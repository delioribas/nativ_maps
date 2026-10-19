// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'dart:async';
import 'dart:math' show Point;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:nativ_maps/nativ_maps.dart';
import 'package:nativ_maps_flutter/src/controller.dart';
import 'package:nativ_maps_flutter/src/internal/layers.dart';
import 'package:nativ_maps_flutter/src/offline/offline_manager.dart';
import 'package:nativ_maps_flutter/src/types/camera.dart';
import 'package:nativ_maps_flutter/src/types/overlays.dart';

/// The map widget.
///
/// ```dart
/// NativMap(
///   styleUrl: maps.maps.styleDescriptorUrl(MapStyle.standard)!,
///   initialCameraPosition: CameraPosition(
///     target: LatLng(-0.1807, -78.4678),
///     zoom: 13,
///   ),
///   onMapCreated: (controller) => _controller = controller,
///   onTap: (position) => print('tapped at $position'),
/// )
/// ```
///
/// ## What it does differently from `google_maps_flutter`
///
/// **Overlays go through the controller, not through parameters.** In Google
/// you pass `markers: {…}` to the widget and every change rebuilds the tree.
/// Here you call `controller.addMarker(...)`, and the widget doesn't rebuild
/// to move a vehicle. With two hundred vehicles updating every few seconds,
/// the difference shows.
///
/// Anyone who prefers Google's declarative style has it in the
/// `nativ_maps_google` package, which adds the `markers:`, `polylines:` and
/// related parameters as an extension.
class NativMap extends StatefulWidget {
  /// Creates the map.
  const NativMap({
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

  /// The style descriptor URL.
  ///
  /// It comes from `MapsClient.styleDescriptorUrl`. Changing it at runtime
  /// changes the map style and reinstalls the overlays, so switching between
  /// light and dark is just changing this property.
  final String styleUrl;

  /// Where the camera starts.
  ///
  /// It's only read when the map is created. To move it afterwards, use the
  /// controller.
  final CameraPosition initialCameraPosition;

  /// Called once, with the controller ready.
  final void Function(NativMapController controller)? onMapCreated;

  /// Called every time a style finishes loading.
  ///
  /// Also on style changes, not just on the first one.
  final VoidCallback? onStyleLoaded;

  /// Called if the style doesn't load within [styleLoadTimeout].
  ///
  /// **It's worth hooking up.** The style fails to load for three reasons, and
  /// all three are configuration: invalid key, wrong region or no network.
  /// Without this, the user sees a gray rectangle with no explanation at all.
  final void Function(Object error)? onStyleError;

  /// Called on a tap anywhere on the map.
  final void Function(LatLng position)? onTap;

  /// Called on a long press.
  final void Function(LatLng position)? onLongPress;

  /// Called on a tap on a marker.
  ///
  /// It takes priority over [onTap]: if the tap lands on a marker, [onTap] is
  /// **not** called. It's what anyone coming from Google expects.
  final void Function(Marker marker)? onMarkerTap;

  /// Called on a tap on a cluster of markers.
  ///
  /// If it isn't passed, the map zooms in to the level at which that cluster
  /// splits apart, which is what you almost always want.
  final void Function(Cluster cluster)? onClusterTap;

  /// Called on a tap on a polyline.
  final void Function(Polyline polyline)? onPolylineTap;

  /// Called while the camera moves.
  ///
  /// It's debounced: during a continuous move it arrives about sixteen times
  /// per second at most, not once per frame. Without that, an expensive
  /// operation hooked up here blocks panning.
  final void Function(CameraPosition position)? onCameraMove;

  /// Called when the camera stops.
  ///
  /// **It's the right place to fetch data**: fetching on every
  /// [onCameraMove] means dozens of requests per gesture.
  final VoidCallback? onCameraIdle;

  /// Whether the blue location dot is shown.
  final bool myLocationEnabled;

  /// Whether the camera follows the location, and how.
  final MyLocationTracking myLocationTracking;

  /// Whether the compass is shown when the map is rotated.
  final bool compassEnabled;

  /// Whether the zoom in and zoom out buttons are shown.
  ///
  /// They're Flutter widgets drawn on top, not native controls: you can
  /// replace them by mounting your own over the map in a `Stack`.
  final bool zoomControlsEnabled;

  /// Whether the scale bar is shown.
  final bool scaleBarEnabled;

  /// Whether the attribution button is shown.
  ///
  /// **Turning it off may breach the data provider's terms.** Attribution is
  /// mandatory and must be visible; if you remove this button you have to
  /// show it somewhere else on the screen.
  final bool attributionEnabled;

  /// Whether the map can be rotated.
  final bool rotateGesturesEnabled;

  /// Whether it can be panned.
  final bool scrollGesturesEnabled;

  /// Whether it can be zoomed with the fingers.
  final bool zoomGesturesEnabled;

  /// Whether it can be tilted.
  final bool tiltGesturesEnabled;

  /// The zoom limits.
  final MinMaxZoomPreference minMaxZoomPreference;

  /// The rectangle the map can't be panned out of.
  final LatLngBounds? cameraTargetBounds;

  /// Whether the offline map manager is set up.
  ///
  /// With `false` —the default—, `NativMapController.offline` returns `null`.
  /// It has to be requested explicitly because downloading maps has legal
  /// implications that must be settled first; see [NativOfflineManager].
  final bool offlineEnabled;

  /// Custom HTTP headers for the map's requests.
  ///
  /// It's what makes it possible to authenticate **the tiles** with SigV4 or
  /// through a proxy. Without this, the style can only be authenticated with
  /// the key in the URL, which is the path that must not leave development.
  ///
  /// They're sent to the host of [styleUrl] —your proxy, behind one— and to
  /// Amazon Location, and to nothing else. Changing them —a renewed session
  /// token— applies them again.
  ///
  /// Pass them **from the first build** if the style needs them: the map then
  /// starts empty and requests [styleUrl] once they're set. Added later, the
  /// style has already been requested without them.
  final Map<String, String>? customHeaders;

  /// The map's inner padding.
  ///
  /// It shifts the camera center and the native controls. It keeps a bottom
  /// sheet from covering the point that was just centered.
  final EdgeInsets padding;

  /// How long to wait for the style to load before calling [onStyleError].
  ///
  /// It exists because the "style loaded" event **never arrives** if the style
  /// fails. Without a limit, everything waiting on that event hangs silently
  /// and the screen stays gray forever.
  final Duration styleLoadTimeout;

  @override
  State<NativMap> createState() => _NativMapState();
}

/// Whether the camera follows the user's location, and how.
enum MyLocationTracking {
  /// It doesn't follow it.
  none,

  /// The camera centers on the location.
  follow,

  /// It centers and also rotates with the device's compass.
  followWithHeading,

  /// It centers and rotates with the GPS heading.
  ///
  /// With the device moving, it's steadier than the compass, which drifts near
  /// metal and engines.
  followWithBearing,
}

class _NativMapState extends State<NativMap> {
  NativMapController? _controller;
  LayerInstaller? _installer;
  NativOfflineManager? _offline;

  Completer<void> _styleReady = Completer<void>();
  Timer? _cameraDebounce;
  Marker? _openInfoWindowMarker;
  Offset? _infoWindowOffset;
  ml.MapLibreMapController? _native;

  /// Whether the first `onCameraIdle` —the one for the initial camera— has
  /// gone out.
  bool _initialIdleSent = false;

  /// Where the camera was the last time `onCameraIdle` went out.
  CameraPosition? _lastIdle;

  /// The style the native map is created with, fixed for its whole life.
  ///
  /// `maplibre_gl` reloads the style by itself whenever this string changes,
  /// and [didUpdateWidget] already reloads it through the controller: passing
  /// the live [NativMap.styleUrl] here loaded every new style twice. With
  /// [NativMap.customHeaders] it starts as an empty style, see
  /// [_waitingForHeaders].
  late final String _initialStyle = widget.customHeaders == null
      ? widget.styleUrl
      : _emptyStyle;

  /// Whether the real style is still waiting for the headers.
  ///
  /// A native map starts downloading its style the moment it exists, and its
  /// headers can only be set afterwards: the first request always went out
  /// without them, and behind a proxy that's a 401 and a blank map. So the
  /// map starts empty, the headers go in, and only then the real style.
  late bool _waitingForHeaders = widget.customHeaders != null;

  /// The two things the real style waits for: the headers set, and the empty
  /// placeholder done loading. Requesting it while the placeholder is still
  /// loading left the native side halfway through a style switch.
  bool _headersSet = false;
  bool _placeholderLoaded = false;

  static const String _emptyStyle = '{"version":8,"sources":{},"layers":[]}';

  @override
  void didUpdateWidget(covariant NativMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The style is read on every rebuild, not only when the map is created.
    // Otherwise, switching between light and dark by changing this property
    // would do nothing, and that's precisely why `dayNightStyleUrls` exists.
    final hostChanged =
        Uri.tryParse(oldWidget.styleUrl)?.host !=
        Uri.tryParse(widget.styleUrl)?.host;
    if (_controller != null &&
        widget.customHeaders != null &&
        (hostChanged ||
            !mapEquals(oldWidget.customHeaders, widget.customHeaders))) {
      // Before the style reload below, so its requests already carry them.
      unawaited(_applyCustomHeaders());
    }
    // While the real style still waits for its headers, there's nothing to
    // switch: it'll be requested with the current styleUrl.
    if (oldWidget.styleUrl != widget.styleUrl &&
        _controller != null &&
        !_waitingForHeaders) {
      _styleReady = Completer<void>();
      unawaited(
        _controller!.setMapStyle(widget.styleUrl).catchError((Object error) {
          // A style that doesn't load must not bring down the screen: the map
          // keeps the previous one, which is what the user was already seeing.
          widget.onStyleError?.call(error);
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: <Widget>[
      ml.MapLibreMap(
        styleString: _initialStyle,
        // `maplibre_gl` builds four annotation managers —their sources and
        // layers— on every style load, and this package draws with its own
        // layers: they were dead weight, and they raced a style switch.
        annotationOrder: const <ml.AnnotationType>[],
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
        // Without this, a tap on an interactive layer —one the app adds with
        // `style`, for example— doesn't reach `onMapClick`, and with it
        // `onMarkerTap`, the info windows and `onTap` are lost. The package's
        // layers are no longer interactive; this covers the rest.
        featureTapsTriggersMapClick: true,
        onMapLongClick: _onMapLongClick,
        onCameraIdle: () => unawaited(_onCameraIdle()),
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

  // ─── Lifecycle ───────────────────────────────────────────────────────

  Future<void> _onMapCreated(ml.MapLibreMapController native) async {
    _installer = LayerInstaller(native);
    _native = native;
    native.onFeatureDrag.add(_onFeatureDrag);

    if (widget.offlineEnabled) {
      _offline = NativOfflineManager(
        styleUrl: widget.styleUrl,
        controller: native,
      );
    }

    final controller = NativMapController(
      native: native,
      installer: _installer!,
      ensureStyleReady: _ensureStyleReady,
      onOverlaysChanged: _onOverlaysChanged,
      offline: _offline,
    );
    controller.nativePixelRatio = _nativePixelRatio;
    _controller = controller;

    if (widget.customHeaders != null) await _applyCustomHeaders();
    _headersSet = true;
    await _loadRealStyleWhenReady();
    if (widget.padding != EdgeInsets.zero) {
      await native.setPadding(
        top: widget.padding.top,
        left: widget.padding.left,
        bottom: widget.padding.bottom,
        right: widget.padding.right,
      );
    }

    widget.onMapCreated?.call(controller);

    // Arms the load-time watchdog: without this, a style that doesn't load
    // leaves the screen gray forever, with no explanation.
    unawaited(
      _ensureStyleReady().catchError((Object error) {
        if (mounted) widget.onStyleError?.call(error);
      }),
    );
  }

  /// Requests the real style once the headers are set and the placeholder
  /// has loaded, whichever happens last. The next "style loaded" is then
  /// always the real one.
  Future<void> _loadRealStyleWhenReady() async {
    if (!_waitingForHeaders || !_headersSet || !_placeholderLoaded) return;
    _waitingForHeaders = false;
    await _native?.setStyle(widget.styleUrl);
  }

  /// The headers go to the style's host —a proxy, behind one— and to Amazon
  /// Location. Only to `amazonaws.com`, a proxy would never get its token.
  Future<void> _applyCustomHeaders() async {
    final headers = widget.customHeaders;
    final controller = _controller;
    if (headers == null || controller == null) return;
    await controller.setCustomHeaders(
      headers,
      urlFilter: <String>[
        ?Uri.tryParse(widget.styleUrl)?.host,
        'amazonaws.com',
      ],
    );
  }

  Future<void> _onStyleLoaded() async {
    // The empty placeholder style isn't the app's: nothing to report, but
    // it's one of the two things the real style waits for.
    if (_waitingForHeaders) {
      _placeholderLoaded = true;
      await _loadRealStyleWhenReady();
      return;
    }
    if (!_styleReady.isCompleted) _styleReady.complete();
    // A style change deletes every layer and source; without reinstalling
    // them, switching to dark mode would make every marker disappear.
    await _controller?.reinstallAfterStyleChange();
    if (mounted) widget.onStyleLoaded?.call();
    // The native side doesn't send an idle for the initial camera, and
    // `google_maps_flutter` does: a "pick a location" pin waits for it to look
    // up the first address. It goes out once, when there's a map to ask.
    if (!_initialIdleSent && mounted) {
      _initialIdleSent = true;
      await _onCameraIdle();
    }
  }

  /// Waits for the style to load, with a time limit.
  ///
  /// The style-loaded event **never arrives** if the style fails —expired key,
  /// wrong region, no network—, and those are exactly the three things most
  /// often gotten wrong the first time it's configured. Without this limit,
  /// everything waiting here hangs silently.
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

  /// Called after every overlay sync.
  ///
  /// It only rebuilds if there's an open info window: its position on screen
  /// depends on where the marker is. Without an open info window, `build`
  /// reads no overlay at all —they're painted by pushing GeoJSON, not by
  /// rebuilding widgets— and calling `setState` would be wasted work.
  void _onOverlaysChanged() {
    final open = _openInfoWindowMarker;
    if (open == null || !mounted) return;
    // The marker of an open info window may have been removed, hidden or
    // moved. Removed or hidden, the window closes, as in Google: before, it
    // stayed on screen pointing at nothing.
    final current = _controller?.markerById(open.markerId);
    if (current == null || !current.visible) {
      _hideInfoWindow();
      return;
    }
    if (!identical(current, open)) {
      setState(() => _openInfoWindowMarker = current);
      unawaited(_refreshInfoWindowPosition());
      return;
    }
    setState(() {});
  }

  /// Engine pixels per logical pixel: the pixel density on Android, where
  /// `maplibre_gl` speaks in physical pixels, and 1 on iOS and on the web.
  double get _nativePixelRatio =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? MediaQuery.devicePixelRatioOf(context)
      : 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller?.nativePixelRatio = _nativePixelRatio;
  }

  // ─── Gestures ────────────────────────────────────────────────────────

  Future<void> _onMapClick(Point<double> point, ml.LatLng coordinates) async {
    final controller = _controller;
    if (controller == null) return;
    // In engine units, which is what `queryRenderedFeatures` expects for the
    // hit-test. The info window, being a Flutter widget, is placed in logical
    // pixels: on Android you have to divide by the pixel density, or it ends
    // up off the screen.
    final screenPoint = Offset(point.x, point.y);
    final logicalPoint = screenPoint / controller.nativePixelRatio;

    final cluster = await controller.clusterAt(screenPoint);
    if (cluster != null) {
      if (widget.onClusterTap != null) {
        widget.onClusterTap!(cluster);
      } else {
        // Without a handler, tapping a cluster opens it. It's what anyone who
        // has used a map expects, and `google_maps_flutter` can't do it
        // because it clusters outside the engine.
        final zoom = await controller.getClusterExpansionZoom(cluster);
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(cluster.position, zoom),
        );
      }
      return;
    }

    final marker = await controller.markerAt(screenPoint);
    if (marker != null) {
      _showInfoWindow(marker, logicalPoint);
      marker.onTap?.call();
      widget.onMarkerTap?.call(marker);
      return; // The tap doesn't propagate: that's what Google does.
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

  /// Debounce for the camera movement.
  ///
  /// The native event arrives once per frame. Without a debounce, an expensive
  /// operation hooked up to [NativMap.onCameraMove] turns smooth panning into
  /// stuttering.
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

  Future<void> _onCameraIdle() async {
    final controller = _controller;
    // Before there's a controller and a style, there's no camera anyone can
    // ask about; the initial idle is sent from `_onStyleLoaded` instead.
    if (controller == null || !_styleReady.isCompleted) return;

    // A debounced move still pending would land *after* this idle and leave
    // the app believing the camera is still moving. It's dropped, and the
    // resting position goes out as the last move, before the idle.
    final movePending = _cameraDebounce?.isActive ?? false;
    _cameraDebounce?.cancel();

    final position = await controller.getCameraPosition();
    if (!mounted) return;
    // One idle per resting place: the native side sometimes reports the same
    // stop twice, and every idle tends to trigger a billed request.
    if (position != null && _sameCamera(position, _lastIdle)) return;
    _lastIdle = position;

    if (movePending && position != null) widget.onCameraMove?.call(position);
    widget.onCameraIdle?.call();
    if (_openInfoWindowMarker != null) {
      unawaited(_refreshInfoWindowPosition());
    }
  }

  static bool _sameCamera(CameraPosition a, CameraPosition? b) =>
      b != null &&
      (a.target.latitude - b.target.latitude).abs() < 1e-9 &&
      (a.target.longitude - b.target.longitude).abs() < 1e-9 &&
      (a.zoom - b.zoom).abs() < 1e-6 &&
      (a.bearing - b.bearing).abs() < 1e-6 &&
      (a.tilt - b.tilt).abs() < 1e-6;

  void _onFeatureDrag(
    Point<double> point,
    ml.LatLng origin,
    ml.LatLng current,
    ml.LatLng delta,
    String id,
    ml.Annotation? annotation,
    ml.DragEventType eventType,
  ) {
    // An info window doesn't follow its marker while it's dragged; it's
    // closed, as Google does.
    if (eventType == ml.DragEventType.start) _hideInfoWindow();
    unawaited(
      _controller?.handleMarkerDrag(
        id,
        LatLng(current.latitude, current.longitude),
        eventType,
      ),
    );
  }

  // ─── Info window ─────────────────────────────────────────────────────

  void _showInfoWindow(Marker marker, Offset at) {
    if (marker.infoWindow.isEmpty) {
      _hideInfoWindow();
      return;
    }
    setState(() {
      _openInfoWindowMarker = marker;
      _infoWindowOffset = at;
    });
    // It opens where the finger tapped, which is instant, and right away it
    // anchors to the marker's position: otherwise, the info window covers the
    // icon itself.
    unawaited(_refreshInfoWindowPosition());
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
      // The map may not be ready. The info window stays where it was.
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
      // The width is subtracted by eye because the widget isn't measured yet;
      // the `FractionalTranslation` truly centers it once mounted.
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
          heroTag: 'nativ-zoom-in-${identityHashCode(this)}',
          onPressed: () => _controller?.animateCamera(CameraUpdate.zoomIn()),
          child: const Icon(Icons.add),
        ),
        const SizedBox(height: 8),
        FloatingActionButton.small(
          heroTag: 'nativ-zoom-out-${identityHashCode(this)}',
          onPressed: () => _controller?.animateCamera(CameraUpdate.zoomOut()),
          child: const Icon(Icons.remove),
        ),
      ],
    ),
  );

  @override
  void dispose() {
    _cameraDebounce?.cancel();
    _native?.onFeatureDrag.remove(_onFeatureDrag);
    _controller?.dispose();
    super.dispose();
  }
}
