// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:nativ_maps/nativ_maps.dart';
import 'package:test/test.dart';

import '../support/fake_service.dart';

void main() {
  final quito = LatLng(-0.1807, -78.4678);
  final ahora = DateTime.utc(2026, 8, 23, 10);

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
  Map<String, dynamic> matriz(List<int> segundos, {int? sinRuta}) =>
      <String, dynamic>{
        'ErrorCount': sinRuta == null ? 0 : 1,
        'RouteMatrix': <dynamic>[
          for (var i = 0; i < segundos.length; i++)
            <dynamic>[
              if (i == sinRuta)
                <String, dynamic>{'Error': 'NoMatch'}
              else
                <String, dynamic>{
                  'Distance': segundos[i] * 10,
                  'Duration': segundos[i],
                },
            ],
        ],
      };

  DriverLocation conductor(
    String id,
    double metros,
    double rumbo, {
    bool libre = true,
    DateTime? visto,
  }) => DriverLocation(
    driverId: id,
    position: quito.offset(metros, rumbo),
    available: libre,
    updatedAt: visto ?? ahora,
  );

  group('shortlist', () {
    test('ordena por línea recta y no gasta ninguna petición', () {
      final lista = planificador.shortlist(<DriverLocation>[
        conductor('lejos', 1200, 90),
        conductor('cerca', 300, 0),
        conductor('medio', 900, 180),
      ], quito);

      expect(lista.map((c) => c.driver.driverId), <String>[
        'cerca',
        'medio',
        'lejos',
      ]);
      expect(service.requests, isEmpty);
    });

    test('descarta a los que no están libres', () {
      final lista = planificador.shortlist(<DriverLocation>[
        conductor('ocupado', 100, 0, libre: false),
        conductor('libre', 800, 0),
      ], quito);
      expect(lista.map((c) => c.driver.driverId), <String>['libre']);
    });

    test('descarta posiciones viejas', () {
      // Un coche cuya última posición es de hace diez minutos ya no está ahí.
      final lista = planificador.shortlist(
        <DriverLocation>[
          conductor(
            'fantasma',
            100,
            0,
            visto: ahora.subtract(const Duration(minutes: 10)),
          ),
          conductor('actual', 800, 0),
        ],
        quito,
        staleAfter: const Duration(minutes: 2),
        now: ahora,
      );
      expect(lista.map((c) => c.driver.driverId), <String>['actual']);
    });

    test('descarta a los que están fuera del radio', () {
      const cerca = DispatchPlanner(
        routes: _NuncaSeLlama(),
        maxRadiusMeters: 1000,
      );
      final lista = cerca.shortlist(<DriverLocation>[
        conductor('dentro', 900, 0),
        conductor('fuera', 5000, 0),
      ], quito);
      expect(lista.map((c) => c.driver.driverId), <String>['dentro']);
    });

    test('recorta al tamaño de la preselección', () {
      const tres = DispatchPlanner(routes: _NuncaSeLlama(), shortlistSize: 3);
      final lista = tres.shortlist(<DriverLocation>[
        for (var i = 1; i <= 10; i++) conductor('c$i', 100.0 * i, 0),
      ], quito);
      expect(lista, hasLength(3));
      expect(lista.first.driver.driverId, 'c1');
    });
  });

  group('rank', () {
    test('la línea recta se equivoca y la matriz lo corrige', () {
      // El conductor «cerca» está a 300 m… al otro lado del río.
      service.stub('/v2/route-matrix', matriz(<int>[900, 480, 240]));

      final lista = planificador.shortlist(<DriverLocation>[
        conductor('lejos', 1200, 90),
        conductor('cerca', 300, 0),
        conductor('medio', 900, 180),
      ], quito);
      expect(lista.first.driver.driverId, 'cerca');

      return planificador.rank(lista, quito).then((refinados) {
        expect(refinados.map((c) => c.driver.driverId), <String>[
          'lejos',
          'medio',
          'cerca',
        ]);
        expect(refinados.first.drivingDuration, const Duration(seconds: 240));
        expect(refinados.first.refined, isTrue);
        // 12 km de conducción para 1,2 km en recta: hay un río de por medio.
        expect(refinados.last.detourFactor, greaterThan(2));
      });
    });

    test('manda a los conductores como orígenes, no al revés', () async {
      // Con un solo destino la matriz cuesta una celda por candidato. Al
      // revés costaría lo mismo, pero la lectura de las filas cambiaría y el
      // orden del resultado saldría mal.
      service.stub('/v2/route-matrix', matriz(<int>[100, 200]));
      final lista = planificador.shortlist(<DriverLocation>[
        conductor('a', 300, 0),
        conductor('b', 600, 0),
      ], quito);
      await planificador.rank(lista, quito);

      final cuerpo = service.lastRequest.body;
      expect(cuerpo['Origins']! as List<dynamic>, hasLength(2));
      expect(cuerpo['Destinations']! as List<dynamic>, hasLength(1));
    });

    test('los que no tienen ruta van al final, no desaparecen', () async {
      service.stub('/v2/route-matrix', matriz(<int>[300, 0, 120], sinRuta: 1));
      final lista = planificador.shortlist(<DriverLocation>[
        conductor('a', 200, 0),
        conductor('isla', 400, 0),
        conductor('c', 600, 0),
      ], quito);

      final refinados = await planificador.rank(lista, quito);
      expect(refinados, hasLength(3));
      expect(refinados.last.driver.driverId, 'isla');
      expect(refinados.last.refined, isFalse);
    });

    test('una preselección vacía no llama al servicio', () async {
      expect(await planificador.rank(<DriverCandidate>[], quito), isEmpty);
      expect(service.requests, isEmpty);
    });

    test('findNearest encadena las dos fases', () async {
      service.stub('/v2/route-matrix', matriz(<int>[600, 180]));
      final resultado = await planificador.findNearest(<DriverLocation>[
        conductor('a', 300, 0),
        conductor('b', 900, 0),
      ], quito);
      expect(resultado.first.driver.driverId, 'b');
      expect(service.requests, hasLength(1));
    });

    test('sin candidatos no se gasta una petición', () async {
      final resultado = await planificador.findNearest(<DriverLocation>[
        conductor('lejisimos', 50000, 0),
      ], quito);
      expect(resultado, isEmpty);
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
      throw StateError('La preselección no debe llamar al servicio');
}
