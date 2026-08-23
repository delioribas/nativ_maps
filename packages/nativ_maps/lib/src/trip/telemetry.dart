// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/lat_lng.dart';
import 'package:nativ_maps/src/trip/position_filter.dart';

/// Qué clase de suceso de conducción se detectó.
enum DrivingEventType {
  /// Acelerón.
  harshAcceleration,

  /// Frenazo.
  harshBraking,

  /// Curva tomada deprisa.
  harshCornering,

  /// Circulación por encima del límite.
  speeding,
}

/// Un suceso de conducción, con dónde y cuándo pasó.
@immutable
class DrivingEvent {
  /// Crea un suceso.
  const DrivingEvent({
    required this.type,
    required this.timestamp,
    required this.position,
    required this.magnitude,
    required this.speedKmh,
  });

  /// Qué clase de suceso es.
  final DrivingEventType type;

  /// Cuándo ocurrió.
  final DateTime timestamp;

  /// Dónde ocurrió.
  final LatLng position;

  /// Cuánto: metros por segundo al cuadrado, o km/h de exceso.
  ///
  /// Para las tres primeras clases es aceleración; para
  /// [DrivingEventType.speeding] es cuánto se pasó del límite.
  final double magnitude;

  /// La velocidad en ese momento, en km/h.
  final double speedKmh;

  /// La magnitud en unidades de gravedad, para las de aceleración.
  ///
  /// Un frenazo de emergencia ronda los 0,6 g. Un frenazo brusco pero normal
  /// se queda en 0,35 g.
  double get gForce => magnitude.abs() / 9.80665;

  @override
  String toString() =>
      'DrivingEvent(${type.name}, ${magnitude.toStringAsFixed(1)}, '
      '${timestamp.toIso8601String()})';
}

/// La nota de conducción de un trayecto o de un conductor.
@immutable
class DrivingScore {
  /// Crea una nota.
  const DrivingScore({
    required this.value,
    required this.distanceKm,
    required this.counts,
  });

  /// La nota, de 0 a 100.
  final int value;

  /// Sobre cuántos kilómetros se calculó.
  final double distanceKm;

  /// Cuántos sucesos de cada clase.
  final Map<DrivingEventType, int> counts;

  /// Cuántos sucesos hubo en total.
  int get eventCount => counts.values.fold(0, (sum, howMany) => sum + howMany);

  /// Sucesos por cada cien kilómetros.
  ///
  /// **Es la única cifra comparable entre conductores.** El total absoluto
  /// solo dice quién conduce más horas.
  double get eventsPer100Km =>
      distanceKm <= 0 ? 0 : eventCount / distanceKm * 100;

  @override
  String toString() =>
      'DrivingScore($value/100, $eventCount events over '
      '${distanceKm.toStringAsFixed(1)} km)';
}

/// Detecta acelerones, frenazos, curvas bruscas y excesos de velocidad.
///
/// ```dart
/// final analizador = TelemetryAnalyzer(speedLimitKmh: 50);
/// for (final lectura in flujoDelGps) {
///   for (final suceso in analizador.add(lectura)) {
///     avisar(suceso);
///   }
/// }
/// print(analizador.score());
/// ```
///
/// ## Por qué no vale derivar la velocidad de las posiciones
///
/// Calcular la aceleración como `Δposición / Δt²` amplifica el ruido del GPS
/// al cuadrado: un rebote de 15 m entre dos lecturas de un segundo aparece
/// como 30 m/s², tres veces la gravedad, y el analizador detecta frenazos en
/// un coche parado.
///
/// Por eso se exige la **velocidad declarada por el receptor** —la del efecto
/// Doppler, que es independiente de la posición— y las lecturas que no la
/// traen no generan sucesos de aceleración. Es preferible perder detecciones a
/// inventarlas: un informe lleno de frenazos falsos deja de leerse a la
/// primera semana.
///
/// ## Los umbrales
///
/// | Suceso | Por defecto | Referencia |
/// |---|---|---|
/// | Acelerón | 3,0 m/s² | 0,31 g |
/// | Frenazo | −3,5 m/s² | 0,36 g |
/// | Curva | 3,5 m/s² lateral | pasajero desplazado |
/// | Exceso | límite + 8 km/h | margen del velocímetro |
class TelemetryAnalyzer {
  /// Crea un analizador.
  TelemetryAnalyzer({
    this.harshAccelerationMps2 = 3.0,
    this.harshBrakingMps2 = -3.5,
    this.harshCorneringMps2 = 3.5,
    this.speedLimitKmh,
    this.speedToleranceKmh = 8,
    this.minSpeedingDuration = const Duration(seconds: 10),
    this.maxSampleGap = const Duration(seconds: 10),
  });

  /// A partir de cuánto es un acelerón, en m/s².
  final double harshAccelerationMps2;

  /// A partir de cuánto es un frenazo, en m/s². Es negativo.
  final double harshBrakingMps2;

  /// A partir de cuánta aceleración lateral es una curva brusca, en m/s².
  final double harshCorneringMps2;

  /// El límite de velocidad de la vía, en km/h, si se conoce.
  ///
  /// El paquete **no** lo averigua: Amazon Location no publica los límites por
  /// tramo. Sale de la cartografía propia, de un fichero de zonas o de la
  /// política de la flota.
  final double? speedLimitKmh;

  /// Cuánto se tolera por encima del límite antes de contar exceso.
  final double speedToleranceKmh;

  /// Cuánto tiene que durar el exceso para generar un solo suceso.
  ///
  /// Sin esto, un minuto a 60 en una vía de 50 genera sesenta sucesos.
  final Duration minSpeedingDuration;

  /// Separación máxima entre lecturas para poder derivar aceleración.
  ///
  /// Con un hueco de dos minutos, la diferencia de velocidades no describe
  /// ninguna maniobra concreta.
  final Duration maxSampleGap;

  final List<DrivingEvent> _events = <DrivingEvent>[];
  PositionFix? _previous;
  double _distanceMeters = 0;
  DateTime? _speedingSince;
  double _speedingPeak = 0;

  /// Todos los sucesos detectados, en orden.
  List<DrivingEvent> get events => List<DrivingEvent>.unmodifiable(_events);

  /// Procesa una lectura y devuelve los sucesos que provocó.
  ///
  /// Los sucesos se registran **en un solo sitio**, al final: repartir el
  /// `add` entre varios caminos de salida es cómo se acaba contando un exceso
  /// de velocidad dos veces.
  List<DrivingEvent> add(PositionFix fix) {
    final produced = <DrivingEvent>[];
    final previous = _previous;
    _previous = fix;

    if (previous != null) {
      _distanceMeters += previous.position.distanceTo(fix.position);
    }

    // Sin velocidad del receptor no se evalúa nada: ver la nota de la clase.
    final speed = fix.speedKmh;
    if (speed != null) {
      final speeding = _closeSpeedingEpisode(fix, speed);
      if (speeding != null) produced.add(speeding);

      final previousSpeed = previous?.speedKmh;
      final gap = previous == null
          ? Duration.zero
          : fix.timestamp.difference(previous.timestamp);

      if (previous != null &&
          previousSpeed != null &&
          gap > Duration.zero &&
          gap <= maxSampleGap) {
        final seconds = gap.inMicroseconds / 1e6;

        // ── Aceleración longitudinal
        final acceleration = (speed - previousSpeed) / 3.6 / seconds;
        if (acceleration >= harshAccelerationMps2) {
          produced.add(
            _event(
              DrivingEventType.harshAcceleration,
              fix,
              acceleration,
              speed,
            ),
          );
        } else if (acceleration <= harshBrakingMps2) {
          produced.add(
            _event(DrivingEventType.harshBraking, fix, acceleration, speed),
          );
        }

        // ── Aceleración lateral: velocidad por velocidad angular
        final heading = fix.headingDegrees;
        final previousHeading = previous.headingDegrees;
        if (heading != null && previousHeading != null) {
          final turn = _headingDelta(previousHeading, heading);
          final omega = turn * math.pi / 180 / seconds;
          final lateral = (speed / 3.6) * omega.abs();
          if (lateral >= harshCorneringMps2) {
            produced.add(
              _event(DrivingEventType.harshCornering, fix, lateral, speed),
            );
          }
        }
      }
    }

    _events.addAll(produced);
    return produced;
  }

  /// Cierra un episodio de exceso de velocidad, si acaba de terminar.
  ///
  /// Devuelve el suceso **al bajar** del umbral, no mientras se está por
  /// encima: así un minuto a 70 en una vía de 50 es un suceso y no sesenta.
  DrivingEvent? _closeSpeedingEpisode(PositionFix fix, double speed) {
    final limit = speedLimitKmh;
    if (limit == null) return null;

    if (speed > limit + speedToleranceKmh) {
      _speedingSince ??= fix.timestamp;
      _speedingPeak = math.max(_speedingPeak, speed);
      return null;
    }

    final from = _speedingSince;
    if (from == null) return null;
    final duration = fix.timestamp.difference(from);
    final peak = _speedingPeak;
    _speedingSince = null;
    _speedingPeak = 0;

    if (duration < minSpeedingDuration) return null;
    return DrivingEvent(
      type: DrivingEventType.speeding,
      timestamp: from,
      position: fix.position,
      magnitude: peak - limit,
      speedKmh: peak,
    );
  }

  DrivingEvent _event(
    DrivingEventType kind,
    PositionFix fix,
    double magnitude,
    double speed,
  ) => DrivingEvent(
    type: kind,
    timestamp: fix.timestamp,
    position: fix.position,
    magnitude: magnitude,
    speedKmh: speed,
  );

  /// La diferencia de rumbo más corta entre dos ángulos, con signo.
  ///
  /// Sin esto, pasar de 359° a 1° parece un giro de 358 grados y todo coche
  /// que cruce el norte genera una curva brusca.
  static double _headingDelta(double from, double to) {
    var d = (to - from) % 360;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
  }

  /// Calcula la nota a partir de lo detectado hasta ahora.
  ///
  /// Parte de 100 y descuenta por suceso y por cada cien kilómetros, de forma
  /// que un conductor con mucha ruta no salga penalizado por acumular más
  /// sucesos absolutos. Los pesos por defecto castigan más el frenazo, que es
  /// el que mejor predice el accidente.
  DrivingScore score({
    double harshWeight = 4,
    double corneringWeight = 2,
    double speedingWeight = 6,
  }) {
    final counts = <DrivingEventType, int>{};
    for (final event in _events) {
      counts.update(event.type, (n) => n + 1, ifAbsent: () => 1);
    }

    final km = _distanceMeters / 1000;
    final base = math.max(km, 1.0);
    final penalty =
        ((counts[DrivingEventType.harshAcceleration] ?? 0) * harshWeight +
            (counts[DrivingEventType.harshBraking] ?? 0) * harshWeight +
            (counts[DrivingEventType.harshCornering] ?? 0) * corneringWeight +
            (counts[DrivingEventType.speeding] ?? 0) * speedingWeight) /
        base *
        100;

    return DrivingScore(
      value: (100 - penalty).clamp(0, 100).round(),
      distanceKm: km,
      counts: Map<DrivingEventType, int>.unmodifiable(counts),
    );
  }

  /// Vuelve al estado inicial.
  void reset() {
    _events.clear();
    _previous = null;
    _distanceMeters = 0;
    _speedingSince = null;
    _speedingPeak = 0;
  }
}
