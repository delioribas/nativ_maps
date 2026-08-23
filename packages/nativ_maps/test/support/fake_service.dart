// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nativ_maps/nativ_maps.dart';

/// Un servicio de Amazon Location falso, que registra lo que se le envía.
///
/// La pieza que hace posible probar las diecisiete operaciones sin gastar una
/// sola unidad ni tener una clave: verifica **la petición** —ruta, cuerpo,
/// parámetros— y devuelve la respuesta que se le indique.
///
/// Comprobar la petición y no solo la respuesta es lo que caza los tres fallos
/// que motivaron este paquete: una URL de v0, un `DistanceUnit` que no existe
/// y un orden `lat,lon` invertido. Los tres producen respuestas de error
/// perfectamente normales, así que una prueba que solo mire el resultado los
/// deja pasar.
class FakeAlsService {
  /// Crea el servicio falso.
  FakeAlsService();

  /// Todo lo que se ha enviado, en orden.
  final List<RecordedRequest> requests = <RecordedRequest>[];

  /// Respuestas encoladas por ruta. La clave es la ruta sin el host.
  final Map<String, Object> _responses = <String, Object>{};

  /// Códigos de estado por ruta, cuando se quiere provocar un error.
  final Map<String, int> _statuses = <String, int>{};

  /// Cuántas veces debe fallar una ruta antes de responder bien.
  final Map<String, int> _failuresLeft = <String, int>{};

  /// Encola la respuesta de [path].
  void stub(String path, Map<String, dynamic> body, {int status = 200}) {
    _responses[path] = body;
    _statuses[path] = status;
  }

  /// Encola una respuesta binaria, para `GetStaticMap`.
  void stubBytes(String path, List<int> bytes, {String type = 'image/png'}) {
    _responses[path] = (bytes, type);
    _statuses[path] = 200;
  }

  /// Hace que [path] falle [times] veces antes de responder lo encolado.
  ///
  /// Sirve para probar el reintento sin depender de la red real.
  void failTimes(String path, int times, {int status = 503}) {
    _failuresLeft[path] = times;
    _statuses['$path#fail'] = status;
  }

  /// La última petición registrada.
  RecordedRequest get lastRequest => requests.last;

  /// El cliente que se le pasa a [NativMaps].
  http.Client get client => _MockClient(this);

  http.Response _handle(http.BaseRequest request, String body) {
    final path = request.url.path;
    requests.add(
      RecordedRequest(
        method: request.method,
        path: path,
        query: request.url.queryParametersAll,
        headers: Map<String, String>.from(request.headers),
        rawBody: body,
      ),
    );

    final remaining = _failuresLeft[path] ?? 0;
    if (remaining > 0) {
      _failuresLeft[path] = remaining - 1;
      return http.Response('{"message":"temporal"}', _statuses['$path#fail']!);
    }

    final stubbed = _responses[path];
    if (stubbed == null) {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'message': 'FakeAlsService: no hay respuesta encolada para $path',
        }),
        404,
      );
    }
    if (stubbed is (List<int>, String)) {
      return http.Response.bytes(
        stubbed.$1,
        200,
        headers: <String, String>{'content-type': stubbed.$2},
      );
    }
    return http.Response(
      jsonEncode(stubbed),
      _statuses[path] ?? 200,
      headers: <String, String>{
        'content-type': 'application/json',
        'x-amzn-requestid': 'prueba-0001',
      },
    );
  }
}

/// Una petición tal como llegó al servicio falso.
class RecordedRequest {
  /// Crea el registro.
  RecordedRequest({
    required this.method,
    required this.path,
    required this.query,
    required this.headers,
    required this.rawBody,
  });

  /// `GET` o `POST`.
  final String method;

  /// La ruta, sin host ni consulta.
  final String path;

  /// Los parámetros de consulta, con repeticiones.
  final Map<String, List<String>> query;

  /// Las cabeceras enviadas.
  final Map<String, String> headers;

  /// El cuerpo sin decodificar.
  final String rawBody;

  /// El cuerpo decodificado como objeto JSON.
  Map<String, dynamic> get body => rawBody.isEmpty
      ? const <String, dynamic>{}
      : jsonDecode(rawBody) as Map<String, dynamic>;

  /// El primer valor del parámetro de consulta [name].
  String? param(String name) => query[name]?.first;

  @override
  String toString() => '$method $path';
}

class _MockClient extends http.BaseClient {
  _MockClient(this._service);

  final FakeAlsService _service;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request is http.Request ? request.body : '';
    final response = _service._handle(request, body);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

/// Construye un [NativMaps] apuntando al servicio falso.
///
/// El presupuesto va sin límite por defecto para que una prueba de otra cosa
/// no falle por un tope; las pruebas de presupuesto lo pasan explícito.
NativMaps fakeNativMaps(
  FakeAlsService service, {
  String region = 'us-east-1',
  Credentials? credentials,
  Budget? budget,
  String? language = 'es',
  IntendedUse intendedUse = IntendedUse.singleUse,
}) => NativMaps(
  region: region,
  credentials: credentials ?? const ApiKeyCredentials('CLAVE-DE-PRUEBA'),
  language: language,
  intendedUse: intendedUse,
  budget: budget ?? Budget.unlimited(),
  httpClient: service.client,
  transportOptions: const TransportOptions(
    // Sin espera entre reintentos: la prueba no tiene por qué durar.
    maxRetryDelay: Duration(milliseconds: 1),
  ),
);
