import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Demande au navigateur de rendre le stockage persistant (best-effort).
/// Réduit le risque d'éviction d'IndexedDB sur iOS (surtout en PWA installée).
/// Web uniquement (utilise `dart:js_interop` / `package:web`).
Future<void> requestPersistentStorage() async {
  try {
    final storage = web.window.navigator.storage;
    await storage.persist().toDart;
  } catch (_) {
    // Non supporté / refusé : on continue sans garantie.
  }
}
