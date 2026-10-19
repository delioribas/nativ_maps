// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

/// Las 17 operaciones que aceptan clave de API, contra Amazon Location de
/// verdad.
///
/// `dart test` las salta: gastan dinero. Se lanzan a propósito, desde
/// `packages/nativ_maps`, con
///
/// ```sh
/// set -a; source ../../.env; set +a
/// dart test -P live
/// ```
///
/// Cada respuesta se guarda cruda en `test/live/respuestas/`, **sin la
/// clave**, junto con la petición que la provocó. Es la materia prima para
/// convertir cualquier diferencia con lo que el paquete espera en una prueba
/// con la respuesta real.
///
/// El gasto de una pasada completa ronda las 25 unidades: la matriz es de
/// 2×2 y la isócrona lleva un solo umbral.
@Tags(<String>['live'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:nativ_maps/nativ_maps.dart';
import 'package:test/test.dart';

void main() {
  final apiKey = Platform.environment['ALS_API_KEY'];
  final region = Platform.environment['ALS_REGION'] ?? 'us-east-1';

  // Quito: lo bastante conocido para saber si un resultado tiene sentido.
  final carolina = LatLng(-0.1825, -78.4840);
  final amazonasNacionesUnidas = LatLng(-0.1807, -78.4678);
  final plazaGrande = LatLng(-0.2201, -78.5123);
  final quicentro = LatLng(-0.1762, -78.4797);
  final aeropuerto = LatLng(-0.1292, -78.3575);

  late _Recorder recorder;
  late NativMaps maps;

  group(
    'contra AWS',
    skip: apiKey == null
        ? 'Falta ALS_API_KEY. Carga el .env: set -a; source ../../.env'
        : false,
    () {
      setUpAll(() {
        recorder = _Recorder(apiKey!);
        maps = NativMaps(
          region: region,
          credentials: ApiKeyCredentials(apiKey),
          language: 'es',
          // Una pasada completa son ~25 unidades. El tope corta un bucle
          // desbocado, no una ejecución normal.
          budget: Budget(maxUnits: 80, window: const Duration(hours: 1)),
          httpClient: recorder,
        );
      });

      tearDownAll(() {
        maps.close();
        recorder.close();
      });

      group('places', () {
        String? placeIdFromSearch;

        test('autocomplete', () async {
          recorder.label = 'autocomplete';
          final suggestions = await maps.places.autocomplete(
            query: 'Av. Amazonas',
            biasPosition: carolina,
            filter: const SearchFilter(includeCountries: <String>['ECU']),
          );

          expect(suggestions, isNotEmpty);
          for (final s in suggestions) {
            expect(s.title, isNotEmpty);
            expect(s.placeId, isNotNull, reason: s.title);
            // Un tipo que no está en el enum se lee como null.
            expect(s.placeType, isNotNull, reason: s.title);
          }
        });

        test('searchText', () async {
          recorder.label = 'search-text';
          final response = await maps.places.searchText(
            queryText: 'farmacia',
            biasPosition: carolina,
            maxResults: 5,
          );

          expect(response.places, isNotEmpty);
          for (final place in response.places) {
            expect(place.position, isNotNull, reason: place.title);
            expect(place.placeType, isNotNull, reason: place.title);
            expect(place.formattedAddress, isNotNull, reason: place.title);
          }
          placeIdFromSearch = response.places.first.placeId;
        });

        test('getPlace', () async {
          recorder.label = 'get-place';
          final placeId = placeIdFromSearch;
          if (placeId == null) {
            markTestSkipped('searchText no dejó un placeId');
            return;
          }
          final place = await maps.places.getPlace(
            placeId,
            additionalFeatures: const <PlaceFeature>[
              PlaceFeature.contact,
              PlaceFeature.timeZone,
            ],
          );

          expect(place.placeId, placeId);
          expect(place.position, isNotNull);
          expect(place.placeType, isNotNull);
          expect(place.timeZone?.name, isNotNull);
        });

        test('reverseGeocode', () async {
          recorder.label = 'reverse-geocode';
          final places = await maps.places.reverseGeocode(
            amazonasNacionesUnidas,
            radiusMeters: 200,
            maxResults: 3,
          );

          expect(places, isNotEmpty);
          for (final place in places) {
            expect(place.position, isNotNull, reason: place.title);
            expect(place.placeType, isNotNull, reason: place.title);
          }
          printOnFailure(
            'tipos: ${places.map((p) => p.placeType?.name).join(', ')}',
          );
        });

        test('geocode', () async {
          recorder.label = 'geocode';
          final places = await maps.places.geocode(
            queryText: 'Av. Amazonas y Naciones Unidas, Quito',
            includeCountries: const <String>['ECU'],
            maxResults: 3,
          );

          expect(places, isNotEmpty);
          final first = places.first;
          expect(first.position, isNotNull);
          expect(first.placeType, isNotNull);
          // Tiene que caer en Quito, no en otra Av. Amazonas del país.
          expect(
            first.position!.distanceTo(amazonasNacionesUnidas),
            lessThan(5000),
          );
        });

        test('searchNearby', () async {
          recorder.label = 'search-nearby';
          final response = await maps.places.searchNearby(
            position: carolina,
            radiusMeters: 500,
            maxResults: 5,
          );

          expect(response.places, isNotEmpty);
          for (final place in response.places) {
            expect(place.position, isNotNull, reason: place.title);
            expect(place.distanceMeters, isNotNull, reason: place.title);
            expect(place.distanceMeters, lessThanOrEqualTo(500));
          }
        });

        test('suggest', () async {
          recorder.label = 'suggest';
          final response = await maps.places.suggest(
            query: 'cafe',
            biasPosition: carolina,
            additionalFeatures: const <PlaceFeature>[PlaceFeature.core],
          );

          expect(response.results, isNotEmpty);
          for (final result in response.results) {
            expect(result.title, isNotEmpty);
            if (result.type == SuggestResultType.place) {
              expect(result.place, isNotNull, reason: result.title);
              expect(result.place!.position, isNotNull, reason: result.title);
            } else {
              expect(result.queryId, isNotNull, reason: result.title);
            }
          }
        });
      });

      group('routes', () {
        test('calculateRoutes', () async {
          recorder.label = 'calculate-routes';
          final response = await maps.routes.calculateRoutes(
            origin: carolina,
            destination: plazaGrande,
            legAdditionalFeatures: const <RouteFeature>[
              RouteFeature.summary,
              RouteFeature.tolls,
            ],
            maxAlternatives: 1,
          );

          final best = response.best;
          expect(best, isNotNull);
          expect(best!.distanceMeters, greaterThan(3000));
          expect(best.duration, greaterThan(Duration.zero));
          expect(best.legs, isNotEmpty);
          expect(best.points, isNotEmpty);
          expect(best.steps, isNotEmpty);
          expect(best.legs.first.travelMode, TravelMode.car);
          // La geometría tiene que empezar cerca del origen: si sale en otro
          // continente, el orden lat/lon se ha invertido en algún sitio.
          expect(best.points.first.distanceTo(carolina), lessThan(500));
          expect(best.points.last.distanceTo(plazaGrande), lessThan(500));
        });

        test('calculateRouteMatrix', () async {
          recorder.label = 'route-matrix';
          final matrix = await maps.routes.calculateRouteMatrix(
            origins: <LatLng>[carolina, plazaGrande],
            destinations: <LatLng>[quicentro, aeropuerto],
          );

          expect(matrix.originCount, 2);
          expect(matrix.destinationCount, 2);
          expect(matrix.errorCount, 0);
          for (final row in matrix.cells) {
            for (final cell in row) {
              expect(cell.isValid, isTrue, reason: cell.error);
              expect(cell.distanceMeters, greaterThan(0));
              expect(cell.duration, greaterThan(Duration.zero));
            }
          }
          // El aeropuerto está bastante más lejos que el Quicentro.
          expect(
            matrix.cells[0][1].distanceMeters,
            greaterThan(matrix.cells[0][0].distanceMeters),
          );
        });

        test('calculateIsolines', () async {
          recorder.label = 'isolines';
          final response = await maps.routes.calculateIsolines(
            origin: carolina,
            thresholds: Thresholds.time(const <Duration>[Duration(minutes: 5)]),
          );

          expect(response.isolines, hasLength(1));
          final isoline = response.isolines.first;
          expect(isoline.timeThreshold, const Duration(minutes: 5));
          expect(isoline.outerRing.length, greaterThan(3));
          // maxPoints: 300 por defecto. Con margen: es un objetivo, no un
          // máximo estricto del servicio.
          expect(isoline.pointCount, lessThan(600));
          expect(
            LatLngBounds.fromPoints(isoline.outerRing).contains(carolina),
            isTrue,
          );
        });

        test('snapToRoads', () async {
          recorder.label = 'snap-to-roads';
          final start = DateTime.utc(2026, 10, 18, 15);
          final trace = <LatLng>[
            LatLng(-0.2000, -78.4905),
            LatLng(-0.1960, -78.4893),
            LatLng(-0.1920, -78.4882),
            LatLng(-0.1880, -78.4870),
            LatLng(-0.1840, -78.4858),
          ];
          final response = await maps.routes.snapToRoads(
            tracePoints: <TracePoint>[
              for (var i = 0; i < trace.length; i++)
                TracePoint(
                  position: trace[i],
                  timestamp: start.add(Duration(seconds: 15 * i)),
                ),
            ],
            snapRadiusMeters: 300,
          );

          expect(response.geometry.points, isNotEmpty);
          expect(response.snappedPoints, isNotEmpty);
          expect(response.chunkCount, 1);
          for (final point in response.snappedPoints) {
            expect(point.displacementMeters ?? 0, lessThan(300));
          }
        });

        test('optimizeWaypoints', () async {
          recorder.label = 'optimize-waypoints';
          final response = await maps.routes.optimizeWaypoints(
            origin: carolina,
            waypoints: <OptimizationWaypoint>[
              OptimizationWaypoint(id: 'plaza-grande', position: plazaGrande),
              OptimizationWaypoint(id: 'quicentro', position: quicentro),
              OptimizationWaypoint(
                id: 'amazonas',
                position: amazonasNacionesUnidas,
              ),
            ],
          );

          expect(
            response.orderedIds,
            containsAll(<String>['plaza-grande', 'quicentro', 'amazonas']),
          );
          expect(response.distanceMeters, greaterThan(0));
          expect(response.duration, greaterThan(Duration.zero));
          expect(response.connections, isNotEmpty);
          expect(response.impedingWaypointIds, isEmpty);
        });
      });

      group('maps', () {
        Map<String, dynamic>? style;

        test('styleDescriptorUrl se puede cargar', () async {
          recorder.label = 'style-descriptor';
          final url = maps.maps.styleDescriptorUrl(MapStyle.standard);
          expect(url, isNotNull);

          final response = await recorder.get(Uri.parse(url!));
          expect(response.statusCode, 200, reason: response.body);
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          expect(json['version'], 8);
          expect(json['sources'], isA<Map<String, dynamic>>());
          expect(json['layers'], isA<List<dynamic>>());
          style = json;
        });

        test('tileUrlTemplate devuelve una tesela', () async {
          recorder.label = 'tile';
          final tileset = _tilesetFrom(style) ?? 'vector.basemap';
          final template = maps.maps.tileUrlTemplate(tileset);
          expect(template, isNotNull);

          final (x, y) = _tileFor(carolina, 12);
          final url = template!
              .replaceAll('{z}', '12')
              .replaceAll('{x}', '$x')
              .replaceAll('{y}', '$y');
          final response = await recorder.get(Uri.parse(url));

          expect(
            response.statusCode,
            200,
            reason: response.statusCode == 403
                ? 'La clave no permite geo-maps:GetTile. Sin eso el mapa '
                      'carga el estilo y se queda en blanco: revisa las '
                      'acciones de la clave en la consola de Amazon Location.'
                : 'tileset $tileset',
          );
          expect(response.bodyBytes, isNotEmpty);
        });

        test('glyphsUrlTemplate devuelve glifos', () async {
          recorder.label = 'glyphs';
          final template = maps.maps.glyphsUrlTemplate();
          expect(template, isNotNull);
          printOnFailure(
            'del estilo: ${recorder.redact('${style?['glyphs']}')}',
          );
          printOnFailure('del paquete: ${recorder.redact(template!)}');

          final font = _firstFontFrom(style) ?? 'Amazon Ember Regular';
          final url = template
              .replaceAll('{fontstack}', Uri.encodeComponent(font))
              .replaceAll('{range}', '0-255');
          final response = await recorder.get(Uri.parse(url));

          expect(response.statusCode, 200, reason: 'fuente $font');
          expect(response.bodyBytes, isNotEmpty);
        });

        test('spritesUrl devuelve sprites', () async {
          recorder.label = 'sprites';
          final base = maps.maps.spritesUrl(MapStyle.standard);
          expect(base, isNotNull);
          printOnFailure('del estilo: ${style?['sprite']}');
          printOnFailure('del paquete: $base');

          // Las cuatro que pide MapLibre por su cuenta a partir de la base.
          for (final suffix in <String>[
            '.json',
            '.png',
            '@2x.json',
            '@2x.png',
          ]) {
            final response = await recorder.get(Uri.parse('$base$suffix'));
            expect(response.statusCode, 200, reason: suffix);
            expect(response.bodyBytes, isNotEmpty);
          }
        });

        test('staticMap devuelve una imagen', () async {
          recorder.label = 'static-map';
          printOnFailure(
            'Un 403 «explicit deny» aquí es de la clave, no del paquete: no '
            'permite geo-maps:GetStaticMap.',
          );
          final image = await maps.maps.staticMap(
            center: carolina,
            zoom: 14,
            width: 400,
            height: 300,
          );

          expect(image.bytes, isNotEmpty);
          expect(image.contentType, startsWith('image/'));
        });
      });
    },
  );
}

/// Un cliente HTTP real que guarda cada intercambio en disco.
///
/// La clave se borra de las URL y de los cuerpos antes de escribir: un
/// descriptor de estilo, por ejemplo, la repite en cada URL que lleva dentro.
class _Recorder extends http.BaseClient {
  _Recorder(this._apiKey);

  final String _apiKey;
  final http.Client _inner = http.Client();
  final Directory _directory = Directory('test/live/respuestas');
  final Map<String, int> _counts = <String, int>{};

  /// El nombre con el que se guardan las respuestas de la prueba en curso.
  String label = 'sin-nombre';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final requestBody = request is http.Request ? request.body : '';
    final response = await _inner.send(request);
    final bytes = await response.stream.toBytes();
    _save(request, requestBody, response, bytes);
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      response.statusCode,
      contentLength: bytes.length,
      headers: response.headers,
      request: request,
      reasonPhrase: response.reasonPhrase,
    );
  }

  /// Quita la clave de [text], en claro y codificada para una URL.
  String redact(String text) => text
      .replaceAll(_apiKey, '<CLAVE>')
      .replaceAll(Uri.encodeQueryComponent(_apiKey), '<CLAVE>');

  void _save(
    http.BaseRequest request,
    String requestBody,
    http.StreamedResponse response,
    List<int> bytes,
  ) {
    _directory.createSync(recursive: true);
    final count = _counts[label] = (_counts[label] ?? 0) + 1;
    final name = count == 1 ? label : '$label-$count';
    final type = response.headers['content-type'] ?? '';

    Object? content;
    if (type.contains('json') || type.startsWith('text/')) {
      content = _decode(redact(utf8.decode(bytes, allowMalformed: true)));
    } else {
      File('${_directory.path}/$name.bin').writeAsBytesSync(bytes);
      content = '${bytes.length} bytes en $name.bin';
    }

    final record = <String, Object?>{
      'request': <String, Object?>{
        'method': request.method,
        'url': redact(request.url.toString()),
        if (requestBody.isNotEmpty) 'body': _decode(redact(requestBody)),
      },
      'status': response.statusCode,
      'contentType': type,
      'requestId': response.headers['x-amzn-requestid'],
      'response': content,
    };
    File(
      '${_directory.path}/$name.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(record));
  }

  static Object? _decode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return text;
    }
  }

  @override
  void close() => _inner.close();
}

/// El conjunto de teselas que usa el estilo, sacado de su primera fuente
/// vectorial: `…/v2/tiles/vector.basemap?key=…` → `vector.basemap`.
String? _tilesetFrom(Map<String, dynamic>? style) {
  final sources = style?['sources'];
  if (sources is! Map<String, dynamic>) return null;
  for (final source in sources.values) {
    if (source is! Map<String, dynamic>) continue;
    final url = source['url'];
    if (url is! String) continue;
    final segments = Uri.parse(url).pathSegments;
    final index = segments.indexOf('tiles');
    if (index >= 0 && index + 1 < segments.length) {
      return segments[index + 1];
    }
  }
  return null;
}

/// La primera fuente tipográfica que pide alguna capa del estilo.
String? _firstFontFrom(Map<String, dynamic>? style) {
  final layers = style?['layers'];
  if (layers is! List<dynamic>) return null;
  for (final layer in layers) {
    if (layer is! Map<String, dynamic>) continue;
    final layout = layer['layout'];
    if (layout is! Map<String, dynamic>) continue;
    final fonts = layout['text-font'];
    if (fonts is List<dynamic> && fonts.isNotEmpty && fonts.first is String) {
      return fonts.first as String;
    }
  }
  return null;
}

/// La tesela XYZ que contiene [point] en el nivel [zoom].
(int, int) _tileFor(LatLng point, int zoom) {
  final n = 1 << zoom;
  final x = ((point.longitude + 180) / 360 * n).floor();
  final latRad = point.latitude * math.pi / 180;
  final y =
      ((1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
              2 *
              n)
          .floor();
  return (x, y);
}
