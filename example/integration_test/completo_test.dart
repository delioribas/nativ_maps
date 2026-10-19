// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:convert';
import 'dart:io' show HttpClient, Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nativ_maps_example/main.dart' as app;
import 'package:nativ_maps_example/widgets/demo_scaffold.dart';
import 'package:nativ_maps_flutter/nativ_maps_flutter.dart';

/// Los nueve demos, con todos sus botones, de principio a fin.
///
/// Lo que la prueba no puede hacer por sí misma lo pide por el registro, para
/// que lo haga un vigilante desde fuera:
///
/// | Línea | Qué hace el vigilante |
/// |---|---|
/// | `CAPTURA: <nombre>` | captura la pantalla |
/// | `GESTO: toque <x> <y>` | un toque **nativo**, en píxeles físicos |
/// | `GESTO: mantener <x> <y>` | una pulsación larga nativa |
/// | `GESTO: arrastrar <x1> <y1> <x2> <y2> <ms>` | un arrastre nativo, sin esperar a que acabe |
/// | `RED: off` / `RED: on` | modo avión |
/// | `ROTAR: horizontal` / `ROTAR: vertical` | gira la pantalla |
///
/// El vigilante es `tool/vigilante.py`. Cuenta las órdenes que ya cumplió y la
/// prueba espera a cada una antes de seguir: con esperas fijas, una captura
/// lenta dejaba en cola el toque siguiente, la prueba comprobaba antes de que
/// ocurriera, y en cada pasada fallaba algo distinto. Sin vigilante, vuelve a
/// las esperas fijas.
///
/// Los gestos, la red y el giro solo existen en Android, donde `adb` los
/// hace de verdad. En iOS el simulador no admite toques desde fuera sin
/// permiso de accesibilidad, así que esos pasos se saltan y se dice.
///
/// No se para en el primer fallo: apunta cada uno y los enseña todos al
/// final, para que una pasada sirva para ver el estado entero.
///
/// ```sh
/// ALS_API_KEY=... python3 tool/vigilante.py \
///   android emulator-5554 completo_test.dart /tmp/capturas
/// ```
void main() {
  // Sin esto, el binding de las pruebas en vivo se traga los toques reales
  // del dispositivo —los de `adb`— y el mapa nativo no los recibe nunca.
  IntegrationTestWidgetsFlutterBinding.ensureInitialized()
          .shouldPropagateDevicePointerEvents =
      true;

  final gestos = Platform.isAndroid;

  // Donde el vigilante cuenta lo que ya hizo. `10.0.2.2` es el ordenador
  // visto desde el emulador.
  final vigilante = Uri.parse(
    'http://${Platform.isAndroid ? '10.0.2.2' : '127.0.0.1'}:18300/hechas',
  );

  testWidgets('los nueve demos, completos', (tester) async {
    final fallos = <String>[];

    Future<void> hold(int milliseconds) async {
      for (var i = 0; i < milliseconds ~/ 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    /// Espera a que termine la petición en curso: los demos enseñan una
    /// barra de progreso mientras tanto.
    Future<void> esperarCarga({int maximo = 25000}) async {
      await hold(800);
      for (var t = 0; t < maximo; t += 200) {
        if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
        await hold(200);
      }
      await hold(1200);
    }

    void revisar(String paso) {
      final excepcion = tester.takeException();
      if (excepcion != null) fallos.add('$paso: excepción $excepcion');
      final tarjetas = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_TarjetaDeError',
      );
      if (tarjetas.evaluate().isNotEmpty) {
        final texto = tester
            .widgetList<Text>(
              find.descendant(of: tarjetas.first, matching: find.byType(Text)),
            )
            .map((t) => t.data)
            .join(' · ');
        debugPrint('ERROR_VISIBLE: $paso: $texto');
        fallos.add('$paso: $texto');
      }
    }

    void comprobar(bool condicion, String que) {
      if (!condicion) {
        debugPrint('FALLO: $que');
        fallos.add(que);
      }
    }

    // Las órdenes escritas para el vigilante.
    var ordenes = 0;

    Future<int?> cumplidas() => tester.runAsync<int?>(() async {
      final cliente = HttpClient()
        ..connectionTimeout = const Duration(seconds: 2);
      try {
        final respuesta = await (await cliente.getUrl(vigilante)).close();
        return int.tryParse(
          (await respuesta.transform(utf8.decoder).join()).trim(),
        );
      } on Object {
        return null;
      } finally {
        cliente.close(force: true);
      }
    });

    /// Escribe una orden para el vigilante y espera a que la cumpla.
    ///
    /// Si no contesta —no lo hay, o el modo avión corta también el camino
    /// hasta el ordenador—, espera [sinVigilante] y sigue; la orden siguiente
    /// vuelve a preguntar.
    Future<void> orden(String linea, {int sinVigilante = 3000}) async {
      ordenes++;
      debugPrint(linea);
      final limite = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(limite)) {
        final hechas = await cumplidas();
        if (hechas == null) {
          await hold(sinVigilante);
          return;
        }
        if (hechas >= ordenes) return;
        await hold(100);
      }
      debugPrint('AVISO: el vigilante no confirmó «$linea» en 30 s');
    }

    Future<void> captura(String nombre) => orden('CAPTURA: $nombre');

    /// Busca [finder] desplazando lo que haga falta: el panel y el menú son
    /// listas perezosas, y lo que no se ve todavía no existe.
    Future<Finder> alcanzar(Finder finder) async {
      if (finder.evaluate().isEmpty) {
        final listas = find.byType(Scrollable).evaluate().toList();
        for (var i = listas.length - 1; i >= 0; i--) {
          try {
            await tester.scrollUntilVisible(
              finder,
              120,
              scrollable: find.byType(Scrollable).at(i),
              maxScrolls: 30,
            );
            break;
          } on StateError {
            // En esta lista no está; se prueba la siguiente.
          }
        }
      }
      await tester.ensureVisible(finder.first);
      return finder.first;
    }

    Future<void> pulsar(String texto, {bool esperar = true}) async {
      final boton = await alcanzar(find.text(texto));
      await hold(300);
      await tester.tap(boton);
      // Sin dejar pasar fotogramas, un diálogo que se cierra sigue encima y
      // se traga el siguiente toque.
      if (esperar) {
        await esperarCarga();
      } else {
        await hold(1000);
      }
      revisar(texto);
    }

    /// Un punto del mapa visible, en proporción al hueco que deja el panel.
    Offset enMapa(double fx, double fy, {double panel = 250}) {
      final r = tester.getRect(find.byType(NativMap));
      return Offset(r.left + r.width * fx, r.top + (r.height - panel) * fy);
    }

    Future<bool> gesto(String tipo, Offset logico) async {
      if (!gestos) {
        debugPrint('OMITIDO en iOS: gesto $tipo');
        return false;
      }
      final dpr = tester.view.devicePixelRatio;
      await orden(
        'GESTO: $tipo ${(logico.dx * dpr).round()} '
        '${(logico.dy * dpr).round()}',
        sinVigilante: 1000,
      );
      // Ya ocurrió: lo que queda es que la app lo procese.
      await hold(tipo == 'mantener' ? 3000 : 1500);
      return true;
    }

    /// El valor de un [Dato] del panel, por su etiqueta.
    String? dato(String etiqueta) => tester
        .widgetList<Dato>(find.byType(Dato))
        .where((d) => d.etiqueta == etiqueta)
        .firstOrNull
        ?.valor;

    Future<bool> arrastrar(Offset desde, Offset hasta, int ms) async {
      if (!gestos) {
        debugPrint('OMITIDO en iOS: arrastrar');
        return false;
      }
      final dpr = tester.view.devicePixelRatio;
      int px(double v) => (v * dpr).round();
      await orden(
        'GESTO: arrastrar ${px(desde.dx)} ${px(desde.dy)} '
        '${px(hasta.dx)} ${px(hasta.dy)} $ms',
        sinVigilante: 0,
      );
      // Vuelve a mitad del arrastre: lo que sigue se ve con el mapa en
      // movimiento.
      await hold(ms ~/ 2);
      return true;
    }

    /// El valor de un [Dato] aunque el panel se haya desplazado y ya no
    /// esté construido: sube el panel hasta él.
    Future<String?> leerDato(String etiqueta) async {
      if (dato(etiqueta) == null) {
        final panel = find.descendant(
          of: find.byType(PanelDeResultados),
          matching: find.byType(Scrollable),
        );
        if (panel.evaluate().isNotEmpty) {
          try {
            await tester.scrollUntilVisible(
              find.text(etiqueta),
              -120,
              scrollable: panel.first,
              maxScrolls: 20,
            );
          } on StateError {
            // No está en el panel.
          }
          await hold(300);
        }
      }
      return dato(etiqueta);
    }

    bool hayTexto(String parte) =>
        find.textContaining(parte).evaluate().isNotEmpty;

    Future<void> abrir(String demo) async {
      final entrada = await alcanzar(find.text(demo));
      await hold(300);
      await tester.tap(entrada);
      await hold(9000);
      revisar('abrir $demo');
    }

    Future<void> volver() async {
      await tester.pageBack();
      await hold(2000);
    }

    app.main();
    await hold(6000);
    await captura('00-inicio');

    // ── 1 · Mapa básico ─────────────────────────────────────────────────
    await abrir('Mapa básico');
    await captura('01-basico-standard');
    for (final estilo in <String>['Monochrome', 'Hybrid', 'Satellite']) {
      await pulsar(estilo);
      await hold(5000);
      await captura('01-basico-${estilo.toLowerCase()}');
    }
    await pulsar('Standard');
    await pulsar('Dark');
    await hold(5000);
    await captura('01-basico-dark');
    await pulsar('Light');
    await pulsar('google');
    await hold(5000);
    await captura('01-basico-aspecto-google');
    await pulsar('aws');
    for (final (grupo, valor) in <(String, String)>[
      ('trafico', 'Congestion'),
      ('relieve', 'Hillshade'),
      ('edificios', 'Buildings3D'),
      ('poi', 'VeryDense'),
    ]) {
      await pulsar(valor);
      await hold(5000);
      await captura('01-basico-$grupo');
    }
    await tester.tap(find.byTooltip('Miniatura del servidor'));
    // La pinta el servidor: puede tardar, y no hay barra de progreso que
    // esperar. Se espera al diálogo, con límite.
    for (var t = 0; t < 30 && !hayTexto('GetStaticMap'); t++) {
      await hold(500);
    }
    comprobar(hayTexto('GetStaticMap'), 'mapa básico: no salió la miniatura');
    comprobar(hayTexto('image/'), 'mapa básico: la miniatura no es imagen');
    await captura('01-basico-miniatura');
    await pulsar('Cerrar', esperar: false);
    await volver();

    // ── 2 · Superposiciones ─────────────────────────────────────────────
    await abrir('Superposiciones');
    await pulsar('Marcadores');
    await hold(2000);
    await captura('02-marcadores');
    // El marcador sencillo está en el centro de la cámara, que el relleno
    // inferior de 200 sube; se toca un poco por encima de la punta.
    final centro = enMapa(0.5, 0.5, panel: 200);
    if (await gesto('toque', centro.translate(0, -18))) {
      comprobar(
        (await leerDato('Último toque')) == 'marcador · sencillo',
        'superposiciones: el toque al marcador no llegó a onMarkerTap',
      );
      comprobar(
        hayTexto('Marcador sencillo'),
        'superposiciones: no se abrió el globo del marcador',
      );
      await captura('02-globo');
    }
    // El de globo a medida, a 600 m al suroeste: ~63 px a z13 en Quito.
    if (await gesto('toque', centro.translate(-44, 44 - 18))) {
      comprobar(
        hayTexto('Con iconos, botones, lo que sea.'),
        'superposiciones: no se abrió el globo a medida',
      );
      await captura('02-globo-a-medida');
      if (hayTexto('Un botón')) {
        await pulsar('Un botón', esperar: false);
        await hold(1000);
        comprobar(
          (await leerDato('Último toque')) == 'botón dentro del globo',
          'superposiciones: el botón dentro del globo no respondió',
        );
      }
    }
    if (gestos) {
      await orden('ROTAR: horizontal', sinVigilante: 0);
      await hold(7000);
      await captura('02-girada');
      await orden('ROTAR: vertical', sinVigilante: 0);
      await hold(7000);
      comprobar(
        hayTexto('3 marcadores'),
        'superposiciones: tras girar la pantalla se perdió el recuento',
      );
      await captura('02-vuelta-a-vertical');
    }
    // Un toque en un sitio vacío: llega a onTap y cierra el globo abierto.
    if (await gesto('toque', enMapa(0.12, 0.1, panel: 200))) {
      comprobar(
        (await leerDato('Último toque') ?? '').startsWith('mapa ·'),
        'superposiciones: onTap no llegó',
      );
      comprobar(
        !hayTexto('Con iconos, botones, lo que sea.'),
        'superposiciones: tocar el mapa no cerró el globo',
      );
    }
    await pulsar('Polilíneas');
    await pulsar('Polígono + agujero');
    await pulsar('Círculo 500 m');
    await hold(2000);
    await captura('02-lineas-y-areas');
    // Un vértice de la línea continua lejos de los marcadores —a 1 km caía
    // sobre la etiqueta de «con rumbo», y entonces gana el marcador, como
    // debe—: 1,6 km a rumbo 78°, ~164 px a la derecha y ~35 px arriba.
    if (await gesto('toque', centro.translate(164, -35))) {
      comprobar(
        (await leerDato('Último toque') ?? '').startsWith('línea ·'),
        'superposiciones: el toque a la polilínea no llegó',
      );
    }
    // La discontinua: 1 km al sur, ~105 px por debajo del centro.
    if (await gesto('toque', centro.translate(0, 105))) {
      comprobar(
        (await leerDato('Último toque')) == 'línea · discontinua',
        'superposiciones: el toque a la línea discontinua no llegó',
      );
    }
    // Con un globo abierto, quitar su marcador tiene que cerrarlo.
    if (await gesto('toque', centro.translate(0, -18))) {
      comprobar(
        hayTexto('Marcador sencillo'),
        'superposiciones: no se abrió el globo antes de limpiar',
      );
    }
    await pulsar('Limpiar');
    comprobar(
      !hayTexto('Marcador sencillo'),
      'superposiciones: el globo se quedó abierto tras quitar su marcador',
    );
    await pulsar('300 vehículos');
    await hold(3000);
    comprobar(
      hayTexto('300 marcadores'),
      'superposiciones: no aparecen los 300',
    );
    await captura('02-agrupados');
    await pulsar('Limpiar');
    await pulsar('Mapa de calor');
    await hold(3000);
    await captura('02-calor');
    await pulsar('Limpiar');
    await pulsar('Marcadores');
    await pulsar('Animar', esperar: false);
    await hold(3000);
    await captura('02-animando');
    await pulsar('Limpiar');

    // Arrastrar: el marcador está a 400 m al sureste, ~30 px y ~30 px.
    await pulsar('Arrastrable');
    await hold(1500);
    await captura('02-arrastrable');
    final punta = centro.translate(30, 30 - 18);
    if (await arrastrar(punta, punta.translate(120, 70), 1600)) {
      await hold(3500);
      final soltado = await leerDato('Último toque');
      comprobar(
        (soltado ?? '').startsWith('soltado en'),
        'superposiciones: el arrastre no llegó a onDragEnd ($soltado)',
      );
      await captura('02-arrastrado');
    }
    await pulsar('Imagen anclada');
    await hold(3000);
    await captura('02-imagen-anclada');
    await pulsar('Teselas propias');
    await hold(6000);
    await captura('02-teselas-propias');
    await pulsar('Limpiar');
    await hold(3000);
    await captura('02-limpio');
    await volver();

    // ── 3 · Búsqueda de lugares ─────────────────────────────────────────
    await abrir('Búsqueda de lugares');
    await tester.enterText(find.byType(TextField), 'Av. Amazonas');
    await esperarCarga();
    revisar('autocomplete');
    final sugerencias = find.byType(ListTile);
    comprobar(
      sugerencias.evaluate().isNotEmpty,
      'búsqueda: autocomplete no devolvió sugerencias',
    );
    await captura('03-autocompletar');
    if (sugerencias.evaluate().isNotEmpty) {
      await tester.tap(sugerencias.first);
      await esperarCarga();
      revisar('getPlace');
      await captura('03-lugar-elegido');
    }
    await tester.enterText(find.byType(TextField), 'Quicentro');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await esperarCarga();
    revisar('searchText');
    await captura('03-buscar-texto');
    FocusManager.instance.primaryFocus?.unfocus();
    await hold(800);
    for (final operacion in <String>['Geocode', 'SearchNearby', 'Suggest']) {
      await pulsar(operacion);
      await captura('03-${operacion.toLowerCase()}');
    }
    if (await gesto('mantener', enMapa(0.5, 0.4, panel: 260))) {
      await esperarCarga();
      revisar('reverseGeocode');
      await captura('03-geocodificar-al-reves');
    }
    await volver();

    // ── 3b · Elegir ubicación ───────────────────────────────────────────
    double desvio() =>
        double.tryParse((dato('Alfiler ↔ cámara') ?? '').split(' ').first) ??
        double.infinity;
    await abrir('Elegir ubicación');
    await esperarCarga();
    comprobar(
      dato('Peticiones') == '1',
      'ubicación: al cargar debe haber una petición, hay ${dato('Peticiones')}',
    );
    comprobar(
      desvio() < 3,
      'ubicación: el alfiler no cae en el centro de la cámara '
      '(${dato('Alfiler ↔ cámara')})',
    );
    comprobar(
      dato('Tipo') != null && dato('Tipo') != '—',
      'ubicación: no llegó la dirección del centro',
    );
    final centroInicial = dato('Centro');
    await captura('03b-ubicacion-inicial');
    final desde = enMapa(0.5, 0.65, panel: 220);
    if (await arrastrar(desde, desde.translate(-140, -190), 2600)) {
      comprobar(
        hayTexto('Moviendo…'),
        'ubicación: onCameraMove no llegó durante el arrastre',
      );
      await captura('03b-ubicacion-moviendo');
      await hold(4000);
      await esperarCarga();
      comprobar(
        dato('Peticiones') == '2',
        'ubicación: un arrastre tiene que ser UNA petición, van '
        '${dato('Peticiones')}',
      );
      comprobar(
        dato('Centro') != centroInicial,
        'ubicación: el centro no cambió al arrastrar',
      );
      comprobar(
        desvio() < 3,
        'ubicación: tras arrastrar, el alfiler no cae en el centro '
        '(${dato('Alfiler ↔ cámara')})',
      );
      comprobar(
        !hayTexto('Moviendo…'),
        'ubicación: se quedó en «Moviendo…» después de soltar',
      );
      await captura('03b-ubicacion-tras-arrastrar');
    }
    await volver();

    // ── 4 · Rutas y peajes ──────────────────────────────────────────────
    await abrir('Rutas y peajes');
    if (await gesto('toque', enMapa(0.3, 0.3, panel: 260))) {
      await gesto('toque', enMapa(0.7, 0.7, panel: 260));
      await esperarCarga();
      revisar('calculateRoutes');
      comprobar(hayTexto('Ruta · '), 'rutas: no se calculó la ruta');
      await captura('04-ruta-coche');
      for (final modo in <String>['Pedestrian', 'Scooter', 'Truck', 'Car']) {
        await pulsar(modo);
        comprobar(hayTexto('Ruta · '), 'rutas: sin ruta en modo $modo');
        await captura('04-ruta-${modo.toLowerCase()}');
      }
      await pulsar('evitar peajes');
      await captura('04-sin-peajes');
    }
    await volver();

    // ── 5 · Isócronas ───────────────────────────────────────────────────
    await abrir('Isócronas');
    await pulsar('Calcular');
    await captura('05-desde-aqui');
    await pulsar('hasta aquí', esperar: false);
    await pulsar('Calcular');
    await captura('05-hasta-aqui');
    await volver();

    // ── 6 · Matriz y optimización ───────────────────────────────────────
    await abrir('Matriz y optimización');
    await pulsar('Matriz 8×1');
    await captura('06-matriz');
    await pulsar('Filtrar antes (3×1)');
    await captura('06-filtrar');
    await pulsar('Optimizar paradas');
    await captura('06-optimizar');
    await pulsar('Pasarse del límite');
    try {
      // La última línea del panel queda por debajo de lo visible.
      await alcanzar(find.textContaining('0 unidades gastadas'));
    } on StateError {
      // No está: lo dice la comprobación de abajo.
    }
    comprobar(
      hayTexto('0 unidades gastadas'),
      'matriz: pasarse del límite no se cortó antes de enviar',
    );
    await captura('06-limite');
    await volver();

    // ── 7 · Pegar rastro a la calle ─────────────────────────────────────
    await abrir('Pegar rastro a la calle');
    await pulsar('Pegar a la calle');
    await captura('07-pegado');
    await pulsar('Otro rastro', esperar: false);
    await pulsar('Pegar a la calle');
    await captura('07-otro-pegado');
    await volver();

    // ── 8 · Sin conexión ────────────────────────────────────────────────
    await abrir('Sin conexión');
    await pulsar('Vaciar caché');
    await pulsar('Descargar lo visible', esperar: false);
    for (var t = 0; t < 120 && !hayTexto('Región descargada'); t++) {
      await hold(1000);
    }
    revisar('descargar región');
    comprobar(
      hayTexto('Región descargada'),
      'sin conexión: la región no terminó de descargarse en 2 min',
    );
    await pulsar('Listar');
    comprobar(!hayTexto('Regiones guardadas · 0'), 'sin conexión: no se listó');
    await captura('08-descargada');
    if (gestos) {
      // El mapa nuevo, sin red y con la caché normal vacía: solo puede
      // pintar lo que tenga la región descargada.
      await pulsar('Vaciar caché');
      await orden('RED: off', sinVigilante: 0);
      await hold(4000);
      await volver();
      await abrir('Sin conexión');
      await captura('08-sin-red');
      await orden('RED: on', sinVigilante: 0);
      await hold(5000);
    }
    final borrar = find.byIcon(Icons.delete_outline);
    while (borrar.evaluate().isNotEmpty) {
      await tester.ensureVisible(borrar.first);
      await tester.tap(borrar.first);
      await esperarCarga();
    }
    await pulsar('Listar');
    comprobar(
      hayTexto('Regiones guardadas · 0'),
      'sin conexión: las regiones no se borraron',
    );
    await captura('08-borradas');
    await volver();

    debugPrint('RESUMEN: ${fallos.length} fallo(s)');
    for (final fallo in fallos) {
      debugPrint('RESUMEN: · $fallo');
    }
    expect(fallos, isEmpty, reason: fallos.join('\n'));
  });
}
