import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../models/log_entry.dart';
import '../services/db_service.dart';
import '../services/onedrive_sync_service.dart';
import '../services/settings_service.dart';

class EntryScreen extends StatefulWidget {
  /// Wenn gesetzt, wird ein bestehender Eintrag bearbeitet statt
  /// einen neuen anzulegen.
  final LogEntry? existing;
  final VoidCallback onSaved;

  const EntryScreen({super.key, this.existing, required this.onSaved});

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  final _laengeCtrl = TextEditingController();
  final _durchmesserCtrl = TextEditingController();
  final _kommentarCtrl = TextEditingController();

  String _baumart = baumartenListe.first;
  String _rinde = rindeListe.first;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _baumart = e.baumart;
      _rinde = e.rinde;
      _laengeCtrl.text = _fmt(e.laenge);
      _durchmesserCtrl.text = _fmt(e.durchmesser);
      _kommentarCtrl.text = e.kommentar;
    }
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _laengeCtrl.dispose();
    _durchmesserCtrl.dispose();
    _kommentarCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final laenge = double.tryParse(_laengeCtrl.text.replaceAll(',', '.'));
    final durchmesser =
        double.tryParse(_durchmesserCtrl.text.replaceAll(',', '.'));

    if (laenge == null || laenge <= 0) {
      _showError('Bitte eine gueltige Laenge eingeben.');
      return;
    }
    if (durchmesser == null || durchmesser <= 0) {
      _showError('Bitte einen gueltigen Durchmesser eingeben.');
      return;
    }

    setState(() => _saving = true);

    double? lat;
    double? lng;
    if (await SettingsService.instance.gpsEnabled) {
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 8),
        );

        lat = pos.latitude;
        lng = pos.longitude;
      } catch (_) {
        // GPS optional - Speichern klappt auch ohne Standort weiter.
      }
    }

    final now = DateTime.now();
    final entry = widget.existing != null
        ? widget.existing!.copyWith(
            baumart: _baumart,
            laenge: laenge,
            durchmesser: durchmesser,
            rinde: _rinde,
            kommentar: _kommentarCtrl.text.trim(),
            latitude: lat ?? widget.existing!.latitude,
            longitude: lng ?? widget.existing!.longitude,
            updatedAt: now,
            synced: false, // Korrektur muss erneut synchronisiert werden
          )
        : LogEntry(
            id: const Uuid().v4(),
            lfdNr: await DbService.instance.nextLfdNr(),
            baumart: _baumart,
            laenge: laenge,
            durchmesser: durchmesser,
            rinde: _rinde,
            kommentar: _kommentarCtrl.text.trim(),
            latitude: lat,
            longitude: lng,
            createdAt: now,
            updatedAt: now,
          );

    await DbService.instance.upsert(entry);
    // Sync-Versuch im Hintergrund - blockiert die Eingabe nicht.
    unawaited(OneDriveSyncService.instance.trySync());

    if (!mounted) return;
    setState(() => _saving = false);

    if (widget.existing != null) {
      Navigator.of(context).pop();
    } else {
      _laengeCtrl.clear();
      _durchmesserCtrl.clear();
      _kommentarCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Eintrag gespeichert'), duration: Duration(seconds: 1)),
      );
    }
    widget.onSaved();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      appBar: isEdit ? AppBar(title: const Text('Eintrag korrigieren')) : null,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Baumart', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _BaumartAuswahl(
              selected: _baumart,
              onSelect: (v) => setState(() => _baumart = v),
            ),
            const SizedBox(height: 24),

            _GrossesZahlenfeld(
              label: 'Laenge [m]',
              controller: _laengeCtrl,
            ),
            const SizedBox(height: 16),
            _GrossesZahlenfeld(
              label: 'Durchmesser [cm]',
              controller: _durchmesserCtrl,
            ),
            const SizedBox(height: 24),

            const Text('Rinde', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: rindeListe
                  .map((r) => ButtonSegment(value: r, label: Text(r)))
                  .toList(),
              selected: {_rinde},
              onSelectionChanged: (s) => setState(() => _rinde = s.first),
              style: const ButtonStyle(
                visualDensity: VisualDensity(horizontal: 2, vertical: 2),
              ),
            ),
            const SizedBox(height: 24),

            TextField(
              controller: _kommentarCtrl,
              decoration: const InputDecoration(
                labelText: 'Kommentar (optional)',
                border: OutlineInputBorder(),
              ),
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: 32),

            SizedBox(
              height: 64,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check, size: 28),
                label: Text(
                  isEdit ? 'Aenderung speichern' : 'Speichern & naechster Stamm',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BaumartAuswahl extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _BaumartAuswahl({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: baumartenListe.map((art) {
        final isSelected = art == selected;
        return ChoiceChip(
          label: Text(
            baumartenAnzeige[art]!,
            style: const TextStyle(fontSize: 16),
          ),
          selected: isSelected,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          onSelected: (_) {
            HapticFeedback.selectionClick();
            onSelect(art);
          },
        );
      }).toList(),
    );
  }
}

class _GrossesZahlenfeld extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  const _GrossesZahlenfeld({required this.label, required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
      ],
      style: const TextStyle(fontSize: 28),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      ),
    );
  }
}

// kleine Hilfsfunktion, damit unawaited(...) ohne extra Paket funktioniert
void unawaited(Future<void> future) {}
