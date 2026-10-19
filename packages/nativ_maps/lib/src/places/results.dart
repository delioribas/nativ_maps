// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/json.dart';
import 'package:nativ_maps/src/places/place.dart';

/// An autocomplete suggestion.
///
/// It's deliberately leaner than [Place]: `Autocomplete` is the cheapest
/// operation and returns no position. To get the coordinate you have to call
/// `getPlace` with the [placeId] — a second request, which you only pay for
/// the suggestion the user **picks** instead of for the twenty they see.
///
/// That's the whole design of the search bar: typing is cheap, picking costs
/// once.
@immutable
class AutocompleteSuggestion {
  /// Creates the suggestion.
  const AutocompleteSuggestion({
    required this.title,
    this.placeId,
    this.placeType,
    this.address,
    this.distanceMeters,
    this.highlights = const <Highlight>[],
  });

  /// Reads the suggestion from the service response.
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

  /// The text shown in the list.
  final String title;

  /// The identifier to fetch the details with `getPlace`.
  final String? placeId;

  /// What kind of place it is.
  final PlaceType? placeType;

  /// The address on one line, if it includes one.
  final String? address;

  /// Straight-line distance from the bias, if one was given.
  final double? distanceMeters;

  /// The spans of the title that match what was typed, to highlight them.
  final List<Highlight> highlights;

  @override
  String toString() => 'AutocompleteSuggestion($title)';
}

/// What kind of suggestion `suggest` returned.
enum SuggestResultType {
  /// A specific place, in [SuggestResult.place].
  place('Place'),

  /// A refined query to search again with, in [SuggestResult.queryId].
  ///
  /// It's what happens when you type «restaurante»: there's no place called
  /// that, there's a search to run.
  query('Query');

  const SuggestResultType(this.wireName);

  /// The literal the service returns.
  final String wireName;
}

/// An item in the `suggest` response.
///
/// `Suggest` is the cheap operation: it mixes specific places with queries to
/// refine, which is why an item can be one thing or the other. Check [type]
/// before reading [place] or [queryId].
@immutable
class SuggestResult {
  /// Creates the result.
  const SuggestResult({
    required this.title,
    required this.type,
    this.place,
    this.queryId,
    this.queryType,
    this.highlights = const <Highlight>[],
  });

  /// Reads the result from the service response.
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

  /// The text shown.
  final String title;

  /// Whether this is a place or a query.
  final SuggestResultType type;

  /// The place, when [type] is [SuggestResultType.place].
  final Place? place;

  /// The query identifier, when [type] is [SuggestResultType.query].
  ///
  /// Pass it to `searchText` as `queryId` to run the refined search without
  /// sending the text again.
  final String? queryId;

  /// What kind of query it is.
  final String? queryType;

  /// The spans of the title that match what was typed.
  final List<Highlight> highlights;

  @override
  String toString() => 'SuggestResult($title, ${type.name})';
}

/// A proposed rewrite of what was searched for.
///
/// «pizzeria en quito» is broken down into the original term and the refined
/// one, with the positions inside the text so it can be underlined.
@immutable
class QueryRefinement {
  /// Creates the proposal.
  const QueryRefinement({
    this.refinedTerm,
    this.originalTerm,
    this.startIndex,
    this.endIndex,
  });

  /// Reads the proposal from the service response.
  factory QueryRefinement.fromJson(Map<String, dynamic> json) =>
      QueryRefinement(
        refinedTerm: Json.string(json, 'RefinedTerm'),
        originalTerm: Json.string(json, 'OriginalTerm'),
        startIndex: Json.integer(json, 'StartIndex'),
        endIndex: Json.integer(json, 'EndIndex'),
      );

  /// The term as the service understands it.
  final String? refinedTerm;

  /// The term as the user typed it.
  final String? originalTerm;

  /// Where it starts inside the original text.
  final int? startIndex;

  /// Where it ends inside the original text.
  final int? endIndex;
}

/// The `suggest` response, with its refinements.
@immutable
class SuggestResponse {
  /// Creates the response.
  const SuggestResponse({
    this.results = const <SuggestResult>[],
    this.queryRefinements = const <QueryRefinement>[],
    this.pricingBucket,
  });

  /// Reads the service response.
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

  /// The suggestions, in the order the service gave them.
  final List<SuggestResult> results;

  /// Proposals for rewriting the query.
  final List<QueryRefinement> queryRefinements;

  /// The pricing bucket AWS applied to this call.
  ///
  /// It lets you reconcile the bill against what the app thinks it spent,
  /// which is the only way to detect that a screen is over-requesting.
  final String? pricingBucket;

  @override
  String toString() => 'SuggestResponse(${results.length} sugerencias)';
}

/// A page of search results.
///
/// It carries the [nextToken] inside because pagination is the part that
/// gets forgotten the most: a list that only shows the first ten results and
/// never the next ones looks like it works.
@immutable
class PlaceSearchResponse {
  /// Creates the page.
  const PlaceSearchResponse({
    this.places = const <Place>[],
    this.nextToken,
    this.pricingBucket,
  });

  /// Reads the page from the service response.
  factory PlaceSearchResponse.fromJson(Map<String, dynamic> json) =>
      PlaceSearchResponse(
        places: Json.objects(
          json,
          'ResultItems',
        ).map(Place.fromJson).toList(growable: false),
        nextToken: Json.string(json, 'NextToken'),
        pricingBucket: Json.string(json, 'PricingBucket'),
      );

  /// The results on this page.
  final List<Place> places;

  /// The token to request the next page, or `null` if there are no more.
  final String? nextToken;

  /// The pricing bucket AWS applied.
  final String? pricingBucket;

  /// Are there more pages?
  bool get hasMore => nextToken != null;

  /// How many results this page has.
  int get length => places.length;

  /// Did it come back empty?
  bool get isEmpty => places.isEmpty;

  /// Does it contain anything?
  bool get isNotEmpty => places.isNotEmpty;

  @override
  String toString() =>
      'PlaceSearchResponse(${places.length} lugares'
      '${hasMore ? ', hay más' : ''})';
}
