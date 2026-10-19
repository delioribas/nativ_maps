// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/enums.dart';

/// Extra data that can be requested per route leg.
///
/// Each one bloats the response. [tolls] and [summary] are the ones that are
/// almost always worth it; [travelStepInstructions] multiplies the size
/// several times over and is only needed if you are really going to navigate.
enum RouteFeature {
  /// Elevation along the path.
  elevation('Elevation'),

  /// Roadworks, accidents and closures.
  incidents('Incidents'),

  /// The waypoints the route passes through without stopping.
  passThroughWaypoints('PassThroughWaypoints'),

  /// The distance and duration summary of the leg.
  ///
  /// Without this, `Summary.Overview` may be missing and the leg shows up
  /// with zero distance and duration.
  summary('Summary'),

  /// **Tolls with their amount.** This is what Google doesn't give you.
  tolls('Tolls'),

  /// The text of each maneuver.
  travelStepInstructions('TravelStepInstructions'),

  /// The road types for trucks.
  truckRoadTypes('TruckRoadTypes'),

  /// The typical duration of the leg, without traffic.
  ///
  /// Compared with the actual duration it gives the traffic delay, which is
  /// what gets shown as "10 min longer than usual".
  typicalDuration('TypicalDuration'),

  /// Low-emission zones and the like.
  zones('Zones');

  const RouteFeature(this.wireName);

  /// The literal that travels in the JSON.
  final String wireName;
}

/// What to avoid when calculating the route.
///
/// None of these is an absolute ban: if there is no alternative, the service
/// goes through anyway and says so in `RouteResponse.notices`. That is the
/// right call — an impossible route is useless to everyone — but you have to
/// read the notices if the avoidance was truly mandatory.
@immutable
class RouteAvoidance {
  /// Creates the set of avoidances.
  const RouteAvoidance({
    this.tollRoads = false,
    this.tollTransponders = false,
    this.ferries = false,
    this.tunnels = false,
    this.uTurns = false,
    this.dirtRoads = false,
    this.controlledAccessHighways = false,
    this.seasonalClosure = false,
    this.tollGates = false,
  });

  /// Avoid toll roads.
  final bool tollRoads;

  /// Avoid roads that only accept a transponder.
  final bool tollTransponders;

  /// Avoid ferries. Important on coastal routes: a ferry adds hours of waiting
  /// that don't show up in the distance.
  final bool ferries;

  /// Avoid tunnels. This is the avoidance that matters with hazardous goods.
  final bool tunnels;

  /// Avoid U-turns.
  final bool uTurns;

  /// Avoid unpaved roads.
  final bool dirtRoads;

  /// Avoid controlled-access highways.
  final bool controlledAccessHighways;

  /// Avoid roads with seasonal closures.
  final bool seasonalClosure;

  /// Avoid toll gates.
  final bool tollGates;

  /// Was nothing requested to be avoided?
  bool get isEmpty =>
      !tollRoads &&
      !tollTransponders &&
      !ferries &&
      !tunnels &&
      !uTurns &&
      !dirtRoads &&
      !controlledAccessHighways &&
      !seasonalClosure &&
      !tollGates;

  /// The avoidances in the shape the service expects.
  Map<String, dynamic> toJson() => <String, dynamic>{
    if (tollRoads) 'TollRoads': true,
    if (tollTransponders) 'TollTransponders': true,
    if (ferries) 'Ferries': true,
    if (tunnels) 'Tunnels': true,
    if (uTurns) 'UTurns': true,
    if (dirtRoads) 'DirtRoads': true,
    if (controlledAccessHighways) 'ControlledAccessHighways': true,
    if (seasonalClosure) 'SeasonalClosure': true,
    if (tollGates) 'TollGates': true,
  };
}

/// The vehicle's characteristics, which change the route.
///
/// The most noticeable case is the truck: its dimensions and weight make a
/// route that is fine for a car impossible. A bridge with 3.5 m of clearance
/// doesn't show up as closed on the map — the truck simply doesn't fit.
@immutable
class TravelModeOptions {
  /// Truck options.
  const TravelModeOptions.truck({
    this.grossWeightKg,
    this.heightCm,
    this.lengthCm,
    this.widthCm,
    this.axleCount,
    this.trailerCount,
    this.hazardousCargos = const <String>[],
    this.tunnelRestrictionCode,
    this.truckType,
    this.engineType,
    this.occupancy,
    this.licensePlateLastCharacter,
  }) : _kind = TravelMode.truck;

  /// Car options.
  const TravelModeOptions.car({
    this.engineType,
    this.occupancy,
    this.licensePlateLastCharacter,
  }) : _kind = TravelMode.car,
       grossWeightKg = null,
       heightCm = null,
       lengthCm = null,
       widthCm = null,
       axleCount = null,
       trailerCount = null,
       hazardousCargos = const <String>[],
       tunnelRestrictionCode = null,
       truckType = null;

  /// Motorcycle options.
  const TravelModeOptions.scooter({
    this.engineType,
    this.licensePlateLastCharacter,
  }) : _kind = TravelMode.scooter,
       grossWeightKg = null,
       heightCm = null,
       lengthCm = null,
       widthCm = null,
       axleCount = null,
       trailerCount = null,
       hazardousCargos = const <String>[],
       tunnelRestrictionCode = null,
       truckType = null,
       occupancy = null;

  final TravelMode _kind;

  /// Gross weight in kilograms.
  final int? grossWeightKg;

  /// Height in centimeters. The one that decides whether it fits under a
  /// bridge.
  final int? heightCm;

  /// Length in centimeters.
  final int? lengthCm;

  /// Width in centimeters.
  final int? widthCm;

  /// Number of axles. Determines the toll tariff.
  final int? axleCount;

  /// Number of trailers.
  final int? trailerCount;

  /// Hazardous goods: `Explosive`, `Gas`, `Flammable`, `Combustible`,
  /// `Organic`, `Poison`, `Radioactive`, `Corrosive`, `PoisonousInhalation`,
  /// `HarmfulToWater`, `Other`.
  final List<String> hazardousCargos;

  /// Tunnel restriction code, from `B` to `E`.
  final String? tunnelRestrictionCode;

  /// Truck class: `StraightTruck`, `Tractor`, `Trailer`.
  final String? truckType;

  /// Engine type: `Electric`, `Diesel`, `Gasoline`. Changes which low-emission
  /// zones it may enter.
  final String? engineType;

  /// Occupants. Grants access to high-occupancy lanes.
  final int? occupancy;

  /// Last character of the license plate.
  ///
  /// This is what Quito's "pico y placa" needs, along with the equivalent
  /// restrictions in other cities, which depend on that character and on the
  /// day of the week.
  final String? licensePlateLastCharacter;

  /// The options in the shape the service expects for [travelMode].
  ///
  /// They are nested under the mode's key (`Truck`, `Car`, `Scooter`), which
  /// is how the API wants them. If the mode doesn't match the constructor's,
  /// an empty map is returned instead of sending truck options under `Car`,
  /// which would cause a `400`.
  Map<String, dynamic> toJson(TravelMode travelMode) {
    if (travelMode != _kind) return const <String, dynamic>{};

    final options = <String, dynamic>{
      if (grossWeightKg != null) 'GrossWeight': grossWeightKg,
      if (heightCm != null) 'Height': heightCm,
      if (lengthCm != null) 'Length': lengthCm,
      if (widthCm != null) 'Width': widthCm,
      if (axleCount != null) 'AxleCount': axleCount,
      if (trailerCount != null) 'TrailerCount': trailerCount,
      if (hazardousCargos.isNotEmpty) 'HazardousCargos': hazardousCargos,
      if (tunnelRestrictionCode != null)
        'TunnelRestrictionCode': tunnelRestrictionCode,
      if (truckType != null) 'TruckType': truckType,
      if (engineType != null) 'EngineType': engineType,
      if (occupancy != null) 'Occupancy': occupancy,
      if (licensePlateLastCharacter != null)
        'LicensePlate': <String, dynamic>{
          'LastCharacter': licensePlateLastCharacter,
        },
    };
    if (options.isEmpty) return const <String, dynamic>{};
    return <String, dynamic>{_kind.wireName: options};
  }
}

/// The thresholds of an isoline: by time, by distance, or both.
///
/// **Each threshold is billed separately**, and the maximum is five. Asking
/// for five thresholds in one call is more convenient than making five calls,
/// but it costs the same. That is why [count] exists: it is what the budget
/// is going to charge.
@immutable
class Thresholds {
  /// Creates the thresholds.
  const Thresholds({
    this.time = const <Duration>[],
    this.distanceMeters = const <double>[],
  });

  /// Thresholds by time. The usual case: "what is reachable in 8 minutes".
  factory Thresholds.time(List<Duration> durations) =>
      Thresholds(time: durations);

  /// Thresholds by distance traveled **by road**, not in a straight line.
  factory Thresholds.distance(List<double> meters) =>
      Thresholds(distanceMeters: meters);

  /// The time thresholds.
  final List<Duration> time;

  /// The distance thresholds, in meters.
  final List<double> distanceMeters;

  /// How many thresholds there are in total. **This is what gets billed.**
  int get count => time.length + distanceMeters.length;

  /// The thresholds in the shape the service expects.
  Map<String, dynamic> toJson() => <String, dynamic>{
    if (time.isNotEmpty)
      'Time': time.map((d) => d.inSeconds).toList(growable: false),
    if (distanceMeters.isNotEmpty)
      'Distance': distanceMeters.map((m) => m.round()).toList(growable: false),
  };

  @override
  String toString() => 'Thresholds($count umbral(es))';
}

/// How much detail an isoline's polygon has.
///
/// ## Why this is not optional in practice
///
/// Without a limit, the polygon of a thirty-minute isoline comes with several
/// thousand vertices. The map accepts it, tries to draw it, and the UI stops
/// responding — on a mid-range phone, several seconds per repaint. It is not
/// a precision issue: at the scale the isoline is viewed at, three hundred
/// points and three thousand look exactly the same.
///
/// That is why the default value of `calculateIsolines` already comes with
/// `maxPoints` set, instead of leaving it unset and documenting the risk.
@immutable
class IsolineGranularity {
  /// Creates the granularity.
  const IsolineGranularity({this.maxPoints, this.maxResolutionMeters});

  /// Maximum vertices of the polygon. Three hundred work well for drawing.
  final int? maxPoints;

  /// Maximum resolution in meters: the minimum distance between two vertices.
  final int? maxResolutionMeters;

  /// The granularity in the shape the service expects.
  Map<String, dynamic> toJson() => <String, dynamic>{
    if (maxPoints != null) 'MaxPoints': maxPoints,
    if (maxResolutionMeters != null) 'MaxResolution': maxResolutionMeters,
  };
}

/// The driver's mandatory rest breaks, for `optimizeWaypoints`.
///
/// Without this, the optimization plans fourteen-hour shifts in a row. They
/// look gorgeous on the map and they are illegal.
@immutable
class DriverOptions {
  /// Creates the driver options.
  const DriverOptions({this.restProfile, this.treatServiceTimeAs});

  /// The regulatory rest profile, e.g. `EU` or `US`.
  final String? restProfile;

  /// Whether service time counts as rest or as work: `Rest` or `Work`.
  final String? treatServiceTimeAs;

  /// The options in the shape the service expects.
  Map<String, dynamic> toJson() => <String, dynamic>{
    if (restProfile != null)
      'RestProfile': <String, dynamic>{'Profile': restProfile},
    if (treatServiceTimeAs != null) 'TreatServiceTimeAs': treatServiceTimeAs,
  };
}
