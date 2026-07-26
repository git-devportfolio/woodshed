import 'package:flutter/material.dart';

/// Bloc de transport : quatre grandes cibles sur une ligne, play/pause dominant.
///
/// Les quatre conteneurs ont la même taille ; la dominance de play/pause vient
/// de son remplissage en couleur d'accent et de son icône plus grande.
class TransportBar extends StatelessWidget {
  const TransportBar({
    super.key,
    required this.isPlaying,
    required this.onRewind,
    required this.onPlayPause,
    required this.onForward,
    required this.onRestart,
  });

  static const height = 76.0;
  static const _gap = 12.0;
  static const _radius = 20.0;
  static const _playIconSize = 48.0;
  static const _skipIconSize = 34.0;

  final bool isPlaying;
  final VoidCallback onRewind;
  final VoidCallback onPlayPause;
  final VoidCallback onForward;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: _button(
              name: 'rewind',
              tooltip: '−10 s',
              icon: Icons.replay_10,
              iconSize: _skipIconSize,
              onPressed: onRewind,
            ),
          ),
          const SizedBox(width: _gap),
          Expanded(
            child: _button(
              name: 'play',
              tooltip: isPlaying ? 'Pause' : 'Lecture',
              icon: isPlaying ? Icons.pause : Icons.play_arrow,
              iconSize: _playIconSize,
              onPressed: onPlayPause,
              primary: true,
            ),
          ),
          const SizedBox(width: _gap),
          Expanded(
            child: _button(
              name: 'forward',
              tooltip: '+10 s',
              icon: Icons.forward_10,
              iconSize: _skipIconSize,
              onPressed: onForward,
            ),
          ),
          const SizedBox(width: _gap),
          Expanded(
            child: _button(
              name: 'restart',
              tooltip: 'Redémarrer',
              icon: Icons.replay,
              iconSize: _skipIconSize,
              onPressed: onRestart,
            ),
          ),
        ],
      );

  Widget _button({
    required String name,
    required String tooltip,
    required IconData icon,
    required double iconSize,
    required VoidCallback onPressed,
    bool primary = false,
  }) {
    final style = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(height),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
      ),
    );
    final child = Icon(icon, size: iconSize);
    final key = ValueKey('transport-$name');

    return Tooltip(
      message: tooltip,
      child: primary
          ? FilledButton(key: key, style: style, onPressed: onPressed, child: child)
          : FilledButton.tonal(key: key, style: style, onPressed: onPressed, child: child),
    );
  }
}
