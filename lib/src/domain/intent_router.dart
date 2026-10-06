import 'dart:async';

import 'package:puck/src/data/llm/llm_provider.dart';
import 'package:puck/src/data/llm/local_fallback_provider.dart';
import 'package:puck/src/data/llm/prompt.dart';
import 'package:puck/src/data/models/context.dart';
import 'package:puck/src/domain/safety.dart';

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
  IntentRouter({
    required LlmProvider llm,
    required LocalIntentResolver local,
    DateTime Function()? now,
  })  : _llm = llm,
        _local = local,
        _now = now ?? DateTime.now;

  final LlmProvider _llm;
  final LocalIntentResolver _local;

  /// Injected so the cost policy below is testable without sleeping.
  final DateTime Function() _now;

  /// The single-tap rewrite is optional polish, so it gets a hard deadline.
  /// The deterministic line is already on screen; a slow model must never be
  /// allowed to delay or degrade it.
  static const Duration polishTimeout = Duration(milliseconds: 900);

  // -- Cost policy -----------------------------------------------------------
  //
  // Every polished card is a paid request. The rules below are what keeps the
  // tap gesture from being the most expensive thing in the app: a tap is the
  // one gesture people make dozens of times a day, and none of those taps
  // needs a model. They are all local decisions, so they are all here rather
  // than in the (not yet built) proxy.

  /// Shortest local line worth polishing, in characters.
  ///
  /// The model's job is to sharpen a sentence that sprawls. Below this length
  /// the deterministic line is already tighter than the model's own budget, so
  /// the request can only return it unchanged or make it worse -- and it would
  /// be paid for either way.
  static const int polishSkipBelowChars = 30;

  /// At most one polish request per this interval, however many taps happen.
  static const Duration polishMinInterval = Duration(seconds: 20);

  /// A polish of the same local line inside this window is reused.
  static const Duration polishCacheTtl = Duration(minutes: 10);

  static const int _polishCacheLimit = 24;

  final Map<String, _Polished> _polishCache = <String, _Polished>{};
  DateTime? _lastPolish;

  /// How much of a streaming answer is held back before any of it is shown.
  /// Long enough to recognise a filler opener, short enough that the first
  /// words are not visibly late.
  static const int leadWindow = 24;

  bool get isOnlineCapable => _llm.isConfigured;

  // -- INTENT (swipe up) ----------------------------------------------------

  Stream<String> resolve(String query) =>
      resolveRequest(LlmRequest(mode: PuckMode.intent, query: query));

  /// The streaming path. CONTEXT goes through the bounded helper below,
  /// because it is an upgrade to something already on screen rather than the
  /// answer itself.
  Stream<String> resolveRequest(LlmRequest request) async* {
    if (request.mode == PuckMode.intent) {
      // Before the resolver, before the network: a crisis question is answered
      // here, locally, with one fixed line. See PuckSafety -- this is the one
      // category where the model's answer being merely *plausible* is not an
      // acceptable failure mode, and where the question must not leave the
      // phone at all.
      if (PuckSafety.isCrisis(request.query)) {
        yield _local.safety();
        return;
      }

      final String? instant = _local.tryResolve(request.query);
      if (instant != null) {
        yield instant;
        return;
      }

      // INTENT is the only path where model text is the whole answer, so it
      // is the only one that needs a guard on the way out. The README used to
      // claim "every output passes a client-side validator" while this path
      // streamed raw tokens straight to the card; now the claim is true.
      if (!_llm.isConfigured) {
        yield _local.offline();
        return;
      }
      yield* _guardedIntent(request);
      return;
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
      yield _failureLine(e);
    } catch (_) {
      yield _local.offline();
    }
  }

  /// Streams an answer while keeping the promise that what reaches the card
  /// has passed [PuckPrompt.isAcceptable].
  ///
  /// Three rules, each one a failure that was actually observed:
  ///
  ///   1. The first [leadWindow] characters are held back. A filler opener
  ///      ("Sure, ...") is not recoverable once it is on screen, and the
  ///      stream is the only place it can still be stopped.
  ///   2. Emission stops at the word budget. `max_completion_tokens` bounds
  ///      the API call, but the client cannot see a provider-side change to
  ///      that parameter, so it enforces its own ceiling rather than trusting
  ///      one. Stopping at a word boundary leaves a short answer rather than a
  ///      severed sentence, and short is what the card is for.
  ///   3. A stream that ends before the lead is released is validated whole.
  ///      Empty, over-length or filler output becomes the honest offline line.
  ///
  /// A failure mid-stream after text has been shown ends the answer quietly:
  /// appending an error line to a half-sentence reads as a malfunction.
  Stream<String> _guardedIntent(LlmRequest request) async* {
    final int wordBudget = PuckPrompt.wordLimitFor(PuckMode.intent) +
        PuckPrompt.validationTolerance;

    final StringBuffer held = StringBuffer();
    int words = 0;
    bool released = false;

    try {
      await for (final String token in _llm.complete(request)) {
        if (!released) {
          held.write(token);
          final String buffer = held.toString();
          // Wait until there is something to judge: either the text has
          // outgrown the lead window, or a word has ended inside it.
          if (buffer.length < leadWindow &&
              !buffer.contains(RegExp(r'\s'))) {
            continue;
          }
          if (buffer.length > PuckPrompt.maxAnswerChars ||
              PuckPrompt.hasBannedOpening(buffer)) {
            yield _local.offline();
            return;
          }
          released = true;
          words = _wordCount(buffer);
          yield buffer;
          continue;
        }

        final int added = _wordCount(token);
        if (words + added > wordBudget) return; // budget spent, end cleanly
        words += added;
        yield token;
      }
    } on LlmException catch (e) {
      if (released) return;
      yield _failureLine(e);
      return;
    } catch (_) {
      if (released) return;
      yield _local.offline();
      return;
    }

    if (released) return;

    final String whole = held.toString().trim();
    if (whole.isEmpty || !PuckPrompt.isAcceptable(PuckMode.intent, whole)) {
      yield _local.offline();
      return;
    }
    yield whole;
  }

  /// What the person sees when the cloud answer failed.
  ///
  /// A rejected key is the one failure with an action attached to it, and it is
  /// the user's own doing, so it gets its own localized line. Everything else
  /// -- no network, a 500, a timeout -- is the offline line, because from the
  /// phone in someone's hand those are the same event.
  String _failureLine(LlmException e) {
    if (e.statusCode == 401 || e.statusCode == 403) {
      return _local.keyRejected();
    }
    return _local.offline();
  }

  static int _wordCount(String text) => text
      .split(RegExp(r'\s+'))
      .where((String w) => w.trim().isNotEmpty)
      .length;

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

    final String key = localLine.headline.trim();
    if (key.length < polishSkipBelowChars) return null;

    final DateTime now = _now();
    final _Polished? cached = _polishCache[key];
    if (cached != null && now.difference(cached.at) < polishCacheTtl) {
      // Same line, recently polished: the model's answer cannot have changed
      // in ten minutes, and the tap should be instant.
      return cached.text;
    }

    final DateTime? last = _lastPolish;
    if (last != null && now.difference(last) < polishMinInterval) return null;

    final LlmRequest request = LlmRequest(
      mode: PuckMode.context,
      contextEnvelope:
          PuckPrompt.buildEnvelope(snapshot: snapshot, localLine: localLine),
    );

    final String? text = await _collect(request, polishTimeout);
    // Stamped after the call, not before: the interval is meant to bound how
    // often a *slow* network is asked, and stamping first would let two taps a
    // millisecond apart both through.
    _lastPolish = _now();
    if (text != null) _remember(key, text, _now());
    return text;
  }

  void _remember(String key, String text, DateTime at) {
    _polishCache.remove(key);
    _polishCache[key] = _Polished(text, at);
    while (_polishCache.length > _polishCacheLimit) {
      _polishCache.remove(_polishCache.keys.first);
    }
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

class _Polished {
  const _Polished(this.text, this.at);

  final String text;
  final DateTime at;
}
