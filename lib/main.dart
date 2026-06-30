import 'package:flutter/material.dart';

import 'src/player/artcnn_player_page.dart';

void main() {
  runApp(const IrisesceApp());
}

class IrisesceApp extends StatelessWidget {
  const IrisesceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Irisesce',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff247c6d)),
        useMaterial3: true,
      ),
      home: const ArtCnnPlayerPage(),
    );
  }
}
