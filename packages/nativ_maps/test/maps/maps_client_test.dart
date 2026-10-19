// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:nativ_maps/nativ_maps.dart';
import 'package:test/test.dart';

import '../support/fake_service.dart';

void main() {
  late FakeAlsService service;
  late NativMaps maps;
  final carolina = LatLng(-0.1825, -78.4840);

  setUp(() {
    service = FakeAlsService();
    maps = fakeNativMaps(service);
  });

  tearDown(() => maps.close());

  group('staticMap', () {
    test('va a /v2/static/map, no a /v2/static-map', () async {
      service.stubBytes('/v2/static/map', <int>[
        0xFF,
        0xD8,
      ], type: 'image/jpeg');

      final imagen = await maps.maps.staticMap(
        center: carolina,
        zoom: 14,
        width: 400,
        height: 300,
      );

      expect(service.lastRequest.method, 'GET');
      expect(service.lastRequest.path, '/v2/static/map');
      expect(service.lastRequest.param('center'), '-78.484,-0.1825');
      expect(imagen.contentType, 'image/jpeg');
    });

    test('usa los nombres cortos: lang, pois y scale-unit', () async {
      service.stubBytes('/v2/static/map', <int>[
        0xFF,
        0xD8,
      ], type: 'image/jpeg');

      await maps.maps.staticMap(
        center: carolina,
        zoom: 14,
        width: 400,
        height: 300,
        language: 'es',
        pointsOfInterest: false,
        scaleBarUnit: ScaleBarUnit.kilometers,
      );

      // Un nombre que el servicio no conoce no da error: se ignora en
      // silencio. Por eso se comprueba el nombre exacto.
      final query = service.lastRequest.query;
      expect(service.lastRequest.param('lang'), 'es');
      expect(service.lastRequest.param('pois'), 'Disabled');
      expect(service.lastRequest.param('scale-unit'), 'Kilometers');
      expect(query.containsKey('language'), isFalse);
      expect(query.containsKey('points-of-interests'), isFalse);
      expect(query.containsKey('scale-bar-unit'), isFalse);
    });

    test('la URL lleva la misma ruta que la petición', () {
      final url = maps.maps.staticMapUrl(
        center: carolina,
        radiusMeters: 800,
        width: 400,
        height: 300,
      );

      expect(Uri.parse(url!).path, '/v2/static/map');
      expect(Uri.parse(url).queryParameters['radius'], '800');
    });

    group('lanza antes de enviar', () {
      test('con un tamaño fuera de 64..1400', () {
        expect(
          () => maps.maps.staticMap(
            center: carolina,
            zoom: 14,
            width: 63,
            height: 300,
          ),
          throwsArgumentError,
        );
        expect(
          () => maps.maps.staticMap(
            center: carolina,
            zoom: 14,
            width: 400,
            height: 1401,
          ),
          throwsArgumentError,
        );
      });

      test('con un estilo que no es standard ni satellite', () {
        expect(
          () => maps.maps.staticMap(
            center: carolina,
            zoom: 14,
            width: 400,
            height: 300,
            style: MapStyle.monochrome,
          ),
          throwsArgumentError,
        );
      });

      test('con zoom y radiusMeters a la vez', () {
        expect(
          () => maps.maps.staticMap(
            center: carolina,
            zoom: 14,
            radiusMeters: 500,
            width: 400,
            height: 300,
          ),
          throwsArgumentError,
        );
      });

      test('con center y sin zoom ni radiusMeters', () {
        expect(
          () => maps.maps.staticMap(center: carolina, width: 400, height: 300),
          throwsArgumentError,
        );
      });

      tearDown(() => expect(service.requests, isEmpty));
    });
  });

  group('plantillas de URL', () {
    test('tileUrlTemplate deja {z}, {x} e {y} literales y lleva la clave', () {
      final url = maps.maps.tileUrlTemplate('vector.basemap')!;

      // `Uri` las codifica como %7B…%7D, y entonces MapLibre no las sustituye.
      expect(url, contains('/v2/tiles/vector.basemap/{z}/{x}/{y}?'));
      expect(url, isNot(contains('%7B')));
      expect(url, contains('key=CLAVE-DE-PRUEBA'));
    });

    test('glyphsUrlTemplate deja las llaves literales y va sin clave', () {
      final url = maps.maps.glyphsUrlTemplate()!;

      expect(
        url,
        'https://maps.geo.us-east-1.amazonaws.com/v2/glyphs/{fontstack}/'
        '{range}.pbf',
      );
    });

    test('spritesUrl sigue la ruta del estilo y va sin clave ni extensión', () {
      expect(
        maps.maps.spritesUrl(MapStyle.standard),
        'https://maps.geo.us-east-1.amazonaws.com/v2/styles/Standard/Light/'
        'Default/sprites/sprites',
      );
      expect(
        maps.maps.spritesUrl(
          MapStyle.monochrome,
          colorScheme: MapColorScheme.dark,
        ),
        endsWith('/v2/styles/Monochrome/Dark/Default/sprites/sprites'),
      );
    });
  });
}
