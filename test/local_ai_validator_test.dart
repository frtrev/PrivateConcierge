import 'package:flutter_test/flutter_test.dart';
import 'package:private_concierge/services/local_ai/local_ai_models.dart';
import 'package:private_concierge/services/local_ai/local_ai_validator.dart';

void main() {
  const validator = LocalAiResultValidator();
  LocalAiResult result({
    String intent = 'searchNearby',
    Map<String, dynamic> arguments = const {},
    bool confirmation = false,
    double confidence = .9,
  }) => LocalAiResult(
    requestId: '1',
    intent: intent,
    arguments: arguments,
    confidence: confidence,
    requiresConfirmation: confirmation,
  );

  test('accepts registered function with valid arguments', () {
    expect(
      validator
          .validate(result(arguments: const {'category': 'restaurant'}))
          .intent,
      'searchNearby',
    );
  });
  test('rejects unknown function', () {
    expect(
      () => validator.validate(result(intent: 'executeCode')),
      throwsA(isA<LocalAiValidationException>()),
    );
  });
  test('rejects invalid arguments', () {
    expect(
      () => validator.validate(result(arguments: const {'category': 4})),
      throwsA(isA<LocalAiValidationException>()),
    );
  });
  test('sensitive navigation requires confirmation', () {
    expect(
      () => validator.validate(result(intent: 'startNavigation')),
      throwsA(isA<LocalAiValidationException>()),
    );
    expect(
      validator
          .validate(result(intent: 'startNavigation', confirmation: true))
          .requiresConfirmation,
      isTrue,
    );
  });
  test('general answers require non-empty answer text', () {
    expect(
      validator
          .validate(
            result(intent: 'answerGeneral', arguments: const {'answer': '4'}),
          )
          .arguments['answer'],
      '4',
    );
    expect(
      () => validator.validate(result(intent: 'answerGeneral')),
      throwsA(isA<LocalAiValidationException>()),
    );
  });
}
