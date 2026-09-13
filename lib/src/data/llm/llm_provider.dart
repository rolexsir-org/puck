import 'dart:async';

import 'package:puck/src/data/llm/prompt.dart';

/// The LLM seam.
///
/// Puck talks to exactly one thing: a request in, a stream of text out.
/// Swapping Groq for OpenAI, Gemini, or a local model means implementing this
/// and changing one line in `providers.dart`.
///
/// Note the argument is a whole [LlmRequest], not a String. Sampling
/// parameters and stop sequences are per-mode decisions (see [PuckPrompt]),
/// so the mode has to travel with the text.
abstract class LlmProvider {
  String get id;

  /// False when a key is missing -- lets the router fall back offline instead
  /// of burning a network round-trip on a call that will 401.
  bool get isConfigured;

  /// Emits text deltas as they arrive.
  Stream<String> complete(LlmRequest request);
}

class LlmException implements Exception {
  const LlmException(this.message, {this.retryable = true, this.statusCode});

  final String message;
  final bool retryable;
  final int? statusCode;

  @override
  String toString() => 'LlmException(${statusCode ?? '-'}): $message';
}
