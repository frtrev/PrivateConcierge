import 'geo.dart';
import 'poi.dart';
import 'opening_hours.dart';

enum AssistantResultType { message, place, placeList, navigation, unavailable }

enum AssistantActionType { openInMaps, navigate, call, openWebsite }

class AssistantAction {
  const AssistantAction({required this.type, required this.placeId});

  final AssistantActionType type;
  final String placeId;

  Map<String, Object?> toMap() => {'type': type.name, 'placeId': placeId};
}

class PlaceResult {
  const PlaceResult({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.category,
    this.subcategory,
    this.distanceMeters,
    this.phoneNumber,
    this.website,
    this.openingHours,
    this.isOpenNow,
    this.arrival,
    this.departure,
  });

  factory PlaceResult.fromPoi(PointOfInterest poi) => PlaceResult(
    id: poi.id,
    name: poi.name,
    latitude: poi.coordinates.latitude,
    longitude: poi.coordinates.longitude,
    address: poi.address,
    category: poi.category,
    subcategory: poi.subcategory,
    distanceMeters: poi.distanceMeters,
    phoneNumber: poi.phoneNumber,
    website: poi.website?.toString(),
    openingHours: poi.openingHours,
    isOpenNow: poi.openingHours?.isOpenAt(DateTime.now()),
  );

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String address;
  final String category;
  final String? subcategory;
  final double? distanceMeters;
  final String? phoneNumber;
  final String? website;
  final PlaceOpeningHours? openingHours;
  final bool? isOpenNow;
  final DateTime? arrival;
  final DateTime? departure;

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    'address': address,
    'category': category,
    'subcategory': subcategory,
    'distanceMeters': distanceMeters,
    'phoneNumber': phoneNumber,
    'website': website,
    'openingHours': openingHours?.toMap(),
    'isOpenNow': isOpenNow,
    'arrivalMs': arrival?.millisecondsSinceEpoch,
    'departureMs': departure?.millisecondsSinceEpoch,
  };

  PointOfInterest toPoi() => PointOfInterest(
    id: id,
    regionId: 'assistant-result',
    name: name,
    coordinates: Coordinates(latitude, longitude),
    category: category,
    subcategory: subcategory ?? '',
    address: address,
    distanceMeters: distanceMeters,
    phoneNumber: phoneNumber,
    website: website == null ? null : Uri.tryParse(website!),
    openingHours: openingHours,
  );
}

class AssistantConversationState {
  const AssistantConversationState({
    this.lastIntent,
    this.lastCategory,
    this.lastBrand,
    this.selectedPlaceId,
  });

  final String? lastIntent;
  final String? lastCategory;
  final String? lastBrand;
  final String? selectedPlaceId;

  Map<String, Object?> toMap() => {
    'lastIntent': lastIntent,
    'lastCategory': lastCategory,
    'lastBrand': lastBrand,
    'selectedPlaceId': selectedPlaceId,
  };
}

class AssistantResult {
  const AssistantResult({
    required this.response,
    required this.spokenResponse,
    required this.type,
    this.places = const [],
    this.actions = const [],
    this.context = const AssistantConversationState(),
  });

  final String response;
  final String spokenResponse;
  final AssistantResultType type;
  final List<PlaceResult> places;
  final List<AssistantAction> actions;
  final AssistantConversationState context;

  PlaceResult? get selectedPlace {
    final selectedId = context.selectedPlaceId;
    if (selectedId != null) {
      for (final place in places) {
        if (place.id == selectedId) return place;
      }
    }
    return places.length == 1 ? places.first : null;
  }

  Map<String, Object?> toMap() => {
    'response': response,
    'spokenResponse': spokenResponse,
    'type': type.name,
    'places': places.map((place) => place.toMap()).toList(growable: false),
    'actions': actions.map((action) => action.toMap()).toList(growable: false),
    'context': context.toMap(),
  };
}

class AssistantPlatformCapabilities {
  const AssistantPlatformCapabilities({
    required this.canOpenMap,
    required this.canStartNavigation,
    required this.canShowPlaceList,
    required this.canUseVoiceFollowUp,
  });

  final bool canOpenMap;
  final bool canStartNavigation;
  final bool canShowPlaceList;
  final bool canUseVoiceFollowUp;
}
