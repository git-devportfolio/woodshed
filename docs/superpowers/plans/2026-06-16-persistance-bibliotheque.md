# Persistance / bibliothèque — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Une bibliothèque de morceaux persistée en IndexedDB : importer un fichier une fois → il est sauvegardé et rechargeable d'un tap, avec ses réglages (pitch/vitesse/volume) auto-mémorisés ; deux écrans (Bibliothèque → Lecteur), lecteur enrichi (scrubber + ⟲−10 s, sans bouton boucle).

**Architecture:** Couche données isolée derrière l'interface `LibraryRepository` (impl `idb_shim`, 2 object stores : métadonnées `tracks` + octets `audio`). Le lecteur (refonte du spike) reçoit un `Track`, charge ses octets, applique ses réglages et les sauvegarde en debounce. Volume ajouté au moteur via un `GainNode` maître dans la façade. Import via le sélecteur natif `pickAudioFile()` (déjà construit) + une util de probe de durée.

**Tech Stack:** Flutter web (Dart 3.12), `idb_shim` (IndexedDB + factory mémoire pour tests), `uuid`, `package:web` (OfflineAudioContext pour la durée), moteur audio existant (façade JS + worklets).

**Référence spec :** `docs/superpowers/specs/2026-06-16-persistance-bibliotheque-design.md`

---

## Carte des fichiers

```
lib/
  core/library/
    track.dart                  # modèles Track + TrackSettings (purs, JSON)
    library_repository.dart      # interface LibraryRepository (pur Dart)
    idb_library_repository.dart  # impl idb_shim (2 stores)
  core/audio/
    probe_duration.dart          # probeAudioDuration(bytes) via OfflineAudioContext (web)
    web_audio_engine.dart        # + setVolume réel
  core/io/
    audio_file_picker.dart       # (déjà créé)
    persistent_storage.dart      # requestPersistentStorage() (navigator.storage.persist)
  features/player/
    player_controller.dart       # ex-SpikeController : repo + track, applique/sauve réglages
    player_page.dart             # ex-SpikePage : titre, scrubber, -10s, transport, pitch/vitesse/volume
  features/library/
    library_page.dart            # liste + import + suppression
  main.dart                      # repo + persist() + home LibraryPage
web/audio/
  facade.js                      # + GainNode maître + setVolume ; backends -> destination
  backend-plain.js               # connect(destination)
  backend-soundtouch.js          # connect(destination)
  backend-rubberband.js          # connect(destination)
test/
  track_test.dart                # round-trip JSON
  idb_library_repository_test.dart  # CRUD contre factory mémoire
  player_controller_test.dart    # apply + debounce save (remplace spike_controller_test.dart)
```

À supprimer en fin de parcours : `lib/features/spike/` (spike_page.dart, spike_controller.dart) et `test/spike_controller_test.dart`.

---

## Task 1 : Dépendances + modèles (Track, TrackSettings) [TDD]

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/core/library/track.dart`
- Test: `test/track_test.dart`

- [ ] **Step 1 : Ajouter les dépendances**

Dans `pubspec.yaml`, sous `dependencies:` (après `web:`), ajouter :
```yaml
  idb_shim: ^2.6.1
  uuid: ^4.5.1
```
Puis : `flutter pub get` (Expected : résolution OK).

- [ ] **Step 2 : Écrire le test (échoue)**

Créer `test/track_test.dart` :
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed/core/library/track.dart';

void main() {
  test('TrackSettings round-trip JSON', () {
    final s = TrackSettings(pitchSemitones: 3, speed: 0.75, volume: 0.5);
    final back = TrackSettings.fromJson(s.toJson());
    expect(back.pitchSemitones, 3);
    expect(back.speed, 0.75);
    expect(back.volume, 0.5);
  });

  test('TrackSettings valeurs par défaut', () {
    final s = TrackSettings();
    expect(s.pitchSemitones, 0);
    expect(s.speed, 1.0);
    expect(s.volume, 1.0);
  });

  test('Track round-trip JSON', () {
    final t = Track(
      id: 'abc',
      name: 'Mon solo.mp3',
      durationMs: 238000,
      importedAt: DateTime.utc(2026, 6, 16, 10, 30),
      settings: TrackSettings(pitchSemitones: -2, speed: 0.5, volume: 0.8),
    );
    final back = Track.fromJson(t.toJson());
    expect(back.id, 'abc');
    expect(back.name, 'Mon solo.mp3');
    expect(back.durationMs, 238000);
    expect(back.importedAt, DateTime.utc(2026, 6, 16, 10, 30));
    expect(back.settings.pitchSemitones, -2);
    expect(back.settings.speed, 0.5);
    expect(back.settings.volume, 0.8);
  });
}
```

- [ ] **Step 3 : Lancer (échoue)** — `flutter test test/track_test.dart` → FAIL (`track.dart` introuvable).

- [ ] **Step 4 : Implémenter**

Créer `lib/core/library/track.dart` :
```dart
/// Réglages de pratique d'un morceau. Extensible (recevra loopA/loopB plus tard).
class TrackSettings {
  TrackSettings({this.pitchSemitones = 0, this.speed = 1.0, this.volume = 1.0});

  double pitchSemitones;
  double speed;
  double volume;

  Map<String, dynamic> toJson() => {
        'pitchSemitones': pitchSemitones,
        'speed': speed,
        'volume': volume,
      };

  factory TrackSettings.fromJson(Map json) => TrackSettings(
        pitchSemitones: (json['pitchSemitones'] as num?)?.toDouble() ?? 0,
        speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
        volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      );
}

/// Un morceau de la bibliothèque (métadonnées + réglages ; les octets audio
/// sont stockés à part, indexés par [id]).
class Track {
  Track({
    required this.id,
    required this.name,
    required this.durationMs,
    required this.importedAt,
    required this.settings,
  });

  final String id;
  final String name;
  final int durationMs;
  final DateTime importedAt;
  TrackSettings settings;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'durationMs': durationMs,
        'importedAt': importedAt.toIso8601String(),
        'settings': settings.toJson(),
      };

  factory Track.fromJson(Map json) => Track(
        id: json['id'] as String,
        name: json['name'] as String,
        durationMs: (json['durationMs'] as num).toInt(),
        importedAt: DateTime.parse(json['importedAt'] as String),
        settings: TrackSettings.fromJson(json['settings'] as Map),
      );
}
```

- [ ] **Step 5 : Lancer (passe)** — `flutter test test/track_test.dart` → PASS (3 tests).
- [ ] **Step 6 : Analyse** — `flutter analyze` → `No issues found!`
- [ ] **Step 7 : Commit**
```bash
git add pubspec.yaml pubspec.lock lib/core/library/track.dart test/track_test.dart
git commit -m "feat(library): modeles Track/TrackSettings + deps idb_shim/uuid"
```

---

## Task 2 : `LibraryRepository` + `IdbLibraryRepository` [TDD avec idb mémoire]

**Files:**
- Create: `lib/core/library/library_repository.dart`
- Create: `lib/core/library/idb_library_repository.dart`
- Test: `test/idb_library_repository_test.dart`

- [ ] **Step 1 : Définir l'interface (pur Dart)**

Créer `lib/core/library/library_repository.dart` :
```dart
import 'dart:typed_data';
import 'track.dart';

/// Accès persistant à la bibliothèque de morceaux.
abstract class LibraryRepository {
  Future<List<Track>> listTracks();
  Future<Track> addTrack(String name, Uint8List bytes, Duration duration);
  Future<Uint8List> loadAudio(String id);
  Future<void> updateSettings(String id, TrackSettings settings);
  Future<void> deleteTrack(String id);
}
```

- [ ] **Step 2 : Écrire le test (échoue)**

Créer `test/idb_library_repository_test.dart` (utilise la factory mémoire d'idb_shim → pas de navigateur) :
```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:woodshed/core/library/idb_library_repository.dart';
import 'package:woodshed/core/library/track.dart';

void main() {
  late IdbLibraryRepository repo;

  setUp(() {
    repo = IdbLibraryRepository(newIdbFactoryMemory());
  });

  test('addTrack puis listTracks renvoie le morceau', () async {
    final t = await repo.addTrack('a.mp3', Uint8List.fromList([1, 2, 3]),
        const Duration(seconds: 200));
    final list = await repo.listTracks();
    expect(list, hasLength(1));
    expect(list.single.id, t.id);
    expect(list.single.name, 'a.mp3');
    expect(list.single.durationMs, 200000);
  });

  test('loadAudio renvoie exactement les octets stockés', () async {
    final t = await repo.addTrack('a.mp3', Uint8List.fromList([9, 8, 7, 6]),
        const Duration(seconds: 1));
    final bytes = await repo.loadAudio(t.id);
    expect(bytes, [9, 8, 7, 6]);
  });

  test('updateSettings persiste les nouveaux réglages', () async {
    final t = await repo.addTrack('a.mp3', Uint8List.fromList([1]),
        const Duration(seconds: 1));
    await repo.updateSettings(
        t.id, TrackSettings(pitchSemitones: 4, speed: 0.5, volume: 0.3));
    final reloaded = (await repo.listTracks()).single;
    expect(reloaded.settings.pitchSemitones, 4);
    expect(reloaded.settings.speed, 0.5);
    expect(reloaded.settings.volume, 0.3);
  });

  test('deleteTrack retire le morceau et son audio', () async {
    final t = await repo.addTrack('a.mp3', Uint8List.fromList([1]),
        const Duration(seconds: 1));
    await repo.deleteTrack(t.id);
    expect(await repo.listTracks(), isEmpty);
    expect(() => repo.loadAudio(t.id), throwsA(isA<StateError>()));
  });
}
```

- [ ] **Step 3 : Lancer (échoue)** — `flutter test test/idb_library_repository_test.dart` → FAIL (`idb_library_repository.dart` introuvable).

- [ ] **Step 4 : Implémenter**

Créer `lib/core/library/idb_library_repository.dart` :
```dart
import 'dart:typed_data';

import 'package:idb_shim/idb.dart';
import 'package:uuid/uuid.dart';

import 'library_repository.dart';
import 'track.dart';

/// Implémentation [LibraryRepository] sur IndexedDB via idb_shim.
/// Deux object stores : `tracks` (métadonnées+réglages, clé = id) et `audio`
/// (octets bruts, clé = id passée explicitement).
class IdbLibraryRepository implements LibraryRepository {
  IdbLibraryRepository(this._factory);

  final IdbFactory _factory;
  Database? _db;

  static const _dbName = 'woodshed';
  static const _tracksStore = 'tracks';
  static const _audioStore = 'audio';
  static const _uuid = Uuid();

  Future<Database> _open() async {
    return _db ??= await _factory.open(
      _dbName,
      version: 1,
      onUpgradeNeeded: (VersionChangeEvent e) {
        final db = e.database;
        if (!db.objectStoreNames.contains(_tracksStore)) {
          db.createObjectStore(_tracksStore, keyPath: 'id');
        }
        if (!db.objectStoreNames.contains(_audioStore)) {
          db.createObjectStore(_audioStore);
        }
      },
    );
  }

  @override
  Future<Track> addTrack(String name, Uint8List bytes, Duration duration) async {
    final db = await _open();
    final track = Track(
      id: _uuid.v4(),
      name: name,
      durationMs: duration.inMilliseconds,
      importedAt: DateTime.now(),
      settings: TrackSettings(),
    );
    final txn = db.transactionList([_tracksStore, _audioStore], idbModeReadWrite);
    await txn.objectStore(_tracksStore).put(track.toJson());
    await txn.objectStore(_audioStore).put(bytes, track.id);
    await txn.completed;
    return track;
  }

  @override
  Future<List<Track>> listTracks() async {
    final db = await _open();
    final txn = db.transaction(_tracksStore, idbModeReadOnly);
    final rows = await txn.objectStore(_tracksStore).getAll();
    await txn.completed;
    return rows.map((e) => Track.fromJson(e as Map)).toList()
      ..sort((a, b) => b.importedAt.compareTo(a.importedAt));
  }

  @override
  Future<Uint8List> loadAudio(String id) async {
    final db = await _open();
    final txn = db.transaction(_audioStore, idbModeReadOnly);
    final value = await txn.objectStore(_audioStore).getObject(id);
    await txn.completed;
    if (value == null) {
      throw StateError('Audio introuvable pour le morceau $id');
    }
    return value as Uint8List;
  }

  @override
  Future<void> updateSettings(String id, TrackSettings settings) async {
    final db = await _open();
    final txn = db.transaction(_tracksStore, idbModeReadWrite);
    final store = txn.objectStore(_tracksStore);
    final existing = await store.getObject(id);
    if (existing != null) {
      final track = Track.fromJson(existing as Map);
      track.settings = settings;
      await store.put(track.toJson());
    }
    await txn.completed;
  }

  @override
  Future<void> deleteTrack(String id) async {
    final db = await _open();
    final txn = db.transactionList([_tracksStore, _audioStore], idbModeReadWrite);
    await txn.objectStore(_tracksStore).delete(id);
    await txn.objectStore(_audioStore).delete(id);
    await txn.completed;
  }
}
```

- [ ] **Step 5 : Lancer (passe)** — `flutter test test/idb_library_repository_test.dart` → PASS (4 tests).
  > Note : `loadAudio` renvoie `Uint8List` ; la factory mémoire conserve l'instance telle quelle. Sur navigateur, IndexedDB restitue aussi un `Uint8List`/`ByteBuffer` — si un test futur tournait sur navigateur et qu'un cast échouait, convertir via `Uint8List.fromList(...)`. En mémoire, le cast direct fonctionne.
- [ ] **Step 6 : Analyse** — `flutter analyze` → clean.
- [ ] **Step 7 : Commit**
```bash
git add lib/core/library/library_repository.dart lib/core/library/idb_library_repository.dart test/idb_library_repository_test.dart
git commit -m "feat(library): IdbLibraryRepository (idb_shim) + tests memoire"
```

---

## Task 3 : Volume (GainNode maître) + util de durée

But : implémenter le volume (inexistant) et fournir `probeAudioDuration`. Validé par `flutter analyze` + `flutter build web` (audio jugé manuellement).

**Files:**
- Modify: `web/audio/facade.js`, `web/audio/backend-plain.js`, `web/audio/backend-soundtouch.js`, `web/audio/backend-rubberband.js`
- Modify: `lib/core/audio/web_audio_engine.dart`
- Create: `lib/core/audio/probe_duration.dart`

- [ ] **Step 1 : Façade — GainNode maître + setVolume**

Dans `web/audio/facade.js` :
- Ajouter la variable d'état (près de `let masterGain = null;`) en haut de l'IIFE :
```js
  let masterGain = null;       // gain maître (volume), entre les backends et la sortie
```
- Dans `init()`, après la création de `ctx`, créer le gain et le connecter à la sortie :
```js
    async init() {
      if (!ctx) {
        ctx = new (window.AudioContext || window.webkitAudioContext)();
        masterGain = ctx.createGain();
        masterGain.connect(ctx.destination);
      }
      await this.setEngine(backendId);
    },
```
- Passer `masterGain` comme destination aux backends. Dans `setEngine`, remplacer `backend = await factory(ctx);` par :
```js
      backend = await factory(ctx, masterGain);
```
- Ajouter la méthode `setVolume` à l'objet `window.woodshedAudio` (près de `setLoop`) :
```js
    setVolume(v) { if (masterGain) masterGain.gain.value = v; },
```

- [ ] **Step 2 : Backends — se connecter à `destination` (le gain maître) au lieu de `ctx.destination`**

Les trois fabriques de backend reçoivent désormais `(ctx, destination)`.
- `web/audio/backend-plain.js` : changer la signature `window.woodshedAudioRegisterBackend('plain', async (ctx) => {` en `... async (ctx, destination) => {`, et dans `startFrom`, remplacer `src.connect(ctx.destination);` par `src.connect(destination);`.
- `web/audio/backend-soundtouch.js` : signature `async (ctx, destination) => {`, et dans `ensureNode`, remplacer `node.connect(ctx.destination);` par `node.connect(destination);`.
- `web/audio/backend-rubberband.js` : signature `async (ctx, destination) => {`, et dans `ensureNode`, remplacer `node.connect(ctx.destination);` par `node.connect(destination);`.

- [ ] **Step 3 : WebAudioEngine — setVolume réel**

Dans `lib/core/audio/web_audio_engine.dart` :
- Ajouter à l'extension type `_Facade` (près des autres externals) :
```dart
  external void setVolume(double v);
```
- Remplacer l'implémentation qui lève `UnimplementedError` :
```dart
  @override
  Future<void> setVolume(double volume) async => _facade.setVolume(volume);
```
(laisser `setLoopRange` lever `UnimplementedError` — hors périmètre.)

- [ ] **Step 4 : Util `probeAudioDuration`**

Créer `lib/core/audio/probe_duration.dart` :
```dart
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Décode les octets audio dans un [OfflineAudioContext] (insensible à la
/// suspension iOS) et renvoie leur durée. Lève si le format n'est pas décodable.
Future<Duration> probeAudioDuration(Uint8List bytes) async {
  final buffer = Uint8List.fromList(bytes).buffer.toJS;
  final offline = web.OfflineAudioContext(2, 1, 44100);
  final audioBuffer = await offline.decodeAudioData(buffer).toDart;
  return Duration(milliseconds: (audioBuffer.duration * 1000).round());
}
```

- [ ] **Step 5 : Vérifier**

Run : `flutter analyze` → `No issues found!`
Run : `flutter test` → tous les tests existants passent.
Run : `MSYS_NO_PATHCONV=1 flutter build web --release --base-href /woodshed/` → succès (compile l'interop `probe_duration.dart` + `setVolume`).
> On ne peut pas juger le volume à l'oreille ici (sans navigateur) ; ce sera validé sur appareil après l'UI.

- [ ] **Step 6 : Commit**
```bash
git add web/audio/ lib/core/audio/web_audio_engine.dart lib/core/audio/probe_duration.dart
git commit -m "feat(audio): volume (GainNode maitre) + probeAudioDuration"
```

---

## Task 4 : `PlayerController` [TDD avec fakes]

**Files:**
- Create: `lib/features/player/player_controller.dart`
- Test: `test/player_controller_test.dart`

- [ ] **Step 1 : Écrire le test (échoue)**

Créer `test/player_controller_test.dart` :
```dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed/core/audio/audio_engine.dart';
import 'package:woodshed/core/audio/engine_kind.dart';
import 'package:woodshed/core/library/library_repository.dart';
import 'package:woodshed/core/library/track.dart';
import 'package:woodshed/features/player/player_controller.dart';

class FakeEngine implements AudioEngine {
  double pitch = 0, speed = 1, volume = 1;
  final _pos = StreamController<Duration>.broadcast();
  @override
  Future<void> setPitch(double s) async => pitch = s;
  @override
  Future<void> setSpeed(double r) async => speed = r;
  @override
  Future<void> setVolume(double v) async => volume = v;
  @override
  Future<void> load(Uint8List b) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration p) async {}
  @override
  Future<void> setLoop(bool l) async {}
  @override
  Future<void> setEngine(EngineKind k) async {}
  @override
  Stream<Duration> get position => _pos.stream;
  @override
  Duration get duration => const Duration(minutes: 4);
  @override
  int get glitchCount => 0;
  @override
  Future<void> dispose() async => _pos.close();
  @override
  Future<void> setLoopRange(Duration a, Duration b) async {}
}

class FakeRepo implements LibraryRepository {
  int saveCount = 0;
  TrackSettings? lastSaved;
  @override
  Future<void> updateSettings(String id, TrackSettings s) async {
    saveCount++;
    lastSaved = s;
  }
  @override
  Future<Track> addTrack(String n, Uint8List b, Duration d) async =>
      throw UnimplementedError();
  @override
  Future<void> deleteTrack(String id) async {}
  @override
  Future<Uint8List> loadAudio(String id) async => Uint8List(0);
  @override
  Future<List<Track>> listTracks() async => [];
}

Track _track() => Track(
      id: 't1',
      name: 'a.mp3',
      durationMs: 240000,
      importedAt: DateTime.utc(2026),
      settings: TrackSettings(pitchSemitones: 3, speed: 0.75, volume: 0.5),
    );

void main() {
  test('applySettings applique les réglages du morceau au moteur', () async {
    final engine = FakeEngine();
    final c = PlayerController(engine, FakeRepo(), _track());
    await c.applySettings();
    expect(engine.pitch, 3);
    expect(engine.speed, 0.75);
    expect(engine.volume, 0.5);
  });

  test('setPitch borne, met à jour le moteur et le track', () async {
    final engine = FakeEngine();
    final c = PlayerController(engine, FakeRepo(), _track());
    await c.setPitch(10);
    expect(engine.pitch, 6);
    expect(c.track.settings.pitchSemitones, 6);
  });

  test('les changements rapprochés ne déclenchent qu’une sauvegarde (debounce)',
      () async {
    final engine = FakeEngine();
    final repo = FakeRepo();
    final c = PlayerController(engine, repo, _track(),
        saveDebounce: const Duration(milliseconds: 20));
    await c.setPitch(1);
    await c.setPitch(2);
    await c.setSpeed(0.5);
    expect(repo.saveCount, 0); // rien encore (debounce)
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(repo.saveCount, 1);
    expect(repo.lastSaved!.pitchSemitones, 2);
    expect(repo.lastSaved!.speed, 0.5);
  });

  test('rewind10s borne à zéro et recule de 10 s', () async {
    final c = PlayerController(FakeEngine(), FakeRepo(), _track());
    await c.rewind10s(const Duration(seconds: 4));
    expect(c.lastSeekTarget, Duration.zero); // 4s - 10s borné à 0
    await c.rewind10s(const Duration(seconds: 30));
    expect(c.lastSeekTarget, const Duration(seconds: 20));
  });
}
```

- [ ] **Step 2 : Lancer (échoue)** — `flutter test test/player_controller_test.dart` → FAIL (`PlayerController` introuvable).

- [ ] **Step 3 : Implémenter**

Créer `lib/features/player/player_controller.dart` :
```dart
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/audio/audio_engine.dart';
import '../../core/audio/pitch_math.dart';
import '../../core/library/library_repository.dart';
import '../../core/library/track.dart';

/// État du lecteur. Délègue l'audio à [AudioEngine] et persiste les réglages du
/// [track] (en debounce) via [LibraryRepository].
class PlayerController extends ChangeNotifier {
  PlayerController(
    this._engine,
    this._repo,
    this.track, {
    this.saveDebounce = const Duration(milliseconds: 500),
  });

  final AudioEngine _engine;
  final LibraryRepository _repo;
  final Track track;
  final Duration saveDebounce;

  bool isPlaying = false;

  /// Dernière cible de seek (exposée pour les tests).
  @visibleForTesting
  Duration lastSeekTarget = Duration.zero;

  Timer? _saveTimer;

  double get pitch => track.settings.pitchSemitones;
  double get speed => track.settings.speed;
  double get volume => track.settings.volume;

  /// Applique au moteur les réglages mémorisés du morceau (après le load).
  Future<void> applySettings() async {
    await _engine.setPitch(track.settings.pitchSemitones);
    await _engine.setSpeed(track.settings.speed);
    await _engine.setVolume(track.settings.volume);
  }

  Future<void> setPitch(double semitones) async {
    track.settings.pitchSemitones = clampSemitones(semitones);
    await _engine.setPitch(track.settings.pitchSemitones);
    _scheduleSave();
    notifyListeners();
  }

  Future<void> setSpeed(double rate) async {
    track.settings.speed = rate;
    await _engine.setSpeed(rate);
    _scheduleSave();
    notifyListeners();
  }

  Future<void> setVolume(double v) async {
    track.settings.volume = v;
    await _engine.setVolume(v);
    _scheduleSave();
    notifyListeners();
  }

  Future<void> play() async {
    await _engine.play();
    isPlaying = true;
    notifyListeners();
  }

  Future<void> pause() async {
    await _engine.pause();
    isPlaying = false;
    notifyListeners();
  }

  Future<void> restart() async => seek(Duration.zero);

  Future<void> seek(Duration position) async {
    lastSeekTarget = position;
    await _engine.seek(position);
  }

  Future<void> rewind10s(Duration current) async {
    final target = current - const Duration(seconds: 10);
    await seek(target < Duration.zero ? Duration.zero : target);
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDebounce, _save);
  }

  void _save() => _repo.updateSettings(track.id, track.settings);

  @override
  void dispose() {
    _saveTimer?.cancel();
    _save(); // sauvegarde finale immédiate en quittant le lecteur
    super.dispose();
  }
}
```

- [ ] **Step 4 : Lancer (passe)** — `flutter test test/player_controller_test.dart` → PASS (4 tests).
- [ ] **Step 5 : Analyse** — `flutter analyze` → clean.
- [ ] **Step 6 : Commit**
```bash
git add lib/features/player/player_controller.dart test/player_controller_test.dart
git commit -m "feat(player): PlayerController (apply + sauvegarde debounce des reglages)"
```

---

## Task 5 : `PlayerPage` (refonte du spike)

**Files:**
- Create: `lib/features/player/player_page.dart`

- [ ] **Step 1 : Implémenter la page lecteur**

Créer `lib/features/player/player_page.dart`. Elle reçoit un `Track` + le `LibraryRepository`, crée son moteur, charge les octets du morceau, applique ses réglages, et auto-sauvegarde via le contrôleur. Scrubber + ⟲−10 s + transport + pitch/vitesse/volume. Pas de bouton boucle.

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/audio/web_audio_engine.dart';
import '../../core/library/library_repository.dart';
import '../../core/library/track.dart';
import 'player_controller.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.track, required this.repo});
  final Track track;
  final LibraryRepository repo;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final WebAudioEngine _engine;
  late final PlayerController _c;
  StreamSubscription<Duration>? _posSub;
  Duration _position = Duration.zero;
  bool _loading = true;
  bool _scrubbing = false;
  double _scrubValue = 0;

  @override
  void initState() {
    super.initState();
    _engine = WebAudioEngine();
    _c = PlayerController(_engine, widget.repo, widget.track);
    _posSub = _engine.position.listen((p) {
      if (!_scrubbing) setState(() => _position = p);
    });
    _engine.init().then((_) => _loadTrack());
  }

  Future<void> _loadTrack() async {
    try {
      final bytes = await widget.repo.loadAudio(widget.track.id);
      await _engine.load(bytes).timeout(const Duration(seconds: 20));
      await _c.applySettings();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Échec du chargement : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _c.dispose();
    _engine.dispose();
    super.dispose();
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final total = Duration(milliseconds: widget.track.durationMs);
    final totalMs = total.inMilliseconds.toDouble();
    final posMs = (_scrubbing ? _scrubValue : _position.inMilliseconds.toDouble())
        .clamp(0, totalMs == 0 ? 1 : totalMs);

    return Scaffold(
      appBar: AppBar(title: Text(widget.track.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : AnimatedBuilder(
              animation: _c,
              builder: (context, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Slider(
                      value: posMs.toDouble(),
                      max: totalMs == 0 ? 1 : totalMs,
                      onChangeStart: (_) => setState(() => _scrubbing = true),
                      onChanged: (v) => setState(() => _scrubValue = v),
                      onChangeEnd: (v) {
                        _c.seek(Duration(milliseconds: v.round()));
                        setState(() {
                          _position = Duration(milliseconds: v.round());
                          _scrubbing = false;
                        });
                      },
                    ),
                    Text('${_fmt(Duration(milliseconds: posMs.round()))} / ${_fmt(total)}'),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          iconSize: 32,
                          tooltip: '−10 s',
                          onPressed: () => _c.rewind10s(_position),
                          icon: const Icon(Icons.replay_10),
                        ),
                        IconButton(
                          iconSize: 44,
                          onPressed: () =>
                              _c.isPlaying ? _c.pause() : _c.play(),
                          icon: Icon(
                              _c.isPlaying ? Icons.pause : Icons.play_arrow),
                        ),
                        IconButton(
                          iconSize: 32,
                          tooltip: 'Redémarrer',
                          onPressed: _c.restart,
                          icon: const Icon(Icons.replay),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('Pitch : ${_c.pitch.toStringAsFixed(0)} demi-tons'),
                    Slider(
                      value: _c.pitch,
                      min: -6,
                      max: 6,
                      divisions: 12,
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
                    Text('Volume : ${(_c.volume * 100).round()} %'),
                    Slider(
                      value: _c.volume,
                      onChanged: (v) => _c.setVolume(v),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
```

- [ ] **Step 2 : Vérifier**

Run : `flutter analyze` → clean.
Run : `MSYS_NO_PATHCONV=1 flutter build web --release --base-href /woodshed/` → succès.
> Audio/scrubber jugés manuellement après l'écran bibliothèque (Task 6) qui permet d'ouvrir un morceau.

- [ ] **Step 3 : Commit**
```bash
git add lib/features/player/player_page.dart
git commit -m "feat(player): PlayerPage (titre, scrubber, -10s, pitch/vitesse/volume)"
```

---

## Task 6 : `LibraryPage` + navigation + `main.dart` + persist + nettoyage

**Files:**
- Create: `lib/core/io/persistent_storage.dart`
- Create: `lib/features/library/library_page.dart`
- Modify: `lib/main.dart`
- Delete: `lib/features/spike/spike_page.dart`, `lib/features/spike/spike_controller.dart`, `test/spike_controller_test.dart`
- Modify: `pubspec.yaml` (retirer `file_picker`, désormais inutilisé)

- [ ] **Step 1 : Util stockage persistant**

Créer `lib/core/io/persistent_storage.dart` :
```dart
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Demande au navigateur de rendre le stockage persistant (best-effort).
/// Réduit le risque d'éviction d'IndexedDB sur iOS (surtout en PWA installée).
Future<void> requestPersistentStorage() async {
  try {
    final storage = web.window.navigator.storage;
    await storage.persist().toDart;
  } catch (_) {
    // Non supporté / refusé : on continue sans garantie.
  }
}
```

- [ ] **Step 2 : Écran bibliothèque**

Créer `lib/features/library/library_page.dart` :
```dart
import 'package:flutter/material.dart';
import '../../core/audio/probe_duration.dart';
import '../../core/io/audio_file_picker.dart';
import '../../core/library/library_repository.dart';
import '../../core/library/track.dart';
import '../player/player_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.repo});
  final LibraryRepository repo;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  late Future<List<Track>> _tracks;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() => _tracks = widget.repo.listTracks());
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 6)));
  }

  Future<void> _import() async {
    final picked = await pickAudioFile();
    if (picked == null) return;
    setState(() => _importing = true);
    try {
      final duration = await probeAudioDuration(picked.bytes);
      await widget.repo.addTrack(picked.name, picked.bytes, duration);
      _reload();
    } catch (e) {
      _snack('Import impossible (format non décodable sur iOS ? MP3/M4A/WAV) : $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _open(Track t) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerPage(track: t, repo: widget.repo)),
    );
    _reload(); // au retour : la durée/les réglages ont pu changer
  }

  Future<void> _delete(Track t) async {
    await widget.repo.deleteTrack(t.id);
    _reload();
  }

  String _fmt(int ms) {
    final d = Duration(milliseconds: ms);
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('woodshed')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _import,
        icon: _importing
            ? const SizedBox(
                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add),
        label: Text(_importing ? 'Import…' : 'Importer'),
      ),
      body: FutureBuilder<List<Track>>(
        future: _tracks,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final tracks = snap.data!;
          if (tracks.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Aucun morceau. Touche « Importer » pour en ajouter.',
                    textAlign: TextAlign.center),
              ),
            );
          }
          return ListView.builder(
            itemCount: tracks.length,
            itemBuilder: (context, i) {
              final t = tracks[i];
              return Dismissible(
                key: ValueKey(t.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (_) => _delete(t),
                child: ListTile(
                  leading: const Icon(Icons.music_note),
                  title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_fmt(t.durationMs)),
                  onTap: () => _open(t),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 3 : `main.dart`**

Remplacer tout le contenu de `lib/main.dart` par :
```dart
import 'package:flutter/material.dart';
import 'package:idb_shim/idb_browser.dart';

import 'core/io/persistent_storage.dart';
import 'core/library/idb_library_repository.dart';
import 'core/library/library_repository.dart';
import 'features/library/library_page.dart';

void main() {
  final repo = IdbLibraryRepository(idbFactoryBrowser);
  requestPersistentStorage();
  runApp(WoodshedApp(repo: repo));
}

class WoodshedApp extends StatelessWidget {
  const WoodshedApp({super.key, required this.repo});
  final LibraryRepository repo;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'woodshed',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        home: LibraryPage(repo: repo),
      );
}
```

- [ ] **Step 4 : Supprimer le spike obsolète**

```bash
git rm lib/features/spike/spike_page.dart lib/features/spike/spike_controller.dart test/spike_controller_test.dart
```

- [ ] **Step 5 : Retirer `file_picker` de `pubspec.yaml`**

Supprimer la ligne `file_picker: ^11.0.2` de `pubspec.yaml` (remplacé par le sélecteur natif), puis `flutter pub get`.

- [ ] **Step 6 : Vérifier**

Run : `flutter analyze` → `No issues found!` (aucune référence résiduelle à `spike_*` ni à `file_picker`).
Run : `flutter test` → tous les tests passent (track, idb_repo, player_controller, pitch_math).
Run : `MSYS_NO_PATHCONV=1 flutter build web --release --base-href /woodshed/` → succès.

- [ ] **Step 7 : Commit**
```bash
git add -A
git commit -m "feat(library): ecran Bibliotheque + navigation + persist + retrait du spike/file_picker"
```

---

## Task 7 : Validation sur appareil (manuelle)

Après déploiement (push → GitHub Pages), sur iPhone (cache PWA vidé) :
- [ ] Importer un morceau → il apparaît dans la liste avec sa durée.
- [ ] Fermer/rouvrir la PWA → le morceau est **toujours là** (persistance OK).
- [ ] Ouvrir le morceau → il charge ; régler pitch/vitesse/**volume** ; revenir à la liste ; rouvrir → **les réglages sont conservés**.
- [ ] Scrubber : glisser déplace la lecture ; ⟲−10 s recule.
- [ ] Supprimer un morceau (swipe) → disparaît et ne revient pas après réouverture.

Consigner tout souci ; sinon l'incrément est livré.

---

## Notes d'exécution

- **Testé automatiquement** : modèles (JSON), dépôt IndexedDB (factory mémoire), logique du contrôleur (apply + debounce). Le reste (Web Audio, IndexedDB navigateur réel, UI) est validé **manuellement** (Task 7).
- **Build local Windows** : préfixer `MSYS_NO_PATHCONV=1` devant `flutter build web ... --base-href /woodshed/` (Git Bash mange le `/woodshed/` sinon).
- **Déploiement** : le workflow GitHub Pages se déclenche au push sur `spike/web-audio-engine`.
