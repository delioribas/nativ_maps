// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:math' as math;

import 'package:compass_maps/src/core/lat_lng.dart';

/// Alfabeto del formato **Flexible Polyline de HERE**.
///
/// **No es el de Google.** Google codifica con `carácter − 63`; HERE usa este
/// base64 propio, donde `A` vale 0 y `_` vale 63. Aplicar el esquema de Google
/// a una cadena de HERE devuelve números distintos desde el primer carácter, y
/// el resultado no falla: dibuja una línea en otro sitio.
const String _flexibleAlphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

/// Tabla inversa del alfabeto, construida una sola vez.
final Map<int, int> _flexibleValues = <int, int>{
  for (var i = 0; i < _flexibleAlphabet.length; i++)
    _flexibleAlphabet.codeUnitAt(i): i,
};

/// Decodifica el formato **Flexible Polyline de HERE**, que es el que devuelve
/// Amazon Location v2 cuando se pide `GeometryFormat.flexiblePolyline`.
///
/// ## Los dos errores que este código evita
///
/// Este decodificador nació corrigiendo dos fallos que se tapaban entre sí.
/// Quedan documentados porque los dos son fáciles de reintroducir:
///
/// **1 · El alfabeto.** Hacer `codeUnitAt(i) - 63` es el esquema de las
/// polilíneas de Google. HERE usa [_flexibleAlphabet]. Con la cadena de
/// referencia `BFoz5xJ67i1B1B7PzIhaxL7Y`, la `B` inicial vale 1 con la tabla
/// correcta y 3 con la de Google.
///
/// **2 · La cabecera son dos enteros, no uno:**
///
/// ```text
/// [versión] [contenido de cabecera] [datos…]
/// ```
///
/// Leer solo el primero y tomarlo por el contenido hace que la precisión salga
/// `1 & 0x0F = 1` —dividir entre 10 en lugar de entre 100 000— y una ruta de
/// Quito aparece en mitad del Pacífico.
///
/// Lanza [FormatException] si la cadena trae un carácter fuera del alfabeto o
/// una versión que no es la 1. Prefiere fallar a devolver una línea inventada.
///
/// Referencia: https://github.com/heremaps/flexible-polyline
List<LatLng> decodeFlexiblePolyline(String encoded) {
  if (encoded.isEmpty) return const <LatLng>[];

  var index = 0;

  int readUnsigned() {
    var result = 0;
    var shift = 0;
    while (index < encoded.length) {
      final value = _flexibleValues[encoded.codeUnitAt(index++)];
      if (value == null) {
        throw FormatException(
          'carácter fuera del alfabeto de Flexible Polyline',
          encoded,
          index - 1,
        );
      }
      result |= (value & 0x1F) << shift;
      shift += 5;
      if (value < 0x20) break;
    }
    return result;
  }

  int readSigned() {
    final unsigned = readUnsigned();
    return (unsigned & 1) != 0 ? ~(unsigned >> 1) : unsigned >> 1;
  }

  // La versión se lee y se descarta: solo existe la 1, pero hay que consumirla
  // para que el siguiente entero sea la cabecera de verdad. Este es el paso
  // que faltaba.
  final version = readUnsigned();
  if (version != 1) {
    throw FormatException(
      'Flexible Polyline versión $version no soportada (solo la 1)',
      encoded,
      0,
    );
  }

  final header = readUnsigned();
  final precision = header & 0x0F;
  final thirdDimension = (header >> 4) & 0x07; // 0 = solo lat/lon
  final scale = math.pow(10, precision).toDouble();

  var lat = 0;
  var lng = 0;
  final points = <LatLng>[];

  while (index < encoded.length) {
    lat += readSigned();
    if (index >= encoded.length) break;
    lng += readSigned();
    // El tercer eje (altitud, nivel…) se consume para no desalinear la
    // secuencia, pero no se guarda: LatLng es plano.
    if (thirdDimension != 0 && index < encoded.length) readSigned();
    points.add(LatLng(lat / scale, lng / scale));
  }
  return points;
}

/// Codifica una lista de puntos en el formato **Flexible Polyline de HERE**.
///
/// Es la operación inversa de [decodeFlexiblePolyline]. Existe sobre todo para
/// poder probar el decodificador contra sí mismo con puntos generados, y para
/// guardar un rastro comprimido en la base de datos propia: una ruta de mil
/// puntos ocupa alrededor de una décima parte que su JSON.
///
/// [precision] son los decimales que se conservan. Cinco es el valor que usa
/// Amazon Location y da algo más de un metro de resolución; siete llega al
/// centímetro y ocupa cerca de un 40 % más.
String encodeFlexiblePolyline(Iterable<LatLng> points, {int precision = 5}) {
  if (precision < 0 || precision > 15) {
    throw ArgumentError.value(precision, 'precision', 'debe estar en [0, 15]');
  }

  final buffer = StringBuffer();
  final scale = math.pow(10, precision).toDouble();

  void writeUnsigned(int value) {
    var v = value;
    while (v > 0x1F) {
      buffer.writeCharCode(_flexibleAlphabet.codeUnitAt((v & 0x1F) | 0x20));
      v >>= 5;
    }
    buffer.writeCharCode(_flexibleAlphabet.codeUnitAt(v));
  }

  void writeSigned(int value) =>
      writeUnsigned(value < 0 ? ~(value << 1) : value << 1);

  writeUnsigned(1); // versión
  writeUnsigned(precision); // cabecera: sin tercer eje

  var lastLat = 0;
  var lastLng = 0;
  for (final p in points) {
    final lat = (p.latitude * scale).round();
    final lng = (p.longitude * scale).round();
    writeSigned(lat - lastLat);
    writeSigned(lng - lastLng);
    lastLat = lat;
    lastLng = lng;
  }
  return buffer.toString();
}

/// Decodifica el formato de **polilínea codificada de Google**.
///
/// Amazon Location no lo devuelve nunca. Está aquí porque los proyectos que
/// migran desde `google_maps_flutter` suelen tener rastros ya guardados en
/// este formato, y sin esto habría que mantener dos decodificadores en la app.
///
/// Lanza [FormatException] ante un carácter fuera de rango.
List<LatLng> decodeGooglePolyline(String encoded, {int precision = 5}) {
  if (encoded.isEmpty) return const <LatLng>[];

  final scale = math.pow(10, precision).toDouble();
  final points = <LatLng>[];
  var index = 0;
  var lat = 0;
  var lng = 0;

  int readDelta() {
    var result = 0;
    var shift = 0;
    int byte;
    do {
      if (index >= encoded.length) {
        throw FormatException('polilínea truncada', encoded, index);
      }
      byte = encoded.codeUnitAt(index++) - 63;
      if (byte < 0 || byte > 0x3F) {
        throw FormatException(
          'carácter fuera del alfabeto de Google',
          encoded,
          index - 1,
        );
      }
      result |= (byte & 0x1F) << shift;
      shift += 5;
    } while (byte >= 0x20);
    return (result & 1) != 0 ? ~(result >> 1) : result >> 1;
  }

  while (index < encoded.length) {
    lat += readDelta();
    lng += readDelta();
    points.add(LatLng(lat / scale, lng / scale));
  }
  return points;
}
