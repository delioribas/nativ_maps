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
  Route twoStepRoute() => Route(
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
        final tracker = RouteTracker(twoStepRoute());
        // A 1 500 m: queda medio tramo rápido, 15 s.
        final progress = tracker.update(quito.offset(1500, 90));

        expect(progress.remainingMeters, closeTo(500, 5));
        expect(progress.remainingDuration.inSeconds, closeTo(15, 2));
        // El reparto proporcional daría 150 × 500/2000 = 37 s, más del doble.
        expect(progress.remainingDuration.inSeconds, lessThan(25));
      },
    );

    test('la hora de llegada se calcula desde el instante que se le pasa', () {
      final now = DateTime.utc(2026, 8, 23, 10);
      final progress = RouteTracker(
        twoStepRoute(),
      ).update(quito.offset(1500, 90), now: now);
      expect(
        progress.eta.difference(now).inSeconds,
        progress.remainingDuration.inSeconds,
      );
    });

    test('dice en qué maniobra va y cuánto falta para la siguiente', () {
      final progress = RouteTracker(
        twoStepRoute(),
      ).update(quito.offset(600, 90));

      expect(progress.stepIndex, 0);
      expect(progress.currentStep?.instruction, 'Siga por la avenida');
      expect(progress.nextStep?.instruction, 'Incorpórese a la autopista');
      expect(progress.distanceToNextManeuverMeters, closeTo(400, 5));
    });

    test('el progreso avanza de 0 a 1', () {
      final tracker = RouteTracker(twoStepRoute());
      expect(tracker.update(quito).fraction, closeTo(0, 0.01));
      expect(tracker.update(quito.offset(2000, 90)).fraction, closeTo(1, 0.01));
    });

    test('no declara desvío con una sola lectura mala', () {
      final tracker = RouteTracker(
        twoStepRoute(),
        offRouteThresholdMeters: 45,
        offRouteStrikes: 3,
      );
      tracker.update(quito.offset(500, 90));

      // Dos rebotes seguidos a 200 m: todavía no es un desvío.
      final faraway = quito.offset(500, 90).offset(200, 0);
      expect(tracker.update(faraway).offRoute, isFalse);
      expect(tracker.update(faraway).offRoute, isFalse);
      // Al tercero sí.
      expect(tracker.update(faraway).offRoute, isTrue);
    });

    test('volver a la ruta cancela el desvío y reinicia la cuenta', () {
      final tracker = RouteTracker(twoStepRoute(), offRouteStrikes: 2);
      final faraway = quito.offset(500, 90).offset(300, 0);
      tracker
        ..update(faraway)
        ..update(faraway);
      expect(tracker.isOffRoute, isTrue);

      expect(tracker.update(quito.offset(600, 90)).offRoute, isFalse);
      expect(tracker.update(faraway).offRoute, isFalse);
    });

    test('recupera al vehículo que reaparece lejos, fuera de la ventana', () {
      // Un túnel: se pierde la señal al principio y se recupera al final.
      final path = <LatLng>[
        for (var i = 0; i <= 200; i++) quito.offset(50.0 * i, 90),
      ];
      final longRoute = Route(
        distanceMeters: 10000,
        duration: const Duration(minutes: 15),
        legs: <RouteLeg>[
          RouteLeg(
            distanceMeters: 10000,
            duration: const Duration(minutes: 15),
            geometry: RouteGeometry(path),
          ),
        ],
      );
      final tracker = RouteTracker(longRoute, searchWindowSegments: 5);
      tracker.update(quito.offset(100, 90));

      // Reaparece a 9 km, mucho más allá de la ventana de cinco segmentos.
      final progress = tracker.update(quito.offset(9000, 90));
      expect(progress.match.alongMeters, closeTo(9000, 50));
      expect(progress.offRoute, isFalse);
    });

    test('sin indicaciones cae al reparto proporcional', () {
      final withoutSteps = Route(
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
      final progress = RouteTracker(
        withoutSteps,
      ).update(quito.offset(1000, 90));
      expect(progress.remainingDuration.inSeconds, closeTo(100, 3));
    });

    test('una ruta sin geometría no se puede seguir', () {
      const emptyRoute = Route(
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
      expect(() => RouteTracker(emptyRoute), throwsArgumentError);
    });
  });
}
