import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:puck/src/core/theme.dart';
import 'package:puck/src/data/services/speech_service.dart';
import 'package:puck/src/features/puck/puck_controller.dart';
import 'package:puck/src/providers.dart';

/// The swipe-up surface: one line of input, one line of output.
///
/// Design constraints, in priority order:
///   1. It must be on screen and focused in under a frame. No hero animation,
///      no scale-in -- the gesture already told the user what is happening.
///   2. The answer must never be more than a sentence. Enforced by the prompt,
///      not by the UI, so the UI just renders whatever comes back.
///   3. Anything unhandled (no key, no network) resolves to a sentence too.
///      An error dialog here would break the spell.
class IntentBar extends ConsumerStatefulWidget {
  const IntentBar({required this.controller, super.key});

  final PuckController controller;

  @override
  ConsumerState<IntentBar> createState() => _IntentBarState();
}

class _IntentBarState extends ConsumerState<IntentBar>
    with SingleTickerProviderStateMixin {
  final TextEditingController _field = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ValueNotifier<bool> _listening = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _copied = ValueNotifier<bool>(false);

  Timer? _copiedTimer;
  double _dragDistance = 0;

  static const List<String> _hints = <String>[
    'flip a coin',
    'wash this wool sweater',
    'wake me at 7',
    'should I take an umbrella',
  ];

  @override
  void initState() {
    super.initState();
    // The bar appears because of a flick; the keyboard should already be up.
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    unawaited(ref.read(speechServiceProvider).cancel());
    _field.dispose();
    _focus.dispose();
    _listening.dispose();
    _copied.dispose();
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
    final SpeechService speech = ref.read(speechServiceProvider);

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
    await ref.read(speechServiceProvider).stop();
  }

  Future<void> _copy(String text) async {
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    _copied.value = true;
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) _copied.value = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final IntentView? intent = widget.controller.intent;
    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return GestureDetector(
      // Swipe down anywhere on the scrim to bail out.
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
        color: PuckPalette.background.withValues(alpha: 0.94),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(bottom: keyboardInset),
          child: Column(
            children: <Widget>[
              const _Grabber(),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: intent == null
                          ? const SizedBox.shrink(key: ValueKey<String>('empty'))
                          : _Answer(
                              key: const ValueKey<String>('answer'),
                              intent: intent,
                              onCopy: _copy,
                              copied: _copied,
                            ),
                    ),
                  ),
                ),
              ),
              _InputRow(
                controller: _field,
                focusNode: _focus,
                listening: _listening,
                onSubmit: _submit,
                onMic: _toggleMic,
                hints: _hints,
                showHints: intent == null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: PuckPalette.hairline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

/// The answer: monospace, tappable to copy, with a thinking state.
class _Answer extends StatelessWidget {
  const _Answer({
    required this.intent,
    required this.onCopy,
    required this.copied,
    super.key,
  });

  final IntentView intent;
  final Future<void> Function(String) onCopy;
  final ValueNotifier<bool> copied;

  @override
  Widget build(BuildContext context) {
    final String answer = intent.answer.trim();
    final bool thinking = intent.streaming && answer.isEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          '“${intent.query}”'.toUpperCase(),
          style: PuckType.label.copyWith(fontSize: 9),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 14),
        if (thinking)
          const _ThinkingDots()
        else
          GestureDetector(
            onTap: () => unawaited(onCopy(answer)),
            behavior: HitTestBehavior.opaque,
            child: Text(
              answer.isEmpty ? '…' : answer,
              style: PuckType.mono.copyWith(
                fontSize: 20,
                height: 1.42,
                color: intent.failed ? PuckPalette.textMid : PuckPalette.textHigh,
              ),
            ),
          ),
        const SizedBox(height: 14),
        ValueListenableBuilder<bool>(
          valueListenable: copied,
          builder: (BuildContext context, bool didCopy, Widget? child) {
            return Text(
              didCopy
                  ? 'COPIED'
                  : (thinking ? 'THINKING' : 'TAP TO COPY'),
              style: PuckType.label,
            );
          },
        ),
      ],
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
                color: PuckPalette.textHigh.withValues(alpha: opacity),
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
    required this.hints,
    required this.showHints,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueNotifier<bool> listening;
  final Future<void> Function() onSubmit;
  final Future<void> Function() onMic;
  final List<String> hints;
  final bool showHints;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (showHints) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 12),
              child: Text(
                hints.take(2).join('   ·   '),
                style: PuckType.label.copyWith(fontSize: 9),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          Container(
            height: 52,
            decoration: BoxDecoration(
              color: PuckPalette.surface,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: PuckPalette.hairline),
            ),
            child: Row(
              children: <Widget>[
                const SizedBox(width: 18),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    style: PuckType.input,
                    cursorWidth: 1.5,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (String _) => unawaited(onSubmit()),
                    decoration: const InputDecoration(
                      hintText: 'Ask anything…',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: listening,
                  builder: (BuildContext context, bool active, Widget? _) {
                    return _RoundButton(
                      icon: active ? Icons.stop_rounded : Icons.mic_none_rounded,
                      active: active,
                      onTap: () => unawaited(onMic()),
                    );
                  },
                ),
                const SizedBox(width: 6),
                _RoundButton(
                  icon: Icons.arrow_upward_rounded,
                  filled: true,
                  onTap: () => unawaited(onSubmit()),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
        ],
      ),
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
        duration: const Duration(milliseconds: 160),
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: filled
              ? PuckPalette.textHigh
              : (active ? PuckPalette.danger : Colors.transparent),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 17,
          color: filled
              ? PuckPalette.background
              : (active ? Colors.white : PuckPalette.textMid),
        ),
      ),
    );
  }
}
