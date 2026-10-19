// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:nativ_maps/nativ_maps.dart';
import 'package:nativ_maps_sigv4/src/signer.dart';

/// Where the AWS credentials come from.
///
/// It is queried before every request, so it can return different credentials
/// each time: that is what lets them be refreshed when they expire without
/// anything else noticing.
typedef AwsCredentialsProvider = Future<AwsCredentials> Function();

/// Authentication with **SigV4, signing on the device itself**.
///
/// It is path C of the design: no backend and no permanent key inside the
/// APK. In exchange you have to set up a Cognito identity pool and its IAM
/// policy.
///
/// ```dart
/// final maps = NativMaps(
///   region: 'us-east-1',
///   credentials: SigV4Credentials(
///     provider: () => myCognitoPool.fetchCredentials(),
///   ),
/// );
/// ```
///
/// ## Why this is better than an API key
///
/// Identity pool credentials **expire** —typically in an hour— and are issued
/// per device. One extracted from the binary stops working on its own; an API
/// key works until someone revokes it by hand, and by then it has already been
/// spent.
///
/// ## ⚠️ The mistake that costs an afternoon
///
/// **The three services sign with different names**: `geo-places`,
/// `geo-routes`, `geo-maps`. Signing with the wrong one gives a `403`
/// **identical** to that of an invalid key.
///
/// You can't get it wrong here: the name is set by [AlsService.signingName],
/// and the client itself passes the service when signing.
///
/// ## The map tiles too
///
/// This object signs the calls to Places, Routes and Maps. For **the tiles**
/// to be signed as well, you have to pass the widget the headers produced by
/// [mapHeaders]:
///
/// ```dart
/// NativMap(
///   styleUrl: url,
///   customHeaders: await credentials.mapHeaders(
///     styleUrl: url,
///     region: 'us-east-1',
///   ),
///   ...
/// )
/// ```
///
/// That is why this package chose `maplibre_gl` as its engine: it is the only
/// one that accepts custom HTTP headers, without which the tiles can only be
/// authenticated with the key in the URL.
class SigV4Credentials implements Credentials {
  /// Creates the credentials from a provider.
  SigV4Credentials({
    required AwsCredentialsProvider provider,
    Duration cacheFor = const Duration(minutes: 50),
    SigV4Signer signer = const SigV4Signer(),
  }) : _provider = provider,
       _cacheFor = cacheFor,
       _signer = signer;

  /// Creates the credentials from fixed ones, with no refreshing.
  ///
  /// For tests and for a Dart server with a role's credentials. **Not in a
  /// mobile app**: a permanent secret key inside the binary is worse than an
  /// API key, because it grants access to the whole account and not just to
  /// Location.
  factory SigV4Credentials.fixed(AwsCredentials credentials) =>
      SigV4Credentials(provider: () async => credentials);

  final AwsCredentialsProvider _provider;
  final Duration _cacheFor;
  final SigV4Signer _signer;

  AwsCredentials? _cached;
  DateTime? _cachedAt;
  Future<AwsCredentials>? _inFlight;

  @override
  bool get isConfigured => true;

  /// `null`: this path authenticates with headers, not with the key in the URL.
  @override
  String? get apiKeyForUrl => null;

  @override
  Uri baseUri(AlsService service, String region) =>
      Uri.https(service.hostFor(region));

  @override
  Future<http.BaseRequest> sign(
    http.BaseRequest request,
    AlsService service,
    String region,
  ) async {
    final credentials = await _credentials();
    final body = request is http.Request ? request.bodyBytes : null;

    final headers = _signer.sign(
      method: request.method,
      uri: request.url,
      // This is the piece that prevents the impossible-to-diagnose 403.
      service: service.signingName,
      region: region,
      credentials: credentials,
      body: body,
    );
    request.headers.addAll(headers);
    return request;
  }

  /// The signed headers so that **MapLibre** can request the style and tiles.
  ///
  /// They are passed to the widget in `customHeaders`.
  ///
  /// ## ⚠️ These headers expire
  ///
  /// A SigV4 signature is valid for a few minutes, and temporary credentials
  /// for an hour. A map left open for hours will stop loading new tiles.
  ///
  /// The right fix is to call this again periodically and then
  /// `controller.setCustomHeaders(...)` with the result. That is why this
  /// method returns the headers and doesn't install them: whoever installs
  /// them has to know it must be repeated.
  ///
  /// The alternative —a signing proxy— doesn't have this problem, and it is the
  /// reason it is still the recommended path for production.
  Future<Map<String, String>> mapHeaders({
    required String styleUrl,
    required String region,
  }) async {
    final credentials = await _credentials();
    return _signer.sign(
      method: 'GET',
      uri: Uri.parse(styleUrl),
      service: AlsService.maps.signingName,
      region: region,
      credentials: credentials,
    );
  }

  /// The current credentials, refreshing them if needed.
  ///
  /// Two simultaneous calls share a single refresh: without that, opening a
  /// screen that fires five requests at once would ask the pool for
  /// credentials five times.
  Future<AwsCredentials> _credentials() {
    final cached = _cached;
    final cachedAt = _cachedAt;
    final isFresh =
        cached != null &&
        cachedAt != null &&
        !cached.isExpired() &&
        DateTime.now().difference(cachedAt) < _cacheFor;
    if (isFresh) return Future<AwsCredentials>.value(cached);

    return _inFlight ??= _provider()
        .then((credentials) {
          _cached = credentials;
          _cachedAt = DateTime.now();
          _inFlight = null;
          return credentials;
        })
        .catchError((Object error) {
          _inFlight = null;
          throw error;
        });
  }

  /// Forgets the stored credentials and forces them to be requested again.
  ///
  /// Call it on sign-out: the previous user's credentials remain valid until
  /// they expire.
  void invalidate() {
    _cached = null;
    _cachedAt = null;
  }

  @override
  void close() => invalidate();

  @override
  String toString() => 'SigV4Credentials(${_cached ?? 'sin cargar'})';
}
