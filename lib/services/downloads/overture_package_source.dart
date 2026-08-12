import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pmtiles/pmtiles.dart';
import 'package:vector_tile/vector_tile.dart';

import '../../core/models/geo.dart';
import '../../core/models/poi.dart';
import '../../core/models/region.dart';

class OverturePackageDownload {
  const OverturePackageDownload({
    required this.bytes,
    this.fraction,
    this.points,
  });
  final int bytes;
  final double? fraction;
  final List<PointOfInterest>? points;
}

class OverturePackageSource {
  const OverturePackageSource();
  static const zoom = 14;

  Stream<OverturePackageDownload> download(Region region) async* {
    final archive = await PmTilesArchive.from(region.downloadUrl.toString());
    var bytes = 0;
    final points = <PointOfInterest>[];
    final seen = <String>{};
    try {
      final tiles = tileCoordinatesFor(region.bounds, zoom);
      const batchSize = 48;
      for (var offset = 0; offset < tiles.length; offset += batchSize) {
        final end = math.min(offset + batchSize, tiles.length);
        final batch = tiles.sublist(offset, end);
        await for (final tile in archive.tiles(
          batch
              .map((value) => ZXY(zoom, value.$1, value.$2).toTileId())
              .toList(),
        )) {
          Uint8List tileBytes;
          try {
            tileBytes = Uint8List.fromList(tile.bytes());
          } catch (_) {
            continue;
          }
          bytes += tile.compressedBytes().length;
          final coordinate = ZXY.fromTileId(tile.id);
          final vector = VectorTile.fromBytes(bytes: tileBytes);
          for (final layer in vector.layers.where(
            (value) => value.name == 'place',
          )) {
            for (final feature in layer.features) {
              final properties = feature.decodeProperties();
              final id = _string(properties, 'id');
              final name =
                  _string(properties, '@name') ??
                  _jsonField(properties, 'names', 'primary');
              if (id == null || name == null || !seen.add(id)) continue;
              if (_string(properties, 'operating_status') ==
                  'permanently_closed') {
                continue;
              }
              final geo = feature.toGeoJson(
                x: coordinate.x,
                y: coordinate.y,
                z: coordinate.z,
              );
              final geometry = geo?.geometry;
              if (geometry is! GeometryPoint) continue;
              final location = Coordinates(
                geometry.coordinates[1],
                geometry.coordinates[0],
              );
              if (distanceMeters(region.center, location) >
                  region.coverageMiles * 1609.344) {
                continue;
              }
              final primary =
                  _jsonField(properties, 'taxonomy', 'primary') ??
                  _jsonField(properties, 'categories', 'primary') ??
                  _string(properties, 'basic_category') ??
                  'place';
              points.add(
                PointOfInterest(
                  id: '${region.id}-$id',
                  regionId: region.id,
                  name: name,
                  coordinates: location,
                  category: _appCategory(primary),
                  subcategory: primary,
                  address: _address(properties),
                ),
              );
            }
          }
        }
        yield OverturePackageDownload(
          bytes: bytes,
          fraction: end / tiles.length,
        );
      }
    } finally {
      await archive.close();
    }
    if (points.isEmpty) {
      throw const FormatException('Overture returned no places for this area.');
    }
    yield OverturePackageDownload(bytes: bytes, fraction: 1, points: points);
  }

  static List<(int, int)> tileCoordinatesFor(GeoBounds bounds, int zoom) {
    final west = _tileX(bounds.west, zoom);
    final east = _tileX(bounds.east, zoom);
    final north = _tileY(bounds.north, zoom);
    final south = _tileY(bounds.south, zoom);
    return [
      for (var x = west; x <= east; x++)
        for (var y = north; y <= south; y++) (x, y),
    ];
  }

  static int _tileX(double longitude, int zoom) =>
      (((longitude + 180) / 360) * (1 << zoom)).floor();
  static int _tileY(double latitude, int zoom) {
    final radians = latitude.clamp(-85.0511, 85.0511) * math.pi / 180;
    return ((1 -
                math.log(math.tan(radians) + 1 / math.cos(radians)) / math.pi) /
            2 *
            (1 << zoom))
        .floor();
  }

  String? _string(Map<String, VectorTileValue> values, String key) =>
      values[key]?.stringValue;
  String? _jsonField(
    Map<String, VectorTileValue> values,
    String key,
    String field,
  ) {
    final raw = _string(values, key);
    if (raw == null) return null;
    try {
      final value = (jsonDecode(raw) as Map<String, dynamic>)[field];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    } catch (_) {
      return null;
    }
  }

  String _address(Map<String, VectorTileValue> values) {
    final raw = _string(values, 'addresses');
    if (raw == null) return '';
    try {
      final values = jsonDecode(raw) as List<dynamic>;
      if (values.isEmpty) return '';
      final address = values.first as Map<String, dynamic>;
      return [
        address['freeform'],
        address['locality'],
        address['region'],
      ].whereType<String>().where((value) => value.isNotEmpty).join(', ');
    } catch (_) {
      return '';
    }
  }

  String _appCategory(String value) {
    final category = value.toLowerCase();
    if (category.contains('restaurant') ||
        {'cafe', 'coffee_shop', 'bakery', 'bar'}.contains(category)) {
      return 'restaurant';
    }
    if (category.contains('church') || category.contains('worship')) {
      return 'church';
    }
    if (category.contains('cinema') ||
        category.contains('theater') ||
        category.contains('theatre')) {
      return 'entertainment';
    }
    if (category.contains('grocery') || category.contains('supermarket')) {
      return 'grocery';
    }
    if (category.contains('pharmacy') || category.contains('drugstore')) {
      return 'pharmacy';
    }
    if (category.contains('hardware') ||
        category.contains('home_improvement')) {
      return 'hardware';
    }
    if (category.contains('department_store') ||
        category.contains('shopping_center') ||
        category.contains('retail')) {
      return 'shopping';
    }
    if (category.contains('park')) return 'park';
    if (category.contains('museum')) return 'museum';
    if (category.contains('gas_station')) return 'gas';
    return 'other';
  }
}
