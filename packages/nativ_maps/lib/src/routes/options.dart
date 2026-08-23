// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/enums.dart';

/// Datos extra que se pueden pedir por tramo de ruta.
///
/// Cada uno engorda la respuesta. [tolls] y [summary] son los que casi siempre
/// compensan; [travelStepInstructions] multiplica el tamaño por varias veces y
/// solo hace falta si de verdad se va a navegar.
enum RouteFeature {
  /// Altitud a lo largo del trazado.
  elevation('Elevation'),

  /// Obras, accidentes y cortes.
  incidents('Incidents'),

  /// Los puntos de paso por los que se pasa sin parar.
  passThroughWaypoints('PassThroughWaypoints'),

  /// El resumen de distancia y duración del tramo.
  ///
  /// Sin esto, `Summary.Overview` puede no venir y el tramo aparece con
  /// distancia y duración a cero.
  summary('Summary'),

  /// Los sistemas de peaje por los que pasa.
  tollSystems('TollSystems'),

  /// **Los peajes con su importe.** Esto es lo que Google no da.
  tolls('Tolls'),

  /// El texto de cada maniobra.
  travelStepInstructions('TravelStepInstructions'),

  /// Los tipos de vía para camión.
  truckRoadTypes('TruckRoadTypes'),

  /// La duración típica del tramo, sin tráfico.
  ///
  /// Comparada con la duración real da el retraso por tráfico, que es lo que
  /// se enseña como «10 min más de lo habitual».
  typicalDuration('TypicalDuration'),

  /// Zonas de bajas emisiones y similares.
  zones('Zones');

  const RouteFeature(this.wireName);

  /// El literal que viaja en el JSON.
  final String wireName;
}

/// Qué evitar al calcular la ruta.
///
/// Ninguna de estas es una prohibición absoluta: si no hay alternativa, el
/// servicio pasa igual y lo dice en `RouteResponse.notices`. Es lo correcto —
/// una ruta imposible no le sirve a nadie— pero hay que leer los avisos si la
/// evitación era obligatoria de verdad.
@immutable
class RouteAvoidance {
  /// Crea el conjunto de evitaciones.
  const RouteAvoidance({
    this.tollRoads = false,
    this.tollTransponders = false,
    this.ferries = false,
    this.tunnels = false,
    this.uTurns = false,
    this.dirtRoads = false,
    this.controlledAccessHighways = false,
    this.seasonalClosure = false,
    this.tollGates = false,
  });

  /// Evitar vías de peaje.
  final bool tollRoads;

  /// Evitar vías que solo admiten transpondedor.
  final bool tollTransponders;

  /// Evitar ferris. Importante en rutas costeras: un ferri añade horas de
  /// espera que no se ven en la distancia.
  final bool ferries;

  /// Evitar túneles. Es la evitación que importa con mercancías peligrosas.
  final bool tunnels;

  /// Evitar cambios de sentido.
  final bool uTurns;

  /// Evitar caminos sin asfaltar.
  final bool dirtRoads;

  /// Evitar autopistas de acceso controlado.
  final bool controlledAccessHighways;

  /// Evitar vías con cierre estacional.
  final bool seasonalClosure;

  /// Evitar barreras de peaje.
  final bool tollGates;

  /// ¿No se pidió evitar nada?
  bool get isEmpty =>
      !tollRoads &&
      !tollTransponders &&
      !ferries &&
      !tunnels &&
      !uTurns &&
      !dirtRoads &&
      !controlledAccessHighways &&
      !seasonalClosure &&
      !tollGates;

  /// Las evitaciones en la forma que espera el servicio.
  Map<String, dynamic> toJson() => <String, dynamic>{
    if (tollRoads) 'TollRoads': true,
    if (tollTransponders) 'TollTransponders': true,
    if (ferries) 'Ferries': true,
    if (tunnels) 'Tunnels': true,
    if (uTurns) 'UTurns': true,
    if (dirtRoads) 'DirtRoads': true,
    if (controlledAccessHighways) 'ControlledAccessHighways': true,
    if (seasonalClosure) 'SeasonalClosure': true,
    if (tollGates) 'TollGates': true,
  };
}

/// Las características del vehículo, que cambian la ruta.
///
/// El caso que más se nota es el camión: sus dimensiones y su peso hacen que
/// una ruta correcta para un coche sea imposible. Un puente con gálibo de
/// 3,5 m no aparece como cortado en el mapa — simplemente el camión no cabe.
@immutable
class TravelModeOptions {
  /// Opciones de camión.
  const TravelModeOptions.truck({
    this.grossWeightKg,
    this.heightCm,
    this.lengthCm,
    this.widthCm,
    this.axleCount,
    this.trailerCount,
    this.hazardousCargos = const <String>[],
    this.tunnelRestrictionCode,
    this.truckType,
    this.engineType,
    this.occupancy,
    this.licensePlateLastCharacter,
  }) : _kind = TravelMode.truck;

  /// Opciones de coche.
  const TravelModeOptions.car({
    this.engineType,
    this.occupancy,
    this.licensePlateLastCharacter,
  }) : _kind = TravelMode.car,
       grossWeightKg = null,
       heightCm = null,
       lengthCm = null,
       widthCm = null,
       axleCount = null,
       trailerCount = null,
       hazardousCargos = const <String>[],
       tunnelRestrictionCode = null,
       truckType = null;

  /// Opciones de moto.
  const TravelModeOptions.scooter({
    this.engineType,
    this.licensePlateLastCharacter,
  }) : _kind = TravelMode.scooter,
       grossWeightKg = null,
       heightCm = null,
       lengthCm = null,
       widthCm = null,
       axleCount = null,
       trailerCount = null,
       hazardousCargos = const <String>[],
       tunnelRestrictionCode = null,
       truckType = null,
       occupancy = null;

  final TravelMode _kind;

  /// Peso bruto en kilogramos.
  final int? grossWeightKg;

  /// Altura en centímetros. La que decide si cabe bajo un puente.
  final int? heightCm;

  /// Longitud en centímetros.
  final int? lengthCm;

  /// Anchura en centímetros.
  final int? widthCm;

  /// Número de ejes. Determina la tarifa de peaje.
  final int? axleCount;

  /// Número de remolques.
  final int? trailerCount;

  /// Mercancías peligrosas: `Explosive`, `Gas`, `Flammable`, `Combustible`,
  /// `Organic`, `Poison`, `Radioactive`, `Corrosive`, `PoisonousInhalation`,
  /// `HarmfulToWater`, `Other`.
  final List<String> hazardousCargos;

  /// Código de restricción de túneles, de `B` a `E`.
  final String? tunnelRestrictionCode;

  /// Clase de camión: `StraightTruck`, `Tractor`, `Trailer`.
  final String? truckType;

  /// Motorización: `Electric`, `Diesel`, `Gasoline`. Cambia las zonas de bajas
  /// emisiones en las que se puede entrar.
  final String? engineType;

  /// Ocupantes. Da acceso a los carriles de alta ocupación.
  final int? occupancy;

  /// Última cifra de la matrícula.
  ///
  /// Es lo que hace falta para el «pico y placa» de Quito y las restricciones
  /// equivalentes de otras ciudades, que dependen de esa cifra y del día de la
  /// semana.
  final String? licensePlateLastCharacter;

  /// Las opciones en la forma que espera el servicio para [travelMode].
  ///
  /// Se anidan bajo la clave del modo (`Truck`, `Car`, `Scooter`), que es como
  /// las quiere la API. Si el modo no coincide con el del constructor, se
  /// devuelve un mapa vacío en vez de enviar opciones de camión bajo `Car`,
  /// que provocaría un `400`.
  Map<String, dynamic> toJson(TravelMode travelMode) {
    if (travelMode != _kind) return const <String, dynamic>{};

    final options = <String, dynamic>{
      if (grossWeightKg != null) 'GrossWeight': grossWeightKg,
      if (heightCm != null) 'Height': heightCm,
      if (lengthCm != null) 'Length': lengthCm,
      if (widthCm != null) 'Width': widthCm,
      if (axleCount != null) 'AxleCount': axleCount,
      if (trailerCount != null) 'TrailerCount': trailerCount,
      if (hazardousCargos.isNotEmpty) 'HazardousCargos': hazardousCargos,
      if (tunnelRestrictionCode != null)
        'TunnelRestrictionCode': tunnelRestrictionCode,
      if (truckType != null) 'TruckType': truckType,
      if (engineType != null) 'EngineType': engineType,
      if (occupancy != null) 'Occupancy': occupancy,
      if (licensePlateLastCharacter != null)
        'LicensePlate': <String, dynamic>{
          'LastCharacter': licensePlateLastCharacter,
        },
    };
    if (options.isEmpty) return const <String, dynamic>{};
    return <String, dynamic>{_kind.wireName: options};
  }
}

/// Los umbrales de una isócrona: por tiempo, por distancia o los dos.
///
/// **Cada umbral se cobra aparte**, y el máximo es cinco. Pedir cinco umbrales
/// en una llamada es más cómodo que hacer cinco llamadas, pero cuesta lo
/// mismo. Por eso [count] existe: es lo que el presupuesto va a cargar.
@immutable
class Thresholds {
  /// Crea los umbrales.
  const Thresholds({
    this.time = const <Duration>[],
    this.distanceMeters = const <double>[],
  });

  /// Umbrales por tiempo. El caso normal: «lo alcanzable en 8 minutos».
  factory Thresholds.time(List<Duration> durations) =>
      Thresholds(time: durations);

  /// Umbrales por distancia recorrida **por carretera**, no en línea recta.
  factory Thresholds.distance(List<double> meters) =>
      Thresholds(distanceMeters: meters);

  /// Los umbrales de tiempo.
  final List<Duration> time;

  /// Los umbrales de distancia, en metros.
  final List<double> distanceMeters;

  /// Cuántos umbrales hay en total. **Es lo que se factura.**
  int get count => time.length + distanceMeters.length;

  /// Los umbrales en la forma que espera el servicio.
  Map<String, dynamic> toJson() => <String, dynamic>{
    if (time.isNotEmpty)
      'Time': time.map((d) => d.inSeconds).toList(growable: false),
    if (distanceMeters.isNotEmpty)
      'Distance': distanceMeters.map((m) => m.round()).toList(growable: false),
  };

  @override
  String toString() => 'Thresholds($count umbral(es))';
}

/// Cuánto detalle tiene el polígono de una isócrona.
///
/// ## Por qué esto no es opcional en la práctica
///
/// Sin límite, el polígono de una isócrona de treinta minutos trae varios
/// miles de vértices. El mapa lo acepta, lo intenta dibujar y la interfaz deja
/// de responder — en un móvil de gama media, varios segundos por cada
/// repintado. No es un problema de precisión: a la escala en la que se ve la
/// isócrona, trescientos puntos y tres mil se ven exactamente igual.
///
/// Por eso el valor por defecto de `calculateIsolines` ya trae `maxPoints`
/// puesto, en vez de dejarlo sin poner y documentar el riesgo.
@immutable
class IsolineGranularity {
  /// Crea la granularidad.
  const IsolineGranularity({this.maxPoints, this.maxResolutionMeters});

  /// Vértices máximos del polígono. Trescientos van bien para pintar.
  final int? maxPoints;

  /// Resolución máxima en metros: la distancia mínima entre dos vértices.
  final int? maxResolutionMeters;

  /// La granularidad en la forma que espera el servicio.
  Map<String, dynamic> toJson() => <String, dynamic>{
    if (maxPoints != null) 'MaxPoints': maxPoints,
    if (maxResolutionMeters != null) 'MaxResolution': maxResolutionMeters,
  };
}

/// Los descansos obligatorios del conductor, para `optimizeWaypoints`.
///
/// Sin esto, la optimización planifica jornadas de catorce horas seguidas.
/// Salen preciosas en el mapa y son ilegales.
@immutable
class DriverOptions {
  /// Crea las opciones del conductor.
  const DriverOptions({this.restProfile, this.treatServiceTimeAs});

  /// El perfil normativo de descansos, p. ej. `EU` o `US`.
  final String? restProfile;

  /// Si el tiempo de servicio cuenta como descanso o como trabajo:
  /// `Rest` o `Work`.
  final String? treatServiceTimeAs;

  /// Las opciones en la forma que espera el servicio.
  Map<String, dynamic> toJson() => <String, dynamic>{
    if (restProfile != null)
      'RestProfile': <String, dynamic>{'Profile': restProfile},
    if (treatServiceTimeAs != null) 'TreatServiceTimeAs': treatServiceTimeAs,
  };
}
