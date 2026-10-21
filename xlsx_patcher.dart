import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Eine Zeile fuer das Blatt "Erfassung".
class ErfassungRow {
  final int lfdNr;
  final String baumart;
  final double laenge;
  final double durchmesser;
  final String rinde;
  final String kommentar;

  const ErfassungRow({
    required this.lfdNr,
    required this.baumart,
    required this.laenge,
    required this.durchmesser,
    required this.rinde,
    required this.kommentar,
  });
}

/// Aendert in einer .xlsx-Datei NUR einzelne Zellen im Blatt "Erfassung".
/// Alles andere (Formeln, Dropdown-Listen, Formatierung, Blatt "Holzliste")
/// bleibt unveraendert. Im Gegensatz zum Neuschreiben der ganzen Datei
/// kann dabei nichts verloren gehen oder beschaedigt werden.
class XlsxPatcher {
  static const String _cols = 'ABCDEF';

  /// [writes]: Excel-Zeilennummer (1 = Kopfzeile) -> neuer Inhalt.
  /// [clears]: Excel-Zeilen, deren Spalten B bis F geleert werden sollen.
  static Uint8List patchErfassung(
    Uint8List xlsx, {
    required Map<int, ErfassungRow> writes,
    required List<int> clears,
  }) {
    final archive = ZipDecoder().decodeBytes(xlsx);

    String readText(String name) {
      final f = archive.findFile(name);
      if (f == null) throw StateError('In der Excel-Datei fehlt $name.');
      return utf8.decode(f.content as List<int>);
    }

    // 1. Datei des Blatts "Erfassung" ermitteln.
    final wb = readText('xl/workbook.xml');
    final sheetTag =
        RegExp(r'<sheet\b[^>]*\bname="Erfassung"[^>]*/>').firstMatch(wb);
    if (sheetTag == null) {
      throw StateError('Das Blatt "Erfassung" wurde nicht gefunden.');
    }
    final rid =
        RegExp(r'r:id="([^"]+)"').firstMatch(sheetTag.group(0)!)!.group(1)!;
    final rels = readText('xl/_rels/workbook.xml.rels');
    final relTag = RegExp(
      '<Relationship\\b[^>]*\\bId="${RegExp.escape(rid)}"[^>]*/>',
    ).firstMatch(rels);
    if (relTag == null) {
      throw StateError('Das Blatt "Erfassung" ist nicht verknuepft.');
    }
    final target =
        RegExp(r'Target="([^"]+)"').firstMatch(relTag.group(0)!)!.group(1)!;
    final path = target.startsWith('/') ? target.substring(1) : 'xl/$target';

    // 2. Zeilen des Blatts einlesen (unveraenderte Zeilen bleiben 1:1 erhalten).
    final sheet = readText(path);
    final start = sheet.indexOf('<sheetData>');
    final end = sheet.indexOf('</sheetData>');
    if (start < 0 || end < 0) {
      throw StateError('Das Blatt "Erfassung" hat ein unerwartetes Format.');
    }
    final bodyStart = start + '<sheetData>'.length;
    final head = sheet.substring(0, bodyStart);
    final body = sheet.substring(bodyStart, end);
    final tail = sheet.substring(end);

    final rowRe = RegExp(r'<row\b[^>]*?(?:/>|>.*?</row>)', dotAll: true);
    final cellRe = RegExp(r'<c\b[^>]*?(?:/>|>.*?</c>)', dotAll: true);

    final rows = <int, String>{};
    for (final m in rowRe.allMatches(body)) {
      final raw = m.group(0)!;
      final r = int.parse(RegExp(r'\br="(\d+)"').firstMatch(raw)!.group(1)!);
      rows[r] = raw;
    }

    int colIndex(String letters) {
      var n = 0;
      for (final code in letters.codeUnits) {
        n = n * 26 + (code - 64);
      }
      return n;
    }

    void editRow(int rnum, Map<int, Object?> values) {
      final raw = rows[rnum];
      String openTag;
      final cells = <int, String>{};

      if (raw == null) {
        openTag = '<row r="$rnum">';
      } else {
        final gt = raw.indexOf('>');
        final selfClosing = raw.substring(0, gt + 1).endsWith('/>');
        openTag =
            selfClosing ? '${raw.substring(0, gt - 1)}>' : raw.substring(0, gt + 1);
        if (!selfClosing) {
          final inner = raw.substring(gt + 1, raw.lastIndexOf('</row>'));
          for (final cm in cellRe.allMatches(inner)) {
            final cell = cm.group(0)!;
            final letters =
                RegExp(r'\br="([A-Z]+)\d+"').firstMatch(cell)!.group(1)!;
            cells[colIndex(letters)] = cell;
          }
        }
      }

      values.forEach((ci, val) {
        final old = cells[ci];
        // Die Nummerierungs-Formeln in Spalte A nie ueberschreiben.
        if (ci == 1 && old != null && old.contains('<f')) return;
        String? style;
        if (old != null) {
          final tag = old.substring(0, old.indexOf('>') + 1);
          style = RegExp(r'\bs="(\d+)"').firstMatch(tag)?.group(1);
        }
        cells[ci] = _makeCell('${_cols[ci - 1]}$rnum', style, val);
      });

      final keys = cells.keys.toList()..sort();
      rows[rnum] = '$openTag${keys.map((k) => cells[k]!).join()}</row>';
    }

    writes.forEach((rnum, r) {
      editRow(rnum, {
        1: r.lfdNr,
        2: r.baumart,
        3: r.laenge,
        4: r.durchmesser,
        5: r.rinde,
        6: r.kommentar,
      });
    });
    for (final rnum in clears) {
      editRow(rnum, {2: '', 3: '', 4: '', 5: '', 6: ''});
    }

    final rowKeys = rows.keys.toList()..sort();
    final newSheet = '$head${rowKeys.map((k) => rows[k]!).join()}$tail';

    // 3. Excel anweisen, beim Oeffnen alle Formeln neu zu berechnen,
    //    damit das Blatt "Holzliste" die neuen Werte sofort zeigt.
    var newWb = wb;
    final calc = RegExp(r'<calcPr\b([^>]*?)(/?)>').firstMatch(wb);
    if (calc != null) {
      final attrs = calc.group(1) ?? '';
      if (!attrs.contains('fullCalcOnLoad')) {
        newWb = wb.replaceRange(
          calc.start,
          calc.end,
          '<calcPr$attrs fullCalcOnLoad="1"${calc.group(2) ?? ''}>',
        );
      }
    } else {
      newWb = wb.replaceFirst(
        '</sheets>',
        '</sheets><calcPr fullCalcOnLoad="1"/>',
      );
    }

    // 4. Datei neu verpacken, alle anderen Teile unveraendert uebernehmen.
    final out = Archive();
    for (final f in archive.files) {
      if (f.name == path) {
        final bytes = utf8.encode(newSheet);
        out.addFile(ArchiveFile(f.name, bytes.length, bytes));
      } else if (f.name == 'xl/workbook.xml') {
        final bytes = utf8.encode(newWb);
        out.addFile(ArchiveFile(f.name, bytes.length, bytes));
      } else {
        out.addFile(f);
      }
    }
    final data = ZipEncoder().encode(out);
    if (data == null) {
      throw StateError('Excel-Datei konnte nicht erzeugt werden.');
    }
    return Uint8List.fromList(data);
  }

  static String _makeCell(String ref, String? style, Object? value) {
    final s = style == null ? '' : ' s="$style"';
    if (value == null || (value is String && value.isEmpty)) {
      return '<c r="$ref"$s/>';
    }
    if (value is num) {
      return '<c r="$ref"$s><v>$value</v></c>';
    }
    final text = value.toString();
    final preserve = text != text.trim() ? ' xml:space="preserve"' : '';
    return '<c r="$ref"$s t="inlineStr"><is><t$preserve>${_escape(text)}</t></is></c>';
  }

  static String _escape(String t) => t
      .replaceAll(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]'), '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
