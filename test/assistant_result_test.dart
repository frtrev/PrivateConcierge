import 'package:flutter_test/flutter_test.dart';
import 'package:private_concierge/core/models/assistant_result.dart';

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
    expect((payload['actions']! as List), hasLength(2));
  });
}
