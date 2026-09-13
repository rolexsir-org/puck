import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:puck/src/core/constants.dart';
import 'package:puck/src/core/format.dart';
import 'package:puck/src/core/theme.dart';
import 'package:puck/src/data/models/context.dart';
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

class _PuckHomeState extends ConsumerState<PuckHome>
    with TickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    ref.read(puckControllerProvider).attach(this);

    // Warm the two things that cost something on first use: the secure-store
    // read for the API key, and the joke asset decode. Both finish long
    // before a finger can double-tap.
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
      // The keyboard resize is the keyboard animation; the bar rides it.
      resizeToAvoidBottomInset: true,
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

              if (!overlaysOpen) const _Footer(),

              if (controller.intentBarOpen)
                Positioned.fill(
                  child: IntentBar(
                    controller: controller,
                    bubbleCenter: _bubbleCenter(controller, canvas),
                  ),
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

  static Offset _bubbleCenter(PuckController controller, Size canvas) {
    final Offset pos = controller.bubblePosition.value;
    return Offset(
      PuckConstants.bubbleMargin + pos.dx + PuckConstants.bubbleSize / 2,
      PuckConstants.bubbleMargin + pos.dy + PuckConstants.bubbleSize / 2,
    );
  }
}

/// Pure black. Painted once, never rebuilt.
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(
      child: ColoredBox(color: PuckPalette.background),
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
        onRelease: controller.onBubbleRelease,
      ),
    );
  }
}

/// Anchors the transient card 16px above the bubble, centred on the bubble
/// and clamped to the screen edges -- so the card can never cover the thing
/// you are about to touch again.
class _PanelLayer extends StatelessWidget {
  const _PanelLayer({required this.controller, required this.canvas});

  final PuckController controller;
  final Size canvas;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Offset>(
      valueListenable: controller.bubblePosition,
      builder: (BuildContext context, Offset pos, Widget? _) {
        final double bubbleLeft = PuckConstants.bubbleMargin + pos.dx;
        final double bubbleTop = PuckConstants.bubbleMargin + pos.dy;
        final double bubbleCentreX = bubbleLeft + PuckConstants.bubbleSize / 2;

        final double width = PuckFormat.clamp(
          canvas.width - PuckConstants.screenMargin * 2,
          120,
          PuckConstants.cardMaxWidth,
        );

        double left = bubbleCentreX - width / 2;
        left = PuckFormat.clamp(
          left,
          PuckConstants.screenMargin,
          canvas.width - PuckConstants.screenMargin - width,
        );

        // Rare: the bubble parked near the top. Put the card below it
        // instead of off-screen.
        final bool placeBelow = bubbleTop < 240;

        return Positioned(
          left: left,
          width: width,
          top: placeBelow
              ? bubbleTop + PuckConstants.bubbleSize + 16
              : null,
          bottom: placeBelow
              ? null
              : canvas.height - bubbleTop + 16,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: PuckConstants.cardMaxWidth),
            child: AnimatedSwitcher(
              duration: PuckConstants.cardOut,
              switchInCurve: PuckConstants.moveCurve,
              switchOutCurve: PuckConstants.moveCurve,
              transitionBuilder:
                  (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: child,
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
        final String? joke = c.joke;
        return joke == null
            ? _empty
            : JokeCard(key: const ValueKey<String>('joke'), text: joke);
      case PanelKind.answer:
        // Answers render inside the IntentBar, which reads
        // `controller.intent` directly; the controller never assigns this
        // panel. Returning the empty slot keeps the switch exhaustive
        // without inventing a second renderer for the same content.
        return _empty;
      case PanelKind.none:
        return _empty;
    }
  }
}

/// The one affordance Puck allows itself: a quiet way into settings.
class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 6),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).pushNamed('/settings'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Text(
              'Settings',
              textAlign: TextAlign.center,
              style: PuckType.label.copyWith(color: PuckPalette.textMuted),
            ),
          ),
        ),
      ),
    );
  }
}
