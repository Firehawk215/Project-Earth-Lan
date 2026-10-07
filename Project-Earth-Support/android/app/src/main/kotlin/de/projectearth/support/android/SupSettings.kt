package de.projectearth.support.android

import android.content.Context
import android.os.Build
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.SecureRandom

class SupSettings(
    val name: String,
    val inviteEnc: String,
    val remember: Boolean,
    val server: String,
    val machineKey: String,
    /** "" = Sprache des Geraets, sonst "de" oder "en" */
    val lang: String = "",
    val quality: Int = 2,
)

/** Einstellungen als JSON, atomar geschrieben (Temp-Datei -> Rename). Der Einladungscode liegt nur verschluesselt vor. */
object SupSettingsStore {
    private fun file(ctx: Context) = File(ctx.filesDir, "settings.json")

    private fun newMachineKey(): String {
        val b = ByteArray(16)
        SecureRandom().nextBytes(b)
        return b.joinToString("") { "%02x".format(it) }
    }

    @Synchronized
    fun load(ctx: Context): SupSettings {
        var name = Build.MODEL ?: "Android"
        var enc = ""
        var remember = true
        var server = ""
        var key = ""
        var lang = ""
        var quality = 2
        try {
            val f = file(ctx)
            if (f.exists()) {
                val j = JSONObject(f.readText(Charsets.UTF_8))
                name = j.optString("name", name)
                enc = j.optString("inviteEnc", "")
                remember = j.optBoolean("remember", true)
                server = j.optString("server", "")
                key = j.optString("machineKey", "")
                lang = j.optString("lang", "")
                quality = j.optInt("quality", 2)
            }
        } catch (e: Exception) {
            SupLog.e("Einstellungen konnten nicht gelesen werden", e)
        }
        if (lang != "de" && lang != "en") lang = ""
        if (quality < 1 || quality > 3) quality = 2
        if (key.length != 32) {
            // Geraeteschluessel: sorgt nur dafuer, dass dieses Geraet beim Vermittler immer dieselbe virtuelle Adresse bekommt
            key = newMachineKey()
            save(ctx, SupSettings(name, enc, remember, server, key, lang, quality))
        }
        return SupSettings(name, enc, remember, server, key, lang, quality)
    }

    @Synchronized
    fun save(ctx: Context, s: SupSettings) {
        try {
            val j = JSONObject()
            j.put("name", s.name)
            j.put("inviteEnc", s.inviteEnc)
            j.put("remember", s.remember)
            j.put("server", s.server)
            j.put("machineKey", s.machineKey)
            j.put("lang", s.lang)
            j.put("quality", s.quality)
            val f = file(ctx)
            val tmp = File(f.path + ".tmp")
            FileOutputStream(tmp).use { o ->
                o.write(j.toString(2).toByteArray(Charsets.UTF_8))
                o.flush()
                o.fd.sync()
            }
            Files.move(tmp.toPath(), f.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        } catch (e: Exception) {
            SupLog.e("Einstellungen konnten nicht gespeichert werden", e)
        }
    }
}
