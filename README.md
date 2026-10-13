# Holzliste-App

Digitale Erfassung von Baumstämmen im Wald – als Ersatz/Ergänzung zur
Excel-Vorlage `Holzliste.xlsx`. Läuft komplett offline, synchronisiert
automatisch bei WLAN nach OneDrive.

## Funktionsumfang

- Erfassung: Baumart, Länge, Durchmesser, Rinde, Kommentar, optional GPS
- Automatische Berechnung von Volumen (fm/rm) und Stärkeklasse – identisch
  zu den Formeln in der Original-Excel
- Bearbeiten und Löschen bestehender Einträge (mit Rückgängig-Funktion)
- Offline-first: alle Daten liegen zunächst verschlüsselt auf dem Gerät
- Automatischer Sync nach OneDrive, sobald WLAN verfügbar ist
- Die Original-Excel-Datei bleibt die Quelle der Wahrheit: die App
  schreibt nur in das Tabellenblatt "Erfassung", das Blatt "Holzliste"
  berechnet sich beim Öffnen in Excel wie gewohnt automatisch

## Einmalige Einrichtung (vor dem ersten Build)

Zwei Dinge müssen einmalig eingerichtet werden: der OneDrive-Zugang
(Azure-App-Registrierung) und der Signatur-Schlüssel für die APK.
Beides dauert zusammen ca. 15 Minuten.

### 1. Azure-App-Registrierung (für den OneDrive-Zugriff)

Das ist kostenlos und benötigt keine Firma/Organisation – es funktioniert
mit deinem ganz normalen privaten Microsoft-Konto.

1. Öffne https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade
   und melde dich mit deinem privaten Microsoft-Konto an.
2. Klicke auf **Neue Registrierung**.
3. Name: z. B. `Holzliste-App`
4. Unterstützte Kontotypen: **Konten in einem beliebigen
   Organisationsverzeichnis und private Microsoft-Konten**
5. Plattform hinzufügen → **Öffentlicher Client/Nativ (Mobil & Desktop)**
   → als Redirect-URI eintragen:
   `de.holzliste.app://oauth-callback`
6. Unter **API-Berechtigungen** → **Berechtigung hinzufügen** →
   **Microsoft Graph** → **Delegierte Berechtigungen** →
   `Files.ReadWrite.AppFolder` und `offline_access` hinzufügen.
7. Auf der Übersichtsseite der App die **Anwendungs-ID (Client)**
   kopieren – das ist die `ONEDRIVE_CLIENT_ID`, die du gleich als
   GitHub-Secret hinterlegst.

Hinweis zur Sicherheit: Die App bekommt dadurch **nur Zugriff auf einen
eigenen, abgeschotteten Ordner** in deinem OneDrive (`Apps/Holzliste-App`),
nicht auf dein gesamtes privates OneDrive. Die Excel-Datei landet beim
ersten Sync automatisch dort.

### 2. Signatur-Schlüssel erzeugen (einmalig)

Zum Signieren der APK wird ein privater Schlüssel benötigt. Auf einem PC
mit installiertem Java (`keytool` ist Teil jedes JDK):

```bash
keytool -genkey -v -keystore holzliste-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias holzliste
```

Du wirst nach einem Passwort und ein paar Angaben (Name etc.) gefragt –
frei ausfüllbar. **Bewahre die Datei `holzliste-release.jks` und das
Passwort sicher auf** (z. B. Passwort-Manager) – ohne sie können
zukünftige App-Updates nicht mehr signiert werden.

Dann die Datei in Base64 umwandeln (wird als GitHub-Secret hinterlegt,
niemals im Klartext ins Repository):

```bash
base64 -i holzliste-release.jks | tr -d '\n' > keystore-base64.txt
```

### 3. GitHub-Secrets hinterlegen

Im Repository unter **Settings → Secrets and variables → Actions →
New repository secret** folgende fünf Secrets anlegen:

| Name | Wert |
|---|---|
| `ONEDRIVE_CLIENT_ID` | Anwendungs-ID aus Schritt 1 |
| `KEYSTORE_BASE64` | Inhalt von `keystore-base64.txt` |
| `KEYSTORE_PASSWORD` | Das Keystore-Passwort aus Schritt 2 |
| `KEY_ALIAS` | `holzliste` (oder dein gewählter Alias) |
| `KEY_PASSWORD` | Das Schlüssel-Passwort aus Schritt 2 |

## Build auslösen

Jeder Push auf `main` baut automatisch eine signierte Release-APK.
Alternativ manuell: Reiter **Actions** → **Android Release Build** →
**Run workflow**.

Nach ca. 5–8 Minuten liegt die fertige APK unter **Releases** (rechte
Seitenleiste des Repositorys) zum Download bereit.

## Installation auf dem Handy (Android 11)

1. Release-Seite auf dem Handy öffnen, `app-release.apk` herunterladen
2. Beim ersten Öffnen fragt Android nach Erlaubnis, Apps aus dieser
   Quelle (z. B. dem Browser) zu installieren – einmalig bestätigen
3. Installieren, App öffnen, unter **Einstellungen** einmalig
   **Mit OneDrive verbinden**

## Bekannte Grenze

Die mitgelieferte Excel-Vorlage hat die Berechnungsformeln bis Zeile 722
vorausgefüllt (≈ 720 Stämme). Wird dieses Limit erreicht, meldet die App
das im Sync-Status. Die Formeln lassen sich am PC in der Excel jederzeit
weiter nach unten ziehen.

## Sicherheitsmaßnahmen im Überblick

- Minimal notwendige Android-Berechtigungen (Internet, Netzwerkstatus,
  Standort nur bei aktiviertem GPS-Feature)
- Lokale Datenbank verschlüsselt (SQLCipher), Schlüssel im Android
  Keystore
- OneDrive-Anmeldung über OAuth2/PKCE – kein Client-Secret im Code oder
  in der APK
- Zugriff auf OneDrive ist auf einen dedizierten App-Ordner beschränkt
- Kein Klartext-Netzwerkverkehr (nur HTTPS)
- Kein automatisches Android-Backup der App-Daten
- Signierte, code-verschleierte Release-APK (R8/ProGuard)
