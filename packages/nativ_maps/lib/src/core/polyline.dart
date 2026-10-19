// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'dart:math' as math;

import 'package:nativ_maps/src/core/lat_lng.dart';

/// Alphabet of **HERE's Flexible Polyline** format.
///
/// **It is not Google's.** Google encodes with `character − 63`; HERE uses
/// this base64 of its own, where `A` is 0 and `_` is 63. Applying Google's
/// scheme to a HERE string gives different numbers from the first character,
/// and the result does not fail: it draws a line somewhere else.
const String _flexibleAlphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

/// Reverse lookup table for the alphabet, built only once.
final Map<int, int> _flexibleValues = <int, int>{
  for (var i = 0; i < _flexibleAlphabet.length; i++)
    _flexibleAlphabet.codeUnitAt(i): i,
};

/// Decodes **HERE's Flexible Polyline** format, which is what Amazon Location
/// v2 returns when you ask for `GeometryFormat.flexiblePolyline`.
///
/// ## The two bugs this code avoids
///
/// This decoder was born fixing two bugs that masked each other. They stay
/// documented because both are easy to reintroduce:
///
/// **1 · The alphabet.** Doing `codeUnitAt(i) - 63` is the Google polyline
/// scheme. HERE uses [_flexibleAlphabet]. With the reference string
/// `BFoz5xJ67i1B1B7PzIhaxL7Y`, the leading `B` is 1 with the right table and
/// 3 with Google's.
///
/// **2 · The header is two integers, not one:**
///
/// ```text
/// [version] [header content] [data…]
/// ```
///
/// Reading only the first one and taking it as the content makes the
/// precision come out as `1 & 0x0F = 1` —dividing by 10 instead of by
/// 100,000— and a route in Quito shows up in the middle of the Pacific.
///
/// Throws [FormatException] if the string contains a character outside the
/// alphabet or a version other than 1. It prefers failing to returning a
/// made-up line.
///
/// Reference: https://github.com/heremaps/flexible-polyline
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

  // The version is read and discarded: only version 1 exists, but it has to
  // be consumed so that the next integer is the real header. This is the step
  // that was missing.
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
  final thirdDimension = (header >> 4) & 0x07; // 0 = lat/lon only
  final scale = math.pow(10, precision).toDouble();

  var lat = 0;
  var lng = 0;
  final points = <LatLng>[];

  while (index < encoded.length) {
    lat += readSigned();
    if (index >= encoded.length) break;
    lng += readSigned();
    // The third axis (altitude, level…) is consumed so the sequence does not
    // fall out of alignment, but it is not kept: LatLng is flat.
    if (thirdDimension != 0 && index < encoded.length) readSigned();
    points.add(LatLng(lat / scale, lng / scale));
  }
  return points;
}

/// Encodes a list of points in **HERE's Flexible Polyline** format.
///
/// It is the inverse of [decodeFlexiblePolyline]. It exists mainly to test
/// the decoder against itself with generated points, and to store a
/// compressed track in your own database: a thousand-point route takes up
/// about a tenth of its JSON.
///
/// [precision] is the number of decimals kept. Five is the value Amazon
/// Location uses and gives a little over one meter of resolution; seven
/// reaches the centimeter and takes up about 40 % more.
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

  writeUnsigned(1); // version
  writeUnsigned(precision); // header: no third axis

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

/// Decodes **Google's encoded polyline** format.
///
/// Amazon Location never returns it. It is here because projects migrating
/// from `google_maps_flutter` often have tracks already stored in this format,
/// and without it the app would have to maintain two decoders.
///
/// Throws [FormatException] on an out-of-range character.
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
