// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:async';

import 'package:nativ_maps_example/config.dart';
import 'package:nativ_maps_example/widgets/demo_scaffold.dart';
import 'package:nativ_maps_flutter/nativ_maps_flutter.dart';
import 'package:flutter/material.dart';

/// Rutas con indicaciones, alternativas y **coste de peaje**.
///
/// ## La línea que resume el paquete entero
///
/// ```dart
/// final ruta = (await maps.routes.calculateRoutes(...)).best!;
/// controller.addPolyline(Polyline(polylineId: id, points: ruta.points));
/// ```
///
/// `ruta.points` son `LatLng` de este paquete y `Polyline` los acepta tal
/// cual. **No hay conversión.** Ese es todo el argumento del §1: en cualquier
/// otra combinación habría que escribir el pegamento que traduce el `lat/lng`
/// de una respuesta JSON al tipo del mapa, y es donde se cuelan los errores de
/// orden de coordenadas.
///
/// ## Lo que solo se ve aquí
///
/// - **Peajes con importe.** Google no los da.
/// - `travelOnlyDuration`: el tiempo conduciendo, sin esperas ni descansos.
/// - `majorRoadLabels`: «por la Panamericana» dice más que «43 min».
class RutasDemo extends StatefulWidget {
  /// Crea la demostración.
  const RutasDemo({super.key});

  @override
  State<RutasDemo> createState() => _RutasDemoState();
}

class _RutasDemoState extends State<RutasDemo> {
  NativMapController? _mapa;
  LatLng? _origen;
  LatLng? _destino;
  RouteResponse? _respuesta;
  int _elegida = 0;

  TravelMode _modo = TravelMode.car;
  bool _evitarPeajes = false;
  bool _cargando = false;
  Object? _error;

  @override
  Widget build(BuildContext context) => DemoScaffold(
    titulo: 'Rutas y peajes',
    cargando: _cargando,
    error: _error,
    panel: _panel(),
    child: NativMap(
      styleUrl: Config.maps.maps.styleDescriptorUrl(
        MapStyle.standard,
        // El tráfico dentro del propio estilo: es el equivalente real de
        // `trafficEnabled`, y lo pinta el servidor.
        traffic: MapTraffic.congestion,
      )!,
      initialCameraPosition: CameraPosition(
        target: Config.defaultCenter,
        zoom: 12,
      ),
      onMapCreated: (controller) => _mapa = controller,
      onTap: _ponerPunto,
      padding: const EdgeInsets.only(bottom: 260),
    ),
  );

  Future<void> _ponerPunto(LatLng posicion) async {
    setState(() {
      if (_origen == null || (_origen != null && _destino != null)) {
        _origen = posicion;
        _destino = null;
        _respuesta = null;
      } else {
        _destino = posicion;
      }
    });

    await _mapa?.setMarkers(<Marker>[
      if (_origen != null)
        Marker(
          markerId: const MarkerId('origen'),
          position: _origen!,
          icon: BitmapDescriptor.defaultMarkerWithHue(MarkerHue.hueGreen),
          infoWindow: const InfoWindow(title: 'Origen'),
        ),
      if (_destino != null)
        Marker(
          markerId: const MarkerId('destino'),
          position: _destino!,
          icon: BitmapDescriptor.defaultMarkerWithHue(MarkerHue.hueRed),
          infoWindow: const InfoWindow(title: 'Destino'),
        ),
    ]);

    if (_origen != null && _destino != null) await _calcular();
  }

  Future<void> _calcular() async {
    final origen = _origen;
    final destino = _destino;
    if (origen == null || destino == null) return;

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final respuesta = await Config.maps.routes.calculateRoutes(
        origin: origen,
        destination: destino,
        travelMode: _modo,
        // Hasta tres alternativas para poder compararlas.
        maxAlternatives: 2,
        // Sin pedir `tolls` explícitamente, los peajes no vienen. Y `summary`
        // hace falta para que `Summary.Overview` traiga distancia y duración
        // por tramo — sin él, salen a cero.
        legAdditionalFeatures: const <RouteFeature>[
          RouteFeature.tolls,
          RouteFeature.summary,
          RouteFeature.typicalDuration,
        ],
        avoid: RouteAvoidance(tollRoads: _evitarPeajes),
      );

      setState(() {
        _respuesta = respuesta;
        _elegida = 0;
      });
      await _pintar();
    } on NativMapsException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _pintar() async {
    final respuesta = _respuesta;
    final mapa = _mapa;
    if (respuesta == null || mapa == null || respuesta.isEmpty) return;

    await mapa.setPolylines(<Polyline>[
      // Las alternativas primero y en gris, para que la elegida quede encima.
      for (final (indice, ruta) in respuesta.routes.indexed)
        if (indice != _elegida)
          Polyline(
            polylineId: PolylineId('alt-$indice'),
            points: ruta.points,
            color: Colors.grey.shade500,
            width: 4,
            zIndex: 0,
          ),
      Polyline(
        polylineId: const PolylineId('elegida'),
        // Aquí está: los puntos de la ruta entran directamente en la línea.
        points: respuesta.routes[_elegida].points,
        color: Theme.of(context).colorScheme.primary,
        width: 7,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        zIndex: 1,
      ),
    ]);

    final bounds = respuesta.routes[_elegida].bounds;
    if (bounds != null) {
      await mapa.animateCamera(
        CameraUpdate.newLatLngBounds(bounds.padded(300), 56),
      );
    }
  }

  Widget _panel() {
    final respuesta = _respuesta;
    final ruta = respuesta == null || respuesta.isEmpty
        ? null
        : respuesta.routes[_elegida];

    return PanelDeResultados(
      titulo: ruta == null
          ? 'Toca dos puntos del mapa'
          : 'Ruta · ${ruta.distanceKm.toStringAsFixed(1)} km · '
                '${ruta.duration.inMinutes} min',
      altura: 260,
      children: <Widget>[
        Wrap(
          spacing: 6,
          children: <Widget>[
            for (final modo in TravelMode.values)
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
            FilterChip(
              label: const Text(
                'evitar peajes',
                style: TextStyle(fontSize: 11),
              ),
              selected: _evitarPeajes,
              onSelected: (valor) {
                setState(() => _evitarPeajes = valor);
                unawaited(_calcular());
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (respuesta != null && respuesta.routes.length > 1)
          Row(
            children: <Widget>[
              const Text('Alternativas: ', style: TextStyle(fontSize: 12)),
              for (final (indice, alternativa) in respuesta.routes.indexed)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(
                      '${alternativa.duration.inMinutes} min',
                      style: const TextStyle(fontSize: 11),
                    ),
                    selected: indice == _elegida,
                    onSelected: (_) {
                      setState(() => _elegida = indice);
                      unawaited(_pintar());
                    },
                  ),
                ),
            ],
          ),
        if (ruta != null) ...<Widget>[
          Dato('Distancia', '${ruta.distanceMeters.round()} m'),
          Dato('Duración', '${ruta.duration.inSeconds} s'),
          Dato('Tramos', '${ruta.legs.length}'),
          Dato('Indicaciones', '${ruta.steps.length}'),
          Dato(
            'Solo conduciendo',
            ruta.legs.first.travelOnlyDuration == null
                ? '—'
                : '${ruta.legs.first.travelOnlyDuration!.inSeconds} s',
          ),
          Dato(
            'Vías principales',
            ruta.majorRoadLabels.isEmpty
                ? '—'
                : ruta.majorRoadLabels.join(' · '),
          ),
          // Esto es lo que Google no da.
          Dato(
            'Peajes',
            ruta.tolls.isEmpty
                ? 'ninguno'
                : ruta.tollCostByCurrency.entries
                      .map((e) => '${e.value.toStringAsFixed(2)} ${e.key}')
                      .join(' + '),
          ),
          if (respuesta != null && respuesta.notices.isNotEmpty)
            Dato('Avisos', respuesta.notices.join(', ')),
          const SizedBox(height: 8),
          const Text(
            'Primeras indicaciones',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          for (final paso in ruta.steps.take(6))
            Dato(
              paso.type ?? '?',
              '${paso.instruction ?? paso.nextRoad ?? ''} '
              '· ${paso.distanceMeters.round()} m',
            ),
        ],
      ],
    );
  }
}
