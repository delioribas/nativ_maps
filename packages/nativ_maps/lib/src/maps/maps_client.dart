// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/client/transport.dart';
import 'package:nativ_maps/src/core/enums.dart';
import 'package:nativ_maps/src/core/lat_lng.dart';

/// The Amazon Location Maps v2 operations.
///
/// | Operation | How it's used here |
/// |---|---|
/// | `GetStyleDescriptor` | [styleDescriptorUrl], which MapLibre consumes |
/// | `GetStaticMap` | [staticMap] and [staticMapUrl] |
/// | `GetTile` | MapLibre requests them on its own from the descriptor |
/// | `GetGlyphs` | same |
/// | `GetSprites` | same |
///
/// ## Why three of the five have no method
///
/// The style descriptor **carries its own URLs** for tiles, glyphs and
/// sprites, with the key placed where it's needed. MapLibre follows them on
/// its own. Building them separately —as the previous generation did— was a
/// way for them to drift out of sync with the style without anyone noticing:
/// you changed the style and the labels kept requesting the old one's glyphs.
///
/// They're exposed anyway in [tileUrlTemplate], [glyphsUrlTemplate] and
/// [spritesUrl] for anyone building their own renderer or wanting to preload
/// tiles, but they're not the normal path.
class MapsClient {
  /// Builds the client. Internal use: it comes already set up in `NativMaps`.
  @internal
  MapsClient({
    required AlsTransport transport,
    required this.region,
    this.politicalView,
  }) : _transport = transport;

  final AlsTransport _transport;

  /// AWS region.
  final String region;

  /// Political view for disputed borders, in ISO 3166.
  final String? politicalView;

  static const AlsService _service = AlsService.maps;

  /// The Maps host for this region.
  String get host => _service.hostFor(region);

  // ─── GetStyleDescriptor ───────────────────────────────────────────────

  /// The style descriptor URL, which is what MapLibre consumes.
  ///
  /// ```dart
  /// NativMap(
  ///   styleUrl: maps.styleDescriptorUrl(
  ///     MapStyle.standard,
  ///     colorScheme: MapColorScheme.dark,
  ///     traffic: MapTraffic.congestion,
  ///   ),
  ///   ...
  /// )
  /// ```
  ///
  /// ## Dark mode is rendered by the server
  ///
  /// [colorScheme] is not a filter over light tiles: the service generates the
  /// whole dark style. That's why the labels stay readable, which doesn't
  /// happen when you invert the colors of a light map — which is what you have
  /// to do with `google_maps_flutter`.
  ///
  /// ## What Google doesn't give you, and here is a parameter
  ///
  /// [traffic], [terrain], [buildings], [contourDensity], [poiDensity],
  /// [poiCategories] and [travelModes] are drawn by the server **inside the
  /// same style**, with no second request and no overlay layer. [poiDensity]
  /// set to [MapPoiDensity.off] is what you want when the map is the backdrop
  /// for your own data and the points of interest just get in the way.
  ///
  /// **The URL carries the key inside** on the API key path. Don't log it or
  /// show it on screen.
  ///
  /// Returns `null` if no credentials are configured, instead of throwing:
  /// this gets called from `build()`, and an exception there doesn't degrade
  /// the screen, it prevents it from opening.
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
      // Each category goes as a repeated parameter, not comma-separated.
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

  /// The pair of style URLs for switching between day and night.
  ///
  /// In the previous generation this required **two separate resources**
  /// created by hand in the console (`MyMap` and `MyMapDark`) that had to be
  /// kept in sync: changing one and forgetting the other left the app with two
  /// maps that didn't look alike. Now it's the same style with a different
  /// parameter.
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

  /// An already rendered map image. `GET /v2/static/map`.
  ///
  /// AWS returns it as **PNG** (verified against the service, 2026-10-19); the
  /// format it actually sends in each response is in `AlsBytes.contentType`.
  ///
  /// **The server draws it**, so it works where there's no widget: the
  /// thumbnail of a push notification, the map in a PDF, the image in an
  /// email, the preview in a list. `google_maps_flutter` solves this with
  /// `takeSnapshot`, which requires the map to be mounted and visible on
  /// screen.
  ///
  /// There are three ways to frame it, **mutually exclusive**:
  ///
  /// - [center] with [zoom] or with [radiusMeters] —one of the two, not
  ///   both—: the classic framing;
  /// - [boundingBox]: the rectangle that has to be visible;
  /// - [boundedPositions]: the points that have to fit, and the service
  ///   computes the framing. It's the most convenient one for drawing a route.
  ///
  /// [geoJsonOverlay] draws geometry on top: the route line, the markers, the
  /// polygon of an isoline. It's what turns this into a useful thumbnail and
  /// not an empty map.
  ///
  /// [width] and [height] range from 64 to 1400 pixels, and [style] only
  /// accepts [MapStyle.standard] and [MapStyle.satellite]. Outside of that it
  /// throws `ArgumentError` before sending.
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
      path: _staticMapPath,
      queryParameters: query,
    );
  }

  /// The static map URL, without downloading it.
  ///
  /// It's for passing to an `Image.network` or to an email template. In
  /// exchange, **the URL carries the key inside** on the API key path: you
  /// can't send it to a third party or write it to a log. That's what
  /// [staticMap] is for: it downloads the bytes and exposes nothing.
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
      path: '${_trimSlash(base.path)}$_staticMapPath',
      queryParameters: query,
    );
    return _withApiKey(uri).toString();
  }

  /// `map` is the file name the service requires; `map@2x` doubles the
  /// density. With `/v2/static-map` the gateway responds 403 "Missing
  /// Authentication Token", which is misleading: nothing is missing, the path
  /// doesn't exist.
  static const String _staticMapPath = '/v2/static/map';

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
        'staticMap necesita un encuadre: center (con zoom o radiusMeters), '
        'boundingBox o boundedPositions.',
      );
    }
    if (framings.length > 1) {
      throw ArgumentError(
        'center, boundingBox y boundedPositions son excluyentes; llegaron '
        '${framings.join(', ')}. La API responde 400 con más de uno.',
      );
    }
    if (zoom != null && radiusMeters != null) {
      throw ArgumentError('zoom y radiusMeters son excluyentes.');
    }
    if (center != null && zoom == null && radiusMeters == null) {
      throw ArgumentError('center necesita zoom o radiusMeters.');
    }
    if (width < 64 || width > 1400 || height < 64 || height > 1400) {
      throw ArgumentError(
        'width y height admiten entre 64 y 1400 píxeles; llegaron '
        '${width}x$height.',
      );
    }
    if (style != MapStyle.standard && style != MapStyle.satellite) {
      throw ArgumentError.value(
        style,
        'style',
        'el mapa estático solo admite standard y satellite',
      );
    }

    // The parameter names don't follow the API's camelCase ones: `lang`,
    // `pois` and `scale-unit`. A name the service doesn't know raises no
    // error — it's silently ignored and the image comes out without the
    // setting.
    return <String, String>{
      'width': '$width',
      'height': '$height',
      'style': style.wireName,
      if (center != null) 'center': _lonLatParam(center),
      if (zoom != null) 'zoom': _trimNumber(zoom),
      // (the two above transform the value, so `?` doesn't apply)
      if (boundingBox != null)
        'bounding-box': boundingBox.toBbox().map(_trimNumber).join(','),
      if (boundedPositions.isNotEmpty)
        'bounded-positions': boundedPositions.map(_lonLatParam).join(','),
      if (radiusMeters != null) 'radius': '${radiusMeters.round()}',
      if (colorScheme != null) 'color-scheme': colorScheme.wireName,
      'geojson-overlay': ?geoJsonOverlay,
      if (paddingPixels != null) 'padding': '${paddingPixels.round()}',
      if (scaleBarUnit != null) 'scale-unit': scaleBarUnit.wireName,
      if (cropLabels != null) 'crop-labels': '$cropLabels',
      if (pointsOfInterest != null)
        'pois': pointsOfInterest ? 'Enabled' : 'Disabled',
      'lang': ?language,
      if ((politicalView ?? this.politicalView) != null)
        'political-view': politicalView ?? this.politicalView!,
    };
  }

  // ─── Tiles, glyphs, sprites ───────────────────────────────────────────

  /// The tile URL template, with `{z}`, `{x}` and `{y}` left unsubstituted.
  ///
  /// **You don't need it to draw a map**: the style descriptor already carries
  /// it and MapLibre follows it on its own. It's here for anyone building
  /// their own renderer or wanting to preload an area by hand.
  ///
  /// [tileset] is usually `vector.basemap`, `raster.satellite` or whichever
  /// the style indicates.
  String? tileUrlTemplate(String tileset) {
    if (!_transport.credentials.isConfigured) return null;
    final base = _transport.credentials.baseUri(_service, region);
    final uri = base.replace(
      path: '${_trimSlash(base.path)}/v2/tiles/$tileset/{z}/{x}/{y}',
    );
    return _keepPlaceholders(_withApiKey(uri).toString());
  }

  /// The glyphs URL template, with `{fontstack}` and `{range}`.
  ///
  /// Same as [tileUrlTemplate]: the style already carries it. It goes
  /// **without the key**, as in the style itself: `GetGlyphs` is public.
  String? glyphsUrlTemplate() {
    if (!_transport.credentials.isConfigured) return null;
    final base = _transport.credentials.baseUri(_service, region);
    final uri = base.replace(
      path: '${_trimSlash(base.path)}/v2/glyphs/{fontstack}/{range}.pbf',
    );
    return _keepPlaceholders(uri.toString());
  }

  /// The URL of a style's sprites, in the form MapLibre's `sprite` property
  /// expects: **without an extension**.
  ///
  /// MapLibre appends `.json` and `.png`, or `@2x.json` and `@2x.png` on
  /// high-density screens. They depend on the style and the color scheme: the
  /// dark mode icons are not the light mode ones.
  ///
  /// It goes **without the key**: `GetSprites` is public, and a `?key=` at the
  /// end would end up in front of the extension MapLibre appends.
  String? spritesUrl(
    MapStyle style, {
    MapColorScheme colorScheme = MapColorScheme.light,
  }) {
    if (!_transport.credentials.isConfigured) return null;
    final base = _transport.credentials.baseUri(_service, region);
    return base
        .replace(
          path:
              '${_trimSlash(base.path)}/v2/styles/${style.wireName}/'
              '${colorScheme.wireName}/Default/sprites/sprites',
        )
        .toString();
  }

  // ─── Helpers ──────────────────────────────────────────────────────────

  /// Adds the key to the URL when the credentials are an API key.
  ///
  /// It can't go through `credentials.sign` because that works on an
  /// `http.BaseRequest`, and what's produced here is a URL that gets handed
  /// to MapLibre for it to request. It's the only boundary in the package
  /// where the key goes out in plain text, which is why the method that uses
  /// it documents that the URL must not be logged.
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

  /// Returns a template's braces to their literal form.
  ///
  /// `Uri` encodes them as `%7B` and `%7D`, and then neither MapLibre nor a
  /// `replaceAll('{z}', …)` can find them: the request goes out with `{z}` as
  /// text and AWS rejects it.
  static String _keepPlaceholders(String url) =>
      url.replaceAll('%7B', '{').replaceAll('%7D', '}');

  static String _lonLatParam(LatLng point) =>
      '${_trimNumber(point.longitude)},${_trimNumber(point.latitude)}';

  /// Writes a number without scientific notation and without trailing
  /// decimals.
  ///
  /// `Uri` doesn't do it: a `1e-7` in the query string causes a `400` because
  /// the service doesn't interpret it as a number.
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
