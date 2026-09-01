import 'local_ai_models.dart';

class LocalAiValidationException implements Exception {
  const LocalAiValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}

class LocalAiResultValidator {
  const LocalAiResultValidator();
  static const allowedIntents = {
    'searchNearby',
    'findClosest',
    'filterCategory',
    'filterOpen',
    'businessDetails',
    'openDestination',
    'startNavigation',
    'answerGeneral',
    'clarify',
  };
  static const sensitiveIntents = {'startNavigation'};

  LocalAiResult validate(LocalAiResult result) {
    if (!allowedIntents.contains(result.intent)) {
      throw LocalAiValidationException('Unknown Local AI function.');
    }
    if (result.confidence < 0 || result.confidence > 1) {
      throw LocalAiValidationException('Invalid confidence.');
    }
    if (result.intent == 'searchNearby') {
      final category = result.arguments['category'];
      if (category != null &&
          (category is! String || category.trim().isEmpty)) {
        throw LocalAiValidationException('Invalid search category.');
      }
    }
    if (result.intent == 'answerGeneral') {
      final answer = result.arguments['answer'];
      if (answer is! String || answer.trim().isEmpty) {
        throw LocalAiValidationException('Invalid general answer.');
      }
    }
    if (sensitiveIntents.contains(result.intent) &&
        !result.requiresConfirmation) {
      throw LocalAiValidationException(
        'Sensitive function requires confirmation.',
      );
    }
    return result;
  }
}
