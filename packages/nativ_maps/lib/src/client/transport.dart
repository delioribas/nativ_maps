// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:nativ_maps/src/auth/credentials.dart';
import 'package:nativ_maps/src/client/budget.dart';
import 'package:nativ_maps/src/core/enums.dart';
import 'package:nativ_maps/src/core/exceptions.dart';

/// Network settings shared by the three clients.
@immutable
class TransportOptions {
  /// Creates the settings. The defaults are the ones that behave well on a
  /// phone with patchy coverage.
  const TransportOptions({
    this.timeout = const Duration(seconds: 8),
    this.maxRetries = 2,
    this.maxRetryDelay = const Duration(seconds: 30),
    this.userAgent = 'nativ-maps-dart/0.9.2',
  });

  /// Maximum time for **each attempt**, not for the whole thing.
  final Duration timeout;

  /// Retries after the first send. `2` means up to three sends.
  final int maxRetries;

  /// The longest wait between attempts, even if the server asks for more with
  /// `Retry-After`.
  ///
  /// Blindly obeying a ten-minute `Retry-After` leaves the UI hanging with no
  /// explanation, and the user cannot tell that apart from a broken app.
  final Duration maxRetryDelay;

  /// The `User-Agent` that is sent.
  ///
  /// Identifying the client helps AWS diagnose, and helps you recognize your
  /// own traffic in CloudWatch when the bill does not add up.
  final String userAgent;
}

/// Runs the requests: authenticates, retries, maps errors and charges the
/// budget.
///
/// It is internal: none of the 44 operations exposes it. It exists so
/// that retries, the spending cap and error translation are written **once**
/// and not 44 times, which is where discrepancies creep in.
@internal
class AlsTransport {
  /// Creates the transport.
  AlsTransport({
    required this.region,
    required this.credentials,
    required this.budget,
    this.options = const TransportOptions(),
    http.Client? httpClient,
    math.Random? random,
  }) : _http = httpClient ?? http.Client(),
       _ownsClient = httpClient == null,
       _random = random ?? math.Random();

  /// AWS region, e.g. `us-east-1`.
  final String region;

  /// How each request is authenticated.
  final Credentials credentials;

  /// The spending cap. It is charged before sending.
  final Budget budget;

  /// Network settings.
  final TransportOptions options;

  final http.Client _http;
  final bool _ownsClient;
  final math.Random _random;
  bool _closed = false;

  static const Map<String, String> _jsonHeaders = <String, String>{
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  /// Sends a `POST` with a JSON body and returns the response object.
  ///
  /// [billingUnits] is what this call really costs: 1 almost always, the
  /// number of thresholds for an isoline, the number of pairs for a matrix.
  Future<Map<String, dynamic>> postJson({
    required String operation,
    required AlsService service,
    required String path,
    required Map<String, dynamic> body,
    Map<String, String> queryParameters = const <String, String>{},
    int billingUnits = BillingUnits.single,
  }) async {
    _ensureConfigured(operation);
    _ensureAuthSupported(operation, service);
    budget.charge(operation, billingUnits);

    final uri = _buildUri(service, path, queryParameters);
    // Nulls are stripped here and not in each operation: Amazon Location
    // treats a field present with a null value as a field that was sent, and
    // several of them trigger a 400 instead of taking the default value.
    final payload = jsonEncode(_stripNulls(body));

    final response = await _send(
      operation: operation,
      service: service,
      buildRequest: () => http.Request('POST', uri)
        ..headers.addAll(_jsonHeaders)
        ..headers['User-Agent'] = options.userAgent
        ..body = payload,
    );
    return _decode(operation, service, response);
  }

  /// Sends a request with a JSON body using the given method.
  ///
  /// It exists because Geofencing and Tracking use `PUT`, `DELETE` and
  /// `PATCH` as well as `POST` — the v2 generation only uses `POST` and
  /// `GET`, so until those two families arrived it was not needed.
  Future<Map<String, dynamic>> sendJson({
    required String operation,
    required AlsService service,
    required String method,
    required String path,
    Map<String, dynamic>? body,
    Map<String, String> queryParameters = const <String, String>{},
    int billingUnits = BillingUnits.single,
  }) async {
    _ensureConfigured(operation);
    _ensureAuthSupported(operation, service);
    budget.charge(operation, billingUnits);

    final uri = _buildUri(service, path, queryParameters);
    final payload = body == null ? null : jsonEncode(_stripNulls(body));

    final response = await _send(
      operation: operation,
      service: service,
      buildRequest: () {
        final request = http.Request(method.toUpperCase(), uri)
          ..headers.addAll(_jsonHeaders)
          ..headers['User-Agent'] = options.userAgent;
        if (payload != null) request.body = payload;
        return request;
      },
    );

    // Several control plane operations respond 200 with an empty body.
    // Returning an empty map instead of failing is the right thing: the
    // operation succeeded and there is nothing to read.
    if (response.statusCode == 200 && response.body.trim().isEmpty) {
      return const <String, dynamic>{};
    }
    return _decode(operation, service, response);
  }

  /// Sends a `GET` and returns the response object.
  ///
  /// A list goes in [repeatedParameters], **one parameter per element**: the
  /// service reads `a=X,Y` as a single value `X,Y` and responds `400`.
  Future<Map<String, dynamic>> getJson({
    required String operation,
    required AlsService service,
    required String path,
    Map<String, String> queryParameters = const <String, String>{},
    List<MapEntry<String, String>> repeatedParameters =
        const <MapEntry<String, String>>[],
    int billingUnits = BillingUnits.single,
  }) async {
    _ensureConfigured(operation);
    budget.charge(operation, billingUnits);

    final uri = _buildUri(
      service,
      path,
      queryParameters,
      repeatedParameters: repeatedParameters,
    );
    final response = await _send(
      operation: operation,
      service: service,
      buildRequest: () => http.Request('GET', uri)
        ..headers['Accept'] = 'application/json'
        ..headers['User-Agent'] = options.userAgent,
    );
    return _decode(operation, service, response);
  }

  /// Sends a `GET` and returns the raw bytes.
  ///
  /// Used by `GetStaticMap`, which responds with an image and not with JSON.
  Future<AlsBytes> getBytes({
    required String operation,
    required AlsService service,
    required String path,
    Map<String, String> queryParameters = const <String, String>{},
    List<MapEntry<String, String>> repeatedParameters =
        const <MapEntry<String, String>>[],
    int billingUnits = BillingUnits.single,
  }) async {
    _ensureConfigured(operation);
    budget.charge(operation, billingUnits);

    final uri = _buildUri(
      service,
      path,
      queryParameters,
      repeatedParameters: repeatedParameters,
    );
    final response = await _send(
      operation: operation,
      service: service,
      buildRequest: () =>
          http.Request('GET', uri)..headers['User-Agent'] = options.userAgent,
    );
    if (response.statusCode != 200) {
      throw _apiException(operation, service, response);
    }
    return AlsBytes(
      bytes: response.bodyBytes,
      contentType:
          response.headers['content-type'] ?? 'application/octet-stream',
    );
  }

  /// Builds the final URI, already pointing at the destination the
  /// credentials decide.
  ///
  /// [repeatedParameters] exists for parameters that can appear several
  /// times in the same URL —`poi-categories` accepts up to nine—, something a
  /// `Map<String, String>` cannot represent.
  Uri _buildUri(
    AlsService service,
    String path,
    Map<String, String> queryParameters, {
    List<MapEntry<String, String>> repeatedParameters =
        const <MapEntry<String, String>>[],
  }) {
    final base = credentials.baseUri(service, region);
    final query = <String, List<String>>{};
    for (final entry in queryParameters.entries) {
      query.putIfAbsent(entry.key, () => <String>[]).add(entry.value);
    }
    for (final entry in repeatedParameters) {
      query.putIfAbsent(entry.key, () => <String>[]).add(entry.value);
    }
    return base.replace(
      path: '${_trimTrailingSlash(base.path)}$path',
      queryParameters: query.isEmpty ? null : query,
    );
  }

  static String _trimTrailingSlash(String path) =>
      path.endsWith('/') ? path.substring(0, path.length - 1) : path;

  /// Checks that the authentication path works for this service.
  ///
  /// **Amazon Location API keys only cover Places, Routes and Maps.**
  /// Geofencing and Tracking require SigV4, through a proxy or with
  /// `nativ_maps_sigv4`. Trying it with a key gives a `403` that looks like
  /// every other `403`, so it is cut off here with a message that says what
  /// to do.
  void _ensureAuthSupported(String operation, AlsService service) {
    if (service.supportsApiKey) return;
    if (credentials.apiKeyForUrl == null) return;
    throw NativMapsConfigurationException(
      '$operation pertenece a ${service.hostPrefix}, que NO admite clave de '
      'API: las claves de Amazon Location solo cubren Places, Routes y Maps. '
      'Hacen falta credenciales SigV4 — un proxy que firme '
      '(ProxyCredentials) o el paquete nativ_maps_sigv4.',
    );
  }

  void _ensureConfigured(String operation) {
    if (_closed) {
      throw StateError(
        'El cliente de Nativ Maps ya se cerró. Llamar a $operation después '
        'de close() es un error de ciclo de vida, no de red.',
      );
    }
    if (!credentials.isConfigured) {
      throw NativMapsConfigurationException(
        'Amazon Location sin configurar: $credentials no tiene con qué '
        'autenticar $operation. Con ApiKeyCredentials, la clave está vacía.',
      );
    }
  }

  /// Sends with retries and exponential backoff with jitter.
  ///
  /// It only retries what can get better on its own: `429`, `5xx` and network
  /// failures. A `400` or a `403` is returned on the first attempt, because
  /// retrying a misspelled parameter is spending quota to get the same error
  /// three times.
  ///
  /// The request is **rebuilt** on every attempt: `http.Request` consumes its
  /// body when sent, so reusing the object sends the second attempt empty — a
  /// bug that only shows up when the network is bad, which is exactly when it
  /// is hardest to debug.
  Future<http.Response> _send({
    required String operation,
    required AlsService service,
    required http.Request Function() buildRequest,
  }) async {
    Object? lastError;
    http.Response? lastResponse;

    for (var attempt = 0; attempt <= options.maxRetries; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(_retryDelay(attempt, lastResponse));
      }
      try {
        final signed = await credentials.sign(buildRequest(), service, region);
        final streamed = await _http.send(signed).timeout(options.timeout);
        final response = await http.Response.fromStream(
          streamed,
        ).timeout(options.timeout);

        if (response.statusCode != 429 && response.statusCode < 500) {
          return response;
        }
        lastResponse = response;
        lastError = null;
      } on TimeoutException catch (e) {
        lastError = e;
        lastResponse = null;
      } on http.ClientException catch (e) {
        lastError = e;
        lastResponse = null;
      } on Exception catch (e) {
        // Any socket, DNS or TLS failure. They are caught as `Exception` and
        // not by the `dart:io` types on purpose: this package is pure Dart
        // and has to compile where `dart:io` does not exist, too.
        lastError = e;
        lastResponse = null;
      }
    }

    if (lastResponse != null) return lastResponse;
    throw AlsTransportException(
      operation: operation,
      attempts: options.maxRetries + 1,
      message:
          'no se pudo contactar con ${service.hostFor(region)} tras '
          '${options.maxRetries + 1} intento(s). Como el servicio no llegó a '
          'responder, esta llamada no se ha facturado.',
      cause: lastError,
    );
  }

  /// How long to wait before attempt [attempt].
  ///
  /// If the server sent `Retry-After`, it is honored up to
  /// [TransportOptions.maxRetryDelay]: it is the server saying how long to
  /// wait, and guessing worse only makes the congestion worse.
  ///
  /// Otherwise, exponential backoff with ±30 % jitter. The jitter is not
  /// decoration: without it, twenty phones that fail at the same time retry
  /// at the same time and rebuild exactly the spike that caused the `429`.
  Duration _retryDelay(int attempt, http.Response? response) {
    final suggested = _retryAfter(response);
    if (suggested != null) return suggested;

    final baseMs = 200 * math.pow(2, attempt).toInt();
    final jitter = 1.0 + (_random.nextDouble() * 0.6 - 0.3);
    final ms = (baseMs * jitter).round();
    return Duration(
      milliseconds: math.min(ms, options.maxRetryDelay.inMilliseconds),
    );
  }

  Duration? _retryAfter(http.Response? response) {
    final raw = response?.headers['retry-after'];
    if (raw == null) return null;
    final seconds = int.tryParse(raw.trim());
    if (seconds == null || seconds < 0) return null;
    return Duration(
      seconds: math.min(seconds, options.maxRetryDelay.inSeconds),
    );
  }

  Map<String, dynamic> _decode(
    String operation,
    AlsService service,
    http.Response response,
  ) {
    if (response.statusCode != 200) {
      throw _apiException(operation, service, response);
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (e) {
      throw AlsParseException(
        operation: operation,
        message: 'la respuesta llegó con 200 pero no es JSON: ${e.message}',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw AlsParseException(
        operation: operation,
        message:
            'se esperaba un objeto JSON en la raíz y llegó '
            '${decoded.runtimeType}',
      );
    }
    return decoded;
  }

  /// Translates an error response into the package's type.
  ///
  /// The body is truncated and **the URL is never included**: on the API key
  /// path the key travels in the query string, and an error message ends up
  /// in a crash report, in a log or in a screenshot pasted into a chat.
  AlsApiException _apiException(
    String operation,
    AlsService service,
    http.Response response,
  ) {
    String? awsCode;
    var message = _truncate(response.body);

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        awsCode = decoded['__type'] as String? ?? decoded['code'] as String?;
        final detail =
            decoded['message'] as String? ??
            decoded['Message'] as String? ??
            decoded['errorMessage'] as String?;
        if (detail != null && detail.isNotEmpty) message = detail;
      }
    } on FormatException {
      // A body that is not JSON (a gateway page, for example) is left as is,
      // truncated.
    }

    return AlsApiException(
      operation: operation,
      service: service,
      statusCode: response.statusCode,
      message: message,
      // The full name arrives as `com.amazon...#ValidationException`.
      awsErrorCode: awsCode?.split('#').last,
      requestId:
          response.headers['x-amzn-requestid'] ??
          response.headers['x-amz-request-id'],
    );
  }

  static String _truncate(String body, [int max = 500]) =>
      body.length > max ? '${body.substring(0, max)}…' : body;

  /// Strips nulls, recursively, from maps and lists.
  static Object? _stripNulls(Object? value) => switch (value) {
    final Map<String, dynamic> map => <String, dynamic>{
      for (final e in map.entries)
        if (e.value != null) e.key: _stripNulls(e.value),
    },
    final List<dynamic> list =>
      list.where((dynamic e) => e != null).map<Object?>(_stripNulls).toList(),
    _ => value,
  };

  /// Closes the HTTP client and the credentials. Idempotent.
  void close() {
    if (_closed) return;
    _closed = true;
    credentials.close();
    if (_ownsClient) _http.close();
  }
}

/// Bytes with their content type, what `GetStaticMap` returns.
@immutable
class AlsBytes {
  /// Creates the result.
  const AlsBytes({required this.bytes, required this.contentType});

  /// The image bytes.
  final List<int> bytes;

  /// The `Content-Type` the service declared, e.g. `image/png`.
  final String contentType;

  /// How many bytes it takes up.
  int get length => bytes.length;

  @override
  String toString() => 'AlsBytes($length bytes, $contentType)';
}
