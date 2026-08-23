# nativ_maps_sigv4

**Firma AWS Signature Version 4 para `nativ_maps`.**

Firmar **en el propio dispositivo**, sin backend y sin una clave permanente
dentro del APK.

```dart
import 'package:nativ_maps_sigv4/nativ_maps_sigv4.dart';

final maps = NativMaps(
  region: 'us-east-1',
  credentials: SigV4Credentials(
    provider: () => miPoolDeCognito.obtenerCredenciales(),
  ),
);
```

## Por qué vive en su propio paquete

Va aparte **a propósito**. El paquete oficial `aws_signature_v4` arrastra
dieciséis dependencias transitivas, y quien solo usa una clave de API no tiene
por qué pagarlas.

Esta implementación depende de `crypto` y nada más.

## Verificado contra los vectores oficiales de AWS

Un fallo de firma no produce un error legible: produce un `403` **idéntico** al
de una clave inválida. Por eso la firma se comprueba contra el valor exacto del
vector `get-vanilla` de la suite de pruebas de SigV4 de AWS, no solo contra su
forma.

## Los tres nombres de firma

**Los tres servicios de Amazon Location firman con nombres distintos:**
`geo-places`, `geo-routes`, `geo-maps`. No es `geo`, ni el nombre del host.

Aquí no se puede equivocar: el nombre lo pone el enum `AlsService`, no quien
llama.

## Las teselas del mapa también

```dart
NativMap(
  styleUrl: url,
  customHeaders: await credenciales.mapHeaders(
    styleUrl: url,
    region: 'us-east-1',
  ),
);
```

> ⚠️ **Estas cabeceras caducan.** Un mapa abierto durante horas dejará de cargar
> teselas nuevas; hay que renovarlas con `controller.setCustomHeaders(...)`. Un
> proxy que firme no tiene este problema, y por eso sigue siendo el camino
> recomendado para producción.

## Licencia

MIT
