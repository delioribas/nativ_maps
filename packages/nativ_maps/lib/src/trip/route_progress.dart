// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/lat_lng.dart';
import 'package:nativ_maps/src/routes/models.dart';
import 'package:nativ_maps/src/trip/geodesy.dart';

/// Where the vehicle is along a calculated route.
@immutable
@experimental
class RouteProgress {
  /// Creates a progress.
  const RouteProgress({
    required this.match,
    required this.traveledMeters,
    required this.remainingMeters,
    required this.remainingDuration,
    required this.eta,
    required this.offRoute,
    required this.stepIndex,
    required this.currentStep,
    required this.nextStep,
    required this.distanceToNextManeuverMeters,
  });

  /// The point on the route the position was snapped to.
  final PathMatch match;

  /// How much route lies behind, in meters.
  final double traveledMeters;

  /// How much route lies ahead, in meters.
  final double remainingMeters;

  /// How much time is left, based on the times the service gave for each
  /// maneuver.
  final Duration remainingDuration;

  /// The estimated time of arrival.
  final DateTime eta;

  /// Is it off the route?
  ///
  /// A single bad reading does not trigger it: several in a row have to land
  /// far away. See `RouteTracker.offRouteStrikes`.
  final bool offRoute;

  /// The index of the current maneuver within `Route.steps`.
  final int stepIndex;

  /// The current maneuver, if the route carries instructions.
  final TravelStep? currentStep;

  /// The next maneuver.
  final TravelStep? nextStep;

  /// How many meters are left until the next maneuver.
  final double? distanceToNextManeuverMeters;

  /// How much of the route has been covered, between 0 and 1.
  double get fraction => match.fraction;

  /// How far the vehicle is from the route, in meters.
  double get deviationMeters => match.distanceMeters;

  @override
  String toString() =>
      'RouteProgress(${(fraction * 100).round()} %, faltan '
      '${(remainingMeters / 1000).toStringAsFixed(1)} km / '
      '${remainingDuration.inMinutes} min'
      '${offRoute ? ', FUERA DE RUTA' : ''})';
}

/// Follows a vehicle along a route, **without spending requests**.
///
/// ```dart
/// final tracker = RouteTracker(response.best!);
/// // ...for each GPS position:
/// final progress = tracker.update(position);
/// if (progress.offRoute) await recalculateRoute();
/// ```
///
/// ## Why the remaining time is not proportional to the distance
///
/// The easy way to estimate what is left is `duration × (1 − fraction)`. It is
/// wrong as soon as the route mixes road types: if 20 of the 25 km are left,
/// but those 20 are highway and the 5 already covered were city, that formula
/// says twice as long as it will actually take.
///
/// Here the time the service gave **for each maneuver** is used: the
/// proportional part of the current maneuver is consumed and the remaining
/// ones are added in full. If the route comes without instructions
/// —`RouteFeature.travelStepInstructions` was not requested— it falls back to
/// the proportional split, which is all that is left.
///
/// ## Why there is hysteresis on the deviation
///
/// A single bad reading puts the car 80 m from its lane. Recalculating the
/// route there is a billed request thrown away, and on a street with tall
/// buildings it happens several times a minute. It takes [offRouteStrikes]
/// readings in a row far from the route to accept it.
@experimental
class RouteTracker {
  /// Creates a tracker over a route.
  ///
  /// Throws [ArgumentError] if the route has no geometry: without points there
  /// is nothing to project onto.
  RouteTracker(
    this.route, {
    this.offRouteThresholdMeters = 45,
    this.offRouteStrikes = 3,
    this.searchWindowSegments = 60,
  }) : _path = route.points {
    if (_path.length < 2) {
      throw ArgumentError.value(
        route,
        'route',
        'The route carries no geometry: request RouteFeature with geometry, '
            'or use a response that includes it',
      );
    }
    _cumulative = cumulativeDistances(_path);
    _stepEnds = _accumulateSteps();
  }

  /// The route being followed.
  final Route route;

  /// How many meters away the vehicle has to be to count as having left.
  ///
  /// 45 m allows for the width of an avenue with side lanes and the typical
  /// error of a phone in a city. For highways it can be raised to 80.
  final double offRouteThresholdMeters;

  /// How many readings in a row far away it takes to accept the deviation.
  final int offRouteStrikes;

  /// How many segments are looked at ahead of the last match.
  ///
  /// It avoids walking a route of thousands of points on every position. If
  /// the best result within the window is far away, the search is repeated
  /// over the whole route: that is what rescues the vehicle after a tunnel.
  final int searchWindowSegments;

  final List<LatLng> _path;
  late final List<double> _cumulative;
  late final List<double> _stepEnds;

  int _lastSegment = 0;
  int _strikes = 0;
  bool _offRoute = false;

  /// Is it off the route right now?
  bool get isOffRoute => _offRoute;

  /// The length of the route geometry, in meters.
  double get pathLengthMeters => _cumulative.last;

  /// Searches the whole route again on the next call.
  ///
  /// Call it after a long pause without positions, or when the app resumes:
  /// the search window assumes continuity.
  void resync() {
    _lastSegment = 0;
    _strikes = 0;
    _offRoute = false;
  }

  /// Computes the progress for a position.
  RouteProgress update(LatLng position, {DateTime? now}) {
    var match = nearestPointOnPath(
      _path,
      position,
      fromIndex: _lastSegment,
      maxSegments: searchWindowSegments,
      cumulative: _cumulative,
    );

    // If there is nothing close within the window, it may be a real deviation
    // or the vehicle may have reappeared far away. Check the whole route
    // before declaring anything.
    if (match.distanceMeters > offRouteThresholdMeters) {
      final fullScan = nearestPointOnPath(
        _path,
        position,
        cumulative: _cumulative,
      );
      if (fullScan.distanceMeters < match.distanceMeters) {
        match = fullScan;
      }
    }

    _lastSegment = match.segmentIndex;

    if (match.distanceMeters > offRouteThresholdMeters) {
      _strikes++;
      if (_strikes >= offRouteStrikes) _offRoute = true;
    } else {
      _strikes = 0;
      _offRoute = false;
    }

    final metersLeft = math.max(0.0, _cumulative.last - match.alongMeters);
    final timeLeft = _remainingFrom(match.alongMeters);
    final moment = now ?? DateTime.now();

    final (index, current, next, toManeuver) = _maneuversAt(match.alongMeters);

    return RouteProgress(
      match: match,
      traveledMeters: match.alongMeters,
      remainingMeters: metersLeft,
      remainingDuration: timeLeft,
      eta: moment.add(timeLeft),
      offRoute: _offRoute,
      stepIndex: index,
      currentStep: current,
      nextStep: next,
      distanceToNextManeuverMeters: toManeuver,
    );
  }

  /// Cumulative distance at the end of each maneuver.
  ///
  /// It is scaled so the sum matches the real length of the geometry: both
  /// figures come from the service and differ by a few meters due to
  /// rounding, and without scaling the progress goes out of step at the end.
  List<double> _accumulateSteps() {
    final steps = route.steps;
    if (steps.isEmpty) return const <double>[];
    final total = steps.fold<double>(0, (s, p) => s + p.distanceMeters);
    if (total <= 0) return const <double>[];
    final scale = _cumulative.last / total;
    final ends = <double>[];
    var cumulative = 0.0;
    for (final step in steps) {
      cumulative += step.distanceMeters * scale;
      ends.add(cumulative);
    }
    return ends;
  }

  Duration _remainingFrom(double travelled) {
    final steps = route.steps;
    if (steps.isEmpty || _stepEnds.isEmpty) {
      // Without instructions, the proportional split is all that is left.
      final total = _cumulative.last;
      if (total <= 0) return Duration.zero;
      final fraction = 1 - (travelled / total).clamp(0.0, 1.0);
      return Duration(
        microseconds: (route.duration.inMicroseconds * fraction).round(),
      );
    }

    final index = _stepIndexAt(travelled);
    final stepStart = index == 0 ? 0.0 : _stepEnds[index - 1];
    final stepLength = _stepEnds[index] - stepStart;
    final stepDone = stepLength <= 0
        ? 1.0
        : ((travelled - stepStart) / stepLength).clamp(0.0, 1.0);

    var micros = (steps[index].duration.inMicroseconds * (1 - stepDone))
        .round();
    for (var i = index + 1; i < steps.length; i++) {
      micros += steps[i].duration.inMicroseconds;
    }
    return Duration(microseconds: micros);
  }

  int _stepIndexAt(double travelled) {
    var low = 0;
    var high = _stepEnds.length - 1;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (_stepEnds[mid] <= travelled) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  (int, TravelStep?, TravelStep?, double?) _maneuversAt(double travelled) {
    final steps = route.steps;
    if (steps.isEmpty || _stepEnds.isEmpty) {
      return (0, null, null, null);
    }
    final index = _stepIndexAt(travelled);
    final next = index + 1 < steps.length ? steps[index + 1] : null;
    final to = math.max(0.0, _stepEnds[index] - travelled);
    return (index, steps[index], next, to);
  }
}
