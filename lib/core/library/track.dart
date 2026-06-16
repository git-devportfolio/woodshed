/// Réglages de pratique d'un morceau. Extensible (recevra loopA/loopB plus tard).
class TrackSettings {
  TrackSettings({this.pitchSemitones = 0, this.speed = 1.0, this.volume = 1.0});

  double pitchSemitones;
  double speed;
  double volume;

  Map<String, dynamic> toJson() => {
        'pitchSemitones': pitchSemitones,
        'speed': speed,
        'volume': volume,
      };

  factory TrackSettings.fromJson(Map json) => TrackSettings(
        pitchSemitones: (json['pitchSemitones'] as num?)?.toDouble() ?? 0,
        speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
        volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
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

  factory Track.fromJson(Map json) => Track(
        id: json['id'] as String,
        name: json['name'] as String,
        durationMs: (json['durationMs'] as num).toInt(),
        importedAt: DateTime.parse(json['importedAt'] as String),
        settings: TrackSettings.fromJson(json['settings'] as Map),
      );
}
