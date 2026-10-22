import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Alle sicherheitskritischen Werte (DB-Schluessel, OneDrive-Tokens)
/// landen ausschliesslich hier - verschluesselt im Android Keystore,
/// nie in SharedPreferences oder Klartextdateien.
class SecureStorageService {
  SecureStorageService._();
  static final SecureStorageService instance = SecureStorageService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      // erzwingt den Android EncryptedSharedPreferences-Mechanismus
      // (Schluessel liegt im Android Keystore, nicht in der App selbst)
      encryptedSharedPreferences: true,
    ),
  );

  static const _dbKeyKey = 'db_encryption_key';
  static const _accessTokenKey = 'onedrive_access_token';
  static const _refreshTokenKey = 'onedrive_refresh_token';
  static const _tokenExpiryKey = 'onedrive_token_expiry';

  Future<String>? _dbKeyFuture;

  /// Liefert den Datenbank-Schluessel. Gleichzeitige Aufrufe teilen sich
  /// dasselbe Ergebnis, damit beim allerersten Start nie zwei verschiedene
  /// Schluessel entstehen. Existiert schon eine Datenbank, wird NIE ein
  /// neuer Schluessel erzeugt (allowCreate = false), sondern ein Fehler
  /// gemeldet - ein neuer Schluessel koennte die alten Daten nicht oeffnen.
  Future<String> getOrCreateDbKey({required bool allowCreate}) {
    return _dbKeyFuture ??=
        _loadOrCreateDbKey(allowCreate).catchError((Object e) {
      _dbKeyFuture = null;
      throw e;
    });
  }

  Future<String> _loadOrCreateDbKey(bool allowCreate) async {
    final existing = await _storage.read(key: _dbKeyKey);
    if (existing != null) return existing;

    if (!allowCreate) {
      throw StateError(
        'Der Schlüssel der lokalen Datenbank fehlt im Android-Schlüsselspeicher.',
      );
    }

    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final key = base64UrlEncode(bytes);
    await _storage.write(key: _dbKeyKey, value: key);
    return key;
  }

  Future<void> saveTokens({
    required String accessToken,
    required String? refreshToken,
    required DateTime expiry,
  }) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    if (refreshToken != null) {
      await _storage.write(key: _refreshTokenKey, value: refreshToken);
    }
    await _storage.write(
      key: _tokenExpiryKey,
      value: expiry.toIso8601String(),
    );
  }

  Future<String?> get accessToken => _storage.read(key: _accessTokenKey);
  Future<String?> get refreshToken => _storage.read(key: _refreshTokenKey);

  Future<DateTime?> get tokenExpiry async {
    final v = await _storage.read(key: _tokenExpiryKey);
    return v == null ? null : DateTime.tryParse(v);
  }

  Future<void> clearOneDriveTokens() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _tokenExpiryKey);
  }

  Future<bool> get isOneDriveConnected async =>
      (await accessToken) != null || (await refreshToken) != null;
}
