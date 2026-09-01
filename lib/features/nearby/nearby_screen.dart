import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_dependencies.dart';
import '../../core/models/geo.dart';
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

class _NearbyScreenState extends State<NearbyScreen>
    with WidgetsBindingObserver {
  final searchController = TextEditingController();
  String? category;
  String query = '';
  Future<List<PointOfInterest>> results = Future.value(const []);
  Coordinates? _origin;
  DateTime? _updatedAt;
  StreamSubscription<Coordinates>? _locationSubscription;
  bool _refreshing = false;
  int _searchGeneration = 0;
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
    WidgetsBinding.instance.addObserver(this);
    category = widget.initialCategory;
    _origin = widget.dependencies.bootstrap.coordinates;
    _search();
    unawaited(_refreshLocation());
    _locationSubscription = widget.dependencies.bootstrap
        .foregroundLocationUpdates()
        .listen(_handleLocation, onError: (_) {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshLocation());
  }

  void _handleLocation(Coordinates value) {
    final previous = _origin;
    _origin = value;
    if (previous == null || distanceMeters(previous, value) >= 250) {
      _updatedAt = DateTime.now();
      if (mounted) setState(_search);
    }
  }

  Future<void> _refreshLocation() async {
    if (_refreshing) return;
    if (mounted) setState(() => _refreshing = true);
    try {
      final value = await widget.dependencies.bootstrap
          .refreshCurrentLocation();
      if (!mounted) return;
      _origin = value;
      _updatedAt = DateTime.now();
      setState(_search);
    } catch (_) {
      // Keep the last known location and existing results when a fix is unavailable.
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _search() {
    final origin = _origin;
    if (origin == null) {
      results = Future.value(const []);
      return;
    }
    final generation = ++_searchGeneration;
    final pending = widget.dependencies.nearby.search(
      origin,
      category: category,
      query: query,
    );
    results = pending.then(
      (value) =>
          generation == _searchGeneration ? value : const <PointOfInterest>[],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_locationSubscription?.cancel());
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Nearby'),
      actions: [
        IconButton(
          tooltip: 'Refresh current location',
          onPressed: _refreshing ? null : _refreshLocation,
          icon: _refreshing
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.my_location),
        ),
      ],
    ),
    body: Column(
      children: [
        if (_updatedAt != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 16),
                const SizedBox(width: 6),
                Text(
                  'Using current location • updated ${_time(_updatedAt!)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
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
              for (final value in <String?>[null, ...categories])
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: ChoiceChip(
                    label: Text(value ?? 'All'),
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
                          ? 'No matching places near your current location.'
                          : '“$query” was not found near your current location.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: _refreshLocation,
                child: ListView.builder(
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
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    ),
  );

  String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
