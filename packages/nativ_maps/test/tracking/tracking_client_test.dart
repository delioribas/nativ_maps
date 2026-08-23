// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:nativ_maps/nativ_maps.dart';
import 'package:test/test.dart';

import '../support/fake_service.dart';

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

  group('posiciones', () {
    test(
      'batchUpdateDevicePosition envía la hora del GPS, no la de ahora',
      () async {
        service.stub('/tracking/v0/trackers/flota/positions', {
          'Errors': <dynamic>[],
        });

        final horaDelGps = DateTime.utc(2026, 8, 22, 11, 30);
        await maps.tracking.batchUpdateDevicePosition(
          trackerName: 'flota',
          updates: <DevicePositionUpdate>[
            DevicePositionUpdate(
              deviceId: 'gt06-1',
              position: LatLng(-0.1807, -78.4678),
              sampleTime: horaDelGps,
              horizontalAccuracyMeters: 12,
            ),
          ],
        );

        final enviado =
            (service.lastRequest.body['Updates']! as List<dynamic>).first
                as Map<String, dynamic>;
        // Mandar la hora de envío en vez de la del GPS desordena el histórico y
        // engaña al filtrado por tiempo del rastreador.
        expect(enviado['SampleTime'], '2026-08-22T11:30:00.000Z');
        expect(enviado['Position'], <double>[-78.4678, -0.1807]);
      },
    );

    test('un lote grande se TROCEA en peticiones de 10', () async {
      service.stub('/tracking/v0/trackers/flota/positions', {
        'Errors': <dynamic>[],
      });

      final resultado = await maps.tracking.batchUpdateDevicePosition(
        trackerName: 'flota',
        updates: <DevicePositionUpdate>[
          for (var i = 0; i < 25; i++)
            DevicePositionUpdate(
              deviceId: 'd$i',
              position: LatLng(0, 0),
              sampleTime: DateTime.utc(2026),
            ),
        ],
      );

      // 25 posiciones = 3 peticiones. Quien llama escribió una línea.
      expect(service.requests, hasLength(3));
      expect(
        (service.requests.first.body['Updates']! as List<dynamic>).length,
        10,
      );
      expect(
        (service.requests.last.body['Updates']! as List<dynamic>).length,
        5,
      );
      expect(resultado.total, 25);
      expect(resultado.isCompleteSuccess, isTrue);
    });

    test(
      'los errores por dispositivo se agregan de todos los trozos',
      () async {
        service.stub('/tracking/v0/trackers/flota/positions', {
          'Errors': <dynamic>[
            {
              'DeviceId': 'malo',
              'SampleTime': '2026-08-22T12:00:00.000Z',
              'Error': {'Code': 'ValidationError', 'Message': 'posición mala'},
            },
          ],
        });

        final resultado = await maps.tracking.batchUpdateDevicePosition(
          trackerName: 'flota',
          updates: <DevicePositionUpdate>[
            for (var i = 0; i < 15; i++)
              DevicePositionUpdate(
                deviceId: 'd$i',
                position: LatLng(0, 0),
                sampleTime: DateTime.utc(2026),
              ),
          ],
        );

        // Dos trozos, un error en cada uno.
        expect(resultado.errors, hasLength(2));
        expect(resultado.errors.first.code, 'ValidationError');
        expect(resultado.succeeded, 13);
      },
    );

    test('getDevicePosition lee la última y distingue las dos horas', () async {
      service.stub(
        '/tracking/v0/trackers/flota/devices/gt06-1/positions/latest',
        {
          'DeviceId': 'gt06-1',
          'Position': <double>[-78.4678, -0.1807],
          'SampleTime': '2026-08-22T12:00:00.000Z',
          // Llegó cinco minutos después: cobertura mala.
          'ReceivedTime': '2026-08-22T12:05:00.000Z',
          'Accuracy': {'Horizontal': 9.5},
        },
      );

      final posicion = await maps.tracking.getDevicePosition(
        trackerName: 'flota',
        deviceId: 'gt06-1',
      );

      expect(service.lastRequest.method, 'GET');
      expect(posicion.position.latitude, closeTo(-0.1807, 1e-9));
      expect(posicion.horizontalAccuracyMeters, 9.5);
      // La diferencia es el retraso de la red. Enseñar `receivedTime` como
      // «última posición» hace creer que el vehículo estaba ahí hace un
      // momento cuando la medida es de antes.
      expect(posicion.networkDelay, const Duration(minutes: 5));
    });

    test(
      'una posición ilegible LANZA, no devuelve el golfo de Guinea',
      () async {
        service.stub('/tracking/v0/trackers/flota/devices/x/positions/latest', {
          'DeviceId': 'x',
          'SampleTime': '2026-08-22T12:00:00.000Z',
        });

        await expectLater(
          maps.tracking.getDevicePosition(trackerName: 'flota', deviceId: 'x'),
          throwsFormatException,
        );
      },
    );

    test('batchGetDevicePosition separa posiciones de errores', () async {
      service.stub('/tracking/v0/trackers/flota/get-positions', {
        'DevicePositions': <dynamic>[
          {
            'DeviceId': 'a',
            'Position': <double>[-78.4, -0.18],
            'SampleTime': '2026-08-22T12:00:00.000Z',
            'ReceivedTime': '2026-08-22T12:00:01.000Z',
          },
        ],
        'Errors': <dynamic>[
          {
            'DeviceId': 'b',
            'Error': {'Code': 'ResourceNotFoundError', 'Message': 'no existe'},
          },
        ],
      });

      final r = await maps.tracking.batchGetDevicePosition(
        trackerName: 'flota',
        deviceIds: <String>['a', 'b'],
      );

      expect(r.positions, hasLength(1));
      expect(r.result.errors, hasLength(1));
      // Un dispositivo que no existe no tumba la llamada entera.
      expect(r.result.succeeded, 1);
    });

    test('getDevicePositionHistory pagina y ordena las fechas', () async {
      service.stub(
        '/tracking/v0/trackers/flota/devices/gt06-1/list-positions',
        {
          'DevicePositions': <dynamic>[
            {
              'DeviceId': 'gt06-1',
              'Position': <double>[-78.4, -0.18],
              'SampleTime': '2026-08-22T10:00:00.000Z',
              'ReceivedTime': '2026-08-22T10:00:02.000Z',
            },
          ],
          'NextToken': 'p2',
        },
      );

      final historico = await maps.tracking.getDevicePositionHistory(
        trackerName: 'flota',
        deviceId: 'gt06-1',
        from: DateTime.utc(2026, 8, 22, 8),
        to: DateTime.utc(2026, 8, 22, 12),
        maxResults: 100,
      );

      expect(
        service.lastRequest.body['StartTimeInclusive'],
        '2026-08-22T08:00:00.000Z',
      );
      expect(historico.items, hasLength(1));
      expect(historico.hasMore, isTrue);
    });

    test('fechas al revés o maxResults fuera de rango lanzan', () async {
      expect(
        () => maps.tracking.getDevicePositionHistory(
          trackerName: 'f',
          deviceId: 'd',
          from: DateTime.utc(2026, 8, 22, 12),
          to: DateTime.utc(2026, 8, 22, 8),
        ),
        throwsArgumentError,
      );
      expect(
        () => maps.tracking.getDevicePositionHistory(
          trackerName: 'f',
          deviceId: 'd',
          maxResults: 500,
        ),
        throwsArgumentError,
      );
      expect(service.requests, isEmpty);
    });

    test('listDevicePositions filtra por polígono y lo cierra', () async {
      service.stub('/tracking/v0/trackers/flota/list-positions', {
        'Entries': <dynamic>[
          {
            'DeviceId': 'a',
            'Position': <double>[-78.4, -0.18],
            'SampleTime': '2026-08-22T12:00:00.000Z',
          },
        ],
      });

      await maps.tracking.listDevicePositions(
        trackerName: 'flota',
        filterGeometry: <LatLng>[
          LatLng(-0.2, -78.5),
          LatLng(-0.2, -78.4),
          LatLng(-0.1, -78.4),
        ],
      );

      final anillo =
          ((service.lastRequest.body['FilterGeometry']!
                          as Map<String, dynamic>)['Polygon']!
                      as List<dynamic>)
                  .first
              as List<dynamic>;
      // Cerrado: cuatro puntos para un triángulo.
      expect(anillo, hasLength(4));
      expect(anillo.first.toString(), anillo.last.toString());
    });

    test('un polígono de menos de 3 puntos lanza', () async {
      expect(
        () => maps.tracking.listDevicePositions(
          trackerName: 'f',
          filterGeometry: <LatLng>[LatLng(0, 0), LatLng(1, 1)],
        ),
        throwsArgumentError,
      );
    });
  });

  group('verificación de posición', () {
    test('convierte la desviación a metros y detecta el proxy', () async {
      service.stub('/tracking/v0/trackers/flota/positions/verify', {
        'DeviceId': 'gt06-1',
        'SampleTime': '2026-08-22T12:00:00.000Z',
        'ReceivedTime': '2026-08-22T12:00:01.000Z',
        'DistanceUnit': 'Kilometers',
        'InferredState': {
          'Position': <double>[-79.9, -2.17],
          'DeviationDistance': 274.5, // KILÓMETROS en la respuesta cruda
          'ProxyDetected': true,
          'Accuracy': {'Horizontal': 1500},
        },
      });

      final v = await maps.tracking.verifyDevicePosition(
        trackerName: 'flota',
        deviceId: 'gt06-1',
        position: LatLng(-0.1807, -78.4678),
        sampleTime: DateTime.utc(2026, 8, 22, 12),
        ipv4Address: '190.0.0.1',
        wifiAccessPoints: const <WiFiAccessPoint>[
          WiFiAccessPoint(macAddress: 'aa:bb:cc:dd:ee:ff', rss: -60),
        ],
      );

      // Se pide en kilómetros y se convierte, como el resto del paquete.
      expect(service.lastRequest.body['DistanceUnit'], 'Kilometers');
      expect(v.deviationMeters, 274500.0);
      expect(v.proxyDetected, isTrue);
      // Declara estar en Quito y todo apunta a Guayaquil, por un proxy.
      expect(v.isSuspicious(), isTrue);

      final estado =
          service.lastRequest.body['DeviceState']! as Map<String, dynamic>;
      expect(estado['Ipv4Address'], '190.0.0.1');
      expect(estado['WiFiAccessPoints']! as List<dynamic>, hasLength(1));
    });

    test('una desviación pequeña sin proxy no es sospechosa', () async {
      service.stub('/tracking/v0/trackers/flota/positions/verify', {
        'DeviceId': 'd',
        'InferredState': {
          'DeviationDistance': 0.8, // 800 m
          'ProxyDetected': false,
        },
      });

      final v = await maps.tracking.verifyDevicePosition(
        trackerName: 'flota',
        deviceId: 'd',
        position: LatLng(0, 0),
        sampleTime: DateTime.utc(2026),
      );
      expect(v.deviationMeters, 800.0);
      // El umbral por defecto es generoso a propósito: la localización por
      // antenas tiene kilómetros de error en zona rural.
      expect(v.isSuspicious(), isFalse);
      expect(v.isSuspicious(maxDeviationMeters: 500), isTrue);
    });
  });

  group('rastreadores', () {
    test('createTracker usa DistanceBased por defecto, no TimeBased', () async {
      service.stub('/tracking/v0/trackers', {
        'TrackerName': 'flota',
        'TrackerArn': 'arn:aws:geo:us-east-1:1:tracker/flota',
        'CreateTime': '2026-08-22T12:00:00.000Z',
      });

      await maps.tracking.createTracker(trackerName: 'flota');

      // El valor por defecto del SERVICIO es TimeBased, que guarda una
      // posición cada 30 s aunque el vehículo esté parado. Este paquete elige
      // DistanceBased, que es lo correcto para rastreo de vehículos.
      expect(service.lastRequest.body['PositionFiltering'], 'DistanceBased');
    });

    test('describeTracker lee el filtrado configurado', () async {
      service.stub('/tracking/v0/trackers/flota', {
        'TrackerName': 'flota',
        'TrackerArn': 'arn:…',
        'Description': 'Flota de Quito',
        'PositionFiltering': 'AccuracyBased',
        'EventBridgeEnabled': true,
      });

      final rastreador = await maps.tracking.describeTracker('flota');
      expect(rastreador.positionFiltering, PositionFiltering.accuracyBased);
      expect(rastreador.eventBridgeEnabled, isTrue);
    });

    test('updateTracker usa PATCH y deleteTracker DELETE', () async {
      service.stub('/tracking/v0/trackers/flota', {
        'TrackerName': 'flota',
        'TrackerArn': 'arn:…',
        'UpdateTime': '2026-08-22T12:00:00.000Z',
      });

      await maps.tracking.updateTracker(
        trackerName: 'flota',
        positionFiltering: PositionFiltering.distanceBased,
      );
      expect(service.lastRequest.method, 'PATCH');

      service.stub('/tracking/v0/trackers/flota', <String, dynamic>{});
      await maps.tracking.deleteTracker('flota');
      expect(service.lastRequest.method, 'DELETE');
    });

    test('listTrackers lee su página', () async {
      service.stub('/tracking/v0/list-trackers', {
        'Entries': <dynamic>[
          {'TrackerName': 'flota', 'Description': 'x'},
        ],
      });
      final r = await maps.tracking.listTrackers();
      expect(r.items.first.trackerName, 'flota');
    });
  });

  group('el enlace con las geovallas', () {
    test('associateConsumer es lo que hace que todo funcione solo', () async {
      service.stub(
        '/tracking/v0/trackers/flota/consumers',
        <String, dynamic>{},
      );

      await maps.tracking.associateConsumer(
        trackerName: 'flota',
        collectionArn: 'arn:aws:geo:us-east-1:1:geofence-collection/zonas',
      );

      expect(service.lastRequest.method, 'POST');
      // Es el ARN completo, no el nombre.
      expect(
        service.lastRequest.body['ConsumerArn'],
        contains('geofence-collection'),
      );
    });

    test('listConsumers es lo primero que mirar si no disparan', () async {
      service.stub('/tracking/v0/trackers/flota/list-consumers', {
        'ConsumerArns': <String>['arn:aws:geo:us-east-1:1:x/zonas'],
      });
      final r = await maps.tracking.listConsumers(trackerName: 'flota');
      expect(r.items, hasLength(1));
    });

    test('disassociateConsumer usa DELETE con el ARN en la ruta', () async {
      const arn = 'arn:aws:geo:us-east-1:1:geofence-collection/zonas';
      service.stub(
        '/tracking/v0/trackers/flota/consumers/${Uri.encodeComponent(arn)}',
        <String, dynamic>{},
      );
      await maps.tracking.disassociateConsumer(
        trackerName: 'flota',
        collectionArn: arn,
      );
      expect(service.lastRequest.method, 'DELETE');
    });
  });

  group('DevicePosition', () {
    test('isFresh distingue «dónde está» de «dónde estuvo»', () {
      final reciente = DevicePosition(
        position: LatLng(0, 0),
        sampleTime: DateTime.now().toUtc().subtract(const Duration(minutes: 2)),
      );
      final vieja = DevicePosition(
        position: LatLng(0, 0),
        sampleTime: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      );
      expect(reciente.isFresh(), isTrue);
      // Un vehículo con una posición de hace una hora NO está ahí.
      expect(vieja.isFresh(), isFalse);
      expect(vieja.age.inMinutes, greaterThanOrEqualTo(59));
    });
  });

  group('la clave de API tampoco sirve para rastreo', () {
    test('se corta antes de enviar', () async {
      final conClave = fakeNativMaps(service);
      addTearDown(conClave.close);
      await expectLater(
        conClave.tracking.listTrackers(),
        throwsA(isA<NativMapsConfigurationException>()),
      );
      expect(service.requests, isEmpty);
    });
  });
}
