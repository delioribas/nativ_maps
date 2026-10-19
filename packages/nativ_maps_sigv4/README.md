# nativ_maps_sigv4

**AWS Signature Version 4 signing for `nativ_maps`.**

Signing **on the device itself**, with no backend and no permanent key inside
the APK.

```dart
import 'package:nativ_maps_sigv4/nativ_maps_sigv4.dart';

final maps = NativMaps(
  region: 'us-east-1',
  credentials: SigV4Credentials(
    provider: () => myCognitoPool.fetchCredentials(),
  ),
);
```

## Why it lives in its own package

It is separate **on purpose**. The official `aws_signature_v4` package drags in
sixteen transitive dependencies, and someone who only uses an API key has no
reason to pay for them.

This implementation depends on `crypto` and nothing else.

## Verified against AWS's official vectors

A signing bug doesn't produce a readable error: it produces a `403`
**identical** to that of an invalid key. That is why the signature is checked
against the exact value of the `get-vanilla` vector from AWS's SigV4 test
suite, not just against its shape.

## The three signing names

**The three Amazon Location services sign with different names:**
`geo-places`, `geo-routes`, `geo-maps`. Not `geo`, nor the host name.

You can't get it wrong here: the name is set by the `AlsService` enum, not by
the caller.

## The map tiles too

```dart
NativMap(
  styleUrl: url,
  customHeaders: await credentials.mapHeaders(
    styleUrl: url,
    region: 'us-east-1',
  ),
);
```

> ⚠️ **These headers expire.** A map left open for hours will stop loading new
> tiles; you have to refresh them with `controller.setCustomHeaders(...)`. A
> signing proxy doesn't have this problem, and that is why it is still the
> recommended path for production.

## License

MIT
