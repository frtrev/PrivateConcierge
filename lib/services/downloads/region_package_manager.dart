import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/region.dart';
import '../../repositories/poi_repository.dart';
import '../geography/region_resolver.dart';
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
    this._source,
  );
  final SharedPreferences _preferences;
  final PoiRepository _repository;
  final OpenStreetMapPackageSource _source;
  static const _prefix = 'public_region_version_';

  @override
  Future<bool> isCurrent(Region region) async =>
      _preferences.getInt('$_prefix${region.id}') == region.version;

  @override
  Stream<PackageProgress> install(Region region) async* {
    yield PackageProgress(
      .03,
      'Requesting real POIs for ${region.displayName}',
    );
    OpenStreetMapDownload? completed;
    await for (final update in _source.download(region)) {
      final network = update.networkFraction;
      final progress = network == null ? .08 : .08 + network.clamp(0, 1) * .57;
      yield PackageProgress(
        progress,
        'Downloading OpenStreetMap POIs • ${_formatBytes(update.bytes)}',
      );
      if (update.points != null) completed = update;
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
    yield PackageProgress(1, '${points.length} OpenStreetMap POIs ready');
  }

  @override
  Future<List<Region>> installedRegions() async => bundledRegions
      .where((region) => _preferences.containsKey('$_prefix${region.id}'))
      .map(
        (region) => region.installed(
          _preferences.getInt('$_prefix${region.id}')!,
          DateTime.parse(
            _preferences.getString('public_region_updated_${region.id}')!,
          ),
        ),
      )
      .toList();

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
    ]) {
      await _preferences.remove(key);
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
