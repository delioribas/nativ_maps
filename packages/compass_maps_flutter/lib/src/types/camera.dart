// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:compass_maps/compass_maps.dart';
import 'package:flutter/foundation.dart';

/// Dónde está la cámara del mapa.
///
/// Mismo nombre y mismos campos que en `google_maps_flutter`, con una
/// diferencia de vocabulario que conviene conocer: lo que Google llama [tilt],
/// MapLibre lo llama *pitch*. Aquí se llama `tilt` porque el objetivo es que
/// el código que viene de Google compile sin tocarlo.
@immutable
class CameraPosition {
  /// Crea la posición de cámara.
  const CameraPosition({
    required this.target,
    this.zoom = 0.0,
    this.bearing = 0.0,
    this.tilt = 0.0,
  });

  /// El punto que queda en el centro de la pantalla.
  final LatLng target;

  /// El nivel de acercamiento. 0 es el mundo entero; 20, un portal.
  final double zoom;

  /// Hacia dónde apunta el norte, en grados en el sentido de las agujas.
  final double bearing;

  /// La inclinación en grados. 0 es cenital; 60, casi a ras.
  final double tilt;

  /// Copia con algún campo cambiado.
  CameraPosition copyWith({
    LatLng? target,
    double? zoom,
    double? bearing,
    double? tilt,
  }) => CameraPosition(
    target: target ?? this.target,
    zoom: zoom ?? this.zoom,
    bearing: bearing ?? this.bearing,
    tilt: tilt ?? this.tilt,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraPosition &&
          target == other.target &&
          zoom == other.zoom &&
          bearing == other.bearing &&
          tilt == other.tilt;

  @override
  int get hashCode => Object.hash(target, zoom, bearing, tilt);

  @override
  String toString() =>
      'CameraPosition($target, zoom: $zoom, bearing: $bearing, tilt: $tilt)';
}

/// Qué clase de movimiento de cámara es.
enum _CameraUpdateKind {
  newCameraPosition,
  newLatLng,
  newLatLngBounds,
  newLatLngZoom,
  scrollBy,
  zoomBy,
  zoomIn,
  zoomOut,
  zoomTo,
  bearingTo,
  tiltTo,
}

/// Una orden de movimiento de cámara.
///
/// Las **nueve fábricas de `google_maps_flutter` están todas**, con el mismo
/// nombre y la misma firma, más `bearingTo` y `tiltTo`, que Google no tiene.
///
/// ```dart
/// controller.animateCamera(CameraUpdate.newLatLngZoom(posicion, 16));
/// controller.moveCamera(CameraUpdate.newLatLngBounds(ruta.bounds!, 48));
/// ```
///
/// Es un valor inerte: describir un movimiento no lo ejecuta y no toca el
/// mapa. Lo aplica el controlador.
@immutable
class CameraUpdate {
  const CameraUpdate._(
    this._kind, {
    this.position,
    this.target,
    this.bounds,
    this.zoom,
    this.padding,
    this.dx,
    this.dy,
    this.bearing,
    this.tilt,
  });

  /// Lleva la cámara a una posición completa.
  factory CameraUpdate.newCameraPosition(CameraPosition position) =>
      CameraUpdate._(_CameraUpdateKind.newCameraPosition, position: position);

  /// Centra en un punto, conservando el zoom.
  factory CameraUpdate.newLatLng(LatLng target) =>
      CameraUpdate._(_CameraUpdateKind.newLatLng, target: target);

  /// Encuadra un rectángulo con [padding] píxeles de margen.
  ///
  /// Es la fábrica que conviene usar para enseñar una ruta entera o todos los
  /// vehículos a la vez: elegir el zoom a mano da encuadres que se salen por
  /// los bordes en unas pantallas y sobran en otras.
  factory CameraUpdate.newLatLngBounds(
    LatLngBounds bounds, [
    double padding = 32,
  ]) => CameraUpdate._(
    _CameraUpdateKind.newLatLngBounds,
    bounds: bounds,
    padding: padding,
  );

  /// Centra en un punto con un zoom concreto.
  factory CameraUpdate.newLatLngZoom(LatLng target, double zoom) =>
      CameraUpdate._(
        _CameraUpdateKind.newLatLngZoom,
        target: target,
        zoom: zoom,
      );

  /// Desplaza la vista [dx] y [dy] píxeles.
  factory CameraUpdate.scrollBy(double dx, double dy) =>
      CameraUpdate._(_CameraUpdateKind.scrollBy, dx: dx, dy: dy);

  /// Cambia el zoom en [amount] niveles, opcionalmente alrededor de [focus].
  factory CameraUpdate.zoomBy(double amount, [LatLng? focus]) =>
      CameraUpdate._(_CameraUpdateKind.zoomBy, zoom: amount, target: focus);

  /// Acerca un nivel.
  factory CameraUpdate.zoomIn() =>
      const CameraUpdate._(_CameraUpdateKind.zoomIn);

  /// Aleja un nivel.
  factory CameraUpdate.zoomOut() =>
      const CameraUpdate._(_CameraUpdateKind.zoomOut);

  /// Fija el zoom a un valor absoluto.
  factory CameraUpdate.zoomTo(double zoom) =>
      CameraUpdate._(_CameraUpdateKind.zoomTo, zoom: zoom);

  /// Gira el mapa hasta el rumbo indicado.
  ///
  /// No existe en `google_maps_flutter`, donde hay que reconstruir una
  /// `CameraPosition` entera solo para girar.
  factory CameraUpdate.bearingTo(double bearing) =>
      CameraUpdate._(_CameraUpdateKind.bearingTo, bearing: bearing);

  /// Inclina el mapa hasta el ángulo indicado.
  factory CameraUpdate.tiltTo(double tilt) =>
      CameraUpdate._(_CameraUpdateKind.tiltTo, tilt: tilt);

  final _CameraUpdateKind _kind;

  /// La posición completa, en [CameraUpdate.newCameraPosition].
  final CameraPosition? position;

  /// El punto de destino, en las fábricas que centran.
  final LatLng? target;

  /// El rectángulo, en [CameraUpdate.newLatLngBounds].
  final LatLngBounds? bounds;

  /// El zoom, absoluto o relativo según la fábrica.
  final double? zoom;

  /// El margen en píxeles, en [CameraUpdate.newLatLngBounds].
  final double? padding;

  /// Desplazamiento horizontal en píxeles.
  final double? dx;

  /// Desplazamiento vertical en píxeles.
  final double? dy;

  /// El rumbo, en [CameraUpdate.bearingTo].
  final double? bearing;

  /// La inclinación, en [CameraUpdate.tiltTo].
  final double? tilt;

  /// Aplica este movimiento sobre [current] y devuelve la cámara resultante.
  ///
  /// Los movimientos que necesitan saber el tamaño de la pantalla —encuadrar
  /// un rectángulo, desplazar por píxeles— los resuelve el motor, no esto:
  /// aquí devuelven `null` y el controlador toma el otro camino.
  @internal
  CameraPosition? resolve(CameraPosition current) => switch (_kind) {
    _CameraUpdateKind.newCameraPosition => position,
    _CameraUpdateKind.newLatLng => current.copyWith(target: target),
    _CameraUpdateKind.newLatLngZoom => current.copyWith(
      target: target,
      zoom: zoom,
    ),
    _CameraUpdateKind.zoomTo => current.copyWith(zoom: zoom),
    _CameraUpdateKind.zoomBy => current.copyWith(
      zoom: current.zoom + (zoom ?? 0),
      target: target ?? current.target,
    ),
    _CameraUpdateKind.zoomIn => current.copyWith(zoom: current.zoom + 1),
    _CameraUpdateKind.zoomOut => current.copyWith(zoom: current.zoom - 1),
    _CameraUpdateKind.bearingTo => current.copyWith(bearing: bearing),
    _CameraUpdateKind.tiltTo => current.copyWith(tilt: tilt),
    // Estos dos necesitan el tamaño del lienzo.
    _CameraUpdateKind.newLatLngBounds || _CameraUpdateKind.scrollBy => null,
  };

  /// ¿Es un encuadre de rectángulo?
  @internal
  bool get isBoundsFit => _kind == _CameraUpdateKind.newLatLngBounds;

  /// ¿Es un desplazamiento por píxeles?
  @internal
  bool get isScrollBy => _kind == _CameraUpdateKind.scrollBy;

  @override
  String toString() => 'CameraUpdate.${_kind.name}';
}

/// Cuánto se puede acercar y alejar el mapa.
///
/// El mismo nombre que en `google_maps_flutter`.
@immutable
class MinMaxZoomPreference {
  /// Crea la preferencia.
  const MinMaxZoomPreference(this.minZoom, this.maxZoom);

  /// Sin límites: de 0 a 22.
  static const MinMaxZoomPreference unbounded = MinMaxZoomPreference(
    null,
    null,
  );

  /// El zoom mínimo, o `null` para no limitarlo.
  final double? minZoom;

  /// El zoom máximo, o `null` para no limitarlo.
  final double? maxZoom;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MinMaxZoomPreference &&
          minZoom == other.minZoom &&
          maxZoom == other.maxZoom;

  @override
  int get hashCode => Object.hash(minZoom, maxZoom);
}
