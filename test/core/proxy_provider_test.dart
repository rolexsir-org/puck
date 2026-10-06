import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:puck/src/data/llm/llm_provider.dart';
import 'package:puck/src/data/llm/prompt.dart';
import 'package:puck/src/data/llm/proxy_provider.dart';
import 'package:puck/src/data/repositories/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The shared answer service, from the phone's side.
///
/// The service itself is tested where it runs (`worker/test/`, with
/// `node --test`). What is tested here is everything the app is responsible
/// for: that an unconfigured build sends nothing at all, that the request
/// carries the anonymous device id and no key, that the system prompt still
/// satisfies the marker the worker checks for, and that each refusal from the
/// service turns into the right kind of failure -- retryable or not -- so the
/// router can show the one honest offline line instead of an error.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SettingsRepository> repository() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    return SettingsRepository(await SharedPreferences.getInstance());
  }

  String sse(String text) =>
      'data: {"choices":[{"delta":{"content":"$text"}}]}\n\ndata: [DONE]\n\n';

  LlmRequest intent(String query) =>
      LlmRequest(mode: PuckMode.intent, query: query);

  test('an unconfigured build sends nothing, and fails honestly', () async {
    // The default build: no --dart-define, so no URL. This is the state the
    // app ships in, and "sends nothing" has to be verifiable.
    bool called = false;
    final ProxyLlmProvider provider = ProxyLlmProvider(
      settings: await repository(),
      baseUrl: '',
      client: MockClient((http.Request request) async {
        called = true;
        return http.Response('', 200);
      }),
    );

    expect(provider.isConfigured, isFalse);
    expect(provider.id, 'proxy:none');

    await expectLater(
      provider.complete(intent('why is the sky blue')),
      emitsError(isA<LlmException>()),
    );
    expect(called, isFalse, reason: 'no request may be attempted at all');
  });

  test('a configured build streams the deltas through', () async {
    final ProxyLlmProvider provider = ProxyLlmProvider(
      settings: await repository(),
      baseUrl: 'https://answers.example.org',
      client: MockClient(
        (http.Request request) async => http.Response(sse('Blue.'), 200),
      ),
    );

    expect(provider.isConfigured, isTrue);
    expect(
      await provider.complete(intent('why is the sky blue')).join(),
      'Blue.',
    );
  });

  test('the request carries the anonymous device id and no secret', () async {
    final SettingsRepository settings = await repository();
    String? deviceHeader;
    Map<String, dynamic>? sentBody;
    Map<String, String>? sentHeaders;

    final ProxyLlmProvider provider = ProxyLlmProvider(
      settings: settings,
      baseUrl: 'https://answers.example.org',
      client: MockClient((http.Request request) async {
        deviceHeader = request.headers['X-Puck-Device'];
        sentHeaders = request.headers;
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(sse('Blue.'), 200);
      }),
    );

    await provider.complete(intent('why is the sky blue')).join();

    expect(deviceHeader, settings.deviceId);
    expect(deviceHeader, isNotNull);
    // Nothing that looks like a credential, in the headers or the body.
    expect(
      sentHeaders!.keys.map((String k) => k.toLowerCase()),
      isNot(contains('authorization')),
    );
    expect(sentHeaders!.keys.map((String k) => k.toLowerCase()),
        isNot(contains('x-api-key')));
    final String whole = jsonEncode(sentBody);
    expect(whole.contains('Bearer'), isFalse);
    expect(whole.contains('api_key'), isFalse);

    // The URL is the one the reference worker serves.
    expect(ProxyLlmProvider.answerPath, '/v1/answer');
  });

  test('the request still satisfies the worker\'s prompt marker', () async {
    // A contract between two files in two languages, so it is asserted rather
    // than assumed: the worker refuses anything whose system turn does not
    // contain this marker, which is what keeps the endpoint from being a free
    // general-purpose model. If the prompt preamble is ever reworded, this
    // test fails here rather than in production.
    Map<String, dynamic>? sentBody;
    final ProxyLlmProvider provider = ProxyLlmProvider(
      settings: await repository(),
      baseUrl: 'https://answers.example.org',
      client: MockClient((http.Request request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(sse('Blue.'), 200);
      }),
    );

    await provider.complete(intent('why is the sky blue')).join();

    final List<dynamic> messages = sentBody!['messages'] as List<dynamic>;
    expect(messages, hasLength(2));
    final Map<String, dynamic> system = messages[0] as Map<String, dynamic>;
    expect(system['role'], 'system');
    expect(
      system['content'].toString(),
      contains('You are the intelligence engine inside Puck'),
    );
    expect(sentBody!['mode'], 'intent');
  });

  test('a refusal is translated into the right kind of failure', () async {
    // Retryable or not decides whether the router shows the offline line or
    // the line about the key; the service's own JSON is never shown.
    for (final (int status, bool retryable, String id) in <(int, bool, String)>[
      (429, true, 'rate limited'),
      (503, true, 'switched off'),
      (413, false, 'too large'),
      (400, false, 'bad shape'),
    ]) {
      final ProxyLlmProvider provider = ProxyLlmProvider(
        settings: await repository(),
        baseUrl: 'https://answers.example.org',
        client: MockClient(
          (http.Request request) async =>
              http.Response('{"error":"$id"}', status),
        ),
      );

      Object? thrown;
      try {
        await provider.complete(intent('why is the sky blue')).join();
      } catch (error) {
        thrown = error;
      }

      expect(thrown, isA<LlmException>(), reason: 'status $status');
      final LlmException exception = thrown! as LlmException;
      expect(exception.statusCode, status);
      expect(exception.retryable, retryable, reason: 'status $status');
      // The service's payload never becomes a user-visible string.
      expect(exception.message.contains('$id'), isFalse);
    }
  });

  test('a 200 with no frames is a failure, not an empty answer', () async {
    final ProxyLlmProvider provider = ProxyLlmProvider(
      settings: await repository(),
      baseUrl: 'https://answers.example.org',
      client: MockClient(
        (http.Request request) async => http.Response('', 200),
      ),
    );

    await expectLater(
      provider.complete(intent('why is the sky blue')).join(),
      throwsA(isA<LlmException>()),
    );
  });
}
