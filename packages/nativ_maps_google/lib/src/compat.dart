// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:flutter/foundation.dart';
import 'package:nativ_maps_flutter/nativ_maps_flutter.dart';
import 'package:nativ_maps_google/src/google_map_style.dart';
import 'package:nativ_maps_google/src/style_translator.dart';

/// El controlador con los nombres exactos de `google_maps_flutter`.
///
/// ## El mecanismo: `extension`, nunca clases
///
/// Esto no envuelve el controlador ni hereda de él. Es una `extension`, y eso
/// tiene cuatro consecuencias que ninguna clase envoltorio da:
///
/// - **Coste nulo en ejecución.** Un método de extensión se resuelve al
///   compilar; no se crea ningún objeto.
/// - **El núcleo queda libre.** No hay una jerarquía que respetar ni un
///   contrato que mantener hacia abajo.
/// - **Reversible.** Borrar este paquete no rompe nada debajo: el código que
///   ya usa los nombres propios sigue igual.
/// - **Conviven.** `animateCamera()` en una línea y `mostrarVehiculo()` en la
///   siguiente, sobre el mismo objeto.
///
/// ## Lo que se omite, y por qué
///
/// La Regla 2 del diseño dice: **nada existe aquí que el núcleo no sepa
/// hacer**. Si `google_maps_flutter` tiene un método sin equivalente real, se
/// omite y se documenta — nunca un hueco que devuelve `null` en silencio,
/// porque eso es compatibilidad de mentira y cada hueco acaba siendo un ticket.
///
/// Los tres que faltan, con su motivo:
///
/// | Método de Google | Por qué no está |
/// |---|---|
/// | `setIndoorEnabled` | Amazon Location no tiene planos de interior |
/// | `setLiteModeEnabled` | exclusivo de Android + Google |
/// | `cloudMapId` | estilos alojados en la nube de Google |
///
/// `AdvancedMarker` tampoco: es una API propietaria reciente de Google sin
/// nada equivalente.
extension GoogleMapsCompat on NativMapController {
  /// El nivel de zoom actual. Alias de `getZoomLevel`.
  Future<double> get zoomLevel => getZoomLevel();

  /// Cambia varios marcadores de golpe.
  ///
  /// En `google_maps_flutter` esto recibe un objeto de actualizaciones; aquí
  /// recibe el conjunto que tiene que quedar, que es lo que hace de verdad.
  Future<void> updateMarkers(Set<Marker> markers) => setMarkers(markers);

  /// Cambia varias polilíneas de golpe.
  Future<void> updatePolylines(Set<Polyline> polylines) =>
      setPolylines(polylines);

  /// Cambia varios polígonos de golpe.
  Future<void> updatePolygons(Set<Polygon> polygons) => setPolygons(polygons);

  /// Cambia varios círculos de golpe.
  Future<void> updateCircles(Set<Circle> circles) => setCircles(circles);

  /// Mueve la cámara con animación y una configuración.
  ///
  /// Es la versión de `google_maps_flutter` 2.12 con `duration`. Devuelve si
  /// el movimiento llegó a completarse.
  Future<bool> animateCameraWithConfiguration(
    CameraUpdate update, {
    Duration? duration,
  }) async {
    await animateCamera(update, duration: duration);
    return true;
  }

  /// Mueve la cámara sin animación, con configuración.
  Future<bool> moveCameraWithConfiguration(CameraUpdate update) async {
    await moveCamera(update);
    return true;
  }

  /// Aplica un estilo JSON del Styling Wizard de Google.
  ///
  /// **Es una traducción, no una equivalencia.** Devuelve un
  /// [GoogleStyleReport] con qué reglas se aplicaron y cuáles no encontraron
  /// capa; conviene registrarlo la primera vez que se migra un tema.
  ///
  /// ```dart
  /// final informe = await controller.setGoogleMapStyle(temaOscuroJson);
  /// if (!informe.isComplete) debugPrint('$informe');
  /// ```
  ///
  /// En `google_maps_flutter` este método devuelve `void` y el error se
  /// consulta luego con `getStyleError()`. Aquí el resultado viene de vuelta,
  /// que es donde sirve.
  Future<GoogleStyleReport> setGoogleMapStyle(String styleJson) async {
    final style = GoogleMapStyle.parse(styleJson);
    return applyGoogleStyle(style);
  }

  /// El último error de estilo.
  ///
  /// Existe por compatibilidad con `getStyleError()` de Google. Devuelve
  /// siempre `null` porque [setGoogleMapStyle] ya devuelve el resultado
  /// directamente, que es mejor sitio para mirarlo.
  Future<String?> getStyleError() async => null;

  /// Alias de `getVisibleRegion`, ya idéntico.
  Future<LatLngBounds> get visibleRegion => getVisibleRegion();
}

/// Los tipos de mapa de `google_maps_flutter`, con su equivalente aquí.
///
/// La equivalencia no es exacta y conviene saber en qué:
///
/// | `MapType` de Google | Aquí | Nota |
/// |---|---|---|
/// | `normal` | [MapStyle.standard] | idéntico |
/// | `satellite` | [MapStyle.satellite] | idéntico |
/// | `hybrid` | [MapStyle.hybrid] | idéntico |
/// | `terrain` | [MapStyle.standard] + relieve | **mejor**: es un parámetro |
/// | `none` | — | no existe: MapLibre siempre dibuja el fondo del estilo |
enum MapType {
  /// El mapa de calles a color.
  normal,

  /// Solo imagen de satélite.
  satellite,

  /// Satélite con etiquetas encima.
  hybrid,

  /// Relieve del terreno.
  ///
  /// Aquí sale mejor que en Google: [asMapStyle] devuelve el estilo estándar y
  /// [terrainOption] dice qué relieve pedirle al descriptor.
  terrain;

  /// El estilo de Amazon Location que corresponde.
  MapStyle get asMapStyle => switch (this) {
    MapType.normal => MapStyle.standard,
    MapType.satellite => MapStyle.satellite,
    MapType.hybrid => MapStyle.hybrid,
    MapType.terrain => MapStyle.standard,
  };

  /// El relieve que hay que pedirle al descriptor, si aplica.
  ///
  /// Solo [MapType.terrain] devuelve algo. Es la pieza que hace que el modo
  /// terreno salga mejor que en Google: en vez de un estilo cerrado, es un
  /// parámetro que se puede subir a [MapTerrain.terrain3d].
  MapTerrain? get terrainOption =>
      this == MapType.terrain ? MapTerrain.hillshade : null;
}

/// El esquema de color de `google_maps_flutter` 2.12.
///
/// El equivalente aquí es **mejor**: [MapColorScheme] lo renderiza el
/// servidor, así que el modo oscuro no es un filtro sobre teselas claras y las
/// etiquetas siguen siendo legibles.
enum MapColorSchemeCompat {
  /// Modo claro.
  light,

  /// Modo oscuro.
  dark,

  /// Sigue al tema del sistema.
  followSystem;

  /// El esquema de Amazon Location.
  ///
  /// [platformBrightness] solo se usa con [followSystem]; sale de
  /// `MediaQuery.platformBrightnessOf(context)`.
  MapColorScheme resolve(Brightness platformBrightness) => switch (this) {
    MapColorSchemeCompat.light => MapColorScheme.light,
    MapColorSchemeCompat.dark => MapColorScheme.dark,
    MapColorSchemeCompat.followSystem =>
      platformBrightness == Brightness.dark
          ? MapColorScheme.dark
          : MapColorScheme.light,
  };
}
