// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:nativ_maps/nativ_maps.dart';
import 'package:test/test.dart';

void main() {
  final quito = LatLng(-0.1807, -78.4678);

  const tariff = Tariff(
    currency: 'USD',
    baseFare: 250,
    perKilometer: 110,
    perMinute: 35,
  );

  const economics = DriverEconomics(
    costPerKilometer: 20,
    minimumNetPerHour: 1200,
  );

  const advisor = PriceAdvisor(tariff: tariff, economics: economics);

  // Un trayecto de 6 km en 12 minutos.
  // Referencia = 250 + 6×110 + 12×35 = 1330
  const meters = 6000.0;
  const duration = Duration(minutes: 12);

  DriverCandidate driver(
    String id,
    double metrosHasta,
    int minutosHasta, {
    bool refinado = true,
  }) => DriverCandidate(
    driver: DriverLocation(
      driverId: id,
      position: quito.offset(metrosHasta, 90),
    ),
    straightLineMeters: metrosHasta,
    drivingMeters: refinado ? metrosHasta : null,
    drivingDuration: refinado ? Duration(minutes: minutosHasta) : null,
  );

  group('referencia', () {
    test('sin mercado el precio es la tarifa', () {
      final p = advisor.suggest(distanceMeters: meters, duration: duration);
      expect(p.reference, 1330);
      expect(p.recommended, 1330);
      expect(p.demandMultiplier, 1.0);
      expect(p.factors, isEmpty);
    });

    test('el mínimo cae por debajo del recomendado', () {
      final p = advisor.suggest(distanceMeters: meters, duration: duration);
      expect(p.minimum, lessThan(p.recommended));
      expect(p.minimum, (1330 * 0.85).round());
    });
  });

  group('suelo de oferta', () {
    test('el mínimo es lo que necesita el conductor más barato', () {
      // A: 1 km y 3 min → con aversión 1,6 son 4,8 min de tiempo muerto.
      //    coste 7 km × 0,20 = 1,40 · objetivo 12/h × 0,28 h = 3,36
      //    break-even = 4,76
      final p = advisor.suggest(
        distanceMeters: meters,
        duration: duration,
        nearbyDrivers: <DriverCandidate>[
          driver('a', 1000, 3),
          driver('b', 8000, 20),
        ],
      );
      expect(p.minimum, 476);
    });

    test(
      'con todos los coches lejos el precio sube por encima de la tarifa',
      () {
        // El caso que la línea recta y una fórmula fija no ven: la tarifa dice
        // 13,30 pero al conductor más cercano le cuesta media hora llegar, así
        // que a ese precio no viene nadie.
        final p = advisor.suggest(
          distanceMeters: meters,
          duration: duration,
          nearbyDrivers: <DriverCandidate>[
            driver('lejos1', 15000, 35),
            driver('lejos2', 18000, 40),
          ],
        );
        expect(p.recommended, greaterThan(p.reference));
        expect(p.factors.map((f) => f.name), contains('Distant drivers'));
      },
    );

    test('con coches al lado no se infla el precio', () {
      final p = advisor.suggest(
        distanceMeters: meters,
        duration: duration,
        nearbyDrivers: <DriverCandidate>[
          driver('a', 500, 2),
          driver('b', 900, 3),
        ],
      );
      expect(p.recommended, p.reference);
      expect(p.factors.map((f) => f.name), isNot(contains('Distant drivers')));
    });
  });

  group('demanda', () {
    test('el multiplicador sale del ratio peticiones por conductor', () {
      final p = advisor.suggest(
        distanceMeters: meters,
        duration: duration,
        market: const MarketConditions(availableDrivers: 5, openRequests: 10),
      );
      // ratio 2 → 2^0.6 ≈ 1,516
      expect(p.demandMultiplier, closeTo(1.516, 0.01));
      expect(p.recommended, closeTo(1330 * 1.516, 5));
      final factor = p.factors.firstWhere((f) => f.name == 'Demand');
      expect(factor.detail, contains('10 requests'));
    });

    test('el mercado equilibrado no mueve el precio', () {
      final p = advisor.suggest(
        distanceMeters: meters,
        duration: duration,
        market: const MarketConditions(availableDrivers: 10, openRequests: 10),
      );
      expect(p.demandMultiplier, 1.0);
    });

    test('más oferta que demanda tampoco lo baja', () {
      // El precio no cae por debajo de la tarifa: eso sería empujar al
      // conductor por debajo de lo que la tarifa dice que vale el trayecto.
      final p = advisor.suggest(
        distanceMeters: meters,
        duration: duration,
        market: const MarketConditions(availableDrivers: 20, openRequests: 2),
      );
      expect(p.demandMultiplier, 1.0);
      expect(p.recommended, 1330);
    });

    test('sin ningún conductor libre se va al techo', () {
      final p = advisor.suggest(
        distanceMeters: meters,
        duration: duration,
        market: const MarketConditions(openRequests: 8),
      );
      expect(p.demandMultiplier, 2.5);
      final factor = p.factors.firstWhere((f) => f.name == 'Demand');
      expect(factor.detail, contains('cap'));
    });

    test('el techo se respeta con un desequilibrio enorme', () {
      const withCap = PriceAdvisor(
        tariff: tariff,
        economics: economics,
        maxSurge: 1.8,
      );
      final p = withCap.suggest(
        distanceMeters: meters,
        duration: duration,
        market: const MarketConditions(availableDrivers: 1, openRequests: 60),
      );
      expect(p.demandMultiplier, 1.8);
    });

    test('las señales con nombre multiplican y quedan escritas', () {
      final p = advisor.suggest(
        distanceMeters: meters,
        duration: duration,
        market: const MarketConditions(
          signals: <DemandSignal>[DemandSignal.rain, DemandSignal.event],
        ),
      );
      expect(p.demandMultiplier, closeTo(1.15 * 1.30, 0.001));
      expect(
        p.factors.map((f) => f.name),
        containsAll(<String>['Rain', 'Event']),
      );
    });
  });

  group('vuelta de vacío', () {
    test('añade una prima proporcional a la probabilidad', () {
      final p = advisor.suggest(
        distanceMeters: meters,
        duration: duration,
        market: const MarketConditions(returnEmptyProbability: 0.5),
      );
      // 6 km × 0,20 × 0,5 = 0,60 sobre una referencia de 13,30
      expect(p.demandMultiplier, closeTo(1 + 60 / 1330, 0.001));
      expect(p.factors.map((f) => f.name), contains('Empty return'));
    });

    test('sin probabilidad no hay prima', () {
      final p = advisor.suggest(distanceMeters: meters, duration: duration);
      expect(p.factors.map((f) => f.name), isNot(contains('Empty return')));
    });
  });

  group('tráfico', () {
    test('no se cobra dos veces si la tarifa ya cobra por minuto', () {
      final p = advisor.suggest(
        distanceMeters: meters,
        duration: duration,
        market: const MarketConditions(congestionFactor: 1.6),
      );
      expect(p.factors.map((f) => f.name), isNot(contains('Traffic')));
      expect(p.demandMultiplier, 1.0);
    });

    test('sí se cobra si la tarifa es solo por distancia', () {
      const distanceOnlyAdvisor = PriceAdvisor(
        tariff: Tariff(currency: 'USD', baseFare: 250, perKilometer: 110),
        economics: economics,
      );
      final p = distanceOnlyAdvisor.suggest(
        distanceMeters: meters,
        duration: duration,
        market: const MarketConditions(congestionFactor: 1.6),
      );
      expect(p.demandMultiplier, closeTo(1.6, 0.001));
      final factor = p.factors.firstWhere((f) => f.name == 'Traffic');
      expect(factor.detail, contains('60 %'));
    });
  });

  group('previsión de aceptación', () {
    final nearby = <DriverCandidate>[
      driver('a', 1000, 3),
      driver('b', 4000, 10),
      driver('c', 12000, 28),
    ];

    test('con conductores reales cuenta, no estima', () {
      final p = advisor.suggest(
        distanceMeters: meters,
        duration: duration,
        nearbyDrivers: nearby,
      );
      expect(p.forecast.estimated, isFalse);
      expect(p.forecast.driversConsidered, 3);
    });

    test('sin conductores marca que es una estimación', () {
      final p = advisor.suggest(distanceMeters: meters, duration: duration);
      expect(p.forecast.estimated, isTrue);
      expect(p.forecast.driversConsidered, 0);
    });

    test('un conductor sin refinar contamina la previsión, y se dice', () {
      final p = advisor.suggest(
        distanceMeters: meters,
        duration: duration,
        nearbyDrivers: <DriverCandidate>[
          driver('a', 1000, 3),
          driver('sinRefinar', 2000, 0, refinado: false),
        ],
      );
      expect(p.forecast.estimated, isTrue);
      expect(p.forecast.driversConsidered, 2);
    });

    test('subir el precio no puede reducir cuántos aceptan', () {
      var previous = -1;
      for (final amount in <int>[200, 500, 900, 1400, 2500, 5000]) {
        final f = advisor.forecast(
          offered: amount,
          distanceMeters: meters,
          duration: duration,
          nearbyDrivers: nearby,
        );
        expect(f.driversLikelyToAccept, greaterThanOrEqualTo(previous));
        previous = f.driversLikelyToAccept;
      }
      expect(previous, 3);
    });

    test('el tiempo de llegada es el del más cercano que aceptaría', () {
      // A 4,76 solo acepta el de tres minutos.
      final cheap = advisor.forecast(
        offered: 480,
        distanceMeters: meters,
        duration: duration,
        nearbyDrivers: nearby,
      );
      expect(cheap.driversLikelyToAccept, 1);
      expect(cheap.expectedPickup, const Duration(minutes: 3));

      // A un precio alto aceptan todos, y sigue viniendo el más cercano.
      final generous = advisor.forecast(
        offered: 5000,
        distanceMeters: meters,
        duration: duration,
        nearbyDrivers: nearby,
      );
      expect(generous.driversLikelyToAccept, 3);
      expect(generous.expectedPickup, const Duration(minutes: 3));
    });

    test('por debajo del mínimo no acepta nadie', () {
      final p = advisor.suggest(
        distanceMeters: meters,
        duration: duration,
        nearbyDrivers: nearby,
      );
      final f = advisor.forecast(
        offered: p.minimum - 1,
        distanceMeters: meters,
        duration: duration,
        nearbyDrivers: nearby,
      );
      expect(f.driversLikelyToAccept, 0);
      expect(f.expectedPickup, isNull);
    });

    test('la curva de respaldo crece con el importe', () {
      double p(int amount) => advisor
          .forecast(offered: amount, distanceMeters: meters, duration: duration)
          .probability;
      expect(p(800), lessThan(p(1330)));
      expect(p(1330), lessThan(p(2000)));
      expect(p(1330), greaterThan(0.5));
    });
  });

  group('el precio de la prisa', () {
    test('para que venga el más cercano se paga su reserva con margen', () {
      // El más cercano en tiempo es el caro de traer: está a 25 min.
      final p = advisor.suggest(
        distanceMeters: meters,
        duration: duration,
        nearbyDrivers: <DriverCandidate>[
          driver('cercanoEnTiempo', 9000, 25),
          driver('lejosEnTiempo', 20000, 45),
        ],
      );
      expect(p.fast, greaterThanOrEqualTo(p.recommended));
      // Y a ese precio, acepta.
      final f = advisor.forecast(
        offered: p.fast,
        distanceMeters: meters,
        duration: duration,
        nearbyDrivers: <DriverCandidate>[driver('cercanoEnTiempo', 9000, 25)],
      );
      expect(f.driversLikelyToAccept, 1);
    });

    test('sin conductores el precio de la prisa es el recomendado', () {
      final p = advisor.suggest(distanceMeters: meters, duration: duration);
      expect(p.fast, p.recommended);
    });
  });

  group('peajes y tasas', () {
    test('van aparte y no entran en el precio, como en inDrive', () {
      final p = advisor.suggest(
        distanceMeters: meters,
        duration: duration,
        tolls: 300,
        fees: 150,
      );
      expect(p.recommended, 1330);
      expect(p.extrasPaidSeparately, 450);
    });
  });

  group('explicación', () {
    test('el desglose enseña cada factor que movió el precio', () {
      final text = advisor
          .suggest(
            distanceMeters: meters,
            duration: duration,
            nearbyDrivers: <DriverCandidate>[driver('a', 1000, 3)],
            market: const MarketConditions(
              availableDrivers: 4,
              openRequests: 8,
              signals: <DemandSignal>[DemandSignal.rain],
            ),
            tolls: 300,
          )
          .explain();

      expect(text, contains('Reference'));
      expect(text, contains('Demand'));
      expect(text, contains('Rain'));
      expect(text, contains('Minimum bid'));
      expect(text, contains('Recommended'));
      expect(text, contains('paid separately'));
    });

    test('el importe se formatea según la moneda', () {
      const clp = PriceAdvisor(
        tariff: Tariff(
          currency: 'CLP',
          baseFare: 400,
          perKilometer: 700,
          minorUnitDigits: 0,
        ),
        economics: economics,
      );
      final p = clp.suggest(distanceMeters: meters, duration: duration);
      expect(p.formatAmount(p.recommended), isNot(contains(',')));
    });
  });
}
