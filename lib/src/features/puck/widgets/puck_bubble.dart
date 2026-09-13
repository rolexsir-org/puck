import 'package:flutter/material.dart';
import 'package:puck/src/core/constants.dart';
import 'package:puck/src/core/theme.dart';
import 'package:puck/src/features/puck/puck_gesture_recognizer.dart';

/// The entire product surface: one 72px white disc.
///
/// The icon is a white circle on black; the bubble is the same object, so
/// recognising the app on the home screen and recognising the control in the
/// app are the same act. Everything it can do is expressed by how you touch
/// it, so its job is to *report that touch back* -- the red hold ring exists
/// because a 3-second hold with no feedback is indistinguishable from a
/// frozen app.
class PuckBubble extends StatefulWidget {
  const PuckBubble({
    required this.onGesture,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onRelease,
    super.key,
  });

  final void Function(PuckGestureKind kind) onGesture;
  final void Function(Offset globalPosition) onDragStart;
  final void Function(Offset delta, Offset globalPosition) onDragUpdate;
  final void Function(Velocity velocity) onDragEnd;

  /// The finger physically left the bubble, whatever the press became. SOS
  /// reads this as the pocket-release signal.
  final VoidCallback onRelease;

  @override
  State<PuckBubble> createState() => PuckBubbleState();
}

class PuckBubbleState extends State<PuckBubble> with TickerProviderStateMixin {
  /// Press scale: 1.0 -> 0.94 in 80ms, back on release. One controller, two
  /// durations -- the return is gentler than the hit.
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: PuckConstants.pressIn,
    reverseDuration: PuckConstants.pressOut,
  );

  /// Drives the hold ring. Duration matches the recogniser exactly, so the
  /// ring filling up *is* the countdown.
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: PuckConstants.longPressDuration,
  );

  bool _armed = false;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _hold.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed && !_armed) {
        setState(() => _armed = true);
      }
    });
  }

  void _onPressStart() {
    _armed = false;
    _press.forward();
    _hold.forward(from: 0);
  }

  void _onPressCancel() {
    _press.reverse();
    _hold.stop();
    _hold.reset();
    if (_armed && mounted) setState(() => _armed = false);
  }

  void _onDragStart(Offset global) {
    setState(() => _dragging = true);
    widget.onDragStart(global);
  }

  void _onDragEnd(Velocity velocity) {
    setState(() => _dragging = false);
    widget.onDragEnd(velocity);
  }

  @override
  void dispose() {
    _press.dispose();
    _hold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        PuckGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<PuckGestureRecognizer>(
          () => PuckGestureRecognizer(
            onGesture: widget.onGesture,
            onDragStart: _onDragStart,
            onDragUpdate: widget.onDragUpdate,
            onDragEnd: _onDragEnd,
            onPressStart: _onPressStart,
            onPressCancel: _onPressCancel,
            onPressEnd: widget.onRelease,
          ),
          (PuckGestureRecognizer instance) {
            // Callbacks are captured in the constructor closure; nothing to
            // rebind on rebuild.
          },
        ),
      },
      child: TweenAnimationBuilder<double>(
        // First appearance: 0.8 -> 1.0 on a spring-like curve, with the
        // overshoot that says "object", not "render target". Runs once.
        tween: Tween<double>(begin: 0.8, end: 1),
        duration: PuckConstants.move,
        curve: Curves.easeOutBack,
        builder: (BuildContext context, double appear, Widget? child) {
          return AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[_press, _hold]),
            builder: (BuildContext context, Widget? inner) {
              final double press = 1 - (0.06 * _press.value);
              return Transform.scale(
                scale: appear * press,
                child: inner,
              );
            },
            child: child,
          );
        },
        child: SizedBox(
          width: PuckConstants.bubbleSize,
          height: PuckConstants.bubbleSize,
          child: RepaintBoundary(
            child: CustomPaint(
              foregroundPainter: _HoldRingPainter(hold: _hold),
              child: AnimatedContainer(
                duration: PuckConstants.pressOut,
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: PuckPalette.textPrim,
                  boxShadow: <BoxShadow>[
                    // Single soft shadow. While dragging it deepens -- the
                    // disc lifts off the glass.
                    BoxShadow(
                      color: _dragging
                          ? const Color(0x73000000)
                          : const Color(0x4D000000),
                      blurRadius: _dragging ? 16 : 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The 3-second hold ring, painted over the white disc: sweeps clockwise from
/// 12 o'clock, then closes and stays red while SOS is armed. Red is the one
/// non-monochrome colour, and this is its other home.
class _HoldRingPainter extends CustomPainter {
  const _HoldRingPainter({required this.hold});

  final Animation<double> hold;

  /// The ring repaints on every tick of the hold controller -- the sweep
  /// *is* the countdown.
  @override
  Listenable? get repaint => hold;

  @override
  void paint(Canvas canvas, Size size) {
    final double progress = hold.value.clamp(0.0, 1.0);
    if (progress <= 0) return;

    final Offset center = size.center(Offset.zero);
    final double radius = size.width / 2 - 6;

    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = progress >= 1 ? StrokeCap.butt : StrokeCap.round
      ..color = PuckPalette.emergency;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5707963,
      6.2831853 * progress,
      false,
      ring,
    );
  }

  @override
  bool shouldRepaint(_HoldRingPainter old) => old.hold.value != hold.value;
}
