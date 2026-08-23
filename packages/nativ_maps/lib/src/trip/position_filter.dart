// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/lat_lng.dart';

/// Una lectura cruda del GPS, tal y como la entrega el dispositivo.
///
/// Es el tipo de entrada de toda esta capa. Se construye desde lo que dé el
/// sistema —`Geolocator` en Flutter, una trama de un GT06, una fila de una
/// base de datos— y desde ahí ya no hace falta convertir nada más.
@immutable
class PositionFix {
  /// Crea una lectura.
  const PositionFix({
    required this.position,
    required this.timestamp,
    this.accuracyMeters,
    this.speedKmh,
    this.headingDegrees,
    this.altitudeMeters,
  });

  /// Dónde dice el receptor que está.
  final LatLng position;

  /// Cuándo se tomó la muestra.
  ///
  /// **La hora del receptor, no la de recepción.** En un rastreador que manda
  /// por GPRS las dos se separan minutos cuando hay cobertura mala, y usar la
  /// de recepción convierte un atasco en un teletransporte.
  final DateTime timestamp;

  /// El radio de incertidumbre declarado, en metros.
  ///
  /// Es el dato más valioso de toda la lectura y el que casi nadie usa. Sin
  /// él no hay forma de distinguir un coche que avanza despacio de un coche
  /// parado cuyo GPS está rebotando entre edificios.
  final double? accuracyMeters;

  /// La velocidad medida por el receptor, en km/h.
  ///
  /// Viene del desplazamiento Doppler de la portadora, no de dividir espacio
  /// entre tiempo, así que es **más fiable que la velocidad calculada** entre
  /// dos posiciones consecutivas. Cuando está, se prefiere.
  final double? speedKmh;

  /// El rumbo en grados desde el norte, entre 0 y 360.
  final double? headingDegrees;

  /// La altitud sobre el elipsoide, en metros.
  final double? altitudeMeters;

  /// Una copia con algunos campos cambiados.
  PositionFix copyWith({
    LatLng? position,
    DateTime? timestamp,
    double? accuracyMeters,
    double? speedKmh,
    double? headingDegrees,
    double? altitudeMeters,
  }) => PositionFix(
    position: position ?? this.position,
    timestamp: timestamp ?? this.timestamp,
    accuracyMeters: accuracyMeters ?? this.accuracyMeters,
    speedKmh: speedKmh ?? this.speedKmh,
    headingDegrees: headingDegrees ?? this.headingDegrees,
    altitudeMeters: altitudeMeters ?? this.altitudeMeters,
  );

  @override
  String toString() =>
      'PositionFix($position, ${timestamp.toIso8601String()}, '
      '±${accuracyMeters?.round()} m)';
}

/// Por qué se descartó una lectura.
///
/// Se expone entera a propósito: quien cobra por kilómetro tiene que poder
/// justificar **por qué** una posición no contó, y un contador de descartes
/// por motivo es la mejor señal de que un rastreador va mal.
enum FixRejection {
  /// La incertidumbre declarada supera el máximo aceptado.
  poorAccuracy,

  /// La marca de tiempo es anterior o igual a la de la última aceptada.
  ///
  /// Pasa constantemente con lotes reenviados tras una pérdida de cobertura.
  outOfOrder,

  /// El desplazamiento no supera el ruido del propio receptor.
  ///
  /// **Este es el que evita cobrar de más.** Un móvil parado en una calle
  /// estrecha declara ±30 m y salta 20 m cada segundo. Sumar esos saltos son
  /// 72 km/h de vehículo aparcado.
  withinNoise,

  /// La velocidad implícita entre las dos lecturas es imposible.
  ///
  /// Un solo satélite reflejado en una fachada coloca la posición a un
  /// kilómetro durante una muestra.
  impossibleSpeed,
}

/// El resultado de pasar una lectura por el filtro.
@immutable
class FilterResult {
  /// Crea un resultado aceptado.
  const FilterResult.accepted({
    required PositionFix fix,
    required this.distanceMeters,
    required this.elapsed,
  }) : _fix = fix,
       rejection = null;

  /// Crea un resultado descartado.
  const FilterResult.rejected(FixRejection this.rejection)
    : _fix = null,
      distanceMeters = 0,
      elapsed = Duration.zero;

  final PositionFix? _fix;

  /// El motivo del descarte, o `null` si se aceptó.
  final FixRejection? rejection;

  /// Lo que avanzó respecto a la última lectura aceptada, en metros.
  final double distanceMeters;

  /// El tiempo transcurrido desde la última lectura aceptada.
  final Duration elapsed;

  /// ¿Se aceptó?
  bool get accepted => _fix != null;

  /// La lectura aceptada, ya suavizada si el filtro lo tenía activado.
  ///
  /// Lanza [StateError] si se consulta en un resultado descartado; comprueba
  /// antes con [accepted].
  PositionFix get fix {
    final value = _fix;
    if (value == null) {
      throw StateError(
        'The fix was rejected as $rejection: there is no position to read',
      );
    }
    return value;
  }

  /// La velocidad implícita entre las dos lecturas, en km/h.
  ///
  /// Devuelve `null` si no hay tiempo transcurrido con el que dividir.
  double? get impliedSpeedKmh {
    final seconds = elapsed.inMicroseconds / 1e6;
    if (seconds <= 0) return null;
    return distanceMeters / seconds * 3.6;
  }

  @override
  String toString() => accepted
      ? 'FilterResult(aceptada, +${distanceMeters.toStringAsFixed(1)} m)'
      : 'FilterResult(descartada: ${rejection!.name})';
}

/// Descarta las lecturas de GPS que no representan movimiento real.
///
/// ## El problema que resuelve
///
/// Sumar la distancia entre posiciones consecutivas es la forma obvia de medir
/// un viaje, y está mal. Un receptor parado no repite la misma coordenada:
/// rebota dentro de su círculo de incertidumbre. En un cañón urbano ese
/// círculo son 30 m y el rebote ocurre cada segundo.
///
/// Un taxi esperando veinte minutos frente a un hotel acumula así varios
/// kilómetros que nadie recorrió, y el pasajero los paga.
///
/// ## Las cuatro comprobaciones, en orden
///
/// | Comprobación | Descarta | Ajuste |
/// |---|---|---|
/// | Incertidumbre declarada | lecturas de mala calidad | [maxAccuracyMeters] |
/// | Orden temporal | lotes reenviados y duplicados | — |
/// | Umbral de ruido | el rebote del receptor parado | [noiseFactor] |
/// | Velocidad implícita | los saltos por señal reflejada | [maxSpeedKmh] |
///
/// ## Suavizado
///
/// Con [smooth] activado se aplica además un filtro de Kalman de **velocidad
/// constante**: el estado no es solo la posición, también la velocidad en
/// cada eje.
///
/// Esa distinción no es un detalle académico. Un Kalman que solo estima
/// posición no tiene forma de saber que el vehículo se mueve, así que cada
/// predicción supone que sigue donde estaba y la corrección solo avanza una
/// fracción de lo medido. El resultado va **sistemáticamente por detrás**: a
/// 54 km/h el retraso pasa de los noventa metros, y el punto azul se arrastra
/// una manzana entera por detrás del coche. Con el estado de velocidad, la
/// predicción ya incorpora el avance y el filtro alisa sin retrasar.
///
/// **El suavizado no sustituye al descarte.** Un Kalman alimentado con rebote
/// devuelve un rebote más suave, y la suma sigue inflada.
class PositionFilter {
  /// Crea un filtro.
  ///
  /// Los valores por defecto están pensados para un móvil en ciudad. Para un
  /// rastreador dedicado con antena externa se puede bajar
  /// [maxAccuracyMeters] a 20 y [noiseFactor] a 1.
  PositionFilter({
    this.maxAccuracyMeters = 50,
    this.noiseFactor = 2.0,
    this.minDisplacementMeters = 3,
    this.maxSpeedKmh = 220,
    this.smooth = false,
    this.processNoiseMps2 = 2.0,
  }) {
    if (noiseFactor < 0) {
      throw ArgumentError.value(
        noiseFactor,
        'noiseFactor',
        'Cannot be negative',
      );
    }
  }

  /// Incertidumbre máxima aceptada, en metros.
  ///
  /// Una lectura que declara ±120 m no sirve ni para cobrar ni para pintar.
  final double maxAccuracyMeters;

  /// Cuántas veces la incertidumbre tiene que superar el desplazamiento.
  ///
  /// Con `2.0` y una lectura de ±10 m hace falta avanzar más de 20 m para que
  /// cuente. Subirlo descarta movimiento lento real —un taxi en un atasco—;
  /// bajarlo deja pasar rebote. `2.0` es el equilibrio habitual.
  final double noiseFactor;

  /// Suelo absoluto de desplazamiento, en metros.
  ///
  /// Se aplica cuando la lectura **no declara** incertidumbre, que es el caso
  /// de muchos rastreadores baratos: sin ese dato, [noiseFactor] no tiene
  /// sobre qué operar y este es el único freno que queda.
  final double minDisplacementMeters;

  /// Velocidad implícita máxima, en km/h.
  final double maxSpeedKmh;

  /// ¿Se suaviza la posición con un filtro de Kalman?
  final bool smooth;

  /// Ruido de proceso del Kalman, en metros por segundo al cuadrado.
  ///
  /// Es cuánta aceleración se considera plausible entre dos medidas. Más alto
  /// sigue mejor los arranques y frenazos y suaviza menos; más bajo alisa más
  /// y tarda más en reaccionar. Para tráfico urbano, entre 1 y 3.
  final double processNoiseMps2;

  PositionFix? _last;
  DateTime? _lastSmoothedAt;
  double _originLat = 0;
  double _originLon = 0;
  double _cosOrigin = 1;
  _Axis? _east;
  _Axis? _north;

  /// La última lectura aceptada, o `null` si todavía no hubo ninguna.
  PositionFix? get last => _last;

  /// Vuelve al estado inicial.
  ///
  /// Hay que llamarlo entre viajes: si no, el primer punto de la carrera nueva
  /// se compara con el último de la anterior y la distancia entre las dos se
  /// cuela como si fuera recorrido.
  void reset() {
    _last = null;
    _lastSmoothedAt = null;
    _east = null;
    _north = null;
  }

  /// Pasa una lectura por el filtro.
  FilterResult add(PositionFix fix) {
    final accuracy = fix.accuracyMeters;
    if (accuracy != null && accuracy > maxAccuracyMeters) {
      return const FilterResult.rejected(FixRejection.poorAccuracy);
    }

    final previous = _last;
    if (previous == null) {
      _last = smooth ? _applySmoothing(fix) : fix;
      return FilterResult.accepted(
        fix: _last!,
        distanceMeters: 0,
        elapsed: Duration.zero,
      );
    }

    if (!fix.timestamp.isAfter(previous.timestamp)) {
      return const FilterResult.rejected(FixRejection.outOfOrder);
    }

    final elapsed = fix.timestamp.difference(previous.timestamp);
    final advance = previous.position.distanceTo(fix.position);

    // El umbral de ruido: el mayor entre el suelo absoluto y lo que dicta la
    // incertidumbre declarada de las dos lecturas.
    final uncertainty = math.max(accuracy ?? 0, previous.accuracyMeters ?? 0);
    final threshold = math.max(
      minDisplacementMeters,
      uncertainty * noiseFactor,
    );
    if (advance < threshold) {
      return const FilterResult.rejected(FixRejection.withinNoise);
    }

    final seconds = elapsed.inMicroseconds / 1e6;
    if (seconds > 0 && advance / seconds * 3.6 > maxSpeedKmh) {
      return const FilterResult.rejected(FixRejection.impossibleSpeed);
    }

    final accepted = smooth ? _applySmoothing(fix) : fix;
    // La distancia se mide sobre la posición que se guarda, no sobre la cruda:
    // si no, la suma de avances y el camino dibujado dejan de coincidir.
    final actualAdvance = previous.position.distanceTo(accepted.position);
    _last = accepted;
    return FilterResult.accepted(
      fix: accepted,
      distanceMeters: actualAdvance,
      elapsed: elapsed,
    );
  }

  /// Filtro de Kalman de velocidad constante, un eje por coordenada.
  ///
  /// Se trabaja en **metros sobre un plano local**, no en grados: un grado de
  /// longitud mide 111 km en el ecuador y 55 en Madrid, así que un filtro que
  /// opera sobre grados aplica sin querer un suavizado distinto en cada eje y
  /// distinto en cada latitud.
  ///
  /// Los dos ejes se filtran por separado. Es la aproximación estándar en
  /// seguimiento de vehículos: el acoplamiento real entre ellos es pequeño y
  /// un filtro de cuatro estados acoplado no mejora lo suficiente como para
  /// justificar la inversión de una matriz en cada lectura.
  PositionFix _applySmoothing(PositionFix fix) {
    final accuracy = fix.accuracyMeters ?? maxAccuracyMeters;
    final measurementVariance = accuracy * accuracy;

    if (_east == null || _north == null) {
      _originLat = fix.position.latitude;
      _originLon = fix.position.longitude;
      _cosOrigin = math.cos(_originLat * math.pi / 180.0);
      _east = _Axis(0, measurementVariance);
      _north = _Axis(0, measurementVariance);
      _lastSmoothedAt = fix.timestamp;
      return fix;
    }

    final previous = _lastSmoothedAt ?? fix.timestamp;
    final dt = fix.timestamp.difference(previous).inMicroseconds / 1e6;
    _lastSmoothedAt = fix.timestamp;

    final (x, y) = _project(fix.position);
    final q = processNoiseMps2 * processNoiseMps2;

    _east!
      ..predict(dt, q)
      ..correct(x, measurementVariance);
    _north!
      ..predict(dt, q)
      ..correct(y, measurementVariance);

    return fix.copyWith(
      position: _unproject(_east!.position, _north!.position),
    );
  }

  (double, double) _project(LatLng point) {
    final dLat = (point.latitude - _originLat) * math.pi / 180.0;
    final dLon = (point.longitude - _originLon) * math.pi / 180.0;
    return (earthRadiusMeters * dLon * _cosOrigin, earthRadiusMeters * dLat);
  }

  LatLng _unproject(double x, double y) => LatLng(
    _originLat + y / earthRadiusMeters * 180.0 / math.pi,
    _originLon + x / (earthRadiusMeters * _cosOrigin) * 180.0 / math.pi,
  );
}

/// Un eje del filtro de Kalman: posición y velocidad.
class _Axis {
  _Axis(this.position, double initialVariance)
    : velocity = 0,
      _p00 = initialVariance,
      _p01 = 0,
      // Sin ninguna medida todavía no se sabe nada de la velocidad. Empezar
      // con una varianza grande deja que las primeras lecturas la fijen
      // deprisa, en vez de arrastrar un cero durante medio minuto.
      _p11 = 1e4;

  /// La posición estimada, en metros desde el origen.
  double position;

  /// La velocidad estimada, en metros por segundo.
  double velocity;

  double _p00;
  double _p01;
  double _p11;

  /// Avanza el estado [dt] segundos suponiendo velocidad constante.
  void predict(double dt, double q) {
    if (dt <= 0) return;
    position += velocity * dt;

    // P = F·P·Fᵀ + Q, con Q el modelo de ruido blanco en la aceleración.
    final dt2 = dt * dt;
    final dt3 = dt2 * dt;
    final dt4 = dt2 * dt2;
    _p00 += dt * (2 * _p01 + dt * _p11) + q * dt4 / 4;
    _p01 += dt * _p11 + q * dt3 / 2;
    _p11 += q * dt2;
  }

  /// Corrige el estado con una medida de posición de varianza [r].
  void correct(double measurement, double r) {
    final s = _p00 + r;
    if (s <= 0) return;
    final k0 = _p00 / s;
    final k1 = _p01 / s;
    final innovation = measurement - position;

    position += k0 * innovation;
    velocity += k1 * innovation;

    // El orden importa: `_p11` necesita el `_p01` de antes de actualizarlo.
    final previousP01 = _p01;
    _p00 -= k0 * _p00;
    _p01 -= k0 * _p01;
    _p11 -= k1 * previousP01;
  }
}
