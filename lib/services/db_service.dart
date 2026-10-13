import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/log_entry.dart';
import 'secure_storage_service.dart';

/// Kapselt den Zugriff auf die lokale, verschluesselte Geraete-Datenbank.
/// Die App funktioniert damit vollstaendig offline; die Verschluesselung
/// schuetzt die Daten, falls das Handy im Wald verloren geht.
class DbService {
  DbService._();
  static final DbService instance = DbService._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, 'holzliste.db');

    // Der Verschluesselungsschluessel liegt nicht im Code, sondern wird
    // einmalig zufaellig erzeugt und sicher im Android Keystore abgelegt.
    final password = await SecureStorageService.instance.getOrCreateDbKey();

    return openDatabase(
      path,
      password: password,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE entries (
            id TEXT PRIMARY KEY,
            lfd_nr INTEGER NOT NULL,
            baumart TEXT NOT NULL,
            laenge REAL NOT NULL,
            durchmesser REAL NOT NULL,
            rinde TEXT NOT NULL,
            kommentar TEXT,
            latitude REAL,
            longitude REAL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            synced INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
    );
  }

  Future<int> nextLfdNr() async {
    final db = await database;
    final result = await db.rawQuery('SELECT MAX(lfd_nr) AS m FROM entries');
    final max = result.first['m'] as int?;
    return (max ?? 0) + 1;
  }

  Future<void> upsert(LogEntry entry) async {
    final db = await database;
    await db.insert(
      'entries',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    final db = await database;
    await db.delete('entries', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<LogEntry>> all() async {
    final db = await database;
    final rows = await db.query('entries', orderBy: 'lfd_nr ASC');
    return rows.map(LogEntry.fromMap).toList();
  }

  Future<List<LogEntry>> unsynced() async {
    final db = await database;
    final rows = await db.query(
      'entries',
      where: 'synced = 0',
      orderBy: 'lfd_nr ASC',
    );
    return rows.map(LogEntry.fromMap).toList();
  }

  Future<void> markSynced(String id) async {
    final db = await database;
    await db.update(
      'entries',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
