import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:puck/src/core/constants.dart';

/// The one gesture that Puck understands: a press.
///
/// Flutter's stock recognisers could not do this cleanly. A `GestureDetector`
/// with tap + doubleTap + longPress + verticalDrag puts four recognisers in the
/// gesture arena, and the vertical-drag recogniser wins the moment the finger
/// clears touch slop -- which kills swipe-up, because a swipe-up *is* vertical
/// travel. Stacking `Listener` on top means reimplementing slop, timing and
/// velocity anyway.
///
/// So: one recogniser, one pointer, a small state machine. It accepts the
/// arena immediately (Puck owns anything that starts on the bubble) and then
/// classifies the press by distance, time and velocity:
///
///   travel up > 56px, vertical-dominant  -> swipe up   (fires mid-gesture, so
///                                                        it feels instant)
///   travel > 18px in any direction       -> drag
///   held 3s without leaving the slop     -> long press
///   released inside slop, < 260ms        -> tap, unless a second tap lands
///                                           within 260ms -> double tap
///
/// The tap is intentionally resolved on a 260ms delay rather than immediately:
/// firing on pointer-up would flash the context card before every joke.
class PuckGestureRecognizer extends OneSequenceGestureRecognizer {
  PuckGestureRecognizer({
    required this.onGesture,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragStart,
    this.onPressStart,
    this.onPressCancel,
    this.longPressDuration = PuckConstants.longPressDuration,
    this.doubleTapTimeout = PuckConstants.doubleTapTimeout,
    this.swipeUpDistance = PuckConstants.swipeUpDistance,
  });

  final void Function(PuckGestureKind kind) onGesture;
  final void Function(Offset globalPosition) onDragStart;
  final void Function(Offset delta, Offset globalPosition) onDragUpdate;
  final void Function(Velocity velocity) onDragEnd;

  /// Fired on pointer down / on any resolution, so the bubble can run its
  /// press animation and its 3-second hold ring.
  final VoidCallback? onPressStart;
  final VoidCallback? onPressCancel;

  final Duration longPressDuration;
  final Duration doubleTapTimeout;
  final double swipeUpDistance;

  static const double _touchSlop = PuckConstants.touchSlop;
  static const double _axisRatio = PuckConstants.swipeUpAxisRatio;

  int? _pointer;
  Offset? _origin;
  Offset? _lastPosition;
  _Mode _mode = _Mode.none;

  Timer? _longPressTimer;
  Timer? _doubleTapTimer;
  DateTime? _lastTapAt;

  final VelocityTracker _tracker = VelocityTracker.withKind(PointerDeviceKind.touch);

  @override
  String get debugDescription => 'puck';

  @override
  void addAllowedPointer(PointerDownEvent event) {
    // Single-pointer only: a second finger is ignored, not tracked.
    if (_pointer != null) return;

    _pointer = event.pointer;
    _origin = event.position;
    _lastPosition = event.position;
    _mode = _Mode.none;

    startTrackingPointer(event.pointer);
    // Claim the arena immediately -- nothing above us should compete.
    resolve(GestureDisposition.accepted);

    _longPressTimer?.cancel();
    _longPressTimer = Timer(longPressDuration, _fireLongPress);
    onPressStart?.call();
  }

  @override
  void handleEvent(PointerEvent event) {
    assert(_pointer == null || _pointer == event.pointer);

    if (event is PointerMoveEvent) {
      _handleMove(event);
      return;
    }

    if (event is PointerUpEvent) {
      _handleUp(event);
      return;
    }

    if (event is PointerCancelEvent) {
      _cancelLongPress();
      if (_mode == _Mode.drag) onDragEnd(Velocity.zero);
      onPressCancel?.call();
      _reset();
      stopTrackingPointer(event.pointer);
    }
  }

  void _handleMove(PointerMoveEvent event) {
    _tracker.addPosition(event.timeStamp, event.position);

    final Offset? origin = _origin;
    if (origin == null) return;

    final Offset delta = event.position - origin;
    final double dy = delta.dy; // negative is upward

    if (_mode == _Mode.none) {
      // Swipe up wins over drag as soon as it is unambiguous, so the intent
      // bar is already opening while the finger is still moving.
      if (-dy >= swipeUpDistance && -dy >= delta.dx.abs() * _axisRatio) {
        _cancelLongPress();
        _mode = _Mode.consumed;
        onPressCancel?.call();
        onGesture(PuckGestureKind.swipeUp);
        _reset();
        stopTrackingPointer(event.pointer);
        return;
      }

      if (delta.distance > _touchSlop) {
        _cancelLongPress();
        _mode = _Mode.drag;
        _lastPosition = event.position;
        onPressCancel?.call();
        onDragStart(event.position);
      }
    }

    if (_mode == _Mode.drag) {
      final Offset? last = _lastPosition;
      if (last != null) onDragUpdate(event.position - last, event.position);
      _lastPosition = event.position;
    }
  }

  void _handleUp(PointerUpEvent event) {
    _tracker.addPosition(event.timeStamp, event.position);
    _cancelLongPress();

    if (_mode == _Mode.drag) {
      onDragEnd(_tracker.getVelocity());
      onPressCancel?.call();
      _reset();
      stopTrackingPointer(event.pointer);
      return;
    }

    if (_mode == _Mode.none) {
      _resolveTap();
    } else {
      onPressCancel?.call();
    }

    _reset();
    stopTrackingPointer(event.pointer);
  }

  void _resolveTap() {
    final DateTime now = DateTime.now();
    final DateTime? previous = _lastTapAt;

    _doubleTapTimer?.cancel();

    if (previous != null && now.difference(previous) <= doubleTapTimeout) {
      _lastTapAt = null;
      _doubleTapTimer = null;
      onPressCancel?.call();
      onGesture(PuckGestureKind.doubleTap);
      return;
    }

    _lastTapAt = now;
    _doubleTapTimer = Timer(doubleTapTimeout, () {
      _doubleTapTimer = null;
      onPressCancel?.call();
      onGesture(PuckGestureKind.tap);
    });
  }

  void _fireLongPress() {
    _longPressTimer = null;
    if (_mode != _Mode.none) return;
    _mode = _Mode.consumed;
    onPressCancel?.call();
    onGesture(PuckGestureKind.longPress);
  }

  void _cancelLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  void _reset() {
    _mode = _Mode.none;
    _pointer = null;
    _origin = null;
    _lastPosition = null;
  }

  @override
  void acceptGesture(int pointer) {
    // Nothing to do: we accept unconditionally on pointer down.
  }

  @override
  void rejectGesture(int pointer) {
    _cancelLongPress();
    onPressCancel?.call();
    _reset();
    stopTrackingPointer(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _cancelLongPress();
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _doubleTapTimer?.cancel();
    _doubleTapTimer = null;
    super.dispose();
  }
}

enum _Mode { none, drag, consumed }

enum PuckGestureKind { tap, doubleTap, longPress, swipeUp }
