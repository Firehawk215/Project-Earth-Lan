package de.projectearth.support.android

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.Image
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.util.Range
import android.util.Size
import java.io.ByteArrayOutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Kamera fuer den Video-Chat: Camera2 liefert YUV-Bilder, jedes wird auf halbe Groesse verkleinert und als JPEG
 * weitergegeben (ca. 12 Bilder/s, 320x240). JPEG statt H.264, weil die Windows-Seite es ohne Zusatzsoftware
 * anzeigen und selbst erzeugen kann. Laeuft nur, solange die App sichtbar ist (kein Kamera-Hintergrunddienst).
 */
class CamCapture(private val onJpeg: (ByteArray, Int) -> Unit) {
    companion object {
        const val FPS = 12
        const val QUALITY = 55
    }

    @Volatile private var running = false
    private var thread: HandlerThread? = null
    private var camera: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var reader: ImageReader? = null
    @Volatile private var rotQuarter = 0
    private var lastSent = 0L
    private var nv21 = ByteArray(0)
    private val jpeg = ByteArrayOutputStream(32 * 1024)

    val isRunning: Boolean get() = running

    /** Liefert null bei Erfolg, sonst eine Fehlermeldung. Benoetigt CAMERA. displayDeg = aktuelle Bildschirmdrehung (0/90/180/270). */
    @SuppressLint("MissingPermission")
    fun start(ctx: Context, front: Boolean, displayDeg: Int): String? {
        if (running) return null
        try {
            val cm = ctx.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val want = if (front) CameraCharacteristics.LENS_FACING_FRONT else CameraCharacteristics.LENS_FACING_BACK
            val id = cm.cameraIdList.firstOrNull { cm.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) == want }
                ?: cm.cameraIdList.firstOrNull()
                ?: return "Keine Kamera gefunden."
            val ch = cm.getCameraCharacteristics(id)
            val isFront = ch.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_FRONT
            val sensor = ch.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90
            val need = if (isFront) (sensor + displayDeg) % 360 else (sensor - displayDeg + 360) % 360
            rotQuarter = need / 90

            val size = pickSize(ch)
            val t = HandlerThread("pes-cam").also { it.start() }
            thread = t
            val h = Handler(t.looper)
            val rd = ImageReader.newInstance(size.width, size.height, ImageFormat.YUV_420_888, 2)
            reader = rd
            running = true
            rd.setOnImageAvailableListener({ r ->
                val img = try { r.acquireLatestImage() } catch (_: Exception) { null } ?: return@setOnImageAvailableListener
                try { if (running) handle(img) } catch (e: Exception) { SupLog.w("Kamerabild: " + e.message) } finally { try { img.close() } catch (_: Exception) {} }
            }, h)

            val opened = CountDownLatch(1)
            var openErr: String? = null
            cm.openCamera(id, object : CameraDevice.StateCallback() {
                override fun onOpened(c: CameraDevice) { camera = c; opened.countDown() }
                override fun onDisconnected(c: CameraDevice) { try { c.close() } catch (_: Exception) {}; openErr = "Kamera getrennt."; opened.countDown() }
                override fun onError(c: CameraDevice, error: Int) { try { c.close() } catch (_: Exception) {}; openErr = "Kamera-Fehler $error."; opened.countDown() }
            }, h)
            if (!opened.await(5, TimeUnit.SECONDS)) { stop(); return "Kamera hat nicht geantwortet." }
            if (openErr != null || camera == null) { val e = openErr ?: "Kamera konnte nicht geoeffnet werden."; stop(); return e }

            val ready = CountDownLatch(1)
            var sessErr: String? = null
            @Suppress("DEPRECATION")
            camera!!.createCaptureSession(listOf(rd.surface), object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(s: CameraCaptureSession) {
                    session = s
                    try {
                        val rb = camera!!.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
                        rb.addTarget(rd.surface)
                        pickFps(ch)?.let { rb.set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, it) }
                        s.setRepeatingRequest(rb.build(), null, h)
                    } catch (e: Exception) { sessErr = "Kamera-Anfrage fehlgeschlagen: " + e.message }
                    ready.countDown()
                }
                override fun onConfigureFailed(s: CameraCaptureSession) { sessErr = "Kamera-Sitzung konnte nicht erstellt werden."; ready.countDown() }
            }, h)
            if (!ready.await(5, TimeUnit.SECONDS)) { stop(); return "Kamera-Sitzung: Zeitueberschreitung." }
            if (sessErr != null) { val e = sessErr; stop(); return e }
            return null
        } catch (e: CameraAccessException) {
            SupLog.e("Kamera starten", e); stop(); return "Kamerazugriff nicht moeglich: ${e.message}"
        } catch (e: Exception) {
            SupLog.e("Kamera starten", e); stop(); return "Kamera konnte nicht gestartet werden: ${e.message}"
        }
    }

    /** Bevorzugt 640x480 (4:3); daraus wird 320x240. */
    private fun pickSize(ch: CameraCharacteristics): Size {
        val map = ch.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
        val sizes = map?.getOutputSizes(ImageFormat.YUV_420_888) ?: return Size(640, 480)
        sizes.firstOrNull { it.width == 640 && it.height == 480 }?.let { return it }
        val ok = sizes.filter { it.width * 3 == it.height * 4 && it.width in 480..960 }
        if (ok.isNotEmpty()) return ok.minByOrNull { Math.abs(it.width - 640) }!!
        return sizes.filter { it.width in 480..1280 }.minByOrNull { it.width * it.height } ?: sizes.minByOrNull { it.width * it.height }!!
    }

    private fun pickFps(ch: CameraCharacteristics): Range<Int>? {
        val r = ch.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES) ?: return null
        return r.filter { it.upper in 15..30 }.minByOrNull { it.upper * 100 - it.lower }
    }

    /** YUV_420_888 -> NV21 in halber Groesse (jeder zweite Bildpunkt), dann JPEG. Laeuft im Kamera-Thread. */
    private fun handle(img: Image) {
        val now = System.nanoTime() / 1_000_000
        if (now - lastSent < 1000 / FPS) return
        lastSent = now
        val w = img.width
        val h = img.height
        val ow = (w / 2) and 1.inv()
        val oh = (h / 2) and 1.inv()
        if (ow < 16 || oh < 16) return
        val need = ow * oh * 3 / 2
        if (nv21.size != need) nv21 = ByteArray(need)
        val out = nv21
        val yp = img.planes[0]
        val up = img.planes[1]
        val vp = img.planes[2]
        val yb = yp.buffer
        val yRow = yp.rowStride
        val yPix = yp.pixelStride
        val rowBuf = ByteArray(yRow)
        var o = 0
        for (y in 0 until oh) {
            val pos = (y * 2) * yRow
            yb.position(pos)
            val n = minOf(yRow, yb.remaining())
            yb.get(rowBuf, 0, n)
            var x = 0
            val step = 2 * yPix
            var src = 0
            while (x < ow) { out[o++] = if (src < n) rowBuf[src] else 0; src += step; x++ }
        }
        // Farbe: die Ebenen haben die halbe Aufloesung; fuer das halbe Bild wird wieder jeder zweite Wert genommen
        val ub = up.buffer
        val vb = vp.buffer
        val cRow = up.rowStride
        val cPix = up.pixelStride
        val uRowBuf = ByteArray(cRow)
        val vRowBuf = ByteArray(cRow)
        val cw = ow / 2
        val chh = oh / 2
        for (y in 0 until chh) {
            val pos = (y * 2) * cRow
            if (pos >= ub.limit() || pos >= vb.limit()) break
            ub.position(pos); vb.position(pos)
            val nu = minOf(cRow, ub.remaining())
            val nv = minOf(cRow, vb.remaining())
            ub.get(uRowBuf, 0, nu); vb.get(vRowBuf, 0, nv)
            var src = 0
            val step = 2 * cPix
            for (x in 0 until cw) {
                out[o++] = if (src < nv) vRowBuf[src] else 127      // NV21: erst V, dann U
                out[o++] = if (src < nu) uRowBuf[src] else 127
                src += step
            }
        }
        jpeg.reset()
        YuvImage(out, ImageFormat.NV21, ow, oh, null).compressToJpeg(Rect(0, 0, ow, oh), QUALITY, jpeg)
        onJpeg(jpeg.toByteArray(), rotQuarter)
    }

    fun stop() {
        running = false
        try { session?.stopRepeating() } catch (_: Exception) {}
        try { session?.close() } catch (_: Exception) {}
        try { camera?.close() } catch (_: Exception) {}
        try { reader?.close() } catch (_: Exception) {}
        try { thread?.quitSafely() } catch (_: Exception) {}
        session = null; camera = null; reader = null; thread = null
    }
}
