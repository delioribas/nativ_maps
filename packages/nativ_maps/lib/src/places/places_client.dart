// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/client/cache.dart';
import 'package:nativ_maps/src/client/transport.dart';
import 'package:nativ_maps/src/core/enums.dart';
import 'package:nativ_maps/src/core/lat_lng.dart';
import 'package:nativ_maps/src/places/options.dart';
import 'package:nativ_maps/src/places/place.dart';
import 'package:nativ_maps/src/places/results.dart';

/// The **seven** Amazon Location Places v2 operations.
///
/// | Method | Endpoint | What for |
/// |---|---|---|
/// | [autocomplete] | `POST /v2/autocomplete` | typing an address |
/// | [searchText] | `POST /v2/search-text` | finding a place by name |
/// | [reverseGeocode] | `POST /v2/reverse-geocode` | coordinate to address |
/// | [getPlace] | `GET /v2/place/{id}` | the full details |
/// | [geocode] | `POST /v2/geocode` | address to coordinate, with precision |
/// | [searchNearby] | `POST /v2/search-nearby` | what's near a point |
/// | [suggest] | `POST /v2/suggest` | suggestions cheaper than autocomplete |
///
/// It isn't instantiated by hand: you get it from `NativMaps.places`.
///
/// ## They all cost money
///
/// Every call is a billed request. The ones that fire as you type
/// —[autocomplete] and [suggest]— are the ones that get out of hand the most,
/// which is why they have a cache with expiry: deleting a letter and typing
/// it again doesn't pay twice.
///
/// Debouncing, on the other hand, is **not** here: it depends on the typing
/// rhythm and on the UI thread, and putting it in the client would force the
/// core to know about UI timers. It lives in the search widget of
/// `nativ_maps_flutter`.
class PlacesClient {
  /// Builds the client. Internal use: it comes already set up in `NativMaps`.
  @internal
  PlacesClient({
    required AlsTransport transport,
    required this.intendedUse,
    this.language,
    this.politicalView,
  }) : _transport = transport;

  final AlsTransport _transport;

  /// Whether the results are going to be stored. See [IntendedUse].
  final IntendedUse intendedUse;

  /// Language of the results, in BCP 47. For Ecuador, `es`.
  final String? language;

  /// Political view for disputed borders, in ISO 3166.
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

  /// Suggestions while typing. `POST /v2/autocomplete`.
  ///
  /// It's the cheapest of the operations that produce suggestions, and in
  /// exchange it **returns no coordinates**: to get them you have to call
  /// [getPlace] with the `placeId` of the one the user picks. That's the right
  /// design for a search bar — typing is cheap, picking costs once.
  ///
  /// ```dart
  /// final suggestions = await places.autocomplete(
  ///   query: text,
  ///   biasPosition: currentPosition,
  ///   filter: const SearchFilter(includeCountries: ['ECU']),
  /// );
  /// // and only when the user taps one:
  /// final place = await places.getPlace(suggestions[i].placeId!);
  /// ```
  ///
  /// [biasPosition] and [filter] are **not** mutually exclusive: the bias
  /// ranks, the filter discards. What is mutually exclusive is filling in
  /// both `boundingBox` and `circle` inside [filter]; that is checked before
  /// sending.
  ///
  /// [maxResults] accepts 1 to 20.
  ///
  /// The intended use of this operation is always [IntendedUse.singleUse], and
  /// it isn't this package's decision: the API rejects `Storage` here. A
  /// half-typed suggestion can't be stored.
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
        // Fixed on purpose: the API rejects `Storage` in this operation.
        'IntendedUse': IntendedUse.singleUse.wireName,
      },
    );

    final results = _items(
      json,
    ).map(AutocompleteSuggestion.fromJson).toList(growable: false);
    if (useCache) _autocompleteCache.set(cacheKey, results);
    return results;
  }

  // ─── 2 · SearchText ───────────────────────────────────────────────────

  /// Free-text search. `POST /v2/search-text`.
  ///
  /// It's the one that answers "gas station", "Hospital Metropolitano" or a
  /// fully typed address. It returns places with a coordinate, unlike
  /// [autocomplete].
  ///
  /// [queryId] comes from a query-type [SuggestResult]: it runs that refined
  /// search without sending the text again. It's mutually exclusive with
  /// [queryText].
  ///
  /// [maxResults] accepts 1 to 100. To go past the first page, send
  /// [nextToken] back with **the same** parameters; changing them between
  /// pages gives inconsistent results.
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

  /// From coordinate to address. `POST /v2/reverse-geocode`.
  ///
  /// It's the one that turns `-0.1807, -78.4678` into «Av. Amazonas y Naciones
  /// Unidas» — what you need to show when an alarm goes off, because nobody
  /// dispatches a unit to a pair of decimals.
  ///
  /// [radiusMeters] limits how far the result can stray from the point.
  /// Without a limit, a position in an area with no addresses returns the
  /// nearest locality **even if it's kilometers away**, and it's shown just
  /// like an exact address. Checking [Place.placeType] with
  /// [PlaceType.isPrecise] tells the two cases apart.
  ///
  /// It returns the whole list and not just the first one: on a corner, the
  /// second result is usually the other street, and with both you can read
  /// out the intersection.
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

  /// The full details of a place. `GET /v2/place/{PlaceId}`.
  ///
  /// Unlike the others, the response does **not** come wrapped in
  /// `ResultItems`: the object is at the root.
  ///
  /// The result is cached for six hours: a `placeId` always points to the same
  /// place, and the only thing that changes in that time is the opening hours.
  ///
  /// [additionalFeatures] is where this operation earns its price: it's the
  /// only one that returns contacts, opening hours and access points.
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
    // `core` is always included and intersections belong to other
    // operations: GetPlace responds 400 to either of them.
    final unsupported = additionalFeatures.where(
      (f) => f == PlaceFeature.core || f == PlaceFeature.intersections,
    );
    if (unsupported.isNotEmpty) {
      throw ArgumentError.value(
        unsupported.map((f) => f.name).join(', '),
        'additionalFeatures',
        'getPlace solo admite contact, timeZone, access, phonemes y '
            'secondaryAddresses',
      );
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
      // One per feature: with `Contact,TimeZone` the service responds 400
      // saying that `Contact,TimeZone` is not a valid value.
      repeatedParameters: <MapEntry<String, String>>[
        for (final feature in additionalFeatures)
          MapEntry<String, String>('additional-features', feature.wireName),
      ],
      queryParameters: <String, String>{
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

  /// From address to coordinate, with a match score.
  /// `POST /v2/geocode`.
  ///
  /// It differs from [searchText] in that it's designed for addresses rather
  /// than names, and in that it returns [Place.matchScore]: how well the
  /// result matches what was requested, between 0 and 1.
  ///
  /// That score is what makes automation possible. With a `matchScore` above
  /// 0.9 and a [PlaceType.pointAddress] you can accept the address on its own;
  /// below that you have to show it to the user. Without it, the only honest
  /// option is to always ask.
  ///
  /// [queryComponents] geocodes field by field instead of with free text, and
  /// gives better results when the address comes from a form. It's mutually
  /// exclusive with [queryText].
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

  /// What's near a point. `POST /v2/search-nearby`.
  ///
  /// It's the one that answers "the nearest gas station" without the user
  /// typing anything. It sorts by straight-line distance, not by road: for the
  /// latter you have to run the candidates through
  /// `RoutesClient.calculateRouteMatrix`, which costs one calculation per pair.
  ///
  /// Combining the two is the cheap pattern: ask for ten by proximity here
  /// (one unit) and compute the matrix only for the first three (three units)
  /// instead of a matrix of ten (ten units).
  ///
  /// [radiusMeters] is mandatory in practice: without it, the service picks
  /// a radius that is almost never the one you wanted.
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

  /// Mixed suggestions of places and queries. `POST /v2/suggest`.
  ///
  /// It's cheaper than [autocomplete] and returns two different things in the
  /// same list: specific places and **queries to refine**. When you type
  /// «restau» there's no place called that, there's a search to run, and this
  /// operation says so explicitly with [SuggestResultType.query].
  ///
  /// For place suggestions to include position and address you have to
  /// request [PlaceFeature.core] in [additionalFeatures]. Without it only the
  /// title comes back, which is what makes it cheap.
  ///
  /// [maxQueryRefinements] limits how many rewrite proposals come back.
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

  // ─── Helpers ──────────────────────────────────────────────────────────

  /// Empties this client's caches.
  ///
  /// Call it when switching language or session: what's stored is in the
  /// previous language, and continuing to serve it produces a list half in
  /// Spanish and half in English with no visible explanation.
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

  /// Checks that the filter doesn't carry two mutually exclusive shapes.
  ///
  /// The API responds `400` if `BoundingBox` and `Circle` arrive together.
  /// It's checked here so the error comes out with the parameter's name and
  /// at the spot where it can be fixed, instead of as an opaque `400` after
  /// having paid for the outbound trip.
  static void _checkFilter(SearchFilter? filter, String operation) {
    if (filter == null) return;
    if (filter.boundingBox != null && filter.circle != null) {
      throw ArgumentError(
        'en $operation, boundingBox y circle son excluyentes dentro de '
        'SearchFilter: Amazon Location responde 400 si llegan los dos.',
      );
    }
  }

  /// Checks the range of `maxResults` instead of clamping it silently.
  ///
  /// Clamping hides the error: whoever asked for 200 results keeps believing
  /// they have them all, and their pagination never advances because they
  /// think everything is already on the first page.
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
