// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:math' as math;

import 'package:nativ_maps/nativ_maps.dart';
import 'package:test/test.dart';

void main() {
  final quito = LatLng(-0.1807, -78.4678);
  final base = DateTime.utc(2026, 8, 23, 10);

  PositionFix lectura(
    LatLng donde,
    int segundo, {
    double? precision = 5,
    double? velocidad,
  }) => PositionFix(
    position: donde,
    timestamp: base.add(Duration(seconds: segundo)),
    accuracyMeters: precision,
    speedKmh: velocidad,
  );

  group('PositionFilter', () {
    test('la primera lectura siempre se acepta, con avance cero', () {
      final filtro = PositionFilter();
      final r = filtro.add(lectura(quito, 0));
      expect(r.accepted, isTrue);
      expect(r.distanceMeters, 0);
    });

    test('descarta por incertidumbre declarada', () {
      final filtro = PositionFilter(maxAccuracyMeters: 30);
      final r = filtro.add(lectura(quito, 0, precision: 120));
      expect(r.accepted, isFalse);
      expect(r.rejection, FixRejection.poorAccuracy);
    });

    test('descarta una lectura anterior a la última aceptada', () {
      final filtro = PositionFilter()..add(lectura(quito, 10));
      final r = filtro.add(lectura(quito.offset(200, 90), 5));
      expect(r.rejection, FixRejection.outOfOrder);
    });

    test('descarta el rebote del receptor parado', () {
      final filtro = PositionFilter(noiseFactor: 2);
      filtro.add(lectura(quito, 0, precision: 20));
      // Con ±20 m el umbral es 40 m; un salto de 25 m es ruido.
      final r = filtro.add(lectura(quito.offset(25, 30), 1, precision: 20));
      expect(r.rejection, FixRejection.withinNoise);
    });

    test('acepta movimiento que supera el ruido', () {
      final filtro = PositionFilter(noiseFactor: 2);
      filtro.add(lectura(quito, 0, precision: 5));
      final r = filtro.add(lectura(quito.offset(30, 90), 2, precision: 5));
      expect(r.accepted, isTrue);
      expect(r.distanceMeters, closeTo(30, 1));
      expect(r.impliedSpeedKmh, closeTo(54, 2));
    });

    test('descarta un salto imposible', () {
      final filtro = PositionFilter(maxSpeedKmh: 200);
      filtro.add(lectura(quito, 0));
      // 2 km en un segundo son 7 200 km/h.
      final r = filtro.add(lectura(quito.offset(2000, 90), 1));
      expect(r.rejection, FixRejection.impossibleSpeed);
    });

    test('sin incertidumbre declarada usa el suelo absoluto', () {
      final filtro = PositionFilter(minDisplacementMeters: 10);
      filtro.add(lectura(quito, 0, precision: null));
      final cerca = filtro.add(
        lectura(quito.offset(4, 90), 1, precision: null),
      );
      final lejos = filtro.add(
        lectura(quito.offset(40, 90), 2, precision: null),
      );
      expect(cerca.rejection, FixRejection.withinNoise);
      expect(lejos.accepted, isTrue);
    });

    test('leer la posición de una lectura descartada lanza', () {
      final filtro = PositionFilter(maxAccuracyMeters: 10);
      final r = filtro.add(lectura(quito, 0, precision: 99));
      expect(() => r.fix, throwsStateError);
    });

    test('reset olvida la última posición', () {
      final filtro = PositionFilter()..add(lectura(quito, 0));
      expect(filtro.last, isNotNull);
      filtro.reset();
      expect(filtro.last, isNull);
      // Sin reset, el primer punto del viaje nuevo se compararía con el
      // último del anterior y esa distancia contaría como recorrido.
      final r = filtro.add(lectura(quito.offset(5000, 90), 3600));
      expect(r.distanceMeters, 0);
    });

    test('el suavizado reduce el temblor sin desplazar la trayectoria', () {
      final rng = math.Random(7);
      final crudo = <LatLng>[];
      final suavizado = <LatLng>[];
      final filtro = PositionFilter(smooth: true, noiseFactor: 0);

      for (var i = 0; i < 60; i++) {
        // Avance limpio de 15 m por segundo, más ruido de hasta 8 m.
        final real = quito.offset(15.0 * i, 90);
        final medido = real.offset(
          rng.nextDouble() * 8,
          rng.nextDouble() * 360,
        );
        crudo.add(medido);
        final r = filtro.add(
          PositionFix(
            position: medido,
            timestamp: base.add(Duration(seconds: i)),
            accuracyMeters: 8,
          ),
        );
        if (r.accepted) suavizado.add(r.fix.position);
      }

      double desviacion(List<LatLng> puntos) {
        var total = 0.0;
        for (var i = 0; i < puntos.length; i++) {
          total += puntos[i].distanceTo(quito.offset(15.0 * i, 90));
        }
        return total / puntos.length;
      }

      expect(desviacion(suavizado), lessThan(desviacion(crudo)));

      // Guardia contra el retraso. Un Kalman que solo estima posición pasa
      // esta prueba de desviación media y aun así arrastra el punto casi cien
      // metros por detrás del coche. El estado de velocidad es lo que lo
      // evita, y esto es lo que lo comprueba.
      final ultimoReal = quito.offset(15.0 * (suavizado.length - 1), 90);
      expect(suavizado.last.distanceTo(ultimoReal), lessThan(15));
    });
  });
}
