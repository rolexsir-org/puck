import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The entire approved palette. Nothing outside this list may appear in the
/// app; if a colour seems missing (amber for "acquiring GPS", for instance),
/// the nearest token above is used instead of inventing a new one.
///
/// # Contrast (WCAG 2.1 AA, verified in `test/core/contrast_test.dart`)
///
/// `textMuted` was `#666666`: **3.66:1** on black and **3.29:1** on the card.
/// It is used for 13px captions, where AA requires 4.5:1, so every quiet label
/// in the app -- provenance labels, settings notes, the footer -- sat below
/// the floor. It is now `#828282`: **5.46:1** on black, **4.91:1** on the
/// card, still visibly the quietest text in the palette. A brightness change,
/// not a redesign.
///
/// The rest were already compliant (measured, not assumed): `textSec`
/// 7.37:1 / 6.63:1, `textPrim` 21:1 / 18.88:1.
///
/// One consequence worth stating: white on `emergency` is **3.55:1** and
/// *fails* AA for 17px text, so the buttons that use the emergency fill draw
/// their label in `background` instead -- black on that red is 5.92:1. Red is
/// for the surface, not for the letters. Hover-free, disabled-free: the
/// contrast is fixed, not state-dependent.
///
abstract final class PuckPalette {
  static const Color background = Color(0xFF000000);
  static const Color card = Color(0xFF111111);
  static const Color divider = Color(0xFF1F1F1F);
  static const Color mutedBg = Color(0xFF2A2A2A);
  static const Color textMuted = Color(0xFF828282);
  static const Color textSec = Color(0xFF999999);
  static const Color textPrim = Color(0xFFFFFFFF);
  static const Color emergency = Color(0xFFFF3B30);
  static const Color success = Color(0xFF30D158);
}

/// Type scale. System fonts only -- shipping a font family costs 300KB+ and
/// buys nothing at this size.
///
/// Five sizes (13/15/17/19/24), three weights (400/500/600). Line height 1.3
/// for body, 1.15 for large numbers. Letter spacing -0.2 on large numbers,
/// 0 everywhere else.
abstract final class PuckType {
  static const String fontFamily = '.System';

  /// Secondary captions: card provenance labels, helper text.
  static const TextStyle label = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w400,
    color: PuckPalette.textMuted,
  );

  /// Body: detail lines, settings notes, SOS status.
  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    height: 1.3,
    fontWeight: FontWeight.w400,
    color: PuckPalette.textSec,
  );

  /// The payload. Card headlines, jokes, answers, inputs.
  static const TextStyle primary = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    height: 1.3,
    fontWeight: FontWeight.w500,
    color: PuckPalette.textPrim,
  );

  /// Large single-line numbers: the SOS countdown label states, sheet titles.
  static const TextStyle title = TextStyle(
    fontFamily: fontFamily,
    fontSize: 19,
    height: 1.15,
    fontWeight: FontWeight.w500,
    color: PuckPalette.textPrim,
  );

  /// Reserved for the one moment Puck is loud: the SOS ring number.
  static const TextStyle countdown = TextStyle(
    fontFamily: fontFamily,
    fontSize: 96,
    height: 1.15,
    letterSpacing: -0.2,
    fontWeight: FontWeight.w300,
    color: PuckPalette.textPrim,
  );
}

abstract final class PuckTheme {
  static ThemeData dark() {
    const base = ColorScheme.dark(
      primary: PuckPalette.textPrim,
      onPrimary: PuckPalette.background,
      surface: PuckPalette.background,
      onSurface: PuckPalette.textPrim,
      error: PuckPalette.emergency,
      onError: PuckPalette.textPrim,
      outline: PuckPalette.divider,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: base,
      scaffoldBackgroundColor: PuckPalette.background,
      canvasColor: PuckPalette.background,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      fontFamily: PuckType.fontFamily,
      dividerColor: PuckPalette.divider,
      appBarTheme: const AppBarTheme(
        backgroundColor: PuckPalette.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        foregroundColor: PuckPalette.textPrim,
        titleTextStyle: TextStyle(
          fontFamily: PuckType.fontFamily,
          fontSize: 17,
          letterSpacing: 0,
          fontWeight: FontWeight.w500,
          color: PuckPalette.textPrim,
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        hintStyle: TextStyle(color: PuckPalette.textMuted),
        contentPadding: EdgeInsets.zero,
        isDense: true,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: PuckPalette.textPrim,
        selectionColor: Color(0x33FFFFFF),
        selectionHandleColor: PuckPalette.textPrim,
      ),
    );
  }

  /// Applied once at startup for true edge-to-edge on both platforms.
  /// Status bar icons stay light on black in every state the app can be in.
  static void applySystemChrome() {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}

/// The card chrome shared by every floating panel.
///
/// #111111, not pure black -- the card has to read as an object floating
/// above the screen it sits on.
class PuckCard extends StatelessWidget {
  const PuckCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PuckPalette.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: child,
      ),
    );
  }
}
