<p align="center">
  <img src="Design/icon.png" width="128" alt="">
</p>

<h1 align="center">KeepAlive</h1>

<p align="center">
  Hält selbst entwickelte iOS-Apps auf deinem iPhone und iPad installiert, ohne kostenpflichtigen Developer Account.<br>
  <a href="README.md">English</a>
</p>

<p align="center">
  <img src="Design/screenshots/keepalive.png" alt="KeepAlive-Einstellungsfenster mit dem Menü aus der Menüleiste">
</p>

Apps, die mit einem kostenlosen Apple Account signiert sind, lassen sich nach sieben
Tagen nicht mehr öffnen. KeepAlive ist eine kleine Menüleisten-App für deinen Mac, die
sie vorher neu baut und installiert, sobald dein iPhone oder iPad im selben WLAN ist.
Einmal eingerichtet, musst du dich um nichts mehr kümmern.

- Erneuert frühzeitig, standardmäßig ab drei Tagen. So bleiben vier Tage Puffer.
- Funktioniert mit mehreren Geräten, zum Beispiel einem iPhone und einem iPad.
- Installiert über WLAN oder Kabel mit Apples eigenen Werkzeugen. Deine Daten in den Apps
  bleiben erhalten.
- Spart Energie: Builds warten auf das Netzteil, außer eine App läuft innerhalb eines Tages ab.
- Funktioniert mit jedem Xcode-Projekt, auch mit Flutter und anderen plattformübergreifenden Projekten.
- Aktualisiert sich selbst und ist auf Deutsch, Englisch, Spanisch, Französisch, Japanisch,
  Portugiesisch und vereinfachtem Chinesisch verfügbar. [Korrekturen sind willkommen.](../../issues/new/choose)

## Was du brauchst

- Einen Mac mit macOS 14 Sonoma oder neuer
- [Xcode](https://apps.apple.com/app/xcode/id497799835) 15 oder neuer aus dem App Store
- Einen kostenlosen Apple Account
- Ein iPhone oder iPad

## Installation

1. Öffne das **Terminal**: Drücke ⌘ Leertaste, tippe `Terminal` und drücke den Zeilenschalter.
2. Kopiere diese Zeile, füge sie im Terminal ein und drücke den Zeilenschalter:

   ```sh
   curl -fsSL https://raw.githubusercontent.com/oli-zr/keepalive/main/scripts/install.sh | sh
   ```

Der Befehl lädt die neueste Version, prüft, dass sie vollständig und unverändert ist,
legt KeepAlive in den Ordner „Programme“ und öffnet es. KeepAlive erscheint dann als Symbol
oben in der Menüleiste. Du kannst vorher nachlesen, [was der Befehl macht](scripts/install.sh).

<details>
<summary>Ohne Terminal installieren</summary>

1. Lade `KeepAlive.zip` aus dem [neuesten Release](../../releases/latest) und öffne die Datei.
2. Bewege KeepAlive in den Ordner „Programme“ und öffne es.
3. Beim ersten Öffnen blockiert macOS die App, weil sie nicht notarisiert ist. Dafür wäre
   ein kostenpflichtiger Developer Account nötig. Öffne Systemeinstellungen → Datenschutz &
   Sicherheit, scrolle nach unten und klicke bei der Meldung zu KeepAlive auf **Dennoch öffnen**.

</details>

<details>
<summary>Selbst bauen</summary>

Dafür ist Xcode 26 oder neuer nötig.

```sh
git clone https://github.com/oli-zr/keepalive.git
cd keepalive
scripts/build_app.sh
open build/KeepAlive.app
```

</details>

<details>
<summary>Herkunft eines Downloads prüfen</summary>

Jedes Release wird von GitHub Actions aus dem getaggten Quellcode gebaut, und GitHub
signiert einen Nachweis über diesen Build. Mit der [GitHub CLI](https://cli.github.com)
kannst du prüfen, dass ein Download aus diesem Repository stammt und danach nicht verändert
wurde:

```sh
gh attestation verify KeepAlive.zip --repo oli-zr/keepalive
```

</details>

## Einrichtung

### 1. In Xcode anmelden (einmalig)

Öffne Xcode, wähle Xcode → Settings → **Apple Accounts**, klicke auf **+** und melde dich
mit deinem Apple Account an. In Xcode 26 und älter heißt der Bereich **Accounts**.

### 2. iPhone oder iPad verbinden (einmal pro Gerät)

1. Öffne Xcode, schließe das Gerät per Kabel an deinen Mac an und entsperre es. Fragt es,
   ob du diesem Computer vertraust, tippe auf **Vertrauen**.
2. Aktiviere auf dem Gerät Einstellungen → Datenschutz & Sicherheit → **Entwicklermodus**
   und starte es neu, wenn du dazu aufgefordert wirst. Die Option erscheint, sobald das
   Gerät einmal mit Xcode verbunden war.
3. Mit Xcode 27 war’s das schon: Ab jetzt ist das Gerät auch über WLAN erreichbar. Mit
   Xcode 26 oder älter wähle außerdem Window → Devices and Simulators, dann das Gerät, und
   aktiviere **Connect via network**.

### 3. Projekt vorbereiten (einmal pro App)

1. Öffne das Projekt in Xcode.
2. Wähle das App-Target, öffne **Signing & Capabilities**, aktiviere **Automatically manage
   signing** und wähle dein Personal Team.
3. Wähle oben im Fenster dein Gerät und klicke auf Run (▶).
4. Beim ersten Mal öffnet sich die App noch nicht. Öffne auf dem Gerät Einstellungen →
   Allgemein → VPN und Geräteverwaltung, tippe auf deinen Apple Account und dann auf
   **Vertrauen**.

Bei Flutter-Projekten führe vorher einmal `flutter build ios` aus. In KeepAlive kannst du
später unter **Vor dem Build** `flutter build ios --release --config-only` eintragen, damit
das iOS-Projekt vor jedem Build aktuell ist.

### 4. App zu KeepAlive hinzufügen

1. Klicke auf das KeepAlive-Symbol in der Menüleiste und wähle **Einstellungen …**.
2. Klicke unter **Apps** auf **App hinzufügen …** und wähle den Projektordner.
3. Aktiviere unter **Allgemein** die Option **Beim Anmelden öffnen**, damit KeepAlive
   immer läuft.

Das war’s. KeepAlive installiert die App sofort und erneuert sie ab jetzt von selbst.
Nutzt du mehrere Geräte, schalte jedes unter **Geräte** ein. Soll eine App nur auf einige
davon, klicke unter **Apps** neben der App auf ⓘ.

## Wenn etwas nicht klappt

Ein Klick auf das KeepAlive-Symbol zeigt den Zustand jeder App. Unter **Einstellungen … →
Aktivität** steht alles, was KeepAlive gemacht hat, mit den vollständigen Meldungen.

| Meldung | Was zu tun ist |
| --- | --- |
| *iPhone ist nicht erreichbar* | Verbinde das Gerät mit dem WLAN deines Macs. KeepAlive versucht es selbst erneut. |
| *Entsperre iPhone einmal …* | Entsperre das Gerät. Nach einem Neustart ist das einmal nötig, bevor Apps installiert werden können. |
| *Es konnte kein Provisioning-Profil erstellt werden* | Führe für dieses Projekt [Schritt 3 der Einrichtung](#3-projekt-vorbereiten-einmal-pro-app) aus. |
| *Mit einem kostenlosen Apple Account können drei eigene Apps gleichzeitig auf einem Gerät sein …* | Entferne eine davon vom Gerät oder schalte die App in KeepAlive für dieses Gerät aus. Siehe [Grenzen](#grenzen). |
| *Mit einem kostenlosen Apple Account lassen sich zehn neue App-IDs pro Woche erstellen …* | Warte ein paar Tage. KeepAlive versucht es selbst erneut. |
| *Xcode wurde nicht gefunden* | Installiere Xcode aus dem App Store oder wähle es unter Einstellungen → Allgemein aus. |
| Das Gerät fehlt unter **Geräte** | Wiederhole [Schritt 2 der Einrichtung](#2-iphone-oder-ipad-verbinden-einmal-pro-gerät) und klicke auf die Schaltfläche zum Aktualisieren. |

Kommst du nicht weiter? [Eröffne ein Issue](../../issues/new/choose) und füge die
passenden Zeilen aus `~/Library/Logs/KeepAlive/` hinzu.

## Grenzen

Diese Grenzen setzt Apple für kostenlose Accounts, nicht KeepAlive.

- Höchstens drei eigene Apps gleichzeitig pro Gerät.
- Höchstens zehn neue App-IDs innerhalb von sieben Tagen.
- Manche Funktionen wie Push-Mitteilungen oder iCloud sind nicht verfügbar.
- Dein Mac muss alle paar Tage wach und im selben Netzwerk wie deine Geräte sein.

## Updates

KeepAlive prüft einmal am Tag auf GitHub, ob es eine neue Version gibt, und installiert
sie selbst, während keine App gebaut wird. Unter Allgemein → Updates lässt sich das
abschalten oder von Hand prüfen. Auch der Installationsbefehl aktualisiert KeepAlive,
wenn du ihn erneut ausführst.

## Deinstallieren

1. Klicke auf das KeepAlive-Symbol und wähle **KeepAlive beenden**.
2. Bewege KeepAlive aus dem Ordner „Programme“ in den Papierkorb.
3. Um auch Einstellungen und Protokolle zu entfernen, führe im Terminal aus:

   ```sh
   rm -rf ~/Library/Application\ Support/KeepAlive ~/Library/Logs/KeepAlive
   ```

Die Apps auf deinen Geräten bleiben installiert, bis sie ablaufen.

## So funktioniert’s

Alle 30 Minuten, zu einem Zeitpunkt, den macOS für günstig hält, und wenn der Mac aufwacht
oder sich mit einem Netzwerk verbindet, prüft KeepAlive, ob eine App fällig ist. Für jede
fällige App passiert Folgendes:

1. KeepAlive sucht deine Geräte mit `devicectl`.
2. Das zwischengespeicherte Provisioning-Profil der App wird gelöscht, damit Apple ein
   neues ausstellt, das sieben Tage gültig ist.
3. Die Release-Konfiguration wird mit `xcodebuild -allowProvisioningUpdates` gebaut.
4. Die App wird mit `devicectl device install app` auf jedem Gerät installiert, auf dem
   sie fällig ist. Ist ein Gerät neu in deinem Personal Team, wird es vorher dort registriert.
5. Die Build-Dateien werden gelöscht. In deinem Projektordner wird nichts angelegt.

Ein Gerät, das gerade nicht da oder gesperrt ist, hält die anderen nicht auf. Es bekommt
die App, sobald es wieder erreichbar ist.

Die Einstellungen liegen in `~/Library/Application Support/KeepAlive`, die Protokolle in
`~/Library/Logs/KeepAlive`. Zusammen brauchen sie weniger als ein Megabyte.

## Lizenz

MIT, siehe [LICENSE](LICENSE).

KeepAlive ist ein unabhängiges Projekt und steht in keiner Verbindung zu Apple Inc.
Xcode, iPhone und macOS sind Marken der Apple Inc.
