// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:math' as math;

import 'package:nativ_maps/nativ_maps.dart';
import 'package:test/test.dart';

void main() {
  final quito = LatLng(-0.1807, -78.4678);
  final base = DateTime.utc(2026, 8, 23, 10);

  PositionFix fix(
    LatLng donde,
    int segundo, {
    double? accuracy = 5,
    double? speed,
  }) => PositionFix(
    position: donde,
    timestamp: base.add(Duration(seconds: segundo)),
    accuracyMeters: accuracy,
    speedKmh: speed,
  );

  group('PositionFilter', () {
    test('la primera lectura siempre se acepta, con avance cero', () {
      final filter = PositionFilter();
      final r = filter.add(fix(quito, 0));
      expect(r.accepted, isTrue);
      expect(r.distanceMeters, 0);
    });

    test('descarta por incertidumbre declarada', () {
      final filter = PositionFilter(maxAccuracyMeters: 30);
      final r = filter.add(fix(quito, 0, accuracy: 120));
      expect(r.accepted, isFalse);
      expect(r.rejection, FixRejection.poorAccuracy);
    });

    test('descarta una lectura anterior a la última aceptada', () {
      final filter = PositionFilter()..add(fix(quito, 10));
      final r = filter.add(fix(quito.offset(200, 90), 5));
      expect(r.rejection, FixRejection.outOfOrder);
    });

    test('descarta el rebote del receptor parado', () {
      final filter = PositionFilter(noiseFactor: 2);
      filter.add(fix(quito, 0, accuracy: 20));
      // Con ±20 m el umbral es 40 m; un salto de 25 m es ruido.
      final r = filter.add(fix(quito.offset(25, 30), 1, accuracy: 20));
      expect(r.rejection, FixRejection.withinNoise);
    });

    test('acepta movimiento que supera el ruido', () {
      final filter = PositionFilter(noiseFactor: 2);
      filter.add(fix(quito, 0, accuracy: 5));
      final r = filter.add(fix(quito.offset(30, 90), 2, accuracy: 5));
      expect(r.accepted, isTrue);
      expect(r.distanceMeters, closeTo(30, 1));
      expect(r.impliedSpeedKmh, closeTo(54, 2));
    });

    test('descarta un salto imposible', () {
      final filter = PositionFilter(maxSpeedKmh: 200);
      filter.add(fix(quito, 0));
      // 2 km en un segundo son 7 200 km/h.
      final r = filter.add(fix(quito.offset(2000, 90), 1));
      expect(r.rejection, FixRejection.impossibleSpeed);
    });

    test('sin incertidumbre declarada usa el suelo absoluto', () {
      final filter = PositionFilter(minDisplacementMeters: 10);
      filter.add(fix(quito, 0, accuracy: null));
      final closeBy = filter.add(fix(quito.offset(4, 90), 1, accuracy: null));
      final faraway = filter.add(fix(quito.offset(40, 90), 2, accuracy: null));
      expect(closeBy.rejection, FixRejection.withinNoise);
      expect(faraway.accepted, isTrue);
    });

    test('leer la posición de una lectura descartada lanza', () {
      final filter = PositionFilter(maxAccuracyMeters: 10);
      final r = filter.add(fix(quito, 0, accuracy: 99));
      expect(() => r.fix, throwsStateError);
    });

    test('reset olvida la última posición', () {
      final filter = PositionFilter()..add(fix(quito, 0));
      expect(filter.last, isNotNull);
      filter.reset();
      expect(filter.last, isNull);
      // Sin reset, el primer punto del viaje nuevo se compararía con el
      // último del anterior y esa distancia contaría como recorrido.
      final r = filter.add(fix(quito.offset(5000, 90), 3600));
      expect(r.distanceMeters, 0);
    });

    test('el suavizado reduce el temblor sin desplazar la trayectoria', () {
      final rng = math.Random(7);
      final raw = <LatLng>[];
      final smoothed = <LatLng>[];
      final filter = PositionFilter(smooth: true, noiseFactor: 0);

      for (var i = 0; i < 60; i++) {
        // Avance limpio de 15 m por segundo, más ruido de hasta 8 m.
        final actual = quito.offset(15.0 * i, 90);
        final measured = actual.offset(
          rng.nextDouble() * 8,
          rng.nextDouble() * 360,
        );
        raw.add(measured);
        final r = filter.add(
          PositionFix(
            position: measured,
            timestamp: base.add(Duration(seconds: i)),
            accuracyMeters: 8,
          ),
        );
        if (r.accepted) smoothed.add(r.fix.position);
      }

      double deviation(List<LatLng> puntos) {
        var total = 0.0;
        for (var i = 0; i < puntos.length; i++) {
          total += puntos[i].distanceTo(quito.offset(15.0 * i, 90));
        }
        return total / puntos.length;
      }

      expect(deviation(smoothed), lessThan(deviation(raw)));

      // Guardia contra el retraso. Un Kalman que solo estima posición pasa
      // esta prueba de desviación media y aun así arrastra el punto casi cien
      // metros por detrás del coche. El estado de velocidad es lo que lo
      // evita, y esto es lo que lo comprueba.
      final lastTruePosition = quito.offset(15.0 * (smoothed.length - 1), 90);
      expect(smoothed.last.distanceTo(lastTruePosition), lessThan(15));
    });
  });
}
