// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
// `meta` is explicit because of `@internal`, even though the Flutter 3.44+
// linter flags it as redundant: `flutter/foundation.dart` doesn't re-export it
// until recent versions and the declared floor is Flutter 3.32. Version 0.5.1
// removed it and didn't compile on 3.32.
// ignore: unnecessary_import
import 'package:meta/meta.dart' show internal;
import 'package:nativ_maps/nativ_maps.dart';

/// A marker's identifier. Same name as in `google_maps_flutter`.
///
/// It's a type and not a `String` on purpose: it prevents passing a polyline's
/// identifier where a marker's goes, which compiles without complaint if both
/// are strings.
@immutable
class MarkerId {
  /// Creates the identifier.
  const MarkerId(this.value);

  /// The value.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MarkerId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'MarkerId($value)';
}

/// A polyline's identifier.
@immutable
class PolylineId {
  /// Creates the identifier.
  const PolylineId(this.value);

  /// The value.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PolylineId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'PolylineId($value)';
}

/// A polygon's identifier.
@immutable
class PolygonId {
  /// Creates the identifier.
  const PolygonId(this.value);

  /// The value.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PolygonId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'PolygonId($value)';
}

/// A circle's identifier.
@immutable
class CircleId {
  /// Creates the identifier.
  const CircleId(this.value);

  /// The value.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is CircleId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'CircleId($value)';
}

/// A heatmap's identifier.
@immutable
class HeatmapId {
  /// Creates the identifier.
  const HeatmapId(this.value);

  /// The value.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is HeatmapId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'HeatmapId($value)';
}

/// A marker's icon.
///
/// In `google_maps_flutter` this is `BitmapDescriptor`. Here the name is the
/// same so migrated code compiles, but the implementation is different:
/// MapLibre works with images registered in the style by name, so an icon is
/// an image that's registered once and referenced many times.
///
/// That difference is an advantage: a hundred markers with the same icon
/// upload the image **once**.
@immutable
class BitmapDescriptor {
  const BitmapDescriptor._({required this.name, this.bytes, this.hue});

  static const String _defaultPinPrefix = 'nativ-default-marker-';

  /// The default red pin, like Google's.
  ///
  /// The package draws it itself: the style doesn't come with any marker icon.
  static const BitmapDescriptor defaultMarker = BitmapDescriptor._(
    name: '${_defaultPinPrefix}0',
    hue: hueRed,
  );

  /// The default pin tinted with a color.
  ///
  /// [hue] goes from 0 to 360, as in `google_maps_flutter`, and the same
  /// constants work: [hueAzure], [hueGreen]… (also in [MarkerHue]).
  static BitmapDescriptor defaultMarkerWithHue(double hue) =>
      BitmapDescriptor._(
        name: '$_defaultPinPrefix${hue.round() % 360}',
        hue: hue,
      );

  /// An icon from the bytes of a PNG image.
  ///
  /// [name] has to be unique per image: it's the key it's registered under in
  /// the style. Two different icons with the same name overwrite each other.
  factory BitmapDescriptor.fromBytes(String name, Uint8List bytes) =>
      BitmapDescriptor._(name: name, bytes: bytes);

  /// An icon already registered in the style, by its name.
  ///
  /// It lets you use the icons the Amazon Location style itself ships with,
  /// without uploading anything.
  factory BitmapDescriptor.fromStyleImage(String name) =>
      BitmapDescriptor._(name: name);

  /// The key the image lives under in the style.
  final String name;

  /// The bytes, if it has to be registered.
  final Uint8List? bytes;

  /// The hue, from 0 to 360.
  final double? hue;

  /// Whether it's one of the default pins, which the package draws.
  @internal
  bool get isDefaultPin => bytes == null && name.startsWith(_defaultPinPrefix);

  /// Whether this image has to be uploaded to the style.
  ///
  /// The default pins too: if they aren't registered, the layer asks for an
  /// image that doesn't exist and the marker isn't drawn.
  bool get needsUpload => bytes != null || isDefaultPin;

  // The `google_maps_flutter` hues, in the same place as there:
  // `BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure)`
  // compiles without changing anything.

  /// Red, the default color.
  static const double hueRed = MarkerHue.hueRed;

  /// Orange.
  static const double hueOrange = MarkerHue.hueOrange;

  /// Yellow.
  static const double hueYellow = MarkerHue.hueYellow;

  /// Green.
  static const double hueGreen = MarkerHue.hueGreen;

  /// Cyan.
  static const double hueCyan = MarkerHue.hueCyan;

  /// Azure blue.
  static const double hueAzure = MarkerHue.hueAzure;

  /// Dark blue.
  static const double hueBlue = MarkerHue.hueBlue;

  /// Violet.
  static const double hueViolet = MarkerHue.hueViolet;

  /// Magenta.
  static const double hueMagenta = MarkerHue.hueMagenta;

  /// Rose.
  static const double hueRose = MarkerHue.hueRose;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BitmapDescriptor && other.name == name && other.hue == hue;

  @override
  int get hashCode => Object.hash(name, hue);
}

/// The named hues of `google_maps_flutter`, so migrated code compiles without
/// looking up the numbers.
abstract final class MarkerHue {
  /// Red, Google's default color.
  static const double hueRed = 0.0;

  /// Orange.
  static const double hueOrange = 30.0;

  /// Yellow.
  static const double hueYellow = 60.0;

  /// Green.
  static const double hueGreen = 120.0;

  /// Cyan.
  static const double hueCyan = 180.0;

  /// Azure blue.
  static const double hueAzure = 210.0;

  /// Dark blue.
  static const double hueBlue = 240.0;

  /// Violet.
  static const double hueViolet = 270.0;

  /// Magenta.
  static const double hueMagenta = 300.0;

  /// Rose.
  static const double hueRose = 330.0;
}

/// The info window that pops up when a marker is tapped.
///
/// **It's reimplemented as a Flutter widget**, not as a native view. You lose
/// the exact look of Google's and gain the ability to put **anything** inside:
/// a photo, a button, a list. It's the §4 change the table marks as
/// "reimplemented".
@immutable
class InfoWindow {
  /// Creates the window.
  const InfoWindow({
    this.title,
    this.snippet,
    this.anchor = const Offset(0.5, 0.0),
    this.onTap,
    this.builder,
  });

  /// An empty window: the marker shows nothing when tapped.
  static const InfoWindow noText = InfoWindow();

  /// The title, in bold.
  final String? title;

  /// The secondary line.
  final String? snippet;

  /// Where it anchors relative to the icon. `(0.5, 0)` is top center.
  final Offset anchor;

  /// What to do when the window is tapped.
  final VoidCallback? onTap;

  /// Custom content. If passed, [title] and [snippet] are ignored.
  ///
  /// This is where the reimplementation pays off: any widget will do.
  final Widget Function(BuildContext context)? builder;

  /// Whether there's anything to show.
  bool get isEmpty => title == null && snippet == null && builder == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InfoWindow &&
          title == other.title &&
          snippet == other.snippet &&
          anchor == other.anchor;

  @override
  int get hashCode => Object.hash(title, snippet, anchor);
}

/// A marker on the map.
///
/// Same field names as in `google_maps_flutter`, so migrated code compiles
/// without touching it.
@immutable
class Marker {
  /// Creates the marker.
  const Marker({
    required this.markerId,
    required this.position,
    this.icon = BitmapDescriptor.defaultMarker,
    this.infoWindow = InfoWindow.noText,
    this.alpha = 1.0,
    this.anchor = const Offset(0.5, 1.0),
    this.draggable = false,
    this.flat = false,
    this.rotation = 0.0,
    this.visible = true,
    this.zIndex = 0.0,
    this.iconScale = 1.0,
    this.label,
    this.onTap,
    this.onDragStart,
    this.onDrag,
    this.onDragEnd,
    this.clusterManagerId,
  });

  /// The identifier. Two markers with the same one overwrite each other.
  final MarkerId markerId;

  /// Where it is.
  final LatLng position;

  /// The icon.
  final BitmapDescriptor icon;

  /// The info window that pops up when it's tapped.
  final InfoWindow infoWindow;

  /// The opacity, from 0 to 1.
  final double alpha;

  /// Which point of the icon rests on the coordinate. `(0.5, 1)` is the bottom
  /// tip, which is what a pin wants.
  final Offset anchor;

  /// Whether it can be dragged.
  ///
  /// Pressing on it and moving the finger drags the marker instead of the map,
  /// and [onDragStart], [onDrag] and [onDragEnd] report where it goes. The
  /// controller keeps the new position: `NativMapController.markers` returns
  /// it and the next `addMarker` with the same id starts from it.
  final bool draggable;

  /// Whether it stays flat on the map when it's rotated and tilted.
  ///
  /// `true` is what you want for a vehicle's icon, which has to turn with the
  /// street. `false` keeps it always facing the viewer, like a pin.
  final bool flat;

  /// The rotation in degrees. For a vehicle, the GPS heading.
  final double rotation;

  /// Whether it's drawn.
  final bool visible;

  /// The stacking order: higher goes on top.
  final double zIndex;

  /// The icon's size; 1 is the original.
  final double iconScale;

  /// A text under the icon. The license plate, for example.
  ///
  /// If it collides with another marker or another text, **it's hidden** until
  /// you zoom in and it stops colliding; the icon stays visible. It's what
  /// keeps a hundred license plates together from becoming an unreadable
  /// smudge, but it means a text isn't guaranteed at every zoom.
  final String? label;

  /// What to do when it's tapped.
  final VoidCallback? onTap;

  /// Called when a drag ends, with the position where it was dropped.
  final void Function(LatLng position)? onDragEnd;

  /// Called when a drag starts, with the marker's position at that moment.
  ///
  /// Only for markers with [draggable] set.
  final void Function(LatLng position)? onDragStart;

  /// Called on every step of a drag, with the position under the finger.
  ///
  /// It fires once per frame: anything expensive belongs in [onDragEnd].
  final void Function(LatLng position)? onDrag;

  /// Which cluster manager it belongs to, if it's clustered.
  final ClusterManagerId? clusterManagerId;

  /// A copy with some fields changed.
  ///
  /// It's what you use to move a vehicle: `copyWith(position:, rotation:)` on
  /// every new position.
  Marker copyWith({
    LatLng? position,
    BitmapDescriptor? icon,
    InfoWindow? infoWindow,
    double? alpha,
    Offset? anchor,
    bool? draggable,
    bool? flat,
    double? rotation,
    bool? visible,
    double? zIndex,
    double? iconScale,
    String? label,
    VoidCallback? onTap,
    void Function(LatLng position)? onDragStart,
    void Function(LatLng position)? onDrag,
    void Function(LatLng position)? onDragEnd,
    ClusterManagerId? clusterManagerId,
  }) => Marker(
    markerId: markerId,
    position: position ?? this.position,
    icon: icon ?? this.icon,
    infoWindow: infoWindow ?? this.infoWindow,
    alpha: alpha ?? this.alpha,
    anchor: anchor ?? this.anchor,
    draggable: draggable ?? this.draggable,
    flat: flat ?? this.flat,
    rotation: rotation ?? this.rotation,
    visible: visible ?? this.visible,
    zIndex: zIndex ?? this.zIndex,
    iconScale: iconScale ?? this.iconScale,
    label: label ?? this.label,
    onTap: onTap ?? this.onTap,
    onDragStart: onDragStart ?? this.onDragStart,
    onDrag: onDrag ?? this.onDrag,
    onDragEnd: onDragEnd ?? this.onDragEnd,
    clusterManagerId: clusterManagerId ?? this.clusterManagerId,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Marker &&
          markerId == other.markerId &&
          position == other.position &&
          icon == other.icon &&
          alpha == other.alpha &&
          anchor == other.anchor &&
          draggable == other.draggable &&
          flat == other.flat &&
          rotation == other.rotation &&
          visible == other.visible &&
          zIndex == other.zIndex &&
          iconScale == other.iconScale &&
          label == other.label &&
          infoWindow == other.infoWindow &&
          clusterManagerId == other.clusterManagerId;

  @override
  int get hashCode => Object.hash(
    markerId,
    position,
    icon,
    alpha,
    anchor,
    draggable,
    flat,
    rotation,
    visible,
    zIndex,
    iconScale,
    label,
    infoWindow,
    clusterManagerId,
  );

  @override
  String toString() => 'Marker(${markerId.value} @ $position)';
}

/// How a polyline ends.
enum Cap {
  /// A straight cut right at the last point.
  buttCap('butt'),

  /// A semicircle that sticks out.
  roundCap('round'),

  /// A square that sticks out.
  squareCap('square');

  const Cap(this.wireName);

  /// The value of `line-cap` in the MapLibre style.
  final String wireName;
}

/// How two segments of a polyline are joined.
enum JointType {
  /// A pointed corner.
  mitered('miter'),

  /// A rounded corner. It's what to use on a long route: pointed, a sharp
  /// turn draws a spike that sticks out several pixels.
  round('round'),

  /// A cut-off corner.
  bevel('bevel');

  const JointType(this.wireName);

  /// The value of `line-join` in the MapLibre style.
  final String wireName;
}

/// A piece of a dashed line's pattern.
@immutable
class PatternItem {
  const PatternItem._(this.type, this.length);

  /// A dash of [length] pixels.
  factory PatternItem.dash(double length) => PatternItem._('dash', length);

  /// A gap of [length] pixels.
  factory PatternItem.gap(double length) => PatternItem._('gap', length);

  /// A dot.
  static const PatternItem dot = PatternItem._('dot', 1);

  /// `dash`, `gap` or `dot`.
  final String type;

  /// The length in pixels.
  final double length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PatternItem && other.type == type && other.length == length;

  @override
  int get hashCode => Object.hash(type, length);
}

/// A line on the map.
@immutable
class Polyline {
  /// Creates the polyline.
  const Polyline({
    required this.polylineId,
    this.points = const <LatLng>[],
    this.color = const Color(0xFF1E88E5),
    this.width = 4,
    this.startCap = Cap.buttCap,
    this.endCap = Cap.buttCap,
    this.jointType = JointType.round,
    this.patterns = const <PatternItem>[],
    this.visible = true,
    this.zIndex = 0,
    this.blur = 0,
    this.opacity = 1.0,
    this.onTap,
  });

  /// The identifier.
  final PolylineId polylineId;

  /// The points, in order.
  ///
  /// This is where the package's thesis shows: `route.points` from a
  /// `RouteResponse` goes straight in, without converting anything.
  final List<LatLng> points;

  /// The color.
  final Color color;

  /// The width in pixels.
  final double width;

  /// How it starts.
  final Cap startCap;

  /// How it ends.
  final Cap endCap;

  /// How the segments are joined.
  final JointType jointType;

  /// The dash pattern. Empty means a solid line.
  final List<PatternItem> patterns;

  /// Whether it's drawn.
  final bool visible;

  /// The stacking order.
  final double zIndex;

  /// Edge blur in pixels. Useful for a route's halo.
  final double blur;

  /// The opacity, from 0 to 1.
  final double opacity;

  /// What to do when it's tapped.
  final VoidCallback? onTap;

  /// Whether it's dashed.
  bool get isDashed => patterns.isNotEmpty;

  /// A copy with some fields changed.
  Polyline copyWith({
    List<LatLng>? points,
    Color? color,
    double? width,
    Cap? startCap,
    Cap? endCap,
    JointType? jointType,
    List<PatternItem>? patterns,
    bool? visible,
    double? zIndex,
    double? blur,
    double? opacity,
    VoidCallback? onTap,
  }) => Polyline(
    polylineId: polylineId,
    points: points ?? this.points,
    color: color ?? this.color,
    width: width ?? this.width,
    startCap: startCap ?? this.startCap,
    endCap: endCap ?? this.endCap,
    jointType: jointType ?? this.jointType,
    patterns: patterns ?? this.patterns,
    visible: visible ?? this.visible,
    zIndex: zIndex ?? this.zIndex,
    blur: blur ?? this.blur,
    opacity: opacity ?? this.opacity,
    onTap: onTap ?? this.onTap,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Polyline &&
          polylineId == other.polylineId &&
          listEquals(points, other.points) &&
          color == other.color &&
          width == other.width &&
          startCap == other.startCap &&
          endCap == other.endCap &&
          jointType == other.jointType &&
          listEquals(patterns, other.patterns) &&
          visible == other.visible &&
          zIndex == other.zIndex &&
          blur == other.blur &&
          opacity == other.opacity;

  @override
  int get hashCode => Object.hash(
    polylineId,
    Object.hashAll(points),
    color,
    width,
    startCap,
    endCap,
    jointType,
    visible,
    zIndex,
    blur,
    opacity,
  );

  @override
  String toString() => 'Polyline(${polylineId.value}, ${points.length} puntos)';
}

/// A closed area on the map.
@immutable
class Polygon {
  /// Creates the polygon.
  const Polygon({
    required this.polygonId,
    this.points = const <LatLng>[],
    this.holes = const <List<LatLng>>[],
    this.fillColor = const Color(0x551E88E5),
    this.strokeColor = const Color(0xFF1E88E5),
    this.strokeWidth = 2,
    this.visible = true,
    this.zIndex = 0,
    this.onTap,
  });

  /// The polygon of an isoline, ready to paint.
  ///
  /// It takes the outline and the holes of the isoline's first polygon. It's
  /// the shortcut that turns "how far it got in eight minutes" into a patch on
  /// the map in one line of code.
  ///
  /// An isoline can bring **several polygons** —with a river and no bridges
  /// nearby, what's reachable is two separate patches—; to paint them all you
  /// have to iterate `isoline.polygons` and create one for each.
  factory Polygon.fromIsoline(
    Isoline isoline, {
    required PolygonId polygonId,
    Color fillColor = const Color(0x5539FF14),
    Color strokeColor = const Color(0xFF39FF14),
    double strokeWidth = 2,
  }) {
    final first = isoline.polygons.isEmpty
        ? const <List<LatLng>>[]
        : isoline.polygons.first;
    return Polygon(
      polygonId: polygonId,
      points: first.isEmpty ? const <LatLng>[] : first.first,
      holes: first.length > 1 ? first.sublist(1) : const <List<LatLng>>[],
      fillColor: fillColor,
      strokeColor: strokeColor,
      strokeWidth: strokeWidth,
    );
  }

  /// The identifier.
  final PolygonId polygonId;

  /// The outline.
  final List<LatLng> points;

  /// The interior holes.
  final List<List<LatLng>> holes;

  /// The fill color, usually with transparency.
  final Color fillColor;

  /// The stroke color.
  final Color strokeColor;

  /// The stroke width in pixels.
  final double strokeWidth;

  /// Whether it's drawn.
  final bool visible;

  /// The stacking order.
  final double zIndex;

  /// What to do when it's tapped.
  final VoidCallback? onTap;

  /// A copy with some fields changed.
  Polygon copyWith({
    List<LatLng>? points,
    List<List<LatLng>>? holes,
    Color? fillColor,
    Color? strokeColor,
    double? strokeWidth,
    bool? visible,
    double? zIndex,
    VoidCallback? onTap,
  }) => Polygon(
    polygonId: polygonId,
    points: points ?? this.points,
    holes: holes ?? this.holes,
    fillColor: fillColor ?? this.fillColor,
    strokeColor: strokeColor ?? this.strokeColor,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    visible: visible ?? this.visible,
    zIndex: zIndex ?? this.zIndex,
    onTap: onTap ?? this.onTap,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Polygon &&
          polygonId == other.polygonId &&
          listEquals(points, other.points) &&
          fillColor == other.fillColor &&
          strokeColor == other.strokeColor &&
          strokeWidth == other.strokeWidth &&
          visible == other.visible &&
          zIndex == other.zIndex;

  @override
  int get hashCode => Object.hash(
    polygonId,
    Object.hashAll(points),
    fillColor,
    strokeColor,
    strokeWidth,
    visible,
    zIndex,
  );

  @override
  String toString() => 'Polygon(${polygonId.value})';
}

/// A circle with a radius in meters.
///
/// **It's geodesic**, like Google's: the radius is meters on the ground, not
/// pixels. That's why it's drawn by turning it into a many-sided polygon; a
/// pixel circle would change its real size when you zoom the map out.
@immutable
class Circle {
  /// Creates the circle.
  const Circle({
    required this.circleId,
    required this.center,
    required this.radius,
    this.fillColor = const Color(0x5539FF14),
    this.strokeColor = const Color(0xFF39FF14),
    this.strokeWidth = 2,
    this.visible = true,
    this.zIndex = 0,
    this.segments = 72,
    this.onTap,
  });

  /// The identifier.
  final CircleId circleId;

  /// The center.
  final LatLng center;

  /// The radius **in meters**.
  final double radius;

  /// The fill color.
  final Color fillColor;

  /// The stroke color.
  final Color strokeColor;

  /// The stroke width.
  final double strokeWidth;

  /// Whether it's drawn.
  final bool visible;

  /// The stacking order.
  final double zIndex;

  /// How many sides it's broken into.
  ///
  /// Seventy-two looks round at any reasonable zoom. Raising it a lot with a
  /// hundred circles on screen does show.
  final int segments;

  /// What to do when it's tapped.
  final VoidCallback? onTap;

  /// A copy with some fields changed.
  Circle copyWith({
    LatLng? center,
    double? radius,
    Color? fillColor,
    Color? strokeColor,
    double? strokeWidth,
    bool? visible,
    double? zIndex,
    int? segments,
    VoidCallback? onTap,
  }) => Circle(
    circleId: circleId,
    center: center ?? this.center,
    radius: radius ?? this.radius,
    fillColor: fillColor ?? this.fillColor,
    strokeColor: strokeColor ?? this.strokeColor,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    visible: visible ?? this.visible,
    zIndex: zIndex ?? this.zIndex,
    segments: segments ?? this.segments,
    onTap: onTap ?? this.onTap,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Circle &&
          circleId == other.circleId &&
          center == other.center &&
          radius == other.radius &&
          fillColor == other.fillColor &&
          strokeColor == other.strokeColor &&
          strokeWidth == other.strokeWidth &&
          visible == other.visible &&
          zIndex == other.zIndex &&
          segments == other.segments;

  @override
  int get hashCode => Object.hash(
    circleId,
    center,
    radius,
    fillColor,
    strokeColor,
    strokeWidth,
    visible,
    zIndex,
    segments,
  );

  @override
  String toString() => 'Circle(${circleId.value}, ${radius}m)';
}

/// A marker cluster manager's identifier.
@immutable
class ClusterManagerId {
  /// Creates the identifier.
  const ClusterManagerId(this.value);

  /// The value.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClusterManagerId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'ClusterManagerId($value)';
}

/// Groups nearby markers into a single symbol with the count.
///
/// ## Why this is better than in Google
///
/// **MapLibre clusters natively**: the data source carries `cluster: true` and
/// the engine does the work in C++, per tile and on the render thread. In
/// `google_maps_flutter` you have to use a manager class that recomputes in
/// Dart on every camera move, and with a few thousand markers that shows when
/// panning.
///
/// What here is a parameter, there is a separate library.
@immutable
class ClusterManager {
  /// Creates the cluster manager.
  const ClusterManager({
    required this.clusterManagerId,
    this.maxZoom = 14,
    this.radius = 50,
    this.onClusterTap,
    this.textColor = const Color(0xFFFFFFFF),
    this.colorSteps = const <(int, Color)>[
      (0, Color(0xFF51BBD6)),
      (10, Color(0xFFF1F075)),
      (50, Color(0xFFF28CB1)),
    ],
    this.radiusSteps = const <(int, double)>[(0, 18), (10, 22), (50, 28)],
  });

  /// The identifier.
  final ClusterManagerId clusterManagerId;

  /// From this zoom on, markers stop being clustered.
  final int maxZoom;

  /// The clustering radius in pixels.
  final double radius;

  /// What to do when a cluster is tapped.
  ///
  /// If it isn't passed, the map automatically zooms in to the level at which
  /// that cluster splits apart, which is what you almost always want.
  final void Function(Cluster cluster)? onClusterTap;

  /// The color of the number.
  final Color textColor;

  /// The circle's color depending on how many markers it groups.
  ///
  /// Each pair is "from N markers on, this color". The first one has to start
  /// at 0.
  final List<(int, Color)> colorSteps;

  /// The circle's size depending on how many it groups.
  final List<(int, double)> radiusSteps;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClusterManager &&
          clusterManagerId == other.clusterManagerId &&
          maxZoom == other.maxZoom &&
          radius == other.radius;

  @override
  int get hashCode => Object.hash(clusterManagerId, maxZoom, radius);
}

/// A cluster of markers, as it's tapped on the map.
@immutable
class Cluster {
  /// Creates the cluster.
  const Cluster({
    required this.clusterManagerId,
    required this.position,
    required this.pointCount,
    this.clusterId,
  });

  /// Which cluster manager it belongs to.
  final ClusterManagerId clusterManagerId;

  /// Where the cluster's symbol is.
  final LatLng position;

  /// How many markers it groups.
  final int pointCount;

  /// The cluster's internal identifier in MapLibre.
  ///
  /// It's what you need to ask the engine at which zoom this particular cluster
  /// splits apart, which is what `google_maps_flutter` can't give you.
  final int? clusterId;

  @override
  String toString() => 'Cluster($pointCount marcadores @ $position)';
}

/// A heatmap.
///
/// ## Why this is also better than in Google
///
/// In `google_maps_flutter` the heatmap is a closed type with very few knobs.
/// Here it's a **native MapLibre `heatmap` layer**, and the color ramp, the
/// radius and the intensity can be made to depend on the zoom.
@immutable
class Heatmap {
  /// Creates the heatmap.
  const Heatmap({
    required this.heatmapId,
    required this.data,
    this.radius = 30,
    this.opacity = 0.7,
    this.intensity = 1.0,
    this.minZoom = 0,
    this.maxZoom = 22,
    this.gradient = const <(double, Color)>[
      (0.0, Color(0x00000000)),
      (0.2, Color(0xFF2196F3)),
      (0.4, Color(0xFF00E5FF)),
      (0.6, Color(0xFF76FF03)),
      (0.8, Color(0xFFFFEA00)),
      (1.0, Color(0xFFFF3D00)),
    ],
    this.visible = true,
  });

  /// The identifier.
  final HeatmapId heatmapId;

  /// The points and their weight. A `null` weight counts as 1.
  final List<({LatLng point, double? weight})> data;

  /// Each point's radius of influence, in pixels.
  final double radius;

  /// The opacity of the whole layer.
  final double opacity;

  /// The intensity multiplier.
  final double intensity;

  /// The zoom from which it's visible.
  final double minZoom;

  /// The zoom up to which it's visible.
  final double maxZoom;

  /// The color ramp: pairs of (density from 0 to 1, color).
  ///
  /// The first color is usually transparent so that areas without data don't
  /// get tinted.
  final List<(double, Color)> gradient;

  /// Whether it's drawn.
  final bool visible;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Heatmap &&
          heatmapId == other.heatmapId &&
          radius == other.radius &&
          opacity == other.opacity &&
          intensity == other.intensity &&
          visible == other.visible &&
          data.length == other.data.length;

  @override
  int get hashCode =>
      Object.hash(heatmapId, radius, opacity, intensity, visible, data.length);

  @override
  String toString() => 'Heatmap(${heatmapId.value}, ${data.length} puntos)';
}

/// A ground overlay's identifier.
@immutable
class GroundOverlayId {
  /// Creates the identifier.
  const GroundOverlayId(this.value);

  /// The value.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroundOverlayId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'GroundOverlayId($value)';
}

/// An image pinned to a rectangle of the map.
///
/// A building plan, a scanned map, a coverage area.
@immutable
class GroundOverlay {
  /// Creates the overlay.
  const GroundOverlay({
    required this.groundOverlayId,
    required this.bounds,
    required this.imageUrl,
    this.opacity = 1.0,
    this.visible = true,
    this.zIndex = 0,
  });

  /// The identifier.
  final GroundOverlayId groundOverlayId;

  /// The rectangle it covers.
  final LatLngBounds bounds;

  /// The image URL. A base64 `data:` URL works too.
  final String imageUrl;

  /// The opacity.
  final double opacity;

  /// Whether it's drawn.
  final bool visible;

  /// The stacking order.
  final double zIndex;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroundOverlay &&
          groundOverlayId == other.groundOverlayId &&
          bounds == other.bounds &&
          imageUrl == other.imageUrl &&
          opacity == other.opacity &&
          visible == other.visible;

  @override
  int get hashCode =>
      Object.hash(groundOverlayId, bounds, imageUrl, opacity, visible);
}

/// A tile layer's identifier.
@immutable
class TileOverlayId {
  /// Creates the identifier.
  const TileOverlayId(this.value);

  /// The value.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TileOverlayId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'TileOverlayId($value)';
}

/// A layer of your own tiles on top of the map.
///
/// For painting data that's already served as tiles: land registry, network
/// coverage, weather.
@immutable
class TileOverlay {
  /// Creates the layer.
  const TileOverlay({
    required this.tileOverlayId,
    required this.urlTemplate,
    this.tileSize = 256,
    this.opacity = 1.0,
    this.minZoom = 0,
    this.maxZoom = 22,
    this.visible = true,
    this.zIndex = 0,
    this.attribution,
  });

  /// The identifier.
  final TileOverlayId tileOverlayId;

  /// The URL template, with `{z}`, `{x}` and `{y}`.
  final String urlTemplate;

  /// The tile size in pixels.
  final int tileSize;

  /// The opacity.
  final double opacity;

  /// The zoom from which it's requested.
  final double minZoom;

  /// The zoom up to which it's requested.
  final double maxZoom;

  /// Whether it's drawn.
  final bool visible;

  /// The stacking order.
  final double zIndex;

  /// The attribution that has to be shown.
  ///
  /// Almost every tile provider requires it in their terms, and it's the first
  /// thing that gets forgotten.
  final String? attribution;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TileOverlay &&
          tileOverlayId == other.tileOverlayId &&
          urlTemplate == other.urlTemplate &&
          opacity == other.opacity &&
          visible == other.visible;

  @override
  int get hashCode => Object.hash(tileOverlayId, urlTemplate, opacity, visible);
}
