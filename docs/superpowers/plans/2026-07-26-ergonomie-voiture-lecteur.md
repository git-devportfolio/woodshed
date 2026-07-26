# Ergonomie voiture de l'écran lecteur — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rendre l'écran lecteur utilisable en voiture — police Inter unifiée, cibles tactiles nettement plus grandes, ligne de vitesse à quatre valeurs sans `0.5x`, et layout qui tient sans scroller.

**Architecture:** Un `ThemeData` centralisé porte la police Inter embarquée. Les trois blocs de contrôles du lecteur (transport, pitch, vitesse) sortent de `player_page.dart` vers `lib/features/player/widgets/`, où ils ne reçoivent que des valeurs primitives et des callbacks — ce qui les rend testables sur la VM Dart, contrairement à `PlayerPage` qui dépend de `WebAudioEngine` et donc de `package:web`. `player_page.dart` ne garde que la composition et le calcul de hauteur de la waveform.

**Tech Stack:** Flutter 3.44 / Dart 3.12, Material 3, `flutter_test` (tests widget), police Inter statique en asset local. **Aucune dépendance nouvelle** dans `pubspec.yaml`.

Spec de référence : `docs/superpowers/specs/2026-07-26-ergonomie-voiture-lecteur-design.md`

## Global Constraints

- **Aucune modification de logique audio** : `PlayerController`, `WebAudioEngine`, `web/audio/*.js` ne sont pas touchés. Ce lot est purement présentation.
- **Aucune dépendance ajoutée** : pas de `google_fonts`, pas de package de thème.
- **Palette inchangée** : `ColorScheme.fromSeed(seedColor: Colors.deepPurple)`, mode clair uniquement. Pas de `darkTheme`.
- **Textes UI en français**, identifiants de code en anglais (`CLAUDE.md`).
- **`flutter_lints`** doit passer sans avertissement : `flutter analyze` propre après chaque tâche.
- **Vitesses exactes** : `[0.75, 0.85, 0.95, 1.0]`. Le libellé de `1.0` est `1x`, jamais `1.0x`.
- **Signe moins typographique** U+2212 (`−`) pour les valeurs de pitch négatives, comme l'existant.
- **Métriques figées** (spec §5) : transport 76 px / gap 12 / rayon 20 / icône play 48 / icônes saut 34 ; pitch 64 × 64 / icône 32 / valeur large de 72 ; vitesse 56 / gap 8 / rayon 16 ; labels 16 px w600.
- **`_fixedBodyHeight = 466`** et waveform bornée à `clamp(96, 180)`.
- Chaque tâche finit par un **commit** avec un message en français, préfixé `feat:` / `refactor:` / `chore:`.

---

### Task 1 : Police Inter embarquée et thème centralisé

**Files:**
- Create: `assets/fonts/Inter-Regular.ttf`, `assets/fonts/Inter-SemiBold.ttf`, `assets/fonts/OFL.txt`
- Create: `lib/core/theme/app_theme.dart`
- Create: `test/core/theme/app_theme_test.dart`
- Modify: `pubspec.yaml` (section `flutter:`, après `uses-material-design: true` ligne 64)
- Modify: `lib/main.dart:24-30` (le `MaterialApp`)

**Interfaces:**
- Consumes: rien (première tâche).
- Produces: `ThemeData buildWoodshedTheme()` dans `lib/core/theme/app_theme.dart` — consommé par `main.dart`. La famille de police déclarée s'appelle exactement `Inter`.

- [ ] **Step 1 : Récupérer les deux fichiers de police**

Inter est sous OFL 1.1. Les statiques sont dans le dossier `extras/ttf/` de l'archive officielle.
**Cette étape nécessite un accès réseau — le demander avant de lancer la commande.**

```bash
mkdir -p assets/fonts
cd "$(mktemp -d)" && curl -fsSL -o inter.zip https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip && unzip -o -q inter.zip
```

Puis copier les deux poids et la licence vers le projet (adapter le chemin si l'arborescence de
l'archive diffère — `find . -name 'Inter-Regular.ttf'` la localise) :

```bash
cp extras/ttf/Inter-Regular.ttf extras/ttf/Inter-SemiBold.ttf /c/local.dev/lab/woodshed/assets/fonts/
cp LICENSE.txt /c/local.dev/lab/woodshed/assets/fonts/OFL.txt
```

Si l'URL a changé, télécharger l'archive depuis `https://rsms.me/inter/` et copier les deux mêmes
fichiers. **Ne pas** substituer la variable font (`InterVariable.ttf`) : Flutter pilote mal les axes
variables, la spec impose deux statiques.

- [ ] **Step 2 : Vérifier que les fichiers sont réels et non des pages d'erreur**

```bash
ls -l assets/fonts/
```

Attendu : `Inter-Regular.ttf` et `Inter-SemiBold.ttf` pèsent **chacun plus de 50 Ko** (typiquement
~110 Ko). Un fichier de quelques centaines d'octets signifie que le téléchargement a renvoyé une page
d'erreur — recommencer l'étape 1. Vérifier aussi que `OFL.txt` contient bien le texte de la licence.

- [ ] **Step 3 : Écrire le test du thème (il doit échouer)**

Créer `test/core/theme/app_theme_test.dart` :

```dart
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
```

- [ ] **Step 4 : Lancer le test pour vérifier qu'il échoue**

Run: `flutter test test/core/theme/app_theme_test.dart`
Expected: FAIL à la compilation — `Error: Couldn't resolve the package 'woodshed/core/theme/app_theme.dart'` (le fichier n'existe pas encore).

- [ ] **Step 5 : Créer le thème**

Créer `lib/core/theme/app_theme.dart` :

```dart
import 'package:flutter/material.dart';

/// Thème unique de l'application : police Inter embarquée + palette violette.
///
/// Le `TextTheme` n'est pas redéfini : les tailles particulières restent locales
/// aux widgets qui les portent, pour ne pas affecter les écrans hors périmètre.
ThemeData buildWoodshedTheme() => ThemeData(
      fontFamily: 'Inter',
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
    );
```

- [ ] **Step 6 : Déclarer la police dans `pubspec.yaml`**

Sous la section `flutter:`, juste après `uses-material-design: true` :

```yaml
  fonts:
    - family: Inter
      fonts:
        - asset: assets/fonts/Inter-Regular.ttf
          weight: 400
        - asset: assets/fonts/Inter-SemiBold.ttf
          weight: 600
```

Attention à l'indentation : `fonts:` est au même niveau que `uses-material-design:` (2 espaces).

- [ ] **Step 7 : Brancher le thème dans `main.dart`**

Remplacer le `theme:` du `MaterialApp` (`lib/main.dart:26-28`) par `theme: buildWoodshedTheme(),` et
ajouter l'import `import 'core/theme/app_theme.dart';`. Le résultat :

```dart
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'woodshed',
        theme: buildWoodshedTheme(),
        home: LibraryPage(repo: repo, engine: engine),
      );
```

- [ ] **Step 8 : Lancer le test pour vérifier qu'il passe**

Run: `flutter test test/core/theme/app_theme_test.dart`
Expected: PASS — 3 tests.

- [ ] **Step 9 : Vérifier que la police est réellement chargée**

Run: `flutter pub get && flutter analyze`
Expected: aucun avertissement. Puis `flutter run -d chrome` : le titre de la bibliothèque et les
libellés doivent visiblement changer de dessin (Inter au lieu de Roboto — les chiffres et le `a`
minuscule sont les plus reconnaissables). Un avertissement console du type
`Unable to load asset: assets/fonts/Inter-Regular.ttf` signifie que la déclaration `pubspec.yaml`
est mal indentée.

- [ ] **Step 10 : Commit**

```bash
git add assets/fonts pubspec.yaml lib/core/theme/app_theme.dart lib/main.dart test/core/theme/app_theme_test.dart
git commit -m "feat(ui): police Inter embarquee + theme centralise"
```

---

### Task 2 : `SectionLabel` et `SpeedSelector`

Les trois blocs de réglage partagent le même style de label (16 px w600). Un petit widget partagé
évite de le dupliquer trois fois — il est créé ici puis réutilisé aux tâches 3, 4 et 5.

**Files:**
- Create: `lib/features/player/widgets/section_label.dart`
- Create: `lib/features/player/widgets/speed_selector.dart`
- Create: `test/features/player/speed_selector_test.dart`

**Interfaces:**
- Consumes: rien de la tâche 1 (indépendant du thème).
- Produces:
  - `SectionLabel(String text)` — **paramètre positionnel**, appelé `SectionLabel('Vitesse')`. Utilisé par `PitchStepper` (tâche 4) et par le libellé de volume dans `player_page.dart` (tâche 5).
  - `SpeedSelector({required double speed, required ValueChanged<double> onChanged})`, avec `static const List<double> SpeedSelector.speeds`. Chaque bouton porte la clé `ValueKey('speed-$r')` où `$r` est le `toString()` du double (`speed-0.75`, `speed-0.85`, `speed-0.95`, `speed-1.0`).
  - Le label affiché vient de `SpeedSelector.label(double)` (`static`), qui rend `1x` pour `1.0` et `0.75x` pour `0.75`.

- [ ] **Step 1 : Écrire les tests (ils doivent échouer)**

Créer `test/features/player/speed_selector_test.dart` :

```dart
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
```

- [ ] **Step 2 : Lancer les tests pour vérifier qu'ils échouent**

Run: `flutter test test/features/player/speed_selector_test.dart`
Expected: FAIL à la compilation — le package `woodshed/features/player/widgets/speed_selector.dart` n'existe pas.

- [ ] **Step 3 : Créer `SectionLabel`**

Créer `lib/features/player/widgets/section_label.dart` :

```dart
import 'package:flutter/material.dart';

/// Libellé d'un bloc de réglage, placé au-dessus de ses contrôles.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  static const fontSize = 16.0;

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
      );
}
```

- [ ] **Step 4 : Créer `SpeedSelector`**

Créer `lib/features/player/widgets/speed_selector.dart` :

```dart
import 'package:flutter/material.dart';

import 'section_label.dart';

/// Sélecteur de vitesse : une seule ligne, quatre cibles larges (usage voiture).
///
/// La ligne unique est garantie par construction — un `Row` d'`Expanded` ne peut
/// pas passer à la ligne, contrairement à un `Wrap`.
class SpeedSelector extends StatelessWidget {
  const SpeedSelector({super.key, required this.speed, required this.onChanged});

  static const speeds = <double>[0.75, 0.85, 0.95, 1.0];
  static const _height = 56.0;
  static const _gap = 8.0;
  static const _radius = 16.0;

  final double speed;
  final ValueChanged<double> onChanged;

  /// `1.0` s'affiche `1x` ; les autres gardent leurs décimales (`0.75x`).
  static String label(double rate) => rate == 1.0 ? '1x' : '${rate}x';

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(_height),
      padding: EdgeInsets.zero,
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Vitesse'),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final rate in speeds) ...[
              if (rate != speeds.first) const SizedBox(width: _gap),
              Expanded(
                child: rate == speed
                    ? FilledButton(
                        key: ValueKey('speed-$rate'),
                        style: style,
                        onPressed: () => onChanged(rate),
                        child: Text(label(rate)),
                      )
                    : FilledButton.tonal(
                        key: ValueKey('speed-$rate'),
                        style: style,
                        onPressed: () => onChanged(rate),
                        child: Text(label(rate)),
                      ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
```

- [ ] **Step 5 : Lancer les tests pour vérifier qu'ils passent**

Run: `flutter test test/features/player/speed_selector_test.dart`
Expected: PASS — 4 tests.

- [ ] **Step 6 : Vérifier l'analyse statique**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7 : Commit**

```bash
git add lib/features/player/widgets/section_label.dart lib/features/player/widgets/speed_selector.dart test/features/player/speed_selector_test.dart
git commit -m "feat(player): selecteur de vitesse sur une ligne, sans 0.5x"
```

---

### Task 3 : `TransportBar`

**Files:**
- Create: `lib/features/player/widgets/transport_bar.dart`
- Create: `test/features/player/transport_bar_test.dart`

**Interfaces:**
- Consumes: rien des tâches 1–2 (`TransportBar` n'affiche aucun label, donc pas de `SectionLabel`).
- Produces: `TransportBar({required bool isPlaying, required VoidCallback onRewind, required VoidCallback onPlayPause, required VoidCallback onForward, required VoidCallback onRestart})`. Clés des boutons : `ValueKey('transport-rewind')`, `transport-play`, `transport-forward`, `transport-restart`. Hauteur totale du widget : **76 px** (valeur utilisée par `_fixedBodyHeight` en tâche 5).

- [ ] **Step 1 : Écrire les tests (ils doivent échouer)**

Créer `test/features/player/transport_bar_test.dart` :

```dart
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
```

- [ ] **Step 2 : Lancer les tests pour vérifier qu'ils échouent**

Run: `flutter test test/features/player/transport_bar_test.dart`
Expected: FAIL à la compilation — `transport_bar.dart` n'existe pas.

- [ ] **Step 3 : Créer `TransportBar`**

Créer `lib/features/player/widgets/transport_bar.dart` :

```dart
import 'package:flutter/material.dart';

/// Bloc de transport : quatre grandes cibles sur une ligne, play/pause dominant.
///
/// Les quatre conteneurs ont la même taille ; la dominance de play/pause vient
/// de son remplissage en couleur d'accent et de son icône plus grande.
class TransportBar extends StatelessWidget {
  const TransportBar({
    super.key,
    required this.isPlaying,
    required this.onRewind,
    required this.onPlayPause,
    required this.onForward,
    required this.onRestart,
  });

  static const height = 76.0;
  static const _gap = 12.0;
  static const _radius = 20.0;
  static const _playIconSize = 48.0;
  static const _skipIconSize = 34.0;

  final bool isPlaying;
  final VoidCallback onRewind;
  final VoidCallback onPlayPause;
  final VoidCallback onForward;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: _button(
              name: 'rewind',
              tooltip: '−10 s',
              icon: Icons.replay_10,
              iconSize: _skipIconSize,
              onPressed: onRewind,
            ),
          ),
          const SizedBox(width: _gap),
          Expanded(
            child: _button(
              name: 'play',
              tooltip: isPlaying ? 'Pause' : 'Lecture',
              icon: isPlaying ? Icons.pause : Icons.play_arrow,
              iconSize: _playIconSize,
              onPressed: onPlayPause,
              primary: true,
            ),
          ),
          const SizedBox(width: _gap),
          Expanded(
            child: _button(
              name: 'forward',
              tooltip: '+10 s',
              icon: Icons.forward_10,
              iconSize: _skipIconSize,
              onPressed: onForward,
            ),
          ),
          const SizedBox(width: _gap),
          Expanded(
            child: _button(
              name: 'restart',
              tooltip: 'Redémarrer',
              icon: Icons.replay,
              iconSize: _skipIconSize,
              onPressed: onRestart,
            ),
          ),
        ],
      );

  Widget _button({
    required String name,
    required String tooltip,
    required IconData icon,
    required double iconSize,
    required VoidCallback onPressed,
    bool primary = false,
  }) {
    final style = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(height),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
      ),
    );
    final child = Icon(icon, size: iconSize);
    final key = ValueKey('transport-$name');

    return Tooltip(
      message: tooltip,
      child: primary
          ? FilledButton(key: key, style: style, onPressed: onPressed, child: child)
          : FilledButton.tonal(key: key, style: style, onPressed: onPressed, child: child),
    );
  }
}
```

- [ ] **Step 4 : Lancer les tests pour vérifier qu'ils passent**

Run: `flutter test test/features/player/transport_bar_test.dart`
Expected: PASS — 5 tests.

Si le test de hauteur échoue avec une valeur supérieure à 76, c'est que la `tapTargetSize` du thème
ajoute du padding : ajouter `tapTargetSize: MaterialTapTargetSize.shrinkWrap` au `styleFrom` (la
cible réelle de 76 px dépasse déjà largement le minimum que ce réglage protège).

- [ ] **Step 5 : Vérifier l'analyse statique**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6 : Commit**

```bash
git add lib/features/player/widgets/transport_bar.dart test/features/player/transport_bar_test.dart
git commit -m "feat(player): bloc de transport a grandes cibles tactiles"
```

---

### Task 4 : `PitchStepper`

**Files:**
- Create: `lib/features/player/widgets/pitch_stepper.dart`
- Create: `test/features/player/pitch_stepper_test.dart`

**Interfaces:**
- Consumes: `SectionLabel` de la tâche 2 (`lib/features/player/widgets/section_label.dart`).
- Produces: `PitchStepper({required double pitch, required ValueChanged<double> onChanged})`, avec `static const PitchStepper.min = -6.0` et `max = 6.0`, et `static String PitchStepper.format(double)`. Clés : `ValueKey('pitch-minus')`, `pitch-plus`, `pitch-value`. Hauteur totale : **94 px** (label 22 + écart 8 + boutons 64).

- [ ] **Step 1 : Écrire les tests (ils doivent échouer)**

Créer `test/features/player/pitch_stepper_test.dart` :

```dart
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
```

- [ ] **Step 2 : Lancer les tests pour vérifier qu'ils échouent**

Run: `flutter test test/features/player/pitch_stepper_test.dart`
Expected: FAIL à la compilation — `pitch_stepper.dart` n'existe pas.

- [ ] **Step 3 : Créer `PitchStepper`**

Créer `lib/features/player/widgets/pitch_stepper.dart`. Le libellé était calculé par `_pitchLabel`
dans `player_page.dart` — il déménage ici en `static format`, et l'ancienne méthode privée sera
supprimée en tâche 5.

```dart
import 'package:flutter/material.dart';

import 'section_label.dart';

/// Stepper de transposition : label au-dessus, `[−] valeur [+]` centré dessous.
///
/// Le label est au-dessus (et non sur la même ligne) parce qu'avec des boutons
/// de 64 px la ligne complète dépasserait la largeur d'un petit écran.
class PitchStepper extends StatelessWidget {
  const PitchStepper({super.key, required this.pitch, required this.onChanged});

  static const min = -6.0;
  static const max = 6.0;
  static const _buttonSize = 64.0;
  static const _iconSize = 32.0;
  static const _valueWidth = 72.0;
  static const _valueFontSize = 36.0;

  final double pitch;
  final ValueChanged<double> onChanged;

  /// `0`, `+3`, `−2` — le moins est le signe typographique U+2212.
  static String format(double semitones) {
    final n = semitones.round();
    if (n == 0) return '0';
    return n > 0 ? '+$n' : '−${n.abs()}';
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Pitch (demi-tons)'),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                key: const ValueKey('pitch-minus'),
                tooltip: '−1 demi-ton',
                iconSize: _iconSize,
                style: IconButton.styleFrom(
                  minimumSize: const Size(_buttonSize, _buttonSize),
                ),
                // `.toDouble()` est obligatoire : `num.clamp` renvoie un `num`,
                // pas un `double` (comme dans le code d'origine).
                onPressed: pitch > min
                    ? () => onChanged((pitch - 1).clamp(min, max).toDouble())
                    : null,
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                key: const ValueKey('pitch-value'),
                width: _valueWidth,
                child: Text(
                  format(pitch),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: _valueFontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton.filledTonal(
                key: const ValueKey('pitch-plus'),
                tooltip: '+1 demi-ton',
                iconSize: _iconSize,
                style: IconButton.styleFrom(
                  minimumSize: const Size(_buttonSize, _buttonSize),
                ),
                onPressed: pitch < max
                    ? () => onChanged((pitch + 1).clamp(min, max).toDouble())
                    : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ],
      );
}
```

- [ ] **Step 4 : Lancer les tests pour vérifier qu'ils passent**

Run: `flutter test test/features/player/pitch_stepper_test.dart`
Expected: PASS — 6 tests.

- [ ] **Step 5 : Vérifier l'analyse statique**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6 : Commit**

```bash
git add lib/features/player/widgets/pitch_stepper.dart test/features/player/pitch_stepper_test.dart
git commit -m "feat(player): stepper de pitch agrandi, label au-dessus"
```

---

### Task 5 : Câblage dans `PlayerPage` et layout sans scroll

Cette tâche remplace les trois blocs inline par les widgets des tâches 2–4 et introduit le calcul de
hauteur de la waveform. `PlayerPage` reçoit un `WebAudioEngine` concret, dépendant de `package:web` :
**aucun test widget n'est possible ici**, la vérification passe par `flutter analyze` puis un run réel.

**Files:**
- Modify: `lib/features/player/player_page.dart` (le `build`, lignes 79-239, et suppression de `_pitchLabel` lignes 73-77)

**Interfaces:**
- Consumes: `TransportBar` (tâche 3), `PitchStepper` (tâche 4), `SpeedSelector` + `SectionLabel` (tâche 2). `WaveformView` expose déjà un paramètre `height` (défaut 120) — voir `lib/features/player/waveform_view.dart:17`.
- Produces: rien pour des tâches ultérieures.

- [ ] **Step 1 : Ajouter les imports et la constante de hauteur fixe**

En tête de `player_page.dart`, après les imports existants :

```dart
import 'widgets/pitch_stepper.dart';
import 'widgets/section_label.dart';
import 'widgets/speed_selector.dart';
import 'widgets/transport_bar.dart';
```

Dans `_PlayerPageState`, à côté des autres champs :

```dart
  /// Hauteur cumulée de tout le corps sauf la waveform (spec §7) : padding 32 +
  /// ligne temps/boucle 56 + transport 76 + pitch 94 + vitesse 86 + volume 70 +
  /// écarts 52.
  static const _fixedBodyHeight = 466.0;
```

- [ ] **Step 2 : Supprimer `_pitchLabel`**

Supprimer la méthode `_pitchLabel` (`player_page.dart:73-77`) : son rôle est repris par
`PitchStepper.format`. Garder `_fmt` (utilisé par l'affichage du temps).

- [ ] **Step 3 : Remplacer le corps du lecteur**

Remplacer le `body:` (à partir de `body: _loading` jusqu'à la fin du `Scaffold`) par :

```dart
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : AnimatedBuilder(
              animation: _c,
              builder: (context, _) => LayoutBuilder(
                builder: (context, constraints) {
                  final waveformHeight =
                      (constraints.maxHeight - _fixedBodyHeight)
                          .clamp(96.0, 180.0);

                  return SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          WaveformView(
                            height: waveformHeight,
                            peaks: _peaks,
                            duration: total,
                            position: Duration(milliseconds: posMs.round()),
                            loopA: _c.loopA,
                            loopB: _c.loopB,
                            loopEnabled: _c.loopEnabled,
                            onSeek: (t) {
                              _c.seek(t);
                              setState(() => _position = t);
                            },
                            onSetA: (t) => _c.setLoopA(t),
                            onSetB: (t) => _c.setLoopB(t),
                          ),
                          SizedBox(
                            height: 56,
                            child: Row(
                              children: [
                                Text(
                                    '${_fmt(Duration(milliseconds: posMs.round()))} / ${_fmt(total)}'),
                                const Spacer(),
                                FilledButton.tonalIcon(
                                  onPressed: _c.toggleLoop,
                                  icon: Icon(_c.loopEnabled
                                      ? Icons.repeat_on
                                      : Icons.repeat),
                                  label: Text(_c.loopEnabled
                                      ? 'Boucle A–B : ON'
                                      : 'Boucle A–B'),
                                ),
                                IconButton(
                                  tooltip: 'Réinitialiser la boucle',
                                  onPressed: _c.resetLoop,
                                  icon: const Icon(
                                      Icons.settings_backup_restore),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          TransportBar(
                            isPlaying: _c.isPlaying,
                            onRewind: () => _c.rewind10s(_position),
                            onPlayPause: () =>
                                _c.isPlaying ? _c.pause() : _c.play(),
                            onForward: () => _c.forward10s(_position),
                            onRestart: () {
                              _c.restart();
                              setState(() => _position =
                                  _c.loopEnabled ? _c.loopA : Duration.zero);
                            },
                          ),
                          const SizedBox(height: 16),
                          PitchStepper(
                            pitch: _c.pitch,
                            onChanged: _c.setPitch,
                          ),
                          const SizedBox(height: 12),
                          SpeedSelector(
                            speed: _c.speed,
                            onChanged: _c.setSpeed,
                          ),
                          const SizedBox(height: 12),
                          SectionLabel(
                              'Volume : ${(_c.volume * 100).round()} %'),
                          Slider(
                            value: _c.volume,
                            onChanged: (v) => _c.setVolume(v),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
```

Trois points à ne pas rater :
- Le `Row` temps/boucle est enveloppé d'un `SizedBox(height: 56)` : sans lui, `_fixedBodyHeight` ne correspondrait pas au rendu réel.
- `WaveformView` reçoit désormais `height:` — c'est la seule interaction avec ce widget.
- `onPlayPause` conserve l'expression conditionnelle existante ; ne pas la « simplifier » en un appel unique, `play()` et `pause()` ne sont pas interchangeables.

- [ ] **Step 4 : Vérifier l'analyse statique et la suite de tests**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` puis tous les tests au vert (les 5 fichiers de tests existants + les 4 nouveaux). Un avertissement `unused_element` sur `_pitchLabel` signifie que l'étape 2 a été oubliée.

- [ ] **Step 5 : Vérifier visuellement dans Chrome**

Run: `flutter run -d chrome`

Charger un morceau et contrôler, en réduisant la fenêtre à ~390 × 760 :
- typographie Inter partout, y compris sur l'écran bibliothèque ;
- quatre boutons de transport de taille égale sur une ligne, play/pause violet plein ;
- ligne de vitesse à quatre boutons, **aucun `0.5x`**, `1x` sélectionné par défaut ;
- pitch : label au-dessus, `[−] valeur [+]` centré, valeur qui ne décale rien en passant de `0` à `−6` ;
- **aucun scroll** à cette taille de fenêtre ;
- **aucun bandeau jaune/noir d'overflow**, en particulier sur la ligne temps/boucle qui n'a pas été retouchée mais dont les métriques de texte changent avec Inter.

- [ ] **Step 6 : Commit**

```bash
git add lib/features/player/player_page.dart
git commit -m "refactor(player): composition des blocs extraits + layout sans scroll"
```

---

### Task 6 : Validation sur iPhone

Aucun test automatisé ne dira si les boutons sont assez gros pour être touchés sans regarder. C'est la
seule vérification qui compte vraiment pour ce lot.

**Files:** aucun (validation).

**Interfaces:**
- Consumes: l'application complète des tâches 1–5.
- Produces: rien.

- [ ] **Step 1 : Construire et déployer**

Garde-fou local d'abord — le workflow CI utilise un `--base-href` que le build local n'a pas besoin de
reproduire, mais une erreur de compilation web se verrait ici :

Run: `flutter build web --release`

Le déploiement est ensuite **automatique** : `.github/workflows/deploy-pages.yml` se déclenche sur
tout push vers `spike/web-audio-engine`, construit avec `--base-href /woodshed/` et publie sur GitHub
Pages.

```bash
git push
```

Attendre la fin du workflow (onglet Actions) avant de tester sur l'iPhone — sinon on teste la version
précédente.

- [ ] **Step 2 : Contourner le cache de la PWA**

La police est un **nouvel asset** : sans cette précaution on teste l'ancienne version. Ouvrir l'URL
dans un **onglet privé Safari**, ou désinstaller puis réinstaller la PWA depuis l'écran d'accueil.
Vérifier au passage qu'aucun texte ne s'affiche en police système (signe que l'asset n'a pas été
récupéré).

- [ ] **Step 3 : Contrôler l'absence de scroll**

En PWA installée et en Safari avec ses barres, vérifier que **tous** les contrôles — jusqu'au slider
de volume — sont visibles sans faire défiler. Si le volume est coupé, réduire la borne haute de la
waveform (`clamp(96.0, 180.0)` → `clamp(96.0, 150.0)`) plutôt que de rogner les cibles tactiles.

- [ ] **Step 4 : Essayer dans la voiture**

Téléphone à sa place habituelle, moteur à l'arrêt d'abord. Toucher play/pause, ±10 s et redémarrage
**sans viser précisément**. Lire pitch et vitesse d'un coup d'œil. Noter tout bouton manqué.

- [ ] **Step 5 : Ajuster si besoin**

Les tailles viennent d'un calcul de place, pas d'un essai. Chaque widget regroupe ses constantes en
tête (`TransportBar.height`, `PitchStepper._buttonSize`, `SpeedSelector._height`) : un ajustement est
une modification d'une ligne. Si le transport passe au-dessus de 76 px, mettre `_fixedBodyHeight` à
jour dans `player_page.dart` **et** dans la spec §7 — sinon le seuil de scroll devient faux.

- [ ] **Step 6 : Commit d'éventuels ajustements**

```bash
git add -u
git commit -m "polish(player): ajustement des tailles apres essai reel"
```

Si aucun ajustement n'est nécessaire, sauter ce commit.

---

## Écarts assumés par rapport à la demande initiale

À rappeler en fin d'implémentation, ils sont volontaires et documentés dans la spec :

1. **Boutons de vitesse pleine largeur** au lieu d'un groupe centré plus étroit — quatre cibles de ~80 px valent mieux que des marges perdues en voiture. Le résultat reste symétrique.
2. **Labels de pitch au-dessus** des contrôles au lieu d'en ligne — la ligne complète déborderait à 320 px de large avec des boutons de 64 px.
3. **Perte définitive du 0.5x** — plus aucun palier sous 0.75x pour déchiffrer un passage très rapide.
