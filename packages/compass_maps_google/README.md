# compass_maps_google

**Capa de compatibilidad para migrar de `google_maps_flutter`.**

```diff
- import 'package:google_maps_flutter/google_maps_flutter.dart';
+ import 'package:compass_maps_google/compass_maps_google.dart';
```

**No depende de `google_maps_flutter`**, no llama a ninguna API de Google y no
necesita clave de Google. Solo toma prestado el vocabulario.

## El mecanismo: `typedef` y `extension`, nunca clases

El núcleo ya llama `LatLng` a `LatLng` y `Marker` a `Marker`. **No hay nada que
traducir**: la mayor parte de este paquete es reexportación. Lo poco que difiere
—unos nombres de método y el estilo JSON— va en `extension`.

- **Coste nulo en ejecución.** Un alias no crea objetos.
- **El núcleo queda libre.** Una `extension` no hereda ni envuelve.
- **Reversible.** Borrar este paquete no rompe nada debajo.
- **Conviven.** `animateCamera()` y `mostrarVehiculo()` sobre el mismo objeto.

## Traduce estilos JSON de Google

```dart
final informe = await controlador.setGoogleMapStyle(temaOscuroJson);
if (!informe.isComplete) debugPrint('$informe');
```

Los **27 `featureType`**, **9 `elementType`** y **8 *stylers*** de la referencia
de Google están modelados. La traducción es **aproximada** —MapLibre organiza
las capas de otra forma— y por eso devuelve un informe que **dice qué reglas no
se aplicaron**, en vez de fallar en silencio.

## Lo que se omite, y por qué

| Método de Google | Motivo |
|---|---|
| `setIndoorEnabled` | Amazon Location no tiene planos de interior |
| `setLiteModeEnabled` | exclusivo de Android + Google |
| `cloudMapId` | estilos alojados en la nube de Google |
| `AdvancedMarker` | API propietaria reciente de Google |

**Se omiten y se documentan; nunca un hueco que devuelve `null` en silencio.**
Un método que existe y no hace nada es peor que uno que no existe: al segundo lo
caza el compilador.

## Guía completa

[doc/MIGRACION.md](https://github.com/delioribas/compass_maps/blob/main/doc/MIGRACION.md)
