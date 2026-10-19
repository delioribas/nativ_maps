// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'dart:math' as math;

import 'package:meta/meta.dart';

/// A geographic point: latitude and longitude in decimal degrees.
///
/// The order is **latitude first**, as in `google_maps_flutter`. Amazon
/// Location and GeoJSON use the opposite (`[lon, lat]`), and that mismatch is
/// the most common mistake when talking to map services: it does not fail, it
/// gives you a point on another continent. That is why the conversion is not
/// done by hand anywhere — it happens in [toLonLat] and [LatLng.fromLonLat],
/// the only two boundaries where the order changes.
///
/// ```dart
/// const quito = LatLng(-0.1807, -78.4678);
/// quito.toLonLat(); // [-78.4678, -0.1807]  ← what Amazon Location expects
/// ```
@immutable
class LatLng {
  /// Creates a point from latitude and longitude in degrees.
  ///
  /// Throws [ArgumentError] if the latitude falls outside `[-90, 90]` or the
  /// longitude outside `[-180, 180]`. Checking it here and not later matters:
  /// a swapped pair —longitude where the latitude goes— almost always has an
  /// out-of-range latitude, so this constructor catches the swap at the spot
  /// where it happened and not three layers further down.
  LatLng(this.latitude, this.longitude) {
    if (latitude.isNaN ||
        longitude.isNaN ||
        latitude < -90.0 ||
        latitude > 90.0) {
      throw ArgumentError.value(
        latitude,
        'latitude',
        'fuera de [-90, 90]. ¿Están la latitud y la longitud al revés?',
      );
    }
    if (longitude < -180.0 || longitude > 180.0) {
      throw ArgumentError.value(longitude, 'longitude', 'fuera de [-180, 180]');
    }
  }

  /// Creates a point from the Amazon Location and GeoJSON order:
  /// `[longitude, latitude]`.
  ///
  /// Throws [FormatException] if the list does not have at least two numbers.
  /// It does not return `LatLng(0, 0)`: that coordinate exists —it is in the
  /// Gulf of Guinea— and a marker there is drawn exactly like a correct one.
  /// In a tracking app, a silently wrong position is worse than an error in
  /// plain sight.
  factory LatLng.fromLonLat(List<dynamic> lonLat) {
    if (lonLat.length < 2) {
      throw FormatException('se esperaba [lon, lat]', lonLat.toString());
    }
    final lon = lonLat[0];
    final lat = lonLat[1];
    if (lon is! num || lat is! num) {
      throw FormatException('[lon, lat] no numérico', lonLat.toString());
    }
    return LatLng(lat.toDouble(), lon.toDouble());
  }

  /// Latitude in decimal degrees, within `[-90, 90]`.
  final double latitude;

  /// Longitude in decimal degrees, within `[-180, 180]`.
  final double longitude;

  /// Short alias for [latitude].
  double get lat => latitude;

  /// Short alias for [longitude].
  double get lng => longitude;

  /// This point in the Amazon Location and GeoJSON order: `[lon, lat]`.
  List<double> toLonLat() => <double>[longitude, latitude];

  /// Great-circle distance in meters (haversine formula).
  ///
  /// It is straight-line distance over the sphere, **not by road**. For real
  /// driving distance you need `RoutesClient.calculateRoutes` or
  /// `calculateRouteMatrix`, which cost a request; this one costs nothing and
  /// is good for sorting candidates before paying for the ones that survive.
  double distanceTo(LatLng other) {
    final dLat = _toRadians(other.latitude - latitude);
    final dLon = _toRadians(other.longitude - longitude);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(latitude)) *
            math.cos(_toRadians(other.latitude)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// Initial bearing in degrees towards [other]: 0 is north, increasing
  /// clockwise.
  ///
  /// It is the value `icon-rotate` expects to orient a vehicle's icon.
  double bearingTo(LatLng other) {
    final lat1 = _toRadians(latitude);
    final lat2 = _toRadians(other.latitude);
    final dLon = _toRadians(other.longitude - longitude);
    final y = math.sin(dLon) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return (math.atan2(y, x) * 180.0 / math.pi + 360.0) % 360.0;
  }

  /// The point [meters] meters away on bearing [bearingDegrees].
  ///
  /// Useful for building the rectangle around a position without asking the
  /// service for anything.
  LatLng offset(double meters, double bearingDegrees) {
    final angular = meters / earthRadiusMeters;
    final bearing = _toRadians(bearingDegrees);
    final lat1 = _toRadians(latitude);
    final lon1 = _toRadians(longitude);

    final lat2 = math.asin(
      math.sin(lat1) * math.cos(angular) +
          math.cos(lat1) * math.sin(angular) * math.cos(bearing),
    );
    final lon2 =
        lon1 +
        math.atan2(
          math.sin(bearing) * math.sin(angular) * math.cos(lat1),
          math.cos(angular) - math.sin(lat1) * math.sin(lat2),
        );

    return LatLng(
      lat2 * 180.0 / math.pi,
      _normalizeLongitude(lon2 * 180.0 / math.pi),
    );
  }

  /// Copy with the latitude or the longitude changed.
  LatLng copyWith({double? latitude, double? longitude}) =>
      LatLng(latitude ?? this.latitude, longitude ?? this.longitude);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LatLng &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'LatLng($latitude, $longitude)';
}

/// A geographic rectangle, defined by its southwest and northeast corners.
///
/// It does not accept rectangles that cross the antimeridian (±180°): most
/// Amazon Location operations do not either, and accepting it here would only
/// move the failure to the server.
@immutable
class LatLngBounds {
  /// Creates a rectangle from its two corners.
  ///
  /// Throws [ArgumentError] if the southwest ends up north or east of the
  /// northeast, that is, if the corners arrived swapped.
  LatLngBounds({required this.southwest, required this.northeast}) {
    if (southwest.latitude > northeast.latitude) {
      throw ArgumentError(
        'southwest.latitude (${southwest.latitude}) está al norte de '
        'northeast.latitude (${northeast.latitude}): las esquinas están '
        'cambiadas.',
      );
    }
    if (southwest.longitude > northeast.longitude) {
      throw ArgumentError(
        'southwest.longitude (${southwest.longitude}) está al este de '
        'northeast.longitude (${northeast.longitude}). Este tipo no admite '
        'rectángulos que crucen el antimeridiano.',
      );
    }
  }

  /// The smallest rectangle enclosing every point in [points].
  ///
  /// Throws [ArgumentError] with an empty list.
  ///
  /// This used to be an `assert`, which Dart strips when compiling in release
  /// mode: the installed app silently returned a rectangle of infinities and
  /// passed it to `fitBounds`. In other words, it warned in debug and failed in
  /// production, which is exactly the wrong way round.
  factory LatLngBounds.fromPoints(Iterable<LatLng> points) {
    if (points.isEmpty) {
      throw ArgumentError.value(
        points,
        'points',
        'se necesita al menos un punto para calcular un rectángulo',
      );
    }
    var minLat = double.infinity;
    var maxLat = double.negativeInfinity;
    var minLng = double.infinity;
    var maxLng = double.negativeInfinity;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  /// The rectangle from the Amazon Location format:
  /// `[minLon, minLat, maxLon, maxLat]`.
  factory LatLngBounds.fromBbox(List<dynamic> bbox) {
    if (bbox.length < 4 || bbox.any((dynamic v) => v is! num)) {
      throw FormatException(
        'se esperaba [minLon, minLat, maxLon, maxLat]',
        bbox.toString(),
      );
    }
    final values = bbox.cast<num>().map((n) => n.toDouble()).toList();
    return LatLngBounds(
      southwest: LatLng(values[1], values[0]),
      northeast: LatLng(values[3], values[2]),
    );
  }

  /// Southwest corner: the one with the lowest latitude and longitude.
  final LatLng southwest;

  /// Northeast corner: the one with the highest latitude and longitude.
  final LatLng northeast;

  /// Short alias for [southwest].
  LatLng get sw => southwest;

  /// Short alias for [northeast].
  LatLng get ne => northeast;

  /// The center point of the rectangle.
  LatLng get center => LatLng(
    (southwest.latitude + northeast.latitude) / 2,
    (southwest.longitude + northeast.longitude) / 2,
  );

  /// The rectangle in the Amazon Location format:
  /// `[minLon, minLat, maxLon, maxLat]`.
  List<double> toBbox() => <double>[
    southwest.longitude,
    southwest.latitude,
    northeast.longitude,
    northeast.latitude,
  ];

  /// Does [point] fall inside the rectangle? The edges count as inside.
  bool contains(LatLng point) =>
      point.latitude >= southwest.latitude &&
      point.latitude <= northeast.latitude &&
      point.longitude >= southwest.longitude &&
      point.longitude <= northeast.longitude;

  /// The smallest rectangle containing this one and [other].
  LatLngBounds extend(LatLngBounds other) => LatLngBounds(
    southwest: LatLng(
      math.min(southwest.latitude, other.southwest.latitude),
      math.min(southwest.longitude, other.southwest.longitude),
    ),
    northeast: LatLng(
      math.max(northeast.latitude, other.northeast.latitude),
      math.max(northeast.longitude, other.northeast.longitude),
    ),
  );

  /// The same rectangle with a margin of [meters] meters on each side.
  ///
  /// The result is clipped to the world's limits, so widening a rectangle
  /// next to the pole does not produce an impossible latitude.
  LatLngBounds padded(double meters) {
    final latDelta = meters / 111320.0;
    final cosLat = math.cos(_toRadians(center.latitude)).abs();
    final lngDelta = cosLat < 1e-9 ? 180.0 : meters / (111320.0 * cosLat);
    return LatLngBounds(
      southwest: LatLng(
        math.max(-90.0, southwest.latitude - latDelta),
        math.max(-180.0, southwest.longitude - lngDelta),
      ),
      northeast: LatLng(
        math.min(90.0, northeast.latitude + latDelta),
        math.min(180.0, northeast.longitude + lngDelta),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LatLngBounds &&
          southwest == other.southwest &&
          northeast == other.northeast;

  @override
  int get hashCode => Object.hash(southwest, northeast);

  @override
  String toString() => 'LatLngBounds($southwest, $northeast)';
}

/// Mean Earth radius in meters, the value Amazon Location uses.
const double earthRadiusMeters = 6371000.0;

double _toRadians(double degrees) => degrees * math.pi / 180.0;

double _normalizeLongitude(double degrees) => (degrees + 540.0) % 360.0 - 180.0;
