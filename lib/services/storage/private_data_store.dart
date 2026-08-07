import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

abstract interface class PrivateDataStore {
  Future<void> open();
  Future<void> deleteEverything();
}

class SqlitePrivateDataStore implements PrivateDataStore {
  Database? _database;
  @override
  Future<void> open() async {
    final root = await getApplicationSupportDirectory();
    _database = await openDatabase(
      p.join(root.path, 'private_user_data.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE private_values (key TEXT PRIMARY KEY, value TEXT)',
        );
      },
    );
  }

  @override
  Future<void> deleteEverything() async => _database?.delete('private_values');
}
