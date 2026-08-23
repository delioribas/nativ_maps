// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:nativ_maps/nativ_maps.dart';
import 'package:test/test.dart';

import '../support/fake_service.dart';

void main() {
  late FakeAlsService service;
  late NativMaps maps;

  setUp(() {
    service = FakeAlsService();
    maps = fakeNativMaps(service);
  });

  tearDown(() => maps.close());

  group('las 7 operaciones van a los endpoints de v2', () {
    test('autocomplete → POST /v2/autocomplete', () async {
      service.stub('/v2/autocomplete', <String, dynamic>{
        'ResultItems': <dynamic>[
          <String, dynamic>{
            'PlaceId': 'ec-1',
            'Title': 'Av. Amazonas',
            'PlaceType': 'Street',
          },
        ],
      });

      final resultados = await maps.places.autocomplete(query: 'amazonas');

      expect(service.lastRequest.method, 'POST');
      expect(service.lastRequest.path, '/v2/autocomplete');
      expect(resultados, hasLength(1));
      expect(resultados.first.title, 'Av. Amazonas');
      expect(resultados.first.placeId, 'ec-1');
      expect(resultados.first.placeType, PlaceType.street);
    });

    test('searchText → POST /v2/search-text, con posición', () async {
      service.stub('/v2/search-text', <String, dynamic>{
        'ResultItems': <dynamic>[
          <String, dynamic>{
            'PlaceId': 'ec-2',
            'Title': 'Gasolinera Primax',
            'PlaceType': 'PointOfInterest',
            // Amazon Location manda [lon, lat].
            'Position': <double>[-78.4678, -0.1807],
            'Address': <String, dynamic>{'Label': 'Av. Amazonas 1234, Quito'},
            'Distance': 420,
          },
        ],
        'NextToken': 'pagina-2',
      });

      final respuesta = await maps.places.searchText(queryText: 'gasolinera');

      expect(service.lastRequest.path, '/v2/search-text');
      expect(respuesta.places, hasLength(1));
      // La comprobación que importa: el orden se invierte al leer.
      expect(respuesta.places.first.position!.latitude, closeTo(-0.1807, 1e-9));
      expect(
        respuesta.places.first.position!.longitude,
        closeTo(-78.4678, 1e-9),
      );
      expect(respuesta.places.first.distanceMeters, 420);
      expect(respuesta.hasMore, isTrue);
      expect(respuesta.nextToken, 'pagina-2');
    });

    test('reverseGeocode → POST /v2/reverse-geocode', () async {
      service.stub('/v2/reverse-geocode', <String, dynamic>{
        'ResultItems': <dynamic>[
          <String, dynamic>{
            'Title': 'Av. Amazonas y Naciones Unidas',
            'PlaceType': 'Intersection',
            'Position': <double>[-78.4678, -0.1807],
            'Address': <String, dynamic>{
              'Label': 'Av. Amazonas y Naciones Unidas, Quito, ECU',
              'Country': <String, dynamic>{'Code3': 'ECU', 'Name': 'Ecuador'},
              'Locality': 'Quito',
              'Street': 'Av. Amazonas',
              'Intersection': <String>['Av. Amazonas', 'Naciones Unidas'],
            },
          },
        ],
      });

      final lugares = await maps.places.reverseGeocode(
        LatLng(-0.1807, -78.4678),
        radiusMeters: 200,
      );

      final enviado = service.lastRequest.body;
      expect(enviado['QueryPosition'], <double>[-78.4678, -0.1807]);
      expect(enviado['QueryRadius'], 200);
      expect(lugares.first.address!.country!.code3, 'ECU');
      expect(lugares.first.address!.shortLabel, 'Av. Amazonas');
      expect(lugares.first.placeType!.isPrecise, isTrue);
    });

    test('getPlace → GET /v2/place/{id}, sin ResultItems', () async {
      service.stub('/v2/place/ec-2', <String, dynamic>{
        // La respuesta de esta operación NO viene envuelta.
        'PlaceId': 'ec-2',
        'Title': 'Hospital Metropolitano',
        'PlaceType': 'PointOfInterest',
        'Position': <double>[-78.4820, -0.1900],
        'Contacts': <String, dynamic>{
          'Phones': <dynamic>[
            <String, dynamic>{'Value': '+593 2 399 8000'},
          ],
        },
        'AccessPoints': <dynamic>[
          <String, dynamic>{
            'Position': <double>[-78.4823, -0.1902],
          },
        ],
      });

      final lugar = await maps.places.getPlace(
        'ec-2',
        additionalFeatures: const <PlaceFeature>[
          PlaceFeature.contact,
          PlaceFeature.access,
        ],
      );

      expect(service.lastRequest.method, 'GET');
      expect(service.lastRequest.path, '/v2/place/ec-2');
      expect(
        service.lastRequest.param('additional-features'),
        'Contact,Access',
      );
      expect(lugar.contacts!.phones.first.value, '+593 2 399 8000');
      // El punto de acceso gana a la posición para navegar.
      expect(lugar.navigationPosition, isNot(equals(lugar.position)));
    });

    test('geocode → POST /v2/geocode, con matchScore', () async {
      service.stub('/v2/geocode', <String, dynamic>{
        'ResultItems': <dynamic>[
          <String, dynamic>{
            'Title': 'Av. Amazonas 1234',
            'PlaceType': 'PointAddress',
            'Position': <double>[-78.4678, -0.1807],
            'MatchScores': <String, dynamic>{'Overall': 0.97},
          },
        ],
      });

      final lugares = await maps.places.geocode(queryText: 'Amazonas 1234');

      expect(service.lastRequest.path, '/v2/geocode');
      // Es lo que permite aceptar una dirección sin preguntar al usuario.
      expect(lugares.first.matchScore, 0.97);
      expect(lugares.first.placeType, PlaceType.pointAddress);
    });

    test('searchNearby → POST /v2/search-nearby', () async {
      service.stub('/v2/search-nearby', <String, dynamic>{
        'ResultItems': <dynamic>[
          <String, dynamic>{
            'Title': 'Farmacia',
            'Position': <double>[-78.4680, -0.1810],
            'Distance': 95,
          },
        ],
      });

      await maps.places.searchNearby(
        position: LatLng(-0.1807, -78.4678),
        radiusMeters: 500,
      );

      final enviado = service.lastRequest.body;
      expect(service.lastRequest.path, '/v2/search-nearby');
      expect(enviado['QueryPosition'], <double>[-78.4678, -0.1807]);
      expect(enviado['QueryRadius'], 500);
    });

    test('suggest → POST /v2/suggest, mezcla lugares y consultas', () async {
      service.stub('/v2/suggest', <String, dynamic>{
        'ResultItems': <dynamic>[
          <String, dynamic>{
            'Title': 'Restaurantes',
            'SuggestResultItemType': 'Query',
            'Query': <String, dynamic>{
              'QueryId': 'q-1',
              'QueryType': 'Category',
            },
          },
          <String, dynamic>{
            'Title': 'La Briciola',
            'SuggestResultItemType': 'Place',
            'Place': <String, dynamic>{
              'PlaceId': 'ec-9',
              'Position': <double>[-78.49, -0.20],
            },
          },
        ],
        'QueryRefinements': <dynamic>[
          <String, dynamic>{'RefinedTerm': 'restaurante', 'StartIndex': 0},
        ],
      });

      final respuesta = await maps.places.suggest(query: 'restau');

      expect(respuesta.results, hasLength(2));
      expect(respuesta.results[0].type, SuggestResultType.query);
      expect(respuesta.results[0].queryId, 'q-1');
      expect(respuesta.results[1].type, SuggestResultType.place);
      expect(respuesta.results[1].place!.placeId, 'ec-9');
      expect(respuesta.queryRefinements, hasLength(1));
    });
  });

  group('lo que NO se debe enviar', () {
    test('nunca sale DistanceUnit: en v2 no existe y da 400', () async {
      service.stub('/v2/search-text', <String, dynamic>{
        'ResultItems': <dynamic>[],
      });
      await maps.places.searchText(queryText: 'x');
      expect(service.lastRequest.rawBody, isNot(contains('DistanceUnit')));
    });

    test('los campos nulos no viajan', () async {
      service.stub('/v2/search-text', <String, dynamic>{
        'ResultItems': <dynamic>[],
      });
      await maps.places.searchText(queryText: 'x');
      // Un campo presente con valor nulo cuenta como enviado para la API.
      expect(service.lastRequest.rawBody, isNot(contains('null')));
    });

    test(
      'autocomplete fuerza SingleUse aunque el cliente sea Storage',
      () async {
        final almacen = fakeNativMaps(
          service,
          intendedUse: IntendedUse.storage,
        );
        addTearDown(almacen.close);
        service.stub('/v2/autocomplete', <String, dynamic>{
          'ResultItems': <dynamic>[],
        });

        await almacen.places.autocomplete(query: 'x');

        // La API rechaza Storage aquí; no es una decisión de este paquete.
        expect(service.lastRequest.body['IntendedUse'], 'SingleUse');
      },
    );

    test('searchText sí respeta el uso previsto configurado', () async {
      final almacen = fakeNativMaps(service, intendedUse: IntendedUse.storage);
      addTearDown(almacen.close);
      service.stub('/v2/search-text', <String, dynamic>{
        'ResultItems': <dynamic>[],
      });

      await almacen.places.searchText(queryText: 'x');

      expect(service.lastRequest.body['IntendedUse'], 'Storage');
    });
  });

  group('los errores salen donde se pueden corregir', () {
    test('boundingBox y circle a la vez lanzan antes de enviar', () async {
      expect(
        () => maps.places.autocomplete(
          query: 'x',
          filter: SearchFilter(
            boundingBox: LatLngBounds(
              southwest: LatLng(-1, -80),
              northeast: LatLng(1, -78),
            ),
            circle: (center: LatLng(0, -79), radiusMeters: 1000),
          ),
        ),
        throwsArgumentError,
      );
      // Lo importante: no se llegó a gastar una petición.
      expect(service.requests, isEmpty);
    });

    test('maxResults fuera de rango lanza en vez de recortarse', () async {
      // Recortar en silencio deja a quien llama creyendo que tiene 200
      // resultados y con una paginación que nunca avanza.
      expect(
        () => maps.places.autocomplete(query: 'x', maxResults: 200),
        throwsArgumentError,
      );
      expect(service.requests, isEmpty);
    });

    test('searchText sin texto ni queryId lanza', () async {
      expect(() => maps.places.searchText(), throwsArgumentError);
    });

    test('queryText y queryId juntos lanzan', () async {
      expect(
        () => maps.places.searchText(queryText: 'a', queryId: 'b'),
        throwsArgumentError,
      );
    });

    test('geocode con texto y componentes a la vez lanza', () async {
      expect(
        () => maps.places.geocode(
          queryText: 'a',
          queryComponents: const AddressComponents(locality: 'Quito'),
        ),
        throwsArgumentError,
      );
    });

    test('una clave vacía falla antes de la red, con mensaje claro', () async {
      final sinClave = fakeNativMaps(
        service,
        credentials: const ApiKeyCredentials(''),
      );
      addTearDown(sinClave.close);

      expect(
        () => sinClave.places.searchText(queryText: 'x'),
        throwsA(isA<NativMapsConfigurationException>()),
      );
      expect(service.requests, isEmpty);
    });
  });

  group('la caché evita pagar dos veces lo mismo', () {
    test('dos autocomplete idénticos son una sola petición', () async {
      service.stub('/v2/autocomplete', <String, dynamic>{
        'ResultItems': <dynamic>[
          <String, dynamic>{'Title': 'Amazonas'},
        ],
      });

      await maps.places.autocomplete(query: 'amazonas');
      await maps.places.autocomplete(query: 'amazonas');

      expect(service.requests, hasLength(1));
    });

    test('cambiar la consulta sí pide de nuevo', () async {
      service.stub('/v2/autocomplete', <String, dynamic>{
        'ResultItems': <dynamic>[],
      });
      await maps.places.autocomplete(query: 'a');
      await maps.places.autocomplete(query: 'ab');
      expect(service.requests, hasLength(2));
    });

    test('clearCaches obliga a volver a pedir', () async {
      service.stub('/v2/autocomplete', <String, dynamic>{
        'ResultItems': <dynamic>[],
      });
      await maps.places.autocomplete(query: 'a');
      maps.clearCaches();
      await maps.places.autocomplete(query: 'a');
      expect(service.requests, hasLength(2));
    });
  });
}
