// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'package:flutter_test/flutter_test.dart';
import 'package:nativ_maps_flutter/nativ_maps_flutter.dart';

/// How `maplibre_gl` decides whether a map request gets the custom headers.
///
/// Android: `Pattern.matches(pattern, url)`, the whole URL has to match.
/// iOS: `url.range(of: pattern, options: .regularExpression)`, anywhere in it.
bool android(String pattern, String url) =>
    RegExp('^(?:$pattern)\$').hasMatch(url);
bool ios(String pattern, String url) => RegExp(pattern).hasMatch(url);

bool both(List<String> patterns, String url) {
  final a = patterns.any((p) => android(p, url));
  final i = patterns.any((p) => ios(p, url));
  // The whole point: the same answer on both platforms.
  expect(a, i, reason: 'Android and iOS disagree on $url');
  return a;
}

void main() {
  test('a plain host never matched on Android: why headers were lost', () {
    const tile =
        'https://maps.geo.us-east-1.amazonaws.com/v2/tiles/vector.basemap/1/2/3';
    expect(ios('amazonaws.com', tile), isTrue);
    expect(android('amazonaws.com', tile), isFalse);
  });

  group('hostPatterns', () {
    final aws = NativMapController.hostPatterns(const <String>[
      'amazonaws.com',
    ]);
    final proxy = NativMapController.hostPatterns(const <String>[
      'api.miempresa.com',
      '10.0.2.2',
    ]);

    test('match the host and its subdomains on both platforms', () {
      expect(
        both(
          aws,
          'https://maps.geo.us-east-1.amazonaws.com/v2/tiles/vector.basemap/1/2/3',
        ),
        isTrue,
      );
      expect(
        both(
          proxy,
          'https://api.miempresa.com/geo/v2/styles/Standard/descriptor'
          '?color-scheme=Dark',
        ),
        isTrue,
      );
      // The Android emulator reaches the computer's localhost at 10.0.2.2.
      expect(
        both(proxy, 'http://10.0.2.2:8080/geo/v2/glyphs/Noto/0-255'),
        isTrue,
      );
    });

    test('do not leak the headers to look-alike hosts', () {
      expect(both(aws, 'https://evil.com/?next=amazonaws.com'), isFalse);
      expect(both(aws, 'https://amazonaws.com.evil.com/tiles'), isFalse);
      expect(both(proxy, 'https://api.miempresa.com.evil.com/geo'), isFalse);
      expect(both(proxy, 'https://evilapi.miempresa.com.co/x'), isFalse);
    });

    test('the dot in a host is literal, not "any character"', () {
      expect(both(proxy, 'https://apixmiempresa.com/geo'), isFalse);
    });

    test('empty and repeated hosts are dropped', () {
      expect(
        NativMapController.hostPatterns(const <String>['', 'a.com', 'a.com']),
        hasLength(1),
      );
    });
  });
}
