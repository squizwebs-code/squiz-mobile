import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:squiz/core/brand.dart';
import 'package:squiz/core/theme.dart';

void main() {
  test('brand colour is #428bca', () => expect(kBrand.toARGB32(), 0xFF428BCA));

  for (final b in Brightness.values) {
    test('primary is the brand colour in ${b.name} theme', () {
      final t = buildTheme(b);
      expect(t.colorScheme.primary.toARGB32(), 0xFF428BCA);
      expect(t.colorScheme.brightness, b);
      expect(t.extension<SquizColors>(), isNotNull);
    });
  }
}
