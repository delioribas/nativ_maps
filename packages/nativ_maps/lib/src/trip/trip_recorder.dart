// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/lat_lng.dart';
import 'package:nativ_maps/src/trip/position_filter.dart';

/// A period during which the vehicle was stopped.
///
/// It is what feeds a taximeter's waiting charge, and what answers "why did
/// you charge me eight minutes of waiting?" with a time and a place.
@immutable
@experimental
class StopPeriod {
  /// Creates a stop period.
  const StopPeriod({
    required this.position,
    required this.start,
    required this.end,
  });

  /// Where it stopped.
  final LatLng position;

  /// When the stop started.
  final DateTime start;

  /// When it got moving again.
  final DateTime end;

  /// How long it lasted.
  Duration get duration => end.difference(start);

  @override
  String toString() => 'StopPeriod(${duration.inSeconds} s at $position)';
}

/// The state of the trip after processing a fix.
@immutable
@experimental
class TripUpdate {
  /// Creates an update.
  const TripUpdate({
    required this.filter,
    required this.distanceMeters,
    required this.duration,
    required this.movingDuration,
    required this.stoppedDuration,
    required this.stopped,
    required this.speedKmh,
  });

  /// What the filter did with the fix.
  final FilterResult filter;

  /// Accumulated trip distance, in meters.
  final double distanceMeters;

  /// Total time since the first fix.
  final Duration duration;

  /// Time spent moving.
  final Duration movingDuration;

  /// Time spent stopped, counting only stops already confirmed.
  final Duration stoppedDuration;

  /// Is it stopped right now?
  final bool stopped;

  /// The estimated speed at this instant, in km/h.
  final double speedKmh;

  @override
  String toString() =>
      'TripUpdate(${(distanceMeters / 1000).toStringAsFixed(2)} km, '
      '${speedKmh.toStringAsFixed(0)} km/h${stopped ? ', stopped' : ''})';
}

/// A finished trip, with everything needed to charge for it and to defend it.
@immutable
@experimental
class TripSummary {
  /// Creates a summary.
  const TripSummary({
    required this.start,
    required this.end,
    required this.distanceMeters,
    required this.movingDuration,
    required this.stoppedDuration,
    required this.stops,
    required this.track,
    required this.acceptedFixes,
    required this.rejections,
    required this.maxSpeedKmh,
  });

  /// Time of the first accepted fix.
  final DateTime start;

  /// Time of the last processed fix.
  final DateTime end;

  /// Distance covered, in meters, with the noise already discounted.
  final double distanceMeters;

  /// Time spent moving.
  final Duration movingDuration;

  /// Time spent stopped in confirmed stops.
  final Duration stoppedDuration;

  /// The stops, in order.
  final List<StopPeriod> stops;

  /// The path, with only the positions that passed the filter.
  ///
  /// It is empty if the recorder was created with `keepTrack: false`.
  final List<LatLng> track;

  /// How many fixes were accepted.
  final int acceptedFixes;

  /// How many were discarded, by reason.
  ///
  /// A high share of [FixRejection.poorAccuracy] points to a tracker with a
  /// badly placed antenna; one of [FixRejection.outOfOrder], to a problem
  /// with resending after losing coverage.
  final Map<FixRejection, int> rejections;

  /// The top speed observed, in km/h.
  final double maxSpeedKmh;

  /// Total duration of the trip.
  Duration get duration => end.difference(start);

  /// Distance in kilometers.
  double get distanceKm => distanceMeters / 1000;

  /// Average speed counting only the time spent moving, in km/h.
  ///
  /// It is the one that describes how the vehicle was driven. The average
  /// over the total time mixes driving with traffic lights and does not mean
  /// much.
  double get averageMovingSpeedKmh {
    final seconds = movingDuration.inMicroseconds / 1e6;
    if (seconds <= 0) return 0;
    return distanceMeters / seconds * 3.6;
  }

  /// How many fixes were discarded in total.
  int get rejectedFixes =>
      rejections.values.fold(0, (sum, howMany) => sum + howMany);

  @override
  String toString() =>
      'TripSummary(${distanceKm.toStringAsFixed(2)} km in '
      '${duration.inMinutes} min, ${stops.length} stop(s))';
}

/// Turns a stream of GPS positions into a measurable trip.
///
/// It combines three things that in practice cannot be separated: filtering
/// the noise, adding up the distance and detecting stops.
///
/// ```dart
/// final recorder = TripRecorder();
/// for (final fix in gpsStream) {
///   final state = recorder.add(fix);
///   show(state.distanceMeters, state.speedKmh);
/// }
/// final trip = recorder.finish();
/// ```
///
/// ## What almost everyone gets wrong
///
/// When the vehicle is stopped, the filter **discards** almost every fix as
/// noise. If the recorder ignored the discards, the clock would freeze during
/// stops: a taxi waiting half an hour would show up as a two-minute trip.
///
/// Here a discard because of [FixRejection.withinNoise] is not lost data, it
/// is **proof that the vehicle has not moved**. Time advances with every fix;
/// only the distance depends on fixes being accepted.
///
/// ## Hysteresis in stop detection
///
/// With a single threshold, a car hovering around it goes in and out of
/// "stopped" several times a minute and generates dozens of two-second stops.
/// That is why there are two thresholds, [stopSpeedKmh] to enter and
/// [resumeSpeedKmh] to leave, and a minimum duration before the stop is
/// accepted.
@experimental
class TripRecorder {
  /// Creates a recorder.
  ///
  /// The defaults suit an urban taxi: it counts as stopped below 3 km/h, as
  /// moving above 8, and a stop counts from 45 seconds on, which leaves out
  /// short traffic lights.
  TripRecorder({
    PositionFilter? filter,
    this.stopSpeedKmh = 3,
    this.resumeSpeedKmh = 8,
    this.minStopDuration = const Duration(seconds: 45),
    this.keepTrack = true,
  }) : filter = filter ?? PositionFilter() {
    if (resumeSpeedKmh <= stopSpeedKmh) {
      throw ArgumentError.value(
        resumeSpeedKmh,
        'resumeSpeedKmh',
        'Must be greater than stopSpeedKmh, or there is no hysteresis and '
            'the vehicle flips in and out of «stopped» constantly',
      );
    }
  }

  /// The filter that decides which fixes count.
  final PositionFilter filter;

  /// Below this speed it counts as stopped, in km/h.
  final double stopSpeedKmh;

  /// Above this speed it counts as moving, in km/h.
  final double resumeSpeedKmh;

  /// How long a halt has to last to count as a stop.
  final Duration minStopDuration;

  /// Is the full path kept?
  ///
  /// Setting it to `false` saves memory on a server that processes whole
  /// fleets and only needs the totals.
  final bool keepTrack;

  final List<LatLng> _track = <LatLng>[];
  final List<StopPeriod> _stops = <StopPeriod>[];
  final Map<FixRejection, int> _rejections = <FixRejection, int>{};

  DateTime? _start;
  DateTime? _lastTime;
  double _distance = 0;
  double _maxSpeed = 0;
  int _accepted = 0;

  DateTime? _stopCandidate;
  LatLng? _stopPosition;
  bool _stopConfirmed = false;
  Duration _stopped = Duration.zero;

  /// Accumulated distance, in meters.
  double get distanceMeters => _distance;

  /// The stops confirmed so far.
  List<StopPeriod> get stops => List<StopPeriod>.unmodifiable(_stops);

  /// Is it stopped right now?
  bool get isStopped => _stopConfirmed;

  /// Processes a fix and returns the state of the trip.
  TripUpdate add(PositionFix fix) {
    final result = filter.add(fix);
    if (result.rejection == FixRejection.outOfOrder) {
      // An old fix cannot move the clock backwards.
      _rejections.update(
        FixRejection.outOfOrder,
        (n) => n + 1,
        ifAbsent: () => 1,
      );
      return _snapshot(result, 0);
    }

    _start ??= fix.timestamp;
    final previous = _lastTime;
    _lastTime = fix.timestamp;

    final speed = _speedFrom(fix, result);
    if (speed > _maxSpeed) _maxSpeed = speed;

    if (result.accepted) {
      _accepted++;
      _distance += result.distanceMeters;
      if (keepTrack) _track.add(result.fix.position);
    } else {
      _rejections.update(result.rejection!, (n) => n + 1, ifAbsent: () => 1);
    }

    _updateStops(fix, speed, previous);
    return _snapshot(result, speed);
  }

  /// The speed used to decide whether it is stopped.
  ///
  /// The receiver's is preferred —it comes from Doppler and is more
  /// reliable—; if it is missing, it is computed. A discard as noise means
  /// zero: that is exactly what the filter has just determined.
  double _speedFrom(PositionFix fix, FilterResult result) {
    if (result.rejection == FixRejection.withinNoise) return 0;
    final declared = fix.speedKmh;
    if (declared != null) return math.max(0, declared);
    return result.impliedSpeedKmh ?? 0;
  }

  void _updateStops(PositionFix fix, double speed, DateTime? previous) {
    if (speed <= stopSpeedKmh) {
      // The stop started at the previous fix, not at this one: by the time it
      // is detected it had been stopped for the whole interval.
      _stopCandidate ??= previous ?? fix.timestamp;
      _stopPosition ??= fix.position;
      if (!_stopConfirmed &&
          fix.timestamp.difference(_stopCandidate!) >= minStopDuration) {
        _stopConfirmed = true;
      }
      return;
    }

    if (speed >= resumeSpeedKmh) {
      if (_stopConfirmed && _stopCandidate != null) {
        final stop = StopPeriod(
          position: _stopPosition ?? fix.position,
          start: _stopCandidate!,
          end: previous ?? fix.timestamp,
        );
        if (stop.duration > Duration.zero) {
          _stops.add(stop);
          _stopped += stop.duration;
        }
      }
      _stopCandidate = null;
      _stopPosition = null;
      _stopConfirmed = false;
    }
    // Between the two thresholds the state does not change: that band is the
    // hysteresis, and it is what prevents a hundred two-second stops.
  }

  TripUpdate _snapshot(FilterResult result, double speed) {
    final total = _start == null || _lastTime == null
        ? Duration.zero
        : _lastTime!.difference(_start!);
    final stopped = _stopped + _openStopDuration();
    return TripUpdate(
      filter: result,
      distanceMeters: _distance,
      duration: total,
      movingDuration: total - stopped < Duration.zero
          ? Duration.zero
          : total - stopped,
      stoppedDuration: stopped,
      stopped: _stopConfirmed,
      speedKmh: speed,
    );
  }

  Duration _openStopDuration() {
    if (!_stopConfirmed || _stopCandidate == null || _lastTime == null) {
      return Duration.zero;
    }
    return _lastTime!.difference(_stopCandidate!);
  }

  /// Closes the trip and returns the summary.
  ///
  /// If the vehicle ended up stopped, that stop is closed here: without this,
  /// a taxi that ends the trip waiting for the passenger to pay would lose
  /// those minutes of waiting.
  TripSummary finish() {
    // `_stopPosition` is set at the same time as `_stopConfirmed`, so it
    // cannot be missing here. It is checked anyway: the alternative would be
    // to make up a `LatLng(0, 0)` —the Gulf of Guinea— and this package does
    // not do that anywhere.
    final finalPosition = _stopPosition ?? filter.last?.position;
    if (_stopConfirmed &&
        _stopCandidate != null &&
        _lastTime != null &&
        finalPosition != null) {
      final stop = StopPeriod(
        position: finalPosition,
        start: _stopCandidate!,
        end: _lastTime!,
      );
      if (stop.duration > Duration.zero) {
        _stops.add(stop);
        _stopped += stop.duration;
      }
      _stopConfirmed = false;
      _stopCandidate = null;
    }

    final start = _start ?? DateTime.fromMillisecondsSinceEpoch(0);
    final end = _lastTime ?? start;
    final total = end.difference(start);

    return TripSummary(
      start: start,
      end: end,
      distanceMeters: _distance,
      movingDuration: total - _stopped < Duration.zero
          ? Duration.zero
          : total - _stopped,
      stoppedDuration: _stopped,
      stops: List<StopPeriod>.unmodifiable(_stops),
      track: List<LatLng>.unmodifiable(_track),
      acceptedFixes: _accepted,
      rejections: Map<FixRejection, int>.unmodifiable(_rejections),
      maxSpeedKmh: _maxSpeed,
    );
  }

  /// Returns to the initial state to start another trip.
  void reset() {
    filter.reset();
    _track.clear();
    _stops.clear();
    _rejections.clear();
    _start = null;
    _lastTime = null;
    _distance = 0;
    _maxSpeed = 0;
    _accepted = 0;
    _stopCandidate = null;
    _stopPosition = null;
    _stopConfirmed = false;
    _stopped = Duration.zero;
  }
}
