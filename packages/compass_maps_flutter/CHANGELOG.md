# Changelog

## 0.1.0

Primera versión.

### El widget

- `CompassMap` sobre MapLibre Native, con Android e iOS **verificados
  compilando**, no declarados.
- `CompassMapController` con los nombres exactos de `google_maps_flutter`:
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

`CompassOfflineManager` con descarga de regiones y progreso observable, tope de
caché, listado, borrado, caducidad automática y fusión de una base preparada.
**`google_maps_flutter` no puede dar esto**: sus condiciones prohíben cachear
teselas.

### Estilo

`StyleEditor` para retocar el estilo en caliente: apagar capas por palabra
clave, cambiar colores, grosores y opacidades, y aplicar propiedades de pintura
a medida.

### Las 44 operaciones

Reexporta `compass_maps` entero: instalando solo este paquete se tienen todas.
