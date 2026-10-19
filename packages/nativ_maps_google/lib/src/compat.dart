// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'package:flutter/foundation.dart';
import 'package:nativ_maps_flutter/nativ_maps_flutter.dart';
import 'package:nativ_maps_google/src/google_map_style.dart';
import 'package:nativ_maps_google/src/style_translator.dart';

/// The controller with the exact names from `google_maps_flutter`.
///
/// ## The mechanism: `extension`, never classes
///
/// This neither wraps the controller nor inherits from it. It is an
/// `extension`, and that has four consequences no wrapper class gives you:
///
/// - **Zero runtime cost.** An extension method is resolved at compile time;
///   no object is created.
/// - **The core stays free.** There is no hierarchy to respect and no contract
///   to maintain downstream.
/// - **Reversible.** Deleting this package breaks nothing underneath: code that
///   already uses the core's own names stays the same.
/// - **They coexist.** `animateCamera()` on one line and `showVehicle()` on the
///   next, on the same object.
///
/// ## What is left out, and why
///
/// Rule 2 of the design says: **nothing exists here that the core can't do**.
/// If `google_maps_flutter` has a method with no real equivalent, it is left
/// out and documented — never a stub that silently returns `null`, because
/// that is fake compatibility and every stub ends up as a ticket.
///
/// The three that are missing, with their reason:
///
/// | Google method | Why it isn't here |
/// |---|---|
/// | `setIndoorEnabled` | Amazon Location has no indoor floor plans |
/// | `setLiteModeEnabled` | exclusive to Android + Google |
/// | `cloudMapId` | styles hosted in Google's cloud |
///
/// Nor is `AdvancedMarker`: it is a recent proprietary Google API with nothing
/// equivalent.
extension GoogleMapsCompat on NativMapController {
  /// The current zoom level. Alias of `getZoomLevel`.
  Future<double> get zoomLevel => getZoomLevel();

  /// Changes several markers at once.
  ///
  /// In `google_maps_flutter` this takes an updates object; here it takes the
  /// set that should remain, which is what it really does.
  Future<void> updateMarkers(Set<Marker> markers) => setMarkers(markers);

  /// Changes several polylines at once.
  Future<void> updatePolylines(Set<Polyline> polylines) =>
      setPolylines(polylines);

  /// Changes several polygons at once.
  Future<void> updatePolygons(Set<Polygon> polygons) => setPolygons(polygons);

  /// Changes several circles at once.
  Future<void> updateCircles(Set<Circle> circles) => setCircles(circles);

  /// Moves the camera with animation and a configuration.
  ///
  /// It is the `google_maps_flutter` 2.12 version with `duration`. Returns
  /// whether the movement completed.
  Future<bool> animateCameraWithConfiguration(
    CameraUpdate update, {
    Duration? duration,
  }) async {
    await animateCamera(update, duration: duration);
    return true;
  }

  /// Moves the camera without animation, with a configuration.
  Future<bool> moveCameraWithConfiguration(CameraUpdate update) async {
    await moveCamera(update);
    return true;
  }

  /// Applies a JSON style from Google's Styling Wizard.
  ///
  /// **It is a translation, not an equivalence.** Returns a
  /// [GoogleStyleReport] with which rules were applied and which found no
  /// layer; it is worth logging the first time you migrate a theme.
  ///
  /// ```dart
  /// final report = await controller.setGoogleMapStyle(darkThemeJson);
  /// if (!report.isComplete) debugPrint('$report');
  /// ```
  ///
  /// In `google_maps_flutter` this method returns `void` and the error is
  /// queried later with `getStyleError()`. Here the result comes right back,
  /// which is where it is useful.
  Future<GoogleStyleReport> setGoogleMapStyle(String styleJson) async {
    final style = GoogleMapStyle.parse(styleJson);
    return applyGoogleStyle(style);
  }

  /// The last style error.
  ///
  /// It exists for compatibility with Google's `getStyleError()`. It always
  /// returns `null` because [setGoogleMapStyle] already returns the result
  /// directly, which is a better place to look at it.
  Future<String?> getStyleError() async => null;

  /// Alias of `getVisibleRegion`, already identical.
  Future<LatLngBounds> get visibleRegion => getVisibleRegion();
}

/// The map types from `google_maps_flutter`, with their equivalent here.
///
/// The equivalence is not exact, and it is worth knowing where:
///
/// | Google's `MapType` | Here | Note |
/// |---|---|---|
/// | `normal` | [MapStyle.standard] | identical |
/// | `satellite` | [MapStyle.satellite] | identical |
/// | `hybrid` | [MapStyle.hybrid] | identical |
/// | `terrain` | [MapStyle.standard] + relief | **better**: it is a parameter |
/// | `none` | — | doesn't exist: MapLibre always draws the style's background |
enum MapType {
  /// The full-color street map.
  normal,

  /// Satellite imagery only.
  satellite,

  /// Satellite with labels on top.
  hybrid,

  /// Terrain relief.
  ///
  /// It comes out better here than in Google: [asMapStyle] returns the
  /// standard style and [terrainOption] says which relief to ask the
  /// descriptor for.
  terrain;

  /// The matching Amazon Location style.
  MapStyle get asMapStyle => switch (this) {
    MapType.normal => MapStyle.standard,
    MapType.satellite => MapStyle.satellite,
    MapType.hybrid => MapStyle.hybrid,
    MapType.terrain => MapStyle.standard,
  };

  /// The relief to ask the descriptor for, if any.
  ///
  /// Only [MapType.terrain] returns something. It is the piece that makes
  /// terrain mode come out better than in Google: instead of a closed style,
  /// it is a parameter that can be raised to [MapTerrain.terrain3d].
  MapTerrain? get terrainOption =>
      this == MapType.terrain ? MapTerrain.hillshade : null;
}

/// The color scheme from `google_maps_flutter` 2.12.
///
/// The equivalent here is **better**: [MapColorScheme] is rendered by the
/// server, so dark mode is not a filter over light tiles and the labels stay
/// readable.
enum MapColorSchemeCompat {
  /// Light mode.
  light,

  /// Dark mode.
  dark,

  /// Follows the system theme.
  followSystem;

  /// The Amazon Location scheme.
  ///
  /// [platformBrightness] is only used with [followSystem]; it comes from
  /// `MediaQuery.platformBrightnessOf(context)`.
  MapColorScheme resolve(Brightness platformBrightness) => switch (this) {
    MapColorSchemeCompat.light => MapColorScheme.light,
    MapColorSchemeCompat.dark => MapColorScheme.dark,
    MapColorSchemeCompat.followSystem =>
      platformBrightness == Brightness.dark
          ? MapColorScheme.dark
          : MapColorScheme.light,
  };
}
