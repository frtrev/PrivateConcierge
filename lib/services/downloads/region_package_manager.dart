import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static const expectedHashes = {
    'us-tn-memphis':
        '7141b38fffa0a537dca276ff07912d47552a2c9cfb8e8b33ec79d1b707196927',
    'us-tn-nashville':
        '4593556bf28a360b782ff062ad356f563f1f3770d8dc224f4c1e48639ed53002',
    'us-tx-dallas':
        'e52b4c980bea425012ce2d670c8859e4f14cb4a54cb87a3a0cae3b01efdda5da',
  };

  @override
  Future<bool> isCurrent(Region region) async =>
      _preferences.getInt('$_prefix${region.id}') == region.version;

  @override
  Stream<PackageProgress> install(Region region) async* {
    OverturePackageDownload? completed;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        yield PackageProgress(
          .03,
          'Downloading Overture Maps package • attempt $attempt of 3',
        );
        await for (final update in _source.download(region)) {
          yield PackageProgress(
            .05 + (update.fraction ?? .1) * .62,
            'Downloading Overture Places • ${_formatBytes(update.bytes)}',
          );
          if (update.points != null) completed = update;
        }
        break;
      } catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint('Overture package attempt $attempt failed: $error');
          debugPrintStack(stackTrace: stackTrace);
        }
        if (attempt == 3) {
          throw const OverturePackageException(
            'The offline places package is temporarily unavailable. Please check your connection and try again later.',
          );
        }
        yield PackageProgress(
          .05 + attempt * .1,
          'Download interrupted • retrying shortly',
        );
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
    }
    if (completed?.points == null || completed?.compressedBytes == null) {
      throw const OverturePackageException(
        'The offline places package could not be verified.',
      );
    }
    yield const PackageProgress(.72, 'Verifying Overture Maps package');
    final actualHash = sha256.convert(completed!.compressedBytes!).toString();
    if (actualHash != expectedHashes[region.id]) {
      throw const OverturePackageException(
        'The offline places package could not be verified.',
      );
    }
    yield PackageProgress(
      .82,
      'Installing ${completed.points!.length} real places locally',
    );
    await _repository.replaceRegion(region.id, completed.points!);
    final now = DateTime.now();
    await _preferences.setInt('$_prefix${region.id}', region.version);
    await _preferences.setString(
      'public_region_updated_${region.id}',
      now.toIso8601String(),
    );
    await _preferences.setInt(
      'public_region_poi_count_${region.id}',
      completed.points!.length,
    );
    await _preferences.setString(
      'public_region_source_${region.id}',
      'Overture Maps',
    );
    yield PackageProgress(
      1,
      '${completed.points!.length} Overture places ready',
    );
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
  Future<void> delete(Region region) async {
    await _repository.deleteRegion(region.id);
    for (final key in [
      '$_prefix${region.id}',
      'public_region_updated_${region.id}',
      'public_region_poi_count_${region.id}',
      'public_region_source_${region.id}',
    ]) {
      await _preferences.remove(key);
    }
  }

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
