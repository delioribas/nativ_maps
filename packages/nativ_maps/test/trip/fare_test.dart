// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:nativ_maps/nativ_maps.dart';
import 'package:test/test.dart';

void main() {
  // Se usa hora LOCAL a propósito: las franjas de una tarifa son horas de la
  // ciudad, y así la prueba vale en cualquier huso.
  final departure = DateTime(2026, 8, 23, 21, 50);

  TripSummary trip({
    double meters = 10000,
    Duration total = const Duration(minutes: 20),
    List<StopPeriod> stops = const <StopPeriod>[],
    DateTime? from,
  }) {
    final start = from ?? departure;
    final stopped = stops.fold(
      Duration.zero,
      (Duration s, StopPeriod p) => s + p.duration,
    );
    return TripSummary(
      start: start,
      end: start.add(total),
      distanceMeters: meters,
      movingDuration: total - stopped,
      stoppedDuration: stopped,
      stops: stops,
      track: const <LatLng>[],
      acceptedFixes: 0,
      rejections: const <FixRejection, int>{},
      maxSpeedKmh: 0,
    );
  }

  const basicTariff = Tariff(
    currency: 'EUR',
    baseFare: 250,
    perKilometer: 110,
    perMinute: 35,
  );

  group('Tariff.quote', () {
    test('suma bandera, distancia y tiempo', () {
      final amount = basicTariff.quote(trip());
      // 250 + 10 km × 110 + 20 min × 35
      expect(amount.total, 2050);
      expect(amount.formattedTotal, '20,50');
      expect(amount.lines, hasLength(3));
    });

    test('el desglose cuadra con el total', () {
      final amount = basicTariff.quote(trip());
      final sum = amount.lines.fold<int>(0, (s, l) => s + l.amount);
      expect(sum, amount.total);
    });

    test('cada línea dice la cuenta que la produjo', () {
      final amount = basicTariff.quote(trip());
      final distance = amount.lines.firstWhere(
        (l) => l.label.contains('distance'),
      );
      expect(distance.detail, contains('10.00 km'));
      expect(distance.detail, contains('1,10'));
    });

    test('aplica el mínimo cuando la carrera es corta', () {
      const shortTrip = Tariff(
        currency: 'EUR',
        baseFare: 250,
        perKilometer: 110,
        minimumFare: 600,
      );
      final amount = shortTrip.quote(
        trip(meters: 500, total: const Duration(minutes: 3)),
      );
      expect(amount.total, 600);
      expect(amount.lines.map((l) => l.label), contains('Minimum fare'));
    });

    test('redondea una sola vez y al final', () {
      const roundedTariff = Tariff(
        currency: 'EUR',
        baseFare: 250,
        perKilometer: 110,
        perMinute: 35,
        rounding: FareRounding.nearestMajor,
      );
      final amount = roundedTariff.quote(trip());
      // 20,50 € al euro más cercano son 21,00 €.
      expect(amount.total, 2100);
      final fit = amount.lines.firstWhere((l) => l.label == 'Rounding');
      expect(fit.amount, 50);
    });

    test('cobra la espera descontando la cortesía una sola vez', () {
      const withWaiting = Tariff(
        currency: 'EUR',
        baseFare: 250,
        waitingPerMinute: 30,
        waitingGrace: Duration(minutes: 3),
      );
      final stop = StopPeriod(
        position: LatLng(-0.1807, -78.4678),
        start: departure.add(const Duration(minutes: 5)),
        end: departure.add(const Duration(minutes: 15)),
      );
      final amount = withWaiting.quote(trip(stops: <StopPeriod>[stop]));
      // 10 min parado − 3 de cortesía = 7 min × 0,30 €
      final waiting = amount.lines.firstWhere(
        (l) => l.label.contains('waiting'),
      );
      expect(waiting.amount, 210);
    });

    test('parte el viaje cuando cruza a la tarifa nocturna', () {
      const night = TariffBand(
        name: 'Nocturna',
        startOfDay: Duration(hours: 22),
        endOfDay: Duration(hours: 6),
        multiplier: 1.25,
      );
      const withBands = Tariff(
        currency: 'EUR',
        baseFare: 250,
        perKilometer: 110,
        perMinute: 35,
        bands: <TariffBand>[night],
      );

      // 21:50 → 22:10: diez minutos de cada tarifa.
      final amount = withBands.quote(trip());

      final labels = amount.lines.map((l) => l.label).toList();
      expect(labels.where((e) => e.startsWith('Nocturna')), hasLength(2));
      expect(labels.where((e) => e.startsWith('Standard')), hasLength(2));

      // 250 + (550 + 350) diurnos + (688 + 438) nocturnos
      expect(amount.total, 2276);
    });

    test('cobrarlo todo a la tarifa de salida daría menos', () {
      // La comprobación de que el reparto sirve para algo.
      const night = TariffBand(
        name: 'Nocturna',
        startOfDay: Duration(hours: 22),
        endOfDay: Duration(hours: 6),
        multiplier: 1.25,
      );
      const withBands = Tariff(
        currency: 'EUR',
        baseFare: 250,
        perKilometer: 110,
        perMinute: 35,
        bands: <TariffBand>[night],
      );
      expect(
        withBands.quote(trip()).total,
        greaterThan(basicTariff.quote(trip()).total),
      );
    });

    test('la demanda multiplica lo que debe y respeta lo que no', () {
      const withSurcharges = Tariff(
        currency: 'EUR',
        baseFare: 250,
        perKilometer: 110,
        surcharges: <Surcharge>[
          Surcharge(name: 'Aeropuerto', amount: 300),
          Surcharge(name: 'Reserva', amount: 100, surgeable: true),
        ],
      );
      final amount = withSurcharges.quote(
        trip(total: const Duration(minutes: 20)),
        surgeMultiplier: 1.5,
      );
      // (250 + 1100 + 100) × 1,5 = 2175, más 300 de aeropuerto sin multiplicar
      expect(amount.total, 2475);
    });

    test('los peajes no los toca ni la demanda ni el mínimo', () {
      final amount = basicTariff.quote(trip(), tolls: 420);
      expect(amount.total, 2050 + 420);
      expect(amount.lines.last.label, 'Tolls');
    });

    test('rechaza una demanda no positiva', () {
      expect(
        () => basicTariff.quote(trip(), surgeMultiplier: 0),
        throwsArgumentError,
      );
    });

    test('el recibo enseña todas las líneas', () {
      final receipt = basicTariff.quote(trip()).toReceipt();
      expect(receipt, contains('Flagfall'));
      expect(receipt, contains('TOTAL'));
      expect(receipt, contains('EUR'));
    });

    test('una moneda sin decimales no inventa céntimos', () {
      const clp = Tariff(
        currency: 'CLP',
        baseFare: 400,
        perKilometer: 700,
        minorUnitDigits: 0,
      );
      final amount = clp.quote(trip());
      expect(amount.formattedTotal, '7400');
      expect(amount.formattedTotal, isNot(contains(',')));
    });
  });

  group('TariffBand.appliesAt', () {
    const night = TariffBand(
      name: 'Nocturna',
      startOfDay: Duration(hours: 22),
      endOfDay: Duration(hours: 6),
    );

    test('cubre las dos mitades de una franja que cruza la medianoche', () {
      expect(night.appliesAt(DateTime(2026, 8, 23, 23)), isTrue);
      expect(night.appliesAt(DateTime(2026, 8, 24, 2)), isTrue);
      expect(night.appliesAt(DateTime(2026, 8, 24, 12)), isFalse);
      expect(night.appliesAt(DateTime(2026, 8, 23, 21, 59)), isFalse);
    });

    test('el tramo de madrugada pertenece al día anterior', () {
      // Nocturna solo de viernes. La 01:00 del sábado sigue siendo la
      // nocturna del viernes: si no, el pasajero paga diurna de madrugada.
      const fridayOnly = TariffBand(
        name: 'Viernes noche',
        startOfDay: Duration(hours: 22),
        endOfDay: Duration(hours: 6),
        weekdays: <int>{DateTime.friday},
      );
      expect(fridayOnly.appliesAt(DateTime(2026, 8, 21, 23)), isTrue);
      expect(fridayOnly.appliesAt(DateTime(2026, 8, 22, 1)), isTrue);
      expect(fridayOnly.appliesAt(DateTime(2026, 8, 22, 23)), isFalse);
    });

    test('una franja normal se queda dentro de su día', () {
      const peak = TariffBand(
        name: 'Hora punta',
        startOfDay: Duration(hours: 7),
        endOfDay: Duration(hours: 10),
        weekdays: <int>{1, 2, 3, 4, 5},
      );
      expect(peak.appliesAt(DateTime(2026, 8, 24, 8)), isTrue);
      expect(peak.appliesAt(DateTime(2026, 8, 24, 11)), isFalse);
      expect(peak.appliesAt(DateTime(2026, 8, 23, 8)), isFalse);
    });
  });

  group('Tariff.estimate', () {
    test('estima antes de empezar, sin paradas', () {
      final upfront = basicTariff.estimate(
        distanceMeters: 10000,
        duration: const Duration(minutes: 20),
        departure: DateTime(2026, 8, 23, 12),
      );
      expect(upfront.total, 2050);
    });
  });
}
