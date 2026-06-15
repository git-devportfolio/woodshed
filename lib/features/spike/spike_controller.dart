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
  EngineKind engine = EngineKind.soundTouch;

  Future<void> load(Uint8List bytes) async {
    await _engine.load(bytes);
    loaded = true;
    notifyListeners();
  }

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

  Future<void> restart() async {
    await _engine.seek(Duration.zero);
  }
}
