// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:nativ_maps/nativ_maps.dart';
import 'package:test/test.dart';

void main() {
  final quito = LatLng(-0.1807, -78.4678);
  final base = DateTime.utc(2026, 8, 23, 10);

  PositionFix fix(
    int segundo, {
    double? speed,
    double? heading,
    double meters = 0,
  }) => PositionFix(
    position: quito.offset(meters, 90),
    timestamp: base.add(Duration(seconds: segundo)),
    accuracyMeters: 5,
    speedKmh: speed,
    headingDegrees: heading,
  );

  group('aceleración', () {
    test('detecta un frenazo', () {
      final analyzer = TelemetryAnalyzer()..add(fix(0, speed: 80));
      // De 80 a 40 km/h en dos segundos son −5,6 m/s².
      final events = analyzer.add(fix(2, speed: 40, meters: 30));

      expect(events, hasLength(1));
      expect(events.single.type, DrivingEventType.harshBraking);
      expect(events.single.magnitude, closeTo(-5.56, 0.1));
      expect(events.single.gForce, closeTo(0.57, 0.05));
    });

    test('detecta un acelerón', () {
      final analyzer = TelemetryAnalyzer()..add(fix(0, speed: 0));
      final events = analyzer.add(fix(2, speed: 45, meters: 12));
      expect(events.single.type, DrivingEventType.harshAcceleration);
    });

    test('una conducción suave no genera nada', () {
      final analyzer = TelemetryAnalyzer();
      for (var i = 0; i <= 20; i++) {
        analyzer.add(fix(i, speed: 40 + i.toDouble(), meters: 11.0 * i));
      }
      expect(analyzer.events, isEmpty);
    });

    test('sin velocidad del receptor no se inventa ninguna', () {
      // Derivar la aceleración de las posiciones amplifica el ruido del GPS
      // al cuadrado y produce frenazos en un coche parado. Es preferible no
      // detectar a detectar mentiras.
      final analyzer = TelemetryAnalyzer()
        ..add(fix(0))
        ..add(fix(1, meters: 500));
      expect(analyzer.events, isEmpty);
    });

    test('un hueco largo entre lecturas no describe ninguna maniobra', () {
      final analyzer = TelemetryAnalyzer(
        maxSampleGap: const Duration(seconds: 10),
      )..add(fix(0, speed: 100));
      final events = analyzer.add(fix(600, speed: 0));
      expect(events, isEmpty);
    });
  });

  group('curvas', () {
    test('detecta una curva tomada deprisa', () {
      // 90° en dos segundos a 40 km/h son 8,7 m/s² laterales.
      final analyzer = TelemetryAnalyzer()..add(fix(0, speed: 40, heading: 0));
      final events = analyzer.add(fix(2, speed: 40, heading: 90, meters: 22));
      expect(
        events.map((s) => s.type),
        contains(DrivingEventType.harshCornering),
      );
    });

    test('cruzar el norte no es una curva de 358 grados', () {
      // Sin normalizar la diferencia de rumbo, todo coche que pase de 359° a
      // 1° generaría una curva brusca.
      final analyzer = TelemetryAnalyzer()
        ..add(fix(0, speed: 50, heading: 359));
      final events = analyzer.add(fix(1, speed: 50, heading: 1, meters: 14));
      expect(events, isEmpty);
    });
  });

  group('exceso de velocidad', () {
    test('un exceso largo es un suceso, no cien', () {
      final analyzer = TelemetryAnalyzer(
        speedLimitKmh: 50,
        minSpeedingDuration: const Duration(seconds: 10),
      );
      // Treinta segundos a 70 en una vía de 50.
      for (var i = 0; i <= 30; i++) {
        analyzer.add(fix(i, speed: 70, meters: 19.4 * i));
      }
      // Y luego baja.
      analyzer.add(fix(31, speed: 45, meters: 600));

      final speedingEvents = analyzer.events
          .where((s) => s.type == DrivingEventType.speeding)
          .toList();
      expect(speedingEvents, hasLength(1));
      expect(speedingEvents.single.magnitude, closeTo(20, 0.1));
    });

    test('un adelantamiento corto no cuenta', () {
      final analyzer = TelemetryAnalyzer(
        speedLimitKmh: 50,
        minSpeedingDuration: const Duration(seconds: 10),
      );
      for (var i = 0; i <= 4; i++) {
        analyzer.add(fix(i, speed: 70, meters: 19.4 * i));
      }
      // Al bajar de 70 a 45 hay un frenazo de verdad; lo que se comprueba
      // aquí es que NO se registra un exceso de velocidad.
      analyzer.add(fix(5, speed: 45, meters: 100));
      expect(
        analyzer.events.where((s) => s.type == DrivingEventType.speeding),
        isEmpty,
      );
    });

    test('la tolerancia deja pasar el margen del velocímetro', () {
      final analyzer = TelemetryAnalyzer(
        speedLimitKmh: 50,
        speedToleranceKmh: 8,
        minSpeedingDuration: const Duration(seconds: 5),
      );
      for (var i = 0; i <= 30; i++) {
        analyzer.add(fix(i, speed: 55, meters: 15.0 * i));
      }
      analyzer.add(fix(31, speed: 40, meters: 470));
      expect(
        analyzer.events.where((s) => s.type == DrivingEventType.speeding),
        isEmpty,
      );
    });

    test('sin límite conocido no se evalúa', () {
      final analyzer = TelemetryAnalyzer();
      for (var i = 0; i <= 60; i++) {
        analyzer.add(fix(i, speed: 150, meters: 41.0 * i));
      }
      expect(
        analyzer.events.where((s) => s.type == DrivingEventType.speeding),
        isEmpty,
      );
    });
  });

  group('DrivingScore', () {
    test('una conducción limpia saca cien', () {
      final analyzer = TelemetryAnalyzer();
      for (var i = 0; i <= 100; i++) {
        analyzer.add(fix(i, speed: 50, meters: 14.0 * i));
      }
      expect(analyzer.score().value, 100);
    });

    test('los sucesos bajan la nota', () {
      final analyzer = TelemetryAnalyzer();
      for (var i = 0; i < 10; i++) {
        analyzer
          ..add(fix(i * 10, speed: 80, meters: 300.0 * i))
          ..add(fix(i * 10 + 2, speed: 30, meters: 300.0 * i + 30));
      }
      final score = analyzer.score();
      expect(score.value, lessThan(100));
      expect(score.counts[DrivingEventType.harshBraking], greaterThan(5));
      expect(score.eventsPer100Km, greaterThan(0));
    });

    test('reset deja el analizador como nuevo', () {
      final analyzer = TelemetryAnalyzer()
        ..add(fix(0, speed: 80))
        ..add(fix(2, speed: 20, meters: 30));
      expect(analyzer.events, isNotEmpty);
      analyzer.reset();
      expect(analyzer.events, isEmpty);
      expect(analyzer.score().value, 100);
    });
  });
}
