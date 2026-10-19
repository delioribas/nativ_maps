// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
// `meta` is imported explicitly, even though on Flutter 3.44+ the linter flags
// it as redundant: `package:flutter/foundation.dart` **does not re-export
// `@internal`** until recent versions, and this package declares Flutter 3.32
// as its floor. Without this import, anyone using it on 3.32 runs into twelve
// `undefined_annotation` errors.
// ignore: unnecessary_import
import 'package:meta/meta.dart';
import 'package:nativ_maps_flutter/src/internal/geojson.dart';
import 'package:nativ_maps_flutter/src/types/overlays.dart';

/// Installs and maintains the style's sources and layers.
///
/// It's where all the knowledge of the MapLibre style specification lives, so
/// the rest of the package doesn't have to know anything about it.
///
/// ## Layer order matters
///
/// They're installed in the order they're drawn: first the areas —at the very
/// bottom—, then the lines, and the symbols on top. A polyline installed after
/// the markers would run over them, and a route covering the vehicles driving
/// along it is exactly what you don't want.
@internal
class LayerInstaller {
  /// Creates the installer on top of a native controller.
  LayerInstaller(this._native);

  final ml.MapLibreMapController _native;

  /// The installed dashed polylines, by pattern.
  ///
  /// Each different pattern needs **its own layer**: `line-dasharray` doesn't
  /// accept data-driven expressions in the MapLibre specification, so the
  /// pattern is a literal per layer. Without this split, every dashed line on
  /// a map would come out with the same pattern.
  final Map<String, String> _dashLayers = <String, String>{};

  /// Areas and lines are not interactive for `maplibre_gl`.
  ///
  /// The plugin marks every layer as interactive by default, and a tap on an
  /// interactive layer comes out through `onFeatureTapped` and **not** through
  /// `onMapClick`. Since the package works out by itself what's under the
  /// finger —`markerAt`, `clusterAt`, `polylineAt`—, with interactive layers
  /// neither `onMarkerTap` nor the info windows nor `onTap` on a polygon ever
  /// arrived.
  static const bool _interactive = false;

  /// Marker layers are the exception: they have to be interactive.
  ///
  /// The native side only starts dragging a feature that sits on an
  /// interactive layer and carries `draggable: true`; on any other layer a
  /// press just pans the map. Taps on them still reach `onMapClick` because
  /// the widget sets `featureTapsTriggersMapClick`, which is what keeps
  /// `onMarkerTap` and the info windows working.
  static const bool _markersInteractive = true;

  // ─── Identifiers ─────────────────────────────────────────────────────

  /// Source of the unclustered markers.
  static const String markerSourceId = 'nativ-markers-src';

  /// Layer of the unclustered markers that face the screen.
  static const String markerLayerId = 'nativ-markers-layer';

  /// Layer of the flat markers (`Marker.flat`), which rotate with the map.
  ///
  /// It's the lower of the two: whatever has to stay under the markers —a
  /// heatmap, a dashed line— goes under this one.
  static const String markerFlatLayerId = 'nativ-markers-flat-layer';

  /// The two marker layers, for the hit-test.
  static const List<String> markerLayerIds = <String>[
    markerLayerId,
    markerFlatLayerId,
  ];

  /// Source of the solid polylines.
  static const String lineSourceId = 'nativ-lines-src';

  /// Layer of the solid polylines.
  static const String lineLayerId = 'nativ-lines-layer';

  /// Base layer of the dashed polylines.
  static const String dashedLineLayerId = 'nativ-lines-dashed-layer';

  /// Source of polygons and circles.
  static const String areaSourceId = 'nativ-areas-src';

  /// Fill layer of the areas.
  static const String areaFillLayerId = 'nativ-areas-fill';

  /// Outline layer of the areas.
  static const String areaOutlineLayerId = 'nativ-areas-outline';

  /// The source of a cluster manager.
  static String clusterSourceId(ClusterManagerId id) =>
      'nativ-cluster-src-${id.value}';

  /// The layer of a cluster's circle.
  static String clusterCircleLayerId(ClusterManagerId id) =>
      'nativ-cluster-circle-${id.value}';

  /// The layer of a cluster's number.
  static String clusterCountLayerId(ClusterManagerId id) =>
      'nativ-cluster-count-${id.value}';

  /// The layer of a cluster manager's standalone markers.
  static String clusterMarkerLayerId(ClusterManagerId id) =>
      'nativ-cluster-marker-${id.value}';

  /// The source of a heatmap.
  static String heatmapSourceId(HeatmapId id) =>
      'nativ-heatmap-src-${id.value}';

  /// The layer of a heatmap.
  static String heatmapLayerId(HeatmapId id) =>
      'nativ-heatmap-layer-${id.value}';

  /// The source of a ground overlay.
  static String groundOverlaySourceId(GroundOverlayId id) =>
      'nativ-ground-src-${id.value}';

  /// The layer of a ground overlay.
  static String groundOverlayLayerId(GroundOverlayId id) =>
      'nativ-ground-layer-${id.value}';

  /// The source of a tile overlay.
  static String tileOverlaySourceId(TileOverlayId id) =>
      'nativ-tiles-src-${id.value}';

  /// The layer of a tile overlay.
  static String tileOverlayLayerId(TileOverlayId id) =>
      'nativ-tiles-layer-${id.value}';

  // ─── Installation ────────────────────────────────────────────────────

  /// Installs the base sources and layers.
  ///
  /// It's idempotent: calling it again after a style change reinstalls what
  /// the change deleted and doesn't duplicate what survived.
  Future<void> installBaseLayers() async {
    _dashLayers.clear();

    await _addSource(areaSourceId);
    await _addSource(lineSourceId);
    await _addSource(markerSourceId);

    // 1 · Areas, at the very bottom.
    await _tryAdd(
      () => _native.addFillLayer(
        areaSourceId,
        areaFillLayerId,
        const ml.FillLayerProperties(
          fillColor: <Object>['get', 'fill'],
          fillSortKey: <Object>['get', 'zIndex'],
        ),
        enableInteraction: _interactive,
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
        enableInteraction: _interactive,
      ),
    );

    // 2 · Solid lines.
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
        enableInteraction: _interactive,
      ),
    );

    // 3 · Markers, on top: first the flat ones, and on top of them the ones
    // that face the screen.
    //
    // They're two layers because `icon-rotation-alignment` **does not accept
    // expressions** in the style specification: with a `case` on `flat`,
    // MapLibre rejects the property and the whole layer goes undrawn —with no
    // error reaching Dart—. One layer per value, each with its own filter, is
    // the form it accepts.
    await _tryAdd(
      () => _native.addSymbolLayer(
        markerSourceId,
        markerFlatLayerId,
        _markerProperties(rotationAlignment: 'map'),
        filter: <Object>[
          '==',
          <Object>['get', 'flat'],
          true,
        ],
        enableInteraction: _markersInteractive,
      ),
    );
    await _tryAdd(
      () => _native.addSymbolLayer(
        markerSourceId,
        markerLayerId,
        _markerProperties(rotationAlignment: 'viewport'),
        filter: <Object>[
          '!=',
          <Object>['get', 'flat'],
          true,
        ],
        enableInteraction: _markersInteractive,
      ),
    );
  }

  /// The properties of a marker layer.
  ///
  /// [rotationAlignment] is `map` for the flat ones —a vehicle's icon rotates
  /// with the map— and `viewport` for the rest.
  static ml.SymbolLayerProperties _markerProperties({
    required String rotationAlignment,
  }) => ml.SymbolLayerProperties(
    iconImage: <Object>['get', 'icon'],
    iconSize: <Object>['get', 'iconScale'],
    iconRotate: <Object>['get', 'rotation'],
    iconOpacity: <Object>['get', 'alpha'],
    iconAllowOverlap: true,
    iconIgnorePlacement: false,
    iconRotationAlignment: rotationAlignment,
    iconAnchor: <Object>['get', 'anchor'],
    symbolSortKey: <Object>['get', 'zIndex'],
    textField: <Object>['get', 'label'],
    textSize: 12.0,
    textOffset: <Object>[
      'array',
      'number',
      2,
      <Object>['get', 'labelOffset'],
    ],
    textAnchor: 'top',
    textHaloWidth: 1.2,
    textHaloColor: 'rgba(255,255,255,0.9)',
    textAllowOverlap: false,
    textOptional: true,
  );

  /// Installs the layers of a cluster manager.
  ///
  /// The source carries `cluster: true`, which is what makes **the engine** do
  /// the clustering. In `google_maps_flutter` this is done by a Dart class that
  /// recomputes on every camera move.
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

    // The cluster's circle.
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
        enableInteraction: _interactive,
      ),
    );

    // The number inside the cluster.
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
        enableInteraction: _interactive,
      ),
    );

    // The ones that didn't end up clustered, as regular markers.
    await _tryAdd(
      () => _native.addSymbolLayer(
        clusterSourceId(id),
        clusterMarkerLayerId(id),
        // The same properties as the unclustered markers: without them, a
        // marker lost its text and its anchor when it left a cluster.
        _markerProperties(rotationAlignment: 'viewport'),
        filter: <Object>[
          '!',
          <Object>['has', 'point_count'],
        ],
        enableInteraction: _markersInteractive,
      ),
    );
  }

  /// Removes the layers and the source of a cluster manager.
  Future<void> removeCluster(ClusterManagerId id) async {
    await _tryRemoveLayer(clusterMarkerLayerId(id));
    await _tryRemoveLayer(clusterCountLayerId(id));
    await _tryRemoveLayer(clusterCircleLayerId(id));
    await _tryRemoveSource(clusterSourceId(id));
  }

  /// Installs the source and the layer of a heatmap.
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
        // Under the markers: a heatmap on top would cover them.
        belowLayerId: markerFlatLayerId,
        // No `enableInteraction`: the plugin doesn't make a heatmap
        // interactive.
      ),
    );
  }

  /// Removes a heatmap.
  Future<void> removeHeatmap(HeatmapId id) async {
    await _tryRemoveLayer(heatmapLayerId(id));
    await _tryRemoveSource(heatmapSourceId(id));
  }

  // ─── Raster overlays ──────────────────────────────────────────────────

  /// The raster layers and sources installed, to remove them next time.
  final List<(String layer, String source)> _rasters =
      <(String layer, String source)>[];

  /// Installs every ground and tile overlay again, lowest `zIndex` first.
  ///
  /// They all go **below the package's areas**: an image or a tile layer is
  /// background, and a polygon, a route or a marker has to stay readable on
  /// top of it. Each one is added right under the areas, so the last one
  /// added ends up on top — hence the order.
  ///
  /// Reinstalling everything is simpler than diffing, and these change rarely:
  /// a plan of a building, a coverage layer.
  Future<void> installRasterOverlays(
    Iterable<GroundOverlay> grounds,
    Iterable<TileOverlay> tiles,
  ) async {
    for (final (layer, source) in _rasters) {
      await _tryRemoveLayer(layer);
      await _tryRemoveSource(source);
    }
    _rasters.clear();

    final ordered = <(double, Future<void> Function())>[
      for (final g in grounds)
        if (g.visible) (g.zIndex, () => _installGround(g)),
      for (final t in tiles)
        if (t.visible) (t.zIndex, () => _installTiles(t)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    for (final (_, install) in ordered) {
      await install();
    }
  }

  Future<void> _installGround(GroundOverlay overlay) async {
    final source = groundOverlaySourceId(overlay.groundOverlayId);
    final layer = groundOverlayLayerId(overlay.groundOverlayId);
    final b = overlay.bounds;
    final (n, s, e, w) = (
      b.northeast.latitude,
      b.southwest.latitude,
      b.northeast.longitude,
      b.southwest.longitude,
    );
    final url = overlay.imageUrl;
    if (url.startsWith('data:')) {
      // MapLibre downloads an image source by URL and doesn't understand
      // `data:`; the bytes are decoded here and handed over directly.
      await _tryAdd(
        () => _native.addImageSource(
          source,
          UriData.parse(url).contentAsBytes(),
          ml.LatLngQuad(
            topLeft: ml.LatLng(n, w),
            topRight: ml.LatLng(n, e),
            bottomRight: ml.LatLng(s, e),
            bottomLeft: ml.LatLng(s, w),
          ),
        ),
      );
    } else {
      await _tryAdd(
        () => _native.addSource(
          source,
          ml.ImageSourceProperties(
            url: url,
            // Clockwise from the top-left corner, as `[lon, lat]`.
            coordinates: <List<double>>[
              <double>[w, n],
              <double>[e, n],
              <double>[e, s],
              <double>[w, s],
            ],
          ),
        ),
      );
    }
    await _addRasterLayer(source, layer, overlay.opacity);
  }

  Future<void> _installTiles(TileOverlay overlay) async {
    final source = tileOverlaySourceId(overlay.tileOverlayId);
    final layer = tileOverlayLayerId(overlay.tileOverlayId);
    await _tryAdd(
      () => _native.addSource(
        source,
        ml.RasterSourceProperties(
          tiles: <String>[overlay.urlTemplate],
          tileSize: overlay.tileSize.toDouble(),
          minzoom: overlay.minZoom,
          maxzoom: overlay.maxZoom,
          attribution: overlay.attribution,
        ),
      ),
    );
    await _addRasterLayer(source, layer, overlay.opacity);
  }

  Future<void> _addRasterLayer(
    String source,
    String layer,
    double opacity,
  ) async {
    await _tryAdd(
      () => _native.addRasterLayer(
        source,
        layer,
        ml.RasterLayerProperties(
          rasterOpacity: opacity,
          // Without this, every pan fades the tiles in again.
          rasterFadeDuration: 0,
        ),
        belowLayerId: areaFillLayerId,
      ),
    );
    _rasters.add((layer, source));
  }

  // ─── Pushing data ────────────────────────────────────────────────────

  /// Replaces one feature of a source, leaving the rest as they are.
  ///
  /// It's how a dragged marker follows the finger: sending the whole marker
  /// collection on every frame of a drag would stutter with a few hundred.
  Future<void> pushFeature(
    String sourceId,
    Map<String, dynamic> feature,
  ) async {
    try {
      await _native.setGeoJsonFeature(sourceId, feature);
    } on Object catch (error) {
      debugPrint(
        'nativ_maps: could not update a feature of "$sourceId" — $error',
      );
    }
  }

  /// Pushes a GeoJSON collection to a source.
  ///
  /// If the source doesn't exist —because a style change deleted it—, the base
  /// layers are reinstalled and it retries once. It's the difference between a
  /// map that recovers on its own and one that stays empty after switching to
  /// dark mode.
  Future<void> push(String sourceId, Map<String, dynamic> data) async {
    try {
      await _native.setGeoJsonSource(sourceId, data);
    } on Object {
      try {
        await _native.addGeoJsonSource(sourceId, data);
      } on Object catch (error) {
        debugPrint('nativ_maps: no se pudo empujar "$sourceId" — $error');
      }
    }
  }

  /// Pushes the dashed polylines, one layer per pattern.
  Future<void> pushDashed(Iterable<Polyline> lines) async {
    final byPattern = <String, List<Polyline>>{};
    for (final line in lines) {
      final dash = GeoJson.dashArray(line.patterns, line.width);
      byPattern.putIfAbsent(dash.join(','), () => <Polyline>[]).add(line);
    }

    // Empties the layers of patterns no longer in use, instead of deleting
    // them: removing and recreating a layer causes a visible flicker.
    for (final key in _dashLayers.keys) {
      if (!byPattern.containsKey(key)) {
        await push('$dashedLineLayerId-src-$key', GeoJson.empty);
      }
    }

    for (final entry in byPattern.entries) {
      final sourceId = '$dashedLineLayerId-src-${entry.key}';
      final layerId = '$dashedLineLayerId-${entry.key}';
      if (!_dashLayers.containsKey(entry.key)) {
        await _tryAdd(() => _native.addGeoJsonSource(sourceId, GeoJson.empty));
        final dash = GeoJson.dashArray(
          entry.value.first.patterns,
          entry.value.first.width,
        );
        // Recorded only once the layer is there: recorded before, a layer
        // that failed to go in was never tried again, and its dashed lines
        // never showed up.
        final installed = await _tryAdd(
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
            belowLayerId: markerFlatLayerId,
            enableInteraction: _interactive,
          ),
        );
        if (installed) _dashLayers[entry.key] = layerId;
      }
      await push(sourceId, GeoJson.polylines(entry.value));
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────

  Future<void> _addSource(String id) =>
      _tryAdd(() => _native.addGeoJsonSource(id, GeoJson.empty));

  /// Runs something that may fail because it already exists.
  ///
  /// MapLibre throws when a repeated layer or source is added, and after a
  /// style change there's no cheap way to know which ones survived. Trying it
  /// and swallowing the duplicate error is simpler and faster than checking the
  /// layer list before each one.
  ///
  /// Whether it's there now: added, or already there.
  Future<bool> _tryAdd(Future<void> Function() action) async {
    try {
      await action();
      return true;
    } on Object catch (error) {
      final message = error.toString();
      final alreadyExists =
          message.contains('already exists') ||
          message.contains('ya existe') ||
          message.contains('duplicate');
      if (!alreadyExists) {
        debugPrint('nativ_maps: al instalar una capa — $error');
      }
      return alreadyExists;
    }
  }

  Future<void> _tryRemoveLayer(String id) async {
    try {
      await _native.removeLayer(id);
    } on Object {
      // It didn't exist. There's nothing to do.
    }
  }

  Future<void> _tryRemoveSource(String id) async {
    try {
      await _native.removeSource(id);
    } on Object {
      // It didn't exist.
    }
  }
}
