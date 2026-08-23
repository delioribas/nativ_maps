# Changelog

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
