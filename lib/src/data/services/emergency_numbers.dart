import 'dart:ui' show Locale;

/// The number to dial when Puck has no one to text.
///
/// For most of the people who will ever install Puck, "no emergency contact
/// configured" *is* the default state, and an SOS sheet that says "no contact
/// set" and stops is inert exactly where it matters most.
///
/// What this is not: a guess that could put the wrong number under a shaking
/// thumb. Every entry is the public emergency number of that region, the
/// number is always shown as text next to the action ("Call 112"), and the
/// dialer -- never a call -- is what opens. A wrong or missing entry therefore
/// costs a visible correction, not a mis-dial.
class EmergencyNumbers {
  const EmergencyNumbers._();

  /// Used when the region is unknown. 112 is the GSM standard emergency
  /// number: it routes to local emergency services in the EU and in most of
  /// the world, and it is accepted by every GSM handset even with no SIM and
  /// no keypad unlock.
  static const String fallback = '112';

  /// Region -> number. Deliberately only regions where the number is
  /// unambiguous; anything absent falls back to [fallback] rather than being
  /// guessed at.
  static const Map<String, String> _byRegion = <String, String>{
    'US': '911', 'CA': '911', 'MX': '911', // North America
    'GB': '999', 'IE': '999', 'IM': '999', 'JE': '999', 'GG': '999',
    'AU': '000', 'NZ': '111',
    'IN': '112', 'PK': '1122', 'BD': '999', 'LK': '119', 'NP': '112',
    'CN': '110', 'JP': '119', 'KR': '119', 'TW': '110', 'HK': '999',
    'SG': '999', 'MY': '999', 'TH': '191', 'VN': '113', 'PH': '911',
    'ID': '112', 'KH': '119', 'MM': '199',
    'BR': '190', 'AR': '911', 'CL': '133', 'CO': '123', 'PE': '105',
    'VE': '911', 'EC': '911', 'UY': '911', 'PY': '911', 'BO': '110',
    'ZA': '112', 'NG': '112', 'KE': '999', 'EG': '112', 'MA': '190',
    'GH': '112', 'TZ': '112', 'UG': '112', 'ET': '112',
    'RU': '112', 'UA': '112', 'TR': '112', 'IL': '100', 'SA': '911',
    'AE': '999', 'QA': '999', 'KW': '112', 'JO': '911', 'LB': '112',
    'IR': '115', 'IQ': '104',
    // The EU / EEA / most of Europe -- 112 everywhere.
    'AT': '112', 'BE': '112', 'BG': '112', 'CH': '112', 'CY': '112',
    'CZ': '112', 'DE': '112', 'DK': '112', 'EE': '112', 'ES': '112',
    'FI': '112', 'FR': '112', 'GR': '112', 'HR': '112', 'HU': '112',
    'IS': '112', 'IT': '112', 'LI': '112', 'LT': '112', 'LU': '112',
    'LV': '112', 'MT': '112', 'NL': '112', 'NO': '112', 'PL': '112',
    'PT': '112', 'RO': '112', 'SE': '112', 'SI': '112', 'SK': '112',
    'RS': '112', 'BA': '112', 'MK': '112', 'AL': '112', 'MD': '112',
  };

  /// The number to offer, and the region it belongs to.
  ///
  /// Region comes from the device locale, which is the only signal available
  /// without a permission: the SIM's country needs `READ_PHONE_STATE` (a
  /// restricted permission and an unreasonable ask for a dialer shortcut),
  /// and the network country needs a location-grade permission on modern
  /// Android. A locale is a good proxy for "where am I" -- and when it is
  /// wrong, the number is on screen before anything is dialled.
  static EmergencyNumber resolve(Locale? locale) {
    final String region = (locale?.countryCode ?? '').toUpperCase();
    if (region.isEmpty) {
      return const EmergencyNumber(
        number: fallback,
        region: '',
        isRegional: false,
      );
    }
    final String? number = _byRegion[region];
    return EmergencyNumber(
      number: number ?? fallback,
      region: region,
      isRegional: number != null,
    );
  }
}

class EmergencyNumber {
  const EmergencyNumber({
    required this.number,
    required this.region,
    required this.isRegional,
  });

  final String number;

  /// ISO 3166-1 alpha-2, or '' when the locale did not say.
  final String region;

  /// False when this is the [EmergencyNumbers.fallback] rather than a number
  /// confirmed for [region]. The UI says so instead of implying certainty.
  final bool isRegional;

  // There deliberately is no `label` getter here. There used to be one, and it
  // returned the English string "$number (standard emergency line)" -- a
  // user-visible sentence compiled into the data layer, where no locale
  // exists. The wording now comes from [PuckStrings] (`callEmergency`,
  // `sosEmergencyFallbackNote`, `sosEmergencyRegionalNote`), which is the only
  // place in the app allowed to hold words.
}
