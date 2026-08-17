import '../../core/models/assistant_result.dart';
import '../../core/models/prayer.dart';
import '../storage/private_data_store.dart';

enum _PrayerConversationState {
  idle,
  awaitingText,
  awaitingName,
  awaitingPlayName,
  editingText,
}

class PrayerConversationService {
  PrayerConversationService(this.store);
  final PrayerStore store;
  _PrayerConversationState _state = _PrayerConversationState.idle;
  String? _draftText;
  Prayer? _editing;

  void beginRecording() {
    _reset();
    _state = _PrayerConversationState.awaitingText;
  }

  void beginEdit(Prayer prayer) {
    _editing = prayer;
    _state = _PrayerConversationState.editingText;
  }

  Future<AssistantResult?> handle(String input) async {
    final text = input.trim();
    if (text.isEmpty) return null;
    if (_isCancel(text)) {
      _reset();
      return _message('Okay, I stopped the prayer request.');
    }
    switch (_state) {
      case _PrayerConversationState.awaitingText:
        _draftText = text;
        _state = _PrayerConversationState.awaitingName;
        return _message('What do you want to name this prayer?');
      case _PrayerConversationState.awaitingName:
        await store.savePrayer(name: text, text: _draftText!);
        _reset();
        return _message('I saved the prayer as $text.');
      case _PrayerConversationState.editingText:
        final prayer = _editing!;
        await store.savePrayer(id: prayer.id, text: text);
        _reset();
        return _message('I updated ${prayer.name}.');
      case _PrayerConversationState.awaitingPlayName:
        _state = _PrayerConversationState.idle;
        return _findPrayer(text);
      case _PrayerConversationState.idle:
        break;
    }

    final normalized = _normalize(text);
    if (_asksToSave(normalized)) {
      _state = _PrayerConversationState.awaitingText;
      return _message(
        "Of course, I'm listening. What prayer would you like me to record?",
      );
    }
    if (_asksToPray(normalized)) {
      final inlineName = _inlinePrayerName(normalized);
      if (inlineName != null) return _findPrayer(inlineName);
      _state = _PrayerConversationState.awaitingPlayName;
      return _message('Of course. What do you want to pray?');
    }
    return null;
  }

  Future<AssistantResult> _findPrayer(String requestedName) async {
    final prayers = await store.prayers();
    final needle = _normalize(requestedName).replaceFirst(
      RegExp(r'^(the prayer called|prayer called|the prayer|prayer)\s+'),
      '',
    );
    Prayer? match;
    for (final prayer in prayers) {
      final name = _normalize(prayer.name);
      if (name == needle || name.contains(needle) || needle.contains(name)) {
        match = prayer;
        break;
      }
    }
    if (match != null) {
      return _message('Of course. ${match.text}');
    }
    if (prayers.isEmpty) {
      return _message(
        'You do not have any saved prayers yet. Would you like to save one?',
      );
    }
    return AssistantResult(
      response:
          'I could not find that prayer. I have the following prayers saved:',
      spokenResponse:
          'I could not find that prayer. I have the following prayers saved: ${prayers.map((p) => p.name).join(', ')}.',
      type: AssistantResultType.message,
      context: const AssistantConversationState(lastIntent: 'listPrayers'),
      prayerChoices: [
        for (final prayer in prayers)
          PrayerChoice(id: prayer.id, name: prayer.name),
      ],
    );
  }

  bool _asksToSave(String text) =>
      RegExp(r'\b(save|record|remember|add)\b.*\bprayer\b').hasMatch(text) ||
      RegExp(r'\bprayer\b.*\b(save|record|remember)\b').hasMatch(text);

  bool _asksToPray(String text) =>
      RegExp(
        r'^(lets|let s|let us|i want to|can we|please)\s+pray\b',
      ).hasMatch(text) ||
      text == 'pray';

  String? _inlinePrayerName(String text) {
    final match = RegExp(
      r'^(?:lets|let s|let us|i want to|can we|please)\s+pray\s+(.+)$',
    ).firstMatch(text);
    return match?.group(1)?.trim();
  }

  bool _isCancel(String text) => RegExp(
    r'^(cancel|stop|never mind|nevermind)$',
  ).hasMatch(_normalize(text));
  String _normalize(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  AssistantResult _message(String value) => AssistantResult(
    response: value,
    spokenResponse: value,
    type: AssistantResultType.message,
    context: const AssistantConversationState(lastIntent: 'prayer'),
  );

  void _reset() {
    _state = _PrayerConversationState.idle;
    _draftText = null;
    _editing = null;
  }
}
