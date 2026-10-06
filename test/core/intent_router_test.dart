import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:puck/src/data/llm/llm_provider.dart';
import 'package:puck/src/data/llm/local_fallback_provider.dart';
import 'package:puck/src/data/llm/prompt.dart';
import 'package:puck/src/domain/intent_router.dart';

/// A scripted provider. Tokens arrive one at a time, exactly as SSE delivers
/// them, so the guard is exercised on partial text rather than on a finished
/// string.
class _ScriptedLlm implements LlmProvider {
  _ScriptedLlm(this.tokens, {this.failure});

  final List<String> tokens;
  final Object? failure;

  @override
  String get id => 'scripted';

  @override
  bool get isConfigured => true;

  @override
  Stream<String> complete(LlmRequest request) async* {
    for (final String token in tokens) {
      yield token;
    }
    if (failure != null) throw failure!;
  }
}

void main() {
  IntentRouter routerFor(
    List<String> tokens, {
    Object? failure,
  }) =>
      IntentRouter(
        llm: _ScriptedLlm(tokens, failure: failure),
        local: LocalIntentResolver(),
      );

  Future<String> answer(List<String> tokens, {Object? failure}) =>
      routerFor(tokens, failure: failure)
          .resolveRequest(
            const LlmRequest(
              mode: PuckMode.intent,
              query: 'why is the sky blue',
            ),
          )
          .join();

  group('the intent stream cannot put banned text on the card', () {
    test('a filler opener never reaches the screen', () async {
      final String out = await answer(<String>['Sure', ', the sky is blue']);

      expect(out, LocalIntentResolver.offlineLine);
      expect(out, isNot(contains('Sure')));
    });

    test('a runaway answer is cut at the word budget', () async {
      final List<String> tokens =
          List<String>.generate(40, (int i) => ' word$i');
      final String out = await answer(tokens);
      final int words =
          out.split(RegExp(r'\s+')).where((String w) => w.isNotEmpty).length;

      expect(words, lessThanOrEqualTo(
        PuckPrompt.wordLimitFor(PuckMode.intent) +
            PuckPrompt.validationTolerance,
      ));
    });

    test('a short, clean answer streams through unchanged', () async {
      final String out =
          await answer(<String>['Blue', ' light', ' scatters', ' more.']);

      expect(out, 'Blue light scatters more.');
    });

    test('an empty stream degrades to the offline line, not to a blank card',
        () async {
      expect(await answer(<String>[]), LocalIntentResolver.offlineLine);
    });

    test('a transport failure before any text yields the offline line',
        () async {
      final String out = await answer(
        <String>[],
        failure: const LlmException('boom'),
      );

      expect(out, LocalIntentResolver.offlineLine);
    });

    test('a failure after text has been shown ends quietly, without appending',
        () async {
      final String out = await answer(
        <String>['Blue', ' light', ' scatters.'],
        failure: const LlmException('boom'),
      );

      expect(out, 'Blue light scatters.');
    });
  });

  test('deterministic queries never reach the model', () async {
    final _ScriptedLlm llm = _ScriptedLlm(<String>['should not be used']);
    final IntentRouter router =
        IntentRouter(llm: llm, local: LocalIntentResolver());

    final String out = await router.resolve('flip a coin').join();

    expect(out, anyOf('Heads.', 'Tails.'));
  });
}
