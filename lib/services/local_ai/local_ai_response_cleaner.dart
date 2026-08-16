String cleanLocalAiAnswer(String rawAnswer) {
  var answer = rawAnswer
      .replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<\|(?:im_end|endoftext)\|>'), '')
      .trim();

  // A truncated thinking block is not a user-facing answer.
  answer = answer.replaceAll(
    RegExp(r'<think>[\s\S]*$', caseSensitive: false),
    '',
  );

  // Small models occasionally emit another chat turn instead of stopping.
  final nextRole = RegExp(
    r'\n\s*(?:user|assistant|system)\s*:',
    caseSensitive: false,
  ).firstMatch(answer);
  if (nextRole != null) answer = answer.substring(0, nextRole.start).trim();
  answer = answer.replaceFirst(
    RegExp(
      r'^\s*(?:assistant|answer)\s*(?:says)?\s*[:\-]\s*',
      caseSensitive: false,
    ),
    '',
  );

  final sentences = answer.split(RegExp(r'(?<=[.!?])\s+'));
  final uniqueSentences = <String>[];
  final seen = <String>{};
  for (final sentence in sentences) {
    final key = sentence.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (key.isEmpty || seen.contains(key)) break;
    seen.add(key);
    uniqueSentences.add(sentence.trim());
  }
  answer = uniqueSentences.join(' ').trim();

  // Keep accidental run-on repetition bounded even when it has no punctuation.
  final words = answer.split(RegExp(r'\s+'));
  if (words.length > 80) answer = words.take(80).join(' ');
  if (RegExp(
    r'^_+[a-z0-9]+(?:_[a-z0-9]+)+$',
    caseSensitive: false,
  ).hasMatch(answer)) {
    return '';
  }
  return answer.trim();
}
