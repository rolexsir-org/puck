import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:puck/app.dart';
import 'package:puck/src/core/theme.dart';
import 'package:puck/src/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Puck is a single portrait surface; locking it avoids a rebuild storm on
  // rotation and keeps the bubble's snapped position stable.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  PuckTheme.applySystemChrome();

  // One async read at startup, injected into the tree. Everything downstream
  // is synchronous.
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const PuckApp(),
    ),
  );
}
