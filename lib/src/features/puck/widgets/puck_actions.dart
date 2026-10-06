import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:puck/src/core/theme.dart';
import 'package:puck/src/features/puck/puck_controller.dart';
import 'package:puck/src/features/puck/puck_gesture_recognizer.dart';
import 'package:puck/src/l10n/puck_strings.dart';

/// The four behaviours, as a list of labelled buttons.
///
/// This is the surface that makes Puck usable by switch access, by voice
/// control, and by anyone who cannot hold a finger still for three seconds --
/// none of which the gesture model can serve on its own, however good the
/// gesture model is.
///
/// It is deliberately *not* part of the normal flow. It opens from a
/// semantics action on the bubble ("Show all actions"), from the quiet
/// "Actions" affordance that appears only when an assistive technology is
/// running, or from the accessibility shortcut -- never from a stray tap. The
/// people who do not need it never see it, which is the only way it can exist
/// without becoming a menu.
class PuckActionsSheet extends StatefulWidget {
  const PuckActionsSheet({
    required this.controller,
    required this.onOpenSettings,
    required this.onOpenPrivacy,
    required this.onClose,
    super.key,
  });

  final PuckController controller;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenPrivacy;
  final VoidCallback onClose;

  @override
  State<PuckActionsSheet> createState() => _PuckActionsSheetState();
}

class _PuckActionsSheetState extends State<PuckActionsSheet> {
  /// SOS is the one action here that gets a confirmation step.
  ///
  /// The hold is its own confirmation -- three seconds of deliberate pressure.
  /// A tap on a list is not, so the list asks first, in words, with the
  /// consequences stated. That keeps the pocket-safety promise while removing
  /// the physical demand.
  bool _confirmingSos = false;

  void _run(VoidCallback action) {
    widget.onClose();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final PuckStrings s = PuckStrings.of(context);

    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Container(
        color: PuckPalette.background.withValues(alpha: 0.98),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Semantics(
                        header: true,
                        child: Text(s.actionsTitle, style: PuckType.title),
                      ),
                      const SizedBox(height: 6),
                      Text(s.actionsHint, style: PuckType.label),
                      const SizedBox(height: 20),
                      if (_confirmingSos)
                        _ConfirmSos(
                          strings: s,
                          onStart: () => _run(
                            () => widget.controller
                                .handleGesture(PuckGestureKind.longPress),
                          ),
                          onBack: () => setState(() => _confirmingSos = false),
                        )
                      else ...<Widget>[
                        _ActionButton(
                          label: s.actionTap,
                          onTap: () => _run(() => widget.controller
                              .handleGesture(PuckGestureKind.tap)),
                        ),
                        _ActionButton(
                          label: s.actionJoke,
                          onTap: () => _run(() => widget.controller
                              .handleGesture(PuckGestureKind.doubleTap)),
                        ),
                        _ActionButton(
                          label: s.actionAsk,
                          onTap: () => _run(widget.controller.openIntentBar),
                        ),
                        _ActionButton(
                          label: s.actionSos,
                          emergency: true,
                          onTap: () => setState(() => _confirmingSos = true),
                        ),
                      ],
                      const Divider(
                        height: 40,
                        thickness: 1,
                        color: PuckPalette.divider,
                      ),
                      _ActionButton(
                        label: s.actionSettings,
                        quiet: true,
                        onTap: () => _run(widget.onOpenSettings),
                      ),
                      _ActionButton(
                        label: s.actionPrivacy,
                        quiet: true,
                        onTap: () => _run(widget.onOpenPrivacy),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: SizedBox(
                  height: 56,
                  child: _ActionButton(
                    label: s.actionsClose,
                    quiet: true,
                    onTap: widget.onClose,
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

class _ConfirmSos extends StatelessWidget {
  const _ConfirmSos({
    required this.strings,
    required this.onStart,
    required this.onBack,
  });

  final PuckStrings strings;
  final VoidCallback onStart;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          liveRegion: true,
          child: Text(
            strings.sosConfirmTitle,
            style: PuckType.primary.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 8),
        Text(strings.sosConfirmBody, style: PuckType.body),
        const SizedBox(height: 16),
        _ActionButton(
          label: strings.sosConfirmStart,
          emergency: true,
          onTap: onStart,
        ),
        _ActionButton(
          label: strings.sosConfirmBack,
          quiet: true,
          onTap: onBack,
        ),
      ],
    );
  }
}

/// 56px tall, full width, 16px corners: comfortably past the 48dp minimum,
/// with a real button semantics node rather than a gesture on a box.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onTap,
    this.emergency = false,
    this.quiet = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool emergency;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        label: label,
        child: ExcludeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              height: 56,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: emergency
                    ? PuckPalette.emergency
                    : (quiet ? Colors.transparent : PuckPalette.card),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: emergency
                    ? PuckType.primary.copyWith(
                        color: PuckPalette.background,
                        fontWeight: FontWeight.w600,
                      )
                    : PuckType.primary.copyWith(
                        fontWeight: FontWeight.w400,
                        color: quiet
                            ? PuckPalette.textSec
                            : PuckPalette.textPrim,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// True when something is reading the screen: TalkBack, VoiceOver, Switch
/// Access, or the accessibility shortcut.
///
/// Two signals, because they cover different populations. `semanticsEnabled`
/// is true for any assistive technology that consumes the semantics tree
/// (including switch access); `accessibleNavigation` is the platform's own
/// flag and is what most screen readers set. Either one is enough to offer the
/// action list, and neither is ever true for someone using Puck with a finger.
bool assistiveTechActive(BuildContext context) {
  if (SemanticsBinding.instance.semanticsEnabled) return true;
  return MediaQuery.maybeOf(context)?.accessibleNavigation ?? false;
}

/// The visible way in, shown *only* when [assistiveTechActive].
///
/// A screen-reader user who has not yet discovered the semantics actions needs
/// a target they can swipe to; this is that target, and it costs nothing to
/// anyone else because it does not exist for them.
class ActionsAffordance extends StatelessWidget {
  const ActionsAffordance({required this.onOpen, super.key});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Semantics(
        button: true,
        hint: PuckStrings.of(context).actionsHint,
        child: ExcludeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpen,
            child: Container(
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: PuckPalette.card,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                PuckStrings.of(context).actionsOpen,
                style: PuckType.primary.copyWith(fontWeight: FontWeight.w400),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
