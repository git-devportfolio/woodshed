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

  test('TrackSettings.fromJson tolère les clés manquantes', () {
    final s = TrackSettings.fromJson({});
    expect(s.pitchSemitones, 0);
    expect(s.speed, 1.0);
    expect(s.volume, 1.0);
  });

  test('Track.fromJson lève une FormatException sur JSON invalide', () {
    expect(() => Track.fromJson({'name': 'x'}), throwsFormatException);
  });

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
}
