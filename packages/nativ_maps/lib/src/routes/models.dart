// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/enums.dart';
import 'package:nativ_maps/src/core/json.dart';
import 'package:nativ_maps/src/core/lat_lng.dart';
import 'package:nativ_maps/src/core/polyline.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  One rule governs this entire file
//
//  **Distances in meters and durations in seconds. Always.** The v2 API has
//  no unit parameter, and sending one —as the v0 generation did with
//  `DistanceUnit`— causes a 400. Since no conversion is possible, there is
//  none to forget either.
//
//  Durations are also exposed as Dart `Duration`, which is what the rest of
//  the language expects.
// ═══════════════════════════════════════════════════════════════════════════

/// The geometry of a leg, whether it comes as a list of points or as a
/// polyline.
///
/// Amazon Location returns one or the other depending on `LegGeometryFormat`,
/// and this type absorbs the difference: [points] always has the points,
/// whatever format was requested.
@immutable
class RouteGeometry {
  /// Creates the geometry from the points.
  const RouteGeometry(this.points, {this.encoded});

  /// Reads the geometry from the response, decoding it if needed.
  ///
  /// An unreadable polyline returns an **empty** geometry instead of throwing:
  /// a route without a line is still usable —distance and duration live
  /// elsewhere— and bringing down the screen because it can't be drawn is
  /// worse. The failure stays visible because [points] comes out empty.
  factory RouteGeometry.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const RouteGeometry(<LatLng>[]);

    final lineString = Json.latLngList(json, 'LineString');
    if (lineString.isNotEmpty) return RouteGeometry(lineString);

    final encoded = Json.string(json, 'Polyline');
    if (encoded != null) {
      try {
        return RouteGeometry(decodeFlexiblePolyline(encoded), encoded: encoded);
      } on FormatException {
        return RouteGeometry(const <LatLng>[], encoded: encoded);
      }
    }
    return const RouteGeometry(<LatLng>[]);
  }

  /// The points of the line, already decoded.
  final List<LatLng> points;

  /// The original string, if it came compressed.
  ///
  /// Keeping it lets you persist the route without re-encoding it and without
  /// losing precision on the round trip.
  final String? encoded;

  /// Could the geometry be read?
  bool get isEmpty => points.isEmpty;

  /// The rectangle enclosing the line, or `null` if it is empty.
  ///
  /// It is what you pass to `fitBounds` to frame the whole route.
  LatLngBounds? get bounds =>
      points.isEmpty ? null : LatLngBounds.fromPoints(points);

  @override
  String toString() => 'RouteGeometry(${points.length} puntos)';
}

/// A navigation step.
@immutable
class TravelStep {
  /// Creates the step.
  const TravelStep({
    required this.distanceMeters,
    required this.duration,
    this.type,
    this.instruction,
    this.geometryOffset,
    this.nextRoad,
    this.currentRoad,
    this.turnAngle,
    this.turnIntensity,
    this.exitNumber,
  });

  /// Reads the step from the service response.
  ///
  /// The angle and the intensity **are not at the root of the step**: each
  /// maneuver type brings them under its own key —`TurnStepDetails`,
  /// `KeepStepDetails`, `UTurnStepDetails`…—. Read from the root they always
  /// came out `null`, without any error.
  factory TravelStep.fromJson(Map<String, dynamic> json) {
    final maneuver = _maneuverDetails(json);
    return TravelStep(
      distanceMeters: Json.numberOrZero(json, 'Distance'),
      duration: Duration(seconds: Json.integer(json, 'Duration') ?? 0),
      type: Json.string(json, 'Type'),
      instruction: Json.string(json, 'Instruction'),
      geometryOffset: Json.integer(json, 'GeometryOffset'),
      nextRoad: _roadName(Json.object(json, 'NextRoad')),
      currentRoad: _roadName(Json.object(json, 'CurrentRoad')),
      turnAngle: Json.number(maneuver, 'TurnAngle'),
      turnIntensity: Json.string(maneuver, 'TurnIntensity'),
      // `ExitNumber` is the exit sign on a highway, as localized text; on a
      // roundabout it is missing and the exit is `RelativeExit`.
      exitNumber:
          Json.objects(json, 'ExitNumber')
              .map((e) => Json.string(e, 'Value'))
              .whereType<String>()
              .firstOrNull ??
          Json.integer(maneuver, 'RelativeExit')?.toString(),
    );
  }

  /// The maneuver details, whatever key they come under.
  static Map<String, dynamic>? _maneuverDetails(Map<String, dynamic> json) {
    for (final entry in json.entries) {
      final value = entry.value;
      if (entry.key.endsWith('StepDetails') && value is Map<String, dynamic>) {
        return value;
      }
    }
    return null;
  }

  static String? _roadName(Map<String, dynamic>? road) {
    if (road == null) return null;
    final names = Json.objects(road, 'RoadName');
    for (final name in names) {
      final value = Json.string(name, 'Value');
      if (value != null) return value;
    }
    return null;
  }

  /// How many meters this step lasts.
  final double distanceMeters;

  /// How long it takes to cover it.
  final Duration duration;

  /// The kind of maneuver: `Turn`, `Continue`, `Roundabout`, `Arrive`…
  final String? type;

  /// The ready-made text, in the request's language.
  ///
  /// Only with `RouteFeature.travelStepInstructions` and
  /// `TravelStepType.standard`.
  final String? instruction;

  /// At which point of [RouteGeometry.points] this step starts.
  ///
  /// It is what lets you highlight the stretch of the current maneuver on the
  /// map without recalculating anything.
  final int? geometryOffset;

  /// The name of the road being turned onto.
  final String? nextRoad;

  /// The name of the current road.
  final String? currentRoad;

  /// The turn angle in degrees.
  final double? turnAngle;

  /// How tight the turn is: `Slight`, `Typical`, `Sharp`.
  final String? turnIntensity;

  /// The exit number, on roundabouts and interchanges.
  final String? exitNumber;

  @override
  String toString() =>
      'TravelStep(${type ?? '?'}, ${distanceMeters.round()} m)';
}

/// A toll on the route.
///
/// **Google doesn't give you this.** It is one of the things that only exist
/// here, and for a delivery app it changes the cost-per-trip calculation.
@immutable
class Toll {
  /// Creates the toll.
  const Toll({
    this.systemRef,
    this.country,
    this.paymentMethods = const <String>[],
    this.currency,
    this.amount,
    this.transponders = const <String>[],
  });

  /// Reads the toll from the service response.
  ///
  /// The amount lives inside `PaymentSites[].Rates[].ConvertedPrice`, not at
  /// the root of the toll: a toll has several rates —per axle, per time of
  /// day, per payment method— and here the first one is taken, which is the
  /// one that applies to the vehicle queried.
  ///
  /// The toll doesn't bring the name of its system, but its **position** in
  /// the leg's `TollSystems` list. [systemNames] is that list; without it,
  /// [systemRef] stays `null`.
  factory Toll.fromJson(
    Map<String, dynamic> json, {
    List<String?> systemNames = const <String?>[],
  }) {
    final rates = Json.objects(json, 'Rates');
    final firstRate = rates.isEmpty ? null : rates.first;
    final price =
        Json.object(firstRate, 'LocalPrice') ??
        Json.object(firstRate, 'ConvertedPrice');
    final systems = json['Systems'];
    final systemIndex = systems is List && systems.isNotEmpty
        ? systems.first
        : null;

    return Toll(
      systemRef: systemIndex is int && systemIndex < systemNames.length
          ? systemNames[systemIndex]
          : null,
      country: Json.string(json, 'Country'),
      paymentMethods: Json.strings(firstRate, 'PaymentMethods'),
      currency: Json.string(price, 'Currency'),
      amount: Json.number(price, 'Value'),
      transponders: Json.objects(firstRate, 'Transponders')
          .map((t) => Json.string(t, 'Name'))
          .whereType<String>()
          .toList(growable: false),
    );
  }

  /// The name of the toll system it belongs to.
  ///
  /// It comes with `RouteFeature.tolls`: AWS returns the leg's toll systems
  /// along with the tolls, and there is no separate feature to request them.
  final String? systemRef;

  /// The country where it is charged.
  final String? country;

  /// How it can be paid: `Cash`, `CreditCard`, `Transponder`…
  final List<String> paymentMethods;

  /// The currency of the amount, in ISO 4217.
  final String? currency;

  /// How much it costs.
  final double? amount;

  /// The accepted transponders, if any.
  final List<String> transponders;

  @override
  String toString() => amount == null
      ? 'Toll(${systemRef ?? '?'})'
      : 'Toll($amount ${currency ?? ''})';
}

/// An incident on the route: roadworks, accident, closure.
@immutable
class RouteIncident {
  /// Creates the incident.
  const RouteIncident({
    this.type,
    this.severity,
    this.description,
    this.startTime,
    this.endTime,
  });

  /// Reads the incident from the service response.
  factory RouteIncident.fromJson(Map<String, dynamic> json) => RouteIncident(
    type: Json.string(json, 'Type'),
    severity: Json.string(json, 'Severity'),
    description: Json.string(json, 'Description'),
    startTime: Json.dateTime(json, 'StartTime'),
    endTime: Json.dateTime(json, 'EndTime'),
  );

  /// What kind of incident it is.
  final String? type;

  /// How severe it is: `Critical`, `High`, `Medium`, `Low`.
  final String? severity;

  /// The human-readable description.
  final String? description;

  /// When it started.
  final DateTime? startTime;

  /// When it is expected to end.
  final DateTime? endTime;

  @override
  String toString() => 'RouteIncident(${type ?? '?'}, ${severity ?? '?'})';
}

/// A leg of the route: the stretch between two consecutive stops.
@immutable
class RouteLeg {
  /// Creates the leg.
  const RouteLeg({
    required this.distanceMeters,
    required this.duration,
    required this.geometry,
    this.travelMode,
    this.type,
    this.travelOnlyDuration,
    this.steps = const <TravelStep>[],
    this.tolls = const <Toll>[],
    this.incidents = const <RouteIncident>[],
    this.departureTime,
    this.arrivalTime,
    this.departurePosition,
    this.arrivalPosition,
  });

  /// Reads the leg from the service response.
  ///
  /// ## Where distance and duration live
  ///
  /// **Not in the leg.** In v2 they are inside the detail block that matches
  /// the travel mode —`VehicleLegDetails`, `PedestrianLegDetails` or
  /// `FerryLegDetails`—, in `Summary.Overview`.
  ///
  /// Reading them from `leg['Distance']`, which is where they were in v0,
  /// doesn't raise an error: it returns **zeros**. A 12 km route that claims
  /// to take 0 seconds goes unnoticed in the code and jumps out on screen.
  factory RouteLeg.fromJson(Map<String, dynamic> json) {
    final details =
        Json.object(json, 'VehicleLegDetails') ??
        Json.object(json, 'PedestrianLegDetails') ??
        Json.object(json, 'FerryLegDetails');
    final summary = Json.object(details, 'Summary');
    final overview = Json.object(summary, 'Overview');
    final travelOnly = Json.object(summary, 'TravelOnly');
    final departure = Json.object(details, 'Departure');
    final arrival = Json.object(details, 'Arrival');
    final tollSystems = Json.objects(
      details,
      'TollSystems',
    ).map((s) => Json.string(s, 'Name')).toList(growable: false);

    return RouteLeg(
      distanceMeters: Json.numberOrZero(overview, 'Distance'),
      duration: Duration(seconds: Json.integer(overview, 'Duration') ?? 0),
      travelOnlyDuration: travelOnly == null
          ? null
          : Duration(seconds: Json.integer(travelOnly, 'Duration') ?? 0),
      geometry: RouteGeometry.fromJson(Json.object(json, 'Geometry')),
      travelMode: Json.enumValue(
        json,
        'TravelMode',
        TravelMode.values,
        (m) => m.wireName,
      ),
      type: Json.string(json, 'Type'),
      steps: Json.objects(
        details,
        'TravelSteps',
      ).map(TravelStep.fromJson).toList(growable: false),
      tolls: Json.objects(details, 'Tolls')
          .map((t) => Toll.fromJson(t, systemNames: tollSystems))
          .toList(growable: false),
      incidents: Json.objects(
        details,
        'Incidents',
      ).map(RouteIncident.fromJson).toList(growable: false),
      departureTime: Json.dateTime(departure, 'Time'),
      arrivalTime: Json.dateTime(arrival, 'Time'),
      departurePosition: Json.latLng(
        Json.object(departure, 'Place'),
        'Position',
      ),
      arrivalPosition: Json.latLng(Json.object(arrival, 'Place'), 'Position'),
    );
  }

  /// Length of the leg in meters.
  final double distanceMeters;

  /// How long it takes, stops included.
  final Duration duration;

  /// How long it takes just driving, without waits or stops.
  ///
  /// The difference from [duration] is the time lost on ferries, customs or
  /// the driver's mandatory rest breaks.
  final Duration? travelOnlyDuration;

  /// The line that draws the leg.
  final RouteGeometry geometry;

  /// How it is traveled.
  final TravelMode? travelMode;

  /// The kind of leg: `Vehicle`, `Pedestrian`, `Ferry`.
  final String? type;

  /// The turn-by-turn steps, if requested.
  final List<TravelStep> steps;

  /// The leg's tolls.
  final List<Toll> tolls;

  /// The incidents, if requested.
  final List<RouteIncident> incidents;

  /// When it departs.
  final DateTime? departureTime;

  /// When it arrives.
  final DateTime? arrivalTime;

  /// Where it departs from.
  final LatLng? departurePosition;

  /// Where it arrives.
  final LatLng? arrivalPosition;

  /// The total cost of the leg's tolls, by currency.
  ///
  /// It returns a map and not a number because an international route crosses
  /// currencies, and adding them up would give a meaningless number.
  Map<String, double> get tollCostByCurrency {
    final totals = <String, double>{};
    for (final toll in tolls) {
      final currency = toll.currency;
      final amount = toll.amount;
      if (currency == null || amount == null) continue;
      totals[currency] = (totals[currency] ?? 0) + amount;
    }
    return totals;
  }

  @override
  String toString() =>
      'RouteLeg(${(distanceMeters / 1000).toStringAsFixed(1)} km, '
      '${duration.inMinutes} min)';
}

/// A complete route between an origin and a destination.
@immutable
class Route {
  /// Creates the route.
  const Route({
    required this.distanceMeters,
    required this.duration,
    required this.legs,
    this.majorRoadLabels = const <String>[],
  });

  /// Reads the route from the service response.
  factory Route.fromJson(Map<String, dynamic> json) {
    final summary = Json.object(json, 'Summary');
    final legs = Json.objects(
      json,
      'Legs',
    ).map(RouteLeg.fromJson).toList(growable: false);

    // If the summary is missing, it is built by adding up the legs. Better
    // than returning zero: the sum is exact, it only costs walking the list.
    final distance =
        Json.number(summary, 'Distance') ??
        legs.fold<double>(0, (sum, leg) => sum + leg.distanceMeters);
    final seconds =
        Json.integer(summary, 'Duration') ??
        legs.fold<int>(0, (sum, leg) => sum + leg.duration.inSeconds);

    return Route(
      distanceMeters: distance,
      duration: Duration(seconds: seconds),
      legs: legs,
      majorRoadLabels: Json.objects(json, 'MajorRoadLabels')
          .map((r) => Json.string(Json.object(r, 'RoadName'), 'Value'))
          .whereType<String>()
          .toList(growable: false),
    );
  }

  /// Total length in meters.
  final double distanceMeters;

  /// Total duration.
  final Duration duration;

  /// The legs, in order.
  final List<RouteLeg> legs;

  /// The major roads it goes along.
  ///
  /// It is what tells two alternatives apart for whoever is looking: "via the
  /// Panamericana" versus "via the Simón Bolívar" says much more than
  /// "43 min" versus "45 min".
  final List<String> majorRoadLabels;

  /// All the points of the route, from every leg, in a single stroke.
  ///
  /// It is what you pass to a `Polyline` to draw it in one go. The first point
  /// of every leg except the first is dropped, because it matches the last
  /// point of the previous one and duplicating it leaves a visible artifact
  /// on rounded line caps.
  List<LatLng> get points {
    final all = <LatLng>[];
    for (final leg in legs) {
      final points = leg.geometry.points;
      if (points.isEmpty) continue;
      all.addAll(all.isEmpty ? points : points.skip(1));
    }
    return all;
  }

  /// The rectangle enclosing the whole route, or `null` if there is no
  /// geometry.
  LatLngBounds? get bounds {
    final all = points;
    return all.isEmpty ? null : LatLngBounds.fromPoints(all);
  }

  /// All the steps, from every leg, in order.
  List<TravelStep> get steps => <TravelStep>[
    for (final leg in legs) ...leg.steps,
  ];

  /// All the tolls on the route.
  List<Toll> get tolls => <Toll>[for (final leg in legs) ...leg.tolls];

  /// The total toll cost, by currency.
  Map<String, double> get tollCostByCurrency {
    final totals = <String, double>{};
    for (final leg in legs) {
      leg.tollCostByCurrency.forEach((currency, amount) {
        totals[currency] = (totals[currency] ?? 0) + amount;
      });
    }
    return totals;
  }

  /// The tolls in [currency], in **minor units**: cents with the default two
  /// decimals, or whatever [minorUnitDigits] says (0 for CLP or JPY).
  ///
  /// It is the unit that `Tariff`, `PriceAdvisor` and `BidAdvisor` expect.
  /// [tollCostByCurrency] gives major units —`0.4` dollars—, and rounding
  /// that value as is, which is the easy mistake, turns a 0.40 toll into
  /// zero.
  int tollCostInMinorUnits(String currency, {int minorUnitDigits = 2}) =>
      ((tollCostByCurrency[currency] ?? 0) * math.pow(10, minorUnitDigits))
          .round();

  /// The distance in kilometers, rounded to one decimal.
  double get distanceKm => distanceMeters / 1000.0;

  @override
  String toString() =>
      'Route(${distanceKm.toStringAsFixed(1)} km, ${duration.inMinutes} min, '
      '${legs.length} tramo(s))';
}

/// The response of `calculateRoutes`.
@immutable
class RouteResponse {
  /// Creates the response.
  const RouteResponse({
    required this.routes,
    this.notices = const <String>[],
    this.pricingBucket,
  });

  /// Reads the service response.
  factory RouteResponse.fromJson(Map<String, dynamic> json) => RouteResponse(
    routes: Json.objects(
      json,
      'Routes',
    ).map(Route.fromJson).toList(growable: false),
    notices: Json.objects(json, 'Notices')
        .map((n) => Json.string(n, 'Code'))
        .whereType<String>()
        .toList(growable: false),
    pricingBucket: Json.string(json, 'PricingBucket'),
  );

  /// The routes, with the preferred one first.
  final List<Route> routes;

  /// Service notices: restriction violations, estimated legs.
  ///
  /// A notice doesn't prevent using the route, but it does explain why it is
  /// odd. The most common one is that the route crosses a road forbidden for
  /// the truck's dimensions because there was no alternative.
  final List<String> notices;

  /// The pricing bucket AWS applied.
  final String? pricingBucket;

  /// The preferred route, or `null` if the service didn't find any.
  Route? get best => routes.isEmpty ? null : routes.first;

  /// Was there any route?
  bool get isEmpty => routes.isEmpty;

  @override
  String toString() => 'RouteResponse(${routes.length} ruta(s))';
}

/// A cell of the origin-destination matrix.
///
/// This used to be a bare `double` with the distance. The v2 API also returns
/// the duration and a possible error **per cell**, and discarding them forces
/// you to request the matrix again to know how long it takes — at the price
/// of a whole matrix.
@immutable
class MatrixCell {
  /// Creates the cell.
  const MatrixCell({
    required this.distanceMeters,
    required this.duration,
    this.error,
  });

  /// Reads the cell from the service response.
  factory MatrixCell.fromJson(Map<String, dynamic> json) => MatrixCell(
    distanceMeters: Json.numberOrZero(json, 'Distance'),
    duration: Duration(seconds: Json.integer(json, 'Duration') ?? 0),
    error: Json.string(json, 'Error'),
  );

  /// Road distance in meters.
  final double distanceMeters;

  /// Driving time.
  final Duration duration;

  /// Why this pair couldn't be calculated, if it couldn't.
  final String? error;

  /// Was it calculated correctly?
  ///
  /// Check it before using the numbers: a cell with an error holds zeros, and
  /// a zero is a perfectly believable value for "the closest one".
  bool get isValid => error == null;

  @override
  String toString() => isValid
      ? 'MatrixCell(${distanceMeters.round()} m, ${duration.inSeconds} s)'
      : 'MatrixCell(error: $error)';
}

/// The response of `calculateRouteMatrix`.
@immutable
class RouteMatrix {
  /// Creates the matrix.
  const RouteMatrix({
    required this.cells,
    this.errorCount = 0,
    this.pricingBucket,
  });

  /// Reads the matrix from the service response.
  factory RouteMatrix.fromJson(Map<String, dynamic> json) {
    final raw = json['RouteMatrix'];
    final rows = <List<MatrixCell>>[];
    if (raw is List) {
      for (final row in raw) {
        if (row is! List) continue;
        rows.add(
          row
              .whereType<Map<String, dynamic>>()
              .map(MatrixCell.fromJson)
              .toList(growable: false),
        );
      }
    }
    return RouteMatrix(
      cells: List<List<MatrixCell>>.unmodifiable(rows),
      errorCount: Json.integer(json, 'ErrorCount') ?? 0,
      pricingBucket: Json.string(json, 'PricingBucket'),
    );
  }

  /// The cells: `cells[origin][destination]`.
  final List<List<MatrixCell>> cells;

  /// How many cells couldn't be calculated.
  final int errorCount;

  /// The pricing bucket AWS applied.
  final String? pricingBucket;

  /// How many origins it has.
  int get originCount => cells.length;

  /// How many destinations it has.
  int get destinationCount => cells.isEmpty ? 0 : cells.first.length;

  /// The cell for the given pair.
  MatrixCell cell(int origin, int destination) => cells[origin][destination];

  /// The index of the destination closest to [origin] **by road**.
  ///
  /// This is the matrix's reason to exist: the closest unit in a straight line
  /// may be on the other side of a river with no bridge. Returns `null` if no
  /// cell in that row could be calculated.
  int? nearestDestination(int origin, {bool byDuration = true}) {
    var bestIndex = -1;
    var bestValue = double.infinity;
    final row = cells[origin];
    for (var i = 0; i < row.length; i++) {
      final cell = row[i];
      if (!cell.isValid) continue;
      final value = byDuration
          ? cell.duration.inSeconds.toDouble()
          : cell.distanceMeters;
      if (value < bestValue) {
        bestValue = value;
        bestIndex = i;
      }
    }
    return bestIndex < 0 ? null : bestIndex;
  }

  @override
  String toString() =>
      'RouteMatrix(${originCount}x$destinationCount'
      '${errorCount > 0 ? ', $errorCount con error' : ''})';
}

/// An isoline: the polygon of what is reachable within a threshold.
///
/// **Google doesn't have this.** It is the operation that answers "how far
/// could it get in eight minutes?" without calculating a thousand routes.
@immutable
class Isoline {
  /// Creates the isoline.
  const Isoline({
    required this.polygons,
    this.distanceThresholdMeters,
    this.timeThreshold,
  });

  /// Reads the isoline from the service response.
  ///
  /// An isoline can bring **several polygons**: in a city with a river and no
  /// bridges nearby, what is reachable is two separate patches. Flattening
  /// that into a single polygon would join both banks with a straight line
  /// across the water, drawing as reachable exactly what isn't.
  factory Isoline.fromJson(Map<String, dynamic> json) {
    final polygons = <List<List<LatLng>>>[];

    for (final geometry in Json.objects(json, 'Geometries')) {
      final polygon = geometry['Polygon'];
      if (polygon is List) {
        final rings = <List<LatLng>>[];
        for (final ring in polygon) {
          if (ring is! List) continue;
          final points = <LatLng>[];
          for (final coordinate in ring) {
            if (coordinate is! List || coordinate.length < 2) continue;
            try {
              points.add(LatLng.fromLonLat(coordinate));
            } on FormatException {
              continue;
            } on ArgumentError {
              continue;
            }
          }
          if (points.isNotEmpty) rings.add(points);
        }
        if (rings.isNotEmpty) polygons.add(rings);
        continue;
      }

      final encodedRings = geometry['PolylinePolygon'];
      if (encodedRings is List) {
        final rings = <List<LatLng>>[];
        for (final encoded in encodedRings.whereType<String>()) {
          try {
            final points = decodeFlexiblePolyline(encoded);
            if (points.isNotEmpty) rings.add(points);
          } on FormatException {
            continue;
          }
        }
        if (rings.isNotEmpty) polygons.add(rings);
      }
    }

    final seconds = Json.integer(json, 'TimeThreshold');
    return Isoline(
      polygons: polygons,
      distanceThresholdMeters: Json.number(json, 'DistanceThreshold'),
      timeThreshold: seconds == null ? null : Duration(seconds: seconds),
    );
  }

  /// The polygons. Each one is a list of rings: the first is the outline and
  /// the rest are the holes.
  final List<List<List<LatLng>>> polygons;

  /// This isoline's distance threshold, if requested by distance.
  final double? distanceThresholdMeters;

  /// The time threshold, if requested by time.
  final Duration? timeThreshold;

  /// The outline of the main polygon, which is what gets drawn almost always.
  List<LatLng> get outerRing => polygons.isEmpty || polygons.first.isEmpty
      ? const <LatLng>[]
      : polygons.first.first;

  /// How many points it has in total.
  ///
  /// Useful to check that `granularity` is doing its job: a thirty-minute
  /// isoline without a point limit comes with several thousand and chokes the
  /// map.
  int get pointCount => polygons.fold(
    0,
    (sum, polygon) => sum + polygon.fold<int>(0, (s, ring) => s + ring.length),
  );

  @override
  String toString() =>
      'Isoline(${polygons.length} polígono(s), '
      '$pointCount puntos, ${timeThreshold ?? distanceThresholdMeters})';
}

/// The response of `calculateIsolines`.
@immutable
class IsolineResponse {
  /// Creates the response.
  const IsolineResponse({
    required this.isolines,
    this.snappedOrigin,
    this.snappedDestination,
    this.departureTime,
    this.arrivalTime,
    this.pricingBucket,
  });

  /// Reads the service response.
  factory IsolineResponse.fromJson(Map<String, dynamic> json) =>
      IsolineResponse(
        isolines: Json.objects(
          json,
          'Isolines',
        ).map(Isoline.fromJson).toList(growable: false),
        snappedOrigin: Json.latLng(json, 'SnappedOrigin'),
        snappedDestination: Json.latLng(json, 'SnappedDestination'),
        departureTime: Json.dateTime(json, 'DepartureTime'),
        arrivalTime: Json.dateTime(json, 'ArrivalTime'),
        pricingBucket: Json.string(json, 'PricingBucket'),
      );

  /// The isolines, one per requested threshold.
  final List<Isoline> isolines;

  /// The origin snapped to the nearest road.
  ///
  /// If it is far from the one requested, the starting position fell outside
  /// the road network and the whole calculation starts from somewhere else.
  final LatLng? snappedOrigin;

  /// The destination snapped to the road, in arrival mode.
  final LatLng? snappedDestination;

  /// The departure time used in the calculation.
  final DateTime? departureTime;

  /// The arrival time used, in reverse mode.
  final DateTime? arrivalTime;

  /// The pricing bucket AWS applied.
  final String? pricingBucket;

  @override
  String toString() => 'IsolineResponse(${isolines.length} isócrona(s))';
}

/// A point of a GPS trace, as sent to `snapToRoads`.
///
/// The GT06 and most tracking devices send heading, speed and time along with
/// the position. **Giving it only the position wastes half the accuracy** of
/// the operation: with speed and heading, the service can tell the frontage
/// road apart from the parallel highway.
@immutable
class TracePoint {
  /// Creates the trace point.
  const TracePoint({
    required this.position,
    this.headingDegrees,
    this.speedKmh,
    this.timestamp,
  });

  /// Where the GPS said it was.
  final LatLng position;

  /// The heading in degrees, 0 = north.
  final double? headingDegrees;

  /// The speed **in kilometers per hour**.
  ///
  /// It is the only quantity in the whole package that is not in SI units,
  /// and not by choice: the API asks for it that way.
  final double? speedKmh;

  /// When it was recorded.
  final DateTime? timestamp;

  /// The point in the shape the service expects.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'Position': position.toLonLat(),
    if (headingDegrees != null) 'Heading': headingDegrees,
    if (speedKmh != null) 'Speed': speedKmh,
    if (timestamp != null) 'Timestamp': timestamp!.toUtc().toIso8601String(),
  };

  @override
  String toString() => 'TracePoint($position)';
}

/// A trace point already snapped to the street.
@immutable
class SnappedTracePoint {
  /// Creates the snapped point.
  const SnappedTracePoint({
    required this.snappedPosition,
    this.originalPosition,
    this.confidence,
  });

  /// Reads the point from the service response, or `null` if it has no
  /// position.
  static SnappedTracePoint? fromJson(Map<String, dynamic> json) {
    final snapped = Json.latLng(json, 'SnappedPosition');
    if (snapped == null) return null;
    return SnappedTracePoint(
      snappedPosition: snapped,
      originalPosition: Json.latLng(json, 'OriginalPosition'),
      confidence: Json.number(json, 'Confidence'),
    );
  }

  /// The position on the street.
  final LatLng snappedPosition;

  /// The raw position the GPS sent.
  final LatLng? originalPosition;

  /// How sure the service is about this point, between 0 and 1.
  ///
  /// It is what lets you **discard the doubtful ones** instead of drawing a
  /// made-up street. With poor coverage, a point with 0.2 confidence snapped
  /// to a parallel avenue produces a trace that looks right and isn't.
  final double? confidence;

  /// How far the point moved when snapped, in meters.
  ///
  /// A large displacement with low confidence is the clear sign that
  /// `snapRadius` fell short or that there was no street there.
  double? get displacementMeters =>
      originalPosition?.distanceTo(snappedPosition);

  @override
  String toString() =>
      'SnappedTracePoint($snappedPosition'
      '${confidence == null ? '' : ', conf. $confidence'})';
}

/// The response of `snapToRoads`.
@immutable
class SnapToRoadsResponse {
  /// Creates the response.
  const SnapToRoadsResponse({
    required this.geometry,
    this.snappedPoints = const <SnappedTracePoint>[],
    this.notices = const <String>[],
    this.chunkCount = 1,
    this.pricingBucket,
  });

  /// Reads the service response.
  factory SnapToRoadsResponse.fromJson(Map<String, dynamic> json) =>
      SnapToRoadsResponse(
        geometry: RouteGeometry.fromJson(Json.object(json, 'SnappedGeometry')),
        snappedPoints: Json.objects(json, 'SnappedTracePoints')
            .map(SnappedTracePoint.fromJson)
            .whereType<SnappedTracePoint>()
            .toList(growable: false),
        notices: Json.objects(json, 'Notices')
            .map((n) => Json.string(n, 'Code'))
            .whereType<String>()
            .toList(growable: false),
        pricingBucket: Json.string(json, 'PricingBucket'),
      );

  /// The line snapped to the street, ready to draw.
  final RouteGeometry geometry;

  /// The points, one for each of those sent.
  final List<SnappedTracePoint> snappedPoints;

  /// Service notices.
  final List<String> notices;

  /// How many requests the trace was chunked into.
  ///
  /// It is what was really billed: a 12,000-point history is three requests,
  /// even though the caller wrote a single line.
  final int chunkCount;

  /// The pricing bucket AWS applied.
  final String? pricingBucket;

  /// The points whose confidence reaches [minimum].
  ///
  /// The rest of the points should not be drawn as the route: they are points
  /// the service snapped to a street without being sure.
  List<SnappedTracePoint> confidentPoints({double minimum = 0.5}) =>
      snappedPoints
          .where((p) => (p.confidence ?? 1.0) >= minimum)
          .toList(growable: false);

  @override
  String toString() =>
      'SnapToRoadsResponse(${snappedPoints.length} puntos, '
      '$chunkCount petición(es))';
}

/// A stop to visit, for `optimizeWaypoints`.
@immutable
class OptimizationWaypoint {
  /// Creates the stop.
  const OptimizationWaypoint({
    required this.id,
    required this.position,
    this.serviceDuration,
    this.appointmentTime,
    this.before = const <String>[],
    this.headingDegrees,
    this.sideOfStreet,
  });

  /// The identifier it comes back with in the result.
  ///
  /// It is how you recover the order, the customer or the work order behind
  /// it: the response brings the reordered identifiers, not the objects.
  final String id;

  /// Where it is.
  final LatLng position;

  /// How long it takes to service it.
  ///
  /// Without this, the optimization plans as if unloading were instantaneous,
  /// and a twenty-delivery route comes out two hours shorter than it really
  /// takes.
  final Duration? serviceDuration;

  /// The time of a scheduled appointment.
  final DateTime? appointmentTime;

  /// Identifiers of stops that must be visited **after** this one.
  ///
  /// It is how you express "pick up before delivering" without fixing the
  /// whole order.
  final List<String> before;

  /// The heading to arrive with, if it matters.
  final double? headingDegrees;

  /// Which side of the street it is on: `Left`, `Right`, `Any`.
  final String? sideOfStreet;

  /// The stop in the shape the service expects.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'Id': id,
    'Position': position.toLonLat(),
    if (serviceDuration != null) 'ServiceDuration': serviceDuration!.inSeconds,
    if (appointmentTime != null)
      'AppointmentTime': appointmentTime!.toUtc().toIso8601String(),
    if (before.isNotEmpty) 'Before': before,
    if (headingDegrees != null) 'Heading': headingDegrees,
    if (sideOfStreet != null)
      'SideOfStreet': <String, dynamic>{'Position': position.toLonLat()},
  };
}

/// A stop already placed in its slot within the optimal route.
@immutable
class OptimizedWaypoint {
  /// Creates the optimized stop.
  const OptimizedWaypoint({
    required this.id,
    this.position,
    this.arrivalTime,
    this.departureTime,
  });

  /// Reads the stop from the service response.
  factory OptimizedWaypoint.fromJson(Map<String, dynamic> json) =>
      OptimizedWaypoint(
        id: Json.string(json, 'Id') ?? '',
        position: Json.latLng(json, 'Position'),
        arrivalTime: Json.dateTime(json, 'ArrivalTime'),
        departureTime: Json.dateTime(json, 'DepartureTime'),
      );

  /// The identifier given when it was sent.
  final String id;

  /// Where it is.
  final LatLng? position;

  /// What time it arrives.
  final DateTime? arrivalTime;

  /// What time it departs.
  final DateTime? departureTime;

  @override
  String toString() => 'OptimizedWaypoint($id)';
}

/// The connection between two consecutive stops of the optimal route.
@immutable
class WaypointConnection {
  /// Creates the connection.
  const WaypointConnection({
    required this.fromId,
    required this.toId,
    required this.distanceMeters,
    required this.duration,
    this.restDuration,
    this.waitDuration,
  });

  /// Reads the connection from the service response.
  factory WaypointConnection.fromJson(
    Map<String, dynamic> json,
  ) => WaypointConnection(
    fromId: Json.string(json, 'From') ?? '',
    toId: Json.string(json, 'To') ?? '',
    distanceMeters: Json.numberOrZero(json, 'Distance'),
    // It is called `TravelDuration`, not `Duration` as at the root of the
    // response. Read as `Duration` it always came out zero.
    duration: Duration(seconds: Json.integer(json, 'TravelDuration') ?? 0),
    restDuration: Duration(seconds: Json.integer(json, 'RestDuration') ?? 0),
    waitDuration: Duration(seconds: Json.integer(json, 'WaitDuration') ?? 0),
  );

  /// Which stop it leaves from.
  final String fromId;

  /// Which stop it arrives at.
  final String toId;

  /// How many meters there are.
  final double distanceMeters;

  /// How long it takes driving.
  final Duration duration;

  /// The driver's mandatory rest break on this stretch.
  final Duration? restDuration;

  /// Wait until the destination's time window opens.
  ///
  /// A long wait is the sign that the appointments are badly spread: the
  /// driver arrives early and sits idle.
  final Duration? waitDuration;

  @override
  String toString() => 'WaypointConnection($fromId → $toId)';
}

/// The response of `optimizeWaypoints`.
@immutable
class WaypointOptimizationResponse {
  /// Creates the response.
  const WaypointOptimizationResponse({
    required this.waypoints,
    required this.distanceMeters,
    required this.duration,
    this.connections = const <WaypointConnection>[],
    this.impedingWaypointIds = const <String>[],
    this.pricingBucket,
  });

  /// Reads the service response.
  factory WaypointOptimizationResponse.fromJson(Map<String, dynamic> json) =>
      WaypointOptimizationResponse(
        waypoints: Json.objects(
          json,
          'OptimizedWaypoints',
        ).map(OptimizedWaypoint.fromJson).toList(growable: false),
        distanceMeters: Json.numberOrZero(json, 'Distance'),
        duration: Duration(seconds: Json.integer(json, 'Duration') ?? 0),
        connections: Json.objects(
          json,
          'Connections',
        ).map(WaypointConnection.fromJson).toList(growable: false),
        impedingWaypointIds: Json.objects(json, 'ImpedingWaypoints')
            .map((w) => Json.string(w, 'Id'))
            .whereType<String>()
            .toList(growable: false),
        pricingBucket: Json.string(json, 'PricingBucket'),
      );

  /// The stops **in the order they must be visited**.
  final List<OptimizedWaypoint> waypoints;

  /// Total distance of the route.
  final double distanceMeters;

  /// Total duration, waits and service times included.
  final Duration duration;

  /// The connections between consecutive stops.
  final List<WaypointConnection> connections;

  /// The stops the service couldn't fit in.
  ///
  /// Usually they are the ones with an appointment that is impossible to
  /// keep. They come separately and not mixed into the order because someone
  /// has to be shown them: they are the ones to reschedule.
  final List<String> impedingWaypointIds;

  /// The pricing bucket AWS applied.
  final String? pricingBucket;

  /// The order of **your** stops, ready to reorder your own list.
  ///
  /// [waypoints] also includes the origin and the destination, with the
  /// identifiers `Origin` and `Destination` and their departure and arrival
  /// times. They are not here: they are not yours, and looking them up in
  /// your list would fail.
  List<String> get orderedIds => waypoints
      .map((w) => w.id)
      .where((id) => !reservedIds.contains(id))
      .toList(growable: false);

  /// The identifiers the service reserves for the origin and the destination.
  static const Set<String> reservedIds = <String>{'Origin', 'Destination'};

  @override
  String toString() =>
      'WaypointOptimizationResponse('
      '${waypoints.length} paradas, ${duration.inMinutes} min)';
}
