// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

/// A set of AWS credentials.
///
/// [sessionToken] is only carried by temporary ones —those from a Cognito
/// identity pool or from an assumed role—, and **it must be included in the
/// signature** when it exists: leaving it out gives a `403` that looks exactly
/// like the one for a bad key.
@immutable
class AwsCredentials {
  /// Creates the credentials.
  const AwsCredentials({
    required this.accessKeyId,
    required this.secretAccessKey,
    this.sessionToken,
    this.expiration,
  });

  /// The key's identifier.
  final String accessKeyId;

  /// The secret key. **It is never written to a log or to an error.**
  final String secretAccessKey;

  /// The session token, in temporary credentials.
  final String? sessionToken;

  /// When they expire, in temporary credentials.
  final DateTime? expiration;

  /// Are they temporary?
  bool get isTemporary => sessionToken != null;

  /// Have they expired, with a [margin] of safety?
  ///
  /// The margin exists because a request signed with credentials that expire
  /// two seconds from now arrives expired. One minute is more than enough.
  bool isExpired({Duration margin = const Duration(minutes: 1)}) {
    final expires = expiration;
    if (expires == null) return false;
    return DateTime.now().toUtc().isAfter(expires.subtract(margin));
  }

  @override
  String toString() =>
      'AwsCredentials($accessKeyId${isTemporary ? ', temporales' : ''})';
}

/// Signs requests with **AWS Signature Version 4**.
///
/// ## Why this is in its own package
///
/// The official `aws_signature_v4` package works well, but it drags in sixteen
/// transitive dependencies. Someone who only uses an API key has no reason to
/// pay for them.
///
/// This implementation depends on `crypto` and nothing else. It is verified
/// against the **official vectors of AWS's SigV4 test suite**, which is the
/// only way to trust a signer: a signing bug doesn't give a readable error, it
/// gives a `403` identical to that of an invalid key.
///
/// ## The most expensive mistake
///
/// **The three Amazon Location services sign with different names**:
/// `geo-places`, `geo-routes` and `geo-maps`. Not `geo`, nor the host name.
/// Signing with the wrong one gives a `403` indistinguishable from that of a
/// bad key, and that is where the afternoon goes.
///
/// That is why `SigV4Credentials` takes an `AlsService` and not a string: the
/// name is set by the enum, not by the caller.
@immutable
class SigV4Signer {
  /// Creates the signer.
  const SigV4Signer();

  /// The algorithm, which goes verbatim into the header.
  static const String algorithm = 'AWS4-HMAC-SHA256';

  /// The hex SHA-256 of an empty body.
  ///
  /// It is used so often —every `GET` request— that it deserves to be a
  /// constant.
  static const String emptyBodySha256 =
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

  /// Signs a request and returns the headers that must be added.
  ///
  /// It returns the headers instead of modifying the request so that it works
  /// the same with `http`, with `dio` or with anything else, and so that it can
  /// be tested without building a request.
  ///
  /// [uri] must already carry all the query parameters: the signature covers
  /// them, so adding one afterwards invalidates it.
  ///
  /// [signedAt] exists for tests; in production it is left unset and the
  /// current UTC time is used.
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

    // ── 1 · Canonical request ──────────────────────────────────────────
    //
    // The order of everything here is part of the algorithm: headers sorted
    // by lowercase name, query parameters sorted by key and then by value,
    // and the path encoded. Any deviation produces a different signature and
    // an unexplained 403.
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

    // ── 2 · String to sign ─────────────────────────────────────────────
    final scope = '$dateStamp/$region/$service/aws4_request';
    final stringToSign = <String>[
      algorithm,
      amzDate,
      scope,
      _hex(sha256.convert(utf8.encode(canonicalRequest)).bytes),
    ].join('\n');

    // ── 3 · Signing key, derived in four steps ─────────────────────────
    //
    // Each step uses the previous result as its key. The first one has the
    // `AWS4` prefix glued to the secret, which is easy to forget.
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

  /// The canonical request, exposed so it can be tested against AWS's
  /// official vectors.
  ///
  /// For each case, AWS's test suite ships the `.creq` file with this exact
  /// string. Being able to compare it is what turns "the signature comes out
  /// wrong" into "step 1 comes out wrong".
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

  /// The hex signature of an already built canonical request.
  ///
  /// Exposed so the **exact** result can be checked against AWS's official
  /// vectors, which publish the canonical request (`.creq`) and the final
  /// signature separately. Without this you could only check that the
  /// signature has the right shape, which is a much weaker guarantee: a
  /// miscalculated signature also has sixty-four hex characters.
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

  // ─── Pieces of the algorithm ──────────────────────────────────────────

  static List<int> _signingKey(
    String secret,
    String dateStamp,
    String region,
    String service,
  ) {
    // The `AWS4` prefix is glued to the secret. Forgetting it gives a
    // signature that is valid in shape and rejected by the server.
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

  /// The timestamp in AWS's compact format: `20260822T120000Z`.
  static String _amzDate(DateTime utc) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${utc.year}${two(utc.month)}${two(utc.day)}T'
        '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
  }

  /// The `Host` header, with the port only if it is not the standard one.
  ///
  /// Including `:443` on an HTTPS request invalidates the signature, because
  /// the HTTP client doesn't send it and the server signs without it.
  static String _hostHeader(Uri uri) {
    final isDefaultPort =
        (uri.scheme == 'https' && uri.port == 443) ||
        (uri.scheme == 'http' && uri.port == 80) ||
        !uri.hasPort;
    return isDefaultPort ? uri.host : '${uri.host}:${uri.port}';
  }

  /// The canonical URI: the path **as it travels**, encoded again.
  ///
  /// Every service except S3 encodes twice. `Uri.path` is already encoded —an
  /// ARN in the path travels as `arn%3Aaws`— and the canonical URI encodes it
  /// again: `arn%253Aaws`. The slash is not encoded.
  ///
  /// It used to be decoded and then encoded only once. That made no difference
  /// as long as the path had nothing to encode; with an ARN, as in
  /// `DisassociateTrackerConsumer`, AWS responded 403.
  static String _canonicalPath(Uri uri) {
    if (uri.path.isEmpty) return '/';
    return uri.path.split('/').map(_uriEncode).join('/');
  }

  /// The canonical query string: sorted by key and then by value.
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

  /// Encodes according to RFC 3986, which is **not** what
  /// `Uri.encodeComponent` does.
  ///
  /// Two differences that matter: `Uri.encodeComponent` lets `!`, `*`, `'`,
  /// `(` and `)` through, which AWS does encode; and it encodes the space as
  /// `%20`, which is correct —never as `+`—.
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

  /// Collapses consecutive spaces, as the algorithm requires for header
  /// values.
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
