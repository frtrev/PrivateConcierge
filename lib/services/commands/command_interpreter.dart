import '../../core/models/assistant_command.dart';

abstract interface class CommandInterpreter {
  AssistantCommand interpret(String text);
}

class DeterministicCommandInterpreter implements CommandInterpreter {
  static const categories = {
    'restaurant': 'restaurant',
    'food': 'restaurant',
    'church': 'church',
    'gym': 'gym',
    'gas': 'gas',
    'park': 'park',
    'historic': 'historic',
    'museum': 'museum',
    'grocery': 'grocery',
  };
  @override
  AssistantCommand interpret(String text) {
    final normalized = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
        .trim();
    if (normalized.contains('what city') ||
        normalized.contains('what region')) {
      return AssistantCommand(
        intent: AssistantIntent.currentRegion,
        originalText: text,
      );
    }
    if (normalized.contains('where am i')) {
      return AssistantCommand(
        intent: AssistantIntent.currentLocation,
        originalText: text,
      );
    }
    if (normalized.contains('regions') && normalized.contains('download')) {
      return AssistantCommand(
        intent: AssistantIntent.downloadedRegions,
        originalText: text,
      );
    }
    if (normalized.contains('download this region')) {
      return AssistantCommand(
        intent: AssistantIntent.downloadCurrentRegion,
        originalText: text,
      );
    }
    if (normalized.contains('near') ||
        normalized.contains('interesting') ||
        normalized.startsWith('find ')) {
      for (final entry in categories.entries) {
        if (normalized.contains(entry.key)) {
          return AssistantCommand(
            intent: AssistantIntent.findNearby,
            originalText: text,
            parameters: {'category': entry.value},
          );
        }
      }
      return AssistantCommand(
        intent: AssistantIntent.findNearby,
        originalText: text,
      );
    }
    return AssistantCommand(
      intent: AssistantIntent.unknown,
      originalText: text,
    );
  }
}
