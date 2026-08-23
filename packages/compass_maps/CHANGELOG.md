# Changelog

Este proyecto sigue [Versionado Semántico](https://semver.org/lang/es/).
Mientras la versión mayor sea `0`, una versión menor puede romper la API; a
partir de `1.0.0`, no.

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
