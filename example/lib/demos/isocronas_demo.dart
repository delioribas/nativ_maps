// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:async';

import 'package:compass_maps_example/config.dart';
import 'package:compass_maps_example/widgets/demo_scaffold.dart';
import 'package:compass_maps_flutter/compass_maps_flutter.dart';
import 'package:flutter/material.dart';

/// **Isócronas: hasta dónde se llega en X minutos.** Google no tiene esto.
///
/// ## Para qué sirve de verdad
///
/// El caso que la justifica: un vehículo robado del que se perdió la señal
/// hace ocho minutos. La isócrona dibuja **dónde puede estar ahora**, y eso es
/// una zona de búsqueda, no un punto.
///
/// Funciona en los dos sentidos, y la diferencia importa:
///
/// - **Hacia fuera** (`origin`): ¿hasta dónde pudo llegar desde aquí?
/// - **Hacia dentro** (`destination`): ¿quién puede llegar HASTA aquí a
///   tiempo? Es la pregunta de un despacho de emergencias, y no es la misma:
///   las calles de sentido único hacen que las dos zonas no coincidan.
///
/// ## Las dos cosas que hay que saber
///
/// **Se cobra por umbral**, hasta cinco. Tres umbrales son tres unidades, no
/// una. El panel enseña el gasto para que se vea.
///
/// **`granularity` no es opcional en la práctica.** Sin `maxPoints`, el
/// polígono de treinta minutos trae varios miles de vértices y la interfaz
/// deja de responder mientras el dispositivo intenta dibujarlo. El valor por
/// defecto de este paquete ya viene puesto en 300.
class IsocronasDemo extends StatefulWidget {
  /// Crea la demostración.
  const IsocronasDemo({super.key});

  @override
  State<IsocronasDemo> createState() => _IsocronasDemoState();
}

class _IsocronasDemoState extends State<IsocronasDemo> {
  CompassMapController? _mapa;
  LatLng _punto = Config.defaultCenter;
  bool _haciaDentro = false;
  TravelMode _modo = TravelMode.car;
  int _maxPuntos = 300;
  final Set<int> _minutos = <int>{5, 10, 15};

  IsolineResponse? _respuesta;
  bool _cargando = false;
  Object? _error;

  static const _colores = <Color>[
    Color(0xFF00E676),
    Color(0xFFFFEA00),
    Color(0xFFFF9100),
    Color(0xFFFF3D00),
    Color(0xFFD500F9),
  ];

  @override
  Widget build(BuildContext context) => DemoScaffold(
    titulo: 'Isócronas',
    cargando: _cargando,
    error: _error,
    panel: _panel(),
    child: CompassMap(
      styleUrl: Config.maps.maps.styleDescriptorUrl(
        MapStyle.standard,
        colorScheme: MapColorScheme.dark,
        // El mapa es el fondo de los polígonos: los puntos de interés solo
        // estorban, y apagarlos en el descriptor evita que el servidor los
        // mande siquiera.
        poiDensity: MapPoiDensity.off,
      )!,
      initialCameraPosition: CameraPosition(target: _punto, zoom: 12),
      onMapCreated: (controller) {
        _mapa = controller;
        unawaited(_marcarPunto());
      },
      onTap: (posicion) {
        setState(() => _punto = posicion);
        unawaited(_marcarPunto());
        unawaited(_calcular());
      },
      padding: const EdgeInsets.only(bottom: 250),
    ),
  );

  Future<void> _marcarPunto() =>
      _mapa?.setMarkers(<Marker>[
        Marker(
          markerId: const MarkerId('centro'),
          position: _punto,
          infoWindow: InfoWindow(
            title: _haciaDentro ? 'Destino' : 'Origen',
            snippet: _haciaDentro
                ? 'Quién llega HASTA aquí'
                : 'Hasta dónde se llega DESDE aquí',
          ),
        ),
      ]) ??
      Future<void>.value();

  Future<void> _calcular() async {
    if (_minutos.isEmpty) return;
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final umbrales = _minutos.toList()..sort();
      final respuesta = await Config.maps.routes.calculateIsolines(
        // Uno u otro, nunca los dos: el paquete lo comprueba antes de enviar.
        origin: _haciaDentro ? null : _punto,
        destination: _haciaDentro ? _punto : null,
        arrivalTime: _haciaDentro
            ? DateTime.now().add(Duration(minutes: umbrales.last))
            : null,
        thresholds: Thresholds.time(<Duration>[
          for (final minuto in umbrales) Duration(minutes: minuto),
        ]),
        travelMode: _modo,
        // Sin esto, una isócrona de 30 min ahoga el mapa.
        granularity: IsolineGranularity(maxPoints: _maxPuntos),
      );

      setState(() => _respuesta = respuesta);
      await _pintar(respuesta);
    } on CompassMapsException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _pintar(IsolineResponse respuesta) async {
    final poligonos = <Polygon>[];

    // Se recorren al revés para que la más grande quede debajo; si no, la de
    // cinco minutos queda tapada por la de quince.
    final isocronas = respuesta.isolines.reversed.toList();
    for (final (indice, isocrona) in isocronas.indexed) {
      final color =
          _colores[(isocronas.length - 1 - indice).clamp(
            0,
            _colores.length - 1,
          )];

      // Una isócrona puede traer VARIOS polígonos: con un río sin puentes
      // cerca, lo alcanzable son dos manchas separadas. Unirlas dibujaría como
      // alcanzable justo el agua.
      for (final (subIndice, polygon) in isocrona.polygons.indexed) {
        if (polygon.isEmpty) continue;
        poligonos.add(
          Polygon(
            polygonId: PolygonId('iso-$indice-$subIndice'),
            points: polygon.first,
            holes: polygon.length > 1 ? polygon.sublist(1) : const [],
            fillColor: color.withValues(alpha: 0.22),
            strokeColor: color,
            strokeWidth: 2,
            zIndex: indice.toDouble(),
          ),
        );
      }
    }

    await _mapa?.setPolygons(poligonos);

    final todos = <LatLng>[
      for (final isocrona in respuesta.isolines) ...isocrona.outerRing,
    ];
    if (todos.isNotEmpty) {
      await _mapa?.animateCamera(
        CameraUpdate.newLatLngBounds(LatLngBounds.fromPoints(todos), 40),
      );
    }
  }

  Widget _panel() {
    final respuesta = _respuesta;
    return PanelDeResultados(
      titulo:
          'Isócronas · ${_minutos.length} umbral(es) = '
          '${_minutos.length} unidad(es) facturables',
      altura: 250,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Text('Sentido: ', style: TextStyle(fontSize: 12)),
            ChoiceChip(
              label: const Text('desde aquí', style: TextStyle(fontSize: 11)),
              selected: !_haciaDentro,
              onSelected: (_) {
                setState(() => _haciaDentro = false);
                unawaited(_marcarPunto());
                unawaited(_calcular());
              },
            ),
            const SizedBox(width: 6),
            ChoiceChip(
              label: const Text('hasta aquí', style: TextStyle(fontSize: 11)),
              selected: _haciaDentro,
              onSelected: (_) {
                setState(() => _haciaDentro = true);
                unawaited(_marcarPunto());
                unawaited(_calcular());
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          children: <Widget>[
            for (final minuto in const <int>[5, 10, 15, 20, 30])
              FilterChip(
                label: Text(
                  '$minuto min',
                  style: const TextStyle(fontSize: 11),
                ),
                selected: _minutos.contains(minuto),
                onSelected: (elegido) {
                  setState(() {
                    if (elegido) {
                      // Cinco es el máximo que admite la API, y el paquete lo
                      // comprueba antes de enviar.
                      if (_minutos.length >= 5) return;
                      _minutos.add(minuto);
                    } else {
                      _minutos.remove(minuto);
                    }
                  });
                },
              ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          children: <Widget>[
            for (final modo in <TravelMode>[
              TravelMode.car,
              TravelMode.scooter,
              TravelMode.pedestrian,
            ])
              ChoiceChip(
                label: Text(
                  modo.wireName,
                  style: const TextStyle(fontSize: 11),
                ),
                selected: modo == _modo,
                onSelected: (_) {
                  setState(() => _modo = modo);
                  unawaited(_calcular());
                },
              ),
          ],
        ),
        Row(
          children: <Widget>[
            const Text('maxPoints ', style: TextStyle(fontSize: 12)),
            Expanded(
              child: Slider(
                value: _maxPuntos.toDouble(),
                min: 30,
                max: 2000,
                divisions: 20,
                label: '$_maxPuntos',
                onChanged: (valor) =>
                    setState(() => _maxPuntos = valor.round()),
                onChangeEnd: (_) => unawaited(_calcular()),
              ),
            ),
          ],
        ),
        FilledButton.tonal(
          onPressed: () => unawaited(_calcular()),
          child: const Text('Calcular'),
        ),
        if (respuesta != null) ...<Widget>[
          const SizedBox(height: 8),
          for (final isocrona in respuesta.isolines)
            Dato(
              '${isocrona.timeThreshold?.inMinutes ?? '?'} min',
              '${isocrona.polygons.length} polígono(s), '
                  '${isocrona.pointCount} puntos',
            ),
          Dato(
            'Origen pegado',
            respuesta.snappedOrigin == null
                ? '—'
                : '${respuesta.snappedOrigin!.latitude.toStringAsFixed(5)}, '
                      '${respuesta.snappedOrigin!.longitude.toStringAsFixed(5)}',
          ),
          const Text(
            'Si el origen pegado queda lejos del que pediste, el punto caía '
            'fuera de la red vial y todo el cálculo parte de otro sitio.',
            style: TextStyle(fontSize: 11),
          ),
        ],
      ],
    );
  }
}
