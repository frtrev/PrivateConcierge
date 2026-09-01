import 'package:flutter/foundation.dart';

import '../../core/models/assistant_command.dart';
import '../../core/models/assistant_result.dart';
import '../../core/models/local_query.dart';
import '../../core/models/poi.dart';
import '../../features/loading/bootstrap_service.dart';
import '../../services/commands/command_interpreter.dart';
import '../../services/downloads/region_package_manager.dart';
import '../../services/nearby/nearby_service.dart';
import '../../services/profile/user_profile_service.dart';
import '../../services/query/local_query_engine.dart';
import '../../services/query/place_detail_follow_up.dart';
import '../../services/tracking/tracking_query_engine.dart';
import '../../services/local_ai/local_ai_coordinator.dart';
import '../../services/prayers/prayer_conversation_service.dart';

class AssistantEngine {
  AssistantEngine({
    required this.queries,
    required this.commands,
    required this.bootstrap,
    required this.packages,
    required this.nearby,
    required this.profiles,
    required this.tracking,
    PlaceDetailFollowUpResolver? placeDetails,
    this.localAi,
    this.prayers,
  }) : placeDetails = placeDetails ?? PlaceDetailFollowUpResolver();

  final LocalQueryEngine queries;
  final CommandInterpreter commands;
  final BootstrapService bootstrap;
  final RegionPackageManager packages;
  final NearbyService nearby;
  final UserProfileService profiles;
  final PlaceDetailFollowUpResolver placeDetails;
  final TrackingQueryEngine tracking;
  final LocalAiCoordinator? localAi;
  final PrayerConversationService? prayers;

  Future<AssistantResult> answer(String text) async {
    final prayerAnswer = await prayers?.handle(text);
    if (prayerAnswer != null) return prayerAnswer;
    final normalized = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 .?+\-*/]'), ' ')
        .trim();
    if (RegExp(r'^(no|no thanks|not now|cancel)$').hasMatch(normalized) &&
        queries.context.current?.selectedPoi != null) {
      return const AssistantResult(
        response: 'Okay. I will not start directions.',
        spokenResponse: 'Okay. I will not start directions.',
        type: AssistantResultType.message,
        context: AssistantConversationState(lastIntent: 'declinedFollowUp'),
      );
    }
    final trackingAnswer = await tracking.answer(text);
    if (trackingAnswer != null) return _personalizeResult(trackingAnswer);
    final detailAnswer = _placeDetailFollowUp(text);
    if (detailAnswer != null) return detailAnswer;
    if (_looksLikeGeneralQuestion(normalized)) {
      final generalAnswer = await localAi?.answerGeneral(normalized);
      if (generalAnswer != null) {
        return AssistantResult(
          response: generalAnswer,
          spokenResponse: generalAnswer,
          type: AssistantResultType.message,
          context: const AssistantConversationState(
            lastIntent: 'localAiGeneralAnswer',
          ),
          usedLocalAi: true,
        );
      }
    }
    // The deterministic query engine handles known place searches,
    // navigation, and conversational follow-ups in milliseconds. Keep it on
    // the critical path for CarPlay instead of waiting for local inference to
    // rediscover an intent that is already understood locally.
    final directAnswer = await queries.answer(
      text,
      origin: bootstrap.coordinates,
    );
    if (directAnswer.plan.intent != LocalQueryIntent.unknown) {
      return _fromQuery(directAnswer);
    }
    var enhancedText = text;
    final localResult = await localAi?.interpret(normalized);
    if (localResult != null) {
      if (localResult.confidence < .75 &&
          localResult.clarificationQuestion != null) {
        return AssistantResult(
          response: localResult.clarificationQuestion!,
          spokenResponse: localResult.clarificationQuestion!,
          type: AssistantResultType.message,
          context: const AssistantConversationState(
            lastIntent: 'localAiClarification',
          ),
        );
      }
      if (localResult.intent == 'searchNearby') {
        final category = localResult.arguments['category'] as String?;
        enhancedText = category == null
            ? 'find nearby'
            : 'find nearby $category';
      }
      if (localResult.intent == 'answerGeneral') {
        final answer = localResult.arguments['answer'] as String;
        return AssistantResult(
          response: answer,
          spokenResponse: answer,
          type: AssistantResultType.message,
          context: const AssistantConversationState(
            lastIntent: 'localAiGeneralAnswer',
          ),
          usedLocalAi: true,
        );
      }
    }
    final answer = await queries.answer(
      enhancedText,
      origin: bootstrap.coordinates,
    );
    if (answer.plan.intent != LocalQueryIntent.unknown) {
      return _fromQuery(answer, usedLocalAi: localResult != null);
    }
    return _fromCommand(text);
  }

  AssistantResult _personalizeResult(AssistantResult result) {
    final spoken = result.spokenResponse;
    return AssistantResult(
      response: _personalize(spoken),
      spokenResponse: _personalize(spoken),
      type: result.type,
      places: result.places,
      actions: result.actions,
      context: result.context,
      usedLocalAi: result.usedLocalAi,
    );
  }

  AssistantResult? _placeDetailFollowUp(String text) {
    if (!placeDetails.recognizes(text)) return null;
    final place = queries.context.current?.selectedPoi;
    if (place != null && kDebugMode) _logPlaceDetails(place);
    final answer = placeDetails.resolve(text, place);
    return _detailResult(answer.message, place, action: answer.action);
  }

  AssistantResult _detailResult(
    String message,
    PointOfInterest? place, {
    AssistantActionType? action,
  }) => AssistantResult(
    response: _personalize(message),
    spokenResponse: message,
    type: place == null
        ? AssistantResultType.message
        : AssistantResultType.place,
    places: place == null ? const [] : [PlaceResult.fromPoi(place)],
    actions: action == null || place == null
        ? const []
        : [AssistantAction(type: action, placeId: place.id)],
    context: AssistantConversationState(
      lastIntent: 'placeDetails',
      selectedPlaceId: place?.id,
    ),
  );

  void _logPlaceDetails(PointOfInterest place) {
    debugPrint('''
Place details provider: Overture
place=${place.name}
openingHours=${place.openingHours == null ? 'unavailable' : 'provider'}
phoneNumber=${place.phoneNumber == null ? 'unavailable' : 'provider'}
website=${place.website == null ? 'unavailable' : 'provider'}
address=${place.address.isEmpty ? 'unavailable' : 'provider'}
coordinates=provider
category=provider
distance=${place.distanceMeters == null ? 'unavailable' : 'calculated locally'}
''');
  }

  AssistantResult _fromQuery(QueryAnswer answer, {bool usedLocalAi = false}) {
    final result = answer.result;
    final selected = result.selectedPoi ?? result.alternativePoi;
    final pois = result.places.isNotEmpty
        ? result.places
        : selected == null
        ? const <PointOfInterest>[]
        : [selected];
    if (kDebugMode) {
      for (final poi in pois) {
        _logPlaceDetails(poi);
      }
    }
    final places = pois.map(PlaceResult.fromPoi).toList(growable: false);
    final actions = selected == null
        ? const <AssistantAction>[]
        : [
            AssistantAction(
              type: AssistantActionType.openInMaps,
              placeId: selected.id,
            ),
            AssistantAction(
              type: AssistantActionType.navigate,
              placeId: selected.id,
            ),
            if (selected.phoneNumber?.isNotEmpty == true)
              AssistantAction(
                type: AssistantActionType.call,
                placeId: selected.id,
              ),
            if (selected.website != null)
              AssistantAction(
                type: AssistantActionType.openWebsite,
                placeId: selected.id,
              ),
          ];
    final personalized = _personalize(answer.text);
    final type = result.navigationRequested
        ? AssistantResultType.navigation
        : result.status == QueryResultStatus.unavailable
        ? AssistantResultType.unavailable
        : places.length > 1
        ? AssistantResultType.placeList
        : places.length == 1
        ? AssistantResultType.place
        : AssistantResultType.message;
    return AssistantResult(
      response: personalized,
      spokenResponse: _vehicleResponse(answer, selected),
      type: type,
      places: places,
      actions: actions,
      context: AssistantConversationState(
        lastIntent: answer.plan.intent.name,
        lastCategory: answer.plan.placeQuery?.category ?? answer.plan.category,
        lastBrand: answer.plan.placeQuery?.brand,
        selectedPlaceId: selected?.id,
      ),
      usedLocalAi: usedLocalAi,
    );
  }

  Future<AssistantResult> _fromCommand(String text) async {
    final command = commands.interpret(text);
    String response;
    List<PointOfInterest> points = const [];
    switch (command.intent) {
      case AssistantIntent.currentLocation:
      case AssistantIntent.currentRegion:
        response = bootstrap.region == null
            ? 'I do not have a current region.'
            : 'You are in ${bootstrap.region!.displayName}.';
      case AssistantIntent.downloadedRegions:
        final regions = await packages.installedRegions();
        response = regions.isEmpty
            ? 'No regions are downloaded.'
            : 'Downloaded: ${regions.map((region) => region.displayName).join(', ')}.';
      case AssistantIntent.findNearby:
        final origin = bootstrap.coordinates;
        if (origin == null) {
          response = 'Location is unavailable. Enable it to search nearby.';
          break;
        }
        points = await nearby.search(
          origin,
          category: command.parameters['category'],
        );
        response = points.isEmpty
            ? 'I found no matching places in the downloaded region.'
            : _describe(points);
      case AssistantIntent.downloadCurrentRegion:
        response = 'The current region is already checked during startup.';
      case AssistantIntent.unknown:
        response =
            'I can answer where you are, list downloaded regions, or find nearby places.';
    }
    final places = points
        .take(5)
        .map(PlaceResult.fromPoi)
        .toList(growable: false);
    return AssistantResult(
      response: _personalize(response),
      spokenResponse: response,
      type: places.isEmpty
          ? AssistantResultType.message
          : AssistantResultType.placeList,
      places: places,
      context: AssistantConversationState(lastIntent: command.intent.name),
    );
  }

  String _vehicleResponse(QueryAnswer answer, PointOfInterest? selected) {
    if (answer.result.places.length > 1) {
      return vehiclePlaceListSummary(answer);
    }
    if (selected == null) return answer.text;
    if (answer.result.navigationRequested) {
      return 'Starting directions to ${selected.name}.';
    }
    final miles = selected.distanceMeters == null
        ? null
        : (selected.distanceMeters! / 1609.344).toStringAsFixed(1);
    return miles == null
        ? '${selected.name} is the matching place. Would you like directions?'
        : '${selected.name} is $miles miles away. Would you like directions?';
  }

  String _personalize(String message) {
    final profile = profiles.load();
    if (profile == null) return message;
    final address = profile.preferredAddress.trim();
    final prefix = address.isEmpty ? '' : '$address, ';
    return switch (profile.personality) {
      'professional' => '$prefix$message',
      'playful' => '${prefix}here’s what I found: $message',
      _ => '${prefix}of course. $message',
    };
  }

  String _describe(List<PointOfInterest> points) =>
      'Nearby: ${points.take(3).map((point) => '${point.name}, ${(point.distanceMeters! / 1609.344).toStringAsFixed(1)} miles').join('; ')}.';

  bool _looksLikeGeneralQuestion(String text) {
    final placeLanguage = RegExp(
      r'\b(near|nearby|nearest|closest|place|places|restaurant|store|shop|gas|pharmacy|church|navigate|directions|map|open now)\b',
    );
    if (placeLanguage.hasMatch(text)) return false;
    if (RegExp(
      r'\d\s*(\+|-|\*|/|times|plus|minus|divided)\s*\d',
    ).hasMatch(text)) {
      return true;
    }
    return RegExp(
      r'^(who|what|why|how|when|tell me|explain|define|calculate)\b',
    ).hasMatch(text);
  }
}

String vehiclePlaceListSummary(QueryAnswer answer) {
  if (answer.plan.limit > 10) {
    return 'I can only display up to 10 nearby places, here they are:';
  }
  final displayedCount = answer.result.places.length.clamp(0, 10);
  return 'I found $displayedCount places, here they are:';
}
