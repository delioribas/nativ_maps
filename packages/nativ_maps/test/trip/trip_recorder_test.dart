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
      final registrador = TripRecorder();
      var sumaIngenua = 0.0;
      LatLng? anterior;

      for (var i = 0; i < 1200; i++) {
        final medido = quito.offset(
          rng.nextDouble() * 15,
          rng.nextDouble() * 360,
        );
        if (anterior != null) sumaIngenua += anterior.distanceTo(medido);
        anterior = medido;

        registrador.add(
          PositionFix(
            position: medido,
            timestamp: base.add(Duration(seconds: i)),
            accuracyMeters: 20,
            speedKmh: 0,
          ),
        );
      }

      final viaje = registrador.finish();

      // La suma ingenua se pasa de largo: kilómetros de un coche aparcado.
      expect(sumaIngenua, greaterThan(5000));
      // El registrador no se traga ni uno.
      expect(viaje.distanceMeters, lessThan(50));
      expect(viaje.rejections[FixRejection.withinNoise], greaterThan(1100));
    });

    test('el reloj sigue corriendo mientras está parado', () {
      // El corolario del caso anterior: si los descartes por ruido se
      // ignorasen, veinte minutos de espera durarían cero.
      final registrador = TripRecorder(
        minStopDuration: const Duration(seconds: 30),
      );
      for (var i = 0; i <= 600; i++) {
        registrador.add(
          PositionFix(
            position: quito,
            timestamp: base.add(Duration(seconds: i)),
            accuracyMeters: 10,
            speedKmh: 0,
          ),
        );
      }
      final viaje = registrador.finish();

      expect(viaje.duration, const Duration(seconds: 600));
      expect(viaje.stoppedDuration.inSeconds, greaterThan(590));
      expect(viaje.movingDuration.inSeconds, lessThan(10));
      expect(viaje.stops, hasLength(1));
    });

    test('mide bien un trayecto en línea recta', () {
      final registrador = TripRecorder();
      for (var i = 0; i <= 60; i++) {
        registrador.add(
          PositionFix(
            position: quito.offset(20.0 * i, 90),
            timestamp: base.add(Duration(seconds: i)),
            accuracyMeters: 5,
            speedKmh: 72,
          ),
        );
      }
      final viaje = registrador.finish();

      expect(viaje.distanceMeters, closeTo(1200, 20));
      expect(viaje.stops, isEmpty);
      expect(viaje.averageMovingSpeedKmh, closeTo(72, 3));
      expect(viaje.maxSpeedKmh, closeTo(72, 1));
    });

    test('la histéresis evita cien paradas de dos segundos', () {
      // Un coche oscilando alrededor del umbral de parada. Con un solo
      // umbral generaría decenas de paradas espurias.
      final registrador = TripRecorder(
        stopSpeedKmh: 3,
        resumeSpeedKmh: 8,
        minStopDuration: const Duration(seconds: 20),
      );
      for (var i = 0; i <= 300; i++) {
        registrador.add(
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
      expect(registrador.finish().stops.length, lessThanOrEqualTo(1));
    });

    test('una detención corta no cuenta como parada', () {
      final registrador = TripRecorder(
        minStopDuration: const Duration(seconds: 45),
      );
      for (var i = 0; i <= 120; i++) {
        // Semáforo de 20 s en mitad del trayecto.
        final parado = i >= 50 && i < 70;
        registrador.add(
          PositionFix(
            position: quito.offset(parado ? 1000 : 20.0 * i, 90),
            timestamp: base.add(Duration(seconds: i)),
            accuracyMeters: 5,
            speedKmh: parado ? 0 : 72,
          ),
        );
      }
      expect(registrador.finish().stops, isEmpty);
    });

    test('cierra la parada que quedó abierta al terminar', () {
      final registrador = TripRecorder(
        minStopDuration: const Duration(seconds: 30),
      );
      for (var i = 0; i <= 60; i++) {
        registrador.add(
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
        registrador.add(
          PositionFix(
            position: quito.offset(1200, 90),
            timestamp: base.add(Duration(seconds: i)),
            accuracyMeters: 5,
            speedKmh: 0,
          ),
        );
      }
      final viaje = registrador.finish();

      // Sin cerrar la parada final, esos dos minutos de espera se perderían.
      expect(viaje.stops, hasLength(1));
      expect(viaje.stoppedDuration.inSeconds, greaterThan(100));
    });

    test('keepTrack a false no guarda el recorrido', () {
      final registrador = TripRecorder(keepTrack: false);
      for (var i = 0; i <= 30; i++) {
        registrador.add(
          PositionFix(
            position: quito.offset(30.0 * i, 90),
            timestamp: base.add(Duration(seconds: i)),
            accuracyMeters: 5,
          ),
        );
      }
      final viaje = registrador.finish();
      expect(viaje.track, isEmpty);
      expect(viaje.distanceMeters, greaterThan(800));
    });

    test('rechaza una histéresis invertida', () {
      expect(
        () => TripRecorder(stopSpeedKmh: 10, resumeSpeedKmh: 5),
        throwsArgumentError,
      );
    });

    test('reset deja el registrador como nuevo', () {
      final registrador = TripRecorder();
      for (var i = 0; i <= 30; i++) {
        registrador.add(
          PositionFix(
            position: quito.offset(30.0 * i, 90),
            timestamp: base.add(Duration(seconds: i)),
            accuracyMeters: 5,
          ),
        );
      }
      expect(registrador.distanceMeters, greaterThan(0));
      registrador.reset();
      expect(registrador.distanceMeters, 0);
      expect(registrador.stops, isEmpty);
    });
  });
}
