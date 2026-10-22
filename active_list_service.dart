import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/log_entry.dart';
import 'db_service.dart';

/// Merkt sich, in welche Liste gerade erfasst wird. Erfassung und Liste
/// greifen beide darauf zu, damit sie immer dieselbe Liste zeigen.
class ActiveListService {
  ActiveListService._();
  static final ActiveListService instance = ActiveListService._();

  static const _key = 'active_list_id';

  final ValueNotifier<ListInfo?> active = ValueNotifier<ListInfo?>(null);

  Future<void>? _initFuture;

  /// Laedt die zuletzt genutzte Liste (einmalig, danach sofort fertig).
  Future<void> ensureInit() {
    return _initFuture ??= _init().catchError((Object e) {
      _initFuture = null;
      throw e;
    });
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_key);
    final all = await DbService.instance.lists();

    ListInfo? selected;
    for (final l in all) {
      if (l.id == savedId) selected = l;
    }
    selected ??= all.isNotEmpty ? all.first : null;
    active.value = selected;
  }

  Future<void> select(ListInfo list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, list.id);
    active.value = list;
  }

  Future<ListInfo> createAndSelect(String name) async {
    final info = await DbService.instance.createList(name);
    await select(info);
    return info;
  }
}
