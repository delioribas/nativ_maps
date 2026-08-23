// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:nativ_maps/nativ_maps.dart';
import 'package:test/test.dart';

void main() {
  // Se usa hora LOCAL a propósito: las franjas de una tarifa son horas de la
  // ciudad, y así la prueba vale en cualquier huso.
  final salida = DateTime(2026, 8, 23, 21, 50);

  TripSummary viaje({
    double metros = 10000,
    Duration total = const Duration(minutes: 20),
    List<StopPeriod> paradas = const <StopPeriod>[],
    DateTime? desde,
  }) {
    final inicio = desde ?? salida;
    final parado = paradas.fold(
      Duration.zero,
      (Duration s, StopPeriod p) => s + p.duration,
    );
    return TripSummary(
      start: inicio,
      end: inicio.add(total),
      distanceMeters: metros,
      movingDuration: total - parado,
      stoppedDuration: parado,
      stops: paradas,
      track: const <LatLng>[],
      acceptedFixes: 0,
      rejections: const <FixRejection, int>{},
      maxSpeedKmh: 0,
    );
  }

  const basica = Tariff(
    currency: 'EUR',
    baseFare: 250,
    perKilometer: 110,
    perMinute: 35,
  );

  group('Tariff.quote', () {
    test('suma bandera, distancia y tiempo', () {
      final importe = basica.quote(viaje());
      // 250 + 10 km × 110 + 20 min × 35
      expect(importe.total, 2050);
      expect(importe.formattedTotal, '20,50');
      expect(importe.lines, hasLength(3));
    });

    test('el desglose cuadra con el total', () {
      final importe = basica.quote(viaje());
      final suma = importe.lines.fold<int>(0, (s, l) => s + l.amount);
      expect(suma, importe.total);
    });

    test('cada línea dice la cuenta que la produjo', () {
      final importe = basica.quote(viaje());
      final distancia = importe.lines.firstWhere(
        (l) => l.label.contains('distancia'),
      );
      expect(distancia.detail, contains('10.00 km'));
      expect(distancia.detail, contains('1,10'));
    });

    test('aplica el mínimo cuando la carrera es corta', () {
      const corta = Tariff(
        currency: 'EUR',
        baseFare: 250,
        perKilometer: 110,
        minimumFare: 600,
      );
      final importe = corta.quote(
        viaje(metros: 500, total: const Duration(minutes: 3)),
      );
      expect(importe.total, 600);
      expect(importe.lines.map((l) => l.label), contains('Ajuste al mínimo'));
    });

    test('redondea una sola vez y al final', () {
      const redondeada = Tariff(
        currency: 'EUR',
        baseFare: 250,
        perKilometer: 110,
        perMinute: 35,
        rounding: FareRounding.nearestMajor,
      );
      final importe = redondeada.quote(viaje());
      // 20,50 € al euro más cercano son 21,00 €.
      expect(importe.total, 2100);
      final ajuste = importe.lines.firstWhere((l) => l.label == 'Redondeo');
      expect(ajuste.amount, 50);
    });

    test('cobra la espera descontando la cortesía una sola vez', () {
      const conEspera = Tariff(
        currency: 'EUR',
        baseFare: 250,
        waitingPerMinute: 30,
        waitingGrace: Duration(minutes: 3),
      );
      final parada = StopPeriod(
        position: LatLng(-0.1807, -78.4678),
        start: salida.add(const Duration(minutes: 5)),
        end: salida.add(const Duration(minutes: 15)),
      );
      final importe = conEspera.quote(viaje(paradas: <StopPeriod>[parada]));
      // 10 min parado − 3 de cortesía = 7 min × 0,30 €
      final espera = importe.lines.firstWhere(
        (l) => l.label.contains('espera'),
      );
      expect(espera.amount, 210);
    });

    test('parte el viaje cuando cruza a la tarifa nocturna', () {
      const nocturna = TariffBand(
        name: 'Nocturna',
        startOfDay: Duration(hours: 22),
        endOfDay: Duration(hours: 6),
        multiplier: 1.25,
      );
      const conFranjas = Tariff(
        currency: 'EUR',
        baseFare: 250,
        perKilometer: 110,
        perMinute: 35,
        bands: <TariffBand>[nocturna],
      );

      // 21:50 → 22:10: diez minutos de cada tarifa.
      final importe = conFranjas.quote(viaje());

      final etiquetas = importe.lines.map((l) => l.label).toList();
      expect(etiquetas.where((e) => e.startsWith('Nocturna')), hasLength(2));
      expect(etiquetas.where((e) => e.startsWith('Tarifa')), hasLength(2));

      // 250 + (550 + 350) diurnos + (688 + 438) nocturnos
      expect(importe.total, 2276);
    });

    test('cobrarlo todo a la tarifa de salida daría menos', () {
      // La comprobación de que el reparto sirve para algo.
      const nocturna = TariffBand(
        name: 'Nocturna',
        startOfDay: Duration(hours: 22),
        endOfDay: Duration(hours: 6),
        multiplier: 1.25,
      );
      const conFranjas = Tariff(
        currency: 'EUR',
        baseFare: 250,
        perKilometer: 110,
        perMinute: 35,
        bands: <TariffBand>[nocturna],
      );
      expect(
        conFranjas.quote(viaje()).total,
        greaterThan(basica.quote(viaje()).total),
      );
    });

    test('la demanda multiplica lo que debe y respeta lo que no', () {
      const conCargos = Tariff(
        currency: 'EUR',
        baseFare: 250,
        perKilometer: 110,
        surcharges: <Surcharge>[
          Surcharge(name: 'Aeropuerto', amount: 300),
          Surcharge(name: 'Reserva', amount: 100, surgeable: true),
        ],
      );
      final importe = conCargos.quote(
        viaje(total: const Duration(minutes: 20)),
        surgeMultiplier: 1.5,
      );
      // (250 + 1100 + 100) × 1,5 = 2175, más 300 de aeropuerto sin multiplicar
      expect(importe.total, 2475);
    });

    test('los peajes no los toca ni la demanda ni el mínimo', () {
      final importe = basica.quote(viaje(), tolls: 420);
      expect(importe.total, 2050 + 420);
      expect(importe.lines.last.label, 'Peajes');
    });

    test('rechaza una demanda no positiva', () {
      expect(
        () => basica.quote(viaje(), surgeMultiplier: 0),
        throwsArgumentError,
      );
    });

    test('el recibo enseña todas las líneas', () {
      final recibo = basica.quote(viaje()).toReceipt();
      expect(recibo, contains('Bajada de bandera'));
      expect(recibo, contains('TOTAL'));
      expect(recibo, contains('EUR'));
    });

    test('una moneda sin decimales no inventa céntimos', () {
      const pesos = Tariff(
        currency: 'CLP',
        baseFare: 400,
        perKilometer: 700,
        minorUnitDigits: 0,
      );
      final importe = pesos.quote(viaje());
      expect(importe.formattedTotal, '7400');
      expect(importe.formattedTotal, isNot(contains(',')));
    });
  });

  group('TariffBand.appliesAt', () {
    const nocturna = TariffBand(
      name: 'Nocturna',
      startOfDay: Duration(hours: 22),
      endOfDay: Duration(hours: 6),
    );

    test('cubre las dos mitades de una franja que cruza la medianoche', () {
      expect(nocturna.appliesAt(DateTime(2026, 8, 23, 23)), isTrue);
      expect(nocturna.appliesAt(DateTime(2026, 8, 24, 2)), isTrue);
      expect(nocturna.appliesAt(DateTime(2026, 8, 24, 12)), isFalse);
      expect(nocturna.appliesAt(DateTime(2026, 8, 23, 21, 59)), isFalse);
    });

    test('el tramo de madrugada pertenece al día anterior', () {
      // Nocturna solo de viernes. La 01:00 del sábado sigue siendo la
      // nocturna del viernes: si no, el pasajero paga diurna de madrugada.
      const soloViernes = TariffBand(
        name: 'Viernes noche',
        startOfDay: Duration(hours: 22),
        endOfDay: Duration(hours: 6),
        weekdays: <int>{DateTime.friday},
      );
      expect(soloViernes.appliesAt(DateTime(2026, 8, 21, 23)), isTrue);
      expect(soloViernes.appliesAt(DateTime(2026, 8, 22, 1)), isTrue);
      expect(soloViernes.appliesAt(DateTime(2026, 8, 22, 23)), isFalse);
    });

    test('una franja normal se queda dentro de su día', () {
      const punta = TariffBand(
        name: 'Hora punta',
        startOfDay: Duration(hours: 7),
        endOfDay: Duration(hours: 10),
        weekdays: <int>{1, 2, 3, 4, 5},
      );
      expect(punta.appliesAt(DateTime(2026, 8, 24, 8)), isTrue);
      expect(punta.appliesAt(DateTime(2026, 8, 24, 11)), isFalse);
      expect(punta.appliesAt(DateTime(2026, 8, 23, 8)), isFalse);
    });
  });

  group('Tariff.estimate', () {
    test('estima antes de empezar, sin paradas', () {
      final previo = basica.estimate(
        distanceMeters: 10000,
        duration: const Duration(minutes: 20),
        departure: DateTime(2026, 8, 23, 12),
      );
      expect(previo.total, 2050);
    });
  });
}
