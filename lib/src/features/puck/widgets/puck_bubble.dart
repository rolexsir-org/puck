import 'package:flutter/material.dart';
import 'package:puck/src/core/constants.dart';
import 'package:puck/src/core/theme.dart';
import 'package:puck/src/features/puck/puck_gesture_recognizer.dart';

/// The entire product surface: one 72px disc.
///
/// Everything it can do is expressed by how you touch it, so its job is to
/// *report that touch back* -- the long-press ring exists because a 3-second
/// hold with no feedback is indistinguishable from a frozen app.
class PuckBubble extends StatefulWidget {
  const PuckBubble({
    required this.onGesture,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    super.key,
  });

  final void Function(PuckGestureKind kind) onGesture;
  final void Function(Offset globalPosition) onDragStart;
  final void Function(Offset delta, Offset globalPosition) onDragUpdate;
  final void Function(Velocity velocity) onDragEnd;

  @override
  State<PuckBubble> createState() => PuckBubbleState();
}

class PuckBubbleState extends State<PuckBubble> with TickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 110),
  );

  /// Drives the hold ring. Duration matches the recogniser exactly, so the
  /// ring filling up *is* the countdown.
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: PuckConstants.longPressDuration,
  );

  bool _armed = false;

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
        PuckGestureRecognizer: GestureRecognizerFactoryWithHandlers<
            PuckGestureRecognizer>(
          () => PuckGestureRecognizer(
            onGesture: widget.onGesture,
            onDragStart: widget.onDragStart,
            onDragUpdate: widget.onDragUpdate,
            onDragEnd: widget.onDragEnd,
            onPressStart: _onPressStart,
            onPressCancel: _onPressCancel,
          ),
          (PuckGestureRecognizer instance) {
            // Callbacks are captured in the constructor closure; nothing to
            // rebind on rebuild.
          },
        ),
      },
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[_press, _hold]),
        builder: (BuildContext context, Widget? child) {
          final double scale = 1 - (0.07 * _press.value);
          return Transform.scale(
            scale: scale,
            child: child,
          );
        },
        child: SizedBox(
          width: PuckConstants.bubbleSize,
          height: PuckConstants.bubbleSize,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _PuckFacePainter(
                progress: _hold.value,
                armed: _armed,
                pressed: _press.value,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hand-painted rather than built from widgets: three arcs and a dot is
/// cheaper than a stack of containers with box shadows, and it keeps the
/// bubble perfectly crisp at any DPI.
class _PuckFacePainter extends CustomPainter {
  const _PuckFacePainter({
    required this.progress,
    required this.armed,
    required this.pressed,
  });

  final double progress;
  final bool armed;
  final double pressed;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = size.width / 2;
    final Rect rect = Offset.zero & size;

    // Body: a very slight radial lift keeps it from reading as a flat hole
    // punched in the background.
    final Paint fill = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.25, -0.3),
        radius: 1.05,
        colors: <Color>[
          Color.lerp(PuckPalette.surfaceHi, Colors.white, 0.04 * pressed)!,
          PuckPalette.surface,
        ],
      ).createShader(rect);
    canvas.drawCircle(center, radius - 1, fill);

    // Rim.
    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = PuckPalette.hairline,
    );

    // Hold ring: sweeps clockwise from 12 o'clock over exactly three seconds.
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 4.5),
        -1.5707963,
        6.2831853 * progress.clamp(0.0, 1.0),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = armed
              ? PuckPalette.danger
              : PuckPalette.textHigh.withValues(alpha: 0.9),
      );
    }

    // Core dot. Grows slightly on press; turns red only for SOS.
    final double dotRadius = 6 + (1.5 * pressed);
    canvas.drawCircle(
      center,
      dotRadius,
      Paint()..color = armed ? PuckPalette.danger : PuckPalette.textHigh,
    );
  }

  @override
  bool shouldRepaint(_PuckFacePainter old) =>
      old.progress != progress ||
      old.armed != armed ||
      old.pressed != pressed;
}
