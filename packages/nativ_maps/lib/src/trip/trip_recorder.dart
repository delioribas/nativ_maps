// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/lat_lng.dart';
import 'package:nativ_maps/src/trip/position_filter.dart';

/// Un periodo en el que el vehículo estuvo parado.
///
/// Es lo que alimenta el cargo por espera de un taxímetro, y lo que responde a
/// «¿por qué me cobraste ocho minutos de espera?» con una hora y un sitio.
@immutable
class StopPeriod {
  /// Crea un periodo de parada.
  const StopPeriod({
    required this.position,
    required this.start,
    required this.end,
  });

  /// Dónde se paró.
  final LatLng position;

  /// Cuándo empezó la parada.
  final DateTime start;

  /// Cuándo se reanudó la marcha.
  final DateTime end;

  /// Cuánto duró.
  Duration get duration => end.difference(start);

  @override
  String toString() => 'StopPeriod(${duration.inSeconds} s en $position)';
}

/// El estado del viaje después de procesar una lectura.
@immutable
class TripUpdate {
  /// Crea una actualización.
  const TripUpdate({
    required this.filter,
    required this.distanceMeters,
    required this.duration,
    required this.movingDuration,
    required this.stoppedDuration,
    required this.stopped,
    required this.speedKmh,
  });

  /// Qué hizo el filtro con la lectura.
  final FilterResult filter;

  /// Distancia acumulada del viaje, en metros.
  final double distanceMeters;

  /// Tiempo total desde la primera lectura.
  final Duration duration;

  /// Tiempo en movimiento.
  final Duration movingDuration;

  /// Tiempo detenido, contando solo las paradas ya confirmadas.
  final Duration stoppedDuration;

  /// ¿Está parado ahora mismo?
  final bool stopped;

  /// La velocidad estimada en este instante, en km/h.
  final double speedKmh;

  @override
  String toString() =>
      'TripUpdate(${(distanceMeters / 1000).toStringAsFixed(2)} km, '
      '${speedKmh.toStringAsFixed(0)} km/h${stopped ? ', parado' : ''})';
}

/// Un viaje terminado, con todo lo necesario para cobrarlo y para defenderlo.
@immutable
class TripSummary {
  /// Crea un resumen.
  const TripSummary({
    required this.start,
    required this.end,
    required this.distanceMeters,
    required this.movingDuration,
    required this.stoppedDuration,
    required this.stops,
    required this.track,
    required this.acceptedFixes,
    required this.rejections,
    required this.maxSpeedKmh,
  });

  /// Hora de la primera lectura aceptada.
  final DateTime start;

  /// Hora de la última lectura procesada.
  final DateTime end;

  /// Distancia recorrida, en metros, ya descontado el ruido.
  final double distanceMeters;

  /// Tiempo en movimiento.
  final Duration movingDuration;

  /// Tiempo detenido en paradas confirmadas.
  final Duration stoppedDuration;

  /// Las paradas, en orden.
  final List<StopPeriod> stops;

  /// El recorrido, solo con las posiciones que pasaron el filtro.
  ///
  /// Está vacío si el registrador se creó con `keepTrack: false`.
  final List<LatLng> track;

  /// Cuántas lecturas se aceptaron.
  final int acceptedFixes;

  /// Cuántas se descartaron, por motivo.
  ///
  /// Una proporción alta de [FixRejection.poorAccuracy] señala un rastreador
  /// con la antena mal puesta; una de [FixRejection.outOfOrder], un problema
  /// de reenvío por cobertura.
  final Map<FixRejection, int> rejections;

  /// La velocidad punta observada, en km/h.
  final double maxSpeedKmh;

  /// Duración total del viaje.
  Duration get duration => end.difference(start);

  /// Distancia en kilómetros.
  double get distanceKm => distanceMeters / 1000;

  /// Velocidad media contando solo el tiempo en movimiento, en km/h.
  ///
  /// Es la que describe cómo se condujo. La media sobre el tiempo total
  /// mezcla la conducción con los semáforos y no significa gran cosa.
  double get averageMovingSpeedKmh {
    final segundos = movingDuration.inMicroseconds / 1e6;
    if (segundos <= 0) return 0;
    return distanceMeters / segundos * 3.6;
  }

  /// Cuántas lecturas se descartaron en total.
  int get rejectedFixes =>
      rejections.values.fold(0, (suma, cuantas) => suma + cuantas);

  @override
  String toString() =>
      'TripSummary(${distanceKm.toStringAsFixed(2)} km en '
      '${duration.inMinutes} min, ${stops.length} parada(s))';
}

/// Convierte un chorro de posiciones de GPS en un viaje medible.
///
/// Junta tres cosas que en la práctica no se pueden separar: el filtrado del
/// ruido, la suma de la distancia y la detección de paradas.
///
/// ```dart
/// final registrador = TripRecorder();
/// for (final lectura in flujoDelGps) {
///   final estado = registrador.add(lectura);
///   mostrar(estado.distanceMeters, estado.speedKmh);
/// }
/// final viaje = registrador.finish();
/// ```
///
/// ## Lo que casi todo el mundo hace mal
///
/// Cuando el vehículo está parado, el filtro **descarta** casi todas las
/// lecturas por ruido. Si el registrador ignorase los descartes, el reloj se
/// quedaría congelado durante las paradas: un taxi esperando media hora
/// aparecería como un viaje de dos minutos.
///
/// Aquí un descarte por [FixRejection.withinNoise] no es un dato perdido, es
/// **la prueba de que el vehículo no se ha movido**. El tiempo avanza con
/// todas las lecturas; solo la distancia depende de que se acepten.
///
/// ## Histéresis en la detección de paradas
///
/// Con un solo umbral, un coche oscilando alrededor de él entra y sale de
/// «parado» varias veces por minuto y genera decenas de paradas de dos
/// segundos. Por eso hay dos umbrales, [stopSpeedKmh] para entrar y
/// [resumeSpeedKmh] para salir, y una duración mínima antes de dar la parada
/// por buena.
class TripRecorder {
  /// Crea un registrador.
  ///
  /// Los valores por defecto sirven para un taxi urbano: se considera parado
  /// por debajo de 3 km/h, en marcha por encima de 8, y una parada cuenta a
  /// partir de 45 segundos, que deja fuera los semáforos cortos.
  TripRecorder({
    PositionFilter? filter,
    this.stopSpeedKmh = 3,
    this.resumeSpeedKmh = 8,
    this.minStopDuration = const Duration(seconds: 45),
    this.keepTrack = true,
  }) : filter = filter ?? PositionFilter() {
    if (resumeSpeedKmh <= stopSpeedKmh) {
      throw ArgumentError.value(
        resumeSpeedKmh,
        'resumeSpeedKmh',
        'Tiene que ser mayor que stopSpeedKmh, o no hay histéresis y el '
            'vehículo entra y sale de «parado» constantemente',
      );
    }
  }

  /// El filtro que decide qué lecturas cuentan.
  final PositionFilter filter;

  /// Por debajo de esta velocidad se considera detenido, en km/h.
  final double stopSpeedKmh;

  /// Por encima de esta velocidad se considera en marcha, en km/h.
  final double resumeSpeedKmh;

  /// Cuánto tiene que durar una detención para contar como parada.
  final Duration minStopDuration;

  /// ¿Se guarda el recorrido completo?
  ///
  /// Ponerlo a `false` ahorra memoria en un servidor que procesa flotas
  /// enteras y solo necesita los totales.
  final bool keepTrack;

  final List<LatLng> _track = <LatLng>[];
  final List<StopPeriod> _stops = <StopPeriod>[];
  final Map<FixRejection, int> _rejections = <FixRejection, int>{};

  DateTime? _start;
  DateTime? _lastTime;
  double _distance = 0;
  double _maxSpeed = 0;
  int _accepted = 0;

  DateTime? _stopCandidate;
  LatLng? _stopPosition;
  bool _stopConfirmed = false;
  Duration _stopped = Duration.zero;

  /// Distancia acumulada, en metros.
  double get distanceMeters => _distance;

  /// Las paradas confirmadas hasta ahora.
  List<StopPeriod> get stops => List<StopPeriod>.unmodifiable(_stops);

  /// ¿Está parado ahora mismo?
  bool get isStopped => _stopConfirmed;

  /// Procesa una lectura y devuelve el estado del viaje.
  TripUpdate add(PositionFix fix) {
    final resultado = filter.add(fix);
    if (resultado.rejection == FixRejection.outOfOrder) {
      // Una lectura vieja no puede mover el reloj hacia atrás.
      _rejections.update(
        FixRejection.outOfOrder,
        (n) => n + 1,
        ifAbsent: () => 1,
      );
      return _estado(resultado, 0);
    }

    _start ??= fix.timestamp;
    final anterior = _lastTime;
    _lastTime = fix.timestamp;

    final velocidad = _velocidad(fix, resultado);
    if (velocidad > _maxSpeed) _maxSpeed = velocidad;

    if (resultado.accepted) {
      _accepted++;
      _distance += resultado.distanceMeters;
      if (keepTrack) _track.add(resultado.fix.position);
    } else {
      _rejections.update(resultado.rejection!, (n) => n + 1, ifAbsent: () => 1);
    }

    _actualizarParadas(fix, velocidad, anterior);
    return _estado(resultado, velocidad);
  }

  /// La velocidad que se usa para decidir si está parado.
  ///
  /// Se prefiere la del receptor —viene del Doppler y es más fiable—; si no
  /// está, se calcula. Un descarte por ruido significa cero: es exactamente
  /// lo que el filtro acaba de determinar.
  double _velocidad(PositionFix fix, FilterResult resultado) {
    if (resultado.rejection == FixRejection.withinNoise) return 0;
    final declarada = fix.speedKmh;
    if (declarada != null) return math.max(0, declarada);
    return resultado.impliedSpeedKmh ?? 0;
  }

  void _actualizarParadas(
    PositionFix fix,
    double velocidad,
    DateTime? anterior,
  ) {
    if (velocidad <= stopSpeedKmh) {
      // La parada empezó en la lectura anterior, no en esta: cuando se detecta
      // ya llevaba parado todo el intervalo.
      _stopCandidate ??= anterior ?? fix.timestamp;
      _stopPosition ??= fix.position;
      if (!_stopConfirmed &&
          fix.timestamp.difference(_stopCandidate!) >= minStopDuration) {
        _stopConfirmed = true;
      }
      return;
    }

    if (velocidad >= resumeSpeedKmh) {
      if (_stopConfirmed && _stopCandidate != null) {
        final parada = StopPeriod(
          position: _stopPosition ?? fix.position,
          start: _stopCandidate!,
          end: anterior ?? fix.timestamp,
        );
        if (parada.duration > Duration.zero) {
          _stops.add(parada);
          _stopped += parada.duration;
        }
      }
      _stopCandidate = null;
      _stopPosition = null;
      _stopConfirmed = false;
    }
    // Entre los dos umbrales no se cambia de estado: esa banda es la
    // histéresis, y es lo que evita cien paradas de dos segundos.
  }

  TripUpdate _estado(FilterResult resultado, double velocidad) {
    final total = _start == null || _lastTime == null
        ? Duration.zero
        : _lastTime!.difference(_start!);
    final parado = _stopped + _paradaEnCurso();
    return TripUpdate(
      filter: resultado,
      distanceMeters: _distance,
      duration: total,
      movingDuration: total - parado < Duration.zero
          ? Duration.zero
          : total - parado,
      stoppedDuration: parado,
      stopped: _stopConfirmed,
      speedKmh: velocidad,
    );
  }

  Duration _paradaEnCurso() {
    if (!_stopConfirmed || _stopCandidate == null || _lastTime == null) {
      return Duration.zero;
    }
    return _lastTime!.difference(_stopCandidate!);
  }

  /// Cierra el viaje y devuelve el resumen.
  ///
  /// Si el vehículo terminó parado, esa parada se cierra aquí: sin esto, un
  /// taxi que acaba el trayecto esperando a que el pasajero pague perdería
  /// esos minutos de espera.
  TripSummary finish() {
    // `_stopPosition` se pone a la vez que `_stopConfirmed`, así que aquí no
    // puede faltar. Se comprueba igual: la alternativa sería inventar un
    // `LatLng(0, 0)` —el Golfo de Guinea— y este paquete no hace eso en
    // ningún sitio.
    final posicionFinal = _stopPosition ?? filter.last?.position;
    if (_stopConfirmed &&
        _stopCandidate != null &&
        _lastTime != null &&
        posicionFinal != null) {
      final parada = StopPeriod(
        position: posicionFinal,
        start: _stopCandidate!,
        end: _lastTime!,
      );
      if (parada.duration > Duration.zero) {
        _stops.add(parada);
        _stopped += parada.duration;
      }
      _stopConfirmed = false;
      _stopCandidate = null;
    }

    final inicio = _start ?? DateTime.fromMillisecondsSinceEpoch(0);
    final fin = _lastTime ?? inicio;
    final total = fin.difference(inicio);

    return TripSummary(
      start: inicio,
      end: fin,
      distanceMeters: _distance,
      movingDuration: total - _stopped < Duration.zero
          ? Duration.zero
          : total - _stopped,
      stoppedDuration: _stopped,
      stops: List<StopPeriod>.unmodifiable(_stops),
      track: List<LatLng>.unmodifiable(_track),
      acceptedFixes: _accepted,
      rejections: Map<FixRejection, int>.unmodifiable(_rejections),
      maxSpeedKmh: _maxSpeed,
    );
  }

  /// Vuelve al estado inicial para empezar otro viaje.
  void reset() {
    filter.reset();
    _track.clear();
    _stops.clear();
    _rejections.clear();
    _start = null;
    _lastTime = null;
    _distance = 0;
    _maxSpeed = 0;
    _accepted = 0;
    _stopCandidate = null;
    _stopPosition = null;
    _stopConfirmed = false;
    _stopped = Duration.zero;
  }
}
