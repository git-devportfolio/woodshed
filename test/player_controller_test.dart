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
  Duration? loopA, loopB;
  bool loopEnabled = false;
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
  Future<void> setLoop(bool on) async { loopEnabled = on; }
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
  Future<void> setLoopRange(Duration a, Duration b) async { loopA = a; loopB = b; }
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

  test('les changements rapprochés ne déclenchent qu\'une sauvegarde (debounce)',
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

  test('restart va à loopA quand la boucle est active', () async {
    final c = PlayerController(FakeEngine(), FakeRepo(), _track());
    await c.setLoopA(const Duration(seconds: 30));
    await c.toggleLoop();
    await c.restart();
    expect(c.lastSeekTarget, const Duration(seconds: 30));
  });

  test('restart va à 0 sans boucle', () async {
    final c = PlayerController(FakeEngine(), FakeRepo(), _track());
    await c.restart();
    expect(c.lastSeekTarget, Duration.zero);
  });

  test('play se cale sur loopA si boucle active et position hors [A,B]', () async {
    final c = PlayerController(FakeEngine(), FakeRepo(), _track());
    await c.setLoopA(const Duration(seconds: 20));
    await c.setLoopB(const Duration(seconds: 40));
    await c.toggleLoop();
    c.currentPosition = Duration.zero;
    await c.play();
    expect(c.lastSeekTarget, const Duration(seconds: 20));
  });

  test('resetLoop remet A=0 et B=durée', () async {
    final engine = FakeEngine();
    final c = PlayerController(engine, FakeRepo(), _track());
    await c.setLoopA(const Duration(seconds: 30));
    await c.setLoopB(const Duration(seconds: 60));
    await c.resetLoop();
    expect(c.loopA, Duration.zero);
    expect(c.loopB, const Duration(milliseconds: 240000));
    expect(engine.loopA, Duration.zero);
    expect(engine.loopB, const Duration(milliseconds: 240000));
  });
}
