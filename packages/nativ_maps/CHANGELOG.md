# Changelog

Este proyecto sigue [Versionado Semántico](https://semver.org/lang/es/).
Mientras la versión mayor sea `0`, una versión menor puede romper la API; a
partir de `1.0.0`, no.

## 0.9.2

### Fixed

- **Markers and overlays added before the style finished loading no longer
  fail.** `setMarkers`, `addMarker` and the sync that pushes overlays to the
  map talked to it before its style was ready —from `onMapCreated`, or in the
  middle of a style switch— and the native side answered `STYLE_NOT_READY`.
  The next style load usually put them back, which is why it went unnoticed;
  when it landed at the wrong moment, a marker was left without its icon.
  They now wait for the style, and what changes meanwhile goes out in one
  push.
- **A dashed polyline whose layer failed to install now shows up.** The layer
  was recorded as installed before it was, and wasn't tried again until the
  next style change.
- `setMarkers` puts the markers in place before uploading their icons, like
  `addMarker` already did, so a style that loads in between re-uploads them.

## 0.9.1

**The signing proxy, end to end.** `ProxyCredentials` was the recommended way
to ship, and nothing proved it worked: there was no server to point it at, and
the map never sent the proxy its token on Android. Now there's a contract, six
reference servers checked with the same conformance test against AWS, and a
map that loads through a proxy on Android and iOS, with no key in the app.

### Fixed

- **`NativMap.customHeaders` never reached the map on Android.** `maplibre_gl`
  matches the header filter against the whole URL on Android and searches for
  it on iOS, so the default `amazonaws.com` only ever worked on iOS. The
  headers now go out on both, with the same rule.
- **…and never reached a proxy on either platform.** They only went to
  `amazonaws.com`, while a map served through a proxy asks the proxy's host.
  They now go to the `styleUrl`'s host and to `amazonaws.com`, and to nothing
  else: not to a third-party tile server you add.
- **The first style request always went out without the headers.** A native
  map starts downloading its style the moment it exists, before its headers
  can be set: behind a proxy, a `401` and a blank map. With `customHeaders`,
  the map now starts empty and loads the style once they're in place.
- **Changing `styleUrl` loaded the new style twice.**
- `maplibre_gl`'s annotation managers are no longer created. The package
  never used them —it draws with its own layers— and they made every style
  load heavier and could fail a style switch with `STYLE_NOT_READY`.

### Changed

- **`ProxyCredentials` also sends `X-Nativ-Host`**, the Amazon Location host
  the request is meant for. Geofencing, tracking and their two control planes
  all sign as `geo`: the signing name alone couldn't tell a proxy which of the
  four to call. `X-Nativ-Service` and `X-Nativ-Region` are still sent.
- **`NativMapController.setCustomHeaders(urlFilter:)` takes hosts**, as it
  always said, and matches each host and its subdomains the same way on
  Android and iOS. It used to hand the strings to each platform as a regular
  expression, with the different results above.

### New

- **[doc/PROXY.md](https://github.com/delioribas/nativ_maps/blob/main/doc/PROXY.md)**:
  what a proxy must do —authorize first, forward only to Amazon Location
  hosts, rewrite the style so the tiles come back through it and the API key
  never reaches the phone—, the IAM policy, and a production checklist.
- **Reference servers** in `proxies/`: Node, AWS Lambda (with a SAM template,
  and no keys at all: the function's role signs), Go, Python, PHP and Java.
  Same variables, same behavior, same structure: a framework-free core and a
  small server, with snippets for Express, NestJS, FastAPI, Laravel, Spring
  Boot and others.
- **A conformance test for any proxy**, yours included:
  `PROXY_URL=… PROXY_TOKEN=… dart test -P proxy` in `packages/nativ_maps`.
  It goes through the proxy the way the package and the map renderer do, and
  checks what the proxy has to refuse.
- The example app runs through a proxy with
  `--dart-define=ALS_PROXY_URL=… --dart-define=ALS_PROXY_TOKEN=…`, with no key
  inside the app.

## 0.9.0

**Release candidate for 1.0.0.** All 44 operations have now run against Amazon
Location for real —17 with an API key, 27 with IAM credentials signed with
SigV4— and every enum value that travels in a request has been checked against
the service, in 111 checks. The API has been reviewed for freezing: what never
worked is gone, and what was declared but did nothing now works. The API docs
are now in English.

### Breaking changes

- **`FareAdvisor` and `FareSuggestion` are gone.** They were deprecated in favor
  of `PriceAdvisor`.
- **`RouteFeature.tollSystems` is gone.** AWS never accepted it in a request:
  it always answered 400. The toll systems come with `RouteFeature.tolls`.
- **`TravelStepType.general` is gone** —it isn't an AWS value; always 400— and
  **`TravelStepType.none` is now `TravelStepType.standard`.** It is AWS's
  `Default` steps, the only ones that carry written instructions; the old name
  and docs said the opposite.
- **The calculation layer is `@experimental`**: `Tariff`, `TripRecorder`,
  `PriceAdvisor`, `RideAuction`, `DispatchPlanner`, `TelemetryAnalyzer`,
  `RouteTracker` and the path geometry functions stay outside the 1.0
  stability promise until they have been used charging real rides.

### New

- **Draggable markers.** `Marker.draggable` now works, with `onDragStart`,
  `onDrag` and `onDragEnd` —the names `google_maps_flutter` uses—. The marker
  follows the finger instead of the map panning, and the controller keeps the
  new position.
- **`GroundOverlay` and `TileOverlay` can be drawn**:
  `addGroundOverlay`/`removeGroundOverlay`/`setGroundOverlays`/
  `clearGroundOverlays`, and the same for tile overlays. They were exported
  types with no way to put them on a map. Both go under the package's polygons,
  lines and markers; an image accepts `https` and `data:` URLs.
- **`applyGoogleLook()`** in `nativ_maps_google`: the palette of the current
  Google Maps over `MapStyle.standard`, measured in the Google Maps app.
- **Live tests for the 27 IAM operations** (`dart test -P live` in
  `nativ_maps_sigv4`, or `melos run test:live:iam`) and for every enum value
  (`test/live/enums_live_test.dart` in `nativ_maps`).

### Fixed

| What | What happened |
|---|---|
| Geofence polygons and the `listDevicePositions` filter | AWS rejected a clockwise outer ring with a 400 —"must be oriented counter-clockwise"—, and that's how a zone comes out when drawn NW, NE, SE, SW. Rings are now closed and oriented automatically |
| SigV4 with anything encoded in the path: `disassociateConsumer`, or a `deviceId` with `:` | **403**, "signature does not match": the canonical path was encoded once and AWS encodes it twice |
| `StyleEditor.setColor`, `setLineWidth`, `setOpacity`, `setPaintProperties` | **wiped the rest of the layer**: `maplibre_gl` sends every untouched property as `null`, which resets it. Changing a label's color erased its text; a road's, its width. Also fixes `setGoogleMapStyle` |
| `NativMap.onCameraIdle` | never fired for the initial camera —`google_maps_flutter` does—, and a debounced `onCameraMove` could land after it, leaving the app thinking the camera was still moving. Now: once for the initial camera, then once per new resting place, always after the last move |
| The info window of a removed or hidden marker | stayed open, pointing at nothing |
| Tolls on a pedestrian route; written instructions with turn-by-turn steps | a billed 400 from AWS. Now an `ArgumentError` before sending |
| `GetStaticMap` | documented as JPEG; AWS returns PNG |

### Documented

- Which `PlaceFeature` values each Places operation accepts, measured against
  the service: anything outside its row is a 400.

### Tested

- Every response shape from geofencing and tracking, with the real AWS
  responses as fixtures.
- The example app, demo by demo, on an Android emulator and the iOS simulator,
  with real taps and drags; and the two apps that use the package, ryvell and
  xyntar, compile and pass their tests against this version.

## 0.5.3

**Tocar el mapa, probado por fin en un dispositivo.** La 0.5.1 probó que los
marcadores se dibujan; esta, que se pueden tocar. Probado con la app de
ejemplo en un emulador Android (Pixel 7, Android 15) y en el simulador de iOS
(iPhone 15).

### Corregido

| Qué | Qué pasaba |
|---|---|
| `onMarkerTap`, `onPolylineTap`, `onClusterTap`, los globos y `onTap` sobre un polígono | **no llegaban nunca**. `maplibre_gl` hace interactiva toda capa, y un toque sobre una capa interactiva sale por `onFeatureTapped` y no por `onMapClick`, que es donde el paquete resuelve qué hay bajo el dedo. Ahora las capas del paquete no son interactivas y el mapa pide `featureTapsTriggersMapClick` |
| Globo (`InfoWindow`) en Android | salía fuera de la pantalla: `maplibre_gl` da el toque en píxeles físicos y el globo, que es un widget, se colocaba en lógicos. Ahora se coloca bien y se ancla al marcador |
| `getScreenCoordinate` y `getLatLng` | devolvían y pedían píxeles físicos en Android y lógicos en iOS. Ahora **píxeles lógicos de Flutter en las dos**, los de `Positioned`. En Android cambia el valor que devuelven |
| Marcadores dentro de un `ClusterManager` | al salir de un grupo perdían el texto y el ancla: su capa no usaba las mismas propiedades que la de los marcadores sueltos |

### Documentado

- `Marker.label` se oculta si choca con otro marcador o texto, y vuelve al
  acercar el zoom.

### Añadido

- `example/integration_test/recorrido_test.dart`: recorre las superposiciones
  en un dispositivo o simulador real y deja cada estado en pantalla para
  capturarlo.
- `tool/test_floor.sh`: análisis y pruebas de los dos paquetes de pub.dev con
  Flutter 3.32, cada uno resuelto suelto, como lo ve quien lo instala.

## 0.5.2

**`nativ_maps_flutter` 0.5.1 no compilaba en Flutter 3.32**, el suelo que
declara. Usaba `@internal` contando con que `flutter/foundation.dart` lo
reexporta, y eso solo pasa en versiones recientes de Flutter. Ahora importa
`meta` explícitamente, como el resto del paquete.

Lo encontró la primera prueba contra el suelo de verdad: cada paquete copiado
fuera del workspace y resuelto con Flutter 3.32.0 y Dart 3.8, como lo verá
quien lo instale. Con 3.32.0 pasan el análisis estricto y las pruebas de los
dos paquetes publicados.

Sin cambios de comportamiento: si usas Flutter 3.44 o posterior, la 0.5.1 y
la 0.5.2 hacen lo mismo.

## 0.5.1

**Los marcadores, probados por fin en un dispositivo.** La 0.5.0 se probó
contra AWS; esta, en un emulador Android (Pixel 7, Android 15) con una app
real que la usa —ryvell, Quito—. Salieron tres fallos del mapa que ninguna
prueba sin dispositivo podía ver, uno de la capa de cálculo y dos de la
documentación.

### Corregido

| Qué | Qué pasaba |
|---|---|
| `BitmapDescriptor.defaultMarker` y `defaultMarkerWithHue` | **no se dibujaban nunca**: la imagen `nativ-default-marker` no se registraba en ningún sitio. Ahora el paquete pinta el alfiler, uno por color, y lo registra en el estilo |
| Capa de marcadores | usaba `icon-rotation-alignment` con una expresión, que la especificación de MapLibre no admite, y MapLibre rechazaba la propiedad. Ahora son dos capas, planos y verticales |
| `Marker.anchor` | se ignoraba: todo icono se anclaba por abajo, y uno centrado —un vehículo— quedaba medio icono desplazado. Ahora se respeta, redondeado a las nueve posiciones de MapLibre, y el texto baja para no pisar el icono |
| `PriceAdvisor.suggest` | mínimo, recomendado y rápido no pasaban por el redondeo de la tarifa: «Mínimo 1,28 $» junto a «Recomendado 1,50 $» |
| Documentación: peajes | cinco ejemplos hacían `tollCostByCurrency['USD']?.round()`, que redondea dólares: un peaje de 0,40 contaba como 0 |
| Documentación: buscador | recomendaba `autocomplete` para buscar destinos, pero solo completa direcciones: «Quicentro» o «Aeropuerto Mariscal Sucre» daban cero resultados. Ahora recomienda `suggest` con `PlaceFeature.core`, que además trae la posición |

### Añadido

- `Route.tollCostInMinorUnits(currency)`: los peajes en la unidad que esperan
  `Tariff`, `PriceAdvisor` y `BidAdvisor`.
- `Tariff.applyRounding(amount)`: la regla de redondeo de la tarifa, para
  cualquier importe que se enseñe junto a uno suyo.
- `BitmapDescriptor.hueRed`, `hueAzure`… en el mismo sitio que en
  `google_maps_flutter`: el código migrado compila sin cambios. `MarkerHue`
  sigue.

## 0.5.0

**Primera pasada contra Amazon Location de verdad.** Las 17 operaciones que
aceptan clave de API se lanzaron contra AWS en `us-east-1` (Quito, 18 de
octubre de 2026). Salieron nueve diferencias entre lo que el paquete suponía y
lo que AWS hace; cuatro de ellas no daban ningún error, solo datos vacíos.

### Corregido

| Operación | Qué pasaba | Cómo se notaba |
|---|---|---|
| `getPlace` | `additional-features` iba separado por comas | `400` con cualquier característica |
| `staticMap` | la ruta era `/v2/static-map` en vez de `/v2/static/map` | `403` «Missing Authentication Token» |
| `staticMap` | `language`, `points-of-interests` y `scale-bar-unit` no existen: son `lang`, `pois` y `scale-unit` | **nada**: AWS ignora los parámetros que no conoce |
| `tileUrlTemplate`, `glyphsUrlTemplate` | las llaves salían como `%7B…%7D` | ni MapLibre ni `replaceAll('{z}')` las sustituían |
| `spritesUrlTemplate` | la ruta no existe | `403` |
| `optimizeWaypoints` | la duración de cada enlace se leía de `Duration`; es `TravelDuration` | **nada**: `connections[].duration` siempre cero |
| `optimizeWaypoints` | `orderedIds` incluía `Origin` y `Destination` | `firstWhere` lanzaba al reordenar la lista propia |
| `calculateRoutes` | ángulo e intensidad del giro se leían de la raíz del paso; van en `TurnStepDetails`, `KeepStepDetails`… | **nada**: `turnAngle` y `turnIntensity` siempre `null` |
| `calculateRoutes` | `exitNumber` y el sistema del peaje (`systemRef`) se leían con una forma que AWS no usa | **nada**: siempre `null` |

### Cambios que rompen

- `spritesUrlTemplate(String fileName)` pasa a ser
  `spritesUrl(MapStyle style, {MapColorScheme colorScheme})`. Devuelve la
  base sin extensión, que es lo que espera MapLibre. La anterior nunca
  funcionó.
- `staticMap` y `staticMapUrl` lanzan `ArgumentError` antes de enviar si
  `width` o `height` salen de **64..1400** (antes se aceptaba 1..1440), si el
  estilo no es `standard` ni `satellite`, si llegan `zoom` y `radiusMeters` a
  la vez, o si llega `center` sin ninguno de los dos.
- `getPlace` lanza `ArgumentError` con `PlaceFeature.core` o
  `PlaceFeature.intersections`, que esa operación no admite.
- `optimizeWaypoints` lanza `ArgumentError` si una parada se llama `Origin` o
  `Destination`.
- `glyphsUrlTemplate` ya no lleva la clave: `GetGlyphs` es público, igual que
  `GetSprites`.

### Añadido

- `test/live/`: las 17 operaciones contra AWS de verdad. `dart test` las
  salta; se lanzan con `dart test -P live` y `ALS_API_KEY` en el entorno.
  Guardan cada respuesta cruda, sin la clave, en `test/live/respuestas/`.
- `WaypointOptimizationResponse.reservedIds`.

## 0.4.0

**Precio sugerido para mercados de puja**, con la forma de inDrive y apoyado
en los datos que ya devuelve Amazon Location.

### Añadido

| Clase | Qué resuelve |
|---|---|
| `PriceAdvisor` | el precio sugerido, con el porqué de cada factor |
| `SuggestedPrice` | mínimo de puja · recomendado · precio de la prisa |
| `MarketConditions` | oferta, demanda, lluvia, atasco, vuelta de vacío |
| `AcceptanceForecast` | cuántos aceptarían y quién llegaría antes |
| `DemandSignal` | presiones con nombre, para poder explicarlas |
| `TariffCalibration` | **ajusta tu tarifa a los precios reales de tu ciudad** |

### La forma es la de inDrive

Su ayuda oficial describe dos números —precio recomendado y **mínimo
recomendado de puja**— y deja **peajes y tasas de aeropuerto fuera de la
tarifa**, a cargo del pasajero. `SuggestedPrice` tiene exactamente esa forma:
`minimum`, `recommended` y `extrasPaidSeparately` aparte, más un tercer número
que ellos no dan, `fast`: lo que cuesta que venga el conductor más cercano.

### Por qué la previsión de aceptación no es una curva inventada

Lo difícil de un mercado de pujas es saber a qué precio contesta alguien. Lo
habitual es inventar una curva y enseñar un porcentaje con dos decimales que
nadie ha medido. La 0.3.0 hacía eso, y estaba mal.

Con los tiempos de recogida reales que devuelve `calculateRouteMatrix`, el
**precio de reserva de cada conductor cercano es calculable**: es su
`BidAdvisor.breakEvenFare`. Y entonces «cuántos aceptarían a este precio» deja
de ser una estimación y pasa a ser un conteo. `AcceptanceForecast.estimated`
dice cuál de las dos cosas estás mirando, y es `true` incluso cuando hay
conductores pero alguno no pasó por la matriz.

### El tiempo de ir a recoger pesa más

Los estudios de aceptación de carreras coinciden en que a los conductores el
tiempo muerto les molesta **más** que el mismo tiempo dentro del trayecto: no
está pagado, no acerca al destino y compite con esperar algo mejor.
`PriceAdvisor.pickupAversion` lo recoge inflando ese tiempo al calcular el
precio de reserva. Con el valor por defecto, doce minutos de recogida se
valoran como diecinueve.

Es la consecuencia práctica: cuando todos los coches están lejos, el precio
sugerido **sube por encima de la tarifa**, porque a la tarifa no viene nadie.

### Demanda

`ratio ^ 0.6` sobre peticiones por conductor libre, con techo en 2,5×. El
exponente por debajo de 1 hace que el precio suba menos que proporcionalmente
al desequilibrio, que es lo correcto: la escasez se corrige sola en minutos y
una subida lineal sobrerreacciona a picos que se deshacen antes de notarse.

El atasco solo se cobra aparte si la tarifa **no** cobra por minuto; cuando lo
hace ya está dentro, y sumarlo sería cobrarlo dos veces.

### Ajustar la tarifa a tu ciudad

Las tarifas de las aplicaciones que ya operan no son públicas, cambian entre
ciudades y cambian con el tiempo: **no se pueden traer hechas en un paquete**.
Lo que sí se puede es medirlas.

`TariffCalibration.fit` toma precios observados —distancia, duración, importe—
y devuelve por mínimos cuadrados la bajada de bandera, el precio por kilómetro
y el precio por minuto que los reproducen. Hay una prueba que genera precios
con una tarifa conocida y comprueba que el ajuste **la redescubre exacta**.

Y avisa de lo que casi nadie mira: si en tus muestras la distancia y la
duración van de la mano —lo normal en ciudad— el modelo predice bien el total
pero **el reparto entre kilómetro y minuto es arbitrario**.
`TariffFit.splitIsReliable` lo dice, y `report()` lo escribe en el informe.

### Obsoleto

- **`FareAdvisor` y `FareSuggestion`**, en favor de `PriceAdvisor` y
  `SuggestedPrice`. Siguen funcionando y siguen probados; se retiran en la
  1.0.0.

### Corregido

- **`BidAdvisor.breakEvenFare` devolvía un céntimo de más** en algunos casos.
  El importe se redondea hacia arriba, y `1200 × 0.28 + 140` da
  `476.00000000000006` en coma flotante: un `ceil()` a secas subía a 477. La
  misma carrera daba dos números según cómo se escribiera la duración.

### Paso a inglés, en marcha

La API pública siempre estuvo en inglés. En esta versión pasan también a
inglés **los identificadores internos y todos los textos que se ven en
ejecución**: etiquetas del desglose de tarifa, factores del precio sugerido,
informe del calibrador y **todos los mensajes de excepción** de la capa de
cálculo, que son los que acaban en los registros de quien use el paquete.

El dartdoc está a medio camino: `geodesy` ya está en inglés y el resto sigue
en español. Se irá traduciendo en las próximas versiones. Es un cambio de
documentación: no afecta a ninguna firma ni a ningún comportamiento.

### Pruebas

**41 nuevas**, 376 en total.

## 0.3.0

**Capa de cálculo para taxi, VTC por pujas y rastreo por GPS.** Ocho módulos
de Dart puro que **no gastan ni una petición**: todo ocurre en el dispositivo.

Amazon Location dice dónde están las cosas y cómo se va de una a otra. Lo que
no dice —y lo que separa una demo de una aplicación que cobra— es cuánto ha
recorrido de verdad ese coche, cuánto se le cobra, si le compensa la carrera y
si conduce bien. Eso es lo que hay aquí.

### Añadido

| Módulo | Qué resuelve | Clase principal |
|---|---|---|
| Filtrado de GPS | el ruido que infla el kilometraje | `PositionFilter` |
| Registro de viaje | distancia, paradas y tiempos reales | `TripRecorder` |
| Tarificación | taxímetro con desglose auditable | `Tariff` |
| Progreso de ruta | ETA, maniobra y desvío, sin llamadas | `RouteTracker` |
| Subasta de carreras | el modelo de puja tipo inDrive | `RideAuction` |
| Economía del conductor | si la carrera compensa de verdad | `BidAdvisor` |
| Despacho | el conductor más cercano **en tiempo** | `DispatchPlanner` |
| Telemática | acelerones, frenazos, curvas, excesos | `TelemetryAnalyzer` |
| Geometría de caminos | proyección, recorte de históricos | `simplifyPath` |

### Las decisiones que importan

**El ruido del GPS no se suma.** Un receptor parado no repite coordenada:
rebota dentro de su círculo de incertidumbre, y en un cañón urbano ese círculo
son 30 m cada segundo. Sumar distancias entre lecturas consecutivas convierte
veinte minutos de espera en varios kilómetros que el pasajero paga. Hay una
prueba que simula exactamente eso: la suma ingenua da **más de 5 km** de un
coche aparcado, y `TripRecorder` da **menos de 50 m**.

**Un descarte por ruido es un dato, no un hueco.** Mientras el vehículo está
parado el filtro rechaza casi todas las lecturas. Si el registrador las
ignorase, el reloj se congelaría durante las esperas. Aquí el tiempo avanza con
todas las lecturas y solo la distancia depende de que se acepten.

**El dinero va en enteros.** Los importes son unidades menores —céntimos— y son
`int`. Un `double` no representa 0,10 exactamente, y sumar carreras así
descuadra la caja. El redondeo ocurre **una sola vez**, al final.

**Nunca se devuelve solo un total.** `FareBreakdown` trae una línea por
concepto con la cuenta que la produjo (`12,40 km × 1,10`). Un número suelto no
se puede defender en una reclamación seis meses después.

**La tarifa nocturna se parte de verdad.** Un trayecto de 21:50 a 22:10 tiene
diez minutos de cada tarifa. Cobrarlo entero a la de salida —lo que hace casi
todo el software— es incorrecto y en mercado regulado es sancionable. El tiempo
se reparte de forma exacta; la distancia, en proporción al tiempo en marcha, y
esa aproximación está documentada donde se usa.

**El tiempo que falta no es una regla de tres.** `duración × (1 − fracción)` se
equivoca en cuanto la ruta mezcla ciudad y autopista. `RouteTracker` usa el
tiempo que el servicio dio **por maniobra**.

**El desvío necesita varias lecturas.** Recalcular la ruta con un solo rebote
del GPS es una petición facturada tirada, y en una calle estrecha pasa varias
veces por minuto.

**La línea recta elige mal al conductor.** El que está a 300 m al otro lado del
río tarda quince minutos. `DispatchPlanner` preselecciona gratis por línea
recta y refina solo a esos con la matriz: 12 celdas por carrera en vez de 800.

**Al conductor le importa el neto por hora, no el importe.** Una carrera de
8 € a doce minutos de distancia deja 15,82 €/h; una de 5 € a dos minutos deja
20,00 €/h. `BidAdvisor` hace esa cuenta, contando el trayecto muerto que no
paga nadie, y `breakEvenFare` dice qué contraofertar.

**La aceleración no se deriva de las posiciones.** Hacerlo amplifica el ruido
al cuadrado y produce frenazos en coches parados. `TelemetryAnalyzer` exige la
velocidad del receptor, que viene del efecto Doppler, y prefiere no detectar a
inventar.

### Sobre lo que no es una medición

`FareAdvisor.acceptanceProbability` es una **curva logística de dos parámetros**,
no un dato. Los valores por defecto son una forma razonable para empezar; hay
que calibrarlos con el historial propio. Está dicho así de claro en la
documentación de la clase a propósito.

### Pruebas

**106 pruebas nuevas**, 335 en total. Cubren los casos que rompen las
implementaciones ingenuas: el coche parado que acumula kilómetros, la espera
que no se cobra, la franja nocturna a caballo de la medianoche, el rumbo que
cruza el norte, el túnel que deja al vehículo fuera de la ventana de búsqueda,
y el conductor que parece cerca y no lo está.

## 0.2.0

**El paquete cambia de nombre.** Antes se publicaba como `compass_maps` y
`compass_maps_flutter`; ahora es `nativ_maps` y `nativ_maps_flutter`. El código
es el mismo y la versión sigue la serie anterior, pero **cambian todos los
`import` y todos los nombres de clase**, y eso es lo que justifica subir la
menor en vez de publicar un parche.

Los nombres antiguos quedan en pub.dev marcados como descontinuados, apuntando
aquí. No van a recibir más versiones.

### Cambiado

- **Nombres de paquete**

  | Antes | Ahora |
  |---|---|
  | `compass_maps` | **`nativ_maps`** |
  | `compass_maps_flutter` | **`nativ_maps_flutter`** |
  | `compass_maps_google` | **`nativ_maps_google`** |
  | `compass_maps_sigv4` | **`nativ_maps_sigv4`** |

- **Nombres de clase.** El prefijo `Compass` pasa a `Nativ`, sin excepción:

  | Antes | Ahora |
  |---|---|
  | `CompassMap` | **`NativMap`** |
  | `CompassMapController` | **`NativMapController`** |
  | `CompassMaps` | **`NativMaps`** |
  | `CompassMapsException` | **`NativMapsException`** |
  | `CompassMapsConfigurationException` | **`NativMapsConfigurationException`** |
  | `CompassOfflineManager` | **`NativOfflineManager`** |

- **El repositorio se movió** a `github.com/delioribas/nativ_maps`. Las
  dependencias por git tienen que apuntar a la etiqueta `v0.2.0` de la URL
  nueva; GitHub redirige la antigua, pero no conviene depender de eso.

### Sin cambios, a propósito

- **`compassEnabled` sigue llamándose así.** Es la brújula del mapa, no el
  nombre del paquete: es el parámetro que espera `maplibre_gl` y es el mismo
  nombre que usa `GoogleMap`, así que renombrarlo habría roto la promesa de
  migrar cambiando un solo `import`.
- Ninguna firma, ningún parámetro y ningún comportamiento. Solo nombres.

### Cuidado si usas `ProxyCredentials`

Las cabeceras que el cliente manda a tu proxy **cambian de nombre**:

```diff
-X-Compass-Service: geo-places
-X-Compass-Region:  us-east-1
+X-Nativ-Service:   geo-places
+X-Nativ-Region:    us-east-1
```

Tu proxy firma leyendo esas cabeceras. Si actualizas el paquete sin actualizar
el proxy, dejará de saber con qué servicio firmar y AWS devolverá un `403`.
Es el único cambio de este renombrado que **sale del proceso**.

## 0.1.1

**Baja el suelo de versiones cinco versiones de Dart.** La 0.1.0 exigía
`sdk: ^3.13.0` y `meta: ^1.19.0`, que en la práctica lo dejaban inservible
para cualquier proyecto que no estuviera ya en Flutter 3.47.

### Cambiado

- `sdk`: `^3.13.0` → **`^3.8.0`**. El suelo real, comprobado ejecutando el
  análisis y las pruebas con Dart 3.8.1: por debajo falla porque el paquete
  usa elementos con `?` en literales de colección, estables desde Dart 3.8.
- `meta`: `^1.19.0` → **`^1.16.0`**. Este era el bloqueo peor, porque **lo fija
  el SDK de Flutter** y no hay `dependency_override` que valga: Flutter 3.32 y
  3.35 traen `meta` 1.16.0, la 3.41 trae 1.17.0 y la 3.44 trae 1.18.0. Pedir
  `^1.19.0` las excluía todas. De `meta` solo se usan `@immutable`,
  `@internal` y `@visibleForTesting`, las tres disponibles desde 1.2.0.
- `http`: `^1.6.0` → **`^1.1.0`**. Solo se usan `Client`, `BaseClient`,
  `Request`, `Response` y `StreamedResponse`.

### Corregido

- **`@internal` rompía la compilación en Flutter 3.32.**
  `package:flutter/foundation.dart` no reexporta esa anotación hasta versiones
  recientes, y los imports de `meta` se habían quitado porque el linter de
  Flutter 3.47 los marcaba como redundantes. Doce errores de
  `undefined_annotation` que solo aparecían en el suelo.

## 0.1.0

Primera versión. **44 operaciones de Amazon Location.**

### Places v2 · 7 operaciones

`autocomplete`, `searchText`, `reverseGeocode`, `getPlace`, `geocode`,
`searchNearby` y `suggest`, con el modelo de dirección completo de v2 —país,
región, subregión, localidad, distrito, manzana, calle desglosada en piezas,
número, edificio e intersección—, contactos, horarios, puntos de acceso, zona
horaria y puntuación de coincidencia.

### Routes v2 · 5 operaciones

`calculateRoutes` (con **peajes**, alternativas e indicaciones paso a paso),
`calculateRouteMatrix`, **`calculateIsolines`** en los dos sentidos,
**`snapToRoads`** con troceado y cosido automáticos, y `optimizeWaypoints` con
citas, tiempos de servicio y descansos de conductor.

### Maps v2 · 5 operaciones

`styleDescriptorUrl` con **los 10 parámetros** del descriptor —incluidos
tráfico, relieve, edificios 3D, curvas de nivel y densidad de puntos de
interés—, `staticMap` con los tres modos de encuadre, y las URLs de teselas,
glifos y sprites.

### Geovallas · 12 operaciones

`putGeofence`, `batchPutGeofence`, `getGeofence`, `listGeofences`,
`batchDeleteGeofence`, `batchEvaluateGeofences`, **`forecastGeofenceEvents`**
—que predice entradas y salidas antes de que ocurran— y las cinco de gestión de
colecciones.

`GeofenceGeometry` admite círculo, polígono y multipolígono, cierra los anillos
sola y resuelve `contains` **en local**, sin gastar una petición.

### Rastreo de dispositivos · 15 operaciones

`batchUpdateDevicePosition` con troceado automático, `getDevicePosition`,
`batchGetDevicePosition`, `getDevicePositionHistory`, `listDevicePositions` con
filtro por polígono, `batchDeleteDevicePositionHistory`,
**`verifyDevicePosition`** —detecta ubicaciones falseadas— y las ocho de
gestión de rastreadores y de enlace con geovallas.

### Infraestructura

- Interfaz `Credentials` con `ApiKeyCredentials`, `ProxyCredentials` y
  `HeaderCredentials`.
- **Comprobación de camino de autenticación**: geovallas y rastreo rechazan la
  clave de API **antes de enviar**, con un mensaje que dice qué hacer, en vez
  de dejar que llegue como un `403` indistinguible.
- `Budget`: tope de unidades facturables por ventana **deslizante**, con la
  cuenta real por operación (isócronas por umbral, matriz por par, `snapToRoads`
  por trozo).
- Límites duros comprobados antes de enviar: 15×100 en la matriz sin acotar,
  5 umbrales en isócronas, 10 posiciones por lote en geovallas, 3 propiedades
  por geovalla, 1 000 vértices por polígono.
- `LatLng` y `LatLngBounds` que **lanzan** ante datos ilegibles en vez de
  devolver `LatLng(0, 0)`.
- Decodificador y **codificador** de Flexible Polyline de HERE, verificados
  contra el vector oficial del repositorio de HERE.
- Reintentos con retroceso exponencial y fluctuación, respetando `Retry-After`,
  que **no** reintentan un `400` ni un `403`.
- 143 pruebas con `MockClient` que verifican **la petición enviada**, no solo
  la respuesta.
