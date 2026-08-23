# nativ_maps

> **Amazon Location Service con la forma de Google Maps.**
> Un framework de Flutter reutilizable, publicable en pub.dev.

[![Dart 3.13](https://img.shields.io/badge/Dart-3.13-0175C2)](https://dart.dev)
[![Flutter 3.47](https://img.shields.io/badge/Flutter-3.47-02569B)](https://flutter.dev)
[![Licencia MIT](https://img.shields.io/badge/licencia-MIT-green)](LICENSE)

---

## La tesis en cuatro líneas

`google_maps_flutter` **solo dibuja**. No tiene búsqueda de lugares, ni
geocodificación, ni rutas. Para eso hay que llamar a las API REST por separado,
con otra clave, otro cliente HTTP y **otros tipos** — y escribir el pegamento
que convierte el `lat/lng` de una respuesta JSON al `LatLng` del mapa.

Ese pegamento se reescribe en cada proyecto, y es donde se cuelan los errores de
orden de coordenadas.

**Aquí el `LatLng` que devuelve una búsqueda es el que acepta un marcador:**

```dart
final ruta = (await maps.routes.calculateRoutes(
  origin: aqui,
  destination: alli,
)).best!;

// Sin convertir nada. Ese es todo el argumento.
await controlador.addPolyline(
  Polyline(polylineId: const PolylineId('ruta'), points: ruta.points),
);
```

---

## Empezar en dos minutos

```yaml
dependencies:
  nativ_maps_flutter: ^0.2.0
```

```dart
import 'package:nativ_maps_flutter/nativ_maps_flutter.dart';

final maps = NativMaps(
  region: 'us-east-1',
  credentials: const ApiKeyCredentials('tu-clave'),
  language: 'es',
);

NativMap(
  styleUrl: maps.maps.styleDescriptorUrl(MapStyle.standard)!,
  initialCameraPosition: CameraPosition(
    target: LatLng(-0.1807, -78.4678),
    zoom: 13,
  ),
  onMapCreated: (controlador) => _controlador = controlador,
);
```

**Instalando solo `nativ_maps_flutter` ya tienes las 44 operaciones**: el
paquete reexporta el núcleo entero.

> **La regla que lo resume:** si sabes usar `google_maps_flutter`, ya sabes usar
> la mitad de esto sin leer nada. Y la otra mitad es lo que Google no te daba.

---

## Qué hay aquí

| Documento | Para qué |
|---|---|
| **[doc/RECETAS.md](doc/RECETAS.md)** | 49 recetas copiables, una por tarea. **Empieza aquí.** |
| **[AGENTS.md](AGENTS.md)** | Escrito para agentes de IA: mapa de la API, reglas duras y trampas |
| **[doc/MIGRACION.md](doc/MIGRACION.md)** | De `google_maps_flutter`, paso a paso |
| **[doc/COBERTURA.md](doc/COBERTURA.md)** | Qué está cubierto, qué es mejor y **qué no existe** |
| [example/](example/) | App con 8 pantallas que ejercitan las operaciones |

---

## Los cuatro paquetes

```
packages/
├── nativ_maps/            ① núcleo · Dart puro · sin Flutter
├── nativ_maps_flutter/    ② EL QUE SE INSTALA · widget + reexporta ①
├── nativ_maps_google/     ③ compatibilidad · typedef + extension
└── nativ_maps_sigv4/      ④ firma SigV4 · opcional
```

| Paquete | Por qué está separado |
|---|---|
| `nativ_maps` | No depende de Flutter → se prueba **sin emulador** y sirve en una herramienta de línea de órdenes o un servidor Dart |
| `nativ_maps_flutter` | La puerta de entrada. Reexporta el núcleo entero |
| `nativ_maps_google` | Opcional. Solo lo añade quien viene de Google |
| `nativ_maps_sigv4` | Aparte **a propósito**: quien solo usa clave de API no debe pagar sus dependencias |

---

## Las 44 operaciones de Amazon Location

### Places · 7

| Método | Endpoint | Para qué |
|---|---|---|
| `autocomplete` | `POST /v2/autocomplete` | escribir una dirección |
| `searchText` | `POST /v2/search-text` | buscar un lugar por nombre |
| `reverseGeocode` | `POST /v2/reverse-geocode` | de coordenada a dirección dictable |
| `getPlace` | `GET /v2/place/{id}` | ficha completa |
| `geocode` | `POST /v2/geocode` | de dirección a coordenada, **con precisión** |
| `searchNearby` | `POST /v2/search-nearby` | qué hay cerca de un punto |
| `suggest` | `POST /v2/suggest` | sugerencia más barata que autocomplete |

### Routes · 5

| Método | Endpoint | Para qué |
|---|---|---|
| `calculateRoutes` | `POST /v2/routes` | ruta entre dos puntos, **con peajes** |
| `calculateRouteMatrix` | `POST /v2/route-matrix` | quién está más cerca **por carretera** |
| **`calculateIsolines`** | `POST /v2/isolines` | **área alcanzable en X minutos** |
| **`snapToRoads`** | `POST /v2/snap-to-roads` | **pegar el rastro GPS a la calle real** |
| `optimizeWaypoints` | `POST /v2/optimize-waypoints` | orden óptimo de paradas |

### Maps · 5

| Operación | Cómo |
|---|---|
| `GetStyleDescriptor` | `maps.styleDescriptorUrl(...)` — **10 parámetros** |
| `GetStaticMap` | `maps.staticMap(...)` — la pinta el servidor |
| `GetTile` · `GetGlyphs` · `GetSprites` | MapLibre las pide sola desde el descriptor |

### Geovallas · 12

| Método | Para qué |
|---|---|
| `putGeofence` · `batchPutGeofence` | crear zonas: círculo, polígono o multipolígono |
| `getGeofence` · `listGeofences` · `batchDeleteGeofence` | gestionarlas |
| `batchEvaluateGeofences` | ¿entró o salió? → evento en EventBridge |
| **`forecastGeofenceEvents`** | **¿va a entrar? Avisa ANTES de que ocurra** |
| `createCollection` · `describeCollection` · … | la colección, 5 operaciones |

### Rastreo de dispositivos · 15

| Método | Para qué |
|---|---|
| `batchUpdateDevicePosition` | subir posiciones, con troceado automático |
| `getDevicePosition` · `batchGetDevicePosition` | la última conocida |
| `getDevicePositionHistory` | el histórico, listo para `snapToRoads` |
| `listDevicePositions` | **quién hay dentro de este polígono ahora** |
| **`verifyDevicePosition`** | **¿me están falseando la ubicación?** |
| `associateConsumer` | **enlazar con geovallas: evaluación automática** |
| `createTracker` · `describeTracker` · … | el recurso, 7 operaciones más |

> ### ⚠️ Geovallas y rastreo son de la generación anterior
>
> Tres diferencias con Places, Routes y Maps v2:
>
> 1. **Hay que crear un recurso** —una colección o un rastreador—, en la consola
>    o con el propio paquete.
> 2. **No admiten clave de API.** Las claves de Amazon Location solo cubren
>    Places, Routes y Maps. Aquí hacen falta credenciales SigV4. El paquete lo
>    **corta antes de enviar**, con un mensaje que dice qué hacer, en vez de
>    dejar que llegue como un `403` idéntico a todos los demás.
> 3. **Sí usan `DistanceUnit`.** La regla «nunca envíes `DistanceUnit`» vale
>    para Routes v2, no para estas. El paquete pide kilómetros y **convierte a
>    metros**, para que todo el resto siga en unidades del SI.

---

## Lo que Google no te daba

| Capacidad | `google_maps_flutter` | Aquí |
|---|---|---|
| **Isócronas** | no existe | `calculateIsolines` |
| **Aviso anticipado de geovalla** | no existe | `forecastGeofenceEvents` |
| **Detección de ubicación falseada** | no existe | `verifyDevicePosition` |
| **Pegado a carretera** | no existe | `snapToRoads`, con troceado automático |
| **Optimización de paradas** | no existe | `optimizeWaypoints` |
| **Coste de peajes** | no existe | `Toll` con importe y moneda |
| **Mapas sin conexión** | **prohibido por sus condiciones** | `controller.offline` |
| Búsqueda y geocodificación | otra API, otra clave, otros tipos | mismo cliente, mismos tipos |
| Clústeres | clase gestora en Dart | **nativo, en el motor** |
| Mapa de calor | tipo cerrado | **capa nativa con rampa propia** |
| Modo oscuro | filtro sobre teselas claras | **lo renderiza el servidor** |
| Tráfico, relieve, edificios 3D | solo tráfico | **parámetros del descriptor** |

---

## Control de gasto: arquitectura, no un extra

Amazon Location **se factura por petición**, y algunas cobran más de una.

```dart
final maps = NativMaps(
  region: 'us-east-1',
  credentials: const ApiKeyCredentials(clave),
  budget: Budget(maxUnits: 500, window: const Duration(minutes: 1)),
);
```

| Operación | Lo que parece | Lo que cuesta |
|---|---|---|
| `searchText` | 1 petición | 1 unidad |
| `calculateIsolines` con 5 umbrales | 1 petición | **5 unidades** |
| `calculateRouteMatrix` de 10×10 | 1 petición | **100 unidades** |
| `snapToRoads` con 12 000 puntos | 1 llamada | **3 unidades** (se trocea) |

Un bucle sobre la flota, un `initState` que pide una ruta en cada
reconstrucción, una pantalla que se refresca sola: ninguna se ve como un error
al leer el código, y las tres aparecen en la factura.

**Los límites duros se comprueban antes de enviar**, con el cálculo hecho en el
mensaje:

```dart
await maps.routes.calculateRouteMatrix(
  origins: dieciseisPuntos,   // ArgumentError, y NO se envía nada
  destinations: unPunto,
);
// «sin acotar la zona el máximo es 15 orígenes, 100 destinos y 100 celdas;
//  se pidieron 16×1 = 16 celdas. Pasa `routingBoundary` para subir el límite,
//  o filtra los candidatos por distancia en línea recta antes de llamar —
//  eso es gratis y esto cuesta 16 unidades.»
```

---

## Autenticación: tres caminos, una interfaz

| Camino | Cómo | Coste real |
|---|---|---|
| **A · Clave de API** | `ApiKeyCredentials` | **se extrae de un APK.** Solo desarrollo |
| **B · Proxy que firma** | `ProxyCredentials` | un endpoint nuevo. **Recomendado en producción** |
| **C · SigV4 en el móvil** | `nativ_maps_sigv4` | configurar Cognito y la política IAM |

Cambiar de camino es cambiar el objeto que se pasa al constructor. Nada más
arriba se entera.

> ⚠️ **Los tres servicios firman con nombres distintos:** `geo-places`,
> `geo-routes`, `geo-maps`. Equivocarse da un `403` **idéntico** al de una clave
> mala. Aquí no se puede fallar: el nombre lo pone el enum `AlsService`.

---

## Mapas sin conexión

```dart
final progreso = controlador.offline!.downloadRegion(
  bounds: await controlador.getVisibleRegion(),
  minZoom: 10,
  maxZoom: 15,
  name: 'Quito centro',
);
await for (final evento in progreso) {
  print('${(evento.fraction * 100).round()} %');
}
```

> ### ⚠️ Resolver antes de enviar una app con esto
>
> Que MapLibre **pueda** guardar teselas no significa que Amazon **permita**
> guardar las suyas. Las condiciones remiten a la **Sección 82 de los AWS
> Service Terms**, que AWS no publica de forma consultable.
>
> 1. **Leer la Sección 82 completa**, en `aws.amazon.com/service-terms`.
> 2. **Comprobar qué proveedor sirve tu región.** Si el mapa base abierto
>    (OpenStreetMap Daylight) sirve, el problema legal se simplifica mucho.
> 3. **Declarar la atribución**, obligatoria y visible. En un mapa guardado
>    también — y ahí es justo donde se olvida.
> 4. **Fijar una caducidad**, con `deleteStaleRegions`.
>
> Este paquete da la herramienta y el recordatorio; la decisión legal es de
> quien publica la app.

---

## Limitaciones conocidas

Están aquí y no escondidas porque son lo primero con lo que se topa quien
instala el paquete.

### 1 · Android Gradle Plugin 8.x, no 9.x

`maplibre_gl` 0.27.0 **no compila con AGP 9**. Su `build.gradle` deja de aplicar
el plugin de Kotlin al detectar AGP 9 —porque ahí aplicarlo rompe el build de la
app— y luego usa la extensión `kotlin {}`, que en AGP 9 no está registrada.

```text
Could not find method kotlin() for arguments […] on project ':maplibre_gl'
```

**Arreglo:** en `android/settings.gradle.kts`, fijar
`id("com.android.application") version "8.13.2"`.

Flutter 3.47 genera proyectos con AGP 9.1.0 y avisa de que el soporte de AGP 8
se retirará. Hay que seguir la evolución de `maplibre_gl`.

### 2 · Hace falta JDK 21

`maplibre_gl` compila su Java con `sourceCompatibility 21`. Flutter usa el JDK
que trae Android Studio —hoy el 17— y **lo prefiere antes que `JAVA_HOME`**.

```text
error: invalid source release: 21
```

**Arreglo:** `flutter config --jdk-dir="/ruta/al/jdk-21"`.

### 3 · Tres cosas de Google que no existen

| Método de Google | Motivo |
|---|---|
| `setIndoorEnabled` | Amazon Location no tiene planos de interior |
| `setLiteModeEnabled` | exclusivo de Android + Google |
| `cloudMapId` | estilos alojados en la nube de Google |
| `AdvancedMarker` | API propietaria reciente de Google |

**Se omiten y se documentan; nunca un hueco que devuelve `null` en silencio.**
Un método que existe y no hace nada es peor que uno que no existe: al segundo lo
caza el compilador.

### 4 · La traducción de estilos de Google es aproximada

`setGoogleMapStyle` traduce por coincidencia de nombre de capa, y devuelve un
`GoogleStyleReport` que **dice qué reglas no se aplicaron**. Ver
[doc/MIGRACION.md](doc/MIGRACION.md).

---

## Estado del proyecto

| | |
|---|---|
| Operaciones | **44 de 44** de Amazon Location |
| Análisis estático | **limpio en los 4 paquetes y en el ejemplo**, con `--fatal-infos` y `public_member_api_docs: error` |
| Pub points del núcleo | **160/160**, medido con `pana` |
| Pruebas | **229 verdes** |
| Firma SigV4 | verificada contra el **vector oficial `get-vanilla` de AWS** |
| Polilínea de HERE | verificada contra el **vector oficial de `heremaps/flexible-polyline`** |
| Android | **APK compilado** |
| iOS | **`Runner.app` compilado** |
| Ensayo de publicación | **0 avisos** en los dos paquetes públicos |
| Peticiones al servicio real | **ninguna todavía** ← ver «Antes de producción» |

### Antes de producción

Los clientes están contrastados campo a campo contra la referencia viva de AWS,
pero **no se ha enviado ninguna petición al servicio real**. Antes de confiar en
esto en producción, hay que ejecutar el `example/` con una clave de verdad y
recorrer las ocho pantallas. Es media tarde y es la única forma de cerrar la
distancia entre «coincide con la documentación» y «funciona».

---

## Desarrollo

```sh
dart pub get                 # el workspace resuelve los 5 paquetes a la vez
dart run melos run verify    # formato + análisis + todas las pruebas
dart run melos run test      # solo las pruebas de Dart puro
dart run melos run doc       # dartdoc
```

```sh
cd example
flutter run \
  --dart-define=ALS_API_KEY=tu-clave \
  --dart-define=ALS_REGION=us-east-1
```

---

## Licencia

MIT — ver [LICENSE](LICENSE).

Los datos de mapas son de Amazon Location Service y sus proveedores (HERE,
Esri, GrabMaps, OpenStreetMap Daylight). **La atribución es obligatoria y
visible**; ver la [documentación de atribución de AWS][atribucion].

[atribucion]: https://docs.aws.amazon.com/location/latest/developerguide/data-attribution.html
