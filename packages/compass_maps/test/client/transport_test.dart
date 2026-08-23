// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:compass_maps/compass_maps.dart';
import 'package:test/test.dart';

import '../support/fake_service.dart';

void main() {
  late FakeAlsService service;

  setUp(() => service = FakeAlsService());

  group('reintentos', () {
    test('reintenta un 503 y acaba respondiendo', () async {
      service
        ..failTimes('/v2/search-text', 2)
        ..stub('/v2/search-text', <String, dynamic>{
          'ResultItems': <dynamic>[
            <String, dynamic>{'Title': 'ok'},
          ],
        });
      final maps = fakeCompassMaps(service);
      addTearDown(maps.close);

      final respuesta = await maps.places.searchText(queryText: 'x');

      expect(respuesta.places.first.title, 'ok');
      expect(service.requests, hasLength(3)); // 1 + 2 reintentos
    });

    test(
      'NO reintenta un 400: reintentar un parámetro mal es gastar cuota',
      () async {
        service.stub('/v2/search-text', <String, dynamic>{
          'message': 'parámetro inválido',
        }, status: 400);
        final maps = fakeCompassMaps(service);
        addTearDown(maps.close);

        await expectLater(
          maps.places.searchText(queryText: 'x'),
          throwsA(isA<AlsApiException>()),
        );
        expect(service.requests, hasLength(1));
      },
    );

    test('NO reintenta un 403', () async {
      service.stub('/v2/search-text', <String, dynamic>{
        'message': 'no',
      }, status: 403);
      final maps = fakeCompassMaps(service);
      addTearDown(maps.close);

      await expectLater(
        maps.places.searchText(queryText: 'x'),
        throwsA(isA<AlsApiException>()),
      );
      expect(service.requests, hasLength(1));
    });

    test('sí reintenta un 429', () async {
      service
        ..failTimes('/v2/search-text', 1, status: 429)
        ..stub('/v2/search-text', <String, dynamic>{
          'ResultItems': <dynamic>[],
        });
      final maps = fakeCompassMaps(service);
      addTearDown(maps.close);

      await maps.places.searchText(queryText: 'x');
      expect(service.requests, hasLength(2));
    });

    test('el cuerpo se reenvía entero en cada intento', () async {
      // `http.Request` consume su cuerpo al enviarse: reutilizar el objeto
      // manda el segundo intento vacío, y eso solo se ve cuando la red va mal,
      // que es cuando menos se puede depurar.
      service
        ..failTimes('/v2/search-text', 1)
        ..stub('/v2/search-text', <String, dynamic>{
          'ResultItems': <dynamic>[],
        });
      final maps = fakeCompassMaps(service);
      addTearDown(maps.close);

      await maps.places.searchText(queryText: 'gasolinera');

      expect(service.requests, hasLength(2));
      for (final peticion in service.requests) {
        expect(peticion.body['QueryText'], 'gasolinera');
      }
    });
  });

  group('errores', () {
    test('el 403 trae la pista de los tres nombres de firma', () async {
      service.stub('/v2/routes', <String, dynamic>{
        'message': 'denegado',
      }, status: 403);
      final maps = fakeCompassMaps(service);
      addTearDown(maps.close);

      try {
        await maps.routes.calculateRoutes(
          origin: LatLng(0, 0),
          destination: LatLng(1, 1),
        );
        fail('debería haber lanzado');
      } on AlsApiException catch (e) {
        expect(e.isConfigurationError, isTrue);
        expect(e.isRetryable, isFalse);
        expect(e.service, AlsService.routes);
        // El nombre de firma correcto para este servicio, escrito en el error.
        expect(e.hint, contains('geo-routes'));
        expect(e.requestId, 'prueba-0001');
      }
    });

    test('el 400 recuerda las tres causas más repetidas', () async {
      service.stub('/v2/search-text', <String, dynamic>{
        'message': 'malo',
      }, status: 400);
      final maps = fakeCompassMaps(service);
      addTearDown(maps.close);

      try {
        await maps.places.searchText(queryText: 'x');
        fail('debería haber lanzado');
      } on AlsApiException catch (e) {
        expect(e.hint, contains('DistanceUnit'));
      }
    });

    test('la URL NUNCA aparece en el mensaje de error', () async {
      // En el camino de clave de API la clave viaja en la consulta, y un
      // mensaje de error acaba en un informe de fallos o en una captura.
      service.stub('/v2/search-text', <String, dynamic>{
        'message': 'malo',
      }, status: 400);
      final maps = fakeCompassMaps(
        service,
        credentials: const ApiKeyCredentials('CLAVE-SECRETA-123'),
      );
      addTearDown(maps.close);

      try {
        await maps.places.searchText(queryText: 'x');
        fail('debería haber lanzado');
      } on AlsApiException catch (e) {
        expect(e.toString(), isNot(contains('CLAVE-SECRETA-123')));
        expect(e.toString(), isNot(contains('amazonaws.com')));
      }
    });

    test(
      'un 200 que no es JSON da AlsParseException, no AlsApiException',
      () async {
        final maps = fakeCompassMaps(service);
        addTearDown(maps.close);
        // Sin encolar respuesta, el servicio falso devuelve 404 con JSON; para
        // este caso encolamos bytes, que no son JSON.
        service.stubBytes('/v2/search-text', <int>[1, 2, 3], type: 'image/png');

        await expectLater(
          maps.places.searchText(queryText: 'x'),
          throwsA(isA<AlsParseException>()),
        );
      },
    );

    test('usar el cliente después de close lanza StateError', () async {
      final maps = fakeCompassMaps(service)..close();
      expect(() => maps.places.searchText(queryText: 'x'), throwsStateError);
    });
  });

  group('autenticación', () {
    test('la clave de API va en la consulta, no en una cabecera', () async {
      service.stub('/v2/search-text', <String, dynamic>{
        'ResultItems': <dynamic>[],
      });
      final maps = fakeCompassMaps(
        service,
        credentials: const ApiKeyCredentials('MI-CLAVE'),
      );
      addTearDown(maps.close);

      await maps.places.searchText(queryText: 'x');

      expect(service.lastRequest.param('key'), 'MI-CLAVE');
    });

    test('el proxy manda a su host y dice qué servicio era', () async {
      service.stub('/geo/v2/search-text', <String, dynamic>{
        'ResultItems': <dynamic>[],
      });
      final maps = fakeCompassMaps(
        service,
        credentials: ProxyCredentials(
          baseUrl: Uri.parse('https://api.miempresa.com/geo'),
          headers: const <String, String>{'Authorization': 'Bearer t'},
        ),
      );
      addTearDown(maps.close);

      await maps.places.searchText(queryText: 'x');

      final peticion = service.lastRequest;
      expect(peticion.path, '/geo/v2/search-text');
      expect(peticion.param('key'), isNull); // la clave no sale del servidor
      expect(peticion.headers['Authorization'], 'Bearer t');
      // Para que el proxy firme con el nombre correcto sin deducirlo.
      expect(peticion.headers['X-Compass-Service'], 'geo-places');
      expect(peticion.headers['X-Compass-Region'], 'us-east-1');
    });

    test('HeaderCredentials se consulta en cada petición', () async {
      service.stub('/v2/search-text', <String, dynamic>{
        'ResultItems': <dynamic>[],
      });
      var llamadas = 0;
      final maps = fakeCompassMaps(
        service,
        credentials: HeaderCredentials((service, region) async {
          llamadas++;
          return <String, String>{'X-Token': 'token-$llamadas'};
        }),
      );
      addTearDown(maps.close);

      await maps.places.searchText(queryText: 'a');
      await maps.places.searchText(queryText: 'b');

      expect(llamadas, 2);
      expect(service.lastRequest.headers['X-Token'], 'token-2');
    });

    test('los tres servicios firman con nombres distintos', () {
      expect(AlsService.places.signingName, 'geo-places');
      expect(AlsService.routes.signingName, 'geo-routes');
      expect(AlsService.maps.signingName, 'geo-maps');
      expect(
        AlsService.places.hostFor('us-east-1'),
        'places.geo.us-east-1.amazonaws.com',
      );
    });
  });
}
