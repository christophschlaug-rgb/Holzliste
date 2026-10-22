import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/log_entry.dart';
import 'secure_storage_service.dart';

/// Kapselt den Zugriff auf die lokale, verschluesselte Geraete-Datenbank.
/// Die App funktioniert damit vollstaendig offline; die Verschluesselung
/// schuetzt die Daten, falls das Handy im Wald verloren geht.
class DbService {
  DbService._();
  static final DbService instance = DbService._();

  Future<Database>? _opening;

  /// Die Datenbank wird nur einmal geoeffnet; gleichzeitige Zugriffe
  /// (z. B. beim App-Start) teilen sich dasselbe Ergebnis.
  Future<Database> get database {
    return _opening ??= _open().catchError((Object e) {
      _opening = null;
      throw e;
    });
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, 'holzliste.db');

    // Der Verschluesselungsschluessel liegt nicht im Code, sondern wird
    // einmalig zufaellig erzeugt und sicher im Android Keystore abgelegt.
    final dbExists = await File(path).exists();
    final password = await SecureStorageService.instance
        .getOrCreateDbKey(allowCreate: !dbExists);

    return openDatabase(
      path,
      password: password,
      version: 4,
      onCreate: (db, version) async {
        await _createEntriesTable(db);
        await _createListsTable(db);
        await _insertDefaultList(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Bestehende Eintraege wandern in die Standard-Liste.
          await _createListsTable(db); // enthaelt bereits synced_rows
          await _insertDefaultList(db);
          await db.execute(
            "ALTER TABLE entries ADD COLUMN list_id TEXT NOT NULL DEFAULT '$defaultListId'",
          );
        } else {
          if (oldVersion < 3) {
            await db.execute(
              'ALTER TABLE lists ADD COLUMN synced_rows INTEGER NOT NULL DEFAULT 0',
            );
          }
          if (oldVersion < 4) {
            await db.execute(
              'ALTER TABLE lists ADD COLUMN closed INTEGER NOT NULL DEFAULT 0',
            );
          }
        }
        if (oldVersion < 3) {
          // Bereits uebertragene Zeilen je Liste uebernehmen.
          await db.execute('''
            UPDATE lists SET synced_rows = COALESCE(
              (SELECT MAX(lfd_nr) FROM entries
                WHERE entries.list_id = lists.id AND entries.synced = 1),
              0)
          ''');
        }
      },
    );
  }

  Future<void> _createEntriesTable(Database db) async {
    await db.execute('''
      CREATE TABLE entries (
        id TEXT PRIMARY KEY,
        list_id TEXT NOT NULL DEFAULT '$defaultListId',
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
  }

  Future<void> _createListsTable(Database db) async {
    await db.execute('''
      CREATE TABLE lists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        file_name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        synced_rows INTEGER NOT NULL DEFAULT 0,
        closed INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _insertDefaultList(Database db) async {
    final info = ListInfo(
      id: defaultListId,
      name: 'Liste 1',
      fileName: 'Holzliste.xlsx',
      createdAt: DateTime.now(),
    );
    await db.insert('lists', info.toMap());
  }

  // ---------------------------------------------------------------- Listen

  Future<List<ListInfo>> lists() async {
    final db = await database;
    final rows = await db.query('lists', orderBy: 'created_at ASC');
    return rows.map(ListInfo.fromMap).toList();
  }

  /// Legt eine neue Liste samt eigenem, eindeutigem Excel-Dateinamen an.
  Future<ListInfo> createList(String name) async {
    final db = await database;
    final existing = await lists();
    final usedFiles = existing.map((l) => l.fileName.toLowerCase()).toSet();

    // Dateiname mit Anlagedatum: so kann eine neue Liste nie versehentlich
    // eine alte Excel-Datei gleichen Namens in OneDrive weiterbenutzen.
    final now = DateTime.now();
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}'
        '-${now.day.toString().padLeft(2, '0')}';
    final base = _sanitizeFileName(name);
    var fileName = 'Holzliste - $base $date.xlsx';
    var counter = 2;
    while (usedFiles.contains(fileName.toLowerCase())) {
      fileName = 'Holzliste - $base $date ($counter).xlsx';
      counter++;
    }

    final info = ListInfo(
      id: const Uuid().v4(),
      name: name.trim(),
      fileName: fileName,
      createdAt: DateTime.now(),
    );
    await db.insert('lists', info.toMap());
    return info;
  }

  String _sanitizeFileName(String name) {
    var cleaned = name
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|#%&{}~]'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.length > 60) cleaned = cleaned.substring(0, 60).trim();
    return cleaned.isEmpty ? 'Liste' : cleaned;
  }

  /// Benennt eine Liste um. Der Dateiname der Excel in OneDrive bleibt
  /// bewusst unveraendert, damit die Synchronisation stabil bleibt.
  Future<void> renameList(String id, String name) async {
    final db = await database;
    await db.update(
      'lists',
      {'name': name.trim()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> setListClosed(String id, bool closed) async {
    final db = await database;
    await db.update(
      'lists',
      {'closed': closed ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Loescht eine Liste samt aller Stamm-Eintraege von diesem Geraet.
  /// Die Excel-Datei in OneDrive wird nie angefasst.
  Future<void> deleteList(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('entries', where: 'list_id = ?', whereArgs: [id]);
      await txn.delete('lists', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<int> countUnsyncedEntries(String listId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM entries WHERE list_id = ? AND synced = 0',
      [listId],
    );
    return (result.first['c'] as int?) ?? 0;
  }

  Future<void> setSyncedRows(String listId, int rows) async {
    final db = await database;
    await db.update(
      'lists',
      {'synced_rows': rows},
      where: 'id = ?',
      whereArgs: [listId],
    );
  }

  // -------------------------------------------------------------- Eintraege

  Future<int> nextLfdNr(String listId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT MAX(lfd_nr) AS m FROM entries WHERE list_id = ?',
      [listId],
    );
    final max = result.first['m'] as int?;
    return (max ?? 0) + 1;
  }

  Future<int> countEntries(String listId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM entries WHERE list_id = ?',
      [listId],
    );
    return (result.first['c'] as int?) ?? 0;
  }

  Future<void> upsert(LogEntry entry) async {
    final db = await database;
    await db.insert(
      'entries',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<LogEntry>> all(String listId) async {
    final db = await database;
    final rows = await db.query(
      'entries',
      where: 'list_id = ?',
      whereArgs: [listId],
      orderBy: 'lfd_nr ASC',
    );
    return rows.map(LogEntry.fromMap).toList();
  }

  /// Alle noch nicht synchronisierten Eintraege, ueber alle Listen hinweg.
  Future<List<LogEntry>> unsynced() async {
    final db = await database;
    final rows = await db.query(
      'entries',
      where: 'synced = 0',
      orderBy: 'lfd_nr ASC',
    );
    return rows.map(LogEntry.fromMap).toList();
  }

  /// Markiert einen Eintrag nur dann als synchronisiert, wenn er sich seit
  /// dem Auslesen nicht veraendert hat (Bearbeiten, Verschieben waehrend
  /// eines laufenden Syncs).
  Future<void> markSynced(LogEntry e) async {
    final db = await database;
    await db.update(
      'entries',
      {'synced': 1},
      where: 'id = ? AND updated_at = ? AND lfd_nr = ? AND list_id = ?',
      whereArgs: [e.id, e.updatedAt.toIso8601String(), e.lfdNr, e.listId],
    );
  }

  // ------------------------------------------- Loeschen, Reihenfolge, Umzug

  /// Setzt die Reihenfolge einer Liste: lfd. Nr. = Position (ab 1).
  /// Nur Eintraege, deren Nummer sich aendert, muessen neu synchronisiert
  /// werden.
  Future<void> applyOrder(String listId, List<String> orderedIds) async {
    final db = await database;
    await db.transaction((txn) async {
      for (var i = 0; i < orderedIds.length; i++) {
        await txn.rawUpdate(
          'UPDATE entries SET lfd_nr = ?, synced = 0 '
          'WHERE id = ? AND list_id = ? AND lfd_nr != ?',
          [i + 1, orderedIds[i], listId, i + 1],
        );
      }
    });
  }

  /// Zaehlt eine Liste nach Aenderungen lueckenlos von 1 an durch
  /// (wie die Nummerierung in der Excel).
  Future<void> _renumber(String listId) async {
    final remaining = await all(listId);
    await applyOrder(listId, remaining.map((e) => e.id).toList());
  }

  Future<void> deleteEntries(String listId, List<String> ids) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.delete('entries', where: 'id = ?', whereArgs: [id]);
      }
    });
    await _renumber(listId);
  }

  /// Verschiebt Eintraege (in der uebergebenen Reihenfolge) ans Ende einer
  /// anderen Liste und zaehlt die Quellliste neu durch.
  Future<void> moveToList(
    List<String> ids,
    String fromListId,
    String toListId,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      final result = await txn.rawQuery(
        'SELECT MAX(lfd_nr) AS m FROM entries WHERE list_id = ?',
        [toListId],
      );
      var next = ((result.first['m'] as int?) ?? 0) + 1;
      for (final id in ids) {
        await txn.update(
          'entries',
          {'list_id': toListId, 'lfd_nr': next, 'synced': 0},
          where: 'id = ?',
          whereArgs: [id],
        );
        next++;
      }
    });
    await _renumber(fromListId);
  }
}
