import 'dart:ui' show Locale;

/// The one category of question Puck refuses to improvise an answer to.
///
/// # Why this exists
///
/// Every other question goes to the model when the network is there. "I want
/// to kill myself" must not: a 20-billion-parameter model on a card that
/// disappears after eleven seconds is not a crisis service, and the cost of
/// pretending otherwise is measured in funerals. The app's own rules say the
/// model may never originate facts -- this is the case where a *wrong* fact is
/// not the failure mode, and the failure mode is the thing the user does next.
///
/// So the check is local, deterministic, and happens before anything else:
/// the question never leaves the phone, no request is billed, and the answer
/// is the fixed line in `PuckStrings.safetyLine` -- short, localized, and
/// pointing at real help (an emergency number or a crisis line) rather than at
/// a chatbot.
///
/// # What it deliberately does not do
///
/// * It does not try to be a classifier. It is a narrow phrase list, and it is
///   meant to be conservative: it catches a person saying the thing plainly,
///   in the first person, in one of the languages Puck ships. Anything subtler
///   is a decision for a clinician and a lawyer, not for this file -- see
///   FINDINGS.md, "the assistant safety boundary".
/// * It does not name a crisis line. Puck has no verified, per-region,
///   kept-current database of them, and inventing a number is worse than
///   pointing at the emergency number the device already knows (see
///   `EmergencyNumbers`).
/// * It does not block the topic. "How do crisis lines work?" is a question,
///   not an emergency; the patterns require first-person, immediate phrasing.
///
/// # Language
///
/// Phrases are tagged by language for maintenance only. All of them are
/// checked regardless of the UI locale, because the language someone types in
/// is not the language their phone's interface is set to -- and because no
/// phrase on this list means anything harmless in another language. This is
/// the opposite of the resolver's per-language policy, on purpose: there, a
/// wrong match produces a wrong answer, so an unknown language must match
/// nothing. Here, a missing match means a crisis question reaches a language
/// model.
class PuckSafety {
  const PuckSafety._();

  static const Map<String, List<String>> _phrases = <String, List<String>>{
    'en': <String>[
      // Self-harm, first person and immediate.
      r'kill (myself|me)',
      r'killing myself',
      r'end (my|it all)',
      r'take my own life',
      r'want to die',
      r'wanna die',
      r'wish i (was|were) dead',
      r'better off dead',
      r'no reason to live',
      r'suicid',
      r'self[- ]harm',
      r'hurt(ing)? myself',
      r'cut(ting)? myself',
      r'overdos(e|ed|ing)',
      r'took too many (pills|tablets)',
      // Medical emergency, in progress.
      r'chest pain',
      r'heart attack',
      r"can'?t breathe",
      r'cannot breathe',
      r'stopped breathing',
      r'severe bleeding',
      r'bleeding (badly|a lot|heavily)',
      r"won'?t stop bleeding",
      r'having a stroke',
      r'anaphyla',
      // Someone else, right now.
      r'someone is following me',
      r'being followed',
      r'(someone|he|she|they) (is |are )?(attacking|choking|hurting) me',
      r'(he|she|they) has a (knife|gun)',
      r'someone (broke|is breaking) in',
    ],
    'es': <String>[
      r'quiero morir',
      r'quiero morirme',
      r'matarme',
      r'quitarme la vida',
      r'acabar con mi vida',
      r'no quiero vivir',
      r'suicid',
      r'hacerme da[nñ]o',
      r'cortarme',
      r'sobredosis',
      r'tom[eé] (muchas|demasiadas) pastillas',
      r'dolor (en el pecho|de pecho)',
      r'ataque al coraz[oó]n',
      r'infarto',
      r'no puedo respirar',
      r'me estoy ahogando',
      r'sangrado (abundante|fuerte)',
      r'no para de sangrar',
      r'me est[aá]n? (siguiendo|atacando)',
      r'me sigue alguien',
      r'alguien me sigue',
      r'tiene (un cuchillo|una pistola|un arma)',
      r'entraron a mi casa',
    ],
  };

  /// Compiled once: this runs on every question, before anything else does.
  static final List<RegExp> _compiled = <RegExp>[
    for (final List<String> phrases in _phrases.values)
      for (final String phrase in phrases) RegExp(phrase),
  ];

  /// True when the request is a crisis, in any language Puck knows.
  static bool isCrisis(String query, {Locale locale = const Locale('en')}) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return false;

    // `locale` is accepted so a caller can state which language it *believes*
    // the text is in, and deliberately not used to narrow the match: the
    // language someone types in is not the language their phone is set to, and
    // a missed crisis is the more expensive mistake. See the class note.
    for (final RegExp pattern in _compiled) {
      if (pattern.hasMatch(q)) return true;
    }
    return false;
  }
}
