import 'package:flutter/material.dart';
import 'package:puck/src/core/theme.dart';
import 'package:puck/src/features/puck/puck_screen.dart';
import 'package:puck/src/features/settings/settings_screen.dart';

class PuckApp extends StatelessWidget {
  const PuckApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Puck',
      debugShowCheckedModeBanner: false,
      theme: PuckTheme.dark(),
      // No named-route generator: two screens, both statically known.
      initialRoute: '/',
      routes: <String, WidgetBuilder>{
        '/': (BuildContext context) => const PuckHome(),
        '/settings': (BuildContext context) => const SettingsScreen(),
      },
    );
  }
}
