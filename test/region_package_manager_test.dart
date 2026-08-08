import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:private_concierge/core/models/geo.dart';
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

class _FlakyDownloadClient implements DownloadClient {
  _FlakyDownloadClient(this.failuresBeforeSuccess);
  final int failuresBeforeSuccess;
  int attempts = 0;

  @override
  Stream<DownloadChunk> downloadPublicResource(
    PublicDownloadRequest request,
  ) async* {
    attempts++;
    if (attempts <= failuresBeforeSuccess) {
      throw const PublicDownloadException(
        kind: PublicDownloadFailure.server,
        retryable: true,
        statusCode: 504,
      );
    }
    yield* _DownloadClient().downloadPublicResource(request);
  }
}

class _CountingDownloadClient implements DownloadClient {
  int requests = 0;
  @override
  Stream<DownloadChunk> downloadPublicResource(
    PublicDownloadRequest request,
  ) async* {
    requests++;
    yield* _DownloadClient().downloadPublicResource(request);
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
    expect(points.last.id, '${bundledRegions.first.id}-osm-way-84');
    expect(points.last.category, 'museum');
    expect(points.last.address, bundledRegions.first.displayName);
  });

  test('same OSM feature is namespaced across overlapping regions', () {
    final source = OpenStreetMapPackageSource(_DownloadClient());
    final element = [
      {
        'type': 'node',
        'id': 42,
        'lat': 35.1,
        'lon': -90.0,
        'tags': {'name': 'Shared Cafe', 'amenity': 'cafe'},
      },
    ];
    final first = source.parseElements(bundledRegions[0], element).single;
    final second = source.parseElements(bundledRegions[1], element).single;
    expect(first.id, isNot(second.id));
    expect(first.id, startsWith('${bundledRegions[0].id}-'));
    expect(second.id, startsWith('${bundledRegions[1].id}-'));
  });

  test('large current area uses four tiles and deduplicates POIs', () async {
    final client = _CountingDownloadClient();
    final region = const CurrentAreaRegionFactory().create(
      const Coordinates(41.8781, -87.6298),
    );
    final updates = await OpenStreetMapPackageSource(
      client,
    ).download(region).toList();
    expect(client.requests, 4);
    expect(updates.last.points, hasLength(2));
    expect(updates.last.networkFraction, 1);
  });

  test('retries transient timeouts and reports each attempt', () async {
    SharedPreferences.setMockInitialValues({});
    final client = _FlakyDownloadClient(2);
    final manager = OpenStreetMapRegionPackageManager(
      await SharedPreferences.getInstance(),
      MemoryPoiRepository(),
      OpenStreetMapPackageSource(client),
      retryDelays: const [Duration.zero, Duration.zero],
    );
    final updates = await manager.install(bundledRegions.first).toList();
    expect(client.attempts, 3);
    expect(
      updates.any((update) => update.message.contains('attempt 2 of 3')),
      isTrue,
    );
    expect(updates.last.fraction, 1);
  });

  test('exhausted retries return only a user-facing failure', () async {
    SharedPreferences.setMockInitialValues({});
    final client = _FlakyDownloadClient(99);
    final manager = OpenStreetMapRegionPackageManager(
      await SharedPreferences.getInstance(),
      MemoryPoiRepository(),
      OpenStreetMapPackageSource(client),
      retryDelays: const [Duration.zero, Duration.zero],
    );
    await expectLater(
      manager.install(bundledRegions.first).drain<void>(),
      throwsA(
        isA<RegionDownloadException>()
            .having(
              (error) => error.userMessage,
              'message',
              contains('try again'),
            )
            .having(
              (error) => error.userMessage,
              'raw response',
              isNot(contains('504')),
            ),
      ),
    );
    expect(client.attempts, 3);
  });
}
