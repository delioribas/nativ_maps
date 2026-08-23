// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:nativ_maps/nativ_maps.dart';
import 'package:nativ_maps_sigv4/src/signer.dart';

/// De dónde salen las credenciales de AWS.
///
/// Se consulta antes de cada petición, así que puede devolver credenciales
/// distintas cada vez: es lo que permite renovarlas cuando caducan sin que
/// nada más se entere.
typedef AwsCredentialsProvider = Future<AwsCredentials> Function();

/// Autenticación con **SigV4 firmando en el propio dispositivo**.
///
/// Es el camino C del diseño: sin backend y sin clave permanente dentro del
/// APK. A cambio hay que configurar un pool de identidades de Cognito y su
/// política de IAM.
///
/// ```dart
/// final maps = NativMaps(
///   region: 'us-east-1',
///   credentials: SigV4Credentials(
///     provider: () => miPoolDeCognito.obtenerCredenciales(),
///   ),
/// );
/// ```
///
/// ## Por qué esto es mejor que una clave de API
///
/// Las credenciales de un pool de identidades **caducan** —típicamente en una
/// hora— y se emiten por dispositivo. Una extraída del binario deja de servir
/// sola; una clave de API sirve hasta que alguien la revoca a mano, y para
/// entonces ya se ha gastado.
///
/// ## ⚠️ El error que cuesta una tarde
///
/// **Los tres servicios firman con nombres distintos**: `geo-places`,
/// `geo-routes`, `geo-maps`. Firmar con el equivocado da un `403` **idéntico**
/// al de una clave inválida.
///
/// Aquí no se puede equivocar: el nombre lo pone [AlsService.signingName], y
/// el servicio lo pasa el propio cliente al firmar.
///
/// ## Las teselas del mapa también
///
/// Este objeto firma las llamadas a Places, Routes y Maps. Para que **las
/// teselas** vayan firmadas hay que pasarle al widget las cabeceras que
/// produce [mapHeaders]:
///
/// ```dart
/// NativMap(
///   styleUrl: url,
///   customHeaders: await credenciales.mapHeaders(
///     styleUrl: url,
///     region: 'us-east-1',
///   ),
///   ...
/// )
/// ```
///
/// Es el motivo por el que este paquete eligió `maplibre_gl` como motor: es el
/// único que admite cabeceras HTTP propias, sin las cuales las teselas solo se
/// pueden autenticar con la clave en la URL.
class SigV4Credentials implements Credentials {
  /// Crea las credenciales a partir de un proveedor.
  SigV4Credentials({
    required AwsCredentialsProvider provider,
    Duration cacheFor = const Duration(minutes: 50),
    SigV4Signer signer = const SigV4Signer(),
  }) : _provider = provider,
       _cacheFor = cacheFor,
       _signer = signer;

  /// Crea las credenciales con unas fijas, sin renovación.
  ///
  /// Para pruebas y para un servidor Dart con credenciales de un rol. **No en
  /// una app móvil**: una clave secreta permanente dentro del binario es peor
  /// que una clave de API, porque da acceso a toda la cuenta y no solo a
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

  /// `null`: este camino autentica con cabeceras, no con la clave en la URL.
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
      // Aquí está la pieza que evita el 403 imposible de diagnosticar.
      service: service.signingName,
      region: region,
      credentials: credentials,
      body: body,
    );
    request.headers.addAll(headers);
    return request;
  }

  /// Las cabeceras firmadas para que **MapLibre** pida el estilo y las teselas.
  ///
  /// Se le pasan al widget en `customHeaders`.
  ///
  /// ## ⚠️ Estas cabeceras caducan
  ///
  /// Una firma de SigV4 vale unos minutos, y las credenciales temporales, una
  /// hora. Un mapa abierto durante horas dejará de cargar teselas nuevas.
  ///
  /// El apaño correcto es volver a llamar a esto periódicamente y a
  /// `controller.setCustomHeaders(...)` con el resultado. Por eso este método
  /// devuelve las cabeceras y no las instala: quien las instala tiene que
  /// saber que hay que repetirlo.
  ///
  /// La alternativa —un proxy que firme— no tiene este problema, y es la razón
  /// por la que sigue siendo el camino recomendado para producción.
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

  /// Las credenciales vigentes, renovándolas si hace falta.
  ///
  /// Dos llamadas simultáneas comparten una sola renovación: sin eso, arrancar
  /// una pantalla que lanza cinco peticiones a la vez pediría cinco veces
  /// credenciales al pool.
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

  /// Olvida las credenciales guardadas y obliga a pedirlas de nuevo.
  ///
  /// Hay que llamarlo al cerrar sesión: las del usuario anterior siguen
  /// siendo válidas hasta que caducan.
  void invalidate() {
    _cached = null;
    _cachedAt = null;
  }

  @override
  void close() => invalidate();

  @override
  String toString() => 'SigV4Credentials(${_cached ?? 'sin cargar'})';
}
