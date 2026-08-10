import '../../core/models/local_query.dart';

abstract interface class QueryInterpreter {
  ParsedQuery interpret(String text);
}

class RuleBasedQueryInterpreter implements QueryInterpreter {
  static const _categories = <String, String>{
    'restaurant': 'restaurant',
    'restaurants': 'restaurant',
    'food': 'restaurant',
    'eat': 'restaurant',
    'dining': 'restaurant',
    'gas station': 'gas',
    'gas': 'gas',
    'fuel': 'gas',
    'pharmacy': 'pharmacy',
    'pharmacies': 'pharmacy',
    'drugstore': 'pharmacy',
    'church': 'church',
    'gym': 'gym',
    'park': 'park',
    'museum': 'museum',
    'grocery': 'grocery',
    'supermarket': 'grocery',
    'movie theater': 'entertainment',
    'movie theatre': 'entertainment',
    'cinema': 'entertainment',
    'theater': 'entertainment',
    'hospital': 'medical',
    'doctor': 'medical',
    'dentist': 'medical',
    'store': 'shopping',
    'shopping': 'shopping',
    'hotel': 'lodging',
    'school': 'education',
  };

  static const _cuisines = <String>{
    'mexican',
    'italian',
    'chinese',
    'indian',
    'thai',
    'japanese',
    'american',
  };

  @override
  ParsedQuery interpret(String text) {
    final normalized = text
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9.' ]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return _unknown(text);

    final refersToSelection = RegExp(
      r'\b(there|it|that place)\b',
    ).hasMatch(normalized);
    if (RegExp(r'\b(take|navigate|directions|route)\b').hasMatch(normalized)) {
      final nearest = RegExp(r'\b(nearest|closest)\b').hasMatch(normalized);
      return ParsedQuery(
        intent: LocalQueryIntent.navigate,
        originalText: text,
        confidence: refersToSelection ? .98 : .82,
        operation: nearest ? QueryOperation.nearest : QueryOperation.nearby,
        category: _findCategory(normalized),
        name: refersToSelection || nearest ? null : _navigationName(normalized),
        usesPreviousSelection: refersToSelection,
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
    final nearest = RegExp(
      r'\b(nearest|closest|closest one|nearest one)\b',
    ).hasMatch(normalized);
    final highestRated = RegExp(
      r'\b(highest|best) rated\b',
    ).hasMatch(normalized);
    final distanceQuestion = RegExp(r'\bhow far\b').hasMatch(normalized);
    final radius = RegExp(
      r'within (\d+(?:\.\d+)?) (mile|miles|mi)\b',
    ).firstMatch(normalized);
    final category = _findCategory(normalized);
    String? cuisine;
    for (final value in _cuisines) {
      if (normalized.contains(value)) {
        cuisine = value;
        break;
      }
    }

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

    final looksLikePoiQuery =
        category != null ||
        cuisine != null ||
        nearest ||
        radius != null ||
        RegExp(r'\b(show|find|where|are there|what)\b').hasMatch(normalized);
    if (!looksLikePoiQuery) return _unknown(text);

    return ParsedQuery(
      intent: distanceQuestion
          ? LocalQueryIntent.distanceTo
          : LocalQueryIntent.findPoi,
      originalText: text,
      confidence: category != null || cuisine != null
          ? .94
          : nearest || radius != null
          ? .82
          : .72,
      operation: nearest
          ? QueryOperation.nearest
          : radius != null
          ? QueryOperation.withinRadius
          : highestRated
          ? QueryOperation.highestRated
          : QueryOperation.nearby,
      category: category ?? (cuisine == null ? null : 'restaurant'),
      name: cuisine,
      radiusMiles: radius == null ? null : double.parse(radius.group(1)!),
      limit: nearest || distanceQuestion || highestRated ? 1 : 5,
    );
  }

  String? _findCategory(String text) {
    for (final entry in _categories.entries) {
      if (RegExp('\\b${RegExp.escape(entry.key)}\\b').hasMatch(text)) {
        return entry.value;
      }
    }
    return null;
  }

  String? _navigationName(String text) {
    final match = RegExp(
      r'(?:to|directions to|route to) (?:the )?(.+)$',
    ).firstMatch(text);
    return match?.group(1)?.trim();
  }

  ParsedQuery _unknown(String text) => ParsedQuery(
    intent: LocalQueryIntent.unknown,
    originalText: text,
    confidence: 0,
  );
}
