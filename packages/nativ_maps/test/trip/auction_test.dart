// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:nativ_maps/nativ_maps.dart';
import 'package:test/test.dart';

void main() {
  final quito = LatLng(-0.1807, -78.4678);
  final now = DateTime.utc(2026, 8, 23, 10);

  RideRequest request() => RideRequest(
    id: 'c-1',
    pickup: quito,
    dropoff: quito.offset(4200, 90),
    proposedFare: 500,
    currency: 'USD',
    createdAt: now,
  );

  DriverBid offer(
    String driver,
    int amount, {
    int minutos = 4,
    double? score,
    DateTime? cuando,
  }) => DriverBid(
    driverId: driver,
    requestId: 'c-1',
    amount: amount,
    etaToPickup: Duration(minutes: minutos),
    createdAt: cuando ?? now,
    driverRating: score,
  );

  group('RideAuction', () {
    test('recoge ofertas y las devuelve vivas', () {
      final auction = RideAuction(request: request())
        ..bid(offer('a', 500), now: now)
        ..bid(offer('b', 650), now: now);
      expect(auction.liveBids(now), hasLength(2));
    });

    test('volver a ofertar sustituye, no acumula', () {
      // Es lo que hace falta para poder bajar el precio: si se acumulase, el
      // pasajero vería dos ofertas del mismo conductor.
      final auction = RideAuction(request: request())
        ..bid(offer('a', 650), now: now)
        ..bid(offer('a', 550), now: now);
      final live = auction.liveBids(now);
      expect(live, hasLength(1));
      expect(live.single.amount, 550);
    });

    test('una oferta caducada deja de contar', () {
      final auction = RideAuction(request: request())
        ..bid(offer('a', 500), now: now);
      final later = now.add(const Duration(minutes: 3));
      expect(auction.liveBids(later), isEmpty);
    });

    test('no se acepta una oferta caducada', () {
      // Aceptarla sería prometerle al pasajero un tiempo de llegada que el
      // conductor ya no puede cumplir: lleva tres minutos conduciendo.
      final auction = RideAuction(request: request())
        ..bid(offer('a', 500), now: now);
      expect(
        () => auction.accept('a', now: now.add(const Duration(minutes: 3))),
        throwsStateError,
      );
    });

    test('aceptar cierra la subasta', () {
      final auction = RideAuction(request: request())
        ..bid(offer('a', 500), now: now);
      final winner = auction.accept('a', now: now);

      expect(winner.driverId, 'a');
      expect(auction.winner, isNotNull);
      expect(auction.stateAt(now), AuctionState.accepted);
      expect(() => auction.bid(offer('b', 400), now: now), throwsStateError);
    });

    test('caduca sola al pasar su tiempo', () {
      final auction = RideAuction(
        request: request(),
        duration: const Duration(minutes: 5),
      );
      expect(auction.stateAt(now), AuctionState.open);
      expect(
        auction.stateAt(now.add(const Duration(minutes: 6))),
        AuctionState.expired,
      );
    });

    test('rechaza una oferta de otra petición', () {
      final auction = RideAuction(request: request());
      expect(
        () => auction.bid(
          DriverBid(
            driverId: 'a',
            requestId: 'OTRA',
            amount: 500,
            etaToPickup: const Duration(minutes: 3),
            createdAt: now,
          ),
          now: now,
        ),
        throwsArgumentError,
      );
    });

    test('retirar quita la oferta', () {
      final auction = RideAuction(request: request())
        ..bid(offer('a', 500), now: now);
      expect(auction.withdraw('a'), isTrue);
      expect(auction.withdraw('a'), isFalse);
      expect(auction.liveBids(now), isEmpty);
    });

    test('cancelar impide seguir ofertando', () {
      final auction = RideAuction(request: request())..cancel();
      expect(auction.stateAt(now), AuctionState.cancelled);
    });
  });

  group('BidRanking', () {
    test('solo por precio ordena de más barata a más cara', () {
      const ranking = BidRanking(priceWeight: 1, etaWeight: 0, ratingWeight: 0);
      final ordered = ranking.sort(<DriverBid>[
        offer('caro', 900),
        offer('barato', 500),
        offer('medio', 700),
      ], now: now);
      expect(ordered.map((o) => o.driverId), <String>[
        'barato',
        'medio',
        'caro',
      ]);
    });

    test('la espera puede ganarle al precio', () {
      const ranking = BidRanking(priceWeight: 1, etaWeight: 3, ratingWeight: 0);
      final ordered = ranking.sort(<DriverBid>[
        offer('lento', 500, minutos: 20),
        offer('rapido', 700, minutos: 2),
      ], now: now);
      expect(ordered.first.driverId, 'rapido');
    });

    test('quita las caducadas antes de ordenar', () {
      const ranking = BidRanking();
      final ordered = ranking.sort(<DriverBid>[
        offer('vieja', 400, cuando: now.subtract(const Duration(hours: 1))),
        offer('viva', 800),
      ], now: now);
      expect(ordered.map((o) => o.driverId), <String>['viva']);
    });

    test('con una sola oferta no hay nada que normalizar', () {
      expect(
        const BidRanking().sort(<DriverBid>[offer('a', 500)], now: now),
        hasLength(1),
      );
    });
  });

  group('BidAdvisor', () {
    const advisor = BidAdvisor(
      currency: 'EUR',
      minorUnitDigits: 2,
      economics: DriverEconomics(costPerKilometer: 20, minimumNetPerHour: 1500),
    );

    test('la carrera que paga menos puede rendir más por hora', () {
      // La tabla que sale en la documentación de BidAdvisor, comprobada.
      final a = advisor.evaluate(
        fare: 800,
        deadheadMeters: 5000,
        deadheadDuration: const Duration(minutes: 12),
        tripMeters: 6000,
        tripDuration: const Duration(minutes: 10),
      );
      final b = advisor.evaluate(
        fare: 500,
        deadheadMeters: 800,
        deadheadDuration: const Duration(minutes: 2),
        tripMeters: 4200,
        tripDuration: const Duration(minutes: 10),
      );

      expect(a.drivingCost, 220);
      expect(a.net, 580);
      expect(a.netPerHour, 1582);

      expect(b.drivingCost, 100);
      expect(b.net, 400);
      expect(b.netPerHour, 2000);

      // El importe suelto dice A; el neto por hora dice B.
      expect(a.gross, greaterThan(b.gross));
      expect(b.netPerHour, greaterThan(a.netPerHour));
    });

    test('marca como no rentable la que no llega al mínimo por hora', () {
      final poor = advisor.evaluate(
        fare: 400,
        deadheadMeters: 5000,
        deadheadDuration: const Duration(minutes: 12),
        tripMeters: 6000,
        tripDuration: const Duration(minutes: 10),
      );
      expect(poor.worthIt, isFalse);
      expect(poor.deadheadShare, closeTo(0.4545, 0.001));
    });

    test('descuenta la comisión de la plataforma', () {
      const withCommission = BidAdvisor(
        currency: 'EUR',
        minorUnitDigits: 2,
        economics: DriverEconomics(costPerKilometer: 20, commissionRate: 0.25),
      );
      final r = withCommission.evaluate(
        fare: 1000,
        deadheadMeters: 0,
        deadheadDuration: Duration.zero,
        tripMeters: 5000,
        tripDuration: const Duration(minutes: 10),
      );
      expect(r.commission, 250);
      expect(r.net, 1000 - 250 - 100);
    });

    test('breakEvenFare da el importe que hay que contraofertar', () {
      final floorPrice = advisor.breakEvenFare(
        deadheadMeters: 5000,
        deadheadDuration: const Duration(minutes: 12),
        tripMeters: 6000,
        tripDuration: const Duration(minutes: 10),
      );
      // Y a ese importe la carrera ya compensa.
      final r = advisor.evaluate(
        fare: floorPrice,
        deadheadMeters: 5000,
        deadheadDuration: const Duration(minutes: 12),
        tripMeters: 6000,
        tripDuration: const Duration(minutes: 10),
      );
      expect(r.worthIt, isTrue);
      expect(floorPrice, 770);
    });

    test('el factor de vuelta encarece las carreras a las afueras', () {
      const withReturnLeg = BidAdvisor(
        currency: 'EUR',
        minorUnitDigits: 2,
        economics: DriverEconomics(costPerKilometer: 20, returnFactor: 1.0),
      );
      final r = withReturnLeg.evaluate(
        fare: 800,
        deadheadMeters: 5000,
        deadheadDuration: const Duration(minutes: 12),
        tripMeters: 6000,
        tripDuration: const Duration(minutes: 10),
      );
      // 5 + 6 + 5 de vuelta = 16 km
      expect(r.drivingCost, 320);
    });
  });
}
