// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:compass_maps/compass_maps.dart';
import 'package:test/test.dart';

void main() {
  group('LatLng', () {
    test('conserva el orden lat/lng y lo invierte solo en toLonLat', () {
      final quito = LatLng(-0.1807, -78.4678);
      expect(quito.latitude, -0.1807);
      expect(quito.longitude, -78.4678);
      // La única frontera donde el orden cambia.
      expect(quito.toLonLat(), <double>[-78.4678, -0.1807]);
    });

    test('fromLonLat lee el orden de Amazon Location', () {
      final punto = LatLng.fromLonLat(const <dynamic>[-78.4678, -0.1807]);
      expect(punto.latitude, closeTo(-0.1807, 1e-9));
      expect(punto.longitude, closeTo(-78.4678, 1e-9));
    });

    test('caza el par invertido en el constructor', () {
      // Una longitud de Quito (-78) puesta donde va la latitud queda fuera de
      // [-90, 90] solo a veces; con -78 no. Pero una latitud como longitud sí
      // se caza cuando la longitud pasa de 90.
      expect(() => LatLng(-78.4678, -0.1807), returnsNormally);
      expect(() => LatLng(120.0, 0.0), throwsArgumentError);
      expect(() => LatLng(0.0, 200.0), throwsArgumentError);
      expect(() => LatLng(double.nan, 0.0), throwsArgumentError);
    });

    test('fromLonLat lanza en vez de devolver el golfo de Guinea', () {
      // Este es el fallo que motivó la regla: LatLng(0, 0) es una coordenada
      // real y se pinta en el mapa exactamente igual que una correcta.
      expect(() => LatLng.fromLonLat(const <dynamic>[]), throwsFormatException);
      expect(
        () => LatLng.fromLonLat(const <dynamic>[1.0]),
        throwsFormatException,
      );
      expect(
        () => LatLng.fromLonLat(const <dynamic>['a', 'b']),
        throwsFormatException,
      );
    });

    test('distanceTo da la distancia por el gran círculo', () {
      final quito = LatLng(-0.1807, -78.4678);
      final guayaquil = LatLng(-2.1709, -79.9224);
      // Quito–Guayaquil son unos 270 km en línea recta.
      expect(quito.distanceTo(guayaquil), closeTo(270000, 8000));
      expect(quito.distanceTo(quito), closeTo(0, 1e-6));
    });

    test('bearingTo da 0 al norte y 90 al este', () {
      final origen = LatLng(0, 0);
      expect(origen.bearingTo(LatLng(1, 0)), closeTo(0, 0.01));
      expect(origen.bearingTo(LatLng(0, 1)), closeTo(90, 0.01));
      expect(origen.bearingTo(LatLng(-1, 0)), closeTo(180, 0.01));
      expect(origen.bearingTo(LatLng(0, -1)), closeTo(270, 0.01));
    });

    test('offset y distanceTo son inversos', () {
      final origen = LatLng(-0.1807, -78.4678);
      final destino = origen.offset(1000, 45);
      expect(origen.distanceTo(destino), closeTo(1000, 1));
      expect(origen.bearingTo(destino), closeTo(45, 0.5));
    });

    test('la igualdad es por valor', () {
      expect(LatLng(1, 2), equals(LatLng(1, 2)));
      expect(LatLng(1, 2).hashCode, equals(LatLng(1, 2).hashCode));
      expect(LatLng(1, 2), isNot(equals(LatLng(2, 1))));
    });
  });

  group('LatLngBounds', () {
    test('fromPoints lanza con la lista vacía, no devuelve infinitos', () {
      // Antes era un `assert`, que desaparece al compilar en release: avisaba
      // en depuración y fallaba callado en producción.
      expect(
        () => LatLngBounds.fromPoints(const <LatLng>[]),
        throwsArgumentError,
      );
    });

    test('fromPoints encierra todos los puntos', () {
      final bounds = LatLngBounds.fromPoints(<LatLng>[
        LatLng(-0.2, -78.5),
        LatLng(-0.1, -78.4),
        LatLng(-0.15, -78.6),
      ]);
      expect(bounds.southwest, equals(LatLng(-0.2, -78.6)));
      expect(bounds.northeast, equals(LatLng(-0.1, -78.4)));
      expect(bounds.contains(LatLng(-0.15, -78.5)), isTrue);
      expect(bounds.contains(LatLng(0.5, -78.5)), isFalse);
    });

    test('rechaza esquinas cambiadas', () {
      expect(
        () => LatLngBounds(southwest: LatLng(10, 0), northeast: LatLng(-10, 0)),
        throwsArgumentError,
      );
      expect(
        () => LatLngBounds(southwest: LatLng(0, 10), northeast: LatLng(0, -10)),
        throwsArgumentError,
      );
    });

    test('toBbox usa el orden de Amazon Location', () {
      final bounds = LatLngBounds(
        southwest: LatLng(-1, -80),
        northeast: LatLng(1, -78),
      );
      // [minLon, minLat, maxLon, maxLat]
      expect(bounds.toBbox(), <double>[-80, -1, -78, 1]);
      expect(LatLngBounds.fromBbox(bounds.toBbox()), equals(bounds));
    });

    test('padded no se sale del mundo en el polo', () {
      final polar = LatLngBounds(
        southwest: LatLng(89.9, 0),
        northeast: LatLng(89.99, 1),
      );
      final ancho = polar.padded(50000);
      expect(ancho.northeast.latitude, lessThanOrEqualTo(90.0));
      expect(ancho.southwest.longitude, greaterThanOrEqualTo(-180.0));
    });

    test('extend une dos rectángulos', () {
      final a = LatLngBounds(southwest: LatLng(0, 0), northeast: LatLng(1, 1));
      final b = LatLngBounds(
        southwest: LatLng(-1, -1),
        northeast: LatLng(0.5, 0.5),
      );
      final unido = a.extend(b);
      expect(unido.southwest, equals(LatLng(-1, -1)));
      expect(unido.northeast, equals(LatLng(1, 1)));
    });
  });
}
