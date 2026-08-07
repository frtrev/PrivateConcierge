import 'package:flutter_test/flutter_test.dart';
import 'package:private_concierge/core/models/assistant_command.dart';
import 'package:private_concierge/services/commands/command_interpreter.dart';

void main() {
  final interpreter = DeterministicCommandInterpreter();
  test('extracts nearby category without UI coupling', () {
    final result = interpreter.interpret('Find a church nearby.');
    expect(result.intent, AssistantIntent.findNearby);
    expect(result.parameters['category'], 'church');
  });
  test(
    'recognizes current region request',
    () => expect(
      interpreter.interpret('What city am I in?').intent,
      AssistantIntent.currentRegion,
    ),
  );
}
