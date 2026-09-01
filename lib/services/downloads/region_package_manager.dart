import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/geo.dart';
import '../../core/models/region.dart';
import '../../repositories/poi_repository.dart';
import '../geography/region_resolver.dart';
import 'overture_package_source.dart';

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
  Future<void> removeLegacyRegions();
}

class OvertureRegionPackageManager implements RegionPackageManager {
  OvertureRegionPackageManager(
    this._preferences,
    this._repository,
    this._source,
  );
  final SharedPreferences _preferences;
  final PoiRepository _repository;
  final OverturePackageSource _source;
  static const _prefix = 'public_region_version_';
  static const _catalogKey = 'installed_overture_regions_v2';

  @override
  Future<bool> isCurrent(Region region) async =>
      _preferences.getInt('$_prefix${region.id}') == region.version;

  @override
  Stream<PackageProgress> install(Region region) async* {
    OverturePackageDownload? completed;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        yield PackageProgress(
          .02,
          'Connecting to Overture • attempt $attempt of 3',
        );
        await for (final update in _source.download(region)) {
          final fraction = update.fraction ?? 0;
          yield PackageProgress(
            .04 + fraction * .74,
            'Downloading ${region.coverageMiles}-mile area • ${_formatBytes(update.bytes)}',
          );
          if (update.points != null) completed = update;
        }
        break;
      } catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint('Overture area attempt $attempt failed: $error');
          debugPrintStack(stackTrace: stackTrace);
        }
        if (attempt == 3) {
          throw const OverturePackageException(
            'The offline area could not be completed after three attempts. Your existing private data was not changed. Check your connection and try again.',
          );
        }
        yield PackageProgress(.08, 'Connection interrupted • retrying safely');
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
    }
    final points = completed?.points;
    if (points == null || points.isEmpty) {
      throw const OverturePackageException(
        'The downloaded area contained no usable places.',
      );
    }
    yield PackageProgress(
      .82,
      'Installing ${points.length} places on this device',
    );
    await _repository.replaceRegion(region.id, points);
    final siblings = (await installedRegions()).where(
      (candidate) =>
          candidate.id != region.id &&
          distanceMeters(candidate.center, region.center) < 1000,
    );
    for (final sibling in siblings) {
      await delete(sibling);
    }
    final now = DateTime.now();
    await _preferences.setInt('$_prefix${region.id}', region.version);
    await _preferences.setString(
      'public_region_updated_${region.id}',
      now.toIso8601String(),
    );
    await _preferences.setInt(
      'public_region_poi_count_${region.id}',
      points.length,
    );
    await _saveCatalogRegion(region, now);
    yield PackageProgress(1, '${points.length} Overture places ready offline');
  }

  @override
  Future<List<Region>> installedRegions() async {
    final raw = _preferences.getString(_catalogKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((value) => _fromJson(value as Map<String, dynamic>))
          .where((region) => _preferences.containsKey('$_prefix${region.id}'))
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> delete(Region region) async {
    await _repository.deleteRegion(region.id);
    for (final key in [
      '$_prefix${region.id}',
      'public_region_updated_${region.id}',
      'public_region_poi_count_${region.id}',
    ]) {
      await _preferences.remove(key);
    }
    final remaining = (await installedRegions()).where(
      (value) => value.id != region.id,
    );
    await _preferences.setString(
      _catalogKey,
      jsonEncode(remaining.map(_toJson).toList()),
    );
  }

  @override
  Future<void> removeLegacyRegions() async {
    for (final id in legacyRegionIds) {
      await _repository.deleteRegion(id);
      await _preferences.remove('$_prefix$id');
    }
  }

  Future<void> _saveCatalogRegion(Region region, DateTime installedAt) async {
    final values = (await installedRegions())
        .where((value) => value.id != region.id)
        .toList();
    values.add(region.installed(region.version, installedAt));
    await _preferences.setString(
      _catalogKey,
      jsonEncode(values.map(_toJson).toList()),
    );
  }

  Map<String, dynamic> _toJson(Region value) => {
    'id': value.id,
    'name': value.name,
    'area': value.administrativeArea,
    'country': value.country,
    'lat': value.center.latitude,
    'lon': value.center.longitude,
    'south': value.bounds.south,
    'west': value.bounds.west,
    'north': value.bounds.north,
    'east': value.bounds.east,
    'version': value.version,
    'release': value.release,
    'url': value.downloadUrl.toString(),
    'bytes': value.approximateBytes,
    'miles': value.coverageMiles,
    'installed': value.lastUpdated?.toIso8601String(),
  };

  Region _fromJson(Map<String, dynamic> value) => Region(
    id: value['id'] as String,
    name: value['name'] as String,
    administrativeArea: value['area'] as String? ?? '',
    country: value['country'] as String? ?? '',
    center: Coordinates(
      (value['lat'] as num).toDouble(),
      (value['lon'] as num).toDouble(),
    ),
    bounds: GeoBounds(
      south: (value['south'] as num).toDouble(),
      west: (value['west'] as num).toDouble(),
      north: (value['north'] as num).toDouble(),
      east: (value['east'] as num).toDouble(),
    ),
    version: value['version'] as int,
    release: value['release'] as String? ?? '',
    downloadUrl: Uri.parse(value['url'] as String),
    approximateBytes: value['bytes'] as int,
    coverageMiles: value['miles'] as int,
    installedVersion: value['version'] as int,
    lastUpdated: value['installed'] == null
        ? null
        : DateTime.parse(value['installed'] as String),
  );

  String _formatBytes(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(0)} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class OverturePackageException implements Exception {
  const OverturePackageException(this.message);
  final String message;
  @override
  String toString() => message;
}
