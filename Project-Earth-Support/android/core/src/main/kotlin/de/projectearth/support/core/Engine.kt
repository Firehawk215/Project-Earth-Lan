package de.projectearth.support.core

import java.io.IOException
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.Inet4Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.SocketTimeoutException
import java.nio.charset.StandardCharsets
import java.security.SecureRandom
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

/** Ein Teilnehmer in der Lobby (uebernommen aus Project Earth LAN, Protokoll unveraendert). */
class PesPeer(val nodeId: Long) {
    @Volatile var name: String = ""
    @Volatile var vip: Int = 0
    @Volatile var publicEp: InetSocketAddress? = null
    @Volatile var localEps: List<InetSocketAddress> = emptyList()

    /** bestaetigter direkter Weg (nach Hole Punching) */
    @Volatile var directEp: InetSocketAddress? = null

    /** 0 = verbinde / punching, 1 = direkt, 2 = relay */
    @Volatile var path: Int = 0
    val lastRxMs = AtomicLong(0)
    @Volatile var lastHelloMs: Long = 0
    @Volatile var lastRelayHelloMs: Long = 0
    @Volatile var punchStartMs: Long = 0
    @Volatile var rttMs: Int = -1
    val rxBytes = AtomicLong(0)
    val txBytes = AtomicLong(0)
    @Volatile var authFails: Int = 0
    @Volatile var inServerList: Boolean = true
    @Volatile var hasRev: Boolean = false
    @Volatile var infoRev: Int = 0
    @Volatile var punching: Boolean = false

    // Replay-Schutz (Sliding Window, 64 Pakete); Zugriff nur unter synchronized(this)
    var anySeq = false
    var maxSeq = 0
    var window = 0L
}

class PesPeerInfo(
    val nodeId: Long,
    val name: String,
    val vip: Int,
    val mode: String,
    val endpoint: String,
    val rttMs: Int,
    val rxBytes: Long,
    val txBytes: Long,
    /** 0 = verbindet, 1 = direkt, 2 = relay */
    val path: Int,
) {
    val ip: String get() = PesBytes.ipToString(vip)
}

/**
 * P2P-Engine, uebernommen aus der App Project Earth LAN (Protokoll unveraendert, gleich wie in der Windows-.ps1):
 * Signaling (UDP) zum Vermittlungsserver, UDP-Hole-Punching, Relay-Fallback,
 * AES-256-CTR + HMAC-SHA256 je Paket. Statt Wintun-Adapter gibt es zwei Schnittstellen:
 * [sendIp] (ausgehende IPv4-Pakete) und [inboundSink] (eingehende IPv4-Pakete).
 */
class PesP2pEngine {
    companion object {
        const val PROTO_VERSION = 1
        private const val T_HELLO = 1
        private const val T_HELLO_ACK = 2
        private const val T_DATA = 4
        private const val T_BYE = 5
        private const val S_REGISTER = 0x10
        private const val S_LEAVE = 0x11
        private const val S_RELAY = 0x12
        private const val S_WELCOME = 0x20
        private const val S_PEER = 0x21
        private const val S_RELAYED = 0x22
        private const val S_ERROR = 0x23
        private const val S_MEMBERS = 0x24
        private const val S_SYNC = 0x25
        private const val S_PEER2 = 0x26
        private const val S_GONE = 0x27
        private const val EXT_V2 = 0xE2
        private val DEFAULT_NOISE = intArrayOf(5353, 5355, 137, 138, 1900, 3702, 67, 68, 17500, 57621, 1716, 21027, 427, 8611, 8612, 161)

        private val clockOrigin = System.nanoTime()
        private fun now(): Long = (System.nanoTime() - clockOrigin) / 1_000_000L + 1

        private fun newer(a: Int, b: Int): Boolean = (a - b) > 0

        private fun mix(nid: Long, rev: Int): Long {
            var z = nid xor ((rev.toLong() and 0xFFFFFFFFL) * -0x61c8864680b583ebL)
            z = (z xor (z ushr 30)) * -0x40a7b892e31b1a47L
            z = (z xor (z ushr 27)) * -0x6b2fb644ecceee15L
            return z xor (z ushr 31)
        }

        fun lobbyIdOf(lobby: String): ByteArray = PesKeys.deriveLobbyId(lobby)
    }

    // ---- Einstellungen (vor start() setzbar) ----
    @Volatile var preferredPort = 9892
    @Volatile var allowRelay = true
    @Volatile var punchTimeoutMs = 8000
    @Volatile var peerTimeoutMs = 20000
    @Volatile var punchBudgetPerTick = 120

    // Broadcast-Firewall (Hintergrund-Laerm von Windows/Linux/macOS), Standardwerte wie am PC
    @Volatile private var noisePorts: Set<Int> = DEFAULT_NOISE.toSet()
    @Volatile private var noiseEnabled = true
    @Volatile private var noiseIgmp = true
    @Volatile private var noiseStrict = true

    // ---- Status ----
    @Volatile var state: String = "Getrennt"
        private set
    @Volatile var lastError: String = ""
        private set
    @Volatile var assignedIp: String = ""
        private set
    @Volatile var prefixLength: Int = 16
        private set
    @Volatile var publicEndpoint: String = ""
        private set
    @Volatile var serverReachable = false
        private set
    @Volatile var localPort = 0
        private set
    @Volatile var isRunning = false
        private set
    @Volatile var vip: Int = 0
        private set
    @Volatile var netMask: Int = 0
        private set
    @Volatile var broadcastIp: Int = 0
        private set

    val log = ConcurrentLinkedQueue<String>()

    /** Wird fuer jedes angenommene, geprueft eingehende IPv4-Paket aufgerufen. */
    @Volatile var inboundSink: ((ByteArray) -> Unit)? = null

    /** Wird aufgerufen, wenn der Server eine (neue) virtuelle IP zugewiesen hat. */
    @Volatile var onIpAssigned: ((Int, Int) -> Unit)? = null

    /** Optionaler Zusatz-Empfaenger fuer Protokollzeilen (z. B. Fehlerprotokoll der App). */
    @Volatile var logSink: ((String) -> Unit)? = null

    // ---- intern ----
    private val sync = Any()
    private val byNode = HashMap<Long, PesPeer>()
    private val byVip = HashMap<Int, PesPeer>()
    private var sock: DatagramSocket? = null
    private var stopLatch = CountDownLatch(1)
    private var udpThread: Thread? = null
    private var maintThread: Thread? = null
    @Volatile private var stopping = false
    private var cTun: PesP2pCrypto? = null
    private var cUdp: PesP2pCrypto? = null
    private var cMaint: PesP2pCrypto? = null
    private var lobbyId = ByteArray(16)
    private var machineKey = ByteArray(16)
    private var nodeId = 0L
    private var displayName = ""
    private var serverHost = ""
    private var serverPort = 0
    @Volatile private var serverEp: InetSocketAddress? = null
    private var lastResolveMs = -1000000L
    private val lastRegTxMs = AtomicLong(-1000000L)
    private val lastServerRxMs = AtomicLong(0)
    @Volatile private var gotWelcome = false
    private var lastGoneCleanMs = 0L
    private val seqCounter = AtomicInteger(0)
    @Volatile private var cookie = ByteArray(8)
    private var syncRev = 0
    private var syncTotal = 0
    private val syncIds = HashSet<Long>()
    private val gone = HashMap<Long, Pair<Int, Long>>()
    private val noiseBlocked = AtomicLong(0)

    val noiseBlockedCount: Long get() = noiseBlocked.get()
    val peerCount: Int get() = synchronized(sync) { byNode.size }
    val ownNodeId: Long get() = nodeId

    private fun addLog(text: String) {
        val t = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.ROOT).format(java.util.Date()) + "  " + text
        log.add(t)
        while (log.size > 400) log.poll()
        try { logSink?.invoke(t) } catch (_: Throwable) { }
    }

    private fun setState(s: String) {
        if (state != s) {
            state = s
            addLog("Status: $s")
        }
    }

    private fun nextSeq(): Int = seqCounter.incrementAndGet()

    // =========================================================================
    // START
    // =========================================================================
    fun start(serverHostName: String, serverUdpPort: Int, lobbyName: String, password: String, myName: String, machineKeyHex: String?) {
        if (isRunning) throw IllegalStateException("P2P laeuft bereits.")
        if (lobbyName.trim().length < 3) throw IllegalArgumentException("Der Lobby-Name muss mindestens 3 Zeichen haben.")
        if (password.length < 6) throw IllegalArgumentException("Das Lobby-Passwort muss mindestens 6 Zeichen haben.")
        if (serverHostName.isEmpty()) throw IllegalArgumentException("Kein Vermittlungsserver eingetragen.")

        stopping = false
        gotWelcome = false
        serverReachable = false
        vip = 0
        netMask = 0
        broadcastIp = 0
        assignedIp = ""
        publicEndpoint = ""
        lastError = ""
        lastResolveMs = -1000000L
        lastRegTxMs.set(-1000000L)
        lastServerRxMs.set(0)
        serverEp = null
        cookie = ByteArray(8)
        synchronized(sync) { byNode.clear(); byVip.clear(); gone.clear() }
        syncIds.clear()
        syncRev = 0
        syncTotal = 0
        stopLatch = CountDownLatch(1)

        serverHost = serverHostName.trim()
        serverPort = serverUdpPort
        displayName = if (myName.isEmpty()) "Android" else myName

        setState("Schluessel werden abgeleitet ...")
        lobbyId = PesKeys.deriveLobbyId(lobbyName)
        val km = PesKeys.deriveKeyMaterial(lobbyName, password)
        val encKey = km.copyOfRange(0, 32)
        val macKey = km.copyOfRange(32, 64)
        cTun = PesP2pCrypto(encKey, macKey)
        cUdp = PesP2pCrypto(encKey, macKey)
        cMaint = PesP2pCrypto(encKey, macKey)

        val rng = SecureRandom()
        val mk = if (machineKeyHex != null && machineKeyHex.length == 32) PesBytes.fromHex(machineKeyHex) else null
        machineKey = mk ?: ByteArray(16).also { rng.nextBytes(it) }
        val rnd = ByteArray(8)
        do {
            rng.nextBytes(rnd)
            nodeId = PesBytes.readI64(rnd, 0)
        } while (nodeId == 0L)
        seqCounter.set(rng.nextInt() and 0x0FFFFFFF)

        val s = DatagramSocket(null)
        try {
            s.reuseAddress = false
            try {
                s.bind(InetSocketAddress(preferredPort))
            } catch (e: java.net.SocketException) {
                addLog("UDP-Port $preferredPort ist belegt - nutze einen zufaelligen Port.")
                s.bind(InetSocketAddress(0))
            }
            s.soTimeout = 1000
            try { s.receiveBufferSize = 1 shl 20 } catch (_: Exception) { }
            try { s.sendBufferSize = 1 shl 20 } catch (_: Exception) { }
        } catch (e: Exception) {
            try { s.close() } catch (_: Exception) { }
            throw e
        }
        sock = s
        localPort = s.localPort
        isRunning = true
        addLog("Lokaler UDP-Port: $localPort")
        setState("Verbinde mit Vermittlungsserver ...")
        udpThread = Thread({ udpLoop() }, "PES-P2P-UDP").also { it.isDaemon = true; it.start() }
        maintThread = Thread({ maintLoop() }, "PES-P2P-MAINT").also { it.isDaemon = true; it.start() }
    }

    // =========================================================================
    // STOP
    // =========================================================================
    fun stop() {
        if (!isRunning) return
        stopping = true
        stopLatch.countDown()
        try { maintThread?.join(3000) } catch (_: InterruptedException) { }
        // Abmelden: Peers und Server sofort informieren (sonst erst nach Timeout)
        try {
            val empty = ByteArray(0)
            val c = cMaint
            if (c != null) {
                for (p in snapshotPeers()) {
                    val bye = c.seal(T_BYE, nodeId, nextSeq(), empty, 0, 0)
                    val d = p.directEp
                    if (p.path == 1 && d != null) sendRaw(bye, d)
                    else if (p.path == 2) sendRelay(p.nodeId, bye)
                }
            }
            val se = serverEp
            if (se != null) {
                val lv = ByteArray(3 + 16 + 8)
                lv[0] = 0x50
                lv[1] = 0x53
                lv[2] = S_LEAVE.toByte()
                System.arraycopy(lobbyId, 0, lv, 3, 16)
                PesBytes.writeI64(lv, 19, nodeId)
                sendRaw(lv, se)
            }
        } catch (_: Exception) { }
        try { sock?.close() } catch (_: Exception) { }
        try { udpThread?.join(3000) } catch (_: InterruptedException) { }
        isRunning = false
        serverReachable = false
        assignedIp = ""
        vip = 0
        synchronized(sync) { byNode.clear(); byVip.clear() }
        setState("Getrennt")
    }

    // =========================================================================
    // Ausgehend: IPv4-Pakete der lokalen Seite -> Peers
    // =========================================================================
    private fun countNoise() {
        noiseBlocked.incrementAndGet()
    }

    private fun isNoise(p: ByteArray, multi: Boolean): Boolean {
        if (!noiseEnabled) return false
        val proto = PesBytes.u8(p, 9)
        if (proto == 2) {
            if (noiseIgmp) { countNoise(); return true }
            return false
        }
        if (proto != 17) return false
        if (!multi && !noiseStrict) return false
        val ihl = (PesBytes.u8(p, 0) and 15) * 4
        if (p.size < ihl + 4) return true
        val sport = PesBytes.readU16(p, ihl)
        val dport = PesBytes.readU16(p, ihl + 2)
        val set = noisePorts
        if (set.contains(dport)) { countNoise(); return true }
        if (noiseStrict && set.contains(sport)) { countNoise(); return true }
        return false
    }

    /** Ein ausgehendes IPv4-Paket verschicken (Unicast an den Peer mit dieser virtuellen IP, Broadcast an alle). */
    fun sendIp(p: ByteArray) {
        if (p.size < 20 || (PesBytes.u8(p, 0) shr 4) != 4) return
        val my = vip
        if (my == 0) return
        val dst = PesBytes.readI32(p, 16)
        val multi = dst == -1 || dst == broadcastIp || ((dst ushr 28) == 0xE)
        if (isNoise(p, multi)) return
        if (multi) {
            for (peer in snapshotPeers()) if (peer.path != 0) sendData(peer, p)
            return
        }
        if ((dst and netMask) != (my and netMask)) return
        val target = synchronized(sync) { byVip[dst] }
        if (target == null || target.path == 0) return
        sendData(target, p)
    }

    private fun sendData(peer: PesPeer, ipPacket: ByteArray) {
        val c = cTun ?: return
        val wire = c.seal(T_DATA, nodeId, nextSeq(), ipPacket, 0, ipPacket.size)
        val d = peer.directEp
        if (peer.path == 1 && d != null) sendRaw(wire, d)
        else if (peer.path == 2) sendRelay(peer.nodeId, wire)
        else return
        peer.txBytes.addAndGet(ipPacket.size.toLong())
    }

    private fun sendRaw(data: ByteArray, ep: InetSocketAddress) {
        try {
            sock?.send(DatagramPacket(data, data.size, ep))
        } catch (_: IOException) {
        } catch (_: IllegalArgumentException) {
        }
    }

    private fun sendRelay(toNode: Long, wire: ByteArray) {
        val se = serverEp
        if (se == null || !allowRelay) return
        val r = ByteArray(3 + 16 + 8 + 8 + wire.size)
        r[0] = 0x50
        r[1] = 0x53
        r[2] = S_RELAY.toByte()
        System.arraycopy(lobbyId, 0, r, 3, 16)
        PesBytes.writeI64(r, 19, nodeId)
        PesBytes.writeI64(r, 27, toNode)
        System.arraycopy(wire, 0, r, 35, wire.size)
        sendRaw(r, se)
    }

    // =========================================================================
    // Eingehend: UDP-Thread
    // =========================================================================
    private fun udpLoop() {
        val buf = ByteArray(65536)
        val dp = DatagramPacket(buf, buf.size)
        while (!stopping) {
            val s = sock ?: break
            try {
                dp.setData(buf, 0, buf.size)
                s.receive(dp)
            } catch (e: SocketTimeoutException) {
                continue
            } catch (e: IOException) {
                if (stopping || s.isClosed) break
                addLog("UDP-Fehler: ${e.message}")
                try { Thread.sleep(50) } catch (_: InterruptedException) { }
                continue
            }
            val n = dp.length
            if (n < 3) continue
            val addr = dp.socketAddress as? InetSocketAddress ?: continue
            val ep = normalize(addr)
            try {
                if (buf[0].toInt() == 0x50 && buf[1].toInt() == 0x53) {
                    val se2 = serverEp
                    if (se2 != null && se2 == ep) handleServer(buf, n, ep)
                } else if (buf[0].toInt() == 0x50 && buf[1].toInt() == 0x45) {
                    handlePeerPacket(buf, 0, n, ep, false)
                }
            } catch (ex: Exception) {
                addLog("Paketfehler: ${ex.javaClass.simpleName}: ${ex.message}")
            }
        }
    }

    /** IPv4-gemappte IPv6-Adressen auf echte IPv4 abbilden, damit Vergleiche stimmen. */
    private fun normalize(a: InetSocketAddress): InetSocketAddress {
        val ad = a.address
        if (ad is Inet4Address) return a
        val b = ad?.address
        if (b != null && b.size == 16) {
            var mapped = true
            for (i in 0 until 10) if (b[i].toInt() != 0) mapped = false
            if (b[10].toInt() != -1 || b[11].toInt() != -1) mapped = false
            if (mapped) return InetSocketAddress(InetAddress.getByAddress(b.copyOfRange(12, 16)), a.port)
        }
        return a
    }

    private fun replayOk(p: PesPeer, seq: Int): Boolean {
        synchronized(p) {
            if (!p.anySeq) {
                p.anySeq = true
                p.maxSeq = seq
                p.window = 1L
                return true
            }
            if (Integer.compareUnsigned(seq, p.maxSeq) > 0) {
                val d = seq - p.maxSeq
                p.window = if (Integer.compareUnsigned(d, 64) >= 0) 1L else ((p.window shl d) or 1L)
                p.maxSeq = seq
                return true
            }
            val back = p.maxSeq - seq
            if (Integer.compareUnsigned(back, 64) >= 0) return false
            val bit = 1L shl back
            if ((p.window and bit) != 0L) return false
            p.window = p.window or bit
            return true
        }
    }

    private fun handlePeerPacket(buf: ByteArray, off: Int, len: Int, ep: InetSocketAddress, viaRelay: Boolean) {
        if (len < PesP2pCrypto.HDR + PesP2pCrypto.TAG) return
        val sender = PesBytes.readI64(buf, off + 3)
        if (sender == nodeId) return
        val p = synchronized(sync) { byNode[sender] } ?: return // (noch) nicht in der Lobby-Liste
        val opened = cUdp!!.open(buf, off, len)
        if (opened == null) {
            val f = ++p.authFails
            if (f == 5) addLog("Pakete von ${p.name} lassen sich nicht pruefen - anderes Lobby-Passwort?")
            return
        }
        if (!replayOk(p, opened.seq)) return
        p.authFails = 0
        p.lastRxMs.set(now())

        if (!viaRelay) {
            val cur = p.directEp
            if (p.path != 1 || cur == null) {
                p.directEp = ep
                p.path = 1
                addLog("Direktverbindung (Hole Punching) mit ${p.name} ueber ${fmt(ep)}")
            } else if (cur != ep && (PesBytes.isPrivate(ep.address) || !PesBytes.isPrivate(cur.address))) {
                // Roaming / besserer Weg (z. B. gleiches Heimnetz statt Umweg ueber die Public-IP)
                p.directEp = ep
                addLog("Weg zu ${p.name} gewechselt -> ${fmt(ep)}")
            }
        } else if (p.path == 0) {
            p.path = 2
            addLog("Verbindung mit ${p.name} laeuft ueber Relay (Vermittlungsserver).")
        }

        val body = opened.body
        when (opened.type) {
            T_HELLO -> if (body.size >= 16 && PesBytes.readI64(body, 0) == nodeId) {
                val ack = ByteArray(16)
                PesBytes.writeI64(ack, 0, sender)
                System.arraycopy(body, 8, ack, 8, 8)
                val w = cUdp!!.seal(T_HELLO_ACK, nodeId, nextSeq(), ack, 0, 16)
                if (viaRelay) sendRelay(sender, w) else sendRaw(w, ep)
            }
            T_HELLO_ACK -> if (body.size >= 16 && PesBytes.readI64(body, 0) == nodeId) {
                val rtt = now() - PesBytes.readI64(body, 8)
                if (rtt in 0..9999) p.rttMs = rtt.toInt()
            }
            T_DATA -> deliverInbound(p, body)
            T_BYE -> {
                p.path = 0
                p.directEp = null
                p.inServerList = false
                addLog("${p.name} hat die Lobby verlassen.")
            }
        }
    }

    private fun fmt(ep: InetSocketAddress): String = (ep.address?.hostAddress ?: ep.hostString) + ":" + ep.port

    private fun deliverInbound(p: PesPeer, ip: ByteArray) {
        if (ip.size < 20 || (PesBytes.u8(ip, 0) shr 4) != 4) return
        val src = PesBytes.readI32(ip, 12)
        val dst = PesBytes.readI32(ip, 16)
        if (src != p.vip) return // Anti-Spoofing: nur die eigene virtuelle IP des Peers
        val my = vip
        val multiIn = dst == -1 || dst == broadcastIp || ((dst ushr 28) == 0xE)
        if (!(dst == my || multiIn)) return
        if (isNoise(ip, multiIn)) return
        if (stopping) return
        p.rxBytes.addAndGet(ip.size.toLong())
        inboundSink?.invoke(ip)
    }

    // =========================================================================
    // Signaling: Nachrichten vom Vermittlungsserver
    // =========================================================================
    private fun readEp(b: ByteArray, o: Int): InetSocketAddress {
        val a = ByteArray(4)
        System.arraycopy(b, o, a, 0, 4)
        return InetSocketAddress(InetAddress.getByAddress(a), PesBytes.readU16(b, o + 4))
    }

    private fun handleServer(b: ByteArray, n: Int, ep: InetSocketAddress) {
        lastServerRxMs.set(now())
        if (!serverReachable) {
            serverReachable = true
            if (gotWelcome) setState("Verbunden")
        }
        val t = PesBytes.u8(b, 2)
        if (t == S_WELCOME && n >= 3 + 4 + 6 + 1 + 8) {
            val newVip = PesBytes.readI32(b, 3)
            val pub = readEp(b, 7)
            var prefix = PesBytes.u8(b, 13)
            val ck = ByteArray(8)
            System.arraycopy(b, 14, ck, 0, 8)
            cookie = ck
            if (newVip == 0) {
                // Erste Antwort: nur Cookie (beweist, dass wir unter dieser Adresse erreichbar
                // sind - Schutz gegen gefaelschte Absender). Sofort erneut registrieren.
                lastRegTxMs.set(-1000000L)
                return
            }
            if (prefix < 8 || prefix > 30) prefix = 16
            val m = if (prefix == 0) 0 else (-1 shl (32 - prefix))
            publicEndpoint = fmt(pub)
            var changed = false
            if (newVip != vip || m != netMask) {
                netMask = m
                broadcastIp = (newVip and m) or m.inv()
                vip = newVip
                prefixLength = prefix
                assignedIp = PesBytes.ipToString(newVip)
                changed = true
                addLog("Virtuelle IP zugewiesen: $assignedIp/$prefix (oeffentlich sichtbar als $publicEndpoint)")
            }
            gotWelcome = true
            setState("Verbunden")
            if (changed) {
                try { onIpAssigned?.invoke(newVip, prefix) } catch (ex: Exception) { addLog("IP-Zuweisung: ${ex.message}") }
            }
        } else if (t == S_PEER && n >= 3 + 8 + 4 + 6 + 2) {
            applyPeer(b, n, 3, false, 0)
        } else if (t == S_PEER2 && n >= 8 + 8 + 4 + 6 + 2) {
            applyPeer(b, n, 8, true, PesBytes.readI32(b, 4))
        } else if (t == S_GONE && n >= 15) {
            val rev = PesBytes.readI32(b, 3)
            val nid = PesBytes.readI64(b, 7)
            synchronized(sync) {
                gone[nid] = Pair(rev, now())
                val p = byNode[nid]
                if (p != null && (!p.hasRev || !newer(p.infoRev, rev))) p.inServerList = false
            }
        } else if (t == S_SYNC && n >= 12) {
            val rev = PesBytes.readI32(b, 3)
            val total = PesBytes.readU16(b, 7)
            val cnt = PesBytes.u8(b, 11)
            if (rev != syncRev || syncTotal != total) {
                syncRev = rev
                syncTotal = total
                syncIds.clear()
            }
            var i = 0
            while (i < cnt && 12 + i * 8 + 8 <= n) {
                syncIds.add(PesBytes.readI64(b, 12 + i * 8))
                i++
            }
            if (syncIds.size >= syncTotal) {
                synchronized(sync) {
                    for (p in byNode.values) {
                        val g = gone[p.nodeId]
                        val goneLater = g != null && newer(g.first, rev)
                        if (syncIds.contains(p.nodeId)) {
                            if (!goneLater) p.inServerList = true
                        } else if (!p.hasRev || !newer(p.infoRev, rev)) {
                            p.inServerList = false
                        }
                    }
                }
                syncIds.clear()
                syncTotal = -1
            }
        } else if (t == S_MEMBERS && n >= 4) {
            val cnt = PesBytes.u8(b, 3)
            val set = HashSet<Long>()
            var i = 0
            while (i < cnt && 4 + i * 8 + 8 <= n) {
                set.add(PesBytes.readI64(b, 4 + i * 8))
                i++
            }
            synchronized(sync) { for (p in byNode.values) p.inServerList = set.contains(p.nodeId) }
        } else if (t == S_RELAYED && n >= 3 + 8 + PesP2pCrypto.HDR + PesP2pCrypto.TAG) {
            val from = PesBytes.readI64(b, 3)
            if (PesBytes.readI64(b, 11 + 3) != from) return // Absender im Paket muss zum Relay-Absender passen
            handlePeerPacket(b, 11, n - 11, ep, true)
        } else if (t == S_ERROR && n >= 5) {
            val ml = minOf(PesBytes.u8(b, 4), n - 5)
            val msg = String(b, 5, ml, StandardCharsets.UTF_8)
            lastError = msg
            setState("Fehler: $msg")
        }
    }

    /** Mitspieler-Info aus PEER (alt) bzw. PEER2 (mit Revision) uebernehmen. */
    private fun applyPeer(b: ByteArray, n: Int, start: Int, withRev: Boolean, rev: Int) {
        var o = start
        val nid = PesBytes.readI64(b, o); o += 8
        val pv = PesBytes.readI32(b, o); o += 4
        val pub = readEp(b, o); o += 6
        val nl = PesBytes.u8(b, o++)
        if (o + nl + 1 > n) return
        val nm = String(b, o, nl, StandardCharsets.UTF_8); o += nl
        val cnt = PesBytes.u8(b, o++)
        val locals = ArrayList<InetSocketAddress>()
        var i = 0
        while (i < cnt && o + 6 <= n) {
            locals.add(readEp(b, o))
            o += 6
            i++
        }
        if (nid == nodeId) return
        var isNew = false
        synchronized(sync) {
            if (withRev) {
                val g = gone[nid]
                if (g != null) {
                    if (!newer(rev, g.first)) return // verspaetete Info ueber jemanden, der schon weg ist
                    gone.remove(nid)
                }
            }
            var p = byNode[nid]
            if (p != null && withRev && p.hasRev && newer(p.infoRev, rev)) return // aeltere Info
            if (p == null) {
                p = PesPeer(nid)
                p.punchStartMs = now()
                byNode[nid] = p
                isNew = true
            }
            if (p.vip != pv) {
                if (p.vip != 0) {
                    val old = byVip[p.vip]
                    if (old === p) byVip.remove(p.vip)
                }
                p.vip = pv
                byVip[pv] = p
            }
            p.name = nm
            p.publicEp = pub
            p.localEps = locals
            p.inServerList = true
            if (withRev) {
                p.hasRev = true
                p.infoRev = rev
            }
        }
        if (isNew) addLog("Mitspieler in der Lobby: $nm (${PesBytes.ipToString(pv)}) - starte Hole Punching an ${fmt(pub)}")
    }

    private fun getLocalCandidates(): List<InetSocketAddress> {
        val list = ArrayList<InetSocketAddress>()
        try {
            val e = NetworkInterface.getNetworkInterfaces() ?: return list
            for (ni in e) {
                try {
                    if (!ni.isUp || ni.isLoopback) continue
                } catch (_: Exception) { continue }
                for (ia in ni.interfaceAddresses) {
                    val a = ia.address
                    if (a !is Inet4Address) continue
                    val bb = a.address
                    if (PesBytes.u8(bb, 0) == 169 && PesBytes.u8(bb, 1) == 254) continue
                    val u = PesBytes.readI32(bb, 0)
                    val m = netMask
                    if (m != 0 && (u and m) == (vip and m)) continue
                    list.add(InetSocketAddress(a, localPort))
                    if (list.size >= 6) return list
                }
            }
        } catch (_: Exception) { }
        return list
    }

    private fun listDigest(): Long {
        var d = 0L
        synchronized(sync) {
            for (p in byNode.values) if (p.hasRev && p.inServerList) d = d xor mix(p.nodeId, p.infoRev)
        }
        return d
    }

    private fun sendRegister() {
        val se = serverEp ?: return
        val nm = PesBytes.utf8Limit(displayName, 32)
        val locals = getLocalCandidates()
        val p = ByteArray(4 + 16 + 8 + 16 + 1 + nm.size + 1 + locals.size * 6 + 8 + 9)
        p[0] = 0x50
        p[1] = 0x53
        p[2] = S_REGISTER.toByte()
        p[3] = PROTO_VERSION.toByte()
        System.arraycopy(lobbyId, 0, p, 4, 16)
        PesBytes.writeI64(p, 20, nodeId)
        System.arraycopy(machineKey, 0, p, 28, 16)
        var o = 44
        p[o++] = nm.size.toByte()
        System.arraycopy(nm, 0, p, o, nm.size)
        o += nm.size
        p[o++] = locals.size.toByte()
        for (l in locals) {
            System.arraycopy(l.address.address, 0, p, o, 4)
            PesBytes.writeU16(p, o + 4, l.port)
            o += 6
        }
        System.arraycopy(cookie, 0, p, o, 8)
        // Erweiterung E2: eigener Stand der Mitgliederliste (alte Server ignorieren das)
        p[o + 8] = EXT_V2.toByte()
        PesBytes.writeI64(p, o + 9, listDigest())
        sendRaw(p, se)
    }

    private fun sendHello(p: PesPeer, ep: InetSocketAddress?, viaRelay: Boolean) {
        val body = ByteArray(16)
        PesBytes.writeI64(body, 0, p.nodeId)
        PesBytes.writeI64(body, 8, now())
        val w = cMaint!!.seal(T_HELLO, nodeId, nextSeq(), body, 0, 16)
        if (viaRelay) sendRelay(p.nodeId, w) else if (ep != null) sendRaw(w, ep)
    }

    // =========================================================================
    // Wartung - Registrierung, Hole Punching, Keepalive, Timeouts
    // =========================================================================
    private fun maintLoop() {
        while (!stopping) {
            try {
                maintTick()
            } catch (ex: Exception) {
                addLog("Wartungsfehler: ${ex.javaClass.simpleName}: ${ex.message}")
            }
            try {
                if (stopLatch.await(200, TimeUnit.MILLISECONDS)) break
            } catch (_: InterruptedException) {
                break
            }
        }
    }

    private fun maintTick() {
        val now = now()

        // DNS des Servers alle 5 Minuten neu aufloesen (DynDNS-tauglich)
        if (serverEp == null || now - lastResolveMs > 300000) {
            lastResolveMs = now
            try {
                var ip: InetAddress? = null
                val lit = PesBytes.parseIp(serverHost)
                if (lit != null) {
                    ip = PesBytes.intToInet(lit)
                } else {
                    for (a in InetAddress.getAllByName(serverHost)) {
                        if (a is Inet4Address) { ip = a; break }
                    }
                }
                if (ip != null) {
                    val ne = InetSocketAddress(ip, serverPort)
                    if (serverEp == null || serverEp != ne) {
                        serverEp = ne
                        addLog("Vermittlungsserver: ${fmt(ne)}")
                    }
                } else if (serverEp == null) {
                    setState("Fehler: Server-Adresse nicht aufloesbar")
                }
            } catch (ex: Exception) {
                if (serverEp == null) setState("Fehler: Server nicht aufloesbar (${ex.message})")
            }
        }

        // Registrierung / Keepalive beim Server (anfangs schnell, dann alle 10 s)
        val sinceSrv = now - lastServerRxMs.get()
        val regInterval = if (gotWelcome && serverReachable) 10000 else 2000
        if (now - lastRegTxMs.get() >= regInterval) {
            lastRegTxMs.set(now)
            sendRegister()
        }
        if (serverReachable && sinceSrv > 35000) {
            serverReachable = false
            setState(if (gotWelcome) "Server nicht erreichbar - bestehende Direktverbindungen bleiben aktiv" else "Verbinde mit Vermittlungsserver ...")
        }

        if (!gotWelcome) return // ohne eigene IP kein Punching

        // Alte "ist weg"-Merker aufraeumen (nur gegen verspaetete Pakete noetig)
        if (gone.isNotEmpty() && now - lastGoneCleanMs > 30000) {
            lastGoneCleanMs = now
            synchronized(sync) {
                val old = gone.entries.filter { now - it.value.second > 120000 }.map { it.key }
                for (id in old) gone.remove(id)
            }
        }

        var budget = punchBudgetPerTick
        for (p in snapshotPeers()) {
            val lastRx = p.lastRxMs.get()

            if (p.path != 0 && lastRx > 0 && now - lastRx > peerTimeoutMs) {
                addLog("Keine Antwort mehr von ${p.name} - baue Verbindung neu auf.")
                p.path = 0
                p.directEp = null
                p.punchStartMs = now
                p.rttMs = -1
                p.punching = false
            }

            if (p.path == 1) {
                // Keepalive haelt das NAT-Loch offen (typische UDP-Timeouts: 30-120 s)
                val d = p.directEp
                if (d != null && now - p.lastHelloMs >= 5000) {
                    p.lastHelloMs = now
                    sendHello(p, d, false)
                }
            } else {
                // UDP Hole Punching: beide Seiten senden gleichzeitig an alle bekannten Adressen
                if (!p.punching) {
                    if (budget <= 0) continue
                    p.punching = true
                    p.punchStartMs = now
                }
                val since = now - p.punchStartMs
                val iv = if (since < 10000) 250 else 2000
                if (now - p.lastHelloMs >= iv && budget > 0) {
                    budget--
                    p.lastHelloMs = now
                    p.publicEp?.let { sendHello(p, it, false) }
                    for (l in p.localEps) sendHello(p, l, false)
                }
                if (p.path == 0 && since > punchTimeoutMs && allowRelay && serverReachable) {
                    p.path = 2
                    addLog("Kein direkter Weg zu ${p.name} (symmetrisches NAT?) - nutze Relay ueber den Vermittlungsserver.")
                }
                if (p.path == 2 && now - p.lastRelayHelloMs >= 2000) {
                    p.lastRelayHelloMs = now
                    sendHello(p, null, true)
                }
            }

            if (!p.inServerList && (lastRx == 0L || now - lastRx > 15000)) {
                synchronized(sync) {
                    byNode.remove(p.nodeId)
                    val cur = byVip[p.vip]
                    if (cur === p) byVip.remove(p.vip)
                }
                addLog("${p.name} ist nicht mehr in der Lobby.")
            }
        }
    }

    private fun snapshotPeers(): List<PesPeer> = synchronized(sync) { ArrayList(byNode.values) }

    /** Fuer die Oberflaeche. */
    fun getPeers(): List<PesPeerInfo> {
        val r = ArrayList<PesPeerInfo>()
        for (p in snapshotPeers()) {
            val d = p.directEp
            val mode: String
            val endpoint: String
            when (p.path) {
                1 -> { mode = "Direkt"; endpoint = if (d == null) "" else fmt(d) }
                2 -> { mode = "Relay"; endpoint = "ueber Server" }
                else -> {
                    mode = if (p.authFails >= 5) "Passwort falsch?" else "Verbinde ..."
                    endpoint = p.publicEp?.let { fmt(it) } ?: ""
                }
            }
            r.add(PesPeerInfo(p.nodeId, p.name, p.vip, mode, endpoint, if (p.path == 0) -1 else p.rttMs, p.rxBytes.get(), p.txBytes.get(), p.path))
        }
        r.sortWith { a, b -> a.name.compareTo(b.name, ignoreCase = true) }
        return r
    }
}
