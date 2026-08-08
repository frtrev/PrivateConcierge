import 'package:flutter/material.dart';

import '../../core/models/geo.dart';
import '../../core/models/poi.dart';
import '../../services/storage/private_data_store.dart';

class MyPlacesScreen extends StatefulWidget {
  const MyPlacesScreen({
    super.key,
    required this.privateData,
    required this.getCurrentLocation,
  });

  final PrivateDataStore privateData;
  final Future<Coordinates> Function() getCurrentLocation;

  @override
  State<MyPlacesScreen> createState() => _MyPlacesScreenState();
}

class _MyPlacesScreenState extends State<MyPlacesScreen> {
  late Future<List<PointOfInterest>> places;

  @override
  void initState() {
    super.initState();
    places = widget.privateData.customPlaces();
  }

  void _refresh() => setState(() => places = widget.privateData.customPlaces());

  Future<void> _addCurrentLocation() async {
    var placeName = 'Home';
    var fieldVersion = 0;
    var tag = 'home';
    var saving = false;
    String? error;
    await showDialog<void>(
      context: context,
      barrierDismissible: !saving,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          scrollable: true,
          icon: const Icon(Icons.add_location_alt_outlined, size: 40),
          title: const Text('Set current location'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Create a private custom POI at your current location. It stays only on this device.',
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  for (final choice in const [
                    ('home', 'Home'),
                    ('work', 'Work'),
                    ('other', 'Other'),
                  ])
                    ChoiceChip(
                      label: Text(choice.$2),
                      selected: tag == choice.$1,
                      onSelected: saving
                          ? null
                          : (_) => setDialogState(() {
                              tag = choice.$1;
                              if (choice.$1 != 'other') {
                                placeName = choice.$2;
                              } else if (placeName == 'Home' ||
                                  placeName == 'Work') {
                                placeName = '';
                              }
                              fieldVersion++;
                            }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: ValueKey(fieldVersion),
                initialValue: placeName,
                onChanged: (value) => placeName = value,
                enabled: !saving,
                autofocus: false,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Place name',
                  hintText: 'Home, Work, Gym, Mom’s house…',
                  border: OutlineInputBorder(),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      final name = placeName.trim();
                      if (name.isEmpty) {
                        setDialogState(() => error = 'Enter a place name.');
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        error = null;
                      });
                      Coordinates? currentCoordinates;
                      try {
                        currentCoordinates = await widget.getCurrentLocation();
                        await widget.privateData.saveCustomPlace(
                          name: name,
                          tag: tag,
                          coordinates: currentCoordinates,
                        );
                        if (!mounted || !dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        _refresh();
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(
                            content: Text('$name saved on this device.'),
                          ),
                        );
                      } on CustomPlaceConflictException catch (conflict) {
                        if (!mounted || !dialogContext.mounted) return;
                        setDialogState(() => saving = false);
                        final overwrite = await showDialog<bool>(
                          context: this.context,
                          builder: (context) => AlertDialog(
                            icon: const Icon(Icons.location_on_outlined),
                            title: Text(
                              '${conflict.existing.name} already exists',
                            ),
                            content: const Text(
                              'Would you like to replace its saved location, or return and enter another name?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Use another name'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Overwrite'),
                              ),
                            ],
                          ),
                        );
                        if (overwrite != true ||
                            !mounted ||
                            !dialogContext.mounted) {
                          if (dialogContext.mounted) {
                            setDialogState(
                              () => error =
                                  'Choose another name, or select a different tag.',
                            );
                          }
                          return;
                        }
                        setDialogState(() => saving = true);
                        await widget.privateData.saveCustomPlace(
                          name: name,
                          tag: tag,
                          coordinates: currentCoordinates!,
                          overwrite: true,
                        );
                        if (!mounted || !dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        _refresh();
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(
                            content: Text('$name updated on this device.'),
                          ),
                        );
                      } catch (_) {
                        if (!dialogContext.mounted) return;
                        setDialogState(() {
                          saving = false;
                          error =
                              'Current location is unavailable. Check location services and try again.';
                        });
                      }
                    },
              icon: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
              label: Text(saving ? 'Locating…' : 'Save current'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('My places')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _addCurrentLocation,
      icon: const Icon(Icons.add_location_alt_outlined),
      label: const Text('Set current location'),
    ),
    body: FutureBuilder<List<PointOfInterest>>(
      future: places,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final values = snapshot.data ?? [];
        if (values.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.home_work_outlined, size: 64),
                  SizedBox(height: 16),
                  Text(
                    'No custom places yet',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Save Home, Work, or any place that is not in the public POI database.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          itemCount: values.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final place = values[index];
            return ListTile(
              leading: Icon(_iconFor(place.category)),
              title: Text(place.name),
              subtitle: Text(
                '${_tagLabel(place.category)} • Private custom POI',
              ),
              trailing: IconButton(
                tooltip: 'Delete ${place.name}',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await widget.privateData.deleteCustomPlace(place.id);
                  _refresh();
                },
              ),
            );
          },
        );
      },
    ),
  );

  IconData _iconFor(String tag) => switch (tag) {
    'home' => Icons.home_outlined,
    'work' => Icons.work_outline,
    _ => Icons.place_outlined,
  };

  String _tagLabel(String tag) => switch (tag) {
    'home' => 'Home',
    'work' => 'Work',
    _ => 'Other',
  };
}
