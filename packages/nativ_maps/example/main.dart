// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

// ignore_for_file: avoid_print

import 'package:nativ_maps/nativ_maps.dart';

/// Ejemplo de `nativ_maps` desde la línea de órdenes.
///
/// Enseña que este paquete **no necesita Flutter**: sirve igual en una
/// herramienta de consola o en un servidor Dart.
///
/// ```sh
/// dart run example/main.dart TU_CLAVE us-east-1
/// ```
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('Uso: dart run example/main.dart TU_CLAVE [REGION]');
    return;
  }

  final maps = NativMaps(
    region: args.length > 1 ? args[1] : 'us-east-1',
    credentials: ApiKeyCredentials(args.first),
    language: 'es',
    // El tope de gasto no es un extra: una isócrona con cinco umbrales cuesta
    // cinco unidades y una matriz de 10×10 cuesta cien.
    budget: Budget(maxUnits: 100),
  );

  try {
    // ─── 1 · Buscar un lugar ──────────────────────────────────────────
    final busqueda = await maps.places.searchText(
      queryText: 'Aeropuerto Mariscal Sucre',
      biasPosition: LatLng(-0.1807, -78.4678),
      maxResults: 1,
    );
    if (busqueda.isEmpty) {
      print('Sin resultados.');
      return;
    }

    final destino = busqueda.places.first;
    print('📍 ${destino.title}');
    print('   ${destino.formattedAddress ?? '—'}');
    print('   ${destino.position}');

    // ─── 2 · Calcular una ruta hasta él ───────────────────────────────
    //
    // Aquí está la tesis del paquete: `destino.position` es un `LatLng` de
    // este mismo paquete y entra directamente en `calculateRoutes`. No hay
    // conversión, que es donde se cuelan los errores de orden de coordenadas.
    final ruta = (await maps.routes.calculateRoutes(
      origin: LatLng(-0.1807, -78.4678),
      destination: destino.position!,
      legAdditionalFeatures: const <RouteFeature>[RouteFeature.tolls],
    )).best;

    if (ruta != null) {
      print(
        '\n🛣  ${ruta.distanceKm.toStringAsFixed(1)} km · '
        '${ruta.duration.inMinutes} min',
      );
      print('   Por: ${ruta.majorRoadLabels.join(' · ')}');
      print('   Puntos de la línea: ${ruta.points.length}');
      if (ruta.tolls.isNotEmpty) {
        print('   Peajes: ${ruta.tollCostByCurrency}');
      }
    }

    // ─── 3 · Una isócrona, que Google no tiene ────────────────────────
    final zona = await maps.routes.calculateIsolines(
      origin: LatLng(-0.1807, -78.4678),
      thresholds: Thresholds.time(const <Duration>[Duration(minutes: 10)]),
      // Sin `maxPoints` —que ya viene por defecto— una isócrona larga trae
      // miles de vértices.
      granularity: const IsolineGranularity(maxPoints: 120),
    );
    final isocrona = zona.isolines.first;
    print(
      '\n⏱  Alcanzable en 10 min: ${isocrona.pointCount} vértices en '
      '${isocrona.polygons.length} polígono(s)',
    );

    // ─── 4 · La URL del estilo, para MapLibre ─────────────────────────
    final estilo = maps.maps.styleDescriptorUrl(
      MapStyle.standard,
      colorScheme: MapColorScheme.dark,
      traffic: MapTraffic.congestion,
    );
    print('\n🗺  Estilo oscuro con tráfico:');
    // La URL lleva la clave dentro: aquí se enmascara antes de imprimirla.
    print('   ${estilo?.replaceAll(RegExp('key=[^&]*'), 'key=…')}');

    print(
      '\n💰 Gastado: ${maps.budget.usedUnits} de '
      '${maps.budget.maxUnits} unidades',
    );
  } on AlsApiException catch (e) {
    // `hint` lleva escrita la causa concreta, incluidos los tres motivos
    // distintos que producen el mismo 403.
    print('❌ ${e.operation} → ${e.statusCode}: ${e.message}');
    if (e.hint != null) print('   ${e.hint}');
  } on BudgetExhaustedException catch (e) {
    print('❌ $e');
  } on NativMapsConfigurationException catch (e) {
    print('❌ ${e.message}');
  } finally {
    maps.close();
  }
}
