// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:math' as math;

import 'package:compass_maps/compass_maps.dart';
import 'package:compass_maps_flutter/src/types/overlays.dart';
import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

/// Convierte las superposiciones a GeoJSON y a expresiones de estilo.
///
/// ## Por qué GeoJSON y no anotaciones
///
/// `maplibre_gl` ofrece dos caminos: gestores de anotaciones (`addSymbol`,
/// `addLine`…) o fuentes GeoJSON con capas propias. Este paquete usa el
/// segundo, y la diferencia se nota con volumen:
///
/// - Las anotaciones cruzan el canal de plataforma **una por objeto**. Mover
///   200 vehículos son 200 llamadas por actualización.
/// - Una fuente GeoJSON se empuja **entera de una vez**: una sola llamada con
///   los 200 dentro. Y es el único camino que permite agrupar de forma nativa
///   (`cluster: true`) y usar la capa de mapa de calor.
///
/// El coste es que el estilo hay que escribirlo a mano, que es lo que hace
/// este archivo.
@internal
abstract final class GeoJson {
  /// Una colección vacía, para inicializar las fuentes.
  static Map<String, dynamic> get empty => <String, dynamic>{
    'type': 'FeatureCollection',
    'features': <dynamic>[],
  };

  /// Los marcadores visibles como colección de puntos.
  ///
  /// El identificador va **también** en `id` además de en las propiedades:
  /// `queryRenderedFeatures` devuelve el `id` de la entidad, y sin él habría
  /// que buscar el marcador comparando coordenadas en coma flotante.
  static Map<String, dynamic> markers(Iterable<Marker> markers) =>
      <String, dynamic>{
        'type': 'FeatureCollection',
        'features': <dynamic>[
          for (final m in markers)
            if (m.visible)
              <String, dynamic>{
                'type': 'Feature',
                'id': m.markerId.value.hashCode & 0x7FFFFFFF,
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
                  'flat': m.flat,
                  if (m.icon.hue != null) 'hue': m.icon.hue,
                },
              },
        ],
      };

  /// Las polilíneas como colección de líneas.
  ///
  /// Se separan las continuas de las discontinuas porque `line-dasharray`
  /// **no admite expresiones basadas en datos** en la especificación de
  /// MapLibre: el patrón es literal por capa. Meter las dos clases en la misma
  /// capa haría que todas salieran discontinuas o ninguna.
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

  /// Polígonos y círculos en una sola colección.
  ///
  /// Los círculos se convierten aquí en polígonos de muchos lados: el radio de
  /// un [Circle] son **metros sobre el terreno**, y la capa `circle` de
  /// MapLibre dibuja radios en píxeles. Un círculo de píxeles cambiaría de
  /// tamaño real al alejar el mapa, que es justo lo contrario de lo que
  /// significa «300 metros a la redonda».
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

  /// Los puntos de un mapa de calor, con su peso.
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

  /// Un anillo cerrado: GeoJSON exige que el último punto repita al primero.
  ///
  /// Sin cerrarlo, MapLibre dibuja el polígono igual pero el borde se queda
  /// abierto por un lado — un fallo que solo se ve mirando de cerca.
  static List<dynamic> _ring(List<LatLng> points) {
    final ring = <dynamic>[for (final p in points) p.toLonLat()];
    if (ring.length >= 2 && ring.first.toString() != ring.last.toString()) {
      ring.add(points.first.toLonLat());
    }
    return ring;
  }

  /// Un color como `rgba()`, que es lo que entiende el estilo de MapLibre.
  ///
  /// Se escribe a mano en vez de con `toARGB32()` porque hace falta el canal
  /// alfa **separado**: un color hexadecimal de ocho dígitos no lo interpretan
  /// igual todas las propiedades de estilo, y la transparencia de un relleno
  /// es justo lo que más se usa aquí.
  static String rgba(Color color) {
    final r = (color.r * 255).round().clamp(0, 255);
    final g = (color.g * 255).round().clamp(0, 255);
    final b = (color.b * 255).round().clamp(0, 255);
    return 'rgba($r,$g,$b,${color.a.toStringAsFixed(3)})';
  }

  /// Los puntos de un círculo geodésico de [radiusMeters] alrededor de
  /// [center].
  ///
  /// Recorre el arco sobre la esfera, no sobre la proyección: cerca del polo,
  /// un círculo dibujado como una elipse en píxeles se ve mal y mide mal.
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

  /// La expresión de interpolación de color de un mapa de calor.
  static List<Object> heatmapColorExpression(List<(double, Color)> gradient) =>
      <Object>[
        'interpolate',
        <Object>['linear'],
        <Object>['heatmap-density'],
        for (final (stop, color) in gradient) ...<Object>[stop, rgba(color)],
      ];

  /// La expresión de color de un grupo según cuántos marcadores agrupe.
  ///
  /// `step` y no `interpolate`: los saltos de color de un grupo tienen que ser
  /// discretos para que se distingan de un vistazo.
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

  /// La expresión de radio de un grupo según cuántos agrupe.
  static List<Object> clusterRadiusExpression(List<(int, double)> steps) {
    if (steps.isEmpty) return <Object>['literal', 18.0];
    return <Object>[
      'step',
      <Object>['get', 'point_count'],
      steps.first.$2,
      for (final (count, radius) in steps.skip(1)) ...<Object>[count, radius],
    ];
  }

  /// El patrón de discontinuidad como `line-dasharray`.
  ///
  /// MapLibre lo mide en **múltiplos del grosor de la línea**, no en píxeles,
  /// así que hay que dividir. Pasarlo en píxeles da un patrón cuyo tamaño
  /// depende del grosor sin que se entienda por qué.
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
