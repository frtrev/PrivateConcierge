import 'package:flutter_test/flutter_test.dart';
import 'package:private_concierge/core/models/local_query.dart';
import 'package:private_concierge/core/models/place_query.dart';
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

  test('maps movie theater language to entertainment POIs', () {
    final result = interpreter.interpret('Find the nearest movie theater');
    expect(result.intent, LocalQueryIntent.findPoi);
    expect(result.category, 'entertainment');
    expect(result.operation, QueryOperation.nearest);
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

  test('affirmative answers navigate to the selected place', () {
    for (final phrase in ['yes', 'yes please', 'sure', 'go ahead']) {
      final result = interpreter.interpret(phrase);
      expect(result.intent, LocalQueryIntent.navigate, reason: phrase);
      expect(result.usesPreviousSelection, isTrue, reason: phrase);
    }
  });

  test('does not invent an intent for unrelated or malformed input', () {
    expect(
      interpreter.interpret('purple seventeen').intent,
      LocalQueryIntent.unknown,
    );
    expect(interpreter.interpret('   ').confidence, 0);
  });

  group('structured place queries', () {
    test('parses retail, pizza, donut, and named-place requests', () {
      final walmart = interpreter.interpret('Where is the nearest Walmart?');
      expect(walmart.placeQuery?.brand, 'Walmart');
      expect(walmart.operation, QueryOperation.nearest);

      for (final phrase in ['pizza place', 'pizza restaurant']) {
        final pizza = interpreter.interpret('Where is the nearest $phrase?');
        expect(pizza.placeQuery?.category, 'restaurant', reason: phrase);
        expect(pizza.placeQuery?.searchTerm, 'pizza', reason: phrase);
      }

      final donut = interpreter.interpret('Where is the nearest donut place?');
      expect(donut.placeQuery?.category, isNull);
      expect(donut.placeQuery?.searchTerm, 'donut');

      final named = interpreter.interpret(
        'Where is the nearest Memphis Pizza Cafe?',
      );
      expect(named.placeQuery?.searchTerm, 'memphis pizza cafe');
    });

    test('respects top result counts', () {
      final topThree = interpreter.interpret('Top 3 donut places');
      expect(topThree.placeQuery?.searchTerm, 'donut');
      expect(topThree.placeQuery?.limit, 3);

      final topTen = interpreter.interpret('Top 10 donut places');
      expect(topTen.placeQuery?.searchTerm, 'donut');
      expect(topTen.placeQuery?.limit, 10);

      final topThreeWords = interpreter.interpret('Top three donut places');
      expect(topThreeWords.placeQuery?.limit, 3);
    });

    test("parses closest BP", () {
      final result = interpreter.interpret("Where's the closest BP?");
      expect(result.intent, LocalQueryIntent.findPoi);
      expect(result.placeQuery?.category, 'gas');
      expect(result.placeQuery?.brand, 'BP');
      expect(result.placeQuery?.sort, PlaceSort.distance);
      expect(result.placeQuery?.limit, 1);
    });

    test('parses brand-only and nearest brand requests', () {
      final bp = interpreter.interpret('Find me a BP.');
      expect(bp.placeQuery?.brand, 'BP');
      expect(bp.placeQuery?.category, 'gas');

      final shell = interpreter.interpret('Find the nearest Shell.');
      expect(shell.placeQuery?.brand, 'Shell');
      expect(shell.operation, QueryOperation.nearest);
      expect(shell.limit, 1);
    });

    test('parses generic categories, counts, and cuisine', () {
      final gas = interpreter.interpret('Where is the closest gas station?');
      expect(gas.placeQuery?.category, 'gas');
      expect(gas.placeQuery?.limit, 1);

      final restaurants = interpreter.interpret(
        'Show me three nearby restaurants.',
      );
      expect(restaurants.placeQuery?.category, 'restaurant');
      expect(restaurants.placeQuery?.limit, 3);

      final mexican = interpreter.interpret(
        'Find the closest Mexican restaurant.',
      );
      expect(mexican.placeQuery?.category, 'restaurant');
      expect(mexican.placeQuery?.searchTerm, 'mexican');
      expect(mexican.placeQuery?.limit, 1);

      final threeMexican = interpreter.interpret(
        'Show me the three closest Mexican restaurants.',
      );
      expect(threeMexican.placeQuery?.category, 'restaurant');
      expect(threeMexican.placeQuery?.searchTerm, 'mexican');
      expect(threeMexican.placeQuery?.sort, PlaceSort.distance);
      expect(threeMexican.placeQuery?.limit, 3);
    });

    test('parses Starbucks and open-now constraints', () {
      final starbucks = interpreter.interpret('Find a Starbucks.');
      expect(starbucks.placeQuery?.brand, 'Starbucks');
      expect(starbucks.placeQuery?.category, 'restaurant');

      final openBp = interpreter.interpret("Find a BP that's open.");
      expect(openBp.placeQuery?.brand, 'BP');
      expect(openBp.placeQuery?.openNow, isTrue);
    });
  });

  test('recognizes map and navigation follow-up actions', () {
    for (final phrase in [
      'navigate there',
      'take me there',
      'directions there',
      'open it in maps',
      'show it on the map',
      'navigate to it',
    ]) {
      final result = interpreter.interpret(phrase);
      expect(result.intent, LocalQueryIntent.navigate, reason: phrase);
      expect(result.usesPreviousSelection, isTrue, reason: phrase);
    }
    final closest = interpreter.interpret('take me to the closest one');
    expect(closest.intent, LocalQueryIntent.navigate);
    expect(closest.usesPreviousResults, isTrue);
  });
}
