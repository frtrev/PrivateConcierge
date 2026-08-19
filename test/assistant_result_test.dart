import 'package:flutter_test/flutter_test.dart';
import 'package:private_concierge/core/models/assistant_result.dart';
import 'package:private_concierge/core/models/geo.dart';
import 'package:private_concierge/core/models/opening_hours.dart';
import 'package:private_concierge/core/models/local_query.dart';
import 'package:private_concierge/core/models/poi.dart';
import 'package:private_concierge/services/assistant/assistant_engine.dart';
import 'package:private_concierge/services/query/local_query_engine.dart';

void main() {
  test('serializes one exact place for every presentation adapter', () {
    const place = PlaceResult(
      id: 'bp',
      name: 'BP',
      latitude: 35.1,
      longitude: -89.9,
      address: '1 Fuel Way',
      category: 'gas',
      distanceMeters: 3862.4256,
      phoneNumber: '+19015550100',
      website: 'https://example.com',
      openingHours: PlaceOpeningHours({
        1: [OpeningInterval(540, 1020)],
      }),
      isOpenNow: true,
    );
    const result = AssistantResult(
      response: 'The closest BP is 2.4 miles away.',
      spokenResponse: 'BP is 2.4 miles away. Would you like directions?',
      type: AssistantResultType.place,
      places: [place],
      actions: [
        AssistantAction(type: AssistantActionType.openInMaps, placeId: 'bp'),
        AssistantAction(type: AssistantActionType.navigate, placeId: 'bp'),
      ],
      context: AssistantConversationState(selectedPlaceId: 'bp'),
    );
    final payload = result.toMap();
    final serializedPlace = (payload['places']! as List).single as Map;
    expect(result.selectedPlace?.id, 'bp');
    expect(serializedPlace['id'], 'bp');
    expect(serializedPlace['latitude'], 35.1);
    expect(serializedPlace['longitude'], -89.9);
    expect(serializedPlace['phoneNumber'], '+19015550100');
    expect(serializedPlace['website'], 'https://example.com');
    expect(serializedPlace['openingHours'], isNotNull);
    expect((payload['actions']! as List), hasLength(2));
    expect(payload['usedLocalAi'], isFalse);
  });

  test('serializes the local AI response indicator', () {
    const result = AssistantResult(
      response: '4',
      spokenResponse: '4',
      type: AssistantResultType.message,
      usedLocalAi: true,
    );
    expect(result.toMap()['usedLocalAi'], isTrue);
  });

  test('serializes tappable prayer choices', () {
    const result = AssistantResult(
      response: 'Choose a prayer',
      spokenResponse: 'Choose a prayer',
      type: AssistantResultType.message,
      prayerChoices: [PrayerChoice(id: 7, name: 'Morning')],
    );
    expect(result.toMap()['prayerChoices'], [
      {'id': 7, 'name': 'Morning', 'isRoutine': false},
    ]);
  });

  test('vehicle place-list summary reports count and ten-place cap', () {
    QueryAnswer answer({required int requested, required int found}) =>
        QueryAnswer(
          text: 'Nearby results',
          plan: QueryPlan(
            intent: LocalQueryIntent.findPoi,
            operation: QueryOperation.nearby,
            confidence: 1,
            limit: requested,
          ),
          result: LocalQueryResult(
            status: QueryResultStatus.success,
            places: List.generate(
              found,
              (index) => PointOfInterest(
                id: '$index',
                regionId: 'r',
                name: 'Place $index',
                coordinates: const Coordinates(35, -90),
                category: 'other',
                subcategory: '',
                address: '',
              ),
            ),
          ),
        );

    expect(
      vehiclePlaceListSummary(answer(requested: 3, found: 3)),
      'I found 3 places, here they are:',
    );
    expect(
      vehiclePlaceListSummary(answer(requested: 15, found: 15)),
      'I can only display up to 10 nearby places, here they are:',
    );
  });
}
