import 'package:flutter_test/flutter_test.dart';
import 'package:private_concierge/services/local_ai/local_ai_response_cleaner.dart';

void main() {
  test('removes thinking, tokens, and assistant role labels', () {
    expect(
      cleanLocalAiAnswer(
        '<think>reasoning</think> Assistant: The answer is four.<|im_end|>',
      ),
      'The answer is four.',
    );
  });

  test('stops repeated sentences', () {
    expect(
      cleanLocalAiAnswer('The answer is four. The answer is four. Again.'),
      'The answer is four.',
    );
  });

  test('stops when the model starts another chat turn', () {
    expect(
      cleanLocalAiAnswer('I am doing well.\nUser: What about you?'),
      'I am doing well.',
    );
  });

  test('rejects truncated reasoning and internal markers', () {
    expect(cleanLocalAiAnswer('<think>unfinished reasoning'), isEmpty);
    expect(cleanLocalAiAnswer('__of_any_other_reason'), isEmpty);
  });
}
