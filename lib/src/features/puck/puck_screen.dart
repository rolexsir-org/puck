import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:puck/src/core/constants.dart';
import 'package:puck/src/core/format.dart';
import 'package:puck/src/core/theme.dart';
import 'package:puck/src/data/models/context.dart';
import 'package:puck/src/data/repositories/joke_repository.dart';
import 'package:puck/src/features/puck/puck_controller.dart';
import 'package:puck/src/features/puck/widgets/context_card.dart';
import 'package:puck/src/features/puck/widgets/intent_bar.dart';
import 'package:puck/src/features/puck/widgets/joke_card.dart';
import 'package:puck/src/features/puck/widgets/puck_bubble.dart';
import 'package:puck/src/features/puck/widgets/sos_sheet.dart';
import 'package:puck/src/providers.dart';

/// The whole app, on one screen.
///
/// Layer order matters: the bubble must sit above the panel (it is the thing
/// you are aiming at), and both the intent bar and the SOS sheet are
/// full-bleed, so they own the surface entirely while open.
class PuckHome extends ConsumerStatefulWidget {
  const PuckHome({super.key});

  @override
  ConsumerState<PuckHome> createState() => _PuckHomeState();
}

class _PuckHomeState extends ConsumerState<PuckHome> with TickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    ref.read(puckControllerProvider).attach(this);

    // Warm the two things that cost something on first use: the secure-store
    // read for the API key, and the joke asset decode.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(settingsProvider).hydrate();
      await ref.read(jokeRepositoryProvider).load();
    });
  }

  @override
  void dispose() {
    ref.read(puckControllerProvider).detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final PuckController controller = ref.watch(puckControllerProvider);
    final bool overlaysOpen = controller.intentBarOpen || controller.isSosActive;

    return Scaffold(
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Size canvas = Size(constraints.maxWidth, constraints.maxHeight);
          controller.updateCanvas(canvas);

          return Stack(
            children: <Widget>[
              const _Backdrop(),

              if (!overlaysOpen)
                _PanelLayer(controller: controller, canvas: canvas),

              _BubbleLayer(controller: controller),

              if (!overlaysOpen) _Footer(controller: controller),

              if (controller.intentBarOpen)
                Positioned.fill(
                  child: IntentBar(controller: controller),
                ),

              if (controller.isSosActive)
                Positioned.fill(
                  child: SosSheet(controller: controller),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Matte black with a barely-there lift at the top. Static: painted once,
/// never rebuilt.
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.55),
            radius: 1.25,
            colors: <Color>[Color(0xFF16161B), PuckPalette.background],
          ),
        ),
      ),
    );
  }
}

class _BubbleLayer extends StatelessWidget {
  const _BubbleLayer({required this.controller});

  final PuckController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Offset>(
      valueListenable: controller.bubblePosition,
      // `child` is hoisted so a drag rebuilds the Positioned, not the bubble.
      builder: (BuildContext context, Offset pos, Widget? child) {
        return Positioned(
          left: PuckConstants.bubbleMargin + pos.dx,
          top: PuckConstants.bubbleMargin + pos.dy,
          width: PuckConstants.bubbleSize,
          height: PuckConstants.bubbleSize,
          child: child!,
        );
      },
      child: PuckBubble(
        onGesture: controller.handleGesture,
        onDragStart: controller.onDragStart,
        onDragUpdate: controller.onDragUpdate,
        onDragEnd: controller.onDragEnd,
      ),
    );
  }
}

/// Anchors the transient card to whichever side the bubble is parked on, and
/// flips above/below depending on where it sits vertically -- so the card can
/// never cover the thing you are about to touch again.
class _PanelLayer extends StatelessWidget {
  const _PanelLayer({required this.controller, required this.canvas});

  final PuckController controller;
  final Size canvas;

  @override
  Widget build(BuildContext context) {
    final double maxX = canvas.width -
        PuckConstants.bubbleSize -
        PuckConstants.bubbleMargin * 2;
    final double maxY = canvas.height -
        PuckConstants.bubbleSize -
        PuckConstants.bubbleMargin * 2;

    return ValueListenableBuilder<Offset>(
      valueListenable: controller.bubblePosition,
      builder: (BuildContext context, Offset pos, Widget? _) {
        final bool bubbleOnLeft = pos.dx < maxX / 2;
        final bool bubbleLow = pos.dy > maxY * 0.5;

        return Positioned(
          left: bubbleOnLeft ? PuckConstants.bubbleMargin : null,
          right: bubbleOnLeft ? null : PuckConstants.bubbleMargin,
          top: bubbleLow ? null : pos.dy + PuckConstants.bubbleMargin + PuckConstants.bubbleSize + 14,
          bottom: bubbleLow ? canvas.height - PuckConstants.bubbleMargin - pos.dy + 14 : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: PuckFormat.clamp(
                canvas.width - PuckConstants.bubbleMargin * 2 - 8,
                120,
                PuckConstants.panelMaxWidth,
              ),
            ),
            child: AnimatedSwitcher(
              duration: PuckConstants.panelDuration,
              switchInCurve: PuckConstants.panelInCurve,
              switchOutCurve: PuckConstants.panelOutCurve,
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.06),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: _panelFor(controller),
            ),
          ),
        );
      },
    );
  }

  static const Widget _empty = SizedBox.shrink(key: ValueKey<String>('none'));

  Widget _panelFor(PuckController c) {
    switch (c.panel) {
      case PanelKind.context:
        final ContextItem? item = c.contextItem;
        return item == null
            ? _empty
            : ContextCard(key: const ValueKey<String>('context'), item: item);
      case PanelKind.joke:
        final Joke? joke = c.joke;
        return joke == null
            ? _empty
            : JokeCard(key: const ValueKey<String>('joke'), joke: joke);
      case PanelKind.answer:
        // Answers render inside the IntentBar, which reads `controller.intent`
        // directly; the controller never assigns this panel. Returning the
        // empty slot keeps the switch exhaustive without inventing a second
        // renderer for the same content.
        return _empty;
      case PanelKind.none:
        return _empty;
    }
  }
}

/// Settings link, and the one-time gesture legend.
///
/// A four-gesture interface with no visible chrome is undiscoverable, so Puck
/// breaks its own rule exactly once, on first run.
class _Footer extends ConsumerWidget {
  const _Footer({required this.controller});

  final PuckController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool introSeen = ref.watch(settingsProvider).introSeen;
    final bool showIntro =
        !introSeen && controller.panel == PanelKind.none && !controller.intentBarOpen;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (showIntro) ...<Widget>[
              const Padding(
                padding: EdgeInsets.fromLTRB(28, 0, 28, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _LegendLine(label: 'TAP', text: 'one useful thing'),
                    SizedBox(height: 7),
                    _LegendLine(label: 'DOUBLE TAP', text: 'a small joke'),
                    SizedBox(height: 7),
                    _LegendLine(label: 'HOLD 3s', text: 'SOS'),
                    SizedBox(height: 7),
                    _LegendLine(label: 'SWIPE UP', text: 'ask anything'),
                  ],
                ),
              ),
            ],
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pushNamed('/settings'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                child: Text(
                  'SETTINGS',
                  style: PuckType.label.copyWith(
                    color: PuckPalette.textLow.withValues(alpha: 0.65),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendLine extends StatelessWidget {
  const _LegendLine({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: 74,
          child: Text(label, style: PuckType.label),
        ),
        Text(text, style: PuckType.detail.copyWith(fontSize: 12.5)),
      ],
    );
  }
}
