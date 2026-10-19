// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

// Only annotations are used here, and they come from `meta`. Importing
// `package:flutter/foundation.dart` would be redundant on Flutter 3.32 and
// `meta` would be redundant on 3.44+; `meta` is chosen, since it works on both.
import 'package:meta/meta.dart';
import 'package:nativ_maps/nativ_maps.dart';

/// Where the map camera is.
///
/// Same name and same fields as in `google_maps_flutter`, with one difference
/// in vocabulary worth knowing: what Google calls [tilt], MapLibre calls
/// *pitch*. Here it's called `tilt` because the goal is for code coming from
/// Google to compile without touching it.
@immutable
class CameraPosition {
  /// Creates the camera position.
  const CameraPosition({
    required this.target,
    this.zoom = 0.0,
    this.bearing = 0.0,
    this.tilt = 0.0,
  });

  /// The point that sits at the center of the screen.
  final LatLng target;

  /// The zoom level. 0 is the whole world; 20, a doorway.
  final double zoom;

  /// Where north points, in degrees clockwise.
  final double bearing;

  /// The tilt in degrees. 0 is straight down; 60, almost at ground level.
  final double tilt;

  /// A copy with some fields changed.
  CameraPosition copyWith({
    LatLng? target,
    double? zoom,
    double? bearing,
    double? tilt,
  }) => CameraPosition(
    target: target ?? this.target,
    zoom: zoom ?? this.zoom,
    bearing: bearing ?? this.bearing,
    tilt: tilt ?? this.tilt,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraPosition &&
          target == other.target &&
          zoom == other.zoom &&
          bearing == other.bearing &&
          tilt == other.tilt;

  @override
  int get hashCode => Object.hash(target, zoom, bearing, tilt);

  @override
  String toString() =>
      'CameraPosition($target, zoom: $zoom, bearing: $bearing, tilt: $tilt)';
}

/// What kind of camera move it is.
enum _CameraUpdateKind {
  newCameraPosition,
  newLatLng,
  newLatLngBounds,
  newLatLngZoom,
  scrollBy,
  zoomBy,
  zoomIn,
  zoomOut,
  zoomTo,
  bearingTo,
  tiltTo,
}

/// A camera move command.
///
/// **All nine `google_maps_flutter` factories are here**, with the same name
/// and the same signature, plus `bearingTo` and `tiltTo`, which Google doesn't
/// have.
///
/// ```dart
/// controller.animateCamera(CameraUpdate.newLatLngZoom(position, 16));
/// controller.moveCamera(CameraUpdate.newLatLngBounds(route.bounds!, 48));
/// ```
///
/// It's an inert value: describing a move doesn't execute it and doesn't
/// touch the map. The controller applies it.
@immutable
class CameraUpdate {
  const CameraUpdate._(
    this._kind, {
    this.position,
    this.target,
    this.bounds,
    this.zoom,
    this.padding,
    this.dx,
    this.dy,
    this.bearing,
    this.tilt,
  });

  /// Takes the camera to a complete position.
  factory CameraUpdate.newCameraPosition(CameraPosition position) =>
      CameraUpdate._(_CameraUpdateKind.newCameraPosition, position: position);

  /// Centers on a point, keeping the zoom.
  factory CameraUpdate.newLatLng(LatLng target) =>
      CameraUpdate._(_CameraUpdateKind.newLatLng, target: target);

  /// Frames a rectangle with [padding] pixels of margin.
  ///
  /// It's the factory to use for showing a whole route or every vehicle at
  /// once: picking the zoom by hand gives framings that spill over the edges
  /// on some screens and leave room to spare on others.
  factory CameraUpdate.newLatLngBounds(
    LatLngBounds bounds, [
    double padding = 32,
  ]) => CameraUpdate._(
    _CameraUpdateKind.newLatLngBounds,
    bounds: bounds,
    padding: padding,
  );

  /// Centers on a point with a specific zoom.
  factory CameraUpdate.newLatLngZoom(LatLng target, double zoom) =>
      CameraUpdate._(
        _CameraUpdateKind.newLatLngZoom,
        target: target,
        zoom: zoom,
      );

  /// Scrolls the view by [dx] and [dy] pixels.
  factory CameraUpdate.scrollBy(double dx, double dy) =>
      CameraUpdate._(_CameraUpdateKind.scrollBy, dx: dx, dy: dy);

  /// Changes the zoom by [amount] levels, optionally around [focus].
  factory CameraUpdate.zoomBy(double amount, [LatLng? focus]) =>
      CameraUpdate._(_CameraUpdateKind.zoomBy, zoom: amount, target: focus);

  /// Zooms in one level.
  factory CameraUpdate.zoomIn() =>
      const CameraUpdate._(_CameraUpdateKind.zoomIn);

  /// Zooms out one level.
  factory CameraUpdate.zoomOut() =>
      const CameraUpdate._(_CameraUpdateKind.zoomOut);

  /// Sets the zoom to an absolute value.
  factory CameraUpdate.zoomTo(double zoom) =>
      CameraUpdate._(_CameraUpdateKind.zoomTo, zoom: zoom);

  /// Rotates the map to the given bearing.
  ///
  /// It doesn't exist in `google_maps_flutter`, where you have to rebuild a
  /// whole `CameraPosition` just to rotate.
  factory CameraUpdate.bearingTo(double bearing) =>
      CameraUpdate._(_CameraUpdateKind.bearingTo, bearing: bearing);

  /// Tilts the map to the given angle.
  factory CameraUpdate.tiltTo(double tilt) =>
      CameraUpdate._(_CameraUpdateKind.tiltTo, tilt: tilt);

  final _CameraUpdateKind _kind;

  /// The complete position, in [CameraUpdate.newCameraPosition].
  final CameraPosition? position;

  /// The target point, in the factories that center.
  final LatLng? target;

  /// The rectangle, in [CameraUpdate.newLatLngBounds].
  final LatLngBounds? bounds;

  /// The zoom, absolute or relative depending on the factory.
  final double? zoom;

  /// The margin in pixels, in [CameraUpdate.newLatLngBounds].
  final double? padding;

  /// Horizontal scroll in pixels.
  final double? dx;

  /// Vertical scroll in pixels.
  final double? dy;

  /// The bearing, in [CameraUpdate.bearingTo].
  final double? bearing;

  /// The tilt, in [CameraUpdate.tiltTo].
  final double? tilt;

  /// Applies this move to [current] and returns the resulting camera.
  ///
  /// The moves that need to know the screen size —framing a rectangle,
  /// scrolling by pixels— are resolved by the engine, not by this: here they
  /// return `null` and the controller takes the other path.
  @internal
  CameraPosition? resolve(CameraPosition current) => switch (_kind) {
    _CameraUpdateKind.newCameraPosition => position,
    _CameraUpdateKind.newLatLng => current.copyWith(target: target),
    _CameraUpdateKind.newLatLngZoom => current.copyWith(
      target: target,
      zoom: zoom,
    ),
    _CameraUpdateKind.zoomTo => current.copyWith(zoom: zoom),
    _CameraUpdateKind.zoomBy => current.copyWith(
      zoom: current.zoom + (zoom ?? 0),
      target: target ?? current.target,
    ),
    _CameraUpdateKind.zoomIn => current.copyWith(zoom: current.zoom + 1),
    _CameraUpdateKind.zoomOut => current.copyWith(zoom: current.zoom - 1),
    _CameraUpdateKind.bearingTo => current.copyWith(bearing: bearing),
    _CameraUpdateKind.tiltTo => current.copyWith(tilt: tilt),
    // These two need the canvas size.
    _CameraUpdateKind.newLatLngBounds || _CameraUpdateKind.scrollBy => null,
  };

  /// Whether it's a rectangle framing.
  @internal
  bool get isBoundsFit => _kind == _CameraUpdateKind.newLatLngBounds;

  /// Whether it's a scroll by pixels.
  @internal
  bool get isScrollBy => _kind == _CameraUpdateKind.scrollBy;

  @override
  String toString() => 'CameraUpdate.${_kind.name}';
}

/// How far the map can be zoomed in and out.
///
/// The same name as in `google_maps_flutter`.
@immutable
class MinMaxZoomPreference {
  /// Creates the preference.
  const MinMaxZoomPreference(this.minZoom, this.maxZoom);

  /// No limits: from 0 to 22.
  static const MinMaxZoomPreference unbounded = MinMaxZoomPreference(
    null,
    null,
  );

  /// The minimum zoom, or `null` to leave it unlimited.
  final double? minZoom;

  /// The maximum zoom, or `null` to leave it unlimited.
  final double? maxZoom;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MinMaxZoomPreference &&
          minZoom == other.minZoom &&
          maxZoom == other.maxZoom;

  @override
  int get hashCode => Object.hash(minZoom, maxZoom);
}
