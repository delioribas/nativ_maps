// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

/// Capa de compatibilidad para migrar de `google_maps_flutter`.
///
/// ## Qué hace, en una frase
///
/// Que el código escrito para `google_maps_flutter` compile y funcione contra
/// Amazon Location **cambiando el `import`**.
///
/// ```diff
/// - import 'package:google_maps_flutter/google_maps_flutter.dart';
/// + import 'package:compass_maps_google/compass_maps_google.dart';
/// ```
///
/// ## Lo que NO hace
///
/// **No depende de `google_maps_flutter`**, ni llama a ninguna API de Google,
/// ni necesita una clave de Google. No hay nada de Google en tiempo de
/// ejecución: solo se toma prestado el vocabulario.
///
/// ## El mecanismo: `typedef` y `extension`, nunca clases
///
/// El núcleo ya llama `LatLng` a `LatLng`, `Marker` a `Marker` y
/// `CameraUpdate.newLatLngZoom()` a lo que Google llama igual. **No hay nada
/// que traducir**: la mayor parte de este paquete es reexportación.
///
/// Lo único que difiere son unos pocos nombres de método del controlador y el
/// estilo JSON, y eso se resuelve con `extension`. Consecuencias:
///
/// - **Coste nulo en ejecución.** Un alias no crea objetos.
/// - **El núcleo queda libre.** Una `extension` no hereda ni envuelve.
/// - **Reversible.** Borrar este paquete no rompe nada debajo.
/// - **Conviven.** `animateCamera()` en una línea y `mostrarVehiculo()` en la
///   siguiente.
///
/// ## Lo que se omite, y por qué
///
/// | Método de Google | Motivo |
/// |---|---|
/// | `setIndoorEnabled` | Amazon Location no tiene planos de interior |
/// | `setLiteModeEnabled` | exclusivo de Android + Google |
/// | `cloudMapId` | estilos alojados en la nube de Google |
/// | `AdvancedMarker` | API propietaria reciente de Google |
///
/// Se omiten y se documentan; **nunca un hueco que devuelve `null` en
/// silencio**. Un método que existe y no hace nada es peor que uno que no
/// existe: el segundo lo caza el compilador.
library;

export 'package:compass_maps_flutter/compass_maps_flutter.dart';

export 'src/compat.dart' show GoogleMapsCompat, MapColorSchemeCompat, MapType;
export 'src/google_map_style.dart'
    show GoogleMapStyle, GoogleStyleReport, GoogleStyleRule, GoogleStyler;
export 'src/style_translator.dart' show GoogleStyleApplier;
