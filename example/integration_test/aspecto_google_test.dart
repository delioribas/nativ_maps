// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nativ_maps_example/config.dart';
import 'package:nativ_maps_google/nativ_maps_google.dart';

/// Los mismos sitios con el estilo de AWS y con `applyGoogleLook`.
///
/// Como `recorrido_test.dart`, no compara píxeles: deja cada vista en pantalla
/// y escribe `CAPTURA: <nombre>` para capturarla desde fuera, junto a una
/// captura de la app de Google Maps en el mismo punto.
///
/// Google usa teselas de 256 px y MapLibre de 512: el z15 de Google es el z14
/// de aquí.
///
/// ```sh
/// flutter test integration_test/aspecto_google_test.dart -d <dispositivo> \
///   --dart-define=ALS_API_KEY=... --dart-define=ALS_REGION=us-east-1
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> hold(WidgetTester tester, int seconds) async {
    for (var i = 0; i < seconds * 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  final paradas = <(String, LatLng, double)>[
    ('z11-ciudad', LatLng(-0.1825, -78.484), 11),
    ('z14-carolina', LatLng(-0.1825, -78.484), 14),
    ('z16-edificios', LatLng(-0.1745, -78.4835), 16),
  ];

  testWidgets('aspecto Google: los mismos sitios, con y sin la paleta', (
    tester,
  ) async {
    NativMapController? mapa;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NativMap(
            styleUrl: Config.maps.maps.styleDescriptorUrl(MapStyle.standard)!,
            initialCameraPosition: CameraPosition(
              target: paradas.first.$2,
              zoom: paradas.first.$3,
            ),
            onMapCreated: (c) => mapa = c,
          ),
        ),
      ),
    );
    await hold(tester, 10);

    for (final aspecto in <String>['aws', 'google']) {
      if (aspecto == 'google') {
        final informe = await mapa!.applyGoogleLook();
        debugPrint('INFORME: $informe');
        expect(informe.isComplete, isTrue, reason: '$informe');
      }
      for (final (nombre, centro, zoom) in paradas) {
        await mapa!.moveCamera(CameraUpdate.newLatLngZoom(centro, zoom));
        await hold(tester, 8);
        debugPrint('CAPTURA: $aspecto-$nombre');
        await hold(tester, 4);
      }
    }

    expect(tester.takeException(), isNull);
  });
}
