// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:compass_maps_flutter/compass_maps_flutter.dart';
import 'package:compass_maps_google/src/google_map_style.dart';

/// Aplica un estilo JSON de Google Maps sobre el estilo de Amazon Location.
extension GoogleStyleApplier on CompassMapController {
  /// Traduce y aplica [style], y cuenta qué pasó.
  ///
  /// ## Cómo traduce
  ///
  /// 1. Pide al motor la lista de capas del estilo cargado.
  /// 2. Para cada regla de Google, busca las capas cuyo identificador contenga
  ///    alguna de las palabras clave de su `featureType` —la tabla está
  ///    completa y visible en [GoogleMapStyle.featureKeywords]—.
  /// 3. Separa geometría de etiquetas según el `elementType`.
  /// 4. Aplica los *stylers* en el orden que documenta Google: color absoluto,
  ///    tinte, saturación, brillo, gamma, inversión.
  ///
  /// Las transformaciones **relativas** —saturación, brillo, gamma— necesitan
  /// leer el color actual de la capa. Cuando el estilo lo define con una
  /// expresión que depende del zoom —lo normal en las vías—, no hay un color
  /// que transformar y la regla se anota como no aplicada. Es la limitación
  /// principal de esta traducción, y por eso está en el informe.
  ///
  /// ## Cuándo llamarlo
  ///
  /// En `CompassMap.onStyleLoaded`, **no** en `onMapCreated`: un cambio de
  /// `styleUrl` recarga el estilo desde el servidor y deshace todo esto.
  ///
  /// ```dart
  /// CompassMap(
  ///   styleUrl: url,
  ///   initialCameraPosition: camara,
  ///   onMapCreated: (c) => controlador = c,
  ///   onStyleLoaded: () async {
  ///     final informe = await controlador.setGoogleMapStyle(temaOscuro);
  ///     if (!informe.isComplete) debugPrint('$informe');
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
      // `visibility` se resuelve primero y por separado: apagar una capa hace
      // irrelevante todo lo demás que se le pida.
      if (styler.visibility != null) {
        await style.setVisible(layer.id, visible: styler.visibility != 'off');
        changed = true;
        continue;
      }

      if (styler.weight != null && layer.type == StyleLayerType.line) {
        if (await style.setLineWidth(layer.id, styler.weight!)) changed = true;
        continue;
      }

      // Un color absoluto no necesita leer el actual.
      if (styler.color != null &&
          styler.hue == null &&
          styler.saturation == null &&
          styler.lightness == null &&
          styler.gamma == null &&
          !(styler.invertLightness ?? false)) {
        if (await style.setColor(layer.id, styler.color!)) changed = true;
        continue;
      }

      // El resto son transformaciones relativas: hace falta el color actual.
      final current = await style.getColor(layer.id) ?? styler.color;
      if (current == null) continue; // color por expresión: nada que operar
      if (await style.setColor(layer.id, styler.applyTo(current))) {
        changed = true;
      }
    }
    return changed;
  }
}
