import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/geo.dart';
import '../../core/models/region.dart';
import '../../repositories/poi_repository.dart';
import '../geography/region_resolver.dart';
import '../network/download_client.dart';
import 'open_street_map_package.dart';

class PackageProgress {
  const PackageProgress(this.fraction, this.message);
  final double fraction;
  final String message;
}

abstract interface class RegionPackageManager {
  Future<bool> isCurrent(Region region);
  Stream<PackageProgress> install(Region region);
  Future<List<Region>> installedRegions();
  Future<int?> installedPoiCount(Region region);
  Future<void> delete(Region region);
}

class OpenStreetMapRegionPackageManager implements RegionPackageManager {
  OpenStreetMapRegionPackageManager(
    this._preferences,
    this._repository,
    this._source, {
    this.retryDelays = const [Duration(seconds: 2), Duration(seconds: 5)],
  });
  final SharedPreferences _preferences;
  final PoiRepository _repository;
  final OpenStreetMapPackageSource _source;
  final List<Duration> retryDelays;
  static const _prefix = 'public_region_version_';

  @override
  Future<bool> isCurrent(Region region) async =>
      _preferences.getInt('$_prefix${region.id}') == region.version;

  @override
  Stream<PackageProgress> install(Region region) async* {
    OpenStreetMapDownload? completed;
    final maxAttempts = retryDelays.length + 1;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final attemptBase = (attempt - 1) * .62 / maxAttempts;
      final attemptSpan = .62 / maxAttempts;
      yield PackageProgress(
        attemptBase + .01,
        'Connecting to OpenStreetMap • attempt $attempt of $maxAttempts',
      );
      try {
        await for (final update in _source.download(region)) {
          final network = update.networkFraction;
          final withinAttempt = network == null ? .12 : network.clamp(0, 1);
          yield PackageProgress(
            attemptBase + withinAttempt * attemptSpan,
            'Downloading POIs • attempt $attempt of $maxAttempts • ${_formatBytes(update.bytes)}',
          );
          if (update.points != null) completed = update;
        }
        break;
      } on PublicDownloadException catch (error) {
        if (!error.retryable || attempt == maxAttempts) {
          throw RegionDownloadException(_friendlyFailure(error));
        }
        final delay = retryDelays[attempt - 1];
        final seconds = delay.inSeconds;
        if (seconds == 0) {
          yield PackageProgress(
            attemptBase + attemptSpan,
            'OpenStreetMap is temporarily busy • retrying now',
          );
        } else {
          for (var remaining = seconds; remaining > 0; remaining--) {
            yield PackageProgress(
              attemptBase + attemptSpan,
              'OpenStreetMap is temporarily busy • retrying in $remaining seconds',
            );
            await Future<void>.delayed(const Duration(seconds: 1));
          }
        }
      }
    }
    if (completed?.points == null ||
        completed!.points!.isEmpty ||
        completed.rawBytes == null) {
      throw const FormatException(
        'The downloaded region package was incomplete.',
      );
    }
    yield const PackageProgress(.70, 'Verifying downloaded package integrity');
    final digest = sha256.convert(completed.rawBytes!).toString();
    final points = completed.points!;
    yield PackageProgress(.78, 'Installing ${points.length} real POIs locally');
    // replaceRegion is transactional: the prior installed package survives a failed replacement.
    await _repository.replaceRegion(region.id, points);
    final now = DateTime.now();
    await _preferences.setInt('$_prefix${region.id}', region.version);
    await _preferences.setString(
      'public_region_updated_${region.id}',
      now.toIso8601String(),
    );
    await _preferences.setString('public_region_sha256_${region.id}', digest);
    await _preferences.setInt(
      'public_region_poi_count_${region.id}',
      points.length,
    );
    await _preferences.setString(
      'public_region_source_${region.id}',
      'OpenStreetMap',
    );
    await _preferences.setString(
      'public_region_metadata_${region.id}',
      jsonEncode({
        'id': region.id,
        'name': region.name,
        'administrativeArea': region.administrativeArea,
        'country': region.country,
        'south': region.bounds.south,
        'west': region.bounds.west,
        'north': region.bounds.north,
        'east': region.bounds.east,
        'version': region.version,
        'downloadUrl': region.downloadUrl.toString(),
        'approximateBytes': region.approximateBytes,
      }),
    );
    yield PackageProgress(1, '${points.length} OpenStreetMap POIs ready');
  }

  @override
  Future<List<Region>> installedRegions() async {
    final installed = <Region>[];
    for (final key in _preferences.getKeys().where(
      (key) => key.startsWith(_prefix),
    )) {
      final id = key.substring(_prefix.length);
      Region? region;
      for (final candidate in bundledRegions) {
        if (candidate.id == id) region = candidate;
      }
      region ??= _readRegion(id);
      final updated = _preferences.getString('public_region_updated_$id');
      final version = _preferences.getInt('$_prefix$id');
      if (region != null && updated != null && version != null) {
        installed.add(region.installed(version, DateTime.parse(updated)));
      }
    }
    return installed;
  }

  @override
  Future<int?> installedPoiCount(Region region) async =>
      _preferences.getInt('public_region_poi_count_${region.id}');

  @override
  Future<void> delete(Region region) async {
    await _repository.deleteRegion(region.id);
    for (final key in [
      '$_prefix${region.id}',
      'public_region_updated_${region.id}',
      'public_region_sha256_${region.id}',
      'public_region_poi_count_${region.id}',
      'public_region_source_${region.id}',
      'public_region_metadata_${region.id}',
    ]) {
      await _preferences.remove(key);
    }
  }

  Region? _readRegion(String id) {
    final raw = _preferences.getString('public_region_metadata_$id');
    if (raw == null) return null;
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic>) return null;
    return Region(
      id: value['id'] as String,
      name: value['name'] as String,
      administrativeArea: value['administrativeArea'] as String,
      country: value['country'] as String,
      bounds: GeoBounds(
        south: (value['south'] as num).toDouble(),
        west: (value['west'] as num).toDouble(),
        north: (value['north'] as num).toDouble(),
        east: (value['east'] as num).toDouble(),
      ),
      version: value['version'] as int,
      downloadUrl: Uri.parse(value['downloadUrl'] as String),
      approximateBytes: value['approximateBytes'] as int,
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _friendlyFailure(PublicDownloadException error) {
    if (error.kind == PublicDownloadFailure.connection) {
      return 'We could not connect to the geographic data service. Check your internet connection and try again.';
    }
    return 'The geographic data service is taking longer than usual. Your existing downloaded places are safe. Please try again in a few minutes.';
  }
}

class RegionDownloadException implements Exception {
  const RegionDownloadException(this.userMessage);
  final String userMessage;
  @override
  String toString() => userMessage;
}
