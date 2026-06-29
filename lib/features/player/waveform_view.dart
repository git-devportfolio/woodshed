import 'package:flutter/material.dart';

/// Waveform interactive : pics, tête de lecture, zone de boucle [A,B] + poignées.
/// Tap = seek ; glisser une poignée = régler A ou B.
class WaveformView extends StatefulWidget {
  const WaveformView({
    super.key,
    required this.peaks,
    required this.duration,
    required this.position,
    required this.loopA,
    required this.loopB,
    required this.loopEnabled,
    required this.onSeek,
    required this.onSetA,
    required this.onSetB,
    this.height = 120,
  });

  final List<double> peaks;
  final Duration duration;
  final Duration position;
  final Duration loopA;
  final Duration loopB;
  final bool loopEnabled;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<Duration> onSetA;
  final ValueChanged<Duration> onSetB;
  final double height;

  @override
  State<WaveformView> createState() => _WaveformViewState();
}

enum _Handle { none, a, b }

class _WaveformViewState extends State<WaveformView> {
  _Handle _dragging = _Handle.none;

  double _timeToX(Duration t, double width) {
    final ms = widget.duration.inMilliseconds;
    if (ms == 0) return 0;
    return (t.inMilliseconds / ms) * width;
  }

  Duration _xToTime(double x, double width) {
    if (width == 0) return Duration.zero;
    final frac = (x / width).clamp(0.0, 1.0);
    return Duration(milliseconds: (frac * widget.duration.inMilliseconds).round());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const touch = 24.0; // tolérance tactile autour d'une poignée
        return GestureDetector(
          onTapDown: (d) => widget.onSeek(_xToTime(d.localPosition.dx, width)),
          onHorizontalDragStart: (d) {
            final x = d.localPosition.dx;
            final ax = _timeToX(widget.loopA, width);
            final bx = _timeToX(widget.loopB, width);
            if ((x - ax).abs() <= touch) {
              _dragging = _Handle.a;
            } else if ((x - bx).abs() <= touch) {
              _dragging = _Handle.b;
            } else {
              _dragging = _Handle.none; // drag hors poignée : ignoré (le seek se fait au tap)
            }
          },
          onHorizontalDragUpdate: (d) {
            if (_dragging == _Handle.none) return;
            final t = _xToTime(d.localPosition.dx, width);
            if (_dragging == _Handle.a) {
              widget.onSetA(t);
            } else if (_dragging == _Handle.b) {
              widget.onSetB(t);
            }
          },
          onHorizontalDragEnd: (_) => _dragging = _Handle.none,
          child: CustomPaint(
            size: Size(width, widget.height),
            painter: _WaveformPainter(
              peaks: widget.peaks,
              duration: widget.duration,
              position: widget.position,
              loopA: widget.loopA,
              loopB: widget.loopB,
              loopEnabled: widget.loopEnabled,
              waveColor: scheme.primary.withValues(alpha: 0.6),
              loopColor: scheme.tertiary.withValues(alpha: 0.25),
              handleColor: scheme.tertiary,
              playheadColor: scheme.error,
            ),
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.peaks,
    required this.duration,
    required this.position,
    required this.loopA,
    required this.loopB,
    required this.loopEnabled,
    required this.waveColor,
    required this.loopColor,
    required this.handleColor,
    required this.playheadColor,
  });

  final List<double> peaks;
  final Duration duration;
  final Duration position;
  final Duration loopA;
  final Duration loopB;
  final bool loopEnabled;
  final Color waveColor, loopColor, handleColor, playheadColor;

  double _x(Duration t, double w) {
    final ms = duration.inMilliseconds;
    return ms == 0 ? 0 : (t.inMilliseconds / ms) * w;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;

    // Zone de boucle
    final ax = _x(loopA, size.width);
    final bx = _x(loopB, size.width);
    canvas.drawRect(
      Rect.fromLTRB(ax, 0, bx, size.height),
      Paint()..color = loopColor.withValues(alpha: loopColor.a * (loopEnabled ? 1.0 : 0.3)),
    );

    // Pics
    if (peaks.isNotEmpty) {
      final bw = size.width / peaks.length;
      final wave = Paint()..color = waveColor;
      for (var i = 0; i < peaks.length; i++) {
        final h = (peaks[i] * mid).clamp(1.0, mid);
        final x = i * bw;
        canvas.drawRect(Rect.fromLTRB(x, mid - h, x + bw * 0.8, mid + h), wave);
      }
    }

    // Poignées A et B
    final handle = Paint()
      ..color = handleColor
      ..strokeWidth = loopEnabled ? 3 : 2;
    canvas.drawLine(Offset(ax, 0), Offset(ax, size.height), handle);
    canvas.drawLine(Offset(bx, 0), Offset(bx, size.height), handle);
    canvas.drawCircle(Offset(ax, 8), 6, handle);
    canvas.drawCircle(Offset(bx, size.height - 8), 6, handle);

    // Tête de lecture
    final px = _x(position, size.width);
    canvas.drawLine(
      Offset(px, 0),
      Offset(px, size.height),
      Paint()
        ..color = playheadColor
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.position != position ||
      old.loopA != loopA ||
      old.loopB != loopB ||
      old.loopEnabled != loopEnabled ||
      old.duration != duration ||
      !identical(old.peaks, peaks);
}
