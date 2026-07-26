import 'package:flutter/material.dart';

import 'section_label.dart';

/// Stepper de transposition : label au-dessus, `[−] valeur [+]` centré dessous.
///
/// Le label est au-dessus (et non sur la même ligne) parce qu'avec des boutons
/// de 64 px la ligne complète dépasserait la largeur d'un petit écran.
class PitchStepper extends StatelessWidget {
  const PitchStepper({super.key, required this.pitch, required this.onChanged});

  static const min = -6.0;
  static const max = 6.0;
  static const _buttonSize = 64.0;
  static const _iconSize = 32.0;
  static const _valueWidth = 72.0;
  static const _valueFontSize = 36.0;

  final double pitch;
  final ValueChanged<double> onChanged;

  /// `0`, `+3`, `−2` — le moins est le signe typographique U+2212.
  static String format(double semitones) {
    final n = semitones.round();
    if (n == 0) return '0';
    return n > 0 ? '+$n' : '−${n.abs()}';
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Pitch (demi-tons)'),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                key: const ValueKey('pitch-minus'),
                tooltip: '−1 demi-ton',
                iconSize: _iconSize,
                style: IconButton.styleFrom(
                  minimumSize: const Size(_buttonSize, _buttonSize),
                ),
                // `.toDouble()` est obligatoire : `num.clamp` renvoie un `num`,
                // pas un `double` (comme dans le code d'origine).
                onPressed: pitch > min
                    ? () => onChanged((pitch - 1).clamp(min, max).toDouble())
                    : null,
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                key: const ValueKey('pitch-value'),
                width: _valueWidth,
                child: Text(
                  format(pitch),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: _valueFontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton.filledTonal(
                key: const ValueKey('pitch-plus'),
                tooltip: '+1 demi-ton',
                iconSize: _iconSize,
                style: IconButton.styleFrom(
                  minimumSize: const Size(_buttonSize, _buttonSize),
                ),
                onPressed: pitch < max
                    ? () => onChanged((pitch + 1).clamp(min, max).toDouble())
                    : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ],
      );
}
