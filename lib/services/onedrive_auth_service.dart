import 'package:flutter_appauth/flutter_appauth.dart';

import 'secure_storage_service.dart';

/// Authentifizierung gegen Microsoft Graph fuer private OneDrive-Konten.
///
/// WICHTIG: Es wird bewusst kein Client-Secret verwendet. Native/mobile
/// Apps gelten als "public clients" - ein Secret liesse sich aus einer
/// verteilten APK ohnehin auslesen und waere ein Sicherheitsrisiko.
/// Stattdessen kommt der PKCE-Flow zum Einsatz (RFC 7636), den
/// flutter_appauth automatisch anwendet.
///
/// Die Client-ID stammt NICHT aus dem Quellcode, sondern wird beim Bau
/// der App als --dart-define uebergeben (siehe .github/workflows und
/// README.md). Damit landet sie nicht fest im Repository.
class OneDriveAuthService {
  OneDriveAuthService._();
  static final OneDriveAuthService instance = OneDriveAuthService._();

  static const String _clientId = String.fromEnvironment(
    'ONEDRIVE_CLIENT_ID',
    defaultValue: '',
  );

  // "common" erlaubt sowohl private Microsoft-Konten als auch
  // organisatorische Konten - passend fuer ein privates OneDrive.
  static const String _authEndpoint =
      'https://login.microsoftonline.com/common/oauth2/v2.0/authorize';
  static const String _tokenEndpoint =
      'https://login.microsoftonline.com/common/oauth2/v2.0/token';

  static const String _redirectUri = 'de.holzliste.app://oauth-callback';

  static const List<String> _scopes = [
    'openid',
    'offline_access',
    'Files.ReadWrite.AppFolder',
  ];

  final FlutterAppAuth _appAuth = const FlutterAppAuth();

  bool get isConfigured => _clientId.isNotEmpty;

  Future<bool> signIn() async {
    if (!isConfigured) {
      throw StateError(
        'ONEDRIVE_CLIENT_ID wurde beim Bau der App nicht gesetzt. '
        'Siehe README.md, Abschnitt "Azure-App-Registrierung".',
      );
    }

    final result = await _appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        _clientId,
        _redirectUri,
        serviceConfiguration: const AuthorizationServiceConfiguration(
          authorizationEndpoint: _authEndpoint,
          tokenEndpoint: _tokenEndpoint,
        ),
        scopes: _scopes,
        preferEphemeralSession: false,
      ),
    );

    if (result.accessToken == null) return false;

    await SecureStorageService.instance.saveTokens(
      accessToken: result.accessToken!,
      refreshToken: result.refreshToken,
      expiry: result.accessTokenExpirationDateTime ??
          DateTime.now().add(const Duration(minutes: 55)),
    );
    return true;
  }

  Future<void> signOut() async {
    await SecureStorageService.instance.clearOneDriveTokens();
  }

  /// Liefert ein gueltiges Access-Token, erneuert es bei Bedarf leise
  /// im Hintergrund ueber das gespeicherte Refresh-Token.
  Future<String?> validAccessToken() async {
    final storage = SecureStorageService.instance;
    final expiry = await storage.tokenExpiry;
    final token = await storage.accessToken;

    if (token != null &&
        expiry != null &&
        expiry.isAfter(DateTime.now().add(const Duration(minutes: 2)))) {
      return token;
    }

    final refreshToken = await storage.refreshToken;
    if (refreshToken == null || !isConfigured) return null;

    final result = await _appAuth.token(
      TokenRequest(
        _clientId,
        _redirectUri,
        refreshToken: refreshToken,
        serviceConfiguration: const AuthorizationServiceConfiguration(
          authorizationEndpoint: _authEndpoint,
          tokenEndpoint: _tokenEndpoint,
        ),
        scopes: _scopes,
      ),
    );

    if (result.accessToken == null) return null;

    await storage.saveTokens(
      accessToken: result.accessToken!,
      refreshToken: result.refreshToken ?? refreshToken,
      expiry: result.accessTokenExpirationDateTime ??
          DateTime.now().add(const Duration(minutes: 55)),
    );
    return result.accessToken;
  }
}
