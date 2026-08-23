// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Una regla de estilo de Google Maps, tal como sale del Styling Wizard.
///
/// El formato es una lista de objetos con esta forma:
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
/// Los valores válidos están en la referencia de Google: 27 `featureType`,
/// 9 `elementType` y 8 *stylers*.
@immutable
class GoogleStyleRule {
  /// Crea la regla.
  const GoogleStyleRule({
    this.featureType = 'all',
    this.elementType = 'all',
    this.stylers = const <GoogleStyler>[],
  });

  /// Lee la regla de un objeto del JSON de Google.
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

  /// A qué se aplica: `water`, `road.highway`, `poi.park`, `all`…
  final String featureType;

  /// A qué parte de eso: `geometry.fill`, `labels.text.stroke`, `all`…
  final String elementType;

  /// Qué se le hace.
  final List<GoogleStyler> stylers;

  @override
  String toString() => 'GoogleStyleRule($featureType/$elementType)';
}

/// Una transformación de estilo de Google.
///
/// Los ocho que define Google, con sus rangos:
///
/// | Styler | Rango | Qué hace |
/// |---|---|---|
/// | `color` | `#RRGGBB` | fija el color, absoluto |
/// | `hue` | `#RRGGBB` | tiñe conservando la luminosidad |
/// | `saturation` | −100 a 100 | cambia la saturación |
/// | `lightness` | −100 a 100 | cambia el brillo |
/// | `gamma` | 0,01 a 10 | ajuste no lineal del brillo |
/// | `invert_lightness` | booleano | invierte el brillo |
/// | `visibility` | `on`/`off`/`simplified` | si se dibuja |
/// | `weight` | ≥ 0 | grosor en píxeles |
@immutable
class GoogleStyler {
  /// Crea el styler.
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

  /// Lee el styler de un objeto del JSON de Google.
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

  /// El color absoluto.
  final Color? color;

  /// El tinte que se aplica conservando la luminosidad.
  final Color? hue;

  /// Cambio de saturación, de −100 a 100.
  final double? saturation;

  /// Cambio de brillo, de −100 a 100.
  final double? lightness;

  /// Corrección gamma, de 0,01 a 10.
  final double? gamma;

  /// ¿Se invierte el brillo?
  final bool? invertLightness;

  /// `on`, `off` o `simplified`.
  final String? visibility;

  /// Grosor en píxeles.
  final double? weight;

  /// ¿Este styler oculta lo que toca?
  bool get hidesFeature => visibility == 'off';

  /// Aplica esta transformación a [base] y devuelve el color resultante.
  ///
  /// El orden es el que documenta Google: primero el color absoluto, luego el
  /// tinte, después saturación, brillo, gamma e inversión. Cambiar el orden da
  /// resultados distintos, y notablemente distintos con gamma.
  Color applyTo(Color base) {
    var result = color ?? base;

    if (hue != null) {
      // El tinte de Google cambia el matiz y conserva luminosidad y
      // saturación. Es la diferencia con `color`, que las pisa todas.
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

/// Un estilo completo de Google Maps, ya leído.
///
/// ## Para qué existe
///
/// Los proyectos que vienen de `google_maps_flutter` casi siempre traen un
/// estilo JSON: un tema oscuro sacado de Snazzy Maps, un mapa con los puntos
/// de interés apagados, una paleta corporativa. Sin esto, migrar significaría
/// rehacer ese estilo desde cero contra la especificación de MapLibre.
///
/// ## ⚠️ Es una traducción, no una equivalencia
///
/// Google y MapLibre organizan las capas de forma distinta y con nombres
/// distintos. Esta traducción va **por coincidencia de nombre de capa**: busca
/// en el estilo de Amazon Location las capas cuyo identificador contiene la
/// palabra del `featureType` de Google.
///
/// Funciona bien para lo que se usa el 95 % de las veces —agua, vías,
/// etiquetas, puntos de interés, terreno— y no puede funcionar para las
/// distinciones finas de Google, como separar `road.highway.controlled_access`
/// de `road.highway`.
///
/// Por eso [GoogleStyleReport] existe: la aplicación **dice qué reglas
/// aplicó y cuáles no encontraron capa**, en vez de fallar en silencio. La
/// alternativa —tragarse las reglas que no encajan— es la compatibilidad de
/// mentira que la Regla 2 del diseño prohíbe.
@immutable
class GoogleMapStyle {
  /// Crea el estilo a partir de sus reglas.
  const GoogleMapStyle(this.rules);

  /// Lee un estilo del JSON del Styling Wizard de Google.
  ///
  /// Lanza [FormatException] si no es una lista de objetos.
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

  /// Las reglas, en el orden en que se aplican.
  ///
  /// El orden importa: una regla posterior sobre la misma capa gana.
  final List<GoogleStyleRule> rules;

  /// Las palabras que identifican cada `featureType` de Google dentro de los
  /// identificadores de capa de un estilo MapLibre.
  ///
  /// Esta tabla **es** la traducción, y es donde está toda su imprecisión. Se
  /// deja visible a propósito: quien necesite afinar para un estilo concreto
  /// puede leerla y saber exactamente qué se está buscando.
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

  /// ¿Coincide [layerId] con el `featureType` de esta regla?
  ///
  /// `all` coincide con todo. Un `featureType` desconocido no coincide con
  /// nada, y eso se refleja en el informe.
  static bool matchesFeature(String featureType, String layerId) {
    if (featureType == 'all') return true;
    final keywords = featureKeywords[featureType];
    if (keywords == null || keywords.isEmpty) return featureType == 'all';
    final lower = layerId.toLowerCase();
    return keywords.any(lower.contains);
  }

  /// ¿Es [layerId] una capa de etiquetas?
  ///
  /// Hace falta para separar `geometry` de `labels`, que es la distinción de
  /// `elementType` que más se usa: casi todos los temas oscuros la necesitan.
  static bool isLabelLayer(String layerId) {
    final lower = layerId.toLowerCase();
    return lower.contains('label') ||
        lower.contains('name') ||
        lower.contains('text') ||
        lower.contains('shield') ||
        lower.contains('icon');
  }

  /// ¿Se aplica esta regla a [layerId]?
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

/// Qué pasó al aplicar un estilo de Google.
///
/// Existe porque una traducción que se traga en silencio lo que no entiende es
/// peor que ninguna: quien migra cree que su tema está aplicado y no sabe qué
/// falta. Con esto sabe exactamente qué reglas no encontraron capa.
@immutable
class GoogleStyleReport {
  /// Crea el informe.
  const GoogleStyleReport({
    required this.appliedRules,
    required this.unmatchedRules,
    required this.touchedLayers,
    required this.totalLayers,
  });

  /// Cuántas reglas encontraron al menos una capa.
  final int appliedRules;

  /// Las reglas que no encontraron ninguna capa, con su descripción.
  ///
  /// **Esto es lo que hay que leer.** Cada entrada es una parte del tema que
  /// no se aplicó y que, si importa, hay que resolver a mano contra el estilo
  /// de MapLibre.
  final List<String> unmatchedRules;

  /// Cuántas capas se modificaron.
  final int touchedLayers;

  /// Cuántas capas tenía el estilo.
  final int totalLayers;

  /// ¿Se aplicó todo?
  bool get isComplete => unmatchedRules.isEmpty;

  /// Qué fracción de las reglas encontró destino.
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
