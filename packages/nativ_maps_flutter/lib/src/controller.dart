// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'dart:async';
import 'dart:math' show Point;
import 'dart:ui' show Offset, Rect;

import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
// `meta` is imported explicitly, even though on Flutter 3.44+ the linter flags
// it as redundant: `package:flutter/foundation.dart` **does not re-export
// `@internal`** until recent versions, and this package declares Flutter 3.32
// as its floor. Without this import, anyone using it on 3.32 runs into twelve
// `undefined_annotation` errors.
// ignore: unnecessary_import
import 'package:meta/meta.dart';
import 'package:nativ_maps/nativ_maps.dart';
import 'package:nativ_maps_flutter/src/internal/default_pin.dart';
import 'package:nativ_maps_flutter/src/internal/geojson.dart';
import 'package:nativ_maps_flutter/src/internal/layers.dart';
import 'package:nativ_maps_flutter/src/offline/offline_manager.dart';
import 'package:nativ_maps_flutter/src/style_editor.dart';
import 'package:nativ_maps_flutter/src/types/camera.dart';
import 'package:nativ_maps_flutter/src/types/overlays.dart';

/// The remote control for the map.
///
/// It arrives through `NativMap.onMapCreated` and lives as long as the widget
/// does.
///
/// ## The shape is that of `google_maps_flutter`
///
/// `animateCamera`, `moveCamera`, `getVisibleRegion`, `getZoomLevel`,
/// `getScreenCoordinate`, `getLatLng`, `setMapStyle`, `takeSnapshot`… have the
/// same names and do the same thing. Anyone coming from Google has nothing to
/// learn for half of this.
///
/// ## What Google doesn't have
///
/// [offline] —downloading regions to use the map without a network—,
/// [heatmaps] with their own color ramp, and the native clustering of
/// [ClusterManager].
///
/// ## How to extend it for a specific project
///
/// **Not by adding methods here.** A framework for eighteen projects can't
/// know what a vehicle is, or a water sample. Each project writes its own
/// `extension` on this same controller:
///
/// ```dart
/// extension TrackingMap on NativMapController {
///   Future<void> showVehicle(Vehicle v) => addMarker(
///         Marker(
///           markerId: MarkerId(v.id),
///           position: v.position,
///           rotation: v.heading,
///           flat: true,
///         ),
///       );
/// }
/// ```
///
/// An `extension` neither inherits nor wraps: it has no runtime cost, it
/// doesn't lock the core, and deleting it breaks nothing underneath.
class NativMapController {
  /// Internal use: the widget builds it.
  @internal
  NativMapController({
    required ml.MapLibreMapController native,
    required LayerInstaller installer,
    required Future<void> Function() ensureStyleReady,
    required VoidCallback onOverlaysChanged,
    NativOfflineManager? offline,
  }) : style = StyleEditor(native),
       _native = native,
       _installer = installer,
       _ensureStyleReady = ensureStyleReady,
       _onOverlaysChanged = onOverlaysChanged,
       _offline = offline;

  /// Tweaks the map style at runtime: turning layers off, changing colors,
  /// adjusting widths.
  ///
  /// What you change here **does not survive a `styleUrl` change**: you have
  /// to apply it again in `NativMap.onStyleLoaded`, which is called on every
  /// load precisely for this reason.
  final StyleEditor style;

  final ml.MapLibreMapController _native;
  final LayerInstaller _installer;
  final Future<void> Function() _ensureStyleReady;
  final VoidCallback _onOverlaysChanged;
  final NativOfflineManager? _offline;

  final Map<MarkerId, Marker> _markers = <MarkerId, Marker>{};
  final Map<PolylineId, Polyline> _polylines = <PolylineId, Polyline>{};
  final Map<PolygonId, Polygon> _polygons = <PolygonId, Polygon>{};
  final Map<CircleId, Circle> _circles = <CircleId, Circle>{};
  final Map<HeatmapId, Heatmap> _heatmaps = <HeatmapId, Heatmap>{};
  final Map<ClusterManagerId, ClusterManager> _clusterManagers =
      <ClusterManagerId, ClusterManager>{};
  final Map<GroundOverlayId, GroundOverlay> _groundOverlays =
      <GroundOverlayId, GroundOverlay>{};
  final Map<TileOverlayId, TileOverlay> _tileOverlays =
      <TileOverlayId, TileOverlay>{};
  final Set<String> _uploadedImages = <String>{};

  bool _disposed = false;
  bool _syncScheduled = false;

  // ═══════════════════════════════════════════════════════════════════════
  //  Camera — the same names as in google_maps_flutter
  // ═══════════════════════════════════════════════════════════════════════

  /// Moves the camera with an animation.
  Future<void> animateCamera(CameraUpdate update, {Duration? duration}) async {
    _checkAlive();
    await _native.animateCamera(await _toNative(update), duration: duration);
  }

  /// Moves the camera at once, without an animation.
  Future<void> moveCamera(CameraUpdate update) async {
    _checkAlive();
    await _native.moveCamera(await _toNative(update));
  }

  /// The current camera position.
  ///
  /// Returns `null` if the map hasn't finished being created yet. It returns
  /// `null` instead of a default value because a camera at `LatLng(0, 0)` with
  /// zoom 0 is a legitimate value and would be used as if it were true.
  Future<CameraPosition?> getCameraPosition() async {
    _checkAlive();
    final native = await _native.queryCameraPosition();
    if (native == null) return null;
    return _fromNativeCamera(native);
  }

  /// The rectangle visible on screen right now.
  Future<LatLngBounds> getVisibleRegion() async {
    _checkAlive();
    final region = await _native.getVisibleRegion();
    return LatLngBounds(
      southwest: LatLng(region.southwest.latitude, region.southwest.longitude),
      northeast: LatLng(region.northeast.latitude, region.northeast.longitude),
    );
  }

  /// The current zoom level.
  Future<double> getZoomLevel() async {
    final camera = await getCameraPosition();
    return camera?.zoom ?? 0;
  }

  /// Engine pixels per Flutter logical pixel.
  ///
  /// `maplibre_gl` returns and takes screen positions in **physical pixels**
  /// on Android and in **points** on iOS. The widget sets the screen's pixel
  /// density here on Android and 1 everywhere else, and [getScreenCoordinate]
  /// and [getLatLng] always work in logical pixels.
  @internal
  double nativePixelRatio = 1;

  /// From a geographic coordinate to a screen position, in Flutter **logical
  /// pixels** —the ones `Positioned` uses—, the same on Android as on iOS.
  ///
  /// `google_maps_flutter` returns physical pixels on Android and logical ones
  /// on iOS; not here, and that's why a widget placed with this lands in the
  /// right spot on both.
  Future<Offset> getScreenCoordinate(LatLng latLng) async {
    _checkAlive();
    final point = await _native.toScreenLocation(
      ml.LatLng(latLng.latitude, latLng.longitude),
    );
    return Offset(point.x.toDouble(), point.y.toDouble()) / nativePixelRatio;
  }

  /// From a screen position, in logical pixels, to a geographic coordinate.
  /// The inverse of [getScreenCoordinate].
  Future<LatLng> getLatLng(Offset screenCoordinate) async {
    _checkAlive();
    final native = screenCoordinate * nativePixelRatio;
    final latLng = await _native.toLatLng(Point<double>(native.dx, native.dy));
    return LatLng(latLng.latitude, latLng.longitude);
  }

  /// How many meters one pixel spans at this latitude and this zoom.
  ///
  /// It's what you need to decide the level of detail of what gets drawn:
  /// below a certain real size, a polygon isn't worth painting.
  Future<double> getMetersPerPixel(double latitude) async {
    _checkAlive();
    return _native.getMetersPerPixelAtLatitude(latitude);
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Markers
  // ═══════════════════════════════════════════════════════════════════════

  /// The markers on the map right now.
  List<Marker> get markers => List<Marker>.unmodifiable(_markers.values);

  /// Adds or replaces a marker.
  Future<void> addMarker(Marker marker) async {
    _checkAlive();
    _markers[marker.markerId] = marker;
    await _uploadIconIfNeeded(marker.icon);
    _scheduleSync();
  }

  /// Adds or replaces several markers at once.
  ///
  /// **This is what to use for more than a handful.** Adding them one by one
  /// works —the sync is batched all the same—, but this also avoids uploading
  /// the same image over and over.
  Future<void> addMarkers(Iterable<Marker> markers) async {
    _checkAlive();
    for (final marker in markers) {
      _markers[marker.markerId] = marker;
      await _uploadIconIfNeeded(marker.icon);
    }
    _scheduleSync();
  }

  /// Changes a marker that already exists.
  ///
  /// Equivalent to [addMarker]; it exists under this name because it's the one
  /// `google_maps_flutter` uses.
  Future<void> updateMarker(Marker marker) => addMarker(marker);

  /// Removes a marker.
  Future<void> removeMarker(MarkerId markerId) async {
    _checkAlive();
    if (_markers.remove(markerId) != null) _scheduleSync();
  }

  /// Leaves exactly the given set of markers.
  ///
  /// It's the operation that matches a `setState` with the whole list: it
  /// works out what's extra and what's missing instead of removing everything
  /// and putting it back, which causes a visible flicker.
  Future<void> setMarkers(Iterable<Marker> markers) async {
    _checkAlive();
    final wanted = <MarkerId, Marker>{for (final m in markers) m.markerId: m};
    final changedIcons = <BitmapDescriptor>[
      for (final entry in wanted.entries)
        if (_markers[entry.key] != entry.value) entry.value.icon,
    ];
    if (changedIcons.isEmpty && _markers.length == wanted.length) return;
    // Into the collection first, like addMarker: a style that finishes
    // loading while the icons go up re-uploads what's in the collection, and
    // a marker still outside it would be left without its icon.
    _markers
      ..clear()
      ..addAll(wanted);
    for (final icon in changedIcons) {
      await _uploadIconIfNeeded(icon);
    }
    _scheduleSync();
  }

  /// Removes every marker.
  Future<void> clearMarkers() async {
    _checkAlive();
    if (_markers.isEmpty) return;
    _markers.clear();
    _scheduleSync();
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Polylines, polygons and circles
  // ═══════════════════════════════════════════════════════════════════════

  /// The polylines on the map right now.
  List<Polyline> get polylines =>
      List<Polyline>.unmodifiable(_polylines.values);

  /// Adds or replaces a polyline.
  ///
  /// ```dart
  /// final route = (await maps.routes.calculateRoutes(...)).best!;
  /// // No conversion at all: the route's points are this package's LatLng.
  /// await controller.addPolyline(
  ///   Polyline(polylineId: const PolylineId('route'), points: route.points),
  /// );
  /// ```
  Future<void> addPolyline(Polyline polyline) async {
    _checkAlive();
    _polylines[polyline.polylineId] = polyline;
    _scheduleSync();
  }

  /// Removes a polyline.
  Future<void> removePolyline(PolylineId polylineId) async {
    _checkAlive();
    if (_polylines.remove(polylineId) != null) _scheduleSync();
  }

  /// Leaves exactly the given set of polylines.
  Future<void> setPolylines(Iterable<Polyline> polylines) async {
    _checkAlive();
    _polylines
      ..clear()
      ..addEntries(polylines.map((p) => MapEntry(p.polylineId, p)));
    _scheduleSync();
  }

  /// Removes every polyline.
  Future<void> clearPolylines() async {
    _checkAlive();
    if (_polylines.isEmpty) return;
    _polylines.clear();
    _scheduleSync();
  }

  /// The polygons on the map right now.
  List<Polygon> get polygons => List<Polygon>.unmodifiable(_polygons.values);

  /// Adds or replaces a polygon.
  Future<void> addPolygon(Polygon polygon) async {
    _checkAlive();
    _polygons[polygon.polygonId] = polygon;
    _scheduleSync();
  }

  /// Removes a polygon.
  Future<void> removePolygon(PolygonId polygonId) async {
    _checkAlive();
    if (_polygons.remove(polygonId) != null) _scheduleSync();
  }

  /// Leaves exactly the given set of polygons.
  Future<void> setPolygons(Iterable<Polygon> polygons) async {
    _checkAlive();
    _polygons
      ..clear()
      ..addEntries(polygons.map((p) => MapEntry(p.polygonId, p)));
    _scheduleSync();
  }

  /// Removes every polygon.
  Future<void> clearPolygons() async {
    _checkAlive();
    if (_polygons.isEmpty) return;
    _polygons.clear();
    _scheduleSync();
  }

  /// The circles on the map right now.
  List<Circle> get circles => List<Circle>.unmodifiable(_circles.values);

  /// Adds or replaces a circle.
  Future<void> addCircle(Circle circle) async {
    _checkAlive();
    _circles[circle.circleId] = circle;
    _scheduleSync();
  }

  /// Removes a circle.
  Future<void> removeCircle(CircleId circleId) async {
    _checkAlive();
    if (_circles.remove(circleId) != null) _scheduleSync();
  }

  /// Leaves exactly the given set of circles.
  Future<void> setCircles(Iterable<Circle> circles) async {
    _checkAlive();
    _circles
      ..clear()
      ..addEntries(circles.map((c) => MapEntry(c.circleId, c)));
    _scheduleSync();
  }

  /// Removes every circle.
  Future<void> clearCircles() async {
    _checkAlive();
    if (_circles.isEmpty) return;
    _circles.clear();
    _scheduleSync();
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Heatmaps — what in Google is a closed type
  // ═══════════════════════════════════════════════════════════════════════

  /// The heatmaps on the map right now.
  List<Heatmap> get heatmaps => List<Heatmap>.unmodifiable(_heatmaps.values);

  /// Adds or replaces a heatmap.
  ///
  /// Each one lives in its own native layer: the color ramp, the radius and the
  /// intensity are its own and aren't shared. In `google_maps_flutter` this is
  /// a closed type with very few knobs.
  Future<void> addHeatmap(Heatmap heatmap) async {
    _checkAlive();
    await _ensureStyleReady();
    _heatmaps[heatmap.heatmapId] = heatmap;
    await _installer.installHeatmap(heatmap);
    _scheduleSync();
  }

  /// Removes a heatmap.
  Future<void> removeHeatmap(HeatmapId heatmapId) async {
    _checkAlive();
    if (_heatmaps.remove(heatmapId) == null) return;
    await _installer.removeHeatmap(heatmapId);
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Clustering — native, not computed in Dart
  // ═══════════════════════════════════════════════════════════════════════

  /// Registers a marker cluster manager.
  ///
  /// Markers whose `clusterManagerId` matches are clustered **in the engine**,
  /// not in Dart. The difference shows from a few thousand on: panning the map
  /// stops stuttering.
  ///
  /// It has to be registered **before** adding the markers that use it.
  Future<void> addClusterManager(ClusterManager manager) async {
    _checkAlive();
    await _ensureStyleReady();
    _clusterManagers[manager.clusterManagerId] = manager;
    await _installer.installCluster(manager);
    _scheduleSync();
  }

  /// Removes a cluster manager and its layers.
  Future<void> removeClusterManager(ClusterManagerId id) async {
    _checkAlive();
    if (_clusterManagers.remove(id) == null) return;
    await _installer.removeCluster(id);
    _scheduleSync();
  }

  /// The zoom at which the given cluster splits apart.
  ///
  /// It's what lets a tap on a cluster open it instead of doing nothing.
  /// `google_maps_flutter` can't provide this because it clusters outside the
  /// engine.
  Future<double> getClusterExpansionZoom(Cluster cluster) async {
    _checkAlive();
    if (cluster.clusterId == null) return 0;
    final zoom = await _native.getClusterExpansionZoom(
      LayerInstaller.clusterSourceId(cluster.clusterManagerId),
      cluster.clusterId!,
    );
    return zoom.toDouble();
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Ground and tile overlays
  // ═══════════════════════════════════════════════════════════════════════

  /// The ground overlays on the map right now.
  List<GroundOverlay> get groundOverlays =>
      List<GroundOverlay>.unmodifiable(_groundOverlays.values);

  /// Adds or replaces an image pinned to a rectangle of the map.
  ///
  /// It's drawn under the package's polygons, lines and markers, and over the
  /// base map: a building plan or a scanned map is background, and what's
  /// drawn on it has to stay readable.
  Future<void> addGroundOverlay(GroundOverlay overlay) async {
    _checkAlive();
    _groundOverlays[overlay.groundOverlayId] = overlay;
    await _installRasters();
  }

  /// Removes a ground overlay.
  Future<void> removeGroundOverlay(GroundOverlayId id) async {
    _checkAlive();
    if (_groundOverlays.remove(id) == null) return;
    await _installRasters();
  }

  /// Leaves exactly [overlays] as the ground overlays.
  Future<void> setGroundOverlays(Iterable<GroundOverlay> overlays) async {
    _checkAlive();
    _groundOverlays
      ..clear()
      ..addEntries(overlays.map((o) => MapEntry(o.groundOverlayId, o)));
    await _installRasters();
  }

  /// Removes every ground overlay.
  Future<void> clearGroundOverlays() => setGroundOverlays(const []);

  /// The tile overlays on the map right now.
  List<TileOverlay> get tileOverlays =>
      List<TileOverlay>.unmodifiable(_tileOverlays.values);

  /// Adds or replaces a layer of your own tiles over the base map.
  ///
  /// For data that's already served as tiles: land registry, network coverage,
  /// weather. It goes, like ground overlays, under the package's polygons,
  /// lines and markers.
  Future<void> addTileOverlay(TileOverlay overlay) async {
    _checkAlive();
    _tileOverlays[overlay.tileOverlayId] = overlay;
    await _installRasters();
  }

  /// Removes a tile overlay.
  Future<void> removeTileOverlay(TileOverlayId id) async {
    _checkAlive();
    if (_tileOverlays.remove(id) == null) return;
    await _installRasters();
  }

  /// Leaves exactly [overlays] as the tile overlays.
  Future<void> setTileOverlays(Iterable<TileOverlay> overlays) async {
    _checkAlive();
    _tileOverlays
      ..clear()
      ..addEntries(overlays.map((o) => MapEntry(o.tileOverlayId, o)));
    await _installRasters();
  }

  /// Removes every tile overlay.
  Future<void> clearTileOverlays() => setTileOverlays(const []);

  Future<void> _installRasters() async {
    await _ensureStyleReady();
    if (_disposed) return;
    await _installer.installRasterOverlays(
      _groundOverlays.values,
      _tileOverlays.values,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Style
  // ═══════════════════════════════════════════════════════════════════════

  /// Changes the map style.
  ///
  /// Pass it the URL from `MapsClient.styleDescriptorUrl`. Changing the style
  /// **deletes every layer and source**, so this method reinstalls them and
  /// pushes the overlays again. Without that, switching to dark mode would make
  /// every marker disappear.
  Future<void> setMapStyle(String styleUrl) async {
    _checkAlive();
    await _native.setStyle(styleUrl);
    // The widget does the rest when it gets the style-loaded event.
  }

  /// Custom HTTP headers for the map's requests.
  ///
  /// It's the piece that makes the SigV4 and proxy paths possible **for the
  /// tiles too**: without this, the style and the tiles could only be
  /// authenticated with the key in the URL.
  ///
  /// [urlFilter] is the **host names** they're added to —a host and its
  /// subdomains—, so your headers don't reach third parties. Behind a proxy,
  /// that's the proxy's host.
  ///
  /// They're host names, not patterns, on purpose: `maplibre_gl` matches the
  /// filter differently on each platform —the whole URL on Android, anywhere
  /// in it on iOS— and a plain `amazonaws.com` never matched a whole URL, so
  /// on Android the headers were never sent. Each host is turned here into a
  /// pattern that both match the same way: see [hostPatterns].
  Future<void> setCustomHeaders(
    Map<String, String> headers, {
    List<String> urlFilter = const <String>['amazonaws.com'],
  }) async {
    _checkAlive();
    await _native.setCustomHeaders(headers, hostPatterns(urlFilter));
  }

  /// Turns host names into URL patterns that match the host and its
  /// subdomains, over any scheme, port, path or query.
  ///
  /// The pattern is anchored at both ends, so it means the same thing whether
  /// it's matched against the whole URL —Android— or searched inside it —iOS—.
  @visibleForTesting
  static List<String> hostPatterns(Iterable<String> hosts) => <String>[
    for (final host in hosts.toSet())
      if (host.isNotEmpty)
        '^https?://([^/?#]*\\.)?${RegExp.escape(host)}(:[0-9]+)?([/?#].*)?\$',
  ];

  /// A snapshot of the map as it looks right now.
  ///
  /// It requires the map to be mounted and visible. For a thumbnail without a
  /// map on screen —a notification, a PDF— there's `MapsClient.staticMap`,
  /// which the server renders.
  Future<Uint8List> takeSnapshot({int? width, int? height}) {
    _checkAlive();
    return _native.takeSnapshot(width: width, height: height);
  }

  /// Empties the ambient tile cache.
  Future<void> clearTileCache() async {
    _checkAlive();
    await _native.clearAmbientCache();
  }

  /// Forces tiles to be fetched over the network even if there's a local copy.
  Future<void> forceOnlineMode() async {
    _checkAlive();
    await _native.forceOnlineMode();
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Offline — what google_maps_flutter can't give you
  // ═══════════════════════════════════════════════════════════════════════

  /// Download regions, manage the cache and delete what's stored.
  ///
  /// **`google_maps_flutter` has no offline mode**, and not because of a
  /// technical limitation: Google's terms forbid caching tiles. That's why no
  /// Google wrapper offers it.
  ///
  /// Returns `null` if the widget was created without `offlineEnabled: true`.
  ///
  /// ⚠️ Before using it in production, read the warning on
  /// [NativOfflineManager]: the fact that MapLibre **can** store tiles doesn't
  /// mean Amazon's terms **allow** storing theirs.
  NativOfflineManager? get offline => _offline;

  // ═══════════════════════════════════════════════════════════════════════
  //  Querying the map
  // ═══════════════════════════════════════════════════════════════════════

  /// The marker under [screenPoint], or `null`.
  ///
  /// It uses the engine's **native** hit-test (`queryRenderedFeatures`), which
  /// gets the actual shape of the drawn icon right. A hit-test done in Dart
  /// —going through the markers and keeping the closest one in pixels— fails
  /// with large icons, with rotated icons and when two overlap.
  @internal
  Future<Marker?> markerAt(Offset screenPoint) async {
    if (_disposed || _markers.isEmpty) return null;
    try {
      final features = await _native.queryRenderedFeatures(
        Point<double>(screenPoint.dx, screenPoint.dy),
        <String>[
          ...LayerInstaller.markerLayerIds,
          for (final id in _clusterManagers.keys)
            LayerInstaller.clusterMarkerLayerId(id),
        ],
        null,
      );
      for (final feature in features) {
        if (feature is! Map) continue;
        final properties = feature['properties'];
        if (properties is! Map) continue;
        final id = properties['id'];
        if (id is! String) continue;
        final marker = _markers[MarkerId(id)];
        if (marker != null) return marker;
      }
    } on Object {
      // A failing hit-test must not bring down the gesture: the map may be
      // half-loaded, and the user simply sees that nothing happens.
      return null;
    }
    return null;
  }

  /// The cluster under [screenPoint], or `null`.
  @internal
  Future<Cluster?> clusterAt(Offset screenPoint) async {
    if (_disposed || _clusterManagers.isEmpty) return null;
    for (final entry in _clusterManagers.entries) {
      try {
        final features = await _native.queryRenderedFeatures(
          Point<double>(screenPoint.dx, screenPoint.dy),
          <String>[LayerInstaller.clusterCircleLayerId(entry.key)],
          null,
        );
        for (final feature in features) {
          if (feature is! Map) continue;
          final properties = feature['properties'];
          final geometry = feature['geometry'];
          if (properties is! Map || geometry is! Map) continue;
          final count = properties['point_count'];
          final coordinates = geometry['coordinates'];
          if (count is! num || coordinates is! List) continue;
          return Cluster(
            clusterManagerId: entry.key,
            position: LatLng.fromLonLat(coordinates),
            pointCount: count.toInt(),
            clusterId: (properties['cluster_id'] as num?)?.toInt(),
          );
        }
      } on Object {
        continue;
      }
    }
    return null;
  }

  /// The polyline under [screenPoint], or `null`.
  @internal
  Future<Polyline?> polylineAt(Offset screenPoint) async {
    if (_disposed || _polylines.isEmpty) return null;
    // A line is a few pixels wide and a fingertip isn't: looking only at the
    // exact pixel missed most real taps. 12 dp around it, like the margin
    // MapLibre gives its own interactive layers.
    final tolerance = 12 * nativePixelRatio;
    // Each dash pattern lives in a layer of its own; the base id alone never
    // matched a dashed line.
    final dashPatterns = <String>{
      for (final line in _polylines.values)
        if (line.isDashed)
          GeoJson.dashArray(line.patterns, line.width).join(','),
    };
    try {
      final features = await _native.queryRenderedFeaturesInRect(
        Rect.fromCenter(
          center: screenPoint,
          width: tolerance * 2,
          height: tolerance * 2,
        ),
        <String>[
          LayerInstaller.lineLayerId,
          for (final pattern in dashPatterns)
            '${LayerInstaller.dashedLineLayerId}-$pattern',
        ],
        null,
      );
      for (final feature in features) {
        if (feature is! Map) continue;
        final properties = feature['properties'];
        if (properties is! Map) continue;
        final id = properties['id'];
        if (id is String) return _polylines[PolylineId(id)];
      }
    } on Object {
      return null;
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Internals
  // ═══════════════════════════════════════════════════════════════════════

  /// The marker with [id], as the controller has it now.
  @internal
  Marker? markerById(MarkerId id) => _markers[id];

  /// Moves a marker that's being dragged, and tells its callbacks.
  ///
  /// [featureId] is the native feature id the drag event carries — a number,
  /// sometimes as a string — and [phase] is the native `start`, `drag` or
  /// `end`. Only that marker's feature is pushed: sending the whole collection
  /// on every frame would stutter with a few hundred markers.
  @internal
  Future<void> handleMarkerDrag(
    Object featureId,
    LatLng position,
    ml.DragEventType phase,
  ) async {
    if (_disposed) return;
    final id = int.tryParse(featureId.toString());
    Marker? marker;
    for (final m in _markers.values) {
      if (GeoJson.featureId(m.markerId) == id) {
        marker = m;
        break;
      }
    }
    if (marker == null || !marker.draggable) return;

    final moved = marker.copyWith(position: position);
    _markers[marker.markerId] = moved;
    switch (phase) {
      case ml.DragEventType.start:
        marker.onDragStart?.call(position);
      case ml.DragEventType.drag:
        marker.onDrag?.call(position);
      case ml.DragEventType.end:
        marker.onDragEnd?.call(position);
    }

    final clusterId = moved.clusterManagerId;
    if (clusterId != null && _clusterManagers.containsKey(clusterId)) {
      // A clustered source regroups on every change: it gets the whole set.
      _scheduleSync();
    } else {
      await _installer.pushFeature(
        LayerInstaller.markerSourceId,
        GeoJson.marker(moved),
      );
    }
  }

  /// Reinstalls the layers and pushes the data again after a style change.
  @internal
  Future<void> reinstallAfterStyleChange() async {
    if (_disposed) return;
    await _installer.installBaseLayers();
    for (final manager in _clusterManagers.values) {
      await _installer.installCluster(manager);
    }
    for (final heatmap in _heatmaps.values) {
      await _installer.installHeatmap(heatmap);
    }
    await _installer.installRasterOverlays(
      _groundOverlays.values,
      _tileOverlays.values,
    );
    _uploadedImages.clear();
    for (final marker in _markers.values) {
      await _uploadIconIfNeeded(marker.icon);
    }
    await syncNow();
  }

  /// Pushes the current state to the map without waiting for the next
  /// microtask.
  @internal
  Future<void> syncNow() async {
    if (_disposed) return;
    _syncScheduled = false;

    final clustered = <ClusterManagerId, List<Marker>>{};
    final plain = <Marker>[];
    for (final marker in _markers.values) {
      final id = marker.clusterManagerId;
      if (id != null && _clusterManagers.containsKey(id)) {
        clustered.putIfAbsent(id, () => <Marker>[]).add(marker);
      } else {
        plain.add(marker);
      }
    }

    await _installer.push(
      LayerInstaller.markerSourceId,
      GeoJson.markers(plain),
    );
    for (final entry in _clusterManagers.entries) {
      await _installer.push(
        LayerInstaller.clusterSourceId(entry.key),
        GeoJson.markers(clustered[entry.key] ?? const <Marker>[]),
      );
    }

    final solid = _polylines.values.where((p) => !p.isDashed);
    final dashed = _polylines.values.where((p) => p.isDashed);
    await _installer.push(
      LayerInstaller.lineSourceId,
      GeoJson.polylines(solid),
    );
    await _installer.pushDashed(dashed);

    await _installer.push(
      LayerInstaller.areaSourceId,
      GeoJson.areas(_polygons.values, _circles.values),
    );

    for (final heatmap in _heatmaps.values) {
      await _installer.push(
        LayerInstaller.heatmapSourceId(heatmap.heatmapId),
        GeoJson.heatmap(heatmap),
      );
    }

    _onOverlaysChanged();
  }

  /// Batches the syncs into a single push per microtask.
  ///
  /// Without this, adding two hundred markers in a loop would be two hundred
  /// trips across the platform channel with the whole collection each time
  /// —quadratic work—. With this, it's one.
  ///
  /// It waits for the style: pushed before it loads —from `onMapCreated`, or
  /// during a style switch— the data failed with `STYLE_NOT_READY`. What
  /// changes meanwhile goes in the same push.
  void _scheduleSync() {
    if (_syncScheduled || _disposed) return;
    _syncScheduled = true;
    scheduleMicrotask(() async {
      try {
        await _ensureStyleReady();
      } on Object {
        // The style never loaded, and the widget already reported it. When a
        // style does load, its reinstall pushes everything.
        _syncScheduled = false;
        return;
      }
      if (_disposed) return;
      await syncNow();
    });
  }

  Future<void> _uploadIconIfNeeded(BitmapDescriptor icon) async {
    if (!icon.needsUpload || _uploadedImages.contains(icon.name)) return;
    try {
      // An image only goes into a loaded style: before, or in the middle of
      // a style switch, it failed with `STYLE_NOT_READY`.
      await _ensureStyleReady();
      if (_disposed) return;
      final bytes = icon.bytes ?? await DefaultPin.png(icon.hue ?? 0);
      await _native.addImage(icon.name, bytes);
      _uploadedImages.add(icon.name);
    } on Object catch (error) {
      debugPrint(
        'nativ_maps: no se pudo registrar el icono '
        '"${icon.name}" — $error',
      );
    }
  }

  Future<ml.CameraUpdate> _toNative(CameraUpdate update) async {
    if (update.isBoundsFit) {
      final bounds = update.bounds!;
      final padding = update.padding ?? 32;
      return ml.CameraUpdate.newLatLngBounds(
        ml.LatLngBounds(
          southwest: ml.LatLng(
            bounds.southwest.latitude,
            bounds.southwest.longitude,
          ),
          northeast: ml.LatLng(
            bounds.northeast.latitude,
            bounds.northeast.longitude,
          ),
        ),
        left: padding,
        top: padding,
        right: padding,
        bottom: padding,
      );
    }
    if (update.isScrollBy) {
      return ml.CameraUpdate.scrollBy(update.dx ?? 0, update.dy ?? 0);
    }

    final current =
        await getCameraPosition() ?? CameraPosition(target: LatLng(0, 0));
    final target = update.resolve(current) ?? current;
    return ml.CameraUpdate.newCameraPosition(
      ml.CameraPosition(
        target: ml.LatLng(target.target.latitude, target.target.longitude),
        zoom: target.zoom,
        bearing: target.bearing,
        tilt: target.tilt,
      ),
    );
  }

  static CameraPosition _fromNativeCamera(ml.CameraPosition native) =>
      CameraPosition(
        target: LatLng(native.target.latitude, native.target.longitude),
        zoom: native.zoom,
        bearing: native.bearing,
        tilt: native.tilt,
      );

  void _checkAlive() {
    if (_disposed) {
      throw StateError(
        'NativMapController usado después de que el widget se desmontara. '
        'Guardar el controlador en un campo y usarlo tras un `Navigator.pop` '
        'es la forma más común de llegar aquí.',
      );
    }
  }

  /// Internal use: the widget calls it when it unmounts.
  @internal
  void dispose() {
    _disposed = true;
    _markers.clear();
    _polylines.clear();
    _polygons.clear();
    _circles.clear();
    _heatmaps.clear();
    _clusterManagers.clear();
    _groundOverlays.clear();
    _tileOverlays.clear();
    _uploadedImages.clear();
  }
}
