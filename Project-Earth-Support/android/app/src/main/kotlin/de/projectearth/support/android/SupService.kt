package de.projectearth.support.android

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import de.projectearth.support.core.PesProto

/** Haelt die Sitzung im Vordergrund am Leben (sichtbare Benachrichtigung mit "Trennen"). Waehrend eines Anrufs mit Mikrofon-Typ. */
class SupService : Service() {
    companion object {
        const val ACTION_START = "de.projectearth.support.android.START"
        const val ACTION_STOP = "de.projectearth.support.android.STOP"
        const val ACTION_SYNC = "de.projectearth.support.android.SYNC"
    }

    @Volatile private var worker: Thread? = null
    @Volatile private var alive = false
    @Volatile private var micType = false
    private var wake: PowerManager.WakeLock? = null
    private var wifi: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(text: String): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val stop = PendingIntent.getService(this, 1, Intent(this, SupService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        return NotificationCompat.Builder(this, SupRuntime.CH_STATUS)
            .setSmallIcon(R.drawable.ic_stat)
            .setContentTitle("Project Earth Support")
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(open)
            .addAction(0, Tr.t("Trennen"), stop)
            .build()
    }

    private fun goForeground(text: String, mic: Boolean) {
        val n = buildNotification(text)
        if (Build.VERSION.SDK_INT >= 30) {
            var type = if (Build.VERSION.SDK_INT >= 34) ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE else 0
            if (mic) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            if (type != 0) startForeground(SupRuntime.NOTIF_STATUS, n, type) else startForeground(SupRuntime.NOTIF_STATUS, n)
        } else startForeground(SupRuntime.NOTIF_STATUS, n)
        micType = mic
    }

    /** Ton: Dienst-Typ um "Mikrofon" erweitern (nur mit Berechtigung erlaubt), dann Aufnahme und Wiedergabe starten oder stoppen. */
    private fun audioSync() {
        try {
            val inCall = SupRuntime.currentSession()?.callState == PesProto.CALL_ACTIVE
            if (inCall && !micType && SupRuntime.hasMicPermission()) goForeground(SupRuntime.statusText(), true)
            SupRuntime.syncAudio()
            if (!inCall && micType) goForeground(SupRuntime.statusText(), false)
        } catch (e: Exception) {
            SupLog.e("Ton im Dienst", e)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                goForeground(Tr.t("Verbinde ..."), false)
                if (!alive) {
                    alive = true
                    worker = Thread({ run() }, "pes-service").also { it.isDaemon = true; it.start() }
                }
            }
            ACTION_SYNC -> if (alive) Thread({ audioSync() }, "pes-audio-sync").start()
            ACTION_STOP -> {
                alive = false
                Thread({
                    SupRuntime.stopSessionBlocking()
                    releaseLocks()
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                }, "pes-stop").start()
            }
            else -> {
                // Neustart durch das System ohne Sitzung: nichts zu tun
                if (!SupRuntime.isActive) stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    private fun run() {
        SupRuntime.startSessionBlocking()
        var last = ""
        while (alive) {
            try {
                if (!SupRuntime.isActive) break                      // Sitzung nicht zustande gekommen oder beendet
                acquireLocks()
                val t = SupRuntime.statusText()
                if (t != last) {
                    last = t
                    try { NotificationManagerCompat.from(this).notify(SupRuntime.NOTIF_STATUS, buildNotification(t)) } catch (_: SecurityException) {}
                }
            } catch (e: Exception) {
                SupLog.e("Dienstschleife", e)
            }
            Thread.sleep(1500)
        }
        if (alive) {
            // ohne ACTION_STOP beendet (Verbindungsfehler)
            alive = false
            releaseLocks()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    /** Waehrend einer Sitzung bleiben Prozessor und WLAN wach (Bild und Ton brauchen eine stabile Leitung). */
    private fun acquireLocks() {
        if (wake == null) {
            wake = (getSystemService(Context.POWER_SERVICE) as PowerManager).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ProjectEarthSupport:session").also { it.setReferenceCounted(false) }
        }
        if (wake?.isHeld == false) wake?.acquire(4 * 60 * 60 * 1000L)
        if (wifi == null) {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            wifi = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_LOW_LATENCY, "ProjectEarthSupport:wifi").also { it.setReferenceCounted(false) }
        }
        if (wifi?.isHeld == false) wifi?.acquire()
    }

    private fun releaseLocks() {
        try { if (wake?.isHeld == true) wake?.release() } catch (_: Exception) {}
        try { if (wifi?.isHeld == true) wifi?.release() } catch (_: Exception) {}
    }

    override fun onDestroy() {
        alive = false
        releaseLocks()
        super.onDestroy()
    }
}
