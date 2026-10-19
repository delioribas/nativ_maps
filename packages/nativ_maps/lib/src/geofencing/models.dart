// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/json.dart';
import 'package:nativ_maps/src/core/lat_lng.dart';
import 'package:nativ_maps/src/core/rings.dart';

/// The shape of a geofence: a circle, a polygon or several polygons.
///
/// ## Watch the coordinate order
///
/// As everywhere in Amazon Location, the JSON carries `[lon, lat]`. This type
/// absorbs that: you build it with [LatLng] and the order is flipped at the
/// boundary.
@immutable
class GeofenceGeometry {
  const GeofenceGeometry._({this.circle, this.polygon, this.multiPolygon});

  /// A circular geofence: a center and a radius **in meters**.
  ///
  /// It's the cheapest way to express "within 500 m of the warehouse", and the
  /// one the service evaluates fastest.
  factory GeofenceGeometry.circle({
    required LatLng center,
    required double radiusMeters,
  }) {
    if (radiusMeters <= 0) {
      throw ArgumentError.value(
        radiusMeters,
        'radiusMeters',
        'debe ser positivo',
      );
    }
    return GeofenceGeometry._(
      circle: (center: center, radiusMeters: radiusMeters),
    );
  }

  /// A polygonal geofence.
  ///
  /// The first ring is the outline; the following ones are holes. **The
  /// maximum is 1,000 vertices in total**, counting every ring: above that,
  /// the service rejects the request.
  ///
  /// The ring is closed automatically if it didn't come closed.
  factory GeofenceGeometry.polygon(List<List<LatLng>> rings) {
    if (rings.isEmpty || rings.first.length < 3) {
      throw ArgumentError.value(
        rings,
        'rings',
        'un polígono necesita al menos un anillo de 3 puntos',
      );
    }
    final total = rings.fold<int>(0, (sum, ring) => sum + ring.length);
    if (total > 1000) {
      throw ArgumentError.value(
        total,
        'rings',
        'el máximo son 1000 vértices en total; para más, usa Geobuf',
      );
    }
    return GeofenceGeometry._(polygon: rings);
  }

  /// Several independent polygons in a single geofence.
  ///
  /// It's for a zone made of several separate patches —three branches, for
  /// example— without having to create three geofences.
  factory GeofenceGeometry.multiPolygon(List<List<List<LatLng>>> polygons) {
    if (polygons.isEmpty) {
      throw ArgumentError.value(polygons, 'polygons', 'no puede estar vacío');
    }
    return GeofenceGeometry._(multiPolygon: polygons);
  }

  /// Reads the geometry from the service response.
  factory GeofenceGeometry.fromJson(Map<String, dynamic> json) {
    final circle = Json.object(json, 'Circle');
    if (circle != null) {
      final center = Json.latLng(circle, 'Center');
      final radius = Json.number(circle, 'Radius');
      if (center != null && radius != null) {
        return GeofenceGeometry._(
          circle: (center: center, radiusMeters: radius),
        );
      }
    }

    final polygon = json['Polygon'];
    if (polygon is List) {
      return GeofenceGeometry._(polygon: _readRings(polygon));
    }

    final multi = json['MultiPolygon'];
    if (multi is List) {
      return GeofenceGeometry._(
        multiPolygon: <List<List<LatLng>>>[
          for (final poly in multi)
            if (poly is List) _readRings(poly),
        ],
      );
    }

    // Geobuf: it's recognized and flagged as unsupported instead of
    // pretending the geofence has no shape. See `isGeobuf`.
    return const GeofenceGeometry._();
  }

  static List<List<LatLng>> _readRings(List<dynamic> raw) => <List<LatLng>>[
    for (final ring in raw)
      if (ring is List)
        <LatLng>[
          for (final coordinate in ring)
            if (coordinate is List && coordinate.length >= 2)
              LatLng.fromLonLat(coordinate),
        ],
  ];

  /// The circle, if it's circular.
  final ({LatLng center, double radiusMeters})? circle;

  /// The rings, if it's polygonal. The first one is the outline.
  final List<List<LatLng>>? polygon;

  /// The polygons, if there are several.
  final List<List<List<LatLng>>>? multiPolygon;

  /// Did it come encoded in Geobuf?
  ///
  /// This package **doesn't decode Geobuf**: it's a protocol buffers format
  /// that would require a whole dependency for a rare case. A Geobuf geofence
  /// is read with all three shapes empty, and this says so explicitly instead
  /// of pretending the geofence has no shape.
  bool get isGeobuf =>
      circle == null && polygon == null && multiPolygon == null;

  /// The main outline, whatever the shape.
  ///
  /// A circle is turned into a 72-sided polygon so it can be drawn.
  List<LatLng> get outerRing {
    final c = circle;
    if (c != null) return _circleToRing(c.center, c.radiusMeters);
    final p = polygon;
    if (p != null && p.isNotEmpty) return p.first;
    final m = multiPolygon;
    if (m != null && m.isNotEmpty && m.first.isNotEmpty) return m.first.first;
    return const <LatLng>[];
  }

  /// Does it contain this point?
  ///
  /// **It's computed here, without calling the service.** It's exact for the
  /// circle and a ray-casting approximation for the polygon, and it's enough
  /// to draw the state in the UI without spending a request.
  ///
  /// The **official** evaluation —the one that fires the EventBridge events—
  /// is done by `batchEvaluateGeofences`, and it may differ at the edges.
  bool contains(LatLng point) {
    final c = circle;
    if (c != null) return c.center.distanceTo(point) <= c.radiusMeters;

    final rings = polygon ?? multiPolygon?.expand((p) => p).toList();
    if (rings == null || rings.isEmpty) return false;

    var inside = _pointInRing(point, rings.first);
    // The following rings are holes: falling inside one takes you out of the
    // polygon.
    for (final hole in rings.skip(1)) {
      if (_pointInRing(point, hole)) inside = false;
    }
    return inside;
  }

  /// The geometry in the shape the service expects.
  Map<String, dynamic> toJson() {
    final c = circle;
    if (c != null) {
      return <String, dynamic>{
        'Circle': <String, dynamic>{
          'Center': c.center.toLonLat(),
          'Radius': c.radiusMeters,
        },
      };
    }
    final p = polygon;
    if (p != null) {
      return <String, dynamic>{'Polygon': _ringsToJson(p)};
    }
    final m = multiPolygon;
    if (m != null) {
      return <String, dynamic>{
        'MultiPolygon': <dynamic>[for (final poly in m) _ringsToJson(poly)],
      };
    }
    throw StateError('una geovalla sin forma no se puede enviar');
  }

  /// Converts rings to JSON: closed, the outline counterclockwise and the
  /// holes clockwise, which is what the service requires.
  static List<dynamic> _ringsToJson(List<List<LatLng>> rings) => <dynamic>[
    for (var i = 0; i < rings.length; i++)
      ringToLonLat(rings[i], counterClockwise: i == 0),
  ];

  static bool _pointInRing(LatLng point, List<LatLng> ring) {
    if (ring.length < 3) return false;
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i];
      final b = ring[j];
      final cruza =
          (a.latitude > point.latitude) != (b.latitude > point.latitude);
      if (!cruza) continue;
      final x =
          (b.longitude - a.longitude) *
              (point.latitude - a.latitude) /
              (b.latitude - a.latitude) +
          a.longitude;
      if (point.longitude < x) inside = !inside;
    }
    return inside;
  }

  static List<LatLng> _circleToRing(LatLng center, double radiusMeters) =>
      <LatLng>[
        for (var i = 0; i <= 72; i++) center.offset(radiusMeters, i * 5.0),
      ];

  @override
  String toString() {
    if (circle != null) {
      return 'GeofenceGeometry.circle(${circle!.radiusMeters} m)';
    }
    if (polygon != null) {
      return 'GeofenceGeometry.polygon(${polygon!.length} anillo(s))';
    }
    if (multiPolygon != null) {
      return 'GeofenceGeometry.multiPolygon(${multiPolygon!.length})';
    }
    return 'GeofenceGeometry(Geobuf, no decodificado)';
  }
}

/// A stored geofence.
@immutable
class Geofence {
  /// Creates the geofence.
  const Geofence({
    required this.geofenceId,
    required this.geometry,
    this.status,
    this.createTime,
    this.updateTime,
    this.properties = const <String, String>{},
  });

  /// Reads the geofence from the service response.
  factory Geofence.fromJson(Map<String, dynamic> json) {
    final geometry = Json.object(json, 'Geometry');
    return Geofence(
      geofenceId: Json.string(json, 'GeofenceId') ?? '',
      geometry: geometry == null
          ? const GeofenceGeometry._()
          : GeofenceGeometry.fromJson(geometry),
      status: Json.string(json, 'Status'),
      createTime: Json.dateTime(json, 'CreateTime'),
      updateTime: Json.dateTime(json, 'UpdateTime'),
      properties: _readProperties(json['GeofenceProperties']),
    );
  }

  static Map<String, String> _readProperties(Object? raw) {
    if (raw is! Map) return const <String, String>{};
    return <String, String>{
      for (final entry in raw.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
  }

  /// The identifier within the collection.
  final String geofenceId;

  /// The shape.
  final GeofenceGeometry geometry;

  /// `ACTIVE`, `PENDING`, `FAILED` or `DELETING`.
  ///
  /// A freshly created geofence takes a moment to become `ACTIVE`, and until
  /// then it **fires no events**. Evaluating positions against one in
  /// `PENDING` doesn't fail: nothing triggers at all, which is worse.
  final String? status;

  /// When it was created.
  final DateTime? createTime;

  /// When it was last changed.
  final DateTime? updateTime;

  /// Up to **three** properties that travel inside every event it fires.
  ///
  /// It's where you put the client identifier or the zone type, so you don't
  /// have to look it up when the event arrives. Keys accept 20 characters and
  /// values 40.
  final Map<String, String> properties;

  /// Is it ready to fire events?
  bool get isActive => status == 'ACTIVE';

  @override
  String toString() => 'Geofence($geofenceId, ${status ?? '?'})';
}

/// A device's position, as it's sent to the service.
@immutable
class DevicePositionUpdate {
  /// Creates the update.
  const DevicePositionUpdate({
    required this.deviceId,
    required this.position,
    required this.sampleTime,
    this.horizontalAccuracyMeters,
    this.properties = const <String, String>{},
  });

  /// The device identifier.
  ///
  /// For geofences **an associated tracker doesn't need to exist**: it's a
  /// free-form string.
  final String deviceId;

  /// Where it was.
  final LatLng position;

  /// When the reading was taken.
  ///
  /// **It's not the send time.** Sending the current time instead of the GPS
  /// time scrambles the history and fools the tracker's time-based filtering.
  final DateTime sampleTime;

  /// The GPS horizontal accuracy in meters.
  ///
  /// With a tracker in `AccuracyBased` mode, this value decides whether the
  /// position is stored: leaving it out amounts to saying "perfect accuracy",
  /// and then everything is stored.
  final double? horizontalAccuracyMeters;

  /// Up to three properties that travel with the position.
  final Map<String, String> properties;

  /// The update in the shape the service expects.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'DeviceId': deviceId,
    'Position': position.toLonLat(),
    'SampleTime': sampleTime.toUtc().toIso8601String(),
    if (horizontalAccuracyMeters != null)
      'Accuracy': <String, dynamic>{'Horizontal': horizontalAccuracyMeters},
    if (properties.isNotEmpty) 'PositionProperties': properties,
  };

  @override
  String toString() => 'DevicePositionUpdate($deviceId @ $position)';
}

/// A per-item error in a batch operation.
///
/// It exists because these operations **don't fail as a whole**: they process
/// what they can and return the failures one by one. Ignoring this list means
/// losing positions without noticing.
@immutable
class BatchItemError {
  /// Creates the error.
  const BatchItemError({
    required this.itemId,
    this.code,
    this.message,
    this.sampleTime,
  });

  /// Reads the error from the service response.
  factory BatchItemError.fromJson(Map<String, dynamic> json, String idField) {
    final error = Json.object(json, 'Error');
    return BatchItemError(
      itemId: Json.string(json, idField) ?? '',
      code: Json.string(error, 'Code'),
      message: Json.string(error, 'Message'),
      sampleTime: Json.dateTime(json, 'SampleTime'),
    );
  }

  /// The identifier of the item that failed.
  final String itemId;

  /// The AWS code: `AccessDeniedError`, `ValidationError`…
  final String? code;

  /// The explanation.
  final String? message;

  /// The sample time, on position errors.
  final DateTime? sampleTime;

  @override
  String toString() => 'BatchItemError($itemId, ${code ?? '?'}): $message';
}

/// The result of a batch operation.
@immutable
class BatchResult {
  /// Creates the result.
  const BatchResult({
    required this.total,
    this.errors = const <BatchItemError>[],
  });

  /// How many items were sent.
  final int total;

  /// The ones that failed. **You have to check it**: the operation returns 200
  /// even if half of them fail.
  final List<BatchItemError> errors;

  /// How many succeeded.
  int get succeeded => total - errors.length;

  /// Did everything succeed?
  bool get isCompleteSuccess => errors.isEmpty;

  @override
  String toString() => 'BatchResult($succeeded/$total)';
}

/// What's going to happen to a device with respect to a geofence.
enum ForecastedEventType {
  /// It's going to enter the zone.
  enter('ENTER'),

  /// It's going to leave the zone.
  exit('EXIT'),

  /// It's inside and will stay inside.
  idle('IDLE');

  const ForecastedEventType(this.wireName);

  /// The literal the service returns.
  final String wireName;
}

/// A geofence event **that hasn't happened yet**.
///
/// This is what makes `forecastGeofenceEvents` unique: it doesn't tell you
/// where the device is, it tells you **where it's going to be** if it keeps
/// its speed. For a tracking app it's the difference between warning when the
/// vehicle has already left the allowed zone and warning six minutes before.
@immutable
class ForecastedGeofenceEvent {
  /// Creates the forecasted event.
  const ForecastedGeofenceEvent({
    required this.eventId,
    required this.geofenceId,
    required this.eventType,
    required this.isDeviceInGeofence,
    required this.nearestDistance,
    this.forecastedBreachTime,
    this.geofenceProperties = const <String, String>{},
  });

  /// Reads the event from the service response.
  factory ForecastedGeofenceEvent.fromJson(Map<String, dynamic> json) =>
      ForecastedGeofenceEvent(
        eventId: Json.string(json, 'EventId') ?? '',
        geofenceId: Json.string(json, 'GeofenceId') ?? '',
        eventType:
            Json.enumValue(
              json,
              'EventType',
              ForecastedEventType.values,
              (t) => t.wireName,
            ) ??
            ForecastedEventType.idle,
        isDeviceInGeofence: Json.boolean(json, 'IsDeviceInGeofence') ?? false,
        nearestDistance: Json.numberOrZero(json, 'NearestDistance'),
        forecastedBreachTime: Json.dateTime(json, 'ForecastedBreachTime'),
        geofenceProperties: Geofence._readProperties(
          json['GeofenceProperties'],
        ),
      );

  /// The identifier of the forecasted event.
  final String eventId;

  /// The geofence involved.
  final String geofenceId;

  /// What's going to happen.
  final ForecastedEventType eventType;

  /// Is it inside the geofence right now?
  final bool isDeviceInGeofence;

  /// Distance to the nearest edge.
  ///
  /// ⚠️ **In the unit that was requested**, and the API's default is
  /// **kilometers**, not meters. It's the only quantity in the whole package
  /// that doesn't arrive in meters, and not by choice: this family of
  /// operations is from the previous generation, the one that does have
  /// `DistanceUnit`.
  ///
  /// `GeofencingClient.forecastGeofenceEvents` requests kilometers and
  /// converts them, so **this field does arrive in meters**. The detail is
  /// documented because anyone reading the raw AWS response will see
  /// something else.
  final double nearestDistance;

  /// When it's expected to cross the edge.
  final DateTime? forecastedBreachTime;

  /// The geofence's properties, so you don't have to look it up.
  final Map<String, String> geofenceProperties;

  /// How long until it crosses, from now.
  Duration? get timeUntilBreach {
    final breach = forecastedBreachTime;
    if (breach == null) return null;
    final falta = breach.difference(DateTime.now().toUtc());
    return falta.isNegative ? Duration.zero : falta;
  }

  @override
  String toString() =>
      'ForecastedGeofenceEvent(${eventType.name} '
      '$geofenceId en ${timeUntilBreach?.inMinutes ?? '?'} min)';
}

/// The `forecastGeofenceEvents` response.
@immutable
class ForecastGeofenceEventsResponse {
  /// Creates the response.
  const ForecastGeofenceEventsResponse({
    this.events = const <ForecastedGeofenceEvent>[],
    this.nextToken,
  });

  /// Reads the service response.
  factory ForecastGeofenceEventsResponse.fromJson(Map<String, dynamic> json) =>
      ForecastGeofenceEventsResponse(
        events: Json.objects(
          json,
          'ForecastedEvents',
        ).map(ForecastedGeofenceEvent.fromJson).toList(growable: false),
        nextToken: Json.string(json, 'NextToken'),
      );

  /// The forecasted events.
  final List<ForecastedGeofenceEvent> events;

  /// The token for the next page.
  final String? nextToken;

  /// Only the ones that mean crossing an edge: entering or leaving.
  ///
  /// It's what you should show. The [ForecastedEventType.idle] ones say "still
  /// where it was", which is almost never an alert.
  List<ForecastedGeofenceEvent> get breaches => events
      .where((e) => e.eventType != ForecastedEventType.idle)
      .toList(growable: false);

  @override
  String toString() =>
      'ForecastGeofenceEventsResponse(${events.length} evento(s), '
      '${breaches.length} cruce(s))';
}

/// A geofence collection.
@immutable
class GeofenceCollection {
  /// Creates the collection.
  const GeofenceCollection({
    required this.collectionName,
    this.collectionArn,
    this.description,
    this.geofenceCount,
    this.kmsKeyId,
    this.createTime,
    this.updateTime,
    this.tags = const <String, String>{},
  });

  /// Reads the collection from the service response.
  factory GeofenceCollection.fromJson(Map<String, dynamic> json) =>
      GeofenceCollection(
        collectionName: Json.string(json, 'CollectionName') ?? '',
        collectionArn: Json.string(json, 'CollectionArn'),
        description: Json.string(json, 'Description'),
        geofenceCount: Json.integer(json, 'GeofenceCount'),
        kmsKeyId: Json.string(json, 'KmsKeyId'),
        createTime: Json.dateTime(json, 'CreateTime'),
        updateTime: Json.dateTime(json, 'UpdateTime'),
        tags: Geofence._readProperties(json['Tags']),
      );

  /// The name, which is its identifier.
  final String collectionName;

  /// The full ARN. It's what you need to link it to a tracker.
  final String? collectionArn;

  /// The description.
  final String? description;

  /// How many geofences it has.
  final int? geofenceCount;

  /// The KMS key it's encrypted with, if one was configured.
  final String? kmsKeyId;

  /// When it was created.
  final DateTime? createTime;

  /// When it was changed.
  final DateTime? updateTime;

  /// The AWS tags.
  final Map<String, String> tags;

  @override
  String toString() => 'GeofenceCollection($collectionName)';
}

/// A page of geofences or collections.
@immutable
class GeofencePage<T> {
  /// Creates the page.
  const GeofencePage({required this.items, this.nextToken});

  /// The items on this page.
  final List<T> items;

  /// The token for the next one, or `null` if there are no more.
  final String? nextToken;

  /// Are there more pages?
  bool get hasMore => nextToken != null;

  @override
  String toString() =>
      'GeofencePage(${items.length}${hasMore ? ', hay más' : ''})';
}
