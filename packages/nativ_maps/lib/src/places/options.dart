// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/lat_lng.dart';

/// How a search is narrowed down: by rectangle, by circle, by country, or by
/// several of them at once.
///
/// A filter is not the same as a **bias**. The bias (`biasPosition`) says
/// "results from around here, first"; the filter says "the ones outside,
/// don't even show them". Mixing them up makes a search for a Quito address
/// return the Bogotá one because nobody ruled out Colombia.
@immutable
class SearchFilter {
  /// Creates the filter.
  const SearchFilter({
    this.boundingBox,
    this.circle,
    this.includeCountries = const <String>[],
    this.includeCategories = const <String>[],
    this.excludeCategories = const <String>[],
    this.includeBusinessChains = const <String>[],
    this.excludeBusinessChains = const <String>[],
    this.includeFoodTypes = const <String>[],
    this.includePlaceTypes = const <String>[],
  });

  /// Only what falls inside this rectangle.
  final LatLngBounds? boundingBox;

  /// Only what falls inside this circle.
  final ({LatLng center, double radiusMeters})? circle;

  /// Country codes in **ISO 3166 alpha-3**, e.g. `['ECU']`.
  ///
  /// The alpha-2 (`EC`) doesn't raise an error: it returns zero results,
  /// which is harder to diagnose than a failure.
  final List<String> includeCountries;

  /// Category identifiers to include.
  final List<String> includeCategories;

  /// Category identifiers to exclude.
  final List<String> excludeCategories;

  /// Business chains to include.
  final List<String> includeBusinessChains;

  /// Business chains to exclude.
  final List<String> excludeBusinessChains;

  /// Food types to include.
  final List<String> includeFoodTypes;

  /// Place types to include, using the `PlaceType` names.
  final List<String> includePlaceTypes;

  /// Is everything empty? An empty filter is not sent.
  bool get isEmpty =>
      boundingBox == null &&
      circle == null &&
      includeCountries.isEmpty &&
      includeCategories.isEmpty &&
      excludeCategories.isEmpty &&
      includeBusinessChains.isEmpty &&
      excludeBusinessChains.isEmpty &&
      includeFoodTypes.isEmpty &&
      includePlaceTypes.isEmpty;

  /// The filter in the shape the service expects.
  Map<String, dynamic> toJson() => <String, dynamic>{
    if (boundingBox != null) 'BoundingBox': boundingBox!.toBbox(),
    if (circle != null)
      'Circle': <String, dynamic>{
        'Center': circle!.center.toLonLat(),
        'Radius': circle!.radiusMeters,
      },
    if (includeCountries.isNotEmpty) 'IncludeCountries': includeCountries,
    if (includeCategories.isNotEmpty) 'IncludeCategories': includeCategories,
    if (excludeCategories.isNotEmpty) 'ExcludeCategories': excludeCategories,
    if (includeBusinessChains.isNotEmpty)
      'IncludeBusinessChains': includeBusinessChains,
    if (excludeBusinessChains.isNotEmpty)
      'ExcludeBusinessChains': excludeBusinessChains,
    if (includeFoodTypes.isNotEmpty) 'IncludeFoodTypes': includeFoodTypes,
    if (includePlaceTypes.isNotEmpty) 'IncludePlaceTypes': includePlaceTypes,
  };
}

/// Extra data that can be requested in a Places operation.
///
/// **Each one has a cost.** Not in separate billing units, but in response
/// size and in time. Requesting all of them "just in case" in an autocomplete
/// that fires on every keystroke is a decision you will notice.
///
/// ## Each operation accepts a different subset
///
/// Measured against the service on 2026-10-19. Anything outside its row is a
/// **400**: `contact` in `autocomplete`, for example, or `core` in
/// `searchText`.
///
/// | Operation | Accepts |
/// |---|---|
/// | `autocomplete` | `core` |
/// | `suggest` | `core`, `timeZone`, `access`, `phonemes` |
/// | `searchText` | `contact`, `timeZone`, `access`, `phonemes` |
/// | `searchNearby` | `contact`, `timeZone`, `access`, `phonemes` |
/// | `getPlace` | all but `core` and `intersections` |
/// | `geocode` | `timeZone`, `access`, `secondaryAddresses`, `intersections` |
/// | `reverseGeocode` | `timeZone`, `access`, `intersections` |
enum PlaceFeature {
  /// The place's base fields. In `suggest` you have to request it explicitly
  /// for the response to include position and address.
  core('Core'),

  /// Phone numbers, websites and emails.
  contact('Contact'),

  /// The place's time zone.
  timeZone('TimeZone'),

  /// The access points.
  access('Access'),

  /// How the name is pronounced. For voice readout in navigation.
  phonemes('Phonemes'),

  /// The secondary addresses inside the place: units, flats or suites of the
  /// same building.
  secondaryAddresses('SecondaryAddresses'),

  /// The intersections near the place: the cross streets of an address.
  intersections('Intersections');

  const PlaceFeature(this.wireName);

  /// The literal that travels in the JSON.
  final String wireName;
}

/// How postal codes are handled in an autocomplete.
enum PostalCodeMode {
  /// Each postal code appears once, even if it covers several localities.
  mergeAllSpannedLocalities('MergeAllSpannedLocalities'),

  /// One result per locality. It is the service's default value.
  enumerateSpannedLocalities('EnumerateSpannedLocalities');

  const PostalCodeMode(this.wireName);

  /// The literal that travels in the JSON.
  final String wireName;
}

/// The components of an address, for geocoding field by field.
///
/// It's the alternative to sending the address as free text, and it gives
/// better results when the address already comes split up from a form: the
/// service doesn't have to guess where the street ends and the city begins.
@immutable
class AddressComponents {
  /// Creates the components.
  const AddressComponents({
    this.country,
    this.region,
    this.subRegion,
    this.locality,
    this.district,
    this.street,
    this.addressNumber,
    this.postalCode,
  });

  /// Country, in ISO alpha-2 or alpha-3.
  final String? country;

  /// Province or state.
  final String? region;

  /// Canton or county.
  final String? subRegion;

  /// City.
  final String? locality;

  /// Neighborhood.
  final String? district;

  /// Street.
  final String? street;

  /// Number.
  final String? addressNumber;

  /// Postal code.
  final String? postalCode;

  /// Was none of them filled in?
  bool get isEmpty =>
      country == null &&
      region == null &&
      subRegion == null &&
      locality == null &&
      district == null &&
      street == null &&
      addressNumber == null &&
      postalCode == null;

  /// The components in the shape the service expects.
  Map<String, dynamic> toJson() => <String, dynamic>{
    if (country != null) 'Country': country,
    if (region != null) 'Region': region,
    if (subRegion != null) 'SubRegion': subRegion,
    if (locality != null) 'Locality': locality,
    if (district != null) 'District': district,
    if (street != null) 'Street': street,
    if (addressNumber != null) 'AddressNumber': addressNumber,
    if (postalCode != null) 'PostalCode': postalCode,
  };
}
