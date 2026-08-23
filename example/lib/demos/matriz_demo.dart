// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:async';
import 'dart:math' as math;

import 'package:compass_maps_example/config.dart';
import 'package:compass_maps_example/widgets/demo_scaffold.dart';
import 'package:compass_maps_flutter/compass_maps_flutter.dart';
import 'package:flutter/material.dart';

/// **Matriz de rutas y optimización de paradas.**
///
/// ## La pregunta que responde la matriz
///
/// «¿Cuál de mis unidades llega antes?» — **por carretera**, que es una
/// pregunta distinta de «cuál está más cerca en línea recta». La más cercana
/// en línea recta puede estar al otro lado de un río sin puente.
///
/// ## Y la que responde la optimización
///
/// «¿En qué orden hago estas veinte entregas?» Es el problema del viajante con
/// ventanas horarias y tiempos de servicio. Google no lo tiene como operación.
///
/// ## ⚠️ El coste, que es lo que sorprende
///
/// **La matriz se factura por par, no por petición.** Una matriz de 10×10 son
/// cien cálculos de ruta y cien unidades de presupuesto. Es la operación donde
/// más se separan lo que parece —una llamada— y lo que cuesta.
///
/// El botón «Filtrar antes» enseña el patrón barato: ordenar por distancia en
/// línea recta —que es gratis— y pedir la matriz solo de los tres primeros.
/// Ocho unidades de diferencia por consulta, en una app que consulta cada vez
/// que entra un aviso.
class MatrizDemo extends StatefulWidget {
  /// Crea la demostración.
  const MatrizDemo({super.key});

  @override
  State<MatrizDemo> createState() => _MatrizDemoState();
}

class _MatrizDemoState extends State<MatrizDemo> {
  CompassMapController? _mapa;
  final _rng = math.Random(7);

  late List<LatLng> _unidades;
  LatLng? _aviso;

  final List<Widget> _resultado = <Widget>[];
  bool _cargando = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _unidades = <LatLng>[
      for (var i = 0; i < 8; i++)
        Config.defaultCenter.offset(
          1500 + _rng.nextDouble() * 6000,
          _rng.nextDouble() * 360,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) => DemoScaffold(
    titulo: 'Matriz y optimización',
    cargando: _cargando,
    error: _error,
    panel: _panel(),
    child: CompassMap(
      styleUrl: Config.maps.maps.styleDescriptorUrl(MapStyle.standard)!,
      initialCameraPosition: CameraPosition(
        target: Config.defaultCenter,
        zoom: 12,
      ),
      onMapCreated: (controller) {
        _mapa = controller;
        unawaited(_dibujar());
      },
      onTap: (posicion) {
        setState(() => _aviso = posicion);
        unawaited(_dibujar());
      },
      padding: const EdgeInsets.only(bottom: 260),
    ),
  );

  Future<void> _dibujar() =>
      _mapa?.setMarkers(<Marker>[
        for (final (indice, unidad) in _unidades.indexed)
          Marker(
            markerId: MarkerId('u-$indice'),
            position: unidad,
            label: 'U$indice',
            icon: BitmapDescriptor.defaultMarkerWithHue(MarkerHue.hueAzure),
          ),
        if (_aviso != null)
          Marker(
            markerId: const MarkerId('aviso'),
            position: _aviso!,
            icon: BitmapDescriptor.defaultMarkerWithHue(MarkerHue.hueRed),
            infoWindow: const InfoWindow(title: 'Aviso'),
          ),
      ]) ??
      Future<void>.value();

  /// La matriz completa: ocho unidades contra un aviso = 8 unidades de gasto.
  Future<void> _matrizCompleta() => _ejecutar(() async {
    final aviso = _aviso;
    if (aviso == null) {
      setState(
        () => _resultado
          ..clear()
          ..add(const Dato('Falta', 'toca el mapa para poner el aviso')),
      );
      return;
    }

    final antes = Config.maps.budget.usedUnits;
    final matriz = await Config.maps.routes.calculateRouteMatrix(
      origins: _unidades,
      destinations: <LatLng>[aviso],
    );
    final gasto = Config.maps.budget.usedUnits - antes;

    final ganador = matriz.nearestDestination(0);
    // Se busca la unidad con menor duración recorriendo la columna.
    var mejor = -1;
    var mejorSegundos = double.infinity;
    for (var i = 0; i < matriz.originCount; i++) {
      final celda = matriz.cell(i, 0);
      // Una celda con error trae CEROS, y un cero parece «lo más cerca
      // posible». Comprobarlo no es opcional.
      if (!celda.isValid) continue;
      if (celda.duration.inSeconds < mejorSegundos) {
        mejorSegundos = celda.duration.inSeconds.toDouble();
        mejor = i;
      }
    }

    await _resaltar(mejor);
    setState(() {
      _resultado
        ..clear()
        ..add(Dato('Matriz', '${matriz.originCount}×1'))
        ..add(Dato('Unidades gastadas', '$gasto'))
        ..add(Dato('Celdas con error', '${matriz.errorCount}'))
        ..add(
          Dato(
            'Más cercana por carretera',
            mejor < 0 ? '—' : 'U$mejor · ${(mejorSegundos / 60).round()} min',
          ),
        );
      if (ganador != null) {
        _resultado.add(const Dato('', ''));
      }
      // La comparación que justifica la matriz.
      final porLineaRecta = _porLineaRecta(aviso).first;
      _resultado
        ..add(
          Dato(
            'Más cercana en recta',
            'U${porLineaRecta.$1} · '
                '${(porLineaRecta.$2 / 1000).toStringAsFixed(1)} km',
          ),
        )
        ..add(
          Dato(
            '¿Coinciden?',
            mejor == porLineaRecta.$1
                ? 'sí, esta vez'
                : 'NO — por eso existe la matriz',
          ),
        );
    });
  });

  /// El patrón barato: filtrar por línea recta antes de pagar la matriz.
  Future<void> _filtrarAntes() => _ejecutar(() async {
    final aviso = _aviso;
    if (aviso == null) return;

    // Este paso es GRATIS: es aritmética local, no una petición.
    final candidatos = _porLineaRecta(aviso).take(3).toList();

    final antes = Config.maps.budget.usedUnits;
    final matriz = await Config.maps.routes.calculateRouteMatrix(
      origins: <LatLng>[for (final c in candidatos) _unidades[c.$1]],
      destinations: <LatLng>[aviso],
    );
    final gasto = Config.maps.budget.usedUnits - antes;

    var mejor = -1;
    var mejorSegundos = double.infinity;
    for (var i = 0; i < matriz.originCount; i++) {
      final celda = matriz.cell(i, 0);
      if (celda.isValid && celda.duration.inSeconds < mejorSegundos) {
        mejorSegundos = celda.duration.inSeconds.toDouble();
        mejor = candidatos[i].$1;
      }
    }

    await _resaltar(mejor);
    setState(() {
      _resultado
        ..clear()
        ..add(const Dato('Paso 1', 'ordenar por recta — GRATIS'))
        ..add(Dato('Paso 2', 'matriz de solo ${candidatos.length}'))
        ..add(Dato('Unidades gastadas', '$gasto en vez de 8'))
        ..add(
          Dato(
            'Elegida',
            mejor < 0 ? '—' : 'U$mejor · ${(mejorSegundos / 60).round()} min',
          ),
        );
    });
  });

  /// El orden óptimo para visitar todas las unidades como si fueran paradas.
  Future<void> _optimizar() => _ejecutar(() async {
    final antes = Config.maps.budget.usedUnits;
    final respuesta = await Config.maps.routes.optimizeWaypoints(
      origin: Config.defaultCenter,
      waypoints: <OptimizationWaypoint>[
        for (final (indice, unidad) in _unidades.indexed)
          OptimizationWaypoint(
            id: 'parada-$indice',
            position: unidad,
            // El campo que más se olvida y el que más cambia el
            // resultado: sin él, la optimización planifica como si
            // descargar fuera instantáneo.
            serviceDuration: const Duration(minutes: 8),
          ),
      ],
    );
    final gasto = Config.maps.budget.usedUnits - antes;

    // La respuesta devuelve IDENTIFICADORES, no objetos: con ellos se
    // reordena la lista propia de pedidos.
    final orden = <LatLng>[
      Config.defaultCenter,
      for (final id in respuesta.orderedIds)
        _unidades[int.parse(id.split('-').last)],
    ];

    await _mapa?.setPolylines(<Polyline>[
      Polyline(
        polylineId: const PolylineId('orden'),
        points: orden,
        color: Colors.deepPurple,
        width: 4,
        patterns: <PatternItem>[PatternItem.dash(14), PatternItem.gap(8)],
      ),
    ]);

    setState(() {
      _resultado
        ..clear()
        ..add(Dato('Unidades gastadas', '$gasto'))
        ..add(
          Dato(
            'Recorrido',
            '${(respuesta.distanceMeters / 1000).toStringAsFixed(1)} km · '
                '${respuesta.duration.inMinutes} min',
          ),
        )
        ..add(Dato('Orden', respuesta.orderedIds.join(' → ')))
        ..add(
          Dato(
            'No encajaron',
            respuesta.impedingWaypointIds.isEmpty
                ? 'ninguna'
                : respuesta.impedingWaypointIds.join(', '),
          ),
        );
    });
  });

  /// El error que el paquete atrapa **antes** de enviar.
  Future<void> _pasarseDelLimite() async {
    setState(() {
      _error = null;
      _resultado.clear();
    });
    try {
      await Config.maps.routes.calculateRouteMatrix(
        origins: <LatLng>[
          for (var i = 0; i < 16; i++)
            Config.defaultCenter.offset(100.0 * i, 0),
        ],
        destinations: <LatLng>[Config.defaultCenter],
      );
    } on ArgumentError catch (error) {
      setState(() {
        _resultado
          ..clear()
          ..add(const Dato('Se pidió', '16 orígenes, sin acotar zona'))
          ..add(const Dato('Máximo', '15 orígenes / 100 destinos / 100 celdas'))
          ..add(Dato('Resultado', '${error.message}'))
          ..add(
            const Dato(
              'Lo importante',
              'no se envió nada: 0 unidades gastadas',
            ),
          );
      });
    }
  }

  /// Ordena las unidades por distancia en línea recta. Gratis.
  List<(int, double)> _porLineaRecta(LatLng destino) {
    final distancias = <(int, double)>[
      for (final (indice, unidad) in _unidades.indexed)
        (indice, unidad.distanceTo(destino)),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return distancias;
  }

  Future<void> _resaltar(int indice) async {
    if (indice < 0 || _aviso == null) return;
    await _mapa?.setPolylines(<Polyline>[
      Polyline(
        polylineId: const PolylineId('elegida'),
        points: <LatLng>[_unidades[indice], _aviso!],
        color: Colors.green,
        width: 5,
      ),
    ]);
  }

  Widget _panel() => PanelDeResultados(
    titulo: 'Matriz · se factura POR PAR',
    altura: 260,
    children: <Widget>[
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          _Boton('Matriz 8×1', _matrizCompleta),
          _Boton('Filtrar antes (3×1)', _filtrarAntes),
          _Boton('Optimizar paradas', _optimizar),
          _Boton('Pasarse del límite', _pasarseDelLimite),
        ],
      ),
      const SizedBox(height: 8),
      ..._resultado,
      if (_resultado.isEmpty)
        const Text(
          'Toca el mapa para poner un aviso y pulsa «Matriz 8×1».',
          style: TextStyle(fontSize: 12),
        ),
    ],
  );

  Future<void> _ejecutar(Future<void> Function() accion) async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await accion();
    } on CompassMapsException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }
}

class _Boton extends StatelessWidget {
  const _Boton(this.texto, this.onPressed);

  final String texto;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.tonal(
    onPressed: () => unawaited(onPressed()),
    style: FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      visualDensity: VisualDensity.compact,
    ),
    child: Text(texto, style: const TextStyle(fontSize: 12)),
  );
}
