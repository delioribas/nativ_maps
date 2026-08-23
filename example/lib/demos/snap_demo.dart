// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:async';
import 'dart:math' as math;

import 'package:nativ_maps_example/config.dart';
import 'package:nativ_maps_example/widgets/demo_scaffold.dart';
import 'package:nativ_maps_flutter/nativ_maps_flutter.dart';
import 'package:flutter/material.dart';

/// **Pegar un rastro GPS a la calle real.** Google no tiene esto.
///
/// ## El problema que resuelve
///
/// Un rastro GPS crudo zigzaguea sobre las aceras, atraviesa manzanas y salta
/// entre carriles. Dibujado tal cual, el histórico de un vehículo parece un
/// error de la app. `SnapToRoads` lo convierte en un recorrido que sigue la
/// calzada.
///
/// ## Lo que casi todo el mundo desperdicia
///
/// `TracePoint` acepta **rumbo, velocidad y hora** además de la posición, y
/// **el GT06 manda los tres**. Con la velocidad, el servicio distingue el
/// carril de servicio de la autopista paralela; sin ella, tiene que adivinar.
///
/// El interruptor «solo posiciones» de esta demo enseña la diferencia.
///
/// ## El troceado
///
/// La API admite entre 2 y **5 000** puntos por petición. Un histórico de un
/// día se pasa de largo. Este paquete **trocea y cose** en vez de fallar, con
/// solape entre trozos para que la costura no salte a otra calle.
///
/// Cada trozo es una petición facturada: `chunkCount` dice cuántas fueron.
class SnapDemo extends StatefulWidget {
  /// Crea la demostración.
  const SnapDemo({super.key});

  @override
  State<SnapDemo> createState() => _SnapDemoState();
}

class _SnapDemoState extends State<SnapDemo> {
  NativMapController? _mapa;
  final _rng = math.Random(11);

  late List<TracePoint> _rastro;
  bool _soloPosiciones = false;
  double _radio = 500;
  double _confianzaMinima = 0.5;

  SnapToRoadsResponse? _respuesta;
  bool _cargando = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _rastro = _generarRastroConRuido();
  }

  /// Un rastro con el ruido típico de un localizador urbano barato.
  ///
  /// Va describiendo una avenida y le añade una desviación aleatoria de hasta
  /// unos veinte metros, que es lo que produce un GPS entre edificios altos.
  List<TracePoint> _generarRastroConRuido() {
    final inicio = Config.defaultCenter;
    final base = DateTime.now().subtract(const Duration(minutes: 20));
    return <TracePoint>[
      for (var i = 0; i < 60; i++)
        TracePoint(
          position: inicio
              .offset(60.0 * i, 35)
              .offset(_rng.nextDouble() * 22, _rng.nextDouble() * 360),
          headingDegrees: 35 + (_rng.nextDouble() * 20 - 10),
          speedKmh: 28 + _rng.nextDouble() * 22,
          timestamp: base.add(Duration(seconds: i * 12)),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) => DemoScaffold(
    titulo: 'Pegar rastro a la calle',
    cargando: _cargando,
    error: _error,
    panel: _panel(),
    child: NativMap(
      styleUrl: Config.maps.maps.styleDescriptorUrl(MapStyle.standard)!,
      initialCameraPosition: CameraPosition(
        target: Config.defaultCenter,
        zoom: 15,
      ),
      onMapCreated: (controller) {
        _mapa = controller;
        unawaited(_pintarCrudo());
      },
      padding: const EdgeInsets.only(bottom: 250),
    ),
  );

  Future<void> _pintarCrudo() async {
    await _mapa?.setPolylines(<Polyline>[
      Polyline(
        polylineId: const PolylineId('crudo'),
        points: <LatLng>[for (final punto in _rastro) punto.position],
        color: Colors.red.withValues(alpha: 0.6),
        width: 3,
        patterns: <PatternItem>[PatternItem.dash(8), PatternItem.gap(6)],
      ),
    ]);
    final bounds = LatLngBounds.fromPoints(<LatLng>[
      for (final punto in _rastro) punto.position,
    ]);
    await _mapa?.animateCamera(
      CameraUpdate.newLatLngBounds(bounds.padded(200), 48),
    );
  }

  Future<void> _pegar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final puntos = _soloPosiciones
          // Lo que hace casi todo el mundo, y desperdicia la mitad de la
          // precisión de la operación.
          ? <TracePoint>[
              for (final punto in _rastro) TracePoint(position: punto.position),
            ]
          : _rastro;

      final respuesta = await Config.maps.routes.snapToRoads(
        tracePoints: puntos,
        // 300 por defecto es corto con cobertura urbana mala; ~500 va mejor
        // para un GT06 entre edificios.
        snapRadiusMeters: _radio,
      );

      setState(() => _respuesta = respuesta);
      await _pintarPegado(respuesta);
    } on NativMapsException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _pintarPegado(SnapToRoadsResponse respuesta) async {
    final fiables = respuesta.confidentPoints(minimum: _confianzaMinima);

    await _mapa?.setPolylines(<Polyline>[
      // El crudo se queda debajo, para poder comparar.
      Polyline(
        polylineId: const PolylineId('crudo'),
        points: <LatLng>[for (final punto in _rastro) punto.position],
        color: Colors.red.withValues(alpha: 0.45),
        width: 3,
        patterns: <PatternItem>[PatternItem.dash(8), PatternItem.gap(6)],
        zIndex: 0,
      ),
      Polyline(
        polylineId: const PolylineId('pegado'),
        points: respuesta.geometry.points,
        color: Colors.green,
        width: 6,
        jointType: JointType.round,
        zIndex: 1,
      ),
    ]);

    // Los puntos dudosos se marcan en vez de pintarse como recorrido: pegarlos
    // a una calle sin estar seguro es dibujar una calle inventada.
    await _mapa?.setMarkers(<Marker>[
      for (final (indice, punto) in respuesta.snappedPoints.indexed)
        if ((punto.confidence ?? 1) < _confianzaMinima)
          Marker(
            markerId: MarkerId('dudoso-$indice'),
            position: punto.snappedPosition,
            icon: BitmapDescriptor.defaultMarkerWithHue(MarkerHue.hueOrange),
            iconScale: 0.6,
            infoWindow: InfoWindow(
              title: 'Confianza baja',
              snippet:
                  'conf. ${punto.confidence?.toStringAsFixed(2)} · '
                  'movido ${punto.displacementMeters?.round()} m',
            ),
          ),
    ]);

    setState(() {
      _respuesta = respuesta;
      _fiables = fiables.length;
    });
  }

  int _fiables = 0;

  Widget _panel() {
    final respuesta = _respuesta;
    final desplazamientos = <double>[
      for (final punto in respuesta?.snappedPoints ?? <SnappedTracePoint>[])
        if (punto.displacementMeters != null) punto.displacementMeters!,
    ];
    final medio = desplazamientos.isEmpty
        ? null
        : desplazamientos.reduce((a, b) => a + b) / desplazamientos.length;

    return PanelDeResultados(
      titulo: 'SnapToRoads · ${_rastro.length} puntos de rastro',
      altura: 250,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.tonal(
                onPressed: () => unawaited(_pegar()),
                child: const Text('Pegar a la calle'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    _rastro = _generarRastroConRuido();
                    _respuesta = null;
                  });
                  unawaited(_mapa?.clearMarkers());
                  unawaited(_pintarCrudo());
                },
                child: const Text('Otro rastro'),
              ),
            ),
          ],
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Enviar solo posiciones',
            style: TextStyle(fontSize: 12),
          ),
          subtitle: const Text(
            'Sin rumbo, velocidad ni hora. El GT06 los manda: no usarlos '
            'desperdicia la mitad de la precisión.',
            style: TextStyle(fontSize: 11),
          ),
          value: _soloPosiciones,
          onChanged: (valor) => setState(() => _soloPosiciones = valor),
        ),
        Row(
          children: <Widget>[
            const Text('snapRadius ', style: TextStyle(fontSize: 12)),
            Expanded(
              child: Slider(
                value: _radio,
                min: 50,
                max: 2000,
                divisions: 39,
                label: '${_radio.round()} m',
                onChanged: (valor) => setState(() => _radio = valor),
              ),
            ),
            Text('${_radio.round()} m', style: const TextStyle(fontSize: 11)),
          ],
        ),
        Row(
          children: <Widget>[
            const Text('confianza mín. ', style: TextStyle(fontSize: 12)),
            Expanded(
              child: Slider(
                value: _confianzaMinima,
                divisions: 10,
                label: _confianzaMinima.toStringAsFixed(1),
                onChanged: (valor) => setState(() => _confianzaMinima = valor),
                onChangeEnd: (_) {
                  if (respuesta != null) unawaited(_pintarPegado(respuesta));
                },
              ),
            ),
          ],
        ),
        if (respuesta != null) ...<Widget>[
          Dato('Puntos pegados', '${respuesta.snappedPoints.length}'),
          Dato('Fiables', '$_fiables de ${respuesta.snappedPoints.length}'),
          Dato(
            'Peticiones reales',
            '${respuesta.chunkCount} — es lo que se factura',
          ),
          Dato(
            'Desplazamiento medio',
            medio == null ? '—' : '${medio.toStringAsFixed(1)} m',
          ),
          if (respuesta.notices.isNotEmpty)
            Dato('Avisos', respuesta.notices.join(', ')),
          const Text(
            'Rojo discontinuo: lo que mandó el GPS. Verde: la calle real. '
            'Naranja: puntos que el servicio pegó sin estar seguro.',
            style: TextStyle(fontSize: 11),
          ),
        ],
      ],
    );
  }
}
