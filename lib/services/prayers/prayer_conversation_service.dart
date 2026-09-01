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

  bool get isCapturingPrayerText =>
      _state == _PrayerConversationState.awaitingText ||
      _state == _PrayerConversationState.editingText;

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
        _draftText = _formatPrayerText(text);
        _state = _PrayerConversationState.awaitingName;
        return _message('What do you want to name this prayer?');
      case _PrayerConversationState.awaitingName:
        await store.savePrayer(name: text, text: _draftText!);
        _reset();
        return _message('I saved the prayer as $text.');
      case _PrayerConversationState.editingText:
        final prayer = _editing!;
        await store.savePrayer(id: prayer.id, text: _formatPrayerText(text));
        _reset();
        return _message('I updated ${prayer.name}.');
      case _PrayerConversationState.awaitingPlayName:
        _state = _PrayerConversationState.idle;
        return _findPrayerOrRoutine(text);
      case _PrayerConversationState.idle:
        break;
    }

    final normalized = _normalize(text);
    if (_asksToSave(normalized)) {
      _state = _PrayerConversationState.awaitingText;
      return _message(
        "Of course, you can start praying after the beep, I'll be listening.",
      );
    }
    if (_asksToPray(normalized)) {
      final inlineName = _inlinePrayerName(normalized);
      if (inlineName != null) return _findPrayerOrRoutine(inlineName);
      _state = _PrayerConversationState.awaitingPlayName;
      return _message('Which prayer or prayer routine would you like?');
    }
    return null;
  }

  Future<AssistantResult> _findPrayerOrRoutine(String requestedName) async {
    final prayers = await store.prayers();
    final routines = await store.prayerRoutines();
    final needle = _normalize(requestedName).replaceFirst(
      RegExp(
        r'^(the prayer routine called|prayer routine called|the routine called|routine called|the prayer routine|prayer routine|the routine|routine|the prayer called|prayer called|the prayer|prayer)\s+',
      ),
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
      return AssistantResult(
        response: "Let's begin.",
        spokenResponse: "Let's begin.",
        type: AssistantResultType.message,
        context: const AssistantConversationState(lastIntent: 'playPrayer'),
        prayerChoices: [PrayerChoice(id: match.id, name: match.name)],
      );
    }
    PrayerRoutine? routineMatch;
    for (final routine in routines) {
      final name = _normalize(routine.name);
      if (name == needle || name.contains(needle) || needle.contains(name)) {
        routineMatch = routine;
        break;
      }
    }
    if (routineMatch != null) {
      return AssistantResult(
        response: "Let's begin.",
        spokenResponse: "Let's begin.",
        type: AssistantResultType.message,
        context: const AssistantConversationState(lastIntent: 'playPrayer'),
        prayerChoices: [
          PrayerChoice(
            id: routineMatch.id,
            name: routineMatch.name,
            isRoutine: true,
          ),
        ],
      );
    }
    if (prayers.isEmpty && routines.isEmpty) {
      return _message(
        'You do not have any saved prayers or prayer routines yet. Would you like to save a prayer?',
      );
    }
    return AssistantResult(
      response:
          'I could not find that prayer or routine. Here are your saved options:',
      spokenResponse:
          'I could not find that prayer or routine. You have: ${[...prayers.map((p) => p.name), ...routines.map((r) => '${r.name} routine')].join(', ')}.',
      type: AssistantResultType.message,
      context: const AssistantConversationState(
        lastIntent: 'listPrayerOptions',
      ),
      prayerChoices: [
        for (final prayer in prayers)
          PrayerChoice(id: prayer.id, name: prayer.name),
        for (final routine in routines)
          PrayerChoice(id: routine.id, name: routine.name, isRoutine: true),
      ],
    );
  }

  bool _asksToSave(String text) =>
      RegExp(r'\b(save|record|remember|add)\b.*\bprayer\b').hasMatch(text) ||
      RegExp(r'\bprayer\b.*\b(save|record|remember)\b').hasMatch(text);

  bool _asksToPray(String text) =>
      RegExp(
        r'^(lets|let s|let us|i want to|i would like to|i d like to|id like to|can we|please)\s+pray\b',
      ).hasMatch(text) ||
      RegExp(r'^i feel like\s+praying\b').hasMatch(text) ||
      text == 'pray';

  String? _inlinePrayerName(String text) {
    final match = RegExp(
      r'^(?:(?:lets|let s|let us|i want to|i would like to|i d like to|id like to|can we|please)\s+pray|i feel like\s+praying)\s+(.+)$',
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

  String _formatPrayerText(String text) {
    var value = text
        .trim()
        .replaceAll(RegExp(r'\s+([,.;!?])'), r'$1')
        .replaceAll(RegExp(r'\s+'), ' ');
    if (value.isEmpty) return value;
    value = '${value[0].toUpperCase()}${value.substring(1)}';
    if (!RegExp(r'[.!?]$').hasMatch(value)) value = '$value.';
    return value;
  }

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
