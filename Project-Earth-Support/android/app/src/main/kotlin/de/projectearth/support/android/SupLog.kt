package de.projectearth.support.android

import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Fehlerprotokoll (Datei in der App, wird bei ca. 512 KB rotiert). Enthaelt nie Passwoerter oder Einladungscodes. */
object SupLog {
    private var file: File? = null
    private val fmt = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
    private const val MAX = 512 * 1024

    fun init(ctx: Context) {
        val dir = File(ctx.filesDir, "logs")
        dir.mkdirs()
        file = File(dir, "support.log")
    }

    @Synchronized
    fun w(msg: String) {
        val f = file ?: return
        try {
            if (f.length() > MAX) {
                val old = File(f.path + ".1")
                if (old.exists()) old.delete()
                f.renameTo(old)
            }
            f.appendText(fmt.format(Date()) + "  " + msg.replace("\r", " ").replace("\n", " | ") + "\n", Charsets.UTF_8)
        } catch (_: Exception) {
        }
    }

    fun e(msg: String, t: Throwable?) {
        w("FEHLER: $msg" + if (t != null) " (${t.javaClass.simpleName}: ${t.message})" else "")
    }

    /** Letzte Zeilen (hoechstens ca. 32 KB) fuer die Anzeige. */
    @Synchronized
    fun tail(): String {
        val f = file ?: return ""
        return try {
            if (!f.exists()) return ""
            val len = f.length()
            val max = 32 * 1024L
            java.io.RandomAccessFile(f, "r").use { r ->
                val start = if (len > max) len - max else 0L
                r.seek(start)
                val b = ByteArray((len - start).toInt())
                r.readFully(b)
                var s = String(b, Charsets.UTF_8)
                if (start > 0) s = s.substringAfter('\n', s)
                s
            }
        } catch (_: Exception) {
            ""
        }
    }
}
