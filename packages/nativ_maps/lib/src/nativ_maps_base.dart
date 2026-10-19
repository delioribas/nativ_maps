// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'package:http/http.dart' as http;
import 'package:nativ_maps/src/auth/credentials.dart';
import 'package:nativ_maps/src/client/budget.dart';
import 'package:nativ_maps/src/client/transport.dart';
import 'package:nativ_maps/src/core/enums.dart';
import 'package:nativ_maps/src/geofencing/geofencing_client.dart';
import 'package:nativ_maps/src/maps/maps_client.dart';
import 'package:nativ_maps/src/places/places_client.dart';
import 'package:nativ_maps/src/routes/routes_client.dart';
import 'package:nativ_maps/src/tracking/tracking_client.dart';

/// The gateway to Amazon Location's **44 operations**.
///
/// ```dart
/// final maps = NativMaps(
///   region: 'us-east-1',
///   credentials: const ApiKeyCredentials('...'),
///   language: 'es',
///   budget: Budget(maxUnits: 500, window: const Duration(minutes: 1)),
/// );
///
/// final results = await maps.places.searchText(queryText: 'gasolinera');
/// final route = await maps.routes.calculateRoutes(
///   origin: here,
///   destination: results.places.first.position!,
/// );
/// final style = maps.maps.styleDescriptorUrl(MapStyle.standard);
///
/// maps.close(); // closes the HTTP client
/// ```
///
/// ## Why five clients and not 44 methods here
///
/// Because they are different services: **they sign with different names**
/// —`geo-places`, `geo-routes`, `geo-maps` in the v2 generation, and plain
/// `geo` for geofencing and tracking—, they have different hosts and they
/// are billed separately. Flattening them into a single class would hide
/// precisely the distinction you need to keep in mind when reading a bill or
/// debugging a `403`.
///
/// | Client | Operations | Generation |
/// |---|---|---|
/// | [places] | 7 | v2, resourceless |
/// | [routes] | 5 | v2, resourceless |
/// | [maps] | 5 | v2, resourceless |
/// | [geofencing] | 12 | previous, **requires SigV4** |
/// | [tracking] | 15 | previous, **requires SigV4** |
///
/// ## This does not depend on Flutter
///
/// On purpose. `nativ_maps` is tested without an emulator, runs in a
/// command-line tool and works on a Dart server. The map widget lives in
/// `nativ_maps_flutter`, which re-exports all of this: installing just that
/// package gets you all forty-four operations.
class NativMaps {
  /// Creates the client.
  ///
  /// [region] is the AWS region, e.g. `us-east-1`. **It has to be one where
  /// Amazon Location is available**; in one where it is not, DNS resolves
  /// anyway and the error arrives as a generic connection failure.
  ///
  /// [budget] is the spending cap. Its default —600 units per minute— does
  /// not claim to be right for any particular app: it aims to stop a runaway
  /// loop within the first minute rather than on the monthly bill. Tune it,
  /// or pass [Budget.unlimited] knowingly.
  ///
  /// [httpClient] lets you inject a `MockClient` in tests. If you pass one,
  /// [close] does **not** close it: whoever created it closes it.
  NativMaps({
    required this.region,
    required this.credentials,
    this.language,
    this.politicalView,
    this.intendedUse = IntendedUse.singleUse,
    Budget? budget,
    TransportOptions transportOptions = const TransportOptions(),
    http.Client? httpClient,
  }) : budget = budget ?? Budget(maxUnits: 600),
       _transport = AlsTransport(
         region: region,
         credentials: credentials,
         budget: budget ?? Budget(maxUnits: 600),
         options: transportOptions,
         httpClient: httpClient,
       ) {
    if (region.isEmpty) {
      throw ArgumentError.value(region, 'region', 'no puede estar vacía');
    }
    places = PlacesClient(
      transport: _transport,
      intendedUse: intendedUse,
      language: language,
      politicalView: politicalView,
    );
    routes = RoutesClient(transport: _transport, language: language);
    maps = MapsClient(
      transport: _transport,
      region: region,
      politicalView: politicalView,
    );
    geofencing = GeofencingClient(transport: _transport);
    tracking = TrackingClient(transport: _transport);
  }

  /// The AWS region.
  final String region;

  /// How each request is authenticated.
  final Credentials credentials;

  /// Language of the results, in BCP 47.
  final String? language;

  /// Political view for disputed borders, in ISO 3166.
  final String? politicalView;

  /// Whether the results are going to be stored. See [IntendedUse].
  final IntendedUse intendedUse;

  /// The spending cap, shared by the three clients.
  ///
  /// There is just one on purpose: the spending belongs to the AWS account,
  /// not to each service. Three separate budgets would let through three
  /// times as much.
  final Budget budget;

  final AlsTransport _transport;

  /// The seven Places operations.
  late final PlacesClient places;

  /// The five Routes operations.
  late final RoutesClient routes;

  /// The Maps operations.
  late final MapsClient maps;

  /// The twelve geofencing operations.
  ///
  /// ⚠️ They belong to the **previous generation**: you have to create a
  /// collection and they **do not accept an API key**. With
  /// `ApiKeyCredentials`, the first call throws
  /// `NativMapsConfigurationException` explaining that SigV4 credentials are
  /// needed.
  late final GeofencingClient geofencing;

  /// The fifteen device tracking operations.
  ///
  /// ⚠️ Same conditions as [geofencing]. And before using it, the question
  /// that saves money: **if you already store the history in your own
  /// database, this is duplicated infrastructure.** What does justify using
  /// it is in the `TrackingClient` documentation.
  late final TrackingClient tracking;

  /// Are there enough credentials to call the service?
  ///
  /// Worth checking at startup: without it, the first map screen fails with
  /// a network error that does not say the key is missing.
  bool get isConfigured => credentials.isConfigured;

  /// Empties all caches.
  ///
  /// Call it when the language or the session changes.
  void clearCaches() {
    places.clearCache();
    routes.clearCache();
  }

  /// Closes the HTTP client and the credentials.
  ///
  /// After this, any operation throws [StateError]. It is idempotent.
  void close() => _transport.close();
}
