import 'package:flutter_test/flutter_test.dart';
import 'package:private_concierge/core/models/local_query.dart';
import 'package:private_concierge/services/query/query_interpreter.dart';

void main() {
  final interpreter = RuleBasedQueryInterpreter();

  test(
    'equivalent nearest restaurant phrasings produce equivalent intents',
    () {
      const phrases = [
        'closest restaurant',
        'nearest restaurant',
        'what restaurant is closest',
        'find the nearest place to eat',
        "where's the nearest restaurant?",
      ];
      final parsed = phrases.map(interpreter.interpret).toList();
      for (final query in parsed) {
        expect(query.intent, LocalQueryIntent.findPoi);
        expect(query.operation, QueryOperation.nearest);
        expect(query.category, 'restaurant');
        expect(query.limit, 1);
        expect(query.confidence, greaterThan(.9));
      }
    },
  );

  test('extracts cuisine and radius', () {
    final result = interpreter.interpret(
      'Show me Mexican restaurants within 3 miles',
    );
    expect(result.intent, LocalQueryIntent.findPoi);
    expect(result.category, 'restaurant');
    expect(result.name, 'mexican');
    expect(result.radiusMiles, 3);
    expect(result.operation, QueryOperation.withinRadius);
  });

  test('recognizes comparisons and contextual follow-ups', () {
    final comparison = interpreter.interpret(
      'Which is closer, Target or Walmart?',
    );
    expect(comparison.intent, LocalQueryIntent.compareDistance);
    expect(comparison.name, 'target');
    expect(comparison.secondName, 'walmart');

    final closest = interpreter.interpret('Which one is closest?');
    expect(closest.usesPreviousResults, isTrue);
    final navigation = interpreter.interpret('Take me there');
    expect(navigation.intent, LocalQueryIntent.navigate);
    expect(navigation.usesPreviousSelection, isTrue);

    final directNavigation = interpreter.interpret(
      'Take me to the closest restaurant',
    );
    expect(directNavigation.intent, LocalQueryIntent.navigate);
    expect(directNavigation.operation, QueryOperation.nearest);
    expect(directNavigation.category, 'restaurant');
  });

  test('does not invent an intent for unrelated or malformed input', () {
    expect(
      interpreter.interpret('purple seventeen').intent,
      LocalQueryIntent.unknown,
    );
    expect(interpreter.interpret('   ').confidence, 0);
  });
}
