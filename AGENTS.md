# AGENTS.md — cómo usar `nativ_maps` sin leer el código fuente

Este archivo está escrito para **agentes de IA** que tengan que escribir código
contra este paquete. Es denso a propósito: todo lo que hace falta para acertar a
la primera, sin abrir ningún `.dart`.

Si eres una persona, [README.md](README.md) es más agradable y
[doc/RECETAS.md](doc/RECETAS.md) tiene los ejemplos completos.

---

## 0 · Lo mínimo

```yaml
dependencies:
  # Lo único que está en pub.dev. Trae el widget y las 44 operaciones.
  nativ_maps_flutter: ^0.4.0

  # Los otros dos NO se publican: se consumen por git, con una ETIQUETA y
  # nunca con una rama. Añádelos solo si los necesitas.
  nativ_maps_sigv4:      # SOLO si usas geovallas o rastreo (exigen SigV4)
    git:
      url: https://github.com/delioribas/nativ_maps.git
      path: packages/nativ_maps_sigv4
      ref: v0.4.0
  nativ_maps_google:     # SOLO si migras de google_maps_flutter
    git:
      url: https://github.com/delioribas/nativ_maps.git
      path: packages/nativ_maps_google
      ref: v0.4.0
```

```dart
import 'package:nativ_maps_flutter/nativ_maps_flutter.dart';
```

**Un solo import.** `nativ_maps_flutter` reexporta el núcleo entero. Nunca
importes `package:nativ_maps/nativ_maps.dart` en una app Flutter: no hace
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
| 12 | **Geovallas y rastreo NO aceptan clave de API** | Se corta antes de enviar. Hacen falta `ProxyCredentials` o `nativ_maps_sigv4` |
| 13 | `batchEvaluateGeofences` **devuelve vacío a propósito** | Los eventos salen por **EventBridge**, no por la respuesta. Para saberlo ahora, `GeofenceGeometry.contains` (local, gratis) |
| 14 | Mira `BatchResult.errors` siempre | Estas operaciones responden 200 aunque falle la mitad |
| 15 | En rastreo, `sampleTime` es **la hora del GPS** | La de envío desordena el histórico y engaña al filtrado del rastreador |

---

## 2 · Mapa de la API

### Punto de entrada

```dart
final maps = NativMaps(
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
`NativMapsConfigurationException` **antes de enviar**.

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

### La capa de cálculo — firmas exactas

**Dart puro. Ninguna de estas llamadas usa la red ni gasta unidades**, salvo
`DispatchPlanner.rank`, que sí llama a la matriz.

```dart
// ── Lectura del GPS: el tipo de entrada de toda la capa
PositionFix({
  required LatLng position,
  required DateTime timestamp,
  double? accuracyMeters,      // el dato más valioso; pásalo siempre
  double? speedKmh,            // del receptor (Doppler), no calculada
  double? headingDegrees,
  double? altitudeMeters,
})

// ── Filtrar el ruido
PositionFilter({
  double maxAccuracyMeters = 50,
  double noiseFactor = 2.0,
  double minDisplacementMeters = 3,
  double maxSpeedKmh = 220,
  bool smooth = false,
  double processNoiseMps2 = 2.0,
})
FilterResult add(PositionFix fix)   // .accepted, .rejection, .distanceMeters
void reset()

enum FixRejection { poorAccuracy, outOfOrder, withinNoise, impossibleSpeed }

// ── Medir el viaje
TripRecorder({
  PositionFilter? filter,
  double stopSpeedKmh = 3,
  double resumeSpeedKmh = 8,        // > stopSpeedKmh o lanza
  Duration minStopDuration = const Duration(seconds: 45),
  bool keepTrack = true,
})
TripUpdate add(PositionFix fix)
TripSummary finish()
void reset()

// TripSummary: .distanceMeters .distanceKm .duration .movingDuration
//              .stoppedDuration .stops .track .maxSpeedKmh
//              .averageMovingSpeedKmh .rejections .acceptedFixes

// ── Tarificar. TODOS los importes en unidades menores (céntimos), int.
Tariff({
  required String currency,        // ISO 4217
  required int baseFare,
  int perKilometer = 0,
  int perMinute = 0,
  int waitingPerMinute = 0,
  Duration waitingGrace = Duration.zero,
  int minimumFare = 0,
  int minorUnitDigits = 2,         // 0 para CLP, JPY
  FareRounding rounding = FareRounding.none,
  List<TariffBand> bands = const <TariffBand>[],
  List<Surcharge> surcharges = const <Surcharge>[],
})
FareBreakdown quote(TripSummary trip, {
  double surgeMultiplier = 1.0,
  int tolls = 0,
  List<Surcharge> extraSurcharges = const <Surcharge>[],
})
FareBreakdown estimate({           // antes de empezar, desde una ruta
  required double distanceMeters,
  required Duration duration,
  DateTime? departure,
  double surgeMultiplier = 1.0,
  int tolls = 0,
})

TariffBand({
  required String name,
  required Duration startOfDay,
  required Duration endOfDay,      // < startOfDay ⇒ cruza la medianoche
  double multiplier = 1.0,
  Set<int> weekdays = const <int>{1,2,3,4,5,6,7},   // DateTime.monday = 1
})
Surcharge({required String name, required int amount, bool surgeable = false})

enum FareRounding { none, nearest5, nearest10, nearest50, nearestMajor,
                    upToMajor }

// FareBreakdown: .total .lines .formattedTotal .toReceipt() .currency

// ── Seguir una ruta ya calculada
RouteTracker(Route route, {
  double offRouteThresholdMeters = 45,
  int offRouteStrikes = 3,
  int searchWindowSegments = 60,
})
RouteProgress update(LatLng position, {DateTime? now})
void resync()                      // tras una pausa larga sin posiciones

// RouteProgress: .remainingMeters .remainingDuration .eta .offRoute
//                .fraction .deviationMeters .currentStep .nextStep
//                .distanceToNextManeuverMeters .stepIndex

// ── Subasta de carreras (modelo inDrive)
RideRequest({
  required String id, required LatLng pickup, required LatLng dropoff,
  required int proposedFare, required String currency,
  required DateTime createdAt,
  double? estimatedDistanceMeters, Duration? estimatedDuration,
  int passengerCount = 1, String note = '', Set<String> tags = const {},
})
DriverBid({
  required String driverId, required String requestId, required int amount,
  required Duration etaToPickup, required DateTime createdAt,
  Duration validFor = const Duration(minutes: 2),
  double? driverRating, int? completedTrips, String vehicleLabel = '',
})
RideAuction({required RideRequest request,
             Duration duration = const Duration(minutes: 5)})
void bid(DriverBid offer, {DateTime? now})     // sustituye la del mismo id
bool withdraw(String driverId)
DriverBid accept(String driverId, {DateTime? now})   // lanza si caducó
void cancel()
List<DriverBid> liveBids(DateTime now)
AuctionState stateAt(DateTime now)

BidRanking({double priceWeight = 1, double etaWeight = 1,
            double ratingWeight = 0.5})
List<DriverBid> sort(List<DriverBid> bids, {DateTime? now})

// ── ¿Le compensa al conductor?
DriverEconomics({
  required int costPerKilometer,   // combustible + desgaste, NO solo gasolina
  double commissionRate = 0,
  int minimumNetPerHour = 0,
  double returnFactor = 0.0,
})
BidAdvisor({required DriverEconomics economics,
            required int minorUnitDigits, required String currency})
BidEvaluation evaluate({
  required int fare,
  required double deadheadMeters, required Duration deadheadDuration,
  required double tripMeters, required Duration tripDuration,
})
int breakEvenFare({...los mismos cuatro...})   // qué contraofertar

// BidEvaluation: .net .netPerHour .worthIt .drivingCost .commission
//                .deadheadShare .engagedDuration

// ── Precio sugerido al pasajero
FareAdvisor({required Tariff tariff, double minimumRatio = 0.80,
             double maximumRatio = 1.40, double midpointRatio = 0.95,
             double steepness = 9.0})
FareSuggestion suggest({required double distanceMeters,
  required Duration duration, DateTime? departure,
  double demandFactor = 1.0, int tolls = 0})
double acceptanceProbability({required int offered, required int reference,
                              double demandFactor = 1.0})

// ── Precio sugerido (modelo de puja, forma de inDrive)
MarketConditions({
  int availableDrivers = 0,
  int openRequests = 0,
  List<DemandSignal> signals = const <DemandSignal>[],
  double returnEmptyProbability = 0,   // 0..1, vuelta de vacío
  double congestionFactor = 1.0,       // duración con tráfico / sin tráfico
})
DemandSignal({required String name, required double multiplier})
// constantes listas: DemandSignal.rain (1.15), .event (1.30), .noTransit (1.20)

PriceAdvisor({
  required Tariff tariff,
  required DriverEconomics economics,
  double surgeExponent = 0.6,      // multiplicador = ratio ^ este exponente
  double maxSurge = 2.5,
  double minimumRatio = 0.85,      // solo si no hay conductores
  double pickupAversion = 1.6,     // el tiempo muerto pesa más
  double targetAcceptance = 0.5,
  double fastMargin = 1.08,
  double fallbackSteepness = 9.0,  // ← inventado; calíbralo
  double detourFactor = 1.4,
  double urbanSpeedKmh = 24,
})
SuggestedPrice suggest({
  required double distanceMeters,
  required Duration duration,
  List<DriverCandidate> nearbyDrivers = const <DriverCandidate>[],
  MarketConditions market = const MarketConditions(),
  DateTime? departure,
  int tolls = 0,      // NO entra en el precio, se informa aparte
  int fees = 0,
})
AcceptanceForecast forecast({    // para el deslizador del precio
  required int offered,
  required double distanceMeters,
  required Duration duration,
  List<DriverCandidate> nearbyDrivers = const <DriverCandidate>[],
  int? reference,
})

// SuggestedPrice: .minimum .recommended .fast .reference
//                 .extrasPaidSeparately .demandMultiplier .factors
//                 .forecast .explain() .formatAmount()
// AcceptanceForecast: .probability .driversLikelyToAccept
//                     .driversConsidered .expectedPickup .estimated

// ── Ajustar la tarifa a precios reales de tu ciudad
FareSample({
  required double distanceMeters,   // de calculateRoutes, NO de la otra app
  required Duration duration,
  required int observedFare,        // SIN peajes ni tasas
  String label = '',
})
TariffFit TariffCalibration.fit(List<FareSample> samples,
    {bool includeTimeComponent = true})

// TariffFit: .baseFare .perKilometer .perMinute .rSquared
//            .meanAbsoluteError .maxAbsoluteError .sampleCount
//            .distanceTimeCorrelation .splitIsReliable .isUsable
//            .toTariff(currency: ...) .predict(...) .report(samples)

// ── Elegir conductor.  shortlist es GRATIS; rank SÍ llama a la matriz.
DispatchPlanner({required RoutesClient routes, int shortlistSize = 12,
                 double maxRadiusMeters = 8000})
List<DriverCandidate> shortlist(List<DriverLocation> drivers, LatLng pickup,
    {Duration? staleAfter, DateTime? now})
Future<List<DriverCandidate>> rank(List<DriverCandidate> candidates,
    LatLng pickup, {TravelMode travelMode = TravelMode.car,
    DateTime? departureTime})
Future<List<DriverCandidate>> findNearest(List<DriverLocation> drivers,
    LatLng pickup, {Duration? staleAfter,
    TravelMode travelMode = TravelMode.car, DateTime? now})

// ── Telemática
TelemetryAnalyzer({
  double harshAccelerationMps2 = 3.0,
  double harshBrakingMps2 = -3.5,
  double harshCorneringMps2 = 3.5,
  double? speedLimitKmh,           // el paquete NO lo averigua
  double speedToleranceKmh = 8,
  Duration minSpeedingDuration = const Duration(seconds: 10),
  Duration maxSampleGap = const Duration(seconds: 10),
})
List<DrivingEvent> add(PositionFix fix)
DrivingScore score({double harshWeight = 4, double corneringWeight = 2,
                    double speedingWeight = 6})
void reset()

// ── Geometría de caminos
double pathLength(List<LatLng> path)
List<double> cumulativeDistances(List<LatLng> path)
double crossTrackMeters(LatLng point, LatLng start, LatLng end)
PathMatch nearestPointOnPath(List<LatLng> path, LatLng point,
    {int fromIndex = 0, int? maxSegments, List<double>? cumulative})
LatLng interpolateOnPath(List<LatLng> path, double alongMeters,
    {List<double>? cumulative})
List<LatLng> simplifyPath(List<LatLng> path, {required double toleranceMeters})
```

### `NativMapController` — lo que se usa de verdad

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
NativOfflineManager? get offline;   // null si offlineEnabled: false
StyleEditor get style;                // retocar capas en caliente

// Estilo y capturas
Future<void> setMapStyle(String styleUrl);
Future<void> setCustomHeaders(Map<String, String> h, {List<String> urlFilter});
Future<Uint8List> takeSnapshot({int? width, int? height});
Future<void> clearTileCache();
```

### El widget

```dart
NativMap(
  styleUrl: ...,                        // requerido
  initialCameraPosition: ...,           // requerido, SOLO al crear
  onMapCreated: (NativMapController c) {},
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
| `GoogleMapController` | `NativMapController` | — |
| `MapType.terrain` | `MapStyle.standard` + `terrain:` | Aquí el relieve es un parámetro, no un estilo cerrado |
| `setMapStyle(json)` (Google JSON) | `setGoogleMapStyle(json)` en `nativ_maps_google` | Traducción **aproximada**, con informe |
| `tilt` | `tilt` (MapLibre lo llama *pitch*) | Se mantiene el nombre de Google |

**Con `nativ_maps_google` importado, `animateCamera`, `moveCamera`,
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
} on NativMapsConfigurationException {
  // Falta la clave. Se lanza ANTES de enviar
} on AlsParseException {
  // 200 pero la forma cambió. No reintentes: mira el cuerpo real
}
```

`NativMapsException` es la raíz **sellada** de las cinco. Capturarla atrapa
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

### Cobrar una carrera de principio a fin

```dart
final registrador = TripRecorder();
final tarifa = Tariff(currency: 'USD', baseFare: 250, perKilometer: 110,
    perMinute: 35, waitingPerMinute: 30,
    waitingGrace: const Duration(minutes: 3), minimumFare: 500);

suscripcion = flujoDelGps.listen((posicion) {
  final estado = registrador.add(PositionFix(
    position: LatLng(posicion.latitude, posicion.longitude),
    timestamp: posicion.timestamp,
    accuracyMeters: posicion.accuracy,   // ← imprescindible
    speedKmh: posicion.speed * 3.6,      // ← del receptor
  ));
  mostrarEnPantalla(estado.distanceMeters, estado.speedKmh);
});

// Al terminar:
final viaje = registrador.finish();
final importe = tarifa.quote(viaje, tolls: ruta.tollCostByCurrency['USD']
    ?.round() ?? 0);
guardar(viaje, importe.lines);   // guarda el DESGLOSE, no solo el total
```

### Sugerirle un precio al pasajero

```dart
// 1 · La ruta da distancia, duración CON TRÁFICO y peajes.
final ruta = (await maps.routes.calculateRoutes(
  origin: recogida, destination: destino,
)).best!;

// 2 · La matriz da el tiempo REAL de recogida de cada conductor.
final cercanos = await planificador.findNearest(conectados, recogida);

// 3 · Y con eso sale el precio.
final precio = asesor.suggest(
  distanceMeters: ruta.distanceMeters,
  duration: ruta.duration,
  nearbyDrivers: cercanos,
  market: MarketConditions(
    availableDrivers: cercanos.length,
    openRequests: peticionesSinAsignar,
    signals: <DemandSignal>[if (llueve) DemandSignal.rain],
  ),
  tolls: ruta.tollCostByCurrency['USD']?.round() ?? 0,
);

deslizador
  ..min = precio.minimum
  ..value = precio.recommended;

// Al mover el deslizador, sin ninguna petición:
final f = asesor.forecast(
  offered: loQueMarcaElDeslizador,
  distanceMeters: ruta.distanceMeters,
  duration: ruta.duration,
  nearbyDrivers: cercanos,
);
etiqueta.text = f.estimated
    ? 'Precio orientativo'
    : '${f.driversLikelyToAccept} de ${f.driversConsidered} conductores';
```

### Decidir si aceptar una carrera (conductor)

```dart
const asesor = BidAdvisor(currency: 'USD', minorUnitDigits: 2,
  economics: DriverEconomics(costPerKilometer: 20, commissionRate: 0.20,
      minimumNetPerHour: 1500));

final analisis = asesor.evaluate(
  fare: peticion.proposedFare,
  deadheadMeters: hastaRecoger.distanceMeters,
  deadheadDuration: hastaRecoger.duration,
  tripMeters: elTrayecto.distanceMeters,
  tripDuration: elTrayecto.duration,
);

if (analisis.worthIt) {
  aceptar();
} else {
  contraofertar(asesor.breakEvenFare(/* los mismos cuatro */));
}
```

### Ofrecer la carrera a quien llegue antes de verdad

```dart
final planificador = DispatchPlanner(routes: maps.routes);
final finalistas = await planificador.findNearest(
  conductoresConectados, peticion.pickup,
  staleAfter: const Duration(minutes: 2),   // descarta posiciones viejas
);
for (final c in finalistas.take(5)) {
  notificar(c.driver.driverId, llegaEn: c.drivingDuration!);
}
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
NativMap(
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
Widget build(_) { final maps = NativMaps(...); }
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

### Sumar la distancia entre lecturas del GPS

```dart
// ❌ Un coche aparcado acumula kilómetros: el receptor rebota dentro de su
//    círculo de incertidumbre, y el pasajero paga ese rebote.
for (var i = 1; i < posiciones.length; i++) {
  total += posiciones[i - 1].distanceTo(posiciones[i]);
}

// ✅
final registrador = TripRecorder();
for (final p in lecturas) registrador.add(p);
final total = registrador.finish().distanceMeters;
```

### Pasar `PositionFix` sin `accuracyMeters`

```dart
// ❌ Sin la incertidumbre no hay forma de distinguir avance lento de rebote,
//    y el filtro solo puede aplicar el suelo absoluto de 3 m.
PositionFix(position: p, timestamp: t)

// ✅
PositionFix(position: p, timestamp: t, accuracyMeters: lectura.accuracy,
    speedKmh: lectura.speed * 3.6)
```

### Guardar solo el total de la carrera

```dart
// ❌ Seis meses después llega la reclamación y no hay cómo justificarlo.
guardar(importe.total);

// ✅ El desglose trae la cuenta de cada línea: «12,40 km × 1,10».
guardar(importe.total, importe.lines);
```

### Usar `double` para el dinero

```dart
// ❌ 0,10 no existe en coma flotante binaria; la caja descuadra a fin de mes.
double tarifa = 1.10;

// ✅ Unidades menores, enteras. El redondeo ocurre una vez, al final.
const perKilometer = 110;   // céntimos
```

### Ordenar conductores por distancia en línea recta

```dart
// ❌ El que está a 300 m al otro lado del río tarda quince minutos.
conductores.sort((a, b) => a.position.distanceTo(punto)
    .compareTo(b.position.distanceTo(punto)));

// ✅ Gratis primero, matriz solo para los finalistas.
final mejores = await planificador.findNearest(conductores, punto);
```

### Recalcular la ruta al primer punto que se salga

```dart
// ❌ Una lectura mala coloca el coche a 80 m de su carril. En una calle
//    estrecha pasa varias veces por minuto, y cada recálculo se factura.
if (posicion.distanceTo(ruta.points.first) > 50) await recalcular();

// ✅ RouteTracker exige varias lecturas seguidas antes de darlo por bueno.
final progreso = seguimiento.update(posicion);
if (progreso.offRoute) await recalcular();
```

### Recortar el rastro antes de medirlo

```dart
// ❌ Douglas–Peucker quita justo los puntos de las curvas suaves: la
//    distancia siempre sale menor, y se cobra de menos.
final total = pathLength(simplifyPath(rastro, toleranceMeters: 5));

// ✅ Primero se mide, después se recorta para guardar.
final total = registrador.finish().distanceMeters;
final paraGuardar = simplifyPath(viaje.track, toleranceMeters: 5);
```

### Enseñar `acceptanceProbability` como si fuera un dato

```dart
// ❌ «87 % de probabilidad» con dos decimales: nadie lo vuelve a cuestionar.
Text('${(p * 100).toStringAsFixed(1)} % de aceptación');

// ✅ Es una curva calibrable, no una medición. Enséñala como orientación
//    cualitativa hasta que la ajustes con tu propio historial.
Text(p > 0.6 ? 'Buen precio' : 'Puede que nadie conteste');
```

### Enseñar la probabilidad de aceptación cuando es una estimación

```dart
// ❌ `estimated: true` significa que detrás hay una curva sin calibrar o
//    tiempos en línea recta. Un porcentaje con decimales ahí es mentira.
Text('${(f.probability * 100).toStringAsFixed(1)} % de aceptación');

// ✅
Text(f.estimated
    ? 'Precio orientativo'
    : '${f.driversLikelyToAccept} de ${f.driversConsidered} aceptarían');
```

### Meter los peajes dentro del precio sugerido

```dart
// ❌ El peaje no se negocia y no se lo lleva el conductor. Dentro del
//    precio, la puja se distorsiona y el conductor cree que gana más.
final ofrecer = precio.recommended + peajes;

// ✅ Van aparte, como en inDrive.
final ofrecer = precio.recommended;
final aparte = precio.extrasPaidSeparately;
```

### Calibrar la tarifa con muestras de hora punta

```dart
// ❌ La demanda se cuela DENTRO de los coeficientes, y luego MarketConditions
//    la vuelve a aplicar: se cobra dos veces.
// ✅ Toma las muestras en horas tranquilas. La demanda es una capa aparte.
```

### Fiarte del reparto km/minuto sin mirar la correlación

```dart
// ❌ En ciudad, kilómetros y minutos van de la mano. El ajuste predice bien
//    el total y el reparto entre los dos puede ser arbitrario.
final tarifa = ajuste.toTariff(currency: 'USD');

// ✅
if (!ajuste.splitIsReliable) {
  // Añade muestras que rompan la relación: un corto en atasco y un largo
  // por autopista a las seis de la mañana.
}
```

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
