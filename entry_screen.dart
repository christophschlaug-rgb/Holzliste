import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../models/log_entry.dart';
import '../services/active_list_service.dart';
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
    ActiveListService.instance.ensureInit();
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

  /// Holt den Standort, falls in den Einstellungen aktiviert. Fragt beim
  /// ersten Mal die Android-Berechtigung ab. Scheitert still, damit das
  /// Speichern auch ohne GPS-Empfang (z. B. im dichten Bestand) klappt.
  Future<Position?> _readPosition() async {
    if (!await SettingsService.instance.gpsEnabled) return null;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 6),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    final laenge = double.tryParse(_laengeCtrl.text.replaceAll(',', '.'));
    final durchmesser =
        double.tryParse(_durchmesserCtrl.text.replaceAll(',', '.'));

    if (laenge == null || laenge <= 0) {
      _showError('Bitte eine gültige Länge eingeben.');
      return;
    }
    if (durchmesser == null || durchmesser <= 0) {
      _showError('Bitte einen gültigen Durchmesser eingeben.');
      return;
    }

    await ActiveListService.instance.ensureInit();
    final activeList = ActiveListService.instance.active.value;
    if (activeList == null) {
      _showError('Es ist keine Liste ausgewählt.');
      return;
    }

    setState(() => _saving = true);

    final pos = await _readPosition();
    final lat = pos?.latitude;
    final lng = pos?.longitude;

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
            listId: activeList.id,
            lfdNr: await DbService.instance.nextLfdNr(activeList.id),
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
    OneDriveSyncService.instance.trySync().catchError((_) => false);

    if (!mounted) return;
    setState(() => _saving = false);

    if (widget.existing != null) {
      Navigator.of(context).pop();
    } else {
      _laengeCtrl.clear();
      _durchmesserCtrl.clear();
      _kommentarCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Eintrag gespeichert'),
          duration: Duration(seconds: 1),
        ),
      );
    }
    widget.onSaved();
  }

  Future<void> _confirmAndDelete() async {
    final existing = widget.existing;
    if (existing == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Stamm Nr. ${existing.lfdNr} löschen?'),
        content: const Text(
          'Die Nummern der übrigen Stämme werden neu durchgezählt. '
          'Das lässt sich nicht rückgängig machen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await DbService.instance.deleteEntries(existing.listId, [existing.id]);
    OneDriveSyncService.instance.trySync().catchError((_) => false);

    if (!mounted) return;
    Navigator.of(context).pop();
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
            ValueListenableBuilder<ListInfo?>(
              valueListenable: ActiveListService.instance.active,
              builder: (context, list, _) => Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  avatar: const Icon(Icons.folder_open, size: 18),
                  label: Text('Liste: ${list?.name ?? '–'}'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Baumart',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _BaumartAuswahl(
              selected: _baumart,
              onSelect: (v) => setState(() => _baumart = v),
            ),
            const SizedBox(height: 24),
            _GrossesZahlenfeld(
              label: 'Länge [m]',
              controller: _laengeCtrl,
            ),
            const SizedBox(height: 16),
            _GrossesZahlenfeld(
              label: 'Durchmesser [cm]',
              controller: _durchmesserCtrl,
            ),
            const SizedBox(height: 24),
            const Text(
              'Rinde',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
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
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check, size: 28),
                label: Text(
                  isEdit ? 'Änderung speichern' : 'Speichern & nächster Stamm',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ),
            if (isEdit) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _saving ? null : _confirmAndDelete,
                icon: const Icon(Icons.delete_outline),
                label: const Text(
                  'Stamm löschen',
                  style: TextStyle(fontSize: 18),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  minimumSize: const Size.fromHeight(56),
                ),
              ),
            ],
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      ),
    );
  }
}
