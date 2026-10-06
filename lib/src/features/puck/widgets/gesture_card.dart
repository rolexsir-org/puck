import 'package:flutter/material.dart';
import 'package:puck/src/core/theme.dart';
import 'package:puck/src/features/puck/widgets/appear_in.dart';
import 'package:puck/src/l10n/puck_strings.dart';

/// The one-time card that names the four gestures.
///
/// Constraints, all of them load-bearing:
///   * It appears only after the first tap has been *served*, so it never
///     stands between a stranger and the thing that already works.
///   * It is a card in the same visual language as `ContextCard` -- same
///     chrome, same type, no arrows, no coachmarks, no stepped wizard.
///   * It is dismissed by a tap on it, and it is never shown again.
///
/// Discoverability without onboarding is exactly this: the product explains
/// itself once, in the shape of the product.
class GestureCard extends StatelessWidget {
  const GestureCard({required this.onDismiss, super.key});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final PuckStrings s = PuckStrings.of(context);

    return RepaintBoundary(
      child: AppearIn(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onDismiss,
          child: Semantics(
            container: true,
            // A card that must be tapped away is a button, so it says so.
            button: true,
            label: s.firstRunTitle,
            hint: s.firstRunDismiss,
            onTap: onDismiss,
            // Deliberately *not* wrapped in `ExcludeSemantics`, which is what
            // the bubble does. The bubble is one control with one name; this
            // card is information whose whole purpose is the four lines below
            // the title. Collapsing it to "Four things, one button" would
            // announce the heading and swallow the content -- the one thing a
            // user of this card came for.
            child: PuckCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(s.firstRunTitle, style: PuckType.primary),
                  const SizedBox(height: 12),
                  _GestureLine(text: s.firstRunTap),
                  _GestureLine(text: s.firstRunDoubleTap),
                  _GestureLine(text: s.firstRunHold),
                  _GestureLine(text: s.firstRunSwipe),
                  const SizedBox(height: 10),
                  Text(s.firstRunDismiss, style: PuckType.label),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GestureLine extends StatelessWidget {
  const _GestureLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 7, right: 10),
            child: Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: PuckPalette.textSec,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Flexible(child: Text(text, style: PuckType.body)),
        ],
      ),
    );
  }
}
