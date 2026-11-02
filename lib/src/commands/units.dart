/// The unit table for spoken conversions ("ten kilometres in miles").
///
/// Small on purpose: the conversions a person actually asks a phone for, in
/// the units those people use, each one defined once. Everything is expressed
/// as a factor to a single base unit per kind, so adding a unit is one line and
/// cannot silently disagree with its neighbours. Temperature is the exception
/// and gets its own rule, because 0 °C is not 0 of anything.
library;

enum UnitKind { length, mass, volume, temperature, data, speed, time }

class Unit {
  const Unit({
    required this.id,
    required this.kind,
    required this.factor,
    required this.aliases,
    this.spoken = '',
    this.plural,
  });

  /// Stable identifier, also present in [aliases].
  final String id;
  final UnitKind kind;

  /// How many base units one of these is. Base units: metre, kilogram, litre,
  /// megabyte, kilometre per hour, second. Ignored for temperature.
  final double factor;

  /// Spoken and typed spellings. Lowercase; the resolver lowercases input.
  final List<String> aliases;

  /// How this unit is *said*. Not the symbol: "km" read by a speech synthesiser
  /// is "k m". Empty falls back to [id].
  final String spoken;

  /// Optional irregular plural ("feet", "inches") already included in
  /// [aliases] -- kept separate only to document why it is there.
  final String? plural;

  /// Spoken name for narration.
  String get pronounce => spoken.isEmpty ? id : spoken;

  @override
  String toString() => id;
}

abstract final class Units {
  static const Unit metre = Unit(
    id: 'm',
    spoken: 'meters',
    kind: UnitKind.length,
    factor: 1,
    aliases: <String>['m', 'meter', 'metre', 'meters', 'metres'],
  );
  static const Unit kilometre = Unit(
    id: 'km',
    spoken: 'kilometers',
    kind: UnitKind.length,
    factor: 1000,
    aliases: <String>['km', 'kms', 'kilometer', 'kilometre', 'kilometers',
      'kilometres'],
  );
  static const Unit centimetre = Unit(
    id: 'cm',
    spoken: 'centimeters',
    kind: UnitKind.length,
    factor: 0.01,
    aliases: <String>['cm', 'centimeter', 'centimetre', 'centimeters',
      'centimetres'],
  );
  static const Unit millimetre = Unit(
    id: 'mm',
    spoken: 'millimeters',
    kind: UnitKind.length,
    factor: 0.001,
    aliases: <String>['mm', 'millimeter', 'millimetre', 'millimeters',
      'millimetres'],
  );
  static const Unit inch = Unit(
    id: 'in',
    spoken: 'inches',
    kind: UnitKind.length,
    factor: 0.0254,
    aliases: <String>['inch', 'inches', 'in'],
    // "in" is also a preposition. The parser only resolves a unit from a slot
    // it already knows is a unit ("... to <unit>"), so the ambiguity is
    // contained; the resolver never guesses.
    plural: 'inches',
  );
  static const Unit foot = Unit(
    id: 'ft',
    spoken: 'feet',
    kind: UnitKind.length,
    factor: 0.3048,
    aliases: <String>['ft', 'foot', 'feet'],
    plural: 'feet',
  );
  static const Unit yard = Unit(
    id: 'yd',
    spoken: 'yards',
    kind: UnitKind.length,
    factor: 0.9144,
    aliases: <String>['yd', 'yard', 'yards'],
  );
  static const Unit mile = Unit(
    id: 'mi',
    spoken: 'miles',
    kind: UnitKind.length,
    factor: 1609.344,
    aliases: <String>['mi', 'mile', 'miles'],
  );

  static const Unit gram = Unit(
    id: 'g',
    spoken: 'grams',
    kind: UnitKind.mass,
    factor: 0.001,
    aliases: <String>['g', 'gram', 'grams', 'gramme', 'grammes'],
  );
  static const Unit kilogram = Unit(
    id: 'kg',
    spoken: 'kilograms',
    kind: UnitKind.mass,
    factor: 1,
    aliases: <String>['kg', 'kgs', 'kilo', 'kilos', 'kilogram', 'kilograms'],
  );
  static const Unit milligram = Unit(
    id: 'mg',
    spoken: 'milligrams',
    kind: UnitKind.mass,
    factor: 0.000001,
    aliases: <String>['mg', 'milligram', 'milligrams'],
  );
  static const Unit ounce = Unit(
    id: 'oz',
    spoken: 'ounces',
    kind: UnitKind.mass,
    factor: 0.028349523125,
    aliases: <String>['oz', 'ounce', 'ounces'],
  );
  static const Unit pound = Unit(
    id: 'lb',
    spoken: 'pounds',
    kind: UnitKind.mass,
    factor: 0.45359237,
    aliases: <String>['lb', 'lbs', 'pound', 'pounds'],
  );
  static const Unit stone = Unit(
    id: 'st',
    spoken: 'stone',
    kind: UnitKind.mass,
    factor: 6.35029318,
    aliases: <String>['st', 'stone', 'stones'],
  );
  static const Unit tonne = Unit(
    id: 't',
    spoken: 'tonnes',
    kind: UnitKind.mass,
    factor: 1000,
    aliases: <String>['t', 'tonne', 'tonnes', 'ton', 'tons'],
  );

  static const Unit millilitre = Unit(
    id: 'ml',
    spoken: 'milliliters',
    kind: UnitKind.volume,
    factor: 0.001,
    aliases: <String>['ml', 'milliliter', 'millilitre', 'milliliters',
      'millilitres'],
  );
  static const Unit litre = Unit(
    id: 'l',
    spoken: 'liters',
    kind: UnitKind.volume,
    factor: 1,
    aliases: <String>['l', 'liter', 'litre', 'liters', 'litres'],
  );
  static const Unit cup = Unit(
    id: 'cup',
    spoken: 'cups',
    kind: UnitKind.volume,
    factor: 0.2365882365,
    aliases: <String>['cup', 'cups'],
  );
  static const Unit tablespoon = Unit(
    id: 'tbsp',
    spoken: 'tablespoons',
    kind: UnitKind.volume,
    factor: 0.01478676478,
    aliases: <String>['tbsp', 'tablespoon', 'tablespoons'],
  );
  static const Unit teaspoon = Unit(
    id: 'tsp',
    spoken: 'teaspoons',
    kind: UnitKind.volume,
    factor: 0.00492892159,
    aliases: <String>['tsp', 'teaspoon', 'teaspoons'],
  );
  static const Unit fluidOunce = Unit(
    id: 'floz',
    spoken: 'fluid ounces',
    kind: UnitKind.volume,
    factor: 0.0295735295625,
    aliases: <String>['floz', 'fluid ounce', 'fluid ounces'],
  );
  static const Unit pint = Unit(
    id: 'pt',
    spoken: 'pints',
    kind: UnitKind.volume,
    factor: 0.473176473,
    aliases: <String>['pt', 'pint', 'pints'],
  );
  static const Unit quart = Unit(
    id: 'qt',
    spoken: 'quarts',
    kind: UnitKind.volume,
    factor: 0.946352946,
    aliases: <String>['qt', 'quart', 'quarts'],
  );
  static const Unit gallon = Unit(
    id: 'gal',
    spoken: 'gallons',
    kind: UnitKind.volume,
    // US liquid gallon. A UK gallon is 4.546 L, and a phone that silently
    // picks one of two answers for "a gallon" is worse than one that names
    // the one it used (the narrator says so).
    factor: 3.785411784,
    aliases: <String>['gal', 'gallon', 'gallons'],
  );

  static const Unit celsius = Unit(
    id: 'c',
    spoken: 'degrees Celsius',
    kind: UnitKind.temperature,
    factor: 1,
    aliases: <String>['c', 'celsius', 'centigrade', 'degree celsius',
      'degrees celsius', 'dc'],
  );
  static const Unit fahrenheit = Unit(
    id: 'f',
    spoken: 'degrees Fahrenheit',
    kind: UnitKind.temperature,
    factor: 1,
    aliases: <String>['f', 'fahrenheit', 'degree fahrenheit',
      'degrees fahrenheit', 'df'],
  );
  static const Unit kelvin = Unit(
    id: 'k',
    spoken: 'kelvin',
    kind: UnitKind.temperature,
    factor: 1,
    aliases: <String>['k', 'kelvin'],
  );

  static const Unit megabyte = Unit(
    id: 'mb',
    spoken: 'megabytes',
    kind: UnitKind.data,
    factor: 1,
    aliases: <String>['mb', 'megabyte', 'megabytes', 'mib'],
  );
  static const Unit kilobyte = Unit(
    id: 'kb',
    spoken: 'kilobytes',
    kind: UnitKind.data,
    factor: 0.001,
    aliases: <String>['kb', 'kilobyte', 'kilobytes'],
  );
  static const Unit gigabyte = Unit(
    id: 'gb',
    spoken: 'gigabytes',
    kind: UnitKind.data,
    factor: 1000,
    aliases: <String>['gb', 'gigabyte', 'gigabytes'],
  );
  static const Unit terabyte = Unit(
    id: 'tb',
    spoken: 'terabytes',
    kind: UnitKind.data,
    factor: 1000000,
    aliases: <String>['tb', 'terabyte', 'terabytes'],
  );

  static const Unit kilometrePerHour = Unit(
    id: 'kmh',
    spoken: 'kilometers per hour',
    kind: UnitKind.speed,
    factor: 1,
    aliases: <String>['kmh', 'kph', 'kmph', 'kilometers per hour',
      'kilometres per hour', 'km per hour'],
  );
  static const Unit milePerHour = Unit(
    id: 'mph',
    spoken: 'miles per hour',
    kind: UnitKind.speed,
    factor: 1.609344,
    aliases: <String>['mph', 'miles per hour', 'mile per hour'],
  );

  static const Unit second = Unit(
    id: 's',
    spoken: 'seconds',
    kind: UnitKind.time,
    factor: 1,
    aliases: <String>['s', 'second', 'seconds', 'sec', 'secs'],
  );
  static const Unit minute = Unit(
    id: 'min',
    spoken: 'minutes',
    kind: UnitKind.time,
    factor: 60,
    aliases: <String>['min', 'mins', 'minute', 'minutes'],
  );
  static const Unit hour = Unit(
    id: 'h',
    spoken: 'hours',
    kind: UnitKind.time,
    factor: 3600,
    aliases: <String>['h', 'hr', 'hrs', 'hour', 'hours'],
  );
  static const Unit day = Unit(
    id: 'day',
    spoken: 'days',
    kind: UnitKind.time,
    factor: 86400,
    aliases: <String>['day', 'days'],
  );

  /// Every unit the parser will resolve, in one list.
  static const List<Unit> all = <Unit>[
    metre, kilometre, centimetre, millimetre, inch, foot, yard, mile,
    gram, kilogram, milligram, ounce, pound, stone, tonne,
    millilitre, litre, cup, tablespoon, teaspoon, fluidOunce, pint, quart,
    gallon,
    celsius, fahrenheit, kelvin,
    megabyte, kilobyte, gigabyte, terabyte,
    kilometrePerHour, milePerHour,
    second, minute, hour, day,
  ];

  /// Longest aliases first, so "fluid ounces" is not read as "ounce", and
  /// "km per hour" is not read as "km".
  static final List<Unit> _byAliasLength = <Unit>[...all]
    ..sort((Unit a, Unit b) => _longestAlias(b).compareTo(_longestAlias(a)));

  static int _longestAlias(Unit u) =>
      u.aliases.map((String a) => a.length).reduce((int a, int b) => a > b ? a : b);

  static final Map<String, Unit> _aliasIndex = <String, Unit>{
    for (final Unit unit in all)
      for (final String alias in unit.aliases) alias: unit,
  };

  /// Resolve a spoken or typed unit name. Null when it is not a unit -- the
  /// caller decides what that means, and the parser uses it to fail closed.
  static Unit? resolve(String token) {
    final String cleaned = token
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[°º]'), ' ')
        .replaceAll(RegExp(r'\bdegrees?\b'), ' degree ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    for (final Unit unit in _byAliasLength) {
      for (final String alias in unit.aliases) {
        if (cleaned == alias) return unit;
      }
    }
    // Trailing plural without an explicit alias ("kilograms" is an alias, but
    // a translator's "kilogrammes" may not be).
    if (cleaned.endsWith('s')) {
      final Unit? singular = _aliasIndex[cleaned.substring(0, cleaned.length - 1)];
      if (singular != null) return singular;
    }
    return null;
  }

  /// Convert [value] from [from] to [to]. Null when the kinds differ -- "5 kg
  /// in miles" has no answer, and the parser turns that into "I cannot convert
  /// those".
  static double? convert(double value, Unit from, Unit to) {
    if (from.kind != to.kind) return null;
    if (from.kind == UnitKind.temperature) {
      final double celsius = switch (from.id) {
        'c' => value,
        'f' => (value - 32) * 5 / 9,
        'k' => value - 273.15,
        _ => value,
      };
      return switch (to.id) {
        'c' => celsius,
        'f' => celsius * 9 / 5 + 32,
        'k' => celsius + 273.15,
        _ => celsius,
      };
    }
    return value * from.factor / to.factor;
  }
}
