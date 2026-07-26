import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed/features/player/widgets/speed_selector.dart';

Widget _host({required double speed, required ValueChanged<double> onChanged}) =>
    MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: SpeedSelector(speed: speed, onChanged: onChanged),
        ),
      ),
    );

/// Couleur de fond réellement peinte par le bouton d'une vitesse donnée.
Color _background(WidgetTester tester, String key) {
  final material = tester.widget<Material>(
    find
        .descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(Material),
        )
        .first,
  );
  return material.color!;
}

void main() {
  testWidgets('expose exactement quatre vitesses, sans 0.5', (tester) async {
    await tester.pumpWidget(_host(speed: 1.0, onChanged: (_) {}));

    expect(find.text('0.75x'), findsOneWidget);
    expect(find.text('0.85x'), findsOneWidget);
    expect(find.text('0.95x'), findsOneWidget);
    expect(find.text('1x'), findsOneWidget);
    expect(find.textContaining('0.5'), findsNothing);
    expect(find.text('1.0x'), findsNothing);
  });

  testWidgets('le tap remonte la vitesse choisie', (tester) async {
    final tapped = <double>[];
    await tester.pumpWidget(_host(speed: 1.0, onChanged: tapped.add));

    await tester.tap(find.text('0.85x'));
    await tester.pump();

    expect(tapped, [0.85]);
  });

  testWidgets('seule la vitesse courante porte la couleur d\'accent',
      (tester) async {
    await tester.pumpWidget(_host(speed: 0.85, onChanged: (_) {}));

    final selected = _background(tester, 'speed-0.85');
    final others = {
      _background(tester, 'speed-0.75'),
      _background(tester, 'speed-0.95'),
      _background(tester, 'speed-1.0'),
    };

    expect(others.length, 1,
        reason: 'les vitesses non sélectionnées partagent le même fond');
    expect(others.single, isNot(selected));
  });

  testWidgets('les quatre boutons tiennent sur une ligne à 320 px',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(speed: 1.0, onChanged: (_) {}));

    expect(tester.takeException(), isNull);
    // Même ordonnée = même ligne.
    final y = tester.getCenter(find.byKey(const ValueKey('speed-0.75'))).dy;
    for (final k in ['speed-0.85', 'speed-0.95', 'speed-1.0']) {
      expect(tester.getCenter(find.byKey(ValueKey(k))).dy, y);
    }
  });
}
