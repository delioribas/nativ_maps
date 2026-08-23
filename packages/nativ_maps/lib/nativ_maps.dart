// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

/// Amazon Location Service v2 en Dart puro, con la forma de Google Maps.
///
/// Las **44 operaciones** —Places, Routes, Maps, geovallas y rastreo— detrás
/// de un cliente tipado, con tope de gasto, reintentos y sin ninguna
/// dependencia de Flutter.
///
/// ```dart
/// import 'package:nativ_maps/nativ_maps.dart';
///
/// final maps = NativMaps(
///   region: 'us-east-1',
///   credentials: const ApiKeyCredentials('...'),
///   language: 'es',
/// );
///
/// final resultados = await maps.places.searchText(queryText: 'gasolinera');
/// ```
///
/// ## La tesis
///
/// El `LatLng` que devuelve una búsqueda es el mismo que acepta un marcador.
/// Una ruta calculada se pinta pasándola directamente a una polilínea. Sin
/// conversiones, sin dos claves y sin dos sistemas de tipos.
///
/// ## Para pintar mapas
///
/// Este paquete **no dibuja**. El widget está en `nativ_maps_flutter`, que
/// reexporta todo lo de aquí: instalando solo ese ya se tienen las diecisiete
/// operaciones más el mapa.
///
/// Vive aparte para poder probarse sin emulador y para servir en una
/// herramienta de línea de órdenes o un servidor Dart.
///
/// ## Mapa de la biblioteca
///
/// | Quiero… | Miro en… |
/// |---|---|
/// | empezar | `NativMaps` |
/// | buscar, geocodificar | `PlacesClient` |
/// | rutas, isócronas, snap a carretera | `RoutesClient` |
/// | zonas y avisos anticipados | `GeofencingClient` |
/// | histórico de dispositivos | `TrackingClient` |
/// | el estilo del mapa | `MapsClient` |
/// | autenticar | `Credentials` |
/// | no llevarme un susto en la factura | `Budget` |
library;

// Los `export` van en un solo bloque y en orden alfabético porque es lo que
// exige `directives_ordering`. La agrupación por servicio, que sería más
// legible, se documenta arriba en la tabla en su lugar.
export 'src/auth/api_key.dart'
    show ApiKeyCredentials, HeaderCredentials, ProxyCredentials;
export 'src/auth/credentials.dart' show Credentials, DirectCredentials;
export 'src/client/budget.dart' show BillingUnits, Budget, BudgetPolicy;
export 'src/client/transport.dart' show AlsBytes, TransportOptions;
export 'src/core/enums.dart';
export 'src/core/exceptions.dart';
export 'src/core/lat_lng.dart' show LatLng, LatLngBounds, earthRadiusMeters;
export 'src/core/polyline.dart'
    show decodeFlexiblePolyline, decodeGooglePolyline, encodeFlexiblePolyline;
export 'src/geofencing/geofencing_client.dart' show GeofencingClient;
export 'src/geofencing/models.dart'
    show
        BatchItemError,
        BatchResult,
        DevicePositionUpdate,
        ForecastGeofenceEventsResponse,
        ForecastedEventType,
        ForecastedGeofenceEvent,
        Geofence,
        GeofenceCollection,
        GeofenceGeometry,
        GeofencePage;
export 'src/maps/maps_client.dart' show MapsClient;
export 'src/nativ_maps_base.dart' show NativMaps;
export 'src/places/address.dart'
    show Address, AdminArea, Country, StreetComponent;
export 'src/places/options.dart'
    show AddressComponents, PlaceFeature, PostalCodeMode, SearchFilter;
export 'src/places/place.dart'
    show
        AccessPoint,
        ContactDetail,
        Contacts,
        Highlight,
        OpeningHours,
        OpeningHoursComponent,
        Place,
        PlaceCategory,
        PlaceType,
        TimeZoneInfo;
export 'src/places/places_client.dart' show PlacesClient;
export 'src/places/results.dart'
    show
        AutocompleteSuggestion,
        PlaceSearchResponse,
        QueryRefinement,
        SuggestResponse,
        SuggestResult,
        SuggestResultType;
export 'src/routes/models.dart'
    show
        Isoline,
        IsolineResponse,
        MatrixCell,
        OptimizationWaypoint,
        OptimizedWaypoint,
        Route,
        RouteGeometry,
        RouteIncident,
        RouteLeg,
        RouteMatrix,
        RouteResponse,
        SnapToRoadsResponse,
        SnappedTracePoint,
        Toll,
        TracePoint,
        TravelStep,
        WaypointConnection,
        WaypointOptimizationResponse;
export 'src/routes/options.dart'
    show
        DriverOptions,
        IsolineGranularity,
        RouteAvoidance,
        RouteFeature,
        Thresholds,
        TravelModeOptions;
export 'src/routes/routes_client.dart'
    show AlsParseExceptionForMatrix, RoutesClient;
export 'src/tracking/models.dart'
    show
        DevicePosition,
        PositionFiltering,
        PositionVerification,
        Tracker,
        TrackingPage,
        WiFiAccessPoint;
export 'src/tracking/tracking_client.dart' show TrackingClient;
