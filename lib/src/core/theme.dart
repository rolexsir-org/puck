import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Puck's entire colour vocabulary: six greys and one red.
///
/// The red exists for exactly one reason -- the SOS state -- and is never
/// used decoratively. Everything else is monochrome by design.
abstract final class PuckPalette {
  /// Matte black. Not #000 -- pure black makes OLED text look like it floats.
  static const Color background = Color(0xFF08080A);

  static const Color surface = Color(0xFF141418);
  static const Color surfaceHi = Color(0xFF1C1C21);
  static const Color hairline = Color(0xFF27272E);

  static const Color textHigh = Color(0xFFF4F4F6);
  static const Color textMid = Color(0xFF9A9AA3);
  static const Color textLow = Color(0xFF5C5C66);

  static const Color danger = Color(0xFFE5484D);
}

/// Type scale. System fonts only -- shipping a font family costs 300KB+ and
/// buys nothing at this size.
abstract final class PuckType {
  static const String fontFamily = '.System';

  /// Tiny, letter-spaced, uppercase. Used for provenance labels.
  static const TextStyle label = TextStyle(
    fontFamily: fontFamily,
    fontSize: 10,
    height: 1.2,
    letterSpacing: 1.4,
    fontWeight: FontWeight.w600,
    color: PuckPalette.textLow,
  );

  /// The payload. The largest text on screen at any time.
  static const TextStyle headline = TextStyle(
    fontFamily: fontFamily,
    fontSize: 19,
    height: 1.32,
    letterSpacing: -0.25,
    fontWeight: FontWeight.w500,
    color: PuckPalette.textHigh,
  );

  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    height: 1.42,
    letterSpacing: -0.1,
    color: PuckPalette.textHigh,
  );

  static const TextStyle detail = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13.5,
    height: 1.36,
    color: PuckPalette.textMid,
  );

  /// Jokes and AI answers. Monospace signals "quoted, not UI".
  static const TextStyle mono = TextStyle(
    fontFamily: 'Menlo',
    fontFamilyFallback: <String>['SFMono-Regular', 'RobotoMono', 'monospace'],
    fontSize: 15,
    height: 1.5,
    letterSpacing: -0.15,
    color: PuckPalette.textHigh,
  );

  static const TextStyle input = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    height: 1.3,
    letterSpacing: -0.2,
    color: PuckPalette.textHigh,
  );
}

abstract final class PuckTheme {
  static ThemeData dark() {
    const base = ColorScheme.dark(
      primary: PuckPalette.textHigh,
      onPrimary: PuckPalette.background,
      surface: PuckPalette.surface,
      onSurface: PuckPalette.textHigh,
      error: PuckPalette.danger,
      onError: Colors.white,
      outline: PuckPalette.hairline,
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
      dividerColor: PuckPalette.hairline,
      appBarTheme: const AppBarTheme(
        backgroundColor: PuckPalette.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        foregroundColor: PuckPalette.textHigh,
        titleTextStyle: TextStyle(
          fontFamily: PuckType.fontFamily,
          fontSize: 15,
          letterSpacing: 0.4,
          fontWeight: FontWeight.w600,
          color: PuckPalette.textHigh,
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        hintStyle: TextStyle(color: PuckPalette.textLow),
        contentPadding: EdgeInsets.zero,
        isDense: true,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: PuckPalette.textHigh,
        selectionColor: Color(0x33F4F4F6),
        selectionHandleColor: PuckPalette.textHigh,
      ),
    );
  }

  /// Applied once at startup for true edge-to-edge on both platforms.
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
class PuckCard extends StatelessWidget {
  const PuckCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 14),
    this.borderColor = PuckPalette.hairline,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PuckPalette.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 28,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
