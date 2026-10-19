// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'package:nativ_maps/src/core/lat_lng.dart';

/// A polygon ring the way Amazon Location demands it: `[lon, lat]`, closed
/// and with the right winding order.
///
/// The service wants the outline **counter-clockwise** and the holes
/// clockwise, and otherwise it responds 400 —"must be oriented
/// counter-clockwise"— instead of flipping it. Whoever draws a zone does not
/// know which way they drew it; it gets flipped here. Verified against the
/// service with `PutGeofence`, `BatchPutGeofence` and `ListDevicePositions`.
List<List<double>> ringToLonLat(
  List<LatLng> ring, {
  required bool counterClockwise,
}) {
  final closed = <LatLng>[
    ...ring,
    // Left open, the service responds "LinearRing must be closed".
    if (ring.isNotEmpty && ring.first != ring.last) ring.first,
  ];
  final isCounterClockwise = _signedArea(closed) > 0;
  final oriented = isCounterClockwise == counterClockwise
      ? closed
      : closed.reversed;
  return <List<double>>[for (final point in oriented) point.toLonLat()];
}

/// Twice the signed area, in degrees with x = longitude and y = latitude:
/// positive if the closed ring winds counter-clockwise.
double _signedArea(List<LatLng> closed) {
  var sum = 0.0;
  for (var i = 0; i < closed.length - 1; i++) {
    final a = closed[i];
    final b = closed[i + 1];
    sum += a.longitude * b.latitude - b.longitude * a.latitude;
  }
  return sum;
}
