<p align="center">
  <img src="Design/icon.png" width="128" alt="">
</p>

<h1 align="center">KeepAlive</h1>

<p align="center">
  Hält selbst entwickelte iOS-Apps auf deinem iPhone installiert, ohne kostenpflichtigen Developer Account.<br>
  <a href="README.md">English</a>
</p>

<p align="center">
  <img src="Design/screenshots/keepalive.png" alt="KeepAlive-Einstellungsfenster mit dem Menü aus der Menüleiste">
</p>

Apps, die mit einem kostenlosen Apple Account signiert sind, lassen sich nach sieben
Tagen nicht mehr öffnen. KeepAlive ist eine kleine Menüleisten-App für deinen Mac, die
sie vorher neu baut und installiert, sobald dein iPhone im selben WLAN ist.

- Baut von jedem ausgewählten Projekt die **Release**-Konfiguration.
- Erneuert frühzeitig, standardmäßig ab drei Tagen. So bleiben vier Tage Puffer.
- Installiert über WLAN oder Kabel mit Apples eigenen Werkzeugen (`xcodebuild` und `devicectl`).
- Spart Energie. macOS plant die Prüfungen ein, und Builds warten auf das Netzteil,
  außer eine App läuft innerhalb eines Tages ab.
- Funktioniert mit jedem Xcode-Projekt oder -Workspace. Für Flutter und andere
  plattformübergreifende Projekte lässt sich vor jedem Build ein Befehl ausführen.
- Hinterlässt keine Build-Dateien, sobald eine App installiert ist.
- Auf Deutsch und Englisch.

## Voraussetzungen

- macOS 14 Sonoma oder neuer
- Xcode 15 oder neuer, mit deinem Apple Account angemeldet
- Ein iPhone oder iPad mit aktiviertem Entwicklermodus

## Installation

Lade `KeepAlive.zip` aus dem [neuesten Release](../../releases/latest), entpacke es und
bewege KeepAlive in den Ordner „Programme“.

KeepAlive ist nicht notarisiert, weil dafür ein kostenpflichtiger Developer Account nötig
ist. Deshalb blockiert macOS die App beim ersten Öffnen. Öffne dann Systemeinstellungen →
Datenschutz & Sicherheit, scrolle nach unten und klicke bei der Meldung zu KeepAlive auf
**Dennoch öffnen**. Alternativ geht es im Terminal:

```sh
xattr -dr com.apple.quarantine /Applications/KeepAlive.app
```

Selbst bauen (dafür ist Xcode 26 oder neuer nötig):

```sh
git clone https://github.com/oli-zr/keepalive.git
cd keepalive
scripts/build_app.sh
open build/KeepAlive.app
```

## Einrichtung

Das ist nur einmal nötig.

1. **Anmelden:** In Xcode unter Settings → Accounts deinen Apple Account hinzufügen.
2. **WLAN-Kopplung:** Das iPhone per Kabel anschließen. In Xcode Window → Devices and
   Simulators wählen, das iPhone auswählen und **Connect via network** aktivieren.
3. **Projekt vorbereiten:** Das Projekt einmal in Xcode öffnen. Unter Signing &
   Capabilities **Automatically manage signing** und dein Personal Team wählen, dann
   einmal auf dem iPhone ausführen. Beim ersten Mal musst du dem Entwicklerzertifikat
   auf dem iPhone unter Einstellungen → Allgemein → VPN und Geräteverwaltung vertrauen.
4. **In KeepAlive hinzufügen:** Auf das KeepAlive-Symbol in der Menüleiste klicken und
   Einstellungen … → Apps → App hinzufügen … wählen.
5. **KeepAlive laufen lassen:** Unter Allgemein **Beim Anmelden öffnen** aktivieren. Sind
   mehrere Geräte gekoppelt, unter Gerät dein iPhone auswählen.

Bei Flutter-Projekten unter **Vor dem Build** `flutter build ios --release --config-only`
eintragen, damit das iOS-Projekt vor jedem Build aktuell ist.

## So funktioniert’s

Alle 30 Minuten, zu einem Zeitpunkt, den macOS für günstig hält, und nach dem Aufwachen
des Macs prüft KeepAlive, ob eine App fällig ist. Für jede fällige App passiert Folgendes:

1. KeepAlive sucht dein iPhone mit `devicectl`.
2. Das zwischengespeicherte Provisioning-Profil der App wird gelöscht, damit Apple ein
   neues ausstellt, das sieben Tage gültig ist.
3. Die Release-Konfiguration wird mit `xcodebuild -allowProvisioningUpdates` gebaut.
4. Die App wird mit `devicectl device install app` installiert. Deine Daten in der App
   bleiben erhalten.
5. Die Build-Dateien werden gelöscht. In deinem Projektordner wird nichts angelegt.

Die Einstellungen liegen in `~/Library/Application Support/KeepAlive`, die Protokolle in
`~/Library/Logs/KeepAlive`. Zusammen brauchen sie weniger als ein Megabyte.

## Updates

KeepAlive prüft einmal am Tag auf GitHub, ob es eine neue Version gibt, installiert sie
selbst, während keine App gebaut wird, und startet neu. Der Download wird dabei mit der
Prüfsumme abgeglichen, die mit jedem Release veröffentlicht wird. Unter Allgemein →
Updates lässt sich das abschalten oder von Hand prüfen. Versionen vor 1.1 können sich
noch nicht selbst aktualisieren; ersetze sie einmalig von Hand.

## Grenzen

Diese Grenzen setzt Apple für kostenlose Accounts, nicht KeepAlive.

- Höchstens drei eigene Apps gleichzeitig pro Gerät.
- Höchstens zehn neue App-IDs innerhalb von sieben Tagen.
- Manche Funktionen wie Push-Mitteilungen oder iCloud sind nicht verfügbar.
- Dein Mac muss alle paar Tage wach und im selben Netzwerk wie dein iPhone sein.

## Lizenz

MIT, siehe [LICENSE](LICENSE).

KeepAlive ist ein unabhängiges Projekt und steht in keiner Verbindung zu Apple Inc.
Xcode, iPhone und macOS sind Marken der Apple Inc.
