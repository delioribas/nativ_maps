// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:math' as math;

import 'package:nativ_maps/nativ_maps.dart';
import 'package:test/test.dart';

void main() {
  final quito = LatLng(-0.1807, -78.4678);
  final base = DateTime.utc(2026, 8, 23, 10);

  group('TripRecorder', () {
    test('un vehículo parado no acumula kilómetros', () {
      // La prueba que justifica todo este módulo.
      //
      // Un móvil quieto en una calle estrecha declara ±20 m y rebota dentro
      // de ese círculo cada segundo. Sumar las distancias entre lecturas
      // consecutivas convierte veinte minutos de espera en varios kilómetros
      // que el pasajero acaba pagando.
      final rng = math.Random(42);
      final recorder = TripRecorder();
      var naiveSum = 0.0;
      LatLng? previous;

      for (var i = 0; i < 1200; i++) {
        final measured = quito.offset(
          rng.nextDouble() * 15,
          rng.nextDouble() * 360,
        );
        if (previous != null) naiveSum += previous.distanceTo(measured);
        previous = measured;

        recorder.add(
          PositionFix(
            position: measured,
            timestamp: base.add(Duration(seconds: i)),
            accuracyMeters: 20,
            speedKmh: 0,
          ),
        );
      }

      final trip = recorder.finish();

      // La suma ingenua se pasa de largo: kilómetros de un coche aparcado.
      expect(naiveSum, greaterThan(5000));
      // El registrador no se traga ni uno.
      expect(trip.distanceMeters, lessThan(50));
      expect(trip.rejections[FixRejection.withinNoise], greaterThan(1100));
    });

    test('el reloj sigue corriendo mientras está parado', () {
      // El corolario del caso anterior: si los descartes por ruido se
      // ignorasen, veinte minutos de espera durarían cero.
      final recorder = TripRecorder(
        minStopDuration: const Duration(seconds: 30),
      );
      for (var i = 0; i <= 600; i++) {
        recorder.add(
          PositionFix(
            position: quito,
            timestamp: base.add(Duration(seconds: i)),
            accuracyMeters: 10,
            speedKmh: 0,
          ),
        );
      }
      final trip = recorder.finish();

      expect(trip.duration, const Duration(seconds: 600));
      expect(trip.stoppedDuration.inSeconds, greaterThan(590));
      expect(trip.movingDuration.inSeconds, lessThan(10));
      expect(trip.stops, hasLength(1));
    });

    test('mide bien un trayecto en línea recta', () {
      final recorder = TripRecorder();
      for (var i = 0; i <= 60; i++) {
        recorder.add(
          PositionFix(
            position: quito.offset(20.0 * i, 90),
            timestamp: base.add(Duration(seconds: i)),
            accuracyMeters: 5,
            speedKmh: 72,
          ),
        );
      }
      final trip = recorder.finish();

      expect(trip.distanceMeters, closeTo(1200, 20));
      expect(trip.stops, isEmpty);
      expect(trip.averageMovingSpeedKmh, closeTo(72, 3));
      expect(trip.maxSpeedKmh, closeTo(72, 1));
    });

    test('la histéresis evita cien paradas de dos segundos', () {
      // Un coche oscilando alrededor del umbral de parada. Con un solo
      // umbral generaría decenas de paradas espurias.
      final recorder = TripRecorder(
        stopSpeedKmh: 3,
        resumeSpeedKmh: 8,
        minStopDuration: const Duration(seconds: 20),
      );
      for (var i = 0; i <= 300; i++) {
        recorder.add(
          PositionFix(
            position: quito.offset(0.5 * i, 90),
            timestamp: base.add(Duration(seconds: i)),
            accuracyMeters: 5,
            speedKmh: i.isEven ? 2 : 5,
          ),
        );
      }
      // Nunca supera los 8 km/h, así que nunca sale del estado de parado:
      // una sola parada, no ciento cincuenta.
      expect(recorder.finish().stops.length, lessThanOrEqualTo(1));
    });

    test('una detención corta no cuenta como parada', () {
      final recorder = TripRecorder(
        minStopDuration: const Duration(seconds: 45),
      );
      for (var i = 0; i <= 120; i++) {
        // Semáforo de 20 s en mitad del trayecto.
        final stopped = i >= 50 && i < 70;
        recorder.add(
          PositionFix(
            position: quito.offset(stopped ? 1000 : 20.0 * i, 90),
            timestamp: base.add(Duration(seconds: i)),
            accuracyMeters: 5,
            speedKmh: stopped ? 0 : 72,
          ),
        );
      }
      expect(recorder.finish().stops, isEmpty);
    });

    test('cierra la parada que quedó abierta al terminar', () {
      final recorder = TripRecorder(
        minStopDuration: const Duration(seconds: 30),
      );
      for (var i = 0; i <= 60; i++) {
        recorder.add(
          PositionFix(
            position: quito.offset(20.0 * i, 90),
            timestamp: base.add(Duration(seconds: i)),
            accuracyMeters: 5,
            speedKmh: 72,
          ),
        );
      }
      // El taxi llega y espera a que el pasajero pague.
      for (var i = 61; i <= 180; i++) {
        recorder.add(
          PositionFix(
            position: quito.offset(1200, 90),
            timestamp: base.add(Duration(seconds: i)),
            accuracyMeters: 5,
            speedKmh: 0,
          ),
        );
      }
      final trip = recorder.finish();

      // Sin cerrar la parada final, esos dos minutos de espera se perderían.
      expect(trip.stops, hasLength(1));
      expect(trip.stoppedDuration.inSeconds, greaterThan(100));
    });

    test('keepTrack a false no guarda el recorrido', () {
      final recorder = TripRecorder(keepTrack: false);
      for (var i = 0; i <= 30; i++) {
        recorder.add(
          PositionFix(
            position: quito.offset(30.0 * i, 90),
            timestamp: base.add(Duration(seconds: i)),
            accuracyMeters: 5,
          ),
        );
      }
      final trip = recorder.finish();
      expect(trip.track, isEmpty);
      expect(trip.distanceMeters, greaterThan(800));
    });

    test('rechaza una histéresis invertida', () {
      expect(
        () => TripRecorder(stopSpeedKmh: 10, resumeSpeedKmh: 5),
        throwsArgumentError,
      );
    });

    test('reset deja el registrador como nuevo', () {
      final recorder = TripRecorder();
      for (var i = 0; i <= 30; i++) {
        recorder.add(
          PositionFix(
            position: quito.offset(30.0 * i, 90),
            timestamp: base.add(Duration(seconds: i)),
            accuracyMeters: 5,
          ),
        );
      }
      expect(recorder.distanceMeters, greaterThan(0));
      recorder.reset();
      expect(recorder.distanceMeters, 0);
      expect(recorder.stops, isEmpty);
    });
  });
}
