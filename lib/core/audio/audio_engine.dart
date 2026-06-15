import 'dart:typed_data';
import 'engine_kind.dart';

/// Moteur audio abstrait. Isole l'app du moteur concret (Web Audio, Android…).
abstract class AudioEngine {
  /// Charge des octets audio (fichier local décodé).
  Future<void> load(Uint8List bytes);

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);

  /// Vitesse sans altérer la tonalité (0.5 / 0.75 / 1.0).
  Future<void> setSpeed(double rate);

  /// Transposition en demi-tons (-6 .. +6).
  Future<void> setPitch(double semitones);

  /// Active/désactive la boucle sur le morceau entier.
  Future<void> setLoop(bool loop);

  /// Change de backend à chaud (conserve position/pitch/vitesse côté façade).
  Future<void> setEngine(EngineKind kind);

  /// Position courante (pour le curseur UI).
  Stream<Duration> get position;

  /// Durée totale du morceau chargé.
  Duration get duration;

  /// Nombre de glitches (buffer underruns) remontés par le backend, si dispo.
  int get glitchCount;

  Future<void> dispose();

  // --- Hors périmètre du spike (déclarés pour l'archi, non implémentés sur web) ---
  Future<void> setVolume(double volume);
  Future<void> setLoopRange(Duration a, Duration b);
}
