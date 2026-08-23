// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:compass_maps/src/client/transport.dart';
import 'package:compass_maps/src/core/enums.dart';
import 'package:compass_maps/src/core/json.dart';
import 'package:compass_maps/src/core/lat_lng.dart';
import 'package:compass_maps/src/geofencing/models.dart'
    show BatchItemError, BatchResult, DevicePositionUpdate;
import 'package:compass_maps/src/tracking/models.dart';
import 'package:meta/meta.dart';

/// Las **15 operaciones** de rastreo de dispositivos de Amazon Location.
///
/// | Método | Endpoint | Para qué |
/// |---|---|---|
/// | [batchUpdateDevicePosition] | `POST …/positions` | subir posiciones |
/// | [getDevicePosition] | `GET …/devices/{d}/positions/latest` | la última |
/// | [batchGetDevicePosition] | `POST …/get-positions` | las últimas de varios |
/// | [getDevicePositionHistory] | `POST …/devices/{d}/list-positions` | el histórico |
/// | [listDevicePositions] | `POST …/list-positions` | **quién hay en esta zona** |
/// | [batchDeleteDevicePositionHistory] | `POST …/delete-positions` | borrar histórico |
/// | [verifyDevicePosition] | `POST …/positions/verify` | **¿me están mintiendo?** |
/// | [createTracker] · [describeTracker] | control | gestionar |
/// | [updateTracker] · [deleteTracker] | control | gestionar |
/// | [listTrackers] | control | listarlos |
/// | [associateConsumer] | control | **enlazar geovallas** |
/// | [disassociateConsumer] · [listConsumers] | control | ver y deshacer |
///
/// ## ⚠️ Antes de usarlo: ¿de verdad lo necesitas?
///
/// Si ya guardas el histórico de tus dispositivos en tu propia base de datos
/// —lo normal cuando los localizadores reportan a un servidor propio—, esto es
/// **infraestructura duplicada** y una segunda factura por el mismo dato.
///
/// Las tres cosas que sí justifican usarlo:
///
/// 1. **[associateConsumer]**: enlazar el rastreador con una colección de
///    geovallas hace que AWS evalúe **automáticamente** cada posición y
///    dispare eventos en EventBridge. Sin esto hay que llamar a
///    `batchEvaluateGeofences` a mano por cada posición.
/// 2. **[verifyDevicePosition]**: detecta ubicaciones falseadas. No hay forma
///    de hacer esto por tu cuenta.
/// 3. **[listDevicePositions] con `filterGeometry`**: «quién hay dentro de
///    este polígono ahora mismo», resuelto por el servicio.
///
/// ## Tres cosas que no son como en v2
///
/// 1. **Hay que crear un rastreador.** Con [createTracker] o en la consola.
/// 2. **No admite clave de API.** Hacen falta credenciales SigV4.
/// 3. **El histórico se borra a los 30 días.** No es configurable. Si necesitas
///    guardarlo más, hay que copiarlo a tu propio almacenamiento.
class TrackingClient {
  /// Construye el cliente. Uso interno: llega ya montado en `CompassMaps`.
  @internal
  TrackingClient({required AlsTransport transport}) : _transport = transport;

  final AlsTransport _transport;

  static const AlsService _data = AlsService.tracking;
  static const AlsService _control = AlsService.trackingControl;

  /// Máximo de dispositivos por llamada por lotes.
  static const int maxDevicesPerBatch = 10;

  /// Cuántos días conserva AWS el histórico. **No es configurable.**
  static const int historyRetentionDays = 30;

  // ─── Posiciones ───────────────────────────────────────────────────────

  /// Sube posiciones de hasta 10 dispositivos.
  ///
  /// ```dart
  /// await maps.tracking.batchUpdateDevicePosition(
  ///   trackerName: 'flota',
  ///   updates: [
  ///     for (final p in lote)
  ///       DevicePositionUpdate(
  ///         deviceId: p.imei,
  ///         position: LatLng(p.lat, p.lng),
  ///         sampleTime: p.horaDelGps,          // la del GPS, no la de ahora
  ///         horizontalAccuracyMeters: p.hdop * 5,
  ///       ),
  ///   ],
  /// );
  /// ```
  ///
  /// ## Lo que el rastreador puede descartar
  ///
  /// **No todo lo que se sube se guarda.** El `positionFiltering` del
  /// rastreador decide, y con el valor por defecto
  /// —[PositionFiltering.timeBased]— solo se guarda **una posición cada 30
  /// segundos por dispositivo**. Un
  /// localizador que reporta cada cinco segundos verá cinco de cada seis
  /// posiciones descartadas sin ningún error.
  ///
  /// Para rastreo de vehículos, [PositionFiltering.distanceBased] es casi
  /// siempre lo correcto.
  ///
  /// ## El troceado
  ///
  /// El máximo son 10 por llamada. Este método **trocea solo** y devuelve el
  /// total agregado, en vez de obligar a quien llama a partir la lista.
  Future<BatchResult> batchUpdateDevicePosition({
    required String trackerName,
    required List<DevicePositionUpdate> updates,
  }) async {
    if (updates.isEmpty) {
      throw ArgumentError.value(updates, 'updates', 'no puede estar vacío');
    }

    final errores = <BatchItemError>[];
    for (var i = 0; i < updates.length; i += maxDevicesPerBatch) {
      final trozo = updates.skip(i).take(maxDevicesPerBatch).toList();
      final json = await _transport.sendJson(
        operation: 'BatchUpdateDevicePosition',
        service: _data,
        method: 'POST',
        path: '/tracking/v0/trackers/${_seg(trackerName)}/positions',
        body: <String, dynamic>{
          'Updates': <dynamic>[for (final u in trozo) u.toJson()],
        },
      );
      errores.addAll(
        Json.objects(
          json,
          'Errors',
        ).map((e) => BatchItemError.fromJson(e, 'DeviceId')),
      );
    }
    return BatchResult(total: updates.length, errors: errores);
  }

  /// La última posición conocida de un dispositivo.
  ///
  /// Comprobar [DevicePosition.isFresh] antes de tratarla como «dónde está
  /// ahora» no es opcional: un vehículo cuya última posición es de hace media
  /// hora **no está** ahí.
  Future<DevicePosition> getDevicePosition({
    required String trackerName,
    required String deviceId,
  }) async {
    final json = await _transport.sendJson(
      operation: 'GetDevicePosition',
      service: _data,
      method: 'GET',
      path:
          '/tracking/v0/trackers/${_seg(trackerName)}'
          '/devices/${_seg(deviceId)}/positions/latest',
    );
    return DevicePosition.fromJson(json);
  }

  /// Las últimas posiciones de varios dispositivos, hasta 10.
  ///
  /// Devuelve las posiciones **y los errores por dispositivo**: uno que no
  /// exista no hace fallar la llamada entera, aparece en [BatchResult.errors].
  Future<({List<DevicePosition> positions, BatchResult result})>
  batchGetDevicePosition({
    required String trackerName,
    required List<String> deviceIds,
  }) async {
    if (deviceIds.isEmpty) {
      throw ArgumentError.value(deviceIds, 'deviceIds', 'no puede estar vacío');
    }
    if (deviceIds.length > maxDevicesPerBatch) {
      throw ArgumentError.value(
        deviceIds.length,
        'deviceIds',
        'el máximo son $maxDevicesPerBatch por llamada',
      );
    }

    final json = await _transport.sendJson(
      operation: 'BatchGetDevicePosition',
      service: _data,
      method: 'POST',
      path: '/tracking/v0/trackers/${_seg(trackerName)}/get-positions',
      body: <String, dynamic>{'DeviceIds': deviceIds},
    );

    return (
      positions: Json.objects(
        json,
        'DevicePositions',
      ).map(DevicePosition.fromJson).toList(growable: false),
      result: BatchResult(
        total: deviceIds.length,
        errors: Json.objects(json, 'Errors')
            .map((e) => BatchItemError.fromJson(e, 'DeviceId'))
            .toList(growable: false),
      ),
    );
  }

  /// El histórico de posiciones de un dispositivo.
  ///
  /// Sin fechas, el servicio devuelve **las últimas 24 horas**.
  ///
  /// **AWS borra el histórico a los 30 días** y no es configurable: pedir algo
  /// más antiguo devuelve una lista vacía, no un error.
  ///
  /// El resultado entra directamente en `snapToRoads` para limpiarlo:
  ///
  /// ```dart
  /// final historico = await maps.tracking.getDevicePositionHistory(
  ///   trackerName: 'flota',
  ///   deviceId: imei,
  ///   from: DateTime.now().subtract(const Duration(hours: 8)),
  /// );
  ///
  /// final limpio = await maps.routes.snapToRoads(
  ///   tracePoints: [
  ///     for (final p in historico.items)
  ///       TracePoint(position: p.position, timestamp: p.sampleTime),
  ///   ],
  /// );
  /// ```
  Future<TrackingPage<DevicePosition>> getDevicePositionHistory({
    required String trackerName,
    required String deviceId,
    DateTime? from,
    DateTime? to,
    int? maxResults,
    String? nextToken,
  }) async {
    if (from != null && to != null && !from.isBefore(to)) {
      throw ArgumentError('`from` tiene que ser anterior a `to`.');
    }
    if (maxResults != null && (maxResults < 1 || maxResults > 100)) {
      throw ArgumentError.value(
        maxResults,
        'maxResults',
        'admite entre 1 y 100',
      );
    }

    final json = await _transport.sendJson(
      operation: 'GetDevicePositionHistory',
      service: _data,
      method: 'POST',
      path:
          '/tracking/v0/trackers/${_seg(trackerName)}'
          '/devices/${_seg(deviceId)}/list-positions',
      body: <String, dynamic>{
        if (from != null) 'StartTimeInclusive': from.toUtc().toIso8601String(),
        if (to != null) 'EndTimeExclusive': to.toUtc().toIso8601String(),
        'MaxResults': ?maxResults,
        'NextToken': ?nextToken,
      },
    );

    return TrackingPage<DevicePosition>(
      items: Json.objects(
        json,
        'DevicePositions',
      ).map(DevicePosition.fromJson).toList(growable: false),
      nextToken: Json.string(json, 'NextToken'),
    );
  }

  /// Las últimas posiciones de **todos** los dispositivos del rastreador.
  ///
  /// Con [filterGeometry] responde a «**quién hay dentro de este polígono
  /// ahora mismo**», resuelto por el servicio en vez de bajándose la flota
  /// entera y filtrando en el móvil.
  ///
  /// ```dart
  /// final dentro = await maps.tracking.listDevicePositions(
  ///   trackerName: 'flota',
  ///   filterGeometry: zonaDeInteres,   // un polígono
  /// );
  /// ```
  ///
  /// El filtro admite **un solo polígono** y hasta 1 000 vértices.
  Future<TrackingPage<DevicePosition>> listDevicePositions({
    required String trackerName,
    List<LatLng>? filterGeometry,
    int? maxResults,
    String? nextToken,
  }) async {
    if (filterGeometry != null && filterGeometry.length < 3) {
      throw ArgumentError.value(
        filterGeometry,
        'filterGeometry',
        'un polígono necesita al menos 3 puntos',
      );
    }

    final json = await _transport.sendJson(
      operation: 'ListDevicePositions',
      service: _data,
      method: 'POST',
      path: '/tracking/v0/trackers/${_seg(trackerName)}/list-positions',
      body: <String, dynamic>{
        'MaxResults': ?maxResults,
        'NextToken': ?nextToken,
        if (filterGeometry != null)
          'FilterGeometry': <String, dynamic>{
            'Polygon': <dynamic>[
              <dynamic>[
                for (final p in filterGeometry) p.toLonLat(),
                // El anillo tiene que ir cerrado.
                if (filterGeometry.first != filterGeometry.last)
                  filterGeometry.first.toLonLat(),
              ],
            ],
          },
      },
    );

    return TrackingPage<DevicePosition>(
      items: Json.objects(
        json,
        'Entries',
      ).map(DevicePosition.fromJson).toList(growable: false),
      nextToken: Json.string(json, 'NextToken'),
    );
  }

  /// Borra el histórico de varios dispositivos.
  ///
  /// **No se puede deshacer.** Sirve para atender una solicitud de borrado de
  /// datos personales: el recorrido de un vehículo *es* dato personal de quien
  /// lo conduce.
  Future<BatchResult> batchDeleteDevicePositionHistory({
    required String trackerName,
    required List<String> deviceIds,
  }) async {
    if (deviceIds.isEmpty) {
      throw ArgumentError.value(deviceIds, 'deviceIds', 'no puede estar vacío');
    }
    final json = await _transport.sendJson(
      operation: 'BatchDeleteDevicePositionHistory',
      service: _data,
      method: 'POST',
      path: '/tracking/v0/trackers/${_seg(trackerName)}/delete-positions',
      body: <String, dynamic>{'DeviceIds': deviceIds},
    );
    return BatchResult(
      total: deviceIds.length,
      errors: Json.objects(json, 'Errors')
          .map((e) => BatchItemError.fromJson(e, 'DeviceId'))
          .toList(growable: false),
    );
  }

  /// Comprueba si una posición declarada es de fiar.
  ///
  /// Contrasta lo que dice el dispositivo con lo que el servicio deduce de su
  /// dirección IP y de los puntos Wi-Fi que ve. Detecta dos cosas:
  ///
  /// - **Que la posición llegó por un proxy o una VPN**, que es la señal más
  ///   fuerte de ubicación falseada.
  /// - **Cuánto se separa** de la posición deducida.
  ///
  /// ```dart
  /// final v = await maps.tracking.verifyDevicePosition(
  ///   trackerName: 'flota',
  ///   deviceId: imei,
  ///   position: posicionDeclarada,
  ///   sampleTime: hora,
  ///   ipv4Address: ipDelDispositivo,
  ///   wifiAccessPoints: puntosVistos,
  /// );
  ///
  /// if (v.isSuspicious()) revisar(imei);
  /// ```
  ///
  /// **Sin [ipv4Address] ni [wifiAccessPoints] no puede deducir gran cosa**:
  /// son las dos señales independientes del GPS, y sin ellas solo queda lo que
  /// el propio dispositivo declara.
  ///
  /// La desviación llega en la unidad pedida —kilómetros por defecto—; aquí se
  /// convierte a **metros**, como el resto del paquete.
  Future<PositionVerification> verifyDevicePosition({
    required String trackerName,
    required String deviceId,
    required LatLng position,
    required DateTime sampleTime,
    double? horizontalAccuracyMeters,
    String? ipv4Address,
    List<WiFiAccessPoint> wifiAccessPoints = const <WiFiAccessPoint>[],
  }) async {
    final json = await _transport.sendJson(
      operation: 'VerifyDevicePosition',
      service: _data,
      method: 'POST',
      path: '/tracking/v0/trackers/${_seg(trackerName)}/positions/verify',
      body: <String, dynamic>{
        'DeviceState': <String, dynamic>{
          'DeviceId': deviceId,
          'Position': position.toLonLat(),
          'SampleTime': sampleTime.toUtc().toIso8601String(),
          if (horizontalAccuracyMeters != null)
            'Accuracy': <String, dynamic>{
              'Horizontal': horizontalAccuracyMeters,
            },
          'Ipv4Address': ?ipv4Address,
          if (wifiAccessPoints.isNotEmpty)
            'WiFiAccessPoints': <dynamic>[
              for (final ap in wifiAccessPoints) ap.toJson(),
            ],
        },
        'DistanceUnit': 'Kilometers',
      },
    );

    final v = PositionVerification.fromJson(json);
    return PositionVerification(
      deviceId: v.deviceId,
      proxyDetected: v.proxyDetected,
      inferredPosition: v.inferredPosition,
      // De kilómetros a metros.
      deviationMeters: v.deviationMeters == null
          ? null
          : v.deviationMeters! * 1000,
      inferredAccuracyMeters: v.inferredAccuracyMeters,
      sampleTime: v.sampleTime,
      receivedTime: v.receivedTime,
    );
  }

  // ─── Rastreadores · plano de control ──────────────────────────────────

  /// Crea un rastreador.
  ///
  /// **[positionFiltering] es la decisión que hay que pensar.** El valor por
  /// defecto del servicio guarda una posición cada 30 segundos aunque el
  /// vehículo esté parado; [PositionFiltering.distanceBased] solo guarda si se
  /// movió más de 30 metros, y para rastreo de vehículos suele ser lo correcto
  /// — el histórico de un día pasa de miles de puntos a cientos sin perder
  /// nada del recorrido.
  Future<Tracker> createTracker({
    required String trackerName,
    String? description,
    PositionFiltering positionFiltering = PositionFiltering.distanceBased,
    bool? eventBridgeEnabled,
    String? kmsKeyId,
    Map<String, String> tags = const <String, String>{},
  }) async {
    final json = await _transport.sendJson(
      operation: 'CreateTracker',
      service: _control,
      method: 'POST',
      path: '/tracking/v0/trackers',
      body: <String, dynamic>{
        'TrackerName': trackerName,
        'PositionFiltering': positionFiltering.wireName,
        'Description': ?description,
        'EventBridgeEnabled': ?eventBridgeEnabled,
        'KmsKeyId': ?kmsKeyId,
        if (tags.isNotEmpty) 'Tags': tags,
      },
    );
    return Tracker.fromJson(json);
  }

  /// Lee los datos de un rastreador.
  Future<Tracker> describeTracker(String trackerName) async {
    final json = await _transport.sendJson(
      operation: 'DescribeTracker',
      service: _control,
      method: 'GET',
      path: '/tracking/v0/trackers/${_seg(trackerName)}',
    );
    return Tracker.fromJson(json);
  }

  /// Cambia la configuración de un rastreador.
  ///
  /// Cambiar [positionFiltering] **no reprocesa el histórico**: se aplica solo
  /// a lo que llegue a partir de ahora.
  Future<Tracker> updateTracker({
    required String trackerName,
    String? description,
    PositionFiltering? positionFiltering,
    bool? eventBridgeEnabled,
  }) async {
    final json = await _transport.sendJson(
      operation: 'UpdateTracker',
      service: _control,
      method: 'PATCH',
      path: '/tracking/v0/trackers/${_seg(trackerName)}',
      body: <String, dynamic>{
        'Description': ?description,
        if (positionFiltering != null)
          'PositionFiltering': positionFiltering.wireName,
        'EventBridgeEnabled': ?eventBridgeEnabled,
      },
    );
    return Tracker.fromJson(json);
  }

  /// Borra un rastreador **y todo su histórico**. No se puede deshacer.
  Future<void> deleteTracker(String trackerName) async {
    await _transport.sendJson(
      operation: 'DeleteTracker',
      service: _control,
      method: 'DELETE',
      path: '/tracking/v0/trackers/${_seg(trackerName)}',
    );
  }

  /// Lista los rastreadores de la cuenta.
  Future<TrackingPage<Tracker>> listTrackers({
    int? maxResults,
    String? nextToken,
  }) async {
    final json = await _transport.sendJson(
      operation: 'ListTrackers',
      service: _control,
      method: 'POST',
      path: '/tracking/v0/list-trackers',
      body: <String, dynamic>{
        'MaxResults': ?maxResults,
        'NextToken': ?nextToken,
      },
    );
    return TrackingPage<Tracker>(
      items: Json.objects(
        json,
        'Entries',
      ).map(Tracker.fromJson).toList(growable: false),
      nextToken: Json.string(json, 'NextToken'),
    );
  }

  // ─── Consumidores: el enlace con las geovallas ────────────────────────

  /// Enlaza el rastreador con una colección de geovallas.
  ///
  /// **Esto es lo que hace que todo lo demás funcione solo.** Una vez
  /// enlazados, cada posición que entra por [batchUpdateDevicePosition] se
  /// evalúa **automáticamente** contra las geovallas de esa colección y
  /// dispara eventos `ENTER` y `EXIT` en Amazon EventBridge.
  ///
  /// Sin el enlace hay que llamar a `GeofencingClient.batchEvaluateGeofences`
  /// a mano por cada lote de posiciones — el doble de peticiones y el doble de
  /// factura para el mismo resultado.
  ///
  /// [collectionArn] es el ARN completo, no el nombre. Sale de
  /// `GeofenceCollection.collectionArn`.
  Future<void> associateConsumer({
    required String trackerName,
    required String collectionArn,
  }) async {
    await _transport.sendJson(
      operation: 'AssociateTrackerConsumer',
      service: _control,
      method: 'POST',
      path: '/tracking/v0/trackers/${_seg(trackerName)}/consumers',
      body: <String, dynamic>{'ConsumerArn': collectionArn},
    );
  }

  /// Deshace el enlace.
  ///
  /// A partir de ese momento las posiciones dejan de evaluarse **sin dar
  /// ningún error**: simplemente no salta nada.
  Future<void> disassociateConsumer({
    required String trackerName,
    required String collectionArn,
  }) async {
    await _transport.sendJson(
      operation: 'DisassociateTrackerConsumer',
      service: _control,
      method: 'DELETE',
      path:
          '/tracking/v0/trackers/${_seg(trackerName)}'
          '/consumers/${_seg(collectionArn)}',
    );
  }

  /// Las colecciones de geovallas enlazadas con un rastreador.
  ///
  /// Es lo primero que hay que mirar cuando «las geovallas no disparan»: casi
  /// siempre es que el enlace no está.
  Future<TrackingPage<String>> listConsumers({
    required String trackerName,
    int? maxResults,
    String? nextToken,
  }) async {
    final json = await _transport.sendJson(
      operation: 'ListTrackerConsumers',
      service: _control,
      method: 'POST',
      path: '/tracking/v0/trackers/${_seg(trackerName)}/list-consumers',
      body: <String, dynamic>{
        'MaxResults': ?maxResults,
        'NextToken': ?nextToken,
      },
    );
    return TrackingPage<String>(
      items: Json.strings(json, 'ConsumerArns'),
      nextToken: Json.string(json, 'NextToken'),
    );
  }

  static String _seg(String value) => Uri.encodeComponent(value);
}
