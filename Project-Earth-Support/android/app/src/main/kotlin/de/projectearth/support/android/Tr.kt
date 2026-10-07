package de.projectearth.support.android

import java.util.Locale

/** Diese Datei wird von tools/gen_tr.py erzeugt (Texte der Oberflaeche: deutsch im Quelltext, englisch aus der Tabelle). */
object BuildInfo {
    const val VERSION = "2026.10.07"
}

object Tr {
    @Volatile var isEnglish = false
        private set

    /** "" = Sprache des Geraets, sonst "de" oder "en". */
    fun setLanguage(lang: String) {
        isEnglish = when (lang) {
            "en" -> true
            "de" -> false
            else -> !Locale.getDefault().language.startsWith("de")
        }
    }

    private fun fill(s: String, args: Array<out Any>): String {
        if (args.isEmpty()) return s
        var r = s
        for (i in args.indices) r = r.replace("{$i}", args[i].toString())
        return r
    }

    /** Fester Text der Oberflaeche. */
    fun t(de: String, vararg args: Any): String = fill(if (isEnglish) (en[de] ?: de) else de, args)

    private fun find(text: String, table: Map<String, String>): String {
        table[text]?.let { return it }
        for ((k, v) in table) {
            if (!k.endsWith("*")) continue
            val p = k.dropLast(1)
            if (text.startsWith(p)) return v.dropLast(1) + find(text.substring(p.length), table)
        }
        return text
    }

    /** Meldung aus dem Kern (dort bewusst reines ASCII): deutsche Schreibweise mit Umlauten oder englische Fassung. */
    fun core(text: String): String = if (text.isEmpty()) text else find(text, if (isEnglish) coreEn else coreDe)

    fun help(): List<Pair<String, String>> = if (isEnglish) helpEn else helpDe

    private val en: Map<String, String> = hashMapOf(
        "1. Neue Sitzung (du bist der Helfer)" to "1. New session (you are the helper)",
        "2. Verbindung" to "2. Connection",
        "Ablehnen" to "Decline",
        "Anleitung und Hilfe" to "Guide and help",
        "Annehmen" to "Accept",
        "Anruf beendet." to "Call ended.",
        "Anruf gestartet ..." to "Calling ...",
        "Anruf verbunden." to "Call connected.",
        "Anrufen" to "Call",
        "Ansicht beenden" to "Stop viewing",
        "Auflegen" to "Hang up",
        "Bildschirm anfordern" to "Request screen",
        "Bildschirm angefordert - der Kunde muss zustimmen." to "Screen requested - the customer has to agree.",
        "Bildschirm {0}" to "Screen {0}",
        "Bitte einen Namen eintragen." to "Please enter a name.",
        "Bitte zuerst die Adresse des Vermittlers eintragen (Name oder IP, optional mit :Port)." to "Please enter the address of the mediator first (name or IP, optionally with :port).",
        "Chat" to "Chat",
        "Chat (neu)" to "Chat (new)",
        "Chat und Verlauf" to "Chat and history",
        "Code senden" to "Send code",
        "Das Datei-Angebot wurde zurückgezogen: {0}" to "The file offer was withdrawn: {0}",
        "Datei angeboten: {0} - warte auf die Zustimmung des Partners." to "File offered: {0} - waiting for the partner to agree.",
        "Datei empfangen" to "Receive file",
        "Datei empfangen und geprüft: {0}" to "File received and verified: {0}",
        "Datei gesendet und geprüft: {0}" to "File sent and verified: {0}",
        "Datei kann nicht empfangen werden:" to "File cannot be received:",
        "Datei senden" to "Send file",
        "Datei {0} liegt in der App, das Speichern unter Download ist fehlgeschlagen." to "File {0} is kept inside the app, saving to Download failed.",
        "Datei-Übertragung abgebrochen: {0}" to "File transfer aborted: {0}",
        "Der Einladungscode ist ungültig. Er beginnt mit \"PES1:\"." to "The invitation code is invalid. It starts with \"PES1:\".",
        "Der Kunde erlaubt die Steuerung nicht (nur ansehen)." to "The customer does not allow control (view only).",
        "Der Kunde hat die Anfrage abgelehnt." to "The customer declined the request.",
        "Der Kunde überträgt seinen Bildschirm - Steuerung erlaubt." to "The customer is sharing the screen - control allowed.",
        "Der Kunde überträgt seinen Bildschirm - nur ansehen." to "The customer is sharing the screen - view only.",
        "Der Kunde überträgt seinen Bildschirm nicht mehr." to "The customer is no longer sharing the screen.",
        "Der Kunde überträgt seinen Bildschirm nicht." to "The customer is not sharing the screen.",
        "Der Partner hat den Anruf abgelehnt." to "The partner declined the call.",
        "Der Partner hat die Datei abgelehnt: {0}" to "The partner declined the file: {0}",
        "Der Partner hat nicht abgenommen." to "The partner did not answer.",
        "Die Größe der Datei ist unbekannt." to "The size of the file is unknown.",
        "Die Kamera des Partners ist aus." to "The partner's camera is off.",
        "Die Kamera läuft nur während eines Anrufs." to "The camera only runs during a call.",
        "Die Sitzung wird beendet." to "The session will be ended.",
        "Die Verbindung konnte nicht gestartet werden:" to "The connection could not be started:",
        "Die Verbindung zu {0} wird getrennt." to "The connection to {0} will be closed.",
        "Die Vermittler-Adresse im Einladungscode ist ungültig." to "The mediator address in the invitation code is invalid.",
        "Diese App ist für den Helfer. Der Kunde startet Project-Earth-Support auf seinem Windows-PC, fügt den Code ein und entscheidet selbst, ob er seinen Bildschirm zeigt und die Steuerung erlaubt." to "This app is for the helper. The customer starts Project-Earth-Support on the Windows PC, pastes the code and decides personally whether to show the screen and allow control.",
        "Einfügen" to "Paste",
        "Eingehender Anruf" to "Incoming call",
        "Einladungscode (PES1:...)" to "Invitation code (PES1:...)",
        "Einladungscode merken (verschlüsselt im Android Keystore)" to "Remember invitation code (encrypted in the Android Keystore)",
        "Einladungscode senden" to "Send invitation code",
        "Empfange Datei: {0}" to "Receiving file: {0}",
        "Empfange {0}: {1} von {2}" to "Receiving {0}: {1} of {2}",
        "Entf" to "Del",
        "Es klingelt beim Partner ..." to "Ringing ...",
        "Fernwartung" to "Remote support",
        "Front" to "Front",
        "Getrennt." to "Disconnected.",
        "Hier erscheint der Bildschirm des Kunden." to "The customer's screen appears here.",
        "Hilfe" to "Help",
        "Hoch" to "Up",
        "Hörer" to "Earpiece",
        "Ich" to "Me",
        "Ja" to "Yes",
        "Kamera: an" to "Camera: on",
        "Kamera: aus" to "Camera: off",
        "Kopieren" to "Copy",
        "Laut" to "Speaker",
        "Links" to "Left",
        "Live-Fernwartung mit Video-Chat" to "Live remote support with video chat",
        "Live-Video-Chat" to "Live video chat",
        "Mein Name" to "My name",
        "Mikro: an" to "Mic: on",
        "Mikro: aus" to "Mic: off",
        "Mit \"Bildschirm anfordern\" fragst du ihn danach." to "Ask for it with \"Request screen\".",
        "Mit Anrufen startest du Bild und Ton." to "Call starts picture and sound.",
        "Nachricht" to "Message",
        "Nein" to "No",
        "Neuen Code erzeugen" to "Create new code",
        "Nicht verbunden." to "Not connected.",
        "Nimm nur Dateien an, die du erwartest. Gespeichert wird unter Download/Project Earth Support." to "Only accept files you are expecting. They are saved under Download/Project Earth Support.",
        "Normal" to "Normal",
        "Ohne Kamera-Berechtigung ist kein Video möglich." to "No video without the camera permission.",
        "Ohne Mikrofon-Berechtigung hört dich der Partner nicht." to "Without the microphone permission the partner cannot hear you.",
        "Project Earth Support - bitte diesen Einladungscode im Programm einfügen und auf Verbinden klicken:" to "Project Earth Support - please paste this invitation code into the program and click Connect:",
        "Rechts" to "Right",
        "Runter" to "Down",
        "Rück" to "Back",
        "Rücktaste" to "Backspace",
        "Scharf" to "Sharp",
        "Schließen" to "Close",
        "Sende Datei: {0}" to "Sending file: {0}",
        "Sende {0}: {1} von {2}" to "Sending {0}: {1} of {2}",
        "Senden" to "Send",
        "Sitzung beenden?" to "End the session?",
        "Sitzung gestartet. Schicke dem Kunden den Einladungscode." to "Session started. Send the invitation code to the customer.",
        "Sobald der Kunde verbunden ist, kannst du ihn anrufen." to "As soon as the customer is connected you can call.",
        "Sparsam" to "Economy",
        "Steuerung anfordern" to "Request control",
        "Steuerung angefordert - der Kunde muss zustimmen." to "Control requested - the customer has to agree.",
        "Steuerung: an" to "Control: on",
        "Strg" to "Ctrl",
        "Task-Manager" to "Task Manager",
        "Tastatur" to "Keyboard",
        "Text für den PC des Kunden" to "Text for the customer's PC",
        "Trage die Adresse deines Vermittlers ein und erzeuge einen Code. Den Code bekommt der Kunde - er fügt ihn am PC in Project Earth Support ein." to "Enter the address of your mediator and create a code. The customer gets the code and pastes it into Project Earth Support on the PC.",
        "Trennen" to "Disconnect",
        "Verbinde ..." to "Connecting ...",
        "Verbinde mit dem Vermittler {0} ..." to "Connecting to the mediator {0} ...",
        "Verbinden" to "Connect",
        "Verbunden mit {0}" to "Connected to {0}",
        "Vermittler-Adresse (Name oder IP, optional :Port)" to "Mediator address (name or IP, optional :port)",
        "Verpasster Anruf." to "Missed call.",
        "Vollbild" to "Full screen",
        "Warte auf Zustimmung: {0}" to "Waiting for consent: {0}",
        "Warte auf das Bild ..." to "Waiting for the picture ...",
        "Warte auf den Kunden ..." to "Waiting for the customer ...",
        "Warte auf die Zustimmung des Kunden ..." to "Waiting for the customer to agree ...",
        "Zurück" to "Back",
        "direkt" to "direct",
        "ruft an (Video-Chat mit Ton)" to "is calling (video chat with sound)",
        "{0} ist nicht mehr verbunden." to "{0} is no longer connected.",
        "{0} ist verbunden ({1})." to "{0} is connected ({1}).",
        "{0} möchte dir eine Datei senden:" to "{0} wants to send you a file:",
        "{0} möchte eine Datei senden: {1}" to "{0} wants to send a file: {1}",
        "über den Vermittler (Relay)" to "via the mediator (relay)",
    )

    private val coreEn: Map<String, String> = linkedMapOf(
        "Getrennt" to "Disconnected",
        "Verbunden" to "Connected",
        "Schluessel werden abgeleitet ..." to "Deriving keys ...",
        "Verbinde mit Vermittlungsserver ..." to "Connecting to the mediator ...",
        "Server nicht erreichbar - bestehende Direktverbindungen bleiben aktiv" to "Mediator not reachable - existing direct connections stay active",
        "Fehler: *" to "Error: *",
        "Server-Adresse nicht aufloesbar" to "Mediator address cannot be resolved",
        "Veraltete oder neuere Programmversion - bitte aktualisieren." to "Outdated or newer program version - please update.",
        "Server ausgelastet (zu viele Lobbys)." to "Mediator is full (too many sessions).",
        "Keine freie virtuelle IP." to "No free virtual address.",
        "P2P laeuft bereits." to "The connection is already running.",
        "Der Lobby-Name muss mindestens 3 Zeichen haben." to "The session name must have at least 3 characters.",
        "Das Lobby-Passwort muss mindestens 6 Zeichen haben." to "The session password must have at least 6 characters.",
        "Kein Vermittlungsserver eingetragen." to "No mediator entered.",
        "Verbindung zum Partner verloren." to "Connection to the partner lost.",
        "Partner hat neu gestartet." to "The partner restarted.",
        "Der Partner hat die Sitzung beendet." to "The partner ended the session.",
        "Verbindung getrennt" to "connection closed",
        "Datei nicht gefunden." to "File not found.",
        "Datei ist zu gross." to "File is too large.",
        "Nicht verbunden." to "Not connected.",
        "Es laeuft bereits eine Uebertragung." to "A transfer is already running.",
        "Kein offenes Angebot." to "No open offer.",
        "abgelehnt" to "declined",
        "vom Absender abgebrochen" to "cancelled by the sender",
        "vom Empfaenger abgebrochen" to "cancelled by the receiver",
        "Empfaenger meldet Fehler" to "receiver reports an error",
        "mehr Daten als angekuendigt" to "more data than announced",
        "Pruefsumme stimmt nicht" to "checksum does not match",
        "abgebrochen" to "cancelled",
        "Kein Lautsprecher und kein Mikrofon gefunden - der Anruf laeuft ohne Ton." to "No speaker and no microphone found - the call runs without sound.",
        "Kein Lautsprecher gefunden - du hoerst den Partner nicht." to "No speaker found - you cannot hear the partner.",
        "Kein Mikrofon gefunden - der Partner hoert dich nicht." to "No microphone found - the partner cannot hear you.",
        "Keine Kamera gefunden." to "No camera found.",
        "Die gewaehlte Kamera ist nicht angeschlossen." to "The selected camera is not connected.",
        "Die Kamera liefert keine Bilder mehr." to "The camera no longer delivers pictures.",
        "Die Kamera wurde getrennt." to "The camera was disconnected.",
        "Kamera konnte nicht geoeffnet werden (wird sie von einem anderen Programm benutzt?) *" to "Camera could not be opened (is another program using it?) *",
        "Die Kamera liefert kein passendes Bildformat *" to "The camera does not deliver a suitable picture format *",
        "Media Foundation nicht verfuegbar *" to "Media Foundation not available *",
        "angelegt" to "created",
        "vorhanden" to "exists",
        "entfernt" to "removed",
        "entfernt: *" to "removed: *",
        "Mikrofon wird von diesem Geraet nicht unterstuetzt." to "This device does not support the microphone.",
        "Mikrofon konnte nicht geoeffnet werden (Berechtigung?)." to "The microphone could not be opened (permission?).",
        "Audio konnte nicht gestartet werden: *" to "Sound could not be started: *",
        "Kamera getrennt." to "Camera disconnected.",
        "Kamera hat nicht geantwortet." to "The camera did not respond.",
        "Kamera konnte nicht geoeffnet werden." to "The camera could not be opened.",
        "Kamera-Fehler *" to "Camera error *",
        "Kamera-Anfrage fehlgeschlagen: *" to "Camera request failed: *",
        "Kamera-Sitzung konnte nicht erstellt werden." to "The camera session could not be created.",
        "Kamera-Sitzung: Zeitueberschreitung." to "Camera session: timeout.",
        "Kamerazugriff nicht moeglich: *" to "Camera access not possible: *",
        "Kamera konnte nicht gestartet werden: *" to "The camera could not be started: *",
        "Dateigroesse unbekannt." to "The size of the file is unknown.",
    )

    private val coreDe: Map<String, String> = linkedMapOf(
        "Schluessel werden abgeleitet ..." to "Schlüssel werden abgeleitet ...",
        "Server-Adresse nicht aufloesbar" to "Vermittler-Adresse lässt sich nicht auflösen",
        "Verbinde mit Vermittlungsserver ..." to "Verbinde mit dem Vermittler ...",
        "Server nicht erreichbar - bestehende Direktverbindungen bleiben aktiv" to "Vermittler nicht erreichbar - bestehende Direktverbindungen bleiben aktiv",
        "Fehler: *" to "Fehler: *",
        "P2P laeuft bereits." to "Die Verbindung läuft bereits.",
        "Der Lobby-Name muss mindestens 3 Zeichen haben." to "Der Sitzungsname muss mindestens 3 Zeichen haben.",
        "Das Lobby-Passwort muss mindestens 6 Zeichen haben." to "Das Sitzungs-Passwort muss mindestens 6 Zeichen haben.",
        "Kein Vermittlungsserver eingetragen." to "Kein Vermittler eingetragen.",
        "Server ausgelastet (zu viele Lobbys)." to "Der Vermittler ist ausgelastet (zu viele Sitzungen).",
        "Datei ist zu gross." to "Datei ist zu groß.",
        "Es laeuft bereits eine Uebertragung." to "Es läuft bereits eine Übertragung.",
        "vom Empfaenger abgebrochen" to "vom Empfänger abgebrochen",
        "Empfaenger meldet Fehler" to "Empfänger meldet einen Fehler",
        "mehr Daten als angekuendigt" to "mehr Daten als angekündigt",
        "Pruefsumme stimmt nicht" to "Prüfsumme stimmt nicht",
        "Kein Lautsprecher und kein Mikrofon gefunden - der Anruf laeuft ohne Ton." to "Kein Lautsprecher und kein Mikrofon gefunden - der Anruf läuft ohne Ton.",
        "Kein Lautsprecher gefunden - du hoerst den Partner nicht." to "Kein Lautsprecher gefunden - du hörst den Partner nicht.",
        "Kein Mikrofon gefunden - der Partner hoert dich nicht." to "Kein Mikrofon gefunden - der Partner hört dich nicht.",
        "Die gewaehlte Kamera ist nicht angeschlossen." to "Die gewählte Kamera ist nicht angeschlossen.",
        "Kamera konnte nicht geoeffnet werden (wird sie von einem anderen Programm benutzt?) *" to "Kamera konnte nicht geöffnet werden (wird sie von einem anderen Programm benutzt?) *",
        "Media Foundation nicht verfuegbar *" to "Media Foundation nicht verfügbar *",
        "Mikrofon wird von diesem Geraet nicht unterstuetzt." to "Mikrofon wird von diesem Gerät nicht unterstützt.",
        "Mikrofon konnte nicht geoeffnet werden (Berechtigung?)." to "Mikrofon konnte nicht geöffnet werden (Berechtigung?).",
        "Audio konnte nicht gestartet werden: *" to "Der Ton konnte nicht gestartet werden: *",
        "Kamera getrennt." to "Kamera getrennt.",
        "Kamera hat nicht geantwortet." to "Die Kamera hat nicht geantwortet.",
        "Kamera konnte nicht geoeffnet werden." to "Die Kamera konnte nicht geöffnet werden.",
        "Kamera-Fehler *" to "Kamera-Fehler *",
        "Kamera-Anfrage fehlgeschlagen: *" to "Kamera-Anfrage fehlgeschlagen: *",
        "Kamera-Sitzung konnte nicht erstellt werden." to "Die Kamera-Sitzung konnte nicht erstellt werden.",
        "Kamera-Sitzung: Zeitueberschreitung." to "Kamera-Sitzung: Zeitüberschreitung.",
        "Kamerazugriff nicht moeglich: *" to "Kamerazugriff nicht möglich: *",
        "Kamera konnte nicht gestartet werden: *" to "Die Kamera konnte nicht gestartet werden: *",
        "Dateigroesse unbekannt." to "Die Größe der Datei ist unbekannt.",
    )

    private val helpDe = listOf(
        Pair("Wozu", "Mit dieser App hilfst du jemandem live am Windows-PC: oben läuft der Video-Chat mit Ton, unten siehst du seinen Bildschirm und kannst ihn - wenn er es erlaubt - mit Maus und Tastatur bedienen. Dazu gibt es Textchat und Datei-Übertragung."),
        Pair("So geht es", "1. Adresse deines Vermittlers eintragen und \"Neuen Code erzeugen\" tippen.\n2. Mit \"Code senden\" den Einladungscode an den Kunden schicken (Messenger, E-Mail).\n3. \"Verbinden\" tippen und warten, bis der Kunde da ist. Er startet Project-Earth-Support am PC, fügt den Code ein und klickt auf Verbinden.\n4. \"Anrufen\" startet Bild und Ton. \"Bildschirm anfordern\" bittet um die Freigabe, \"Steuerung anfordern\" zusätzlich um Maus und Tastatur. Der Kunde muss jeweils zustimmen."),
        Pair("Bedienung des fernen Bildschirms", "Tippen = Linksklick, zweimal tippen = Doppelklick, lange drücken = Rechtsklick. Mit einem Finger ziehen = Maus ziehen (Fenster verschieben, markieren). Zwei Finger auseinanderziehen = vergrößern, im vergrößerten Bild mit zwei Fingern verschieben. Ohne Vergrößerung blättern zwei Finger hoch und runter (Mausrad). \"Tastatur\" schickt Text und Tasten wie Enter, Esc, Strg+C oder den Task-Manager. \"Vollbild\" zeigt nur den fernen Bildschirm - am besten quer halten."),
        Pair("Vermittler", "Der Vermittler bringt beide Seiten zusammen; danach läuft die Verbindung möglichst direkt. Er sieht nie Passwörter oder Inhalte. Du brauchst einen Vermittler, der aus dem Internet erreichbar ist: Project-Earth-Support auf einem PC starten, dort \"Vermittler\" öffnen und im Router den UDP-Port 9890 an diesen PC weiterleiten. Im selben WLAN genügt die Adresse dieses PCs. Ein vorhandener Project-Earth-LAN-Rendezvous-Server geht ebenfalls (Adresse:Port)."),
        Pair("Sicherheit", "Alles ist Ende-zu-Ende verschlüsselt (AES-256 + HMAC-SHA256); der Schlüssel entsteht aus dem Passwort im Einladungscode. Wer den Code hat, kann der Sitzung beitreten - also nur an die richtige Person schicken und für jede Sitzung einen neuen Code erzeugen. Bildschirm und Steuerung gibt es nur nach Zustimmung des Kunden; er kann beides jederzeit beenden. Dateien werden nur nach Zustimmung angenommen und mit SHA-256 geprüft. Der Einladungscode wird nur verschlüsselt im Android Keystore gespeichert. Die App lädt nichts nach und aktualisiert sich nicht selbst."),
        Pair("Gut zu wissen", "Die Kamera läuft nur, solange die App sichtbar ist. Der Ton läuft im Hintergrund weiter (sichtbare Benachrichtigung). Empfangene Dateien liegen unter Download/Project Earth Support. Ruckelt das Bild, stelle auf \"Sparsam\". Während einer Windows-Sicherheitsabfrage (UAC) oder am Sperrbildschirm des PCs gibt es kein Bild."),
    )

    private val helpEn = listOf(
        Pair("Purpose", "With this app you help someone live at a Windows PC: the video chat with sound is at the top, below you see the screen and - if the customer allows it - control it with mouse and keyboard. Text chat and file transfer are included."),
        Pair("How to", "1. Enter the address of your mediator and tap \"Create new code\".\n2. Use \"Send code\" to send the invitation code to the customer (messenger, e-mail).\n3. Tap \"Connect\" and wait for the customer, who starts Project-Earth-Support on the PC, pastes the code and clicks Connect.\n4. \"Call\" starts picture and sound. \"Request screen\" asks for the screen, \"Request control\" additionally for mouse and keyboard. The customer has to agree each time."),
        Pair("Using the remote screen", "Tap = left click, double tap = double click, long press = right click. Drag with one finger = drag the mouse (move windows, select). Spread two fingers = zoom, move the zoomed picture with two fingers. Without zoom two fingers up and down scroll (mouse wheel). \"Keyboard\" sends text and keys such as Enter, Esc, Ctrl+C or the Task Manager. \"Full screen\" shows only the remote screen - best held sideways."),
        Pair("Mediator", "The mediator brings both sides together; after that the connection runs directly whenever possible. It never sees passwords or content. You need a mediator that can be reached from the internet: start Project-Earth-Support on a PC, open \"Mediator\" there and forward UDP port 9890 to that PC in the router. In the same Wi-Fi the address of that PC is enough. An existing Project Earth LAN rendezvous server works as well (address:port)."),
        Pair("Security", "Everything is end-to-end encrypted (AES-256 + HMAC-SHA256); the key is derived from the password in the invitation code. Whoever has the code can join the session - so send it only to the right person and create a new code for every session. Screen and control are only available after the customer agrees and can be stopped by the customer at any time. Files are only accepted after consent and verified with SHA-256. The invitation code is only stored encrypted in the Android Keystore. The app downloads nothing and never updates itself."),
        Pair("Good to know", "The camera only runs while the app is visible. Sound continues in the background (visible notification). Received files are under Download/Project Earth Support. If the picture stutters, switch to \"Economy\". During a Windows security prompt (UAC) or on the PC's lock screen there is no picture."),
    )
}
