import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:puck/src/core/constants.dart';
import 'package:puck/src/data/llm/llm_provider.dart';
import 'package:puck/src/data/llm/prompt.dart';
import 'package:puck/src/data/llm/sse.dart';
import 'package:puck/src/data/repositories/settings_repository.dart';

/// Groq chat completions, streaming over SSE.
///
/// The stream is consumed straight off `Client.send()` -- no polling, no
/// buffering the whole body -- so the first token paints the moment the
/// model emits it.
///
/// Sampling is deliberately per-mode rather than per-app: CONTEXT needs
/// near-determinism because it is a compression task, and INTENT sits a
/// little looser. See [PuckPrompt.temperatureFor].
class GroqLlmProvider implements LlmProvider {
  GroqLlmProvider({
    required SettingsRepository settings,
    http.Client? client,
    this.model = defaultModel,
  })  : _settings = settings,
        _client = client ?? http.Client();

  static const String endpoint =
      'https://api.groq.com/openai/v1/chat/completions';

  /// The fastest production model on GroqCloud at time of writing, and the
  /// only one Puck uses. One model, one price class, no picker.
  static const String defaultModel = 'openai/gpt-oss-20b';

  final SettingsRepository _settings;
  final http.Client _client;
  final String model;

  @override
  String get id => 'groq:$model';

  @override
  bool get isConfigured => (_settings.groqApiKey ?? '').trim().isNotEmpty;

  @override
  Stream<String> complete(LlmRequest request) async* {
    final String key = (_settings.groqApiKey ?? '').trim();
    if (key.isEmpty) {
      throw const LlmException('No API key configured', retryable: false);
    }

    final http.Request httpRequest = http.Request('POST', Uri.parse(endpoint))
      ..headers.addAll(<String, String>{
        'Authorization': 'Bearer $key',
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'text/event-stream',
      })
      ..body = jsonEncode(<String, dynamic>{
        'model': model,
        'stream': true,
        'messages': <Map<String, String>>[
          <String, String>{
            'role': 'system',
            'content': PuckPrompt.system(request),
          },
          <String, String>{'role': 'user', 'content': PuckPrompt.user(request)},
        ],
        // Low reasoning keeps TTFT down; these answers need no deliberation.
        'reasoning_effort': 'low',
        'temperature': PuckPrompt.temperatureFor(request.mode),
        'max_completion_tokens': PuckPrompt.maxTokensFor(request.mode),
        'stop': PuckPrompt.stopFor(request.mode),
      });

    final http.StreamedResponse response = await _client
        .send(httpRequest)
        .timeout(PuckConstants.llmConnectTimeout);

    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw LlmException(
        _describeStatus(response.statusCode),
        statusCode: response.statusCode,
        retryable: response.statusCode >= 500 || response.statusCode == 429,
      );
    }

    // Parsing is shared with the proxy provider: one wire format, one
    // implementation. See `sse.dart` for why.
    yield* openAiSseDeltas(
      response.stream,
      idleTimeout: PuckConstants.llmIdleTimeout,
    );
  }

  String _describeStatus(int code) {
    if (code == 401) return 'The API key was rejected';
    if (code == 429) return 'Rate limited';
    return 'Network error $code';
  }

  void dispose() => _client.close();
}
