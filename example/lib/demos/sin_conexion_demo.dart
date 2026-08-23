// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:async';

import 'package:nativ_maps_example/config.dart';
import 'package:nativ_maps_example/widgets/demo_scaffold.dart';
import 'package:nativ_maps_flutter/nativ_maps_flutter.dart';
import 'package:flutter/material.dart';

/// **Mapas sin conexión.** `google_maps_flutter` no puede dar esto.
///
/// ## Por qué Google no lo tiene
///
/// **No es una limitación técnica: sus condiciones prohíben cachear teselas.**
/// Por eso ningún envoltorio de Google lo ofrece, por bien escrito que esté.
///
/// ## Por qué importa
///
/// Un vehículo robado saliendo hacia zona sin cobertura, un muestreo de campo,
/// una instalación en un sótano. Los tres son sitios sin red, y los tres son
/// donde la app tiene que funcionar.
///
/// ## ⚠️ Lo que hay que resolver antes de enviar una app con esto
///
/// Que MapLibre **pueda** guardar teselas no significa que Amazon **permita**
/// guardar las suyas. Las condiciones remiten a la **Sección 82 de los AWS
/// Service Terms**, que AWS no publica de forma consultable.
///
/// 1. Leer la Sección 82 completa, en `aws.amazon.com/service-terms`.
/// 2. Comprobar qué proveedor sirve tu región. Si el mapa base abierto
///    (OpenStreetMap Daylight) sirve, el problema legal se simplifica mucho.
/// 3. Declarar la atribución, obligatoria y visible. **En un mapa guardado
///    también** — y ahí es justo donde se olvida.
/// 4. Fijar una caducidad. Para eso está `deleteStaleRegions`.
class SinConexionDemo extends StatefulWidget {
  /// Crea la demostración.
  const SinConexionDemo({super.key});

  @override
  State<SinConexionDemo> createState() => _SinConexionDemoState();
}

class _SinConexionDemoState extends State<SinConexionDemo> {
  NativMapController? _mapa;
  StreamSubscription<DownloadProgress>? _descarga;

  double _minZoom = 10;
  double _maxZoom = 15;
  DownloadProgress? _progreso;
  List<OfflineRegion> _regiones = <OfflineRegion>[];
  Object? _error;

  @override
  void dispose() {
    unawaited(_descarga?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DemoScaffold(
    titulo: 'Sin conexión',
    error: _error,
    panel: _panel(),
    child: NativMap(
      styleUrl: Config.maps.maps.styleDescriptorUrl(MapStyle.standard)!,
      initialCameraPosition: CameraPosition(
        target: Config.defaultCenter,
        zoom: 12,
      ),
      // Se pide EXPLÍCITAMENTE porque descargar mapas tiene implicaciones
      // legales que hay que resolver antes. Sin esto,
      // `controller.offline` devuelve `null`.
      offlineEnabled: true,
      onMapCreated: (controller) {
        _mapa = controller;
        unawaited(_listar());
      },
      padding: const EdgeInsets.only(bottom: 290),
    ),
  );

  /// Descarga lo que se ve ahora mismo en pantalla.
  ///
  /// El rango de zoom es LA decisión: el número de teselas crece **por cuatro
  /// con cada nivel**. De z10 a z14 son unos pocos megabytes; de z10 a z18,
  /// cientos, y media hora con datos móviles.
  Future<void> _descargar() async {
    final offline = _mapa?.offline;
    final region = await _mapa?.getVisibleRegion();
    if (offline == null || region == null) return;

    setState(() {
      _error = null;
      _progreso = null;
    });

    await _descarga?.cancel();
    _descarga = offline
        .downloadRegion(
          bounds: region,
          minZoom: _minZoom,
          maxZoom: _maxZoom,
          name: 'Zona ${DateTime.now().toIso8601String().substring(11, 16)}',
        )
        .listen(
          (progreso) => setState(() => _progreso = progreso),
          onError: (Object error) => setState(() => _error = error),
          onDone: () {
            unawaited(_listar());
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Región descargada')),
              );
            }
          },
        );
  }

  Future<void> _listar() async {
    final offline = _mapa?.offline;
    if (offline == null) return;
    try {
      final regiones = await offline.listRegions();
      if (mounted) setState(() => _regiones = regiones);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _borrar(OfflineRegion region) async {
    await _mapa?.offline?.deleteRegion(region.id);
    await _listar();
  }

  /// Borra lo que lleve guardado más de siete días.
  ///
  /// Llamarlo al arrancar la app es lo más sencillo: unas pocas
  /// comprobaciones locales, y la app deja de conservar mapas más tiempo del
  /// permitido sin que nadie tenga que acordarse.
  Future<void> _caducar() async {
    final borradas = await _mapa?.offline?.deleteStaleRegions(
      const Duration(days: 7),
    );
    await _listar();
    if (mounted && borradas != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$borradas región(es) caducada(s) borrada(s)')),
      );
    }
  }

  Widget _panel() {
    final progreso = _progreso;
    return PanelDeResultados(
      titulo: 'Regiones guardadas · ${_regiones.length}',
      altura: 290,
      children: <Widget>[
        Row(
          children: <Widget>[
            const SizedBox(
              width: 70,
              child: Text('Zoom', style: TextStyle(fontSize: 12)),
            ),
            Expanded(
              child: RangeSlider(
                values: RangeValues(_minZoom, _maxZoom),
                min: 6,
                max: 18,
                divisions: 12,
                labels: RangeLabels(
                  'z${_minZoom.round()}',
                  'z${_maxZoom.round()}',
                ),
                onChanged: (valores) => setState(() {
                  _minZoom = valores.start;
                  _maxZoom = valores.end;
                }),
              ),
            ),
          ],
        ),
        Text(
          'De z${_minZoom.round()} a z${_maxZoom.round()}: '
          '${_estimacion()}. El número de teselas se multiplica por cuatro '
          'con cada nivel.',
          style: const TextStyle(fontSize: 11),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            FilledButton.tonal(
              onPressed: () => unawaited(_descargar()),
              child: const Text('Descargar lo visible'),
            ),
            OutlinedButton(
              onPressed: () => unawaited(_listar()),
              child: const Text('Listar'),
            ),
            OutlinedButton(
              onPressed: () => unawaited(_caducar()),
              child: const Text('Caducar >7 días'),
            ),
            OutlinedButton(
              onPressed: () => unawaited(_mapa?.clearTileCache()),
              child: const Text('Vaciar caché'),
            ),
          ],
        ),
        if (progreso != null) ...<Widget>[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progreso.fraction),
          Dato('Progreso', '${(progreso.fraction * 100).round()} %'),
          if (progreso.completedBytes > 0)
            Dato(
              'Descargado',
              '${progreso.completedMegabytes.toStringAsFixed(1)} MB',
            ),
        ],
        const SizedBox(height: 8),
        for (final region in _regiones)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(region.name ?? 'Región ${region.id}'),
            subtitle: Text(
              'z${region.minZoom.round()}–z${region.maxZoom.round()} · '
              '${region.downloadedAt?.toIso8601String().substring(0, 16) ?? '?'}'
              '${region.isStale(const Duration(days: 7)) ? ' · CADUCADA' : ''}',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => unawaited(_borrar(region)),
            ),
          ),
        if (_regiones.isEmpty)
          const Text(
            'Ninguna región guardada todavía.',
            style: TextStyle(fontSize: 12),
          ),
        const SizedBox(height: 8),
        const Text(
          '⚠️ Antes de enviar una app con esto: leer la Sección 82 de los AWS '
          'Service Terms, comprobar qué proveedor sirve tu región, declarar '
          'la atribución también en el mapa guardado y fijar una caducidad.',
          style: TextStyle(fontSize: 11),
        ),
      ],
    );
  }

  /// Una estimación grosera del tamaño, para que el rango de zoom no se elija
  /// a ciegas.
  String _estimacion() {
    final niveles = (_maxZoom - _minZoom).round();
    final factor = 1 << (2 * niveles.clamp(0, 12));
    if (factor < 64) return 'pocos MB';
    if (factor < 4096) return 'decenas de MB';
    return 'cientos de MB — puede tardar mucho con datos móviles';
  }
}
