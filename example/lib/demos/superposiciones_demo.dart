// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:async';
import 'dart:math' as math;

import 'package:compass_maps_example/config.dart';
import 'package:compass_maps_example/widgets/demo_scaffold.dart';
import 'package:compass_maps_flutter/compass_maps_flutter.dart';
import 'package:flutter/material.dart';

/// Todas las superposiciones, incluidas las dos que Google hace peor.
///
/// ## Lo que enseña
///
/// | Superposición | Nota |
/// |---|---|
/// | `Marker` | con rumbo, etiqueta y globo de información a medida |
/// | `Polyline` | continua y discontinua, con extremos y uniones |
/// | `Polygon` | con agujeros |
/// | `Circle` | radio en **metros**, geodésico |
/// | `ClusterManager` | **agrupado nativo**, en el motor y no en Dart |
/// | `Heatmap` | **capa nativa**, con rampa de color propia |
///
/// ## Y una cosa que no se ve pero importa
///
/// El botón «300 vehículos» añade trescientos marcadores en un bucle. La
/// sincronización se agrupa en **un solo** empujón por microtask, así que son
/// trescientas líneas de código y una sola llamada al motor. Con anotaciones
/// —el otro camino que ofrece MapLibre— serían trescientas llamadas.
class SuperposicionesDemo extends StatefulWidget {
  /// Crea la demostración.
  const SuperposicionesDemo({super.key});

  @override
  State<SuperposicionesDemo> createState() => _SuperposicionesDemoState();
}

class _SuperposicionesDemoState extends State<SuperposicionesDemo> {
  CompassMapController? _mapa;
  Timer? _animacion;
  String _ultimoToque = '—';
  int _marcadores = 0;

  static const _clusterId = ClusterManagerId('vehiculos');
  final _rng = math.Random(42);

  @override
  void dispose() {
    _animacion?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DemoScaffold(
    titulo: 'Superposiciones',
    panel: PanelDeResultados(
      titulo: 'Superposiciones · $_marcadores marcadores',
      altura: 200,
      children: <Widget>[
        Dato('Último toque', _ultimoToque),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _Boton('Marcadores', _anadirMarcadores),
            _Boton('Polilíneas', _anadirPolilineas),
            _Boton('Polígono + agujero', _anadirPoligono),
            _Boton('Círculo 500 m', _anadirCirculo),
            _Boton('300 vehículos', _anadirMuchos),
            _Boton('Mapa de calor', _anadirMapaDeCalor),
            _Boton('Animar', () async => _animar()),
            _Boton('Limpiar', _limpiar),
          ],
        ),
      ],
    ),
    child: CompassMap(
      styleUrl: Config.maps.maps.styleDescriptorUrl(MapStyle.standard)!,
      initialCameraPosition: CameraPosition(
        target: Config.defaultCenter,
        zoom: 13,
      ),
      onMapCreated: (controller) async {
        _mapa = controller;
        // El agrupador hay que registrarlo ANTES de añadir los marcadores
        // que lo usan.
        await controller.addClusterManager(
          const ClusterManager(
            clusterManagerId: _clusterId,
            maxZoom: 14,
            radius: 60,
          ),
        );
      },
      onTap: (posicion) =>
          setState(() => _ultimoToque = 'mapa · ${_fmt(posicion)}'),
      onMarkerTap: (marcador) => setState(
        () => _ultimoToque = 'marcador · ${marcador.markerId.value}',
      ),
      onPolylineTap: (linea) =>
          setState(() => _ultimoToque = 'línea · ${linea.polylineId.value}'),
      // Sin manejador, tocar un grupo lo abre solo. Con manejador, mandas
      // tú — pero entonces tienes que abrirlo a mano.
      onClusterTap: (grupo) =>
          setState(() => _ultimoToque = 'grupo de ${grupo.pointCount}'),
      padding: const EdgeInsets.only(bottom: 200),
    ),
  );

  // ── Marcadores ──────────────────────────────────────────────────────

  Future<void> _anadirMarcadores() async {
    final centro = Config.defaultCenter;
    await _mapa?.addMarkers(<Marker>[
      Marker(
        markerId: const MarkerId('sencillo'),
        position: centro,
        infoWindow: const InfoWindow(
          title: 'Marcador sencillo',
          snippet: 'Título y subtítulo, como en Google.',
        ),
      ),
      Marker(
        markerId: const MarkerId('con-rumbo'),
        position: centro.offset(600, 45),
        // `flat: true` pega el icono al mapa, así que gira con la calle. Es lo
        // que quiere el icono de un vehículo; sin esto se queda de frente
        // como un alfiler.
        flat: true,
        rotation: 45,
        label: 'PBA-1234',
        infoWindow: const InfoWindow(title: 'Con rumbo y matrícula'),
      ),
      Marker(
        markerId: const MarkerId('a-medida'),
        position: centro.offset(600, 225),
        infoWindow: InfoWindow(
          // Aquí está lo que se gana al reimplementar el globo como widget de
          // Flutter: cabe cualquier cosa dentro, no solo dos líneas de texto.
          builder: (context) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.local_shipping, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Globo a medida',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text('Con iconos, botones, lo que sea.'),
              TextButton(
                onPressed: () =>
                    setState(() => _ultimoToque = 'botón dentro del globo'),
                child: const Text('Un botón'),
              ),
            ],
          ),
        ),
      ),
    ]);
    _contar();
  }

  Future<void> _anadirMuchos() async {
    final centro = Config.defaultCenter;
    await _mapa?.addMarkers(<Marker>[
      for (var i = 0; i < 300; i++)
        Marker(
          markerId: MarkerId('v-$i'),
          position: centro.offset(
            _rng.nextDouble() * 6000,
            _rng.nextDouble() * 360,
          ),
          rotation: _rng.nextDouble() * 360,
          flat: true,
          // Al pertenecer a un agrupador, los agrupa el MOTOR. En
          // google_maps_flutter esto lo haría una clase en Dart recalculando
          // en cada movimiento de cámara.
          clusterManagerId: _clusterId,
        ),
    ]);
    _contar();
  }

  // ── Líneas y áreas ──────────────────────────────────────────────────

  Future<void> _anadirPolilineas() async {
    final centro = Config.defaultCenter;
    final continua = <LatLng>[
      for (var i = 0; i < 12; i++) centro.offset(200.0 * i, 30 + i * 6),
    ];
    final discontinua = <LatLng>[
      for (var i = 0; i < 12; i++) centro.offset(200.0 * i, 210 - i * 6),
    ];

    await _mapa?.setPolylines(<Polyline>[
      Polyline(
        polylineId: const PolylineId('continua'),
        points: continua,
        width: 6,
        // `round` en las uniones: en pico, un giro cerrado dibuja una púa que
        // sobresale varios píxeles.
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
      Polyline(
        polylineId: const PolylineId('discontinua'),
        points: discontinua,
        color: Colors.deepOrange,
        width: 4,
        // Cada patrón distinto va a su propia capa, porque `line-dasharray`
        // no admite expresiones basadas en datos.
        patterns: <PatternItem>[PatternItem.dash(16), PatternItem.gap(10)],
      ),
    ]);
  }

  Future<void> _anadirPoligono() async {
    final centro = Config.defaultCenter;
    await _mapa?.addPolygon(
      Polygon(
        polygonId: const PolygonId('zona'),
        points: <LatLng>[
          for (var i = 0; i < 6; i++) centro.offset(2000, i * 60.0),
        ],
        holes: <List<LatLng>>[
          <LatLng>[for (var i = 0; i < 6; i++) centro.offset(700, i * 60.0)],
        ],
        fillColor: Colors.purple.withValues(alpha: 0.25),
        strokeColor: Colors.purple,
        strokeWidth: 2,
      ),
    );
  }

  Future<void> _anadirCirculo() async {
    await _mapa?.addCircle(
      Circle(
        circleId: const CircleId('cobertura'),
        center: Config.defaultCenter,
        // METROS sobre el terreno, no píxeles: al alejar el mapa, el círculo
        // sigue midiendo 500 m de verdad.
        radius: 500,
        fillColor: Colors.green.withValues(alpha: 0.2),
        strokeColor: Colors.green,
      ),
    );
  }

  Future<void> _anadirMapaDeCalor() async {
    final centro = Config.defaultCenter;
    await _mapa?.addHeatmap(
      Heatmap(
        heatmapId: const HeatmapId('incidencias'),
        data: <({LatLng point, double? weight})>[
          for (var i = 0; i < 400; i++)
            (
              point: centro.offset(
                _rng.nextDouble() * _rng.nextDouble() * 5000,
                _rng.nextDouble() * 360,
              ),
              weight: _rng.nextDouble(),
            ),
        ],
        radius: 36,
        // La rampa se puede cambiar entera. En google_maps_flutter el mapa de
        // calor es un tipo cerrado con muy pocos mandos.
        gradient: const <(double, Color)>[
          (0.0, Color(0x00000000)),
          (0.3, Color(0xFF2962FF)),
          (0.6, Color(0xFF00E676)),
          (0.85, Color(0xFFFFD600)),
          (1.0, Color(0xFFD50000)),
        ],
      ),
    );
  }

  // ── Movimiento ──────────────────────────────────────────────────────

  /// Mueve los marcadores como lo haría un rastreo real.
  ///
  /// `copyWith` conserva el identificador, que es lo que hace que el marcador
  /// se **mueva** en vez de duplicarse dejando el anterior clavado.
  void _animar() {
    _animacion?.cancel();
    _animacion = Timer.periodic(const Duration(milliseconds: 900), (_) async {
      final mapa = _mapa;
      if (mapa == null) return;
      final actuales = mapa.markers;
      if (actuales.isEmpty) return;

      await mapa.addMarkers(<Marker>[
        for (final marcador in actuales)
          marcador.copyWith(
            position: marcador.position.offset(
              40 + _rng.nextDouble() * 60,
              marcador.rotation + (_rng.nextDouble() * 40 - 20),
            ),
            rotation: (marcador.rotation + (_rng.nextDouble() * 40 - 20)) % 360,
          ),
      ]);
    });
  }

  Future<void> _limpiar() async {
    _animacion?.cancel();
    final mapa = _mapa;
    if (mapa == null) return;
    await mapa.clearMarkers();
    await mapa.clearPolylines();
    await mapa.clearPolygons();
    await mapa.clearCircles();
    await mapa.removeHeatmap(const HeatmapId('incidencias'));
    _contar();
  }

  void _contar() => setState(() => _marcadores = _mapa?.markers.length ?? 0);

  static String _fmt(LatLng p) =>
      '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';
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
