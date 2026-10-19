// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/trip/auction.dart';
import 'package:nativ_maps/src/trip/dispatch.dart';
import 'package:nativ_maps/src/trip/fare.dart';

/// A named demand pressure, so the breakdown can be explained.
///
/// Rain, a match letting out, the last metro. The engine doesn't guess them
/// —it has no way to— but it does multiply them and write them down in the
/// breakdown, which is what lets you answer "why are you suggesting 9 and not
/// 6?".
@immutable
@experimental
class DemandSignal {
  /// Creates a signal.
  const DemandSignal({required this.name, required this.multiplier});

  /// Moderate rain: demand goes up and supply goes down at the same time.
  static const DemandSignal rain = DemandSignal(name: 'Rain', multiplier: 1.15);

  /// A large event letting out.
  static const DemandSignal event = DemandSignal(
    name: 'Event',
    multiplier: 1.30,
  );

  /// A time band with no public transport.
  static const DemandSignal noTransit = DemandSignal(
    name: 'No public transport',
    multiplier: 1.20,
  );

  /// The name shown in the breakdown.
  final String name;

  /// What it multiplies by.
  final double multiplier;

  @override
  String toString() => 'DemandSignal($name, ×$multiplier)';
}

/// The state of the market at request time.
///
/// What the platform knows and the device doesn't: how many cars are free and
/// how many people are requesting at the same time.
@immutable
@experimental
class MarketConditions {
  /// Creates a market state.
  const MarketConditions({
    this.availableDrivers = 0,
    this.openRequests = 0,
    this.signals = const <DemandSignal>[],
    this.returnEmptyProbability = 0,
    this.congestionFactor = 1.0,
  });

  /// How many free drivers there are in the area.
  final int availableDrivers;

  /// How many unassigned requests are competing for them.
  final int openRequests;

  /// Named demand pressures.
  final List<DemandSignal> signals;

  /// Probability that the driver comes back empty, between 0 and 1.
  ///
  /// A trip that ends in an industrial park at eleven at night forces the
  /// driver to come back with no passenger, and the driver pays for that
  /// mileage. Without a premium that covers it, nobody takes those rides and
  /// the passenger is left waiting without understanding why.
  final double returnEmptyProbability;

  /// How much longer the trip takes than without traffic.
  ///
  /// It comes from comparing the duration with `TrafficUsage.useTrafficData`
  /// and with `TrafficUsage.ignoreTrafficData`. `1.0` is free-flowing traffic;
  /// `1.6` is a trip that takes 60 % longer because of congestion.
  ///
  /// It only applies if the tariff does **not** charge per minute: when it
  /// does, the congestion is already paid for and adding it again would charge
  /// it twice.
  final double congestionFactor;

  /// How many requests there are per free driver.
  ///
  /// It is the standard measure of market pressure. With no drivers it returns
  /// infinity, which the engine clamps to the configured cap.
  double get demandRatio {
    if (availableDrivers <= 0) return double.infinity;
    return openRequests / availableDrivers;
  }

  @override
  String toString() =>
      'MarketConditions($openRequests peticiones / $availableDrivers libres)';
}

/// A factor that moved the suggested price, and by how much.
@immutable
@experimental
class PriceFactor {
  /// Creates a factor.
  const PriceFactor({
    required this.name,
    required this.multiplier,
    this.detail = '',
  });

  /// What it is.
  final String name;

  /// What it multiplied by.
  final double multiplier;

  /// The short explanation.
  final String detail;

  @override
  String toString() =>
      '$name ×${multiplier.toStringAsFixed(2)}'
      '${detail.isEmpty ? '' : ' ($detail)'}';
}

/// How many drivers would accept an amount, and who would arrive first.
///
/// When there is real data on nearby drivers this is **not an estimate**: it
/// is counting how many of them make money at that amount.
@immutable
@experimental
class AcceptanceForecast {
  /// Creates a forecast.
  const AcceptanceForecast({
    required this.probability,
    required this.driversLikelyToAccept,
    required this.driversConsidered,
    required this.expectedPickup,
    required this.estimated,
  });

  /// Probability that **someone** accepts, between 0 and 1.
  final double probability;

  /// How many of the nearby drivers make money at that amount.
  final int driversLikelyToAccept;

  /// How many drivers it was calculated over.
  final int driversConsidered;

  /// How long the closest of the drivers who would accept would take to
  /// arrive.
  ///
  /// It is the real driving time returned by the route matrix, not a guess. It
  /// is `null` if nobody would accept.
  final Duration? expectedPickup;

  /// Is there any assumption behind this number?
  ///
  /// `false` only when real drivers were counted, **all of them refined by the
  /// route matrix**. It is `true` in two cases:
  ///
  /// - no driver was passed, and the probability comes from a parametric curve
  ///   that **must be calibrated** (see `PriceAdvisor.fallbackSteepness`);
  /// - drivers were passed but some of them didn't go through the matrix, so
  ///   their pickup time is a straight-line estimate.
  ///
  /// Don't show a percentage with decimals when this is `true`.
  final bool estimated;

  @override
  String toString() => estimated
      ? 'AcceptanceForecast(${(probability * 100).round()} % estimated)'
      : 'AcceptanceForecast($driversLikelyToAccept of $driversConsidered, '
            'arrives in ${expectedPickup?.inMinutes ?? '—'} min)';
}

/// The suggested price for a ride, shaped the way inDrive does it.
///
/// Three numbers and the reason behind each one.
@immutable
@experimental
class SuggestedPrice {
  /// Creates a suggestion.
  const SuggestedPrice({
    required this.currency,
    required this.minorUnitDigits,
    required this.reference,
    required this.minimum,
    required this.recommended,
    required this.fast,
    required this.extrasPaidSeparately,
    required this.demandMultiplier,
    required this.factors,
    required this.forecast,
  });

  /// The ISO 4217 currency code.
  final String currency;

  /// How many decimal places the currency has.
  final int minorUnitDigits;

  /// What it would cost with the reference tariff, with no market.
  ///
  /// It is the honest anchor: what the trip would be worth on a quiet Tuesday.
  final int reference;

  /// The **recommended minimum bid**.
  ///
  /// Below this no nearby driver makes money, so the request goes unanswered.
  /// It is not a prohibition: it is the line past which the passenger is
  /// asking someone to work for free.
  final int minimum;

  /// The price shown by default.
  final int recommended;

  /// What you have to offer for the **closest** driver to accept.
  ///
  /// Sometimes it matches [recommended]; when it doesn't, the difference is
  /// exactly what being in a hurry costs.
  final int fast;

  /// Tolls and fees, which the passenger pays separately.
  ///
  /// **They are not part of the price**, just like in inDrive: they are an
  /// amount that isn't negotiated and that the driver doesn't keep.
  final int extrasPaidSeparately;

  /// The total market multiplier that was applied.
  final double demandMultiplier;

  /// Everything that moved the price, in order.
  final List<PriceFactor> factors;

  /// What would happen with [recommended].
  final AcceptanceForecast forecast;

  /// Formats an amount in minor units.
  String formatAmount(int minorUnits) {
    if (minorUnitDigits == 0) return '$minorUnits';
    final divisor = math.pow(10, minorUnitDigits).toInt();
    final remainder = (minorUnits % divisor).abs();
    return '${minorUnits ~/ divisor},'
        '${remainder.toString().padLeft(minorUnitDigits, '0')}';
  }

  /// The breakdown as text, to show it or log it.
  String explain() {
    final buffer = StringBuffer()
      ..writeln('Reference           ${formatAmount(reference)} $currency');
    for (final factor in factors) {
      buffer.writeln('  $factor');
    }
    buffer
      ..writeln('Minimum bid         ${formatAmount(minimum)}')
      ..writeln('Recommended         ${formatAmount(recommended)}')
      ..writeln('Fastest pickup      ${formatAmount(fast)}');
    if (extrasPaidSeparately != 0) {
      buffer.writeln(
        'Tolls and fees      ${formatAmount(extrasPaidSeparately)} '
        '(paid separately)',
      );
    }
    buffer.writeln('Forecast            $forecast');
    return buffer.toString();
  }

  @override
  String toString() =>
      'SuggestedPrice(${formatAmount(minimum)} – '
      '${formatAmount(recommended)} $currency)';
}

/// Calculates the suggested price of a ride in a bidding market.
///
/// ```dart
/// final advisor = PriceAdvisor(tariff: tariff, economics: costs);
///
/// // 1 · The route gives distance, duration with traffic, and tolls.
/// final route = (await maps.routes.calculateRoutes(
///   origin: pickup, destination: destination,
/// )).best!;
///
/// // 2 · The matrix gives each driver's REAL pickup time.
/// final nearby = await planner.findNearest(onlineDrivers, pickup);
///
/// // 3 · And from that comes the price.
/// final price = advisor.suggest(
///   distanceMeters: route.distanceMeters,
///   duration: route.duration,
///   nearbyDrivers: nearby,
///   market: MarketConditions(
///     availableDrivers: nearby.length,
///     openRequests: unassignedRequests,
///     signals: <DemandSignal>[if (isRaining) DemandSignal.rain],
///   ),
///   tolls: route.tollCostInMinorUnits('USD'),
/// );
/// print(price.explain());
/// ```
///
/// ## Where each number comes from
///
/// The model has four layers, and each one answers a different question:
///
/// | Layer | Question | Where it comes from |
/// |---|---|---|
/// | Reference | what is this trip worth? | `Tariff` + the route |
/// | Supply floor | what does a driver need to charge? | route matrix |
/// | Demand | how many people am I competing with? | requests ÷ drivers |
/// | Forecast | how many would accept? | count over the real ones |
///
/// ## Why this is not a made-up formula
///
/// The hard part of a bidding market is knowing **at what price someone
/// answers**. The usual approach is to make up a curve and show a percentage
/// with two decimals that nobody has measured.
///
/// Here there's no need. With the real pickup times returned by
/// `calculateRouteMatrix`, each nearby driver's reservation price is
/// **computable**: it is their [BidAdvisor.breakEvenFare]. And then "how many
/// would accept at this price" stops being an estimate and becomes a count.
///
/// Only when no drivers are passed does it fall back to a parametric curve,
/// and the result comes flagged with `estimated: true` so it isn't mistaken
/// for a count.
///
/// ## Why pickup time weighs more
///
/// Studies of ride acceptance agree that drivers **mind the time spent getting
/// to the pickup more than the same time inside the trip**: it isn't paid, it
/// doesn't bring them closer to the destination and it competes with the
/// chance that something better comes up. [pickupAversion] captures that by
/// inflating the deadhead time when calculating the reservation price.
@immutable
@experimental
class PriceAdvisor {
  /// Creates a price advisor.
  const PriceAdvisor({
    required this.tariff,
    required this.economics,
    this.surgeExponent = 0.6,
    this.maxSurge = 2.5,
    this.minimumRatio = 0.85,
    this.pickupAversion = 1.6,
    this.targetAcceptance = 0.5,
    this.fastMargin = 1.08,
    this.fallbackSteepness = 9.0,
    this.detourFactor = 1.4,
    this.urbanSpeedKmh = 24,
  });

  /// The reference tariff: what the trip would be worth with no market.
  final Tariff tariff;

  /// The driver's costs, to calculate their reservation price.
  final DriverEconomics economics;

  /// How strongly the price responds to the imbalance between supply and
  /// demand.
  ///
  /// The multiplier is `ratio ^ surgeExponent`, with the ratio in requests per
  /// free driver. With `0.6`: two requests per car give ×1.52; three, ×1.93;
  /// five, ×2.63 —clamped by [maxSurge]—.
  ///
  /// An exponent below 1 makes the price rise **less than proportionally** to
  /// the imbalance, which is what you want: a shortage of cars corrects itself
  /// within minutes, and a linear rise overreacts to spikes that fade before
  /// anyone notices them.
  final double surgeExponent;

  /// The cap on the demand multiplier.
  ///
  /// It always exists, and in many markets it is also regulated. Without a
  /// cap, an area with zero free drivers sends the ratio to infinity.
  final double maxSurge;

  /// Floor for the minimum bid, as a fraction of the reference.
  ///
  /// It is only used when there is no data on nearby drivers: with it, the
  /// minimum is the reservation price of the cheapest one, which is better
  /// data.
  final double minimumRatio;

  /// How much more a minute spent getting to the pickup weighs than a minute
  /// of trip.
  ///
  /// `1.6` means twelve minutes of pickup are valued as if they were nineteen.
  /// It is above 1 because deadhead time isn't paid, doesn't bring the driver
  /// closer to the destination and competes with waiting for a better ride.
  ///
  /// It is the parameter most worth calibrating with your own data: it varies
  /// quite a bit between full-time and part-time drivers.
  final double pickupAversion;

  /// What fraction of the nearby drivers should accept the recommended price.
  final double targetAcceptance;

  /// How far above the reservation price to go so that they really accept.
  ///
  /// Nobody accepts a job that leaves them exactly zero margin over their
  /// target. 8 % above turns "I don't lose" into "it's worth it".
  final double fastMargin;

  /// Steepness of the fallback curve, when there are no drivers.
  ///
  /// **This one is a made-up parameter**, and that's why the result it
  /// produces comes flagged with `AcceptanceForecast.estimated`. Calibrate it
  /// with your history of offers and acceptances as soon as you have it.
  final double fallbackSteepness;

  /// How much longer the real trip is than the straight line.
  ///
  /// It is only used with drivers not refined by the matrix. `1.4` is normal
  /// in a regular urban grid.
  final double detourFactor;

  /// Assumed urban speed, for drivers that weren't refined.
  final double urbanSpeedKmh;

  /// Calculates the suggested price.
  ///
  /// [nearbyDrivers] should come from `DispatchPlanner.findNearest`, already
  /// refined with the matrix: without that refinement the calculation works,
  /// but it relies on straight-line distances and the result is flagged as
  /// estimated.
  ///
  /// [tolls] **is not part of the price**: it is reported separately in
  /// [SuggestedPrice.extrasPaidSeparately], just as inDrive does.
  SuggestedPrice suggest({
    required double distanceMeters,
    required Duration duration,
    List<DriverCandidate> nearbyDrivers = const <DriverCandidate>[],
    MarketConditions market = const MarketConditions(),
    DateTime? departure,
    int tolls = 0,
    int fees = 0,
  }) {
    final factors = <PriceFactor>[];

    // ── 1 · Reference: what the trip is worth on a quiet Tuesday
    final reference = tariff
        .estimate(
          distanceMeters: distanceMeters,
          duration: duration,
          departure: departure,
        )
        .total;

    // ── 2 · Market multiplier
    var multiplier = 1.0;

    final ratio = market.demandRatio;
    if (market.availableDrivers > 0 && market.openRequests > 0) {
      final demand = math.pow(ratio, surgeExponent).toDouble();
      final clamped = demand.clamp(1.0, maxSurge);
      if (clamped != 1.0) {
        multiplier *= clamped;
        factors.add(
          PriceFactor(
            name: 'Demand',
            multiplier: clamped,
            detail:
                '${market.openRequests} requests / '
                '${market.availableDrivers} available',
          ),
        );
      }
    } else if (market.availableDrivers == 0 && market.openRequests > 0) {
      multiplier *= maxSurge;
      factors.add(
        PriceFactor(
          name: 'Demand',
          multiplier: maxSurge,
          detail: 'no drivers available (cap)',
        ),
      );
    }

    for (final signal in market.signals) {
      multiplier *= signal.multiplier;
      factors.add(
        PriceFactor(name: signal.name, multiplier: signal.multiplier),
      );
    }

    // Congestion is only charged separately if the tariff does NOT charge per
    // minute: when it does, it is already inside the reference and adding it
    // would charge it twice.
    if (tariff.perMinute == 0 && market.congestionFactor > 1.0) {
      final congestion = market.congestionFactor.clamp(1.0, 2.0);
      multiplier *= congestion;
      factors.add(
        PriceFactor(
          name: 'Traffic',
          multiplier: congestion,
          detail: 'takes ${((congestion - 1) * 100).round()} % longer',
        ),
      );
    }

    if (market.returnEmptyProbability > 0) {
      // Cover the empty return: the mileage back, weighted by the probability
      // of having to make it, expressed as a surcharge on the reference.
      final returnCost =
          distanceMeters /
          1000 *
          economics.costPerKilometer *
          market.returnEmptyProbability.clamp(0.0, 1.0);
      if (reference > 0 && returnCost > 0) {
        final returnLeg = 1 + returnCost / reference;
        multiplier *= returnLeg;
        factors.add(
          PriceFactor(
            name: 'Empty return',
            multiplier: returnLeg,
            detail: '${(market.returnEmptyProbability * 100).round()} % likely',
          ),
        );
      }
    }

    // ── 3 · Supply floor: what each nearby driver needs to charge
    final reservations = _reservationPrices(
      nearbyDrivers,
      distanceMeters,
      duration,
    )..sort();

    final int floorPrice;
    final int supplyFloor;
    if (reservations.isEmpty) {
      floorPrice = (reference * minimumRatio).round();
      supplyFloor = reference;
    } else {
      floorPrice = reservations.first;
      supplyFloor = _quantile(reservations, targetAcceptance);
      if (supplyFloor > reference) {
        factors.add(
          PriceFactor(
            name: 'Distant drivers',
            multiplier: supplyFloor / reference,
            detail:
                'the closest driver is far away; '
                '${reservations.length} driver(s) considered',
          ),
        );
      }
    }

    final base = math.max(reference, supplyFloor);
    final recommendedPrice = (base * multiplier).round();

    // ── 4 · What it costs to get the closest one to come
    final int fastPrice;
    if (nearbyDrivers.isEmpty) {
      fastPrice = recommendedPrice;
    } else {
      final elMasCercano = _soonestToArrive(nearbyDrivers);
      final theirReservation = _reservationPrice(
        elMasCercano,
        distanceMeters,
        duration,
      );
      fastPrice = math.max(
        recommendedPrice,
        (theirReservation * fastMargin * multiplier).round(),
      );
    }

    // The three figures are shown together: either all of them get the
    // tariff's rounding rule, or the minimum comes out at `1,28` next to a
    // recommended `1,50`. Rounding doesn't change the order, so minimum ≤
    // recommended ≤ fast still holds.
    final recommended = tariff.applyRounding(recommendedPrice);

    return SuggestedPrice(
      currency: tariff.currency,
      minorUnitDigits: tariff.minorUnitDigits,
      reference: reference,
      minimum: tariff.applyRounding(math.min(floorPrice, recommendedPrice)),
      recommended: recommended,
      fast: tariff.applyRounding(fastPrice),
      extrasPaidSeparately: tolls + fees,
      demandMultiplier: multiplier,
      factors: List<PriceFactor>.unmodifiable(factors),
      forecast: forecast(
        offered: recommended,
        nearbyDrivers: nearbyDrivers,
        distanceMeters: distanceMeters,
        duration: duration,
        reference: reference,
      ),
    );
  }

  /// How many drivers would accept [offered], and who would arrive first.
  ///
  /// It is what gets called when the price slider moves: with the nearby
  /// drivers at hand, it **counts**; without them, it estimates with a curve
  /// that has to be calibrated.
  AcceptanceForecast forecast({
    required int offered,
    required double distanceMeters,
    required Duration duration,
    List<DriverCandidate> nearbyDrivers = const <DriverCandidate>[],
    int? reference,
  }) {
    if (nearbyDrivers.isEmpty) {
      final anchor =
          reference ??
          tariff
              .estimate(distanceMeters: distanceMeters, duration: duration)
              .total;
      final p = anchor <= 0
          ? 0.0
          : 1 / (1 + math.exp(-fallbackSteepness * (offered / anchor - 0.95)));
      return AcceptanceForecast(
        probability: p,
        driversLikelyToAccept: 0,
        driversConsidered: 0,
        expectedPickup: null,
        estimated: true,
      );
    }

    var wouldAccept = 0;
    Duration? soonest;
    for (final candidate in nearbyDrivers) {
      final reservation = _reservationPrice(
        candidate,
        distanceMeters,
        duration,
      );
      if (offered < reservation) continue;
      wouldAccept++;
      final arrival = _durationOf(candidate);
      if (soonest == null || arrival < soonest) soonest = arrival;
    }

    // If any of them didn't go through the matrix, their pickup time is a
    // guess and the count stops being a count. We say so.
    final allRefined = nearbyDrivers.every((c) => c.refined);

    return AcceptanceForecast(
      probability: wouldAccept / nearbyDrivers.length,
      driversLikelyToAccept: wouldAccept,
      driversConsidered: nearbyDrivers.length,
      expectedPickup: soonest,
      estimated: !allRefined,
    );
  }

  /// A driver's reservation price: below it, it isn't worth it for them.
  int _reservationPrice(
    DriverCandidate candidate,
    double distanceMeters,
    Duration duration,
  ) {
    final advisor = BidAdvisor(
      economics: economics,
      minorUnitDigits: tariff.minorUnitDigits,
      currency: tariff.currency,
    );
    final meters = _metersOf(candidate);
    final arrival = _durationOf(candidate);
    return advisor.breakEvenFare(
      deadheadMeters: meters,
      // This is where the aversion to deadhead time comes in: a minute spent
      // getting to the pickup is valued as more than a minute, which is what
      // the ride acceptance studies say.
      deadheadDuration: Duration(
        microseconds: (arrival.inMicroseconds * pickupAversion).round(),
      ),
      tripMeters: distanceMeters,
      tripDuration: duration,
    );
  }

  List<int> _reservationPrices(
    List<DriverCandidate> candidates,
    double distanceMeters,
    Duration duration,
  ) => <int>[
    for (final c in candidates) _reservationPrice(c, distanceMeters, duration),
  ];

  double _metersOf(DriverCandidate c) =>
      c.drivingMeters ?? c.straightLineMeters * detourFactor;

  Duration _durationOf(DriverCandidate c) {
    final actual = c.drivingDuration;
    if (actual != null) return actual;
    final meters = _metersOf(c);
    final seconds = meters / (urbanSpeedKmh / 3.6);
    return Duration(milliseconds: (seconds * 1000).round());
  }

  DriverCandidate _soonestToArrive(List<DriverCandidate> candidates) {
    var best = candidates.first;
    var bestTime = _durationOf(best);
    for (final c in candidates.skip(1)) {
      final t = _durationOf(c);
      if (t < bestTime) {
        best = c;
        bestTime = t;
      }
    }
    return best;
  }

  /// The price at which the fraction [fraction] of a sorted list accepts.
  static int _quantile(List<int> sorted, double fraction) {
    if (sorted.isEmpty) return 0;
    final target = (fraction.clamp(0.0, 1.0) * sorted.length).ceil();
    final index = (target - 1).clamp(0, sorted.length - 1);
    return sorted[index];
  }
}
