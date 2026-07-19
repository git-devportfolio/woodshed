import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'audio_engine.dart';
import 'engine_kind.dart';

@JS('woodshedAudio')
external _Facade get _facade;

extension type _Facade._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> init();
  external JSPromise<JSAny?> load(JSUint8Array data);
  external void play();
  external void pause();
  external void seek(double seconds);
  external void setTempo(double ratio);
  external void setPitchSemitones(double n);
  external void setLoop(bool loop);
  external void setLoopRange(double aSec, double bSec);
  external JSPromise<JSAny?> setEngine(String id);
  external int getGlitchCount();
  external JSArray<JSNumber> getPeaks();
  external double get duration;
  external void setVolume(double v);
  external void onPosition(JSFunction cb);
  external void resume();
  external void dispose();
  external JSPromise<JSUint8Array> renderMp3(
      double fromSec, double toSec, double pitchSemitones, double speed);
}

/// Implémentation [AudioEngine] sur le web, proxy vers la façade `window.woodshedAudio`.
class WebAudioEngine implements AudioEngine {
  final _positionController = StreamController<Duration>.broadcast();
  Duration _duration = Duration.zero;
  Future<void>? _ready;

  /// Doit être appelée avant toute autre opération : initialise l'AudioContext
  /// et le backend côté façade JS, et branche le flux de position.
  Future<void> init() {
    _facade.onPosition(
      ((double seconds) {
        _positionController.add(
            Duration(milliseconds: (seconds * 1000).round()));
      }).toJS,
    );
    return _ready = _facade.init().toDart.then((_) {});
  }

  /// Se résout quand le moteur (AudioContext + worklet) est prêt.
  Future<void> get ready => _ready ?? Future<void>.value();

  @override
  Future<void> load(Uint8List bytes) async {
    // Attendre que le moteur soit prêt : sinon le 1er import (worklet Rubber Band
    // ~612 Ko encore en cours de chargement) n'aboutit pas et le Play reste grisé.
    await ready;
    await _facade.load(bytes.toJS).toDart;
    _duration = Duration(milliseconds: (_facade.duration * 1000).round());
  }

  /// Reprend l'AudioContext. À appeler DANS un geste utilisateur (iOS exige
  /// resume() pendant un geste, sinon le contexte reste suspendu et
  /// decodeAudioData ne se résout jamais).
  void resume() => _facade.resume();

  @override
  Future<void> play() async => _facade.play();
  @override
  Future<void> pause() async => _facade.pause();
  @override
  Future<void> seek(Duration position) async =>
      _facade.seek(position.inMilliseconds / 1000.0);
  @override
  Future<void> setSpeed(double rate) async => _facade.setTempo(rate); // vitesse -> tempo (façade)
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

  /// Pics de waveform normalisés [0,1] du morceau courant (≈800 points).
  List<double> get waveformPeaks =>
      _facade.getPeaks().toDart.map((e) => e.toDartDouble).toList();

  @override
  Future<void> dispose() async {
    _facade.dispose();
    await _positionController.close();
  }

  @override
  Future<void> setVolume(double volume) async => _facade.setVolume(volume);
  @override
  Future<void> setLoopRange(Duration a, Duration b) async =>
      _facade.setLoopRange(a.inMilliseconds / 1000.0, b.inMilliseconds / 1000.0);

  /// Rend l'audio traité (pitch/vitesse courants) entre [from] et [to] et renvoie un MP3.
  Future<Uint8List> exportMp3({
    required Duration from,
    required Duration to,
    required double pitchSemitones,
    required double speed,
  }) async {
    final result = await _facade
        .renderMp3(from.inMilliseconds / 1000.0, to.inMilliseconds / 1000.0,
            pitchSemitones, speed)
        .toDart;
    return result.toDart;
  }
}
