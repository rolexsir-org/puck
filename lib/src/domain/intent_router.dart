import 'dart:async';

import 'package:puck/src/data/llm/llm_provider.dart';
import 'package:puck/src/data/llm/local_fallback_provider.dart';
import 'package:puck/src/data/llm/prompt.dart';
import 'package:puck/src/data/models/context.dart';

/// Decides where a query goes: the device, or the cloud.
///
/// Order matters for perceived speed. Deterministic intents (coin, dice,
/// sums) resolve in microseconds and never touch the network -- an LLM
/// round-trip for "flip a coin" is both slower and worse, since a model will
/// happily answer "Heads" with a bias it cannot perceive.
///
/// With no key configured we skip the network entirely rather than showing a
/// spinner that is guaranteed to fail.
class IntentRouter {
  IntentRouter({required LlmProvider llm, required LocalIntentResolver local})
      : _llm = llm,
        _local = local;

  final LlmProvider _llm;
  final LocalIntentResolver _local;

  /// The single-tap rewrite is optional polish, so it gets a hard deadline.
  /// The deterministic line is already on screen; a slow model must never be
  /// allowed to delay or degrade it.
  static const Duration polishTimeout = Duration(milliseconds: 900);

  bool get isOnlineCapable => _llm.isConfigured;

  // -- INTENT (swipe up) ----------------------------------------------------

  Stream<String> resolve(String query) =>
      resolveRequest(LlmRequest(mode: PuckMode.intent, query: query));

  /// The streaming path. CONTEXT goes through the bounded helper below,
  /// because it is an upgrade to something already on screen rather than the
  /// answer itself.
  Stream<String> resolveRequest(LlmRequest request) async* {
    if (request.mode == PuckMode.intent) {
      final String? instant = _local.tryResolve(request.query);
      if (instant != null) {
        yield instant;
        return;
      }
    }

    if (!_llm.isConfigured) {
      yield _local.offline();
      return;
    }

    try {
      yield* _llm.complete(request);
    } on LlmException catch (e) {
      // Optional feature, one honest line. A 401 reads as offline to the
      // person holding the phone; the fix is the same either way.
      yield e.retryable ? LocalIntentResolver.offlineLine : e.message;
    } catch (_) {
      yield LocalIntentResolver.offlineLine;
    }
  }

  // -- CONTEXT (single tap, hybrid) -----------------------------------------

  /// Asks the model to sharpen a line the local ranker already produced.
  ///
  /// Returns null on anything other than a clean, in-budget answer -- timeout,
  /// transport error, empty stream, or output that fails
  /// [PuckPrompt.isAcceptable]. The caller keeps showing the deterministic
  /// line, so the network can only ever improve the card, never break it.
  Future<String?> sharpenContext({
    required ContextSnapshot snapshot,
    required ContextItem localLine,
  }) async {
    if (!_llm.isConfigured) return null;

    final LlmRequest request = LlmRequest(
      mode: PuckMode.context,
      contextEnvelope:
          PuckPrompt.buildEnvelope(snapshot: snapshot, localLine: localLine),
    );

    return _collect(request, polishTimeout);
  }

  /// Drains a stream under a deadline, cancelling the underlying
  /// subscription if the deadline wins.
  ///
  /// The explicit `cancel()` matters: a bare `Future.timeout` would walk away
  /// from the stream and leave the HTTP subscription open until it happened
  /// to finish, leaking a socket on every slow tap.
  Future<String?> _collect(LlmRequest request, Duration timeout) async {
    final StringBuffer buffer = StringBuffer();
    final Completer<String> done = Completer<String>();

    late final StreamSubscription<String> subscription;
    subscription = _llm.complete(request).listen(
      buffer.write,
      onError: (Object _) {
        if (!done.isCompleted) done.complete('');
      },
      onDone: () {
        if (!done.isCompleted) done.complete(buffer.toString());
      },
      cancelOnError: true,
    );

    final String text =
        await done.future.timeout(timeout, onTimeout: () => '');
    await subscription.cancel();

    if (!PuckPrompt.isAcceptable(request.mode, text)) return null;
    return text.trim();
  }
}
