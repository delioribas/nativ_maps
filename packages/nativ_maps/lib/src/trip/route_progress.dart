// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/lat_lng.dart';
import 'package:nativ_maps/src/routes/models.dart';
import 'package:nativ_maps/src/trip/geodesy.dart';

/// Dónde va el vehículo dentro de una ruta calculada.
@immutable
class RouteProgress {
  /// Crea un progreso.
  const RouteProgress({
    required this.match,
    required this.traveledMeters,
    required this.remainingMeters,
    required this.remainingDuration,
    required this.eta,
    required this.offRoute,
    required this.stepIndex,
    required this.currentStep,
    required this.nextStep,
    required this.distanceToNextManeuverMeters,
  });

  /// El punto de la ruta al que se enganchó la posición.
  final PathMatch match;

  /// Cuánta ruta queda por detrás, en metros.
  final double traveledMeters;

  /// Cuánta ruta queda por delante, en metros.
  final double remainingMeters;

  /// Cuánto falta, según los tiempos que dio el servicio por cada maniobra.
  final Duration remainingDuration;

  /// La hora estimada de llegada.
  final DateTime eta;

  /// ¿Está fuera de la ruta?
  ///
  /// No se activa con una sola lectura mala: hace falta que varias seguidas
  /// caigan lejos. Ver `RouteTracker.offRouteStrikes`.
  final bool offRoute;

  /// El índice de la maniobra en curso dentro de `Route.steps`.
  final int stepIndex;

  /// La maniobra en curso, si la ruta trae indicaciones.
  final TravelStep? currentStep;

  /// La maniobra siguiente.
  final TravelStep? nextStep;

  /// Cuántos metros faltan para la maniobra siguiente.
  final double? distanceToNextManeuverMeters;

  /// Cuánta ruta se lleva hecha, entre 0 y 1.
  double get fraction => match.fraction;

  /// A qué distancia de la ruta está el vehículo, en metros.
  double get deviationMeters => match.distanceMeters;

  @override
  String toString() =>
      'RouteProgress(${(fraction * 100).round()} %, faltan '
      '${(remainingMeters / 1000).toStringAsFixed(1)} km / '
      '${remainingDuration.inMinutes} min'
      '${offRoute ? ', FUERA DE RUTA' : ''})';
}

/// Sigue a un vehículo a lo largo de una ruta, **sin gastar peticiones**.
///
/// ```dart
/// final seguimiento = RouteTracker(respuesta.best!);
/// // ...por cada posición del GPS:
/// final progreso = seguimiento.update(posicion);
/// if (progreso.offRoute) await recalcularRuta();
/// ```
///
/// ## Por qué el tiempo restante no es proporcional a la distancia
///
/// La forma fácil de estimar lo que falta es `duración × (1 − fracción)`. Está
/// mal en cuanto la ruta mezcla tipos de vía: si quedan 20 km de los 25, pero
/// esos 20 son autopista y los 5 recorridos eran ciudad, esa cuenta dice el
/// doble de lo que va a tardar.
///
/// Aquí se usa el tiempo que el servicio dio **para cada maniobra**: se
/// consume la parte proporcional de la maniobra en curso y se suman enteras
/// las que quedan. Si la ruta viene sin indicaciones —no se pidió
/// `RouteFeature.travelStepInstructions`— se cae al reparto proporcional, que
/// es lo único que queda.
///
/// ## Por qué hay histéresis en el desvío
///
/// Una sola lectura mala coloca el coche a 80 m de su carril. Recalcular la
/// ruta ahí es una petición facturada tirada, y en una calle con edificios
/// altos ocurre varias veces por minuto. Hacen falta [offRouteStrikes]
/// lecturas seguidas lejos de la ruta para darlo por bueno.
class RouteTracker {
  /// Crea un seguimiento sobre una ruta.
  ///
  /// Lanza [ArgumentError] si la ruta no tiene geometría: sin puntos no hay
  /// nada sobre lo que proyectar.
  RouteTracker(
    this.route, {
    this.offRouteThresholdMeters = 45,
    this.offRouteStrikes = 3,
    this.searchWindowSegments = 60,
  }) : _path = route.points {
    if (_path.length < 2) {
      throw ArgumentError.value(
        route,
        'route',
        'The route carries no geometry: request RouteFeature with geometry, '
            'or use a response that includes it',
      );
    }
    _cumulative = cumulativeDistances(_path);
    _stepEnds = _accumulateSteps();
  }

  /// La ruta que se sigue.
  final Route route;

  /// A partir de cuántos metros se considera que el vehículo se salió.
  ///
  /// 45 m deja pasar el ancho de una avenida con laterales y el error típico
  /// de un móvil en ciudad. Para autopista se puede subir a 80.
  final double offRouteThresholdMeters;

  /// Cuántas lecturas seguidas lejos hacen falta para dar el desvío por bueno.
  final int offRouteStrikes;

  /// Cuántos segmentos se miran por delante del último emparejamiento.
  ///
  /// Evita recorrer una ruta de miles de puntos en cada posición. Si el mejor
  /// resultado dentro de la ventana queda lejos, se repite la búsqueda sobre
  /// la ruta entera: es lo que rescata al vehículo tras un túnel.
  final int searchWindowSegments;

  final List<LatLng> _path;
  late final List<double> _cumulative;
  late final List<double> _stepEnds;

  int _lastSegment = 0;
  int _strikes = 0;
  bool _offRoute = false;

  /// ¿Está fuera de ruta ahora mismo?
  bool get isOffRoute => _offRoute;

  /// La longitud de la geometría de la ruta, en metros.
  double get pathLengthMeters => _cumulative.last;

  /// Vuelve a buscar en toda la ruta en la próxima llamada.
  ///
  /// Hay que llamarlo tras una pausa larga sin posiciones, o al reanudar la
  /// aplicación: la ventana de búsqueda supone continuidad.
  void resync() {
    _lastSegment = 0;
    _strikes = 0;
    _offRoute = false;
  }

  /// Calcula el progreso para una posición.
  RouteProgress update(LatLng position, {DateTime? now}) {
    var match = nearestPointOnPath(
      _path,
      position,
      fromIndex: _lastSegment,
      maxSegments: searchWindowSegments,
      cumulative: _cumulative,
    );

    // Si dentro de la ventana no hay nada cerca, puede ser un desvío de verdad
    // o que el vehículo reapareciese lejos. Se comprueba mirando toda la ruta
    // antes de declarar nada.
    if (match.distanceMeters > offRouteThresholdMeters) {
      final fullScan = nearestPointOnPath(
        _path,
        position,
        cumulative: _cumulative,
      );
      if (fullScan.distanceMeters < match.distanceMeters) {
        match = fullScan;
      }
    }

    _lastSegment = match.segmentIndex;

    if (match.distanceMeters > offRouteThresholdMeters) {
      _strikes++;
      if (_strikes >= offRouteStrikes) _offRoute = true;
    } else {
      _strikes = 0;
      _offRoute = false;
    }

    final metersLeft = math.max(0.0, _cumulative.last - match.alongMeters);
    final timeLeft = _remainingFrom(match.alongMeters);
    final moment = now ?? DateTime.now();

    final (index, current, next, toManeuver) = _maneuversAt(match.alongMeters);

    return RouteProgress(
      match: match,
      traveledMeters: match.alongMeters,
      remainingMeters: metersLeft,
      remainingDuration: timeLeft,
      eta: moment.add(timeLeft),
      offRoute: _offRoute,
      stepIndex: index,
      currentStep: current,
      nextStep: next,
      distanceToNextManeuverMeters: toManeuver,
    );
  }

  /// Distancia acumulada al final de cada maniobra.
  ///
  /// Se escala para que la suma coincida con la longitud real de la
  /// geometría: las dos cifras vienen del servicio y difieren en unos metros
  /// por redondeo, y sin escalar el progreso se descuadra al final.
  List<double> _accumulateSteps() {
    final steps = route.steps;
    if (steps.isEmpty) return const <double>[];
    final total = steps.fold<double>(0, (s, p) => s + p.distanceMeters);
    if (total <= 0) return const <double>[];
    final scale = _cumulative.last / total;
    final ends = <double>[];
    var cumulative = 0.0;
    for (final step in steps) {
      cumulative += step.distanceMeters * scale;
      ends.add(cumulative);
    }
    return ends;
  }

  Duration _remainingFrom(double travelled) {
    final steps = route.steps;
    if (steps.isEmpty || _stepEnds.isEmpty) {
      // Sin indicaciones no queda más que el reparto proporcional.
      final total = _cumulative.last;
      if (total <= 0) return Duration.zero;
      final fraction = 1 - (travelled / total).clamp(0.0, 1.0);
      return Duration(
        microseconds: (route.duration.inMicroseconds * fraction).round(),
      );
    }

    final index = _stepIndexAt(travelled);
    final stepStart = index == 0 ? 0.0 : _stepEnds[index - 1];
    final stepLength = _stepEnds[index] - stepStart;
    final stepDone = stepLength <= 0
        ? 1.0
        : ((travelled - stepStart) / stepLength).clamp(0.0, 1.0);

    var micros = (steps[index].duration.inMicroseconds * (1 - stepDone))
        .round();
    for (var i = index + 1; i < steps.length; i++) {
      micros += steps[i].duration.inMicroseconds;
    }
    return Duration(microseconds: micros);
  }

  int _stepIndexAt(double travelled) {
    var low = 0;
    var high = _stepEnds.length - 1;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (_stepEnds[mid] <= travelled) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  (int, TravelStep?, TravelStep?, double?) _maneuversAt(double travelled) {
    final steps = route.steps;
    if (steps.isEmpty || _stepEnds.isEmpty) {
      return (0, null, null, null);
    }
    final index = _stepIndexAt(travelled);
    final next = index + 1 < steps.length ? steps[index + 1] : null;
    final to = math.max(0.0, _stepEnds[index] - travelled);
    return (index, steps[index], next, to);
  }
}
