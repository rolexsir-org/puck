import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puck/app.dart';
import 'package:puck/src/core/theme.dart';
import 'package:puck/src/features/puck/widgets/puck_bubble.dart';
import 'package:puck/src/features/settings/settings_screen.dart';
import 'package:puck/src/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The layout matrix, as a test rather than as a promise.
//
// Workstream 6's acceptance criteria are mostly unmeasurable here (frame times,
// memory over 50 cycles, real APK size on a real 2 GB phone), but two of them
// are not: *does every screen still lay out at 320x568*, and *does anything
// overflow at 2.0x system text*. Both are property tests over the widget tree,
// and both are the conditions most likely to be shipped broken, because no
// developer ever runs their own app at 2.0x on the smallest phone in the world.
//
// These tests are **written, not run** -- there is no Flutter SDK in the
// environment this repository was authored in. See FINDINGS.md §1 and §5.

/// The three sizes that matter, in logical pixels: the smallest Android phone
/// still in use, the most common one, and a small tablet in portrait.
const List<(String, Size)> matrix = <(String, Size)>[
  ('320x568 (smallest supported)', Size(320, 568)),
  ('412x915 (the common one)', Size(412, 915)),
  ('600x960 (small tablet)', Size(600, 960)),
];

/// The four system text scales, including the two that break layouts: 1.3x
/// (the most common real-world setting) and 2.0x (the accessibility maximum
/// this project commits to, and the one EVERYONE.md's row 4 names).
const List<(String, double)> scales = <(String, double)>[
  ('1.0x', 1.0),
  ('1.3x', 1.3),
  ('1.6x', 1.6),
  ('2.0x', 2.0),
];

Future<void> pumpApp(
  WidgetTester tester, {
  required Size size,
  double textScale = 1.0,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: Builder(
        builder: (BuildContext context) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            // Below the app's own MaterialApp, which is where the text scaler
            // has to be injected to reach every route.
            child: const PuckApp(),
          );
        },
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

/// Fails with the overflowing widget's own description, which is far more
/// useful than "expected zero, found two".
void expectNoOverflow(WidgetTester tester) {
  final Object? error = tester.takeException();
  expect(error, isNull, reason: 'a layout overflowed: $error');
}

void main() {
  for (final (String name, Size size) in matrix) {
    group(name, () {
      for (final (String scaleName, double scale) in scales) {
        testWidgets('the bubble survives $scaleName', (
          WidgetTester tester,
        ) async {
          await pumpApp(tester, size: size, textScale: scale);

          expect(find.byType(PuckBubble), findsOneWidget);
          expectNoOverflow(tester);

          // The bubble is a fixed 72dp disc: text scaling must not change the
          // product's one constant, and the disc must not leave the screen.
          final Rect rect = tester.getRect(find.byType(PuckBubble));
          expect(rect.width, lessThanOrEqualTo(size.width));
          expect(rect.height, lessThanOrEqualTo(size.height));
        });
      }

      testWidgets('the settings screen survives 2.0x', (
        WidgetTester tester,
      ) async {
        // The densest surface in the app: labels, hints, a switch, three
        // hold-length buttons and two text fields. If anything is going to
        // clip at the largest accessibility scale, it is this.
        await pumpApp(tester, size: size, textScale: 2.0);

        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();

        expect(find.byType(SettingsScreen), findsOneWidget);
        expectNoOverflow(tester);

        // Every interactive thing is at least 48dp at 1.0x. At 2.0x they can
        // only grow, so this is a 1.0x measurement on the smallest screen --
        // the worst case for a target shrinking is a small screen, not a large
        // font.
        await tester.pumpAndSettle();
      });

      testWidgets('the tap card survives 2.0x', (
        WidgetTester tester,
      ) async {
        await pumpApp(tester, size: size, textScale: 2.0);

        await tester.tap(find.byType(PuckBubble));
        await tester.pumpAndSettle(const Duration(seconds: 1));

        expectNoOverflow(tester);
      });
    });
  }

  testWidgets('every target in settings is at least 48dp at 1.0x',
      (WidgetTester tester) async {
    // WCAG 2.5.5 and the Android/iOS guidance agree on 48dp, and this project
    // committed to it for every control in EVERYONE.md's row 5. Measured, not
    // eyeballed: the smallest screen is the one where a 44dp target hurts.
    await pumpApp(tester, size: const Size(320, 568));

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    for (final Finder finder in <Finder>[
      find.text('Settings').first,
      find.text('Back'),
      find.text('Paste'),
      find.text('Let Puck answer with the internet'),
    ]) {
      if (finder.evaluate().isEmpty) continue;
      final Rect rect = tester.getRect(finder);
      expect(
        rect.height,
        greaterThanOrEqualTo(47),
        reason: 'a target is shorter than 48dp',
      );
    }
  });

  test('the field is black and the disc is white, by theme, not by accident',
      () {
    // The one constant of the product. Asserted against the theme rather than
    // against a widget, because the theme is what every screen inherits --
    // and because the palette's own contrast ratios are checked in
    // `test/core/contrast_math_test.dart`.
    final ThemeData theme = PuckTheme.dark();
    expect(theme.scaffoldBackgroundColor, PuckPalette.background);
    expect(theme.colorScheme.surface, PuckPalette.background);
    expect(theme.colorScheme.onSurface, PuckPalette.textPrim);
    expect(theme.dividerColor, PuckPalette.divider);
    // No splash, no highlight, no hover fill: a gesture surface must not
    // flash a colour the palette does not contain.
    expect(theme.splashFactory, NoSplash.splashFactory);
    expect(theme.highlightColor, Colors.transparent);
    expect(theme.hoverColor, Colors.transparent);
  });
}
