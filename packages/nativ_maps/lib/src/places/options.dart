// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/lat_lng.dart';

/// Cómo se acota una búsqueda: por rectángulo, por círculo, por país o por
/// varias cosas a la vez.
///
/// El filtro es distinto del **sesgo**. El sesgo (`biasPosition`) dice «los
/// resultados de por aquí, primero»; el filtro dice «los de fuera, ni
/// enseñarlos». Confundirlos hace que una búsqueda de una dirección de Quito
/// devuelva la de Bogotá porque nadie descartó Colombia.
@immutable
class SearchFilter {
  /// Crea el filtro.
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

  /// Solo lo que caiga dentro de este rectángulo.
  final LatLngBounds? boundingBox;

  /// Solo lo que caiga dentro de este círculo.
  final ({LatLng center, double radiusMeters})? circle;

  /// Códigos de país en **ISO 3166 alfa-3**, p. ej. `['ECU']`.
  ///
  /// El alfa-2 (`EC`) no da error: devuelve cero resultados, que es más difícil
  /// de diagnosticar que un fallo.
  final List<String> includeCountries;

  /// Identificadores de categoría a incluir.
  final List<String> includeCategories;

  /// Identificadores de categoría a excluir.
  final List<String> excludeCategories;

  /// Cadenas comerciales a incluir.
  final List<String> includeBusinessChains;

  /// Cadenas comerciales a excluir.
  final List<String> excludeBusinessChains;

  /// Tipos de comida a incluir.
  final List<String> includeFoodTypes;

  /// Tipos de lugar a incluir, con los nombres de `PlaceType`.
  final List<String> includePlaceTypes;

  /// ¿Está todo vacío? Un filtro vacío no se envía.
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

  /// El filtro en la forma que espera el servicio.
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

/// Datos extra que se pueden pedir en una operación de Places.
///
/// **Cada uno cuesta.** No en unidades facturables aparte, pero sí en tamaño
/// de respuesta y en tiempo. Pedirlos todos «por si acaso» en un
/// autocompletado que se dispara con cada tecla es una decisión que se nota.
enum PlaceFeature {
  /// Los campos base del lugar. En `suggest` hay que pedirlo explícitamente
  /// para que la respuesta traiga posición y dirección.
  core('Core'),

  /// Teléfonos, webs y correos.
  contact('Contact'),

  /// La zona horaria del sitio.
  timeZone('TimeZone'),

  /// Los puntos de entrada.
  access('Access'),

  /// Cómo se pronuncia el nombre. Para lectura por voz en navegación.
  phonemes('Phonemes'),

  /// El desglose del código postal.
  secondaryAddresses('SecondaryAddresses'),

  /// Direcciones alternativas del mismo sitio.
  intersections('Intersections');

  const PlaceFeature(this.wireName);

  /// El literal que viaja en el JSON.
  final String wireName;
}

/// Cómo se tratan los códigos postales en un autocompletado.
enum PostalCodeMode {
  /// Cada código postal aparece una vez, aunque cubra varias localidades.
  mergeAllSpannedLocalities('MergeAllSpannedLocalities'),

  /// Un resultado por localidad. Es el valor por defecto del servicio.
  enumerateSpannedLocalities('EnumerateSpannedLocalities');

  const PostalCodeMode(this.wireName);

  /// El literal que viaja en el JSON.
  final String wireName;
}

/// Los componentes de una dirección, para geocodificar campo a campo.
///
/// Es la alternativa a mandar la dirección como texto libre, y da mejores
/// resultados cuando la dirección ya viene troceada de un formulario: el
/// servicio no tiene que adivinar dónde acaba la calle y empieza la ciudad.
@immutable
class AddressComponents {
  /// Crea los componentes.
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

  /// País, en ISO alfa-2 o alfa-3.
  final String? country;

  /// Provincia o estado.
  final String? region;

  /// Cantón o condado.
  final String? subRegion;

  /// Ciudad.
  final String? locality;

  /// Barrio.
  final String? district;

  /// Calle.
  final String? street;

  /// Número.
  final String? addressNumber;

  /// Código postal.
  final String? postalCode;

  /// ¿No se rellenó ninguno?
  bool get isEmpty =>
      country == null &&
      region == null &&
      subRegion == null &&
      locality == null &&
      district == null &&
      street == null &&
      addressNumber == null &&
      postalCode == null;

  /// Los componentes en la forma que espera el servicio.
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
