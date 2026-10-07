package de.projectearth.support.android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** "Ablehnen" in der Anruf-Benachrichtigung (ohne die App zu oeffnen). */
class SupCallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try { SupRuntime.answerCall(false) } catch (e: Exception) { SupLog.e("Anruf ablehnen", e) }
    }
}
