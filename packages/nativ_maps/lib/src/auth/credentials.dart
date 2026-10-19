// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/enums.dart';

/// How a request to Amazon Location is authenticated.
///
/// The three real-world paths fit behind this interface, and the app that
/// uses them does not need to know which one is in place:
///
/// | Path | Implementation | Cost |
/// |---|---|---|
/// | API key | `ApiKeyCredentials` | can be extracted from an APK |
/// | Signing proxy | `ProxyCredentials` | a new endpoint |
/// | SigV4 on the phone | `nativ_maps_sigv4` | setting up Cognito |
///
/// Switching paths means switching the object passed when building the
/// client. Nothing further up notices.
///
/// ## Why [sign] receives the service
///
/// Because **the three services sign with different names**: `geo-places`,
/// `geo-routes` and `geo-maps`. Signing with the wrong one gives a `403`
/// identical to that of a bad key. Passing [AlsService] instead of a string
/// makes that mistake impossible.
abstract interface class Credentials {
  /// Returns the request ready to send: signed, with the key attached or
  /// redirected to the proxy, depending on the path.
  ///
  /// It may return a different request from the one it received. It must not
  /// modify [request] if it returns another one.
  Future<http.BaseRequest> sign(
    http.BaseRequest request,
    AlsService service,
    String region,
  );

  /// The base that requests for [service] in [region] are sent to.
  ///
  /// The direct path returns the AWS host; the proxy path, the backend's.
  /// Letting the credentials decide, rather than the client, is what allows
  /// switching paths without touching any of the 44 operations.
  Uri baseUri(AlsService service, String region);

  /// Is there enough configuration to call the service?
  ///
  /// It is checked before sending, so that an empty key gives a clear error
  /// instead of a `403` from the server five layers further down.
  bool get isConfigured;

  /// The key to put in the query string of a URL handed to MapLibre, or
  /// `null` if this path does not use a key.
  ///
  /// It exists because there is a boundary [sign] cannot cover: the style
  /// descriptor and the tiles **are not requested by this package**, MapLibre
  /// requests them from a URL we give it. There is no `http.BaseRequest` to
  /// sign there.
  ///
  /// The proxy path and the SigV4 path return `null` on purpose: both
  /// authenticate with headers, and the map widget installs them with
  /// `setCustomHeaders`. Only the API key path needs to put it in the URL,
  /// and that is why it is the only path where the key appears in plain text.
  String? get apiKeyForUrl;

  /// Releases whatever needs releasing (internal HTTP clients, renewal timers
  /// for temporary credentials). It is idempotent.
  void close();
}

/// Convenient base for writing your own [Credentials].
///
/// It assumes the direct path to AWS —the host from [AlsService.hostFor]—
/// and leaves only [sign] to implement. If you need another destination,
/// implement the full [Credentials].
@immutable
abstract base class DirectCredentials implements Credentials {
  /// Const constructor for subclasses.
  const DirectCredentials();

  @override
  Uri baseUri(AlsService service, String region) =>
      Uri.https(service.hostFor(region));

  @override
  bool get isConfigured => true;

  @override
  String? get apiKeyForUrl => null;

  @override
  void close() {}
}
