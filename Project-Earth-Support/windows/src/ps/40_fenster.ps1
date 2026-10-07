
# ==============================================================================
# 8b. OPTIONEN-FENSTER (eigener Prozess: -Optionen)
# ==============================================================================
function Show-PesOptionsWindow {
    $s = $script:PesSettings
    $f = New-PesForm -Title ($script:PesTitle + ' - ' + (T 'Optionen')) -W 600 -H 684
    $o = @{}
    $y = 14
    [void](New-PesLabel -Text 'Allgemein' -X 16 -Y $y -W 300 -H 22 -Kind 'head' -Parent $f); $y += 28
    [void](New-PesLabel -Text 'Mein Name' -X 16 -Y ($y + 3) -W 170 -Parent $f)
    $o.Name = New-PesText -X 190 -Y $y -W 390 -Parent $f; $o.Name.MaxLength = 32; $o.Name.Text = [string]$s.Name; $y += 32
    [void](New-PesLabel -Text 'Sprache' -X 16 -Y ($y + 3) -W 170 -Parent $f)
    $o.Lang = New-PesCombo -X 190 -Y $y -W 200 -Parent $f
    [void]$o.Lang.Items.Add('Deutsch'); [void]$o.Lang.Items.Add('English')
    $o.Lang.SelectedIndex = if ($s.Language -eq 'en') { 1 } else { 0 }; $y += 32
    [void](New-PesLabel -Text 'Empfangene Dateien' -X 16 -Y ($y + 3) -W 170 -Parent $f)
    $o.Dir = New-PesText -X 190 -Y $y -W 300 -Parent $f; $o.Dir.Text = [string]$s.DownloadDir
    $bDir = New-PesButton -Text 'Wählen' -X 498 -Y ($y - 1) -W 82 -H 26 -Parent $f; $y += 32
    $o.Tray = New-PesCheck -Text 'Beim Minimieren in den Infobereich (neben der Uhr) legen' -X 16 -Y $y -W 560 -Parent $f; $o.Tray.Checked = [bool]$s.MinimizeToTray; $y += 26
    $o.Auto = New-PesCheck -Text 'Mit Windows starten (bleibt im Infobereich, verbindet nicht von selbst)' -X 16 -Y $y -W 560 -Parent $f; $o.Auto.Checked = (Test-PesAutostart); $y += 34

    [void](New-PesLabel -Text 'Netzwerk' -X 16 -Y $y -W 300 -H 22 -Kind 'head' -Parent $f); $y += 28
    [void](New-PesLabel -Text 'Netzwerkadapter' -X 16 -Y ($y + 3) -W 170 -Parent $f)
    $o.Adapter = New-PesCombo -X 190 -Y $y -W 390 -Parent $f
    [void]$o.Adapter.Items.Add((T 'Automatisch (empfohlen)'))
    $o.AdapterNames = New-Object System.Collections.ArrayList
    [void]$o.AdapterNames.Add('')
    $sel = 0
    foreach ($a in (Get-PesAdapterList)) {
        [void]$o.Adapter.Items.Add($a.Text); [void]$o.AdapterNames.Add($a.Name)
        if ($a.Name -eq [string]$s.AdapterName) { $sel = $o.Adapter.Items.Count - 1 }
    }
    $o.Adapter.SelectedIndex = $sel; $y += 32
    [void](New-PesLabel -Text 'UDP-Port (Standard 9892)' -X 16 -Y ($y + 3) -W 170 -Parent $f)
    $o.Udp = New-PesText -X 190 -Y $y -W 90 -Parent $f; $o.Udp.Text = [string]$s.UdpPort; $o.Udp.MaxLength = 5
    $bStd = New-PesButton -Text 'Standard' -X 288 -Y ($y - 1) -W 100 -H 26 -Parent $f
    $bRnd = New-PesButton -Text 'Zufallsport' -X 396 -Y ($y - 1) -W 110 -H 26 -Parent $f; $y += 34

    [void](New-PesLabel -Text 'Ton und Kamera' -X 16 -Y $y -W 300 -H 22 -Kind 'head' -Parent $f); $y += 28
    $std = T 'Standardgerät (Windows)'
    [void](New-PesLabel -Text 'Mikrofon' -X 16 -Y ($y + 3) -W 170 -Parent $f)
    $o.Mic = New-PesCombo -X 190 -Y $y -W 390 -Parent $f; [void]$o.Mic.Items.Add($std)
    foreach ($n in [PesWinmm]::InputDeviceNames()) { [void]$o.Mic.Items.Add($n) }
    $o.Mic.SelectedIndex = [Math]::Max(0, $o.Mic.Items.IndexOf([string]$s.MicDevice)); $y += 32
    [void](New-PesLabel -Text 'Lautsprecher' -X 16 -Y ($y + 3) -W 170 -Parent $f)
    $o.Spk = New-PesCombo -X 190 -Y $y -W 390 -Parent $f; [void]$o.Spk.Items.Add($std)
    foreach ($n in [PesWinmm]::OutputDeviceNames()) { [void]$o.Spk.Items.Add($n) }
    $o.Spk.SelectedIndex = [Math]::Max(0, $o.Spk.Items.IndexOf([string]$s.SpeakerDevice)); $y += 32
    [void](New-PesLabel -Text 'Kamera' -X 16 -Y ($y + 3) -W 170 -Parent $f)
    $o.Cam = New-PesCombo -X 190 -Y $y -W 390 -Parent $f; [void]$o.Cam.Items.Add((T 'Erste Kamera'))
    foreach ($n in [PesCamera]::Devices()) { [void]$o.Cam.Items.Add($n) }
    $o.Cam.SelectedIndex = [Math]::Max(0, $o.Cam.Items.IndexOf([string]$s.Camera)); $y += 32
    $o.Flip = New-PesCheck -Text 'Kamerabild steht auf dem Kopf: umdrehen' -X 16 -Y $y -W 560 -Parent $f; $o.Flip.Checked = [bool]$s.CameraFlip; $y += 26
    $o.Echo = New-PesCheck -Text 'Echo-Sperre: Mikrofon stumm, solange der Partner spricht (ohne Kopfhörer empfohlen)' -X 16 -Y $y -W 570 -Parent $f; $o.Echo.Checked = [bool]$s.EchoGate; $y += 34

    [void](New-PesLabel -Text 'Eigener Mini-Vermittler (nur für Helfer)' -X 16 -Y $y -W 400 -H 22 -Kind 'head' -Parent $f); $y += 28
    [void](New-PesLabel -Text 'UDP-Port (Standard 9890)' -X 16 -Y ($y + 3) -W 170 -Parent $f)
    $o.RvPort = New-PesText -X 190 -Y $y -W 90 -Parent $f; $o.RvPort.Text = [string]$s.RvPort; $o.RvPort.MaxLength = 5; $y += 32
    [void](New-PesLabel -Text 'Die öffentliche Adresse (DynDNS-Name) wird im Fenster des Vermittlers eingetragen - je Port getrennt.' -X 190 -Y $y -W 390 -H 32 -Kind 'muted' -Parent $f); $y += 36
    $o.RvAuto = New-PesCheck -Text 'Vermittler zusammen mit dem Autostart starten' -X 16 -Y $y -W 560 -Parent $f; $o.RvAuto.Checked = [bool]$s.RvAutostart; $y += 36

    $o.Msg = New-PesLabel -Text '' -X 16 -Y ($y + 2) -W 568 -H 34 -Kind 'muted' -Parent $f; $y += 40
    $bFw = New-PesButton -Text 'Firewall-Regeln entfernen' -X 16 -Y $y -W 190 -H 32 -Parent $f
    $bClean = New-PesButton -Text 'Alles entfernen ...' -X 214 -Y $y -W 150 -H 32 -Kind 'danger' -Parent $f
    $bSave = New-PesButton -Text 'Speichern' -X 372 -Y $y -W 104 -H 32 -Kind 'accent' -Parent $f
    $bClose = New-PesButton -Text 'Schließen' -X 484 -Y $y -W 100 -H 32 -Parent $f
    $script:PesOpt = $o
    $script:PesOptForm = $f

    $bDir.Add_Click({
        $d = New-Object System.Windows.Forms.FolderBrowserDialog
        try { $d.SelectedPath = $script:PesOpt.Dir.Text; if ($d.ShowDialog($script:PesOptForm) -eq 'OK') { $script:PesOpt.Dir.Text = $d.SelectedPath } } finally { $d.Dispose() }
    })
    $bStd.Add_Click({ $script:PesOpt.Udp.Text = [string]$script:PesDefaultUdpPort })
    $bRnd.Add_Click({ $script:PesOpt.Udp.Text = [string](Get-Random -Minimum 20000 -Maximum 60000) })
    $bFw.Add_Click({
        $script:PesOpt.Msg.Text = T 'Firewall-Regeln werden entfernt ...'
        Start-PesJob -Name 'Firewall-Regeln entfernen' -Script $script:PesFirewallRemoveScript -Arguments @($script:PesFirewallPrefix) -OnDone { param($r) $script:PesOpt.Msg.Text = (T 'Firewall-Regeln "Project Earth Support ...":') + ' ' + [PesI18n]::Core($r) }
    })
    $bClean.Add_Click({
        $r = Show-PesAsk -Title (T 'Alles entfernen') -Text ((T 'Entfernt den Autostart, alle Firewall-Regeln "Project Earth Support ..." und den Ordner mit Einstellungen und Protokollen.') + $script:NL + $script:NL + (T 'Empfangene Dateien und das Programm selbst bleiben erhalten.')) -Buttons @((T 'Entfernen'), (T 'Zurück')) -Accent 1 -Danger 0 -Owner $script:PesOptForm
        if ($r -ne 0) { return }
        $script:PesOptCleanup = $true
        Start-PesJob -Name 'Autostart entfernen' -Script $script:PesTaskScript -Arguments @($false, $script:PesTaskName, '', '')
        Start-PesJob -Name 'Firewall-Regeln entfernen' -Script $script:PesFirewallRemoveScript -Arguments @($script:PesFirewallPrefix) -OnDone {
            param($r)
            try { if ([System.IO.Directory]::Exists($script:PesDataDir)) { [System.IO.Directory]::Delete($script:PesDataDir, $true) } } catch { }
            $script:PesOptForm.Close()
        }
        $script:PesOpt.Msg.Text = T 'Wird entfernt ...'
    })
    $bSave.Add_Click({ if (Save-PesOptions) { $script:PesOpt.Msg.ForeColor = $script:C.OkText; $script:PesOpt.Msg.Text = T 'Gespeichert. Die Änderungen gelten ab dem nächsten Verbinden.' } })
    $bClose.Add_Click({ $script:PesOptForm.Close() })
    return $f
}

function Save-PesOptions {
    $o = $script:PesOpt
    $s = $script:PesSettings
    $udp = 0; $rvp = 0
    if (-not [int]::TryParse($o.Udp.Text.Trim(), [ref]$udp) -or $udp -lt 1024 -or $udp -gt 65535) { $o.Msg.ForeColor = $script:C.Err; $o.Msg.Text = T 'Der UDP-Port muss zwischen 1024 und 65535 liegen.'; return $false }
    if (-not [int]::TryParse($o.RvPort.Text.Trim(), [ref]$rvp) -or $rvp -lt 1024 -or $rvp -gt 65535) { $o.Msg.ForeColor = $script:C.Err; $o.Msg.Text = T 'Der Vermittler-Port muss zwischen 1024 und 65535 liegen.'; return $false }
    if ($udp -eq $rvp) { $o.Msg.ForeColor = $script:C.Err; $o.Msg.Text = T 'Der UDP-Port und der Vermittler-Port müssen verschieden sein.'; return $false }
    $name = $o.Name.Text.Trim()
    if (-not $name) { $o.Msg.ForeColor = $script:C.Err; $o.Msg.Text = T 'Bitte einen Namen eintragen.'; return $false }
    $s.Name = $name
    $s.Language = if ($o.Lang.SelectedIndex -eq 1) { 'en' } else { 'de' }
    if ($o.Dir.Text.Trim()) { $s.DownloadDir = $o.Dir.Text.Trim() }
    $s.MinimizeToTray = [bool]$o.Tray.Checked
    $s.AdapterName = [string]$o.AdapterNames[[Math]::Max(0, $o.Adapter.SelectedIndex)]
    $s.UdpPort = $udp
    $s.MicDevice = if ($o.Mic.SelectedIndex -gt 0) { [string]$o.Mic.SelectedItem } else { '' }
    $s.SpeakerDevice = if ($o.Spk.SelectedIndex -gt 0) { [string]$o.Spk.SelectedItem } else { '' }
    $s.Camera = if ($o.Cam.SelectedIndex -gt 0) { [string]$o.Cam.SelectedItem } else { '' }
    $s.CameraFlip = [bool]$o.Flip.Checked
    $s.EchoGate = [bool]$o.Echo.Checked
    $s.RvPort = $rvp
    $s.RvAutostart = [bool]$o.RvAuto.Checked
    # Rolle und Einladungscode gehören dem Hauptfenster: aus der Datei übernehmen, nicht überschreiben
    $cur = Read-PesSettings
    $s.Role = $cur.Role; $s.InviteEnc = $cur.InviteEnc; $s.RememberInvite = $cur.RememberInvite; $s.ServerAddress = $cur.ServerAddress; $s.Quality = $cur.Quality
    Save-PesSettings
    [PesI18n]::Lang = $s.Language
    [PesI18n]::ApplyAll()
    # Autostart: geplante Aufgabe anlegen oder entfernen (im Hintergrund)
    if ($script:IsCompiledExe) { $exe = $script:SelfPath; $arg = '-Autostart' }
    else { $exe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'; $arg = '-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "' + $script:SelfPath + '" -Autostart' }
    Start-PesJob -Name 'Autostart' -Script $script:PesTaskScript -Arguments @([bool]$o.Auto.Checked, $script:PesTaskName, $exe, $arg) -OnDone {
        param($r)
        if ($r -like 'Fehler*') { $script:PesOpt.Msg.ForeColor = $script:C.Err; $script:PesOpt.Msg.Text = (T 'Autostart:') + ' ' + $r }
    }
    return $true
}

# ==============================================================================
# 8c. MINI-VERMITTLER (eigener Prozess: -Vermittler [-Port n]; pro Port eine Instanz)
# ==============================================================================
function Get-PesRvConfigPath {
    param([int]$RvPort)
    return (Join-Path $script:PesDataDir ('vermittler_' + $RvPort + '.json'))
}

# Pro Port eine eigene Konfiguration (oeffentliche Adresse dieses Vermittlers)
function Read-PesRvConfig {
    param([int]$RvPort)
    $c = @{ PublicAddress = '' }
    try {
        $p = Get-PesRvConfigPath $RvPort
        if ([System.IO.File]::Exists($p)) {
            $j = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            if ($j.PublicAddress) { $c.PublicAddress = [string]$j.PublicAddress }
        }
    } catch { }
    return $c
}

function Update-PesRvAddresses {
    $r = $script:PesRv
    $suffix = if ($r.Port -eq $script:PesDefaultRvPort) { '' } else { ':' + $r.Port }
    $r.Addr.Items.Clear()
    $pub = [string]$r.Config.PublicAddress
    if ($pub) { [void]$r.Addr.Items.Add($pub + $suffix) }
    foreach ($a in (Get-PesAdapterList)) { [void]$r.Addr.Items.Add($a.Ip + $suffix) }
    if ($r.Addr.Items.Count -gt 0) { $r.Addr.SelectedIndex = 0 }
    if ($r.Server) { $r.Server.PublicIp = $null }
    if ($pub -and $r.Server) {
        # Mitglieder aus dem eigenen Heimnetz werden mit der öffentlichen Adresse angekündigt
        Start-PesJob -Name 'Öffentliche Adresse auflösen' -Script {
            param([string]$HostName)
            try { foreach ($a in [System.Net.Dns]::GetHostAddresses($HostName)) { if ($a.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) { return $a.ToString() } } } catch { }
            return ''
        } -Arguments @($pub) -OnDone {
            param($ip)
            $a = $null
            if ($ip -and [System.Net.IPAddress]::TryParse($ip, [ref]$a) -and $script:PesRv.Server) {
                $b = $a.GetAddressBytes()
                $private = ($b[0] -eq 10) -or ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or ($b[0] -eq 192 -and $b[1] -eq 168) -or ($b[0] -eq 127)
                if (-not $private) { $script:PesRv.Server.PublicIp = $a }
            }
        }
    }
}

function Show-PesRvWindow {
    param([int]$RvPort)
    $f = New-PesForm -Title ($script:PesTitle + ' - ' + (T 'Vermittler') + ' (UDP ' + $RvPort + ')') -W 620 -H 520
    $r = @{ Port = $RvPort; Tick = 0; Config = (Read-PesRvConfig $RvPort) }
    $r.Status = New-PesLabel -Text '' -X 16 -Y 14 -W 588 -H 24 -Parent $f
    $r.Status.Font = $script:FontBold
    [void](New-PesLabel -Text 'Diese Adresse trägt der Helfer als "Vermittler-Adresse" ein:' -X 16 -Y 46 -W 588 -H 20 -Parent $f)
    $r.Addr = New-PesCombo -X 16 -Y 70 -W 440 -Parent $f
    $bCopy = New-PesButton -Text 'Adresse kopieren' -X 464 -Y 68 -W 140 -H 28 -Parent $f
    [void](New-PesLabel -Text 'Im selben Netz (LAN/WLAN) reicht die Adresse dieses PCs. Für Kunden im Internet: im Router den UDP-Port an diesen PC weiterleiten und hier die öffentliche Adresse (DynDNS-Name oder feste IP) eintragen.' -X 16 -Y 104 -W 588 -H 52 -Kind 'muted' -Parent $f)
    [void](New-PesLabel -Text 'Öffentliche Adresse' -X 16 -Y 163 -W 150 -Parent $f)
    $r.Pub = New-PesText -X 170 -Y 160 -W 286 -Parent $f
    $r.Pub.Text = [string]$r.Config.PublicAddress
    $bPub = New-PesButton -Text 'Übernehmen' -X 464 -Y 159 -W 140 -H 26 -Parent $f
    $r.Stats = New-PesLabel -Text '' -X 16 -Y 198 -W 588 -H 20 -Kind 'ok' -Parent $f
    $log = New-Object System.Windows.Forms.TextBox
    $log.Multiline = $true; $log.ReadOnly = $true; $log.ScrollBars = 'Vertical'; $log.BorderStyle = 'FixedSingle'
    $log.BackColor = $script:C.Field; $log.ForeColor = $script:C.Muted; $log.Font = $script:FontMono
    $log.Location = New-Object System.Drawing.Point(16, 226); $log.Size = New-Object System.Drawing.Size(588, 236)
    $f.Controls.Add($log); $r.Log = $log
    $bHide = New-PesButton -Text 'In den Infobereich' -X 300 -Y 474 -W 150 -H 32 -Parent $f
    $bEnd = New-PesButton -Text 'Vermittler beenden' -X 458 -Y 474 -W 146 -H 32 -Kind 'danger' -Parent $f
    $script:PesRv = $r
    $script:PesRvForm = $f

    try {
        $srv = New-Object PesRendezvousServer
        $srv.Port = $RvPort
        $srv.Start()
        $r.Server = $srv
        $r.Status.Text = T 'Der Vermittler läuft auf UDP-Port {0}.' $RvPort
        $r.Status.ForeColor = $script:C.OkText
        Add-PesFirewallRule -Service 'Vermittler' -UdpPort $RvPort
    } catch {
        $r.Status.Text = (T 'Der Vermittler konnte nicht starten (Port {0} belegt?):' $RvPort) + ' ' + $_.Exception.Message
        $r.Status.ForeColor = $script:C.Err
        Write-PesLog -Level 'FEHLER' -Message ('Vermittler: ' + $_.Exception.Message)
    }
    Update-PesRvAddresses

    $bCopy.Add_Click({ try { if ($script:PesRv.Addr.SelectedItem) { [System.Windows.Forms.Clipboard]::SetText([string]$script:PesRv.Addr.SelectedItem) } } catch { } })
    $bPub.Add_Click({
        $r = $script:PesRv
        $pub = $r.Pub.Text.Trim()
        $h = $null; $p = 0
        if ($pub -and (-not [PesProto]::ParseServer($pub, $r.Port, [ref]$h, [ref]$p) -or $pub.Contains(':'))) {
            Show-PesInfo -Text (T 'Die öffentliche Adresse ist ungültig (nur Name oder IP, ohne Port).') -Owner $script:PesRvForm
            return
        }
        $r.Config.PublicAddress = $pub
        try { Write-PesTextFileAtomic -Path (Get-PesRvConfigPath $r.Port) -Text (@{ PublicAddress = $pub } | ConvertTo-Json) } catch { Write-PesLog -Level 'FEHLER' -Message ('Vermittler-Konfiguration: ' + $_.Exception.Message) }
        Update-PesRvAddresses
    })
    $bHide.Add_Click({ $script:PesRvForm.Hide() })
    $bEnd.Add_Click({ $script:PesRvForm.Close() })
    $f.Add_FormClosing({
        if ($script:PesRv.Server -and $script:PesRv.Server.MemberCount -gt 0 -and -not $script:PesSelbsttest -and -not $script:PesRv.Confirmed) {
            $q = Show-PesAsk -Title $script:PesTitle -Text (T 'Über diesen Vermittler laufen gerade Sitzungen. Wirklich beenden?') -Buttons @((T 'Beenden'), (T 'Zurück')) -Accent 1 -Danger 0 -Owner $this
            if ($q -ne 0) { $_.Cancel = $true; return }
            $script:PesRv.Confirmed = $true
        }
    })
    return $f
}

function Update-PesRv {
    $r = $script:PesRv
    Receive-PesJobs
    $r.Tick++
    $srv = $r.Server
    if ($srv) {
        $line = $null
        $n = 0
        while ($n -lt 40 -and $srv.Log.TryDequeue([ref]$line)) {
            $n++
            Write-PesLog -Level 'RV' -Message $line
            try {
                if ($r.Log.TextLength -gt 60000) { $r.Log.Text = $r.Log.Text.Substring(30000) }
                $r.Log.AppendText($line + $script:NL)
            } catch { }
        }
        if (($r.Tick % 5) -eq 0) { $t = T 'Teilnehmer: {0}   weitergeleitete Pakete: {1}' $srv.MemberCount $srv.RelayedPackets; if ($r.Stats.Text -ne $t) { $r.Stats.Text = $t } }
    }
    if ($script:PesShowEvent -and $script:PesShowEvent.WaitOne(0)) { try { $script:PesRvForm.Show(); $script:PesRvForm.Activate() } catch { } }
}

# ==============================================================================
# 8d. HILFE (eigener Prozess: -Hilfe)
# ==============================================================================
$script:PesHelpDe = @'
PROJECT EARTH SUPPORT - ANLEITUNG

WOZU
Ein Helfer hilft einem Kunden live am PC. Oben läuft der Video-Chat mit Ton, unten die
Fernwartung (Bildschirm des Kunden, auf Wunsch mit Maus und Tastatur). Dazu gibt es
Textchat und Datei-Übertragung. Der Helfer nutzt dieses Programm oder die Android-App
"Project Earth Support", der Kunde dieses Programm.

SO GEHT ES - HELFER
1. Rechts "Ich helfe" wählen und den eigenen Namen eintragen.
2. Bei "Vermittler-Adresse" die Adresse des Vermittlers eintragen (eigener Server,
   DynDNS-Name oder die Adresse des PCs, auf dem der Vermittler läuft).
   Kein Server vorhanden? Unten auf "Vermittler" klicken: Dann läuft er auf diesem PC.
3. "Neuer Code" klicken, mit "Kopieren" in die Zwischenablage legen und dem Kunden
   schicken (Messenger, E-Mail). Der Code enthält Adresse, Sitzung und Passwort.
4. "Verbinden" klicken und warten, bis der Kunde da ist.
5. "Anrufen" startet den Video-Chat. "Bildschirm anfordern" bittet den Kunden um die
   Freigabe, "Steuerung anfordern" zusätzlich um Maus und Tastatur.

SO GEHT ES - KUNDE
1. Programm starten, "Ich brauche Hilfe" ist schon gewählt.
2. Den Einladungscode des Helfers einfügen ("Einfügen") und "Verbinden" klicken.
3. Ruft der Helfer an: "Annehmen".
4. Fragt der Helfer nach dem Bildschirm, erscheint eine Abfrage. Erst nach Ihrer
   Zustimmung wird übertragen. Oben am Bildschirm steht dann ein roter Hinweis.
5. Beenden: Knopf "Beenden" im roten Hinweis, "Freigabe beenden" im Fenster oder
   jederzeit die Tasten Strg+Umschalt+F12.

FERNWARTUNG FÜR DEN HELFER
- In das Bild klicken: Maus und Tastatur gehen an den PC des Kunden (blauer Rahmen).
- "Tasten" sendet Tastenfolgen, die Windows sonst selbst abfängt (Task-Manager,
  Windows-Taste, Alt+Tab ...). Strg+Alt+Entf lässt Windows aus der Ferne nicht zu.
- "Sparsam / Normal / Scharf" stellt Bildgröße und Qualität ein (langsame Leitung:
  Sparsam). Bei mehreren Bildschirmen wählst du den Bildschirm aus.
- "Foto" speichert das aktuelle Bild, "Großansicht" (F11) blendet alles andere aus.
- Während einer Windows-Sicherheitsabfrage (UAC) oder am Sperrbildschirm gibt es kein
  Bild. Der Kunde muss solche Abfragen selbst bestätigen.

VERMITTLER
Der Vermittler bringt beide Seiten zusammen (wie beim Project Earth LAN Manager: gleiche
Technik, aber eine eigene, unabhängige Sitzung). Danach läuft die Verbindung möglichst
direkt zwischen beiden PCs; nur wenn das nicht geht, leitet der Vermittler die
verschlüsselten Pakete weiter. Er sieht nie Passwörter oder Inhalte.
- Im selben Netz genügt die Adresse des PCs, auf dem der Vermittler läuft.
- Für Kunden im Internet: im Router den UDP-Port 9890 an diesen PC weiterleiten und
  im Fenster des Vermittlers die öffentliche Adresse (DynDNS-Name) eintragen.
- Ein vorhandener Project-Earth-LAN-Rendezvous-Server kann ebenfalls eingetragen werden
  (Adresse:Port). Nötig ist das nicht.

SICHERHEIT UND DATENSCHUTZ
- Alles ist Ende-zu-Ende verschlüsselt (AES-256 + HMAC-SHA256). Der Schlüssel entsteht
  aus dem Passwort im Einladungscode. Wer den Code hat, kann der Sitzung beitreten -
  also nur an die richtige Person schicken. Für jede Sitzung einen neuen Code erzeugen.
- Der Bildschirm wird nur nach Zustimmung übertragen, die Steuerung nur nach einer
  zweiten Zustimmung. Es gibt keinen Zugriff ohne anwesenden Kunden.
- Dateien werden nur nach Zustimmung angenommen und mit SHA-256 geprüft.
- Das Programm lädt nichts nach und aktualisiert sich nicht selbst.
- Der Einladungscode wird nur verschlüsselt gespeichert (Windows DPAPI) und nur, wenn
  "merken" angehakt ist. Im Protokoll stehen nie Codes oder Passwörter.

DATEIEN UND PORTS
- Einstellungen und Protokolle: C:\ProgramData\Project-Earth-Support
- Empfangene Dateien: Downloads\Project Earth Support (änderbar unter Optionen)
- UDP 9892: eigene Verbindung (änderbar), Firewall-Regel "Project Earth Support (UDP 9892)"
- UDP 9890: Vermittler (nur wenn gestartet), Regel "Project Earth Support Vermittler (UDP 9890)"
- Autostart: geplante Aufgabe "Project Earth Support Autostart" (nur wenn eingeschaltet)
- Alles wieder entfernen: Optionen -> "Alles entfernen ..."

WENN ETWAS NICHT KLAPPT
- "Verbinde mit Vermittlungsserver ..." bleibt stehen: Adresse im Code falsch, Vermittler
  läuft nicht oder der UDP-Port ist im Router nicht weitergeleitet.
- Kein Ton: unter Optionen Mikrofon und Lautsprecher wählen. Echo? Kopfhörer benutzen
  oder die Echo-Sperre eingeschaltet lassen.
- Kein Kamerabild: Kamera unter Optionen wählen; ein anderes Programm darf sie nicht
  gerade benutzen.
- Ruckelt das Bild: "Sparsam" wählen.
'@

$script:PesHelpEn = @'
PROJECT EARTH SUPPORT - GUIDE

PURPOSE
A helper assists a customer live at the PC. The video chat with sound is at the top,
remote support (the customer's screen, optionally with mouse and keyboard) at the bottom.
Text chat and file transfer are included. The helper uses this program or the Android app
"Project Earth Support", the customer uses this program.

HOW TO - HELPER
1. Choose "I am helping" on the right and enter your name.
2. Enter the address of the mediator under "Mediator address" (your own server, a DynDNS
   name or the address of the PC running the mediator).
   No server? Click "Mediator" at the bottom: it then runs on this PC.
3. Click "New code", put it on the clipboard with "Copy" and send it to the customer
   (messenger, e-mail). The code contains address, session and password.
4. Click "Connect" and wait for the customer.
5. "Call" starts the video chat. "Request screen" asks the customer to share the screen,
   "Request control" additionally asks for mouse and keyboard.

HOW TO - CUSTOMER
1. Start the program, "I need help" is already selected.
2. Paste the helper's invitation code ("Paste") and click "Connect".
3. When the helper calls: "Accept".
4. When the helper asks for the screen, a prompt appears. Nothing is transmitted before you
   agree. A red notice is then shown at the top of the screen.
5. To stop: the "Stop" button in the red notice, "Stop sharing" in the window, or at any
   time the keys Ctrl+Shift+F12.

REMOTE SUPPORT FOR THE HELPER
- Click into the picture: mouse and keyboard go to the customer's PC (blue frame).
- "Keys" sends key combinations that Windows would otherwise catch itself (Task Manager,
  Windows key, Alt+Tab ...). Windows does not allow Ctrl+Alt+Del remotely.
- "Economy / Normal / Sharp" sets picture size and quality (slow line: Economy). With
  several screens you choose the screen.
- "Photo" saves the current picture, "Large view" (F11) hides everything else.
- During a Windows security prompt (UAC) or on the lock screen there is no picture. The
  customer has to confirm such prompts personally.

MEDIATOR
The mediator brings both sides together (same technology as the Project Earth LAN Manager,
but an independent session of its own). After that the connection runs directly between
both PCs whenever possible; only if that fails the mediator forwards the encrypted packets.
It never sees passwords or content.
- In the same network the address of the PC running the mediator is enough.
- For customers on the internet: forward UDP port 9890 to this PC in the router and enter
  the public address (DynDNS name) in the mediator window.
- An existing Project Earth LAN rendezvous server can be entered as well (address:port).
  It is not required.

SECURITY AND PRIVACY
- Everything is end-to-end encrypted (AES-256 + HMAC-SHA256). The key is derived from the
  password in the invitation code. Whoever has the code can join the session - so send it
  only to the right person. Create a new code for every session.
- The screen is only transmitted after consent, control only after a second consent. There
  is no access without the customer being present.
- Files are only accepted after consent and are verified with SHA-256.
- The program downloads nothing and never updates itself.
- The invitation code is only stored encrypted (Windows DPAPI) and only if "remember" is
  ticked. Codes or passwords never appear in the log.

FILES AND PORTS
- Settings and logs: C:\ProgramData\Project-Earth-Support
- Received files: Downloads\Project Earth Support (can be changed under Options)
- UDP 9892: own connection (changeable), firewall rule "Project Earth Support (UDP 9892)"
- UDP 9890: mediator (only when started), rule "Project Earth Support Vermittler (UDP 9890)"
- Autostart: scheduled task "Project Earth Support Autostart" (only when enabled)
- Remove everything again: Options -> "Remove everything ..."

IF SOMETHING DOES NOT WORK
- "Verbinde mit Vermittlungsserver ..." stays: wrong address in the code, the mediator is not
  running or the UDP port is not forwarded in the router.
- No sound: choose microphone and speaker under Options. Echo? Use headphones or keep the
  echo lock switched on.
- No camera picture: choose the camera under Options; no other program may be using it.
- Picture stutters: choose "Economy".
'@

function Show-PesHelpWindow {
    $f = New-PesForm -Title ($script:PesTitle + ' - ' + (T 'Anleitung und Hilfe')) -W 780 -H 640 -Sizable $true
    $f.MinimumSize = New-Object System.Drawing.Size(560, 400)
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Multiline = $true; $tb.ReadOnly = $true; $tb.ScrollBars = 'Vertical'; $tb.BorderStyle = 'None'; $tb.WordWrap = $true
    $tb.BackColor = $script:C.Field; $tb.ForeColor = $script:C.Text; $tb.Font = New-Object System.Drawing.Font('Consolas', 10)
    $tb.Location = New-Object System.Drawing.Point(12, 12); $tb.Size = New-Object System.Drawing.Size(756, 572)
    $tb.Anchor = 'Top,Bottom,Left,Right'
    $text = if ($script:PesSettings.Language -eq 'en') { $script:PesHelpEn } else { $script:PesHelpDe }
    $tb.Text = ($text -replace "\r?\n", $script:NL)
    $tb.SelectionStart = 0; $tb.SelectionLength = 0
    $f.Controls.Add($tb)
    $bSave = New-PesButton -Text 'Auf den Desktop speichern' -X 12 -Y 596 -W 220 -H 32 -Parent $f
    $bLog = New-PesButton -Text 'Protokoll-Ordner öffnen' -X 240 -Y 596 -W 200 -H 32 -Parent $f
    $bClose = New-PesButton -Text 'Schließen' -X 668 -Y 596 -W 100 -H 32 -Parent $f
    $bSave.Anchor = 'Bottom,Left'; $bLog.Anchor = 'Bottom,Left'; $bClose.Anchor = 'Bottom,Right'
    $script:PesHelpForm = $f
    $script:PesHelpText = $tb
    $bSave.Add_Click({
        try {
            $p = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Project Earth Support - Anleitung.txt'
            [System.IO.File]::WriteAllText($p, $script:PesHelpText.Text, (New-Object System.Text.UTF8Encoding($true)))
            $this.Text = T 'Gespeichert'
        } catch { $this.Text = T 'Speichern fehlgeschlagen' }
    })
    $bLog.Add_Click({ try { if (-not [System.IO.Directory]::Exists($script:PesLogDir)) { [void][System.IO.Directory]::CreateDirectory($script:PesLogDir) }; [void][System.Diagnostics.Process]::Start($script:PesLogDir) } catch { } })
    $bClose.Add_Click({ $script:PesHelpForm.Close() })
    return $f
}
