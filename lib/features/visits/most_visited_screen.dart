import 'package:flutter/material.dart';

import '../../core/models/visited_place.dart';
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
  late Future<List<VisitedPlace>> places;
  late Future<bool> backgroundEnabled;

  @override
  void initState() {
    super.initState();
    places = widget.privateData.mostVisited();
    backgroundEnabled = widget.visitTracker.backgroundTrackingEnabled;
  }

  void _refresh() => setState(() => places = widget.privateData.mostVisited());

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Most visited places')),
    body: RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: FutureBuilder<List<VisitedPlace>>(
        future: places,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
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
          final values = snapshot.data ?? [];
          if (values.isEmpty) {
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
                  'Enable background visits, then staying near the same public or custom place for about two minutes records a private visit on this device.',
                  textAlign: TextAlign.center,
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            itemCount: values.length + 2,
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
              final place = values[index - 2];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                leading: CircleAvatar(child: Text('$index')),
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

  String _relativeDate(DateTime value) {
    final difference = DateTime.now().difference(value);
    if (difference.inMinutes < 1) return 'just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    if (difference.inDays < 7) return '${difference.inDays}d ago';
    return '${value.month}/${value.day}/${value.year}';
  }
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
                : 'Requires “Always” location access. iOS shows the location indicator while tracking.',
          ),
          trailing: active
              ? const Icon(Icons.check_circle)
              : FilledButton(onPressed: onEnable, child: const Text('Enable')),
        ),
      );
    },
  );
}
