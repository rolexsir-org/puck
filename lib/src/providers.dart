import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:puck/src/core/haptics.dart';
import 'package:puck/src/data/llm/groq_provider.dart';
import 'package:puck/src/data/llm/local_fallback_provider.dart';
import 'package:puck/src/data/repositories/context_repository.dart';
import 'package:puck/src/data/repositories/joke_repository.dart';
import 'package:puck/src/data/repositories/settings_repository.dart';
import 'package:puck/src/data/services/battery_service.dart';
import 'package:puck/src/data/services/calendar_service.dart';
import 'package:puck/src/data/services/location_service.dart';
import 'package:puck/src/data/services/messaging_service.dart';
import 'package:puck/src/data/services/speech_service.dart';
import 'package:puck/src/data/services/torch_service.dart';
import 'package:puck/src/data/services/weather_service.dart';
import 'package:puck/src/domain/intent_router.dart';
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

final Provider<IntentRouter> intentRouterProvider = Provider<IntentRouter>(
  (Ref ref) => IntentRouter(
    llm: ref.watch(groqProvider),
    local: ref.watch(localResolverProvider),
  ),
);
