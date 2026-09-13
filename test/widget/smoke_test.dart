import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puck/src/features/puck/widgets/context_card.dart';
import 'package:puck/src/features/puck/widgets/joke_card.dart';
import 'package:puck/src/features/puck/widgets/puck_bubble.dart';
import 'package:puck/src/features/settings/settings_screen.dart';
import 'package:puck/src/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:puck/app.dart';

/// The judge's first 90 seconds, compressed: the app builds to a black
/// screen with a bubble, a tap resolves to the context card, a double-tap
/// resolves to the joke card, and settings opens. No plugins, no network.
void main() {
  testWidgets('launches to the bubble, tap and double-tap resolve',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const PuckApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // The whole product is on screen: one bubble.
    expect(find.byType(PuckBubble), findsOneWidget);

    // Tap resolves to the guaranteed card. The double-tap window is 260ms,
    // so the tap commits after that.
    await tester.tap(find.byType(PuckBubble));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byType(ContextCard), findsOneWidget);

    // Double-tap resolves to a joke card (the bag ships with the app).
    await tester.tap(find.byType(PuckBubble));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.byType(PuckBubble));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byType(JokeCard), findsOneWidget);
  });

  testWidgets('settings opens and shows the four things that matter',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'sos.release.cancels': 1,
    });
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const PuckApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('API key'), findsOneWidget);
    expect(find.text('Emergency contact'), findsOneWidget);
    expect(
      find.textContaining('It has done that 1 time.'),
      findsOneWidget,
    );
  });
}
