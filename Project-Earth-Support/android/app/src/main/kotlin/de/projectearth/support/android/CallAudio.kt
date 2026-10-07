package de.projectearth.support.android

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import de.projectearth.support.core.PesProto
import de.projectearth.support.core.PesSession

/** Mikrofon (AudioRecord) und Wiedergabe (AudioTrack) fuer den Anruf: 16 kHz, mono, 16 Bit, 20-ms-Frames (wie in Project Earth LAN). */
class CallAudio(private val session: PesSession) {
    @Volatile private var running = false
    private var rec: AudioRecord? = null
    private var track: AudioTrack? = null
    private var recThread: Thread? = null
    private var playThread: Thread? = null
    private var aec: AcousticEchoCanceler? = null
    private var ns: NoiseSuppressor? = null
    private var am: AudioManager? = null
    private var prevMode = AudioManager.MODE_NORMAL

    val isRunning: Boolean get() = running

    /** Liefert null bei Erfolg, sonst eine Fehlermeldung. Benoetigt RECORD_AUDIO. */
    @SuppressLint("MissingPermission")
    fun start(ctx: Context, speaker: Boolean): String? {
        if (running) return null
        val rate = 16000
        val frameBytes = PesProto.FRAME * 2
        try {
            val a = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            am = a
            prevMode = a.mode
            a.mode = AudioManager.MODE_IN_COMMUNICATION
            setSpeaker(speaker)

            val minIn = AudioRecord.getMinBufferSize(rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
            if (minIn <= 0) { restoreMode(); return "Mikrofon wird von diesem Geraet nicht unterstuetzt." }
            val r = AudioRecord(MediaRecorder.AudioSource.VOICE_COMMUNICATION, rate, AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT, maxOf(minIn, frameBytes * 8))
            if (r.state != AudioRecord.STATE_INITIALIZED) { r.release(); restoreMode(); return "Mikrofon konnte nicht geoeffnet werden (Berechtigung?)." }
            rec = r
            try { if (AcousticEchoCanceler.isAvailable()) aec = AcousticEchoCanceler.create(r.audioSessionId)?.also { it.enabled = true } } catch (_: Exception) {}
            try { if (NoiseSuppressor.isAvailable()) ns = NoiseSuppressor.create(r.audioSessionId)?.also { it.enabled = true } } catch (_: Exception) {}

            val minOut = AudioTrack.getMinBufferSize(rate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
            val t = AudioTrack.Builder()
                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                .setAudioFormat(AudioFormat.Builder().setSampleRate(rate).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).setEncoding(AudioFormat.ENCODING_PCM_16BIT).build())
                .setBufferSizeInBytes(maxOf(minOut, frameBytes * 6))
                .setTransferMode(AudioTrack.MODE_STREAM)
                .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
                .build()
            track = t
            running = true
            r.startRecording()
            t.play()
            recThread = Thread({ recLoop(r) }, "pes-rec").also { it.priority = Thread.MAX_PRIORITY; it.isDaemon = true; it.start() }
            playThread = Thread({ playLoop(t) }, "pes-play").also { it.priority = Thread.MAX_PRIORITY; it.isDaemon = true; it.start() }
            return null
        } catch (e: Exception) {
            SupLog.e("Audio starten", e)
            stop()
            return "Audio konnte nicht gestartet werden: ${e.message}"
        }
    }

    private fun recLoop(r: AudioRecord) {
        val buf = ShortArray(PesProto.FRAME)
        while (running) {
            var got = 0
            while (got < buf.size && running) {
                val n = r.read(buf, got, buf.size - got, AudioRecord.READ_BLOCKING)
                if (n <= 0) { if (!running) return; Thread.sleep(5); continue }
                got += n
            }
            if (got == buf.size) try { session.sendAudio(buf) } catch (_: Exception) {}
        }
    }

    private fun playLoop(t: AudioTrack) {
        while (running) {
            val f = try { session.pullAudio() } catch (_: Exception) { ShortArray(PesProto.FRAME) }
            val n = t.write(f, 0, f.size, AudioTrack.WRITE_BLOCKING)
            if (n < 0) { if (!running) return; Thread.sleep(10) }
        }
    }

    fun setSpeaker(on: Boolean) {
        val a = am ?: return
        try {
            if (Build.VERSION.SDK_INT >= 31) {
                if (on) {
                    val d = a.availableCommunicationDevices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                    if (d != null) a.setCommunicationDevice(d)
                } else a.clearCommunicationDevice()
            } else {
                @Suppress("DEPRECATION")
                a.isSpeakerphoneOn = on
            }
        } catch (e: Exception) { SupLog.e("Lautsprecher umschalten", e) }
    }

    private fun restoreMode() {
        val a = am ?: return
        try {
            if (Build.VERSION.SDK_INT >= 31) a.clearCommunicationDevice()
            else @Suppress("DEPRECATION") { a.isSpeakerphoneOn = false }
            a.mode = prevMode
        } catch (_: Exception) {}
    }

    fun stop() {
        running = false
        try { recThread?.join(500) } catch (_: Exception) {}
        try { playThread?.join(500) } catch (_: Exception) {}
        recThread = null; playThread = null
        try { rec?.stop() } catch (_: Exception) {}
        try { rec?.release() } catch (_: Exception) {}
        try { track?.stop() } catch (_: Exception) {}
        try { track?.release() } catch (_: Exception) {}
        try { aec?.release() } catch (_: Exception) {}
        try { ns?.release() } catch (_: Exception) {}
        rec = null; track = null; aec = null; ns = null
        restoreMode()
    }
}
