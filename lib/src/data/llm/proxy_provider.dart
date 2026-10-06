import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:puck/src/core/constants.dart';
import 'package:puck/src/data/llm/llm_provider.dart';
import 'package:puck/src/data/llm/prompt.dart';
import 'package:puck/src/data/llm/sse.dart';
import 'package:puck/src/data/repositories/settings_repository.dart';

/// The shared answer service: the same [LlmProvider] seam, pointed at a proxy
/// that holds the API key instead of the phone holding it.
///
/// # Why this exists
///
/// Puck's first principle is that there is no setup. A user who has to find,
/// paste and pay for an API key before the swipe-up gesture does anything has
/// been given a developer tool, not a product -- and the people this whole
/// change is for are the least likely to do it. One key, held as a secret by a
/// tiny proxy, is what makes "ask anything" work on a fresh install.
///
/// # What it deliberately does not do
///
/// * **It ships off.** The URL comes from `--dart-define=PUCK_PROXY_URL=...`,
///   so the default build has no endpoint and [isConfigured] is false: the
///   app answers from the deterministic resolver and the honest offline line,
///   exactly as it does today. Turning this on spends someone's money, and
///   that decision is the owner's -- see FINDINGS.md §4.1. There is no API key
///   anywhere in this repository, and there never can be: the proxy holds it,
///   the app only knows a URL.
/// * **It sends nothing identifying.** One header, `X-Puck-Device`, carrying
///   the anonymous resettable UUID from settings -- 16 random bytes whose only
///   job is to let the proxy count requests per device. No account, no
///   install ID, nothing derived from the device. The privacy screen says so.
/// * **It does not retry silently.** A refusal from the proxy (rate limited,
///   ceiling reached, switched off) ends the answer with the offline line
///   rather than hammering a service that just said no.
///
/// The drain is the same as the direct-key path: [openAiSseDeltas].
class ProxyLlmProvider implements LlmProvider {
  ProxyLlmProvider({
    required SettingsRepository settings,
    String? baseUrl,
    http.Client? client,
  })  : _settings = settings,
        _baseUrl = (baseUrl ?? configuredBaseUrl).trim(),
        _client = client ?? http.Client();

  /// Injected by whoever builds the app: `flutter build apk
  /// --dart-define=PUCK_PROXY_URL=https://answers.example.org`. Empty by
  /// default, and an empty string is a complete, working configuration in
  /// which nothing is ever sent.
  static const String configuredBaseUrl =
      String.fromEnvironment('PUCK_PROXY_URL');

  /// The path the reference worker in `worker/` serves.
  static const String answerPath = '/v1/answer';

  final SettingsRepository _settings;
  final http.Client _client;
  final String _baseUrl;

  @override
  String get id => _baseUrl.isEmpty ? 'proxy:none' : 'proxy:$_baseUrl';

  @override
  bool get isConfigured => _baseUrl.isNotEmpty;

  @override
  Stream<String> complete(LlmRequest request) async* {
    if (_baseUrl.isEmpty) {
      throw const LlmException(
        'No shared answer service is configured',
        retryable: false,
      );
    }

    final Uri uri = Uri.parse('$_baseUrl$answerPath');
    final http.Request httpRequest = http.Request('POST', uri)
      ..headers.addAll(<String, String>{
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'text/event-stream',
        // The whole identity the service needs, and all it gets.
        'X-Puck-Device': _settings.deviceId,
      })
      ..body = jsonEncode(<String, dynamic>{
        // The prompt is built here, by the same code the direct-key path uses,
        // so the two paths cannot drift into answering differently. The worker
        // validates this shape and sets its own sampling parameters; it does
        // not trust the client with them.
        'mode': request.mode == PuckMode.intent ? 'intent' : 'context',
        'messages': <Map<String, String>>[
          <String, String>{
            'role': 'system',
            'content': PuckPrompt.system(request),
          },
          <String, String>{'role': 'user', 'content': PuckPrompt.user(request)},
        ],
      });

    final http.StreamedResponse response = await _client
        .send(httpRequest)
        .timeout(PuckConstants.llmConnectTimeout);

    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw LlmException(
        _describeStatus(response.statusCode),
        statusCode: response.statusCode,
        // 429 (too many requests) and 5xx are worth another try later; the
        // rest are a configuration or policy answer, and retrying is rude.
        retryable: response.statusCode == 429 || response.statusCode >= 500,
      );
    }

    yield* openAiSseDeltas(
      response.stream,
      idleTimeout: PuckConstants.llmIdleTimeout,
    );
  }

  /// Never shown to a user: these strings are diagnostics. The card shows the
  /// localized offline line (or, for a refused key, the line about Settings) --
  /// see `IntentRouter._failureLine`.
  String _describeStatus(int code) {
    if (code == 429) return 'Shared service rate limit reached';
    if (code == 503) return 'Shared service is switched off';
    if (code == 413) return 'Request too large for the shared service';
    return 'Shared service error $code';
  }

  void dispose() => _client.close();
}
