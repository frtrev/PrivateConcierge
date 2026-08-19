import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_dependencies.dart';
import '../../core/models/prayer.dart';
import '../../services/prayers/prayer_routine_sequence.dart';
import '../../services/voice/speech_voice_service.dart';
import '../voice_assistant/voice_assistant_screen.dart';

class PrayerLibraryScreen extends StatefulWidget {
  const PrayerLibraryScreen({super.key, required this.dependencies});
  final AppDependencies dependencies;

  @override
  State<PrayerLibraryScreen> createState() => _PrayerLibraryScreenState();
}

class _PrayerLibraryScreenState extends State<PrayerLibraryScreen> {
  late Future<(List<Prayer>, List<PrayerRoutine>)> data = _load();
  int? playingPrayerId;
  int? playingRoutineId;
  int playbackGeneration = 0;

  bool get playing => playingPrayerId != null || playingRoutineId != null;

  Future<(List<Prayer>, List<PrayerRoutine>)> _load() async => (
    await widget.dependencies.prayers.prayers(),
    await widget.dependencies.prayers.prayerRoutines(),
  );

  void _refresh() => setState(() => data = _load());

  String _timestamp(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '${value.month}/${value.day}/${value.year} at $hour:'
        '${value.minute.toString().padLeft(2, '0')} $suffix';
  }

  Future<String?> _askText(String title, String initial) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value?.trim().isEmpty == true ? null : value;
  }

  Future<void> _editPrayer(Prayer prayer) async {
    widget.dependencies.prayerConversation.beginEdit(prayer);
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => VoiceAssistantScreen(
          dependencies: widget.dependencies,
          initialPrompt:
              "Of course, I'm listening. Please say the updated prayer.",
        ),
      ),
    );
    _refresh();
  }

  Future<void> _editPrayerText(Prayer prayer) async {
    final controller = TextEditingController(text: prayer.text);
    var previewing = false;
    var previewGeneration = 0;
    final value = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final media = MediaQuery.of(context);
          final availableHeight =
              media.size.height - media.viewInsets.bottom - 270;
          final editorHeight = math.min(
            440.0,
            math.max(180.0, availableHeight),
          );
          return AlertDialog(
            title: Row(
              children: [
                IconButton.filledTonal(
                  tooltip: previewing ? 'Stop preview' : 'Preview prayer',
                  icon: Icon(previewing ? Icons.stop : Icons.play_arrow),
                  onPressed: previewing
                      ? () async {
                          previewGeneration++;
                          await widget.dependencies.speechVoices.stop();
                          if (context.mounted) {
                            setDialogState(() => previewing = false);
                          }
                        }
                      : controller.text.trim().isEmpty
                      ? null
                      : () async {
                          final generation = ++previewGeneration;
                          setDialogState(() => previewing = true);
                          try {
                            await widget.dependencies.speechVoices.speak(
                              controller.text.trim(),
                              purpose: SpeechPurpose.prayer,
                            );
                          } finally {
                            if (context.mounted &&
                                generation == previewGeneration) {
                              setDialogState(() => previewing = false);
                            }
                          }
                        },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Edit ${prayer.name}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              height: editorHeight,
              child: TextField(
                controller: controller,
                autofocus: true,
                onChanged: (_) => setDialogState(() {}),
                expands: true,
                minLines: null,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Prayer text',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: previewing ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: previewing
                    ? null
                    : () => Navigator.pop(context, controller.text.trim()),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    if (value != null && value.isNotEmpty) {
      await widget.dependencies.prayers.savePrayer(id: prayer.id, text: value);
      _refresh();
    }
  }

  Future<void> _deletePrayer(Prayer prayer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${prayer.name}?'),
        content: const Text('This also removes the prayer from every routine.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.dependencies.prayers.deletePrayer(prayer.id);
      _refresh();
    }
  }

  Future<void> _playRoutine(
    PrayerRoutine routine,
    List<PrayerRoutine> routines,
  ) async {
    if (playing) return;
    final generation = ++playbackGeneration;
    setState(() => playingRoutineId = routine.id);
    try {
      final prayers = PrayerRoutineSequence.expand(routine, routines);
      for (var index = 0; index < prayers.length; index++) {
        if (generation != playbackGeneration) return;
        await widget.dependencies.speechVoices.speakPrayer(prayers[index]);
        if (generation != playbackGeneration) return;
        if (index + 1 < prayers.length) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
    } finally {
      if (mounted && generation == playbackGeneration) {
        setState(() => playingRoutineId = null);
      }
    }
  }

  Future<void> _playPrayer(Prayer prayer) async {
    if (playing) return;
    final generation = ++playbackGeneration;
    setState(() => playingPrayerId = prayer.id);
    try {
      await widget.dependencies.speechVoices.speakPrayer(prayer);
    } finally {
      if (mounted && generation == playbackGeneration) {
        setState(() => playingPrayerId = null);
      }
    }
  }

  Future<void> _stopPlayback() async {
    playbackGeneration++;
    if (mounted) {
      setState(() {
        playingPrayerId = null;
        playingRoutineId = null;
      });
    }
    await widget.dependencies.speechVoices.stop();
  }

  @override
  void dispose() {
    playbackGeneration++;
    unawaited(widget.dependencies.speechVoices.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Prayers')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () async {
        final prayers = await widget.dependencies.prayers.prayers();
        final routines = await widget.dependencies.prayers.prayerRoutines();
        if (!context.mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => PrayerRoutineEditorScreen(
              dependencies: widget.dependencies,
              prayers: prayers,
              routines: routines,
            ),
          ),
        );
        _refresh();
      },
      icon: const Icon(Icons.playlist_add),
      label: const Text('New routine'),
    ),
    body: FutureBuilder<(List<Prayer>, List<PrayerRoutine>)>(
      future: data,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final (prayers, routines) = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            FilledButton.icon(
              onPressed: () {
                widget.dependencies.prayerConversation.beginRecording();
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => VoiceAssistantScreen(
                      dependencies: widget.dependencies,
                      initialPrompt:
                          "Of course, you can start praying after the beep, I'll be listening.",
                    ),
                  ),
                ).then((_) => _refresh());
              },
              icon: const Icon(Icons.mic),
              label: const Text('Record a prayer with Charon'),
            ),
            const SizedBox(height: 20),
            Text(
              'Saved prayers',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (prayers.isEmpty)
              const ListTile(title: Text('No prayers saved yet.')),
            for (final prayer in prayers)
              Card.outlined(
                child: ListTile(
                  leading: IconButton(
                    tooltip: playingPrayerId == prayer.id
                        ? 'Stop prayer'
                        : 'Play prayer',
                    icon: Icon(
                      playingPrayerId == prayer.id
                          ? Icons.stop
                          : Icons.play_arrow,
                    ),
                    onPressed: playingPrayerId == prayer.id
                        ? _stopPlayback
                        : playing
                        ? null
                        : () => _playPrayer(prayer),
                  ),
                  title: Text(prayer.name),
                  isThreeLine: true,
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        prayer.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text('Saved ${_timestamp(prayer.createdAt)}'),
                    ],
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) async {
                      if (action == 'rename') {
                        final name = await _askText(
                          'Rename prayer',
                          prayer.name,
                        );
                        if (name != null) {
                          await widget.dependencies.prayers.renamePrayer(
                            prayer.id,
                            name,
                          );
                          _refresh();
                        }
                      } else if (action == 'edit') {
                        await _editPrayer(prayer);
                      } else if (action == 'edit_text') {
                        await _editPrayerText(prayer);
                      } else if (action == 'remove') {
                        await _deletePrayer(prayer);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: Text('Rename')),
                      PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit with Charon'),
                      ),
                      PopupMenuItem(
                        value: 'edit_text',
                        child: Text('Edit text manually'),
                      ),
                      PopupMenuItem(value: 'remove', child: Text('Remove')),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),
            Text(
              'Prayer routines',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (routines.isEmpty)
              const ListTile(title: Text('No prayer routines yet.')),
            for (final routine in routines)
              Card.outlined(
                child: ListTile(
                  leading: IconButton(
                    tooltip: playingRoutineId == routine.id
                        ? 'Stop routine'
                        : 'Play routine',
                    icon: Icon(
                      playingRoutineId == routine.id
                          ? Icons.stop
                          : Icons.play_arrow,
                    ),
                    onPressed: playingRoutineId == routine.id
                        ? _stopPlayback
                        : playing || routine.steps.isEmpty
                        ? null
                        : () => _playRoutine(routine, routines),
                  ),
                  title: Text(routine.name),
                  subtitle: Text(
                    routine.steps
                        .map(
                          (step) =>
                              '${step.repeatCount}× ${step.name}${step.type == PrayerRoutineStepType.routine ? ' (routine)' : ''}',
                        )
                        .join(' • '),
                  ),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => PrayerRoutineEditorScreen(
                          dependencies: widget.dependencies,
                          prayers: prayers,
                          routines: routines,
                          routine: routine,
                        ),
                      ),
                    );
                    _refresh();
                  },
                  trailing: IconButton(
                    tooltip: 'Remove routine',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await widget.dependencies.prayers.deletePrayerRoutine(
                        routine.id,
                      );
                      _refresh();
                    },
                  ),
                ),
              ),
            const SizedBox(height: 90),
          ],
        );
      },
    ),
  );
}

class PrayerRoutineEditorScreen extends StatefulWidget {
  const PrayerRoutineEditorScreen({
    super.key,
    required this.dependencies,
    required this.prayers,
    required this.routines,
    this.routine,
  });
  final AppDependencies dependencies;
  final List<Prayer> prayers;
  final List<PrayerRoutine> routines;
  final PrayerRoutine? routine;

  @override
  State<PrayerRoutineEditorScreen> createState() =>
      _PrayerRoutineEditorScreenState();
}

class _PrayerRoutineEditorScreenState extends State<PrayerRoutineEditorScreen> {
  late final TextEditingController name = TextEditingController(
    text: widget.routine?.name,
  );
  late List<PrayerRoutineStep> selected = [...?widget.routine?.steps];

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final availableRoutines = widget.routines.where(_canNest).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.routine == null ? 'New prayer routine' : 'Edit prayer routine',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: name,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Routine name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Prayer order'),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: selected.length,
            onReorderItem: (oldIndex, newIndex) {
              setState(() {
                selected.insert(newIndex, selected.removeAt(oldIndex));
              });
            },
            itemBuilder: (_, index) => ListTile(
              key: ValueKey(
                '$index-${selected[index].type.name}-${selected[index].referenceId}',
              ),
              leading: const Icon(Icons.drag_handle),
              title: Text(
                '${selected[index].name}${selected[index].type == PrayerRoutineStepType.routine ? ' (routine)' : ''}',
              ),
              subtitle: Row(
                children: [
                  IconButton(
                    tooltip: 'Decrease repetitions',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: selected[index].repeatCount <= 1
                        ? null
                        : () => setState(() {
                            selected[index] = selected[index].copyWith(
                              repeatCount: selected[index].repeatCount - 1,
                            );
                          }),
                  ),
                  Text(
                    '${selected[index].repeatCount} time${selected[index].repeatCount == 1 ? '' : 's'}',
                  ),
                  IconButton(
                    tooltip: 'Increase repetitions',
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: selected[index].repeatCount >= 100
                        ? null
                        : () => setState(() {
                            selected[index] = selected[index].copyWith(
                              repeatCount: selected[index].repeatCount + 1,
                            );
                          }),
                  ),
                ],
              ),
              trailing: IconButton(
                tooltip: 'Remove step',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => setState(() => selected.removeAt(index)),
              ),
            ),
          ),
          if (widget.prayers.isNotEmpty) ...[
            const Divider(),
            const Text('Add saved prayers'),
            for (final prayer in widget.prayers)
              ListTile(
                title: Text(prayer.name),
                trailing: const Icon(Icons.add_circle_outline),
                onTap: () => setState(
                  () => selected.add(
                    PrayerRoutineStep(
                      type: PrayerRoutineStepType.prayer,
                      referenceId: prayer.id,
                      name: prayer.name,
                      repeatCount: 1,
                      prayer: prayer,
                    ),
                  ),
                ),
              ),
          ],
          if (availableRoutines.isNotEmpty) ...[
            const Divider(),
            const Text('Add another routine'),
            for (final routine in availableRoutines)
              ListTile(
                leading: const Icon(Icons.account_tree_outlined),
                title: Text(routine.name),
                trailing: const Icon(Icons.add_circle_outline),
                onTap: () => setState(
                  () => selected.add(
                    PrayerRoutineStep(
                      type: PrayerRoutineStepType.routine,
                      referenceId: routine.id,
                      name: routine.name,
                      repeatCount: 1,
                    ),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: name.text.trim().isEmpty || selected.isEmpty
                ? null
                : () async {
                    await widget.dependencies.prayers.savePrayerRoutine(
                      id: widget.routine?.id,
                      name: name.text,
                      steps: selected,
                    );
                    if (context.mounted) Navigator.pop(context);
                  },
            child: const Text('Save routine'),
          ),
        ],
      ),
    );
  }

  bool _canNest(PrayerRoutine candidate) {
    final editingId = widget.routine?.id;
    if (editingId == null) return true;
    if (candidate.id == editingId) return false;
    final byId = {for (final routine in widget.routines) routine.id: routine};
    bool containsEditing(int routineId, Set<int> visited) {
      if (!visited.add(routineId)) return false;
      final routine = byId[routineId];
      if (routine == null) return false;
      for (final step in routine.steps) {
        if (step.type != PrayerRoutineStepType.routine) continue;
        if (step.referenceId == editingId ||
            containsEditing(step.referenceId, visited)) {
          return true;
        }
      }
      return false;
    }

    return !containsEditing(candidate.id, <int>{});
  }
}
