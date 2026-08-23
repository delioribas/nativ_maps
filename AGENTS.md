# AGENTS.md — cómo usar `compass_maps` sin leer el código fuente

Este archivo está escrito para **agentes de IA** que tengan que escribir código
contra este paquete. Es denso a propósito: todo lo que hace falta para acertar a
la primera, sin abrir ningún `.dart`.

Si eres una persona, [README.md](README.md) es más agradable y
[doc/RECETAS.md](doc/RECETAS.md) tiene los ejemplos completos.

---

## 0 · Lo mínimo

```yaml
dependencies:
  compass_maps_flutter: ^0.1.0   # widget + las 44 operaciones
  compass_maps_sigv4: ^0.1.0     # SOLO si usas geovallas o rastreo
  compass_maps_google: ^0.1.0    # SOLO si migras de google_maps_flutter
```

```dart
import 'package:compass_maps_flutter/compass_maps_flutter.dart';
```

**Un solo import.** `compass_maps_flutter` reexporta el núcleo entero. Nunca
importes `package:compass_maps/compass_maps.dart` en una app Flutter: no hace
falta y duplica los símbolos.

---

## 1 · Las quince reglas duras

Si solo lees una sección, que sea esta. Cada regla existe porque romperla
produce un fallo **silencioso**.

| # | Regla | Qué pasa si la rompes |
|---|---|---|
| 1 | `LatLng(lat, lng)` — **latitud primero** | El constructor lanza si la latitud sale de `[-90, 90]`; si no, dibujas en otro continente |
| 2 | Nunca conviertas coordenadas a mano | Usa `toLonLat()` / `LatLng.fromLonLat()`. Son las únicas fronteras donde el orden cambia |
| 3 | **Distancias en metros, duraciones en segundos.** Siempre | v2 no tiene parámetro de unidad. Enviar `DistanceUnit` da `400` |
| 4 | Nunca envíes `DistanceUnit`, `Motorcycle` ni URLs con `/v0/` | Son de la generación anterior. `400` o `404` |
| 5 | La moto es `TravelMode.scooter`, no `motorcycle` | El enum no deja equivocarse; si construyes el JSON a mano, sí |
| 6 | `calculateIsolines` **siempre** con `granularity` | Sin `maxPoints`, 30 min = miles de vértices y la interfaz se congela. El valor por defecto ya trae 300 |
| 7 | La matriz cuesta **por par** | 10×10 = 100 unidades. Filtra por `distanceTo()` —gratis— antes de llamar |
| 8 | Las isócronas cuestan **por umbral** | 5 umbrales = 5 unidades |
| 9 | Un `Place` de `autocomplete` **no trae posición** | Llama a `getPlace(placeId)` solo con la que el usuario elija |
| 10 | Comprueba `MatrixCell.isValid` antes de usar los números | Una celda con error trae **ceros**, y un cero parece «lo más cerca posible» |
| 11 | Comprueba `PlaceType.isPrecise` en `reverseGeocode` | Un `locality` significa «no encontré el portal, te doy la ciudad» — kilómetros de diferencia |
| 12 | **Geovallas y rastreo NO aceptan clave de API** | Se corta antes de enviar. Hacen falta `ProxyCredentials` o `compass_maps_sigv4` |
| 13 | `batchEvaluateGeofences` **devuelve vacío a propósito** | Los eventos salen por **EventBridge**, no por la respuesta. Para saberlo ahora, `GeofenceGeometry.contains` (local, gratis) |
| 14 | Mira `BatchResult.errors` siempre | Estas operaciones responden 200 aunque falle la mitad |
| 15 | En rastreo, `sampleTime` es **la hora del GPS** | La de envío desordena el histórico y engaña al filtrado del rastreador |

---

## 2 · Mapa de la API

### Punto de entrada

```dart
final maps = CompassMaps(
  region: 'us-east-1',                              // requerido
  credentials: const ApiKeyCredentials('clave'),    // requerido
  language: 'es',                                   // opcional, BCP 47
  politicalView: null,                              // opcional, ISO 3166
  intendedUse: IntendedUse.singleUse,               // storage si lo guardas
  budget: Budget(maxUnits: 500),                    // opcional pero recomendado
);

maps.places      // PlacesClient     · 7 operaciones · v2, acepta clave
maps.routes      // RoutesClient     · 5 operaciones · v2, acepta clave
maps.maps        // MapsClient       · 5 operaciones · v2, acepta clave
maps.geofencing  // GeofencingClient · 12 ops · ⚠️ EXIGE SigV4
maps.tracking    // TrackingClient   · 15 ops · ⚠️ EXIGE SigV4
maps.close();    // cierra el cliente HTTP
```

### `maps.places` — firmas exactas

```dart
Future<List<AutocompleteSuggestion>> autocomplete({
  required String query,
  LatLng? biasPosition,
  SearchFilter? filter,
  int maxResults = 5,              // 1..20, LANZA fuera de rango
  PostalCodeMode? postalCodeMode,
  List<PlaceFeature> additionalFeatures = const [],
  String? language,
  bool useCache = true,
});

Future<PlaceSearchResponse> searchText({
  String? queryText,               // queryText O queryId, no los dos
  String? queryId,
  LatLng? biasPosition,
  SearchFilter? filter,
  int maxResults = 10,             // 1..100
  List<PlaceFeature> additionalFeatures = const [],
  String? nextToken,               // paginación
  String? language,
  IntendedUse? intendedUse,
  bool useCache = true,
});

Future<List<Place>> reverseGeocode(
  LatLng position, {
  double? radiusMeters,            // PONLO. Sin él, la ciudad más cercana
  int maxResults = 1,
  List<String> includePlaceTypes = const [],
  List<PlaceFeature> additionalFeatures = const [],
  String? language,
  IntendedUse? intendedUse,
});

Future<Place> getPlace(
  String placeId, {
  List<PlaceFeature> additionalFeatures = const [],  // contact/timeZone/access
  String? language,
  IntendedUse? intendedUse,
  bool useCache = true,
});

Future<List<Place>> geocode({
  String? queryText,                        // texto O componentes
  AddressComponents? queryComponents,
  LatLng? biasPosition,
  List<String> includeCountries = const [], // ISO alfa-3: 'ECU', no 'EC'
  int maxResults = 5,
  List<PlaceFeature> additionalFeatures = const [],
  String? language,
  IntendedUse? intendedUse,
});

Future<PlaceSearchResponse> searchNearby({
  required LatLng position,
  double? radiusMeters,            // PONLO
  SearchFilter? filter,
  int maxResults = 10,
  List<PlaceFeature> additionalFeatures = const [],
  String? nextToken,
  String? language,
  IntendedUse? intendedUse,
});

Future<SuggestResponse> suggest({
  required String query,
  LatLng? biasPosition,
  SearchFilter? filter,
  int maxResults = 5,              // 1..20
  int? maxQueryRefinements,
  List<PlaceFeature> additionalFeatures = const [],  // pide `core` para posición
  String? language,
});
```

### `maps.routes` — firmas exactas

```dart
Future<RouteResponse> calculateRoutes({
  required LatLng origin,
  required LatLng destination,
  List<LatLng> waypoints = const [],
  TravelMode travelMode = TravelMode.car,
  TravelModeOptions? travelModeOptions,      // .truck() / .car() / .scooter()
  DateTime? departureTime,                   // excluyente con arrivalTime
  DateTime? arrivalTime,
  RouteOptimization optimizeFor = RouteOptimization.fastestRoute,
  RouteAvoidance? avoid,
  TrafficUsage traffic = TrafficUsage.useTrafficData,
  GeometryFormat geometryFormat = GeometryFormat.simple,
  TravelStepType travelStepType = TravelStepType.turnByTurn,
  List<RouteFeature> legAdditionalFeatures = const [],  // tolls, summary…
  int maxAlternatives = 0,                   // 0..6
  String? language,
  bool useCache = true,
});

Future<RouteMatrix> calculateRouteMatrix({
  required List<LatLng> origins,        // ≤15 sin routingBoundary
  required List<LatLng> destinations,   // ≤100 · celdas ≤100
  TravelMode travelMode = TravelMode.car,
  TravelModeOptions? travelModeOptions,
  LatLngBounds? routingBoundary,        // pásalo para superar los límites
  DateTime? departureTime,
  RouteAvoidance? avoid,
  TrafficUsage traffic = TrafficUsage.useTrafficData,
  RouteOptimization optimizeFor = RouteOptimization.fastestRoute,
});

Future<IsolineResponse> calculateIsolines({
  LatLng? origin,                       // origin XOR destination
  LatLng? destination,
  required Thresholds thresholds,       // ≤5 umbrales
  TravelMode travelMode = TravelMode.car,
  TravelModeOptions? travelModeOptions,
  IsolineGranularity granularity = const IsolineGranularity(maxPoints: 300),
  DateTime? departureTime,
  DateTime? arrivalTime,
  RouteAvoidance? avoid,
  TrafficUsage traffic = TrafficUsage.useTrafficData,
  RouteOptimization optimizeFor = RouteOptimization.fastestRoute,
  GeometryFormat geometryFormat = GeometryFormat.simple,
});

Future<SnapToRoadsResponse> snapToRoads({
  required List<TracePoint> tracePoints,   // ≥2 · se trocea solo si >5000
  double? snapRadiusMeters,                // 0..10000 · usa ~500 en ciudad
  TravelMode travelMode = TravelMode.car,
  TravelModeOptions? travelModeOptions,
  GeometryFormat geometryFormat = GeometryFormat.simple,
  int overlapPoints = 10,                  // solape entre trozos
});

Future<WaypointOptimizationResponse> optimizeWaypoints({
  required LatLng origin,
  required List<OptimizationWaypoint> waypoints,   // ids ÚNICOS
  LatLng? destination,
  TravelMode travelMode = TravelMode.car,
  TravelModeOptions? travelModeOptions,
  DateTime? departureTime,
  WaypointOptimization optimizeFor = WaypointOptimization.fastestRoute,
  RouteAvoidance? avoid,
  TrafficUsage traffic = TrafficUsage.useTrafficData,
  DriverOptions? driver,
});
```

### `maps.maps` — firmas exactas

```dart
String? styleDescriptorUrl(          // devuelve null si no hay credenciales
  MapStyle style, {                  // standard | monochrome | hybrid | satellite
  MapColorScheme? colorScheme,       // light | dark  ← lo renderiza el servidor
  MapTraffic? traffic,               // all | congestion
  MapTerrain? terrain,               // hillshade | terrain3d
  MapBuildings? buildings,           // buildings3d
  MapContourDensity? contourDensity, // low | medium | high
  MapPoiDensity? poiDensity,         // off | verySparse | … | veryDense
  List<MapPoiCategory> poiCategories = const [],  // ≤9
  List<MapTravelMode> travelModes = const [],     // ≤2
  String? politicalView,
});

({String? light, String? dark}) dayNightStyleUrls(MapStyle style, {...});

Future<AlsBytes> staticMap({         // los bytes de la imagen
  LatLng? center, double? zoom,      // center+zoom XOR boundingBox XOR
  LatLngBounds? boundingBox,         // boundedPositions
  List<LatLng> boundedPositions = const [],
  required int width,                // 1..1440
  required int height,               // 1..1440
  MapStyle style = MapStyle.standard,
  MapColorScheme? colorScheme,
  String? geoJsonOverlay,            // geometría encima
  ...
});

String? staticMapUrl({...});         // ⚠️ la URL LLEVA LA CLAVE: no la registres
```

### `maps.geofencing` — firmas exactas

⚠️ **Exige SigV4.** Con `ApiKeyCredentials` lanza
`CompassMapsConfigurationException` **antes de enviar**.

```dart
Future<Geofence> putGeofence({
  required String collectionName,
  required String geofenceId,
  required GeofenceGeometry geometry,     // .circle() .polygon() .multiPolygon()
  Map<String, String> properties = const {},  // ≤3, clave ≤20, valor ≤40
});

Future<BatchResult> batchPutGeofence({    // ≤10
  required String collectionName,
  required List<Geofence> geofences,
});

Future<Geofence> getGeofence({required String collectionName,
                              required String geofenceId});

Future<GeofencePage<Geofence>> listGeofences({
  required String collectionName, int? maxResults, String? nextToken});

Future<BatchResult> batchDeleteGeofence({
  required String collectionName, required List<String> geofenceIds});

// Devuelve SOLO errores: los eventos ENTER/EXIT salen por EventBridge.
Future<BatchResult> batchEvaluateGeofences({
  required String collectionName,
  required List<DevicePositionUpdate> positions,   // ≤10
});

// LA operación que justifica esta familia: avisa ANTES de que ocurra.
Future<ForecastGeofenceEventsResponse> forecastGeofenceEvents({
  required String collectionName,
  required LatLng position,
  double? speedKmh,          // SIN ESTO no predice, solo comprueba contención
  Duration? timeHorizon,     // SIN ESTO tampoco
  int? maxResults,
  String? nextToken,
});

// Plano de control (host cp.geofencing.geo.…, se resuelve solo)
Future<GeofenceCollection> createCollection({required String collectionName,
    String? description, String? kmsKeyId, Map<String, String> tags = const {}});
Future<GeofenceCollection> describeCollection(String collectionName);
Future<GeofenceCollection> updateCollection({required String collectionName,
    String? description});
Future<void> deleteCollection(String collectionName);   // borra las geovallas
Future<GeofencePage<GeofenceCollection>> listCollections({int? maxResults,
    String? nextToken});
```

`GeofenceGeometry` resuelve `contains(LatLng)` **en local, gratis**. La
evaluación oficial —la que dispara eventos— es `batchEvaluateGeofences`.

### `maps.tracking` — firmas exactas

⚠️ **Exige SigV4.** Y antes de usarlo: **si ya guardas el histórico en tu propia
base de datos, esto es infraestructura duplicada.** Lo que sí lo justifica:
`associateConsumer`, `verifyDevicePosition` y `listDevicePositions` con filtro.

```dart
// Trocea solo en peticiones de 10.
Future<BatchResult> batchUpdateDevicePosition({
  required String trackerName,
  required List<DevicePositionUpdate> updates,
});

Future<DevicePosition> getDevicePosition({required String trackerName,
                                          required String deviceId});

Future<({List<DevicePosition> positions, BatchResult result})>
  batchGetDevicePosition({required String trackerName,
                          required List<String> deviceIds});  // ≤10

Future<TrackingPage<DevicePosition>> getDevicePositionHistory({
  required String trackerName,
  required String deviceId,
  DateTime? from,        // por defecto: últimas 24 h
  DateTime? to,
  int? maxResults,       // 1..100
  String? nextToken,
});

// «quién hay dentro de este polígono ahora mismo»
Future<TrackingPage<DevicePosition>> listDevicePositions({
  required String trackerName,
  List<LatLng>? filterGeometry,   // ≥3 puntos, se cierra solo
  int? maxResults,
  String? nextToken,
});

Future<BatchResult> batchDeleteDevicePositionHistory({
  required String trackerName, required List<String> deviceIds});

// ¿me están falseando la ubicación?
Future<PositionVerification> verifyDevicePosition({
  required String trackerName,
  required String deviceId,
  required LatLng position,
  required DateTime sampleTime,
  double? horizontalAccuracyMeters,
  String? ipv4Address,                       // SIN ESTO no deduce gran cosa
  List<WiFiAccessPoint> wifiAccessPoints = const [],
});

// Plano de control
Future<Tracker> createTracker({required String trackerName, String? description,
    PositionFiltering positionFiltering = PositionFiltering.distanceBased,
    bool? eventBridgeEnabled, String? kmsKeyId, Map<String, String> tags = const {}});
Future<Tracker> describeTracker(String trackerName);
Future<Tracker> updateTracker({required String trackerName, String? description,
    PositionFiltering? positionFiltering, bool? eventBridgeEnabled});
Future<void> deleteTracker(String trackerName);          // borra el histórico
Future<TrackingPage<Tracker>> listTrackers({int? maxResults, String? nextToken});

// El enlace que hace que las geovallas se evalúen SOLAS
Future<void> associateConsumer({required String trackerName,
                                required String collectionArn});  // el ARN
Future<void> disassociateConsumer({required String trackerName,
                                   required String collectionArn});
Future<TrackingPage<String>> listConsumers({required String trackerName,
    int? maxResults, String? nextToken});
```

**AWS borra el histórico a los 30 días.** No es configurable.

### `CompassMapController` — lo que se usa de verdad

```dart
// Cámara — nombres idénticos a google_maps_flutter
Future<void> animateCamera(CameraUpdate update, {Duration? duration});
Future<void> moveCamera(CameraUpdate update);
Future<CameraPosition?> getCameraPosition();   // null si el mapa no está listo
Future<LatLngBounds> getVisibleRegion();
Future<double> getZoomLevel();
Future<Offset> getScreenCoordinate(LatLng latLng);
Future<LatLng> getLatLng(Offset screenCoordinate);
Future<double> getMetersPerPixel(double latitude);

// Marcadores
Future<void> addMarker(Marker m);
Future<void> addMarkers(Iterable<Marker> ms);   // USA ESTE con más de un puñado
Future<void> updateMarker(Marker m);
Future<void> removeMarker(MarkerId id);
Future<void> setMarkers(Iterable<Marker> ms);   // deja EXACTAMENTE ese conjunto
Future<void> clearMarkers();
List<Marker> get markers;

// Igual para polylines / polygons / circles:
//   addX · removeX(XId) · setXs(Iterable) · clearXs · get xs

// Lo que Google no tiene
Future<void> addHeatmap(Heatmap h);
Future<void> removeHeatmap(HeatmapId id);
Future<void> addClusterManager(ClusterManager m);   // ANTES de los marcadores
Future<double> getClusterExpansionZoom(Cluster c);
CompassOfflineManager? get offline;   // null si offlineEnabled: false
StyleEditor get style;                // retocar capas en caliente

// Estilo y capturas
Future<void> setMapStyle(String styleUrl);
Future<void> setCustomHeaders(Map<String, String> h, {List<String> urlFilter});
Future<Uint8List> takeSnapshot({int? width, int? height});
Future<void> clearTileCache();
```

### El widget

```dart
CompassMap(
  styleUrl: ...,                        // requerido
  initialCameraPosition: ...,           // requerido, SOLO al crear
  onMapCreated: (CompassMapController c) {},
  onStyleLoaded: () {},                 // en CADA carga, no solo la primera
  onStyleError: (Object e) {},          // ENGÁNCHALO
  onTap: (LatLng p) {},
  onLongPress: (LatLng p) {},
  onMarkerTap: (Marker m) {},           // tiene prioridad sobre onTap
  onClusterTap: (Cluster c) {},         // sin él, tocar un grupo lo abre solo
  onPolylineTap: (Polyline p) {},
  onCameraMove: (CameraPosition p) {},  // con antirrebote de 60 ms
  onCameraIdle: () {},                  // ← PIDE DATOS AQUÍ, no en onCameraMove
  myLocationEnabled: false,
  myLocationTracking: MyLocationTracking.none,
  compassEnabled: true,
  zoomControlsEnabled: false,
  scaleBarEnabled: false,
  attributionEnabled: true,             // ⚠️ quitarlo puede incumplir condiciones
  rotateGesturesEnabled: true,
  scrollGesturesEnabled: true,
  zoomGesturesEnabled: true,
  tiltGesturesEnabled: true,
  minMaxZoomPreference: MinMaxZoomPreference.unbounded,
  cameraTargetBounds: null,
  offlineEnabled: false,                // true para que `offline` no sea null
  customHeaders: null,                  // para SigV4 en las teselas
  padding: EdgeInsets.zero,
  styleLoadTimeout: Duration(seconds: 20),
)
```

---

## 3 · Diferencias con `google_maps_flutter` que cambian el código

| En Google | Aquí | Por qué |
|---|---|---|
| `markers: {…}` como parámetro del widget | `controller.addMarker(...)` | Mover un vehículo no debe reconstruir el árbol de widgets |
| `BitmapDescriptor.fromAssetImage` | `BitmapDescriptor.fromBytes(nombre, bytes)` | MapLibre registra la imagen **una vez** por nombre y la referencia muchas |
| `GoogleMapController` | `CompassMapController` | — |
| `MapType.terrain` | `MapStyle.standard` + `terrain:` | Aquí el relieve es un parámetro, no un estilo cerrado |
| `setMapStyle(json)` (Google JSON) | `setGoogleMapStyle(json)` en `compass_maps_google` | Traducción **aproximada**, con informe |
| `tilt` | `tilt` (MapLibre lo llama *pitch*) | Se mantiene el nombre de Google |

**Con `compass_maps_google` importado, `animateCamera`, `moveCamera`,
`getVisibleRegion`, `getZoomLevel`, `updateMarkers`, `getStyleError` y las nueve
fábricas de `CameraUpdate` ya se llaman igual.**

---

## 4 · Errores: qué capturar y qué significa

```dart
try {
  await maps.places.searchText(queryText: 'x');
} on AlsApiException catch (e) {
  e.statusCode;             // 400, 403, 404, 429, 5xx
  e.isConfigurationError;   // true en 400 y 403 → NO reintentes
  e.isRetryable;            // true en 429 y 5xx
  e.hint;                   // ← LEE ESTO: la causa concreta, escrita
  e.requestId;              // lo primero que pide el soporte de AWS
} on BudgetExhaustedException catch (e) {
  e.requestedUnits;         // lo que pedía la operación rechazada
  e.resetsAt;               // cuándo vuelve a haber presupuesto
} on AlsTransportException {
  // No llegó a haber respuesta → NO se ha facturado nada
} on CompassMapsConfigurationException {
  // Falta la clave. Se lanza ANTES de enviar
} on AlsParseException {
  // 200 pero la forma cambió. No reintentes: mira el cuerpo real
}
```

`CompassMapsException` es la raíz **sellada** de las cinco. Capturarla atrapa
todo lo del framework sin atrapar los errores de programación de tu app.

`ArgumentError` se lanza **antes de enviar** en los límites duros (matriz,
umbrales, `maxResults`, filtros excluyentes). No se ha gastado nada.

---

## 5 · Patrones correctos

### Barra de búsqueda (el patrón barato)

```dart
// 1 · al teclear, con antirrebote de 300 ms
_debounce = Timer(const Duration(milliseconds: 300), () async {
  final s = await maps.places.autocomplete(
    query: texto,
    biasPosition: posicionActual,                       // ordena
    filter: const SearchFilter(includeCountries: ['ECU']),  // descarta
  );
  setState(() => _sugerencias = s);
});

// 2 · SOLO al elegir una, se paga la segunda petición
final lugar = await maps.places.getPlace(sugerencia.placeId!);
await controlador.animateCamera(
  CameraUpdate.newLatLngZoom(lugar.position!, 16),
);
```

### Filtrar antes de pagar la matriz

```dart
// Gratis: aritmética local
final cercanos = unidades
  ..sort((a, b) => a.distanceTo(aviso).compareTo(b.distanceTo(aviso)));

// 3 unidades en vez de 20
final matriz = await maps.routes.calculateRouteMatrix(
  origins: cercanos.take(3).toList(),
  destinations: [aviso],
);
```

### Mover marcadores sin duplicarlos

```dart
// copyWith CONSERVA el markerId → el marcador se mueve.
// Crear uno nuevo con otro id deja el anterior clavado en el mapa.
await controlador.addMarkers([
  for (final m in controlador.markers)
    m.copyWith(position: nuevaPosicion(m), rotation: nuevoRumbo(m)),
]);
```

### Avisar ANTES de que un vehículo salga de la zona

```dart
final aviso = await maps.geofencing.forecastGeofenceEvents(
  collectionName: 'zonas-permitidas',
  position: ultimaPosicion,
  speedKmh: velocidadActual,             // SIN ESTO no predice nada
  timeHorizon: const Duration(minutes: 10),
);

// `breaches` deja fuera los IDLE, que dicen «sigue donde estaba».
for (final e in aviso.breaches) {
  alertar('${e.eventType.name} ${e.geofenceId} en '
          '${e.timeUntilBreach?.inMinutes} min');
}
```

### Comprobar una zona sin gastar una petición

```dart
// Local y gratis. Para pintar el estado en la interfaz.
final zona = GeofenceGeometry.circle(center: bodega, radiusMeters: 500);
if (zona.contains(posicionDelVehiculo)) { ... }

// La evaluación OFICIAL —la que dispara eventos— es otra cosa:
await maps.geofencing.batchEvaluateGeofences(
  collectionName: 'zonas',
  positions: [DevicePositionUpdate(
    deviceId: imei, position: p, sampleTime: horaDelGps)],
);
// ↑ Devuelve solo errores. Los eventos llegan por EventBridge.
```

### Día y noche

```dart
final estilos = maps.maps.dayNightStyleUrls(MapStyle.standard);
CompassMap(
  styleUrl: esDeNoche ? estilos.dark! : estilos.light!,
  // Cambiar esta cadena recarga el estilo y reinstala las superposiciones solo.
  ...
);
```

### Isócrona pintada

```dart
final r = await maps.routes.calculateIsolines(
  origin: ultimaPosicion,
  thresholds: Thresholds.time([const Duration(minutes: 8)]),
  travelMode: TravelMode.scooter,
);
await controlador.addPolygon(
  Polygon.fromIsoline(r.isolines.first, polygonId: const PolygonId('zona')),
);
// ⚠️ Si la isócrona trae varios polígonos (un río sin puentes), recorre
// `isolines.first.polygons` y crea uno por cada uno. Aplanarlos une las dos
// orillas con una recta sobre el agua.
```

---

## 6 · Antipatrones que producen fallos silenciosos

```dart
// ❌ Pedir en cada movimiento de cámara → decenas de peticiones por gesto
onCameraMove: (p) => maps.places.searchNearby(position: p.target),
// ✅
onCameraIdle: () => _buscarEnLaVistaActual(),

// ❌ Un cliente por pantalla → cada uno con sus cachías vacías
Widget build(_) { final maps = CompassMaps(...); }
// ✅ uno compartido en toda la app

// ❌ La celda con error trae ceros, y un cero parece «lo más cerca»
final mejor = matriz.cell(i, 0).duration;
// ✅
if (matriz.cell(i, 0).isValid) { ... }

// ❌ `locality` es la ciudad entera, a kilómetros del punto
final direccion = lugares.first.formattedAddress;
// ✅
if (lugares.first.placeType?.isPrecise ?? false) { ... }

// ❌ Sin granularidad, 30 min = miles de vértices y la interfaz se congela
calculateIsolines(origin: p, thresholds: Thresholds.time([Duration(minutes: 30)]),
                  granularity: const IsolineGranularity());
// ✅ deja el valor por defecto, que ya trae maxPoints: 300

// ❌ La URL lleva la clave dentro
logger.info('estilo: ${maps.maps.styleDescriptorUrl(MapStyle.standard)}');
// ✅ nunca registres esa URL
```

---

## 7 · Nombres exactos de los enums

```dart
TravelMode      .car .truck .pedestrian .scooter        // NO .motorcycle
MapStyle        .standard .monochrome .hybrid .satellite
MapColorScheme  .light .dark
IntendedUse     .singleUse .storage
PlaceType       .country .region .subRegion .locality .district .subDistrict
                .postalCode .block .subBlock .intersection .street
                .pointAddress .interpolatedAddress .pointOfInterest
PlaceFeature    .core .contact .timeZone .access .phonemes
                .secondaryAddresses .intersections
RouteFeature    .elevation .incidents .passThroughWaypoints .summary
                .tollSystems .tolls .travelStepInstructions .truckRoadTypes
                .typicalDuration .zones
MapTraffic      .all .congestion
MapTerrain      .hillshade .terrain3d
MapBuildings    .buildings3d
MapPoiDensity   .off .verySparse .sparse .standard .dense .veryDense
AlsService      .places .routes .maps               // firman geo-places/-routes/-maps
                .geofencing .geofencingControl      // firman `geo` a secas
                .tracking .trackingControl          // los `*Control` usan cp.
PositionFiltering .timeBased .distanceBased .accuracyBased
ForecastedEventType .enter .exit .idle
Cap             .buttCap .roundCap .squareCap
JointType       .mitered .round .bevel
```

---

## 8 · Antes de dar por buena la integración

1. `dart run melos run verify` en la raíz → formato, análisis y las 186 pruebas.
2. Android: AGP **8.x** (no 9.x) y **JDK 21**. Ver «Limitaciones conocidas» en
   el README.
3. La atribución tiene que verse. `attributionEnabled: false` sin enseñarla en
   otro sitio puede incumplir las condiciones del proveedor de datos.
4. Para mapas sin conexión: leer la **Sección 82 de los AWS Service Terms**
   antes de enviar la app.
