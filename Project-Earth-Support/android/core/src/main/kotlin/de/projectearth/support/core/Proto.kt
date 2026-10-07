package de.projectearth.support.core

import java.nio.charset.StandardCharsets
import java.security.SecureRandom
import java.util.Base64

/** Zerlegter Einladungscode. */
class PesInvite(val server: String, val lobby: String, val password: String)

/**
 * Konstanten und Helfer des Dienstes "Support" (virtueller UDP-Port 9891, Magic-Byte 0xA8) -
 * 1:1 passend zu PesProto in Project-Earth-Support.ps1.
 * Alles laeuft als normale IPv4/UDP-Pakete durch die unveraenderte P2P-Engine (AES-256-CTR + HMAC-SHA256 je Paket).
 */
object PesProto {
    const val MAGIC = 0xA8
    const val PORT = 9891
    const val VERSION = 1
    const val MSS = 1100
    const val FRAME = 320
    const val DEFAULT_SERVER_PORT = 9890

    const val K_HELLO = 0x01
    const val K_REL = 0x02
    const val K_ACK = 0x03
    const val K_BYE = 0x04
    const val K_AUDIO = 0x10
    const val K_VIDEO = 0x11

    // Nachrichten auf Strom 0 (Steuerung)
    const val M_CHAT = 0x20
    const val M_CALL = 0x21
    const val M_MEDIA = 0x22
    const val M_SCRREQ = 0x30
    const val M_SCRSTAT = 0x31
    const val M_INPUT = 0x32
    const val M_SCROPT = 0x33
    const val M_FOFFER = 0x40
    const val M_FANSW = 0x41
    const val M_FCANCEL = 0x44
    const val M_FDONE = 0x45
    // Strom 1 (Dateidaten) und Strom 2 (Bildschirm)
    const val M_FDATA = 0x42
    const val M_FEND = 0x43
    const val M_RECT = 0x60

    const val ROLE_HELPER = 1
    const val ROLE_CUSTOMER = 2
    const val CALL_IDLE = 0
    const val CALL_OUT = 1
    const val CALL_IN = 2
    const val CALL_ACTIVE = 3

    const val VIDEO_CHUNK = 1100
    const val VIDEO_MAX_FRAME = VIDEO_CHUNK * 255
    const val SEP = '\u001f'

    fun muLawEncode(sample: Short): Byte {
        var s = sample.toInt()
        val sign = (s shr 8) and 0x80
        if (sign != 0) s = -s
        if (s > 32635) s = 32635
        s += 0x84
        var exponent = 7
        var mask = 0x4000
        while ((s and mask) == 0 && exponent > 0) { exponent--; mask = mask shr 1 }
        val mantissa = (s shr (exponent + 3)) and 0x0F
        return (sign or (exponent shl 4) or mantissa).inv().toByte()
    }

    fun muLawDecode(b: Byte): Short {
        val u = b.toInt().inv() and 0xFF
        val sign = u and 0x80
        val exponent = (u shr 4) and 0x07
        val mantissa = u and 0x0F
        var s = ((mantissa shl 3) + 0x84) shl exponent
        s -= 0x84
        return (if (sign != 0) -s else s).toShort()
    }

    // ---- Einladungscode "PES1:" + Base64url(Server \n Lobby \n Passwort) ----
    fun inviteCreate(server: String, lobby: String, password: String): String {
        val raw = "$server\n$lobby\n$password".toByteArray(StandardCharsets.UTF_8)
        return "PES1:" + Base64.getUrlEncoder().withoutPadding().encodeToString(raw)
    }

    fun inviteParse(text: String?): PesInvite? {
        if (text.isNullOrEmpty()) return null
        val i = text.indexOf("PES1:")
        if (i < 0) return null
        val sb = StringBuilder()
        var k = i + 5
        while (k < text.length && sb.length < 600) {
            val c = text[k]
            val ok = c in 'A'..'Z' || c in 'a'..'z' || c in '0'..'9' || c == '-' || c == '_'
            if (!ok) break
            sb.append(c)
            k++
        }
        if (sb.isEmpty()) return null
        return try {
            var b = sb.toString().replace('-', '+').replace('_', '/')
            while (b.length % 4 != 0) b += "="
            val parts = String(Base64.getDecoder().decode(b), StandardCharsets.UTF_8).split("\n")
            if (parts.size < 3 || parts[0].isEmpty() || parts[1].isEmpty()) null
            else PesInvite(parts[0], parts[1], parts.subList(2, parts.size).joinToString("\n"))
        } catch (e: Exception) {
            null
        }
    }

    /** Zerlegt "host" oder "host:port"; null bei ungueltiger Eingabe. */
    fun parseServer(text: String?, defaultPort: Int = DEFAULT_SERVER_PORT): Pair<String, Int>? {
        val t = text?.trim() ?: return null
        if (t.isEmpty() || t.length > 255) return null
        val c = t.lastIndexOf(':')
        var h = t
        var port = defaultPort
        if (c >= 0) {
            h = t.substring(0, c)
            val ps = t.substring(c + 1)
            if (ps.isEmpty() || ps.length > 5 || !ps.all { it in '0'..'9' }) return null
            port = ps.toInt()
            if (port < 1 || port > 65535) return null
        }
        if (h.isEmpty()) return null
        if (!h.all { it in 'A'..'Z' || it in 'a'..'z' || it in '0'..'9' || it == '.' || it == '-' }) return null
        return Pair(h, port)
    }

    private const val ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789"

    fun randomText(length: Int): String {
        val r = ByteArray(length * 2)
        SecureRandom().nextBytes(r)
        val sb = StringBuilder(length)
        for (i in 0 until length) sb.append(ALPHABET[(((r[i * 2].toInt() and 0xFF) shl 8) or (r[i * 2 + 1].toInt() and 0xFF)) % ALPHABET.length])
        return sb.toString()
    }

    fun newLobby(): String = "pes-" + randomText(12).lowercase()
    fun newPassword(): String = randomText(24)

    // ---- IPv4/UDP-Huelle (die Engine transportiert IPv4-Pakete) ----
    fun wrap(src: Int, dst: Int, ipId: Int, payload: ByteArray, len: Int = payload.size): ByteArray {
        val p = ByteArray(28 + len)
        p[0] = 0x45
        PesBytes.writeU16(p, 2, 28 + len)
        PesBytes.writeU16(p, 4, ipId and 0xFFFF)
        p[6] = 0x40
        p[8] = 64
        p[9] = 17
        PesBytes.writeI32(p, 12, src)
        PesBytes.writeI32(p, 16, dst)
        var sum = 0
        var i = 0
        while (i < 20) { sum += (PesBytes.u8(p, i) shl 8) or PesBytes.u8(p, i + 1); i += 2 }
        while ((sum shr 16) != 0) sum = (sum and 0xFFFF) + (sum shr 16)
        PesBytes.writeU16(p, 10, sum.inv() and 0xFFFF)
        PesBytes.writeU16(p, 20, PORT)
        PesBytes.writeU16(p, 22, PORT)
        PesBytes.writeU16(p, 24, 8 + len)
        System.arraycopy(payload, 0, p, 28, len)
        return p
    }

    /** Liefert (Offset der Nutzdaten, Laenge, virtuelle IP des Absenders) oder null. */
    fun unwrap(ip: ByteArray?): Triple<Int, Int, Int>? {
        if (ip == null || ip.size < 30) return null
        if ((PesBytes.u8(ip, 0) shr 4) != 4) return null
        val ihl = (PesBytes.u8(ip, 0) and 15) * 4
        if (ihl < 20 || ip.size < ihl + 10) return null
        if (PesBytes.u8(ip, 9) != 17) return null
        if ((PesBytes.readU16(ip, 6) and 0x3FFF) != 0) return null
        val total = PesBytes.readU16(ip, 2)
        if (total > ip.size || total < ihl + 10) return null
        if (PesBytes.readU16(ip, ihl + 2) != PORT) return null
        val ulen = PesBytes.readU16(ip, ihl + 4)
        if (ulen < 10 || ihl + ulen > total) return null
        if (PesBytes.u8(ip, ihl + 8) != MAGIC) return null
        return Triple(ihl + 8, ulen - 8, PesBytes.readI32(ip, 12))
    }

    fun cleanName(s: String?, max: Int): String {
        if (s == null) return ""
        val sb = StringBuilder()
        for (c in s) {
            if (c.code < 32 || c.code == 127) continue
            sb.append(c)
            if (sb.length >= max) break
        }
        return sb.toString().trim()
    }

    /** Dateiname aus dem Netz: nie Pfade, keine reservierten Zeichen, begrenzte Laenge. */
    fun cleanFileName(s0: String?): String {
        var s = s0 ?: ""
        val cut = maxOf(s.lastIndexOf('/'), s.lastIndexOf('\\'))
        if (cut >= 0) s = s.substring(cut + 1)
        val sb = StringBuilder()
        for (c in s) {
            if (c.code < 32 || c.code == 127 || c == '<' || c == '>' || c == ':' || c == '"' || c == '/' || c == '\\' || c == '|' || c == '?' || c == '*') { sb.append('_'); continue }
            sb.append(c)
            if (sb.length >= 120) break
        }
        var r = sb.toString().trim().trimEnd('.', ' ')
        while (r.startsWith(".")) r = r.substring(1)
        if (r.isEmpty()) r = "datei"
        val up = r.uppercase()
        val dot = up.indexOf('.')
        val stem = if (dot < 0) up else up.substring(0, dot)
        val reserved = setOf("CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
            "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9")
        if (stem in reserved) r = "_$r"
        return r
    }
}
