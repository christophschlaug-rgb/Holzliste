import 'package:flutter/material.dart';

import 'screens/entry_screen.dart';
import 'screens/list_screen.dart';
import 'screens/settings_screen.dart';
import 'services/onedrive_sync_service.dart';

void main() {
  runApp(const HolzlisteApp());
}

class HolzlisteApp extends StatelessWidget {
  const HolzlisteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Holzliste',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E5A38), // Waldgrün
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E5A38),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _listKey = GlobalKey<ListScreenState>();

  @override
  void initState() {
    super.initState();
    // Beim Start einmal versuchen zu synchronisieren, falls WLAN da ist.
    OneDriveSyncService.instance.trySync();
  }

  void _onEntrySaved() {
    _listKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      EntryScreen(onSaved: _onEntrySaved),
      ListScreen(key: _listKey),
      const SettingsScreen(),
    ];
    final titles = ['Erfassung', 'Liste', 'Einstellungen'];

    return Scaffold(
      appBar: AppBar(title: Text(titles[_index])),
      body: IndexedStack(
        index: _index,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          setState(() => _index = i);
          if (i == 1) _listKey.currentState?.reload();
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.add_box), label: 'Erfassung'),
          NavigationDestination(icon: Icon(Icons.list), label: 'Liste'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Einstellungen'),
        ],
      ),
    );
  }
}
