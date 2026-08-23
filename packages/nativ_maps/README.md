# nativ_maps

**Amazon Location Service v2 en Dart puro, con la forma de Google Maps.**

Las **44 operaciones** —Places, Routes, Maps, geovallas y rastreo de
dispositivos— detrás de un cliente tipado, con tope de gasto, reintentos y
**sin ninguna dependencia de Flutter**.

```dart
import 'package:nativ_maps/nativ_maps.dart';

final maps = NativMaps(
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
[`nativ_maps_flutter`](https://pub.dev/packages/nativ_maps_flutter), que
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

## La capa de cálculo

Dart puro, **sin peticiones**: lo que hace falta encima del servicio para que
una aplicación de taxi, de pujas o de rastreo funcione de verdad.

| Clase | Qué resuelve |
|---|---|
| `TripRecorder` | mide el viaje sin que el ruido del GPS lo infle |
| `Tariff` | taxímetro con desglose auditable, franjas y espera |
| `RouteTracker` | ETA por maniobra y desvío, sin llamadas |
| `RideAuction` · `BidAdvisor` | subasta tipo inDrive y rentabilidad real |
| `DispatchPlanner` | el conductor más cercano en tiempo, no en línea recta |
| `TelemetryAnalyzer` | acelerones, frenazos, curvas y excesos |

Un coche parado con ±20 m de incertidumbre acumula **más de 5 km** por hora si
se suman las distancias entre lecturas. `TripRecorder` acumula **menos de
50 m**. Esa diferencia es lo que el pasajero acaba pagando.

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

- [Recetas](https://github.com/delioribas/nativ_maps/blob/main/doc/RECETAS.md) — 40 ejemplos copiables
- [Para agentes de IA](https://github.com/delioribas/nativ_maps/blob/main/AGENTS.md)
- [Cobertura](https://github.com/delioribas/nativ_maps/blob/main/doc/COBERTURA.md)

## Licencia

MIT
