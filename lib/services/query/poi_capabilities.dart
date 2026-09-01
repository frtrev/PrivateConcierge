import '../../core/models/local_query.dart';
import '../../core/models/poi.dart';
import '../nearby/nearby_service.dart';
import 'place_search_service.dart';
import 'query_capability.dart';

const _metersPerMile = 1609.344;

class FindPoiCapability implements QueryCapability {
  FindPoiCapability(this.nearby)
    : structuredSearch = StructuredPlaceSearch(
        retriever: PlaceCandidateRetriever(nearby),
      );
  final NearbyService nearby;
  final StructuredPlaceSearch structuredSearch;
  @override
  String get id => 'find_poi';
  @override
  Set<LocalQueryIntent> get supportedIntents => const {
    LocalQueryIntent.findPoi,
  };

  @override
  Future<LocalQueryResult> execute(
    QueryPlan plan,
    QueryExecutionContext context,
  ) async {
    if (plan.operation == QueryOperation.highestRated) {
      return const LocalQueryResult(
        status: QueryResultStatus.unavailable,
        detail: 'Ratings are not included in the downloaded place data yet.',
      );
    }
    final placeQuery = plan.placeQuery;
    var points = plan.candidatePois;
    if (points.isEmpty && placeQuery != null) {
      final origin = context.origin;
      if (origin == null) {
        return const LocalQueryResult(status: QueryResultStatus.unavailable);
      }
      final outcome = await structuredSearch.search(
        origin,
        placeQuery,
        radiusMeters: (plan.radiusMiles ?? 15) * _metersPerMile,
      );
      var matches = outcome.matches;
      if (placeQuery.openNow == true) {
        final withHours = matches
            .where((value) => value.place.openingHours != null)
            .toList(growable: false);
        if (withHours.isEmpty) {
          return const LocalQueryResult(
            status: QueryResultStatus.unavailable,
            detail:
                'The matching place data does not include reliable opening hours, so I cannot verify what is open now.',
          );
        }
        matches = withHours
            .where(
              (value) => value.place.openingHours!.isOpenAt(DateTime.now()),
            )
            .toList(growable: false);
      }
      final limited = matches
          .take(plan.limit)
          .map((value) => value.place)
          .toList(growable: false);
      if (limited.isEmpty) {
        return LocalQueryResult(
          status: QueryResultStatus.empty,
          alternativePoi: outcome.alternative,
          candidatesRetrieved: outcome.retrievedCount,
          candidatesMatched: 0,
        );
      }
      return LocalQueryResult(
        status: QueryResultStatus.success,
        places: limited,
        selectedPoi: plan.limit == 1 ? limited.first : null,
        candidatesRetrieved: outcome.retrievedCount,
        candidatesMatched: matches.length,
        selectedMatchScore: matches.first.score,
      );
    }
    if (points.isEmpty) {
      final origin = context.origin;
      if (origin == null) {
        return const LocalQueryResult(status: QueryResultStatus.unavailable);
      }
      points = await nearby.search(
        origin,
        category: plan.category,
        query: plan.name,
        radiusMeters: (plan.radiusMiles ?? 15) * _metersPerMile,
      );
    }
    if (points.isEmpty) {
      return const LocalQueryResult(status: QueryResultStatus.empty);
    }
    final limited = points.take(plan.limit).toList(growable: false);
    return LocalQueryResult(
      status: QueryResultStatus.success,
      places: limited,
      selectedPoi: plan.limit == 1 ? limited.first : null,
    );
  }
}

class DistanceCapability implements QueryCapability {
  const DistanceCapability(this.nearby);
  final NearbyService nearby;
  @override
  String get id => 'distance_to';
  @override
  Set<LocalQueryIntent> get supportedIntents => const {
    LocalQueryIntent.distanceTo,
  };

  @override
  Future<LocalQueryResult> execute(
    QueryPlan plan,
    QueryExecutionContext context,
  ) async {
    final origin = context.origin;
    if (origin == null) {
      return const LocalQueryResult(status: QueryResultStatus.unavailable);
    }
    var points = plan.candidatePois;
    if (points.isEmpty) {
      points = await nearby.search(
        origin,
        category: plan.category,
        query: plan.name,
      );
    }
    if (points.isEmpty) {
      return const LocalQueryResult(status: QueryResultStatus.empty);
    }
    return LocalQueryResult(
      status: QueryResultStatus.success,
      places: [points.first],
      selectedPoi: points.first,
    );
  }
}

class ComparisonCapability implements QueryCapability {
  const ComparisonCapability(this.nearby);
  final NearbyService nearby;
  @override
  String get id => 'compare_distance';
  @override
  Set<LocalQueryIntent> get supportedIntents => const {
    LocalQueryIntent.compareDistance,
  };

  @override
  Future<LocalQueryResult> execute(
    QueryPlan plan,
    QueryExecutionContext context,
  ) async {
    final origin = context.origin;
    if (origin == null) {
      return const LocalQueryResult(status: QueryResultStatus.unavailable);
    }
    final first = await nearby.search(
      origin,
      query: plan.name,
      radiusMeters: 50 * _metersPerMile,
    );
    final second = await nearby.search(
      origin,
      query: plan.secondName,
      radiusMeters: 50 * _metersPerMile,
    );
    if (first.isEmpty || second.isEmpty) {
      return const LocalQueryResult(
        status: QueryResultStatus.empty,
        detail: 'I could not find both named places in the downloaded region.',
      );
    }
    final ordered = <PointOfInterest>[first.first, second.first]
      ..sort((a, b) => a.distanceMeters!.compareTo(b.distanceMeters!));
    return LocalQueryResult(
      status: QueryResultStatus.success,
      places: ordered,
      selectedPoi: ordered.first,
      comparisonPoi: ordered.last,
    );
  }
}

class NavigationCapability implements QueryCapability {
  const NavigationCapability(this.nearby);
  final NearbyService nearby;
  @override
  String get id => 'navigate_to';
  @override
  Set<LocalQueryIntent> get supportedIntents => const {
    LocalQueryIntent.navigate,
  };

  @override
  Future<LocalQueryResult> execute(
    QueryPlan plan,
    QueryExecutionContext context,
  ) async {
    var selected = plan.selectedPoi;
    if (selected == null && plan.candidatePois.isNotEmpty) {
      final candidates = [...plan.candidatePois]
        ..sort(
          (a, b) => (a.distanceMeters ?? double.infinity).compareTo(
            b.distanceMeters ?? double.infinity,
          ),
        );
      selected = candidates.first;
    }
    if (selected == null && plan.name != null && context.origin != null) {
      final matches = await nearby.search(
        context.origin!,
        category: plan.category,
        query: plan.name,
        radiusMeters: 50 * _metersPerMile,
      );
      if (matches.isNotEmpty) selected = matches.first;
    }
    if (selected == null && plan.category != null && context.origin != null) {
      final matches = await nearby.search(
        context.origin!,
        category: plan.category,
        radiusMeters: 50 * _metersPerMile,
      );
      if (matches.isNotEmpty) selected = matches.first;
    }
    if (selected == null) {
      return const LocalQueryResult(
        status: QueryResultStatus.clarification,
        detail: 'Which place would you like directions to?',
      );
    }
    return LocalQueryResult(
      status: QueryResultStatus.success,
      places: [selected],
      selectedPoi: selected,
      navigationRequested: true,
    );
  }
}
