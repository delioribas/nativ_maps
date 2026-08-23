// Copyright (c) 2026 Delio Ribas. MIT licence — see LICENSE.

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/lat_lng.dart';

/// A local flat projection, in metres, around an origin.
///
/// ## Why not spherical trigonometry
///
/// The great-circle cross-track formula is
/// `asin(sin(δ13) · sin(θ13 − θ12)) · R`. It is exact at planetary scale, but
/// over the distances of a taxi ride —segments tens of metres long— it loses
/// precision exactly where precision is needed: `asin` of a minuscule number,
/// and `acos(cos(δ13) / cos(dxt/R))` with both cosines almost equal to 1, is
/// catastrophic cancellation in 64-bit floating point.
///
/// A local equirectangular projection does not have that problem, is an order
/// of magnitude faster —no trigonometric calls inside the loop— and its error
/// below 10 km is measured in millimetres. A taxi meter processes thousands of
/// positions per trip: both things matter.
///
/// The origin is chosen **per segment**, not once per path, so the distortion
/// never grows with the length of the route.
@immutable
class _Plane {
  _Plane(this.origin) : _cosLat = math.cos(origin.latitude * math.pi / 180.0);

  /// The point taken as `(0, 0)`.
  final LatLng origin;

  final double _cosLat;

  /// Metres east and north of the origin.
  (double, double) project(LatLng point) {
    final dLat = (point.latitude - origin.latitude) * math.pi / 180.0;
    final dLon = (point.longitude - origin.longitude) * math.pi / 180.0;
    return (earthRadiusMeters * dLon * _cosLat, earthRadiusMeters * dLat);
  }

  /// The inverse of [project].
  LatLng unproject(double x, double y) => LatLng(
    origin.latitude + y / earthRadiusMeters * 180.0 / math.pi,
    origin.longitude + x / (earthRadiusMeters * _cosLat) * 180.0 / math.pi,
  );
}

/// The result of projecting a point onto a path.
///
/// This is what [nearestPointOnPath] returns, and the piece that route
/// progress, off-route detection and history trimming all rest on.
@immutable
class PathMatch {
  /// Creates a match.
  const PathMatch({
    required this.segmentIndex,
    required this.position,
    required this.distanceMeters,
    required this.alongMeters,
    required this.fraction,
  });

  /// The index of the segment it landed on, that is, of its starting point.
  ///
  /// A path of `n` points has `n - 1` segments, so this value ranges from `0`
  /// to `n - 2`.
  final int segmentIndex;

  /// The closest point on the path, already interpolated inside the segment.
  ///
  /// **It is not a vertex of the path**, except by coincidence. That is exactly
  /// the mistake to avoid: on a motorway two consecutive vertices can be 200 m
  /// apart, and taking the nearest vertex reports a 100 m deviation for a car
  /// driving perfectly in its lane.
  final LatLng position;

  /// The perpendicular distance between the original point and [position].
  ///
  /// It is the measure of «how far off the path am I».
  final double distanceMeters;

  /// How much path lies behind [position], counted from the start.
  final double alongMeters;

  /// [alongMeters] as a fraction of the total length, between 0 and 1.
  final double fraction;

  @override
  String toString() =>
      'PathMatch(segmento $segmentIndex, a ${distanceMeters.round()} m, '
      'recorrido ${alongMeters.round()} m)';
}

/// The total length of a path, in metres.
///
/// Returns `0` for a path of fewer than two points.
double pathLength(List<LatLng> path) {
  if (path.length < 2) return 0;
  var total = 0.0;
  for (var i = 0; i < path.length - 1; i++) {
    total += path[i].distanceTo(path[i + 1]);
  }
  return total;
}

/// The cumulative distance up to each point of the path.
///
/// The result has the same length as [path] and starts at `0`. It is worth
/// computing once and keeping when progress will be queried many times over
/// the same route.
List<double> cumulativeDistances(List<LatLng> path) {
  final cumulative = List<double>.filled(path.length, 0);
  for (var i = 1; i < path.length; i++) {
    cumulative[i] = cumulative[i - 1] + path[i - 1].distanceTo(path[i]);
  }
  return cumulative;
}

/// The perpendicular distance from [point] to the segment [start]–[end].
///
/// The point is projected **inside the segment**: if the perpendicular falls
/// outside, the distance to the nearest endpoint is returned. Without that
/// clamp, a point well before the start of a segment would report a small
/// distance for being aligned with its extension — geometrically true and
/// operationally absurd.
double crossTrackMeters(LatLng point, LatLng start, LatLng end) {
  final plane = _Plane(start);
  final (px, py) = plane.project(point);
  final (bx, by) = plane.project(end);
  final lengthSquared = bx * bx + by * by;
  if (lengthSquared == 0) return point.distanceTo(start);
  final t = ((px * bx + py * by) / lengthSquared).clamp(0.0, 1.0);
  final dx = px - bx * t;
  final dy = py - by * t;
  return math.sqrt(dx * dx + dy * dy);
}

/// Finds the point on the path closest to [point].
///
/// ## The search window
///
/// Walking the 5,000 points of a long route on every GPS fix is wasted work:
/// a car travelling at 90 km/h moves 25 m per second, so the new match is a
/// couple of segments away from the previous one. [fromIndex] and
/// [maxSegments] restrict the scan to that window.
///
/// **Be careful using it always.** With the window on, a vehicle that
/// teleports —a tunnel, lost signal, an app restart— matches the wrong stretch
/// and never recovers. Callers must rescan the whole path when the resulting
/// distance is large; `RouteTracker` does that on its own.
///
/// Throws [ArgumentError] if the path has fewer than two points.
PathMatch nearestPointOnPath(
  List<LatLng> path,
  LatLng point, {
  int fromIndex = 0,
  int? maxSegments,
  List<double>? cumulative,
}) {
  if (path.length < 2) {
    throw ArgumentError.value(
      path.length,
      'path',
      'A path needs at least two points to project onto',
    );
  }

  final cum = cumulative ?? cumulativeDistances(path);
  final start = fromIndex.clamp(0, path.length - 2);
  final end = maxSegments == null
      ? path.length - 1
      : math.min(start + maxSegments, path.length - 1);

  var bestDistance = double.infinity;
  var bestIndex = start;
  var bestT = 0.0;
  var bestPoint = path[start];

  for (var i = start; i < end; i++) {
    final a = path[i];
    final b = path[i + 1];
    final plane = _Plane(a);
    final (px, py) = plane.project(point);
    final (bx, by) = plane.project(b);
    final lengthSquared = bx * bx + by * by;
    final t = lengthSquared == 0
        ? 0.0
        : ((px * bx + py * by) / lengthSquared).clamp(0.0, 1.0);
    final cx = bx * t;
    final cy = by * t;
    final dx = px - cx;
    final dy = py - cy;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance < bestDistance) {
      bestDistance = distance;
      bestIndex = i;
      bestT = t;
      bestPoint = t == 0
          ? a
          : t == 1
          ? b
          : plane.unproject(cx, cy);
    }
  }

  final segmentLength = cum[bestIndex + 1] - cum[bestIndex];
  final travelled = cum[bestIndex] + segmentLength * bestT;
  final total = cum.last;

  return PathMatch(
    segmentIndex: bestIndex,
    position: bestPoint,
    distanceMeters: bestDistance,
    alongMeters: travelled,
    fraction: total == 0 ? 0 : (travelled / total).clamp(0.0, 1.0),
  );
}

/// The point that lies [alongMeters] from the start of the path.
///
/// Clamped at both ends: asking for a negative distance returns the first
/// point, and asking for more than the total length returns the last.
LatLng interpolateOnPath(
  List<LatLng> path,
  double alongMeters, {
  List<double>? cumulative,
}) {
  if (path.isEmpty) {
    throw ArgumentError.value(path, 'path', 'The path is empty');
  }
  if (path.length == 1) return path.first;

  final cum = cumulative ?? cumulativeDistances(path);
  if (alongMeters <= 0) return path.first;
  if (alongMeters >= cum.last) return path.last;

  // Binary search: a long route has thousands of points and this function is
  // called on every frame of an animation.
  var low = 0;
  var high = cum.length - 1;
  while (high - low > 1) {
    final mid = (low + high) >> 1;
    if (cum[mid] <= alongMeters) {
      low = mid;
    } else {
      high = mid;
    }
  }

  final length = cum[high] - cum[low];
  if (length == 0) return path[low];
  final t = (alongMeters - cum[low]) / length;

  final plane = _Plane(path[low]);
  final (bx, by) = plane.project(path[high]);
  return plane.unproject(bx * t, by * t);
}

/// Trims a path while keeping its shape, with **Douglas–Peucker**.
///
/// ## What it is actually for
///
/// Storing a fleet's history at 1 Hz is 86,400 positions per vehicle per day.
/// The vast majority add nothing: a car waiting at a traffic light produces 90
/// identical points, and a motorway straight is described just as well by two
/// points as by two hundred.
///
/// With [toleranceMeters] of 5 m, a typical urban trace keeps between 3 % and
/// 8 % of its points with no visible difference when drawn.
///
/// **Do not use this before computing the trip distance.** Trimming removes
/// precisely the points of gentle curves, and the sum of distances over the
/// trimmed path always comes out smaller. Measure first, then trim to store.
List<LatLng> simplifyPath(
  List<LatLng> path, {
  required double toleranceMeters,
}) {
  if (toleranceMeters <= 0) {
    throw ArgumentError.value(
      toleranceMeters,
      'toleranceMeters',
      'The tolerance must be greater than zero',
    );
  }
  if (path.length < 3) return List<LatLng>.of(path);

  final keep = List<bool>.filled(path.length, false);
  keep[0] = true;
  keep[path.length - 1] = true;

  // An explicit stack instead of recursion: a full day of trace overflows the
  // call stack in the worst case.
  final pending = <(int, int)>[(0, path.length - 1)];

  while (pending.isNotEmpty) {
    final (start, end) = pending.removeLast();
    if (end - start < 2) continue;

    var worstDistance = 0.0;
    var worstIndex = -1;
    for (var i = start + 1; i < end; i++) {
      final d = crossTrackMeters(path[i], path[start], path[end]);
      if (d > worstDistance) {
        worstDistance = d;
        worstIndex = i;
      }
    }

    if (worstDistance > toleranceMeters && worstIndex > 0) {
      keep[worstIndex] = true;
      pending
        ..add((start, worstIndex))
        ..add((worstIndex, end));
    }
  }

  return <LatLng>[
    for (var i = 0; i < path.length; i++)
      if (keep[i]) path[i],
  ];
}
