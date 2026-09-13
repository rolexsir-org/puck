import 'package:flutter/material.dart';
import 'package:puck/src/core/theme.dart';
import 'package:puck/src/features/puck/widgets/appear_in.dart';

/// The double-tap card. One line of deadpan, set like everything else in the
/// app -- a joke that announces itself as a joke stops being one.
class JokeCard extends StatelessWidget {
  const JokeCard({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AppearIn(
        child: PuckCard(
          child: Text(
            text,
            style: PuckType.primary.copyWith(fontWeight: FontWeight.w400),
          ),
        ),
      ),
    );
  }
}
