import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/models/user_profile.dart';
import '../../services/voice/speech_voice_service.dart';
import '../../services/voice/kokoro_tts_service.dart';

class ProfileOnboardingScreen extends StatefulWidget {
  const ProfileOnboardingScreen({
    super.key,
    required this.onComplete,
    required this.speechVoices,
    this.initialProfile,
    this.editing = false,
  });

  final Future<void> Function(UserProfile profile) onComplete;
  final SpeechVoiceService speechVoices;
  final UserProfile? initialProfile;
  final bool editing;

  @override
  State<ProfileOnboardingScreen> createState() =>
      _ProfileOnboardingScreenState();
}

class _ProfileOnboardingScreenState extends State<ProfileOnboardingScreen>
    with WidgetsBindingObserver {
  final nameController = TextEditingController();
  String address = 'name';
  String personality = 'warm';
  String voiceGender = 'male';
  bool saving = false;
  late Future<List<SpeechVoice>> voices;
  String? selectedVoiceId;
  bool noVoicesFound = false;
  late Future<List<SpeechEngine>> engines;
  String? selectedEngineId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final profile = widget.initialProfile;
    if (profile != null) {
      nameController.text = profile.name;
      address = profile.addressStyle;
      personality = profile.personality;
      voiceGender = profile.voiceGender;
    }
    engines = _loadEngines();
    voices = _loadVoices();
  }

  Future<List<SpeechEngine>> _loadEngines() async {
    if (!Platform.isAndroid) return const [];
    final values = await widget.speechVoices.engines();
    selectedEngineId = await widget.speechVoices.selectedEngineId();
    if (selectedEngineId == null && values.isNotEmpty) {
      selectedEngineId = values.first.id;
    }
    return values;
  }

  Future<List<SpeechVoice>> _loadVoices() async {
    final values = await widget.speechVoices.voices();
    selectedVoiceId = await widget.speechVoices.selectedVoiceId();
    if (selectedVoiceId == null && values.isNotEmpty) {
      selectedVoiceId = _preferredVoice(values, voiceGender).id;
    }
    noVoicesFound = values.isEmpty;
    return values;
  }

  SpeechVoice _preferredVoice(List<SpeechVoice> values, String gender) {
    if (Platform.isAndroid) {
      final googleSuffix = gender == 'female' ? 'iob-network' : 'iom-network';
      for (final voice in values) {
        if (voice.name.toLowerCase().contains(googleSuffix)) return voice;
      }
      return values.firstWhere(
        (voice) => voice.id == 'system:default',
        orElse: () => values.first,
      );
    }
    final preferredName = gender == 'female' ? 'tessa' : 'daniel';
    return values.cast<SpeechVoice?>().firstWhere(
      (voice) => voice!.name.toLowerCase() == preferredName,
      orElse: () => values.first,
    )!;
  }

  Future<void> _chooseVoiceGender(String gender) async {
    setState(() => voiceGender = gender);
    final values = await voices;
    if (values.isEmpty || !mounted) return;
    final voice = _preferredVoice(values, gender);
    setState(() => selectedVoiceId = voice.id);
    await _preview(voice.id);
  }

  Future<void> _preview(String voiceId) async {
    final profile = UserProfile(
      addressStyle: address,
      name: nameController.text.trim(),
      personality: personality,
      voiceGender: voiceGender,
    );
    final preferred = profile.preferredAddress.trim();
    await widget.speechVoices.preview(
      voiceId: voiceId,
      text: preferred.isEmpty ? 'Hello.' : 'Hello, $preferred.',
    );
  }

  void _refreshVoices() {
    setState(() => voices = _loadVoices());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && noVoicesFound) {
      _refreshVoices();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(28),
        children: [
          const SizedBox(height: 30),
          Icon(
            Icons.auto_awesome,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            widget.editing ? 'Assistant settings' : 'Make your concierge yours',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'This profile stays on your device and controls how your assistant speaks to you.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          TextField(
            controller: nameController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.name],
            selectAllOnFocus: true,
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
            decoration: const InputDecoration(
              labelText: 'Name or preferred form of address',
              hintText: 'Francisco',
            ),
          ),
          const SizedBox(height: 20),
          const Text('How should I address you?'),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 10.0;
              final width = (constraints.maxWidth - spacing) / 2;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final option in const [
                    ('mr', 'Mr.'),
                    ('maam', 'Ma’am'),
                    ('name', 'By name'),
                    ('other', 'Other'),
                  ])
                    SizedBox(
                      width: width,
                      child: ChoiceChip(
                        label: SizedBox(
                          width: double.infinity,
                          child: Text(option.$2, textAlign: TextAlign.center),
                        ),
                        selected: address == option.$1,
                        onSelected: (_) => setState(() => address = option.$1),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          const Text('Assistant personality'),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: personality,
            onChanged: (value) => setState(() => personality = value!),
            child: const Column(
              children: [
                RadioListTile(
                  value: 'warm',
                  title: Text('Warm and thoughtful'),
                ),
                RadioListTile(
                  value: 'professional',
                  title: Text('Polished and concise'),
                ),
                RadioListTile(
                  value: 'playful',
                  title: Text('Friendly and playful'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('Voice style'),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'male', label: Text('Male')),
              ButtonSegment(value: 'female', label: Text('Female')),
            ],
            selected: {voiceGender},
            onSelectionChanged: (selection) =>
                _chooseVoiceGender(selection.first),
          ),
          const SizedBox(height: 28),
          const Text('Charon voice'),
          const SizedBox(height: 8),
          ValueListenableBuilder<KokoroStatus>(
            valueListenable: widget.speechVoices.kokoro.status,
            builder: (context, status, _) => Card.outlined(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.graphic_eq),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Kokoro-82M embedded voices',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Optional private speech generated entirely on this device. OS voices remain available.',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Kokoro v1.1 INT8 • 140 MB download • about 205 MB installed',
                    ),
                    if (status.state == KokoroInstallState.downloading) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: status.totalBytes > 0
                            ? status.downloadedBytes / status.totalBytes
                            : null,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${(status.downloadedBytes / 1048576).toStringAsFixed(1)} of '
                        '${(status.totalBytes / 1048576).toStringAsFixed(1)} MB',
                      ),
                    ] else if (status.state ==
                        KokoroInstallState.installing) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                      const SizedBox(height: 6),
                      const Text('Verifying and installing…'),
                    ] else if (status.error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        status.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (status.installed)
                      const Row(
                        children: [
                          Icon(Icons.check_circle_outline),
                          SizedBox(width: 8),
                          Text('Downloaded and ready'),
                        ],
                      )
                    else
                      FilledButton.icon(
                        onPressed:
                            status.state == KokoroInstallState.downloading ||
                                status.state == KokoroInstallState.installing
                            ? null
                            : () async {
                                try {
                                  await widget.speechVoices.kokoro.download();
                                  if (mounted) _refreshVoices();
                                } catch (_) {}
                              },
                        icon: const Icon(Icons.download),
                        label: Text(
                          status.state == KokoroInstallState.failed
                              ? 'Retry Kokoro download'
                              : 'Download Kokoro voices',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (Platform.isAndroid) ...[
            FutureBuilder<List<SpeechEngine>>(
              future: engines,
              builder: (context, snapshot) {
                final values = snapshot.data ?? const <SpeechEngine>[];
                if (!snapshot.hasData) return const LinearProgressIndicator();
                if (values.isEmpty) {
                  return const Text('No text-to-speech engines were found.');
                }
                return DropdownButtonFormField<String>(
                  key: ValueKey(selectedEngineId),
                  initialValue:
                      values.any((engine) => engine.id == selectedEngineId)
                      ? selectedEngineId
                      : values.first.id,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Speech engine',
                  ),
                  items: [
                    for (final engine in values)
                      DropdownMenuItem(
                        value: engine.id,
                        child: Text(engine.name),
                      ),
                  ],
                  onChanged: (engineId) async {
                    if (engineId == null) return;
                    await widget.speechVoices.selectEngine(engineId);
                    if (!mounted) return;
                    setState(() {
                      selectedEngineId = engineId;
                      selectedVoiceId = null;
                      voices = _loadVoices();
                    });
                  },
                );
              },
            ),
            const SizedBox(height: 12),
          ],
          FutureBuilder<List<SpeechVoice>>(
            future: voices,
            builder: (context, snapshot) {
              final values = snapshot.data ?? const <SpeechVoice>[];
              if (!snapshot.hasData) {
                return const LinearProgressIndicator();
              }
              if (values.isEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('No installed English voices were found.'),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final opened = await widget.speechVoices
                            .installVoices();
                        if (!opened && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Voice installation is managed in your device text-to-speech settings.',
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Install voices'),
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    key: ValueKey(selectedVoiceId),
                    initialValue:
                        values.any((voice) => voice.id == selectedVoiceId)
                        ? selectedVoiceId
                        : values.first.id,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Voice',
                    ),
                    items: [
                      for (final voice in values)
                        DropdownMenuItem(
                          value: voice.id,
                          child: Text('${voice.name} (${voice.locale})'),
                        ),
                    ],
                    onChanged: (voiceId) async {
                      if (voiceId == null) return;
                      setState(() => selectedVoiceId = voiceId);
                      await _preview(voiceId);
                    },
                  ),
                  if (Platform.isAndroid) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: widget.speechVoices.installVoices,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Install more voices'),
                    ),
                    const Text(
                      'System default uses the voice selected in Android text-to-speech settings.',
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 28),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: nameController,
            builder: (context, value, _) => FilledButton.icon(
              onPressed: saving || value.text.trim().isEmpty
                  ? null
                  : () async {
                      FocusScope.of(context).unfocus();
                      setState(() => saving = true);
                      final voiceId = selectedVoiceId;
                      if (voiceId != null) {
                        await widget.speechVoices.select(voiceId);
                      }
                      await widget.onComplete(
                        UserProfile(
                          addressStyle: address,
                          name: nameController.text.trim(),
                          personality: personality,
                          voiceGender: voiceGender,
                        ),
                      );
                    },
              icon: const Icon(Icons.check),
              label: Text(
                saving
                    ? 'Saving…'
                    : widget.editing
                    ? 'Save changes'
                    : 'Continue',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
