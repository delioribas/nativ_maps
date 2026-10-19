// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

/// The conformance test for a `ProxyCredentials` server.
///
/// Any proxy —the reference ones in `proxies/` or your own— is right when
/// this passes against it. It goes through the proxy the way the package
/// does, and the way the map renderer does, and checks what a proxy must
/// refuse.
///
/// Skipped by `dart test`. With the proxy running, from `packages/nativ_maps`:
///
/// ```sh
/// PROXY_URL=http://localhost:8080/geo PROXY_TOKEN=… AWS_REGION=us-east-1 \
///   dart test -P proxy
/// ```
///
/// It creates a geofence collection and a tracker named `nativ-maps-proxy-…`
/// through the proxy and deletes them at the end, so the proxy's AWS
/// credentials need geofencing and tracking permissions. About 25 requests.
@Tags(<String>['proxy'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:nativ_maps/nativ_maps.dart';
import 'package:test/test.dart';

void main() {
  final env = Platform.environment;
  final proxyUrl = env['PROXY_URL'];
  final token = env['PROXY_TOKEN'] ?? '';
  final region = env['AWS_REGION'] ?? env['ALS_REGION'] ?? 'us-east-1';

  final carolina = LatLng(-0.1825, -78.4840);
  final quicentro = LatLng(-0.1762, -78.4797);
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final collection = 'nativ-maps-proxy-$stamp';
  final tracker = 'nativ-maps-proxy-$stamp';

  late NativMaps maps;
  late Uri base;
  final client = http.Client();
  var collectionAlive = false;
  var trackerAlive = false;

  Map<String, String> auth() => <String, String>{
    'Authorization': 'Bearer $token',
  };

  group(
    'proxy conformance',
    skip: proxyUrl == null
        ? 'Missing PROXY_URL: start a proxy and point the test at it.'
        : false,
    () {
      setUpAll(() {
        base = Uri.parse(proxyUrl!);
        maps = NativMaps(
          region: region,
          credentials: ProxyCredentials(baseUrl: base, headers: auth()),
        );
      });

      tearDownAll(() async {
        if (trackerAlive) {
          await maps.tracking.deleteTracker(tracker).catchError((_) {});
        }
        if (collectionAlive) {
          await maps.geofencing.deleteCollection(collection).catchError((_) {});
        }
        maps.close();
        client.close();
      });

      Uri at(String path, [Map<String, String>? query]) =>
          base.replace(path: '${base.path}$path', queryParameters: query);

      group('refuses', () {
        test('a request without the app token: 401', () async {
          final r = await client.post(
            at('/v2/suggest'),
            headers: <String, String>{
              'X-Nativ-Host': 'places.geo.$region.amazonaws.com',
            },
          );
          expect(r.statusCode, 401);
        });

        test('a wrong token: 401', () async {
          final r = await client.post(
            at('/v2/suggest'),
            headers: <String, String>{
              'Authorization': 'Bearer not-the-token',
              'X-Nativ-Host': 'places.geo.$region.amazonaws.com',
            },
          );
          expect(r.statusCode, 401);
        });

        for (final host in <String>[
          'example.com',
          'places.geo.$region.amazonaws.com.evil.com',
          'evil.com/places.geo.$region.amazonaws.com',
          's3.amazonaws.com',
          'places.geo.$region.amazonaws.com:8443',
        ]) {
          test('forwarding to $host: 400', () async {
            final r = await client.post(
              at('/v2/suggest'),
              headers: <String, String>{...auth(), 'X-Nativ-Host': host},
            );
            expect(r.statusCode, 400);
          });
        }

        test('a non-map path without X-Nativ-Host: 400', () async {
          final r = await client.post(at('/v2/suggest'), headers: auth());
          expect(r.statusCode, 400);
        });
      });

      group('forwards what the package sends', () {
        test('places.suggest', () async {
          final r = await maps.places.suggest(
            query: 'Quicentro',
            biasPosition: carolina,
            additionalFeatures: const <PlaceFeature>[PlaceFeature.core],
          );
          expect(r.results, isNotEmpty);
        });

        test('places.reverseGeocode', () async {
          final places = await maps.places.reverseGeocode(
            carolina,
            radiusMeters: 200,
          );
          expect(places, isNotEmpty);
        });

        test('places.getPlace, with repeated query parameters', () async {
          final found = await maps.places.searchText(
            queryText: 'Quicentro',
            biasPosition: carolina,
          );
          final place = await maps.places.getPlace(
            found.places.first.placeId!,
            additionalFeatures: const <PlaceFeature>[
              PlaceFeature.contact,
              PlaceFeature.timeZone,
            ],
            useCache: false,
          );
          expect(place.title, isNotEmpty);
        });

        test('routes.calculateRoutes', () async {
          final r = await maps.routes.calculateRoutes(
            origin: carolina,
            destination: quicentro,
            useCache: false,
          );
          expect(r.best?.distanceMeters, greaterThan(0));
        });

        test('maps.staticMap returns the image bytes intact', () async {
          final image = await maps.maps.staticMap(
            center: carolina,
            zoom: 14,
            width: 200,
            height: 150,
          );
          // A PNG starts with these eight bytes; anything else means the
          // proxy mangled a binary body.
          expect(image.bytes.take(8), <int>[137, 80, 78, 71, 13, 10, 26, 10]);
        });

        test('an AWS error comes back as AWS sent it', () async {
          // `contact` isn't accepted by autocomplete: AWS answers 400, and the
          // package has to see that 400 and its message, not a proxy error.
          await expectLater(
            maps.places.autocomplete(
              query: 'Av. Amazonas',
              additionalFeatures: const <PlaceFeature>[PlaceFeature.contact],
              useCache: false,
            ),
            throwsA(
              isA<AlsApiException>()
                  .having((e) => e.statusCode, 'statusCode', 400)
                  .having((e) => e.message, 'message', isNotEmpty),
            ),
          );
        });
      });

      group('serves the map the way the renderer asks', () {
        late Map<String, dynamic> style;

        test('the style descriptor, with only the app token', () async {
          // What MapLibre does: GET the styleUrl with `customHeaders`, and no
          // X-Nativ headers at all.
          final r = await client.get(
            Uri.parse(maps.maps.styleDescriptorUrl(MapStyle.standard)!),
            headers: auth(),
          );
          expect(r.statusCode, 200, reason: r.body);
          style = jsonDecode(r.body) as Map<String, dynamic>;
        });

        List<String> urls() => <String>[
          style['glyphs'] as String,
          style['sprite'] as String,
          for (final source in (style['sources'] as Map).values)
            ...((source as Map)['tiles'] as List? ?? const <dynamic>[])
                .cast<String>(),
        ];

        test('points every tile, glyph and sprite URL at the proxy', () {
          for (final url in urls()) {
            expect(url, startsWith(base.toString()), reason: url);
          }
        });

        test('never hands the phone an API key', () {
          for (final url in urls()) {
            expect(url, isNot(contains('key=')), reason: url);
          }
        });

        test('a vector tile', () async {
          final tiles =
              ((style['sources'] as Map).values.first as Map)['tiles'] as List;
          final url = (tiles.first as String)
              .replaceAll('{z}', '14')
              .replaceAll('{x}', '4655')
              .replaceAll('{y}', '8199');
          final r = await client.get(Uri.parse(url), headers: auth());
          expect(r.statusCode, 200);
          expect(r.bodyBytes, isNotEmpty);
        });

        test('glyphs', () async {
          final url = (style['glyphs'] as String)
              .replaceAll('{fontstack}', 'Amazon Ember Regular')
              .replaceAll('{range}', '0-255');
          final r = await client.get(Uri.parse(url), headers: auth());
          expect(r.statusCode, 200);
        });

        test('the sprite sheet, JSON and image', () async {
          final sprite = style['sprite'] as String;
          final json = await client.get(
            Uri.parse('$sprite.json'),
            headers: auth(),
          );
          final png = await client.get(
            Uri.parse('$sprite.png'),
            headers: auth(),
          );
          expect(json.statusCode, 200);
          expect(png.statusCode, 200);
          expect(png.bodyBytes.take(4), <int>[137, 80, 78, 71]);
        });

        test('the map assets need the app token too', () async {
          final r = await client.get(
            Uri.parse(maps.maps.styleDescriptorUrl(MapStyle.standard)!),
          );
          expect(r.statusCode, 401);
        });
      });

      group('reaches the four hosts that all sign as geo', () {
        test('geofencing control plane: createCollection', () async {
          await maps.geofencing.createCollection(collectionName: collection);
          collectionAlive = true;
        });

        test('geofencing data plane: putGeofence and listGeofences', () async {
          await maps.geofencing.putGeofence(
            collectionName: collection,
            geofenceId: 'carolina',
            geometry: GeofenceGeometry.circle(
              center: carolina,
              radiusMeters: 400,
            ),
          );
          final page = await maps.geofencing.listGeofences(
            collectionName: collection,
          );
          expect(page.items.map((g) => g.geofenceId), contains('carolina'));
        });

        test('tracking control plane: createTracker', () async {
          await maps.tracking.createTracker(trackerName: tracker);
          trackerAlive = true;
        });

        test('tracking data plane: a position goes in and comes out', () async {
          final result = await maps.tracking.batchUpdateDevicePosition(
            trackerName: tracker,
            updates: <DevicePositionUpdate>[
              DevicePositionUpdate(
                deviceId: 'taxi-1',
                position: quicentro,
                sampleTime: DateTime.now().toUtc(),
              ),
            ],
          );
          expect(result.errors, isEmpty);
          DevicePosition? position;
          for (var i = 0; i < 10 && position == null; i++) {
            try {
              position = await maps.tracking.getDevicePosition(
                trackerName: tracker,
                deviceId: 'taxi-1',
              );
            } on AlsApiException catch (e) {
              if (e.statusCode != 404) rethrow;
              await Future<void>.delayed(const Duration(seconds: 2));
            }
          }
          expect(position?.position.latitude, closeTo(-0.1762, 1e-6));
        });

        test('cleanup goes through the proxy too', () async {
          await maps.tracking.deleteTracker(tracker);
          trackerAlive = false;
          await maps.geofencing.deleteCollection(collection);
          collectionAlive = false;
        });
      });
    },
  );
}
