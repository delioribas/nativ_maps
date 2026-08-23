// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:math' as math;

import 'package:nativ_maps/nativ_maps.dart';
import 'package:test/test.dart';

void main() {
  // La tarifa «real» que el calibrador tiene que redescubrir.
  const flagfall = 250;
  const perKm = 110;
  const perMin = 35;

  int trueFare(double km, double min) =>
      (flagfall + km * perKm + min * perMin).round();

  FareSample sample(double km, double min, {int? price, String label = ''}) =>
      FareSample(
        distanceMeters: km * 1000,
        duration: Duration(seconds: (min * 60).round()),
        observedFare: price ?? trueFare(km, min),
        label: label,
      );

  /// Diez trayectos con distancias y tiempos deliberadamente descorrelados:
  /// hay un corto en atasco y un largo por autopista.
  List<FareSample> theSamples() => <FareSample>[
    sample(2, 12, label: 'corto en atasco'),
    sample(3, 5),
    sample(5, 15),
    sample(6, 30, label: 'atasco largo'),
    sample(8, 18),
    sample(12, 20),
    sample(15, 14, label: 'autopista'),
    sample(18, 22),
    sample(25, 25),
    sample(30, 28, label: 'aeropuerto'),
  ];

  group('TariffCalibration.fit', () {
    test('redescubre exactamente una tarifa conocida', () {
      final fit = TariffCalibration.fit(theSamples());

      expect(fit.baseFare, flagfall);
      expect(fit.perKilometer, perKm);
      expect(fit.perMinute, perMin);
      expect(fit.rSquared, closeTo(1.0, 1e-9));
      expect(fit.meanAbsoluteError, closeTo(0, 0.5));
    });

    test('la tarifa ajustada reproduce los precios observados', () {
      final samples = theSamples();
      final tariff = TariffCalibration.fit(samples).toTariff(currency: 'USD');

      for (final m in samples) {
        final estimated = tariff.estimate(
          distanceMeters: m.distanceMeters,
          duration: m.duration,
        );
        expect(estimated.total, closeTo(m.observedFare, 2));
      }
    });

    test('aguanta el ruido de precios redondeados en la calle', () {
      // Los precios reales vienen redondeados y con algo de variación.
      final rng = math.Random(3);
      final noisy = <FareSample>[
        for (final m in theSamples())
          FareSample(
            distanceMeters: m.distanceMeters,
            duration: m.duration,
            observedFare:
                (m.observedFare * (1 + (rng.nextDouble() - 0.5) * 0.06))
                    .round(),
          ),
      ];

      final fit = TariffCalibration.fit(noisy);

      expect(fit.rSquared, greaterThan(0.98));
      expect(fit.perKilometer, closeTo(perKm, perKm * 0.15));
      expect(fit.perMinute, closeTo(perMin, perMin * 0.35));
    });

    test('avisa cuando el reparto entre km y minuto no es fiable', () {
      // Todos los trayectos a la misma velocidad: matemáticamente no hay
      // forma de separar lo que cobra el kilómetro de lo que cobra el minuto.
      final proportional = <FareSample>[
        for (final km in <double>[2, 4, 6, 9, 12, 16, 20, 25])
          sample(km, km * 2),
      ];

      final fit = TariffCalibration.fit(proportional);

      expect(fit.distanceTimeCorrelation, greaterThan(0.99));
      expect(fit.splitIsReliable, isFalse);
      // Y aun así predice bien el total: por eso el aviso hace falta.
      expect(fit.rSquared, greaterThan(0.99));
    });

    test('con muestras variadas el reparto sí es fiable', () {
      final fit = TariffCalibration.fit(theSamples());
      expect(fit.splitIsReliable, isTrue);
    });

    test('sin componente de tiempo ajusta solo bandera y kilómetro', () {
      final distanceOnly = <FareSample>[
        for (final km in <double>[2, 5, 8, 12, 18, 25])
          FareSample(
            distanceMeters: km * 1000,
            duration: Duration(minutes: (km * 2).round()),
            observedFare: (300 + km * 140).round(),
          ),
      ];

      final fit = TariffCalibration.fit(
        distanceOnly,
        includeTimeComponent: false,
      );

      expect(fit.perMinute, 0);
      expect(fit.baseFare, closeTo(300, 3));
      expect(fit.perKilometer, closeTo(140, 3));
      expect(fit.rSquared, greaterThan(0.999));
    });

    test('nunca devuelve un precio por kilómetro negativo', () {
      // Datos donde el precio baja con la distancia: no tiene sentido físico,
      // así que el coeficiente se recorta a cero en vez de propagarse.
      final nonsensical = <FareSample>[
        const FareSample(
          distanceMeters: 2000,
          duration: Duration(minutes: 30),
          observedFare: 2000,
        ),
        const FareSample(
          distanceMeters: 10000,
          duration: Duration(minutes: 12),
          observedFare: 900,
        ),
        const FareSample(
          distanceMeters: 20000,
          duration: Duration(minutes: 8),
          observedFare: 700,
        ),
        const FareSample(
          distanceMeters: 30000,
          duration: Duration(minutes: 6),
          observedFare: 600,
        ),
      ];

      final fit = TariffCalibration.fit(nonsensical);
      expect(fit.baseFare, greaterThanOrEqualTo(0));
      expect(fit.perKilometer, greaterThanOrEqualTo(0));
      expect(fit.perMinute, greaterThanOrEqualTo(0));
    });

    test('isUsable exige buen ajuste y muestras suficientes', () {
      // Diez muestras perfectas: el ajuste es perfecto pero son pocas.
      expect(TariffCalibration.fit(theSamples()).isUsable, isTrue);
      expect(TariffCalibration.fit(theSamples()).sampleCount, 10);
    });

    test('rechaza menos de tres muestras', () {
      expect(
        () => TariffCalibration.fit(<FareSample>[sample(5, 10)]),
        throwsArgumentError,
      );
    });

    test('rechaza muestras sin ninguna variación', () {
      expect(
        () => TariffCalibration.fit(<FareSample>[
          sample(5, 10),
          sample(5, 10),
          sample(5, 10),
        ]),
        throwsArgumentError,
      );
    });
  });

  group('TariffFit', () {
    test('predice un trayecto que no estaba en las muestras', () {
      final fit = TariffCalibration.fit(theSamples());
      expect(
        fit.predict(
          distanceMeters: 7000,
          duration: const Duration(minutes: 16),
        ),
        trueFare(7, 16),
      );
    });

    test('el informe enseña el error muestra a muestra', () {
      final samples = theSamples();
      final text = TariffCalibration.fit(samples).report(samples);

      expect(text, contains('flagfall'));
      expect(text, contains('R²'));
      expect(text, contains('correlation'));
      expect(text, contains('aeropuerto'));
      expect(text, contains('observed'));
    });

    test('el informe avisa del reparto poco fiable en el propio texto', () {
      final proportional = <FareSample>[
        for (final km in <double>[2, 4, 6, 9, 12, 16, 20, 25])
          sample(km, km * 2),
      ];
      final text = TariffCalibration.fit(proportional).report(proportional);
      expect(text, contains('NOT reliable'));
    });

    test('toTariff acepta las capas que el ajuste no puede aprender', () {
      final tariff = TariffCalibration.fit(theSamples()).toTariff(
        currency: 'USD',
        minimumFare: 150,
        waitingPerMinute: 30,
        rounding: FareRounding.nearest10,
        bands: <TariffBand>[
          const TariffBand(
            name: 'Nocturna',
            startOfDay: Duration(hours: 22),
            endOfDay: Duration(hours: 6),
            multiplier: 1.25,
          ),
        ],
      );

      expect(tariff.baseFare, flagfall);
      expect(tariff.minimumFare, 150);
      expect(tariff.bands, hasLength(1));
      expect(tariff.rounding, FareRounding.nearest10);
    });
  });
}
