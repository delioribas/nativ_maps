# Cobertura

Este documento es una **lista de comprobación, no una promesa**. Dice qué está
cubierto, qué sale mejor que en Google y —sobre todo— **qué no existe**.

La razón de que sea explícito: si quien migra espera paridad completa, cada
hueco es un ticket. Un hueco documentado es una decisión; uno callado es un
fallo.

---

## Las dos reglas que gobiernan esta tabla

> **Regla 1 · hacia arriba.** Toda operación de Amazon Location **tiene** su
> método en el núcleo. Sin excepciones. Los otros niveles son vistas
> opcionales. *Esto garantiza que no se pierde nada.*

> **Regla 2 · hacia abajo.** Nada existe en la capa de compatibilidad que el
> núcleo no sepa hacer. Si `google_maps_flutter` tiene un método sin
> equivalente real, se **omite y se documenta** — nunca un hueco que devuelve
> `null` en silencio. *Esto evita la compatibilidad de mentira.*

---

## Amazon Location · 44 de 44

### Places · 7 de 7

| Operación | Método | Estado |
|---|---|---|
| `Autocomplete` | `places.autocomplete` | ✅ completo |
| `SearchText` | `places.searchText` | ✅ completo, con paginación |
| `ReverseGeocode` | `places.reverseGeocode` | ✅ completo |
| `GetPlace` | `places.getPlace` | ✅ completo |
| `Geocode` | `places.geocode` | ✅ completo, texto y componentes |
| `SearchNearby` | `places.searchNearby` | ✅ completo, con paginación |
| `Suggest` | `places.suggest` | ✅ completo, con refinamientos |

Modelo de respuesta: `Place` con **la estructura de dirección completa** de v2
—país, región, subregión, localidad, distrito, manzana, calle desglosada en
piezas, número, edificio, intersección—, contactos, horarios, puntos de acceso,
zona horaria, categorías, cadenas comerciales, tipos de comida y puntuación de
coincidencia.

### Routes · 5 de 5

| Operación | Método | Estado |
|---|---|---|
| `CalculateRoutes` | `routes.calculateRoutes` | ✅ completo |
| `CalculateRouteMatrix` | `routes.calculateRouteMatrix` | ✅ con límites comprobados antes de enviar |
| `CalculateIsolines` | `routes.calculateIsolines` | ✅ en los dos sentidos |
| `SnapToRoads` | `routes.snapToRoads` | ✅ **con troceado y cosido automáticos** |
| `OptimizeWaypoints` | `routes.optimizeWaypoints` | ✅ con citas, servicio y descansos |

### Maps · 5 de 5

| Operación | Cómo | Estado |
|---|---|---|
| `GetStyleDescriptor` | `maps.styleDescriptorUrl` | ✅ **los 10 parámetros** |
| `GetStaticMap` | `maps.staticMap` / `staticMapUrl` | ✅ los tres encuadres |
| `GetTile` | el descriptor la trae; `maps.tileUrlTemplate` | ✅ |
| `GetGlyphs` | ídem; `maps.glyphsUrlTemplate` | ✅ |
| `GetSprites` | ídem; `maps.spritesUrlTemplate` | ✅ |

### Geovallas · 12 de 12

| Operación | Método | Estado |
|---|---|---|
| `PutGeofence` | `geofencing.putGeofence` | ✅ círculo, polígono y multipolígono |
| `BatchPutGeofence` | `geofencing.batchPutGeofence` | ✅ con límite comprobado |
| `GetGeofence` | `geofencing.getGeofence` | ✅ |
| `ListGeofences` | `geofencing.listGeofences` | ✅ con paginación |
| `BatchDeleteGeofence` | `geofencing.batchDeleteGeofence` | ✅ |
| `BatchEvaluateGeofences` | `geofencing.batchEvaluateGeofences` | ✅ |
| `ForecastGeofenceEvents` | `geofencing.forecastGeofenceEvents` | ✅ **con conversión a metros** |
| `CreateGeofenceCollection` | `geofencing.createCollection` | ✅ |
| `DescribeGeofenceCollection` | `geofencing.describeCollection` | ✅ |
| `UpdateGeofenceCollection` | `geofencing.updateCollection` | ✅ |
| `DeleteGeofenceCollection` | `geofencing.deleteCollection` | ✅ |
| `ListGeofenceCollections` | `geofencing.listCollections` | ✅ |

**Geobuf no se decodifica.** Es protocol buffers y exigiría una dependencia
entera para un caso poco frecuente. Una geovalla en ese formato se marca con
`GeofenceGeometry.isGeobuf`, en vez de aparentar que no tiene forma.

### Rastreo de dispositivos · 15 de 15

| Operación | Método | Estado |
|---|---|---|
| `BatchUpdateDevicePosition` | `tracking.batchUpdateDevicePosition` | ✅ **con troceado automático** |
| `GetDevicePosition` | `tracking.getDevicePosition` | ✅ |
| `BatchGetDevicePosition` | `tracking.batchGetDevicePosition` | ✅ |
| `GetDevicePositionHistory` | `tracking.getDevicePositionHistory` | ✅ con paginación |
| `ListDevicePositions` | `tracking.listDevicePositions` | ✅ con filtro por polígono |
| `BatchDeleteDevicePositionHistory` | `tracking.batchDeleteDevicePositionHistory` | ✅ |
| `VerifyDevicePosition` | `tracking.verifyDevicePosition` | ✅ IP y Wi-Fi; **celdas LTE no** |
| `CreateTracker` … `ListTrackers` | 5 métodos | ✅ |
| `AssociateTrackerConsumer` … | 3 métodos | ✅ |

**Las señales de celdas LTE de `VerifyDevicePosition` no están modeladas.**
Son doce campos de radio —`Earfcn`, `Pci`, `Rsrp`, `Rsrq`, `Tac`,
`TimingAdvance`…— que un teléfono Android no expone sin permisos especiales y
que un localizador GT06 no manda. La IP y los puntos Wi-Fi, que sí están, son
las dos señales que se pueden obtener en la práctica.

---

## `google_maps_flutter` · 21 capacidades

Enumerado de `google_maps_flutter_platform_interface` 2.15.0.

### Idénticas · 16

| Capacidad | Cómo se implementa |
|---|---|
| `Marker` · `updateMarkers` | capa de símbolos de MapLibre |
| `Polyline` · `Cap` · `JointType` · `PatternItem` | `line-cap`, `line-join`, `line-dasharray` |
| `Polygon` | capa de relleno con anillos y agujeros |
| `Circle` | polígono geodésico de 72 lados |
| `GroundOverlay` | fuente `image` |
| `TileOverlay` · `TileProvider` | fuente `raster` |
| `animateCamera` · `moveCamera` · `…WithConfiguration` | las nueve fábricas de `CameraUpdate` |
| `getVisibleRegion` · `getZoomLevel` | directo |
| `getLatLng` · `getScreenCoordinate` | `toLatLng` · `toScreenLocation` |
| `setMapStyle` · `getStyleError` | traducción con informe |
| `clearTileCache` | gestor sin conexión |

### Mejores · 4

| Capacidad | Por qué sale mejor |
|---|---|
| **`ClusterManager`** | MapLibre agrupa **de forma nativa** (`cluster: true`), en el motor y por tesela. Google necesita una clase gestora que recalcula en Dart en cada movimiento de cámara |
| **`Heatmap`** | Capa `heatmap` nativa con rampa por expresión. En Google es un tipo cerrado con muy pocos mandos |
| **`MapColorScheme`** | Parámetro del descriptor: **el modo oscuro lo renderiza el servidor**, no es un filtro sobre teselas claras, así que las etiquetas siguen siendo legibles |
| **`trafficEnabled`** | Parámetro del descriptor, junto con relieve, edificios 3D, curvas de nivel y densidad de puntos de interés — que en Google no existen |

### Distintas · 2

| Capacidad | Qué cambia | Qué se gana |
|---|---|---|
| `takeSnapshot` | También hay `GetStaticMap`, que **lo pinta el servidor** | Funciona **fuera de pantalla**: una notificación, un PDF, un correo. `takeSnapshot` de Google exige el mapa montado y visible |
| `InfoWindow` | Reimplementada como **widget de Flutter** posicionado | Cabe **cualquier cosa** dentro: una foto, un botón, una lista |

### Imposibles · 3

| Capacidad | Por qué |
|---|---|
| `indoorViewEnabled` | **Amazon Location no tiene planos de interior.** No hay dato que servir |
| `liteModeEnabled` | Exclusivo de Android + Google. Lo más parecido es `GetStaticMap` |
| `cloudMapId` | Estilos alojados en la nube de Google. Aquí el estilo se configura con los 10 parámetros del descriptor o se retoca con `StyleEditor` |

**`AdvancedMarker`** tampoco: es una API propietaria reciente de Google sin nada
equivalente. Un `Marker` con `InfoWindow(builder:)` cubre casi todos sus casos.

**Recuento: 16 idénticas · 4 mejores · 2 de otra forma · 3 imposibles.**

---

## Lo que este paquete tiene y Google no

| | Google | Aquí |
|---|---|---|
| Autocompletado de direcciones | otra API, otra clave | `places.autocomplete` |
| Geocodificación | otra API | `places.geocode`, con `matchScore` |
| Geocodificación inversa | otra API | `places.reverseGeocode` |
| Ficha de lugar | otra API | `places.getPlace` |
| Búsqueda por cercanía | otra API | `places.searchNearby` |
| Rutas | otra API | `routes.calculateRoutes` |
| Matriz de rutas | otra API | `routes.calculateRouteMatrix` |
| **Isócronas** | **no existe** | `routes.calculateIsolines` |
| **Pegado a carretera** | **no existe** | `routes.snapToRoads` |
| **Optimización de paradas** | **no existe** | `routes.optimizeWaypoints` |
| **Coste de peajes** | **no existe** | `Toll` con importe y moneda |
| **Mapas sin conexión** | **prohibido por sus condiciones** | `controller.offline` |
| **Tope de gasto** | no existe | `Budget`, con las unidades reales |

---

## Lo que todavía no está

Honestidad sobre el estado real del paquete, no sobre su diseño.

| | Estado | Nota |
|---|---|---|
| Peticiones al servicio real de AWS | ❌ **ninguna todavía** | Todo está contrastado campo a campo contra la referencia viva de AWS y contra el modelo oficial de botocore, y probado con `MockClient`. Falta media tarde con una clave de verdad |
| Geobuf en geovallas | ❌ no se decodifica | Se detecta y se marca; ver arriba |
| Celdas LTE en `verifyDevicePosition` | ❌ no modeladas | Ver arriba |
| Jobs · API Keys · Tags | ❌ no cubiertas | 12 operaciones de gestión de la cuenta, no de datos. No las necesita una app |
| `GroundOverlay` · `TileOverlay` | modelados, no cableados | Los tipos existen y están documentados; falta la instalación de la capa en el controlador |
| Web | ❌ no declarado | `maplibre_gl` lo soporta, pero las regiones sin conexión —media razón de ser del paquete— no existen en el navegador. Declararlo sería prometer algo a medias |
| Escritorio | ❌ no declarado | Ídem |
| Cobertura de pruebas medida | ❌ | 186 pruebas verdes, sin umbral en CI todavía |
| Editor verificado en pub.dev | ❌ | Hace falta un dominio propio |

---

## Estado de verificación

| Qué | Cómo se verificó |
|---|---|
| Firma SigV4 | Contra el **vector oficial `get-vanilla` de AWS**, valor exacto, más contraste con una implementación independiente |
| Polilínea flexible de HERE | Contra el **vector oficial de `heremaps/flexible-polyline`**, los cuatro puntos |
| Los 17 endpoints | Contra la **referencia viva de la API de AWS**, consultada al escribirlos |
| Las 7 operaciones de Places | `MockClient` verificando **la petición enviada**, no solo la respuesta |
| Las 5 de Routes | Ídem, más los tres límites duros |
| Las 12 de geovallas | `MockClient` verificando método, ruta, host y cuerpo |
| Las 15 de rastreo | Ídem, más el troceado y la conversión de unidades |
| Rutas y hosts de las 27 nuevas | Contra el **modelo oficial de botocore** de AWS, incluido el prefijo `cp.` de los planos de control |
| Pub points del núcleo | **160/160**, medido con `pana` 0.23.18 |
| Análisis estático | `--fatal-infos` con `public_member_api_docs: error` en los 4 paquetes |
| Android | **APK compilado** con Flutter 3.47.1 |
| iOS | **`Runner.app` compilado** con Xcode 15.4 |

Comprobar **la petición** y no solo la respuesta es lo que caza los tres fallos
que motivaron este paquete: una URL de v0, un `DistanceUnit` que no existe y un
orden `lat,lon` invertido. Los tres producen respuestas de error perfectamente
normales, así que una prueba que solo mire el resultado los deja pasar.
