// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:compass_maps_flutter/compass_maps_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CameraUpdate', () {
    final camara = CameraPosition(
      target: LatLng(-0.1807, -78.4678),
      zoom: 13,
      bearing: 45,
      tilt: 30,
    );

    test('newLatLng conserva zoom, rumbo e inclinación', () {
      final resultado = CameraUpdate.newLatLng(LatLng(1, 2)).resolve(camara)!;
      expect(resultado.target, LatLng(1, 2));
      expect(resultado.zoom, 13);
      expect(resultado.bearing, 45);
      expect(resultado.tilt, 30);
    });

    test('newLatLngZoom cambia los dos', () {
      final resultado = CameraUpdate.newLatLngZoom(
        LatLng(1, 2),
        17,
      ).resolve(camara)!;
      expect(resultado.target, LatLng(1, 2));
      expect(resultado.zoom, 17);
    });

    test('zoomIn y zoomOut se mueven un nivel', () {
      expect(CameraUpdate.zoomIn().resolve(camara)!.zoom, 14);
      expect(CameraUpdate.zoomOut().resolve(camara)!.zoom, 12);
    });

    test('zoomBy es relativo y zoomTo absoluto', () {
      expect(CameraUpdate.zoomBy(2.5).resolve(camara)!.zoom, 15.5);
      expect(CameraUpdate.zoomTo(2.5).resolve(camara)!.zoom, 2.5);
    });

    test('bearingTo y tiltTo solo tocan lo suyo', () {
      final girado = CameraUpdate.bearingTo(180).resolve(camara)!;
      expect(girado.bearing, 180);
      expect(girado.target, camara.target);
      expect(girado.zoom, camara.zoom);

      final inclinado = CameraUpdate.tiltTo(0).resolve(camara)!;
      expect(inclinado.tilt, 0);
      expect(inclinado.bearing, 45);
    });

    test('los que necesitan el tamaño del lienzo devuelven null', () {
      // Encuadrar un rectángulo y desplazar por píxeles dependen del tamaño de
      // la pantalla, así que los resuelve el motor y no este cálculo.
      final bounds = LatLngBounds(
        southwest: LatLng(-1, -1),
        northeast: LatLng(1, 1),
      );
      expect(CameraUpdate.newLatLngBounds(bounds).resolve(camara), isNull);
      expect(CameraUpdate.newLatLngBounds(bounds).isBoundsFit, isTrue);
      expect(CameraUpdate.scrollBy(10, 20).resolve(camara), isNull);
      expect(CameraUpdate.scrollBy(10, 20).isScrollBy, isTrue);
    });

    test('las nueve fábricas de google_maps_flutter existen', () {
      // La comprobación de la promesa del §4: quien viene de Google encuentra
      // los mismos nombres con las mismas firmas.
      expect(CameraUpdate.newCameraPosition(camara), isA<CameraUpdate>());
      expect(CameraUpdate.newLatLng(LatLng(0, 0)), isA<CameraUpdate>());
      expect(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(southwest: LatLng(0, 0), northeast: LatLng(1, 1)),
          40,
        ),
        isA<CameraUpdate>(),
      );
      expect(CameraUpdate.newLatLngZoom(LatLng(0, 0), 10), isA<CameraUpdate>());
      expect(CameraUpdate.scrollBy(1, 1), isA<CameraUpdate>());
      expect(CameraUpdate.zoomBy(1), isA<CameraUpdate>());
      expect(CameraUpdate.zoomIn(), isA<CameraUpdate>());
      expect(CameraUpdate.zoomOut(), isA<CameraUpdate>());
      expect(CameraUpdate.zoomTo(10), isA<CameraUpdate>());
    });
  });

  group('los identificadores no se pueden intercambiar', () {
    test('un MarkerId no es un PolylineId', () {
      // Si los dos fueran String, pasar uno donde va el otro compilaría.
      const marcador = MarkerId('x');
      const linea = PolylineId('x');
      expect(marcador.value, linea.value);
      // ignore: unrelated_type_equality_checks
      expect(marcador == linea, isFalse);
    });

    test('la igualdad es por valor', () {
      expect(const MarkerId('a'), const MarkerId('a'));
      expect(const MarkerId('a').hashCode, const MarkerId('a').hashCode);
      expect(const MarkerId('a'), isNot(const MarkerId('b')));
    });
  });

  group('Marker', () {
    test('copyWith conserva el identificador', () {
      // Es la operación que se usa para mover un vehículo: si cambiara el
      // identificador, cada actualización crearía un marcador nuevo y dejaría
      // el anterior clavado en el mapa.
      final original = Marker(
        markerId: const MarkerId('v-1'),
        position: LatLng(0, 0),
      );
      final movido = original.copyWith(position: LatLng(1, 1), rotation: 90);
      expect(movido.markerId, const MarkerId('v-1'));
      expect(movido.position, LatLng(1, 1));
      expect(movido.rotation, 90);
    });

    test('la igualdad detecta un cambio de posición', () {
      // De esto depende que `setMarkers` no vuelva a empujar todo sin cambios.
      final a = Marker(markerId: const MarkerId('m'), position: LatLng(0, 0));
      final b = Marker(markerId: const MarkerId('m'), position: LatLng(0, 1));
      expect(a, isNot(b));
      expect(a, Marker(markerId: const MarkerId('m'), position: LatLng(0, 0)));
    });
  });

  group('Polygon.fromIsoline', () {
    test('convierte una isócrona en un polígono pintable', () {
      // El atajo que convierte «hasta dónde llegó en ocho minutos» en una
      // mancha en el mapa en una línea de código.
      final isocrona = Isoline(
        polygons: <List<List<LatLng>>>[
          <List<LatLng>>[
            <LatLng>[LatLng(0, 0), LatLng(0, 1), LatLng(1, 1), LatLng(0, 0)],
            <LatLng>[LatLng(0.2, 0.2), LatLng(0.2, 0.4), LatLng(0.4, 0.4)],
          ],
        ],
        timeThreshold: const Duration(minutes: 8),
      );

      final poligono = Polygon.fromIsoline(
        isocrona,
        polygonId: const PolygonId('zona'),
      );
      expect(poligono.points.length, 4);
      expect(poligono.holes.length, 1);
    });

    test('una isócrona vacía da un polígono vacío, no revienta', () {
      final poligono = Polygon.fromIsoline(
        const Isoline(polygons: <List<List<LatLng>>>[]),
        polygonId: const PolygonId('z'),
      );
      expect(poligono.points, isEmpty);
    });
  });

  group('Heatmap', () {
    test('la rampa por defecto empieza en transparente', () {
      // Si no, las zonas sin datos se tiñen del primer color y el mapa entero
      // parece tener actividad.
      const mapa = Heatmap(
        heatmapId: HeatmapId('h'),
        data: <({LatLng point, double? weight})>[],
      );
      expect(mapa.gradient.first.$1, 0.0);
      expect(mapa.gradient.first.$2.a, 0.0);
    });
  });

  group('ClusterManager', () {
    test('los saltos de color empiezan en cero', () {
      // Una expresión `step` de MapLibre exige que el primer valor sea el de
      // por defecto; si el primer salto no empieza en 0, los grupos pequeños
      // salen sin color.
      const gestor = ClusterManager(clusterManagerId: ClusterManagerId('c'));
      expect(gestor.colorSteps.first.$1, 0);
      expect(gestor.radiusSteps.first.$1, 0);
    });
  });

  group('MinMaxZoomPreference', () {
    test('unbounded no limita nada', () {
      expect(MinMaxZoomPreference.unbounded.minZoom, isNull);
      expect(MinMaxZoomPreference.unbounded.maxZoom, isNull);
    });
  });

  group('InfoWindow', () {
    test('noText está vacía', () {
      expect(InfoWindow.noText.isEmpty, isTrue);
    });

    test('un builder la hace no vacía aunque no tenga texto', () {
      // Es la ventaja de reimplementarla como widget: cabe cualquier cosa.
      final ventana = InfoWindow(builder: (context) => const SizedBox.shrink());
      expect(ventana.isEmpty, isFalse);
    });
  });

  group('BitmapDescriptor', () {
    test('el marcador por defecto no necesita subirse', () {
      expect(BitmapDescriptor.defaultMarker.needsUpload, isFalse);
    });

    test('los tintes con nombre de Google están', () {
      expect(MarkerHue.hueRed, 0.0);
      expect(MarkerHue.hueAzure, 210.0);
      expect(
        BitmapDescriptor.defaultMarkerWithHue(MarkerHue.hueGreen).hue,
        120.0,
      );
    });
  });
}
