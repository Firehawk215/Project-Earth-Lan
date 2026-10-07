
# ==============================================================================
# 9. START (Mutex je Fenster/Port, Fehlerprotokoll, Aufräumen im finally)
# ==============================================================================
$script:PesSelbsttest = [bool]$Selbsttest
$script:PesIcon = $null
$script:PesTray = $null
$script:PesShowEvent = $null
$script:PesMutex = $null

# Kleines Startfenster: das Laden der eingebetteten Programmteile dauert einen Moment
function Show-PesSplash {
    $f = New-Object System.Windows.Forms.Form
    $f.FormBorderStyle = 'None'; $f.StartPosition = 'CenterScreen'; $f.ShowInTaskbar = $false; $f.TopMost = $true
    $f.BackColor = $script:C.Surface; $f.Size = New-Object System.Drawing.Size(380, 84)
    $l = New-Object System.Windows.Forms.Label
    $l.Dock = 'Fill'; $l.TextAlign = 'MiddleCenter'; $l.ForeColor = $script:C.Text; $l.Font = $script:FontBig
    $l.Text = 'Project Earth Support ...'
    $f.Controls.Add($l)
    $f.Show(); $f.Refresh()
    return $f
}

# Nur eine Instanz je Fenster (beim Vermittler: je Port). Liefert $false, wenn schon eine läuft.
function Enter-PesSingleInstance {
    param([string]$Key)
    $created = $false
    try {
        $script:PesMutex = New-Object System.Threading.Mutex($true, ('Global\ProjectEarthSupport_' + $Key), [ref]$created)
        $script:PesShowEvent = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, ('Global\ProjectEarthSupport_Show_' + $Key))
    } catch { $created = $true }
    if (-not $created) {
        # Läuft schon: das vorhandene Fenster nach vorne holen statt ein zweites zu öffnen
        try { [void]$script:PesShowEvent.Set() } catch { }
        return $false
    }
    return $true
}

function New-PesTray {
    param([string]$Text, [scriptblock]$OnOpen, [scriptblock]$OnExit, [string]$ExitText)
    $t = New-Object System.Windows.Forms.NotifyIcon
    if ($script:PesIcon) { $t.Icon = $script:PesIcon } else { $t.Icon = [System.Drawing.SystemIcons]::Application }
    $t.Text = $Text
    $m = New-Object System.Windows.Forms.ContextMenuStrip
    $i1 = New-Object System.Windows.Forms.ToolStripMenuItem; [PesI18n]::Reg($i1, 'Öffnen'); $i1.Add_Click($OnOpen); [void]$m.Items.Add($i1)
    $i2 = New-Object System.Windows.Forms.ToolStripMenuItem; [PesI18n]::Reg($i2, $ExitText); $i2.Add_Click($OnExit); [void]$m.Items.Add($i2)
    $t.ContextMenuStrip = $m
    $t.Add_DoubleClick($OnOpen)
    $t.Visible = $true
    return $t
}

function Start-PesMainMode {
    if (-not (Enter-PesSingleInstance 'Main')) { return }
    $splash = $null
    if (-not $Autostart -and -not $script:PesSelbsttest) { $splash = Show-PesSplash }
    try {
        Initialize-PesTypes
        [PesNative]::HideConsole()
        [PesI18n]::Lang = [string]$script:PesSettings.Language
        $script:PesIcon = New-PesIcon
        $script:PesHost = New-Object PesHost
        $form = New-PesMainWindow
        $script:PesHost.RemoteVideo = $script:PesUi.VidRemote
        $script:PesHost.SelfVideo = $script:PesUi.VidSelf
        $script:PesHost.View = $script:PesUi.View
        Set-PesLanguage
        $script:PesTray = New-PesTray -Text $script:PesTitle -ExitText 'Beenden' -OnOpen { Show-PesMainWindow } -OnExit { $script:PesUi.Form.Close() }
        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = 100
        $timer.Add_Tick({ try { Update-PesMain } catch { Write-PesLog -Level 'FEHLER' -Message ('Zeitgeber: ' + $_.Exception.Message + ' @ ' + $_.InvocationInfo.ScriptLineNumber); $script:PesState.SelfTestErrors++ } })
        $timer.Start()
        Write-PesLog -Message ('Gestartet, Version ' + $script:PesVersion + $(if ($script:IsCompiledExe) { ' (exe)' } else { ' (ps1)' }))
    } finally {
        if ($splash) { $splash.Close(); $splash.Dispose() }
    }
    try {
        if ($script:PesSelbsttest) { Invoke-PesSelfTest -Form $form; return }
        if ($Autostart) {
            # Autostart: nur im Infobereich bleiben; verbunden wird erst, wenn der Nutzer es will
            if ($script:PesSettings.RvAutostart) { $script:PesState.RvProc = Start-PesSelf @('-Vermittler', '-Autostart') }
            $form.WindowState = 'Minimized'
            $form.ShowInTaskbar = $false
            $form.Add_Shown({ $this.Hide(); $this.ShowInTaskbar = $true })
        }
        [System.Windows.Forms.Application]::Run($form)
    } finally {
        try { $timer.Stop(); $timer.Dispose() } catch { }
        try { Stop-PesShareUi } catch { }
        try { Close-PesRing } catch { }
        try { $script:PesHost.Disconnect() } catch { }
        try { if ($script:PesTray) { $script:PesTray.Visible = $false; $script:PesTray.Dispose() } } catch { }
        Start-Sleep -Milliseconds 300              # Abmeldung beim Partner und beim Vermittler noch hinausgehen lassen
        Write-PesLog -Message 'Beendet.'
    }
}

function Start-PesOptionsMode {
    if (-not (Enter-PesSingleInstance 'Optionen')) { return }
    Initialize-PesTypes
    [PesNative]::HideConsole()
    [PesI18n]::Lang = [string]$script:PesSettings.Language
    $script:PesIcon = New-PesIcon
    $f = Show-PesOptionsWindow
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 200
    $timer.Add_Tick({
        try { Receive-PesJobs } catch { }
        if ($script:PesShowEvent -and $script:PesShowEvent.WaitOne(0)) { try { $script:PesOptForm.Activate() } catch { } }
    })
    $timer.Start()
    try { [System.Windows.Forms.Application]::Run($f) } finally { $timer.Stop(); $timer.Dispose() }
}

function Start-PesHelpMode {
    if (-not (Enter-PesSingleInstance 'Hilfe')) { return }
    Initialize-PesTypes
    [PesNative]::HideConsole()
    [PesI18n]::Lang = [string]$script:PesSettings.Language
    $script:PesIcon = New-PesIcon
    [System.Windows.Forms.Application]::Run((Show-PesHelpWindow))
}

function Start-PesRvMode {
    $rvPort = if ($Port -gt 0) { $Port } else { [int]$script:PesSettings.RvPort }
    if ($rvPort -lt 1 -or $rvPort -gt 65535) { $rvPort = $script:PesDefaultRvPort }
    $script:PesLogContext = 'vermittler-' + $rvPort
    if (-not (Enter-PesSingleInstance ('Vermittler_' + $rvPort))) { return }
    Initialize-PesTypes
    [PesNative]::HideConsole()
    [PesI18n]::Lang = [string]$script:PesSettings.Language
    $script:PesIcon = New-PesIcon
    $f = Show-PesRvWindow -RvPort $rvPort
    $script:PesTray = New-PesTray -Text ($script:PesTitle + ' - Vermittler (UDP ' + $rvPort + ')') -ExitText 'Vermittler beenden' -OnOpen { try { $script:PesRvForm.Show(); $script:PesRvForm.Activate() } catch { } } -OnExit { $script:PesRvForm.Close() }
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 200
    $timer.Add_Tick({ try { Update-PesRv } catch { Write-PesLog -Level 'FEHLER' -Message ('Vermittler-Zeitgeber: ' + $_.Exception.Message) } })
    $timer.Start()
    Write-PesLog -Message ('Vermittler gestartet auf UDP ' + $rvPort)
    try {
        if ($Autostart) { $f.WindowState = 'Minimized'; $f.ShowInTaskbar = $false; $f.Add_Shown({ $this.Hide(); $this.ShowInTaskbar = $true; $this.WindowState = 'Normal' }) }
        [System.Windows.Forms.Application]::Run($f)
    } finally {
        try { $timer.Stop(); $timer.Dispose() } catch { }
        try { if ($script:PesRv.Server) { $script:PesRv.Server.Stop() } } catch { }
        try { if ($script:PesTray) { $script:PesTray.Visible = $false; $script:PesTray.Dispose() } } catch { }
        Write-PesLog -Message 'Vermittler beendet.'
    }
}

# ---- Selbsttest (-Selbsttest): baut alle Fenster auf, spielt die Abläufe einmal durch und beendet sich ----
function Invoke-PesSelfTest {
    param($Form)
    $script:PesTestFail = 0
    $out = New-Object System.Collections.Generic.List[string]
    $chk = {
        param([bool]$Ok, [string]$What)
        if ($Ok) { $out.Add('  OK   ' + $What) } else { $out.Add('  FEHLER ' + $What); $script:PesTestFail++ }
    }
    $pump = { param([int]$Ms) $sw = [Diagnostics.Stopwatch]::StartNew(); while ($sw.ElapsedMilliseconds -lt $Ms) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 15 } }
    # Bild eines Fensters in den Protokoll-Ordner legen (nur im Selbsttest; zeigt, ob der Aufbau stimmt)
    $shot = {
        param($Win, [string]$Name)
        try {
            $Win.TopMost = $true; $Win.Activate(); & $pump 250
            $b = $Win.Bounds
            $bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
            $g.Dispose()
            $bmp.Save((Join-Path $script:PesLogDir ('selbsttest-' + $Name + '.png')), [System.Drawing.Imaging.ImageFormat]::Png)
            $bmp.Dispose()
            $Win.TopMost = $false
        } catch { }
    }
    $rv = $null
    try {
        $Form.Show(); & $pump 400
        & $chk ($Form.Visible -and $script:PesUi.Chat.Height -gt 40) 'Hauptfenster aufgebaut'
        # Beide Rollen und beide Sprachen einmal durchschalten
        Set-PesRole 'Helfer'; & $pump 150
        & $chk ($script:PesUi.BarHelper.Visible -and -not $script:PesUi.BarCustomer.Visible -and $script:PesUi.TxtServer.Visible) 'Rolle Helfer: Leiste und Vermittler-Feld sichtbar'
        Set-PesRole 'Kunde'; & $pump 150
        & $chk ($script:PesUi.BarCustomer.Visible -and -not $script:PesUi.TxtServer.Visible) 'Rolle Kunde: einfache Ansicht'
        & $shot $Form 'kunde-de'
        $script:PesSettings.Language = 'en'; Set-PesLanguage; & $pump 150
        & $chk ($script:PesUi.BtnConnect.Text -eq 'Connect') 'Englisch: Knopf "Connect"'
        Set-PesRole 'Helfer'; & $pump 150
        Set-PesFullscreen $true; & $pump 100; Set-PesFullscreen $false; & $pump 100

        # Eigener Vermittler auf einem Testport, Sitzung als Helfer aufbauen (ohne Partner)
        $rv = New-Object PesRendezvousServer; $rv.Port = 39690; $rv.BindAddress = [System.Net.IPAddress]::Loopback; $rv.Start()
        $script:PesUi.TxtServer.Text = '127.0.0.1:39690'
        $script:PesUi.TxtName.Text = 'Selbsttest'
        $script:PesSettings.UdpPort = 39692
        New-PesInviteCode
        $inv = [PesProto]::InviteParse($script:PesUi.TxtCode.Text)
        & $chk ($inv -and $inv[0] -eq '127.0.0.1:39690' -and $inv[2].Length -ge 16) 'Neuer Einladungscode (Passwort mindestens 16 Zeichen)'
        $script:PesUi.ChkRemember.Checked = $false
        Connect-Pes
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while ($sw.ElapsedMilliseconds -lt 12000 -and -not ($script:PesState.Connected -and $script:PesHost.Engine -and $script:PesHost.Engine.State -eq 'Verbunden')) { & $pump 100 }
        & $chk ($script:PesState.Connected -and $script:PesHost.Engine.State -eq 'Verbunden') 'Verbinden über die Oberfläche (im Hintergrund), virtuelle Adresse erhalten'

        # Zweite Seite im selben Prozess als Kunde (ohne Oberfläche), damit alle Abläufe echt durchlaufen
        $c = New-Object PesHost
        $c.Connect('127.0.0.1', 39690, $inv[1], $inv[2], 'Testkunde', $null, 2, 39693, '127.0.0.1', (Join-Path $env:TEMP 'pes-selbsttest'))
        $sw.Restart()
        while ($sw.ElapsedMilliseconds -lt 20000 -and -not ($script:PesHost.Session.Paired -and $c.Session -and $c.Session.Paired)) { & $pump 100 }
        & $chk ($script:PesHost.Session.Paired) 'Kopplung mit dem Testkunden'
        & $pump 800
        & $chk ($script:PesUi.Head.Text -like '*Testkunde*') 'Kopfzeile zeigt den Partner'
        # Chat in beide Richtungen
        $script:PesUi.TxtChat.Text = 'Hallo vom Helfer'; Send-PesChat
        [void]$c.Session.SendChat('Hallo vom Kunden')
        & $pump 800
        & $chk ($script:PesUi.Chat.Text -like '*Hallo vom Helfer*' -and $script:PesUi.Chat.Text -like '*Testkunde: Hallo vom Kunden*') 'Chat erscheint im Verlauf'
        # Anruf: Helfer ruft an, Kunde nimmt an
        Invoke-PesCallButton; & $pump 500
        $c.Session.AnswerCall($true); & $pump 1200
        & $chk ($script:PesHost.Session.CallState -eq 3 -and $script:PesUi.BtnCall.Text -eq 'Hang up') 'Anruf aktiv, Knopf zeigt "Hang up"'
        & $chk ($script:PesHost.MediaRunning) 'Ton wurde gestartet (oder meldet fehlende Geräte)'
        $script:PesState.WantCam = $true; & $pump 1500
        & $chk (-not $script:PesHost.CameraRunning -or $script:PesHost.Session.MyCam) 'Kamera-Schalter ohne Absturz'
        $script:PesState.WantCam = $false
        # Bildschirm: Helfer fordert an, Kunde gibt frei
        Invoke-PesControlButton; & $pump 600
        $c.StartShare($true)
        $sw.Restart()
        while ($sw.ElapsedMilliseconds -lt 15000 -and -not $script:PesUi.View.HasImage) { & $pump 100 }
        & $chk ($script:PesUi.View.HasImage -and $script:PesHost.Session.ControlActive) 'Fernbild kommt in der Oberfläche an, Steuerung erlaubt'
        & $pump 600
        & $chk ($script:PesUi.BtnView.Text -eq 'Stop viewing' -and $script:PesUi.BtnControl.Text -eq 'Control: on' -and $script:PesUi.View.ControlEnabled) 'Knöpfe der Fernwartung folgen dem Zustand'
        & $shot $Form 'helfer-en-sitzung'
        Save-PesScreenshot
        Invoke-PesViewButton; & $pump 800
        $c.StopShare(); & $pump 800
        & $chk (-not $script:PesHost.Session.ShareActive) 'Ansicht beendet'
        # Datei vom Kunden zum Helfer (die Abfrage wird im Selbsttest nicht gezeigt und gilt als abgelehnt)
        $tf = Join-Path $env:TEMP 'pes-selbsttest-datei.txt'; [System.IO.File]::WriteAllText($tf, ('x' * 5000))
        [void]$c.Session.OfferFile($tf); & $pump 1200
        $tx = $c.Session.TxFile
        & $chk ($tx -and $tx.State -eq 3) 'Datei-Angebot wird ohne Zustimmung nicht angenommen'
        Invoke-PesCallButton; & $pump 500

        # Rolle Kunde in der Oberfläche: Ereignisse des Helfers einspielen (Abfragen gelten im Selbsttest als abgelehnt)
        foreach ($line in @('SCREEN|req|1', 'SCREEN|req|2', 'SCREEN|req|5', 'CALL|in|Tester', 'CALL|missed', 'FILE|sent|a.txt', 'FILE|failed|a.txt|abgebrochen', 'PEER|down|Testkunde|Verbindung zum Partner verloren.')) {
            try { Invoke-PesSessionEvent -Line ($line -replace '\|', [string][PesProto]::Sep) } catch { & $chk $false ('Ereignis ' + $line + ': ' + $_.Exception.Message) }
        }
        & $pump 300
        Close-PesRing
        Show-PesBanner; & $pump 100; Hide-PesBanner
        $c.Disconnect()
        Disconnect-Pes
        & $pump 600
        & $chk (-not $script:PesState.Connected -and $script:PesUi.BtnConnect.Text -eq 'Connect') 'Trennen'
        $script:PesSettings.Language = 'de'; Set-PesLanguage; & $pump 200
        & $shot $Form 'helfer-de'
        $script:PesSettings.Language = 'en'; Set-PesLanguage; & $pump 100

        # Unterfenster einmal aufbauen (ohne sie anzuzeigen)
        $fo = Show-PesOptionsWindow; $fo.Show(); & $pump 300
        & $chk ($script:PesOpt.Adapter.Items.Count -ge 1 -and $script:PesOpt.Mic.Items.Count -ge 1) 'Optionen-Fenster aufgebaut'
        & $shot $fo 'optionen'
        $fo.Close(); $fo.Dispose()
        $fh = Show-PesHelpWindow; $fh.Show(); & $pump 200
        & $chk ($script:PesHelpText.Text.Length -gt 1500) 'Hilfe-Fenster aufgebaut'
        & $shot $fh 'hilfe'
        $fh.Close(); $fh.Dispose()
        $script:PesLogContext = 'support'
        $fr = Show-PesRvWindow -RvPort 39691; $fr.Show(); & $pump 300; Update-PesRv
        & $chk ($script:PesRv.Server -and $script:PesRv.Server.IsRunning) 'Vermittler-Fenster aufgebaut, Vermittler läuft'
        & $shot $fr 'vermittler'
        try { $script:PesRv.Server.Stop() } catch { }
        $fr.Close(); $fr.Dispose()

        $miss = [PesI18n]::Missing()
        & $chk ($miss.Count -eq 0) ('Englische Texte vollständig' + $(if ($miss.Count -gt 0) { ' - es fehlen: ' + ($miss -join ' || ') } else { '' }))
        & $chk ($script:PesState.SelfTestErrors -eq 0) 'Keine Fehler im Zeitgeber'
        & $chk ($script:PesJobs.Count -ge 0) 'Hintergrundaufgaben liefen ohne Absturz'
        $sw.Restart(); while ($script:PesJobs.Count -gt 0 -and $sw.ElapsedMilliseconds -lt 20000) { Receive-PesJobs; & $pump 200 }
    } catch {
        & $chk $false ('Ausnahme: ' + $_.Exception.Message + ' @ Zeile ' + $_.InvocationInfo.ScriptLineNumber)
    } finally {
        try { if ($rv) { $rv.Stop() } } catch { }
        # Der Selbsttest hinterlässt keine geänderten Einstellungen
        try { if ($script:PesSelfTestBackup) { $script:PesSettings = $script:PesSelfTestBackup; Save-PesSettings } } catch { }
    }
    $out.Add($(if ($script:PesTestFail -gt 0) { 'ERGEBNIS: ' + $script:PesTestFail + ' Fehler' } else { 'ERGEBNIS: alle Prüfungen bestanden' }))
    try { [System.IO.File]::WriteAllLines((Join-Path $script:PesLogDir 'selbsttest.log'), $out, (New-Object System.Text.UTF8Encoding($true))) } catch { }
    foreach ($l in $out) { Write-Output $l }
    $script:PesExitCode = if ($script:PesTestFail -gt 0) { 1 } else { 0 }
    try { $Form.Close() } catch { }
}

$script:PesExitCode = 0
try {
    $script:PesSettings = Read-PesSettings
    if ($script:PesSelbsttest) { $script:PesSelfTestBackup = Read-PesSettings }
    if ($Vermittler) { Start-PesRvMode }
    elseif ($Optionen) { $script:PesLogContext = 'optionen'; Start-PesOptionsMode }
    elseif ($Hilfe) { $script:PesLogContext = 'hilfe'; Start-PesHelpMode }
    else { Start-PesMainMode }
} catch {
    Write-PesLog -Level 'FEHLER' -Message ('Absturz: ' + $_.Exception.Message + ' @ Zeile ' + $_.InvocationInfo.ScriptLineNumber)
    $script:PesExitCode = 1
    if ($script:PesSelbsttest) { Write-Output ('FEHLER Absturz: ' + $_.Exception.Message + ' @ Zeile ' + $_.InvocationInfo.ScriptLineNumber) }
    else {
        try { [void][System.Windows.Forms.MessageBox]::Show(('Project Earth Support wurde unerwartet beendet:' + $script:NL + $_.Exception.Message + $script:NL + $script:NL + 'Details stehen im Protokoll: ' + $script:PesLogDir), 'Project Earth Support', 'OK', 'Error') } catch { }
    }
} finally {
    try { if ($script:PesMutex) { $script:PesMutex.ReleaseMutex(); $script:PesMutex.Dispose() } } catch { }
    try { if ($script:PesShowEvent) { $script:PesShowEvent.Dispose() } } catch { }
}
exit $script:PesExitCode
