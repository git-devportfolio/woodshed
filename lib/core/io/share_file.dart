import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Partage le fichier via la feuille de partage (Drive/AirDrop…) si disponible,
/// sinon le télécharge. À appeler dans un geste utilisateur (iOS).
Future<void> shareOrDownloadFile(Uint8List bytes, String name, String mime) async {
  final parts = [bytes.toJS].toJS;
  final file = web.File(parts, name, web.FilePropertyBag(type: mime));
  final data = web.ShareData(files: [file].toJS);
  final nav = web.window.navigator;
  if (nav.canShare(data)) {
    try {
      await nav.share(data).toDart;
    } catch (_) {
      // partage annulé par l'utilisateur : ne rien faire
    }
    return;
  }
  downloadFile(bytes, name, mime);
}

/// Déclenche un téléchargement du fichier (repli desktop / bouton explicite).
void downloadFile(Uint8List bytes, String name, String mime) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = name
    ..style.display = 'none';
  web.document.body!.appendChild(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
}
