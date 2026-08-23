// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:nativ_maps/nativ_maps.dart';
import 'package:test/test.dart';

void main() {
  final quito = LatLng(-0.1807, -78.4678);
  final base = DateTime.utc(2026, 8, 23, 10);

  PositionFix lectura(
    int segundo, {
    double? velocidad,
    double? rumbo,
    double metros = 0,
  }) => PositionFix(
    position: quito.offset(metros, 90),
    timestamp: base.add(Duration(seconds: segundo)),
    accuracyMeters: 5,
    speedKmh: velocidad,
    headingDegrees: rumbo,
  );

  group('aceleración', () {
    test('detecta un frenazo', () {
      final analizador = TelemetryAnalyzer()..add(lectura(0, velocidad: 80));
      // De 80 a 40 km/h en dos segundos son −5,6 m/s².
      final sucesos = analizador.add(lectura(2, velocidad: 40, metros: 30));

      expect(sucesos, hasLength(1));
      expect(sucesos.single.type, DrivingEventType.harshBraking);
      expect(sucesos.single.magnitude, closeTo(-5.56, 0.1));
      expect(sucesos.single.gForce, closeTo(0.57, 0.05));
    });

    test('detecta un acelerón', () {
      final analizador = TelemetryAnalyzer()..add(lectura(0, velocidad: 0));
      final sucesos = analizador.add(lectura(2, velocidad: 45, metros: 12));
      expect(sucesos.single.type, DrivingEventType.harshAcceleration);
    });

    test('una conducción suave no genera nada', () {
      final analizador = TelemetryAnalyzer();
      for (var i = 0; i <= 20; i++) {
        analizador.add(
          lectura(i, velocidad: 40 + i.toDouble(), metros: 11.0 * i),
        );
      }
      expect(analizador.events, isEmpty);
    });

    test('sin velocidad del receptor no se inventa ninguna', () {
      // Derivar la aceleración de las posiciones amplifica el ruido del GPS
      // al cuadrado y produce frenazos en un coche parado. Es preferible no
      // detectar a detectar mentiras.
      final analizador = TelemetryAnalyzer()
        ..add(lectura(0))
        ..add(lectura(1, metros: 500));
      expect(analizador.events, isEmpty);
    });

    test('un hueco largo entre lecturas no describe ninguna maniobra', () {
      final analizador = TelemetryAnalyzer(
        maxSampleGap: const Duration(seconds: 10),
      )..add(lectura(0, velocidad: 100));
      final sucesos = analizador.add(lectura(600, velocidad: 0));
      expect(sucesos, isEmpty);
    });
  });

  group('curvas', () {
    test('detecta una curva tomada deprisa', () {
      // 90° en dos segundos a 40 km/h son 8,7 m/s² laterales.
      final analizador = TelemetryAnalyzer()
        ..add(lectura(0, velocidad: 40, rumbo: 0));
      final sucesos = analizador.add(
        lectura(2, velocidad: 40, rumbo: 90, metros: 22),
      );
      expect(
        sucesos.map((s) => s.type),
        contains(DrivingEventType.harshCornering),
      );
    });

    test('cruzar el norte no es una curva de 358 grados', () {
      // Sin normalizar la diferencia de rumbo, todo coche que pase de 359° a
      // 1° generaría una curva brusca.
      final analizador = TelemetryAnalyzer()
        ..add(lectura(0, velocidad: 50, rumbo: 359));
      final sucesos = analizador.add(
        lectura(1, velocidad: 50, rumbo: 1, metros: 14),
      );
      expect(sucesos, isEmpty);
    });
  });

  group('exceso de velocidad', () {
    test('un exceso largo es un suceso, no cien', () {
      final analizador = TelemetryAnalyzer(
        speedLimitKmh: 50,
        minSpeedingDuration: const Duration(seconds: 10),
      );
      // Treinta segundos a 70 en una vía de 50.
      for (var i = 0; i <= 30; i++) {
        analizador.add(lectura(i, velocidad: 70, metros: 19.4 * i));
      }
      // Y luego baja.
      analizador.add(lectura(31, velocidad: 45, metros: 600));

      final excesos = analizador.events
          .where((s) => s.type == DrivingEventType.speeding)
          .toList();
      expect(excesos, hasLength(1));
      expect(excesos.single.magnitude, closeTo(20, 0.1));
    });

    test('un adelantamiento corto no cuenta', () {
      final analizador = TelemetryAnalyzer(
        speedLimitKmh: 50,
        minSpeedingDuration: const Duration(seconds: 10),
      );
      for (var i = 0; i <= 4; i++) {
        analizador.add(lectura(i, velocidad: 70, metros: 19.4 * i));
      }
      // Al bajar de 70 a 45 hay un frenazo de verdad; lo que se comprueba
      // aquí es que NO se registra un exceso de velocidad.
      analizador.add(lectura(5, velocidad: 45, metros: 100));
      expect(
        analizador.events.where((s) => s.type == DrivingEventType.speeding),
        isEmpty,
      );
    });

    test('la tolerancia deja pasar el margen del velocímetro', () {
      final analizador = TelemetryAnalyzer(
        speedLimitKmh: 50,
        speedToleranceKmh: 8,
        minSpeedingDuration: const Duration(seconds: 5),
      );
      for (var i = 0; i <= 30; i++) {
        analizador.add(lectura(i, velocidad: 55, metros: 15.0 * i));
      }
      analizador.add(lectura(31, velocidad: 40, metros: 470));
      expect(
        analizador.events.where((s) => s.type == DrivingEventType.speeding),
        isEmpty,
      );
    });

    test('sin límite conocido no se evalúa', () {
      final analizador = TelemetryAnalyzer();
      for (var i = 0; i <= 60; i++) {
        analizador.add(lectura(i, velocidad: 150, metros: 41.0 * i));
      }
      expect(
        analizador.events.where((s) => s.type == DrivingEventType.speeding),
        isEmpty,
      );
    });
  });

  group('DrivingScore', () {
    test('una conducción limpia saca cien', () {
      final analizador = TelemetryAnalyzer();
      for (var i = 0; i <= 100; i++) {
        analizador.add(lectura(i, velocidad: 50, metros: 14.0 * i));
      }
      expect(analizador.score().value, 100);
    });

    test('los sucesos bajan la nota', () {
      final analizador = TelemetryAnalyzer();
      for (var i = 0; i < 10; i++) {
        analizador
          ..add(lectura(i * 10, velocidad: 80, metros: 300.0 * i))
          ..add(lectura(i * 10 + 2, velocidad: 30, metros: 300.0 * i + 30));
      }
      final nota = analizador.score();
      expect(nota.value, lessThan(100));
      expect(nota.counts[DrivingEventType.harshBraking], greaterThan(5));
      expect(nota.eventsPer100Km, greaterThan(0));
    });

    test('reset deja el analizador como nuevo', () {
      final analizador = TelemetryAnalyzer()
        ..add(lectura(0, velocidad: 80))
        ..add(lectura(2, velocidad: 20, metros: 30));
      expect(analizador.events, isNotEmpty);
      analizador.reset();
      expect(analizador.events, isEmpty);
      expect(analizador.score().value, 100);
    });
  });
}
