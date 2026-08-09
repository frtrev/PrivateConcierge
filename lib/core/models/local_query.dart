import 'poi.dart';

enum LocalQueryIntent {
  findPoi,
  distanceTo,
  compareDistance,
  navigate,
  unknown,
}

enum QueryOperation { nearby, nearest, highestRated, withinRadius }

class ParsedQuery {
  const ParsedQuery({
    required this.intent,
    required this.originalText,
    required this.confidence,
    this.operation = QueryOperation.nearby,
    this.category,
    this.name,
    this.secondName,
    this.radiusMiles,
    this.limit = 5,
    this.usesPreviousResults = false,
    this.usesPreviousSelection = false,
  });

  final LocalQueryIntent intent;
  final String originalText;
  final double confidence;
  final QueryOperation operation;
  final String? category;
  final String? name;
  final String? secondName;
  final double? radiusMiles;
  final int limit;
  final bool usesPreviousResults;
  final bool usesPreviousSelection;
}

class QueryPlan {
  const QueryPlan({
    required this.intent,
    required this.operation,
    required this.confidence,
    this.category,
    this.name,
    this.secondName,
    this.radiusMiles,
    this.limit = 5,
    this.candidatePois = const [],
    this.selectedPoi,
  });

  final LocalQueryIntent intent;
  final QueryOperation operation;
  final double confidence;
  final String? category;
  final String? name;
  final String? secondName;
  final double? radiusMiles;
  final int limit;
  final List<PointOfInterest> candidatePois;
  final PointOfInterest? selectedPoi;
}

enum QueryResultStatus { success, empty, clarification, unavailable, unknown }

class LocalQueryResult {
  const LocalQueryResult({
    required this.status,
    this.places = const [],
    this.selectedPoi,
    this.comparisonPoi,
    this.navigationRequested = false,
    this.detail,
  });

  final QueryResultStatus status;
  final List<PointOfInterest> places;
  final PointOfInterest? selectedPoi;
  final PointOfInterest? comparisonPoi;
  final bool navigationRequested;
  final String? detail;
}
