// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/lat_lng.dart';

/// Proyección plana local, en metros, alrededor de un origen.
///
/// ## Por qué no se usa trigonometría esférica
///
/// La fórmula de distancia transversal de una circunferencia máxima es
/// `asin(sin(δ13) · sin(θ13 − θ12)) · R`. Es exacta a escala planetaria, pero
/// para las distancias de un viaje en taxi —segmentos de decenas de metros—
/// pierde precisión justo donde hace falta: `asin` de un número minúsculo, y
/// `acos(cos(δ13) / cos(dxt/R))` con los dos cosenos casi iguales a 1, es
/// cancelación catastrófica en coma flotante de 64 bits.
///
/// Una proyección equirectangular local no tiene ese problema, es un orden de
/// magnitud más rápida —no hay funciones trigonométricas dentro del bucle— y
/// su error por debajo de 10 km está en los milímetros. Un medidor de taxi
/// procesa miles de posiciones por viaje: las dos cosas importan.
///
/// El origen se elige **por segmento**, no una vez por camino, para que la
/// distorsión nunca crezca con la longitud de la ruta.
@immutable
class _Plane {
  _Plane(this.origin) : _cosLat = math.cos(origin.latitude * math.pi / 180.0);

  /// El punto que se toma como `(0, 0)`.
  final LatLng origin;

  final double _cosLat;

  /// Metros al este y al norte del origen.
  (double, double) project(LatLng point) {
    final dLat = (point.latitude - origin.latitude) * math.pi / 180.0;
    final dLon = (point.longitude - origin.longitude) * math.pi / 180.0;
    return (earthRadiusMeters * dLon * _cosLat, earthRadiusMeters * dLat);
  }

  /// La operación inversa de [project].
  LatLng unproject(double x, double y) => LatLng(
    origin.latitude + y / earthRadiusMeters * 180.0 / math.pi,
    origin.longitude + x / (earthRadiusMeters * _cosLat) * 180.0 / math.pi,
  );
}

/// El resultado de proyectar un punto sobre un camino.
///
/// Es lo que devuelve [nearestPointOnPath], y la pieza sobre la que se apoyan
/// el progreso de ruta, la detección de desvío y el recorte de históricos.
@immutable
class PathMatch {
  /// Crea un emparejamiento.
  const PathMatch({
    required this.segmentIndex,
    required this.position,
    required this.distanceMeters,
    required this.alongMeters,
    required this.fraction,
  });

  /// El índice del segmento donde cayó, es decir el del punto de partida.
  ///
  /// Para un camino de `n` puntos hay `n - 1` segmentos, así que este valor
  /// va de `0` a `n - 2`.
  final int segmentIndex;

  /// El punto del camino más cercano, ya interpolado dentro del segmento.
  ///
  /// **No es un vértice del camino**, salvo por casualidad. Ese es justo el
  /// error que hay que evitar: en una autopista dos vértices consecutivos
  /// pueden estar a 200 m, y quedarse con el vértice más cercano da una
  /// distancia de desvío de 100 m para un coche que va perfectamente por su
  /// carril.
  final LatLng position;

  /// La distancia perpendicular entre el punto original y [position].
  ///
  /// Es la medida de «cuánto me he salido del camino».
  final double distanceMeters;

  /// Cuánto camino queda por detrás de [position], contado desde el principio.
  final double alongMeters;

  /// [alongMeters] como fracción de la longitud total, entre 0 y 1.
  final double fraction;

  @override
  String toString() =>
      'PathMatch(segmento $segmentIndex, a ${distanceMeters.round()} m, '
      'recorrido ${alongMeters.round()} m)';
}

/// La longitud total de un camino, en metros.
///
/// Devuelve `0` para un camino de menos de dos puntos.
double pathLength(List<LatLng> path) {
  if (path.length < 2) return 0;
  var total = 0.0;
  for (var i = 0; i < path.length - 1; i++) {
    total += path[i].distanceTo(path[i + 1]);
  }
  return total;
}

/// La distancia acumulada hasta cada punto del camino.
///
/// El resultado tiene la misma longitud que [path] y empieza en `0`. Merece la
/// pena calcularlo una vez y guardarlo cuando se va a consultar el progreso
/// muchas veces sobre la misma ruta.
List<double> cumulativeDistances(List<LatLng> path) {
  final cumulative = List<double>.filled(path.length, 0);
  for (var i = 1; i < path.length; i++) {
    cumulative[i] = cumulative[i - 1] + path[i - 1].distanceTo(path[i]);
  }
  return cumulative;
}

/// La distancia perpendicular de [point] al segmento que va de [start] a [end].
///
/// El punto se proyecta **dentro del segmento**: si la perpendicular cae fuera,
/// se devuelve la distancia al extremo más cercano. Sin ese recorte, un punto
/// muy anterior al inicio de un segmento daría una distancia pequeña por estar
/// alineado con su prolongación, que es geométricamente cierto y operativamente
/// absurdo.
double crossTrackMeters(LatLng point, LatLng start, LatLng end) {
  final plane = _Plane(start);
  final (px, py) = plane.project(point);
  final (bx, by) = plane.project(end);
  final lengthSquared = bx * bx + by * by;
  if (lengthSquared == 0) return point.distanceTo(start);
  final t = ((px * bx + py * by) / lengthSquared).clamp(0.0, 1.0);
  final dx = px - bx * t;
  final dy = py - by * t;
  return math.sqrt(dx * dx + dy * dy);
}

/// Encuentra el punto del camino más cercano a [point].
///
/// ## La ventana de búsqueda
///
/// Recorrer los 5 000 puntos de una ruta larga en cada posición del GPS es
/// trabajo desperdiciado: un coche que avanza a 90 km/h se mueve 25 m por
/// segundo, así que el emparejamiento nuevo está a un par de segmentos del
/// anterior. [fromIndex] y [maxSegments] permiten mirar solo esa ventana.
///
/// **Cuidado con usarla siempre.** Con la ventana puesta, un vehículo que se
/// teletransporta —túnel, pérdida de señal, reinicio de la app— se empareja
/// con el trozo equivocado y ya no se recupera. Quien la use debe volver a
/// buscar en todo el camino cuando la distancia resultante sea grande;
/// `RouteTracker` lo hace por su cuenta.
///
/// Lanza [ArgumentError] si el camino tiene menos de dos puntos.
PathMatch nearestPointOnPath(
  List<LatLng> path,
  LatLng point, {
  int fromIndex = 0,
  int? maxSegments,
  List<double>? cumulative,
}) {
  if (path.length < 2) {
    throw ArgumentError.value(
      path.length,
      'path',
      'A path needs at least two points to project onto',
    );
  }

  final cum = cumulative ?? cumulativeDistances(path);
  final start = fromIndex.clamp(0, path.length - 2);
  final end = maxSegments == null
      ? path.length - 1
      : math.min(start + maxSegments, path.length - 1);

  var bestDistance = double.infinity;
  var bestIndex = start;
  var bestT = 0.0;
  var bestPoint = path[start];

  for (var i = start; i < end; i++) {
    final a = path[i];
    final b = path[i + 1];
    final plane = _Plane(a);
    final (px, py) = plane.project(point);
    final (bx, by) = plane.project(b);
    final lengthSquared = bx * bx + by * by;
    final t = lengthSquared == 0
        ? 0.0
        : ((px * bx + py * by) / lengthSquared).clamp(0.0, 1.0);
    final cx = bx * t;
    final cy = by * t;
    final dx = px - cx;
    final dy = py - cy;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance < bestDistance) {
      bestDistance = distance;
      bestIndex = i;
      bestT = t;
      bestPoint = t == 0
          ? a
          : t == 1
          ? b
          : plane.unproject(cx, cy);
    }
  }

  final segmentLength = cum[bestIndex + 1] - cum[bestIndex];
  final travelled = cum[bestIndex] + segmentLength * bestT;
  final total = cum.last;

  return PathMatch(
    segmentIndex: bestIndex,
    position: bestPoint,
    distanceMeters: bestDistance,
    alongMeters: travelled,
    fraction: total == 0 ? 0 : (travelled / total).clamp(0.0, 1.0),
  );
}

/// El punto que está a [alongMeters] del principio del camino.
///
/// Se recorta a los extremos: pedir una distancia negativa devuelve el primer
/// punto, y pedir más de la longitud total devuelve el último.
LatLng interpolateOnPath(
  List<LatLng> path,
  double alongMeters, {
  List<double>? cumulative,
}) {
  if (path.isEmpty) {
    throw ArgumentError.value(path, 'path', 'The path is empty');
  }
  if (path.length == 1) return path.first;

  final cum = cumulative ?? cumulativeDistances(path);
  if (alongMeters <= 0) return path.first;
  if (alongMeters >= cum.last) return path.last;

  // Búsqueda binaria: el camino de una ruta larga tiene miles de puntos y
  // esta función se llama en cada fotograma de una animación.
  var low = 0;
  var high = cum.length - 1;
  while (high - low > 1) {
    final mid = (low + high) >> 1;
    if (cum[mid] <= alongMeters) {
      low = mid;
    } else {
      high = mid;
    }
  }

  final length = cum[high] - cum[low];
  if (length == 0) return path[low];
  final t = (alongMeters - cum[low]) / length;

  final plane = _Plane(path[low]);
  final (bx, by) = plane.project(path[high]);
  return plane.unproject(bx * t, by * t);
}

/// Recorta un camino conservando su forma, con **Douglas–Peucker**.
///
/// ## Para qué sirve de verdad
///
/// Guardar el histórico de una flota a 1 Hz son 86 400 posiciones por vehículo
/// y día. La inmensa mayoría no aporta nada: un coche parado en un semáforo
/// genera 90 puntos idénticos, y una recta de autopista queda igual de bien
/// descrita con dos puntos que con doscientos.
///
/// Con [toleranceMeters] de 5 m, un rastro urbano típico se queda entre el 3 %
/// y el 8 % de sus puntos sin que se note al dibujarlo.
///
/// **No uses esto antes de calcular la distancia del viaje.** El recorte quita
/// justamente los puntos de las curvas suaves, y la suma de distancias sobre
/// el camino recortado siempre sale menor. Primero se mide, después se recorta
/// para guardar.
List<LatLng> simplifyPath(
  List<LatLng> path, {
  required double toleranceMeters,
}) {
  if (toleranceMeters <= 0) {
    throw ArgumentError.value(
      toleranceMeters,
      'toleranceMeters',
      'The tolerance must be greater than zero',
    );
  }
  if (path.length < 3) return List<LatLng>.of(path);

  final keep = List<bool>.filled(path.length, false);
  keep[0] = true;
  keep[path.length - 1] = true;

  // Pila explícita en vez de recursión: un rastro de un día entero desborda
  // la pila de llamadas en el peor caso.
  final pending = <(int, int)>[(0, path.length - 1)];

  while (pending.isNotEmpty) {
    final (start, end) = pending.removeLast();
    if (end - start < 2) continue;

    var worstDistance = 0.0;
    var worstIndex = -1;
    for (var i = start + 1; i < end; i++) {
      final d = crossTrackMeters(path[i], path[start], path[end]);
      if (d > worstDistance) {
        worstDistance = d;
        worstIndex = i;
      }
    }

    if (worstDistance > toleranceMeters && worstIndex > 0) {
      keep[worstIndex] = true;
      pending
        ..add((start, worstIndex))
        ..add((worstIndex, end));
    }
  }

  return <LatLng>[
    for (var i = 0; i < path.length; i++)
      if (keep[i]) path[i],
  ];
}
