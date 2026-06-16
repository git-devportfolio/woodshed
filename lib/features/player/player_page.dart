import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/audio/web_audio_engine.dart';
import '../../core/library/library_repository.dart';
import '../../core/library/track.dart';
import 'player_controller.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.track, required this.repo});
  final Track track;
  final LibraryRepository repo;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final WebAudioEngine _engine;
  late final PlayerController _c;
  StreamSubscription<Duration>? _posSub;
  Duration _position = Duration.zero;
  bool _loading = true;
  bool _scrubbing = false;
  double _scrubValue = 0;

  @override
  void initState() {
    super.initState();
    _engine = WebAudioEngine();
    _c = PlayerController(_engine, widget.repo, widget.track);
    _posSub = _engine.position.listen((p) {
      if (!_scrubbing) setState(() => _position = p);
    });
    _engine.init().then((_) {
      if (mounted) _loadTrack();
    });
  }

  Future<void> _loadTrack() async {
    try {
      final bytes = await widget.repo.loadAudio(widget.track.id);
      await _engine.load(bytes).timeout(const Duration(seconds: 20));
      await _c.applySettings();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Échec du chargement : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _c.dispose();
    _engine.dispose();
    super.dispose();
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final total = Duration(milliseconds: widget.track.durationMs);
    final totalMs = total.inMilliseconds.toDouble();
    final posMs = (_scrubbing ? _scrubValue : _position.inMilliseconds.toDouble())
        .clamp(0, totalMs == 0 ? 1 : totalMs);

    return Scaffold(
      appBar: AppBar(title: Text(widget.track.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : AnimatedBuilder(
              animation: _c,
              builder: (context, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Slider(
                      value: posMs.toDouble(),
                      max: totalMs == 0 ? 1 : totalMs,
                      onChangeStart: (_) => setState(() => _scrubbing = true),
                      onChanged: (v) => setState(() => _scrubValue = v),
                      onChangeEnd: (v) {
                        _c.seek(Duration(milliseconds: v.round()));
                        setState(() {
                          _position = Duration(milliseconds: v.round());
                          _scrubbing = false;
                        });
                      },
                    ),
                    Text('${_fmt(Duration(milliseconds: posMs.round()))} / ${_fmt(total)}'),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          iconSize: 32,
                          tooltip: '−10 s',
                          onPressed: () => _c.rewind10s(_position),
                          icon: const Icon(Icons.replay_10),
                        ),
                        IconButton(
                          iconSize: 44,
                          onPressed: () =>
                              _c.isPlaying ? _c.pause() : _c.play(),
                          icon: Icon(
                              _c.isPlaying ? Icons.pause : Icons.play_arrow),
                        ),
                        IconButton(
                          iconSize: 32,
                          tooltip: 'Redémarrer',
                          onPressed: _c.restart,
                          icon: const Icon(Icons.replay),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('Pitch : ${_c.pitch.toStringAsFixed(0)} demi-tons'),
                    Slider(
                      value: _c.pitch,
                      min: -6,
                      max: 6,
                      divisions: 12,
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
                    Text('Volume : ${(_c.volume * 100).round()} %'),
                    Slider(
                      value: _c.volume,
                      onChanged: (v) => _c.setVolume(v),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
