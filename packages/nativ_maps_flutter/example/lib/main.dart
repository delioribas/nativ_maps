// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:flutter/material.dart';
import 'package:nativ_maps_flutter/nativ_maps_flutter.dart';

/// El cliente de Amazon Location, compartido por toda la app.
///
/// **Uno solo, no uno por pantalla**: cada instancia trae sus propias cachés, y
/// crear una por pantalla significa pagar dos veces la misma búsqueda.
final maps = NativMaps(
  region: const String.fromEnvironment('ALS_REGION', defaultValue: 'us-east-1'),
  credentials: const ApiKeyCredentials(String.fromEnvironment('ALS_API_KEY')),
  language: 'es',
  // No es un extra: una matriz de 10×10 cuesta cien unidades, y un bucle en un
  // `initState` no se ve como un error al leer el código.
  budget: Budget(maxUnits: 200),
);

void main() => runApp(const EjemploMinimo());

/// El mapa mínimo con Amazon Location.
class EjemploMinimo extends StatefulWidget {
  /// Crea la app.
  const EjemploMinimo({super.key});

  @override
  State<EjemploMinimo> createState() => _EjemploMinimoState();
}

class _EjemploMinimoState extends State<EjemploMinimo> {
  NativMapController? _mapa;
  String _estado = 'Toca el mapa para calcular una ruta desde el centro.';

  static final _centro = LatLng(-0.1807, -78.4678);

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('nativ_maps')),
      body: Column(
        children: <Widget>[
          Padding(padding: const EdgeInsets.all(12), child: Text(_estado)),
          Expanded(
            child: NativMap(
              // La URL del estilo es todo lo que hace falta para el mapa.
              styleUrl: maps.maps.styleDescriptorUrl(MapStyle.standard) ?? '',
              initialCameraPosition: CameraPosition(target: _centro, zoom: 12),
              onMapCreated: (controlador) async {
                _mapa = controlador;
                await controlador.addMarker(
                  Marker(
                    markerId: const MarkerId('centro'),
                    position: _centro,
                    infoWindow: const InfoWindow(title: 'Quito'),
                  ),
                );
              },
              // Merece la pena engancharlo: sin esto, un estilo que no
              // carga deja un rectángulo gris sin ninguna explicación.
              onStyleError: (error) =>
                  setState(() => _estado = 'Error de estilo: $error'),
              onTap: _calcularRuta,
              zoomControlsEnabled: true,
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _calcularRuta(LatLng destino) async {
    final mapa = _mapa;
    if (mapa == null) return;
    setState(() => _estado = 'Calculando…');

    try {
      final respuesta = await maps.routes.calculateRoutes(
        origin: _centro,
        destination: destino,
      );
      final ruta = respuesta.best;
      if (ruta == null) {
        setState(() => _estado = 'Sin ruta para ese par.');
        return;
      }

      // La tesis del paquete: los puntos de la ruta entran directamente en la
      // polilínea, sin convertir nada.
      await mapa.addPolyline(
        Polyline(
          polylineId: const PolylineId('ruta'),
          points: ruta.points,
          width: 6,
        ),
      );
      await mapa.animateCamera(
        CameraUpdate.newLatLngBounds(ruta.bounds!.padded(300), 48),
      );

      setState(
        () => _estado =
            '${ruta.distanceKm.toStringAsFixed(1)} km · '
            '${ruta.duration.inMinutes} min',
      );
    } on NativMapsException catch (error) {
      setState(() => _estado = '$error');
    }
  }
}
