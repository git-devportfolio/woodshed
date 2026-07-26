import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed/features/player/widgets/pitch_stepper.dart';

Widget _host({required double pitch, ValueChanged<double>? onChanged}) =>
    MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: PitchStepper(pitch: pitch, onChanged: onChanged ?? (_) {}),
        ),
      ),
    );

IconButton _button(WidgetTester tester, String key) =>
    tester.widget<IconButton>(find.byKey(ValueKey(key)));

void main() {
  test('formate la valeur avec son signe', () {
    expect(PitchStepper.format(0), '0');
    expect(PitchStepper.format(3), '+3');
    expect(PitchStepper.format(-2), '−2'); // U+2212
    expect(PitchStepper.format(-6), '−6');
  });

  testWidgets('affiche la valeur courante et son libellé', (tester) async {
    await tester.pumpWidget(_host(pitch: -2));

    expect(find.text('Pitch (demi-tons)'), findsOneWidget);
    expect(find.text('−2'), findsOneWidget);
  });

  testWidgets('les taps émettent la valeur voisine', (tester) async {
    final emitted = <double>[];
    await tester.pumpWidget(_host(pitch: 0, onChanged: emitted.add));

    await tester.tap(find.byKey(const ValueKey('pitch-plus')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pitch-minus')));
    await tester.pump();

    expect(emitted, [1.0, -1.0]);
  });

  testWidgets('les bornes désactivent le bouton correspondant', (tester) async {
    await tester.pumpWidget(_host(pitch: -6));
    expect(_button(tester, 'pitch-minus').onPressed, isNull);
    expect(_button(tester, 'pitch-plus').onPressed, isNotNull);

    await tester.pumpWidget(_host(pitch: 6));
    expect(_button(tester, 'pitch-plus').onPressed, isNull);
    expect(_button(tester, 'pitch-minus').onPressed, isNotNull);
  });

  testWidgets('la largeur de la valeur ne bouge pas entre 0 et −6',
      (tester) async {
    await tester.pumpWidget(_host(pitch: 0));
    final zero = tester.getSize(find.byKey(const ValueKey('pitch-value')));

    await tester.pumpWidget(_host(pitch: -6));
    final six = tester.getSize(find.byKey(const ValueKey('pitch-value')));

    expect(six.width, zero.width);
  });

  testWidgets('aucun débordement sur une largeur de 320 px', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(pitch: -6));

    expect(tester.takeException(), isNull);
  });
}
