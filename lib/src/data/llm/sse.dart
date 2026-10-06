import 'dart:async';
import 'dart:convert';

import 'package:puck/src/data/llm/llm_provider.dart';

/// Turns an OpenAI-style server-sent-event stream into text deltas.
///
/// Shared by the two providers ([GroqLlmProvider] with a user's own key, and
/// [ProxyLlmProvider] against the shared service) because the wire format is
/// the same one and the parsing has exactly one correct behaviour: emit the
/// content of each `data:` frame, stop at `[DONE]`, ignore keep-alives and
/// malformed frames, and give up if the stream ends without a single usable
/// frame. Two copies of that would be two places to get the offsets wrong.
///
/// The stream is consumed frame by frame with no buffering of the whole body,
/// so the first token paints the moment the model emits it.
Stream<String> openAiSseDeltas(
  Stream<List<int>> body, {
  required Duration idleTimeout,
}) async* {
  String lastFrame = '';

  await for (final String line in body
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .timeout(idleTimeout)) {
    if (line.isEmpty || !line.startsWith('data:')) continue;

    final String data = line.substring(5).trim();
    if (data == '[DONE]') break;

    lastFrame = data;
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      continue; // Malformed keep-alive or partial frame.
    }

    final dynamic choices = json['choices'];
    if (choices is! List || choices.isEmpty) continue;
    final dynamic delta = (choices.first as Map<dynamic, dynamic>)['delta'];
    if (delta is! Map<dynamic, dynamic>) continue;
    final Object? content = delta['content'];
    if (content is String && content.isNotEmpty) yield content;
  }

  if (lastFrame.isEmpty) {
    // A 200 with no content is not an answer. The caller turns this into the
    // one honest offline line rather than showing an empty card.
    throw const LlmException('Empty response from model', retryable: true);
  }
}
