// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
// `meta` is imported explicitly, even though on Flutter 3.44+ the linter flags
// it as redundant: `package:flutter/foundation.dart` **does not re-export
// `@internal`** until recent versions, and this package declares Flutter 3.32
// as its floor. Without this import, anyone using it on 3.32 runs into twelve
// `undefined_annotation` errors.
// ignore: unnecessary_import
import 'package:meta/meta.dart';

/// What kind of layer it is, within a MapLibre style.
enum StyleLayerType {
  /// The fill of an area.
  fill('fill'),

  /// A line.
  line('line'),

  /// An icon or a label.
  symbol('symbol'),

  /// A circle with a radius in pixels.
  circle('circle'),

  /// The map's background color.
  background('background'),

  /// An image layer.
  raster('raster'),

  /// Relief shading.
  hillshade('hillshade'),

  /// A heatmap.
  heatmap('heatmap'),

  /// Extruded buildings.
  fillExtrusion('fill-extrusion');

  const StyleLayerType(this.wireName);

  /// The name in the style specification.
  final String wireName;

  /// The type whose name is [wireName], or `null` if it isn't recognized.
  static StyleLayerType? fromWireName(String? name) {
    if (name == null) return null;
    for (final type in values) {
      if (type.wireName == name) return type;
    }
    return null;
  }

  /// The main color property of this layer type.
  ///
  /// It saves you from having to remember that a fill uses `fill-color`, a
  /// line `line-color`, a label `text-color` and the background
  /// `background-color`. Getting it wrong raises no error: the property is
  /// ignored and the color doesn't change, which is worse.
  String? get colorProperty => switch (this) {
    StyleLayerType.fill => 'fill-color',
    StyleLayerType.line => 'line-color',
    StyleLayerType.symbol => 'text-color',
    StyleLayerType.circle => 'circle-color',
    StyleLayerType.background => 'background-color',
    StyleLayerType.fillExtrusion => 'fill-extrusion-color',
    StyleLayerType.raster ||
    StyleLayerType.hillshade ||
    StyleLayerType.heatmap => null,
  };
}

/// A style layer, with what you need to tweak it.
@immutable
class StyleLayer {
  /// Creates the layer description.
  const StyleLayer({required this.id, required this.type, this.sourceLayer});

  /// The layer's identifier within the style.
  final String id;

  /// What kind of layer it is.
  final StyleLayerType? type;

  /// The source layer within the tile source, if it has one.
  final String? sourceLayer;

  @override
  String toString() => 'StyleLayer($id, ${type?.wireName ?? '?'})';
}

/// Tweaks the map style at runtime.
///
/// You get it from `NativMapController.style`.
///
/// ## What it's for
///
/// The Amazon Location style comes ready-made, and it's almost always what you
/// want. This exists for the three things you almost always need on top:
///
/// - **Turning off what gets in the way.** A map that's the background for
///   your own data doesn't need points of interest or shop labels.
/// - **Matching the palette** to the app's, without redoing the whole style.
/// - **Applying a theme that already exists**, which is what the
///   `nativ_maps_google` package does when it translates a Google JSON style.
///
/// ## What changes here doesn't survive a style change
///
/// Changing `styleUrl` reloads the style from the server and undoes all of
/// this. You have to apply it again in `NativMap.onStyleLoaded`, which is
/// called on **every** load, and not just the first, precisely for this
/// reason.
class StyleEditor {
  /// Internal use: the controller builds it.
  @internal
  StyleEditor(this._native);

  final ml.MapLibreMapController _native;

  /// Every layer in the style, in the order they're drawn.
  ///
  /// It's the first thing to look at when tweaking a style: the provider picks
  /// the names and there's no way to guess them.
  ///
  /// ```dart
  /// for (final layer in await controller.style.layers()) {
  ///   debugPrint('$layer');
  /// }
  /// ```
  Future<List<StyleLayer>> layers() async {
    final ids = await _native.getLayerIds();
    final result = <StyleLayer>[];
    for (final raw in ids) {
      if (raw is! String) continue;
      final properties = await _properties(raw);
      result.add(
        StyleLayer(
          id: raw,
          type: StyleLayerType.fromWireName(properties?['type'] as String?),
          sourceLayer: properties?['source-layer'] as String?,
        ),
      );
    }
    return result;
  }

  /// Just the identifiers, without looking up each one's type.
  ///
  /// Much faster than [layers] when you only need the name: a style easily has
  /// two hundred layers, and [layers] crosses the platform channel once for
  /// each one.
  Future<List<String>> layerIds() async {
    final ids = await _native.getLayerIds();
    return ids.whereType<String>().toList(growable: false);
  }

  /// Turns a layer on or off.
  ///
  /// Turning it off is better than deleting it: the layer is still there and
  /// can be turned back on without reloading the style.
  Future<void> setVisible(String layerId, {required bool visible}) async {
    await _guard(layerId, () => _native.setLayerVisibility(layerId, visible));
  }

  /// Turns off every layer whose identifier contains [keyword].
  ///
  /// Returns how many were turned off. It's the shortcut for the most common
  /// request:
  ///
  /// ```dart
  /// // A clean map, as a background for your own data.
  /// await controller.style.hideMatching('poi');
  /// await controller.style.hideMatching('label');
  /// ```
  ///
  /// To turn off the points of interest there's a better and cheaper way:
  /// request the descriptor with `poiDensity: MapPoiDensity.off`, so the
  /// server doesn't even send them.
  Future<int> hideMatching(String keyword) async {
    final lower = keyword.toLowerCase();
    var hidden = 0;
    for (final id in await layerIds()) {
      if (id.toLowerCase().contains(lower)) {
        await setVisible(id, visible: false);
        hidden++;
      }
    }
    return hidden;
  }

  /// Changes a layer's main color.
  ///
  /// It picks the right property on its own based on the type: `fill-color`
  /// for a fill, `line-color` for a line, `text-color` for a label.
  ///
  /// Returns `false` if the layer doesn't exist or its type has no color —an
  /// image layer, for example—, instead of failing silently.
  Future<bool> setColor(String layerId, Color color) async {
    final properties = await _properties(layerId);
    final type = StyleLayerType.fromWireName(properties?['type'] as String?);
    final property = type?.colorProperty;
    if (type == null || property == null) return false;

    return _applyPaint(layerId, <String, Object?>{
      property: _rgba(color),
      // A label without a halo on a dark map becomes unreadable as soon as it
      // passes over a light area; the halo is adjusted to match.
      if (type == StyleLayerType.symbol)
        'text-halo-color': color.computeLuminance() > 0.5
            ? 'rgba(0,0,0,0.75)'
            : 'rgba(255,255,255,0.75)',
    });
  }

  /// Changes the width of a line layer.
  ///
  /// Returns `false` if the layer isn't a line layer.
  Future<bool> setLineWidth(String layerId, double width) async {
    final properties = await _properties(layerId);
    final type = StyleLayerType.fromWireName(properties?['type'] as String?);
    if (type == null || type != StyleLayerType.line) return false;
    return _applyPaint(layerId, <String, Object?>{'line-width': width});
  }

  /// Changes a layer's opacity.
  Future<bool> setOpacity(String layerId, double opacity) async {
    final properties = await _properties(layerId);
    final type = StyleLayerType.fromWireName(properties?['type'] as String?);
    if (type == null) return false;
    final property = switch (type) {
      StyleLayerType.fill => 'fill-opacity',
      StyleLayerType.line => 'line-opacity',
      StyleLayerType.symbol => 'text-opacity',
      StyleLayerType.circle => 'circle-opacity',
      StyleLayerType.background => 'background-opacity',
      StyleLayerType.raster => 'raster-opacity',
      StyleLayerType.hillshade => null,
      StyleLayerType.heatmap => 'heatmap-opacity',
      StyleLayerType.fillExtrusion => 'fill-extrusion-opacity',
    };
    if (property == null) return false;
    return _applyPaint(layerId, <String, Object?>{property: opacity});
  }

  /// A layer's main color, if it can be read.
  ///
  /// Returns `null` when the style defines the color with an **expression**
  /// —one that depends on the zoom or on the data— instead of a fixed value.
  /// That's the norm for roads, whose color changes with the zoom. It tells you
  /// whether a relative transformation —lightening, saturating— has anything
  /// to operate on.
  Future<Color?> getColor(String layerId) async {
    final properties = await _properties(layerId);
    final type = StyleLayerType.fromWireName(properties?['type'] as String?);
    final property = type?.colorProperty;
    if (property == null) return null;
    final paint = properties?['paint'];
    if (paint is! Map) return null;
    return _parseColor(paint[property]);
  }

  /// Applies paint properties to a layer.
  ///
  /// It's the escape hatch for what the named methods don't cover: any
  /// property in the MapLibre specification. The keys are the specification's,
  /// with hyphens: `fill-color`, `line-dasharray`, `text-halo-width`.
  ///
  /// Returns `false` if the layer doesn't exist or its type doesn't accept
  /// these properties.
  Future<bool> setPaintProperties(
    String layerId,
    Map<String, Object?> properties,
  ) async {
    final existing = await _properties(layerId);
    final type = StyleLayerType.fromWireName(existing?['type'] as String?);
    if (type == null) return false;
    return _applyPaint(layerId, properties);
  }

  // ─── Internals ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _properties(String layerId) async {
    try {
      return await _native.getLayerProperties(layerId);
    } on Object {
      return null;
    }
  }

  /// Applies [properties] to the layer, without touching any other property.
  Future<bool> _applyPaint(String layerId, Map<String, Object?> properties) =>
      _guard(
        layerId,
        () => _native.setLayerProperties(
          layerId,
          OnlyTheseProperties(properties),
        ),
      );

  Future<bool> _guard(String layerId, Future<void> Function() action) async {
    try {
      await action();
      return true;
    } on Object catch (error) {
      debugPrint(
        'nativ_maps: no se pudo retocar la capa "$layerId" '
        '— $error',
      );
      return false;
    }
  }

  static String _rgba(Color color) {
    final r = (color.r * 255).round().clamp(0, 255);
    final g = (color.g * 255).round().clamp(0, 255);
    final b = (color.b * 255).round().clamp(0, 255);
    return 'rgba($r,$g,$b,${color.a.toStringAsFixed(3)})';
  }

  /// Reads a color from the style, whether hexadecimal or `rgb()`/`rgba()`.
  static Color? _parseColor(Object? raw) {
    if (raw is! String) return null;
    final value = raw.trim();

    if (value.startsWith('#')) {
      var hex = value.substring(1);
      if (hex.length == 3) {
        hex = hex.split('').map((c) => '$c$c').join();
      }
      if (hex.length == 6) hex = 'FF$hex';
      final parsed = int.tryParse(hex, radix: 16);
      return parsed == null ? null : Color(parsed);
    }

    if (value.startsWith('rgb')) {
      final open = value.indexOf('(');
      final close = value.indexOf(')');
      if (open < 0 || close < 0) return null;
      final parts = value.substring(open + 1, close).split(',');
      if (parts.length < 3) return null;
      final r = int.tryParse(parts[0].trim());
      final g = int.tryParse(parts[1].trim());
      final b = int.tryParse(parts[2].trim());
      if (r == null || g == null || b == null) return null;
      final a = parts.length > 3
          ? (double.tryParse(parts[3].trim()) ?? 1.0)
          : 1.0;
      return Color.fromRGBO(r, g, b, a);
    }
    return null;
  }
}

/// A layer's properties, **only the ones asked for**.
///
/// `maplibre_gl` sends them with `toJson(skipNulls: false)`. With its typed
/// classes —`LineLayerProperties`, `SymbolLayerProperties`…— every property
/// that wasn't touched travels too, set to `null`, and the native side resets
/// them to their default value: changing a label's color erased its text, and
/// changing a street's color, its width. This class sends the map as is.
///
/// The native side picks the converter by the layer's actual type, not by the
/// Dart class; that's why implementing the interface is enough.
@visibleForTesting
final class OnlyTheseProperties implements ml.LayerProperties {
  /// Wraps [properties].
  const OnlyTheseProperties(this.properties);

  /// What gets sent, and nothing else.
  final Map<String, Object?> properties;

  @override
  Map<String, dynamic> toJson({bool skipNulls = true}) =>
      Map<String, dynamic>.of(properties);
}
