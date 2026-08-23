// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:async';
import 'dart:math' show Point;
import 'dart:ui' show Offset;

import 'package:compass_maps/compass_maps.dart';
import 'package:compass_maps_flutter/src/internal/geojson.dart';
import 'package:compass_maps_flutter/src/internal/layers.dart';
import 'package:compass_maps_flutter/src/offline/offline_manager.dart';
import 'package:compass_maps_flutter/src/style_editor.dart';
import 'package:compass_maps_flutter/src/types/camera.dart';
import 'package:compass_maps_flutter/src/types/overlays.dart';
import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

/// El mando del mapa.
///
/// Llega por `CompassMap.onMapCreated` y vive mientras viva el widget.
///
/// ## La forma es la de `google_maps_flutter`
///
/// `animateCamera`, `moveCamera`, `getVisibleRegion`, `getZoomLevel`,
/// `getScreenCoordinate`, `getLatLng`, `setMapStyle`, `takeSnapshot`… se
/// llaman igual y hacen lo mismo. Quien viene de Google no tiene nada que
/// aprender para la mitad de esto.
///
/// ## Lo que Google no tiene
///
/// [offline] —descargar regiones para usar el mapa sin red—, [heatmaps] con
/// rampa de color propia, y el agrupado nativo de [ClusterManager].
///
/// ## Cómo se extiende para un proyecto concreto
///
/// **No añadiendo métodos aquí.** Un framework para dieciocho proyectos no
/// puede saber qué es un vehículo ni qué es una muestra de agua. Cada proyecto
/// escribe su propia `extension` sobre este mismo controlador:
///
/// ```dart
/// extension MapaDeRastreo on CompassMapController {
///   Future<void> mostrarVehiculo(Vehiculo v) => addMarker(
///         Marker(
///           markerId: MarkerId(v.id),
///           position: v.posicion,
///           rotation: v.rumbo,
///           flat: true,
///         ),
///       );
/// }
/// ```
///
/// Una `extension` no hereda ni envuelve: no tiene coste en ejecución, no
/// bloquea el núcleo y borrarla no rompe nada debajo.
class CompassMapController {
  /// Uso interno: lo construye el widget.
  @internal
  CompassMapController({
    required ml.MapLibreMapController native,
    required LayerInstaller installer,
    required Future<void> Function() ensureStyleReady,
    required VoidCallback onOverlaysChanged,
    CompassOfflineManager? offline,
  }) : style = StyleEditor(native),
       _native = native,
       _installer = installer,
       _ensureStyleReady = ensureStyleReady,
       _onOverlaysChanged = onOverlaysChanged,
       _offline = offline;

  /// Retoca el estilo del mapa en caliente: apagar capas, cambiar colores,
  /// ajustar grosores.
  ///
  /// Lo que se cambie aquí **no sobrevive a un cambio de `styleUrl`**: hay que
  /// volver a aplicarlo en `CompassMap.onStyleLoaded`, que se llama en cada
  /// carga precisamente por esto.
  final StyleEditor style;

  final ml.MapLibreMapController _native;
  final LayerInstaller _installer;
  final Future<void> Function() _ensureStyleReady;
  final VoidCallback _onOverlaysChanged;
  final CompassOfflineManager? _offline;

  final Map<MarkerId, Marker> _markers = <MarkerId, Marker>{};
  final Map<PolylineId, Polyline> _polylines = <PolylineId, Polyline>{};
  final Map<PolygonId, Polygon> _polygons = <PolygonId, Polygon>{};
  final Map<CircleId, Circle> _circles = <CircleId, Circle>{};
  final Map<HeatmapId, Heatmap> _heatmaps = <HeatmapId, Heatmap>{};
  final Map<ClusterManagerId, ClusterManager> _clusterManagers =
      <ClusterManagerId, ClusterManager>{};
  final Set<String> _uploadedImages = <String>{};

  bool _disposed = false;
  bool _syncScheduled = false;

  // ═══════════════════════════════════════════════════════════════════════
  //  Cámara — los mismos nombres que en google_maps_flutter
  // ═══════════════════════════════════════════════════════════════════════

  /// Mueve la cámara con animación.
  Future<void> animateCamera(CameraUpdate update, {Duration? duration}) async {
    _checkAlive();
    await _native.animateCamera(await _toNative(update), duration: duration);
  }

  /// Mueve la cámara de golpe, sin animación.
  Future<void> moveCamera(CameraUpdate update) async {
    _checkAlive();
    await _native.moveCamera(await _toNative(update));
  }

  /// La posición actual de la cámara.
  ///
  /// Devuelve `null` si el mapa todavía no ha terminado de crearse. Se
  /// devuelve `null` en vez de un valor por defecto porque una cámara en
  /// `LatLng(0, 0)` con zoom 0 es un valor legítimo y se usaría como si fuera
  /// cierto.
  Future<CameraPosition?> getCameraPosition() async {
    _checkAlive();
    final native = await _native.queryCameraPosition();
    if (native == null) return null;
    return _fromNativeCamera(native);
  }

  /// El rectángulo que se ve ahora mismo en pantalla.
  Future<LatLngBounds> getVisibleRegion() async {
    _checkAlive();
    final region = await _native.getVisibleRegion();
    return LatLngBounds(
      southwest: LatLng(region.southwest.latitude, region.southwest.longitude),
      northeast: LatLng(region.northeast.latitude, region.northeast.longitude),
    );
  }

  /// El nivel de zoom actual.
  Future<double> getZoomLevel() async {
    final camera = await getCameraPosition();
    return camera?.zoom ?? 0;
  }

  /// De coordenada geográfica a píxeles de pantalla.
  Future<Offset> getScreenCoordinate(LatLng latLng) async {
    _checkAlive();
    final point = await _native.toScreenLocation(
      ml.LatLng(latLng.latitude, latLng.longitude),
    );
    return Offset(point.x.toDouble(), point.y.toDouble());
  }

  /// De píxeles de pantalla a coordenada geográfica.
  Future<LatLng> getLatLng(Offset screenCoordinate) async {
    _checkAlive();
    final latLng = await _native.toLatLng(
      Point<double>(screenCoordinate.dx, screenCoordinate.dy),
    );
    return LatLng(latLng.latitude, latLng.longitude);
  }

  /// Cuántos metros mide un píxel a esta latitud y este zoom.
  ///
  /// Es lo que hace falta para decidir el nivel de detalle de lo que se
  /// dibuja: por debajo de cierto tamaño real, un polígono no merece la pena
  /// pintarlo.
  Future<double> getMetersPerPixel(double latitude) async {
    _checkAlive();
    return _native.getMetersPerPixelAtLatitude(latitude);
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Marcadores
  // ═══════════════════════════════════════════════════════════════════════

  /// Los marcadores que hay ahora mismo.
  List<Marker> get markers => List<Marker>.unmodifiable(_markers.values);

  /// Añade o reemplaza un marcador.
  Future<void> addMarker(Marker marker) async {
    _checkAlive();
    _markers[marker.markerId] = marker;
    await _uploadIconIfNeeded(marker.icon);
    _scheduleSync();
  }

  /// Añade o reemplaza varios marcadores de una vez.
  ///
  /// **Es lo que hay que usar con más de un puñado.** Añadirlos de uno en uno
  /// funciona —la sincronización se agrupa igual—, pero esto evita también las
  /// subidas repetidas de la misma imagen.
  Future<void> addMarkers(Iterable<Marker> markers) async {
    _checkAlive();
    for (final marker in markers) {
      _markers[marker.markerId] = marker;
      await _uploadIconIfNeeded(marker.icon);
    }
    _scheduleSync();
  }

  /// Cambia un marcador que ya existe.
  ///
  /// Equivale a [addMarker]; existe con este nombre porque es el que usa
  /// `google_maps_flutter`.
  Future<void> updateMarker(Marker marker) => addMarker(marker);

  /// Quita un marcador.
  Future<void> removeMarker(MarkerId markerId) async {
    _checkAlive();
    if (_markers.remove(markerId) != null) _scheduleSync();
  }

  /// Deja exactamente el conjunto de marcadores indicado.
  ///
  /// Es la operación que corresponde a un `setState` con la lista entera:
  /// calcula qué sobra y qué falta en vez de borrar y volver a poner todo, que
  /// produce un parpadeo visible.
  Future<void> setMarkers(Iterable<Marker> markers) async {
    _checkAlive();
    final wanted = <MarkerId, Marker>{for (final m in markers) m.markerId: m};
    var changed = _markers.length != wanted.length;
    for (final entry in wanted.entries) {
      if (_markers[entry.key] != entry.value) {
        changed = true;
        await _uploadIconIfNeeded(entry.value.icon);
      }
    }
    if (!changed) return;
    _markers
      ..clear()
      ..addAll(wanted);
    _scheduleSync();
  }

  /// Quita todos los marcadores.
  Future<void> clearMarkers() async {
    _checkAlive();
    if (_markers.isEmpty) return;
    _markers.clear();
    _scheduleSync();
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Polilíneas, polígonos y círculos
  // ═══════════════════════════════════════════════════════════════════════

  /// Las polilíneas que hay ahora mismo.
  List<Polyline> get polylines =>
      List<Polyline>.unmodifiable(_polylines.values);

  /// Añade o reemplaza una polilínea.
  ///
  /// ```dart
  /// final ruta = (await maps.routes.calculateRoutes(...)).best!;
  /// // Sin convertir nada: los puntos de la ruta son LatLng de este paquete.
  /// await controller.addPolyline(
  ///   Polyline(polylineId: const PolylineId('ruta'), points: ruta.points),
  /// );
  /// ```
  Future<void> addPolyline(Polyline polyline) async {
    _checkAlive();
    _polylines[polyline.polylineId] = polyline;
    _scheduleSync();
  }

  /// Quita una polilínea.
  Future<void> removePolyline(PolylineId polylineId) async {
    _checkAlive();
    if (_polylines.remove(polylineId) != null) _scheduleSync();
  }

  /// Deja exactamente el conjunto de polilíneas indicado.
  Future<void> setPolylines(Iterable<Polyline> polylines) async {
    _checkAlive();
    _polylines
      ..clear()
      ..addEntries(polylines.map((p) => MapEntry(p.polylineId, p)));
    _scheduleSync();
  }

  /// Quita todas las polilíneas.
  Future<void> clearPolylines() async {
    _checkAlive();
    if (_polylines.isEmpty) return;
    _polylines.clear();
    _scheduleSync();
  }

  /// Los polígonos que hay ahora mismo.
  List<Polygon> get polygons => List<Polygon>.unmodifiable(_polygons.values);

  /// Añade o reemplaza un polígono.
  Future<void> addPolygon(Polygon polygon) async {
    _checkAlive();
    _polygons[polygon.polygonId] = polygon;
    _scheduleSync();
  }

  /// Quita un polígono.
  Future<void> removePolygon(PolygonId polygonId) async {
    _checkAlive();
    if (_polygons.remove(polygonId) != null) _scheduleSync();
  }

  /// Deja exactamente el conjunto de polígonos indicado.
  Future<void> setPolygons(Iterable<Polygon> polygons) async {
    _checkAlive();
    _polygons
      ..clear()
      ..addEntries(polygons.map((p) => MapEntry(p.polygonId, p)));
    _scheduleSync();
  }

  /// Quita todos los polígonos.
  Future<void> clearPolygons() async {
    _checkAlive();
    if (_polygons.isEmpty) return;
    _polygons.clear();
    _scheduleSync();
  }

  /// Los círculos que hay ahora mismo.
  List<Circle> get circles => List<Circle>.unmodifiable(_circles.values);

  /// Añade o reemplaza un círculo.
  Future<void> addCircle(Circle circle) async {
    _checkAlive();
    _circles[circle.circleId] = circle;
    _scheduleSync();
  }

  /// Quita un círculo.
  Future<void> removeCircle(CircleId circleId) async {
    _checkAlive();
    if (_circles.remove(circleId) != null) _scheduleSync();
  }

  /// Deja exactamente el conjunto de círculos indicado.
  Future<void> setCircles(Iterable<Circle> circles) async {
    _checkAlive();
    _circles
      ..clear()
      ..addEntries(circles.map((c) => MapEntry(c.circleId, c)));
    _scheduleSync();
  }

  /// Quita todos los círculos.
  Future<void> clearCircles() async {
    _checkAlive();
    if (_circles.isEmpty) return;
    _circles.clear();
    _scheduleSync();
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Mapas de calor — lo que en Google es un tipo cerrado
  // ═══════════════════════════════════════════════════════════════════════

  /// Los mapas de calor que hay ahora mismo.
  List<Heatmap> get heatmaps => List<Heatmap>.unmodifiable(_heatmaps.values);

  /// Añade o reemplaza un mapa de calor.
  ///
  /// Cada uno vive en su propia capa nativa: la rampa de color, el radio y la
  /// intensidad son suyos y no se comparten. En `google_maps_flutter` esto es
  /// un tipo cerrado con muy pocos mandos.
  Future<void> addHeatmap(Heatmap heatmap) async {
    _checkAlive();
    await _ensureStyleReady();
    _heatmaps[heatmap.heatmapId] = heatmap;
    await _installer.installHeatmap(heatmap);
    _scheduleSync();
  }

  /// Quita un mapa de calor.
  Future<void> removeHeatmap(HeatmapId heatmapId) async {
    _checkAlive();
    if (_heatmaps.remove(heatmapId) == null) return;
    await _installer.removeHeatmap(heatmapId);
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Agrupado — nativo, no calculado en Dart
  // ═══════════════════════════════════════════════════════════════════════

  /// Registra un agrupador de marcadores.
  ///
  /// Los marcadores cuyo `clusterManagerId` coincida se agrupan **en el
  /// motor**, no en Dart. La diferencia se nota a partir de unos pocos miles:
  /// el desplazamiento del mapa deja de tirones.
  ///
  /// Hay que registrarlo **antes** de añadir los marcadores que lo usan.
  Future<void> addClusterManager(ClusterManager manager) async {
    _checkAlive();
    await _ensureStyleReady();
    _clusterManagers[manager.clusterManagerId] = manager;
    await _installer.installCluster(manager);
    _scheduleSync();
  }

  /// Quita un agrupador y sus capas.
  Future<void> removeClusterManager(ClusterManagerId id) async {
    _checkAlive();
    if (_clusterManagers.remove(id) == null) return;
    await _installer.removeCluster(id);
    _scheduleSync();
  }

  /// A qué zoom se separa el grupo indicado.
  ///
  /// Es lo que permite que tocar un grupo lo abra en vez de no hacer nada.
  /// `google_maps_flutter` no puede dar este dato porque agrupa fuera del
  /// motor.
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
  //  Estilo
  // ═══════════════════════════════════════════════════════════════════════

  /// Cambia el estilo del mapa.
  ///
  /// Se le pasa la URL de `MapsClient.styleDescriptorUrl`. Cambiar el estilo
  /// **borra todas las capas y fuentes**, así que este método las reinstala y
  /// vuelve a empujar las superposiciones. Sin eso, cambiar a modo oscuro
  /// haría desaparecer todos los marcadores.
  Future<void> setMapStyle(String styleUrl) async {
    _checkAlive();
    await _native.setStyle(styleUrl);
    // El resto lo hace el widget al recibir el evento de estilo cargado.
  }

  /// Cabeceras HTTP propias para las peticiones del mapa.
  ///
  /// Es la pieza que hace posible el camino de SigV4 y el de proxy **también
  /// para las teselas**: sin esto, el estilo y las teselas solo se podrían
  /// autenticar con la clave en la URL.
  ///
  /// [urlFilter] limita a qué URLs se añaden; conviene acotarlo al host de
  /// Amazon Location para no mandar tus cabeceras a terceros.
  Future<void> setCustomHeaders(
    Map<String, String> headers, {
    List<String> urlFilter = const <String>['amazonaws.com'],
  }) async {
    _checkAlive();
    await _native.setCustomHeaders(headers, urlFilter);
  }

  /// Una captura del mapa tal como se ve ahora.
  ///
  /// Exige que el mapa esté montado y visible. Para una miniatura sin mapa en
  /// pantalla —una notificación, un PDF— está `MapsClient.staticMap`, que la
  /// pinta el servidor.
  Future<Uint8List> takeSnapshot({int? width, int? height}) {
    _checkAlive();
    return _native.takeSnapshot(width: width, height: height);
  }

  /// Vacía la caché de teselas del entorno.
  Future<void> clearTileCache() async {
    _checkAlive();
    await _native.clearAmbientCache();
  }

  /// Fuerza a pedir las teselas por red aunque haya copia local.
  Future<void> forceOnlineMode() async {
    _checkAlive();
    await _native.forceOnlineMode();
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Sin conexión — lo que google_maps_flutter no puede dar
  // ═══════════════════════════════════════════════════════════════════════

  /// Descargar regiones, gestionar la caché y borrar lo guardado.
  ///
  /// **`google_maps_flutter` no tiene modo sin conexión**, y no por una
  /// limitación técnica: las condiciones de Google prohíben cachear teselas.
  /// Por eso ningún envoltorio de Google lo ofrece.
  ///
  /// Devuelve `null` si el widget se creó sin `offlineEnabled: true`.
  ///
  /// ⚠️ Antes de usarlo en producción, leer la advertencia de
  /// [CompassOfflineManager]: que MapLibre **pueda** guardar teselas no
  /// significa que las condiciones de Amazon **permitan** guardar las suyas.
  CompassOfflineManager? get offline => _offline;

  // ═══════════════════════════════════════════════════════════════════════
  //  Interrogar el mapa
  // ═══════════════════════════════════════════════════════════════════════

  /// El marcador que hay bajo [screenPoint], o `null`.
  ///
  /// Usa el hit-test **nativo** del motor (`queryRenderedFeatures`), que
  /// acierta con la forma real del icono dibujado. Un hit-test hecho en Dart
  /// —recorrer los marcadores y quedarse con el más cercano en píxeles— falla
  /// con iconos grandes, con iconos girados y cuando dos se solapan.
  @internal
  Future<Marker?> markerAt(Offset screenPoint) async {
    if (_disposed || _markers.isEmpty) return null;
    try {
      final features = await _native.queryRenderedFeatures(
        Point<double>(screenPoint.dx, screenPoint.dy),
        <String>[
          LayerInstaller.markerLayerId,
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
      // Un hit-test que falla no debe tumbar el gesto: el mapa puede estar a
      // medio cargar, y el usuario simplemente ve que no pasa nada.
      return null;
    }
    return null;
  }

  /// El grupo que hay bajo [screenPoint], o `null`.
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

  /// La polilínea que hay bajo [screenPoint], o `null`.
  @internal
  Future<Polyline?> polylineAt(Offset screenPoint) async {
    if (_disposed || _polylines.isEmpty) return null;
    try {
      final features = await _native.queryRenderedFeatures(
        Point<double>(screenPoint.dx, screenPoint.dy),
        <String>[LayerInstaller.lineLayerId, LayerInstaller.dashedLineLayerId],
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
  //  Internos
  // ═══════════════════════════════════════════════════════════════════════

  /// Vuelve a instalar capas y a empujar los datos tras un cambio de estilo.
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
    _uploadedImages.clear();
    for (final marker in _markers.values) {
      await _uploadIconIfNeeded(marker.icon);
    }
    await syncNow();
  }

  /// Empuja el estado actual al mapa sin esperar al siguiente microtask.
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

  /// Agrupa las sincronizaciones en un solo empujón por microtask.
  ///
  /// Sin esto, añadir doscientos marcadores en un bucle serían doscientos
  /// cruces del canal de plataforma con la colección entera cada vez —trabajo
  /// cuadrático—. Con esto, es uno.
  void _scheduleSync() {
    if (_syncScheduled || _disposed) return;
    _syncScheduled = true;
    scheduleMicrotask(() async {
      if (_disposed) return;
      await syncNow();
    });
  }

  Future<void> _uploadIconIfNeeded(BitmapDescriptor icon) async {
    if (!icon.needsUpload || _uploadedImages.contains(icon.name)) return;
    try {
      await _native.addImage(icon.name, icon.bytes!);
      _uploadedImages.add(icon.name);
    } on Object catch (error) {
      debugPrint(
        'compass_maps: no se pudo registrar el icono '
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
        'CompassMapController usado después de que el widget se desmontara. '
        'Guardar el controlador en un campo y usarlo tras un `Navigator.pop` '
        'es la forma más común de llegar aquí.',
      );
    }
  }

  /// Uso interno: lo llama el widget al desmontarse.
  @internal
  void dispose() {
    _disposed = true;
    _markers.clear();
    _polylines.clear();
    _polygons.clear();
    _circles.clear();
    _heatmaps.clear();
    _clusterManagers.clear();
    _uploadedImages.clear();
  }
}
