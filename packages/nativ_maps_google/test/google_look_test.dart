// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nativ_maps_google/nativ_maps_google.dart';

/// Las capas reales del estilo estándar: identificador → tipo.
Map<String, String> _awsLayers() => <String, String>{
  for (final line in File(
    'test/fixtures/aws_standard_layers.txt',
  ).readAsLinesSync())
    if (line.isNotEmpty && !line.startsWith('#'))
      line.split(' ').first: line.split(' ').last,
};

void main() {
  final layers = _awsLayers();
  final plan = GoogleLook.plan(layers.keys);

  test('cada regla encuentra al menos una capa del estilo estándar', () {
    expect(plan.unmatched, isEmpty);
  });

  test('cada propiedad va a una capa de su tipo', () {
    const prefixes = <String, String>{
      'background': 'background-',
      'fill': 'fill-',
      'line': 'line-',
      'symbol': 'text-',
    };
    for (final MapEntry(key: id, value: paint) in plan.layers.entries) {
      final prefix = prefixes[layers[id]];
      for (final property in paint.keys) {
        expect(
          prefix != null && property.startsWith(prefix),
          isTrue,
          reason: '$property sobre $id, que es ${layers[id]}',
        );
      }
    }
  });

  test('ninguna capa recibe la misma propiedad de dos reglas', () {
    final seen = <String>{};
    for (final rule in GoogleLook.light) {
      for (final id in layers.keys.where(rule.matches)) {
        for (final property in rule.paint.keys) {
          expect(seen.add('$id/$property'), isTrue, reason: '$id/$property');
        }
      }
    }
  });

  test('los colores fijos son #RRGGBB o hsl()', () {
    final color = RegExp(r'^(#[0-9A-F]{6}|hsl\(.+\))$');
    void check(Object value) {
      if (value is String && value.startsWith(RegExp(r'#|hsl\('))) {
        expect(color.hasMatch(value), isTrue, reason: value);
      } else if (value is List) {
        value.whereType<Object>().forEach(check);
      }
    }

    for (final paint in plan.layers.values) {
      paint.values.forEach(check);
    }
  });

  test('las calles quedan más claras que su borde, como en Google', () {
    int luma(String hex) {
      final v = int.parse(hex.substring(1), radix: 16);
      return (v >> 16) + (v >> 8 & 0xFF) + (v & 0xFF);
    }

    for (final kind in <String>['minor', 'primary', 'motorway-trunk']) {
      final fill = plan.layers['road_$kind']!['line-color']! as String;
      final edge = plan.layers['road_$kind-casing']!['line-color']! as String;
      expect(luma(fill), greaterThan(luma(edge)), reason: kind);
    }
  });

  test('se ancla entero: land no toca landuse_urban', () {
    expect(plan.layers.containsKey('land'), isTrue);
    expect(plan.layers.containsKey('landuse_urban'), isFalse);
  });

  test('sobre otro estilo, el plan lo dice en vez de callar', () {
    final other = GoogleLook.plan(<String>['satellite', 'labels']);
    expect(other.layers, isEmpty);
    expect(other.unmatched, hasLength(GoogleLook.light.length));
  });

  test('si dos reglas fijan lo mismo, gana la última', () {
    final result = GoogleLook.plan(
      <String>['water_fill'],
      rules: const <GoogleLookRule>[
        GoogleLookRule('water_fill', <String, Object>{'fill-color': '#000000'}),
        GoogleLookRule('water_.*', <String, Object>{'fill-color': '#FFFFFF'}),
      ],
    );
    expect(result.layers['water_fill'], <String, Object>{
      'fill-color': '#FFFFFF',
    });
  });
}
