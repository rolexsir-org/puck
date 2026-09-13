import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:puck/src/core/constants.dart';
import 'package:puck/src/core/format.dart';
import 'package:puck/src/core/haptics.dart';
import 'package:puck/src/data/models/context.dart';
import 'package:puck/src/data/repositories/context_repository.dart';
import 'package:puck/src/data/repositories/joke_repository.dart';
import 'package:puck/src/data/repositories/settings_repository.dart';
import 'package:puck/src/data/services/location_service.dart';
import 'package:puck/src/data/services/messaging_service.dart';
import 'package:puck/src/data/services/torch_service.dart';
import 'package:puck/src/domain/context_ranker.dart';
import 'package:puck/src/domain/intent_router.dart';
import 'package:puck/src/features/puck/puck_gesture_recognizer.dart';
import 'package:puck/src/features/puck/spring_offset.dart';
import 'package:puck/src/providers.dart';

/// Which transient surface, if any, is currently on screen.
///
/// Only one at a time by construction -- that constraint is the design.
enum PanelKind { none, context, joke, answer }

class IntentView {
  const IntentView({
    required this.query,
    required this.answer,
    required this.streaming,
    this.failed = false,
  });

  final String query;
  final String answer;
  final bool streaming;
  final bool failed;

  IntentView copyWith({
    String? query,
    String? answer,
    bool? streaming,
    bool? failed,
  }) =>
      IntentView(
        query: query ?? this.query,
        answer: answer ?? this.answer,
        streaming: streaming ?? this.streaming,
        failed: failed ?? this.failed,
      );
}

/// The SOS sheet has exactly two states: the ring is counting down, or the
/// countdown completed and the sheet is a status light.
enum SosPhase { counting, active }

class SosView {
  const SosView({
    required this.phase,
    required this.status,
    required this.torchOn,
    required this.secondsLeft,
    this.body,
    this.position,
    this.hasContact = false,
  });

  final SosPhase phase;
  final String status;
  final bool torchOn;

  /// Whole seconds left in the countdown. Drives the big number.
  final int secondsLeft;

  final String? body;
  final Position? position;
  final bool hasContact;

  SosView copyWith({
    SosPhase? phase,
    String? status,
    bool? torchOn,
    int? secondsLeft,
    String? body,
    Position? position,
    bool? hasContact,
  }) =>
      SosView(
        phase: phase ?? this.phase,
        status: status ?? this.status,
        torchOn: torchOn ?? this.torchOn,
        secondsLeft: secondsLeft ?? this.secondsLeft,
        body: body ?? this.body,
        position: position ?? this.position,
        hasContact: hasContact ?? this.hasContact,
      );
}

/// Wires the four gestures to the four behaviours, and owns every timer.
///
/// Deliberately a `ChangeNotifier` rather than an immutable state class: the
/// bubble position updates at 60fps during a drag, and rebuilding the tree
/// from a copied state object on every frame is wasted work for a surface
/// this small. Panels *are* immutable; only the container is observable.
class PuckController extends ChangeNotifier {
  PuckController(this._ref);

  final Ref _ref;

  // -- Geometry -------------------------------------------------------------

  Size _canvas = Size.zero;
  bool _dragging = false;
  SpringOffset2D? _spring;

  /// Top-left of the bubble *within the padded area*. Margins are added by
  /// the view at paint time, so this stays in [0, max].
  final ValueNotifier<Offset> bubblePosition =
      ValueNotifier<Offset>(Offset.zero);

  double get _maxX => _canvas.width <= 0
      ? 0
      : PuckFormat.clamp(
          _canvas.width - PuckConstants.bubbleSize - PuckConstants.bubbleMargin * 2,
          0,
          double.infinity,
        );

  double get _maxY => _canvas.height <= 0
      ? 0
      : PuckFormat.clamp(
          _canvas.height - PuckConstants.bubbleSize - PuckConstants.bubbleMargin * 2,
          0,
          double.infinity,
        );

  void attach(TickerProvider vsync) {
    _spring?.dispose();
    _spring = SpringOffset2D(
      vsync: vsync,
      onUpdate: () => bubblePosition.value = _spring!.value,
      spring: PuckConstants.snapSpring,
    );
    if (_canvas != Size.zero) _spring!.jumpTo(bubblePosition.value);
  }

  void detach() {
    _spring?.dispose();
    _spring = null;
  }

  /// Called from LayoutBuilder. First layout parks the bubble at the
  /// bottom-right edge -- its home, and the first thing the eye should find.
  /// Later layouts re-clamp into view.
  void updateCanvas(Size size) {
    if (_canvas == size) return;
    final bool firstLayout = _canvas == Size.zero;
    _canvas = size;

    if (firstLayout) {
      // Safe to set synchronously: the bubble's listener does not exist until
      // this frame's tree is built, so nothing can be marked dirty mid-build.
      final Offset home = Offset(_maxX, _maxY);
      bubblePosition.value = home;
      _spring?.jumpTo(home);
      return;
    }

    // Rotation / split-view: we are inside the build phase, so notifying
    // listeners now would be a markNeedsBuild-during-build. Re-clamp after
    // the frame lands instead -- one frame of slack is invisible here.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!hasListeners) return;
      final Offset clamped = Offset(
        PuckFormat.clamp(bubblePosition.value.dx, 0, _maxX),
        PuckFormat.clamp(bubblePosition.value.dy, 0, _maxY),
      );
      if (clamped == bubblePosition.value) return;
      bubblePosition.value = clamped;
      _spring?.jumpTo(clamped);
    });
  }

  // -- Drag -----------------------------------------------------------------

  void onDragStart(Offset globalPosition) {
    // Overlays own the surface while they are open; a new press on the
    // bubble's old spot must not start a drag underneath them.
    if (_intentBarOpen || _sos != null) return;
    _dragging = true;
    _spring?.jumpTo(bubblePosition.value);
    _cancelDismiss();
  }

  void onDragUpdate(Offset delta, Offset globalPosition) {
    if (!_dragging) return;
    final Offset next = bubblePosition.value + delta;
    bubblePosition.value = Offset(
      PuckFormat.clamp(next.dx, 0, _maxX),
      PuckFormat.clamp(next.dy, 0, _maxY),
    );
  }

  void onDragEnd(Velocity velocity) {
    if (!_dragging) return;
    _dragging = false;
    _snap(velocity);
  }

  /// Snap to whichever edge the fling was heading for.
  ///
  /// The velocity projection is what makes this feel physical: flick the
  /// bubble leftward and it commits to the left edge even if it was released
  /// on the right half of the screen.
  void _snap(Velocity velocity) {
    final Offset current = bubblePosition.value;
    final double projectedX = current.dx + velocity.pixelsPerSecond.dx * 0.08;
    final double targetX = projectedX < _maxX / 2 ? 0.0 : _maxX;
    final double projectedY = current.dy + velocity.pixelsPerSecond.dy * 0.06;
    final double targetY = PuckFormat.clamp(projectedY, 0, _maxY);

    _spring?.jumpTo(current);
    _spring?.animateTo(Offset(targetX, targetY), velocity: velocity);
    unawaited(_read<HapticsService>(hapticsProvider).tick());
  }

  /// The finger came off the bubble. If SOS is counting down, that lift is
  /// the pocket saying "this was not deliberate" -- disarm, and remember it.
  void onBubbleRelease() {
    final SosView? sos = _sos;
    if (sos == null || sos.phase != SosPhase.counting) return;
    unawaited(_ref.read(settingsProvider).incrementReleaseCancels());
    unawaited(_read<HapticsService>(hapticsProvider).sosCancel());
    unawaited(_closeSos());
  }

  // -- Panels ---------------------------------------------------------------

  PanelKind _panel = PanelKind.none;
  ContextItem? _contextItem;
  String? _joke;
  IntentView? _intent;
  SosView? _sos;
  bool _intentBarOpen = false;

  PanelKind get panel => _panel;
  ContextItem? get contextItem => _contextItem;
  String? get joke => _joke;
  IntentView? get intent => _intent;
  SosView? get sos => _sos;
  bool get intentBarOpen => _intentBarOpen;
  bool get isSosActive => _sos != null;

  Timer? _dismissTimer;
  Timer? _sosRunawayTimer;
  Timer? _sosCountdownTimer;
  StreamSubscription<String>? _intentSub;

  DateTime? _dismissDeadline;

  void _cancelDismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _dismissDeadline = null;
  }

  /// Auto-dismissal always targets whatever is on screen right now.
  void _scheduleDismiss(Duration delay) {
    _cancelDismiss();
    _dismissDeadline = DateTime.now().add(delay);
    _dismissTimer = Timer(delay, () {
      _dismissTimer = null;
      _dismissDeadline = null;
      if (_intentBarOpen) {
        closeIntentBar();
      } else {
        _panel = PanelKind.none;
        _contextItem = null;
        _joke = null;
        _intent = null;
        notifyListeners();
      }
    });
  }

  /// Guarantees the card stays up long enough to read an upgraded line.
  void _ensureRemainingDismiss(Duration minimum) {
    final DateTime? deadline = _dismissDeadline;
    if (deadline == null) return;
    if (deadline.difference(DateTime.now()) >= minimum) return;
    _scheduleDismiss(minimum);
  }

  // -- Gesture dispatch -----------------------------------------------------

  void handleGesture(PuckGestureKind kind) {
    // Overlays own the surface while they are open. The one exception is the
    // pointer that armed SOS: its lift is the pocket-release signal, which is
    // handled in [onBubbleRelease], not here.
    if (_intentBarOpen || _sos != null) return;
    switch (kind) {
      case PuckGestureKind.tap:
        unawaited(_showContext());
      case PuckGestureKind.doubleTap:
        _showJoke();
      case PuckGestureKind.longPress:
        unawaited(_armSos());
      case PuckGestureKind.swipeUp:
        openIntentBar();
    }
  }

  /// Behaviour 1 -- the one thing worth knowing.
  ///
  /// Two-phase on purpose, and the phases are ordered by what the user is
  /// promised: the first paint is the *guaranteed* answer -- the time and a
  /// line to go with it -- computed with zero awaits, well inside the 100ms
  /// budget. The snapshot then either upgrades the card with something more
  /// urgent or leaves the time alone. The panel key does not change, so the
  /// upgrade is a text update in place, not a re-animation.
  Future<void> _showContext() async {
    unawaited(_read<HapticsService>(hapticsProvider).light());

    _panel = PanelKind.context;
    _joke = null;
    _intent = null;
    _contextItem = ContextRanker.timeOfDay(DateTime.now());
    _scheduleDismiss(PuckConstants.contextDismiss);
    notifyListeners();

    final ContextSnapshot snapshot =
        await _read<ContextRepository>(contextRepositoryProvider).snapshot();
    if (!hasListeners || _panel != PanelKind.context) return;

    // Phase 2: the deterministic line. Offline, instant, always available.
    final ContextItem ranked = ContextRanker.rank(snapshot);
    _contextItem = ranked;
    _panel = PanelKind.context;
    notifyListeners();

    // Phase 3: optional polish. The model is asked to *sharpen* the line the
    // ranker already chose -- it can compress a fact, never invent one. Any
    // failure (timeout, transport, off-budget output) returns null and the
    // deterministic line simply stays on screen.
    final String? sharpened = await _read<IntentRouter>(intentRouterProvider)
        .sharpenContext(snapshot: snapshot, localLine: ranked);
    if (sharpened == null || !hasListeners || _panel != PanelKind.context) {
      return;
    }

    _contextItem = ContextItem(
      kind: ranked.kind,
      label: ranked.label,
      headline: sharpened,
      detail: ranked.detail,
    );
    _panel = PanelKind.context;
    _ensureRemainingDismiss(PuckConstants.minReadTime);
    notifyListeners();
  }

  /// Behaviour 2 -- the double-tap. The shuffle bag is the whole feature:
  /// instant, offline, and it never repeats until it has to.
  Future<void> _showJoke() async {
    unawaited(_read<HapticsService>(hapticsProvider).light());

    final JokeRepository repo = _read<JokeRepository>(jokeRepositoryProvider);
    await repo.load();
    if (!hasListeners) return;

    final String? line = repo.next();
    if (line == null) return;

    _joke = line;
    _contextItem = null;
    _intent = null;
    _panel = PanelKind.joke;
    _scheduleDismiss(PuckConstants.jokeDismiss);
    notifyListeners();
  }

  /// Behaviour 3 -- SOS.
  ///
  /// A three-second hold arms it; the sheet counts down for three more. The
  /// countdown is the pocket filter: a phone jostled in a bag lifts the
  /// finger long before three seconds are up, and the lift disarms
  /// everything. Holding through the countdown is a deliberate act.
  ///
  /// GPS acquisition starts the moment the sheet appears, in parallel with
  /// the ring -- by the time the countdown ends, the fix has usually landed.
  Future<void> _armSos() async {
    if (_sos != null) return; // already armed

    final SettingsRepository settings = _read<SettingsRepository>(settingsProvider);
    final HapticsService haptics = _read<HapticsService>(hapticsProvider);

    unawaited(haptics.heavy());
    unawaited(haptics.sosAlarm());

    _sos = SosView(
      phase: SosPhase.counting,
      status: 'Getting your location',
      torchOn: false,
      secondsLeft: PuckConstants.sosCountdown.inSeconds,
      body: null,
      hasContact: settings.hasEmergencyContact,
    );
    _panel = PanelKind.none;
    _intentBarOpen = false;
    _cancelDismiss();
    notifyListeners();

    // A pocket-armed SOS must not cook the phone or flatten the battery.
    _sosRunawayTimer?.cancel();
    _sosRunawayTimer = Timer(PuckConstants.sosRunawayTimeout, () {
      _sosRunawayTimer = null;
      if (_sos == null) return;
      unawaited(_stopTorch());
      _sos = _sos!.copyWith(torchOn: false);
      notifyListeners();
    });

    // The countdown: one tick per second, then fire.
    _sosCountdownTimer?.cancel();
    _sosCountdownTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      final SosView? sos = _sos;
      if (sos == null || sos.phase != SosPhase.counting) {
        t.cancel();
        return;
      }
      final int left = sos.secondsLeft - 1;
      if (left <= 0) {
        t.cancel();
        _fireSos();
        return;
      }
      _sos = sos.copyWith(secondsLeft: left);
      unawaited(_read<HapticsService>(hapticsProvider).tick());
      notifyListeners();
    });

    final Position? position =
        await _read<LocationService>(locationServiceProvider).current();
    if (!hasListeners || _sos == null) return;

    final DateTime now = DateTime.now();
    final String body = MessagingService.buildSosBody(
      latitude: position?.latitude,
      longitude: position?.longitude,
      accuracy: position?.accuracy,
      at: now,
    );

    _sos = _sos!.copyWith(
      status: position == null
          ? 'No GPS fix yet -- the message will say so'
          : 'Location found',
      body: body,
      position: position,
    );
    notifyListeners();
  }

  /// The countdown ran out with the finger still down. Torch, message,
  /// status light.
  Future<void> _fireSos() async {
    final SosView? sos = _sos;
    if (sos == null || sos.phase != SosPhase.counting) return;

    _sosCountdownTimer?.cancel();
    _sosCountdownTimer = null;

    final TorchService torch = _read<TorchService>(torchServiceProvider);
    unawaited(torch.startSos());

    _sos = sos.copyWith(
      phase: SosPhase.active,
      torchOn: true,
      status: sos.position == null
          ? 'Finding your location'
          : 'Location found',
    );
    notifyListeners();

    if (sos.hasContact && sos.body != null) {
      await _read<MessagingService>(messagingServiceProvider).openSms(
        recipient: _read<SettingsRepository>(settingsProvider).contactPhone,
        body: sos.body!,
      );
    }
  }

  /// "I'm safe." Both exits -- the button and the lifted finger -- land here.
  Future<void> cancelSos() async {
    unawaited(_read<HapticsService>(hapticsProvider).sosCancel());
    await _closeSos();
  }

  Future<void> _closeSos() async {
    _sosRunawayTimer?.cancel();
    _sosRunawayTimer = null;
    _sosCountdownTimer?.cancel();
    _sosCountdownTimer = null;
    _sos = null;
    await _stopTorch();
    notifyListeners();
  }

  Future<void> _stopTorch() async {
    final TorchService torch = _read<TorchService>(torchServiceProvider);
    await torch.stop();
  }

  // -- Behaviour 4 -- universal intent --------------------------------------

  void openIntentBar() {
    _intentBarOpen = true;
    _intent = null;
    _contextItem = null;
    _joke = null;
    _panel = PanelKind.none;
    _cancelDismiss();
    unawaited(_read<HapticsService>(hapticsProvider).tick());
    notifyListeners();
  }

  void closeIntentBar() {
    _intentSub?.cancel();
    _intentSub = null;
    _intentBarOpen = false;
    _intent = null;
    _cancelDismiss();
    notifyListeners();
  }

  void submitQuery(String raw) {
    final String query = raw.trim();
    if (query.isEmpty) return;

    unawaited(_read<HapticsService>(hapticsProvider).tick());

    _intent = IntentView(query: query, answer: '', streaming: true);
    _cancelDismiss();
    notifyListeners();

    _intentSub?.cancel();
    _intentSub = _read<IntentRouter>(intentRouterProvider)
        .resolve(query)
        .listen(
      (String token) {
        if (_intent == null) return;
        _intent = _intent!.copyWith(answer: _intent!.answer + token);
        notifyListeners();
      },
      onError: (Object error) {
        if (_intent == null) return;
        _intent = _intent!.copyWith(streaming: false, failed: true);
        _scheduleDismiss(const Duration(seconds: 6));
        notifyListeners();
      },
      onDone: () {
        if (_intent == null) return;
        _intent = _intent!.copyWith(streaming: false);
        notifyListeners();
        _scheduleDismiss(PuckConstants.answerDismiss);
      },
    );
  }

  /// Bails out of an in-flight generation without closing the bar.
  void cancelQuery() {
    _intentSub?.cancel();
    _intentSub = null;
    _intent = null;
    notifyListeners();
  }

  // -- Internals ------------------------------------------------------------

  T _read<T>(ProviderBase<T> provider) => _ref.read<T>(provider);

  @override
  void dispose() {
    _intentSub?.cancel();
    _dismissTimer?.cancel();
    _sosRunawayTimer?.cancel();
    _sosCountdownTimer?.cancel();
    _spring?.dispose();
    bubblePosition.dispose();
    super.dispose();
  }
}

/// Provided from the screen that owns the surface, so `dispose` runs when the
/// screen is popped and every timer dies with it.
final ChangeNotifierProvider<PuckController> puckControllerProvider =
    ChangeNotifierProvider<PuckController>(PuckController.new);
