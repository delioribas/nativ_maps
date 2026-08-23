// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:compass_maps/src/core/json.dart';
import 'package:compass_maps/src/core/lat_lng.dart';
import 'package:meta/meta.dart';

/// La forma de una geovalla: un círculo, un polígono o varios polígonos.
///
/// ## Cuidado con el orden de las coordenadas
///
/// Como en todo Amazon Location, en el JSON van `[lon, lat]`. Este tipo lo
/// absorbe: se construye con [LatLng] y el orden se invierte en la frontera.
@immutable
class GeofenceGeometry {
  const GeofenceGeometry._({this.circle, this.polygon, this.multiPolygon});

  /// Una geovalla circular: un centro y un radio **en metros**.
  ///
  /// Es la forma más barata de expresar «a 500 m de la bodega», y la que el
  /// servicio evalúa más rápido.
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

  /// Una geovalla poligonal.
  ///
  /// El primer anillo es el contorno; los siguientes son agujeros. **El
  /// máximo son 1 000 vértices en total**, contando todos los anillos: por
  /// encima, el servicio rechaza la petición.
  ///
  /// El anillo se cierra solo si no venía cerrado.
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

  /// Varios polígonos independientes en una sola geovalla.
  ///
  /// Sirve para una zona que son varias manchas separadas —tres sucursales,
  /// por ejemplo— sin tener que crear tres geovallas.
  factory GeofenceGeometry.multiPolygon(List<List<List<LatLng>>> polygons) {
    if (polygons.isEmpty) {
      throw ArgumentError.value(polygons, 'polygons', 'no puede estar vacío');
    }
    return GeofenceGeometry._(multiPolygon: polygons);
  }

  /// Lee la geometría de la respuesta del servicio.
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

    // Geobuf: se reconoce y se marca como no soportado en lugar de fingir que
    // la geovalla no tiene forma. Ver `isGeobuf`.
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

  /// El círculo, si es circular.
  final ({LatLng center, double radiusMeters})? circle;

  /// Los anillos, si es poligonal. El primero es el contorno.
  final List<List<LatLng>>? polygon;

  /// Los polígonos, si son varios.
  final List<List<List<LatLng>>>? multiPolygon;

  /// ¿Vino codificada en Geobuf?
  ///
  /// Este paquete **no decodifica Geobuf**: es un formato de protocol buffers
  /// que exigiría una dependencia entera para un caso poco frecuente. Una
  /// geovalla en Geobuf se lee con las tres formas vacías, y esto lo dice
  /// explícitamente en vez de aparentar que la geovalla no tiene forma.
  bool get isGeobuf =>
      circle == null && polygon == null && multiPolygon == null;

  /// El contorno principal, sea cual sea la forma.
  ///
  /// Un círculo se convierte en un polígono de 72 lados para poder pintarlo.
  List<LatLng> get outerRing {
    final c = circle;
    if (c != null) return _circleToRing(c.center, c.radiusMeters);
    final p = polygon;
    if (p != null && p.isNotEmpty) return p.first;
    final m = multiPolygon;
    if (m != null && m.isNotEmpty && m.first.isNotEmpty) return m.first.first;
    return const <LatLng>[];
  }

  /// ¿Contiene este punto?
  ///
  /// **Se calcula aquí, sin llamar al servicio.** Es exacto para el círculo y
  /// una aproximación por rayo para el polígono, y basta para pintar el estado
  /// en la interfaz sin gastar una petición.
  ///
  /// La evaluación **oficial** —la que dispara los eventos de EventBridge— la
  /// hace `batchEvaluateGeofences`, y puede diferir en los bordes.
  bool contains(LatLng point) {
    final c = circle;
    if (c != null) return c.center.distanceTo(point) <= c.radiusMeters;

    final rings = polygon ?? multiPolygon?.expand((p) => p).toList();
    if (rings == null || rings.isEmpty) return false;

    var inside = _pointInRing(point, rings.first);
    // Los anillos siguientes son agujeros: caer dentro de uno saca del
    // polígono.
    for (final hole in rings.skip(1)) {
      if (_pointInRing(point, hole)) inside = false;
    }
    return inside;
  }

  /// La geometría en la forma que espera el servicio.
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

  /// Convierte anillos a JSON, cerrándolos si hace falta.
  static List<dynamic> _ringsToJson(List<List<LatLng>> rings) => <dynamic>[
    for (final ring in rings)
      <dynamic>[
        for (final point in ring) point.toLonLat(),
        // El servicio exige el anillo cerrado. Sin esto responde un 400
        // que dice «LinearRing must be closed», que al menos es claro,
        // pero es un viaje de ida perdido.
        if (ring.isNotEmpty && ring.first != ring.last) ring.first.toLonLat(),
      ],
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

/// Una geovalla guardada.
@immutable
class Geofence {
  /// Crea la geovalla.
  const Geofence({
    required this.geofenceId,
    required this.geometry,
    this.status,
    this.createTime,
    this.updateTime,
    this.properties = const <String, String>{},
  });

  /// Lee la geovalla de la respuesta del servicio.
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

  /// El identificador dentro de la colección.
  final String geofenceId;

  /// La forma.
  final GeofenceGeometry geometry;

  /// `ACTIVE`, `PENDING`, `FAILED` o `DELETING`.
  ///
  /// Una geovalla recién creada tarda un momento en pasar a `ACTIVE`, y hasta
  /// entonces **no dispara eventos**. Evaluar posiciones contra una en
  /// `PENDING` no falla: simplemente no salta nada, que es peor.
  final String? status;

  /// Cuándo se creó.
  final DateTime? createTime;

  /// Cuándo se cambió por última vez.
  final DateTime? updateTime;

  /// Hasta **tres** propiedades que viajan dentro de cada evento que dispare.
  ///
  /// Es donde se mete el identificador del cliente o el tipo de zona, para no
  /// tener que consultarlo al recibir el evento. Las claves admiten 20
  /// caracteres y los valores 40.
  final Map<String, String> properties;

  /// ¿Está lista para disparar eventos?
  bool get isActive => status == 'ACTIVE';

  @override
  String toString() => 'Geofence($geofenceId, ${status ?? '?'})';
}

/// La posición de un dispositivo, tal como se envía al servicio.
@immutable
class DevicePositionUpdate {
  /// Crea la actualización.
  const DevicePositionUpdate({
    required this.deviceId,
    required this.position,
    required this.sampleTime,
    this.horizontalAccuracyMeters,
    this.properties = const <String, String>{},
  });

  /// El identificador del dispositivo.
  ///
  /// Para geovallas **no hace falta que exista un rastreador asociado**: es
  /// una cadena libre.
  final String deviceId;

  /// Dónde estaba.
  final LatLng position;

  /// Cuándo se tomó la medida.
  ///
  /// **No es la hora de envío.** Mandar la hora actual en vez de la del GPS
  /// desordena el histórico y engaña al filtrado por tiempo del rastreador.
  final DateTime sampleTime;

  /// La precisión horizontal del GPS en metros.
  ///
  /// Con un rastreador en modo `AccuracyBased`, este valor decide si la
  /// posición se guarda: no darlo equivale a decir «precisión perfecta», y
  /// entonces se guarda todo.
  final double? horizontalAccuracyMeters;

  /// Hasta tres propiedades que viajan con la posición.
  final Map<String, String> properties;

  /// La actualización en la forma que espera el servicio.
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

/// Un error por elemento en una operación por lotes.
///
/// Existe porque estas operaciones **no fallan enteras**: procesan lo que
/// pueden y devuelven los fallos uno a uno. Ignorar esta lista es perder
/// posiciones sin enterarse.
@immutable
class BatchItemError {
  /// Crea el error.
  const BatchItemError({
    required this.itemId,
    this.code,
    this.message,
    this.sampleTime,
  });

  /// Lee el error de la respuesta del servicio.
  factory BatchItemError.fromJson(Map<String, dynamic> json, String idField) {
    final error = Json.object(json, 'Error');
    return BatchItemError(
      itemId: Json.string(json, idField) ?? '',
      code: Json.string(error, 'Code'),
      message: Json.string(error, 'Message'),
      sampleTime: Json.dateTime(json, 'SampleTime'),
    );
  }

  /// El identificador del elemento que falló.
  final String itemId;

  /// El código de AWS: `AccessDeniedError`, `ValidationError`…
  final String? code;

  /// La explicación.
  final String? message;

  /// La hora de la muestra, en los errores de posición.
  final DateTime? sampleTime;

  @override
  String toString() => 'BatchItemError($itemId, ${code ?? '?'}): $message';
}

/// El resultado de una operación por lotes.
@immutable
class BatchResult {
  /// Crea el resultado.
  const BatchResult({
    required this.total,
    this.errors = const <BatchItemError>[],
  });

  /// Cuántos elementos se enviaron.
  final int total;

  /// Los que fallaron. **Hay que mirarla**: la operación devuelve 200 aunque
  /// falle la mitad.
  final List<BatchItemError> errors;

  /// Cuántos salieron bien.
  int get succeeded => total - errors.length;

  /// ¿Salió todo bien?
  bool get isCompleteSuccess => errors.isEmpty;

  @override
  String toString() => 'BatchResult($succeeded/$total)';
}

/// Qué le va a pasar a un dispositivo respecto a una geovalla.
enum ForecastedEventType {
  /// Va a entrar en la zona.
  enter('ENTER'),

  /// Va a salir de la zona.
  exit('EXIT'),

  /// Está dentro y va a seguir dentro.
  idle('IDLE');

  const ForecastedEventType(this.wireName);

  /// El literal que devuelve el servicio.
  final String wireName;
}

/// Un evento de geovalla **que todavía no ha pasado**.
///
/// Esto es lo que hace única a `forecastGeofenceEvents`: no dice dónde está el
/// dispositivo, dice **dónde va a estar** si mantiene la velocidad. Para una
/// app de rastreo es la diferencia entre avisar cuando el vehículo ya salió de
/// la zona permitida y avisar seis minutos antes.
@immutable
class ForecastedGeofenceEvent {
  /// Crea el evento previsto.
  const ForecastedGeofenceEvent({
    required this.eventId,
    required this.geofenceId,
    required this.eventType,
    required this.isDeviceInGeofence,
    required this.nearestDistance,
    this.forecastedBreachTime,
    this.geofenceProperties = const <String, String>{},
  });

  /// Lee el evento de la respuesta del servicio.
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

  /// El identificador del evento previsto.
  final String eventId;

  /// La geovalla implicada.
  final String geofenceId;

  /// Qué va a pasar.
  final ForecastedEventType eventType;

  /// ¿Está ahora dentro de la geovalla?
  final bool isDeviceInGeofence;

  /// Distancia al borde más cercano.
  ///
  /// ⚠️ **En la unidad que se pidió**, y el valor por defecto de la API es
  /// **kilómetros**, no metros. Es la única magnitud de todo el paquete que no
  /// llega en metros, y no por decisión propia: esta familia de operaciones es
  /// de la generación anterior, la que sí tiene `DistanceUnit`.
  ///
  /// `GeofencingClient.forecastGeofenceEvents` pide kilómetros y lo convierte,
  /// así que **este campo sí llega en metros**. Se documenta el detalle porque
  /// quien lea la respuesta cruda de AWS verá otra cosa.
  final double nearestDistance;

  /// Cuándo se prevé que cruce el borde.
  final DateTime? forecastedBreachTime;

  /// Las propiedades de la geovalla, para no tener que consultarla.
  final Map<String, String> geofenceProperties;

  /// Cuánto falta para que cruce, desde ahora.
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

/// La respuesta de `forecastGeofenceEvents`.
@immutable
class ForecastGeofenceEventsResponse {
  /// Crea la respuesta.
  const ForecastGeofenceEventsResponse({
    this.events = const <ForecastedGeofenceEvent>[],
    this.nextToken,
  });

  /// Lee la respuesta del servicio.
  factory ForecastGeofenceEventsResponse.fromJson(Map<String, dynamic> json) =>
      ForecastGeofenceEventsResponse(
        events: Json.objects(
          json,
          'ForecastedEvents',
        ).map(ForecastedGeofenceEvent.fromJson).toList(growable: false),
        nextToken: Json.string(json, 'NextToken'),
      );

  /// Los eventos previstos.
  final List<ForecastedGeofenceEvent> events;

  /// El testigo de la siguiente página.
  final String? nextToken;

  /// Solo los que suponen cruzar un borde: entrar o salir.
  ///
  /// Es lo que hay que enseñar. Los [ForecastedEventType.idle] dicen «sigue
  /// donde estaba», que casi nunca es una alerta.
  List<ForecastedGeofenceEvent> get breaches => events
      .where((e) => e.eventType != ForecastedEventType.idle)
      .toList(growable: false);

  @override
  String toString() =>
      'ForecastGeofenceEventsResponse(${events.length} evento(s), '
      '${breaches.length} cruce(s))';
}

/// Una colección de geovallas.
@immutable
class GeofenceCollection {
  /// Crea la colección.
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

  /// Lee la colección de la respuesta del servicio.
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

  /// El nombre, que es su identificador.
  final String collectionName;

  /// El ARN completo. Es lo que hace falta para enlazarla con un rastreador.
  final String? collectionArn;

  /// La descripción.
  final String? description;

  /// Cuántas geovallas tiene.
  final int? geofenceCount;

  /// La clave de KMS con la que se cifra, si se configuró.
  final String? kmsKeyId;

  /// Cuándo se creó.
  final DateTime? createTime;

  /// Cuándo se cambió.
  final DateTime? updateTime;

  /// Las etiquetas de AWS.
  final Map<String, String> tags;

  @override
  String toString() => 'GeofenceCollection($collectionName)';
}

/// Una página de geovallas o de colecciones.
@immutable
class GeofencePage<T> {
  /// Crea la página.
  const GeofencePage({required this.items, this.nextToken});

  /// Los elementos de esta página.
  final List<T> items;

  /// El testigo para la siguiente, o `null` si no hay más.
  final String? nextToken;

  /// ¿Hay más páginas?
  bool get hasMore => nextToken != null;

  @override
  String toString() =>
      'GeofencePage(${items.length}${hasMore ? ', hay más' : ''})';
}
