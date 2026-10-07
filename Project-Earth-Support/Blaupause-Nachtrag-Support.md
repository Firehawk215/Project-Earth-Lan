# Nachtrag zur PEL-Blaupause-Spinnennetz: Dienst "Support"

Stand 2026-10-07. Die Original-Blaupause war beim Bau nicht lesbar (PC nicht
verbunden). Dieser Nachtrag ist deshalb ein VORSCHLAG und muss vor dem
Eintragen gegen das Portregister geprueft werden.

## Portregister (neu)

| Port | Proto | Dienst | Bemerkung |
|---|---|---|---|
| 9890 | UDP (echt) | Support Mini-Vermittler | Magic "PS", protokollgleich mit PEL Rendezvous; mehrere Instanzen pro Port moeglich |
| 9891 | UDP (virtuell) | Support | Magic-Byte 0xA8, nur im Tunnel 10.77.0.0/16 |
| 9892 | UDP (echt) | Support P2P-Socket | Magic "PE", ersetzt 47800 fuer dieses Tool |

Zu pruefen: 9890 und 9892 liegen im Bereich "neue Dienste 9881-9899";
0xA8 im Bereich 0xA4-0xAF. Kollision mit bereits vergebenen Eintraegen
(z. B. 9881 Dienstverzeichnis) besteht nach den bekannten Regeln nicht.

## Dienst

- Name: Support
- Vertrauen: eigene Lobby "pes-" + 12 Zeichen, Passwort 24 Zeichen (erzeugt)
- Einladungscode: `PES1:` + Base64url(Server \n Lobby \n Passwort)
- Schluesselableitung: V1 unveraendert (PBKDF2-SHA1, 100000)
- Rahmen: HELLO 0x01, REL 0x02, ACK 0x03, BYE 0x04, AUDIO 0x10, VIDEO 0x11
- Zuverlaessige Stroeme: 0 Steuerung, 1 Datei, 2 Bildschirm
- Paarung: genau ein Helfer und ein Kunde

## Firewall

- Project Earth Support (UDP 9892)
- Project Earth Support Vermittler (UDP 9890)

## Nachfolge-Komponenten

Manager, PEL Rendezvous und PEL-Android-App sind NICHT geaendert. Uninstall-PEL
entfernt die Regeln automatisch (Praefix "Project Earth"); die geplante
Aufgabe "Project Earth Support Autostart" und der Ordner
`C:\ProgramData\Project-Earth-Support` muessten dort noch ergaenzt werden.
