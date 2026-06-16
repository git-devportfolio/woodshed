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
