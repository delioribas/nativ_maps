// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/json.dart';
import 'package:nativ_maps/src/core/lat_lng.dart';
import 'package:nativ_maps/src/places/address.dart';

/// What kind of place a result is.
///
/// It matters more than it seems: a [locality] returned by an address search
/// means "I couldn't find the street number, here's the city", and showing it
/// as if it were the exact address is how a vehicle ends up "located" at the
/// geographic center of Quito.
enum PlaceType {
  /// The whole country.
  country('Country'),

  /// A first-level administrative division.
  region('Region'),

  /// A second-level one.
  subRegion('SubRegion'),

  /// A city or town.
  locality('Locality'),

  /// A district or neighborhood.
  district('District'),

  /// A subdistrict.
  subDistrict('SubDistrict'),

  /// A postal code area.
  postalCode('PostalCode'),

  /// A block.
  block('Block'),

  /// A sub-block.
  subBlock('SubBlock'),

  /// An intersection of streets.
  intersection('Intersection'),

  /// A whole street.
  street('Street'),

  /// A specific street number. It's the level of precision you want for a
  /// delivery address.
  pointAddress('PointAddress'),

  /// A point interpolated along the street segment: the position is an
  /// estimate between two known street numbers, not a real one.
  interpolatedAddress('InterpolatedAddress'),

  /// A business or point of interest.
  pointOfInterest('PointOfInterest');

  const PlaceType(this.wireName);

  /// The literal the service returns.
  final String wireName;

  /// Is it precise enough to treat as a specific address?
  ///
  /// A [pointAddress] or a [pointOfInterest] points to a place; a [locality]
  /// points to a whole city. The difference between the two is kilometers.
  bool get isPrecise =>
      this == pointAddress ||
      this == pointOfInterest ||
      this == interpolatedAddress ||
      this == intersection;
}

/// A point-of-interest category: "restaurant", "gas station", "hospital".
@immutable
class PlaceCategory {
  /// Creates the category.
  const PlaceCategory({this.id, this.name, this.localizedName, this.primary});

  /// Reads the category from the service response.
  factory PlaceCategory.fromJson(Map<String, dynamic> json) => PlaceCategory(
    id: Json.string(json, 'Id'),
    name: Json.string(json, 'Name'),
    localizedName: Json.string(json, 'LocalizedName'),
    primary: Json.boolean(json, 'Primary'),
  );

  /// Stable identifier of the category. It's the one to use for filtering;
  /// the name changes with the language.
  final String? id;

  /// Name of the category.
  final String? name;

  /// Name in the requested language.
  final String? localizedName;

  /// Is this the place's main category? A place can have several.
  final bool? primary;

  @override
  String toString() => localizedName ?? name ?? id ?? 'PlaceCategory(?)';
}

/// A way to get in touch: phone, website, email or social network.
@immutable
class ContactDetail {
  /// Creates the contact.
  const ContactDetail({this.label, this.value, this.categories = const []});

  /// Reads the contact from the service response.
  factory ContactDetail.fromJson(Map<String, dynamic> json) => ContactDetail(
    label: Json.string(json, 'Label'),
    value: Json.string(json, 'Value'),
    categories: Json.objects(
      json,
      'Categories',
    ).map(PlaceCategory.fromJson).toList(growable: false),
  );

  /// Human-readable label of the contact.
  final String? label;

  /// The value: the number, the URL, the email address.
  final String? value;

  /// Which part of the business it belongs to, when it has several.
  final List<PlaceCategory> categories;

  @override
  String toString() => value ?? label ?? 'ContactDetail(?)';
}

/// A place's contacts, grouped by type.
@immutable
class Contacts {
  /// Creates the group.
  const Contacts({
    this.phones = const <ContactDetail>[],
    this.faxes = const <ContactDetail>[],
    this.websites = const <ContactDetail>[],
    this.emails = const <ContactDetail>[],
  });

  /// Reads the contacts from the service response.
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

  /// Phone numbers.
  final List<ContactDetail> phones;

  /// Faxes.
  final List<ContactDetail> faxes;

  /// Websites.
  final List<ContactDetail> websites;

  /// Email addresses.
  final List<ContactDetail> emails;

  /// Is there any contact of any type?
  bool get isEmpty =>
      phones.isEmpty && faxes.isEmpty && websites.isEmpty && emails.isEmpty;
}

/// A place's opening hours, including whether it's open now.
@immutable
class OpeningHours {
  /// Creates the opening hours.
  const OpeningHours({
    this.display = const <String>[],
    this.openNow,
    this.components = const <OpeningHoursComponent>[],
    this.categories = const <PlaceCategory>[],
  });

  /// Reads the opening hours from the service response.
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

  /// The opening hours already written out for display, one line per slot.
  final List<String> display;

  /// Is it open at the time of the query?
  ///
  /// The server computes it in the place's time zone, which is the reason not
  /// to compute it on the phone: doing it right requires knowing the place's
  /// time zone, not the phone's.
  final bool? openNow;

  /// The opening hours in machine-readable form, for computing with.
  final List<OpeningHoursComponent> components;

  /// Which part of the business these opening hours apply to.
  final List<PlaceCategory> categories;
}

/// A time slot in machine-readable format.
@immutable
class OpeningHoursComponent {
  /// Creates the time slot.
  const OpeningHoursComponent({
    this.openTime,
    this.openDuration,
    this.recurrence,
  });

  /// Reads the time slot from the service response.
  factory OpeningHoursComponent.fromJson(Map<String, dynamic> json) =>
      OpeningHoursComponent(
        openTime: Json.string(json, 'OpenTime'),
        openDuration: Json.string(json, 'OpenDuration'),
        recurrence: Json.string(json, 'Recurrence'),
      );

  /// Opening time in ISO 8601 `T` format, e.g. `T080000`.
  final String? openTime;

  /// How long it stays open, as an ISO 8601 duration, e.g. `PT10H30M`.
  final String? openDuration;

  /// The recurrence rule, in iCalendar RRULE format.
  final String? recurrence;
}

/// A point through which you enter or leave a place.
///
/// It's the difference between navigating to the centroid of a shopping mall
/// and navigating to its door. For a delivery app, [AccessPoint] is what
/// keeps the driver from ending up on the wrong side of the block.
@immutable
class AccessPoint {
  /// Creates the access point.
  const AccessPoint({required this.position});

  /// Reads the point from the service response, or `null` if it has no
  /// position.
  static AccessPoint? fromJson(Map<String, dynamic> json) {
    final position = Json.latLng(json, 'Position');
    return position == null ? null : AccessPoint(position: position);
  }

  /// Where the entrance is.
  final LatLng position;

  @override
  String toString() => 'AccessPoint($position)';
}

/// A place's time zone.
@immutable
class TimeZoneInfo {
  /// Creates the time zone.
  const TimeZoneInfo({this.name, this.offset, this.offsetSeconds});

  /// Reads the time zone from the service response.
  factory TimeZoneInfo.fromJson(Map<String, dynamic> json) => TimeZoneInfo(
    name: Json.string(json, 'Name'),
    offset: Json.string(json, 'Offset'),
    offsetSeconds: Json.integer(json, 'OffsetSeconds'),
  );

  /// IANA name, e.g. `America/Guayaquil`.
  final String? name;

  /// Offset in `+HH:MM` format.
  final String? offset;

  /// The same offset in seconds, ready to add.
  final int? offsetSeconds;

  /// The offset as a [Duration], if the service provided it.
  Duration? get offsetDuration =>
      offsetSeconds == null ? null : Duration(seconds: offsetSeconds!);

  @override
  String toString() => name ?? offset ?? 'TimeZoneInfo(?)';
}

/// Which part of the search text matched which part of the result.
///
/// It's for bolding what the user already typed inside each suggestion, the
/// way the Google Maps search bar does. Without it you have to find the
/// substring by hand, and that breaks with accents and capital letters.
@immutable
class Highlight {
  /// Creates the highlighted span.
  const Highlight({required this.startIndex, required this.endIndex});

  /// Reads the span from the service response, or `null` if it's incomplete.
  static Highlight? fromJson(Map<String, dynamic> json) {
    final start = Json.integer(json, 'StartIndex');
    final end = Json.integer(json, 'EndIndex');
    if (start == null || end == null) return null;
    return Highlight(startIndex: start, endIndex: end);
  }

  /// First highlighted character, counting from zero.
  final int startIndex;

  /// First character **after** the highlight.
  final int endIndex;

  @override
  String toString() => 'Highlight($startIndex..$endIndex)';
}

/// A search or geocoding result.
///
/// It's the type returned by `searchText`, `reverseGeocode`, `geocode`,
/// `searchNearby` and `getPlace`. All five share a shape in v2, which is why
/// there is **one** model and not five almost-identical ones.
///
/// How much of it is filled in depends on the operation and on the
/// `additionalFeatures` you request: `getPlace` brings everything, an
/// `autocomplete` only brings title and address.
@immutable
class Place {
  /// Creates the place.
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

  /// Reads the place from the service response.
  ///
  /// The position is optional here and not in the constructor because some
  /// result types legitimately don't include it —an `autocomplete` item is
  /// just text—. Where the position is essential, whoever uses it checks it.
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

  /// The name of the place, or the address if it has no name. It's what goes
  /// in the results list.
  final String title;

  /// The place's stable identifier.
  ///
  /// It's what you store in the database to fetch the details again with
  /// `getPlace` without paying for another search. **It is not global**: an
  /// identifier from one region is not valid in another.
  final String? placeId;

  /// What kind of place it is. See [PlaceType.isPrecise].
  final PlaceType? placeType;

  /// The address, broken down.
  final Address? address;

  /// Where it is.
  final LatLng? position;

  /// Distance in meters from the query point.
  ///
  /// It only comes in operations that have a reference point (`searchNearby`,
  /// `reverseGeocode`, or a search with a bias). It's straight-line distance,
  /// **not by road**.
  final double? distanceMeters;

  /// The rectangle worth framing to see this whole place.
  ///
  /// For a country it's the country; for a street number, the block. Passing
  /// it to `fitBounds` gives a sensible framing without making up a zoom
  /// level.
  final LatLngBounds? mapView;

  /// The service corrected the street number because the requested one
  /// doesn't exist.
  ///
  /// It's a warning sign, not a detail: it means the position is that of the
  /// nearest number, not the one you asked for.
  final bool? addressNumberCorrected;

  /// The place's categories.
  final List<PlaceCategory> categories;

  /// Food types, when it's a restaurant.
  final List<PlaceCategory> foodTypes;

  /// The business chains it belongs to.
  final List<String> businessChains;

  /// The entrances to the place.
  final List<AccessPoint> accessPoints;

  /// The contacts, if `contact` was requested in `additionalFeatures`.
  final Contacts? contacts;

  /// The opening hours, if they were requested.
  final List<OpeningHours> openingHours;

  /// The time zone, if `timeZone` was requested in `additionalFeatures`.
  final TimeZoneInfo? timeZone;

  /// The political view applied to this result.
  final String? politicalView;

  /// How well it matches what was requested, between 0 and 1.
  ///
  /// Only `geocode` returns it. It's what lets you tell "this is the address"
  /// from "this is the closest thing I found", and so decide whether to
  /// accept it on its own or show it to the user to confirm.
  final double? matchScore;

  /// The spans of the title that match what was searched for.
  final List<Highlight> highlights;

  /// The position of the main access point if there is one, otherwise that of
  /// the place itself.
  ///
  /// It's the right coordinate to **navigate** to: [position] may be the
  /// centroid of the premises, and the route to the centroid of a shopping
  /// mall ends in the middle of the building.
  LatLng? get navigationPosition =>
      accessPoints.isNotEmpty ? accessPoints.first.position : position;

  /// The address on one line, if there is one.
  String? get formattedAddress => address?.label;

  @override
  String toString() => 'Place($title${position == null ? '' : ' @ $position'})';
}
