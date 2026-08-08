import 'dart:convert';

import '../../core/models/geo.dart';
import '../../core/models/poi.dart';
import '../../core/models/region.dart';
import '../network/download_client.dart';

class OpenStreetMapPackageSource {
  const OpenStreetMapPackageSource(this._downloadClient);
  final DownloadClient _downloadClient;

  Stream<OpenStreetMapDownload> download(Region region) async* {
    final received = <int>[];
    await for (final chunk in _downloadClient.downloadPublicResource(
      PublicDownloadRequest(
        uri: region.downloadUrl,
        formFields: {'data': buildQuery(region)},
      ),
    )) {
      received.addAll(chunk.bytes);
      final networkFraction = chunk.totalBytes == null || chunk.totalBytes == 0
          ? null
          : chunk.receivedBytes / chunk.totalBytes!;
      yield OpenStreetMapDownload(
        bytes: received.length,
        networkFraction: networkFraction,
      );
    }
    if (received.isEmpty) {
      throw const FormatException('The OpenStreetMap response was empty.');
    }
    final decoded = jsonDecode(utf8.decode(received));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid OpenStreetMap package.');
    }
    final points = parseElements(region, decoded['elements']);
    if (points.isEmpty) {
      throw const FormatException(
        'OpenStreetMap returned no named POIs for this region.',
      );
    }
    yield OpenStreetMapDownload(
      bytes: received.length,
      networkFraction: 1,
      points: points,
      rawBytes: received,
    );
  }

  String buildQuery(Region region) {
    final b = region.bounds;
    final bbox = '${b.south},${b.west},${b.north},${b.east}';
    return '''[out:json][timeout:60][bbox:$bbox];
(
  nwr["name"]["amenity"~"^(restaurant|cafe|fast_food|food_court|place_of_worship|fuel|charging_station|pharmacy|hospital|clinic|doctors|dentist|bank|atm|library|theatre|cinema|community_centre|marketplace)\$"];
  nwr["name"]["tourism"~"^(museum|attraction|gallery|viewpoint|zoo|theme_park|information|hotel|motel)\$"];
  nwr["name"]["leisure"~"^(park|fitness_centre|sports_centre|garden|playground|nature_reserve|stadium)\$"];
  nwr["name"]["historic"];
  nwr["name"]["shop"~"^(supermarket|convenience|bakery|mall|department_store)\$"];
);
out center tags;''';
  }

  List<PointOfInterest> parseElements(Region region, Object? value) {
    if (value is! List) return const [];
    final result = <PointOfInterest>[];
    final seen = <String>{};
    for (final item in value) {
      if (item is! Map<String, dynamic>) continue;
      final tagsValue = item['tags'];
      if (tagsValue is! Map) continue;
      final tags = tagsValue.map((key, value) => MapEntry('$key', '$value'));
      final name = tags['name']?.trim();
      final type = item['type'];
      final id = item['id'];
      final center = item['center'];
      final lat =
          _number(item['lat']) ??
          (center is Map ? _number(center['lat']) : null);
      final lon =
          _number(item['lon']) ??
          (center is Map ? _number(center['lon']) : null);
      if (name == null ||
          name.isEmpty ||
          type == null ||
          id == null ||
          lat == null ||
          lon == null) {
        continue;
      }
      final stableId = 'osm-$type-$id';
      if (!seen.add(stableId)) continue;
      final classification = _classify(tags);
      result.add(
        PointOfInterest(
          id: stableId,
          regionId: region.id,
          name: name,
          coordinates: Coordinates(lat, lon),
          category: classification.$1,
          subcategory: classification.$2,
          address: _address(tags, region),
          description: _description(tags),
        ),
      );
    }
    return result;
  }

  double? _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value');

  (String, String) _classify(Map<String, String> tags) {
    final amenity = tags['amenity'];
    if (const {
      'restaurant',
      'cafe',
      'fast_food',
      'food_court',
    }.contains(amenity)) {
      return ('restaurant', amenity!);
    }
    if (amenity == 'place_of_worship') {
      final religion = tags['religion'];
      return religion == 'christian'
          ? ('church', tags['denomination'] ?? 'christian')
          : ('place_of_worship', religion ?? amenity!);
    }
    if (const {'fuel', 'charging_station'}.contains(amenity)) {
      return ('gas', amenity!);
    }
    if (const {'fitness_centre', 'sports_centre'}.contains(tags['leisure'])) {
      return ('gym', tags['leisure']!);
    }
    if (const {
      'park',
      'garden',
      'nature_reserve',
      'playground',
    }.contains(tags['leisure'])) {
      return ('park', tags['leisure']!);
    }
    if (tags.containsKey('historic')) return ('historic', tags['historic']!);
    if (tags['tourism'] == 'museum') return ('museum', 'museum');
    if (tags.containsKey('tourism')) return ('attraction', tags['tourism']!);
    if (const {'supermarket', 'convenience', 'bakery'}.contains(tags['shop'])) {
      return ('grocery', tags['shop']!);
    }
    return ('service', amenity ?? tags['shop'] ?? tags['leisure'] ?? 'place');
  }

  String _address(Map<String, String> tags, Region region) {
    final street = [
      tags['addr:housenumber'],
      tags['addr:street'],
    ].whereType<String>().join(' ');
    final city = tags['addr:city'];
    final state = tags['addr:state'];
    final parts = [
      street,
      city,
      state,
    ].whereType<String>().where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? region.displayName : parts.join(', ');
  }

  String? _description(Map<String, String> tags) =>
      tags['description'] ?? tags['cuisine'] ?? tags['operator'];
}

class OpenStreetMapDownload {
  const OpenStreetMapDownload({
    required this.bytes,
    this.networkFraction,
    this.points,
    this.rawBytes,
  });
  final int bytes;
  final double? networkFraction;
  final List<PointOfInterest>? points;
  final List<int>? rawBytes;
}
