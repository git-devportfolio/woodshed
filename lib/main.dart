import 'package:flutter/material.dart';
import 'package:idb_shim/idb_browser.dart';

import 'core/audio/web_audio_engine.dart';
import 'core/io/persistent_storage.dart';
import 'core/library/idb_library_repository.dart';
import 'core/library/library_repository.dart';
import 'core/theme/app_theme.dart';
import 'features/library/library_page.dart';

void main() {
  final repo = IdbLibraryRepository(idbFactoryBrowser);
  requestPersistentStorage();
  final engine = WebAudioEngine();
  engine.init(); // fire-and-forget : initialise le contexte audio + worklet en fond
  runApp(WoodshedApp(repo: repo, engine: engine));
}

class WoodshedApp extends StatelessWidget {
  const WoodshedApp({super.key, required this.repo, required this.engine});
  final LibraryRepository repo;
  final WebAudioEngine engine;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'woodshed',
        theme: buildWoodshedTheme(),
        home: LibraryPage(repo: repo, engine: engine),
      );
}
