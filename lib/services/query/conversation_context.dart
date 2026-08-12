import '../../core/models/local_query.dart';
import '../../core/models/place_query.dart';
import '../../core/models/poi.dart';

class ConversationSnapshot {
  const ConversationSnapshot({
    required this.createdAt,
    required this.intent,
    required this.results,
    this.selectedPoi,
    this.placeQuery,
  });

  final DateTime createdAt;
  final LocalQueryIntent intent;
  final List<PointOfInterest> results;
  final PointOfInterest? selectedPoi;
  final PlaceQuery? placeQuery;
}

abstract interface class ConversationContext {
  ConversationSnapshot? get current;
  void remember(QueryPlan plan, LocalQueryResult result);
  void clear();
}

class BoundedConversationContext implements ConversationContext {
  BoundedConversationContext({
    this.ttl = const Duration(minutes: 10),
    this.maxResults = 10,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration ttl;
  final int maxResults;
  final DateTime Function() _clock;
  ConversationSnapshot? _snapshot;

  @override
  ConversationSnapshot? get current {
    final value = _snapshot;
    if (value != null && _clock().difference(value.createdAt) > ttl) {
      _snapshot = null;
      return null;
    }
    return value;
  }

  @override
  void remember(QueryPlan plan, LocalQueryResult result) {
    if (result.status != QueryResultStatus.success) return;
    final previous = current;
    final results = result.places.isEmpty
        ? previous?.results ?? const <PointOfInterest>[]
        : result.places;
    _snapshot = ConversationSnapshot(
      createdAt: _clock(),
      intent: plan.intent,
      results: List.unmodifiable(results.take(maxResults)),
      selectedPoi:
          result.selectedPoi ??
          (result.places.length == 1
              ? result.places.first
              : previous?.selectedPoi),
      placeQuery: plan.placeQuery ?? previous?.placeQuery,
    );
  }

  @override
  void clear() => _snapshot = null;
}

class QueryContextResolver {
  const QueryContextResolver(this.context);
  final ConversationContext context;

  QueryPlan resolve(ParsedQuery query) {
    final snapshot = context.current;
    return QueryPlan(
      intent: query.intent,
      operation: query.operation,
      confidence: query.confidence,
      category:
          query.category ??
          ((query.usesPreviousResults || query.usesPreviousSelection)
              ? snapshot?.placeQuery?.category
              : null),
      name: query.name,
      secondName: query.secondName,
      radiusMiles: query.radiusMiles,
      limit: query.limit,
      candidatePois: query.usesPreviousResults
          ? snapshot?.results ?? const []
          : const [],
      selectedPoi: query.usesPreviousSelection ? snapshot?.selectedPoi : null,
      placeQuery:
          query.placeQuery ??
          ((query.usesPreviousResults || query.usesPreviousSelection)
              ? snapshot?.placeQuery
              : null),
    );
  }
}
