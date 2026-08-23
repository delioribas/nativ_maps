# Changelog

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

Primera versión.

- `SigV4Signer`: firma AWS Signature Version 4 con `crypto` como única
  dependencia, en lugar de las dieciséis transitivas de `aws_signature_v4`.
- **Verificado contra el vector oficial `get-vanilla`** de la suite de pruebas
  de SigV4 de AWS: el valor hexadecimal exacto, no solo la forma.
- Codificación RFC 3986 correcta —que no es la de `Uri.encodeComponent`—,
  cadena de consulta ordenada, cabeceras canónicas y colapso de espacios.
- `SigV4Credentials` con renovación automática, caché con margen de caducidad y
  una sola renovación compartida entre llamadas simultáneas.
- `mapHeaders` para firmar **también las teselas del mapa**, que es lo que
  ningún otro camino permite.
- El nombre de firma lo pone el enum `AlsService`: `geo-places`, `geo-routes`,
  `geo-maps` en la generación v2, y `geo` en geovallas y rastreo. No se puede
  escribir mal.
