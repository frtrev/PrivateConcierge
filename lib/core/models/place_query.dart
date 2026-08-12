enum PlaceSort { distance, relevance }

class PlaceQuery {
  const PlaceQuery({
    this.category,
    this.brand,
    this.searchTerm,
    this.openNow,
    this.limit = 5,
    this.sort = PlaceSort.distance,
  });

  final String? category;
  final String? brand;
  final String? searchTerm;
  final bool? openNow;
  final int limit;
  final PlaceSort sort;
}
