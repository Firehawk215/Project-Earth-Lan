
# ==============================================================================
# 8. OBERFLÄCHE: Fabrik-Funktionen (Dark Theme, flache Buttons)
# ==============================================================================
function New-PesForm {
    param([string]$Title, [int]$W, [int]$H, [bool]$Sizable = $false)
    $f = New-Object System.Windows.Forms.Form
    $f.Text = $Title
    $f.ClientSize = New-Object System.Drawing.Size($W, $H)
    $f.StartPosition = 'CenterScreen'
    $f.BackColor = $script:C.Bg
    $f.ForeColor = $script:C.Text
    $f.Font = $script:FontUi
    if (-not $Sizable) { $f.FormBorderStyle = 'FixedSingle'; $f.MaximizeBox = $false }
    if ($script:PesIcon) { $f.Icon = $script:PesIcon }
    return $f
}

# Kind: normal | accent | ok | danger
function New-PesButton {
    param([string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H = 32, [string]$Kind = 'normal', $Parent = $null)
    $b = New-Object System.Windows.Forms.Button
    $b.Location = New-Object System.Drawing.Point($X, $Y)
    $b.Size = New-Object System.Drawing.Size($W, $H)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderColor = $script:C.Border
    $b.ForeColor = $script:C.Text
    $b.Font = $script:FontUi
    $b.UseVisualStyleBackColor = $false
    Set-PesButtonKind -Button $b -Kind $Kind
    if ($Text) { [PesI18n]::Reg($b, $Text) }
    if ($Parent) { $Parent.Controls.Add($b) }
    return $b
}

function Set-PesButtonKind {
    param($Button, [string]$Kind)
    switch ($Kind) {
        'accent' { $Button.BackColor = $script:C.Accent }
        'ok'     { $Button.BackColor = $script:C.Ok }
        'danger' { $Button.BackColor = $script:C.Danger }
        default  { $Button.BackColor = $script:C.Surface }
    }
}

# Kind: normal | muted | head | ok | err | warn
function New-PesLabel {
    param([string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H = 20, [string]$Kind = 'normal', $Parent = $null)
    $l = New-Object System.Windows.Forms.Label
    $l.Location = New-Object System.Drawing.Point($X, $Y)
    $l.Size = New-Object System.Drawing.Size($W, $H)
    $l.BackColor = [System.Drawing.Color]::Transparent
    $l.Font = $script:FontUi
    switch ($Kind) {
        'muted' { $l.ForeColor = $script:C.Muted; $l.Font = $script:FontSmall }
        'head'  { $l.ForeColor = $script:C.AccentText; $l.Font = $script:FontBold }
        'ok'    { $l.ForeColor = $script:C.OkText }
        'err'   { $l.ForeColor = $script:C.Err }
        'warn'  { $l.ForeColor = $script:C.Warn }
        default { $l.ForeColor = $script:C.Text }
    }
    if ($Text) { [PesI18n]::Reg($l, $Text) }
    if ($Parent) { $Parent.Controls.Add($l) }
    return $l
}

function New-PesText {
    param([int]$X, [int]$Y, [int]$W, [int]$H = 24, [bool]$Multiline = $false, $Parent = $null)
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = New-Object System.Drawing.Point($X, $Y)
    $t.Size = New-Object System.Drawing.Size($W, $H)
    $t.BackColor = $script:C.Field
    $t.ForeColor = $script:C.Text
    $t.BorderStyle = 'FixedSingle'
    $t.Font = $script:FontUi
    if ($Multiline) { $t.Multiline = $true; $t.Font = $script:FontMono }
    if ($Parent) { $Parent.Controls.Add($t) }
    return $t
}

function New-PesPanel {
    param([int]$X = 0, [int]$Y = 0, [int]$W = 10, [int]$H = 10, $Color = $null, $Parent = $null)
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point($X, $Y)
    $p.Size = New-Object System.Drawing.Size($W, $H)
    if ($null -ne $Color) { $p.BackColor = $Color } else { $p.BackColor = $script:C.Bg }
    if ($Parent) { $Parent.Controls.Add($p) }
    return $p
}

function New-PesCheck {
    param([string]$Text, [int]$X, [int]$Y, [int]$W, $Parent = $null)
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Location = New-Object System.Drawing.Point($X, $Y)
    $c.Size = New-Object System.Drawing.Size($W, 22)
    $c.ForeColor = $script:C.Text
    $c.BackColor = [System.Drawing.Color]::Transparent
    $c.Font = $script:FontUi
    [PesI18n]::Reg($c, $Text)
    if ($Parent) { $Parent.Controls.Add($c) }
    return $c
}

function New-PesCombo {
    param([int]$X, [int]$Y, [int]$W, $Parent = $null)
    $c = New-Object System.Windows.Forms.ComboBox
    $c.Location = New-Object System.Drawing.Point($X, $Y)
    $c.Size = New-Object System.Drawing.Size($W, 24)
    $c.DropDownStyle = 'DropDownList'
    $c.FlatStyle = 'Flat'
    $c.BackColor = $script:C.Field
    $c.ForeColor = $script:C.Text
    $c.Font = $script:FontUi
    if ($Parent) { $Parent.Controls.Add($c) }
    return $c
}

# Programmsymbol zur Laufzeit zeichnen (keine Begleitdatei nötig): Kopfhörer-Ring in Akzentfarbe
function New-PesIcon {
    try {
        $bmp = New-Object System.Drawing.Bitmap(32, 32)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = 'AntiAlias'
        $g.Clear([System.Drawing.Color]::Transparent)
        $b1 = New-Object System.Drawing.SolidBrush($script:C.Accent)
        $g.FillEllipse($b1, 1, 1, 30, 30)
        $b2 = New-Object System.Drawing.SolidBrush($script:C.Bg)
        $g.FillEllipse($b2, 6, 6, 20, 20)
        $b3 = New-Object System.Drawing.SolidBrush($script:C.OkText)
        $g.FillRectangle($b3, 10, 13, 12, 8)
        $g.FillRectangle($b3, 13, 22, 6, 2)
        $b1.Dispose(); $b2.Dispose(); $b3.Dispose(); $g.Dispose()
        $h = $bmp.GetHicon()
        return [System.Drawing.Icon]::FromHandle($h)
    } catch { return $null }
}

# Dunkler Dialog mit frei benennbaren Knöpfen; liefert den Index des gewählten Knopfs (-1 = geschlossen).
function Show-PesAsk {
    param([string]$Title, [string]$Text, [string[]]$Buttons, [int]$Accent = 0, [int]$Danger = -1, $Owner = $null)
    $w = 500
    $f = New-PesForm -Title $Title -W $w -H 190
    $f.StartPosition = if ($Owner) { 'CenterParent' } else { 'CenterScreen' }
    $f.MinimizeBox = $false
    $f.TopMost = $true
    $f.Tag = -1
    $l = New-PesLabel -Text '' -X 18 -Y 16 -W ($w - 36) -H 112 -Parent $f
    $l.Text = $Text
    $bw = [Math]::Min(180, [int](($w - 36 - 8 * ($Buttons.Count - 1)) / $Buttons.Count))
    $x = $w - 18 - ($bw * $Buttons.Count) - (8 * ($Buttons.Count - 1))
    for ($i = 0; $i -lt $Buttons.Count; $i++) {
        $kind = 'normal'
        if ($i -eq $Accent) { $kind = 'accent' }
        if ($i -eq $Danger) { $kind = 'danger' }
        # Die Beschriftungen kommen schon in der richtigen Sprache herein
        $b = New-PesButton -Text '' -X $x -Y 140 -W $bw -H 34 -Kind $kind -Parent $f
        $b.Text = $Buttons[$i]
        $b.Tag = $i
        $b.Add_Click({ $this.FindForm().Tag = [int]$this.Tag; $this.FindForm().Close() })
        $x += $bw + 8
    }
    if ($script:PesSelbsttest) { $f.Dispose(); return -1 }
    if ($Owner) { [void]$f.ShowDialog($Owner) } else { [void]$f.ShowDialog() }
    $r = [int]$f.Tag
    $f.Dispose()
    return $r
}

function Show-PesInfo {
    param([string]$Text, $Owner = $null)
    [void](Show-PesAsk -Title $script:PesTitle -Text $Text -Buttons @('OK') -Owner $Owner)
}

# ==============================================================================
# 8a. HAUPTFENSTER
# ==============================================================================
$script:PesUi = @{}                      # alle Controls des Hauptfensters
$script:PesState = @{
    Connected = $false; Connecting = $false; LastPaired = $false; LastCall = 0
    ShareUi = $false; ControlUi = $false; WantCam = $false; WantMic = $true
    ViewWanted = $false; ControlWanted = $false; Fullscreen = $false
    AskOpen = $false; RingForm = $null; Banner = $null; BannerLabel = $null
    Tick = 0; OptProc = $null; RvProc = $null; HelpProc = $null; LastHotkey = $false
    SelfTestErrors = 0; Closing = $false; LastMonitors = -1; LastShareLabel = ''
}

function Add-PesChatLine {
    param([string]$Who, [string]$Text, [string]$Kind = 'sys')
    $rt = $script:PesUi.Chat
    if (-not $rt -or $rt.IsDisposed) { return }
    try {
        $rt.SelectionStart = $rt.TextLength
        $rt.SelectionLength = 0
        $rt.SelectionColor = $script:C.Muted
        $rt.AppendText('[' + (Get-Date -Format 'HH:mm') + '] ')
        switch ($Kind) {
            'me'    { $rt.SelectionColor = $script:C.AccentText }
            'peer'  { $rt.SelectionColor = $script:C.OkText }
            'err'   { $rt.SelectionColor = $script:C.Err }
            'warn'  { $rt.SelectionColor = $script:C.Warn }
            default { $rt.SelectionColor = $script:C.Muted }
        }
        if ($Who) { $rt.AppendText($Who + ': ') }
        if ($Kind -eq 'me' -or $Kind -eq 'peer') { $rt.SelectionColor = $script:C.Text }
        $rt.AppendText($Text + $script:NL)
        $rt.ScrollToCaret()
    } catch { }
    if ($Kind -ne 'me' -and $Kind -ne 'peer') { Write-PesLog -Message $Text }
}

function Get-PesRoleInt { if ($script:PesSettings.Role -eq 'Helfer') { return 1 } else { return 2 } }

# Ordnet die Seitenleiste neu an (je nach Rolle sind andere Zeilen sichtbar).
function Update-PesSideLayout {
    $u = $script:PesUi
    if (-not $u.Side) { return }
    $helper = $script:PesSettings.Role -eq 'Helfer'
    $w = $u.Side.ClientSize.Width - 24
    $y = 10
    $u.LblConn.Location = New-Object System.Drawing.Point(12, $y); $y += 26
    $half = [int](($w - 8) / 2)
    $u.BtnRoleCustomer.SetBounds(12, $y, $half, 34)
    $u.BtnRoleHelper.SetBounds(12 + $half + 8, $y, $w - $half - 8, 34); $y += 44
    $u.LblName.Location = New-Object System.Drawing.Point(12, $y); $y += 18
    $u.TxtName.SetBounds(12, $y, $w, 24); $y += 32
    foreach ($c in @($u.LblServer, $u.TxtServer, $u.BtnNewCode)) { $c.Visible = $helper }
    if ($helper) {
        $u.LblServer.Location = New-Object System.Drawing.Point(12, $y); $y += 18
        $u.TxtServer.SetBounds(12, $y, $w - 118, 24)
        $u.BtnNewCode.SetBounds(12 + $w - 110, $y - 1, 110, 26); $y += 32
    }
    $u.LblCode.Location = New-Object System.Drawing.Point(12, $y); $y += 18
    $u.TxtCode.SetBounds(12, $y, $w, 50); $y += 56
    $third = [int](($w - 16) / 3)
    $u.BtnPaste.SetBounds(12, $y, $third, 28)
    $u.BtnCopy.SetBounds(12 + $third + 8, $y, $third, 28)
    $u.ChkRemember.SetBounds(12 + 2 * ($third + 8), $y + 3, $w - 2 * ($third + 8), 22); $y += 36
    $u.BtnConnect.SetBounds(12, $y, $w, 38); $y += 46
    $u.LblStatus.SetBounds(12, $y, $w, 38); $y += 44
    $u.LblChat.Location = New-Object System.Drawing.Point(12, $y); $y += 22
    $bottom = $u.Side.ClientSize.Height
    $u.BtnOptions.SetBounds(12, $bottom - 40, [int](($w - 24) / 4), 30)
    $bw = [int](($w - 24) / 4)
    $u.BtnRv.SetBounds(12 + $bw + 8, $bottom - 40, $bw, 30)
    $u.BtnHelp.SetBounds(12 + 2 * ($bw + 8), $bottom - 40, $bw, 30)
    $u.BtnLang.SetBounds(12 + 3 * ($bw + 8), $bottom - 40, $w - 3 * ($bw + 8), 30)
    $u.LblFile.SetBounds(12, $bottom - 68, $w, 20)
    $u.BtnFile.SetBounds(12, $bottom - 104, [int]($w * 0.5) - 4, 30)
    $u.BtnFolder.SetBounds(12 + [int]($w * 0.5) + 4, $bottom - 104, $w - [int]($w * 0.5) - 4, 30)
    $u.TxtChat.SetBounds(12, $bottom - 140, $w - 88, 26)
    $u.BtnSend.SetBounds(12 + $w - 80, $bottom - 141, 80, 28)
    $ch = $bottom - 148 - $y
    if ($ch -lt 60) { $ch = 60 }
    $u.Chat.SetBounds(12, $y, $w, $ch)
    $u.BtnRoleCustomer.BackColor = if ($helper) { $script:C.Surface } else { $script:C.Accent }
    $u.BtnRoleHelper.BackColor = if ($helper) { $script:C.Accent } else { $script:C.Surface }
    # Fernwartungs-Leiste: je Rolle andere Knöpfe
    $u.BarHelper.Visible = $helper
    $u.BarCustomer.Visible = -not $helper
    $u.View.Visible = $helper
    $u.ShareInfo.Visible = -not $helper
}

function Set-PesRole {
    param([string]$Role)
    if ($script:PesState.Connected -or $script:PesState.Connecting) { return }
    $script:PesSettings.Role = $Role
    Save-PesSettings
    Update-PesSideLayout
    Update-PesTexts
}

# Alle Texte, die vom Zustand abhängen (wird vom Timer und nach Aktionen aufgerufen).
function Update-PesTexts {
    $u = $script:PesUi
    $st = $script:PesState
    $h = $script:PesHost
    $ses = if ($h) { $h.Session } else { $null }
    $helper = $script:PesSettings.Role -eq 'Helfer'
    $paired = $ses -and $ses.Paired
    $call = if ($ses) { $ses.CallState } else { 0 }

    # Verbinden-Knopf und Sperren der Eingaben
    $busy = $st.Connected -or $st.Connecting
    if ($st.Connecting) { $u.BtnConnect.Text = T 'Abbrechen'; Set-PesButtonKind $u.BtnConnect 'normal' }
    elseif ($st.Connected) { $u.BtnConnect.Text = T 'Trennen'; Set-PesButtonKind $u.BtnConnect 'danger' }
    else { $u.BtnConnect.Text = T 'Verbinden'; Set-PesButtonKind $u.BtnConnect 'accent' }
    foreach ($c in @($u.TxtName, $u.TxtServer, $u.TxtCode, $u.BtnNewCode, $u.BtnPaste, $u.BtnRoleCustomer, $u.BtnRoleHelper)) { $c.Enabled = -not $busy }

    # Kopfzeile
    if (-not $busy) {
        $u.Head.Text = T 'Nicht verbunden. Rechts den Einladungscode einfügen und auf Verbinden klicken.'
        $u.Head.ForeColor = $script:C.Muted
    } elseif ($paired) {
        $u.Head.Text = T 'Verbunden mit {0}' $ses.PartnerName
        $u.Head.ForeColor = $script:C.OkText
    } elseif ($st.Connected) {
        $u.Head.Text = if ($helper) { T 'Sitzung läuft - warte auf den Kunden. Schicke ihm den Einladungscode.' } else { T 'Sitzung läuft - warte auf den Helfer.' }
        $u.Head.ForeColor = $script:C.Warn
    } else {
        $u.Head.Text = T 'Verbindung wird aufgebaut ...'
        $u.Head.ForeColor = $script:C.Warn
    }

    # Anruf-Leiste
    $u.BtnCall.Enabled = [bool]$paired
    if ($call -eq 3) { $u.BtnCall.Text = T 'Auflegen'; Set-PesButtonKind $u.BtnCall 'danger' }
    elseif ($call -eq 1) { $u.BtnCall.Text = T 'Anruf abbrechen'; Set-PesButtonKind $u.BtnCall 'danger' }
    else { $u.BtnCall.Text = T 'Anrufen'; Set-PesButtonKind $u.BtnCall 'ok' }
    $u.BtnMic.Text = if ($st.WantMic) { T 'Mikrofon: an' } else { T 'Mikrofon: aus' }
    $u.BtnCam.Text = if ($st.WantCam) { T 'Kamera: an' } else { T 'Kamera: aus' }
    Set-PesButtonKind $u.BtnMic $(if ($st.WantMic) { 'normal' } else { 'danger' })
    Set-PesButtonKind $u.BtnCam $(if ($st.WantCam) { 'accent' } else { 'normal' })
    $callText = ''
    if ($call -eq 1) { $callText = T 'Es klingelt beim Partner ...' }
    elseif ($call -eq 2) { $callText = T 'Eingehender Anruf ...' }
    elseif ($call -eq 3) {
        $callText = T 'Im Gespräch'
        if ($h -and $h.MediaError) { $callText = [PesI18n]::Core($h.MediaError) }
        elseif ($h -and $st.WantCam -and -not $h.CameraRunning -and $h.CameraError) { $callText = [PesI18n]::Core($h.CameraError) }
    }
    elseif ($paired) { $callText = T 'Bereit für einen Anruf' }
    $u.LblCall.Text = $callText
    $u.VidRemote.Placeholder = if ($call -eq 3) { if ($ses.PartnerCam) { T 'Warte auf das Bild ...' } else { T 'Die Kamera des Partners ist aus.' } } else { (T 'Live-Video-Chat') + $script:NL + (T 'Hier erscheint das Bild des Partners, sobald ein Anruf läuft.') }
    $u.VidRemote.Caption = if ($paired) { $ses.PartnerName } else { '' }
    $u.VidSelf.Visible = ($call -eq 3 -and $st.WantCam)

    # Fernwartung
    if ($helper) {
        $share = $paired -and $ses.ShareActive
        $ctl = $share -and $ses.ControlActive
        foreach ($c in @($u.BtnView, $u.BtnControl, $u.CmbQuality, $u.CmbMonitor, $u.BtnKeys, $u.BtnShot, $u.BtnFull)) { $c.Enabled = [bool]$paired }
        if ($share) { $u.BtnView.Text = T 'Ansicht beenden'; Set-PesButtonKind $u.BtnView 'danger' } else { $u.BtnView.Text = T 'Bildschirm anfordern'; Set-PesButtonKind $u.BtnView 'accent' }
        if ($ctl) { $u.BtnControl.Text = T 'Steuerung: an'; Set-PesButtonKind $u.BtnControl 'ok' } else { $u.BtnControl.Text = T 'Steuerung anfordern'; Set-PesButtonKind $u.BtnControl 'normal' }
        $u.BtnKeys.Enabled = [bool]$ctl
        $u.BtnShot.Enabled = [bool]$share
        $u.View.ControlEnabled = [bool]$ctl
        if (-not $paired) { $u.View.Placeholder = (T 'Fernwartung') + $script:NL + (T 'Hier erscheint der Bildschirm des Kunden.') }
        elseif (-not $share) { $u.View.Placeholder = if ($st.ViewWanted) { T 'Warte auf die Zustimmung des Kunden ...' } else { (T 'Der Kunde überträgt seinen Bildschirm nicht.') + $script:NL + (T 'Mit "Bildschirm anfordern" fragst du ihn danach.') } }
        else { $u.View.Placeholder = T 'Warte auf das Bild ...' }
    } else {
        $share = [bool]$st.ShareUi
        $u.BtnShare.Enabled = [bool]$paired
        $u.BtnAllow.Enabled = $share
        if ($share) { $u.BtnShare.Text = T 'Freigabe beenden'; Set-PesButtonKind $u.BtnShare 'danger' } else { $u.BtnShare.Text = T 'Bildschirm freigeben'; Set-PesButtonKind $u.BtnShare 'accent' }
        if ($st.ControlUi) { $u.BtnAllow.Text = T 'Steuerung sperren'; Set-PesButtonKind $u.BtnAllow 'danger' } else { $u.BtnAllow.Text = T 'Steuerung erlauben'; Set-PesButtonKind $u.BtnAllow 'normal' }
        if (-not $share) {
            $u.ShareTitle.Text = T 'Ihr Bildschirm wird NICHT übertragen.'
            $u.ShareTitle.ForeColor = $script:C.OkText
            $u.ShareText.Text = (T 'Der Helfer sieht Ihren Bildschirm erst, wenn Sie zustimmen.') + $script:NL + (T 'Maus und Tastatur kann er nur bedienen, wenn Sie das zusätzlich erlauben.') + $script:NL + $script:NL + (T 'Notfall-Stopp jederzeit: Strg+Umschalt+F12')
        } else {
            $u.ShareTitle.Text = if ($st.ControlUi) { T 'Ihr Bildschirm wird an {0} übertragen - mit Steuerung.' $ses.PartnerName } else { T 'Ihr Bildschirm wird an {0} übertragen - nur ansehen.' $ses.PartnerName }
            $u.ShareTitle.ForeColor = $script:C.Warn
            $fps = 0; $kb = 0
            if ($h -and $h.Screen) { $fps = $h.Screen.Fps; $kb = $h.Screen.Kbps }
            $extra = ''
            if ($h -and $h.Screen -and $h.Screen.LastError) { $extra = $script:NL + (T 'Hinweis: Bei Sperrbildschirm oder Windows-Sicherheitsabfrage (UAC) gibt es kurz kein Bild.') }
            $u.ShareText.Text = (T 'Übertragung: {0} Bilder/s, {1} kbit/s' $fps $kb) + $script:NL + (T 'Notfall-Stopp jederzeit: Strg+Umschalt+F12') + $extra
        }
    }

    # Chat und Datei
    foreach ($c in @($u.TxtChat, $u.BtnSend, $u.BtnFile)) { $c.Enabled = [bool]$paired }
}

function New-PesMainWindow {
    $u = $script:PesUi
    # Auf kleinen Bildschirmen passt sich das Fenster an die verfügbare Fläche an
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $fw = [Math]::Min(1260, $wa.Width - 24)
    $fh = [Math]::Min(800, $wa.Height - 48)
    $f = New-PesForm -Title ($script:PesTitle + '  ' + $script:PesVersion) -W $fw -H $fh -Sizable $true
    $f.MinimumSize = New-Object System.Drawing.Size(([Math]::Min(1040, $fw)), ([Math]::Min(700, $fh)))
    $f.KeyPreview = $true
    $u.Form = $f

    # ---- Seitenleiste (rechts) ----
    $side = New-PesPanel -W 344 -H 800 -Color $script:C.Surface
    $side.Dock = 'Right'
    $u.Side = $side
    $u.LblConn = New-PesLabel -Text 'Verbindung' -X 12 -Y 10 -W 300 -H 22 -Kind 'head' -Parent $side
    $u.BtnRoleCustomer = New-PesButton -Text 'Ich brauche Hilfe' -X 12 -Y 36 -W 150 -H 34 -Parent $side
    $u.BtnRoleHelper = New-PesButton -Text 'Ich helfe' -X 170 -Y 36 -W 150 -H 34 -Parent $side
    $u.LblName = New-PesLabel -Text 'Mein Name' -X 12 -Y 80 -W 300 -H 18 -Kind 'muted' -Parent $side
    $u.TxtName = New-PesText -X 12 -Y 98 -W 316 -Parent $side
    $u.TxtName.MaxLength = 32
    $u.LblServer = New-PesLabel -Text 'Vermittler-Adresse (Name oder IP, optional :Port)' -X 12 -Y 130 -W 320 -H 18 -Kind 'muted' -Parent $side
    $u.TxtServer = New-PesText -X 12 -Y 148 -W 200 -Parent $side
    $u.BtnNewCode = New-PesButton -Text 'Neuer Code' -X 220 -Y 147 -W 108 -H 26 -Parent $side
    $u.LblCode = New-PesLabel -Text 'Einladungscode (PES1:...)' -X 12 -Y 180 -W 300 -H 18 -Kind 'muted' -Parent $side
    $u.TxtCode = New-PesText -X 12 -Y 198 -W 316 -H 50 -Multiline $true -Parent $side
    $u.BtnPaste = New-PesButton -Text 'Einfügen' -X 12 -Y 254 -W 100 -H 28 -Parent $side
    $u.BtnCopy = New-PesButton -Text 'Kopieren' -X 120 -Y 254 -W 100 -H 28 -Parent $side
    $u.ChkRemember = New-PesCheck -Text 'merken' -X 230 -Y 257 -W 96 -Parent $side
    $u.BtnConnect = New-PesButton -Text 'Verbinden' -X 12 -Y 290 -W 316 -H 38 -Kind 'accent' -Parent $side
    $u.BtnConnect.Font = $script:FontBold
    $u.LblStatus = New-PesLabel -Text '' -X 12 -Y 336 -W 316 -H 38 -Kind 'muted' -Parent $side
    $u.LblChat = New-PesLabel -Text 'Chat und Verlauf' -X 12 -Y 380 -W 300 -H 22 -Kind 'head' -Parent $side
    $chat = New-Object System.Windows.Forms.RichTextBox
    $chat.ReadOnly = $true; $chat.BorderStyle = 'None'; $chat.BackColor = $script:C.Field; $chat.ForeColor = $script:C.Text
    $chat.Font = $script:FontUi; $chat.DetectUrls = $false; $chat.ScrollBars = 'Vertical'
    $side.Controls.Add($chat); $u.Chat = $chat
    $u.TxtChat = New-PesText -X 12 -Y 600 -W 230 -H 26 -Parent $side
    $u.TxtChat.MaxLength = 2000
    $u.BtnSend = New-PesButton -Text 'Senden' -X 250 -Y 599 -W 78 -H 28 -Parent $side
    $u.BtnFile = New-PesButton -Text 'Datei senden' -X 12 -Y 640 -W 150 -H 30 -Parent $side
    $u.BtnFolder = New-PesButton -Text 'Empfangene Dateien' -X 170 -Y 640 -W 158 -H 30 -Parent $side
    $u.LblFile = New-PesLabel -Text '' -X 12 -Y 676 -W 316 -H 20 -Kind 'muted' -Parent $side
    $u.BtnOptions = New-PesButton -Text 'Optionen' -X 12 -Y 720 -W 76 -H 30 -Parent $side
    $u.BtnRv = New-PesButton -Text 'Vermittler' -X 92 -Y 720 -W 76 -H 30 -Parent $side
    $u.BtnHelp = New-PesButton -Text 'Hilfe' -X 172 -Y 720 -W 76 -H 30 -Parent $side
    $u.BtnLang = New-PesButton -Text '' -X 252 -Y 720 -W 76 -H 30 -Parent $side

    # ---- Hauptbereich (links): Kopfzeile, oben Video, unten Fernwartung ----
    $main = New-PesPanel
    $main.Dock = 'Fill'
    $u.Main = $main
    $headPanel = New-PesPanel -H 38 -Color $script:C.Surface
    $headPanel.Dock = 'Top'
    $head = New-PesLabel -Text '' -X 12 -Y 9 -W 800 -H 22 -Parent $headPanel
    $head.Font = $script:FontBold
    $head.Anchor = 'Top,Left,Right'
    $u.Head = $head; $u.HeadPanel = $headPanel

    $split = New-Object System.Windows.Forms.SplitContainer
    $split.Dock = 'Fill'
    $split.Orientation = 'Horizontal'
    $split.BackColor = $script:C.Border
    $split.SplitterWidth = 5
    $split.Panel1.BackColor = $script:C.Bg
    $split.Panel2.BackColor = $script:C.Bg
    $u.Split = $split

    # OBEN: Live-Video-Chat
    $vid = New-Object PesVideoPanel
    $vid.Dock = 'Fill'
    $vid.Font = $script:FontBig
    $u.VidRemote = $vid
    $self = New-Object PesVideoPanel
    $self.Size = New-Object System.Drawing.Size(168, 126)
    $self.Mirror = $true
    $self.Visible = $false
    $self.Font = $script:FontSmall
    $self.BackColor = [System.Drawing.Color]::FromArgb(40, 44, 50)
    $vid.Controls.Add($self)
    $u.VidSelf = $self
    $vid.Add_Resize({ $s = $script:PesUi.VidSelf; if ($s) { $s.Location = New-Object System.Drawing.Point(($this.Width - $s.Width - 10), ($this.Height - $s.Height - 10)) } })
    $barCall = New-PesPanel -H 46 -Color $script:C.Surface
    $barCall.Dock = 'Bottom'
    $u.BtnCall = New-PesButton -Text 'Anrufen' -X 10 -Y 7 -W 150 -H 32 -Kind 'ok' -Parent $barCall
    $u.BtnMic = New-PesButton -Text 'Mikrofon: an' -X 168 -Y 7 -W 130 -H 32 -Parent $barCall
    $u.BtnCam = New-PesButton -Text 'Kamera: aus' -X 306 -Y 7 -W 130 -H 32 -Parent $barCall
    $u.LblCall = New-PesLabel -Text '' -X 448 -Y 13 -W 440 -H 22 -Kind 'muted' -Parent $barCall
    $u.LblCall.Font = $script:FontUi
    $u.LblCall.Anchor = 'Top,Left,Right'
    $split.Panel1.Controls.Add($vid)
    $split.Panel1.Controls.Add($barCall)
    $vid.BringToFront()

    # UNTEN: Fernwartung
    $view = New-Object PesViewPanel
    $view.Dock = 'Fill'
    $view.Font = $script:FontBig
    $u.View = $view
    $info = New-PesPanel
    $info.Dock = 'Fill'
    $u.ShareInfo = $info
    $u.ShareTitle = New-PesLabel -Text '' -X 24 -Y 24 -W 800 -H 30 -Parent $info
    $u.ShareTitle.Font = $script:FontBig
    $u.ShareTitle.Anchor = 'Top,Left,Right'
    $u.ShareText = New-PesLabel -Text '' -X 24 -Y 62 -W 800 -H 120 -Kind 'muted' -Parent $info
    $u.ShareText.Font = $script:FontUi
    $u.ShareText.Anchor = 'Top,Left,Right'

    $barH = New-PesPanel -H 46 -Color $script:C.Surface
    $barH.Dock = 'Top'
    $u.BarHelper = $barH
    $u.BtnView = New-PesButton -Text 'Bildschirm anfordern' -X 10 -Y 7 -W 170 -H 32 -Kind 'accent' -Parent $barH
    $u.BtnControl = New-PesButton -Text 'Steuerung anfordern' -X 188 -Y 7 -W 160 -H 32 -Parent $barH
    $u.CmbQuality = New-PesCombo -X 356 -Y 11 -W 110 -Parent $barH
    $u.CmbMonitor = New-PesCombo -X 474 -Y 11 -W 120 -Parent $barH
    $u.BtnKeys = New-PesButton -Text 'Tasten' -X 602 -Y 7 -W 84 -H 32 -Parent $barH
    $u.BtnShot = New-PesButton -Text 'Foto' -X 694 -Y 7 -W 70 -H 32 -Parent $barH
    $u.BtnFull = New-PesButton -Text 'Großansicht' -X 772 -Y 7 -W 110 -H 32 -Parent $barH
    $barC = New-PesPanel -H 46 -Color $script:C.Surface
    $barC.Dock = 'Top'
    $u.BarCustomer = $barC
    $u.BtnShare = New-PesButton -Text 'Bildschirm freigeben' -X 10 -Y 7 -W 190 -H 32 -Kind 'accent' -Parent $barC
    $u.BtnAllow = New-PesButton -Text 'Steuerung erlauben' -X 208 -Y 7 -W 180 -H 32 -Parent $barC
    $lblHot = New-PesLabel -Text 'Notfall-Stopp: Strg+Umschalt+F12' -X 400 -Y 13 -W 400 -H 22 -Kind 'muted' -Parent $barC
    $lblHot.Font = $script:FontUi

    $split.Panel2.Controls.Add($view)
    $split.Panel2.Controls.Add($info)
    $split.Panel2.Controls.Add($barH)
    $split.Panel2.Controls.Add($barC)
    $view.BringToFront(); $info.BringToFront()

    $main.Controls.Add($split)
    $main.Controls.Add($headPanel)
    $split.BringToFront()
    $f.Controls.Add($main)
    $f.Controls.Add($side)
    $main.BringToFront()

    # Tasten-Menü des Helfers (Tastenfolgen, die Windows lokal abfängt)
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $menu.BackColor = $script:C.Surface; $menu.ForeColor = $script:C.Text; $menu.ShowImageMargin = $false
    $chords = @(
        @{ Text = 'Task-Manager (Strg+Umschalt+Esc)'; Keys = @(0x11, 0x10, 0x1B) },
        @{ Text = 'Windows-Taste'; Keys = @(0x5B) },
        @{ Text = 'Ausführen (Windows+R)'; Keys = @(0x5B, 0x52) },
        @{ Text = 'Fenster wechseln (Alt+Tab)'; Keys = @(0x12, 0x09) },
        @{ Text = 'Fenster schließen (Alt+F4)'; Keys = @(0x12, 0x73) },
        @{ Text = 'Desktop anzeigen (Windows+D)'; Keys = @(0x5B, 0x44) }
    )
    foreach ($c in $chords) {
        $it = New-Object System.Windows.Forms.ToolStripMenuItem
        [PesI18n]::Reg($it, $c.Text)
        $it.Tag = [int[]]$c.Keys
        $it.Add_Click({ try { $script:PesUi.View.SendChord([int[]]$this.Tag); [void]$script:PesUi.View.Focus() } catch { } })
        [void]$menu.Items.Add($it)
    }
    $u.KeysMenu = $menu

    # Auswahllisten
    foreach ($q in @('Sparsam', 'Normal', 'Scharf')) { [void]$u.CmbQuality.Items.Add((T $q)) }
    $u.CmbQuality.SelectedIndex = [Math]::Max(0, [Math]::Min(2, $script:PesSettings.Quality - 1))
    [void]$u.CmbMonitor.Items.Add((T 'Bildschirm {0}' 1)); $u.CmbMonitor.SelectedIndex = 0

    # Startwerte
    $u.TxtName.Text = [string]$script:PesSettings.Name
    $u.TxtServer.Text = [string]$script:PesSettings.ServerAddress
    $u.ChkRemember.Checked = [bool]$script:PesSettings.RememberInvite
    if ($script:PesSettings.RememberInvite -and $script:PesSettings.InviteEnc) { $u.TxtCode.Text = Unprotect-PesText $script:PesSettings.InviteEnc }
    if (-not $u.TxtCode.Text) {
        # Liegt ein Einladungscode in der Zwischenablage, wird er gleich eingetragen
        try { $clip = [System.Windows.Forms.Clipboard]::GetText(); if ($clip -and [PesProto]::InviteParse($clip)) { $u.TxtCode.Text = $clip.Trim() } } catch { }
    }

    # ---- Ereignisse ----
    $u.BtnRoleCustomer.Add_Click({ Set-PesRole 'Kunde' })
    $u.BtnRoleHelper.Add_Click({ Set-PesRole 'Helfer' })
    $u.BtnNewCode.Add_Click({ New-PesInviteCode })
    $u.BtnPaste.Add_Click({ try { $t = [System.Windows.Forms.Clipboard]::GetText(); if ($t) { $script:PesUi.TxtCode.Text = $t.Trim() } } catch { } })
    $u.BtnCopy.Add_Click({
        try {
            $t = $script:PesUi.TxtCode.Text.Trim()
            if ($t) { [System.Windows.Forms.Clipboard]::SetText($t); Add-PesChatLine -Text (T 'Einladungscode in die Zwischenablage kopiert. Schicke ihn dem Kunden (z. B. per Messenger oder E-Mail).') }
        } catch { }
    })
    $u.BtnConnect.Add_Click({ if ($script:PesState.Connected -or $script:PesState.Connecting) { Disconnect-Pes -Ask $true } else { Connect-Pes } })
    $u.BtnSend.Add_Click({ Send-PesChat })
    $u.TxtChat.Add_KeyDown({ if ($_.KeyCode -eq 'Return') { $_.SuppressKeyPress = $true; Send-PesChat } })
    $u.BtnFile.Add_Click({ Send-PesFile })
    $u.BtnFolder.Add_Click({
        try {
            $d = [string]$script:PesSettings.DownloadDir
            if (-not [System.IO.Directory]::Exists($d)) { [void][System.IO.Directory]::CreateDirectory($d) }
            [void][System.Diagnostics.Process]::Start($d)        # öffnet den Ordner im Explorer (kein Konsolenfenster)
        } catch { }
    })
    $u.BtnOptions.Add_Click({ if (-not $script:PesState.OptProc -or $script:PesState.OptProc.HasExited) { $script:PesState.OptProc = Start-PesSelf @('-Optionen') } })
    $u.BtnHelp.Add_Click({ if (-not $script:PesState.HelpProc -or $script:PesState.HelpProc.HasExited) { $script:PesState.HelpProc = Start-PesSelf @('-Hilfe') } })
    $u.BtnRv.Add_Click({ if (-not $script:PesState.RvProc -or $script:PesState.RvProc.HasExited) { $script:PesState.RvProc = Start-PesSelf @('-Vermittler') } })
    $u.BtnLang.Add_Click({
        $script:PesSettings.Language = if ($script:PesSettings.Language -eq 'en') { 'de' } else { 'en' }
        Save-PesSettings
        Set-PesLanguage
    })
    $u.BtnCall.Add_Click({ Invoke-PesCallButton })
    $u.BtnMic.Add_Click({ $script:PesState.WantMic = -not $script:PesState.WantMic; Sync-PesMedia; Update-PesTexts })
    $u.BtnCam.Add_Click({ $script:PesState.WantCam = -not $script:PesState.WantCam; Sync-PesMedia; Update-PesTexts })
    $u.BtnView.Add_Click({ Invoke-PesViewButton })
    $u.BtnControl.Add_Click({ Invoke-PesControlButton })
    $u.CmbQuality.Add_SelectedIndexChanged({ Send-PesScreenOptions })
    $u.CmbMonitor.Add_SelectedIndexChanged({ Send-PesScreenOptions })
    $u.BtnKeys.Add_Click({ $script:PesUi.KeysMenu.Show($this, 0, $this.Height) })
    $u.BtnShot.Add_Click({ Save-PesScreenshot })
    $u.BtnFull.Add_Click({ Set-PesFullscreen (-not $script:PesState.Fullscreen) })
    $u.BtnShare.Add_Click({ Invoke-PesShareButton })
    $u.BtnAllow.Add_Click({ Invoke-PesAllowButton })
    $side.Add_Resize({ Update-PesSideLayout })
    $f.Add_KeyDown({ if ($_.KeyCode -eq 'F11') { Set-PesFullscreen (-not $script:PesState.Fullscreen); $_.Handled = $true } })
    $f.Add_Resize({
        if ($this.WindowState -eq 'Minimized' -and $script:PesSettings.MinimizeToTray) { $this.Hide() }
    })
    $f.Add_FormClosing({
        if ($script:PesState.Closing) { return }
        if ($script:PesState.Connected -and -not $script:PesSelbsttest) {
            $r = Show-PesAsk -Title $script:PesTitle -Text (T 'Die Sitzung läuft noch. Programm wirklich beenden?') -Buttons @((T 'Beenden'), (T 'Zurück')) -Accent 1 -Danger 0 -Owner $this
            if ($r -ne 0) { $_.Cancel = $true; return }
        }
        $script:PesState.Closing = $true
    })
    $f.Add_Shown({
        # Erst jetzt hat der Teiler seine Größe (vorher würde das Setzen der Mindestgrößen fehlschlagen)
        try {
            $sp = $script:PesUi.Split
            $sp.SplitterDistance = [int]($sp.Height * 0.42)
            $sp.Panel1MinSize = 150
            $sp.Panel2MinSize = 200
        } catch { }
        Update-PesSideLayout
        Update-PesTexts
    })
    Update-PesSideLayout
    return $f
}

function Set-PesLanguage {
    [PesI18n]::Lang = [string]$script:PesSettings.Language
    [PesI18n]::ApplyAll()
    $u = $script:PesUi
    if ($u.BtnLang) { $u.BtnLang.Text = if ($script:PesSettings.Language -eq 'en') { 'Deutsch' } else { 'English' } }
    if ($u.CmbQuality) {
        $i = $u.CmbQuality.SelectedIndex
        $u.CmbQuality.Items.Clear()
        foreach ($q in @('Sparsam', 'Normal', 'Scharf')) { [void]$u.CmbQuality.Items.Add((T $q)) }
        if ($i -ge 0) { $u.CmbQuality.SelectedIndex = $i }
        $script:PesState.LastMonitors = -1
    }
    if ($u.Form) { Update-PesTexts }
}

function Set-PesFullscreen {
    param([bool]$On)
    $u = $script:PesUi
    $script:PesState.Fullscreen = $On
    $u.Side.Visible = -not $On
    $u.HeadPanel.Visible = -not $On
    $u.Split.Panel1Collapsed = $On
    $u.BtnFull.Text = if ($On) { T 'Normalansicht' } else { T 'Großansicht' }
}

# ---- Verbinden / Trennen ----
function New-PesInviteCode {
    $u = $script:PesUi
    $srv = $u.TxtServer.Text.Trim()
    $h = $null; $p = 0
    if (-not [PesProto]::ParseServer($srv, $script:PesDefaultRvPort, [ref]$h, [ref]$p)) {
        Show-PesInfo -Text ((T 'Bitte zuerst die Adresse des Vermittlers eintragen (Name oder IP, optional mit :Port).') + $script:NL + $script:NL + (T 'Ohne eigenen Server: unten auf "Vermittler" klicken - er läuft dann auf diesem PC.')) -Owner $u.Form
        return
    }
    $server = if ($p -eq $script:PesDefaultRvPort) { $h } else { $h + ':' + $p }
    # Lobby und Passwort werden zufällig erzeugt (Passwort 24 Zeichen) und stehen nur im Code
    $u.TxtCode.Text = [PesProto]::InviteCreate($server, [PesProto]::NewLobby(), [PesProto]::NewPassword())
    Add-PesChatLine -Text (T 'Neuer Einladungscode erzeugt. Mit "Kopieren" in die Zwischenablage legen und dem Kunden schicken.')
}

function Connect-Pes {
    $u = $script:PesUi
    $name = $u.TxtName.Text.Trim()
    if (-not $name) { Show-PesInfo -Text (T 'Bitte einen Namen eintragen.') -Owner $u.Form; return }
    $inv = [PesProto]::InviteParse($u.TxtCode.Text)
    if (-not $inv) {
        $msg = T 'Der Einladungscode ist ungültig. Er beginnt mit "PES1:" und kommt vom Helfer.'
        if ($script:PesSettings.Role -eq 'Helfer') { $msg = $msg + $script:NL + (T 'Als Helfer erzeugst du ihn mit "Neuer Code".') }
        Show-PesInfo -Text $msg -Owner $u.Form
        return
    }
    $h = $null; $p = 0
    if (-not [PesProto]::ParseServer($inv[0], $script:PesDefaultRvPort, [ref]$h, [ref]$p)) { Show-PesInfo -Text (T 'Die Vermittler-Adresse im Einladungscode ist ungültig.') -Owner $u.Form; return }
    $script:PesSettings.Name = $name
    $script:PesSettings.ServerAddress = $u.TxtServer.Text.Trim()
    $script:PesSettings.RememberInvite = [bool]$u.ChkRemember.Checked
    $script:PesSettings.InviteEnc = if ($u.ChkRemember.Checked) { Protect-PesText $u.TxtCode.Text.Trim() } else { '' }
    Save-PesSettings
    $bind = Get-PesBindIp
    Add-PesFirewallRule -Service '' -UdpPort ([int]$script:PesSettings.UdpPort)
    $script:PesHost.EchoGate = [bool]$script:PesSettings.EchoGate
    $script:PesState.Connecting = $true
    $script:PesState.Connected = $false
    $script:PesState.LastPaired = $false
    $p2 = @($h, $p, $inv[1], $inv[2], $name, [string]$script:PesSettings.MachineKey, (Get-PesRoleInt), [int]$script:PesSettings.UdpPort, $bind, [string]$script:PesSettings.DownloadDir)
    $script:PesHost.Connect($p2[0], $p2[1], $p2[2], $p2[3], $p2[4], $p2[5], $p2[6], $p2[7], $p2[8], $p2[9])
    Add-PesChatLine -Text (T 'Verbinde mit dem Vermittler {0} ...' ($h + ':' + $p))
    Update-PesTexts
}

function Disconnect-Pes {
    param([bool]$Ask = $false)
    $st = $script:PesState
    if ($Ask -and $st.Connected -and $script:PesHost.Session -and $script:PesHost.Session.Paired) {
        $r = Show-PesAsk -Title $script:PesTitle -Text (T 'Sitzung mit {0} wirklich beenden?' $script:PesHost.Session.PartnerName) -Buttons @((T 'Trennen'), (T 'Zurück')) -Accent 1 -Danger 0 -Owner $script:PesUi.Form
        if ($r -ne 0) { return }
    }
    Stop-PesShareUi
    Close-PesRing
    try { $script:PesHost.Disconnect() } catch { }
    $st.Connected = $false; $st.Connecting = $false; $st.LastPaired = $false; $st.LastCall = 0
    $st.ViewWanted = $false; $st.ControlWanted = $false
    Add-PesChatLine -Text (T 'Getrennt.')
    Update-PesTexts
}

function Send-PesChat {
    $u = $script:PesUi
    $t = $u.TxtChat.Text.Trim()
    if (-not $t) { return }
    $ses = $script:PesHost.Session
    if ($ses -and $ses.SendChat($t)) { Add-PesChatLine -Who (T 'Ich') -Text $t -Kind 'me'; $u.TxtChat.Text = '' }
}

function Send-PesFile {
    $ses = $script:PesHost.Session
    if (-not $ses -or -not $ses.Paired) { return }
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = T 'Datei für den Partner auswählen'
    try {
        if ($dlg.ShowDialog($script:PesUi.Form) -ne 'OK') { return }
        $err = $ses.OfferFile($dlg.FileName)
        if ($err) { Add-PesChatLine -Text ((T 'Datei kann nicht gesendet werden:') + ' ' + [PesI18n]::Core($err)) -Kind 'err' }
        else { Add-PesChatLine -Text (T 'Datei angeboten: {0} - warte auf die Zustimmung des Partners.' ([System.IO.Path]::GetFileName($dlg.FileName))) }
    } finally { $dlg.Dispose() }
}

# ---- Anruf ----
function Invoke-PesCallButton {
    $ses = $script:PesHost.Session
    if (-not $ses) { return }
    if ($ses.CallState -eq 0) { [void]$ses.Call() } else { $ses.Hangup() }
    Update-PesTexts
}

# Ton und Kamera folgen dem Anruf-Zustand und den beiden Schaltern.
function Sync-PesMedia {
    $h = $script:PesHost
    $ses = $h.Session
    $st = $script:PesState
    if (-not $ses -or $ses.CallState -ne 3) {
        if ($h.MediaRunning -or $h.CameraRunning) { $h.StopMedia() }
        return
    }
    if (-not $h.MediaRunning) {
        $mic = Get-PesDeviceIndex -Names ([PesWinmm]::InputDeviceNames()) -Want ([string]$script:PesSettings.MicDevice)
        $spk = Get-PesDeviceIndex -Names ([PesWinmm]::OutputDeviceNames()) -Want ([string]$script:PesSettings.SpeakerDevice)
        $h.StartMedia($mic, $spk)
        if ($h.MediaError) { Add-PesChatLine -Text ([PesI18n]::Core($h.MediaError)) -Kind 'warn' }
    }
    if ($st.WantCam -and -not $h.CameraRunning -and -not $st.CamTried) {
        $st.CamTried = $true
        $h.StartCamera([string]$script:PesSettings.Camera, [bool]$script:PesSettings.CameraFlip)
    }
    if (-not $st.WantCam) { if ($h.CameraRunning) { $h.StopCamera() }; $st.CamTried = $false }
    # Dem Partner wird die Kamera nur als "an" gemeldet, wenn sie wirklich Bilder liefert
    $camOn = [bool]($st.WantCam -and $h.CameraRunning)
    if ($ses.MyCam -ne $camOn -or $ses.MyMic -ne [bool]$st.WantMic) { $ses.SetMedia($camOn, [bool]$st.WantMic) }
}

function Show-PesRing {
    param([string]$Name)
    Close-PesRing
    $f = New-PesForm -Title (T 'Eingehender Anruf') -W 420 -H 210
    $f.TopMost = $true; $f.MinimizeBox = $false
    $l1 = New-PesLabel -Text '' -X 20 -Y 22 -W 380 -H 34 -Parent $f
    $l1.Font = New-Object System.Drawing.Font('Segoe UI', 16)
    $l1.Text = $Name
    $l2 = New-PesLabel -Text 'ruft an (Video-Chat mit Ton)' -X 22 -Y 62 -W 380 -H 22 -Kind 'muted' -Parent $f
    $l2.Font = $script:FontUi
    $bNo = New-PesButton -Text 'Ablehnen' -X 20 -Y 140 -W 180 -H 46 -Kind 'danger' -Parent $f
    $bYes = New-PesButton -Text 'Annehmen' -X 220 -Y 140 -W 180 -H 46 -Kind 'ok' -Parent $f
    $bYes.Font = $script:FontBold; $bNo.Font = $script:FontBold
    $bYes.Add_Click({ try { $script:PesHost.Session.AnswerCall($true) } catch { }; Close-PesRing })
    $bNo.Add_Click({ try { $script:PesHost.Session.AnswerCall($false) } catch { }; Close-PesRing })
    $f.Add_FormClosing({ if ($script:PesState.RingForm -eq $this) { try { if ($script:PesHost.Session -and $script:PesHost.Session.CallState -eq 2) { $script:PesHost.Session.AnswerCall($false) } } catch { }; $script:PesState.RingForm = $null } })
    $script:PesState.RingForm = $f
    if (-not $script:PesSelbsttest) { $f.Show() }
    if ($script:PesTray -and $script:PesUi.Form -and -not $script:PesUi.Form.Visible) {
        try { $script:PesTray.ShowBalloonTip(8000, $script:PesTitle, (T '{0} ruft an.' $Name), 'Info') } catch { }
    }
}

function Close-PesRing {
    $f = $script:PesState.RingForm
    $script:PesState.RingForm = $null
    if ($f -and -not $f.IsDisposed) { try { $f.Close(); $f.Dispose() } catch { } }
}

# ---- Fernwartung: Helfer ----
function Invoke-PesViewButton {
    $ses = $script:PesHost.Session
    if (-not $ses -or -not $ses.Paired) { return }
    if ($ses.ShareActive) {
        [void]$ses.RequestScreen(3)
        $script:PesState.ViewWanted = $false; $script:PesState.ControlWanted = $false
    } else {
        Send-PesScreenOptions
        [void]$ses.RequestScreen(1)
        $script:PesState.ViewWanted = $true
        Add-PesChatLine -Text (T 'Bildschirm angefordert - der Kunde muss zustimmen.')
    }
    Update-PesTexts
}

function Invoke-PesControlButton {
    $ses = $script:PesHost.Session
    if (-not $ses -or -not $ses.Paired) { return }
    if ($ses.ControlActive) {
        [void]$ses.RequestScreen(4)
        $script:PesState.ControlWanted = $false
    } else {
        Send-PesScreenOptions
        [void]$ses.RequestScreen(2)
        $script:PesState.ViewWanted = $true; $script:PesState.ControlWanted = $true
        Add-PesChatLine -Text (T 'Steuerung angefordert - der Kunde muss zustimmen.')
    }
    Update-PesTexts
}

function Send-PesScreenOptions {
    $u = $script:PesUi
    $ses = $script:PesHost.Session
    $q = $u.CmbQuality.SelectedIndex + 1
    if ($q -lt 1) { $q = 2 }
    if ($script:PesSettings.Quality -ne $q) { $script:PesSettings.Quality = $q; Save-PesSettings }
    $m = [Math]::Max(0, $u.CmbMonitor.SelectedIndex)
    if ($ses -and $ses.Paired) { [void]$ses.SetScreenOptions($q, $m) }
}

function Save-PesScreenshot {
    try {
        $d = [string]$script:PesSettings.DownloadDir
        if (-not [System.IO.Directory]::Exists($d)) { [void][System.IO.Directory]::CreateDirectory($d) }
        $file = Join-Path $d ('Bildschirmfoto_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.png')
        if ($script:PesUi.View.SaveImage($file)) { Add-PesChatLine -Text (T 'Bildschirmfoto gespeichert: {0}' $file) }
    } catch { Add-PesChatLine -Text ((T 'Bildschirmfoto konnte nicht gespeichert werden:') + ' ' + $_.Exception.Message) -Kind 'err' }
}

# ---- Fernwartung: Kunde (Zustimmung, Hinweis-Leiste, Notfall-Stopp) ----
function Show-PesBanner {
    $st = $script:PesState
    if ($st.Banner -and -not $st.Banner.IsDisposed) { return }
    $b = New-Object System.Windows.Forms.Form
    $b.FormBorderStyle = 'None'; $b.ShowInTaskbar = $false; $b.TopMost = $true; $b.StartPosition = 'Manual'
    $b.BackColor = $script:C.Danger; $b.ForeColor = [System.Drawing.Color]::White
    $b.Size = New-Object System.Drawing.Size(620, 34)
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $b.Location = New-Object System.Drawing.Point(($wa.Left + [int](($wa.Width - 620) / 2)), $wa.Top)
    $l = New-Object System.Windows.Forms.Label
    $l.Location = New-Object System.Drawing.Point(10, 7); $l.Size = New-Object System.Drawing.Size(470, 20)
    $l.Font = $script:FontBold; $l.ForeColor = [System.Drawing.Color]::White; $l.BackColor = [System.Drawing.Color]::Transparent
    $b.Controls.Add($l)
    $btn = New-PesButton -Text 'Beenden' -X 500 -Y 3 -W 112 -H 28 -Parent $b
    $btn.BackColor = [System.Drawing.Color]::FromArgb(60, 20, 16)
    $btn.Add_Click({ Stop-PesShareUi; Add-PesChatLine -Text (T 'Freigabe beendet.') })
    $st.Banner = $b; $st.BannerLabel = $l
    if (-not $script:PesSelbsttest) { $b.Show() }
}

function Hide-PesBanner {
    $b = $script:PesState.Banner
    $script:PesState.Banner = $null; $script:PesState.BannerLabel = $null
    if ($b -and -not $b.IsDisposed) { try { $b.Close(); $b.Dispose() } catch { } }
}

function Start-PesShareUi {
    param([bool]$Control)
    $h = $script:PesHost
    if (-not $h.Session -or -not $h.Session.Paired) { return }
    $st = $script:PesState
    if (-not $st.ShareUi) { $h.StartShare($Control) } else { $h.SetControl($Control) }
    $st.ShareUi = $true; $st.ControlUi = $Control
    Show-PesBanner
    $who = $h.Session.PartnerName
    if ($Control) { Add-PesChatLine -Text (T 'Bildschirm wird an {0} übertragen - mit Steuerung von Maus und Tastatur.' $who) -Kind 'warn' }
    else { Add-PesChatLine -Text (T 'Bildschirm wird an {0} übertragen - nur ansehen.' $who) -Kind 'warn' }
    Update-PesTexts
}

function Stop-PesShareUi {
    $st = $script:PesState
    if (-not $st.ShareUi -and -not $st.Banner) { return }
    try { $script:PesHost.StopShare() } catch { }
    $st.ShareUi = $false; $st.ControlUi = $false
    Hide-PesBanner
    Update-PesTexts
}

function Invoke-PesShareButton {
    $ses = $script:PesHost.Session
    if (-not $ses -or -not $ses.Paired) { return }
    if ($script:PesState.ShareUi) { Stop-PesShareUi; Add-PesChatLine -Text (T 'Freigabe beendet.'); return }
    $r = Show-PesAsk -Title (T 'Bildschirm freigeben') -Text ((T 'Soll {0} Ihren Bildschirm jetzt sehen können?' $ses.PartnerName) + $script:NL + $script:NL + (T 'Alles, was auf dem Bildschirm steht, wird übertragen. Sie können die Freigabe jederzeit beenden.')) -Buttons @((T 'Ja, freigeben'), (T 'Nein')) -Accent 1 -Owner $script:PesUi.Form
    if ($r -eq 0) { Start-PesShareUi -Control $false }
}

function Invoke-PesAllowButton {
    $ses = $script:PesHost.Session
    if (-not $ses -or -not $script:PesState.ShareUi) { return }
    if ($script:PesState.ControlUi) { Start-PesShareUi -Control $false; Add-PesChatLine -Text (T 'Steuerung gesperrt - der Helfer kann nur noch zusehen.'); return }
    $r = Show-PesAsk -Title (T 'Steuerung erlauben') -Text ((T 'Soll {0} Maus und Tastatur dieses PCs bedienen dürfen?' $ses.PartnerName) + $script:NL + $script:NL + (T 'Erlauben Sie das nur Personen, denen Sie vertrauen. Notfall-Stopp: Strg+Umschalt+F12')) -Buttons @((T 'Ja, erlauben'), (T 'Nein')) -Accent 1 -Owner $script:PesUi.Form
    if ($r -eq 0) { Start-PesShareUi -Control $true }
}

# Der Helfer bittet um Ansicht (1) oder Steuerung (2), beendet (3), gibt die Steuerung ab (4) oder braucht ein Komplettbild (5).
function Invoke-PesScreenRequest {
    param([int]$Sub)
    $st = $script:PesState
    $ses = $script:PesHost.Session
    if (-not $ses) { return }
    if ($Sub -eq 5) { if ($st.ShareUi -and $script:PesHost.Screen) { $script:PesHost.Screen.ForceFull() }; return }
    if ($Sub -eq 3) { if ($st.ShareUi) { Stop-PesShareUi; Add-PesChatLine -Text (T 'Der Helfer hat die Ansicht beendet.') }; return }
    if ($Sub -eq 4) { if ($st.ControlUi) { Start-PesShareUi -Control $false; Add-PesChatLine -Text (T 'Der Helfer hat die Steuerung abgegeben.') }; return }
    if ($Sub -eq 1 -and $st.ShareUi) { $script:PesHost.Screen.ForceFull(); return }
    if ($Sub -eq 2 -and $st.ControlUi) { return }
    if ($st.AskOpen) { return }                                         # schon eine Abfrage offen
    $st.AskOpen = $true
    try {
        $who = $ses.PartnerName
        if ($script:PesUi.Form.WindowState -eq 'Minimized' -or -not $script:PesUi.Form.Visible) { Show-PesMainWindow }
        if ($Sub -eq 1) {
            $r = Show-PesAsk -Title (T 'Anfrage des Helfers') -Text ((T '{0} möchte Ihren Bildschirm sehen.' $who) + $script:NL + $script:NL + (T 'Alles, was auf dem Bildschirm steht, wird übertragen. Sie können die Freigabe jederzeit beenden.')) -Buttons @((T 'Nur ansehen'), (T 'Ablehnen')) -Accent 0 -Owner $script:PesUi.Form
            if ($r -eq 0) { Start-PesShareUi -Control $false } else { Add-PesChatLine -Text (T 'Anfrage abgelehnt.'); Send-PesDeny }
        } elseif ($st.ShareUi) {
            $r = Show-PesAsk -Title (T 'Anfrage des Helfers') -Text ((T '{0} möchte zusätzlich Maus und Tastatur bedienen.' $who) + $script:NL + $script:NL + (T 'Erlauben Sie das nur Personen, denen Sie vertrauen. Notfall-Stopp: Strg+Umschalt+F12')) -Buttons @((T 'Erlauben'), (T 'Ablehnen')) -Accent 1 -Owner $script:PesUi.Form
            if ($r -eq 0) { Start-PesShareUi -Control $true } else { Add-PesChatLine -Text (T 'Anfrage abgelehnt.'); Send-PesDeny }
        } else {
            $r = Show-PesAsk -Title (T 'Anfrage des Helfers') -Text ((T '{0} möchte Ihren Bildschirm sehen und Maus und Tastatur bedienen.' $who) + $script:NL + $script:NL + (T 'Erlauben Sie das nur Personen, denen Sie vertrauen. Notfall-Stopp: Strg+Umschalt+F12')) -Buttons @((T 'Ansehen und steuern'), (T 'Nur ansehen'), (T 'Ablehnen')) -Accent 1 -Owner $script:PesUi.Form
            if ($r -eq 0) { Start-PesShareUi -Control $true }
            elseif ($r -eq 1) { Start-PesShareUi -Control $false }
            else { Add-PesChatLine -Text (T 'Anfrage abgelehnt.'); Send-PesDeny }
        }
    } finally { $st.AskOpen = $false }
}

# Ablehnung: der Helfer bekommt den unveränderten Freigabe-Zustand gemeldet und weiß damit Bescheid.
function Send-PesDeny {
    $ses = $script:PesHost.Session
    if (-not $ses) { return }
    if ($script:PesState.ShareUi) { $script:PesHost.SetControl([bool]$script:PesState.ControlUi) }
    else { $ses.SetShare($false, $false, 0, 0, 0, 1) }
}

function Show-PesMainWindow {
    $f = $script:PesUi.Form
    if (-not $f -or $f.IsDisposed) { return }
    try {
        $f.Show()
        if ($f.WindowState -eq 'Minimized') { $f.WindowState = 'Normal' }
        $f.Activate()
        [void][PesNative]::SetForegroundWindow($f.Handle)
    } catch { }
}

# ---- Ereignisse der Sitzung (kommen als Textzeilen aus dem Kern) ----
function Invoke-PesSessionEvent {
    param([string]$Line)
    $f = $Line.Split([PesProto]::Sep)
    $st = $script:PesState
    switch ($f[0]) {
        'PEER' {
            if ($f[1] -eq 'up') {
                $roleText = if ($f[3] -eq '1') { T 'Helfer' } else { T 'Kunde' }
                $plat = if ($f[4] -eq '2') { 'Android' } else { 'Windows' }
                Add-PesChatLine -Text (T '{0} ist verbunden ({1}, {2}).' $f[2] $roleText $plat) -Kind 'warn'
            } else {
                Add-PesChatLine -Text ((T '{0} ist nicht mehr verbunden.' $f[2]) + ' ' + [PesI18n]::Core($f[3])) -Kind 'warn'
                Stop-PesShareUi; Close-PesRing
                $st.ViewWanted = $false; $st.ControlWanted = $false; $st.ShareSeen = $false; $st.LastShareState = ''
                try { $script:PesUi.View.ClearImage() } catch { }
            }
        }
        'CHAT' { Add-PesChatLine -Who $f[1] -Text $f[2] -Kind 'peer' }
        'CALL' {
            switch ($f[1]) {
                'in' { Show-PesRing -Name $f[2] }
                'out' { Add-PesChatLine -Text (T 'Anruf gestartet ...') }
                'active' { Close-PesRing; $st.CamTried = $false; Add-PesChatLine -Text (T 'Anruf verbunden.') }
                'declined' { Add-PesChatLine -Text (T 'Der Partner hat den Anruf abgelehnt.') }
                'ended' { Close-PesRing; Add-PesChatLine -Text (T 'Anruf beendet.') }
                'missed' { Close-PesRing; Add-PesChatLine -Text (T 'Verpasster Anruf.') }
                'timeout' { Add-PesChatLine -Text (T 'Der Partner hat nicht abgenommen.') }
            }
        }
        'SCREEN' {
            if ($f[1] -eq 'req') { Invoke-PesScreenRequest -Sub ([int]$f[2]) }
            elseif ($f[1] -eq 'state') {
                # Derselbe Zustand kommt mehrfach (z. B. wenn sich nur die Bildgröße ändert): nur Wechsel melden
                $key = $f[2] + $f[3]
                if ($st.LastShareState -eq $key) { return }
                $st.LastShareState = $key
                if ($f[2] -eq '1') {
                    if ($f[3] -eq '1') { Add-PesChatLine -Text (T 'Der Kunde überträgt seinen Bildschirm - Steuerung erlaubt.') }
                    else {
                        if ($st.ControlWanted -and $st.ShareSeen) { Add-PesChatLine -Text (T 'Der Kunde erlaubt die Steuerung nicht (nur ansehen).') }
                        else { Add-PesChatLine -Text (T 'Der Kunde überträgt seinen Bildschirm - nur ansehen.') }
                    }
                    $st.ShareSeen = $true; $st.ControlWanted = $false
                } else {
                    if ($st.ViewWanted -and -not $st.ShareSeen) { Add-PesChatLine -Text (T 'Der Kunde hat die Anfrage abgelehnt.') }
                    else { Add-PesChatLine -Text (T 'Der Kunde überträgt seinen Bildschirm nicht mehr.') }
                    $st.ViewWanted = $false; $st.ControlWanted = $false; $st.ShareSeen = $false
                    try { $script:PesUi.View.ClearImage() } catch { }
                }
            }
        }
        'FILE' {
            switch ($f[1]) {
                'offer' {
                    $size = 0L; [void][long]::TryParse($f[4], [ref]$size)
                    $ses = $script:PesHost.Session
                    $r = Show-PesAsk -Title (T 'Datei empfangen') -Text ((T '{0} möchte Ihnen eine Datei senden:' $ses.PartnerName) + $script:NL + $script:NL + $f[3] + '  (' + (Format-PesSize $size) + ')' + $script:NL + $script:NL + (T 'Nehmen Sie nur Dateien an, die Sie erwarten. Gespeichert wird im Ordner "Downloads\Project Earth Support".')) -Buttons @((T 'Annehmen'), (T 'Ablehnen')) -Accent 1 -Owner $script:PesUi.Form
                    $err = $ses.AnswerFile(($r -eq 0))
                    if ($r -eq 0 -and -not $err) { Add-PesChatLine -Text (T 'Empfange Datei: {0}' $f[3]) }
                    elseif ($err) { Add-PesChatLine -Text ((T 'Datei kann nicht empfangen werden:') + ' ' + $err) -Kind 'err' }
                }
                'sending' { Add-PesChatLine -Text (T 'Sende Datei: {0}' $f[2]) }
                'declined' { Add-PesChatLine -Text (T 'Der Partner hat die Datei abgelehnt: {0}' $f[2]) }
                'sent' { Add-PesChatLine -Text (T 'Datei gesendet und geprüft: {0}' $f[2]) }
                'received' { Add-PesChatLine -Text (T 'Datei empfangen und geprüft: {0}' $f[3]) }
                'failed' { Add-PesChatLine -Text ((T 'Datei-Übertragung abgebrochen: {0}' $f[2]) + ' (' + [PesI18n]::Core($f[3]) + ')') -Kind 'err' }
                'withdrawn' { Add-PesChatLine -Text (T 'Das Datei-Angebot wurde zurückgezogen: {0}' $f[2]) }
            }
        }
        'SYS' { Add-PesChatLine -Text $f[1] -Kind 'err' }
    }
}

# ---- Zeitgeber: holt alle 100 ms Zustand und Ereignisse ab (die Oberfläche blockiert nie) ----
function Update-PesMain {
    $st = $script:PesState
    $u = $script:PesUi
    $h = $script:PesHost
    $st.Tick++
    Receive-PesJobs

    # Verbindungsaufbau im Hintergrund
    if ($st.Connecting) {
        if ($h.State -eq 2) { $st.Connecting = $false; $st.Connected = $true; Add-PesChatLine -Text (T 'Sitzung gestartet.') }
        elseif ($h.State -eq 3) {
            $st.Connecting = $false; $st.Connected = $false
            Add-PesChatLine -Text ((T 'Verbinden fehlgeschlagen:') + ' ' + [PesI18n]::Core($h.Error)) -Kind 'err'
            try { $h.Disconnect() } catch { }
        }
    }
    $eng = $h.Engine
    $ses = $h.Session
    if ($eng) {
        $line = $null
        while ($eng.Log.TryDequeue([ref]$line)) { Write-PesLog -Level 'P2P' -Message $line }
    }
    if ($ses) {
        $ev = $null
        $n = 0
        while ($n -lt 50 -and $ses.Events.TryDequeue([ref]$ev)) { $n++; try { Invoke-PesSessionEvent -Line $ev } catch { Write-PesLog -Level 'FEHLER' -Message ('Ereignis: ' + $_.Exception.Message) } }
    }

    # Klingeln bei eingehendem Anruf (Systemklang, kein Fremdprozess)
    if ($st.RingForm -and ($st.Tick % 20) -eq 1) { try { [System.Media.SystemSounds]::Exclamation.Play() } catch { } }

    if ($st.Connected -and $ses) {
        Sync-PesMedia
        # Kunde: Freigabe endet auch, wenn die Sitzung sie verliert (Partner weg) oder die Aufnahme stoppt
        if ($st.ShareUi -and -not $ses.ShareActive) { Stop-PesShareUi; Add-PesChatLine -Text (T 'Freigabe beendet.') }
        # Notfall-Stopp Strg+Umschalt+F12 (wird nur abgefragt, es gibt keinen Tastatur-Haken)
        $hot = (([PesNative]::GetAsyncKeyState(0x7B) -band 0x8000) -ne 0) -and (([PesNative]::GetAsyncKeyState(0x11) -band 0x8000) -ne 0) -and (([PesNative]::GetAsyncKeyState(0x10) -band 0x8000) -ne 0)
        if ($hot -and -not $st.LastHotkey -and $st.ShareUi) { Stop-PesShareUi; Add-PesChatLine -Text (T 'Notfall-Stopp: Freigabe beendet.') -Kind 'warn' }
        $st.LastHotkey = $hot
        if ($st.Banner -and $st.BannerLabel) {
            $bt = if ($st.ControlUi) { T 'Bildschirm wird übertragen an {0} - MIT STEUERUNG' $ses.PartnerName } else { T 'Bildschirm wird übertragen an {0}' $ses.PartnerName }
            if ($st.BannerLabel.Text -ne $bt) { $st.BannerLabel.Text = $bt }
        }
    }

    if (($st.Tick % 5) -eq 0) {
        # Statuszeile in der Seitenleiste
        $s1 = ''
        if ($eng -and ($st.Connected -or $st.Connecting)) {
            $s1 = [PesI18n]::Core($eng.State)
            if ($eng.AssignedIp) { $s1 = $s1 + '  (' + $eng.AssignedIp + ')' }
            if ($ses -and $ses.Paired) {
                foreach ($p in $eng.GetPeers()) {
                    if ($p.Vip -eq $ses.PartnerVip) {
                        $way = if ($p.Path -eq 1) { T 'direkt' } elseif ($p.Path -eq 2) { T 'über den Vermittler (Relay)' } else { T 'verbindet ...' }
                        $s1 = $s1 + $script:NL + (T 'Weg: {0}' $way)
                        if ($p.RttMs -ge 0) { $s1 = $s1 + ', ' + $p.RttMs + ' ms' }
                    }
                }
            }
        }
        if ($u.LblStatus.Text -ne $s1) { $u.LblStatus.Text = $s1 }

        # Datei-Fortschritt
        $ft = ''
        if ($ses) {
            $tx = $ses.TxFile; $rx = $ses.RxFile
            if ($tx -and ($tx.State -eq 1 -or $tx.State -eq 4)) { $ft = T 'Sende {0}: {1} von {2}' $tx.Name (Format-PesSize $tx.Done) (Format-PesSize $tx.Size) }
            elseif ($rx -and $rx.State -eq 1) { $ft = T 'Empfange {0}: {1} von {2}' $rx.Name (Format-PesSize $rx.Done) (Format-PesSize $rx.Size) }
            elseif ($tx -and $tx.State -eq 0) { $ft = T 'Warte auf Zustimmung: {0}' $tx.Name }
        }
        if ($u.LblFile.Text -ne $ft) { $u.LblFile.Text = $ft }

        # Bildschirm-Auswahl des Helfers an die Zahl der Bildschirme des Kunden anpassen
        if ($ses -and $ses.Role -eq 1 -and $ses.ShareActive -and $ses.ScreenMonitors -ne $st.LastMonitors -and $ses.ScreenMonitors -ge 1) {
            $st.LastMonitors = $ses.ScreenMonitors
            $sel = [Math]::Max(0, $u.CmbMonitor.SelectedIndex)
            $u.CmbMonitor.Items.Clear()
            for ($i = 1; $i -le $ses.ScreenMonitors; $i++) { [void]$u.CmbMonitor.Items.Add((T 'Bildschirm {0}' $i)) }
            $u.CmbMonitor.SelectedIndex = [Math]::Min($sel, $u.CmbMonitor.Items.Count - 1)
        }
        Update-PesTexts

        # Optionen-Fenster geschlossen: Einstellungen neu lesen
        if ($st.OptProc -and $st.OptProc.HasExited) {
            $st.OptProc = $null
            $keepRole = $script:PesSettings.Role
            $script:PesSettings = Read-PesSettings
            $script:PesSettings.Role = $keepRole
            $script:PesHost.EchoGate = [bool]$script:PesSettings.EchoGate
            if (-not $st.Connected -and -not $st.Connecting) { $u.TxtName.Text = [string]$script:PesSettings.Name }
            Set-PesLanguage
        }
        # Zweiter Programmstart: vorhandenes Fenster nach vorne holen
        if ($script:PesShowEvent -and $script:PesShowEvent.WaitOne(0)) { Show-PesMainWindow }
    }
}
