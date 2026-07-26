import 'package:flutter/material.dart';

/// Thème unique de l'application : police Inter embarquée + palette violette.
///
/// Le `TextTheme` n'est pas redéfini : les tailles particulières restent locales
/// aux widgets qui les portent, pour ne pas affecter les écrans hors périmètre.
ThemeData buildWoodshedTheme() => ThemeData(
      fontFamily: 'Inter',
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
    );
