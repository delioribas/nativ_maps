// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

/// Compatibility layer for migrating from `google_maps_flutter`.
///
/// ## What it does, in one sentence
///
/// It makes code written for `google_maps_flutter` compile and run against
/// Amazon Location **by changing the `import`**.
///
/// ```diff
/// - import 'package:google_maps_flutter/google_maps_flutter.dart';
/// + import 'package:nativ_maps_google/nativ_maps_google.dart';
/// ```
///
/// ## What it does NOT do
///
/// **It does not depend on `google_maps_flutter`**, it does not call any
/// Google API, and it does not need a Google key. There is nothing from Google
/// at runtime: only the vocabulary is borrowed.
///
/// ## The mechanism: `typedef` and `extension`, never classes
///
/// The core already uses Google's names: `LatLng` is `LatLng`, `Marker` is
/// `Marker`, and `CameraUpdate.newLatLngZoom()` is called just what Google
/// calls it. **There is nothing to translate**: most of this package is
/// re-exports.
///
/// The only things that differ are a few controller method names and the JSON
/// style, and those are handled with `extension`. Consequences:
///
/// - **Zero runtime cost.** An alias creates no objects.
/// - **The core stays free.** An `extension` neither inherits nor wraps.
/// - **Reversible.** Deleting this package breaks nothing underneath.
/// - **They coexist.** `animateCamera()` on one line and `showVehicle()` on the
///   next.
///
/// ## What is left out, and why
///
/// | Google method | Reason |
/// |---|---|
/// | `setIndoorEnabled` | Amazon Location has no indoor floor plans |
/// | `setLiteModeEnabled` | exclusive to Android + Google |
/// | `cloudMapId` | styles hosted in Google's cloud |
/// | `AdvancedMarker` | recent proprietary Google API |
///
/// They are left out and documented; **never a stub that silently returns
/// `null`**. A method that exists and does nothing is worse than one that
/// doesn't exist: the compiler catches the second.
library;

export 'package:nativ_maps_flutter/nativ_maps_flutter.dart';

export 'src/compat.dart' show GoogleMapsCompat, MapColorSchemeCompat, MapType;
export 'src/google_look.dart'
    show GoogleLook, GoogleLookApplier, GoogleLookRule;
export 'src/google_map_style.dart'
    show GoogleMapStyle, GoogleStyleReport, GoogleStyleRule, GoogleStyler;
export 'src/style_translator.dart' show GoogleStyleApplier;
