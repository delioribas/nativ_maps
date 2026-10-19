// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/json.dart';

/// A country, with its two ISO codes and its name.
@immutable
class Country {
  /// Creates the country.
  const Country({this.code2, this.code3, this.name});

  /// Reads the country from the service response.
  factory Country.fromJson(Map<String, dynamic> json) => Country(
    code2: Json.string(json, 'Code2'),
    code3: Json.string(json, 'Code3'),
    name: Json.string(json, 'Name'),
  );

  /// ISO 3166-1 alpha-2 code, e.g. `EC`.
  final String? code2;

  /// ISO 3166-1 alpha-3 code, e.g. `ECU`.
  ///
  /// **It is the one the `includeCountries` filters expect.** Passing the
  /// alpha-2 where the alpha-3 goes doesn't raise an error: it returns zero
  /// results, which is harder to diagnose.
  final String? code3;

  /// Name of the country in the requested language.
  final String? name;

  @override
  String toString() => name ?? code3 ?? code2 ?? 'Country(?)';
}

/// An administrative division with a code and a name: province, canton,
/// parish, depending on the level.
@immutable
class AdminArea {
  /// Creates the area.
  const AdminArea({this.code, this.name});

  /// Reads the area from the service response.
  factory AdminArea.fromJson(Map<String, dynamic> json) => AdminArea(
    code: Json.string(json, 'Code'),
    name: Json.string(json, 'Name'),
  );

  /// Code of the division, when the provider gives one.
  final String? code;

  /// Name of the division.
  final String? name;

  @override
  String toString() => name ?? code ?? 'AdminArea(?)';
}

/// One piece of a street name, already split out.
///
/// «Avenida de los Shyris» arrives broken down into type (`Avenida`),
/// separator (`de los`) and base name (`Shyris`). It lets you compose the
/// address with each country's order and abbreviations without treating the
/// street as an opaque string.
@immutable
class StreetComponent {
  /// Creates the piece.
  const StreetComponent({
    this.baseName,
    this.type,
    this.typePlacement,
    this.typeSeparator,
    this.prefix,
    this.suffix,
    this.direction,
    this.language,
  });

  /// Reads the piece from the service response.
  factory StreetComponent.fromJson(Map<String, dynamic> json) =>
      StreetComponent(
        baseName: Json.string(json, 'BaseName'),
        type: Json.string(json, 'Type'),
        typePlacement: Json.string(json, 'TypePlacement'),
        typeSeparator: Json.string(json, 'TypeSeparator'),
        prefix: Json.string(json, 'Prefix'),
        suffix: Json.string(json, 'Suffix'),
        direction: Json.string(json, 'Direction'),
        language: Json.string(json, 'Language'),
      );

  /// The name without the type: `Shyris` from «Avenida de los Shyris».
  final String? baseName;

  /// The street type: `Avenida`, `Calle`, `Pasaje`.
  final String? type;

  /// Whether the type goes before or after the name (`BeforeBaseName`,
  /// `AfterBaseName`). In Spanish it goes before; in English, after.
  final String? typePlacement;

  /// What separates the type from the name: `de los`, `del`.
  final String? typeSeparator;

  /// Street prefix.
  final String? prefix;

  /// Street suffix.
  final String? suffix;

  /// Cardinal direction, like the `N` in «Av. 10 de Agosto N24».
  final String? direction;

  /// BCP 47 language of this piece.
  final String? language;

  @override
  String toString() => baseName ?? type ?? 'StreetComponent(?)';
}

/// A complete postal address, as Amazon Location v2 breaks it down.
///
/// Most apps only need [label], which is the address already composed and
/// ready to show. The full breakdown is there because there are two things
/// you can only do with it: fill in a form field by field —country, province,
/// city, street, number— and compose the address with a specific country's
/// conventions.
///
/// The previous client kept only `Address.Label` and threw away the rest,
/// which forced you to fetch the place again every time a field was needed.
@immutable
class Address {
  /// Creates the address.
  const Address({
    this.label,
    this.country,
    this.region,
    this.subRegion,
    this.locality,
    this.district,
    this.subDistrict,
    this.postalCode,
    this.block,
    this.subBlock,
    this.street,
    this.streetComponents = const <StreetComponent>[],
    this.addressNumber,
    this.building,
    this.intersection = const <String>[],
  });

  /// Reads the address from the service response.
  factory Address.fromJson(Map<String, dynamic> json) {
    final country = Json.object(json, 'Country');
    final region = Json.object(json, 'Region');
    final subRegion = Json.object(json, 'SubRegion');
    return Address(
      label: Json.string(json, 'Label'),
      country: country == null ? null : Country.fromJson(country),
      region: region == null ? null : AdminArea.fromJson(region),
      subRegion: subRegion == null ? null : AdminArea.fromJson(subRegion),
      locality: Json.string(json, 'Locality'),
      district: Json.string(json, 'District'),
      subDistrict: Json.string(json, 'SubDistrict'),
      postalCode: Json.string(json, 'PostalCode'),
      block: Json.string(json, 'Block'),
      subBlock: Json.string(json, 'SubBlock'),
      street: Json.string(json, 'Street'),
      streetComponents: Json.objects(
        json,
        'StreetComponents',
      ).map(StreetComponent.fromJson).toList(growable: false),
      addressNumber: Json.string(json, 'AddressNumber'),
      building: Json.string(json, 'Building'),
      intersection: Json.strings(json, 'Intersection'),
    );
  }

  /// The complete address on one line, already composed by the service.
  ///
  /// This is what you show on screen. Composing it by hand from the fields
  /// goes wrong as soon as you cross a border: the order and the separators
  /// change by country.
  final String? label;

  /// The country.
  final Country? country;

  /// First administrative level: province, state, department.
  final AdminArea? region;

  /// Second level: canton, county.
  final AdminArea? subRegion;

  /// The city or town.
  final String? locality;

  /// The neighborhood or district.
  final String? district;

  /// Subdivision of the neighborhood.
  final String? subDistrict;

  /// Postal code.
  final String? postalCode;

  /// Block, where the addressing system uses it (Japan, parts of Asia).
  final String? block;

  /// Sub-block.
  final String? subBlock;

  /// The street, already composed.
  final String? street;

  /// The street broken down into pieces.
  final List<StreetComponent> streetComponents;

  /// The street number.
  final String? addressNumber;

  /// Name of the building, if it has one.
  final String? building;

  /// The streets that cross, when the position is a corner.
  ///
  /// It's what gets read out over the radio when there's no number:
  /// «Amazonas y Naciones Unidas».
  final List<String> intersection;

  /// The shortest address that's still useful to say out loud: street and
  /// number, or the corner, or the city.
  ///
  /// It's what gets read aloud when dispatching a call, where the full
  /// [label] —with country and postal code— is too much.
  String? get shortLabel {
    if (street != null) {
      return addressNumber == null ? street : '$street $addressNumber';
    }
    if (intersection.isNotEmpty) return intersection.join(' y ');
    return locality ?? label;
  }

  @override
  String toString() => label ?? shortLabel ?? 'Address(?)';
}
