import 'package:flutter/material.dart';
import 'features/spike/spike_page.dart';

void main() => runApp(const WoodshedApp());

class WoodshedApp extends StatelessWidget {
  const WoodshedApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'woodshed — spike',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        home: const SpikePage(),
      );
}
