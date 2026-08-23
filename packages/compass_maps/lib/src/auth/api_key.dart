// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:compass_maps/src/auth/credentials.dart';
import 'package:compass_maps/src/core/enums.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

/// Autenticación con una clave de API de Amazon Location.
///
/// Es el camino de cero infraestructura: la clave viaja como `?key=` en la
/// cadena de consulta y no hace falta ni backend ni pool de identidades.
///
/// ## ⚠️ Lo que hay que saber antes de usarla en producción
///
/// **Una clave compilada dentro del APK se extrae en dos minutos.** No es una
/// hipótesis ni una cuestión de ofuscación: el binario contiene la cadena, y
/// hay herramientas de una línea para sacarla. Quien la saque puede gastar
/// contra tu cuenta hasta que la revoques.
///
/// Lo que la hace aceptable, cuando lo es:
///
/// - **Restringir la clave en la consola de AWS.** Se le pueden fijar las
///   operaciones permitidas, la lista de referentes y una fecha de caducidad.
///   Una clave que solo sirve para `GetStyleDescriptor` y caduca en 90 días es
///   un riesgo muy distinto de una sin restricciones.
/// - **Ponerle un tope de gasto de verdad**, en AWS Budgets. El `Budget` de
///   este paquete protege de tus propios bucles, no de un tercero con tu clave.
///
/// Para todo lo demás está [ProxyCredentials] o el paquete
/// `compass_maps_sigv4`.
@immutable
final class ApiKeyCredentials extends DirectCredentials {
  /// Crea las credenciales a partir de la clave.
  const ApiKeyCredentials(this.apiKey);

  /// La clave de API de Amazon Location.
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
    // La clave se añade a la consulta conservando lo que ya hubiera: varias
    // operaciones de Maps llevan sus propios parámetros ahí, y reemplazar el
    // mapa entero los borraría.
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

/// Autenticación delegada en un backend propio que firma con SigV4.
///
/// El móvil llama a tu servidor, tu servidor firma y reenvía a AWS. **La clave
/// nunca sale del servidor**, que es la única forma de que no se pueda extraer
/// del APK.
///
/// El backend tiene que reproducir la ruta tal cual: si la app pide
/// `POST /v2/search-text`, el proxy debe firmar y reenviar exactamente eso al
/// host `places.geo.{región}.amazonaws.com`. Este paquete no impone ningún
/// formato propio precisamente para que el proxy pueda ser un reenviador
/// transparente de veinte líneas.
///
/// [headers] permite añadir la autenticación de **tu** backend —el token de
/// sesión del usuario, normalmente—, que es una cosa distinta de la de AWS.
@immutable
final class ProxyCredentials implements Credentials {
  /// Crea las credenciales apuntando al backend.
  const ProxyCredentials({required this.baseUrl, this.headers = const {}});

  /// La base del proxy, p. ej. `https://api.miempresa.com/geo`.
  ///
  /// La ruta de la operación se añade detrás, así que una base con ruta
  /// (`/geo`) produce `/geo/v2/search-text`.
  final Uri baseUrl;

  /// Cabeceras que se añaden a cada petición: normalmente el `Authorization`
  /// de tu propio backend.
  final Map<String, String> headers;

  @override
  bool get isConfigured => baseUrl.host.isNotEmpty;

  /// `null`: el proxy autentica con cabeceras, no con la clave en la URL.
  @override
  String? get apiKeyForUrl => null;

  /// El proxy es un solo destino para los tres servicios. Se le indica cuál
  /// era con la cabecera `X-Compass-Service`, para que pueda firmar con el
  /// nombre correcto sin tener que deducirlo de la ruta.
  @override
  Uri baseUri(AlsService service, String region) => baseUrl;

  @override
  Future<http.BaseRequest> sign(
    http.BaseRequest request,
    AlsService service,
    String region,
  ) async {
    request.headers.addAll(headers);
    request.headers['X-Compass-Service'] = service.signingName;
    request.headers['X-Compass-Region'] = region;
    return request;
  }

  @override
  void close() {}

  @override
  String toString() => 'ProxyCredentials($baseUrl)';
}

/// Autenticación con cabeceras que produce una función tuya.
///
/// Es el escape para lo que no encaja en los otros tres: un token que se
/// renueva solo, una firma calculada en código nativo, una cabecera que exige
/// una pasarela corporativa. La función se llama **en cada petición**, así que
/// puede devolver un valor distinto cada vez; si es cara, cachéala dentro.
final class HeaderCredentials implements Credentials {
  /// Crea las credenciales a partir de la función que produce las cabeceras.
  const HeaderCredentials(this._headerBuilder, {Uri? baseUrl})
    : _baseUrl = baseUrl;

  final Future<Map<String, String>> Function(AlsService service, String region)
  _headerBuilder;
  final Uri? _baseUrl;

  @override
  bool get isConfigured => true;

  /// `null`: este camino autentica con cabeceras.
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

/// Copia una petición cambiándole la URL.
///
/// [http.BaseRequest.url] es de solo lectura, así que no hay forma de
/// redirigir una petición sin reconstruirla. Se conservan el cuerpo, las
/// cabeceras y los ajustes; solo se contemplan los dos tipos que este paquete
/// produce.
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
