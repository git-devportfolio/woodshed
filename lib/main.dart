import 'package:flutter/material.dart';
import 'package:idb_shim/idb_browser.dart';

import 'core/io/persistent_storage.dart';
import 'core/library/idb_library_repository.dart';
import 'core/library/library_repository.dart';
import 'features/library/library_page.dart';

void main() {
  final repo = IdbLibraryRepository(idbFactoryBrowser);
  requestPersistentStorage();
  runApp(WoodshedApp(repo: repo));
}

class WoodshedApp extends StatelessWidget {
  const WoodshedApp({super.key, required this.repo});
  final LibraryRepository repo;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'woodshed',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        home: LibraryPage(repo: repo),
      );
}
