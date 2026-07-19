import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/audio/export_naming.dart';
import '../../core/audio/web_audio_engine.dart';
import '../../core/io/share_file.dart';
import '../../core/library/track.dart';
import 'player_controller.dart';

enum _Scope { whole, loop }

class ExportSheet extends StatefulWidget {
  const ExportSheet({
    super.key,
    required this.engine,
    required this.controller,
    required this.track,
  });
  final WebAudioEngine engine;
  final PlayerController controller;
  final Track track;

  @override
  State<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<ExportSheet> {
  _Scope _scope = _Scope.whole;
  bool _generating = false;
  Uint8List? _mp3;
  String? _fileName;

  Duration get _total => Duration(milliseconds: widget.track.durationMs);
  bool get _hasLoop =>
      widget.controller.loopA > Duration.zero || widget.controller.loopB < _total;

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _generate() async {
    if (_generating) return;
    setState(() {
      _generating = true;
      _mp3 = null;
    });
    try {
      final loop = _scope == _Scope.loop;
      final from = loop ? widget.controller.loopA : Duration.zero;
      final to = loop ? widget.controller.loopB : _total;
      final pitch = widget.controller.pitch;
      final speed = widget.controller.speed;
      final bytes = await widget.engine.exportMp3(
        from: from,
        to: to,
        pitchSemitones: pitch,
        speed: speed,
      );
      if (!mounted) return;
      setState(() {
        _mp3 = bytes;
        _fileName = exportFileName(widget.track.name, pitch, speed);
      });
    } catch (e) {
      _snack('Échec de l\'export : $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kb = _mp3 == null ? 0 : (_mp3!.length / 1024).round();
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Exporter en MP3', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          const Text('Portée'),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Morceau entier'),
                selected: _scope == _Scope.whole,
                onSelected: (_) => setState(() {
                  _scope = _Scope.whole;
                  _mp3 = null;
                  _fileName = null;
                }),
              ),
              ChoiceChip(
                label: const Text('Boucle A/B'),
                selected: _scope == _Scope.loop,
                onSelected: _hasLoop
                    ? (_) => setState(() {
                          _scope = _Scope.loop;
                          _mp3 = null;
                          _fileName = null;
                        })
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _generating ? null : _generate,
            icon: _generating
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.graphic_eq),
            label: Text(_generating ? 'Génération…' : 'Générer le MP3'),
          ),
          if (_mp3 != null) ...[
            const SizedBox(height: 16),
            Text('$_fileName · $kb Ko', textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => shareOrDownloadFile(_mp3!, _fileName!, 'audio/mpeg'),
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Partager'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => downloadFile(_mp3!, _fileName!, 'audio/mpeg'),
                    icon: const Icon(Icons.download),
                    label: const Text('Télécharger'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
