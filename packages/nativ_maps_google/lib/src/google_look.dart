// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'package:flutter/foundation.dart';
import 'package:nativ_maps_flutter/nativ_maps_flutter.dart';
import 'package:nativ_maps_google/src/google_map_style.dart';

/// A rule of the look: which layers it applies to and what paint it gives them.
@immutable
class GoogleLookRule {
  /// Creates the rule.
  const GoogleLookRule(this.layers, this.paint);

  /// Regular expression over the layer id. It is anchored on both ends: `land`
  /// matches `land` and not `landuse_urban`.
  final String layers;

  /// The paint properties, with their MapLibre names (`line-color`,
  /// `fill-color`…). The values can be expressions.
  final Map<String, Object> paint;

  /// Does it apply to [layerId]?
  bool matches(String layerId) => RegExp('^(?:$layers)\$').hasMatch(layerId);

  @override
  String toString() => 'GoogleLookRule($layers)';
}

/// The look of current Google Maps on top of Amazon Location's standard
/// style.
///
/// ## Where the colors come from
///
/// From an eyedropper over screenshots of the Google Maps app for Android
/// (October 2026), in Quito, at z12, z15 and z17. It is the palette of the
/// November 2023 redesign: bluish-gray streets rather than white ones, mint
/// green parks, light-blue water and shops in beige.
///
/// ## What doesn't change
///
/// - **The typeface.** Google uses Roboto; Amazon Location's glyph server only
///   serves Amazon Ember and Noto Sans.
/// - **The point-of-interest icons.** They are the ones from the AWS style;
///   only the text color changes, per category, as Google does.
/// - **The data.** AWS draws with its providers' data: there will be
///   businesses, buildings or names that don't match Google's.
///
/// ## Against which style
///
/// Only [MapStyle.standard] in the light scheme. The rules look for that
/// style's layer names; on another one, almost none finds a target and the
/// report says so.
abstract final class GoogleLook {
  /// The light palette, in the order it is applied.
  static const List<GoogleLookRule> light = <GoogleLookRule>[
    // ── Land, water and vegetation
    GoogleLookRule('land', <String, Object>{
      'background-color': <Object>[
        'interpolate',
        <Object>['linear'],
        <Object>['zoom'],
        15,
        _land,
        17,
        _landHigh,
      ],
    }),
    GoogleLookRule('water_fill|water_ocean', <String, Object>{
      'fill-color': _water,
    }),
    GoogleLookRule('water_waterway', <String, Object>{'line-color': _water}),
    // AWS's distinction by type of green area is kept; only the colors
    // change. Forest and scrub are lighter than a park, as in Google at z12.
    GoogleLookRule('landuse_greenspace', <String, Object>{
      'fill-color': <Object>[
        'case',
        <Object>[
          'match',
          <Object>['get', 'kind'],
          <Object>['forest', 'natural_forest', 'natural_wood', 'wood'],
          true,
          false,
        ],
        _natural,
        <Object>[
          'match',
          <Object>['get', 'kind'],
          <Object>['sports_centre', 'zoo', 'golf_course'],
          true,
          false,
        ],
        _parkDark,
        <Object>[
          '==',
          <Object>['get', 'kind'],
          'cemetery',
        ],
        _natural,
        _park,
      ],
    }),
    GoogleLookRule('landuse_misc', <String, Object>{
      'fill-color': <Object>[
        'match',
        <Object>['get', 'kind'],
        <Object>['commercial', 'retail'],
        _commercial,
        'military',
        'hsl(40, 38%, 96%)',
        'hsl(227, 8%, 94%)',
      ],
    }),
    GoogleLookRule(
      'landuse_public-complex|landuse_public-complex-above',
      <String, Object>{
        'fill-color': <Object>[
          'match',
          <Object>['get', 'kind'],
          'hospital',
          _hospital,
          'hsl(40, 60%, 94%)',
        ],
      },
    ),

    // ── Buildings
    GoogleLookRule('building_fill|building_fill-above-tunnel', <String, Object>{
      'fill-color': <Object>[
        'interpolate',
        <Object>['linear'],
        <Object>['zoom'],
        15,
        _buildingLow,
        17,
        _building,
      ],
    }),
    GoogleLookRule('building_line', <String, Object>{
      'line-color': _buildingLine,
    }),

    // ── Roads. AWS paints them the opposite way to Google: a dark line with
    // a white halo. Google uses a light line with a darker edge.
    GoogleLookRule(
      '(road|bridge)_(service|minor|tertiary|tertiary-link|primary|'
      'primary-link)',
      <String, Object>{'line-color': _road},
    ),
    GoogleLookRule(
      '(road|bridge)_(service|minor|tertiary|tertiary-link)-casing',
      <String, Object>{'line-color': _minorEdge},
    ),
    GoogleLookRule(
      '(road|bridge)_(primary|primary-link)-casing',
      <String, Object>{'line-color': _roadEdge},
    ),
    GoogleLookRule('(road|bridge)_motorway-trunk(-link)?', <String, Object>{
      'line-color': _highway,
    }),
    GoogleLookRule(
      '(road|bridge)_motorway-trunk(-link)?-casing',
      <String, Object>{'line-color': _highwayEdge},
    ),
    GoogleLookRule(
      'tunnel_(service|minor|tertiary|tertiary-link|primary|primary-link|'
      'motorway-trunk|motorway-trunk-link)',
      <String, Object>{'line-color': _tunnel},
    ),
    GoogleLookRule(
      'tunnel_(service|minor|tertiary|tertiary-link|primary|primary-link|'
      'motorway-trunk|motorway-trunk-link)-casing',
      <String, Object>{'line-color': _road},
    ),

    // ── Labels. Google colors each place's text by category. AWS writes
    // street names in uppercase; Google doesn't. That is a layout property,
    // but it travels down the same path.
    GoogleLookRule('road_label_(service|small|medium)', <String, Object>{
      'text-color': _labelRoad,
      'text-transform': 'none',
    }),
    GoogleLookRule('road_label_large', <String, Object>{
      'text-color': _labelRoadLarge,
      'text-transform': 'none',
    }),
    GoogleLookRule('place_label_locality_settlement', <String, Object>{
      'text-color': _labelDistrict,
    }),
    GoogleLookRule(
      'poi_landuse_park(_lowzoom)?|nationalpark_label(_lowzoom)?|'
      'poi_550_leisure_outdoor',
      <String, Object>{'text-color': _labelPark},
    ),
    GoogleLookRule('poi_600_shopping', <String, Object>{
      'text-color': _labelShopping,
    }),
    GoogleLookRule('poi_300_sights_museums', <String, Object>{
      'text-color': _labelAttraction,
    }),
    GoogleLookRule('poi_100_food_drink', <String, Object>{
      'text-color': _labelFood,
    }),
    GoogleLookRule(
      'poi_700_business_services(_generic)?|poi_900_areas_buildings',
      <String, Object>{'text-color': _labelGeneric},
    ),
  ];

  /// Which paint each layer in [layerIds] gets, and which rules found none.
  ///
  /// This is the pure part: it doesn't touch the engine. If two rules set the
  /// same property on a layer, the last one wins.
  static ({
    Map<String, Map<String, Object>> layers,
    List<GoogleLookRule> unmatched,
  })
  plan(Iterable<String> layerIds, {List<GoogleLookRule> rules = light}) {
    final ids = layerIds.toList(growable: false);
    final layers = <String, Map<String, Object>>{};
    final unmatched = <GoogleLookRule>[];
    for (final rule in rules) {
      final targets = ids.where(rule.matches).toList(growable: false);
      if (targets.isEmpty) {
        unmatched.add(rule);
        continue;
      }
      for (final id in targets) {
        (layers[id] ??= <String, Object>{}).addAll(rule.paint);
      }
    }
    return (layers: layers, unmatched: unmatched);
  }

  // Measured in the Google Maps app; see the class documentation.
  static const String _land = '#F5F3F3';
  static const String _landHigh = '#F8F7F7';
  static const String _water = '#90DAEE';
  static const String _park = '#C3F1D5';
  static const String _parkDark = '#A9EAC2';
  static const String _natural = '#CDF1DC';
  static const String _commercial = '#F8F0DE';
  static const String _hospital = '#FCE8E6';
  static const String _buildingLow = '#EFEDED';
  static const String _building = '#E8E9ED';
  static const String _buildingLine = '#D6D9E6';
  static const String _road = '#D8E0E7';
  static const String _roadEdge = '#C7D0D7';
  static const String _minorEdge = '#CFD9E3';
  static const String _highway = '#ABBCD6';
  static const String _highwayEdge = '#7D8FB8';
  static const String _tunnel = '#E6EBEF';
  static const String _labelRoad = '#4D5D6F';
  static const String _labelRoadLarge = '#354557';
  static const String _labelDistrict = '#2F3034';
  static const String _labelPark = '#19865F';
  static const String _labelShopping = '#1A73E8';
  static const String _labelAttraction = '#8242D3';
  static const String _labelFood = '#D65900';
  static const String _labelGeneric = '#546E7A';
}

/// Applies [GoogleLook] on top of the loaded style.
extension GoogleLookApplier on NativMapController {
  /// Repaints the map with Google's palette, and reports what happened.
  ///
  /// ## When to call it
  ///
  /// In `NativMap.onStyleLoaded`, **not** in `onMapCreated`: a change of
  /// `styleUrl` reloads the style from the server and undoes all of this.
  /// For a moment the original style shows.
  ///
  /// ```dart
  /// NativMap(
  ///   styleUrl: maps.maps.styleDescriptorUrl(MapStyle.standard)!,
  ///   initialCameraPosition: camera,
  ///   onMapCreated: (c) => controller = c,
  ///   onStyleLoaded: () async {
  ///     final report = await controller.applyGoogleLook();
  ///     if (!report.isComplete) debugPrint('$report');
  ///   },
  /// )
  /// ```
  ///
  /// Only for [MapStyle.standard] in the light scheme: on the dark one it
  /// would paint daytime colors.
  Future<GoogleStyleReport> applyGoogleLook({
    List<GoogleLookRule> rules = GoogleLook.light,
  }) async {
    final ids = await style.layerIds();
    final plan = GoogleLook.plan(ids, rules: rules);
    final problems = <String>[
      for (final rule in plan.unmatched)
        '${rule.layers} — ninguna capa coincide; ¿es MapStyle.standard?',
    ];

    var touched = 0;
    for (final MapEntry(key: id, value: paint) in plan.layers.entries) {
      if (await style.setPaintProperties(id, paint)) {
        touched++;
      } else {
        problems.add('$id — el motor rechazó la pintura');
      }
    }

    return GoogleStyleReport(
      appliedRules: rules.length - plan.unmatched.length,
      unmatchedRules: problems,
      touchedLayers: touched,
      totalLayers: ids.length,
    );
  }
}
