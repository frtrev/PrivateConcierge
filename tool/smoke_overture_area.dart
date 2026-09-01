import 'package:private_concierge/core/models/geo.dart';
import 'package:private_concierge/core/models/region.dart';
import 'package:private_concierge/services/downloads/overture_package_source.dart';

Future<void> main(List<String> arguments) async {
  final latitude = double.parse(arguments.elementAtOrNull(0) ?? '35.1495');
  final longitude = double.parse(arguments.elementAtOrNull(1) ?? '-90.049');
  final miles = int.parse(arguments.elementAtOrNull(2) ?? '1');
  final center = Coordinates(latitude, longitude);
  final latitudeDelta = miles / 69;
  final longitudeDelta = miles / 56;
  final region = Region(
    id: 'smoke',
    name: 'Smoke test',
    administrativeArea: '',
    country: 'US',
    center: center,
    bounds: GeoBounds(
      south: latitude - latitudeDelta,
      west: longitude - longitudeDelta,
      north: latitude + latitudeDelta,
      east: longitude + longitudeDelta,
    ),
    version: 202607220,
    release: '2026-07-22.0',
    downloadUrl: Uri.parse(
      'https://overturemaps-extras-us-west-2.s3.us-west-2.amazonaws.com/tiles/2026-07-22.0/places.pmtiles',
    ),
    approximateBytes: 0,
    coverageMiles: miles,
  );
  var lastBucket = -1;
  await for (final update in const OverturePackageSource().download(region)) {
    final bucket = ((update.fraction ?? 0) * 10).floor();
    if (bucket != lastBucket) {
      lastBucket = bucket;
      // This command is a developer smoke test; stdout is its intended output.
      // ignore: avoid_print
      print(
        '${(update.fraction! * 100).toStringAsFixed(0)}% • ${update.bytes} bytes',
      );
    }
    if (update.points != null) {
      // This command is a developer smoke test; stdout is its intended output.
      // ignore: avoid_print
      print('${update.points!.length} POIs, ${update.bytes} compressed bytes');
    }
  }
}
