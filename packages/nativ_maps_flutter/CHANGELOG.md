# Changelog

## 0.2.0

**El paquete cambia de nombre.** Antes se publicaba como `compass_maps` y
`compass_maps_flutter`; ahora es `nativ_maps` y `nativ_maps_flutter`. El código
es el mismo y la versión sigue la serie anterior, pero **cambian todos los
`import` y todos los nombres de clase**, y eso es lo que justifica subir la
menor en vez de publicar un parche.

Los nombres antiguos quedan en pub.dev marcados como descontinuados, apuntando
aquí. No van a recibir más versiones.

### Cambiado

- **Nombres de paquete**

  | Antes | Ahora |
  |---|---|
  | `compass_maps` | **`nativ_maps`** |
  | `compass_maps_flutter` | **`nativ_maps_flutter`** |
  | `compass_maps_google` | **`nativ_maps_google`** |
  | `compass_maps_sigv4` | **`nativ_maps_sigv4`** |

- **Nombres de clase.** El prefijo `Compass` pasa a `Nativ`, sin excepción:

  | Antes | Ahora |
  |---|---|
  | `CompassMap` | **`NativMap`** |
  | `CompassMapController` | **`NativMapController`** |
  | `CompassMaps` | **`NativMaps`** |
  | `CompassMapsException` | **`NativMapsException`** |
  | `CompassMapsConfigurationException` | **`NativMapsConfigurationException`** |
  | `CompassOfflineManager` | **`NativOfflineManager`** |

- **El repositorio se movió** a `github.com/delioribas/nativ_maps`. Las
  dependencias por git tienen que apuntar a la etiqueta `v0.2.0` de la URL
  nueva; GitHub redirige la antigua, pero no conviene depender de eso.

### Sin cambios, a propósito

- **`compassEnabled` sigue llamándose así.** Es la brújula del mapa, no el
  nombre del paquete: es el parámetro que espera `maplibre_gl` y es el mismo
  nombre que usa `GoogleMap`, así que renombrarlo habría roto la promesa de
  migrar cambiando un solo `import`.
- Ninguna firma, ningún parámetro y ningún comportamiento. Solo nombres.

## 0.1.1

**Baja el suelo de versiones cinco versiones de Dart.** La 0.1.0 exigía
`sdk: ^3.13.0` y `meta: ^1.19.0`, que en la práctica lo dejaban inservible
para cualquier proyecto que no estuviera ya en Flutter 3.47.

### Cambiado

- `sdk`: `^3.13.0` → **`^3.8.0`**. El suelo real, comprobado ejecutando el
  análisis y las pruebas con Dart 3.8.1: por debajo falla porque el paquete
  usa elementos con `?` en literales de colección, estables desde Dart 3.8.
- `meta`: `^1.19.0` → **`^1.16.0`**. Este era el bloqueo peor, porque **lo fija
  el SDK de Flutter** y no hay `dependency_override` que valga: Flutter 3.32 y
  3.35 traen `meta` 1.16.0, la 3.41 trae 1.17.0 y la 3.44 trae 1.18.0. Pedir
  `^1.19.0` las excluía todas. De `meta` solo se usan `@immutable`,
  `@internal` y `@visibleForTesting`, las tres disponibles desde 1.2.0.
- `http`: `^1.6.0` → **`^1.1.0`**. Solo se usan `Client`, `BaseClient`,
  `Request`, `Response` y `StreamedResponse`.

### Corregido

- **`@internal` rompía la compilación en Flutter 3.32.**
  `package:flutter/foundation.dart` no reexporta esa anotación hasta versiones
  recientes, y los imports de `meta` se habían quitado porque el linter de
  Flutter 3.47 los marcaba como redundantes. Doce errores de
  `undefined_annotation` que solo aparecían en el suelo.

### Quitado

- La dependencia de `collection`, que estaba declarada y **no se importaba en
  ningún fichero**.

### Cambiado, además

- `flutter`: `>=3.41.0` → **`>=3.32.0`**. Es la primera versión estable que
  trae Dart 3.8, así que es la que corresponde al nuevo suelo del SDK.

## 0.1.0

Primera versión.

### El widget

- `NativMap` sobre MapLibre Native, con Android e iOS **verificados
  compilando**, no declarados.
- `NativMapController` con los nombres exactos de `google_maps_flutter`:
  `animateCamera`, `moveCamera`, `getVisibleRegion`, `getZoomLevel`,
  `getScreenCoordinate`, `getLatLng`, `takeSnapshot`, `setMapStyle`.
- Las **nueve** fábricas de `CameraUpdate` de Google, más `bearingTo` y
  `tiltTo`, que Google no tiene.

### Superposiciones

- `Marker` con rumbo, etiqueta, orden de apilado y globo de información.
- `Polyline` con extremos, uniones y patrones discontinuos.
- `Polygon` con agujeros y `Circle` **geodésico**, con el radio en metros.
- **`ClusterManager` nativo**: agrupa el motor, por tesela, no una clase en
  Dart que recalcula en cada movimiento de cámara.
- **`Heatmap` como capa nativa**, con rampa de color, radio e intensidad
  propios.
- `InfoWindow` reimplementada como widget de Flutter: cabe cualquier cosa
  dentro.
- Sincronización **agrupada por microtask**: añadir 300 marcadores en un bucle
  es una sola llamada al motor.
- Hit-test **nativo** con `queryRenderedFeatures`, no el más cercano en píxeles.

### Sin conexión

`NativOfflineManager` con descarga de regiones y progreso observable, tope de
caché, listado, borrado, caducidad automática y fusión de una base preparada.
**`google_maps_flutter` no puede dar esto**: sus condiciones prohíben cachear
teselas.

### Estilo

`StyleEditor` para retocar el estilo en caliente: apagar capas por palabra
clave, cambiar colores, grosores y opacidades, y aplicar propiedades de pintura
a medida.

### Las 44 operaciones

Reexporta `nativ_maps` entero: instalando solo este paquete se tienen todas.
