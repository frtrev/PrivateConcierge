import 'dart:convert';
import 'dart:io';

import '../../core/models/geo.dart';
import '../../core/models/poi.dart';
import '../../core/models/region.dart';
import '../network/download_client.dart';

class OverturePackageDownload {
  const OverturePackageDownload({
    required this.bytes,
    this.fraction,
    this.points,
    this.compressedBytes,
  });
  final int bytes;
  final double? fraction;
  final List<PointOfInterest>? points;
  final List<int>? compressedBytes;
}

class OverturePackageSource {
  const OverturePackageSource(this._client);
  final DownloadClient _client;

  Stream<OverturePackageDownload> download(Region region) async* {
    final compressed = <int>[];
    await for (final chunk in _client.downloadPublicResource(
      region.downloadUrl,
    )) {
      compressed.addAll(chunk.bytes);
      final fraction = chunk.totalBytes == null || chunk.totalBytes == 0
          ? null
          : chunk.receivedBytes / chunk.totalBytes!;
      yield OverturePackageDownload(
        bytes: compressed.length,
        fraction: fraction,
      );
    }
    final text = utf8.decode(gzip.decode(compressed));
    final points = <PointOfInterest>[];
    for (final line in const LineSplitter().convert(text)) {
      if (line.trim().isEmpty) continue;
      final row = jsonDecode(line) as Map<String, dynamic>;
      points.add(
        PointOfInterest(
          id: row['id'] as String,
          regionId: region.id,
          name: row['name'] as String,
          coordinates: Coordinates(
            (row['latitude'] as num).toDouble(),
            (row['longitude'] as num).toDouble(),
          ),
          category: row['category'] as String,
          subcategory: row['subcategory'] as String,
          address: row['address'] as String,
        ),
      );
    }
    if (points.isEmpty) {
      throw const FormatException('The Overture package contained no POIs.');
    }
    yield OverturePackageDownload(
      bytes: compressed.length,
      fraction: 1,
      points: points,
      compressedBytes: compressed,
    );
  }
}
