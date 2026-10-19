// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/client/budget.dart';
import 'package:nativ_maps/src/client/cache.dart';
import 'package:nativ_maps/src/client/transport.dart';
import 'package:nativ_maps/src/core/enums.dart';
import 'package:nativ_maps/src/core/lat_lng.dart';
import 'package:nativ_maps/src/routes/models.dart';
import 'package:nativ_maps/src/routes/options.dart';

/// The **five** operations of Amazon Location Routes v2.
///
/// | Method | Endpoint | What for |
/// |---|---|---|
/// | [calculateRoutes] | `POST /v2/routes` | route between two points |
/// | [calculateRouteMatrix] | `POST /v2/route-matrix` | who is closest **by road** |
/// | [calculateIsolines] | `POST /v2/isolines` | **area reachable in X minutes** |
/// | [snapToRoads] | `POST /v2/snap-to-roads` | **snap the GPS trace to the real street** |
/// | [optimizeWaypoints] | `POST /v2/optimize-waypoints` | optimal order of stops |
///
/// The two marked in bold **don't exist in Google Maps**. Together with the
/// tolls in [Toll], they are what this package gives you and no Google wrapper
/// can.
///
/// ## The hard limits are checked here
///
/// The three operations with a limit check it **before sending**, because the
/// alternative is finding out with a `400` after having paid for the outbound
/// trip:
///
/// - matrix without a bounded area: 15 origins, 100 destinations, 100 cells;
/// - isolines: 5 thresholds;
/// - `snapToRoads`: 5,000 points — and this one **doesn't fail, it chunks**.
class RoutesClient {
  /// Builds the client. Internal use: it comes already wired into `NativMaps`.
  @internal
  RoutesClient({required AlsTransport transport, this.language})
    : _transport = transport;

  final AlsTransport _transport;

  /// Language of the instructions, in BCP 47.
  final String? language;

  static const AlsService _service = AlsService.routes;

  /// Routes are the most expensive requests, and they used to go uncached.
  ///
  /// Ten minutes is long enough that opening and closing a detail screen
  /// doesn't pay for them twice, and short enough that the traffic information
  /// is still relevant.
  final LruCache<String, RouteResponse> _routeCache =
      LruCache<String, RouteResponse>(60, ttl: const Duration(minutes: 10));

  // ─── Service limits ───────────────────────────────────────────────────

  /// Maximum origins of a matrix without a bounded area.
  static const int maxUnboundedMatrixOrigins = 15;

  /// Maximum destinations of a matrix without a bounded area.
  static const int maxUnboundedMatrixDestinations = 100;

  /// Maximum cells of a matrix without a bounded area.
  static const int maxUnboundedMatrixCells = 100;

  /// Maximum thresholds per isoline request. **Billed per threshold.**
  static const int maxIsolineThresholds = 5;

  /// Maximum points per `snapToRoads` request.
  static const int maxTracePointsPerRequest = 5000;

  // ─── 1 · CalculateRoutes ──────────────────────────────────────────────

  /// Calculates a route. `POST /v2/routes`.
  ///
  /// ```dart
  /// final response = await routes.calculateRoutes(
  ///   origin: currentPosition,
  ///   destination: destination,
  ///   travelMode: TravelMode.scooter,
  ///   legAdditionalFeatures: const [RouteFeature.tolls, RouteFeature.summary],
  /// );
  /// final route = response.best!;
  /// map.addPolyline(Polyline(polylineId: 'route', points: route.points));
  /// ```
  ///
  /// The geometry is requested in [GeometryFormat.simple] by default: it
  /// weighs more over the network but there is nothing to decode. For a long
  /// history or a poor connection, [GeometryFormat.flexiblePolyline] cuts the
  /// size by around 80 % and is decoded automatically.
  ///
  /// [departureTime] and [arrivalTime] are mutually exclusive. With neither,
  /// `DepartNow` is sent, which uses the current traffic.
  ///
  /// **Distances in meters and durations in seconds.** v2 has no unit
  /// parameter; sending `DistanceUnit` —which existed in v0— causes a `400`.
  Future<RouteResponse> calculateRoutes({
    required LatLng origin,
    required LatLng destination,
    List<LatLng> waypoints = const <LatLng>[],
    TravelMode travelMode = TravelMode.car,
    TravelModeOptions? travelModeOptions,
    DateTime? departureTime,
    DateTime? arrivalTime,
    RouteOptimization optimizeFor = RouteOptimization.fastestRoute,
    RouteAvoidance? avoid,
    TrafficUsage traffic = TrafficUsage.useTrafficData,
    GeometryFormat geometryFormat = GeometryFormat.simple,
    TravelStepType travelStepType = TravelStepType.turnByTurn,
    List<RouteFeature> legAdditionalFeatures = const <RouteFeature>[],
    int maxAlternatives = 0,
    String? language,
    bool useCache = true,
  }) async {
    if (departureTime != null && arrivalTime != null) {
      throw ArgumentError(
        'departureTime y arrivalTime son excluyentes: la API responde 400 si '
        'llegan los dos.',
      );
    }
    if (maxAlternatives < 0 || maxAlternatives > 6) {
      throw ArgumentError.value(
        maxAlternatives,
        'maxAlternatives',
        'admite entre 0 y 6',
      );
    }
    // Written instructions only exist for the default steps; with
    // turn-by-turn ones the API answers 400.
    if (travelStepType == TravelStepType.turnByTurn &&
        legAdditionalFeatures.contains(RouteFeature.travelStepInstructions)) {
      throw ArgumentError.value(
        travelStepType,
        'travelStepType',
        'RouteFeature.travelStepInstructions exige TravelStepType.standard: '
            'con turnByTurn la API responde 400',
      );
    }
    // A pedestrian pays no tolls, and the API answers 400 instead of
    // ignoring the request. Caught here, nothing is billed.
    if (travelMode == TravelMode.pedestrian &&
        legAdditionalFeatures.contains(RouteFeature.tolls)) {
      throw ArgumentError.value(
        legAdditionalFeatures,
        'legAdditionalFeatures',
        'RouteFeature.tolls no se admite con TravelMode.pedestrian: la API '
            'responde 400',
      );
    }

    final cacheKey = _key(<Object?>[
      'route',
      origin,
      destination,
      waypoints,
      travelMode.wireName,
      optimizeFor.wireName,
      traffic.wireName,
      geometryFormat.wireName,
      travelStepType.wireName,
      legAdditionalFeatures.map((f) => f.wireName).join(','),
      maxAlternatives,
      departureTime?.toIso8601String(),
      arrivalTime?.toIso8601String(),
      avoid?.toJson(),
      travelModeOptions?.toJson(travelMode),
    ]);
    // With a departure time of "now" the cache does help —opening the same
    // detail screen twice in a row—, but with a fixed time it makes no sense to
    // reuse a result calculated with different traffic.
    if (useCache) {
      final hit = _routeCache.get(cacheKey);
      if (hit != null) return hit;
    }

    final json = await _transport.postJson(
      operation: 'CalculateRoutes',
      service: _service,
      path: '/v2/routes',
      body: <String, dynamic>{
        'Origin': origin.toLonLat(),
        'Destination': destination.toLonLat(),
        if (waypoints.isNotEmpty)
          'Waypoints': waypoints
              .map((w) => <String, dynamic>{'Position': w.toLonLat()})
              .toList(),
        'TravelMode': travelMode.wireName,
        if (travelModeOptions != null)
          'TravelModeOptions': travelModeOptions.toJson(travelMode),
        'LegGeometryFormat': geometryFormat.wireName,
        'OptimizeRoutingFor': optimizeFor.wireName,
        'TravelStepType': travelStepType.wireName,
        'MaxAlternatives': maxAlternatives,
        'Traffic': <String, dynamic>{'Usage': traffic.wireName},
        if (avoid != null && !avoid.isEmpty) 'Avoid': avoid.toJson(),
        if (legAdditionalFeatures.isNotEmpty)
          'LegAdditionalFeatures': legAdditionalFeatures
              .map((f) => f.wireName)
              .toList(),
        if (departureTime != null)
          'DepartureTime': departureTime.toUtc().toIso8601String()
        else if (arrivalTime != null)
          'ArrivalTime': arrivalTime.toUtc().toIso8601String()
        else
          'DepartNow': true,
        if ((language ?? this.language) != null)
          'InstructionsMeasurementSystem': 'Metric',
      },
    );

    final response = RouteResponse.fromJson(json);
    if (useCache) _routeCache.set(cacheKey, response);
    return response;
  }

  // ─── 2 · CalculateRouteMatrix ─────────────────────────────────────────

  /// Distances and times between every pair. `POST /v2/route-matrix`.
  ///
  /// It answers "which of my ten units gets there first" **by road**, which is
  /// a different question from "which one is closest in a straight line": the
  /// closest in a straight line may be on the other side of a river with no
  /// bridge.
  ///
  /// ## The cost, which is what surprises people
  ///
  /// **It is billed per pair, not per request.** A 10×10 matrix is a hundred
  /// route calculations and a hundred budget units. It is the operation where
  /// what it looks like —one call— and what it costs are furthest apart.
  ///
  /// The cheap pattern is to filter first: sort by [LatLng.distanceTo], which
  /// is free, keep the first three or four and request the matrix only for
  /// those.
  ///
  /// ## The limit
  ///
  /// Without [routingBoundary], AWS allows 15 origins, 100 destinations and
  /// 100 cells. It is checked before sending and an [ArgumentError] is thrown
  /// with the math already done, instead of letting the service answer `400`.
  Future<RouteMatrix> calculateRouteMatrix({
    required List<LatLng> origins,
    required List<LatLng> destinations,
    TravelMode travelMode = TravelMode.car,
    TravelModeOptions? travelModeOptions,
    LatLngBounds? routingBoundary,
    DateTime? departureTime,
    RouteAvoidance? avoid,
    TrafficUsage traffic = TrafficUsage.useTrafficData,
    RouteOptimization optimizeFor = RouteOptimization.fastestRoute,
  }) async {
    if (origins.isEmpty || destinations.isEmpty) {
      throw ArgumentError(
        'la matriz necesita al menos un origen y un destino.',
      );
    }
    if (routingBoundary == null) {
      final cells = origins.length * destinations.length;
      if (origins.length > maxUnboundedMatrixOrigins ||
          destinations.length > maxUnboundedMatrixDestinations ||
          cells > maxUnboundedMatrixCells) {
        throw ArgumentError(
          'sin acotar la zona el máximo es $maxUnboundedMatrixOrigins '
          'orígenes, $maxUnboundedMatrixDestinations destinos y '
          '$maxUnboundedMatrixCells celdas; se pidieron ${origins.length}×'
          '${destinations.length} = $cells celdas. Pasa `routingBoundary` '
          'para subir el límite, o filtra los candidatos por distancia en '
          'línea recta antes de llamar — eso es gratis y esto cuesta $cells '
          'unidades.',
        );
      }
    }

    final json = await _transport.postJson(
      operation: 'CalculateRouteMatrix',
      service: _service,
      path: '/v2/route-matrix',
      billingUnits: BillingUnits.routeMatrix(
        origins.length,
        destinations.length,
      ),
      body: <String, dynamic>{
        'Origins': origins
            .map((o) => <String, dynamic>{'Position': o.toLonLat()})
            .toList(),
        'Destinations': destinations
            .map((d) => <String, dynamic>{'Position': d.toLonLat()})
            .toList(),
        'TravelMode': travelMode.wireName,
        if (travelModeOptions != null)
          'TravelModeOptions': travelModeOptions.toJson(travelMode),
        'OptimizeRoutingFor': optimizeFor.wireName,
        'Traffic': <String, dynamic>{'Usage': traffic.wireName},
        if (avoid != null && !avoid.isEmpty) 'Avoid': avoid.toJson(),
        if (departureTime != null)
          'DepartureTime': departureTime.toUtc().toIso8601String(),
        'RoutingBoundary': routingBoundary == null
            ? <String, dynamic>{'Unbounded': true}
            : <String, dynamic>{
                'Geometry': <String, dynamic>{
                  'BoundingBox': routingBoundary.toBbox(),
                },
              },
      },
    );

    final matrix = RouteMatrix.fromJson(json);
    if (matrix.originCount != origins.length ||
        matrix.cells.any((row) => row.length != destinations.length)) {
      throw AlsParseExceptionForMatrix(
        expectedOrigins: origins.length,
        expectedDestinations: destinations.length,
        actualOrigins: matrix.originCount,
        actualDestinations: matrix.destinationCount,
      );
    }
    return matrix;
  }

  // ─── 3 · CalculateIsolines ────────────────────────────────────────────

  /// The area reachable within a threshold. `POST /v2/isolines`.
  ///
  /// **Google doesn't have this.** It answers "how far could it get in eight
  /// minutes?" without calculating a thousand routes, and it works in both
  /// directions:
  ///
  /// ```dart
  /// // Outward: how far could it get in 8 minutes?
  /// final zone = await routes.calculateIsolines(
  ///   origin: lastPosition,
  ///   thresholds: Thresholds.time([const Duration(minutes: 8)]),
  ///   travelMode: TravelMode.scooter,
  ///   granularity: const IsolineGranularity(maxPoints: 300),
  /// );
  ///
  /// // Inward: who can get HERE in 10 minutes?
  /// final reach = await routes.calculateIsolines(
  ///   destination: vehiclePosition,
  ///   arrivalTime: DateTime.now().add(const Duration(minutes: 10)),
  ///   thresholds: Thresholds.time([const Duration(minutes: 10)]),
  /// );
  /// ```
  ///
  /// ## Two things you need to know
  ///
  /// **It is billed per threshold**, up to five. Asking for five in one call
  /// is more convenient than five calls, but it costs exactly the same: five
  /// units.
  ///
  /// **[granularity] is mandatory in practice.** Without `maxPoints`, the
  /// thirty-minute polygon comes with several thousand vertices and chokes the
  /// map: the device gets stuck drawing and the UI stops responding. Three
  /// hundred points are more than enough for it to look right.
  ///
  /// [origin] and [destination] are mutually exclusive, and you must give one
  /// of them.
  Future<IsolineResponse> calculateIsolines({
    LatLng? origin,
    LatLng? destination,
    required Thresholds thresholds,
    TravelMode travelMode = TravelMode.car,
    TravelModeOptions? travelModeOptions,
    IsolineGranularity granularity = const IsolineGranularity(maxPoints: 300),
    DateTime? departureTime,
    DateTime? arrivalTime,
    RouteAvoidance? avoid,
    TrafficUsage traffic = TrafficUsage.useTrafficData,
    RouteOptimization optimizeFor = RouteOptimization.fastestRoute,
    GeometryFormat geometryFormat = GeometryFormat.simple,
  }) async {
    if ((origin == null) == (destination == null)) {
      throw ArgumentError(
        'calculateIsolines necesita origin O destination, exactamente uno. '
        'Con origin calcula lo alcanzable DESDE ese punto; con destination, '
        'lo que puede llegar HASTA él.',
      );
    }
    final count = thresholds.count;
    if (count == 0) {
      throw ArgumentError('hay que pedir al menos un umbral.');
    }
    if (count > maxIsolineThresholds) {
      throw ArgumentError(
        'se pidieron $count umbrales y el máximo es $maxIsolineThresholds. '
        'Y ojo: se cobra por umbral, así que $count umbrales son $count '
        'unidades facturables, no una.',
      );
    }

    final json = await _transport.postJson(
      operation: 'CalculateIsolines',
      service: _service,
      path: '/v2/isolines',
      billingUnits: BillingUnits.isolines(count),
      body: <String, dynamic>{
        if (origin != null) 'Origin': origin.toLonLat(),
        if (destination != null) 'Destination': destination.toLonLat(),
        'Thresholds': thresholds.toJson(),
        'TravelMode': travelMode.wireName,
        if (travelModeOptions != null)
          'TravelModeOptions': travelModeOptions.toJson(travelMode),
        'IsolineGranularity': granularity.toJson(),
        'IsolineGeometryFormat': geometryFormat.wireName,
        'OptimizeRoutingFor': optimizeFor.wireName,
        'Traffic': <String, dynamic>{'Usage': traffic.wireName},
        if (avoid != null && !avoid.isEmpty) 'Avoid': avoid.toJson(),
        if (departureTime != null)
          'DepartureTime': departureTime.toUtc().toIso8601String(),
        if (arrivalTime != null)
          'ArrivalTime': arrivalTime.toUtc().toIso8601String(),
      },
    );
    return IsolineResponse.fromJson(json);
  }

  // ─── 4 · SnapToRoads ──────────────────────────────────────────────────

  /// Snaps a GPS trace to the real street. `POST /v2/snap-to-roads`.
  ///
  /// **Google doesn't have this.** It is what turns a cloud of points
  /// zigzagging over the sidewalks into a route that follows the roadway, and
  /// it is the difference between a history you can show a customer and one
  /// that looks like a bug.
  ///
  /// ## The chunking, which is the important part
  ///
  /// The API accepts between 2 and **5,000** points per request. A day's
  /// history goes way past that. This method **chunks and stitches** instead
  /// of failing:
  ///
  /// - it splits the trace into chunks of [maxTracePointsPerRequest];
  /// - it **overlaps [overlapPoints] points** between consecutive chunks, so
  ///   the service has context at the seam and doesn't start each chunk by
  ///   snapping the first point to the wrong street;
  /// - it removes the overlap when joining, so the line doesn't double back
  ///   on itself.
  ///
  /// Each chunk is a billed request: 12,000 points are three units.
  /// [SnapToRoadsResponse.chunkCount] tells you how many there really were.
  ///
  /// ## The data the tracking device already sends
  ///
  /// [TracePoint] accepts heading, speed and time, and **the GT06 sends all
  /// three**. Giving it only positions wastes half the accuracy: with the
  /// speed, the service tells the frontage road apart from the parallel
  /// highway.
  ///
  /// [snapRadiusMeters] is 300 by default and up to 10,000. With poor urban
  /// coverage, 300 falls short; around 500 works better for a GT06 in the
  /// city.
  Future<SnapToRoadsResponse> snapToRoads({
    required List<TracePoint> tracePoints,
    double? snapRadiusMeters,
    TravelMode travelMode = TravelMode.car,
    TravelModeOptions? travelModeOptions,
    GeometryFormat geometryFormat = GeometryFormat.simple,
    int overlapPoints = 10,
  }) async {
    if (tracePoints.length < 2) {
      throw ArgumentError.value(
        tracePoints.length,
        'tracePoints',
        'hacen falta al menos 2 puntos',
      );
    }
    if (snapRadiusMeters != null &&
        (snapRadiusMeters < 0 || snapRadiusMeters > 10000)) {
      throw ArgumentError.value(
        snapRadiusMeters,
        'snapRadiusMeters',
        'admite entre 0 y 10000',
      );
    }
    if (overlapPoints < 0 || overlapPoints >= maxTracePointsPerRequest) {
      throw ArgumentError.value(
        overlapPoints,
        'overlapPoints',
        'debe estar entre 0 y $maxTracePointsPerRequest',
      );
    }

    final chunks = _chunkTrace(tracePoints, overlapPoints);

    Future<SnapToRoadsResponse> sendChunk(List<TracePoint> chunk) async {
      final json = await _transport.postJson(
        operation: 'SnapToRoads',
        service: _service,
        path: '/v2/snap-to-roads',
        body: <String, dynamic>{
          'TracePoints': chunk.map((p) => p.toJson()).toList(),
          'TravelMode': travelMode.wireName,
          if (travelModeOptions != null)
            'TravelModeOptions': travelModeOptions.toJson(travelMode),
          'SnappedGeometryFormat': geometryFormat.wireName,
          if (snapRadiusMeters != null) 'SnapRadius': snapRadiusMeters.round(),
        },
      );
      return SnapToRoadsResponse.fromJson(json);
    }

    if (chunks.length == 1) {
      final single = await sendChunk(chunks.first);
      return SnapToRoadsResponse(
        geometry: single.geometry,
        snappedPoints: single.snappedPoints,
        notices: single.notices,
        pricingBucket: single.pricingBucket,
      );
    }

    // Sequential, not parallel: firing twenty requests at once is the fastest
    // way to run into a 429, and then the whole trace is lost for being in a
    // hurry.
    final points = <LatLng>[];
    final snapped = <SnappedTracePoint>[];
    final notices = <String>[];
    String? pricingBucket;

    for (var i = 0; i < chunks.length; i++) {
      final response = await sendChunk(chunks[i]);
      // The overlap is dropped when stitching: its points already came in the
      // previous chunk, and repeating them draws a line that doubles back.
      final skip = i == 0 ? 0 : overlapPoints;
      points.addAll(response.geometry.points.skip(skip));
      snapped.addAll(response.snappedPoints.skip(skip));
      notices.addAll(response.notices);
      pricingBucket ??= response.pricingBucket;
    }

    return SnapToRoadsResponse(
      geometry: RouteGeometry(points),
      snappedPoints: snapped,
      notices: notices.toSet().toList(growable: false),
      chunkCount: chunks.length,
      pricingBucket: pricingBucket,
    );
  }

  /// Splits the trace into overlapping chunks.
  @visibleForTesting
  static List<List<TracePoint>> chunkTraceForTesting(
    List<TracePoint> points,
    int overlap,
  ) => _chunkTrace(points, overlap);

  static List<List<TracePoint>> _chunkTrace(
    List<TracePoint> points,
    int overlap,
  ) {
    if (points.length <= maxTracePointsPerRequest) {
      return <List<TracePoint>>[points];
    }
    final chunks = <List<TracePoint>>[];
    final step = maxTracePointsPerRequest - overlap;
    var start = 0;
    while (start < points.length) {
      final end = (start + maxTracePointsPerRequest).clamp(0, points.length);
      chunks.add(points.sublist(start, end));
      if (end >= points.length) break;
      start += step;
    }
    return chunks;
  }

  // ─── 5 · OptimizeWaypoints ────────────────────────────────────────────

  /// Reorders the stops to minimize the route.
  /// `POST /v2/optimize-waypoints`.
  ///
  /// **Google doesn't have this** as an operation of its own. It solves the
  /// traveling salesman problem with time windows, service times and the
  /// driver's mandatory rest breaks, which is what a delivery manifest really
  /// needs.
  ///
  /// The result returns **identifiers**, not objects: in
  /// [WaypointOptimizationResponse.orderedIds] is the order in which to
  /// reorder your own list of orders.
  ///
  /// [OptimizationWaypoint.serviceDuration] is the most forgotten field and
  /// the one that changes the result the most: without it, the optimization
  /// plans as if unloading were instantaneous, and a twenty-delivery route
  /// comes out two hours shorter than it really takes.
  Future<WaypointOptimizationResponse> optimizeWaypoints({
    required LatLng origin,
    required List<OptimizationWaypoint> waypoints,
    LatLng? destination,
    TravelMode travelMode = TravelMode.car,
    TravelModeOptions? travelModeOptions,
    DateTime? departureTime,
    WaypointOptimization optimizeFor = WaypointOptimization.fastestRoute,
    RouteAvoidance? avoid,
    TrafficUsage traffic = TrafficUsage.useTrafficData,
    DriverOptions? driver,
  }) async {
    if (waypoints.isEmpty) {
      throw ArgumentError('hay que dar al menos una parada que optimizar.');
    }
    final ids = waypoints.map((w) => w.id).toSet();
    if (ids.length != waypoints.length) {
      throw ArgumentError(
        'los identificadores de parada se repiten. La respuesta los devuelve '
        'reordenados y sin nada más, así que dos paradas con el mismo '
        'identificador son indistinguibles al reconstruir la lista.',
      );
    }
    final reserved = ids.intersection(WaypointOptimizationResponse.reservedIds);
    if (reserved.isNotEmpty) {
      throw ArgumentError.value(
        reserved.join(', '),
        'waypoints',
        'Origin y Destination son los identificadores que el servicio da al '
            'origen y al destino; una parada con ese nombre se confundiría '
            'con ellos',
      );
    }

    final json = await _transport.postJson(
      operation: 'OptimizeWaypoints',
      service: _service,
      path: '/v2/optimize-waypoints',
      body: <String, dynamic>{
        'Origin': origin.toLonLat(),
        if (destination != null) 'Destination': destination.toLonLat(),
        'Waypoints': waypoints.map((w) => w.toJson()).toList(),
        'TravelMode': travelMode.wireName,
        if (travelModeOptions != null)
          'TravelModeOptions': travelModeOptions.toJson(travelMode),
        'OptimizeSequencingFor': optimizeFor.wireName,
        'Traffic': <String, dynamic>{'Usage': traffic.wireName},
        if (avoid != null && !avoid.isEmpty) 'Avoid': avoid.toJson(),
        if (driver != null) 'Driver': driver.toJson(),
        if (departureTime != null)
          'DepartureTime': departureTime.toUtc().toIso8601String(),
      },
    );
    return WaypointOptimizationResponse.fromJson(json);
  }

  // ─── Helpers ──────────────────────────────────────────────────────────

  /// Empties the route cache.
  void clearCache() => _routeCache.clear();

  static String _key(List<Object?> parts) => parts.join('|');
}

/// The matrix arrived with different dimensions from the ones requested.
///
/// It has its own type because the action is different from that of any other
/// parse failure: here the response is syntactically valid and the indices
/// don't mean what you think. Using it anyway would give the wrong vehicle as
/// "the closest one", without any visible symptom.
class AlsParseExceptionForMatrix implements Exception {
  /// Creates the exception with the expected and the received dimensions.
  const AlsParseExceptionForMatrix({
    required this.expectedOrigins,
    required this.expectedDestinations,
    required this.actualOrigins,
    required this.actualDestinations,
  });

  /// How many origins were sent.
  final int expectedOrigins;

  /// How many destinations were sent.
  final int expectedDestinations;

  /// How many rows the response brought.
  final int actualOrigins;

  /// How many columns the response brought.
  final int actualDestinations;

  @override
  String toString() =>
      'AlsParseExceptionForMatrix: se pidió una matriz de '
      '${expectedOrigins}x$expectedDestinations y llegó de '
      '${actualOrigins}x$actualDestinations. Los índices no corresponden con '
      'los orígenes y destinos enviados, así que usarla daría el par '
      'equivocado sin ningún síntoma visible.';
}
