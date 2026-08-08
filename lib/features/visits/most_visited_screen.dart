import 'package:flutter/material.dart';

import '../../core/models/visited_place.dart';
import '../../services/storage/private_data_store.dart';

class MostVisitedScreen extends StatefulWidget {
  const MostVisitedScreen({super.key, required this.privateData});

  final PrivateDataStore privateData;

  @override
  State<MostVisitedScreen> createState() => _MostVisitedScreenState();
}

class _MostVisitedScreenState extends State<MostVisitedScreen> {
  late Future<List<VisitedPlace>> places;

  @override
  void initState() {
    super.initState();
    places = widget.privateData.mostVisited();
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
              children: const [
                SizedBox(height: 80),
                Icon(Icons.place_outlined, size: 64),
                SizedBox(height: 18),
                Text(
                  'No visited places yet',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 10),
                Text(
                  'While the app is open, staying near the same place for about two minutes records a private visit on this device.',
                  textAlign: TextAlign.center,
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            itemCount: values.length + 1,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == 0) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(8, 8, 8, 18),
                  child: Text(
                    'Stored only on this device. Continuous time at one place counts as one visit.',
                  ),
                );
              }
              final place = values[index - 1];
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

  String _relativeDate(DateTime value) {
    final difference = DateTime.now().difference(value);
    if (difference.inMinutes < 1) return 'just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    if (difference.inDays < 7) return '${difference.inDays}d ago';
    return '${value.month}/${value.day}/${value.year}';
  }
}
