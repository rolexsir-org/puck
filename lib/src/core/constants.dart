import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

/// The single tuning surface for Puck.
///
/// Anything a designer would want to argue about lives here and nowhere else.
abstract final class PuckConstants {
  // -- Geometry -------------------------------------------------------------
  static const double bubbleSize = 72;
  static const double bubbleMargin = 14;
  static const double screenMargin = 16;
  static const double cardMaxWidth = 340;

  // -- Gestures -------------------------------------------------------------
  /// Long-press hold time before SOS arms.
  static const Duration longPressDuration = Duration(seconds: 3);

  /// How long we wait for a second tap before committing to a single tap.
  /// Kept short (Flutter's default is 300ms) because single tap is the
  /// highest-frequency gesture in the app.
  static const Duration doubleTapTimeout = Duration(milliseconds: 260);

  /// Upward travel (logical px) that converts a drag into a swipe-up.
  static const double swipeUpDistance = 56;

  /// Pointer travel before a press becomes a drag. Matches kTouchSlop.
  static const double touchSlop = 18;

  /// Vertical travel must dominate horizontal by this ratio to count as up.
  static const double swipeUpAxisRatio = 1.2;

  // -- Dismissals -----------------------------------------------------------
  static const Duration contextDismiss = Duration(seconds: 4);
  static const Duration jokeDismiss = Duration(seconds: 4);

  /// Longer than the toasts: an answer takes more reading than a heads-up.
  static const Duration answerDismiss = Duration(seconds: 7);

  /// When a card is upgraded in place (the local line sharpened by the model),
  /// guarantee at least this much reading time remains. Otherwise a rewrite
  /// arriving at 3.6s gives the user four-tenths of a second to read a better
  /// line than the one they already read.
  static const Duration minReadTime = Duration(milliseconds: 2200);

  // -- Motion ---------------------------------------------------------------
  /// One spring for the whole app. Damping 25.2 on stiffness 400 with unit
  /// mass is a damping ratio of 0.63 -- snappy with a whisper of overshoot.
  static const SpringDescription snapSpring = SpringDescription(
    mass: 1,
    stiffness: 400,
    damping: 25.2,
  );

  /// The press response is faster than everything else on purpose: the
  /// bubble must feel like a physical button, not a UI element.
  static const Duration pressIn = Duration(milliseconds: 80);
  static const Duration pressOut = Duration(milliseconds: 160);

  /// Appear: scale from 0.9 + fade, 200ms, spring curve.
  static const Duration cardIn = Duration(milliseconds: 200);

  /// Disappear: fade only, no scale.
  static const Duration cardOut = Duration(milliseconds: 240);

  /// The shared easing for everything that is not the spring.
  static const Duration move = Duration(milliseconds: 240);
  static const Curve moveCurve = Curves.easeOutCubic;

  // -- SOS ------------------------------------------------------------------
  /// The countdown ring sweep, full to empty.
  static const Duration sosCountdown = Duration(seconds: 3);

  /// Torch + haptics run down after this long even if the sheet is never
  /// dismissed, so a phone in a pocket does not cook itself.
  static const Duration sosRunawayTimeout = Duration(seconds: 30);

  /// Morse timings for the SOS strobe (... --- ...).
  static const Duration morseDot = Duration(milliseconds: 200);
  static const Duration morseDash = Duration(milliseconds: 600);
  static const Duration morseGap = Duration(milliseconds: 200);
  static const Duration morseLetterGap = Duration(milliseconds: 600);
  static const int sosStrobeCycles = 2;

  // -- Network --------------------------------------------------------------
  static const Duration llmConnectTimeout = Duration(seconds: 6);
  static const Duration llmIdleTimeout = Duration(seconds: 20);
  static const Duration weatherTimeout = Duration(seconds: 5);
  static const Duration locationTimeout = Duration(seconds: 8);

  /// Weather is re-fetched at most this often; the ranker reads the cache.
  static const Duration weatherCacheTtl = Duration(minutes: 30);

  /// Battery and calendar snapshots are this stale at most. A tap inside the
  /// window is answered from memory, which keeps the guaranteed
  /// under-100ms card truly guaranteed.
  static const Duration snapshotCacheTtl = Duration(seconds: 30);
}
