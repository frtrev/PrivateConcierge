import '../../core/models/local_query.dart';
import '../../core/models/poi.dart';

class ConversationSnapshot {
  const ConversationSnapshot({
    required this.createdAt,
    required this.intent,
    required this.results,
    this.selectedPoi,
  });

  final DateTime createdAt;
  final LocalQueryIntent intent;
  final List<PointOfInterest> results;
  final PointOfInterest? selectedPoi;
}

abstract interface class ConversationContext {
  ConversationSnapshot? get current;
  void remember(LocalQueryIntent intent, LocalQueryResult result);
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
  void remember(LocalQueryIntent intent, LocalQueryResult result) {
    if (result.status != QueryResultStatus.success) return;
    final previous = current;
    final results = result.places.isEmpty
        ? previous?.results ?? const <PointOfInterest>[]
        : result.places;
    _snapshot = ConversationSnapshot(
      createdAt: _clock(),
      intent: intent,
      results: List.unmodifiable(results.take(maxResults)),
      selectedPoi: result.selectedPoi ?? previous?.selectedPoi,
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
      category: query.category,
      name: query.name,
      secondName: query.secondName,
      radiusMiles: query.radiusMiles,
      limit: query.limit,
      candidatePois: query.usesPreviousResults
          ? snapshot?.results ?? const []
          : const [],
      selectedPoi: query.usesPreviousSelection ? snapshot?.selectedPoi : null,
    );
  }
}
