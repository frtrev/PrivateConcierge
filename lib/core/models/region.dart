import 'geo.dart';

class Region {
  const Region({
    required this.id,
    required this.name,
    required this.administrativeArea,
    required this.country,
    required this.bounds,
    required this.version,
    required this.downloadUrl,
    required this.approximateBytes,
    this.installedVersion,
    this.lastUpdated,
  });
  final String id;
  final String name;
  final String administrativeArea;
  final String country;
  final GeoBounds bounds;
  final int version;
  final Uri downloadUrl;
  final int approximateBytes;
  final int? installedVersion;
  final DateTime? lastUpdated;

  String get displayName =>
      administrativeArea.isEmpty ? name : '$name, $administrativeArea';
  Region installed(int version, DateTime date) => Region(
    id: id,
    name: name,
    administrativeArea: administrativeArea,
    country: country,
    bounds: bounds,
    version: this.version,
    downloadUrl: downloadUrl,
    approximateBytes: approximateBytes,
    installedVersion: version,
    lastUpdated: date,
  );
}
