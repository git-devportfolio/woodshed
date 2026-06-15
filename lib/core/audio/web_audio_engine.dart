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
    await _facade.load(bytes.toJS).toDart;
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
