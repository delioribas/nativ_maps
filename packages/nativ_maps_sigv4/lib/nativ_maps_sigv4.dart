// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

/// AWS Signature Version 4 signing for `nativ_maps`.
///
/// It is path C of the design: signing **on the device itself**, with no
/// backend and no permanent key inside the APK.
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
/// ## Why it lives in its own package
///
/// It is separate **on purpose**. The official `aws_signature_v4` package
/// drags in sixteen transitive dependencies, and someone who only uses an API
/// key has no reason to pay for them.
///
/// This implementation depends on `crypto` and nothing else, and it is
/// verified against the official vectors of AWS's SigV4 test suite. That
/// verification is not a luxury: a signing bug doesn't produce a readable
/// error, it produces a `403` identical to that of an invalid key.
///
/// ## The three signing names
///
/// `geo-places`, `geo-routes` and `geo-maps`. Not `geo`, nor the host name.
/// You can't get it wrong here because the name is set by the `AlsService`
/// enum, not by the caller.
library;

export 'src/signer.dart' show AwsCredentials, SigV4Signer;
export 'src/sigv4_credentials.dart'
    show AwsCredentialsProvider, SigV4Credentials;
