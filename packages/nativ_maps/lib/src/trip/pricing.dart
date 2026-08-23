// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/trip/auction.dart';
import 'package:nativ_maps/src/trip/dispatch.dart';
import 'package:nativ_maps/src/trip/fare.dart';

/// Una presión de demanda con nombre, para que el desglose se pueda explicar.
///
/// La lluvia, un partido que acaba, el último metro. El motor no las adivina
/// —no tiene forma— pero sí las multiplica y las deja escritas en el desglose,
/// que es lo que permite responder a «¿por qué me sugieres 9 y no 6?».
@immutable
class DemandSignal {
  /// Crea una señal.
  const DemandSignal({required this.name, required this.multiplier});

  /// Lluvia moderada: sube la demanda y baja la oferta a la vez.
  static const DemandSignal rain = DemandSignal(name: 'Rain', multiplier: 1.15);

  /// Salida de un evento masivo.
  static const DemandSignal event = DemandSignal(
    name: 'Event',
    multiplier: 1.30,
  );

  /// Franja sin transporte público.
  static const DemandSignal noTransit = DemandSignal(
    name: 'No public transport',
    multiplier: 1.20,
  );

  /// El nombre que sale en el desglose.
  final String name;

  /// Por cuánto multiplica.
  final double multiplier;

  @override
  String toString() => 'DemandSignal($name, ×$multiplier)';
}

/// El estado del mercado en el momento de pedir.
///
/// Lo que sabe la plataforma y el dispositivo no: cuántos coches hay libres y
/// cuánta gente está pidiendo a la vez.
@immutable
class MarketConditions {
  /// Crea un estado de mercado.
  const MarketConditions({
    this.availableDrivers = 0,
    this.openRequests = 0,
    this.signals = const <DemandSignal>[],
    this.returnEmptyProbability = 0,
    this.congestionFactor = 1.0,
  });

  /// Cuántos conductores libres hay en la zona.
  final int availableDrivers;

  /// Cuántas peticiones sin asignar hay compitiendo por ellos.
  final int openRequests;

  /// Presiones de demanda con nombre.
  final List<DemandSignal> signals;

  /// Probabilidad de que el conductor vuelva de vacío, entre 0 y 1.
  ///
  /// Un trayecto que acaba en un polígono industrial a las once de la noche
  /// obliga a volver sin pasajero, y ese kilometraje lo paga el conductor. Sin
  /// una prima que lo cubra, esas carreras no las coge nadie y el pasajero se
  /// queda esperando sin entender por qué.
  final double returnEmptyProbability;

  /// Cuánto más tarda el trayecto que sin tráfico.
  ///
  /// Sale de comparar la duración con `TrafficUsage.useTrafficData` y con
  /// `TrafficUsage.ignoreTrafficData`. `1.0` es circulación libre; `1.6` es un
  /// trayecto que tarda un 60 % más por atasco.
  ///
  /// Solo se aplica si la tarifa **no** cobra por minuto: cuando lo hace, el
  /// atasco ya está pagado y volver a sumarlo sería cobrarlo dos veces.
  final double congestionFactor;

  /// Cuántas peticiones hay por cada conductor libre.
  ///
  /// Es la medida estándar de presión del mercado. Sin conductores devuelve
  /// infinito, que el motor recorta al techo configurado.
  double get demandRatio {
    if (availableDrivers <= 0) return double.infinity;
    return openRequests / availableDrivers;
  }

  @override
  String toString() =>
      'MarketConditions($openRequests peticiones / $availableDrivers libres)';
}

/// Un factor que movió el precio sugerido, y cuánto.
@immutable
class PriceFactor {
  /// Crea un factor.
  const PriceFactor({
    required this.name,
    required this.multiplier,
    this.detail = '',
  });

  /// Qué es.
  final String name;

  /// Por cuánto multiplicó.
  final double multiplier;

  /// La explicación corta.
  final String detail;

  @override
  String toString() =>
      '$name ×${multiplier.toStringAsFixed(2)}'
      '${detail.isEmpty ? '' : ' ($detail)'}';
}

/// Cuántos conductores aceptarían un importe, y quién llegaría antes.
///
/// Cuando hay datos reales de conductores cercanos esto **no es una
/// estimación**: es contar cuántos de ellos ganan dinero con ese importe.
@immutable
class AcceptanceForecast {
  /// Crea una previsión.
  const AcceptanceForecast({
    required this.probability,
    required this.driversLikelyToAccept,
    required this.driversConsidered,
    required this.expectedPickup,
    required this.estimated,
  });

  /// Probabilidad de que **alguien** acepte, entre 0 y 1.
  final double probability;

  /// Cuántos de los conductores cercanos ganan dinero con ese importe.
  final int driversLikelyToAccept;

  /// Sobre cuántos conductores se calculó.
  final int driversConsidered;

  /// Cuánto tardaría en llegar el más cercano de los que aceptarían.
  ///
  /// Es el tiempo de conducción real que devolvió la matriz de rutas, no una
  /// suposición. Es `null` si no aceptaría ninguno.
  final Duration? expectedPickup;

  /// ¿Hay alguna suposición detrás de este número?
  ///
  /// `false` solo cuando se contaron conductores reales **todos refinados
  /// por la matriz de rutas**. Es `true` en dos casos:
  ///
  /// - no se pasó ningún conductor, y la probabilidad sale de una curva
  ///   paramétrica que **hay que calibrar** (ver
  ///   `PriceAdvisor.fallbackSteepness`);
  /// - se pasaron conductores pero alguno no pasó por la matriz, así que su
  ///   tiempo de recogida es una estimación en línea recta.
  ///
  /// No enseñes un porcentaje con decimales cuando esto es `true`.
  final bool estimated;

  @override
  String toString() => estimated
      ? 'AcceptanceForecast(${(probability * 100).round()} % estimated)'
      : 'AcceptanceForecast($driversLikelyToAccept of $driversConsidered, '
            'arrives in ${expectedPickup?.inMinutes ?? '—'} min)';
}

/// El precio sugerido para una carrera, con la forma de inDrive.
///
/// Tres números y el porqué de cada uno.
@immutable
class SuggestedPrice {
  /// Crea una sugerencia.
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

  /// El código ISO 4217 de la moneda.
  final String currency;

  /// Cuántos decimales tiene la moneda.
  final int minorUnitDigits;

  /// Lo que costaría con la tarifa de referencia, sin mercado.
  ///
  /// Es el ancla honesta: lo que valdría el trayecto un martes tranquilo.
  final int reference;

  /// El **mínimo recomendado de puja**.
  ///
  /// Por debajo de esto ningún conductor cercano gana dinero, así que la
  /// petición se queda sin respuesta. No es una prohibición: es la frontera a
  /// partir de la cual el pasajero está pidiendo que alguien trabaje gratis.
  final int minimum;

  /// El precio que se enseña por defecto.
  final int recommended;

  /// Lo que hay que ofrecer para que acepte el conductor **más cercano**.
  ///
  /// A veces coincide con [recommended]; cuando no, la diferencia es
  /// exactamente lo que cuesta la prisa.
  final int fast;

  /// Peajes y tasas, que el pasajero paga aparte.
  ///
  /// **No van dentro del precio**, igual que en inDrive: son un importe que no
  /// se negocia y que no se lleva el conductor.
  final int extrasPaidSeparately;

  /// El multiplicador total de mercado que se aplicó.
  final double demandMultiplier;

  /// Cada cosa que movió el precio, en orden.
  final List<PriceFactor> factors;

  /// Qué pasaría con [recommended].
  final AcceptanceForecast forecast;

  /// Da formato a un importe en unidades menores.
  String formatAmount(int minorUnits) {
    if (minorUnitDigits == 0) return '$minorUnits';
    final divisor = math.pow(10, minorUnitDigits).toInt();
    final remainder = (minorUnits % divisor).abs();
    return '${minorUnits ~/ divisor},'
        '${remainder.toString().padLeft(minorUnitDigits, '0')}';
  }

  /// El desglose en texto, para enseñarlo o registrarlo.
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

/// Calcula el precio sugerido de una carrera en un mercado de pujas.
///
/// ```dart
/// final asesor = PriceAdvisor(tariff: tarifa, economics: costes);
///
/// // 1 · La ruta da distancia, duración con tráfico y peajes.
/// final ruta = (await maps.routes.calculateRoutes(
///   origin: recogida, destination: destino,
/// )).best!;
///
/// // 2 · La matriz da el tiempo REAL de recogida de cada conductor.
/// final cercanos = await planificador.findNearest(conectados, recogida);
///
/// // 3 · Y con eso sale el precio.
/// final precio = asesor.suggest(
///   distanceMeters: ruta.distanceMeters,
///   duration: ruta.duration,
///   nearbyDrivers: cercanos,
///   market: MarketConditions(
///     availableDrivers: cercanos.length,
///     openRequests: peticionesSinAsignar,
///     signals: <DemandSignal>[if (llueve) DemandSignal.rain],
///   ),
///   tolls: ruta.tollCostByCurrency['USD']?.round() ?? 0,
/// );
/// print(precio.explain());
/// ```
///
/// ## De dónde sale cada número
///
/// El modelo tiene cuatro capas, y cada una responde a una pregunta distinta:
///
/// | Capa | Pregunta | De dónde sale |
/// |---|---|---|
/// | Referencia | ¿cuánto vale este trayecto? | `Tariff` + la ruta |
/// | Suelo de oferta | ¿qué necesita cobrar un conductor? | matriz de rutas |
/// | Demanda | ¿con cuánta gente compito? | peticiones ÷ conductores |
/// | Previsión | ¿cuántos aceptarían? | conteo sobre los reales |
///
/// ## Por qué esto no es una fórmula inventada
///
/// La parte difícil de un mercado de pujas es saber **a qué precio contesta
/// alguien**. Lo habitual es inventar una curva y enseñar un porcentaje con
/// dos decimales que nadie ha medido.
///
/// Aquí no hace falta. Con los tiempos de recogida reales que devuelve
/// `calculateRouteMatrix`, el precio de reserva de cada conductor cercano es
/// **calculable**: es su [BidAdvisor.breakEvenFare]. Y entonces «cuántos
/// aceptarían a este precio» deja de ser una estimación y pasa a ser un
/// conteo.
///
/// Solo cuando no se pasan conductores se cae a una curva paramétrica, y el
/// resultado viene marcado con `estimated: true` para que no se confunda.
///
/// ## Por qué el tiempo de recogida pesa más
///
/// Los estudios de aceptación de carreras coinciden en que a los conductores
/// **el tiempo de ir a recoger les molesta más que el mismo tiempo dentro del
/// trayecto**: no está pagado, no acerca al destino y compite con la
/// posibilidad de que salga algo mejor. [pickupAversion] recoge eso
/// inflando el tiempo muerto al calcular el precio de reserva.
@immutable
class PriceAdvisor {
  /// Crea un asesor de precios.
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

  /// La tarifa de referencia: lo que valdría el trayecto sin mercado.
  final Tariff tariff;

  /// Los costes del conductor, para calcular su precio de reserva.
  final DriverEconomics economics;

  /// Cuánto responde el precio al desequilibrio entre oferta y demanda.
  ///
  /// El multiplicador es `ratio ^ surgeExponent`, con el ratio en peticiones
  /// por conductor libre. Con `0.6`: dos peticiones por coche dan ×1,52; tres,
  /// ×1,93; cinco, ×2,63 —recortado por [maxSurge]—.
  ///
  /// Un exponente por debajo de 1 hace que el precio suba **menos que
  /// proporcionalmente** al desequilibrio, que es lo que se quiere: la
  /// escasez de coches se corrige sola en minutos, y una subida lineal
  /// sobrerreacciona a picos que se deshacen antes de que nadie los note.
  final double surgeExponent;

  /// El techo del multiplicador de demanda.
  ///
  /// Existe siempre, y en muchos mercados está además regulado. Sin techo, una
  /// zona con cero conductores libres dispara el ratio a infinito.
  final double maxSurge;

  /// Suelo del mínimo de puja, como fracción de la referencia.
  ///
  /// Solo se usa cuando no hay datos de conductores cercanos: con ellos, el
  /// mínimo es el precio de reserva del más barato, que es un dato mejor.
  final double minimumRatio;

  /// Cuánto más pesa un minuto de ir a recoger que un minuto de trayecto.
  ///
  /// `1.6` significa que doce minutos de recogida se valoran como si fueran
  /// diecinueve. Está por encima de 1 porque el tiempo muerto no está pagado,
  /// no acerca al destino y compite con esperar una carrera mejor.
  ///
  /// Es el parámetro que más conviene calibrar con datos propios: cambia
  /// bastante entre conductores a tiempo completo y a tiempo parcial.
  final double pickupAversion;

  /// Qué fracción de los conductores cercanos debería aceptar el recomendado.
  final double targetAcceptance;

  /// Cuánto se pasa del precio de reserva para que acepten de verdad.
  ///
  /// Nadie acepta un trabajo que le deja exactamente cero de margen sobre su
  /// objetivo. Un 8 % por encima convierte «no pierdo» en «me compensa».
  final double fastMargin;

  /// Pendiente de la curva de respaldo, cuando no hay conductores.
  ///
  /// **Esto sí es un parámetro inventado**, y por eso el resultado que produce
  /// viene marcado con `AcceptanceForecast.estimated`. Calíbralo con tu
  /// historial de ofertas y aceptaciones en cuanto lo tengas.
  final double fallbackSteepness;

  /// Cuánto más largo es el trayecto real que la línea recta.
  ///
  /// Solo se usa con conductores sin refinar por la matriz. `1.4` es lo normal
  /// en una trama urbana regular.
  final double detourFactor;

  /// Velocidad urbana supuesta, para conductores sin refinar.
  final double urbanSpeedKmh;

  /// Calcula el precio sugerido.
  ///
  /// [nearbyDrivers] deberían venir de `DispatchPlanner.findNearest`, ya
  /// refinados con la matriz: sin ese refinado el cálculo funciona, pero se
  /// apoya en distancias en línea recta y el resultado se marca como estimado.
  ///
  /// [tolls] **no entra en el precio**: se informa aparte en
  /// [SuggestedPrice.extrasPaidSeparately], igual que hace inDrive.
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

    // ── 1 · Referencia: lo que vale el trayecto un martes tranquilo
    final reference = tariff
        .estimate(
          distanceMeters: distanceMeters,
          duration: duration,
          departure: departure,
        )
        .total;

    // ── 2 · Multiplicador de mercado
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

    // El atasco solo se cobra aparte si la tarifa NO cobra por minuto: cuando
    // lo hace, ya está dentro de la referencia y sumarlo sería cobrarlo dos
    // veces.
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
      // Cubrir la vuelta de vacío: el kilometraje de regreso, ponderado por la
      // probabilidad de tener que hacerlo, expresado como recargo sobre la
      // referencia.
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

    // ── 3 · Suelo de oferta: qué necesita cobrar cada conductor cercano
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

    // ── 4 · Lo que cuesta que venga el más cercano
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

    return SuggestedPrice(
      currency: tariff.currency,
      minorUnitDigits: tariff.minorUnitDigits,
      reference: reference,
      minimum: math.min(floorPrice, recommendedPrice),
      recommended: recommendedPrice,
      fast: fastPrice,
      extrasPaidSeparately: tolls + fees,
      demandMultiplier: multiplier,
      factors: List<PriceFactor>.unmodifiable(factors),
      forecast: forecast(
        offered: recommendedPrice,
        nearbyDrivers: nearbyDrivers,
        distanceMeters: distanceMeters,
        duration: duration,
        reference: reference,
      ),
    );
  }

  /// Cuántos conductores aceptarían [offered], y quién llegaría antes.
  ///
  /// Es lo que se llama al mover el deslizador del precio: con los conductores
  /// cercanos delante, **cuenta**; sin ellos, estima con una curva que hay que
  /// calibrar.
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

    // Si alguno no pasó por la matriz, su tiempo de recogida es una
    // suposición y el conteo deja de ser un conteo. Se dice.
    final allRefined = nearbyDrivers.every((c) => c.refined);

    return AcceptanceForecast(
      probability: wouldAccept / nearbyDrivers.length,
      driversLikelyToAccept: wouldAccept,
      driversConsidered: nearbyDrivers.length,
      expectedPickup: soonest,
      estimated: !allRefined,
    );
  }

  /// El precio de reserva de un conductor: por debajo, no le compensa.
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
      // Aquí entra la aversión al tiempo muerto: el minuto de ir a recoger se
      // valora como más de un minuto, que es lo que dicen los estudios de
      // aceptación de carreras.
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

  /// El precio al que acepta la fracción [fraction] de una lista ordenada.
  static int _quantile(List<int> sorted, double fraction) {
    if (sorted.isEmpty) return 0;
    final target = (fraction.clamp(0.0, 1.0) * sorted.length).ceil();
    final index = (target - 1).clamp(0, sorted.length - 1);
    return sorted[index];
  }
}
