# 🌍 Project Earth LAN Manager (Standalone)

> **Hast du Bock? Plug & Play – auf geht's!**
> Ein reines Hobby- und Freizeitprojekt für LAN-Games und die gute alte Zeit.

LAN-Partys, Online-LAN mit Freunden oder Community-Abende – ohne Installation, ohne Registrierung, ohne Werbung.
Der Manager will nichts Etabliertes ersetzen, sondern alle abholen, die einfach **zusammen spielen** wollen.

---

## 📑 Inhalt

- [Auf einen Blick](#-auf-einen-blick)
- [Verbindung & Netzwerk](#-verbindung--netzwerk)
- [Gaming](#-gaming)
- [Matchmaking & Turniere](#-matchmaking--turniere)
- [LAN-Party-Intranet](#-lan-party-intranet)
- [Kommunikation](#-kommunikation)
- [Dateien & Medien](#-dateien--medien)
- [Transparenz](#-transparenz)

---

## ✅ Auf einen Blick

| | |
|---|---|
| 💾 **Installation** | Keine nötig |
| 💶 **Kosten** | Kostenlos |
| 👤 **Account** | Keine Registrierung, keine persönlichen Daten |
| 🌐 **Spieler online** | Bis zu 512 |
| 🏠 **Spieler im LAN** | Unbegrenzt |
| 🔓 **Quellcode** | PowerShell, öffentlich auf GitHub |

**Bedienung:**
- Optionaler Autostart – der Manager startet direkt im Infobereich (neben der Uhr)
- Ein einziges Symbol für alle Fenster, mit Menü aller offenen Fenster

---

## 🔗 Verbindung & Netzwerk

- **Peer-to-Peer** – direkte Verbindung zwischen den Teilnehmern
- **Einladungscode** – Lobby beitreten, ohne IP-Adressen eintippen
- **Automatische Erkennung** anderer Manager im Netzwerk
- **PLM Rendezvous** – optional dauerhafte Verbindung über einen eigenen VPS
- **Firewall & Ports** – Regeln werden automatisch gesetzt
- **Netzwerkadapter** frei wählbar

> ℹ️ Die Verbindung besteht, solange der Manager geöffnet ist.

---

## 🎮 Gaming

- **Game Server Browser** – unabhängig von Steam und anderen Launchern
- **Direkter Beitritt** – das passende Spiel wird gestartet und verbunden
- **Server-Listen** werden zwischen den Managern ausgetauscht
- **Game-Suche** – legt Verknüpfungen im Ordner `Lan Games` an

---

## 🏆 Matchmaking & Turniere

### Matchmaking
- Mitspieler für ein Spiel finden
- Modi: **1 vs 1** bis **5 vs 5** sowie **Jeder gegen jeden**
- Bereit-Check und möglichst **ausgeglichene Teams** nach Wertung (Elo)
- Ergebnisse zählen erst nach **Bestätigung durch das gegnerische Team**
- Wertung pro Spiel

### Turnier-Planer

| Modus | Teilnehmer |
|---|---|
| K.-o.-System | bis 64 (Freilose für die Besten) |
| Jeder gegen jeden | bis 16 |

- Auch mit **Teams bis 5 Spieler**, ausgeglichen nach Wertung
- **Gäste ohne Manager** können eingetragen werden
- Ergebnisse werden gemeldet und bestätigt – **Sieger rücken automatisch weiter**

---

## 🖥️ LAN-Party-Intranet

Ein eigenes Intranet direkt aus dem Manager – **ohne Webserver-Software**.

- **Baukasten mit Vorlagen:** Klassische LAN-Party · Turnier-Event · Kleine Freundes-LAN
- **Live-Vorschau** beim Bearbeiten
- **Blöcke:** News, Zeitplan, Spiele-Server (mit direktem Beitritt), Regeln, Sitzplan, Downloads und mehr
- **Live-Daten:** Turnierbaum bzw. Tabelle, geplante Spieleabende, Matchmaking-Ergebnisse
- **Umfragen & Bestelllisten** (z. B. Pizza 🍕) – ein Eintrag pro PC
- **Vorhandenes Intranet** des Veranstalters einbetten
- **Automatische Suche** nach Intranets im Netzwerk und in der P2P-Lobby

---

## 💬 Kommunikation

- **Voice-Chat** – privat, in Gruppen und in Kanälen
- **Kanäle** – dauerhaft und auf Wunsch passwortgeschützt
- **Text-Chat**
- **Lautstärke pro Teilnehmer**, Ein- und Ausgabegerät wählbar
- **Postfach** für Nachrichten an Teilnehmer, die offline sind
- **Freundesliste**, Anstupsen, Bannliste

---

## 📁 Dateien & Medien

- **Datei-Freigabe**
  - ganze Ordner übertragen
  - parallele Übertragung
  - abgebrochene Übertragungen fortsetzen
  - Statusanzeige mit Tempo und Restzeit
- **Kodi-Streaming** für Serien, Filme und Musik

---

## 🔍 Transparenz

Der komplette Quellcode ist in **PowerShell** geschrieben und hier auf GitHub **öffentlich einsehbar**.
Jeder kann nachlesen, was der Manager tut.
