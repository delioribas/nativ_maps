// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:nativ_maps/nativ_maps.dart';
import 'package:test/test.dart';

import '../support/fake_service.dart';

/// Una ruta de dos tramos con la forma real de v2.
///
/// La distancia y la duración van donde v2 las pone de verdad —dentro de
/// `VehicleLegDetails.Summary.Overview`—, **no** en `leg['Distance']`. Es la
/// diferencia entre leer los números y leer ceros.
Map<String, dynamic> _rutaDeDosTramos() => <String, dynamic>{
  'Routes': <dynamic>[
    <String, dynamic>{
      'Summary': <String, dynamic>{'Distance': 12400, 'Duration': 1560},
      'MajorRoadLabels': <dynamic>[
        <String, dynamic>{
          'RoadName': <String, dynamic>{'Value': 'Av. Simón Bolívar'},
        },
      ],
      'Legs': <dynamic>[
        <String, dynamic>{
          'TravelMode': 'Car',
          'Type': 'Vehicle',
          'Geometry': <String, dynamic>{
            'LineString': <dynamic>[
              <double>[-78.4678, -0.1807],
              <double>[-78.4700, -0.1830],
            ],
          },
          'VehicleLegDetails': <String, dynamic>{
            'Summary': <String, dynamic>{
              'Overview': <String, dynamic>{'Distance': 6200, 'Duration': 780},
              'TravelOnly': <String, dynamic>{'Duration': 740},
            },
            'Tolls': <dynamic>[
              <String, dynamic>{
                'SystemRef': 'peaje-oyacoto',
                'Country': 'ECU',
                'Rates': <dynamic>[
                  <String, dynamic>{
                    'PaymentMethods': <String>['Cash'],
                    'LocalPrice': <String, dynamic>{
                      'Currency': 'USD',
                      'Value': 0.4,
                    },
                  },
                ],
              },
            ],
            'TravelSteps': <dynamic>[
              <String, dynamic>{
                'Type': 'Turn',
                'Distance': 300,
                'Duration': 40,
                'GeometryOffset': 0,
                'NextRoad': <String, dynamic>{
                  'RoadName': <dynamic>[
                    <String, dynamic>{'Value': 'Naciones Unidas'},
                  ],
                },
              },
            ],
          },
        },
        <String, dynamic>{
          'TravelMode': 'Car',
          'Geometry': <String, dynamic>{
            'LineString': <dynamic>[
              <double>[-78.4700, -0.1830],
              <double>[-78.4750, -0.1900],
            ],
          },
          'VehicleLegDetails': <String, dynamic>{
            'Summary': <String, dynamic>{
              'Overview': <String, dynamic>{'Distance': 6200, 'Duration': 780},
            },
          },
        },
      ],
    },
  ],
};

void main() {
  late FakeAlsService service;
  late NativMaps maps;

  setUp(() {
    service = FakeAlsService();
    maps = fakeNativMaps(service);
  });

  tearDown(() => maps.close());

  group('calculateRoutes', () {
    test(
      'lee distancia y duración de Summary.Overview, no del tramo',
      () async {
        service.stub('/v2/routes', _rutaDeDosTramos());

        final respuesta = await maps.routes.calculateRoutes(
          origin: LatLng(-0.1807, -78.4678),
          destination: LatLng(-0.1900, -78.4750),
        );
        final ruta = respuesta.best!;

        // Si se leyera `leg['Distance']` —que en v2 no existe—, esto sería 0.
        expect(ruta.legs.first.distanceMeters, 6200);
        expect(ruta.legs.first.duration, const Duration(seconds: 780));
        expect(
          ruta.legs.first.travelOnlyDuration,
          const Duration(seconds: 740),
        );
        expect(ruta.distanceMeters, 12400);
        expect(ruta.duration, const Duration(seconds: 1560));
      },
    );

    test('cose los tramos sin duplicar el punto de la costura', () async {
      service.stub('/v2/routes', _rutaDeDosTramos());
      final ruta = (await maps.routes.calculateRoutes(
        origin: LatLng(-0.1807, -78.4678),
        destination: LatLng(-0.1900, -78.4750),
      )).best!;

      // 2 + 2 puntos, menos el compartido = 3.
      expect(ruta.points, hasLength(3));
      expect(ruta.bounds, isNotNull);
    });

    test('lee los peajes, que Google no da', () async {
      service.stub('/v2/routes', _rutaDeDosTramos());
      final ruta = (await maps.routes.calculateRoutes(
        origin: LatLng(-0.1807, -78.4678),
        destination: LatLng(-0.1900, -78.4750),
        legAdditionalFeatures: const <RouteFeature>[RouteFeature.tolls],
      )).best!;

      expect(ruta.tolls, hasLength(1));
      expect(ruta.tolls.first.amount, 0.4);
      expect(ruta.tolls.first.currency, 'USD');
      expect(ruta.tollCostByCurrency, <String, double>{'USD': 0.4});
    });

    test('envía las coordenadas en [lon, lat] y nunca DistanceUnit', () async {
      service.stub('/v2/routes', _rutaDeDosTramos());
      await maps.routes.calculateRoutes(
        origin: LatLng(-0.1807, -78.4678),
        destination: LatLng(-0.1900, -78.4750),
      );

      final enviado = service.lastRequest.body;
      expect(service.lastRequest.path, '/v2/routes');
      expect(enviado['Origin'], <double>[-78.4678, -0.1807]);
      expect(enviado['Destination'], <double>[-78.4750, -0.1900]);
      expect(service.lastRequest.rawBody, isNot(contains('DistanceUnit')));
      // Sin horas, se usa el tráfico de ahora.
      expect(enviado['DepartNow'], isTrue);
    });

    test('la moto se llama Scooter en v2, no Motorcycle', () async {
      service.stub('/v2/routes', _rutaDeDosTramos());
      await maps.routes.calculateRoutes(
        origin: LatLng(-0.1807, -78.4678),
        destination: LatLng(-0.1900, -78.4750),
        travelMode: TravelMode.scooter,
      );
      expect(service.lastRequest.body['TravelMode'], 'Scooter');
    });

    test('salida y llegada a la vez lanzan', () async {
      expect(
        () => maps.routes.calculateRoutes(
          origin: LatLng(0, 0),
          destination: LatLng(1, 1),
          departureTime: DateTime.now(),
          arrivalTime: DateTime.now(),
        ),
        throwsArgumentError,
      );
    });

    test('las opciones de camión se anidan bajo su modo', () async {
      service.stub('/v2/routes', _rutaDeDosTramos());
      await maps.routes.calculateRoutes(
        origin: LatLng(0, 0),
        destination: LatLng(1, 1),
        travelMode: TravelMode.truck,
        travelModeOptions: const TravelModeOptions.truck(
          grossWeightKg: 18000,
          heightCm: 400,
        ),
      );

      final opciones =
          service.lastRequest.body['TravelModeOptions'] as Map<String, dynamic>;
      expect(opciones['Truck'], isA<Map<String, dynamic>>());
      expect((opciones['Truck'] as Map<String, dynamic>)['GrossWeight'], 18000);
    });

    test('opciones de camión con modo coche no se envían', () async {
      service.stub('/v2/routes', _rutaDeDosTramos());
      await maps.routes.calculateRoutes(
        origin: LatLng(0, 0),
        destination: LatLng(1, 1),
        travelModeOptions: const TravelModeOptions.truck(heightCm: 400),
      );
      // Enviar opciones de camión bajo `Car` provocaría un 400.
      expect(service.lastRequest.rawBody, isNot(contains('Truck')));
    });
  });

  group('calculateRouteMatrix', () {
    Map<String, dynamic> matrizDe(int filas, int columnas) => <String, dynamic>{
      'ErrorCount': 0,
      'RouteMatrix': <dynamic>[
        for (var i = 0; i < filas; i++)
          <dynamic>[
            for (var j = 0; j < columnas; j++)
              <String, dynamic>{
                'Distance': 1000 * (i + j + 1),
                'Duration': 60 * (i + j + 1),
              },
          ],
      ],
    };

    test('el límite sin acotar zona se comprueba ANTES de enviar', () async {
      // 16 orígenes pasa de 15: la petición no debe salir.
      expect(
        () => maps.routes.calculateRouteMatrix(
          origins: <LatLng>[for (var i = 0; i < 16; i++) LatLng(i * 0.1, 0)],
          destinations: <LatLng>[LatLng(0, 0)],
        ),
        throwsArgumentError,
      );
      expect(service.requests, isEmpty);
    });

    test('el límite de 100 celdas también', () async {
      expect(
        () => maps.routes.calculateRouteMatrix(
          origins: <LatLng>[for (var i = 0; i < 11; i++) LatLng(i * 0.1, 0)],
          destinations: <LatLng>[
            for (var i = 0; i < 11; i++) LatLng(0, i * 0.1),
          ],
        ),
        throwsArgumentError,
      );
      expect(service.requests, isEmpty);
    });

    test('con zona acotada el límite no aplica', () async {
      service.stub('/v2/route-matrix', matrizDe(20, 20));
      final matriz = await maps.routes.calculateRouteMatrix(
        origins: <LatLng>[for (var i = 0; i < 20; i++) LatLng(i * 0.01, 0)],
        destinations: <LatLng>[
          for (var i = 0; i < 20; i++) LatLng(0, i * 0.01),
        ],
        routingBoundary: LatLngBounds(
          southwest: LatLng(-1, -1),
          northeast: LatLng(1, 1),
        ),
      );
      expect(matriz.originCount, 20);
    });

    test('cobra al presupuesto por par, no por petición', () async {
      final presupuesto = Budget(maxUnits: 1000);
      final conTope = fakeNativMaps(service, budget: presupuesto);
      addTearDown(conTope.close);
      service.stub('/v2/route-matrix', matrizDe(5, 5));

      await conTope.routes.calculateRouteMatrix(
        origins: <LatLng>[for (var i = 0; i < 5; i++) LatLng(i * 0.01, 0)],
        destinations: <LatLng>[for (var i = 0; i < 5; i++) LatLng(0, i * 0.01)],
      );

      // 5x5 son 25 cálculos de ruta, no uno.
      expect(presupuesto.usedUnits, 25);
    });

    test(
      'nearestDestination usa la carretera y salta las celdas con error',
      () async {
        service.stub('/v2/route-matrix', <String, dynamic>{
          'ErrorCount': 1,
          'RouteMatrix': <dynamic>[
            <dynamic>[
              <String, dynamic>{
                'Distance': 0,
                'Duration': 0,
                'Error': 'sin ruta',
              },
              <String, dynamic>{'Distance': 8000, 'Duration': 900},
              <String, dynamic>{'Distance': 3000, 'Duration': 400},
            ],
          ],
        });

        final matriz = await maps.routes.calculateRouteMatrix(
          origins: <LatLng>[LatLng(0, 0)],
          destinations: <LatLng>[LatLng(1, 1), LatLng(2, 2), LatLng(3, 3)],
        );

        // La celda 0 trae ceros, que parecerían «lo más cerca posible».
        expect(matriz.cell(0, 0).isValid, isFalse);
        expect(matriz.nearestDestination(0), 2);
        expect(matriz.errorCount, 1);
      },
    );

    test('unas dimensiones distintas de las pedidas lanzan', () async {
      service.stub('/v2/route-matrix', matrizDe(1, 1));
      expect(
        () => maps.routes.calculateRouteMatrix(
          origins: <LatLng>[LatLng(0, 0), LatLng(1, 1)],
          destinations: <LatLng>[LatLng(2, 2), LatLng(3, 3)],
        ),
        throwsA(isA<AlsParseExceptionForMatrix>()),
      );
    });
  });

  group('calculateIsolines', () {
    Map<String, dynamic> isocronaDe(int cuantas) => <String, dynamic>{
      'SnappedOrigin': <double>[-78.4678, -0.1807],
      'Isolines': <dynamic>[
        for (var i = 0; i < cuantas; i++)
          <String, dynamic>{
            'TimeThreshold': 480 * (i + 1),
            'Geometries': <dynamic>[
              <String, dynamic>{
                'Polygon': <dynamic>[
                  <dynamic>[
                    <double>[-78.47, -0.18],
                    <double>[-78.46, -0.18],
                    <double>[-78.46, -0.17],
                    <double>[-78.47, -0.18],
                  ],
                ],
              },
            ],
          },
      ],
    };

    test('calcula hacia fuera desde un origen', () async {
      service.stub('/v2/isolines', isocronaDe(1));
      final respuesta = await maps.routes.calculateIsolines(
        origin: LatLng(-0.1807, -78.4678),
        thresholds: Thresholds.time(const <Duration>[Duration(minutes: 8)]),
        travelMode: TravelMode.scooter,
      );

      final enviado = service.lastRequest.body;
      expect(service.lastRequest.path, '/v2/isolines');
      expect(enviado['Origin'], <double>[-78.4678, -0.1807]);
      expect(enviado['Destination'], isNull);
      expect((enviado['Thresholds'] as Map<String, dynamic>)['Time'], <int>[
        480,
      ]);
      expect(respuesta.isolines.first.outerRing, hasLength(4));
      expect(respuesta.snappedOrigin, isNotNull);
    });

    test('calcula hacia dentro desde un destino', () async {
      service.stub('/v2/isolines', isocronaDe(1));
      await maps.routes.calculateIsolines(
        destination: LatLng(-0.1807, -78.4678),
        thresholds: Thresholds.time(const <Duration>[Duration(minutes: 10)]),
      );
      expect(service.lastRequest.body['Destination'], isNotNull);
      expect(service.lastRequest.body['Origin'], isNull);
    });

    test('origen y destino a la vez, o ninguno, lanzan', () async {
      final umbral = Thresholds.time(const <Duration>[Duration(minutes: 5)]);
      expect(
        () => maps.routes.calculateIsolines(
          origin: LatLng(0, 0),
          destination: LatLng(1, 1),
          thresholds: umbral,
        ),
        throwsArgumentError,
      );
      expect(
        () => maps.routes.calculateIsolines(thresholds: umbral),
        throwsArgumentError,
      );
    });

    test('más de 5 umbrales lanza antes de enviar', () async {
      expect(
        () => maps.routes.calculateIsolines(
          origin: LatLng(0, 0),
          thresholds: Thresholds.time(const <Duration>[
            Duration(minutes: 1),
            Duration(minutes: 2),
            Duration(minutes: 3),
            Duration(minutes: 4),
            Duration(minutes: 5),
            Duration(minutes: 6),
          ]),
        ),
        throwsArgumentError,
      );
      expect(service.requests, isEmpty);
    });

    test('cobra al presupuesto POR UMBRAL', () async {
      final presupuesto = Budget(maxUnits: 100);
      final conTope = fakeNativMaps(service, budget: presupuesto);
      addTearDown(conTope.close);
      service.stub('/v2/isolines', isocronaDe(3));

      await conTope.routes.calculateIsolines(
        origin: LatLng(0, 0),
        thresholds: Thresholds.time(const <Duration>[
          Duration(minutes: 5),
          Duration(minutes: 10),
          Duration(minutes: 15),
        ]),
      );

      // Tres umbrales son tres unidades, no una.
      expect(presupuesto.usedUnits, 3);
    });

    test('la granularidad va puesta por defecto', () async {
      service.stub('/v2/isolines', isocronaDe(1));
      await maps.routes.calculateIsolines(
        origin: LatLng(0, 0),
        thresholds: Thresholds.time(const <Duration>[Duration(minutes: 30)]),
      );
      // Sin MaxPoints, una isócrona de 30 min ahoga el mapa.
      final granularidad =
          service.lastRequest.body['IsolineGranularity']
              as Map<String, dynamic>;
      expect(granularidad['MaxPoints'], 300);
    });

    test('varios polígonos no se aplanan en uno', () async {
      // Con un río sin puentes, lo alcanzable son dos manchas separadas.
      // Unirlas dibujaría como alcanzable justo el agua.
      service.stub('/v2/isolines', <String, dynamic>{
        'Isolines': <dynamic>[
          <String, dynamic>{
            'TimeThreshold': 600,
            'Geometries': <dynamic>[
              <String, dynamic>{
                'Polygon': <dynamic>[
                  <dynamic>[
                    <double>[-78.5, -0.2],
                    <double>[-78.4, -0.2],
                    <double>[-78.5, -0.2],
                  ],
                ],
              },
              <String, dynamic>{
                'Polygon': <dynamic>[
                  <dynamic>[
                    <double>[-78.3, -0.1],
                    <double>[-78.2, -0.1],
                    <double>[-78.3, -0.1],
                  ],
                ],
              },
            ],
          },
        ],
      });

      final respuesta = await maps.routes.calculateIsolines(
        origin: LatLng(0, 0),
        thresholds: Thresholds.time(const <Duration>[Duration(minutes: 10)]),
      );
      expect(respuesta.isolines.first.polygons, hasLength(2));
    });
  });

  group('snapToRoads', () {
    Map<String, dynamic> pegadoDe(int puntos) => <String, dynamic>{
      'SnappedGeometry': <String, dynamic>{
        'LineString': <dynamic>[
          for (var i = 0; i < puntos; i++)
            <double>[-78.46 - i * 0.0001, -0.18 - i * 0.0001],
        ],
      },
      'SnappedTracePoints': <dynamic>[
        for (var i = 0; i < puntos; i++)
          <String, dynamic>{
            'Confidence': i.isEven ? 0.95 : 0.2,
            'OriginalPosition': <double>[-78.46, -0.18],
            'SnappedPosition': <double>[
              -78.46 - i * 0.0001,
              -0.18 - i * 0.0001,
            ],
          },
      ],
    };

    List<TracePoint> rastroDe(int n) => <TracePoint>[
      for (var i = 0; i < n; i++)
        TracePoint(
          position: LatLng(-0.18 - i * 0.00001, -78.46 - i * 0.00001),
          headingDegrees: 90,
          speedKmh: 42,
          timestamp: DateTime.utc(2026, 8, 22, 10).add(Duration(seconds: i)),
        ),
    ];

    test('envía rumbo, velocidad y hora, que el GT06 ya manda', () async {
      service.stub('/v2/snap-to-roads', pegadoDe(3));
      await maps.routes.snapToRoads(tracePoints: rastroDe(3));

      final enviados = service.lastRequest.body['TracePoints'] as List<dynamic>;
      final primero = enviados.first as Map<String, dynamic>;
      expect(primero['Heading'], 90);
      expect(primero['Speed'], 42);
      expect(primero['Timestamp'], isA<String>());
      // Y la posición en [lon, lat].
      expect(
        (primero['Position'] as List<dynamic>).first,
        closeTo(-78.46, 1e-4),
      );
    });

    test('un rastro largo se TROCEA, no falla', () async {
      // 12 000 puntos pasan del máximo de 5 000 por petición.
      service.stub('/v2/snap-to-roads', pegadoDe(5000));
      final respuesta = await maps.routes.snapToRoads(
        tracePoints: rastroDe(12000),
      );

      expect(service.requests.length, greaterThan(1));
      expect(respuesta.chunkCount, service.requests.length);
    });

    test('los trozos van con solape para no romper la costura', () async {
      service.stub('/v2/snap-to-roads', pegadoDe(10));
      await maps.routes.snapToRoads(
        tracePoints: rastroDe(12000),
        overlapPoints: 10,
      );

      final primero = service.requests[0].body['TracePoints'] as List<dynamic>;
      final segundo = service.requests[1].body['TracePoints'] as List<dynamic>;
      expect(primero, hasLength(5000));
      // El segundo trozo empieza 10 puntos antes de donde acabó el primero.
      expect(segundo.first, equals(primero[5000 - 10]));
    });

    test('menos de 2 puntos lanza', () async {
      expect(
        () => maps.routes.snapToRoads(tracePoints: rastroDe(1)),
        throwsArgumentError,
      );
    });

    test('un radio fuera de rango lanza', () async {
      expect(
        () => maps.routes.snapToRoads(
          tracePoints: rastroDe(5),
          snapRadiusMeters: 20000,
        ),
        throwsArgumentError,
      );
    });

    test('confidentPoints separa lo dudoso de lo fiable', () async {
      service.stub('/v2/snap-to-roads', pegadoDe(6));
      final respuesta = await maps.routes.snapToRoads(
        tracePoints: rastroDe(6),
        snapRadiusMeters: 500,
      );

      expect(respuesta.snappedPoints, hasLength(6));
      // La mitad venía con confianza 0,2: pintarlos sería inventar una calle.
      expect(respuesta.confidentPoints(), hasLength(3));
      expect(respuesta.snappedPoints.first.displacementMeters, isNotNull);
    });
  });

  group('optimizeWaypoints', () {
    test('devuelve el orden y lo que no encajó', () async {
      service.stub('/v2/optimize-waypoints', <String, dynamic>{
        'Distance': 24000,
        'Duration': 3600,
        'OptimizedWaypoints': <dynamic>[
          <String, dynamic>{'Id': 'pedido-3'},
          <String, dynamic>{'Id': 'pedido-1'},
          <String, dynamic>{'Id': 'pedido-2'},
        ],
        'ImpedingWaypoints': <dynamic>[
          <String, dynamic>{'Id': 'pedido-4'},
        ],
      });

      final respuesta = await maps.routes.optimizeWaypoints(
        origin: LatLng(-0.1807, -78.4678),
        waypoints: <OptimizationWaypoint>[
          OptimizationWaypoint(
            id: 'pedido-1',
            position: LatLng(-0.19, -78.47),
            serviceDuration: const Duration(minutes: 5),
          ),
          OptimizationWaypoint(id: 'pedido-2', position: LatLng(-0.20, -78.48)),
          OptimizationWaypoint(id: 'pedido-3', position: LatLng(-0.18, -78.46)),
          OptimizationWaypoint(id: 'pedido-4', position: LatLng(-0.30, -78.90)),
        ],
      );

      expect(respuesta.orderedIds, <String>[
        'pedido-3',
        'pedido-1',
        'pedido-2',
      ]);
      // Las que no encajan vienen aparte: son las que hay que reprogramar.
      expect(respuesta.impedingWaypointIds, <String>['pedido-4']);

      final enviadas = service.lastRequest.body['Waypoints'] as List<dynamic>;
      expect((enviadas.first as Map<String, dynamic>)['ServiceDuration'], 300);
    });

    test('identificadores repetidos lanzan', () async {
      expect(
        () => maps.routes.optimizeWaypoints(
          origin: LatLng(0, 0),
          waypoints: <OptimizationWaypoint>[
            OptimizationWaypoint(id: 'a', position: LatLng(1, 1)),
            OptimizationWaypoint(id: 'a', position: LatLng(2, 2)),
          ],
        ),
        throwsArgumentError,
      );
    });
  });
}
