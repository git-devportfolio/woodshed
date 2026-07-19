import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed/core/audio/export_naming.dart';

void main() {
  group('exportFileName', () {
    test('pitch négatif + vitesse', () {
      expect(exportFileName('Mon solo.mp3', -2, 0.85), 'Mon solo_-2st_0.85x.mp3');
    });
    test('pitch 0 et vitesse 1.0 -> 0st et 1x', () {
      expect(exportFileName('Track', 0, 1.0), 'Track_0st_1x.mp3');
    });
    test('pitch positif + assainissement des caractères + extension retirée', () {
      expect(exportFileName('a/b:c.wav', 3, 0.5), 'a_b_c_+3st_0.5x.mp3');
    });
    test('nom vide -> audio', () {
      expect(exportFileName('', 0, 1.0), 'audio_0st_1x.mp3');
    });
  });

  group('exportOutputSeconds', () {
    test('morceau entier ralenti double la durée', () {
      expect(exportOutputSeconds(fromSec: 0, toSec: 240, speed: 0.5), 480);
    });
    test('segment à 0.75x', () {
      expect(exportOutputSeconds(fromSec: 10, toSec: 40, speed: 0.75), closeTo(40, 1e-9));
    });
    test('vitesse 1.0 conserve la durée', () {
      expect(exportOutputSeconds(fromSec: 0, toSec: 100, speed: 1.0), 100);
    });
  });
}
