// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:nativ_maps/src/auth/credentials.dart';
import 'package:nativ_maps/src/core/enums.dart';

/// Authentication with an Amazon Location API key.
///
/// It is the zero-infrastructure path: the key travels as `?key=` in the
/// query string and you need neither a backend nor an identity pool.
///
/// ## ⚠️ What you need to know before using it in production
///
/// **A key compiled into the APK gets extracted in two minutes.** It is not a
/// hypothesis or a matter of obfuscation: the binary contains the string, and
/// there are one-line tools to pull it out. Whoever pulls it out can spend
/// against your account until you revoke it.
///
/// What makes it acceptable, when it is:
///
/// - **Restricting the key in the AWS console.** You can set the allowed
///   operations, the list of referrers and an expiry date. A key that only
///   works for `GetStyleDescriptor` and expires in 90 days is a very
///   different risk from one with no restrictions.
/// - **Giving it a real spending cap**, in AWS Budgets. This package's
///   `Budget` protects you from your own loops, not from a third party with
///   your key.
///
/// For everything else there is [ProxyCredentials] or the
/// `nativ_maps_sigv4` package.
@immutable
final class ApiKeyCredentials extends DirectCredentials {
  /// Creates the credentials from the key.
  const ApiKeyCredentials(this.apiKey);

  /// The Amazon Location API key.
  final String apiKey;

  @override
  bool get isConfigured => apiKey.isNotEmpty;

  @override
  String? get apiKeyForUrl => apiKey.isEmpty ? null : apiKey;

  @override
  Future<http.BaseRequest> sign(
    http.BaseRequest request,
    AlsService service,
    String region,
  ) async {
    // The key is added to the query, keeping whatever was already there:
    // several Maps operations carry their own parameters there, and replacing
    // the whole map would wipe them out.
    final uri = request.url.replace(
      queryParameters: <String, dynamic>{
        ...request.url.queryParametersAll,
        'key': apiKey,
      },
    );
    return _copyWithUrl(request, uri);
  }

  @override
  String toString() =>
      'ApiKeyCredentials(clave de ${apiKey.length} caracteres)';
}

/// Authentication delegated to your own backend, which signs with SigV4.
///
/// The phone calls your server, your server signs and forwards to AWS. **The
/// key never leaves the server**, which is the only way to make sure it cannot
/// be extracted from the APK.
///
/// The backend has to reproduce the path as is: if the app requests
/// `POST /v2/search-text`, the proxy must sign and forward exactly that to the
/// host `places.geo.{region}.amazonaws.com`. This package imposes no format
/// of its own precisely so that the proxy can be a transparent twenty-line
/// forwarder.
///
/// [headers] lets you add **your** backend's authentication —usually the
/// user's session token—, which is a different thing from AWS's.
@immutable
final class ProxyCredentials implements Credentials {
  /// Creates the credentials pointing at the backend.
  const ProxyCredentials({required this.baseUrl, this.headers = const {}});

  /// The proxy base, e.g. `https://api.mycompany.com/geo`.
  ///
  /// The operation path is appended after it, so a base with a path (`/geo`)
  /// produces `/geo/v2/search-text`.
  final Uri baseUrl;

  /// Headers added to every request: usually your own backend's
  /// `Authorization`.
  final Map<String, String> headers;

  @override
  bool get isConfigured => baseUrl.host.isNotEmpty;

  /// `null`: the proxy authenticates with headers, not with the key in the
  /// URL.
  @override
  String? get apiKeyForUrl => null;

  /// The proxy is a single destination for the three services. It is told
  /// which one it was with the `X-Nativ-Service` header, so it can sign with
  /// the right name without having to infer it from the path.
  @override
  Uri baseUri(AlsService service, String region) => baseUrl;

  @override
  Future<http.BaseRequest> sign(
    http.BaseRequest request,
    AlsService service,
    String region,
  ) async {
    request.headers.addAll(headers);
    request.headers['X-Nativ-Service'] = service.signingName;
    request.headers['X-Nativ-Region'] = region;
    return request;
  }

  @override
  void close() {}

  @override
  String toString() => 'ProxyCredentials($baseUrl)';
}

/// Authentication with headers produced by a function of yours.
///
/// It is the escape hatch for whatever does not fit the other three: a token
/// that renews itself, a signature computed in native code, a header that a
/// corporate gateway demands. The function is called **on every request**, so
/// it can return a different value each time; if it is expensive, cache
/// inside it.
final class HeaderCredentials implements Credentials {
  /// Creates the credentials from the function that produces the headers.
  const HeaderCredentials(this._headerBuilder, {Uri? baseUrl})
    : _baseUrl = baseUrl;

  final Future<Map<String, String>> Function(AlsService service, String region)
  _headerBuilder;
  final Uri? _baseUrl;

  @override
  bool get isConfigured => true;

  /// `null`: this path authenticates with headers.
  @override
  String? get apiKeyForUrl => null;

  @override
  Uri baseUri(AlsService service, String region) =>
      _baseUrl ?? Uri.https(service.hostFor(region));

  @override
  Future<http.BaseRequest> sign(
    http.BaseRequest request,
    AlsService service,
    String region,
  ) async {
    request.headers.addAll(await _headerBuilder(service, region));
    return request;
  }

  @override
  void close() {}
}

/// Copies a request, changing its URL.
///
/// [http.BaseRequest.url] is read-only, so there is no way to redirect a
/// request without rebuilding it. The body, the headers and the settings are
/// kept; only the two types this package produces are handled.
http.BaseRequest _copyWithUrl(http.BaseRequest original, Uri url) {
  final copy = switch (original) {
    final http.Request r =>
      http.Request(r.method, url)
        ..bodyBytes = r.bodyBytes
        ..encoding = r.encoding
        ..followRedirects = r.followRedirects
        ..maxRedirects = r.maxRedirects
        ..persistentConnection = r.persistentConnection,
    _ =>
      http.Request(original.method, url)
        ..followRedirects = original.followRedirects
        ..maxRedirects = original.maxRedirects
        ..persistentConnection = original.persistentConnection,
  };
  copy.headers.addAll(original.headers);
  return copy;
}
