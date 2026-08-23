// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:compass_maps_google/compass_maps_google.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Un tema oscuro real, del estilo de los que produce el Styling Wizard de
/// Google y publica Snazzy Maps. Es el caso concreto que motiva este código:
/// un proyecto que migra casi siempre trae uno de estos.
const _temaOscuro = '''
[
  { "elementType": "geometry", "stylers": [{ "color": "#242f3e" }] },
  { "elementType": "labels.text.stroke", "stylers": [{ "color": "#242f3e" }] },
  { "elementType": "labels.text.fill", "stylers": [{ "color": "#746855" }] },
  {
    "featureType": "poi",
    "elementType": "labels.text.fill",
    "stylers": [{ "color": "#d59563" }]
  },
  {
    "featureType": "road",
    "elementType": "geometry",
    "stylers": [{ "color": "#38414e" }]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry",
    "stylers": [{ "color": "#746855" }]
  },
  {
    "featureType": "water",
    "elementType": "geometry",
    "stylers": [{ "color": "#17263c" }]
  },
  {
    "featureType": "transit",
    "stylers": [{ "visibility": "off" }]
  }
]
''';

void main() {
  group('lectura del formato de Google', () {
    test('lee el tema oscuro entero', () {
      final estilo = GoogleMapStyle.parse(_temaOscuro);
      expect(estilo.rules, hasLength(8));
      expect(estilo.rules.first.elementType, 'geometry');
      expect(estilo.rules.first.featureType, 'all'); // por defecto
      expect(estilo.rules.first.stylers.first.color, const Color(0xFF242F3E));
    });

    test('lee los ocho stylers de la referencia de Google', () {
      final estilo = GoogleMapStyle.parse('''
      [{
        "featureType": "water",
        "stylers": [
          { "color": "#112233" },
          { "hue": "#ff0000" },
          { "saturation": -40 },
          { "lightness": 25 },
          { "gamma": 1.8 },
          { "invert_lightness": true },
          { "visibility": "simplified" },
          { "weight": 3 }
        ]
      }]
      ''');
      final stylers = estilo.rules.first.stylers;
      expect(stylers[0].color, const Color(0xFF112233));
      expect(stylers[1].hue, const Color(0xFFFF0000));
      expect(stylers[2].saturation, -40);
      expect(stylers[3].lightness, 25);
      expect(stylers[4].gamma, 1.8);
      expect(stylers[5].invertLightness, isTrue);
      expect(stylers[6].visibility, 'simplified');
      expect(stylers[7].weight, 3);
    });

    test('acepta el color con y sin alfa', () {
      final estilo = GoogleMapStyle.parse(
        '[{"stylers":[{"color":"#80112233"}]},'
        '{"stylers":[{"color":"#112233"}]}]',
      );
      expect(estilo.rules[0].stylers.first.color, const Color(0x80112233));
      expect(estilo.rules[1].stylers.first.color, const Color(0xFF112233));
    });

    test('lanza si la raíz no es una lista', () {
      expect(
        () => GoogleMapStyle.parse('{"featureType":"water"}'),
        throwsFormatException,
      );
    });

    test('ignora las entradas basura en vez de reventar', () {
      // Un estilo copiado a mano puede traer un `null` o un número suelto.
      final estilo = GoogleMapStyle.parse(
        '[null, 42, {"featureType":"water"}]',
      );
      expect(estilo.rules, hasLength(1));
    });
  });

  group('transformaciones de color', () {
    test('color es absoluto: pisa todo lo que había', () {
      const styler = GoogleStyler(color: Color(0xFF112233));
      expect(styler.applyTo(const Color(0xFFAABBCC)), const Color(0xFF112233));
    });

    test('hue cambia el matiz y conserva la luminosidad', () {
      // Es la diferencia con `color`: `hue` tiñe, no pinta encima.
      const styler = GoogleStyler(hue: Color(0xFFFF0000));
      final base = HSLColor.fromColor(const Color(0xFF3366AA));
      final resultado = HSLColor.fromColor(styler.applyTo(base.toColor()));
      expect(resultado.lightness, closeTo(base.lightness, 0.02));
      expect(resultado.saturation, closeTo(base.saturation, 0.02));
      expect(resultado.hue, closeTo(0, 1)); // rojo
    });

    test('lightness sube y baja el brillo dentro de los límites', () {
      const masClaro = GoogleStyler(lightness: 30);
      const masOscuro = GoogleStyler(lightness: -30);
      const base = Color(0xFF808080);
      expect(
        HSLColor.fromColor(masClaro.applyTo(base)).lightness,
        greaterThan(HSLColor.fromColor(base).lightness),
      );
      expect(
        HSLColor.fromColor(masOscuro.applyTo(base)).lightness,
        lessThan(HSLColor.fromColor(base).lightness),
      );
      // Y no se sale: +100 sobre un color ya claro no da un valor imposible.
      const alTope = GoogleStyler(lightness: 100);
      expect(
        HSLColor.fromColor(alTope.applyTo(const Color(0xFFEEEEEE))).lightness,
        lessThanOrEqualTo(1.0),
      );
    });

    test('saturation −100 deja el color en gris', () {
      const gris = GoogleStyler(saturation: -100);
      final resultado = HSLColor.fromColor(
        gris.applyTo(const Color(0xFFFF0000)),
      );
      expect(resultado.saturation, closeTo(0, 0.01));
    });

    test('invert_lightness invierte el brillo', () {
      const invertir = GoogleStyler(invertLightness: true);
      final claro = HSLColor.fromColor(const Color(0xFFEEEEEE)).lightness;
      final invertido = HSLColor.fromColor(
        invertir.applyTo(const Color(0xFFEEEEEE)),
      );
      expect(invertido.lightness, closeTo(1.0 - claro, 0.02));
    });

    test('gamma es no lineal, no un desplazamiento', () {
      const gamma = GoogleStyler(gamma: 2.0);
      final medio = HSLColor.fromColor(gamma.applyTo(const Color(0xFF808080)));
      // Gamma 2 sobre luminosidad 0,5 da √0,5 ≈ 0,707.
      expect(medio.lightness, closeTo(0.707, 0.03));
    });

    test('el orden de aplicación es el que documenta Google', () {
      // Color, luego tinte, luego saturación, brillo, gamma e inversión.
      // Aplicar `color` y `lightness` juntos parte del color absoluto.
      const combinado = GoogleStyler(color: Color(0xFF000000), lightness: 50);
      final resultado = HSLColor.fromColor(
        combinado.applyTo(const Color(0xFFFFFFFF)),
      );
      // Si el orden fuera al revés, saldría de blanco y quedaría en 1,0.
      expect(resultado.lightness, closeTo(0.5, 0.02));
    });
  });

  group('coincidencia de capas', () {
    test('`all` coincide con todo', () {
      expect(GoogleMapStyle.matchesFeature('all', 'lo-que-sea'), isTrue);
    });

    test('water encuentra las capas de agua del estilo de AWS', () {
      for (final capa in <String>[
        'water',
        'water-shadow',
        'waterway-river',
        'ocean-labels',
      ]) {
        expect(
          GoogleMapStyle.matchesFeature('water', capa),
          isTrue,
          reason: capa,
        );
      }
      expect(GoogleMapStyle.matchesFeature('water', 'road-motorway'), isFalse);
    });

    test('road.highway distingue autopistas de calles', () {
      expect(
        GoogleMapStyle.matchesFeature('road.highway', 'road-motorway'),
        isTrue,
      );
      expect(
        GoogleMapStyle.matchesFeature('road.highway', 'road-minor'),
        isFalse,
      );
      expect(GoogleMapStyle.matchesFeature('road.local', 'road-minor'), isTrue);
    });

    test('un featureType desconocido no coincide con nada', () {
      // Preferible a coincidir con todo: una regla que no se entiende no debe
      // repintar el mapa entero. Aparece en el informe.
      expect(
        GoogleMapStyle.matchesFeature('inventado.que.no.existe', 'water'),
        isFalse,
      );
    });

    test('separa geometría de etiquetas por elementType', () {
      const reglaGeometria = GoogleStyleRule(
        featureType: 'water',
        elementType: 'geometry',
      );
      const reglaEtiquetas = GoogleStyleRule(
        featureType: 'water',
        elementType: 'labels.text.fill',
      );

      expect(GoogleMapStyle.appliesTo(reglaGeometria, 'water'), isTrue);
      expect(
        GoogleMapStyle.appliesTo(reglaGeometria, 'water-name-label'),
        isFalse,
      );
      expect(GoogleMapStyle.appliesTo(reglaEtiquetas, 'water'), isFalse);
      expect(
        GoogleMapStyle.appliesTo(reglaEtiquetas, 'water-name-label'),
        isTrue,
      );
    });

    test('reconoce las etiquetas por varias palabras', () {
      for (final capa in <String>[
        'road-label',
        'poi-name',
        'country-text',
        'road-shield',
        'poi-icon',
      ]) {
        expect(GoogleMapStyle.isLabelLayer(capa), isTrue, reason: capa);
      }
      expect(GoogleMapStyle.isLabelLayer('water'), isFalse);
    });

    test('la tabla de traducción cubre los 27 featureType de Google', () {
      // Si Google añade uno y no está aquí, sus reglas caen en el informe de
      // no aplicadas en vez de desaparecer. La cuenta es la comprobación de
      // que la tabla se escribió entera y no a medias.
      const deGoogle = <String>[
        'all',
        'administrative',
        'administrative.country',
        'administrative.land_parcel',
        'administrative.locality',
        'administrative.neighborhood',
        'administrative.province',
        'landscape',
        'landscape.man_made',
        'landscape.natural',
        'landscape.natural.landcover',
        'landscape.natural.terrain',
        'poi',
        'poi.attraction',
        'poi.business',
        'poi.government',
        'poi.medical',
        'poi.park',
        'poi.place_of_worship',
        'poi.school',
        'poi.sports_complex',
        'road',
        'road.arterial',
        'road.highway',
        'road.highway.controlled_access',
        'road.local',
        'transit',
        'transit.line',
        'transit.station',
        'transit.station.airport',
        'transit.station.bus',
        'transit.station.rail',
        'water',
      ];
      for (final tipo in deGoogle) {
        expect(
          GoogleMapStyle.featureKeywords.containsKey(tipo),
          isTrue,
          reason: 'falta $tipo en la tabla de traducción',
        );
      }
    });
  });

  group('GoogleStyleReport', () {
    test('dice la cobertura y qué faltó', () {
      const informe = GoogleStyleReport(
        appliedRules: 6,
        unmatchedRules: <String>['transit.station.bus/all — sin capa'],
        touchedLayers: 42,
        totalLayers: 180,
      );
      expect(informe.isComplete, isFalse);
      expect(informe.coverage, closeTo(6 / 7, 0.01));
      // El informe tiene que ser legible de un vistazo: es lo que hace que la
      // traducción no falle en silencio.
      expect(informe.toString(), contains('transit.station.bus'));
      expect(informe.toString(), contains('42 de 180 capas'));
    });

    test('sin reglas cuenta como completo', () {
      const informe = GoogleStyleReport(
        appliedRules: 0,
        unmatchedRules: <String>[],
        touchedLayers: 0,
        totalLayers: 100,
      );
      expect(informe.isComplete, isTrue);
      expect(informe.coverage, 1.0);
    });
  });

  group('MapType', () {
    test('los cuatro tipos de Google tienen destino', () {
      expect(MapType.normal.asMapStyle, MapStyle.standard);
      expect(MapType.satellite.asMapStyle, MapStyle.satellite);
      expect(MapType.hybrid.asMapStyle, MapStyle.hybrid);
      expect(MapType.terrain.asMapStyle, MapStyle.standard);
    });

    test('solo terrain pide relieve', () {
      // Es donde este paquete sale mejor que Google: el relieve es un
      // parámetro del descriptor y no un estilo cerrado.
      expect(MapType.terrain.terrainOption, MapTerrain.hillshade);
      expect(MapType.normal.terrainOption, isNull);
    });
  });

  group('MapColorSchemeCompat', () {
    test('followSystem sigue al brillo de la plataforma', () {
      expect(
        MapColorSchemeCompat.followSystem.resolve(Brightness.dark),
        MapColorScheme.dark,
      );
      expect(
        MapColorSchemeCompat.followSystem.resolve(Brightness.light),
        MapColorScheme.light,
      );
    });

    test('los explícitos ignoran la plataforma', () {
      expect(
        MapColorSchemeCompat.dark.resolve(Brightness.light),
        MapColorScheme.dark,
      );
    });
  });
}
