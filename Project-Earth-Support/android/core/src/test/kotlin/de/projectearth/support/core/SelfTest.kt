package de.projectearth.support.core

import java.io.File
import java.security.MessageDigest
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import kotlin.system.exitProcess

/**
 * Selbsttest des Kotlin-Kerns (reine JVM, ohne Android).
 *   kk <Vermittler-Port>                        Kotlin-Helfer <-> Kotlin-Kunde in einem Prozess
 *   interop <Port> <Lobby> <Passwort> <Ordner>  Kotlin-Helfer gegen den C#-Kunden aus Project-Earth-Support.ps1
 * Der Vermittler laeuft jeweils ausserhalb (C#, gestartet vom Testskript).
 */
object SelfTest {
    private var fail = 0

    private fun check(ok: Boolean, what: String) {
        if (ok) println("  OK   $what") else { println("  FEHLER $what"); fail++ }
    }

    private fun waitFor(ms: Long = 10000, cond: () -> Boolean): Boolean {
        val end = System.currentTimeMillis() + ms
        while (System.currentTimeMillis() < end) {
            if (cond()) return true
            Thread.sleep(20)
        }
        return false
    }

    private fun drain(s: PesSession): List<String> {
        val l = ArrayList<String>()
        while (true) l.add((s.events.poll() ?: break).replace(PesProto.SEP, '|'))
        return l
    }

    private fun sha(f: File): String = PesBytes.hex(MessageDigest.getInstance("SHA-256").digest(f.readBytes()))

    /** Fuer den JUnit-Lauf: nur die Pruefungen ohne Netz; liefert die Zahl der Fehler. */
    fun runUnit(): Int { fail = 0; unitChecks(); return fail }

    private fun unitChecks() {
        val code = PesProto.inviteCreate("host.example:9890", "pes-abc", "geheim-1234567890")
        val inv = PesProto.inviteParse("Text davor $code und danach")
        check(inv != null && inv.server == "host.example:9890" && inv.lobby == "pes-abc" && inv.password == "geheim-1234567890", "Einladungscode erzeugen und lesen")
        check(PesProto.inviteParse("PEL1:abcd") == null, "PEL-Code wird nicht angenommen")
        check(PesProto.newPassword().length >= 16, "Passwort mindestens 16 Zeichen")
        check(PesProto.cleanFileName("..\\..\\Windows\\evil?.exe") == "evil_.exe", "Dateiname bereinigen")
        check(PesProto.cleanFileName("CON.txt") == "_CON.txt", "Reservierte Namen")
        check(PesProto.parseServer("a.b:1")?.second == 1 && PesProto.parseServer("a b") == null && PesProto.parseServer("x:99999") == null, "Server-Adresse pruefen")
        var mu = true
        for (v in intArrayOf(0, 1, -1, 100, -100, 1000, -1000, 12345, -12345, 32000, -32000)) {
            val d = PesProto.muLawDecode(PesProto.muLawEncode(v.toShort())).toInt()
            if (Math.abs(d - v) > maxOf(16, Math.abs(v) / 16)) mu = false
        }
        check(mu, "u-law hin und zurueck")
        val w = PesProto.wrap(0x0A4D0102, 0x0A4D0304, 7, byteArrayOf(0xA8.toByte(), 1, 2, 3))
        val u = PesProto.unwrap(w)
        check(u != null && u.second == 4 && u.third == 0x0A4D0102 && w[u.first + 3].toInt() == 3, "IPv4/UDP-Huelle")
        // Strom: Verlust, Vertauschung, grosse Nachricht
        val a = PesRel(0); val b = PesRel(0)
        val rnd = java.util.Random(5)
        val msgs = listOf(ByteArray(1) { 9 }, ByteArray(250000) { (it * 3).toByte() }, ByteArray(1100) { 1 }, ByteArray(1101) { 2 }, ByteArray(70000) { (it * 5).toByte() })
        for (m in msgs) a.enqueue(m)
        val got = ArrayList<ByteArray>()
        var now = 0L
        var guard = 0
        while (got.size < msgs.size && guard++ < 200000) {
            now += 5
            val pk = ArrayList<ByteArray>()
            a.pump(now, 12, pk)
            pk.shuffle(rnd)
            for (p in pk) {
                if (rnd.nextInt(100) < 15) continue
                b.onData(p, 0, p.size, got)
                val ack = b.buildAck()
                if (rnd.nextInt(100) < 15) continue
                val more = ArrayList<ByteArray>()
                a.onAck(PesBytes.readI32(ack, 0), PesBytes.readI64(ack, 4), now, more)
                for (q in more) { if (rnd.nextInt(100) >= 15) b.onData(q, 0, q.size, got) }
            }
        }
        var same = got.size == msgs.size
        for (i in got.indices) if (same && !got[i].contentEquals(msgs[i])) same = false
        check(same, "Strom liefert alles vollstaendig und in Reihenfolge (15 % Verlust, vertauscht; ${a.retransmits} Wiederholungen)")
    }

    private class Sink {
        val frames = ConcurrentLinkedQueue<ByteArray>()
        val rects = ConcurrentLinkedQueue<IntArray>()
        val inputs = ConcurrentLinkedQueue<ByteArray>()
        @Volatile var rot = -1
        val rectBytes = AtomicLong(0)
        val badRect = AtomicInteger(0)
    }

    /** Ablauf aus Sicht des Helfers; der Kunde ist entweder im selben Prozess ([cust]) oder der C#-Knoten. */
    private fun helperFlow(port: Int, lobby: String, pw: String, dir: File, cust: PesSession?) {
        val eA = PesP2pEngine()
        eA.preferredPort = 39894
        eA.start("127.0.0.1", port, lobby, pw, "Helfer-Handy", null)
        val sA = PesSession(eA)
        sA.myName = "Helfer"; sA.role = PesProto.ROLE_HELPER
        sA.downloadDir = File(dir, "A")
        val sink = Sink()
        sA.onScreenRect = { r, j ->
            for (i in j.indices) if (j[i] != ((i * 7 + r[2]) and 255).toByte()) { sink.badRect.incrementAndGet(); break }
            sink.rectBytes.addAndGet(j.size.toLong()); sink.rects.add(r)
        }
        sA.onVideoFrame = { j, r -> sink.rot = r; sink.frames.add(j) }
        sA.start()
        check(waitFor(25000) { sA.paired && sA.partnerName == "Kunde" }, "Kopplung Helfer <-> Kunde")
        Thread.sleep(600)
        check(drain(sA).any { it.startsWith("PEER|up|Kunde") }, "Ereignis PEER up beim Helfer")
        println("  Wege: " + eA.getPeers().joinToString { it.name + "=" + it.mode })

        // Chat (der Kunde antwortet mit "Echo: ...")
        sA.sendChat("Hallo Kunde 123")
        var echo = false
        waitFor(8000) { for (e in drain(sA)) if (e.startsWith("CHAT|") && e.endsWith("Echo: Hallo Kunde 123")) echo = true; echo }
        check(echo, "Chat hin und zurueck")

        // Anruf: der Kunde nimmt automatisch an und schickt Ton und ein Videobild
        check(sA.call(), "Anruf starten")
        check(waitFor(8000) { sA.callState == PesProto.CALL_ACTIVE }, "Anruf aktiv")
        sA.setMedia(true, true)
        val frame = ShortArray(320) { (8000 * Math.sin(it / 5.0)).toInt().toShort() }
        var heard = false
        for (i in 0 until 150) {
            sA.sendAudio(frame)
            if (i % 5 == 0) sA.sendVideo(ByteArray(5000) { (it * 11).toByte() }, 1)
            val f = sA.pullAudio()
            if (f.any { Math.abs(it.toInt()) > 2000 }) heard = true
            Thread.sleep(20)
            if (heard && sink.frames.isNotEmpty()) break
        }
        check(heard, "Ton vom Kunden kommt an")
        val vf = sink.frames.poll()
        check(vf != null && vf.size == 9000 && vf[0] == 0.toByte() && vf[8999] == ((8999 * 13) and 255).toByte() && sink.rot == 2, "Videobild vom Kunden kommt an (9 Teile, Drehung 2)")
        check(waitFor(5000) { sA.partnerCam }, "Kamera-Zustand des Kunden gemeldet")

        // Bildschirm
        check(!sA.inputKey(65, true, false), "Keine Eingabe ohne Erlaubnis")
        sA.requestScreen(2)
        check(waitFor(10000) { sA.shareActive && sA.controlActive }, "Freigabe mit Steuerung gemeldet")
        val sizes = intArrayOf(300000, 1500, 60000, 1, 1100, 1101, 250000, 40000)
        check(waitFor(60000) { sink.rects.size == sizes.size }, "Alle ${sizes.size} Rechtecke angekommen")
        check(sink.badRect.get() == 0 && sink.rectBytes.get() == sizes.sum().toLong(), "Rechteck-Inhalte unveraendert")
        var ordered = true
        var i = 0
        while (true) { val r = sink.rects.poll() ?: break; if (r[2] != 64 * i || r[0] != 1280 || r[1] != 720) ordered = false; i++ }
        check(ordered, "Reihenfolge und Masse der Rechtecke")
        sA.inputButton(0, true, 1000, 2000); sA.inputButton(0, false, 1000, 2000)
        sA.inputKey(0x41, true, false); sA.inputText("abc"); sA.inputMove(30000, 40000)
        sA.setScreenOptions(3, 1)
        Thread.sleep(400)
        sA.sendChat("INPUTS?")
        var inputsOk = false
        waitFor(8000) { for (e in drain(sA)) if (e.startsWith("CHAT|") && e.endsWith("Inputs: 2:0:1:1000:2000 2:0:0:1000:2000 4:65:1 5:abc 1:30000:40000 opt:3:1")) inputsOk = true; inputsOk }
        check(inputsOk, "Eingaben und Qualitaetswunsch kommen beim Kunden richtig an")
        sA.requestScreen(3)
        check(waitFor(8000) { !sA.shareActive }, "Freigabe beendet gemeldet")
        check(!sA.inputKey(65, true, false), "Nach dem Beenden keine Eingabe mehr")

        // Datei hin (der Kunde nimmt automatisch an) und zurueck (der Kunde schickt sie wieder)
        val src = File(dir, "quelle test.bin")
        val data = ByteArray(3 * 1024 * 1024 + 4321); java.util.Random(7).nextBytes(data); src.writeBytes(data)
        check(sA.offerFile(src) == null, "Datei anbieten")
        check(waitFor(120000) { sA.txFile()?.state == 2 }, "Datei gesendet und bestaetigt")
        var offer = false
        waitFor(20000) { for (e in drain(sA)) if (e.startsWith("FILE|offer|") && e.contains("quelle test.bin")) offer = true; offer }
        check(offer, "Rueck-Angebot kommt an")
        check(sA.answerFile(true) == null, "Rueck-Angebot annehmen")
        check(waitFor(120000) { sA.rxFile()?.state == 2 }, "Datei zurueck empfangen")
        val back = File(File(dir, "A"), "quelle test.bin")
        check(back.isFile && sha(back) == sha(src), "Zurueckerhaltene Datei ist identisch (SHA-256)")
        check((File(dir, "A").listFiles() ?: emptyArray()).none { it.name.endsWith(".part") }, "Keine Teil-Datei uebrig")

        sA.hangup()
        println("  Wiederholte Pakete: " + sA.retransmits + ", RTT " + sA.rtt + " ms")
        sA.sendChat("ENDE")
        Thread.sleep(500)
        sA.stop()
        if (cust != null) check(waitFor(5000) { !cust.paired }, "Abmeldung wird sofort erkannt")
        eA.stop()
    }

    /** Kunde im selben Prozess, mit demselben Verhalten wie der C#-Testknoten. */
    private fun startKotlinCustomer(port: Int, lobby: String, pw: String, dir: File): Pair<PesP2pEngine, PesSession> {
        val eB = PesP2pEngine()
        eB.preferredPort = 39895
        eB.start("127.0.0.1", port, lobby, pw, "Kunden-PC", null)
        val sB = PesSession(eB)
        sB.myName = "Kunde"; sB.role = PesProto.ROLE_CUSTOMER; sB.platform = 1
        sB.downloadDir = File(dir, "B")
        val inputs = ConcurrentLinkedQueue<String>()
        sB.onInput = { b ->
            val k = b[0].toInt()
            inputs.add(when (k) {
                1 -> "1:" + PesBytes.readU16(b, 1) + ":" + PesBytes.readU16(b, 3)
                2 -> "2:" + b[1] + ":" + b[2] + ":" + PesBytes.readU16(b, 3) + ":" + PesBytes.readU16(b, 5)
                4 -> "4:" + PesBytes.readU16(b, 1) + ":" + b[3]
                5 -> "5:" + String(b, 1, b.size - 1, Charsets.UTF_8)
                else -> "?"
            })
        }
        sB.start()
        Thread({
            var end = false
            var opt = ""
            while (!end && sB.isRunning) {
                for (e in drain(sB)) {
                    val f = e.split('|')
                    when {
                        f[0] == "CHAT" && f[2] == "ENDE" -> end = true
                        f[0] == "CHAT" && f[2] == "INPUTS?" -> sB.sendChat("Inputs: " + inputs.joinToString(" ") + " " + opt)
                        f[0] == "CHAT" -> sB.sendChat("Echo: " + f[2])
                        f[0] == "CALL" && f[1] == "in" -> sB.answerCall(true)
                        f[0] == "CALL" && f[1] == "active" -> {
                            sB.setMedia(true, true)
                            Thread({
                                val fr = ShortArray(320) { (9000 * Math.sin(it / 4.0)).toInt().toShort() }
                                for (i in 0 until 200) {
                                    if (sB.callState != PesProto.CALL_ACTIVE) break
                                    sB.sendAudio(fr)
                                    if (i % 5 == 0) sB.sendVideo(ByteArray(9000) { (it * 13).toByte() }, 2)
                                    Thread.sleep(20)
                                }
                            }, "test-media").start()
                        }
                        f[0] == "SCREEN" && f[1] == "req" && f[2] == "2" -> {
                            sB.setShare(true, true, 1280, 720, 0, 1)
                            var n = 0
                            for (size in intArrayOf(300000, 1500, 60000, 1, 1100, 1101, 250000, 40000)) {
                                val x = 64 * n
                                sB.sendScreenRect(1280, 720, x, 0, 64, 64, 1, ByteArray(size) { ((it * 7 + x) and 255).toByte() })
                                n++
                            }
                        }
                        f[0] == "SCREEN" && f[1] == "req" && f[2] == "3" -> sB.setShare(false, false, 0, 0, 0, 1)
                        f[0] == "SCREEN" && f[1] == "opt" -> opt = "opt:" + f[2] + ":" + f[3]
                        f[0] == "FILE" && f[1] == "offer" -> sB.answerFile(true)
                        f[0] == "FILE" && f[1] == "received" -> sB.offerFile(File(f[3]))
                    }
                }
                Thread.sleep(20)
            }
        }, "test-customer").also { it.isDaemon = true }.start()
        return Pair(eB, sB)
    }

    @JvmStatic
    fun main(args: Array<String>) {
        val mode = args.getOrNull(0) ?: "unit"
        println("Kotlin-Selbsttest: $mode")
        unitChecks()
        if (mode == "kk") {
            val port = args[1].toInt()
            val dir = File(System.getProperty("java.io.tmpdir"), "pes-kt-" + System.nanoTime()).also { it.mkdirs() }
            val lobby = PesProto.newLobby(); val pw = PesProto.newPassword()
            val c = startKotlinCustomer(port, lobby, pw, dir)
            helperFlow(port, lobby, pw, dir, c.second)
            c.second.stop(); c.first.stop()
            dir.deleteRecursively()
        } else if (mode == "interop") {
            val dir = File(args[4]).also { it.mkdirs() }
            helperFlow(args[1].toInt(), args[2], args[3], dir, null)
        }
        if (fail > 0) { println("ERGEBNIS: $fail Fehler"); exitProcess(1) }
        println("ERGEBNIS: alle Pruefungen bestanden")
        exitProcess(0)
    }
}
