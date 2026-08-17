import 'package:flutter/material.dart';

import '../../app/app_dependencies.dart';
import '../../core/models/prayer.dart';
import '../voice_assistant/voice_assistant_screen.dart';

class PrayerLibraryScreen extends StatefulWidget {
  const PrayerLibraryScreen({super.key, required this.dependencies});
  final AppDependencies dependencies;

  @override
  State<PrayerLibraryScreen> createState() => _PrayerLibraryScreenState();
}

class _PrayerLibraryScreenState extends State<PrayerLibraryScreen> {
  late Future<(List<Prayer>, List<PrayerRoutine>)> data = _load();
  bool playing = false;

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

  Future<void> _playRoutine(PrayerRoutine routine) async {
    if (playing) return;
    setState(() => playing = true);
    try {
      for (var index = 0; index < routine.prayers.length; index++) {
        await widget.dependencies.speechVoices.speak(
          routine.prayers[index].text,
        );
        if (index + 1 < routine.prayers.length) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
    } finally {
      if (mounted) setState(() => playing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Prayers')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () async {
        final prayers = await widget.dependencies.prayers.prayers();
        if (!context.mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => PrayerRoutineEditorScreen(
              dependencies: widget.dependencies,
              prayers: prayers,
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
                          "Of course, I'm listening. What prayer would you like me to record?",
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
                    tooltip: 'Play prayer',
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () =>
                        widget.dependencies.speechVoices.speak(prayer.text),
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
                    icon: Icon(
                      playing ? Icons.hourglass_top : Icons.play_arrow,
                    ),
                    onPressed: playing || routine.prayers.isEmpty
                        ? null
                        : () => _playRoutine(routine),
                  ),
                  title: Text(routine.name),
                  subtitle: Text(
                    routine.prayers.map((p) => p.name).join(' • '),
                  ),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => PrayerRoutineEditorScreen(
                          dependencies: widget.dependencies,
                          prayers: prayers,
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
    this.routine,
  });
  final AppDependencies dependencies;
  final List<Prayer> prayers;
  final PrayerRoutine? routine;

  @override
  State<PrayerRoutineEditorScreen> createState() =>
      _PrayerRoutineEditorScreenState();
}

class _PrayerRoutineEditorScreenState extends State<PrayerRoutineEditorScreen> {
  late final TextEditingController name = TextEditingController(
    text: widget.routine?.name,
  );
  late List<Prayer> selected = [...?widget.routine?.prayers];

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final available = widget.prayers
        .where((p) => !selected.any((s) => s.id == p.id))
        .toList();
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
              key: ValueKey(selected[index].id),
              leading: const Icon(Icons.drag_handle),
              title: Text(selected[index].name),
              trailing: IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => setState(() => selected.removeAt(index)),
              ),
            ),
          ),
          if (available.isNotEmpty) ...[
            const Divider(),
            const Text('Add saved prayers'),
            for (final prayer in available)
              ListTile(
                title: Text(prayer.name),
                trailing: const Icon(Icons.add_circle_outline),
                onTap: () => setState(() => selected.add(prayer)),
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
                      prayerIds: selected.map((p) => p.id).toList(),
                    );
                    if (context.mounted) Navigator.pop(context);
                  },
            child: const Text('Save routine'),
          ),
        ],
      ),
    );
  }
}
