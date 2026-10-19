// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nativ_maps_example/main.dart' as app;

/// Un recorrido por las superposiciones en un dispositivo o simulador real.
///
/// No comprueba píxeles: deja cada estado en pantalla el tiempo suficiente
/// para capturarlo desde fuera (`xcrun simctl io … screenshot` o `adb exec-out
/// screencap`), que es lo único que ve lo que pinta el motor nativo. Lo que sí
/// comprueba es que nada lanza en el camino.
///
/// ```sh
/// flutter test integration_test/recorrido_test.dart -d <dispositivo> \
///   --dart-define=ALS_API_KEY=... --dart-define=ALS_REGION=us-east-1
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> hold(WidgetTester tester, int seconds) async {
    for (var i = 0; i < seconds * 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> press(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).first);
    await hold(tester, 2);
  }

  testWidgets('superposiciones: marcadores, líneas, áreas, grupos y calor', (
    tester,
  ) async {
    app.main();
    await hold(tester, 6);

    await press(tester, 'Superposiciones');
    await hold(tester, 8);

    // 1 · Marcadores, líneas y áreas.
    for (final label in <String>[
      'Marcadores',
      'Polilíneas',
      'Polígono + agujero',
      'Círculo 500 m',
    ]) {
      await press(tester, label);
    }
    debugPrint('RECORRIDO: superposiciones');
    await hold(tester, 10);

    // 2 · Agrupado nativo.
    await press(tester, 'Limpiar');
    await press(tester, '300 vehículos');
    debugPrint('RECORRIDO: grupos');
    await hold(tester, 10);

    // 3 · Mapa de calor.
    await press(tester, 'Limpiar');
    await press(tester, 'Mapa de calor');
    debugPrint('RECORRIDO: calor');
    await hold(tester, 10);

    expect(tester.takeException(), isNull);
  });
}
