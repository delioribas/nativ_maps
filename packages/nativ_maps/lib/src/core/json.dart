// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/lat_lng.dart';

/// Lenient readers for the service responses.
///
/// ## Why they tolerate instead of demand
///
/// Amazon Location adds fields without notice and not every data provider
/// returns the same ones. A strict reader turns "HERE started sending a new
/// field" into "the app stopped opening the map", and that is worse than
/// ignoring what it does not understand.
///
/// The tolerance has one specific limit, and it is the position:
/// [Json.requiredLatLng] **throws**. An unreadable position cannot be replaced
/// with a default value, because `LatLng(0, 0)` exists —it is in the Gulf of
/// Guinea— and it is drawn on the map exactly like a correct one.
@internal
abstract final class Json {
  /// The map at [key], or `null` if it is missing or not a map.
  static Map<String, dynamic>? object(Map<String, dynamic>? json, String key) {
    final value = json?[key];
    return value is Map<String, dynamic> ? value : null;
  }

  /// The list of maps at [key], empty if it is missing.
  static List<Map<String, dynamic>> objects(
    Map<String, dynamic>? json,
    String key,
  ) {
    final value = json?[key];
    if (value is! List) return const <Map<String, dynamic>>[];
    return value.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  /// The string at [key], or `null`. An empty string counts as missing: the
  /// service returns `""` in fields that do not apply, and propagating it
  /// forces every call site to check two things.
  static String? string(Map<String, dynamic>? json, String key) {
    final value = json?[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  /// The list of strings at [key], empty if it is missing.
  static List<String> strings(Map<String, dynamic>? json, String key) {
    final value = json?[key];
    if (value is! List) return const <String>[];
    return value.whereType<String>().toList(growable: false);
  }

  /// The number at [key] as a `double`, or `null`.
  static double? number(Map<String, dynamic>? json, String key) {
    final value = json?[key];
    return value is num ? value.toDouble() : null;
  }

  /// The number at [key] as a `double`, or `0` if it is missing.
  ///
  /// Only for distances and durations, where zero is a legitimate and
  /// distinguishable value. Never for coordinates.
  static double numberOrZero(Map<String, dynamic>? json, String key) =>
      number(json, key) ?? 0.0;

  /// The integer at [key], or `null`.
  static int? integer(Map<String, dynamic>? json, String key) {
    final value = json?[key];
    return value is num ? value.toInt() : null;
  }

  /// The boolean at [key], or `null`.
  static bool? boolean(Map<String, dynamic>? json, String key) {
    final value = json?[key];
    return value is bool ? value : null;
  }

  /// The ISO 8601 timestamp at [key], or `null` if missing or unparseable.
  static DateTime? dateTime(Map<String, dynamic>? json, String key) {
    final value = json?[key];
    return value is String ? DateTime.tryParse(value) : null;
  }

  /// The position at [key], which comes as `[lon, lat]`. `null` if missing.
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

  /// The position at [key], **throwing** if it cannot be read.
  ///
  /// Used where the position is the object's reason to exist: a search result
  /// without a coordinate is not a degraded result, it is a useless one.
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

  /// The rectangle at [key], which comes as `[west, south, east, north]`.
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

  /// The list of positions at [key], in `[[lon, lat], …]` format.
  ///
  /// Unreadable entries are discarded instead of bringing down the whole list:
  /// in a thousand-point geometry, losing one is better than losing the line.
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

  /// The enum value whose `wireName` matches the string at [key].
  ///
  /// Returns `null` for a value the package does not know yet, instead of
  /// throwing: AWS adds values to the API enums without changing version.
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
