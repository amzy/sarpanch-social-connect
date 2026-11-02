import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarpanch_social_connect/core/theme/app_theme.dart';

void main() {
  group('Sarpanch Social Connect themes', () {
    test('defines all six approved brand themes', () {
      expect(AppThemeId.values, hasLength(6));
      expect(brandPalettes.keys, containsAll(AppThemeId.values));
    });

    test('builds a Material 3 light and dark theme for every palette', () {
      for (final themeId in AppThemeId.values) {
        final light = buildAppTheme(themeId, Brightness.light);
        final dark = buildAppTheme(themeId, Brightness.dark);

        expect(light.useMaterial3, isTrue);
        expect(dark.useMaterial3, isTrue);
        expect(light.brightness, Brightness.light);
        expect(dark.brightness, Brightness.dark);
        expect(light.colorScheme.primary, isNot(dark.colorScheme.primary));
      }
    });

    test('each theme has a user-facing label and description', () {
      for (final themeId in AppThemeId.values) {
        expect(themeId.label, isNotEmpty);
        expect(themeId.description, isNotEmpty);
      }
    });
  });
}
