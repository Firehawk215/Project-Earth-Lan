package de.projectearth.support.core

import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.Locale
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/** Ergebnis von [PesP2pCrypto.open]. */
class PesOpened(val type: Int, val node: Long, val seq: Int, val body: ByteArray)

/**
 * Paketformat Peer <-> Peer (wie PesP2pCrypto im PC-Manager):
 *   [0..1] Magic 'P''E'  [2] Typ  [3..10] Absender-NodeId  [11..14] Seq
 *   [15..] AES-256-CTR(Nutzdaten)  [letzte 16] HMAC-SHA256(Header+Chiffrat), auf 16 Byte gekuerzt
 * CTR-Zaehlerblock = NodeId(8) | Seq(4) | Blocknummer(4).
 * Threadsicher (synchronisiert); je Einsatzzweck eine eigene Instanz verwenden.
 */
class PesP2pCrypto(encKey: ByteArray, macKey: ByteArray) {
    companion object {
        const val HDR = 15
        const val TAG = 16
    }

    private val ecb: Cipher = Cipher.getInstance("AES/ECB/NoPadding").also {
        it.init(Cipher.ENCRYPT_MODE, SecretKeySpec(encKey, "AES"))
    }
    private val mac: Mac = Mac.getInstance("HmacSHA256").also { it.init(SecretKeySpec(macKey, "HmacSHA256")) }

    private fun ctr(node: Long, seq: Int, src: ByteArray, srcOff: Int, dst: ByteArray, dstOff: Int, len: Int) {
        if (len <= 0) return
        val blocks = (len + 15) / 16
        val ctr = ByteArray(blocks * 16)
        for (b in 0 until blocks) {
            val o = b * 16
            PesBytes.writeI64(ctr, o, node)
            PesBytes.writeI32(ctr, o + 8, seq)
            PesBytes.writeI32(ctr, o + 12, b)
        }
        val ks = ecb.doFinal(ctr)
        for (i in 0 until len) dst[dstOff + i] = (src[srcOff + i].toInt() xor ks[i].toInt()).toByte()
    }

    @Synchronized
    fun seal(type: Int, node: Long, seq: Int, body: ByteArray, off: Int, len: Int): ByteArray {
        val p = ByteArray(HDR + len + TAG)
        p[0] = 0x50
        p[1] = 0x45
        p[2] = type.toByte()
        PesBytes.writeI64(p, 3, node)
        PesBytes.writeI32(p, 11, seq)
        ctr(node, seq, body, off, p, HDR, len)
        mac.update(p, 0, HDR + len)
        val h = mac.doFinal()
        System.arraycopy(h, 0, p, HDR + len, TAG)
        return p
    }

    /** Entschluesselte Nutzdaten oder null (falscher Schluessel / manipuliert). */
    @Synchronized
    fun open(buf: ByteArray, off: Int, len: Int): PesOpened? {
        if (len < HDR + TAG || buf[off].toInt() != 0x50 || buf[off + 1].toInt() != 0x45) return null
        val bodyLen = len - HDR - TAG
        mac.update(buf, off, HDR + bodyLen)
        val h = mac.doFinal()
        var diff = 0
        for (i in 0 until TAG) diff = diff or (h[i].toInt() xor buf[off + HDR + bodyLen + i].toInt())
        if (diff != 0) return null
        val type = buf[off + 2].toInt() and 0xFF
        val node = PesBytes.readI64(buf, off + 3)
        val seq = PesBytes.readI32(buf, off + 11)
        val body = ByteArray(bodyLen)
        ctr(node, seq, buf, off + HDR, body, 0, bodyLen)
        return PesOpened(type, node, seq, body)
    }
}

/** Schluesselableitung exakt wie im PC-Manager (PBKDF2-HMAC-SHA1, 100.000 Runden, 64 Byte). */
object PesKeys {
    const val PBKDF2_ROUNDS = 100000

    /** Lobby-ID: SHA-256("PEL-LOBBY-V1|" + lobby.trim().lower), erste 16 Byte. */
    fun deriveLobbyId(lobbyName: String): ByteArray {
        val h = MessageDigest.getInstance("SHA-256")
            .digest(("PEL-LOBBY-V1|" + normalizeLobby(lobbyName)).toByteArray(StandardCharsets.UTF_8))
        return h.copyOfRange(0, 16)
    }

    fun normalizeLobby(name: String): String = name.trim().lowercase(Locale.ROOT)

    /** Liefert 64 Byte: [0..31] AES-Schluessel, [32..63] HMAC-Schluessel. */
    fun deriveKeyMaterial(lobbyName: String, password: String, rounds: Int = PBKDF2_ROUNDS): ByteArray {
        val salt = ("PEL-P2P-V1|" + normalizeLobby(lobbyName)).toByteArray(StandardCharsets.UTF_8)
        return pbkdf2HmacSha1(password.toByteArray(StandardCharsets.UTF_8), salt, rounds, 64)
    }

    fun pbkdf2HmacSha1(password: ByteArray, salt: ByteArray, iterations: Int, dkLen: Int): ByteArray {
        require(password.isNotEmpty()) { "Passwort leer" }
        val mac = Mac.getInstance("HmacSHA1")
        mac.init(SecretKeySpec(password, "HmacSHA1"))
        val hLen = mac.macLength
        val blocks = (dkLen + hLen - 1) / hLen
        val out = ByteArray(dkLen)
        val ib = ByteArray(4)
        for (block in 1..blocks) {
            PesBytes.writeI32(ib, 0, block)
            mac.update(salt)
            mac.update(ib)
            var u = mac.doFinal()
            val t = u.copyOf()
            for (i in 1 until iterations) {
                u = mac.doFinal(u)
                for (k in t.indices) t[k] = (t[k].toInt() xor u[k].toInt()).toByte()
            }
            val off = (block - 1) * hLen
            System.arraycopy(t, 0, out, off, minOf(hLen, dkLen - off))
        }
        return out
    }
}
