import 'dart:ui' show Locale;

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:puck/src/core/format.dart';
import 'package:puck/src/l10n/strings_es.dart';

/// Every word Puck says, in one place, keyed for translators.
///
/// # Why this and not `flutter gen-l10n`
///
/// `flutter_localizations` and `intl` are used -- see `app.dart` for the
/// delegates and [clock]/[stamp] below for locale-aware time and dates -- and
/// the ARB files under `lib/l10n/` are the translator-facing source of truth.
/// What is deliberately *not* used is compile-time code generation: the
/// generated accessor class is a build artefact this repository could not
/// produce while it was being written (no Dart toolchain in the authoring
/// environment), and committing a thousand lines of unrun generated code would
/// have broken the one rule that matters -- do not claim a thing works if you
/// did not run it.
///
/// The contract generation would have given us is enforced by
/// `test/core/strings_test.dart` instead: it loads every ARB file on disk and
/// fails when the ARB keys and the maps below disagree, in either direction. A
/// missing translation is a red test, which is the actual requirement.
///
/// # Fallback
///
/// A key missing from a locale falls back to English, and that is *visible*
/// ([isTranslated] is false, [untranslatedKeys] lists them) rather than
/// silently blank. A half-translated app that shows English for the parts
/// nobody translated is honest; one that shows empty boxes is broken.
class PuckStrings {
  const PuckStrings._(this.locale, this._values, this._english);

  final Locale locale;
  final Map<String, String> _values;
  final Map<String, String> _english;

  /// The languages Puck ships.
  ///
  /// Two, done completely, rather than twelve done badly. English is the
  /// source and the fallback for everything else; Spanish is the first real
  /// translation because one target language covers Spain and Latin America
  /// (~500M speakers) and because it exercises everything that makes
  /// localization hard except the script direction: gendered word order in the
  /// card headlines, a 24-hour clock for most regions, and a different date
  /// order.
  ///
  /// Which languages come next is a business decision, not a technical one --
  /// see FINDINGS.md. Adding one is a new map in this directory plus a new ARB
  /// file; the layout work (RTL mirroring) is already done and tested with a
  /// forced RTL direction, so an Arabic or Urdu translation is a translation
  /// rather than a project.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
  ];

  static PuckStrings of(BuildContext context) {
    final Locale? locale = Localizations.maybeLocaleOf(context);
    return forLocale(locale ?? const Locale('en'));
  }

  static PuckStrings forLocale(Locale locale) {
    final Map<String, String>? values = _translations[locale.languageCode];
    return PuckStrings._(
      Locale(locale.languageCode),
      values ?? const <String, String>{},
      _en,
    );
  }

  /// True when the key came from a real translation rather than the English
  /// fallback.
  bool isTranslated(String key) => _values.containsKey(key);

  List<String> untranslatedKeys() => _en.keys
      .where((String k) => !_values.containsKey(k))
      .toList(growable: false);

  /// Used by the ARB parity test and by the ARB export script.
  static Map<String, String> englishSource() => Map<String, String>.of(_en);

  static Map<String, String> translationsFor(String languageCode) =>
      Map<String, String>.of(
        _translations[languageCode] ?? const <String, String>{},
      );

  bool get isEnglish => locale.languageCode == 'en';

  String get localeName => locale.languageCode;

  String text(String key) => _values[key] ?? _english[key] ?? key;

  /// `%1`, `%2` ... substitution, so a translation can reorder its arguments.
  /// Spanish puts the object before the verb far more often than English does,
  /// and a template that cannot move its own parts is a template that will be
  /// translated wrongly.
  String format(String key, List<String> args) {
    String out = text(key);
    for (int i = 0; i < args.length; i++) {
      out = out.replaceAll('%${i + 1}', args[i]);
    }
    return out;
  }

  // -- Time, dates and counts ------------------------------------------------
  //
  // English goes through [PuckFormat], which is the same code the unit tests
  // exercise, so the tested path and the shipped path are the same path.
  // Everything else goes through `intl`: a 24-hour clock where that is the
  // norm, locale month and day names, and the region's date order.

  /// "3:07 PM" in en, "15:07" in es.
  String clock(DateTime t) {
    if (isEnglish) return PuckFormat.clock(t);
    return DateFormat.jm(localeName).format(t);
  }

  /// "3:14 PM · Wed Jan 15" in en, "15:14 · mié, 15 ene" in es.
  String stamp(DateTime t) {
    if (isEnglish) return PuckFormat.stamp(t);
    return '${clock(t)} · ${DateFormat.MMMEd(localeName).format(t)}';
  }

  /// "now", "in 12m", "in 2h 5m", "in 2d" -- with localized unit words.
  String countdown(Duration d) {
    if (isEnglish) return PuckFormat.countdown(d);
    if (d <= Duration.zero) return text('countdownNow');
    if (d.inMinutes < 1) return _in('${d.inSeconds}', text('unitSeconds'));
    if (d.inHours < 1) return _in('${d.inMinutes}', text('unitMinutes'));
    if (d.inDays < 1) {
      final int minutes = d.inMinutes.remainder(60);
      if (minutes == 0) return _in('${d.inHours}', text('unitHours'));
      return _in(
        '${d.inHours}${text('unitHours')} $minutes${text('unitMinutes')}',
        '',
      );
    }
    return _in('${d.inDays}', text('unitDays'));
  }

  String _in(String value, String unit) =>
      text('countdownIn').replaceAll('%1', '$value$unit');

  // -- The four gestures ----------------------------------------------------

  String get bubbleLabel => text('bubbleLabel');
  String get bubbleHint => text('bubbleHint');
  String get actionTap => text('actionTap');
  String get actionJoke => text('actionJoke');
  String get actionSos => text('actionSos');
  String get actionAsk => text('actionAsk');
  String get actionSettings => text('actionSettings');
  String get actionPrivacy => text('actionPrivacy');
  String get actionsTitle => text('actionsTitle');
  String get actionsOpen => text('actionsOpen');
  String get actionsClose => text('actionsClose');
  String get actionsHint => text('actionsHint');
  String get sosConfirmTitle => text('sosConfirmTitle');
  String get sosConfirmBody => text('sosConfirmBody');
  String get sosConfirmStart => text('sosConfirmStart');
  String get sosConfirmBack => text('sosConfirmBack');

  // -- First run ------------------------------------------------------------

  String get firstRunTitle => text('firstRunTitle');
  String get firstRunTap => text('firstRunTap');
  String get firstRunDoubleTap => text('firstRunDoubleTap');
  String get firstRunHold => text('firstRunHold');
  String get firstRunSwipe => text('firstRunSwipe');
  String get firstRunDismiss => text('firstRunDismiss');

  // -- The tap card ---------------------------------------------------------

  String get labelHappeningNow => text('labelHappeningNow');
  String get labelNextUp => text('labelNextUp');
  String get labelToday => text('labelToday');
  String get labelBattery => text('labelBattery');
  String get labelWeather => text('labelWeather');
  String get labelGoodMorning => text('labelGoodMorning');
  String get labelGoodAfternoon => text('labelGoodAfternoon');
  String get labelGoodEvening => text('labelGoodEvening');
  String get allDay => text('allDay');
  String get nothingUrgentNight => text('nothingUrgentNight');
  String get nothingUrgentLate => text('nothingUrgentLate');
  String get nothingUrgent => text('nothingUrgent');
  String get clearAhead => text('clearAhead');

  /// WMO weather codes in words, in the user's language.
  String weatherDescription(int code) {
    if (code == 0) return text('wxClear');
    if (code <= 3) return text('wxPartlyCloudy');
    if (code == 45 || code == 48) return text('wxFog');
    if (code <= 57) return text('wxDrizzle');
    if (code <= 67) return text('wxRain');
    if (code <= 77) return text('wxSnow');
    if (code <= 82) return text('wxShowers');
    if (code <= 86) return text('wxSnowShowers');
    return text('wxThunderstorm');
  }

  String startedAgo(String title, String when) =>
      format('headlineStarted', <String>[title, when]);
  String nextUp(String title, String when) =>
      format('headlineNextUp', <String>[title, when]);
  String batteryLow(int level) =>
      format('headlineBatteryLow', <String>['$level']);
  String batteryCritical(int level) =>
      format('headlineBatteryCritical', <String>['$level']);
  String chargedTo(int level) =>
      format('headlineCharged', <String>['$level']);
  String rainStarting(String when) =>
      format('headlineRainStarting', <String>[when]);
  String rainAt(String clock) => format('headlineRainAt', <String>[clock]);
  String coldOutside(String temperature) =>
      format('headlineCold', <String>[temperature]);
  String hotOutside(String temperature) =>
      format('headlineHot', <String>[temperature]);
  String timeOfDay(String clock, String closing) =>
      format('headlineTime', <String>[clock, closing]);
  String condition(String description, String temperature) =>
      format('detailCondition', <String>[description, temperature]);

  // -- The intent bar -------------------------------------------------------

  String get askAnything => text('askAnything');
  String get intentFieldLabel => text('intentFieldLabel');
  String get micStart => text('micStart');
  String get micStop => text('micStop');
  String get sendAnswer => text('sendAnswer');
  String get thinking => text('thinking');
  String get answerComplete => text('answerComplete');

  // -- SOS ------------------------------------------------------------------

  String get sosCancel => text('sosCancel');
  String get sosStop => text('sosStop');
  String get sosCancelHint => text('sosCancelHint');
  String get sosStopHint => text('sosStopHint');
  String get sosGettingLocation => text('sosGettingLocation');
  String get sosLocationFound => text('sosLocationFound');
  String get sosLocationMissing => text('sosLocationMissing');
  String get sosNoContact => text('sosNoContact');
  String get sosMessageReady => text('sosMessageReady');
  String get sosNoMessagingApp => text('sosNoMessagingApp');
  String get sosDialerOpen => text('sosDialerOpen');
  String get sosNoDialer => text('sosNoDialer');
  String get sosEmergencyFallbackNote => text('sosEmergencyFallbackNote');
  String get sosEmergencyRegionalNote => text('sosEmergencyRegionalNote');
  String get sosRingWaiting => text('sosRingWaiting');
  String get sosRingFound => text('sosRingFound');
  String sosCounting(int seconds) =>
      format('sosCounting', <String>['$seconds']);
  String sosCountingAnnouncement(int seconds) =>
      format('sosCountingAnnouncement', <String>['$seconds']);
  String callEmergency(String number) =>
      format('callEmergency', <String>[number]);
  String callEmergencySemantics(String number) =>
      format('callEmergencySemantics', <String>[number]);

  /// The emergency message itself. Localized because the recipient may not
  /// read English either -- in fact, for an SOS from a Spanish speaker, the
  /// recipient is *likely* not to.
  ///
  /// These two keys were referenced by `MessagingService.buildSosBody` before
  /// they existed in the map, which meant `text()` returned the key itself and
  /// the most important message in the app went out as "sosMessage /
  /// sosMessageNoLocation". `test/core/strings_test.dart` now parses this file
  /// and fails if any `text('...')` key is missing from the map.
  String get sosMessage => text('sosMessage');
  String get sosMessageNoLocation => text('sosMessageNoLocation');

  /// The line under "Call 112": what that button does, in words, before it is
  /// pressed.
  String get callEmergencyHint => text('callEmergencyHint');

  /// An untitled calendar event. The word lives here rather than in
  /// `CalendarService`, which has no locale and used to put the English
  /// string "Busy" into a Spanish card.
  String get busyLabel => text('busyLabel');

  // -- Settings -------------------------------------------------------------

  String get settingsTitle => text('settingsTitle');
  String get back => text('back');
  String get holdTitle => text('holdTitle');
  String get holdOneSecond => text('holdOneSecond');
  String get holdTwoSeconds => text('holdTwoSeconds');
  String get holdThreeSeconds => text('holdThreeSeconds');
  String get holdNote => text('holdNote');
  String get emergencyContactTitle => text('emergencyContactTitle');
  String get emergencyContactHint => text('emergencyContactHint');
  String get emergencyContactNote => text('emergencyContactNote');
  String get advancedTitle => text('advancedTitle');
  String get advancedNote => text('advancedNote');
  String get apiKeyTitle => text('apiKeyTitle');
  String get apiKeyHint => text('apiKeyHint');
  String get paste => text('paste');
  String get apiKeyNote => text('apiKeyNote');
  String releaseCancels(int times) => format(
        times == 1 ? 'releaseCancelsOne' : 'releaseCancelsMany',
        <String>['$times'],
      );
  String get cloudTitle => text('cloudTitle');
  String get cloudNote => text('cloudNote');
  String get privacyTitle => text('privacyTitle');
  String get privacyNote => text('privacyNote');
  String get clearDataTitle => text('clearDataTitle');
  String get clearDataAction => text('clearDataAction');
  String get clearDataConfirm => text('clearDataConfirm');
  String get clearDataDone => text('clearDataDone');
  String get clearDataCancel => text('clearDataCancel');
  String get diagnosticsTitle => text('diagnosticsTitle');
  String get diagnosticsVersion => text('diagnosticsVersion');
  String get diagnosticsPlatform => text('diagnosticsPlatform');
  String get diagnosticsCloud => text('diagnosticsCloud');
  String get diagnosticsCloudOn => text('diagnosticsCloudOn');
  String get diagnosticsCloudOff => text('diagnosticsCloudOff');
  String get diagnosticsSpeech => text('diagnosticsSpeech');
  String get diagnosticsUnavailable => text('diagnosticsUnavailable');
  String get diagnosticsAvailable => text('diagnosticsAvailable');
  String get feedbackTitle => text('feedbackTitle');
  String get feedbackNote => text('feedbackNote');
  String get feedbackAction => text('feedbackAction');
  String get feedbackNoMail => text('feedbackNoMail');

  // -- The privacy screen ---------------------------------------------------

  String get privacyScreenTitle => text('privacyScreenTitle');
  String get privacyIntro => text('privacyIntro');
  String get privacySendsTitle => text('privacySendsTitle');
  String get privacyQuestion => text('privacyQuestion');
  String get privacyEventTitle => text('privacyEventTitle');
  String get privacyEventWhen => text('privacyEventWhen');
  String get privacyEventWhere => text('privacyEventWhere');
  String get privacyBattery => text('privacyBattery');
  String get privacyWeather => text('privacyWeather');
  String get privacyTime => text('privacyTime');
  String get privacyDeviceId => text('privacyDeviceId');
  String get privacyNeverTitle => text('privacyNeverTitle');
  String get privacyNeverBody => text('privacyNeverBody');
  String get privacyAttribution => text('privacyAttribution');

  // -- Answers that must exist in every language ----------------------------

  String get coinHeads => text('coinHeads');
  String get coinTails => text('coinTails');

  /// The one honest sentence for "I cannot answer this without the network".
  String get offlineLine => text('offlineLine');

  /// A rejected API key is the one cloud failure with an action attached to
  /// it, so it says what to do instead of pretending to be offline.
  String get answerKeyRejected => text('answerKeyRejected');

  /// The crisis / medical / legal line. Fixed, short, never improvised by the
  /// model -- see [PuckSafety].
  String get safetyLine => text('safetyLine');

  /// The double-tap in a language with no joke bag. Honest, and still a
  /// pleasant thing to read rather than an error.
  String get jokeFallback => text('jokeFallback');

  // -- The source strings ---------------------------------------------------

  static const Map<String, String> _en = <String, String>{
    'bubbleLabel': 'Puck',
    'bubbleHint': 'Tap for the one thing worth knowing. Double tap for a joke. '
        'Hold for emergency. Swipe up to ask anything.',
    'actionTap': 'Tell me the one thing worth knowing',
    'actionJoke': 'Tell me a joke',
    'actionSos': 'Emergency',
    'actionAsk': 'Ask a question',
    'actionSettings': 'Settings',
    'actionPrivacy': 'What leaves my phone',
    'actionsTitle': 'What Puck can do',
    'actionsOpen': 'Show all actions',
    'actionsClose': 'Close',
    'actionsHint': 'Every action Puck has, as a button. Nothing here needs a '
        'gesture.',
    'sosConfirmTitle': 'Start the emergency countdown?',
    'sosConfirmBody': 'Puck turns on the torch and opens a message you still '
        'have to send yourself. You can cancel at any point.',
    'sosConfirmStart': 'Start countdown',
    'sosConfirmBack': 'Not now',
    'firstRunTitle': 'Four things, one button',
    'firstRunTap': 'Tap — the one thing worth knowing',
    'firstRunDoubleTap': 'Double tap — a joke',
    'firstRunHold': 'Hold — emergency',
    'firstRunSwipe': 'Swipe up — ask anything',
    'firstRunDismiss': 'Tap this card to put it away for good',
    'labelHappeningNow': 'HAPPENING NOW',
    'labelNextUp': 'NEXT UP',
    'labelToday': 'TODAY',
    'labelBattery': 'BATTERY',
    'labelWeather': 'WEATHER',
    'labelGoodMorning': 'GOOD MORNING',
    'labelGoodAfternoon': 'GOOD AFTERNOON',
    'labelGoodEvening': 'GOOD EVENING',
    'allDay': 'All day',
    'nothingUrgent': 'nothing needs you right now.',
    'nothingUrgentNight': 'Nothing urgent. Sleep is also a plan.',
    'nothingUrgentLate': 'Nothing urgent. Tomorrow is already queueing.',
    'clearAhead': 'clear ahead.',
    'wxClear': 'Clear',
    'wxPartlyCloudy': 'Partly cloudy',
    'wxFog': 'Fog',
    'wxDrizzle': 'Drizzle',
    'wxRain': 'Rain',
    'wxSnow': 'Snow',
    'wxShowers': 'Showers',
    'wxSnowShowers': 'Snow showers',
    'wxThunderstorm': 'Thunderstorm',
    'headlineStarted': '%1 started %2 ago',
    'headlineNextUp': '%1 %2',
    'headlineBatteryLow': '%1% — charge before you leave',
    'headlineBatteryCritical': '%1% — find a cable now',
    'headlineCharged': 'Charged to %1%',
    'headlineRainStarting': 'Rain starting %1 — take an umbrella',
    'headlineRainAt': 'Rain at %1 — take an umbrella',
    'headlineCold': '%1° outside — wear a jacket',
    'headlineHot': '%1° outside — carry water',
    'headlineTime': '%1 — %2',
    'detailCondition': '%1 · %2',
    'countdownNow': 'now',
    'countdownIn': 'in %1',
    'unitSeconds': 's',
    'unitMinutes': 'm',
    'unitHours': 'h',
    'unitDays': 'd',
    'askAnything': 'Ask anything.',
    'intentFieldLabel': 'Your question',
    'micStart': 'Speak your question',
    'micStop': 'Stop listening',
    'sendAnswer': 'Ask',
    'thinking': 'Thinking',
    'answerComplete': 'Answer complete',
    'sosCancel': 'CANCEL',
    'sosStop': 'STOP',
    'sosCancelHint': 'Cancels the emergency. Nothing is sent.',
    'sosStopHint': 'Stops the torch and closes this screen.',
    'sosGettingLocation': 'Getting your location',
    'sosLocationFound': 'Location found',
    'sosLocationMissing': 'No GPS fix — the message says so',
    'sosNoContact': 'No contact set — call instead',
    'sosMessageReady': 'Message ready — press send',
    'sosNoMessagingApp': 'No messaging app — call instead',
    'sosDialerOpen': 'Dialer open — press call',
    'sosNoDialer': 'This device has no dialer',
    'sosCounting': 'SOS in %1',
    'sosCountingAnnouncement': 'SOS in %1 seconds. Lift your finger to cancel.',
    'sosRingWaiting': 'Waiting for a location fix',
    'sosRingFound': 'Location found',
    'sosEmergencyFallbackNote': 'Local emergency number. Opens the dialer — '
        'nothing is dialled for you.',
    'sosEmergencyRegionalNote': 'Could not read your region, so this is the '
        'standard emergency line. Opens the dialer — nothing is dialled for you.',
    'callEmergency': 'CALL %1',
    'callEmergencySemantics': 'Call emergency services, %1',
    'settingsTitle': 'Settings',
    'back': 'Back',
    'holdTitle': 'Hold to start an emergency',
    'holdOneSecond': '1 second',
    'holdTwoSeconds': '2 seconds',
    'holdThreeSeconds': '3 seconds',
    'holdNote': 'Three seconds is the default and the safest. Shorten it only '
        'if holding a button that long is hard for you.',
    'emergencyContactTitle': 'Emergency contact',
    'emergencyContactHint': 'Number',
    'emergencyContactNote': 'The SOS message opens in Messages, ready to send. '
        'Nothing is ever sent on its own. With no contact, Puck offers the '
        'local emergency number instead.',
    'advancedTitle': 'Advanced',
    'advancedNote': 'Puck answers by itself through a shared service. Nothing '
        'to set up.',
    'apiKeyTitle': 'Use my own key (optional)',
    'apiKeyHint': 'Paste a key',
    'paste': 'Paste',
    'apiKeyNote': 'Optional and advanced. With your own key, answers come '
        'straight from your own Groq account and the shared service is not used.',
    'releaseCancelsOne': 'Puck cancels itself when you release early. It has '
        'done that %1 time.',
    'releaseCancelsMany': 'Puck cancels itself when you release early. It has '
        'done that %1 times.',
    'cloudTitle': 'Let Puck answer with the internet',
    'cloudNote': 'Off means no question, and nothing else, ever leaves your '
        'phone. The tap card, the joke, the dice and the emergency path all '
        'keep working.',
    'privacyTitle': 'What leaves your phone',
    'privacyNote': 'The list, in plain words, before you turn anything on.',
    'clearDataTitle': 'Erase everything Puck stored',
    'clearDataAction': 'Erase local data',
    'clearDataConfirm': 'Erase? This cannot be undone.',
    'clearDataDone': 'Erased.',
    'clearDataCancel': 'Keep it',
    'diagnosticsTitle': 'Diagnostics',
    'diagnosticsVersion': 'Version',
    'diagnosticsPlatform': 'Platform',
    'diagnosticsCloud': 'Cloud answers',
    'diagnosticsCloudOn': 'on',
    'diagnosticsCloudOff': 'off',
    'diagnosticsSpeech': 'Speech input',
    'diagnosticsUnavailable': 'unavailable',
    'diagnosticsAvailable': 'available',
    'feedbackTitle': 'Tell the maker',
    'feedbackNote': 'Opens your mail app with the version and a short status '
        'block. No personal data is included.',
    'feedbackAction': 'Send feedback',
    'feedbackNoMail': 'No mail app on this device.',
    'privacyScreenTitle': 'What leaves your phone',
    'privacyIntro': 'Puck sends something only when you ask it to answer a '
        'question. Here is the whole list.',
    'privacySendsTitle': 'Sent with a question',
    'privacyQuestion': 'The question you typed or said.',
    'privacyEventTitle': 'The title of your next calendar event, if one is '
        'close.',
    'privacyEventWhen': 'Whether that event has started, and how long until it '
        'does.',
    'privacyEventWhere': 'The event location, if the calendar entry has one.',
    'privacyBattery': 'Your battery level and whether it is charging.',
    'privacyWeather': 'The current temperature and weather where you are, from '
        'Open-Meteo.',
    'privacyTime': 'Your local time.',
    'privacyDeviceId': 'A random ID for this app install, used only to count '
        'requests so one phone cannot use everything. Reset it any time.',
    'privacyNeverTitle': 'Never sent',
    'privacyNeverBody': 'No location coordinates, no contacts, no messages, no '
        'calendar contents, no name, no email, no advertising ID. There is no '
        'account, no analytics and no crash reporting.',
    'privacyAttribution': 'Weather by Open-Meteo (CC BY 4.0). Answers by Groq. '
        'Both are listed because both can see what is above in this list.',
    'coinHeads': 'Heads.',
    'coinTails': 'Tails.',
    'sosMessage': 'I need help.',
    'sosMessageNoLocation': 'Location unavailable.',
    'callEmergencyHint': 'Opens the dialer with the number ready. '
        'You press call.',
    'busyLabel': 'Busy',
    'offlineLine': 'Offline. Try coin, dice, or maths.',
    'answerKeyRejected': 'That key was refused. Fix or clear it in Settings; '
        'coin, dice and maths still work.',
    'safetyLine': 'I cannot help with this. Please contact a local emergency '
        'number or a crisis line now.',
    'jokeFallback': 'The jokes only work in English so far. The button does '
        'not.',
  };

  /// Per-language overrides. A key absent here falls back to English, which is
  /// deliberate and visible rather than silent -- see [untranslatedKeys].
  static const Map<String, Map<String, String>> _translations =
      <String, Map<String, String>>{
    'en': _en,
    'es': stringsEs,
  };
}
