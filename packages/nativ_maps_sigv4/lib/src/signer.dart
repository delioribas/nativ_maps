// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

/// Unas credenciales de AWS.
///
/// [sessionToken] solo lo llevan las temporales —las de un pool de identidades
/// de Cognito o las de un rol asumido—, y **es obligatorio incluirlo en la
/// firma** cuando existe: omitirlo da un `403` que se parece exactamente al de
/// una clave mala.
@immutable
class AwsCredentials {
  /// Crea las credenciales.
  const AwsCredentials({
    required this.accessKeyId,
    required this.secretAccessKey,
    this.sessionToken,
    this.expiration,
  });

  /// El identificador de la clave.
  final String accessKeyId;

  /// La clave secreta. **Nunca se escribe en un registro ni en un error.**
  final String secretAccessKey;

  /// El testigo de sesión, en credenciales temporales.
  final String? sessionToken;

  /// Cuándo caducan, en credenciales temporales.
  final DateTime? expiration;

  /// ¿Son temporales?
  bool get isTemporary => sessionToken != null;

  /// ¿Están caducadas, con [margin] de margen?
  ///
  /// El margen existe porque una petición firmada con credenciales que caducan
  /// dentro de dos segundos llega caducada. Un minuto es de sobra.
  bool isExpired({Duration margin = const Duration(minutes: 1)}) {
    final expires = expiration;
    if (expires == null) return false;
    return DateTime.now().toUtc().isAfter(expires.subtract(margin));
  }

  @override
  String toString() =>
      'AwsCredentials($accessKeyId${isTemporary ? ', temporales' : ''})';
}

/// Firma peticiones con **AWS Signature Version 4**.
///
/// ## Por qué esto está en su propio paquete
///
/// El paquete oficial `aws_signature_v4` funciona bien, pero arrastra
/// dieciséis dependencias transitivas. Quien solo usa una clave de API no
/// tiene por qué pagarlas.
///
/// Esta implementación depende de `crypto` y nada más. Está verificada contra
/// los **vectores oficiales de la suite de pruebas de SigV4 de AWS**, que es
/// la única forma de confiar en un firmador: un fallo de firma no da un error
/// legible, da un `403` idéntico al de una clave inválida.
///
/// ## El error que más cuesta
///
/// **Los tres servicios de Amazon Location firman con nombres distintos**:
/// `geo-places`, `geo-routes` y `geo-maps`. No es `geo`, ni el nombre del
/// host. Firmar con el equivocado da un `403` que no se distingue del de una
/// clave mala, y ahí es donde se pierde la tarde.
///
/// Por eso `SigV4Credentials` recibe un `AlsService` y no una cadena: el
/// nombre lo pone el enum, no quien llama.
@immutable
class SigV4Signer {
  /// Crea el firmador.
  const SigV4Signer();

  /// El algoritmo, que va literal en la cabecera.
  static const String algorithm = 'AWS4-HMAC-SHA256';

  /// El SHA-256 en hexadecimal de un cuerpo vacío.
  ///
  /// Se usa tantas veces —toda petición `GET`— que merece ser constante.
  static const String emptyBodySha256 =
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

  /// Firma una petición y devuelve las cabeceras que hay que añadir.
  ///
  /// Devuelve las cabeceras en lugar de modificar la petición para que sirva
  /// igual con `http`, con `dio` o con lo que sea, y para poder probarla sin
  /// construir una petición.
  ///
  /// [uri] tiene que llevar ya todos los parámetros de consulta: la firma los
  /// cubre, así que añadir uno después la invalida.
  ///
  /// [signedAt] existe para las pruebas; en producción se deja sin poner y se
  /// usa la hora actual en UTC.
  Map<String, String> sign({
    required String method,
    required Uri uri,
    required String service,
    required String region,
    required AwsCredentials credentials,
    Map<String, String> headers = const <String, String>{},
    List<int>? body,
    DateTime? signedAt,
  }) {
    final now = (signedAt ?? DateTime.now()).toUtc();
    final amzDate = _amzDate(now);
    final dateStamp = amzDate.substring(0, 8);

    final payloadHash = body == null || body.isEmpty
        ? emptyBodySha256
        : _hex(sha256.convert(body).bytes);

    // ── 1 · Petición canónica ──────────────────────────────────────────
    //
    // El orden de todo aquí es parte del algoritmo: cabeceras ordenadas por
    // nombre en minúsculas, parámetros de consulta ordenados por clave y
    // luego por valor, y la ruta codificada. Cualquier desviación produce una
    // firma distinta y un 403 sin explicación.
    final canonicalHeaders = <String, String>{
      'host': _hostHeader(uri),
      'x-amz-date': amzDate,
      if (credentials.sessionToken != null)
        'x-amz-security-token': credentials.sessionToken!,
      'x-amz-content-sha256': payloadHash,
      for (final entry in headers.entries)
        entry.key.toLowerCase(): entry.value.trim(),
    };

    final sortedHeaderNames = canonicalHeaders.keys.toList()..sort();
    final signedHeaders = sortedHeaderNames.join(';');

    final canonicalRequest = <String>[
      method.toUpperCase(),
      _canonicalPath(uri),
      _canonicalQuery(uri),
      for (final name in sortedHeaderNames)
        '$name:${_collapseSpaces(canonicalHeaders[name]!)}',
      '',
      signedHeaders,
      payloadHash,
    ].join('\n');

    // ── 2 · Cadena que se firma ────────────────────────────────────────
    final scope = '$dateStamp/$region/$service/aws4_request';
    final stringToSign = <String>[
      algorithm,
      amzDate,
      scope,
      _hex(sha256.convert(utf8.encode(canonicalRequest)).bytes),
    ].join('\n');

    // ── 3 · Clave de firma, derivada en cuatro pasos ───────────────────
    //
    // Cada paso usa el resultado del anterior como clave. El primero lleva el
    // prefijo `AWS4` pegado al secreto, que es fácil de olvidar.
    final signature = _hex(
      _hmac(
        _signingKey(credentials.secretAccessKey, dateStamp, region, service),
        utf8.encode(stringToSign),
      ),
    );

    return <String, String>{
      'Authorization':
          '$algorithm '
          'Credential=${credentials.accessKeyId}/$scope, '
          'SignedHeaders=$signedHeaders, '
          'Signature=$signature',
      'X-Amz-Date': amzDate,
      'X-Amz-Content-Sha256': payloadHash,
      if (credentials.sessionToken != null)
        'X-Amz-Security-Token': credentials.sessionToken!,
    };
  }

  /// La petición canónica, expuesta para poder probarla contra los vectores
  /// oficiales de AWS.
  ///
  /// La suite de pruebas de AWS trae, para cada caso, el fichero `.creq` con
  /// esta cadena exacta. Poder compararla es lo que convierte «la firma sale
  /// mal» en «el paso 1 sale mal».
  @visibleForTesting
  String canonicalRequestFor({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required String payloadHash,
  }) {
    final lower = <String, String>{
      for (final entry in headers.entries)
        entry.key.toLowerCase(): entry.value.trim(),
    };
    final names = lower.keys.toList()..sort();
    return <String>[
      method.toUpperCase(),
      _canonicalPath(uri),
      _canonicalQuery(uri),
      for (final name in names) '$name:${_collapseSpaces(lower[name]!)}',
      '',
      names.join(';'),
      payloadHash,
    ].join('\n');
  }

  /// La firma hexadecimal de una petición canónica ya construida.
  ///
  /// Expuesta para poder comprobar el resultado **exacto** contra los vectores
  /// oficiales de AWS, que publican la petición canónica (`.creq`) y la firma
  /// final por separado. Sin esto solo se podría comprobar que la firma tiene
  /// la forma correcta, que es una garantía mucho más débil: una firma mal
  /// calculada también tiene sesenta y cuatro caracteres hexadecimales.
  @visibleForTesting
  String signatureOfCanonicalRequest({
    required String canonicalRequest,
    required String amzDate,
    required String region,
    required String service,
    required String secretAccessKey,
  }) {
    final dateStamp = amzDate.substring(0, 8);
    final stringToSign = <String>[
      algorithm,
      amzDate,
      '$dateStamp/$region/$service/aws4_request',
      _hex(sha256.convert(utf8.encode(canonicalRequest)).bytes),
    ].join('\n');
    return _hex(
      _hmac(
        _signingKey(secretAccessKey, dateStamp, region, service),
        utf8.encode(stringToSign),
      ),
    );
  }

  // ─── Piezas del algoritmo ─────────────────────────────────────────────

  static List<int> _signingKey(
    String secret,
    String dateStamp,
    String region,
    String service,
  ) {
    // El prefijo `AWS4` va pegado al secreto. Olvidarlo da una firma válida en
    // forma y rechazada por el servidor.
    final kDate = _hmac(utf8.encode('AWS4$secret'), utf8.encode(dateStamp));
    final kRegion = _hmac(kDate, utf8.encode(region));
    final kService = _hmac(kRegion, utf8.encode(service));
    return _hmac(kService, utf8.encode('aws4_request'));
  }

  static List<int> _hmac(List<int> key, List<int> data) =>
      Hmac(sha256, key).convert(data).bytes;

  static String _hex(List<int> bytes) =>
      Uint8List.fromList(bytes).map(_byteToHex).join();

  static String _byteToHex(int byte) => byte.toRadixString(16).padLeft(2, '0');

  /// La marca de tiempo en el formato compacto de AWS: `20260822T120000Z`.
  static String _amzDate(DateTime utc) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${utc.year}${two(utc.month)}${two(utc.day)}T'
        '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
  }

  /// La cabecera `Host`, con el puerto solo si no es el estándar.
  ///
  /// Incluir `:443` en un HTTPS invalida la firma, porque el cliente HTTP no
  /// lo manda y el servidor firma sin él.
  static String _hostHeader(Uri uri) {
    final isDefaultPort =
        (uri.scheme == 'https' && uri.port == 443) ||
        (uri.scheme == 'http' && uri.port == 80) ||
        !uri.hasPort;
    return isDefaultPort ? uri.host : '${uri.host}:${uri.port}';
  }

  /// La ruta canónica.
  ///
  /// Los segmentos van codificados con el juego de caracteres sin reservar de
  /// RFC 3986, y **la barra no se codifica**. `Uri.path` ya viene codificado,
  /// así que se decodifica y se vuelve a codificar para normalizar: dos rutas
  /// equivalentes con codificaciones distintas tienen que dar la misma firma.
  static String _canonicalPath(Uri uri) {
    if (uri.path.isEmpty) return '/';
    final segments = uri.path.split('/').map((segment) {
      if (segment.isEmpty) return '';
      return _uriEncode(Uri.decodeComponent(segment));
    });
    return segments.join('/');
  }

  /// La cadena de consulta canónica: ordenada por clave y luego por valor.
  static String _canonicalQuery(Uri uri) {
    final pairs = <(String, String)>[];
    uri.queryParametersAll.forEach((key, values) {
      for (final value in values) {
        pairs.add((_uriEncode(key), _uriEncode(value)));
      }
    });
    pairs.sort((a, b) {
      final byKey = a.$1.compareTo(b.$1);
      return byKey != 0 ? byKey : a.$2.compareTo(b.$2);
    });
    return pairs.map((pair) => '${pair.$1}=${pair.$2}').join('&');
  }

  /// Codifica según RFC 3986, que **no** es lo que hace
  /// `Uri.encodeComponent`.
  ///
  /// Dos diferencias que importan: `Uri.encodeComponent` deja pasar `!`, `*`,
  /// `'`, `(` y `)`, que AWS sí codifica; y codifica el espacio como `%20`,
  /// que es lo correcto —nunca como `+`—.
  static String _uriEncode(String value) {
    const unreserved =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~';
    final buffer = StringBuffer();
    for (final byte in utf8.encode(value)) {
      final char = String.fromCharCode(byte);
      if (unreserved.contains(char)) {
        buffer.write(char);
      } else {
        buffer.write('%${_byteToHex(byte).toUpperCase()}');
      }
    }
    return buffer.toString();
  }

  /// Colapsa espacios consecutivos, como exige el algoritmo para los valores
  /// de cabecera.
  static String _collapseSpaces(String value) {
    final buffer = StringBuffer();
    var lastWasSpace = false;
    for (final unit in value.trim().codeUnits) {
      final isSpace = unit == 0x20;
      if (isSpace && lastWasSpace) continue;
      buffer.writeCharCode(unit);
      lastWasSpace = isSpace;
    }
    return buffer.toString();
  }
}
