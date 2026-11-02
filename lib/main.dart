import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:puck/app.dart';
import 'package:puck/src/core/theme.dart';
import 'package:puck/src/providers.dart';
import 'package:puck/src/voice/model_store.dart';
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

  // Locale data for `intl`'s DateFormat: without this, a 24-hour clock or a
  // localized month name throws on the first format call. One table load at
  // startup, no network, no cost after.
  await initializeDateFormatting();

  // One async read at startup, injected into the tree. Everything downstream
  // is synchronous.
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  // The voice-model directory. Resolved here rather than lazily because the
  // settings screen reads it on first paint and a FutureBuilder in front of a
  // download button is a worse experience than one extra millisecond at
  // launch. Creating the directory is idempotent and touches no model.
  final VoiceModelStore voiceModels = await VoiceModelStore.open();

  runApp(
    ProviderScope(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        voiceModelStoreProvider.overrideWithValue(voiceModels),
      ],
      child: const PuckApp(),
    ),
  );
}
