# Migrar desde `google_maps_flutter`

> **La prueba de que la capa de compatibilidad está bien hecha** es que un
> proyecto real que use `google_maps_flutter` funcione cambiando el `import`.
> Este documento dice exactamente cuánto es cierto y dónde deja de serlo.

---

## Paso 1 · Cambiar dependencias

```diff
 dependencies:
-  google_maps_flutter: ^2.12.0
+  nativ_maps_flutter: ^0.3.0
+  nativ_maps_google:
+    git:
+      url: https://github.com/delioribas/nativ_maps.git
+      path: packages/nativ_maps_google
+      ref: v0.3.0
```

`nativ_maps_google` **no está en pub.dev a propósito**: es una capa de
transición, y publicarla sería un cuarto paquete que mantener para siempre. Se
consume por git con una **etiqueta**, nunca con una rama — una rama cambia bajo
los pies y rompe compilaciones que ayer funcionaban.

```diff
-import 'package:google_maps_flutter/google_maps_flutter.dart';
+import 'package:nativ_maps_google/nativ_maps_google.dart';
```

`nativ_maps_google` **no depende de `google_maps_flutter`**, no llama a
ninguna API de Google y no necesita clave de Google. Solo toma prestado el
vocabulario.

---

## Paso 2 · Quitar las claves de Google de las plataformas

### Android

```diff
 <application …>
-  <meta-data android:name="com.google.android.geo.API_KEY"
-             android:value="AIza…"/>
 </application>
```

### iOS

```diff
 // ios/Runner/AppDelegate.swift
-import GoogleMaps
 …
-    GMSServices.provideAPIKey("AIza…")
```

**No hace falta añadir nada a cambio**: la clave de Amazon Location va en el
código Dart, y el estilo llega por URL.

---

## Paso 3 · Lo que ya compila sin tocarlo

Estos nombres son **idénticos**, con la misma firma:

| | |
|---|---|
| Tipos | `LatLng` · `LatLngBounds` · `Marker` · `MarkerId` · `Polyline` · `PolylineId` · `Polygon` · `PolygonId` · `Circle` · `CircleId` · `InfoWindow` · `BitmapDescriptor` · `CameraPosition` · `CameraUpdate` · `MinMaxZoomPreference` · `Cap` · `JointType` · `PatternItem` |
| Cámara | las **nueve** fábricas de `CameraUpdate`, más `bearingTo` y `tiltTo` que Google no tiene |
| Controlador | `animateCamera` · `moveCamera` · `getVisibleRegion` · `getZoomLevel` · `getScreenCoordinate` · `getLatLng` · `takeSnapshot` · `setMapStyle` · `clearTileCache` · `updateMarkers` · `updatePolylines` · `updatePolygons` · `updateCircles` · `getStyleError` |

---

## Paso 4 · Lo que hay que cambiar

### 4.1 · El widget

```diff
-GoogleMap(
-  initialCameraPosition: CameraPosition(target: quito, zoom: 13),
-  markers: _marcadores,
-  polylines: _lineas,
-  onMapCreated: (c) => _controlador = c,
-)
+NativMap(
+  styleUrl: maps.maps.styleDescriptorUrl(MapStyle.standard)!,
+  initialCameraPosition: CameraPosition(target: quito, zoom: 13),
+  onMapCreated: (c) {
+    _controlador = c;
+    c.setMarkers(_marcadores);
+    c.setPolylines(_lineas);
+  },
+)
```

**Las superposiciones van por el controlador, no por parámetros del widget.**

No es un capricho. En Google, cambiar un marcador reconstruye el árbol y
recalcula el conjunto entero. Con doscientos vehículos actualizándose cada tres
segundos, eso se ve. Aquí, mover un vehículo es una llamada al controlador y el
widget no se reconstruye.

**Cómo se traduce un `setState` con marcadores:**

```diff
-setState(() => _marcadores = nuevos);
+await _controlador.setMarkers(nuevos);
```

`setMarkers` calcula qué sobra y qué falta, así que no parpadea.

### 4.2 · Iconos

```diff
-final icono = await BitmapDescriptor.fromAssetImage(
-  const ImageConfiguration(size: Size(48, 48)),
-  'assets/vehiculo.png',
-);
+final datos = await rootBundle.load('assets/vehiculo.png');
+final icono = BitmapDescriptor.fromBytes(
+  'vehiculo',                       // ← nombre único: es la clave del estilo
+  datos.buffer.asUint8List(),
+);
```

MapLibre registra la imagen **una vez por nombre** y la referencia muchas: cien
marcadores con el mismo icono la suben una sola vez. A cambio, hay que darle un
nombre, y dos iconos distintos con el mismo nombre se pisan.

### 4.3 · Tipo de mapa

```diff
-mapType: MapType.terrain,
+styleUrl: maps.maps.styleDescriptorUrl(
+  MapType.terrain.asMapStyle,
+  terrain: MapType.terrain.terrainOption,
+)!,
```

`MapType` existe en `nativ_maps_google` con `asMapStyle` y `terrainOption`
para hacer justo esta traducción.

| `MapType` de Google | Aquí | |
|---|---|---|
| `normal` | `MapStyle.standard` | idéntico |
| `satellite` | `MapStyle.satellite` | idéntico |
| `hybrid` | `MapStyle.hybrid` | idéntico |
| `terrain` | `standard` + `terrain:` | **mejor**: se elige sombreado o modelo 3D |
| `none` | — | **no existe**: MapLibre siempre pinta el fondo del estilo |

### 4.4 · Estilo JSON

```diff
-_controlador.setMapStyle(temaOscuroJson);
+final informe = await _controlador.setGoogleMapStyle(temaOscuroJson);
+if (!informe.isComplete) debugPrint('$informe');
```

Ver la sección [Estilos de Google](#estilos-de-google-qué-se-traduce-y-qué-no).

### 4.5 · Tráfico

```diff
-trafficEnabled: true,
+styleUrl: maps.maps.styleDescriptorUrl(
+  MapStyle.standard,
+  traffic: MapTraffic.all,     // o .congestion
+)!,
```

**Mejor que en Google**: el tráfico lo dibuja el servidor dentro del propio
estilo, no es una capa superpuesta.

### 4.6 · Clústeres

```diff
-final gestor = ClusterManager(...);   // recalcula en Dart en cada movimiento
-clusterManagers: {gestor},
+await _controlador.addClusterManager(
+  const ClusterManager(clusterManagerId: ClusterManagerId('flota')),
+);
+// y cada marcador con: clusterManagerId: const ClusterManagerId('flota')
```

Aquí agrupa **el motor**, en C++ y por tesela.

---

## Paso 5 · Lo que no existe

**Se omite y se documenta; nunca un hueco que devuelve `null` en silencio.** Un
método que existe y no hace nada es peor que uno que no existe: al segundo lo
caza el compilador el día de la migración, no un usuario seis meses después.

| Método de Google | Por qué no está | Qué hacer |
|---|---|---|
| `setIndoorEnabled` / `indoorViewEnabled` | Amazon Location **no tiene planos de interior** | Borrar la llamada. No hay alternativa |
| `setLiteModeEnabled` / `liteModeEnabled` | Exclusivo de Android + Google | Usar `GetStaticMap` para una vista no interactiva |
| `cloudMapId` | Estilos alojados en la nube de Google | Usar el descriptor con sus 10 parámetros, o `StyleEditor` |
| `AdvancedMarker` | API propietaria reciente de Google | `Marker` normal + `InfoWindow` con `builder` |
| `buildingsEnabled` | En v2 es `MapBuildings.buildings3d` | `styleDescriptorUrl(..., buildings: MapBuildings.buildings3d)` |

---

## Estilos de Google: qué se traduce y qué no

```dart
final informe = await controlador.setGoogleMapStyle(temaOscuroJson);

print(informe);
// GoogleStyleReport: 21 de 24 reglas aplicadas (88 %), 47 de 183 capas
// modificadas.
// Sin capa que coincida:
//   · transit.station.bus/all — ninguna capa del estilo de Amazon Location
//     coincide con ese tipo de elemento
//   · road.highway/geometry.stroke — hay 4 capa(s) que coinciden, pero su
//     color viene de una expresión que depende del zoom…
```

### Cómo traduce

1. Pide al motor la lista de capas del estilo cargado.
2. Para cada regla, busca las capas cuyo identificador contiene alguna palabra
   clave del `featureType` — la tabla completa está en
   `GoogleMapStyle.featureKeywords`, visible a propósito.
3. Separa geometría de etiquetas según el `elementType`.
4. Aplica los *stylers* en el orden que documenta Google: color absoluto, tinte,
   saturación, brillo, gamma, inversión.

### Lo que cubre

Los **27 `featureType`**, los **9 `elementType`** y los **8 *stylers*** de la
referencia de Google están leídos y modelados. En la práctica funciona bien para
lo que se usa el 95 % de las veces: agua, vías, etiquetas, puntos de interés,
terreno y `visibility: off`.

### Lo que no puede cubrir

| Limitación | Por qué |
|---|---|
| `road.highway.controlled_access` vs `road.highway` | MapLibre no separa esas dos capas |
| Saturación, brillo y gamma sobre vías | Su color viene de una **expresión que depende del zoom**: no hay un color fijo sobre el que operar |
| `visibility: "simplified"` | Se trata como `on`; MapLibre no tiene un nivel intermedio |
| Coincidencias exactas de tono | Las paletas base son distintas |

**Por eso el informe existe.** Una traducción que se traga en silencio lo que no
entiende es peor que ninguna: quien migra cree que su tema está aplicado y no
sabe qué falta.

### Cuándo llamarlo

```dart
NativMap(
  styleUrl: url,
  onMapCreated: (c) => _controlador = c,
  // En onStyleLoaded, NO en onMapCreated: un cambio de styleUrl recarga el
  // estilo desde el servidor y deshace todos los retoques.
  onStyleLoaded: () async {
    await _controlador.setGoogleMapStyle(temaOscuro);
  },
);
```

Si el informe deja fuera algo que importa, se ajusta a mano con `StyleEditor`:

```dart
await controlador.style.setColor('road-motorway-case', const Color(0xFF1A1A2E));
```

---

## Lo que se gana con la migración

No es solo paridad. Estas cinco cosas **no existen en Google** y están
disponibles el mismo día que cambias el `import`:

| | |
|---|---|
| **Búsqueda y geocodificación** | En el mismo cliente y con los mismos tipos. Antes: otra API, otra clave, otro sistema de tipos, y el pegamento entre los dos |
| **Isócronas** | «Hasta dónde pudo llegar en 8 minutos» sin calcular mil rutas |
| **Pegado a carretera** | Un rastro GPS con ruido convertido en un recorrido enseñable |
| **Coste de peajes** | Importe y moneda por peaje |
| **Mapas sin conexión** | Prohibido por las condiciones de Google. Aquí es una llamada |

---

## Lista de comprobación

```text
[ ] Cambiado el import a nativ_maps_google
[ ] Quitadas las claves de Google de AndroidManifest.xml y AppDelegate.swift
[ ] GoogleMap → NativMap, con styleUrl
[ ] markers:/polylines:/… → controlador.setMarkers(...)/setPolylines(...)
[ ] BitmapDescriptor.fromAssetImage → .fromBytes con nombre único
[ ] mapType → styleUrl con el estilo y el relieve
[ ] setMapStyle(json) → setGoogleMapStyle(json), y LEÍDO el informe
[ ] Borradas las llamadas a los métodos que no existen
[ ] android/settings.gradle.kts con AGP 8.x, no 9.x
[ ] JDK 21 configurado (flutter config --jdk-dir)
[ ] La atribución se ve en pantalla
[ ] Presupuesto puesto en NativMaps
```
