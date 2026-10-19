# nativ_maps_google

**Compatibility layer for migrating from `google_maps_flutter`.**

```diff
- import 'package:google_maps_flutter/google_maps_flutter.dart';
+ import 'package:nativ_maps_google/nativ_maps_google.dart';
```

**It does not depend on `google_maps_flutter`**, it does not call any Google API
and it does not need a Google key. It only borrows the vocabulary.

## The mechanism: `typedef` and `extension`, never classes

The core already uses Google's names: `LatLng` is `LatLng` and `Marker` is
`Marker`. **There is nothing to translate**: most of this package is re-exports.
The little that differs —a few method names and the JSON style— goes in an
`extension`.

- **Zero runtime cost.** An alias creates no objects.
- **The core stays free.** An `extension` neither inherits nor wraps.
- **Reversible.** Deleting this package breaks nothing underneath.
- **They coexist.** `animateCamera()` and `showVehicle()` on the same object.

## It translates Google JSON styles

```dart
final report = await controller.setGoogleMapStyle(darkThemeJson);
if (!report.isComplete) debugPrint('$report');
```

All **27 `featureType`s**, **9 `elementType`s** and **8 *stylers*** from
Google's reference are modeled. The translation is **approximate** —MapLibre
organizes layers differently— and that is why it returns a report that **says
which rules were not applied**, instead of failing silently.

## Make it look like Google Maps

```dart
NativMap(
  styleUrl: maps.maps.styleDescriptorUrl(MapStyle.standard)!,
  initialCameraPosition: camera,
  onMapCreated: (c) => controller = c,
  // On every load: a style change undoes the tweaks.
  onStyleLoaded: () => controller.applyGoogleLook(),
)
```

It repaints the AWS standard style with the palette of current Google Maps,
measured in the app: bluish-gray streets with an edge, mint green parks,
light-blue water, shops in beige, bluish highways, and each place's text in its
category's color. Street names are no longer in uppercase.

**What doesn't change:** the typeface (the Amazon Location server doesn't serve
Roboto), the icons and the data —there will be businesses and buildings that
Google has and AWS doesn't—. Only for `MapStyle.standard` in the light scheme.

## What is left out, and why

| Google method | Reason |
|---|---|
| `setIndoorEnabled` | Amazon Location has no indoor floor plans |
| `setLiteModeEnabled` | exclusive to Android + Google |
| `cloudMapId` | styles hosted in Google's cloud |
| `AdvancedMarker` | recent proprietary Google API |

**They are left out and documented; never a stub that silently returns `null`.**
A method that exists and does nothing is worse than one that doesn't exist: the
compiler catches the second.

## Full guide

[doc/MIGRACION.md](https://github.com/delioribas/nativ_maps/blob/main/doc/MIGRACION.md)
