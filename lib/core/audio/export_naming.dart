/// Nom du fichier d'export : `"<morceau>_<pitch>_<vitesse>x.mp3"`.
/// Ex. `exportFileName('Mon solo.mp3', -2, 0.85)` => `'Mon solo_-2st_0.85x.mp3'`.
String exportFileName(String trackName, double pitchSemitones, double speed) {
  final base = _sanitize(_stripExtension(trackName));
  final p = pitchSemitones.round();
  final pitchLabel = p == 0 ? '0st' : '${p > 0 ? '+' : ''}${p}st';
  return '${base}_${pitchLabel}_${_trimNum(speed)}x.mp3';
}

/// Durée de sortie en secondes : (toSec - fromSec) / vitesse.
double exportOutputSeconds({
  required double fromSec,
  required double toSec,
  required double speed,
}) {
  final span = toSec - fromSec;
  return speed <= 0 ? span : span / speed;
}

String _stripExtension(String name) {
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

String _sanitize(String s) {
  final cleaned = s.replaceAll(RegExp(r'[^a-zA-Z0-9\-_ ]'), '_').trim();
  return cleaned.isEmpty ? 'audio' : cleaned;
}

String _trimNum(double v) {
  var s = v.toString();
  if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
  return s;
}
