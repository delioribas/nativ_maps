// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:typed_data';

import 'package:compass_maps_example/config.dart';
import 'package:compass_maps_example/widgets/demo_scaffold.dart';
import 'package:compass_maps_flutter/compass_maps_flutter.dart';
import 'package:flutter/material.dart';

/// El mapa, sus cuatro estilos y los rasgos que Google no tiene.
///
/// ## Lo que enseña
///
/// 1. El widget mínimo que hace falta para tener un mapa.
/// 2. Los cuatro estilos del catálogo de v2.
/// 3. **Día y noche renderizados por el servidor**, no un filtro de color.
/// 4. **Tráfico, relieve y edificios 3D como parámetros del descriptor**, sin
///    una segunda petición ni una capa superpuesta.
/// 5. `GetStaticMap`: una miniatura que pinta el servidor, útil donde no hay
///    widget —una notificación, un PDF—.
class MapaBasicoDemo extends StatefulWidget {
  /// Crea la demostración.
  const MapaBasicoDemo({super.key});

  @override
  State<MapaBasicoDemo> createState() => _MapaBasicoDemoState();
}

class _MapaBasicoDemoState extends State<MapaBasicoDemo> {
  CompassMapController? _mapa;

  MapStyle _estilo = MapStyle.standard;
  MapColorScheme _esquema = MapColorScheme.light;
  MapTraffic? _trafico;
  MapTerrain? _relieve;
  MapBuildings? _edificios;
  MapPoiDensity? _densidadPoi;

  /// La URL del descriptor de estilo.
  ///
  /// **Es todo lo que hace falta para cambiar el aspecto del mapa.** Cambiar
  /// esta cadena y reconstruir basta: el widget detecta la diferencia, recarga
  /// el estilo y reinstala las superposiciones.
  String get _styleUrl =>
      Config.maps.maps.styleDescriptorUrl(
        _estilo,
        colorScheme: _esquema,
        traffic: _trafico,
        terrain: _relieve,
        buildings: _edificios,
        poiDensity: _densidadPoi,
      ) ??
      '';

  @override
  Widget build(BuildContext context) => DemoScaffold(
    titulo: 'Mapa básico',
    acciones: <Widget>[
      IconButton(
        tooltip: 'Miniatura del servidor',
        icon: const Icon(Icons.image_outlined),
        onPressed: _mostrarMiniatura,
      ),
    ],
    panel: _panel(),
    child: CompassMap(
      styleUrl: _styleUrl,
      initialCameraPosition: CameraPosition(
        target: Config.defaultCenter,
        zoom: 13,
      ),
      onMapCreated: (controller) => _mapa = controller,
      // Merece la pena engancharlo siempre: sin esto, un estilo que no
      // carga deja un rectángulo gris sin ninguna explicación.
      onStyleError: (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      },
      zoomControlsEnabled: true,
      myLocationEnabled: false,
      padding: const EdgeInsets.only(bottom: 240),
    ),
  );

  Widget _panel() => PanelDeResultados(
    titulo: 'Descriptor de estilo · 10 parámetros',
    altura: 240,
    children: <Widget>[
      _Selector<MapStyle>(
        etiqueta: 'Estilo',
        valor: _estilo,
        valores: MapStyle.values,
        nombre: (v) => v.wireName,
        onChanged: (v) => setState(() => _estilo = v),
      ),
      _Selector<MapColorScheme>(
        etiqueta: 'Tono',
        valor: _esquema,
        valores: MapColorScheme.values,
        nombre: (v) => v.wireName,
        onChanged: (v) => setState(() => _esquema = v),
      ),
      _SelectorOpcional<MapTraffic>(
        etiqueta: 'Tráfico',
        valor: _trafico,
        valores: MapTraffic.values,
        nombre: (v) => v.wireName,
        onChanged: (v) => setState(() => _trafico = v),
      ),
      _SelectorOpcional<MapTerrain>(
        etiqueta: 'Relieve',
        valor: _relieve,
        valores: MapTerrain.values,
        nombre: (v) => v.wireName,
        onChanged: (v) => setState(() => _relieve = v),
      ),
      _SelectorOpcional<MapBuildings>(
        etiqueta: 'Edificios',
        valor: _edificios,
        valores: MapBuildings.values,
        nombre: (v) => v.wireName,
        onChanged: (v) => setState(() => _edificios = v),
      ),
      _SelectorOpcional<MapPoiDensity>(
        etiqueta: 'Puntos de interés',
        valor: _densidadPoi,
        valores: MapPoiDensity.values,
        nombre: (v) => v.wireName,
        onChanged: (v) => setState(() => _densidadPoi = v),
      ),
      const SizedBox(height: 8),
      const Text(
        'Tráfico, relieve, edificios 3D y densidad de puntos de interés '
        'los dibuja el servidor dentro del mismo estilo. En '
        'google_maps_flutter, el tráfico es un interruptor y el resto no '
        'existe.',
        style: TextStyle(fontSize: 11),
      ),
    ],
  );

  /// Enseña una miniatura pintada por el servidor.
  ///
  /// `GetStaticMap` no necesita que haya un mapa en pantalla: sirve para una
  /// notificación push, un PDF o un correo. `takeSnapshot` de
  /// `google_maps_flutter` exige el widget montado y visible.
  Future<void> _mostrarMiniatura() async {
    final region = await _mapa?.getVisibleRegion();
    if (region == null || !mounted) return;

    final imagen = await Config.maps.maps.staticMap(
      boundingBox: region,
      width: 600,
      height: 400,
      style: _estilo,
      colorScheme: _esquema,
    );
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('GetStaticMap'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Image.memory(Uint8List.fromList(imagen.bytes), fit: BoxFit.contain),
            const SizedBox(height: 8),
            Text(
              '${imagen.length} bytes · ${imagen.contentType}',
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}

class _Selector<T> extends StatelessWidget {
  const _Selector({
    required this.etiqueta,
    required this.valor,
    required this.valores,
    required this.nombre,
    required this.onChanged,
  });

  final String etiqueta;
  final T valor;
  final List<T> valores;
  final String Function(T) nombre;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      SizedBox(
        width: 120,
        child: Text(etiqueta, style: Theme.of(context).textTheme.bodySmall),
      ),
      Expanded(
        child: Wrap(
          spacing: 6,
          children: <Widget>[
            for (final v in valores)
              ChoiceChip(
                label: Text(nombre(v), style: const TextStyle(fontSize: 11)),
                selected: v == valor,
                onSelected: (_) => onChanged(v),
              ),
          ],
        ),
      ),
    ],
  );
}

class _SelectorOpcional<T> extends StatelessWidget {
  const _SelectorOpcional({
    required this.etiqueta,
    required this.valor,
    required this.valores,
    required this.nombre,
    required this.onChanged,
  });

  final String etiqueta;
  final T? valor;
  final List<T> valores;
  final String Function(T) nombre;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      SizedBox(
        width: 120,
        child: Text(etiqueta, style: Theme.of(context).textTheme.bodySmall),
      ),
      Expanded(
        child: Wrap(
          spacing: 6,
          children: <Widget>[
            ChoiceChip(
              label: const Text('—', style: TextStyle(fontSize: 11)),
              selected: valor == null,
              onSelected: (_) => onChanged(null),
            ),
            for (final v in valores)
              ChoiceChip(
                label: Text(nombre(v), style: const TextStyle(fontSize: 11)),
                selected: v == valor,
                onSelected: (_) => onChanged(v),
              ),
          ],
        ),
      ),
    ],
  );
}
