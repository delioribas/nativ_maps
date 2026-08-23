// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:compass_maps_flutter/src/internal/geojson.dart';
import 'package:compass_maps_flutter/src/types/overlays.dart';
import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

/// Instala y mantiene las fuentes y capas del estilo.
///
/// Es donde vive todo el conocimiento de la especificación de estilo de
/// MapLibre, para que el resto del paquete no tenga que saber nada de ella.
///
/// ## El orden de las capas importa
///
/// Se instalan en el orden en que se dibujan: primero las áreas —abajo del
/// todo—, luego las líneas, y los símbolos encima. Una polilínea instalada
/// después de los marcadores les pasaría por encima, y una ruta tapando los
/// vehículos que la recorren es exactamente lo que no se quiere.
@internal
class LayerInstaller {
  /// Crea el instalador sobre un controlador nativo.
  LayerInstaller(this._native);

  final ml.MapLibreMapController _native;

  /// Las polilíneas discontinuas instaladas, por patrón.
  ///
  /// Cada patrón distinto necesita **su propia capa**: `line-dasharray` no
  /// admite expresiones basadas en datos en la especificación de MapLibre, así
  /// que el patrón es literal por capa. Sin esta separación, todas las líneas
  /// discontinuas de un mapa saldrían con el mismo patrón.
  final Map<String, String> _dashLayers = <String, String>{};

  // ─── Identificadores ──────────────────────────────────────────────────

  /// Fuente de los marcadores sin agrupar.
  static const String markerSourceId = 'compass-markers-src';

  /// Capa de los marcadores sin agrupar.
  static const String markerLayerId = 'compass-markers-layer';

  /// Fuente de las polilíneas continuas.
  static const String lineSourceId = 'compass-lines-src';

  /// Capa de las polilíneas continuas.
  static const String lineLayerId = 'compass-lines-layer';

  /// Capa base de las polilíneas discontinuas.
  static const String dashedLineLayerId = 'compass-lines-dashed-layer';

  /// Fuente de polígonos y círculos.
  static const String areaSourceId = 'compass-areas-src';

  /// Capa de relleno de las áreas.
  static const String areaFillLayerId = 'compass-areas-fill';

  /// Capa de borde de las áreas.
  static const String areaOutlineLayerId = 'compass-areas-outline';

  /// La fuente de un agrupador.
  static String clusterSourceId(ClusterManagerId id) =>
      'compass-cluster-src-${id.value}';

  /// La capa del círculo de un grupo.
  static String clusterCircleLayerId(ClusterManagerId id) =>
      'compass-cluster-circle-${id.value}';

  /// La capa del número de un grupo.
  static String clusterCountLayerId(ClusterManagerId id) =>
      'compass-cluster-count-${id.value}';

  /// La capa de los marcadores sueltos de un agrupador.
  static String clusterMarkerLayerId(ClusterManagerId id) =>
      'compass-cluster-marker-${id.value}';

  /// La fuente de un mapa de calor.
  static String heatmapSourceId(HeatmapId id) =>
      'compass-heatmap-src-${id.value}';

  /// La capa de un mapa de calor.
  static String heatmapLayerId(HeatmapId id) =>
      'compass-heatmap-layer-${id.value}';

  // ─── Instalación ──────────────────────────────────────────────────────

  /// Instala las fuentes y capas base.
  ///
  /// Es idempotente: volver a llamarlo tras un cambio de estilo reinstala lo
  /// que el cambio borró y no duplica lo que sobrevivió.
  Future<void> installBaseLayers() async {
    _dashLayers.clear();

    await _addSource(areaSourceId);
    await _addSource(lineSourceId);
    await _addSource(markerSourceId);

    // 1 · Áreas, abajo del todo.
    await _tryAdd(
      () => _native.addFillLayer(
        areaSourceId,
        areaFillLayerId,
        const ml.FillLayerProperties(
          fillColor: <Object>['get', 'fill'],
          fillSortKey: <Object>['get', 'zIndex'],
        ),
      ),
    );
    await _tryAdd(
      () => _native.addLineLayer(
        areaSourceId,
        areaOutlineLayerId,
        const ml.LineLayerProperties(
          lineColor: <Object>['get', 'stroke'],
          lineWidth: <Object>['get', 'strokeWidth'],
          lineJoin: 'round',
        ),
      ),
    );

    // 2 · Líneas continuas.
    await _tryAdd(
      () => _native.addLineLayer(
        lineSourceId,
        lineLayerId,
        const ml.LineLayerProperties(
          lineColor: <Object>['get', 'color'],
          lineWidth: <Object>['get', 'width'],
          lineBlur: <Object>['get', 'blur'],
          lineOpacity: <Object>['get', 'opacity'],
          lineCap: 'round',
          lineJoin: 'round',
          lineSortKey: <Object>['get', 'zIndex'],
        ),
      ),
    );

    // 3 · Marcadores, encima.
    await _tryAdd(
      () => _native.addSymbolLayer(
        markerSourceId,
        markerLayerId,
        const ml.SymbolLayerProperties(
          iconImage: <Object>['get', 'icon'],
          iconSize: <Object>['get', 'iconScale'],
          iconRotate: <Object>['get', 'rotation'],
          iconOpacity: <Object>['get', 'alpha'],
          iconAllowOverlap: true,
          iconIgnorePlacement: false,
          // `map` hace que el icono gire con el mapa, que es lo que quiere el
          // marcador de un vehículo; los planos lo anulan con `iconRotate`.
          iconRotationAlignment: <Object>[
            'case',
            <Object>['get', 'flat'],
            'map',
            'viewport',
          ],
          iconAnchor: 'bottom',
          symbolSortKey: <Object>['get', 'zIndex'],
          textField: <Object>['get', 'label'],
          textSize: 12.0,
          textOffset: <Object>[
            'literal',
            <double>[0, 0.8],
          ],
          textAnchor: 'top',
          textHaloWidth: 1.2,
          textHaloColor: 'rgba(255,255,255,0.9)',
          textAllowOverlap: false,
          textOptional: true,
        ),
      ),
    );
  }

  /// Instala las capas de un agrupador.
  ///
  /// La fuente lleva `cluster: true`, que es lo que hace que **el motor**
  /// agrupe. En `google_maps_flutter` esto lo hace una clase en Dart que
  /// recalcula en cada movimiento de cámara.
  Future<void> installCluster(ClusterManager manager) async {
    final id = manager.clusterManagerId;
    await _tryAdd(
      () => _native.addSource(
        clusterSourceId(id),
        ml.GeojsonSourceProperties(
          data: GeoJson.empty,
          cluster: true,
          clusterMaxZoom: manager.maxZoom.toDouble(),
          clusterRadius: manager.radius,
        ),
      ),
    );

    // Círculo del grupo.
    await _tryAdd(
      () => _native.addCircleLayer(
        clusterSourceId(id),
        clusterCircleLayerId(id),
        ml.CircleLayerProperties(
          circleColor: GeoJson.clusterColorExpression(manager.colorSteps),
          circleRadius: GeoJson.clusterRadiusExpression(manager.radiusSteps),
          circleStrokeWidth: 2,
          circleStrokeColor: 'rgba(255,255,255,0.85)',
        ),
        filter: <Object>['has', 'point_count'],
      ),
    );

    // Número dentro del grupo.
    await _tryAdd(
      () => _native.addSymbolLayer(
        clusterSourceId(id),
        clusterCountLayerId(id),
        ml.SymbolLayerProperties(
          textField: <Object>['get', 'point_count_abbreviated'],
          textSize: 13.0,
          textColor: GeoJson.rgba(manager.textColor),
          textAllowOverlap: true,
          textIgnorePlacement: true,
        ),
        filter: <Object>['has', 'point_count'],
      ),
    );

    // Los que no llegaron a agruparse, como marcadores normales.
    await _tryAdd(
      () => _native.addSymbolLayer(
        clusterSourceId(id),
        clusterMarkerLayerId(id),
        const ml.SymbolLayerProperties(
          iconImage: <Object>['get', 'icon'],
          iconSize: <Object>['get', 'iconScale'],
          iconRotate: <Object>['get', 'rotation'],
          iconAllowOverlap: true,
          iconAnchor: 'bottom',
        ),
        filter: <Object>[
          '!',
          <Object>['has', 'point_count'],
        ],
      ),
    );
  }

  /// Quita las capas y la fuente de un agrupador.
  Future<void> removeCluster(ClusterManagerId id) async {
    await _tryRemoveLayer(clusterMarkerLayerId(id));
    await _tryRemoveLayer(clusterCountLayerId(id));
    await _tryRemoveLayer(clusterCircleLayerId(id));
    await _tryRemoveSource(clusterSourceId(id));
  }

  /// Instala la fuente y la capa de un mapa de calor.
  Future<void> installHeatmap(Heatmap heatmap) async {
    final source = heatmapSourceId(heatmap.heatmapId);
    await _tryAdd(() => _native.addGeoJsonSource(source, GeoJson.empty));
    await _tryRemoveLayer(heatmapLayerId(heatmap.heatmapId));
    await _tryAdd(
      () => _native.addHeatmapLayer(
        source,
        heatmapLayerId(heatmap.heatmapId),
        ml.HeatmapLayerProperties(
          heatmapWeight: <Object>['get', 'weight'],
          heatmapIntensity: heatmap.intensity,
          heatmapRadius: heatmap.radius,
          heatmapOpacity: heatmap.visible ? heatmap.opacity : 0.0,
          heatmapColor: GeoJson.heatmapColorExpression(heatmap.gradient),
        ),
        minzoom: heatmap.minZoom,
        maxzoom: heatmap.maxZoom,
        // Debajo de los marcadores: un mapa de calor encima los taparía.
        belowLayerId: markerLayerId,
      ),
    );
  }

  /// Quita un mapa de calor.
  Future<void> removeHeatmap(HeatmapId id) async {
    await _tryRemoveLayer(heatmapLayerId(id));
    await _tryRemoveSource(heatmapSourceId(id));
  }

  // ─── Empuje de datos ──────────────────────────────────────────────────

  /// Empuja una colección GeoJSON a una fuente.
  ///
  /// Si la fuente no existe —porque un cambio de estilo la borró—, se
  /// reinstalan las capas base y se reintenta una vez. Es la diferencia entre
  /// un mapa que se recupera solo y uno que se queda vacío tras cambiar a modo
  /// oscuro.
  Future<void> push(String sourceId, Map<String, dynamic> data) async {
    try {
      await _native.setGeoJsonSource(sourceId, data);
    } on Object {
      try {
        await _native.addGeoJsonSource(sourceId, data);
      } on Object catch (error) {
        debugPrint('compass_maps: no se pudo empujar "$sourceId" — $error');
      }
    }
  }

  /// Empuja las polilíneas discontinuas, una capa por patrón.
  Future<void> pushDashed(Iterable<Polyline> lines) async {
    final byPattern = <String, List<Polyline>>{};
    for (final line in lines) {
      final dash = GeoJson.dashArray(line.patterns, line.width);
      byPattern.putIfAbsent(dash.join(','), () => <Polyline>[]).add(line);
    }

    // Vacía las capas de patrones que ya no se usan, en vez de borrarlas:
    // quitar y volver a crear una capa provoca un parpadeo visible.
    for (final key in _dashLayers.keys) {
      if (!byPattern.containsKey(key)) {
        await push('$dashedLineLayerId-src-$key', GeoJson.empty);
      }
    }

    for (final entry in byPattern.entries) {
      final sourceId = '$dashedLineLayerId-src-${entry.key}';
      final layerId = '$dashedLineLayerId-${entry.key}';
      if (!_dashLayers.containsKey(entry.key)) {
        _dashLayers[entry.key] = layerId;
        await _tryAdd(() => _native.addGeoJsonSource(sourceId, GeoJson.empty));
        final dash = GeoJson.dashArray(
          entry.value.first.patterns,
          entry.value.first.width,
        );
        await _tryAdd(
          () => _native.addLineLayer(
            sourceId,
            layerId,
            ml.LineLayerProperties(
              lineColor: <Object>['get', 'color'],
              lineWidth: <Object>['get', 'width'],
              lineOpacity: <Object>['get', 'opacity'],
              lineDasharray: <Object>['literal', dash],
              lineCap: 'butt',
              lineJoin: 'round',
            ),
            belowLayerId: markerLayerId,
          ),
        );
      }
      await push(sourceId, GeoJson.polylines(entry.value));
    }
  }

  // ─── Auxiliares ───────────────────────────────────────────────────────

  Future<void> _addSource(String id) =>
      _tryAdd(() => _native.addGeoJsonSource(id, GeoJson.empty));

  /// Ejecuta algo que puede fallar porque ya existe.
  ///
  /// MapLibre lanza al añadir una capa o fuente repetida, y tras un cambio de
  /// estilo no hay forma barata de saber cuáles sobrevivieron. Intentarlo y
  /// tragarse el error de duplicado es más simple y más rápido que consultar
  /// la lista de capas antes de cada una.
  Future<void> _tryAdd(Future<void> Function() action) async {
    try {
      await action();
    } on Object catch (error) {
      final message = error.toString();
      final alreadyExists =
          message.contains('already exists') ||
          message.contains('ya existe') ||
          message.contains('duplicate');
      if (!alreadyExists) {
        debugPrint('compass_maps: al instalar una capa — $error');
      }
    }
  }

  Future<void> _tryRemoveLayer(String id) async {
    try {
      await _native.removeLayer(id);
    } on Object {
      // No existía. No hay nada que hacer.
    }
  }

  Future<void> _tryRemoveSource(String id) async {
    try {
      await _native.removeSource(id);
    } on Object {
      // No existía.
    }
  }
}
