// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

/// Los tres servicios de Amazon Location v2.
///
/// Existe por una razón muy concreta: **cada uno firma con un nombre
/// distinto**. Equivocarse produce un `403` idéntico al de una clave inválida,
/// y se pierde una tarde buscando en el sitio equivocado. Al ser un enum, el
/// nombre no se puede escribir mal.
enum AlsService {
  /// Búsqueda, geocodificación y fichas de lugar.
  places('geo-places', 'places'),

  /// Rutas, matrices, isócronas, pegado a carretera y optimización.
  routes('geo-routes', 'routes'),

  /// Estilos, teselas y mapas estáticos.
  maps('geo-maps', 'maps'),

  /// Geovallas: evaluar posiciones contra zonas y predecir entradas y salidas.
  ///
  /// **Firma con `geo`, no con `geo-geofencing`.** Es de la generación
  /// anterior, la que sigue usando recursos creados en la consola, y AWS no ha
  /// sacado una v2 de ella. El nombre de firma es el del servicio heredado.
  geofencing('geo', 'geofencing'),

  /// El plano de control de las geovallas: crear, borrar y listar colecciones.
  ///
  /// **Va a otro host**: `cp.geofencing.geo.…`, con el prefijo `cp.` delante.
  /// Mandar una operación de control al host de datos da un `404` que parece
  /// una ruta mal escrita.
  geofencingControl('geo', 'cp.geofencing'),

  /// Rastreo de dispositivos: posiciones, histórico y verificación.
  ///
  /// Firma con `geo`, como [geofencing].
  tracking('geo', 'tracking'),

  /// El plano de control del rastreo: crear, borrar y listar rastreadores.
  ///
  /// También con el prefijo `cp.`.
  trackingControl('geo', 'cp.tracking');

  const AlsService(this.signingName, this.hostPrefix);

  /// El nombre con el que SigV4 firma las peticiones a este servicio.
  ///
  /// Hay **dos generaciones y no comparten nombre**:
  ///
  /// - Places, Routes y Maps v2 firman con `geo-places`, `geo-routes` y
  ///   `geo-maps`.
  /// - Geofencing y Tracking firman con `geo` a secas, porque son de la
  ///   generación anterior.
  ///
  /// Equivocarse da un `403` idéntico al de una clave inválida. Al ser un
  /// enum, el nombre no se puede escribir mal.
  final String signingName;

  /// El prefijo del host: `{hostPrefix}.geo.{región}.amazonaws.com`.
  ///
  /// El prefijo `cp.` de los planos de control forma parte de esto:
  /// `cp.geofencing.geo.us-east-1.amazonaws.com`.
  final String hostPrefix;

  /// ¿Es de la generación v2, la que no necesita crear recursos?
  ///
  /// Importa para dos cosas: la generación v2 acepta clave de API y la
  /// anterior **no** —solo SigV4—, y la anterior sí usa `DistanceUnit`,
  /// que en v2 provoca un `400`.
  bool get isV2 => this == places || this == routes || this == maps;

  /// ¿Admite autenticación con clave de API?
  ///
  /// **Solo la generación v2.** Las claves de API de Amazon Location cubren
  /// Places, Routes y Maps; Geofencing y Tracking exigen SigV4, sea con un
  /// proxy o con `nativ_maps_sigv4`. Intentarlo con clave da un `403`.
  bool get supportsApiKey => isV2;

  /// El host del servicio en [region].
  ///
  /// Por ejemplo, `places.geo.us-east-1.amazonaws.com`.
  String hostFor(String region) => '$hostPrefix.geo.$region.amazonaws.com';
}

/// Modo de viaje para las operaciones de Routes.
///
/// El nombre de la moto es el que más confusión causa: en la generación
/// anterior era `Motorcycle`; en v2 se llama [scooter], y la documentación de
/// AWS dice explícitamente que **también cubre las motocicletas**, no solo los
/// ciclomotores.
enum TravelMode {
  /// Coche o furgoneta. El valor por defecto de todas las operaciones.
  car('Car'),

  /// Camión. Admite dimensiones, peso y mercancías peligrosas en
  /// `TruckOptions`, que cambian la ruta por restricciones de vía.
  truck('Truck'),

  /// A pie. Ignora sentidos únicos y usa aceras y pasos.
  pedestrian('Pedestrian'),

  /// Moto, ciclomotor o motocicleta.
  scooter('Scooter');

  const TravelMode(this.wireName);

  /// El literal que viaja en el JSON de la petición.
  final String wireName;
}

/// Catálogo de estilos de mapa de Maps v2.
///
/// En la generación anterior había que crear un recurso «Map» en la consola y
/// el nombre lo elegías tú, así que un nombre mal escrito solo se descubría en
/// tiempo de ejecución. En v2 el catálogo es fijo y no se crea nada: por eso
/// esto es un enum y no un `String`.
enum MapStyle {
  /// Cartografía completa a color. El estilo por defecto.
  standard('Standard'),

  /// Un solo tono, pensado como fondo bajo datos propios.
  monochrome('Monochrome'),

  /// Satélite con etiquetas y vías encima.
  hybrid('Hybrid'),

  /// Solo imagen de satélite, sin etiquetas.
  satellite('Satellite');

  const MapStyle(this.wireName);

  /// El literal que viaja en la URL.
  final String wireName;
}

/// Tono del mapa.
///
/// Sustituye a la pareja de recursos «claro» y «oscuro» que había que crear a
/// mano en la generación anterior y mantener sincronizados. Ahora es el mismo
/// estilo con otro parámetro, y **lo renderiza el servidor**: no es un filtro
/// de color sobre teselas claras, así que las etiquetas siguen siendo legibles.
enum MapColorScheme {
  /// Fondo claro. Es el valor por defecto del servicio.
  light('Light'),

  /// Fondo oscuro.
  dark('Dark');

  const MapColorScheme(this.wireName);

  /// El literal que viaja en la URL.
  final String wireName;
}

/// Si el resultado se va a guardar en tu propia infraestructura.
///
/// No es un detalle técnico ni una optimización: la documentación de AWS dice
/// que **guardar un resultado obtenido con [singleUse] incumple las
/// condiciones del servicio**. [storage] se factura más caro.
///
/// La regla práctica: una dirección que se escribe en la ficha de un
/// cliente es [storage]; una que solo se enseña en pantalla mientras se
/// elige, es [singleUse].
enum IntendedUse {
  /// El resultado se muestra y se descarta. Más barato.
  singleUse('SingleUse'),

  /// El resultado se guarda en tu base de datos. Más caro, y obligatorio si
  /// lo vas a persistir.
  storage('Storage');

  const IntendedUse(this.wireName);

  /// El literal que viaja en el JSON o en la URL.
  final String wireName;
}

/// Qué se optimiza al calcular una ruta.
enum RouteOptimization {
  /// La ruta más rápida en tiempo. El valor por defecto.
  fastestRoute('FastestRoute'),

  /// La ruta más corta en distancia, aunque tarde más.
  shortestRoute('ShortestRoute');

  const RouteOptimization(this.wireName);

  /// El literal que viaja en el JSON.
  final String wireName;
}

/// Cómo se usa la información de tráfico al calcular.
enum TrafficUsage {
  /// Se tiene en cuenta el tráfico en tiempo real. Por defecto.
  useTrafficData('UseTrafficData'),

  /// Se ignora. Da resultados reproducibles, útil para comparar.
  ignoreTrafficData('IgnoreTrafficData');

  const TrafficUsage(this.wireName);

  /// El literal que viaja en el JSON.
  final String wireName;
}

/// Formato en el que llega la geometría de una ruta o una isócrona.
enum GeometryFormat {
  /// Lista de coordenadas sin comprimir (`LineString`). Más pesada por la red,
  /// pero no hay nada que decodificar.
  simple('Simple'),

  /// Cadena comprimida en el formato **Flexible Polyline de HERE**, que no
  /// es el de Google. Mucho más ligera; la decodifica
  /// `decodeFlexiblePolyline`.
  flexiblePolyline('FlexiblePolyline');

  const GeometryFormat(this.wireName);

  /// El literal que viaja en el JSON.
  final String wireName;
}

/// Detalle de las indicaciones paso a paso de una ruta.
enum TravelStepType {
  /// Una indicación por maniobra: «gire a la derecha en…».
  turnByTurn('TurnByTurn'),

  /// Una indicación por tramo, sin maniobras intermedias.
  general('General'),

  /// Sin indicaciones. Es lo más barato de transmitir cuando solo se quiere
  /// la línea para pintarla.
  none('Default');

  const TravelStepType(this.wireName);

  /// El literal que viaja en el JSON.
  final String wireName;
}

/// Qué se optimiza al reordenar las paradas de `optimizeWaypoints`.
enum WaypointOptimization {
  /// Minimiza el tiempo total del recorrido.
  fastestRoute('FastestRoute'),

  /// Minimiza la distancia total.
  shortestRoute('ShortestRoute');

  const WaypointOptimization(this.wireName);

  /// El literal que viaja en el JSON.
  final String wireName;
}

// ═══════════════════════════════════════════════════════════════════════════
//  Rasgos del descriptor de estilo (Maps v2)
//
//  Estos siete parámetros son lo que en `google_maps_flutter` no existe o
//  requiere una capa aparte: el tráfico, el relieve, los edificios en 3D y la
//  densidad de puntos de interés los pinta el servidor dentro del mismo
//  estilo, sin una segunda petición ni una capa superpuesta.
// ═══════════════════════════════════════════════════════════════════════════

/// Cómo se dibujan los edificios.
enum MapBuildings {
  /// Edificios extruidos en tres dimensiones.
  ///
  /// Solo vale con [MapStyle.standard] y [MapStyle.monochrome].
  buildings3d('Buildings3D');

  const MapBuildings(this.wireName);

  /// El literal que viaja en la URL.
  final String wireName;
}

/// Cómo se dibuja el relieve del terreno.
enum MapTerrain {
  /// Sombreado del relieve. Solo con [MapStyle.standard] y
  /// [MapStyle.monochrome].
  hillshade('Hillshade'),

  /// Modelo tridimensional del terreno.
  terrain3d('Terrain3D');

  const MapTerrain(this.wireName);

  /// El literal que viaja en la URL.
  final String wireName;
}

/// Densidad de las curvas de nivel.
///
/// No disponible en `ap-southeast-1` ni `ap-southeast-5` (GrabMaps), ni con
/// [MapStyle.satellite].
enum MapContourDensity {
  /// Pocas curvas, solo las principales.
  low('Low'),

  /// Densidad intermedia.
  medium('Medium'),

  /// Todas las curvas disponibles.
  high('High');

  const MapContourDensity(this.wireName);

  /// El literal que viaja en la URL.
  final String wireName;
}

/// Tráfico en tiempo real dibujado dentro del estilo.
///
/// Este es el equivalente real de `trafficEnabled` de `google_maps_flutter`:
/// no es una capa superpuesta que se pide aparte, es el propio servidor
/// coloreando las vías al generar el estilo.
enum MapTraffic {
  /// Congestión más incidencias (obras, accidentes, cortes).
  all('All'),

  /// Solo el color de congestión de las vías.
  congestion('Congestion');

  const MapTraffic(this.wireName);

  /// El literal que viaja en la URL.
  final String wireName;
}

/// Cuántos puntos de interés se dibujan.
enum MapPoiDensity {
  /// Ninguno. Es lo que se quiere cuando el mapa es el fondo de datos propios.
  off('Off'),

  /// Muy pocos.
  verySparse('VerySparse'),

  /// Pocos.
  sparse('Sparse'),

  /// El valor por defecto del servicio.
  standard('Default'),

  /// Muchos.
  dense('Dense'),

  /// Todos los disponibles.
  veryDense('VeryDense');

  const MapPoiDensity(this.wireName);

  /// El literal que viaja en la URL.
  final String wireName;
}

/// Categorías de puntos de interés que se dibujan.
///
/// Al indicar alguna, solo se dibujan esas. Se pueden pasar hasta nueve, y no
/// tiene efecto si la densidad es [MapPoiDensity.off].
enum MapPoiCategory {
  /// Restaurantes, bares y cafeterías.
  foodAndDrink('FoodAndDrink'),

  /// Ocio y espectáculos.
  entertainment('Entertainment'),

  /// Monumentos y museos.
  sightsAndMuseums('SightsAndMuseums'),

  /// Estaciones, paradas y aeropuertos.
  transportation('Transportation'),

  /// Hoteles y alojamiento.
  accommodations('Accommodations'),

  /// Parques y aire libre.
  leisureAndOutdoor('LeisureAndOutdoor'),

  /// Comercios.
  shopping('Shopping'),

  /// Oficinas y servicios.
  businessAndServices('BusinessAndServices'),

  /// Instalaciones y edificios públicos.
  facilitiesAndBuildings('FacilitiesAndBuildings');

  const MapPoiCategory(this.wireName);

  /// El literal que viaja en la URL.
  final String wireName;
}

/// Información adicional de un modo de transporte, dibujada en el estilo.
enum MapTravelMode {
  /// Redes de transporte público.
  transit('Transit'),

  /// Restricciones de vía para camiones.
  truck('Truck');

  const MapTravelMode(this.wireName);

  /// El literal que viaja en la URL.
  final String wireName;
}

/// Unidad de la barra de escala de un mapa estático.
enum ScaleBarUnit {
  /// Kilómetros.
  kilometers('Kilometers'),

  /// Kilómetros con millas debajo.
  kilometersMiles('KilometersMiles'),

  /// Millas.
  miles('Miles'),

  /// Millas con kilómetros debajo.
  milesKilometers('MilesKilometers');

  const ScaleBarUnit(this.wireName);

  /// El literal que viaja en la URL.
  final String wireName;
}
