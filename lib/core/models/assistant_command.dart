enum AssistantIntent {
  currentLocation,
  currentRegion,
  findNearby,
  downloadedRegions,
  downloadCurrentRegion,
  unknown,
}

class AssistantCommand {
  const AssistantCommand({
    required this.intent,
    required this.originalText,
    this.parameters = const {},
  });
  final AssistantIntent intent;
  final String originalText;
  final Map<String, String> parameters;
}
