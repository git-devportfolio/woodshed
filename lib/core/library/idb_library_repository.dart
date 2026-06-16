import 'dart:typed_data';

import 'package:idb_shim/idb.dart';
import 'package:uuid/uuid.dart';

import 'library_repository.dart';
import 'track.dart';

/// Implémentation [LibraryRepository] sur IndexedDB via idb_shim.
/// Deux object stores : `tracks` (métadonnées+réglages, clé = id) et `audio`
/// (octets bruts, clé = id passée explicitement).
class IdbLibraryRepository implements LibraryRepository {
  IdbLibraryRepository(this._factory);

  final IdbFactory _factory;
  Database? _db;

  static const _dbName = 'woodshed';
  static const _tracksStore = 'tracks';
  static const _audioStore = 'audio';
  static const _uuid = Uuid();

  Future<Database> _open() async {
    // Pas de garde contre les appels concurrents : acceptable ici, l'app n'ouvre
    // jamais deux opérations DB simultanées au démarrage.
    return _db ??= await _factory.open(
      _dbName,
      version: 1,
      onUpgradeNeeded: (VersionChangeEvent e) {
        final db = e.database;
        if (!db.objectStoreNames.contains(_tracksStore)) {
          db.createObjectStore(_tracksStore, keyPath: 'id');
        }
        if (!db.objectStoreNames.contains(_audioStore)) {
          db.createObjectStore(_audioStore);
        }
      },
    );
  }

  @override
  Future<Track> addTrack(
      String name, Uint8List bytes, Duration duration) async {
    final db = await _open();
    final track = Track(
      id: _uuid.v4(),
      name: name,
      durationMs: duration.inMilliseconds,
      importedAt: DateTime.now(),
      settings: TrackSettings(),
    );
    final txn =
        db.transactionList([_tracksStore, _audioStore], idbModeReadWrite);
    await txn.objectStore(_tracksStore).put(track.toJson());
    await txn.objectStore(_audioStore).put(bytes, track.id);
    await txn.completed;
    return track;
  }

  @override
  Future<List<Track>> listTracks() async {
    final db = await _open();
    final txn = db.transaction(_tracksStore, idbModeReadOnly);
    final rows = await txn.objectStore(_tracksStore).getAll();
    await txn.completed;
    return rows.map((e) => Track.fromJson(e as Map)).toList()
      ..sort((a, b) => b.importedAt.compareTo(a.importedAt));
  }

  @override
  Future<Uint8List> loadAudio(String id) async {
    final db = await _open();
    final txn = db.transaction(_audioStore, idbModeReadOnly);
    final value = await txn.objectStore(_audioStore).getObject(id);
    await txn.completed;
    if (value == null) {
      throw StateError('Audio introuvable pour le morceau $id');
    }
    return value is Uint8List
        ? value
        : Uint8List.fromList((value as List).cast<int>());
  }

  /// No-op si le morceau [id] n'existe pas (ex. supprimé pendant un debounce).
  @override
  Future<void> updateSettings(String id, TrackSettings settings) async {
    final db = await _open();
    final txn = db.transaction(_tracksStore, idbModeReadWrite);
    final store = txn.objectStore(_tracksStore);
    final existing = await store.getObject(id);
    if (existing != null) {
      final track = Track.fromJson(existing as Map);
      track.settings = settings;
      await store.put(track.toJson());
    }
    await txn.completed;
  }

  @override
  Future<void> deleteTrack(String id) async {
    final db = await _open();
    final txn =
        db.transactionList([_tracksStore, _audioStore], idbModeReadWrite);
    await txn.objectStore(_tracksStore).delete(id);
    await txn.objectStore(_audioStore).delete(id);
    await txn.completed;
  }
}
