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
  external JSPromise<JSAny?> setEngine(String id);
  external int getGlitchCount();
  external double get duration;
  external void onPosition(JSFunction cb);
  external void resume();
  external void dispose();
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

  @override
  Future<void> dispose() async {
    _facade.dispose();
    await _positionController.close();
  }

  @override
  Future<void> setVolume(double volume) async =>
      throw UnimplementedError('Hors périmètre du spike');
  @override
  Future<void> setLoopRange(Duration a, Duration b) async =>
      throw UnimplementedError('Hors périmètre du spike');
}
