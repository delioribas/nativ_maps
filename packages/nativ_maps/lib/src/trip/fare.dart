// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/lat_lng.dart';
import 'package:nativ_maps/src/trip/position_filter.dart';
import 'package:nativ_maps/src/trip/trip_recorder.dart';

/// Cómo se redondea el importe final.
///
/// En muchos mercados el redondeo está regulado y no es opcional.
enum FareRounding {
  /// Se deja el importe exacto.
  none,

  /// Al múltiplo de 5 unidades menores más cercano.
  nearest5,

  /// Al múltiplo de 10 más cercano.
  nearest10,

  /// Al múltiplo de 50 más cercano.
  nearest50,

  /// A la unidad mayor más cercana: al euro, al dólar.
  nearestMajor,

  /// Siempre hacia arriba, a la unidad mayor.
  upToMajor,
}

/// Una franja horaria con su propio recargo.
///
/// Sirve para la tarifa nocturna, la de fin de semana y la de festivos, que
/// son la norma en cualquier mercado regulado.
///
/// ```dart
/// // Nocturna: de 22:00 a 06:00, todos los días, un 25 % más cara.
/// const nocturna = TariffBand(
///   name: 'Nocturna',
///   startOfDay: Duration(hours: 22),
///   endOfDay: Duration(hours: 6),
///   multiplier: 1.25,
/// );
/// ```
@immutable
class TariffBand {
  /// Crea una franja.
  const TariffBand({
    required this.name,
    required this.startOfDay,
    required this.endOfDay,
    this.multiplier = 1.0,
    this.weekdays = const <int>{1, 2, 3, 4, 5, 6, 7},
  });

  /// El nombre que sale en el desglose.
  final String name;

  /// A qué hora del día empieza, contada desde medianoche.
  final Duration startOfDay;

  /// A qué hora del día acaba.
  ///
  /// Si es **anterior** a [startOfDay], la franja cruza la medianoche. Es el
  /// caso normal de la nocturna: `22:00` a `06:00`.
  final Duration endOfDay;

  /// Por cuánto se multiplican la bajada de bandera, el kilómetro y el minuto.
  final double multiplier;

  /// Los días de la semana en los que se aplica.
  ///
  /// Se usan las constantes de `DateTime`: `DateTime.monday` es 1 y
  /// `DateTime.sunday` es 7.
  final Set<int> weekdays;

  /// ¿Está activa esta franja en ese instante?
  bool appliesAt(DateTime moment) {
    final sinceMidnight = Duration(
      hours: moment.hour,
      minutes: moment.minute,
      seconds: moment.second,
    );
    final wrapsMidnight = endOfDay <= startOfDay;

    // Cuando la franja cruza la medianoche, el tramo que cae después de las
    // 00:00 pertenece al día anterior. Una nocturna de viernes que se
    // configuró solo para viernes tiene que seguir activa a la 01:00 del
    // sábado, o el pasajero paga tarifa diurna a esa hora.
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

/// Un cargo fijo que se suma al viaje.
///
/// Aeropuerto, maletas, reserva anticipada, peaje urbano, limpieza.
@immutable
class Surcharge {
  /// Crea un cargo.
  const Surcharge({
    required this.name,
    required this.amount,
    this.surgeable = false,
  });

  /// El nombre que sale en el desglose.
  final String name;

  /// El importe, en unidades menores.
  final int amount;

  /// ¿Lo multiplica la demanda?
  ///
  /// Por defecto **no**, que es lo correcto casi siempre: un recargo de
  /// aeropuerto de tres euros no pasa a costar cinco porque llueva. Los que
  /// van a `true` se suman a la base **antes** de aplicar la demanda y antes
  /// de comprobar el mínimo.
  final bool surgeable;

  @override
  String toString() => 'Surcharge($name, $amount)';
}

/// Una línea del desglose de la tarifa.
///
/// Cada importe cobrado tiene la suya, con la cuenta que lo produjo escrita
/// en [detail]. Es lo que se enseña cuando alguien reclama.
@immutable
class FareLine {
  /// Crea una línea.
  const FareLine({required this.label, required this.amount, this.detail = ''});

  /// Qué concepto es.
  final String label;

  /// El importe, en unidades menores.
  final int amount;

  /// La cuenta que produjo el importe, por ejemplo `12,4 km × 85`.
  final String detail;

  @override
  String toString() =>
      detail.isEmpty ? '$label: $amount' : '$label: $amount  ($detail)';
}

/// El importe de un viaje, desglosado.
///
/// **Nunca se devuelve solo un total.** Un número suelto no se puede
/// justificar, no se puede auditar y no se puede reproducir seis meses
/// después cuando llega la reclamación.
@immutable
class FareBreakdown {
  /// Crea un desglose.
  const FareBreakdown({
    required this.currency,
    required this.minorUnitDigits,
    required this.lines,
    required this.total,
  });

  /// El código ISO 4217 de la moneda, por ejemplo `EUR`.
  final String currency;

  /// Cuántos decimales tiene la moneda.
  ///
  /// Dos para el euro y el dólar, cero para el peso chileno y el yen.
  final int minorUnitDigits;

  /// Todas las líneas, en el orden en que se aplicaron.
  final List<FareLine> lines;

  /// El total a cobrar, en unidades menores.
  final int total;

  /// El total como número decimal.
  ///
  /// **Solo para enseñarlo.** Nunca se hacen cuentas con este valor: la coma
  /// flotante binaria no representa exactamente los céntimos, y sumar mil
  /// carreras así produce un descuadre con la contabilidad.
  double get totalAsDecimal => total / math.pow(10, minorUnitDigits);

  /// El total formateado, por ejemplo `12,45`.
  String get formattedTotal => formatAmount(total);

  /// Da formato a un importe en unidades menores.
  String formatAmount(int minorUnits) {
    if (minorUnitDigits == 0) return '$minorUnits';
    final divisor = math.pow(10, minorUnitDigits).toInt();
    final whole = minorUnits ~/ divisor;
    final remainder = (minorUnits % divisor).abs();
    return '$whole,${remainder.toString().padLeft(minorUnitDigits, '0')}';
  }

  /// El desglose completo en texto, listo para un recibo o un registro.
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

/// La tarifa de un taxi o un VTC, y el motor que la aplica.
///
/// ```dart
/// const tarifa = Tariff(
///   currency: 'EUR',
///   baseFare: 250,        // 2,50 € de bajada de bandera
///   perKilometer: 110,    // 1,10 € el kilómetro
///   perMinute: 35,        // 0,35 € el minuto en marcha
///   waitingPerMinute: 30, // 0,30 € el minuto parado
///   minimumFare: 500,     // 5,00 € mínimo
///   rounding: FareRounding.nearest5,
/// );
///
/// final importe = tarifa.quote(viaje);
/// print(importe.toReceipt());
/// ```
///
/// ## Todo en unidades menores, y enteras
///
/// Los importes son **céntimos**, no euros, y son `int`, no `double`. Un
/// `double` no puede representar 0,10 exactamente; sumar diez carreras de
/// 1,10 € da 11,000000000000002 y la caja no cuadra a final de mes. Con
/// enteros no hay ese problema, y el redondeo ocurre **una sola vez**, al
/// final, donde la ley dice que ocurra.
@immutable
class Tariff {
  /// Crea una tarifa.
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

  /// El código ISO 4217 de la moneda.
  final String currency;

  /// Cuántos decimales tiene la moneda.
  final int minorUnitDigits;

  /// La bajada de bandera, en unidades menores.
  final int baseFare;

  /// Lo que cuesta cada kilómetro.
  final int perKilometer;

  /// Lo que cuesta cada minuto **en marcha**.
  ///
  /// Las tarifas mixtas cobran distancia y tiempo a la vez; las de solo
  /// distancia dejan esto a cero.
  final int perMinute;

  /// Lo que cuesta cada minuto **detenido**.
  final int waitingPerMinute;

  /// Cuánta espera es gratis antes de empezar a cobrarla.
  ///
  /// Se descuenta del conjunto del viaje, no de cada parada: si no, veinte
  /// semáforos de un minuto con un minuto de cortesía cada uno salen gratis.
  final Duration waitingGrace;

  /// El importe mínimo de una carrera.
  final int minimumFare;

  /// Cómo se redondea el total.
  final FareRounding rounding;

  /// Las franjas horarias, en orden de prioridad.
  ///
  /// Se aplica **la primera que coincida**, así que las más específicas van
  /// antes: la de festivos delante de la de fin de semana.
  ///
  /// > **Las horas de las franjas se leen en la misma zona que las marcas de
  /// > tiempo del viaje.** Una nocturna que empieza a las 22:00 solo empieza a
  /// > las 22:00 de la ciudad si el viaje llega con marcas locales. Si el
  /// > servidor guarda en UTC —que es lo correcto—, convierte a la zona de la
  /// > ciudad antes de tarificar, o define las franjas en UTC. Mezclar las dos
  /// > cosas desplaza la tarifa nocturna varias horas.
  final List<TariffBand> bands;

  /// Cargos fijos que se aplican siempre.
  final List<Surcharge> surcharges;

  /// Calcula el importe de un viaje.
  ///
  /// ## Cómo se reparte cuando el viaje cruza una franja
  ///
  /// Un trayecto que empieza a las 21:50 y acaba a las 22:10 tiene diez
  /// minutos de tarifa diurna y diez de nocturna. Cobrarlo entero a la tarifa
  /// de salida —lo que hace casi todo el software— es incorrecto, y en un
  /// mercado regulado es sancionable.
  ///
  /// Aquí el viaje se **parte por los límites de las franjas**:
  ///
  /// - El **tiempo** se reparte de forma exacta, porque las paradas tienen
  ///   hora de inicio y de fin.
  /// - La **distancia** se reparte en proporción al tiempo en marcha de cada
  ///   tramo. Es una aproximación: un trayecto que hace autopista antes de las
  ///   22:00 y ciudad después le asigna a la nocturna más kilómetros de los
  ///   que realmente recorrió. El error queda acotado por lo que se mueva la
  ///   velocidad media entre tramos, y en un recorrido urbano es pequeño.
  ///
  /// [surgeMultiplier] multiplica la parte variable —bandera, distancia y
  /// tiempo— pero **no** los cargos con `taxable: false` ni los peajes.
  ///
  /// [tolls] son los peajes en unidades menores; salen de
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

    // ── Bajada de bandera, con el multiplicador de la franja de salida
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

    // ── Espera gratuita, descontada del total y no de cada parada
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

    // ── Cargos que sí multiplica la demanda, antes de aplicarla
    final allSurcharges = <Surcharge>[...surcharges, ...extraSurcharges];
    for (final surcharge in allSurcharges) {
      if (surcharge.surgeable && surcharge.amount != 0) {
        lines.add(FareLine(label: surcharge.name, amount: surcharge.amount));
      }
    }

    var variable = lines.fold<int>(0, (sum, l) => sum + l.amount);

    // ── Demanda
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

    // ── Mínimo, antes de sumar lo que no debe verse afectado por él
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

    // ── Cargos fijos que no multiplica la demanda, y peajes
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

    // ── Redondeo, una sola vez y al final
    final rounded = _applyRounding(total);
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

  /// Da formato a un importe en unidades menores de esta moneda.
  String formatMinor(int minorUnits) {
    if (minorUnitDigits == 0) return '$minorUnits';
    final divisor = math.pow(10, minorUnitDigits).toInt();
    final remainder = (minorUnits % divisor).abs();
    return '${minorUnits ~/ divisor},'
        '${remainder.toString().padLeft(minorUnitDigits, '0')}';
  }

  /// Una estimación **antes** de empezar, a partir de una ruta calculada.
  ///
  /// Sirve para enseñar «unos 12 €» al pedir el coche. No sustituye a
  /// [quote]: no hay paradas todavía, así que la espera no entra, y el tiempo
  /// es el que predijo el servicio, no el que ocurrió.
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

  int _applyRounding(int amount) {
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

  /// Parte el viaje por los límites de las franjas horarias.
  List<_Segment> _splitByBands(TripSummary trip) {
    final boundaries = <DateTime>{trip.start, trip.end};

    if (bands.isNotEmpty) {
      // Los límites candidatos son las horas de inicio y fin de cada franja,
      // en cada día que toca el viaje. Un viaje dura minutos u horas, así que
      // son un puñado de fechas, no un barrido.
      // Se conserva la zona del viaje. Construir aquí un `DateTime` local
      // cuando las marcas vienen en UTC pondría el corte de la nocturna a las
      // 22:00 de la máquina, no a las 22:00 del viaje: en un servidor en otro
      // huso la tarifa cambiaría de hora sin que nadie tocase nada.
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

    // La distancia se reparte en proporción al tiempo en marcha.
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
