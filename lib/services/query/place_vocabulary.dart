class PlaceBrand {
  const PlaceBrand({
    required this.name,
    required this.category,
    required this.aliases,
  });

  final String name;
  final String category;
  final Set<String> aliases;
}

class PlaceVocabulary {
  const PlaceVocabulary();

  static const categoryPhrases = <String, String>{
    'place to eat': 'restaurant',
    'places to eat': 'restaurant',
    'fast food': 'restaurant',
    'restaurants': 'restaurant',
    'restaurant': 'restaurant',
    'dining': 'restaurant',
    'food': 'restaurant',
    'gas stations': 'gas',
    'gas station': 'gas',
    'fuel station': 'gas',
    'fuel': 'gas',
    'gas': 'gas',
    'drugstore': 'pharmacy',
    'pharmacies': 'pharmacy',
    'pharmacy': 'pharmacy',
    'grocery store': 'grocery',
    'supermarket': 'grocery',
    'grocery': 'grocery',
    'hardware store': 'hardware',
    'movie theater': 'entertainment',
    'movie theatre': 'entertainment',
    'cinema': 'entertainment',
    'theater': 'entertainment',
    'church': 'church',
    'gym': 'gym',
    'park': 'park',
    'museum': 'museum',
    'hospital': 'medical',
    'doctor': 'medical',
    'dentist': 'medical',
    'store': 'shopping',
    'shopping': 'shopping',
    'hotel': 'lodging',
    'school': 'education',
    'cafe': 'restaurant',
    'coffee shop': 'restaurant',
  };

  static const brands = <PlaceBrand>[
    PlaceBrand(name: 'BP', category: 'gas', aliases: {'bp', 'b p'}),
    PlaceBrand(name: 'Shell', category: 'gas', aliases: {'shell'}),
    PlaceBrand(name: 'Exxon', category: 'gas', aliases: {'exxon'}),
    PlaceBrand(name: 'Marathon', category: 'gas', aliases: {'marathon'}),
    PlaceBrand(name: 'Chevron', category: 'gas', aliases: {'chevron'}),
    PlaceBrand(
      name: 'Starbucks',
      category: 'restaurant',
      aliases: {'starbucks'},
    ),
    PlaceBrand(
      name: "McDonald's",
      category: 'restaurant',
      aliases: {'mcdonalds', "mcdonald's", 'mc donalds'},
    ),
    PlaceBrand(
      name: "Wendy's",
      category: 'restaurant',
      aliases: {'wendys', "wendy's"},
    ),
    PlaceBrand(
      name: 'Taco Bell',
      category: 'restaurant',
      aliases: {'taco bell'},
    ),
    PlaceBrand(name: 'Walmart', category: 'shopping', aliases: {'walmart'}),
    PlaceBrand(name: 'Target', category: 'shopping', aliases: {'target'}),
    PlaceBrand(
      name: 'Home Depot',
      category: 'hardware',
      aliases: {'home depot', 'the home depot'},
    ),
    PlaceBrand(
      name: "Lowe's",
      category: 'hardware',
      aliases: {'lowes', "lowe's"},
    ),
  ];

  static const cuisines = <String>{
    'mexican',
    'italian',
    'chinese',
    'indian',
    'thai',
    'japanese',
    'american',
  };

  static const numberWords = <String, int>{
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
  };

  PlaceBrand? findBrand(String normalizedText) {
    for (final brand in brands) {
      for (final alias in brand.aliases) {
        if (containsPhrase(normalizedText, alias)) return brand;
      }
    }
    return null;
  }

  MapEntry<String, String>? findCategory(String normalizedText) {
    final entries = categoryPhrases.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));
    for (final entry in entries) {
      if (containsPhrase(normalizedText, entry.key)) return entry;
    }
    return null;
  }

  static String normalize(String value) => value
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r"[^a-z0-9' ]"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String normalizeName(String value) =>
      normalize(value.replaceAll("'", ''));

  static bool containsPhrase(String text, String phrase) {
    final normalizedText = normalizeName(text);
    final normalizedPhrase = normalizeName(phrase);
    return RegExp(
      '(?:^|\\s)${RegExp.escape(normalizedPhrase)}(?:\\s|\$)',
    ).hasMatch(normalizedText);
  }
}
