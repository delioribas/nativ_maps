// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/lat_lng.dart';
import 'package:nativ_maps/src/trip/position_filter.dart';
import 'package:nativ_maps/src/trip/trip_recorder.dart';

/// How the final amount is rounded.
///
/// In many markets rounding is regulated and not optional.
@experimental
enum FareRounding {
  /// The amount is left exact.
  none,

  /// To the nearest multiple of 5 minor units.
  nearest5,

  /// To the nearest multiple of 10.
  nearest10,

  /// To the nearest multiple of 50.
  nearest50,

  /// To the nearest major unit: the euro, the dollar.
  nearestMajor,

  /// Always up, to the major unit.
  upToMajor,
}

/// A time band with its own surcharge.
///
/// It covers the night tariff, the weekend tariff and the holiday tariff,
/// which are the norm in any regulated market.
///
/// ```dart
/// // Night: from 22:00 to 06:00, every day, 25 % more expensive.
/// const night = TariffBand(
///   name: 'Night',
///   startOfDay: Duration(hours: 22),
///   endOfDay: Duration(hours: 6),
///   multiplier: 1.25,
/// );
/// ```
@immutable
@experimental
class TariffBand {
  /// Creates a band.
  const TariffBand({
    required this.name,
    required this.startOfDay,
    required this.endOfDay,
    this.multiplier = 1.0,
    this.weekdays = const <int>{1, 2, 3, 4, 5, 6, 7},
  });

  /// The name shown in the breakdown.
  final String name;

  /// The time of day it starts, counted from midnight.
  final Duration startOfDay;

  /// The time of day it ends.
  ///
  /// If it is **earlier** than [startOfDay], the band crosses midnight. That
  /// is the usual case for the night band: `22:00` to `06:00`.
  final Duration endOfDay;

  /// What the flagfall, the per-kilometer and the per-minute rates are
  /// multiplied by.
  final double multiplier;

  /// The days of the week on which it applies.
  ///
  /// It uses the `DateTime` constants: `DateTime.monday` is 1 and
  /// `DateTime.sunday` is 7.
  final Set<int> weekdays;

  /// Is this band active at that moment?
  bool appliesAt(DateTime moment) {
    final sinceMidnight = Duration(
      hours: moment.hour,
      minutes: moment.minute,
      seconds: moment.second,
    );
    final wrapsMidnight = endOfDay <= startOfDay;

    // When the band crosses midnight, the stretch that falls after 00:00
    // belongs to the previous day. A Friday night band configured only for
    // Fridays must still be active at 01:00 on Saturday, or the passenger
    // pays the day tariff at that hour.
    if (wrapsMidnight) {
      if (sinceMidnight >= startOfDay) {
        return weekdays.contains(moment.weekday);
      }
      if (sinceMidnight < endOfDay) {
        final previousDay = moment.weekday == DateTime.monday
            ? DateTime.sunday
            : moment.weekday - 1;
        return weekdays.contains(previousDay);
      }
      return false;
    }

    return weekdays.contains(moment.weekday) &&
        sinceMidnight >= startOfDay &&
        sinceMidnight < endOfDay;
  }

  @override
  String toString() => 'TariffBand($name, ×$multiplier)';
}

/// A fixed charge added to the trip.
///
/// Airport, luggage, advance booking, urban toll, cleaning.
@immutable
@experimental
class Surcharge {
  /// Creates a charge.
  const Surcharge({
    required this.name,
    required this.amount,
    this.surgeable = false,
  });

  /// The name shown in the breakdown.
  final String name;

  /// The amount, in minor units.
  final int amount;

  /// Does demand multiply it?
  ///
  /// By default **no**, which is almost always right: a three-euro airport
  /// surcharge doesn't start costing five because it's raining. Those set to
  /// `true` are added to the base **before** demand is applied and before the
  /// minimum is checked.
  final bool surgeable;

  @override
  String toString() => 'Surcharge($name, $amount)';
}

/// One line of the fare breakdown.
///
/// Every amount charged has its own, with the calculation that produced it
/// written in [detail]. It's what you show when someone files a complaint.
@immutable
@experimental
class FareLine {
  /// Creates a line.
  const FareLine({required this.label, required this.amount, this.detail = ''});

  /// What the item is.
  final String label;

  /// The amount, in minor units.
  final int amount;

  /// The calculation that produced the amount, for example `12.4 km × 85`.
  final String detail;

  @override
  String toString() =>
      detail.isEmpty ? '$label: $amount' : '$label: $amount  ($detail)';
}

/// The fare of a trip, broken down.
///
/// **A bare total is never returned.** A lone number can't be justified,
/// can't be audited and can't be reproduced six months later when the
/// complaint arrives.
@immutable
@experimental
class FareBreakdown {
  /// Creates a breakdown.
  const FareBreakdown({
    required this.currency,
    required this.minorUnitDigits,
    required this.lines,
    required this.total,
  });

  /// The ISO 4217 currency code, for example `EUR`.
  final String currency;

  /// How many decimal places the currency has.
  ///
  /// Two for the euro and the dollar, zero for the Chilean peso and the yen.
  final int minorUnitDigits;

  /// All the lines, in the order they were applied.
  final List<FareLine> lines;

  /// The total to charge, in minor units.
  final int total;

  /// The total as a decimal number.
  ///
  /// **For display only.** Never do arithmetic with this value: binary
  /// floating point can't represent cents exactly, and adding up a thousand
  /// rides this way leaves the books out of balance.
  double get totalAsDecimal => total / math.pow(10, minorUnitDigits);

  /// The formatted total, for example `12,45`.
  String get formattedTotal => formatAmount(total);

  /// Formats an amount given in minor units.
  String formatAmount(int minorUnits) {
    if (minorUnitDigits == 0) return '$minorUnits';
    final divisor = math.pow(10, minorUnitDigits).toInt();
    final whole = minorUnits ~/ divisor;
    final remainder = (minorUnits % divisor).abs();
    return '$whole,${remainder.toString().padLeft(minorUnitDigits, '0')}';
  }

  /// The full breakdown as text, ready for a receipt or a log.
  String toReceipt() {
    final buffer = StringBuffer();
    for (final line in lines) {
      buffer.write(line.label.padRight(28));
      buffer.write(formatAmount(line.amount).padLeft(10));
      if (line.detail.isNotEmpty) buffer.write('   ${line.detail}');
      buffer.writeln();
    }
    buffer
      ..writeln('-' * 38)
      ..writeln(
        '${'TOTAL'.padRight(28)}${formattedTotal.padLeft(10)}  $currency',
      );
    return buffer.toString();
  }

  @override
  String toString() =>
      'FareBreakdown($formattedTotal $currency, '
      '${lines.length} line(s))';
}

/// A taxi or private-hire tariff, and the engine that applies it.
///
/// ```dart
/// const tariff = Tariff(
///   currency: 'EUR',
///   baseFare: 250,        // €2.50 flagfall
///   perKilometer: 110,    // €1.10 per kilometer
///   perMinute: 35,        // €0.35 per minute while moving
///   waitingPerMinute: 30, // €0.30 per minute stopped
///   minimumFare: 500,     // €5.00 minimum
///   rounding: FareRounding.nearest5,
/// );
///
/// final fare = tariff.quote(trip);
/// print(fare.toReceipt());
/// ```
///
/// ## Everything in minor units, as integers
///
/// Amounts are **cents**, not euros, and they are `int`, not `double`. A
/// `double` can't represent 0.10 exactly; adding up ten €1.10 rides gives
/// 11.000000000000002 and the till doesn't balance at the end of the month.
/// Integers don't have that problem, and rounding happens **only once**, at
/// the end, where the law says it should.
@immutable
@experimental
class Tariff {
  /// Creates a tariff.
  const Tariff({
    required this.currency,
    required this.baseFare,
    this.perKilometer = 0,
    this.perMinute = 0,
    this.waitingPerMinute = 0,
    this.waitingGrace = Duration.zero,
    this.minimumFare = 0,
    this.minorUnitDigits = 2,
    this.rounding = FareRounding.none,
    this.bands = const <TariffBand>[],
    this.surcharges = const <Surcharge>[],
  });

  /// The ISO 4217 currency code.
  final String currency;

  /// How many decimal places the currency has.
  final int minorUnitDigits;

  /// The flagfall, in minor units.
  final int baseFare;

  /// What each kilometer costs.
  final int perKilometer;

  /// What each minute **while moving** costs.
  ///
  /// Mixed tariffs charge distance and time together; distance-only tariffs
  /// leave this at zero.
  final int perMinute;

  /// What each minute **stopped** costs.
  final int waitingPerMinute;

  /// How much waiting is free before it starts being charged.
  ///
  /// It is deducted from the trip as a whole, not from each stop: otherwise
  /// twenty one-minute traffic lights, each with its own minute of grace,
  /// come out free.
  final Duration waitingGrace;

  /// The minimum fare for a ride.
  final int minimumFare;

  /// How the total is rounded.
  final FareRounding rounding;

  /// The time bands, in order of priority.
  ///
  /// **The first one that matches** applies, so the more specific ones go
  /// first: the holiday band ahead of the weekend band.
  ///
  /// > **Band times are read in the same time zone as the trip's
  /// > timestamps.** A night band that starts at 22:00 only starts at 22:00
  /// > city time if the trip comes with local timestamps. If the server
  /// > stores UTC —which is the right thing to do—, convert to the city's
  /// > time zone before pricing, or define the bands in UTC. Mixing the two
  /// > shifts the night tariff by several hours.
  final List<TariffBand> bands;

  /// Fixed charges that always apply.
  final List<Surcharge> surcharges;

  /// Calculates the fare of a trip.
  ///
  /// ## How it's split when the trip crosses a band
  ///
  /// A trip that starts at 21:50 and ends at 22:10 has ten minutes of day
  /// tariff and ten of night tariff. Charging all of it at the starting
  /// tariff —what almost all software does— is wrong, and in a regulated
  /// market it can get you fined.
  ///
  /// Here the trip is **split at the band boundaries**:
  ///
  /// - **Time** is split exactly, because stops have a start and an end
  ///   time.
  /// - **Distance** is split in proportion to each segment's moving time.
  ///   It's an approximation: a trip that runs on the highway before 22:00
  ///   and through the city afterwards assigns the night band more
  ///   kilometers than it actually covered. The error is bounded by how much
  ///   the average speed changes between segments, and on an urban route it
  ///   is small.
  ///
  /// [surgeMultiplier] multiplies the variable part —flagfall, distance and
  /// time— but **not** the charges with `surgeable: false` nor the tolls.
  ///
  /// [tolls] are the tolls in minor units; they come from
  /// `Route.tollCostByCurrency`.
  FareBreakdown quote(
    TripSummary trip, {
    double surgeMultiplier = 1.0,
    int tolls = 0,
    List<Surcharge> extraSurcharges = const <Surcharge>[],
  }) {
    if (surgeMultiplier <= 0) {
      throw ArgumentError.value(
        surgeMultiplier,
        'surgeMultiplier',
        'Must be greater than zero',
      );
    }

    final lines = <FareLine>[];
    final segments = _splitByBands(trip);

    // ── Flagfall, with the multiplier of the starting band
    final startBand = _bandAt(trip.start);
    final startMultiplier = startBand?.multiplier ?? 1.0;
    final flagfall = (baseFare * startMultiplier).round();
    if (flagfall != 0) {
      lines.add(
        FareLine(
          label: 'Flagfall',
          amount: flagfall,
          detail: startBand == null
              ? ''
              : '${startBand.name} ×${startBand.multiplier}',
        ),
      );
    }

    // ── Free waiting, deducted from the total and not from each stop
    var graceLeft = waitingGrace;

    for (final segment in segments) {
      final multiplier = segment.band?.multiplier ?? 1.0;
      final label = segment.band?.name ?? 'Standard';

      if (perKilometer != 0 && segment.distanceMeters > 0) {
        final km = segment.distanceMeters / 1000;
        lines.add(
          FareLine(
            label: '$label · distance',
            amount: (km * perKilometer * multiplier).round(),
            detail:
                '${km.toStringAsFixed(2)} km × '
                '${formatMinor(perKilometer)}'
                '${multiplier == 1.0 ? '' : ' ×$multiplier'}',
          ),
        );
      }

      if (perMinute != 0 && segment.moving > Duration.zero) {
        final minutos = segment.moving.inMicroseconds / 6e7;
        lines.add(
          FareLine(
            label: '$label · time',
            amount: (minutos * perMinute * multiplier).round(),
            detail:
                '${minutos.toStringAsFixed(1)} min × '
                '${formatMinor(perMinute)}'
                '${multiplier == 1.0 ? '' : ' ×$multiplier'}',
          ),
        );
      }

      if (waitingPerMinute != 0 && segment.stopped > Duration.zero) {
        final billable = segment.stopped - graceLeft;
        graceLeft = graceLeft - segment.stopped;
        if (graceLeft < Duration.zero) {
          graceLeft = Duration.zero;
        }
        if (billable > Duration.zero) {
          final minutos = billable.inMicroseconds / 6e7;
          lines.add(
            FareLine(
              label: '$label · waiting',
              amount: (minutos * waitingPerMinute * multiplier).round(),
              detail:
                  '${minutos.toStringAsFixed(1)} min × '
                  '${formatMinor(waitingPerMinute)}'
                  '${multiplier == 1.0 ? '' : ' ×$multiplier'}',
            ),
          );
        }
      }
    }

    // ── Charges that demand does multiply, before applying it
    final allSurcharges = <Surcharge>[...surcharges, ...extraSurcharges];
    for (final surcharge in allSurcharges) {
      if (surcharge.surgeable && surcharge.amount != 0) {
        lines.add(FareLine(label: surcharge.name, amount: surcharge.amount));
      }
    }

    var variable = lines.fold<int>(0, (sum, l) => sum + l.amount);

    // ── Demand
    if (surgeMultiplier != 1.0) {
      final increase = (variable * (surgeMultiplier - 1)).round();
      lines.add(
        FareLine(
          label: 'Surge',
          amount: increase,
          detail: '×${surgeMultiplier.toStringAsFixed(2)}',
        ),
      );
      variable += increase;
    }

    // ── Minimum, before adding what must not be affected by it
    if (minimumFare > 0 && variable < minimumFare) {
      final fit = minimumFare - variable;
      lines.add(
        FareLine(
          label: 'Minimum fare',
          amount: fit,
          detail: 'minimum ${formatMinor(minimumFare)}',
        ),
      );
      variable = minimumFare;
    }

    // ── Fixed charges that demand doesn't multiply, and tolls
    var total = variable;
    for (final surcharge in allSurcharges) {
      if (surcharge.surgeable || surcharge.amount == 0) continue;
      lines.add(FareLine(label: surcharge.name, amount: surcharge.amount));
      total += surcharge.amount;
    }
    if (tolls != 0) {
      lines.add(FareLine(label: 'Tolls', amount: tolls));
      total += tolls;
    }

    // ── Rounding, only once and at the end
    final rounded = applyRounding(total);
    if (rounded != total) {
      lines.add(
        FareLine(
          label: 'Rounding',
          amount: rounded - total,
          detail: rounding.name,
        ),
      );
    }

    return FareBreakdown(
      currency: currency,
      minorUnitDigits: minorUnitDigits,
      lines: List<FareLine>.unmodifiable(lines),
      total: rounded,
    );
  }

  /// Formats an amount in this currency's minor units.
  String formatMinor(int minorUnits) {
    if (minorUnitDigits == 0) return '$minorUnits';
    final divisor = math.pow(10, minorUnitDigits).toInt();
    final remainder = (minorUnits % divisor).abs();
    return '${minorUnits ~/ divisor},'
        '${remainder.toString().padLeft(minorUnitDigits, '0')}';
  }

  /// An estimate **before** starting, from a calculated route.
  ///
  /// It's for showing "about €12" when the car is requested. It doesn't
  /// replace [quote]: there are no stops yet, so waiting isn't included, and
  /// the time is the one the service predicted, not the one that happened.
  FareBreakdown estimate({
    required double distanceMeters,
    required Duration duration,
    DateTime? departure,
    double surgeMultiplier = 1.0,
    int tolls = 0,
  }) {
    final start = departure ?? DateTime.now();
    return quote(
      TripSummary(
        start: start,
        end: start.add(duration),
        distanceMeters: distanceMeters,
        movingDuration: duration,
        stoppedDuration: Duration.zero,
        stops: const <StopPeriod>[],
        track: const <LatLng>[],
        acceptedFixes: 0,
        rejections: const <FixRejection, int>{},
        maxSpeedKmh: 0,
      ),
      surgeMultiplier: surgeMultiplier,
      tolls: tolls,
    );
  }

  TariffBand? _bandAt(DateTime moment) {
    for (final band in bands) {
      if (band.appliesAt(moment)) return band;
    }
    return null;
  }

  /// Rounds [amount], in minor units, with this tariff's [rounding] rule.
  ///
  /// It's the same rule [quote] applies to the total. Any amount shown to
  /// the passenger next to a figure from this tariff —a minimum bid, a
  /// suggested price— has to go through here, or a `1,28` will show up next
  /// to a `1,50`.
  int applyRounding(int amount) {
    final majorUnit = math.pow(10, minorUnitDigits).toInt();
    return switch (rounding) {
      FareRounding.none => amount,
      FareRounding.nearest5 => (amount / 5).round() * 5,
      FareRounding.nearest10 => (amount / 10).round() * 10,
      FareRounding.nearest50 => (amount / 50).round() * 50,
      FareRounding.nearestMajor => (amount / majorUnit).round() * majorUnit,
      FareRounding.upToMajor => (amount / majorUnit).ceil() * majorUnit,
    };
  }

  /// Splits the trip at the time band boundaries.
  List<_Segment> _splitByBands(TripSummary trip) {
    final boundaries = <DateTime>{trip.start, trip.end};

    if (bands.isNotEmpty) {
      // The candidate boundaries are the start and end times of each band,
      // on each day the trip touches. A trip lasts minutes or hours, so they
      // are a handful of dates, not a sweep.
      // The trip's time zone is preserved. Building a local `DateTime` here
      // when the timestamps come in UTC would put the night band cutoff at
      // 22:00 on the machine, not at 22:00 on the trip: on a server in
      // another time zone the tariff would change hour without anyone
      // touching anything.
      var day = _midnight(trip.start);
      final lastDay = _midnight(trip.end).add(const Duration(days: 1));
      while (!day.isAfter(lastDay)) {
        for (final band in bands) {
          for (final timeOfDay in <Duration>[band.startOfDay, band.endOfDay]) {
            final boundary = day.add(timeOfDay);
            if (boundary.isAfter(trip.start) && boundary.isBefore(trip.end)) {
              boundaries.add(boundary);
            }
          }
        }
        day = day.add(const Duration(days: 1));
      }
    }

    final sorted = boundaries.toList()..sort();
    final totalMoving = trip.movingDuration.inMicroseconds;

    return <_Segment>[
      for (var i = 0; i < sorted.length - 1; i++)
        _segmentBetween(trip, sorted[i], sorted[i + 1], totalMoving),
    ];
  }

  _Segment _segmentBetween(
    TripSummary trip,
    DateTime from,
    DateTime to,
    int totalMoving,
  ) {
    final duration = to.difference(from);
    var stopped = Duration.zero;
    for (final stop in trip.stops) {
      stopped += _overlap(from, to, stop.start, stop.end);
    }
    var moving = duration - stopped;
    if (moving < Duration.zero) moving = Duration.zero;

    // Distance is split in proportion to moving time.
    final distance = totalMoving <= 0
        ? 0.0
        : trip.distanceMeters * moving.inMicroseconds / totalMoving;

    return _Segment(
      band: _bandAt(from),
      moving: moving,
      stopped: stopped,
      distanceMeters: distance,
    );
  }

  static DateTime _midnight(DateTime moment) => moment.isUtc
      ? DateTime.utc(moment.year, moment.month, moment.day)
      : DateTime(moment.year, moment.month, moment.day);

  static Duration _overlap(
    DateTime aDesde,
    DateTime aHasta,
    DateTime bDesde,
    DateTime bHasta,
  ) {
    final start = aDesde.isAfter(bDesde) ? aDesde : bDesde;
    final end = aHasta.isBefore(bHasta) ? aHasta : bHasta;
    final d = end.difference(start);
    return d < Duration.zero ? Duration.zero : d;
  }
}

@immutable
class _Segment {
  const _Segment({
    required this.band,
    required this.moving,
    required this.stopped,
    required this.distanceMeters,
  });

  final TariffBand? band;
  final Duration moving;
  final Duration stopped;
  final double distanceMeters;
}
