import 'dart:async';

import 'package:flutter/animation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';

/// Two spring simulations driven by one ticker pair.
///
/// `AnimationController.animateWith` runs a real physics simulation and stops
/// when it settles, which is exactly what edge-snapping wants: the bubble
/// should decelerate *into* the edge with the velocity your finger had, not
/// ease along a fixed curve. A `Curves.easeOut` tween cannot express "the user
/// flicked this hard".
///
/// Two controllers rather than one, because `animateWith` drives a single
/// scalar and a bubble moves in two axes.
class SpringOffset2D {
  SpringOffset2D({
    required TickerProvider vsync,
    required this.onUpdate,
    Offset value = Offset.zero,
    this.spring = const SpringDescription(mass: 1, stiffness: 420, damping: 26),
  }) : _value = value {
    _x = AnimationController.unbounded(vsync: vsync)..addListener(_tick);
    _y = AnimationController.unbounded(vsync: vsync)..addListener(_tick);
  }

  final VoidCallback onUpdate;
  final SpringDescription spring;

  late final AnimationController _x;
  late final AnimationController _y;
  Offset _value;

  Offset get value => _value;

  /// Launches toward [target], inheriting the fling velocity so a fast flick
  /// carries past the midpoint and a slow drag does not.
  void animateTo(Offset target, {Velocity velocity = Velocity.zero}) {
    unawaited(
      _x.animateWith(
        SpringSimulation(
          spring,
          _value.dx,
          target.dx,
          velocity.pixelsPerSecond.dx,
        ),
      ),
    );
    unawaited(
      _y.animateWith(
        SpringSimulation(
          spring,
          _value.dy,
          target.dy,
          velocity.pixelsPerSecond.dy,
        ),
      ),
    );
  }

  /// Stops dead and teleports. Used for the first layout and on rotation.
  void jumpTo(Offset target) {
    _x.stop();
    _y.stop();
    _x.value = target.dx;
    _y.value = target.dy;
    _value = target;
    onUpdate();
  }

  void _tick() {
    _value = Offset(_x.value, _y.value);
    onUpdate();
  }

  void dispose() {
    _x.dispose();
    _y.dispose();
  }
}
