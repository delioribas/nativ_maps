// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:compass_maps/src/core/json.dart';
import 'package:compass_maps/src/core/lat_lng.dart';
import 'package:compass_maps/src/places/address.dart';
import 'package:meta/meta.dart';

/// Qué clase de sitio es un resultado.
///
/// Importa más de lo que parece: un [locality] devuelto por una búsqueda de
/// dirección significa «no encontré el portal, te doy la ciudad», y enseñarlo
/// como si fuera la dirección exacta es cómo un vehículo acaba «localizado» en
/// el centro geográfico de Quito.
enum PlaceType {
  /// El país entero.
  country('Country'),

  /// Una división administrativa de primer nivel.
  region('Region'),

  /// Una de segundo nivel.
  subRegion('SubRegion'),

  /// Una ciudad o población.
  locality('Locality'),

  /// Un distrito o barrio.
  district('District'),

  /// Un subdistrito.
  subDistrict('SubDistrict'),

  /// Una zona de código postal.
  postalCode('PostalCode'),

  /// Una manzana.
  block('Block'),

  /// Una submanzana.
  subBlock('SubBlock'),

  /// Una intersección de vías.
  intersection('Intersection'),

  /// Una calle entera.
  street('Street'),

  /// Un portal concreto. Es el nivel de precisión que se quiere para una
  /// dirección de entrega.
  pointAddress('PointAddress'),

  /// Un punto interpolado sobre el tramo de calle: la posición es una
  /// estimación entre dos portales conocidos, no un portal real.
  interpolatedAddress('InterpolatedAddress'),

  /// Un negocio o punto de interés.
  pointOfInterest('PointOfInterest');

  const PlaceType(this.wireName);

  /// El literal que devuelve el servicio.
  final String wireName;

  /// ¿Es lo bastante preciso para tratarlo como una dirección concreta?
  ///
  /// Un [pointAddress] o un [pointOfInterest] señalan un sitio; una
  /// [locality] señala una ciudad entera. La diferencia entre los dos son
  /// kilómetros.
  bool get isPrecise =>
      this == pointAddress ||
      this == pointOfInterest ||
      this == interpolatedAddress ||
      this == intersection;
}

/// Una categoría de punto de interés: «restaurante», «gasolinera», «hospital».
@immutable
class PlaceCategory {
  /// Crea la categoría.
  const PlaceCategory({this.id, this.name, this.localizedName, this.primary});

  /// Lee la categoría de la respuesta del servicio.
  factory PlaceCategory.fromJson(Map<String, dynamic> json) => PlaceCategory(
    id: Json.string(json, 'Id'),
    name: Json.string(json, 'Name'),
    localizedName: Json.string(json, 'LocalizedName'),
    primary: Json.boolean(json, 'Primary'),
  );

  /// Identificador estable de la categoría. Es el que hay que usar para
  /// filtrar; el nombre cambia con el idioma.
  final String? id;

  /// Nombre de la categoría.
  final String? name;

  /// Nombre en el idioma pedido.
  final String? localizedName;

  /// ¿Es la categoría principal de este sitio? Un sitio puede tener varias.
  final bool? primary;

  @override
  String toString() => localizedName ?? name ?? id ?? 'PlaceCategory(?)';
}

/// Una forma de contactar: teléfono, web, correo o red social.
@immutable
class ContactDetail {
  /// Crea el contacto.
  const ContactDetail({this.label, this.value, this.categories = const []});

  /// Lee el contacto de la respuesta del servicio.
  factory ContactDetail.fromJson(Map<String, dynamic> json) => ContactDetail(
    label: Json.string(json, 'Label'),
    value: Json.string(json, 'Value'),
    categories: Json.objects(
      json,
      'Categories',
    ).map(PlaceCategory.fromJson).toList(growable: false),
  );

  /// Etiqueta legible del contacto.
  final String? label;

  /// El valor: el número, la URL, la dirección de correo.
  final String? value;

  /// A qué parte del negocio corresponde, cuando tiene varias.
  final List<PlaceCategory> categories;

  @override
  String toString() => value ?? label ?? 'ContactDetail(?)';
}

/// Los contactos de un sitio, agrupados por tipo.
@immutable
class Contacts {
  /// Crea el grupo.
  const Contacts({
    this.phones = const <ContactDetail>[],
    this.faxes = const <ContactDetail>[],
    this.websites = const <ContactDetail>[],
    this.emails = const <ContactDetail>[],
  });

  /// Lee los contactos de la respuesta del servicio.
  factory Contacts.fromJson(Map<String, dynamic> json) {
    List<ContactDetail> read(String key) => Json.objects(
      json,
      key,
    ).map(ContactDetail.fromJson).toList(growable: false);
    return Contacts(
      phones: read('Phones'),
      faxes: read('Faxes'),
      websites: read('Websites'),
      emails: read('Emails'),
    );
  }

  /// Teléfonos.
  final List<ContactDetail> phones;

  /// Faxes.
  final List<ContactDetail> faxes;

  /// Sitios web.
  final List<ContactDetail> websites;

  /// Direcciones de correo.
  final List<ContactDetail> emails;

  /// ¿Hay algún contacto de cualquier tipo?
  bool get isEmpty =>
      phones.isEmpty && faxes.isEmpty && websites.isEmpty && emails.isEmpty;
}

/// El horario de un sitio, con si está abierto ahora.
@immutable
class OpeningHours {
  /// Crea el horario.
  const OpeningHours({
    this.display = const <String>[],
    this.openNow,
    this.components = const <OpeningHoursComponent>[],
    this.categories = const <PlaceCategory>[],
  });

  /// Lee el horario de la respuesta del servicio.
  factory OpeningHours.fromJson(Map<String, dynamic> json) => OpeningHours(
    display: Json.strings(json, 'Display'),
    openNow: Json.boolean(json, 'OpenNow'),
    components: Json.objects(
      json,
      'Components',
    ).map(OpeningHoursComponent.fromJson).toList(growable: false),
    categories: Json.objects(
      json,
      'Categories',
    ).map(PlaceCategory.fromJson).toList(growable: false),
  );

  /// El horario ya escrito para enseñar, una línea por franja.
  final List<String> display;

  /// ¿Está abierto en el momento de la consulta?
  ///
  /// Lo calcula el servidor en la zona horaria del sitio, que es la razón de
  /// no calcularlo en el móvil: hacerlo bien exige saber la zona del sitio y
  /// no la del teléfono.
  final bool? openNow;

  /// El horario en forma legible por máquina, para calcular con él.
  final List<OpeningHoursComponent> components;

  /// A qué parte del negocio se aplica este horario.
  final List<PlaceCategory> categories;
}

/// Una franja horaria en formato legible por máquina.
@immutable
class OpeningHoursComponent {
  /// Crea la franja.
  const OpeningHoursComponent({
    this.openTime,
    this.openDuration,
    this.recurrence,
  });

  /// Lee la franja de la respuesta del servicio.
  factory OpeningHoursComponent.fromJson(Map<String, dynamic> json) =>
      OpeningHoursComponent(
        openTime: Json.string(json, 'OpenTime'),
        openDuration: Json.string(json, 'OpenDuration'),
        recurrence: Json.string(json, 'Recurrence'),
      );

  /// Hora de apertura en formato `T` de ISO 8601, p. ej. `T080000`.
  final String? openTime;

  /// Cuánto dura la apertura, en duración ISO 8601, p. ej. `PT10H30M`.
  final String? openDuration;

  /// La regla de repetición, en formato RRULE de iCalendar.
  final String? recurrence;
}

/// Un punto por el que se entra o se sale de un sitio.
///
/// Es la diferencia entre navegar al centroide de un centro comercial y
/// navegar a su puerta. Para una app de reparto, [AccessPoint] es lo que evita
/// que el conductor acabe en el lado equivocado de la manzana.
@immutable
class AccessPoint {
  /// Crea el punto de acceso.
  const AccessPoint({required this.position});

  /// Lee el punto de la respuesta del servicio, o `null` si no trae posición.
  static AccessPoint? fromJson(Map<String, dynamic> json) {
    final position = Json.latLng(json, 'Position');
    return position == null ? null : AccessPoint(position: position);
  }

  /// Dónde está la entrada.
  final LatLng position;

  @override
  String toString() => 'AccessPoint($position)';
}

/// La zona horaria de un sitio.
@immutable
class TimeZoneInfo {
  /// Crea la zona horaria.
  const TimeZoneInfo({this.name, this.offset, this.offsetSeconds});

  /// Lee la zona de la respuesta del servicio.
  factory TimeZoneInfo.fromJson(Map<String, dynamic> json) => TimeZoneInfo(
    name: Json.string(json, 'Name'),
    offset: Json.string(json, 'Offset'),
    offsetSeconds: Json.integer(json, 'OffsetSeconds'),
  );

  /// Nombre IANA, p. ej. `America/Guayaquil`.
  final String? name;

  /// Desfase en formato `+HH:MM`.
  final String? offset;

  /// El mismo desfase en segundos, ya listo para sumar.
  final int? offsetSeconds;

  /// El desfase como [Duration], si el servicio lo dio.
  Duration? get offsetDuration =>
      offsetSeconds == null ? null : Duration(seconds: offsetSeconds!);

  @override
  String toString() => name ?? offset ?? 'TimeZoneInfo(?)';
}

/// Qué parte del texto buscado coincidió con qué parte del resultado.
///
/// Sirve para resaltar en negrita lo que el usuario ya escribió dentro de cada
/// sugerencia, como hace la barra de búsqueda de Google Maps. Sin esto hay que
/// buscar la subcadena a mano, y eso falla con acentos y mayúsculas.
@immutable
class Highlight {
  /// Crea el tramo resaltado.
  const Highlight({required this.startIndex, required this.endIndex});

  /// Lee el tramo de la respuesta del servicio, o `null` si viene incompleto.
  static Highlight? fromJson(Map<String, dynamic> json) {
    final start = Json.integer(json, 'StartIndex');
    final end = Json.integer(json, 'EndIndex');
    if (start == null || end == null) return null;
    return Highlight(startIndex: start, endIndex: end);
  }

  /// Primer carácter resaltado, contando desde cero.
  final int startIndex;

  /// Primer carácter **después** del resaltado.
  final int endIndex;

  @override
  String toString() => 'Highlight($startIndex..$endIndex)';
}

/// Un resultado de búsqueda o geocodificación.
///
/// Es el tipo que devuelven `searchText`, `reverseGeocode`, `geocode`,
/// `searchNearby` y `getPlace`. Los cinco comparten forma en v2, y por eso hay
/// **un** modelo y no cinco casi iguales.
///
/// Cuánto trae relleno depende de la operación y de los `additionalFeatures`
/// que se pidan: `getPlace` lo trae todo, un `autocomplete` solo trae título y
/// dirección.
@immutable
class Place {
  /// Crea el lugar.
  const Place({
    required this.title,
    this.placeId,
    this.placeType,
    this.address,
    this.position,
    this.distanceMeters,
    this.mapView,
    this.addressNumberCorrected,
    this.categories = const <PlaceCategory>[],
    this.foodTypes = const <PlaceCategory>[],
    this.businessChains = const <String>[],
    this.accessPoints = const <AccessPoint>[],
    this.contacts,
    this.openingHours = const <OpeningHours>[],
    this.timeZone,
    this.politicalView,
    this.matchScore,
    this.highlights = const <Highlight>[],
  });

  /// Lee el lugar de la respuesta del servicio.
  ///
  /// La posición es opcional aquí y no en el constructor porque hay tipos de
  /// resultado que legítimamente no la traen —un elemento de `autocomplete`
  /// es solo texto—. Donde la posición es imprescindible, la comprueba quien
  /// la usa.
  factory Place.fromJson(Map<String, dynamic> json) {
    final address = Json.object(json, 'Address');
    final contacts = Json.object(json, 'Contacts');
    final timeZone = Json.object(json, 'TimeZone');
    final matchScores = Json.object(json, 'MatchScores');

    return Place(
      title: Json.string(json, 'Title') ?? Json.string(address, 'Label') ?? '',
      placeId: Json.string(json, 'PlaceId'),
      placeType: Json.enumValue(
        json,
        'PlaceType',
        PlaceType.values,
        (t) => t.wireName,
      ),
      address: address == null ? null : Address.fromJson(address),
      position: Json.latLng(json, 'Position'),
      distanceMeters: Json.number(json, 'Distance'),
      mapView: Json.bounds(json, 'MapView'),
      addressNumberCorrected: Json.boolean(json, 'AddressNumberCorrected'),
      categories: Json.objects(
        json,
        'Categories',
      ).map(PlaceCategory.fromJson).toList(growable: false),
      foodTypes: Json.objects(
        json,
        'FoodTypes',
      ).map(PlaceCategory.fromJson).toList(growable: false),
      businessChains: Json.objects(json, 'BusinessChains')
          .map((c) => Json.string(c, 'Name'))
          .whereType<String>()
          .toList(growable: false),
      accessPoints: Json.objects(json, 'AccessPoints')
          .map(AccessPoint.fromJson)
          .whereType<AccessPoint>()
          .toList(growable: false),
      contacts: contacts == null ? null : Contacts.fromJson(contacts),
      openingHours: Json.objects(
        json,
        'OpeningHours',
      ).map(OpeningHours.fromJson).toList(growable: false),
      timeZone: timeZone == null ? null : TimeZoneInfo.fromJson(timeZone),
      politicalView: Json.string(json, 'PoliticalView'),
      matchScore: Json.number(matchScores, 'Overall'),
      highlights: _readHighlights(json),
    );
  }

  static List<Highlight> _readHighlights(Map<String, dynamic> json) {
    final highlights = Json.object(json, 'Highlights');
    if (highlights == null) return const <Highlight>[];
    return <Highlight>[
      for (final key in const <String>['Title', 'Address'])
        ...Json.objects(
          highlights,
          key,
        ).map(Highlight.fromJson).whereType<Highlight>(),
    ];
  }

  /// El nombre del sitio, o la dirección si no tiene nombre. Es lo que se pone
  /// en la lista de resultados.
  final String title;

  /// El identificador estable del lugar.
  ///
  /// Es lo que se guarda en la base de datos para volver a pedir la ficha con
  /// `getPlace` sin pagar otra búsqueda. **No es global**: un identificador de
  /// una región no vale en otra.
  final String? placeId;

  /// Qué clase de sitio es. Ver [PlaceType.isPrecise].
  final PlaceType? placeType;

  /// La dirección desglosada.
  final Address? address;

  /// Dónde está.
  final LatLng? position;

  /// Distancia en metros desde el punto de la consulta.
  ///
  /// Solo viene en las operaciones que tienen un punto de referencia
  /// (`searchNearby`, `reverseGeocode`, o una búsqueda con sesgo). Es distancia
  /// en línea recta, **no por carretera**.
  final double? distanceMeters;

  /// El rectángulo que conviene encuadrar para ver este sitio entero.
  ///
  /// Para un país es el país; para un portal, la manzana. Pasárselo a
  /// `fitBounds` da un encuadre sensato sin inventar un nivel de zoom.
  final LatLngBounds? mapView;

  /// El servicio corrigió el número del portal porque el pedido no existe.
  ///
  /// Es una señal de aviso, no un detalle: significa que la posición es del
  /// número más cercano, no del que se pidió.
  final bool? addressNumberCorrected;

  /// Las categorías del sitio.
  final List<PlaceCategory> categories;

  /// Tipos de comida, cuando es un restaurante.
  final List<PlaceCategory> foodTypes;

  /// Las cadenas comerciales a las que pertenece.
  final List<String> businessChains;

  /// Las entradas al sitio.
  final List<AccessPoint> accessPoints;

  /// Los contactos, si se pidió `contact` en `additionalFeatures`.
  final Contacts? contacts;

  /// Los horarios, si se pidieron.
  final List<OpeningHours> openingHours;

  /// La zona horaria, si se pidió `timeZone` en `additionalFeatures`.
  final TimeZoneInfo? timeZone;

  /// El punto de vista político aplicado a este resultado.
  final String? politicalView;

  /// Lo bien que encaja con lo que se pidió, entre 0 y 1.
  ///
  /// Solo lo devuelve `geocode`. Es lo que permite distinguir «esta es la
  /// dirección» de «esto es lo más parecido que encontré», y por tanto decidir
  /// si se acepta sola o se le enseña al usuario para que confirme.
  final double? matchScore;

  /// Los tramos del título que coinciden con lo buscado.
  final List<Highlight> highlights;

  /// La posición del acceso principal si lo hay, y si no la del propio sitio.
  ///
  /// Es la coordenada correcta a la que **navegar**: [position] puede ser el
  /// centroide del recinto, y la ruta hasta el centroide de un centro
  /// comercial termina en mitad del edificio.
  LatLng? get navigationPosition =>
      accessPoints.isNotEmpty ? accessPoints.first.position : position;

  /// La dirección en una línea, si la hay.
  String? get formattedAddress => address?.label;

  @override
  String toString() => 'Place($title${position == null ? '' : ' @ $position'})';
}
