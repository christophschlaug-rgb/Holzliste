import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:excel/excel.dart' as xls;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../models/log_entry.dart';
import 'db_service.dart';
import 'onedrive_auth_service.dart';

enum SyncStatus { idle, syncing, ok, waitingForWifi, error }

/// Was bei einer Liste noch an OneDrive uebertragen werden muss.
class _ListWork {
  final ListInfo list;

  /// Neue oder geaenderte Eintraege (inkl. neu nummerierter).
  final List<LogEntry> entries;

  /// Aktuelle Anzahl der Eintraege in der Liste.
  final int total;

  /// Zeilen, die in der Excel nicht mehr gebraucht werden
  /// (durch Loeschen oder Verschieben frei geworden).
  final int stale;

  const _ListWork(this.list, this.entries, this.total, this.stale);
}

/// Jede Liste hat ihre eigene Excel-Datei im "App-Ordner" von OneDrive
/// (Files.ReadWrite.AppFolder-Berechtigung). Die App bekommt damit
/// NUR Zugriff auf einen eigenen, abgeschotteten Ordner - nicht auf
/// dein gesamtes privates OneDrive.
class OneDriveSyncService {
  OneDriveSyncService._();
  static final OneDriveSyncService instance = OneDriveSyncService._();

  static const String _graphAppFolder =
      'https://graph.microsoft.com/v1.0/me/drive/special/approot';

  // Die Vorlage hat Formeln bis Excel-Zeile 722 vorbefuellt
  // (Zeile 1 = Kopfzeile, also maximal lfd. Nr. 721).
  static const int _maxLfdNr = 721;

  SyncStatus status = SyncStatus.idle;
  int pendingCount = 0;
  String? lastError;

  bool _running = false;
  bool _again = false;

  Future<bool> _isOnWifi() async {
    final result = await Connectivity().checkConnectivity();
    return result.contains(ConnectivityResult.wifi);
  }

  /// Wird nach jeder Aenderung sowie beim Start aufgerufen. Laeuft bereits
  /// ein Sync, wird danach automatisch noch einmal synchronisiert, damit
  /// zwei gleichzeitige Uploads nie dieselbe Datei ueberschreiben.
  Future<bool> trySync() async {
    if (_running) {
      _again = true;
      return false;
    }
    _running = true;
    try {
      var ok = false;
      do {
        _again = false;
        ok = await _syncOnce();
      } while (_again && ok);
      return ok;
    } finally {
      _running = false;
    }
  }

  int _pendingOf(List<_ListWork> work) =>
      work.fold<int>(0, (sum, w) => sum + w.entries.length + w.stale);

  Future<List<_ListWork>> _collectWork() async {
    final lists = await DbService.instance.lists();
    final unsynced = await DbService.instance.unsynced();

    final result = <_ListWork>[];
    for (final l in lists) {
      final entries = unsynced.where((e) => e.listId == l.id).toList();
      final total = await DbService.instance.countEntries(l.id);
      final stale = l.syncedRows > total ? l.syncedRows - total : 0;
      if (entries.isNotEmpty || stale > 0) {
        result.add(_ListWork(l, entries, total, stale));
      }
    }
    return result;
  }

  Future<bool> _syncOnce() async {
    final work = await _collectWork();
    pendingCount = _pendingOf(work);

    if (work.isEmpty) {
      status = SyncStatus.ok;
      return true;
    }

    if (!await _isOnWifi()) {
      status = SyncStatus.waitingForWifi;
      return false;
    }

    final token = await OneDriveAuthService.instance.validAccessToken();
    if (token == null) {
      status = SyncStatus.error;
      lastError = 'Nicht mit OneDrive verbunden.';
      return false;
    }

    status = SyncStatus.syncing;
    try {
      for (final w in work) {
        await _syncList(token, w);
      }
      pendingCount = _pendingOf(await _collectWork());
      status = SyncStatus.ok;
      lastError = null;
      return true;
    } catch (e) {
      status = SyncStatus.error;
      lastError = e.toString();
      try {
        pendingCount = _pendingOf(await _collectWork());
      } catch (_) {}
      return false;
    }
  }

  Future<void> _syncList(String token, _ListWork w) async {
    if (w.total > _maxLfdNr) {
      throw StateError(
        'Die Vorlage ist auf $_maxLfdNr Zeilen ausgelegt. '
        'Bitte die Formeln im Blatt "Holzliste" am PC nach unten erweitern.',
      );
    }

    final bytes = await _downloadOrCreateWorkbook(token, w.list.fileName);
    final workbook = xls.Excel.decodeBytes(bytes);
    final sheet = workbook['Erfassung'];

    for (final entry in w.entries) {
      final row = entry.lfdNr; // Zeilenindex 0 = Kopfzeile
      _setCell(sheet, 0, row, entry.lfdNr);
      _setCell(sheet, 1, row, baumartenAnzeige[entry.baumart]);
      _setCell(sheet, 2, row, entry.laenge);
      _setCell(sheet, 3, row, entry.durchmesser);
      _setCell(sheet, 4, row, entry.rinde);
      _setCell(sheet, 5, row, entry.kommentar);
    }

    // Zeilen leeren, die durch Loeschen/Verschieben frei geworden sind.
    // Die Nummerierung in Spalte A bleibt wie in der Vorlage stehen.
    for (var nr = w.total + 1; nr <= w.list.syncedRows; nr++) {
      for (var col = 1; col <= 5; col++) {
        _setCell(sheet, col, nr, '');
      }
    }

    final updatedBytes = workbook.encode();
    if (updatedBytes == null) {
      throw StateError('Excel-Datei konnte nicht erzeugt werden.');
    }
    await _upload(token, w.list.fileName, Uint8List.fromList(updatedBytes));

    for (final entry in w.entries) {
      await DbService.instance.markSynced(entry);
    }
    await DbService.instance.setSyncedRows(w.list.id, w.total);
  }

  void _setCell(xls.Sheet sheet, int col, int row, Object? value) {
    final cell = sheet.cell(
      xls.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    if (value is num) {
      cell.value = xls.DoubleCellValue(value.toDouble());
    } else if (value != null) {
      cell.value = xls.TextCellValue(value.toString());
    }
  }

  Uri _fileUri(String fileName) => Uri.parse(
        '$_graphAppFolder:/${Uri.encodeComponent(fileName)}:/content',
      );

  Future<Uint8List> _downloadOrCreateWorkbook(
    String token,
    String fileName,
  ) async {
    final resp = await http.get(
      _fileUri(fileName),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (resp.statusCode == 200) {
      return resp.bodyBytes;
    }

    // Nur wenn die Datei sicher nicht existiert (404), wird die Vorlage
    // angelegt. Bei jedem anderen Fehler bricht der Sync ab, damit eine
    // bestehende Excel nie durch die leere Vorlage ueberschrieben wird.
    if (resp.statusCode != 404) {
      throw StateError('OneDrive-Download fehlgeschlagen (${resp.statusCode}).');
    }

    final template = await rootBundle.load(
      'assets/templates/Holzliste_Vorlage.xlsx',
    );
    final bytes = template.buffer.asUint8List(
      template.offsetInBytes,
      template.lengthInBytes,
    );
    await _upload(token, fileName, bytes);
    return bytes;
  }

  Future<void> _upload(String token, String fileName, Uint8List bytes) async {
    final resp = await http.put(
      _fileUri(fileName),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type':
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      },
      body: bytes,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw StateError('OneDrive-Upload fehlgeschlagen (${resp.statusCode}).');
    }
  }
}
