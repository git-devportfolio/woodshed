import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/audio/engine_kind.dart';
import '../../core/audio/web_audio_engine.dart';
import 'spike_controller.dart';

class SpikePage extends StatefulWidget {
  const SpikePage({super.key});
  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> {
  late final WebAudioEngine _engine;
  late final SpikeController _c;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _engine = WebAudioEngine();
    _c = SpikeController(_engine);
    _engine.init();
    _engine.position.listen((p) => setState(() => _position = p));
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(
        type: FileType.audio, withData: true);
    final bytes = result?.files.single.bytes;
    if (bytes == null) return;
    await _engine.load(bytes);
    setState(() => _c.loaded = true);
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Spike moteur audio')),
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.folder_open),
                label: const Text('Charger un morceau'),
              ),
              const SizedBox(height: 16),
              Text('${_fmt(_position)} / ${_fmt(_engine.duration)}'),
              Text('Moteur : ${_c.engine.name} · glitches : ${_engine.glitchCount}'),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 40,
                    onPressed: _c.loaded
                        ? () => _c.isPlaying ? _c.pause() : _c.play()
                        : null,
                    icon: Icon(_c.isPlaying ? Icons.pause : Icons.play_arrow),
                  ),
                  IconButton(
                    iconSize: 32,
                    onPressed: _c.loaded ? _c.restart : null,
                    icon: const Icon(Icons.replay),
                  ),
                  IconButton(
                    iconSize: 32,
                    onPressed: _c.loaded ? _c.toggleLoop : null,
                    icon: Icon(_c.looping ? Icons.repeat_on : Icons.repeat),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Pitch : ${_c.pitch.toStringAsFixed(0)} demi-tons'),
              Slider(
                value: _c.pitch,
                min: -6, max: 6, divisions: 12,
                label: _c.pitch.toStringAsFixed(0),
                onChanged: (v) => _c.setPitch(v),
              ),
              const SizedBox(height: 8),
              const Text('Vitesse'),
              Wrap(
                spacing: 8,
                children: [0.5, 0.75, 1.0]
                    .map((r) => ChoiceChip(
                          label: Text('${r}x'),
                          selected: _c.speed == r,
                          onSelected: (_) => _c.setSpeed(r),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
              const Text('Moteur'),
              Wrap(
                spacing: 8,
                children: [EngineKind.soundTouch, EngineKind.rubberBand]
                    .map((k) => ChoiceChip(
                          label: Text(k.name),
                          selected: _c.engine == k,
                          onSelected: (_) => _c.setEngine(k),
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
