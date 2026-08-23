// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/enums.dart';
import 'package:nativ_maps/src/core/json.dart';
import 'package:nativ_maps/src/core/lat_lng.dart';
import 'package:nativ_maps/src/core/polyline.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  Una regla que gobierna todo este archivo
//
//  **Distancias en metros y duraciones en segundos. Siempre.** La API v2 no
//  tiene parámetro de unidad, y enviarlo —como hacía la generación v0 con
//  `DistanceUnit`— provoca un 400. Como no hay conversión posible, tampoco hay
//  ninguna que se pueda olvidar.
//
//  Las duraciones se exponen además como `Duration` de Dart, que es lo que
//  espera el resto del lenguaje.
// ═══════════════════════════════════════════════════════════════════════════

/// La geometría de un tramo, venga como lista de puntos o como polilínea.
///
/// Amazon Location devuelve una cosa u otra según `LegGeometryFormat`, y este
/// tipo absorbe la diferencia: [points] siempre tiene los puntos, se haya
/// pedido el formato que se haya pedido.
@immutable
class RouteGeometry {
  /// Crea la geometría a partir de los puntos.
  const RouteGeometry(this.points, {this.encoded});

  /// Lee la geometría de la respuesta, decodificando si hace falta.
  ///
  /// Una polilínea ilegible devuelve una geometría **vacía** en vez de lanzar:
  /// una ruta sin línea sigue siendo utilizable —distancia y duración están en
  /// otro sitio— y tumbar la pantalla por no poder pintarla es peor. El fallo
  /// queda visible porque [points] sale vacío.
  factory RouteGeometry.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const RouteGeometry(<LatLng>[]);

    final lineString = Json.latLngList(json, 'LineString');
    if (lineString.isNotEmpty) return RouteGeometry(lineString);

    final encoded = Json.string(json, 'Polyline');
    if (encoded != null) {
      try {
        return RouteGeometry(decodeFlexiblePolyline(encoded), encoded: encoded);
      } on FormatException {
        return RouteGeometry(const <LatLng>[], encoded: encoded);
      }
    }
    return const RouteGeometry(<LatLng>[]);
  }

  /// Los puntos de la línea, ya decodificados.
  final List<LatLng> points;

  /// La cadena original, si vino comprimida.
  ///
  /// Guardarla permite persistir la ruta sin volver a codificarla y sin perder
  /// precisión en el viaje de ida y vuelta.
  final String? encoded;

  /// ¿Se pudo leer la geometría?
  bool get isEmpty => points.isEmpty;

  /// El rectángulo que encierra la línea, o `null` si está vacía.
  ///
  /// Es lo que se le pasa a `fitBounds` para encuadrar la ruta entera.
  LatLngBounds? get bounds =>
      points.isEmpty ? null : LatLngBounds.fromPoints(points);

  @override
  String toString() => 'RouteGeometry(${points.length} puntos)';
}

/// Una indicación de navegación.
@immutable
class TravelStep {
  /// Crea la indicación.
  const TravelStep({
    required this.distanceMeters,
    required this.duration,
    this.type,
    this.instruction,
    this.geometryOffset,
    this.nextRoad,
    this.currentRoad,
    this.turnAngle,
    this.turnIntensity,
    this.exitNumber,
  });

  /// Lee la indicación de la respuesta del servicio.
  factory TravelStep.fromJson(Map<String, dynamic> json) => TravelStep(
    distanceMeters: Json.numberOrZero(json, 'Distance'),
    duration: Duration(seconds: Json.integer(json, 'Duration') ?? 0),
    type: Json.string(json, 'Type'),
    instruction: Json.string(json, 'Instruction'),
    geometryOffset: Json.integer(json, 'GeometryOffset'),
    nextRoad: _roadName(Json.object(json, 'NextRoad')),
    currentRoad: _roadName(Json.object(json, 'CurrentRoad')),
    turnAngle: Json.number(json, 'TurnAngle'),
    turnIntensity: Json.string(json, 'TurnIntensity'),
    exitNumber: Json.strings(json, 'ExitNumber').firstOrNull,
  );

  static String? _roadName(Map<String, dynamic>? road) {
    if (road == null) return null;
    final names = Json.objects(road, 'RoadName');
    for (final name in names) {
      final value = Json.string(name, 'Value');
      if (value != null) return value;
    }
    return null;
  }

  /// Cuántos metros dura esta indicación.
  final double distanceMeters;

  /// Cuánto se tarda en recorrerla.
  final Duration duration;

  /// La clase de maniobra: `Turn`, `Continue`, `Roundabout`, `Arrive`…
  final String? type;

  /// El texto ya escrito, si se pidió con `instructionsMeasurementSystem`.
  final String? instruction;

  /// En qué punto de [RouteGeometry.points] empieza esta indicación.
  ///
  /// Es lo que permite resaltar en el mapa el tramo de la maniobra en curso
  /// sin volver a calcular nada.
  final int? geometryOffset;

  /// El nombre de la vía a la que se sale.
  final String? nextRoad;

  /// El nombre de la vía en la que se está.
  final String? currentRoad;

  /// El ángulo del giro en grados.
  final double? turnAngle;

  /// Lo cerrado que es el giro: `Slight`, `Typical`, `Sharp`.
  final String? turnIntensity;

  /// El número de la salida, en rotondas y enlaces.
  final String? exitNumber;

  @override
  String toString() =>
      'TravelStep(${type ?? '?'}, ${distanceMeters.round()} m)';
}

/// Un peaje de la ruta.
///
/// **Google no da esto.** Es una de las cosas que solo existen aquí, y para
/// una app de reparto cambia el cálculo del coste por viaje.
@immutable
class Toll {
  /// Crea el peaje.
  const Toll({
    this.systemRef,
    this.country,
    this.paymentMethods = const <String>[],
    this.currency,
    this.amount,
    this.transponders = const <String>[],
  });

  /// Lee el peaje de la respuesta del servicio.
  ///
  /// El importe vive dentro de `PaymentSites[].Rates[].ConvertedPrice`, no en
  /// la raíz del peaje: un peaje tiene varias tarifas —por eje, por hora, por
  /// método de pago— y aquí se toma la primera, que es la que aplica al
  /// vehículo consultado.
  factory Toll.fromJson(Map<String, dynamic> json) {
    final rates = Json.objects(json, 'Rates');
    final firstRate = rates.isEmpty ? null : rates.first;
    final price =
        Json.object(firstRate, 'LocalPrice') ??
        Json.object(firstRate, 'ConvertedPrice');

    return Toll(
      systemRef: Json.string(json, 'SystemRef'),
      country: Json.string(json, 'Country'),
      paymentMethods: Json.strings(firstRate, 'PaymentMethods'),
      currency: Json.string(price, 'Currency'),
      amount: Json.number(price, 'Value'),
      transponders: Json.objects(firstRate, 'Transponders')
          .map((t) => Json.string(t, 'Name'))
          .whereType<String>()
          .toList(growable: false),
    );
  }

  /// La referencia del sistema de peaje.
  final String? systemRef;

  /// El país en el que se cobra.
  final String? country;

  /// Cómo se puede pagar: `Cash`, `CreditCard`, `Transponder`…
  final List<String> paymentMethods;

  /// La moneda del importe, en ISO 4217.
  final String? currency;

  /// Cuánto cuesta.
  final double? amount;

  /// Los transpondedores aceptados, si los hay.
  final List<String> transponders;

  @override
  String toString() => amount == null
      ? 'Toll(${systemRef ?? '?'})'
      : 'Toll($amount ${currency ?? ''})';
}

/// Una incidencia en la ruta: obras, accidente, corte.
@immutable
class RouteIncident {
  /// Crea la incidencia.
  const RouteIncident({
    this.type,
    this.severity,
    this.description,
    this.startTime,
    this.endTime,
  });

  /// Lee la incidencia de la respuesta del servicio.
  factory RouteIncident.fromJson(Map<String, dynamic> json) => RouteIncident(
    type: Json.string(json, 'Type'),
    severity: Json.string(json, 'Severity'),
    description: Json.string(json, 'Description'),
    startTime: Json.dateTime(json, 'StartTime'),
    endTime: Json.dateTime(json, 'EndTime'),
  );

  /// Qué clase de incidencia es.
  final String? type;

  /// Lo grave que es: `Critical`, `High`, `Medium`, `Low`.
  final String? severity;

  /// La descripción legible.
  final String? description;

  /// Cuándo empezó.
  final DateTime? startTime;

  /// Cuándo se espera que acabe.
  final DateTime? endTime;

  @override
  String toString() => 'RouteIncident(${type ?? '?'}, ${severity ?? '?'})';
}

/// Un tramo de la ruta: el trozo entre dos paradas consecutivas.
@immutable
class RouteLeg {
  /// Crea el tramo.
  const RouteLeg({
    required this.distanceMeters,
    required this.duration,
    required this.geometry,
    this.travelMode,
    this.type,
    this.travelOnlyDuration,
    this.steps = const <TravelStep>[],
    this.tolls = const <Toll>[],
    this.incidents = const <RouteIncident>[],
    this.departureTime,
    this.arrivalTime,
    this.departurePosition,
    this.arrivalPosition,
  });

  /// Lee el tramo de la respuesta del servicio.
  ///
  /// ## Dónde viven la distancia y la duración
  ///
  /// **No en el tramo.** En v2 están dentro del bloque de detalle que
  /// corresponde al modo de viaje —`VehicleLegDetails`, `PedestrianLegDetails`
  /// o `FerryLegDetails`—, en `Summary.Overview`.
  ///
  /// Leerlas de `leg['Distance']`, que es donde estaban en v0, no da error:
  /// devuelve **ceros**. Una ruta de 12 km que dice durar 0 segundos pasa
  /// desapercibida en el código y salta a la vista en la pantalla.
  factory RouteLeg.fromJson(Map<String, dynamic> json) {
    final details =
        Json.object(json, 'VehicleLegDetails') ??
        Json.object(json, 'PedestrianLegDetails') ??
        Json.object(json, 'FerryLegDetails');
    final summary = Json.object(details, 'Summary');
    final overview = Json.object(summary, 'Overview');
    final travelOnly = Json.object(summary, 'TravelOnly');
    final departure = Json.object(details, 'Departure');
    final arrival = Json.object(details, 'Arrival');

    return RouteLeg(
      distanceMeters: Json.numberOrZero(overview, 'Distance'),
      duration: Duration(seconds: Json.integer(overview, 'Duration') ?? 0),
      travelOnlyDuration: travelOnly == null
          ? null
          : Duration(seconds: Json.integer(travelOnly, 'Duration') ?? 0),
      geometry: RouteGeometry.fromJson(Json.object(json, 'Geometry')),
      travelMode: Json.enumValue(
        json,
        'TravelMode',
        TravelMode.values,
        (m) => m.wireName,
      ),
      type: Json.string(json, 'Type'),
      steps: Json.objects(
        details,
        'TravelSteps',
      ).map(TravelStep.fromJson).toList(growable: false),
      tolls: Json.objects(
        details,
        'Tolls',
      ).map(Toll.fromJson).toList(growable: false),
      incidents: Json.objects(
        details,
        'Incidents',
      ).map(RouteIncident.fromJson).toList(growable: false),
      departureTime: Json.dateTime(departure, 'Time'),
      arrivalTime: Json.dateTime(arrival, 'Time'),
      departurePosition: Json.latLng(
        Json.object(departure, 'Place'),
        'Position',
      ),
      arrivalPosition: Json.latLng(Json.object(arrival, 'Place'), 'Position'),
    );
  }

  /// Longitud del tramo en metros.
  final double distanceMeters;

  /// Cuánto se tarda, paradas incluidas.
  final Duration duration;

  /// Cuánto se tarda solo conduciendo, sin esperas ni paradas.
  ///
  /// La diferencia con [duration] es el tiempo perdido en ferris, aduanas o
  /// descansos obligatorios de conductor.
  final Duration? travelOnlyDuration;

  /// La línea que dibuja el tramo.
  final RouteGeometry geometry;

  /// Cómo se recorre.
  final TravelMode? travelMode;

  /// La clase de tramo: `Vehicle`, `Pedestrian`, `Ferry`.
  final String? type;

  /// Las indicaciones paso a paso, si se pidieron.
  final List<TravelStep> steps;

  /// Los peajes del tramo.
  final List<Toll> tolls;

  /// Las incidencias, si se pidieron.
  final List<RouteIncident> incidents;

  /// Cuándo se sale.
  final DateTime? departureTime;

  /// Cuándo se llega.
  final DateTime? arrivalTime;

  /// Desde dónde se sale.
  final LatLng? departurePosition;

  /// Adónde se llega.
  final LatLng? arrivalPosition;

  /// El coste total de los peajes del tramo, por moneda.
  ///
  /// Devuelve un mapa y no un número porque una ruta internacional cruza
  /// monedas, y sumarlas daría un número sin significado.
  Map<String, double> get tollCostByCurrency {
    final totals = <String, double>{};
    for (final toll in tolls) {
      final currency = toll.currency;
      final amount = toll.amount;
      if (currency == null || amount == null) continue;
      totals[currency] = (totals[currency] ?? 0) + amount;
    }
    return totals;
  }

  @override
  String toString() =>
      'RouteLeg(${(distanceMeters / 1000).toStringAsFixed(1)} km, '
      '${duration.inMinutes} min)';
}

/// Una ruta completa entre un origen y un destino.
@immutable
class Route {
  /// Crea la ruta.
  const Route({
    required this.distanceMeters,
    required this.duration,
    required this.legs,
    this.majorRoadLabels = const <String>[],
  });

  /// Lee la ruta de la respuesta del servicio.
  factory Route.fromJson(Map<String, dynamic> json) {
    final summary = Json.object(json, 'Summary');
    final legs = Json.objects(
      json,
      'Legs',
    ).map(RouteLeg.fromJson).toList(growable: false);

    // Si el resumen no vino, se compone sumando los tramos. Es preferible a
    // devolver cero: la suma es exacta, solo cuesta recorrer la lista.
    final distance =
        Json.number(summary, 'Distance') ??
        legs.fold<double>(0, (sum, leg) => sum + leg.distanceMeters);
    final seconds =
        Json.integer(summary, 'Duration') ??
        legs.fold<int>(0, (sum, leg) => sum + leg.duration.inSeconds);

    return Route(
      distanceMeters: distance,
      duration: Duration(seconds: seconds),
      legs: legs,
      majorRoadLabels: Json.objects(json, 'MajorRoadLabels')
          .map((r) => Json.string(Json.object(r, 'RoadName'), 'Value'))
          .whereType<String>()
          .toList(growable: false),
    );
  }

  /// Longitud total en metros.
  final double distanceMeters;

  /// Duración total.
  final Duration duration;

  /// Los tramos, en orden.
  final List<RouteLeg> legs;

  /// Las vías principales por las que pasa.
  ///
  /// Es lo que distingue dos alternativas para quien mira: «por la
  /// Panamericana» contra «por la Simón Bolívar» dice mucho más que «43 min»
  /// contra «45 min».
  final List<String> majorRoadLabels;

  /// Todos los puntos de la ruta, de todos los tramos, en un solo trazo.
  ///
  /// Es lo que se le pasa a una `Polyline` para pintarla de una vez. Se quita
  /// el primer punto de cada tramo salvo el primero, porque coincide con el
  /// último del anterior y duplicarlo deja un artefacto visible en los
  /// extremos de línea redondeados.
  List<LatLng> get points {
    final all = <LatLng>[];
    for (final leg in legs) {
      final points = leg.geometry.points;
      if (points.isEmpty) continue;
      all.addAll(all.isEmpty ? points : points.skip(1));
    }
    return all;
  }

  /// El rectángulo que encierra la ruta entera, o `null` si no hay geometría.
  LatLngBounds? get bounds {
    final all = points;
    return all.isEmpty ? null : LatLngBounds.fromPoints(all);
  }

  /// Todas las indicaciones, de todos los tramos, en orden.
  List<TravelStep> get steps => <TravelStep>[
    for (final leg in legs) ...leg.steps,
  ];

  /// Todos los peajes de la ruta.
  List<Toll> get tolls => <Toll>[for (final leg in legs) ...leg.tolls];

  /// El coste total de peajes, por moneda.
  Map<String, double> get tollCostByCurrency {
    final totals = <String, double>{};
    for (final leg in legs) {
      leg.tollCostByCurrency.forEach((currency, amount) {
        totals[currency] = (totals[currency] ?? 0) + amount;
      });
    }
    return totals;
  }

  /// La distancia en kilómetros, redondeada a un decimal.
  double get distanceKm => distanceMeters / 1000.0;

  @override
  String toString() =>
      'Route(${distanceKm.toStringAsFixed(1)} km, ${duration.inMinutes} min, '
      '${legs.length} tramo(s))';
}

/// La respuesta de `calculateRoutes`.
@immutable
class RouteResponse {
  /// Crea la respuesta.
  const RouteResponse({
    required this.routes,
    this.notices = const <String>[],
    this.pricingBucket,
  });

  /// Lee la respuesta del servicio.
  factory RouteResponse.fromJson(Map<String, dynamic> json) => RouteResponse(
    routes: Json.objects(
      json,
      'Routes',
    ).map(Route.fromJson).toList(growable: false),
    notices: Json.objects(json, 'Notices')
        .map((n) => Json.string(n, 'Code'))
        .whereType<String>()
        .toList(growable: false),
    pricingBucket: Json.string(json, 'PricingBucket'),
  );

  /// Las rutas, con la preferida primero.
  final List<Route> routes;

  /// Avisos del servicio: violaciones de restricciones, tramos estimados.
  ///
  /// Un aviso no impide usar la ruta, pero sí explica por qué es rara. El más
  /// habitual es que la ruta cruza una vía prohibida para las dimensiones del
  /// camión porque no había alternativa.
  final List<String> notices;

  /// El tramo de precio que aplicó AWS.
  final String? pricingBucket;

  /// La ruta preferida, o `null` si el servicio no encontró ninguna.
  Route? get best => routes.isEmpty ? null : routes.first;

  /// ¿Hubo alguna ruta?
  bool get isEmpty => routes.isEmpty;

  @override
  String toString() => 'RouteResponse(${routes.length} ruta(s))';
}

/// Una celda de la matriz origen-destino.
///
/// Antes esto era un `double` suelto con la distancia. La API v2 devuelve
/// además la duración y un posible error **por celda**, y descartarlos obliga
/// a pedir la matriz otra vez para saber cuánto se tarda — a precio de matriz
/// entera.
@immutable
class MatrixCell {
  /// Crea la celda.
  const MatrixCell({
    required this.distanceMeters,
    required this.duration,
    this.error,
  });

  /// Lee la celda de la respuesta del servicio.
  factory MatrixCell.fromJson(Map<String, dynamic> json) => MatrixCell(
    distanceMeters: Json.numberOrZero(json, 'Distance'),
    duration: Duration(seconds: Json.integer(json, 'Duration') ?? 0),
    error: Json.string(json, 'Error'),
  );

  /// Distancia por carretera en metros.
  final double distanceMeters;

  /// Tiempo de conducción.
  final Duration duration;

  /// Por qué no se pudo calcular este par, si no se pudo.
  final String? error;

  /// ¿Se calculó bien?
  ///
  /// Hay que comprobarlo antes de usar los números: una celda con error trae
  /// ceros, y un cero es un valor perfectamente creíble para «el más cercano».
  bool get isValid => error == null;

  @override
  String toString() => isValid
      ? 'MatrixCell(${distanceMeters.round()} m, ${duration.inSeconds} s)'
      : 'MatrixCell(error: $error)';
}

/// La respuesta de `calculateRouteMatrix`.
@immutable
class RouteMatrix {
  /// Crea la matriz.
  const RouteMatrix({
    required this.cells,
    this.errorCount = 0,
    this.pricingBucket,
  });

  /// Lee la matriz de la respuesta del servicio.
  factory RouteMatrix.fromJson(Map<String, dynamic> json) {
    final raw = json['RouteMatrix'];
    final rows = <List<MatrixCell>>[];
    if (raw is List) {
      for (final row in raw) {
        if (row is! List) continue;
        rows.add(
          row
              .whereType<Map<String, dynamic>>()
              .map(MatrixCell.fromJson)
              .toList(growable: false),
        );
      }
    }
    return RouteMatrix(
      cells: List<List<MatrixCell>>.unmodifiable(rows),
      errorCount: Json.integer(json, 'ErrorCount') ?? 0,
      pricingBucket: Json.string(json, 'PricingBucket'),
    );
  }

  /// Las celdas: `cells[origen][destino]`.
  final List<List<MatrixCell>> cells;

  /// Cuántas celdas no se pudieron calcular.
  final int errorCount;

  /// El tramo de precio que aplicó AWS.
  final String? pricingBucket;

  /// Cuántos orígenes tiene.
  int get originCount => cells.length;

  /// Cuántos destinos tiene.
  int get destinationCount => cells.isEmpty ? 0 : cells.first.length;

  /// La celda del par indicado.
  MatrixCell cell(int origin, int destination) => cells[origin][destination];

  /// El índice del destino más cercano a [origin] **por carretera**.
  ///
  /// Esta es la razón de ser de la matriz: la unidad más cercana en línea
  /// recta puede estar al otro lado de un río sin puente. Devuelve `null` si
  /// ninguna celda de esa fila se pudo calcular.
  int? nearestDestination(int origin, {bool byDuration = true}) {
    var bestIndex = -1;
    var bestValue = double.infinity;
    final row = cells[origin];
    for (var i = 0; i < row.length; i++) {
      final cell = row[i];
      if (!cell.isValid) continue;
      final value = byDuration
          ? cell.duration.inSeconds.toDouble()
          : cell.distanceMeters;
      if (value < bestValue) {
        bestValue = value;
        bestIndex = i;
      }
    }
    return bestIndex < 0 ? null : bestIndex;
  }

  @override
  String toString() =>
      'RouteMatrix(${originCount}x$destinationCount'
      '${errorCount > 0 ? ', $errorCount con error' : ''})';
}

/// Una isócrona: el polígono de lo alcanzable dentro de un umbral.
///
/// **Google no tiene esto.** Es la operación que responde «¿hasta dónde pudo
/// llegar en ocho minutos?» sin calcular mil rutas.
@immutable
class Isoline {
  /// Crea la isócrona.
  const Isoline({
    required this.polygons,
    this.distanceThresholdMeters,
    this.timeThreshold,
  });

  /// Lee la isócrona de la respuesta del servicio.
  ///
  /// Una isócrona puede traer **varios polígonos**: en una ciudad con un río
  /// sin puentes cerca, lo alcanzable son dos manchas separadas. Aplanar eso a
  /// un solo polígono uniría las dos orillas con una línea recta sobre el
  /// agua, dibujando como alcanzable justo lo que no lo es.
  factory Isoline.fromJson(Map<String, dynamic> json) {
    final polygons = <List<List<LatLng>>>[];

    for (final geometry in Json.objects(json, 'Geometries')) {
      final polygon = geometry['Polygon'];
      if (polygon is List) {
        final rings = <List<LatLng>>[];
        for (final ring in polygon) {
          if (ring is! List) continue;
          final points = <LatLng>[];
          for (final coordinate in ring) {
            if (coordinate is! List || coordinate.length < 2) continue;
            try {
              points.add(LatLng.fromLonLat(coordinate));
            } on FormatException {
              continue;
            } on ArgumentError {
              continue;
            }
          }
          if (points.isNotEmpty) rings.add(points);
        }
        if (rings.isNotEmpty) polygons.add(rings);
        continue;
      }

      final encodedRings = geometry['PolylinePolygon'];
      if (encodedRings is List) {
        final rings = <List<LatLng>>[];
        for (final encoded in encodedRings.whereType<String>()) {
          try {
            final points = decodeFlexiblePolyline(encoded);
            if (points.isNotEmpty) rings.add(points);
          } on FormatException {
            continue;
          }
        }
        if (rings.isNotEmpty) polygons.add(rings);
      }
    }

    final seconds = Json.integer(json, 'TimeThreshold');
    return Isoline(
      polygons: polygons,
      distanceThresholdMeters: Json.number(json, 'DistanceThreshold'),
      timeThreshold: seconds == null ? null : Duration(seconds: seconds),
    );
  }

  /// Los polígonos. Cada uno es una lista de anillos: el primero es el
  /// contorno y los siguientes, los agujeros.
  final List<List<List<LatLng>>> polygons;

  /// El umbral de distancia de esta isócrona, si se pidió por distancia.
  final double? distanceThresholdMeters;

  /// El umbral de tiempo, si se pidió por tiempo.
  final Duration? timeThreshold;

  /// El contorno del polígono principal, que es lo que se pinta casi siempre.
  List<LatLng> get outerRing => polygons.isEmpty || polygons.first.isEmpty
      ? const <LatLng>[]
      : polygons.first.first;

  /// Cuántos puntos tiene en total.
  ///
  /// Sirve para comprobar que `granularity` está haciendo su trabajo: una
  /// isócrona de treinta minutos sin límite de puntos trae varios miles y
  /// ahoga el mapa.
  int get pointCount => polygons.fold(
    0,
    (sum, polygon) => sum + polygon.fold<int>(0, (s, ring) => s + ring.length),
  );

  @override
  String toString() =>
      'Isoline(${polygons.length} polígono(s), '
      '$pointCount puntos, ${timeThreshold ?? distanceThresholdMeters})';
}

/// La respuesta de `calculateIsolines`.
@immutable
class IsolineResponse {
  /// Crea la respuesta.
  const IsolineResponse({
    required this.isolines,
    this.snappedOrigin,
    this.snappedDestination,
    this.departureTime,
    this.arrivalTime,
    this.pricingBucket,
  });

  /// Lee la respuesta del servicio.
  factory IsolineResponse.fromJson(Map<String, dynamic> json) =>
      IsolineResponse(
        isolines: Json.objects(
          json,
          'Isolines',
        ).map(Isoline.fromJson).toList(growable: false),
        snappedOrigin: Json.latLng(json, 'SnappedOrigin'),
        snappedDestination: Json.latLng(json, 'SnappedDestination'),
        departureTime: Json.dateTime(json, 'DepartureTime'),
        arrivalTime: Json.dateTime(json, 'ArrivalTime'),
        pricingBucket: Json.string(json, 'PricingBucket'),
      );

  /// Las isócronas, una por umbral pedido.
  final List<Isoline> isolines;

  /// El origen pegado a la carretera más cercana.
  ///
  /// Si está lejos del que se pidió, la posición de partida caía fuera de la
  /// red vial y todo el cálculo parte de otro sitio.
  final LatLng? snappedOrigin;

  /// El destino pegado a la carretera, en el modo de llegada.
  final LatLng? snappedDestination;

  /// La hora de salida usada en el cálculo.
  final DateTime? departureTime;

  /// La hora de llegada usada, en el modo inverso.
  final DateTime? arrivalTime;

  /// El tramo de precio que aplicó AWS.
  final String? pricingBucket;

  @override
  String toString() => 'IsolineResponse(${isolines.length} isócrona(s))';
}

/// Un punto de un rastro GPS, tal como se envía a `snapToRoads`.
///
/// El GT06 y la mayoría de los localizadores mandan rumbo, velocidad y hora
/// junto a la posición. **Darle solo la posición desperdicia la mitad de la
/// precisión** de la operación: con la velocidad y el rumbo, el servicio sabe
/// distinguir el carril de servicio de la autopista paralela.
@immutable
class TracePoint {
  /// Crea el punto de rastro.
  const TracePoint({
    required this.position,
    this.headingDegrees,
    this.speedKmh,
    this.timestamp,
  });

  /// Dónde dijo el GPS que estaba.
  final LatLng position;

  /// El rumbo en grados, 0 = norte.
  final double? headingDegrees;

  /// La velocidad **en kilómetros por hora**.
  ///
  /// Es la única magnitud de todo el paquete que no está en unidades del SI, y
  /// no por decisión propia: la API la pide así.
  final double? speedKmh;

  /// Cuándo se registró.
  final DateTime? timestamp;

  /// El punto en la forma que espera el servicio.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'Position': position.toLonLat(),
    if (headingDegrees != null) 'Heading': headingDegrees,
    if (speedKmh != null) 'Speed': speedKmh,
    if (timestamp != null) 'Timestamp': timestamp!.toUtc().toIso8601String(),
  };

  @override
  String toString() => 'TracePoint($position)';
}

/// Un punto de rastro ya pegado a la calle.
@immutable
class SnappedTracePoint {
  /// Crea el punto pegado.
  const SnappedTracePoint({
    required this.snappedPosition,
    this.originalPosition,
    this.confidence,
  });

  /// Lee el punto de la respuesta del servicio, o `null` si no trae posición.
  static SnappedTracePoint? fromJson(Map<String, dynamic> json) {
    final snapped = Json.latLng(json, 'SnappedPosition');
    if (snapped == null) return null;
    return SnappedTracePoint(
      snappedPosition: snapped,
      originalPosition: Json.latLng(json, 'OriginalPosition'),
      confidence: Json.number(json, 'Confidence'),
    );
  }

  /// La posición sobre la calle.
  final LatLng snappedPosition;

  /// La posición cruda que mandó el GPS.
  final LatLng? originalPosition;

  /// Lo seguro que está el servicio de este punto, entre 0 y 1.
  ///
  /// Es lo que permite **descartar lo dudoso** en lugar de dibujar una calle
  /// inventada. Con cobertura mala, un punto de confianza 0,2 pegado a una
  /// avenida paralela produce un rastro que parece correcto y no lo es.
  final double? confidence;

  /// Cuánto se movió el punto al pegarlo, en metros.
  ///
  /// Un desplazamiento grande con confianza baja es la señal clara de que
  /// `snapRadius` se quedó corto o de que ahí no había calle.
  double? get displacementMeters =>
      originalPosition?.distanceTo(snappedPosition);

  @override
  String toString() =>
      'SnappedTracePoint($snappedPosition'
      '${confidence == null ? '' : ', conf. $confidence'})';
}

/// La respuesta de `snapToRoads`.
@immutable
class SnapToRoadsResponse {
  /// Crea la respuesta.
  const SnapToRoadsResponse({
    required this.geometry,
    this.snappedPoints = const <SnappedTracePoint>[],
    this.notices = const <String>[],
    this.chunkCount = 1,
    this.pricingBucket,
  });

  /// Lee la respuesta del servicio.
  factory SnapToRoadsResponse.fromJson(Map<String, dynamic> json) =>
      SnapToRoadsResponse(
        geometry: RouteGeometry.fromJson(Json.object(json, 'SnappedGeometry')),
        snappedPoints: Json.objects(json, 'SnappedTracePoints')
            .map(SnappedTracePoint.fromJson)
            .whereType<SnappedTracePoint>()
            .toList(growable: false),
        notices: Json.objects(json, 'Notices')
            .map((n) => Json.string(n, 'Code'))
            .whereType<String>()
            .toList(growable: false),
        pricingBucket: Json.string(json, 'PricingBucket'),
      );

  /// La línea pegada a la calle, lista para pintar.
  final RouteGeometry geometry;

  /// Los puntos, uno por cada uno de los que se enviaron.
  final List<SnappedTracePoint> snappedPoints;

  /// Avisos del servicio.
  final List<String> notices;

  /// En cuántas peticiones se troceó el rastro.
  ///
  /// Es lo que de verdad se facturó: un histórico de 12 000 puntos son tres
  /// peticiones, aunque quien llamó escribiera una línea.
  final int chunkCount;

  /// El tramo de precio que aplicó AWS.
  final String? pricingBucket;

  /// Los puntos cuya confianza llega a [minimum].
  ///
  /// El complemento de esta lista no se debe pintar como recorrido: son
  /// puntos que el servicio pegó a una calle sin estar seguro.
  List<SnappedTracePoint> confidentPoints({double minimum = 0.5}) =>
      snappedPoints
          .where((p) => (p.confidence ?? 1.0) >= minimum)
          .toList(growable: false);

  @override
  String toString() =>
      'SnapToRoadsResponse(${snappedPoints.length} puntos, '
      '$chunkCount petición(es))';
}

/// Una parada que hay que visitar, para `optimizeWaypoints`.
@immutable
class OptimizationWaypoint {
  /// Crea la parada.
  const OptimizationWaypoint({
    required this.id,
    required this.position,
    this.serviceDuration,
    this.appointmentTime,
    this.before = const <String>[],
    this.headingDegrees,
    this.sideOfStreet,
  });

  /// El identificador con el que vuelve en el resultado.
  ///
  /// Es cómo se recupera el pedido, el cliente o la orden de trabajo que hay
  /// detrás: la respuesta trae los identificadores reordenados, no los objetos.
  final String id;

  /// Dónde está.
  final LatLng position;

  /// Cuánto se tarda en atenderla.
  ///
  /// Sin esto, la optimización planifica como si descargar fuera instantáneo, y
  /// una ruta de veinte entregas sale con dos horas menos de las que dura.
  final Duration? serviceDuration;

  /// La hora a la que hay una cita concertada.
  final DateTime? appointmentTime;

  /// Identificadores de paradas que tienen que visitarse **después** de esta.
  ///
  /// Es cómo se expresa «recoger antes de entregar» sin fijar el orden entero.
  final List<String> before;

  /// El rumbo con el que se llega, si importa.
  final double? headingDegrees;

  /// De qué lado de la calle está: `Left`, `Right`, `Any`.
  final String? sideOfStreet;

  /// La parada en la forma que espera el servicio.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'Id': id,
    'Position': position.toLonLat(),
    if (serviceDuration != null) 'ServiceDuration': serviceDuration!.inSeconds,
    if (appointmentTime != null)
      'AppointmentTime': appointmentTime!.toUtc().toIso8601String(),
    if (before.isNotEmpty) 'Before': before,
    if (headingDegrees != null) 'Heading': headingDegrees,
    if (sideOfStreet != null)
      'SideOfStreet': <String, dynamic>{'Position': position.toLonLat()},
  };
}

/// Una parada ya colocada en su sitio dentro del recorrido óptimo.
@immutable
class OptimizedWaypoint {
  /// Crea la parada optimizada.
  const OptimizedWaypoint({
    required this.id,
    this.position,
    this.arrivalTime,
    this.departureTime,
  });

  /// Lee la parada de la respuesta del servicio.
  factory OptimizedWaypoint.fromJson(Map<String, dynamic> json) =>
      OptimizedWaypoint(
        id: Json.string(json, 'Id') ?? '',
        position: Json.latLng(json, 'Position'),
        arrivalTime: Json.dateTime(json, 'ArrivalTime'),
        departureTime: Json.dateTime(json, 'DepartureTime'),
      );

  /// El identificador que se dio al enviarla.
  final String id;

  /// Dónde está.
  final LatLng? position;

  /// A qué hora se llega.
  final DateTime? arrivalTime;

  /// A qué hora se sale.
  final DateTime? departureTime;

  @override
  String toString() => 'OptimizedWaypoint($id)';
}

/// El enlace entre dos paradas consecutivas del recorrido óptimo.
@immutable
class WaypointConnection {
  /// Crea el enlace.
  const WaypointConnection({
    required this.fromId,
    required this.toId,
    required this.distanceMeters,
    required this.duration,
    this.restDuration,
    this.waitDuration,
  });

  /// Lee el enlace de la respuesta del servicio.
  factory WaypointConnection.fromJson(
    Map<String, dynamic> json,
  ) => WaypointConnection(
    fromId: Json.string(json, 'From') ?? '',
    toId: Json.string(json, 'To') ?? '',
    distanceMeters: Json.numberOrZero(json, 'Distance'),
    duration: Duration(seconds: Json.integer(json, 'Duration') ?? 0),
    restDuration: Duration(seconds: Json.integer(json, 'RestDuration') ?? 0),
    waitDuration: Duration(seconds: Json.integer(json, 'WaitDuration') ?? 0),
  );

  /// De qué parada sale.
  final String fromId;

  /// A qué parada llega.
  final String toId;

  /// Cuántos metros hay.
  final double distanceMeters;

  /// Cuánto se tarda conduciendo.
  final Duration duration;

  /// Descanso obligatorio del conductor en este trayecto.
  final Duration? restDuration;

  /// Espera hasta que abra la ventana horaria del destino.
  ///
  /// Una espera larga es la señal de que las citas están mal repartidas: el
  /// conductor llega antes de tiempo y se queda parado.
  final Duration? waitDuration;

  @override
  String toString() => 'WaypointConnection($fromId → $toId)';
}

/// La respuesta de `optimizeWaypoints`.
@immutable
class WaypointOptimizationResponse {
  /// Crea la respuesta.
  const WaypointOptimizationResponse({
    required this.waypoints,
    required this.distanceMeters,
    required this.duration,
    this.connections = const <WaypointConnection>[],
    this.impedingWaypointIds = const <String>[],
    this.pricingBucket,
  });

  /// Lee la respuesta del servicio.
  factory WaypointOptimizationResponse.fromJson(Map<String, dynamic> json) =>
      WaypointOptimizationResponse(
        waypoints: Json.objects(
          json,
          'OptimizedWaypoints',
        ).map(OptimizedWaypoint.fromJson).toList(growable: false),
        distanceMeters: Json.numberOrZero(json, 'Distance'),
        duration: Duration(seconds: Json.integer(json, 'Duration') ?? 0),
        connections: Json.objects(
          json,
          'Connections',
        ).map(WaypointConnection.fromJson).toList(growable: false),
        impedingWaypointIds: Json.objects(json, 'ImpedingWaypoints')
            .map((w) => Json.string(w, 'Id'))
            .whereType<String>()
            .toList(growable: false),
        pricingBucket: Json.string(json, 'PricingBucket'),
      );

  /// Las paradas **en el orden en que hay que visitarlas**.
  final List<OptimizedWaypoint> waypoints;

  /// Distancia total del recorrido.
  final double distanceMeters;

  /// Duración total, esperas y servicios incluidos.
  final Duration duration;

  /// Los enlaces entre paradas consecutivas.
  final List<WaypointConnection> connections;

  /// Las paradas que el servicio no pudo encajar.
  ///
  /// Normalmente son las que tienen una cita imposible de cumplir. Vienen
  /// separadas y no mezcladas en el orden porque hay que enseñárselas a
  /// alguien: son las que hay que reprogramar.
  final List<String> impedingWaypointIds;

  /// El tramo de precio que aplicó AWS.
  final String? pricingBucket;

  /// El orden de los identificadores, listo para reordenar tu propia lista.
  List<String> get orderedIds =>
      waypoints.map((w) => w.id).toList(growable: false);

  @override
  String toString() =>
      'WaypointOptimizationResponse('
      '${waypoints.length} paradas, ${duration.inMinutes} min)';
}
