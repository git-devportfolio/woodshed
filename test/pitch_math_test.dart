import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed/core/audio/pitch_math.dart';

void main() {
  group('semitonesToRatio', () {
    test('0 demi-ton => ratio 1.0', () {
      expect(semitonesToRatio(0), closeTo(1.0, 1e-9));
    });
    test('+12 demi-tons => ratio 2.0 (une octave plus haut)', () {
      expect(semitonesToRatio(12), closeTo(2.0, 1e-9));
    });
    test('-12 demi-tons => ratio 0.5 (une octave plus bas)', () {
      expect(semitonesToRatio(-12), closeTo(0.5, 1e-9));
    });
    test('+6 demi-tons => ~1.41421', () {
      expect(semitonesToRatio(6), closeTo(1.41421356, 1e-6));
    });
  });

  group('clampSemitones', () {
    test('borne haute à +6', () => expect(clampSemitones(10), 6.0));
    test('borne basse à -6', () => expect(clampSemitones(-10), -6.0));
    test('laisse passer une valeur interne', () => expect(clampSemitones(3), 3.0));
  });
}
