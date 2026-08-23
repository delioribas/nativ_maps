// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:compass_maps/compass_maps.dart';
import 'package:test/test.dart';

void main() {
  group('decodeFlexiblePolyline', () {
    // Vector de referencia del repositorio heremaps/flexible-polyline.
    // Es el que distingue una implementación correcta de una que aplica el
    // alfabeto de Google: con la tabla equivocada, el primer punto ya sale mal.
    const referencia = 'BFoz5xJ67i1B1B7PzIhaxL7Y';
    const esperado = <(double, double)>[
      (50.10228, 8.69821),
      (50.10201, 8.69567),
      (50.10063, 8.69150),
      (50.09878, 8.68752),
    ];

    test('decodifica el vector de referencia de HERE', () {
      final puntos = decodeFlexiblePolyline(referencia);
      expect(puntos, hasLength(esperado.length));
      for (var i = 0; i < esperado.length; i++) {
        expect(puntos[i].latitude, closeTo(esperado[i].$1, 1e-5));
        expect(puntos[i].longitude, closeTo(esperado[i].$2, 1e-5));
      }
    });

    test('la cabecera son DOS enteros, no uno', () {
      // Este es el segundo fallo original: leer solo la versión y tomarla por
      // la cabecera deja la precisión en `1 & 0x0F = 1`, es decir dividir
      // entre 10 en vez de entre 100 000. Una ruta de Quito acaba en el
      // Pacífico. Si la precisión se leyera mal, la latitud saldría ~500 000
      // veces mayor y quedaría fuera del rango legal de LatLng.
      final puntos = decodeFlexiblePolyline(referencia);
      expect(puntos.first.latitude, inInclusiveRange(-90, 90));
      expect(puntos.first.latitude, closeTo(50.1, 0.1));
    });

    test('devuelve vacío con la cadena vacía', () {
      expect(decodeFlexiblePolyline(''), isEmpty);
    });

    test('lanza ante un carácter fuera del alfabeto', () {
      expect(() => decodeFlexiblePolyline('BFoz5xJ!!!'), throwsFormatException);
    });

    test('lanza ante una versión que no es la 1', () {
      // 'C' vale 2 en el alfabeto de HERE: versión 2.
      expect(() => decodeFlexiblePolyline('CFoz5xJ'), throwsFormatException);
    });
  });

  group('encodeFlexiblePolyline', () {
    test('el viaje de ida y vuelta conserva los puntos', () {
      final original = <LatLng>[
        LatLng(-0.18070, -78.46780),
        LatLng(-0.18150, -78.46900),
        LatLng(-0.18220, -78.47010),
        LatLng(-2.17090, -79.92240),
      ];
      final vuelta = decodeFlexiblePolyline(encodeFlexiblePolyline(original));
      expect(vuelta, hasLength(original.length));
      for (var i = 0; i < original.length; i++) {
        expect(vuelta[i].latitude, closeTo(original[i].latitude, 1e-5));
        expect(vuelta[i].longitude, closeTo(original[i].longitude, 1e-5));
      }
    });

    test('comprime de verdad frente al JSON equivalente', () {
      // La razón de existir del formato: una ruta larga ocupa una fracción.
      final ruta = <LatLng>[
        for (var i = 0; i < 500; i++)
          LatLng(-0.18 - i * 0.0001, -78.46 - i * 0.0001),
      ];
      final codificada = encodeFlexiblePolyline(ruta);
      final comoJson = ruta.map((p) => p.toLonLat()).toList().toString();
      expect(codificada.length, lessThan(comoJson.length ~/ 3));
    });

    test('rechaza una precisión fuera de rango', () {
      expect(
        () => encodeFlexiblePolyline(<LatLng>[LatLng(0, 0)], precision: 20),
        throwsArgumentError,
      );
    });

    test('la lista vacía produce solo la cabecera', () {
      final codificada = encodeFlexiblePolyline(const <LatLng>[]);
      expect(decodeFlexiblePolyline(codificada), isEmpty);
    });
  });

  group('decodeGooglePolyline', () {
    test('decodifica el vector de referencia de Google', () {
      // El de la documentación de Google: (38.5,-120.2) (40.7,-120.95)
      // (43.252,-126.453).
      final puntos = decodeGooglePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
      expect(puntos, hasLength(3));
      expect(puntos[0].latitude, closeTo(38.5, 1e-5));
      expect(puntos[0].longitude, closeTo(-120.2, 1e-5));
      expect(puntos[2].latitude, closeTo(43.252, 1e-5));
      expect(puntos[2].longitude, closeTo(-126.453, 1e-5));
    });

    test('los dos alfabetos NO son intercambiables', () {
      // La prueba que justifica tener dos decodificadores: pasar una cadena de
      // HERE por el de Google no falla, da otros números.
      final comoHere = decodeFlexiblePolyline('BFoz5xJ67i1B1B7PzIhaxL7Y');
      List<LatLng> comoGoogle;
      try {
        comoGoogle = decodeGooglePolyline('BFoz5xJ67i1B1B7PzIhaxL7Y');
      } on FormatException {
        // También vale que reviente: lo que no puede es coincidir.
        return;
      }
      expect(comoGoogle, isNot(equals(comoHere)));
    });
  });
}
