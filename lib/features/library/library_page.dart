import 'package:flutter/material.dart';
import '../../core/audio/probe_duration.dart';
import '../../core/io/audio_file_picker.dart';
import '../../core/library/library_repository.dart';
import '../../core/library/track.dart';
import '../player/player_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.repo});
  final LibraryRepository repo;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  late Future<List<Track>> _tracks;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() => _tracks = widget.repo.listTracks());
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 6)));
  }

  Future<void> _import() async {
    final picked = await pickAudioFile();
    if (picked == null) return;
    setState(() => _importing = true);
    try {
      final duration = await probeAudioDuration(picked.bytes);
      await widget.repo.addTrack(picked.name, picked.bytes, duration);
      _reload();
    } catch (e) {
      _snack('Import impossible (format non décodable sur iOS ? MP3/M4A/WAV) : $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _open(Track t) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerPage(track: t, repo: widget.repo)),
    );
    _reload(); // au retour : la durée/les réglages ont pu changer
  }

  Future<void> _delete(Track t) async {
    await widget.repo.deleteTrack(t.id);
    _reload();
  }

  String _fmt(int ms) {
    final d = Duration(milliseconds: ms);
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('woodshed')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _import,
        icon: _importing
            ? const SizedBox(
                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add),
        label: Text(_importing ? 'Import…' : 'Importer'),
      ),
      body: FutureBuilder<List<Track>>(
        future: _tracks,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final tracks = snap.data!;
          if (tracks.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Aucun morceau. Touche « Importer » pour en ajouter.',
                    textAlign: TextAlign.center),
              ),
            );
          }
          return ListView.builder(
            itemCount: tracks.length,
            itemBuilder: (context, i) {
              final t = tracks[i];
              return Dismissible(
                key: ValueKey(t.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (_) => _delete(t),
                child: ListTile(
                  leading: const Icon(Icons.music_note),
                  title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_fmt(t.durationMs)),
                  onTap: () => _open(t),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
