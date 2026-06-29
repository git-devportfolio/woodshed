# Boucle A/B + waveform — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Afficher la waveform du morceau, y poser une boucle A/B par poignées glissables, boucler la lecture entre A et B (sans micro-coupure), persister la boucle par morceau, et ajouter une commande +10 s.

**Architecture:** Le bouclage de segment s'appuie sur `loopStart`/`loopEnd`/`loop` natifs de l'`AudioBufferSourceNode` (piloté via la façade JS + les 3 backends). Les pics de waveform sont calculés en JS depuis le buffer déjà décodé et exposés à Dart pour un `CustomPainter`. `TrackSettings` gagne `loopA/loopB/loopEnabled` (persistés). `PlayerController` orchestre, `WaveformView` est le widget interactif.

**Tech Stack:** Flutter web (Dart 3.12), Web Audio (AudioBufferSourceNode loop), `idb_shim` (persistance existante), CustomPainter.

**Référence spec :** `docs/superpowers/specs/2026-06-16-boucle-ab-waveform-design.md`

## Global Constraints

- Flutter web uniquement ; cible PWA iPhone. Respecter `flutter_lints`.
- Texte UI et commentaires en **français** ; identifiants en **anglais**.
- L'UI passe par l'interface `AudioEngine` ; le code Web Audio reste derrière la façade JS.
- Build local Windows : préfixer `MSYS_NO_PATHCONV=1 flutter build web --release --base-href /woodshed/`.
- Écart minimal boucle : `minGap = 0,2 s` (200 ms) entre A et B.
- Pas de backend/réseau ; persistance locale IndexedDB.

---

## Task 1 : `TrackSettings` — champs de boucle (TDD)

**Files:**
- Modify: `lib/core/library/track.dart`
- Test: `test/track_test.dart`

**Interfaces:**
- Produces: `TrackSettings` gagne `double? loopA; double? loopB; bool loopEnabled;` (constructeur avec `loopEnabled = false` par défaut, loopA/loopB null). `toJson` ajoute les 3 clés ; `fromJson` les lit avec tolérance aux clés absentes.

- [ ] **Step 1 : Écrire les tests (échouent)**

Ajouter dans `test/track_test.dart`, dans `main()` :
```dart
  test('TrackSettings round-trip avec boucle', () {
    final s = TrackSettings(
      pitchSemitones: 2, speed: 0.75, volume: 0.5,
      loopA: 12.5, loopB: 40.0, loopEnabled: true,
    );
    final back = TrackSettings.fromJson(s.toJson());
    expect(back.loopA, 12.5);
    expect(back.loopB, 40.0);
    expect(back.loopEnabled, true);
  });

  test('TrackSettings.fromJson sans champs boucle (rétrocompat)', () {
    final s = TrackSettings.fromJson({'pitchSemitones': 0, 'speed': 1.0, 'volume': 1.0});
    expect(s.loopA, isNull);
    expect(s.loopB, isNull);
    expect(s.loopEnabled, false);
  });
```

- [ ] **Step 2 : Lancer (échoue)** — `flutter test test/track_test.dart` → FAIL (`loopA` n'existe pas).

- [ ] **Step 3 : Implémenter** — dans `lib/core/library/track.dart`, modifier `TrackSettings` :
```dart
class TrackSettings {
  TrackSettings({
    this.pitchSemitones = 0,
    this.speed = 1.0,
    this.volume = 1.0,
    this.loopA,
    this.loopB,
    this.loopEnabled = false,
  });

  double pitchSemitones;
  double speed;
  double volume;
  double? loopA; // secondes, null = non défini (→ 0)
  double? loopB; // secondes, null = non défini (→ durée)
  bool loopEnabled;

  Map<String, dynamic> toJson() => {
        'pitchSemitones': pitchSemitones,
        'speed': speed,
        'volume': volume,
        'loopA': loopA,
        'loopB': loopB,
        'loopEnabled': loopEnabled,
      };

  factory TrackSettings.fromJson(Map json) => TrackSettings(
        pitchSemitones: (json['pitchSemitones'] as num?)?.toDouble() ?? 0,
        speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
        volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
        loopA: (json['loopA'] as num?)?.toDouble(),
        loopB: (json['loopB'] as num?)?.toDouble(),
        loopEnabled: (json['loopEnabled'] as bool?) ?? false,
      );
}
```

- [ ] **Step 4 : Lancer (passe)** — `flutter test test/track_test.dart` → PASS (tous, dont les 2 nouveaux).
- [ ] **Step 5 : Analyse** — `flutter analyze` → `No issues found!`
- [ ] **Step 6 : Commit**
```bash
git add lib/core/library/track.dart test/track_test.dart
git commit -m "feat(library): TrackSettings loopA/loopB/loopEnabled (persistance boucle)"
```

---

## Task 2 : Moteur — bouclage de segment (`setLoopRange` + `setLoop`)

But : la lecture boucle entre A et B. Validé par `flutter analyze` + `flutter build web` (audio jugé sur appareil).

**Files:**
- Modify: `web/audio/facade.js`, `web/audio/backend-plain.js`, `web/audio/backend-soundtouch.js`, `web/audio/backend-rubberband.js`
- Modify: `lib/core/audio/web_audio_engine.dart`

**Interfaces:**
- Consumes: l'`AudioEngine` existant (`setLoop(bool)` déjà présent ; `setLoopRange` lève actuellement `UnimplementedError`).
- Produces: `WebAudioEngine.setLoopRange(Duration a, Duration b)` réel ; façade `setLoopRange(aSec, bSec)` + `setLoop(on)` qui pilotent `src.loopStart/loopEnd/loop` ; état boucle réinjecté dans `setEngine`.

- [ ] **Step 1 : Façade — état boucle + `setLoopRange` + réinjection (`web/audio/facade.js`)**

Lire le fichier. Ajouter trois variables d'état près des autres `let` en haut de l'IIFE :
```js
  let loopAsec = 0;          // borne A (s) ; 0 par défaut
  let loopBsec = 0;          // borne B (s) ; 0 = fin du buffer (boucle morceau entier)
  let loopOn = false;        // bouclage actif
```
Ajouter/мodifier les méthodes de `window.woodshedAudio` :
```js
    setLoop(on) { loopOn = on; backend && backend.setLoop(on); },
    setLoopRange(aSec, bSec) { loopAsec = aSec; loopBsec = bSec; backend && backend.setLoopRange(aSec, bSec); },
```
(Si une ancienne `setLoop` existe déjà, la remplacer par celle-ci.) Dans `setEngine`, après `backend = await factory(ctx, masterGain);` et la réinjection tempo/pitch existante, **réinjecter aussi la boucle** :
```js
      backend.setLoopRange(loopAsec, loopBsec);
      backend.setLoop(loopOn);
```

- [ ] **Step 2 : Backends — appliquer `loopStart/loopEnd/loop` à la source**

Pour CHACUN des 3 backends (`backend-plain.js`, `backend-soundtouch.js`, `backend-rubberband.js`), lire le fichier puis :
- Ajouter l'état près des autres `let` : `let loopStartSec = 0, loopEndSec = 0, loopOn = false;` (si une variable `loop` existait pour un bouclage morceau-entier, la remplacer par `loopOn`).
- Dans la fonction qui crée la source (`startFrom`), juste après `src = ctx.createBufferSource(); src.buffer = buffer;`, appliquer :
```js
    src.loop = loopOn;
    src.loopStart = loopStartSec;
    src.loopEnd = loopEndSec;
```
- Remplacer/ajouter dans l'objet retourné :
```js
    setLoop(on) { loopOn = on; if (src) src.loop = on; },
    setLoopRange(a, b) { loopStartSec = a; loopEndSec = b; if (src) { src.loopStart = a; src.loopEnd = b; } },
```
(Pour `backend-plain.js` qui avait déjà un `setLoop(l){ loop=l; if(src) src.loop=l; }`, le remplacer par la version `loopOn` ci-dessus et ajouter `setLoopRange`.)

- [ ] **Step 3 : `WebAudioEngine` — implémenter `setLoopRange` (`lib/core/audio/web_audio_engine.dart`)**

Ajouter à l'extension type `_Facade` : `external void setLoopRange(double aSec, double bSec);` (la façade a déjà `setLoop` external). Remplacer l'override qui lève :
```dart
  @override
  Future<void> setLoopRange(Duration a, Duration b) async =>
      _facade.setLoopRange(a.inMilliseconds / 1000.0, b.inMilliseconds / 1000.0);
```
Vérifier que `setLoop` proxy existe déjà (`Future<void> setLoop(bool loop) async => _facade.setLoop(loop);`) — sinon l'ajouter.

- [ ] **Step 4 : Vérifier**
```
flutter analyze            # No issues found!
flutter test               # tous verts
MSYS_NO_PATHCONV=1 flutter build web --release --base-href /woodshed/   # succès
```
(Audio jugé sur appareil ultérieurement.)

- [ ] **Step 5 : Commit**
```bash
git add web/audio/ lib/core/audio/web_audio_engine.dart
git commit -m "feat(audio): bouclage de segment A/B (loopStart/loopEnd natifs)"
```

---

## Task 3 : Waveform — calcul des pics (façade) + exposition Dart

But : exposer ~800 pics normalisés du morceau chargé. Validé par analyze + build.

**Files:**
- Modify: `web/audio/facade.js`
- Modify: `lib/core/audio/web_audio_engine.dart`

**Interfaces:**
- Produces: façade `getPeaks()` → tableau JS de nombres [0,1] (longueur ≤ 800) ; `WebAudioEngine.waveformPeaks` → `List<double>`.

- [ ] **Step 1 : Façade — calculer les pics au `load` (`web/audio/facade.js`)**

Ajouter une variable d'état `let peaks = [];` en haut. Ajouter la fonction de calcul dans l'IIFE :
```js
  function computePeaks(buf, buckets) {
    const len = buf.length;
    const ch0 = buf.getChannelData(0);
    const ch1 = buf.numberOfChannels > 1 ? buf.getChannelData(1) : null;
    const out = new Array(buckets).fill(0);
    const block = Math.max(1, Math.floor(len / buckets));
    let maxAll = 1e-6;
    for (let b = 0; b < buckets; b++) {
      let m = 0;
      const start = b * block;
      const end = Math.min(len, start + block);
      for (let i = start; i < end; i++) {
        let v = Math.abs(ch0[i]);
        if (ch1) { const v1 = Math.abs(ch1[i]); if (v1 > v) v = v1; }
        if (v > m) m = v;
      }
      out[b] = m;
      if (m > maxAll) maxAll = m;
    }
    for (let b = 0; b < buckets; b++) out[b] = out[b] / maxAll;
    return out;
  }
```
Dans `load(...)`, juste après l'obtention de `decoded` (le buffer décodé) et avant/après `backend.load(decoded)`, calculer :
```js
      peaks = computePeaks(decoded, 800);
```
Ajouter à l'objet `window.woodshedAudio` : `getPeaks() { return peaks; },`.

- [ ] **Step 2 : `WebAudioEngine` — exposer les pics (`lib/core/audio/web_audio_engine.dart`)**

Ajouter à `_Facade` : `external JSArray<JSNumber> getPeaks();`. Ajouter un getter :
```dart
  /// Pics de waveform normalisés [0,1] du morceau courant (≈800 points).
  List<double> get waveformPeaks =>
      _facade.getPeaks().toDart.map((e) => e.toDartDouble).toList();
```
(`import 'dart:js_interop'` est déjà présent ; `JSArray`/`JSNumber` en proviennent.)

- [ ] **Step 3 : Vérifier**
```
flutter analyze            # No issues found!
MSYS_NO_PATHCONV=1 flutter build web --release --base-href /woodshed/   # succès
```

- [ ] **Step 4 : Commit**
```bash
git add web/audio/facade.js lib/core/audio/web_audio_engine.dart
git commit -m "feat(audio): calcul + exposition des pics de waveform"
```

---

## Task 4 : `PlayerController` — boucle + `forward10s` (TDD)

**Files:**
- Modify: `lib/features/player/player_controller.dart`
- Test: `test/player_controller_test.dart`

**Interfaces:**
- Consumes: `AudioEngine.setLoopRange(Duration,Duration)`, `setLoop(bool)` (Task 2) ; `Track.durationMs`, `TrackSettings.loopA/loopB/loopEnabled` (Task 1).
- Produces: `PlayerController` gagne getters `Duration get loopA`, `Duration get loopB`, `bool get loopEnabled` et méthodes `setLoopA(Duration)`, `setLoopB(Duration)`, `toggleLoop()`, `forward10s(Duration current)` ; `applySettings()` réapplique la boucle.

- [ ] **Step 1 : Écrire les tests (échouent)** — dans `test/player_controller_test.dart` :

Étendre `FakeEngine` (champs + override de boucle) — ajouter à la classe :
```dart
  Duration? loopA, loopB;
  bool loopEnabled = false;
  @override
  Future<void> setLoopRange(Duration a, Duration b) async { loopA = a; loopB = b; }
  @override
  Future<void> setLoop(bool on) async { loopEnabled = on; }
```
(Supprimer l'ancien `setLoopRange`/`setLoop` vide s'il existe pour éviter le doublon.)

Ajouter dans `main()` (le `_track()` a `durationMs: 240000` = 240 s) :
```dart
  test('setLoopA borne dans [0, B - 0.2s] et délègue au moteur', () async {
    final engine = FakeEngine();
    final c = PlayerController(engine, FakeRepo(), _track());
    await c.setLoopB(const Duration(seconds: 40));
    await c.setLoopA(const Duration(seconds: 30));
    expect(c.loopA, const Duration(seconds: 30));
    expect(engine.loopA, const Duration(seconds: 30));
    await c.setLoopA(const Duration(seconds: -5)); // sous 0
    expect(c.loopA, Duration.zero);
    await c.setLoopA(const Duration(seconds: 100)); // au-delà de B-0.2
    expect(c.loopA, const Duration(seconds: 40) - const Duration(milliseconds: 200));
  });

  test('setLoopB borne dans [A + 0.2s, durée]', () async {
    final engine = FakeEngine();
    final c = PlayerController(engine, FakeRepo(), _track());
    await c.setLoopB(const Duration(minutes: 10)); // au-delà de la durée
    expect(c.loopB, const Duration(milliseconds: 240000));
  });

  test('toggleLoop bascule et délègue', () async {
    final engine = FakeEngine();
    final c = PlayerController(engine, FakeRepo(), _track());
    await c.toggleLoop();
    expect(c.loopEnabled, true);
    expect(engine.loopEnabled, true);
  });

  test('forward10s borné à la durée', () async {
    final c = PlayerController(FakeEngine(), FakeRepo(), _track());
    await c.forward10s(const Duration(seconds: 100));
    expect(c.lastSeekTarget, const Duration(seconds: 110));
    await c.forward10s(const Duration(seconds: 238));
    expect(c.lastSeekTarget, const Duration(milliseconds: 240000)); // borné
  });

  test('applySettings réapplique la boucle', () async {
    final engine = FakeEngine();
    final t = _track();
    t.settings.loopA = 10; t.settings.loopB = 20; t.settings.loopEnabled = true;
    final c = PlayerController(engine, FakeRepo(), t);
    await c.applySettings();
    expect(engine.loopA, const Duration(seconds: 10));
    expect(engine.loopB, const Duration(seconds: 20));
    expect(engine.loopEnabled, true);
  });
```

- [ ] **Step 2 : Lancer (échoue)** — `flutter test test/player_controller_test.dart` → FAIL.

- [ ] **Step 3 : Implémenter** — dans `lib/features/player/player_controller.dart`, ajouter (après les getters pitch/speed/volume) :
```dart
  static const _minGap = Duration(milliseconds: 200);
  Duration get _duration => Duration(milliseconds: track.durationMs);

  Duration get loopA => Duration(
      milliseconds: ((track.settings.loopA ?? 0) * 1000).round());
  Duration get loopB => track.settings.loopB == null
      ? _duration
      : Duration(milliseconds: (track.settings.loopB! * 1000).round());
  bool get loopEnabled => track.settings.loopEnabled;

  Future<void> setLoopA(Duration a) async {
    final maxA = loopB - _minGap;
    var v = a;
    if (v < Duration.zero) v = Duration.zero;
    if (v > maxA) v = maxA < Duration.zero ? Duration.zero : maxA;
    track.settings.loopA = v.inMilliseconds / 1000.0;
    await _engine.setLoopRange(loopA, loopB);
    _scheduleSave();
    notifyListeners();
  }

  Future<void> setLoopB(Duration b) async {
    final minB = loopA + _minGap;
    var v = b;
    if (v > _duration) v = _duration;
    if (v < minB) v = minB > _duration ? _duration : minB;
    track.settings.loopB = v.inMilliseconds / 1000.0;
    await _engine.setLoopRange(loopA, loopB);
    _scheduleSave();
    notifyListeners();
  }

  Future<void> toggleLoop() async {
    track.settings.loopEnabled = !track.settings.loopEnabled;
    await _engine.setLoop(track.settings.loopEnabled);
    _scheduleSave();
    notifyListeners();
  }

  Future<void> forward10s(Duration current) async {
    final target = current + const Duration(seconds: 10);
    await seek(target > _duration ? _duration : target);
  }
```
Et dans `applySettings()`, après les setPitch/setSpeed/setVolume existants, ajouter :
```dart
    await _engine.setLoopRange(loopA, loopB);
    await _engine.setLoop(loopEnabled);
```

- [ ] **Step 4 : Lancer (passe)** — `flutter test test/player_controller_test.dart` → PASS.
- [ ] **Step 5 : Analyse** — `flutter analyze` → clean.
- [ ] **Step 6 : Commit**
```bash
git add lib/features/player/player_controller.dart test/player_controller_test.dart
git commit -m "feat(player): boucle A/B + forward10s dans le controleur (TDD)"
```

---

## Task 5 : `WaveformView` (widget CustomPainter)

But : widget réutilisable affichant pics + tête de lecture + zone A/B + poignées, avec gestes tap/drag. Validé par analyze + build.

**Files:**
- Create: `lib/features/player/waveform_view.dart`

**Interfaces:**
- Produces: `WaveformView` widget :
```dart
WaveformView({
  required List<double> peaks,
  required Duration duration,
  required Duration position,
  required Duration loopA,
  required Duration loopB,
  required bool loopEnabled,
  required ValueChanged<Duration> onSeek,
  required ValueChanged<Duration> onSetA,
  required ValueChanged<Duration> onSetB,
})
```

- [ ] **Step 1 : Implémenter** — `lib/features/player/waveform_view.dart` :
```dart
import 'package:flutter/material.dart';

/// Waveform interactive : pics, tête de lecture, zone de boucle [A,B] + poignées.
/// Tap = seek ; glisser une poignée = régler A ou B.
class WaveformView extends StatefulWidget {
  const WaveformView({
    super.key,
    required this.peaks,
    required this.duration,
    required this.position,
    required this.loopA,
    required this.loopB,
    required this.loopEnabled,
    required this.onSeek,
    required this.onSetA,
    required this.onSetB,
    this.height = 120,
  });

  final List<double> peaks;
  final Duration duration;
  final Duration position;
  final Duration loopA;
  final Duration loopB;
  final bool loopEnabled;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<Duration> onSetA;
  final ValueChanged<Duration> onSetB;
  final double height;

  @override
  State<WaveformView> createState() => _WaveformViewState();
}

enum _Handle { none, a, b }

class _WaveformViewState extends State<WaveformView> {
  _Handle _dragging = _Handle.none;

  double _timeToX(Duration t, double width) {
    final ms = widget.duration.inMilliseconds;
    if (ms == 0) return 0;
    return (t.inMilliseconds / ms) * width;
  }

  Duration _xToTime(double x, double width) {
    if (width == 0) return Duration.zero;
    final frac = (x / width).clamp(0.0, 1.0);
    return Duration(milliseconds: (frac * widget.duration.inMilliseconds).round());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const touch = 24.0; // tolérance tactile autour d'une poignée
        return GestureDetector(
          onTapDown: (d) => widget.onSeek(_xToTime(d.localPosition.dx, width)),
          onHorizontalDragStart: (d) {
            final x = d.localPosition.dx;
            final ax = _timeToX(widget.loopA, width);
            final bx = _timeToX(widget.loopB, width);
            if ((x - ax).abs() <= touch) {
              _dragging = _Handle.a;
            } else if ((x - bx).abs() <= touch) {
              _dragging = _Handle.b;
            } else {
              _dragging = _Handle.none;
            }
          },
          onHorizontalDragUpdate: (d) {
            if (_dragging == _Handle.none) return;
            final t = _xToTime(d.localPosition.dx, width);
            if (_dragging == _Handle.a) {
              widget.onSetA(t);
            } else if (_dragging == _Handle.b) {
              widget.onSetB(t);
            }
          },
          onHorizontalDragEnd: (_) => _dragging = _Handle.none,
          child: CustomPaint(
            size: Size(width, widget.height),
            painter: _WaveformPainter(
              peaks: widget.peaks,
              duration: widget.duration,
              position: widget.position,
              loopA: widget.loopA,
              loopB: widget.loopB,
              loopEnabled: widget.loopEnabled,
              waveColor: scheme.primary.withValues(alpha: 0.6),
              loopColor: scheme.tertiary.withValues(alpha: 0.25),
              handleColor: scheme.tertiary,
              playheadColor: scheme.error,
            ),
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.peaks,
    required this.duration,
    required this.position,
    required this.loopA,
    required this.loopB,
    required this.loopEnabled,
    required this.waveColor,
    required this.loopColor,
    required this.handleColor,
    required this.playheadColor,
  });

  final List<double> peaks;
  final Duration duration;
  final Duration position;
  final Duration loopA;
  final Duration loopB;
  final bool loopEnabled;
  final Color waveColor, loopColor, handleColor, playheadColor;

  double _x(Duration t, double w) {
    final ms = duration.inMilliseconds;
    return ms == 0 ? 0 : (t.inMilliseconds / ms) * w;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;

    // Zone de boucle
    final ax = _x(loopA, size.width);
    final bx = _x(loopB, size.width);
    canvas.drawRect(
      Rect.fromLTRB(ax, 0, bx, size.height),
      Paint()..color = loopColor,
    );

    // Pics
    if (peaks.isNotEmpty) {
      final bw = size.width / peaks.length;
      final wave = Paint()..color = waveColor;
      for (var i = 0; i < peaks.length; i++) {
        final h = (peaks[i] * mid).clamp(1.0, mid);
        final x = i * bw;
        canvas.drawRect(Rect.fromLTRB(x, mid - h, x + bw * 0.8, mid + h), wave);
      }
    }

    // Poignées A et B
    final handle = Paint()
      ..color = handleColor
      ..strokeWidth = loopEnabled ? 3 : 2;
    canvas.drawLine(Offset(ax, 0), Offset(ax, size.height), handle);
    canvas.drawLine(Offset(bx, 0), Offset(bx, size.height), handle);
    canvas.drawCircle(Offset(ax, 8), 6, handle);
    canvas.drawCircle(Offset(bx, size.height - 8), 6, handle);

    // Tête de lecture
    final px = _x(position, size.width);
    canvas.drawLine(
      Offset(px, 0),
      Offset(px, size.height),
      Paint()
        ..color = playheadColor
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.position != position ||
      old.loopA != loopA ||
      old.loopB != loopB ||
      old.loopEnabled != loopEnabled ||
      !identical(old.peaks, peaks);
}
```

- [ ] **Step 2 : Vérifier**
```
flutter analyze            # No issues found!
MSYS_NO_PATHCONV=1 flutter build web --release --base-href /woodshed/   # succès
```
(Si `withValues` n'est pas dispo dans la version Flutter, utiliser `withOpacity` — vérifier et adapter.)

- [ ] **Step 3 : Commit**
```bash
git add lib/features/player/waveform_view.dart
git commit -m "feat(player): WaveformView (pics + tete de lecture + zone A/B + poignees)"
```

---

## Task 6 : Intégrer dans `PlayerPage` (waveform + toggle boucle + +10 s)

**Files:**
- Modify: `lib/features/player/player_page.dart`

**Interfaces:**
- Consumes: `WaveformView` (Task 5), `WebAudioEngine.waveformPeaks` (Task 3), `PlayerController.{loopA,loopB,loopEnabled,setLoopA,setLoopB,toggleLoop,forward10s}` (Task 4).

- [ ] **Step 1 : Remplacer le `Slider` de position par la `WaveformView`**

Lire `player_page.dart`. Ajouter l'import `import 'waveform_view.dart';`. Ajouter un champ d'état `List<double> _peaks = const [];`. Dans `_loadAndPlay()`, après `await widget.engine.load(bytes)...` et le reset de position, lire les pics :
```dart
      _peaks = widget.engine.waveformPeaks;
```
(dans le `setState` qui suit le load, ou un `setState` dédié avant `applySettings`.)

Dans `build`, REMPLACER le `Slider` de position (et son `onChangeStart/Changed/End`) par :
```dart
                    WaveformView(
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
```
(Garder la ligne de temps `Text('${_fmt(...)} / ${_fmt(total)}')` sous la waveform. Le `_scrubbing`/`_scrubValue` du slider ne sont plus utilisés pour la position — la waveform gère le seek au tap ; tu peux retirer ces deux champs et leur usage dans le listener de position s'ils deviennent inutilisés, sinon laisser le guard `!_scrubbing` est sans effet.)

- [ ] **Step 2 : Ajouter le toggle boucle et le bouton +10 s à la barre de transport**

Dans la `Row` de transport, ajouter un bouton boucle (à gauche) et un +10 s (à droite, après restart) :
```dart
                        IconButton(
                          iconSize: 28,
                          tooltip: _c.loopEnabled ? 'Boucle activée' : 'Boucle désactivée',
                          isSelected: _c.loopEnabled,
                          onPressed: _c.toggleLoop,
                          icon: const Icon(Icons.repeat),
                        ),
                        // … −10 s, play/pause, restart existants …
                        IconButton(
                          iconSize: 32,
                          tooltip: '+10 s',
                          onPressed: () => _c.forward10s(_position),
                          icon: const Icon(Icons.forward_10),
                        ),
```
(Placer le toggle boucle au début de la Row et le +10 s à la fin.)

- [ ] **Step 3 : Vérifier**
```
flutter analyze            # No issues found!
flutter test               # tous verts
MSYS_NO_PATHCONV=1 flutter build web --release --base-href /woodshed/   # succès
```

- [ ] **Step 4 : Commit**
```bash
git add lib/features/player/player_page.dart
git commit -m "feat(player): waveform interactive + toggle boucle + bouton +10s"
```

---

## Task 7 : Validation sur appareil (manuelle)

Après déploiement (push → GitHub Pages), sur iPhone (cache PWA vidé) :
- [ ] Ouvrir un morceau → la **waveform s'affiche**, la tête de lecture avance.
- [ ] **Glisser A et B** → la zone se met à jour ; **tap** sur la waveform → la lecture saute là.
- [ ] **Activer ⟲** → la lecture **boucle proprement** entre A et B (pas de clic/coupure).
- [ ] **+10 s** / **−10 s** déplacent la lecture, bornés aux extrémités.
- [ ] Quitter → rouvrir le morceau → **A, B et l'état de boucle sont retrouvés** ; la liste reflète les réglages.
- [ ] Cumuler avec pitch/vitesse → la boucle reste correcte.

Consigner tout souci ; sinon l'incrément est livré.

---

## Notes d'exécution

- **Testé automatiquement** : `TrackSettings` (JSON + rétrocompat), `PlayerController` (bornage boucle, forward10s, applySettings). Le reste (Web Audio loop, calcul de pics, rendu/gestes waveform) est validé **manuellement** (Task 7).
- **Décodage unique** : les pics réutilisent le buffer déjà décodé par la façade (pas de coût ajouté).
- **`setEngine` réinjecte la boucle** (Task 2 Step 1) pour survivre à un changement de moteur.
