import 'dart:convert';
import 'dart:math' as math;

import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;

import '../../core/models/geo.dart';
import '../../core/models/region.dart';

abstract interface class RegionResolver {
  Future<Region?> resolve(Coordinates coordinates);
  Future<List<Region>> options(Coordinates coordinates);
}

abstract interface class AreaLabelResolver {
  Future<AreaLabel> label(Coordinates coordinates);
}

class AreaLabel {
  const AreaLabel(this.city, this.administrativeArea, this.country);
  final String city;
  final String administrativeArea;
  final String country;
}

class DeviceAreaLabelResolver implements AreaLabelResolver {
  DeviceAreaLabelResolver({Geocoding? geocoding})
    : _geocoding = geocoding ?? Geocoding();
  final Geocoding _geocoding;

  @override
  Future<AreaLabel> label(Coordinates coordinates) async {
    try {
      final values = await _geocoding
          .placemarkFromCoordinates(coordinates.latitude, coordinates.longitude)
          .timeout(const Duration(seconds: 8));
      final place = values.first;
      final city = _firstNonEmpty([
        place.locality,
        place.subAdministrativeArea,
        place.administrativeArea,
      ]);
      return AreaLabel(
        city ?? 'Current location',
        place.administrativeArea ?? '',
        place.isoCountryCode ?? place.country ?? '',
      );
    } catch (_) {
      return const AreaLabel('Current location', '', '');
    }
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }
}

abstract interface class OvertureReleaseResolver {
  Future<String> latest();
}

class StacOvertureReleaseResolver implements OvertureReleaseResolver {
  StacOvertureReleaseResolver({http.Client? client})
    : _client = client ?? http.Client();
  final http.Client _client;
  static const fallbackRelease = '2026-07-22.0';

  @override
  Future<String> latest() async {
    try {
      final response = await _client
          .get(Uri.parse('https://stac.overturemaps.org/catalog.json'))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return fallbackRelease;
      final value =
          (jsonDecode(response.body) as Map<String, dynamic>)['latest'];
      return value is String && value.isNotEmpty ? value : fallbackRelease;
    } catch (_) {
      return fallbackRelease;
    }
  }
}

class LocationRegionResolver implements RegionResolver {
  LocationRegionResolver({
    AreaLabelResolver? labels,
    OvertureReleaseResolver? releases,
  }) : _labels = labels ?? DeviceAreaLabelResolver(),
       _releases = releases ?? StacOvertureReleaseResolver();
  final AreaLabelResolver _labels;
  final OvertureReleaseResolver _releases;

  @override
  Future<Region?> resolve(Coordinates coordinates) async =>
      (await options(coordinates)).first;

  @override
  Future<List<Region>> options(Coordinates coordinates) async {
    final results = await Future.wait([
      _labels.label(coordinates),
      _releases.latest(),
    ]);
    final label = results[0] as AreaLabel;
    final release = results[1] as String;
    return [
      50,
      100,
      150,
    ].map((miles) => _region(coordinates, label, release, miles)).toList();
  }

  Region _region(
    Coordinates center,
    AreaLabel label,
    String release,
    int miles,
  ) {
    final latitudeDelta = miles / 69.0;
    final longitudeDelta =
        miles /
        (69.172 *
            math.max(.15, math.cos(center.latitude * math.pi / 180).abs()));
    final coordinateKey =
        '${center.latitude.toStringAsFixed(3)}_${center.longitude.toStringAsFixed(3)}'
            .replaceAll('-', 'm')
            .replaceAll('.', 'p');
    return Region(
      id: 'overture-$coordinateKey-${miles}mi',
      name: label.city,
      administrativeArea: label.administrativeArea,
      country: label.country,
      center: center,
      bounds: GeoBounds(
        south: center.latitude - latitudeDelta,
        west: center.longitude - longitudeDelta,
        north: center.latitude + latitudeDelta,
        east: center.longitude + longitudeDelta,
      ),
      version: _versionOf(release),
      release: release,
      downloadUrl: Uri.parse(
        'https://overturemaps-extras-us-west-2.s3.us-west-2.amazonaws.com/tiles/$release/places.pmtiles',
      ),
      approximateBytes: miles * miles * 11500,
      coverageMiles: miles,
    );
  }

  int _versionOf(String release) =>
      int.tryParse(release.replaceAll(RegExp('[^0-9]'), '')) ?? 1;
}

const legacyRegionIds = {
  'us-tn-memphis',
  'us-tn-memphis-50mi',
  'us-tn-memphis-100mi',
  'us-tn-memphis-150mi',
  'us-tn-nashville',
  'us-tx-dallas',
};
