// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:compass_maps/compass_maps.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Identificador de un marcador. Mismo nombre que en `google_maps_flutter`.
///
/// Es un tipo y no un `String` a propósito: impide pasar el identificador de
/// una polilínea donde va el de un marcador, que compila sin problema si los
/// dos son cadenas.
@immutable
class MarkerId {
  /// Crea el identificador.
  const MarkerId(this.value);

  /// El valor.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MarkerId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'MarkerId($value)';
}

/// Identificador de una polilínea.
@immutable
class PolylineId {
  /// Crea el identificador.
  const PolylineId(this.value);

  /// El valor.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PolylineId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'PolylineId($value)';
}

/// Identificador de un polígono.
@immutable
class PolygonId {
  /// Crea el identificador.
  const PolygonId(this.value);

  /// El valor.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PolygonId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'PolygonId($value)';
}

/// Identificador de un círculo.
@immutable
class CircleId {
  /// Crea el identificador.
  const CircleId(this.value);

  /// El valor.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is CircleId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'CircleId($value)';
}

/// Identificador de un mapa de calor.
@immutable
class HeatmapId {
  /// Crea el identificador.
  const HeatmapId(this.value);

  /// El valor.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is HeatmapId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'HeatmapId($value)';
}

/// El icono de un marcador.
///
/// En `google_maps_flutter` esto es `BitmapDescriptor`. Aquí el nombre es el
/// mismo para que el código migrado compile, pero la implementación es
/// distinta: MapLibre trabaja con imágenes registradas en el estilo por
/// nombre, así que un icono es una imagen que se registra una vez y se
/// referencia muchas.
///
/// Esa diferencia es una ventaja: cien marcadores con el mismo icono suben la
/// imagen **una** vez.
@immutable
class BitmapDescriptor {
  const BitmapDescriptor._({required this.name, this.bytes, this.hue});

  /// El marcador por defecto del estilo.
  static const BitmapDescriptor defaultMarker = BitmapDescriptor._(
    name: 'compass-default-marker',
  );

  /// El marcador por defecto teñido de un color.
  ///
  /// [hue] va de 0 a 360, como en `google_maps_flutter`. Las constantes
  /// `hueRed`, `hueAzure`… de Google están en [MarkerHue].
  static BitmapDescriptor defaultMarkerWithHue(double hue) =>
      BitmapDescriptor._(name: 'compass-default-marker', hue: hue);

  /// Un icono a partir de los bytes de una imagen PNG.
  ///
  /// [name] tiene que ser único por imagen: es la clave con la que se registra
  /// en el estilo. Dos iconos distintos con el mismo nombre se pisan.
  factory BitmapDescriptor.fromBytes(String name, Uint8List bytes) =>
      BitmapDescriptor._(name: name, bytes: bytes);

  /// Un icono ya registrado en el estilo, por su nombre.
  ///
  /// Sirve para usar los iconos que el propio estilo de Amazon Location trae
  /// dentro, sin subir nada.
  factory BitmapDescriptor.fromStyleImage(String name) =>
      BitmapDescriptor._(name: name);

  /// La clave con la que la imagen vive en el estilo.
  final String name;

  /// Los bytes, si hay que registrarla.
  final Uint8List? bytes;

  /// El tinte, de 0 a 360.
  final double? hue;

  /// ¿Hay que subir esta imagen al estilo?
  bool get needsUpload => bytes != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BitmapDescriptor && other.name == name && other.hue == hue;

  @override
  int get hashCode => Object.hash(name, hue);
}

/// Los tintes con nombre de `google_maps_flutter`, para que el código migrado
/// compile sin buscar los números.
abstract final class MarkerHue {
  /// Rojo, el color por defecto de Google.
  static const double hueRed = 0.0;

  /// Naranja.
  static const double hueOrange = 30.0;

  /// Amarillo.
  static const double hueYellow = 60.0;

  /// Verde.
  static const double hueGreen = 120.0;

  /// Cian.
  static const double hueCyan = 180.0;

  /// Azul.
  static const double hueAzure = 210.0;

  /// Azul oscuro.
  static const double hueBlue = 240.0;

  /// Violeta.
  static const double hueViolet = 270.0;

  /// Magenta.
  static const double hueMagenta = 300.0;

  /// Rosa.
  static const double hueRose = 330.0;
}

/// El globo que sale al tocar un marcador.
///
/// **Está reimplementado como widget de Flutter**, no como una vista nativa.
/// Se pierde el aspecto exacto del de Google y se gana poder poner **lo que
/// sea** dentro: una foto, un botón, una lista. Es el cambio del §4 que la
/// tabla marca como «reimplementado».
@immutable
class InfoWindow {
  /// Crea la ventana.
  const InfoWindow({
    this.title,
    this.snippet,
    this.anchor = const Offset(0.5, 0.0),
    this.onTap,
    this.builder,
  });

  /// Una ventana vacía: el marcador no muestra nada al tocarlo.
  static const InfoWindow noText = InfoWindow();

  /// El título en negrita.
  final String? title;

  /// La línea secundaria.
  final String? snippet;

  /// Dónde se ancla respecto al icono. `(0.5, 0)` es arriba y centrado.
  final Offset anchor;

  /// Qué hacer al tocar la ventana.
  final VoidCallback? onTap;

  /// Contenido a medida. Si se pasa, [title] y [snippet] se ignoran.
  ///
  /// Aquí es donde se aprovecha la reimplementación: cualquier widget vale.
  final Widget Function(BuildContext context)? builder;

  /// ¿Hay algo que mostrar?
  bool get isEmpty => title == null && snippet == null && builder == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InfoWindow &&
          title == other.title &&
          snippet == other.snippet &&
          anchor == other.anchor;

  @override
  int get hashCode => Object.hash(title, snippet, anchor);
}

/// Un marcador en el mapa.
///
/// Mismos nombres de campo que en `google_maps_flutter`, para que el código
/// migrado compile sin tocarlo.
@immutable
class Marker {
  /// Crea el marcador.
  const Marker({
    required this.markerId,
    required this.position,
    this.icon = BitmapDescriptor.defaultMarker,
    this.infoWindow = InfoWindow.noText,
    this.alpha = 1.0,
    this.anchor = const Offset(0.5, 1.0),
    this.draggable = false,
    this.flat = false,
    this.rotation = 0.0,
    this.visible = true,
    this.zIndex = 0.0,
    this.iconScale = 1.0,
    this.label,
    this.onTap,
    this.onDragEnd,
    this.clusterManagerId,
  });

  /// El identificador. Dos marcadores con el mismo se pisan.
  final MarkerId markerId;

  /// Dónde está.
  final LatLng position;

  /// El icono.
  final BitmapDescriptor icon;

  /// El globo que sale al tocarlo.
  final InfoWindow infoWindow;

  /// La opacidad, de 0 a 1.
  final double alpha;

  /// Qué punto del icono se apoya en la coordenada. `(0.5, 1)` es la punta de
  /// abajo, que es lo que quiere un alfiler.
  final Offset anchor;

  /// ¿Se puede arrastrar?
  final bool draggable;

  /// ¿Queda pegado al mapa al girar e inclinar?
  ///
  /// `true` es lo que se quiere para el icono de un vehículo, que tiene que
  /// girar con la calle. `false` lo mantiene siempre de frente, como un
  /// alfiler.
  final bool flat;

  /// La rotación en grados. Para un vehículo, el rumbo del GPS.
  final double rotation;

  /// ¿Se dibuja?
  final bool visible;

  /// El orden de apilado: mayor queda encima.
  final double zIndex;

  /// El tamaño del icono, 1 es el original.
  final double iconScale;

  /// Un texto debajo del icono. La matrícula, por ejemplo.
  final String? label;

  /// Qué hacer al tocarlo.
  final VoidCallback? onTap;

  /// Qué hacer al soltarlo tras arrastrarlo.
  final void Function(LatLng position)? onDragEnd;

  /// A qué agrupador pertenece, si está agrupado.
  final ClusterManagerId? clusterManagerId;

  /// Copia con algún campo cambiado.
  ///
  /// Es lo que se usa para mover un vehículo: `copyWith(position:, rotation:)`
  /// en cada posición nueva.
  Marker copyWith({
    LatLng? position,
    BitmapDescriptor? icon,
    InfoWindow? infoWindow,
    double? alpha,
    Offset? anchor,
    bool? draggable,
    bool? flat,
    double? rotation,
    bool? visible,
    double? zIndex,
    double? iconScale,
    String? label,
    VoidCallback? onTap,
    void Function(LatLng position)? onDragEnd,
    ClusterManagerId? clusterManagerId,
  }) => Marker(
    markerId: markerId,
    position: position ?? this.position,
    icon: icon ?? this.icon,
    infoWindow: infoWindow ?? this.infoWindow,
    alpha: alpha ?? this.alpha,
    anchor: anchor ?? this.anchor,
    draggable: draggable ?? this.draggable,
    flat: flat ?? this.flat,
    rotation: rotation ?? this.rotation,
    visible: visible ?? this.visible,
    zIndex: zIndex ?? this.zIndex,
    iconScale: iconScale ?? this.iconScale,
    label: label ?? this.label,
    onTap: onTap ?? this.onTap,
    onDragEnd: onDragEnd ?? this.onDragEnd,
    clusterManagerId: clusterManagerId ?? this.clusterManagerId,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Marker &&
          markerId == other.markerId &&
          position == other.position &&
          icon == other.icon &&
          alpha == other.alpha &&
          anchor == other.anchor &&
          flat == other.flat &&
          rotation == other.rotation &&
          visible == other.visible &&
          zIndex == other.zIndex &&
          iconScale == other.iconScale &&
          label == other.label &&
          infoWindow == other.infoWindow &&
          clusterManagerId == other.clusterManagerId;

  @override
  int get hashCode => Object.hash(
    markerId,
    position,
    icon,
    alpha,
    anchor,
    flat,
    rotation,
    visible,
    zIndex,
    iconScale,
    label,
    infoWindow,
    clusterManagerId,
  );

  @override
  String toString() => 'Marker(${markerId.value} @ $position)';
}

/// Cómo termina una polilínea.
enum Cap {
  /// Corte recto justo en el último punto.
  buttCap('butt'),

  /// Semicírculo que sobresale.
  roundCap('round'),

  /// Cuadrado que sobresale.
  squareCap('square');

  const Cap(this.wireName);

  /// El valor de `line-cap` en el estilo de MapLibre.
  final String wireName;
}

/// Cómo se unen dos segmentos de una polilínea.
enum JointType {
  /// Esquina en pico.
  mitered('miter'),

  /// Esquina redondeada. Es lo que hay que usar en una ruta larga: en pico,
  /// un giro cerrado dibuja una púa que sobresale varios píxeles.
  round('round'),

  /// Esquina cortada.
  bevel('bevel');

  const JointType(this.wireName);

  /// El valor de `line-join` en el estilo de MapLibre.
  final String wireName;
}

/// Un trozo del patrón de una línea discontinua.
@immutable
class PatternItem {
  const PatternItem._(this.type, this.length);

  /// Un trazo de [length] píxeles.
  factory PatternItem.dash(double length) => PatternItem._('dash', length);

  /// Un hueco de [length] píxeles.
  factory PatternItem.gap(double length) => PatternItem._('gap', length);

  /// Un punto.
  static const PatternItem dot = PatternItem._('dot', 1);

  /// `dash`, `gap` o `dot`.
  final String type;

  /// La longitud en píxeles.
  final double length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PatternItem && other.type == type && other.length == length;

  @override
  int get hashCode => Object.hash(type, length);
}

/// Una línea sobre el mapa.
@immutable
class Polyline {
  /// Crea la polilínea.
  const Polyline({
    required this.polylineId,
    this.points = const <LatLng>[],
    this.color = const Color(0xFF1E88E5),
    this.width = 4,
    this.startCap = Cap.buttCap,
    this.endCap = Cap.buttCap,
    this.jointType = JointType.round,
    this.patterns = const <PatternItem>[],
    this.visible = true,
    this.zIndex = 0,
    this.blur = 0,
    this.opacity = 1.0,
    this.onTap,
  });

  /// El identificador.
  final PolylineId polylineId;

  /// Los puntos, en orden.
  ///
  /// Aquí es donde se ve la tesis del paquete: `ruta.points` de un
  /// `RouteResponse` entra directamente, sin convertir nada.
  final List<LatLng> points;

  /// El color.
  final Color color;

  /// El grosor en píxeles.
  final double width;

  /// Cómo empieza.
  final Cap startCap;

  /// Cómo termina.
  final Cap endCap;

  /// Cómo se unen los segmentos.
  final JointType jointType;

  /// El patrón de discontinuidad. Vacío es línea continua.
  final List<PatternItem> patterns;

  /// ¿Se dibuja?
  final bool visible;

  /// El orden de apilado.
  final double zIndex;

  /// Difuminado del borde en píxeles. Sirve para el halo de una ruta.
  final double blur;

  /// La opacidad, de 0 a 1.
  final double opacity;

  /// Qué hacer al tocarla.
  final VoidCallback? onTap;

  /// ¿Es discontinua?
  bool get isDashed => patterns.isNotEmpty;

  /// Copia con algún campo cambiado.
  Polyline copyWith({
    List<LatLng>? points,
    Color? color,
    double? width,
    Cap? startCap,
    Cap? endCap,
    JointType? jointType,
    List<PatternItem>? patterns,
    bool? visible,
    double? zIndex,
    double? blur,
    double? opacity,
    VoidCallback? onTap,
  }) => Polyline(
    polylineId: polylineId,
    points: points ?? this.points,
    color: color ?? this.color,
    width: width ?? this.width,
    startCap: startCap ?? this.startCap,
    endCap: endCap ?? this.endCap,
    jointType: jointType ?? this.jointType,
    patterns: patterns ?? this.patterns,
    visible: visible ?? this.visible,
    zIndex: zIndex ?? this.zIndex,
    blur: blur ?? this.blur,
    opacity: opacity ?? this.opacity,
    onTap: onTap ?? this.onTap,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Polyline &&
          polylineId == other.polylineId &&
          listEquals(points, other.points) &&
          color == other.color &&
          width == other.width &&
          startCap == other.startCap &&
          endCap == other.endCap &&
          jointType == other.jointType &&
          listEquals(patterns, other.patterns) &&
          visible == other.visible &&
          zIndex == other.zIndex &&
          blur == other.blur &&
          opacity == other.opacity;

  @override
  int get hashCode => Object.hash(
    polylineId,
    Object.hashAll(points),
    color,
    width,
    startCap,
    endCap,
    jointType,
    visible,
    zIndex,
    blur,
    opacity,
  );

  @override
  String toString() => 'Polyline(${polylineId.value}, ${points.length} puntos)';
}

/// Un área cerrada sobre el mapa.
@immutable
class Polygon {
  /// Crea el polígono.
  const Polygon({
    required this.polygonId,
    this.points = const <LatLng>[],
    this.holes = const <List<LatLng>>[],
    this.fillColor = const Color(0x551E88E5),
    this.strokeColor = const Color(0xFF1E88E5),
    this.strokeWidth = 2,
    this.visible = true,
    this.zIndex = 0,
    this.onTap,
  });

  /// El polígono de una isócrona, ya listo para pintar.
  ///
  /// Toma el contorno y los agujeros del primer polígono de la isócrona. Es el
  /// atajo que convierte «hasta dónde llegó en ocho minutos» en una mancha en
  /// el mapa en una línea de código.
  ///
  /// Una isócrona puede traer **varios polígonos** —con un río sin puentes
  /// cerca, lo alcanzable son dos manchas separadas—; para pintarlos todos hay
  /// que recorrer `isoline.polygons` y crear uno por cada uno.
  factory Polygon.fromIsoline(
    Isoline isoline, {
    required PolygonId polygonId,
    Color fillColor = const Color(0x5539FF14),
    Color strokeColor = const Color(0xFF39FF14),
    double strokeWidth = 2,
  }) {
    final first = isoline.polygons.isEmpty
        ? const <List<LatLng>>[]
        : isoline.polygons.first;
    return Polygon(
      polygonId: polygonId,
      points: first.isEmpty ? const <LatLng>[] : first.first,
      holes: first.length > 1 ? first.sublist(1) : const <List<LatLng>>[],
      fillColor: fillColor,
      strokeColor: strokeColor,
      strokeWidth: strokeWidth,
    );
  }

  /// El identificador.
  final PolygonId polygonId;

  /// El contorno.
  final List<LatLng> points;

  /// Los huecos interiores.
  final List<List<LatLng>> holes;

  /// El color de relleno, normalmente con transparencia.
  final Color fillColor;

  /// El color del borde.
  final Color strokeColor;

  /// El grosor del borde en píxeles.
  final double strokeWidth;

  /// ¿Se dibuja?
  final bool visible;

  /// El orden de apilado.
  final double zIndex;

  /// Qué hacer al tocarlo.
  final VoidCallback? onTap;

  /// Copia con algún campo cambiado.
  Polygon copyWith({
    List<LatLng>? points,
    List<List<LatLng>>? holes,
    Color? fillColor,
    Color? strokeColor,
    double? strokeWidth,
    bool? visible,
    double? zIndex,
    VoidCallback? onTap,
  }) => Polygon(
    polygonId: polygonId,
    points: points ?? this.points,
    holes: holes ?? this.holes,
    fillColor: fillColor ?? this.fillColor,
    strokeColor: strokeColor ?? this.strokeColor,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    visible: visible ?? this.visible,
    zIndex: zIndex ?? this.zIndex,
    onTap: onTap ?? this.onTap,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Polygon &&
          polygonId == other.polygonId &&
          listEquals(points, other.points) &&
          fillColor == other.fillColor &&
          strokeColor == other.strokeColor &&
          strokeWidth == other.strokeWidth &&
          visible == other.visible &&
          zIndex == other.zIndex;

  @override
  int get hashCode => Object.hash(
    polygonId,
    Object.hashAll(points),
    fillColor,
    strokeColor,
    strokeWidth,
    visible,
    zIndex,
  );

  @override
  String toString() => 'Polygon(${polygonId.value})';
}

/// Un círculo de radio en metros.
///
/// **Es geodésico**, como el de Google: el radio son metros sobre el terreno,
/// no píxeles. Por eso se dibuja convirtiéndolo en un polígono de muchos
/// lados; un círculo de píxeles cambiaría de tamaño real al alejar el mapa.
@immutable
class Circle {
  /// Crea el círculo.
  const Circle({
    required this.circleId,
    required this.center,
    required this.radius,
    this.fillColor = const Color(0x5539FF14),
    this.strokeColor = const Color(0xFF39FF14),
    this.strokeWidth = 2,
    this.visible = true,
    this.zIndex = 0,
    this.segments = 72,
    this.onTap,
  });

  /// El identificador.
  final CircleId circleId;

  /// El centro.
  final LatLng center;

  /// El radio **en metros**.
  final double radius;

  /// El color de relleno.
  final Color fillColor;

  /// El color del borde.
  final Color strokeColor;

  /// El grosor del borde.
  final double strokeWidth;

  /// ¿Se dibuja?
  final bool visible;

  /// El orden de apilado.
  final double zIndex;

  /// En cuántos lados se descompone.
  ///
  /// Setenta y dos se ve redondo a cualquier zoom razonable. Subirlo mucho con
  /// cien círculos en pantalla sí se nota.
  final int segments;

  /// Qué hacer al tocarlo.
  final VoidCallback? onTap;

  /// Copia con algún campo cambiado.
  Circle copyWith({
    LatLng? center,
    double? radius,
    Color? fillColor,
    Color? strokeColor,
    double? strokeWidth,
    bool? visible,
    double? zIndex,
    int? segments,
    VoidCallback? onTap,
  }) => Circle(
    circleId: circleId,
    center: center ?? this.center,
    radius: radius ?? this.radius,
    fillColor: fillColor ?? this.fillColor,
    strokeColor: strokeColor ?? this.strokeColor,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    visible: visible ?? this.visible,
    zIndex: zIndex ?? this.zIndex,
    segments: segments ?? this.segments,
    onTap: onTap ?? this.onTap,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Circle &&
          circleId == other.circleId &&
          center == other.center &&
          radius == other.radius &&
          fillColor == other.fillColor &&
          strokeColor == other.strokeColor &&
          strokeWidth == other.strokeWidth &&
          visible == other.visible &&
          zIndex == other.zIndex &&
          segments == other.segments;

  @override
  int get hashCode => Object.hash(
    circleId,
    center,
    radius,
    fillColor,
    strokeColor,
    strokeWidth,
    visible,
    zIndex,
    segments,
  );

  @override
  String toString() => 'Circle(${circleId.value}, ${radius}m)';
}

/// Identificador de un agrupador de marcadores.
@immutable
class ClusterManagerId {
  /// Crea el identificador.
  const ClusterManagerId(this.value);

  /// El valor.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClusterManagerId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'ClusterManagerId($value)';
}

/// Agrupa marcadores cercanos en un solo símbolo con el recuento.
///
/// ## Por qué esto es mejor que en Google
///
/// **MapLibre agrupa de forma nativa**: la fuente de datos lleva `cluster:
/// true` y el motor hace el trabajo en C++, por tesela y en el hilo de
/// renderizado. En `google_maps_flutter` hay que usar una clase gestora que
/// recalcula en Dart en cada movimiento de cámara, y con unos cuantos miles de
/// marcadores eso se nota en el desplazamiento.
///
/// Lo que aquí es un parámetro, allí es una biblioteca aparte.
@immutable
class ClusterManager {
  /// Crea el agrupador.
  const ClusterManager({
    required this.clusterManagerId,
    this.maxZoom = 14,
    this.radius = 50,
    this.onClusterTap,
    this.textColor = const Color(0xFFFFFFFF),
    this.colorSteps = const <(int, Color)>[
      (0, Color(0xFF51BBD6)),
      (10, Color(0xFFF1F075)),
      (50, Color(0xFFF28CB1)),
    ],
    this.radiusSteps = const <(int, double)>[(0, 18), (10, 22), (50, 28)],
  });

  /// El identificador.
  final ClusterManagerId clusterManagerId;

  /// A partir de este zoom los marcadores dejan de agruparse.
  final int maxZoom;

  /// El radio de agrupación en píxeles.
  final double radius;

  /// Qué hacer al tocar un grupo.
  ///
  /// Si no se pasa, el mapa acerca automáticamente hasta el zoom en el que ese
  /// grupo se separa, que es lo que casi siempre se quiere.
  final void Function(Cluster cluster)? onClusterTap;

  /// El color del número.
  final Color textColor;

  /// El color del círculo según cuántos marcadores agrupe.
  ///
  /// Cada par es «a partir de N marcadores, este color». El primero tiene que
  /// empezar en 0.
  final List<(int, Color)> colorSteps;

  /// El tamaño del círculo según cuántos agrupe.
  final List<(int, double)> radiusSteps;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClusterManager &&
          clusterManagerId == other.clusterManagerId &&
          maxZoom == other.maxZoom &&
          radius == other.radius;

  @override
  int get hashCode => Object.hash(clusterManagerId, maxZoom, radius);
}

/// Un grupo de marcadores, tal como se toca en el mapa.
@immutable
class Cluster {
  /// Crea el grupo.
  const Cluster({
    required this.clusterManagerId,
    required this.position,
    required this.pointCount,
    this.clusterId,
  });

  /// A qué agrupador pertenece.
  final ClusterManagerId clusterManagerId;

  /// Dónde está el símbolo del grupo.
  final LatLng position;

  /// Cuántos marcadores agrupa.
  final int pointCount;

  /// El identificador interno del grupo en MapLibre.
  ///
  /// Es lo que hace falta para preguntarle al motor a qué zoom se separa este
  /// grupo concreto, que es lo que `google_maps_flutter` no puede dar.
  final int? clusterId;

  @override
  String toString() => 'Cluster($pointCount marcadores @ $position)';
}

/// Un mapa de calor.
///
/// ## Por qué esto también es mejor que en Google
///
/// En `google_maps_flutter` el mapa de calor es un tipo cerrado con muy pocos
/// mandos. Aquí es una **capa `heatmap` nativa de MapLibre**, y la rampa de
/// color, el radio y la intensidad se pueden hacer depender del zoom.
@immutable
class Heatmap {
  /// Crea el mapa de calor.
  const Heatmap({
    required this.heatmapId,
    required this.data,
    this.radius = 30,
    this.opacity = 0.7,
    this.intensity = 1.0,
    this.minZoom = 0,
    this.maxZoom = 22,
    this.gradient = const <(double, Color)>[
      (0.0, Color(0x00000000)),
      (0.2, Color(0xFF2196F3)),
      (0.4, Color(0xFF00E5FF)),
      (0.6, Color(0xFF76FF03)),
      (0.8, Color(0xFFFFEA00)),
      (1.0, Color(0xFFFF3D00)),
    ],
    this.visible = true,
  });

  /// El identificador.
  final HeatmapId heatmapId;

  /// Los puntos y su peso. El peso `null` cuenta como 1.
  final List<({LatLng point, double? weight})> data;

  /// El radio de influencia de cada punto, en píxeles.
  final double radius;

  /// La opacidad de toda la capa.
  final double opacity;

  /// El multiplicador de intensidad.
  final double intensity;

  /// A partir de qué zoom se ve.
  final double minZoom;

  /// Hasta qué zoom se ve.
  final double maxZoom;

  /// La rampa de color: pares de (densidad de 0 a 1, color).
  ///
  /// El primer color suele ser transparente para que las zonas sin datos no se
  /// tiñan.
  final List<(double, Color)> gradient;

  /// ¿Se dibuja?
  final bool visible;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Heatmap &&
          heatmapId == other.heatmapId &&
          radius == other.radius &&
          opacity == other.opacity &&
          intensity == other.intensity &&
          visible == other.visible &&
          data.length == other.data.length;

  @override
  int get hashCode =>
      Object.hash(heatmapId, radius, opacity, intensity, visible, data.length);

  @override
  String toString() => 'Heatmap(${heatmapId.value}, ${data.length} puntos)';
}

/// Identificador de una imagen superpuesta.
@immutable
class GroundOverlayId {
  /// Crea el identificador.
  const GroundOverlayId(this.value);

  /// El valor.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroundOverlayId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'GroundOverlayId($value)';
}

/// Una imagen anclada a un rectángulo del mapa.
///
/// Un plano de obra, un mapa escaneado, una zona de cobertura.
@immutable
class GroundOverlay {
  /// Crea la superposición.
  const GroundOverlay({
    required this.groundOverlayId,
    required this.bounds,
    required this.imageUrl,
    this.opacity = 1.0,
    this.visible = true,
    this.zIndex = 0,
  });

  /// El identificador.
  final GroundOverlayId groundOverlayId;

  /// El rectángulo que ocupa.
  final LatLngBounds bounds;

  /// La URL de la imagen. Vale un `data:` en base64.
  final String imageUrl;

  /// La opacidad.
  final double opacity;

  /// ¿Se dibuja?
  final bool visible;

  /// El orden de apilado.
  final double zIndex;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroundOverlay &&
          groundOverlayId == other.groundOverlayId &&
          bounds == other.bounds &&
          imageUrl == other.imageUrl &&
          opacity == other.opacity &&
          visible == other.visible;

  @override
  int get hashCode =>
      Object.hash(groundOverlayId, bounds, imageUrl, opacity, visible);
}

/// Identificador de una capa de teselas.
@immutable
class TileOverlayId {
  /// Crea el identificador.
  const TileOverlayId(this.value);

  /// El valor.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TileOverlayId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'TileOverlayId($value)';
}

/// Una capa de teselas propia encima del mapa.
///
/// Para pintar datos que se sirven ya en teselas: catastro, cobertura de red,
/// meteorología.
@immutable
class TileOverlay {
  /// Crea la capa.
  const TileOverlay({
    required this.tileOverlayId,
    required this.urlTemplate,
    this.tileSize = 256,
    this.opacity = 1.0,
    this.minZoom = 0,
    this.maxZoom = 22,
    this.visible = true,
    this.zIndex = 0,
    this.attribution,
  });

  /// El identificador.
  final TileOverlayId tileOverlayId;

  /// La plantilla de URL, con `{z}`, `{x}` e `{y}`.
  final String urlTemplate;

  /// El tamaño de la tesela en píxeles.
  final int tileSize;

  /// La opacidad.
  final double opacity;

  /// A partir de qué zoom se pide.
  final double minZoom;

  /// Hasta qué zoom se pide.
  final double maxZoom;

  /// ¿Se dibuja?
  final bool visible;

  /// El orden de apilado.
  final double zIndex;

  /// La atribución que hay que enseñar.
  ///
  /// Casi todos los proveedores de teselas la exigen en sus condiciones, y es
  /// lo primero que se olvida.
  final String? attribution;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TileOverlay &&
          tileOverlayId == other.tileOverlayId &&
          urlTemplate == other.urlTemplate &&
          opacity == other.opacity &&
          visible == other.visible;

  @override
  int get hashCode => Object.hash(tileOverlayId, urlTemplate, opacity, visible);
}
