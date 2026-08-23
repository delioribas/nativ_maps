// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

/// Amazon Location Service con la forma de Google Maps.
///
/// Un widget de mapa sobre MapLibre con marcadores, polilíneas, polígonos,
/// círculos, clústeres, mapas de calor y **regiones sin conexión**, más las
/// 17 operaciones de Places, Routes y Maps reexportadas del núcleo.
///
/// ```dart
/// import 'package:nativ_maps_flutter/nativ_maps_flutter.dart';
///
/// final maps = NativMaps(
///   region: 'us-east-1',
///   credentials: const ApiKeyCredentials('...'),
/// );
///
/// NativMap(
///   styleUrl: maps.maps.styleDescriptorUrl(MapStyle.standard)!,
///   initialCameraPosition: CameraPosition(
///     target: LatLng(-0.1807, -78.4678),
///     zoom: 13,
///   ),
///   onMapCreated: (c) => controller = c,
/// );
/// ```
///
/// **Instalando solo este paquete ya tienes las 17 operaciones**: reexporta
/// `nativ_maps` entero.
///
/// ## La regla que lo resume
///
/// Si sabes usar `google_maps_flutter`, ya sabes usar la mitad de esto sin
/// leer nada. Y la otra mitad es lo que Google no te daba: isócronas, pegado a
/// carretera, optimización de paradas, coste de peajes y mapas sin conexión.
library;

export 'package:nativ_maps/nativ_maps.dart';

export 'src/controller.dart' show NativMapController;
export 'src/nativ_map.dart' show NativMap, MyLocationTracking;
export 'src/offline/offline_manager.dart'
    show NativOfflineManager, DownloadProgress, OfflineRegion;
export 'src/style_editor.dart' show StyleEditor, StyleLayer, StyleLayerType;
export 'src/types/camera.dart'
    show CameraPosition, CameraUpdate, MinMaxZoomPreference;
export 'src/types/overlays.dart'
    show
        BitmapDescriptor,
        Cap,
        Circle,
        CircleId,
        Cluster,
        ClusterManager,
        ClusterManagerId,
        GroundOverlay,
        GroundOverlayId,
        Heatmap,
        HeatmapId,
        InfoWindow,
        JointType,
        Marker,
        MarkerHue,
        MarkerId,
        PatternItem,
        Polygon,
        PolygonId,
        Polyline,
        PolylineId,
        TileOverlay,
        TileOverlayId;
