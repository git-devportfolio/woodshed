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
}
