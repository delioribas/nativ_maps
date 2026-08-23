// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:compass_maps/src/core/lat_lng.dart';
import 'package:meta/meta.dart';

/// Lectores tolerantes para las respuestas del servicio.
///
/// ## Por qué toleran en vez de exigir
///
/// Amazon Location añade campos sin avisar y no todos los proveedores de datos
/// devuelven los mismos. Un lector estricto convierte «HERE empezó a mandar un
/// campo nuevo» en «la app dejó de abrir el mapa», y eso es peor que ignorar
/// lo que no se entiende.
///
/// La tolerancia tiene un límite concreto, y es la posición:
/// [Json.requiredLatLng] **lanza**. Una posición ilegible no se puede
/// sustituir por un valor por
/// defecto, porque `LatLng(0, 0)` existe —está en el golfo de Guinea— y se
/// pinta en el mapa exactamente igual que una correcta.
@internal
abstract final class Json {
  /// El mapa de [key], o `null` si no está o no es un mapa.
  static Map<String, dynamic>? object(Map<String, dynamic>? json, String key) {
    final value = json?[key];
    return value is Map<String, dynamic> ? value : null;
  }

  /// La lista de mapas de [key], vacía si no está.
  static List<Map<String, dynamic>> objects(
    Map<String, dynamic>? json,
    String key,
  ) {
    final value = json?[key];
    if (value is! List) return const <Map<String, dynamic>>[];
    return value.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  /// La cadena de [key], o `null`. Una cadena vacía cuenta como ausente: el
  /// servicio devuelve `""` en campos que no aplican, y propagarlo obliga a
  /// comprobar dos cosas en cada sitio de uso.
  static String? string(Map<String, dynamic>? json, String key) {
    final value = json?[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  /// La lista de cadenas de [key], vacía si no está.
  static List<String> strings(Map<String, dynamic>? json, String key) {
    final value = json?[key];
    if (value is! List) return const <String>[];
    return value.whereType<String>().toList(growable: false);
  }

  /// El número de [key] como `double`, o `null`.
  static double? number(Map<String, dynamic>? json, String key) {
    final value = json?[key];
    return value is num ? value.toDouble() : null;
  }

  /// El número de [key] como `double`, o `0` si falta.
  ///
  /// Solo para distancias y duraciones, donde el cero es un valor legítimo y
  /// distinguible. Nunca para coordenadas.
  static double numberOrZero(Map<String, dynamic>? json, String key) =>
      number(json, key) ?? 0.0;

  /// El entero de [key], o `null`.
  static int? integer(Map<String, dynamic>? json, String key) {
    final value = json?[key];
    return value is num ? value.toInt() : null;
  }

  /// El booleano de [key], o `null`.
  static bool? boolean(Map<String, dynamic>? json, String key) {
    final value = json?[key];
    return value is bool ? value : null;
  }

  /// La marca de tiempo ISO 8601 de [key], o `null` si falta o no se entiende.
  static DateTime? dateTime(Map<String, dynamic>? json, String key) {
    final value = json?[key];
    return value is String ? DateTime.tryParse(value) : null;
  }

  /// La posición de [key], que viene como `[lon, lat]`. `null` si falta.
  static LatLng? latLng(Map<String, dynamic>? json, String key) {
    final value = json?[key];
    if (value is! List || value.length < 2) return null;
    try {
      return LatLng.fromLonLat(value);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  /// La posición de [key], **lanzando** si no se puede leer.
  ///
  /// Se usa donde la posición es la razón de ser del objeto: un resultado de
  /// búsqueda sin coordenada no es un resultado degradado, es un resultado
  /// que no sirve.
  static LatLng requiredLatLng(
    Map<String, dynamic>? json,
    String key,
    String operation,
  ) {
    final value = latLng(json, key);
    if (value == null) {
      throw FormatException(
        'en $operation, el campo "$key" no trae una posición legible. No se '
        'sustituye por LatLng(0, 0): esa coordenada existe —el golfo de '
        'Guinea— y se pintaría en el mapa como si fuera correcta.',
        json?[key]?.toString() ?? 'ausente',
      );
    }
    return value;
  }

  /// El rectángulo de [key], que viene como `[oeste, sur, este, norte]`.
  static LatLngBounds? bounds(Map<String, dynamic>? json, String key) {
    final value = json?[key];
    if (value is! List || value.length < 4) return null;
    try {
      return LatLngBounds.fromBbox(value);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  /// La lista de posiciones de [key], en formato `[[lon, lat], …]`.
  ///
  /// Las entradas ilegibles se descartan en vez de tumbar la lista entera: en
  /// una geometría de mil puntos, perder uno es preferible a perder la línea.
  static List<LatLng> latLngList(Map<String, dynamic>? json, String key) {
    final value = json?[key];
    if (value is! List) return const <LatLng>[];
    final points = <LatLng>[];
    for (final raw in value) {
      if (raw is! List || raw.length < 2) continue;
      try {
        points.add(LatLng.fromLonLat(raw));
      } on FormatException {
        continue;
      } on ArgumentError {
        continue;
      }
    }
    return points;
  }

  /// El valor de enum cuyo `wireName` coincide con la cadena de [key].
  ///
  /// Devuelve `null` ante un valor que el paquete todavía no conoce, en vez de
  /// lanzar: AWS añade valores a los enums de la API sin cambiar de versión.
  static T? enumValue<T extends Enum>(
    Map<String, dynamic>? json,
    String key,
    List<T> values,
    String Function(T) wireName,
  ) {
    final raw = string(json, key);
    if (raw == null) return null;
    for (final value in values) {
      if (wireName(value) == raw) return value;
    }
    return null;
  }
}
