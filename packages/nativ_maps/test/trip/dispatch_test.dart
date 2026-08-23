// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:nativ_maps/nativ_maps.dart';
import 'package:test/test.dart';

import '../support/fake_service.dart';

void main() {
  final quito = LatLng(-0.1807, -78.4678);
  final now = DateTime.utc(2026, 8, 23, 10);

  late FakeAlsService service;
  late NativMaps maps;
  late DispatchPlanner planificador;

  setUp(() {
    service = FakeAlsService();
    maps = fakeNativMaps(service);
    planificador = DispatchPlanner(routes: maps.routes);
  });

  tearDown(() => maps.close());

  /// Una matriz de `n` orígenes por un destino, con las duraciones dadas.
  Map<String, dynamic> matrix(List<int> seconds, {int? sinRuta}) =>
      <String, dynamic>{
        'ErrorCount': sinRuta == null ? 0 : 1,
        'RouteMatrix': <dynamic>[
          for (var i = 0; i < seconds.length; i++)
            <dynamic>[
              if (i == sinRuta)
                <String, dynamic>{'Error': 'NoMatch'}
              else
                <String, dynamic>{
                  'Distance': seconds[i] * 10,
                  'Duration': seconds[i],
                },
            ],
        ],
      };

  DriverLocation driver(
    String id,
    double meters,
    double heading, {
    bool libre = true,
    DateTime? seen,
  }) => DriverLocation(
    driverId: id,
    position: quito.offset(meters, heading),
    available: libre,
    updatedAt: seen ?? now,
  );

  group('shortlist', () {
    test('ordena por línea recta y no gasta ninguna petición', () {
      final list = planificador.shortlist(<DriverLocation>[
        driver('lejos', 1200, 90),
        driver('cerca', 300, 0),
        driver('medio', 900, 180),
      ], quito);

      expect(list.map((c) => c.driver.driverId), <String>[
        'cerca',
        'medio',
        'lejos',
      ]);
      expect(service.requests, isEmpty);
    });

    test('descarta a los que no están libres', () {
      final list = planificador.shortlist(<DriverLocation>[
        driver('ocupado', 100, 0, libre: false),
        driver('libre', 800, 0),
      ], quito);
      expect(list.map((c) => c.driver.driverId), <String>['libre']);
    });

    test('descarta posiciones viejas', () {
      // Un coche cuya última posición es de hace diez minutos ya no está ahí.
      final list = planificador.shortlist(
        <DriverLocation>[
          driver(
            'fantasma',
            100,
            0,
            seen: now.subtract(const Duration(minutes: 10)),
          ),
          driver('actual', 800, 0),
        ],
        quito,
        staleAfter: const Duration(minutes: 2),
        now: now,
      );
      expect(list.map((c) => c.driver.driverId), <String>['actual']);
    });

    test('descarta a los que están fuera del radio', () {
      const closeBy = DispatchPlanner(
        routes: _NuncaSeLlama(),
        maxRadiusMeters: 1000,
      );
      final list = closeBy.shortlist(<DriverLocation>[
        driver('dentro', 900, 0),
        driver('fuera', 5000, 0),
      ], quito);
      expect(list.map((c) => c.driver.driverId), <String>['dentro']);
    });

    test('recorta al tamaño de la preselección', () {
      const threeOnly = DispatchPlanner(
        routes: _NuncaSeLlama(),
        shortlistSize: 3,
      );
      final list = threeOnly.shortlist(<DriverLocation>[
        for (var i = 1; i <= 10; i++) driver('c$i', 100.0 * i, 0),
      ], quito);
      expect(list, hasLength(3));
      expect(list.first.driver.driverId, 'c1');
    });
  });

  group('rank', () {
    test('la línea recta se equivoca y la matriz lo corrige', () {
      // El conductor «cerca» está a 300 m… al otro lado del río.
      service.stub('/v2/route-matrix', matrix(<int>[900, 480, 240]));

      final list = planificador.shortlist(<DriverLocation>[
        driver('lejos', 1200, 90),
        driver('cerca', 300, 0),
        driver('medio', 900, 180),
      ], quito);
      expect(list.first.driver.driverId, 'cerca');

      return planificador.rank(list, quito).then((refinedList) {
        expect(refinedList.map((c) => c.driver.driverId), <String>[
          'lejos',
          'medio',
          'cerca',
        ]);
        expect(refinedList.first.drivingDuration, const Duration(seconds: 240));
        expect(refinedList.first.refined, isTrue);
        // 12 km de conducción para 1,2 km en recta: hay un río de por medio.
        expect(refinedList.last.detourFactor, greaterThan(2));
      });
    });

    test('manda a los conductores como orígenes, no al revés', () async {
      // Con un solo destino la matriz cuesta una celda por candidato. Al
      // revés costaría lo mismo, pero la lectura de las filas cambiaría y el
      // orden del resultado saldría mal.
      service.stub('/v2/route-matrix', matrix(<int>[100, 200]));
      final list = planificador.shortlist(<DriverLocation>[
        driver('a', 300, 0),
        driver('b', 600, 0),
      ], quito);
      await planificador.rank(list, quito);

      final body = service.lastRequest.body;
      expect(body['Origins']! as List<dynamic>, hasLength(2));
      expect(body['Destinations']! as List<dynamic>, hasLength(1));
    });

    test('los que no tienen ruta van al final, no desaparecen', () async {
      service.stub('/v2/route-matrix', matrix(<int>[300, 0, 120], sinRuta: 1));
      final list = planificador.shortlist(<DriverLocation>[
        driver('a', 200, 0),
        driver('isla', 400, 0),
        driver('c', 600, 0),
      ], quito);

      final refinedList = await planificador.rank(list, quito);
      expect(refinedList, hasLength(3));
      expect(refinedList.last.driver.driverId, 'isla');
      expect(refinedList.last.refined, isFalse);
    });

    test('una preselección vacía no llama al servicio', () async {
      expect(await planificador.rank(<DriverCandidate>[], quito), isEmpty);
      expect(service.requests, isEmpty);
    });

    test('findNearest encadena las dos fases', () async {
      service.stub('/v2/route-matrix', matrix(<int>[600, 180]));
      final result = await planificador.findNearest(<DriverLocation>[
        driver('a', 300, 0),
        driver('b', 900, 0),
      ], quito);
      expect(result.first.driver.driverId, 'b');
      expect(service.requests, hasLength(1));
    });

    test('sin candidatos no se gasta una petición', () async {
      final result = await planificador.findNearest(<DriverLocation>[
        driver('lejisimos', 50000, 0),
      ], quito);
      expect(result, isEmpty);
      expect(service.requests, isEmpty);
    });
  });
}

/// Un cliente que falla si alguien lo usa: las pruebas de [DispatchPlanner]
/// que solo preseleccionan no deben tocar la red.
class _NuncaSeLlama implements RoutesClient {
  const _NuncaSeLlama();

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw StateError('Shortlisting must not call the service');
}
