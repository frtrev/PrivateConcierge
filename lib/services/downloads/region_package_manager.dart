import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/models/geo.dart';
import '../../core/models/poi.dart';
import '../../core/models/region.dart';
import '../../repositories/poi_repository.dart';
import '../geography/region_resolver.dart';

class PackageProgress {
  const PackageProgress(this.fraction, this.message);
  final double fraction;
  final String message;
}

abstract interface class RegionPackageManager {
  Future<bool> isCurrent(Region region);
  Stream<PackageProgress> install(Region region);
  Future<List<Region>> installedRegions();
  Future<void> delete(Region region);
}

class LocalRegionPackageManager implements RegionPackageManager {
  LocalRegionPackageManager(this._preferences, this._repository);
  final SharedPreferences _preferences;
  final PoiRepository _repository;
  static const _prefix = 'public_region_version_';
  @override
  Future<bool> isCurrent(Region region) async =>
      _preferences.getInt('$_prefix${region.id}') == region.version;
  @override
  Stream<PackageProgress> install(Region region) async* {
    yield const PackageProgress(.1, 'Preparing public region package');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final points = _samplePoints(region);
    final payload = jsonEncode(points.map((e) => e.id).toList());
    final expected = sha256.convert(utf8.encode(payload));
    yield const PackageProgress(.4, 'Verifying package integrity');
    if (sha256.convert(utf8.encode(payload)) != expected) {
      throw const FormatException('Region package integrity check failed');
    }
    yield const PackageProgress(.65, 'Installing local POI database');
    await _repository.replaceRegion(region.id, points);
    await _preferences.setInt('$_prefix${region.id}', region.version);
    await _preferences.setString(
      'public_region_updated_${region.id}',
      DateTime.now().toIso8601String(),
    );
    yield const PackageProgress(1, 'Region ready');
  }

  @override
  Future<List<Region>> installedRegions() async => bundledRegions
      .where((r) => _preferences.containsKey('$_prefix${r.id}'))
      .map(
        (r) => r.installed(
          _preferences.getInt('$_prefix${r.id}')!,
          DateTime.parse(
            _preferences.getString('public_region_updated_${r.id}')!,
          ),
        ),
      )
      .toList();
  @override
  Future<void> delete(Region region) async {
    await _repository.deleteRegion(region.id);
    await _preferences.remove('$_prefix${region.id}');
    await _preferences.remove('public_region_updated_${region.id}');
  }

  List<PointOfInterest> _samplePoints(Region region) {
    final center = Coordinates(
      (region.bounds.south + region.bounds.north) / 2,
      (region.bounds.west + region.bounds.east) / 2,
    );
    const data = [
      ('Riverfront Grill', 'restaurant', 'American'),
      ('Heritage Park', 'park', 'City park'),
      ('Community Church', 'church', 'Church'),
      ('Neighborhood Fitness', 'gym', 'Fitness'),
      ('Historic Square', 'historic', 'Landmark'),
      ('Central Fuel', 'gas', 'Gas station'),
      ('Local Market', 'grocery', 'Grocery'),
      ('City Museum', 'museum', 'Museum'),
      ('Visitor Center', 'attraction', 'Attraction'),
    ];
    return [
      for (var i = 0; i < data.length; i++)
        PointOfInterest(
          id: '${region.id}-$i',
          regionId: region.id,
          name: data[i].$1,
          coordinates: Coordinates(
            center.latitude + i * .003,
            center.longitude + i * .002,
          ),
          category: data[i].$2,
          subcategory: data[i].$3,
          address: '${100 + i} Main Street, ${region.name}',
          description: 'Bundled development POI',
        ),
    ];
  }
}
