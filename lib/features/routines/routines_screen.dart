import 'package:flutter/material.dart';

import '../../core/models/routine_pattern.dart';
import '../../services/routines/routine_engine.dart';

class RoutinesScreen extends StatelessWidget {
  const RoutinesScreen({super.key, required this.engine});

  final RoutineEngine engine;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Learned routines')),
    body: FutureBuilder<List<RoutinePattern>>(
      future: engine.patterns(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final patterns = snapshot.data!;
        if (patterns.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'No routine is strong enough yet. Three completed visits to the same place on the same weekday establish a pattern.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: patterns.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final pattern = patterns[index];
            return Card(
              child: ListTile(
                leading: const Icon(Icons.auto_graph),
                title: Text(pattern.placeName),
                subtitle: Text(
                  '${_weekday(pattern.weekday)} • usually ${_time(pattern.typicalArrivalMinute)}–${_time(pattern.typicalDepartureMinute)}\n${pattern.sampleCount} visits • ${pattern.category}',
                ),
                isThreeLine: true,
              ),
            );
          },
        );
      },
    ),
  );

  static String _weekday(int value) => const [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ][value - 1];

  static String _time(int minute) {
    final normalized = minute % 1440;
    final hour = normalized ~/ 60;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:${(normalized % 60).toString().padLeft(2, '0')} $period';
  }
}
