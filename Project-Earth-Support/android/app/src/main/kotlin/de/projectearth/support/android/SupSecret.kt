package de.projectearth.support.android

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Verschluesselt sensible Daten (Einladungscode mit Sitzungs-Passwort) mit einem Schluessel im Android Keystore
 * (AES-256-GCM, der Schluessel verlaesst das Geraet nicht). Gegenstueck zu DPAPI am PC.
 */
object SupSecret {
    private const val ALIAS = "pes_secret_v1"
    private const val PROVIDER = "AndroidKeyStore"

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance(PROVIDER).also { it.load(null) }
        (ks.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val kg = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, PROVIDER)
        kg.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return kg.generateKey()
    }

    fun encrypt(plain: String): String {
        if (plain.isEmpty()) return ""
        return try {
            val c = Cipher.getInstance("AES/GCM/NoPadding")
            c.init(Cipher.ENCRYPT_MODE, key())
            val ct = c.doFinal(plain.toByteArray(Charsets.UTF_8))
            "v1:" + Base64.encodeToString(c.iv, Base64.NO_WRAP) + ":" + Base64.encodeToString(ct, Base64.NO_WRAP)
        } catch (e: Exception) {
            SupLog.e("Verschluesselung fehlgeschlagen", e)
            ""
        }
    }

    /** Klartext oder null (leer, beschaedigt, Schluessel weg). */
    fun decrypt(s: String): String? {
        return try {
            if (!s.startsWith("v1:")) return null
            val p = s.split(':')
            if (p.size != 3) return null
            val c = Cipher.getInstance("AES/GCM/NoPadding")
            c.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, Base64.decode(p[1], Base64.NO_WRAP)))
            String(c.doFinal(Base64.decode(p[2], Base64.NO_WRAP)), Charsets.UTF_8)
        } catch (e: Exception) {
            SupLog.e("Entschluesselung fehlgeschlagen", e)
            null
        }
    }
}
