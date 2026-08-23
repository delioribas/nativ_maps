// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:compass_maps_example/config.dart';
import 'package:compass_maps_example/demos/busqueda_demo.dart';
import 'package:compass_maps_example/demos/isocronas_demo.dart';
import 'package:compass_maps_example/demos/mapa_basico_demo.dart';
import 'package:compass_maps_example/demos/matriz_demo.dart';
import 'package:compass_maps_example/demos/rutas_demo.dart';
import 'package:compass_maps_example/demos/sin_conexion_demo.dart';
import 'package:compass_maps_example/demos/snap_demo.dart';
import 'package:compass_maps_example/demos/superposiciones_demo.dart';
import 'package:flutter/material.dart';

void main() => runApp(const CompassMapsExampleApp());

/// La app de ejemplo.
///
/// Ejercita **las 17 operaciones** de Amazon Location v2 y todo lo que el
/// widget del mapa sabe hacer. Es a la vez la demostración y la prueba de que
/// la matriz de plataformas declarada —Android e iOS— es cierta.
class CompassMapsExampleApp extends StatelessWidget {
  /// Crea la app.
  const CompassMapsExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'compass_maps',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorSchemeSeed: const Color(0xFF1E88E5),
      useMaterial3: true,
    ),
    darkTheme: ThemeData(
      colorSchemeSeed: const Color(0xFF1E88E5),
      brightness: Brightness.dark,
      useMaterial3: true,
    ),
    home: const _Inicio(),
  );
}

// Los constructores van como funciones con nombre y no como `Demo.new`
// porque un constructor con parámetro `key` no encaja en `WidgetBuilder`.
Widget _construyeMapaBasicoDemo(BuildContext _) => const MapaBasicoDemo();
Widget _construyeSuperposicionesDemo(BuildContext _) =>
    const SuperposicionesDemo();
Widget _construyeBusquedaDemo(BuildContext _) => const BusquedaDemo();
Widget _construyeRutasDemo(BuildContext _) => const RutasDemo();
Widget _construyeIsocronasDemo(BuildContext _) => const IsocronasDemo();
Widget _construyeMatrizDemo(BuildContext _) => const MatrizDemo();
Widget _construyeSnapDemo(BuildContext _) => const SnapDemo();
Widget _construyeSinConexionDemo(BuildContext _) => const SinConexionDemo();

/// Una demostración de la lista.
class _Demo {
  const _Demo({
    required this.titulo,
    required this.descripcion,
    required this.icono,
    required this.constructor,
    this.operaciones = const <String>[],
  });

  final String titulo;
  final String descripcion;
  final IconData icono;
  final WidgetBuilder constructor;
  final List<String> operaciones;
}

const _demos = <_Demo>[
  _Demo(
    titulo: 'Mapa básico',
    descripcion:
        'El widget, los estilos del catálogo, día y noche, tráfico y relieve.',
    icono: Icons.map_outlined,
    constructor: _construyeMapaBasicoDemo,
    operaciones: <String>['GetStyleDescriptor', 'GetStaticMap'],
  ),
  _Demo(
    titulo: 'Superposiciones',
    descripcion:
        'Marcadores, polilíneas, polígonos, círculos, clústeres y mapa de '
        'calor.',
    icono: Icons.layers_outlined,
    constructor: _construyeSuperposicionesDemo,
  ),
  _Demo(
    titulo: 'Búsqueda de lugares',
    descripcion:
        'Las 7 operaciones de Places, con el patrón barato de la barra de '
        'búsqueda.',
    icono: Icons.search,
    operaciones: <String>[
      'Autocomplete',
      'SearchText',
      'ReverseGeocode',
      'GetPlace',
      'Geocode',
      'SearchNearby',
      'Suggest',
    ],
    constructor: _construyeBusquedaDemo,
  ),
  _Demo(
    titulo: 'Rutas y peajes',
    descripcion: 'Ruta con indicaciones, alternativas y coste de peaje.',
    icono: Icons.route_outlined,
    operaciones: <String>['CalculateRoutes'],
    constructor: _construyeRutasDemo,
  ),
  _Demo(
    titulo: 'Isócronas',
    descripcion: 'Hasta dónde se llega en X minutos. Google no tiene esto.',
    icono: Icons.timelapse_outlined,
    operaciones: <String>['CalculateIsolines'],
    constructor: _construyeIsocronasDemo,
  ),
  _Demo(
    titulo: 'Matriz y optimización',
    descripcion:
        'Quién llega antes por carretera, y el orden óptimo de paradas.',
    icono: Icons.grid_on_outlined,
    operaciones: <String>['CalculateRouteMatrix', 'OptimizeWaypoints'],
    constructor: _construyeMatrizDemo,
  ),
  _Demo(
    titulo: 'Pegar rastro a la calle',
    descripcion: 'Un rastro GPS con ruido convertido en un recorrido real.',
    icono: Icons.timeline_outlined,
    operaciones: <String>['SnapToRoads'],
    constructor: _construyeSnapDemo,
  ),
  _Demo(
    titulo: 'Sin conexión',
    descripcion:
        'Descargar una región y usar el mapa sin red. Google no puede.',
    icono: Icons.cloud_off_outlined,
    constructor: _construyeSinConexionDemo,
  ),
];

class _Inicio extends StatelessWidget {
  const _Inicio();

  @override
  Widget build(BuildContext context) {
    if (!Config.isConfigured) return const _SinConfigurar();

    return Scaffold(
      appBar: AppBar(
        title: const Text('compass_maps'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Amazon Location v2 · región ${Config.region}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _demos.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final demo = _demos[index];
          return ListTile(
            leading: Icon(demo.icono),
            title: Text(demo.titulo),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(demo.descripcion),
                if (demo.operaciones.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: <Widget>[
                        for (final operacion in demo.operaciones)
                          _Etiqueta(operacion),
                      ],
                    ),
                  ),
              ],
            ),
            isThreeLine: demo.operaciones.isNotEmpty,
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: demo.constructor)),
          );
        },
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 11,
          fontFamily: 'monospace',
          color: scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

/// Lo que se ve sin clave: una explicación, no un mapa gris.
class _SinConfigurar extends StatelessWidget {
  const _SinConfigurar();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.key_off_outlined, size: 48),
            const SizedBox(height: 16),
            Text(
              'Falta la clave de Amazon Location',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            const Text('Arranca la app así:'),
            const SizedBox(height: 8),
            const _Codigo(
              'flutter run \\\n'
              '  --dart-define=ALS_API_KEY=tu-clave \\\n'
              '  --dart-define=ALS_REGION=us-east-1',
            ),
            const SizedBox(height: 24),
            Text(
              'La clave se saca de la consola de Amazon Location, en '
              'Claves de API. Conviene restringirla a las operaciones que '
              'usa la app y ponerle fecha de caducidad: una clave dentro '
              'de un APK se extrae en dos minutos.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}

class _Codigo extends StatelessWidget {
  const _Codigo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      texto,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
    ),
  );
}
