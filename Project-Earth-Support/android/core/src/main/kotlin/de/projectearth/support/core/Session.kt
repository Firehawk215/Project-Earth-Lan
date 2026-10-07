package de.projectearth.support.core

import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

class PesFileInfo(val id: Int, val name: String, val size: Long) {
    @Volatile var path: String = ""
    @Volatile var done: Long = 0
    /** 0 = wartet auf Antwort, 1 = laeuft, 2 = fertig, 3 = abgebrochen/Fehler, 4 = gesendet, wartet auf Bestaetigung */
    @Volatile var state: Int = 0
    @Volatile var error: String = ""
}

/**
 * Sitzungsschicht der Fernwartung - 1:1 passend zu PesSession in Project-Earth-Support.ps1:
 * Partnersuche (HELLO), Anruf, Ton, Video, Bildschirm, Eingaben, Chat, Dateien.
 * Eingehenden Daten wird nie vertraut: Laengen, Zustaende und Absender werden geprueft.
 */
class PesSession(private val engine: PesP2pEngine) {
    // ---- Einstellungen (vor start() setzen) ----
    @Volatile var myName: String = ""
    @Volatile var role: Int = PesProto.ROLE_HELPER
    @Volatile var platform: Int = 2                      // 1 = Windows, 2 = Android
    @Volatile var downloadDir: File? = null
    @Volatile var maxFileSize: Long = 4L * 1024 * 1024 * 1024

    // ---- Rueckrufe (kommen aus Arbeits-Threads, muessen schnell sein) ----
    @Volatile var onVideoFrame: ((ByteArray, Int) -> Unit)? = null          // JPEG, Drehung 0..3
    @Volatile var onScreenRect: ((IntArray, ByteArray) -> Unit)? = null     // { sw, sh, x, y, w, h, fl }, JPEG
    @Volatile var onInput: ((ByteArray) -> Unit)? = null                    // Eingabe vom Helfer (nur bei erlaubter Steuerung)

    /** Ereignisse fuer die Oberflaeche: Felder mit [PesProto.SEP] getrennt. */
    val events = ConcurrentLinkedQueue<String>()

    // ---- Zustand ----
    @Volatile var paired = false; private set
    @Volatile var partnerName = ""; private set
    @Volatile var partnerRole = 0; private set
    @Volatile var partnerPlatform = 0; private set
    @Volatile var partnerVip = 0; private set
    @Volatile var callState = PesProto.CALL_IDLE; private set
    @Volatile var partnerCam = false; private set
    @Volatile var partnerMic = false; private set
    @Volatile var myCam = false; private set
    @Volatile var myMic = true; private set
    @Volatile var shareActive = false; private set
    @Volatile var controlActive = false; private set
    @Volatile var screenW = 0; private set
    @Volatile var screenH = 0; private set
    @Volatile var screenMonitor = 0; private set
    @Volatile var screenMonitors = 0; private set
    @Volatile var wantQuality = 2; private set
    @Volatile var wantMonitor = 0; private set
    private val lastVideoRx = AtomicLong(0)
    private val lastAudioRx = AtomicLong(0)

    private val lk = Any()
    private val rel = arrayOf(PesRel(0), PesRel(1), PesRel(2))
    private val clockOrigin = System.nanoTime()
    private var thread: Thread? = null
    @Volatile private var running = false
    private var mySid = 0
    private var partnerSid = 0
    private var handshake = false
    private var lastHelloTx = -100000L
    private var lastPartnerRx = 0L
    private var callSince = 0L
    private val ipId = AtomicInteger(0)
    private val audioSeq = AtomicInteger(0)
    private val videoSeq = AtomicInteger(0)
    private var ptrX = -1
    private var ptrY = -1
    private var ptrDirty = false
    private var lastPtrTx = 0L
    // Ton
    private val jitter = java.util.ArrayDeque<ShortArray>()
    private var jitterPlaying = false
    // Video-Empfang
    private var vSeq = -1
    private var vCount = 0
    private var vGot = 0
    private var vBytes = 0
    private var vParts: Array<ByteArray?>? = null
    // Dateien
    private var txFile: PesFileInfo? = null
    private var rxFile: PesFileInfo? = null
    private var txStream: InputStream? = null
    private var rxStream: FileOutputStream? = null
    private var txHash: MessageDigest? = null
    private var rxHash: MessageDigest? = null
    private var txOpen: (() -> InputStream)? = null
    private var rxTemp: File? = null

    private fun now(): Long = (System.nanoTime() - clockOrigin) / 1_000_000L + 1
    val videoAgeMs: Long get() { val t = lastVideoRx.get(); return if (t == 0L) Long.MAX_VALUE else now() - t }
    val audioAgeMs: Long get() { val t = lastAudioRx.get(); return if (t == 0L) Long.MAX_VALUE else now() - t }
    val screenBacklog: Long get() = synchronized(lk) { rel[2].backlog }
    val retransmits: Long get() = synchronized(lk) { rel[0].retransmits + rel[1].retransmits + rel[2].retransmits }
    val rtt: Int get() = synchronized(lk) { rel[0].rtt }
    val isRunning: Boolean get() = running

    private fun ev(vararg f: String) {
        events.add(f.joinToString(PesProto.SEP.toString()))
        while (events.size > 2000) events.poll()
    }

    fun start() {
        if (running) return
        val rng = SecureRandom()
        do { mySid = rng.nextInt() } while (mySid == 0)
        myName = PesProto.cleanName(myName, 32)
        running = true
        engine.inboundSink = { onIp(it) }
        thread = Thread({ loop() }, "PES-SESSION").also { it.isDaemon = true; it.start() }
    }

    fun stop() {
        if (!running) return
        try { if (callState != PesProto.CALL_IDLE) hangup() } catch (_: Exception) {}
        try { synchronized(lk) { flushLocked(now()) } } catch (_: Exception) {}
        try { if (paired) { sendBye(); Thread.sleep(30); sendBye() } } catch (_: Exception) {}
        running = false
        try { thread?.join(1500) } catch (_: InterruptedException) {}
        engine.inboundSink = null
        synchronized(lk) { unpair("", false) }
    }

    // =========================================================================
    // Senden (roh)
    // =========================================================================
    private fun sendRaw(dst: Int, payload: ByteArray) {
        val my = engine.vip
        if (my == 0 || dst == 0) return
        engine.sendIp(PesProto.wrap(my, dst, ipId.incrementAndGet(), payload))
    }

    private fun sendHello(dst: Int, toPartner: Boolean) {
        val nm = PesBytes.utf8Limit(myName, 32)
        val p = ByteArray(15 + nm.size)
        p[0] = PesProto.MAGIC.toByte(); p[1] = PesProto.K_HELLO.toByte()
        p[2] = PesProto.VERSION.toByte(); p[3] = role.toByte(); p[4] = platform.toByte()
        p[5] = (if (paired && !toPartner) 1 else 0).toByte()             // Bit0 = bereits in einer Sitzung
        PesBytes.writeI32(p, 6, mySid)
        PesBytes.writeI32(p, 10, if (toPartner) partnerSid else 0)
        p[14] = nm.size.toByte()
        System.arraycopy(nm, 0, p, 15, nm.size)
        sendRaw(dst, p)
    }

    /** Abmeldung: der Partner muss nicht erst auf den Zeitablauf warten. */
    private fun sendBye() {
        val p = ByteArray(6)
        p[0] = PesProto.MAGIC.toByte(); p[1] = PesProto.K_BYE.toByte()
        PesBytes.writeI32(p, 2, mySid)
        sendRaw(partnerVip, p)
    }

    private fun sendRelPacket(stream: Int, kind: Int, body: ByteArray) {
        val p = ByteArray(7 + body.size)
        p[0] = PesProto.MAGIC.toByte(); p[1] = kind.toByte()
        PesBytes.writeI32(p, 2, mySid xor partnerSid)
        p[6] = stream.toByte()
        System.arraycopy(body, 0, p, 7, body.size)
        sendRaw(partnerVip, p)
    }

    /** Unter lk: Wiederholungen, neue Pakete und Bestaetigungen aller Stroeme senden. */
    private fun flushLocked(now: Long) {
        if (!handshake) return
        val pk = ArrayList<ByteArray>()
        for (i in rel.indices) {
            pk.clear()
            rel[i].pump(now, if (i == 0) 16 else 12, pk)
            for (b in pk) sendRelPacket(i, PesProto.K_REL, b)
            if (rel[i].ackDue) sendRelPacket(i, PesProto.K_ACK, rel[i].buildAck())
        }
    }

    private fun sendMsg(stream: Int, msg: ByteArray): Boolean {
        synchronized(lk) {
            if (!handshake) return false
            rel[stream].enqueue(msg)
            if (stream == 0) flushLocked(now())
            return true
        }
    }

    private fun msg(type: Int, vararg body: Int): ByteArray {
        val m = ByteArray(1 + body.size)
        m[0] = type.toByte()
        for (i in body.indices) m[1 + i] = body[i].toByte()
        return m
    }

    // =========================================================================
    // Arbeits-Thread
    // =========================================================================
    private fun loop() {
        while (running) {
            try { tick() } catch (ex: Exception) { ev("SYS", "Sitzungsfehler: " + ex.message) }
            try { Thread.sleep(5) } catch (_: InterruptedException) { break }
        }
    }

    private fun tick() {
        val now = now()
        var helloTo: ArrayList<Int>? = null
        synchronized(lk) {
            if (paired && now - lastPartnerRx > 12000) unpair("Verbindung zum Partner verloren.", true)
            if (callState == PesProto.CALL_OUT && now - callSince > 45000) { callState = PesProto.CALL_IDLE; ev("CALL", "timeout"); enqueueLocked(0, msg(PesProto.M_CALL, 5)) }
            if (callState == PesProto.CALL_IN && now - callSince > 50000) { callState = PesProto.CALL_IDLE; ev("CALL", "missed") }
            val iv = if (handshake) 2000 else 500
            if (now - lastHelloTx >= iv) {
                lastHelloTx = now
                val l = ArrayList<Int>()
                for (pi in engine.getPeers()) if (pi.path != 0 && pi.vip != 0) l.add(pi.vip)
                helloTo = l
            }
            if (handshake) {
                if (ptrDirty && now - lastPtrTx >= 25 && rel[0].backlog < 4000) {
                    ptrDirty = false; lastPtrTx = now
                    val b = ByteArray(6)
                    b[0] = PesProto.M_INPUT.toByte(); b[1] = 1
                    PesBytes.writeU16(b, 2, ptrX); PesBytes.writeU16(b, 4, ptrY)
                    rel[0].enqueue(b)
                }
                pumpFileLocked()
                flushLocked(now)
            }
        }
        val h = helloTo
        if (h != null) {
            val pv = partnerVip
            for (v in h) sendHello(v, paired && v == pv)
        }
    }

    private fun enqueueLocked(stream: Int, m: ByteArray) { if (handshake) rel[stream].enqueue(m) }

    /** Unter lk. Setzt alles zurueck, was an den Partner gebunden ist. */
    private fun unpair(reason: String, notify: Boolean) {
        val was = paired
        paired = false; handshake = false; partnerSid = 0
        for (r in rel) r.reset()
        callState = PesProto.CALL_IDLE; partnerCam = false; partnerMic = false
        shareActive = false; controlActive = false
        synchronized(jitter) { jitter.clear(); jitterPlaying = false; vSeq = -1; vParts = null }
        ptrDirty = false
        abortTxLocked("Verbindung getrennt", false)
        abortRxLocked("Verbindung getrennt", false)
        partnerVip = 0
        if (was && notify) ev("PEER", "down", partnerName, reason)
        partnerName = ""
    }

    // =========================================================================
    // Empfang (laeuft im UDP-Thread der Engine)
    // =========================================================================
    private fun onIp(ip: ByteArray) {
        if (!running) return
        val u = PesProto.unwrap(ip) ?: return
        val off = u.first
        val len = u.second
        val src = u.third
        if (len < 2) return
        val kind = PesBytes.u8(ip, off + 1)
        try {
            if (kind == PesProto.K_HELLO) { onHello(ip, off, len, src); return }
            if (!paired || src != partnerVip) return                   // alles andere nur vom Partner
            when (kind) {
                PesProto.K_BYE -> if (len >= 6) synchronized(lk) {
                    if (paired && PesBytes.readI32(ip, off + 2) == partnerSid) unpair("Der Partner hat die Sitzung beendet.", true)
                }
                PesProto.K_AUDIO -> onAudio(ip, off, len)
                PesProto.K_VIDEO -> onVideo(ip, off, len)
                PesProto.K_REL, PesProto.K_ACK -> onRel(kind, ip, off, len)
            }
        } catch (ex: Exception) {
            ev("SYS", "Paketfehler: " + ex.message)
        }
    }

    private fun onHello(b: ByteArray, off: Int, len: Int, src: Int) {
        if (len < 15) return
        if (PesBytes.u8(b, off + 2) != PesProto.VERSION) return
        val prole = PesBytes.u8(b, off + 3)
        val plat = PesBytes.u8(b, off + 4)
        val flags = PesBytes.u8(b, off + 5)
        val sid = PesBytes.readI32(b, off + 6)
        val echo = PesBytes.readI32(b, off + 10)
        val nl = PesBytes.u8(b, off + 14)
        if (nl > 32 || 15 + nl > len || sid == 0) return
        if (prole != PesProto.ROLE_HELPER && prole != PesProto.ROLE_CUSTOMER) return
        var name = PesProto.cleanName(String(b, off + 15, nl, Charsets.UTF_8), 32)
        if (name.isEmpty()) name = "?"
        var reply = false
        synchronized(lk) {
            val now = now()
            if (paired && src == partnerVip) {
                if (sid != partnerSid) {
                    // Partner hat neu gestartet: alles zuruecksetzen und neu koppeln
                    unpair("Partner hat neu gestartet.", true)
                } else {
                    lastPartnerRx = now
                    partnerName = name
                    if (!handshake && echo == mySid) { handshake = true; ev("PEER", "up", name, prole.toString(), plat.toString()) }
                    return
                }
            }
            if (paired) return                                          // belegt: andere werden nicht angenommen
            if (prole == role) return                                   // Helfer koppelt nur mit Kunde und umgekehrt
            if ((flags and 1) != 0 && echo != mySid) return             // Gegenseite ist schon vergeben
            paired = true; partnerVip = src; partnerSid = sid; partnerName = name
            partnerRole = prole; partnerPlatform = plat; lastPartnerRx = now
            handshake = echo == mySid
            for (r in rel) r.reset()
            if (handshake) ev("PEER", "up", name, prole.toString(), plat.toString())
            reply = true
        }
        if (reply) sendHello(src, true)
    }

    private fun onRel(kind: Int, b: ByteArray, off: Int, len: Int) {
        if (len < 7 + 5) return
        var deliver: ArrayList<ByteArray>? = null
        var stream = 0
        synchronized(lk) {
            if (!handshake) return
            if (PesBytes.readI32(b, off + 2) != (mySid xor partnerSid)) return
            stream = PesBytes.u8(b, off + 6)
            if (stream >= rel.size) return
            val now = now()
            lastPartnerRx = now
            if (kind == PesProto.K_REL) {
                val d = ArrayList<ByteArray>()
                rel[stream].onData(b, off + 7, len - 7, d)
                sendRelPacket(stream, PesProto.K_ACK, rel[stream].buildAck())
                deliver = d
            } else {
                if (len < 7 + 12) return
                val pk = ArrayList<ByteArray>()
                rel[stream].onAck(PesBytes.readI32(b, off + 7), PesBytes.readI64(b, off + 11), now, pk)
                rel[stream].pump(now, 12, pk)                           // Fenster ist frei geworden: gleich nachschieben
                for (x in pk) sendRelPacket(stream, PesProto.K_REL, x)
            }
        }
        val d = deliver ?: return
        for (m in d) {
            try { onMessage(stream, m) } catch (ex: Exception) { ev("SYS", "Nachrichtenfehler: " + ex.message) }
        }
    }

    private fun onMessage(stream: Int, m: ByteArray) {
        if (m.isEmpty()) return
        val t = PesBytes.u8(m, 0)
        if (stream == 2) {
            if (t != PesProto.M_RECT || m.size < 14 || role != PesProto.ROLE_HELPER) return
            val r = IntArray(7)
            for (i in 0 until 6) r[i] = PesBytes.readU16(m, 1 + i * 2)
            r[6] = PesBytes.u8(m, 13)
            if (r[0] < 16 || r[1] < 16 || r[0] > 8192 || r[1] > 8192) return
            if (r[4] < 1 || r[5] < 1 || r[2] + r[4] > r[0] || r[3] + r[5] > r[1]) return
            screenW = r[0]; screenH = r[1]
            onScreenRect?.invoke(r, m.copyOfRange(14, m.size))
            return
        }
        if (stream == 1) { onFileStream(t, m); return }
        when (t) {
            PesProto.M_CHAT -> {
                if (m.size > 1 + 8000) return
                ev("CHAT", partnerName, String(m, 1, m.size - 1, Charsets.UTF_8).replace(PesProto.SEP, ' '))
            }
            PesProto.M_CALL -> if (m.size >= 2) onCall(PesBytes.u8(m, 1))
            PesProto.M_MEDIA -> if (m.size >= 3) {
                partnerCam = m[1].toInt() != 0; partnerMic = m[2].toInt() != 0
                ev("MEDIA", PesBytes.u8(m, 1).toString(), PesBytes.u8(m, 2).toString())
            }
            PesProto.M_SCRREQ -> if (m.size >= 2 && role == PesProto.ROLE_CUSTOMER && PesBytes.u8(m, 1) in 1..5) ev("SCREEN", "req", PesBytes.u8(m, 1).toString())
            PesProto.M_SCRSTAT -> if (m.size >= 9 && role == PesProto.ROLE_HELPER) {
                shareActive = m[1].toInt() != 0; controlActive = m[1].toInt() != 0 && m[2].toInt() != 0
                screenW = PesBytes.readU16(m, 3); screenH = PesBytes.readU16(m, 5)
                screenMonitor = PesBytes.u8(m, 7); screenMonitors = PesBytes.u8(m, 8)
                ev("SCREEN", "state", PesBytes.u8(m, 1).toString(), PesBytes.u8(m, 2).toString())
            }
            PesProto.M_INPUT -> if (role == PesProto.ROLE_CUSTOMER && controlActive && shareActive && m.size >= 2 && m.size <= 1 + 1 + 1024) {
                onInput?.invoke(m.copyOfRange(1, m.size))
            }
            PesProto.M_SCROPT -> if (m.size >= 3 && role == PesProto.ROLE_CUSTOMER) {
                var q = PesBytes.u8(m, 1)
                if (q < 1) q = 1
                if (q > 3) q = 3
                wantQuality = q; wantMonitor = PesBytes.u8(m, 2)
                ev("SCREEN", "opt", q.toString(), PesBytes.u8(m, 2).toString())
            }
            PesProto.M_FOFFER -> onFileOffer(m)
            PesProto.M_FANSW -> onFileAnswer(m)
            PesProto.M_FCANCEL -> onFileCancel(m)
            PesProto.M_FDONE -> onFileDone(m)
        }
    }

    // =========================================================================
    // Chat
    // =========================================================================
    fun sendChat(text0: String?): Boolean {
        var text = text0 ?: return false
        if (text.isEmpty()) return false
        if (text.length > 2000) text = text.substring(0, 2000)
        val t = text.toByteArray(Charsets.UTF_8)
        val m = ByteArray(1 + t.size)
        m[0] = PesProto.M_CHAT.toByte()
        System.arraycopy(t, 0, m, 1, t.size)
        return sendMsg(0, m)
    }

    // =========================================================================
    // Anruf (Ton + Video)
    // =========================================================================
    private fun onCall(sub: Int) {
        var sendAccept = false
        var media = false
        synchronized(lk) {
            when (sub) {
                1 -> if (callState == PesProto.CALL_IDLE) { callState = PesProto.CALL_IN; callSince = now(); ev("CALL", "in", partnerName) }
                else if (callState == PesProto.CALL_OUT) { callState = PesProto.CALL_ACTIVE; sendAccept = true; media = true; ev("CALL", "active") }
                2 -> if (callState == PesProto.CALL_OUT) { callState = PesProto.CALL_ACTIVE; media = true; ev("CALL", "active") }
                3 -> if (callState == PesProto.CALL_OUT) { callState = PesProto.CALL_IDLE; ev("CALL", "declined") }
                4 -> if (callState != PesProto.CALL_IDLE) { callState = PesProto.CALL_IDLE; clearMedia(); ev("CALL", "ended") }
                5 -> if (callState == PesProto.CALL_IN) { callState = PesProto.CALL_IDLE; ev("CALL", "missed") }
            }
        }
        if (sendAccept) sendMsg(0, msg(PesProto.M_CALL, 2))
        if (media) sendMedia()
    }

    private fun clearMedia() {
        synchronized(jitter) { jitter.clear(); jitterPlaying = false; vSeq = -1; vParts = null }
        partnerCam = false
    }

    fun call(): Boolean {
        synchronized(lk) {
            if (!handshake || callState != PesProto.CALL_IDLE) return false
            callState = PesProto.CALL_OUT; callSince = now()
        }
        ev("CALL", "out")
        return sendMsg(0, msg(PesProto.M_CALL, 1))
    }

    fun answerCall(accept: Boolean) {
        synchronized(lk) {
            if (callState != PesProto.CALL_IN) return
            callState = if (accept) PesProto.CALL_ACTIVE else PesProto.CALL_IDLE
        }
        sendMsg(0, msg(PesProto.M_CALL, if (accept) 2 else 3))
        if (accept) { ev("CALL", "active"); sendMedia() }
    }

    fun hangup() {
        val st: Int
        synchronized(lk) { st = callState; callState = PesProto.CALL_IDLE; clearMedia() }
        if (st == PesProto.CALL_IDLE) return
        sendMsg(0, msg(PesProto.M_CALL, if (st == PesProto.CALL_OUT) 5 else if (st == PesProto.CALL_IN) 3 else 4))
        ev("CALL", "ended")
    }

    fun setMedia(cam: Boolean, mic: Boolean) {
        myCam = cam; myMic = mic
        if (callState == PesProto.CALL_ACTIVE) sendMedia()
    }

    private fun sendMedia() { sendMsg(0, msg(PesProto.M_MEDIA, if (myCam) 1 else 0, if (myMic) 1 else 0)) }

    /** Ein Mikrofon-Frame (320 Samples, 16 kHz mono). */
    fun sendAudio(f: ShortArray) {
        if (f.size < PesProto.FRAME) return
        if (callState != PesProto.CALL_ACTIVE || !myMic || !paired) return
        val p = ByteArray(4 + PesProto.FRAME)
        p[0] = PesProto.MAGIC.toByte(); p[1] = PesProto.K_AUDIO.toByte()
        PesBytes.writeU16(p, 2, audioSeq.incrementAndGet() and 0xFFFF)
        for (i in 0 until PesProto.FRAME) p[4 + i] = PesProto.muLawEncode(f[i])
        sendRaw(partnerVip, p)
    }

    private fun onAudio(b: ByteArray, off: Int, len: Int) {
        if (callState != PesProto.CALL_ACTIVE) return
        val n = len - 4
        if (n != PesProto.FRAME) return
        val fr = ShortArray(n) { PesProto.muLawDecode(b[off + 4 + it]) }
        lastAudioRx.set(now())
        synchronized(jitter) {
            jitter.addLast(fr)
            while (jitter.size > 12) jitter.removeFirst()
        }
    }

    /** Naechster Wiedergabe-Frame (320 Samples); Stille, solange nichts ansteht. */
    fun pullAudio(): ShortArray {
        synchronized(jitter) {
            if (!jitterPlaying) { if (jitter.size >= 3) jitterPlaying = true else return ShortArray(PesProto.FRAME) }
            if (jitter.isEmpty()) { jitterPlaying = false; return ShortArray(PesProto.FRAME) }
            return jitter.removeFirst()
        }
    }

    /** Ein JPEG-Bild der eigenen Kamera, wird in Teilen gesendet (verlorene Bilder werden nicht wiederholt). */
    fun sendVideo(jpeg: ByteArray, rotQuarter: Int): Boolean {
        if (jpeg.isEmpty() || jpeg.size > PesProto.VIDEO_MAX_FRAME) return false
        if (callState != PesProto.CALL_ACTIVE || !myCam || !paired) return false
        val cnt = (jpeg.size + PesProto.VIDEO_CHUNK - 1) / PesProto.VIDEO_CHUNK
        val sq = videoSeq.incrementAndGet() and 0xFFFF
        val dst = partnerVip
        for (i in 0 until cnt) {
            val o = i * PesProto.VIDEO_CHUNK
            val n = minOf(PesProto.VIDEO_CHUNK, jpeg.size - o)
            val p = ByteArray(7 + n)
            p[0] = PesProto.MAGIC.toByte(); p[1] = PesProto.K_VIDEO.toByte()
            PesBytes.writeU16(p, 2, sq)
            p[4] = i.toByte(); p[5] = cnt.toByte(); p[6] = (rotQuarter and 3).toByte()
            System.arraycopy(jpeg, o, p, 7, n)
            sendRaw(dst, p)
        }
        return true
    }

    private fun onVideo(b: ByteArray, off: Int, len: Int) {
        if (callState != PesProto.CALL_ACTIVE || len < 8) return
        val seq = PesBytes.readU16(b, off + 2)
        val idx = PesBytes.u8(b, off + 4)
        val cnt = PesBytes.u8(b, off + 5)
        val rot = PesBytes.u8(b, off + 6) and 3
        val n = len - 7
        if (cnt == 0 || idx >= cnt || n <= 0 || n > PesProto.VIDEO_CHUNK) return
        var done: ByteArray? = null
        synchronized(jitter) {
            var parts = vParts
            if (parts == null || vSeq != seq || vCount != cnt) {
                // Nur neuere Bilder beginnen (verspaetete Teile alter Bilder verwerfen)
                if (parts != null && vSeq >= 0 && ((seq - vSeq) and 0xFFFF) > 0x8000) return
                vSeq = seq; vCount = cnt; vGot = 0; vBytes = 0
                parts = arrayOfNulls(cnt)
                vParts = parts
            }
            if (parts[idx] != null) return
            if (vBytes + n > PesProto.VIDEO_MAX_FRAME) { vParts = null; return }
            parts[idx] = b.copyOfRange(off + 7, off + 7 + n)
            vGot++; vBytes += n
            if (vGot == vCount) {
                val out = ByteArray(vBytes)
                var o = 0
                for (x in parts) { System.arraycopy(x!!, 0, out, o, x.size); o += x.size }
                vParts = null
                done = out
            }
        }
        val d = done ?: return
        lastVideoRx.set(now())
        onVideoFrame?.invoke(d, rot)
    }

    // =========================================================================
    // Bildschirm
    // =========================================================================
    /** Helfer: 1 = ansehen, 2 = ansehen und steuern, 3 = beenden, 4 = Steuerung abgeben, 5 = Komplettbild neu senden. */
    fun requestScreen(sub: Int): Boolean {
        if (role != PesProto.ROLE_HELPER || sub < 1 || sub > 5) return false
        return sendMsg(0, msg(PesProto.M_SCRREQ, sub))
    }

    fun setScreenOptions(quality: Int, monitor: Int): Boolean {
        if (role != PesProto.ROLE_HELPER) return false
        return sendMsg(0, msg(PesProto.M_SCROPT, quality, monitor))
    }

    /** Kunde: eigenen Freigabe-Zustand setzen und dem Helfer melden. */
    fun setShare(share: Boolean, control: Boolean, w: Int, h: Int, monitor: Int, monitors: Int) {
        if (role != PesProto.ROLE_CUSTOMER) return
        shareActive = share; controlActive = share && control
        screenW = w; screenH = h; screenMonitor = monitor; screenMonitors = monitors
        val m = ByteArray(9)
        m[0] = PesProto.M_SCRSTAT.toByte(); m[1] = (if (share) 1 else 0).toByte(); m[2] = (if (share && control) 1 else 0).toByte()
        PesBytes.writeU16(m, 3, w); PesBytes.writeU16(m, 5, h)
        m[7] = monitor.toByte(); m[8] = monitors.toByte()
        sendMsg(0, m)
    }

    /** Kunde: ein geaendertes Rechteck (JPEG) senden. fl Bit0 = letztes Rechteck dieses Durchgangs. */
    fun sendScreenRect(sw: Int, sh: Int, x: Int, y: Int, w: Int, h: Int, fl: Int, jpeg: ByteArray): Boolean {
        if (role != PesProto.ROLE_CUSTOMER || !shareActive) return false
        val m = ByteArray(14 + jpeg.size)
        m[0] = PesProto.M_RECT.toByte()
        PesBytes.writeU16(m, 1, sw); PesBytes.writeU16(m, 3, sh)
        PesBytes.writeU16(m, 5, x); PesBytes.writeU16(m, 7, y)
        PesBytes.writeU16(m, 9, w); PesBytes.writeU16(m, 11, h)
        m[13] = fl.toByte()
        System.arraycopy(jpeg, 0, m, 14, jpeg.size)
        synchronized(lk) {
            if (!handshake) return false
            rel[2].enqueue(m)
            flushLocked(now())
        }
        return true
    }

    // ---- Eingaben des Helfers (Koordinaten 0..65535 bezogen auf den freigegebenen Bildschirm) ----
    private fun clamp16(v: Int): Int = if (v < 0) 0 else if (v > 65535) 65535 else v

    fun inputMove(x: Int, y: Int) {
        if (role != PesProto.ROLE_HELPER || !controlActive) return
        synchronized(lk) { ptrX = clamp16(x); ptrY = clamp16(y); ptrDirty = true }
    }

    private fun sendInput(body: ByteArray): Boolean {
        if (role != PesProto.ROLE_HELPER || !controlActive) return false
        val m = ByteArray(1 + body.size)
        m[0] = PesProto.M_INPUT.toByte()
        System.arraycopy(body, 0, m, 1, body.size)
        synchronized(lk) {
            if (!handshake) return false
            ptrDirty = false                                            // die Taste traegt die aktuelle Position selbst
            rel[0].enqueue(m)
            flushLocked(now())
        }
        return true
    }

    fun inputButton(button: Int, down: Boolean, x: Int, y: Int): Boolean {
        val b = ByteArray(7)
        b[0] = 2; b[1] = button.toByte(); b[2] = (if (down) 1 else 0).toByte()
        PesBytes.writeU16(b, 3, clamp16(x)); PesBytes.writeU16(b, 5, clamp16(y))
        return sendInput(b)
    }

    fun inputWheel(delta0: Int, x: Int, y: Int): Boolean {
        val delta = if (delta0 > 32767) 32767 else if (delta0 < -32768) -32768 else delta0
        val b = ByteArray(7)
        b[0] = 3; PesBytes.writeU16(b, 1, delta and 0xFFFF)
        PesBytes.writeU16(b, 3, clamp16(x)); PesBytes.writeU16(b, 5, clamp16(y))
        return sendInput(b)
    }

    fun inputKey(vk: Int, down: Boolean, extended: Boolean): Boolean {
        val b = ByteArray(5)
        b[0] = 4; PesBytes.writeU16(b, 1, vk and 0xFFFF); b[3] = (if (down) 1 else 0).toByte(); b[4] = (if (extended) 1 else 0).toByte()
        return sendInput(b)
    }

    fun inputText(text0: String?): Boolean {
        var text = text0 ?: return false
        if (text.isEmpty()) return false
        if (text.length > 200) text = text.substring(0, 200)
        val t = text.toByteArray(Charsets.UTF_8)
        val b = ByteArray(1 + t.size)
        b[0] = 5
        System.arraycopy(t, 0, b, 1, t.size)
        return sendInput(b)
    }

    // =========================================================================
    // Dateien (eine Uebertragung je Richtung; der Empfaenger muss zustimmen)
    // =========================================================================
    fun txFile(): PesFileInfo? = synchronized(lk) { txFile }
    fun rxFile(): PesFileInfo? = synchronized(lk) { rxFile }

    /** Liefert null bei Erfolg, sonst eine Fehlermeldung. [open] wird erst nach der Zustimmung des Empfaengers aufgerufen. */
    fun offerFile(name0: String, size: Long, open: () -> InputStream): String? {
        if (size < 0) return "Dateigroesse unbekannt."
        if (size > maxFileSize) return "Datei ist zu gross."
        synchronized(lk) {
            if (!handshake) return "Nicht verbunden."
            val cur = txFile
            if (cur != null && (cur.state < 2 || cur.state == 4)) return "Es laeuft bereits eine Uebertragung."
            val f = PesFileInfo(SecureRandom().nextInt(), PesProto.cleanFileName(name0), size)
            txFile = f
            txOpen = open
            val nm = PesBytes.utf8Limit(f.name, 240)
            val m = ByteArray(13 + nm.size)
            m[0] = PesProto.M_FOFFER.toByte()
            PesBytes.writeI32(m, 1, f.id)
            PesBytes.writeI64(m, 5, f.size)
            System.arraycopy(nm, 0, m, 13, nm.size)
            rel[0].enqueue(m)
            flushLocked(now())
        }
        return null
    }

    fun offerFile(file: File): String? {
        if (!file.isFile) return "Datei nicht gefunden."
        return offerFile(file.name, file.length()) { java.io.FileInputStream(file) }
    }

    private fun onFileOffer(m: ByteArray) {
        if (m.size < 14 || m.size > 13 + 300) return
        val id = PesBytes.readI32(m, 1)
        val size = PesBytes.readI64(m, 5)
        val name = PesProto.cleanFileName(String(m, 13, m.size - 13, Charsets.UTF_8))
        synchronized(lk) {
            val cur = rxFile
            if ((cur != null && cur.state < 2) || size < 0 || size > maxFileSize) {
                rel[0].enqueue(byteArrayOf(PesProto.M_FANSW.toByte(), m[1], m[2], m[3], m[4], 0))
                return
            }
            rxFile = PesFileInfo(id, name, size)
        }
        ev("FILE", "offer", (id.toLong() and 0xFFFFFFFFL).toString(), name, size.toString())
    }

    /** Empfaenger: Angebot annehmen oder ablehnen. Liefert null bei Erfolg. */
    fun answerFile(accept: Boolean): String? {
        synchronized(lk) {
            val f = rxFile
            if (f == null || f.state != 0) return "Kein offenes Angebot."
            val a = ByteArray(6)
            a[0] = PesProto.M_FANSW.toByte(); PesBytes.writeI32(a, 1, f.id); a[5] = (if (accept) 1 else 0).toByte()
            if (!accept) { f.state = 3; f.error = "abgelehnt"; rel[0].enqueue(a); flushLocked(now()); return null }
            try {
                val dir = downloadDir ?: throw IllegalStateException("Kein Zielordner")
                dir.mkdirs()
                val tmp = File(dir, f.name + "." + String.format("%08x", f.id) + ".part")
                rxTemp = tmp
                rxStream = FileOutputStream(tmp)
                rxHash = MessageDigest.getInstance("SHA-256")
                f.state = 1
            } catch (ex: Exception) {
                f.state = 3; f.error = ex.message ?: "Fehler"
                a[5] = 0; rel[0].enqueue(a); flushLocked(now())
                return f.error
            }
            rel[0].enqueue(a); flushLocked(now())
        }
        return null
    }

    private fun onFileAnswer(m: ByteArray) {
        if (m.size < 6) return
        val id = PesBytes.readI32(m, 1)
        val ok = m[5].toInt() != 0
        synchronized(lk) {
            val f = txFile
            if (f == null || f.id != id || f.state != 0) return
            if (!ok) { f.state = 3; f.error = "abgelehnt"; ev("FILE", "declined", f.name); return }
            try {
                txStream = txOpen!!.invoke()
                txHash = MessageDigest.getInstance("SHA-256")
                f.state = 1
                ev("FILE", "sending", f.name)
            } catch (ex: Exception) {
                abortTxLocked(ex.message ?: "Fehler", true)
            }
        }
    }

    /** Unter lk: Dateidaten nachschieben, solange der Strom nicht staut. */
    private fun pumpFileLocked() {
        val f = txFile ?: return
        val st = txStream ?: return
        if (f.state != 1) return
        try {
            var rounds = 0
            while (rel[1].backlog < 256 * 1024 && rounds++ < 8) {
                val buf = ByteArray(5 + 32768)
                var n = 0
                // InputStream.read darf weniger liefern - auffuellen, damit die Bloecke gross bleiben
                while (n < 32768) {
                    val r = st.read(buf, 5 + n, 32768 - n)
                    if (r <= 0) break
                    n += r
                }
                if (n <= 0) {
                    val e = ByteArray(5 + 32)
                    e[0] = PesProto.M_FEND.toByte(); PesBytes.writeI32(e, 1, f.id)
                    System.arraycopy(txHash!!.digest(), 0, e, 5, 32)
                    rel[1].enqueue(e)
                    try { st.close() } catch (_: Exception) {}
                    txStream = null
                    f.state = 4                                         // gesendet, wartet auf Bestaetigung
                    return
                }
                txHash!!.update(buf, 5, n)
                buf[0] = PesProto.M_FDATA.toByte(); PesBytes.writeI32(buf, 1, f.id)
                rel[1].enqueue(if (n < 32768) buf.copyOf(5 + n) else buf)
                f.done += n
            }
        } catch (ex: Exception) {
            abortTxLocked(ex.message ?: "Fehler", true)
        }
    }

    private fun onFileStream(t: Int, m: ByteArray) {
        if (m.size < 5) return
        val id = PesBytes.readI32(m, 1)
        var doneName: String? = null
        var donePath = ""
        synchronized(lk) {
            val f = rxFile
            val st = rxStream
            if (f == null || f.id != id || f.state != 1 || st == null) return
            try {
                if (t == PesProto.M_FDATA) {
                    val n = m.size - 5
                    if (f.done + n > f.size) { abortRxLocked("mehr Daten als angekuendigt", true); return }
                    st.write(m, 5, n)
                    rxHash!!.update(m, 5, n)
                    f.done += n
                } else if (t == PesProto.M_FEND && m.size >= 37) {
                    val h = rxHash!!.digest()
                    var ok = f.done == f.size
                    var i = 0
                    while (ok && i < 32) { if (h[i] != m[5 + i]) ok = false; i++ }
                    st.close(); rxStream = null
                    if (!ok) { abortRxLocked("Pruefsumme stimmt nicht", true); return }
                    val dir = downloadDir!!
                    var target = File(dir, f.name)
                    var k = 1
                    while (target.exists()) {
                        val dot = f.name.lastIndexOf('.')
                        val stem = if (dot > 0) f.name.substring(0, dot) else f.name
                        val ext = if (dot > 0) f.name.substring(dot) else ""
                        target = File(dir, "$stem ($k)$ext")
                        k++
                    }
                    if (!rxTemp!!.renameTo(target)) { abortRxLocked("Datei konnte nicht umbenannt werden", true); return }
                    rxTemp = null
                    f.path = target.path; f.state = 2
                    val d = ByteArray(6)
                    d[0] = PesProto.M_FDONE.toByte(); PesBytes.writeI32(d, 1, id); d[5] = 1
                    rel[0].enqueue(d)
                    doneName = f.name; donePath = target.path
                }
            } catch (ex: Exception) {
                abortRxLocked(ex.message ?: "Fehler", true)
            }
        }
        val dn = doneName
        if (dn != null) ev("FILE", "received", dn, donePath)
    }

    private fun onFileCancel(m: ByteArray) {
        if (m.size < 5) return
        val id = PesBytes.readI32(m, 1)
        synchronized(lk) {
            val r = rxFile
            if (r != null && r.id == id && r.state < 2) abortRxLocked("vom Absender abgebrochen", false)
            val t = txFile
            if (t != null && t.id == id && (t.state < 2 || t.state == 4)) abortTxLocked("vom Empfaenger abgebrochen", false)
        }
    }

    private fun onFileDone(m: ByteArray) {
        if (m.size < 6) return
        val id = PesBytes.readI32(m, 1)
        synchronized(lk) {
            val f = txFile
            if (f == null || f.id != id) return
            if (m[5].toInt() != 0) { f.state = 2; ev("FILE", "sent", f.name) }
            else { f.state = 3; f.error = "Empfaenger meldet Fehler"; ev("FILE", "failed", f.name, f.error) }
        }
    }

    fun cancelFiles() {
        synchronized(lk) {
            val t = txFile
            if (t != null && (t.state < 2 || t.state == 4)) abortTxLocked("abgebrochen", true)
            val r = rxFile
            if (r != null && r.state < 2) abortRxLocked("abgebrochen", true)
            flushLocked(now())
        }
    }

    private fun abortTxLocked(why: String, tell: Boolean) {
        try { txStream?.close() } catch (_: Exception) {}
        txStream = null
        val f = txFile ?: return
        if (f.state == 2 || f.state == 3) return
        f.state = 3; f.error = why
        if (tell && handshake) { val c = ByteArray(5); c[0] = PesProto.M_FCANCEL.toByte(); PesBytes.writeI32(c, 1, f.id); rel[0].enqueue(c) }
        ev("FILE", "failed", f.name, why)
    }

    private fun abortRxLocked(why: String, tell: Boolean) {
        try { rxStream?.close() } catch (_: Exception) {}
        rxStream = null
        try { rxTemp?.delete() } catch (_: Exception) {}
        rxTemp = null
        val f = rxFile ?: return
        if (f.state == 2 || f.state == 3) return
        val wasOffer = f.state == 0
        f.state = 3; f.error = why
        if (tell && handshake) { val c = ByteArray(5); c[0] = PesProto.M_FCANCEL.toByte(); PesBytes.writeI32(c, 1, f.id); rel[0].enqueue(c) }
        ev("FILE", if (wasOffer) "withdrawn" else "failed", f.name, why)
    }
}
