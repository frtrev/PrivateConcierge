import 'dart:math' as math;
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../core/models/geo.dart';
import '../core/models/poi.dart';
import '../core/models/opening_hours.dart';
import '../repositories/poi_repository.dart';

class SqlitePoiRepository implements PoiRepository {
  Database? _database;
  @override
  Future<void> open() async {
    final root = await getApplicationSupportDirectory();
    _database = await openDatabase(
      p.join(root.path, 'public_geography.db'),
      version: 3,
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE poi (id TEXT PRIMARY KEY, region_id TEXT NOT NULL, name TEXT NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL, category TEXT NOT NULL, subcategory TEXT NOT NULL, address TEXT NOT NULL, description TEXT, phone_number TEXT, website TEXT, opening_hours TEXT)',
        );
        await _createIndexes(db);
      },
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) await _createIndexes(db);
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE poi ADD COLUMN phone_number TEXT');
          await db.execute('ALTER TABLE poi ADD COLUMN website TEXT');
          await db.execute('ALTER TABLE poi ADD COLUMN opening_hours TEXT');
        }
      },
    );
  }

  Database get _db =>
      _database ?? (throw StateError('POI database is not open'));
  @override
  Future<void> replaceRegion(String regionId, List<PointOfInterest> points) =>
      _db.transaction((txn) async {
        await txn.delete('poi', where: 'region_id = ?', whereArgs: [regionId]);
        var batch = txn.batch();
        var pending = 0;
        for (final point in points) {
          batch.insert('poi', {
            'id': point.id,
            'region_id': regionId,
            'name': point.name,
            'latitude': point.coordinates.latitude,
            'longitude': point.coordinates.longitude,
            'category': point.category,
            'subcategory': point.subcategory,
            'address': point.address,
            'description': point.description,
            'phone_number': point.phoneNumber,
            'website': point.website?.toString(),
            'opening_hours': point.openingHours == null
                ? null
                : jsonEncode(point.openingHours!.toMap()),
          });
          pending++;
          if (pending == 1000) {
            await batch.commit(noResult: true);
            batch = txn.batch();
            pending = 0;
          }
        }
        if (pending > 0) await batch.commit(noResult: true);
      });

  static Future<void> _createIndexes(DatabaseExecutor db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_poi_lat_lon ON poi(latitude, longitude)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_poi_category_lat ON poi(category, latitude)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_poi_region ON poi(region_id)',
    );
  }

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
    final latitudeDelta = radiusMeters / 111320;
    final longitudeScale = math.cos(origin.latitude * math.pi / 180).abs();
    final longitudeDelta =
        radiusMeters / (111320 * math.max(longitudeScale, .01));
    final clauses = <String>[
      'latitude BETWEEN ? AND ?',
      'longitude BETWEEN ? AND ?',
    ];
    final arguments = <Object?>[
      origin.latitude - latitudeDelta,
      origin.latitude + latitudeDelta,
      origin.longitude - longitudeDelta,
      origin.longitude + longitudeDelta,
    ];
    if (category != null) {
      clauses.add('category = ?');
      arguments.add(category);
    }
    final rows = await _db.query(
      'poi',
      where: clauses.join(' AND '),
      whereArgs: arguments,
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
                phoneNumber: row['phone_number'] as String?,
                website: (row['website'] as String?) == null
                    ? null
                    : Uri.tryParse(row['website']! as String),
                openingHours: (row['opening_hours'] as String?) == null
                    ? null
                    : PlaceOpeningHours.fromMap(
                        jsonDecode(row['opening_hours']! as String)
                            as Map<String, dynamic>,
                      ),
              );
              return point.withDistance(
                distanceMeters(origin, point.coordinates),
              );
            })
            .where((point) {
              if (point.distanceMeters! > radiusMeters) return false;
              final normalized = query?.trim().toLowerCase() ?? '';
              if (normalized.isEmpty) return true;
              final searchText =
                  '${point.name} ${point.address} '
                          '${point.subcategory.replaceAll('_', ' ')}'
                      .toLowerCase();
              return searchText.contains(normalized);
            })
            .toList()
          ..sort((a, b) => a.distanceMeters!.compareTo(b.distanceMeters!));
    return result;
  }
}
