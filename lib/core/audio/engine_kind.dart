/// Backends audio disponibles côté web, dans l'ordre d'intégration du spike.
enum EngineKind {
  /// Lecture brute (AudioBufferSourceNode), sans transposition. Valide la plomberie.
  plain,

  /// SoundTouch via AudioWorklet.
  soundTouch,

  /// Rubber Band via AudioWorklet (plafonné, cf. spec §7).
  rubberBand,
}

extension EngineKindId on EngineKind {
  /// Identifiant passé à la façade JS.
  String get jsId => switch (this) {
        EngineKind.plain => 'plain',
        EngineKind.soundTouch => 'soundtouch',
        EngineKind.rubberBand => 'rubberband',
      };
}
