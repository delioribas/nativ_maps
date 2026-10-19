// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/lat_lng.dart';

/// A raw GPS fix, exactly as the device delivers it.
///
/// It is the input type for this whole layer. Build it from whatever the
/// system gives you —`Geolocator` in Flutter, a GT06 frame, a database row—
/// and from there on nothing else needs converting.
@immutable
@experimental
class PositionFix {
  /// Creates a fix.
  const PositionFix({
    required this.position,
    required this.timestamp,
    this.accuracyMeters,
    this.speedKmh,
    this.headingDegrees,
    this.altitudeMeters,
  });

  /// Where the receiver says it is.
  final LatLng position;

  /// When the sample was taken.
  ///
  /// **The receiver's time, not the time it was received.** On a tracker that
  /// sends over GPRS the two drift minutes apart when coverage is bad, and
  /// using the reception time turns a traffic jam into a teleport.
  final DateTime timestamp;

  /// The declared uncertainty radius, in meters.
  ///
  /// It is the most valuable piece of the whole fix and the one almost nobody
  /// uses. Without it there is no way to tell a car moving slowly from a
  /// parked car whose GPS is bouncing between buildings.
  final double? accuracyMeters;

  /// The speed measured by the receiver, in km/h.
  ///
  /// It comes from the Doppler shift of the carrier, not from dividing
  /// distance by time, so it is **more reliable than the speed computed**
  /// between two consecutive positions. When present, it is preferred.
  final double? speedKmh;

  /// The heading in degrees from north, between 0 and 360.
  final double? headingDegrees;

  /// The altitude above the ellipsoid, in meters.
  final double? altitudeMeters;

  /// A copy with some fields changed.
  PositionFix copyWith({
    LatLng? position,
    DateTime? timestamp,
    double? accuracyMeters,
    double? speedKmh,
    double? headingDegrees,
    double? altitudeMeters,
  }) => PositionFix(
    position: position ?? this.position,
    timestamp: timestamp ?? this.timestamp,
    accuracyMeters: accuracyMeters ?? this.accuracyMeters,
    speedKmh: speedKmh ?? this.speedKmh,
    headingDegrees: headingDegrees ?? this.headingDegrees,
    altitudeMeters: altitudeMeters ?? this.altitudeMeters,
  );

  @override
  String toString() =>
      'PositionFix($position, ${timestamp.toIso8601String()}, '
      '±${accuracyMeters?.round()} m)';
}

/// Why a fix was discarded.
///
/// It is exposed in full on purpose: whoever charges per kilometer has to be
/// able to justify **why** a position did not count, and a counter of
/// discards by reason is the best sign that a tracker is misbehaving.
@experimental
enum FixRejection {
  /// The declared uncertainty exceeds the maximum accepted.
  poorAccuracy,

  /// The timestamp is earlier than or equal to that of the last accepted fix.
  ///
  /// It happens all the time with batches resent after losing coverage.
  outOfOrder,

  /// The displacement does not exceed the receiver's own noise.
  ///
  /// **This is the one that prevents overcharging.** A parked phone on a
  /// narrow street declares ±30 m and jumps 20 m every second. Adding up those
  /// jumps means 72 km/h for a parked vehicle.
  withinNoise,

  /// The implied speed between the two fixes is impossible.
  ///
  /// A single satellite reflected off a building facade puts the position a
  /// kilometer away for one sample.
  impossibleSpeed,
}

/// The result of passing a fix through the filter.
@immutable
@experimental
class FilterResult {
  /// Creates an accepted result.
  const FilterResult.accepted({
    required PositionFix fix,
    required this.distanceMeters,
    required this.elapsed,
  }) : _fix = fix,
       rejection = null;

  /// Creates a rejected result.
  const FilterResult.rejected(FixRejection this.rejection)
    : _fix = null,
      distanceMeters = 0,
      elapsed = Duration.zero;

  final PositionFix? _fix;

  /// The reason for the discard, or `null` if it was accepted.
  final FixRejection? rejection;

  /// How far it advanced from the last accepted fix, in meters.
  final double distanceMeters;

  /// The time elapsed since the last accepted fix.
  final Duration elapsed;

  /// Was it accepted?
  bool get accepted => _fix != null;

  /// The accepted fix, already smoothed if the filter had smoothing on.
  ///
  /// Throws [StateError] if read on a rejected result; check [accepted]
  /// first.
  PositionFix get fix {
    final value = _fix;
    if (value == null) {
      throw StateError(
        'The fix was rejected as $rejection: there is no position to read',
      );
    }
    return value;
  }

  /// The implied speed between the two fixes, in km/h.
  ///
  /// Returns `null` if there is no elapsed time to divide by.
  double? get impliedSpeedKmh {
    final seconds = elapsed.inMicroseconds / 1e6;
    if (seconds <= 0) return null;
    return distanceMeters / seconds * 3.6;
  }

  @override
  String toString() => accepted
      ? 'FilterResult(aceptada, +${distanceMeters.toStringAsFixed(1)} m)'
      : 'FilterResult(descartada: ${rejection!.name})';
}

/// Discards GPS fixes that do not represent real movement.
///
/// ## The problem it solves
///
/// Adding up the distance between consecutive positions is the obvious way to
/// measure a trip, and it is wrong. A stationary receiver does not repeat the
/// same coordinate: it bounces around inside its uncertainty circle. In an
/// urban canyon that circle is 30 m and the bounce happens every second.
///
/// A taxi waiting twenty minutes outside a hotel racks up several kilometers
/// that way that nobody traveled, and the passenger pays for them.
///
/// ## The four checks, in order
///
/// | Check | Discards | Setting |
/// |---|---|---|
/// | Declared uncertainty | poor-quality fixes | [maxAccuracyMeters] |
/// | Time order | resent batches and duplicates | — |
/// | Noise threshold | the bounce of a stationary receiver | [noiseFactor] |
/// | Implied speed | jumps from reflected signals | [maxSpeedKmh] |
///
/// ## Smoothing
///
/// With [smooth] on, a **constant-velocity** Kalman filter is applied as
/// well: the state is not just the position, but also the velocity on each
/// axis.
///
/// That distinction is not an academic detail. A Kalman filter that only
/// estimates position has no way of knowing the vehicle is moving, so every
/// prediction assumes it is still where it was and the correction only moves
/// a fraction of what was measured. The result lags **systematically
/// behind**: at 54 km/h the lag exceeds ninety meters, and the blue dot drags
/// a whole block behind the car. With the velocity state, the prediction
/// already includes the advance and the filter smooths without lagging.
///
/// **Smoothing does not replace discarding.** A Kalman filter fed with bounce
/// returns a smoother bounce, and the sum is still inflated.
@experimental
class PositionFilter {
  /// Creates a filter.
  ///
  /// The defaults are meant for a phone in a city. For a dedicated tracker
  /// with an external antenna you can lower [maxAccuracyMeters] to 20 and
  /// [noiseFactor] to 1.
  PositionFilter({
    this.maxAccuracyMeters = 50,
    this.noiseFactor = 2.0,
    this.minDisplacementMeters = 3,
    this.maxSpeedKmh = 220,
    this.smooth = false,
    this.processNoiseMps2 = 2.0,
  }) {
    if (noiseFactor < 0) {
      throw ArgumentError.value(
        noiseFactor,
        'noiseFactor',
        'Cannot be negative',
      );
    }
  }

  /// Maximum accepted uncertainty, in meters.
  ///
  /// A fix that declares ±120 m is good neither for charging nor for drawing.
  final double maxAccuracyMeters;

  /// How many times the uncertainty the displacement has to exceed.
  ///
  /// With `2.0` and a ±10 m fix, it has to move more than 20 m to count.
  /// Raising it discards real slow movement —a taxi in a traffic jam—;
  /// lowering it lets bounce through. `2.0` is the usual balance.
  final double noiseFactor;

  /// Absolute displacement floor, in meters.
  ///
  /// It applies when the fix **does not declare** an uncertainty, which is
  /// the case for many cheap trackers: without that figure, [noiseFactor] has
  /// nothing to work on and this is the only brake left.
  final double minDisplacementMeters;

  /// Maximum implied speed, in km/h.
  final double maxSpeedKmh;

  /// Is the position smoothed with a Kalman filter?
  final bool smooth;

  /// Kalman process noise, in meters per second squared.
  ///
  /// It is how much acceleration is considered plausible between two
  /// measurements. Higher follows starts and braking better and smooths less;
  /// lower smooths more and takes longer to react. For urban traffic, between
  /// 1 and 3.
  final double processNoiseMps2;

  PositionFix? _last;
  DateTime? _lastSmoothedAt;
  double _originLat = 0;
  double _originLon = 0;
  double _cosOrigin = 1;
  _Axis? _east;
  _Axis? _north;

  /// The last accepted fix, or `null` if there has not been one yet.
  PositionFix? get last => _last;

  /// Returns to the initial state.
  ///
  /// Call it between trips: otherwise the first point of the new ride is
  /// compared with the last one of the previous ride and the distance between
  /// the two sneaks in as if it had been traveled.
  void reset() {
    _last = null;
    _lastSmoothedAt = null;
    _east = null;
    _north = null;
  }

  /// Passes a fix through the filter.
  FilterResult add(PositionFix fix) {
    final accuracy = fix.accuracyMeters;
    if (accuracy != null && accuracy > maxAccuracyMeters) {
      return const FilterResult.rejected(FixRejection.poorAccuracy);
    }

    final previous = _last;
    if (previous == null) {
      _last = smooth ? _applySmoothing(fix) : fix;
      return FilterResult.accepted(
        fix: _last!,
        distanceMeters: 0,
        elapsed: Duration.zero,
      );
    }

    if (!fix.timestamp.isAfter(previous.timestamp)) {
      return const FilterResult.rejected(FixRejection.outOfOrder);
    }

    final elapsed = fix.timestamp.difference(previous.timestamp);
    final advance = previous.position.distanceTo(fix.position);

    // The noise threshold: the larger of the absolute floor and what the
    // declared uncertainty of the two fixes dictates.
    final uncertainty = math.max(accuracy ?? 0, previous.accuracyMeters ?? 0);
    final threshold = math.max(
      minDisplacementMeters,
      uncertainty * noiseFactor,
    );
    if (advance < threshold) {
      return const FilterResult.rejected(FixRejection.withinNoise);
    }

    final seconds = elapsed.inMicroseconds / 1e6;
    if (seconds > 0 && advance / seconds * 3.6 > maxSpeedKmh) {
      return const FilterResult.rejected(FixRejection.impossibleSpeed);
    }

    final accepted = smooth ? _applySmoothing(fix) : fix;
    // The distance is measured on the position that is stored, not on the raw
    // one: otherwise the sum of advances and the drawn path stop matching.
    final actualAdvance = previous.position.distanceTo(accepted.position);
    _last = accepted;
    return FilterResult.accepted(
      fix: accepted,
      distanceMeters: actualAdvance,
      elapsed: elapsed,
    );
  }

  /// Constant-velocity Kalman filter, one axis per coordinate.
  ///
  /// It works in **meters on a local plane**, not in degrees: a degree of
  /// longitude measures 111 km at the equator and 55 in Madrid, so a filter
  /// that operates on degrees unintentionally applies different smoothing on
  /// each axis and at each latitude.
  ///
  /// The two axes are filtered separately. It is the standard approximation
  /// in vehicle tracking: the real coupling between them is small, and a
  /// coupled four-state filter does not improve enough to justify inverting a
  /// matrix on every fix.
  PositionFix _applySmoothing(PositionFix fix) {
    final accuracy = fix.accuracyMeters ?? maxAccuracyMeters;
    final measurementVariance = accuracy * accuracy;

    if (_east == null || _north == null) {
      _originLat = fix.position.latitude;
      _originLon = fix.position.longitude;
      _cosOrigin = math.cos(_originLat * math.pi / 180.0);
      _east = _Axis(0, measurementVariance);
      _north = _Axis(0, measurementVariance);
      _lastSmoothedAt = fix.timestamp;
      return fix;
    }

    final previous = _lastSmoothedAt ?? fix.timestamp;
    final dt = fix.timestamp.difference(previous).inMicroseconds / 1e6;
    _lastSmoothedAt = fix.timestamp;

    final (x, y) = _project(fix.position);
    final q = processNoiseMps2 * processNoiseMps2;

    _east!
      ..predict(dt, q)
      ..correct(x, measurementVariance);
    _north!
      ..predict(dt, q)
      ..correct(y, measurementVariance);

    return fix.copyWith(
      position: _unproject(_east!.position, _north!.position),
    );
  }

  (double, double) _project(LatLng point) {
    final dLat = (point.latitude - _originLat) * math.pi / 180.0;
    final dLon = (point.longitude - _originLon) * math.pi / 180.0;
    return (earthRadiusMeters * dLon * _cosOrigin, earthRadiusMeters * dLat);
  }

  LatLng _unproject(double x, double y) => LatLng(
    _originLat + y / earthRadiusMeters * 180.0 / math.pi,
    _originLon + x / (earthRadiusMeters * _cosOrigin) * 180.0 / math.pi,
  );
}

/// One axis of the Kalman filter: position and velocity.
class _Axis {
  _Axis(this.position, double initialVariance)
    : velocity = 0,
      _p00 = initialVariance,
      _p01 = 0,
      // With no measurement yet, nothing is known about the velocity.
      // Starting with a large variance lets the first fixes pin it down
      // quickly, instead of dragging a zero along for half a minute.
      _p11 = 1e4;

  /// The estimated position, in meters from the origin.
  double position;

  /// The estimated velocity, in meters per second.
  double velocity;

  double _p00;
  double _p01;
  double _p11;

  /// Advances the state [dt] seconds assuming constant velocity.
  void predict(double dt, double q) {
    if (dt <= 0) return;
    position += velocity * dt;

    // P = F·P·Fᵀ + Q, with Q the white-noise model on the acceleration.
    final dt2 = dt * dt;
    final dt3 = dt2 * dt;
    final dt4 = dt2 * dt2;
    _p00 += dt * (2 * _p01 + dt * _p11) + q * dt4 / 4;
    _p01 += dt * _p11 + q * dt3 / 2;
    _p11 += q * dt2;
  }

  /// Corrects the state with a position measurement of variance [r].
  void correct(double measurement, double r) {
    final s = _p00 + r;
    if (s <= 0) return;
    final k0 = _p00 / s;
    final k1 = _p01 / s;
    final innovation = measurement - position;

    position += k0 * innovation;
    velocity += k1 * innovation;

    // Order matters: `_p11` needs `_p01` from before it is updated.
    final previousP01 = _p01;
    _p00 -= k0 * _p00;
    _p01 -= k0 * _p01;
    _p11 -= k1 * previousP01;
  }
}
