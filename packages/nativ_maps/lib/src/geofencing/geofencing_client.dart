// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/client/transport.dart';
import 'package:nativ_maps/src/core/enums.dart';
import 'package:nativ_maps/src/core/json.dart';
import 'package:nativ_maps/src/core/lat_lng.dart';
import 'package:nativ_maps/src/geofencing/models.dart';

/// The **12 Amazon Location geofencing operations**.
///
/// | Method | Endpoint | What for |
/// |---|---|---|
/// | [putGeofence] | `PUT /collections/{c}/geofences/{g}` | create or change a zone |
/// | [batchPutGeofence] | `POST …/put-geofences` | up to 10 at once |
/// | [getGeofence] | `GET …/geofences/{g}` | read one |
/// | [listGeofences] | `POST …/list-geofences` | list them |
/// | [batchDeleteGeofence] | `POST …/delete-geofences` | delete several |
/// | [batchEvaluateGeofences] | `POST …/positions` | **entered or exited?** |
/// | [forecastGeofenceEvents] | `POST …/forecast-geofence-events` | **is it about to enter?** |
/// | [createCollection] | `POST /collections` | create the collection |
/// | [describeCollection] | `GET /collections/{c}` | read it |
/// | [updateCollection] | `PATCH /collections/{c}` | change it |
/// | [deleteCollection] | `DELETE /collections/{c}` | delete it |
/// | [listCollections] | `POST /list-collections` | list them |
///
/// ## ⚠️ Three things that aren't like in Places, Routes and Maps
///
/// This family belongs to the **previous generation**, and it shows in three
/// places:
///
/// 1. **You have to create a resource.** A geofence collection is created
///    with [createCollection] or in the console. It's not like v2, where you
///    create nothing.
/// 2. **It doesn't accept an API key.** Amazon Location keys only cover
///    Places, Routes and Maps. Here you need SigV4 credentials — a proxy or
///    `nativ_maps_sigv4`. Trying it with a key is cut off before sending, with
///    a message that says so.
/// 3. **The control plane goes to another host**, with the `cp.` prefix. It's
///    resolved automatically, but it explains why there are two values in
///    `AlsService`.
///
/// ## What really justifies using it
///
/// [forecastGeofenceEvents]. It doesn't tell you where the vehicle is: it
/// tells you **where it's going to be**. Warning six minutes before it leaves
/// the allowed zone is a different operation from warning once it has left.
class GeofencingClient {
  /// Builds the client. Internal use: it comes already set up in `NativMaps`.
  @internal
  GeofencingClient({required AlsTransport transport}) : _transport = transport;

  final AlsTransport _transport;

  static const AlsService _data = AlsService.geofencing;
  static const AlsService _control = AlsService.geofencingControl;

  /// Maximum positions per call to [batchEvaluateGeofences].
  static const int maxPositionsPerBatch = 10;

  /// Maximum geofences per call to [batchPutGeofence].
  static const int maxGeofencesPerBatch = 10;

  // ─── Geofences ────────────────────────────────────────────────────────

  /// Creates or replaces a geofence.
  ///
  /// ```dart
  /// await maps.geofencing.putGeofence(
  ///   collectionName: 'allowed-zones',
  ///   geofenceId: 'north-warehouse',
  ///   geometry: GeofenceGeometry.circle(
  ///     center: LatLng(-0.1807, -78.4678),
  ///     radiusMeters: 500,
  ///   ),
  ///   properties: {'client': 'ACME', 'type': 'warehouse'},
  /// );
  /// ```
  ///
  /// [properties] accepts **three** entries at most, with keys of up to 20
  /// characters and values of up to 40. They travel **inside every event** the
  /// geofence fires, so that's where you put what you'll need on receiving it
  /// without having to look it up.
  ///
  /// A freshly created geofence takes a moment to become `ACTIVE`, and until
  /// then it **fires nothing**. Evaluating against one in `PENDING` doesn't
  /// fail: it simply doesn't trigger, which is worse.
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

  /// Creates or replaces up to 10 geofences at once.
  ///
  /// **It doesn't fail as a whole**: it processes what it can and returns the
  /// failures one by one. You have to check `errors`, because the response is
  /// 200 even if half of them fail.
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

  /// Reads a geofence.
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

  /// Lists the geofences in a collection.
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

  /// Deletes several geofences.
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

  // ─── Evaluation ───────────────────────────────────────────────────────

  /// Evaluates positions against the geofences in a collection.
  ///
  /// ## The response comes back empty on purpose
  ///
  /// **This operation doesn't tell you whether the device entered or
  /// exited.** Evaluation is asynchronous: the service publishes an `ENTER` or
  /// `EXIT` event to **Amazon EventBridge**, and that's where you have to
  /// listen for it — with a Lambda, an SQS queue or an SNS notification.
  ///
  /// Anyone expecting a synchronous answer finds an empty `Errors` and
  /// concludes that nothing happened. That's why [BatchResult.errors] is the
  /// only thing that comes back, and you have to check it: it's 200 even if
  /// half of them fail.
  ///
  /// To know right now whether a point is inside without waiting for
  /// EventBridge, there's `GeofenceGeometry.contains`, which is computed
  /// locally and costs nothing.
  ///
  /// ## Details that matter
  ///
  /// - At most **10 positions** per call.
  /// - **A tracker doesn't need to exist**: the `deviceId` is a free-form
  ///   string.
  /// - The last geofence a device was seen in is remembered for **30 days**.
  ///   After that, the first position produces an `ENTER` again.
  /// - **Accuracy is ignored**: the evaluation uses the position as is.
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

  /// **Predicts** which geofences a device is going to cross.
  ///
  /// This is the operation that has no equivalent anywhere else, and the main
  /// reason to use this family:
  ///
  /// ```dart
  /// final forecast = await maps.geofencing.forecastGeofenceEvents(
  ///   collectionName: 'allowed-zones',
  ///   position: lastPosition,
  ///   speedKmh: 62,
  ///   timeHorizon: const Duration(minutes: 10),
  /// );
  ///
  /// for (final event in forecast.breaches) {
  ///   alert(
  ///     'Vehicle will ${event.eventType.name} zone ${event.geofenceId} '
  ///     'in ${event.timeUntilBreach!.inMinutes} min',
  ///   );
  /// }
  /// ```
  ///
  /// **Warning before is a different operation from warning after.** With a
  /// stolen vehicle, six minutes of lead time are the difference between
  /// intercepting it and chasing it.
  ///
  /// ## Two things you need to know
  ///
  /// **Without [speedKmh] or without [timeHorizon] it predicts nothing**: it
  /// turns into a simple containment check and returns only `IDLE` events for
  /// the geofences it's already in. It's useful, but it's not what you asked
  /// for.
  ///
  /// **It doesn't take heading into account.** The AWS documentation says so
  /// explicitly: it's conservative and includes possible crossings in *any*
  /// direction. With a vehicle stopped at an intersection, that's several
  /// zones at once.
  ///
  /// ## The unit
  ///
  /// This family does have `DistanceUnit` —it's from the previous
  /// generation—. Here it's always requested in kilometers and **converted to
  /// meters**, so that `nearestDistance` arrives in the same unit as
  /// everything else in the package.
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
        // Fixed on purpose: requested in kilometers and converted to meters
        // on read, so the rest of the package stays in SI units.
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
            // From kilometers to meters.
            nearestDistance: e.nearestDistance * 1000,
            forecastedBreachTime: e.forecastedBreachTime,
            geofenceProperties: e.geofenceProperties,
          ),
      ],
      nextToken: respuesta.nextToken,
    );
  }

  // ─── Collections · control plane ──────────────────────────────────────

  /// Creates a geofence collection.
  ///
  /// It goes to **another host** (`cp.geofencing.geo.…`) and is usually done
  /// once, from an admin tool or from the console. A mobile app should almost
  /// never have permission for this.
  ///
  /// [kmsKeyId] encrypts the geofences with your own key. It's what a client
  /// asks for when they consider the zones sensitive information — and a zone
  /// *draws* where someone lives, so sometimes it is.
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

  /// Reads a collection's data, including how many geofences it has.
  Future<GeofenceCollection> describeCollection(String collectionName) async {
    final json = await _transport.sendJson(
      operation: 'DescribeGeofenceCollection',
      service: _control,
      method: 'GET',
      path: '/geofencing/v0/collections/${_seg(collectionName)}',
    );
    return GeofenceCollection.fromJson(json);
  }

  /// Changes a collection's description.
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

  /// Deletes a collection **and all its geofences**.
  ///
  /// It can't be undone, and linked trackers stop firing events without
  /// raising any error: nothing triggers anymore.
  Future<void> deleteCollection(String collectionName) async {
    await _transport.sendJson(
      operation: 'DeleteGeofenceCollection',
      service: _control,
      method: 'DELETE',
      path: '/geofencing/v0/collections/${_seg(collectionName)}',
    );
  }

  /// Lists the account's collections.
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

  // ─── Helpers ──────────────────────────────────────────────────────────

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
