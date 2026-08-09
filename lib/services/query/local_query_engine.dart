import '../../core/models/geo.dart';
import '../../core/models/local_query.dart';
import 'conversation_context.dart';
import 'query_capability.dart';
import 'query_interpreter.dart';
import 'response_generator.dart';

class QueryAnswer {
  const QueryAnswer({
    required this.text,
    required this.plan,
    required this.result,
  });
  final String text;
  final QueryPlan plan;
  final LocalQueryResult result;
}

class LocalQueryEngine {
  const LocalQueryEngine({
    required this.interpreter,
    required this.contextResolver,
    required this.registry,
    required this.responseGenerator,
    required this.context,
  });

  final QueryInterpreter interpreter;
  final QueryContextResolver contextResolver;
  final CapabilityRegistry registry;
  final QueryResponseGenerator responseGenerator;
  final ConversationContext context;

  Future<QueryAnswer> answer(
    String text, {
    required Coordinates? origin,
  }) async {
    final parsed = interpreter.interpret(text);
    final plan = contextResolver.resolve(parsed);
    late final LocalQueryResult result;
    if (parsed.confidence < .5 || parsed.intent == LocalQueryIntent.unknown) {
      result = const LocalQueryResult(status: QueryResultStatus.unknown);
    } else if (parsed.confidence < .7) {
      result = const LocalQueryResult(
        status: QueryResultStatus.clarification,
        detail: 'Which kind of place should I look for?',
      );
    } else if ((parsed.usesPreviousResults || parsed.usesPreviousSelection) &&
        context.current == null) {
      result = const LocalQueryResult(
        status: QueryResultStatus.clarification,
        detail:
            'That earlier result has expired. Please search for the place again.',
      );
    } else {
      result = await registry.execute(
        plan,
        QueryExecutionContext(origin: origin),
      );
    }
    context.remember(plan.intent, result);
    return QueryAnswer(
      text: responseGenerator.generate(plan, result),
      plan: plan,
      result: result,
    );
  }
}
