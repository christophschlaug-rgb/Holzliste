import 'package:flutter/material.dart';

import '../models/log_entry.dart';
import '../services/db_service.dart';
import '../services/volume_calculator.dart';

/// Zahl mit deutschem Dezimalkomma.
String _num(double v, int digits) =>
    v.toStringAsFixed(digits).replaceAll('.', ',');

double _sumFm(Iterable<LogEntry> entries) {
  double sum = 0;
  for (final e in entries) {
    sum += VolumeCalculator.volumeFm(
      baumart: e.baumart,
      laengeM: e.laenge,
      durchmesserCm: e.durchmesser,
      rinde: e.rinde,
    );
  }
  return sum;
}

class _ClosedInfo {
  final ListInfo list;
  final int count;
  final double fm;
  const _ClosedInfo(this.list, this.count, this.fm);
}

/// Übersicht aller abgeschlossenen Listen.
class ClosedListsScreen extends StatefulWidget {
  const ClosedListsScreen({super.key});

  @override
  State<ClosedListsScreen> createState() => _ClosedListsScreenState();
}

class _ClosedListsScreenState extends State<ClosedListsScreen> {
  List<_ClosedInfo> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await DbService.instance.lists();
      final items = <_ClosedInfo>[];
      for (final l in all.where((l) => l.closed)) {
        final entries = await DbService.instance.all(l.id);
        items.add(_ClosedInfo(l, entries.length, _sumFm(entries)));
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _reopen(ListInfo list) async {
    await DbService.instance.setListClosed(list.id, false);
    await _load();
    _snack('Liste "${list.name}" ist wieder geöffnet.');
  }

  Future<void> _delete(_ClosedInfo item) async {
    final unsynced =
        await DbService.instance.countUnsyncedEntries(item.list.id);
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Liste "${item.list.name}" endgültig löschen?'),
        content: Text(
          'Alle ${item.count} Stämme dieser Liste werden von diesem Handy '
          'gelöscht. Die Excel-Datei "${item.list.fileName}" in OneDrive '
          'bleibt erhalten.'
          '${unsynced > 0 ? '\n\nAchtung: $unsynced Stämme sind noch nicht in OneDrive gespeichert und gehen verloren.' : ''}',
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

    await DbService.instance.deleteList(item.list.id);
    await _load();
    _snack('Liste "${item.list.name}" gelöscht.');
  }

  Future<void> _openDetail(_ClosedInfo item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClosedListDetailScreen(list: item.list),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Fehler beim Laden: $_error'),
      );
    } else if (_items.isEmpty) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Noch keine abgeschlossenen Listen.\nÜber das Menü im Listen-Tab kannst du eine Liste abschließen.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
    } else {
      body = ListView.builder(
        itemCount: _items.length,
        itemBuilder: (context, i) {
          final item = _items[i];
          final rm = VolumeCalculator.volumeRm(item.fm);
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.lock_outline)),
            title: Text(item.list.name),
            subtitle: Text(
              '${item.count} Stämme · ${_num(item.fm, 3)} fm · ${_num(rm, 3)} rm',
            ),
            onTap: () => _openDetail(item),
            trailing: PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'open') {
                  _reopen(item.list);
                } else if (v == 'delete') {
                  _delete(item);
                }
              },
              itemBuilder: (context) => const <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'open',
                  child: Text('Wieder öffnen'),
                ),
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Text('Endgültig löschen …'),
                ),
              ],
            ),
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Abgeschlossene Listen')),
      body: body,
    );
  }
}

/// Nur-Lesen-Ansicht einer abgeschlossenen Liste. Stämme lassen sich
/// markieren, um Teilsummen zu sehen; geändert werden kann nichts.
class ClosedListDetailScreen extends StatefulWidget {
  final ListInfo list;
  const ClosedListDetailScreen({super.key, required this.list});

  @override
  State<ClosedListDetailScreen> createState() => _ClosedListDetailScreenState();
}

class _ClosedListDetailScreenState extends State<ClosedListDetailScreen> {
  List<LogEntry> _entries = [];
  final Set<String> _selected = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final entries = await DbService.instance.all(widget.list.id);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _reopen() async {
    await DbService.instance.setListClosed(widget.list.id, false);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _toggle(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  Widget _buildFooter() {
    final selMode = _selected.isNotEmpty;
    final subset = selMode
        ? _entries.where((e) => _selected.contains(e.id)).toList()
        : _entries;
    final sumFm = _sumFm(subset);
    final sumRm = VolumeCalculator.volumeRm(sumFm);
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        color: selMode ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              selMode
                  ? 'Markiert: ${subset.length} von ${_entries.length}'
                  : '${_entries.length} Stamm/Stämme',
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Summe: ${_num(sumFm, 3)} fm',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  '${_num(sumRm, 3)} rm',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(widget.list.name)),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: theme.colorScheme.secondaryContainer,
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
            child: Row(
              children: [
                const Icon(Icons.lock_outline, size: 20),
                const SizedBox(width: 8),
                const Expanded(child: Text('Abgeschlossen – nur lesen')),
                TextButton(
                  onPressed: _reopen,
                  child: const Text('Wieder öffnen'),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Fehler beim Laden: $_error'),
            ),
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
                final rm = VolumeCalculator.volumeRm(fm);
                final sk = VolumeCalculator.staerkeklasse(e.durchmesser);
                final isSel = _selected.contains(e.id);

                return ListTile(
                  selected: isSel,
                  selectedTileColor: theme.colorScheme.primaryContainer,
                  onTap: () => _toggle(e.id),
                  leading: CircleAvatar(
                    child: isSel ? const Icon(Icons.check) : Text('${e.lfdNr}'),
                  ),
                  title: Text(
                    '${baumartenAnzeige[e.baumart]} · ${_num(e.laenge, 1)} m · ${_num(e.durchmesser, 0)} cm',
                  ),
                  subtitle: Text(
                    'Stk.-Klasse $sk · ${e.rinde}'
                    '${e.kommentar.isNotEmpty ? ' · ${e.kommentar}' : ''}',
                  ),
                  trailing: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${_num(fm, 3)} fm',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${_num(rm, 3)} rm',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (_entries.isNotEmpty) _buildFooter(),
        ],
      ),
    );
  }
}
