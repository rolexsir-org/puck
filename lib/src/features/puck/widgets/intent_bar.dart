import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:puck/src/core/constants.dart';
import 'package:puck/src/core/theme.dart';
import 'package:puck/src/data/services/speech_service.dart';
import 'package:puck/src/features/puck/puck_controller.dart';
import 'package:puck/src/providers.dart';

/// The swipe-up surface: a pill that rises from wherever the bubble was,
/// grows to fit the answer, and closes on a swipe down or a tap outside.
///
/// Design constraints, in priority order:
///   1. It is on screen and focused in one frame. The gesture already told
///      the user what is happening; the bar does not narrate it.
///   2. The answer must never be more than a sentence. Enforced by the
///      prompt, not by the UI, so the UI just renders whatever comes back.
///   3. Anything unhandled (no key, no network) resolves to one human line.
///      An error dialog here would break the spell.
class IntentBar extends ConsumerStatefulWidget {
  const IntentBar({
    required this.controller,
    required this.bubbleCenter,
    super.key,
  });

  final PuckController controller;

  /// Where the bubble was when the gesture happened. The pill rises from
  /// there, not from the keyboard edge.
  final Offset bubbleCenter;

  @override
  ConsumerState<IntentBar> createState() => _IntentBarState();
}

class _IntentBarState extends ConsumerState<IntentBar>
    with SingleTickerProviderStateMixin {
  final TextEditingController _field = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ValueNotifier<bool> _listening = ValueNotifier<bool>(false);

  late final AnimationController _rise = AnimationController(
    vsync: this,
    duration: PuckConstants.move,
  );

  // RectTween evaluates to `Rect?` (the null case means "both ends unset").
  // begin and end are always assigned together below, so it is non-null in
  // practice; the type just can't know that.
  late final Animation<Rect?> _pill;

  double _dragDistance = 0;

  /// Captured rather than read in `dispose()`: the provider container can be
  /// gone by then, and a stale listener on a shared service is exactly the bug
  /// being fixed below.
  late final SpeechService _speech;

  @override
  void initState() {
    super.initState();
    _speech = ref.read(speechServiceProvider);
    // The bar appears because of a flick; the cursor is already in the field
    // before the keyboard finishes its own animation.
    _focus.requestFocus();
    _rise.forward();

    final Size screen = MediaQueryData.fromView(
      WidgetsBinding.instance.platformDispatcher.views.first,
    ).size;
    final Rect rest = Rect.fromLTWH(
      PuckConstants.screenMargin,
      0,
      screen.width - PuckConstants.screenMargin * 2,
      0,
    );

    // Start as a bubble-sized circle at the bubble, end as the resting pill.
    final Rect from = Rect.fromCircle(
      center: widget.bubbleCenter,
      radius: PuckConstants.bubbleSize / 2,
    );
    _pill = RectTween(begin: from, end: rest).animate(
      CurvedAnimation(parent: _rise, curve: PuckConstants.moveCurve),
    );
  }

  @override
  void dispose() {
    // The speech service outlives this widget (it is provided at app scope),
    // so its callbacks have to be cut here or the next session's recogniser
    // writes into a dead widget's TextEditingController.
    _speech
      ..onText = null
      ..onDone = null
      ..onError = null;
    unawaited(_speech.cancel());
    _rise.dispose();
    _field.dispose();
    _focus.dispose();
    _listening.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String query = _field.text.trim();
    if (query.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await _stopListening();
    widget.controller.submitQuery(query);
  }

  Future<void> _toggleMic() async {
    final SpeechService speech = _speech;

    if (_listening.value) {
      await _stopListening();
      return;
    }

    final bool ok = await speech.init();
    if (!ok || !mounted) return;

    speech
      ..onText = (String text, bool partial) {
        _field.text = text;
        _field.selection = TextSelection.collapsed(offset: text.length);
      }
      ..onDone = () {
        if (mounted) _listening.value = false;
      }
      ..onError = (String _) {
        if (mounted) _listening.value = false;
      };

    final bool started = await speech.start();
    if (!mounted) return;
    _listening.value = started;
  }

  Future<void> _stopListening() async {
    _listening.value = false;
    await _speech.stop();
  }

  @override
  Widget build(BuildContext context) {
    final IntentView? intent = widget.controller.intent;

    // The keyboard is handled by the Scaffold's resize, which animates in
    // lock-step with the OS keyboard -- no jump, no double-compensation.
    return GestureDetector(
      // Swipe down anywhere on the scrim to bail out; tap outside to close.
      onVerticalDragUpdate: (DragUpdateDetails d) {
        _dragDistance += d.delta.dy;
      },
      onVerticalDragEnd: (DragEndDetails d) {
        if (_dragDistance > 60) widget.controller.closeIntentBar();
        _dragDistance = 0;
      },
      onTap: () => widget.controller.closeIntentBar(),
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: PuckPalette.background.withValues(alpha: 0.96),
        child: SafeArea(
          top: false,
          child: Column(
            children: <Widget>[
              // The answer grows upward from the pill and scrolls if it
              // somehow outgrows the screen -- the input never moves.
              Expanded(
                child: intent == null
                    ? const SizedBox.shrink()
                    : Align(
                        alignment: Alignment.bottomCenter,
                        child: SingleChildScrollView(
                          reverse: true,
                          padding: const EdgeInsets.only(
                            left: PuckConstants.screenMargin,
                            right: PuckConstants.screenMargin,
                            bottom: 12,
                          ),
                          child: _Answer(intent: intent),
                        ),
                      ),
              ),
              AnimatedBuilder(
                animation: _rise,
                builder: (BuildContext context, Widget? child) {
                  final Rect r = _pill.value ?? Rect.zero;
                  return Align(
                    alignment: Alignment.bottomLeft,
                    child: Container(
                      margin: EdgeInsets.only(left: r.left),
                      width: r.width,
                      child: child,
                    ),
                  );
                },
                child: _InputRow(
                  controller: _field,
                  focusNode: _focus,
                  listening: _listening,
                  onSubmit: _submit,
                  onMic: _toggleMic,
                ),
              ),
              const SizedBox(height: PuckConstants.screenMargin),
            ],
          ),
        ),
      ),
    );
  }
}

/// The answer: streams in with a blinking cursor, sized to be read, not
/// studied. Tappable nothing, chromeless -- it is a sentence on a card.
class _Answer extends StatelessWidget {
  const _Answer({required this.intent});

  final IntentView intent;

  @override
  Widget build(BuildContext context) {
    final String answer = intent.answer.trim();
    final bool thinking = intent.streaming && answer.isEmpty;

    return PuckCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (thinking)
            const _ThinkingDots()
          else
            Text.rich(
              TextSpan(
                text: answer,
                style: PuckType.primary.copyWith(fontWeight: FontWeight.w400),
                children: intent.streaming
                    ? const <InlineSpan>[
                        WidgetSpan(
                          child: _Cursor(),
                          alignment: PlaceholderAlignment.middle,
                        ),
                      ]
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

/// A caret that blinks while tokens are still arriving, then stops. The
/// blink says "live"; the silence afterwards says "done".
class _Cursor extends StatefulWidget {
  const _Cursor();

  @override
  State<_Cursor> createState() => _CursorState();
}

class _CursorState extends State<_Cursor> with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0).animate(_blink),
      child: Container(
        width: 2,
        height: 18,
        margin: const EdgeInsets.only(left: 2),
        color: PuckPalette.textSec,
      ),
    );
  }
}

/// Three dots, staggered. Cheaper and calmer than a spinner.
class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots();

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext context, Widget? _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List<Widget>.generate(3, (int i) {
            final double phase = (_c.value * 3 - i) % 3;
            final double opacity = phase < 0 || phase > 1
                ? 0.22
                : 0.22 + 0.78 * (1 - phase.abs());
            return Container(
              margin: EdgeInsets.only(right: i == 2 ? 0 : 7),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: PuckPalette.textPrim.withValues(alpha: opacity),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

class _InputRow extends StatelessWidget {
  const _InputRow({
    required this.controller,
    required this.focusNode,
    required this.listening,
    required this.onSubmit,
    required this.onMic,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueNotifier<bool> listening;
  final Future<void> Function() onSubmit;
  final Future<void> Function() onMic;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (BuildContext context, TextEditingValue value, Widget? _) {
        final bool hasText = value.text.trim().isNotEmpty;
        return Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: PuckPalette.card,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  style: PuckType.primary.copyWith(
                    fontWeight: FontWeight.w400,
                  ),
                  cursorWidth: 2,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (String _) => unawaited(onSubmit()),
                  decoration: const InputDecoration(
                    hintText: 'Ask anything.',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: listening,
                builder: (BuildContext context, bool active, Widget? _) {
                  if (hasText) {
                    return _RoundButton(
                      icon: Icons.arrow_upward_rounded,
                      filled: true,
                      onTap: () => unawaited(onSubmit()),
                    );
                  }
                  return _RoundButton(
                    icon: active ? Icons.stop_rounded : Icons.mic_none_rounded,
                    active: active,
                    onTap: () => unawaited(onMic()),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onTap,
    this.filled = false,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: PuckConstants.pressOut,
        curve: Curves.easeOutCubic,
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: filled
              ? PuckPalette.textPrim
              : (active
                  ? PuckPalette.emergency
                  : Colors.transparent),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 20,
          color: filled
              ? PuckPalette.background
              : (active ? PuckPalette.textPrim : PuckPalette.textSec),
        ),
      ),
    );
  }
}
