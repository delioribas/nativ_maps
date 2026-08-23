// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:compass_maps/src/client/budget.dart';
import 'package:compass_maps/src/client/cache.dart';
import 'package:compass_maps/src/client/transport.dart';
import 'package:compass_maps/src/core/enums.dart';
import 'package:compass_maps/src/core/lat_lng.dart';
import 'package:compass_maps/src/routes/models.dart';
import 'package:compass_maps/src/routes/options.dart';
import 'package:meta/meta.dart';

/// Las **cinco** operaciones de Amazon Location Routes v2.
///
/// | Método | Endpoint | Para qué |
/// |---|---|---|
/// | [calculateRoutes] | `POST /v2/routes` | ruta entre dos puntos |
/// | [calculateRouteMatrix] | `POST /v2/route-matrix` | quién está más cerca **por carretera** |
/// | [calculateIsolines] | `POST /v2/isolines` | **área alcanzable en X minutos** |
/// | [snapToRoads] | `POST /v2/snap-to-roads` | **pegar el rastro GPS a la calle real** |
/// | [optimizeWaypoints] | `POST /v2/optimize-waypoints` | orden óptimo de paradas |
///
/// Las dos marcadas en negrita **no existen en Google Maps**. Son, junto con
/// los peajes de [Toll], lo que este paquete da y ningún envoltorio de Google
/// puede dar.
///
/// ## Los límites duros están comprobados aquí
///
/// Las tres operaciones con límite lo comprueban **antes de enviar**, porque
/// la alternativa es descubrirlo con un `400` después de haber pagado el viaje
/// de ida:
///
/// - matriz sin acotar zona: 15 orígenes, 100 destinos, 100 celdas;
/// - isócronas: 5 umbrales;
/// - `snapToRoads`: 5 000 puntos — y este **no falla, trocea**.
class RoutesClient {
  /// Construye el cliente. Uso interno: llega ya montado en `CompassMaps`.
  @internal
  RoutesClient({required AlsTransport transport, this.language})
    : _transport = transport;

  final AlsTransport _transport;

  /// Idioma de las indicaciones, en BCP 47.
  final String? language;

  static const AlsService _service = AlsService.routes;

  /// Las rutas son las peticiones que más cuestan, y antes no se cacheaban.
  ///
  /// Diez minutos es suficiente para que abrir y cerrar una ficha no las pague
  /// dos veces, y poco para que la información de tráfico siga siendo
  /// relevante.
  final LruCache<String, RouteResponse> _routeCache =
      LruCache<String, RouteResponse>(60, ttl: const Duration(minutes: 10));

  // ─── Límites del servicio ─────────────────────────────────────────────

  /// Orígenes máximos de una matriz sin acotar zona.
  static const int maxUnboundedMatrixOrigins = 15;

  /// Destinos máximos de una matriz sin acotar zona.
  static const int maxUnboundedMatrixDestinations = 100;

  /// Celdas máximas de una matriz sin acotar zona.
  static const int maxUnboundedMatrixCells = 100;

  /// Umbrales máximos por petición de isócronas. **Se cobra por umbral.**
  static const int maxIsolineThresholds = 5;

  /// Puntos máximos por petición de `snapToRoads`.
  static const int maxTracePointsPerRequest = 5000;

  // ─── 1 · CalculateRoutes ──────────────────────────────────────────────

  /// Calcula una ruta. `POST /v2/routes`.
  ///
  /// ```dart
  /// final respuesta = await routes.calculateRoutes(
  ///   origin: posicionActual,
  ///   destination: destino,
  ///   travelMode: TravelMode.scooter,
  ///   legAdditionalFeatures: const [RouteFeature.tolls, RouteFeature.summary],
  /// );
  /// final ruta = respuesta.best!;
  /// mapa.addPolyline(Polyline(polylineId: 'ruta', points: ruta.points));
  /// ```
  ///
  /// La geometría se pide por defecto en [GeometryFormat.simple]: pesa más por
  /// la red pero no hay que decodificar nada. Para un histórico largo o una
  /// conexión mala, [GeometryFormat.flexiblePolyline] baja el tamaño alrededor
  /// de un 80 % y se decodifica solo.
  ///
  /// [departureTime] y [arrivalTime] son excluyentes. Sin ninguno de los dos
  /// se envía `DepartNow`, que usa el tráfico de este momento.
  ///
  /// **Distancias en metros y duraciones en segundos.** v2 no tiene parámetro
  /// de unidad; enviar `DistanceUnit` —que existía en v0— provoca un `400`.
  Future<RouteResponse> calculateRoutes({
    required LatLng origin,
    required LatLng destination,
    List<LatLng> waypoints = const <LatLng>[],
    TravelMode travelMode = TravelMode.car,
    TravelModeOptions? travelModeOptions,
    DateTime? departureTime,
    DateTime? arrivalTime,
    RouteOptimization optimizeFor = RouteOptimization.fastestRoute,
    RouteAvoidance? avoid,
    TrafficUsage traffic = TrafficUsage.useTrafficData,
    GeometryFormat geometryFormat = GeometryFormat.simple,
    TravelStepType travelStepType = TravelStepType.turnByTurn,
    List<RouteFeature> legAdditionalFeatures = const <RouteFeature>[],
    int maxAlternatives = 0,
    String? language,
    bool useCache = true,
  }) async {
    if (departureTime != null && arrivalTime != null) {
      throw ArgumentError(
        'departureTime y arrivalTime son excluyentes: la API responde 400 si '
        'llegan los dos.',
      );
    }
    if (maxAlternatives < 0 || maxAlternatives > 6) {
      throw ArgumentError.value(
        maxAlternatives,
        'maxAlternatives',
        'admite entre 0 y 6',
      );
    }

    final cacheKey = _key(<Object?>[
      'route',
      origin,
      destination,
      waypoints,
      travelMode.wireName,
      optimizeFor.wireName,
      traffic.wireName,
      geometryFormat.wireName,
      travelStepType.wireName,
      legAdditionalFeatures.map((f) => f.wireName).join(','),
      maxAlternatives,
      departureTime?.toIso8601String(),
      arrivalTime?.toIso8601String(),
      avoid?.toJson(),
      travelModeOptions?.toJson(travelMode),
    ]);
    // Con hora de salida «ahora» la caché sí sirve —dos aperturas seguidas de
    // la misma ficha—, pero con una hora fija no tiene sentido reutilizar un
    // resultado calculado con otro tráfico.
    if (useCache) {
      final hit = _routeCache.get(cacheKey);
      if (hit != null) return hit;
    }

    final json = await _transport.postJson(
      operation: 'CalculateRoutes',
      service: _service,
      path: '/v2/routes',
      body: <String, dynamic>{
        'Origin': origin.toLonLat(),
        'Destination': destination.toLonLat(),
        if (waypoints.isNotEmpty)
          'Waypoints': waypoints
              .map((w) => <String, dynamic>{'Position': w.toLonLat()})
              .toList(),
        'TravelMode': travelMode.wireName,
        if (travelModeOptions != null)
          'TravelModeOptions': travelModeOptions.toJson(travelMode),
        'LegGeometryFormat': geometryFormat.wireName,
        'OptimizeRoutingFor': optimizeFor.wireName,
        'TravelStepType': travelStepType.wireName,
        'MaxAlternatives': maxAlternatives,
        'Traffic': <String, dynamic>{'Usage': traffic.wireName},
        if (avoid != null && !avoid.isEmpty) 'Avoid': avoid.toJson(),
        if (legAdditionalFeatures.isNotEmpty)
          'LegAdditionalFeatures': legAdditionalFeatures
              .map((f) => f.wireName)
              .toList(),
        if (departureTime != null)
          'DepartureTime': departureTime.toUtc().toIso8601String()
        else if (arrivalTime != null)
          'ArrivalTime': arrivalTime.toUtc().toIso8601String()
        else
          'DepartNow': true,
        if ((language ?? this.language) != null)
          'InstructionsMeasurementSystem': 'Metric',
      },
    );

    final response = RouteResponse.fromJson(json);
    if (useCache) _routeCache.set(cacheKey, response);
    return response;
  }

  // ─── 2 · CalculateRouteMatrix ─────────────────────────────────────────

  /// Distancias y tiempos entre todos los pares. `POST /v2/route-matrix`.
  ///
  /// Responde a «cuál de mis diez unidades llega antes» **por carretera**, que
  /// es una pregunta distinta de «cuál está más cerca en línea recta»: la más
  /// cercana en línea recta puede estar al otro lado de un río sin puente.
  ///
  /// ## El coste, que es lo que sorprende
  ///
  /// **Se factura por par, no por petición.** Una matriz de 10×10 son cien
  /// cálculos de ruta y cien unidades de presupuesto. Es la operación donde
  /// más se separan lo que parece —una llamada— y lo que cuesta.
  ///
  /// El patrón barato es filtrar antes: ordenar por [LatLng.distanceTo], que
  /// es gratis, quedarse con los tres o cuatro primeros y pedir la matriz solo
  /// de esos.
  ///
  /// ## El límite
  ///
  /// Sin [routingBoundary], AWS permite 15 orígenes, 100 destinos y 100 celdas.
  /// Se comprueba antes de enviar y se lanza [ArgumentError] con el cálculo
  /// hecho, en vez de dejar que el servicio conteste `400`.
  Future<RouteMatrix> calculateRouteMatrix({
    required List<LatLng> origins,
    required List<LatLng> destinations,
    TravelMode travelMode = TravelMode.car,
    TravelModeOptions? travelModeOptions,
    LatLngBounds? routingBoundary,
    DateTime? departureTime,
    RouteAvoidance? avoid,
    TrafficUsage traffic = TrafficUsage.useTrafficData,
    RouteOptimization optimizeFor = RouteOptimization.fastestRoute,
  }) async {
    if (origins.isEmpty || destinations.isEmpty) {
      throw ArgumentError(
        'la matriz necesita al menos un origen y un destino.',
      );
    }
    if (routingBoundary == null) {
      final cells = origins.length * destinations.length;
      if (origins.length > maxUnboundedMatrixOrigins ||
          destinations.length > maxUnboundedMatrixDestinations ||
          cells > maxUnboundedMatrixCells) {
        throw ArgumentError(
          'sin acotar la zona el máximo es $maxUnboundedMatrixOrigins '
          'orígenes, $maxUnboundedMatrixDestinations destinos y '
          '$maxUnboundedMatrixCells celdas; se pidieron ${origins.length}×'
          '${destinations.length} = $cells celdas. Pasa `routingBoundary` '
          'para subir el límite, o filtra los candidatos por distancia en '
          'línea recta antes de llamar — eso es gratis y esto cuesta $cells '
          'unidades.',
        );
      }
    }

    final json = await _transport.postJson(
      operation: 'CalculateRouteMatrix',
      service: _service,
      path: '/v2/route-matrix',
      billingUnits: BillingUnits.routeMatrix(
        origins.length,
        destinations.length,
      ),
      body: <String, dynamic>{
        'Origins': origins
            .map((o) => <String, dynamic>{'Position': o.toLonLat()})
            .toList(),
        'Destinations': destinations
            .map((d) => <String, dynamic>{'Position': d.toLonLat()})
            .toList(),
        'TravelMode': travelMode.wireName,
        if (travelModeOptions != null)
          'TravelModeOptions': travelModeOptions.toJson(travelMode),
        'OptimizeRoutingFor': optimizeFor.wireName,
        'Traffic': <String, dynamic>{'Usage': traffic.wireName},
        if (avoid != null && !avoid.isEmpty) 'Avoid': avoid.toJson(),
        if (departureTime != null)
          'DepartureTime': departureTime.toUtc().toIso8601String(),
        'RoutingBoundary': routingBoundary == null
            ? <String, dynamic>{'Unbounded': true}
            : <String, dynamic>{
                'Geometry': <String, dynamic>{
                  'BoundingBox': routingBoundary.toBbox(),
                },
              },
      },
    );

    final matrix = RouteMatrix.fromJson(json);
    if (matrix.originCount != origins.length ||
        matrix.cells.any((row) => row.length != destinations.length)) {
      throw AlsParseExceptionForMatrix(
        expectedOrigins: origins.length,
        expectedDestinations: destinations.length,
        actualOrigins: matrix.originCount,
        actualDestinations: matrix.destinationCount,
      );
    }
    return matrix;
  }

  // ─── 3 · CalculateIsolines ────────────────────────────────────────────

  /// El área alcanzable dentro de un umbral. `POST /v2/isolines`.
  ///
  /// **Google no tiene esto.** Responde a «¿hasta dónde pudo llegar en ocho
  /// minutos?» sin calcular mil rutas, y funciona en los dos sentidos:
  ///
  /// ```dart
  /// // Hacia fuera: ¿hasta dónde pudo llegar en 8 minutos?
  /// final zona = await routes.calculateIsolines(
  ///   origin: ultimaPosicion,
  ///   thresholds: Thresholds.time([const Duration(minutes: 8)]),
  ///   travelMode: TravelMode.scooter,
  ///   granularity: const IsolineGranularity(maxPoints: 300),
  /// );
  ///
  /// // Hacia dentro: ¿quién llega AQUÍ en 10 minutos?
  /// final alcance = await routes.calculateIsolines(
  ///   destination: posicionVehiculo,
  ///   arrivalTime: DateTime.now().add(const Duration(minutes: 10)),
  ///   thresholds: Thresholds.time([const Duration(minutes: 10)]),
  /// );
  /// ```
  ///
  /// ## Dos cosas que hay que saber
  ///
  /// **Se cobra por umbral**, hasta cinco. Pedir cinco en una llamada es más
  /// cómodo que cinco llamadas, pero cuesta exactamente lo mismo: cinco
  /// unidades.
  ///
  /// **[granularity] es obligatoria en la práctica.** Sin `maxPoints`, el
  /// polígono de treinta minutos trae varios miles de vértices y ahoga el
  /// mapa: el dispositivo se queda dibujando y la interfaz deja de responder.
  /// Trescientos puntos son de sobra para que se vea bien.
  ///
  /// [origin] y [destination] son excluyentes, y hay que dar uno de los dos.
  Future<IsolineResponse> calculateIsolines({
    LatLng? origin,
    LatLng? destination,
    required Thresholds thresholds,
    TravelMode travelMode = TravelMode.car,
    TravelModeOptions? travelModeOptions,
    IsolineGranularity granularity = const IsolineGranularity(maxPoints: 300),
    DateTime? departureTime,
    DateTime? arrivalTime,
    RouteAvoidance? avoid,
    TrafficUsage traffic = TrafficUsage.useTrafficData,
    RouteOptimization optimizeFor = RouteOptimization.fastestRoute,
    GeometryFormat geometryFormat = GeometryFormat.simple,
  }) async {
    if ((origin == null) == (destination == null)) {
      throw ArgumentError(
        'calculateIsolines necesita origin O destination, exactamente uno. '
        'Con origin calcula lo alcanzable DESDE ese punto; con destination, '
        'lo que puede llegar HASTA él.',
      );
    }
    final count = thresholds.count;
    if (count == 0) {
      throw ArgumentError('hay que pedir al menos un umbral.');
    }
    if (count > maxIsolineThresholds) {
      throw ArgumentError(
        'se pidieron $count umbrales y el máximo es $maxIsolineThresholds. '
        'Y ojo: se cobra por umbral, así que $count umbrales son $count '
        'unidades facturables, no una.',
      );
    }

    final json = await _transport.postJson(
      operation: 'CalculateIsolines',
      service: _service,
      path: '/v2/isolines',
      billingUnits: BillingUnits.isolines(count),
      body: <String, dynamic>{
        if (origin != null) 'Origin': origin.toLonLat(),
        if (destination != null) 'Destination': destination.toLonLat(),
        'Thresholds': thresholds.toJson(),
        'TravelMode': travelMode.wireName,
        if (travelModeOptions != null)
          'TravelModeOptions': travelModeOptions.toJson(travelMode),
        'IsolineGranularity': granularity.toJson(),
        'IsolineGeometryFormat': geometryFormat.wireName,
        'OptimizeRoutingFor': optimizeFor.wireName,
        'Traffic': <String, dynamic>{'Usage': traffic.wireName},
        if (avoid != null && !avoid.isEmpty) 'Avoid': avoid.toJson(),
        if (departureTime != null)
          'DepartureTime': departureTime.toUtc().toIso8601String(),
        if (arrivalTime != null)
          'ArrivalTime': arrivalTime.toUtc().toIso8601String(),
      },
    );
    return IsolineResponse.fromJson(json);
  }

  // ─── 4 · SnapToRoads ──────────────────────────────────────────────────

  /// Pega un rastro GPS a la calle real. `POST /v2/snap-to-roads`.
  ///
  /// **Google no tiene esto.** Es lo que convierte una nube de puntos que
  /// zigzaguea sobre las aceras en un recorrido que sigue la calzada, y es la
  /// diferencia entre un histórico que se puede enseñar a un cliente y uno que
  /// parece un error.
  ///
  /// ## El troceado, que es la parte importante
  ///
  /// La API admite entre 2 y **5 000** puntos por petición. Un histórico de un
  /// día se pasa de largo. Este método **trocea y cose** en vez de fallar:
  ///
  /// - parte el rastro en trozos de [maxTracePointsPerRequest];
  /// - **solapa [overlapPoints] puntos** entre trozos consecutivos, para que
  ///   el servicio tenga contexto en la costura y no empiece cada trozo
  ///   pegando el primer punto a la calle equivocada;
  /// - quita el solape al unir, para que la línea no vuelva sobre sí misma.
  ///
  /// Cada trozo es una petición facturada: 12 000 puntos son tres unidades.
  /// [SnapToRoadsResponse.chunkCount] dice cuántas fueron de verdad.
  ///
  /// ## Los datos que el localizador ya manda
  ///
  /// [TracePoint] acepta rumbo, velocidad y hora, y **el GT06 manda los tres**.
  /// Darle solo posiciones desperdicia la mitad de la precisión: con la
  /// velocidad, el servicio distingue el carril de servicio de la autopista
  /// paralela.
  ///
  /// [snapRadiusMeters] son 300 por defecto y hasta 10 000. Con cobertura
  /// urbana mala, 300 se queda corto; alrededor de 500 va mejor para un GT06
  /// en ciudad.
  Future<SnapToRoadsResponse> snapToRoads({
    required List<TracePoint> tracePoints,
    double? snapRadiusMeters,
    TravelMode travelMode = TravelMode.car,
    TravelModeOptions? travelModeOptions,
    GeometryFormat geometryFormat = GeometryFormat.simple,
    int overlapPoints = 10,
  }) async {
    if (tracePoints.length < 2) {
      throw ArgumentError.value(
        tracePoints.length,
        'tracePoints',
        'hacen falta al menos 2 puntos',
      );
    }
    if (snapRadiusMeters != null &&
        (snapRadiusMeters < 0 || snapRadiusMeters > 10000)) {
      throw ArgumentError.value(
        snapRadiusMeters,
        'snapRadiusMeters',
        'admite entre 0 y 10000',
      );
    }
    if (overlapPoints < 0 || overlapPoints >= maxTracePointsPerRequest) {
      throw ArgumentError.value(
        overlapPoints,
        'overlapPoints',
        'debe estar entre 0 y $maxTracePointsPerRequest',
      );
    }

    final chunks = _chunkTrace(tracePoints, overlapPoints);

    Future<SnapToRoadsResponse> sendChunk(List<TracePoint> chunk) async {
      final json = await _transport.postJson(
        operation: 'SnapToRoads',
        service: _service,
        path: '/v2/snap-to-roads',
        body: <String, dynamic>{
          'TracePoints': chunk.map((p) => p.toJson()).toList(),
          'TravelMode': travelMode.wireName,
          if (travelModeOptions != null)
            'TravelModeOptions': travelModeOptions.toJson(travelMode),
          'SnappedGeometryFormat': geometryFormat.wireName,
          if (snapRadiusMeters != null) 'SnapRadius': snapRadiusMeters.round(),
        },
      );
      return SnapToRoadsResponse.fromJson(json);
    }

    if (chunks.length == 1) {
      final single = await sendChunk(chunks.first);
      return SnapToRoadsResponse(
        geometry: single.geometry,
        snappedPoints: single.snappedPoints,
        notices: single.notices,
        pricingBucket: single.pricingBucket,
      );
    }

    // En serie y no en paralelo: lanzar veinte peticiones a la vez es la forma
    // más rápida de encontrarse un 429, y entonces se pierde el rastro entero
    // por ir con prisa.
    final points = <LatLng>[];
    final snapped = <SnappedTracePoint>[];
    final notices = <String>[];
    String? pricingBucket;

    for (var i = 0; i < chunks.length; i++) {
      final response = await sendChunk(chunks[i]);
      // El solape se descuenta al coser: sus puntos ya vinieron en el trozo
      // anterior, y repetirlos dibuja una línea que vuelve sobre sí misma.
      final skip = i == 0 ? 0 : overlapPoints;
      points.addAll(response.geometry.points.skip(skip));
      snapped.addAll(response.snappedPoints.skip(skip));
      notices.addAll(response.notices);
      pricingBucket ??= response.pricingBucket;
    }

    return SnapToRoadsResponse(
      geometry: RouteGeometry(points),
      snappedPoints: snapped,
      notices: notices.toSet().toList(growable: false),
      chunkCount: chunks.length,
      pricingBucket: pricingBucket,
    );
  }

  /// Parte el rastro en trozos con solape.
  @visibleForTesting
  static List<List<TracePoint>> chunkTraceForTesting(
    List<TracePoint> points,
    int overlap,
  ) => _chunkTrace(points, overlap);

  static List<List<TracePoint>> _chunkTrace(
    List<TracePoint> points,
    int overlap,
  ) {
    if (points.length <= maxTracePointsPerRequest) {
      return <List<TracePoint>>[points];
    }
    final chunks = <List<TracePoint>>[];
    final step = maxTracePointsPerRequest - overlap;
    var start = 0;
    while (start < points.length) {
      final end = (start + maxTracePointsPerRequest).clamp(0, points.length);
      chunks.add(points.sublist(start, end));
      if (end >= points.length) break;
      start += step;
    }
    return chunks;
  }

  // ─── 5 · OptimizeWaypoints ────────────────────────────────────────────

  /// Reordena las paradas para minimizar el recorrido.
  /// `POST /v2/optimize-waypoints`.
  ///
  /// **Google no tiene esto** como operación propia. Resuelve el problema del
  /// viajante con ventanas horarias, tiempos de servicio y descansos
  /// obligatorios del conductor, que es lo que una hoja de reparto necesita de
  /// verdad.
  ///
  /// El resultado devuelve **identificadores**, no objetos: en
  /// [WaypointOptimizationResponse.orderedIds] está el orden con el que
  /// reordenar tu propia lista de pedidos.
  ///
  /// [OptimizationWaypoint.serviceDuration] es el campo que más se olvida y el
  /// que más cambia el resultado: sin él, la optimización planifica como si
  /// descargar fuera instantáneo, y una ruta de veinte entregas sale con dos
  /// horas menos de las que dura.
  Future<WaypointOptimizationResponse> optimizeWaypoints({
    required LatLng origin,
    required List<OptimizationWaypoint> waypoints,
    LatLng? destination,
    TravelMode travelMode = TravelMode.car,
    TravelModeOptions? travelModeOptions,
    DateTime? departureTime,
    WaypointOptimization optimizeFor = WaypointOptimization.fastestRoute,
    RouteAvoidance? avoid,
    TrafficUsage traffic = TrafficUsage.useTrafficData,
    DriverOptions? driver,
  }) async {
    if (waypoints.isEmpty) {
      throw ArgumentError('hay que dar al menos una parada que optimizar.');
    }
    final ids = waypoints.map((w) => w.id).toSet();
    if (ids.length != waypoints.length) {
      throw ArgumentError(
        'los identificadores de parada se repiten. La respuesta los devuelve '
        'reordenados y sin nada más, así que dos paradas con el mismo '
        'identificador son indistinguibles al reconstruir la lista.',
      );
    }

    final json = await _transport.postJson(
      operation: 'OptimizeWaypoints',
      service: _service,
      path: '/v2/optimize-waypoints',
      body: <String, dynamic>{
        'Origin': origin.toLonLat(),
        if (destination != null) 'Destination': destination.toLonLat(),
        'Waypoints': waypoints.map((w) => w.toJson()).toList(),
        'TravelMode': travelMode.wireName,
        if (travelModeOptions != null)
          'TravelModeOptions': travelModeOptions.toJson(travelMode),
        'OptimizeSequencingFor': optimizeFor.wireName,
        'Traffic': <String, dynamic>{'Usage': traffic.wireName},
        if (avoid != null && !avoid.isEmpty) 'Avoid': avoid.toJson(),
        if (driver != null) 'Driver': driver.toJson(),
        if (departureTime != null)
          'DepartureTime': departureTime.toUtc().toIso8601String(),
      },
    );
    return WaypointOptimizationResponse.fromJson(json);
  }

  // ─── Auxiliares ───────────────────────────────────────────────────────

  /// Vacía la caché de rutas.
  void clearCache() => _routeCache.clear();

  static String _key(List<Object?> parts) => parts.join('|');
}

/// La matriz llegó con unas dimensiones distintas de las que se pidieron.
///
/// Tiene tipo propio porque la acción es distinta de la de cualquier otro
/// fallo de lectura: aquí la respuesta es sintácticamente válida y los índices
/// no significan lo que se cree. Usarla igual daría el vehículo equivocado
/// como «el más cercano», sin ningún síntoma visible.
class AlsParseExceptionForMatrix implements Exception {
  /// Crea la excepción con las dimensiones esperadas y las recibidas.
  const AlsParseExceptionForMatrix({
    required this.expectedOrigins,
    required this.expectedDestinations,
    required this.actualOrigins,
    required this.actualDestinations,
  });

  /// Cuántos orígenes se enviaron.
  final int expectedOrigins;

  /// Cuántos destinos se enviaron.
  final int expectedDestinations;

  /// Cuántas filas trajo la respuesta.
  final int actualOrigins;

  /// Cuántas columnas trajo la respuesta.
  final int actualDestinations;

  @override
  String toString() =>
      'AlsParseExceptionForMatrix: se pidió una matriz de '
      '${expectedOrigins}x$expectedDestinations y llegó de '
      '${actualOrigins}x$actualDestinations. Los índices no corresponden con '
      'los orígenes y destinos enviados, así que usarla daría el par '
      'equivocado sin ningún síntoma visible.';
}
