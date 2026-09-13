import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:puck/src/core/constants.dart';
import 'package:puck/src/data/llm/llm_provider.dart';
import 'package:puck/src/data/llm/prompt.dart';
import 'package:puck/src/data/repositories/settings_repository.dart';

/// Groq chat completions, streaming over SSE.
///
/// Model choice (verified against the Groq model catalogue, Sept 2026):
/// `openai/gpt-oss-20b` is the fastest production model on GroqCloud at
/// ~1,000 tok/s and $0.075/M in. The old default, `llama-3.1-8b-instant`, has
/// moved to the Enterprise tier and is no longer available on a normal key --
/// do not copy-paste it from older tutorials.
///
/// Sampling is deliberately per-mode rather than per-app: GIGGLE needs
/// entropy (a low temperature makes it tell the same few lines forever),
/// CONTEXT needs near-determinism because it is a compression task, and
/// INTENT sits in between. See [PuckPrompt.temperatureFor].
class GroqLlmProvider implements LlmProvider {
  GroqLlmProvider({
    required SettingsRepository settings,
    http.Client? client,
    this.model = GroqLlmProvider.defaultModel,
    this.deviceActionsSupported = false,
  })  : _settings = settings,
        _client = client ?? http.Client();

  static const String endpoint =
      'https://api.groq.com/openai/v1/chat/completions';
  static const String defaultModel = 'openai/gpt-oss-20b';

  /// Fallback if the configured model is rejected (deprecations happen).
  static const String fallbackModel = 'openai/gpt-oss-120b';

  final SettingsRepository _settings;
  final http.Client _client;
  final String model;

  /// Flip to true only when a real action registry exists behind the intent
  /// router. Until then the prompt forbids claiming device actions, so the
  /// model says "not connected" instead of inventing "Alarm set for 7:00 AM".
  final bool deviceActionsSupported;

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
            'content': PuckPrompt.system(
              request,
              actionsSupported: deviceActionsSupported,
            ),
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
      final String body = await response.stream
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 2), onTimeout: () => '');
      throw LlmException(
        _describeStatus(response.statusCode, body),
        statusCode: response.statusCode,
        retryable: response.statusCode >= 500 || response.statusCode == 429,
      );
    }

    String lastFrame = '';
    await for (final String line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(PuckConstants.llmIdleTimeout)) {
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
      final dynamic delta = (choices.first as Map)['delta'];
      if (delta is! Map) continue;
      final Object? content = delta['content'];
      if (content is String && content.isNotEmpty) yield content;
    }

    if (lastFrame.isEmpty) {
      throw const LlmException('Empty response from Groq');
    }
  }

  String _describeStatus(int code, String body) {
    if (code == 401) return 'Groq rejected the API key';
    if (code == 429) return 'Rate limited by Groq';
    if (code == 404) return 'Model unavailable — check the model id';
    final String trimmed = body.trim();
    if (trimmed.length > 120) {
      return 'Groq error $code: ${trimmed.substring(0, 120)}…';
    }
    return 'Groq error $code: $trimmed';
  }

  void dispose() => _client.close();
}
