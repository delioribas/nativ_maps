// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

/// Las 27 operaciones de geovallas y rastreo, contra Amazon Location de
/// verdad y firmadas con SigV4.
///
/// `dart test` las salta. Se lanzan a propósito, desde
/// `packages/nativ_maps_sigv4`, con credenciales IAM en el entorno:
///
/// ```sh
/// set -a; source ../../.env; set +a
/// dart test -P live
/// ```
///
/// **Crea recursos en la cuenta** —una colección de geovallas y un
/// rastreador, con el prefijo `nativ-maps-live-`— y los borra al terminar,
/// también si algo falla por el camino. El coste de una pasada son céntimos.
///
/// Cada respuesta se guarda en `test/live/respuestas/`, que git ignora.
@Tags(<String>['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:nativ_maps/nativ_maps.dart';
import 'package:nativ_maps_sigv4/nativ_maps_sigv4.dart';
import 'package:test/test.dart';

void main() {
  final env = Platform.environment;
  final accessKeyId = env['AWS_ACCESS_KEY_ID'];
  final secretAccessKey = env['AWS_SECRET_ACCESS_KEY'];
  final region = env['AWS_REGION'] ?? env['ALS_REGION'] ?? 'us-east-1';

  // Quito. La Carolina es la geovalla circular; el taxi 1 baja hacia ella por
  // el norte y el taxi 2 está en el centro histórico.
  final carolina = LatLng(-0.1825, -78.4840);
  final plazaGrande = LatLng(-0.2201, -78.5123);
  final recorrido = <LatLng>[
    LatLng(-0.1700, -78.4850),
    LatLng(-0.1720, -78.4848),
    LatLng(-0.1740, -78.4846),
    LatLng(-0.1760, -78.4844),
  ];

  final stamp = DateTime.now().millisecondsSinceEpoch;
  final collection = 'nativ-maps-live-$stamp';
  final tracker = 'nativ-maps-live-$stamp';

  late _Recorder recorder;
  late NativMaps maps;
  String? collectionArn;
  var collectionAlive = false;
  var trackerAlive = false;

  /// Repite [read] hasta que [done] se cumpla: el rastreo tarda unos
  /// segundos en reflejar una posición recién enviada.
  Future<T> eventually<T>(
    Future<T> Function() read,
    bool Function(T) done,
  ) async {
    late T last;
    for (var i = 0; i < 15; i++) {
      last = await read();
      if (done(last)) return last;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return last;
  }

  group(
    'contra AWS con IAM',
    skip: accessKeyId == null || secretAccessKey == null
        ? 'Faltan AWS_ACCESS_KEY_ID y AWS_SECRET_ACCESS_KEY. Carga el .env.'
        : false,
    () {
      setUpAll(() {
        recorder = _Recorder();
        maps = NativMaps(
          region: region,
          credentials: SigV4Credentials.fixed(
            AwsCredentials(
              accessKeyId: accessKeyId!,
              secretAccessKey: secretAccessKey!,
            ),
          ),
          httpClient: recorder,
        );
      });

      // Pase lo que pase, la cuenta queda como estaba.
      tearDownAll(() async {
        if (trackerAlive) {
          await _quietly(() => maps.tracking.deleteTracker(tracker));
        }
        if (collectionAlive) {
          await _quietly(() => maps.geofencing.deleteCollection(collection));
        }
        maps.close();
        recorder.close();
      });

      group('geovallas', () {
        test('createCollection', () async {
          recorder.label = 'createCollection';
          final created = await maps.geofencing.createCollection(
            collectionName: collection,
            description: 'nativ_maps: prueba en vivo',
          );
          collectionAlive = true;
          collectionArn = created.collectionArn;
          expect(created.collectionName, collection);
          expect(collectionArn, contains(':geofence-collection/$collection'));
        });

        test('describeCollection', () async {
          recorder.label = 'describeCollection';
          final described = await maps.geofencing.describeCollection(
            collection,
          );
          expect(described.description, 'nativ_maps: prueba en vivo');
          expect(described.createTime, isNotNull);
        });

        test('updateCollection', () async {
          recorder.label = 'updateCollection';
          await maps.geofencing.updateCollection(
            collectionName: collection,
            description: 'nativ_maps: actualizada',
          );
          final described = await maps.geofencing.describeCollection(
            collection,
          );
          expect(described.description, 'nativ_maps: actualizada');
        });

        test('listCollections', () async {
          recorder.label = 'listCollections';
          final page = await maps.geofencing.listCollections();
          expect(page.items.map((c) => c.collectionName), contains(collection));
        });

        test('putGeofence', () async {
          recorder.label = 'putGeofence';
          await maps.geofencing.putGeofence(
            collectionName: collection,
            geofenceId: 'carolina',
            geometry: GeofenceGeometry.circle(
              center: carolina,
              radiusMeters: 400,
            ),
            properties: const <String, String>{'zona': 'parque'},
          );
        });

        test('batchPutGeofence, con un anillo en sentido horario', () async {
          recorder.label = 'batchPutGeofence';
          // Noroeste → noreste → sureste → suroeste: como lo dibujaría
          // cualquiera, y en sentido horario.
          final result = await maps.geofencing.batchPutGeofence(
            collectionName: collection,
            geofences: <Geofence>[
              Geofence(
                geofenceId: 'centro-historico',
                geometry: GeofenceGeometry.polygon(<List<LatLng>>[
                  <LatLng>[
                    LatLng(-0.2180, -78.5150),
                    LatLng(-0.2180, -78.5100),
                    LatLng(-0.2225, -78.5100),
                    LatLng(-0.2225, -78.5150),
                  ],
                ]),
              ),
              Geofence(
                geofenceId: 'aeropuerto',
                geometry: GeofenceGeometry.circle(
                  center: LatLng(-0.1292, -78.3575),
                  radiusMeters: 1500,
                ),
              ),
            ],
          );
          expect(result.total, 2);
          expect(result.errors, isEmpty, reason: '${result.errors}');
        });

        test('getGeofence', () async {
          recorder.label = 'getGeofence';
          final geofence = await maps.geofencing.getGeofence(
            collectionName: collection,
            geofenceId: 'carolina',
          );
          expect(geofence.geometry.circle?.radiusMeters, 400);
          expect(
            geofence.geometry.circle?.center.latitude,
            closeTo(-0.1825, 1e-6),
          );
          expect(geofence.properties, <String, String>{'zona': 'parque'});
        });

        test('listGeofences', () async {
          recorder.label = 'listGeofences';
          final page = await maps.geofencing.listGeofences(
            collectionName: collection,
          );
          expect(
            page.items.map((g) => g.geofenceId),
            unorderedEquals(<String>[
              'carolina',
              'centro-historico',
              'aeropuerto',
            ]),
          );
        });

        test('batchEvaluateGeofences devuelve solo errores', () async {
          recorder.label = 'batchEvaluateGeofences';
          final result = await maps.geofencing.batchEvaluateGeofences(
            collectionName: collection,
            positions: <DevicePositionUpdate>[
              DevicePositionUpdate(
                deviceId: 'taxi-1',
                position: carolina,
                sampleTime: DateTime.now().toUtc(),
              ),
            ],
          );
          expect(result.errors, isEmpty, reason: '${result.errors}');
        });

        test(
          'forecastGeofenceEvents prevé la entrada en La Carolina',
          () async {
            recorder.label = 'forecastGeofenceEvents';
            // A ~1,2 km al norte del centro, a 40 km/h: llega en un par de
            // minutos.
            final forecast = await maps.geofencing.forecastGeofenceEvents(
              collectionName: collection,
              position: LatLng(-0.1720, -78.4840),
              speedKmh: 40,
              timeHorizon: const Duration(minutes: 10),
            );
            final carolinaEvents = forecast.events.where(
              (e) => e.geofenceId == 'carolina',
            );
            expect(carolinaEvents, isNotEmpty, reason: '${forecast.events}');
            expect(carolinaEvents.first.eventType, ForecastedEventType.enter);
            expect(carolinaEvents.first.isDeviceInGeofence, isFalse);
          },
        );

        test('batchDeleteGeofence', () async {
          recorder.label = 'batchDeleteGeofence';
          final result = await maps.geofencing.batchDeleteGeofence(
            collectionName: collection,
            geofenceIds: const <String>['aeropuerto'],
          );
          expect(result.errors, isEmpty, reason: '${result.errors}');
        });
      });

      group('rastreo', () {
        test('createTracker', () async {
          recorder.label = 'createTracker';
          final created = await maps.tracking.createTracker(
            trackerName: tracker,
            description: 'nativ_maps: prueba en vivo',
          );
          trackerAlive = true;
          expect(created.trackerName, tracker);
          expect(created.trackerArn, contains(':tracker/$tracker'));
        });

        test('describeTracker', () async {
          recorder.label = 'describeTracker';
          final described = await maps.tracking.describeTracker(tracker);
          expect(described.positionFiltering, PositionFiltering.distanceBased);
        });

        test('updateTracker', () async {
          recorder.label = 'updateTracker';
          await maps.tracking.updateTracker(
            trackerName: tracker,
            description: 'nativ_maps: actualizado',
          );
          final described = await maps.tracking.describeTracker(tracker);
          expect(described.description, 'nativ_maps: actualizado');
        });

        test('updateTracker acepta los tres filtrados', () async {
          recorder.label = 'updateTracker-filtrado';
          // Acaba en distanceBased, que es con el que sigue la prueba.
          for (final filtering in <PositionFiltering>[
            PositionFiltering.timeBased,
            PositionFiltering.accuracyBased,
            PositionFiltering.distanceBased,
          ]) {
            await maps.tracking.updateTracker(
              trackerName: tracker,
              positionFiltering: filtering,
            );
            final described = await maps.tracking.describeTracker(tracker);
            expect(described.positionFiltering, filtering);
          }
        });

        test('listTrackers', () async {
          recorder.label = 'listTrackers';
          final page = await maps.tracking.listTrackers();
          expect(page.items.map((t) => t.trackerName), contains(tracker));
        });

        test('associateConsumer', () async {
          recorder.label = 'associateConsumer';
          await maps.tracking.associateConsumer(
            trackerName: tracker,
            collectionArn: collectionArn!,
          );
        });

        test('listConsumers', () async {
          recorder.label = 'listConsumers';
          final page = await maps.tracking.listConsumers(trackerName: tracker);
          expect(page.items, contains(collectionArn));
        });

        test('batchUpdateDevicePosition', () async {
          recorder.label = 'batchUpdateDevicePosition';
          // La hora del GPS, en orden: un punto cada dos minutos, terminando
          // hace dos.
          final now = DateTime.now().toUtc();
          final result = await maps.tracking.batchUpdateDevicePosition(
            trackerName: tracker,
            updates: <DevicePositionUpdate>[
              for (var i = 0; i < recorrido.length; i++)
                DevicePositionUpdate(
                  deviceId: 'taxi-1',
                  position: recorrido[i],
                  sampleTime: now.subtract(
                    Duration(minutes: 2 * (recorrido.length - i)),
                  ),
                  horizontalAccuracyMeters: 5,
                ),
              DevicePositionUpdate(
                deviceId: 'taxi-2',
                position: plazaGrande,
                sampleTime: now.subtract(const Duration(minutes: 1)),
                horizontalAccuracyMeters: 8,
              ),
            ],
          );
          expect(result.total, recorrido.length + 1);
          expect(result.errors, isEmpty, reason: '${result.errors}');
        });

        test('getDevicePosition', () async {
          recorder.label = 'getDevicePosition';
          final position = await eventually(
            () => maps.tracking.getDevicePosition(
              trackerName: tracker,
              deviceId: 'taxi-1',
            ),
            (p) => p.position.latitude.toStringAsFixed(4) == '-0.1760',
          );
          expect(position.position.latitude, closeTo(-0.1760, 1e-6));
          expect(position.position.longitude, closeTo(-78.4844, 1e-6));
          expect(position.horizontalAccuracyMeters, 5);
        });

        test('batchGetDevicePosition', () async {
          recorder.label = 'batchGetDevicePosition';
          final result = await maps.tracking.batchGetDevicePosition(
            trackerName: tracker,
            deviceIds: const <String>['taxi-1', 'taxi-2'],
          );
          expect(
            result.positions.map((p) => p.deviceId),
            unorderedEquals(<String>['taxi-1', 'taxi-2']),
          );
          expect(result.result.errors, isEmpty);
        });

        test('getDevicePositionHistory, en orden', () async {
          recorder.label = 'getDevicePositionHistory';
          final page = await eventually(
            () => maps.tracking.getDevicePositionHistory(
              trackerName: tracker,
              deviceId: 'taxi-1',
              from: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
            ),
            (p) => p.items.length >= recorrido.length,
          );
          expect(page.items, hasLength(recorrido.length));
          expect(
            page.items.map((p) => p.position.latitude.toStringAsFixed(4)),
            <String>['-0.1700', '-0.1720', '-0.1740', '-0.1760'],
          );
        });

        test('listDevicePositions con filtro de zona', () async {
          recorder.label = 'listDevicePositions';
          // El norte de Quito: el taxi 1 dentro, el 2 fuera.
          final page = await maps.tracking.listDevicePositions(
            trackerName: tracker,
            filterGeometry: <LatLng>[
              LatLng(-0.1600, -78.5000),
              LatLng(-0.1600, -78.4700),
              LatLng(-0.1900, -78.4700),
              LatLng(-0.1900, -78.5000),
            ],
          );
          expect(page.items.map((p) => p.deviceId), <String>['taxi-1']);
        });

        test('verifyDevicePosition', () async {
          recorder.label = 'verifyDevicePosition';
          final verification = await maps.tracking.verifyDevicePosition(
            trackerName: tracker,
            deviceId: 'taxi-1',
            position: recorrido.last,
            sampleTime: DateTime.now().toUtc(),
            horizontalAccuracyMeters: 5,
          );
          expect(verification.deviceId, 'taxi-1');
        });

        test('disassociateConsumer', () async {
          recorder.label = 'disassociateConsumer';
          await maps.tracking.disassociateConsumer(
            trackerName: tracker,
            collectionArn: collectionArn!,
          );
          final page = await maps.tracking.listConsumers(trackerName: tracker);
          expect(page.items, isEmpty);
        });

        test('batchDeleteDevicePositionHistory', () async {
          recorder.label = 'batchDeleteDevicePositionHistory';
          final result = await maps.tracking.batchDeleteDevicePositionHistory(
            trackerName: tracker,
            deviceIds: const <String>['taxi-1', 'taxi-2'],
          );
          expect(result.errors, isEmpty, reason: '${result.errors}');
        });

        test('deleteTracker', () async {
          recorder.label = 'deleteTracker';
          await maps.tracking.deleteTracker(tracker);
          trackerAlive = false;
        });
      });

      test('deleteCollection', () async {
        recorder.label = 'deleteCollection';
        await maps.geofencing.deleteCollection(collection);
        collectionAlive = false;
      });
    },
  );
}

Future<void> _quietly(Future<void> Function() action) async {
  try {
    await action();
  } on Object catch (error) {
    stderr.writeln('limpieza: $error');
  }
}

/// Guarda cada petición y su respuesta, sin cabeceras: la firma y el
/// identificador de la clave van ahí.
class _Recorder extends http.BaseClient {
  final http.Client _inner = http.Client();
  final Directory _directory = Directory('test/live/respuestas');
  final Map<String, int> _counts = <String, int>{};

  String label = 'sin-nombre';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final requestBody = request is http.Request ? request.body : '';
    final response = await _inner.send(request);
    final bytes = await response.stream.toBytes();

    _directory.createSync(recursive: true);
    final count = _counts[label] = (_counts[label] ?? 0) + 1;
    final name = count == 1 ? label : '$label-$count';
    File('${_directory.path}/$name.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'request': <String, Object?>{
          'method': request.method,
          'url': request.url.toString(),
          if (requestBody.isNotEmpty) 'body': _decode(requestBody),
        },
        'status': response.statusCode,
        'requestId': response.headers['x-amzn-requestid'],
        'response': _decode(utf8.decode(bytes, allowMalformed: true)),
      }),
    );

    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      response.statusCode,
      contentLength: bytes.length,
      headers: response.headers,
      request: request,
      reasonPhrase: response.reasonPhrase,
    );
  }

  static Object? _decode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return text;
    }
  }

  @override
  void close() => _inner.close();
}
