import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Un fichier audio choisi par l'utilisateur.
class PickedAudio {
  PickedAudio(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// Ouvre un sélecteur de fichier natif (`<input type="file">`) et renvoie le
/// fichier choisi, ou `null` si rien n'a été sélectionné.
///
/// DOIT être appelé dans un geste utilisateur (le `click()` est synchrone).
///
/// On évite `package:file_picker` sur web : sa détection d'annulation (événements
/// `focus`/`cancel`) renvoyait `null` à tort sur iOS — la 1ʳᵉ sélection était
/// ignorée et il fallait rouvrir le sélecteur. Ici on n'écoute QUE l'événement
/// `change` réel, donc plus de fausse annulation.
Future<PickedAudio?> pickAudioFile() {
  final completer = Completer<PickedAudio?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = false
    ..style.display = 'none';
  // Attaché au DOM avant click() : plus fiable sur iOS Safari.
  web.document.body!.appendChild(input);

  void finish(PickedAudio? value) {
    input.remove();
    if (!completer.isCompleted) completer.complete(value);
  }

  input.addEventListener(
    'change',
    ((web.Event _) {
      final files = input.files;
      if (files == null || files.length == 0) {
        finish(null);
        return;
      }
      final file = files.item(0)!;
      final reader = web.FileReader();
      reader.addEventListener(
        'loadend',
        ((web.Event _) {
          final buffer = (reader.result as JSArrayBuffer?)?.toDart;
          finish(buffer == null ? null : PickedAudio(file.name, buffer.asUint8List()));
        }).toJS,
      );
      reader.addEventListener('error', ((web.Event _) => finish(null)).toJS);
      reader.readAsArrayBuffer(file);
    }).toJS,
  );

  input.click();
  return completer.future;
}
