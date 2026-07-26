import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/audio/web_audio_engine.dart';
import '../../core/library/library_repository.dart';
import '../../core/library/track.dart';
import 'export_sheet.dart';
import 'player_controller.dart';
import 'waveform_view.dart';
import 'widgets/pitch_stepper.dart';
import 'widgets/section_label.dart';
import 'widgets/speed_selector.dart';
import 'widgets/transport_bar.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.track, required this.repo, required this.engine});
  final Track track;
  final LibraryRepository repo;
  final WebAudioEngine engine;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final PlayerController _c;
  StreamSubscription<Duration>? _posSub;
  Duration _position = Duration.zero;
  bool _loading = true;
  List<double> _peaks = const [];

  /// Hauteur cumulée de tout le corps sauf la waveform (spec §7) : padding 32 +
  /// ligne temps/boucle 56 + transport 76 + pitch 94 + vitesse 86 + volume 70 +
  /// écarts 52.
  static const _fixedBodyHeight = 466.0;

  @override
  void initState() {
    super.initState();
    _c = PlayerController(widget.engine, widget.repo, widget.track);
    _posSub = widget.engine.position.listen((p) {
      _c.currentPosition = p;
      if (!_loading) setState(() => _position = p);
    });
    _loadAndPlay();
  }

  Future<void> _loadAndPlay() async {
    if (mounted) setState(() => _loading = true);
    try {
      final bytes = await widget.repo.loadAudio(widget.track.id);
      await widget.engine.load(bytes).timeout(const Duration(seconds: 20));
      if (mounted) {
        setState(() {
          _position = Duration.zero;
          _peaks = widget.engine.waveformPeaks;
        });
      }
      await _c.applySettings();
      await _c.play();
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
    widget.engine.pause(); // stoppe la lecture (effet synchrone ; moteur partagé NON disposé ici)
    super.dispose();
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final total = Duration(milliseconds: widget.track.durationMs);
    final totalMs = total.inMilliseconds.toDouble();
    final posMs = _position.inMilliseconds.toDouble().clamp(0, totalMs == 0 ? 1 : totalMs);

    return Scaffold(
      appBar: AppBar(
        title: Hero(
          tag: 'track-title-${widget.track.id}',
          child: Material(
            type: MaterialType.transparency,
            child: Text(widget.track.name),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Exporter / Partager',
            icon: const Icon(Icons.ios_share),
            onPressed: _loading
                ? null
                : () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => ExportSheet(
                        engine: widget.engine,
                        controller: _c,
                        track: widget.track,
                      ),
                    ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final waveformHeight =
                    (constraints.maxHeight - _fixedBodyHeight)
                        .clamp(96.0, 180.0);

                return AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) => SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          WaveformView(
                            height: waveformHeight,
                            peaks: _peaks,
                            duration: total,
                            position: Duration(milliseconds: posMs.round()),
                            loopA: _c.loopA,
                            loopB: _c.loopB,
                            loopEnabled: _c.loopEnabled,
                            onSeek: (t) {
                              _c.seek(t);
                              setState(() => _position = t);
                            },
                            onSetA: (t) => _c.setLoopA(t),
                            onSetB: (t) => _c.setLoopB(t),
                          ),
                          SizedBox(
                            height: 56,
                            child: Row(
                              children: [
                                Text(
                                  '${_fmt(Duration(milliseconds: posMs.round()))} / ${_fmt(total)}',
                                  style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600),
                                ),
                                const Spacer(),
                                FilledButton.tonalIcon(
                                  style: FilledButton.styleFrom(
                                    minimumSize:
                                        const Size.fromHeight(56),
                                  ),
                                  onPressed: _c.toggleLoop,
                                  icon: Icon(_c.loopEnabled
                                      ? Icons.repeat_on
                                      : Icons.repeat),
                                  label: Text(_c.loopEnabled
                                      ? 'Boucle A–B : ON'
                                      : 'Boucle A–B'),
                                ),
                                IconButton(
                                  tooltip: 'Réinitialiser la boucle',
                                  onPressed: _c.resetLoop,
                                  icon: const Icon(
                                      Icons.settings_backup_restore),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          TransportBar(
                            isPlaying: _c.isPlaying,
                            onRewind: () => _c.rewind10s(_position),
                            onPlayPause: () =>
                                _c.isPlaying ? _c.pause() : _c.play(),
                            onForward: () => _c.forward10s(_position),
                            onRestart: () {
                              _c.restart();
                              setState(() => _position =
                                  _c.loopEnabled ? _c.loopA : Duration.zero);
                            },
                          ),
                          const SizedBox(height: 16),
                          PitchStepper(
                            pitch: _c.pitch,
                            onChanged: _c.setPitch,
                          ),
                          const SizedBox(height: 12),
                          SpeedSelector(
                            speed: _c.speed,
                            onChanged: _c.setSpeed,
                          ),
                          const SizedBox(height: 12),
                          SectionLabel(
                              'Volume : ${(_c.volume * 100).round()} %'),
                          Slider(
                            value: _c.volume,
                            onChanged: (v) => _c.setVolume(v),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
