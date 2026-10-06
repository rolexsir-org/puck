import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puck/src/core/theme.dart';

/// Contrast is a property of the product, so it is a test, not a habit.
///
/// The palette is fixed and the app has no themes, which makes this cheap:
/// every pair below is a pair that actually appears on screen. If someone
/// brightens a background or dims a label later, this fails with the ratio
/// rather than shipping 3.7:1 text to a person who cannot read it.
///
/// WCAG 2.1 numbers: 4.5:1 for body text, 3:1 for large text (>=18.66px
/// regular / >=24px, i.e. `PuckType.title` and up) and for UI component
/// boundaries that carry meaning.
double _channel(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) => 0.2126 * _channel(c.r) +
    0.7152 * _channel(c.g) +
    0.0722 * _channel(c.b);

double contrast(Color a, Color b) {
  final double la = _luminance(a);
  final double lb = _luminance(b);
  final double hi = math.max(la, lb);
  final double lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  // Every text token on every surface it is drawn on.
  const List<(String, Color, Color)> textPairs = <(String, Color, Color)>[
    ('textPrim on background', PuckPalette.textPrim, PuckPalette.background),
    ('textPrim on card', PuckPalette.textPrim, PuckPalette.card),
    ('textSec on background', PuckPalette.textSec, PuckPalette.background),
    ('textSec on card', PuckPalette.textSec, PuckPalette.card),
    ('textMuted on background', PuckPalette.textMuted, PuckPalette.background),
    ('textMuted on card', PuckPalette.textMuted, PuckPalette.card),
    // Filled surfaces draw their label in background (see the palette note).
    ('background on emergency', PuckPalette.background, PuckPalette.emergency),
    ('background on success', PuckPalette.background, PuckPalette.success),
    ('background on mutedBg', PuckPalette.background, PuckPalette.mutedBg),
    ('textPrim on mutedBg', PuckPalette.textPrim, PuckPalette.mutedBg),
  ];

  group('text contrast', () {
    for (final (String name, Color fg, Color bg) in textPairs) {
      test('$name clears 4.5:1', () {
        final double ratio = contrast(fg, bg);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '$name is ${ratio.toStringAsFixed(2)}:1',
        );
      });
    }
  });

  group('non-text contrast', () {
    test('the divider is visible enough to read as a divider', () {
      // A divider is decoration, not information: 1.14:1 on black is
      // intentional (it is a hairline, not a boundary anyone must perceive).
      // This test exists to stop it being used as a text colour.
      expect(contrast(PuckPalette.divider, PuckPalette.background),
          lessThan(1.5));
      expect(contrast(PuckPalette.divider, PuckPalette.textPrim),
          greaterThan(4.5),
          reason: 'white on divider is used by the pressed states');
    });

    test('the white disc reads against black and against the card', () {
      expect(contrast(PuckPalette.textPrim, PuckPalette.background),
          greaterThanOrEqualTo(3));
      expect(contrast(PuckPalette.textPrim, PuckPalette.card),
          greaterThanOrEqualTo(3));
    });

    test('emergency red reads against black and against the card', () {
      // The red ring, the counting state and the stop button are the one place
      // where colour is the message. It must clear 3:1 to be seen at all.
      expect(contrast(PuckPalette.emergency, PuckPalette.background),
          greaterThanOrEqualTo(3));
      expect(contrast(PuckPalette.emergency, PuckPalette.card),
          greaterThanOrEqualTo(3));
    });
  });

  test('the numbers in this file are the numbers in the palette note', () {
    // Guards the documentation against the code, which is the failure mode
    // that produced the old #666666 in the first place.
    expect(contrast(PuckPalette.textMuted, PuckPalette.background),
        closeTo(5.46, 0.02));
    expect(contrast(PuckPalette.textMuted, PuckPalette.card),
        closeTo(4.91, 0.02));
    expect(contrast(PuckPalette.background, PuckPalette.emergency),
        closeTo(5.92, 0.02));
    expect(contrast(PuckPalette.textPrim, PuckPalette.emergency),
        closeTo(3.55, 0.02));
  });
}
