import '../../core/models/local_query.dart';
import '../../core/models/place_query.dart';
import 'place_vocabulary.dart';

abstract interface class QueryInterpreter {
  ParsedQuery interpret(String text);
}

class RuleBasedQueryInterpreter implements QueryInterpreter {
  const RuleBasedQueryInterpreter({this.vocabulary = const PlaceVocabulary()});

  final PlaceVocabulary vocabulary;

  @override
  ParsedQuery interpret(String text) {
    final normalized = PlaceVocabulary.normalize(text);
    if (normalized.isEmpty) return _unknown(text);

    if (RegExp(
      r'^(yes|yes please|sure|okay|ok|please do|go ahead|take me there)$',
    ).hasMatch(normalized)) {
      return ParsedQuery(
        intent: LocalQueryIntent.navigate,
        originalText: text,
        confidence: .98,
        usesPreviousSelection: true,
        limit: 1,
      );
    }

    final refersToSelection = RegExp(
      r'\b(there|it|that place)\b',
    ).hasMatch(normalized);
    final mapAction = RegExp(
      r'\b(take|navigate|directions|route)\b|\bopen\b.*\bmaps?\b|\bshow\b.*\bmaps?\b',
    ).hasMatch(normalized);
    if (mapAction) {
      final nearest = _hasDistanceIntent(normalized);
      final refersToResults = RegExp(
        r'\b(closest one|nearest one)\b',
      ).hasMatch(normalized);
      return ParsedQuery(
        intent: LocalQueryIntent.navigate,
        originalText: text,
        confidence: refersToSelection ? .98 : .82,
        operation: nearest ? QueryOperation.nearest : QueryOperation.nearby,
        category: vocabulary.findCategory(normalized)?.value,
        name: refersToSelection || refersToResults || nearest
            ? null
            : _navigationName(normalized),
        usesPreviousSelection: refersToSelection,
        usesPreviousResults: refersToResults,
        limit: 1,
      );
    }

    final comparison = RegExp(
      r'which is (?:closer|nearest),? (.+?) or (.+)$',
    ).firstMatch(normalized);
    if (comparison != null) {
      return ParsedQuery(
        intent: LocalQueryIntent.compareDistance,
        originalText: text,
        confidence: .96,
        name: comparison.group(1)!.trim(),
        secondName: comparison.group(2)!.trim(),
        limit: 2,
      );
    }

    final priorResults = RegExp(
      r'\b(which|what) (one|of these)\b',
    ).hasMatch(normalized);
    final nearest = _hasDistanceIntent(normalized);
    final highestRated = RegExp(
      r'\b(highest|best) rated\b',
    ).hasMatch(normalized);
    final distanceQuestion = RegExp(r'\bhow far\b').hasMatch(normalized);
    if (priorResults && (nearest || highestRated)) {
      return ParsedQuery(
        intent: distanceQuestion
            ? LocalQueryIntent.distanceTo
            : LocalQueryIntent.findPoi,
        originalText: text,
        confidence: .96,
        operation: highestRated
            ? QueryOperation.highestRated
            : QueryOperation.nearest,
        usesPreviousResults: true,
        limit: 1,
      );
    }

    final radius = RegExp(
      r'within (\d+(?:\.\d+)?) (mile|miles|mi)\b',
    ).firstMatch(normalized);
    final brand = vocabulary.findBrand(normalized);
    final categoryMatch = vocabulary.findCategory(normalized);
    final typeSearch = vocabulary.findTypeSearchTerm(normalized);
    var category = categoryMatch?.value ?? brand?.category;
    if (typeSearch?.value == 'donut') category = null;
    final cuisines = PlaceVocabulary.cuisines.where(
      (value) => PlaceVocabulary.containsPhrase(normalized, value),
    );
    final cuisine = cuisines.isEmpty ? null : cuisines.first;
    final openNow = RegExp(
      r"\b(open now|open|that's open|that is open)\b",
    ).hasMatch(normalized);
    final explicitLimit = _findLimit(normalized);
    final limit =
        explicitLimit ?? (nearest || distanceQuestion || highestRated ? 1 : 5);
    final hasPlaceAction = RegExp(
      r'\b(show|find|where|are there|what|top)\b',
    ).hasMatch(normalized);
    final possibleNamedTerm = brand == null && hasPlaceAction
        ? _genericSearchTerm(normalized)
        : null;
    final isProbableBusinessName =
        possibleNamedTerm != null &&
        possibleNamedTerm.split(' ').length >= 3 &&
        !PlaceVocabulary.typeSearchTerms.keys.any(
          (value) => PlaceVocabulary.normalizeName(value) == possibleNamedTerm,
        );
    final genericTerm = category == null || isProbableBusinessName
        ? possibleNamedTerm
        : null;
    final searchTerm = cuisine ?? typeSearch?.value ?? genericTerm;

    final looksLikePoiQuery =
        category != null ||
        brand != null ||
        searchTerm != null ||
        nearest ||
        radius != null ||
        hasPlaceAction;
    if (!looksLikePoiQuery) return _unknown(text);

    final operation = nearest
        ? QueryOperation.nearest
        : radius != null
        ? QueryOperation.withinRadius
        : highestRated
        ? QueryOperation.highestRated
        : QueryOperation.nearby;
    final placeQuery = PlaceQuery(
      category: category ?? (cuisine == null ? null : 'restaurant'),
      brand: brand?.name,
      searchTerm: searchTerm,
      openNow: openNow ? true : null,
      limit: limit,
      sort: nearest || RegExp(r'\bnearby\b').hasMatch(normalized)
          ? PlaceSort.distance
          : PlaceSort.relevance,
    );
    return ParsedQuery(
      intent: distanceQuestion
          ? LocalQueryIntent.distanceTo
          : LocalQueryIntent.findPoi,
      originalText: text,
      confidence: category != null || brand != null || cuisine != null
          ? .96
          : nearest || radius != null
          ? .82
          : .72,
      operation: operation,
      category: placeQuery.category,
      name: placeQuery.searchTerm,
      radiusMiles: radius == null ? null : double.parse(radius.group(1)!),
      limit: placeQuery.limit,
      placeQuery: placeQuery,
    );
  }

  bool _hasDistanceIntent(String text) =>
      RegExp(r'\b(nearest|closest|closest one|nearest one)\b').hasMatch(text);

  int? _findLimit(String text) {
    final topNumeric = RegExp(r'\btop\s+(\d{1,2})\b').firstMatch(text);
    if (topNumeric != null) {
      return int.parse(topNumeric.group(1)!).clamp(1, 20);
    }
    final numeric = RegExp(
      r'\b(\d{1,2})\s+(?:closest|nearest|nearby|restaurants?|places?|stores?|stations?)\b',
    ).firstMatch(text);
    if (numeric != null) return int.parse(numeric.group(1)!).clamp(1, 20);
    for (final entry in PlaceVocabulary.numberWords.entries) {
      if (RegExp('\\btop\\s+${entry.key}\\b').hasMatch(text)) {
        return entry.value;
      }
      if (RegExp(
        '\\b${entry.key}\\s+(?:closest|nearest|nearby|restaurants?|places?|stores?|stations?)\\b',
      ).hasMatch(text)) {
        return entry.value;
      }
    }
    return null;
  }

  String? _genericSearchTerm(String text) {
    var value = text.replaceAll(
      RegExp(
        r'\btop\s+(?:\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten)\b',
      ),
      ' ',
    );
    const removable = <String>[
      'where is',
      "where's",
      'what is',
      'show me',
      'find me',
      'find',
      'the',
      'a',
      'an',
      'closest',
      'nearest',
      'nearby',
      'open now',
      'open',
      'that is',
      'that are',
      "that's",
      'which is',
      'please',
    ];
    for (final phrase in removable) {
      value = value.replaceAll(
        RegExp('(?:^|\\s)${RegExp.escape(phrase)}(?=\\s|\$)'),
        ' ',
      );
    }
    value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return value.isEmpty ? null : value;
  }

  String? _navigationName(String text) {
    final match = RegExp(
      r'(?:to|directions to|route to|open|show) (?:the )?(.+?)(?: in maps?| on the maps?)?$',
    ).firstMatch(text);
    return match?.group(1)?.trim();
  }

  ParsedQuery _unknown(String text) => ParsedQuery(
    intent: LocalQueryIntent.unknown,
    originalText: text,
    confidence: 0,
  );
}
