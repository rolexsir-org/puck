import 'dart:async';

import 'package:puck/src/data/llm/llm_provider.dart';
import 'package:puck/src/data/llm/prompt.dart';
import 'package:puck/src/data/repositories/settings_repository.dart';

/// The one switch that stops everything leaving the phone, applied at the seam
/// rather than in each screen.
///
/// The privacy screen promises that "Off means no question, and nothing else,
/// ever leaves your phone". A promise like that is only true if it is enforced
/// in the one place every cloud call passes through, because the failure mode
/// of enforcing it per-feature is that a feature added later forgets. So the
/// gate wraps any [LlmProvider] and answers [isConfigured] with false while the
/// switch is off, which makes the router take its offline path: no socket, no
/// timeout, no spinner, and the same deterministic answers the app has with no
/// key at all.
///
/// It is a wrapper rather than a check inside `GroqLlmProvider` because the
/// planned shared proxy is a second provider; a rule that lives in one provider
/// would be a rule the second one silently does not have.
///
/// Note what is *not* gated here: the weather lookup is a cloud call too, and
/// it is gated in `ContextRepository` where it is made rather than through
/// this seam. Both are listed on the privacy screen.
class GatedLlmProvider implements LlmProvider {
  GatedLlmProvider({
    required LlmProvider inner,
    required SettingsRepository settings,
  })  : _inner = inner,
        _settings = settings;

  final LlmProvider _inner;
  final SettingsRepository _settings;

  @override
  String get id => _settings.cloudEnabled ? _inner.id : 'off:${_inner.id}';

  @override
  bool get isConfigured => _settings.cloudEnabled && _inner.isConfigured;

  @override
  Stream<String> complete(LlmRequest request) {
    if (!_settings.cloudEnabled) {
      // Unreachable through the router, which checks [isConfigured] first.
      // Kept as a real failure rather than an empty stream so that a future
      // caller which skips the check fails visibly instead of quietly
      // pretending the model had nothing to say.
      return Stream<String>.error(
        const LlmException('Cloud answers are switched off', retryable: false),
      );
    }
    return _inner.complete(request);
  }
}
