# nativ_maps

**Amazon Location Service v2 in pure Dart, shaped like Google Maps.**

All **44 operations** —Places, Routes, Maps, geofencing and device
tracking— behind a typed client, with a spending cap, retries and
**no Flutter dependency at all**.

```dart
import 'package:nativ_maps/nativ_maps.dart';

final maps = NativMaps(
  region: 'us-east-1',
  credentials: const ApiKeyCredentials('your-key'),
  language: 'es',
  budget: Budget(maxUnits: 500),
);

final results = await maps.places.searchText(queryText: 'gasolinera');
final route = await maps.routes.calculateRoutes(
  origin: here,
  destination: results.places.first.position!,
);
```

## Looking for the map?

This package **does not draw**. The widget lives in
[`nativ_maps_flutter`](https://pub.dev/packages/nativ_maps_flutter), which
re-exports all of this: installing just that one gets you all forty-four
operations plus the map.

This one lives apart so it can be **tested without an emulator** and used in
a command-line tool or a Dart server.

## The 44 operations

| Places · 7 | Routes · 5 | Maps · 5 |
|---|---|---|
| `autocomplete` | `calculateRoutes` | `styleDescriptorUrl` |
| `searchText` | `calculateRouteMatrix` | `staticMap` |
| `reverseGeocode` | **`calculateIsolines`** | `tileUrlTemplate` |
| `getPlace` | **`snapToRoads`** | `glyphsUrlTemplate` |
| `geocode` | `optimizeWaypoints` | `spritesUrl` |
| `searchNearby` | | |
| `suggest` | | |

The two in bold **do not exist in Google Maps**.

| Geofencing · 12 | Device tracking · 15 |
|---|---|
| `putGeofence` · `batchPutGeofence` | `batchUpdateDevicePosition` |
| `getGeofence` · `listGeofences` | `getDevicePosition` |
| `batchDeleteGeofence` | `batchGetDevicePosition` |
| `batchEvaluateGeofences` | `getDevicePositionHistory` |
| **`forecastGeofenceEvents`** | `listDevicePositions` |
| 5 for managing collections | **`verifyDevicePosition`** |
| | 9 for management and linking |

**`forecastGeofenceEvents`** warns **before** a device enters or leaves a
zone. **`verifyDevicePosition`** detects spoofed locations. Neither has an
equivalent in Google Maps.

> ⚠️ Geofencing and tracking belong to the **previous generation** of Amazon
> Location: you have to create a resource and they **do not accept an API
> key** —SigV4 credentials are needed—. The package checks this **before
> sending**, with a message that says what to do, instead of letting it
> arrive as a `403` identical to every other one.

## The calculation layer

Pure Dart, **no requests**: what you need on top of the service for a taxi,
bidding or tracking app to actually work.

| Class | What it solves |
|---|---|
| `TripRecorder` | measures the trip without GPS noise inflating it |
| `Tariff` | taximeter with an auditable breakdown, time bands and waiting time |
| `RouteTracker` | ETA per maneuver and off-route detection, no calls |
| `RideAuction` · `BidAdvisor` | inDrive-style auction and real profitability |
| `PriceAdvisor` | suggested price with the reason behind each factor |
| `TariffCalibration` | fits the tariff to the prices in your city |
| `DispatchPlanner` | the closest driver in time, not in a straight line |
| `TelemetryAnalyzer` | harsh acceleration, harsh braking, cornering and speeding |

A parked car with ±20 m of uncertainty racks up **more than 5 km** per hour
if you add up the distances between readings. `TripRecorder` racks up **less
than 50 m**. That difference is what the passenger ends up paying.

## Spending control

Amazon Location bills **per request**, and some requests cost more than one
unit:

| Operation | What it looks like | What it costs |
|---|---|---|
| `calculateIsolines` with 5 thresholds | 1 request | **5 units** |
| `calculateRouteMatrix` of 10×10 | 1 request | **100 units** |

`Budget` counts the real units and cuts off before sending. The service's
hard limits are also checked beforehand, with the math spelled out in the
error message.

## Documentation

- [Recipes](https://github.com/delioribas/nativ_maps/blob/main/doc/RECETAS.md) — 40 copy-paste examples
- [For AI agents](https://github.com/delioribas/nativ_maps/blob/main/AGENTS.md)
- [Coverage](https://github.com/delioribas/nativ_maps/blob/main/doc/COBERTURA.md)

## License

MIT
