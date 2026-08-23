// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:nativ_maps/nativ_maps.dart';
import 'package:test/test.dart';

void main() {
  final quito = LatLng(-0.1807, -78.4678);

  group('pathLength', () {
    test('un camino de menos de dos puntos mide cero', () {
      expect(pathLength(<LatLng>[]), 0);
      expect(pathLength(<LatLng>[quito]), 0);
    });

    test('suma los tramos', () {
      final path = <LatLng>[
        quito,
        quito.offset(100, 0),
        quito.offset(100, 0).offset(150, 90),
      ];
      expect(pathLength(path), closeTo(250, 1));
    });
  });

  group('crossTrackMeters', () {
    test('mide la perpendicular a un segmento', () {
      final start = quito;
      final end = quito.offset(1000, 90);
      // Un punto a mitad del segmento, desplazado 40 m al norte.
      final point = quito.offset(500, 90).offset(40, 0);
      expect(crossTrackMeters(point, start, end), closeTo(40, 1));
    });

    test('se recorta al extremo cuando la perpendicular cae fuera', () {
      final start = quito;
      final end = quito.offset(100, 90);
      // 300 m más allá del final, alineado con la prolongación. Sin recorte
      // la distancia sería casi cero, que es geométricamente cierto y
      // operativamente absurdo.
      final point = quito.offset(400, 90);
      expect(crossTrackMeters(point, start, end), closeTo(300, 2));
    });
  });

  group('nearestPointOnPath', () {
    test('devuelve un punto interpolado, no el vértice más cercano', () {
      // Dos vértices a 1 km. El coche está justo en medio, sobre la línea.
      final path = <LatLng>[quito, quito.offset(1000, 90)];
      final point = quito.offset(500, 90);
      final r = nearestPointOnPath(path, point);

      expect(r.distanceMeters, closeTo(0, 1));
      expect(r.alongMeters, closeTo(500, 2));
      expect(r.fraction, closeTo(0.5, 0.01));
      // El vértice más cercano estaría a 500 m: quedarse con él daría un
      // desvío de 500 m para un coche perfectamente en su carril.
      expect(r.position.distanceTo(point), lessThan(2));
    });

    test('elige el segmento correcto en un camino con varias piernas', () {
      final path = <LatLng>[
        quito,
        quito.offset(500, 90),
        quito.offset(500, 90).offset(500, 0),
      ];
      final point = quito.offset(500, 90).offset(250, 0).offset(10, 90);
      final r = nearestPointOnPath(path, point);

      expect(r.segmentIndex, 1);
      expect(r.distanceMeters, closeTo(10, 1));
      expect(r.alongMeters, closeTo(750, 3));
    });

    test('la ventana de búsqueda no mira hacia atrás', () {
      final path = <LatLng>[
        for (var i = 0; i < 20; i++) quito.offset(100.0 * i, 90),
      ];
      final nearTheStart = quito.offset(150, 90);
      final r = nearestPointOnPath(
        path,
        nearTheStart,
        fromIndex: 10,
        maxSegments: 3,
      );
      // Solo pudo mirar los segmentos 10 a 12, así que se engancha al 10.
      expect(r.segmentIndex, 10);
    });

    test('lanza con menos de dos puntos', () {
      expect(
        () => nearestPointOnPath(<LatLng>[quito], quito),
        throwsArgumentError,
      );
    });
  });

  group('interpolateOnPath', () {
    final path = <LatLng>[quito, quito.offset(1000, 90)];

    test('recorta a los extremos', () {
      expect(interpolateOnPath(path, -50), path.first);
      expect(interpolateOnPath(path, 99999), path.last);
    });

    test('interpola dentro del segmento', () {
      final mid = interpolateOnPath(path, 500);
      expect(mid.distanceTo(quito), closeTo(500, 2));
    });
  });

  group('simplifyPath', () {
    test('quita los puntos alineados y conserva los extremos', () {
      final path = <LatLng>[
        for (var i = 0; i <= 20; i++) quito.offset(50.0 * i, 90),
      ];
      final clamped = simplifyPath(path, toleranceMeters: 5);

      expect(clamped.first, path.first);
      expect(clamped.last, path.last);
      expect(clamped.length, 2);
    });

    test('conserva una desviación mayor que la tolerancia', () {
      final path = <LatLng>[
        quito,
        quito.offset(500, 90).offset(30, 0),
        quito.offset(1000, 90),
      ];
      expect(simplifyPath(path, toleranceMeters: 5).length, 3);
      expect(simplifyPath(path, toleranceMeters: 50).length, 2);
    });

    test('un rastro urbano se queda en una fracción de sus puntos', () {
      // Una avenida con ruido de un par de metros: la forma se conserva, los
      // puntos no hacen falta.
      final path = <LatLng>[
        for (var i = 0; i < 400; i++)
          quito.offset(10.0 * i, 45).offset(i.isEven ? 1.5 : 0, 135),
      ];
      final clamped = simplifyPath(path, toleranceMeters: 5);
      expect(clamped.length, lessThan(path.length ~/ 10));
    });

    test('rechaza una tolerancia no positiva', () {
      expect(
        () => simplifyPath(<LatLng>[quito, quito], toleranceMeters: 0),
        throwsArgumentError,
      );
    });
  });
}
