// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:convert';
import 'dart:io';

import 'package:nativ_maps/nativ_maps.dart';
import 'package:test/test.dart';

import '../support/fake_service.dart';

/// Geovallas y rastreo contra respuestas **reales** de AWS.
///
/// Las de `test/fixtures/aws/` salieron de `live_iam_test.dart` de
/// `nativ_maps_sigv4` el 19-10-2026, en us-east-1, con el número de cuenta y
/// los nombres de los recursos cambiados. Lo que se prueba aquí es lo que una
/// respuesta inventada no habría enseñado: que estas operaciones contestan en
/// **kilómetros** —son de la generación anterior— y el paquete promete metros.
final _sigv4 = HeaderCredentials(
  (service, region) async => <String, String>{'Authorization': 'AWS4-firmado'},
);

Map<String, dynamic> _real(String nombre) =>
    jsonDecode(File('test/fixtures/aws/$nombre.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  late FakeAlsService service;
  late NativMaps maps;

  setUp(() {
    service = FakeAlsService();
    maps = fakeNativMaps(service, credentials: _sigv4);
  });

  tearDown(() => maps.close());

  test(
    'forecastGeofenceEvents: la distancia llega en km y sale en metros',
    () async {
      service.stub(
        '/geofencing/v0/collections/zonas/forecast-geofence-events',
        _real('forecastGeofenceEvents'),
      );

      final forecast = await maps.geofencing.forecastGeofenceEvents(
        collectionName: 'zonas',
        position: LatLng(-0.1720, -78.4840),
        speedKmh: 40,
        timeHorizon: const Duration(minutes: 10),
      );

      expect(forecast.events, hasLength(2));
      final carolina = forecast.events.first;
      expect(carolina.geofenceId, 'carolina');
      expect(carolina.eventType, ForecastedEventType.enter);
      expect(carolina.isDeviceInGeofence, isFalse);
      // AWS dijo 0,769 km.
      expect(carolina.nearestDistance, closeTo(769, 1e-6));
      expect(
        carolina.forecastedBreachTime,
        DateTime.utc(2026, 10, 19, 6, 50, 48, 830),
      );
      expect(carolina.geofenceProperties, <String, String>{'zona': 'parque'});
      expect(forecast.breaches, hasLength(2));
    },
  );

  test(
    'verifyDevicePosition: el desvío en metros, la precisión ya lo era',
    () async {
      service.stub(
        '/tracking/v0/trackers/flota/positions/verify',
        _real('verifyDevicePosition'),
      );

      final verificacion = await maps.tracking.verifyDevicePosition(
        trackerName: 'flota',
        deviceId: 'taxi-1',
        position: LatLng(-0.1760, -78.4844),
        sampleTime: DateTime.utc(2026, 10, 19, 6, 49, 41),
      );

      expect(verificacion.deviceId, 'taxi-1');
      expect(verificacion.proxyDetected, isFalse);
      // DeviationDistance: 7,352 km.
      expect(verificacion.deviationMeters, closeTo(7352, 1e-6));
      // Accuracy.Horizontal va siempre en metros, aunque DistanceUnit diga km.
      expect(verificacion.inferredAccuracyMeters, 20000);
      expect(verificacion.inferredPosition!.latitude, closeTo(-0.2309, 1e-9));
    },
  );

  test('getDevicePositionHistory: en orden y con la precisión', () async {
    service.stub(
      '/tracking/v0/trackers/flota/devices/taxi-1/list-positions',
      _real('getDevicePositionHistory'),
    );

    final page = await maps.tracking.getDevicePositionHistory(
      trackerName: 'flota',
      deviceId: 'taxi-1',
    );

    expect(page.items.map((p) => p.position.latitude), <double>[
      -0.17,
      -0.172,
      -0.174,
      -0.176,
    ]);
    expect(page.items.first.horizontalAccuracyMeters, 5);
    expect(
      page.items.first.sampleTime,
      DateTime.utc(2026, 10, 19, 6, 41, 40, 837),
    );
    expect(page.items.first.receivedTime, isNotNull);
    expect(page.hasMore, isFalse);
  });

  test('batchGetDevicePosition: dos dispositivos, sin errores', () async {
    service.stub(
      '/tracking/v0/trackers/flota/get-positions',
      _real('batchGetDevicePosition'),
    );

    final result = await maps.tracking.batchGetDevicePosition(
      trackerName: 'flota',
      deviceIds: const <String>['taxi-1', 'taxi-2'],
    );

    expect(result.positions.map((p) => p.deviceId), <String>[
      'taxi-1',
      'taxi-2',
    ]);
    expect(result.positions.last.position.longitude, closeTo(-78.5123, 1e-9));
    expect(result.positions.last.horizontalAccuracyMeters, 8);
    expect(result.result.errors, isEmpty);
  });

  test('listDevicePositions: las entradas traen el dispositivo', () async {
    service.stub(
      '/tracking/v0/trackers/flota/list-positions',
      _real('listDevicePositions'),
    );

    final page = await maps.tracking.listDevicePositions(trackerName: 'flota');

    expect(page.items.single.deviceId, 'taxi-1');
    expect(page.items.single.position.latitude, closeTo(-0.176, 1e-9));
  });

  test('getGeofence: círculo, estado y propiedades', () async {
    service.stub(
      '/geofencing/v0/collections/zonas/geofences/carolina',
      _real('getGeofence'),
    );

    final geovalla = await maps.geofencing.getGeofence(
      collectionName: 'zonas',
      geofenceId: 'carolina',
    );

    expect(geovalla.geometry.circle!.radiusMeters, 400);
    expect(geovalla.geometry.circle!.center.longitude, closeTo(-78.484, 1e-9));
    expect(geovalla.isActive, isTrue);
    expect(geovalla.properties, <String, String>{'zona': 'parque'});
  });

  test(
    'batchPutGeofence: el error real de un anillo en sentido horario',
    () async {
      // Lo que respondió AWS antes de que el paquete orientara los anillos: un
      // 200 con la mitad del lote fallida. Por eso hay que mirar `errors`.
      service.stub(
        '/geofencing/v0/collections/zonas/put-geofences',
        _real('batchPutGeofence-horario'),
      );

      final result = await maps.geofencing.batchPutGeofence(
        collectionName: 'zonas',
        geofences: <Geofence>[
          Geofence(
            geofenceId: 'aeropuerto',
            geometry: GeofenceGeometry.circle(
              center: LatLng(-0.1292, -78.3575),
              radiusMeters: 1500,
            ),
          ),
        ],
      );

      expect(result.isCompleteSuccess, isFalse);
      final error = result.errors.single;
      expect(error.itemId, 'centro-historico');
      expect(error.code, 'ValidationError');
      expect(error.message, contains('counter-clockwise'));
    },
  );

  test('describeTracker y listConsumers', () async {
    service
      ..stub('/tracking/v0/trackers/flota', _real('describeTracker'))
      ..stub(
        '/tracking/v0/trackers/flota/list-consumers',
        _real('listConsumers'),
      );

    final tracker = await maps.tracking.describeTracker('flota');
    expect(tracker.positionFiltering, PositionFiltering.distanceBased);
    expect(tracker.eventBridgeEnabled, isFalse);

    final consumers = await maps.tracking.listConsumers(trackerName: 'flota');
    expect(
      consumers.items.single,
      'arn:aws:geo:us-east-1:123456789012:geofence-collection/zonas',
    );
  });
}
