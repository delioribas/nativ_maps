# Changelog

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

### Quitado

- La dependencia de `collection`, que estaba declarada y **no se importaba en
  ningún fichero**.

### Cambiado, además

- `flutter`: `>=3.41.0` → **`>=3.32.0`**. Es la primera versión estable que
  trae Dart 3.8, así que es la que corresponde al nuevo suelo del SDK.

## 0.1.0

Primera versión.

### El widget

- `NativMap` sobre MapLibre Native, con Android e iOS **verificados
  compilando**, no declarados.
- `NativMapController` con los nombres exactos de `google_maps_flutter`:
  `animateCamera`, `moveCamera`, `getVisibleRegion`, `getZoomLevel`,
  `getScreenCoordinate`, `getLatLng`, `takeSnapshot`, `setMapStyle`.
- Las **nueve** fábricas de `CameraUpdate` de Google, más `bearingTo` y
  `tiltTo`, que Google no tiene.

### Superposiciones

- `Marker` con rumbo, etiqueta, orden de apilado y globo de información.
- `Polyline` con extremos, uniones y patrones discontinuos.
- `Polygon` con agujeros y `Circle` **geodésico**, con el radio en metros.
- **`ClusterManager` nativo**: agrupa el motor, por tesela, no una clase en
  Dart que recalcula en cada movimiento de cámara.
- **`Heatmap` como capa nativa**, con rampa de color, radio e intensidad
  propios.
- `InfoWindow` reimplementada como widget de Flutter: cabe cualquier cosa
  dentro.
- Sincronización **agrupada por microtask**: añadir 300 marcadores en un bucle
  es una sola llamada al motor.
- Hit-test **nativo** con `queryRenderedFeatures`, no el más cercano en píxeles.

### Sin conexión

`NativOfflineManager` con descarga de regiones y progreso observable, tope de
caché, listado, borrado, caducidad automática y fusión de una base preparada.
**`google_maps_flutter` no puede dar esto**: sus condiciones prohíben cachear
teselas.

### Estilo

`StyleEditor` para retocar el estilo en caliente: apagar capas por palabra
clave, cambiar colores, grosores y opacidades, y aplicar propiedades de pintura
a medida.

### Las 44 operaciones

Reexporta `nativ_maps` entero: instalando solo este paquete se tienen todas.
