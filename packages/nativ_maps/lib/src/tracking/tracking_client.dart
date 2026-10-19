// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/client/transport.dart';
import 'package:nativ_maps/src/core/enums.dart';
import 'package:nativ_maps/src/core/json.dart';
import 'package:nativ_maps/src/core/lat_lng.dart';
import 'package:nativ_maps/src/core/rings.dart';
import 'package:nativ_maps/src/geofencing/models.dart'
    show BatchItemError, BatchResult, DevicePositionUpdate;
import 'package:nativ_maps/src/tracking/models.dart';

/// The **15 device tracking operations** of Amazon Location.
///
/// | Method | Endpoint | What for |
/// |---|---|---|
/// | [batchUpdateDevicePosition] | `POST …/positions` | upload positions |
/// | [getDevicePosition] | `GET …/devices/{d}/positions/latest` | the latest |
/// | [batchGetDevicePosition] | `POST …/get-positions` | the latest of several |
/// | [getDevicePositionHistory] | `POST …/devices/{d}/list-positions` | the history |
/// | [listDevicePositions] | `POST …/list-positions` | **who is in this area** |
/// | [batchDeleteDevicePositionHistory] | `POST …/delete-positions` | delete history |
/// | [verifyDevicePosition] | `POST …/positions/verify` | **are they lying to me?** |
/// | [createTracker] · [describeTracker] | control | manage |
/// | [updateTracker] · [deleteTracker] | control | manage |
/// | [listTrackers] | control | list them |
/// | [associateConsumer] | control | **link geofences** |
/// | [disassociateConsumer] · [listConsumers] | control | inspect and undo |
///
/// ## ⚠️ Before using it: do you really need it?
///
/// If you already store your devices' history in your own database —the
/// usual case when tracking devices report to your own server—, this is
/// **duplicated infrastructure** and a second bill for the same data.
///
/// The three things that do justify using it:
///
/// 1. **[associateConsumer]**: linking the tracker to a geofence collection
///    makes AWS evaluate every position **automatically** and fire events on
///    EventBridge. Without it you have to call `batchEvaluateGeofences` by
///    hand for every position.
/// 2. **[verifyDevicePosition]**: detects spoofed locations. There is no way
///    to do this on your own.
/// 3. **[listDevicePositions] with `filterGeometry`**: "who is inside this
///    polygon right now", resolved by the service.
///
/// ## Three things that are not like in v2
///
/// 1. **You have to create a tracker.** With [createTracker] or in the
///    console.
/// 2. **It doesn't accept an API key.** SigV4 credentials are required.
/// 3. **The history is deleted after 30 days.** It is not configurable. If
///    you need to keep it longer, you have to copy it to your own storage.
class TrackingClient {
  /// Builds the client. Internal use: it comes already wired into `NativMaps`.
  @internal
  TrackingClient({required AlsTransport transport}) : _transport = transport;

  final AlsTransport _transport;

  static const AlsService _data = AlsService.tracking;
  static const AlsService _control = AlsService.trackingControl;

  /// Maximum devices per batch call.
  static const int maxDevicesPerBatch = 10;

  /// How many days AWS keeps the history. **It is not configurable.**
  static const int historyRetentionDays = 30;

  // ─── Positions ────────────────────────────────────────────────────────

  /// Uploads positions for up to 10 devices.
  ///
  /// ```dart
  /// await maps.tracking.batchUpdateDevicePosition(
  ///   trackerName: 'fleet',
  ///   updates: [
  ///     for (final p in batch)
  ///       DevicePositionUpdate(
  ///         deviceId: p.imei,
  ///         position: LatLng(p.lat, p.lng),
  ///         sampleTime: p.gpsTime,             // the GPS time, not now
  ///         horizontalAccuracyMeters: p.hdop * 5,
  ///       ),
  ///   ],
  /// );
  /// ```
  ///
  /// ## What the tracker may discard
  ///
  /// **Not everything you upload gets stored.** The tracker's
  /// `positionFiltering` decides, and with the default
  /// —[PositionFiltering.timeBased]— only **one position every 30 seconds per
  /// device** is stored. A
  /// tracking device that reports every five seconds will see five out of six
  /// positions discarded without any error.
  ///
  /// For vehicle tracking, [PositionFiltering.distanceBased] is almost always
  /// the right choice.
  ///
  /// ## The chunking
  ///
  /// The maximum is 10 per call. This method **chunks on its own** and returns
  /// the aggregated total, instead of forcing the caller to split the list.
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

  /// The last known position of a device.
  ///
  /// Checking [DevicePosition.isFresh] before treating it as "where it is now"
  /// is not optional: a vehicle whose last position is half an hour old **is
  /// not** there.
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

  /// The latest positions of several devices, up to 10.
  ///
  /// Returns the positions **and the per-device errors**: one that doesn't
  /// exist doesn't make the whole call fail, it shows up in
  /// [BatchResult.errors].
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

  /// The position history of a device.
  ///
  /// Without dates, the service returns **the last 24 hours**.
  ///
  /// **AWS deletes the history after 30 days** and it is not configurable:
  /// asking for anything older returns an empty list, not an error.
  ///
  /// The result goes straight into `snapToRoads` to clean it up:
  ///
  /// ```dart
  /// final history = await maps.tracking.getDevicePositionHistory(
  ///   trackerName: 'fleet',
  ///   deviceId: imei,
  ///   from: DateTime.now().subtract(const Duration(hours: 8)),
  /// );
  ///
  /// final cleaned = await maps.routes.snapToRoads(
  ///   tracePoints: [
  ///     for (final p in history.items)
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

  /// The latest positions of **all** the tracker's devices.
  ///
  /// With [filterGeometry] it answers "**who is inside this polygon right
  /// now**", resolved by the service instead of downloading the whole fleet
  /// and filtering on the phone.
  ///
  /// ```dart
  /// final inside = await maps.tracking.listDevicePositions(
  ///   trackerName: 'fleet',
  ///   filterGeometry: areaOfInterest,   // a polygon
  /// );
  /// ```
  ///
  /// The filter accepts **a single polygon** and up to 1,000 vertices.
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
              // Closed and counterclockwise: otherwise, 400.
              ringToLonLat(filterGeometry, counterClockwise: true),
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

  /// Deletes the history of several devices.
  ///
  /// **It cannot be undone.** It is for handling a personal-data deletion
  /// request: a vehicle's route *is* personal data of whoever drives it.
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

  /// Checks whether a reported position can be trusted.
  ///
  /// It compares what the device says with what the service infers from its
  /// IP address and the Wi-Fi access points it sees. It detects two things:
  ///
  /// - **That the position arrived through a proxy or a VPN**, which is the
  ///   strongest signal of a spoofed location.
  /// - **How far it is** from the inferred position.
  ///
  /// ```dart
  /// final v = await maps.tracking.verifyDevicePosition(
  ///   trackerName: 'fleet',
  ///   deviceId: imei,
  ///   position: reportedPosition,
  ///   sampleTime: gpsTime,
  ///   ipv4Address: deviceIp,
  ///   wifiAccessPoints: visibleAccessPoints,
  /// );
  ///
  /// if (v.isSuspicious()) review(imei);
  /// ```
  ///
  /// **Without [ipv4Address] or [wifiAccessPoints] it can't infer much**:
  /// they are the two signals independent of the GPS, and without them all
  /// that is left is what the device itself reports.
  ///
  /// The deviation arrives in the requested unit —kilometers by default—; here
  /// it is converted to **meters**, like the rest of the package.
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
      // From kilometers to meters.
      deviationMeters: v.deviationMeters == null
          ? null
          : v.deviationMeters! * 1000,
      inferredAccuracyMeters: v.inferredAccuracyMeters,
      sampleTime: v.sampleTime,
      receivedTime: v.receivedTime,
    );
  }

  // ─── Trackers · control plane ─────────────────────────────────────────

  /// Creates a tracker.
  ///
  /// **[positionFiltering] is the decision to think through.** The service's
  /// default stores one position every 30 seconds even while the vehicle is
  /// parked; [PositionFiltering.distanceBased] only stores if it moved more
  /// than 30 meters, and for vehicle tracking it is usually the right choice
  /// — a day's history goes from thousands of points to hundreds without
  /// losing anything of the route.
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

  /// Reads a tracker's data.
  Future<Tracker> describeTracker(String trackerName) async {
    final json = await _transport.sendJson(
      operation: 'DescribeTracker',
      service: _control,
      method: 'GET',
      path: '/tracking/v0/trackers/${_seg(trackerName)}',
    );
    return Tracker.fromJson(json);
  }

  /// Changes a tracker's configuration.
  ///
  /// Changing [positionFiltering] **does not reprocess the history**: it only
  /// applies to what arrives from now on.
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

  /// Deletes a tracker **and all its history**. It cannot be undone.
  Future<void> deleteTracker(String trackerName) async {
    await _transport.sendJson(
      operation: 'DeleteTracker',
      service: _control,
      method: 'DELETE',
      path: '/tracking/v0/trackers/${_seg(trackerName)}',
    );
  }

  /// Lists the account's trackers.
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

  // ─── Consumers: the link to geofences ─────────────────────────────────

  /// Links the tracker to a geofence collection.
  ///
  /// **This is what makes everything else work on its own.** Once linked,
  /// every position that comes in through [batchUpdateDevicePosition] is
  /// evaluated **automatically** against that collection's geofences and
  /// fires `ENTER` and `EXIT` events on Amazon EventBridge.
  ///
  /// Without the link you have to call
  /// `GeofencingClient.batchEvaluateGeofences` by hand for every batch of
  /// positions — twice the requests and twice the bill for the same result.
  ///
  /// [collectionArn] is the full ARN, not the name. It comes from
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

  /// Removes the link.
  ///
  /// From that moment on, positions stop being evaluated **without any
  /// error**: nothing fires, that's all.
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

  /// The geofence collections linked to a tracker.
  ///
  /// It is the first thing to check when "the geofences don't fire": it is
  /// almost always that the link isn't there.
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
