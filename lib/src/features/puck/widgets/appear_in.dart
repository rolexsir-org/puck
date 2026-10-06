import 'package:flutter/material.dart';
import 'package:puck/src/core/constants.dart';
import 'package:puck/src/core/motion.dart';

/// The shared appear animation for floating panels: scale from 0.9 with the
/// springy overshoot, 200ms. Dismissal is a plain fade handled by the
/// switcher -- things leave slower and quieter than they arrive.
///
/// With the platform's reduce-motion setting on, the panel appears with no
/// travel at all: same end state, zero duration (see [motionDuration]).
class AppearIn extends StatelessWidget {
  const AppearIn({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.9, end: 1),
      duration: motionDuration(context, PuckConstants.cardIn),
      curve: Curves.easeOutBack,
      builder: (BuildContext context, double t, Widget? child) {
        return Transform.scale(scale: t, child: child);
      },
      child: child,
    );
  }
}
