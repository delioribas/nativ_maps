// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativ_maps_flutter/nativ_maps_flutter.dart';
import 'package:nativ_maps_flutter/src/internal/geojson.dart';

void main() {
  group('marcadores a GeoJSON', () {
    test('el orden de las coordenadas se invierte a [lon, lat]', () {
      // La comprobación que caza el error más caro del dominio: GeoJSON usa
      // [lon, lat] y aquí dentro se trabaja con [lat, lng]. Invertirlo no da
      // error, da un punto en otro continente.
      final json = GeoJson.markers(<Marker>[
        Marker(
          markerId: const MarkerId('m1'),
          position: LatLng(-0.1807, -78.4678),
        ),
      ]);

      final features = json['features']! as List<dynamic>;
      final geometry =
          (features.first as Map<String, dynamic>)['geometry']!
              as Map<String, dynamic>;
      expect(geometry['coordinates'], <double>[-78.4678, -0.1807]);
    });

    test('los marcadores invisibles no se envían', () {
      final json = GeoJson.markers(<Marker>[
        Marker(markerId: const MarkerId('a'), position: LatLng(0, 0)),
        Marker(
          markerId: const MarkerId('b'),
          position: LatLng(1, 1),
          visible: false,
        ),
      ]);
      expect((json['features']! as List<dynamic>).length, 1);
    });

    test('el identificador viaja en las propiedades, para el hit-test', () {
      final json = GeoJson.markers(<Marker>[
        Marker(markerId: const MarkerId('vehiculo-7'), position: LatLng(0, 0)),
      ]);
      final feature =
          (json['features']! as List<dynamic>).first as Map<String, dynamic>;
      final properties = feature['properties']! as Map<String, dynamic>;
      // Sin esto habría que buscar el marcador comparando coordenadas en coma
      // flotante, que falla en cuanto hay dos cerca.
      expect(properties['id'], 'vehiculo-7');
      expect(properties['rotation'], 0.0);
      expect(properties['flat'], false);
    });

    test('el rumbo y el modo plano viajan, para orientar un vehículo', () {
      final json = GeoJson.markers(<Marker>[
        Marker(
          markerId: const MarkerId('v'),
          position: LatLng(0, 0),
          rotation: 137.5,
          flat: true,
        ),
      ]);
      final properties =
          ((json['features']! as List<dynamic>).first
                  as Map<String, dynamic>)['properties']!
              as Map<String, dynamic>;
      expect(properties['rotation'], 137.5);
      expect(properties['flat'], true);
    });
  });

  group('polilíneas a GeoJSON', () {
    test('una línea de menos de dos puntos no se envía', () {
      // Un LineString de un punto es GeoJSON inválido y el motor lo rechaza
      // entero, tirando también las líneas buenas de la misma colección.
      final json = GeoJson.polylines(<Polyline>[
        Polyline(
          polylineId: const PolylineId('corta'),
          points: <LatLng>[LatLng(0, 0)],
        ),
        Polyline(
          polylineId: const PolylineId('buena'),
          points: <LatLng>[LatLng(0, 0), LatLng(1, 1)],
        ),
      ]);
      expect((json['features']! as List<dynamic>).length, 1);
    });

    test('el color va como rgba() con el alfa separado', () {
      final json = GeoJson.polylines(<Polyline>[
        Polyline(
          polylineId: const PolylineId('p'),
          points: <LatLng>[LatLng(0, 0), LatLng(1, 1)],
          color: const Color(0x8033AAFF),
        ),
      ]);
      final properties =
          ((json['features']! as List<dynamic>).first
                  as Map<String, dynamic>)['properties']!
              as Map<String, dynamic>;
      // Un hexadecimal de ocho dígitos no lo interpretan igual todas las
      // propiedades de estilo; el alfa separado sí.
      expect(properties['color'], 'rgba(51,170,255,0.502)');
    });
  });

  group('áreas a GeoJSON', () {
    test('el anillo del polígono se cierra', () {
      // GeoJSON exige que el último punto repita al primero. Sin cerrarlo el
      // polígono se dibuja igual pero con el borde abierto por un lado.
      final json = GeoJson.areas(<Polygon>[
        Polygon(
          polygonId: const PolygonId('p'),
          points: <LatLng>[LatLng(0, 0), LatLng(0, 1), LatLng(1, 1)],
        ),
      ], const <Circle>[]);
      final coordinates =
          (((json['features']! as List<dynamic>).first
                      as Map<String, dynamic>)['geometry']!
                  as Map<String, dynamic>)['coordinates']!
              as List<dynamic>;
      final ring = coordinates.first as List<dynamic>;
      expect(ring.length, 4);
      expect(ring.first.toString(), ring.last.toString());
    });

    test('los agujeros van como anillos adicionales', () {
      final json = GeoJson.areas(<Polygon>[
        Polygon(
          polygonId: const PolygonId('p'),
          points: <LatLng>[LatLng(0, 0), LatLng(0, 2), LatLng(2, 2)],
          holes: <List<LatLng>>[
            <LatLng>[LatLng(0.5, 0.5), LatLng(0.5, 1), LatLng(1, 1)],
          ],
        ),
      ], const <Circle>[]);
      final coordinates =
          (((json['features']! as List<dynamic>).first
                      as Map<String, dynamic>)['geometry']!
                  as Map<String, dynamic>)['coordinates']!
              as List<dynamic>;
      expect(coordinates.length, 2);
    });

    test('el círculo se convierte en un polígono geodésico', () {
      // El radio son METROS sobre el terreno, no píxeles. La capa `circle` de
      // MapLibre dibuja píxeles, y un círculo de píxeles cambiaría de tamaño
      // real al alejar el mapa.
      final json = GeoJson.areas(const <Polygon>[], <Circle>[
        Circle(
          circleId: const CircleId('c'),
          center: LatLng(-0.1807, -78.4678),
          radius: 500,
          segments: 36,
        ),
      ]);
      final feature =
          (json['features']! as List<dynamic>).first as Map<String, dynamic>;
      expect((feature['geometry']! as Map<String, dynamic>)['type'], 'Polygon');

      final ring =
          ((feature['geometry']! as Map<String, dynamic>)['coordinates']!
                      as List<dynamic>)
                  .first
              as List<dynamic>;
      expect(ring.length, 37); // 36 segmentos + el cierre
    });
  });

  group('geodesicCircle', () {
    test('todos los puntos quedan a la distancia pedida', () {
      final centro = LatLng(-0.1807, -78.4678);
      final puntos = GeoJson.geodesicCircle(centro, 1000, segments: 24);
      for (final punto in puntos) {
        // Un metro de tolerancia sobre mil: es geodésico, no una elipse en
        // píxeles.
        expect(centro.distanceTo(punto), closeTo(1000, 1));
      }
    });

    test('funciona cerca del polo sin salirse del mundo', () {
      final polar = LatLng(89.9, 0);
      final puntos = GeoJson.geodesicCircle(polar, 50000, segments: 36);
      for (final punto in puntos) {
        expect(punto.latitude, inInclusiveRange(-90, 90));
        expect(punto.longitude, inInclusiveRange(-180, 180));
      }
    });
  });

  group('dashArray', () {
    test('el patrón se expresa en múltiplos del grosor, no en píxeles', () {
      // MapLibre mide `line-dasharray` en múltiplos del grosor. Pasarlo en
      // píxeles da un patrón cuyo tamaño depende del grosor sin que se
      // entienda por qué.
      final dash = GeoJson.dashArray(<PatternItem>[
        PatternItem.dash(12),
        PatternItem.gap(6),
      ], 4);
      expect(dash, <double>[3, 1.5]);
    });

    test('sin patrón devuelve vacío', () {
      expect(GeoJson.dashArray(const <PatternItem>[], 4), isEmpty);
    });

    test('un grosor de cero no divide entre cero', () {
      final dash = GeoJson.dashArray(<PatternItem>[PatternItem.dash(10)], 0);
      expect(dash.first.isFinite, isTrue);
    });
  });

  group('expresiones de estilo', () {
    test('el color de un grupo usa `step`, no `interpolate`', () {
      // Los saltos de color de un grupo tienen que ser discretos para que se
      // distingan de un vistazo.
      final expression = GeoJson.clusterColorExpression(const <(int, Color)>[
        (0, Color(0xFF51BBD6)),
        (10, Color(0xFFF1F075)),
      ]);
      expect(expression.first, 'step');
      expect(expression[1], <Object>['get', 'point_count']);
    });

    test('la rampa de un mapa de calor usa `interpolate`', () {
      final expression = GeoJson.heatmapColorExpression(const <(double, Color)>[
        (0.0, Color(0x00000000)),
        (1.0, Color(0xFFFF3D00)),
      ]);
      expect(expression.first, 'interpolate');
      expect(expression[2], <Object>['heatmap-density']);
    });
  });
}
