// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:compass_maps/src/core/json.dart';
import 'package:meta/meta.dart';

/// Un país, con sus dos códigos ISO y su nombre.
@immutable
class Country {
  /// Crea el país.
  const Country({this.code2, this.code3, this.name});

  /// Lee el país de la respuesta del servicio.
  factory Country.fromJson(Map<String, dynamic> json) => Country(
    code2: Json.string(json, 'Code2'),
    code3: Json.string(json, 'Code3'),
    name: Json.string(json, 'Name'),
  );

  /// Código ISO 3166-1 alfa-2, p. ej. `EC`.
  final String? code2;

  /// Código ISO 3166-1 alfa-3, p. ej. `ECU`.
  ///
  /// **Es el que piden los filtros** `includeCountries`. Pasar el alfa-2 donde
  /// va el alfa-3 no da error: devuelve cero resultados, que es más difícil de
  /// diagnosticar.
  final String? code3;

  /// Nombre del país en el idioma pedido.
  final String? name;

  @override
  String toString() => name ?? code3 ?? code2 ?? 'Country(?)';
}

/// Una división administrativa con código y nombre: provincia, cantón,
/// parroquia, según el nivel.
@immutable
class AdminArea {
  /// Crea el área.
  const AdminArea({this.code, this.name});

  /// Lee el área de la respuesta del servicio.
  factory AdminArea.fromJson(Map<String, dynamic> json) => AdminArea(
    code: Json.string(json, 'Code'),
    name: Json.string(json, 'Name'),
  );

  /// Código de la división, cuando el proveedor lo da.
  final String? code;

  /// Nombre de la división.
  final String? name;

  @override
  String toString() => name ?? code ?? 'AdminArea(?)';
}

/// Una pieza del nombre de una calle, ya separada.
///
/// «Avenida de los Shyris» llega descompuesta en tipo (`Avenida`), separador
/// (`de los`) y nombre base (`Shyris`). Sirve para componer la dirección con
/// el orden y las abreviaturas de cada país sin tratar la calle como una
/// cadena opaca.
@immutable
class StreetComponent {
  /// Crea la pieza.
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

  /// Lee la pieza de la respuesta del servicio.
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

  /// El nombre sin el tipo: `Shyris` de «Avenida de los Shyris».
  final String? baseName;

  /// El tipo de vía: `Avenida`, `Calle`, `Pasaje`.
  final String? type;

  /// Si el tipo va antes o después del nombre (`BeforeBaseName`,
  /// `AfterBaseName`). En español va antes; en inglés, después.
  final String? typePlacement;

  /// Lo que separa el tipo del nombre: `de los`, `del`.
  final String? typeSeparator;

  /// Prefijo de la vía.
  final String? prefix;

  /// Sufijo de la vía.
  final String? suffix;

  /// Punto cardinal, como el `N` de «Av. 10 de Agosto N24».
  final String? direction;

  /// Idioma BCP 47 de esta pieza.
  final String? language;

  @override
  String toString() => baseName ?? type ?? 'StreetComponent(?)';
}

/// Una dirección postal completa, tal como la desglosa Amazon Location v2.
///
/// La mayoría de las apps solo necesitan [label], que es la dirección ya
/// compuesta y lista para enseñar. El desglose está entero porque hay dos
/// cosas que solo se pueden hacer con él: rellenar un formulario campo a campo
/// —país, provincia, ciudad, calle, número— y componer la dirección con las
/// convenciones de un país concreto.
///
/// El cliente anterior guardaba solo `Address.Label` y descartaba el resto, lo
/// que obligaba a pedir el lugar otra vez cada vez que hacía falta un campo.
@immutable
class Address {
  /// Crea la dirección.
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

  /// Lee la dirección de la respuesta del servicio.
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

  /// La dirección completa en una línea, ya compuesta por el servicio.
  ///
  /// Es lo que hay que enseñar en pantalla. Componerla a mano desde los campos
  /// sale mal en cuanto se cruza una frontera: el orden y los separadores
  /// cambian por país.
  final String? label;

  /// El país.
  final Country? country;

  /// Primer nivel administrativo: provincia, estado, departamento.
  final AdminArea? region;

  /// Segundo nivel: cantón, condado.
  final AdminArea? subRegion;

  /// La ciudad o población.
  final String? locality;

  /// El barrio o distrito.
  final String? district;

  /// Subdivisión del barrio.
  final String? subDistrict;

  /// Código postal.
  final String? postalCode;

  /// Manzana, donde el direccionamiento la usa (Japón, partes de Asia).
  final String? block;

  /// Submanzana.
  final String? subBlock;

  /// La calle ya compuesta.
  final String? street;

  /// La calle desglosada en piezas.
  final List<StreetComponent> streetComponents;

  /// El número del portal.
  final String? addressNumber;

  /// Nombre del edificio, si lo tiene.
  final String? building;

  /// Las vías que se cruzan, cuando la posición es una esquina.
  ///
  /// Es lo que se dicta por radio cuando no hay número: «Amazonas y Naciones
  /// Unidas».
  final List<String> intersection;

  /// La dirección más corta que sigue siendo útil para hablar: calle y número,
  /// o la esquina, o la ciudad.
  ///
  /// Es lo que se lee en voz alta al despachar un aviso, donde el [label]
  /// completo —con país y código postal— sobra.
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
