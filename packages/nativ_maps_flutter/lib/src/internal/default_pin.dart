// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// El alfiler de `BitmapDescriptor.defaultMarker`, dibujado en Dart.
///
/// MapLibre no trae ningún icono de marcador. Si no se registra una imagen con
/// el nombre que pide la capa, el marcador **no se dibuja y nada avisa**. Se
/// pinta aquí, una vez por color, y el controlador lo registra en el estilo
/// como cualquier otro icono.
abstract final class DefaultPin {
  /// Ancho en puntos lógicos: el del marcador por defecto de Google.
  static const double width = 27;

  /// Alto en puntos lógicos.
  static const double height = 43;

  /// Se pinta a 3×. iOS registra la imagen con la escala de la pantalla y
  /// Android con la densidad del bitmap, así que a 3× sale nítido y del mismo
  /// tamaño en las dos.
  static const double pixelRatio = 3;

  static final Map<double, Future<Uint8List>> _cache =
      <double, Future<Uint8List>>{};

  /// El PNG del alfiler teñido con [hue] (0–360, como en Google).
  ///
  /// Se guarda por color: tras un cambio de estilo hay que registrarlo otra
  /// vez, pero no hace falta volver a pintarlo.
  static Future<Uint8List> png(double hue) =>
      _cache.putIfAbsent(hue % 360, () => _render(hue % 360));

  static Future<Uint8List> _render(double hue) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(pixelRatio);

    const stroke = 1.5;
    const radius = width / 2 - stroke;
    const center = Offset(width / 2, radius + stroke);
    const tip = Offset(width / 2, height - stroke);

    // Una gota: el círculo de arriba unido a la punta por sus dos tangentes.
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
