import '../../core/models/local_query.dart';

abstract interface class QueryResponseGenerator {
  String generate(QueryPlan plan, LocalQueryResult result);
}

class TemplateQueryResponseGenerator implements QueryResponseGenerator {
  const TemplateQueryResponseGenerator();

  @override
  String generate(QueryPlan plan, LocalQueryResult result) {
    if (result.detail != null) return result.detail!;
    switch (result.status) {
      case QueryResultStatus.unknown:
        return 'I did not understand that. Try asking for a nearby place, a distance, or directions.';
      case QueryResultStatus.clarification:
        return 'Could you be more specific about the place you want?';
      case QueryResultStatus.unavailable:
        return 'Your location is unavailable, so I cannot calculate that locally right now.';
      case QueryResultStatus.empty:
        final brand = plan.placeQuery?.brand;
        final alternative = result.alternativePoi;
        if (brand != null) {
          final notFound = "I couldn't find a $brand nearby.";
          if (alternative == null) return notFound;
          final kind = _categoryLabel(plan.placeQuery?.category);
          return '$notFound The closest $kind is ${alternative.name}, about ${_miles(alternative.distanceMeters)} miles away.';
        }
        return 'I found no matching places in the downloaded region.';
      case QueryResultStatus.success:
        break;
    }
    final selected = result.selectedPoi;
    if (result.navigationRequested && selected != null) {
      return 'Opening directions to ${selected.name}.';
    }
    if (plan.intent == LocalQueryIntent.compareDistance &&
        selected != null &&
        result.comparisonPoi != null) {
      return '${selected.name} is closer at ${_miles(selected.distanceMeters)} miles, compared with '
          '${_miles(result.comparisonPoi!.distanceMeters)} miles to ${result.comparisonPoi!.name}.';
    }
    if (selected != null && plan.intent == LocalQueryIntent.distanceTo) {
      return '${selected.name} is about ${_miles(selected.distanceMeters)} miles away.';
    }
    if (selected != null && plan.operation == QueryOperation.nearest) {
      final kind = plan.placeQuery?.brand ?? _categoryLabel(plan.category);
      return '${selected.name} is the closest $kind, about ${_miles(selected.distanceMeters)} miles away.';
    }
    return 'Nearby: ${result.places.map((place) => '${place.name}, ${_miles(place.distanceMeters)} miles').join('; ')}.';
  }

  String _miles(double? meters) => meters == null
      ? 'an unknown distance'
      : (meters / 1609.344).toStringAsFixed(1);

  String _categoryLabel(String? category) => switch (category) {
    'gas' => 'gas station',
    'shopping' => 'store',
    'medical' => 'medical place',
    null => 'matching place',
    _ => category,
  };
}
