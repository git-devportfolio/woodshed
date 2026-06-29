/// Réglages de pratique d'un morceau.
class TrackSettings {
  TrackSettings({
    this.pitchSemitones = 0,
    this.speed = 1.0,
    this.volume = 1.0,
    this.loopA,
    this.loopB,
    this.loopEnabled = false,
  });

  double pitchSemitones;
  double speed;
  double volume;
  double? loopA; // secondes, null = non défini (→ 0)
  double? loopB; // secondes, null = non défini (→ durée)
  bool loopEnabled;

  Map<String, dynamic> toJson() => {
        'pitchSemitones': pitchSemitones,
        'speed': speed,
        'volume': volume,
        'loopA': loopA,
        'loopB': loopB,
        'loopEnabled': loopEnabled,
      };

  factory TrackSettings.fromJson(Map json) => TrackSettings(
        pitchSemitones: (json['pitchSemitones'] as num?)?.toDouble() ?? 0,
        speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
        volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
        loopA: (json['loopA'] as num?)?.toDouble(),
        loopB: (json['loopB'] as num?)?.toDouble(),
        loopEnabled: (json['loopEnabled'] as bool?) ?? false,
      );
}

/// Un morceau de la bibliothèque (métadonnées + réglages ; les octets audio
/// sont stockés à part, indexés par [id]).
class Track {
  Track({
    required this.id,
    required this.name,
    required this.durationMs,
    required this.importedAt,
    required this.settings,
  });

  final String id;
  final String name;
  final int durationMs;
  final DateTime importedAt;
  TrackSettings settings;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'durationMs': durationMs,
        'importedAt': importedAt.toIso8601String(),
        'settings': settings.toJson(),
      };

  factory Track.fromJson(Map json) {
    final id = json['id'];
    final name = json['name'];
    final durationMs = json['durationMs'];
    final importedAt = json['importedAt'];
    if (id is! String ||
        name is! String ||
        durationMs is! num ||
        importedAt is! String) {
      throw FormatException('Track JSON invalide : $json');
    }
    return Track(
      id: id,
      name: name,
      durationMs: durationMs.toInt(),
      importedAt: DateTime.parse(importedAt),
      settings: TrackSettings.fromJson((json['settings'] as Map?) ?? const {}),
    );
  }
}
