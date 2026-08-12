import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/app_dependencies.dart';
import '../../core/models/assistant_result.dart';
import '../../core/models/poi.dart';
import '../../services/voice/voice_recognition_service.dart';

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
  });
  final AppDependencies dependencies;
  final bool autoStart;
  final VoiceAssistantController? controller;
  @override
  State<VoiceAssistantScreen> createState() => _VoiceAssistantScreenState();
}

class _VoiceAssistantScreenState extends State<VoiceAssistantScreen> {
  static const _carChannel = MethodChannel('charon/car');
  final textController = TextEditingController();
  VoiceRecognitionState state = VoiceRecognitionState.idle;
  String transcript = '';
  String response =
      'Tap the microphone and ask about your location or nearby places.';
  PointOfInterest? selectedPlace;
  bool openingMaps = false;

  @override
  void initState() {
    super.initState();
    widget.controller?.attach(_requestListening);
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _listen());
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
    await for (final result in widget.dependencies.voice.listenOnce()) {
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
    });
    final answer = await widget.dependencies.assistant.answer(text);
    response = answer.response;
    selectedPlace = answer.selectedPlace?.toPoi();
    try {
      await _carChannel.invokeMethod<void>('publishResult', answer.toMap());
    } on PlatformException {
      // The phone assistant remains usable when no vehicle session is active.
    }
    if (answer.type == AssistantResultType.navigation) {
      final place = selectedPlace;
      if (place != null) {
        final opened = await widget.dependencies.navigation.navigateTo(place);
        if (!opened) {
          response = 'I could not open the maps app. ${answer.response}';
        }
      }
    }
    if (mounted) setState(() => state = VoiceRecognitionState.completed);
  }

  @override
  void dispose() {
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(response),
                          if (selectedPlace != null) ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: openingMaps ? null : _openInMaps,
                              icon: openingMaps
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.map_outlined),
                              label: Text(
                                openingMaps ? 'Opening…' : 'Open in Maps',
                              ),
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
