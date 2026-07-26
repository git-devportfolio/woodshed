import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed/core/theme/app_theme.dart';

void main() {
  test('le thème applique la police Inter à toute la typographie', () {
    final theme = buildWoodshedTheme();

    expect(theme.textTheme.bodyMedium?.fontFamily, 'Inter');
    expect(theme.textTheme.titleLarge?.fontFamily, 'Inter');
  });

  test('le thème conserve la palette violette existante', () {
    final expected = ColorScheme.fromSeed(seedColor: Colors.deepPurple);

    expect(buildWoodshedTheme().colorScheme.primary, expected.primary);
    expect(buildWoodshedTheme().colorScheme.secondaryContainer,
        expected.secondaryContainer);
  });

  test('le thème reste en mode clair', () {
    expect(buildWoodshedTheme().brightness, Brightness.light);
  });
}
