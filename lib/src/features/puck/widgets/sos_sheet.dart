import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:puck/src/core/constants.dart';
import 'package:puck/src/core/theme.dart';
import 'package:puck/src/features/puck/puck_controller.dart';
import 'package:puck/src/l10n/puck_strings.dart';

/// The SOS sheet.
///
/// Full-screen black; the one surface where Puck is loud. It appears only
/// after a deliberate hold, then counts down for a few more seconds.
///
/// The countdown is the pocket filter. Lifting the finger at any point in it
/// disarms everything -- a phone jostled in a bag never keeps pressure for
/// six seconds, but a person asking for help does. Holding through the end
/// fires the torch, opens the SMS composer with the location pre-filled (or
/// the dialer, if there is nowhere to text), and the ring becomes a status
/// light for what happened.
///
/// There is no send button. The composer is the confirmation.
///
/// Accessibility note: this is the one screen where a screen-reader user gets
/// nothing from the visuals at all. The countdown is an arc and a big number;
/// the status is a colour. Every phase change here is therefore announced
/// through [SemanticsService], and the ring carries a live label so the
/// seconds are available as text, not only as geometry.
class SosSheet extends StatefulWidget {
  const SosSheet({required this.controller, super.key});

  final PuckController controller;

  @override
  State<SosSheet> createState() => _SosSheetState();
}

class _SosSheetState extends State<SosSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: PuckConstants.move,
  )..forward();

  late final Animation<double> _offset = CurvedAnimation(
    parent: _slide,
    curve: PuckConstants.moveCurve,
  );

  bool _closing = false;

  /// What was last announced, so the sheet speaks once per state rather than
  /// once per frame. The countdown ticks every second; re-announcing the
  /// whole sheet on every tick would make it unusable.
  String? _announced;

  Future<void> _cancel() async {
    if (_closing) return;
    _closing = true;
    await _slide.reverse();
    await widget.controller.cancelSos();
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  /// Announces a state change to assistive technology.
  ///
  /// Announcing is the *only* way a screen-reader user learns that the
  /// countdown started, how far it has got, or what happened when it ended:
  /// the sheet's whole message is an arc, a numeral and a colour. Deferred to
  /// after the frame because it is a platform call, and de-duplicated because
  /// the countdown rebuilds once a second.
  void _announce(String message) {
    if (_announced == message) return;
    _announced = message;
    final TextDirection direction = Directionality.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SemanticsService.announce(message, direction);
    });
  }

  @override
  Widget build(BuildContext context) {
    final SosView? sos = widget.controller.sos;
    if (sos == null) return const SizedBox.shrink();

    final PuckStrings s = PuckStrings.of(context);
    final bool counting = sos.phase == SosPhase.counting;
    final bool offerEmergency =
        !counting && (!sos.hasContact || sos.smsHandoffFailed);

    _announce(
      counting ? s.sosCountingAnnouncement(sos.secondsLeft) : sos.status,
    );

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(_offset),
      child: Container(
        color: PuckPalette.background,
        child: SafeArea(
          top: false,
          child: Column(
            children: <Widget>[
              // The middle of the sheet scrolls so that 2.0x system text --
              // where a status line becomes three lines and the emergency
              // explanation becomes five -- cannot push the cancel button off
              // the bottom of the screen. The button that stops an emergency
              // is the one thing here that must never move.
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: PuckConstants.screenMargin,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _Ring(sos: sos, strings: s),
                        const SizedBox(height: 24),
                        Text(
                          counting
                              ? s.sosCounting(sos.secondsLeft)
                              : sos.status,
                          key: const ValueKey<String>('sos-status'),
                          textAlign: TextAlign.center,
                          style: PuckType.body.copyWith(
                            color: PuckPalette.textSec,
                            fontSize: 17,
                          ),
                        ),
                        if (offerEmergency) ...<Widget>[
                          const SizedBox(height: 20),
                          _EmergencyCall(
                            strings: s,
                            emergency: sos.emergency,
                            onTap: () =>
                                unawaited(widget.controller.dialEmergency()),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: _SheetButton(
                    label: counting ? s.sosCancel : s.sosStop,
                    hint: counting ? s.sosCancelHint : s.sosStopHint,
                    counting: counting,
                    onTap: () => unawaited(_cancel()),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 120px ring, 4px stroke. While counting it sweeps from full to empty in
/// red. Afterwards it is a status light: green once the message is on its way,
/// quiet grey while the radio is still working. (The palette has no amber;
/// in-progress is grey, success is green, alarm is red. Three states, three
/// tokens.)
///
/// The ring is decoration for the eye only. Everything it encodes is also in
/// the text below it and in the semantics label here -- no colour-only and no
/// shape-only information.
class _Ring extends StatelessWidget {
  const _Ring({required this.sos, required this.strings});

  final SosView sos;
  final PuckStrings strings;

  @override
  Widget build(BuildContext context) {
    final bool counting = sos.phase == SosPhase.counting;
    final Color color = counting
        ? PuckPalette.emergency
        : (sos.position != null ? PuckPalette.success : PuckPalette.textSec);

    final String meaning = counting
        ? strings.sosCounting(sos.secondsLeft)
        : (sos.position != null
            ? strings.sosRingFound
            : strings.sosRingWaiting);

    return Semantics(
      // Live region: the seconds are the only thing that changes while the
      // user's finger is still down, and they are the difference between
      // "counting down" and "frozen".
      liveRegion: counting,
      label: meaning,
      container: true,
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          key: ValueKey<SosPhase>(sos.phase),
          tween: Tween<double>(begin: 1, end: counting ? 0 : 1),
          duration: counting
              ? PuckConstants.sosCountdown
              : const Duration(milliseconds: 200),
          curve: counting ? Curves.linear : Curves.easeOutCubic,
          builder: (BuildContext context, double t, Widget? child) {
            return SizedBox(
              width: 120,
              height: 120,
              child: CustomPaint(
                painter: _RingPainter(progress: t, color: color),
                child: Center(child: child),
              ),
            );
          },
          // A 96px numeral inside a 120px ring cannot follow the system text
          // scale: at 2.0x it is 192px tall and leaves the circle it is drawn
          // in. Clamped deliberately, and the same number is available at full
          // scale in the status line below the ring.
          child: counting
              ? MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: Text('${sos.secondsLeft}', style: PuckType.countdown),
                )
              : Icon(
                  sos.position != null
                      ? Icons.check_rounded
                      : Icons.more_horiz_rounded,
                  size: 44,
                  color: color,
                ),
        ),
      ),
    );
  }
}

/// The way out for someone who has nobody configured to text -- which is the
/// default state for a fresh install, and therefore the state most people
/// will be in when they need this.
///
/// The number is printed next to the action and the action opens the dialer.
/// Both choices are deliberate: the user can see what is about to be dialled
/// before they dial it, and Puck itself never places a call.
class _EmergencyCall extends StatelessWidget {
  const _EmergencyCall({
    required this.strings,
    required this.emergency,
    required this.onTap,
  });

  final PuckStrings strings;
  final EmergencyNumber emergency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 24,
      ),
      child: Column(
        children: <Widget>[
          SizedBox(
            width: double.infinity,
            height: 56,
            child: Semantics(
              button: true,
              label: strings.callEmergencySemantics(emergency.number),
              hint: strings.callEmergencyHint,
              child: ExcludeSemantics(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: PuckPalette.emergency,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      strings.callEmergency(emergency.number),
                      // Black on the emergency red: white on it is 3.4:1,
                      // which fails AA for 17px text. See PuckPalette.
                      style: PuckType.primary.copyWith(
                        color: PuckPalette.background,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            emergency.isRegional
                ? strings.sosEmergencyFallbackNote
                : strings.sosEmergencyRegionalNote,
            textAlign: TextAlign.center,
            style: PuckType.label.copyWith(color: PuckPalette.textSec),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final Rect rect = Rect.fromCircle(center: center, radius: 58);

    // Track: the faint circle the sweep lives on.
    canvas.drawCircle(
      center,
      58,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = PuckPalette.mutedBg,
    );

    if (progress <= 0) return;

    // The sweep runs clockwise; `progress` is what remains, so the arc is
    // drawn from the top, backwards -- full to empty, no rewind.
    canvas.drawArc(
      rect,
      -1.5707963,
      6.2831853 * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = progress >= 1 ? StrokeCap.butt : StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

/// The one button. Red while the decision is live; quieter once the message
/// is on its way and "stop" means stop the noise, not stop the message.
///
/// 56px tall, full width: comfortably past the 48dp minimum for a target that
/// someone may be aiming at with shaking hands.
class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.hint,
    required this.counting,
    required this.onTap,
  });

  final String label;
  final String hint;
  final bool counting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      hint: hint,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: PuckConstants.move,
            curve: Curves.easeOutCubic,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: counting ? PuckPalette.emergency : PuckPalette.mutedBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              label,
              style: PuckType.primary.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}
