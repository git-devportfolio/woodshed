import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Partage le fichier via la feuille de partage (Drive/AirDrop…) si disponible,
/// sinon le télécharge. À appeler dans un geste utilisateur (iOS).
Future<void> shareOrDownloadFile(Uint8List bytes, String name, String mime) async {
  final parts = [bytes.toJS].toJS;
  final file = web.File(parts, name, web.FilePropertyBag(type: mime));
  final data = web.ShareData(files: [file].toJS);
  final nav = web.window.navigator;

  // Sonde de disponibilité protégée : sur un navigateur sans Web Share API
  // (ex. Firefox desktop), `canShare` n'existe pas et lève → on bascule alors
  // sur le téléchargement.
  var canShare = false;
  try {
    canShare = nav.canShare(data);
  } catch (_) {
    canShare = false;
  }

  if (canShare) {
    try {
      await nav.share(data).toDart;
      return; // partage réussi
    } catch (e) {
      // Annulation par l'utilisateur (AbortError) : ne rien faire.
      // Autre échec réel : repli sur le téléchargement.
      if (_isAbortError(e)) return;
    }
  }
  downloadFile(bytes, name, mime);
}

/// Vrai si l'erreur JS est une annulation utilisateur (`AbortError`).
bool _isAbortError(Object e) {
  if (!e.isA<JSObject>()) return false;
  final obj = e as JSObject;
  final name = obj.getProperty<JSString?>('name'.toJS);
  return name?.toDart == 'AbortError';
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
