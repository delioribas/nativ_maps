// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:compass_maps/src/client/transport.dart';
import 'package:compass_maps/src/core/enums.dart';
import 'package:compass_maps/src/core/lat_lng.dart';
import 'package:meta/meta.dart';

/// Las operaciones de Amazon Location Maps v2.
///
/// | Operación | Cómo se usa aquí |
/// |---|---|
/// | `GetStyleDescriptor` | [styleDescriptorUrl], que consume MapLibre |
/// | `GetStaticMap` | [staticMap] y [staticMapUrl] |
/// | `GetTile` | MapLibre las pide sola desde el descriptor |
/// | `GetGlyphs` | ídem |
/// | `GetSprites` | ídem |
///
/// ## Por qué tres de las cinco no tienen método
///
/// El descriptor de estilo **lleva dentro sus propias URLs** de teselas,
/// glifos y sprites, ya firmadas o con la clave puesta. MapLibre las sigue
/// solo. Construirlas aparte —como hacía la generación anterior— era una forma
/// de que se desincronizaran del estilo sin que nadie se enterara: se cambiaba
/// el estilo y las etiquetas seguían pidiendo los glifos del anterior.
///
/// Están expuestas igual en [tileUrlTemplate], [glyphsUrlTemplate] y
/// [spritesUrlTemplate] para quien monte su propio renderizador o quiera
/// precargar teselas, pero no son el camino normal.
class MapsClient {
  /// Construye el cliente. Uso interno: llega ya montado en `CompassMaps`.
  @internal
  MapsClient({
    required AlsTransport transport,
    required this.region,
    this.politicalView,
  }) : _transport = transport;

  final AlsTransport _transport;

  /// Región de AWS.
  final String region;

  /// Punto de vista político para las fronteras en disputa, en ISO 3166.
  final String? politicalView;

  static const AlsService _service = AlsService.maps;

  /// El host de Maps para esta región.
  String get host => _service.hostFor(region);

  // ─── GetStyleDescriptor ───────────────────────────────────────────────

  /// La URL del descriptor de estilo, que es lo que consume MapLibre.
  ///
  /// ```dart
  /// CompassMap(
  ///   styleUrl: maps.styleDescriptorUrl(
  ///     MapStyle.standard,
  ///     colorScheme: MapColorScheme.dark,
  ///     traffic: MapTraffic.congestion,
  ///   ),
  ///   ...
  /// )
  /// ```
  ///
  /// ## El modo oscuro lo renderiza el servidor
  ///
  /// [colorScheme] no es un filtro sobre teselas claras: el servicio genera el
  /// estilo oscuro entero. Por eso las etiquetas siguen siendo legibles, cosa
  /// que no ocurre al invertir los colores de un mapa claro — que es lo que
  /// hay que hacer con `google_maps_flutter`.
  ///
  /// ## Lo que Google no da, y aquí es un parámetro
  ///
  /// [traffic], [terrain], [buildings], [contourDensity], [poiDensity],
  /// [poiCategories] y [travelModes] los dibuja el servidor **dentro del mismo
  /// estilo**, sin una segunda petición ni una capa superpuesta. [poiDensity]
  /// en [MapPoiDensity.off] es lo que se quiere cuando el mapa es el fondo de
  /// datos propios y los puntos de interés solo estorban.
  ///
  /// **La URL lleva la clave dentro** en el camino de clave de API. No hay que
  /// registrarla ni enseñarla en pantalla.
  ///
  /// Devuelve `null` si no hay credenciales configuradas, en vez de lanzar: a
  /// esto se le llama desde `build()`, y una excepción ahí no degrada la
  /// pantalla, impide abrirla.
  String? styleDescriptorUrl(
    MapStyle style, {
    MapColorScheme? colorScheme,
    MapTraffic? traffic,
    MapTerrain? terrain,
    MapBuildings? buildings,
    MapContourDensity? contourDensity,
    MapPoiDensity? poiDensity,
    List<MapPoiCategory> poiCategories = const <MapPoiCategory>[],
    List<MapTravelMode> travelModes = const <MapTravelMode>[],
    String? politicalView,
  }) {
    if (!_transport.credentials.isConfigured) return null;
    if (poiCategories.length > 9) {
      throw ArgumentError.value(
        poiCategories.length,
        'poiCategories',
        'el máximo son 9 categorías',
      );
    }
    if (travelModes.length > 2) {
      throw ArgumentError.value(
        travelModes.length,
        'travelModes',
        'el máximo son 2 modos',
      );
    }

    final query = <String, List<String>>{
      if (colorScheme != null) 'color-scheme': <String>[colorScheme.wireName],
      if (traffic != null) 'traffic': <String>[traffic.wireName],
      if (terrain != null) 'terrain': <String>[terrain.wireName],
      if (buildings != null) 'buildings': <String>[buildings.wireName],
      if (contourDensity != null)
        'contour-density': <String>[contourDensity.wireName],
      if (poiDensity != null) 'poi-density': <String>[poiDensity.wireName],
      // Cada categoría va como un parámetro repetido, no separadas por comas.
      if (poiCategories.isNotEmpty)
        'poi-categories': poiCategories
            .map((c) => c.wireName)
            .toList(growable: false),
      if (travelModes.isNotEmpty)
        'travel-modes': travelModes
            .map((m) => m.wireName)
            .toList(growable: false),
      if ((politicalView ?? this.politicalView) != null)
        'political-view': <String>[politicalView ?? this.politicalView!],
    };

    final base = _transport.credentials.baseUri(_service, region);
    final uri = base.replace(
      path: '${_trimSlash(base.path)}/v2/styles/${style.wireName}/descriptor',
      queryParameters: query.isEmpty ? null : query,
    );
    return _withApiKey(uri).toString();
  }

  /// La pareja de URLs de estilo para alternar entre día y noche.
  ///
  /// En la generación anterior esto pedía **dos recursos distintos** creados a
  /// mano en la consola (`MiMapa` y `MiMapaDark`) que había que mantener
  /// sincronizados: cambiar uno y olvidar el otro dejaba la app con dos mapas
  /// que no se parecían. Ahora es el mismo estilo con otro parámetro.
  ({String? light, String? dark}) dayNightStyleUrls(
    MapStyle style, {
    MapTraffic? traffic,
    MapTerrain? terrain,
    MapPoiDensity? poiDensity,
    String? politicalView,
  }) => (
    light: styleDescriptorUrl(
      style,
      colorScheme: MapColorScheme.light,
      traffic: traffic,
      terrain: terrain,
      poiDensity: poiDensity,
      politicalView: politicalView,
    ),
    dark: styleDescriptorUrl(
      style,
      colorScheme: MapColorScheme.dark,
      traffic: traffic,
      terrain: terrain,
      poiDensity: poiDensity,
      politicalView: politicalView,
    ),
  );

  // ─── GetStaticMap ─────────────────────────────────────────────────────

  /// Una imagen de mapa ya renderizada. `GET /v2/static-map`.
  ///
  /// **Lo pinta el servidor**, así que sirve donde no hay widget: la miniatura
  /// de una notificación push, el mapa de un PDF, la imagen de un correo, la
  /// vista previa de una lista. `google_maps_flutter` resuelve esto con
  /// `takeSnapshot`, que exige tener el mapa montado y visible en pantalla.
  ///
  /// Hay tres formas de encuadrar, **excluyentes** entre sí:
  ///
  /// - [center] con [zoom]: el encuadre clásico;
  /// - [boundingBox]: el rectángulo que hay que ver;
  /// - [boundedPositions]: los puntos que tienen que caber, y el servicio
  ///   calcula el encuadre. Es la más cómoda para pintar una ruta.
  ///
  /// [geoJsonOverlay] dibuja geometría encima: la línea de la ruta, los
  /// marcadores, el polígono de una isócrona. Es lo que convierte esto en una
  /// miniatura útil y no en un mapa vacío.
  Future<AlsBytes> staticMap({
    LatLng? center,
    double? zoom,
    LatLngBounds? boundingBox,
    List<LatLng> boundedPositions = const <LatLng>[],
    double? radiusMeters,
    required int width,
    required int height,
    MapStyle style = MapStyle.standard,
    MapColorScheme? colorScheme,
    String? geoJsonOverlay,
    double? paddingPixels,
    ScaleBarUnit? scaleBarUnit,
    bool? cropLabels,
    bool? pointsOfInterest,
    String? language,
    String? politicalView,
  }) async {
    final query = _staticMapQuery(
      center: center,
      zoom: zoom,
      boundingBox: boundingBox,
      boundedPositions: boundedPositions,
      radiusMeters: radiusMeters,
      width: width,
      height: height,
      style: style,
      colorScheme: colorScheme,
      geoJsonOverlay: geoJsonOverlay,
      paddingPixels: paddingPixels,
      scaleBarUnit: scaleBarUnit,
      cropLabels: cropLabels,
      pointsOfInterest: pointsOfInterest,
      language: language,
      politicalView: politicalView,
    );

    return _transport.getBytes(
      operation: 'GetStaticMap',
      service: _service,
      path: '/v2/static-map',
      queryParameters: query,
    );
  }

  /// La URL del mapa estático, sin descargarlo.
  ///
  /// Sirve para pasársela a un `Image.network` o a una plantilla de correo. A
  /// cambio, **la URL lleva la clave dentro** en el camino de clave de API: no
  /// se puede mandar a un tercero ni escribir en un registro. Para eso está
  /// [staticMap], que descarga los bytes y no expone nada.
  String? staticMapUrl({
    LatLng? center,
    double? zoom,
    LatLngBounds? boundingBox,
    List<LatLng> boundedPositions = const <LatLng>[],
    double? radiusMeters,
    required int width,
    required int height,
    MapStyle style = MapStyle.standard,
    MapColorScheme? colorScheme,
    String? geoJsonOverlay,
    double? paddingPixels,
    ScaleBarUnit? scaleBarUnit,
    bool? cropLabels,
    bool? pointsOfInterest,
    String? language,
    String? politicalView,
  }) {
    if (!_transport.credentials.isConfigured) return null;
    final query = _staticMapQuery(
      center: center,
      zoom: zoom,
      boundingBox: boundingBox,
      boundedPositions: boundedPositions,
      radiusMeters: radiusMeters,
      width: width,
      height: height,
      style: style,
      colorScheme: colorScheme,
      geoJsonOverlay: geoJsonOverlay,
      paddingPixels: paddingPixels,
      scaleBarUnit: scaleBarUnit,
      cropLabels: cropLabels,
      pointsOfInterest: pointsOfInterest,
      language: language,
      politicalView: politicalView,
    );
    final base = _transport.credentials.baseUri(_service, region);
    final uri = base.replace(
      path: '${_trimSlash(base.path)}/v2/static-map',
      queryParameters: query,
    );
    return _withApiKey(uri).toString();
  }

  Map<String, String> _staticMapQuery({
    required int width,
    required int height,
    required MapStyle style,
    LatLng? center,
    double? zoom,
    LatLngBounds? boundingBox,
    List<LatLng> boundedPositions = const <LatLng>[],
    double? radiusMeters,
    MapColorScheme? colorScheme,
    String? geoJsonOverlay,
    double? paddingPixels,
    ScaleBarUnit? scaleBarUnit,
    bool? cropLabels,
    bool? pointsOfInterest,
    String? language,
    String? politicalView,
  }) {
    final framings = <String>[
      if (center != null) 'center',
      if (boundingBox != null) 'boundingBox',
      if (boundedPositions.isNotEmpty) 'boundedPositions',
    ];
    if (framings.isEmpty) {
      throw ArgumentError(
        'staticMap necesita un encuadre: center (con zoom), boundingBox o '
        'boundedPositions.',
      );
    }
    if (framings.length > 1) {
      throw ArgumentError(
        'center, boundingBox y boundedPositions son excluyentes; llegaron '
        '${framings.join(', ')}. La API responde 400 con más de uno.',
      );
    }
    if (width < 1 || width > 1440 || height < 1 || height > 1440) {
      throw ArgumentError(
        'width y height admiten entre 1 y 1440 píxeles; llegaron '
        '${width}x$height.',
      );
    }

    return <String, String>{
      'width': '$width',
      'height': '$height',
      'style': style.wireName,
      if (center != null) 'center': _lonLatParam(center),
      if (zoom != null) 'zoom': _trimNumber(zoom),
      // (los dos anteriores transforman el valor, así que `?` no aplica)
      if (boundingBox != null)
        'bounding-box': boundingBox.toBbox().map(_trimNumber).join(','),
      if (boundedPositions.isNotEmpty)
        'bounded-positions': boundedPositions.map(_lonLatParam).join(','),
      if (radiusMeters != null) 'radius': '${radiusMeters.round()}',
      if (colorScheme != null) 'color-scheme': colorScheme.wireName,
      'geojson-overlay': ?geoJsonOverlay,
      if (paddingPixels != null) 'padding': '${paddingPixels.round()}',
      if (scaleBarUnit != null) 'scale-bar-unit': scaleBarUnit.wireName,
      if (cropLabels != null) 'crop-labels': '$cropLabels',
      if (pointsOfInterest != null) 'points-of-interests': '$pointsOfInterest',
      'language': ?language,
      if ((politicalView ?? this.politicalView) != null)
        'political-view': politicalView ?? this.politicalView!,
    };
  }

  // ─── Tiles, glyphs, sprites ───────────────────────────────────────────

  /// La plantilla de URL de teselas, con `{z}`, `{x}` e `{y}` sin sustituir.
  ///
  /// **No hace falta para pintar un mapa**: el descriptor de estilo ya la trae
  /// dentro y MapLibre la sigue sola. Está aquí para quien monte su propio
  /// renderizador o quiera precargar una zona a mano.
  ///
  /// [tileset] es normalmente `raster.satellite` o el que indique el estilo.
  String? tileUrlTemplate(String tileset) {
    if (!_transport.credentials.isConfigured) return null;
    final base = _transport.credentials.baseUri(_service, region);
    final uri = base.replace(
      path: '${_trimSlash(base.path)}/v2/tiles/$tileset/{z}/{x}/{y}',
    );
    return _withApiKey(uri).toString();
  }

  /// La plantilla de URL de glifos, con `{fontstack}` y `{range}`.
  ///
  /// Igual que [tileUrlTemplate]: el estilo ya la trae.
  String? glyphsUrlTemplate() {
    if (!_transport.credentials.isConfigured) return null;
    final base = _transport.credentials.baseUri(_service, region);
    final uri = base.replace(
      path: '${_trimSlash(base.path)}/v2/glyphs/{fontstack}/{range}.pbf',
    );
    return _withApiKey(uri).toString();
  }

  /// La URL de una hoja de sprites.
  String? spritesUrlTemplate(String fileName) {
    if (!_transport.credentials.isConfigured) return null;
    final base = _transport.credentials.baseUri(_service, region);
    final uri = base.replace(
      path: '${_trimSlash(base.path)}/v2/sprites/$fileName',
    );
    return _withApiKey(uri).toString();
  }

  // ─── Auxiliares ───────────────────────────────────────────────────────

  /// Añade la clave a la URL cuando las credenciales son de clave de API.
  ///
  /// No se puede pasar por `credentials.sign` porque eso trabaja sobre una
  /// `http.BaseRequest`, y aquí lo que se produce es una URL que se
  /// le entrega a MapLibre para que la pida él. Es la única frontera del
  /// paquete donde la clave sale en texto, y por eso el método que la usa
  /// documenta que la URL no se puede registrar.
  Uri _withApiKey(Uri uri) {
    final apiKey = _transport.credentials.apiKeyForUrl;
    if (apiKey == null) return uri;
    return uri.replace(
      queryParameters: <String, dynamic>{
        ...uri.queryParametersAll,
        'key': apiKey,
      },
    );
  }

  static String _lonLatParam(LatLng point) =>
      '${_trimNumber(point.longitude)},${_trimNumber(point.latitude)}';

  /// Escribe un número sin notación científica y sin decimales sobrantes.
  ///
  /// `Uri` no lo hace: un `1e-7` en la cadena de consulta provoca un `400`
  /// porque el servicio no lo interpreta como número.
  static String _trimNumber(double value) {
    var text = value.toStringAsFixed(6);
    if (!text.contains('.')) return text;
    while (text.endsWith('0')) {
      text = text.substring(0, text.length - 1);
    }
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
    return text;
  }

  static String _trimSlash(String path) =>
      path.endsWith('/') ? path.substring(0, path.length - 1) : path;
}
