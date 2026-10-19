// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'package:nativ_maps_flutter/nativ_maps_flutter.dart';
import 'package:nativ_maps_google/src/google_map_style.dart';

/// Applies a Google Maps JSON style on top of the Amazon Location style.
extension GoogleStyleApplier on NativMapController {
  /// Translates and applies [style], and reports what happened.
  ///
  /// ## How it translates
  ///
  /// 1. It asks the engine for the list of layers in the loaded style.
  /// 2. For each Google rule, it looks for the layers whose id contains any of
  ///    the keywords of its `featureType` —the table is complete and visible
  ///    in [GoogleMapStyle.featureKeywords]—.
  /// 3. It separates geometry from labels according to the `elementType`.
  /// 4. It applies the *stylers* in the order Google documents: absolute
  ///    color, tint, saturation, brightness, gamma, inversion.
  ///
  /// The **relative** transformations —saturation, brightness, gamma— need to
  /// read the layer's current color. When the style defines it with a
  /// zoom-dependent expression —the usual case for roads—, there is no color
  /// to transform and the rule is recorded as not applied. It is the main
  /// limitation of this translation, and that is why it is in the report.
  ///
  /// ## When to call it
  ///
  /// In `NativMap.onStyleLoaded`, **not** in `onMapCreated`: a change of
  /// `styleUrl` reloads the style from the server and undoes all of this.
  ///
  /// ```dart
  /// NativMap(
  ///   styleUrl: url,
  ///   initialCameraPosition: camera,
  ///   onMapCreated: (c) => controller = c,
  ///   onStyleLoaded: () async {
  ///     final report = await controller.setGoogleMapStyle(darkTheme);
  ///     if (!report.isComplete) debugPrint('$report');
  ///   },
  /// )
  /// ```
  Future<GoogleStyleReport> applyGoogleStyle(GoogleMapStyle style) async {
    final layers = await this.style.layers();
    final unmatched = <String>[];
    final touched = <String>{};
    var applied = 0;

    for (final rule in style.rules) {
      final targets = layers
          .where((layer) => GoogleMapStyle.appliesTo(rule, layer.id))
          .toList(growable: false);

      if (targets.isEmpty) {
        unmatched.add(
          '${rule.featureType}/${rule.elementType} — ninguna capa del estilo '
          'de Amazon Location coincide con ese tipo de elemento',
        );
        continue;
      }

      var appliedToAny = false;
      for (final layer in targets) {
        if (await _applyRule(rule, layer)) {
          touched.add(layer.id);
          appliedToAny = true;
        }
      }

      if (appliedToAny) {
        applied++;
      } else {
        unmatched.add(
          '${rule.featureType}/${rule.elementType} — hay ${targets.length} '
          'capa(s) que coinciden, pero su color viene de una expresión que '
          'depende del zoom, así que una transformación relativa no tiene '
          'sobre qué operar',
        );
      }
    }

    return GoogleStyleReport(
      appliedRules: applied,
      unmatchedRules: unmatched,
      touchedLayers: touched.length,
      totalLayers: layers.length,
    );
  }

  Future<bool> _applyRule(GoogleStyleRule rule, StyleLayer layer) async {
    var changed = false;

    for (final styler in rule.stylers) {
      // `visibility` is resolved first and on its own: turning a layer off
      // makes everything else asked of it irrelevant.
      if (styler.visibility != null) {
        await style.setVisible(layer.id, visible: styler.visibility != 'off');
        changed = true;
        continue;
      }

      if (styler.weight != null && layer.type == StyleLayerType.line) {
        if (await style.setLineWidth(layer.id, styler.weight!)) changed = true;
        continue;
      }

      // An absolute color doesn't need to read the current one.
      if (styler.color != null &&
          styler.hue == null &&
          styler.saturation == null &&
          styler.lightness == null &&
          styler.gamma == null &&
          !(styler.invertLightness ?? false)) {
        if (await style.setColor(layer.id, styler.color!)) changed = true;
        continue;
      }

      // The rest are relative transformations: the current color is needed.
      final current = await style.getColor(layer.id) ?? styler.color;
      if (current == null) continue; // color via expression: nothing to work on
      if (await style.setColor(layer.id, styler.applyTo(current))) {
        changed = true;
      }
    }
    return changed;
  }
}
