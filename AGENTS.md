# AGENTS.md — cómo usar `nativ_maps` sin leer el código fuente

Este archivo está escrito para **agentes de IA** que tengan que escribir código
contra este paquete. Es denso a propósito: todo lo que hace falta para acertar a
la primera, sin abrir ningún `.dart`.

Si eres una persona, [README.md](README.md) es más agradable y
[doc/RECETAS.md](doc/RECETAS.md) tiene los ejemplos completos.

**¿Va a producción?** La clave de API no puede ir dentro de la app: lee la
[sección 9](#9--en-producción-la-clave-en-tu-servidor) antes de entregar nada.

---

## 0 · Lo mínimo

```yaml
dependencies:
  # The only one on pub.dev. Brings the widget and all 44 operations.
  nativ_maps_flutter: ^0.9.2

  # The other two are NOT published: consume them via git, pinned to a TAG and
  # never to a branch. Add them only if you need them.
  nativ_maps_sigv4:      # ONLY if you use geofencing or tracking (they require SigV4)
    git:
      url: https://github.com/delioribas/nativ_maps.git
      path: packages/nativ_maps_sigv4
      ref: v0.9.2
  nativ_maps_google:     # ONLY if you are migrating from google_maps_flutter
    git:
      url: https://github.com/delioribas/nativ_maps.git
      path: packages/nativ_maps_google
      ref: v0.9.2
```

```dart
import 'package:nativ_maps_flutter/nativ_maps_flutter.dart';
```

**Un solo import.** `nativ_maps_flutter` reexporta el núcleo entero. Nunca
importes `package:nativ_maps/nativ_maps.dart` en una app Flutter: no hace
falta y duplica los símbolos.

**`ApiKeyCredentials` es para desarrollar.** Una clave dentro de un APK se
extrae en minutos. En producción: `ProxyCredentials` y uno de los servidores
de `proxies/` —[sección 9](#9--en-producción-la-clave-en-tu-servidor)—.

---

## 1 · Las reglas duras

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
| 9 | `autocomplete` **solo completa direcciones** y no trae posición | Para «¿a dónde vas?» usa `suggest` con `PlaceFeature.core`: encuentra lugares (un centro comercial, el aeropuerto) y ya trae la posición. Con `autocomplete`, «Quicentro» da cero resultados |
| 10 | Comprueba `MatrixCell.isValid` antes de usar los números | Una celda con error trae **ceros**, y un cero parece «lo más cerca posible» |
| 11 | Comprueba `PlaceType.isPrecise` en `reverseGeocode` | Un `locality` significa «no encontré el portal, te doy la ciudad» — kilómetros de diferencia |
| 12 | **Geovallas y rastreo NO aceptan clave de API** | Se corta antes de enviar. Hacen falta `ProxyCredentials` o `nativ_maps_sigv4` |
| 13 | `batchEvaluateGeofences` **devuelve vacío a propósito** | Los eventos salen por **EventBridge**, no por la respuesta. Para saberlo ahora, `GeofenceGeometry.contains` (local, gratis) |
| 14 | Mira `BatchResult.errors` siempre | Estas operaciones responden 200 aunque falle la mitad |
| 15 | En rastreo, `sampleTime` es **la hora del GPS** | La de envío desordena el histórico y engaña al filtrado del rastreador |
| 16 | Cada operación de lugares admite **su** subconjunto de `PlaceFeature` | Fuera de su fila, `400`. La tabla, medida contra AWS, está en la documentación de `PlaceFeature`: `contact` no vale en `autocomplete`, `core` no vale en `searchText` |
| 17 | Las instrucciones escritas exigen `TravelStepType.standard` | Con `turnByTurn` —el valor por defecto— y `RouteFeature.travelStepInstructions`, AWS responde `400`; el paquete lo corta antes de enviar |
| 18 | A pie no hay peajes | `RouteFeature.tolls` con `TravelMode.pedestrian` lanza `ArgumentError` antes de enviar; AWS respondería `400` |
| 19 | Con `ProxyCredentials`, el `NativMap` lleva **`customHeaders` con el mismo token** | El motor de mapas pide el estilo y las teselas por su cuenta: sin el token, `401` y el mapa en blanco, sin excepción |
| 20 | El servidor del proxy **no se improvisa** | Tiene que validar el host, reescribir el estilo y quitar la clave de las URLs. Hay seis hechos en `proxies/` y el contrato en [doc/PROXY.md](doc/PROXY.md) |

---

## 2 · Mapa de la API

### Punto de entrada

```dart
final maps = NativMaps(
  region: 'us-east-1',                              // required
  credentials: const ApiKeyCredentials('api-key'),  // required
  language: 'es',                                   // optional, BCP 47
  politicalView: null,                              // optional, ISO 3166
  intendedUse: IntendedUse.singleUse,               // storage if you persist it
  budget: Budget(maxUnits: 500),                    // optional but recommended
);

// Production: the key stays on YOUR server. See doc/PROXY.md.
//   credentials: ProxyCredentials(
//     baseUrl: Uri.parse('https://api.example.com/geo'),
//     headers: {'Authorization': 'Bearer $token'},   // and the same in
//   ),                                               // NativMap.customHeaders

maps.places      // PlacesClient     · 7 operations · v2, accepts API key
maps.routes      // RoutesClient     · 5 operations · v2, accepts API key
maps.maps        // MapsClient       · 5 operations · v2, accepts API key
maps.geofencing  // GeofencingClient · 12 ops · ⚠️ REQUIRES SigV4
maps.tracking    // TrackingClient   · 15 ops · ⚠️ REQUIRES SigV4
maps.close();    // closes the HTTP client
```

### `maps.places` — firmas exactas

```dart
Future<List<AutocompleteSuggestion>> autocomplete({
  required String query,
  LatLng? biasPosition,
  SearchFilter? filter,
  int maxResults = 5,              // 1..20, THROWS if out of range
  PostalCodeMode? postalCodeMode,
  List<PlaceFeature> additionalFeatures = const [],
  String? language,
  bool useCache = true,
});

Future<PlaceSearchResponse> searchText({
  String? queryText,               // queryText OR queryId, not both
  String? queryId,
  LatLng? biasPosition,
  SearchFilter? filter,
  int maxResults = 10,             // 1..100
  List<PlaceFeature> additionalFeatures = const [],
  String? nextToken,               // pagination
  String? language,
  IntendedUse? intendedUse,
  bool useCache = true,
});

Future<List<Place>> reverseGeocode(
  LatLng position, {
  double? radiusMeters,            // SET IT. Without it, you get the nearest city
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
  String? queryText,                        // text OR components
  AddressComponents? queryComponents,
  LatLng? biasPosition,
  List<String> includeCountries = const [], // ISO alpha-3: 'ECU', not 'EC'
  int maxResults = 5,
  List<PlaceFeature> additionalFeatures = const [],
  String? language,
  IntendedUse? intendedUse,
});

Future<PlaceSearchResponse> searchNearby({
  required LatLng position,
  double? radiusMeters,            // SET IT
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
  List<PlaceFeature> additionalFeatures = const [],  // request `core` for the position
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
  DateTime? departureTime,                   // mutually exclusive with arrivalTime
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
  required List<LatLng> origins,        // ≤15 without routingBoundary
  required List<LatLng> destinations,   // ≤100 · cells ≤100
  TravelMode travelMode = TravelMode.car,
  TravelModeOptions? travelModeOptions,
  LatLngBounds? routingBoundary,        // pass it to go beyond the limits
  DateTime? departureTime,
  RouteAvoidance? avoid,
  TrafficUsage traffic = TrafficUsage.useTrafficData,
  RouteOptimization optimizeFor = RouteOptimization.fastestRoute,
});

Future<IsolineResponse> calculateIsolines({
  LatLng? origin,                       // origin XOR destination
  LatLng? destination,
  required Thresholds thresholds,       // ≤5 thresholds
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
  required List<TracePoint> tracePoints,   // ≥2 · auto-chunked if >5000
  double? snapRadiusMeters,                // 0..10000 · use ~500 in cities
  TravelMode travelMode = TravelMode.car,
  TravelModeOptions? travelModeOptions,
  GeometryFormat geometryFormat = GeometryFormat.simple,
  int overlapPoints = 10,                  // overlap between chunks
});

Future<WaypointOptimizationResponse> optimizeWaypoints({
  required LatLng origin,
  required List<OptimizationWaypoint> waypoints,   // UNIQUE ids
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
String? styleDescriptorUrl(          // returns null if there are no credentials
  MapStyle style, {                  // standard | monochrome | hybrid | satellite
  MapColorScheme? colorScheme,       // light | dark  ← rendered by the server
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

Future<AlsBytes> staticMap({         // the image bytes (PNG; see .contentType)
  LatLng? center, double? zoom,      // center+(zoom XOR radiusMeters) XOR
  LatLngBounds? boundingBox,         // boundingBox XOR boundedPositions
  List<LatLng> boundedPositions = const [],
  double? radiusMeters,
  required int width,                // 64..1400, THROWS if out of range
  required int height,               // 64..1400
  MapStyle style = MapStyle.standard,  // ONLY standard | satellite
  MapColorScheme? colorScheme,
  String? geoJsonOverlay,            // geometry drawn on top
  ...
});

String? staticMapUrl({...});         // ⚠️ the URL CONTAINS THE KEY: do not log it

// Only for a custom renderer: the style descriptor already includes them.
String? tileUrlTemplate(String tileset);   // literal {z}/{x}/{y}, with key
String? glyphsUrlTemplate();               // {fontstack}/{range}, no key
String? spritesUrl(MapStyle style,         // WITHOUT extension: MapLibre appends
    {MapColorScheme colorScheme = MapColorScheme.light});  // .json/.png/@2x
```

### `maps.geofencing` — firmas exactas

⚠️ **Exige SigV4.** Con `ApiKeyCredentials` lanza
`NativMapsConfigurationException` **antes de enviar**. Con `ProxyCredentials`
funciona: firma el proxy, con credenciales IAM que tengan `geo:*` sobre la
colección (sección 9).

```dart
Future<Geofence> putGeofence({
  required String collectionName,
  required String geofenceId,
  required GeofenceGeometry geometry,     // .circle() .polygon() .multiPolygon()
  Map<String, String> properties = const {},  // ≤3, key ≤20, value ≤40
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

// Returns ONLY errors: ENTER/EXIT events go out through EventBridge.
Future<BatchResult> batchEvaluateGeofences({
  required String collectionName,
  required List<DevicePositionUpdate> positions,   // ≤10
});

// THE operation that justifies this family: warns BEFORE it happens.
Future<ForecastGeofenceEventsResponse> forecastGeofenceEvents({
  required String collectionName,
  required LatLng position,
  double? speedKmh,          // WITHOUT THIS it won't predict, only check containment
  Duration? timeHorizon,     // WITHOUT THIS either
  int? maxResults,
  String? nextToken,
});

// Control plane (host cp.geofencing.geo.…, resolved automatically)
Future<GeofenceCollection> createCollection({required String collectionName,
    String? description, String? kmsKeyId, Map<String, String> tags = const {}});
Future<GeofenceCollection> describeCollection(String collectionName);
Future<GeofenceCollection> updateCollection({required String collectionName,
    String? description});
Future<void> deleteCollection(String collectionName);   // deletes the geofences
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
// Automatically split into requests of 10.
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
  DateTime? from,        // default: last 24 h
  DateTime? to,
  int? maxResults,       // 1..100
  String? nextToken,
});

// "who is inside this polygon right now"
Future<TrackingPage<DevicePosition>> listDevicePositions({
  required String trackerName,
  List<LatLng>? filterGeometry,   // ≥3 points, closed automatically
  int? maxResults,
  String? nextToken,
});

Future<BatchResult> batchDeleteDevicePositionHistory({
  required String trackerName, required List<String> deviceIds});

// is my location being spoofed?
Future<PositionVerification> verifyDevicePosition({
  required String trackerName,
  required String deviceId,
  required LatLng position,
  required DateTime sampleTime,
  double? horizontalAccuracyMeters,
  String? ipv4Address,                       // WITHOUT THIS it can't infer much
  List<WiFiAccessPoint> wifiAccessPoints = const [],
});

// Control plane
Future<Tracker> createTracker({required String trackerName, String? description,
    PositionFiltering positionFiltering = PositionFiltering.distanceBased,
    bool? eventBridgeEnabled, String? kmsKeyId, Map<String, String> tags = const {}});
Future<Tracker> describeTracker(String trackerName);
Future<Tracker> updateTracker({required String trackerName, String? description,
    PositionFiltering? positionFiltering, bool? eventBridgeEnabled});
Future<void> deleteTracker(String trackerName);          // deletes the history
Future<TrackingPage<Tracker>> listTrackers({int? maxResults, String? nextToken});

// The link that makes geofences get evaluated ON THEIR OWN
Future<void> associateConsumer({required String trackerName,
                                required String collectionArn});  // the ARN
Future<void> disassociateConsumer({required String trackerName,
                                   required String collectionArn});
Future<TrackingPage<String>> listConsumers({required String trackerName,
    int? maxResults, String? nextToken});
```

**AWS borra el histórico a los 30 días.** No es configurable.

### La capa de cálculo — firmas exactas

**Dart puro. Ninguna de estas llamadas usa la red ni gasta unidades**, salvo
`DispatchPlanner.rank`, que sí llama a la matriz.

⚠️ **Toda esta capa es `@experimental`**: queda **fuera de la promesa de
estabilidad de la 1.0** y puede cambiar en una versión menor. Nadie ha cobrado
todavía carreras reales con ella; cuando se haya calibrado con uso de verdad,
se congelará.

```dart
// ── GPS reading: the input type for the whole layer
PositionFix({
  required LatLng position,
  required DateTime timestamp,
  double? accuracyMeters,      // the most valuable field; always pass it
  double? speedKmh,            // from the receiver (Doppler), not computed
  double? headingDegrees,
  double? altitudeMeters,
})

// ── Filter out the noise
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

// ── Measure the trip
TripRecorder({
  PositionFilter? filter,
  double stopSpeedKmh = 3,
  double resumeSpeedKmh = 8,        // > stopSpeedKmh or it throws
  Duration minStopDuration = const Duration(seconds: 45),
  bool keepTrack = true,
})
TripUpdate add(PositionFix fix)
TripSummary finish()
void reset()

// TripSummary: .distanceMeters .distanceKm .duration .movingDuration
//              .stoppedDuration .stops .track .maxSpeedKmh
//              .averageMovingSpeedKmh .rejections .acceptedFixes

// ── Pricing. ALL amounts in minor units (cents), int.
Tariff({
  required String currency,        // ISO 4217
  required int baseFare,
  int perKilometer = 0,
  int perMinute = 0,
  int waitingPerMinute = 0,
  Duration waitingGrace = Duration.zero,
  int minimumFare = 0,
  int minorUnitDigits = 2,         // 0 for CLP, JPY
  FareRounding rounding = FareRounding.none,
  List<TariffBand> bands = const <TariffBand>[],
  List<Surcharge> surcharges = const <Surcharge>[],
})
FareBreakdown quote(TripSummary trip, {
  double surgeMultiplier = 1.0,
  int tolls = 0,
  List<Surcharge> extraSurcharges = const <Surcharge>[],
})
FareBreakdown estimate({           // before starting, from a route
  required double distanceMeters,
  required Duration duration,
  DateTime? departure,
  double surgeMultiplier = 1.0,
  int tolls = 0,
})

TariffBand({
  required String name,
  required Duration startOfDay,
  required Duration endOfDay,      // < startOfDay ⇒ crosses midnight
  double multiplier = 1.0,
  Set<int> weekdays = const <int>{1,2,3,4,5,6,7},   // DateTime.monday = 1
})
Surcharge({required String name, required int amount, bool surgeable = false})

enum FareRounding { none, nearest5, nearest10, nearest50, nearestMajor,
                    upToMajor }

// FareBreakdown: .total .lines .formattedTotal .toReceipt() .currency

// ── Follow an already calculated route
RouteTracker(Route route, {
  double offRouteThresholdMeters = 45,
  int offRouteStrikes = 3,
  int searchWindowSegments = 60,
})
RouteProgress update(LatLng position, {DateTime? now})
void resync()                      // after a long gap without positions

// RouteProgress: .remainingMeters .remainingDuration .eta .offRoute
//                .fraction .deviationMeters .currentStep .nextStep
//                .distanceToNextManeuverMeters .stepIndex

// ── Ride auction (inDrive model)
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
void bid(DriverBid offer, {DateTime? now})     // replaces the one with the same id
bool withdraw(String driverId)
DriverBid accept(String driverId, {DateTime? now})   // throws if it expired
void cancel()
List<DriverBid> liveBids(DateTime now)
AuctionState stateAt(DateTime now)

BidRanking({double priceWeight = 1, double etaWeight = 1,
            double ratingWeight = 0.5})
List<DriverBid> sort(List<DriverBid> bids, {DateTime? now})

// ── Is it worth it for the driver?
DriverEconomics({
  required int costPerKilometer,   // fuel + wear, NOT just gas
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
int breakEvenFare({...the same four...})   // what to counter-offer

// BidEvaluation: .net .netPerHour .worthIt .drivingCost .commission
//                .deadheadShare .engagedDuration

// ── Suggested price (bidding model, inDrive-style)
MarketConditions({
  int availableDrivers = 0,
  int openRequests = 0,
  List<DemandSignal> signals = const <DemandSignal>[],
  double returnEmptyProbability = 0,   // 0..1, coming back empty
  double congestionFactor = 1.0,       // duration with traffic / without traffic
})
DemandSignal({required String name, required double multiplier})
// ready-made constants: DemandSignal.rain (1.15), .event (1.30), .noTransit (1.20)

PriceAdvisor({
  required Tariff tariff,
  required DriverEconomics economics,
  double surgeExponent = 0.6,      // multiplier = ratio ^ this exponent
  double maxSurge = 2.5,
  double minimumRatio = 0.85,      // only if there are no drivers
  double pickupAversion = 1.6,     // deadhead time weighs more
  double targetAcceptance = 0.5,
  double fastMargin = 1.08,
  double fallbackSteepness = 9.0,  // ← made up; calibrate it
  double detourFactor = 1.4,
  double urbanSpeedKmh = 24,
})
SuggestedPrice suggest({
  required double distanceMeters,
  required Duration duration,
  List<DriverCandidate> nearbyDrivers = const <DriverCandidate>[],
  MarketConditions market = const MarketConditions(),
  DateTime? departure,
  int tolls = 0,      // NOT part of the price, reported separately
  int fees = 0,
})
AcceptanceForecast forecast({    // for the price slider
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

// ── Fit the tariff to real prices in your city
FareSample({
  required double distanceMeters,   // from calculateRoutes, NOT from the other app
  required Duration duration,
  required int observedFare,        // WITHOUT tolls or fees
  String label = '',
})
TariffFit TariffCalibration.fit(List<FareSample> samples,
    {bool includeTimeComponent = true})

// TariffFit: .baseFare .perKilometer .perMinute .rSquared
//            .meanAbsoluteError .maxAbsoluteError .sampleCount
//            .distanceTimeCorrelation .splitIsReliable .isUsable
//            .toTariff(currency: ...) .predict(...) .report(samples)

// ── Choose a driver.  shortlist is FREE; rank DOES call the matrix.
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

// ── Telematics
TelemetryAnalyzer({
  double harshAccelerationMps2 = 3.0,
  double harshBrakingMps2 = -3.5,
  double harshCorneringMps2 = 3.5,
  double? speedLimitKmh,           // the package does NOT look it up
  double speedToleranceKmh = 8,
  Duration minSpeedingDuration = const Duration(seconds: 10),
  Duration maxSampleGap = const Duration(seconds: 10),
})
List<DrivingEvent> add(PositionFix fix)
DrivingScore score({double harshWeight = 4, double corneringWeight = 2,
                    double speedingWeight = 6})
void reset()

// ── Path geometry
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
// Camera — names identical to google_maps_flutter
Future<void> animateCamera(CameraUpdate update, {Duration? duration});
Future<void> moveCamera(CameraUpdate update);
Future<CameraPosition?> getCameraPosition();   // null if the map is not ready
Future<LatLngBounds> getVisibleRegion();
Future<double> getZoomLevel();
Future<Offset> getScreenCoordinate(LatLng latLng);   // Flutter LOGICAL pixels,
Future<LatLng> getLatLng(Offset screenCoordinate);   // on Android AND iOS
Future<double> getMetersPerPixel(double latitude);

// Markers. Marker(draggable: true, onDragStart:, onDrag:, onDragEnd:) drags
// with the finger instead of panning; the controller keeps the new position.
Future<void> addMarker(Marker m);
Future<void> addMarkers(Iterable<Marker> ms);   // USE THIS for more than a handful
Future<void> updateMarker(Marker m);
Future<void> removeMarker(MarkerId id);
Future<void> setMarkers(Iterable<Marker> ms);   // leaves EXACTLY that set
Future<void> clearMarkers();
List<Marker> get markers;

// Same for polylines / polygons / circles / ground overlays / tile overlays:
//   addX · removeX(XId) · setXs(Iterable) · clearXs · get xs
// Ground and tile overlays are drawn UNDER the package's areas, lines and
// markers. GroundOverlay.imageUrl takes https or data:. AWS's own tiles are
// 512 px: TileOverlay(tileSize: 512).

// What Google doesn't have
Future<void> addHeatmap(Heatmap h);
Future<void> removeHeatmap(HeatmapId id);
Future<void> addClusterManager(ClusterManager m);   // BEFORE the markers
Future<double> getClusterExpansionZoom(Cluster c);
NativOfflineManager? get offline;   // null if offlineEnabled: false
StyleEditor get style;                // tweak layers at runtime

// Style and snapshots
Future<void> setMapStyle(String styleUrl);
Future<void> setCustomHeaders(Map<String, String> h, {List<String> urlFilter});
Future<Uint8List> takeSnapshot({int? width, int? height});
Future<void> clearTileCache();
```

### El widget

```dart
NativMap(
  styleUrl: ...,                        // required
  initialCameraPosition: ...,           // required, ONLY at creation
  onMapCreated: (NativMapController c) {},
  onStyleLoaded: () {},                 // on EVERY load, not just the first
  onStyleError: (Object e) {},          // HOOK IT UP
  onTap: (LatLng p) {},
  onLongPress: (LatLng p) {},
  onMarkerTap: (Marker m) {},           // takes priority over onTap
  onClusterTap: (Cluster c) {},         // without it, tapping a cluster expands it
  onPolylineTap: (Polyline p) {},
  onCameraMove: (CameraPosition p) {},  // debounced at 60 ms
  onCameraIdle: () {},                  // ← FETCH DATA HERE, not in onCameraMove.
                                        //   Fires once for the initial camera,
                                        //   then once per new resting place
  myLocationEnabled: false,
  myLocationTracking: MyLocationTracking.none,
  compassEnabled: true,
  zoomControlsEnabled: false,
  scaleBarEnabled: false,
  attributionEnabled: true,             // ⚠️ removing it may breach the terms
  rotateGesturesEnabled: true,
  scrollGesturesEnabled: true,
  zoomGesturesEnabled: true,
  tiltGesturesEnabled: true,
  minMaxZoomPreference: MinMaxZoomPreference.unbounded,
  cameraTargetBounds: null,
  offlineEnabled: false,                // true so that `offline` is not null
  customHeaders: null,                  // REQUIRED with a proxy (its token) or
                                        // SigV4; sent only to the style's host
                                        // and amazonaws.com
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
| El aspecto por defecto de Google | `applyGoogleLook()` en `nativ_maps_google`, dentro de `onStyleLoaded` | Paleta medida en la app de Google. Solo `MapStyle.standard` claro; tipografía, iconos y datos siguen siendo de AWS |
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
  e.isConfigurationError;   // true on 400 and 403 → do NOT retry
  e.isRetryable;            // true on 429 and 5xx
  e.hint;                   // ← READ THIS: the specific cause, spelled out
  e.requestId;              // the first thing AWS support asks for
} on BudgetExhaustedException catch (e) {
  e.requestedUnits;         // what the rejected operation requested
  e.resetsAt;               // when budget becomes available again
} on AlsTransportException {
  // No response was received → NOTHING has been billed
} on NativMapsConfigurationException {
  // Missing key. Thrown BEFORE sending
} on AlsParseException {
  // 200 but the shape changed. Don't retry: look at the actual body
}
```

`NativMapsException` es la raíz **sellada** de las cinco. Capturarla atrapa
todo lo del framework sin atrapar los errores de programación de tu app.

`ArgumentError` se lanza **antes de enviar** en los límites duros (matriz,
umbrales, `maxResults`, filtros excluyentes). No se ha gastado nada.

**Por un proxy**, los errores de AWS llegan tal cual —el mismo `statusCode`, el
mismo `hint`—, y además estos, que son del proxy:

| `statusCode` | Qué pasa |
|---|---|
| `401` | el token de la app no vale: sesión caducada. Renuévalo (sección 9) y reintenta **una** vez |
| `400` sin `requestId` | el proxy no sabe a dónde reenviar: paquete anterior a 0.9.1, o un proxy propio que no sigue el contrato |
| `500` | el servidor no tiene credenciales de AWS, o caducaron. No es culpa de la app |
| `502` | el proxy no llegó a AWS en 60 s. Reintentable |

Un error que trae `requestId` viene de AWS; uno sin él, del proxy.

---

## 5 · Patrones correctos

### Barra de búsqueda de destino

```dart
// 1 · on each keystroke, debounced at 300 ms.
//     `suggest`, NOT `autocomplete`: autocomplete only completes addresses,
//     so "Quicentro" or "Aeropuerto Mariscal Sucre" return zero results.
_debounce = Timer(const Duration(milliseconds: 300), () async {
  final r = await maps.places.suggest(
    query: text,
    biasPosition: currentPosition,                      // ranks
    filter: const SearchFilter(includeCountries: ['ECU']),  // filters out
    additionalFeatures: const [PlaceFeature.core],      // ← brings the position
  );
  setState(() => _suggestions = r.results);
});

// 2 · A place already has its position: picking it costs no extra request.
//     Only a query-type suggestion needs the second one.
final position = suggestion.place?.position ??
    (await maps.places.searchText(queryId: suggestion.queryId))
        .places.first.position!;
await controller.animateCamera(CameraUpdate.newLatLngZoom(position, 16));
```

`autocomplete` + `getPlace` sigue siendo lo adecuado para un formulario de
**dirección postal**, donde lo que se escribe es una calle y un número.

### Cobrar una carrera de principio a fin

```dart
final recorder = TripRecorder();
final tariff = Tariff(currency: 'USD', baseFare: 250, perKilometer: 110,
    perMinute: 35, waitingPerMinute: 30,
    waitingGrace: const Duration(minutes: 3), minimumFare: 500);

subscription = gpsStream.listen((position) {
  final update = recorder.add(PositionFix(
    position: LatLng(position.latitude, position.longitude),
    timestamp: position.timestamp,
    accuracyMeters: position.accuracy,   // ← essential
    speedKmh: position.speed * 3.6,      // ← from the receiver
  ));
  showOnScreen(update.distanceMeters, update.speedKmh);
});

// When finished:
final trip = recorder.finish();
// Tolls in cents: tollCostByCurrency gives dollars, and .round() on 0.40 gives 0.
final fare = tariff.quote(trip, tolls: route.tollCostInMinorUnits('USD'));
save(trip, fare.lines);   // save the BREAKDOWN, not just the total
```

### Sugerirle un precio al pasajero

```dart
// 1 · The route gives distance, duration WITH TRAFFIC, and tolls.
final route = (await maps.routes.calculateRoutes(
  origin: pickup, destination: destination,
)).best!;

// 2 · The matrix gives each driver's REAL pickup time.
final nearby = await planner.findNearest(onlineDrivers, pickup);

// 3 · And from that comes the price.
final price = advisor.suggest(
  distanceMeters: route.distanceMeters,
  duration: route.duration,
  nearbyDrivers: nearby,
  market: MarketConditions(
    availableDrivers: nearby.length,
    openRequests: unassignedRequests,
    signals: <DemandSignal>[if (isRaining) DemandSignal.rain],
  ),
  tolls: route.tollCostInMinorUnits('USD'),   // cents, not dollars
);

slider
  ..min = price.minimum
  ..value = price.recommended;

// When the slider moves, with no request at all:
final f = advisor.forecast(
  offered: sliderValue,
  distanceMeters: route.distanceMeters,
  duration: route.duration,
  nearbyDrivers: nearby,
);
label.text = f.estimated
    ? 'Approximate price'
    : '${f.driversLikelyToAccept} of ${f.driversConsidered} drivers';
```

### Decidir si aceptar una carrera (conductor)

```dart
const advisor = BidAdvisor(currency: 'USD', minorUnitDigits: 2,
  economics: DriverEconomics(costPerKilometer: 20, commissionRate: 0.20,
      minimumNetPerHour: 1500));

final evaluation = advisor.evaluate(
  fare: request.proposedFare,
  deadheadMeters: toPickup.distanceMeters,
  deadheadDuration: toPickup.duration,
  tripMeters: trip.distanceMeters,
  tripDuration: trip.duration,
);

if (evaluation.worthIt) {
  accept();
} else {
  counterOffer(advisor.breakEvenFare(/* the same four */));
}
```

### Ofrecer la carrera a quien llegue antes de verdad

```dart
final planner = DispatchPlanner(routes: maps.routes);
final finalists = await planner.findNearest(
  onlineDrivers, request.pickup,
  staleAfter: const Duration(minutes: 2),   // drops stale positions
);
for (final c in finalists.take(5)) {
  notify(c.driver.driverId, arrivesIn: c.drivingDuration!);
}
```

### Filtrar antes de pagar la matriz

```dart
// Free: local arithmetic
final nearby = vehicles
  ..sort((a, b) => a.distanceTo(incident).compareTo(b.distanceTo(incident)));

// 3 units instead of 20
final matrix = await maps.routes.calculateRouteMatrix(
  origins: nearby.take(3).toList(),
  destinations: [incident],
);
```

### Mover marcadores sin duplicarlos

```dart
// copyWith KEEPS the markerId → the marker moves.
// Creating a new one with another id leaves the old one stuck on the map.
await controller.addMarkers([
  for (final m in controller.markers)
    m.copyWith(position: newPosition(m), rotation: newHeading(m)),
]);
```

### Avisar ANTES de que un vehículo salga de la zona

```dart
final forecast = await maps.geofencing.forecastGeofenceEvents(
  collectionName: 'allowed-zones',
  position: lastPosition,
  speedKmh: currentSpeed,             // WITHOUT THIS it predicts nothing
  timeHorizon: const Duration(minutes: 10),
);

// `breaches` leaves out IDLE events, which say "still where it was".
for (final e in forecast.breaches) {
  alert('${e.eventType.name} ${e.geofenceId} in '
        '${e.timeUntilBreach?.inMinutes} min');
}
```

### Comprobar una zona sin gastar una petición

```dart
// Local and free. For drawing the state in the UI.
final zone = GeofenceGeometry.circle(center: warehouse, radiusMeters: 500);
if (zone.contains(vehiclePosition)) { ... }

// The OFFICIAL evaluation —the one that fires events— is something else:
await maps.geofencing.batchEvaluateGeofences(
  collectionName: 'zones',
  positions: [DevicePositionUpdate(
    deviceId: deviceId, position: p, sampleTime: gpsTime)],
);
// ↑ Returns only errors. Events arrive through EventBridge.
```

### Día y noche

```dart
final styles = maps.maps.dayNightStyleUrls(MapStyle.standard);
NativMap(
  styleUrl: isNight ? styles.dark! : styles.light!,
  // Changing this string reloads the style and reinstalls the overlays by itself.
  ...
);
```

### Isócrona pintada

```dart
final r = await maps.routes.calculateIsolines(
  origin: lastPosition,
  thresholds: Thresholds.time([const Duration(minutes: 8)]),
  travelMode: TravelMode.scooter,
);
await controller.addPolygon(
  Polygon.fromIsoline(r.isolines.first, polygonId: const PolygonId('zone')),
);
// ⚠️ If the isoline has several polygons (a river with no bridges), iterate
// `isolines.first.polygons` and create one for each. Flattening them joins both
// banks with a straight line across the water.
```

---

## 6 · Antipatrones que producen fallos silenciosos

```dart
// ❌ Fetching on every camera move → dozens of requests per gesture
onCameraMove: (p) => maps.places.searchNearby(position: p.target),
// ✅
onCameraIdle: () => _searchCurrentView(),

// ❌ One client per screen → each one with its own empty caches
Widget build(_) { final maps = NativMaps(...); }
// ✅ one shared across the whole app

// ❌ An error cell holds zeros, and a zero looks like "the closest"
final best = matrix.cell(i, 0).duration;
// ✅
if (matrix.cell(i, 0).isValid) { ... }

// ❌ `locality` is the whole city, kilometers away from the point
final address = places.first.formattedAddress;
// ✅
if (places.first.placeType?.isPrecise ?? false) { ... }

// ❌ Without granularity, 30 min = thousands of vertices and the UI freezes
calculateIsolines(origin: p, thresholds: Thresholds.time([Duration(minutes: 30)]),
                  granularity: const IsolineGranularity());
// ✅ keep the default, which already has maxPoints: 300

// ❌ The URL has the key inside
logger.info('style: ${maps.maps.styleDescriptorUrl(MapStyle.standard)}');
// ✅ never log that URL
```

---

### Sumar la distancia entre lecturas del GPS

```dart
// ❌ A parked car racks up kilometers: the receiver bounces around inside its
//    uncertainty circle, and the passenger pays for that bouncing.
for (var i = 1; i < positions.length; i++) {
  total += positions[i - 1].distanceTo(positions[i]);
}

// ✅
final recorder = TripRecorder();
for (final p in readings) recorder.add(p);
final total = recorder.finish().distanceMeters;
```

### Pasar `PositionFix` sin `accuracyMeters`

```dart
// ❌ Without the uncertainty there's no way to tell slow progress from bouncing,
//    and the filter can only apply the absolute 3 m floor.
PositionFix(position: p, timestamp: t)

// ✅
PositionFix(position: p, timestamp: t, accuracyMeters: reading.accuracy,
    speedKmh: reading.speed * 3.6)
```

### Guardar solo el total de la carrera

```dart
// ❌ Six months later the complaint arrives and there's no way to justify it.
save(fare.total);

// ✅ The breakdown has the math for each line: "12.40 km × 1.10".
save(fare.total, fare.lines);
```

### Usar `double` para el dinero

```dart
// ❌ 0.10 has no exact binary float; the till won't balance at month end.
double rate = 1.10;

// ✅ Minor units, as integers. Rounding happens once, at the end.
const perKilometer = 110;   // cents
```

### Ordenar conductores por distancia en línea recta

```dart
// ❌ The driver 300 m away across the river takes fifteen minutes.
drivers.sort((a, b) => a.position.distanceTo(point)
    .compareTo(b.position.distanceTo(point)));

// ✅ Free first, matrix only for the finalists.
final best = await planner.findNearest(drivers, point);
```

### Recalcular la ruta al primer punto que se salga

```dart
// ❌ One bad reading puts the car 80 m from its lane. On a narrow street it
//    happens several times a minute, and every recalculation is billed.
if (position.distanceTo(route.points.first) > 50) await recalculate();

// ✅ RouteTracker requires several readings in a row before trusting it.
final progress = tracker.update(position);
if (progress.offRoute) await recalculate();
```

### Recortar el rastro antes de medirlo

```dart
// ❌ Douglas–Peucker removes exactly the points on gentle curves: the
//    distance always comes out shorter, and you undercharge.
final total = pathLength(simplifyPath(track, toleranceMeters: 5));

// ✅ Measure first, then simplify for storage.
final total = recorder.finish().distanceMeters;
final toStore = simplifyPath(trip.track, toleranceMeters: 5);
```

### Enseñar la probabilidad de aceptación cuando es una estimación

```dart
// ❌ `estimated: true` means there's an uncalibrated curve behind it, or
//    straight-line times. A percentage with decimals there is a lie.
Text('${(f.probability * 100).toStringAsFixed(1)}% acceptance');

// ✅
Text(f.estimated
    ? 'Approximate price'
    : '${f.driversLikelyToAccept} of ${f.driversConsidered} would accept');
```

### Meter los peajes dentro del precio sugerido

```dart
// ❌ Tolls aren't negotiable and the driver doesn't keep them. Inside the
//    price, the bidding gets distorted and the driver thinks they earn more.
final offer = price.recommended + tolls;

// ✅ They go separately, as in inDrive.
final offer = price.recommended;
final extras = price.extrasPaidSeparately;
```

### Calibrar la tarifa con muestras de hora punta

```dart
// ❌ Demand leaks INTO the coefficients, and then MarketConditions
//    applies it again: you charge twice.
// ✅ Take the samples during quiet hours. Demand is a separate layer.
```

### Fiarte del reparto km/minuto sin mirar la correlación

```dart
// ❌ In cities, kilometers and minutes go hand in hand. The fit predicts the
//    total well, and the split between the two can be arbitrary.
final tariff = fit.toTariff(currency: 'USD');

// ✅
if (!fit.splitIsReliable) {
  // Add samples that break the correlation: a short trip in a traffic jam and
  // a long one on the highway at six in the morning.
}
```

## 7 · Nombres exactos de los enums

```dart
TravelMode      .car .truck .pedestrian .scooter        // NOT .motorcycle
MapStyle        .standard .monochrome .hybrid .satellite
MapColorScheme  .light .dark
IntendedUse     .singleUse .storage
PlaceType       .country .region .subRegion .locality .district .subDistrict
                .postalCode .block .subBlock .intersection .street
                .pointAddress .interpolatedAddress .pointOfInterest
PlaceFeature    .core .contact .timeZone .access .phonemes
                .secondaryAddresses .intersections
RouteFeature    .elevation .incidents .passThroughWaypoints .summary
                .tolls .travelStepInstructions .truckRoadTypes
                .typicalDuration .zones          // NOT .tollSystems: AWS rejects it
TravelStepType  .turnByTurn .standard            // instructions need .standard
MapTraffic      .all .congestion
MapTerrain      .hillshade .terrain3d
MapBuildings    .buildings3d
MapPoiDensity   .off .verySparse .sparse .standard .dense .veryDense
AlsService      .places .routes .maps               // sign as geo-places/-routes/-maps
                .geofencing .geofencingControl      // sign as plain `geo`
                .tracking .trackingControl          // the `*Control` ones use cp.
PositionFiltering .timeBased .distanceBased .accuracyBased
ForecastedEventType .enter .exit .idle
Cap             .buttCap .roundCap .squareCap
JointType       .mitered .round .bevel
```

---

## 8 · Antes de dar por buena la integración

1. `dart run melos run verify` en la raíz → formato, análisis y las 435 pruebas.
   Y `tool/test_floor.sh <bin de Flutter 3.32>`: el suelo, con cada paquete
   resuelto suelto, como lo ve quien lo instala.
2. Android: AGP **8.x** (no 9.x) y **JDK 21**. Ver «Limitaciones conocidas» en
   el README.
3. La atribución tiene que verse. `attributionEnabled: false` sin enseñarla en
   otro sitio puede incumplir las condiciones del proveedor de datos.
4. Para mapas sin conexión: leer la **Sección 82 de los AWS Service Terms**
   antes de enviar la app.
5. **En producción, ninguna clave en la app**: `ProxyCredentials`, el
   `NativMap` con `customHeaders` desde el primer `build`, y el proxy pasando
   `dart test -P proxy` —las 26— contra el despliegue real. Lista completa en
   la sección 9.

---

## 9 · En producción: la clave en tu servidor

La app no lleva **ningún secreto de AWS**. Habla con un servidor tuyo —el
proxy—, que comprueba la sesión del usuario, se autentica ante Amazon Location
y reenvía. Contrato completo: [doc/PROXY.md](doc/PROXY.md).

| | `ApiKeyCredentials` | **`ProxyCredentials`** | `SigV4Credentials` (`nativ_maps_sigv4`) |
|---|---|---|---|
| Secreto en el teléfono | la clave, extraíble | **ninguno** | credenciales temporales de Cognito |
| Operaciones | 17 (sin geovallas ni rastreo) | **las 44** | las 44 |
| Límites por usuario | no | **sí, en el proxy** | no |
| Para | desarrollar | **producción** | producción sin backend propio |

### En la app

```dart
// ONE client for the whole app, created once the user has a session.
// The map is read on every request: keep it and update it on renewal.
final auth = <String, String>{'Authorization': 'Bearer ${session.token}'};

final maps = NativMaps(
  region: 'us-east-1',
  credentials: ProxyCredentials(
    baseUrl: Uri.parse('https://api.example.com/geo'),
    headers: auth,
  ),
  budget: Budget(maxUnits: 500),
);

// When the session renews: no new client.
auth['Authorization'] = 'Bearer ${session.token}';

// The map fetches the style and the tiles by itself: it needs the token too.
NativMap(
  styleUrl: maps.maps.styleDescriptorUrl(MapStyle.standard)!, // already the proxy's
  // REQUIRED, from the FIRST build. Build a NEW map in build() from the
  // current token: a changed map is re-applied; the same instance mutated
  // is not.
  customHeaders: {'Authorization': 'Bearer ${session.token}'},
  initialCameraPosition: ...,
  onStyleError: (e) => report(e),   // a 401 here = the token didn't reach it
)
```

| Regla | Si la rompes |
|---|---|
| `customHeaders` **desde el primer `build`** | el estilo se pidió sin token: `401` y mapa en blanco. Con ellas, el mapa arranca vacío y pide el estilo cuando ya están puestas |
| El `styleUrl` sale de `maps.maps.styleDescriptorUrl` | escrito a mano, apunta a AWS y no al proxy |
| Las cabeceras del mapa van **solo** al host del `styleUrl` y a `amazonaws.com` | nada: es a propósito, para que el token no llegue a un tercero |
| `nativ_maps_flutter` **≥ 0.9.1** | en la 0.9.0, Android nunca mandaba las cabeceras del mapa |

### El servidor: no lo escribas, elige uno

Seis implementaciones del mismo contrato en [`proxies/`](proxies). Las seis
pasan las 26 pruebas de conformidad contra AWS, firmando con SigV4 y con clave
de API.

| Si el backend es… | Usa | Montado en |
|---|---|---|
| ninguno todavía | [`proxies/aws-lambda`](proxies/aws-lambda) · **sin ninguna clave**: firma el rol; plantilla SAM con la política exacta | `sam deploy --guided` |
| JavaScript / TypeScript | [`proxies/node`](proxies/node) | Express, Fastify, NestJS |
| Go | [`proxies/go`](proxies/go) | `net/http`, chi, gin, echo |
| Python | [`proxies/python`](proxies/python) | FastAPI, Flask |
| PHP | [`proxies/php`](proxies/php) | Laravel, Slim |
| JVM | [`proxies/java`](proxies/java) | Spring Boot |

Todos: un núcleo sin framework más un servidor mínimo, y **las mismas
variables**:

| Variable | | |
|---|---|---|
| `PROXY_TOKEN` | obligatoria | token de prueba. **En producción, sustituye `authorize` por la comprobación de tu sesión** (JWT, cookie…) |
| `AWS_REGION` | obligatoria | la región del mapa |
| `ALS_API_KEY` | opcional | clave para lugares, rutas y mapas en vez de SigV4. Geovallas y rastreo firman siempre |
| `PROXY_BASE_PATH` | `/geo` | dónde se monta |
| `PROXY_PUBLIC_URL` | se deduce | la URL pública, si hay un balanceador o una CDN delante |
| `PORT` | `8080` | |

Credenciales de AWS por la cadena estándar: el rol de la Lambda, ECS o EC2
—sin claves— o `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`.

### Lo que hace el proxy, por si escribes el tuyo

1. **Comprueba al usuario antes que nada.** Sin sesión, `401` y no se reenvía.
2. Destino = cabecera `X-Nativ-Host`. Sin ella, solo rutas del mapa
   (`/v2/styles|tiles|glyphs|static/`) → `maps.geo.{región}.amazonaws.com`.
3. **Valida el host, coincidencia completa**, o `400`:
   `^(places|routes|maps|geofencing|tracking|cp\.geofencing|cp\.tracking)\.geo\.([a-z0-9-]+)\.amazonaws\.com$`.
   Firma: `places`→`geo-places`, `routes`→`geo-routes`, `maps`→`geo-maps`,
   el resto `geo`.
4. Quita cualquier `key` de la consulta; firma con SigV4 o añade su clave.
5. Reenvía método, ruta, consulta —con parámetros repetidos— y cuerpo, con
   solo `host`, `content-type` y la firma. **Nunca** el `Authorization` de la
   app.
6. Devuelve estado y cuerpo tal cual —también los errores de AWS—, byte a
   byte.
7. **Reescribe el descriptor de estilo**: `https://maps.geo.{región}.amazonaws.com`
   → la URL pública del proxy, y **quita todo `key=`**, que AWS mete en cada
   URL de tesela.
8. No sigue redirecciones; 60 s de espera y `502`; registra solo método, ruta y
   estado.

### IAM

```json
{"Version": "2012-10-17", "Statement": [
  {"Effect": "Allow", "Action": ["geo-places:*", "geo-routes:*", "geo-maps:*"],
   "Resource": "*"},
  {"Effect": "Allow", "Action": "geo:*", "Resource": [
    "arn:aws:geo:us-east-1:<cuenta>:geofence-collection/*",
    "arn:aws:geo:us-east-1:<cuenta>:tracker/*"]},
  {"Effect": "Allow", "Action": ["geo:ListGeofenceCollections", "geo:ListTrackers"],
   "Resource": "*"}
]}
```

Sin geovallas ni rastreo, basta el primer bloque. La plantilla de Lambda trae
la misma política acción por acción.

### Comprobar el despliegue

```sh
cd packages/nativ_maps
PROXY_URL=https://api.example.com/geo PROXY_TOKEN=<a valid session token> \
  dart test -P proxy
```

Las 26: lo que el proxy tiene que rechazar, lo que el paquete manda, el mapa
como lo pide el motor —sin ninguna `key=` a la vista— y los cuatro hosts que
firman como `geo`. Crea y borra sus propios recursos `nativ-maps-proxy-…`.

En el dispositivo, la app de ejemplo corre entera por un proxy:
`flutter run --dart-define=ALS_PROXY_URL=… --dart-define=ALS_PROXY_TOKEN=…`
(`10.0.2.2` es el ordenador visto desde el emulador de Android).

### Antes de entregar

- [ ] Ninguna `ApiKeyCredentials` ni clave en el código de producción.
- [ ] HTTPS delante del proxy.
- [ ] `authorize` es la comprobación de **tu** sesión, no `PROXY_TOKEN`.
- [ ] La lista de hosts del punto 3, tal cual.
- [ ] Límites por usuario en el proxy —la matriz cobra por par— y un tope en
      AWS Budgets.
- [ ] Una CDN delante solo para `/v2/tiles/`, `/v2/glyphs/` y `/v2/styles/`;
      nunca para lugares o rutas, que son de cada usuario.
- [ ] `dart test -P proxy` en verde contra el despliegue real.
