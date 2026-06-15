# Spike moteur audio web (PWA) — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construire une mini-PWA Flutter qui charge un fichier audio local et applique transposition (±6 demi-tons) et vitesse (0.5/0.75/1.0) en temps réel, pour juger à l'oreille sur un iPhone si SoundTouch (puis, sous plafond, Rubber Band) sonne assez bien dans Safari iOS.

**Architecture:** Tout le code Web Audio vit derrière une **façade JS maison à contrat fixe** (`window.woodshedAudio`). Côté Dart, l'interface `AudioEngine` est implémentée par `WebAudioEngine`, simple proxy js_interop vers cette façade. La façade branche successivement trois backends interchangeables : `plain` (lecture brute, valide la plomberie), `soundtouch` (worklet), `rubberband` (worklet, plafonné). La logique pure (maths de pitch, état du contrôleur) est en Dart testable hors navigateur.

**Tech Stack:** Flutter web (Dart 3.12), `package:web` + `dart:js_interop`, Web Audio API + AudioWorklet, `@soundtouchjs/audio-worklet`, `file_picker`, GitHub Pages + GitHub Actions, `coi-serviceworker` (Rubber Band uniquement).

**Référence spec :** `docs/superpowers/specs/2026-06-15-spike-moteur-audio-web-pwa-design.md`

---

## Carte des fichiers

```
lib/
  core/audio/
    audio_engine.dart        # interface AudioEngine (pur Dart, testable)
    engine_kind.dart         # enum EngineKind { plain, soundTouch, rubberBand }
    pitch_math.dart          # conversions pures demi-tons<->ratio, bornage (testable)
    web_audio_engine.dart    # impl. AudioEngine -> proxy js_interop vers window.woodshedAudio
  features/spike/
    spike_controller.dart    # état UI (ChangeNotifier) : pitch, vitesse, moteur, lecture
    spike_page.dart          # UI minimale
  main.dart                  # remplace le compteur par SpikePage
web/
  audio/
    facade.js                # window.woodshedAudio : contrat stable + routage backends
    backend-plain.js         # backend 'plain' (AudioBufferSourceNode, sans pitch)
    backend-soundtouch.js    # backend 'soundtouch'
    backend-rubberband.js    # backend 'rubberband' (Task 6)
  vendor/soundtouch/         # fichiers dist vendorisés (Task 4)
  coi-serviceworker.min.js   # (Task 6 uniquement)
  index.html                 # charge facade.js + backends
test/
  pitch_math_test.dart
  spike_controller_test.dart
.github/workflows/
  deploy-pages.yml           # build + déploiement GitHub Pages
docs/superpowers/
  2026-06-15-verdict-moteur-web.md   # rédigé en Task 7
```

---

## Task 1 : Cœur pur Dart — maths de pitch

**Files:**
- Create: `lib/core/audio/pitch_math.dart`
- Test: `test/pitch_math_test.dart`
- Modify: `pubspec.yaml` (ajouter `web`)

- [ ] **Step 1 : Ajouter la dépendance `web`**

Dans `pubspec.yaml`, sous `dependencies:` (après `file_picker`), ajouter :

```yaml
  web: ^1.1.0
```

Puis lancer :

```bash
flutter pub get
```
Expected : résolution OK, `web` ajouté.

- [ ] **Step 2 : Écrire le test qui échoue**

Créer `test/pitch_math_test.dart` :

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed/core/audio/pitch_math.dart';

void main() {
  group('semitonesToRatio', () {
    test('0 demi-ton => ratio 1.0', () {
      expect(semitonesToRatio(0), closeTo(1.0, 1e-9));
    });
    test('+12 demi-tons => ratio 2.0 (une octave plus haut)', () {
      expect(semitonesToRatio(12), closeTo(2.0, 1e-9));
    });
    test('-12 demi-tons => ratio 0.5 (une octave plus bas)', () {
      expect(semitonesToRatio(-12), closeTo(0.5, 1e-9));
    });
    test('+6 demi-tons => ~1.41421', () {
      expect(semitonesToRatio(6), closeTo(1.41421356, 1e-6));
    });
  });

  group('clampSemitones', () {
    test('borne haute à +6', () => expect(clampSemitones(10), 6.0));
    test('borne basse à -6', () => expect(clampSemitones(-10), -6.0));
    test('laisse passer une valeur interne', () => expect(clampSemitones(3), 3.0));
  });
}
```

- [ ] **Step 3 : Lancer le test pour vérifier qu'il échoue**

Run : `flutter test test/pitch_math_test.dart`
Expected : FAIL — `Target of URI doesn't exist: 'package:woodshed/core/audio/pitch_math.dart'`.

- [ ] **Step 4 : Implémenter le minimum**

Créer `lib/core/audio/pitch_math.dart` :

```dart
import 'dart:math' as math;

/// Convertit un nombre de demi-tons en ratio de fréquence : 2^(n/12).
double semitonesToRatio(double semitones) =>
    math.pow(2, semitones / 12).toDouble();

/// Borne le pitch à l'intervalle autorisé par le spike : [-6, +6] demi-tons.
double clampSemitones(double semitones) => semitones.clamp(-6.0, 6.0);
```

- [ ] **Step 5 : Lancer le test pour vérifier qu'il passe**

Run : `flutter test test/pitch_math_test.dart`
Expected : PASS (7 tests).

- [ ] **Step 6 : Analyse statique**

Run : `flutter analyze`
Expected : `No issues found!`

- [ ] **Step 7 : Commit**

```bash
git add pubspec.yaml pubspec.lock lib/core/audio/pitch_math.dart test/pitch_math_test.dart
git commit -m "feat(audio): maths de pitch (demi-tons<->ratio) + dep web"
```

---

## Task 2 : Interface `AudioEngine`, façade JS (backend `plain`) et `WebAudioEngine`

But : valider toute la plomberie (file_picker → décodage → lecture) **sans pitch**, avant d'ajouter la complexité worklet.

**Files:**
- Create: `lib/core/audio/audio_engine.dart`
- Create: `lib/core/audio/engine_kind.dart`
- Create: `lib/core/audio/web_audio_engine.dart`
- Create: `web/audio/facade.js`
- Create: `web/audio/backend-plain.js`
- Modify: `web/index.html`

- [ ] **Step 1 : Définir l'enum des moteurs**

Créer `lib/core/audio/engine_kind.dart` :

```dart
/// Backends audio disponibles côté web, dans l'ordre d'intégration du spike.
enum EngineKind {
  /// Lecture brute (AudioBufferSourceNode), sans transposition. Valide la plomberie.
  plain,
  /// SoundTouch via AudioWorklet.
  soundTouch,
  /// Rubber Band via AudioWorklet (plafonné, cf. spec §7).
  rubberBand,
}

extension EngineKindId on EngineKind {
  /// Identifiant passé à la façade JS.
  String get jsId => switch (this) {
        EngineKind.plain => 'plain',
        EngineKind.soundTouch => 'soundtouch',
        EngineKind.rubberBand => 'rubberband',
      };
}
```

- [ ] **Step 2 : Définir l'interface `AudioEngine` (pur Dart)**

Créer `lib/core/audio/audio_engine.dart`. Interface déclarée « entière » (cf. doc d'archi) ; le web n'implémente que le sous-ensemble du spike.

```dart
import 'dart:typed_data';
import 'engine_kind.dart';

/// Moteur audio abstrait. Isole l'app du moteur concret (Web Audio, Android…).
abstract class AudioEngine {
  /// Charge des octets audio (fichier local décodé).
  Future<void> load(Uint8List bytes);

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);

  /// Vitesse sans altérer la tonalité (0.5 / 0.75 / 1.0).
  Future<void> setSpeed(double rate);

  /// Transposition en demi-tons (-6 .. +6).
  Future<void> setPitch(double semitones);

  /// Active/désactive la boucle sur le morceau entier.
  Future<void> setLoop(bool loop);

  /// Change de backend à chaud (conserve position/pitch/vitesse côté façade).
  Future<void> setEngine(EngineKind kind);

  /// Position courante (pour le curseur UI).
  Stream<Duration> get position;

  /// Durée totale du morceau chargé.
  Duration get duration;

  /// Nombre de glitches (buffer underruns) remontés par le backend, si dispo.
  int get glitchCount;

  Future<void> dispose();

  // --- Hors périmètre du spike (déclarés pour l'archi, non implémentés sur web) ---
  Future<void> setVolume(double volume);
  Future<void> setLoopRange(Duration a, Duration b);
}
```

- [ ] **Step 3 : Écrire le contrat de la façade JS (backend `plain`)**

Créer `web/audio/facade.js`. C'est LE contrat stable auquel le Dart se lie.

```js
// window.woodshedAudio : façade audio stable pour l'app Flutter.
// Route vers un backend interchangeable ('plain' | 'soundtouch' | 'rubberband').
(function () {
  let ctx = null;            // AudioContext
  let decoded = null;        // AudioBuffer décodé
  let backend = null;        // backend actif
  let backendId = 'plain';
  let positionCb = null;
  let pollTimer = null;

  const backends = {};       // rempli par les fichiers backend-*.js
  window.woodshedAudioRegisterBackend = (id, factory) => { backends[id] = factory; };

  function startPolling() {
    stopPolling();
    pollTimer = setInterval(() => {
      if (backend && positionCb) positionCb(backend.positionSeconds());
    }, 100);
  }
  function stopPolling() { if (pollTimer) { clearInterval(pollTimer); pollTimer = null; } }

  window.woodshedAudio = {
    async init() {
      if (!ctx) ctx = new (window.AudioContext || window.webkitAudioContext)();
      await this.setEngine(backendId);
    },
    async load(arrayBuffer) {
      // decodeAudioData détache le buffer : on le copie.
      decoded = await ctx.decodeAudioData(arrayBuffer.slice(0));
      if (backend) await backend.load(decoded);
    },
    play() { if (ctx.state === 'suspended') ctx.resume(); backend && backend.play(); startPolling(); },
    pause() { backend && backend.pause(); },
    seek(seconds) { backend && backend.seek(seconds); },
    setTempo(ratio) { backend && backend.setTempo(ratio); },
    setPitchSemitones(n) { backend && backend.setPitchSemitones(n); },
    setLoop(loop) { backend && backend.setLoop(loop); },
    async setEngine(id) {
      const wasPlaying = backend ? backend.isPlaying() : false;
      const pos = backend ? backend.positionSeconds() : 0;
      const tempo = backend ? backend.tempo() : 1.0;
      const pitch = backend ? backend.pitchSemitones() : 0;
      if (backend) backend.dispose();
      const factory = backends[id];
      if (!factory) throw new Error('Backend inconnu: ' + id);
      backend = await factory(ctx);
      backendId = id;
      if (decoded) await backend.load(decoded);
      backend.setTempo(tempo);
      backend.setPitchSemitones(pitch);
      backend.seek(pos);
      if (wasPlaying) backend.play();
    },
    getGlitchCount() { return backend ? backend.glitchCount() : 0; },
    get duration() { return decoded ? decoded.duration : 0; },
    onPosition(cb) { positionCb = cb; },
  };
})();
```

- [ ] **Step 4 : Implémenter le backend `plain`**

Créer `web/audio/backend-plain.js`. Lecture brute via `AudioBufferSourceNode` (sources Web Audio = à usage unique : pause/seek recréent la source).

```js
window.woodshedAudioRegisterBackend('plain', async (ctx) => {
  let buffer = null, src = null, playing = false;
  let startedAt = 0;      // ctx.currentTime au démarrage
  let offset = 0;         // position (s) au démarrage
  let loop = false;

  function stopSrc() {
    if (src) { try { src.onended = null; src.stop(); } catch (e) {} src.disconnect(); src = null; }
  }
  function curPos() {
    if (!buffer) return 0;
    const p = playing ? offset + (ctx.currentTime - startedAt) : offset;
    return loop && buffer.duration > 0 ? p % buffer.duration : Math.min(p, buffer.duration);
  }
  function startFrom(pos) {
    stopSrc();
    src = ctx.createBufferSource();
    src.buffer = buffer;
    src.loop = loop;
    src.connect(ctx.destination);
    offset = pos; startedAt = ctx.currentTime;
    src.start(0, pos);
    playing = true;
  }

  return {
    async load(decoded) { buffer = decoded; offset = 0; playing = false; stopSrc(); },
    play() { if (buffer && !playing) startFrom(curPos()); },
    pause() { if (playing) { offset = curPos(); playing = false; stopSrc(); } },
    seek(s) { const wasPlaying = playing; offset = s; if (wasPlaying) startFrom(s); else { playing = false; } },
    setTempo(_r) { /* backend plain : non supporté (vitesse=1.0) */ },
    setPitchSemitones(_n) { /* backend plain : non supporté */ },
    setLoop(l) { loop = l; if (src) src.loop = l; },
    isPlaying() { return playing; },
    positionSeconds() { return curPos(); },
    tempo() { return 1.0; },
    pitchSemitones() { return 0; },
    glitchCount() { return 0; },
    dispose() { stopSrc(); },
  };
});
```

- [ ] **Step 5 : Charger la façade et les backends dans `index.html`**

Dans `web/index.html`, juste avant la balise `<script src="flutter_bootstrap.js" async></script>`, ajouter :

```html
  <script src="audio/facade.js"></script>
  <script src="audio/backend-plain.js"></script>
```

- [ ] **Step 6 : Implémenter `WebAudioEngine` (proxy js_interop)**

Créer `lib/core/audio/web_audio_engine.dart` :

```dart
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'audio_engine.dart';
import 'engine_kind.dart';

@JS('woodshedAudio')
external _Facade get _facade;

extension type _Facade._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> init();
  external JSPromise<JSAny?> load(JSArrayBuffer data);
  external void play();
  external void pause();
  external void seek(double seconds);
  external void setTempo(double ratio);
  external void setPitchSemitones(double n);
  external void setLoop(bool loop);
  external JSPromise<JSAny?> setEngine(String id);
  external int getGlitchCount();
  external double get duration;
  external void onPosition(JSFunction cb);
}

/// Implémentation [AudioEngine] sur le web, proxy vers la façade `window.woodshedAudio`.
class WebAudioEngine implements AudioEngine {
  final _positionController = StreamController<Duration>.broadcast();
  Duration _duration = Duration.zero;

  Future<void> init() async {
    _facade.onPosition(
      ((double seconds) {
        _positionController.add(
            Duration(milliseconds: (seconds * 1000).round()));
      }).toJS,
    );
    await _facade.init().toDart;
  }

  @override
  Future<void> load(Uint8List bytes) async {
    final buffer = bytes.toJS.buffer;
    await _facade.load(buffer).toDart;
    _duration = Duration(milliseconds: (_facade.duration * 1000).round());
  }

  @override
  Future<void> play() async => _facade.play();
  @override
  Future<void> pause() async => _facade.pause();
  @override
  Future<void> seek(Duration position) async =>
      _facade.seek(position.inMilliseconds / 1000.0);
  @override
  Future<void> setSpeed(double rate) async => _facade.setTempo(rate);
  @override
  Future<void> setPitch(double semitones) async =>
      _facade.setPitchSemitones(semitones);
  @override
  Future<void> setLoop(bool loop) async => _facade.setLoop(loop);
  @override
  Future<void> setEngine(EngineKind kind) async =>
      _facade.setEngine(kind.jsId).toDart;

  @override
  Stream<Duration> get position => _positionController.stream;
  @override
  Duration get duration => _duration;
  @override
  int get glitchCount => _facade.getGlitchCount();

  @override
  Future<void> dispose() async => _positionController.close();

  @override
  Future<void> setVolume(double volume) async =>
      throw UnimplementedError('Hors périmètre du spike');
  @override
  Future<void> setLoopRange(Duration a, Duration b) async =>
      throw UnimplementedError('Hors périmètre du spike');
}
```

- [ ] **Step 7 : Vérifier la compilation + l'analyse**

Run : `flutter analyze`
Expected : `No issues found!` (si un avertissement sur `_facade.onPosition` typedef apparaît, vérifier la signature `JSFunction`).

- [ ] **Step 8 : Commit**

```bash
git add lib/core/audio/ web/audio/ web/index.html
git commit -m "feat(audio): interface AudioEngine + facade JS + backend plain + WebAudioEngine"
```

---

## Task 3 : Contrôleur d'état (TDD avec moteur factice) + UI minimale

**Files:**
- Create: `lib/features/spike/spike_controller.dart`
- Create: `lib/features/spike/spike_page.dart`
- Create: `test/spike_controller_test.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1 : Écrire le test du contrôleur (échoue)**

Créer `test/spike_controller_test.dart`. Un `FakeAudioEngine` enregistre les appels pour vérifier le bornage du pitch et le changement de moteur sans navigateur.

```dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed/core/audio/audio_engine.dart';
import 'package:woodshed/core/audio/engine_kind.dart';
import 'package:woodshed/features/spike/spike_controller.dart';

class FakeAudioEngine implements AudioEngine {
  final calls = <String>[];
  double lastPitch = 0, lastSpeed = 1;
  EngineKind lastEngine = EngineKind.plain;
  final _pos = StreamController<Duration>.broadcast();

  @override
  Future<void> load(Uint8List bytes) async => calls.add('load');
  @override
  Future<void> play() async => calls.add('play');
  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> seek(Duration p) async => calls.add('seek:$p');
  @override
  Future<void> setSpeed(double r) async { lastSpeed = r; }
  @override
  Future<void> setPitch(double s) async { lastPitch = s; }
  @override
  Future<void> setLoop(bool l) async => calls.add('loop:$l');
  @override
  Future<void> setEngine(EngineKind k) async { lastEngine = k; }
  @override
  Stream<Duration> get position => _pos.stream;
  @override
  Duration get duration => const Duration(minutes: 4);
  @override
  int get glitchCount => 0;
  @override
  Future<void> dispose() async => _pos.close();
  @override
  Future<void> setVolume(double v) async {}
  @override
  Future<void> setLoopRange(Duration a, Duration b) async {}
}

void main() {
  late FakeAudioEngine engine;
  late SpikeController controller;

  setUp(() {
    engine = FakeAudioEngine();
    controller = SpikeController(engine);
  });

  test('le pitch est borné à +6', () async {
    await controller.setPitch(10);
    expect(engine.lastPitch, 6.0);
    expect(controller.pitch, 6.0);
  });

  test('le pitch est borné à -6', () async {
    await controller.setPitch(-99);
    expect(engine.lastPitch, -6.0);
  });

  test('changer de moteur délègue au moteur', () async {
    await controller.setEngine(EngineKind.soundTouch);
    expect(engine.lastEngine, EngineKind.soundTouch);
    expect(controller.engine, EngineKind.soundTouch);
  });

  test('setSpeed délègue la valeur', () async {
    await controller.setSpeed(0.75);
    expect(engine.lastSpeed, 0.75);
    expect(controller.speed, 0.75);
  });
}
```

- [ ] **Step 2 : Lancer le test (échoue)**

Run : `flutter test test/spike_controller_test.dart`
Expected : FAIL — `SpikeController` introuvable.

- [ ] **Step 3 : Implémenter le contrôleur**

Créer `lib/features/spike/spike_controller.dart` :

```dart
import 'package:flutter/foundation.dart';
import '../../core/audio/audio_engine.dart';
import '../../core/audio/engine_kind.dart';
import '../../core/audio/pitch_math.dart';

/// État de la page de spike. Délègue toute l'audio à [AudioEngine].
class SpikeController extends ChangeNotifier {
  SpikeController(this._engine);
  final AudioEngine _engine;

  double pitch = 0;
  double speed = 1.0;
  bool looping = false;
  bool isPlaying = false;
  bool loaded = false;
  EngineKind engine = EngineKind.plain;

  Future<void> setPitch(double semitones) async {
    pitch = clampSemitones(semitones);
    await _engine.setPitch(pitch);
    notifyListeners();
  }

  Future<void> setSpeed(double rate) async {
    speed = rate;
    await _engine.setSpeed(rate);
    notifyListeners();
  }

  Future<void> setEngine(EngineKind kind) async {
    engine = kind;
    await _engine.setEngine(kind);
    notifyListeners();
  }

  Future<void> toggleLoop() async {
    looping = !looping;
    await _engine.setLoop(looping);
    notifyListeners();
  }

  Future<void> play() async { await _engine.play(); isPlaying = true; notifyListeners(); }
  Future<void> pause() async { await _engine.pause(); isPlaying = false; notifyListeners(); }
  Future<void> restart() async { await _engine.seek(Duration.zero); }
}
```

- [ ] **Step 4 : Lancer le test (passe)**

Run : `flutter test test/spike_controller_test.dart`
Expected : PASS (4 tests).

- [ ] **Step 5 : Implémenter l'UI minimale**

Créer `lib/features/spike/spike_page.dart`. (Texte FR ; identifiants EN.)

```dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/audio/engine_kind.dart';
import '../../core/audio/web_audio_engine.dart';
import 'spike_controller.dart';

class SpikePage extends StatefulWidget {
  const SpikePage({super.key});
  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> {
  late final WebAudioEngine _engine;
  late final SpikeController _c;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _engine = WebAudioEngine();
    _c = SpikeController(_engine);
    _engine.init();
    _engine.position.listen((p) => setState(() => _position = p));
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.audio, withData: true);
    final bytes = result?.files.single.bytes;
    if (bytes == null) return;
    await _engine.load(bytes);
    setState(() => _c.loaded = true);
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Spike moteur audio')),
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.folder_open),
                label: const Text('Charger un morceau'),
              ),
              const SizedBox(height: 16),
              Text('${_fmt(_position)} / ${_fmt(_engine.duration)}'),
              Text('Moteur : ${_c.engine.name} · glitches : ${_engine.glitchCount}'),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 40,
                    onPressed: _c.loaded
                        ? () => _c.isPlaying ? _c.pause() : _c.play()
                        : null,
                    icon: Icon(_c.isPlaying ? Icons.pause : Icons.play_arrow),
                  ),
                  IconButton(
                    iconSize: 32,
                    onPressed: _c.loaded ? _c.restart : null,
                    icon: const Icon(Icons.replay),
                  ),
                  IconButton(
                    iconSize: 32,
                    onPressed: _c.loaded ? _c.toggleLoop : null,
                    icon: Icon(_c.looping ? Icons.repeat_on : Icons.repeat),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Pitch : ${_c.pitch.toStringAsFixed(0)} demi-tons'),
              Slider(
                value: _c.pitch,
                min: -6, max: 6, divisions: 12,
                label: _c.pitch.toStringAsFixed(0),
                onChanged: (v) => _c.setPitch(v),
              ),
              const SizedBox(height: 8),
              const Text('Vitesse'),
              Wrap(
                spacing: 8,
                children: [0.5, 0.75, 1.0]
                    .map((r) => ChoiceChip(
                          label: Text('${r}x'),
                          selected: _c.speed == r,
                          onSelected: (_) => _c.setSpeed(r),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
              const Text('Moteur'),
              Wrap(
                spacing: 8,
                children: [EngineKind.soundTouch, EngineKind.rubberBand]
                    .map((k) => ChoiceChip(
                          label: Text(k.name),
                          selected: _c.engine == k,
                          onSelected: (_) => _c.setEngine(k),
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 6 : Brancher `SpikePage` dans `main.dart`**

Remplacer le contenu de `lib/main.dart` par :

```dart
import 'package:flutter/material.dart';
import 'features/spike/spike_page.dart';

void main() => runApp(const WoodshedApp());

class WoodshedApp extends StatelessWidget {
  const WoodshedApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'woodshed — spike',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        home: const SpikePage(),
      );
}
```

- [ ] **Step 7 : Vérifier dans Chrome (lecture brute)**

Run : `flutter run -d chrome`
Vérifier manuellement :
- « Charger un morceau » ouvre le sélecteur, un MP3 se charge, la durée s'affiche.
- Play joue le son (vitesse normale, hauteur normale — backend `plain`), Pause/Restart fonctionnent, la position avance.
- Le slider Pitch et les chips Vitesse n'ont **pas encore** d'effet (backend `plain`) — c'est attendu.
Expected : lecture audible et fluide à 1.0x.

- [ ] **Step 8 : Analyse + commit**

```bash
flutter analyze
git add lib/ test/spike_controller_test.dart
git commit -m "feat(spike): controleur d'etat (TDD) + UI minimale + lecture brute"
```

---

## Task 4 : Backend SoundTouch (pitch + vitesse temps réel)

But : pitch ±6 et vitesse 0.5/0.75/1.0 réellement audibles. C'est le cœur du spike côté SoundTouch.

> ⚠️ API tierce : le nom exact du processor et le protocole de messages de `@soundtouchjs/audio-worklet` doivent être **confirmés sur le fichier vendorisé** (Step 2). Le code ci-dessous suit l'API publique connue du paquet ; ajuster si la confirmation diffère.

**Files:**
- Create: `web/vendor/soundtouch/soundtouch-worklet.js` (vendorisé)
- Create: `web/audio/backend-soundtouch.js`
- Modify: `web/index.html`

- [ ] **Step 1 : Vendoriser le fichier worklet de SoundTouch**

Télécharger le worklet dist depuis le CDN jsDelivr dans `web/vendor/soundtouch/` :

```bash
mkdir -p web/vendor/soundtouch
curl -L -o web/vendor/soundtouch/soundtouch-worklet.js \
  https://cdn.jsdelivr.net/npm/@soundtouchjs/audio-worklet/dist/soundtouch-worklet.js
```
Expected : fichier non vide (> 10 Ko).

- [ ] **Step 2 : Confirmer le nom du processor et le protocole**

Inspecter le fichier vendorisé pour relever : le nom passé à `registerProcessor('...')`, et les clés de messages acceptées (`pitch`, `pitchSemitones`, `tempo`/`rate`, et le message de chargement des canaux audio) :

```bash
grep -nE "registerProcessor|pitch|tempo|rate|case '|sampleRate" web/vendor/soundtouch/soundtouch-worklet.js | head -40
```
Noter le nom du processor (souvent `'soundtouch-worklet'`) et les paramètres. **Si le protocole diffère du Step 3, adapter `backend-soundtouch.js` en conséquence.** En cas de doute, consulter la doc via context7 (`@soundtouchjs/audio-worklet`) avant de coder.

- [ ] **Step 3 : Implémenter le backend SoundTouch**

Créer `web/audio/backend-soundtouch.js`. Approche : on charge le module worklet une fois, on crée un `AudioWorkletNode`, on lui envoie les canaux PCM du `AudioBuffer` décodé, et on pilote tempo/pitch par messages. La position est estimée par le worklet (frames consommées) et remontée via `port.onmessage`.

```js
window.woodshedAudioRegisterBackend('soundtouch', async (ctx) => {
  await ctx.audioWorklet.addModule('vendor/soundtouch/soundtouch-worklet.js');

  let node = null, playing = false, glitches = 0;
  let tempo = 1.0, pitch = 0, loop = false, posSec = 0, durSec = 0;
  let buffer = null;

  function build() {
    // 'soundtouch-worklet' = nom confirmé au Step 2 ; ajuster si besoin.
    node = new AudioWorkletNode(ctx, 'soundtouch-worklet', { outputChannelCount: [2] });
    node.port.onmessage = (e) => {
      const d = e.data || {};
      if (typeof d.timePlayed === 'number') posSec = d.timePlayed;
      if (d.type === 'underrun') glitches++;
      if (d.type === 'ended' && loop) { sendSeek(0); }
    };
    applyParams();
    node.connect(ctx.destination);
  }
  function applyParams() {
    if (!node) return;
    node.parameters.get('tempo') && node.parameters.get('tempo').setValueAtTime(tempo, ctx.currentTime);
    node.parameters.get('pitch') && node.parameters.get('pitch').setValueAtTime(pitchRatioFromSemitones(pitch), ctx.currentTime);
    // Fallback message-based (selon build) :
    node.port.postMessage({ type: 'tempo', value: tempo });
    node.port.postMessage({ type: 'pitchSemitones', value: pitch });
  }
  function pitchRatioFromSemitones(n) { return Math.pow(2, n / 12); }
  function sendBuffer() {
    if (!node || !buffer) return;
    const channels = [];
    for (let c = 0; c < buffer.numberOfChannels; c++) channels.push(buffer.getChannelData(c).slice(0));
    node.port.postMessage({ type: 'load', channels, sampleRate: buffer.sampleRate }, channels.map(c => c.buffer));
  }
  function sendSeek(s) { posSec = s; node && node.port.postMessage({ type: 'seek', value: s }); }

  return {
    async load(decoded) {
      buffer = decoded; durSec = decoded.duration; posSec = 0;
      if (!node) build();
      sendBuffer();
    },
    play() { if (ctx.state === 'suspended') ctx.resume(); node && node.port.postMessage({ type: 'play' }); playing = true; },
    pause() { node && node.port.postMessage({ type: 'pause' }); playing = false; },
    seek(s) { sendSeek(s); },
    setTempo(r) { tempo = r; applyParams(); },
    setPitchSemitones(n) { pitch = n; applyParams(); },
    setLoop(l) { loop = l; },
    isPlaying() { return playing; },
    positionSeconds() { return posSec; },
    tempo() { return tempo; },
    pitchSemitones() { return pitch; },
    glitchCount() { return glitches; },
    dispose() { if (node) { try { node.disconnect(); } catch (e) {} node = null; } },
  };
});
```

> Le protocole de messages (`load`/`play`/`pause`/`seek`/`tempo`/`pitchSemitones`) est notre **convention de façade**. Si le worklet vendorisé attend un autre protocole (ex. il fournit déjà un wrapper `createSoundTouchNode`), deux choix : (a) adapter ces messages au protocole réel ; (b) écrire un mince worklet maison qui consomme le DSP `soundtouchjs` et expose CE protocole. Le choix se fait au Step 2 selon ce que contient le fichier.

- [ ] **Step 4 : Charger le backend dans `index.html`**

Dans `web/index.html`, après la ligne `backend-plain.js`, ajouter :

```html
  <script src="audio/backend-soundtouch.js"></script>
```

- [ ] **Step 5 : Basculer le moteur par défaut sur SoundTouch**

Dans `web/audio/facade.js`, remplacer `let backendId = 'plain';` par `let backendId = 'soundtouch';`.

- [ ] **Step 6 : Vérifier dans Chrome (pitch + vitesse réels)**

Run : `flutter run -d chrome`
Vérifier manuellement :
- Charger un morceau, Play → son normal.
- Bouger le slider Pitch à +6 puis −6 → la **tonalité** change **sans changer la vitesse**, effet quasi instantané.
- Vitesse 0.5x / 0.75x → la **vitesse** change **sans changer la tonalité**.
- Aucun re-décodage perceptible (pas de gel de l'UI).
- Le compteur de glitches reste bas.
Expected : transposition et ralenti indépendants, en temps réel. Si la console montre une erreur de nom de processor → revenir au Step 2.

- [ ] **Step 7 : Commit**

```bash
git add web/vendor/ web/audio/backend-soundtouch.js web/audio/facade.js web/index.html
git commit -m "feat(spike): backend SoundTouch (pitch+vitesse temps reel) via AudioWorklet"
```

---

## Task 5 : Déploiement GitHub Pages + test iPhone (porte de décision SoundTouch)

But : la vraie validation — juger SoundTouch à l'oreille sur l'iPhone. **Pas de coi-serviceworker à ce stade** (SoundTouch n'a pas besoin de SharedArrayBuffer).

**Files:**
- Create: `.github/workflows/deploy-pages.yml`
- Modify: `web/manifest.json`

- [ ] **Step 1 : Ajuster le manifest PWA**

Dans `web/manifest.json`, mettre à jour `name`, `short_name`, `description`, `background_color`, `theme_color` :

```json
{
  "name": "woodshed — spike audio",
  "short_name": "woodshed",
  "start_url": ".",
  "display": "standalone",
  "background_color": "#0F0F0F",
  "theme_color": "#673AB7",
  "description": "Spike de validation du moteur audio temps reel (transposition / vitesse).",
  "orientation": "portrait-primary",
  "prefer_related_applications": false,
  "icons": [
    { "src": "icons/Icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "icons/Icon-512.png", "sizes": "512x512", "type": "image/png" },
    { "src": "icons/Icon-maskable-192.png", "sizes": "192x192", "type": "image/png", "purpose": "maskable" },
    { "src": "icons/Icon-maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
  ]
}
```

- [ ] **Step 2 : Créer le workflow de déploiement**

Créer `.github/workflows/deploy-pages.yml`. (Confirmer la version Flutter avec `flutter --version` et l'aligner.)

```yaml
name: Deploy PWA to GitHub Pages
on:
  push:
    branches: [spike/web-audio-engine]
  workflow_dispatch:
permissions:
  contents: read
  pages: write
  id-token: write
concurrency:
  group: pages
  cancel-in-progress: true
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: 3.44.0
      - run: flutter pub get
      - run: flutter build web --release --base-href /woodshed/
      - uses: actions/upload-pages-artifact@v3
        with:
          path: build/web
  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
```

- [ ] **Step 3 : Activer GitHub Pages (source = GitHub Actions)**

Dans les réglages du dépôt GitHub : **Settings → Pages → Build and deployment → Source : GitHub Actions**. (Le dépôt doit exister sur GitHub ; sinon le créer et `git push -u origin spike/web-audio-engine`.)

- [ ] **Step 4 : Pousser et déclencher le déploiement**

```bash
git add web/manifest.json .github/workflows/deploy-pages.yml
git commit -m "ci: deploiement PWA sur GitHub Pages + manifest"
git push -u origin spike/web-audio-engine
```
Expected : workflow vert dans l'onglet Actions ; URL `https://<user>.github.io/woodshed/` servie.

- [ ] **Step 5 : Installer la PWA sur l'iPhone**

Sur l'iPhone (Safari) : ouvrir l'URL Pages → **Partager → Sur l'écran d'accueil**. Lancer depuis l'icône (mode standalone).

- [ ] **Step 6 : Checklist de validation à l'oreille (SoundTouch)**

Préparer deux morceaux : un **dense** (mix chargé) et un **clairsemé** (voix/guitare nue). Pour chacun :
- [ ] Charger, Play → lecture fluide.
- [ ] Pitch **+6** : tonalité montée, vitesse inchangée. Artefacts perçus ? (oui/non/léger)
- [ ] Pitch **−6** : tonalité descendue. Artefacts ?
- [ ] Vitesse **0.5x** : ralenti net, tonalité inchangée. Artefacts ?
- [ ] Combiné **−6 & 0.5x**.
- [ ] Boucle longue (plusieurs minutes) : saccades ? compteur de glitches ?
- [ ] Latence au changement de réglage : acceptable ?

- [ ] **Step 7 : Noter le pré-verdict SoundTouch**

Consigner en une ligne le ressenti (« SoundTouch OK » / « limite » / « insuffisant ») — alimente Task 7. **Si SoundTouch est jugé suffisant → Task 6 devient optionnelle.**

---

## Task 6 : (PLAFONNÉE ~2 h) Backend Rubber Band + comparaison iPhone

> **Plafond strict (spec §7) :** uniquement avec un **build WASM existant**, **pas de compilation Emscripten maison**. Boîte de temps ~2 h. Au-delà, ou si aucun build ne s'intègre → **arrêter, documenter le constat dans Task 7**, ne pas s'acharner. À n'entreprendre que si Task 5 a jugé SoundTouch insuffisant (ou pour comparaison explicitement souhaitée).

**Files:**
- Create: `web/coi-serviceworker.min.js`
- Create: `web/vendor/rubberband/` (build vendorisé, si trouvé)
- Create: `web/audio/backend-rubberband.js`
- Modify: `web/index.html`

- [ ] **Step 1 : Démarrer le minuteur (boîte de temps ~2 h)**

Noter l'heure de début. Objectif : un verdict comparatif, pas un moteur parfait.

- [ ] **Step 2 : Trouver et vendoriser un build Rubber Band WASM**

Chercher un build WASM temps-réel maintenu (npm / GitHub, ex. autour de `rubberband-wasm` / bindings AudioWorklet). Confirmer la licence (GPL/commercial). Vendoriser le `.wasm` + le `.js` dans `web/vendor/rubberband/`.
**Si rien d'exploitable en ~30 min → arrêter là**, passer à Task 7 avec le constat « pas de build Rubber Band WASM temps-réel exploitable sans compilation maison ».

- [ ] **Step 3 : Ajouter coi-serviceworker (pour SharedArrayBuffer)**

Télécharger le shim et l'enregistrer en **tout premier** script du `<head>` de `web/index.html` :

```bash
curl -L -o web/coi-serviceworker.min.js \
  https://cdn.jsdelivr.net/gh/gzuidhof/coi-serviceworker/coi-serviceworker.min.js
```

Dans `web/index.html`, dans le `<head>`, avant tout autre script :

```html
  <script src="coi-serviceworker.min.js"></script>
```

> ⚠️ Cohabitation avec le service worker de Flutter à valider : si conflit, désactiver le SW Flutter pour le spike (lancer Flutter avec `--pwa-strategy=none` au build) ou s'assurer que coi-serviceworker prend le contrôle (rechargement automatique au premier chargement).

- [ ] **Step 4 : Vérifier l'isolation cross-origin**

Après build+déploiement (ou en local servi avec en-têtes), ouvrir la console et taper :

```js
crossOriginIsolated
```
Expected : `true` (sinon SharedArrayBuffer indisponible → Rubber Band threads KO).

- [ ] **Step 5 : Implémenter `backend-rubberband.js`**

Même contrat de façade que SoundTouch (`load`/`play`/`pause`/`seek`/`setTempo`/`setPitchSemitones`/`setLoop`/`positionSeconds`/`glitchCount`/`dispose`), en pilotant le build Rubber Band vendorisé. Le code dépend du build trouvé au Step 2 → l'écrire d'après son API, en miroir de `backend-soundtouch.js`. Charger via `<script src="audio/backend-rubberband.js"></script>` dans `index.html`.

- [ ] **Step 6 : Comparer sur iPhone**

Déployer (push → Pages). Sur l'iPhone, pour le **même extrait, mêmes réglages**, basculer la chip moteur **SoundTouch ↔ Rubber Band** et comparer : qualité (−6/+6/0.5x), glitches, latence.

- [ ] **Step 7 : Commit (ou constat d'arrêt)**

```bash
git add web/
git commit -m "feat(spike): backend Rubber Band + coi-serviceworker (comparaison)"
```
Si arrêt au plafond sans intégration : pas de commit de code, on documente en Task 7.

---

## Task 7 : Rédiger le verdict et ouvrir la suite

**Files:**
- Create: `docs/superpowers/2026-06-15-verdict-moteur-web.md`

- [ ] **Step 1 : Rédiger le verdict**

Créer `docs/superpowers/2026-06-15-verdict-moteur-web.md` avec : matériel testé, ressenti SoundTouch (artefacts/glitches/latence sur iPhone), ressenti Rubber Band (ou raison de l'arrêt au plafond), et **la décision** parmi : (1) SoundTouch suffit, (2) Rubber Band requis, (3) aucun suffisant → repenser.

- [ ] **Step 2 : Commit**

```bash
git add docs/superpowers/2026-06-15-verdict-moteur-web.md
git commit -m "docs: verdict du spike moteur audio web"
```

- [ ] **Step 3 : Prochaine étape**

Le verdict débloque la **spec du noyau looper** (boucle A/B, waveform, volume, persistance) : relancer un cycle brainstorming → spec → plan sur cette base. Décider aussi de l'intégration de la branche `spike/web-audio-engine` (PR vers `main` ?).

---

## Notes d'exécution

- **Ce qui est testé automatiquement** : maths de pitch et logique du contrôleur (Dart pur, `flutter test`). Le reste (Web Audio, worklets) est validé **manuellement dans le navigateur / sur iPhone** — c'est la nature d'un spike.
- **Surfaces de dev** : `flutter run -d chrome` pour itérer la plomberie (pas un test audio fiable pour la qualité, cf. doc d'archi) ; **le jugement de qualité se fait sur l'iPhone** via GitHub Pages.
- **Plafond Rubber Band** : respecter strictement la boîte de temps. Le spike a réussi dès lors qu'il rend un verdict, même « SoundTouch only ».
