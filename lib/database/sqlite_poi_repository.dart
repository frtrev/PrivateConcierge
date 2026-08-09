import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../core/models/geo.dart';
import '../core/models/poi.dart';
import '../repositories/poi_repository.dart';

class SqlitePoiRepository implements PoiRepository {
  Database? _database;
  @override
  Future<void> open() async {
    final root = await getApplicationSupportDirectory();
    _database = await openDatabase(
      p.join(root.path, 'public_geography.db'),
      version: 1,
      onCreate: (db, _) => db.execute(
        'CREATE TABLE poi (id TEXT PRIMARY KEY, region_id TEXT NOT NULL, name TEXT NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL, category TEXT NOT NULL, subcategory TEXT NOT NULL, address TEXT NOT NULL, description TEXT)',
      ),
    );
  }

  Database get _db =>
      _database ?? (throw StateError('POI database is not open'));
  @override
  Future<void> replaceRegion(String regionId, List<PointOfInterest> points) =>
      _db.transaction((txn) async {
        await txn.delete('poi', where: 'region_id = ?', whereArgs: [regionId]);
        for (final point in points) {
          await txn.insert('poi', {
            'id': point.id,
            'region_id': regionId,
            'name': point.name,
            'latitude': point.coordinates.latitude,
            'longitude': point.coordinates.longitude,
            'category': point.category,
            'subcategory': point.subcategory,
            'address': point.address,
            'description': point.description,
          });
        }
      });
  @override
  Future<void> deleteRegion(String regionId) =>
      _db.delete('poi', where: 'region_id = ?', whereArgs: [regionId]);
  @override
  Future<List<PointOfInterest>> nearby(
    Coordinates origin, {
    String? category,
    String? query,
    double radiusMeters = 15000,
  }) async {
    final rows = await _db.query(
      'poi',
      where: category == null ? null : 'category = ?',
      whereArgs: category == null ? null : [category],
    );
    final result =
        rows
            .map((row) {
              final point = PointOfInterest(
                id: row['id']! as String,
                regionId: row['region_id']! as String,
                name: row['name']! as String,
                coordinates: Coordinates(
                  row['latitude']! as double,
                  row['longitude']! as double,
                ),
                category: row['category']! as String,
                subcategory: row['subcategory']! as String,
                address: row['address']! as String,
                description: row['description'] as String?,
              );
              return point.withDistance(
                distanceMeters(origin, point.coordinates),
              );
            })
            .where((point) {
              if (point.distanceMeters! > radiusMeters) return false;
              final normalized = query?.trim().toLowerCase() ?? '';
              if (normalized.isEmpty) return true;
              return point.name.toLowerCase().contains(normalized) ||
                  point.address.toLowerCase().contains(normalized) ||
                  point.subcategory.toLowerCase().contains(normalized);
            })
            .toList()
          ..sort((a, b) => a.distanceMeters!.compareTo(b.distanceMeters!));
    return result;
  }
}
