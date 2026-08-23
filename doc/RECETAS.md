# Recetas

Cada receta es **autocontenida y copiable**: un problema, el código completo y
la explicación de por qué así y no de otra forma.

Todas dan por hecho:

```dart
import 'package:nativ_maps_flutter/nativ_maps_flutter.dart';

final maps = NativMaps(
  region: 'us-east-1',
  credentials: const ApiKeyCredentials('tu-clave'),
  language: 'es',
  budget: Budget(maxUnits: 500),
);
```

---

## Índice

**Mapa** — [1](#1--el-mapa-mínimo) · [2](#2--día-y-noche) · [3](#3--tráfico-relieve-y-edificios-3d) · [4](#4--un-mapa-limpio-de-fondo-para-datos-propios) · [5](#5--miniatura-sin-mapa-en-pantalla) · [6](#6--encuadrar-un-conjunto-de-puntos) · [7](#7--retocar-el-estilo-en-caliente)

**Marcadores** — [8](#8--un-marcador-con-globo) · [9](#9--un-globo-a-medida) · [10](#10--icono-propio-desde-un-asset) · [11](#11--mover-un-vehículo-sin-duplicarlo) · [12](#12--miles-de-marcadores-agrupados) · [13](#13--mapa-de-calor)

**Formas** — [14](#14--polilínea-continua-y-discontinua) · [15](#15--polígono-con-agujero) · [16](#16--círculo-de-radio-en-metros) · [17](#17--geovalla-comprobar-si-un-punto-está-dentro)

**Búsqueda** — [18](#18--barra-de-búsqueda-el-patrón-barato) · [19](#19--buscar-por-texto-y-pintar-los-resultados) · [20](#20--de-coordenada-a-dirección-dictable) · [21](#21--geocodificar-un-formulario-con-precisión) · [22](#22--qué-hay-cerca) · [23](#23--paginar-resultados) · [24](#24--sugerencias-que-mezclan-sitios-y-consultas)

**Rutas** — [25](#25--ruta-y-pintarla) · [26](#26--ruta-con-alternativas) · [27](#27--coste-de-peajes) · [28](#28--indicaciones-paso-a-paso) · [29](#29--ruta-de-camión-con-dimensiones) · [30](#30--hora-de-llegada-en-vez-de-salida)

**Lo que Google no da** — [31](#31--isócrona-hasta-dónde-llegó-en-8-minutos) · [32](#32--isócrona-inversa-quién-llega-hasta-aquí) · [33](#33--quién-está-más-cerca-por-carretera) · [34](#34--orden-óptimo-de-veinte-entregas) · [35](#35--pegar-un-histórico-gps-a-la-calle) · [36](#36--mapa-sin-conexión)

**Geovallas y rastreo** — [41](#41--crear-una-zona) · [42](#42--saber-si-un-punto-está-dentro-gratis) · [43](#43--evaluar-posiciones-de-verdad) · [44](#44--avisar-antes-de-que-salga-de-la-zona) · [45](#45--subir-posiciones-de-la-flota) · [46](#46--el-histórico-limpio-en-dos-pasos) · [47](#47--quién-hay-dentro-de-esta-zona-ahora) · [48](#48--detectar-una-ubicación-falseada) · [49](#49--montar-el-sistema-entero-una-vez)

**Producción** — [37](#37--proxy-que-firma-recomendado) · [38](#38--sigv4-en-el-dispositivo) · [39](#39--manejar-los-errores-bien) · [40](#40--no-llevarse-un-susto-en-la-factura)

---

# Mapa

## 1 · El mapa mínimo

```dart
class Pantalla extends StatefulWidget {
  const Pantalla({super.key});
  @override
  State<Pantalla> createState() => _PantallaState();
}

class _PantallaState extends State<Pantalla> {
  NativMapController? _mapa;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: NativMap(
          styleUrl: maps.maps.styleDescriptorUrl(MapStyle.standard)!,
          initialCameraPosition: CameraPosition(
            target: LatLng(-0.1807, -78.4678),
            zoom: 13,
          ),
          onMapCreated: (c) => _mapa = c,
          // Engánchalo siempre: sin esto, un estilo que no carga deja un
          // rectángulo gris sin ninguna explicación, y las tres causas
          // —clave, región, red— son todas de configuración.
          onStyleError: (e) => debugPrint('$e'),
        ),
      );
}
```

`initialCameraPosition` **solo se lee al crear el mapa**. Para moverlo después,
el controlador.

---

## 2 · Día y noche

```dart
final estilos = maps.maps.dayNightStyleUrls(MapStyle.standard);

NativMap(
  styleUrl: Theme.of(context).brightness == Brightness.dark
      ? estilos.dark!
      : estilos.light!,
  ...
);
```

**Lo renderiza el servidor**, no es un filtro sobre teselas claras: las
etiquetas siguen siendo legibles. Cambiar la cadena recarga el estilo y
**reinstala las superposiciones solo**.

---

## 3 · Tráfico, relieve y edificios 3D

```dart
final url = maps.maps.styleDescriptorUrl(
  MapStyle.standard,
  traffic: MapTraffic.congestion,      // el color de las vías por congestión
  terrain: MapTerrain.hillshade,       // sombreado del relieve
  buildings: MapBuildings.buildings3d, // extrusión de edificios
  contourDensity: MapContourDensity.medium,
)!;
```

Los cuatro los dibuja **el servidor dentro del mismo estilo**: no hay segunda
petición ni capa superpuesta. En `google_maps_flutter`, el tráfico es un
interruptor y los otros tres no existen.

---

## 4 · Un mapa limpio, de fondo para datos propios

```dart
final url = maps.maps.styleDescriptorUrl(
  MapStyle.monochrome,
  colorScheme: MapColorScheme.dark,
  poiDensity: MapPoiDensity.off,   // ← ni un punto de interés
)!;
```

Mejor que apagar capas después: así el servidor **no los manda siquiera**.

Si necesitas solo algunas categorías:

```dart
poiDensity: MapPoiDensity.sparse,
poiCategories: const [
  MapPoiCategory.transportation,
  MapPoiCategory.accommodations,
],  // máximo 9
```

---

## 5 · Miniatura sin mapa en pantalla

```dart
final imagen = await maps.maps.staticMap(
  boundedPositions: ruta.points,   // el servidor calcula el encuadre
  width: 600,
  height: 400,
  padding: 40,
);

// Para una notificación, un PDF o un correo.
final widget = Image.memory(Uint8List.fromList(imagen.bytes));
```

`takeSnapshot` de `google_maps_flutter` exige el mapa **montado y visible**.
Esto lo pinta el servidor y funciona en segundo plano.

Con geometría encima:

```dart
final imagen = await maps.maps.staticMap(
  boundedPositions: ruta.points,
  width: 600, height: 400,
  geoJsonOverlay: jsonEncode({
    'type': 'Feature',
    'geometry': {
      'type': 'LineString',
      'coordinates': [for (final p in ruta.points) p.toLonLat()],
    },
  }),
);
```

> ⚠️ `staticMapUrl()` devuelve la URL sin descargar, pero **la URL lleva la
> clave dentro**. No la registres ni se la mandes a un tercero.

---

## 6 · Encuadrar un conjunto de puntos

```dart
final bounds = LatLngBounds.fromPoints(posiciones).padded(500);
await _mapa!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 48));
```

`fromPoints` **lanza con la lista vacía** en vez de devolver un rectángulo de
infinitos. `padded(500)` añade 500 m por lado y se recorta solo en los polos.

---

## 7 · Retocar el estilo en caliente

```dart
NativMap(
  ...
  // En onStyleLoaded, no en onMapCreated: un cambio de styleUrl recarga el
  // estilo desde el servidor y deshace todo esto.
  onStyleLoaded: () async {
    final estilo = _mapa!.style;

    await estilo.hideMatching('poi');          // apaga todo lo que sea POI
    await estilo.setColor('water', Colors.indigo.shade900);
    await estilo.setLineWidth('road-motorway', 6);

    // Para ver cómo se llaman las capas de TU estilo:
    for (final capa in await estilo.layers()) debugPrint('$capa');
  },
);
```

---

# Marcadores

## 8 · Un marcador con globo

```dart
await _mapa!.addMarker(
  Marker(
    markerId: const MarkerId('destino'),
    position: LatLng(-0.1807, -78.4678),
    icon: BitmapDescriptor.defaultMarkerWithHue(MarkerHue.hueAzure),
    infoWindow: const InfoWindow(
      title: 'Destino',
      snippet: 'Av. Amazonas y Naciones Unidas',
    ),
  ),
);
```

---

## 9 · Un globo a medida

```dart
InfoWindow(
  builder: (context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Image.network(vehiculo.foto, height: 80),
      Text(vehiculo.matricula, style: Theme.of(context).textTheme.titleSmall),
      FilledButton(onPressed: _despachar, child: const Text('Despachar')),
    ],
  ),
)
```

El globo está **reimplementado como widget de Flutter**. Se pierde el aspecto
exacto del de Google y se gana poder poner cualquier cosa dentro.

---

## 10 · Icono propio desde un asset

```dart
Future<BitmapDescriptor> _iconoDeVehiculo() async {
  final datos = await rootBundle.load('assets/vehiculo.png');
  return BitmapDescriptor.fromBytes('vehiculo', datos.buffer.asUint8List());
}

final icono = await _iconoDeVehiculo();
await _mapa!.addMarkers([
  for (final v in flota)
    Marker(markerId: MarkerId(v.id), position: v.posicion, icon: icono),
]);
```

El **nombre** es la clave con la que la imagen se registra en el estilo. Cien
marcadores con el mismo icono la suben **una vez**. Dos iconos distintos con el
mismo nombre se pisan.

---

## 11 · Mover un vehículo sin duplicarlo

```dart
Timer.periodic(const Duration(seconds: 3), (_) async {
  final posiciones = await api.posicionesDeFlota();
  await _mapa!.addMarkers([
    for (final p in posiciones)
      Marker(
        markerId: MarkerId(p.vehiculoId),   // ← el MISMO id
        position: LatLng(p.lat, p.lng),
        rotation: p.rumbo,
        flat: true,                          // gira con el mapa, como un coche
        label: p.matricula,
      ),
  ]);
});
```

**El identificador es lo que hace que se mueva en vez de duplicarse.** Con otro
id, el marcador anterior se queda clavado en el mapa.

`flat: true` pega el icono al mapa; sin él se queda siempre de frente, como un
alfiler.

---

## 12 · Miles de marcadores, agrupados

```dart
// 1 · el agrupador, ANTES de los marcadores
await _mapa!.addClusterManager(
  const ClusterManager(
    clusterManagerId: ClusterManagerId('flota'),
    maxZoom: 14,      // a partir de aquí se separan
    radius: 60,
  ),
);

// 2 · los marcadores, apuntando a él
await _mapa!.addMarkers([
  for (final v in flota)
    Marker(
      markerId: MarkerId(v.id),
      position: v.posicion,
      clusterManagerId: const ClusterManagerId('flota'),
    ),
]);
```

**Agrupa el motor, en C++ y por tesela.** En `google_maps_flutter` lo hace una
clase en Dart que recalcula en cada movimiento de cámara, y con unos miles se
nota en el desplazamiento.

Sin `onClusterTap`, tocar un grupo lo abre solo. Con manejador, mandas tú:

```dart
onClusterTap: (grupo) async {
  final zoom = await _mapa!.getClusterExpansionZoom(grupo);
  await _mapa!.animateCamera(
    CameraUpdate.newLatLngZoom(grupo.position, zoom),
  );
},
```

---

## 13 · Mapa de calor

```dart
await _mapa!.addHeatmap(
  Heatmap(
    heatmapId: const HeatmapId('incidencias'),
    data: [
      for (final i in incidencias)
        (point: i.posicion, weight: i.gravedad),   // peso null = 1
    ],
    radius: 36,
    gradient: const [
      (0.0, Color(0x00000000)),   // transparente donde no hay datos
      (0.4, Color(0xFF2962FF)),
      (0.7, Color(0xFFFFD600)),
      (1.0, Color(0xFFD50000)),
    ],
  ),
);
```

Es una **capa `heatmap` nativa**, no un tipo cerrado: la rampa, el radio y la
intensidad son tuyos.

---

# Formas

## 14 · Polilínea continua y discontinua

```dart
await _mapa!.setPolylines([
  Polyline(
    polylineId: const PolylineId('recorrido'),
    points: puntos,
    color: Colors.blue,
    width: 6,
    jointType: JointType.round,   // en pico, un giro cerrado saca una púa
    startCap: Cap.roundCap,
    endCap: Cap.roundCap,
  ),
  Polyline(
    polylineId: const PolylineId('planeado'),
    points: otros,
    patterns: [PatternItem.dash(16), PatternItem.gap(10)],
  ),
]);
```

Cada patrón distinto va a **su propia capa**, porque `line-dasharray` no admite
expresiones basadas en datos. Es automático; solo conviene no inventar veinte
patrones distintos.

---

## 15 · Polígono con agujero

```dart
await _mapa!.addPolygon(
  Polygon(
    polygonId: const PolygonId('zona'),
    points: contorno,
    holes: [huecoInterior],
    fillColor: Colors.purple.withValues(alpha: 0.25),
    strokeColor: Colors.purple,
  ),
);
```

El anillo se cierra solo: GeoJSON exige que el último punto repita al primero, y
sin cerrarlo el borde sale abierto por un lado.

---

## 16 · Círculo de radio en metros

```dart
await _mapa!.addCircle(
  Circle(
    circleId: const CircleId('cobertura'),
    center: antena,
    radius: 1500,          // METROS sobre el terreno, no píxeles
    fillColor: Colors.green.withValues(alpha: 0.2),
    strokeColor: Colors.green,
  ),
);
```

Es **geodésico**: se convierte en un polígono de 72 lados sobre la esfera. Un
círculo de píxeles cambiaría de tamaño real al alejar el mapa.

---

## 17 · Geovalla: comprobar si un punto está dentro

```dart
final zona = LatLngBounds.fromPoints(esquinas);

// Rectangular — instantáneo, sin coste
if (zona.contains(posicionDelVehiculo)) { ... }

// Circular — instantáneo, sin coste
if (centro.distanceTo(posicionDelVehiculo) <= 1500) { ... }
```

`distanceTo` es haversine local: **no cuesta nada**. Es el filtro que hay que
poner antes de cualquier operación facturada.

---

# Búsqueda

## 18 · Barra de búsqueda, el patrón barato

```dart
Timer? _debounce;

void _alEscribir(String texto) {
  _debounce?.cancel();
  if (texto.trim().length < 3) return;

  // 300 ms: por debajo se disparan peticiones a media palabra;
  // por encima se nota el retraso al escribir.
  _debounce = Timer(const Duration(milliseconds: 300), () async {
    final sugerencias = await maps.places.autocomplete(
      query: texto,
      biasPosition: posicionActual,                            // ORDENA
      filter: const SearchFilter(includeCountries: ['ECU']),   // DESCARTA
      maxResults: 6,
    );
    setState(() => _sugerencias = sugerencias);
  });
}

// Y SOLO al elegir una:
Future<void> _elegir(AutocompleteSuggestion s) async {
  final lugar = await maps.places.getPlace(s.placeId!);
  await _mapa!.animateCamera(
    CameraUpdate.newLatLngZoom(lugar.position!, 16),
  );
}
```

**`autocomplete` no devuelve coordenadas, y está bien:** el usuario todavía no
ha elegido. Se paga la segunda petición **solo por la que elige**, no por las
veinte que ve.

`biasPosition` y `filter` **no son excluyentes**: el sesgo ordena, el filtro
descarta. Lo que sí es excluyente es rellenar `boundingBox` y `circle` a la vez
dentro del filtro; se comprueba antes de enviar.

---

## 19 · Buscar por texto y pintar los resultados

```dart
final respuesta = await maps.places.searchText(
  queryText: 'gasolinera',
  biasPosition: (await _mapa!.getCameraPosition())!.target,
  maxResults: 20,
);

await _mapa!.setMarkers([
  for (final (i, lugar) in respuesta.places.indexed)
    if (lugar.position != null)
      Marker(
        markerId: MarkerId('r-$i'),
        position: lugar.position!,
        infoWindow: InfoWindow(
          title: lugar.title,
          snippet: lugar.formattedAddress,
        ),
      ),
]);

final puntos = [
  for (final l in respuesta.places) if (l.position != null) l.position!,
];
if (puntos.isNotEmpty) {
  await _mapa!.animateCamera(
    CameraUpdate.newLatLngBounds(LatLngBounds.fromPoints(puntos), 48),
  );
}
```

---

## 20 · De coordenada a dirección dictable

```dart
final lugares = await maps.places.reverseGeocode(
  posicionDelVehiculo,
  radiusMeters: 200,   // PONLO
  maxResults: 2,       // en una esquina, el 2.º suele ser la otra calle
);

if (lugares.isEmpty) return 'sin dirección conocida';

final lugar = lugares.first;

// LA comprobación que hay que hacer.
if (!(lugar.placeType?.isPrecise ?? false)) {
  return 'cerca de ${lugar.address?.locality} (aproximado)';
}

// Para dictar por radio: calle y número, sin país ni código postal.
return lugar.address?.shortLabel ?? lugar.title;
```

**Sin `radiusMeters`**, una posición en una zona sin direcciones devuelve la
localidad más próxima **aunque esté a kilómetros**, y eso se enseña igual que
una dirección exacta.

---

## 21 · Geocodificar un formulario, con precisión

```dart
final lugares = await maps.places.geocode(
  // Campo a campo da mejores resultados que texto libre cuando la dirección
  // ya viene troceada: el servicio no tiene que adivinar dónde acaba la calle.
  queryComponents: const AddressComponents(
    country: 'ECU',
    locality: 'Quito',
    street: 'Av. Amazonas',
    addressNumber: '1234',
  ),
);

final lugar = lugares.first;

// `matchScore` es lo que permite AUTOMATIZAR. Sin él, la única opción honesta
// es preguntar siempre.
if ((lugar.matchScore ?? 0) > 0.9 &&
    lugar.placeType == PlaceType.pointAddress) {
  guardar(lugar.position!);            // se acepta sola
} else {
  await pedirConfirmacion(lugares);    // se le enseña al usuario
}
```

> Los códigos de país van en **ISO alfa-3** (`ECU`), no alfa-2. El alfa-2 no da
> error: devuelve cero resultados, que es más difícil de diagnosticar.

---

## 22 · Qué hay cerca

```dart
final respuesta = await maps.places.searchNearby(
  position: centro,
  radiusMeters: 1000,   // PONLO
  filter: const SearchFilter(includeCategories: ['gas_station']),
  maxResults: 15,
);

for (final lugar in respuesta.places) {
  print('${lugar.title} · ${lugar.distanceMeters?.round()} m');
}
```

⚠️ Ordena por distancia **en línea recta**, no por carretera. Para lo segundo,
receta [33](#33--quién-está-más-cerca-por-carretera).

---

## 23 · Paginar resultados

```dart
String? testigo;
final todos = <Place>[];

do {
  final pagina = await maps.places.searchText(
    queryText: 'farmacia',
    biasPosition: centro,
    maxResults: 50,
    nextToken: testigo,   // ← con los MISMOS parámetros
  );
  todos.addAll(pagina.places);
  testigo = pagina.nextToken;
} while (testigo != null && todos.length < 200);   // pon un tope
```

Cambiar los parámetros entre páginas da resultados incoherentes. **Y cada página
es una petición facturada**: pon un tope o el bucle se lleva el presupuesto.

---

## 24 · Sugerencias que mezclan sitios y consultas

```dart
final respuesta = await maps.places.suggest(
  query: 'restau',
  biasPosition: centro,
  // Sin `core`, las sugerencias de sitio llegan solo con el título.
  // Eso es lo que las hace baratas.
  additionalFeatures: const [PlaceFeature.core],
);

for (final r in respuesta.results) {
  switch (r.type) {
    case SuggestResultType.place:
      irA(r.place!.position!);
    case SuggestResultType.query:
      // No hay un sitio que se llame «restaurantes»: hay una búsqueda.
      await maps.places.searchText(queryId: r.queryId);
  }
}
```

---

# Rutas

## 25 · Ruta y pintarla

```dart
final respuesta = await maps.routes.calculateRoutes(
  origin: aqui,
  destination: alli,
  travelMode: TravelMode.scooter,
);
final ruta = respuesta.best!;

await _mapa!.addPolyline(
  // Sin convertir nada: `ruta.points` son LatLng de este paquete.
  Polyline(polylineId: const PolylineId('ruta'), points: ruta.points, width: 6),
);
await _mapa!.animateCamera(
  CameraUpdate.newLatLngBounds(ruta.bounds!.padded(300), 56),
);

print('${ruta.distanceKm.toStringAsFixed(1)} km · ${ruta.duration.inMinutes} min');
```

`ruta.points` cose los tramos y **quita el punto repetido de cada costura**, que
si no deja un artefacto visible con extremos redondeados.

---

## 26 · Ruta con alternativas

```dart
final respuesta = await maps.routes.calculateRoutes(
  origin: aqui,
  destination: alli,
  maxAlternatives: 2,   // 0..6
);

// Las alternativas en gris y debajo; la elegida encima.
await _mapa!.setPolylines([
  for (final (i, r) in respuesta.routes.indexed)
    if (i != elegida)
      Polyline(
        polylineId: PolylineId('alt-$i'),
        points: r.points,
        color: Colors.grey,
        zIndex: 0,
      ),
  Polyline(
    polylineId: const PolylineId('elegida'),
    points: respuesta.routes[elegida].points,
    width: 7,
    zIndex: 1,
  ),
]);

// «por la Panamericana» dice más al usuario que «43 min».
print(respuesta.routes[elegida].majorRoadLabels.join(' · '));
```

---

## 27 · Coste de peajes

```dart
final ruta = (await maps.routes.calculateRoutes(
  origin: aqui,
  destination: alli,
  // Sin pedirlo, los peajes NO vienen.
  legAdditionalFeatures: const [RouteFeature.tolls, RouteFeature.summary],
)).best!;

// Mapa por moneda, no un número: una ruta internacional cruza monedas y
// sumarlas daría un valor sin significado.
ruta.tollCostByCurrency.forEach((moneda, importe) {
  print('$importe $moneda');
});

for (final peaje in ruta.tolls) {
  print('${peaje.systemRef}: ${peaje.amount} ${peaje.currency} '
        '(${peaje.paymentMethods.join(', ')})');
}
```

**Google no da esto.**

Para evitarlos:

```dart
avoid: const RouteAvoidance(tollRoads: true),
```

⚠️ No es una prohibición absoluta: si no hay alternativa, el servicio pasa igual
y lo dice en `respuesta.notices`.

---

## 28 · Indicaciones paso a paso

```dart
final ruta = (await maps.routes.calculateRoutes(
  origin: aqui,
  destination: alli,
  travelStepType: TravelStepType.turnByTurn,
  legAdditionalFeatures: const [RouteFeature.travelStepInstructions],
)).best!;

for (final paso in ruta.steps) {
  print('${paso.instruction ?? paso.type} '
        'hacia ${paso.nextRoad} · ${paso.distanceMeters.round()} m');

  // Para resaltar en el mapa el tramo de la maniobra en curso:
  final desde = paso.geometryOffset ?? 0;
}
```

Con `TravelStepType.none` la respuesta pesa mucho menos, y es lo que se quiere
si solo vas a pintar la línea.

---

## 29 · Ruta de camión con dimensiones

```dart
final ruta = (await maps.routes.calculateRoutes(
  origin: almacen,
  destination: cliente,
  travelMode: TravelMode.truck,
  travelModeOptions: const TravelModeOptions.truck(
    grossWeightKg: 18000,
    heightCm: 400,        // la que decide si cabe bajo un puente
    lengthCm: 1600,
    widthCm: 250,
    axleCount: 3,         // determina la tarifa de peaje
    hazardousCargos: ['Flammable'],
    tunnelRestrictionCode: 'C',
  ),
  legAdditionalFeatures: const [RouteFeature.tolls, RouteFeature.zones],
)).best!;
```

Un puente con gálibo de 3,5 m no aparece como cortado en el mapa: simplemente el
camión no cabe. Sin estas dimensiones, la ruta es la de un coche.

Para el «pico y placa» de Quito y restricciones equivalentes:

```dart
travelModeOptions: const TravelModeOptions.car(licensePlateLastCharacter: '7'),
```

---

## 30 · Hora de llegada en vez de salida

```dart
// «Salgo a las 8:00»
departureTime: DateTime(2026, 8, 23, 8),

// «Tengo que estar a las 9:30» → el servicio calcula cuándo salir
arrivalTime: DateTime(2026, 8, 23, 9, 30),
```

Son **excluyentes**; se comprueba antes de enviar. Sin ninguno de los dos se
usa el tráfico de este momento.

---

# Lo que Google no da

## 31 · Isócrona: hasta dónde llegó en 8 minutos

```dart
final respuesta = await maps.routes.calculateIsolines(
  origin: ultimaPosicionConocida,
  thresholds: Thresholds.time([const Duration(minutes: 8)]),
  travelMode: TravelMode.scooter,
  // El valor por defecto ya trae maxPoints: 300. NO lo quites: sin él, una
  // isócrona de 30 min trae miles de vértices y la interfaz se congela.
);

final isocrona = respuesta.isolines.first;

// ⚠️ Puede traer VARIOS polígonos: con un río sin puentes cerca, lo
// alcanzable son dos manchas separadas. Unirlas dibujaría como alcanzable
// justo el agua.
await _mapa!.setPolygons([
  for (final (i, poligono) in isocrona.polygons.indexed)
    Polygon(
      polygonId: PolygonId('zona-$i'),
      points: poligono.first,
      holes: poligono.length > 1 ? poligono.sublist(1) : const [],
      fillColor: Colors.orange.withValues(alpha: 0.25),
      strokeColor: Colors.orange,
    ),
]);
```

Para el caso simple de un solo polígono hay un atajo:

```dart
Polygon.fromIsoline(isocrona, polygonId: const PolygonId('zona'))
```

> **Se cobra por umbral.** Tres umbrales son tres unidades, no una.
> Máximo cinco.

---

## 32 · Isócrona inversa: quién llega hasta aquí

```dart
final respuesta = await maps.routes.calculateIsolines(
  destination: lugarDelAviso,   // ← destination, no origin
  arrivalTime: DateTime.now().add(const Duration(minutes: 10)),
  thresholds: Thresholds.time([const Duration(minutes: 10)]),
);

// Y ahora, quién de la flota cae dentro:
final zona = respuesta.isolines.first.outerRing;
```

**No es la misma zona que la de ida.** Las calles de sentido único hacen que
«desde dónde llego» y «hasta dónde llego» no coincidan.

---

## 33 · Quién está más cerca por carretera

```dart
// 1 · Filtrar por línea recta. GRATIS: es aritmética local.
final candidatos = [...unidades]
  ..sort((a, b) => a.distanceTo(aviso).compareTo(b.distanceTo(aviso)));

// 2 · La matriz solo de los tres primeros → 3 unidades en vez de 20.
final matriz = await maps.routes.calculateRouteMatrix(
  origins: candidatos.take(3).toList(),
  destinations: [aviso],
);

var mejor = -1;
var mejorSegundos = double.infinity;
for (var i = 0; i < matriz.originCount; i++) {
  final celda = matriz.cell(i, 0);
  // OBLIGATORIO: una celda con error trae CEROS, y un cero parece
  // «lo más cerca posible».
  if (!celda.isValid) continue;
  if (celda.duration.inSeconds < mejorSegundos) {
    mejorSegundos = celda.duration.inSeconds.toDouble();
    mejor = i;
  }
}
```

**La matriz se factura por par.** 10×10 = 100 unidades. Sin acotar zona, el
máximo es 15 orígenes, 100 destinos y 100 celdas — y se comprueba **antes de
enviar**.

La unidad más cercana en línea recta puede estar al otro lado de un río sin
puente. Por eso existe la matriz.

---

## 34 · Orden óptimo de veinte entregas

```dart
final respuesta = await maps.routes.optimizeWaypoints(
  origin: almacen,
  waypoints: [
    for (final pedido in pedidos)
      OptimizationWaypoint(
        id: pedido.id,                                   // ÚNICO
        position: pedido.posicion,
        // El campo que más se olvida y el que más cambia el resultado: sin
        // él, la optimización planifica como si descargar fuera instantáneo,
        // y una ruta de veinte entregas sale con dos horas menos.
        serviceDuration: const Duration(minutes: 8),
        appointmentTime: pedido.citaConcertada,
      ),
  ],
  departureTime: DateTime.now(),
  driver: const DriverOptions(restProfile: 'EU'),   // descansos obligatorios
);

// Devuelve IDENTIFICADORES: con ellos reordenas tu propia lista.
final ordenados = [
  for (final id in respuesta.orderedIds)
    pedidos.firstWhere((p) => p.id == id),
];

// Las que no encajan vienen APARTE: son las que hay que reprogramar.
if (respuesta.impedingWaypointIds.isNotEmpty) {
  avisar(respuesta.impedingWaypointIds);
}
```

---

## 35 · Pegar un histórico GPS a la calle

```dart
final respuesta = await maps.routes.snapToRoads(
  tracePoints: [
    for (final p in historicoDelDia)
      TracePoint(
        position: LatLng(p.lat, p.lng),
        // El GT06 manda los tres. Darle solo posiciones desperdicia la mitad
        // de la precisión: con la velocidad, el servicio distingue el carril
        // de servicio de la autopista paralela.
        headingDegrees: p.rumbo,
        speedKmh: p.velocidad,
        timestamp: p.hora,
      ),
  ],
  snapRadiusMeters: 500,   // 300 se queda corto en ciudad con edificios altos
);

// La línea limpia, lista para pintar.
await _mapa!.addPolyline(
  Polyline(polylineId: const PolylineId('recorrido'),
           points: respuesta.geometry.points),
);

// Lo dudoso NO se pinta como recorrido: pegarlo a una calle sin estar seguro
// es dibujar una calle inventada.
final fiables = respuesta.confidentPoints(minimum: 0.5);

// Lo que se facturó de verdad: 12 000 puntos son 3 peticiones.
print('${respuesta.chunkCount} petición(es)');
```

La API admite **5 000 puntos** por petición. Un histórico de un día se pasa, y
este método **trocea y cose** —con solape, para que la costura no salte a otra
calle— en vez de fallar.

---

## 36 · Mapa sin conexión

```dart
NativMap(
  ...
  offlineEnabled: true,   // sin esto, `offline` es null
);

// Descargar lo que se ve ahora
final flujo = _mapa!.offline!.downloadRegion(
  bounds: await _mapa!.getVisibleRegion(),
  minZoom: 10,
  maxZoom: 15,   // ← LA decisión: las teselas se multiplican por 4 por nivel
  name: 'Quito centro',
);

await for (final progreso in flujo) {
  setState(() => _progreso = progreso.fraction);
}

// Listar y borrar
for (final region in await _mapa!.offline!.listRegions()) {
  print('${region.name} · z${region.minZoom}-${region.maxZoom}');
}
await _mapa!.offline!.deleteRegion(id);

// Caducar: llámalo al arrancar la app.
await _mapa!.offline!.deleteStaleRegions(const Duration(days: 7));
```

De z10 a z14 son unos megabytes; de z10 a z18, **cientos**, y media hora con
datos móviles. Para rastreo de vehículos, z10–z15 basta.

> ⚠️ **Antes de enviar una app con esto**, leer la Sección 82 de los AWS Service
> Terms, comprobar qué proveedor sirve tu región, declarar la atribución también
> en el mapa guardado y fijar una caducidad. Ver el README.

---

# Producción

## 37 · Proxy que firma (recomendado)

```dart
final maps = NativMaps(
  region: 'us-east-1',
  credentials: ProxyCredentials(
    baseUrl: Uri.parse('https://api.miempresa.com/geo'),
    headers: {'Authorization': 'Bearer ${sesion.token}'},
  ),
);
```

El móvil llama a tu servidor; tu servidor firma y reenvía. **La clave nunca sale
del servidor**, que es la única forma de que no se extraiga del APK.

Tu proxy recibe la ruta tal cual (`POST /geo/v2/search-text`) y dos cabeceras
que le dicen qué firmar:

```
X-Nativ-Service: geo-places
X-Nativ-Region:  us-east-1
```

Con eso, el proxy es un reenviador transparente de unas veinte líneas.

Para las **teselas**:

```dart
NativMap(
  styleUrl: 'https://api.miempresa.com/geo/v2/styles/Standard/descriptor',
  customHeaders: {'Authorization': 'Bearer ${sesion.token}'},
  ...
);
```

---

## 38 · SigV4 en el dispositivo

```dart
import 'package:nativ_maps_sigv4/nativ_maps_sigv4.dart';

final credenciales = SigV4Credentials(
  provider: () async {
    final c = await cognito.obtenerCredenciales();
    return AwsCredentials(
      accessKeyId: c.accessKeyId,
      secretAccessKey: c.secretKey,
      sessionToken: c.sessionToken,   // OBLIGATORIO en las temporales
      expiration: c.expiration,
    );
  },
);

final maps = NativMaps(region: 'us-east-1', credentials: credenciales);
```

Y para las teselas:

```dart
NativMap(
  styleUrl: url,
  customHeaders: await credenciales.mapHeaders(
    styleUrl: url,
    region: 'us-east-1',
  ),
  ...
);
```

> ⚠️ **Estas cabeceras caducan.** Un mapa abierto durante horas dejará de cargar
> teselas nuevas. Hay que renovarlas periódicamente con
> `controller.setCustomHeaders(...)`. El proxy no tiene este problema, y por eso
> sigue siendo el camino recomendado.

---

## 39 · Manejar los errores bien

```dart
try {
  await maps.places.searchText(queryText: texto);
} on AlsApiException catch (e) {
  if (e.isConfigurationError) {
    // 400 o 403: NO reintentes. `e.hint` dice la causa concreta, incluidos
    // los tres motivos distintos que producen el mismo 403.
    registro.error('${e.operation}: ${e.message}\n${e.hint}');
    mostrar('Hay un problema de configuración del mapa.');
  } else if (e.isThrottled) {
    mostrar('El servicio está saturado. Prueba en un momento.');
  }
  // e.requestId es lo primero que pide el soporte de AWS.
} on BudgetExhaustedException catch (e) {
  mostrar('Demasiadas consultas. Vuelve a intentarlo a las '
          '${DateFormat.Hm().format(e.resetsAt)}.');
} on AlsTransportException {
  // El servicio no llegó a responder → no se ha facturado nada.
  mostrar('Sin conexión.');
} on NativMapsConfigurationException {
  mostrar('Falta la clave de Amazon Location.');
}
```

Captura `NativMapsException` para atrapar las cinco de golpe **sin** atrapar
los errores de programación de tu app, que es lo que hace un `catch (e)`
genérico.

---

## 40 · No llevarse un susto en la factura

```dart
final maps = NativMaps(
  region: 'us-east-1',
  credentials: const ApiKeyCredentials(clave),
  budget: Budget(
    maxUnits: 500,
    window: const Duration(minutes: 1),
    onExceeded: (evento) => registro.alerta(
      'Presupuesto: ${evento.operation} pedía ${evento.requestedUnits}',
    ),
  ),
);

// Consultar en cualquier momento
print('${maps.budget.usedUnits}/${maps.budget.maxUnits}');
print('quedan ${maps.budget.remainingUnits}');

// Medir lo que cuesta una operación concreta
final antes = maps.budget.usedUnits;
await maps.routes.calculateRouteMatrix(origins: o, destinations: d);
print('costó ${maps.budget.usedUnits - antes} unidades');
```

La ventana es **deslizante**, no un contador que se reinicia: un contador dejaría
pasar el doble justo en el cambio de ventana, que es cuando un bucle desbocado
está en su peor momento.

> El presupuesto protege de **tus propios bucles**. No protege de un tercero que
> extrajo la clave del APK: para eso está AWS Budgets, en la consola.


---

# Geovallas y rastreo

> ### ⚠️ Antes de estas nueve recetas
>
> Geovallas y rastreo son de la **generación anterior** de Amazon Location:
>
> 1. **Hay que crear un recurso** —una colección o un rastreador—.
> 2. **No admiten clave de API.** Hacen falta `ProxyCredentials` o
>    `nativ_maps_sigv4`. El paquete lo **corta antes de enviar**, con un
>    mensaje que dice qué hacer.
> 3. Sí usan `DistanceUnit`; el paquete pide kilómetros y **convierte a
>    metros**, para que todo siga en unidades del SI.

```dart
// Las nueve recetas dan por hecho esto:
final maps = NativMaps(
  region: 'us-east-1',
  credentials: ProxyCredentials(
    baseUrl: Uri.parse('https://api.miempresa.com/geo'),
  ),
);
```

---

## 41 · Crear una zona

```dart
// Circular: la más barata de evaluar.
await maps.geofencing.putGeofence(
  collectionName: 'zonas-permitidas',
  geofenceId: 'bodega-norte',
  geometry: GeofenceGeometry.circle(
    center: LatLng(-0.1807, -78.4678),
    radiusMeters: 500,
  ),
  // Hasta TRES. Viajan dentro de cada evento que dispare, así que aquí va lo
  // que hará falta al recibirlo sin tener que consultarlo.
  properties: {'cliente': 'ACME', 'tipo': 'bodega'},
);

// Poligonal, con un agujero. Máximo 1000 vértices en total.
await maps.geofencing.putGeofence(
  collectionName: 'zonas-permitidas',
  geofenceId: 'area-industrial',
  geometry: GeofenceGeometry.polygon([
    contorno,
    huecoInterior,   // los anillos siguientes son agujeros
  ]),
);
```

El anillo se cierra solo. **Una geovalla recién creada tarda un momento en
pasar a `ACTIVE`**, y hasta entonces no dispara nada — no falla, simplemente no
salta, que es peor.

---

## 42 · Saber si un punto está dentro (gratis)

```dart
final zona = GeofenceGeometry.circle(center: bodega, radiusMeters: 500);

// Se calcula EN LOCAL. No cuesta una petición.
if (zona.contains(posicionDelVehiculo)) {
  mostrarInsignia('En la bodega');
}
```

Es exacto para el círculo y por trazado de rayo para el polígono, y basta para
pintar el estado en la interfaz. La evaluación **oficial** —la que dispara los
eventos— es la receta siguiente, y puede diferir en los bordes.

---

## 43 · Evaluar posiciones de verdad

```dart
final resultado = await maps.geofencing.batchEvaluateGeofences(
  collectionName: 'zonas-permitidas',
  positions: [
    for (final p in lote.take(10))    // máximo 10
      DevicePositionUpdate(
        deviceId: p.imei,
        position: LatLng(p.lat, p.lng),
        sampleTime: p.horaDelGps,      // la del GPS, no la de ahora
      ),
  ],
);

// La operación devuelve 200 aunque falle la mitad.
for (final error in resultado.errors) {
  registro.warn('${error.itemId}: ${error.message}');
}
```

> ### ⚠️ La respuesta viene vacía a propósito
>
> **Esta operación no dice si el dispositivo entró o salió.** La evaluación es
> asíncrona: el servicio publica un evento `ENTER` o `EXIT` en **Amazon
> EventBridge**, y ahí es donde hay que escucharlo —con una Lambda, una cola
> SQS o una notificación SNS—.
>
> Quien espere una respuesta síncrona ve un `errors` vacío y concluye que no
> pasó nada.

Y una nota que ahorra un desconcierto: **la última geovalla en la que se vio un
dispositivo se recuerda 30 días**. Pasado ese plazo, la primera posición vuelve
a producir un `ENTER` aunque el vehículo lleve ahí meses.

---

## 44 · Avisar ANTES de que salga de la zona

**Esto no existe en ningún otro sitio.**

```dart
final aviso = await maps.geofencing.forecastGeofenceEvents(
  collectionName: 'zonas-permitidas',
  position: ultimaPosicion,
  speedKmh: velocidadActual,               // SIN ESTO no predice nada
  timeHorizon: const Duration(minutes: 10), // SIN ESTO tampoco
);

// `breaches` deja fuera los IDLE, que solo dicen «sigue donde estaba».
for (final e in aviso.breaches) {
  alertar(
    'El vehículo va a ${e.eventType == ForecastedEventType.exit ? "SALIR de" : "ENTRAR en"} '
    '${e.geofenceProperties['tipo'] ?? e.geofenceId} '
    'en ${e.timeUntilBreach?.inMinutes} minutos, '
    'a ${e.nearestDistance.round()} m del borde',
  );
}
```

Con un vehículo robado, seis minutos de margen son la diferencia entre
interceptarlo y perseguirlo.

**Dos limitaciones que hay que conocer:**

- **Sin `speedKmh` o sin `timeHorizon` no predice**: se convierte en una simple
  comprobación de contención y devuelve solo `IDLE` de las zonas en las que ya
  está.
- **No tiene en cuenta el rumbo.** La documentación de AWS lo dice: es
  conservador e incluye los cruces posibles en *cualquier* dirección. Con un
  vehículo parado en un cruce, eso son varias zonas a la vez.

---

## 45 · Subir posiciones de la flota

```dart
final resultado = await maps.tracking.batchUpdateDevicePosition(
  trackerName: 'flota',
  updates: [
    for (final p in lote)             // se trocea solo en peticiones de 10
      DevicePositionUpdate(
        deviceId: p.imei,
        position: LatLng(p.lat, p.lng),
        sampleTime: p.horaDelGps,      // ← la del GPS
        horizontalAccuracyMeters: p.hdop * 5,
      ),
  ],
);
print('${resultado.succeeded} de ${resultado.total}');
```

> ### ⚠️ No todo lo que se sube se guarda
>
> El `positionFiltering` del rastreador decide. Con el valor por defecto **del
> servicio** —`TimeBased`— solo se guarda **una posición cada 30 segundos por
> dispositivo**: un localizador que reporta cada cinco segundos ve cinco de
> cada seis descartadas, sin ningún error.
>
> Este paquete crea los rastreadores con `PositionFiltering.distanceBased`, que
> solo guarda si se movió más de 30 m. Para rastreo de vehículos es lo
> correcto: el histórico de un día pasa de miles de puntos a cientos **sin
> perder nada del recorrido**, porque los puntos que descarta son los de un
> vehículo parado.

---

## 46 · El histórico, limpio, en dos pasos

```dart
// 1 · Bajarlo
final historico = await maps.tracking.getDevicePositionHistory(
  trackerName: 'flota',
  deviceId: imei,
  from: DateTime.now().subtract(const Duration(hours: 8)),
);

// 2 · Pegarlo a la calle. El resultado entra directamente.
final limpio = await maps.routes.snapToRoads(
  tracePoints: [
    for (final p in historico.items)
      TracePoint(position: p.position, timestamp: p.sampleTime),
  ],
  snapRadiusMeters: 500,
);

await controlador.addPolyline(
  Polyline(polylineId: const PolylineId('recorrido'),
           points: limpio.geometry.points),
);
```

**AWS borra el histórico a los 30 días** y no es configurable: pedir algo más
antiguo devuelve una lista vacía, no un error. Si necesitas conservarlo más,
hay que copiarlo a tu propio almacenamiento.

---

## 47 · Quién hay dentro de esta zona ahora

```dart
final dentro = await maps.tracking.listDevicePositions(
  trackerName: 'flota',
  filterGeometry: contornoDeLaZona,   // ≥3 puntos, se cierra solo
);

for (final p in dentro.items) {
  // Comprobar la frescura no es opcional.
  if (p.isFresh(maxAge: const Duration(minutes: 10))) {
    print('${p.deviceId} está dentro');
  } else {
    print('${p.deviceId} estaba dentro hace ${p.age.inMinutes} min');
  }
}
```

Lo resuelve el servicio, en vez de bajarte la flota entera y filtrar en el
móvil.

---

## 48 · Detectar una ubicación falseada

```dart
final v = await maps.tracking.verifyDevicePosition(
  trackerName: 'flota',
  deviceId: imei,
  position: posicionDeclarada,
  sampleTime: horaDelGps,
  ipv4Address: ipDelDispositivo,       // SIN ESTO no deduce gran cosa
  wifiAccessPoints: puntosWifiVistos,
);

if (v.isSuspicious()) {
  alertar(
    'Posición sospechosa de $imei: '
    '${v.proxyDetected ? "llegó por un proxy" : ""} '
    'y se desvía ${(v.deviationMeters! / 1000).round()} km de lo deducido',
  );
}
```

Contrasta lo que dice el dispositivo con lo que el servicio deduce de su IP y
de los puntos Wi-Fi que ve. **`proxyDetected` es la señal más fuerte**: un
localizador honesto conectado por la red móvil no pasa por un proxy.

El umbral por defecto —10 km— es generoso a propósito: la localización por
antenas de telefonía tiene un error de kilómetros en zona rural, y un umbral
apretado marcaría como sospechoso a medio campo.

---

## 49 · Montar el sistema entero, una vez

Esto se hace **una sola vez**, desde una herramienta de administración. Una app
móvil casi nunca debería tener permiso para el plano de control.

```dart
// 1 · La colección de zonas
final coleccion = await maps.geofencing.createCollection(
  collectionName: 'zonas-permitidas',
  description: 'Zonas donde la flota puede estar',
);

// 2 · Las zonas
await maps.geofencing.batchPutGeofence(
  collectionName: 'zonas-permitidas',
  geofences: [
    for (final b in bodegas.take(10))
      Geofence(
        geofenceId: b.id,
        geometry: GeofenceGeometry.circle(
          center: b.posicion,
          radiusMeters: 500,
        ),
        properties: {'cliente': b.cliente},
      ),
  ],
);

// 3 · El rastreador
final rastreador = await maps.tracking.createTracker(
  trackerName: 'flota',
  positionFiltering: PositionFiltering.distanceBased,
  eventBridgeEnabled: true,
);

// 4 · EL ENLACE. Esto es lo que hace que todo funcione solo.
await maps.tracking.associateConsumer(
  trackerName: 'flota',
  collectionArn: coleccion.collectionArn!,   // el ARN, no el nombre
);
```

**A partir de aquí**, cada posición que entre por `batchUpdateDevicePosition`
se evalúa automáticamente contra las zonas y dispara eventos `ENTER` y `EXIT`
en EventBridge. Sin el paso 4 hay que llamar a `batchEvaluateGeofences` a mano
por cada lote: el doble de peticiones y el doble de factura para el mismo
resultado.

Cuando «las geovallas no disparan», **lo primero que hay que mirar es si el
enlace existe**:

```dart
final enlaces = await maps.tracking.listConsumers(trackerName: 'flota');
print(enlaces.items);   // vacío = ese es el problema
```
