import 'package:shared_preferences/shared_preferences.dart';

/// Unkritische App-Einstellungen (keine Zugangsdaten!).
/// Zugangsdaten liegen ausschliesslich in SecureStorageService.
class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  static const _gpsKey = 'gps_enabled';

  Future<bool> get gpsEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_gpsKey) ?? false;
  }

  Future<void> setGpsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_gpsKey, value);
  }
}
