// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';
import 'package:nativ_maps/nativ_maps.dart';
import 'package:nativ_maps_flutter/src/types/overlays.dart';

/// Converts the overlays to GeoJSON and to style expressions.
///
/// ## Why GeoJSON and not annotations
///
/// `maplibre_gl` offers two paths: annotation managers (`addSymbol`,
/// `addLine`…) or GeoJSON sources with their own layers. This package uses the
/// second, and the difference shows at volume:
///
/// - Annotations cross the platform channel **one per object**. Moving 200
///   vehicles means 200 calls per update.
/// - A GeoJSON source is pushed **whole, in one go**: a single call with all
///   200 inside. And it's the only path that allows native clustering
///   (`cluster: true`) and the heatmap layer.
///
/// The cost is that the style has to be written by hand, which is what this
/// file does.
@internal
abstract final class GeoJson {
  /// An empty collection, for initializing the sources.
  static Map<String, dynamic> get empty => <String, dynamic>{
    'type': 'FeatureCollection',
    'features': <dynamic>[],
  };

  /// The visible markers as a collection of points.
  ///
  /// The identifier goes in `id` **as well as** in the properties:
  /// `queryRenderedFeatures` returns the feature's `id`, and without it you'd
  /// have to find the marker by comparing floating-point coordinates.
  static Map<String, dynamic> markers(Iterable<Marker> markers) =>
      <String, dynamic>{
        'type': 'FeatureCollection',
        'features': <dynamic>[
          for (final m in markers)
            if (m.visible) marker(m),
        ],
      };

  /// The feature of a single marker.
  ///
  /// It's what [markers] puts in the collection, and what a drag pushes on
  /// its own with `setGeoJsonFeature` so that moving one marker doesn't send
  /// all of them.
  static Map<String, dynamic> marker(Marker m) => <String, dynamic>{
    'type': 'Feature',
    'id': featureId(m.markerId),
    'geometry': <String, dynamic>{
      'type': 'Point',
      'coordinates': m.position.toLonLat(),
    },
    'properties': <String, dynamic>{
      'id': m.markerId.value,
      'icon': m.icon.name,
      'iconScale': m.iconScale,
      'rotation': m.rotation,
      'alpha': m.alpha,
      'zIndex': m.zIndex,
      'label': m.label ?? '',
      'anchorX': m.anchor.dx,
      'anchorY': m.anchor.dy,
      'anchor': iconAnchor(m.anchor),
      'labelOffset': labelOffset(m.anchor),
      'flat': m.flat,
      // The native side reads exactly this property, with this name, to
      // decide whether a press starts a drag or pans the map.
      'draggable': m.draggable,
      if (m.icon.hue != null) 'hue': m.icon.hue,
    },
  };

  /// The numeric feature id of a marker.
  ///
  /// MapLibre wants a number; a drag event gives it back, sometimes as a
  /// string, and this is how it's matched to the marker again.
  static int featureId(MarkerId id) => id.value.hashCode & 0x7FFFFFFF;

  /// The MapLibre `icon-anchor` closest to [anchor].
  ///
  /// Google anchors with a free `Offset`; MapLibre, with nine named positions.
  /// It's rounded to the closest one: `(0.5, 1)` is `bottom` —the tip of a
  /// pin— and `(0.5, 0.5)` is `center` —a vehicle seen from above—, which are
  /// the two actually used.
  static String iconAnchor(Offset anchor) {
    String pick(double v, String low, String high) =>
        v < 0.25 ? low : (v > 0.75 ? high : '');
    final x = pick(anchor.dx, 'left', 'right');
    final y = pick(anchor.dy, 'top', 'bottom');
    if (x.isEmpty && y.isEmpty) return 'center';
    if (x.isEmpty) return y;
    if (y.isEmpty) return x;
    return '$y-$x';
  }

  /// How far down the text goes, in `em`, to sit under the icon.
  ///
  /// The text is placed relative to the point, not the icon: with the icon
  /// anchored at its center, a pin's offset would leave it on top of the
  /// bottom half. It's computed for an icon about 40 points tall, which is the
  /// default pin's height.
  static List<double> labelOffset(Offset anchor) => <double>[
    0,
    (1 - anchor.dy.clamp(0.0, 1.0)) * 3.4 + 0.8,
  ];

  /// The polylines as a collection of lines.
  ///
  /// Solid ones are kept apart from dashed ones because `line-dasharray`
  /// **does not accept data-driven expressions** in the MapLibre
  /// specification: the pattern is a literal per layer. Putting both kinds in
  /// the same layer would make all of them come out dashed, or none.
  static Map<String, dynamic> polylines(Iterable<Polyline> lines) =>
      <String, dynamic>{
        'type': 'FeatureCollection',
        'features': <dynamic>[
          for (final p in lines)
            if (p.visible && p.points.length >= 2)
              <String, dynamic>{
                'type': 'Feature',
                'id': p.polylineId.value.hashCode & 0x7FFFFFFF,
                'geometry': <String, dynamic>{
                  'type': 'LineString',
                  'coordinates': <dynamic>[
                    for (final pt in p.points) pt.toLonLat(),
                  ],
                },
                'properties': <String, dynamic>{
                  'id': p.polylineId.value,
                  'color': rgba(p.color),
                  'width': p.width,
                  'blur': p.blur,
                  'opacity': p.opacity,
                  'zIndex': p.zIndex,
                },
              },
        ],
      };

  /// Polygons and circles in a single collection.
  ///
  /// Circles are turned into many-sided polygons here: the radius of a
  /// [Circle] is **meters on the ground**, and MapLibre's `circle` layer draws
  /// radii in pixels. A pixel circle would change its real size when you zoom
  /// the map out, which is exactly the opposite of what "within 300 meters"
  /// means.
  static Map<String, dynamic> areas(
    Iterable<Polygon> polygons,
    Iterable<Circle> circles,
  ) => <String, dynamic>{
    'type': 'FeatureCollection',
    'features': <dynamic>[
      for (final poly in polygons)
        if (poly.visible && poly.points.length >= 3)
          <String, dynamic>{
            'type': 'Feature',
            'id': poly.polygonId.value.hashCode & 0x7FFFFFFF,
            'geometry': <String, dynamic>{
              'type': 'Polygon',
              'coordinates': <dynamic>[
                _ring(poly.points),
                for (final hole in poly.holes) _ring(hole),
              ],
            },
            'properties': <String, dynamic>{
              'id': poly.polygonId.value,
              'fill': rgba(poly.fillColor),
              'stroke': rgba(poly.strokeColor),
              'strokeWidth': poly.strokeWidth,
              'zIndex': poly.zIndex,
            },
          },
      for (final c in circles)
        if (c.visible)
          <String, dynamic>{
            'type': 'Feature',
            'id': c.circleId.value.hashCode & 0x7FFFFFFF,
            'geometry': <String, dynamic>{
              'type': 'Polygon',
              'coordinates': <dynamic>[
                _ring(geodesicCircle(c.center, c.radius, segments: c.segments)),
              ],
            },
            'properties': <String, dynamic>{
              'id': c.circleId.value,
              'fill': rgba(c.fillColor),
              'stroke': rgba(c.strokeColor),
              'strokeWidth': c.strokeWidth,
              'zIndex': c.zIndex,
            },
          },
    ],
  };

  /// The points of a heatmap, with their weight.
  static Map<String, dynamic> heatmap(Heatmap heatmap) => <String, dynamic>{
    'type': 'FeatureCollection',
    'features': <dynamic>[
      for (final entry in heatmap.data)
        <String, dynamic>{
          'type': 'Feature',
          'geometry': <String, dynamic>{
            'type': 'Point',
            'coordinates': entry.point.toLonLat(),
          },
          'properties': <String, dynamic>{'weight': entry.weight ?? 1.0},
        },
    ],
  };

  /// A closed ring: GeoJSON requires the last point to repeat the first.
  ///
  /// Without closing it, MapLibre draws the polygon anyway but the outline is
  /// left open on one side — a bug you only see by looking closely.
  static List<dynamic> _ring(List<LatLng> points) {
    final ring = <dynamic>[for (final p in points) p.toLonLat()];
    if (ring.length >= 2 && ring.first.toString() != ring.last.toString()) {
      ring.add(points.first.toLonLat());
    }
    return ring;
  }

  /// A color as `rgba()`, which is what the MapLibre style understands.
  ///
  /// It's written by hand instead of with `toARGB32()` because the alpha
  /// channel is needed **separately**: not every style property interprets an
  /// eight-digit hex color the same way, and a fill's transparency is exactly
  /// what's used most here.
  static String rgba(Color color) {
    final r = (color.r * 255).round().clamp(0, 255);
    final g = (color.g * 255).round().clamp(0, 255);
    final b = (color.b * 255).round().clamp(0, 255);
    return 'rgba($r,$g,$b,${color.a.toStringAsFixed(3)})';
  }

  /// The points of a geodesic circle of [radiusMeters] around [center].
  ///
  /// It walks the arc on the sphere, not on the projection: near the pole, a
  /// circle drawn as an ellipse in pixels looks wrong and measures wrong.
  static List<LatLng> geodesicCircle(
    LatLng center,
    double radiusMeters, {
    int segments = 72,
  }) {
    final lat = center.latitude * math.pi / 180.0;
    final lon = center.longitude * math.pi / 180.0;
    final angular = radiusMeters / earthRadiusMeters;
    final points = <LatLng>[];

    for (var i = 0; i <= segments; i++) {
      final bearing = 2 * math.pi * i / segments;
      final sinLat =
          math.sin(lat) * math.cos(angular) +
          math.cos(lat) * math.sin(angular) * math.cos(bearing);
      final newLat = math.asin(sinLat);
      final y = math.sin(bearing) * math.sin(angular) * math.cos(lat);
      final x = math.cos(angular) - math.sin(lat) * sinLat;
      final newLon = lon + math.atan2(y, x);
      points.add(
        LatLng(
          (newLat * 180.0 / math.pi).clamp(-90.0, 90.0),
          (newLon * 180.0 / math.pi + 540.0) % 360.0 - 180.0,
        ),
      );
    }
    return points;
  }

  /// The color interpolation expression of a heatmap.
  static List<Object> heatmapColorExpression(List<(double, Color)> gradient) =>
      <Object>[
        'interpolate',
        <Object>['linear'],
        <Object>['heatmap-density'],
        for (final (stop, color) in gradient) ...<Object>[stop, rgba(color)],
      ];

  /// A cluster's color expression, depending on how many markers it groups.
  ///
  /// `step` and not `interpolate`: a cluster's color jumps have to be discrete
  /// so they can be told apart at a glance.
  static List<Object> clusterColorExpression(List<(int, Color)> steps) {
    if (steps.isEmpty) {
      return <Object>['literal', rgba(const Color(0xFF51BBD6))];
    }
    return <Object>[
      'step',
      <Object>['get', 'point_count'],
      rgba(steps.first.$2),
      for (final (count, color) in steps.skip(1)) ...<Object>[
        count,
        rgba(color),
      ],
    ];
  }

  /// A cluster's radius expression, depending on how many it groups.
  static List<Object> clusterRadiusExpression(List<(int, double)> steps) {
    if (steps.isEmpty) return <Object>['literal', 18.0];
    return <Object>[
      'step',
      <Object>['get', 'point_count'],
      steps.first.$2,
      for (final (count, radius) in steps.skip(1)) ...<Object>[count, radius],
    ];
  }

  /// The dash pattern as `line-dasharray`.
  ///
  /// MapLibre measures it in **multiples of the line width**, not in pixels,
  /// so you have to divide. Passing it in pixels gives a pattern whose size
  /// depends on the width for no apparent reason.
  static List<double> dashArray(List<PatternItem> patterns, double width) {
    if (patterns.isEmpty) return const <double>[];
    final w = width <= 0 ? 1.0 : width;
    return <double>[
      for (final item in patterns)
        switch (item.type) {
          'dot' => 0.1,
          _ => item.length / w,
        },
    ];
  }
}
