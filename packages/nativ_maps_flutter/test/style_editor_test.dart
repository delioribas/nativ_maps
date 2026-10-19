// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:nativ_maps_flutter/src/style_editor.dart';

void main() {
  group('OnlyTheseProperties', () {
    test('las clases tipadas de maplibre_gl mandan también lo no tocado', () {
      // Por esto no se usan: `setLayerProperties` llama a
      // `toJson(skipNulls: false)`, y cada `null` devuelve la propiedad a su
      // valor por defecto en el lado nativo. Aquí, el grosor de la calle.
      final typed = ml.LineLayerProperties.fromJson(<String, dynamic>{
        'line-color': '#D8E0E7',
      }).toJson(skipNulls: false);
      expect(typed, containsPair('line-width', isNull));
    });

    test('manda solo las propiedades pedidas, también sin saltar nulos', () {
      const properties = OnlyTheseProperties(<String, Object?>{
        'text-color': '#19865F',
      });
      expect(properties.toJson(skipNulls: false), <String, dynamic>{
        'text-color': '#19865F',
      });
    });

    test('las expresiones viajan tal cual', () {
      const expression = <Object>[
        'interpolate',
        <Object>['linear'],
        <Object>['zoom'],
        15,
        '#F5F3F3',
        17,
        '#F8F7F7',
      ];
      const properties = OnlyTheseProperties(<String, Object?>{
        'background-color': expression,
      });
      expect(properties.toJson()['background-color'], same(expression));
    });
  });
}
