# Changelog

Este proyecto sigue [Versionado Semántico](https://semver.org/lang/es/).
Mientras la versión mayor sea `0`, una versión menor puede romper la API; a
partir de `1.0.0`, no.

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

### Cuidado si usas `ProxyCredentials`

Las cabeceras que el cliente manda a tu proxy **cambian de nombre**:

```diff
-X-Compass-Service: geo-places
-X-Compass-Region:  us-east-1
+X-Nativ-Service:   geo-places
+X-Nativ-Region:    us-east-1
```

Tu proxy firma leyendo esas cabeceras. Si actualizas el paquete sin actualizar
el proxy, dejará de saber con qué servicio firmar y AWS devolverá un `403`.
Es el único cambio de este renombrado que **sale del proceso**.

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

## 0.1.0

Primera versión. **44 operaciones de Amazon Location.**

### Places v2 · 7 operaciones

`autocomplete`, `searchText`, `reverseGeocode`, `getPlace`, `geocode`,
`searchNearby` y `suggest`, con el modelo de dirección completo de v2 —país,
región, subregión, localidad, distrito, manzana, calle desglosada en piezas,
número, edificio e intersección—, contactos, horarios, puntos de acceso, zona
horaria y puntuación de coincidencia.

### Routes v2 · 5 operaciones

`calculateRoutes` (con **peajes**, alternativas e indicaciones paso a paso),
`calculateRouteMatrix`, **`calculateIsolines`** en los dos sentidos,
**`snapToRoads`** con troceado y cosido automáticos, y `optimizeWaypoints` con
citas, tiempos de servicio y descansos de conductor.

### Maps v2 · 5 operaciones

`styleDescriptorUrl` con **los 10 parámetros** del descriptor —incluidos
tráfico, relieve, edificios 3D, curvas de nivel y densidad de puntos de
interés—, `staticMap` con los tres modos de encuadre, y las URLs de teselas,
glifos y sprites.

### Geovallas · 12 operaciones

`putGeofence`, `batchPutGeofence`, `getGeofence`, `listGeofences`,
`batchDeleteGeofence`, `batchEvaluateGeofences`, **`forecastGeofenceEvents`**
—que predice entradas y salidas antes de que ocurran— y las cinco de gestión de
colecciones.

`GeofenceGeometry` admite círculo, polígono y multipolígono, cierra los anillos
sola y resuelve `contains` **en local**, sin gastar una petición.

### Rastreo de dispositivos · 15 operaciones

`batchUpdateDevicePosition` con troceado automático, `getDevicePosition`,
`batchGetDevicePosition`, `getDevicePositionHistory`, `listDevicePositions` con
filtro por polígono, `batchDeleteDevicePositionHistory`,
**`verifyDevicePosition`** —detecta ubicaciones falseadas— y las ocho de
gestión de rastreadores y de enlace con geovallas.

### Infraestructura

- Interfaz `Credentials` con `ApiKeyCredentials`, `ProxyCredentials` y
  `HeaderCredentials`.
- **Comprobación de camino de autenticación**: geovallas y rastreo rechazan la
  clave de API **antes de enviar**, con un mensaje que dice qué hacer, en vez
  de dejar que llegue como un `403` indistinguible.
- `Budget`: tope de unidades facturables por ventana **deslizante**, con la
  cuenta real por operación (isócronas por umbral, matriz por par, `snapToRoads`
  por trozo).
- Límites duros comprobados antes de enviar: 15×100 en la matriz sin acotar,
  5 umbrales en isócronas, 10 posiciones por lote en geovallas, 3 propiedades
  por geovalla, 1 000 vértices por polígono.
- `LatLng` y `LatLngBounds` que **lanzan** ante datos ilegibles en vez de
  devolver `LatLng(0, 0)`.
- Decodificador y **codificador** de Flexible Polyline de HERE, verificados
  contra el vector oficial del repositorio de HERE.
- Reintentos con retroceso exponencial y fluctuación, respetando `Retry-After`,
  que **no** reintentan un `400` ni un `403`.
- 143 pruebas con `MockClient` que verifican **la petición enviada**, no solo
  la respuesta.
