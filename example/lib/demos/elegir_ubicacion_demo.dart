// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:async';

import 'package:nativ_maps_example/config.dart';
import 'package:nativ_maps_example/widgets/demo_scaffold.dart';
import 'package:nativ_maps_flutter/nativ_maps_flutter.dart';
import 'package:flutter/material.dart';

/// El alfiler fijo en el centro: se mueve el mapa, no el alfiler.
///
/// Es como se elige el punto de recogida en una app de taxi.
///
/// ## Lo que enseña
///
/// 1. **El alfiler es un widget de Flutter encima del mapa**, no un
///    marcador: no hay que moverlo, siempre está en el centro.
/// 2. **El centro es el del hueco visible.** Con un panel abajo, el mapa
///    lleva `padding` y la cámara centra en lo que queda; el alfiler tiene
///    que ir ahí, no en el centro de la pantalla.
/// 3. `onCameraMove` para las coordenadas en vivo —gratis— y
///    `onCameraIdle` para pedir la dirección: **una petición por gesto**, no
///    decenas.
/// 4. `reverseGeocode` con radio, y `isPrecise` para no presentar una ciudad
///    como si fuera un portal.
class ElegirUbicacionDemo extends StatefulWidget {
  /// Crea la demostración.
  const ElegirUbicacionDemo({super.key});

  @override
  State<ElegirUbicacionDemo> createState() => _ElegirUbicacionDemoState();
}

class _ElegirUbicacionDemoState extends State<ElegirUbicacionDemo> {
  static const double _panel = 220;

  NativMapController? _mapa;
  LatLng? _centro;
  bool _moviendo = false;
  Place? _lugar;
  int _peticiones = 0;
  double? _desvio;
  bool _cargando = false;
  NativMapsException? _error;

  @override
  Widget build(BuildContext context) => DemoScaffold(
    titulo: 'Elegir ubicación',
    cargando: _cargando,
    error: _error,
    panel: PanelDeResultados(
      titulo: _moviendo
          ? 'Moviendo…'
          : (_lugar?.address?.label ?? _lugar?.title ?? 'Mueve el mapa'),
      altura: _panel,
      children: <Widget>[
        Dato('Centro', _fmt(_centro)),
        Dato(
          'Tipo',
          _lugar == null
              ? '—'
              : '${_lugar!.placeType?.name ?? '?'} · '
                    '${(_lugar!.placeType?.isPrecise ?? false) ? 'precisa' : 'aproximada'}',
        ),
        Dato('Peticiones', '$_peticiones'),
        Dato(
          'Alfiler ↔ cámara',
          _desvio == null ? '—' : '${_desvio!.toStringAsFixed(1)} px',
        ),
      ],
    ),
    child: LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: <Widget>[
          Positioned.fill(
            child: NativMap(
              styleUrl: Config.maps.maps.styleDescriptorUrl(MapStyle.standard)!,
              initialCameraPosition: CameraPosition(
                target: Config.defaultCenter,
                zoom: 16,
              ),
              onMapCreated: (controller) => _mapa = controller,
              onCameraMove: (posicion) => setState(() {
                _moviendo = true;
                _centro = posicion.target;
              }),
              onCameraIdle: () => unawaited(_alSoltar(constraints)),
              padding: const EdgeInsets.only(bottom: _panel),
            ),
          ),
          // El alfiler, en el centro del hueco que deja el panel. No recibe
          // toques: los gestos tienen que llegar al mapa de debajo.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: _panel,
            child: const IgnorePointer(child: Center(child: _Alfiler())),
          ),
        ],
      ),
    ),
  );

  Future<void> _alSoltar(BoxConstraints constraints) async {
    final mapa = _mapa;
    final camara = await mapa?.getCameraPosition();
    if (mapa == null || camara == null || !mounted) return;
    // Dónde cae el centro de la cámara en pantalla, comparado con dónde se
    // dibuja el alfiler. Si no coinciden, la dirección no es la del alfiler.
    final enPantalla = await mapa.getScreenCoordinate(camara.target);
    final alfiler = Offset(
      constraints.maxWidth / 2,
      (constraints.maxHeight - _panel) / 2,
    );
    setState(() {
      _moviendo = false;
      _centro = camara.target;
      _desvio = (enPantalla - alfiler).distance;
      _cargando = true;
      _error = null;
      _peticiones++;
    });
    try {
      final lugares = await Config.maps.places.reverseGeocode(
        camara.target,
        // Sin radio, en una zona sin portales devuelve la ciudad.
        radiusMeters: 60,
      );
      if (mounted) setState(() => _lugar = lugares.firstOrNull);
    } on NativMapsException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  static String _fmt(LatLng? p) => p == null
      ? '—'
      : '${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}';
}

/// Un alfiler cuya punta cae exactamente en el centro de su caja.
class _Alfiler extends StatelessWidget {
  const _Alfiler();

  static const double _alto = 44;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: _alto,
      height: _alto * 2,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // El punto exacto que se elige.
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          // El icono, con la punta apoyada sobre el punto.
          Positioned(
            top: 0,
            child: Icon(Icons.location_pin, size: _alto, color: color),
          ),
        ],
      ),
    );
  }
}
