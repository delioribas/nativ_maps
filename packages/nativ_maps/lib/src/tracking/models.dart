// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/json.dart';
import 'package:nativ_maps/src/core/lat_lng.dart';

/// A device's position, as returned by the service.
@immutable
class DevicePosition {
  /// Creates the position.
  const DevicePosition({
    required this.position,
    required this.sampleTime,
    this.deviceId,
    this.receivedTime,
    this.horizontalAccuracyMeters,
    this.properties = const <String, String>{},
  });

  /// Reads the position from the service response.
  ///
  /// Throws [FormatException] if the coordinate can't be read: a device
  /// position **is** the data, and replacing it with `LatLng(0, 0)` would put
  /// the vehicle in the Gulf of Guinea while looking perfectly correct.
  factory DevicePosition.fromJson(Map<String, dynamic> json) => DevicePosition(
    position: Json.requiredLatLng(json, 'Position', 'DevicePosition'),
    sampleTime:
        Json.dateTime(json, 'SampleTime') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    deviceId: Json.string(json, 'DeviceId'),
    receivedTime: Json.dateTime(json, 'ReceivedTime'),
    horizontalAccuracyMeters: Json.number(
      Json.object(json, 'Accuracy'),
      'Horizontal',
    ),
    properties: _readProperties(json['PositionProperties']),
  );

  static Map<String, String> _readProperties(Object? raw) {
    if (raw is! Map) return const <String, String>{};
    return <String, String>{
      for (final entry in raw.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
  }

  /// Where it was.
  final LatLng position;

  /// When the GPS measured it.
  final DateTime sampleTime;

  /// Which device it was.
  final String? deviceId;

  /// When AWS received it.
  ///
  /// The difference from [sampleTime] is **the network delay**, and on a
  /// tracking device with poor coverage it can be minutes. Showing
  /// [receivedTime] as the "last position" makes people believe the vehicle
  /// was there a moment ago when the reading is a quarter of an hour old.
  final DateTime? receivedTime;

  /// The reported horizontal accuracy, in meters.
  final double? horizontalAccuracyMeters;

  /// The properties that traveled with the position.
  final Map<String, String> properties;

  /// How long the position took to arrive after it was measured.
  Duration? get networkDelay {
    final recibida = receivedTime;
    if (recibida == null) return null;
    final retraso = recibida.difference(sampleTime);
    return retraso.isNegative ? Duration.zero : retraso;
  }

  /// How long ago it was measured.
  Duration get age => DateTime.now().toUtc().difference(sampleTime.toUtc());

  /// Is it recent enough to treat as "where it is now"?
  ///
  /// A vehicle whose last position is half an hour old **is not** there: it
  /// is somewhere inside a twenty-kilometer circle. To draw that circle there
  /// is `RoutesClient.calculateIsolines`.
  bool isFresh({Duration maxAge = const Duration(minutes: 5)}) => age <= maxAge;

  @override
  String toString() =>
      'DevicePosition(${deviceId ?? '?'} @ $position, '
      'hace ${age.inMinutes} min)';
}

/// How the tracker decides which positions to store.
///
/// ## Why this is the first thing to choose
///
/// It is what separates a reasonable bill from an unpleasant one, and what
/// decides whether the history is useful. A tracking device that reports
/// every five seconds and a tracker in [timeBased] store **one in six**
/// positions.
enum PositionFiltering {
  /// One position every 30 seconds at most. **The default.**
  ///
  /// It keeps storing while the vehicle is parked, so the history fills up
  /// with identical points.
  timeBased('TimeBased'),

  /// Only if it moved more than 30 meters.
  ///
  /// **This is the right one for vehicle tracking**: a parked vehicle stops
  /// generating points, and a day's history goes from thousands of positions
  /// to hundreds without losing anything of the route.
  distanceBased('DistanceBased'),

  /// Only if it moved more than the GPS margin of error.
  ///
  /// The most conservative: with two readings of 5 m and 10 m accuracy, it
  /// discards the second if the movement was less than 15 m. It avoids the
  /// "jitter" of a vehicle parked between tall buildings.
  ///
  /// It requires sending `horizontalAccuracyMeters` with every position;
  /// without it, the service assumes perfect accuracy and stores everything.
  accuracyBased('AccuracyBased');

  const PositionFiltering(this.wireName);

  /// The literal that travels in the JSON.
  final String wireName;
}

/// A tracker: the resource where positions are stored.
@immutable
class Tracker {
  /// Creates the tracker.
  const Tracker({
    required this.trackerName,
    this.trackerArn,
    this.description,
    this.positionFiltering,
    this.eventBridgeEnabled,
    this.kmsKeyId,
    this.createTime,
    this.updateTime,
    this.tags = const <String, String>{},
  });

  /// Reads the tracker from the service response.
  factory Tracker.fromJson(Map<String, dynamic> json) => Tracker(
    trackerName: Json.string(json, 'TrackerName') ?? '',
    trackerArn: Json.string(json, 'TrackerArn'),
    description: Json.string(json, 'Description'),
    positionFiltering: Json.enumValue(
      json,
      'PositionFiltering',
      PositionFiltering.values,
      (f) => f.wireName,
    ),
    eventBridgeEnabled: Json.boolean(json, 'EventBridgeEnabled'),
    kmsKeyId: Json.string(json, 'KmsKeyId'),
    createTime: Json.dateTime(json, 'CreateTime'),
    updateTime: Json.dateTime(json, 'UpdateTime'),
    tags: DevicePosition._readProperties(json['Tags']),
  );

  /// The name, which is its identifier.
  final String trackerName;

  /// The full ARN.
  final String? trackerArn;

  /// The description.
  final String? description;

  /// Which positions it stores. See [PositionFiltering].
  final PositionFiltering? positionFiltering;

  /// Does it publish position changes to EventBridge?
  ///
  /// This is different from geofence events: it emits one event for **every
  /// stored position**, and with a large fleet that is a lot of them.
  final bool? eventBridgeEnabled;

  /// The KMS key the history is encrypted with.
  final String? kmsKeyId;

  /// When it was created.
  final DateTime? createTime;

  /// When it was changed.
  final DateTime? updateTime;

  /// The AWS tags.
  final Map<String, String> tags;

  @override
  String toString() => 'Tracker($trackerName)';
}

/// The result of checking whether a position can be trusted.
///
/// It is returned by `TrackingClient.verifyDevicePosition`, and it answers a
/// question no other operation answers: **is the device lying to me?**
@immutable
class PositionVerification {
  /// Creates the result.
  const PositionVerification({
    required this.deviceId,
    required this.proxyDetected,
    this.inferredPosition,
    this.deviationMeters,
    this.inferredAccuracyMeters,
    this.sampleTime,
    this.receivedTime,
  });

  /// Reads the result from the service response.
  ///
  /// The deviation arrives in the requested unit —kilometers by default—;
  /// `TrackingClient` converts it to meters before building this.
  factory PositionVerification.fromJson(Map<String, dynamic> json) {
    final inferido = Json.object(json, 'InferredState');
    return PositionVerification(
      deviceId: Json.string(json, 'DeviceId') ?? '',
      proxyDetected: Json.boolean(inferido, 'ProxyDetected') ?? false,
      inferredPosition: Json.latLng(inferido, 'Position'),
      deviationMeters: Json.number(inferido, 'DeviationDistance'),
      inferredAccuracyMeters: Json.number(
        Json.object(inferido, 'Accuracy'),
        'Horizontal',
      ),
      sampleTime: Json.dateTime(json, 'SampleTime'),
      receivedTime: Json.dateTime(json, 'ReceivedTime'),
    );
  }

  /// Which device was checked.
  final String deviceId;

  /// **Did the position arrive through a proxy or a VPN?**
  ///
  /// It is the strongest signal that someone is faking the location: an
  /// honest tracking device connected over the mobile network doesn't go
  /// through a proxy.
  final bool proxyDetected;

  /// Where the service believes it really was, inferred from the IP, the cell
  /// towers and the Wi-Fi access points seen.
  final LatLng? inferredPosition;

  /// How far the reported position is from the inferred one, **in meters**.
  ///
  /// A deviation of tens of meters is normal. One of tens of kilometers with
  /// `proxyDetected` set to `true` is someone lying.
  final double? deviationMeters;

  /// The accuracy of the inferred position.
  final double? inferredAccuracyMeters;

  /// When it was measured.
  final DateTime? sampleTime;

  /// When it arrived.
  final DateTime? receivedTime;

  /// Is there reason to distrust this position?
  ///
  /// The default threshold —10 km— is deliberately generous: cell-tower
  /// location has an error of kilometers in rural areas, and a tight
  /// threshold would flag half the countryside as suspicious.
  bool isSuspicious({double maxDeviationMeters = 10000}) =>
      proxyDetected ||
      (deviationMeters != null && deviationMeters! > maxDeviationMeters);

  @override
  String toString() =>
      'PositionVerification($deviceId, '
      'proxy: $proxyDetected, desvío: ${deviationMeters?.round()} m)';
}

/// A Wi-Fi access point seen by the device, to verify its position.
@immutable
class WiFiAccessPoint {
  /// Creates the access point.
  const WiFiAccessPoint({required this.macAddress, required this.rss});

  /// The MAC address of the access point.
  final String macAddress;

  /// The received signal strength, in dBm. It is negative.
  final int rss;

  /// The access point in the shape the service expects.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'MacAddress': macAddress,
    'Rss': rss,
  };
}

/// A page of positions or trackers.
@immutable
class TrackingPage<T> {
  /// Creates the page.
  const TrackingPage({required this.items, this.nextToken});

  /// The items.
  final List<T> items;

  /// The token for the next page.
  final String? nextToken;

  /// Are there more?
  bool get hasMore => nextToken != null;

  @override
  String toString() =>
      'TrackingPage(${items.length}${hasMore ? ', hay más' : ''})';
}
