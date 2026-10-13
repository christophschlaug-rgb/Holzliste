import 'dart:math' as math;

/// Repliziert 1:1 die Formeln aus dem Tabellenblatt "Holzliste"
/// der Original-Excel (Spalten F, G, H). Bei jeder Aenderung an der
/// Excel-Vorlage muss dieser Rechner mit aktualisiert werden.
class VolumeCalculator {
  /// Volumen in Festmetern [fm], Mittenschnittformel mit
  /// baumart- und durchmesserabhaengigem Rindenabzug.
  static double volumeFm({
    required String baumart,
    required double laengeM,
    required double durchmesserCm,
    required String rinde,
  }) {
    final bool ohneRinde = rinde == 'ohne Rinde';
    final double d = durchmesserCm;
    final double l = laengeM;
    const double faktor = math.pi / 4;

    double dKorrCm;

    switch (baumart) {
      case 'Fichte':
        if (ohneRinde) {
          dKorrCm = d;
        } else if (d < 27) {
          dKorrCm = d - 1;
        } else if (d < 51) {
          dKorrCm = d - 2;
        } else {
          dKorrCm = d - 3;
        }
        break;

      case 'Buche':
      case 'Birke':
        if (ohneRinde) {
          dKorrCm = d;
        } else if (d < 41) {
          dKorrCm = d - 1;
        } else {
          dKorrCm = d - 2;
        }
        break;

      case 'Eiche':
      case 'Laerche':
        if (ohneRinde) {
          dKorrCm = d;
        } else if (d < 21) {
          dKorrCm = d - 1;
        } else if (d < 32) {
          dKorrCm = d - 2;
        } else if (d < 43) {
          dKorrCm = d - 3;
        } else if (d < 54) {
          dKorrCm = d - 4;
        } else {
          dKorrCm = d - 5;
        }
        break;

      case 'Kiefer':
        if (ohneRinde) {
          dKorrCm = d;
        } else if (d < 21) {
          dKorrCm = d - 1;
        } else if (d < 37) {
          dKorrCm = d - 2;
        } else if (d < 63) {
          dKorrCm = d - 3;
        } else {
          dKorrCm = d - 4;
        }
        break;

      default:
        return 0;
    }

    final double dKorrM = dKorrCm / 100;
    return faktor * dKorrM * dKorrM * l;
  }

  /// Staerkeklasse nach Durchmesser, unabhaengig von der Baumart.
  static String staerkeklasse(double durchmesserCm) {
    final d = durchmesserCm;
    if (d < 10) return '0';
    if (d < 15) return '1a';
    if (d < 20) return '1b';
    if (d < 25) return '2a';
    if (d < 30) return '2b';
    if (d < 35) return '3a';
    if (d < 40) return '3b';
    if (d < 50) return '4';
    if (d < 60) return '5';
    if (d < 70) return '6';
    if (d < 80) return '7';
    return '8';
  }

  /// Volumen in Raummetern [rm] = Festmeter * 1,4 (wie in Spalte H).
  static double volumeRm(double volumeFm) => volumeFm * 1.4;
}
