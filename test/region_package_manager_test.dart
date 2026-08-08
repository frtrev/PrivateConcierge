import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:private_concierge/services/downloads/open_street_map_package.dart';
import 'package:private_concierge/services/downloads/region_package_manager.dart';
import 'package:private_concierge/services/geography/region_resolver.dart';
import 'package:private_concierge/services/network/download_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'nearby_service_test.dart';

class _DownloadClient implements DownloadClient {
  @override
  Stream<DownloadChunk> downloadPublicResource(
    PublicDownloadRequest request,
  ) async* {
    expect(request.formFields['data'], contains('out center tags'));
    final bytes = utf8.encode(
      jsonEncode({
        'elements': [
          {
            'type': 'node',
            'id': 42,
            'lat': 35.1,
            'lon': -90.0,
            'tags': {
              'name': 'Real Cafe',
              'amenity': 'cafe',
              'addr:housenumber': '12',
              'addr:street': 'Beale St',
            },
          },
          {
            'type': 'way',
            'id': 84,
            'center': {'lat': 35.2, 'lon': -90.1},
            'tags': {'name': 'Real Museum', 'tourism': 'museum'},
          },
        ],
      }),
    );
    yield DownloadChunk(
      bytes: bytes,
      receivedBytes: bytes.length,
      totalBytes: bytes.length,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'downloads, parses, fingerprints, and records a real OSM package',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repository = MemoryPoiRepository();
      final preferences = await SharedPreferences.getInstance();
      final manager = OpenStreetMapRegionPackageManager(
        preferences,
        repository,
        OpenStreetMapPackageSource(_DownloadClient()),
      );
      final updates = await manager.install(bundledRegions.first).toList();
      expect(updates.last.fraction, 1);
      expect(updates.last.message, contains('2 OpenStreetMap POIs'));
      expect(await manager.isCurrent(bundledRegions.first), isTrue);
      expect(
        repository.points.map((point) => point.name),
        containsAll(['Real Cafe', 'Real Museum']),
      );
      expect(repository.points.first.category, 'restaurant');
      expect(
        preferences.getString('public_region_sha256_us-tn-memphis'),
        hasLength(64),
      );
      expect(
        (await manager.installedRegions()).single.id,
        bundledRegions.first.id,
      );
    },
  );

  test('parser uses centers for OSM ways and normalizes categories', () async {
    final updates = await OpenStreetMapPackageSource(
      _DownloadClient(),
    ).download(bundledRegions.first).toList();
    final points = updates.last.points!;
    expect(points.last.id, 'osm-way-84');
    expect(points.last.category, 'museum');
    expect(points.last.address, bundledRegions.first.displayName);
  });
}
