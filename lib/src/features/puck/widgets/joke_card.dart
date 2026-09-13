import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:puck/src/core/theme.dart';
import 'package:puck/src/data/repositories/joke_repository.dart';

/// The double-tap card.
///
/// Monospace, because the joke is a quoted object rather than interface copy.
/// Quotes get a wink of a label; jokes get none -- a punchline with a label
/// above it stops being a punchline.
class JokeCard extends StatelessWidget {
  const JokeCard({required this.joke, super.key});

  final Joke joke;

  @override
  Widget build(BuildContext context) {
    final bool isQuote = joke.kind == JokeKind.quote;

    return PuckCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (isQuote) ...<Widget>[
            const Text('MOTIVATION, PROBABLY', style: PuckType.label),
            const SizedBox(height: 8),
          ],
          Text(
            joke.text,
            style: PuckType.mono.copyWith(
              // A joke set in a heavier weight reads like a system alert.
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
