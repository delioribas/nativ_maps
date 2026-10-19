// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

/// Amazon Location Service v2 in pure Dart, shaped like Google Maps.
///
/// All **44 operations** —Places, Routes, Maps, geofencing and tracking—
/// behind a typed client, with a spending cap, retries and no Flutter
/// dependency at all.
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
/// final results = await maps.places.searchText(queryText: 'gasolinera');
/// ```
///
/// ## The thesis
///
/// The `LatLng` a search returns is the same one a marker accepts. A
/// calculated route is drawn by passing it straight to a polyline. No
/// conversions, no two keys and no two type systems.
///
/// ## To draw maps
///
/// This package **does not draw**. The widget lives in `nativ_maps_flutter`,
/// which re-exports everything from here: installing just that one gets you
/// the 44 operations plus the map.
///
/// It lives apart so it can be tested without an emulator and used in a
/// command-line tool or a Dart server.
///
/// ## Library map
///
/// | I want to… | Look at… |
/// |---|---|
/// | get started | `NativMaps` |
/// | search, geocode | `PlacesClient` |
/// | routes, isolines, snap to roads | `RoutesClient` |
/// | zones and early warnings | `GeofencingClient` |
/// | device history | `TrackingClient` |
/// | the map style | `MapsClient` |
/// | authenticate | `Credentials` |
/// | avoid a nasty surprise on the bill | `Budget` |
///
/// ## Calculation layer, no network and no cost
///
/// | I want to… | Look at… |
/// |---|---|
/// | measure a trip without GPS noise inflating it | `TripRecorder` |
/// | discard bad readings | `PositionFilter` |
/// | charge for a ride, with a breakdown | `Tariff` |
/// | know how much is left and whether it left the route | `RouteTracker` |
/// | auction a ride, inDrive-style | `RideAuction` |
/// | decide whether an offer is worth it for the driver | `BidAdvisor` |
/// | suggest a price to the passenger, with the reasons | `PriceAdvisor` |
/// | fit the tariff to the prices in your city | `TariffCalibration` |
/// | pick the driver who is actually closest | `DispatchPlanner` |
/// | score how someone drives | `TelemetryAnalyzer` |
/// | path geometry, trimming histories | `simplifyPath` |
library;

// The `export`s go in a single block, in alphabetical order, because that is
// what `directives_ordering` demands. The grouping by service, which would be
// more readable, is documented in the table above instead.
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
export 'src/trip/auction.dart'
    show
        AuctionState,
        BidAdvisor,
        BidEvaluation,
        BidRanking,
        DriverBid,
        DriverEconomics,
        RideAuction,
        RideRequest;
export 'src/trip/calibration.dart'
    show FareSample, TariffCalibration, TariffFit;
export 'src/trip/dispatch.dart'
    show DispatchPlanner, DriverCandidate, DriverLocation;
export 'src/trip/fare.dart'
    show FareBreakdown, FareLine, FareRounding, Surcharge, Tariff, TariffBand;
export 'src/trip/geodesy.dart'
    show
        PathMatch,
        crossTrackMeters,
        cumulativeDistances,
        interpolateOnPath,
        nearestPointOnPath,
        pathLength,
        simplifyPath;
export 'src/trip/position_filter.dart'
    show FilterResult, FixRejection, PositionFilter, PositionFix;
export 'src/trip/pricing.dart'
    show
        AcceptanceForecast,
        DemandSignal,
        MarketConditions,
        PriceAdvisor,
        PriceFactor,
        SuggestedPrice;
export 'src/trip/route_progress.dart' show RouteProgress, RouteTracker;
export 'src/trip/telemetry.dart'
    show DrivingEvent, DrivingEventType, DrivingScore, TelemetryAnalyzer;
export 'src/trip/trip_recorder.dart'
    show StopPeriod, TripRecorder, TripSummary, TripUpdate;
