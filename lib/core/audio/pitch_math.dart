import 'dart:math' as math;

/// Convertit un nombre de demi-tons en ratio de fréquence : 2^(n/12).
double semitonesToRatio(double semitones) =>
    math.pow(2, semitones / 12).toDouble();

/// Borne le pitch à l'intervalle autorisé par le spike : [-6, +6] demi-tons.
double clampSemitones(double semitones) => semitones.clamp(-6.0, 6.0);
