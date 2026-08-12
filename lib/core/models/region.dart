import 'geo.dart';

class Region {
  const Region({
    required this.id,
    required this.name,
    required this.administrativeArea,
    required this.country,
    required this.center,
    required this.bounds,
    required this.version,
    required this.downloadUrl,
    required this.approximateBytes,
    this.release = '',
    this.coverageMiles = 25,
    this.approximatePoiCount,
    this.installedVersion,
    this.lastUpdated,
  });
  final String id;
  final String name;
  final String administrativeArea;
  final String country;
  final Coordinates center;
  final GeoBounds bounds;
  final int version;
  final Uri downloadUrl;
  final int approximateBytes;
  final String release;
  final int coverageMiles;
  final int? approximatePoiCount;
  final int? installedVersion;
  final DateTime? lastUpdated;

  String get displayName =>
      administrativeArea.trim().isEmpty ? name : '$name, $administrativeArea';
  Region installed(int version, DateTime date) => Region(
    id: id,
    name: name,
    administrativeArea: administrativeArea,
    country: country,
    center: center,
    bounds: bounds,
    version: this.version,
    downloadUrl: downloadUrl,
    approximateBytes: approximateBytes,
    release: release,
    coverageMiles: coverageMiles,
    approximatePoiCount: approximatePoiCount,
    installedVersion: version,
    lastUpdated: date,
  );
}
