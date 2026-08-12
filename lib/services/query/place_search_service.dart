import '../../core/models/geo.dart';
import '../../core/models/place_query.dart';
import '../../core/models/poi.dart';
import '../nearby/nearby_service.dart';
import 'place_matcher.dart';

class PlaceSearchOutcome {
  const PlaceSearchOutcome({
    required this.retrievedCount,
    required this.matches,
    this.alternative,
  });

  final int retrievedCount;
  final List<ScoredPlace> matches;
  final PointOfInterest? alternative;
}

class PlaceCandidateRetriever {
  const PlaceCandidateRetriever(this.nearby);
  final NearbyService nearby;

  Future<List<PointOfInterest>> retrieve(
    Coordinates origin,
    PlaceQuery query, {
    required double radiusMeters,
  }) {
    final repositoryQuery = query.category == null && query.brand == null
        ? query.searchTerm
        : null;
    return nearby.search(
      origin,
      category: query.category,
      query: repositoryQuery,
      radiusMeters: radiusMeters,
    );
  }
}

class StructuredPlaceSearch {
  const StructuredPlaceSearch({
    required this.retriever,
    this.matcher = const PlaceMatcher(),
  });

  final PlaceCandidateRetriever retriever;
  final PlaceMatcher matcher;

  Future<PlaceSearchOutcome> search(
    Coordinates origin,
    PlaceQuery query, {
    required double radiusMeters,
  }) async {
    final candidates = await retriever.retrieve(
      origin,
      query,
      radiusMeters: radiusMeters,
    );
    final result = matcher.match(query, candidates);
    return PlaceSearchOutcome(
      retrievedCount: candidates.length,
      matches: result.matches,
      alternative: result.alternative,
    );
  }
}
