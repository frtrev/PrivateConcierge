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

class AssistantEngine {
  const AssistantEngine({
    required this.queries,
    required this.commands,
    required this.bootstrap,
    required this.packages,
    required this.nearby,
    required this.profiles,
  });

  final LocalQueryEngine queries;
  final CommandInterpreter commands;
  final BootstrapService bootstrap;
  final RegionPackageManager packages;
  final NearbyService nearby;
  final UserProfileService profiles;

  Future<AssistantResult> answer(String text) async {
    final answer = await queries.answer(text, origin: bootstrap.coordinates);
    if (answer.plan.intent != LocalQueryIntent.unknown) {
      return _fromQuery(answer);
    }
    return _fromCommand(text);
  }

  AssistantResult _fromQuery(QueryAnswer answer) {
    final result = answer.result;
    final selected = result.selectedPoi ?? result.alternativePoi;
    final pois = result.places.isNotEmpty
        ? result.places
        : selected == null
        ? const <PointOfInterest>[]
        : [selected];
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
}
