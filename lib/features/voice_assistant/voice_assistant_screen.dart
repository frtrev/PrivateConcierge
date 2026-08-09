import 'package:flutter/material.dart';
import '../../app/app_dependencies.dart';
import '../../core/models/assistant_command.dart';
import '../../core/models/poi.dart';
import '../../services/voice/voice_recognition_service.dart';

class VoiceAssistantScreen extends StatefulWidget {
  const VoiceAssistantScreen({super.key, required this.dependencies});
  final AppDependencies dependencies;
  @override
  State<VoiceAssistantScreen> createState() => _VoiceAssistantScreenState();
}

class _VoiceAssistantScreenState extends State<VoiceAssistantScreen> {
  VoiceRecognitionState state = VoiceRecognitionState.idle;
  String transcript = '';
  String response =
      'Tap the microphone and ask about your location or nearby places.';

  @override
  void initState() {
    super.initState();
    response = _personalize(response);
  }

  Future<void> _listen() async {
    await for (final result in widget.dependencies.voice.listenOnce()) {
      if (!mounted) return;
      setState(() {
        state = result.state;
        if (result.message != null) response = result.message!;
        if (result.text != null) transcript = result.text!;
      });
      if (result.text != null) await _execute(result.text!);
    }
  }

  Future<void> _execute(String text) async {
    final command = widget.dependencies.commands.interpret(text);
    switch (command.intent) {
      case AssistantIntent.currentLocation:
      case AssistantIntent.currentRegion:
        response = widget.dependencies.bootstrap.region == null
            ? 'I do not have a current region.'
            : 'You are in ${widget.dependencies.bootstrap.region!.displayName}.';
      case AssistantIntent.downloadedRegions:
        final regions = await widget.dependencies.packages.installedRegions();
        response = regions.isEmpty
            ? 'No regions are downloaded.'
            : 'Downloaded: ${regions.map((e) => e.displayName).join(', ')}.';
      case AssistantIntent.findNearby:
        final origin = widget.dependencies.bootstrap.coordinates;
        if (origin == null) {
          response = 'Location is unavailable. Enable it to search nearby.';
          break;
        }
        final points = await widget.dependencies.nearby.search(
          origin,
          category: command.parameters['category'],
        );
        response = points.isEmpty
            ? 'I found no matching places in the downloaded region.'
            : _describe(points);
      case AssistantIntent.downloadCurrentRegion:
        response = 'The current region is already checked during startup.';
      case AssistantIntent.unknown:
        response =
            'I can answer where you are, list downloaded regions, or find nearby places.';
    }
    response = _personalize(response);
    if (mounted) setState(() => state = VoiceRecognitionState.completed);
  }

  String _personalize(String message) {
    final profile = widget.dependencies.profileService.load();
    if (profile == null) return message;
    final address = profile.preferredAddress.trim();
    final prefix = address.isEmpty ? '' : '$address, ';
    return switch (profile.personality) {
      'professional' => '$prefix$message',
      'playful' => '${prefix}here’s what I found: $message',
      _ => '${prefix}of course. $message',
    };
  }

  String _describe(List<PointOfInterest> points) =>
      'Nearby: ${points.take(3).map((p) => '${p.name}, ${(p.distanceMeters! / 1609.344).toStringAsFixed(1)} miles').join('; ')}.';
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
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(response),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Text(
            state == VoiceRecognitionState.listening
                ? 'Listening…'
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
