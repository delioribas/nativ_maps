// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/json.dart';
import 'package:nativ_maps/src/places/place.dart';

/// Una sugerencia de autocompletado.
///
/// Es deliberadamente más pobre que [Place]: `Autocomplete` es la operación
/// más barata y no devuelve posición. Para tener la coordenada hay que llamar
/// a `getPlace` con el [placeId] — una segunda petición, que solo se paga por
/// la sugerencia que el usuario **elige** en vez de por las veinte que ve.
///
/// Ese es todo el diseño de la barra de búsqueda: escribir es barato, elegir
/// cuesta una vez.
@immutable
class AutocompleteSuggestion {
  /// Crea la sugerencia.
  const AutocompleteSuggestion({
    required this.title,
    this.placeId,
    this.placeType,
    this.address,
    this.distanceMeters,
    this.highlights = const <Highlight>[],
  });

  /// Lee la sugerencia de la respuesta del servicio.
  factory AutocompleteSuggestion.fromJson(Map<String, dynamic> json) {
    final place = Place.fromJson(json);
    return AutocompleteSuggestion(
      title: place.title,
      placeId: place.placeId,
      placeType: place.placeType,
      address: place.address?.label,
      distanceMeters: place.distanceMeters,
      highlights: place.highlights,
    );
  }

  /// El texto que se enseña en la lista.
  final String title;

  /// El identificador para pedir la ficha con `getPlace`.
  final String? placeId;

  /// Qué clase de sitio es.
  final PlaceType? placeType;

  /// La dirección en una línea, si la trae.
  final String? address;

  /// Distancia en línea recta desde el sesgo, si se dio uno.
  final double? distanceMeters;

  /// Los tramos del título que coinciden con lo escrito, para resaltarlos.
  final List<Highlight> highlights;

  @override
  String toString() => 'AutocompleteSuggestion($title)';
}

/// Qué clase de sugerencia devolvió `suggest`.
enum SuggestResultType {
  /// Un sitio concreto, en [SuggestResult.place].
  place('Place'),

  /// Una consulta refinada para volver a buscar, en [SuggestResult.queryId].
  ///
  /// Es lo que pasa al escribir «restaurante»: no hay un sitio que se llame
  /// así, hay una búsqueda que hacer.
  query('Query');

  const SuggestResultType(this.wireName);

  /// El literal que devuelve el servicio.
  final String wireName;
}

/// Un elemento de la respuesta de `suggest`.
///
/// `Suggest` es la operación barata: mezcla sitios concretos con consultas
/// para refinar, y por eso un elemento puede ser una cosa u otra. Se comprueba
/// con [type] antes de leer [place] o [queryId].
@immutable
class SuggestResult {
  /// Crea el resultado.
  const SuggestResult({
    required this.title,
    required this.type,
    this.place,
    this.queryId,
    this.queryType,
    this.highlights = const <Highlight>[],
  });

  /// Lee el resultado de la respuesta del servicio.
  factory SuggestResult.fromJson(Map<String, dynamic> json) {
    final placeJson = Json.object(json, 'Place');
    final queryJson = Json.object(json, 'Query');
    final type =
        Json.enumValue(
          json,
          'SuggestResultItemType',
          SuggestResultType.values,
          (t) => t.wireName,
        ) ??
        (placeJson != null ? SuggestResultType.place : SuggestResultType.query);

    return SuggestResult(
      title: Json.string(json, 'Title') ?? '',
      type: type,
      place: placeJson == null ? null : Place.fromJson(placeJson),
      queryId: Json.string(queryJson, 'QueryId'),
      queryType: Json.string(queryJson, 'QueryType'),
      highlights: Json.objects(
        Json.object(json, 'Highlights'),
        'Title',
      ).map(Highlight.fromJson).whereType<Highlight>().toList(growable: false),
    );
  }

  /// El texto que se enseña.
  final String title;

  /// Si esto es un sitio o una consulta.
  final SuggestResultType type;

  /// El sitio, cuando [type] es [SuggestResultType.place].
  final Place? place;

  /// El identificador de consulta, cuando [type] es [SuggestResultType.query].
  ///
  /// Se pasa a `searchText` como `queryId` para ejecutar la búsqueda refinada
  /// sin volver a mandar el texto.
  final String? queryId;

  /// Qué clase de consulta es.
  final String? queryType;

  /// Los tramos del título que coinciden con lo escrito.
  final List<Highlight> highlights;

  @override
  String toString() => 'SuggestResult($title, ${type.name})';
}

/// Una propuesta de reescritura de lo que se buscó.
///
/// «pizzeria en quito» se descompone en el término original y el refinado, con
/// las posiciones dentro del texto para poder subrayarlo.
@immutable
class QueryRefinement {
  /// Crea la propuesta.
  const QueryRefinement({
    this.refinedTerm,
    this.originalTerm,
    this.startIndex,
    this.endIndex,
  });

  /// Lee la propuesta de la respuesta del servicio.
  factory QueryRefinement.fromJson(Map<String, dynamic> json) =>
      QueryRefinement(
        refinedTerm: Json.string(json, 'RefinedTerm'),
        originalTerm: Json.string(json, 'OriginalTerm'),
        startIndex: Json.integer(json, 'StartIndex'),
        endIndex: Json.integer(json, 'EndIndex'),
      );

  /// El término tal como lo entiende el servicio.
  final String? refinedTerm;

  /// El término tal como lo escribió el usuario.
  final String? originalTerm;

  /// Dónde empieza dentro del texto original.
  final int? startIndex;

  /// Dónde acaba dentro del texto original.
  final int? endIndex;
}

/// La respuesta de `suggest`, con sus refinamientos.
@immutable
class SuggestResponse {
  /// Crea la respuesta.
  const SuggestResponse({
    this.results = const <SuggestResult>[],
    this.queryRefinements = const <QueryRefinement>[],
    this.pricingBucket,
  });

  /// Lee la respuesta del servicio.
  factory SuggestResponse.fromJson(Map<String, dynamic> json) =>
      SuggestResponse(
        results: Json.objects(
          json,
          'ResultItems',
        ).map(SuggestResult.fromJson).toList(growable: false),
        queryRefinements: Json.objects(
          json,
          'QueryRefinements',
        ).map(QueryRefinement.fromJson).toList(growable: false),
        pricingBucket: Json.string(json, 'PricingBucket'),
      );

  /// Las sugerencias, en el orden que las dio el servicio.
  final List<SuggestResult> results;

  /// Propuestas para reescribir la consulta.
  final List<QueryRefinement> queryRefinements;

  /// El tramo de precio que aplicó AWS a esta llamada.
  ///
  /// Sirve para cuadrar la factura contra lo que la app cree que gastó, que es
  /// la única forma de detectar que una pantalla está pidiendo de más.
  final String? pricingBucket;

  @override
  String toString() => 'SuggestResponse(${results.length} sugerencias)';
}

/// Una página de resultados de búsqueda.
///
/// Lleva el [nextToken] dentro porque paginar es la parte que más se olvida:
/// una lista que solo enseña los primeros diez resultados y nunca los
/// siguientes parece que funciona.
@immutable
class PlaceSearchResponse {
  /// Crea la página.
  const PlaceSearchResponse({
    this.places = const <Place>[],
    this.nextToken,
    this.pricingBucket,
  });

  /// Lee la página de la respuesta del servicio.
  factory PlaceSearchResponse.fromJson(Map<String, dynamic> json) =>
      PlaceSearchResponse(
        places: Json.objects(
          json,
          'ResultItems',
        ).map(Place.fromJson).toList(growable: false),
        nextToken: Json.string(json, 'NextToken'),
        pricingBucket: Json.string(json, 'PricingBucket'),
      );

  /// Los resultados de esta página.
  final List<Place> places;

  /// El testigo para pedir la siguiente página, o `null` si no hay más.
  final String? nextToken;

  /// El tramo de precio que aplicó AWS.
  final String? pricingBucket;

  /// ¿Hay más páginas?
  bool get hasMore => nextToken != null;

  /// Cuántos resultados trae esta página.
  int get length => places.length;

  /// ¿Vino vacía?
  bool get isEmpty => places.isEmpty;

  /// ¿Trae algo?
  bool get isNotEmpty => places.isNotEmpty;

  @override
  String toString() =>
      'PlaceSearchResponse(${places.length} lugares'
      '${hasMore ? ', hay más' : ''})';
}
