# Ejemplo de `compass_maps_flutter`

[`lib/main.dart`](lib/main.dart) es el mapa mínimo: lo justo para tener un mapa
de Amazon Location con un marcador y una ruta pintada.

La app completa —**ocho pantallas** que ejercitan las 44 operaciones, con
clústeres, mapas de calor, isócronas, pegado a carretera y descarga sin
conexión— está en
[`example/`](https://github.com/delioribas/compass_maps/tree/main/example) en la
raíz del repositorio:

```sh
cd example
flutter run --dart-define=ALS_API_KEY=tu-clave --dart-define=ALS_REGION=us-east-1
```

> ⚠️ Android necesita **AGP 8.x** (no 9.x) y **JDK 21**. Ver «Limitaciones
> conocidas» en el README del repositorio.
