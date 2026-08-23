// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

/// Firma AWS Signature Version 4 para `nativ_maps`.
///
/// Es el camino C del diseño: firmar **en el propio dispositivo**, sin backend
/// y sin una clave permanente dentro del APK.
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
/// ## Por qué vive en su propio paquete
///
/// Va aparte **a propósito**. El paquete oficial `aws_signature_v4` arrastra
/// dieciséis dependencias transitivas, y quien solo usa una clave de API no
/// tiene por qué pagarlas.
///
/// Esta implementación depende de `crypto` y nada más, y está verificada
/// contra los vectores oficiales de la suite de pruebas de SigV4 de AWS. Esa
/// verificación no es un lujo: un fallo de firma no produce un error legible,
/// produce un `403` idéntico al de una clave inválida.
///
/// ## Los tres nombres de firma
///
/// `geo-places`, `geo-routes` y `geo-maps`. No es `geo`, ni el nombre del
/// host. Aquí no se puede equivocar porque el nombre lo pone el enum
/// `AlsService`, no quien llama.
library;

export 'src/signer.dart' show AwsCredentials, SigV4Signer;
export 'src/sigv4_credentials.dart'
    show AwsCredentialsProvider, SigV4Credentials;
