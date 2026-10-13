import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:excel/excel.dart' as xls;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../models/log_entry.dart';
import 'db_service.dart';
import 'onedrive_auth_service.dart';
import 'volume_calculator.dart';

enum SyncStatus { idle, syncing, ok, waitingForWifi, error }

/// Die Datei liegt bewusst im "App-Ordner" von OneDrive
/// (Files.ReadWrite.AppFolder-Berechtigung). Die App bekommt damit
/// NUR Zugriff auf einen eigenen, abgeschotteten Ordner - nicht auf
/// dein gesamtes privates OneDrive. Das ist die sicherste verfuegbare
/// Berechtigungsstufe fuer diesen Anwendungsfall.
class OneDriveSyncService {
  OneDriveSyncService._();
  static final OneDriveSyncService instance = OneDriveSyncService._();

  static const String _fileName = 'Holzliste.xlsx';
  static const String _graphAppFolder =
      'https://graph.microsoft.com/v1.0/me/drive/special/approot';

  static const int _maxTemplateRows = 722; // vorbefuellte Formelzeilen

  SyncStatus status = SyncStatus.idle;
  int pendingCount = 0;
  String? lastError;

  Future<bool> _isOnWifi() async {
    final result = await Connectivity().checkConnectivity();
    return result.contains(ConnectivityResult.wifi);
  }

  /// Wird nach jedem lokalen Speichern sowie periodisch/bei WLAN-Wechsel
  /// aufgerufen. Meldet zurueck, ob synchronisiert wurde.
  Future<bool> trySync() async {
    final unsynced = await DbService.instance.unsynced();
    pendingCount = unsynced.length;

    if (unsynced.isEmpty) {
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
      final bytes = await _downloadOrCreateWorkbook(token);
      final workbook = xls.Excel.decodeBytes(bytes);
      final sheet = workbook['Erfassung'];

      if (unsynced.map((e) => e.lfdNr).reduce((a, b) => a > b ? a : b) >
          _maxTemplateRows) {
        status = SyncStatus.error;
        lastError =
            'Die Vorlage ist auf $_maxTemplateRows Zeilen ausgelegt. '
            'Bitte die Formeln im Blatt "Holzliste" am PC nach unten '
            'erweitern.';
        return false;
      }

      for (final entry in unsynced) {
        final row = entry.lfdNr + 1; // Zeile 1 = Kopfzeile
        _setCell(sheet, 0, row, entry.lfdNr);
        _setCell(sheet, 1, row, baumartenAnzeige[entry.baumart]);
        _setCell(sheet, 2, row, entry.laenge);
        _setCell(sheet, 3, row, entry.durchmesser);
        _setCell(sheet, 4, row, entry.rinde);
        _setCell(sheet, 5, row, entry.kommentar);
      }

      final updatedBytes = workbook.encode();
      if (updatedBytes == null) {
        throw StateError('Excel-Datei konnte nicht erzeugt werden.');
      }
      await _upload(token, Uint8List.fromList(updatedBytes));

      for (final entry in unsynced) {
        await DbService.instance.markSynced(entry.id);
      }

      pendingCount = 0;
      status = SyncStatus.ok;
      lastError = null;
      return true;
    } catch (e) {
      status = SyncStatus.error;
      lastError = e.toString();
      return false;
    }
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

  Future<Uint8List> _downloadOrCreateWorkbook(String token) async {
    final getResp = await http.get(
      Uri.parse('$_graphAppFolder:/$_fileName:/content'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (getResp.statusCode == 200) {
      return getResp.bodyBytes;
    }

    // Datei existiert im App-Ordner noch nicht -> mitgelieferte
    // Original-Vorlage (inkl. Formeln in "Holzliste") einmalig hochladen.
    final template = await rootBundle.load(
      'assets/templates/Holzliste_Vorlage.xlsx',
    );
    final bytes = template.buffer.asUint8List();
    await _upload(token, bytes);
    return bytes;
  }

  Future<void> _upload(String token, Uint8List bytes) async {
    final resp = await http.put(
      Uri.parse('$_graphAppFolder:/$_fileName:/content'),
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
