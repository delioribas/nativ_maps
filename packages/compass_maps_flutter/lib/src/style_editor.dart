// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

/// Qué clase de capa es, dentro de un estilo MapLibre.
enum StyleLayerType {
  /// Relleno de un área.
  fill('fill'),

  /// Una línea.
  line('line'),

  /// Un icono o una etiqueta.
  symbol('symbol'),

  /// Un círculo de radio en píxeles.
  circle('circle'),

  /// El color de fondo del mapa.
  background('background'),

  /// Una capa de imagen.
  raster('raster'),

  /// Sombreado de relieve.
  hillshade('hillshade'),

  /// Un mapa de calor.
  heatmap('heatmap'),

  /// Edificios extruidos.
  fillExtrusion('fill-extrusion');

  const StyleLayerType(this.wireName);

  /// El nombre en la especificación de estilo.
  final String wireName;

  /// El tipo cuyo nombre es [wireName], o `null` si no se reconoce.
  static StyleLayerType? fromWireName(String? name) {
    if (name == null) return null;
    for (final type in values) {
      if (type.wireName == name) return type;
    }
    return null;
  }

  /// La propiedad de color principal de este tipo de capa.
  ///
  /// Es lo que evita tener que recordar que un relleno usa `fill-color`, una
  /// línea `line-color`, una etiqueta `text-color` y el fondo
  /// `background-color`. Equivocarse no da error: la propiedad se ignora y el
  /// color no cambia, que es peor.
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

/// Una capa del estilo, con lo que hace falta para retocarla.
@immutable
class StyleLayer {
  /// Crea la descripción de la capa.
  const StyleLayer({required this.id, required this.type, this.sourceLayer});

  /// El identificador de la capa dentro del estilo.
  final String id;

  /// Qué clase de capa es.
  final StyleLayerType? type;

  /// La capa de origen dentro de la fuente de teselas, si la tiene.
  final String? sourceLayer;

  @override
  String toString() => 'StyleLayer($id, ${type?.wireName ?? '?'})';
}

/// Retoca el estilo del mapa en caliente.
///
/// Se obtiene de `CompassMapController.style`.
///
/// ## Para qué sirve
///
/// El estilo de Amazon Location viene hecho, y casi siempre es lo que se
/// quiere. Esto existe para las tres cosas que casi siempre hacen falta
/// encima:
///
/// - **Apagar lo que estorba.** Un mapa que es el fondo de datos propios no
///   necesita los puntos de interés ni las etiquetas de comercio.
/// - **Ajustar la paleta** a la de la app, sin rehacer el estilo entero.
/// - **Aplicar un tema que ya existe**, que es lo que hace el paquete
///   `compass_maps_google` traduciendo un estilo JSON de Google.
///
/// ## Lo que cambia aquí no sobrevive a un cambio de estilo
///
/// Cambiar `styleUrl` recarga el estilo desde el servidor y deshace todo esto.
/// Hay que volver a aplicarlo en `CompassMap.onStyleLoaded`, que se llama en
/// **cada** carga y no solo en la primera precisamente por esto.
class StyleEditor {
  /// Uso interno: lo construye el controlador.
  @internal
  StyleEditor(this._native);

  final ml.MapLibreMapController _native;

  /// Todas las capas del estilo, en el orden en que se dibujan.
  ///
  /// Es lo primero que hay que mirar para retocar un estilo: los nombres los
  /// pone el proveedor y no hay forma de adivinarlos.
  ///
  /// ```dart
  /// for (final capa in await controller.style.layers()) {
  ///   debugPrint('$capa');
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

  /// Solo los identificadores, sin consultar el tipo de cada una.
  ///
  /// Mucho más rápido que [layers] cuando solo hace falta el nombre: un estilo
  /// tiene fácilmente doscientas capas, y [layers] cruza el canal de
  /// plataforma una vez por cada una.
  Future<List<String>> layerIds() async {
    final ids = await _native.getLayerIds();
    return ids.whereType<String>().toList(growable: false);
  }

  /// Enciende o apaga una capa.
  ///
  /// Apagar es preferible a borrar: la capa sigue ahí y se puede volver a
  /// encender sin recargar el estilo.
  Future<void> setVisible(String layerId, {required bool visible}) async {
    await _guard(layerId, () => _native.setLayerVisibility(layerId, visible));
  }

  /// Apaga todas las capas cuyo identificador contenga [keyword].
  ///
  /// Devuelve cuántas se apagaron. Es el atajo para lo más pedido:
  ///
  /// ```dart
  /// // Un mapa limpio, de fondo para datos propios.
  /// await controller.style.hideMatching('poi');
  /// await controller.style.hideMatching('label');
  /// ```
  ///
  /// Para apagar los puntos de interés hay una forma mejor y más barata:
  /// pedir el descriptor con `poiDensity: MapPoiDensity.off`, que evita que el
  /// servidor los mande siquiera.
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

  /// Cambia el color principal de una capa.
  ///
  /// Elige sola la propiedad correcta según el tipo: `fill-color` para un
  /// relleno, `line-color` para una línea, `text-color` para una etiqueta.
  ///
  /// Devuelve `false` si la capa no existe o su tipo no tiene color —una capa
  /// de imagen, por ejemplo—, en vez de fallar en silencio.
  Future<bool> setColor(String layerId, Color color) async {
    final properties = await _properties(layerId);
    final type = StyleLayerType.fromWireName(properties?['type'] as String?);
    final property = type?.colorProperty;
    if (type == null || property == null) return false;

    return _applyPaint(layerId, type, <String, Object?>{
      property: _rgba(color),
      // Una etiqueta sin halo sobre un mapa oscuro se vuelve ilegible en
      // cuanto pasa por encima de una zona clara; se ajusta a juego.
      if (type == StyleLayerType.symbol)
        'text-halo-color': color.computeLuminance() > 0.5
            ? 'rgba(0,0,0,0.75)'
            : 'rgba(255,255,255,0.75)',
    });
  }

  /// Cambia el grosor de una capa de línea.
  ///
  /// Devuelve `false` si la capa no es de línea.
  Future<bool> setLineWidth(String layerId, double width) async {
    final properties = await _properties(layerId);
    final type = StyleLayerType.fromWireName(properties?['type'] as String?);
    if (type == null || type != StyleLayerType.line) return false;
    return _applyPaint(layerId, type, <String, Object?>{'line-width': width});
  }

  /// Cambia la opacidad de una capa.
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
    return _applyPaint(layerId, type, <String, Object?>{property: opacity});
  }

  /// El color principal de una capa, si se puede leer.
  ///
  /// Devuelve `null` cuando el estilo define el color con una **expresión**
  /// —que depende del zoom o de los datos— en vez de con un valor fijo. Es lo
  /// habitual en las vías, cuyo color cambia con el zoom. Sirve para saber si
  /// una transformación relativa —aclarar, saturar— tiene sobre qué operar.
  Future<Color?> getColor(String layerId) async {
    final properties = await _properties(layerId);
    final type = StyleLayerType.fromWireName(properties?['type'] as String?);
    final property = type?.colorProperty;
    if (property == null) return null;
    final paint = properties?['paint'];
    if (paint is! Map) return null;
    return _parseColor(paint[property]);
  }

  /// Aplica propiedades de pintura a una capa.
  ///
  /// Es el escape para lo que los métodos con nombre no cubren: cualquier
  /// propiedad de la especificación de MapLibre. Las claves son las de la
  /// especificación, con guiones: `fill-color`, `line-dasharray`,
  /// `text-halo-width`.
  ///
  /// Devuelve `false` si la capa no existe o su tipo no admite estas
  /// propiedades.
  Future<bool> setPaintProperties(
    String layerId,
    Map<String, Object?> properties,
  ) async {
    final existing = await _properties(layerId);
    final type = StyleLayerType.fromWireName(existing?['type'] as String?);
    if (type == null) return false;
    return _applyPaint(layerId, type, properties);
  }

  // ─── Internos ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _properties(String layerId) async {
    try {
      return await _native.getLayerProperties(layerId);
    } on Object {
      return null;
    }
  }

  /// Construye el objeto de propiedades tipado que espera `maplibre_gl`.
  ///
  /// El paquete nativo no admite un mapa suelto: exige la clase concreta del
  /// tipo de capa. Esta función es el puente, y por eso el tipo hay que
  /// consultarlo antes.
  Future<bool> _applyPaint(
    String layerId,
    StyleLayerType type,
    Map<String, Object?> properties,
  ) async {
    final ml.LayerProperties layerProperties;
    switch (type) {
      case StyleLayerType.fill:
        layerProperties = ml.FillLayerProperties.fromJson(properties);
      case StyleLayerType.line:
        layerProperties = ml.LineLayerProperties.fromJson(properties);
      case StyleLayerType.symbol:
        layerProperties = ml.SymbolLayerProperties.fromJson(properties);
      case StyleLayerType.circle:
        layerProperties = ml.CircleLayerProperties.fromJson(properties);
      case StyleLayerType.background:
        layerProperties = ml.BackgroundLayerProperties.fromJson(properties);
      case StyleLayerType.raster:
        layerProperties = ml.RasterLayerProperties.fromJson(properties);
      case StyleLayerType.hillshade:
        layerProperties = ml.HillshadeLayerProperties.fromJson(properties);
      case StyleLayerType.heatmap:
        layerProperties = ml.HeatmapLayerProperties.fromJson(properties);
      case StyleLayerType.fillExtrusion:
        layerProperties = ml.FillExtrusionLayerProperties.fromJson(properties);
    }
    return _guard(
      layerId,
      () => _native.setLayerProperties(layerId, layerProperties),
    );
  }

  Future<bool> _guard(String layerId, Future<void> Function() action) async {
    try {
      await action();
      return true;
    } on Object catch (error) {
      debugPrint(
        'compass_maps: no se pudo retocar la capa "$layerId" '
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

  /// Lee un color del estilo, sea hexadecimal o `rgb()`/`rgba()`.
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
