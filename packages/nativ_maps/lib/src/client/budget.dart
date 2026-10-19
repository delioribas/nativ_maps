// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/exceptions.dart';

/// What to do when the budget runs out.
enum BudgetPolicy {
  /// Throw [BudgetExhaustedException] and do not send the request.
  ///
  /// It is the default, on purpose: silent mode turns a cap into a
  /// suggestion.
  throwException,

  /// Let the request through and warn via [Budget.onExceeded].
  ///
  /// For when cutting off the service is worse than the bill — tracking in
  /// progress, for example. The call does get billed.
  warn,
}

/// Spending cap per time window, checked before sending.
///
/// ## Why this lives in the client, not in the caller's discipline
///
/// Amazon Location bills **per request**, and some requests cost more than
/// one unit: isolines bill per threshold (up to five), the matrix bills **per
/// pair** —a 10×10 matrix is a hundred calculations—.
///
/// A loop over the fleet, an `initState` that requests a route on every
/// rebuild, a screen that refreshes itself: none of the three looks like a
/// bug when reading the code, and all three show up on the bill. Code review
/// does not catch them because they do not look like bugs. A cap that counts
/// real units does.
///
/// ```dart
/// final maps = NativMaps(
///   region: 'us-east-1',
///   credentials: ApiKeyCredentials(key),
///   budget: Budget(
///     maxUnits: 500,
///     window: const Duration(minutes: 1),
///     onExceeded: (e) => logger.warning('$e'),
///   ),
/// );
/// ```
///
/// The budget protects you from **your own loops**. It does not protect you
/// from a third party who extracted the key from the APK: that is what AWS
/// Budgets, in the console, is for.
class Budget {
  /// Creates a budget of [maxUnits] billing units per [window].
  Budget({
    required this.maxUnits,
    this.window = const Duration(minutes: 1),
    this.policy = BudgetPolicy.throwException,
    this.onExceeded,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    // No `assert`: Dart strips it when compiling in release, so an invalid
    // budget would warn in debug and slip through silently in production.
    // It is the same bug `LatLngBounds.fromPoints` had, and here it would
    // land right in the spending control.
    if (maxUnits <= 0) {
      throw ArgumentError.value(maxUnits, 'maxUnits', 'debe ser positivo');
    }
    if (window <= Duration.zero) {
      throw ArgumentError.value(window, 'window', 'debe ser positiva');
    }
  }

  /// A budget that limits nothing. Useful for tests and for development mode,
  /// where the cap gets in the way more than it helps.
  factory Budget.unlimited() => Budget(
    maxUnits: 1 << 30,
    window: const Duration(days: 365),
    policy: BudgetPolicy.warn,
  );

  /// Billing units allowed within one window.
  final int maxUnits;

  /// The length of the sliding window.
  final Duration window;

  /// What to do when the cap is exceeded.
  final BudgetPolicy policy;

  /// Called every time the cap is exceeded, whatever the policy.
  ///
  /// It is the place to hook up the app's logging: without it, a cap in
  /// [BudgetPolicy.warn] mode leaves no trace that it was crossed.
  final void Function(BudgetExhaustedException event)? onExceeded;

  final DateTime Function() _clock;

  /// A true sliding window: each entry is (instant, units).
  ///
  /// A queue and not a counter that resets, because the counter lets through
  /// twice the cap right at the window boundary — which is exactly when a
  /// runaway loop is at its worst.
  final Queue<(DateTime, int)> _spent = Queue<(DateTime, int)>();

  /// Units spent in the window ending now.
  int get usedUnits {
    _evictExpired();
    return _spent.fold(0, (sum, entry) => sum + entry.$2);
  }

  /// Units still available right now.
  int get remainingUnits => (maxUnits - usedUnits).clamp(0, maxUnits);

  /// When the oldest entry expires, that is, when budget becomes available
  /// again. It is [DateTime.now] if nothing has been spent.
  DateTime get resetsAt {
    _evictExpired();
    if (_spent.isEmpty) return _clock();
    return _spent.first.$1.add(window);
  }

  /// Reserves [units] for [operation].
  ///
  /// Throws [BudgetExhaustedException] if they do not fit and the policy is
  /// [BudgetPolicy.throwException]. With [BudgetPolicy.warn] it warns and
  /// lets the request through.
  ///
  /// The charge is recorded **before** sending and is not refunded if the
  /// request fails: AWS bills most service errors anyway, and a budget that
  /// recovers when something fails is exactly the one that drains when the
  /// service is having a bad day.
  void charge(String operation, int units) {
    if (units <= 0) return;
    _evictExpired();

    final used = _spent.fold(0, (int sum, entry) => sum + entry.$2);
    if (used + units > maxUnits) {
      final event = BudgetExhaustedException(
        operation: operation,
        requestedUnits: units,
        usedUnits: used,
        maxUnits: maxUnits,
        window: window,
        resetsAt: resetsAt,
      );
      onExceeded?.call(event);
      if (policy == BudgetPolicy.throwException) throw event;
    }
    _spent.add((_clock(), units));
  }

  /// Empties the history. After this the full budget is available.
  void reset() => _spent.clear();

  void _evictExpired() {
    final cutoff = _clock().subtract(window);
    while (_spent.isNotEmpty && _spent.first.$1.isBefore(cutoff)) {
      _spent.removeFirst();
    }
  }

  @override
  String toString() =>
      'Budget($usedUnits/$maxUnits por ${window.inSeconds}s, ${policy.name})';
}

/// How many billing units each operation costs.
///
/// Most cost one. The three that do not are precisely the ones that show up
/// on a surprise bill, so they are here with a name and an explanation instead
/// of hidden at the call site.
@immutable
abstract final class BillingUnits {
  /// The normal case: one request, one unit.
  static const int single = 1;

  /// An isoline bills **per threshold**, not per request.
  ///
  /// Asking for five thresholds in one call is more convenient than five
  /// calls, but it costs exactly the same.
  static int isolines(int thresholdCount) =>
      thresholdCount <= 0 ? 1 : thresholdCount;

  /// A matrix bills **per origin-destination pair**.
  ///
  /// Ten origins and ten destinations are a hundred route calculations. It is
  /// the operation with the biggest gap between what it looks like and what
  /// it costs.
  static int routeMatrix(int origins, int destinations) {
    final cells = origins * destinations;
    return cells <= 0 ? 1 : cells;
  }

  /// `SnapToRoads` bills per request sent.
  ///
  /// It matters because a long history gets chunked: 12,000 points are three
  /// requests, and therefore three units, even though the caller only wrote
  /// one line.
  static int snapToRoads(int chunkCount) => chunkCount <= 0 ? 1 : chunkCount;
}
