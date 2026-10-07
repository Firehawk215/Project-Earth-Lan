package de.projectearth.support.android

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.net.Uri
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import de.projectearth.support.core.PesBytes
import de.projectearth.support.core.PesP2pEngine
import de.projectearth.support.core.PesProto
import de.projectearth.support.core.PesSession
import java.io.File
import java.io.FileInputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.LinkedBlockingQueue

/** Eine Zeile im Verlauf. kind: 0 = System, 1 = ich, 2 = Partner, 3 = Warnung, 4 = Fehler */
class ChatLine(val time: String, val who: String, val text: String, val kind: Int)

class FileOfferUi(val name: String, val size: Long)

class UiState(
    val active: Boolean = false,
    val starting: Boolean = false,
    val engineState: String = "",
    val ownIp: String = "",
    val lastError: String = "",
    val paired: Boolean = false,
    val partnerName: String = "",
    val partnerPlatform: Int = 0,
    val path: Int = 0,
    val rtt: Int = -1,
    val callState: Int = 0,
    val partnerCam: Boolean = false,
    val micOn: Boolean = true,
    val camOn: Boolean = false,
    val camFront: Boolean = true,
    val speaker: Boolean = true,
    val mediaMsg: String = "",
    val share: Boolean = false,
    val control: Boolean = false,
    val viewWanted: Boolean = false,
    val monitors: Int = 1,
    val monitor: Int = 0,
    val quality: Int = 2,
    val chatVersion: Int = 0,
    val fileText: String = "",
    val fileOffer: FileOfferUi? = null,
    val screenVersion: Int = 0,
    val remoteVideoVersion: Int = 0,
    val selfVideoVersion: Int = 0,
    val hasRemoteVideo: Boolean = false,
    val invite: String = "",
)

/**
 * Laufzeit der App: haelt Engine und Sitzung, Ton und Kamera, das zusammengesetzte Fernbild und den Verlauf.
 * Die Oberflaeche fragt nur [snapshot] ab und ruft die Aktionen auf; nichts hier blockiert den Oberflaechen-Thread lange.
 */
object SupRuntime {
    const val CH_STATUS = "pes_status"
    const val CH_CALL = "pes_call"
    const val CH_EVENTS = "pes_events"
    const val NOTIF_STATUS = 1
    const val NOTIF_CALL = 7001
    const val NOTIF_EVENT = 7100
    const val EXTRA_CALL = "pes_call"
    const val EXTRA_CALL_ACCEPT = "pes_call_accept"

    lateinit var app: Context
        private set
    @Volatile var uiVisible = false

    @Volatile private var engine: PesP2pEngine? = null
    @Volatile private var session: PesSession? = null
    @Volatile var starting = false
        private set
    @Volatile var lastError = ""
        private set
    @Volatile private var pending: Triple<String, String, String>? = null      // Server, Lobby, Passwort
    @Volatile private var pendingName = ""
    @Volatile private var currentInvite = ""

    val chat = CopyOnWriteArrayList<ChatLine>()
    @Volatile private var chatVersion = 0
    private val timeFmt = SimpleDateFormat("HH:mm", Locale.ROOT)

    // Fernbild (wird aus JPEG-Rechtecken zusammengesetzt)
    val screenLock = Any()
    var screenBitmap: Bitmap? = null
        private set
    @Volatile var screenVersion = 0
        private set
    private val rectQueue = LinkedBlockingQueue<Pair<IntArray, ByteArray>>(3000)
    @Volatile private var viewWanted = false
    @Volatile private var controlWanted = false
    @Volatile private var shareSeen = false
    @Volatile private var lastShareKey = ""
    @Volatile var quality = 2
        private set
    @Volatile var monitor = 0
        private set

    // Video
    val videoLock = Any()
    var remoteFrame: Bitmap? = null
        private set
    @Volatile var remoteRot = 0
        private set
    @Volatile var remoteVideoVersion = 0
        private set
    var selfFrame: Bitmap? = null
        private set
    @Volatile var selfRot = 0
        private set
    @Volatile var selfVideoVersion = 0
        private set

    // Ton und Kamera
    @Volatile private var audio: CallAudio? = null
    @Volatile private var cam: CamCapture? = null
    @Volatile var wantMic = true
        private set
    @Volatile var wantCam = false
        private set
    @Volatile var camFront = true
        private set
    @Volatile var speaker = true
        private set
    @Volatile private var mediaMsg = ""
    @Volatile private var displayDeg = 0
    @Volatile private var fileOffer: FileOfferUi? = null
    @Volatile private var ringing = false

    val isActive: Boolean get() = session != null || starting
    val audioActive: Boolean get() = audio?.isRunning == true
    fun currentSession(): PesSession? = session
    fun settings(): SupSettings = SupSettingsStore.load(app)
    private fun downloadDir(): File = File(app.filesDir, "incoming").also { it.mkdirs() }

    fun init(ctx: Context) {
        app = ctx.applicationContext
        SupLog.init(app)
        val s = settings()
        Tr.setLanguage(s.lang)
        quality = s.quality
        createChannels()
        Thread({ pollLoop() }, "pes-poll").also { it.isDaemon = true }.start()
        Thread({ rectLoop() }, "pes-rects").also { it.isDaemon = true }.start()
    }

    private fun createChannels() {
        val nm = app.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CH_STATUS, "Verbindungsstatus / Connection status", NotificationManager.IMPORTANCE_LOW))
        nm.createNotificationChannel(NotificationChannel(CH_EVENTS, "Nachrichten und Dateien / Messages and files", NotificationManager.IMPORTANCE_DEFAULT))
        // Eingehende Anrufe: hohe Wichtigkeit (Popup); der Klingelton kommt von der App selbst
        val call = NotificationChannel(CH_CALL, "Eingehende Anrufe / Incoming calls", NotificationManager.IMPORTANCE_HIGH)
        call.setSound(null, null)
        call.enableVibration(true)
        call.vibrationPattern = longArrayOf(0, 600, 400, 600)
        call.lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        nm.createNotificationChannel(call)
    }

    private fun now() = timeFmt.format(Date())

    private fun addLine(who: String, text: String, kind: Int) {
        chat.add(ChatLine(now(), who, text, kind))
        while (chat.size > 300) chat.removeAt(0)
        chatVersion++
        if (kind != 1 && kind != 2) SupLog.w(text)
    }

    private fun sys(text: String, kind: Int = 0) = addLine("", text, kind)

    // =========================================================================
    // Verbinden / Trennen
    // =========================================================================
    /** Neuen Einladungscode erzeugen (Lobby und Passwort zufaellig, Passwort 24 Zeichen). Liefert den Code oder null bei ungueltiger Adresse. */
    fun newInvite(serverText: String): String? {
        val sv = PesProto.parseServer(serverText) ?: return null
        val server = if (sv.second == PesProto.DEFAULT_SERVER_PORT) sv.first else sv.first + ":" + sv.second
        val s = settings()
        SupSettingsStore.save(app, SupSettings(s.name, s.inviteEnc, s.remember, serverText.trim(), s.machineKey, s.lang, s.quality))
        return PesProto.inviteCreate(server, PesProto.newLobby(), PesProto.newPassword())
    }

    /** Liefert null bei Erfolg, sonst eine Fehlermeldung. Der eigentliche Aufbau laeuft im Dienst. */
    fun requestConnect(inviteText: String, name: String, remember: Boolean): String? {
        if (isActive) return null
        val nm = name.trim()
        if (nm.isEmpty()) return Tr.t("Bitte einen Namen eintragen.")
        val inv = PesProto.inviteParse(inviteText) ?: return Tr.t("Der Einladungscode ist ungültig. Er beginnt mit \"PES1:\".")
        PesProto.parseServer(inv.server) ?: return Tr.t("Die Vermittler-Adresse im Einladungscode ist ungültig.")
        val s = settings()
        val enc = if (remember) SupSecret.encrypt(inviteText.trim()) else ""
        SupSettingsStore.save(app, SupSettings(nm, enc, remember, s.server, s.machineKey, s.lang, s.quality))
        pending = Triple(inv.server, inv.lobby, inv.password)
        pendingName = nm
        currentInvite = inviteText.trim()
        lastError = ""
        starting = true
        chat.clear(); chatVersion++
        try {
            ContextCompat.startForegroundService(app, Intent(app, SupService::class.java).setAction(SupService.ACTION_START))
        } catch (e: Exception) {
            starting = false
            SupLog.e("Dienst starten", e)
            return Tr.t("Die Verbindung konnte nicht gestartet werden:") + " " + e.message
        }
        return null
    }

    fun requestDisconnect() {
        try { app.startService(Intent(app, SupService::class.java).setAction(SupService.ACTION_STOP)) } catch (e: Exception) { SupLog.e("Dienst stoppen", e) }
    }

    /** Laeuft im Dienst-Thread (Schluesselableitung dauert einen Moment). */
    fun startSessionBlocking() {
        val p = pending ?: run { starting = false; return }
        pending = null
        val e = PesP2pEngine()
        try {
            val sv = PesProto.parseServer(p.first)!!
            e.logSink = { SupLog.w("P2P " + it) }
            val s = PesSession(e)
            s.myName = pendingName
            s.role = PesProto.ROLE_HELPER
            s.platform = 2
            s.downloadDir = downloadDir()
            s.onScreenRect = { r, j -> if (!rectQueue.offer(Pair(r, j))) { rectQueue.clear(); s.requestScreen(5) } }
            s.onVideoFrame = { j, rot -> onRemoteVideo(j, rot) }
            sys(Tr.t("Verbinde mit dem Vermittler {0} ...", sv.first + ":" + sv.second))
            e.start(sv.first, sv.second, p.second, p.third, pendingName, settings().machineKey)
            s.start()
            engine = e
            session = s
            sys(Tr.t("Sitzung gestartet. Schicke dem Kunden den Einladungscode."))
        } catch (ex: Exception) {
            SupLog.e("Verbinden", ex)
            lastError = Tr.core(ex.message ?: "Fehler")
            try { e.stop() } catch (_: Exception) {}
            engine = null; session = null
        } finally {
            starting = false
        }
    }

    fun stopSessionBlocking() {
        stopCamera()
        stopAudio()
        SupRinger.stop()
        try { NotificationManagerCompat.from(app).cancel(NOTIF_CALL) } catch (_: Exception) {}
        val s = session
        val e = engine
        session = null; engine = null
        try { s?.stop() } catch (_: Exception) {}
        try { e?.stop() } catch (_: Exception) {}
        viewWanted = false; controlWanted = false; shareSeen = false; lastShareKey = ""
        fileOffer = null; ringing = false; starting = false
        rectQueue.clear()
        synchronized(screenLock) { screenBitmap = null; screenVersion++ }
        synchronized(videoLock) { remoteFrame = null; selfFrame = null; remoteVideoVersion++; selfVideoVersion++ }
        sys(Tr.t("Getrennt."))
    }

    // =========================================================================
    // Ereignisse der Sitzung
    // =========================================================================
    private fun pollLoop() {
        var tick = 0
        while (true) {
            try {
                val s = session
                if (s != null) {
                    while (true) { val ev = s.events.poll() ?: break; try { handleEvent(s, ev) } catch (e: Exception) { SupLog.e("Ereignis", e) } }
                    val cs = s.callState
                    // Klingeln, solange ein Anruf eingeht
                    if (cs == PesProto.CALL_IN && !ringing) { ringing = true; SupRinger.start(app); notifyIncomingCall(s.partnerName) }
                    if (cs != PesProto.CALL_IN && ringing) { ringing = false; SupRinger.stop(); try { NotificationManagerCompat.from(app).cancel(NOTIF_CALL) } catch (_: Exception) {} }
                    // Kamera nur bei sichtbarer App und laufendem Anruf
                    if (cs != PesProto.CALL_ACTIVE && (cam != null || wantCam)) { stopCamera(); wantCam = false }
                    if (cs == PesProto.CALL_ACTIVE) {
                        val camOn = cam?.isRunning == true
                        if (s.myCam != camOn || s.myMic != wantMic) s.setMedia(camOn, wantMic)
                    }
                    if (tick % 10 == 0 && (cs == PesProto.CALL_ACTIVE) != audioActive) {
                        // Ton startet/stoppt im Dienst (dort darf der Mikrofon-Typ des Vordergrunddienstes gesetzt werden)
                        try { app.startService(Intent(app, SupService::class.java).setAction(SupService.ACTION_SYNC)) } catch (_: Exception) {}
                    }
                } else if (ringing) { ringing = false; SupRinger.stop() }
            } catch (e: Exception) {
                SupLog.e("Abfrage", e)
            }
            tick++
            try { Thread.sleep(100) } catch (_: InterruptedException) { return }
        }
    }

    private fun handleEvent(s: PesSession, line: String) {
        val f = line.split(PesProto.SEP)
        when (f[0]) {
            "PEER" -> if (f[1] == "up") {
                val plat = if (f.getOrNull(4) == "2") "Android" else "Windows"
                sys(Tr.t("{0} ist verbunden ({1}).", f[2], plat), 3)
                if (!uiVisible) notifyEvent(Tr.t("{0} ist verbunden ({1}).", f[2], plat))
            } else {
                sys(Tr.t("{0} ist nicht mehr verbunden.", f[2]) + " " + Tr.core(f.getOrElse(3) { "" }), 3)
                viewWanted = false; controlWanted = false; shareSeen = false; lastShareKey = ""; fileOffer = null
                rectQueue.clear()
                synchronized(screenLock) { screenBitmap = null; screenVersion++ }
                synchronized(videoLock) { remoteFrame = null; remoteVideoVersion++ }
            }
            "CHAT" -> { addLine(f[1], f.getOrElse(2) { "" }, 2); if (!uiVisible) notifyEvent(f[1] + ": " + f.getOrElse(2) { "" }) }
            "CALL" -> when (f[1]) {
                "out" -> sys(Tr.t("Anruf gestartet ..."))
                "active" -> sys(Tr.t("Anruf verbunden."))
                "declined" -> sys(Tr.t("Der Partner hat den Anruf abgelehnt."))
                "ended" -> { sys(Tr.t("Anruf beendet.")); synchronized(videoLock) { remoteFrame = null; remoteVideoVersion++ } }
                "missed" -> sys(Tr.t("Verpasster Anruf."))
                "timeout" -> sys(Tr.t("Der Partner hat nicht abgenommen."))
            }
            "SCREEN" -> if (f[1] == "state") {
                val key = f[2] + f[3]
                if (key == lastShareKey) return
                lastShareKey = key
                if (f[2] == "1") {
                    if (f[3] == "1") sys(Tr.t("Der Kunde überträgt seinen Bildschirm - Steuerung erlaubt."))
                    else if (controlWanted && shareSeen) sys(Tr.t("Der Kunde erlaubt die Steuerung nicht (nur ansehen)."))
                    else sys(Tr.t("Der Kunde überträgt seinen Bildschirm - nur ansehen."))
                    shareSeen = true; controlWanted = false
                } else {
                    if (viewWanted && !shareSeen) sys(Tr.t("Der Kunde hat die Anfrage abgelehnt."))
                    else sys(Tr.t("Der Kunde überträgt seinen Bildschirm nicht mehr."))
                    viewWanted = false; controlWanted = false; shareSeen = false
                    rectQueue.clear()
                    synchronized(screenLock) { screenBitmap = null; screenVersion++ }
                }
            }
            "FILE" -> when (f[1]) {
                "offer" -> {
                    fileOffer = FileOfferUi(f[3], f[4].toLongOrNull() ?: 0L)
                    if (!uiVisible) notifyEvent(Tr.t("{0} möchte eine Datei senden: {1}", s.partnerName, f[3]))
                }
                "sending" -> sys(Tr.t("Sende Datei: {0}", f[2]))
                "declined" -> sys(Tr.t("Der Partner hat die Datei abgelehnt: {0}", f[2]))
                "sent" -> sys(Tr.t("Datei gesendet und geprüft: {0}", f[2]))
                "received" -> exportToDownloads(f[2], File(f[3]))
                "failed" -> sys(Tr.t("Datei-Übertragung abgebrochen: {0}", f[2]) + " (" + Tr.core(f.getOrElse(3) { "" }) + ")", 4)
                "withdrawn" -> { fileOffer = null; sys(Tr.t("Das Datei-Angebot wurde zurückgezogen: {0}", f[2])) }
            }
            "SYS" -> sys(f.getOrElse(1) { "" }, 4)
        }
    }

    // =========================================================================
    // Chat und Dateien
    // =========================================================================
    fun sendChat(text: String) {
        val t = text.trim()
        if (t.isEmpty()) return
        val s = session ?: return
        if (s.sendChat(t)) addLine(Tr.t("Ich"), t, 1)
    }

    fun sendFile(uri: Uri): String? {
        val s = session ?: return Tr.t("Nicht verbunden.")
        var name = "datei"
        var size = -1L
        try {
            app.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val ni = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val si = c.getColumnIndex(OpenableColumns.SIZE)
                    if (ni >= 0 && !c.isNull(ni)) name = c.getString(ni)
                    if (si >= 0 && !c.isNull(si)) size = c.getLong(si)
                }
            }
        } catch (e: Exception) { SupLog.e("Datei-Infos", e) }
        if (size < 0) return Tr.t("Die Größe der Datei ist unbekannt.")
        val err = s.offerFile(name, size) { app.contentResolver.openInputStream(uri) ?: throw java.io.IOException("Datei nicht lesbar") }
        if (err != null) return Tr.core(err)
        sys(Tr.t("Datei angeboten: {0} - warte auf die Zustimmung des Partners.", name))
        return null
    }

    fun answerFile(accept: Boolean) {
        val o = fileOffer ?: return
        fileOffer = null
        val s = session ?: return
        val err = s.answerFile(accept)
        if (accept && err == null) sys(Tr.t("Empfange Datei: {0}", o.name))
        else if (err != null) sys(Tr.t("Datei kann nicht empfangen werden:") + " " + Tr.core(err), 4)
    }

    /** Kopiert eine fertig empfangene Datei nach Download/Project Earth Support und entfernt die private Kopie. */
    private fun exportToDownloads(name: String, src: File) {
        try {
            val ext = name.substringAfterLast('.', "").lowercase(Locale.ROOT)
            val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "application/octet-stream"
            val cv = ContentValues()
            cv.put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            cv.put(MediaStore.MediaColumns.MIME_TYPE, mime)
            cv.put(MediaStore.MediaColumns.RELATIVE_PATH, "Download/Project Earth Support")
            cv.put(MediaStore.MediaColumns.IS_PENDING, 1)
            val res = app.contentResolver
            val uri = res.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, cv) ?: throw IllegalStateException("MediaStore lieferte keinen Eintrag")
            try {
                res.openOutputStream(uri)!!.use { out -> FileInputStream(src).use { it.copyTo(out, 256 * 1024) } }
                val done = ContentValues()
                done.put(MediaStore.MediaColumns.IS_PENDING, 0)
                res.update(uri, done, null, null)
            } catch (e: Exception) {
                try { res.delete(uri, null, null) } catch (_: Exception) {}
                throw e
            }
            src.delete()
            sys(Tr.t("Datei empfangen und geprüft: {0}", "Download/Project Earth Support/$name"))
        } catch (e: Exception) {
            SupLog.e("Export nach Download fehlgeschlagen ($name)", e)
            sys(Tr.t("Datei {0} liegt in der App, das Speichern unter Download ist fehlgeschlagen.", name), 4)
        }
    }

    // =========================================================================
    // Anruf, Ton, Kamera
    // =========================================================================
    fun hasMicPermission(): Boolean = ContextCompat.checkSelfPermission(app, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
    fun hasCamPermission(): Boolean = ContextCompat.checkSelfPermission(app, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    fun call() { session?.call() }
    fun answerCall(accept: Boolean) { session?.answerCall(accept) }
    fun hangup() { session?.hangup() }
    fun setMic(on: Boolean) { wantMic = on }
    fun setSpeaker(on: Boolean) { speaker = on; audio?.setSpeaker(on) }

    /** Ton passend zum Anruf starten oder stoppen (wird vom Dienst aufgerufen). */
    fun syncAudio() {
        val s = session
        val need = s != null && s.callState == PesProto.CALL_ACTIVE
        if (need && audio == null) {
            if (!hasMicPermission()) { mediaMsg = Tr.t("Ohne Mikrofon-Berechtigung hört dich der Partner nicht."); return }
            val a = CallAudio(s!!)
            val err = a.start(app, speaker)
            if (err != null) { mediaMsg = Tr.core(err); SupLog.w(err) } else { audio = a; mediaMsg = "" }
        } else if (!need && audio != null) stopAudio()
    }

    fun stopAudio() {
        val a = audio
        audio = null
        try { a?.stop() } catch (_: Exception) {}
    }

    /** Liefert null bei Erfolg, sonst eine Fehlermeldung. */
    fun startCamera(deg: Int): String? {
        val s = session ?: return Tr.t("Nicht verbunden.")
        if (s.callState != PesProto.CALL_ACTIVE) return Tr.t("Die Kamera läuft nur während eines Anrufs.")
        if (!hasCamPermission()) return Tr.t("Ohne Kamera-Berechtigung ist kein Video möglich.")
        if (cam?.isRunning == true) return null
        displayDeg = deg
        val c = CamCapture { jpeg, rot ->
            s.sendVideo(jpeg, rot)
            // Eigenansicht: jedes Bild klein dekodieren
            try {
                val b = BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size)
                if (b != null) synchronized(videoLock) { selfFrame = b; selfRot = rot; selfVideoVersion++ }
            } catch (_: Exception) {}
        }
        val err = c.start(app, camFront, deg)
        if (err != null) { wantCam = false; return Tr.core(err) }
        cam = c
        wantCam = true
        return null
    }

    fun stopCamera() {
        val c = cam
        cam = null
        try { c?.stop() } catch (_: Exception) {}
        synchronized(videoLock) { if (selfFrame != null) { selfFrame = null; selfVideoVersion++ } }
    }

    fun setCamOff() { wantCam = false; stopCamera() }

    fun switchCamera(): String? {
        camFront = !camFront
        if (cam == null) return null
        stopCamera()
        return startCamera(displayDeg)
    }

    private fun onRemoteVideo(jpeg: ByteArray, rot: Int) {
        try {
            val b = BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size) ?: return
            if (b.width > 4096 || b.height > 4096) return
            synchronized(videoLock) { remoteFrame = b; remoteRot = rot; remoteVideoVersion++ }
        } catch (_: Throwable) {}
    }

    private fun notifyIncomingCall(name: String) {
        if (uiVisible) return   // App ist offen: der Anrufbildschirm erscheint dort direkt
        try {
            val nm = NotificationManagerCompat.from(app)
            if (!nm.areNotificationsEnabled()) return
            val open = Intent(app, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP).putExtra(EXTRA_CALL, true)
            val fl = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            val full = PendingIntent.getActivity(app, 7001, open, fl)
            val accept = PendingIntent.getActivity(app, 7002, Intent(open).putExtra(EXTRA_CALL_ACCEPT, true), fl)
            val decline = PendingIntent.getBroadcast(app, 7003, Intent(app, SupCallReceiver::class.java), fl)
            val who = androidx.core.app.Person.Builder().setName(name).setImportant(true).build()
            val n = NotificationCompat.Builder(app, CH_CALL).setSmallIcon(R.drawable.ic_stat)
                .setContentTitle(name)
                .setContentText(Tr.t("Eingehender Anruf"))
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setOngoing(true).setAutoCancel(false)
                .setTimeoutAfter(50000)
                .setContentIntent(full)
                .setFullScreenIntent(full, true)
                .setStyle(NotificationCompat.CallStyle.forIncomingCall(who, decline, accept))
                .build()
            nm.notify(NOTIF_CALL, n)
        } catch (_: SecurityException) {
        } catch (e: Exception) { SupLog.e("Anruf-Benachrichtigung", e) }
    }

    private fun notifyEvent(text: String) {
        try {
            val nm = NotificationManagerCompat.from(app)
            if (!nm.areNotificationsEnabled()) return
            val open = PendingIntent.getActivity(app, 7100, Intent(app, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            val n = NotificationCompat.Builder(app, CH_EVENTS).setSmallIcon(R.drawable.ic_stat).setContentTitle("Project Earth Support")
                .setContentText(text).setAutoCancel(true).setContentIntent(open).build()
            nm.notify(NOTIF_EVENT, n)
        } catch (_: SecurityException) {
        } catch (e: Exception) { SupLog.e("Benachrichtigung", e) }
    }

    // =========================================================================
    // Fernwartung
    // =========================================================================
    fun requestView() {
        val s = session ?: return
        sendOptions()
        s.requestScreen(1)
        viewWanted = true
        sys(Tr.t("Bildschirm angefordert - der Kunde muss zustimmen."))
    }

    fun requestControl() {
        val s = session ?: return
        sendOptions()
        s.requestScreen(2)
        viewWanted = true; controlWanted = true
        sys(Tr.t("Steuerung angefordert - der Kunde muss zustimmen."))
    }

    fun releaseControl() { session?.requestScreen(4); controlWanted = false }

    fun stopView() {
        session?.requestScreen(3)
        viewWanted = false; controlWanted = false
    }

    fun setQuality(q: Int) {
        quality = q.coerceIn(1, 3)
        val s = settings()
        SupSettingsStore.save(app, SupSettings(s.name, s.inviteEnc, s.remember, s.server, s.machineKey, s.lang, quality))
        sendOptions()
    }

    fun setMonitor(m: Int) { monitor = maxOf(0, m); sendOptions() }

    private fun sendOptions() { session?.setScreenOptions(quality, monitor) }

    fun inputMove(x: Int, y: Int) { session?.inputMove(x, y) }
    fun inputButton(button: Int, down: Boolean, x: Int, y: Int) { session?.inputButton(button, down, x, y) }
    fun inputClick(button: Int, x: Int, y: Int) { val s = session ?: return; s.inputButton(button, true, x, y); s.inputButton(button, false, x, y) }
    fun inputWheel(delta: Int, x: Int, y: Int) { session?.inputWheel(delta, x, y) }
    fun inputText(t: String) { session?.inputText(t) }

    /** Taste oder Tastenfolge (Windows-Tastencodes): alle druecken, in umgekehrter Reihenfolge loslassen. */
    fun inputKeys(vararg vks: Int) {
        val s = session ?: return
        for (vk in vks) s.inputKey(vk, true, vk == 0x5B || vk in 0x21..0x28 || vk == 0x2E)
        for (i in vks.indices.reversed()) s.inputKey(vks[i], false, vks[i] == 0x5B || vks[i] in 0x21..0x28 || vks[i] == 0x2E)
    }

    /** Setzt die empfangenen JPEG-Rechtecke im eigenen Thread zum Fernbild zusammen. */
    private fun rectLoop() {
        val opts = BitmapFactory.Options()
        while (true) {
            try {
                val it = rectQueue.take()
                val r = it.first
                val part = BitmapFactory.decodeByteArray(it.second, 0, it.second.size, opts) ?: continue
                if (part.width != r[4] || part.height != r[5]) { part.recycle(); continue }   // Bild passt nicht zur Ankuendigung
                synchronized(screenLock) {
                    var b = screenBitmap
                    if (b == null || b.width != r[0] || b.height != r[1]) {
                        b = Bitmap.createBitmap(r[0], r[1], Bitmap.Config.ARGB_8888)
                        screenBitmap = b
                    }
                    Canvas(b!!).drawBitmap(part, r[2].toFloat(), r[3].toFloat(), null)
                    screenVersion++
                }
                part.recycle()
            } catch (_: InterruptedException) {
                return
            } catch (e: Throwable) {
                SupLog.w("Fernbild: " + e.message)
            }
        }
    }

    // =========================================================================
    // Zustand fuer die Oberflaeche
    // =========================================================================
    fun statusText(): String {
        val s = session ?: return if (starting) Tr.t("Verbinde ...") else Tr.t("Getrennt.")
        return if (s.paired) Tr.t("Verbunden mit {0}", s.partnerName) else Tr.t("Warte auf den Kunden ...")
    }

    fun snapshot(): UiState {
        val e = engine
        val s = session
        if (e == null || s == null) return UiState(starting = starting, lastError = lastError, chatVersion = chatVersion, camFront = camFront, speaker = speaker, micOn = wantMic, quality = quality, invite = currentInvite)
        var path = 0
        var rtt = -1
        if (s.paired) {
            val pv = s.partnerVip
            for (p in e.getPeers()) if (p.vip == pv) { path = p.path; rtt = p.rttMs }
        }
        var ft = ""
        val tx = s.txFile()
        val rx = s.rxFile()
        if (tx != null && (tx.state == 1 || tx.state == 4)) ft = Tr.t("Sende {0}: {1} von {2}", tx.name, fmtBytes(tx.done), fmtBytes(tx.size))
        else if (rx != null && rx.state == 1) ft = Tr.t("Empfange {0}: {1} von {2}", rx.name, fmtBytes(rx.done), fmtBytes(rx.size))
        else if (tx != null && tx.state == 0) ft = Tr.t("Warte auf Zustimmung: {0}", tx.name)
        return UiState(
            active = true, starting = starting, engineState = Tr.core(e.state), ownIp = e.assignedIp, lastError = e.lastError,
            paired = s.paired, partnerName = s.partnerName, partnerPlatform = s.partnerPlatform, path = path, rtt = rtt,
            callState = s.callState, partnerCam = s.partnerCam, micOn = wantMic, camOn = cam?.isRunning == true, camFront = camFront, speaker = speaker,
            mediaMsg = mediaMsg, share = s.shareActive, control = s.controlActive, viewWanted = viewWanted,
            monitors = maxOf(1, s.screenMonitors), monitor = monitor, quality = quality, chatVersion = chatVersion, fileText = ft, fileOffer = fileOffer,
            screenVersion = screenVersion, remoteVideoVersion = remoteVideoVersion, selfVideoVersion = selfVideoVersion,
            hasRemoteVideo = s.videoAgeMs < 2500, invite = currentInvite,
        )
    }

    fun fmtBytes(b: Long): String = when {
        b >= 1L shl 30 -> String.format(Locale.ROOT, "%.2f GB", b / 1073741824.0)
        b >= 1L shl 20 -> String.format(Locale.ROOT, "%.1f MB", b / 1048576.0)
        b >= 1L shl 10 -> String.format(Locale.ROOT, "%d KB", b / 1024)
        else -> "$b B"
    }

    fun ipText(ip: Int): String = PesBytes.ipToString(ip)
}
