// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:compass_maps/src/client/cache.dart';
import 'package:compass_maps/src/client/transport.dart';
import 'package:compass_maps/src/core/enums.dart';
import 'package:compass_maps/src/core/lat_lng.dart';
import 'package:compass_maps/src/places/options.dart';
import 'package:compass_maps/src/places/place.dart';
import 'package:compass_maps/src/places/results.dart';
import 'package:meta/meta.dart';

/// Las **siete** operaciones de Amazon Location Places v2.
///
/// | Método | Endpoint | Para qué |
/// |---|---|---|
/// | [autocomplete] | `POST /v2/autocomplete` | escribir una dirección |
/// | [searchText] | `POST /v2/search-text` | buscar un lugar por nombre |
/// | [reverseGeocode] | `POST /v2/reverse-geocode` | de coordenada a dirección |
/// | [getPlace] | `GET /v2/place/{id}` | la ficha completa |
/// | [geocode] | `POST /v2/geocode` | de dirección a coordenada, con precisión |
/// | [searchNearby] | `POST /v2/search-nearby` | qué hay cerca de un punto |
/// | [suggest] | `POST /v2/suggest` | sugerencia más barata que autocomplete |
///
/// No se instancia a mano: se obtiene de `CompassMaps.places`.
///
/// ## Todas cuestan dinero
///
/// Cada llamada es una petición facturada. Las que se disparan al teclear
/// —[autocomplete] y [suggest]— son las que más se descontrolan, y por eso
/// llevan caché con caducidad: borrar una letra y volver a escribirla no paga
/// dos veces.
///
/// El antirrebote, en cambio, **no** está aquí: depende del ritmo de escritura
/// y del hilo de la interfaz, y meterlo en el cliente obligaría a que el
/// núcleo supiera de temporizadores de interfaz. Va en el widget de búsqueda
/// de `compass_maps_flutter`.
class PlacesClient {
  /// Construye el cliente. Uso interno: llega ya montado en `CompassMaps`.
  @internal
  PlacesClient({
    required AlsTransport transport,
    required this.intendedUse,
    this.language,
    this.politicalView,
  }) : _transport = transport;

  final AlsTransport _transport;

  /// Si los resultados se van a guardar. Ver [IntendedUse].
  final IntendedUse intendedUse;

  /// Idioma de los resultados, en BCP 47. Para Ecuador, `es`.
  final String? language;

  /// Punto de vista político para las fronteras en disputa, en ISO 3166.
  final String? politicalView;

  static const AlsService _service = AlsService.places;

  final LruCache<String, List<AutocompleteSuggestion>> _autocompleteCache =
      LruCache<String, List<AutocompleteSuggestion>>(
        200,
        ttl: const Duration(minutes: 10),
      );
  final LruCache<String, PlaceSearchResponse> _searchCache =
      LruCache<String, PlaceSearchResponse>(
        200,
        ttl: const Duration(minutes: 30),
      );
  final LruCache<String, Place> _placeCache = LruCache<String, Place>(
    400,
    ttl: const Duration(hours: 6),
  );

  // ─── 1 · Autocomplete ─────────────────────────────────────────────────

  /// Sugerencias mientras se escribe. `POST /v2/autocomplete`.
  ///
  /// Es la operación más barata de las que producen sugerencias, y a cambio
  /// **no devuelve coordenadas**: para tenerlas hay que llamar a [getPlace]
  /// con el `placeId` de la que el usuario elija. Ese es el diseño correcto de
  /// una barra de búsqueda — escribir es barato, elegir cuesta una vez.
  ///
  /// ```dart
  /// final sugerencias = await places.autocomplete(
  ///   query: texto,
  ///   biasPosition: posicionActual,
  ///   filter: const SearchFilter(includeCountries: ['ECU']),
  /// );
  /// // y solo cuando el usuario toca una:
  /// final lugar = await places.getPlace(sugerencias[i].placeId!);
  /// ```
  ///
  /// [biasPosition] y [filter] **no** son excluyentes: el sesgo ordena, el
  /// filtro descarta. Lo que sí es excluyente es rellenar a la vez
  /// `boundingBox` y `circle` dentro de [filter]; se comprueba antes de enviar.
  ///
  /// [maxResults] admite de 1 a 20.
  ///
  /// El uso previsto de esta operación es siempre [IntendedUse.singleUse], y
  /// no es una decisión de este paquete: la API rechaza `Storage` aquí. Una
  /// sugerencia a medio escribir no se puede guardar.
  Future<List<AutocompleteSuggestion>> autocomplete({
    required String query,
    LatLng? biasPosition,
    SearchFilter? filter,
    int maxResults = 5,
    PostalCodeMode? postalCodeMode,
    List<PlaceFeature> additionalFeatures = const <PlaceFeature>[],
    String? language,
    bool useCache = true,
  }) async {
    if (query.trim().isEmpty) return const <AutocompleteSuggestion>[];
    _checkFilter(filter, 'autocomplete');
    final limit = _checkResults(maxResults, 1, 20, 'autocomplete');

    final cacheKey = _key(<Object?>[
      'auto',
      query,
      biasPosition,
      filter?.toJson(),
      limit,
      postalCodeMode?.wireName,
      language ?? this.language,
    ]);
    if (useCache) {
      final hit = _autocompleteCache.get(cacheKey);
      if (hit != null) return hit;
    }

    final json = await _transport.postJson(
      operation: 'Autocomplete',
      service: _service,
      path: '/v2/autocomplete',
      body: <String, dynamic>{
        'QueryText': query,
        'MaxResults': limit,
        if (biasPosition != null) 'BiasPosition': biasPosition.toLonLat(),
        if (filter != null && !filter.isEmpty) 'Filter': filter.toJson(),
        'PostalCodeMode': ?postalCodeMode?.wireName,
        if (additionalFeatures.isNotEmpty)
          'AdditionalFeatures': additionalFeatures
              .map((f) => f.wireName)
              .toList(),
        ..._localeFields(language),
        // Fijo a propósito: la API rechaza `Storage` en esta operación.
        'IntendedUse': IntendedUse.singleUse.wireName,
      },
    );

    final results = _items(json)
        .map(AutocompleteSuggestion.fromJson)
        .toList(growable: false);
    if (useCache) _autocompleteCache.set(cacheKey, results);
    return results;
  }

  // ─── 2 · SearchText ───────────────────────────────────────────────────

  /// Búsqueda por texto libre. `POST /v2/search-text`.
  ///
  /// Es la que responde a «gasolinera», «Hospital Metropolitano» o a una
  /// dirección escrita entera. Devuelve lugares con coordenada, a diferencia
  /// de [autocomplete].
  ///
  /// [queryId] viene de un [SuggestResult] de tipo consulta: ejecuta esa
  /// búsqueda refinada sin volver a mandar el texto. Es excluyente con
  /// [queryText].
  ///
  /// [maxResults] admite de 1 a 100. Para pasar de la primera página se
  /// reenvía [nextToken] con **los mismos** parámetros; cambiarlos entre
  /// páginas da resultados incoherentes.
  Future<PlaceSearchResponse> searchText({
    String? queryText,
    String? queryId,
    LatLng? biasPosition,
    SearchFilter? filter,
    int maxResults = 10,
    List<PlaceFeature> additionalFeatures = const <PlaceFeature>[],
    String? nextToken,
    String? language,
    IntendedUse? intendedUse,
    bool useCache = true,
  }) async {
    if ((queryText == null || queryText.trim().isEmpty) && queryId == null) {
      throw ArgumentError(
        'searchText necesita queryText o queryId. Con los dos vacíos, la API '
        'responde 400.',
      );
    }
    if (queryText != null && queryId != null) {
      throw ArgumentError(
        'queryText y queryId son excluyentes: queryId ya lleva dentro la '
        'consulta que se va a ejecutar.',
      );
    }
    _checkFilter(filter, 'searchText');
    final limit = _checkResults(maxResults, 1, 100, 'searchText');
    final use = intendedUse ?? this.intendedUse;

    final cacheKey = _key(<Object?>[
      'text',
      queryText,
      queryId,
      biasPosition,
      filter?.toJson(),
      limit,
      nextToken,
      language ?? this.language,
      use.wireName,
    ]);
    if (useCache) {
      final hit = _searchCache.get(cacheKey);
      if (hit != null) return hit;
    }

    final json = await _transport.postJson(
      operation: 'SearchText',
      service: _service,
      path: '/v2/search-text',
      body: <String, dynamic>{
        'QueryText': ?queryText,
        'QueryId': ?queryId,
        'MaxResults': limit,
        if (biasPosition != null) 'BiasPosition': biasPosition.toLonLat(),
        if (filter != null && !filter.isEmpty) 'Filter': filter.toJson(),
        if (additionalFeatures.isNotEmpty)
          'AdditionalFeatures': additionalFeatures
              .map((f) => f.wireName)
              .toList(),
        'NextToken': ?nextToken,
        ..._localeFields(language),
        'IntendedUse': use.wireName,
      },
    );

    final response = PlaceSearchResponse.fromJson(json);
    if (useCache) _searchCache.set(cacheKey, response);
    return response;
  }

  // ─── 3 · ReverseGeocode ───────────────────────────────────────────────

  /// De coordenada a dirección. `POST /v2/reverse-geocode`.
  ///
  /// Es la que convierte `-0.1807, -78.4678` en «Av. Amazonas y Naciones
  /// Unidas» — lo que hay que enseñar cuando salta una alarma, porque nadie
  /// despacha una unidad a un par de decimales.
  ///
  /// [radiusMeters] limita cuánto puede alejarse el resultado del punto. Sin
  /// límite, una posición en una zona sin direcciones devuelve la localidad
  /// más próxima **aunque esté a kilómetros**, y eso se enseña igual que una
  /// dirección exacta. Comprobar [Place.placeType] con [PlaceType.isPrecise]
  /// distingue los dos casos.
  ///
  /// Devuelve la lista entera y no solo el primero: en una esquina, el segundo
  /// resultado suele ser la otra calle, y con los dos se dicta la intersección.
  Future<List<Place>> reverseGeocode(
    LatLng position, {
    double? radiusMeters,
    int maxResults = 1,
    List<String> includePlaceTypes = const <String>[],
    List<PlaceFeature> additionalFeatures = const <PlaceFeature>[],
    String? language,
    IntendedUse? intendedUse,
  }) async {
    final limit = _checkResults(maxResults, 1, 100, 'reverseGeocode');
    final json = await _transport.postJson(
      operation: 'ReverseGeocode',
      service: _service,
      path: '/v2/reverse-geocode',
      body: <String, dynamic>{
        'QueryPosition': position.toLonLat(),
        'MaxResults': limit,
        if (radiusMeters != null) 'QueryRadius': radiusMeters.round(),
        if (includePlaceTypes.isNotEmpty)
          'Filter': <String, dynamic>{'IncludePlaceTypes': includePlaceTypes},
        if (additionalFeatures.isNotEmpty)
          'AdditionalFeatures': additionalFeatures
              .map((f) => f.wireName)
              .toList(),
        ..._localeFields(language),
        'IntendedUse': (intendedUse ?? this.intendedUse).wireName,
      },
    );
    return _items(json).map(Place.fromJson).toList(growable: false);
  }

  // ─── 4 · GetPlace ─────────────────────────────────────────────────────

  /// La ficha completa de un lugar. `GET /v2/place/{PlaceId}`.
  ///
  /// A diferencia de las demás, la respuesta **no** viene envuelta en
  /// `ResultItems`: el objeto está en la raíz.
  ///
  /// El resultado se cachea seis horas: un `placeId` señala siempre al mismo
  /// sitio, y lo único que cambia en ese plazo es el horario de apertura.
  ///
  /// [additionalFeatures] es donde esta operación se gana su precio: es la
  /// única que devuelve contactos, horarios y puntos de acceso.
  Future<Place> getPlace(
    String placeId, {
    List<PlaceFeature> additionalFeatures = const <PlaceFeature>[],
    String? language,
    IntendedUse? intendedUse,
    bool useCache = true,
  }) async {
    if (placeId.isEmpty) {
      throw ArgumentError.value(placeId, 'placeId', 'no puede estar vacío');
    }
    final use = intendedUse ?? this.intendedUse;
    final cacheKey = _key(<Object?>[
      'place',
      placeId,
      additionalFeatures.map((f) => f.wireName).toList(),
      language ?? this.language,
      use.wireName,
    ]);
    if (useCache) {
      final hit = _placeCache.get(cacheKey);
      if (hit != null) return hit;
    }

    final json = await _transport.getJson(
      operation: 'GetPlace',
      service: _service,
      path: '/v2/place/${Uri.encodeComponent(placeId)}',
      queryParameters: <String, String>{
        if (additionalFeatures.isNotEmpty)
          'additional-features': additionalFeatures
              .map((f) => f.wireName)
              .join(','),
        if ((language ?? this.language) != null)
          'language': language ?? this.language!,
        'political-view': ?politicalView,
        'intended-use': use.wireName,
      },
    );

    final place = Place.fromJson(json);
    if (useCache) _placeCache.set(cacheKey, place);
    return place;
  }

  // ─── 5 · Geocode ──────────────────────────────────────────────────────

  /// De dirección a coordenada, con puntuación de coincidencia.
  /// `POST /v2/geocode`.
  ///
  /// Se diferencia de [searchText] en que está pensada para direcciones y no
  /// para nombres, y en que devuelve [Place.matchScore]: lo bien que encaja el
  /// resultado con lo que se pidió, entre 0 y 1.
  ///
  /// Esa puntuación es la que permite automatizar. Con un `matchScore` por
  /// encima de 0,9 y un [PlaceType.pointAddress] se puede aceptar la dirección
  /// sola; por debajo hay que enseñársela al usuario. Sin ella, la única
  /// opción honesta es preguntar siempre.
  ///
  /// [queryComponents] geocodifica campo a campo en vez de con texto libre, y
  /// da mejores resultados cuando la dirección viene de un formulario. Es
  /// excluyente con [queryText].
  Future<List<Place>> geocode({
    String? queryText,
    AddressComponents? queryComponents,
    LatLng? biasPosition,
    List<String> includeCountries = const <String>[],
    int maxResults = 5,
    List<PlaceFeature> additionalFeatures = const <PlaceFeature>[],
    String? language,
    IntendedUse? intendedUse,
  }) async {
    final hasText = queryText != null && queryText.trim().isNotEmpty;
    final hasComponents = queryComponents != null && !queryComponents.isEmpty;
    if (!hasText && !hasComponents) {
      throw ArgumentError('geocode necesita queryText o queryComponents.');
    }
    if (hasText && hasComponents) {
      throw ArgumentError(
        'queryText y queryComponents son excluyentes: la API responde 400 si '
        'llegan los dos.',
      );
    }
    final limit = _checkResults(maxResults, 1, 100, 'geocode');

    final json = await _transport.postJson(
      operation: 'Geocode',
      service: _service,
      path: '/v2/geocode',
      body: <String, dynamic>{
        if (hasText) 'QueryText': queryText,
        if (hasComponents) 'QueryComponents': queryComponents.toJson(),
        'MaxResults': limit,
        if (biasPosition != null) 'BiasPosition': biasPosition.toLonLat(),
        if (includeCountries.isNotEmpty)
          'Filter': <String, dynamic>{'IncludeCountries': includeCountries},
        if (additionalFeatures.isNotEmpty)
          'AdditionalFeatures': additionalFeatures
              .map((f) => f.wireName)
              .toList(),
        ..._localeFields(language),
        'IntendedUse': (intendedUse ?? this.intendedUse).wireName,
      },
    );
    return _items(json).map(Place.fromJson).toList(growable: false);
  }

  // ─── 6 · SearchNearby ─────────────────────────────────────────────────

  /// Qué hay cerca de un punto. `POST /v2/search-nearby`.
  ///
  /// Es la que responde «la gasolinera más cercana» sin que el usuario escriba
  /// nada. Ordena por distancia en línea recta, no por carretera: para lo
  /// segundo hay que pasar los candidatos por
  /// `RoutesClient.calculateRouteMatrix`, que cuesta un cálculo por par.
  ///
  /// La combinación de las dos es el patrón barato: pedir diez por cercanía
  /// aquí (una unidad) y calcular la matriz solo de los tres primeros (tres
  /// unidades) en vez de una matriz de diez (diez unidades).
  ///
  /// [radiusMeters] es obligatorio en la práctica: sin él, el servicio elige
  /// un radio que casi nunca es el que se quería.
  Future<PlaceSearchResponse> searchNearby({
    required LatLng position,
    double? radiusMeters,
    SearchFilter? filter,
    int maxResults = 10,
    List<PlaceFeature> additionalFeatures = const <PlaceFeature>[],
    String? nextToken,
    String? language,
    IntendedUse? intendedUse,
  }) async {
    _checkFilter(filter, 'searchNearby');
    final limit = _checkResults(maxResults, 1, 100, 'searchNearby');

    final json = await _transport.postJson(
      operation: 'SearchNearby',
      service: _service,
      path: '/v2/search-nearby',
      body: <String, dynamic>{
        'QueryPosition': position.toLonLat(),
        'MaxResults': limit,
        if (radiusMeters != null) 'QueryRadius': radiusMeters.round(),
        if (filter != null && !filter.isEmpty) 'Filter': filter.toJson(),
        if (additionalFeatures.isNotEmpty)
          'AdditionalFeatures': additionalFeatures
              .map((f) => f.wireName)
              .toList(),
        'NextToken': ?nextToken,
        ..._localeFields(language),
        'IntendedUse': (intendedUse ?? this.intendedUse).wireName,
      },
    );
    return PlaceSearchResponse.fromJson(json);
  }

  // ─── 7 · Suggest ──────────────────────────────────────────────────────

  /// Sugerencias mezcladas de sitios y de consultas. `POST /v2/suggest`.
  ///
  /// Es más barata que [autocomplete] y devuelve dos cosas distintas en la
  /// misma lista: sitios concretos y **consultas para refinar**. Al escribir
  /// «restau» no hay un sitio que se llame así, hay una búsqueda que hacer, y
  /// esta operación lo dice explícitamente con [SuggestResultType.query].
  ///
  /// Para que las sugerencias de sitio traigan posición y dirección hay que
  /// pedir [PlaceFeature.core] en [additionalFeatures]. Sin él llega solo el
  /// título, que es lo que la hace barata.
  ///
  /// [maxQueryRefinements] limita cuántas propuestas de reescritura vuelven.
  Future<SuggestResponse> suggest({
    required String query,
    LatLng? biasPosition,
    SearchFilter? filter,
    int maxResults = 5,
    int? maxQueryRefinements,
    List<PlaceFeature> additionalFeatures = const <PlaceFeature>[],
    String? language,
  }) async {
    if (query.trim().isEmpty) return const SuggestResponse();
    _checkFilter(filter, 'suggest');
    final limit = _checkResults(maxResults, 1, 20, 'suggest');

    final json = await _transport.postJson(
      operation: 'Suggest',
      service: _service,
      path: '/v2/suggest',
      body: <String, dynamic>{
        'QueryText': query,
        'MaxResults': limit,
        'MaxQueryRefinements': ?maxQueryRefinements,
        if (biasPosition != null) 'BiasPosition': biasPosition.toLonLat(),
        if (filter != null && !filter.isEmpty) 'Filter': filter.toJson(),
        if (additionalFeatures.isNotEmpty)
          'AdditionalFeatures': additionalFeatures
              .map((f) => f.wireName)
              .toList(),
        ..._localeFields(language),
        'IntendedUse': IntendedUse.singleUse.wireName,
      },
    );
    return SuggestResponse.fromJson(json);
  }

  // ─── Auxiliares ───────────────────────────────────────────────────────

  /// Vacía las cachés de este cliente.
  ///
  /// Hay que llamarlo al cambiar de idioma o de sesión: lo guardado está en el
  /// idioma anterior, y seguir sirviéndolo produce una lista mitad en español
  /// y mitad en inglés sin ninguna explicación visible.
  void clearCache() {
    _autocompleteCache.clear();
    _searchCache.clear();
    _placeCache.clear();
  }

  Map<String, dynamic> _localeFields(String? override) => <String, dynamic>{
    if ((override ?? language) != null) 'Language': override ?? language,
    if (politicalView != null) 'PoliticalView': politicalView,
  };

  List<Map<String, dynamic>> _items(Map<String, dynamic> json) {
    final items = json['ResultItems'];
    if (items is! List) return const <Map<String, dynamic>>[];
    return items.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  /// Comprueba que el filtro no lleve dos formas excluyentes.
  ///
  /// La API responde `400` si llegan `BoundingBox` y `Circle` a la vez. Se
  /// comprueba aquí para que el error salga con el nombre del parámetro y en
  /// el sitio donde se puede corregir, en vez de como un `400` opaco después
  /// de haber pagado el viaje de ida.
  static void _checkFilter(SearchFilter? filter, String operation) {
    if (filter == null) return;
    if (filter.boundingBox != null && filter.circle != null) {
      throw ArgumentError(
        'en $operation, boundingBox y circle son excluyentes dentro de '
        'SearchFilter: Amazon Location responde 400 si llegan los dos.',
      );
    }
  }

  /// Comprueba el rango de `maxResults` en vez de recortarlo en silencio.
  ///
  /// Recortar oculta el error: quien pidió 200 resultados sigue creyendo que
  /// los tiene todos, y su paginación nunca avanza porque cree que ya está
  /// todo en la primera página.
  static int _checkResults(int value, int min, int max, String operation) {
    if (value < min || value > max) {
      throw ArgumentError.value(
        value,
        'maxResults',
        '$operation admite entre $min y $max',
      );
    }
    return value;
  }

  static String _key(List<Object?> parts) => parts.join('|');
}
