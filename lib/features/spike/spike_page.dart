import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/audio/engine_kind.dart';
import '../../core/audio/web_audio_engine.dart';
import '../../core/io/audio_file_picker.dart';
import 'spike_controller.dart';

class SpikePage extends StatefulWidget {
  const SpikePage({super.key});
  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> {
  late final WebAudioEngine _engine;
  late final SpikeController _c;
  StreamSubscription<Duration>? _posSub;
  Duration _position = Duration.zero;
  bool _engineReady = false;
  bool _loading = false;
  String? _trackName;

  @override
  void initState() {
    super.initState();
    _engine = WebAudioEngine();
    _c = SpikeController(_engine);
    _engine.init().then((_) {
      if (mounted) setState(() => _engineReady = true);
    });
    _posSub = _engine.position.listen((p) => setState(() => _position = p));
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _c.dispose();
    _engine.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    PickedAudio? picked;
    try {
      picked = await pickAudioFile();
    } catch (e) {
      _showMessage('Sélecteur de fichiers indisponible : $e');
      return;
    }
    if (picked == null) return; // annulé / aucun fichier
    setState(() => _loading = true);
    try {
      await _c.load(picked.bytes).timeout(const Duration(seconds: 20));
      if (mounted) setState(() => _trackName = picked!.name);
    } on TimeoutException {
      _showMessage('Le chargement a expiré : le contexte audio iOS est peut-être resté '
          'suspendu. Touche l\'écran, puis réessaie.');
    } catch (e) {
      // Affiche l'erreur réelle (décodage iOS, worklet, etc.) au lieu d'échouer en silence.
      _showMessage('Échec du chargement de « ${picked.name} » : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 6)),
    );
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
                onPressed: (_engineReady && !_loading) ? _pickFile : null,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.folder_open),
                label: Text(!_engineReady
                    ? 'Initialisation du moteur…'
                    : _loading
                        ? 'Chargement…'
                        : 'Charger un morceau'),
              ),
              const SizedBox(height: 16),
              if (_trackName != null) ...[
                Text(
                  _trackName!,
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
              ],
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
                children: [EngineKind.plain, EngineKind.soundTouch, EngineKind.rubberBand]
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
