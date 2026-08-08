import 'package:flutter/material.dart';
import '../../app/app_dependencies.dart';
import '../../core/models/poi.dart';

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({
    super.key,
    required this.dependencies,
    this.initialCategory,
  });
  final AppDependencies dependencies;
  final String? initialCategory;
  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  String? category;
  late Future<List<PointOfInterest>> results;
  static const categories = [
    'restaurant',
    'gas',
    'historic',
    'park',
    'church',
    'gym',
    'museum',
    'grocery',
  ];
  @override
  void initState() {
    super.initState();
    category = widget.initialCategory;
    _search();
  }

  void _search() {
    results = widget.dependencies.nearby.search(
      widget.dependencies.bootstrap.coordinates!,
      category: category,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Nearby • 50 miles')),
    body: Column(
      children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              Padding(
                padding: const EdgeInsets.all(4),
                child: ChoiceChip(
                  label: const Text('All'),
                  selected: category == null,
                  onSelected: (_) => setState(() {
                    category = null;
                    _search();
                  }),
                ),
              ),
              for (final value in categories)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: ChoiceChip(
                    label: Text(value),
                    selected: category == value,
                    onSelected: (_) => setState(() {
                      category = value;
                      _search();
                    }),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<PointOfInterest>>(
            future: results,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.data!.isEmpty) {
                return const Center(
                  child: Text('No matching places in this downloaded region.'),
                );
              }
              return ListView.builder(
                itemCount: snapshot.data!.length,
                itemBuilder: (_, i) {
                  final point = snapshot.data![i];
                  return ListTile(
                    leading: const Icon(Icons.place_outlined),
                    title: Text(point.name),
                    subtitle: Text(
                      '${point.category} • ${(point.distanceMeters! / 1609.344).toStringAsFixed(1)} mi\n${point.address}',
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      icon: const Icon(Icons.navigation_outlined),
                      tooltip: 'Navigate',
                      onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Navigation handoff is available from Android Auto.',
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}
