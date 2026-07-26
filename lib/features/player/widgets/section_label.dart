import 'package:flutter/material.dart';

/// Libellé d'un bloc de réglage, placé au-dessus de ses contrôles.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  static const fontSize = 16.0;

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
      );
}
