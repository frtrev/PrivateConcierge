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
  final searchController = TextEditingController();
  String? category;
  String query = '';
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
    'pharmacy',
    'entertainment',
    'shopping',
    'medical',
    'education',
    'lodging',
    'recreation',
    'service',
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
      query: query,
    );
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Nearby')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SearchBar(
            controller: searchController,
            hintText: 'Search downloaded places',
            leading: const Icon(Icons.search),
            trailing: query.isEmpty
                ? null
                : [
                    IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() {
                        searchController.clear();
                        query = '';
                        _search();
                      }),
                    ),
                  ],
            onChanged: (value) => setState(() {
              query = value;
              _search();
            }),
          ),
        ),
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
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      query.isEmpty
                          ? 'No matching places in this downloaded region.'
                          : '“$query” is not in this downloaded Overture package.',
                      textAlign: TextAlign.center,
                    ),
                  ),
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
