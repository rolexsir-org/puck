import 'package:flutter/widgets.dart';

/// The platform's "reduce motion" setting, honoured.
///
/// Android: Settings > Accessibility > Remove animations. iOS: Settings >
/// Accessibility > Motion > Reduce Motion. Flutter surfaces both as
/// `MediaQueryData.disableAnimations`, and it is false unless someone asked
/// for it, so nothing changes for anyone else.
///
/// Why this matters even though Puck's motion is small: the snap launches a
/// 72px disc across the screen *underneath the finger that just released it*.
/// For a person with a vestibular disorder that is exactly the kind of motion
/// that causes trouble, and the platform has already told us, in a setting
/// they turned on deliberately. A design that ignores a statement that
/// explicit is a design that decided they did not mean it.
///
/// Reduced motion is not *no* state change: the duration becomes zero, so
/// every panel still arrives, at its final position, instantly.
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

/// [duration], or nothing at all when the platform asked for no motion.
Duration motionDuration(BuildContext context, Duration duration) =>
    reduceMotion(context) ? Duration.zero : duration;
