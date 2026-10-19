// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/trip/fare.dart';

/// A price observed on the street, to fit the tariff against.
///
/// You collect them by opening the app you want to compete with, asking for
/// the price of a specific trip and writing down the three numbers.
@immutable
@experimental
class FareSample {
  /// Creates a sample.
  const FareSample({
    required this.distanceMeters,
    required this.duration,
    required this.observedFare,
    this.label = '',
  });

  /// The trip distance, in meters.
  ///
  /// **It has to come from `calculateRoutes`, not from the other app.** If
  /// you mix distances from two routing engines, the fit absorbs that
  /// difference and the resulting tariff ends up biased.
  final double distanceMeters;

  /// The estimated trip duration.
  final Duration duration;

  /// The price the app showed, in minor units.
  ///
  /// **Without tolls or airport fees.** Those go separately and are not part
  /// of the tariff; including them poisons the fit.
  final int observedFare;

  /// A label to recognize the sample: "Downtown → airport".
  final String label;

  /// The distance in kilometers.
  double get kilometers => distanceMeters / 1000;

  /// The duration in minutes.
  double get minutes => duration.inMicroseconds / 6e7;

  @override
  String toString() =>
      'FareSample(${kilometers.toStringAsFixed(1)} km, '
      '${minutes.toStringAsFixed(0)} min → $observedFare)';
}

/// The result of fitting a tariff to observed prices.
///
/// **Always read [rSquared] and [distanceTimeCorrelation] before using the
/// coefficients.** A fit can reproduce the prices very well and still have
/// a completely made-up split between kilometer and minute.
@immutable
@experimental
class TariffFit {
  /// Creates a fit.
  const TariffFit({
    required this.baseFare,
    required this.perKilometer,
    required this.perMinute,
    required this.rSquared,
    required this.meanAbsoluteError,
    required this.maxAbsoluteError,
    required this.sampleCount,
    required this.distanceTimeCorrelation,
  });

  /// The fitted flagfall, in minor units.
  final int baseFare;

  /// The fitted price per kilometer.
  final int perKilometer;

  /// The fitted price per minute.
  final int perMinute;

  /// How much of the variation in prices the model explains, from 0 to 1.
  ///
  /// | Value | What it means |
  /// |---|---|
  /// | > 0.95 | the model reproduces the prices; use it |
  /// | 0.85 – 0.95 | reasonable; check [maxAbsoluteError] first |
  /// | < 0.85 | a factor is missing: zones, time bands or demand |
  final double rSquared;

  /// Mean error in minor units.
  final double meanAbsoluteError;

  /// The worst error across all samples, in minor units.
  ///
  /// More informative than the mean: a large maximum error with a small mean
  /// usually points to a sample taken at rush hour, with demand inside the
  /// price.
  final double maxAbsoluteError;

  /// How many samples the fit was based on.
  final int sampleCount;

  /// How closely distance and duration track each other, from −1 to 1.
  ///
  /// **It's the number most people ignore and the one that ruins most
  /// fits.** On urban trips, kilometers and minutes rise together: if the
  /// correlation goes above 0.95, there is mathematically **no way** to tell
  /// which part of the price comes from the kilometer and which from the
  /// minute. The model predicts the total well and the split between the two
  /// is arbitrary.
  ///
  /// The fix is to add samples that break the relationship: a short trip in
  /// a traffic jam and a long one on the highway at six in the morning.
  final double distanceTimeCorrelation;

  /// Can the split between kilometer and minute be trusted?
  bool get splitIsReliable => distanceTimeCorrelation.abs() < 0.95;

  /// Does the fit reproduce the observed prices?
  bool get isUsable => rSquared >= 0.85 && sampleCount >= 8;

  /// Builds the fitted tariff.
  Tariff toTariff({
    required String currency,
    int minorUnitDigits = 2,
    int minimumFare = 0,
    int waitingPerMinute = 0,
    Duration waitingGrace = Duration.zero,
    FareRounding rounding = FareRounding.none,
    List<TariffBand> bands = const <TariffBand>[],
    List<Surcharge> surcharges = const <Surcharge>[],
  }) => Tariff(
    currency: currency,
    minorUnitDigits: minorUnitDigits,
    baseFare: baseFare,
    perKilometer: perKilometer,
    perMinute: perMinute,
    minimumFare: minimumFare,
    waitingPerMinute: waitingPerMinute,
    waitingGrace: waitingGrace,
    rounding: rounding,
    bands: bands,
    surcharges: surcharges,
  );

  /// What the model predicts for a trip, in minor units.
  int predict({required double distanceMeters, required Duration duration}) =>
      (baseFare +
              distanceMeters / 1000 * perKilometer +
              duration.inMicroseconds / 6e7 * perMinute)
          .round();

  /// A report with one line per sample, to see where it fails.
  String report(List<FareSample> samples) {
    final buffer = StringBuffer()
      ..writeln('Fit over $sampleCount samples')
      ..writeln('  flagfall     $baseFare')
      ..writeln('  per km       $perKilometer')
      ..writeln('  per minute   $perMinute')
      ..writeln('  R²           ${rSquared.toStringAsFixed(4)}')
      ..writeln('  mean error   ${meanAbsoluteError.toStringAsFixed(1)}')
      ..writeln('  max error    ${maxAbsoluteError.toStringAsFixed(1)}')
      ..writeln(
        '  correlation  ${distanceTimeCorrelation.toStringAsFixed(3)}'
        '${splitIsReliable ? '' : '  ← km/min split NOT reliable'}',
      )
      ..writeln('');
    for (final sample in samples) {
      final predicted = predict(
        distanceMeters: sample.distanceMeters,
        duration: sample.duration,
      );
      final error = predicted - sample.observedFare;
      buffer.writeln(
        '  ${sample.kilometers.toStringAsFixed(1).padLeft(5)} km  '
        '${sample.minutes.toStringAsFixed(0).padLeft(3)} min  '
        'observed ${sample.observedFare.toString().padLeft(6)}  '
        'model ${predicted.toString().padLeft(6)}  '
        '${error >= 0 ? '+' : ''}$error'
        '${sample.label.isEmpty ? '' : '   ${sample.label}'}',
      );
    }
    return buffer.toString();
  }

  @override
  String toString() =>
      'TariffFit(bandera $baseFare, km $perKilometer, min $perMinute, '
      'R² ${rSquared.toStringAsFixed(3)})';
}

/// Fits a tariff to the prices you already see on the street.
///
/// ## What it's for
///
/// The tariffs of the apps already operating in your city **are not
/// public**, they change from city to city and they change over time. They
/// can't be hard-coded in a package.
///
/// What you can do is **measure them**: you ask for twenty prices in the app
/// you compete with, write down distance, duration and price, and this
/// returns the flagfall, the price per kilometer and the price per minute
/// that reproduce those numbers.
///
/// ```dart
/// final fit = TariffCalibration.fit(<FareSample>[
///   FareSample(distanceMeters: 3200, duration: Duration(minutes: 11),
///       observedFare: 320, label: 'Centro → Mariscal'),
///   FareSample(distanceMeters: 12800, duration: Duration(minutes: 26),
///       observedFare: 780, label: 'Centro → aeropuerto'),
///   // …eighteen more
/// ]);
///
/// print(fit.report(samples));
/// if (fit.isUsable) {
///   final tariff = fit.toTariff(currency: 'USD', minimumFare: 150);
/// }
/// ```
///
/// ## How to take the samples
///
/// | Rule | Why |
/// |---|---|
/// | At least **fifteen**, ideally thirty | three unknowns need some margin |
/// | **Very** different distances | 2 km and 25 km, not all between 5 and 8 |
/// | At **quiet** hours | demand is not part of the tariff |
/// | Distance, duration from `calculateRoutes` | mixing engines biases it all |
/// | **Without** tolls or airport fees | they go separately |
/// | Some that break the km↔min link | short in a jam, long on an open road |
///
/// The last one is the one almost nobody does, and the one that decides
/// whether the split between kilometer and minute means anything. See
/// [TariffFit.distanceTimeCorrelation].
///
/// ## What this fit doesn't capture
///
/// Demand, time bands and zone surcharges. They are **separate layers**
/// configured on top of the fitted tariff: `TariffBand` for the bands,
/// `Surcharge` for the zones and `MarketConditions` for demand. If you take
/// the samples at rush hour, demand leaks into the coefficients and then
/// gets charged twice.
@experimental
abstract final class TariffCalibration {
  /// Fits by least squares.
  ///
  /// With [includeTimeComponent] set to `false` it fits only flagfall and
  /// kilometer, which is right in markets where the tariff doesn't charge
  /// for time.
  ///
  /// Negative coefficients are clipped to zero and the fit is repeated
  /// without them: a negative price per kilometer means nothing, and it
  /// shows up when there are few samples or they are highly correlated.
  ///
  /// Throws [ArgumentError] with fewer than three samples, or if they all
  /// have the same distance and duration —there is nothing to fit—.
  static TariffFit fit(
    List<FareSample> samples, {
    bool includeTimeComponent = true,
  }) {
    if (samples.length < 3) {
      throw ArgumentError.value(
        samples.length,
        'samples',
        'At least 3 samples are needed to fit 3 coefficients; '
            'for the result to be usable, at least 15',
      );
    }

    final km = <double>[for (final m in samples) m.kilometers];
    final min = <double>[for (final m in samples) m.minutes];
    final y = <double>[for (final m in samples) m.observedFare.toDouble()];

    if (_variance(km) == 0 && _variance(min) == 0) {
      throw ArgumentError.value(
        samples,
        'samples',
        'Every sample has the same distance and duration: there is no '
            'variation to learn from',
      );
    }

    final correlation = _correlation(km, min);

    var coefficients = includeTimeComponent
        ? _leastSquares(<List<double>>[km, min], y)
        : _leastSquares(<List<double>>[km], y);

    // A negative coefficient makes no physical sense. It is pinned to zero
    // and the fit is run again with the rest.
    if (includeTimeComponent && coefficients.length == 3) {
      if (coefficients[2] < 0) {
        coefficients = <double>[
          ..._leastSquares(<List<double>>[km], y),
          0,
        ];
      } else if (coefficients[1] < 0) {
        coefficients = <double>[
          _leastSquares(<List<double>>[min], y)[0],
          0,
          _leastSquares(<List<double>>[min], y)[1],
        ];
      }
    }

    final flagfall = math.max(0.0, coefficients[0]).round();
    final perKm = math.max(0.0, coefficients[1]).round();
    final perMin = coefficients.length > 2
        ? math.max(0.0, coefficients[2]).round()
        : 0;

    // Goodness of fit, measured with the coefficients already rounded to
    // integers: that's what will actually be used, not the intermediate
    // floats.
    var sumErrors = 0.0;
    var worstError = 0.0;
    var sumSquares = 0.0;
    final mean = y.reduce((a, b) => a + b) / y.length;
    var totalSquares = 0.0;

    for (var i = 0; i < samples.length; i++) {
      final predicted = flagfall + km[i] * perKm + min[i] * perMin;
      final error = (predicted - y[i]).abs();
      sumErrors += error;
      if (error > worstError) worstError = error;
      sumSquares += (predicted - y[i]) * (predicted - y[i]);
      totalSquares += (y[i] - mean) * (y[i] - mean);
    }

    return TariffFit(
      baseFare: flagfall,
      perKilometer: perKm,
      perMinute: perMin,
      rSquared: totalSquares == 0 ? 1 : 1 - sumSquares / totalSquares,
      meanAbsoluteError: sumErrors / samples.length,
      maxAbsoluteError: worstError,
      sampleCount: samples.length,
      distanceTimeCorrelation: correlation,
    );
  }

  /// Least squares with an intercept.
  ///
  /// Solves the normal equations `(XᵀX)·b = Xᵀy` by Gaussian elimination
  /// with partial pivoting. With two or three unknowns nothing more
  /// elaborate pays off, and pivoting avoids the only ugly case: a constant
  /// column that leaves a zero on the diagonal.
  static List<double> _leastSquares(
    List<List<double>> columns,
    List<double> y,
  ) {
    final n = y.length;
    final k = columns.length + 1; // +1 for the intercept

    // X with a first column of ones.
    List<double> row(int i) => <double>[
      1,
      for (final column in columns) column[i],
    ];

    final a = <List<double>>[
      for (var r = 0; r < k; r++) List<double>.filled(k + 1, 0),
    ];

    for (var i = 0; i < n; i++) {
      final x = row(i);
      for (var r = 0; r < k; r++) {
        for (var c = 0; c < k; c++) {
          a[r][c] += x[r] * x[c];
        }
        a[r][k] += x[r] * y[i];
      }
    }

    // Gaussian elimination with partial pivoting.
    for (var col = 0; col < k; col++) {
      var pivot = col;
      for (var r = col + 1; r < k; r++) {
        if (a[r][col].abs() > a[pivot][col].abs()) pivot = r;
      }
      if (a[pivot][col].abs() < 1e-12) continue;
      if (pivot != col) {
        final tmp = a[col];
        a[col] = a[pivot];
        a[pivot] = tmp;
      }
      for (var r = 0; r < k; r++) {
        if (r == col) continue;
        final factor = a[r][col] / a[col][col];
        for (var c = col; c <= k; c++) {
          a[r][c] -= factor * a[col][c];
        }
      }
    }

    final solution = List<double>.filled(k, 0);
    for (var r = 0; r < k; r++) {
      // A zero diagonal means a column that carries no information —for
      // example, every sample with the same duration—. Its coefficient is
      // left at zero instead of dividing by almost nothing and getting a
      // huge, meaningless number.
      if (a[r][r].abs() >= 1e-12) solution[r] = a[r][k] / a[r][r];
    }
    return solution;
  }

  static double _variance(List<double> v) {
    if (v.isEmpty) return 0;
    final mean = v.reduce((a, b) => a + b) / v.length;
    var sum = 0.0;
    for (final x in v) {
      sum += (x - mean) * (x - mean);
    }
    return sum / v.length;
  }

  static double _correlation(List<double> a, List<double> b) {
    final meanA = a.reduce((x, y) => x + y) / a.length;
    final meanB = b.reduce((x, y) => x + y) / b.length;
    var cov = 0.0;
    var varA = 0.0;
    var varB = 0.0;
    for (var i = 0; i < a.length; i++) {
      final da = a[i] - meanA;
      final db = b[i] - meanB;
      cov += da * db;
      varA += da * da;
      varB += db * db;
    }
    if (varA == 0 || varB == 0) return 0;
    return cov / math.sqrt(varA * varB);
  }
}
