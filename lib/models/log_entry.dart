/// Ein einzelner Baumstamm-Eintrag, entspricht einer Zeile
/// im Excel-Tabellenblatt "Erfassung".
class LogEntry {
  /// Stabile, lokal erzeugte ID (unabhaengig von der Zeilennummer),
  /// damit spaetere Korrekturen zuverlaessig wiedergefunden werden.
  final String id;

  /// Fortlaufende Nummer wie in Spalte A ("lfd Nr.").
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
