import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kokoro_tts_service.dart';

class SpeechVoice {
  const SpeechVoice({
    required this.id,
    required this.name,
    required this.locale,
  });

  factory SpeechVoice.fromMap(Map<Object?, Object?> value) => SpeechVoice(
    id: value['id']! as String,
    name: value['name']! as String,
    locale: value['locale']! as String,
  );

  final String id;
  final String name;
  final String locale;
}

class SpeechEngine {
  const SpeechEngine({required this.id, required this.name});

  factory SpeechEngine.fromMap(Map<Object?, Object?> value) =>
      SpeechEngine(id: value['id']! as String, name: value['name']! as String);

  final String id;
  final String name;
}

class SpeechVoiceService {
  SpeechVoiceService(this._preferences, this.kokoro);

  static const _channel = MethodChannel('private_concierge/speech_voice');
  static const _selectedKey = 'charon.speech.selectedVoiceId';
  final SharedPreferences _preferences;
  final KokoroTtsService kokoro;

  Future<List<SpeechVoice>> voices() async {
    final values =
        await _channel.invokeListMethod<Object?>('voices') ?? const [];
    final voices = values
        .whereType<Map<Object?, Object?>>()
        .map(SpeechVoice.fromMap)
        .toList();
    if (kokoro.status.value.installed) {
      voices.addAll(
        KokoroTtsService.voices.map(
          (voice) => SpeechVoice(
            id: voice.id,
            name: voice.name,
            locale: 'Embedded • offline',
          ),
        ),
      );
    }
    voices.sort((a, b) {
      if (a.id == 'system:default') return -1;
      if (b.id == 'system:default') return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return voices;
  }

  Future<String?> selectedVoiceId() async =>
      _preferences.getString(_selectedKey) ??
      await _channel.invokeMethod<String>('selectedVoice');

  Future<List<SpeechEngine>> engines() async {
    final values =
        await _channel.invokeListMethod<Object?>('engines') ?? const [];
    final engines = values
        .whereType<Map<Object?, Object?>>()
        .map(SpeechEngine.fromMap)
        .toList();
    engines.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return engines;
  }

  Future<String?> selectedEngineId() =>
      _channel.invokeMethod<String>('selectedEngine');

  Future<void> selectEngine(String engineId) =>
      _channel.invokeMethod<void>('selectEngine', {'engineId': engineId});

  Future<void> preview({required String voiceId, required String text}) async {
    final kokoroVoice = _kokoroVoice(voiceId);
    if (kokoroVoice != null) {
      await kokoro.speak(text, kokoroVoice, wait: false);
      return;
    }
    await _channel.invokeMethod<void>('preview', {
      'voiceId': voiceId,
      'text': text,
    });
  }

  Future<void> speak(String text) async {
    final selected = await selectedVoiceId();
    final kokoroVoice = _kokoroVoice(selected);
    if (kokoroVoice != null) {
      await kokoro.speak(text, kokoroVoice);
      return;
    }
    await _channel.invokeMethod<void>('speak', {'text': text});
  }

  Future<void> select(String voiceId) async {
    await _preferences.setString(_selectedKey, voiceId);
    if (!voiceId.startsWith('kokoro:')) {
      await _channel.invokeMethod<void>('select', {'voiceId': voiceId});
    }
  }

  Future<bool> installVoices() async =>
      await _channel.invokeMethod<bool>('installVoices') ?? false;

  KokoroVoice? _kokoroVoice(String? id) {
    if (id == null) return null;
    for (final voice in KokoroTtsService.voices) {
      if (voice.id == id) return voice;
    }
    return null;
  }
}
