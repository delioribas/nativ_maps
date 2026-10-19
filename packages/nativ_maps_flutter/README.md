# nativ_maps_flutter

**Amazon Location Service, shaped like Google Maps.**

A MapLibre map widget with markers, polylines, polygons, circles,
**native clustering**, **heatmaps** and **offline regions**, plus the
**44 operations** of Places, Routes, Maps, geofencing and device tracking.

```dart
import 'package:nativ_maps_flutter/nativ_maps_flutter.dart';

final maps = NativMaps(
  region: 'us-east-1',
  credentials: const ApiKeyCredentials('your-key'),
);

NativMap(
  styleUrl: maps.maps.styleDescriptorUrl(MapStyle.standard)!,
  initialCameraPosition: CameraPosition(
    target: LatLng(-0.1807, -78.4678),
    zoom: 13,
  ),
  onMapCreated: (controller) => _controller = controller,
);
```

**Installing just this package already gets you all 44 operations**: it
re-exports the entire core.

## The thesis

The `LatLng` a search returns is the one a marker accepts:

```dart
final route = (await maps.routes.calculateRoutes(
  origin: here, destination: there,
)).best!;

// No conversion at all.
await controller.addPolyline(
  Polyline(polylineId: const PolylineId('route'), points: route.points),
);
```

> If you know how to use `google_maps_flutter`, you already know how to use
> half of this without reading anything. And the other half is what Google
> didn't give you.

## What Google didn't give you

| | `google_maps_flutter` | Here |
|---|---|---|
| **Isochrones** | doesn't exist | `calculateIsolines` |
| **Snap to roads** | doesn't exist | `snapToRoads` |
| **Toll costs** | doesn't exist | `Toll` |
| **Offline maps** | **forbidden by its terms** | `controller.offline` |
| Search and geocoding | another API, another key | same client |
| Clustering | manager class in Dart | **native, in the engine** |
| Heatmap | closed type | **native layer** |
| Dark mode | filter over the tiles | **rendered by the server** |

## ⚠️ Android requirements

- **AGP 8.x**, not 9.x — `maplibre_gl` 0.27.0 is not yet compatible with AGP 9
- **JDK 21** — `flutter config --jdk-dir="/path/to/jdk-21"`

The details are under "Known limitations" in the
[repository README](https://github.com/delioribas/nativ_maps#limitaciones-conocidas).

## Documentation

- [Recipes](https://github.com/delioribas/nativ_maps/blob/main/doc/RECETAS.md) — 40 copy-paste examples
- [Migrating from google_maps_flutter](https://github.com/delioribas/nativ_maps/blob/main/doc/MIGRACION.md)
- [For AI agents](https://github.com/delioribas/nativ_maps/blob/main/AGENTS.md)
- [Coverage](https://github.com/delioribas/nativ_maps/blob/main/doc/COBERTURA.md)

## License

MIT. The map data belongs to Amazon Location Service and its providers;
**attribution is mandatory and must be visible**.
