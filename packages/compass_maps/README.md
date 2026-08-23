# compass_maps

**Amazon Location Service v2 en Dart puro, con la forma de Google Maps.**

Las **44 operaciones** —Places, Routes, Maps, geovallas y rastreo de
dispositivos— detrás de un cliente tipado, con tope de gasto, reintentos y
**sin ninguna dependencia de Flutter**.

```dart
import 'package:compass_maps/compass_maps.dart';

final maps = CompassMaps(
  region: 'us-east-1',
  credentials: const ApiKeyCredentials('tu-clave'),
  language: 'es',
  budget: Budget(maxUnits: 500),
);

final lugares = await maps.places.searchText(queryText: 'gasolinera');
final ruta = await maps.routes.calculateRoutes(
  origin: aqui,
  destination: lugares.places.first.position!,
);
```

## ¿Buscas el mapa?

Este paquete **no dibuja**. El widget está en
[`compass_maps_flutter`](https://pub.dev/packages/compass_maps_flutter), que
reexporta todo esto: instalando solo ese ya tienes las cuarenta y cuatro
más el mapa.

Este vive aparte para poder **probarse sin emulador** y para servir en una
herramienta de línea de órdenes o un servidor Dart.

## Las 44 operaciones

| Places · 7 | Routes · 5 | Maps · 5 |
|---|---|---|
| `autocomplete` | `calculateRoutes` | `styleDescriptorUrl` |
| `searchText` | `calculateRouteMatrix` | `staticMap` |
| `reverseGeocode` | **`calculateIsolines`** | `tileUrlTemplate` |
| `getPlace` | **`snapToRoads`** | `glyphsUrlTemplate` |
| `geocode` | `optimizeWaypoints` | `spritesUrlTemplate` |
| `searchNearby` | | |
| `suggest` | | |

Las dos en negrita **no existen en Google Maps**.

| Geovallas · 12 | Rastreo de dispositivos · 15 |
|---|---|
| `putGeofence` · `batchPutGeofence` | `batchUpdateDevicePosition` |
| `getGeofence` · `listGeofences` | `getDevicePosition` |
| `batchDeleteGeofence` | `batchGetDevicePosition` |
| `batchEvaluateGeofences` | `getDevicePositionHistory` |
| **`forecastGeofenceEvents`** | `listDevicePositions` |
| 5 de gestión de colecciones | **`verifyDevicePosition`** |
| | 9 de gestión y de enlace |

**`forecastGeofenceEvents`** avisa **antes** de que un dispositivo entre o salga
de una zona. **`verifyDevicePosition`** detecta ubicaciones falseadas. Ninguna
de las dos tiene equivalente en Google Maps.

> ⚠️ Geovallas y rastreo son de la **generación anterior** de Amazon Location:
> hay que crear un recurso y **no admiten clave de API** —hacen falta
> credenciales SigV4—. El paquete lo comprueba **antes de enviar**, con un
> mensaje que dice qué hacer, en vez de dejar que llegue como un `403`
> idéntico a todos los demás.

## Control de gasto

Amazon Location se factura **por petición**, y algunas cobran más de una:

| Operación | Lo que parece | Lo que cuesta |
|---|---|---|
| `calculateIsolines` con 5 umbrales | 1 petición | **5 unidades** |
| `calculateRouteMatrix` de 10×10 | 1 petición | **100 unidades** |

`Budget` cuenta las unidades reales y corta antes de enviar. Los límites duros
del servicio también se comprueban antes, con el cálculo hecho en el mensaje de
error.

## Documentación

- [Recetas](https://github.com/delioribas/compass_maps/blob/main/doc/RECETAS.md) — 40 ejemplos copiables
- [Para agentes de IA](https://github.com/delioribas/compass_maps/blob/main/AGENTS.md)
- [Cobertura](https://github.com/delioribas/compass_maps/blob/main/doc/COBERTURA.md)

## Licencia

MIT
