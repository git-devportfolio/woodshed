import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed/features/player/widgets/transport_bar.dart';

Widget _host({
  bool isPlaying = false,
  VoidCallback? onRewind,
  VoidCallback? onPlayPause,
  VoidCallback? onForward,
  VoidCallback? onRestart,
}) =>
    MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: TransportBar(
            isPlaying: isPlaying,
            onRewind: onRewind ?? () {},
            onPlayPause: onPlayPause ?? () {},
            onForward: onForward ?? () {},
            onRestart: onRestart ?? () {},
          ),
        ),
      ),
    );

void main() {
  testWidgets('chaque bouton déclenche son propre callback', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(_host(
      onRewind: () => calls.add('rewind'),
      onPlayPause: () => calls.add('play'),
      onForward: () => calls.add('forward'),
      onRestart: () => calls.add('restart'),
    ));

    for (final name in ['rewind', 'play', 'forward', 'restart']) {
      await tester.tap(find.byKey(ValueKey('transport-$name')));
      await tester.pump();
    }

    expect(calls, ['rewind', 'play', 'forward', 'restart']);
  });

  testWidgets('l\'icône centrale suit l\'état de lecture', (tester) async {
    await tester.pumpWidget(_host(isPlaying: false));
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsNothing);

    await tester.pumpWidget(_host(isPlaying: true));
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
  });

  testWidgets('les quatre boutons sont alignés et hauts de 76 px',
      (tester) async {
    await tester.pumpWidget(_host());

    final keys = [
      'transport-rewind',
      'transport-play',
      'transport-forward',
      'transport-restart',
    ];
    final first = tester.getRect(find.byKey(ValueKey(keys.first)));
    expect(first.height, 76);

    for (final key in keys.skip(1)) {
      final rect = tester.getRect(find.byKey(ValueKey(key)));
      expect(rect.top, first.top, reason: '$key doit rester sur la même ligne');
      expect(rect.height, 76);
    }
  });

  testWidgets('aucun débordement sur une largeur de 320 px', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host());

    expect(tester.takeException(), isNull);
  });

  testWidgets('la cible tactile dépasse le minimum de 44 px', (tester) async {
    await tester.pumpWidget(_host());

    for (final name in ['rewind', 'play', 'forward', 'restart']) {
      final size = tester.getSize(find.byKey(ValueKey('transport-$name')));
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThanOrEqualTo(44));
    }
  });
}
