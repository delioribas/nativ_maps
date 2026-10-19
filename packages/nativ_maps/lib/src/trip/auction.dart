// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/lat_lng.dart';

/// A passenger's request, with the price they propose.
///
/// It is the model of bidding apps —inDrive and the ones that copy it—, where
/// the passenger names a price and drivers accept it or counter-offer, instead
/// of the platform imposing the fare.
@immutable
@experimental
class RideRequest {
  /// Creates a request.
  const RideRequest({
    required this.id,
    required this.pickup,
    required this.dropoff,
    required this.proposedFare,
    required this.currency,
    required this.createdAt,
    this.estimatedDistanceMeters,
    this.estimatedDuration,
    this.passengerCount = 1,
    this.note = '',
    this.tags = const <String>{},
  });

  /// The request identifier.
  final String id;

  /// Where the pickup is.
  final LatLng pickup;

  /// Where the drop-off is.
  final LatLng dropoff;

  /// What the passenger offers, in minor units.
  final int proposedFare;

  /// The ISO 4217 currency code.
  final String currency;

  /// When it was created.
  final DateTime createdAt;

  /// The estimated trip distance, if the route has already been calculated.
  final double? estimatedDistanceMeters;

  /// The estimated trip duration.
  final Duration? estimatedDuration;

  /// How many people are traveling.
  final int passengerCount;

  /// A free-form note from the passenger.
  final String note;

  /// Requirement tags: luggage, pet, child seat.
  final Set<String> tags;

  @override
  String toString() => 'RideRequest($id, $proposedFare $currency)';
}

/// A driver's bid on a request.
@immutable
@experimental
class DriverBid {
  /// Creates a bid.
  const DriverBid({
    required this.driverId,
    required this.requestId,
    required this.amount,
    required this.etaToPickup,
    required this.createdAt,
    this.validFor = const Duration(minutes: 2),
    this.driverRating,
    this.completedTrips,
    this.vehicleLabel = '',
  });

  /// Who is bidding.
  final String driverId;

  /// On which request.
  final String requestId;

  /// How much they ask for, in minor units.
  ///
  /// It can be equal to what the passenger offered —a straight acceptance— or
  /// different, which is the counter-offer.
  final int amount;

  /// How long it would take to get to the pickup.
  final Duration etaToPickup;

  /// When it was issued.
  final DateTime createdAt;

  /// How long it stands.
  ///
  /// A bid with no expiry is a trap: the driver keeps driving, and two minutes
  /// later their arrival time is no longer the one they offered.
  final Duration validFor;

  /// The driver's rating, usually from 0 to 5.
  final double? driverRating;

  /// How many trips they have completed.
  final int? completedTrips;

  /// A short description of the vehicle.
  final String vehicleLabel;

  /// When it expires.
  DateTime get expiresAt => createdAt.add(validFor);

  /// Has it expired already?
  bool isExpired(DateTime now) => !now.isBefore(expiresAt);

  @override
  String toString() =>
      'DriverBid($driverId, $amount, arrives in ${etaToPickup.inMinutes} min)';
}

/// The real costs of driving, to decide whether a ride is worth it.
///
/// All amounts are in minor units of the tariff's currency.
@immutable
@experimental
class DriverEconomics {
  /// Creates a cost model.
  const DriverEconomics({
    required this.costPerKilometer,
    this.commissionRate = 0,
    this.minimumNetPerHour = 0,
    this.returnFactor = 0.0,
  });

  /// What each kilometer costs: fuel, tires, maintenance.
  ///
  /// **It isn't just the gas.** A gasoline car in 2026 burns about 8 cents of
  /// fuel per kilometer, but the real wear and tear is around 15–20. A driver
  /// who only counts fuel thinks they earn a third more than they do.
  final int costPerKilometer;

  /// The platform's commission, between 0 and 1.
  final double commissionRate;

  /// The minimum the driver wants to earn per hour, already net.
  final int minimumNetPerHour;

  /// What fraction of the deadhead is repeated on the way back.
  ///
  /// A ride that ends in the outskirts often forces the driver to come back
  /// empty. With `0.5` half of that return counts as a cost. With `0` it is
  /// assumed that there will always be another ride waiting wherever this one
  /// drops you off.
  final double returnFactor;

  @override
  String toString() =>
      'DriverEconomics($costPerKilometer/km, commission $commissionRate)';
}

/// The analysis of whether a ride is good for the driver.
@immutable
@experimental
class BidEvaluation {
  /// Creates an evaluation.
  const BidEvaluation({
    required this.currency,
    required this.minorUnitDigits,
    required this.gross,
    required this.commission,
    required this.drivingCost,
    required this.net,
    required this.engagedDuration,
    required this.netPerHour,
    required this.worthIt,
    required this.deadheadMeters,
    required this.tripMeters,
  });

  /// The ISO 4217 currency code.
  final String currency;

  /// How many decimal places the currency has.
  final int minorUnitDigits;

  /// What the passenger pays.
  final int gross;

  /// What the platform takes.
  final int commission;

  /// What it costs to drive all those kilometers.
  final int drivingCost;

  /// What is really left.
  final int net;

  /// How long the driver stays busy: getting to the pickup, plus the trip.
  final Duration engagedDuration;

  /// The net converted to euros per hour.
  ///
  /// **It is the only number that lets you compare two rides.** Eight euros
  /// twelve minutes away are worse than five two minutes away, and the amount
  /// on its own doesn't tell you that.
  final int netPerHour;

  /// Does it reach the minimum per hour the driver asks for?
  final bool worthIt;

  /// The meters to the pickup point, which nobody pays for.
  final double deadheadMeters;

  /// The meters of the trip with the passenger.
  final double tripMeters;

  /// What share of the total distance is driven without a passenger, between
  /// 0 and 1.
  ///
  /// Above 0.4 the ride is almost never worth it.
  double get deadheadShare {
    final total = deadheadMeters + tripMeters;
    return total <= 0 ? 0 : deadheadMeters / total;
  }

  @override
  String toString() =>
      'BidEvaluation(neto $net, $netPerHour/h, '
      '${worthIt ? 'compensa' : 'NO compensa'})';
}

/// Decides whether a bid is good for the driver.
///
/// ## The mistake that ruins drivers
///
/// An €8 ride looks better than a €5 one. But if the first is 12 minutes away
/// and the second 2, and both take 10 minutes of trip:
///
/// | | Ride A | Ride B |
/// |---|---|---|
/// | Amount | €8.00 | €5.00 |
/// | Getting to the pickup | 5.0 km · 12 min | 0.8 km · 2 min |
/// | Trip | 6.0 km · 10 min | 4.2 km · 10 min |
/// | Total kilometers | 11.0 | 5.0 |
/// | Cost at €0.20/km | €2.20 | €1.00 |
/// | Net | €5.80 | €4.00 |
/// | Time busy | 22 min | 12 min |
/// | **Net per hour** | **€15.82/h** | **€20.00/h** |
///
/// The ride that pays less leaves 26 % more per hour. This class does that
/// math, and those numbers are exactly the ones the test suite checks.
@immutable
@experimental
class BidAdvisor {
  /// Creates an advisor for the driver.
  const BidAdvisor({
    required this.economics,
    required this.minorUnitDigits,
    required this.currency,
  });

  /// The driver's cost model.
  final DriverEconomics economics;

  /// How many decimal places the currency has.
  final int minorUnitDigits;

  /// The ISO 4217 currency code.
  final String currency;

  /// Evaluates a specific ride.
  ///
  /// [deadheadMeters] and [deadheadDuration] are the leg **to the pickup**,
  /// which nobody pays for. They come from a call to the route matrix or,
  /// failing that, from the straight-line distance with a correction factor.
  BidEvaluation evaluate({
    required int fare,
    required double deadheadMeters,
    required Duration deadheadDuration,
    required double tripMeters,
    required Duration tripDuration,
  }) {
    final returnLeg = deadheadMeters * economics.returnFactor;
    final kilometers = (deadheadMeters + tripMeters + returnLeg) / 1000;
    final cost = (kilometers * economics.costPerKilometer).round();
    final commissionAmount = (fare * economics.commissionRate).round();
    final net = fare - commissionAmount - cost;

    final engaged = deadheadDuration + tripDuration;
    final hours = engaged.inMicroseconds / 3.6e9;
    final perHour = hours <= 0 ? 0 : (net / hours).round();

    return BidEvaluation(
      currency: currency,
      minorUnitDigits: minorUnitDigits,
      gross: fare,
      commission: commissionAmount,
      drivingCost: cost,
      net: net,
      engagedDuration: engaged,
      netPerHour: perHour,
      worthIt: perHour >= economics.minimumNetPerHour,
      deadheadMeters: deadheadMeters,
      tripMeters: tripMeters,
    );
  }

  /// The minimum amount at which this ride reaches the hourly target.
  ///
  /// It is what to counter-offer. It returns the gross amount, already
  /// accounting for the commission taking its share.
  int breakEvenFare({
    required double deadheadMeters,
    required Duration deadheadDuration,
    required double tripMeters,
    required Duration tripDuration,
  }) {
    final returnLeg = deadheadMeters * economics.returnFactor;
    final kilometers = (deadheadMeters + tripMeters + returnLeg) / 1000;
    final cost = kilometers * economics.costPerKilometer;
    final hours = (deadheadDuration + tripDuration).inMicroseconds / 3.6e9;
    final target = economics.minimumNetPerHour * hours;
    final gross = (target + cost) / (1 - economics.commissionRate);
    // Round up, but without punishing floating-point noise:
    // `1200 × 0.28 + 140` gives 476.00000000000006, and a bare `ceil()` would
    // return 477. One cent ruins nobody, but it makes the same ride give two
    // different numbers depending on how the duration is written.
    const epsilon = 1e-6;
    return (gross - epsilon).ceil();
  }
}

/// How the bids the passenger sees are sorted.
///
/// The weights can add up to anything; they normalize themselves. Setting
/// `priceWeight: 1, etaWeight: 0` sorts by price only.
@immutable
@experimental
class BidRanking {
  /// Creates a sorting criterion.
  const BidRanking({
    this.priceWeight = 1.0,
    this.etaWeight = 1.0,
    this.ratingWeight = 0.5,
  });

  /// How much being cheap weighs.
  final double priceWeight;

  /// How much arriving soon weighs.
  final double etaWeight;

  /// How much the driver's rating weighs.
  final double ratingWeight;

  /// Sorts the bids from best to worst.
  ///
  /// Each dimension is normalized to the observed range before weighting it:
  /// otherwise, a two-euro difference and a two-minute difference wouldn't be
  /// comparable. Expired bids are removed.
  List<DriverBid> sort(List<DriverBid> bids, {DateTime? now}) {
    final moment = now ?? DateTime.now();
    final live = <DriverBid>[
      for (final offer in bids)
        if (!offer.isExpired(moment)) offer,
    ];
    if (live.length < 2) return live;

    final prices = <int>[for (final o in live) o.amount];
    final waits = <int>[for (final o in live) o.etaToPickup.inSeconds];
    final ratings = <double>[for (final o in live) o.driverRating ?? 0];

    final scored = <(double, DriverBid)>[
      for (final offer in live)
        (
          // Price and waiting are "less is better", so they are inverted.
          priceWeight * (1 - _normalise(offer.amount.toDouble(), prices)) +
              etaWeight *
                  (1 -
                      _normalise(
                        offer.etaToPickup.inSeconds.toDouble(),
                        waits,
                      )) +
              ratingWeight * _normalise(offer.driverRating ?? 0, ratings),
          offer,
        ),
    ]..sort((a, b) => b.$1.compareTo(a.$1));

    return <DriverBid>[for (final (_, offer) in scored) offer];
  }

  static double _normalise(double value, List<num> all) {
    var floorPrice = double.infinity;
    var highest = double.negativeInfinity;
    for (final v in all) {
      final d = v.toDouble();
      if (d < floorPrice) floorPrice = d;
      if (d > highest) highest = d;
    }
    if (highest - floorPrice == 0) return 0.5;
    return (value - floorPrice) / (highest - floorPrice);
  }
}

/// What state an auction is in.
@experimental
enum AuctionState {
  /// Accepting bids.
  open,

  /// The passenger has already chosen.
  accepted,

  /// Time ran out with nobody bidding or no choice made.
  expired,

  /// The passenger withdrew it.
  cancelled,
}

/// The auction for a ride: collects bids and lets one be chosen.
///
/// It is an in-memory state machine, with no network and no persistence: it
/// works the same on the client as on a Dart server, and it gets stored
/// wherever needed.
@experimental
class RideAuction {
  /// Opens an auction.
  RideAuction({
    required this.request,
    this.duration = const Duration(minutes: 5),
  });

  /// The request being auctioned.
  final RideRequest request;

  /// How long it accepts bids.
  final Duration duration;

  final Map<String, DriverBid> _bids = <String, DriverBid>{};
  AuctionState _state = AuctionState.open;
  DriverBid? _winner;

  /// When it closes.
  DateTime get closesAt => request.createdAt.add(duration);

  /// The current state, already taking expiry into account.
  AuctionState stateAt(DateTime now) {
    if (_state != AuctionState.open) return _state;
    return now.isBefore(closesAt) ? AuctionState.open : AuctionState.expired;
  }

  /// The winning bid, if one has already been chosen.
  DriverBid? get winner => _winner;

  /// The bids that are live at that instant.
  List<DriverBid> liveBids(DateTime now) => <DriverBid>[
    for (final offer in _bids.values)
      if (!offer.isExpired(now)) offer,
  ];

  /// Records a bid.
  ///
  /// A driver only has one live bid: bidding again **replaces** the previous
  /// one, which is what is needed to be able to lower the price.
  ///
  /// Throws [StateError] if the auction no longer accepts bids, and
  /// [ArgumentError] if the bid belongs to another request.
  void bid(DriverBid offer, {DateTime? now}) {
    final moment = now ?? DateTime.now();
    if (stateAt(moment) != AuctionState.open) {
      throw StateError(
        'Auction ${request.id} is no longer taking offers '
        '(${stateAt(moment).name})',
      );
    }
    if (offer.requestId != request.id) {
      throw ArgumentError.value(
        offer.requestId,
        'offer.requestId',
        'The offer belongs to another request; expected ${request.id}',
      );
    }
    _bids[offer.driverId] = offer;
  }

  /// Withdraws a driver's bid.
  ///
  /// Returns `true` if there was one to withdraw.
  bool withdraw(String driverId) => _bids.remove(driverId) != null;

  /// Accepts a driver's bid and closes the auction.
  ///
  /// Throws [StateError] if the auction is already closed or if that bid has
  /// expired —accepting an expired bid is promising the passenger an arrival
  /// time the driver can no longer meet.
  DriverBid accept(String driverId, {DateTime? now}) {
    final moment = now ?? DateTime.now();
    if (stateAt(moment) != AuctionState.open) {
      throw StateError('Auction ${request.id} is already closed');
    }
    final offer = _bids[driverId];
    if (offer == null) {
      throw StateError('$driverId has no offer on ${request.id}');
    }
    if (offer.isExpired(moment)) {
      throw StateError("$driverId's offer expired at ${offer.expiresAt}");
    }
    _winner = offer;
    _state = AuctionState.accepted;
    return offer;
  }

  /// Cancels the auction.
  void cancel() {
    if (_state == AuctionState.open) _state = AuctionState.cancelled;
  }
}
