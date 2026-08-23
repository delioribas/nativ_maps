// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:async';
import 'dart:math' show Point;

import 'package:compass_maps/compass_maps.dart';
import 'package:compass_maps_flutter/src/controller.dart';
import 'package:compass_maps_flutter/src/internal/layers.dart';
import 'package:compass_maps_flutter/src/offline/offline_manager.dart';
import 'package:compass_maps_flutter/src/types/camera.dart';
import 'package:compass_maps_flutter/src/types/overlays.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

/// El widget del mapa.
///
/// ```dart
/// CompassMap(
///   styleUrl: maps.maps.styleDescriptorUrl(MapStyle.standard)!,
///   initialCameraPosition: CameraPosition(
///     target: LatLng(-0.1807, -78.4678),
///     zoom: 13,
///   ),
///   onMapCreated: (controller) => _controller = controller,
///   onTap: (posicion) => print('tocado en $posicion'),
/// )
/// ```
///
/// ## Qué hace distinto de `google_maps_flutter`
///
/// **Las superposiciones van por el controlador, no por parámetros.** En
/// Google se pasa `markers: {…}` al widget y cada cambio reconstruye el árbol.
/// Aquí se llama a `controller.addMarker(...)`, y el widget no se reconstruye
/// para mover un vehículo. Con doscientos vehículos actualizándose cada pocos
/// segundos, la diferencia se ve.
///
/// Quien prefiera el estilo declarativo de Google lo tiene en el paquete
/// `compass_maps_google`, que añade los parámetros `markers:`, `polylines:` y
/// compañía como extensión.
class CompassMap extends StatefulWidget {
  /// Crea el mapa.
  const CompassMap({
    required this.styleUrl,
    required this.initialCameraPosition,
    super.key,
    this.onMapCreated,
    this.onStyleLoaded,
    this.onStyleError,
    this.onTap,
    this.onLongPress,
    this.onMarkerTap,
    this.onClusterTap,
    this.onPolylineTap,
    this.onCameraMove,
    this.onCameraIdle,
    this.myLocationEnabled = false,
    this.myLocationTracking = MyLocationTracking.none,
    this.compassEnabled = true,
    this.zoomControlsEnabled = false,
    this.scaleBarEnabled = false,
    this.attributionEnabled = true,
    this.rotateGesturesEnabled = true,
    this.scrollGesturesEnabled = true,
    this.zoomGesturesEnabled = true,
    this.tiltGesturesEnabled = true,
    this.minMaxZoomPreference = MinMaxZoomPreference.unbounded,
    this.cameraTargetBounds,
    this.offlineEnabled = false,
    this.customHeaders,
    this.padding = EdgeInsets.zero,
    this.styleLoadTimeout = const Duration(seconds: 20),
  });

  /// La URL del descriptor de estilo.
  ///
  /// Sale de `MapsClient.styleDescriptorUrl`. Cambiarla en caliente cambia el
  /// estilo del mapa y reinstala las superposiciones, así que alternar entre
  /// claro y oscuro es cambiar esta propiedad.
  final String styleUrl;

  /// Dónde empieza la cámara.
  ///
  /// Solo se lee al crear el mapa. Para moverlo después está el controlador.
  final CameraPosition initialCameraPosition;

  /// Se llama una vez, con el controlador ya listo.
  final void Function(CompassMapController controller)? onMapCreated;

  /// Se llama cada vez que termina de cargar un estilo.
  ///
  /// También en los cambios de estilo, no solo en el primero.
  final VoidCallback? onStyleLoaded;

  /// Se llama si el estilo no carga en [styleLoadTimeout].
  ///
  /// **Merece la pena engancharlo.** El estilo no carga por tres motivos, y
  /// los tres son de configuración: clave inválida, región equivocada o sin
  /// red. Sin esto, el usuario ve un rectángulo gris sin ninguna explicación.
  final void Function(Object error)? onStyleError;

  /// Se llama al tocar el mapa, en cualquier sitio.
  final void Function(LatLng position)? onTap;

  /// Se llama al mantener pulsado.
  final void Function(LatLng position)? onLongPress;

  /// Se llama al tocar un marcador.
  ///
  /// Tiene prioridad sobre [onTap]: si el toque cae en un marcador, [onTap]
  /// **no** se llama. Es lo que espera quien viene de Google.
  final void Function(Marker marker)? onMarkerTap;

  /// Se llama al tocar un grupo de marcadores.
  ///
  /// Si no se pasa, el mapa acerca hasta el zoom en el que ese grupo se
  /// separa, que es lo que casi siempre se quiere.
  final void Function(Cluster cluster)? onClusterTap;

  /// Se llama al tocar una polilínea.
  final void Function(Polyline polyline)? onPolylineTap;

  /// Se llama mientras la cámara se mueve.
  ///
  /// Va con antirrebote: en un movimiento continuo llega unas dieciséis veces
  /// por segundo como mucho, no una por fotograma. Sin eso, una operación cara
  /// enganchada aquí bloquea el desplazamiento.
  final void Function(CameraPosition position)? onCameraMove;

  /// Se llama cuando la cámara se para.
  ///
  /// **Es el sitio correcto para pedir datos**: pedir en cada
  /// [onCameraMove] son decenas de peticiones por gesto.
  final VoidCallback? onCameraIdle;

  /// ¿Se enseña el punto azul de la ubicación?
  final bool myLocationEnabled;

  /// Si la cámara sigue a la ubicación, y cómo.
  final MyLocationTracking myLocationTracking;

  /// ¿Se enseña la brújula al girar el mapa?
  final bool compassEnabled;

  /// ¿Se enseñan los botones de más y menos zoom?
  ///
  /// Son widgets de Flutter dibujados encima, no controles nativos: se pueden
  /// sustituir montando los tuyos sobre el mapa en un `Stack`.
  final bool zoomControlsEnabled;

  /// ¿Se enseña la barra de escala?
  final bool scaleBarEnabled;

  /// ¿Se enseña el botón de atribución?
  ///
  /// **Desactivarlo puede incumplir las condiciones del proveedor de datos.**
  /// La atribución es obligatoria y visible; si se quita este botón hay que
  /// enseñarla en otro sitio de la pantalla.
  final bool attributionEnabled;

  /// ¿Se puede girar el mapa?
  final bool rotateGesturesEnabled;

  /// ¿Se puede desplazar?
  final bool scrollGesturesEnabled;

  /// ¿Se puede hacer zoom con los dedos?
  final bool zoomGesturesEnabled;

  /// ¿Se puede inclinar?
  final bool tiltGesturesEnabled;

  /// Los límites de zoom.
  final MinMaxZoomPreference minMaxZoomPreference;

  /// El rectángulo fuera del cual no se puede desplazar el mapa.
  final LatLngBounds? cameraTargetBounds;

  /// ¿Se prepara el gestor de mapas sin conexión?
  ///
  /// Con `false` —el valor por defecto—, `CompassMapController.offline`
  /// devuelve `null`. Se pide explícitamente porque descargar mapas tiene
  /// implicaciones legales que hay que resolver antes; ver
  /// [CompassOfflineManager].
  final bool offlineEnabled;

  /// Cabeceras HTTP propias para las peticiones del mapa.
  ///
  /// Es lo que hace posible autenticar **las teselas** con SigV4 o con un
  /// proxy. Sin esto, el estilo solo se puede autenticar con la clave en la
  /// URL, que es el camino que no debe salir de desarrollo.
  final Map<String, String>? customHeaders;

  /// Margen interior del mapa.
  ///
  /// Desplaza el centro de la cámara y los controles nativos. Sirve para que
  /// una hoja inferior no tape el punto que se acaba de centrar.
  final EdgeInsets padding;

  /// Cuánto se espera a que cargue el estilo antes de llamar a [onStyleError].
  ///
  /// Existe porque el evento de «estilo cargado» **no llega nunca** si el
  /// estilo falla. Sin un límite, todo lo que espera a ese evento se queda
  /// colgado en silencio y la pantalla se queda gris para siempre.
  final Duration styleLoadTimeout;

  @override
  State<CompassMap> createState() => _CompassMapState();
}

/// Si la cámara sigue a la ubicación del usuario, y cómo.
enum MyLocationTracking {
  /// No la sigue.
  none,

  /// La cámara se centra en la ubicación.
  follow,

  /// Se centra y además gira con la brújula del dispositivo.
  followWithHeading,

  /// Se centra y gira con el rumbo del GPS.
  ///
  /// Con el dispositivo en movimiento es más estable que la brújula, que se
  /// desvía cerca de metales y motores.
  followWithBearing,
}

class _CompassMapState extends State<CompassMap> {
  CompassMapController? _controller;
  LayerInstaller? _installer;
  CompassOfflineManager? _offline;

  Completer<void> _styleReady = Completer<void>();
  Timer? _cameraDebounce;
  Marker? _openInfoWindowMarker;
  Offset? _infoWindowOffset;

  @override
  void didUpdateWidget(covariant CompassMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // El estilo se lee en cada reconstrucción, no solo al crear el mapa. Si no,
    // alternar entre claro y oscuro cambiando esta propiedad no haría nada, y
    // esa es precisamente la razón de que `dayNightStyleUrls` exista.
    if (oldWidget.styleUrl != widget.styleUrl && _controller != null) {
      _styleReady = Completer<void>();
      unawaited(
        _controller!.setMapStyle(widget.styleUrl).catchError((Object error) {
          // Un estilo que no carga no debe tumbar la pantalla: el mapa se
          // queda con el anterior, que es lo que el usuario ya estaba viendo.
          widget.onStyleError?.call(error);
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: <Widget>[
      ml.MapLibreMap(
        styleString: widget.styleUrl,
        initialCameraPosition: ml.CameraPosition(
          target: ml.LatLng(
            widget.initialCameraPosition.target.latitude,
            widget.initialCameraPosition.target.longitude,
          ),
          zoom: widget.initialCameraPosition.zoom,
          bearing: widget.initialCameraPosition.bearing,
          tilt: widget.initialCameraPosition.tilt,
        ),
        onMapCreated: _onMapCreated,
        onStyleLoadedCallback: _onStyleLoaded,
        onMapClick: _onMapClick,
        onMapLongClick: _onMapLongClick,
        onCameraIdle: _onCameraIdle,
        onCameraMove: (_) => _onCameraMove(),
        trackCameraPosition: widget.onCameraMove != null,
        myLocationEnabled: widget.myLocationEnabled,
        myLocationTrackingMode: switch (widget.myLocationTracking) {
          MyLocationTracking.none => ml.MyLocationTrackingMode.none,
          MyLocationTracking.follow => ml.MyLocationTrackingMode.tracking,
          MyLocationTracking.followWithHeading =>
            ml.MyLocationTrackingMode.trackingCompass,
          MyLocationTracking.followWithBearing =>
            ml.MyLocationTrackingMode.trackingGps,
        },
        compassEnabled: widget.compassEnabled,
        scaleControlEnabled: widget.scaleBarEnabled,
        rotateGesturesEnabled: widget.rotateGesturesEnabled,
        scrollGesturesEnabled: widget.scrollGesturesEnabled,
        zoomGesturesEnabled: widget.zoomGesturesEnabled,
        tiltGesturesEnabled: widget.tiltGesturesEnabled,
        minMaxZoomPreference: ml.MinMaxZoomPreference(
          widget.minMaxZoomPreference.minZoom,
          widget.minMaxZoomPreference.maxZoom,
        ),
        cameraTargetBounds: widget.cameraTargetBounds == null
            ? ml.CameraTargetBounds.unbounded
            : ml.CameraTargetBounds(
                ml.LatLngBounds(
                  southwest: ml.LatLng(
                    widget.cameraTargetBounds!.southwest.latitude,
                    widget.cameraTargetBounds!.southwest.longitude,
                  ),
                  northeast: ml.LatLng(
                    widget.cameraTargetBounds!.northeast.latitude,
                    widget.cameraTargetBounds!.northeast.longitude,
                  ),
                ),
              ),
      ),
      if (_openInfoWindowMarker != null && _infoWindowOffset != null)
        _buildInfoWindow(context),
      if (widget.zoomControlsEnabled) _buildZoomControls(),
    ],
  );

  // ─── Ciclo de vida ────────────────────────────────────────────────────

  Future<void> _onMapCreated(ml.MapLibreMapController native) async {
    _installer = LayerInstaller(native);

    if (widget.offlineEnabled) {
      _offline = CompassOfflineManager(
        styleUrl: widget.styleUrl,
        controller: native,
      );
    }

    final controller = CompassMapController(
      native: native,
      installer: _installer!,
      ensureStyleReady: _ensureStyleReady,
      onOverlaysChanged: _onOverlaysChanged,
      offline: _offline,
    );
    _controller = controller;

    if (widget.customHeaders != null) {
      await controller.setCustomHeaders(widget.customHeaders!);
    }
    if (widget.padding != EdgeInsets.zero) {
      await native.setPadding(
        top: widget.padding.top,
        left: widget.padding.left,
        bottom: widget.padding.bottom,
        right: widget.padding.right,
      );
    }

    widget.onMapCreated?.call(controller);

    // Arma el vigilante del tiempo de carga: sin esto, un estilo que no carga
    // deja la pantalla gris para siempre y sin explicación.
    unawaited(
      _ensureStyleReady().catchError((Object error) {
        if (mounted) widget.onStyleError?.call(error);
      }),
    );
  }

  Future<void> _onStyleLoaded() async {
    if (!_styleReady.isCompleted) _styleReady.complete();
    // Un cambio de estilo borra todas las capas y fuentes; sin reinstalarlas,
    // pasar a modo oscuro haría desaparecer todos los marcadores.
    await _controller?.reinstallAfterStyleChange();
    if (mounted) widget.onStyleLoaded?.call();
  }

  /// Espera a que el estilo cargue, con límite.
  ///
  /// El evento de estilo cargado **no llega nunca** si el estilo falla —clave
  /// caducada, región equivocada, sin red—, y esas son justo las tres cosas
  /// que más se equivocan la primera vez que se configura. Sin este límite,
  /// todo lo que espera aquí se queda colgado en silencio.
  Future<void> _ensureStyleReady() async {
    if (_styleReady.isCompleted) return;
    await _styleReady.future.timeout(
      widget.styleLoadTimeout,
      onTimeout: () => throw TimeoutException(
        'El estilo del mapa no cargó en '
        '${widget.styleLoadTimeout.inSeconds} s. '
        'Las tres causas, por frecuencia: la clave de Amazon Location no es '
        'válida o caducó, la región no es la de la clave, o no hay red.',
        widget.styleLoadTimeout,
      ),
    );
  }

  /// Se llama tras cada sincronización de superposiciones.
  ///
  /// Solo reconstruye si hay un globo abierto: su posición en pantalla depende
  /// de dónde esté el marcador. Sin globo abierto, `build` no lee ninguna
  /// superposición —se pintan empujando GeoJSON, no reconstruyendo widgets— y
  /// llamar a `setState` sería trabajo tirado.
  void _onOverlaysChanged() {
    if (_openInfoWindowMarker != null && mounted) setState(() {});
  }

  // ─── Gestos ───────────────────────────────────────────────────────────

  Future<void> _onMapClick(Point<double> point, ml.LatLng coordinates) async {
    final controller = _controller;
    if (controller == null) return;
    final screenPoint = Offset(point.x, point.y);

    final cluster = await controller.clusterAt(screenPoint);
    if (cluster != null) {
      if (widget.onClusterTap != null) {
        widget.onClusterTap!(cluster);
      } else {
        // Sin manejador, tocar un grupo lo abre. Es lo que espera cualquiera
        // que haya usado un mapa, y `google_maps_flutter` no puede hacerlo
        // porque agrupa fuera del motor.
        final zoom = await controller.getClusterExpansionZoom(cluster);
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(cluster.position, zoom),
        );
      }
      return;
    }

    final marker = await controller.markerAt(screenPoint);
    if (marker != null) {
      _showInfoWindow(marker, screenPoint);
      marker.onTap?.call();
      widget.onMarkerTap?.call(marker);
      return; // El toque no se propaga: es lo que hace Google.
    }

    if (widget.onPolylineTap != null) {
      final polyline = await controller.polylineAt(screenPoint);
      if (polyline != null) {
        polyline.onTap?.call();
        widget.onPolylineTap!(polyline);
        return;
      }
    }

    _hideInfoWindow();
    widget.onTap?.call(LatLng(coordinates.latitude, coordinates.longitude));
  }

  void _onMapLongClick(Point<double> point, ml.LatLng coordinates) {
    widget.onLongPress?.call(
      LatLng(coordinates.latitude, coordinates.longitude),
    );
  }

  /// Antirrebote del movimiento de cámara.
  ///
  /// El evento nativo llega una vez por fotograma. Sin antirrebote, una
  /// operación cara enganchada a [CompassMap.onCameraMove] convierte un
  /// desplazamiento fluido en uno a tirones.
  void _onCameraMove() {
    if (widget.onCameraMove == null) return;
    _cameraDebounce?.cancel();
    _cameraDebounce = Timer(const Duration(milliseconds: 60), () async {
      if (!mounted) return;
      final position = await _controller?.getCameraPosition();
      if (position != null && mounted) widget.onCameraMove!(position);
      if (_openInfoWindowMarker != null && mounted) {
        await _refreshInfoWindowPosition();
      }
    });
  }

  void _onCameraIdle() {
    widget.onCameraIdle?.call();
    if (_openInfoWindowMarker != null) {
      unawaited(_refreshInfoWindowPosition());
    }
  }

  // ─── Globo de información ─────────────────────────────────────────────

  void _showInfoWindow(Marker marker, Offset at) {
    if (marker.infoWindow.isEmpty) {
      _hideInfoWindow();
      return;
    }
    setState(() {
      _openInfoWindowMarker = marker;
      _infoWindowOffset = at;
    });
  }

  void _hideInfoWindow() {
    if (_openInfoWindowMarker == null) return;
    setState(() {
      _openInfoWindowMarker = null;
      _infoWindowOffset = null;
    });
  }

  Future<void> _refreshInfoWindowPosition() async {
    final marker = _openInfoWindowMarker;
    final controller = _controller;
    if (marker == null || controller == null) return;
    try {
      final offset = await controller.getScreenCoordinate(marker.position);
      if (mounted) setState(() => _infoWindowOffset = offset);
    } on Object {
      // El mapa puede no estar listo. El globo se queda donde estaba.
    }
  }

  Widget _buildInfoWindow(BuildContext context) {
    final marker = _openInfoWindowMarker!;
    final offset = _infoWindowOffset!;
    final info = marker.infoWindow;
    final theme = Theme.of(context);

    final content =
        info.builder?.call(context) ??
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (info.title != null)
              Text(
                info.title!,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (info.snippet != null)
              Text(info.snippet!, style: theme.textTheme.bodySmall),
          ],
        );

    return Positioned(
      // Se resta el ancho a ojo porque el widget aún no está medido; el
      // `FractionalTranslation` lo centra de verdad una vez montado.
      left: offset.dx,
      top: offset.dy,
      child: FractionalTranslation(
        translation: Offset(-info.anchor.dx, -1.0 - info.anchor.dy),
        child: GestureDetector(
          onTap: info.onTap,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            color: theme.colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildZoomControls() => Positioned(
    right: 16,
    bottom: 16 + widget.padding.bottom,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        FloatingActionButton.small(
          heroTag: 'compass-zoom-in-${identityHashCode(this)}',
          onPressed: () => _controller?.animateCamera(CameraUpdate.zoomIn()),
          child: const Icon(Icons.add),
        ),
        const SizedBox(height: 8),
        FloatingActionButton.small(
          heroTag: 'compass-zoom-out-${identityHashCode(this)}',
          onPressed: () => _controller?.animateCamera(CameraUpdate.zoomOut()),
          child: const Icon(Icons.remove),
        ),
      ],
    ),
  );

  @override
  void dispose() {
    _cameraDebounce?.cancel();
    _controller?.dispose();
    super.dispose();
  }
}
