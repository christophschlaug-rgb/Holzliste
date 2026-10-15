/// ID der Standard-Liste (entspricht der bisherigen Datei Holzliste.xlsx).
const String defaultListId = 'default';

/// Eine Holzliste (z. B. pro Einschlagsort). Jede Liste hat ihre eigene
/// Excel-Datei im OneDrive-App-Ordner.
class ListInfo {
  final String id;
  final String name;
  final String fileName;
  final DateTime createdAt;

  /// Wie viele Zeilen der Excel-Datei beim letzten Sync beschrieben waren.
  /// Daran erkennt die App, welche Zeilen nach Loeschen/Verschieben
  /// in der Excel wieder geleert werden muessen.
  final int syncedRows;

  const ListInfo({
    required this.id,
    required this.name,
    required this.fileName,
    required this.createdAt,
    this.syncedRows = 0,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'file_name': fileName,
        'created_at': createdAt.toIso8601String(),
        'synced_rows': syncedRows,
      };

  factory ListInfo.fromMap(Map<String, Object?> map) => ListInfo(
        id: map['id'] as String,
        name: map['name'] as String,
        fileName: map['file_name'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
        syncedRows: (map['synced_rows'] as int?) ?? 0,
      );
}

/// Ein einzelner Baumstamm-Eintrag, entspricht einer Zeile
/// im Excel-Tabellenblatt "Erfassung".
class LogEntry {
  /// Stabile, lokal erzeugte ID (unabhaengig von der Zeilennummer),
  /// damit spaetere Korrekturen zuverlaessig wiedergefunden werden.
  final String id;

  /// Zu welcher Liste der Eintrag gehoert.
  final String listId;

  /// Fortlaufende Nummer innerhalb der Liste (Spalte A, "lfd Nr.").
  final int lfdNr;

  final String baumart;
  final double laenge; // Meter
  final double durchmesser; // Zentimeter
  final String rinde; // "mit Rinde" | "ohne Rinde"
  final String kommentar;

  final double? latitude;
  final double? longitude;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// true, sobald der Eintrag im aktuellen Stand in OneDrive angekommen ist.
  final bool synced;

  const LogEntry({
    required this.id,
    required this.listId,
    required this.lfdNr,
    required this.baumart,
    required this.laenge,
    required this.durchmesser,
    required this.rinde,
    this.kommentar = '',
    this.latitude,
    this.longitude,
    required this.createdAt,
    required this.updatedAt,
    this.synced = false,
  });

  LogEntry copyWith({
    int? lfdNr,
    String? baumart,
    double? laenge,
    double? durchmesser,
    String? rinde,
    String? kommentar,
    double? latitude,
    double? longitude,
    DateTime? updatedAt,
    bool? synced,
  }) {
    return LogEntry(
      id: id,
      listId: listId,
      lfdNr: lfdNr ?? this.lfdNr,
      baumart: baumart ?? this.baumart,
      laenge: laenge ?? this.laenge,
      durchmesser: durchmesser ?? this.durchmesser,
      rinde: rinde ?? this.rinde,
      kommentar: kommentar ?? this.kommentar,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      synced: synced ?? this.synced,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'list_id': listId,
        'lfd_nr': lfdNr,
        'baumart': baumart,
        'laenge': laenge,
        'durchmesser': durchmesser,
        'rinde': rinde,
        'kommentar': kommentar,
        'latitude': latitude,
        'longitude': longitude,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'synced': synced ? 1 : 0,
      };

  factory LogEntry.fromMap(Map<String, Object?> map) => LogEntry(
        id: map['id'] as String,
        listId: (map['list_id'] as String?) ?? defaultListId,
        lfdNr: map['lfd_nr'] as int,
        baumart: map['baumart'] as String,
        laenge: (map['laenge'] as num).toDouble(),
        durchmesser: (map['durchmesser'] as num).toDouble(),
        rinde: map['rinde'] as String,
        kommentar: map['kommentar'] as String? ?? '',
        latitude: (map['latitude'] as num?)?.toDouble(),
        longitude: (map['longitude'] as num?)?.toDouble(),
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
        synced: (map['synced'] as int) == 1,
      );
}

/// Feste Auswahllisten, identisch zum Tabellenblatt "Baumarten".
const List<String> baumartenListe = [
  'Fichte',
  'Kiefer',
  'Laerche',
  'Eiche',
  'Buche',
  'Birke',
];

// Anzeige mit korrekten Umlauten (interner Wert bleibt ASCII-stabil
// fuer den Excel-Abgleich, siehe volume_calculator.dart).
const Map<String, String> baumartenAnzeige = {
  'Fichte': 'Fichte',
  'Kiefer': 'Kiefer',
  'Laerche': 'Lärche',
  'Eiche': 'Eiche',
  'Buche': 'Buche',
  'Birke': 'Birke',
};

const List<String> rindeListe = ['mit Rinde', 'ohne Rinde'];
