// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// The `BitmapDescriptor.defaultMarker` pin, drawn in Dart.
///
/// MapLibre doesn't come with any marker icon. If no image is registered under
/// the name the layer asks for, the marker **isn't drawn and nothing warns
/// you**. It's painted here, once per color, and the controller registers it
/// in the style like any other icon.
abstract final class DefaultPin {
  /// Width in logical points: that of Google's default marker.
  static const double width = 27;

  /// Height in logical points.
  static const double height = 43;

  /// It's painted at 3×. iOS registers the image with the screen's scale and
  /// Android with the bitmap's density, so at 3× it comes out sharp and the
  /// same size on both.
  static const double pixelRatio = 3;

  static final Map<double, Future<Uint8List>> _cache =
      <double, Future<Uint8List>>{};

  /// The PNG of the pin tinted with [hue] (0–360, as in Google).
  ///
  /// It's cached per color: after a style change it has to be registered
  /// again, but there's no need to paint it again.
  static Future<Uint8List> png(double hue) =>
      _cache.putIfAbsent(hue % 360, () => _render(hue % 360));

  static Future<Uint8List> _render(double hue) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(pixelRatio);

    const stroke = 1.5;
    const radius = width / 2 - stroke;
    const center = Offset(width / 2, radius + stroke);
    const tip = Offset(width / 2, height - stroke);

    // A drop: the top circle joined to the tip by its two tangents.
    final reach = math.acos(radius / (tip.dy - center.dy));
    final pin = Path()
      ..moveTo(tip.dx, tip.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius),
        math.pi / 2 + reach,
        2 * math.pi - 2 * reach,
        false,
      )
      ..close();

    final fill = HSVColor.fromAHSV(1, hue, 0.85, 0.9).toColor();
    canvas
      ..drawPath(pin, Paint()..color = fill)
      ..drawPath(
        pin,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = const Color(0xFFFFFFFF),
      )
      ..drawCircle(
        center,
        radius * 0.38,
        Paint()..color = const Color(0xFFFFFFFF),
      );

    final image = await recorder.endRecording().toImage(
      (width * pixelRatio).ceil(),
      (height * pixelRatio).ceil(),
    );
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      return bytes!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}
