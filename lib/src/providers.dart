import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:puck/src/commands/command_executor.dart';
import 'package:puck/src/commands/command_parser.dart';
import 'package:puck/src/commands/command_router.dart';
import 'package:puck/src/core/haptics.dart';
import 'package:puck/src/data/llm/gated_provider.dart';
import 'package:puck/src/data/llm/groq_provider.dart';
import 'package:puck/src/data/llm/llm_provider.dart';
import 'package:puck/src/data/llm/local_fallback_provider.dart';
import 'package:puck/src/data/llm/proxy_provider.dart';
import 'package:puck/src/data/repositories/context_repository.dart';
import 'package:puck/src/data/repositories/joke_repository.dart';
import 'package:puck/src/data/repositories/settings_repository.dart';
import 'package:puck/src/data/services/battery_service.dart';
import 'package:puck/src/data/services/calendar_service.dart';
import 'package:puck/src/data/services/device_actions.dart';
import 'package:puck/src/data/services/location_service.dart';
import 'package:puck/src/data/services/messaging_service.dart';
import 'package:puck/src/data/services/platform_bridge.dart';
import 'package:puck/src/data/services/speech_service.dart';
import 'package:puck/src/data/services/torch_service.dart';
import 'package:puck/src/data/services/weather_service.dart';
import 'package:puck/src/domain/intent_router.dart';
import 'package:puck/src/voice/model_store.dart';
import 'package:puck/src/voice/speech_output.dart';
import 'package:puck/src/voice/transcriber.dart';
import 'package:puck/src/voice/voice_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Injected by main(), which awaits the one async SharedPreferences read at
/// startup and overrides this with the result.
///
/// Reading it without that override is a wiring error, not a runtime
/// condition, so it fails loudly instead of guessing. Keeping the instance
/// synchronous downstream is deliberate: a tap must reach first paint without
/// awaiting anything.
final Provider<SharedPreferences> sharedPreferencesProvider =
    Provider<SharedPreferences>(
  (Ref ref) => throw StateError(
    'sharedPreferencesProvider must be overridden in main() with the awaited '
    'SharedPreferences instance. It cannot construct itself: getInstance() is '
    'async, and everything downstream reads it synchronously.',
  ),
);

final ChangeNotifierProvider<SettingsRepository> settingsProvider =
    ChangeNotifierProvider<SettingsRepository>(
  (Ref ref) => SettingsRepository(ref.watch(sharedPreferencesProvider)),
);

// -- Services ---------------------------------------------------------------

final Provider<HapticsService> hapticsProvider =
    Provider<HapticsService>((Ref ref) => HapticsService());

final Provider<BatteryService> batteryServiceProvider =
    Provider<BatteryService>((Ref ref) => BatteryService());

final Provider<CalendarService> calendarServiceProvider =
    Provider<CalendarService>((Ref ref) => CalendarService());

final Provider<LocationService> locationServiceProvider =
    Provider<LocationService>((Ref ref) => LocationService());

/// Closed when the container dies. `http.Client` holds a connection pool and
/// a timer; the app has exactly one container, so this used to be "leaked once
/// at process exit" -- which stopped being true when the settings screen began
/// rebuilding providers. Leaked per rebuild is a socket leak.
final Provider<WeatherService> weatherServiceProvider =
    Provider<WeatherService>((Ref ref) {
  final WeatherService service = WeatherService();
  ref.onDispose(service.dispose);
  return service;
});

final Provider<TorchService> torchServiceProvider =
    Provider<TorchService>((Ref ref) => TorchService());

final Provider<MessagingService> messagingServiceProvider =
    Provider<MessagingService>((Ref ref) => MessagingService());

/// Lazily constructed: the recogniser is expensive and only used on swipe-up.
final Provider<SpeechService> speechServiceProvider =
    Provider<SpeechService>((Ref ref) => SpeechService());

final Provider<ContextRepository> contextRepositoryProvider =
    Provider<ContextRepository>(
  (Ref ref) => ContextRepository(
    battery: ref.watch(batteryServiceProvider),
    calendar: ref.watch(calendarServiceProvider),
    location: ref.watch(locationServiceProvider),
    weather: ref.watch(weatherServiceProvider),
    // The weather lookup is a network call to Open-Meteo, so it answers to the
    // same switch as the answers do. See ContextRepository.snapshot().
    settings: ref.watch(settingsProvider),
  ),
);

final Provider<JokeRepository> jokeRepositoryProvider =
    Provider<JokeRepository>(
  (Ref ref) => JokeRepository(ref.watch(settingsProvider)),
);

// -- Intelligence -----------------------------------------------------------

/// Reads the API key lazily from settings, so saving a key in the settings
/// screen does not require rebuilding the provider graph.
final Provider<GroqLlmProvider> groqProvider = Provider<GroqLlmProvider>(
  (Ref ref) {
    final GroqLlmProvider provider =
        GroqLlmProvider(settings: ref.watch(settingsProvider));
    // Same reasoning as the weather client: an undisposed closed-loop HTTP
    // client is a socket and a timer that outlive their owner.
    ref.onDispose(provider.dispose);
    return provider;
  },
);

final Provider<LocalIntentResolver> localResolverProvider =
    Provider<LocalIntentResolver>((Ref ref) => LocalIntentResolver());

/// The shared answer service (see `proxy_provider.dart`). Ships off: with no
/// `PUCK_PROXY_URL` compiled in, [ProxyLlmProvider.isConfigured] is false and
/// nothing in the app ever contacts it. Turning it on is a cost decision, not
/// a code one -- FINDINGS.md §4.1.
final Provider<ProxyLlmProvider> proxyProvider = Provider<ProxyLlmProvider>(
  (Ref ref) {
    final ProxyLlmProvider provider =
        ProxyLlmProvider(settings: ref.watch(settingsProvider));
    ref.onDispose(provider.dispose);
    return provider;
  },
);

/// The one cloud answer path, and which of the two ways in it uses.
///
/// A key the user pasted wins over the shared service: the privacy screen
/// promises that the shared service is not used when someone has their own
/// key, and their key is their bill rather than the project's. Everyone else
/// -- which is everyone on a fresh install -- gets the shared service when one
/// is configured, and the offline resolver when it is not.
final Provider<LlmProvider> llmProvider = Provider<LlmProvider>((Ref ref) {
  final GroqLlmProvider groq = ref.watch(groqProvider);
  if (groq.isConfigured) return groq;
  return ref.watch(proxyProvider);
});

/// Every cloud answer goes through the gate, so the "nothing leaves your
/// phone" switch is one check rather than a per-feature promise.
final Provider<GatedLlmProvider> gatedLlmProvider = Provider<GatedLlmProvider>(
  (Ref ref) => GatedLlmProvider(
    inner: ref.watch(llmProvider),
    settings: ref.watch(settingsProvider),
  ),
);

final Provider<IntentRouter> intentRouterProvider = Provider<IntentRouter>(
  (Ref ref) => IntentRouter(
    llm: ref.watch(gatedLlmProvider),
    local: ref.watch(localResolverProvider),
  ),
);

// -- Voice (2026-11) ---------------------------------------------------------

/// Android's native bridge: media volume, the launcher, the clock app, audio
/// out. One instance, because it wraps one MethodChannel.
final Provider<PlatformBridge> platformBridgeProvider =
    Provider<PlatformBridge>((Ref ref) => PlatformBridge());

/// Where the downloaded voice models live.
///
/// Injected by `main()` after one async `getApplicationSupportDirectory()`, for
/// the same reason as [sharedPreferencesProvider]: the settings screen and the
/// transcriber both want it synchronously, and a provider that can only be read
/// asynchronously would put a `FutureBuilder` in front of a download button.
final Provider<VoiceModelStore> voiceModelStoreProvider =
    Provider<VoiceModelStore>(
  (Ref ref) => throw StateError(
    'voiceModelStoreProvider must be overridden in main() with an awaited '
    'VoiceModelStore. See the note on sharedPreferencesProvider.',
  ),
);

/// The five platform ports the command executor drives.
final Provider<CommandExecutor> commandExecutorProvider =
    Provider<CommandExecutor>((Ref ref) {
  final PlatformBridge bridge = ref.watch(platformBridgeProvider);
  return CommandExecutor(
    volume: BridgedVolumePort(bridge),
    apps: BridgedAppLauncher(bridge),
    clock: BridgedClock(bridge),
    torch: PluginTorch(torch: ref.watch(torchServiceProvider)),
    battery: ServiceBattery(battery: ref.watch(batteryServiceProvider)),
  );
});

/// Parse -> execute -> report, with the duplicate guard.
///
/// The assistant's own name is read from settings at construction; renaming
/// Puck rebuilds this provider, which is exactly the intent ("hey Jarvis" starts
/// working when the name is Jarvis -- as a *phrase* prefix, not as an acoustic
/// wake word; see docs/voice.md §5).
final Provider<CommandRouter> commandRouterProvider =
    Provider<CommandRouter>((Ref ref) {
  final SettingsRepository settings = ref.watch(settingsProvider);
  return CommandRouter(
    parser: CommandParser(assistantName: settings.assistantName),
    executor: ref.watch(commandExecutorProvider),
  );
});

/// Offline-first speech input, falling back to the platform recogniser when the
/// models are not installed.
final Provider<Transcriber> transcriberProvider = Provider<Transcriber>((Ref ref) {
  final VoiceModelStore store = ref.watch(voiceModelStoreProvider);
  final PreferredTranscriber transcriber = PreferredTranscriber(
    offline: SherpaTranscriber(store: store),
    platform: PlatformTranscriber(
      speech: ref.watch(speechServiceProvider),
    ),
  );
  ref.onDispose(transcriber.dispose);
  return transcriber;
});

/// One microphone session at a time, for the whole app.
final ChangeNotifierProvider<VoiceSessionController> voiceSessionProvider =
    ChangeNotifierProvider<VoiceSessionController>(
  (Ref ref) => VoiceSessionController(
    transcriber: ref.watch(transcriberProvider),
  ),
);

/// Spoken answers: the Puck voice when installed, the phone's engine otherwise.
final Provider<SpeechOutput> speechOutputProvider = Provider<SpeechOutput>(
  (Ref ref) {
    final SpeechRouter router = SpeechRouter(
      system: SystemSpeechOutput(bridge: ref.watch(platformBridgeProvider)),
      sherpa: SherpaSpeechOutput(
        // Read, not watched, and inside a closure: the optional voice resolves
        // the model directory only when it is asked to speak, so an app without
        // one still talks through the phone's engine.
        store: () => ref.read(voiceModelStoreProvider),
        bridge: ref.watch(platformBridgeProvider),
      ),
    );
    ref.onDispose(router.dispose);
    return router;
  },
);
