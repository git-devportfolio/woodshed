import 'package:flutter/material.dart';

import 'section_label.dart';

/// Sélecteur de vitesse : une seule ligne, quatre cibles larges (usage voiture).
///
/// La ligne unique est garantie par construction — un `Row` d'`Expanded` ne peut
/// pas passer à la ligne, contrairement à un `Wrap`.
class SpeedSelector extends StatelessWidget {
  const SpeedSelector({super.key, required this.speed, required this.onChanged});

  static const speeds = <double>[0.75, 0.85, 0.95, 1.0];
  static const _height = 56.0;
  static const _gap = 8.0;
  static const _radius = 16.0;

  final double speed;
  final ValueChanged<double> onChanged;

  /// `1.0` s'affiche `1x` ; les autres gardent leurs décimales (`0.75x`).
  static String label(double rate) => rate == 1.0 ? '1x' : '${rate}x';

  /// Posé sur le `Text` (et non dans `styleFrom`) pour hériter la famille de
  /// police du thème ambiant : un `TextStyle` de `Text` a `inherit: true` et
  /// fusionne avec le `DefaultTextStyle` du bouton, alors qu'un `textStyle:`
  /// dans `ButtonStyleButton.styleFrom` remplace intégralement celui du thème.
  static const _labelStyle =
      TextStyle(fontSize: 16, fontWeight: FontWeight.w600);

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(_height),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Vitesse'),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final rate in speeds) ...[
              if (rate != speeds.first) const SizedBox(width: _gap),
              Expanded(
                child: rate == speed
                    ? FilledButton(
                        key: ValueKey('speed-$rate'),
                        style: style,
                        onPressed: () => onChanged(rate),
                        child: Text(label(rate), style: _labelStyle),
                      )
                    : FilledButton.tonal(
                        key: ValueKey('speed-$rate'),
                        style: style,
                        onPressed: () => onChanged(rate),
                        child: Text(label(rate), style: _labelStyle),
                      ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
