// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/lat_lng.dart';
import 'package:nativ_maps/src/trip/fare.dart';

/// La petición de un pasajero, con el precio que propone.
///
/// Es el modelo de las aplicaciones de puja —inDrive y las que la copian—,
/// donde el pasajero nombra un precio y los conductores lo aceptan o
/// contraofertan, en vez de que la plataforma imponga la tarifa.
@immutable
class RideRequest {
  /// Crea una petición.
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

  /// El identificador de la petición.
  final String id;

  /// Dónde recoge.
  final LatLng pickup;

  /// Dónde deja.
  final LatLng dropoff;

  /// Lo que ofrece el pasajero, en unidades menores.
  final int proposedFare;

  /// El código ISO 4217 de la moneda.
  final String currency;

  /// Cuándo se creó.
  final DateTime createdAt;

  /// La distancia estimada del trayecto, si ya se calculó la ruta.
  final double? estimatedDistanceMeters;

  /// La duración estimada del trayecto.
  final Duration? estimatedDuration;

  /// Cuántas personas viajan.
  final int passengerCount;

  /// Una nota libre del pasajero.
  final String note;

  /// Etiquetas de requisitos: equipaje, mascota, silla infantil.
  final Set<String> tags;

  @override
  String toString() => 'RideRequest($id, $proposedFare $currency)';
}

/// La oferta de un conductor sobre una petición.
@immutable
class DriverBid {
  /// Crea una oferta.
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

  /// Quién ofrece.
  final String driverId;

  /// Sobre qué petición.
  final String requestId;

  /// Cuánto pide, en unidades menores.
  ///
  /// Puede ser igual a lo que ofreció el pasajero —aceptación directa— o
  /// distinto, que es la contraoferta.
  final int amount;

  /// Cuánto tardaría en llegar a recoger.
  final Duration etaToPickup;

  /// Cuándo se emitió.
  final DateTime createdAt;

  /// Cuánto tiempo se mantiene en pie.
  ///
  /// Una oferta sin caducidad es una trampa: el conductor sigue conduciendo, y
  /// dos minutos después su tiempo de llegada ya no es el que ofreció.
  final Duration validFor;

  /// La valoración del conductor, normalmente de 0 a 5.
  final double? driverRating;

  /// Cuántos viajes lleva completados.
  final int? completedTrips;

  /// Una descripción corta del vehículo.
  final String vehicleLabel;

  /// Cuándo caduca.
  DateTime get expiresAt => createdAt.add(validFor);

  /// ¿Ha caducado ya?
  bool isExpired(DateTime now) => !now.isBefore(expiresAt);

  @override
  String toString() =>
      'DriverBid($driverId, $amount, arrives in ${etaToPickup.inMinutes} min)';
}

/// El rango de precio que se le sugiere al pasajero.
///
/// El pasajero pone el precio, pero necesita una referencia o pedirá dos euros
/// por un trayecto de veinte kilómetros y nadie le contestará.
@Deprecated(
  'The result type of the deprecated FareAdvisor. Use SuggestedPrice.',
)
@immutable
class FareSuggestion {
  /// Crea una sugerencia.
  const FareSuggestion({
    required this.currency,
    required this.minorUnitDigits,
    required this.reference,
    required this.recommended,
    required this.minimum,
    required this.maximum,
    required this.demandFactor,
  });

  /// El código ISO 4217 de la moneda.
  final String currency;

  /// Cuántos decimales tiene la moneda.
  final int minorUnitDigits;

  /// El precio que saldría con la tarifa de referencia, sin demanda.
  final int reference;

  /// El precio sugerido, ya con la demanda aplicada.
  final int recommended;

  /// El suelo por debajo del cual casi nadie va a contestar.
  final int minimum;

  /// El techo por encima del cual el pasajero está pagando de más.
  final int maximum;

  /// El multiplicador de demanda que se aplicó.
  final double demandFactor;

  @override
  String toString() =>
      'FareSuggestion($minimum – $recommended – $maximum $currency)';
}

/// Sugiere precios y estima cuántos conductores contestarían.
///
/// ## Sobre el modelo de aceptación
///
/// [acceptanceProbability] no es una medición: es una **curva logística con
/// dos parámetros**, y los valores por defecto son una forma razonable, no un
/// dato. Sirven para arrancar; en cuanto la aplicación tenga historial hay que
/// ajustar [midpointRatio] y [steepness] con las ofertas reales y cuántas se
/// aceptaron.
///
/// Se documenta así de claro a propósito: un número inventado con dos decimales
/// enseñado en pantalla como «87 % de probabilidad» es peor que no enseñar
/// nada, porque nadie vuelve a cuestionarlo.
@Deprecated(
  'Use PriceAdvisor: it computes each nearby driver\'s real reservation '
  'price instead of guessing it with a curve, and reports why. '
  'FareAdvisor will be removed in 1.0.0.',
)
@immutable
class FareAdvisor {
  /// Crea un asesor de precios.
  const FareAdvisor({
    required this.tariff,
    this.minimumRatio = 0.80,
    this.maximumRatio = 1.40,
    this.midpointRatio = 0.95,
    this.steepness = 9.0,
  });

  /// La tarifa de referencia con la que se calcula el precio justo.
  final Tariff tariff;

  /// Qué fracción de la referencia marca el suelo sugerido.
  final double minimumRatio;

  /// Qué múltiplo de la referencia marca el techo sugerido.
  final double maximumRatio;

  /// La proporción sobre la referencia a la que aceptaría la mitad.
  ///
  /// Por debajo de 1 porque un conductor sin carrera prefiere una barata a
  /// ninguna: el punto de indiferencia real está algo por debajo del precio
  /// teórico.
  final double midpointRatio;

  /// Cuán abrupta es la curva alrededor de [midpointRatio].
  ///
  /// Más alto, más se parece a un interruptor: por debajo del punto medio no
  /// contesta nadie y por encima contestan todos.
  final double steepness;

  /// Calcula el rango sugerido para un trayecto.
  ///
  /// [demandFactor] es la presión de la demanda en esa zona y ese momento:
  /// `1.0` es normal, `1.6` es hora punta con lluvia.
  FareSuggestion suggest({
    required double distanceMeters,
    required Duration duration,
    DateTime? departure,
    double demandFactor = 1.0,
    int tolls = 0,
  }) {
    if (demandFactor <= 0) {
      throw ArgumentError.value(
        demandFactor,
        'demandFactor',
        'Must be greater than zero',
      );
    }

    final reference = tariff
        .estimate(
          distanceMeters: distanceMeters,
          duration: duration,
          departure: departure,
          tolls: tolls,
        )
        .total;
    final recommendedPrice = (reference * demandFactor).round();

    return FareSuggestion(
      currency: tariff.currency,
      minorUnitDigits: tariff.minorUnitDigits,
      reference: reference,
      recommended: recommendedPrice,
      minimum: (reference * minimumRatio * demandFactor).round(),
      maximum: (reference * maximumRatio * demandFactor).round(),
      demandFactor: demandFactor,
    );
  }

  /// Qué proporción de conductores aceptaría ese importe, entre 0 y 1.
  ///
  /// Ver la nota de la clase: es una curva calibrable, no una medición.
  double acceptanceProbability({
    required int offered,
    required int reference,
    double demandFactor = 1.0,
  }) {
    if (reference <= 0) return 0;
    final ratio = offered / (reference * demandFactor);
    return 1 / (1 + math.exp(-steepness * (ratio - midpointRatio)));
  }
}

/// Los costes reales de conducir, para decidir si una carrera compensa.
///
/// Todos los importes van en unidades menores de la moneda de la tarifa.
@immutable
class DriverEconomics {
  /// Crea un modelo de costes.
  const DriverEconomics({
    required this.costPerKilometer,
    this.commissionRate = 0,
    this.minimumNetPerHour = 0,
    this.returnFactor = 0.0,
  });

  /// Lo que cuesta cada kilómetro: combustible, neumáticos, mantenimiento.
  ///
  /// **No es solo la gasolina.** Un coche de gasolina en 2026 gasta unos 8
  /// céntimos de combustible por kilómetro, pero el desgaste real ronda los
  /// 15–20. Un conductor que solo cuenta el combustible cree que gana un
  /// tercio más de lo que gana.
  final int costPerKilometer;

  /// La comisión de la plataforma, entre 0 y 1.
  final double commissionRate;

  /// Lo mínimo que el conductor quiere ganar por hora, ya neto.
  final int minimumNetPerHour;

  /// Qué fracción del trayecto muerto se repite al volver.
  ///
  /// Una carrera que acaba en las afueras a menudo obliga a volver de vacío.
  /// Con `0.5` se cuenta la mitad de esa vuelta como coste. Con `0` se supone
  /// que siempre habrá otra carrera esperando donde te deje esta.
  final double returnFactor;

  @override
  String toString() =>
      'DriverEconomics($costPerKilometer/km, commission $commissionRate)';
}

/// El análisis de si una carrera le conviene al conductor.
@immutable
class BidEvaluation {
  /// Crea una evaluación.
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

  /// El código ISO 4217 de la moneda.
  final String currency;

  /// Cuántos decimales tiene la moneda.
  final int minorUnitDigits;

  /// Lo que paga el pasajero.
  final int gross;

  /// Lo que se lleva la plataforma.
  final int commission;

  /// Lo que cuesta conducir todos esos kilómetros.
  final int drivingCost;

  /// Lo que queda de verdad.
  final int net;

  /// Cuánto tiempo queda ocupado: ir a recoger, más el trayecto.
  final Duration engagedDuration;

  /// El neto llevado a euros por hora.
  ///
  /// **Es el único número que permite comparar dos carreras.** Ocho euros a
  /// doce minutos de distancia son peores que cinco a dos minutos, y el
  /// importe suelto no lo dice.
  final int netPerHour;

  /// ¿Llega al mínimo por hora que pide el conductor?
  final bool worthIt;

  /// Los metros hasta el punto de recogida, que no paga nadie.
  final double deadheadMeters;

  /// Los metros del trayecto con pasajero.
  final double tripMeters;

  /// Qué proporción del recorrido total va sin pasajero, entre 0 y 1.
  ///
  /// Por encima de 0,4 la carrera casi nunca compensa.
  double get deadheadShare {
    final total = deadheadMeters + tripMeters;
    return total <= 0 ? 0 : deadheadMeters / total;
  }

  @override
  String toString() =>
      'BidEvaluation(neto $net, $netPerHour/h, '
      '${worthIt ? 'compensa' : 'NO compensa'})';
}

/// Decide si una oferta le conviene al conductor.
///
/// ## El error que arruina a los conductores
///
/// Una carrera de 8 € parece mejor que una de 5 €. Pero si la primera está a
/// 12 minutos de distancia y la segunda a 2, y las dos duran 10 minutos de
/// trayecto:
///
/// | | Carrera A | Carrera B |
/// |---|---|---|
/// | Importe | 8,00 € | 5,00 € |
/// | Ir a recoger | 5,0 km · 12 min | 0,8 km · 2 min |
/// | Trayecto | 6,0 km · 10 min | 4,2 km · 10 min |
/// | Kilómetros totales | 11,0 | 5,0 |
/// | Coste a 0,20 €/km | 2,20 € | 1,00 € |
/// | Neto | 5,80 € | 4,00 € |
/// | Tiempo ocupado | 22 min | 12 min |
/// | **Neto por hora** | **15,82 €/h** | **20,00 €/h** |
///
/// La carrera que paga menos deja un 26 % más por hora. Esta clase hace esa
/// cuenta, y esos números son exactamente los que comprueba la suite.
@immutable
class BidAdvisor {
  /// Crea un asesor para el conductor.
  const BidAdvisor({
    required this.economics,
    required this.minorUnitDigits,
    required this.currency,
  });

  /// El modelo de costes del conductor.
  final DriverEconomics economics;

  /// Cuántos decimales tiene la moneda.
  final int minorUnitDigits;

  /// El código ISO 4217 de la moneda.
  final String currency;

  /// Evalúa una carrera concreta.
  ///
  /// [deadheadMeters] y [deadheadDuration] son el trayecto **hasta recoger**,
  /// que no paga nadie. Salen de una llamada a la matriz de rutas o, en su
  /// defecto, de la distancia en línea recta con un factor de corrección.
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

  /// El importe mínimo al que esta carrera alcanza el objetivo por hora.
  ///
  /// Es lo que hay que contraofertar. Devuelve el importe bruto, ya contando
  /// que la comisión se lleva su parte.
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
    // Redondeo hacia arriba, pero sin castigar el ruido de la coma flotante:
    // `1200 × 0.28 + 140` da 476.00000000000006, y un `ceil()` a secas
    // devolvería 477. Un céntimo no arruina a nadie, pero hace que la misma
    // carrera dé dos números distintos según cómo se escriba la duración.
    const epsilon = 1e-6;
    return (gross - epsilon).ceil();
  }
}

/// Cómo se ordenan las ofertas que ve el pasajero.
///
/// Los pesos suman lo que sea; se normalizan solos. Poner
/// `priceWeight: 1, etaWeight: 0` ordena solo por precio.
@immutable
class BidRanking {
  /// Crea un criterio de ordenación.
  const BidRanking({
    this.priceWeight = 1.0,
    this.etaWeight = 1.0,
    this.ratingWeight = 0.5,
  });

  /// Cuánto pesa que sea barata.
  final double priceWeight;

  /// Cuánto pesa que llegue pronto.
  final double etaWeight;

  /// Cuánto pesa la valoración del conductor.
  final double ratingWeight;

  /// Ordena las ofertas de mejor a peor.
  ///
  /// Cada dimensión se normaliza al rango observado antes de pesarla: si no,
  /// una diferencia de dos euros y una de dos minutos no serían comparables.
  /// Las ofertas caducadas se quitan.
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
          // El precio y la espera son «menos es mejor», así que se invierten.
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

/// En qué estado está una subasta.
enum AuctionState {
  /// Admite ofertas.
  open,

  /// El pasajero ya eligió.
  accepted,

  /// Se agotó el tiempo sin que nadie ofreciera o sin elegir.
  expired,

  /// El pasajero la retiró.
  cancelled,
}

/// La subasta de una carrera: recoge ofertas y deja elegir una.
///
/// Es una máquina de estados en memoria, sin red y sin persistencia: sirve
/// igual en el cliente que en un servidor Dart, y se guarda donde haga falta.
class RideAuction {
  /// Abre una subasta.
  RideAuction({
    required this.request,
    this.duration = const Duration(minutes: 5),
  });

  /// La petición que se subasta.
  final RideRequest request;

  /// Cuánto tiempo admite ofertas.
  final Duration duration;

  final Map<String, DriverBid> _bids = <String, DriverBid>{};
  AuctionState _state = AuctionState.open;
  DriverBid? _winner;

  /// Cuándo se cierra.
  DateTime get closesAt => request.createdAt.add(duration);

  /// El estado actual, ya teniendo en cuenta la caducidad.
  AuctionState stateAt(DateTime now) {
    if (_state != AuctionState.open) return _state;
    return now.isBefore(closesAt) ? AuctionState.open : AuctionState.expired;
  }

  /// La oferta ganadora, si ya se eligió.
  DriverBid? get winner => _winner;

  /// Las ofertas vivas en ese instante.
  List<DriverBid> liveBids(DateTime now) => <DriverBid>[
    for (final offer in _bids.values)
      if (!offer.isExpired(now)) offer,
  ];

  /// Registra una oferta.
  ///
  /// Un conductor solo tiene una oferta viva: volver a ofertar **sustituye** a
  /// la anterior, que es lo que hace falta para poder bajar el precio.
  ///
  /// Lanza [StateError] si la subasta ya no admite ofertas, y [ArgumentError]
  /// si la oferta es de otra petición.
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

  /// Retira la oferta de un conductor.
  ///
  /// Devuelve `true` si había alguna que retirar.
  bool withdraw(String driverId) => _bids.remove(driverId) != null;

  /// Acepta la oferta de un conductor y cierra la subasta.
  ///
  /// Lanza [StateError] si la subasta ya está cerrada o si esa oferta caducó
  /// —aceptar una oferta caducada es prometerle al pasajero un tiempo de
  /// llegada que el conductor ya no puede cumplir.
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

  /// Cancela la subasta.
  void cancel() {
    if (_state == AuctionState.open) _state = AuctionState.cancelled;
  }
}
