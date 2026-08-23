// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:compass_maps/src/client/transport.dart';
import 'package:compass_maps/src/core/enums.dart';
import 'package:compass_maps/src/core/json.dart';
import 'package:compass_maps/src/core/lat_lng.dart';
import 'package:compass_maps/src/geofencing/models.dart';
import 'package:meta/meta.dart';

/// Las **12 operaciones** de geovallas de Amazon Location.
///
/// | Método | Endpoint | Para qué |
/// |---|---|---|
/// | [putGeofence] | `PUT /collections/{c}/geofences/{g}` | crear o cambiar una zona |
/// | [batchPutGeofence] | `POST …/put-geofences` | hasta 10 de golpe |
/// | [getGeofence] | `GET …/geofences/{g}` | leer una |
/// | [listGeofences] | `POST …/list-geofences` | listarlas |
/// | [batchDeleteGeofence] | `POST …/delete-geofences` | borrar varias |
/// | [batchEvaluateGeofences] | `POST …/positions` | **¿entró o salió?** |
/// | [forecastGeofenceEvents] | `POST …/forecast-geofence-events` | **¿va a entrar?** |
/// | [createCollection] | `POST /collections` | crear la colección |
/// | [describeCollection] | `GET /collections/{c}` | leerla |
/// | [updateCollection] | `PATCH /collections/{c}` | cambiarla |
/// | [deleteCollection] | `DELETE /collections/{c}` | borrarla |
/// | [listCollections] | `POST /list-collections` | listarlas |
///
/// ## ⚠️ Tres cosas que no son como en Places, Routes y Maps
///
/// Esta familia es de la **generación anterior**, y se nota en tres sitios:
///
/// 1. **Hay que crear un recurso.** Una colección de geovallas se crea con
///    [createCollection] o en la consola. No es como v2, donde no se crea nada.
/// 2. **No admite clave de API.** Las claves de Amazon Location solo cubren
///    Places, Routes y Maps. Aquí hacen falta credenciales SigV4 — un proxy o
///    `compass_maps_sigv4`. Intentarlo con clave se corta antes de enviar, con
///    un mensaje que lo dice.
/// 3. **El plano de control va a otro host**, con el prefijo `cp.`. Se resuelve
///    solo, pero explica por qué hay dos valores en `AlsService`.
///
/// ## Lo que de verdad justifica usarla
///
/// [forecastGeofenceEvents]. No dice dónde está el vehículo: dice **dónde va a
/// estar**. Avisar seis minutos antes de que salga de la zona permitida es una
/// operación distinta de avisar cuando ya salió.
class GeofencingClient {
  /// Construye el cliente. Uso interno: llega ya montado en `CompassMaps`.
  @internal
  GeofencingClient({required AlsTransport transport}) : _transport = transport;

  final AlsTransport _transport;

  static const AlsService _data = AlsService.geofencing;
  static const AlsService _control = AlsService.geofencingControl;

  /// Máximo de posiciones por llamada a [batchEvaluateGeofences].
  static const int maxPositionsPerBatch = 10;

  /// Máximo de geovallas por llamada a [batchPutGeofence].
  static const int maxGeofencesPerBatch = 10;

  // ─── Geovallas ────────────────────────────────────────────────────────

  /// Crea o reemplaza una geovalla.
  ///
  /// ```dart
  /// await maps.geofencing.putGeofence(
  ///   collectionName: 'zonas-permitidas',
  ///   geofenceId: 'bodega-norte',
  ///   geometry: GeofenceGeometry.circle(
  ///     center: LatLng(-0.1807, -78.4678),
  ///     radiusMeters: 500,
  ///   ),
  ///   properties: {'cliente': 'ACME', 'tipo': 'bodega'},
  /// );
  /// ```
  ///
  /// [properties] admite **tres** entradas como mucho, con claves de 20
  /// caracteres y valores de 40. Viajan **dentro de cada evento** que dispare
  /// la geovalla, así que es donde se mete lo que hará falta al recibirlo sin
  /// tener que consultarlo.
  ///
  /// Una geovalla recién creada tarda un momento en pasar a `ACTIVE`, y hasta
  /// entonces **no dispara nada**. Evaluar contra una en `PENDING` no falla:
  /// simplemente no salta, que es peor.
  Future<Geofence> putGeofence({
    required String collectionName,
    required String geofenceId,
    required GeofenceGeometry geometry,
    Map<String, String> properties = const <String, String>{},
  }) async {
    _checkProperties(properties);
    final json = await _transport.sendJson(
      operation: 'PutGeofence',
      service: _data,
      method: 'PUT',
      path:
          '/geofencing/v0/collections/${_seg(collectionName)}'
          '/geofences/${_seg(geofenceId)}',
      body: <String, dynamic>{
        'Geometry': geometry.toJson(),
        if (properties.isNotEmpty) 'GeofenceProperties': properties,
      },
    );
    return Geofence(
      geofenceId: Json.string(json, 'GeofenceId') ?? geofenceId,
      geometry: geometry,
      createTime: Json.dateTime(json, 'CreateTime'),
      updateTime: Json.dateTime(json, 'UpdateTime'),
      properties: properties,
    );
  }

  /// Crea o reemplaza hasta 10 geovallas de una vez.
  ///
  /// **No falla entera**: procesa lo que puede y devuelve los fallos uno a
  /// uno. Hay que mirar `errors`, porque la respuesta es 200 aunque falle la
  /// mitad.
  Future<BatchResult> batchPutGeofence({
    required String collectionName,
    required List<Geofence> geofences,
  }) async {
    if (geofences.isEmpty) {
      throw ArgumentError.value(geofences, 'geofences', 'no puede estar vacío');
    }
    if (geofences.length > maxGeofencesPerBatch) {
      throw ArgumentError.value(
        geofences.length,
        'geofences',
        'el máximo son $maxGeofencesPerBatch por llamada; trocea la lista',
      );
    }

    final json = await _transport.sendJson(
      operation: 'BatchPutGeofence',
      service: _data,
      method: 'POST',
      path: '/geofencing/v0/collections/${_seg(collectionName)}/put-geofences',
      body: <String, dynamic>{
        'Entries': <dynamic>[
          for (final g in geofences)
            <String, dynamic>{
              'GeofenceId': g.geofenceId,
              'Geometry': g.geometry.toJson(),
              if (g.properties.isNotEmpty) 'GeofenceProperties': g.properties,
            },
        ],
      },
    );
    return BatchResult(
      total: geofences.length,
      errors: Json.objects(json, 'Errors')
          .map((e) => BatchItemError.fromJson(e, 'GeofenceId'))
          .toList(growable: false),
    );
  }

  /// Lee una geovalla.
  Future<Geofence> getGeofence({
    required String collectionName,
    required String geofenceId,
  }) async {
    final json = await _transport.sendJson(
      operation: 'GetGeofence',
      service: _data,
      method: 'GET',
      path:
          '/geofencing/v0/collections/${_seg(collectionName)}'
          '/geofences/${_seg(geofenceId)}',
    );
    return Geofence.fromJson(json);
  }

  /// Lista las geovallas de una colección.
  Future<GeofencePage<Geofence>> listGeofences({
    required String collectionName,
    int? maxResults,
    String? nextToken,
  }) async {
    final json = await _transport.sendJson(
      operation: 'ListGeofences',
      service: _data,
      method: 'POST',
      path: '/geofencing/v0/collections/${_seg(collectionName)}/list-geofences',
      body: <String, dynamic>{
        'MaxResults': ?maxResults,
        'NextToken': ?nextToken,
      },
    );
    return GeofencePage<Geofence>(
      items: Json.objects(
        json,
        'Entries',
      ).map(Geofence.fromJson).toList(growable: false),
      nextToken: Json.string(json, 'NextToken'),
    );
  }

  /// Borra varias geovallas.
  Future<BatchResult> batchDeleteGeofence({
    required String collectionName,
    required List<String> geofenceIds,
  }) async {
    if (geofenceIds.isEmpty) {
      throw ArgumentError.value(
        geofenceIds,
        'geofenceIds',
        'no puede estar vacío',
      );
    }
    final json = await _transport.sendJson(
      operation: 'BatchDeleteGeofence',
      service: _data,
      method: 'POST',
      path:
          '/geofencing/v0/collections/${_seg(collectionName)}'
          '/delete-geofences',
      body: <String, dynamic>{'GeofenceIds': geofenceIds},
    );
    return BatchResult(
      total: geofenceIds.length,
      errors: Json.objects(json, 'Errors')
          .map((e) => BatchItemError.fromJson(e, 'GeofenceId'))
          .toList(growable: false),
    );
  }

  // ─── Evaluación ───────────────────────────────────────────────────────

  /// Evalúa posiciones contra las geovallas de una colección.
  ///
  /// ## La respuesta viene vacía a propósito
  ///
  /// **Esta operación no dice si el dispositivo entró o salió.** La evaluación
  /// es asíncrona: el servicio publica un evento `ENTER` o `EXIT` en **Amazon
  /// EventBridge**, y ahí es donde hay que escucharlo — con una Lambda, una
  /// cola SQS o una notificación SNS.
  ///
  /// Quien espere una respuesta síncrona se encuentra un `Errors` vacío y
  /// concluye que no pasó nada. Por eso [BatchResult.errors] es lo único que
  /// vuelve, y hay que mirarlo: es 200 aunque falle la mitad.
  ///
  /// Para saber ahora mismo si un punto está dentro sin esperar a EventBridge,
  /// está `GeofenceGeometry.contains`, que se calcula en local y no cuesta
  /// nada.
  ///
  /// ## Detalles que importan
  ///
  /// - Máximo **10 posiciones** por llamada.
  /// - **No hace falta que exista un rastreador**: el `deviceId` es una cadena
  ///   libre.
  /// - La última geovalla en la que se vio un dispositivo se recuerda **30
  ///   días**. Pasado ese plazo, la primera posición vuelve a producir un
  ///   `ENTER`.
  /// - **Se ignora la precisión**: la evaluación usa la posición tal cual.
  Future<BatchResult> batchEvaluateGeofences({
    required String collectionName,
    required List<DevicePositionUpdate> positions,
  }) async {
    if (positions.isEmpty) {
      throw ArgumentError.value(positions, 'positions', 'no puede estar vacío');
    }
    if (positions.length > maxPositionsPerBatch) {
      throw ArgumentError.value(
        positions.length,
        'positions',
        'el máximo son $maxPositionsPerBatch por llamada; trocea la lista',
      );
    }

    final json = await _transport.sendJson(
      operation: 'BatchEvaluateGeofences',
      service: _data,
      method: 'POST',
      path: '/geofencing/v0/collections/${_seg(collectionName)}/positions',
      body: <String, dynamic>{
        'DevicePositionUpdates': <dynamic>[
          for (final p in positions) p.toJson(),
        ],
      },
    );
    return BatchResult(
      total: positions.length,
      errors: Json.objects(json, 'Errors')
          .map((e) => BatchItemError.fromJson(e, 'DeviceId'))
          .toList(growable: false),
    );
  }

  /// **Predice** qué geovallas va a cruzar un dispositivo.
  ///
  /// Esta es la operación que no tiene equivalente en ningún otro sitio, y la
  /// razón principal para usar esta familia:
  ///
  /// ```dart
  /// final aviso = await maps.geofencing.forecastGeofenceEvents(
  ///   collectionName: 'zonas-permitidas',
  ///   position: ultimaPosicion,
  ///   speedKmh: 62,
  ///   timeHorizon: const Duration(minutes: 10),
  /// );
  ///
  /// for (final evento in aviso.breaches) {
  ///   alertar(
  ///     'El vehículo ${evento.eventType.name} la zona ${evento.geofenceId} '
  ///     'en ${evento.timeUntilBreach!.inMinutes} min',
  ///   );
  /// }
  /// ```
  ///
  /// **Avisar antes es una operación distinta de avisar después.** Con un
  /// vehículo robado, seis minutos de margen son la diferencia entre
  /// interceptarlo y perseguirlo.
  ///
  /// ## Dos cosas que hay que saber
  ///
  /// **Sin [speedKmh] o sin [timeHorizon] no predice nada**: se convierte en
  /// una simple comprobación de contención y devuelve solo eventos `IDLE` de
  /// las geovallas en las que ya está. Es útil, pero no es lo que se pedía.
  ///
  /// **No tiene en cuenta el rumbo.** La documentación de AWS lo dice
  /// explícitamente: es conservador e incluye los cruces posibles en
  /// *cualquier* dirección. Con un vehículo parado en un cruce, eso son varias
  /// zonas a la vez.
  ///
  /// ## La unidad
  ///
  /// Esta familia sí tiene `DistanceUnit` —es de la generación anterior—.
  /// Aquí se pide siempre en kilómetros y **se convierte a metros**, para que
  /// `nearestDistance` llegue en la misma unidad que todo lo demás del
  /// paquete.
  Future<ForecastGeofenceEventsResponse> forecastGeofenceEvents({
    required String collectionName,
    required LatLng position,
    double? speedKmh,
    Duration? timeHorizon,
    int? maxResults,
    String? nextToken,
  }) async {
    final json = await _transport.sendJson(
      operation: 'ForecastGeofenceEvents',
      service: _data,
      method: 'POST',
      path:
          '/geofencing/v0/collections/${_seg(collectionName)}'
          '/forecast-geofence-events',
      body: <String, dynamic>{
        'DeviceState': <String, dynamic>{
          'Position': position.toLonLat(),
          'Speed': ?speedKmh,
        },
        if (timeHorizon != null)
          'TimeHorizonMinutes': timeHorizon.inSeconds / 60.0,
        // Fijos a propósito: se piden en kilómetros y se convierten a metros
        // al leer, para que el resto del paquete siga en unidades del SI.
        'DistanceUnit': 'Kilometers',
        'SpeedUnit': 'KilometersPerHour',
        'MaxResults': ?maxResults,
        'NextToken': ?nextToken,
      },
    );

    final respuesta = ForecastGeofenceEventsResponse.fromJson(json);
    return ForecastGeofenceEventsResponse(
      events: <ForecastedGeofenceEvent>[
        for (final e in respuesta.events)
          ForecastedGeofenceEvent(
            eventId: e.eventId,
            geofenceId: e.geofenceId,
            eventType: e.eventType,
            isDeviceInGeofence: e.isDeviceInGeofence,
            // De kilómetros a metros.
            nearestDistance: e.nearestDistance * 1000,
            forecastedBreachTime: e.forecastedBreachTime,
            geofenceProperties: e.geofenceProperties,
          ),
      ],
      nextToken: respuesta.nextToken,
    );
  }

  // ─── Colecciones · plano de control ───────────────────────────────────

  /// Crea una colección de geovallas.
  ///
  /// Va a **otro host** (`cp.geofencing.geo.…`) y suele hacerse una vez, desde
  /// una herramienta de administración o desde la consola. Una app móvil casi
  /// nunca debería tener permiso para esto.
  ///
  /// [kmsKeyId] cifra las geovallas con una clave propia. Es lo que pide un
  /// cliente que considere las zonas información sensible — y una zona
  /// *dibuja* dónde vive alguien, así que a veces lo es.
  Future<GeofenceCollection> createCollection({
    required String collectionName,
    String? description,
    String? kmsKeyId,
    Map<String, String> tags = const <String, String>{},
  }) async {
    final json = await _transport.sendJson(
      operation: 'CreateGeofenceCollection',
      service: _control,
      method: 'POST',
      path: '/geofencing/v0/collections',
      body: <String, dynamic>{
        'CollectionName': collectionName,
        'Description': ?description,
        'KmsKeyId': ?kmsKeyId,
        if (tags.isNotEmpty) 'Tags': tags,
      },
    );
    return GeofenceCollection.fromJson(json);
  }

  /// Lee los datos de una colección, incluido cuántas geovallas tiene.
  Future<GeofenceCollection> describeCollection(String collectionName) async {
    final json = await _transport.sendJson(
      operation: 'DescribeGeofenceCollection',
      service: _control,
      method: 'GET',
      path: '/geofencing/v0/collections/${_seg(collectionName)}',
    );
    return GeofenceCollection.fromJson(json);
  }

  /// Cambia la descripción de una colección.
  Future<GeofenceCollection> updateCollection({
    required String collectionName,
    String? description,
  }) async {
    final json = await _transport.sendJson(
      operation: 'UpdateGeofenceCollection',
      service: _control,
      method: 'PATCH',
      path: '/geofencing/v0/collections/${_seg(collectionName)}',
      body: <String, dynamic>{'Description': ?description},
    );
    return GeofenceCollection.fromJson(json);
  }

  /// Borra una colección **y todas sus geovallas**.
  ///
  /// No se puede deshacer, y los rastreadores enlazados dejan de disparar
  /// eventos sin dar ningún error: simplemente no salta nada.
  Future<void> deleteCollection(String collectionName) async {
    await _transport.sendJson(
      operation: 'DeleteGeofenceCollection',
      service: _control,
      method: 'DELETE',
      path: '/geofencing/v0/collections/${_seg(collectionName)}',
    );
  }

  /// Lista las colecciones de la cuenta.
  Future<GeofencePage<GeofenceCollection>> listCollections({
    int? maxResults,
    String? nextToken,
  }) async {
    final json = await _transport.sendJson(
      operation: 'ListGeofenceCollections',
      service: _control,
      method: 'POST',
      path: '/geofencing/v0/list-collections',
      body: <String, dynamic>{
        'MaxResults': ?maxResults,
        'NextToken': ?nextToken,
      },
    );
    return GeofencePage<GeofenceCollection>(
      items: Json.objects(
        json,
        'Entries',
      ).map(GeofenceCollection.fromJson).toList(growable: false),
      nextToken: Json.string(json, 'NextToken'),
    );
  }

  // ─── Auxiliares ───────────────────────────────────────────────────────

  static void _checkProperties(Map<String, String> properties) {
    if (properties.length > 3) {
      throw ArgumentError.value(
        properties.length,
        'properties',
        'el máximo son 3 propiedades por geovalla',
      );
    }
    for (final entry in properties.entries) {
      if (entry.key.length > 20) {
        throw ArgumentError.value(
          entry.key,
          'properties',
          'las claves admiten 20 caracteres',
        );
      }
      if (entry.value.length > 40) {
        throw ArgumentError.value(
          entry.value,
          'properties',
          'los valores admiten 40 caracteres',
        );
      }
    }
  }

  static String _seg(String value) => Uri.encodeComponent(value);
}
