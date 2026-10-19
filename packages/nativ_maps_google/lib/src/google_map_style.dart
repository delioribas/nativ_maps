// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A Google Maps style rule, exactly as it comes out of the Styling Wizard.
///
/// The format is a list of objects with this shape:
///
/// ```json
/// [
///   {
///     "featureType": "water",
///     "elementType": "geometry.fill",
///     "stylers": [{ "color": "#0e1626" }]
///   }
/// ]
/// ```
///
/// The valid values are in Google's reference: 27 `featureType`s,
/// 9 `elementType`s and 8 *stylers*.
@immutable
class GoogleStyleRule {
  /// Creates the rule.
  const GoogleStyleRule({
    this.featureType = 'all',
    this.elementType = 'all',
    this.stylers = const <GoogleStyler>[],
  });

  /// Reads the rule from an object in Google's JSON.
  factory GoogleStyleRule.fromJson(Map<String, dynamic> json) =>
      GoogleStyleRule(
        featureType: json['featureType'] as String? ?? 'all',
        elementType: json['elementType'] as String? ?? 'all',
        stylers: <GoogleStyler>[
          for (final styler
              in (json['stylers'] as List<dynamic>? ?? const <dynamic>[]))
            if (styler is Map<String, dynamic>) GoogleStyler.fromJson(styler),
        ],
      );

  /// What it applies to: `water`, `road.highway`, `poi.park`, `all`…
  final String featureType;

  /// Which part of that: `geometry.fill`, `labels.text.stroke`, `all`…
  final String elementType;

  /// What is done to it.
  final List<GoogleStyler> stylers;

  @override
  String toString() => 'GoogleStyleRule($featureType/$elementType)';
}

/// A Google style transformation.
///
/// The eight that Google defines, with their ranges:
///
/// | Styler | Range | What it does |
/// |---|---|---|
/// | `color` | `#RRGGBB` | sets the color, absolute |
/// | `hue` | `#RRGGBB` | tints while keeping the lightness |
/// | `saturation` | −100 to 100 | changes the saturation |
/// | `lightness` | −100 to 100 | changes the brightness |
/// | `gamma` | 0.01 to 10 | non-linear brightness adjustment |
/// | `invert_lightness` | boolean | inverts the brightness |
/// | `visibility` | `on`/`off`/`simplified` | whether it is drawn |
/// | `weight` | ≥ 0 | thickness in pixels |
@immutable
class GoogleStyler {
  /// Creates the styler.
  const GoogleStyler({
    this.color,
    this.hue,
    this.saturation,
    this.lightness,
    this.gamma,
    this.invertLightness,
    this.visibility,
    this.weight,
  });

  /// Reads the styler from an object in Google's JSON.
  factory GoogleStyler.fromJson(Map<String, dynamic> json) => GoogleStyler(
    color: _parseColor(json['color']),
    hue: _parseColor(json['hue']),
    saturation: _parseDouble(json['saturation']),
    lightness: _parseDouble(json['lightness']),
    gamma: _parseDouble(json['gamma']),
    invertLightness: json['invert_lightness'] as bool?,
    visibility: json['visibility'] as String?,
    weight: _parseDouble(json['weight']),
  );

  /// The absolute color.
  final Color? color;

  /// The tint, applied while keeping the lightness.
  final Color? hue;

  /// Saturation change, from −100 to 100.
  final double? saturation;

  /// Brightness change, from −100 to 100.
  final double? lightness;

  /// Gamma correction, from 0.01 to 10.
  final double? gamma;

  /// Is the brightness inverted?
  final bool? invertLightness;

  /// `on`, `off` or `simplified`.
  final String? visibility;

  /// Thickness in pixels.
  final double? weight;

  /// Does this styler hide what it touches?
  bool get hidesFeature => visibility == 'off';

  /// Applies this transformation to [base] and returns the resulting color.
  ///
  /// The order is the one Google documents: first the absolute color, then the
  /// tint, then saturation, brightness, gamma and inversion. Changing the order
  /// gives different results, and noticeably different with gamma.
  Color applyTo(Color base) {
    var result = color ?? base;

    if (hue != null) {
      // Google's tint changes the hue and keeps lightness and saturation.
      // That is the difference from `color`, which overrides all of them.
      final target = HSLColor.fromColor(hue!);
      final current = HSLColor.fromColor(result);
      result = current.withHue(target.hue).toColor();
    }

    var hsl = HSLColor.fromColor(result);

    if (saturation != null) {
      hsl = hsl.withSaturation(
        (hsl.saturation + saturation! / 100.0).clamp(0.0, 1.0),
      );
    }
    if (lightness != null) {
      hsl = hsl.withLightness(
        (hsl.lightness + lightness! / 100.0).clamp(0.0, 1.0),
      );
    }
    if (gamma != null && gamma! > 0) {
      hsl = hsl.withLightness(
        math.pow(hsl.lightness, 1.0 / gamma!).toDouble().clamp(0.0, 1.0),
      );
    }
    if (invertLightness ?? false) {
      hsl = hsl.withLightness(1.0 - hsl.lightness);
    }
    return hsl.toColor();
  }

  static Color? _parseColor(Object? raw) {
    if (raw is! String) return null;
    var hex = raw.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return null;
    final value = int.tryParse(hex, radix: 16);
    return value == null ? null : Color(value);
  }

  static double? _parseDouble(Object? raw) => switch (raw) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s),
    _ => null,
  };
}

/// A complete Google Maps style, already parsed.
///
/// ## Why it exists
///
/// Projects coming from `google_maps_flutter` almost always bring a JSON
/// style: a dark theme taken from Snazzy Maps, a map with the points of
/// interest turned off, a corporate palette. Without this, migrating would
/// mean redoing that style from scratch against the MapLibre specification.
///
/// ## ⚠️ It is a translation, not an equivalence
///
/// Google and MapLibre organize layers differently and with different names.
/// This translation works **by matching layer names**: it looks in the Amazon
/// Location style for the layers whose id contains the word from Google's
/// `featureType`.
///
/// It works well for what is used 95 % of the time —water, roads, labels,
/// points of interest, terrain— and cannot work for Google's fine
/// distinctions, such as separating `road.highway.controlled_access` from
/// `road.highway`.
///
/// That is why [GoogleStyleReport] exists: applying the style **says which
/// rules it applied and which found no layer**, instead of failing silently.
/// The alternative —swallowing the rules that don't fit— is the fake
/// compatibility that Rule 2 of the design forbids.
@immutable
class GoogleMapStyle {
  /// Creates the style from its rules.
  const GoogleMapStyle(this.rules);

  /// Reads a style from the JSON of Google's Styling Wizard.
  ///
  /// Throws [FormatException] if it is not a list of objects.
  factory GoogleMapStyle.parse(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! List) {
      throw FormatException(
        'un estilo de Google Maps es una lista de reglas en la raíz; llegó '
        '${decoded.runtimeType}',
        json,
      );
    }
    return GoogleMapStyle(<GoogleStyleRule>[
      for (final rule in decoded)
        if (rule is Map<String, dynamic>) GoogleStyleRule.fromJson(rule),
    ]);
  }

  /// The rules, in the order they are applied.
  ///
  /// The order matters: a later rule on the same layer wins.
  final List<GoogleStyleRule> rules;

  /// The words that identify each Google `featureType` inside the layer ids
  /// of a MapLibre style.
  ///
  /// This table **is** the translation, and it is where all its imprecision
  /// lives. It is left visible on purpose: anyone who needs to fine-tune for a
  /// specific style can read it and know exactly what is being searched for.
  static const Map<String, List<String>>
  featureKeywords = <String, List<String>>{
    'all': <String>[],
    'administrative': <String>['admin', 'boundary', 'border'],
    'administrative.country': <String>['admin-0', 'country'],
    'administrative.province': <String>['admin-1', 'state', 'province'],
    'administrative.locality': <String>['place', 'city', 'town', 'locality'],
    'administrative.neighborhood': <String>['neighbourhood', 'neighborhood'],
    'administrative.land_parcel': <String>['parcel'],
    'landscape': <String>['land', 'landuse', 'landcover', 'background'],
    'landscape.man_made': <String>['building', 'landuse'],
    'landscape.natural': <String>['landcover', 'natural', 'wood', 'grass'],
    'landscape.natural.landcover': <String>['landcover'],
    'landscape.natural.terrain': <String>['hillshade', 'terrain', 'contour'],
    'poi': <String>['poi'],
    'poi.attraction': <String>['poi'],
    'poi.business': <String>['poi'],
    'poi.government': <String>['poi'],
    'poi.medical': <String>['poi'],
    'poi.park': <String>['park', 'grass', 'garden'],
    'poi.place_of_worship': <String>['poi'],
    'poi.school': <String>['poi'],
    'poi.sports_complex': <String>['pitch', 'sport'],
    'road': <String>['road', 'street', 'highway', 'bridge', 'tunnel'],
    'road.arterial': <String>['secondary', 'tertiary', 'arterial'],
    'road.highway': <String>['motorway', 'trunk', 'highway'],
    'road.highway.controlled_access': <String>['motorway'],
    'road.local': <String>['minor', 'service', 'residential', 'local'],
    'transit': <String>['transit', 'rail', 'ferry', 'aeroway'],
    'transit.line': <String>['rail', 'transit-line', 'ferry'],
    'transit.station': <String>['station'],
    'transit.station.airport': <String>['aeroway', 'airport'],
    'transit.station.bus': <String>['bus'],
    'transit.station.rail': <String>['rail'],
    'water': <String>['water', 'ocean', 'sea', 'river', 'lake'],
  };

  /// Does [layerId] match this rule's `featureType`?
  ///
  /// `all` matches everything. An unknown `featureType` matches nothing, and
  /// that shows up in the report.
  static bool matchesFeature(String featureType, String layerId) {
    if (featureType == 'all') return true;
    final keywords = featureKeywords[featureType];
    if (keywords == null || keywords.isEmpty) return featureType == 'all';
    final lower = layerId.toLowerCase();
    return keywords.any(lower.contains);
  }

  /// Is [layerId] a label layer?
  ///
  /// It is needed to separate `geometry` from `labels`, which is the most used
  /// `elementType` distinction: almost every dark theme needs it.
  static bool isLabelLayer(String layerId) {
    final lower = layerId.toLowerCase();
    return lower.contains('label') ||
        lower.contains('name') ||
        lower.contains('text') ||
        lower.contains('shield') ||
        lower.contains('icon');
  }

  /// Does this rule apply to [layerId]?
  static bool appliesTo(GoogleStyleRule rule, String layerId) {
    if (!matchesFeature(rule.featureType, layerId)) return false;
    final isLabel = isLabelLayer(layerId);
    return switch (rule.elementType) {
      'all' => true,
      'labels' ||
      'labels.text' ||
      'labels.text.fill' ||
      'labels.text.stroke' ||
      'labels.icon' => isLabel,
      'geometry' || 'geometry.fill' || 'geometry.stroke' => !isLabel,
      _ => true,
    };
  }

  @override
  String toString() => 'GoogleMapStyle(${rules.length} reglas)';
}

/// What happened when applying a Google style.
///
/// It exists because a translation that silently swallows what it doesn't
/// understand is worse than none: whoever migrates believes their theme is
/// applied and doesn't know what is missing. With this they know exactly which
/// rules found no layer.
@immutable
class GoogleStyleReport {
  /// Creates the report.
  const GoogleStyleReport({
    required this.appliedRules,
    required this.unmatchedRules,
    required this.touchedLayers,
    required this.totalLayers,
  });

  /// How many rules found at least one layer.
  final int appliedRules;

  /// The rules that found no layer, with their description.
  ///
  /// **This is what you need to read.** Each entry is a part of the theme that
  /// was not applied and that, if it matters, has to be solved by hand against
  /// the MapLibre style.
  final List<String> unmatchedRules;

  /// How many layers were modified.
  final int touchedLayers;

  /// How many layers the style had.
  final int totalLayers;

  /// Was everything applied?
  bool get isComplete => unmatchedRules.isEmpty;

  /// What fraction of the rules found a target.
  double get coverage {
    final total = appliedRules + unmatchedRules.length;
    return total == 0 ? 1.0 : appliedRules / total;
  }

  @override
  String toString() {
    final buffer = StringBuffer(
      'GoogleStyleReport: $appliedRules de '
      '${appliedRules + unmatchedRules.length} reglas aplicadas '
      '(${(coverage * 100).round()} %), $touchedLayers de $totalLayers capas '
      'modificadas.',
    );
    if (unmatchedRules.isNotEmpty) {
      buffer.write('\nSin capa que coincida:');
      for (final rule in unmatchedRules) {
        buffer.write('\n  · $rule');
      }
    }
    return buffer.toString();
  }
}
