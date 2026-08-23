// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:math' as math;

import 'package:meta/meta.dart';

/// Un punto geográfico: latitud y longitud en grados decimales.
///
/// El orden es **latitud primero**, como en `google_maps_flutter`. Amazon
/// Location y GeoJSON usan el contrario (`[lon, lat]`), y esa discrepancia es
/// el error más repetido al hablar con servicios de mapas: no da un fallo,
/// da un punto en otro continente. Por eso la conversión no se hace a mano en
/// ningún sitio — se hace en [toLonLat] y [LatLng.fromLonLat], que son las dos
/// únicas fronteras donde el orden cambia.
///
/// ```dart
/// const quito = LatLng(-0.1807, -78.4678);
/// quito.toLonLat(); // [-78.4678, -0.1807]  ← lo que espera Amazon Location
/// ```
@immutable
class LatLng {
  /// Crea un punto a partir de latitud y longitud en grados.
  ///
  /// Lanza [ArgumentError] si la latitud queda fuera de `[-90, 90]` o la
  /// longitud fuera de `[-180, 180]`. Comprobarlo aquí y no más adelante
  /// importa: un par invertido —longitud donde va la latitud— casi siempre
  /// tiene latitud fuera de rango, así que este constructor caza la inversión
  /// en el sitio donde ocurrió y no tres capas más abajo.
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

  /// Crea un punto desde el orden de Amazon Location y GeoJSON:
  /// `[longitud, latitud]`.
  ///
  /// Lanza [FormatException] si la lista no tiene al menos dos números. No
  /// devuelve `LatLng(0, 0)`: esa coordenada existe —está en el golfo de
  /// Guinea— y un marcador allí se pinta exactamente igual que uno correcto.
  /// En una app de rastreo, una posición falsa en silencio es peor que un
  /// error a la vista.
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

  /// Latitud en grados decimales, dentro de `[-90, 90]`.
  final double latitude;

  /// Longitud en grados decimales, dentro de `[-180, 180]`.
  final double longitude;

  /// Alias corto de [latitude].
  double get lat => latitude;

  /// Alias corto de [longitude].
  double get lng => longitude;

  /// Este punto en el orden de Amazon Location y GeoJSON: `[lon, lat]`.
  List<double> toLonLat() => <double>[longitude, latitude];

  /// Distancia en metros por el gran círculo (fórmula del haversine).
  ///
  /// Es distancia en línea recta sobre la esfera, **no por carretera**. Para
  /// distancia real de conducción hace falta `RoutesClient.calculateRoutes` o
  /// `calculateRouteMatrix`, que cuestan una petición; esta no cuesta nada y
  /// sirve para ordenar candidatos antes de pagar por los que sobreviven.
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

  /// Rumbo inicial en grados hacia [other]: 0 es el norte, aumenta en el
  /// sentido de las agujas del reloj.
  ///
  /// Es el valor que espera `icon-rotate` para orientar el icono de un
  /// vehículo.
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

  /// El punto que está a [meters] metros en el rumbo [bearingDegrees].
  ///
  /// Útil para construir el rectángulo alrededor de una posición sin pedir
  /// nada al servicio.
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

  /// Copia con la latitud o la longitud cambiadas.
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

/// Un rectángulo geográfico, definido por sus esquinas suroeste y noreste.
///
/// No admite rectángulos que crucen el antimeridiano (±180°): la mayoría de
/// las operaciones de Amazon Location tampoco, y aceptarlo aquí solo movería
/// el fallo al servidor.
@immutable
class LatLngBounds {
  /// Crea un rectángulo a partir de sus dos esquinas.
  ///
  /// Lanza [ArgumentError] si el suroeste queda al norte o al este del
  /// noreste, es decir, si las esquinas llegaron cambiadas.
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

  /// El rectángulo mínimo que encierra todos los puntos de [points].
  ///
  /// Lanza [ArgumentError] con la lista vacía.
  ///
  /// Antes esto era un `assert`, que Dart elimina al compilar en modo release:
  /// la app instalada devolvía un rectángulo de infinitos en silencio y se lo
  /// pasaba a `fitBounds`. Es decir, avisaba en depuración y fallaba en
  /// producción, que es exactamente el orden equivocado.
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

  /// El rectángulo desde el formato de Amazon Location:
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

  /// Esquina suroeste: la de menor latitud y menor longitud.
  final LatLng southwest;

  /// Esquina noreste: la de mayor latitud y mayor longitud.
  final LatLng northeast;

  /// Alias corto de [southwest].
  LatLng get sw => southwest;

  /// Alias corto de [northeast].
  LatLng get ne => northeast;

  /// El punto central del rectángulo.
  LatLng get center => LatLng(
    (southwest.latitude + northeast.latitude) / 2,
    (southwest.longitude + northeast.longitude) / 2,
  );

  /// El rectángulo en el formato de Amazon Location:
  /// `[minLon, minLat, maxLon, maxLat]`.
  List<double> toBbox() => <double>[
    southwest.longitude,
    southwest.latitude,
    northeast.longitude,
    northeast.latitude,
  ];

  /// ¿Cae [point] dentro del rectángulo? Los bordes cuentan como dentro.
  bool contains(LatLng point) =>
      point.latitude >= southwest.latitude &&
      point.latitude <= northeast.latitude &&
      point.longitude >= southwest.longitude &&
      point.longitude <= northeast.longitude;

  /// El menor rectángulo que contiene a este y a [other].
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

  /// El mismo rectángulo con un margen de [meters] metros por cada lado.
  ///
  /// El resultado se recorta a los límites del mundo, así que ensanchar un
  /// rectángulo pegado al polo no produce una latitud imposible.
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

/// Radio medio de la Tierra en metros, el valor que usa Amazon Location.
const double earthRadiusMeters = 6371000.0;

double _toRadians(double degrees) => degrees * math.pi / 180.0;

double _normalizeLongitude(double degrees) => (degrees + 540.0) % 360.0 - 180.0;
