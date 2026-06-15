import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed/core/audio/audio_engine.dart';
import 'package:woodshed/core/audio/engine_kind.dart';
import 'package:woodshed/features/spike/spike_controller.dart';

class FakeAudioEngine implements AudioEngine {
  final calls = <String>[];
  double lastPitch = 0, lastSpeed = 1;
  EngineKind lastEngine = EngineKind.plain;
  final _pos = StreamController<Duration>.broadcast();

  @override
  Future<void> load(Uint8List bytes) async => calls.add('load');
  @override
  Future<void> play() async => calls.add('play');
  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> seek(Duration p) async => calls.add('seek:$p');
  @override
  Future<void> setSpeed(double r) async { lastSpeed = r; }
  @override
  Future<void> setPitch(double s) async { lastPitch = s; }
  @override
  Future<void> setLoop(bool l) async => calls.add('loop:$l');
  @override
  Future<void> setEngine(EngineKind k) async { lastEngine = k; }
  @override
  Stream<Duration> get position => _pos.stream;
  @override
  Duration get duration => const Duration(minutes: 4);
  @override
  int get glitchCount => 0;
  @override
  Future<void> dispose() async => _pos.close();
  @override
  Future<void> setVolume(double v) async {}
  @override
  Future<void> setLoopRange(Duration a, Duration b) async {}
}

void main() {
  late FakeAudioEngine engine;
  late SpikeController controller;

  setUp(() {
    engine = FakeAudioEngine();
    controller = SpikeController(engine);
  });

  test('le pitch est borné à +6', () async {
    await controller.setPitch(10);
    expect(engine.lastPitch, 6.0);
    expect(controller.pitch, 6.0);
  });

  test('le pitch est borné à -6', () async {
    await controller.setPitch(-99);
    expect(engine.lastPitch, -6.0);
  });

  test('changer de moteur délègue au moteur', () async {
    await controller.setEngine(EngineKind.soundTouch);
    expect(engine.lastEngine, EngineKind.soundTouch);
    expect(controller.engine, EngineKind.soundTouch);
  });

  test('setSpeed délègue la valeur', () async {
    await controller.setSpeed(0.75);
    expect(engine.lastSpeed, 0.75);
    expect(controller.speed, 0.75);
  });
}
