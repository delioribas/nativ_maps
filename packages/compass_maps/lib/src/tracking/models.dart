// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:compass_maps/src/core/json.dart';
import 'package:compass_maps/src/core/lat_lng.dart';
import 'package:meta/meta.dart';

/// La posición de un dispositivo, tal como la devuelve el servicio.
@immutable
class DevicePosition {
  /// Crea la posición.
  const DevicePosition({
    required this.position,
    required this.sampleTime,
    this.deviceId,
    this.receivedTime,
    this.horizontalAccuracyMeters,
    this.properties = const <String, String>{},
  });

  /// Lee la posición de la respuesta del servicio.
  ///
  /// Lanza [FormatException] si la coordenada no se puede leer: una posición
  /// de dispositivo **es** el dato, y sustituirla por `LatLng(0, 0)` pondría
  /// el vehículo en el golfo de Guinea con toda la apariencia de ser correcto.
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

  /// Dónde estaba.
  final LatLng position;

  /// Cuándo lo midió el GPS.
  final DateTime sampleTime;

  /// Qué dispositivo era.
  final String? deviceId;

  /// Cuándo lo recibió AWS.
  ///
  /// La diferencia con [sampleTime] es **el retraso de la red**, y en un
  /// localizador con cobertura mala puede ser de minutos. Enseñar
  /// [receivedTime] como «última posición» hace creer que el vehículo estaba
  /// ahí hace un momento cuando la medida es de hace un cuarto de hora.
  final DateTime? receivedTime;

  /// La precisión horizontal declarada, en metros.
  final double? horizontalAccuracyMeters;

  /// Las propiedades que viajaron con la posición.
  final Map<String, String> properties;

  /// Cuánto tardó en llegar la posición desde que se midió.
  Duration? get networkDelay {
    final recibida = receivedTime;
    if (recibida == null) return null;
    final retraso = recibida.difference(sampleTime);
    return retraso.isNegative ? Duration.zero : retraso;
  }

  /// Cuánto hace que se midió.
  Duration get age => DateTime.now().toUtc().difference(sampleTime.toUtc());

  /// ¿Es lo bastante reciente para tratarla como «dónde está ahora»?
  ///
  /// Un vehículo cuya última posición es de hace media hora **no está** ahí:
  /// está en algún punto de un círculo de veinte kilómetros. Para dibujar ese
  /// círculo está `RoutesClient.calculateIsolines`.
  bool isFresh({Duration maxAge = const Duration(minutes: 5)}) => age <= maxAge;

  @override
  String toString() =>
      'DevicePosition(${deviceId ?? '?'} @ $position, '
      'hace ${age.inMinutes} min)';
}

/// Cómo decide el rastreador qué posiciones guarda.
///
/// ## Por qué esto es lo primero que hay que elegir
///
/// Es lo que separa una factura razonable de una desagradable, y lo que decide
/// si el histórico sirve. Un localizador que reporta cada cinco segundos y un
/// rastreador en [timeBased] guardan **una de cada seis** posiciones.
enum PositionFiltering {
  /// Una posición cada 30 segundos como mucho. **El valor por defecto.**
  ///
  /// Con un vehículo parado guarda igual, así que el histórico se llena de
  /// puntos idénticos.
  timeBased('TimeBased'),

  /// Solo si se movió más de 30 metros.
  ///
  /// **Es el correcto para rastreo de vehículos**: un vehículo parado deja de
  /// generar puntos, y el histórico de un día pasa de miles de posiciones a
  /// cientos, sin perder nada del recorrido.
  distanceBased('DistanceBased'),

  /// Solo si se movió más que el margen de error del GPS.
  ///
  /// El más conservador: con dos medidas de precisión 5 m y 10 m, descarta la
  /// segunda si el movimiento fue menor de 15 m. Evita el «temblor» de un
  /// vehículo parado entre edificios altos.
  ///
  /// Exige mandar `horizontalAccuracyMeters` en cada posición; sin él, el
  /// servicio asume precisión perfecta y guarda todo.
  accuracyBased('AccuracyBased');

  const PositionFiltering(this.wireName);

  /// El literal que viaja en el JSON.
  final String wireName;
}

/// Un rastreador: el recurso donde se guardan las posiciones.
@immutable
class Tracker {
  /// Crea el rastreador.
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

  /// Lee el rastreador de la respuesta del servicio.
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

  /// El nombre, que es su identificador.
  final String trackerName;

  /// El ARN completo.
  final String? trackerArn;

  /// La descripción.
  final String? description;

  /// Qué posiciones guarda. Ver [PositionFiltering].
  final PositionFiltering? positionFiltering;

  /// ¿Publica los cambios de posición en EventBridge?
  ///
  /// Es distinto de los eventos de geovalla: esto emite un evento por **cada
  /// posición guardada**, y con una flota grande son muchos.
  final bool? eventBridgeEnabled;

  /// La clave de KMS con la que se cifra el histórico.
  final String? kmsKeyId;

  /// Cuándo se creó.
  final DateTime? createTime;

  /// Cuándo se cambió.
  final DateTime? updateTime;

  /// Las etiquetas de AWS.
  final Map<String, String> tags;

  @override
  String toString() => 'Tracker($trackerName)';
}

/// El resultado de comprobar si una posición es de fiar.
///
/// Lo devuelve `TrackingClient.verifyDevicePosition`, y responde a una
/// pregunta que ninguna otra operación responde: **¿me está mintiendo el
/// dispositivo?**
@immutable
class PositionVerification {
  /// Crea el resultado.
  const PositionVerification({
    required this.deviceId,
    required this.proxyDetected,
    this.inferredPosition,
    this.deviationMeters,
    this.inferredAccuracyMeters,
    this.sampleTime,
    this.receivedTime,
  });

  /// Lee el resultado de la respuesta del servicio.
  ///
  /// La desviación llega en la unidad pedida —kilómetros por defecto—;
  /// `TrackingClient` la convierte a metros antes de construir esto.
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

  /// Qué dispositivo se comprobó.
  final String deviceId;

  /// **¿La posición llegó a través de un proxy o una VPN?**
  ///
  /// Es la señal más fuerte de que alguien está falseando la ubicación: un
  /// localizador honesto conectado por la red móvil no pasa por un proxy.
  final bool proxyDetected;

  /// Dónde cree el servicio que estaba de verdad, deducido de la IP, las
  /// antenas de telefonía y los puntos Wi-Fi vistos.
  final LatLng? inferredPosition;

  /// Cuánto se separa la posición declarada de la deducida, **en metros**.
  ///
  /// Una desviación de decenas de metros es normal. Una de decenas de
  /// kilómetros con `proxyDetected` en `true` es alguien mintiendo.
  final double? deviationMeters;

  /// La precisión de la posición deducida.
  final double? inferredAccuracyMeters;

  /// Cuándo se midió.
  final DateTime? sampleTime;

  /// Cuándo llegó.
  final DateTime? receivedTime;

  /// ¿Hay motivos para desconfiar de esta posición?
  ///
  /// El umbral por defecto —10 km— es deliberadamente generoso: la
  /// localización por antenas de telefonía tiene un error de kilómetros en
  /// zona rural, y un umbral apretado marcaría como sospechoso a medio campo.
  bool isSuspicious({double maxDeviationMeters = 10000}) =>
      proxyDetected ||
      (deviationMeters != null && deviationMeters! > maxDeviationMeters);

  @override
  String toString() =>
      'PositionVerification($deviceId, '
      'proxy: $proxyDetected, desvío: ${deviationMeters?.round()} m)';
}

/// Un punto Wi-Fi visto por el dispositivo, para verificar su posición.
@immutable
class WiFiAccessPoint {
  /// Crea el punto.
  const WiFiAccessPoint({required this.macAddress, required this.rss});

  /// La MAC del punto de acceso.
  final String macAddress;

  /// La potencia de la señal recibida, en dBm. Es negativa.
  final int rss;

  /// El punto en la forma que espera el servicio.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'MacAddress': macAddress,
    'Rss': rss,
  };
}

/// Una página de posiciones o de rastreadores.
@immutable
class TrackingPage<T> {
  /// Crea la página.
  const TrackingPage({required this.items, this.nextToken});

  /// Los elementos.
  final List<T> items;

  /// El testigo de la siguiente página.
  final String? nextToken;

  /// ¿Hay más?
  bool get hasMore => nextToken != null;

  @override
  String toString() =>
      'TrackingPage(${items.length}${hasMore ? ', hay más' : ''})';
}
