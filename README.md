# Project Earth LAN

Project Earth LAN ist ein virtuelles LAN über das Internet, gebaut für Spieler.

Früher hat man für LAN-Partys Rechner in einen Raum geschleppt. Heute macht das
ZeroTier One für uns: Alle Mitspieler landen im selben virtuellen Netzwerk und
sehen sich gegenseitig so, als würden die PCs nebeneinander stehen. Damit laufen
alte und neue LAN- und Koop-Spiele wieder, ganz ohne Portfreigaben im Router und
ohne dass jemand einen Server mieten muss. Die Verbindung geht direkt von PC zu
PC (P2P).

Damit man sich mit dem ganzen Netzwerk-Kram nicht herumärgern muss, gibt es den
**Project Earth LAN Manager**. Der macht alles in einem Fenster.

Video zum Projekt: https://youtu.be/_tzuzShSyzg?si=ISYE0XEAjUy-VO9k

**Loslegen:** Unter *Releases* den Manager herunterladen, Rechtsklick →
*Als Administrator ausführen*, dann **Option 1** wählen. Den Rest macht er
selbst.

---

## Was der Manager macht

- **Installiert alles** – ZeroTier One, Netzwerk-Beitritt, Adapter richtig
  einstellen. Ein Klick, fertig.
- **Netzwerke verwalten** – jedem beliebigen ZeroTier-Netzwerk beitreten oder es
  wieder verlassen.
- **Findet deine Spiele** – durchsucht Steam, Epic, GOG, Ubisoft, EA und deine
  Ordner und legt für über 500 LAN-fähige Spiele Verknüpfungen auf dem Desktop
  an. Was er nicht findet, suchst du von Hand dazu.
- **Server-Browser** – zeigt, welche Spiele-Server im Netz gerade laufen. Ein
  Klick auf „Join“ startet das Spiel und verbindet dich. Eigene Dedicated Server
  kann er auch starten und überwachen.
- **Chat, Dateien und Voice** – Gruppen- und Privatchat, Dateien direkt von PC
  zu PC schicken, Sprachchat mit Push-to-Talk.
- **Freunde, Postfach und Bannliste** – siehst, wer online ist, schickst
  Nachrichten (kommen sofort an oder beim nächsten Start des anderen) und
  sperrst, wen du nicht dabeihaben willst.
- **Live-Status und Spieleabende** – wer ist da, wer spielt was, und wann
  treffen wir uns zum Zocken.
- **Downloads und Hilfe** – Tools und Mods vom Server im LAN holen, und per
  Remotedesktop kann man sich gegenseitig helfen, wenn mal was klemmt.
- **Autostart** – auf Wunsch startet der Manager minimiert mit, damit Postfach
  und Status immer laufen.

Ein automatisches Update gibt es nicht. Wenn eine neuere Version da ist, sagt er
nur Bescheid und öffnet diese Seite.

---

## Für alle, die es auf Herz und Nieren prüfen wollen

Niemand sollte eine `.exe` aus dem Internet einfach so starten – ich auch nicht.
Deshalb liegt hier das **Prüfwerkzeug** dabei. Es braucht keine Vorkenntnisse
und keine Administratorrechte, und es hat drei Knöpfe:

- **Prüfen** – zeigt dir in normalem Deutsch, was der Manager tut: welche Ports
  er öffnet, was er in Firewall, Autostart und Registry schreibt, welche Dateien
  er anlegt und welche Adressen er kontaktiert. Dazu sucht es nach den typischen
  Sachen, die Schadsoftware macht, und sagt bei jedem einzelnen Punkt „nein“
  oder zeigt die genaue Zeile. Das geht mit dem Skript **und** mit der fertigen
  `.exe`: Es holt den Code aus der `.exe` heraus, du kannst ihn dir speichern und
  selbst lesen – und per Knopfdruck vergleichen, ob die `.exe` wirklich aus genau
  dem Skript gebaut wurde, das hier liegt.
- **Alles entfernen** – listet alles auf, was der Manager auf deinem PC angelegt
  hat, und du hakst ab, was weg soll. Keine Reste, keine Suche in der Registry.
- **Sandbox** – erstellt dir eine Datei für die Windows Sandbox. Damit probierst
  du den Manager in einem abgeschotteten Wegwerf-Windows aus, auf Wunsch sogar
  ganz ohne Netzwerk.

Deshalb lade ich hier immer beides hoch: die `.exe` und das Skript `.ps1`. In
`PRUEFSUMMEN.txt` stehen die Prüfsummen aller Dateien.

**Noch ein Wort zu Virenwarnungen:** Der Manager fasst Netzwerkadapter, Firewall
und Autostart an – genau danach suchen Virenscanner. Deshalb schlagen sie ab und
zu an, obwohl nichts passiert (bei Defender als `Wacatac.B!ml`, das `!ml` heißt
„geraten“, nicht „gefunden“). Solche Fehlalarme melde ich an Microsoft. Und weil
ich kein teures Zertifikat gekauft habe, meckert Windows beim ersten Start mit
SmartScreen – über *Weitere Informationen → Trotzdem ausführen* geht es weiter.
Wer mir da nicht glauben will: Genau dafür ist das Prüfwerkzeug da.

---

Lizenz: GNU General Public License v3.0
