import 'package:flutter/material.dart';

import '../../core/models/visited_place.dart';
import '../../core/models/visit_diagnostic.dart';
import '../../core/models/visit_session.dart';
import '../../core/models/pending_visit_group.dart';
import '../../core/models/poi.dart';
import '../../services/storage/private_data_store.dart';
import '../../services/visits/visit_tracker.dart';

class MostVisitedScreen extends StatefulWidget {
  const MostVisitedScreen({
    super.key,
    required this.privateData,
    required this.visitTracker,
  });

  final PrivateDataStore privateData;
  final VisitTracker visitTracker;

  @override
  State<MostVisitedScreen> createState() => _MostVisitedScreenState();
}

class _MostVisitedScreenState extends State<MostVisitedScreen> {
  late Future<_MostVisitedData> data;
  late Future<bool> backgroundEnabled;

  @override
  void initState() {
    super.initState();
    data = _loadData();
    backgroundEnabled = widget.visitTracker.backgroundTrackingEnabled;
  }

  Future<_MostVisitedData> _loadData() async => _MostVisitedData(
    places: await widget.privateData.mostVisited(),
    pendingGroups: await widget.privateData.pendingVisitGroups(),
  );

  Future<void> _refresh() async {
    final refreshed = _loadData();
    setState(() => data = refreshed);
    await refreshed;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Most visited places'),
      actions: [
        if (widget.privateData is VisitDiagnosticStore)
          IconButton(
            tooltip: 'Tracking diagnostics',
            icon: const Icon(Icons.monitor_heart_outlined),
            onPressed: _showDiagnostics,
          ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<_MostVisitedData>(
        future: data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              padding: const EdgeInsets.all(24),
              children: const [
                Icon(Icons.error_outline, size: 48),
                SizedBox(height: 12),
                Text(
                  'Visit history could not be loaded.',
                  textAlign: TextAlign.center,
                ),
              ],
            );
          }
          final values = snapshot.data?.places ?? const <VisitedPlace>[];
          final pending =
              snapshot.data?.pendingGroups ?? const <PendingVisitGroup>[];
          if (values.isEmpty && pending.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(28),
              children: [
                _BackgroundTrackingCard(
                  enabled: backgroundEnabled,
                  onEnable: _enableBackgroundTracking,
                ),
                const SizedBox(height: 40),
                const Icon(Icons.place_outlined, size: 64),
                const SizedBox(height: 18),
                const Text(
                  'No visited places yet',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Enable background visits, then several consistent observations near the same public or custom place over about five minutes record a private visit on this device.',
                  textAlign: TextAlign.center,
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            itemCount: values.length + pending.length + 2,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _BackgroundTrackingCard(
                  enabled: backgroundEnabled,
                  onEnable: _enableBackgroundTracking,
                );
              }
              if (index == 1) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(8, 8, 8, 18),
                  child: Text(
                    'Stored only on this device. Continuous time at one place counts as one visit.',
                  ),
                );
              }
              final contentIndex = index - 2;
              if (contentIndex < pending.length) {
                return _PendingVisitGroupTile(
                  key: ValueKey('pending-visit-${pending[contentIndex].id}'),
                  group: pending[contentIndex],
                  onConfirm: (place) =>
                      _confirmGroup(pending[contentIndex], place),
                );
              }
              final place = values[contentIndex - pending.length];
              return ListTile(
                key: ValueKey('visited-place-${place.poiId}'),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                leading: CircleAvatar(
                  child: Text('${contentIndex - pending.length + 1}'),
                ),
                title: Text(place.name),
                subtitle: Text(
                  [
                    place.category,
                    if (place.address.isNotEmpty) place.address,
                    'Last visited ${_relativeDate(place.lastVisited)}',
                  ].join(' • '),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${place.visitCount}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(place.visitCount == 1 ? 'visit' : 'visits'),
                  ],
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => _VisitHistoryScreen(
                      place: place,
                      privateData: widget.privateData,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    ),
  );

  Future<void> _enableBackgroundTracking() async {
    final enabled = await widget.visitTracker.enableBackgroundTracking();
    if (!mounted) return;
    setState(() => backgroundEnabled = Future.value(enabled));
    if (!enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Allow location “Always” in Settings to record background visits.',
          ),
        ),
      );
    }
  }

  Future<void> _confirmGroup(
    PendingVisitGroup group,
    PointOfInterest place,
  ) async {
    await widget.privateData.resolvePendingVisitGroup(group.id, place);
    if (!mounted) return;
    _refresh();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Visit saved at ${place.name}.')));
  }

  Future<void> _showDiagnostics() async {
    final store = widget.privateData;
    if (store is! VisitDiagnosticStore) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) =>
          _TrackingDiagnosticsSheet(store: store as VisitDiagnosticStore),
    );
  }

  String _relativeDate(DateTime value) {
    final difference = DateTime.now().difference(value);
    if (difference.inMinutes < 1) return 'just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    if (difference.inDays < 7) return '${difference.inDays}d ago';
    return '${value.month}/${value.day}/${value.year}';
  }
}

class _MostVisitedData {
  const _MostVisitedData({required this.places, required this.pendingGroups});
  final List<VisitedPlace> places;
  final List<PendingVisitGroup> pendingGroups;
}

class _PendingVisitGroupTile extends StatefulWidget {
  const _PendingVisitGroupTile({
    super.key,
    required this.group,
    required this.onConfirm,
  });
  final PendingVisitGroup group;
  final Future<void> Function(PointOfInterest place) onConfirm;

  @override
  State<_PendingVisitGroupTile> createState() => _PendingVisitGroupTileState();
}

class _PendingVisitGroupTileState extends State<_PendingVisitGroupTile> {
  late bool expanded = widget.group.suggestedPlace == null;
  bool saving = false;

  @override
  Widget build(BuildContext context) {
    final suggested = widget.group.suggestedPlace;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Which place were you at?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.group.candidates.length} nearby places detected • ${_date(widget.group.arrival)}',
            ),
            if (suggested != null && !expanded) ...[
              const SizedBox(height: 14),
              Text(
                suggested.name,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (suggested.address.isNotEmpty) Text(suggested.address),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: saving ? null : () => _save(suggested),
                    child: const Text('I was here'),
                  ),
                  OutlinedButton(
                    onPressed: saving
                        ? null
                        : () => setState(() => expanded = true),
                    child: const Text('Not here this time'),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 10),
              for (final place in widget.group.candidates)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(place.name),
                            Text(
                              [
                                place.category,
                                if (place.address.isNotEmpty) place.address,
                              ].join(' • '),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: saving ? null : () => _save(place),
                        child: const Text('I was here'),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _save(PointOfInterest place) async {
    setState(() => saving = true);
    await widget.onConfirm(place);
    if (mounted) setState(() => saving = false);
  }

  String _date(DateTime value) => '${value.month}/${value.day}/${value.year}';
}

class _TrackingDiagnosticsSheet extends StatefulWidget {
  const _TrackingDiagnosticsSheet({required this.store});
  final VisitDiagnosticStore store;

  @override
  State<_TrackingDiagnosticsSheet> createState() =>
      _TrackingDiagnosticsSheetState();
}

class _VisitHistoryScreen extends StatelessWidget {
  const _VisitHistoryScreen({required this.place, required this.privateData});

  final VisitedPlace place;
  final PrivateDataStore privateData;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(place.name)),
    body: FutureBuilder<List<VisitSession>>(
      future: privateData.visitSessions(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(
            child: Text('Visit sessions could not be loaded.'),
          );
        }
        final sessions = (snapshot.data ?? const <VisitSession>[])
            .where((session) => session.poiId == place.poiId)
            .toList(growable: false);
        if (sessions.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No completed arrival and departure sessions are available for this place yet.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: sessions.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final session = sessions[index];
            final departure = session.departure!;
            return ListTile(
              leading: const Icon(Icons.history),
              title: Text(_sessionDate(session.arrival)),
              subtitle: Text(
                'Arrived ${_sessionTime(session.arrival)}\n'
                'Departed ${_sessionTime(departure)}',
              ),
              trailing: Text(
                _sessionDuration(departure.difference(session.arrival)),
              ),
              isThreeLine: true,
            );
          },
        );
      },
    ),
  );

  String _sessionDate(DateTime value) =>
      '${value.month}/${value.day}/${value.year}';

  String _sessionTime(DateTime value) {
    final hour = value.hour == 0
        ? 12
        : value.hour > 12
        ? value.hour - 12
        : value.hour;
    return '$hour:${value.minute.toString().padLeft(2, '0')} '
        '${value.hour >= 12 ? 'PM' : 'AM'}';
  }

  String _sessionDuration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    return hours == 0 ? '${minutes}m' : '${hours}h ${minutes}m';
  }
}

class _TrackingDiagnosticsSheetState extends State<_TrackingDiagnosticsSheet> {
  late Future<List<VisitDiagnostic>> diagnostics;

  @override
  void initState() {
    super.initState();
    diagnostics = widget.store.visitDiagnostics();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .78,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.monitor_heart_outlined),
            title: const Text('Tracking diagnostics'),
            subtitle: const Text(
              'Location delivery and visit decisions from the last 24 hours, stored only on this device.',
            ),
            trailing: IconButton(
              tooltip: 'Clear diagnostics',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await widget.store.clearVisitDiagnostics();
                if (mounted) {
                  setState(() => diagnostics = widget.store.visitDiagnostics());
                }
              },
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<VisitDiagnostic>>(
              future: diagnostics,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final events = snapshot.data!;
                if (events.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No diagnostics yet. Keep background visits enabled and check again after a trip.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: events.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final event = events[index];
                    return ListTile(
                      dense: true,
                      title: Text(event.event.replaceAll('_', ' ')),
                      subtitle: Text(event.detail),
                      trailing: Text(
                        _diagnosticTime(event.at),
                        textAlign: TextAlign.right,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );

  String _diagnosticTime(DateTime value) =>
      '${value.month}/${value.day}\n${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:${value.second.toString().padLeft(2, '0')}';
}

class _BackgroundTrackingCard extends StatelessWidget {
  const _BackgroundTrackingCard({
    required this.enabled,
    required this.onEnable,
  });

  final Future<bool> enabled;
  final Future<void> Function() onEnable;

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: enabled,
    builder: (context, snapshot) {
      final active = snapshot.data == true;
      return Card(
        child: ListTile(
          leading: Icon(active ? Icons.location_on : Icons.location_off),
          title: Text(
            active ? 'Background visits enabled' : 'Enable background visits',
          ),
          subtitle: Text(
            active
                ? 'Location is processed and stored only on this device.'
                : 'Requires “Always” location access. iOS delivers power-managed location events in the background.',
          ),
          trailing: active
              ? const Icon(Icons.check_circle)
              : FilledButton(onPressed: onEnable, child: const Text('Enable')),
        ),
      );
    },
  );
}
