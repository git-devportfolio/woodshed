import 'dart:typed_data';
import 'track.dart';

/// Accès persistant à la bibliothèque de morceaux.
abstract class LibraryRepository {
  Future<List<Track>> listTracks();
  Future<Track> addTrack(String name, Uint8List bytes, Duration duration);
  Future<Uint8List> loadAudio(String id);
  /// Met à jour les réglages du morceau [id]. No-op si l'id n'existe pas.
  Future<void> updateSettings(String id, TrackSettings settings);
  Future<void> deleteTrack(String id);
}
