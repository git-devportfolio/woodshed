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
  bool _disposed = false;

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
    if (_disposed) return;
    _scheduleSave();
    notifyListeners();
  }

  Future<void> setSpeed(double rate) async {
    track.settings.speed = rate;
    await _engine.setSpeed(rate);
    if (_disposed) return;
    _scheduleSave();
    notifyListeners();
  }

  Future<void> setVolume(double v) async {
    track.settings.volume = v.clamp(0.0, 1.0);
    await _engine.setVolume(track.settings.volume);
    if (_disposed) return;
    _scheduleSave();
    notifyListeners();
  }

  Future<void> play() async {
    await _engine.play();
    if (_disposed) return;
    isPlaying = true;
    notifyListeners();
  }

  Future<void> pause() async {
    await _engine.pause();
    if (_disposed) return;
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
    _disposed = true;
    _saveTimer?.cancel();
    _save(); // sauvegarde finale en quittant (fire-and-forget : non attendue)
    super.dispose();
  }
}
