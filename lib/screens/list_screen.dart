import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/log_entry.dart';
import '../services/active_list_service.dart';
import '../services/db_service.dart';
import '../services/onedrive_sync_service.dart';
import '../services/volume_calculator.dart';
import 'entry_screen.dart';

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

class ListScreen extends StatefulWidget {
  const ListScreen({super.key});

  @override
  State<ListScreen> createState() => ListScreenState();
}

class ListScreenState extends State<ListScreen> {
  List<LogEntry> _entries = [];
  List<ListInfo> _lists = [];
  final Set<String> _selected = {};
  String? _loadedListId;

  bool get _selectionMode => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    ActiveListService.instance.active.addListener(reload);
    ActiveListService.instance.ensureInit();
    reload();
  }

  @override
  void dispose() {
    ActiveListService.instance.active.removeListener(reload);
    super.dispose();
  }

  Future<void> reload() async {
    final active = ActiveListService.instance.active.value;
    final lists = await DbService.instance.lists();
    final entries = active == null
        ? <LogEntry>[]
        : await DbService.instance.all(active.id);
    if (!mounted) return;
    setState(() {
      _lists = lists;
      _entries = entries;
      // Beim Listenwechsel Markierung zuruecksetzen, sonst nur
      // Markierungen entfernen, die es nicht mehr gibt.
      if (_loadedListId != active?.id) _selected.clear();
      _loadedListId = active?.id;
      final ids = entries.map((e) => e.id).toSet();
      _selected.removeWhere((id) => !ids.contains(id));
    });
  }

  void _triggerSync() {
    OneDriveSyncService.instance.trySync().catchError((_) => false);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _toggle(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  // ---------------------------------------------------------------- Listen

  Future<void> _createList() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Neue Liste anlegen'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Name der Liste',
            hintText: 'z. B. Rückegasse Nord',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Anlegen'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;
    await ActiveListService.instance.createAndSelect(name);
    await reload();
    _snack('Liste "$name" angelegt');
  }

  // ------------------------------------------------- Aktionen auf Auswahl

  List<String> _selectedIdsInOrder() =>
      _entries.where((e) => _selected.contains(e.id)).map((e) => e.id).toList();

  Future<void> _deleteSelected() async {
    final active = ActiveListService.instance.active.value;
    if (active == null || _selected.isEmpty) return;
    final count = _selected.length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(count == 1 ? 'Stamm löschen?' : '$count Stämme löschen?'),
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

    await DbService.instance.deleteEntries(active.id, _selectedIdsInOrder());
    _selected.clear();
    await reload();
    _triggerSync();
    _snack(count == 1 ? 'Stamm gelöscht' : '$count Stämme gelöscht');
  }

  /// Verschiebt die markierten Stämme um eine Position (-1 = nach oben,
  /// +1 = nach unten). Markierte Stämme bleiben dabei als Block zusammen.
  Future<void> _moveSelected(int delta) async {
    final active = ActiveListService.instance.active.value;
    if (active == null || _selected.isEmpty) return;

    final ids = _entries.map((e) => e.id).toList();
    void swap(int a, int b) {
      final t = ids[a];
      ids[a] = ids[b];
      ids[b] = t;
    }

    if (delta < 0) {
      for (var i = 1; i < ids.length; i++) {
        if (_selected.contains(ids[i]) && !_selected.contains(ids[i - 1])) {
          swap(i, i - 1);
        }
      }
    } else {
      for (var i = ids.length - 2; i >= 0; i--) {
        if (_selected.contains(ids[i]) && !_selected.contains(ids[i + 1])) {
          swap(i, i + 1);
        }
      }
    }

    await DbService.instance.applyOrder(active.id, ids);
    await reload();
    _triggerSync();
  }

  Future<void> _moveToPosition() async {
    final active = ActiveListService.instance.active.value;
    if (active == null || _selected.isEmpty) return;

    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Auf Position verschieben'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'Neue Nummer (1 bis ${_entries.length})',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Verschieben'),
          ),
        ],
      ),
    );

    final target = int.tryParse(text ?? '');
    if (target == null) return;

    // Markierte Stämme (in ihrer bisherigen Reihenfolge) als Block so
    // einfügen, dass der erste markierte Stamm auf der Zielnummer landet.
    final moving = _selectedIdsInOrder();
    final rest = _entries
        .where((e) => !_selected.contains(e.id))
        .map((e) => e.id)
        .toList();
    var index = target - 1;
    if (index < 0) index = 0;
    if (index > rest.length) index = rest.length;
    rest.insertAll(index, moving);

    await DbService.instance.applyOrder(active.id, rest);
    await reload();
    _triggerSync();
  }

  Future<void> _moveToOtherList() async {
    final active = ActiveListService.instance.active.value;
    if (active == null || _selected.isEmpty) return;

    final others = _lists.where((l) => l.id != active.id).toList();
    if (others.isEmpty) {
      _snack('Lege zuerst über das Symbol oben rechts eine weitere Liste an.');
      return;
    }

    final target = await showDialog<ListInfo>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('In welche Liste verschieben?'),
        children: others
            .map(
              (l) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, l),
                child: Text(l.name, style: const TextStyle(fontSize: 17)),
              ),
            )
            .toList(),
      ),
    );
    if (target == null) return;

    final count = _selected.length;
    await DbService.instance.moveToList(
      _selectedIdsInOrder(),
      active.id,
      target.id,
    );
    _selected.clear();
    await reload();
    _triggerSync();
    _snack(
      count == 1
          ? 'Stamm nach "${target.name}" verschoben'
          : '$count Stämme nach "${target.name}" verschoben',
    );
  }

  void _edit(LogEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EntryScreen(existing: entry, onSaved: reload),
      ),
    );
  }

  // -------------------------------------------------------------------- UI

  Widget _buildHeader() {
    final activeId = ActiveListService.instance.active.value?.id;
    final value = _lists.any((l) => l.id == activeId) ? activeId : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              value: value,
              underline: const SizedBox.shrink(),
              items: _lists
                  .map(
                    (l) => DropdownMenuItem<String>(
                      value: l.id,
                      child: Text(
                        l.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (id) {
                if (id == null) return;
                final selected = _lists.firstWhere((l) => l.id == id);
                ActiveListService.instance.select(selected);
              },
            ),
          ),
          IconButton(
            tooltip: 'Neue Liste anlegen',
            icon: const Icon(Icons.playlist_add, size: 30),
            onPressed: _createList,
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionBar() {
    return Container(
      color: Theme.of(context).colorScheme.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Markierung beenden',
            icon: const Icon(Icons.close),
            onPressed: () => setState(_selected.clear),
          ),
          Expanded(
            child: Text(
              '${_selected.length} markiert',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            tooltip: 'Nach oben',
            icon: const Icon(Icons.arrow_upward),
            onPressed: () => _moveSelected(-1),
          ),
          IconButton(
            tooltip: 'Nach unten',
            icon: const Icon(Icons.arrow_downward),
            onPressed: () => _moveSelected(1),
          ),
          IconButton(
            tooltip: 'Löschen',
            icon: const Icon(Icons.delete_outline),
            onPressed: _deleteSelected,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'all') {
                setState(() => _selected.addAll(_entries.map((e) => e.id)));
              } else if (v == 'pos') {
                _moveToPosition();
              } else if (v == 'list') {
                _moveToOtherList();
              }
            },
            itemBuilder: (context) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'all',
                child: Text('Alle markieren'),
              ),
              PopupMenuItem<String>(
                value: 'pos',
                child: Text('Auf Position verschieben …'),
              ),
              PopupMenuItem<String>(
                value: 'list',
                child: Text('In andere Liste verschieben …'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Noch keine Einträge in dieser Liste.\nWechsle zu "Erfassung", um den ersten Stamm zu erfassen.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      ),
    );
  }

  Widget _buildList() {
    final theme = Theme.of(context);
    return ListView.builder(
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
          key: ValueKey(e.id),
          selected: isSel,
          selectedTileColor: theme.colorScheme.primaryContainer,
          onTap: () {
            if (_selectionMode) {
              _toggle(e.id);
            } else {
              _edit(e);
            }
          },
          onLongPress: () => _toggle(e.id),
          leading: CircleAvatar(
            child: isSel ? const Icon(Icons.check) : Text('${e.lfdNr}'),
          ),
          title: Text(
            '${baumartenAnzeige[e.baumart]} · ${_num(e.laenge, 1)} m · ${_num(e.durchmesser, 0)} cm',
          ),
          subtitle: Text(
            'Stk.-Klasse $sk · ${e.rinde}'
            '${e.kommentar.isNotEmpty ? ' · ${e.kommentar}' : ''}'
            '${e.latitude != null ? ' · GPS erfasst' : ''}',
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
              Icon(
                e.synced ? Icons.cloud_done : Icons.cloud_queue,
                size: 16,
                color: e.synced ? Colors.green : Colors.orange,
              ),
            ],
          ),
        );
      },
    );
  }

  /// Zeigt die Summe aller Stämme - oder nur der markierten, sobald
  /// mindestens ein Stamm markiert ist.
  Widget _buildFooter() {
    final selMode = _selectionMode;
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
    return Column(
      children: [
        _selectionMode ? _buildSelectionBar() : _buildHeader(),
        const Divider(height: 1),
        Expanded(child: _entries.isEmpty ? _buildEmpty() : _buildList()),
        if (_entries.isNotEmpty) _buildFooter(),
      ],
    );
  }
}
