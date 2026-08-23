// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:nativ_maps/nativ_maps.dart';
import 'package:test/test.dart';

void main() {
  final quito = LatLng(-0.1807, -78.4678);

  /// Dos kilómetros en línea recta hacia el este, en dos maniobras.
  ///
  /// La primera es un kilómetro de ciudad que cuesta 120 s; la segunda es un
  /// kilómetro de vía rápida que cuesta 30 s. La diferencia es lo que hace
  /// que el reparto proporcional falle.
  Route rutaDeDosTramos() => Route(
    distanceMeters: 2000,
    duration: const Duration(seconds: 150),
    legs: <RouteLeg>[
      RouteLeg(
        distanceMeters: 2000,
        duration: const Duration(seconds: 150),
        geometry: RouteGeometry(<LatLng>[
          quito,
          quito.offset(1000, 90),
          quito.offset(2000, 90),
        ]),
        steps: const <TravelStep>[
          TravelStep(
            distanceMeters: 1000,
            duration: Duration(seconds: 120),
            instruction: 'Siga por la avenida',
          ),
          TravelStep(
            distanceMeters: 1000,
            duration: Duration(seconds: 30),
            instruction: 'Incorpórese a la autopista',
          ),
        ],
      ),
    ],
  );

  group('RouteTracker', () {
    test(
      'el tiempo restante sale de las maniobras, no de la regla de tres',
      () {
        final seguimiento = RouteTracker(rutaDeDosTramos());
        // A 1 500 m: queda medio tramo rápido, 15 s.
        final progreso = seguimiento.update(quito.offset(1500, 90));

        expect(progreso.remainingMeters, closeTo(500, 5));
        expect(progreso.remainingDuration.inSeconds, closeTo(15, 2));
        // El reparto proporcional daría 150 × 500/2000 = 37 s, más del doble.
        expect(progreso.remainingDuration.inSeconds, lessThan(25));
      },
    );

    test('la hora de llegada se calcula desde el instante que se le pasa', () {
      final ahora = DateTime.utc(2026, 8, 23, 10);
      final progreso = RouteTracker(
        rutaDeDosTramos(),
      ).update(quito.offset(1500, 90), now: ahora);
      expect(
        progreso.eta.difference(ahora).inSeconds,
        progreso.remainingDuration.inSeconds,
      );
    });

    test('dice en qué maniobra va y cuánto falta para la siguiente', () {
      final progreso = RouteTracker(
        rutaDeDosTramos(),
      ).update(quito.offset(600, 90));

      expect(progreso.stepIndex, 0);
      expect(progreso.currentStep?.instruction, 'Siga por la avenida');
      expect(progreso.nextStep?.instruction, 'Incorpórese a la autopista');
      expect(progreso.distanceToNextManeuverMeters, closeTo(400, 5));
    });

    test('el progreso avanza de 0 a 1', () {
      final seguimiento = RouteTracker(rutaDeDosTramos());
      expect(seguimiento.update(quito).fraction, closeTo(0, 0.01));
      expect(
        seguimiento.update(quito.offset(2000, 90)).fraction,
        closeTo(1, 0.01),
      );
    });

    test('no declara desvío con una sola lectura mala', () {
      final seguimiento = RouteTracker(
        rutaDeDosTramos(),
        offRouteThresholdMeters: 45,
        offRouteStrikes: 3,
      );
      seguimiento.update(quito.offset(500, 90));

      // Dos rebotes seguidos a 200 m: todavía no es un desvío.
      final lejos = quito.offset(500, 90).offset(200, 0);
      expect(seguimiento.update(lejos).offRoute, isFalse);
      expect(seguimiento.update(lejos).offRoute, isFalse);
      // Al tercero sí.
      expect(seguimiento.update(lejos).offRoute, isTrue);
    });

    test('volver a la ruta cancela el desvío y reinicia la cuenta', () {
      final seguimiento = RouteTracker(rutaDeDosTramos(), offRouteStrikes: 2);
      final lejos = quito.offset(500, 90).offset(300, 0);
      seguimiento
        ..update(lejos)
        ..update(lejos);
      expect(seguimiento.isOffRoute, isTrue);

      expect(seguimiento.update(quito.offset(600, 90)).offRoute, isFalse);
      expect(seguimiento.update(lejos).offRoute, isFalse);
    });

    test('recupera al vehículo que reaparece lejos, fuera de la ventana', () {
      // Un túnel: se pierde la señal al principio y se recupera al final.
      final camino = <LatLng>[
        for (var i = 0; i <= 200; i++) quito.offset(50.0 * i, 90),
      ];
      final larga = Route(
        distanceMeters: 10000,
        duration: const Duration(minutes: 15),
        legs: <RouteLeg>[
          RouteLeg(
            distanceMeters: 10000,
            duration: const Duration(minutes: 15),
            geometry: RouteGeometry(camino),
          ),
        ],
      );
      final seguimiento = RouteTracker(larga, searchWindowSegments: 5);
      seguimiento.update(quito.offset(100, 90));

      // Reaparece a 9 km, mucho más allá de la ventana de cinco segmentos.
      final progreso = seguimiento.update(quito.offset(9000, 90));
      expect(progreso.match.alongMeters, closeTo(9000, 50));
      expect(progreso.offRoute, isFalse);
    });

    test('sin indicaciones cae al reparto proporcional', () {
      final sinPasos = Route(
        distanceMeters: 2000,
        duration: const Duration(seconds: 200),
        legs: <RouteLeg>[
          RouteLeg(
            distanceMeters: 2000,
            duration: const Duration(seconds: 200),
            geometry: RouteGeometry(<LatLng>[quito, quito.offset(2000, 90)]),
          ),
        ],
      );
      final progreso = RouteTracker(sinPasos).update(quito.offset(1000, 90));
      expect(progreso.remainingDuration.inSeconds, closeTo(100, 3));
    });

    test('una ruta sin geometría no se puede seguir', () {
      const vacia = Route(
        distanceMeters: 0,
        duration: Duration.zero,
        legs: <RouteLeg>[
          RouteLeg(
            distanceMeters: 0,
            duration: Duration.zero,
            geometry: RouteGeometry(<LatLng>[]),
          ),
        ],
      );
      expect(() => RouteTracker(vacia), throwsArgumentError);
    });
  });
}
