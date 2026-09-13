import 'dart:async';

import 'package:flutter/material.dart';
import 'package:puck/src/core/constants.dart';
import 'package:puck/src/core/theme.dart';
import 'package:puck/src/features/puck/puck_controller.dart';

/// The SOS sheet.
///
/// Full-screen black; the one surface where Puck is loud. It appears only
/// after a deliberate three-second hold, then counts down for three more.
///
/// The countdown is the pocket filter. Lifting the finger at any point in it
/// disarms everything -- a phone jostled in a bag never keeps pressure for
/// six seconds, but a person asking for help does. Holding through the end
/// fires the torch, opens the SMS composer with the location pre-filled, and
/// the ring becomes a status light for what happened.
///
/// There is no send button. The composer is the confirmation.
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

  @override
  Widget build(BuildContext context) {
    final SosView? sos = widget.controller.sos;
    if (sos == null) return const SizedBox.shrink();

    final bool counting = sos.phase == SosPhase.counting;

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
              const Spacer(),
              _Ring(sos: sos),
              const SizedBox(height: 24),
              Text(
                counting ? 'SOS in ${sos.secondsLeft}' : sos.status,
                style: PuckType.body.copyWith(
                  color: PuckPalette.textMuted,
                  fontSize: 17,
                ),
              ),
              if (!counting && !sos.hasContact) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  'No emergency contact set',
                  style: PuckType.body.copyWith(color: PuckPalette.emergency),
                ),
              ],
              const Spacer(),
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: _SheetButton(
                    label: counting ? 'CANCEL' : 'STOP',
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
/// red. Afterwards it is a status light: green once the GPS fix landed,
/// quiet grey while the radio is still working. (The palette has no amber;
/// in-progress is grey, success is green, alarm is red. Three states, three
/// tokens.)
class _Ring extends StatelessWidget {
  const _Ring({required this.sos});

  final SosView sos;

  @override
  Widget build(BuildContext context) {
    final bool counting = sos.phase == SosPhase.counting;
    final Color color = counting
        ? PuckPalette.emergency
        : (sos.position != null ? PuckPalette.success : PuckPalette.textSec);

    return TweenAnimationBuilder<double>(
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
      child: counting
          ? Text('${sos.secondsLeft}', style: PuckType.countdown)
          : Icon(
              sos.position != null
                  ? Icons.check_rounded
                  : Icons.more_horiz_rounded,
              size: 44,
              color: color,
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
class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.counting,
    required this.onTap,
  });

  final String label;
  final bool counting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
    );
  }
}
