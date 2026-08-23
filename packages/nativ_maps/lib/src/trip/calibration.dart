// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/trip/fare.dart';

/// Un precio observado en la calle, para ajustar la tarifa contra él.
///
/// Se recogen abriendo la aplicación con la que quieres competir, pidiendo el
/// precio de un trayecto concreto y anotando los tres números.
@immutable
class FareSample {
  /// Crea una muestra.
  const FareSample({
    required this.distanceMeters,
    required this.duration,
    required this.observedFare,
    this.label = '',
  });

  /// La distancia del trayecto, en metros.
  ///
  /// **Tiene que salir de `calculateRoutes`, no de la otra aplicación.** Si se
  /// mezclan las distancias de dos motores de rutas, el ajuste absorbe esa
  /// diferencia y la tarifa resultante queda sesgada.
  final double distanceMeters;

  /// La duración estimada del trayecto.
  final Duration duration;

  /// El precio que enseñó la aplicación, en unidades menores.
  ///
  /// **Sin peajes ni tasas de aeropuerto.** Esas van aparte y no forman parte
  /// de la tarifa; incluirlas envenena el ajuste.
  final int observedFare;

  /// Una etiqueta para reconocer la muestra: «Centro → aeropuerto».
  final String label;

  /// La distancia en kilómetros.
  double get kilometers => distanceMeters / 1000;

  /// La duración en minutos.
  double get minutes => duration.inMicroseconds / 6e7;

  @override
  String toString() =>
      'FareSample(${kilometers.toStringAsFixed(1)} km, '
      '${minutes.toStringAsFixed(0)} min → $observedFare)';
}

/// El resultado de ajustar una tarifa a precios observados.
///
/// **Lee siempre [rSquared] y [distanceTimeCorrelation] antes de usar los
/// coeficientes.** Un ajuste puede reproducir los precios muy bien y aun así
/// tener el reparto entre kilómetro y minuto completamente inventado.
@immutable
class TariffFit {
  /// Crea un ajuste.
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

  /// La bajada de bandera ajustada, en unidades menores.
  final int baseFare;

  /// El precio por kilómetro ajustado.
  final int perKilometer;

  /// El precio por minuto ajustado.
  final int perMinute;

  /// Qué parte de la variación de los precios explica el modelo, de 0 a 1.
  ///
  /// | Valor | Qué significa |
  /// |---|---|
  /// | > 0,95 | el modelo reproduce los precios; úsalo |
  /// | 0,85 – 0,95 | razonable; mira [maxAbsoluteError] antes |
  /// | < 0,85 | falta un factor: zonas, franjas horarias o demanda |
  final double rSquared;

  /// Error medio en unidades menores.
  final double meanAbsoluteError;

  /// El peor error de todas las muestras, en unidades menores.
  ///
  /// Más informativo que la media: un error máximo grande con media pequeña
  /// suele señalar una muestra tomada en hora punta, con la demanda dentro
  /// del precio.
  final double maxAbsoluteError;

  /// Sobre cuántas muestras se ajustó.
  final int sampleCount;

  /// Cuánto se parecen entre sí distancia y duración, de −1 a 1.
  ///
  /// **Es el número que más gente ignora y más ajustes arruina.** En trayectos
  /// urbanos, kilómetros y minutos suben juntos: si la correlación pasa de
  /// 0,95, matemáticamente **no hay forma** de saber qué parte del precio la
  /// pone el kilómetro y qué parte el minuto. El modelo predice bien el total
  /// y el reparto entre los dos es arbitrario.
  ///
  /// Se arregla metiendo muestras que rompan la relación: un trayecto corto en
  /// atasco y uno largo por autopista a las seis de la mañana.
  final double distanceTimeCorrelation;

  /// ¿Se puede confiar en el reparto entre kilómetro y minuto?
  bool get splitIsReliable => distanceTimeCorrelation.abs() < 0.95;

  /// ¿El ajuste reproduce los precios observados?
  bool get isUsable => rSquared >= 0.85 && sampleCount >= 8;

  /// Construye la tarifa ajustada.
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

  /// Lo que predice el modelo para un trayecto, en unidades menores.
  int predict({required double distanceMeters, required Duration duration}) =>
      (baseFare +
              distanceMeters / 1000 * perKilometer +
              duration.inMicroseconds / 6e7 * perMinute)
          .round();

  /// Un informe de una línea por muestra, para ver dónde falla.
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

/// Ajusta una tarifa a los precios que ya se ven en la calle.
///
/// ## Para qué sirve
///
/// Las tarifas de las aplicaciones que ya operan en tu ciudad **no son
/// públicas**, cambian entre ciudades y cambian con el tiempo. No se pueden
/// codificar en un paquete.
///
/// Lo que sí se puede es **medirlas**: pides veinte precios en la aplicación
/// con la que compites, anotas distancia, duración y precio, y esto devuelve
/// la bajada de bandera, el precio por kilómetro y el precio por minuto que
/// reproducen esos números.
///
/// ```dart
/// final ajuste = TariffCalibration.fit(<FareSample>[
///   FareSample(distanceMeters: 3200, duration: Duration(minutes: 11),
///       observedFare: 320, label: 'Centro → Mariscal'),
///   FareSample(distanceMeters: 12800, duration: Duration(minutes: 26),
///       observedFare: 780, label: 'Centro → aeropuerto'),
///   // …dieciocho más
/// ]);
///
/// print(ajuste.report(muestras));
/// if (ajuste.isUsable) {
///   final tarifa = ajuste.toTariff(currency: 'USD', minimumFare: 150);
/// }
/// ```
///
/// ## Cómo tomar las muestras
///
/// | Regla | Por qué |
/// |---|---|
/// | Al menos **quince**, mejor treinta | tres incógnitas necesitan margen |
/// | Distancias **muy** distintas | 2 km y 25 km, no todo entre 5 y 8 |
/// | En horas **tranquilas** | la demanda no es parte de la tarifa |
/// | Distancia y duración de `calculateRoutes` | mezclar motores sesga todo |
/// | **Sin** peajes ni tasas de aeropuerto | van aparte |
/// | Alguna que rompa la relación km↔min | un corto en atasco, un largo libre |
///
/// La última es la que casi nadie hace y la que decide si el reparto entre
/// kilómetro y minuto significa algo. Ver [TariffFit.distanceTimeCorrelation].
///
/// ## Lo que este ajuste no captura
///
/// La demanda, las franjas horarias y los recargos de zona. Son **capas
/// aparte** que se configuran encima de la tarifa ajustada: `TariffBand` para
/// las franjas, `Surcharge` para las zonas y `MarketConditions` para la
/// demanda. Si tomas las muestras en hora punta, la demanda se cuela dentro de
/// los coeficientes y luego se cobra dos veces.
abstract final class TariffCalibration {
  /// Ajusta por mínimos cuadrados.
  ///
  /// Con [includeTimeComponent] en `false` ajusta solo bandera y kilómetro,
  /// que es lo correcto en mercados donde la tarifa no cobra por tiempo.
  ///
  /// Los coeficientes negativos se recortan a cero y el ajuste se repite sin
  /// ellos: un precio por kilómetro negativo no significa nada, y sale cuando
  /// las muestras son pocas o están muy correlacionadas.
  ///
  /// Lanza [ArgumentError] con menos de tres muestras, o si todas tienen la
  /// misma distancia y duración —no hay nada que ajustar—.
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

    // Un coeficiente negativo no tiene sentido físico. Se fija a cero y se
    // vuelve a ajustar con el resto.
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

    // Bondad del ajuste, medida con los coeficientes ya redondeados a enteros:
    // es lo que va a usarse de verdad, no los flotantes intermedios.
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

  /// Mínimos cuadrados con término independiente.
  ///
  /// Resuelve las ecuaciones normales `(XᵀX)·b = Xᵀy` por eliminación de
  /// Gauss con pivoteo parcial. Con dos o tres incógnitas no compensa nada
  /// más elaborado, y el pivoteo evita el único caso feo: una columna
  /// constante que deja un cero en la diagonal.
  static List<double> _leastSquares(
    List<List<double>> columns,
    List<double> y,
  ) {
    final n = y.length;
    final k = columns.length + 1; // +1 por el término independiente

    // X con una primera columna de unos.
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

    // Eliminación de Gauss con pivoteo parcial.
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
      // Una diagonal nula significa una columna que no aporta información
      // —por ejemplo, todas las muestras con la misma duración—. Su
      // coeficiente se deja en cero en vez de dividir por casi nada y sacar
      // un número enorme sin sentido.
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
