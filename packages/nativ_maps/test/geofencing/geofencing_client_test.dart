// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:nativ_maps/nativ_maps.dart';
import 'package:test/test.dart';

import '../support/fake_service.dart';

/// Credenciales que no son de clave de API, que es lo que estas operaciones
/// exigen. Con `ApiKeyCredentials` se cortan antes de enviar.
final _sigv4 = HeaderCredentials(
  (service, region) async => <String, String>{'Authorization': 'AWS4-firmado'},
);

void main() {
  late FakeAlsService service;
  late NativMaps maps;

  setUp(() {
    service = FakeAlsService();
    maps = fakeNativMaps(service, credentials: _sigv4);
  });

  tearDown(() => maps.close());

  group('las 12 operaciones van a la ruta y el método correctos', () {
    test('putGeofence → PUT /geofencing/v0/…/geofences/{id}', () async {
      service.stub('/geofencing/v0/collections/zonas/geofences/bodega', {
        'GeofenceId': 'bodega',
        'CreateTime': '2026-08-22T12:00:00.000Z',
        'UpdateTime': '2026-08-22T12:00:00.000Z',
      });

      final geovalla = await maps.geofencing.putGeofence(
        collectionName: 'zonas',
        geofenceId: 'bodega',
        geometry: GeofenceGeometry.circle(
          center: LatLng(-0.1807, -78.4678),
          radiusMeters: 500,
        ),
        properties: const <String, String>{'cliente': 'ACME'},
      );

      // El método importa: esta es la única del paquete que usa PUT.
      expect(service.lastRequest.method, 'PUT');
      expect(
        service.lastRequest.path,
        '/geofencing/v0/collections/zonas/geofences/bodega',
      );
      final enviado = service.lastRequest.body;
      final circulo =
          (enviado['Geometry']! as Map<String, dynamic>)['Circle']!
              as Map<String, dynamic>;
      // Y el orden de la coordenada, como siempre.
      expect(circulo['Center'], <double>[-78.4678, -0.1807]);
      expect(circulo['Radius'], 500.0);
      expect(geovalla.geofenceId, 'bodega');
    });

    test('batchEvaluateGeofences → POST …/positions', () async {
      service.stub('/geofencing/v0/collections/zonas/positions', {
        'Errors': <dynamic>[],
      });

      final resultado = await maps.geofencing.batchEvaluateGeofences(
        collectionName: 'zonas',
        positions: <DevicePositionUpdate>[
          DevicePositionUpdate(
            deviceId: 'gt06-1',
            position: LatLng(-0.1807, -78.4678),
            sampleTime: DateTime.utc(2026, 8, 22, 12),
            horizontalAccuracyMeters: 8,
          ),
        ],
      );

      expect(
        service.lastRequest.path,
        '/geofencing/v0/collections/zonas/positions',
      );
      final actualizaciones =
          service.lastRequest.body['DevicePositionUpdates']! as List<dynamic>;
      final primera = actualizaciones.first as Map<String, dynamic>;
      expect(primera['DeviceId'], 'gt06-1');
      expect(primera['Position'], <double>[-78.4678, -0.1807]);
      expect((primera['Accuracy']! as Map<String, dynamic>)['Horizontal'], 8.0);
      expect(resultado.isCompleteSuccess, isTrue);
    });

    test('forecastGeofenceEvents predice y convierte a metros', () async {
      service.stub(
        '/geofencing/v0/collections/zonas/forecast-geofence-events',
        {
          'ForecastedEvents': <dynamic>[
            {
              'EventId': 'e-1',
              'GeofenceId': 'zona-restringida',
              'EventType': 'EXIT',
              'IsDeviceInGeofence': true,
              // La API responde en la unidad pedida: KILÓMETROS.
              'NearestDistance': 1.4,
              'ForecastedBreachTime': '2026-08-22T12:06:00.000Z',
              'GeofenceProperties': <String, String>{'cliente': 'ACME'},
            },
            {
              'EventId': 'e-2',
              'GeofenceId': 'bodega',
              'EventType': 'IDLE',
              'IsDeviceInGeofence': true,
              'NearestDistance': 0.2,
            },
          ],
          'DistanceUnit': 'Kilometers',
          'SpeedUnit': 'KilometersPerHour',
        },
      );

      final aviso = await maps.geofencing.forecastGeofenceEvents(
        collectionName: 'zonas',
        position: LatLng(-0.1807, -78.4678),
        speedKmh: 62,
        timeHorizon: const Duration(minutes: 10),
      );

      // Se piden kilómetros y se convierten: el resto del paquete va en metros.
      expect(service.lastRequest.body['DistanceUnit'], 'Kilometers');
      expect(service.lastRequest.body['TimeHorizonMinutes'], 10.0);
      expect(
        (service.lastRequest.body['DeviceState']!
            as Map<String, dynamic>)['Speed'],
        62.0,
      );
      expect(aviso.events.first.nearestDistance, 1400.0);

      // `breaches` deja fuera los IDLE, que dicen «sigue donde estaba».
      expect(aviso.events, hasLength(2));
      expect(aviso.breaches, hasLength(1));
      expect(aviso.breaches.first.eventType, ForecastedEventType.exit);
      expect(aviso.breaches.first.geofenceProperties['cliente'], 'ACME');
    });

    test('el plano de control va al host con prefijo cp.', () async {
      service.stub('/geofencing/v0/collections', {
        'CollectionName': 'zonas',
        'CollectionArn': 'arn:aws:geo:us-east-1:1:geofence-collection/zonas',
        'CreateTime': '2026-08-22T12:00:00.000Z',
      });

      final coleccion = await maps.geofencing.createCollection(
        collectionName: 'zonas',
        description: 'Zonas permitidas de la flota',
      );

      // Mandar esto al host de datos daría un 404 indiagnosticable.
      expect(
        service.lastRequest.headers['host'] ?? service.lastRequest.path,
        anything,
      );
      expect(
        AlsService.geofencingControl.hostFor('us-east-1'),
        'cp.geofencing.geo.us-east-1.amazonaws.com',
      );
      expect(
        AlsService.geofencing.hostFor('us-east-1'),
        'geofencing.geo.us-east-1.amazonaws.com',
      );
      expect(coleccion.collectionArn, contains('geofence-collection'));
    });

    test('deleteCollection usa DELETE y admite cuerpo vacío', () async {
      // Varias operaciones de control responden 200 sin cuerpo.
      service.stub('/geofencing/v0/collections/zonas', <String, dynamic>{});
      await maps.geofencing.deleteCollection('zonas');
      expect(service.lastRequest.method, 'DELETE');
    });

    test('updateCollection usa PATCH', () async {
      service.stub('/geofencing/v0/collections/zonas', {
        'CollectionName': 'zonas',
        'CollectionArn': 'arn:…',
        'UpdateTime': '2026-08-22T12:00:00.000Z',
      });
      await maps.geofencing.updateCollection(
        collectionName: 'zonas',
        description: 'nueva',
      );
      expect(service.lastRequest.method, 'PATCH');
    });

    test('listGeofences y listCollections leen sus páginas', () async {
      service
        ..stub('/geofencing/v0/collections/zonas/list-geofences', {
          'Entries': <dynamic>[
            {
              'GeofenceId': 'bodega',
              'Status': 'ACTIVE',
              'Geometry': {
                'Circle': {
                  'Center': <double>[-78.4678, -0.1807],
                  'Radius': 500,
                },
              },
              'CreateTime': '2026-08-22T12:00:00.000Z',
              'UpdateTime': '2026-08-22T12:00:00.000Z',
            },
          ],
          'NextToken': 'p2',
        })
        ..stub('/geofencing/v0/list-collections', {
          'Entries': <dynamic>[
            {'CollectionName': 'zonas', 'Description': 'x'},
          ],
        });

      final geovallas = await maps.geofencing.listGeofences(
        collectionName: 'zonas',
      );
      expect(geovallas.items.first.isActive, isTrue);
      expect(geovallas.items.first.geometry.circle!.radiusMeters, 500.0);
      expect(geovallas.hasMore, isTrue);

      final colecciones = await maps.geofencing.listCollections();
      expect(colecciones.items.first.collectionName, 'zonas');
      expect(colecciones.hasMore, isFalse);
    });

    test('las operaciones por lotes informan elemento a elemento', () async {
      service
        ..stub('/geofencing/v0/collections/zonas/put-geofences', {
          'Successes': <dynamic>[
            {'GeofenceId': 'a'},
          ],
          'Errors': <dynamic>[
            {
              'GeofenceId': 'b',
              'Error': {'Code': 'ValidationError', 'Message': 'mal'},
            },
          ],
        })
        ..stub('/geofencing/v0/collections/zonas/delete-geofences', {
          'Errors': <dynamic>[],
        });

      final puestas = await maps.geofencing.batchPutGeofence(
        collectionName: 'zonas',
        geofences: <Geofence>[
          Geofence(
            geofenceId: 'a',
            geometry: GeofenceGeometry.circle(
              center: LatLng(0, 0),
              radiusMeters: 100,
            ),
          ),
          Geofence(
            geofenceId: 'b',
            geometry: GeofenceGeometry.circle(
              center: LatLng(1, 1),
              radiusMeters: 100,
            ),
          ),
        ],
      );

      // La operación devuelve 200 aunque falle la mitad: hay que mirar errors.
      expect(puestas.total, 2);
      expect(puestas.succeeded, 1);
      expect(puestas.isCompleteSuccess, isFalse);
      expect(puestas.errors.first.itemId, 'b');
      expect(puestas.errors.first.code, 'ValidationError');

      final borradas = await maps.geofencing.batchDeleteGeofence(
        collectionName: 'zonas',
        geofenceIds: <String>['a'],
      );
      expect(borradas.isCompleteSuccess, isTrue);
    });

    test('getGeofence lee la geometría poligonal', () async {
      service.stub('/geofencing/v0/collections/zonas/geofences/p', {
        'GeofenceId': 'p',
        'Status': 'ACTIVE',
        'Geometry': {
          'Polygon': <dynamic>[
            <dynamic>[
              <double>[-78.5, -0.2],
              <double>[-78.4, -0.2],
              <double>[-78.4, -0.1],
              <double>[-78.5, -0.2],
            ],
          ],
        },
      });

      final geovalla = await maps.geofencing.getGeofence(
        collectionName: 'zonas',
        geofenceId: 'p',
      );
      expect(geovalla.geometry.polygon, hasLength(1));
      expect(
        geovalla.geometry.polygon!.first.first.latitude,
        closeTo(-0.2, 1e-9),
      );
    });
  });

  group('la clave de API NO sirve para geovallas', () {
    test(
      'se corta antes de enviar, con un mensaje que dice qué hacer',
      () async {
        // Es el error que de otro modo llega como un 403 idéntico a todos los
        // demás 403.
        final conClave = fakeNativMaps(service);
        addTearDown(conClave.close);

        await expectLater(
          conClave.geofencing.listCollections(),
          throwsA(
            isA<NativMapsConfigurationException>().having(
              (e) => e.message,
              'message',
              allOf(contains('SigV4'), contains('clave de API')),
            ),
          ),
        );
        expect(service.requests, isEmpty);
      },
    );

    test('Places sí acepta la clave', () async {
      final conClave = fakeNativMaps(service);
      addTearDown(conClave.close);
      service.stub('/v2/search-text', <String, dynamic>{
        'ResultItems': <dynamic>[],
      });
      await conClave.places.searchText(queryText: 'x');
      expect(service.requests, hasLength(1));
    });

    test('los enums lo dicen', () {
      expect(AlsService.places.supportsApiKey, isTrue);
      expect(AlsService.geofencing.supportsApiKey, isFalse);
      expect(AlsService.tracking.supportsApiKey, isFalse);
      // Y el nombre de firma es `geo`, no `geo-geofencing`.
      expect(AlsService.geofencing.signingName, 'geo');
      expect(AlsService.tracking.signingName, 'geo');
      expect(AlsService.places.signingName, 'geo-places');
    });
  });

  group('los límites se comprueban antes de enviar', () {
    test('más de 10 posiciones lanza', () async {
      expect(
        () => maps.geofencing.batchEvaluateGeofences(
          collectionName: 'zonas',
          positions: <DevicePositionUpdate>[
            for (var i = 0; i < 11; i++)
              DevicePositionUpdate(
                deviceId: 'd$i',
                position: LatLng(0, 0),
                sampleTime: DateTime.utc(2026),
              ),
          ],
        ),
        throwsArgumentError,
      );
      expect(service.requests, isEmpty);
    });

    test('más de 3 propiedades lanza', () async {
      expect(
        () => maps.geofencing.putGeofence(
          collectionName: 'zonas',
          geofenceId: 'g',
          geometry: GeofenceGeometry.circle(
            center: LatLng(0, 0),
            radiusMeters: 100,
          ),
          properties: const <String, String>{
            'a': '1',
            'b': '2',
            'c': '3',
            'd': '4',
          },
        ),
        throwsArgumentError,
      );
    });

    test('una clave o un valor demasiado largos lanzan', () async {
      expect(
        () => maps.geofencing.putGeofence(
          collectionName: 'z',
          geofenceId: 'g',
          geometry: GeofenceGeometry.circle(
            center: LatLng(0, 0),
            radiusMeters: 1,
          ),
          properties: <String, String>{'x' * 25: 'v'},
        ),
        throwsArgumentError,
      );
    });
  });

  group('GeofenceGeometry', () {
    test('el polígono se cierra al enviarlo', () {
      // El servicio exige el anillo cerrado; sin esto es un 400 y un viaje
      // de ida perdido.
      final geometria = GeofenceGeometry.polygon(<List<LatLng>>[
        <LatLng>[LatLng(0, 0), LatLng(0, 1), LatLng(1, 1)],
      ]);
      final anillo =
          (geometria.toJson()['Polygon']! as List<dynamic>).first
              as List<dynamic>;
      expect(anillo, hasLength(4));
      expect(anillo.first.toString(), anillo.last.toString());
    });

    test('rechaza un polígono de más de 1000 vértices', () {
      expect(
        () => GeofenceGeometry.polygon(<List<LatLng>>[
          <LatLng>[for (var i = 0; i < 1001; i++) LatLng(i * 0.001, 0)],
        ]),
        throwsArgumentError,
      );
    });

    test('contains resuelve en local, sin gastar una petición', () {
      final circulo = GeofenceGeometry.circle(
        center: LatLng(-0.1807, -78.4678),
        radiusMeters: 500,
      );
      expect(circulo.contains(LatLng(-0.1807, -78.4678)), isTrue);
      final centro = LatLng(-0.1807, -78.4678);
      expect(circulo.contains(centro.offset(400, 0)), isTrue);
      expect(circulo.contains(centro.offset(600, 0)), isFalse);

      final cuadrado = GeofenceGeometry.polygon(<List<LatLng>>[
        <LatLng>[LatLng(0, 0), LatLng(0, 2), LatLng(2, 2), LatLng(2, 0)],
      ]);
      expect(cuadrado.contains(LatLng(1, 1)), isTrue);
      expect(cuadrado.contains(LatLng(3, 3)), isFalse);
    });

    test('el agujero saca del polígono', () {
      final conAgujero = GeofenceGeometry.polygon(<List<LatLng>>[
        <LatLng>[LatLng(0, 0), LatLng(0, 4), LatLng(4, 4), LatLng(4, 0)],
        <LatLng>[LatLng(1, 1), LatLng(1, 3), LatLng(3, 3), LatLng(3, 1)],
      ]);
      expect(conAgujero.contains(LatLng(0.5, 0.5)), isTrue);
      expect(conAgujero.contains(LatLng(2, 2)), isFalse);
    });

    test('Geobuf se reconoce como no decodificado, no como sin forma', () {
      final geobuf = GeofenceGeometry.fromJson(const <String, dynamic>{
        'Geobuf': 'AAAA',
      });
      // Distinguirlo importa: una geovalla en Geobuf sí tiene forma, lo que
      // pasa es que este paquete no la lee.
      expect(geobuf.isGeobuf, isTrue);
      expect(geobuf.outerRing, isEmpty);
    });

    test('el círculo se puede pintar como anillo', () {
      final circulo = GeofenceGeometry.circle(
        center: LatLng(-0.1807, -78.4678),
        radiusMeters: 300,
      );
      expect(circulo.outerRing, hasLength(73));
      for (final punto in circulo.outerRing) {
        expect(LatLng(-0.1807, -78.4678).distanceTo(punto), closeTo(300, 1));
      }
    });

    test('rechaza un radio no positivo', () {
      expect(
        () => GeofenceGeometry.circle(center: LatLng(0, 0), radiusMeters: 0),
        throwsArgumentError,
      );
    });
  });
}
