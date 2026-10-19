// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

/// Amazon Location Service, shaped like Google Maps.
///
/// A MapLibre map widget with markers, polylines, polygons, circles,
/// clusters, heatmaps and **offline regions**, plus the 17 operations of
/// Places, Routes and Maps re-exported from the core.
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
/// **Installing just this package already gets you the 17 operations**: it
/// re-exports all of `nativ_maps`.
///
/// ## The rule that sums it up
///
/// If you know how to use `google_maps_flutter`, you already know how to use
/// half of this without reading anything. And the other half is what Google
/// didn't give you: isochrones, snap to roads, stop optimization, toll costs
/// and offline maps.
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
