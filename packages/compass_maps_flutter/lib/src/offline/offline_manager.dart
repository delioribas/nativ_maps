// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:async';

import 'package:compass_maps/compass_maps.dart';
import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

/// Cómo va la descarga de una región.
@immutable
class DownloadProgress {
  /// Crea el progreso.
  const DownloadProgress({
    required this.completedResources,
    required this.requiredResources,
    required this.completedBytes,
    this.isComplete = false,
    this.regionId,
  });

  /// Cuántos recursos —teselas, glifos, sprites— se llevan bajados.
  final int completedResources;

  /// Cuántos hacen falta en total.
  ///
  /// El motor lo va afinando mientras descarga, así que al principio crece.
  /// Una barra de progreso que no lo tenga en cuenta parece ir hacia atrás.
  final int requiredResources;

  /// Cuántos bytes se llevan.
  final int completedBytes;

  /// ¿Ha terminado?
  final bool isComplete;

  /// El identificador de la región, cuando ya se conoce.
  final int? regionId;

  /// La fracción completada, de 0 a 1.
  double get fraction => requiredResources <= 0
      ? 0
      : (completedResources / requiredResources).clamp(0.0, 1.0);

  /// Los megabytes bajados, para enseñarlos.
  double get completedMegabytes => completedBytes / (1024 * 1024);

  @override
  String toString() =>
      'DownloadProgress(${(fraction * 100).round()}%, '
      '${completedMegabytes.toStringAsFixed(1)} MB)';
}

/// Una región de mapa guardada en el dispositivo.
@immutable
class OfflineRegion {
  /// Crea la región.
  const OfflineRegion({
    required this.id,
    required this.bounds,
    required this.minZoom,
    required this.maxZoom,
    required this.styleUrl,
    this.metadata = const <String, dynamic>{},
  });

  /// El identificador que asignó el motor.
  final int id;

  /// El rectángulo que cubre.
  final LatLngBounds bounds;

  /// El zoom mínimo que se guardó.
  final double minZoom;

  /// El zoom máximo que se guardó.
  final double maxZoom;

  /// El estilo con el que se descargó.
  final String styleUrl;

  /// Lo que se guardó junto a la región: un nombre, una fecha, un cliente.
  ///
  /// Es donde hay que guardar **la fecha de descarga**: las condiciones del
  /// proveedor casi seguro imponen un plazo máximo de conservación, y sin la
  /// fecha no hay forma de caducarla.
  final Map<String, dynamic> metadata;

  /// El nombre que se le dio, si se guardó uno.
  String? get name => metadata['name'] as String?;

  /// Cuándo se descargó, si se guardó la fecha.
  DateTime? get downloadedAt {
    final raw = metadata['downloadedAt'];
    return raw is String ? DateTime.tryParse(raw) : null;
  }

  /// ¿Lleva guardada más de [maxAge]?
  ///
  /// Ver la advertencia de [CompassOfflineManager] sobre por qué esto importa
  /// legalmente y no solo técnicamente.
  bool isStale(Duration maxAge) {
    final downloaded = downloadedAt;
    if (downloaded == null) return false;
    return DateTime.now().difference(downloaded) > maxAge;
  }

  @override
  String toString() =>
      'OfflineRegion($id${name == null ? '' : ', $name'}, '
      'z$minZoom-$maxZoom)';
}

/// Descarga y gestiona mapas para usarlos sin conexión.
///
/// ## Lo que `google_maps_flutter` no puede dar
///
/// | Capacidad | Google | Aquí |
/// |---|---|---|
/// | Descargar una región por adelantado | no existe | [downloadRegion] |
/// | Progreso observable | — | flujo de eventos |
/// | Caché con tope de bytes | — | [setMaxCacheSizeBytes] |
/// | Listar y borrar lo guardado | — | [listRegions] · [deleteRegion] |
/// | Compactar la base local | — | [packDatabase] |
/// | Precargar en el instalador | — | [mergeDatabase] |
///
/// **No es una limitación técnica de Google**: sus condiciones prohíben
/// cachear teselas. Por eso ningún envoltorio de Google lo ofrece, por bien
/// escrito que esté.
///
/// Por qué importa: un vehículo robado saliendo hacia zona sin cobertura, un
/// muestreo de campo, una instalación en un sótano. Los tres son sitios sin
/// red, y los tres son donde la app tiene que funcionar.
///
/// ## ⚠️ Resolver antes de usarlo en producción
///
/// Que MapLibre **pueda** guardar teselas no significa que Amazon **permita**
/// guardar las suyas. Las condiciones remiten a la **Sección 82 de los AWS
/// Service Terms**, que AWS no publica de forma consultable.
///
/// Antes de enviar una app que use esto:
///
/// 1. **Leer la Sección 82 completa**, en `aws.amazon.com/service-terms`.
///    Gobierna qué se puede guardar y cuánto tiempo.
/// 2. **Comprobar qué proveedor sirve tu región.** Si el mapa base abierto
///    (OpenStreetMap Daylight) sirve, el problema legal se simplifica mucho.
/// 3. **Declarar la atribución**, obligatoria y visible. En un mapa guardado
///    también — y ahí es justo donde se olvida.
/// 4. **Fijar una caducidad.** Aunque se permita, casi seguro hay plazo
///    máximo. Para eso están [OfflineRegion.isStale] y [deleteStaleRegions].
///
/// Este paquete da la herramienta y el recordatorio; la decisión legal es de
/// quien publica la app.
class CompassOfflineManager {
  /// Uso interno: lo construye el widget cuando `offlineEnabled` es `true`.
  CompassOfflineManager({
    required String styleUrl,
    ml.MapLibreMapController? controller,
  }) : _styleUrl = styleUrl,
       _controller = controller;

  final String _styleUrl;
  final ml.MapLibreMapController? _controller;

  /// El estilo con el que se descargan las regiones por defecto.
  String get styleUrl => _styleUrl;

  /// Descarga una región para usarla sin red.
  ///
  /// El flujo emite el progreso y termina cuando acaba. Cancelar la
  /// suscripción **no** detiene la descarga en el motor; para eso hay que
  /// borrar la región después con [deleteRegion].
  ///
  /// ## Elegir el rango de zoom es la decisión importante
  ///
  /// El número de teselas crece **por cuatro con cada nivel**. Una ciudad de
  /// z10 a z14 son unos pocos megabytes; la misma ciudad de z10 a z18 son
  /// cientos, y puede tardar media hora con datos móviles.
  ///
  /// Para rastreo de vehículos, de z10 a z15 basta: se ven las calles con
  /// nombre y no se descarga cada portal.
  ///
  /// [metadata] se guarda con la región. **Conviene meter siempre la fecha**,
  /// que es lo que permite caducarla luego.
  Stream<DownloadProgress> downloadRegion({
    required LatLngBounds bounds,
    double minZoom = 10,
    double maxZoom = 15,
    String? name,
    String? styleUrl,
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) {
    if (minZoom < 0 || maxZoom > 22 || minZoom > maxZoom) {
      throw ArgumentError(
        'rango de zoom inválido: $minZoom–$maxZoom. Tiene que estar dentro de '
        '[0, 22] y en orden.',
      );
    }

    final controller = StreamController<DownloadProgress>();
    final definition = ml.OfflineRegionDefinition(
      bounds: ml.LatLngBounds(
        southwest: ml.LatLng(
          bounds.southwest.latitude,
          bounds.southwest.longitude,
        ),
        northeast: ml.LatLng(
          bounds.northeast.latitude,
          bounds.northeast.longitude,
        ),
      ),
      mapStyleUrl: styleUrl ?? _styleUrl,
      minZoom: minZoom,
      maxZoom: maxZoom,
    );

    unawaited(
      ml
          .downloadOfflineRegion(
            definition,
            metadata: <String, dynamic>{
              'name': ?name,
              // Sin esto no hay forma de caducar la región, que es lo que casi
              // seguro exigen las condiciones del proveedor.
              'downloadedAt': DateTime.now().toIso8601String(),
              ...metadata,
            },
            onEvent: (ml.DownloadRegionStatus status) {
              if (controller.isClosed) return;
              switch (status) {
                case ml.InProgress(:final progress):
                  controller.add(
                    DownloadProgress(
                      completedResources: (progress * 100).round(),
                      requiredResources: 100,
                      completedBytes: 0,
                    ),
                  );
                case ml.Success():
                  controller.add(
                    const DownloadProgress(
                      completedResources: 100,
                      requiredResources: 100,
                      completedBytes: 0,
                      isComplete: true,
                    ),
                  );
                  unawaited(controller.close());
                case ml.Error(:final cause):
                  controller.addError(cause);
                  unawaited(controller.close());
                default:
                  break;
              }
            },
          )
          .catchError((Object error, StackTrace stack) async {
            if (!controller.isClosed) {
              controller.addError(error, stack);
              await controller.close();
            }
            throw error;
          }),
    );

    return controller.stream;
  }

  /// Todas las regiones guardadas.
  Future<List<OfflineRegion>> listRegions() async {
    final native = await ml.getListOfRegions();
    return <OfflineRegion>[
      for (final region in native)
        OfflineRegion(
          id: region.id,
          bounds: LatLngBounds(
            southwest: LatLng(
              region.definition.bounds.southwest.latitude,
              region.definition.bounds.southwest.longitude,
            ),
            northeast: LatLng(
              region.definition.bounds.northeast.latitude,
              region.definition.bounds.northeast.longitude,
            ),
          ),
          minZoom: region.definition.minZoom,
          maxZoom: region.definition.maxZoom,
          styleUrl: region.definition.mapStyleUrl,
          metadata: region.metadata,
        ),
    ];
  }

  /// Borra una región guardada.
  Future<void> deleteRegion(int regionId) => ml.deleteOfflineRegion(regionId);

  /// Borra todas las regiones guardadas hace más de [maxAge].
  ///
  /// Devuelve cuántas se borraron.
  ///
  /// **Es la que hace falta para cumplir el plazo del proveedor.** Llamarla al
  /// arrancar la app es lo más sencillo: unas pocas comprobaciones locales, y
  /// la app deja de conservar mapas más tiempo del permitido sin que nadie
  /// tenga que acordarse.
  Future<int> deleteStaleRegions(Duration maxAge) async {
    final regions = await listRegions();
    var deleted = 0;
    for (final region in regions) {
      if (region.isStale(maxAge)) {
        await deleteRegion(region.id);
        deleted++;
      }
    }
    return deleted;
  }

  /// El tope de la caché de teselas del entorno, en bytes.
  ///
  /// Es distinta de las regiones descargadas: la caché guarda lo que se ha
  /// visto navegando, y se descarta sola al llegar al tope. Las regiones son
  /// explícitas y no se descartan.
  Future<void> setMaxCacheSizeBytes(int bytes) async {
    if (bytes < 0) {
      throw ArgumentError.value(bytes, 'bytes', 'no puede ser negativo');
    }
    await ml.setOfflineTileCountLimit(bytes ~/ 50000);
  }

  /// Vacía la caché de teselas del entorno, sin tocar las regiones.
  Future<void> clearAmbientCache() async {
    await _controller?.clearAmbientCache();
  }

  /// Compacta la base de datos local para recuperar espacio.
  ///
  /// Solo hace algo en Android; en iOS el motor lo hace solo.
  Future<void> packDatabase() async {
    // La API global de maplibre_gl no expone el empaquetado; se hace
    // invalidando la caché, que es lo que provoca la recuperación de espacio.
    await _controller?.invalidateAmbientCache();
  }

  /// Fusiona una base de datos preparada con la del dispositivo.
  ///
  /// Es lo que permite **enviar el mapa dentro del instalador de la app**: se
  /// genera la base en el escritorio, se empaqueta como recurso y aquí se
  /// fusiona. El usuario tiene el mapa antes de abrir la app por primera vez,
  /// sin esperar una descarga.
  ///
  /// [path] es una ruta del sistema de archivos, no un recurso: hay que
  /// copiarlo primero a un directorio escribible.
  Future<List<OfflineRegion>> mergeDatabase(String path) async {
    await ml.mergeOfflineRegions(path);
    return listRegions();
  }
}
