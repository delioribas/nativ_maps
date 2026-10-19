// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

/// The three Amazon Location v2 services.
///
/// It exists for one very specific reason: **each one signs with a different
/// name**. Getting it wrong produces a `403` identical to that of an invalid
/// key, and you lose an afternoon looking in the wrong place. Being an enum,
/// the name cannot be misspelled.
enum AlsService {
  /// Search, geocoding and place details.
  places('geo-places', 'places'),

  /// Routes, matrices, isolines, snap to roads and optimization.
  routes('geo-routes', 'routes'),

  /// Styles, tiles and static maps.
  maps('geo-maps', 'maps'),

  /// Geofences: evaluating positions against zones and predicting entries and
  /// exits.
  ///
  /// **Signs with `geo`, not with `geo-geofencing`.** It belongs to the
  /// previous generation, the one that still uses resources created in the
  /// console, and AWS has not released a v2 of it. The signing name is that of
  /// the legacy service.
  geofencing('geo', 'geofencing'),

  /// The geofencing control plane: creating, deleting and listing collections.
  ///
  /// **It goes to another host**: `cp.geofencing.geo.…`, with the `cp.` prefix
  /// in front. Sending a control operation to the data host gives a `404` that
  /// looks like a misspelled path.
  geofencingControl('geo', 'cp.geofencing'),

  /// Device tracking: positions, history and verification.
  ///
  /// Signs with `geo`, like [geofencing].
  tracking('geo', 'tracking'),

  /// The tracking control plane: creating, deleting and listing trackers.
  ///
  /// Also with the `cp.` prefix.
  trackingControl('geo', 'cp.tracking');

  const AlsService(this.signingName, this.hostPrefix);

  /// The name SigV4 uses to sign requests to this service.
  ///
  /// There are **two generations and they do not share names**:
  ///
  /// - Places, Routes and Maps v2 sign with `geo-places`, `geo-routes` and
  ///   `geo-maps`.
  /// - Geofencing and Tracking sign with plain `geo`, because they belong to
  ///   the previous generation.
  ///
  /// Getting it wrong gives a `403` identical to that of an invalid key. Being
  /// an enum, the name cannot be misspelled.
  final String signingName;

  /// The host prefix: `{hostPrefix}.geo.{region}.amazonaws.com`.
  ///
  /// The control planes' `cp.` prefix is part of it:
  /// `cp.geofencing.geo.us-east-1.amazonaws.com`.
  final String hostPrefix;

  /// Does it belong to the v2 generation, the one that needs no resources
  /// created?
  ///
  /// It matters for two things: the v2 generation accepts an API key and the
  /// previous one does **not** —only SigV4—, and the previous one does use
  /// `DistanceUnit`, which in v2 triggers a `400`.
  bool get isV2 => this == places || this == routes || this == maps;

  /// Does it accept API key authentication?
  ///
  /// **Only the v2 generation.** Amazon Location API keys cover Places,
  /// Routes and Maps; Geofencing and Tracking require SigV4, either through a
  /// proxy or with `nativ_maps_sigv4`. Trying it with a key gives a `403`.
  bool get supportsApiKey => isV2;

  /// The service host in [region].
  ///
  /// For example, `places.geo.us-east-1.amazonaws.com`.
  String hostFor(String region) => '$hostPrefix.geo.$region.amazonaws.com';
}

/// Travel mode for the Routes operations.
///
/// The motorbike's name is the one that causes the most confusion: in the
/// previous generation it was `Motorcycle`; in v2 it is called [scooter], and
/// the AWS documentation explicitly says it **also covers motorcycles**, not
/// just mopeds.
enum TravelMode {
  /// Car or van. The default for every operation.
  car('Car'),

  /// Truck. Accepts dimensions, weight and hazardous cargo in
  /// `TruckOptions`, which change the route because of road restrictions.
  truck('Truck'),

  /// On foot. Ignores one-way streets and uses sidewalks and crossings.
  pedestrian('Pedestrian'),

  /// Scooter, moped or motorcycle.
  scooter('Scooter');

  const TravelMode(this.wireName);

  /// The literal that travels in the request JSON.
  final String wireName;
}

/// Catalog of Maps v2 map styles.
///
/// In the previous generation you had to create a "Map" resource in the
/// console and you chose its name, so a misspelled name was only discovered at
/// runtime. In v2 the catalog is fixed and nothing is created: that is why
/// this is an enum and not a `String`.
enum MapStyle {
  /// Full-color cartography. The default style.
  standard('Standard'),

  /// A single tone, meant as a background under your own data.
  monochrome('Monochrome'),

  /// Satellite with labels and roads on top.
  hybrid('Hybrid'),

  /// Satellite imagery only, no labels.
  satellite('Satellite');

  const MapStyle(this.wireName);

  /// The literal that travels in the URL.
  final String wireName;
}

/// Map tone.
///
/// It replaces the pair of "light" and "dark" resources that in the previous
/// generation had to be created by hand and kept in sync. Now it is the same
/// style with another parameter, and **the server renders it**: it is not a
/// color filter over light tiles, so the labels stay legible.
enum MapColorScheme {
  /// Light background. It is the service default.
  light('Light'),

  /// Dark background.
  dark('Dark');

  const MapColorScheme(this.wireName);

  /// The literal that travels in the URL.
  final String wireName;
}

/// Whether the result is going to be stored in your own infrastructure.
///
/// It is not a technical detail or an optimization: the AWS documentation says
/// that **storing a result obtained with [singleUse] breaches the service
/// terms**. [storage] is billed at a higher price.
///
/// The rule of thumb: an address written into a customer's record is
/// [storage]; one that is only shown on screen while choosing is
/// [singleUse].
enum IntendedUse {
  /// The result is shown and discarded. Cheaper.
  singleUse('SingleUse'),

  /// The result is stored in your database. More expensive, and mandatory if
  /// you are going to persist it.
  storage('Storage');

  const IntendedUse(this.wireName);

  /// The literal that travels in the JSON or in the URL.
  final String wireName;
}

/// What is optimized when calculating a route.
enum RouteOptimization {
  /// The fastest route in time. The default.
  fastestRoute('FastestRoute'),

  /// The shortest route in distance, even if it takes longer.
  shortestRoute('ShortestRoute');

  const RouteOptimization(this.wireName);

  /// The literal that travels in the JSON.
  final String wireName;
}

/// How traffic information is used when calculating.
enum TrafficUsage {
  /// Real-time traffic is taken into account. The default.
  useTrafficData('UseTrafficData'),

  /// It is ignored. Gives reproducible results, useful for comparing.
  ignoreTrafficData('IgnoreTrafficData');

  const TrafficUsage(this.wireName);

  /// The literal that travels in the JSON.
  final String wireName;
}

/// Format in which the geometry of a route or an isoline arrives.
enum GeometryFormat {
  /// Uncompressed list of coordinates (`LineString`). Heavier over the
  /// network, but there is nothing to decode.
  simple('Simple'),

  /// String compressed in **HERE's Flexible Polyline** format, which is not
  /// Google's. Much lighter; `decodeFlexiblePolyline` decodes it.
  flexiblePolyline('FlexiblePolyline');

  const GeometryFormat(this.wireName);

  /// The literal that travels in the JSON.
  final String wireName;
}

/// What a route's steps look like.
///
/// Measured against the service on 2026-10-19: both return the steps of the
/// route (`Depart`, `Turn`, `Arrive`…); what changes is whether they can carry
/// a written instruction.
enum TravelStepType {
  /// Steps with the maneuver details —turn angle, intensity, exit number—
  /// and **no written instruction**.
  ///
  /// It can't be combined with `RouteFeature.travelStepInstructions`: the
  /// service answers 400, and the package stops it before sending.
  turnByTurn('TurnByTurn'),

  /// The service's default steps, and the only ones that take
  /// `RouteFeature.travelStepInstructions`: with it, each step carries a ready
  /// instruction in the request's language —"Gire a la derecha en Avenida
  /// Amazonas…"— in `TravelStep.instruction`.
  standard('Default');

  const TravelStepType(this.wireName);

  /// The literal that travels in the JSON.
  final String wireName;
}

/// What is optimized when reordering the stops in `optimizeWaypoints`.
enum WaypointOptimization {
  /// Minimizes the total travel time.
  fastestRoute('FastestRoute'),

  /// Minimizes the total distance.
  shortestRoute('ShortestRoute');

  const WaypointOptimization(this.wireName);

  /// The literal that travels in the JSON.
  final String wireName;
}

// ═══════════════════════════════════════════════════════════════════════════
//  Style descriptor features (Maps v2)
//
//  These seven parameters are what in `google_maps_flutter` does not exist or
//  needs a separate layer: traffic, terrain, 3D buildings and point-of-interest
//  density are drawn by the server inside the same style, with no second
//  request and no overlay.
// ═══════════════════════════════════════════════════════════════════════════

/// How buildings are drawn.
enum MapBuildings {
  /// Buildings extruded in three dimensions.
  ///
  /// Only works with [MapStyle.standard] and [MapStyle.monochrome].
  buildings3d('Buildings3D');

  const MapBuildings(this.wireName);

  /// The literal that travels in the URL.
  final String wireName;
}

/// How terrain relief is drawn.
enum MapTerrain {
  /// Relief shading. Only with [MapStyle.standard] and
  /// [MapStyle.monochrome].
  hillshade('Hillshade'),

  /// Three-dimensional terrain model.
  terrain3d('Terrain3D');

  const MapTerrain(this.wireName);

  /// The literal that travels in the URL.
  final String wireName;
}

/// Density of contour lines.
///
/// Not available in `ap-southeast-1` or `ap-southeast-5` (GrabMaps), nor with
/// [MapStyle.satellite].
enum MapContourDensity {
  /// Few lines, only the main ones.
  low('Low'),

  /// Intermediate density.
  medium('Medium'),

  /// Every available line.
  high('High');

  const MapContourDensity(this.wireName);

  /// The literal that travels in the URL.
  final String wireName;
}

/// Real-time traffic drawn inside the style.
///
/// This is the real equivalent of `google_maps_flutter`'s `trafficEnabled`:
/// it is not an overlay requested separately, it is the server itself
/// coloring the roads when generating the style.
enum MapTraffic {
  /// Congestion plus incidents (roadworks, accidents, closures).
  all('All'),

  /// Only the roads' congestion color.
  congestion('Congestion');

  const MapTraffic(this.wireName);

  /// The literal that travels in the URL.
  final String wireName;
}

/// How many points of interest are drawn.
enum MapPoiDensity {
  /// None. It is what you want when the map is the background for your own
  /// data.
  off('Off'),

  /// Very few.
  verySparse('VerySparse'),

  /// Few.
  sparse('Sparse'),

  /// The service default.
  standard('Default'),

  /// Many.
  dense('Dense'),

  /// All available.
  veryDense('VeryDense');

  const MapPoiDensity(this.wireName);

  /// The literal that travels in the URL.
  final String wireName;
}

/// Point-of-interest categories that are drawn.
///
/// When you specify any, only those are drawn. You can pass up to nine, and it
/// has no effect if the density is [MapPoiDensity.off].
enum MapPoiCategory {
  /// Restaurants, bars and cafés.
  foodAndDrink('FoodAndDrink'),

  /// Leisure and shows.
  entertainment('Entertainment'),

  /// Monuments and museums.
  sightsAndMuseums('SightsAndMuseums'),

  /// Stations, stops and airports.
  transportation('Transportation'),

  /// Hotels and lodging.
  accommodations('Accommodations'),

  /// Parks and the outdoors.
  leisureAndOutdoor('LeisureAndOutdoor'),

  /// Shops.
  shopping('Shopping'),

  /// Offices and services.
  businessAndServices('BusinessAndServices'),

  /// Public facilities and buildings.
  facilitiesAndBuildings('FacilitiesAndBuildings');

  const MapPoiCategory(this.wireName);

  /// The literal that travels in the URL.
  final String wireName;
}

/// Additional information for a mode of transport, drawn in the style.
enum MapTravelMode {
  /// Public transit networks.
  transit('Transit'),

  /// Road restrictions for trucks.
  truck('Truck');

  const MapTravelMode(this.wireName);

  /// The literal that travels in the URL.
  final String wireName;
}

/// Unit of a static map's scale bar.
enum ScaleBarUnit {
  /// Kilometers.
  kilometers('Kilometers'),

  /// Kilometers with miles below.
  kilometersMiles('KilometersMiles'),

  /// Miles.
  miles('Miles'),

  /// Miles with kilometers below.
  milesKilometers('MilesKilometers');

  const ScaleBarUnit(this.wireName);

  /// The literal that travels in the URL.
  final String wireName;
}
