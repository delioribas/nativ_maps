// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:nativ_maps/nativ_maps.dart';
import 'package:test/test.dart';

void main() {
  final quito = LatLng(-0.1807, -78.4678);
  final ahora = DateTime.utc(2026, 8, 23, 10);

  RideRequest peticion() => RideRequest(
    id: 'c-1',
    pickup: quito,
    dropoff: quito.offset(4200, 90),
    proposedFare: 500,
    currency: 'USD',
    createdAt: ahora,
  );

  DriverBid oferta(
    String conductor,
    int importe, {
    int minutos = 4,
    double? nota,
    DateTime? cuando,
  }) => DriverBid(
    driverId: conductor,
    requestId: 'c-1',
    amount: importe,
    etaToPickup: Duration(minutes: minutos),
    createdAt: cuando ?? ahora,
    driverRating: nota,
  );

  group('RideAuction', () {
    test('recoge ofertas y las devuelve vivas', () {
      final subasta = RideAuction(request: peticion())
        ..bid(oferta('a', 500), now: ahora)
        ..bid(oferta('b', 650), now: ahora);
      expect(subasta.liveBids(ahora), hasLength(2));
    });

    test('volver a ofertar sustituye, no acumula', () {
      // Es lo que hace falta para poder bajar el precio: si se acumulase, el
      // pasajero vería dos ofertas del mismo conductor.
      final subasta = RideAuction(request: peticion())
        ..bid(oferta('a', 650), now: ahora)
        ..bid(oferta('a', 550), now: ahora);
      final vivas = subasta.liveBids(ahora);
      expect(vivas, hasLength(1));
      expect(vivas.single.amount, 550);
    });

    test('una oferta caducada deja de contar', () {
      final subasta = RideAuction(request: peticion())
        ..bid(oferta('a', 500), now: ahora);
      final tarde = ahora.add(const Duration(minutes: 3));
      expect(subasta.liveBids(tarde), isEmpty);
    });

    test('no se acepta una oferta caducada', () {
      // Aceptarla sería prometerle al pasajero un tiempo de llegada que el
      // conductor ya no puede cumplir: lleva tres minutos conduciendo.
      final subasta = RideAuction(request: peticion())
        ..bid(oferta('a', 500), now: ahora);
      expect(
        () => subasta.accept('a', now: ahora.add(const Duration(minutes: 3))),
        throwsStateError,
      );
    });

    test('aceptar cierra la subasta', () {
      final subasta = RideAuction(request: peticion())
        ..bid(oferta('a', 500), now: ahora);
      final ganadora = subasta.accept('a', now: ahora);

      expect(ganadora.driverId, 'a');
      expect(subasta.winner, isNotNull);
      expect(subasta.stateAt(ahora), AuctionState.accepted);
      expect(() => subasta.bid(oferta('b', 400), now: ahora), throwsStateError);
    });

    test('caduca sola al pasar su tiempo', () {
      final subasta = RideAuction(
        request: peticion(),
        duration: const Duration(minutes: 5),
      );
      expect(subasta.stateAt(ahora), AuctionState.open);
      expect(
        subasta.stateAt(ahora.add(const Duration(minutes: 6))),
        AuctionState.expired,
      );
    });

    test('rechaza una oferta de otra petición', () {
      final subasta = RideAuction(request: peticion());
      expect(
        () => subasta.bid(
          DriverBid(
            driverId: 'a',
            requestId: 'OTRA',
            amount: 500,
            etaToPickup: const Duration(minutes: 3),
            createdAt: ahora,
          ),
          now: ahora,
        ),
        throwsArgumentError,
      );
    });

    test('retirar quita la oferta', () {
      final subasta = RideAuction(request: peticion())
        ..bid(oferta('a', 500), now: ahora);
      expect(subasta.withdraw('a'), isTrue);
      expect(subasta.withdraw('a'), isFalse);
      expect(subasta.liveBids(ahora), isEmpty);
    });

    test('cancelar impide seguir ofertando', () {
      final subasta = RideAuction(request: peticion())..cancel();
      expect(subasta.stateAt(ahora), AuctionState.cancelled);
    });
  });

  group('BidRanking', () {
    test('solo por precio ordena de más barata a más cara', () {
      const criterio = BidRanking(
        priceWeight: 1,
        etaWeight: 0,
        ratingWeight: 0,
      );
      final orden = criterio.sort(<DriverBid>[
        oferta('caro', 900),
        oferta('barato', 500),
        oferta('medio', 700),
      ], now: ahora);
      expect(orden.map((o) => o.driverId), <String>['barato', 'medio', 'caro']);
    });

    test('la espera puede ganarle al precio', () {
      const criterio = BidRanking(
        priceWeight: 1,
        etaWeight: 3,
        ratingWeight: 0,
      );
      final orden = criterio.sort(<DriverBid>[
        oferta('lento', 500, minutos: 20),
        oferta('rapido', 700, minutos: 2),
      ], now: ahora);
      expect(orden.first.driverId, 'rapido');
    });

    test('quita las caducadas antes de ordenar', () {
      const criterio = BidRanking();
      final orden = criterio.sort(<DriverBid>[
        oferta('vieja', 400, cuando: ahora.subtract(const Duration(hours: 1))),
        oferta('viva', 800),
      ], now: ahora);
      expect(orden.map((o) => o.driverId), <String>['viva']);
    });

    test('con una sola oferta no hay nada que normalizar', () {
      expect(
        const BidRanking().sort(<DriverBid>[oferta('a', 500)], now: ahora),
        hasLength(1),
      );
    });
  });

  group('BidAdvisor', () {
    const asesor = BidAdvisor(
      currency: 'EUR',
      minorUnitDigits: 2,
      economics: DriverEconomics(costPerKilometer: 20, minimumNetPerHour: 1500),
    );

    test('la carrera que paga menos puede rendir más por hora', () {
      // La tabla que sale en la documentación de BidAdvisor, comprobada.
      final a = asesor.evaluate(
        fare: 800,
        deadheadMeters: 5000,
        deadheadDuration: const Duration(minutes: 12),
        tripMeters: 6000,
        tripDuration: const Duration(minutes: 10),
      );
      final b = asesor.evaluate(
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
      final mala = asesor.evaluate(
        fare: 400,
        deadheadMeters: 5000,
        deadheadDuration: const Duration(minutes: 12),
        tripMeters: 6000,
        tripDuration: const Duration(minutes: 10),
      );
      expect(mala.worthIt, isFalse);
      expect(mala.deadheadShare, closeTo(0.4545, 0.001));
    });

    test('descuenta la comisión de la plataforma', () {
      const conComision = BidAdvisor(
        currency: 'EUR',
        minorUnitDigits: 2,
        economics: DriverEconomics(costPerKilometer: 20, commissionRate: 0.25),
      );
      final r = conComision.evaluate(
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
      final minimo = asesor.breakEvenFare(
        deadheadMeters: 5000,
        deadheadDuration: const Duration(minutes: 12),
        tripMeters: 6000,
        tripDuration: const Duration(minutes: 10),
      );
      // Y a ese importe la carrera ya compensa.
      final r = asesor.evaluate(
        fare: minimo,
        deadheadMeters: 5000,
        deadheadDuration: const Duration(minutes: 12),
        tripMeters: 6000,
        tripDuration: const Duration(minutes: 10),
      );
      expect(r.worthIt, isTrue);
      expect(minimo, 770);
    });

    test('el factor de vuelta encarece las carreras a las afueras', () {
      const conVuelta = BidAdvisor(
        currency: 'EUR',
        minorUnitDigits: 2,
        economics: DriverEconomics(costPerKilometer: 20, returnFactor: 1.0),
      );
      final r = conVuelta.evaluate(
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

  group('FareAdvisor', () {
    const asesor = FareAdvisor(
      tariff: Tariff(
        currency: 'EUR',
        baseFare: 250,
        perKilometer: 110,
        perMinute: 35,
      ),
    );

    test('sugiere un rango alrededor de la referencia', () {
      final s = asesor.suggest(
        distanceMeters: 10000,
        duration: const Duration(minutes: 20),
        departure: DateTime(2026, 8, 23, 12),
      );
      expect(s.reference, 2050);
      expect(s.recommended, 2050);
      expect(s.minimum, lessThan(s.recommended));
      expect(s.maximum, greaterThan(s.recommended));
    });

    test('la demanda sube todo el rango', () {
      final normal = asesor.suggest(
        distanceMeters: 10000,
        duration: const Duration(minutes: 20),
        departure: DateTime(2026, 8, 23, 12),
      );
      final punta = asesor.suggest(
        distanceMeters: 10000,
        duration: const Duration(minutes: 20),
        departure: DateTime(2026, 8, 23, 12),
        demandFactor: 1.5,
      );
      expect(punta.recommended, (normal.reference * 1.5).round());
      expect(punta.minimum, greaterThan(normal.minimum));
    });

    test('la probabilidad de aceptación crece con el importe', () {
      double p(int importe) =>
          asesor.acceptanceProbability(offered: importe, reference: 2000);

      expect(p(1200), lessThan(p(2000)));
      expect(p(2000), lessThan(p(3000)));
      expect(p(2000), greaterThan(0.5));
      expect(p(3000), lessThan(1.0));
    });

    test('rechaza una demanda no positiva', () {
      expect(
        () => asesor.suggest(
          distanceMeters: 1000,
          duration: const Duration(minutes: 5),
          demandFactor: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}
