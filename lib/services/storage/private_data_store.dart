import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/models/geo.dart';
import '../../core/models/poi.dart';
import '../../core/models/visited_place.dart';

abstract interface class PrivateDataStore {
  Future<void> open();
  Future<PointOfInterest> saveCustomPlace({
    required String name,
    required String tag,
    required Coordinates coordinates,
    bool overwrite = false,
  });
  Future<List<PointOfInterest>> customPlaces();
  Future<List<PointOfInterest>> customPlacesNear(
    Coordinates coordinates, {
    double radiusMeters = 100,
  });
  Future<void> deleteCustomPlace(String id);
  Future<void> deleteCustomPlaces();
  Future<void> recordVisit(PointOfInterest place, DateTime visitedAt);
  Future<List<VisitedPlace>> mostVisited();
  Future<void> deleteVisitHistory();
  Future<void> deleteEverything();
}

class SqlitePrivateDataStore implements PrivateDataStore {
  Database? _database;
  @override
  Future<void> open() async {
    final root = await getApplicationSupportDirectory();
    _database = await openDatabase(
      p.join(root.path, 'private_user_data.db'),
      version: 4,
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE private_values (key TEXT PRIMARY KEY, value TEXT)',
        );
        await _createVisitsTable(db);
        await _createCustomPlacesTable(db);
      },
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) await _createVisitsTable(db);
        if (oldVersion < 3) await _createCustomPlacesTable(db);
        if (oldVersion >= 3 && oldVersion < 4) {
          await _migrateCustomPlacesToV4(db);
        }
      },
    );
  }

  @override
  Future<PointOfInterest> saveCustomPlace({
    required String name,
    required String tag,
    required Coordinates coordinates,
    bool overwrite = false,
  }) async {
    final db = _database ?? (throw StateError('Private database is not open'));
    final placeKey = _customPlaceKey(name, tag);
    final existingRows = await db.query(
      'custom_places',
      where: 'place_key = ?',
      whereArgs: [placeKey],
      limit: 1,
    );
    if (existingRows.isNotEmpty && !overwrite) {
      throw CustomPlaceConflictException(
        _customPlaceFromRow(existingRows.first),
      );
    }
    final id = existingRows.isEmpty
        ? 'custom-${DateTime.now().microsecondsSinceEpoch}'
        : existingRows.first['id']! as String;
    final place = PointOfInterest(
      id: id,
      regionId: 'private-custom',
      name: name.trim(),
      coordinates: coordinates,
      category: tag,
      subcategory: 'custom',
      address: '',
      description: 'Private custom place',
    );
    final values = {
      'id': place.id,
      'place_key': placeKey,
      'name': place.name,
      'tag': place.category,
      'latitude': coordinates.latitude,
      'longitude': coordinates.longitude,
      'created_ms': DateTime.now().millisecondsSinceEpoch,
    };
    if (existingRows.isEmpty) {
      await db.insert('custom_places', values);
    } else {
      await db.update(
        'custom_places',
        values,
        where: 'id = ?',
        whereArgs: [id],
      );
      await db.update(
        'visited_places',
        {
          'name': place.name,
          'category': place.category,
          'latitude': coordinates.latitude,
          'longitude': coordinates.longitude,
        },
        where: 'poi_id = ?',
        whereArgs: [id],
      );
    }
    return place;
  }

  @override
  Future<List<PointOfInterest>> customPlaces() async {
    final db = _database ?? (throw StateError('Private database is not open'));
    final rows = await db.query('custom_places', orderBy: 'created_ms DESC');
    return rows.map(_customPlaceFromRow).toList();
  }

  @override
  Future<List<PointOfInterest>> customPlacesNear(
    Coordinates coordinates, {
    double radiusMeters = 100,
  }) async {
    final places = await customPlaces();
    return places
        .map(
          (place) => place.withDistance(
            distanceMeters(coordinates, place.coordinates),
          ),
        )
        .where((place) => place.distanceMeters! <= radiusMeters)
        .toList()
      ..sort((a, b) => a.distanceMeters!.compareTo(b.distanceMeters!));
  }

  @override
  Future<void> deleteCustomPlace(String id) async {
    await _database?.delete('custom_places', where: 'id = ?', whereArgs: [id]);
    await _database?.delete(
      'visited_places',
      where: 'poi_id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> deleteCustomPlaces() async {
    final places = await customPlaces();
    for (final place in places) {
      await deleteCustomPlace(place.id);
    }
  }

  @override
  Future<void> recordVisit(PointOfInterest place, DateTime visitedAt) async {
    final db = _database ?? (throw StateError('Private database is not open'));
    await db.transaction((transaction) async {
      final rows = await transaction.query(
        'visited_places',
        columns: ['visit_count', 'last_visited_ms'],
        where: 'poi_id = ?',
        whereArgs: [place.id],
        limit: 1,
      );
      final milliseconds = visitedAt.millisecondsSinceEpoch;
      if (rows.isEmpty) {
        await transaction.insert('visited_places', {
          'poi_id': place.id,
          'name': place.name,
          'category': place.category,
          'address': place.address,
          'latitude': place.coordinates.latitude,
          'longitude': place.coordinates.longitude,
          'visit_count': 1,
          'first_visited_ms': milliseconds,
          'last_visited_ms': milliseconds,
        });
        return;
      }
      final lastVisited = rows.first['last_visited_ms']! as int;
      final count = rows.first['visit_count']! as int;
      final isNewVisit =
          milliseconds - lastVisited >= const Duration(hours: 4).inMilliseconds;
      await transaction.update(
        'visited_places',
        {
          'name': place.name,
          'category': place.category,
          'address': place.address,
          'latitude': place.coordinates.latitude,
          'longitude': place.coordinates.longitude,
          'visit_count': isNewVisit ? count + 1 : count,
          'last_visited_ms': milliseconds,
        },
        where: 'poi_id = ?',
        whereArgs: [place.id],
      );
    });
  }

  @override
  Future<List<VisitedPlace>> mostVisited() async {
    final db = _database ?? (throw StateError('Private database is not open'));
    final rows = await db.query(
      'visited_places',
      orderBy: 'visit_count DESC, last_visited_ms DESC',
    );
    return rows
        .map(
          (row) => VisitedPlace(
            poiId: row['poi_id']! as String,
            name: row['name']! as String,
            category: row['category']! as String,
            address: row['address']! as String,
            coordinates: Coordinates(
              row['latitude']! as double,
              row['longitude']! as double,
            ),
            visitCount: row['visit_count']! as int,
            firstVisited: DateTime.fromMillisecondsSinceEpoch(
              row['first_visited_ms']! as int,
            ),
            lastVisited: DateTime.fromMillisecondsSinceEpoch(
              row['last_visited_ms']! as int,
            ),
          ),
        )
        .toList();
  }

  @override
  Future<void> deleteVisitHistory() async =>
      _database?.delete('visited_places');

  @override
  Future<void> deleteEverything() async {
    await _database?.delete('private_values');
    await deleteVisitHistory();
    await deleteCustomPlaces();
  }

  static Future<void> _createVisitsTable(Database db) => db.execute(
    'CREATE TABLE visited_places (poi_id TEXT PRIMARY KEY, name TEXT NOT NULL, category TEXT NOT NULL, address TEXT NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL, visit_count INTEGER NOT NULL, first_visited_ms INTEGER NOT NULL, last_visited_ms INTEGER NOT NULL)',
  );

  static Future<void> _createCustomPlacesTable(Database db) => db.execute(
    'CREATE TABLE custom_places (id TEXT PRIMARY KEY, place_key TEXT NOT NULL UNIQUE, name TEXT NOT NULL, tag TEXT NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL, created_ms INTEGER NOT NULL)',
  );

  static Future<void> _migrateCustomPlacesToV4(Database db) async {
    await db.execute(
      'CREATE TABLE custom_places_v4 (id TEXT PRIMARY KEY, place_key TEXT NOT NULL UNIQUE, name TEXT NOT NULL, tag TEXT NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL, created_ms INTEGER NOT NULL)',
    );
    final rows = await db.query('custom_places', orderBy: 'created_ms DESC');
    final retainedKeys = <String>{};
    for (final row in rows) {
      final id = row['id']! as String;
      final key = _customPlaceKey(
        row['name']! as String,
        row['tag']! as String,
      );
      if (!retainedKeys.add(key)) {
        await db.delete('visited_places', where: 'poi_id = ?', whereArgs: [id]);
        continue;
      }
      await db.insert('custom_places_v4', {...row, 'place_key': key});
    }
    await db.execute('DROP TABLE custom_places');
    await db.execute('ALTER TABLE custom_places_v4 RENAME TO custom_places');
  }

  static String _customPlaceKey(String name, String tag) {
    final normalizedTag = tag.trim().toLowerCase();
    if (normalizedTag == 'home' || normalizedTag == 'work') {
      return normalizedTag;
    }
    final normalizedName = name.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    return 'other:$normalizedName';
  }

  PointOfInterest _customPlaceFromRow(Map<String, Object?> row) =>
      PointOfInterest(
        id: row['id']! as String,
        regionId: 'private-custom',
        name: row['name']! as String,
        coordinates: Coordinates(
          row['latitude']! as double,
          row['longitude']! as double,
        ),
        category: row['tag']! as String,
        subcategory: 'custom',
        address: '',
        description: 'Private custom place',
      );
}

class CustomPlaceConflictException implements Exception {
  const CustomPlaceConflictException(this.existing);
  final PointOfInterest existing;
}
