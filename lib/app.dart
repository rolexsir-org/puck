import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:puck/src/core/theme.dart';
import 'package:puck/src/features/privacy/privacy_screen.dart';
import 'package:puck/src/features/puck/puck_screen.dart';
import 'package:puck/src/features/settings/settings_screen.dart';
import 'package:puck/src/l10n/puck_strings.dart';

class PuckApp extends StatelessWidget {
  const PuckApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // The app's name in the switcher comes from the same string table as
      // everything else, so a Spanish phone shows a Spanish name.
      onGenerateTitle: (BuildContext context) =>
          PuckStrings.of(context).bubbleLabel,
      debugShowCheckedModeBanner: false,
      theme: PuckTheme.dark(),

      // The delegates are the reason flutter_localizations is a dependency:
      // they localize the framework's own strings (text selection menus, the
      // Switch's announcement, "Back" semantics) and they are what makes the
      // directionality of a locale -- including RTL -- flow into the tree.
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: PuckStrings.supportedLocales,

      // Unlisted locales resolve to English, visibly: the string table falls
      // back key by key rather than showing blanks, and FINDINGS.md records
      // the list of languages that are shipped and why.
      localeResolutionCallback:
          (Locale? locale, Iterable<Locale> supported) {
        if (locale == null) return const Locale('en');
        for (final Locale candidate in supported) {
          if (candidate.languageCode == locale.languageCode) return candidate;
        }
        return const Locale('en');
      },

      // No named-route generator: three screens, all statically known.
      initialRoute: '/',
      routes: <String, WidgetBuilder>{
        '/': (BuildContext context) => const PuckHome(),
        '/settings': (BuildContext context) => const SettingsScreen(),
        '/privacy': (BuildContext context) => const PrivacyScreen(),
      },
    );
  }
}
