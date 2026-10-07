# Project Earth Support - Android (Helfer-App)

Gegenstück zu `Project-Earth-Support.ps1`: Live-Video-Chat oben, Fernwartung unten.

- `core/` - plattformfreier Kern (reine JVM, testbar ohne Android): P2P-Engine (unverändert aus
  Project Earth LAN übernommen), Dienst "Support" (UDP 9891, Kennbyte 0xA8), zuverlässiger Strom, Sitzung.
- `app/`  - Android-Teil (Compose, minSdk 29): Oberfläche, Vordergrunddienst, Ton, Kamera.

Bauen: `gradle :core:test :app:assembleRelease` (Gradle 8.14, JDK 17, Android SDK 35).
Signieren: `signing.properties` wie in `signing.properties.example` anlegen (Schlüssel nie ins Repository).

Selbsttest gegen den C#-Kern der .ps1 (Vermittler läuft im Testskript):
`gradle :core:selfTest -PselfTestArgs="kk 39890"`
