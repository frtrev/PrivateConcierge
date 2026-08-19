import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/prayer.dart';
import 'kokoro_tts_service.dart';

enum SpeechPurpose { regular, prayer }

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
  static const _regularRateKey = 'charon.speech.regularRate';
  static const _prayerRateKey = 'charon.speech.prayerRate';
  static const defaultRegularRate = 0.9;
  static const defaultPrayerRate = 0.75;
  final SharedPreferences _preferences;
  final KokoroTtsService kokoro;

  Future<List<SpeechVoice>> voices() async {
    final values =
        await _channel.invokeListMethod<Object?>('voices') ?? const [];
    final voices = values
        .whereType<Map<Object?, Object?>>()
        .map(SpeechVoice.fromMap)
        .toList();
    if (!Platform.isAndroid && kokoro.status.value.installed) {
      voices.addAll(
        KokoroTtsService.voices.map(
          (voice) => SpeechVoice(
            id: voice.id,
            name: 'Kokoro ${voice.name}',
            locale: voice.locale
                .replaceAll('English (US)', 'US English')
                .replaceAll('English (UK)', 'UK English'),
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

  Future<String?> selectedVoiceId() async {
    final selected = _preferences.getString(_selectedKey);
    if (!Platform.isAndroid || selected?.startsWith('kokoro:') != true) {
      return selected ?? await _channel.invokeMethod<String>('selectedVoice');
    }
    return await _channel.invokeMethod<String>('selectedVoice') ??
        'system:default';
  }

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

  double rateFor(SpeechPurpose purpose) =>
      _preferences.getDouble(
        purpose == SpeechPurpose.prayer ? _prayerRateKey : _regularRateKey,
      ) ??
      (purpose == SpeechPurpose.prayer
          ? defaultPrayerRate
          : defaultRegularRate);

  Future<void> setRate(SpeechPurpose purpose, double rate) =>
      _preferences.setDouble(
        purpose == SpeechPurpose.prayer ? _prayerRateKey : _regularRateKey,
        rate.clamp(0.6, 1.2),
      );

  Future<void> preview({
    required String voiceId,
    required String text,
    SpeechPurpose purpose = SpeechPurpose.regular,
  }) async {
    final rate = rateFor(purpose);
    final kokoroVoice = _kokoroVoice(voiceId);
    if (kokoroVoice != null) {
      await kokoro.speak(text, kokoroVoice, speed: rate, wait: false);
      return;
    }
    await _channel.invokeMethod<void>('preview', {
      'voiceId': voiceId,
      'text': text,
      'rate': rate,
    });
  }

  Future<void> speak(
    String text, {
    SpeechPurpose purpose = SpeechPurpose.regular,
  }) async {
    final rate = rateFor(purpose);
    final selected = await selectedVoiceId();
    final kokoroVoice = _kokoroVoice(selected);
    if (kokoroVoice != null) {
      await kokoro.speak(text, kokoroVoice, speed: rate);
      return;
    }
    await _channel.invokeMethod<void>('speak', {'text': text, 'rate': rate});
  }

  Future<void> speakPrayer(Prayer prayer) async {
    final rate = rateFor(SpeechPurpose.prayer);
    final voice = _kokoroVoice(await selectedVoiceId());
    if (voice == null) {
      await speak(prayer.text, purpose: SpeechPurpose.prayer);
      return;
    }
    await kokoro.speakCachedPrayer(
      prayer.text,
      voice,
      prayerId: prayer.id,
      updatedAt: prayer.updatedAt,
      speed: rate,
    );
  }

  Future<bool> selectedVoiceUsesKokoro() async =>
      _kokoroVoice(await selectedVoiceId()) != null;

  Future<void> regeneratePrayerAudio(
    List<Prayer> prayers, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final voice = _kokoroVoice(await selectedVoiceId());
    if (voice == null) return;
    await kokoro.clearPrayerAudioCache();
    final rate = rateFor(SpeechPurpose.prayer);
    for (var index = 0; index < prayers.length; index++) {
      final prayer = prayers[index];
      await kokoro.cachePrayer(
        prayer.text,
        voice,
        prayerId: prayer.id,
        updatedAt: prayer.updatedAt,
        speed: rate,
      );
      onProgress?.call(index + 1, prayers.length);
    }
  }

  Future<void> pause() async {
    final kokoroVoice = _kokoroVoice(await selectedVoiceId());
    if (kokoroVoice != null) {
      await kokoro.pause();
      return;
    }
    await _channel.invokeMethod<void>('pause');
  }

  Future<void> resume() async {
    final kokoroVoice = _kokoroVoice(await selectedVoiceId());
    if (kokoroVoice != null) {
      await kokoro.resume();
      return;
    }
    await _channel.invokeMethod<void>('resume');
  }

  Future<void> stop() async {
    await kokoro.stop();
    await _channel.invokeMethod<void>('stop');
  }

  Future<void> select(String voiceId) async {
    if (Platform.isAndroid && voiceId.startsWith('kokoro:')) {
      voiceId = 'system:default';
    }
    await _preferences.setString(_selectedKey, voiceId);
    if (!voiceId.startsWith('kokoro:')) {
      await _channel.invokeMethod<void>('select', {'voiceId': voiceId});
    }
  }

  Future<bool> installVoices() async =>
      await _channel.invokeMethod<bool>('installVoices') ?? false;

  KokoroVoice? _kokoroVoice(String? id) {
    if (Platform.isAndroid || id == null) return null;
    for (final voice in KokoroTtsService.voices) {
      if (voice.id == id) return voice;
    }
    return null;
  }
}
