import 'package:flutter/material.dart';

import '../models/log_entry.dart';
import '../services/db_service.dart';
import '../services/onedrive_sync_service.dart';
import '../services/volume_calculator.dart';
import 'entry_screen.dart';

class ListScreen extends StatefulWidget {
  const ListScreen({super.key});

  @override
  State<ListScreen> createState() => ListScreenState();
}

class ListScreenState extends State<ListScreen> {
  List<LogEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    final entries = await DbService.instance.all();
    if (!mounted) return;
    setState(() => _entries = entries);
  }

  Future<void> _delete(LogEntry entry) async {
    await DbService.instance.delete(entry.id);
    await reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Eintrag Nr. ${entry.lfdNr} geloescht'),
        action: SnackBarAction(
          label: 'Rueckgaengig',
          onPressed: () async {
            await DbService.instance.upsert(entry.copyWith(synced: false));
            await reload();
          },
        ),
      ),
    );
  }

  void _edit(LogEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EntryScreen(existing: entry, onSaved: reload),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_entries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Noch keine Eintraege.\nWechsle zu "Erfassung", um den ersten Stamm zu erfassen.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
    }

    double sumFm = 0;
    for (final e in _entries) {
      sumFm += VolumeCalculator.volumeFm(
        baumart: e.baumart,
        laengeM: e.laenge,
        durchmesserCm: e.durchmesser,
        rinde: e.rinde,
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: _entries.length,
            itemBuilder: (context, i) {
              final e = _entries[i];
              final fm = VolumeCalculator.volumeFm(
                baumart: e.baumart,
                laengeM: e.laenge,
                durchmesserCm: e.durchmesser,
                rinde: e.rinde,
              );
              final sk = VolumeCalculator.staerkeklasse(e.durchmesser);

              return Dismissible(
                key: ValueKey(e.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (_) => _delete(e),
                child: ListTile(
                  onTap: () => _edit(e),
                  leading: CircleAvatar(child: Text('${e.lfdNr}')),
                  title: Text(
                    '${baumartenAnzeige[e.baumart]} · ${e.laenge.toStringAsFixed(1)} m · ${e.durchmesser.toStringAsFixed(0)} cm',
                  ),
                  subtitle: Text(
                    'Stk.-Klasse $sk · ${e.rinde}'
                    '${e.kommentar.isNotEmpty ? ' · ${e.kommentar}' : ''}'
                    '${e.latitude != null ? ' · GPS erfasst' : ''}',
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${fm.toStringAsFixed(3)} fm'),
                      Icon(
                        e.synced ? Icons.cloud_done : Icons.cloud_queue,
                        size: 16,
                        color: e.synced ? Colors.green : Colors.orange,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${_entries.length} Stamm/Stämme'),
                Text(
                  'Summe: ${sumFm.toStringAsFixed(3)} fm',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// erneuter Export, damit main.dart bei Tab-Wechsel den Sync anstossen kann
Future<void> triggerBackgroundSync() async {
  await OneDriveSyncService.instance.trySync();
}
