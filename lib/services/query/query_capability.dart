import '../../core/models/geo.dart';
import '../../core/models/local_query.dart';

class QueryExecutionContext {
  const QueryExecutionContext({required this.origin});
  final Coordinates? origin;
}

abstract interface class QueryCapability {
  String get id;
  Set<LocalQueryIntent> get supportedIntents;
  Future<LocalQueryResult> execute(
    QueryPlan plan,
    QueryExecutionContext context,
  );
}

class CapabilityRegistry {
  CapabilityRegistry(Iterable<QueryCapability> capabilities)
    : _capabilities = List.unmodifiable(capabilities);
  final List<QueryCapability> _capabilities;

  List<String> get capabilityIds =>
      _capabilities.map((item) => item.id).toList(growable: false);

  Future<LocalQueryResult> execute(
    QueryPlan plan,
    QueryExecutionContext context,
  ) {
    for (final capability in _capabilities) {
      if (capability.supportedIntents.contains(plan.intent)) {
        return capability.execute(plan, context);
      }
    }
    return Future.value(
      const LocalQueryResult(status: QueryResultStatus.unknown),
    );
  }
}
