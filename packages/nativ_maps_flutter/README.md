# nativ_maps_flutter

**Amazon Location Service con la forma de Google Maps.**

Un widget de mapa sobre MapLibre con marcadores, polilíneas, polígonos,
círculos, **clústeres nativos**, **mapas de calor** y **regiones sin conexión**,
más las **44 operaciones** de Places, Routes, Maps, geovallas y rastreo.

```dart
import 'package:nativ_maps_flutter/nativ_maps_flutter.dart';

final maps = NativMaps(
  region: 'us-east-1',
  credentials: const ApiKeyCredentials('tu-clave'),
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

**Instalando solo este paquete ya tienes las 44 operaciones**: reexporta el
núcleo entero.

## La tesis

El `LatLng` que devuelve una búsqueda es el que acepta un marcador:

```dart
final ruta = (await maps.routes.calculateRoutes(
  origin: aqui, destination: alli,
)).best!;

// Sin convertir nada.
await controlador.addPolyline(
  Polyline(polylineId: const PolylineId('ruta'), points: ruta.points),
);
```

> Si sabes usar `google_maps_flutter`, ya sabes usar la mitad de esto sin leer
> nada. Y la otra mitad es lo que Google no te daba.

## Lo que Google no te daba

| | `google_maps_flutter` | Aquí |
|---|---|---|
| **Isócronas** | no existe | `calculateIsolines` |
| **Pegado a carretera** | no existe | `snapToRoads` |
| **Coste de peajes** | no existe | `Toll` |
| **Mapas sin conexión** | **prohibido por sus condiciones** | `controller.offline` |
| Búsqueda y geocodificación | otra API, otra clave | mismo cliente |
| Clústeres | clase gestora en Dart | **nativo, en el motor** |
| Mapa de calor | tipo cerrado | **capa nativa** |
| Modo oscuro | filtro sobre teselas | **lo renderiza el servidor** |

## ⚠️ Requisitos de Android

- **AGP 8.x**, no 9.x — `maplibre_gl` 0.27.0 aún no es compatible con AGP 9
- **JDK 21** — `flutter config --jdk-dir="/ruta/al/jdk-21"`

Los detalles están en «Limitaciones conocidas» del
[README del repositorio](https://github.com/delioribas/nativ_maps#limitaciones-conocidas).

## Documentación

- [Recetas](https://github.com/delioribas/nativ_maps/blob/main/doc/RECETAS.md) — 40 ejemplos copiables
- [Migrar desde google_maps_flutter](https://github.com/delioribas/nativ_maps/blob/main/doc/MIGRACION.md)
- [Para agentes de IA](https://github.com/delioribas/nativ_maps/blob/main/AGENTS.md)
- [Cobertura](https://github.com/delioribas/nativ_maps/blob/main/doc/COBERTURA.md)

## Licencia

MIT. Los datos de mapas son de Amazon Location Service y sus proveedores; **la
atribución es obligatoria y visible**.
