package de.projectearth.support.android

import android.content.Context
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Handler
import android.os.Looper

/** Spielt den Standard-Klingelton des Geraets in Schleife, bis [stop] aufgerufen wird (folgt dem Klingelmodus: lautlos = still). */
object SupRinger {
    private val main = Handler(Looper.getMainLooper())
    private var ringtone: Ringtone? = null
    @Volatile var playing = false
        private set

    fun start(ctx: Context) {
        val app = ctx.applicationContext
        main.post {
            if (playing) return@post
            try {
                val r = RingtoneManager.getRingtone(app, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE))
                if (r != null) {
                    r.audioAttributes = AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
                    r.isLooping = true
                    r.play()
                }
                ringtone = r
                playing = r != null
            } catch (e: Exception) {
                SupLog.e("Klingelton", e)
                playing = false
            }
        }
    }

    fun stop() {
        if (!playing && ringtone == null) return
        main.post {
            try { ringtone?.stop() } catch (_: Exception) {}
            ringtone = null
            playing = false
        }
        playing = false
    }
}
