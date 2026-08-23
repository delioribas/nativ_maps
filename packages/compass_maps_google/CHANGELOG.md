# Changelog

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

- `typedef` y `extension` sobre `compass_maps_flutter`. **Coste nulo en
  ejecución**: no hay clases envoltorio.
- `GoogleMapsCompat` con los nombres de método de `google_maps_flutter`.
- **Traductor de estilos JSON de Google**: los 27 `featureType`, los 9
  `elementType` y los 8 *stylers* de la referencia de Google, con la aritmética
  de color en el orden que documenta Google.
- `GoogleStyleReport`: dice **qué reglas no se aplicaron**, en vez de tragarse
  en silencio lo que no entiende.
- `MapType` y `MapColorSchemeCompat` con su traducción a los tipos propios.
- Los cuatro métodos de Google sin equivalente real están **omitidos y
  documentados**, nunca devolviendo `null` en silencio.
