import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Décode les octets audio dans un [OfflineAudioContext] (insensible à la
/// suspension iOS) et renvoie leur durée. Lève si le format n'est pas décodable.
Future<Duration> probeAudioDuration(Uint8List bytes) async {
  final buffer = Uint8List.fromList(bytes).buffer.toJS;
  final offline = web.OfflineAudioContext(2.toJS, 1, 44100);
  final audioBuffer = await offline.decodeAudioData(buffer).toDart;
  return Duration(milliseconds: (audioBuffer.duration * 1000).round());
}
