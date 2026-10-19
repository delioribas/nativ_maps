// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/lat_lng.dart';
import 'package:nativ_maps/src/trip/position_filter.dart';

/// What kind of driving event was detected.
@experimental
enum DrivingEventType {
  /// Harsh acceleration.
  harshAcceleration,

  /// Harsh braking.
  harshBraking,

  /// A curve taken too fast.
  harshCornering,

  /// Driving above the limit.
  speeding,
}

/// A driving event, with where and when it happened.
@immutable
@experimental
class DrivingEvent {
  /// Creates an event.
  const DrivingEvent({
    required this.type,
    required this.timestamp,
    required this.position,
    required this.magnitude,
    required this.speedKmh,
  });

  /// What kind of event it is.
  final DrivingEventType type;

  /// When it happened.
  final DateTime timestamp;

  /// Where it happened.
  final LatLng position;

  /// How much: meters per second squared, or km/h over the limit.
  ///
  /// For the first three kinds it is acceleration; for
  /// [DrivingEventType.speeding] it is how far over the limit it went.
  final double magnitude;

  /// The speed at that moment, in km/h.
  final double speedKmh;

  /// The magnitude in units of gravity, for the acceleration ones.
  ///
  /// Emergency braking is around 0.6 g. Harsh but normal braking stays at
  /// 0.35 g.
  double get gForce => magnitude.abs() / 9.80665;

  @override
  String toString() =>
      'DrivingEvent(${type.name}, ${magnitude.toStringAsFixed(1)}, '
      '${timestamp.toIso8601String()})';
}

/// The driving score of a trip or of a driver.
@immutable
@experimental
class DrivingScore {
  /// Creates a score.
  const DrivingScore({
    required this.value,
    required this.distanceKm,
    required this.counts,
  });

  /// The score, from 0 to 100.
  final int value;

  /// Over how many kilometers it was computed.
  final double distanceKm;

  /// How many events of each kind.
  final Map<DrivingEventType, int> counts;

  /// How many events there were in total.
  int get eventCount => counts.values.fold(0, (sum, howMany) => sum + howMany);

  /// Events per hundred kilometers.
  ///
  /// **It is the only figure comparable across drivers.** The absolute total
  /// only tells you who drives more hours.
  double get eventsPer100Km =>
      distanceKm <= 0 ? 0 : eventCount / distanceKm * 100;

  @override
  String toString() =>
      'DrivingScore($value/100, $eventCount events over '
      '${distanceKm.toStringAsFixed(1)} km)';
}

/// Detects harsh acceleration, harsh braking, harsh cornering and speeding.
///
/// ```dart
/// final analyzer = TelemetryAnalyzer(speedLimitKmh: 50);
/// for (final fix in gpsStream) {
///   for (final event in analyzer.add(fix)) {
///     notify(event);
///   }
/// }
/// print(analyzer.score());
/// ```
///
/// ## Why deriving speed from positions does not work
///
/// Computing acceleration as `Δposition / Δt²` squares the GPS noise: a 15 m
/// bounce between two fixes one second apart shows up as 30 m/s², three times
/// gravity, and the analyzer detects harsh braking in a parked car.
///
/// That is why it requires the **speed reported by the receiver** —the
/// Doppler one, which is independent of the position— and fixes that do not
/// carry it generate no acceleration events. Missing detections is better
/// than inventing them: a report full of false harsh braking stops being read
/// after the first week.
///
/// ## The thresholds
///
/// | Event | Default | Reference |
/// |---|---|---|
/// | Harsh acceleration | 3.0 m/s² | 0.31 g |
/// | Harsh braking | −3.5 m/s² | 0.36 g |
/// | Cornering | 3.5 m/s² lateral | passenger thrown sideways |
/// | Speeding | limit + 8 km/h | speedometer margin |
@experimental
class TelemetryAnalyzer {
  /// Creates an analyzer.
  TelemetryAnalyzer({
    this.harshAccelerationMps2 = 3.0,
    this.harshBrakingMps2 = -3.5,
    this.harshCorneringMps2 = 3.5,
    this.speedLimitKmh,
    this.speedToleranceKmh = 8,
    this.minSpeedingDuration = const Duration(seconds: 10),
    this.maxSampleGap = const Duration(seconds: 10),
  });

  /// The threshold for harsh acceleration, in m/s².
  final double harshAccelerationMps2;

  /// The threshold for harsh braking, in m/s². It is negative.
  final double harshBrakingMps2;

  /// The lateral acceleration above which cornering is harsh, in m/s².
  final double harshCorneringMps2;

  /// The road's speed limit, in km/h, if known.
  ///
  /// The package does **not** look it up: Amazon Location does not publish
  /// per-segment limits. It comes from your own map data, a zones file or the
  /// fleet's policy.
  final double? speedLimitKmh;

  /// How much over the limit is tolerated before counting as speeding.
  final double speedToleranceKmh;

  /// How long the speeding has to last to generate a single event.
  ///
  /// Without this, a minute at 60 on a 50 road generates sixty events.
  final Duration minSpeedingDuration;

  /// Maximum gap between fixes for acceleration to be derived.
  ///
  /// With a two-minute gap, the difference in speeds does not describe any
  /// specific maneuver.
  final Duration maxSampleGap;

  final List<DrivingEvent> _events = <DrivingEvent>[];
  PositionFix? _previous;
  double _distanceMeters = 0;
  DateTime? _speedingSince;
  double _speedingPeak = 0;

  /// All the detected events, in order.
  List<DrivingEvent> get events => List<DrivingEvent>.unmodifiable(_events);

  /// Processes a fix and returns the events it caused.
  ///
  /// Events are recorded **in a single place**, at the end: spreading the
  /// `add` across several exit paths is how you end up counting a speeding
  /// episode twice.
  List<DrivingEvent> add(PositionFix fix) {
    final produced = <DrivingEvent>[];
    final previous = _previous;
    _previous = fix;

    if (previous != null) {
      _distanceMeters += previous.position.distanceTo(fix.position);
    }

    // Without the receiver's speed nothing is evaluated: see the class note.
    final speed = fix.speedKmh;
    if (speed != null) {
      final speeding = _closeSpeedingEpisode(fix, speed);
      if (speeding != null) produced.add(speeding);

      final previousSpeed = previous?.speedKmh;
      final gap = previous == null
          ? Duration.zero
          : fix.timestamp.difference(previous.timestamp);

      if (previous != null &&
          previousSpeed != null &&
          gap > Duration.zero &&
          gap <= maxSampleGap) {
        final seconds = gap.inMicroseconds / 1e6;

        // ── Longitudinal acceleration
        final acceleration = (speed - previousSpeed) / 3.6 / seconds;
        if (acceleration >= harshAccelerationMps2) {
          produced.add(
            _event(
              DrivingEventType.harshAcceleration,
              fix,
              acceleration,
              speed,
            ),
          );
        } else if (acceleration <= harshBrakingMps2) {
          produced.add(
            _event(DrivingEventType.harshBraking, fix, acceleration, speed),
          );
        }

        // ── Lateral acceleration: speed times angular velocity
        final heading = fix.headingDegrees;
        final previousHeading = previous.headingDegrees;
        if (heading != null && previousHeading != null) {
          final turn = _headingDelta(previousHeading, heading);
          final omega = turn * math.pi / 180 / seconds;
          final lateral = (speed / 3.6) * omega.abs();
          if (lateral >= harshCorneringMps2) {
            produced.add(
              _event(DrivingEventType.harshCornering, fix, lateral, speed),
            );
          }
        }
      }
    }

    _events.addAll(produced);
    return produced;
  }

  /// Closes a speeding episode, if it has just ended.
  ///
  /// Returns the event **when dropping** below the threshold, not while above
  /// it: that way a minute at 70 on a 50 road is one event and not sixty.
  DrivingEvent? _closeSpeedingEpisode(PositionFix fix, double speed) {
    final limit = speedLimitKmh;
    if (limit == null) return null;

    if (speed > limit + speedToleranceKmh) {
      _speedingSince ??= fix.timestamp;
      _speedingPeak = math.max(_speedingPeak, speed);
      return null;
    }

    final from = _speedingSince;
    if (from == null) return null;
    final duration = fix.timestamp.difference(from);
    final peak = _speedingPeak;
    _speedingSince = null;
    _speedingPeak = 0;

    if (duration < minSpeedingDuration) return null;
    return DrivingEvent(
      type: DrivingEventType.speeding,
      timestamp: from,
      position: fix.position,
      magnitude: peak - limit,
      speedKmh: peak,
    );
  }

  DrivingEvent _event(
    DrivingEventType kind,
    PositionFix fix,
    double magnitude,
    double speed,
  ) => DrivingEvent(
    type: kind,
    timestamp: fix.timestamp,
    position: fix.position,
    magnitude: magnitude,
    speedKmh: speed,
  );

  /// The shortest signed heading difference between two angles.
  ///
  /// Without this, going from 359° to 1° looks like a 358-degree turn and
  /// every car that crosses north generates harsh cornering.
  static double _headingDelta(double from, double to) {
    var d = (to - from) % 360;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
  }

  /// Computes the score from what has been detected so far.
  ///
  /// It starts at 100 and deducts per event and per hundred kilometers, so
  /// that a driver with a lot of mileage is not penalized for piling up more
  /// absolute events. The default weights punish harsh braking the most,
  /// since it is the best predictor of accidents.
  DrivingScore score({
    double harshWeight = 4,
    double corneringWeight = 2,
    double speedingWeight = 6,
  }) {
    final counts = <DrivingEventType, int>{};
    for (final event in _events) {
      counts.update(event.type, (n) => n + 1, ifAbsent: () => 1);
    }

    final km = _distanceMeters / 1000;
    final base = math.max(km, 1.0);
    final penalty =
        ((counts[DrivingEventType.harshAcceleration] ?? 0) * harshWeight +
            (counts[DrivingEventType.harshBraking] ?? 0) * harshWeight +
            (counts[DrivingEventType.harshCornering] ?? 0) * corneringWeight +
            (counts[DrivingEventType.speeding] ?? 0) * speedingWeight) /
        base *
        100;

    return DrivingScore(
      value: (100 - penalty).clamp(0, 100).round(),
      distanceKm: km,
      counts: Map<DrivingEventType, int>.unmodifiable(counts),
    );
  }

  /// Returns to the initial state.
  void reset() {
    _events.clear();
    _previous = null;
    _distanceMeters = 0;
    _speedingSince = null;
    _speedingPeak = 0;
  }
}
