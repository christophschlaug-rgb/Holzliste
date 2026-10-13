import 'package:flutter/material.dart';

import '../services/onedrive_auth_service.dart';
import '../services/onedrive_sync_service.dart';
import '../services/secure_storage_service.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _connected = false;
  bool _gps = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final connected = await SecureStorageService.instance.isOneDriveConnected;
    final gps = await SettingsService.instance.gpsEnabled;
    if (!mounted) return;
    setState(() {
      _connected = connected;
      _gps = gps;
    });
  }

  Future<void> _toggleOneDrive() async {
    setState(() => _busy = true);
    try {
      if (_connected) {
        await OneDriveAuthService.instance.signOut();
      } else {
        if (!OneDriveAuthService.instance.isConfigured) {
          _showError(
            'Diese App wurde ohne OneDrive-Konfiguration gebaut. '
            'Siehe README.md, Abschnitt "Azure-App-Registrierung".',
          );
          return;
        }
        final ok = await OneDriveAuthService.instance.signIn();
        if (!ok) {
          _showError('Anmeldung wurde abgebrochen oder ist fehlgeschlagen.');
        }
      }
    } catch (e) {
      _showError('Fehler: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final sync = OneDriveSyncService.instance;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: Icon(
              _connected ? Icons.cloud_done : Icons.cloud_off,
              color: _connected ? Colors.green : Colors.grey,
            ),
            title: Text(_connected ? 'Mit OneDrive verbunden' : 'Nicht verbunden'),
            subtitle: const Text('Persönliches Microsoft-Konto'),
            trailing: _busy
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : FilledButton(
                    onPressed: _toggleOneDrive,
                    child: Text(_connected ? 'Trennen' : 'Verbinden'),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Standort (GPS) erfassen', style: TextStyle(fontSize: 16)),
                      Text(
                        'Speichert die Position bei jedem neuen Stamm mit.',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _gps,
                  onChanged: (v) async {
                    await SettingsService.instance.setGpsEnabled(v);
                    setState(() => _gps = v);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Icon(_syncIcon(sync.status)),
            title: Text(_syncText(sync)),
            trailing: IconButton(
              icon: const Icon(Icons.sync),
              onPressed: () async {
                await sync.trySync();
                setState(() {});
              },
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Alle Daten werden zunächst lokal und verschlüsselt auf dem Gerät '
            'gespeichert. Sobald WLAN verfügbar ist, werden offene Einträge '
            'automatisch mit OneDrive abgeglichen.',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  IconData _syncIcon(SyncStatus s) {
    switch (s) {
      case SyncStatus.ok:
        return Icons.check_circle;
      case SyncStatus.syncing:
        return Icons.sync;
      case SyncStatus.waitingForWifi:
        return Icons.wifi_off;
      case SyncStatus.error:
        return Icons.error;
      case SyncStatus.idle:
        return Icons.hourglass_empty;
    }
  }

  String _syncText(OneDriveSyncService sync) {
    switch (sync.status) {
      case SyncStatus.ok:
        return 'Alles synchronisiert';
      case SyncStatus.syncing:
        return 'Synchronisiere...';
      case SyncStatus.waitingForWifi:
        return '${sync.pendingCount} Eintrag/Einträge warten auf WLAN';
      case SyncStatus.error:
        return 'Fehler: ${sync.lastError ?? "unbekannt"}';
      case SyncStatus.idle:
        return 'Noch nicht synchronisiert';
    }
  }
}
