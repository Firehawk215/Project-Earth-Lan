package de.projectearth.support.android

import android.Manifest
import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Paint
import android.graphics.RectF
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculateCentroid
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import de.projectearth.support.core.PesProto
import kotlinx.coroutines.delay

// Designsystem (ein Farbsatz fuer alle Project-Earth-Programme)
private val BG = Color(0xFF1E1E1E)
private val SURFACE = Color(0xFF2D2D2D)
private val FIELD = Color(0xFF282828)
private val BORDER = Color(0xFF464646)
private val TEXT = Color(0xFFF1F1F1)
private val MUTED = Color(0xFFAAB2BE)
private val ACCENT = Color(0xFF0078D7)
private val ACCENT_TEXT = Color(0xFF3A96DD)
private val OK = Color(0xFF4EC9B0)
private val OK_BG = Color(0xFF008746)
private val WARN = Color(0xFFFFAA3C)
private val ERR = Color(0xFFF48771)
private val DANGER = Color(0xFFA03228)

private val scheme = darkColorScheme(
    primary = ACCENT, onPrimary = Color.White, secondary = OK, background = BG, onBackground = TEXT,
    surface = SURFACE, onSurface = TEXT, surfaceVariant = FIELD, onSurfaceVariant = MUTED, error = ERR, outline = BORDER,
)

private fun t(s: String, vararg a: Any): String = Tr.t(s, *a)

/** Zustand aus der Anruf-Benachrichtigung ("Annehmen" getippt). */
object CallIntent {
    val accept = mutableStateOf(false)
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyCallIntent(intent)
        setContent { MaterialTheme(colorScheme = scheme) { Root() } }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        applyCallIntent(intent)
    }

    /** Kommt die App ueber die Anruf-Benachrichtigung nach vorn: auch bei gesperrtem Bildschirm anzeigen und Bildschirm einschalten. */
    private fun applyCallIntent(i: Intent?) {
        if (i == null || !i.getBooleanExtra(SupRuntime.EXTRA_CALL, false)) return
        val acc = i.getBooleanExtra(SupRuntime.EXTRA_CALL_ACCEPT, false)
        i.removeExtra(SupRuntime.EXTRA_CALL); i.removeExtra(SupRuntime.EXTRA_CALL_ACCEPT)
        if (Build.VERSION.SDK_INT >= 27) { setShowWhenLocked(true); setTurnScreenOn(true) }
        if (acc) CallIntent.accept.value = true
    }

    override fun onStart() { super.onStart(); SupRuntime.uiVisible = true }

    override fun onStop() {
        SupRuntime.uiVisible = false
        if (Build.VERSION.SDK_INT >= 27) { setShowWhenLocked(false); setTurnScreenOn(false) }
        // Kamera nur bei sichtbarer App (kein Kamera-Hintergrunddienst)
        Thread { SupRuntime.setCamOff() }.start()
        super.onStop()
    }
}

private fun displayDegOf(ctx: Context): Int {
    @Suppress("DEPRECATION")
    val r = (ctx as? Activity)?.windowManager?.defaultDisplay?.rotation ?: 0
    return r * 90
}

private fun copyText(ctx: Context, text: String) {
    val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    cm.setPrimaryClip(ClipData.newPlainText("Project Earth Support", text))
}

private fun shareInvite(ctx: Context, code: String) {
    if (code.isBlank()) return
    val msg = t("Project Earth Support - bitte diesen Einladungscode im Programm einfügen und auf Verbinden klicken:") + "\n\n" + code
    try {
        ctx.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, msg), t("Einladungscode senden")))
    } catch (e: Exception) { SupLog.e("Teilen", e) }
}

@Composable
private fun Root() {
    val ctx = LocalContext.current
    var st by remember { mutableStateOf(SupRuntime.snapshot()) }
    var langTick by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) {
        while (true) {
            st = try { SupRuntime.snapshot() } catch (_: Exception) { st }
            delay(250)
        }
    }
    val notifPerm = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
    LaunchedEffect(Unit) {
        if (Build.VERSION.SDK_INT >= 33 && ctx.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            notifPerm.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
    // Mikrofon-Berechtigung wird erst beim ersten Anruf abgefragt; danach laeuft die gemerkte Aktion weiter
    var afterMic by remember { mutableStateOf<(() -> Unit)?>(null) }
    val micPerm = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { _ -> val a = afterMic; afterMic = null; a?.invoke() }
    val withMic: (() -> Unit) -> Unit = { action ->
        if (SupRuntime.hasMicPermission()) action() else { afterMic = action; micPerm.launch(Manifest.permission.RECORD_AUDIO) }
    }
    // "Annehmen" in der Benachrichtigung
    val accept by CallIntent.accept
    LaunchedEffect(accept) {
        if (accept) { CallIntent.accept.value = false; withMic { SupRuntime.answerCall(true) } }
    }
    // Bildschirm bleibt an, solange eine Sitzung laeuft
    val view = LocalView.current
    DisposableEffect(st.active) {
        view.keepScreenOn = st.active
        onDispose { view.keepScreenOn = false }
    }

    key(langTick) {
        Box(Modifier.fillMaxSize().background(BG).statusBarsPadding().navigationBarsPadding()) {
            if (st.active || st.starting) SessionScreen(st, withMic) else StartScreen(st) { langTick++ }
        }
        if (st.callState == PesProto.CALL_IN) {
            IncomingCallScreen(st.partnerName, onAccept = { withMic { SupRuntime.answerCall(true) } }, onDecline = { SupRuntime.answerCall(false) })
        }
        val offer = st.fileOffer
        if (offer != null) {
            AlertDialog(
                onDismissRequest = { },
                containerColor = SURFACE,
                title = { Text(t("Datei empfangen")) },
                text = {
                    Column {
                        Text(t("{0} möchte dir eine Datei senden:", st.partnerName), fontSize = 14.sp)
                        Spacer(Modifier.height(8.dp))
                        Text(offer.name + "  (" + SupRuntime.fmtBytes(offer.size) + ")", color = OK, fontSize = 14.sp)
                        Spacer(Modifier.height(8.dp))
                        Text(t("Nimm nur Dateien an, die du erwartest. Gespeichert wird unter Download/Project Earth Support."), color = MUTED, fontSize = 12.sp)
                    }
                },
                confirmButton = { TextButton(onClick = { Thread { SupRuntime.answerFile(true) }.start() }) { Text(t("Annehmen")) } },
                dismissButton = { TextButton(onClick = { Thread { SupRuntime.answerFile(false) }.start() }) { Text(t("Ablehnen")) } },
            )
        }
    }
}

@Composable
private fun SectionCard(title: String, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Card(modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp), colors = CardDefaults.cardColors(containerColor = SURFACE)) {
        Column(Modifier.padding(12.dp)) {
            Text(title, color = ACCENT_TEXT, fontSize = 13.sp)
            Spacer(Modifier.height(6.dp))
            content()
        }
    }
}

// =====================================================================================================================
// Startseite: Anmeldung per Einladungscode (wie in Project Earth LAN) und "Neue Sitzung" fuer den Helfer
// =====================================================================================================================
@Composable
private fun StartScreen(st: UiState, onLanguage: () -> Unit) {
    val ctx = LocalContext.current
    val saved = remember { SupRuntime.settings() }
    var invite by remember { mutableStateOf(if (saved.remember && saved.inviteEnc.isNotEmpty()) (SupSecret.decrypt(saved.inviteEnc) ?: "") else "") }
    var name by remember { mutableStateOf(saved.name) }
    var server by remember { mutableStateOf(saved.server) }
    var rememberInvite by remember { mutableStateOf(saved.remember) }
    var msg by remember { mutableStateOf("") }
    var help by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).imePadding().padding(bottom = 24.dp)) {
        Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp, top = 10.dp, bottom = 2.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("Project Earth Support", color = TEXT, fontSize = 20.sp)
                Text(t("Live-Fernwartung mit Video-Chat"), color = MUTED, fontSize = 12.sp)
            }
            TextButton(onClick = { help = true }) { Text(t("Hilfe")) }
            TextButton(onClick = {
                val next = if (Tr.isEnglish) "de" else "en"
                Tr.setLanguage(next)
                val s = SupRuntime.settings()
                SupSettingsStore.save(ctx, SupSettings(s.name, s.inviteEnc, s.remember, s.server, s.machineKey, next, s.quality))
                onLanguage()
            }) { Text(if (Tr.isEnglish) "Deutsch" else "English") }
        }

        SectionCard(t("1. Neue Sitzung (du bist der Helfer)")) {
            Text(t("Trage die Adresse deines Vermittlers ein und erzeuge einen Code. Den Code bekommt der Kunde - er fügt ihn am PC in Project Earth Support ein."), color = MUTED, fontSize = 12.sp)
            Spacer(Modifier.height(6.dp))
            OutlinedTextField(
                value = server, onValueChange = { server = it.take(260) }, label = { Text(t("Vermittler-Adresse (Name oder IP, optional :Port)")) },
                singleLine = true, modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(6.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = {
                    val c = SupRuntime.newInvite(server)
                    if (c == null) msg = t("Bitte zuerst die Adresse des Vermittlers eintragen (Name oder IP, optional mit :Port).") else { invite = c; msg = "" }
                }) { Text(t("Neuen Code erzeugen")) }
                OutlinedButton(onClick = { shareInvite(ctx, invite) }, enabled = PesProto.inviteParse(invite) != null) { Text(t("Code senden")) }
            }
        }

        SectionCard(t("2. Verbindung")) {
            if (st.lastError.isNotEmpty()) Text(st.lastError, color = ERR, fontSize = 13.sp)
            if (msg.isNotEmpty()) Text(msg, color = ERR, fontSize = 13.sp)
            OutlinedTextField(
                value = invite, onValueChange = { invite = it.take(900) }, label = { Text(t("Einladungscode (PES1:...)")) },
                modifier = Modifier.fillMaxWidth(), maxLines = 3, textStyle = androidx.compose.ui.text.TextStyle(fontFamily = FontFamily.Monospace, fontSize = 13.sp),
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinedButton(onClick = {
                    val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    val c = cm.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(ctx)?.toString() ?: ""
                    if (c.isNotEmpty()) invite = c.trim()
                }) { Text(t("Einfügen")) }
                OutlinedButton(onClick = { if (invite.isNotBlank()) copyText(ctx, invite.trim()) }) { Text(t("Kopieren")) }
            }
            OutlinedTextField(value = name, onValueChange = { name = it.take(32) }, label = { Text(t("Mein Name")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(checked = rememberInvite, onCheckedChange = { rememberInvite = it })
                Text(t("Einladungscode merken (verschlüsselt im Android Keystore)"), fontSize = 13.sp)
            }
            Button(onClick = { msg = SupRuntime.requestConnect(invite, name, rememberInvite) ?: "" }, modifier = Modifier.fillMaxWidth()) { Text(t("Verbinden")) }
        }

        Text(
            t("Diese App ist für den Helfer. Der Kunde startet Project-Earth-Support auf seinem Windows-PC, fügt den Code ein und entscheidet selbst, ob er seinen Bildschirm zeigt und die Steuerung erlaubt."),
            color = MUTED, fontSize = 12.sp, modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
        )
    }
    if (help) HelpDialog { help = false }
}

// =====================================================================================================================
// Sitzung: oben Live-Video-Chat, unten Fernwartung
// =====================================================================================================================
@Composable
private fun SessionScreen(st: UiState, withMic: ((() -> Unit) -> Unit)) {
    val ctx = LocalContext.current
    var full by remember { mutableStateOf(false) }
    var chatOpen by remember { mutableStateOf(false) }
    var confirmEnd by remember { mutableStateOf(false) }
    var msg by remember { mutableStateOf("") }
    var seenChat by remember { mutableIntStateOf(st.chatVersion) }
    val pickFile = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri != null) Thread { msg = SupRuntime.sendFile(uri) ?: "" }.start()
    }
    BackHandler(enabled = true) { if (full) full = false else confirmEnd = true }

    Column(Modifier.fillMaxSize()) {
        if (!full) {
            // Kopfzeile: Status und Trennen
            Row(Modifier.fillMaxWidth().background(SURFACE).padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    val head = when {
                        st.paired -> t("Verbunden mit {0}", st.partnerName)
                        st.active && st.engineState == Tr.core("Verbunden") -> t("Warte auf den Kunden ...")
                        st.active -> st.engineState
                        else -> t("Verbinde ...")
                    }
                    Text(head, color = if (st.paired) OK else WARN, fontSize = 15.sp, maxLines = 1)
                    val way = when (st.path) { 1 -> t("direkt"); 2 -> t("über den Vermittler (Relay)"); else -> "" }
                    val sub = if (st.paired) (way + (if (st.rtt >= 0) ", " + st.rtt + " ms" else "")) else if (st.lastError.isNotEmpty()) st.lastError else st.ownIp
                    if (sub.isNotEmpty()) Text(sub, color = MUTED, fontSize = 11.sp, maxLines = 1)
                }
                OutlinedButton(onClick = { confirmEnd = true }, contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp)) { Text(t("Trennen"), fontSize = 13.sp) }
            }
        }
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            val wide = maxWidth > maxHeight
            if (full) {
                RemoteArea(st, full = true, onFull = { full = false }, modifier = Modifier.fillMaxSize())
            } else if (wide) {
                Row(Modifier.fillMaxSize()) {
                    VideoArea(st, withMic, onMsg = { msg = it }, modifier = Modifier.weight(0.38f).fillMaxHeight())
                    Box(Modifier.width(2.dp).fillMaxHeight().background(BORDER))
                    RemoteArea(st, full = false, onFull = { full = true }, modifier = Modifier.weight(0.62f).fillMaxHeight())
                }
            } else {
                Column(Modifier.fillMaxSize()) {
                    VideoArea(st, withMic, onMsg = { msg = it }, modifier = Modifier.weight(0.40f).fillMaxWidth())
                    Box(Modifier.height(2.dp).fillMaxWidth().background(BORDER))
                    RemoteArea(st, full = false, onFull = { full = true }, modifier = Modifier.weight(0.60f).fillMaxWidth())
                }
            }
        }
        if (!full) {
            val info = if (msg.isNotEmpty()) msg else if (st.fileText.isNotEmpty()) st.fileText else st.mediaMsg
            if (info.isNotEmpty()) Text(info, color = if (msg.isNotEmpty()) ERR else MUTED, fontSize = 12.sp, maxLines = 2, modifier = Modifier.padding(horizontal = 12.dp, vertical = 2.dp))
            Row(Modifier.fillMaxWidth().background(SURFACE).padding(horizontal = 8.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                val unread = st.chatVersion != seenChat && !chatOpen
                Button(onClick = { chatOpen = true; seenChat = st.chatVersion }, modifier = Modifier.weight(1f),
                    colors = ButtonDefaults.buttonColors(containerColor = if (unread) OK_BG else ACCENT), contentPadding = PaddingValues(4.dp)) { Text(if (unread) t("Chat (neu)") else t("Chat"), fontSize = 13.sp, maxLines = 1) }
                OutlinedButton(onClick = { msg = ""; pickFile.launch("*/*") }, enabled = st.paired, modifier = Modifier.weight(1f), contentPadding = PaddingValues(4.dp)) { Text(t("Datei senden"), fontSize = 13.sp, maxLines = 1) }
                OutlinedButton(onClick = { shareInvite(ctx, st.invite) }, modifier = Modifier.weight(1f), contentPadding = PaddingValues(4.dp)) { Text(t("Code senden"), fontSize = 13.sp, maxLines = 1) }
            }
        }
    }
    if (chatOpen) ChatDialog(st) { chatOpen = false; seenChat = st.chatVersion }
    if (confirmEnd) {
        AlertDialog(
            onDismissRequest = { confirmEnd = false },
            containerColor = SURFACE,
            title = { Text(t("Sitzung beenden?")) },
            text = { Text(if (st.paired) t("Die Verbindung zu {0} wird getrennt.", st.partnerName) else t("Die Sitzung wird beendet.")) },
            confirmButton = { TextButton(onClick = { confirmEnd = false; SupRuntime.requestDisconnect() }) { Text(t("Trennen"), color = ERR) } },
            dismissButton = { TextButton(onClick = { confirmEnd = false }) { Text(t("Zurück")) } },
        )
    }
}

/** Zeichnet das letzte Videobild (Partner oder eigene Kamera), eingepasst und nach der Drehung des Senders aufrecht gestellt. */
@Composable
private fun VideoCanvas(remote: Boolean, mirror: Boolean, modifier: Modifier) {
    val ver by produceState(0) { while (true) { value = if (remote) SupRuntime.remoteVideoVersion else SupRuntime.selfVideoVersion; delay(40) } }
    val paint = remember { Paint(Paint.FILTER_BITMAP_FLAG) }
    Canvas(modifier.clipToBounds()) {
        if (ver < 0) return@Canvas                      // liest den Zaehler: jede Aenderung zeichnet neu
        drawIntoCanvas { c ->
            synchronized(SupRuntime.videoLock) {
                val b = if (remote) SupRuntime.remoteFrame else SupRuntime.selfFrame
                val rot = if (remote) SupRuntime.remoteRot else SupRuntime.selfRot
                if (b != null && !b.isRecycled && size.width > 4f && size.height > 4f) {
                    val side = rot % 2 == 1
                    val iw = (if (side) b.height else b.width).toFloat()
                    val ih = (if (side) b.width else b.height).toFloat()
                    val sc = minOf(size.width / iw, size.height / ih)
                    val dw = b.width * sc
                    val dh = b.height * sc
                    val nc = c.nativeCanvas
                    nc.save()
                    nc.translate(size.width / 2f, size.height / 2f)
                    nc.rotate(rot * 90f)
                    if (mirror) nc.scale(-1f, 1f)
                    nc.drawBitmap(b, null, RectF(-dw / 2f, -dh / 2f, dw / 2f, dh / 2f), paint)
                    nc.restore()
                }
            }
        }
    }
}

@Composable
private fun VideoArea(st: UiState, withMic: ((() -> Unit) -> Unit), onMsg: (String) -> Unit, modifier: Modifier) {
    val ctx = LocalContext.current
    val camPerm = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        if (!ok) onMsg(t("Ohne Kamera-Berechtigung ist kein Video möglich."))
        else { val d = displayDegOf(ctx); Thread { onMsg(SupRuntime.startCamera(d) ?: "") }.start() }
    }
    val inCall = st.callState == PesProto.CALL_ACTIVE
    Column(modifier.background(Color(0xFF14181C))) {
        Box(Modifier.weight(1f).fillMaxWidth()) {
            if (inCall && st.hasRemoteVideo) VideoCanvas(remote = true, mirror = false, modifier = Modifier.fillMaxSize())
            else {
                val ph = when {
                    inCall && st.partnerCam -> t("Warte auf das Bild ...")
                    inCall -> t("Die Kamera des Partners ist aus.")
                    st.callState == PesProto.CALL_OUT -> t("Es klingelt beim Partner ...")
                    st.paired -> t("Live-Video-Chat") + "\n" + t("Mit Anrufen startest du Bild und Ton.")
                    else -> t("Live-Video-Chat") + "\n" + t("Sobald der Kunde verbunden ist, kannst du ihn anrufen.")
                }
                Text(ph, color = MUTED, fontSize = 14.sp, textAlign = TextAlign.Center, modifier = Modifier.align(Alignment.Center).padding(16.dp))
            }
            if (st.paired) Text(st.partnerName, color = Color.White, fontSize = 12.sp, maxLines = 1,
                modifier = Modifier.align(Alignment.BottomStart).padding(6.dp).background(Color(0x99000000)).padding(horizontal = 6.dp, vertical = 2.dp))
            if (st.camOn) {
                Box(Modifier.align(Alignment.BottomEnd).padding(6.dp).size(width = 78.dp, height = 104.dp).background(Color(0xFF282C32)).border(1.dp, BORDER)) {
                    VideoCanvas(remote = false, mirror = st.camFront, modifier = Modifier.fillMaxSize())
                }
            }
        }
        // Bedienleiste des Anrufs
        val pad = PaddingValues(horizontal = 4.dp, vertical = 4.dp)
        Row(Modifier.fillMaxWidth().background(SURFACE).padding(horizontal = 6.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            if (st.callState == PesProto.CALL_IDLE || st.callState == PesProto.CALL_IN) {
                Button(onClick = { withMic { SupRuntime.call() } }, enabled = st.paired && st.callState == PesProto.CALL_IDLE, modifier = Modifier.weight(1.3f), contentPadding = pad,
                    colors = ButtonDefaults.buttonColors(containerColor = OK_BG)) { Text(t("Anrufen"), fontSize = 13.sp, maxLines = 1) }
            } else {
                Button(onClick = { SupRuntime.hangup() }, modifier = Modifier.weight(1.3f), contentPadding = pad,
                    colors = ButtonDefaults.buttonColors(containerColor = DANGER)) { Text(t("Auflegen"), fontSize = 13.sp, maxLines = 1) }
            }
            OutlinedButton(onClick = { SupRuntime.setMic(!st.micOn) }, modifier = Modifier.weight(1f), contentPadding = pad) { Text(if (st.micOn) t("Mikro: an") else t("Mikro: aus"), fontSize = 12.sp, maxLines = 1, color = if (st.micOn) TEXT else ERR) }
            OutlinedButton(onClick = {
                if (st.camOn) Thread { SupRuntime.setCamOff() }.start()
                else if (!SupRuntime.hasCamPermission()) camPerm.launch(Manifest.permission.CAMERA)
                else { val d = displayDegOf(ctx); Thread { onMsg(SupRuntime.startCamera(d) ?: "") }.start() }
            }, enabled = inCall, modifier = Modifier.weight(1f), contentPadding = pad) { Text(if (st.camOn) t("Kamera: an") else t("Kamera: aus"), fontSize = 12.sp, maxLines = 1) }
            OutlinedButton(onClick = { Thread { onMsg(SupRuntime.switchCamera() ?: "") }.start() }, enabled = inCall, modifier = Modifier.weight(0.8f), contentPadding = pad) { Text(if (st.camFront) t("Front") else t("Rück"), fontSize = 12.sp, maxLines = 1) }
            OutlinedButton(onClick = { SupRuntime.setSpeaker(!st.speaker) }, modifier = Modifier.weight(1f), contentPadding = pad) { Text(if (st.speaker) t("Laut") else t("Hörer"), fontSize = 12.sp, maxLines = 1) }
        }
    }
}

/** Lage des Fernbilds in der Ansicht: eingepasst, mit Vergroesserung und Verschiebung. Liefert (links, oben, Breite, Hoehe). */
private fun fitRect(bw: Int, bh: Int, vw: Float, vh: Float, zoom: Float, pan: Offset): FloatArray {
    val base = minOf(vw / bw, vh / bh)
    val w = bw * base * zoom
    val h = bh * base * zoom
    // Verschieben nur so weit, wie das Bild ueber den Rand hinausragt
    val maxX = maxOf(0f, (w - vw) / 2f)
    val maxY = maxOf(0f, (h - vh) / 2f)
    val px = pan.x.coerceIn(-maxX, maxX)
    val py = pan.y.coerceIn(-maxY, maxY)
    return floatArrayOf((vw - w) / 2f + px, (vh - h) / 2f + py, w, h)
}

@Composable
private fun RemoteArea(st: UiState, full: Boolean, onFull: () -> Unit, modifier: Modifier) {
    var keys by remember { mutableStateOf(false) }
    var text by remember { mutableStateOf("") }
    Column(modifier.background(Color(0xFF121212))) {
        // Leiste der Fernwartung (laesst sich waagerecht schieben, falls der Platz nicht reicht)
        val pad = PaddingValues(horizontal = 10.dp, vertical = 4.dp)
        Row(Modifier.fillMaxWidth().background(SURFACE).horizontalScroll(rememberScrollState()).padding(horizontal = 6.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            if (st.share) Button(onClick = { SupRuntime.stopView() }, contentPadding = pad, colors = ButtonDefaults.buttonColors(containerColor = DANGER)) { Text(t("Ansicht beenden"), fontSize = 12.sp) }
            else Button(onClick = { SupRuntime.requestView() }, enabled = st.paired, contentPadding = pad) { Text(t("Bildschirm anfordern"), fontSize = 12.sp) }
            if (st.control) Button(onClick = { SupRuntime.releaseControl() }, contentPadding = pad, colors = ButtonDefaults.buttonColors(containerColor = OK_BG)) { Text(t("Steuerung: an"), fontSize = 12.sp) }
            else OutlinedButton(onClick = { SupRuntime.requestControl() }, enabled = st.paired, contentPadding = pad) { Text(t("Steuerung anfordern"), fontSize = 12.sp) }
            OutlinedButton(onClick = { keys = !keys }, enabled = st.control, contentPadding = pad) { Text(t("Tastatur"), fontSize = 12.sp) }
            OutlinedButton(onClick = { SupRuntime.setQuality(if (st.quality >= 3) 1 else st.quality + 1) }, contentPadding = pad) {
                Text(when (st.quality) { 1 -> t("Sparsam"); 3 -> t("Scharf"); else -> t("Normal") }, fontSize = 12.sp)
            }
            if (st.monitors > 1) OutlinedButton(onClick = { SupRuntime.setMonitor((st.monitor + 1) % st.monitors) }, contentPadding = pad) { Text(t("Bildschirm {0}", st.monitor + 1), fontSize = 12.sp) }
            OutlinedButton(onClick = onFull, contentPadding = pad) { Text(if (full) t("Normal") else t("Vollbild"), fontSize = 12.sp) }
        }
        RemoteView(st, Modifier.weight(1f).fillMaxWidth())
        if (keys && st.control) {
            Column(Modifier.fillMaxWidth().background(SURFACE).imePadding().padding(horizontal = 6.dp, vertical = 4.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    OutlinedTextField(
                        value = text, onValueChange = { text = it.take(200) }, placeholder = { Text(t("Text für den PC des Kunden"), fontSize = 13.sp) },
                        singleLine = true, modifier = Modifier.weight(1f),
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
                        keyboardActions = KeyboardActions(onSend = { if (text.isNotEmpty()) { SupRuntime.inputText(text); text = "" } }),
                    )
                    Button(onClick = { if (text.isNotEmpty()) { SupRuntime.inputText(text); text = "" } }, contentPadding = pad) { Text(t("Senden"), fontSize = 12.sp) }
                }
                val chips = listOf(
                    "Enter" to intArrayOf(0x0D), "Esc" to intArrayOf(0x1B), "Tab" to intArrayOf(0x09), t("Rücktaste") to intArrayOf(0x08), t("Entf") to intArrayOf(0x2E),
                    t("Links") to intArrayOf(0x25), t("Hoch") to intArrayOf(0x26), t("Runter") to intArrayOf(0x28), t("Rechts") to intArrayOf(0x27),
                    "Win" to intArrayOf(0x5B), t("Strg") + "+C" to intArrayOf(0x11, 0x43), t("Strg") + "+V" to intArrayOf(0x11, 0x56), t("Strg") + "+A" to intArrayOf(0x11, 0x41),
                    t("Strg") + "+Z" to intArrayOf(0x11, 0x5A), "Alt+Tab" to intArrayOf(0x12, 0x09), "Alt+F4" to intArrayOf(0x12, 0x73),
                    t("Task-Manager") to intArrayOf(0x11, 0x10, 0x1B), "Win+R" to intArrayOf(0x5B, 0x52), "Win+D" to intArrayOf(0x5B, 0x44),
                )
                Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    chips.forEach { (label, vks) ->
                        OutlinedButton(onClick = { SupRuntime.inputKeys(*vks) }, contentPadding = PaddingValues(horizontal = 10.dp, vertical = 2.dp)) { Text(label, fontSize = 12.sp) }
                    }
                }
            }
        }
    }
}

/**
 * Der Bildschirm des Kunden. Bedienung bei erlaubter Steuerung:
 * Tippen = Linksklick (zweimal = Doppelklick), lange druecken = Rechtsklick, mit einem Finger ziehen = Maus ziehen,
 * zwei Finger = vergroessern/verschieben; ohne Vergroesserung blaettern zwei Finger hoch/runter (Mausrad).
 */
@Composable
private fun RemoteView(st: UiState, modifier: Modifier) {
    val ver by produceState(0) { while (true) { value = SupRuntime.screenVersion; delay(33) } }
    var zoom by remember { mutableFloatStateOf(1f) }
    var pan by remember { mutableStateOf(Offset.Zero) }
    var vsize by remember { mutableStateOf(IntSize.Zero) }
    val paint = remember { Paint(Paint.FILTER_BITMAP_FLAG) }
    val control = st.control
    val hasImage = st.share && ver >= 0 && SupRuntime.screenBitmap != null
    LaunchedEffect(st.share) { if (!st.share) { zoom = 1f; pan = Offset.Zero } }

    fun norm(p: Offset): Pair<Int, Int>? {
        val b = SupRuntime.screenBitmap ?: return null
        if (vsize.width < 8 || vsize.height < 8) return null
        val r = fitRect(b.width, b.height, vsize.width.toFloat(), vsize.height.toFloat(), zoom, pan)
        if (r[2] < 2f || r[3] < 2f) return null
        val fx = ((p.x - r[0]) / (r[2] - 1f)).coerceIn(0f, 1f)
        val fy = ((p.y - r[1]) / (r[3] - 1f)).coerceIn(0f, 1f)
        return Pair((fx * 65535f).toInt(), (fy * 65535f).toInt())
    }

    Box(modifier.clipToBounds().onSizeChanged { vsize = it }.pointerInput(control) {
        val slop = viewConfiguration.touchSlop
        awaitEachGesture {
            val down = awaitFirstDown(requireUnconsumed = false)
            val start = down.position
            val startTime = down.uptimeMillis
            var last = start
            var lastTime = startTime
            var moved = false
            var multi = false
            var dragging = false
            var wheelAcc = 0f
            while (true) {
                val ev = awaitPointerEvent()
                val pressed = ev.changes.filter { it.pressed }
                if (pressed.isEmpty()) { lastTime = ev.changes.firstOrNull()?.uptimeMillis ?: lastTime; break }
                if (pressed.size >= 2) {
                    if (!multi && dragging) { norm(last)?.let { SupRuntime.inputButton(0, false, it.first, it.second) }; dragging = false }
                    multi = true
                    val z = ev.calculateZoom()
                    val pn = ev.calculatePan()
                    val centroid = ev.calculateCentroid()
                    if (zoom <= 1.01f && Math.abs(z - 1f) < 0.02f) {
                        // Nicht vergroessert: zwei Finger hoch/runter = Mausrad
                        if (control) {
                            wheelAcc += pn.y
                            while (Math.abs(wheelAcc) >= 36f) {
                                val dir = if (wheelAcc > 0) 1 else -1
                                wheelAcc -= dir * 36f
                                norm(centroid)?.let { SupRuntime.inputWheel(dir * 120, it.first, it.second) }
                            }
                        }
                    } else {
                        zoom = (zoom * z).coerceIn(1f, 6f)
                        pan = if (zoom <= 1.01f) Offset.Zero else pan + pn
                    }
                    ev.changes.forEach { it.consume() }
                } else if (!multi) {
                    val p = pressed[0]
                    last = p.position
                    if (!moved && (p.position - start).getDistance() > slop) {
                        moved = true
                        if (control) { norm(start)?.let { SupRuntime.inputButton(0, true, it.first, it.second); dragging = true } }
                    }
                    if (moved) {
                        if (dragging) norm(p.position)?.let { SupRuntime.inputMove(it.first, it.second) }
                        else if (zoom > 1.01f) pan += p.positionChange()
                        p.consume()
                    }
                }
            }
            if (dragging) norm(last)?.let { SupRuntime.inputButton(0, false, it.first, it.second) }
            else if (!multi && !moved && control) {
                // Kurz getippt = Linksklick, lange gedrueckt = Rechtsklick
                norm(start)?.let { SupRuntime.inputClick(if (lastTime - startTime >= 550) 1 else 0, it.first, it.second) }
            }
        }
    }) {
        Canvas(Modifier.fillMaxSize()) {
            if (ver < 0) return@Canvas                  // liest den Zaehler: jede Aenderung zeichnet neu
            drawIntoCanvas { c ->
                synchronized(SupRuntime.screenLock) {
                    val b = SupRuntime.screenBitmap
                    if (b != null && !b.isRecycled && size.width > 8f && size.height > 8f) {
                        val r = fitRect(b.width, b.height, size.width, size.height, zoom, pan)
                        c.nativeCanvas.drawBitmap(b, null, RectF(r[0], r[1], r[0] + r[2], r[1] + r[3]), paint)
                    }
                }
            }
        }
        if (!hasImage) {
            val ph = when {
                !st.paired -> t("Fernwartung") + "\n" + t("Hier erscheint der Bildschirm des Kunden.")
                st.share -> t("Warte auf das Bild ...")
                st.viewWanted -> t("Warte auf die Zustimmung des Kunden ...")
                else -> t("Der Kunde überträgt seinen Bildschirm nicht.") + "\n" + t("Mit \"Bildschirm anfordern\" fragst du ihn danach.")
            }
            Text(ph, color = MUTED, fontSize = 14.sp, textAlign = TextAlign.Center, modifier = Modifier.align(Alignment.Center).padding(16.dp))
        } else if (control) {
            Box(Modifier.fillMaxSize().border(2.dp, ACCENT))
        }
    }
}

/** Vollbild-Anrufbildschirm fuer eingehende Anrufe (wie ein Telefonat): Name gross, Annehmen gruen, Ablehnen rot. */
@Composable
private fun IncomingCallScreen(name: String, onAccept: () -> Unit, onDecline: () -> Unit) {
    Dialog(
        onDismissRequest = { },
        properties = DialogProperties(dismissOnBackPress = false, dismissOnClickOutside = false, usePlatformDefaultWidth = false),
    ) {
        Box(Modifier.fillMaxSize().background(Color(0xFF14181C)).statusBarsPadding().navigationBarsPadding()) {
            Column(Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Spacer(Modifier.weight(1f))
                Text(t("Eingehender Anruf"), color = MUTED, fontSize = 16.sp)
                Spacer(Modifier.height(24.dp))
                Box(Modifier.size(120.dp).clip(CircleShape).background(ACCENT), contentAlignment = Alignment.Center) {
                    Text(name.take(1).uppercase().ifEmpty { "?" }, color = Color.White, fontSize = 56.sp)
                }
                Spacer(Modifier.height(20.dp))
                Text(name, color = TEXT, fontSize = 32.sp, maxLines = 2, textAlign = TextAlign.Center)
                Text(t("ruft an (Video-Chat mit Ton)"), color = MUTED, fontSize = 15.sp, textAlign = TextAlign.Center)
                Spacer(Modifier.weight(1f))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Box(Modifier.size(84.dp).clip(CircleShape).background(DANGER).clickable { onDecline() }, contentAlignment = Alignment.Center) {
                            Text(t("Nein"), color = Color.White, fontSize = 18.sp)
                        }
                        Spacer(Modifier.height(8.dp))
                        Text(t("Ablehnen"), color = TEXT, fontSize = 15.sp)
                    }
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Box(Modifier.size(84.dp).clip(CircleShape).background(OK_BG).clickable { onAccept() }, contentAlignment = Alignment.Center) {
                            Text(t("Ja"), color = Color.White, fontSize = 18.sp)
                        }
                        Spacer(Modifier.height(8.dp))
                        Text(t("Annehmen"), color = TEXT, fontSize = 15.sp)
                    }
                }
                Spacer(Modifier.height(28.dp))
            }
        }
    }
}

@Composable
private fun ChatDialog(st: UiState, onClose: () -> Unit) {
    var text by remember { mutableStateOf("") }
    val list = rememberLazyListState()
    val lines = remember(st.chatVersion) { SupRuntime.chat.toList() }
    LaunchedEffect(lines.size) { if (lines.isNotEmpty()) list.scrollToItem(lines.size - 1) }
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(Modifier.fillMaxSize().background(BG).statusBarsPadding().navigationBarsPadding().imePadding()) {
            Row(Modifier.fillMaxWidth().background(SURFACE).padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(t("Chat und Verlauf"), color = ACCENT_TEXT, fontSize = 15.sp, modifier = Modifier.weight(1f))
                TextButton(onClick = onClose) { Text(t("Schließen")) }
            }
            LazyColumn(Modifier.weight(1f).fillMaxWidth().padding(horizontal = 10.dp), state = list) {
                items(lines) { l ->
                    val color = when (l.kind) { 1 -> TEXT; 2 -> TEXT; 3 -> WARN; 4 -> ERR; else -> MUTED }
                    Row(Modifier.padding(vertical = 2.dp)) {
                        Text(l.time + " ", color = MUTED, fontSize = 12.sp)
                        if (l.who.isNotEmpty()) Text(l.who + ": ", color = if (l.kind == 1) ACCENT_TEXT else OK, fontSize = 14.sp)
                        Text(l.text, color = color, fontSize = 14.sp)
                    }
                }
            }
            Row(Modifier.fillMaxWidth().background(SURFACE).padding(8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = text, onValueChange = { text = it.take(2000) }, placeholder = { Text(t("Nachricht")) }, modifier = Modifier.weight(1f), maxLines = 3,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
                    keyboardActions = KeyboardActions(onSend = { if (text.isNotBlank()) { SupRuntime.sendChat(text); text = "" } }),
                    enabled = st.paired,
                )
                Button(onClick = { if (text.isNotBlank()) { SupRuntime.sendChat(text); text = "" } }, enabled = st.paired) { Text(t("Senden")) }
            }
        }
    }
}

@Composable
private fun HelpDialog(onClose: () -> Unit) {
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(Modifier.fillMaxSize().background(BG).statusBarsPadding().navigationBarsPadding()) {
            Row(Modifier.fillMaxWidth().background(SURFACE).padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(t("Anleitung und Hilfe"), color = ACCENT_TEXT, fontSize = 15.sp, modifier = Modifier.weight(1f))
                TextButton(onClick = onClose) { Text(t("Schließen")) }
            }
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(14.dp)) {
                Tr.help().forEach { (head, body) ->
                    Text(head, color = ACCENT_TEXT, fontSize = 14.sp)
                    Text(body, color = TEXT, fontSize = 13.sp)
                    Spacer(Modifier.height(12.dp))
                }
                Text("Version " + BuildInfo.VERSION, color = MUTED, fontSize = 12.sp)
            }
        }
    }
}
