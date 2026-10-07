# Project Earth Support

Live-Fernhilfe: oben Videochat, unten Fernsteuerung des Kunden-PCs.
Eigenes P2P-Netz (eigene Lobby, eigener Mini-Vermittler), unabhaengig vom
Project Earth LAN Manager, aber protokollgleich (Magic "PS"/"PE").

| Teil | Datei | Rolle |
|---|---|---|
| Windows | `windows/Project-Earth-Support.ps1` | Helfer oder Kunde, optional Mini-Vermittler |
| Android | `android/` (Kotlin, minSdk 29) | Helfer |

## Ablauf

1. Eine Seite startet den Mini-Vermittler (Windows: Knopf "Vermittler") und
   gibt UDP 9890 im Router frei - oder beide sind im selben LAN.
2. Helfer klickt "Neue Sitzung": Lobby und Passwort werden erzeugt, der
   Einladungscode `PES1:...` wird angezeigt.
3. Kunde fuegt den Code ein und klickt "Verbinden".
4. Helfer bittet um "Ansehen" oder "Steuern" - der Kunde muss jedes Mal
   bestaetigen. Beim Kunden steht ein rotes Banner, Not-Aus: Strg+Umschalt+F12.

Es gibt keinen unbeaufsichtigten Zugriff.

## Module

P2P, VIDEO (mit Ton), Fernsteuerung (eigene Bildschirmuebertragung), CHAT,
DATEI, I18N (DE/EN), TRAY, AUTO, ADAPTER, FW, HILFE, SIGN, ANDROID.

## Ports und Firewall

| Zweck | Port | Firewall-Regel |
|---|---|---|
| Mini-Vermittler | UDP 9890 | Project Earth Support Vermittler (UDP 9890) |
| P2P-Socket | UDP 9892 | Project Earth Support (UDP 9892) |
| Dienst "Support" im virtuellen Netz | UDP 9891, Magic 0xA8 | keine (laeuft im Tunnel) |

Geplante Aufgabe (nur wenn Autostart gewaehlt): "Project Earth Support Autostart".
Daten: `C:\ProgramData\Project-Earth-Support` (Passwort per DPAPI).

## Bauen

- Windows-EXE: mit dem PS1-zu-EXE-Builder (ps2exe -noConsole, requireAdmin), die .ps1 bleibt daneben.
- Android: `gradle :core:test :app:assembleRelease`; Signatur mit eigenem Keystore
  (`keystore/signing.properties`, nicht im Repository).
- Das Skript wird aus `windows/src` zusammengesetzt: `python3 tools/build_ps1.py`.

## Tests

`windows/test/core_test.ps1` (Kern, Verlust 0/8/20 %), `win_test.ps1`
(Bildschirm, Eingabe), `Project-Earth-Support.ps1 -Selbsttest`,
Android `:core:test`. Nicht automatisch pruefbar: Kamera, Ton-Geraete,
echtes Internet-NAT, die Android-Oberflaeche auf einem Geraet.
