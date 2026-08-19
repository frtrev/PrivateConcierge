import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/app_dependencies.dart';
import '../../core/models/assistant_result.dart';
import '../../core/models/poi.dart';
import '../../core/models/prayer.dart';
import '../../services/voice/voice_recognition_service.dart';
import '../../services/prayers/prayer_routine_sequence.dart';

class VoiceAssistantController {
  VoidCallback? _listener;

  void requestListening() => _listener?.call();
  void attach(VoidCallback listener) => _listener = listener;
  void detach(VoidCallback listener) {
    if (_listener == listener) _listener = null;
  }
}

class VoiceAssistantScreen extends StatefulWidget {
  const VoiceAssistantScreen({
    super.key,
    required this.dependencies,
    this.autoStart = false,
    this.controller,
    this.initialPrompt,
  });
  final AppDependencies dependencies;
  final bool autoStart;
  final VoiceAssistantController? controller;
  final String? initialPrompt;
  @override
  State<VoiceAssistantScreen> createState() => _VoiceAssistantScreenState();
}

class _VoiceAssistantScreenState extends State<VoiceAssistantScreen> {
  static const _carChannel = MethodChannel('charon/car');
  static const _placeActionChannel = MethodChannel('charon/place_actions');
  final textController = TextEditingController();
  VoiceRecognitionState state = VoiceRecognitionState.idle;
  String transcript = '';
  String response =
      'Tap the microphone and ask about your location or nearby places.';
  PointOfInterest? selectedPlace;
  AssistantResult? assistantResult;
  bool openingMaps = false;
  bool prayerPlaying = false;
  bool prayerPaused = false;
  bool androidPrayerInterrupted = false;
  bool prayerCancelled = false;
  Completer<void>? prayerResumeCompleter;

  @override
  void initState() {
    super.initState();
    widget.controller?.attach(_requestListening);
    final initialPrompt = widget.initialPrompt;
    if (initialPrompt != null) response = initialPrompt;
    if (widget.autoStart || initialPrompt != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (initialPrompt != null) {
          await widget.dependencies.speechVoices.speak(initialPrompt);
        }
        if (mounted) await _listen();
      });
    }
  }

  void _requestListening() {
    if (state == VoiceRecognitionState.listening ||
        state == VoiceRecognitionState.processing) {
      return;
    }
    _listen();
  }

  Future<void> _listen() async {
    await for (final result in widget.dependencies.voice.listenOnce(
      punctuatePauses:
          widget.dependencies.prayerConversation.isCapturingPrayerText,
    )) {
      if (!mounted) return;
      await _publishCarStatus(
        result.text == null && result.state == VoiceRecognitionState.completed
            ? VoiceRecognitionState.processing
            : result.state,
        result.message,
      );
      setState(() {
        state = result.state;
        if (result.message != null) response = result.message!;
        if (result.text != null) transcript = result.text!;
      });
      if (result.text != null) {
        await _publishCarStatus(VoiceRecognitionState.processing, 'Thinking…');
        await _execute(result.text!);
      }
    }
  }

  Future<void> _publishCarStatus(
    VoiceRecognitionState status,
    String? message,
  ) async {
    try {
      await _carChannel.invokeMethod<void>('publishStatus', {
        'state': status.name,
        'message': message,
      });
    } on PlatformException {
      // No active vehicle session is a normal phone-only state.
    }
  }

  Future<void> _execute(String text) async {
    if (text.trim().isEmpty) return;
    setState(() {
      transcript = text.trim();
      state = VoiceRecognitionState.processing;
      selectedPlace = null;
      assistantResult = null;
    });
    final answer = await widget.dependencies.assistant.answer(text);
    response = answer.spokenResponse;
    selectedPlace = answer.selectedPlace?.toPoi();
    assistantResult = answer;
    final prayerChoice =
        answer.context.lastIntent == 'playPrayer' &&
            answer.prayerChoices.length == 1
        ? answer.prayerChoices.single
        : null;
    if (mounted) {
      setState(() {
        if (prayerChoice != null) prayerPlaying = true;
      });
    }
    try {
      await _carChannel.invokeMethod<void>('publishResult', answer.toMap());
    } on PlatformException {
      // The phone assistant remains usable when no vehicle session is active.
    }
    final place = answer.selectedPlace;
    if (place != null && answer.actions.isNotEmpty) {
      final action = answer.actions.first;
      if (action.type == AssistantActionType.call &&
          place.phoneNumber != null) {
        await _invokePlaceAction('call', place.phoneNumber!);
      } else if (action.type == AssistantActionType.openWebsite &&
          place.website != null) {
        await _invokePlaceAction('openWebsite', place.website!);
      }
    }
    if (answer.type == AssistantResultType.navigation) {
      final place = selectedPlace;
      if (place != null) {
        final opened = await widget.dependencies.navigation.navigateTo(place);
        if (!opened) {
          response = 'I could not open the maps app. ${answer.spokenResponse}';
        }
      }
    }
    final asksFollowUp =
        answer.type != AssistantResultType.navigation &&
        answer.spokenResponse.trimRight().endsWith('?');
    if (answer.type != AssistantResultType.navigation) {
      try {
        await widget.dependencies.speechVoices.speak(answer.spokenResponse);
      } on PlatformException {
        // Text remains available if speech synthesis is unavailable.
      }
    }
    if (prayerChoice != null) {
      await _waitForPrayerResume();
      await Future<void>.delayed(const Duration(seconds: 2));
      await _playPrayerChoice(prayerChoice, announce: false);
    }
    if (mounted) setState(() => state = VoiceRecognitionState.completed);
    if (asksFollowUp && mounted) {
      await _listen();
    }
  }

  Future<void> _invokePlaceAction(String method, String value) async {
    try {
      await _placeActionChannel.invokeMethod<bool>(method, {'value': value});
    } on PlatformException {
      // The response still explains what data is available if launch fails.
    }
  }

  @override
  void dispose() {
    prayerCancelled = true;
    if (prayerResumeCompleter?.isCompleted == false) {
      prayerResumeCompleter!.complete();
    }
    unawaited(widget.dependencies.speechVoices.stop());
    widget.controller?.detach(_requestListening);
    textController.dispose();
    super.dispose();
  }

  void _submitText(String value) {
    textController.clear();
    _execute(value);
  }

  Future<void> _openInMaps() async {
    final place = selectedPlace;
    if (place == null || openingMaps) return;
    setState(() => openingMaps = true);
    final opened = await widget.dependencies.navigation.navigateTo(place);
    if (!mounted) return;
    setState(() => openingMaps = false);
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('I could not open the maps app.')),
      );
    }
  }

  Future<void> _openPlaceInMaps(PlaceResult place) async {
    if (openingMaps) return;
    setState(() => openingMaps = true);
    final opened = await widget.dependencies.navigation.navigateTo(
      place.toPoi(),
    );
    if (!mounted) return;
    setState(() => openingMaps = false);
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('I could not open the maps app.')),
      );
    }
  }

  Future<void> _playPrayerChoice(
    PrayerChoice choice, {
    bool announce = true,
  }) async {
    if (!prayerPlaying && mounted) {
      setState(() {
        prayerPlaying = true;
        prayerCancelled = false;
      });
    }
    if (announce) {
      await widget.dependencies.speechVoices.speak("Let's begin.");
      await _waitForPrayerResume();
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    try {
      if (!choice.isRoutine) {
        await _speakPausablePrayer(choice.id);
        return;
      }
      final routines = await widget.dependencies.prayers.prayerRoutines();
      final matches = routines.where((routine) => routine.id == choice.id);
      if (matches.isEmpty) return;
      final prayers = PrayerRoutineSequence.expand(matches.first, routines);
      for (var index = 0; index < prayers.length; index++) {
        if (prayerCancelled) return;
        await _speakPausablePrayerValue(prayers[index]);
        if (!prayerCancelled && index + 1 < prayers.length) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          prayerPlaying = false;
          prayerPaused = false;
        });
      }
    }
  }

  Future<void> _speakPausablePrayer(int id) async {
    final prayers = await widget.dependencies.prayers.prayers();
    final matches = prayers.where((prayer) => prayer.id == id);
    if (matches.isNotEmpty) await _speakPausablePrayerValue(matches.first);
  }

  Future<void> _speakPausablePrayerValue(Prayer prayer) async {
    do {
      await _waitForPrayerResume();
      if (prayerCancelled) return;
      androidPrayerInterrupted = false;
      await widget.dependencies.speechVoices.speakPrayer(prayer);
      await _waitForPrayerResume();
    } while (Platform.isAndroid && androidPrayerInterrupted);
  }

  Future<void> _waitForPrayerResume() async {
    if (!prayerPaused || prayerCancelled) return;
    prayerResumeCompleter ??= Completer<void>();
    await prayerResumeCompleter!.future;
  }

  Future<void> _togglePrayerPause() async {
    if (!prayerPlaying) return;
    if (prayerPaused) {
      await widget.dependencies.speechVoices.resume();
      prayerResumeCompleter?.complete();
      prayerResumeCompleter = null;
      if (mounted) setState(() => prayerPaused = false);
    } else {
      if (Platform.isAndroid) androidPrayerInterrupted = true;
      if (mounted) setState(() => prayerPaused = true);
      await widget.dependencies.speechVoices.pause();
    }
  }

  String _placeDetail(PlaceResult place) {
    final details = <String>[];
    final meters = place.distanceMeters;
    if (meters != null) {
      details.add('${(meters / 1609.344).toStringAsFixed(1)} miles');
    }
    if (place.isOpenNow != null) {
      details.add(place.isOpenNow! ? 'Open now' : 'Closed');
    }
    if (place.address.trim().isNotEmpty) details.add(place.address.trim());
    if (details.isEmpty && place.category.isNotEmpty) {
      details.add(place.category);
    }
    if (place.arrival != null) {
      details.add(
        'Arrived: ${_visitTimestamp(place.arrival!)}  Left: ${place.departure == null ? 'Still there' : _visitTimestamp(place.departure!)}',
      );
    }
    return details.join(' · ');
  }

  String _visitTimestamp(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')} $hour:${value.minute.toString().padLeft(2, '0')} $suffix';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Assistant')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                if (transcript.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Card(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(transcript),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Card(
                    color: assistantResult?.usedLocalAi == true
                        ? Theme.of(context).colorScheme.tertiaryContainer
                        : null,
                    shape: assistantResult?.usedLocalAi == true
                        ? RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.tertiary,
                              width: 2,
                            ),
                          )
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(response),
                          if (assistantResult?.usedLocalAi == true) ...[
                            const SizedBox(height: 10),
                            const Chip(
                              avatar: Icon(Icons.smart_toy, size: 18),
                              label: Text('Qwen Local AI response'),
                            ),
                          ],
                          if (assistantResult?.prayerChoices.isNotEmpty ==
                              true) ...[
                            const SizedBox(height: 12),
                            for (final prayer in assistantResult!.prayerChoices)
                              Card.outlined(
                                child: ListTile(
                                  leading: Icon(
                                    prayer.isRoutine
                                        ? Icons.playlist_play
                                        : Icons.self_improvement,
                                  ),
                                  title: Text(prayer.name),
                                  subtitle: prayer.isRoutine
                                      ? const Text('Prayer routine')
                                      : const Text('Prayer'),
                                  trailing: const Icon(Icons.play_arrow),
                                  onTap: () => _playPrayerChoice(prayer),
                                ),
                              ),
                          ],
                          if (prayerPlaying) ...[
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _togglePrayerPause,
                              icon: Icon(
                                prayerPaused ? Icons.play_arrow : Icons.pause,
                              ),
                              label: Text(
                                prayerPaused ? 'Resume prayer' : 'Pause prayer',
                              ),
                            ),
                          ],
                          if (assistantResult?.places.isNotEmpty == true) ...[
                            const SizedBox(height: 12),
                            for (final place in assistantResult!.places)
                              Card.outlined(
                                child: ListTile(
                                  title: Text(place.name),
                                  subtitle: Text(_placeDetail(place)),
                                  trailing: IconButton(
                                    tooltip: 'Open in Maps',
                                    onPressed: openingMaps
                                        ? null
                                        : () => _openPlaceInMaps(place),
                                    icon: const Icon(Icons.directions_outlined),
                                  ),
                                  onTap: openingMaps
                                      ? null
                                      : () => _openPlaceInMaps(place),
                                ),
                              ),
                          ] else if (selectedPlace != null) ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: openingMaps ? null : _openInMaps,
                              icon: const Icon(Icons.map_outlined),
                              label: const Text('Open in Maps'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          TextField(
            controller: textController,
            textInputAction: TextInputAction.send,
            enabled:
                state != VoiceRecognitionState.listening &&
                state != VoiceRecognitionState.processing,
            decoration: InputDecoration(
              hintText: 'Ask about nearby places',
              prefixIcon: const Icon(Icons.chat_bubble_outline),
              suffixIcon: IconButton(
                tooltip: 'Send',
                icon: const Icon(Icons.send),
                onPressed: () => _submitText(textController.text),
              ),
            ),
            onSubmitted: _submitText,
          ),
          const SizedBox(height: 16),
          Text(
            state == VoiceRecognitionState.listening
                ? 'Listening…'
                : state == VoiceRecognitionState.processing
                ? 'Searching on this phone…'
                : 'Push to talk',
          ),
          const SizedBox(height: 12),
          FloatingActionButton.large(
            onPressed: state == VoiceRecognitionState.listening
                ? null
                : _listen,
            child: Icon(
              state == VoiceRecognitionState.listening
                  ? Icons.graphic_eq
                  : Icons.mic,
            ),
          ),
        ],
      ),
    ),
  );
}
