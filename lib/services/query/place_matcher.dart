import '../../core/models/place_query.dart';
import '../../core/models/poi.dart';
import 'place_vocabulary.dart';

class PlaceMatchWeights {
  const PlaceMatchWeights({
    this.exactBrand = 1000,
    this.brand = 800,
    this.category = 300,
    this.keyword = 160,
    this.distanceMaximum = 40,
  });

  final double exactBrand;
  final double brand;
  final double category;
  final double keyword;
  final double distanceMaximum;
}

class ScoredPlace {
  const ScoredPlace(this.place, this.score);
  final PointOfInterest place;
  final double score;
}

class PlaceMatchResult {
  const PlaceMatchResult({required this.matches, this.alternative});
  final List<ScoredPlace> matches;
  final PointOfInterest? alternative;
}

class PlaceMatcher {
  const PlaceMatcher({
    this.weights = const PlaceMatchWeights(),
    this.vocabulary = const PlaceVocabulary(),
  });

  final PlaceMatchWeights weights;
  final PlaceVocabulary vocabulary;

  PlaceMatchResult match(PlaceQuery query, List<PointOfInterest> candidates) {
    final scored = <ScoredPlace>[];
    for (final place in candidates) {
      final matchScore = score(query, place);
      if (matchScore != null) scored.add(ScoredPlace(place, matchScore));
    }
    scored.sort((a, b) {
      if (query.sort == PlaceSort.distance) {
        final distanceOrder = (a.place.distanceMeters ?? double.infinity)
            .compareTo(b.place.distanceMeters ?? double.infinity);
        if (distanceOrder != 0) return distanceOrder;
      }
      final scoreOrder = b.score.compareTo(a.score);
      if (scoreOrder != 0) return scoreOrder;
      return (a.place.distanceMeters ?? double.infinity).compareTo(
        b.place.distanceMeters ?? double.infinity,
      );
    });
    final alternative = scored.isEmpty && query.brand != null
        ? _closestCategoryCandidate(query, candidates)
        : null;
    return PlaceMatchResult(matches: scored, alternative: alternative);
  }

  double? score(PlaceQuery query, PointOfInterest place) {
    if (query.category != null && place.category != query.category) return null;

    var score = query.category == null ? 0.0 : weights.category;
    final normalizedName = PlaceVocabulary.normalizeName(place.name);
    if (query.brand != null) {
      final brand = PlaceVocabulary.brands.firstWhere(
        (value) => value.name == query.brand,
      );
      final matchingAliases = brand.aliases.where(
        (alias) => PlaceVocabulary.containsPhrase(normalizedName, alias),
      );
      if (matchingAliases.isEmpty) return null;
      final exact = brand.aliases.any(
        (alias) => normalizedName == PlaceVocabulary.normalizeName(alias),
      );
      score += exact ? weights.exactBrand : weights.brand;
    }

    final term = query.searchTerm;
    if (term != null && term.isNotEmpty) {
      final haystack = PlaceVocabulary.normalizeName(
        '${place.name} ${place.subcategory} ${place.description ?? ''}',
      );
      if (!PlaceVocabulary.containsPhrase(haystack, term)) return null;
      score += weights.keyword;
    }

    final meters = place.distanceMeters;
    if (meters != null) {
      final distanceBonus =
          weights.distanceMaximum / (1 + (meters / 1609.344).clamp(0, 100));
      score += distanceBonus;
    }
    return score;
  }

  PointOfInterest? _closestCategoryCandidate(
    PlaceQuery query,
    List<PointOfInterest> candidates,
  ) {
    final alternatives =
        candidates
            .where(
              (place) =>
                  query.category == null || place.category == query.category,
            )
            .toList()
          ..sort(
            (a, b) => (a.distanceMeters ?? double.infinity).compareTo(
              b.distanceMeters ?? double.infinity,
            ),
          );
    return alternatives.isEmpty ? null : alternatives.first;
  }
}
