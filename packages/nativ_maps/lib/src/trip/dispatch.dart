// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/enums.dart';
import 'package:nativ_maps/src/core/lat_lng.dart';
import 'package:nativ_maps/src/routes/routes_client.dart';

/// Where a driver is.
@immutable
@experimental
class DriverLocation {
  /// Creates a driver position.
  const DriverLocation({
    required this.driverId,
    required this.position,
    this.updatedAt,
    this.available = true,
    this.headingDegrees,
  });

  /// Who it is.
  final String driverId;

  /// Where it is.
  final LatLng position;

  /// When it was last heard from.
  final DateTime? updatedAt;

  /// Is it free?
  final bool available;

  /// Which way it faces, in degrees from north.
  final double? headingDegrees;

  @override
  String toString() => 'DriverLocation($driverId, $position)';
}

/// A candidate driver for a pickup.
@immutable
@experimental
class DriverCandidate {
  /// Creates a candidate.
  const DriverCandidate({
    required this.driver,
    required this.straightLineMeters,
    this.drivingMeters,
    this.drivingDuration,
  });

  /// The driver.
  final DriverLocation driver;

  /// The straight-line distance to the pickup, in meters.
  ///
  /// It is free to compute and good for shortlisting, **not for choosing**.
  final double straightLineMeters;

  /// The real driving meters, if it was refined with the matrix.
  final double? drivingMeters;

  /// The real driving time, if it was refined with the matrix.
  final Duration? drivingDuration;

  /// Was it refined with a call to the service?
  bool get refined => drivingDuration != null;

  /// How far the real path strays from the straight line.
  ///
  /// A value of 1.4 is normal in a city with a regular street grid. Above 2.5
  /// there is almost always a river, a railway or a highway in the way, and
  /// that is exactly the case where sorting by straight line gets it wrong.
  double? get detourFactor {
    final meters = drivingMeters;
    if (meters == null || straightLineMeters <= 0) return null;
    return meters / straightLineMeters;
  }

  @override
  String toString() => refined
      ? 'DriverCandidate(${driver.driverId}, '
            '${drivingDuration!.inMinutes} min)'
      : 'DriverCandidate(${driver.driverId}, '
            '${straightLineMeters.round()} m straight line)';
}

/// Chooses which drivers to offer a ride to.
///
/// ## The two phases, and why there are two
///
/// **Sorting by straight-line distance is wrong.** The driver 300 m away on
/// the other side of the river takes fifteen minutes; the one 1.2 km away
/// down the avenue takes four. With the straight line you offer the ride to
/// the first one.
///
/// **Requesting the matrix for the whole fleet is wrong too**, but because of
/// money: every cell is billed, and a fleet of 800 cars means 800 cells for
/// every ride request.
///
/// That is why there are two phases:
///
/// 1. [shortlist] filters by straight line. It is local, instant and **free**.
/// 2. [rank] refines only those with one call to the matrix.
///
/// With 12 candidates, a ride costs 12 cells instead of 800.
@immutable
@experimental
class DispatchPlanner {
  /// Creates a planner.
  const DispatchPlanner({
    required this.routes,
    this.shortlistSize = 12,
    this.maxRadiusMeters = 8000,
  });

  /// The client used for refining.
  final RoutesClient routes;

  /// How many candidates go on to the refining phase.
  ///
  /// The maximum number of origins in an unbounded matrix is 15. Above that,
  /// [rank] splits into several calls, and each one is billed separately.
  final int shortlistSize;

  /// Maximum straight-line radius, in meters.
  ///
  /// A driver 30 km away is not going to come, and putting them in the matrix
  /// is throwing money away.
  final double maxRadiusMeters;

  /// Shortlists by straight-line distance. **Spends no requests.**
  ///
  /// Drops the unavailable ones and, if given, those that have gone without
  /// an update for longer than [staleAfter]: a car whose last position is ten
  /// minutes old is no longer where it says it is.
  List<DriverCandidate> shortlist(
    List<DriverLocation> drivers,
    LatLng pickup, {
    Duration? staleAfter,
    DateTime? now,
  }) {
    final moment = now ?? DateTime.now();

    // Bounding-box rejection before computing any distance. With large fleets
    // this removes 99 % of the candidates with two subtractions, without
    // trigonometry.
    final latDegrees = maxRadiusMeters / 111320.0;
    final cosLat = math.cos(pickup.latitude * math.pi / 180).abs();
    final lonDegrees = cosLat < 1e-6
        ? 180.0
        : maxRadiusMeters / (111320.0 * cosLat);

    final candidates = <DriverCandidate>[];
    for (final driver in drivers) {
      if (!driver.available) continue;

      if (staleAfter != null) {
        final seen = driver.updatedAt;
        if (seen == null || moment.difference(seen).abs() > staleAfter) {
          continue;
        }
      }

      if ((driver.position.latitude - pickup.latitude).abs() > latDegrees) {
        continue;
      }
      if ((driver.position.longitude - pickup.longitude).abs() > lonDegrees) {
        continue;
      }

      final meters = driver.position.distanceTo(pickup);
      if (meters > maxRadiusMeters) continue;
      candidates.add(
        DriverCandidate(driver: driver, straightLineMeters: meters),
      );
    }

    candidates.sort(
      (a, b) => a.straightLineMeters.compareTo(b.straightLineMeters),
    );
    return candidates.take(shortlistSize).toList();
  }

  /// Refines the shortlist with real driving times.
  ///
  /// Sends the drivers as **origins** and the pickup as the only destination,
  /// so it costs one cell per candidate. If there are more than 15 it is
  /// split, because that is the maximum number of origins in an unbounded
  /// matrix.
  ///
  /// The result is sorted by driving time. Candidates for which the service
  /// could not compute a route —an island, an unmapped area— stay at the end
  /// with their unrefined data, instead of disappearing without explanation.
  Future<List<DriverCandidate>> rank(
    List<DriverCandidate> candidates,
    LatLng pickup, {
    TravelMode travelMode = TravelMode.car,
    DateTime? departureTime,
  }) async {
    if (candidates.isEmpty) return const <DriverCandidate>[];

    const perBatch = 15;
    final refinedList = <DriverCandidate>[];
    final unroutable = <DriverCandidate>[];

    for (var i = 0; i < candidates.length; i += perBatch) {
      final batch = candidates.skip(i).take(perBatch).toList();
      final matrix = await routes.calculateRouteMatrix(
        origins: <LatLng>[for (final c in batch) c.driver.position],
        destinations: <LatLng>[pickup],
        travelMode: travelMode,
        departureTime: departureTime,
      );

      for (var j = 0; j < batch.length; j++) {
        final cell = matrix.cells[j][0];
        if (!cell.isValid) {
          unroutable.add(batch[j]);
          continue;
        }
        refinedList.add(
          DriverCandidate(
            driver: batch[j].driver,
            straightLineMeters: batch[j].straightLineMeters,
            drivingMeters: cell.distanceMeters,
            drivingDuration: cell.duration,
          ),
        );
      }
    }

    refinedList.sort(
      (a, b) => a.drivingDuration!.compareTo(b.drivingDuration!),
    );
    return <DriverCandidate>[...refinedList, ...unroutable];
  }

  /// Shortlists and refines in one go.
  ///
  /// It is what you call when a ride request comes in.
  Future<List<DriverCandidate>> findNearest(
    List<DriverLocation> drivers,
    LatLng pickup, {
    Duration? staleAfter,
    TravelMode travelMode = TravelMode.car,
    DateTime? now,
  }) async {
    final shortlisted = shortlist(
      drivers,
      pickup,
      staleAfter: staleAfter,
      now: now,
    );
    if (shortlisted.isEmpty) return const <DriverCandidate>[];
    return rank(shortlisted, pickup, travelMode: travelMode);
  }
}
