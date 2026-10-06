import 'dart:ui' show Locale;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puck/app.dart';
import 'package:puck/src/data/repositories/settings_repository.dart';
import 'package:puck/src/features/settings/settings_screen.dart';
import 'package:puck/src/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The settings screen, driven the way a person drives it.
//
// Two of this project's promises live only here: that a setting change reaches
// storage (so the next launch honours it), and that the screens are translated
// for a phone that is not in English. Both are one widget test away, and both
// are the kind of thing that silently stops being true.
//
// **Written, not run** -- no Flutter SDK in the authoring environment. See
// FINDINGS.md §1 and §5.

void main() {
  Future<SharedPreferences> prefsWith(Map<String, Object> initial) async {
    SharedPreferences.setMockInitialValues(initial);
    return SharedPreferences.getInstance();
  }

  Future<SettingsRepository> openSettings(
    WidgetTester tester, {
    Map<String, Object> initial = const <String, Object>{},
  }) async {
    final SharedPreferences prefs = await prefsWith(initial);
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
    return SettingsRepository(prefs);
  }

  testWidgets('the hold length is 3s until someone says otherwise',
      (WidgetTester tester) async {
    await openSettings(tester);

    // The default is the design constant and is not negotiable: the pocket
    // argument rests on it. The control below it is an accommodation, not a
    // preference, and it must never have moved the default.
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('sos.hold.seconds'), isNull);

    await tester.tap(find.text('1 second'));
    await tester.pumpAndSettle();
    expect(prefs.getInt('sos.hold.seconds'), 1);

    await tester.tap(find.text('3 seconds'));
    await tester.pumpAndSettle();
    expect(prefs.getInt('sos.hold.seconds'), 3);
  });

  testWidgets('the cloud switch is the one switch, and it sticks',
      (WidgetTester tester) async {
    await openSettings(tester);
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    // On by default: an app that has to be configured before it is useful is
    // the thing this whole change exists to remove. What matters is that it
    // can be turned off, and that turning it off is recorded.
    expect(prefs.getBool('privacy.cloud.enabled'), isNull);

    final Finder toggle = find.byType(Switch);
    expect(
      toggle,
      findsOneWidget,
      reason: 'the cloud switch is the only switch on this screen; a second '
          'one would be a menu',
    );

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(prefs.getBool('privacy.cloud.enabled'), isFalse);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(prefs.getBool('privacy.cloud.enabled'), isTrue);
  });

  testWidgets('erasing local data asks first, then erases everything',
      (WidgetTester tester) async {
    await openSettings(
      tester,
      initial: <String, Object>{
        'sos.contact.phone': '+15550100',
        'sos.hold.seconds': 1,
        'sos.release.cancels': 4,
        'privacy.cloud.enabled': false,
        'privacy.device.id': 'aaaa-bbbb',
        'fun.joke.index': 12,
      },
    );
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    // First tap asks; it does not erase. A destructive action behind one tap
    // is a bug even when the button is red.
    await tester.tap(find.text('Erase everything Puck stored'));
    await tester.pumpAndSettle();
    expect(find.text('Erase? This cannot be undone.'), findsOneWidget);
    expect(prefs.getString('sos.contact.phone'), '+15550100');

    // "Keep it" backs out and changes nothing.
    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();
    expect(find.text('Erase? This cannot be undone.'), findsNothing);
    expect(prefs.getString('sos.contact.phone'), '+15550100');

    // Second attempt, confirmed.
    await tester.tap(find.text('Erase everything Puck stored'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Erase local data'));
    await tester.pumpAndSettle();

    for (final String key in <String>[
      'sos.contact.phone',
      'sos.hold.seconds',
      'sos.release.cancels',
      'privacy.cloud.enabled',
      'privacy.device.id',
      'fun.joke.index',
    ]) {
      expect(prefs.get(key), isNull, reason: '$key survived the erase');
    }
  });

  testWidgets('a Spanish phone gets a Spanish settings screen',
      (WidgetTester tester) async {
    // The locale comes from the platform, through the app's own
    // `localeResolutionCallback`, which is the path a real phone takes.
    tester.platformDispatcher.localeTestValue = const Locale('es');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);

    final SharedPreferences prefs = await prefsWith(<String, Object>{});
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const PuckApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Ajustes'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    // Every heading on the screen is Spanish, and no English heading survives
    // next to one. The English strings are the canary: a missing translation
    // shows up as a mixed-language screen, which is what the ARB parity test
    // cannot catch and this one can.
    for (final String spanish in <String>[
      'Ajustes',
      'Qué sale de tu teléfono',
      'Contacto de emergencia',
      'Mantener pulsado para una emergencia',
      'Borrar todo lo que Puck guardó',
    ]) {
      expect(find.text(spanish), findsOneWidget, reason: spanish);
    }
    for (final String english in <String>[
      'Settings',
      'What leaves your phone',
      'Emergency contact',
      'Erase everything Puck stored',
    ]) {
      expect(find.text(english), findsNothing, reason: english);
    }
  });

  testWidgets('the settings screen labels itself for a screen reader',
      (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    addTearDown(handle.dispose);

    await openSettings(tester);

    // A text field with no label is announced as "edit box" and nothing else,
    // which is why both fields carry an explicit label rather than relying on
    // the heading above them being read out first.
    for (final String label in <String>[
      'Emergency contact',
      'Use my own key (optional)',
    ]) {
      expect(
        find.bySemanticsLabel(label),
        findsWidgets,
        reason: 'nothing in the tree is labelled "$label"',
      );
    }

    // And the back control is a button with a name, not a bare icon.
    expect(find.bySemanticsLabel('Back'), findsWidgets);
  });
}
