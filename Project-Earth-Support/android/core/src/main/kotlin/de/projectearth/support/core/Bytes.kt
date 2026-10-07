package de.projectearth.support.core

import java.net.InetAddress
import java.nio.charset.StandardCharsets

/**
 * Big-Endian-Helfer, 1:1 passend zu PesBytes im PC-Manager.
 * IPv4-Adressen werden als Int (Bitmuster, vorzeichenlos zu lesen) gefuehrt,
 * NodeIds als Long (u64-Bitmuster).
 */
object PesBytes {
    fun u8(b: ByteArray, o: Int): Int = b[o].toInt() and 0xFF

    fun readU16(b: ByteArray, o: Int): Int = (u8(b, o) shl 8) or u8(b, o + 1)

    fun writeU16(b: ByteArray, o: Int, v: Int) {
        b[o] = (v shr 8).toByte()
        b[o + 1] = v.toByte()
    }

    fun readI32(b: ByteArray, o: Int): Int =
        (u8(b, o) shl 24) or (u8(b, o + 1) shl 16) or (u8(b, o + 2) shl 8) or u8(b, o + 3)

    fun writeI32(b: ByteArray, o: Int, v: Int) {
        b[o] = (v ushr 24).toByte()
        b[o + 1] = (v ushr 16).toByte()
        b[o + 2] = (v ushr 8).toByte()
        b[o + 3] = v.toByte()
    }

    fun readI64(b: ByteArray, o: Int): Long =
        (readI32(b, o).toLong() shl 32) or (readI32(b, o + 4).toLong() and 0xFFFFFFFFL)

    fun writeI64(b: ByteArray, o: Int, v: Long) {
        writeI32(b, o, (v ushr 32).toInt())
        writeI32(b, o + 4, v.toInt())
    }

    fun ipToString(ip: Int): String =
        "${(ip ushr 24) and 255}.${(ip ushr 16) and 255}.${(ip ushr 8) and 255}.${ip and 255}"

    /** Strenge Punkt-Notation a.b.c.d, sonst null. */
    fun parseIp(s: String?): Int? {
        if (s == null) return null
        val parts = s.trim().split('.')
        if (parts.size != 4) return null
        var v = 0
        for (p in parts) {
            if (p.isEmpty() || p.length > 3 || !p.all { it in '0'..'9' }) return null
            val n = p.toInt()
            if (n > 255) return null
            v = (v shl 8) or n
        }
        return v
    }

    fun inetToInt(a: InetAddress): Int {
        val b = a.address
        return if (b.size == 4) readI32(b, 0) else 0
    }

    fun intToInet(v: Int): InetAddress {
        val b = ByteArray(4)
        writeI32(b, 0, v)
        return InetAddress.getByAddress(b)
    }

    fun isPrivate(a: InetAddress): Boolean {
        val b = a.address
        if (b.size != 4) return false
        val b0 = u8(b, 0)
        val b1 = u8(b, 1)
        return b0 == 10 || (b0 == 172 && b1 in 16..31) || (b0 == 192 && b1 == 168) || (b0 == 100 && b1 in 64..127)
    }

    /** UTF-8 hoechstens maxBytes lang, ohne ein Zeichen zu zerschneiden. */
    fun utf8Limit(s: String?, maxBytes: Int): ByteArray {
        var t = s ?: ""
        while (t.isNotEmpty() && t.toByteArray(StandardCharsets.UTF_8).size > maxBytes) {
            val cut = if (t.length >= 2 && Character.isLowSurrogate(t[t.length - 1]) && Character.isHighSurrogate(t[t.length - 2])) 2 else 1
            t = t.substring(0, t.length - cut)
        }
        return t.toByteArray(StandardCharsets.UTF_8)
    }

    fun hex(b: ByteArray, off: Int = 0, len: Int = b.size - off): String {
        val sb = StringBuilder(len * 2)
        for (i in 0 until len) {
            val v = b[off + i].toInt() and 0xFF
            sb.append("0123456789abcdef"[v ushr 4]).append("0123456789abcdef"[v and 15])
        }
        return sb.toString()
    }

    fun fromHex(s: String): ByteArray? {
        if (s.length % 2 != 0) return null
        val out = ByteArray(s.length / 2)
        for (i in out.indices) {
            val hi = Character.digit(s[i * 2], 16)
            val lo = Character.digit(s[i * 2 + 1], 16)
            if (hi < 0 || lo < 0) return null
            out[i] = ((hi shl 4) or lo).toByte()
        }
        return out
    }
}
