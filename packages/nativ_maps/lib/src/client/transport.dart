// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:nativ_maps/src/auth/credentials.dart';
import 'package:nativ_maps/src/client/budget.dart';
import 'package:nativ_maps/src/core/enums.dart';
import 'package:nativ_maps/src/core/exceptions.dart';

/// Ajustes de red compartidos por los tres clientes.
@immutable
class TransportOptions {
  /// Crea los ajustes. Los valores por defecto son los que se comportan bien
  /// en un móvil con cobertura irregular.
  const TransportOptions({
    this.timeout = const Duration(seconds: 8),
    this.maxRetries = 2,
    this.maxRetryDelay = const Duration(seconds: 30),
    this.userAgent = 'nativ-maps-dart/0.4.0',
  });

  /// Tiempo máximo de **cada intento**, no del conjunto.
  final Duration timeout;

  /// Reintentos tras el primer envío. `2` significa hasta tres envíos.
  final int maxRetries;

  /// Cuánto se espera como mucho entre intentos, incluso si el servidor pide
  /// más con `Retry-After`.
  ///
  /// Obedecer a ciegas un `Retry-After` de diez minutos deja la interfaz
  /// colgada sin explicación, y el usuario no distingue eso de una app rota.
  final Duration maxRetryDelay;

  /// El `User-Agent` que se envía.
  ///
  /// Identificar el cliente ayuda a AWS a diagnosticar, y a ti a reconocer tu
  /// propio tráfico en CloudWatch cuando la factura no cuadra.
  final String userAgent;
}

/// Ejecuta las peticiones: autentica, reintenta, mapea errores y cobra al
/// presupuesto.
///
/// Es interno: ninguna de las diecisiete operaciones lo expone. Existe para
/// que el reintento, el tope de gasto y la traducción de errores estén
/// escritos **una vez** y no diecisiete, que es donde aparecen las
/// discrepancias.
@internal
class AlsTransport {
  /// Crea el transporte.
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

  /// Región de AWS, p. ej. `us-east-1`.
  final String region;

  /// Cómo se autentica cada petición.
  final Credentials credentials;

  /// El tope de gasto. Se cobra antes de enviar.
  final Budget budget;

  /// Ajustes de red.
  final TransportOptions options;

  final http.Client _http;
  final bool _ownsClient;
  final math.Random _random;
  bool _closed = false;

  static const Map<String, String> _jsonHeaders = <String, String>{
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  /// Envía un `POST` con cuerpo JSON y devuelve el objeto de la respuesta.
  ///
  /// [billingUnits] es lo que esta llamada cuesta de verdad: 1 casi siempre,
  /// el número de umbrales en una isócrona, el número de pares en una matriz.
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
    // Los nulos se quitan aquí y no en cada operación: Amazon Location trata
    // un campo presente con valor nulo como un campo enviado, y varios de
    // ellos provocan un 400 en vez de tomar el valor por defecto.
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

  /// Envía una petición con cuerpo JSON por el método que se indique.
  ///
  /// Existe porque Geofencing y Tracking usan `PUT`, `DELETE` y `PATCH`
  /// además de `POST` — la generación v2 solo usa `POST` y `GET`, así que
  /// hasta que llegaron esas dos familias no hacía falta.
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

    // Varias operaciones de plano de control responden 200 con cuerpo vacío.
    // Devolver un mapa vacío en lugar de fallar es lo correcto: la operación
    // salió bien y no hay nada que leer.
    if (response.statusCode == 200 && response.body.trim().isEmpty) {
      return const <String, dynamic>{};
    }
    return _decode(operation, service, response);
  }

  /// Envía un `GET` y devuelve el objeto de la respuesta.
  Future<Map<String, dynamic>> getJson({
    required String operation,
    required AlsService service,
    required String path,
    Map<String, String> queryParameters = const <String, String>{},
    int billingUnits = BillingUnits.single,
  }) async {
    _ensureConfigured(operation);
    budget.charge(operation, billingUnits);

    final uri = _buildUri(service, path, queryParameters);
    final response = await _send(
      operation: operation,
      service: service,
      buildRequest: () => http.Request('GET', uri)
        ..headers['Accept'] = 'application/json'
        ..headers['User-Agent'] = options.userAgent,
    );
    return _decode(operation, service, response);
  }

  /// Envía un `GET` y devuelve los bytes crudos.
  ///
  /// Lo usa `GetStaticMap`, que responde con una imagen y no con JSON.
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

  /// Construye la URI final, ya con el destino que decida la credencial.
  ///
  /// [repeatedParameters] existe para los parámetros que pueden aparecer
  /// varias veces en la misma URL —`poi-categories` admite hasta nueve—, cosa
  /// que un `Map<String, String>` no puede representar.
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

  /// Comprueba que el camino de autenticación sirve para este servicio.
  ///
  /// **Las claves de API de Amazon Location solo cubren Places, Routes y
  /// Maps.** Geofencing y Tracking exigen SigV4, con un proxy o con
  /// `nativ_maps_sigv4`. Intentarlo con clave da un `403` que se parece a
  /// todos los demás `403`, así que se corta aquí con un mensaje que dice qué
  /// hacer.
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

  /// Envía con reintentos y retroceso exponencial con fluctuación.
  ///
  /// Solo reintenta lo que puede mejorar solo: `429`, `5xx` y los fallos de
  /// red. Un `400` o un `403` se devuelven al primer intento, porque
  /// reintentar un parámetro mal escrito es gastar cuota para obtener tres
  /// veces el mismo error.
  ///
  /// La petición se **reconstruye** en cada intento: `http.Request` consume su
  /// cuerpo al enviarse, así que reutilizar el objeto envía el segundo intento
  /// vacío — un fallo que solo aparece cuando la red va mal, que es justo
  /// cuando menos se puede depurar.
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
        // Cualquier fallo de socket, DNS o TLS. Se capturan por `Exception` y
        // no por los tipos de `dart:io` a propósito: este paquete es Dart
        // puro y tiene que compilar también donde `dart:io` no existe.
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

  /// Cuánto esperar antes del intento [attempt].
  ///
  /// Si el servidor mandó `Retry-After`, se respeta hasta
  /// [TransportOptions.maxRetryDelay]: es el servidor diciendo cuánto esperar,
  /// y adivinarlo peor solo empeora la congestión.
  ///
  /// Si no, retroceso exponencial con fluctuación de ±30 %. La fluctuación no
  /// es un adorno: sin ella, veinte móviles que fallan a la vez reintentan a
  /// la vez y reconstruyen exactamente el pico que causó el `429`.
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

  /// Traduce una respuesta de error al tipo del paquete.
  ///
  /// El cuerpo se recorta y **la URL no se incluye nunca**: en el camino de
  /// clave de API la clave viaja en la cadena de consulta, y un mensaje de
  /// error acaba en un informe de fallos, en un log o en una captura pegada en
  /// un chat.
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
      // Un cuerpo que no es JSON (una página de la puerta de enlace, por
      // ejemplo) se deja tal cual recortado.
    }

    return AlsApiException(
      operation: operation,
      service: service,
      statusCode: response.statusCode,
      message: message,
      // El nombre completo llega como `com.amazon...#ValidationException`.
      awsErrorCode: awsCode?.split('#').last,
      requestId:
          response.headers['x-amzn-requestid'] ??
          response.headers['x-amz-request-id'],
    );
  }

  static String _truncate(String body, [int max = 500]) =>
      body.length > max ? '${body.substring(0, max)}…' : body;

  /// Quita los nulos, recursivamente, de mapas y listas.
  static Object? _stripNulls(Object? value) => switch (value) {
    final Map<String, dynamic> map => <String, dynamic>{
      for (final e in map.entries)
        if (e.value != null) e.key: _stripNulls(e.value),
    },
    final List<dynamic> list =>
      list.where((dynamic e) => e != null).map<Object?>(_stripNulls).toList(),
    _ => value,
  };

  /// Cierra el cliente HTTP y las credenciales. Idempotente.
  void close() {
    if (_closed) return;
    _closed = true;
    credentials.close();
    if (_ownsClient) _http.close();
  }
}

/// Bytes con su tipo de contenido, lo que devuelve `GetStaticMap`.
@immutable
class AlsBytes {
  /// Crea el resultado.
  const AlsBytes({required this.bytes, required this.contentType});

  /// Los bytes de la imagen.
  final List<int> bytes;

  /// El `Content-Type` que declaró el servicio, p. ej. `image/png`.
  final String contentType;

  /// Cuántos bytes ocupa.
  int get length => bytes.length;

  @override
  String toString() => 'AlsBytes($length bytes, $contentType)';
}
