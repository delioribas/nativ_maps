// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

/// Every value of every enum that travels in a request, against Amazon
/// Location for real.
///
/// An enum value is a promise that the service accepts it. This found
/// `RouteFeature.tollSystems`, which AWS never accepted, and that each Places
/// operation takes a different subset of `PlaceFeature`. It's here so that a
/// change on AWS's side shows up as a failing test, not as a 400 in someone's
/// app.
///
/// Skipped by `dart test`. Run on purpose, from `packages/nativ_maps`:
///
/// ```sh
/// set -a; source ../../.env; set +a
/// dart test -P live test/live/enums_live_test.dart
/// ```
///
/// About 110 requests, a few cents.
@Tags(<String>['live'])
library;

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:nativ_maps/nativ_maps.dart';
import 'package:test/test.dart';

void main() {
  final apiKey = Platform.environment['ALS_API_KEY'];
  final region = Platform.environment['ALS_REGION'] ?? 'us-east-1';
  final carolina = LatLng(-0.1825, -78.4840);
  final quicentro = LatLng(-0.1762, -78.4797);

  late NativMaps maps;
  final client = http.Client();

  group(
    'enums against AWS',
    skip: apiKey == null
        ? 'Missing ALS_API_KEY. Load the .env: set -a; source ../../.env'
        : false,
    () {
      setUpAll(() {
        maps = NativMaps(
          region: region,
          credentials: ApiKeyCredentials(apiKey!),
          language: 'es',
          budget: Budget(maxUnits: 300, window: const Duration(hours: 1)),
        );
      });

      tearDownAll(() {
        maps.close();
        client.close();
      });

      Future<void> expectStyle(String? url) async {
        final response = await client.get(Uri.parse(url!));
        expect(response.statusCode, 200, reason: response.body);
      }

      group('style descriptor', () {
        for (final style in MapStyle.values) {
          for (final scheme in MapColorScheme.values) {
            test('${style.wireName} · ${scheme.wireName}', () async {
              await expectStyle(
                maps.maps.styleDescriptorUrl(style, colorScheme: scheme),
              );
            });
          }
        }
        for (final v in MapTraffic.values) {
          test('traffic ${v.wireName}', () async {
            await expectStyle(
              maps.maps.styleDescriptorUrl(MapStyle.standard, traffic: v),
            );
          });
        }
        for (final v in MapTerrain.values) {
          test('terrain ${v.wireName}', () async {
            await expectStyle(
              maps.maps.styleDescriptorUrl(MapStyle.standard, terrain: v),
            );
          });
        }
        for (final v in MapBuildings.values) {
          test('buildings ${v.wireName}', () async {
            await expectStyle(
              maps.maps.styleDescriptorUrl(MapStyle.standard, buildings: v),
            );
          });
        }
        for (final v in MapContourDensity.values) {
          test('contour density ${v.wireName}', () async {
            await expectStyle(
              maps.maps.styleDescriptorUrl(
                MapStyle.standard,
                terrain: MapTerrain.hillshade,
                contourDensity: v,
              ),
            );
          });
        }
        for (final v in MapPoiDensity.values) {
          test('POI density ${v.wireName}', () async {
            await expectStyle(
              maps.maps.styleDescriptorUrl(MapStyle.standard, poiDensity: v),
            );
          });
        }
        for (final v in MapPoiCategory.values) {
          test('POI category ${v.wireName}', () async {
            await expectStyle(
              maps.maps.styleDescriptorUrl(
                MapStyle.standard,
                poiCategories: <MapPoiCategory>[v],
              ),
            );
          });
        }
        for (final v in MapTravelMode.values) {
          test('travel mode ${v.wireName}', () async {
            await expectStyle(
              maps.maps.styleDescriptorUrl(
                MapStyle.standard,
                travelModes: <MapTravelMode>[v],
              ),
            );
          });
        }
      });

      group('static map', () {
        for (final unit in ScaleBarUnit.values) {
          test('scale bar ${unit.wireName}', () async {
            final image = await maps.maps.staticMap(
              center: carolina,
              zoom: 14,
              width: 200,
              height: 150,
              scaleBarUnit: unit,
            );
            expect(image.length, greaterThan(1000));
          });
        }
      });

      group('routes', () {
        for (final mode in TravelMode.values) {
          test('travel mode ${mode.wireName}', () async {
            final r = await maps.routes.calculateRoutes(
              origin: carolina,
              destination: quicentro,
              travelMode: mode,
              useCache: false,
            );
            expect(r.routes, isNotEmpty);
          });
        }
        for (final feature in RouteFeature.values) {
          test('leg feature ${feature.wireName}', () async {
            final r = await maps.routes.calculateRoutes(
              origin: carolina,
              destination: quicentro,
              legAdditionalFeatures: <RouteFeature>[feature],
              // Written instructions only exist with the default steps.
              travelStepType: feature == RouteFeature.travelStepInstructions
                  ? TravelStepType.standard
                  : TravelStepType.turnByTurn,
              useCache: false,
            );
            expect(r.routes, isNotEmpty);
          });
        }
        for (final v in RouteOptimization.values) {
          test('optimize for ${v.wireName}', () async {
            await maps.routes.calculateRoutes(
              origin: carolina,
              destination: quicentro,
              optimizeFor: v,
              useCache: false,
            );
          });
        }
        for (final v in TrafficUsage.values) {
          test('traffic ${v.wireName}', () async {
            await maps.routes.calculateRoutes(
              origin: carolina,
              destination: quicentro,
              traffic: v,
              useCache: false,
            );
          });
        }
        for (final v in TravelStepType.values) {
          test('step type ${v.wireName}', () async {
            await maps.routes.calculateRoutes(
              origin: carolina,
              destination: quicentro,
              travelStepType: v,
              useCache: false,
            );
          });
        }
        for (final v in WaypointOptimization.values) {
          test('waypoint optimization ${v.wireName}', () async {
            final r = await maps.routes.optimizeWaypoints(
              origin: carolina,
              waypoints: <OptimizationWaypoint>[
                OptimizationWaypoint(id: 'a', position: quicentro),
                OptimizationWaypoint(
                  id: 'b',
                  position: LatLng(-0.2201, -78.5123),
                ),
              ],
              optimizeFor: v,
            );
            expect(r.orderedIds, hasLength(2));
          });
        }
      });

      group('places', () {
        for (final mode in PostalCodeMode.values) {
          test('postal code mode ${mode.wireName}', () async {
            await maps.places.autocomplete(
              query: '170135',
              postalCodeMode: mode,
              useCache: false,
            );
          });
        }
        for (final use in IntendedUse.values) {
          test('intended use ${use.wireName}', () async {
            await maps.places.searchText(
              queryText: 'Quicentro',
              biasPosition: carolina,
              intendedUse: use,
              useCache: false,
            );
          });
        }

        // The table in the PlaceFeature docs, cell by cell: what's accepted
        // has to work, and what isn't has to still be a 400 — if AWS starts
        // accepting it, the docs need updating.
        const accepted = <String, Set<PlaceFeature>>{
          'autocomplete': <PlaceFeature>{PlaceFeature.core},
          'suggest': <PlaceFeature>{
            PlaceFeature.core,
            PlaceFeature.timeZone,
            PlaceFeature.access,
            PlaceFeature.phonemes,
          },
          'searchText': <PlaceFeature>{
            PlaceFeature.contact,
            PlaceFeature.timeZone,
            PlaceFeature.access,
            PlaceFeature.phonemes,
          },
          'searchNearby': <PlaceFeature>{
            PlaceFeature.contact,
            PlaceFeature.timeZone,
            PlaceFeature.access,
            PlaceFeature.phonemes,
          },
          'getPlace': <PlaceFeature>{
            PlaceFeature.contact,
            PlaceFeature.timeZone,
            PlaceFeature.access,
            PlaceFeature.phonemes,
            PlaceFeature.secondaryAddresses,
          },
          'geocode': <PlaceFeature>{
            PlaceFeature.timeZone,
            PlaceFeature.access,
            PlaceFeature.secondaryAddresses,
            PlaceFeature.intersections,
          },
          'reverseGeocode': <PlaceFeature>{
            PlaceFeature.timeZone,
            PlaceFeature.access,
            PlaceFeature.intersections,
          },
        };

        String? placeId;
        Future<void> call(String op, PlaceFeature f) async {
          final features = <PlaceFeature>[f];
          switch (op) {
            case 'autocomplete':
              await maps.places.autocomplete(
                query: 'Av. Amazonas',
                biasPosition: carolina,
                additionalFeatures: features,
                useCache: false,
              );
            case 'suggest':
              await maps.places.suggest(
                query: 'Quicentro',
                biasPosition: carolina,
                additionalFeatures: features,
              );
            case 'searchText':
              await maps.places.searchText(
                queryText: 'Quicentro',
                biasPosition: carolina,
                additionalFeatures: features,
                useCache: false,
              );
            case 'searchNearby':
              await maps.places.searchNearby(
                position: carolina,
                radiusMeters: 500,
                additionalFeatures: features,
              );
            case 'getPlace':
              placeId ??= (await maps.places.searchText(
                queryText: 'Quicentro',
                biasPosition: carolina,
              )).places.first.placeId;
              await maps.places.getPlace(
                placeId!,
                additionalFeatures: features,
                useCache: false,
              );
            case 'geocode':
              await maps.places.geocode(
                queryText: 'Av. Amazonas N24, Quito',
                additionalFeatures: features,
              );
            case 'reverseGeocode':
              await maps.places.reverseGeocode(
                carolina,
                radiusMeters: 200,
                additionalFeatures: features,
              );
          }
        }

        for (final MapEntry(key: op, value: ok) in accepted.entries) {
          for (final feature in PlaceFeature.values) {
            final shouldWork = ok.contains(feature);
            test('$op · ${feature.wireName} → '
                '${shouldWork ? 'accepted' : '400'}', () async {
              if (shouldWork) {
                await call(op, feature);
              } else {
                // Either AWS answers 400, or the package stops it before
                // sending —it already does for `getPlace`—, which is better.
                await expectLater(
                  call(op, feature),
                  throwsA(
                    anyOf(
                      isA<ArgumentError>(),
                      isA<AlsApiException>().having(
                        (e) => e.statusCode,
                        'statusCode',
                        400,
                      ),
                    ),
                  ),
                );
              }
            });
          }
        }
      });
    },
  );
}
