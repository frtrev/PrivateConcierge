import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/models/assistant_result.dart';
import '../core/models/prayer.dart';
import '../features/loading/bootstrap_screen.dart';
import '../features/onboarding/profile_onboarding_screen.dart';
import '../features/voice_assistant/voice_assistant_screen.dart';
import 'app_dependencies.dart';
import 'app_theme_controller.dart';
import '../services/prayers/prayer_routine_sequence.dart';

class PrivateConciergeApp extends StatefulWidget {
  const PrivateConciergeApp({super.key, required this.dependencies});
  final AppDependencies dependencies;
  @override
  State<PrivateConciergeApp> createState() => _PrivateConciergeAppState();
}

class _PrivateConciergeAppState extends State<PrivateConciergeApp> {
  static const _carChannel = MethodChannel('charon/car');
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _voiceController = VoiceAssistantController();
  bool _openingAssistant = false;
  late final _CarPrayerPlaybackController _carPrayerPlayback;

  @override
  void initState() {
    super.initState();
    _carPrayerPlayback = _CarPrayerPlaybackController(
      widget.dependencies,
      onStateChanged: (state) =>
          _carChannel.invokeMethod<void>('prayerPlaybackState', state),
    );
    _carChannel.setMethodCallHandler((call) async {
      if (call.method == 'talkRequested') {
        _openAssistant();
        return true;
      }
      if (call.method == 'submitRecognizedText') {
        final text = call.arguments as String? ?? '';
        final result = await widget.dependencies.assistant.answer(text);
        return _carResultMap(result);
      }
      if (call.method == 'submitText') {
        final text = call.arguments as String? ?? '';
        final result = await widget.dependencies.assistant.answer(text);
        return _carResultMap(result);
      }
      if (call.method == 'speakCarResponse') {
        await widget.dependencies.speechVoices.speak(
          call.arguments as String? ?? '',
          onKokoroStarted: () =>
              unawaited(_carChannel.invokeMethod<void>('responseAudioStarted')),
        );
        return true;
      }
      if (call.method == 'playCarPrayer') {
        final values = Map<Object?, Object?>.from(call.arguments as Map);
        await _carPrayerPlayback.play(
          PrayerChoice(
            id: values['id']! as int,
            name: values['name']! as String,
            isRoutine: values['isRoutine'] as bool? ?? false,
          ),
          announce: values['announce'] as bool? ?? true,
        );
        return true;
      }
      if (call.method == 'pauseCarPrayer') {
        await _carPrayerPlayback.pause();
        return true;
      }
      if (call.method == 'resumeCarPrayer') {
        await _carPrayerPlayback.resume();
        return true;
      }
      if (call.method == 'stopCarPrayer') {
        await _carPrayerPlayback.stop();
        return true;
      }
      return null;
    });
    _consumePendingCarAction();
  }

  Map<String, Object?> _carResultMap(AssistantResult result) =>
      Map<String, Object?>.from(result.toMap())
        ..['capturePrayerText'] =
            widget.dependencies.prayerConversation.isCapturingPrayerText;

  Future<void> _consumePendingCarAction() async {
    final pending = await _carChannel.invokeMethod<bool>('consumeTalkRequest');
    if (pending == true) _openAssistant();
  }

  void _openAssistant() {
    if (_openingAssistant) {
      _voiceController.requestListening();
      return;
    }
    _openingAssistant = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final navigator = _navigatorKey.currentState;
      if (navigator != null) {
        await navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => VoiceAssistantScreen(
              dependencies: widget.dependencies,
              autoStart: true,
              controller: _voiceController,
            ),
          ),
        );
      }
      _openingAssistant = false;
    });
  }

  @override
  void dispose() {
    _carPrayerPlayback.stop();
    _carChannel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.dependencies.themeController,
    builder: (context, _) => MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Private Concierge',
      debugShowCheckedModeBanner: false,
      theme: PrivateConciergeThemes.light,
      darkTheme: PrivateConciergeThemes.dark,
      themeMode: widget.dependencies.themeController.mode,
      home: widget.dependencies.profileService.load() == null
          ? ProfileOnboardingScreen(
              speechVoices: widget.dependencies.speechVoices,
              onComplete: (profile) async {
                await widget.dependencies.profileService.save(profile);
                if (mounted) setState(() {});
              },
            )
          : BootstrapScreen(dependencies: widget.dependencies),
    ),
  );
}

class _CarPrayerPlaybackController {
  _CarPrayerPlaybackController(
    this.dependencies, {
    required this.onStateChanged,
  });

  final AppDependencies dependencies;
  final Future<void> Function(Map<String, Object?> state) onStateChanged;
  bool _cancelled = false;
  bool _paused = false;
  Completer<void>? _resumeCompleter;

  Future<void> play(PrayerChoice choice, {bool announce = true}) async {
    await stop(notify: false);
    _cancelled = false;
    await _notify('playing', choice);
    try {
      if (announce) {
        await dependencies.speechVoices.speak("Let's begin.");
        if (_cancelled) return;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
      final prayers = await _prayersFor(choice);
      for (var index = 0; index < prayers.length && !_cancelled; index++) {
        await _waitUntilResumed();
        if (_cancelled) break;
        await dependencies.speechVoices.speakPrayer(prayers[index]);
        if (!_cancelled && index + 1 < prayers.length) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
    } finally {
      _paused = false;
      _resumeCompleter = null;
      await _notify(_cancelled ? 'stopped' : 'completed', choice);
    }
  }

  Future<List<Prayer>> _prayersFor(PrayerChoice choice) async {
    if (!choice.isRoutine) {
      return (await dependencies.prayers.prayers())
          .where((prayer) => prayer.id == choice.id)
          .toList();
    }
    final routines = await dependencies.prayers.prayerRoutines();
    final match = routines.where((routine) => routine.id == choice.id);
    return match.isEmpty
        ? const []
        : PrayerRoutineSequence.expand(match.first, routines);
  }

  Future<void> pause() async {
    if (_cancelled || _paused) return;
    _paused = true;
    _resumeCompleter = Completer<void>();
    await dependencies.speechVoices.pause();
    await onStateChanged(const {'state': 'paused'});
  }

  Future<void> resume() async {
    if (_cancelled || !_paused) return;
    await dependencies.speechVoices.resume();
    _paused = false;
    _resumeCompleter?.complete();
    _resumeCompleter = null;
    await onStateChanged(const {'state': 'playing'});
  }

  Future<void> stop({bool notify = true}) async {
    _cancelled = true;
    _paused = false;
    _resumeCompleter?.complete();
    _resumeCompleter = null;
    await dependencies.speechVoices.stop();
    if (notify) await onStateChanged(const {'state': 'stopped'});
  }

  Future<void> _waitUntilResumed() async {
    if (_paused) await _resumeCompleter?.future;
  }

  Future<void> _notify(String state, PrayerChoice choice) => onStateChanged({
    'state': state,
    'id': choice.id,
    'name': choice.name,
    'isRoutine': choice.isRoutine,
  });
}
