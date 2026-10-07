package de.projectearth.support.core

import java.io.ByteArrayOutputStream

/**
 * Zuverlaessiger, geordneter Nachrichtenstrom ueber UDP - 1:1 passend zu PesRel in Project-Earth-Support.ps1.
 * Paket (nach Magic/Art/Epoche/Strom):
 *   REL: seq(4) | fl(1) | Daten      fl Bit0 = Nachrichtenanfang, Bit1 = Nachrichtenende
 *   ACK: cum(4) | sack(8)            cum = naechste erwartete Nummer, sack = Bits fuer cum+1 .. cum+64
 * Nicht threadsicher - die Sitzung sperrt.
 */
class PesRel(val id: Int) {
    private class Seg(val data: ByteArray, val fl: Int) {
        var lastTx = 0L
        var txCount = 0
        var sacked = false
    }

    companion object {
        const val MAX_MESSAGE = 8 * 1024 * 1024
        private const val RX_WINDOW = 1024
        private const val MIN_WINDOW = 12.0
    }

    // Senden
    private val txMsgs = java.util.ArrayDeque<ByteArray>()
    private var txOff = 0
    private var queuedBytes = 0L
    private var flightBytes = 0L
    private var sndUna = 0
    private var sndNxt = 0
    private val flight = HashMap<Int, Seg>()
    private var cwnd = 16.0
    private var ssthresh = 96.0
    private var srtt = -1
    private var rttvar = 0
    private var lastCutMs = -100000L
    private var recoverSeq = 0
    private var hasSack = false
    private var highSack = 0

    // Empfangen
    private var rcvNxt = 0
    private val ooo = HashMap<Int, Seg>()
    private var asm: ByteArrayOutputStream? = null
    var ackDue = false

    var retransmits = 0L
        private set

    val backlog: Long get() = queuedBytes + flightBytes
    val rtt: Int get() = srtt
    val idle: Boolean get() = txMsgs.isEmpty() && flight.isEmpty()

    fun reset() {
        txMsgs.clear(); txOff = 0; queuedBytes = 0; flightBytes = 0
        sndUna = 0; sndNxt = 0; flight.clear()
        cwnd = 16.0; ssthresh = 96.0; srtt = -1; rttvar = 0; lastCutMs = -100000; recoverSeq = 0
        hasSack = false; highSack = 0
        rcvNxt = 0; ooo.clear(); asm = null; ackDue = false
    }

    fun enqueue(msg: ByteArray?) {
        if (msg == null || msg.isEmpty() || msg.size > MAX_MESSAGE) return
        txMsgs.addLast(msg)
        queuedBytes += msg.size
    }

    private fun rto(): Int {
        if (srtt < 0) return 400
        var r = srtt + 4 * rttvar + 20
        if (r < 120) r = 120
        if (r > 1500) r = 1500
        return r
    }

    private fun build(seq: Int, s: Seg): ByteArray {
        val p = ByteArray(5 + s.data.size)
        PesBytes.writeI32(p, 0, seq)
        p[4] = s.fl.toByte()
        System.arraycopy(s.data, 0, p, 5, s.data.size)
        return p
    }

    /** Faellige Wiederholungen und neue Pakete erzeugen (hoechstens budget Stueck). */
    fun pump(now: Long, budget0: Int, out: MutableList<ByteArray>) {
        var budget = budget0
        if (flight.isNotEmpty()) {
            val rto = rto()
            // Liegt ein Paket nachweislich hinter einer Luecke (die Gegenseite hat schon spaetere), reicht eine kurze Wartezeit
            val holeGate = if (srtt < 0) 60 else maxOf(40, srtt * 3 / 2)
            var s = sndUna
            var scanned = 0
            while (s != sndNxt && budget > 0 && scanned < 2048) {
                val g = flight[s]
                if (g != null && !g.sacked) {
                    val hole = hasSack && (highSack - s) >= 2
                    var back = g.txCount - 3
                    if (back < 0) back = 0
                    if (back > 2) back = 2
                    val wait = if (hole) holeGate.toLong() else (rto.toLong() shl back)
                    if (now - g.lastTx > wait) {
                        g.lastTx = now; g.txCount++; retransmits++
                        out.add(build(s, g)); budget--
                        if (now - lastCutMs > maxOf(rto, 200) && (s - recoverSeq) >= 0) {
                            lastCutMs = now
                            ssthresh = maxOf(MIN_WINDOW, cwnd * 0.7)
                            cwnd = maxOf(MIN_WINDOW, cwnd * 0.7)
                            recoverSeq = sndNxt
                        }
                    }
                }
                s++; scanned++
            }
        }
        while (budget > 0 && txMsgs.isNotEmpty() && (sndNxt - sndUna) < cwnd.toInt() && (sndNxt - sndUna) < RX_WINDOW - 8) {
            val m = txMsgs.peekFirst()
            val n = minOf(PesProto.MSS, m.size - txOff)
            val fl = (if (txOff == 0) 1 else 0) or (if (txOff + n >= m.size) 2 else 0)
            val g = Seg(m.copyOfRange(txOff, txOff + n), fl)
            g.lastTx = now; g.txCount = 1
            txOff += n
            queuedBytes -= n; flightBytes += n
            if (txOff >= m.size) { txMsgs.removeFirst(); txOff = 0 }
            flight[sndNxt] = g
            out.add(build(sndNxt, g))
            sndNxt++; budget--
        }
    }

    fun onAck(cum: Int, sack: Long, now: Long, out: MutableList<ByteArray>) {
        if ((cum - sndUna) < 0 || (sndNxt - cum) < 0) return      // veraltet oder unplausibel
        while (sndUna != cum) {
            val g = flight.remove(sndUna)
            if (g != null) {
                flightBytes -= g.data.size
                // Laufzeit nur von Paketen messen, die nie wiederholt wurden und nicht hinter einer Luecke warteten
                if (g.txCount == 1 && !g.sacked) sample((now - g.lastTx).toInt())
                if (cwnd < ssthresh) cwnd += 1.0 else cwnd += 1.0 / cwnd
                if (cwnd > 256) cwnd = 256.0
            }
            sndUna++
        }
        if (hasSack && (highSack - sndUna) < 0) hasSack = false
        if (sack == 0L) return
        for (i in 0 until 64) {
            if ((sack and (1L shl i)) == 0L) continue
            val q = cum + 1 + i
            val g = flight[q] ?: continue
            if (!g.sacked) { g.sacked = true; if (g.txCount == 1) sample((now - g.lastTx).toInt()) }
            if (!hasSack || (q - highSack) > 0) { hasSack = true; highSack = q }
        }
        // Luecken sofort schliessen (pump prueft die kurze Wartezeit je Paket)
        pump(now, 8, out)
    }

    private fun sample(rtt0: Int) {
        var rtt = rtt0
        if (rtt < 0) return
        if (rtt > 5000) rtt = 5000
        if (srtt < 0) { srtt = rtt; rttvar = rtt / 2 }
        else {
            val d = Math.abs(srtt - rtt)
            rttvar = (3 * rttvar + d) / 4
            srtt = (7 * srtt + rtt) / 8
        }
    }

    /** Ein eingehendes Datenpaket; vollstaendige Nachrichten landen in deliver. */
    fun onData(buf: ByteArray, off: Int, len: Int, deliver: MutableList<ByteArray>) {
        if (len < 6) return
        val seq = PesBytes.readI32(buf, off)
        val fl = PesBytes.u8(buf, off + 4)
        val n = len - 5
        if (n > PesProto.MSS + 64) return
        ackDue = true
        val d = seq - rcvNxt
        if (d < 0 || d >= RX_WINDOW) return                             // doppelt oder zu weit voraus
        if (d > 0) {
            if (!ooo.containsKey(seq)) ooo[seq] = Seg(buf.copyOfRange(off + 5, off + 5 + n), fl)
            return
        }
        accept(fl, buf, off + 5, n, deliver)
        rcvNxt++
        while (true) {
            val nx = ooo.remove(rcvNxt) ?: break
            accept(nx.fl, nx.data, 0, nx.data.size, deliver)
            rcvNxt++
        }
    }

    private fun accept(fl: Int, b: ByteArray, off: Int, n: Int, deliver: MutableList<ByteArray>) {
        if ((fl and 1) != 0) asm = ByteArrayOutputStream()
        val a = asm ?: return                                           // Mitte ohne Anfang: verwerfen
        if (a.size() + n > MAX_MESSAGE) { asm = null; return }
        a.write(b, off, n)
        if ((fl and 2) != 0) { deliver.add(a.toByteArray()); asm = null }
    }

    fun buildAck(): ByteArray {
        ackDue = false
        val p = ByteArray(12)
        PesBytes.writeI32(p, 0, rcvNxt)
        var sack = 0L
        if (ooo.isNotEmpty()) {
            for (i in 0 until 64) if (ooo.containsKey(rcvNxt + 1 + i)) sack = sack or (1L shl i)
        }
        PesBytes.writeI64(p, 4, sack)
        return p
    }
}
