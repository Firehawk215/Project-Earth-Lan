# ==============================================================================
# Project Earth LAN - All in One Manager, Downloader & Game Finder
# Features: Admin-Elevated | Full White Text / Dark GUI | Progress Bar Dialogs
# ==============================================================================

# 0. OPTIONS-PARAMETER (getrennte Fenster): -Option <Nummer> startet nur diese Option
$Option = ''
for ($ai = 0; $ai -lt ($args.Count - 1); $ai++) {
    if ([string]$args[$ai] -eq '-Option') { $Option = [string]$args[$ai + 1] }
}
# -Autostart: vom Windows-Autostart (geplante Aufgabe, Button 12) gestartet -> Control
# Center minimiert öffnen.
$script:PelAutostartMode = $false
foreach ($a0 in $args) { if ([string]$a0 -eq '-Autostart') { $script:PelAutostartMode = $true } }
$script:IsCompiledExe = -not ($PSCommandPath -and $PSCommandPath -like '*.ps1')
if ($script:IsCompiledExe) {
    # Mit PS2EXE (oder aehnlichem) zu einer .exe kompiliert: $PSCommandPath ist dann leer
    # bzw. zeigt nicht mehr auf eine .ps1-Datei. Fuer alle Stellen, die sich selbst neu
    # starten (Admin-Erhoehung, einzelne Options-Fenster, Autostart), muss dann die
    # eigene .exe direkt erneut gestartet werden statt "powershell.exe -File ...".
    try { $script:SelfPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName } catch { $script:SelfPath = $null }
} else {
    $script:SelfPath = $PSCommandPath
}

# Versionsnummer dieses Builds. Format: YYYY.MM.DD, damit ein einfacher Textvergleich
# auch die zeitliche Reihenfolge richtig erkennt. Es gibt KEIN automatisches Update mehr:
# der Manager prueft beim Start nur (lesend) auf GitHub, ob dort eine neuere Version
# veroeffentlicht wurde, und zeigt dann im Live-Status einen Button, der die GitHub-Seite
# im Browser oeffnet - heruntergeladen und ersetzt wird ausschliesslich von Hand.
$script:PelVersion = "2026.09.22"
$script:PelGitHubUrl = "https://github.com/Firehawk215/Project-Earth-Lan"
$script:PelGitHubApiLatest = "https://api.github.com/repos/Firehawk215/Project-Earth-Lan/releases/latest"
$script:PelGitHubApiTags = "https://api.github.com/repos/Firehawk215/Project-Earth-Lan/tags"
$script:PelGitHubApiContents = "https://api.github.com/repos/Firehawk215/Project-Earth-Lan/contents/"
$script:PelGitHubRawVersion = "https://raw.githubusercontent.com/Firehawk215/Project-Earth-Lan/main/version.txt"

# ------------------------------------------------------------------------------
# SICHERHEIT: NETZWERK-SECRET (symmetrisch)
# ------------------------------------------------------------------------------
# $script:PelNetworkSecret: gemeinsames Secret (siehe network_code_tool.ps1), dient als
# HMAC-Schluessel, um Status-/Planer-/Postfach-Broadcasts als "echter" Project Earth LAN
# Manager zu kennzeichnen - Pakete ohne passende Signatur werden von allen Nodes ignoriert
# (Schutz vor Spoofing/Fremd-Software auf demselben Netz). Weil der Wert fest im Code
# steht, hat ihn automatisch jeder, der die offizielle .exe startet - ganz ohne manuelle
# Eingabe. Aendern: neuen Code mit network_code_tool.ps1 erzeugen, hier eintragen, neu
# kompilieren und die neue .exe ueber GitHub veroeffentlichen.
$script:PelNetworkSecret = "VOR_DEM_KOMPILIEREN_MIT_CODE_AUS_network_code_tool.ps1_ERSETZEN"

# Feste ZeroTier-Netzwerk-ID von Project Earth LAN (dieselbe, die Option 1 automatisch
# beitritt) - wird verwendet, um beim Adapterwechsel im Live-Status automatisch eine
# Verbindung aufzubauen, ohne dass die ID erneut eingegeben werden muss.
$script:PelNetworkId = "091f0945fc5012f1"

# HMAC-SHA256 ueber Text mit $script:PelNetworkSecret als Schluessel - fuer die Signatur
# von Beacon-/Status-Broadcasts (siehe oben, Punkt 2). Gibt Base64 zurueck.
function Get-PelHmacBase64 {
    param([string]$Text)
    try {
        $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($script:PelNetworkSecret)
        $hmac = New-Object System.Security.Cryptography.HMACSHA256(,$keyBytes)
        try {
            $hash = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text))
            return [Convert]::ToBase64String($hash)
        } finally { $hmac.Dispose() }
    } catch { return '' }
}

# Prueft eine per Get-PelHmacBase64 erzeugte Signatur.
function Test-PelHmac {
    param([string]$Text, [string]$Signature)
    if ([string]::IsNullOrEmpty($Signature)) { return $false }
    $expected = Get-PelHmacBase64 -Text $Text
    if ([string]::IsNullOrEmpty($expected)) { return $false }
    return ($expected -eq $Signature)
}

# Live-Status-Verbund (Control Center <-> Control Center, Port 9928): jeder offene
# Manager meldet seinen eigenen Live-Status (Name, IP, ZeroTier-Status, Freunde online,
# Version) per UDP-Broadcast und hört gleichzeitig auf die Meldungen aller anderen -
# so kennt jeder Manager im Netzwerk automatisch den Status aller anderen, ohne dass
# jemand aktiv nachfragen muss.
$script:PelStatusPort = 9928

# 1. ADMIN-RECHTE & KONSOLE EINRICHTEN
$Host.UI.RawUI.ForegroundColor = "White"
Clear-Host

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $optArg = ""
    if ($Option) { $optArg = " -Option $Option" }
    if ($script:PelAutostartMode) { $optArg += " -Autostart" }
    if (-not $script:IsCompiledExe -and $PSCommandPath) {
        Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"$optArg" -Verb RunAs
        exit
    } elseif ($script:IsCompiledExe -and $script:SelfPath) {
        # Als kompilierte .exe gestartet: die eigene .exe direkt mit erhoehten Rechten
        # neu starten (kein "powershell.exe -File" noetig, sie enthaelt das Skript bereits).
        try {
            Start-Process -FilePath $script:SelfPath -ArgumentList $optArg.Trim() -Verb RunAs
            exit
        } catch {
            Write-Warning "[DEBUG ERROR] Bitte starte den Project Earth LAN Manager als Administrator."
            return
        }
    } else {
        Write-Warning "[DEBUG ERROR] Bitte starte deine PowerShell-Konsole als Administrator."
        return
    }
}

# WinForms & System-Baugruppen laden
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Web

# ------------------------------------------------------------------------------
# HELPER & PROGRESS DIALOG FUNKTIONEN
# ------------------------------------------------------------------------------

function Show-ProgressDialog {
    param (
        [string]$Title,
        [scriptblock]$TaskScript
    )

    $pForm = New-Object System.Windows.Forms.Form
    $pForm.Text = $Title
    $pForm.Size = New-Object System.Drawing.Size(500, 190)
    $pForm.StartPosition = "CenterScreen"
    $pForm.FormBorderStyle = "FixedDialog"
    $pForm.MaximizeBox = $false
    $pForm.MinimizeBox = $false
    $pForm.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $pForm.ForeColor = [System.Drawing.Color]::White

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text = "Initialisiere Vorgang..."
    $lblStatus.Location = New-Object System.Drawing.Point(20, 20)
    $lblStatus.Size = New-Object System.Drawing.Size(445, 30)
    $lblStatus.ForeColor = [System.Drawing.Color]::White
    $lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $pForm.Controls.Add($lblStatus)

    $pb = New-Object System.Windows.Forms.ProgressBar
    $pb.Location = New-Object System.Drawing.Point(20, 55)
    $pb.Size = New-Object System.Drawing.Size(445, 25)
    $pb.Minimum = 0
    $pb.Maximum = 100
    $pb.Value = 0
    $pForm.Controls.Add($pb)

    $lblPercent = New-Object System.Windows.Forms.Label
    $lblPercent.Text = "0%"
    $lblPercent.Location = New-Object System.Drawing.Point(20, 90)
    $lblPercent.Size = New-Object System.Drawing.Size(445, 20)
    $lblPercent.TextAlign = "MiddleCenter"
    $lblPercent.ForeColor = [System.Drawing.Color]::LightGray
    $lblPercent.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)
    $pForm.Controls.Add($lblPercent)

    $updateProgress = {
        param([string]$statusText, [int]$percentValue)
        if ($statusText) { $lblStatus.Text = $statusText }
        if ($percentValue -ge 0 -and $percentValue -le 100) {
            $pb.Value = $percentValue
            $lblPercent.Text = "$percentValue%"
        }
        [System.Windows.Forms.Application]::DoEvents()
    }

    $pForm.Add_Shown({
        try {
            &$TaskScript $updateProgress
            Start-Sleep -Milliseconds 600
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Fehler während des Vorgangs:`n$($_.Exception.Message)", "Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        } finally {
            $pForm.Close()
        }
    })

    [void]$pForm.ShowDialog()
}

function Get-ZeroTierCli {
    $cliExe = "$env:ProgramFiles\ZeroTier\One\zerotier-cli.exe"
    if (Test-Path $cliExe) { return $cliExe }
    $cliExe32 = "${env:ProgramFiles(x86)}\ZeroTier\One\zerotier-cli.exe"
    if (Test-Path $cliExe32) { return $cliExe32 }
    return "zerotier-cli"
}

# Robuster Parser für "zerotier-cli listnetworks". Die Zeilen sind zwar
# leerzeichengetrennt, aber der Netzwerkname (2. Feld) kann selbst Leerzeichen
# enthalten (z. B. "Project Earth Lan") - eine feste Positions-Regex bricht dann und
# meldet die Verbindung fälschlich als "nicht verbunden", obwohl sie tatsächlich OK ist.
# Deshalb wird hier von beiden Enden geparst: die letzten 5 Felder (MAC, Status, Typ,
# Gerät, IP-Liste) sind immer einzelne Tokens ohne Leerzeichen, alles dazwischen ist der
# (möglicherweise mehrteilige) Name.
function Get-PelZtNetworkStatusList {
    $cli = Get-ZeroTierCli
    $out = & $cli listnetworks 2>&1
    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($ln in $out) {
        if ($ln -notmatch '^200\s+listnetworks\s+') { continue }
        $tokens = @(-split $ln)
        if ($tokens.Count -lt 9) { continue }
        $nwid = $tokens[2]
        $status = $tokens[$tokens.Count - 4]
        $dev = $tokens[$tokens.Count - 2]
        $ipList = $tokens[$tokens.Count - 1]
        $nameEndIdx = $tokens.Count - 6
        $name = if ($nameEndIdx -ge 3) { ($tokens[3..$nameEndIdx] -join ' ') } else { '' }
        $ip = ''
        if ($ipList -match '((?:\d{1,3}\.){3}\d{1,3})') { $ip = $matches[1] }
        $result.Add([pscustomobject]@{ Id = $nwid; Name = $name; Status = $status; Dev = $dev; Ip = $ip })
    }
    return $result
}

function Get-ZeroTierNetworkIP {
    param ([string]$NetID)
    $cli = Get-ZeroTierCli
    $maxRetries = 15
    $retryCount = 0
    
    while ($retryCount -lt $maxRetries) {
        $output = & $cli listnetworks 2>&1
        $line = $output | Where-Object { $_ -match $NetID }
        if ($line) {
            if ($line -match '(\b(?:[0-9]{1,3}\.){3}[0-9]{1,3})\/\d+') {
                return $matches[1]
            }
        }
        Start-Sleep -Seconds 1.5
        $retryCount++
    }
    return $null
}

# ------------------------------------------------------------------------------
# NEUE VERSION AUF GITHUB? (nur lesen - es wird NICHTS heruntergeladen oder ersetzt)
# ------------------------------------------------------------------------------
# Die fruehere automatische Update-Verteilung (zentraler Server + P2P ueber Port 9777)
# wurde komplett entfernt. Stattdessen schaut das Control Center beim Start und danach
# alle 6 Stunden auf GitHub nach, ob dort eine neuere Version liegt als dieser Build
# ($script:PelVersion). Wenn ja, erscheint im Live-Status der Button "Neue Version auf
# GitHub", der nur die GitHub-Seite im Browser oeffnet - herunterladen und ersetzen
# macht jeder selbst. Damit kann niemand ueber das Netzwerk fremden Code einschleusen.
#
# Wo gesucht wird (alles oeffentlich lesbar, keine Anmeldung, kein Token):
#   1. neuestes Release (Tag und Titel, z. B. "v2026.09.29" oder "Stand 29.09.2026")
#   2. Tags des Repositorys
#   3. Dateinamen im Hauptverzeichnis (.ps1/.exe/.zip/.7z/.rar/.msi), z. B.
#      "Project Earth Lan Manager 29.09.2026.ps1"
#   4. optional eine version.txt im Hauptverzeichnis (erste Zeile = Version)
# Erkannt werden Datumsangaben als JJJJ.MM.TT und TT.MM.JJJJ (auch mit - oder _).
# Daten, die mehr als 2 Tage in der Zukunft liegen, werden ignoriert (Tippfehler).
# Laeuft in einem eigenen Runspace, die Oberflaeche friert dabei nicht ein.
$script:PelGitHubLatest = ''
$script:PelGitHubCheckScript = {
    param([string]$ApiLatest, [string]$ApiTags, [string]$ApiContents, [string]$RawVersion)
    $state = @{ Best = ''; Src = ''; Ok = $false }
    $maxAllowed = (Get-Date).AddDays(2).ToString('yyyy.MM.dd')
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

    function Add-PelFoundVersion([string]$Text, [string]$Source) {
        if ([string]::IsNullOrWhiteSpace($Text)) { return }
        $found = @()
        foreach ($m in [regex]::Matches($Text, '(?<!\d)(20\d\d)[._-](\d{1,2})[._-](\d{1,2})(?!\d)')) {
            $found += ,@([int]$m.Groups[1].Value, [int]$m.Groups[2].Value, [int]$m.Groups[3].Value)
        }
        foreach ($m in [regex]::Matches($Text, '(?<!\d)(\d{1,2})[._-](\d{1,2})[._-](20\d\d)(?!\d)')) {
            $found += ,@([int]$m.Groups[3].Value, [int]$m.Groups[2].Value, [int]$m.Groups[1].Value)
        }
        foreach ($f in $found) {
            if ($f[1] -lt 1 -or $f[1] -gt 12 -or $f[2] -lt 1 -or $f[2] -gt 31) { continue }
            $v = '{0:D4}.{1:D2}.{2:D2}' -f $f[0], $f[1], $f[2]
            if ($v -gt $maxAllowed) { continue }
            if ($v -gt $state.Best) { $state.Best = $v; $state.Src = $Source }
        }
    }
    function Get-PelWebText([string]$Url) {
        try {
            $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 12 -UserAgent 'ProjectEarthLanManager' -ErrorAction Stop
            $state.Ok = $true
            $c = $r.Content
            if ($c -is [byte[]]) { $c = [System.Text.Encoding]::UTF8.GetString($c) }
            return [string]$c
        } catch { return $null }
    }
    function Get-PelJsonNames([string]$Json, [string]$Field) {
        $names = @()
        if (-not $Json) { return $names }
        foreach ($m in [regex]::Matches($Json, '"' + $Field + '"\s*:\s*"((?:[^"\\]|\\.)*)"')) { $names += $m.Groups[1].Value }
        return $names
    }

    $rel = Get-PelWebText $ApiLatest
    foreach ($n in (Get-PelJsonNames $rel 'tag_name')) { Add-PelFoundVersion $n "Release $n" }
    foreach ($n in (Get-PelJsonNames $rel 'name')) { Add-PelFoundVersion $n "Release $n" }
    $tags = Get-PelWebText $ApiTags
    foreach ($n in (Get-PelJsonNames $tags 'name')) { Add-PelFoundVersion $n "Tag $n" }
    $files = Get-PelWebText $ApiContents
    foreach ($n in (Get-PelJsonNames $files 'name')) {
        if ($n -match '(?i)\.(ps1|exe|zip|7z|rar|msi)$') { Add-PelFoundVersion $n "Datei $n" }
    }
    $vt = Get-PelWebText $RawVersion
    if ($vt) {
        $first = @($vt -split "`r?`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1)
        if ($first.Count -gt 0) { Add-PelFoundVersion ([string]$first[0]) 'version.txt' }
    }
    return [pscustomobject]@{ Ok = [bool]$state.Ok; Latest = [string]$state.Best; Source = [string]$state.Src }
}

# Oeffnet die GitHub-Seite des Projekts im Standardbrowser.
function Open-PelGitHubPage {
    try { Start-Process $script:PelGitHubUrl | Out-Null } catch {
        try { Start-Process 'explorer.exe' -ArgumentList $script:PelGitHubUrl | Out-Null } catch { }
    }
}

# ------------------------------------------------------------------------------
# ZENTRALE NETZWERKADAPTER-AUSWAHL (Control Center -> Live-Status -> "Adapter wechseln")
# ------------------------------------------------------------------------------
# Statt in jedem einzelnen Options-Fenster (Kommunikationszentrale, Server-Browser, ...)
# erneut nach dem Adapter zu fragen, wird die Auswahl einmal hier getroffen und in einer
# gemeinsamen Datei gespeichert. Jedes Options-Fenster liest sie beim Start und startet
# seine Netzwerk-Dienste direkt damit, ohne den Nutzer noch einmal zu fragen.
$script:PelAdapterConfigPath = "C:\Project-Earth-Lan\selected_adapter.json"

function Get-PelAdapterList {
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($nic in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        if ($nic.OperationalStatus -ne [System.Net.NetworkInformation.OperationalStatus]::Up) { continue }
        if ($nic.NetworkInterfaceType -eq [System.Net.NetworkInformation.NetworkInterfaceType]::Loopback) { continue }
        if ($nic.NetworkInterfaceType -eq [System.Net.NetworkInformation.NetworkInterfaceType]::Tunnel) { continue }
        foreach ($ua in $nic.GetIPProperties().UnicastAddresses) {
            if ($ua.Address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { continue }
            $ip = $ua.Address.ToString()
            if ($ip.StartsWith('169.254.')) { continue }
            $mask = '255.255.255.0'
            if ($ua.IPv4Mask) { $mask = $ua.IPv4Mask.ToString() }
            $metric = 0
            try {
                $ifc = Get-NetIPInterface -InterfaceAlias $nic.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($ifc) { $metric = [int]$ifc.InterfaceMetric }
            } catch { }
            $list.Add([pscustomobject]@{
                Name        = $nic.Name
                Description = $nic.Description
                Ip          = $ip
                Mask        = $mask
                Metric      = $metric
                IsZeroTier  = [bool](($nic.Description -match 'ZeroTier') -or ($nic.Name -match 'ZeroTier'))
            })
        }
    }
    return $list
}

# Automatische Adapter-Wahl beim ersten Öffnen (noch nichts zentral gewählt): es gewinnt
# der Adapter mit der niedrigsten Schnittstellenmetrik unter allen aktiven IPv4-Adaptern
# (Windows priorisiert Routen mit der niedrigsten Metrik, das ist also der Adapter, den
# Windows selbst als bevorzugte Verbindung verwendet).
function Get-PelAutoAdapter {
    $all = @(Get-PelAdapterList)
    if ($all.Count -eq 0) { return $null }
    return ($all | Sort-Object -Property Metric | Select-Object -First 1)
}

# Stellt sicher, dass der gewählte Adapter (falls ZeroTier) auch wirklich mit dem
# Project Earth LAN Netzwerk verbunden ist - wird bei jedem Adapterwechsel aufgerufen,
# damit "Adapter wechseln" nicht nur die Auswahl speichert, sondern auch aktiv eine
# Verbindung aufbaut (wie zuvor nur Option 2 "Netzwerk Login" es tat).
function Connect-PelZeroTierNetwork {
    param($Adapter)
    if (-not $Adapter -or -not $Adapter.IsZeroTier) { return }
    try {
        $cli = Get-ZeroTierCli
        $already = [bool](@(Get-PelZtNetworkStatusList) | Where-Object { $_.Id -eq $script:PelNetworkId -and $_.Status -eq 'OK' })
        if (-not $already) {
            & $cli join $script:PelNetworkId 2>&1 | Out-Null
        }
        $adNic = Get-NetIPAddress -IPAddress $Adapter.Ip -ErrorAction SilentlyContinue | Get-NetAdapter -ErrorAction SilentlyContinue
        if ($adNic) {
            Set-NetIPInterface -InterfaceIndex $adNic.InterfaceIndex -AddressFamily IPv4 -InterfaceMetric 1 -ErrorAction SilentlyContinue
            Set-NetIPInterface -InterfaceIndex $adNic.InterfaceIndex -AddressFamily IPv4 -NlMtuBytes 1380 -ErrorAction SilentlyContinue
        }
    } catch { }
}

# Liest die zentral gespeicherte Adapter-Auswahl und prüft, ob sie noch existiert/aktiv
# ist (IP-Abgleich gegen die aktuell aktiven Adapter) - liefert $null, wenn noch nichts
# gewählt wurde oder der gespeicherte Adapter gerade nicht verfügbar ist.
function Get-PelSelectedAdapter {
    try {
        if (-not (Test-Path -LiteralPath $script:PelAdapterConfigPath)) { return $null }
        $saved = Get-Content -LiteralPath $script:PelAdapterConfigPath -Raw | ConvertFrom-Json
        if (-not $saved -or -not $saved.Ip) { return $null }
        $current = @(Get-PelAdapterList) | Where-Object { $_.Ip -eq $saved.Ip } | Select-Object -First 1
        return $current
    } catch {
        return $null
    }
}

function Save-PelSelectedAdapter {
    param($Adapter)
    try {
        $dir = Split-Path -Parent $script:PelAdapterConfigPath
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        $Adapter | Select-Object Name, Description, Ip, Mask | ConvertTo-Json | Set-Content -LiteralPath $script:PelAdapterConfigPath -Encoding UTF8
    } catch { }
}

# Gemeinsamer Auswahldialog (Control Center -> "Adapter wechseln"). $ParentForm ist
# optional (für die Zentrierung über dem aufrufenden Fenster).
function Select-PelNetworkAdapter {
    param($ParentForm = $null)
    $adapters = @(Get-PelAdapterList)
    if ($adapters.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Es wurde kein aktiver IPv4-Netzwerkadapter gefunden.", "Netzwerkadapter", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return $null
    }
    $current = Get-PelSelectedAdapter

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Netzwerkadapter wählen"
    $dlg.Size = New-Object System.Drawing.Size(700, 380)
    $dlg.StartPosition = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $dlg.ForeColor = [System.Drawing.Color]::White

    $fontMainDlg = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Regular)
    $fontBoldDlg = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

    $lblHint = New-Object System.Windows.Forms.Label
    $lblHint.Text = "Adapter für LAN/ZeroTier auswählen (ZeroTier-Adapter sind grün markiert). Gilt für alle Fenster (Chat/Voice, Server-Browser, ...)."
    $lblHint.Location = New-Object System.Drawing.Point(12, 12)
    $lblHint.Size = New-Object System.Drawing.Size(660, 22)
    $lblHint.ForeColor = [System.Drawing.Color]::White
    $lblHint.Font = $fontMainDlg
    $dlg.Controls.Add($lblHint)

    $lv = New-Object System.Windows.Forms.ListView
    $lv.Location = New-Object System.Drawing.Point(12, 40)
    $lv.Size = New-Object System.Drawing.Size(660, 240)
    $lv.View = "Details"
    $lv.FullRowSelect = $true
    $lv.HideSelection = $false
    $lv.MultiSelect = $false
    $lv.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
    $lv.ForeColor = [System.Drawing.Color]::White
    $lv.Font = $fontMainDlg
    [void]$lv.Columns.Add("Adapter", 150)
    [void]$lv.Columns.Add("Beschreibung", 260)
    [void]$lv.Columns.Add("IPv4", 120)
    [void]$lv.Columns.Add("Maske", 110)
    $dlg.Controls.Add($lv)

    $preselect = $null
    foreach ($a in $adapters) {
        $it = New-Object System.Windows.Forms.ListViewItem($a.Name)
        [void]$it.SubItems.Add($a.Description)
        [void]$it.SubItems.Add($a.Ip)
        [void]$it.SubItems.Add($a.Mask)
        $it.Tag = $a
        if ($a.IsZeroTier) { $it.ForeColor = [System.Drawing.Color]::LightGreen }
        [void]$lv.Items.Add($it)
        if (-not $preselect) {
            if ($current -and $current.Ip -eq $a.Ip) { $preselect = $it }
            elseif (-not $current -and $a.IsZeroTier) { $preselect = $it }
        }
    }
    if (-not $preselect) { $preselect = $lv.Items[0] }
    $preselect.Selected = $true

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "Übernehmen"
    $btnOk.Location = New-Object System.Drawing.Point(400, 295)
    $btnOk.Size = New-Object System.Drawing.Size(130, 34)
    $btnOk.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnOk.ForeColor = [System.Drawing.Color]::White
    $btnOk.FlatStyle = "Flat"
    $btnOk.Font = $fontBoldDlg
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dlg.Controls.Add($btnOk)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Abbrechen"
    $btnCancel.Location = New-Object System.Drawing.Point(542, 295)
    $btnCancel.Size = New-Object System.Drawing.Size(130, 34)
    $btnCancel.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
    $btnCancel.ForeColor = [System.Drawing.Color]::White
    $btnCancel.FlatStyle = "Flat"
    $btnCancel.Font = $fontBoldDlg
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($btnCancel)

    $lv.Add_DoubleClick({ $btnOk.PerformClick() })
    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnCancel

    $result = $null
    $ownerArg = if ($ParentForm) { $ParentForm } else { $null }
    $dlgResult = if ($ownerArg) { $dlg.ShowDialog($ownerArg) } else { $dlg.ShowDialog() }
    if ($dlgResult -eq [System.Windows.Forms.DialogResult]::OK -and $lv.SelectedItems.Count -gt 0) {
        $result = $lv.SelectedItems[0].Tag
        Save-PelSelectedAdapter -Adapter $result
    }
    $dlg.Dispose()
    return $result
}

# ------------------------------------------------------------------------------
# SPIEL-EXE-AUSWAHL, WHITELIST & BLACKLIST (Option 7, Option 8, "Mitspielen")
# ------------------------------------------------------------------------------
# Früher wurde einfach die GRÖSSTE .exe im Spielordner genommen. Das traf oft daneben:
# .NET-Installer in _CommonRedist (80 MB), Dedicated Server (BF1942_w32ded.exe ist
# größer als BF1942.exe), Editoren (UnrealEd.exe > UT2004.exe), HLTV-Proxy (hltv.exe >
# hl.exe), Modell-Tools in bin\ (studiomdl.exe > left4dead2.exe), mitgelieferte
# ffmpeg.exe, EA-Installer (__Installer\Touchup.exe) usw. Jetzt gilt:
#   1. Ordner mit Installern, Redistributables, Anticheat, Tools, Engine-Dateien usw.
#      werden gar nicht erst durchsucht (max. 6 Ebenen tief).
#   2. EXEs mit eindeutigen Nicht-Spiel-Namen werden aussortiert (Installer, Updater,
#      Crash-Reporter, Server, Editoren, Browser-Hilfsprozesse, Laufzeitumgebungen ...).
#   3. Die übrigen werden bewertet: Name passt zum Spiel/Ordner (auch Kürzel wie UT2004,
#      BF1942, GTA5, CSGO), bekannte Spiel-EXE aus den Join-Regeln, Multiplayer-EXE
#      (iw3mp statt iw3sp), geringe Ordnertiefe, plausible Größe. Launcher zählen nur,
#      wenn sonst nichts übrig bleibt (z. B. Minecraft Launcher).
# Eigene Korrekturen: C:\Project-Earth-Lan\exe_korrekturen.txt (siehe Option 7 ->
# "Eigene Listen") hat immer Vorrang vor der automatischen Auswahl.
$script:PelExeExcludeDirs = '(?i)^(_?_?commonredist|__installer|_installer|installers?|redists?|redistributables?|_redist|directx\w*|dx9|dxsetup|vcredist\w*|vc_?redist\w*|dotnet\w*|netfx\w*|physx\w*|prerequisites?|_?prereqs?|dependencies|support|easyanticheat\w*|battleye|punkbuster|pb|monobleedingedge|mods?|tools?|sdk|editors?|docs?|documentation|manuals?|extras|soundtrack|ost|artbook|bonus|goodies|wallpapers?|screenshots|crashreports?|logs?|cache|shadercache|shader_cache|thirdparty|third_party|engine|__overlay|_overlay|launcher_data|steam_settings|uninstall\w*|setup|install)$'
$script:PelExeExcludeNames = '(?i)^(unins\d*|uninst.*|uninstall.*|.*setup.*|.*install|.*installer.*|.*update|.*updater.*|.*patch|.*patcher.*|autorun|autoplay|touchup|cleanup|repair.*|activation.*|register.*|dxwebsetup|dxsetup|vc_?redist.*|vcredist.*|dotnetfx.*|ndp\d+.*|oalinst|physx.*|directx.*|xnafx.*|.*prereq.*|.*redist.*|crash|.*crash(handler|reporter|report|sender|pad|dump|mon).*|.*errorreport.*|.*bugreport.*|report.*|feedback.*|.*support.*|sysinfo.*|dxdiag.*|.*diag|.*diagnostics?|systemcheck.*|.*benchmark.*|easyanticheat.*|eac|eac_launcher|.*_be|beservice.*|battleye.*|be_launcher|pnkbstr.*|pbsvc.*|punkbuster.*|uplay.*|upc|origin.*|eadesktop|eabackground.*|gfwl.*|securom.*|steamservice|steamerrorreporter.*|gameoverlayui.*|.*browser.*|cef.*|.*cefsharp.*|.*cefprocess.*|.*subprocess.*|.*webhelper.*|.*webengine.*|qtwebengineprocess|node|python\d*w?|java|javaw|ffmpeg|ffprobe|ffplay|7za?|7z|unzip|zip|curl|wget|lua\d*|luac\d*|perl|.*editor.*|unrealed|ued|world ?builder|.*sdk.*|hammer|hammerplusplus|studiomdl|hlmv|vbsp|vvis|vrad|vpk|shadercompile.*|captioncompiler|.*compiler.*|.*viewer.*|.*modeler.*|.*converter.*|.*config|.*configurator|.*configtool|.*settings|.*options|.*language.*|langselect.*|.*server.*|.*dedicated.*|.*_ded|.*w32ded|.*-ds|srcds.*|hlds.*|hltv|ucc|.*tool|.*tools|.*toolkit|.*helper.*|.*service|.*agent|.*monitor|.*daemon|.*uploader|.*downloader|.*unpack.*|.*extract.*|.*decompress.*|.*convert.*|.*verify.*|dosbox|scummvm|unitycrashhandler(32|64)?|.*handler)$'
$script:PelExeGoodDirs = '(?i)^(bin|bin32|bin64|binaries|win32|win64|x64|x86|system|system64|game|retail|shipping)$'
$script:PelRomanOrNumber = '^(\d+|i{1,3}|iv|v|vi{1,3}|ix|x)$'

function ConvertTo-PelCompactName([string]$s) {
    return ((([string]$s).ToLowerInvariant()) -replace "[’'`´]", '' -replace '[^a-z0-9]', '')
}

# Kürzel eines Spielnamens: "Unreal Tournament 2004" -> ut2004, "Grand Theft Auto V" ->
# gta5/gtav, "Counter-Strike Global Offensive" -> csgo, "Call of Duty 4 ..." -> cod4.
function Get-PelNameAcronyms([string]$Name) {
    $words = @((([string]$Name).ToLowerInvariant() -replace "[’'`´]", '') -split '[^a-z0-9]+' | Where-Object { $_ })
    if ($words.Count -lt 2) { return @() }
    $roman = @{ 'ii' = '2'; 'iii' = '3'; 'iv' = '4'; 'v' = '5'; 'vi' = '6'; 'vii' = '7'; 'viii' = '8'; 'ix' = '9'; 'x' = '10' }
    $a = ''; $b = ''; $c = ''; $cDone = $false
    foreach ($w in $words) {
        if ($w -match '^\d+$') {
            $a += $w; $b += $w
            if (-not $cDone) { $c += $w; $cDone = $true }
        } elseif ($roman.ContainsKey($w) -and $a.Length -gt 0) {
            $a += $roman[$w]; $b += $w
            if (-not $cDone) { $c += $roman[$w]; $cDone = $true }
        } else {
            $a += $w.Substring(0, 1); $b += $w.Substring(0, 1)
            if (-not $cDone) { $c += $w.Substring(0, 1) }
        }
    }
    return @(@($a, $b, $c) | Where-Object { $_.Length -ge 2 } | Select-Object -Unique)
}

# Alle Zahlen aus einem Spielnamen (auch römische): "Battlefield 1942" -> 1942,
# "Diablo II" -> 2.
function Get-PelNameNumbers([string]$Name) {
    $roman = @{ 'ii' = '2'; 'iii' = '3'; 'iv' = '4'; 'v' = '5'; 'vi' = '6'; 'vii' = '7'; 'viii' = '8'; 'ix' = '9'; 'x' = '10' }
    $out = @()
    $i = 0
    foreach ($w in @(([string]$Name).ToLowerInvariant() -split '[^a-z0-9]+' | Where-Object { $_ })) {
        if ($w -match '^\d+$') { $out += $w }
        elseif ($i -gt 0 -and $roman.ContainsKey($w)) { $out += $roman[$w] }
        $i++
    }
    return $out
}

# Verzeichnisse, die nie selbst ein einzelnes Spiel sind (Laufwerkswurzel, Programme-
# Ordner, Sammelordner wie "Games", "steamapps\common", "EA Games" ...). Manche Programme
# tragen so etwas als Installationsort in die Registry ein - dann würde sonst ein ganzes
# Laufwerk oder alle Spiele auf einmal durchsucht und eine beliebige EXE verknüpft.
function Test-PelUnsafeGameRoot([string]$Path) {
    if (-not $Path) { return $true }
    try { $full = [System.IO.Path]::GetFullPath($Path.Trim().TrimEnd('\', '/')) } catch { return $true }
    $root = [System.IO.Path]::GetPathRoot($full)
    if (-not $root -or ($full.TrimEnd('\', '/') -ieq $root.TrimEnd('\', '/'))) { return $true }
    if ($env:windir -and $full.StartsWith($env:windir, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    $leaf = [System.IO.Path]::GetFileName($full).ToLowerInvariant()
    $containers = @('windows', 'program files', 'program files (x86)', 'programdata', 'users', 'appdata', 'local', 'roaming', 'documents', 'desktop', 'downloads',
        'games', 'spiele', 'xboxgames', 'steam', 'steamlibrary', 'steamapps', 'common', 'epic games', 'gog games', 'gog galaxy', 'origin games', 'ea games',
        'electronic arts', 'ubisoft', 'ubisoft game launcher', 'elamigos', 'games (x86)')
    return ($containers -contains $leaf)
}

# Sammelt .exe-Dateien unterhalb eines Spielordners (höchstens 6 Ebenen, ohne Junctions,
# ohne die Ausschluss-Ordner oben). Begrenzt auf 20.000 Ordner / 4.000 EXEs.
function Get-PelExeCandidates([string]$Root, [int]$MaxDepth = 6, [switch]$NoDirExclusions) {
    $list = New-Object System.Collections.Generic.List[object]
    $stack = New-Object System.Collections.Generic.Stack[object]
    $stack.Push([pscustomobject]@{ Dir = $Root; Depth = 0 })
    $dirCount = 0
    while ($stack.Count -gt 0) {
        $it = $stack.Pop()
        $dirCount++
        if ($dirCount -gt 20000) { break }
        try {
            foreach ($f in [System.IO.Directory]::EnumerateFiles($it.Dir, '*.exe')) {
                if (-not $f.EndsWith('.exe', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                $list.Add([pscustomobject]@{ Path = $f; Depth = $it.Depth })
                if ($list.Count -ge 4000) { return $list.ToArray() }
            }
        } catch { }
        if ($it.Depth -ge $MaxDepth) { continue }
        try {
            foreach ($d in [System.IO.Directory]::EnumerateDirectories($it.Dir)) {
                $leaf = [System.IO.Path]::GetFileName($d)
                if (-not $NoDirExclusions -and $leaf -match $script:PelExeExcludeDirs) { continue }
                try { if (([System.IO.File]::GetAttributes($d) -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue } } catch { continue }
                $stack.Push([pscustomobject]@{ Dir = $d; Depth = $it.Depth + 1 })
            }
        } catch { }
    }
    return $list.ToArray()
}

# Wählt die Spiel-EXE in einem Ordner. Rückgabe: Objekt mit Path, Score, Reason (kurze
# Begründung für das Protokoll) - oder $null, wenn keine brauchbare EXE gefunden wurde.
function Select-PelGameExe {
    param([string]$Folder, [string]$GameName = '', [string[]]$PreferredNames = @())
    if (-not $Folder -or -not [System.IO.Directory]::Exists($Folder)) { return $null }
    $rootFull = [System.IO.Path]::GetFullPath($Folder).TrimEnd('\', '/')
    $gComp = ConvertTo-PelCompactName $GameName
    $fComp = ConvertTo-PelCompactName ([System.IO.Path]::GetFileName($rootFull))
    $targets = @(@($gComp, $fComp) | Where-Object { $_ } | Select-Object -Unique)
    $acr = @(@(Get-PelNameAcronyms $GameName) + @(Get-PelNameAcronyms ([System.IO.Path]::GetFileName($rootFull))) | Select-Object -Unique)
    $nums = @(@(Get-PelNameNumbers $GameName) + @(Get-PelNameNumbers ([System.IO.Path]::GetFileName($rootFull))) | Select-Object -Unique)
    $firstLetters = @(@($gComp, $fComp) | Where-Object { $_ } | ForEach-Object { $_.Substring(0, 1) } | Select-Object -Unique)
    $pref = @($PreferredNames | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLowerInvariant() })
    $known = $script:PelKnownGameExes

    foreach ($pass in 1..2) {
        $cands = if ($pass -eq 1) { @(Get-PelExeCandidates -Root $rootFull) } else { @(Get-PelExeCandidates -Root $rootFull -NoDirExclusions) }
        $scored = New-Object System.Collections.Generic.List[object]
        foreach ($c in $cands) {
            $leaf = [System.IO.Path]::GetFileName($c.Path)
            $leafL = $leaf.ToLowerInvariant()
            $base = [System.IO.Path]::GetFileNameWithoutExtension($leaf)
            $baseL = $base.ToLowerInvariant()
            if ($baseL -match $script:PelExeExcludeNames) { continue }
            $x = ConvertTo-PelCompactName $base
            if (-not $x) { continue }
            $size = [int64]0
            try { $size = (New-Object System.IO.FileInfo($c.Path)).Length } catch { }
            $score = 0
            $why = New-Object System.Collections.Generic.List[string]

            # Name
            $ns = 0
            foreach ($t in $targets) {
                if ($x -eq $t) { $ns = [Math]::Max($ns, 60) }
                elseif ($t.Length -ge 4 -and $x.Contains($t)) { $ns = [Math]::Max($ns, 40) }
                elseif ($x.Length -ge 3 -and $t.Contains($x)) { $ns = [Math]::Max($ns, 30) }
            }
            foreach ($a in $acr) {
                if ($x -eq $a) { $ns = [Math]::Max($ns, 50) }
                elseif ($a.Length -ge 3 -and $x.Contains($a)) { $ns = [Math]::Max($ns, 35) }
                elseif ($x.Length -ge 3 -and $a.Contains($x)) { $ns = [Math]::Max($ns, 30) }
            }
            if ($ns -lt 25) {
                foreach ($n in $nums) {
                    if ($x.Contains($n) -and ($firstLetters -contains $x.Substring(0, 1))) { $ns = 25; break }
                }
            }
            if ($ns -gt 0) { $score += $ns; $why.Add('Name passt') }
            if ($pref -contains $leafL) { $score += 50; $why.Add('bekannte Spiel-EXE') }
            elseif ($known -and $known.ContainsKey($leafL)) { $score += 45; $why.Add('bekannte Spiel-EXE') }

            # Multiplayer bevorzugen (LAN!), Singleplayer-Varianten abwerten
            if ($baseL -match '(mp|multiplayer|multi|online)$|(^|[^a-z])mp([^a-z]|$)') { $score += 15; $why.Add('Multiplayer') }
            elseif ($baseL -match '(sp|singleplayer|single|campaign)$|(^|[^a-z])sp([^a-z]|$)') { $score -= 10 }

            # Ordnertiefe und typische Programmordner
            switch ([int]$c.Depth) { 0 { $score += 15 } 1 { $score += 10 } 2 { $score += 5 } }
            $parentLeaf = [System.IO.Path]::GetFileName([System.IO.Path]::GetDirectoryName($c.Path))
            if ([int]$c.Depth -gt 0 -and $parentLeaf -match $script:PelExeGoodDirs) { $score += 5 }
            if ($c.Path -match '(?i)(win64|x64|bin64|_64|64bit)' -or $baseL -match '64$') { $score += 3 }

            # Größe: winzige Stub-Dateien abwerten, echte Programme leicht bevorzugen
            if ($size -lt 64KB) { $score -= 15 }
            elseif ($size -ge 10MB) { $score += 6 }
            elseif ($size -ge 1MB) { $score += 4 }

            # Launcher nur, wenn es nichts Besseres gibt
            if ($baseL -match 'launcher') { $score -= 35; $why.Add('Launcher') }

            $scored.Add([pscustomobject]@{ Path = $c.Path; Score = $score; Size = $size; Depth = [int]$c.Depth; Reason = ($why -join ', ') })
        }
        if ($scored.Count -gt 0) {
            $best = $scored | Sort-Object @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'Size'; Descending = $true }, @{ Expression = 'Depth'; Descending = $false } | Select-Object -First 1
            if (-not $best.Reason) { $best.Reason = 'beste Bewertung' }
            return $best
        }
    }
    return $null
}

# --- Whitelist/Blacklist-Abgleich --------------------------------------------------
# Namen werden vereinheitlicht (Kleinschreibung, Satzzeichen weg, "&" -> "and"), damit
# "Counter-Strike" = "Counter Strike" und "Garry's Mod" = "Garrys Mod" gilt.
function ConvertTo-PelMatchText([string]$s) {
    $t = ([string]$s).ToLowerInvariant()
    $t = $t -replace "[’'`´]", ''
    $t = $t -replace '&', ' and '
    $t = $t -replace '[^a-z0-9]+', ' '
    return $t.Trim()
}

# Whitelist: Einträge müssen als ganze Wörter vorkommen (kein "Battlefield 2" in
# "Battlefield 2142"). Kurze Einzelwörter ("Rust", "Game", "Black", "Doom") gelten nur
# exakt oder mit Versionszusatz ("Doom 3", "Diablo II") - sonst würde "Rust" auch
# "RustDesk" und "Game" jeden "... Game Launcher" aufnehmen. Umgekehrt zählt auch ein
# Ordnername, der vollständig in einem Eintrag steckt ("Raven Shield" ->
# "Tom Clancy's Rainbow Six 3: Raven Shield"), wenn er aus mind. 2 Wörtern besteht.
function Find-PelWhitelistMatch([string]$Name, [string[]]$Entries) {
    $n = ConvertTo-PelMatchText $Name
    if (-not $n) { return $null }
    $nWords = $n.Split(' ')
    foreach ($e in $Entries) {
        $ne = ConvertTo-PelMatchText $e
        if (-not $ne) { continue }
        if ($n -eq $ne) { return $e }
        $eWords = $ne.Split(' ')
        if ($eWords.Count -eq 1 -and $ne.Length -le 6) {
            if ($nWords.Count -ge 2 -and $nWords[0] -eq $ne -and $nWords[1] -match $script:PelRomanOrNumber) { return $e }
            continue
        }
        if ((" $n ").Contains(" $ne ")) { return $e }
        if ($nWords.Count -ge 2 -and $n.Length -ge 8 -and (" $ne ").Contains(" $n ")) { return $e }
    }
    return $null
}

# Blacklist: Begriffe als ganze Wörter/Wortgruppen ("tools" trifft "Authoring Tools",
# aber "mod" trifft NICHT mehr "Modern Warfare"); $ExactNames nur bei exakt gleichem Namen.
function Find-PelBlacklistMatch([string]$Name, [string[]]$Phrases, [string[]]$ExactNames = @()) {
    $n = ConvertTo-PelMatchText $Name
    if (-not $n) { return $null }
    foreach ($x in $ExactNames) { if ($n -eq (ConvertTo-PelMatchText $x)) { return $x } }
    foreach ($b in $Phrases) {
        $nb = ConvertTo-PelMatchText $b
        if ($nb -and (" $n ").Contains(" $nb ")) { return $b }
    }
    return $null
}

# Liefert die echte Spiel-EXE einer "Lan Games"-Verknüpfung. Steam-Spiele verweisen seit
# dem Umbau von Option 7 auf "steam.exe -applaunch <ID>"; die eigentliche Spiel-EXE steht
# dann in der Beschreibung ("... | exe=<Pfad>").
function Get-PelShortcutGameExe($Shortcut) {
    $d = [string]$Shortcut.Description
    if ($d -match '\|\s*exe=(.+)$') {
        $e = $matches[1].Trim()
        if ([System.IO.File]::Exists($e)) { return $e }
    }
    $t = [string]$Shortcut.TargetPath
    if ($t -and [System.IO.File]::Exists($t) -and ([System.IO.Path]::GetFileName($t) -ine 'steam.exe')) { return $t }
    return $null
}

# --- Eigene Listen (vom Nutzer pflegbar, Option 7 -> "Eigene Listen") ----------------
$script:PelUserListDir = 'C:\Project-Earth-Lan'
$script:PelUserWhitelistPath = Join-Path $script:PelUserListDir 'eigene_whitelist.txt'
$script:PelUserBlacklistPath = Join-Path $script:PelUserListDir 'eigene_blacklist.txt'
$script:PelExeOverridePath   = Join-Path $script:PelUserListDir 'exe_korrekturen.txt'

function Initialize-PelUserLists {
    try {
        if (-not [System.IO.Directory]::Exists($script:PelUserListDir)) { [void][System.IO.Directory]::CreateDirectory($script:PelUserListDir) }
        $utf8 = New-Object System.Text.UTF8Encoding($true)
        if (-not [System.IO.File]::Exists($script:PelUserWhitelistPath)) {
            [System.IO.File]::WriteAllText($script:PelUserWhitelistPath, "# Eigene Whitelist für den LAN Game Finder (Option 7)`r`n# Ein Spielname pro Zeile - wird zusätzlich zur eingebauten Liste berücksichtigt.`r`n# Zeilen mit # am Anfang werden ignoriert. Beispiel:`r`n# Medal of Honor Allied Assault`r`n", $utf8)
        }
        if (-not [System.IO.File]::Exists($script:PelUserBlacklistPath)) {
            [System.IO.File]::WriteAllText($script:PelUserBlacklistPath, "# Eigene Blacklist für den LAN Game Finder (Option 7)`r`n# Ein Name (oder Namensteil als ganzes Wort) pro Zeile - solche Einträge werden nie verknüpft.`r`n# Tipp: Taucht ein falsches Programm in 'Lan Games' auf, hier seinen Namen eintragen. Beispiel:`r`n# Wallpaper Engine`r`n", $utf8)
        }
        if (-not [System.IO.File]::Exists($script:PelExeOverridePath)) {
            [System.IO.File]::WriteAllText($script:PelExeOverridePath, "# EXE-Korrekturen für den LAN Game Finder (Option 7)`r`n# Format: Spielname | vollständiger Pfad zur richtigen .exe`r`n# Hat Vorrang vor der automatischen Auswahl. Spiele, die hier stehen, werden auch dann`r`n# verknüpft, wenn der Scan sie nicht selbst findet. Beispiel:`r`n# Battlefield 1942 | D:\Spiele\Battlefield 1942\BF1942.exe`r`n", $utf8)
        }
    } catch { }
}

function Get-PelUserList([string]$Path) {
    $out = @()
    try {
        if ([System.IO.File]::Exists($Path)) {
            foreach ($ln in [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)) {
                $t = $ln.Trim()
                if ($t -and -not $t.StartsWith('#')) { $out += $t }
            }
        }
    } catch { }
    return $out
}

# Liefert die EXE-Korrekturen als Liste von @{ Name; Path; Key } (Key = vereinheitlichter Name).
function Get-PelExeOverrides {
    $out = @()
    foreach ($ln in @(Get-PelUserList $script:PelExeOverridePath)) {
        $parts = $ln -split '\|', 2
        if ($parts.Count -ne 2) { continue }
        $nm = $parts[0].Trim()
        $pt = $parts[1].Trim().Trim('"')
        if ($nm -and $pt) { $out += [pscustomobject]@{ Name = $nm; Path = $pt; Key = (ConvertTo-PelMatchText $nm) } }
    }
    return $out
}

# ------------------------------------------------------------------------------
# SPIELE: BEITRETEN ("Mitspielen"/"Join") & ERKENNUNG ("Wer spielt was")
# ------------------------------------------------------------------------------
# Gemeinsam genutzt vom Control Center (Live-Status -> "Mitspielen") und vom Server-
# Browser (Option 9 -> "Join"). Jede Regel beschreibt, wie ein Spiel direkt mit einem
# Server verbunden wird:
#   Exe      = typische Spiel-EXE(s) (klein geschrieben) - für die Erkennung laufender
#              Spiele und als bevorzugte EXE bei der Suche
#   Match    = Regex auf Spielname/GameSpy-"gamename"/Spielordner
#   Args     = Startparameter ({IP}/{PORT} werden ersetzt)
#   Uri      = Protokoll-Link statt EXE (z. B. Minecraft Bedrock, FiveM)
#   Steam    = $true -> bevorzugt steam://connect/IP:PORT (Source/GoldSrc)
#   Ports    = Standard-Spielports
#   QueryMap = Abfrageport -> Spielport (GameSpy/A2S melden oft den Abfrageport)
#   PortFallback = Regel darf auch allein anhand des Ports gewählt werden
# Egal welcher Weg: die Server-Adresse wird IMMER zusätzlich in die Zwischenablage
# kopiert, damit man sie im Spiel von Hand einfügen kann, falls der automatische
# Beitritt bei einem Spiel nicht greift.
$script:PelJoinRules = @(
    # --- Battlefield --------------------------------------------------------------
    @{ Key = 'bf1942';    Title = 'Battlefield 1942';    Exe = @('bf1942.exe');    Match = 'battlefield ?1942|bfield1942|\bbf ?1942\b'; Args = '+restart 1 +joinServer {IP}:{PORT}'; Ports = @(14567); QueryMap = @{ 23000 = 14567 }; PortFallback = $true }
    @{ Key = 'bfvietnam'; Title = 'Battlefield Vietnam'; Exe = @('bfvietnam.exe'); Match = 'battlefield ?vietnam|bfvietnam';           Args = '+restart 1 +joinServer {IP}:{PORT}'; Ports = @(15567); QueryMap = @{ 23000 = 15567 } }
    @{ Key = 'bf2142';    Title = 'Battlefield 2142';    Exe = @('bf2142.exe');    Match = 'battlefield ?2142|\bbf ?2142\b|\bstella\b'; Args = '+menu 1 +fullscreen 1 +joinServer {IP} +port {PORT}'; Ports = @(17567); QueryMap = @{ 29900 = 17567 } }
    @{ Key = 'bf2';       Title = 'Battlefield 2';       Exe = @('bf2.exe');       Match = 'battlefield ?2(?!\d)|\bbf2(?!\d)|battlefield2|project ?reality'; Args = '+menu 1 +fullscreen 1 +joinServer {IP} +port {PORT}'; Ports = @(16567); QueryMap = @{ 29900 = 16567 }; PortFallback = $true }
    # --- Unreal-Engine (Startparameter = Server-URL "IP:PORT") ---------------------
    @{ Key = 'ut2004';    Title = 'Unreal Tournament 2004'; Exe = @('ut2004.exe');  Match = 'ut ?2004|unreal tournament 2004'; Args = '{IP}:{PORT}'; Ports = @(7777); QueryMap = @{ 7778 = 7777; 7787 = 7777 } }
    @{ Key = 'ut2003';    Title = 'Unreal Tournament 2003'; Exe = @('ut2003.exe');  Match = 'ut ?2003|unreal tournament 2003|^ut2$'; Args = '{IP}:{PORT}'; Ports = @(7777); QueryMap = @{ 7778 = 7777; 7787 = 7777 } }
    @{ Key = 'ut3';       Title = 'Unreal Tournament 3';    Exe = @('ut3.exe');     Match = '\but ?3\b|ut3pc|unreal tournament 3'; Args = '{IP}:{PORT}'; Ports = @(7777); QueryMap = @{ 6500 = 7777 } }
    @{ Key = 'ut99';      Title = 'Unreal Tournament';      Exe = @('unrealtournament.exe'); Match = 'unreal ?tournament(?! ?(2003|2004|3\b))|\but ?99\b|^ut$'; Args = '{IP}:{PORT}'; Ports = @(7777); QueryMap = @{ 7778 = 7777 } }
    @{ Key = 'unrealgold'; Title = 'Unreal (Gold)';         Exe = @('unreal.exe');  Match = '^unreal( gold)?$|unreal ?gold'; Args = '{IP}:{PORT}'; Ports = @(7777); QueryMap = @{ 7778 = 7777 } }
    @{ Key = 'deusex';    Title = 'Deus Ex';                Exe = @('deusex.exe');  Match = 'deus ?ex';    Args = '{IP}:{PORT}'; Ports = @(7790); QueryMap = @{ 7791 = 7790 } }
    @{ Key = 'killingfloor'; Title = 'Killing Floor';       Exe = @('killingfloor.exe'); Match = 'killing ?floor(?! ?2)'; Args = '{IP}:{PORT}'; Ports = @(7707); QueryMap = @{ 7708 = 7707; 7717 = 7707 } }
    @{ Key = 'redorchestra'; Title = 'Red Orchestra';       Exe = @('redorchestra.exe'); Match = 'red ?orchestra(?! ?2)'; Args = '{IP}:{PORT}'; Ports = @(7757); QueryMap = @{ 7758 = 7757; 7767 = 7757 } }
    @{ Key = 'swat4';     Title = 'SWAT 4';                 Exe = @('swat4.exe', 'swat4x.exe'); Match = 'swat ?4'; Args = '{IP}:{PORT}'; Ports = @(10480); QueryMap = @{ 10481 = 10480 } }
    @{ Key = 'ravenshield'; Title = 'Rainbow Six 3: Raven Shield'; Exe = @('ravenshield.exe'); Match = 'raven ?shield'; Args = '{IP}:{PORT}'; Ports = @(7777) }
    # --- id Tech 2/3 & Abkömmlinge (Startparameter "+connect IP:PORT") ----------------
    @{ Key = 'cod4'; Probe = 'quake3';      Title = 'Call of Duty 4';         Exe = @('iw3mp.exe');   Match = 'call of duty ?4|\bcod ?4\b|iw3mp|modern warfare(?! ?[23])'; Args = '+connect {IP}:{PORT}'; Ports = @(28960) }
    @{ Key = 'codwaw'; Probe = 'quake3';    Title = 'Call of Duty: World at War'; Exe = @('codwawmp.exe'); Match = 'world at war|codwaw'; Args = '+connect {IP}:{PORT}'; Ports = @(28960) }
    @{ Key = 'cod2'; Probe = 'quake3';      Title = 'Call of Duty 2';         Exe = @('cod2mp_s.exe'); Match = 'call of duty ?2|\bcod ?2\b|cod2mp'; Args = '+connect {IP}:{PORT}'; Ports = @(28960) }
    @{ Key = 'coduo'; Probe = 'quake3';     Title = 'Call of Duty: United Offensive'; Exe = @('coduomp.exe'); Match = 'united offensive|coduo'; Args = '+connect {IP}:{PORT}'; Ports = @(28960) }
    @{ Key = 'cod1'; Probe = 'quake3';      Title = 'Call of Duty';           Exe = @('codmp.exe');   Match = 'call of duty|codmp|^cod$'; Args = '+connect {IP}:{PORT}'; Ports = @(28960); PortFallback = $true }
    @{ Key = 'mohaa';     Title = 'Medal of Honor: Allied Assault'; Exe = @('mohaa.exe', 'moh_spearhead.exe', 'moh_breakthrough.exe'); Match = 'medal of honor|mohaa|spearhead|breakthrough'; Args = '+connect {IP}:{PORT}'; Ports = @(12203); QueryMap = @{ 12300 = 12203 }; PortFallback = $true }
    @{ Key = 'rtcw'; Probe = 'quake3';      Title = 'Return to Castle Wolfenstein'; Exe = @('wolfmp.exe', 'iowolfmp.exe'); Match = 'return to castle|\brtcw\b|wolfmp'; Args = '+connect {IP}:{PORT}'; Ports = @(27960) }
    @{ Key = 'et'; Probe = 'quake3';        Title = 'Wolfenstein: Enemy Territory'; Exe = @('et.exe', 'etl.exe', 'etlegacy.exe'); Match = 'enemy ?territory|et ?legacy|etmain'; Args = '+connect {IP}:{PORT}'; Ports = @(27960) }
    @{ Key = 'jk2'; Probe = 'quake3';       Title = 'Star Wars Jedi Knight II'; Exe = @('jk2mp.exe'); Match = 'jedi ?outcast|jedi knight ii|\bjk2'; Args = '+connect {IP}:{PORT}'; Ports = @(28070); PortFallback = $true }
    @{ Key = 'jka'; Probe = 'quake3';       Title = 'Star Wars Jedi Academy'; Exe = @('jamp.exe', 'openjk.x86.exe', 'openjk.x86_64.exe'); Match = 'jedi ?academy|jkacademy|\bjka\b'; Args = '+connect {IP}:{PORT}'; Ports = @(29070); PortFallback = $true }
    @{ Key = 'sof2'; Probe = 'quake3';      Title = 'Soldier of Fortune II';  Exe = @('sof2mp.exe');  Match = 'soldier of fortune ?(ii|2)|sof2'; Args = '+connect {IP}:{PORT}'; Ports = @(20100); PortFallback = $true }
    @{ Key = 'urt'; Probe = 'quake3';       Title = 'Urban Terror';           Exe = @('quake3-urt.exe', 'quake3-urt-x86_64.exe', 'urbanterror.exe'); Match = 'urban ?terror|q3ut4'; Args = '+connect {IP}:{PORT}'; Ports = @(27960) }
    @{ Key = 'openarena'; Probe = 'quake3'; Title = 'OpenArena';              Exe = @('openarena.exe', 'openarena.x86_64.exe'); Match = 'open ?arena'; Args = '+connect {IP}:{PORT}'; Ports = @(27960) }
    @{ Key = 'eliteforce'; Probe = 'quake3'; Title = 'Star Trek: Elite Force'; Exe = @('stvoyhm.exe'); Match = 'elite ?force'; Args = '+connect {IP}:{PORT}'; Ports = @(27960) }
    @{ Key = 'q3'; Probe = 'quake3';        Title = 'Quake III Arena';        Exe = @('quake3.exe', 'quake3e.x64.exe', 'quake3e.exe', 'ioquake3.exe', 'ioquake3.x86_64.exe'); Match = 'quake ?(iii|3)|\bq3a\b|baseq3|\bq3\b'; Args = '+connect {IP}:{PORT}'; Ports = @(27960) }
    @{ Key = 'q2';        Title = 'Quake II';               Exe = @('quake2.exe', 'yquake2.exe', 'q2pro.exe'); Match = 'quake ?(ii|2)\b|baseq2'; Args = '+connect {IP}:{PORT}'; Ports = @(27910); PortFallback = $true }
    @{ Key = 'q1';        Title = 'Quake';                  Exe = @('quakespasm.exe', 'ironwail.exe', 'vkquake.exe', 'glquake.exe'); Match = '^quake$|\bid1\b'; Args = '+connect {IP}:{PORT}'; Ports = @(26000) }
    @{ Key = 'serioussam'; Title = 'Serious Sam (Classic)'; Exe = @('serioussam.exe'); Match = 'serious ?sam(?! ?(2|3|4|fusion|siberian))|serioussam'; Args = '+connect {IP}:{PORT}'; Ports = @(25600); PortFallback = $true }
    # --- Weitere Engines mit Direkt-Verbindungsparameter ------------------------------
    @{ Key = 'tribes2';   Title = 'Tribes 2';               Exe = @('tribes2.exe'); Match = 'tribes ?2'; Args = '-connect {IP}:{PORT}'; Ports = @(28000); PortFallback = $true }
    @{ Key = 'halo';      Title = 'Halo: Combat Evolved';   Exe = @('haloce.exe', 'halo.exe'); Match = '\bhalo(ce|[rm])?\b'; Args = '-connect {IP}:{PORT}'; Ports = @(2302) }
    @{ Key = 'arma';      Title = 'Arma / DayZ';            Exe = @('arma3_x64.exe', 'arma3.exe', 'arma2oa.exe', 'arma2.exe', 'dayz_x64.exe'); Match = '\barma|dayz'; Args = '-connect={IP} -port={PORT}'; Ports = @(2302); QueryMap = @{ 2303 = 2302 }; PortFallback = $true }
    @{ Key = 'factorio';  Title = 'Factorio';               Exe = @('factorio.exe'); Match = 'factorio'; Args = '--mp-connect {IP}:{PORT}'; Ports = @(34197); PortFallback = $true }
    @{ Key = 'openttd';   Title = 'OpenTTD';                Exe = @('openttd.exe'); Match = 'openttd|transport tycoon'; Args = '-n {IP}:{PORT}'; Ports = @(3979); PortFallback = $true }
    @{ Key = 'rust';      Title = 'Rust';                   Exe = @('rustclient.exe', 'rust.exe'); Match = '^rust$|\brust\b(?! ?(desk|lang))'; Args = '+connect {IP}:{PORT}'; Ports = @(28015); QueryMap = @{ 28016 = 28015 }; PortFallback = $true }
    @{ Key = 'valheim';   Title = 'Valheim';                Exe = @('valheim.exe'); Match = 'valheim'; Args = '+connect {IP}:{PORT}'; Ports = @(2456); QueryMap = @{ 2457 = 2456 }; PortFallback = $true }
    @{ Key = 'ark';       Title = 'ARK: Survival Evolved';  Exe = @('shootergame.exe'); Match = '\bark\b|survival evolved|shootergame'; Args = '+connect {IP}:{PORT}'; Ports = @(7777) }
    @{ Key = 'gzdoom';    Title = 'GZDoom';                 Exe = @('gzdoom.exe', 'zdoom.exe'); Match = 'g?zdoom'; Args = '-join {IP}:{PORT}'; Ports = @(5029) }
    @{ Key = 'zandronum'; Title = 'Zandronum';              Exe = @('zandronum.exe'); Match = 'zandronum'; Args = '-connect {IP}:{PORT}'; Ports = @(10666); PortFallback = $true }
    @{ Key = 'ddnet';     Title = 'DDNet / Teeworlds';      Exe = @('ddnet.exe', 'teeworlds.exe'); Match = 'ddnet|teeworlds'; Args = '"connect {IP}:{PORT}"'; Ports = @(8303); PortFallback = $true }
    # --- Protokoll-Links ---------------------------------------------------------------
    @{ Key = 'minecraft-bedrock'; Title = 'Minecraft (Bedrock)'; Exe = @('minecraft.windows.exe'); Match = 'bedrock|minecraft for windows|minecraft\.windows'; Uri = 'minecraft://connect/?serverUrl={IP}&serverPort={PORT}'; Ports = @(19132); PortFallback = $true }
    @{ Key = 'fivem';     Title = 'FiveM (GTA V)';          Exe = @('fivem.exe'); Match = 'fivem'; Uri = 'fivem://connect/{IP}:{PORT}'; Ports = @(30120); PortFallback = $true }
    # --- Spiele ohne Direkt-Parameter: werden gestartet, Adresse liegt in der Zwischenablage
    @{ Key = 'minecraft-java'; Title = 'Minecraft (Java)';  Exe = @('minecraftlauncher.exe', 'minecraft.exe'); Match = 'minecraft'; Ports = @(25565); PortFallback = $true }
    @{ Key = '7dtd';      Title = '7 Days to Die';          Exe = @('7daystodie.exe'); Match = '7 ?days'; Ports = @(26900); PortFallback = $true }
    @{ Key = 'terraria';  Title = 'Terraria';               Exe = @('terraria.exe'); Match = 'terraria'; Ports = @(7777) }
    @{ Key = 'descent3';  Title = 'Descent 3';              Exe = @(); Match = 'descent ?3'; Ports = @(2092); QueryMap = @{ 20142 = 2092 }; PortFallback = $true }
    @{ Key = 'ghostrecon'; Title = 'Ghost Recon';           Exe = @('ghostrecon.exe'); Match = 'ghost ?recon'; Ports = @(2346); PortFallback = $true }
    @{ Key = 'roguespear'; Title = 'Rainbow Six: Rogue Spear'; Exe = @('roguespear.exe'); Match = 'rogue ?spear|rspear|rainbow ?six(?!.*raven)'; Ports = @(2346) }
    @{ Key = 'war3';      Title = 'Warcraft III';           Exe = @('war3.exe', 'warcraft iii.exe', 'frozen throne.exe'); Match = 'warcraft ?(iii|3)'; Ports = @(6112) }
    @{ Key = 'starcraft'; Title = 'StarCraft';              Exe = @('starcraft.exe'); Match = 'starcraft'; Ports = @(6112) }
    @{ Key = 'aoe2';      Title = 'Age of Empires II';      Exe = @('empires2.exe', 'age2_x1.exe', 'aoe2de_s.exe'); Match = 'age of empires'; Ports = @(2300) }
    @{ Key = 'redalert2'; Title = 'C&C: Alarmstufe Rot 2';  Exe = @('ra2.exe', 'gamemd.exe'); Match = 'red ?alert|alarmstufe rot|yuri|command ?(&|and) ?conquer'; Ports = @() }
    @{ Key = 'diablo2';   Title = 'Diablo II';              Exe = @('diablo ii.exe', 'd2se.exe'); Match = 'diablo ?(ii|2)'; Ports = @(4000) }
    # --- Familien-Rückfall (anhand des vom Scanner erkannten Protokolls) ----------------
    @{ Key = 'source';    Title = 'Source/GoldSrc-Spiel (Steam)'; Exe = @('cs2.exe', 'csgo.exe', 'hl2.exe', 'hl.exe', 'left4dead2.exe', 'left4dead.exe', 'tf_win64.exe', 'tf.exe'); Match = 'counter-?strike|cstrike|\bcs ?(1\.6|go|2|source)\b|csgo|team ?fortress|\btf2?\b|left ?4 ?dead|\bl4d2?\b|half-?life|\bhl2?(mp|dm)?\b|garry|\bgmod\b|day of defeat|\bdods?\b|insurgency|synergy|sven|black ?mesa|no more room|nmrih|fistful|zombie ?panic|^valve$'; Args = '+connect {IP}:{PORT}'; Steam = $true; Ports = @(27015); PortFallback = $true }
    @{ Key = 'a2s';       Title = 'Steam-Spiel (A2S)';      Exe = @(); Match = ''; Args = '+connect {IP}:{PORT}'; Steam = $true; Ports = @() }
    @{ Key = 'quake3';    Title = 'id-Tech-3-Spiel';        Exe = @(); Match = ''; Args = '+connect {IP}:{PORT}'; Ports = @(27960); PortFallback = $true }
    @{ Key = 'unreal';    Title = 'Unreal-Engine-Spiel';    Exe = @(); Match = ''; Args = '{IP}:{PORT}'; Ports = @(7777); QueryMap = @{ 7778 = 7777; 7787 = 7777 }; PortFallback = $true }
)

# Bekannte Spiel-EXEs für die Erkennung "Wer spielt was" (aus den Regeln abgeleitet,
# plus ein paar Namen, die in den Regeln nur als Familie stehen).
$script:PelKnownGameExes = @{}
foreach ($jr in $script:PelJoinRules) {
    foreach ($jx in @($jr.Exe)) {
        if ($jx -and -not $script:PelKnownGameExes.ContainsKey($jx)) {
            $script:PelKnownGameExes[$jx] = @{ Title = $jr.Title; Ports = @($jr.Ports); Probe = [string]$jr.Probe }
        }
    }
}
foreach ($kv in @(
        @('cs2.exe', 'Counter-Strike 2'), @('csgo.exe', 'Counter-Strike: Global Offensive'), @('left4dead2.exe', 'Left 4 Dead 2'),
        @('left4dead.exe', 'Left 4 Dead'), @('tf_win64.exe', 'Team Fortress 2'), @('tf.exe', 'Team Fortress 2'), @('hl.exe', 'Half-Life / Counter-Strike 1.6'))) {
    $script:PelKnownGameExes[$kv[0]] = @{ Title = $kv[1]; Ports = @(27015) }
}

# Liest Textdateien immer als UTF-8 (mit oder ohne BOM). Windows PowerShell 5.1 würde
# Get-Content ohne BOM als ANSI lesen und Umlaute zerstören.
function Read-PelTextFile([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

# Schreibt eine Datei "atomar" (erst Temp-Datei, dann ersetzen) - ein Absturz mitten im
# Schreiben hinterlässt so nie eine halbe, unlesbare Datei.
function Write-PelTextFileAtomic([string]$Path, [string]$Text) {
    $dir = [System.IO.Path]::GetDirectoryName($Path)
    if ($dir -and -not [System.IO.Directory]::Exists($dir)) { [void][System.IO.Directory]::CreateDirectory($dir) }
    $tmp = "$Path.tmp"
    [System.IO.File]::WriteAllText($tmp, $Text, (New-Object System.Text.UTF8Encoding($false)))
    # [NullString]::Value statt $null: PowerShell würde $null sonst als Leerstring
    # übergeben, und File.Replace lehnt einen leeren Sicherungspfad ab.
    if ([System.IO.File]::Exists($Path)) { [System.IO.File]::Replace($tmp, $Path, [NullString]::Value) }
    else { [System.IO.File]::Move($tmp, $Path) }
}

# Zwischenablage mit Wiederholung (schlägt sonst fehl, wenn gerade ein anderes Programm
# - Zwischenablage-Manager, Remotedesktop - die Zwischenablage kurz belegt).
function Set-PelClipboard([string]$Text) {
    if (-not $Text) { return $false }
    try { [System.Windows.Forms.Clipboard]::SetDataObject($Text, $true, 10, 100); return $true } catch { return $false }
}

function Show-PelMsg {
    param([string]$Text, [string]$Title = 'Project Earth LAN', $Icon = [System.Windows.Forms.MessageBoxIcon]::Information, $Owner = $null)
    if ($Owner) { [void][System.Windows.Forms.MessageBox]::Show($Owner, $Text, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $Icon) }
    else { [void][System.Windows.Forms.MessageBox]::Show($Text, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $Icon) }
}

# Anzeigename für Live-Status und Spieleabend-Planer: der Nickname aus der Kommuni-
# kationszentrale (Option 10), sonst der Computername.
function Get-PelDisplayName {
    $n = ''
    try {
        $cfg = Join-Path $env:APPDATA 'ProjectEarthLan\chat.json'
        if ([System.IO.File]::Exists($cfg)) {
            $j = Read-PelTextFile $cfg | ConvertFrom-Json
            if ($j.Nick) { $n = [string]$j.Nick }
        }
    } catch { }
    if (-not $n) { $n = [string]$env:COMPUTERNAME }
    $n = ($n -replace '[|\r\n]', ' ').Trim()
    if ($n.Length -gt 32) { $n = $n.Substring(0, 32) }
    return $n
}

function Get-PelJoinRule {
    param([string]$GameName = '', [string]$Folder = '', [string]$Key = '', [string]$ExeHint = '', [int]$Port = 0)
    $exeL = ([string]$ExeHint).ToLowerInvariant()
    if ($exeL) {
        foreach ($r in $script:PelJoinRules) { if (@($r.Exe) -contains $exeL) { return $r } }
    }
    foreach ($s in @($GameName, $Folder)) {
        if (-not $s) { continue }
        foreach ($r in $script:PelJoinRules) { if ($r.Match -and ($s -match $r.Match)) { return $r } }
    }
    $famKey = $Key
    if ($Key -eq 'a2s' -and $Port -ge 27015 -and $Port -le 27030) { $famKey = 'source' }
    if ($famKey) {
        foreach ($r in $script:PelJoinRules) { if ($r.Key -eq $famKey) { return $r } }
    }
    if ($Port -gt 0) {
        foreach ($r in $script:PelJoinRules) {
            if (-not $r.PortFallback) { continue }
            if ((@($r.Ports) -contains $Port) -or ($r.QueryMap -and $r.QueryMap.ContainsKey($Port))) { return $r }
        }
    }
    return $null
}

# Liefert den Port, mit dem man sich tatsächlich verbindet: vom Scanner gemeldeter
# Spielport > Umrechnung Abfrageport->Spielport > gefundener Port > Standardport.
function Resolve-PelJoinPort {
    param($Rule, [int]$Port = 0, [int]$JoinPort = 0)
    if ($JoinPort -gt 0) { return $JoinPort }
    if ($Rule -and $Port -gt 0 -and $Rule.QueryMap -and $Rule.QueryMap.ContainsKey($Port)) { return [int]$Rule.QueryMap[$Port] }
    if ($Port -gt 0) { return $Port }
    if ($Rule -and @($Rule.Ports).Count -gt 0) { return [int](@($Rule.Ports)[0]) }
    return 0
}

function Get-PelJoinAddress {
    param([string]$Ip, [int]$Port = 0, [int]$JoinPort = 0, [string]$GameName = '', [string]$Folder = '', [string]$Key = '', [string]$ExeHint = '')
    $rule = Get-PelJoinRule -GameName $GameName -Folder $Folder -Key $Key -ExeHint $ExeHint -Port $Port
    $gp = Resolve-PelJoinPort -Rule $rule -Port $Port -JoinPort $JoinPort
    if ($gp -gt 0) { return "${Ip}:$gp" }
    return $Ip
}

$script:PelJoinMapPath = Join-Path $env:APPDATA 'ProjectEarthLan\joinmap.json'
function Get-PelJoinMap {
    $m = @{}
    try {
        if ([System.IO.File]::Exists($script:PelJoinMapPath)) {
            $obj = Read-PelTextFile $script:PelJoinMapPath | ConvertFrom-Json
            foreach ($prop in $obj.PSObject.Properties) { $m[$prop.Name] = [string]$prop.Value }
        }
    } catch { }
    return $m
}
function Save-PelJoinMap {
    param([hashtable]$Map)
    try {
        $dir = Split-Path -Parent $script:PelJoinMapPath
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        $Map | ConvertTo-Json | Set-Content -LiteralPath $script:PelJoinMapPath -Encoding UTF8
    } catch { }
}

function ConvertTo-PelNormName([string]$s) {
    if (-not $s) { return '' }
    return ($s.ToLower() -replace '[^a-z0-9]', '')
}

function Get-PelSteamCommonFolders {
    $paths = @()
    $steam = $null
    try { $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath } catch { }
    if (-not $steam) { try { $steam = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction Stop).InstallPath } catch { } }
    if ($steam) {
        $steam = $steam -replace '/', '\'
        $paths += (Join-Path $steam 'steamapps\common')
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if ([System.IO.File]::Exists($vdf)) {
            foreach ($m in [regex]::Matches([System.IO.File]::ReadAllText($vdf), '"path"\s+"([^"]+)"')) {
                $lib = $m.Groups[1].Value -replace '\\\\', '\'
                $paths += (Join-Path $lib 'steamapps\common')
            }
        }
    }
    return @($paths | Where-Object { [System.IO.Directory]::Exists($_) } | Select-Object -Unique)
}

# Sammelt installierte Spiele (Name, Ordner, ggf. EXE) aus allen üblichen Quellen.
# Das Ergebnis wird 2 Minuten zwischengespeichert, damit mehrere Joins hintereinander
# nicht jedes Mal alle Laufwerke neu durchsuchen.
function Get-PelGameCandidates {
    if ($script:PelCandCache -and $script:PelCandCacheTime -and (((Get-Date) - $script:PelCandCacheTime).TotalSeconds -lt 120)) { return $script:PelCandCache }
    $cands = [System.Collections.Generic.List[object]]::new()

    # 1. Verknüpfungen im Desktop-Ordner "Lan Games" (Option 7/8)
    $lanFolder = Join-Path ([System.Environment]::GetFolderPath('Desktop')) 'Lan Games'
    if (Test-Path -LiteralPath $lanFolder) {
        try {
            $wsh = New-Object -ComObject WScript.Shell
            foreach ($lnk in @(Get-ChildItem -LiteralPath $lanFolder -Filter '*.lnk' -ErrorAction SilentlyContinue)) {
                try {
                    $target = Get-PelShortcutGameExe ($wsh.CreateShortcut($lnk.FullName))
                    if ($target) {
                        $cands.Add([pscustomobject]@{ Name = $lnk.BaseName; Dir = (Split-Path -Parent $target); Exe = $target })
                    }
                } catch { }
            }
        } catch { }
    }

    # 2. Steam-Bibliotheken
    foreach ($lib in @(Get-PelSteamCommonFolders)) {
        foreach ($d in @(Get-ChildItem -LiteralPath $lib -Directory -ErrorAction SilentlyContinue)) {
            $cands.Add([pscustomobject]@{ Name = $d.Name; Dir = $d.FullName; Exe = $null })
        }
    }

    # 3. Epic Games
    $epicDir = Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'
    if (Test-Path -LiteralPath $epicDir) {
        foreach ($mf in @(Get-ChildItem -LiteralPath $epicDir -Filter '*.item' -ErrorAction SilentlyContinue)) {
            try {
                $j = Read-PelTextFile $mf.FullName | ConvertFrom-Json
                if ($j.DisplayName -and $j.InstallLocation) {
                    $exe = $null
                    if ($j.LaunchExecutable) {
                        $ce = Join-Path $j.InstallLocation $j.LaunchExecutable
                        if ([System.IO.File]::Exists($ce)) { $exe = $ce }
                    }
                    $cands.Add([pscustomobject]@{ Name = $j.DisplayName; Dir = $j.InstallLocation; Exe = $exe })
                }
            } catch { }
        }
    }

    # 4. GOG (eigener Registry-Zweig) und installierte Programme (Uninstall-Registry)
    foreach ($gk in @(Get-ChildItem 'HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games' -ErrorAction SilentlyContinue)) {
        try {
            $gp = Get-ItemProperty -LiteralPath $gk.PSPath -ErrorAction Stop
            if ($gp.gameName -and $gp.path -and [System.IO.Directory]::Exists($gp.path)) {
                $gexe = $null
                if ($gp.exe -and [System.IO.File]::Exists($gp.exe)) { $gexe = $gp.exe }
                $cands.Add([pscustomobject]@{ Name = $gp.gameName; Dir = $gp.path; Exe = $gexe })
            }
        } catch { }
    }
    foreach ($rp in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        foreach ($e in @(Get-ItemProperty -Path $rp -ErrorAction SilentlyContinue)) {
            if ($e.DisplayName -and $e.InstallLocation -and [System.IO.Directory]::Exists([string]$e.InstallLocation)) {
                $cands.Add([pscustomobject]@{ Name = $e.DisplayName; Dir = $e.InstallLocation; Exe = $null })
            }
        }
    }

    # 5. Übliche Spiel- und Herstellerordner auf allen festen Laufwerken (alte Spiele
    #    liegen oft unter "Program Files (x86)\EA GAMES\...", "...\Activision\..." usw.)
    $rels = @('Games', 'Spiele', 'XboxGames', 'GOG Games', 'Epic Games', 'SteamLibrary\steamapps\common', 'Program Files', 'Program Files (x86)')
    foreach ($pub in @('EA GAMES', 'EA Games', 'Origin Games', 'Electronic Arts', 'Activision', 'Ubisoft', 'Ubisoft\Ubisoft Game Launcher\games', 'Sierra', 'Infogrames', 'Atari', 'THQ', 'GOG Galaxy\Games', 'Bethesda Softworks', 'Codemasters', 'Blizzard Entertainment', 'Red Storm Entertainment')) {
        $rels += "Program Files (x86)\$pub"
        $rels += "Program Files\$pub"
    }
    foreach ($drv in [System.IO.DriveInfo]::GetDrives()) {
        if ($drv.DriveType -ne 'Fixed' -or -not $drv.IsReady) { continue }
        foreach ($rel in $rels) {
            $base = Join-Path $drv.RootDirectory.FullName $rel
            if ([System.IO.Directory]::Exists($base)) {
                foreach ($d in @(Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue)) {
                    $cands.Add([pscustomobject]@{ Name = $d.Name; Dir = $d.FullName; Exe = $null })
                }
            }
        }
    }
    $script:PelCandCache = $cands.ToArray()
    $script:PelCandCacheTime = Get-Date
    return $script:PelCandCache
}

# Teilstring-Vergleich mit Ziffern-Grenze: "battlefield2" steckt zwar in
# "battlefield2142", ist aber ein anderes Spiel (Zahl geht direkt weiter).
function Test-PelNameContains([string]$Haystack, [string]$Needle) {
    $idx = $Haystack.IndexOf($Needle)
    while ($idx -ge 0) {
        $after = $idx + $Needle.Length
        $clashAfter = ($after -lt $Haystack.Length) -and [char]::IsDigit($Haystack[$after]) -and [char]::IsDigit($Needle[$Needle.Length - 1])
        $clashBefore = ($idx -gt 0) -and [char]::IsDigit($Haystack[$idx - 1]) -and [char]::IsDigit($Needle[0])
        if (-not $clashAfter -and -not $clashBefore) { return $true }
        $idx = $Haystack.IndexOf($Needle, $idx + 1)
    }
    return $false
}

function Find-PelBestCandidate($cands, [string[]]$phrases) {
    $best = $null
    $bestScore = 0
    # Kurze Namen (z. B. "Rust", "ARK") zählen nur als ganzes Wort - sonst würde "Rust"
    # auch "RustDesk" oder "ARK" auch "Dark Souls" treffen.
    foreach ($c in $cands) {
        $cn = ConvertTo-PelNormName $c.Name
        if ($cn.Length -lt 3) { continue }
        $cWords = @(([string]$c.Name).ToLower() -split '[^a-z0-9]+' | Where-Object { $_ })
        foreach ($ph in $phrases) {
            $pn = ConvertTo-PelNormName $ph
            if ($pn.Length -lt 3) { continue }
            $score = 0
            if ($cn -eq $pn) { $score = 100 }
            elseif ($pn.Length -ge 6 -and (Test-PelNameContains $cn $pn)) { $score = 90 }
            elseif ($cn.Length -ge 6 -and (Test-PelNameContains $pn $cn)) { $score = 85 }
            else {
                $tokens = @(([string]$ph).ToLower() -split '[^a-z0-9]+' | Where-Object { $_.Length -ge 2 -or $_ -match '^\d+$' })
                if ($tokens.Count -gt 0) {
                    $hits = 0
                    foreach ($tk in $tokens) { if ($cWords -contains $tk) { $hits++ } }
                    if ($hits -eq $tokens.Count) { $score = 70 }
                }
            }
            if ($c.Exe -and $score -gt 0) { $score += 5 }
            if ($score -gt $bestScore) { $best = $c; $bestScore = $score }
        }
    }
    return $best
}

function Find-PelGameMainExe([string]$dir, [string[]]$preferred) {
    $sel = Select-PelGameExe -Folder $dir -GameName ([System.IO.Path]::GetFileName($dir.TrimEnd('\'))) -PreferredNames $preferred
    if ($sel) { return $sel.Path }
    return $null
}

# Sucht die passende Spiel-EXE: erst eine Verknüpfung/Installation mit genau der
# bekannten EXE, dann per Namensvergleich (Spielname, Ordner, Regel-Titel).
function Find-PelGameExe {
    param($Rule, [string]$GameName = '', [string]$Folder = '', [string]$ExeHint = '')
    $preferred = @()
    if ($ExeHint) { $preferred += $ExeHint.ToLowerInvariant() }
    if ($Rule) { $preferred += @($Rule.Exe) }
    $cands = @(Get-PelGameCandidates)
    foreach ($c in $cands) {
        if ($c.Exe -and ($preferred -contains ([System.IO.Path]::GetFileName([string]$c.Exe)).ToLowerInvariant())) { return [string]$c.Exe }
    }
    $raw = @($GameName, $Folder)
    if ($Rule) { $raw += $Rule.Title }
    $phrases = @()
    foreach ($rp in @($raw | Where-Object { $_ })) {
        $phrases += $rp
        $cleanP = (([string]$rp) -replace '(?i)\b(dedicated|server|srv|dedizierter)\b', ' ' -replace '[-_:]+', ' ' -replace '\s+', ' ').Trim()
        if ($cleanP -and $cleanP -ne $rp) { $phrases += $cleanP }
    }
    if ($phrases.Count -eq 0) { return $null }
    $best = Find-PelBestCandidate $cands ([string[]]$phrases)
    if (-not $best) { return $null }
    if ($best.Exe) { return [string]$best.Exe }
    return (Find-PelGameMainExe ([string]$best.Dir) ([string[]]$preferred))
}

# Einem Server/Spieler beitreten. Reihenfolge:
#   1. Adresse IMMER in die Zwischenablage (Rückfall, falls der Beitritt nicht greift)
#   2. Protokoll-Link (Minecraft Bedrock, FiveM)
#   3. steam://connect (Source/GoldSrc, wenn Steam installiert ist)
#   4. gemerkte oder gefundene Spiel-EXE mit Verbindungsparametern starten
#   5. EXE auswählen lassen (wird gemerkt)
# Rückgabe: kurzer Statustext für die aufrufende Oberfläche.
#   -LaunchOnly: Spiel nur starten, ohne Verbindungsparameter (Spieler hostet nicht
#   selbst und sein Server ist unbekannt - dann findet man ihn meist im LAN-Browser des
#   Spiels; seine IP liegt trotzdem in der Zwischenablage).
#   Umschalt gedrückt halten beim Klick = Spiel-EXE neu auswählen (falls die gemerkte
#   oder automatisch gefundene EXE falsch ist).
function Invoke-PelJoinGame {
    param([string]$Ip, [int]$Port = 0, [int]$JoinPort = 0, [string]$GameName = '', [string]$Folder = '', [string]$Key = '', [string]$ExeHint = '', $ParentForm = $null, [switch]$LaunchOnly)
    $rule = Get-PelJoinRule -GameName $GameName -Folder $Folder -Key $Key -ExeHint $ExeHint -Port $Port
    $gamePort = 0
    if (-not $LaunchOnly) { $gamePort = Resolve-PelJoinPort -Rule $rule -Port $Port -JoinPort $JoinPort }
    $addr = $Ip
    if ($gamePort -gt 0) { $addr = "${Ip}:$gamePort" }
    $title = 'das Spiel'
    if ($GameName) { $title = $GameName } elseif ($rule) { $title = $rule.Title }
    $forcePick = (([System.Windows.Forms.Control]::ModifierKeys -band [System.Windows.Forms.Keys]::Shift) -eq [System.Windows.Forms.Keys]::Shift)

    if (Set-PelClipboard $addr) {
        $clipHint = "Die Adresse $addr liegt in der Zwischenablage - im Spiel unter 'Direkt verbinden' / 'IP eingeben' mit Strg+V einfügen."
    } else {
        $clipHint = "Die Adresse lautet $addr (konnte nicht in die Zwischenablage kopiert werden - bitte im Spiel von Hand eingeben)."
    }
    if ($LaunchOnly) {
        $clipHint = "$clipHint`nDer Spieler hostet nicht selbst - den Server findest du meist im LAN-/Mehrspieler-Browser des Spiels."
    }

    if (-not $LaunchOnly -and -not $forcePick -and $rule -and $rule.Uri -and $gamePort -gt 0) {
        $uri = ([string]$rule.Uri).Replace('{IP}', $Ip).Replace('{PORT}', [string]$gamePort)
        try {
            Start-Process $uri -ErrorAction Stop
            return "Gestartet: $uri (Adresse zusätzlich in der Zwischenablage)"
        } catch {
            Show-PelMsg "Spiel-Link konnte nicht geöffnet werden:`n$uri`n$($_.Exception.Message)`n`n$clipHint" 'Mitspielen' ([System.Windows.Forms.MessageBoxIcon]::Warning) $ParentForm
            return "Start fehlgeschlagen - Adresse: $addr"
        }
    }

    if (-not $LaunchOnly -and -not $forcePick -and $rule -and $rule.Steam -and $gamePort -gt 0 -and (Test-Path 'HKCU:\Software\Valve\Steam')) {
        try {
            Start-Process ("steam://connect/" + $addr) -ErrorAction Stop
            return "Über Steam verbunden: $addr (Adresse zusätzlich in der Zwischenablage)"
        } catch { }
    }

    $map = Get-PelJoinMap
    $ruleKey = 'generic'
    if ($rule) { $ruleKey = $rule.Key }
    $mapKey = "$ruleKey|$title"
    $exe = $null
    $picked = $false
    if (-not $forcePick -and $map.ContainsKey($mapKey) -and [System.IO.File]::Exists([string]$map[$mapKey])) { $exe = [string]$map[$mapKey] }

    if (-not $exe -and -not $forcePick) {
        if ($ParentForm) { $ParentForm.Cursor = [System.Windows.Forms.Cursors]::WaitCursor }
        try { $exe = Find-PelGameExe -Rule $rule -GameName $GameName -Folder $Folder -ExeHint $ExeHint }
        catch { $exe = $null }
        finally { if ($ParentForm) { $ParentForm.Cursor = [System.Windows.Forms.Cursors]::Default } }
    }

    if (-not $exe) {
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Title = "Spiel-EXE für '$title' auswählen (wird gemerkt)"
        $ofd.Filter = "Programme (*.exe)|*.exe|Alle Dateien (*.*)|*.*"
        $dr = if ($ParentForm) { $ofd.ShowDialog($ParentForm) } else { $ofd.ShowDialog() }
        if ($dr -ne [System.Windows.Forms.DialogResult]::OK) {
            Show-PelMsg "Das Spiel wurde nicht gestartet.`n`n$clipHint" 'Mitspielen' ([System.Windows.Forms.MessageBoxIcon]::Information) $ParentForm
            return "Nicht gestartet - Adresse: $addr"
        }
        $exe = $ofd.FileName
        $picked = $true
    }
    # Nur selbst ausgewählte EXEs dauerhaft merken - eine automatisch gefundene wird bei
    # jedem Beitritt neu gesucht (so bleibt ein Fehlgriff der Suche nicht dauerhaft hängen).
    if ($picked) {
        $map[$mapKey] = $exe
        Save-PelJoinMap $map
    }

    $argText = ''
    if (-not $LaunchOnly -and $rule -and $rule.Args -and $gamePort -gt 0) { $argText = ([string]$rule.Args).Replace('{IP}', $Ip).Replace('{PORT}', [string]$gamePort) }
    try {
        $sp = @{ FilePath = $exe; WorkingDirectory = (Split-Path -Parent $exe); ErrorAction = 'Stop' }
        if ($argText) { $sp.ArgumentList = $argText }
        Start-Process @sp
    } catch {
        Show-PelMsg "Spiel konnte nicht gestartet werden:`n$exe`n$($_.Exception.Message)`n`n$clipHint`n`nTipp: Mit gedrückter Umschalttaste klicken, um die Spiel-EXE neu auszuwählen." 'Mitspielen' ([System.Windows.Forms.MessageBoxIcon]::Error) $ParentForm
        return "Start fehlgeschlagen - Adresse: $addr"
    }
    $exeLeaf = [System.IO.Path]::GetFileName($exe)
    if (-not $argText) {
        $why = 'Für dieses Spiel ist kein automatischer Verbindungsparameter bekannt.'
        if ($LaunchOnly) { $why = 'Es wurde ohne Verbindungsparameter gestartet.' }
        Show-PelMsg "$title wurde gestartet ($exeLeaf).`n$why`n`n$clipHint`n`nFalsches Spiel gestartet? Mit gedrückter Umschalttaste klicken, um die Spiel-EXE neu auszuwählen." 'Mitspielen' ([System.Windows.Forms.MessageBoxIcon]::Information) $ParentForm
        return "Gestartet: $exeLeaf - Adresse: $addr"
    }
    return "Gestartet: $exeLeaf -> $addr (Adresse zusätzlich in der Zwischenablage)"
}

# Erkennung des gerade laufenden Spiels - läuft in einem eigenen Hintergrund-Runspace,
# damit Prozess- und Portabfragen die Oberfläche nicht kurz einfrieren lassen.
# Quellen: Verknüpfungen in "Lan Games", Steam-/Epic-/GOG-Installationsordner (Pfad
# des Prozesses liegt darin) und die bekannten Spiel-EXEs aus den Join-Regeln.
# Zusätzlich: hostet das Spiel selbst (lauscht auf einem Spielport) -> JoinPort;
# ist es per TCP mit einem Server im LAN/VPN verbunden -> Server (IP:Port).
$script:PelGameDetectScript = {
    param($Cache, $KnownExes, [string]$SelfPath)
    $nowUtc = [DateTime]::UtcNow
    $built = $Cache['Built']
    if (-not $Cache['Dirs'] -or -not $built -or (($nowUtc - [DateTime]$built).TotalSeconds -gt 600)) {
        $dirs = New-Object System.Collections.Generic.List[object]
        $skipName = '(?i)^(steamworks shared|steamvr|wallpaper ?engine|steam controller configs|lossless scaling|soundpad|obs studio|proton.*|steam linux runtime.*|spacewar|fps monitor|voicemod|borderless gaming|displayfusion|cheat engine|rivatuner.*|msi afterburner)$'
        $addDir = {
            param([string]$d, [string]$n)
            if (-not $d -or -not $n) { return }
            if ($n -match $skipName) { return }
            $dirs.Add([pscustomobject]@{ Dir = ($d.TrimEnd('\') + '\'); Name = $n })
        }
        try {
            $lanFolder = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Lan Games'
            if ([System.IO.Directory]::Exists($lanFolder)) {
                $wsh = New-Object -ComObject WScript.Shell
                foreach ($lnk in @(Get-ChildItem -LiteralPath $lanFolder -Filter '*.lnk' -ErrorAction SilentlyContinue)) {
                    try {
                        $sc = $wsh.CreateShortcut($lnk.FullName)
                        $t = [string]$sc.TargetPath
                        if ([string]$sc.Description -match '\|\s*exe=(.+)$') { $t = $matches[1].Trim() }
                        if ($t -and [System.IO.File]::Exists($t) -and ([System.IO.Path]::GetFileName($t) -ine 'steam.exe')) { & $addDir (Split-Path -Parent $t) $lnk.BaseName }
                    } catch { }
                }
            }
        } catch { }
        try {
            $steam = $null
            try { $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath } catch { }
            if (-not $steam) { try { $steam = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction Stop).InstallPath } catch { } }
            if ($steam) {
                $steam = $steam -replace '/', '\'
                $libs = @(Join-Path $steam 'steamapps\common')
                $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
                if ([System.IO.File]::Exists($vdf)) {
                    foreach ($m in [regex]::Matches([System.IO.File]::ReadAllText($vdf), '"path"\s+"([^"]+)"')) {
                        $libs += (Join-Path ($m.Groups[1].Value -replace '\\\\', '\') 'steamapps\common')
                    }
                }
                foreach ($lib in @($libs | Select-Object -Unique)) {
                    if (-not [System.IO.Directory]::Exists($lib)) { continue }
                    foreach ($d in [System.IO.Directory]::GetDirectories($lib)) { & $addDir $d ([System.IO.Path]::GetFileName($d)) }
                }
            }
        } catch { }
        try {
            $epicDir = Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'
            if ([System.IO.Directory]::Exists($epicDir)) {
                foreach ($mf in [System.IO.Directory]::GetFiles($epicDir, '*.item')) {
                    try {
                        $j = [System.IO.File]::ReadAllText($mf) | ConvertFrom-Json
                        if ($j.DisplayName -and $j.InstallLocation) { & $addDir ([string]$j.InstallLocation) ([string]$j.DisplayName) }
                    } catch { }
                }
            }
        } catch { }
        try {
            foreach ($gk in @(Get-ChildItem 'HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games' -ErrorAction SilentlyContinue)) {
                try {
                    $gp = Get-ItemProperty -LiteralPath $gk.PSPath -ErrorAction Stop
                    if ($gp.gameName -and $gp.path) { & $addDir ([string]$gp.path) ([string]$gp.gameName) }
                } catch { }
            }
        } catch { }
        $Cache['Dirs'] = $dirs.ToArray()
        $Cache['Built'] = $nowUtc
    }

    $procs = @()
    try { $procs = @(Get-CimInstance -ClassName Win32_Process -Property ProcessId, Name, ExecutablePath, CommandLine, WorkingSetSize -ErrorAction Stop) } catch { }
    $exclExe = '(?i)^(steam|steamwebhelper|steamservice|gameoverlayui|epicgameslauncher|epicwebhelper|galaxyclient|galaxyclient helper|galaxycommunication|unitycrashhandler(32|64)?|crashreportclient|crashpad_handler|crashsender.*|easyanticheat.*|beservice.*|battleye.*|vc_?redist.*|dxsetup|unins\d*|setup|updater|launcher|powershell|pwsh|conhost|cmd|explorer|wallpaper(32|64)|webwallpaper32|ui32|discord|obs(32|64))\.exe$'
    $best = $null
    foreach ($p in $procs) {
        $path = [string]$p.ExecutablePath
        if (-not $path) { continue }
        if ($SelfPath -and ($path -ieq $SelfPath)) { continue }
        $exeName = [System.IO.Path]::GetFileName($path)
        if ($exeName -match $exclExe) { continue }
        $lower = $exeName.ToLowerInvariant()
        $title = $null
        $ports = @()
        $probe = ''
        if (($lower -eq 'javaw.exe' -or $lower -eq 'java.exe') -and ([string]$p.CommandLine -match '(?i)net\.minecraft|\.minecraft')) {
            $title = 'Minecraft (Java)'; $ports = @(25565)
        }
        if (-not $title) {
            $bestLen = 0
            foreach ($d in $Cache['Dirs']) {
                if ($d.Dir.Length -gt $bestLen -and $path.StartsWith($d.Dir, [System.StringComparison]::OrdinalIgnoreCase)) { $title = $d.Name; $bestLen = $d.Dir.Length }
            }
        }
        if ($KnownExes.ContainsKey($lower)) {
            $k = $KnownExes[$lower]
            if (-not $title) { $title = $k.Title }
            $ports = @($k.Ports)
            $probe = [string]$k.Probe
        }
        if (-not $title) { continue }
        $ws = [int64]$p.WorkingSetSize
        if ($ws -lt 25MB) { continue }
        if (-not $best -or $ws -gt $best.Ws) { $best = [pscustomobject]@{ Title = $title; Exe = $exeName; ProcId = [int]$p.ProcessId; Ws = $ws; Ports = $ports; Probe = $probe } }
    }
    if (-not $best) { return }

    $joinPort = 0
    $server = ''
    $clientPorts = @(1900, 3074, 3478, 3479, 3480, 4380, 5353, 5355, 27005, 27036, 27037)
    $udp = @()
    $tcpL = @()
    try { $udp = @(Get-NetUDPEndpoint -OwningProcess $best.ProcId -ErrorAction Stop | Where-Object { [string]$_.LocalAddress -notmatch '^(127\.|::1$)' } | ForEach-Object { [int]$_.LocalPort }) } catch { }
    try { $tcpL = @(Get-NetTCPConnection -OwningProcess $best.ProcId -State Listen -ErrorAction Stop | Where-Object { [string]$_.LocalAddress -notmatch '^(127\.|::1$)' } | ForEach-Object { [int]$_.LocalPort }) } catch { }
    $allP = @($tcpL + $udp)
    foreach ($pp in @($best.Ports)) { if ($allP -contains [int]$pp) { $joinPort = [int]$pp; break } }
    # id-Tech-3/Call-of-Duty: auch ein reiner Client belegt den Spielport. Nur wenn der
    # Port auf eine "getinfo"-Abfrage antwortet, läuft wirklich ein Server auf diesem PC.
    if ($joinPort -gt 0 -and $best.Probe -eq 'quake3' -and ($tcpL -notcontains $joinPort)) {
        $isServer = $false
        $uc = $null
        try {
            $uc = New-Object System.Net.Sockets.UdpClient
            $uc.Client.ReceiveTimeout = 400
            $uc.Connect('127.0.0.1', $joinPort)
            $q = [byte[]](@(0xFF, 0xFF, 0xFF, 0xFF) + [System.Text.Encoding]::ASCII.GetBytes("getinfo pel`n"))
            [void]$uc.Send($q, $q.Length)
            $rep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
            $rb = $uc.Receive([ref]$rep)
            if ($rb.Length -gt 16 -and [System.Text.Encoding]::ASCII.GetString($rb, 4, 12) -eq 'infoResponse') { $isServer = $true }
        } catch { } finally { if ($uc) { try { $uc.Close() } catch { } } }
        if (-not $isServer) { $joinPort = 0 }
    }
    if ($joinPort -eq 0 -and @($best.Ports).Count -eq 0) {
        $c = @($tcpL | Where-Object { $_ -ge 1024 -and $_ -lt 49152 -and $clientPorts -notcontains $_ } | Sort-Object)
        if ($c.Count -eq 0) { $c = @($udp | Where-Object { $_ -ge 1024 -and $_ -lt 49152 -and $clientPorts -notcontains $_ } | Sort-Object) }
        if ($c.Count -gt 0) { $joinPort = [int]$c[0] }
    }
    try {
        foreach ($e in @(Get-NetTCPConnection -OwningProcess $best.ProcId -State Established -ErrorAction Stop)) {
            $ra = [string]$e.RemoteAddress
            $rpt = [int]$e.RemotePort
            if ($rpt -eq 80 -or $rpt -eq 443 -or $rpt -ge 49152) { continue }
            if ($ra -match '^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.|2[56]\.)') { $server = "${ra}:$rpt"; break }
        }
    } catch { }
    [pscustomobject]@{ Title = $best.Title; Exe = $best.Exe; JoinPort = $joinPort; Server = $server }
}

# Lokale IPv4-Adressen (zum Ausfiltern der eigenen Broadcasts, die Windows auch an
# den Absender selbst zurückliefert).
function Get-PelLocalIpSet {
    $set = @{}
    try {
        foreach ($nic in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
            foreach ($ua in $nic.GetIPProperties().UnicastAddresses) {
                if ($ua.Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) { $set[$ua.Address.ToString()] = $true }
            }
        }
    } catch { }
    return $set
}

# ------------------------------------------------------------------------------
# SPIELEABEND-PLANER (Control Center -> "Spieleabend-Planer")
# ------------------------------------------------------------------------------
# Jeder Spieleabend wird lokal gespeichert (C:\Project-Earth-Lan\events.json) und von
# JEDEM Control Center, das ihn kennt, regelmäßig über den Live-Status-Port (9928)
# weitergegeben. Dadurch bekommt ihn auch jemand, der den Manager erst Tage später
# öffnet - es muss nur irgendein anderer Manager online sein, der ihn schon kennt.
# Ein neu gestarteter Manager fragt zusätzlich sofort nach ("PEEVTREQ1"), statt auf die
# nächste reguläre Runde zu warten.
# Damit bei vielen Managern nicht alle gleichzeitig senden, gilt: wer ein Event gerade
# im Netz gehört hat, wartet 60-90 Sekunden (zufällig), bevor er es selbst wieder sendet.
# Absagen kann nur der Ersteller: beim Anlegen entsteht ein geheimer Absage-Code, von dem
# im Netz nur der Hash verteilt wird; eine Absage gilt nur mit dem passenden Code.
# Ankündigung: öffnet jemand den Manager und ein Spieleabend beginnt in höchstens 3 Tagen
# (oder läuft gerade), erscheint einmalig ein Hinweisfenster; 15 Minuten vor Beginn gibt
# es zusätzlich eine Erinnerung, und eine Absage wird ebenfalls einmalig gemeldet.
$script:PelEventsPath      = "C:\Project-Earth-Lan\events.json"
$script:PelEventsLocalPath = "C:\Project-Earth-Lan\events_local.json"
$script:PelEvents = @{}
$script:PelEventsLocal = @{ Own = @{}; Seen = @{}; SeenCancel = @{}; Reminded = @{} }
$script:PelEvtWire = @{}
$script:PelEvtDelay = @{}
$script:PelEvtRandom = New-Object System.Random
$script:PelAnnounceForm = $null
$script:PelAnnounceBox = $null
$script:PelAnnounceParent = $null

function Get-PelNowMs { return [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }
function Get-PelNowSec { return [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

function Get-PelSha256Base64([string]$Text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToBase64String($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text))) }
    finally { $sha.Dispose() }
}

function ConvertTo-PelB64([string]$s) {
    if (-not $s) { return '' }
    return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($s))
}
function ConvertFrom-PelB64([string]$s) {
    if (-not $s) { return '' }
    try { return [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($s)) } catch { return '' }
}
function Limit-PelText([string]$s, [int]$Max) {
    $t = (([string]$s) -replace '[\r\n\t]+', ' ').Trim()
    if ($t.Length -gt $Max) { $t = $t.Substring(0, $Max) }
    return $t
}

function New-PelEventRecord {
    param([string]$Id, [string]$Title, [string]$Game, [string]$Organizer, [string]$Note, [int64]$Start, [int64]$Created, [string]$CancelHash, [bool]$Cancelled = $false, [string]$CancelToken = '')
    return [pscustomobject]@{ Id = $Id; Title = $Title; Game = $Game; Organizer = $Organizer; Note = $Note; Start = $Start; Created = $Created; CancelHash = $CancelHash; Cancelled = $Cancelled; CancelToken = $CancelToken }
}

function Save-PelEvents {
    try {
        $dir = Split-Path -Parent $script:PelEventsPath
        if (-not [System.IO.Directory]::Exists($dir)) { [void][System.IO.Directory]::CreateDirectory($dir) }
        $arr = @($script:PelEvents.Values | Sort-Object Start)
        $json = '[]'
        if ($arr.Count -gt 0) { $json = ConvertTo-Json -InputObject $arr -Depth 4 }
        Write-PelTextFileAtomic $script:PelEventsPath $json
    } catch { }
}

function Save-PelEventsLocal {
    try {
        $dir = Split-Path -Parent $script:PelEventsLocalPath
        if (-not [System.IO.Directory]::Exists($dir)) { [void][System.IO.Directory]::CreateDirectory($dir) }
        $obj = [ordered]@{
            Own        = $script:PelEventsLocal.Own
            Seen       = @($script:PelEventsLocal.Seen.Keys)
            SeenCancel = @($script:PelEventsLocal.SeenCancel.Keys)
            Reminded   = @($script:PelEventsLocal.Reminded.Keys)
        }
        $json = ConvertTo-Json -InputObject $obj -Depth 4
        Write-PelTextFileAtomic $script:PelEventsLocalPath $json
    } catch { }
}

# Entfernt abgelaufene Spieleabende (24 h nach Beginn) samt ihrer lokalen Markierungen.
# Lokale Markierungen werden NUR zusammen mit einem wirklich abgelaufenen Event gelöscht
# (nicht schon, weil ein Event gerade fehlt - z. B. nach einer beschädigten Datei), damit
# eigene Absage-Codes nicht verloren gehen. Verwaiste Einträge werden erst ab einer
# Obergrenze aufgeräumt.
function Remove-PelOldEvents {
    $now = Get-PelNowSec
    $changed = $false
    foreach ($id in @($script:PelEvents.Keys)) {
        if (([int64]$script:PelEvents[$id].Start + 86400) -lt $now) {
            $script:PelEvents.Remove($id)
            foreach ($nm in @('Own', 'Seen', 'SeenCancel', 'Reminded')) { $script:PelEventsLocal[$nm].Remove($id) }
            $changed = $true
        }
    }
    foreach ($nm in @('Own', 'Seen', 'SeenCancel', 'Reminded')) {
        if ($script:PelEventsLocal[$nm].Count -gt 300) {
            foreach ($id in @($script:PelEventsLocal[$nm].Keys)) {
                if (-not $script:PelEvents.ContainsKey($id)) { $script:PelEventsLocal[$nm].Remove($id); $changed = $true }
            }
        }
    }
    if ($changed) { Save-PelEvents; Save-PelEventsLocal }
}

function Import-PelEvents {
    $script:PelEvents = @{}
    $ok = $true
    try {
        if ([System.IO.File]::Exists($script:PelEventsPath)) {
            $parsed = Read-PelTextFile $script:PelEventsPath | ConvertFrom-Json
            foreach ($o in $parsed) {
                if (-not $o -or -not $o.Id) { continue }
                $script:PelEvents[[string]$o.Id] = New-PelEventRecord -Id ([string]$o.Id) -Title ([string]$o.Title) -Game ([string]$o.Game) -Organizer ([string]$o.Organizer) -Note ([string]$o.Note) -Start ([int64]$o.Start) -Created ([int64]$o.Created) -CancelHash ([string]$o.CancelHash) -Cancelled ([bool]$o.Cancelled) -CancelToken ([string]$o.CancelToken)
            }
        }
    } catch { $ok = $false }
    $script:PelEventsLocal = @{ Own = @{}; Seen = @{}; SeenCancel = @{}; Reminded = @{} }
    try {
        if ([System.IO.File]::Exists($script:PelEventsLocalPath)) {
            $lo = Read-PelTextFile $script:PelEventsLocalPath | ConvertFrom-Json
            if ($lo.Own) { foreach ($pr in $lo.Own.PSObject.Properties) { $script:PelEventsLocal.Own[$pr.Name] = [string]$pr.Value } }
            foreach ($nm in @('Seen', 'SeenCancel', 'Reminded')) {
                foreach ($id in @($lo.$nm)) { if ($id) { $script:PelEventsLocal[$nm][[string]$id] = $true } }
            }
        }
    } catch { $ok = $false }
    if (-not $ok) { Write-PelLog -Level 'WARNUNG' -Message 'Spieleabend-Dateien konnten nicht gelesen werden - sie werden aus dem Netzwerk neu aufgebaut.' }
    Remove-PelOldEvents
}

# Netzformat (eine Zeile, Texte Base64, am Ende HMAC mit dem Netzwerk-Secret):
# PEEVT1|Id|Start|Erstellt|Titel|Spiel|Organisator|Notiz|AbsageHash|Abgesagt|AbsageCode|HMAC
function ConvertTo-PelEventWire($e) {
    $core = 'PEEVT1|{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}' -f $e.Id, [int64]$e.Start, [int64]$e.Created, (ConvertTo-PelB64 $e.Title), (ConvertTo-PelB64 $e.Game), (ConvertTo-PelB64 $e.Organizer), (ConvertTo-PelB64 $e.Note), $e.CancelHash, ([int][bool]$e.Cancelled), $e.CancelToken
    return "$core|$(Get-PelHmacBase64 -Text $core)"
}

function ConvertFrom-PelEventWire([string]$Text) {
    $f = $Text -split '\|'
    if ($f.Count -ne 12 -or $f[0] -ne 'PEEVT1') { return $null }
    $core = ($f[0..10] -join '|')
    if (-not (Test-PelHmac -Text $core -Signature $f[11])) { return $null }
    if ($f[1] -notmatch '^[0-9a-f]{12}$') { return $null }
    $start = [int64]0
    $created = [int64]0
    if (-not [int64]::TryParse($f[2], [ref]$start)) { return $null }
    if (-not [int64]::TryParse($f[3], [ref]$created)) { return $null }
    if ($f[10] -and $f[10] -notmatch '^[0-9a-f]{32}$') { return $null }
    return (New-PelEventRecord -Id $f[1] -Title (Limit-PelText (ConvertFrom-PelB64 $f[4]) 60) -Game (Limit-PelText (ConvertFrom-PelB64 $f[5]) 60) -Organizer (Limit-PelText (ConvertFrom-PelB64 $f[6]) 32) -Note (Limit-PelText (ConvertFrom-PelB64 $f[7]) 160) -Start $start -Created $created -CancelHash $f[8] -Cancelled ($f[9] -eq '1') -CancelToken $f[10])
}

# Übernimmt ein empfangenes Event. Rückgabe: 'new', 'cancelled' oder $null (nichts geändert).
# Ein einmal bekanntes Event kann nur noch abgesagt werden (mit gültigem Absage-Code) -
# niemand kann Titel/Zeit eines fremden Spieleabends nachträglich verändern.
function Merge-PelEvent($Inc) {
    if (-not $Inc) { return $null }
    $now = Get-PelNowSec
    if (([int64]$Inc.Start + 86400) -lt $now) { return $null }
    if ([int64]$Inc.Start -gt ($now + 60 * 86400)) { return $null }
    $cur = $script:PelEvents[$Inc.Id]
    if (-not $cur) {
        if ($Inc.Cancelled) {
            if (-not $Inc.CancelToken -or ((Get-PelSha256Base64 $Inc.CancelToken) -ne $Inc.CancelHash)) { return $null }
        } elseif (@($script:PelEvents.Values | Where-Object { -not $_.Cancelled }).Count -ge 30) {
            return $null
        }
        $script:PelEvents[$Inc.Id] = $Inc
        Save-PelEvents
        if ($Inc.Cancelled) { return 'cancelled' }
        return 'new'
    }
    if ($cur.Cancelled -or -not $Inc.Cancelled) { return $null }
    if (-not $Inc.CancelToken -or ((Get-PelSha256Base64 $Inc.CancelToken) -ne $cur.CancelHash)) { return $null }
    $cur.Cancelled = $true
    $cur.CancelToken = $Inc.CancelToken
    Save-PelEvents
    return 'cancelled'
}

# Merkt sich, dass ein Event gerade im Netz zu hören war -> eigene Weitergabe erst
# wieder in 60-90 Sekunden (verhindert, dass bei vielen Managern alle gleichzeitig senden).
function Register-PelEventHeard([string]$Id) {
    $script:PelEvtWire[$Id] = Get-PelNowMs
    $script:PelEvtDelay[$Id] = 60000 + $script:PelEvtRandom.Next(0, 30000)
}

# Andere Manager haben nach Events gefragt: alles innerhalb von 0-4 Sekunden erneut
# senden (zufällig verteilt; wer zuerst sendet, bremst die anderen automatisch aus).
function Request-PelEventResend {
    $now = Get-PelNowMs
    foreach ($id in @($script:PelEvents.Keys)) {
        $script:PelEvtWire[$id] = $now
        $script:PelEvtDelay[$id] = $script:PelEvtRandom.Next(0, 4000)
    }
}

# Liefert höchstens $Max fällige Events, die jetzt gesendet werden sollen.
function Get-PelDueEvents([int]$Max = 2) {
    $now = Get-PelNowMs
    $nowSec = Get-PelNowSec
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($id in @($script:PelEvents.Keys)) {
        if (([int64]$script:PelEvents[$id].Start + 21600) -lt $nowSec) { continue }
        $last = [int64]0
        if ($script:PelEvtWire.ContainsKey($id)) { $last = [int64]$script:PelEvtWire[$id] }
        $delay = [int64]0
        if ($script:PelEvtDelay.ContainsKey($id)) { $delay = [int64]$script:PelEvtDelay[$id] }
        if (($now - $last) -ge $delay) {
            $out.Add($script:PelEvents[$id])
            Register-PelEventHeard $id
            if ($out.Count -ge $Max) { break }
        }
    }
    return $out.ToArray()
}

function New-PelGameNight {
    param([string]$Title, [string]$Game, [string]$Note, [datetime]$StartLocal)
    $id = [Guid]::NewGuid().ToString('N').Substring(0, 12)
    $tokBytes = New-Object byte[] 16
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($tokBytes) } finally { $rng.Dispose() }
    $token = -join ($tokBytes | ForEach-Object { $_.ToString('x2') })
    $start = ([DateTimeOffset]$StartLocal).ToUnixTimeSeconds()
    $e = New-PelEventRecord -Id $id -Title (Limit-PelText $Title 60) -Game (Limit-PelText $Game 60) -Organizer (Get-PelDisplayName) -Note (Limit-PelText $Note 160) -Start $start -Created (Get-PelNowSec) -CancelHash (Get-PelSha256Base64 $token)
    $script:PelEvents[$id] = $e
    $script:PelEventsLocal.Own[$id] = $token
    $script:PelEventsLocal.Seen[$id] = $true
    Save-PelEvents
    Save-PelEventsLocal
    $script:PelEvtWire[$id] = 0
    $script:PelEvtDelay[$id] = 0
    return $e
}

function Stop-PelGameNight([string]$Id) {
    $e = $script:PelEvents[$Id]
    $tok = $script:PelEventsLocal.Own[$Id]
    if (-not $e -or -not $tok -or $e.Cancelled) { return $false }
    $e.Cancelled = $true
    $e.CancelToken = [string]$tok
    $script:PelEventsLocal.SeenCancel[$Id] = $true
    Save-PelEvents
    Save-PelEventsLocal
    $script:PelEvtWire[$Id] = 0
    $script:PelEvtDelay[$Id] = 0
    return $true
}

function Format-PelEventWhen($e, [switch]$Short) {
    $de = [System.Globalization.CultureInfo]::GetCultureInfo('de-DE')
    $dt = [DateTimeOffset]::FromUnixTimeSeconds([int64]$e.Start).LocalDateTime
    $abs = if ($Short) { $dt.ToString('ddd dd.MM., HH:mm', $de) } else { $dt.ToString('ddd dd.MM.yyyy, HH:mm', $de) + ' Uhr' }
    $delta = [int64]$e.Start - (Get-PelNowSec)
    if ($delta -le 0) {
        if ($delta -gt -21600) { $rel = 'läuft gerade' } else { $rel = 'vorbei' }
    } elseif ($delta -lt 3600) {
        $rel = "in $([Math]::Max(1, [int][Math]::Ceiling($delta / 60))) Min."
    } elseif ($delta -lt 86400) {
        $rel = "in $([int][Math]::Floor($delta / 3600)) Std."
    } else {
        $d = [int][Math]::Floor($delta / 86400)
        $rel = if ($d -eq 1) { 'in 1 Tag' } else { "in $d Tagen" }
    }
    return "$abs ($rel)"
}

function Get-PelNextEventText {
    $now = Get-PelNowSec
    $next = @($script:PelEvents.Values | Where-Object { -not $_.Cancelled -and (([int64]$_.Start + 21600) -gt $now) } | Sort-Object Start | Select-Object -First 1)
    if ($next.Count -eq 0) { return 'Nächster Spieleabend: keiner geplant' }
    $e = $next[0]
    $what = if ($e.Game) { $e.Game } else { $e.Title }
    return "Nächster Spieleabend: $(Format-PelEventWhen $e -Short) - $what"
}

# Ermittelt, was dem Nutzer noch angezeigt werden muss (und markiert es als erledigt).
function Get-PelPendingAnnouncements {
    $now = Get-PelNowSec
    $items = New-Object System.Collections.Generic.List[object]
    $changed = $false
    foreach ($e in @($script:PelEvents.Values | Sort-Object Start)) {
        $delta = [int64]$e.Start - $now
        if ($e.Cancelled) {
            if ($script:PelEventsLocal.Seen.ContainsKey($e.Id) -and -not $script:PelEventsLocal.SeenCancel.ContainsKey($e.Id) -and $delta -gt -21600) {
                $items.Add([pscustomobject]@{ Kind = 'cancelled'; Event = $e })
                $script:PelEventsLocal.SeenCancel[$e.Id] = $true
                $changed = $true
            }
            continue
        }
        if ($delta -le -21600) { continue }
        if (-not $script:PelEventsLocal.Seen.ContainsKey($e.Id) -and $delta -le (3 * 86400)) {
            $items.Add([pscustomobject]@{ Kind = 'new'; Event = $e })
            $script:PelEventsLocal.Seen[$e.Id] = $true
            if ($delta -le 900) { $script:PelEventsLocal.Reminded[$e.Id] = $true }
            $changed = $true
            continue
        }
        if ($delta -gt 0 -and $delta -le 900 -and -not $script:PelEventsLocal.Reminded.ContainsKey($e.Id)) {
            $items.Add([pscustomobject]@{ Kind = 'reminder'; Event = $e })
            $script:PelEventsLocal.Reminded[$e.Id] = $true
            $changed = $true
        }
    }
    if ($changed) { Save-PelEventsLocal }
    return $items.ToArray()
}

function Format-PelAnnouncementText($Items) {
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($it in $Items) {
        $e = $it.Event
        $head = switch ($it.Kind) {
            'new'       { 'SPIELEABEND ANGEKÜNDIGT' }
            'reminder'  { 'GLEICH GEHT ES LOS' }
            'cancelled' { 'SPIELEABEND ABGESAGT' }
        }
        $t = "$head`r`n$($e.Title)"
        if ($e.Game) { $t += "`r`nSpiel: $($e.Game)" }
        $t += "`r`nWann: $(Format-PelEventWhen $e)"
        if ($e.Organizer) { $t += "`r`nVon: $($e.Organizer)" }
        if ($e.Note) { $t += "`r`nNotiz: $($e.Note)" }
        $parts.Add($t)
    }
    return ($parts -join "`r`n`r`n")
}

# Nicht-modales Hinweisfenster (blockiert den Live-Status nicht). Kommen weitere
# Meldungen, während es noch offen ist, werden sie unten angehängt.
function Show-PelEventAnnouncement {
    param($Items, $ParentForm = $null)
    if (-not $Items -or @($Items).Count -eq 0) { return }
    $text = Format-PelAnnouncementText $Items
    $script:PelAnnounceParent = $ParentForm
    if ($script:PelAnnounceForm -and -not $script:PelAnnounceForm.IsDisposed -and $script:PelAnnounceForm.Visible) {
        $script:PelAnnounceBox.AppendText("`r`n`r`n" + $text)
        try { $script:PelAnnounceForm.Activate() } catch { }
        return
    }
    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'Project Earth LAN - Spieleabend'
    $f.Size = New-Object System.Drawing.Size(500, 360)
    # Unten rechts statt mittig und NICHT "immer im Vordergrund": so verdeckt das Fenster
    # keine später geöffneten Dialoge (Planer, Meldungen, Dateiauswahl).
    $f.StartPosition = 'Manual'
    try {
        $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $f.Location = New-Object System.Drawing.Point(($wa.Right - $f.Width - 12), ($wa.Bottom - $f.Height - 12))
    } catch { $f.StartPosition = 'CenterScreen' }
    $f.FormBorderStyle = 'FixedDialog'
    $f.MaximizeBox = $false
    $f.MinimizeBox = $false
    $f.ShowInTaskbar = $true
    $f.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $f.ForeColor = [System.Drawing.Color]::White

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Multiline = $true
    $tb.ReadOnly = $true
    $tb.ScrollBars = 'Vertical'
    $tb.Location = New-Object System.Drawing.Point(12, 12)
    $tb.Size = New-Object System.Drawing.Size(460, 245)
    $tb.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
    $tb.ForeColor = [System.Drawing.Color]::White
    $tb.BorderStyle = 'FixedSingle'
    $tb.Font = New-Object System.Drawing.Font('Segoe UI', 10.5, [System.Drawing.FontStyle]::Regular)
    $tb.Text = $text
    $f.Controls.Add($tb)

    $btnPlan = New-Object System.Windows.Forms.Button
    $btnPlan.Text = 'Planer öffnen'
    $btnPlan.Location = New-Object System.Drawing.Point(212, 270)
    $btnPlan.Size = New-Object System.Drawing.Size(125, 32)
    $btnPlan.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
    $btnPlan.ForeColor = [System.Drawing.Color]::White
    $btnPlan.FlatStyle = 'Flat'
    $btnPlan.Add_Click({
        $af = $this.FindForm()
        $script:PelAnnounceForm = $null
        $af.Close()
        Show-PelGameNightPlanner -ParentForm $script:PelAnnounceParent
    })
    $f.Controls.Add($btnPlan)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = 'OK'
    $btnOk.Location = New-Object System.Drawing.Point(347, 270)
    $btnOk.Size = New-Object System.Drawing.Size(125, 32)
    $btnOk.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnOk.ForeColor = [System.Drawing.Color]::White
    $btnOk.FlatStyle = 'Flat'
    $btnOk.Add_Click({ $this.FindForm().Close() })
    $f.Controls.Add($btnOk)
    $f.AcceptButton = $btnOk

    $script:PelAnnounceForm = $f
    $script:PelAnnounceBox = $tb
    $f.Show()
    try { $f.Activate(); $tb.Select(0, 0) } catch { }
}

# ------------------------------------------------------------------------------
# EIGENE SPIELE FUER DEN SPIELEABEND-PLANER
# ------------------------------------------------------------------------------
# Im Planer kann man das Spiel aus der Liste waehlen ODER einfach selbst eintippen
# (z. B. "Doom 3 Open Coop", Mods, Total Conversions, Spiele ohne Verknuepfung).
# Jedes selbst eingetippte Spiel wird hier gemerkt und steht beim naechsten Mal in
# der Liste. Die Datei ist eine einfache Textdatei, eine Zeile pro Spiel - sie kann
# auch von Hand bearbeitet werden.
$script:PelOwnGamesPath = 'C:\Project-Earth-Lan\eigene_spiele.txt'

function Get-PelOwnGames {
    $list = New-Object System.Collections.Generic.List[string]
    try {
        if ([System.IO.File]::Exists($script:PelOwnGamesPath)) {
            foreach ($line in ((Read-PelTextFile $script:PelOwnGamesPath) -split "`r?`n")) {
                $t = Limit-PelText $line 60
                if (-not $t -or $t.StartsWith('#')) { continue }
                $dup = $false
                foreach ($g in $list) { if ($g -eq $t) { $dup = $true; break } }
                if (-not $dup) { $list.Add($t) }
            }
        }
    } catch { }
    # Komma davor: sonst würde PowerShell die Liste in Einzelwerte auflösen und der
    # Aufrufer bekäme bei einem Eintrag einen String und bei keinem Eintrag $null.
    return ,$list
}

function Save-PelOwnGames($Games) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# Eigene Spiele für den Spieleabend-Planer (Control Center -> Spieleabend-Planer).')
    [void]$sb.AppendLine('# Eine Zeile pro Spiel. Zeilen mit # am Anfang werden übersprungen.')
    foreach ($g in @($Games)) {
        $t = Limit-PelText $g 60
        if ($t -and -not $t.StartsWith('#')) { [void]$sb.AppendLine($t) }
    }
    try { Write-PelTextFileAtomic $script:PelOwnGamesPath $sb.ToString(); return $true } catch { return $false }
}

# Fügt ein selbst eingetipptes Spiel hinzu (doppelte Namen werden ignoriert).
function Add-PelOwnGame([string]$Name) {
    $n = Limit-PelText $Name 60
    if (-not $n -or $n.StartsWith('#')) { return $false }
    $list = Get-PelOwnGames
    foreach ($g in $list) { if ($g -eq $n) { return $false } }
    $list.Add($n)
    return (Save-PelOwnGames @($list | Sort-Object))
}

# Kleines Fenster zum Pflegen der eigenen Spiele (hinzufügen/entfernen).
function Show-PelOwnGamesDialog {
    param($ParentForm = $null)
    $cBg = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $cInput = [System.Drawing.Color]::FromArgb(50, 50, 50)
    $fMain = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Regular)
    $fSmall = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Italic)

    $d = New-Object System.Windows.Forms.Form
    $d.Text = 'Eigene Spiele'
    $d.Size = New-Object System.Drawing.Size(430, 420)
    $d.StartPosition = if ($ParentForm) { 'CenterParent' } else { 'CenterScreen' }
    $d.FormBorderStyle = 'FixedDialog'
    $d.MaximizeBox = $false
    $d.MinimizeBox = $false
    $d.BackColor = $cBg
    $d.ForeColor = [System.Drawing.Color]::White
    $d.Font = $fMain

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = 'Spiele, die du selbst eingetragen hast (z. B. Mods oder Spiele ohne Verknüpfung):'
    $lbl.Location = New-Object System.Drawing.Point(12, 10)
    $lbl.Size = New-Object System.Drawing.Size(400, 34)
    $lbl.ForeColor = [System.Drawing.Color]::LightGray
    $lbl.Font = $fSmall
    $d.Controls.Add($lbl)

    $lb = New-Object System.Windows.Forms.ListBox
    $lb.Location = New-Object System.Drawing.Point(12, 46)
    $lb.Size = New-Object System.Drawing.Size(398, 230)
    $lb.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
    $lb.ForeColor = [System.Drawing.Color]::White
    $lb.Font = $fMain
    $d.Controls.Add($lb)

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location = New-Object System.Drawing.Point(12, 286)
    $tb.Size = New-Object System.Drawing.Size(268, 26)
    $tb.MaxLength = 60
    $tb.BackColor = $cInput
    $tb.ForeColor = [System.Drawing.Color]::White
    $tb.Font = $fMain
    $d.Controls.Add($tb)

    $mkBtn = {
        param([string]$t, [int]$x, [int]$y, [int]$w, [bool]$accent)
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $t
        $b.Location = New-Object System.Drawing.Point($x, $y)
        $b.Size = New-Object System.Drawing.Size($w, 30)
        if ($accent) { $b.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215) } else { $b.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45) }
        $b.ForeColor = [System.Drawing.Color]::White
        $b.FlatStyle = 'Flat'
        $b.Font = $fMain
        $d.Controls.Add($b)
        return $b
    }
    $btnAdd = & $mkBtn 'Hinzufügen' 288 284 122 $true
    $btnDel = & $mkBtn 'Ausgewähltes entfernen' 12 324 200 $false
    $btnOk  = & $mkBtn 'Fertig' 280 324 130 $false
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $d.AcceptButton = $btnAdd
    $d.CancelButton = $btnOk

    $fill = {
        $lb.BeginUpdate()
        $lb.Items.Clear()
        foreach ($g in @(Get-PelOwnGames | Sort-Object)) { [void]$lb.Items.Add($g) }
        $lb.EndUpdate()
    }
    & $fill

    $btnAdd.Add_Click({
        $n = Limit-PelText $tb.Text 60
        if (-not $n) { return }
        if (Add-PelOwnGame $n) { $tb.Text = ''; & $fill }
        else { Show-PelMsg "'$n' steht schon in der Liste." 'Eigene Spiele' ([System.Windows.Forms.MessageBoxIcon]::Information) $d; $tb.Text = '' }
    })
    $btnDel.Add_Click({
        if ($lb.SelectedIndex -lt 0) { return }
        $sel = [string]$lb.SelectedItem
        $rest = @(Get-PelOwnGames | Where-Object { $_ -ne $sel })
        [void](Save-PelOwnGames $rest)
        & $fill
    })
    [void]$d.ShowDialog($ParentForm)
    $d.Dispose()
}

function Show-PelGameNightPlanner {
    param($ParentForm = $null)
    $cBg = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $cInput = [System.Drawing.Color]::FromArgb(50, 50, 50)
    $fMain = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Regular)
    $fBold = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
    $fSmall = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Italic)

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Spieleabend-Planer'
    $dlg.Size = New-Object System.Drawing.Size(730, 590)
    $dlg.StartPosition = if ($ParentForm) { 'CenterParent' } else { 'CenterScreen' }
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.BackColor = $cBg
    $dlg.ForeColor = [System.Drawing.Color]::White
    $dlg.Font = $fMain

    $lv = New-Object System.Windows.Forms.ListView
    $lv.Location = New-Object System.Drawing.Point(12, 12)
    $lv.Size = New-Object System.Drawing.Size(690, 250)
    $lv.View = 'Details'
    $lv.FullRowSelect = $true
    $lv.HideSelection = $false
    $lv.MultiSelect = $false
    $lv.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
    $lv.ForeColor = [System.Drawing.Color]::White
    [void]$lv.Columns.Add('Wann', 205)
    [void]$lv.Columns.Add('Spiel', 145)
    [void]$lv.Columns.Add('Titel', 150)
    [void]$lv.Columns.Add('Von', 105)
    [void]$lv.Columns.Add('Status', 80)
    $dlg.Controls.Add($lv)

    $btnCancelEv = New-Object System.Windows.Forms.Button
    $btnCancelEv.Text = 'Ausgewählten absagen'
    $btnCancelEv.Location = New-Object System.Drawing.Point(12, 270)
    $btnCancelEv.Size = New-Object System.Drawing.Size(190, 30)
    $btnCancelEv.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
    $btnCancelEv.ForeColor = [System.Drawing.Color]::White
    $btnCancelEv.FlatStyle = 'Flat'
    $btnCancelEv.Enabled = $false
    $dlg.Controls.Add($btnCancelEv)

    $lblHint = New-Object System.Windows.Forms.Label
    $lblHint.Text = 'Absagen kann nur, wer den Spieleabend angelegt hat.'
    $lblHint.Location = New-Object System.Drawing.Point(215, 276)
    $lblHint.Size = New-Object System.Drawing.Size(487, 20)
    $lblHint.ForeColor = [System.Drawing.Color]::DarkGray
    $lblHint.Font = $fSmall
    $dlg.Controls.Add($lblHint)

    $grp = New-Object System.Windows.Forms.GroupBox
    $grp.Text = 'Neuen Spieleabend ankündigen'
    $grp.Location = New-Object System.Drawing.Point(12, 310)
    $grp.Size = New-Object System.Drawing.Size(690, 185)
    $grp.ForeColor = [System.Drawing.Color]::White
    $grp.Font = $fBold
    $dlg.Controls.Add($grp)

    $mkLabel = {
        param([string]$t, [int]$x, [int]$y, [int]$w)
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $t
        $l.Location = New-Object System.Drawing.Point($x, $y)
        $l.Size = New-Object System.Drawing.Size($w, 20)
        $l.Font = $fMain
        $l.ForeColor = [System.Drawing.Color]::White
        $grp.Controls.Add($l)
    }
    & $mkLabel 'Titel:' 15 31 60
    $tbTitle = New-Object System.Windows.Forms.TextBox
    $tbTitle.Location = New-Object System.Drawing.Point(80, 28)
    $tbTitle.Size = New-Object System.Drawing.Size(280, 24)
    $tbTitle.MaxLength = 60
    $tbTitle.Text = 'Spieleabend'
    $tbTitle.BackColor = $cInput
    $tbTitle.ForeColor = [System.Drawing.Color]::White
    $tbTitle.Font = $fMain
    $grp.Controls.Add($tbTitle)

    # Spiel: aus der Liste wählen ODER frei eintippen (z. B. "Doom 3 Open Coop").
    # Selbst eingetippte Spiele werden automatisch gemerkt (eigene_spiele.txt) und
    # stehen beim nächsten Mal mit in der Liste; über den Button "..." lassen sie
    # sich verwalten.
    & $mkLabel 'Spiel:' 380 31 55
    $cbGame = New-Object System.Windows.Forms.ComboBox
    $cbGame.Location = New-Object System.Drawing.Point(440, 28)
    $cbGame.Size = New-Object System.Drawing.Size(200, 24)
    $cbGame.DropDownStyle = 'DropDown'
    $cbGame.MaxLength = 60
    $cbGame.AutoCompleteMode = 'SuggestAppend'
    $cbGame.AutoCompleteSource = 'ListItems'
    $cbGame.BackColor = $cInput
    $cbGame.ForeColor = [System.Drawing.Color]::White
    $cbGame.Font = $fMain
    $grp.Controls.Add($cbGame)

    $fillGames = {
        $keep = [string]$cbGame.Text
        $gameNames = New-Object System.Collections.Generic.List[string]
        foreach ($og in (Get-PelOwnGames)) { $gameNames.Add([string]$og) }
        try {
            $lanFolder = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Lan Games'
            if ([System.IO.Directory]::Exists($lanFolder)) {
                foreach ($lnk in [System.IO.Directory]::GetFiles($lanFolder, '*.lnk')) { $gameNames.Add([System.IO.Path]::GetFileNameWithoutExtension($lnk)) }
            }
        } catch { }
        foreach ($r in $script:PelJoinRules) { if ($r.Match) { $gameNames.Add([string]$r.Title) } }
        $cbGame.BeginUpdate()
        $cbGame.Items.Clear()
        foreach ($gn in @($gameNames | Sort-Object -Unique)) { [void]$cbGame.Items.Add($gn) }
        $cbGame.EndUpdate()
        $cbGame.Text = $keep
    }
    & $fillGames

    $btnOwnGames = New-Object System.Windows.Forms.Button
    $btnOwnGames.Text = '...'
    $btnOwnGames.Location = New-Object System.Drawing.Point(645, 27)
    $btnOwnGames.Size = New-Object System.Drawing.Size(30, 26)
    $btnOwnGames.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
    $btnOwnGames.ForeColor = [System.Drawing.Color]::White
    $btnOwnGames.FlatStyle = 'Flat'
    $btnOwnGames.Font = $fBold
    $btnOwnGames.Add_Click({
        Show-PelOwnGamesDialog -ParentForm $dlg
        & $fillGames
    })
    $grp.Controls.Add($btnOwnGames)
    $tipPlanner = New-Object System.Windows.Forms.ToolTip
    $tipPlanner.SetToolTip($btnOwnGames, 'Eigene Spiele verwalten (hinzufügen/entfernen)')
    $tipPlanner.SetToolTip($cbGame, 'Spiel auswählen oder einfach eintippen - z. B. "Doom 3 Open Coop". Eigene Eingaben werden gemerkt.')

    & $mkLabel 'Datum:' 15 65 60
    $dtDate = New-Object System.Windows.Forms.DateTimePicker
    $dtDate.Location = New-Object System.Drawing.Point(80, 62)
    $dtDate.Size = New-Object System.Drawing.Size(130, 24)
    $dtDate.Format = 'Short'
    $dtDate.MinDate = [DateTime]::Today
    $dtDate.MaxDate = [DateTime]::Today.AddDays(59)
    $dtDate.Value = [DateTime]::Today.AddDays(1)
    $dtDate.Font = $fMain
    $grp.Controls.Add($dtDate)

    & $mkLabel 'Uhrzeit:' 225 65 60
    $dtTime = New-Object System.Windows.Forms.DateTimePicker
    $dtTime.Location = New-Object System.Drawing.Point(290, 62)
    $dtTime.Size = New-Object System.Drawing.Size(70, 24)
    $dtTime.Format = 'Custom'
    $dtTime.CustomFormat = 'HH:mm'
    $dtTime.ShowUpDown = $true
    $dtTime.Value = [DateTime]::Today.AddHours(20)
    $dtTime.Font = $fMain
    $grp.Controls.Add($dtTime)

    $btnCreate = New-Object System.Windows.Forms.Button
    $btnCreate.Text = 'Ankündigen'
    $btnCreate.Location = New-Object System.Drawing.Point(440, 59)
    $btnCreate.Size = New-Object System.Drawing.Size(235, 30)
    $btnCreate.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnCreate.ForeColor = [System.Drawing.Color]::White
    $btnCreate.FlatStyle = 'Flat'
    $btnCreate.Font = $fBold
    $grp.Controls.Add($btnCreate)

    & $mkLabel 'Notiz:' 15 99 60
    $tbNote = New-Object System.Windows.Forms.TextBox
    $tbNote.Location = New-Object System.Drawing.Point(80, 96)
    $tbNote.Size = New-Object System.Drawing.Size(595, 24)
    $tbNote.MaxLength = 160
    $tbNote.BackColor = $cInput
    $tbNote.ForeColor = [System.Drawing.Color]::White
    $tbNote.Font = $fMain
    $grp.Controls.Add($tbNote)

    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.Text = 'Spiel: aus der Liste wählen oder einfach selbst eintippen (z. B. "Doom 3 Open Coop") - eigene Eingaben merkt sich der Manager für das nächste Mal ("..." zum Verwalten).' + [Environment]::NewLine + 'Alle Project Earth LAN Manager im Netzwerk erhalten die Ankündigung automatisch - auch wer den Manager erst später öffnet (Hinweis ab 3 Tage vor Beginn).'
    $lblInfo.Location = New-Object System.Drawing.Point(15, 126)
    $lblInfo.Size = New-Object System.Drawing.Size(660, 52)
    $lblInfo.ForeColor = [System.Drawing.Color]::DarkGray
    $lblInfo.Font = $fSmall
    $grp.Controls.Add($lblInfo)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = 'Schließen'
    $btnClose.Location = New-Object System.Drawing.Point(572, 505)
    $btnClose.Size = New-Object System.Drawing.Size(130, 30)
    $btnClose.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
    $btnClose.ForeColor = [System.Drawing.Color]::White
    $btnClose.FlatStyle = 'Flat'
    $btnClose.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($btnClose)
    $dlg.CancelButton = $btnClose

    $plannerState = @{ Sig = '' }
    $updateList = {
        $now = Get-PelNowSec
        $rows = @($script:PelEvents.Values | Sort-Object Start)
        $sig = (($rows | ForEach-Object { "$($_.Id):$([int][bool]$_.Cancelled)" }) -join ',') + '|' + [int]($now / 60)
        if ($sig -eq $plannerState.Sig) { return }
        $plannerState.Sig = $sig
        $selId = $null
        if ($lv.SelectedItems.Count -gt 0) { $selId = $lv.SelectedItems[0].Tag.Id }
        $lv.BeginUpdate()
        $lv.Items.Clear()
        foreach ($e in $rows) {
            $delta = [int64]$e.Start - $now
            $own = $script:PelEventsLocal.Own.ContainsKey($e.Id)
            $status = 'geplant'
            if ($e.Cancelled) { $status = 'abgesagt' }
            elseif ($delta -le -21600) { $status = 'vorbei' }
            elseif ($delta -le 0) { $status = 'läuft' }
            $it = New-Object System.Windows.Forms.ListViewItem((Format-PelEventWhen $e))
            [void]$it.SubItems.Add([string]$e.Game)
            [void]$it.SubItems.Add([string]$e.Title)
            $who = [string]$e.Organizer
            if ($own) { $who = "$who (du)" }
            [void]$it.SubItems.Add($who)
            [void]$it.SubItems.Add($status)
            $it.Tag = $e
            if ($e.Cancelled -or $status -eq 'vorbei') { $it.ForeColor = [System.Drawing.Color]::Gray }
            elseif ($own) { $it.ForeColor = [System.Drawing.Color]::LightSkyBlue }
            elseif ($delta -le 3 * 86400) { $it.ForeColor = [System.Drawing.Color]::LightGreen }
            if ($e.Note) { $it.ToolTipText = "Notiz: $($e.Note)" }
            [void]$lv.Items.Add($it)
            if ($selId -and $e.Id -eq $selId) { $it.Selected = $true }
        }
        $lv.EndUpdate()
        if ($rows.Count -eq 0) { $lblHint.Text = 'Noch kein Spieleabend geplant.' }
    }
    $lv.ShowItemToolTips = $true

    $lv.Add_SelectedIndexChanged({
        $ok = $false
        if ($lv.SelectedItems.Count -gt 0) {
            $e = $lv.SelectedItems[0].Tag
            $ok = ($script:PelEventsLocal.Own.ContainsKey($e.Id) -and -not $e.Cancelled -and (([int64]$e.Start + 21600) -gt (Get-PelNowSec)))
        }
        $btnCancelEv.Enabled = $ok
    })

    $btnCancelEv.Add_Click({
        if ($lv.SelectedItems.Count -eq 0) { return }
        $e = $lv.SelectedItems[0].Tag
        $ans = [System.Windows.Forms.MessageBox]::Show($dlg, "Spieleabend '$($e.Title)' am $(Format-PelEventWhen $e) wirklich absagen?`n`nAlle Manager im Netzwerk bekommen die Absage automatisch.", 'Spieleabend absagen', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        if (Stop-PelGameNight $e.Id) {
            $lblHint.Text = 'Abgesagt - die Absage wird jetzt an alle Manager verteilt.'
            $plannerState.Sig = ''
            & $updateList
            $btnCancelEv.Enabled = $false
        }
    })

    $btnCreate.Add_Click({
        $startLocal = $dtDate.Value.Date.Add($dtTime.Value.TimeOfDay)
        $startLocal = $startLocal.AddSeconds(-$startLocal.Second)
        if ($startLocal -lt (Get-Date).AddMinutes(5)) {
            [void][System.Windows.Forms.MessageBox]::Show($dlg, 'Der Spieleabend muss mindestens 5 Minuten in der Zukunft liegen.', 'Spieleabend-Planer', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        $title = $tbTitle.Text.Trim()
        if (-not $title) { $title = 'Spieleabend' }
        # Selbst eingetipptes Spiel für das nächste Mal merken (steht es schon in der
        # Liste, passiert nichts).
        $gameText = Limit-PelText $cbGame.Text 60
        if ($gameText -and $cbGame.FindStringExact($gameText) -lt 0) {
            if (Add-PelOwnGame $gameText) { & $fillGames }
        }
        $e = New-PelGameNight -Title $title -Game $gameText -Note $tbNote.Text.Trim() -StartLocal $startLocal
        $lblHint.Text = "Angekündigt: $(Format-PelEventWhen $e -Short) - wird jetzt an alle Manager verteilt."
        $tbNote.Text = ''
        $plannerState.Sig = ''
        & $updateList
    })

    $plannerTimer = New-Object System.Windows.Forms.Timer
    $plannerTimer.Interval = 2000
    $plannerTimer.Add_Tick({ & $updateList })
    $dlg.Add_FormClosed({ $plannerTimer.Stop(); $plannerTimer.Dispose() })

    & $updateList
    $plannerTimer.Start()
    if ($ParentForm) { [void]$dlg.ShowDialog($ParentForm) } else { [void]$dlg.ShowDialog() }
    $dlg.Dispose()
}

# ------------------------------------------------------------------------------
# FEHLERPROTOKOLL & FEHLERLOG-EXPORT (Control Center -> "Fehlerlog exportieren")
# ------------------------------------------------------------------------------
# Jedes Fenster (Control Center und jede Option in ihrem eigenen Prozess) schreibt seine
# Fehler alle 20 Sekunden und beim Beenden nach C:\Project-Earth-Lan\logs\<Fenster>.log.
# Viele Fehler werden im Skript bewusst still abgefangen (damit die Oberfläche weiterläuft);
# PowerShell merkt sie sich trotzdem in $Error - genau diese Liste wird hier protokolliert.
# Gleiche Fehler aus einem Intervall werden zu einer Zeile ("12x ...") zusammengefasst.
$script:PelLogDir = 'C:\Project-Earth-Lan\logs'
$script:PelLogContext = 'Manager'
$script:PelLogLastErr = $null
$script:PelLogTimer = $null
$script:PelLogIgnore = '(?i)(No|keine)\b.{0,40}MSFT_Net\w+|MSFT_Net\w+.{0,60}(nicht gefunden|not found)'

function Write-PelLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        if (-not [System.IO.Directory]::Exists($script:PelLogDir)) { [void][System.IO.Directory]::CreateDirectory($script:PelLogDir) }
        $file = Join-Path $script:PelLogDir ("{0}.log" -f $script:PelLogContext)
        $fi = New-Object System.IO.FileInfo($file)
        if ($fi.Exists -and $fi.Length -gt 1MB) {
            $old = "$file.1"
            if ([System.IO.File]::Exists($old)) { [System.IO.File]::Delete($old) }
            [System.IO.File]::Move($file, $old)
        }
        $line = "{0} [{1}] {2}`r`n" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
        [System.IO.File]::AppendAllText($file, $line, [System.Text.Encoding]::UTF8)
    } catch { }
}

function Save-PelErrorRecords {
    try {
        $new = New-Object System.Collections.Generic.List[object]
        foreach ($er in $global:Error) {
            if ([object]::ReferenceEquals($er, $script:PelLogLastErr)) { break }
            $new.Add($er)
            if ($new.Count -ge 300) { break }
        }
        if ($new.Count -eq 0) { return }
        $script:PelLogLastErr = $global:Error[0]
        $groups = [ordered]@{}
        for ($i = $new.Count - 1; $i -ge 0; $i--) {
            $er = $new[$i]
            $msg = ''
            $where = ''
            if ($er -is [System.Management.Automation.ErrorRecord]) {
                $msg = [string]$er.Exception.Message
                if ($er.InvocationInfo -and $er.InvocationInfo.ScriptLineNumber -gt 0) {
                    $where = "Zeile $($er.InvocationInfo.ScriptLineNumber): $(([string]$er.InvocationInfo.Line).Trim())"
                }
            } else {
                $msg = [string]$er
            }
            $msg = ($msg -replace '\s+', ' ').Trim()
            if ($msg -match $script:PelLogIgnore) { continue }
            if ($msg.Length -gt 400) { $msg = $msg.Substring(0, 400) + ' ...' }
            if ($where.Length -gt 220) { $where = $where.Substring(0, 220) + ' ...' }
            $k = if ($where) { "$msg | $where" } else { $msg }
            if ($groups.Contains($k)) { $groups[$k] = $groups[$k] + 1 } else { $groups[$k] = 1 }
        }
        foreach ($k in $groups.Keys) {
            $n = [int]$groups[$k]
            $txt = if ($n -gt 1) { "${n}x $k" } else { $k }
            Write-PelLog -Level 'FEHLER' -Message $txt
        }
    } catch { }
}

function Start-PelErrorLogging([string]$Context) {
    $c = ($Context -replace '[^A-Za-z0-9_-]', '')
    if ($c) { $script:PelLogContext = $c }
    $kind = if ($script:IsCompiledExe) { 'EXE' } else { 'PS1' }
    Write-PelLog "Start - Version $($script:PelVersion), Fenster $Context, PID $PID, $kind`: $($script:SelfPath)"
    try {
        $script:PelLogTimer = New-Object System.Windows.Forms.Timer
        $script:PelLogTimer.Interval = 20000
        $script:PelLogTimer.Add_Tick({ Save-PelErrorRecords })
        $script:PelLogTimer.Start()
    } catch { }
}

function Stop-PelErrorLogging {
    try { if ($script:PelLogTimer) { $script:PelLogTimer.Stop() } } catch { }
    Save-PelErrorRecords
    Write-PelLog 'Ende'
}

# Packt alles, was zur Fehlersuche gebraucht wird, in eine ZIP-Datei auf dem Desktop.
# Bewusst NICHT enthalten: Chat-Verläufe, Postfach, Freundesliste, Passwörter, Netzwerk-Code/
# Schlüssel (C:\Project-Earth-Lan\keys, network_code.json).
function Export-PelErrorLog {
    param($ParentForm = $null)
    if ($ParentForm) { $ParentForm.Cursor = [System.Windows.Forms.Cursors]::WaitCursor }
    $zipPath = $null
    try {
        Save-PelErrorRecords
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $work = Join-Path $env:TEMP "PEL_Fehlerlog_$stamp"
        [void][System.IO.Directory]::CreateDirectory($work)
        $utf8 = New-Object System.Text.UTF8Encoding($true)
        $writeFile = { param([string]$name, [string]$text) [System.IO.File]::WriteAllText((Join-Path $work $name), $text, $utf8) }
        $section = {
            param([string]$title, [scriptblock]$body)
            $o = "===== $title =====`r`n"
            try { $o += ((& $body) | Out-String -Width 220) } catch { $o += "Fehler: $($_.Exception.Message)`r`n" }
            return ($o + "`r`n")
        }

        if ([System.IO.Directory]::Exists($script:PelLogDir)) {
            foreach ($lf in [System.IO.Directory]::GetFiles($script:PelLogDir)) { Copy-Item -LiteralPath $lf -Destination $work -Force -ErrorAction SilentlyContinue }
        }
        foreach ($cfgFile in @($script:PelAdapterConfigPath, $script:PelEventsPath)) {
            if ($cfgFile -and [System.IO.File]::Exists($cfgFile)) { Copy-Item -LiteralPath $cfgFile -Destination $work -Force -ErrorAction SilentlyContinue }
        }

        $sys = ''
        $sys += & $section 'Project Earth LAN Manager' {
            [pscustomobject]@{
                Version          = $script:PelVersion
                NeuesteGitHub    = $script:PelGitHubLatest
                Autostart        = (Test-PelAutostart)
                Kompiliert       = $script:IsCompiledExe
                Pfad             = $script:SelfPath
                Zeit             = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz')
                Computer         = $env:COMPUTERNAME
                Anzeigename      = (Get-PelDisplayName)
                Admin            = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
                PowerShell       = $PSVersionTable.PSVersion.ToString()
                DotNet           = [Environment]::Version.ToString()
            } | Format-List
        }
        $sys += & $section 'Betriebssystem' { Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber, OSArchitecture, LastBootUpTime | Format-List }
        $sys += & $section 'Laufende Manager-Fenster' {
            Get-CimInstance Win32_Process | Where-Object { ([string]$_.CommandLine -match '(?i)project.?earth|-Option\s+\d') -or ($script:SelfPath -and [string]$_.ExecutablePath -eq $script:SelfPath) } |
                Select-Object ProcessId, Name, CommandLine | Format-Table -AutoSize -Wrap
        }
        $sys += & $section 'Aktuell erkanntes Spiel (Wer spielt was)' { if ($script:PelMyGame) { $script:PelMyGame | Format-List } else { 'keins erkannt' } }
        $sys += & $section 'Andere Manager im Netz' { if ($script:PelOtherManagers) { $script:PelOtherManagers.Values | Select-Object Name, Ip, SrcIp, Zt, Version, Game, JoinPort, Server | Format-Table -AutoSize } else { '-' } }
        $sys += & $section 'Spieleabende' {
            $script:PelEvents.Values | Select-Object Id, Title, Game, Organizer, @{ n = 'Beginn'; e = { [DateTimeOffset]::FromUnixTimeSeconds([int64]$_.Start).LocalDateTime } }, Cancelled | Format-Table -AutoSize
        }
        & $writeFile 'system.txt' $sys

        $net = ''
        $net += & $section 'Netzwerkadapter' { Get-PelAdapterList | Format-Table Name, Description, Ip, Mask, Metric, IsZeroTier -AutoSize }
        $net += & $section 'Zentral gewählter Adapter' { if ([System.IO.File]::Exists($script:PelAdapterConfigPath)) { Get-Content -LiteralPath $script:PelAdapterConfigPath -Raw } else { 'keiner' } }
        $net += & $section 'ipconfig /all' { ipconfig /all }
        $net += & $section 'Routen (IPv4)' { route print -4 }
        & $writeFile 'netzwerk.txt' $net

        $zt = ''
        $cli = Get-ZeroTierCli
        $zt += & $section 'zerotier-cli info' { & $cli info 2>&1 }
        $zt += & $section 'zerotier-cli listnetworks' { & $cli listnetworks 2>&1 }
        $zt += & $section 'zerotier-cli peers (DIRECT = direkte Verbindung, RELAY = über ZeroTier-Server, oft Lag)' { & $cli peers 2>&1 }
        & $writeFile 'zerotier.txt' $zt

        $pelPorts = @(9776, 9870, 9872, 9873, 9874, 9875, 9876, 9928, 9929)
        $fw = ''
        $fw += & $section 'Firewall-Regeln (Project Earth)' {
            foreach ($r in @(Get-NetFirewallRule -DisplayName 'Project Earth*' -ErrorAction SilentlyContinue)) {
                $pf = $r | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
                [pscustomobject]@{ Name = $r.DisplayName; Aktiv = $r.Enabled; Richtung = $r.Direction; Aktion = $r.Action; Profil = $r.Profile; Protokoll = $pf.Protocol; Port = (@($pf.LocalPort) -join ',') }
            }
        }
        $fw += & $section 'Belegte Manager-Ports' {
            $pn = @{}
            foreach ($pr in @(Get-Process -ErrorAction SilentlyContinue)) { $pn[$pr.Id] = $pr.ProcessName }
            $rows = @()
            foreach ($u in @(Get-NetUDPEndpoint -ErrorAction SilentlyContinue)) {
                if ($pelPorts -contains [int]$u.LocalPort) { $rows += [pscustomobject]@{ Proto = 'UDP'; Adresse = $u.LocalAddress; Port = $u.LocalPort; Prozess = $pn[[int]$u.OwningProcess]; PID = $u.OwningProcess } }
            }
            foreach ($t in @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue)) {
                if ($pelPorts -contains [int]$t.LocalPort) { $rows += [pscustomobject]@{ Proto = 'TCP'; Adresse = $t.LocalAddress; Port = $t.LocalPort; Prozess = $pn[[int]$t.OwningProcess]; PID = $t.OwningProcess } }
            }
            $rows | Sort-Object Port | Format-Table -AutoSize
        }
        & $writeFile 'firewall_ports.txt' $fw

        $ev = & $section 'Programmabstürze (Windows-Ereignisprotokoll, letzte 7 Tage)' {
            $leaf = 'powershell.exe'
            if ($script:SelfPath) { $leaf = [System.IO.Path]::GetFileName($script:SelfPath) }
            Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = @('.NET Runtime', 'Application Error'); StartTime = (Get-Date).AddDays(-7) } -MaxEvents 300 -ErrorAction SilentlyContinue |
                Where-Object { ($_.Message -match [regex]::Escape($leaf)) -or ($_.Message -match '(?i)powershell\.exe') } |
                Select-Object -First 20 |
                ForEach-Object { "[$($_.TimeCreated)] $($_.ProviderName) ($($_.Id))`r`n$($_.Message)`r`n" }
        }
        & $writeFile 'abstuerze.txt' $ev

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $desk = [Environment]::GetFolderPath('Desktop')
        $zipPath = Join-Path $desk ("ProjectEarthLan_Fehlerlog_{0}_{1}.zip" -f $env:COMPUTERNAME, $stamp)
        [System.IO.Compression.ZipFile]::CreateFromDirectory($work, $zipPath)
        try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue } catch { }
    } catch {
        if ($ParentForm) { $ParentForm.Cursor = [System.Windows.Forms.Cursors]::Default }
        Show-PelMsg "Fehlerlog konnte nicht erstellt werden:`n$($_.Exception.Message)" 'Fehlerlog' ([System.Windows.Forms.MessageBoxIcon]::Error) $ParentForm
        return
    } finally {
        if ($ParentForm) { $ParentForm.Cursor = [System.Windows.Forms.Cursors]::Default }
    }
    $msg = "Fehlerlog gespeichert:`n$zipPath`n`nEnthalten: Protokolle aller Fenster, System-, Netzwerk- und ZeroTier-Infos, Firewallregeln, belegte Ports und Absturzmeldungen.`nNicht enthalten: Chats, Postfach-Nachrichten, Freundesliste, Passwörter, Schlüssel.`n`nAchtung: Die Datei enthält IP-Adressen und den Computernamen - nur an Leute schicken, denen du vertraust.`n`nOrdner jetzt öffnen?"
    $ans = if ($ParentForm) { [System.Windows.Forms.MessageBox]::Show($ParentForm, $msg, 'Fehlerlog exportiert', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Information) } else { [System.Windows.Forms.MessageBox]::Show($msg, 'Fehlerlog exportiert', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Information) }
    if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) {
        try { Start-Process -FilePath 'explorer.exe' -ArgumentList "/select,`"$zipPath`"" } catch { }
    }
}

# ------------------------------------------------------------------------------
# POSTFACH (Option 11) - gemeinsamer Teil für Control Center und Option 11
# ------------------------------------------------------------------------------
# Nachrichten an andere Project-Earth-LAN-Nutzer (Empfänger = seine ZeroTier-IP):
#  - Ist der Empfänger online, kommt die Nachricht sofort an (TCP 9929, "live").
#  - Sonst bleibt sie im Ausgang und wird automatisch zugestellt, sobald sein Manager
#    wieder läuft (erkannt an seiner Live-Status-Meldung auf Port 9928).
#  - Zusätzlich bekommen bis zu 3 gerade laufende Manager eine VERSCHLÜSSELTE Kopie
#    (nur der Empfänger kann sie öffnen) und liefern sie aus, falls der Absender
#    inzwischen selbst offline ist. Der Absender unterschreibt jede Nachricht, der
#    Empfänger sieht dadurch, ob sie wirklich von dieser IP stammt.
# Gespeichert wird alles unter C:\Project-Earth-Lan\Postfach (eine Datei pro Nachricht).
# Der eigene Postfach-Schlüssel liegt DPAPI-geschützt (nur dein Windows-Konto kann ihn
# lesen) in C:\Project-Earth-Lan\keys\postfach_schluessel.dat.
# Der Dienst läuft pro PC nur einmal: im Control Center - oder, wenn das geschlossen
# ist, im Fenster von Option 11.
$script:PelMailPort = 9929
$script:PelMailKeyPath = 'C:\Project-Earth-Lan\keys\postfach_schluessel.dat'
$script:PelMailNode = $null
$script:PelMailMutex = $null
$script:PelMailNoteForm = $null
$script:PelMailNoteBox = $null
$script:PelMailCode = @'
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

// -----------------------------------------------------------------------------
// Postfach (Option 11): eine Nachricht = eine Datei (*.msg, UTF-8, Schluessel=Wert).
// Eine Datei pro Nachricht, damit Control Center und Option-11-Fenster gleichzeitig
// damit arbeiten koennen, ohne sich gegenseitig eine gemeinsame Datei zu ueberschreiben.
// -----------------------------------------------------------------------------
public class EarthMailMsg
{
    public string Id = "";
    public string FromName = "";
    public string FromIp = "";
    public string ToName = "";
    public string ToIp = "";
    public string Subject = "";
    public string Body = "";
    public long CreatedUtc;
    public long ReceivedUtc;
    public long DeliveredUtc;
    public bool Read;
    public string Via = "";
    public bool Verified;
    public int Attempts;
    public long NextTryUtc;
    public string LastError = "";
    public bool Relayed;
    public string RelayedTo = "";
    public string Blob = "";
    public long ExpiresUtc;
    public string FilePath = "";
}

public static class EarthMailStore
{
    public static string Root = @"C:\Project-Earth-Lan\Postfach";
    public const int MaxSubject = 100;
    public const int MaxBody = 4000;
    private static readonly object seenLock = new object();
    private static HashSet<string> seen;
    private static readonly Regex IdRx = new Regex("^[0-9a-f]{32}$");

    public static string Inbox { get { return Path.Combine(Root, "Eingang"); } }
    public static string Outbox { get { return Path.Combine(Root, "Ausgang"); } }
    public static string Sent { get { return Path.Combine(Root, "Gesendet"); } }
    public static string Relay { get { return Path.Combine(Root, "Weiterleitung"); } }
    public static string Keys { get { return Path.Combine(Root, "Schluessel"); } }
    public static string SeenFile { get { return Path.Combine(Root, "empfangen.ids"); } }
    public static string OnlineFile { get { return Path.Combine(Root, "online.txt"); } }

    public static long Now() { return (long)(DateTime.UtcNow - new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalMilliseconds; }

    public static void EnsureDirs()
    {
        foreach (string d in new string[] { Root, Inbox, Outbox, Sent, Relay, Keys })
        {
            try { if (!Directory.Exists(d)) Directory.CreateDirectory(d); } catch (Exception) { }
        }
    }

    public static bool IsValidId(string id) { return id != null && IdRx.IsMatch(id); }
    public static string NewId() { return Guid.NewGuid().ToString("N"); }

    public static bool IsValidIp(string ip)
    {
        IPAddress a;
        if (string.IsNullOrEmpty(ip) || !IPAddress.TryParse(ip, out a)) return false;
        if (a.AddressFamily != AddressFamily.InterNetwork) return false;
        return a.ToString() == ip;
    }

    public static string Clean(string s, int max)
    {
        if (s == null) return "";
        s = s.Replace("\r", "");
        if (s.Length > max) s = s.Substring(0, max);
        return s;
    }

    public static string OneLine(string s, int max)
    {
        if (s == null) return "";
        s = s.Replace("\r", " ").Replace("\n", " ").Replace("|", "/").Trim();
        if (s.Length > max) s = s.Substring(0, max);
        return s;
    }

    public static string Esc(string s)
    {
        if (s == null) return "";
        StringBuilder sb = new StringBuilder();
        foreach (char c in s)
        {
            if (c == '\\') sb.Append("\\\\");
            else if (c == '\n') sb.Append("\\n");
            else if (c == '\r') { }
            else sb.Append(c);
        }
        return sb.ToString();
    }

    public static string Unesc(string s)
    {
        if (s == null) return "";
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < s.Length; i++)
        {
            char c = s[i];
            if (c == '\\' && i + 1 < s.Length)
            {
                char n = s[i + 1];
                if (n == 'n') { sb.Append('\n'); i++; continue; }
                if (n == '\\') { sb.Append('\\'); i++; continue; }
            }
            sb.Append(c);
        }
        return sb.ToString();
    }

    public static string ToText(EarthMailMsg m)
    {
        StringBuilder sb = new StringBuilder();
        sb.Append("PEMSG1\n");
        sb.Append("Id=" + Esc(m.Id) + "\n");
        sb.Append("FromName=" + Esc(m.FromName) + "\n");
        sb.Append("FromIp=" + Esc(m.FromIp) + "\n");
        sb.Append("ToName=" + Esc(m.ToName) + "\n");
        sb.Append("ToIp=" + Esc(m.ToIp) + "\n");
        sb.Append("Subject=" + Esc(m.Subject) + "\n");
        sb.Append("CreatedUtc=" + m.CreatedUtc + "\n");
        sb.Append("ReceivedUtc=" + m.ReceivedUtc + "\n");
        sb.Append("DeliveredUtc=" + m.DeliveredUtc + "\n");
        sb.Append("Read=" + (m.Read ? "1" : "0") + "\n");
        sb.Append("Via=" + Esc(m.Via) + "\n");
        sb.Append("Verified=" + (m.Verified ? "1" : "0") + "\n");
        sb.Append("Attempts=" + m.Attempts + "\n");
        sb.Append("NextTryUtc=" + m.NextTryUtc + "\n");
        sb.Append("LastError=" + Esc(m.LastError) + "\n");
        sb.Append("Relayed=" + (m.Relayed ? "1" : "0") + "\n");
        sb.Append("RelayedTo=" + Esc(m.RelayedTo) + "\n");
        sb.Append("ExpiresUtc=" + m.ExpiresUtc + "\n");
        sb.Append("Blob=" + Esc(m.Blob) + "\n");
        sb.Append("Body=" + Esc(m.Body) + "\n");
        return sb.ToString();
    }

    public static EarthMailMsg FromText(string t)
    {
        if (t == null || !t.StartsWith("PEMSG1")) return null;
        EarthMailMsg m = new EarthMailMsg();
        foreach (string raw in t.Split('\n'))
        {
            string l = raw.TrimEnd('\r');
            int eq = l.IndexOf('=');
            if (eq <= 0) continue;
            string k = l.Substring(0, eq);
            string v = Unesc(l.Substring(eq + 1));
            long n; int ni;
            switch (k)
            {
                case "Id": m.Id = v; break;
                case "FromName": m.FromName = v; break;
                case "FromIp": m.FromIp = v; break;
                case "ToName": m.ToName = v; break;
                case "ToIp": m.ToIp = v; break;
                case "Subject": m.Subject = v; break;
                case "Body": m.Body = v; break;
                case "CreatedUtc": if (long.TryParse(v, out n)) m.CreatedUtc = n; break;
                case "ReceivedUtc": if (long.TryParse(v, out n)) m.ReceivedUtc = n; break;
                case "DeliveredUtc": if (long.TryParse(v, out n)) m.DeliveredUtc = n; break;
                case "Read": m.Read = (v == "1"); break;
                case "Via": m.Via = v; break;
                case "Verified": m.Verified = (v == "1"); break;
                case "Attempts": if (int.TryParse(v, out ni)) m.Attempts = ni; break;
                case "NextTryUtc": if (long.TryParse(v, out n)) m.NextTryUtc = n; break;
                case "LastError": m.LastError = v; break;
                case "Relayed": m.Relayed = (v == "1"); break;
                case "RelayedTo": m.RelayedTo = v; break;
                case "ExpiresUtc": if (long.TryParse(v, out n)) m.ExpiresUtc = n; break;
                case "Blob": m.Blob = v; break;
            }
        }
        if (!IsValidId(m.Id)) return null;
        return m;
    }

    public static EarthMailMsg Load(string path)
    {
        try
        {
            EarthMailMsg m = FromText(File.ReadAllText(path, Encoding.UTF8));
            if (m != null) m.FilePath = path;
            return m;
        }
        catch (Exception) { return null; }
    }

    // Atomar schreiben (Temp-Datei + Ersetzen): ein Absturz hinterlaesst nie eine halbe Datei.
    public static bool Save(EarthMailMsg m, string dir)
    {
        try
        {
            if (!IsValidId(m.Id)) return false;
            if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
            string path = Path.Combine(dir, m.Id + ".msg");
            string tmp = path + "." + Guid.NewGuid().ToString("N").Substring(0, 8) + ".tmp";
            File.WriteAllText(tmp, ToText(m), new UTF8Encoding(false));
            if (File.Exists(path)) File.Replace(tmp, path, null);
            else File.Move(tmp, path);
            m.FilePath = path;
            return true;
        }
        catch (Exception) { return false; }
    }

    // Aktualisiert eine vorhandene Datei nur, wenn sie noch existiert - hat der Nutzer die
    // Nachricht inzwischen geloescht (z. B. "Senden abbrechen"), wird sie nicht neu angelegt.
    public static bool SaveIfExists(EarthMailMsg m, string dir)
    {
        string path = Path.Combine(dir, m.Id + ".msg");
        if (!File.Exists(path)) return false;
        return Save(m, dir);
    }

    public static List<EarthMailMsg> List(string dir)
    {
        List<EarthMailMsg> l = new List<EarthMailMsg>();
        try
        {
            if (!Directory.Exists(dir)) return l;
            foreach (string f in Directory.GetFiles(dir, "*.msg"))
            {
                EarthMailMsg m = Load(f);
                if (m != null) l.Add(m);
            }
        }
        catch (Exception) { }
        l.Sort(delegate (EarthMailMsg a, EarthMailMsg b)
        {
            long ta = a.ReceivedUtc > 0 ? a.ReceivedUtc : a.CreatedUtc;
            long tb = b.ReceivedUtc > 0 ? b.ReceivedUtc : b.CreatedUtc;
            return tb.CompareTo(ta);
        });
        return l;
    }

    public static int CountUnread()
    {
        int n = 0;
        foreach (EarthMailMsg m in List(Inbox)) { if (!m.Read) n++; }
        return n;
    }

    public static int CountFiles(string dir)
    {
        try { return Directory.Exists(dir) ? Directory.GetFiles(dir, "*.msg").Length : 0; } catch (Exception) { return 0; }
    }

    // Aendert sich, sobald in einem der Ordner eine Nachricht dazukommt, wegfaellt oder
    // geaendert wird - fuer die Anzeige (nur neu laden, wenn sich wirklich etwas getan hat).
    public static string Signature()
    {
        StringBuilder sb = new StringBuilder();
        foreach (string d in new string[] { Inbox, Outbox, Sent })
        {
            try
            {
                if (!Directory.Exists(d)) { sb.Append("0;"); continue; }
                string[] files = Directory.GetFiles(d, "*.msg");
                long max = 0;
                foreach (string f in files) { long t = File.GetLastWriteTimeUtc(f).Ticks; if (t > max) max = t; }
                sb.Append(files.Length).Append(':').Append(max).Append(';');
            }
            catch (Exception) { sb.Append("x;"); }
        }
        return sb.ToString();
    }

    // Bereits empfangene Nachrichten-IDs: verhindert Doppelte (direkt UND weitergeleitet)
    // und dass eine geloeschte Nachricht ueber eine Weiterleitung wieder auftaucht.
    private static void LoadSeen()
    {
        if (seen != null) return;
        seen = new HashSet<string>();
        try
        {
            if (File.Exists(SeenFile))
                foreach (string l in File.ReadAllLines(SeenFile)) { string t = l.Trim(); if (IsValidId(t)) seen.Add(t); }
        }
        catch (Exception) { }
        try
        {
            if (Directory.Exists(Inbox))
                foreach (string f in Directory.GetFiles(Inbox, "*.msg")) { string id = Path.GetFileNameWithoutExtension(f); if (IsValidId(id)) seen.Add(id); }
        }
        catch (Exception) { }
    }

    public static bool HasSeen(string id)
    {
        lock (seenLock) { LoadSeen(); return seen.Contains(id); }
    }

    public static void AddSeen(string id)
    {
        lock (seenLock)
        {
            LoadSeen();
            if (!seen.Add(id)) return;
            try
            {
                EnsureDirs();
                File.AppendAllText(SeenFile, id + "\n", Encoding.ASCII);
                if (seen.Count > 6000)
                {
                    string[] all = File.ReadAllLines(SeenFile);
                    int keep = Math.Min(all.Length, 5000);
                    string[] tail = new string[keep];
                    Array.Copy(all, all.Length - keep, tail, 0, keep);
                    File.WriteAllLines(SeenFile, tail);
                    seen = null;
                    LoadSeen();
                }
            }
            catch (Exception) { }
        }
    }

    public static string KeyPath(string ip) { return Path.Combine(Keys, ip.Replace(':', '_') + ".key"); }

    public static string LoadPeerKey(string ip)
    {
        try { string p = KeyPath(ip); return File.Exists(p) ? File.ReadAllText(p, Encoding.UTF8) : null; } catch (Exception) { return null; }
    }

    public static long PeerKeyAgeMs(string ip)
    {
        try { string p = KeyPath(ip); return File.Exists(p) ? (long)(DateTime.UtcNow - File.GetLastWriteTimeUtc(p)).TotalMilliseconds : long.MaxValue; } catch (Exception) { return long.MaxValue; }
    }

    public static void SavePeerKey(string ip, string xml)
    {
        try { EnsureDirs(); File.WriteAllText(KeyPath(ip), xml, new UTF8Encoding(false)); } catch (Exception) { }
    }
}

// -----------------------------------------------------------------------------
// Verschluesselung fuer weitergeleitete Nachrichten: nur der Empfaenger kann sie lesen
// (RSA-2048-OAEP fuer den Schluessel, AES-256-CBC + HMAC-SHA256 fuer den Inhalt), und
// der Absender unterschreibt den Inhalt (RSA-SHA256), damit der Empfaenger erkennt, ob
// die Nachricht wirklich von dieser IP stammt.
// -----------------------------------------------------------------------------
public static class EarthMailCrypto
{
    private static RSACryptoServiceProvider NewRsa(int bits)
    {
        RSACryptoServiceProvider r = bits > 0 ? new RSACryptoServiceProvider(bits) : new RSACryptoServiceProvider();
        try { r.PersistKeyInCsp = false; } catch (Exception) { }
        return r;
    }

    public static string MakeKeyPair(out string publicXml)
    {
        using (RSACryptoServiceProvider r = NewRsa(2048))
        {
            publicXml = r.ToXmlString(false);
            return r.ToXmlString(true);
        }
    }

    public static string PublicFromPrivate(string privateXml)
    {
        using (RSACryptoServiceProvider r = Rsa(privateXml)) return r.ToXmlString(false);
    }

    private static RSACryptoServiceProvider Rsa(string xml)
    {
        RSACryptoServiceProvider r = NewRsa(0);
        r.FromXmlString(xml);
        return r;
    }

    public static string Sign(string privateXml, string text)
    {
        using (RSACryptoServiceProvider r = Rsa(privateXml))
            return Convert.ToBase64String(r.SignData(Encoding.UTF8.GetBytes(text), "SHA256"));
    }

    public static bool Verify(string publicXml, string text, string sigB64)
    {
        try
        {
            using (RSACryptoServiceProvider r = Rsa(publicXml))
                return r.VerifyData(Encoding.UTF8.GetBytes(text), "SHA256", Convert.FromBase64String(sigB64));
        }
        catch (Exception) { return false; }
    }

    private static bool SameBytes(byte[] a, byte[] b)
    {
        if (a == null || b == null || a.Length != b.Length) return false;
        int d = 0;
        for (int i = 0; i < a.Length; i++) d |= a[i] ^ b[i];
        return d == 0;
    }

    public static string Seal(string recipientPublicXml, string plain)
    {
        byte[] aesKey = new byte[32];
        byte[] macKey = new byte[32];
        byte[] iv = new byte[16];
        using (RandomNumberGenerator rng = RandomNumberGenerator.Create()) { rng.GetBytes(aesKey); rng.GetBytes(macKey); rng.GetBytes(iv); }
        byte[] keys = new byte[64];
        Buffer.BlockCopy(aesKey, 0, keys, 0, 32);
        Buffer.BlockCopy(macKey, 0, keys, 32, 32);
        byte[] wrapped;
        using (RSACryptoServiceProvider r = Rsa(recipientPublicXml)) wrapped = r.Encrypt(keys, true);
        byte[] cipher;
        using (Aes aes = Aes.Create())
        {
            aes.KeySize = 256; aes.Mode = CipherMode.CBC; aes.Padding = PaddingMode.PKCS7;
            aes.Key = aesKey; aes.IV = iv;
            using (ICryptoTransform enc = aes.CreateEncryptor())
            {
                byte[] p = Encoding.UTF8.GetBytes(plain);
                cipher = enc.TransformFinalBlock(p, 0, p.Length);
            }
        }
        byte[] mac;
        using (HMACSHA256 h = new HMACSHA256(macKey))
        {
            byte[] macIn = new byte[iv.Length + cipher.Length];
            Buffer.BlockCopy(iv, 0, macIn, 0, iv.Length);
            Buffer.BlockCopy(cipher, 0, macIn, iv.Length, cipher.Length);
            mac = h.ComputeHash(macIn);
        }
        MemoryStream ms = new MemoryStream();
        ms.WriteByte(1);
        ms.WriteByte((byte)(wrapped.Length >> 8));
        ms.WriteByte((byte)(wrapped.Length & 0xFF));
        ms.Write(wrapped, 0, wrapped.Length);
        ms.Write(iv, 0, iv.Length);
        ms.Write(mac, 0, mac.Length);
        ms.Write(cipher, 0, cipher.Length);
        return Convert.ToBase64String(ms.ToArray());
    }

    public static string Open(string privateXml, string blobB64)
    {
        try
        {
            byte[] b = Convert.FromBase64String(blobB64);
            if (b.Length < 3 || b[0] != 1) return null;
            int wl = (b[1] << 8) | b[2];
            int pos = 3;
            if (b.Length < pos + wl + 16 + 32 + 16) return null;
            byte[] wrapped = new byte[wl]; Buffer.BlockCopy(b, pos, wrapped, 0, wl); pos += wl;
            byte[] iv = new byte[16]; Buffer.BlockCopy(b, pos, iv, 0, 16); pos += 16;
            byte[] mac = new byte[32]; Buffer.BlockCopy(b, pos, mac, 0, 32); pos += 32;
            byte[] cipher = new byte[b.Length - pos]; Buffer.BlockCopy(b, pos, cipher, 0, cipher.Length);
            byte[] keys;
            using (RSACryptoServiceProvider r = Rsa(privateXml)) keys = r.Decrypt(wrapped, true);
            if (keys.Length != 64) return null;
            byte[] aesKey = new byte[32]; Buffer.BlockCopy(keys, 0, aesKey, 0, 32);
            byte[] macKey = new byte[32]; Buffer.BlockCopy(keys, 32, macKey, 0, 32);
            using (HMACSHA256 h = new HMACSHA256(macKey))
            {
                byte[] macIn = new byte[iv.Length + cipher.Length];
                Buffer.BlockCopy(iv, 0, macIn, 0, iv.Length);
                Buffer.BlockCopy(cipher, 0, macIn, iv.Length, cipher.Length);
                if (!SameBytes(h.ComputeHash(macIn), mac)) return null;
            }
            using (Aes aes = Aes.Create())
            {
                aes.KeySize = 256; aes.Mode = CipherMode.CBC; aes.Padding = PaddingMode.PKCS7;
                aes.Key = aesKey; aes.IV = iv;
                using (ICryptoTransform dec = aes.CreateDecryptor())
                {
                    byte[] p = dec.TransformFinalBlock(cipher, 0, cipher.Length);
                    return Encoding.UTF8.GetString(p);
                }
            }
        }
        catch (Exception) { return null; }
    }
}

// -----------------------------------------------------------------------------
// Postfach-Dienst (TCP 9929): nimmt Nachrichten an, stellt den Ausgang zu (sofort, wenn
// der Empfaenger online ist, sonst automatisch, sobald er wieder auftaucht) und haelt
// verschluesselte Kopien fuer andere bereit (Weiterleitung), damit eine Nachricht auch
// dann ankommt, wenn der Absender inzwischen selbst offline ist.
// Laeuft pro PC nur einmal (Control Center oder, falls das zu ist, Option 11).
// -----------------------------------------------------------------------------
public class EarthMailNode
{
    public int Port = 9929;
    public int StatusPort = 9928;
    public string BindIp = "0.0.0.0";
    public string Secret = "";
    public string PrivateKeyXml = "";
    public string PublicKeyXml = "";
    public string MyName = "";
    // Eigenes Mithoeren der Live-Status-Meldungen (Port 9928). Im Control Center aus:
    // das meldet die Teilnehmer selbst per NotePeer, damit sich nicht zwei Sockets im
    // selben Prozess denselben Port teilen muessen.
    public bool ListenStatus = true;
    public int MaxRelayHolders = 3;
    public int ConnectTimeoutMs = 2500;
    public ConcurrentQueue<string> Events = new ConcurrentQueue<string>();

    private volatile bool running;
    private TcpListener listener;
    private UdpClient statRx;
    private readonly object lk = new object();
    private Dictionary<string, long> onlineSeen = new Dictionary<string, long>();
    private Dictionary<string, string> onlineNames = new Dictionary<string, string>();
    private HashSet<string> kicked = new HashSet<string>();
    private Dictionary<string, long> keyTry = new Dictionary<string, long>();
    private Dictionary<string, List<long>> rate = new Dictionary<string, List<long>>();
    private HashSet<string> localIps = new HashSet<string>();
    private long localIpsAt;
    private long lastOnlineWrite;
    private readonly Random rnd = new Random();

    public string Start()
    {
        EarthMailStore.EnsureDirs();
        try
        {
            listener = new TcpListener(IPAddress.Parse(BindIp), Port);
            listener.Start();
        }
        catch (Exception ex) { return "Port " + Port + " konnte nicht geoeffnet werden: " + ex.Message; }
        running = true;
        if (ListenStatus)
        {
            try
            {
                statRx = new UdpClient(AddressFamily.InterNetwork);
                statRx.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
                statRx.Client.Bind(new IPEndPoint(IPAddress.Any, StatusPort));
                statRx.EnableBroadcast = true;
                Thread st = new Thread(StatusLoop); st.IsBackground = true; st.Start();
            }
            catch (Exception) { statRx = null; }
        }
        Thread ta = new Thread(AcceptLoop); ta.IsBackground = true; ta.Start();
        Thread tw = new Thread(WorkLoop); tw.IsBackground = true; tw.Start();
        return null;
    }

    public void Stop()
    {
        running = false;
        try { if (listener != null) listener.Stop(); } catch (Exception) { }
        try { if (statRx != null) statRx.Close(); } catch (Exception) { }
        try { if (File.Exists(EarthMailStore.OnlineFile)) File.Delete(EarthMailStore.OnlineFile); } catch (Exception) { }
    }

    public bool IsRunning { get { return running; } }

    // ---- Hilfen ---------------------------------------------------------------------------
    public string Hmac(string text)
    {
        using (HMACSHA256 h = new HMACSHA256(Encoding.UTF8.GetBytes(Secret ?? "")))
            return Convert.ToBase64String(h.ComputeHash(Encoding.UTF8.GetBytes(text)));
    }

    private string Signed(string core) { return core + "|" + Hmac(core); }

    private bool CheckSigned(string line, out string[] fields)
    {
        fields = null;
        int cut = line.LastIndexOf('|');
        if (cut <= 0) return false;
        string core = line.Substring(0, cut);
        string sig = line.Substring(cut + 1);
        byte[] a = Encoding.ASCII.GetBytes(Hmac(core));
        byte[] b = Encoding.ASCII.GetBytes(sig);
        if (a.Length != b.Length) return false;
        int d = 0;
        for (int i = 0; i < a.Length; i++) d |= a[i] ^ b[i];
        if (d != 0) return false;
        fields = core.Split('|');
        return true;
    }

    private static string B64(string s) { return Convert.ToBase64String(Encoding.UTF8.GetBytes(s ?? "")); }
    private static string UnB64(string s)
    {
        try { return Encoding.UTF8.GetString(Convert.FromBase64String(s ?? "")); } catch (Exception) { return ""; }
    }

    public bool IsLocalIp(string ip)
    {
        long now = EarthMailStore.Now();
        lock (lk)
        {
            if (now - localIpsAt > 15000)
            {
                HashSet<string> next = new HashSet<string>();
                next.Add("127.0.0.1");
                try
                {
                    foreach (NetworkInterface nic in NetworkInterface.GetAllNetworkInterfaces())
                        foreach (UnicastIPAddressInformation ua in nic.GetIPProperties().UnicastAddresses)
                            if (ua.Address.AddressFamily == AddressFamily.InterNetwork) next.Add(ua.Address.ToString());
                }
                catch (Exception) { }
                foreach (string x in extraLocal) next.Add(x);
                localIps = next;
                localIpsAt = now;
            }
            return localIps.Contains(ip);
        }
    }

    // Test-Hilfe: zusaetzliche "eigene" Adresse (z. B. 127.0.0.2 im Selbsttest).
    private HashSet<string> extraLocal = new HashSet<string>();
    public void AddLocalIp(string ip) { lock (lk) { extraLocal.Add(ip); localIps.Add(ip); } }

    private static bool IsBanned(string ip)
    {
        try
        {
            string path = @"C:\Project-Earth-Lan\ip_bans.json";
            if (!File.Exists(path)) return false;
            string txt = File.ReadAllText(path, Encoding.UTF8);
            int i = 0;
            string needle = "\"Ip\":\"" + ip + "\"";
            while ((i = txt.IndexOf(needle, i, StringComparison.Ordinal)) >= 0)
            {
                // Bis zum naechsten Eintrag lesen (nicht bis zur naechsten "}" - eine
                // Klammer im Grund-Text wuerde den Eintrag sonst zu frueh abschneiden).
                int next = txt.IndexOf("\"Ip\":\"", i + needle.Length, StringComparison.Ordinal);
                string obj = next > i ? txt.Substring(i, next - i) : txt.Substring(i);
                if (obj.IndexOf("\"Deleted\":true", StringComparison.Ordinal) < 0) return true;
                i += needle.Length;
            }
        }
        catch (Exception) { }
        return false;
    }

    private bool RateOk(string ip)
    {
        long now = EarthMailStore.Now();
        lock (lk)
        {
            List<long> l;
            if (!rate.TryGetValue(ip, out l)) { l = new List<long>(); rate[ip] = l; }
            l.RemoveAll(delegate (long t) { return now - t > 60000; });
            if (l.Count >= 40) return false;
            l.Add(now);
            return true;
        }
    }

    // ---- Wer ist gerade online (aus den Live-Status-Meldungen, Port 9928) -------------------
    public void NotePeer(string ip, string name)
    {
        if (!EarthMailStore.IsValidIp(ip) || IsLocalIp(ip)) return;
        long now = EarthMailStore.Now();
        bool cameOnline;
        lock (lk)
        {
            long last;
            cameOnline = !onlineSeen.TryGetValue(ip, out last) || (now - last) > 60000;
            onlineSeen[ip] = now;
            onlineNames[ip] = EarthMailStore.OneLine(name, 40);
            if (cameOnline) kicked.Add(ip);
        }
    }

    public string[] GetOnlinePeers()
    {
        long now = EarthMailStore.Now();
        List<string> l = new List<string>();
        lock (lk)
        {
            foreach (KeyValuePair<string, long> kv in onlineSeen)
                if (now - kv.Value < 45000) l.Add(kv.Key + "|" + (onlineNames.ContainsKey(kv.Key) ? onlineNames[kv.Key] : ""));
        }
        return l.ToArray();
    }

    public string NameOf(string ip)
    {
        lock (lk) { string n; return onlineNames.TryGetValue(ip, out n) ? n : ""; }
    }

    public void Kick(string ip) { lock (lk) { kicked.Add(ip); } }

    private void StatusLoop()
    {
        IPEndPoint ep = new IPEndPoint(IPAddress.Any, 0);
        while (running)
        {
            byte[] d;
            try { d = statRx.Receive(ref ep); }
            catch (Exception) { if (!running) break; Thread.Sleep(100); continue; }
            try
            {
                string txt = Encoding.UTF8.GetString(d);
                if (!txt.StartsWith("PESTAT1|")) continue;
                string[] f;
                if (!CheckSigned(txt, out f) || f.Length < 7) continue;
                NotePeer(ep.Address.ToString(), f[1]);
            }
            catch (Exception) { }
        }
    }

    private void WriteOnlineFile()
    {
        long now = EarthMailStore.Now();
        if (now - lastOnlineWrite < 4000) return;
        lastOnlineWrite = now;
        try
        {
            StringBuilder sb = new StringBuilder();
            foreach (string p in GetOnlinePeers()) sb.Append(p).Append('\n');
            string tmp = EarthMailStore.OnlineFile + ".tmp";
            File.WriteAllText(tmp, sb.ToString(), new UTF8Encoding(false));
            if (File.Exists(EarthMailStore.OnlineFile)) File.Replace(tmp, EarthMailStore.OnlineFile, null);
            else File.Move(tmp, EarthMailStore.OnlineFile);
        }
        catch (Exception) { }
    }

    // ---- Netzwerk: eine Anfrage = eine Verbindung = eine Zeile hin, eine Zeile zurueck ------
    private static string ReadLine(NetworkStream ns, int max)
    {
        MemoryStream ms = new MemoryStream();
        int b;
        while ((b = ns.ReadByte()) >= 0)
        {
            if (b == 10) break;
            if (b != 13) ms.WriteByte((byte)b);
            if (ms.Length > max) return null;
        }
        if (ms.Length == 0 && b < 0) return null;
        return Encoding.UTF8.GetString(ms.ToArray());
    }

    private static void WriteLine(NetworkStream ns, string t)
    {
        byte[] b = Encoding.UTF8.GetBytes(t + "\n");
        ns.Write(b, 0, b.Length);
        ns.Flush();
    }

    // Liefert die Antwortzeile oder null (nicht erreichbar / Zeitueberschreitung).
    public string Request(string ip, string line)
    {
        try
        {
            using (TcpClient c = new TcpClient(AddressFamily.InterNetwork))
            {
                IAsyncResult ar = c.BeginConnect(IPAddress.Parse(ip), Port, null, null);
                if (!ar.AsyncWaitHandle.WaitOne(ConnectTimeoutMs)) { try { c.Close(); } catch (Exception) { } return null; }
                c.EndConnect(ar);
                c.ReceiveTimeout = 8000;
                c.SendTimeout = 8000;
                NetworkStream ns = c.GetStream();
                WriteLine(ns, line);
                return ReadLine(ns, 70000);
            }
        }
        catch (Exception) { return null; }
    }

    private void AcceptLoop()
    {
        while (running)
        {
            try
            {
                TcpClient c = listener.AcceptTcpClient();
                Thread t = new Thread(delegate () { HandleConn(c); });
                t.IsBackground = true;
                t.Start();
            }
            catch (Exception) { if (!running) break; Thread.Sleep(50); }
        }
    }

    private void HandleConn(TcpClient c)
    {
        try
        {
            string ip = ((IPEndPoint)c.Client.RemoteEndPoint).Address.ToString();
            if (ip.StartsWith("::ffff:")) ip = ip.Substring(7);
            if (IsBanned(ip) || !RateOk(ip)) return;
            c.ReceiveTimeout = 8000;
            c.SendTimeout = 8000;
            NetworkStream ns = c.GetStream();
            string line = ReadLine(ns, 70000);
            if (line == null) return;
            string reply = Process(ip, line);
            if (reply != null) WriteLine(ns, reply);
        }
        catch (Exception) { }
        finally { try { c.Close(); } catch (Exception) { } }
    }

    // Verarbeitet eine eingehende Anfrage (auch direkt fuer Tests aufrufbar).
    public string Process(string remoteIp, string line)
    {
        string[] f;
        if (!line.StartsWith("PEMAIL1|") || !CheckSigned(line, out f) || f.Length < 3) return "ERR|format";
        string kind = f[1];
        long now = EarthMailStore.Now();
        if (kind == "KEY")
        {
            if (string.IsNullOrEmpty(PublicKeyXml)) return "ERR|nokey";
            return Signed("KEY|" + B64(PublicKeyXml));
        }
        if (kind == "MSG" && f.Length >= 8)
        {
            string id = f[2];
            string toIp = f[4];
            if (!EarthMailStore.IsValidId(id)) return "ERR|id";
            if (!IsLocalIp(toIp)) return "NOTME";
            if (EarthMailStore.HasSeen(id)) return "DUP";
            EarthMailMsg m = new EarthMailMsg();
            m.Id = id;
            m.FromName = EarthMailStore.OneLine(UnB64(f[3]), 40);
            m.FromIp = remoteIp;
            m.ToIp = toIp;
            long cr; long.TryParse(f[5], out cr);
            m.CreatedUtc = (cr > 0 && cr < now + 86400000L) ? cr : now;
            m.Subject = EarthMailStore.OneLine(UnB64(f[6]), EarthMailStore.MaxSubject);
            m.Body = EarthMailStore.Clean(UnB64(f[7]), EarthMailStore.MaxBody);
            m.ReceivedUtc = now;
            m.Via = "direkt";
            m.Verified = true;
            if (!EarthMailStore.Save(m, EarthMailStore.Inbox)) return "ERR|save";
            EarthMailStore.AddSeen(id);
            if (m.FromName.Length > 0) NotePeer(remoteIp, m.FromName);
            Events.Enqueue("NEW|" + id);
            return "OK";
        }
        if (kind == "RELAY" && f.Length >= 7)
        {
            string id = f[2];
            string toIp = f[3];
            if (!EarthMailStore.IsValidId(id) || !EarthMailStore.IsValidIp(toIp)) return "ERR|id";
            string blob = f[6];
            if (blob.Length > 30000) return "ERR|size";
            if (IsLocalIp(toIp)) return OpenSealed(remoteIp, id, toIp, blob, "");
            if (File.Exists(Path.Combine(EarthMailStore.Relay, id + ".msg"))) return "OK";
            if (EarthMailStore.CountFiles(EarthMailStore.Relay) >= 300) return "ERR|full";
            long exp; long.TryParse(f[5], out exp);
            long maxExp = now + 14L * 86400000L;
            EarthMailMsg r = new EarthMailMsg();
            r.Id = id;
            r.ToIp = toIp;
            r.FromIp = remoteIp;
            long cr; long.TryParse(f[4], out cr);
            r.CreatedUtc = cr > 0 ? cr : now;
            r.ReceivedUtc = now;
            r.ExpiresUtc = (exp > now && exp < maxExp) ? exp : maxExp;
            r.Blob = blob;
            r.NextTryUtc = now + 3000;
            if (!EarthMailStore.Save(r, EarthMailStore.Relay)) return "ERR|save";
            Events.Enqueue("RELAYHOLD|" + id);
            return "OK";
        }
        if (kind == "SEALED" && f.Length >= 5)
        {
            string id = f[2];
            string toIp = f[3];
            if (!EarthMailStore.IsValidId(id)) return "ERR|id";
            if (!IsLocalIp(toIp)) return "NOTME";
            return OpenSealed(remoteIp, id, toIp, f[4], f.Length >= 6 ? UnB64(f[5]) : "");
        }
        return "ERR|kind";
    }

    private string OpenSealed(string remoteIp, string id, string toIp, string blob, string holderName)
    {
        if (EarthMailStore.HasSeen(id)) return "DUP";
        if (string.IsNullOrEmpty(PrivateKeyXml)) return "ERR|nokey";
        string plain = EarthMailCrypto.Open(PrivateKeyXml, blob);
        if (plain == null) return "ERR|decrypt";
        EarthMailMsg inner = EarthMailStore.FromText(plain);
        if (inner == null || inner.Id != id || inner.ToIp != toIp) return "ERR|inner";
        if (!EarthMailStore.IsValidIp(inner.FromIp) || IsBanned(inner.FromIp)) { EarthMailStore.AddSeen(id); return "OK"; }
        long now = EarthMailStore.Now();
        EarthMailMsg m = new EarthMailMsg();
        m.Id = id;
        m.FromName = EarthMailStore.OneLine(inner.FromName, 40);
        m.FromIp = inner.FromIp;
        m.ToIp = toIp;
        m.CreatedUtc = (inner.CreatedUtc > 0 && inner.CreatedUtc < now + 86400000L) ? inner.CreatedUtc : now;
        m.Subject = EarthMailStore.OneLine(inner.Subject, EarthMailStore.MaxSubject);
        m.Body = EarthMailStore.Clean(inner.Body, EarthMailStore.MaxBody);
        m.ReceivedUtc = now;
        string holder = EarthMailStore.OneLine(holderName, 40);
        if (holder.Length == 0) holder = NameOf(remoteIp);
        m.Via = "weitergeleitet über " + (holder.Length > 0 ? holder + " (" + remoteIp + ")" : remoteIp);
        string senderKey = EarthMailStore.LoadPeerKey(inner.FromIp);
        m.Verified = senderKey != null && EarthMailCrypto.Verify(senderKey, SignText(inner), inner.Blob);
        if (!EarthMailStore.Save(m, EarthMailStore.Inbox)) return "ERR|save";
        EarthMailStore.AddSeen(id);
        Events.Enqueue("NEW|" + id);
        return "OK";
    }

    private static string SignText(EarthMailMsg m)
    {
        return m.Id + "|" + m.FromIp + "|" + m.ToIp + "|" + m.CreatedUtc + "|" + m.Subject + "|" + m.Body;
    }

    // ---- Zustellung (Hintergrund-Thread) -------------------------------------------------
    private static long Backoff(int attempts)
    {
        long[] steps = { 15000, 30000, 60000, 120000, 300000, 600000 };
        int i = Math.Max(0, Math.Min(attempts - 1, steps.Length - 1));
        return steps[i];
    }

    private void WorkLoop()
    {
        int tick = 0;
        while (running)
        {
            try { WorkOnce(tick); } catch (Exception) { }
            tick++;
            for (int i = 0; i < 10 && running; i++) Thread.Sleep(100);
        }
    }

    public void WorkOnce(int tick)
    {
        long now = EarthMailStore.Now();
        HashSet<string> kick;
        lock (lk) { kick = kicked; kicked = new HashSet<string>(); }

        foreach (EarthMailMsg m in EarthMailStore.List(EarthMailStore.Outbox))
        {
            if (!running) return;
            if (m.NextTryUtc > now && !kick.Contains(m.ToIp)) continue;
            DeliverOutgoing(m);
        }
        foreach (EarthMailMsg r in EarthMailStore.List(EarthMailStore.Relay))
        {
            if (!running) return;
            if (r.ExpiresUtc > 0 && r.ExpiresUtc < now) { TryDelete(r.FilePath); continue; }
            if (r.NextTryUtc > now && !kick.Contains(r.ToIp)) continue;
            DeliverRelay(r);
        }
        if (tick % 20 == 0) FetchMissingKeys();
        WriteOnlineFile();
    }

    private static void TryDelete(string path) { try { if (!string.IsNullOrEmpty(path) && File.Exists(path)) File.Delete(path); } catch (Exception) { } }

    public string BuildMsgLine(EarthMailMsg m)
    {
        return Signed("PEMAIL1|MSG|" + m.Id + "|" + B64(m.FromName) + "|" + m.ToIp + "|" + m.CreatedUtc + "|" + B64(m.Subject) + "|" + B64(m.Body));
    }

    private void DeliverOutgoing(EarthMailMsg m)
    {
        long now = EarthMailStore.Now();
        if (!EarthMailStore.IsValidIp(m.ToIp))
        {
            m.LastError = "Ungültige IP-Adresse - bitte Nachricht löschen und neu schreiben.";
            m.NextTryUtc = now + 3600000L;
            EarthMailStore.SaveIfExists(m, EarthMailStore.Outbox);
            return;
        }
        string reply = Request(m.ToIp, BuildMsgLine(m));
        if (reply == "OK" || reply == "DUP")
        {
            m.DeliveredUtc = EarthMailStore.Now();
            if (m.Via.Length == 0) m.Via = "direkt";
            m.LastError = "";
            string outPath = Path.Combine(EarthMailStore.Outbox, m.Id + ".msg");
            if (!File.Exists(outPath)) return;
            if (EarthMailStore.Save(m, EarthMailStore.Sent)) TryDelete(outPath);
            Events.Enqueue("SENT|" + m.Id);
            return;
        }
        m.Attempts++;
        if (reply == "NOTME")
        {
            m.LastError = "Unter " + m.ToIp + " antwortet ein anderer PC - neuer Versuch in 10 Minuten.";
            m.NextTryUtc = now + 600000L;
        }
        else if (reply != null && reply.StartsWith("ERR"))
        {
            m.LastError = "Vom Empfänger abgelehnt (" + reply + ") - neuer Versuch später.";
            m.NextTryUtc = now + 600000L;
        }
        else
        {
            m.LastError = "Empfänger offline - wird automatisch zugestellt, sobald er online ist.";
            m.NextTryUtc = now + Backoff(m.Attempts);
            if (!m.Relayed) TryRelay(m);
        }
        EarthMailStore.SaveIfExists(m, EarthMailStore.Outbox);
    }

    // Verschluesselte Kopie an bis zu 3 gerade laufende Manager uebergeben. Die koennen die
    // Nachricht nicht lesen, liefern sie aber aus, sobald der Empfaenger auftaucht - auch
    // wenn der Absender dann selbst schon offline ist.
    private void TryRelay(EarthMailMsg m)
    {
        if (string.IsNullOrEmpty(PrivateKeyXml)) return;
        string recipientKey = EarthMailStore.LoadPeerKey(m.ToIp);
        if (recipientKey == null) return;
        List<string> holders = new List<string>();
        foreach (string p in GetOnlinePeers())
        {
            string ip = p.Split('|')[0];
            if (ip != m.ToIp && !IsLocalIp(ip)) holders.Add(ip);
        }
        if (holders.Count == 0) return;
        for (int i = holders.Count - 1; i > 0; i--) { int j = rnd.Next(i + 1); string t = holders[i]; holders[i] = holders[j]; holders[j] = t; }
        EarthMailMsg inner = new EarthMailMsg();
        inner.Id = m.Id; inner.FromName = m.FromName; inner.FromIp = m.FromIp; inner.ToIp = m.ToIp;
        inner.CreatedUtc = m.CreatedUtc; inner.Subject = m.Subject; inner.Body = m.Body;
        string blob;
        try
        {
            inner.Blob = EarthMailCrypto.Sign(PrivateKeyXml, SignText(inner));
            blob = EarthMailCrypto.Seal(recipientKey, EarthMailStore.ToText(inner));
        }
        catch (Exception) { return; }
        long exp = EarthMailStore.Now() + 14L * 86400000L;
        string line = Signed("PEMAIL1|RELAY|" + m.Id + "|" + m.ToIp + "|" + m.CreatedUtc + "|" + exp + "|" + blob);
        List<string> ok = new List<string>();
        foreach (string h in holders)
        {
            if (ok.Count >= MaxRelayHolders) break;
            if (Request(h, line) == "OK") { string n = NameOf(h); ok.Add(n.Length > 0 ? n : h); }
        }
        if (ok.Count > 0)
        {
            m.Relayed = true;
            m.RelayedTo = string.Join(", ", ok.ToArray());
            Events.Enqueue("RELAYED|" + m.Id + "|" + m.RelayedTo);
        }
    }

    private void DeliverRelay(EarthMailMsg r)
    {
        long now = EarthMailStore.Now();
        string reply = Request(r.ToIp, Signed("PEMAIL1|SEALED|" + r.Id + "|" + r.ToIp + "|" + r.Blob + "|" + B64(MyName)));
        if (reply == "OK" || reply == "DUP" || reply == "NOTME" || (reply != null && reply.StartsWith("ERR|decrypt")) || (reply != null && reply.StartsWith("ERR|inner")))
        {
            TryDelete(r.FilePath);
            if (reply == "OK") Events.Enqueue("RELAYDONE|" + r.Id);
            return;
        }
        r.Attempts++;
        r.NextTryUtc = now + Math.Max(30000, Backoff(r.Attempts));
        EarthMailStore.SaveIfExists(r, EarthMailStore.Relay);
    }

    public bool FetchKey(string ip)
    {
        string reply = Request(ip, Signed("PEMAIL1|KEY|" + Guid.NewGuid().ToString("N").Substring(0, 8)));
        if (reply == null) return false;
        string[] f;
        if (!reply.StartsWith("KEY|") || !CheckSigned(reply, out f) || f.Length < 2) return false;
        string xml = UnB64(f[1]);
        if (xml.IndexOf("<Modulus>", StringComparison.Ordinal) < 0 || xml.IndexOf("<D>", StringComparison.Ordinal) >= 0) return false;
        EarthMailStore.SavePeerKey(ip, xml);
        return true;
    }

    private void FetchMissingKeys()
    {
        long now = EarthMailStore.Now();
        foreach (string p in GetOnlinePeers())
        {
            string ip = p.Split('|')[0];
            if (EarthMailStore.PeerKeyAgeMs(ip) < 86400000L) continue;
            lock (lk)
            {
                long last;
                if (keyTry.TryGetValue(ip, out last) && now - last < 300000) continue;
                keyTry[ip] = now;
            }
            FetchKey(ip);
        }
    }
}
'@

function Initialize-PelMailTypes {
    if (-not ('EarthMailNode' -as [type])) {
        Add-Type -TypeDefinition $script:PelMailCode -Language CSharp
    }
    [EarthMailStore]::EnsureDirs()
}

# Eigenes Schlüsselpaar für das Postfach (einmalig erzeugt). Der private Teil wird mit
# Windows-DPAPI an das eigene Benutzerkonto gebunden gespeichert.
function Get-PelMailKeyPair {
    $priv = $null
    try {
        if ([System.IO.File]::Exists($script:PelMailKeyPath)) {
            $raw = ([System.IO.File]::ReadAllText($script:PelMailKeyPath)).Trim()
            if ($raw.StartsWith('DPAPI:')) {
                Add-Type -AssemblyName System.Security
                $bytes = [System.Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($raw.Substring(6)), $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
                $priv = [System.Text.Encoding]::UTF8.GetString($bytes)
            } elseif ($raw.StartsWith('PLAIN:')) {
                $priv = $raw.Substring(6)
            }
        }
    } catch { $priv = $null }
    if (-not $priv -or $priv -notmatch '<D>') {
        $pubOut = ''
        $priv = [EarthMailCrypto]::MakeKeyPair([ref]$pubOut)
        $txt = $null
        try {
            Add-Type -AssemblyName System.Security
            $prot = [System.Security.Cryptography.ProtectedData]::Protect([System.Text.Encoding]::UTF8.GetBytes($priv), $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
            $txt = 'DPAPI:' + [Convert]::ToBase64String($prot)
        } catch { $txt = 'PLAIN:' + $priv }
        try { Write-PelTextFileAtomic $script:PelMailKeyPath $txt } catch { }
    }
    return @{ Private = $priv; Public = [EarthMailCrypto]::PublicFromPrivate($priv) }
}

# Startet den Postfach-Dienst in diesem Fenster, falls er auf dem PC noch nirgends läuft.
# Rückgabe: $true = läuft (jetzt) hier, $false = läuft woanders oder konnte nicht starten.
function Start-PelMailService {
    param([switch]$NoStatusListener)
    if ($script:PelMailNode) { return $true }
    try { Initialize-PelMailTypes } catch { Write-PelLog -Level 'FEHLER' -Message "Postfach: C#-Teil konnte nicht geladen werden: $($_.Exception.Message)"; return $false }
    try {
        if (-not $script:PelMailMutex) { $script:PelMailMutex = New-Object System.Threading.Mutex($false, 'Global\ProjectEarthLan_Postfach') }
    } catch { return $false }
    $got = $false
    try { $got = $script:PelMailMutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $got = $true } catch { $got = $false }
    if (-not $got) { return $false }
    try {
        $kp = Get-PelMailKeyPair
        $n = New-Object EarthMailNode
        $n.Port = $script:PelMailPort
        $n.StatusPort = $script:PelStatusPort
        $n.Secret = $script:PelNetworkSecret
        $n.PrivateKeyXml = $kp.Private
        $n.PublicKeyXml = $kp.Public
        $n.MyName = Get-PelDisplayName
        $n.ListenStatus = (-not $NoStatusListener)
        $err = $n.Start()
        if ($err) { throw $err }
        $script:PelMailNode = $n
        try {
            if (-not (Get-NetFirewallRule -DisplayName "Project Earth LAN Postfach $($script:PelMailPort) (TCP)" -ErrorAction SilentlyContinue)) {
                New-NetFirewallRule -DisplayName "Project Earth LAN Postfach $($script:PelMailPort) (TCP)" -Direction Inbound -Action Allow -Protocol TCP -LocalPort $script:PelMailPort -RemoteAddress LocalSubnet -Profile Any -ErrorAction Stop | Out-Null
            }
        } catch { }
        Write-PelLog "Postfach-Dienst gestartet (Port $($script:PelMailPort))."
        return $true
    } catch {
        Write-PelLog -Level 'FEHLER' -Message "Postfach-Dienst konnte nicht starten: $($_.Exception.Message)"
        try { $script:PelMailMutex.ReleaseMutex() } catch { }
        return $false
    }
}

function Stop-PelMailService {
    if ($script:PelMailNode) {
        try { $script:PelMailNode.Stop() } catch { }
        $script:PelMailNode = $null
        try { $script:PelMailMutex.ReleaseMutex() } catch { }
    }
}

# Eigene Quell-IP, über die Windows den Empfänger erreichen würde (bei ZeroTier also die
# eigene ZeroTier-IP) - es wird dabei nichts gesendet, nur die Route nachgeschlagen.
function Get-PelSourceIpFor([string]$Ip) {
    $u = $null
    try {
        $u = New-Object System.Net.Sockets.UdpClient
        $u.Connect($Ip, $script:PelMailPort)
        return $u.Client.LocalEndPoint.Address.ToString()
    } catch { return '' } finally { if ($u) { try { $u.Close() } catch { } } }
}

# Legt eine Nachricht in den Ausgang; der Postfach-Dienst stellt sie innerhalb weniger
# Sekunden zu (oder später, sobald der Empfänger online ist). Rückgabe: Id oder $null.
function New-PelMailOutgoing {
    param([string]$ToIp, [string]$ToName, [string]$Subject, [string]$Body)
    Initialize-PelMailTypes
    $ToIp = ([string]$ToIp).Trim()
    if (-not [EarthMailStore]::IsValidIp($ToIp)) { return $null }
    $m = New-Object EarthMailMsg
    $m.Id = [EarthMailStore]::NewId()
    $m.FromName = Get-PelDisplayName
    $m.FromIp = Get-PelSourceIpFor $ToIp
    $m.ToName = [EarthMailStore]::OneLine($ToName, 40)
    $m.ToIp = $ToIp
    $m.Subject = [EarthMailStore]::OneLine($Subject, [EarthMailStore]::MaxSubject)
    $m.Body = [EarthMailStore]::Clean($Body, [EarthMailStore]::MaxBody)
    $m.CreatedUtc = [EarthMailStore]::Now()
    $m.NextTryUtc = 0
    if (-not [EarthMailStore]::Save($m, [EarthMailStore]::Outbox)) { return $null }
    if ($script:PelMailNode) { $script:PelMailNode.Kick($ToIp) }
    return $m.Id
}

# Wer ist gerade online (andere Manager im Netz): "ip|name" je Eintrag. Läuft der Dienst
# in einem anderen Fenster, wird dessen Liste aus online.txt gelesen.
function Get-PelMailOnlinePeers {
    if ($script:PelMailNode) { return @($script:PelMailNode.GetOnlinePeers()) }
    try {
        Initialize-PelMailTypes
        $f = [EarthMailStore]::OnlineFile
        if ([System.IO.File]::Exists($f) -and (([DateTime]::UtcNow - [System.IO.File]::GetLastWriteTimeUtc($f)).TotalSeconds -lt 30)) {
            return @((Read-PelTextFile $f) -split "`n" | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}\|' })
        }
    } catch { }
    return @()
}

function Format-PelMailTime([long]$Ms) {
    if ($Ms -le 0) { return '-' }
    try { return [DateTimeOffset]::FromUnixTimeMilliseconds($Ms).LocalDateTime.ToString('dd.MM.yyyy HH:mm') } catch { return '-' }
}

# Hinweisfenster "Neue Nachricht" (unten rechts, nicht "immer im Vordergrund" - wie die
# Spieleabend-Ankündigung). Weitere Nachrichten werden im offenen Fenster ergänzt.
function Show-PelMailNotification {
    param($Messages, $ParentForm = $null)
    $list = @($Messages | Where-Object { $_ })
    if ($list.Count -eq 0) { return }
    $lines = @()
    foreach ($m in $list) {
        $from = [string]$m.FromName
        if (-not $from) { $from = [string]$m.FromIp }
        $subj = [string]$m.Subject
        if (-not $subj) { $subj = '(kein Betreff)' }
        $lines += "Von $from ($($m.FromIp)) - $(Format-PelMailTime $m.ReceivedUtc)`r`nBetreff: $subj"
    }
    $text = $lines -join "`r`n`r`n"
    try { [System.Media.SystemSounds]::Asterisk.Play() } catch { }
    if ($script:PelMailNoteForm -and -not $script:PelMailNoteForm.IsDisposed -and $script:PelMailNoteForm.Visible) {
        $script:PelMailNoteBox.AppendText("`r`n`r`n" + $text)
        try { $script:PelMailNoteForm.Activate() } catch { }
        return
    }
    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'Project Earth LAN - Neue Nachricht'
    $f.Size = New-Object System.Drawing.Size(460, 300)
    $f.StartPosition = 'Manual'
    try {
        $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $f.Location = New-Object System.Drawing.Point(($wa.Right - $f.Width - 12), ($wa.Bottom - $f.Height - 12))
    } catch { $f.StartPosition = 'CenterScreen' }
    $f.FormBorderStyle = 'FixedDialog'
    $f.MaximizeBox = $false
    $f.MinimizeBox = $false
    $f.ShowInTaskbar = $true
    $f.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $f.ForeColor = [System.Drawing.Color]::White

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Multiline = $true
    $tb.ReadOnly = $true
    $tb.ScrollBars = 'Vertical'
    $tb.Location = New-Object System.Drawing.Point(12, 12)
    $tb.Size = New-Object System.Drawing.Size(420, 190)
    $tb.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
    $tb.ForeColor = [System.Drawing.Color]::White
    $tb.BorderStyle = 'FixedSingle'
    $tb.Font = New-Object System.Drawing.Font('Segoe UI', 10.5, [System.Drawing.FontStyle]::Regular)
    $tb.Text = $text
    $f.Controls.Add($tb)

    $btnOpen = New-Object System.Windows.Forms.Button
    $btnOpen.Text = 'Postfach öffnen'
    $btnOpen.Location = New-Object System.Drawing.Point(172, 214)
    $btnOpen.Size = New-Object System.Drawing.Size(130, 32)
    $btnOpen.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnOpen.ForeColor = [System.Drawing.Color]::White
    $btnOpen.FlatStyle = 'Flat'
    $btnOpen.Add_Click({
        $af = $this.FindForm()
        $script:PelMailNoteForm = $null
        $af.Close()
        Start-OptionWindow '11' { Invoke-FriendsBansMailbox }
    })
    $f.Controls.Add($btnOpen)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = 'Später'
    $btnOk.Location = New-Object System.Drawing.Point(312, 214)
    $btnOk.Size = New-Object System.Drawing.Size(120, 32)
    $btnOk.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
    $btnOk.ForeColor = [System.Drawing.Color]::White
    $btnOk.FlatStyle = 'Flat'
    $btnOk.Add_Click({ $this.FindForm().Close() })
    $f.Controls.Add($btnOk)
    $f.AcceptButton = $btnOpen

    $script:PelMailNoteForm = $f
    $script:PelMailNoteBox = $tb
    $f.Show()
    try { $f.Activate(); $tb.Select(0, 0) } catch { }
}

# ------------------------------------------------------------------------------
# AUTOSTART (Control Center -> Button 12)
# ------------------------------------------------------------------------------
# Umsetzung als geplante Aufgabe "bei Anmeldung" mit höchsten Rechten: der Manager
# braucht Adminrechte, und ein normaler Autostart-Eintrag (Registry "Run") würde bei
# jeder Anmeldung eine UAC-Abfrage auslösen bzw. von Windows übersprungen. Start ca.
# 30 Sekunden nach der Anmeldung (Netzwerk/ZeroTier sind dann da), minimiert, mit
# normaler Priorität (geplante Aufgaben laufen sonst gedrosselt - schlecht für Voice).
$script:PelAutostartTaskName = 'Project Earth LAN Manager (Autostart)'

function Get-PelAutostartInfo {
    $r = [pscustomobject]@{ Enabled = $false; PathOk = $false; Target = '' }
    $found = $false
    try {
        $t = Get-ScheduledTask -TaskName $script:PelAutostartTaskName -ErrorAction Stop
        $found = $true
        $r.Enabled = ([string]$t.State -ne 'Disabled')
        $a = @($t.Actions)[0]
        if ($a) { $r.Target = ("$($a.Execute) $($a.Arguments)").Trim() }
    } catch { }
    if (-not $found) {
        try {
            & schtasks.exe /Query /TN $script:PelAutostartTaskName 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { $found = $true; $r.Enabled = $true; $r.PathOk = $true }
        } catch { }
        return $r
    }
    if ($script:SelfPath -and $r.Target) { $r.PathOk = ($r.Target.IndexOf($script:SelfPath, [StringComparison]::OrdinalIgnoreCase) -ge 0) }
    return $r
}

function Test-PelAutostart {
    try { return [bool](Get-PelAutostartInfo).Enabled } catch { return $false }
}

# Rückgabe: $null = OK, sonst Fehlertext.
function Enable-PelAutostart {
    if (-not $script:SelfPath) { return 'Der Speicherort des Managers ist unbekannt.' }
    $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $workDir = Split-Path -Parent $script:SelfPath
    if ($script:IsCompiledExe) { $exe = $script:SelfPath; $arg = '-Autostart' }
    else { $exe = 'powershell.exe'; $arg = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$($script:SelfPath)`" -Autostart" }
    try {
        $action = New-ScheduledTaskAction -Execute $exe -Argument $arg -WorkingDirectory $workDir
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
        $trigger.Delay = 'PT30S'
        $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -Priority 4
        Register-ScheduledTask -TaskName $script:PelAutostartTaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Startet den Project Earth LAN Manager (Control Center) minimiert bei der Anmeldung - Postfach, Live-Status und Spieleabend-Ankündigungen sind dann immer aktiv. Entfernen: im Manager Button 12.' -Force -ErrorAction Stop | Out-Null
        Write-PelLog "Autostart eingerichtet: $exe $arg"
        return $null
    } catch {
        $firstErr = $_.Exception.Message
        # Ersatzweg ohne ScheduledTasks-Modul
        try {
            if ($script:IsCompiledExe) { $tr = "`"$exe`" -Autostart" } else { $tr = "powershell.exe $arg" }
            & schtasks.exe /Create /TN $script:PelAutostartTaskName /TR $tr /SC ONLOGON /RL HIGHEST /DELAY 0000:30 /F 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-PelLog "Autostart (schtasks) eingerichtet: $tr"; return $null }
        } catch { }
        return $firstErr
    }
}

function Disable-PelAutostart {
    $err = $null
    try { Unregister-ScheduledTask -TaskName $script:PelAutostartTaskName -Confirm:$false -ErrorAction Stop }
    catch {
        try {
            & schtasks.exe /Delete /TN $script:PelAutostartTaskName /F 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { $err = $_.Exception.Message }
        } catch { $err = $_.Exception.Message }
    }
    # Eventuelle alte Autostart-Einträge anderer Versionen (Registry "Run") gleich mit entfernen.
    foreach ($runKey in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run')) {
        try {
            $props = Get-ItemProperty -Path $runKey -ErrorAction Stop
            foreach ($p in $props.PSObject.Properties) {
                if ($p.Name -like 'Project Earth*' -or $p.Name -like 'ProjectEarth*') { Remove-ItemProperty -Path $runKey -Name $p.Name -ErrorAction SilentlyContinue }
            }
        } catch { }
    }
    if (-not $err) { Write-PelLog 'Autostart entfernt.' }
    return $err
}

function Get-HTTPDirectoryContent ([string]$targetUrl, [scriptblock]$logCallback) {
    $foundFiles = [System.Collections.Generic.List[string]]::new()
    $visitedUrls = [System.Collections.Generic.HashSet[string]]::new()

    $rootUriString = if ($targetUrl.EndsWith('/')) { $targetUrl } else { "$targetUrl/" }
    
    function Crawl ([string]$currentUrl) {
        if (-not $currentUrl.EndsWith('/')) { $currentUrl += '/' }
        if ($visitedUrls.Contains($currentUrl)) { return }
        $visitedUrls.Add($currentUrl) | Out-Null

        if ($logCallback) { &$logCallback "Scanne Verzeichnis: $currentUrl" }

        try {
            $response = Invoke-WebRequest -Uri $currentUrl -UseBasicParsing -MaximumRedirection 5 -ErrorAction Stop
            $baseUri = [System.Uri]::new($currentUrl)

            foreach ($link in $response.Links) {
                $rawHref = $link.href
                if ([string]::IsNullOrWhiteSpace($rawHref)) { continue }

                $decodedHref = [System.Net.WebUtility]::HtmlDecode($rawHref)

                if ($decodedHref.Contains('?') -or 
                    $decodedHref.StartsWith('#') -or 
                    $decodedHref -eq '/' -or 
                    $decodedHref -eq '../' -or 
                    $decodedHref -eq './') {
                    continue
                }

                $resolvedUri = [System.Uri]::new($baseUri, $decodedHref)

                if (-not $resolvedUri.AbsoluteUri.StartsWith($rootUriString, [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }

                if ($resolvedUri.AbsoluteUri.EndsWith('/')) {
                    Crawl -currentUrl $resolvedUri.AbsoluteUri
                } else {
                    $relPath = $resolvedUri.AbsoluteUri.Substring($rootUriString.Length)
                    $decodedRelPath = [System.Net.WebUtility]::UrlDecode($relPath)
                    
                    if (-not $foundFiles.Contains($decodedRelPath)) {
                        $foundFiles.Add($decodedRelPath)
                    }
                }
            }
        } catch {
            if ($logCallback) { &$logCallback "FEHLER bei $currentUrl : $($_.Exception.Message)" }
        }
    }

    Crawl -currentUrl $rootUriString
    return $foundFiles
}

# ------------------------------------------------------------------------------
# OPTION 1: Installation von Project Earth LAN
# ------------------------------------------------------------------------------
function Invoke-InstallProjectEarthLan {
    Show-ProgressDialog -Title "Installation: Project Earth LAN" -TaskScript {
        param($report)

        &$report "Starte Download von ZeroTier One..." 10
        $NetworkID1 = "091f0945fc744570" # Account und Netzwerk Verwaltungs Server
        $NetworkID2 = "091f0945fc5012f1" # Project Earth Lan
        $InstallerUrl = "https://download.zerotier.com/dist/ZeroTier%20One.msi"
        $InstallerPath = "$env:TEMP\ZeroTierOneInstaller.msi"
        $DesktopPath = [System.IO.Path]::Combine($env:USERPROFILE, "Desktop")
        $TxtFile = Join-Path $DesktopPath "Project Earth Lan IP.txt"
        $TargetMTU = 1380

        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath

        &$report "Installiere ZeroTier One Service..." 35
        $installProcess = Start-Process msiexec.exe -ArgumentList "/i `"$InstallerPath`" /qn /norestart" -Wait -PassThru

        if ($installProcess.ExitCode -ne 0) {
            &$report "Fehler bei der MSI-Installation." 100
            return
        }

        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

        &$report "Warte auf ZeroTier-Dienst..." 55
        $timeout = 0
        while ((Get-Service -Name "ZeroTierOneService" -ErrorAction SilentlyContinue).Status -ne "Running" -and $timeout -lt 15) {
            Start-Sleep -Seconds 1
            $timeout++
        }
        Start-Sleep -Seconds 2

        $cliExe = Get-ZeroTierCli

        &$report "Trete Netzwerken bei (Account und Netzwerk Verwaltungs Server & Project Earth Lan)..." 70
        & $cliExe join $NetworkID1 | Out-Null
        Start-Sleep -Seconds 1
        & $cliExe join $NetworkID2 | Out-Null

        &$report "Frage zugewiesene IP-Adressen ab..." 85
        $ip1 = Get-ZeroTierNetworkIP -NetID $NetworkID1
        $ip2 = Get-ZeroTierNetworkIP -NetID $NetworkID2

        &$report "Setze Netzwerk-Optimierungen (Metrik & MTU)..." 92
        if ($ip1) {
            $adapter1 = Get-NetIPAddress -IPAddress $ip1 -ErrorAction SilentlyContinue | Get-NetAdapter
            if ($adapter1) {
                Set-NetIPInterface -InterfaceIndex $adapter1.InterfaceIndex -AddressFamily IPv4 -InterfaceMetric 2 -ErrorAction SilentlyContinue
                Set-NetIPInterface -InterfaceIndex $adapter1.InterfaceIndex -AddressFamily IPv4 -NlMtuBytes $TargetMTU -ErrorAction SilentlyContinue
            }
        }

        if ($ip2) {
            $adapter2 = Get-NetIPAddress -IPAddress $ip2 -ErrorAction SilentlyContinue | Get-NetAdapter
            if ($adapter2) {
                Set-NetIPInterface -InterfaceIndex $adapter2.InterfaceIndex -AddressFamily IPv4 -InterfaceMetric 1 -ErrorAction SilentlyContinue
                Set-NetIPInterface -InterfaceIndex $adapter2.InterfaceIndex -AddressFamily IPv4 -NlMtuBytes $TargetMTU -ErrorAction SilentlyContinue
            }
        }

        $fileContent = @"
Account und Netzwerk Verwaltungs Server: $ip1
Project Earth LAN IP: $ip2

==================================================
EIGENES NETZWERK ERSTELLEN (NUR BEI BEDARF!)
==================================================
HINWEIS: Du bist bereits erfolgreich mit dem Project Earth LAN verbunden! 
Die folgenden Schritte benötigst du NUR, wenn du dein eigenes, privates ZeroTier-Netzwerk erstellen und verwalten möchtest:

1. Öffne http://10.147.0.34:3000 im Browser.
2. Klicke dort auf "Los Geht's".
3. Vergib Name, E-Mail und Passwort. Danach kannst du ein eigenes Netzwerk erstellen.
4. Hinweis: Du kannst deinen Account zusätzlich mit einer 2-Faktoren-Authentifizierung (2FA) sichern.

==================================================
FLOW RULES
(Unter 'Flow Rules' eintragen für absolute Sicherheit, keinen unnötigen Broadcast-Lärm & maximale Performance für Gaming)
==================================================

--------------------------------------------------
# 1. Windows-Freigaben, NetBIOS & RPC
drop
    dport 135
    or dport 137:139
    or dport 445
;

# 2. Fernwartung & Remote Desktop
drop
    dport 3389
    or dport 5900
;

# 3. Discovery & Broadcast-Lärm
drop
    dport 111
    or dport 548
    or dport 631
    or dport 1900
    or dport 3702
    or dport 5353
    or dport 5355
    or dport 6320
    or dport 17500
;

# 4. Alles andere explizit erlauben
accept;
--------------------------------------------------
"@

        Set-Content -Path $TxtFile -Value $fileContent -Encoding UTF8 -Force
        Remove-Item -Path $InstallerPath -Force -ErrorAction SilentlyContinue

        &$report "Project Earth LAN erfolgreich eingerichtet!" 100
    }
}

# ------------------------------------------------------------------------------
# OPTION 2: Netzwerk Login
# ------------------------------------------------------------------------------
function Invoke-NetworkLogin {
    $loginForm = New-Object System.Windows.Forms.Form
    $loginForm.Text = "Netzwerk Login"
    $loginForm.Size = New-Object System.Drawing.Size(380, 170)
    $loginForm.StartPosition = "CenterParent"
    $loginForm.FormBorderStyle = "FixedDialog"
    $loginForm.MaximizeBox = $false
    $loginForm.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $loginForm.ForeColor = [System.Drawing.Color]::White

    $lblID = New-Object System.Windows.Forms.Label
    $lblID.Text = "ZeroTier Netzwerk-ID eingeben (16-stellig):"
    $lblID.Location = New-Object System.Drawing.Point(20, 20)
    $lblID.Size = New-Object System.Drawing.Size(320, 20)
    $loginForm.Controls.Add($lblID)

    $txtID = New-Object System.Windows.Forms.TextBox
    $txtID.Location = New-Object System.Drawing.Point(20, 45)
    $txtID.Size = New-Object System.Drawing.Size(320, 25)
    $txtID.BackColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
    $txtID.ForeColor = [System.Drawing.Color]::White
    $loginForm.Controls.Add($txtID)

    $btnSubmit = New-Object System.Windows.Forms.Button
    $btnSubmit.Text = "Verbinden"
    $btnSubmit.Location = New-Object System.Drawing.Point(220, 85)
    $btnSubmit.Size = New-Object System.Drawing.Size(120, 30)
    $btnSubmit.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $btnSubmit.FlatStyle = "Flat"
    $btnSubmit.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $loginForm.Controls.Add($btnSubmit)

    if ($loginForm.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $netId = $txtID.Text.Trim()
        if ($netId.Length -ne 16) {
            [System.Windows.Forms.MessageBox]::Show("Ungültige Netzwerk-ID! Die ID muss exakt 16 Zeichen lang sein.", "Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        }

        $cli = Get-ZeroTierCli
        Write-Host "Trete Netzwerk $netId bei..."
        $res = & $cli join $netId 2>&1

        if ($LASTEXITCODE -eq 0 -or $res -like "*200 join OK*") {
            $ip = Get-ZeroTierNetworkIP -NetID $netId
            if ($ip) {
                $adapter = Get-NetIPAddress -IPAddress $ip -ErrorAction SilentlyContinue | Get-NetAdapter
                if ($adapter) {
                    Set-NetIPInterface -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -InterfaceMetric 1 -ErrorAction SilentlyContinue
                    Set-NetIPInterface -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -NlMtuBytes 1380 -ErrorAction SilentlyContinue
                }
            }
            [System.Windows.Forms.MessageBox]::Show("Erfolgreich dem Netzwerk $netId beigetreten!`n`n(Metrik: 1 | MTU: 1380 wurden automatisch optimiert)", "Erfolg", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } else {
            [System.Windows.Forms.MessageBox]::Show("Fehler beim Beitritt:`n$res", "Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    }
}

# ------------------------------------------------------------------------------
# OPTION 3: Netzwerk Logout
# ------------------------------------------------------------------------------
function Invoke-NetworkLogout {
    $cli = Get-ZeroTierCli
    $netListRaw = & $cli listnetworks 2>&1

    if ($LASTEXITCODE -ne 0 -or -not $netListRaw) {
        [System.Windows.Forms.MessageBox]::Show("Konnte ZeroTier-Netzwerke nicht abfragen oder ZeroTier ist nicht aktiv.", "Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }

    $activeNetworks = @()
    foreach ($line in $netListRaw) {
        if ($line -match "^200\s+listnetworks\s+([a-f0-9]{16})\s+(.*)$") {
            $activeNetworks += $matches[1]
        }
    }

    if ($activeNetworks.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Du bist aktuell mit keinem ZeroTier-Netzwerk verbunden.", "Information", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }

    $logoutForm = New-Object System.Windows.Forms.Form
    $logoutForm.Text = "Netzwerk Logout"
    $logoutForm.Size = New-Object System.Drawing.Size(380, 170)
    $logoutForm.StartPosition = "CenterParent"
    $logoutForm.FormBorderStyle = "FixedDialog"
    $logoutForm.MaximizeBox = $false
    $logoutForm.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $logoutForm.ForeColor = [System.Drawing.Color]::White

    $lblNet = New-Object System.Windows.Forms.Label
    $lblNet.Text = "Wähle das Netzwerk zum Ausloggen aus:"
    $lblNet.Location = New-Object System.Drawing.Point(20, 20)
    $lblNet.Size = New-Object System.Drawing.Size(320, 20)
    $logoutForm.Controls.Add($lblNet)

    $cmbNet = New-Object System.Windows.Forms.ComboBox
    $cmbNet.Location = New-Object System.Drawing.Point(20, 45)
    $cmbNet.Size = New-Object System.Drawing.Size(320, 25)
    $cmbNet.DropDownStyle = "DropDownList"
    $cmbNet.BackColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
    $cmbNet.ForeColor = [System.Drawing.Color]::White
    foreach ($net in $activeNetworks) {
        $cmbNet.Items.Add($net) | Out-Null
    }
    $cmbNet.SelectedIndex = 0
    $logoutForm.Controls.Add($cmbNet)

    $btnLeave = New-Object System.Windows.Forms.Button
    $btnLeave.Text = "Ausloggen"
    $btnLeave.Location = New-Object System.Drawing.Point(200, 85)
    $btnLeave.Size = New-Object System.Drawing.Size(140, 30)
    $btnLeave.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $btnLeave.FlatStyle = "Flat"
    $btnLeave.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $logoutForm.Controls.Add($btnLeave)

    if ($logoutForm.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $selectedNet = $cmbNet.SelectedItem.ToString()
        Write-Host "Verlasse Netzwerk $selectedNet..."
        & $cli leave $selectedNet | Out-Null
        [System.Windows.Forms.MessageBox]::Show("Verbindung zum Netzwerk $selectedNet wurde erfolgreich getrennt.", "Erfolg", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
}

# ------------------------------------------------------------------------------
# OPTION: Was genau macht der Manager inklusive Impressum
# ------------------------------------------------------------------------------
function Invoke-GenerateExplanationFile {
    $DesktopPath = [System.IO.Path]::Combine($env:USERPROFILE, "Desktop")
    $TxtFile = Join-Path $DesktopPath "Was genau passiert wenn ich Project Earth LAN Manager benutze.txt"
    $created = Get-Date -Format 'dd.MM.yyyy HH:mm'

    $explanationText = @"
================================================================================
PROJECT EARTH LAN MANAGER - LIES MICH
Was der Manager macht, was er auf deinem PC anlegt und wie er dich schützt
Version: $($script:PelVersion)          Erstellt am: $created
================================================================================

INHALT
  1. Was ist Project Earth LAN?
  2. ZeroTier One - Herkunft, Zweck und was es auf deinem PC anlegt
  3. Alle Funktionen des Managers
  4. Ordner und Dateien, die der Manager anlegt
  5. Netzwerk-Ports, Firewall-Regeln und System-Einstellungen
  6. Sicherheit & Datenschutz
  7. ZeroTier Flow Rules - die Firewall des Netzwerks
  8. Alles wieder entfernen
  9. Impressum


================================================================================
1. WAS IST PROJECT EARTH LAN?
================================================================================
Project Earth LAN ist ein virtuelles Layer-2-Netzwerk auf Basis von ZeroTier One
für PC-Spieler. Damit laufen LAN- und Koop-Spiele über das Internet so, als
säßen alle im selben Raum - Peer-to-Peer, ohne Portweiterleitung am Router,
kostenlos und ohne Werbung.

Netzwerk-ID von Project Earth LAN: 091f0945fc5012f1

Der Project Earth LAN Manager ist das All-in-One-Werkzeug dazu: Einrichtung,
Netzwerkverwaltung, Spiele finden und beitreten, Chat, Voice, Dateien und mehr.


================================================================================
2. ZEROTIER ONE - HERKUNFT, ZWECK UND WAS ES AUF DEINEM PC ANLEGT
================================================================================
Herkunft
  ZeroTier wurde 2011 von Adam Ierymenko gegründet (Firmensitz USA,
  Kalifornien). Die Software ist Open Source und wird weltweit von
  Privatleuten (Gaming, Heimnetz) und Firmen (Cloud, IoT) eingesetzt.
  Der Manager lädt ZeroTier ausschließlich von der offiziellen Seite
  https://download.zerotier.com herunter.

Zweck
  ZeroTier verbindet Geräte überall auf der Welt so, als hingen sie am selben
  Switch - egal hinter welchem Router, NAT oder welcher Firewall sie stehen.
  - Virtuelles Layer-2-Netzwerk: Jedes Gerät bekommt eine virtuelle IP.
  - Peer-to-Peer: Die Daten fließen direkt von PC zu PC (geringe Latenz).
    ZeroTier-Server helfen nur beim ersten Kontakt oder, falls keine direkte
    Verbindung möglich ist, als Weiterleitung ("Relay") - auch dann bleiben
    die Daten verschlüsselt.
  - Verschlüsselung: Jede Verbindung ist Ende-zu-Ende verschlüsselt
    (Curve25519/Ed25519 für Schlüssel und Identität, Salsa20/Poly1305 bzw.
    AES-GMAC-SIV für die Daten).
  - Zugriffsregeln: Der Betreiber eines Netzwerks legt fest, wer hinein darf,
    und kann netzwerkweite Firewall-Regeln setzen (Flow Rules, siehe Kapitel 7).

Was ZeroTier auf deinem PC anlegt
  Programmordner:
    C:\Program Files (x86)\ZeroTier\One\   (bzw. C:\Program Files\ZeroTier\One\)
    - Oberfläche im Infobereich der Taskleiste und das Befehlszeilen-Werkzeug
      zerotier-cli, über das der Manager ZeroTier steuert.

  Datenordner:  C:\ProgramData\ZeroTier\One\
    - identity.secret   Privater Schlüssel (Identität) dieses PCs.
                        NIEMALS weitergeben - wer diese Datei hat, kann sich
                        im Netzwerk als dein PC ausgeben.
    - identity.public   Öffentlicher Teil der Identität. Daraus stammt deine
                        10-stellige ZeroTier-Adresse (Geräte-ID).
    - authtoken.secret  Zugangsschlüssel für die lokale Steuerung von ZeroTier
                        (nur für Programme auf diesem PC, z. B. zerotier-cli).
    - networks.d\       Je beigetretenem Netzwerk eine Datei <Netzwerk-ID>.conf
                        (Einstellungen vom Netzwerk-Betreiber inkl. Flow Rules)
                        und <Netzwerk-ID>.local.conf (lokale Einstellungen).
    - peers.d\          Zwischenspeicher bekannter Gegenstellen (schnellerer
                        Verbindungsaufbau).
    - planet            Liste der ZeroTier-Root-Server (vermitteln den ersten
                        Kontakt zwischen den Geräten).
    - zerotier-one.port Lokaler Steuerport des Dienstes.
    - Außerdem das Dienstprogramm von ZeroTier selbst.

  Windows-Dienst:  "ZeroTier One" (ZeroTierOneService) - startet mit Windows
                   und hält die Netzwerkverbindungen aufrecht.

  Netzwerkadapter: Je Netzwerk ein virtueller Adapter "ZeroTier One [Netzwerk-ID]"
                   mit deiner virtuellen IP. Er verschwindet, wenn du das
                   Netzwerk verlässt.

  Netzwerk-Port:   ZeroTier selbst nutzt UDP-Port 9993.


================================================================================
3. ALLE FUNKTIONEN DES MANAGERS
================================================================================
CONTROL CENTER (Startfenster)
  - Live-Status: ZeroTier-Verbindung, eigene IP, Freunde online, aktueller
    Netzwerkadapter, andere Manager im Netz, Version, nächster Spieleabend.
  - Adapter wechseln: Der Netzwerkadapter wird einmal zentral gewählt und gilt
    für alle Fenster (auch live in bereits offenen). Beim ersten Start wird
    automatisch der von Windows bevorzugte Adapter (niedrigste Metrik)
    genommen. Bei einem ZeroTier-Adapter baut der Manager die Verbindung
    automatisch auf (Beitritt, Metrik 1, MTU 1380).
  - Wer spielt gerade was: zeigt, welcher Manager im Netz gerade welches Spiel
    spielt (erkannt über laufende Spiel-Programme) und ob er selbst hostet.
  - Mitspielen: startet das Spiel und verbindet direkt zum Server des Spielers
    (bei gut 40 Spielen automatisch, z. B. Battlefield 1942/2/2142, Unreal
    Tournament, Call of Duty, Quake 3, Source-Spiele, Arma, Factorio, Valheim).
    Die Server-Adresse liegt dabei IMMER zusätzlich in der Zwischenablage.
  - Spieleabend-Planer: Spieleabende ankündigen und absagen. Alle Manager im
    Netz bekommen die Ankündigung automatisch - auch wer den Manager erst
    später öffnet (Hinweis ab 3 Tage vorher, Erinnerung 15 Minuten vorher).
    Absagen kann nur, wer den Abend angelegt hat. Das Spiel wählst du aus der
    Liste oder tippst es selbst ein (z. B. "Doom 3 Open Coop") - eigene
    Einträge merkt sich der Manager für das nächste Mal ("..." zum Verwalten).
  - Fehlerlog exportieren: packt Protokolle und System-/Netzwerk-Infos zur
    Fehlersuche in eine ZIP-Datei auf dem Desktop (nur auf deinen Klick).
  - Neue Version: prüft beim Start und alle 6 Stunden auf GitHub, ob es eine
    neuere Version gibt. Wenn ja, erscheint im Live-Status der Button "Neue
    Version auf GitHub". Er öffnet nur die Projektseite
    https://github.com/Firehawk215/Project-Earth-Lan - herunterladen und
    ersetzen machst du selbst. Ein automatisches Update gibt es nicht.
  - Postfach: zeigt ungelesene Nachrichten an (Klick öffnet Option 11); neue
    Nachrichten melden sich unten rechts mit einem Hinweisfenster.
  - Es läuft immer nur ein Control Center. Ein zweiter Start holt das schon
    offene Fenster nach vorne (z. B. wenn es per Autostart minimiert läuft).

OPTION 1 - Project Earth LAN installieren
  Lädt ZeroTier One von der offiziellen Seite, installiert es, tritt zwei
  Netzwerken bei und optimiert die Adapter (Metrik und MTU 1380):
  - 091f0945fc5012f1  "Project Earth Lan" - das Spiele-Netzwerk (Metrik 1)
  - 091f0945fc744570  "Account und Netzwerk Verwaltungs Server" (Metrik 2) -
    nur für die Weboberfläche http://10.147.0.34:3000, auf der du dir ein
    eigenes, kostenloses ZeroTier-Netzwerk anlegen und verwalten kannst.
  Legt "Project Earth Lan IP.txt" auf dem Desktop an (deine IPs, Anleitung für
  ein eigenes Netzwerk und eine Vorlage für Flow Rules).

OPTION 2 - Netzwerk Login
  Beitritt zu jedem beliebigen ZeroTier-Netzwerk über die 16-stellige
  Netzwerk-ID; der Adapter wird automatisch eingestellt (Metrik 1, MTU 1380).

OPTION 3 - Netzwerk Logout
  Verlässt ein Netzwerk und entfernt dessen Adapter. Deine IP bleibt beim
  Wiederverbinden erhalten (die Freischaltung beim Netzwerk-Betreiber bleibt).

OPTION 4 - ReadMe erstellen
  Erstellt diese Datei.

OPTION 5 - Tools, Mods & Games Downloader
  Liest die Ordner des Download-Servers http://172.25.31.177:9930 aus (nur im
  Project Earth LAN erreichbar), Kategorien "Windows Tools", "Mods" und
  "Games" (mit Passwort). Ausgewählte Dateien landen auf dem Desktop unter
  "Server_Downloads\<Kategorie>".

OPTION 6 - Windows Remotedesktop aktivieren / deaktivieren
  Zum gegenseitigen Helfen bei Problemen:
  - Verbinden: startet eine Remotedesktop-Verbindung zu einer IP (Port 9870).
  - RDP hier aktivieren: schaltet Remotedesktop auf diesem PC ein, legt den
    Port auf 9870, erstellt eine Firewall-Regel und "RDP_Port.txt".
  - RDP sperren: schaltet Remotedesktop wieder aus und entfernt die Regel.
  - Konto erstellen / Passwort ändern: legt ein lokales Konto für
    Remotedesktop an (Administrator + Remotedesktopbenutzer) oder ändert das
    Passwort eines bestehenden Kontos.

OPTION 7 - LAN-Spiele als Verknüpfungen anlegen (LAN Game Finder)
  Sucht installierte Spiele (Steam, Epic, GOG, Ubisoft, EA, installierte
  Programme sowie Ordner "Games", "Spiele" und "ElAmigos") und legt für
  LAN-fähige Spiele Verknüpfungen im Desktop-Ordner "Lan Games" an:
  - Whitelist mit über 500 LAN-Spielen, Blacklist für Programme/Werkzeuge.
  - Automatische Wahl der richtigen Spiel-EXE (keine Installer, Server,
    Editoren oder Crash-Reporter); Steam-Spiele starten über Steam.
  - "Eigene Listen": eigene Whitelist, Blacklist und EXE-Korrekturen.
  - Selbst angelegte Verknüpfungen bleiben bei jedem neuen Scan erhalten.

OPTION 8 - Manuelle Game Suche
  Durchsucht alle Laufwerke (auch versteckte Ordner) nach Spielordnern und
  EXE-Dateien per Name, öffnet den Fundort oder legt eine Verknüpfung in
  "Lan Games" an (bei Ordnern wird die Haupt-EXE automatisch bestimmt).

OPTION 9 - Server-Manager & Server-Browser (Port 9872)
  - Server-Browser: sucht laufende Spiel-Server im Netz (Source/A2S, GameSpy,
    Quake 3/Call of Duty, Minecraft Java & Bedrock und bekannte Spiel-Ports),
    per IP, ganzem Subnetz oder Port; "Join" startet das Spiel und verbindet.
  - Manager-Verbund: tauscht gefundene Server-Listen mit anderen Managern aus
    und bietet einen Text-Chat.
  - Server-Manager: startet und überwacht Dedicated Server (auf Wunsch
    automatischer Neustart nach Absturz) und legt Firewall-Regeln dafür an.

OPTION 10 - Kommunikationszentrale (Chat, Dateien, Voice)
  - Text-Chat: Gruppenchat, private Nachrichten, temporäre und dauerhafte
    Kanäle (auch mit Passwort); dauerhafte Kanäle werden netzwerkweit
    abgeglichen.
  - Dateien: direkte Übertragung von PC zu PC mit Fortschritt, Tempo und
    Restzeit, parallelen Verbindungen und Tempolimit.
  - Voice: Gruppen-Sprachchat, private Gespräche, Push-to-Talk,
    Mikrofon-Empfindlichkeit, Lautstärke je Person; läuft auch minimiert weiter.
  - "Nur Freunde anzeigen" (Freundesliste aus Option 11), Rechtsklick-Menü
    (Freund hinzufügen/entfernen, Anstupsen, IP kopieren, Lautstärke, bannen).

OPTION 11 - Freundesliste, Bannliste & Postfach
  - Freundesliste: Freunde mit Name, IP und Notiz anlegen, bearbeiten und
    entfernen. Zeigt, wer gerade online ist; Spieler, die gerade im Netz
    sind, übernimmst du per Doppelklick als Freund.
  - Bannliste: IP-Adressen bannen und entbannen (mit Grund). Von gebannten
    IPs nimmt der Manager nichts mehr an (Chat, Voice, Dateien, Postfach).
  - Postfach mit Eingang, Ausgang und Gesendet: Nachrichten schreiben,
    beantworten und löschen. Ist der Empfänger online, kommt die Nachricht
    sofort an. Sonst wartet sie im Ausgang und wird automatisch zugestellt,
    sobald er seinen Manager das nächste Mal startet. Zusätzlich halten bis
    zu 3 gerade laufende Manager eine verschlüsselte Kopie bereit - so kommt
    sie auch an, wenn du selbst dann schon offline bist.
  Freundes- und Bannliste gehören nur dir und werden nicht mit anderen
  abgeglichen.

OPTION 12 - Autostart (Button im Control Center)
  Nimmt den Manager in den Windows-Autostart auf oder entfernt ihn wieder.
  Umgesetzt als geplante Aufgabe "Project Earth LAN Manager (Autostart)":
  Start ca. 30 Sekunden nach der Anmeldung, minimiert, mit Administrator-
  rechten, aber ohne UAC-Abfrage. So sind Postfach, Live-Status und
  Spieleabend-Ankündigungen immer aktiv.


================================================================================
4. ORDNER UND DATEIEN, DIE DER MANAGER ANLEGT
================================================================================
C:\Project-Earth-Lan\   (gemeinsame Einstellungen aller Fenster)
  selected_adapter.json    Zentral gewählter Netzwerkadapter.
  Friendlist.json          Deine Freundesliste (Option 11) und die dauerhaften
                           Chat-/Voice-Kanäle.
  ip_bans.json             Von dir gebannte IP-Adressen (Option 11).
  PeerVolumes.json         Von dir eingestellte Lautstärke je Teilnehmer.
  events.json              Bekannte Spieleabende (Spieleabend-Planer).
  events_local.json        Welche Ankündigungen du schon gesehen hast und die
                           Absage-Codes deiner eigenen Spieleabende.
  eigene_spiele.txt        Deine selbst eingetippten Spiele für den
                           Spieleabend-Planer (einfache Textdatei).
  eigene_whitelist.txt     Deine zusätzlichen Spiele für Option 7.
  eigene_blacklist.txt     Namen, die Option 7 nie verknüpfen soll.
  exe_korrekturen.txt      Deine festen Zuordnungen "Spiel | Spiel-EXE".
  logs\                    Fehlerprotokolle je Fenster (z. B. ControlCenter.log,
                           Option9.log), höchstens 1 MB je Datei.
  Postfach\                Postfach (Option 11), eine Datei pro Nachricht:
    Eingang\               empfangene Nachrichten
    Ausgang\               eigene Nachrichten, die noch zugestellt werden
    Gesendet\              zugestellte eigene Nachrichten
    Weiterleitung\         verschlüsselte Kopien, die dein Manager für andere
                           bereithält (für dich nicht lesbar, max. 14 Tage)
    Schluessel\            öffentliche Schlüssel anderer Manager
    empfangen.ids          schon erhaltene Nachrichten (gegen Doppelte)
    online.txt             wer gerade online ist (nur solange der Manager läuft)
  keys\postfach_schluessel.dat
                           Dein privater Postfach-Schlüssel, per Windows-DPAPI
                           an dein Benutzerkonto gebunden verschlüsselt.

%APPDATA%\ProjectEarthLan\   (deine persönlichen Einstellungen)
  chat.json                Dein Anzeigename und Ton an/aus.
  fileshare.json           Download-Ordner, parallele Verbindungen, Tempolimit.
  voice.json               Gewähltes Mikrofon und Lautsprecher.
  joinmap.json             Gemerkte Spiel-EXE für "Mitspielen"/"Join".
  chat\chat_JJJJ-MM-TT.log Chat-Verlauf, eine Datei pro Tag.

%USERPROFILE%\Downloads\ProjectEarthLAN\
  Empfangene Dateien aus der Kommunikationszentrale (Ordner änderbar).

Desktop
  Lan Games\               Spiele-Verknüpfungen (Option 7 und 8). Einmalig beim
                           Umstieg auf die neue Version: Unterordner
                           "_Alte Verknüpfungen (vor Update)".
  Server_Downloads\        Downloads aus Option 5, je Kategorie ein Ordner.
  Project Earth Lan IP.txt Deine ZeroTier-IPs, Anleitung eigenes Netzwerk,
                           Flow-Rules-Vorlage (Option 1).
  Was genau passiert wenn ich Project Earth LAN Manager benutze.txt
                           Diese Datei (Option 4).
  RDP_Port.txt             Hinweis auf den Remotedesktop-Port (Option 6).
  ProjectEarthLan_Fehlerlog_<PC>_<Datum>.zip
                           Nur wenn du im Control Center den Fehlerlog
                           exportierst.

Windows-Aufgabenplanung (nur wenn der Autostart aktiv ist, Button 12)
  "Project Earth LAN Manager (Autostart)"   startet den Manager bei der
                                            Anmeldung.

Temporär
  Der ZeroTier-Installer (in %TEMP%) und der Arbeitsordner des Fehlerlog-
  Exports werden nach Gebrauch automatisch gelöscht.


================================================================================
5. NETZWERK-PORTS, FIREWALL-REGELN UND SYSTEM-EINSTELLUNGEN
================================================================================
Ports
  9993  UDP      ZeroTier selbst
  9776  TCP/UDP  Freunde und dauerhafte Kanäle
  9870  TCP      Remotedesktop (nur wenn in Option 6 aktiviert)
  9872  TCP/UDP  Server-Browser-Verbund und dessen Text-Chat (Option 9)
  9873  UDP      Voice-Chat
  9874  TCP/UDP  Text-Chat (Option 10)
  9876  TCP/UDP  Dateiübertragung
  9928  UDP      Live-Status, "Wer spielt was", Spieleabende
  9929  TCP      Postfach (Option 11)
  9930  TCP      Download-Server (Option 5, nur ausgehende Verbindung)

Firewall-Regeln (Windows Defender Firewall, eingehend)
  Alle Regeln des Managers beginnen mit "Project Earth LAN" und erlauben
  Verbindungen NUR aus dem lokalen Subnetz, also von Geräten im selben
  (virtuellen) Netzwerk - nicht aus dem Internet.
  Ausnahme: Die Remotedesktop-Regel "RDP Port 9870 (Custom)" aus Option 6 gilt
  für alle Netzwerke. Aktiviere Remotedesktop deshalb nur, solange du Hilfe
  brauchst, und sperre es danach wieder.
  Der Server-Manager (Option 9) legt für gestartete Dedicated Server ebenfalls
  Regeln an, auch diese nur für das lokale Subnetz.

System-Einstellungen
  - ZeroTier-Adapter: Schnittstellenmetrik (1 bzw. 2) und MTU 1380, damit
    Spiele den ZeroTier-Adapter bevorzugen und keine Pakete zerteilt werden.
  - Nur bei Option 6: Remotedesktop an/aus und Port 9870 in der Registry,
    lokales Benutzerkonto für Remotedesktop.
  - Nur bei Button 12: eine geplante Aufgabe für den Autostart.
  Sonst verändert der Manager nichts an Windows.


================================================================================
6. SICHERHEIT & DATENSCHUTZ
================================================================================
Warum Administrator-Rechte?
  Der Manager startet sich mit Administrator-Rechten. Die braucht er, um
  ZeroTier zu installieren, Netzwerken beizutreten, Firewall-Regeln anzulegen
  und die Netzwerkadapter einzustellen - ohne geht das unter Windows nicht.
  Der Parameter "ExecutionPolicy Bypass" gilt nur für den Manager selbst;
  die PowerShell-Einstellungen deines Systems werden nicht dauerhaft geändert.

Wer betreibt die Netzwerke und was sieht der Betreiber?
  Beide Netzwerke aus Option 1 laufen über einen ZeroTier-Controller, den
  Project Earth LAN selbst betreibt. Das gilt auch für Netzwerke, die du über
  die Weboberfläche http://10.147.0.34:3000 anlegst.
  Der Betreiber eines Netzwerks sieht die ZeroTier-Adresse, die virtuelle IP,
  ob ein Gerät online ist und in der Regel dessen öffentliche IP-Adresse - und
  er entscheidet, wer ins Netzwerk darf.
  Den Datenverkehr zwischen zwei Teilnehmern kann er NICHT mitlesen: ZeroTier
  verschlüsselt jede Verbindung Ende-zu-Ende zwischen den beteiligten Geräten.
  Du kannst jedes Netzwerk jederzeit über Option 3 verlassen.

Was sehen andere Teilnehmer im Netzwerk?
  Wie in jedem echten LAN sieht jedes Mitglied, was im Netzwerk für alle
  sichtbar ist. Beim Manager ist das:
  - dein Anzeigename, deine virtuelle IP, dein ZeroTier-Status, die Version
    und das Spiel, das du gerade spielst (Live-Status / "Wer spielt was"),
  - Nachrichten im Gruppenchat und in offenen Kanälen, deine Anwesenheit in
    Kanälen, Spieleabende,
  - Server-Listen, wenn du in Option 9 "Server mit Managern teilen" aktivierst.
  Private Nachrichten, Postfach-Nachrichten, Dateien und private Gespräche
  gehen nur an die gewählte Person.

Schutz vor gefälschten Meldungen
  Live-Status und Spieleabende werden mit einem Netzwerk-Schlüssel signiert
  (HMAC-SHA256). Meldungen ohne gültige Signatur werden ignoriert - fremde
  Programme können so keine falschen Ankündigungen einschleusen, und einen
  Spieleabend absagen kann nur, wer ihn angelegt hat.

Postfach (Option 11)
  Direkt zugestellte Nachrichten laufen über die verschlüsselte ZeroTier-
  Verbindung und sind mit dem Netzwerk-Schlüssel signiert; als Absender gilt
  die tatsächliche IP der Verbindung. Kopien, die andere Manager für dich
  bereithalten, sind zusätzlich Ende-zu-Ende verschlüsselt (RSA-2048 und
  AES-256) - nur der Empfänger kann sie öffnen. Der Absender unterschreibt
  jede Nachricht; ist die Unterschrift geprüft, zeigt das Postfach
  "bestätigt" an. Auf deinem PC liegen die Nachrichten unverschlüsselt in
  C:\Project-Earth-Lan\Postfach - wie bei einem E-Mail-Programm.

Updates
  Es gibt KEIN automatisches Update und keine Verteilung von Programmdateien
  über das Netzwerk - niemand kann dir so eine veränderte Version
  unterschieben. Der Manager schaut nur nach, ob auf GitHub eine neuere
  Version liegt, und zeigt dann einen Button, der die Projektseite öffnet.
  Neue Versionen gibt es ausschließlich unter
  https://github.com/Firehawk215/Project-Earth-Lan - lade den Manager nie aus
  anderen Quellen (Chat, Mail, fremde Links) herunter.

Download-Server (Option 5)
  Nur im Project Earth LAN erreichbar. Die Dateien stellt der Betreiber
  bereit. Prüfe heruntergeladene Programme wie jede andere Datei aus dem
  Internet mit deinem Virenscanner.

Remotedesktop (Option 6)
  Standardmäßig AUS. Nur einschalten, wenn dir jemand helfen soll, und danach
  wieder sperren. Das angelegte Konto ist ein Administrator-Konto: Verwende
  ein starkes Passwort und lösche das Konto, wenn du es nicht mehr brauchst.
  Remotedesktop läuft auf Port 9870 - diesen Port blockieren die Flow Rules
  bewusst nicht, damit Hilfe über das Project Earth LAN möglich ist. Schutz
  ist dann allein dein Passwort.

Was wird gespeichert und was wird gesendet?
  Einstellungen, Freundes- und Bannliste, Chat-Verläufe, Postfach und
  Protokolle bleiben lokal auf deinem PC (siehe Kapitel 4). Der Manager
  schickt keine Nutzungs- oder Telemetriedaten an den Betreiber - der sieht
  als Netzwerk-Teilnehmer nur dasselbe wie alle anderen (siehe oben). Die
  Versionsprüfung fragt beim Start und alle 6 Stunden die öffentliche
  GitHub-Seite des Projekts ab (GitHub sieht dabei wie bei jedem
  Seitenaufruf deine Internet-IP).
  Der Fehlerlog-Export enthält keine Chats, Postfach-Nachrichten, Passwörter
  oder Schlüssel, aber IP-Adressen und deinen Computernamen - schicke ihn nur
  an Leute, denen du vertraust.

Offener Code
  Der Manager ist ein lesbares PowerShell-Skript ohne verschleierten Code.
  Wer unsicher ist, kann ihn vor dem Start lesen oder zuerst in einer
  virtuellen Maschine testen.

Du willst niemandem vertrauen müssen?
  Lege dir ein eigenes Netzwerk direkt bei ZeroTier an (my.zerotier.com) und
  tritt ihm über Option 2 bei. Chat, Voice, Dateien, Server-Browser,
  Spielerkennung und Spieleabende funktionieren in jedem ZeroTier-Netzwerk -
  grundsätzlich auch mit Hamachi, Radmin VPN oder Tailscale.

Tipps
  - identity.secret (siehe Kapitel 2) niemals weitergeben.
  - Nur Netzwerken beitreten, deren Betreiber du vertraust.
  - Windows und ZeroTier aktuell halten, starke Passwörter verwenden.


================================================================================
7. ZEROTIER FLOW RULES - DIE FIREWALL DES NETZWERKS
================================================================================
Was sind Flow Rules?
  Flow Rules sind Firewall-Regeln, die der Betreiber eines ZeroTier-
  Netzwerks zentral festlegt. Sie werden als Teil der signierten
  Netzwerk-Einstellungen an jedes Gerät verteilt und dort direkt im
  ZeroTier-Dienst durchgesetzt - auf der Seite des Senders UND auf der Seite
  des Empfängers. Ein gesperrtes Paket erreicht dein Windows also gar nicht
  erst.

Warum sind sie so wirksam?
  - Kein Teilnehmer kann sie abschalten oder ändern - nur der Betreiber.
  - Selbst wer einen veränderten ZeroTier-Client benutzt, kommt nicht durch:
    Dein PC filtert eingehende Pakete ebenfalls nach denselben Regeln.
  - Sie gelten für das ganze Netzwerk gleichzeitig, unabhängig davon, wie die
    Windows-Firewall des einzelnen Teilnehmers eingestellt ist.
  - Zusätzlich ist in ZeroTier jede MAC-Adresse fest an die Identität des
    Geräts gebunden - ein Teilnehmer kann sich nicht als ein anderes Gerät
    ausgeben.

Diese Flow Rules sind im Project Earth LAN aktiv:

  1. Windows-Freigaben, NetBIOS & RPC - gesperrt
       Ports 135, 137-139, 445
       Das ist der häufigste Angriffsweg in Netzwerken (Datei- und
       Druckerfreigaben, Fernzugriff auf Windows-Dienste). Kein Teilnehmer
       kann über das Project Earth LAN auf deine Freigaben zugreifen.

  2. Fernwartung - gesperrt
       Port 3389 (Remotedesktop-Standardport) und Port 5900 (VNC)
       Niemand kann sich über die Standard-Ports auf deinen Bildschirm
       schalten.

  3. Discovery- und Broadcast-Lärm - gesperrt
       Ports 111, 548, 631, 1900, 3702, 5353, 5355, 6320, 17500
       (u. a. UPnP/SSDP, WS-Discovery, mDNS/Bonjour, LLMNR, Drucker, Dropbox)
       Dein PC verrät im Netzwerk nicht, welche Geräte und Dienste er hat, und
       die Bandbreite bleibt für die Spiele frei.

  4. Alles andere - erlaubt
       Spiele, Chat, Voice, Dateiübertragung und Server-Suche funktionieren
       ohne Einschränkung.

Die Regeln im ZeroTier-Format (auch in "Project Earth Lan IP.txt" als Vorlage
für dein eigenes Netzwerk):

  drop dport 135 or dport 137:139 or dport 445;
  drop dport 3389 or dport 5900;
  drop dport 111 or dport 548 or dport 631 or dport 1900 or dport 3702
       or dport 5353 or dport 5355 or dport 6320 or dport 17500;
  accept;

Wichtig zu wissen
  Flow Rules schützen den Verkehr INNERHALB des ZeroTier-Netzwerks. Ports, die
  sie erlauben (z. B. Spiel-Ports oder Remotedesktop auf Port 9870), sind nur
  durch das jeweilige Programm und dessen Passwort geschützt. Für dein
  Heimnetz und das Internet gelten weiterhin dein Router und deine
  Windows-Firewall.


================================================================================
8. ALLES WIEDER ENTFERNEN
================================================================================
  1. Autostart: Button 12 im Control Center (oder in der Aufgabenplanung die
     Aufgabe "Project Earth LAN Manager (Autostart)" löschen).
  2. Netzwerke verlassen: Option 3.
  3. Remotedesktop: Option 6 -> "RDP Standard Sperren". Ein über Option 6
     angelegtes Konto löschst du unter Einstellungen -> Konten -> Andere
     Benutzer (oder in der Eingabeaufforderung als Administrator:
     net user <Kontoname> /delete).
  4. ZeroTier deinstallieren: Einstellungen -> Apps -> "ZeroTier One".
     Danach kann der Ordner C:\ProgramData\ZeroTier gelöscht werden.
  5. Firewall-Regeln: Windows Defender Firewall -> Erweiterte Einstellungen ->
     Eingehende Regeln -> alle Regeln, die mit "Project Earth LAN" beginnen,
     sowie "RDP Port 9870 (Custom)" löschen.
  6. Daten des Managers löschen: C:\Project-Earth-Lan,
     %APPDATA%\ProjectEarthLan, %USERPROFILE%\Downloads\ProjectEarthLAN und
     die in Kapitel 4 genannten Dateien und Ordner auf dem Desktop.
  Metrik und MTU verschwinden automatisch mit dem ZeroTier-Adapter.


================================================================================
9. IMPRESSUM
================================================================================
Project Earth Lan

Kontakt:
Alexander Meiß
Bahnhofstr. 28
63549 Ronneburg Hüttengesäß
Tel: +4915156947939
Email: firehawk215@googlemail.com
"@

    Set-Content -Path $TxtFile -Value $explanationText -Encoding UTF8 -Force
    Write-Host "Erklärungs-Datei erfolgreich auf dem Desktop erstellt!"
    $ans = [System.Windows.Forms.MessageBox]::Show("Die Datei wurde auf deinem Desktop erstellt:`n$TxtFile`n`nJetzt öffnen?", "ReadMe erstellt", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Information)
    if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) {
        try { Start-Process -FilePath 'notepad.exe' -ArgumentList "`"$TxtFile`"" } catch { }
    }
}



# ------------------------------------------------------------------------------
# OPTION 5: Tools, Mods, Games
# ------------------------------------------------------------------------------
function Invoke-ToolsModsGames {
    $baseUrl = "http://172.25.31.177:9930"
    $desktopPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)
    $downloadBaseDir = Join-Path $desktopPath "Server_Downloads"

    if (-not (Test-Path -Path $downloadBaseDir)) {
        New-Item -ItemType Directory -Path $downloadBaseDir -Force | Out-Null
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Tools, Mods, Games - HTTP Downloader"
    $form.Size = New-Object System.Drawing.Size(700, 710)
    $form.StartPosition = "CenterParent"
    $form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $form.ForeColor = [System.Drawing.Color]::White

    $fontMain = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Regular)
    $fontBold = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)

    $lblHeader = New-Object System.Windows.Forms.Label
    $lblHeader.Text = "Server URL: $baseUrl"
    $lblHeader.Location = New-Object System.Drawing.Point(20, 15)
    $lblHeader.Size = New-Object System.Drawing.Size(640, 25)
    $lblHeader.Font = $fontBold
    $lblHeader.ForeColor = [System.Drawing.Color]::White
    $form.Controls.Add($lblHeader)

    $grpCategory = New-Object System.Windows.Forms.GroupBox
    $grpCategory.Text = "Kategorie auswählen"
    $grpCategory.Location = New-Object System.Drawing.Point(20, 45)
    $grpCategory.Size = New-Object System.Drawing.Size(640, 70)
    $grpCategory.ForeColor = [System.Drawing.Color]::White
    $grpCategory.Font = $fontMain

    $rbTools = New-Object System.Windows.Forms.RadioButton
    $rbTools.Text = "Windows Tools"
    $rbTools.Location = New-Object System.Drawing.Point(20, 25)
    $rbTools.Size = New-Object System.Drawing.Size(150, 30)
    $rbTools.Checked = $true
    $rbTools.ForeColor = [System.Drawing.Color]::White
    $grpCategory.Controls.Add($rbTools)

    $rbMods = New-Object System.Windows.Forms.RadioButton
    $rbMods.Text = "Mods"
    $rbMods.Location = New-Object System.Drawing.Point(180, 25)
    $rbMods.Size = New-Object System.Drawing.Size(110, 30)
    $rbMods.ForeColor = [System.Drawing.Color]::White
    $grpCategory.Controls.Add($rbMods)

    $rbGames = New-Object System.Windows.Forms.RadioButton
    $rbGames.Text = "Games"
    $rbGames.Location = New-Object System.Drawing.Point(310, 25)
    $rbGames.Size = New-Object System.Drawing.Size(150, 30)
    $rbGames.ForeColor = [System.Drawing.Color]::White
    $grpCategory.Controls.Add($rbGames)

    $form.Controls.Add($grpCategory)

    $lblPass = New-Object System.Windows.Forms.Label
    $lblPass.Text = "Games Passwort:"
    $lblPass.Location = New-Object System.Drawing.Point(20, 125)
    $lblPass.Size = New-Object System.Drawing.Size(120, 25)
    $lblPass.ForeColor = [System.Drawing.Color]::White
    $lblPass.Visible = $false
    $form.Controls.Add($lblPass)

    $txtPass = New-Object System.Windows.Forms.TextBox
    $txtPass.Location = New-Object System.Drawing.Point(145, 122)
    $txtPass.Size = New-Object System.Drawing.Size(150, 25)
    $txtPass.PasswordChar = '*'
    $txtPass.BackColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
    $txtPass.ForeColor = [System.Drawing.Color]::White
    $txtPass.Visible = $false
    $form.Controls.Add($txtPass)

    $rbGames.add_CheckedChanged({
        $lblPass.Visible = $rbGames.Checked
        $txtPass.Visible = $rbGames.Checked
    })

    $btnScan = New-Object System.Windows.Forms.Button
    $btnScan.Text = "Ordner und Dateien auslesen"
    $btnScan.Location = New-Object System.Drawing.Point(310, 120)
    $btnScan.Size = New-Object System.Drawing.Size(350, 30)
    $btnScan.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $btnScan.ForeColor = [System.Drawing.Color]::White
    $btnScan.FlatStyle = "Flat"
    $form.Controls.Add($btnScan)

    $lstFiles = New-Object System.Windows.Forms.ListBox
    $lstFiles.Location = New-Object System.Drawing.Point(20, 160)
    $lstFiles.Size = New-Object System.Drawing.Size(640, 220)
    $lstFiles.SelectionMode = "MultiExtended"
    $lstFiles.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40)
    $lstFiles.ForeColor = [System.Drawing.Color]::White
    $lstFiles.Font = $fontMain
    $form.Controls.Add($lstFiles)

    $btnDownload = New-Object System.Windows.Forms.Button
    $btnDownload.Text = "Ausgewählte Datei(en) herunterladen"
    $btnDownload.Location = New-Object System.Drawing.Point(20, 390)
    $btnDownload.Size = New-Object System.Drawing.Size(450, 35)
    $btnDownload.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnDownload.ForeColor = [System.Drawing.Color]::White
    $btnDownload.FlatStyle = "Flat"
    $btnDownload.Font = $fontBold
    $form.Controls.Add($btnDownload)

    $btnOpenFolder = New-Object System.Windows.Forms.Button
    $btnOpenFolder.Text = "Ordner öffnen"
    $btnOpenFolder.Location = New-Object System.Drawing.Point(480, 390)
    $btnOpenFolder.Size = New-Object System.Drawing.Size(180, 35)
    $btnOpenFolder.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $btnOpenFolder.ForeColor = [System.Drawing.Color]::White
    $btnOpenFolder.FlatStyle = "Flat"
    $btnOpenFolder.Font = $fontBold
    $form.Controls.Add($btnOpenFolder)

    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Location = New-Object System.Drawing.Point(20, 432)
    $progressBar.Size = New-Object System.Drawing.Size(640, 18)
    $progressBar.Minimum = 0
    $progressBar.Maximum = 100
    $progressBar.Value = 0
    $form.Controls.Add($progressBar)

    $txtDebug = New-Object System.Windows.Forms.TextBox
    $txtDebug.Location = New-Object System.Drawing.Point(20, 460)
    $txtDebug.Size = New-Object System.Drawing.Size(640, 190)
    $txtDebug.Multiline = $true
    $txtDebug.ScrollBars = "Vertical"
    $txtDebug.ReadOnly = $true
    $txtDebug.BackColor = [System.Drawing.Color]::FromArgb(15, 15, 15)
    $txtDebug.ForeColor = [System.Drawing.Color]::White
    $txtDebug.Font = New-Object System.Drawing.Font("Consolas", 9)
    $form.Controls.Add($txtDebug)

    $logCallback = {
        param([string]$msg)
        $time = Get-Date -Format "HH:mm:ss"
        $txtDebug.AppendText("[$time] $msg`r`n")
        $txtDebug.SelectionStart = $txtDebug.Text.Length
        $txtDebug.ScrollToCaret()
    }

    $btnScan.add_Click({
        if ($rbGames.Checked) {
            if ($txtPass.Text -ne "") {
                [System.Windows.Forms.MessageBox]::Show("Falsches Passwort! Zugriff verweigert.", "Passwortschutz", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                &$logCallback "ZUGRIFF VERWEIGERT: Falsches Passwort für Kategorie Games."
                return
            }
        }

        $lstFiles.Items.Clear()
        $progressBar.Value = 0
        $category = if ($rbTools.Checked) { "Windows Tools" } elseif ($rbMods.Checked) { "Mods" } else { "Games" }
        
        &$logCallback "Kategorie gewählt: '$category'. Starte Auslesevorgang..."
        
        $targetCatUrl = "$baseUrl/$([System.Uri]::EscapeDataString($category))/"
        $files = Get-HTTPDirectoryContent -targetUrl $targetCatUrl -logCallback $logCallback

        foreach ($file in $files) {
            [void]$lstFiles.Items.Add($file)
        }
        
        &$logCallback "Vorgang beendet. $($files.Count) Datei(en) erfasst."
    })

    $btnDownload.add_Click({
        if ($lstFiles.SelectedItems.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Bitte wähle mindestens eine Datei aus der Liste aus.", "Hinweis", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }

        $category = if ($rbTools.Checked) { "Windows Tools" } elseif ($rbMods.Checked) { "Mods" } else { "Games" }
        $targetDir = Join-Path $downloadBaseDir $category
        if (-not (Test-Path -Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }

        $selectedFiles = @($lstFiles.SelectedItems)
        $btnDownload.Enabled = $false
        $totalFiles = $selectedFiles.Count
        $currentFileIndex = 0

        foreach ($selectedFileRel in $selectedFiles) {
            $currentFileIndex++
            $fileName = [System.IO.Path]::GetFileName($selectedFileRel)
            $destinationFile = Join-Path $targetDir $fileName

            $escapedRelPath = ($selectedFileRel -split '/' | ForEach-Object { [System.Uri]::EscapeDataString($_) }) -join '/'
            $downloadUrl = "$baseUrl/$([System.Uri]::EscapeDataString($category))/$escapedRelPath"

            &$logCallback "[$currentFileIndex/$totalFiles] Starte Download von: $fileName"
            $progressBar.Value = 0

            try {
                $request = [System.Net.HttpWebRequest]::Create($downloadUrl)
                $request.Method = "GET"
                $request.UserAgent = "Mozilla/5.0"
                
                $response = $request.GetResponse()
                $totalBytes = $response.ContentLength
                $responseStream = $response.GetResponseStream()
                $targetStream = [System.IO.File]::Create($destinationFile)

                $buffer = New-Object byte[] 1048576
                $bytesRead = 0
                $totalRead = 0
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                $lastLogTime = [System.Diagnostics.Stopwatch]::StartNew()

                while (($bytesRead = $responseStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    $targetStream.Write($buffer, 0, $bytesRead)
                    $totalRead += $bytesRead

                    if ($totalBytes -gt 0) {
                        $percent = [int](($totalRead / $totalBytes) * 100)
                        $progressBar.Value = [Math]::Min(100, $percent)
                    }

                    if ($lastLogTime.ElapsedMilliseconds -ge 1000 -or $totalRead -eq $totalBytes) {
                        $elapsedSec = $sw.Elapsed.TotalSeconds
                        if ($elapsedSec -gt 0) {
                            $bytesPerSec = $totalRead / $elapsedSec
                            $speedMBs = [Math]::Round($bytesPerSec / 1MB, 2)
                            $currentMB = [Math]::Round($totalRead / 1MB, 2)
                            $totalMB = [Math]::Round($totalBytes / 1MB, 2)
                            $percentVal = if ($totalBytes -gt 0) { [Math]::Min(100, [int](($totalRead / $totalBytes) * 100)) } else { 0 }
                            &$logCallback "Fortschritt: $percentVal% ($currentMB MB / $totalMB MB) | Speed: $speedMBs MB/s"
                        }
                        $lastLogTime.Restart()
                    }

                    [System.Windows.Forms.Application]::DoEvents()
                }

                $sw.Stop()
                $targetStream.Close()
                $responseStream.Close()
                $response.Close()

                $progressBar.Value = 100
                &$logCallback "DOWNLOAD ERFOLGREICH: $fileName"
            } catch {
                &$logCallback "DOWNLOAD FEHLER bei $fileName : $($_.Exception.Message)"
            }
        }

        $btnDownload.Enabled = $true
        [System.Windows.Forms.MessageBox]::Show("Download-Vorgang für alle ausgewählten Dateien abgeschlossen!", "Erfolg", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    })

    $btnOpenFolder.add_Click({
        $category = if ($rbTools.Checked) { "Windows Tools" } elseif ($rbMods.Checked) { "Mods" } else { "Games" }
        $targetDir = Join-Path $downloadBaseDir $category
        
        if (-not (Test-Path -Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
        
        Start-Process explorer.exe -ArgumentList "`"$targetDir`""
        &$logCallback "Zielordner im Explorer geöffnet: $targetDir"
    })

    &$logCallback "Tools, Mods, Games Manager gestartet."
    [void]$form.ShowDialog()
}
# ------------------------------------------------------------------------------
# OPTION 6: Windows Remotedesktop
# ------------------------------------------------------------------------------

function Invoke-CreateOrUpdateUserDialog {
    $metric1Adapter = Get-NetIPInterface -AddressFamily IPv4 | Where-Object { $_.InterfaceMetric -eq 1 -and $_.ConnectionState -eq "Connected" } | Select-Object -First 1
    
    $ipMetric1 = "Keine IP (Metrik 1) gefunden"
    $adapterName = "N/A"

    if ($metric1Adapter) {
        $adapterObj = Get-NetAdapter -InterfaceIndex $metric1Adapter.InterfaceIndex -ErrorAction SilentlyContinue
        if ($adapterObj) { $adapterName = $adapterObj.Name }
        $ipObj = Get-NetIPAddress -InterfaceIndex $metric1Adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($ipObj) { $ipMetric1 = $ipObj.IPAddress }
    }

    $userForm = New-Object System.Windows.Forms.Form
    $userForm.Text = "Lokales Benutzerkonto für RDP"
    $userForm.Size = New-Object System.Drawing.Size(430, 320)
    $userForm.StartPosition = "CenterParent"
    $userForm.FormBorderStyle = "FixedDialog"
    $userForm.MaximizeBox = $false
    $userForm.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $userForm.ForeColor = [System.Drawing.Color]::White

    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.Text = "Erstelle oder ändere ein Passwort für RDP-Zugriffe.`n`nAdapter (Metrik 1): $adapterName`nAktuelle RDP-IP: $ipMetric1"
    $lblInfo.Location = New-Object System.Drawing.Point(20, 15)
    $lblInfo.Size = New-Object System.Drawing.Size(380, 60)
    $lblInfo.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $userForm.Controls.Add($lblInfo)

    $lblUser = New-Object System.Windows.Forms.Label
    $lblUser.Text = "Benutzername:"
    $lblUser.Location = New-Object System.Drawing.Point(20, 85)
    $lblUser.Size = New-Object System.Drawing.Size(380, 20)
    $userForm.Controls.Add($lblUser)

    $txtUser = New-Object System.Windows.Forms.TextBox
    $txtUser.Text = "RDPUser"
    $txtUser.Location = New-Object System.Drawing.Point(20, 105)
    $txtUser.Size = New-Object System.Drawing.Size(370, 25)
    $txtUser.BackColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
    $txtUser.ForeColor = [System.Drawing.Color]::White
    $userForm.Controls.Add($txtUser)

    $lblPass = New-Object System.Windows.Forms.Label
    $lblPass.Text = "Neues Passwort:"
    $lblPass.Location = New-Object System.Drawing.Point(20, 140)
    $lblPass.Size = New-Object System.Drawing.Size(380, 20)
    $userForm.Controls.Add($lblPass)

    $txtPass = New-Object System.Windows.Forms.TextBox
    $txtPass.UseSystemPasswordChar = $true
    $txtPass.Location = New-Object System.Drawing.Point(20, 160)
    $txtPass.Size = New-Object System.Drawing.Size(370, 25)
    $txtPass.BackColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
    $txtPass.ForeColor = [System.Drawing.Color]::White
    $userForm.Controls.Add($txtPass)

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = "Konto Speichern / Ändern"
    $btnSave.Location = New-Object System.Drawing.Point(20, 210)
    $btnSave.Size = New-Object System.Drawing.Size(370, 35)
    $btnSave.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $btnSave.FlatStyle = "Flat"
    $userForm.Controls.Add($btnSave)

    $btnSave.Add_Click({
        $username = $txtUser.Text.Trim()
        $password = $txtPass.Text.Trim()

        if ([string]::IsNullOrWhiteSpace($username) -or [string]::IsNullOrWhiteSpace($password)) {
            [System.Windows.Forms.MessageBox]::Show("Bitte wähle einen Benutzernamen und ein Passwort.", "Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        }

        try {
            $existingUser = Get-LocalUser -Name $username -ErrorAction SilentlyContinue
            if ($existingUser) {
                Set-LocalUser -Name $username -Password (ConvertTo-SecureString $password -AsPlainText -Force)
                Write-Host "Passwort für lokales Konto '$username' geändert."
                [System.Windows.Forms.MessageBox]::Show("Passwort für Benutzer '$username' wurde erfolgreich aktualisiert!`n`nVerbindungs-IP (Metrik 1): $ipMetric1", "Erfolg", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            } else {
                New-LocalUser -Name $username -Password (ConvertTo-SecureString $password -AsPlainText -Force) -FullName "RDP Remote User" -Description "Erstellt via Project Earth LAN Manager"
                Add-LocalGroupMember -Group "Administratoren" -Member $username -ErrorAction SilentlyContinue
                Add-LocalGroupMember -Group "Remotedesktopbenutzer" -Member $username -ErrorAction SilentlyContinue
                Write-Host "Neuer lokaler Benutzer '$username' erstellt und zu Admins/RDP-Gruppe hinzugefügt."
                [System.Windows.Forms.MessageBox]::Show("Lokaler Benutzer '$username' wurde neu erstellt und für Remotedesktop berechtigt!`n`nVerbindungs-IP (Metrik 1): $ipMetric1", "Erfolg", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            }
            $userForm.Close()
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Fehler beim Erstellen/Ändern des Benutzers: $($_.Exception.Message)", "Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })

    [void]$userForm.ShowDialog()
}

function Invoke-RemoteDesktopZeroTier {
    $rdpForm = New-Object System.Windows.Forms.Form
    $rdpForm.Text = "Remotedesktop ZeroTierOne Control"
    $rdpForm.Size = New-Object System.Drawing.Size(430, 310)
    $rdpForm.StartPosition = "CenterParent"
    $rdpForm.FormBorderStyle = "FixedDialog"
    $rdpForm.MaximizeBox = $false
    $rdpForm.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $rdpForm.ForeColor = [System.Drawing.Color]::White

    $lblIP = New-Object System.Windows.Forms.Label
    $lblIP.Text = "ZeroTier IP-Adresse des Ziel-PCs:"
    $lblIP.Location = New-Object System.Drawing.Point(20, 15)
    $lblIP.Size = New-Object System.Drawing.Size(370, 20)
    $rdpForm.Controls.Add($lblIP)

    $txtIP = New-Object System.Windows.Forms.TextBox
    $txtIP.Location = New-Object System.Drawing.Point(20, 35)
    $txtIP.Size = New-Object System.Drawing.Size(370, 25)
    $txtIP.BackColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
    $txtIP.ForeColor = [System.Drawing.Color]::White
    $rdpForm.Controls.Add($txtIP)

    $btnConnect = New-Object System.Windows.Forms.Button
    $btnConnect.Text = "Verbinden (RDP Starten)"
    $btnConnect.Location = New-Object System.Drawing.Point(20, 75)
    $btnConnect.Size = New-Object System.Drawing.Size(370, 32)
    $btnConnect.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnConnect.FlatStyle = "Flat"
    $rdpForm.Controls.Add($btnConnect)

    $btnEnableRdp = New-Object System.Windows.Forms.Button
    $btnEnableRdp.Text = "RDP Hier Aktivieren"
    $btnEnableRdp.Location = New-Object System.Drawing.Point(20, 115)
    $btnEnableRdp.Size = New-Object System.Drawing.Size(180, 32)
    $btnEnableRdp.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $btnEnableRdp.FlatStyle = "Flat"
    $rdpForm.Controls.Add($btnEnableRdp)

    $btnDisableRdp = New-Object System.Windows.Forms.Button
    $btnDisableRdp.Text = "RDP Standard Sperren"
    $btnDisableRdp.Location = New-Object System.Drawing.Point(210, 115)
    $btnDisableRdp.Size = New-Object System.Drawing.Size(180, 32)
    $btnDisableRdp.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $btnDisableRdp.FlatStyle = "Flat"
    $rdpForm.Controls.Add($btnDisableRdp)

    $btnUserConfig = New-Object System.Windows.Forms.Button
    $btnUserConfig.Text = "RDP Konto erstellen / Passwort ändern"
    $btnUserConfig.Location = New-Object System.Drawing.Point(20, 155)
    $btnUserConfig.Size = New-Object System.Drawing.Size(370, 35)
    $btnUserConfig.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $btnUserConfig.FlatStyle = "Flat"
    $btnUserConfig.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $rdpForm.Controls.Add($btnUserConfig)

    $btnConnect.Add_Click({
        $targetIP = $txtIP.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($targetIP)) {
            [System.Windows.Forms.MessageBox]::Show("Bitte gib eine gültige ZeroTier-IP-Adresse ein.", "Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        }

        if (-not ($targetIP -contains ":")) {
            $targetIP = "$targetIP`:9870"
        }

        Write-Host "Starte Remotedesktopverbindung zu $targetIP..."
        Start-Process mstsc.exe -ArgumentList "/v:$targetIP"
        $rdpForm.Close()
    })

    $btnEnableRdp.Add_Click({
        try {
            $targetPort = 9870
            Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "PortNumber" -Value $targetPort

            Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
            New-NetFirewallRule -DisplayName "RDP Port 9870 (Custom)" -Direction Inbound -Action Allow -Protocol TCP -LocalPort $targetPort -ErrorAction SilentlyContinue | Out-Null
            Restart-Service -Name "TermService" -Force -ErrorAction SilentlyContinue

            $desktopPath = [System.IO.Path]::Combine($env:USERPROFILE, "Desktop")
            $portTxtFile = Join-Path $desktopPath "RDP_Port.txt"
            
            $portInfoText = @"
==================================
RDP PORT INFORMATION
==================================
Der aktuell eingestellte RDP-Port lautet: $targetPort

Der Port wurde auf $targetPort geändert. 
Beim Verbinden im mstsc-Fenster muss daher 'IP-Adresse:$targetPort' angegeben werden.
==================================
"@
            Set-Content -Path $portTxtFile -Value $portInfoText -Encoding UTF8 -Force

            Write-Host "Remotedesktop wurde aktiviert! Aktueller Port auf $targetPort geändert."
            [System.Windows.Forms.MessageBox]::Show("Remotedesktop wurde erfolgreich aktiviert!`n`nDer RDP-Port wurde auf $targetPort geändert.`nEine Datei 'RDP_Port.txt' wurde auf dem Desktop erstellt.", "Erfolg", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Fehler beim Aktivieren von RDP: $($_.Exception.Message)", "Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })

    $btnDisableRdp.Add_Click({
        try {
            Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 1
            Disable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
            Remove-NetFirewallRule -DisplayName "RDP Port 9870 (Custom)" -ErrorAction SilentlyContinue
            Restart-Service -Name "TermService" -Force -ErrorAction SilentlyContinue

            Write-Host "Remotedesktop wurde deaktiviert."
            [System.Windows.Forms.MessageBox]::Show("Remotedesktop wurde erfolgreich deaktiviert!", "Erfolg", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Fehler beim Deaktivieren von RDP: $($_.Exception.Message)", "Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })

    $btnUserConfig.Add_Click({
        Invoke-CreateOrUpdateUserDialog
    })

    [void]$rdpForm.ShowDialog()
}

# ------------------------------------------------------------------------------
# OPTION 7: LAN Game Verknüpfung in Ordner auf Desktop
# ------------------------------------------------------------------------------
function Invoke-LanGameFinder {
    # Kennung in der Verknüpfungs-Beschreibung: nur so markierte Verknüpfungen werden bei
    # einem neuen Scan ersetzt - selbst angelegte (z. B. über Option 8) bleiben erhalten.
    $autoDesc = 'Project Earth LAN - automatisch erkannt (Option 7)'

    function New-GameShortcut {
        param ([string]$SourcePath, [string]$DestinationFolder, [string]$ShortcutName, [string]$Arguments = '', [string]$GameExe = '', [string]$Description = '')
        $cleanName = ($ShortcutName -replace '[\\/:*?"<>|]', '').Trim()
        if (-not $cleanName) { $cleanName = 'Spiel' }
        $shortcutPath = Join-Path -Path $DestinationFolder -ChildPath "$cleanName.lnk"
        $wshShell = New-Object -ComObject WScript.Shell
        $shortcut = $wshShell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $SourcePath
        if ($Arguments) { $shortcut.Arguments = $Arguments }
        if ($GameExe) {
            $shortcut.WorkingDirectory = [System.IO.Path]::GetDirectoryName($GameExe)
            $shortcut.IconLocation = "$GameExe,0"
        } else {
            $shortcut.WorkingDirectory = [System.IO.Path]::GetDirectoryName($SourcePath)
        }
        if ($Description) { $shortcut.Description = $Description }
        $shortcut.Save()
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "LAN Game Scanner - Final Edition"
    $form.Size = New-Object System.Drawing.Size(760, 560)
    $form.StartPosition = "CenterParent"
    $form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $form.ForeColor = [System.Drawing.Color]::White

    $fontMain = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Regular)

    $btnDriveSelect = New-Object System.Windows.Forms.Button
    $btnDriveSelect.Location = New-Object System.Drawing.Point(20, 20)
    $btnDriveSelect.Size = New-Object System.Drawing.Size(165, 35)
    $btnDriveSelect.Text = "Festplatten Auswählen"
    $btnDriveSelect.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $btnDriveSelect.ForeColor = [System.Drawing.Color]::White
    $btnDriveSelect.FlatStyle = "Flat"
    $btnDriveSelect.Font = $fontMain

    $btnStartScan = New-Object System.Windows.Forms.Button
    $btnStartScan.Location = New-Object System.Drawing.Point(193, 20)
    $btnStartScan.Size = New-Object System.Drawing.Size(190, 35)
    $btnStartScan.Text = "Suche Starten"
    $btnStartScan.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnStartScan.ForeColor = [System.Drawing.Color]::White
    $btnStartScan.FlatStyle = "Flat"
    $btnStartScan.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

    $btnOpenFolder = New-Object System.Windows.Forms.Button
    $btnOpenFolder.Location = New-Object System.Drawing.Point(391, 20)
    $btnOpenFolder.Size = New-Object System.Drawing.Size(165, 35)
    $btnOpenFolder.Text = "'Lan Games' öffnen"
    $btnOpenFolder.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $btnOpenFolder.ForeColor = [System.Drawing.Color]::White
    $btnOpenFolder.FlatStyle = "Flat"
    $btnOpenFolder.Font = $fontMain

    $btnLists = New-Object System.Windows.Forms.Button
    $btnLists.Location = New-Object System.Drawing.Point(564, 20)
    $btnLists.Size = New-Object System.Drawing.Size(156, 35)
    $btnLists.Text = "Eigene Listen ▾"
    $btnLists.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $btnLists.ForeColor = [System.Drawing.Color]::White
    $btnLists.FlatStyle = "Flat"
    $btnLists.Font = $fontMain

    $txtLog = New-Object System.Windows.Forms.TextBox
    $txtLog.Location = New-Object System.Drawing.Point(20, 75)
    $txtLog.Size = New-Object System.Drawing.Size(700, 420)
    $txtLog.Multiline = $true
    $txtLog.ScrollBars = "Vertical"
    $txtLog.ReadOnly = $true
    $txtLog.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
    $txtLog.ForeColor = [System.Drawing.Color]::White
    $txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)

    $form.Controls.Add($btnDriveSelect)
    $form.Controls.Add($btnStartScan)
    $form.Controls.Add($btnOpenFolder)
    $form.Controls.Add($btnLists)
    $form.Controls.Add($txtLog)

    $global:SelectedDrives = @(Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Root)

    $btnDriveSelect.Add_Click({
        $driveForm = New-Object System.Windows.Forms.Form
        $driveForm.Text = "Laufwerke Überprüfen"
        $driveForm.Size = New-Object System.Drawing.Size(300, 320)
        $driveForm.StartPosition = "CenterParent"
        $driveForm.BackColor = [System.Drawing.Color]::FromArgb(35, 35, 35)
        $driveForm.ForeColor = [System.Drawing.Color]::White

        $checkedListBox = New-Object System.Windows.Forms.CheckedListBox
        $checkedListBox.Location = New-Object System.Drawing.Point(20, 20)
        $checkedListBox.Size = New-Object System.Drawing.Size(240, 200)
        $checkedListBox.BackColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
        $checkedListBox.ForeColor = [System.Drawing.Color]::White

        $allDrives = Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Root
        foreach ($d in $allDrives) {
            $isChecked = $global:SelectedDrives -contains $d
            [void]$checkedListBox.Items.Add($d, $isChecked)
        }

        $btnConfirm = New-Object System.Windows.Forms.Button
        $btnConfirm.Location = New-Object System.Drawing.Point(20, 230)
        $btnConfirm.Size = New-Object System.Drawing.Size(240, 30)
        $btnConfirm.Text = "Übernehmen"
        $btnConfirm.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
        $btnConfirm.ForeColor = [System.Drawing.Color]::White
        $btnConfirm.FlatStyle = "Flat"
        $btnConfirm.Add_Click({
            # Als Kopie übernehmen - die Liste des Dialogs ist nach dem Schließen ungültig.
            $global:SelectedDrives = @($checkedListBox.CheckedItems | ForEach-Object { [string]$_ })
            $driveForm.Close()
        })

        $driveForm.Controls.Add($checkedListBox)
        $driveForm.Controls.Add($btnConfirm)
        [void]$driveForm.ShowDialog()
    })

    $btnOpenFolder.Add_Click({
        $desktopPath = [System.Environment]::GetFolderPath("Desktop")
        $lanGamesPath = Join-Path -Path $desktopPath -ChildPath "Lan Games"
        if (-not (Test-Path $lanGamesPath)) { New-Item -Path $lanGamesPath -ItemType Directory -Force | Out-Null }
        Invoke-Item $lanGamesPath
    })

    # Eigene Listen: Whitelist, Blacklist und EXE-Korrekturen als Textdateien (werden bei
    # Bedarf mit Erklärung angelegt und im Editor geöffnet).
    $listMenu = New-Object System.Windows.Forms.ContextMenuStrip
    foreach ($entry in @(
            @{ Text = 'Eigene Whitelist bearbeiten (zusätzliche Spiele)'; Path = $script:PelUserWhitelistPath },
            @{ Text = 'Eigene Blacklist bearbeiten (nie verknüpfen)'; Path = $script:PelUserBlacklistPath },
            @{ Text = 'EXE-Korrekturen bearbeiten (Spiel | richtige .exe)'; Path = $script:PelExeOverridePath })) {
        $mi = New-Object System.Windows.Forms.ToolStripMenuItem($entry.Text)
        $mi.Tag = $entry.Path
        $mi.Add_Click({
            Initialize-PelUserLists
            try { Start-Process -FilePath 'notepad.exe' -ArgumentList "`"$($this.Tag)`"" } catch { }
        })
        [void]$listMenu.Items.Add($mi)
    }
    $btnLists.Add_Click({ $listMenu.Show($btnLists, (New-Object System.Drawing.Point(0, $btnLists.Height))) })

    $btnStartScan.Add_Click({
        $btnStartScan.Enabled = $false
        try {
        $txtLog.Clear()
        $log = { param([string]$t) $txtLog.AppendText($t + "`r`n"); [System.Windows.Forms.Application]::DoEvents() }
        & $log "Starte Scan mit Whitelist, Blacklist, eigenen Listen und EXE-Bewertung ..."
        Initialize-PelUserLists

        $desktopPath = [System.Environment]::GetFolderPath("Desktop")
        $targetDir = Join-Path -Path $desktopPath -ChildPath "Lan Games"
        if (-not (Test-Path $targetDir)) { New-Item -Path $targetDir -ItemType Directory -Force | Out-Null }

        # Alte automatische Verknüpfungen entfernen - aber NUR die, die dieser Scan selbst
        # angelegt hat (Kennung in der Beschreibung). Beim allerersten Scan nach dem Update
        # haben noch keine Verknüpfungen eine Kennung: die bisherigen werden dann nicht
        # gelöscht, sondern in einen Unterordner verschoben (manuell angelegte lassen sich
        # von dort einfach zurückholen).
        $wshScan = New-Object -ComObject WScript.Shell
        $existing = @(Get-ChildItem -LiteralPath $targetDir -Filter '*.lnk' -File -ErrorAction SilentlyContinue)
        $descs = @{}
        $migrated = $false
        foreach ($lnk in $existing) {
            $dsc = ''
            try { $dsc = [string]$wshScan.CreateShortcut($lnk.FullName).Description } catch { }
            $descs[$lnk.FullName] = $dsc
            if ($dsc -like 'Project Earth LAN*') { $migrated = $true }
        }
        if ($migrated) {
            $keptCount = 0
            foreach ($lnk in $existing) {
                if ([string]$descs[$lnk.FullName] -like "$autoDesc*") { Remove-Item -LiteralPath $lnk.FullName -Force -ErrorAction SilentlyContinue }
                else { $keptCount++ }
            }
            if ($keptCount -gt 0) { & $log "$keptCount eigene/manuelle Verknüpfung(en) bleiben erhalten." }
        } elseif ($existing.Count -gt 0) {
            $backupDir = Join-Path $targetDir '_Alte Verknüpfungen (vor Update)'
            if (-not (Test-Path -LiteralPath $backupDir)) { New-Item -Path $backupDir -ItemType Directory -Force | Out-Null }
            foreach ($lnk in $existing) { Move-Item -LiteralPath $lnk.FullName -Destination (Join-Path $backupDir $lnk.Name) -Force -ErrorAction SilentlyContinue }
            & $log "Einmalige Umstellung: $($existing.Count) bisherige Verknüpfung(en) nach '_Alte Verknüpfungen (vor Update)' verschoben."
            & $log "  -> Selbst angelegte von dort einfach zurück in 'Lan Games' ziehen; sie bleiben ab jetzt bei jedem Scan erhalten."
        }

        # --- Whitelist (eingebaut) ----------------------------------------------------
        # Diese Liste darfst du beliebig erweitern (Komma-getrennt) - oder einfacher über
        # "Eigene Listen" -> "Eigene Whitelist". Kurze Einzelwörter (z. B. "Game", "Rust")
        # gelten nur als exakter Name bzw. mit Versionsnummer, längere Einträge als ganze
        # Wörter (siehe Find-PelWhitelistMatch).
        $RawText = @"
0 A.D., 5089: The Action RPG, 7 Days to Die, A.R.S.E.N.A.L Extended Power, Act of Aggression Reboot Edition, Adrenaline,
Age of Empires II HD, Age of Empires III: Complete Collection, Age of Mythology, Age of Wonders, Age of Wonders II: The Wizard's Throne,
Age of Wonders III, Age of Wonders: Shadow Magic, AI War: Fleet Command, Alexander, Alien Swarm, Alien Swarm: Reactive Drop,
Aliens versus Predator 2, Altitude, Anno 1404, Anno 1404: Venice, Anno 1602: Creation of a New World, Anno 1701, Applied Science,
Argo, ARK: Survival Evolved, ARMA 2, ARMA 3, ARMA: Armed Assault, Armagetron Advanced, Army Men, Artemis: Spaceship Bridge Simulator,
Assassin's Creed Revelations, Assault Cube, At A Distance, Atari Deer hunter 2005, Atomic Bomberman, Awesomenauts, Badlands RoadTrip,
Baldur's Gate, Baldur's Gate II: Enhanced Edition, Baldur's Gate II: Shadows of Amn, Baldur's Gate: Enhanced Edition, BallisticNG,
Battleblock Theater, Battlefield 1, Battlefield 1942, Battlefield 2, Battlefield 2142, Battlefield 3, Battlefield 4,
Battlefield Bad Company 2, Battlefield Hardline, Battlefield Vietnam, Battlefleet Gothic: Armada, Battlerite, Battleships Crossfire,
Battlestations: Midway, Battlestations: Pacific, Battlezone II: Combat Commander, Bionic Commando, Bitfighter, BlazeRush, Block N Load,
Blockland, Bloody Good Time, Blur, Boid, Bombsquad, Bontago, Borderlands, Borderlands 2, Borderlands: The Pre-Sequel, Brawlhalla,
Broforce, Build And Shoot, Burnout Paradise: The Ultimate Box, Call of Duty, Call of Duty 2, Call of Duty 4: Modern Warfare,
Call of Duty: Modern Warfare 2, Call of Duty: Modern Warfare 3, Call of Duty: WWII, Call to Arms, Can't Drive This, Carmageddon,
Carmageddon II: Carpocalypse Now, Carmageddon: Max Damage, Carmageddon: Reincarnation, Castle Crashers, Castle Story, Casus Belli,
Chivalry Medieval Warfare, Chrome Trip, Clonk Rage, Code of War, Codename Eagle, Colin McRae Rally 2005, Command & Conquer 3: Tiberium Wars,
Command & Conquer: Generals, Command & Conquer: Generals Zero Hour, Command & Conquer: Red Alert, Command & Conquer: Red Alert 2,
Command & Conquer: Red Alert 3, Command & Conquer: Tiberian Sun, Command & Conquer: Tiberian Sun - Firestorm, Command & Conquer: Yuri's Revenge,
Company of Heroes, Company of Heroes 2, Cortex Command, Counter-Strike, Counter-Strike 2D, Counter-Strike: Global Offensive, Counter-Strike: Source,
Crawl, Crusader Kings 2, Cry of Fear, Crysis Wars, Cube 2: Sauerbraten, Daikatana, Day of Defeat, Dead Frontier, Dead Island, DEFCON,
Defense of the Ancients, Demigod, Descent, Descent 3, Descent II, Desolate, Deus Ex, Diablo, Diablo II, Diablo III, Digital Paintball 2,
Din's Curse, DiRT 3, DiRT 3 Complete Edition, DiRT Rally, Dirty Bomb, Divinity: Original Sin - Enhanced Edition, Don't Starve Together, Doom,
Doom 3, Doom II: Hell on Earth, DotA 2, Duck Game, Duke Nukem 3D: Atomic Edition, Dungeon Defenders, Dungeon Defenders II, Dungeon Keeper,
Dungeon Keeper 2, Dungeon Keeper Gold, Dungeon of the Endless, Dungeon Siege, Dungeon Siege II, Dying Light, Dying Light: The Following, Dystopia,
E.Y.E.: Divine Cybermancy, Emergency 4: Global Fighters for Life, Emperor: Battle for Dune, Empire Earth, Empire Earth 3, Empire Earth Gold Edition,
Empires Mod, Empires: Dawn of The Modern World, Enemy Territory: Quake Wars, E-Racer, Etherlords 2, F.E.A.R., F.E.A.R. Platinum, F1 2013,
F1 Challenge '99-'02, Factorio, Far cry, Far Cry 2, Far Cry 4, Farm Hands, Fear Combat, Feel The Snow, FIFA 08, FIFA 11, FIFA 16, FIFA Football 2002,
Fistful of Frags, Flatout, FlatOut 2, Fortress Forever, Forts, FreeCiv, Freedom Force, Galcon 2: Galactic Conquest, Game Stock Car Extreme, Gang Beasts,
Gang Garrison 2, Garry's mod, Gas Guzzlers Extreme, Gas Guzzlers: Combat Carnage, Gauntlet Slayer Edition, Gears of War, GeneWars, Gimbal,
GoldenEye: Source, Golf With Your Friends, Grand Prix Legends, Grand Theft Auto 2, Grand Theft Auto IV, Grand Theft Auto V, Grim dawn, Gun Bombers,
Guns of Icarus Online, Half-Life, Half-Life 2: Deathmatch, Halo 2 PC, Halo: Combat Evolved, Hammerwatch, HAWKEN, Hedgewars, Helldivers, Heretic,
Heretic II, Heroes of Might and Magic 3, Heroes of Might and Magic IV, Heroes of Might and Magic IV: Complete, Heroes of Might and Magic V,
Heroes of Newerth, Heroes of the Storm, HeXen II, Hexen: Beyond Heretic, Hidden in Plain Sight, Homefront: The Revolution, Homeworld, Homeworld 2,
Homeworld Remastered Collection, Homeworld: Cataclysm, Homeworld: Deserts of Kharak, Impossible Creatures, Insurgency, Insurgency: Modern Infantry Combat,
Jagged Alliance 2, Jamestown: Legend of the Lost Colony, Killing Floor, Killing Floor 2, King Arthur's Gold, League of Legends, Left 4 Dead, Left 4 Dead 2,
Lethal League, Little Fighter 2, Magic 2014 - Duels of the Planeswalkers, Magic 2015 - Duels of the Planeswalkers, Magicka, Magicka 2, Marble Arena 2,
MechWarrior Online, MechWarrior: Living Legends, Might & Magic Heroes VI, Minecraft, Minetest, Mobile Forces, mobile legends, Monaco: What's Yours Is Mine,
Monday Night Combat, Moto Racer, Moto Racer 2, MotoGP 2, Mount & Blade: Warband, Mount Your Friends, Move or Die, Multi Theft Auto: San Andreas,
NASCAR Racing 2003 Season, NASCAR Thunder 2004, Natural Selection, Natural Selection 2, Need for Speed III: Hot Pursuit, Need For Speed Underground 2,
Need for Speed: Hot Pursuit, Need for Speed: Hot Pursuit 2, Need for Speed: Most Wanted, Need for Speed: Shift, Need for Speed: Underground,
NEOTOKYO, Nerf Arena Blast, Neverwinter Nights, Neverwinter Nights 2, Next Car Game: Wreckfest, No One Lives Forever 2, Nox, Nuclear Dawn, One Clone Left,
Open Liero X, Open Red Alert, Open Transport Tycoon Deluxe, OpenArena, OpenRA, OpenSpades, OpenTTD, Orbital Gear, ORION: Prelude, osu!, Outgun, Outlaws,
Outlaws + A Handful of Missions, Overcooked, Overwatch, Paladins: Champions of the Realm, Path of Exile, Pax Imperia: Eminent Domain, Payday 2,
Pirates of the Polygon Sea, Pirates, Vikings and Knights, Pirates, Vikings and Knights II, Plain Sight, Planetary Annihilation, Planetary Annihilation: TITANS,
Plants vs. Zombies: Garden Warfare 2, Port Royale, Port Royale 2, Port Royale 3, Portal 2, Praetorians, Prison Architect, Pro Evolution Soccer 2004,
Pro Evolution Soccer 2016, Project Reality: Battlefield 2, Project Zomboid, PULSAR: Lost Colony, Pure, Quake, Quake 2, Quake II: Quad Damage,
Quake III Arena, Quake III: Gold, Quake Live, Race Driver: Grid, Realm of the Mad God, Red Eclipse, Red Faction, Red Faction: Guerrilla, Renegade X,
Resident Evil 5, Return to Castle Wolfenstein, Re-Volt, Rise of Flight, Rise of Nations, Rise of Nations: Extended Edition, Rise of Nations: Rise of Legends,
Rise of the Triad 2013 (Doom edition), Risk II, Risk of Rain, Robot Roller-Derby Disco Dodgeball, Rocket League, Rome: Total War, Rune Classic,
RUNNING WITH RIFLES, Rust, Sacred 2 Fallen Angel, Sacred 2 Gold, Sacred Citadel, Sacrifice, Saints Row IV, Saints Row: The Third, Salt and Sanctuary,
Samurai Gunn, Sanctum 2, Savage XR, Screencheat, Serious Sam 3: BFE, Serious Sam: The First Encounter, Shaun White Snowboarding, ShootMania Storm,
Sid Meier's Alpha Centauri, Sid Meier's Alpha Centauri Planetary Pack, Sid Meier's Civilization II Gold, Sid Meier's Civilization III, Sid Meier's Civilization IV,
Sid Meier's Civilization V, Sid Meier's Civilization VI, Sins of a Solar Empire, Sins of a Solar Empire: Rebellion, Smite, Smokin' Guns, Sniper Ghost Warior 2,
Soldat, Sonic & All-Stars Racing Transformed, South Park Rally, Space Engineers, Speedrunners, Speedrunners Party Mode, Split/Second, Sportsfriends,
Star Wars Battlefront, Star Wars Jedi Knight II: Jedi Outcast, Star Wars Jedi Knight: Jedi Academy, Star Wars: Battlefront II, Star Wars: Empire at War,
Star Wars: Empire at War: Forces of Corruption, Starbound, StarCraft, StarCraft II: Heart of the Swarm, StarCraft II: Legacy of the Void,
StarCraft II: Starter Edition, StarCraft II: Wings of Liberty, StarCraft: Brood War, Stardew Valley, Starlancer, Startopia, Staxel, Steel Storm, Stellaris,
Stikbold! A Dodgeball Adventure, Strike Vector, Stronghold, Stronghold Crusader, Summoning Wars, Supraball, Supreme Commander, Supreme Commander: Forged Alliance,
Sven Co-op, SWAT 4, SWAT 4: Gold Edition, SWAT 4: The Stetchkov Syndicate, Synergy, System Shock 2, Tabletop Simulator, Team Fortress 2, Team Fortress Classic,
Teeworlds, Terraria, Tesseract, Tetrinet, The Battle for Wesnoth, The Forest, The Guild 2, The Hidden: Source, The Lord of the Rings: The Battle for Middle-earth II,
The Mean Greens - Plastic Warfare, The Red Solstice, The Settlers 2, The Ship: Murder Party, Titan Quest, Titanfall, Tom Clancys Ghost Recon - Advanced Warfighter 2,
Tom Clancy's H.A.W.X, Tom Clancy's Rainbow Six 3: Raven Shield, Tom Clancy's Rainbow Six Siege, Tom Clancy's Rainbow Six: Rogue Spear, Tom Clancy's Rainbow Six: Vegas,
Tom Clancy's Rainbow Six: Vegas 2, Tom Clancy's The Division, Torchlight 2, Total Annihilation: Commander Pack, Total War: Rome II, TowerFall Ascension,
Trackmania Nations Forever, Trackmania Turbo, Tremulous, Tribes 2, Tribes: Ascend, Trine 2: Complete Story, TRON 2.0, UFO2000, Unreal, Unreal Tournament,
Unreal Tournament 2004, Unreal Tournament 3, Unturned, Urban Terror, Vampire: The Masquerade Redemption, Viper Racing, Viscera Cleanup Detail,
Viscera Cleanup Detail: Santa's Rampage, Viscera Cleanup Detail: Shadow Warrior, War of the Roses, Warcraft II: Battle.net Edition, Warcraft II: Tides of Darkness,
Warcraft III: Reign of Chaos, Warcraft III: The Frozen Throne, Warcraft: Orcs and Humans, Warface, Warhammer 40,000: Dawn of War, Warhammer 40,000: Dawn of War - Dark Crusade,
Warhammer 40,000: Dawn of War - Soulstorm, Warhammer 40,000: Dawn of War - Winter Assault, Warhammer 40,000: Dawn of War II, Warhammer: End Times - Vermintide, Warshift,
Warsow, Warzone 2100, Widelands, Windward, Witch it, Wolfenstein: Enemy Territory, World In Conflict, World In Conflict Complete Edition, World in Conflict: Soviet Assault,
World of Tanks, Worms Armageddon, Wreckfest, XCOM 2, XCOM: Enemy Unknown, Xonotic, YSFlight, Yu-Gi-Oh Joey The Passion, Zero Gear, Zero-K, Zombie Panic! Source,OpenCoop,
Zombies Monsters Robots,Game,Black,UT2004,FEARMP,FEARServer
"@
        $ExtraWhitelist = @(
            'Medal of Honor', 'Medal of Honor Allied Assault', 'Call of Duty: United Offensive', 'Call of Duty: World at War', 'Soldier of Fortune II',
            'Starsiege: Tribes', 'Delta Force', 'Operation Flashpoint', 'Arma', 'Ghost Recon', 'Rainbow Six', 'Hidden & Dangerous 2', 'Worms', 'The Settlers',
            'Need for Speed', 'Command & Conquer', 'Red Alert', 'Serious Sam', 'Painkiller', 'Quake 4', "America's Army", 'Tactical Ops', 'Postal 2',
            'Red Orchestra', 'Rising Storm', 'Day of Infamy', 'Deep Rock Galactic', 'Valheim', 'Satisfactory', 'Raft', 'Grounded', 'Lethal Company',
            'Core Keeper', 'Empyrion - Galactic Survival', 'Astroneer', 'Barotrauma', 'DDNet', 'Age of Empires II', 'Age of Empires', 'Stronghold Crusader',
            'Halo', 'Crysis', 'Enemy Territory', 'Heroes of Might and Magic', 'Diablo II', 'Trackmania', 'Unreal Tournament'
        )
        $GameWhitelist = @(@(($RawText -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }) + $ExtraWhitelist + @(Get-PelUserList $script:PelUserWhitelistPath) | Select-Object -Unique)

        # --- Blacklist ------------------------------------------------------------------
        # Begriffe gelten als ganze Wörter/Wortgruppen. Bewusst NICHT mehr als Teilwort:
        # "mod" (traf "Garry's Mod", "Modern Warfare"), "driver" ("Race Driver: Grid"),
        # "flash" ("Operation Flashpoint"), "chrome" ("Chrome Trip"), "clone" ("One Clone
        # Left"), "edge", "client", "update", "windows", "player", "security".
        $NameBlacklist = @(
            # Programme & Werkzeuge
            '7-zip', '7 zip', 'winrar', 'docker', 'jdownloader', 'kodi', 'bandicam', 'total commander', 'sd card formatter',
            'google chrome', 'mozilla firefox', 'firefox', 'microsoft edge', 'opera gx', 'browser', 'java runtime', 'java se', 'java update', 'java tm',
            'adobe flash', 'flash player', 'visual c++', 'visual c', 'runtime', 'redistributable', 'redistributables', 'codec', 'codec pack', 'media player',
            'vlc', 'messenger', 'zerotier', 'hamachi', 'radmin vpn', 'tailscale', 'registry', 'sdk', 'plugin', 'nvidia', 'geforce', 'amd software',
            'amd chipset', 'radeon software', 'intel', 'realtek', 'windows sdk', 'windows kits', 'windows driver', 'microsoft office', 'office', 'net framework',
            'dotnet', 'antivirus', 'discord', 'microsoft teams', 'teams', 'zoom', 'skype', 'spotify', 'virtualbox', 'vmware', 'notepad', 'ccleaner',
            'helper', 'driver booster', 'drivers', 'worldbuilder', 'world builder', 'level editor', 'editor', 'unrealed', 'unreal engine', 'testapp',
            'mod organizer', 'mod manager', 'clonezilla', 'macrium',
            # Launcher & Plattformen
            'epic games launcher', 'ubisoft connect', 'ubisoft game launcher', 'uplay', 'rockstar games launcher', 'ea app', 'gog galaxy', 'battle net',
            'xbox', 'game bar', 'gameinput', 'gaming services', 'geforce experience', 'razer', 'logitech', 'corsair', 'msi afterburner', 'rivatuner',
            'cheat engine', 'wemod', 'overwolf', 'curseforge', 'teamspeak', 'mumble', 'obs studio', 'streamlabs', 'reshade',
            # Keine Spiele in Steam-/Epic-Bibliotheken
            'steamworks shared', 'steamvr', 'steam controller configs', 'steam linux runtime', 'proton', 'wallpaper engine', 'soundtrack', 'ost',
            'original soundtrack', 'artbook', 'art book', 'dedicated server', 'server', 'authoring tools', 'tools', 'tool', 'benchmark', '3dmark',
            'spacewar', 'source filmmaker', 'blender', 'soundpad', 'lossless scaling', 'rpg maker', 'aseprite', 'voicemod', 'fps monitor',
            'bonus content', 'digital extras', 'deluxe content', 'source sdk'
        ) + @(Get-PelUserList $script:PelUserBlacklistPath)
        $NameBlacklistExact = @('Steam', 'Origin', 'Java', 'Vortex', 'Launcher', 'Tools', 'Redist', 'Setup', 'Installer', 'Uninstall', 'Support', 'Engine', 'Common')

        $AllDiscoveredGames = New-Object System.Collections.Generic.List[object]

        # Steam: Bibliotheken + App-Manifeste (liefern den echten Spielnamen und die App-ID)
        $steamRoot = $null
        try { $steamRoot = (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -Name "InstallPath" -ErrorAction Stop).InstallPath } catch { }
        if (-not $steamRoot) { try { $steamRoot = ((Get-ItemProperty "HKCU:\Software\Valve\Steam" -ErrorAction Stop).SteamPath) -replace '/', '\' } catch { } }
        $steamExe = $null
        if ($steamRoot) {
            $se = Join-Path $steamRoot 'steam.exe'
            if (Test-Path -LiteralPath $se) { $steamExe = $se }
            $steamLibs = @((Join-Path $steamRoot "steamapps"))
            $vdfPath = Join-Path $steamRoot "steamapps\libraryfolders.vdf"
            if (Test-Path $vdfPath) {
                foreach ($line in @(Get-Content $vdfPath -ErrorAction SilentlyContinue)) {
                    if ($line -match '"path"\s+"([^"]+)"') { $steamLibs += Join-Path ($matches[1] -replace '\\\\', '\') "steamapps" }
                }
            }
            foreach ($lib in @($steamLibs | Select-Object -Unique)) {
                $commonPath = Join-Path $lib "common"
                if (-not (Test-Path $commonPath)) { continue }
                $manifest = @{}
                foreach ($acf in @(Get-ChildItem -LiteralPath $lib -Filter 'appmanifest_*.acf' -File -ErrorAction SilentlyContinue)) {
                    try {
                        $t = [System.IO.File]::ReadAllText($acf.FullName)
                        $inst = [regex]::Match($t, '"installdir"\s+"([^"]*)"').Groups[1].Value
                        if ($inst) {
                            $manifest[$inst.ToLowerInvariant()] = [pscustomobject]@{
                                AppId = [regex]::Match($t, '"appid"\s+"(\d+)"').Groups[1].Value
                                Name  = [regex]::Match($t, '"name"\s+"([^"]*)"').Groups[1].Value
                            }
                        }
                    } catch { }
                }
                foreach ($sg in @(Get-ChildItem -Path $commonPath -Directory -Force -ErrorAction SilentlyContinue)) {
                    $mf = $manifest[$sg.Name.ToLowerInvariant()]
                    $nm = $sg.Name
                    $appId = ''
                    if ($mf) { if ($mf.Name) { $nm = $mf.Name }; $appId = $mf.AppId }
                    $AllDiscoveredGames.Add([PSCustomObject]@{ Name = $nm; Path = $sg.FullName; Source = "Steam"; AppId = $appId; KnownExe = '' })
                }
            }
        }

        # Epic: das Manifest nennt die Start-EXE selbst ("LaunchExecutable") - die ist
        # verlässlicher als jede Suche.
        $epicManifestPath = "C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests"
        if (Test-Path $epicManifestPath) {
            foreach ($file in (Get-ChildItem -Path $epicManifestPath -Filter "*.item" -Force -ErrorAction SilentlyContinue)) {
                try {
                    $json = Read-PelTextFile $file.FullName | ConvertFrom-Json
                    if ($null -ne $json.DisplayName -and $null -ne $json.InstallLocation) {
                        $ke = ''
                        if ($json.LaunchExecutable) { $cand = Join-Path $json.InstallLocation $json.LaunchExecutable; if (Test-Path -LiteralPath $cand) { $ke = $cand } }
                        $AllDiscoveredGames.Add([PSCustomObject]@{ Name = $json.DisplayName; Path = $json.InstallLocation; Source = "Epic"; AppId = ''; KnownExe = $ke })
                    }
                } catch { }
            }
        }

        foreach ($install in (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Ubisoft\Launcher\Installs\*" -ErrorAction SilentlyContinue)) {
            if ($null -ne $install.InstallDir) {
                $AllDiscoveredGames.Add([PSCustomObject]@{ Name = (Split-Path $install.InstallDir -Leaf); Path = $install.InstallDir; Source = "Ubisoft"; AppId = ''; KnownExe = '' })
            }
        }
        # GOG: der Registry-Eintrag nennt die Spiel-EXE ebenfalls direkt ("exe")
        foreach ($install in (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games\*" -ErrorAction SilentlyContinue)) {
            if ($null -ne $install.GAMENAME -and $null -ne $install.path) {
                $ke = ''
                if ($install.exe -and (Test-Path -LiteralPath ([string]$install.exe))) { $ke = [string]$install.exe }
                $AllDiscoveredGames.Add([PSCustomObject]@{ Name = $install.GAMENAME; Path = $install.path; Source = "GOG"; AppId = ''; KnownExe = $ke })
            }
        }
        foreach ($install in (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Origin Games\*" -ErrorAction SilentlyContinue)) {
            if ($null -ne $install.DisplayName -and $null -ne $install.InstallDir) {
                $AllDiscoveredGames.Add([PSCustomObject]@{ Name = $install.DisplayName; Path = $install.InstallDir; Source = "EA App"; AppId = ''; KnownExe = '' })
            }
        }

        foreach ($drive in $global:SelectedDrives) {
            foreach ($dir in @((Join-Path $drive "Games"), (Join-Path $drive "Spiele"), (Join-Path $drive "Program Files\ElAmigos"), (Join-Path $drive "Program Files (x86)\ElAmigos"))) {
                if (Test-Path $dir) {
                    foreach ($sd in (Get-ChildItem -Path $dir -Directory -Force -ErrorAction SilentlyContinue)) {
                        $AllDiscoveredGames.Add([PSCustomObject]@{ Name = $sd.Name; Path = $sd.FullName; Source = "CustomDir"; AppId = ''; KnownExe = '' })
                    }
                }
            }
        }

        $regPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        foreach ($app in (Get-ItemProperty $regPaths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -and $_.InstallLocation })) {
            $AllDiscoveredGames.Add([PSCustomObject]@{ Name = $app.DisplayName; Path = $app.InstallLocation; Source = "Registry"; AppId = ''; KnownExe = '' })
        }

        # EXE-Korrekturen: gelten für gefundene Spiele und werden zusätzlich als eigene
        # Einträge übernommen (auch wenn der Scan das Spiel selbst nicht findet).
        $overrides = @{}
        foreach ($ov in @(Get-PelExeOverrides)) {
            $overrides[$ov.Key] = $ov
            if (Test-Path -LiteralPath $ov.Path) {
                $AllDiscoveredGames.Add([PSCustomObject]@{ Name = $ov.Name; Path = [System.IO.Path]::GetDirectoryName($ov.Path); Source = "Eigene Liste"; AppId = ''; KnownExe = $ov.Path })
            } else {
                & $log "[Eigene Liste] EXE nicht gefunden, übersprungen: $($ov.Name) -> $($ov.Path)"
            }
        }

        & $log "Gefunden: $($AllDiscoveredGames.Count) Einträge - wende Filter an und wähle die Spiel-EXE ..."

        $storeSources = @('Steam', 'Epic', 'Ubisoft', 'GOG', 'EA App', 'Eigene Liste')
        $gamesCount = 0
        $processedPaths = @{}
        $processedNames = @{}
        $skipBlack = New-Object System.Collections.Generic.List[string]
        $skipNoExe = New-Object System.Collections.Generic.List[string]
        $skipUnsafe = 0
        $skipNotWhite = 0

        # Eigene Liste zuerst (hat Vorrang), dann die Stores, dann Registry/Ordner
        $order = @{ 'Eigene Liste' = 0; 'Steam' = 1; 'Epic' = 1; 'GOG' = 1; 'Ubisoft' = 1; 'EA App' = 1; 'CustomDir' = 2; 'Registry' = 3 }
        foreach ($gameObj in @($AllDiscoveredGames | Sort-Object @{ Expression = { $order[[string]$_.Source] } })) {
            if ([string]::IsNullOrWhiteSpace($gameObj.Path) -or [string]::IsNullOrWhiteSpace($gameObj.Name)) { continue }
            $cleanPath = ([string]$gameObj.Path).Trim().Trim('"').TrimEnd('\')
            $pathKey = $cleanPath.ToLowerInvariant()
            $nameKey = ConvertTo-PelMatchText $gameObj.Name
            if ($processedPaths.ContainsKey($pathKey) -or $processedNames.ContainsKey($nameKey)) { continue }

            if ($gameObj.Source -ne 'Eigene Liste') {
                $bad = Find-PelBlacklistMatch -Name $gameObj.Name -Phrases $NameBlacklist -ExactNames $NameBlacklistExact
                if ($bad) { if ($gameObj.Source -in $storeSources) { $skipBlack.Add("$($gameObj.Name) ($bad)") }; continue }
                if ($gameObj.Source -notin $storeSources) {
                    if (-not (Find-PelWhitelistMatch -Name $gameObj.Name -Entries $GameWhitelist)) { $skipNotWhite++; continue }
                }
                if (Test-PelUnsafeGameRoot $cleanPath) { $skipUnsafe++; continue }
            }

            $driveMatch = $false
            foreach ($drive in $global:SelectedDrives) {
                if ($cleanPath.StartsWith([string]$drive, [System.StringComparison]::OrdinalIgnoreCase)) { $driveMatch = $true; break }
            }
            if (-not $driveMatch) { continue }
            if (-not (Test-Path -LiteralPath $cleanPath)) { continue }

            # Spiel-EXE bestimmen: eigene Korrektur > Angabe des Stores > Bewertung
            $exePath = $null
            $why = ''
            $ov = $overrides[$nameKey]
            if ($ov -and (Test-Path -LiteralPath $ov.Path)) { $exePath = $ov.Path; $why = 'eigene Korrektur' }
            elseif ($gameObj.KnownExe -and ([System.IO.Path]::GetFileNameWithoutExtension([string]$gameObj.KnownExe) -notmatch $script:PelExeExcludeNames)) {
                $exePath = [string]$gameObj.KnownExe; $why = "Angabe von $($gameObj.Source)"
            } else {
                $sel = Select-PelGameExe -Folder $cleanPath -GameName $gameObj.Name
                if ($sel) { $exePath = $sel.Path; $why = $sel.Reason }
            }
            if (-not $exePath) {
                if ($gameObj.Source -in $storeSources) { $skipNoExe.Add([string]$gameObj.Name) }
                continue
            }

            $rel = $exePath
            if ($exePath.StartsWith($cleanPath, [System.StringComparison]::OrdinalIgnoreCase)) { $rel = $exePath.Substring($cleanPath.Length).TrimStart('\') }
            try {
                if ($gameObj.Source -eq 'Steam' -and $gameObj.AppId -and $steamExe -and $why -ne 'eigene Korrektur') {
                    # Steam-Spiele über Steam starten (-applaunch): Steam setzt dabei alle
                    # nötigen Startparameter (z. B. "-game cstrike" bei Source-Spielen,
                    # Anticheat, DRM) - die ausgewählte EXE dient als Symbol und für die
                    # Spielerkennung/Mitspielen (steht in der Beschreibung).
                    New-GameShortcut -SourcePath $steamExe -Arguments "-applaunch $($gameObj.AppId)" -GameExe $exePath -DestinationFolder $targetDir -ShortcutName $gameObj.Name -Description "$autoDesc | exe=$exePath"
                    & $log "[Steam] $($gameObj.Name)  ->  über Steam (App $($gameObj.AppId)), EXE: $rel ($why)"
                } else {
                    New-GameShortcut -SourcePath $exePath -DestinationFolder $targetDir -ShortcutName $gameObj.Name -Description $autoDesc
                    & $log "[$($gameObj.Source)] $($gameObj.Name)  ->  $rel ($why)"
                }
                $processedPaths[$pathKey] = $true
                $processedNames[$nameKey] = $true
                $gamesCount++
            } catch {
                & $log "[$($gameObj.Source)] FEHLER bei $($gameObj.Name): $($_.Exception.Message)"
            }
        }

        & $log ""
        & $log "Fertig! Es wurden $gamesCount LAN-Spiele verknüpft."
        if ($skipBlack.Count -gt 0) { & $log "Ausgelassen (Blacklist, keine Spiele): $($skipBlack -join '; ')" }
        if ($skipNoExe.Count -gt 0) { & $log "Ausgelassen (keine passende Spiel-EXE gefunden): $($skipNoExe -join '; ')" }
        & $log "Nicht auf der Whitelist (Registry/Spieleordner): $skipNotWhite  |  Sammelordner übersprungen: $skipUnsafe"
        & $log "Falsche EXE oder fehlendes Spiel? -> 'Eigene Listen' (EXE-Korrekturen / Whitelist / Blacklist) und neu scannen."
        } finally {
            $btnStartScan.Enabled = $true
        }
    })

    [void]$form.ShowDialog()
}

# ------------------------------------------------------------------------------
# OPTION 8: Manuelle Game Suche (dynamisch, systemweit, inkl. versteckter Dateien)
# ------------------------------------------------------------------------------
function Invoke-ManualGameSearch {
    # C#-Suchmotor: läuft in einem Hintergrund-Thread, die GUI bleibt bedienbar.
    # Durchsucht alle Laufwerke inkl. versteckter Dateien/Ordner und Systemdateien
    # (das Skript läuft dank Start-Prüfung immer mit Administratorrechten).
    if (-not ('EarthFileSearcher' -as [type])) {
        $searcherCode = @'
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Threading;

public class EarthSearchHit
{
    public string FullPath;
    public bool IsDirectory;
    public bool IsHidden;
}

public class EarthFileSearcher
{
    public ConcurrentQueue<EarthSearchHit> Hits = new ConcurrentQueue<EarthSearchHit>();
    public volatile bool CancelRequested;
    public volatile bool Finished;
    public volatile bool LimitReached;
    public volatile string CurrentDir = "";
    public int HitCount;
    public int ScannedCount;
    public int MaxHits = 1000;

    private string[] roots;
    private string[] words;
    private bool allTypes;
    private bool skipWindows;
    private string windowsDir;
    private Thread worker;

    public EarthFileSearcher(string[] roots, string[] words, bool allTypes, bool skipWindows)
    {
        this.roots = roots;
        this.words = words;
        this.allTypes = allTypes;
        this.skipWindows = skipWindows;
        string sr = Environment.GetEnvironmentVariable("SystemRoot");
        this.windowsDir = (sr == null) ? "" : sr.TrimEnd('\\');
    }

    public void Start()
    {
        worker = new Thread(new ThreadStart(Run));
        worker.IsBackground = true;
        worker.Start();
    }

    public void Cancel()
    {
        CancelRequested = true;
    }

    private void Run()
    {
        try
        {
            foreach (string root in roots)
            {
                if (CancelRequested || LimitReached) break;
                Walk(root);
            }
        }
        catch (Exception) { }
        Finished = true;
    }

    private bool Matches(string name)
    {
        for (int i = 0; i < words.Length; i++)
        {
            if (name.IndexOf(words[i], StringComparison.OrdinalIgnoreCase) < 0) return false;
        }
        return true;
    }

    private bool ShouldSkipDescent(string fullName, string name)
    {
        if (name.Equals("$Recycle.Bin", StringComparison.OrdinalIgnoreCase)) return true;
        if (name.Equals("System Volume Information", StringComparison.OrdinalIgnoreCase)) return true;
        if (skipWindows && windowsDir.Length > 0 &&
            string.Equals(fullName.TrimEnd('\\'), windowsDir, StringComparison.OrdinalIgnoreCase)) return true;
        return false;
    }

    private void AddHit(FileSystemInfo fi, bool isDir)
    {
        EarthSearchHit h = new EarthSearchHit();
        h.FullPath = fi.FullName;
        h.IsDirectory = isDir;
        h.IsHidden = (fi.Attributes & (FileAttributes.Hidden | FileAttributes.System)) != 0;
        Hits.Enqueue(h);
        HitCount++;
        if (HitCount >= MaxHits) LimitReached = true;
    }

    private void Walk(string root)
    {
        Stack<string> stack = new Stack<string>();
        stack.Push(root);

        while (stack.Count > 0)
        {
            if (CancelRequested || LimitReached) return;

            string dir = stack.Pop();
            CurrentDir = dir;

            IEnumerable<FileSystemInfo> entries;
            try
            {
                entries = new DirectoryInfo(dir).EnumerateFileSystemInfos();
            }
            catch (Exception)
            {
                continue;
            }

            try
            {
                foreach (FileSystemInfo fi in entries)
                {
                    if (CancelRequested || LimitReached) return;
                    ScannedCount++;

                    string name = fi.Name;
                    bool isDir = (fi.Attributes & FileAttributes.Directory) == FileAttributes.Directory;

                    if (isDir)
                    {
                        if (Matches(name)) AddHit(fi, true);

                        bool isReparse = (fi.Attributes & FileAttributes.ReparsePoint) == FileAttributes.ReparsePoint;
                        if (!isReparse && !ShouldSkipDescent(fi.FullName, name))
                        {
                            stack.Push(fi.FullName);
                        }
                    }
                    else
                    {
                        if ((allTypes || name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) && Matches(name))
                        {
                            AddHit(fi, false);
                        }
                    }
                }
            }
            catch (Exception)
            {
                // Zugriff verweigert o.ä. -> nächstes Verzeichnis
            }
        }
    }
}
'@
        Add-Type -TypeDefinition $searcherCode -Language CSharp
    }

    $state = @{ Searcher = $null }

    # --- Hilfsfunktionen -------------------------------------------------------
    function Get-LanGamesFolder {
        $desktopPath = [System.Environment]::GetFolderPath("Desktop")
        $path = Join-Path -Path $desktopPath -ChildPath "Lan Games"
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -Path $path -ItemType Directory -Force | Out-Null
        }
        return $path
    }

    # Haupt-EXE im gewählten Ordner: dieselbe Bewertung wie der LAN Game Finder (Option 7)
    # statt "größte Datei" - siehe Select-PelGameExe.
    function Find-MainExe {
        param ([string]$FolderPath)
        $sel = Select-PelGameExe -Folder $FolderPath -GameName ([System.IO.Path]::GetFileName($FolderPath.TrimEnd('\')))
        if ($sel) { return $sel.Path }
        return $null
    }

    function New-LanShortcut {
        param ([string]$TargetPath, [string]$DestinationFolder, [string]$ShortcutName, [string]$WorkingDirectory)
        $cleanName = ($ShortcutName -replace '[\\/:*?"<>|]', '').Trim()
        if ([string]::IsNullOrWhiteSpace($cleanName)) { $cleanName = "Spiel" }

        $wsh = New-Object -ComObject WScript.Shell
        $shortcutPath = Join-Path -Path $DestinationFolder -ChildPath "$cleanName.lnk"
        $counter = 2
        while (Test-Path -LiteralPath $shortcutPath) {
            $existing = $wsh.CreateShortcut($shortcutPath)
            if ($existing.TargetPath -ieq $TargetPath) { return "vorhanden" }
            $shortcutPath = Join-Path -Path $DestinationFolder -ChildPath "$cleanName ($counter).lnk"
            $counter++
        }
        $sc = $wsh.CreateShortcut($shortcutPath)
        $sc.TargetPath = $TargetPath
        $sc.WorkingDirectory = $WorkingDirectory
        # Kennung: manuell angelegt -> wird vom LAN Game Finder (Option 7) nie gelöscht
        $sc.Description = 'Project Earth LAN - manuell (Option 8)'
        $sc.Save()
        return "erstellt"
    }

    # --- GUI -------------------------------------------------------------------
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Manuelle Game Suche"
    $form.Size = New-Object System.Drawing.Size(900, 640)
    $form.MinimumSize = New-Object System.Drawing.Size(760, 520)
    $form.StartPosition = "CenterParent"
    $form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $form.ForeColor = [System.Drawing.Color]::White

    $fontMain = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Regular)
    $fontBold = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

    $lblSearch = New-Object System.Windows.Forms.Label
    $lblSearch.Text = "Spielname:"
    $lblSearch.Location = New-Object System.Drawing.Point(20, 20)
    $lblSearch.Size = New-Object System.Drawing.Size(80, 22)
    $lblSearch.ForeColor = [System.Drawing.Color]::White
    $lblSearch.Font = $fontBold

    $txtSearch = New-Object System.Windows.Forms.TextBox
    $txtSearch.Location = New-Object System.Drawing.Point(105, 17)
    $txtSearch.Size = New-Object System.Drawing.Size(490, 26)
    $txtSearch.BackColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
    $txtSearch.ForeColor = [System.Drawing.Color]::White
    $txtSearch.Font = $fontMain
    $txtSearch.Anchor = "Top,Left,Right"

    $btnSearch = New-Object System.Windows.Forms.Button
    $btnSearch.Text = "Suchen"
    $btnSearch.Location = New-Object System.Drawing.Point(605, 14)
    $btnSearch.Size = New-Object System.Drawing.Size(120, 30)
    $btnSearch.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnSearch.ForeColor = [System.Drawing.Color]::White
    $btnSearch.FlatStyle = "Flat"
    $btnSearch.Font = $fontBold
    $btnSearch.Anchor = "Top,Right"

    $btnStop = New-Object System.Windows.Forms.Button
    $btnStop.Text = "Stopp"
    $btnStop.Location = New-Object System.Drawing.Point(735, 14)
    $btnStop.Size = New-Object System.Drawing.Size(125, 30)
    $btnStop.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $btnStop.ForeColor = [System.Drawing.Color]::White
    $btnStop.FlatStyle = "Flat"
    $btnStop.Font = $fontMain
    $btnStop.Anchor = "Top,Right"

    $chkAllTypes = New-Object System.Windows.Forms.CheckBox
    $chkAllTypes.Text = "Alle Dateitypen anzeigen (nicht nur .exe)"
    $chkAllTypes.Location = New-Object System.Drawing.Point(105, 52)
    $chkAllTypes.Size = New-Object System.Drawing.Size(320, 24)
    $chkAllTypes.ForeColor = [System.Drawing.Color]::White
    $chkAllTypes.Font = $fontMain

    $chkSkipWindows = New-Object System.Windows.Forms.CheckBox
    $chkSkipWindows.Text = "Windows-Ordner überspringen (schneller)"
    $chkSkipWindows.Checked = $true
    $chkSkipWindows.Location = New-Object System.Drawing.Point(440, 52)
    $chkSkipWindows.Size = New-Object System.Drawing.Size(340, 24)
    $chkSkipWindows.ForeColor = [System.Drawing.Color]::White
    $chkSkipWindows.Font = $fontMain

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text = "Suchbegriff eingeben - die Suche startet automatisch (mind. 2 Zeichen)."
    $lblStatus.Location = New-Object System.Drawing.Point(20, 84)
    $lblStatus.Size = New-Object System.Drawing.Size(840, 22)
    $lblStatus.ForeColor = [System.Drawing.Color]::LightGray
    $lblStatus.Font = $fontMain
    $lblStatus.Anchor = "Top,Left,Right"

    $listView = New-Object System.Windows.Forms.ListView
    $listView.Location = New-Object System.Drawing.Point(20, 112)
    $listView.Size = New-Object System.Drawing.Size(840, 390)
    $listView.View = "Details"
    $listView.FullRowSelect = $true
    $listView.MultiSelect = $true
    $listView.HideSelection = $false
    $listView.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
    $listView.ForeColor = [System.Drawing.Color]::White
    $listView.BorderStyle = "FixedSingle"
    $listView.Font = New-Object System.Drawing.Font("Consolas", 9)
    $listView.Anchor = "Top,Bottom,Left,Right"
    [void]$listView.Columns.Add("Name", 230)
    [void]$listView.Columns.Add("Typ", 70)
    [void]$listView.Columns.Add("Versteckt", 75)
    [void]$listView.Columns.Add("Pfad", 440)

    $btnOpen = New-Object System.Windows.Forms.Button
    $btnOpen.Text = "1. Verzeichnis öffnen"
    $btnOpen.Location = New-Object System.Drawing.Point(20, 515)
    $btnOpen.Size = New-Object System.Drawing.Size(410, 42)
    $btnOpen.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $btnOpen.ForeColor = [System.Drawing.Color]::White
    $btnOpen.FlatStyle = "Flat"
    $btnOpen.Font = $fontBold
    $btnOpen.Anchor = "Bottom,Left"

    $btnShortcut = New-Object System.Windows.Forms.Button
    $btnShortcut.Text = "2. Verknüpfung in 'Lan Games' erstellen"
    $btnShortcut.Location = New-Object System.Drawing.Point(450, 515)
    $btnShortcut.Size = New-Object System.Drawing.Size(410, 42)
    $btnShortcut.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnShortcut.ForeColor = [System.Drawing.Color]::White
    $btnShortcut.FlatStyle = "Flat"
    $btnShortcut.Font = $fontBold
    $btnShortcut.Anchor = "Bottom,Right"

    foreach ($ctrl in @($lblSearch, $txtSearch, $btnSearch, $btnStop, $chkAllTypes, $chkSkipWindows, $lblStatus, $listView, $btnOpen, $btnShortcut)) {
        $form.Controls.Add($ctrl)
    }

    # Timer: Verzögerung nach dem Tippen (dynamische Suche)
    $debounceTimer = New-Object System.Windows.Forms.Timer
    $debounceTimer.Interval = 600

    # Timer: Treffer aus dem Hintergrund-Thread in die Liste übernehmen
    $pollTimer = New-Object System.Windows.Forms.Timer
    $pollTimer.Interval = 150

    # --- Suche starten ---------------------------------------------------------
    function Start-ManualSearch {
        $debounceTimer.Stop()
        $pollTimer.Stop()
        if ($null -ne $state.Searcher) { $state.Searcher.Cancel() }
        $state.Searcher = $null
        $listView.Items.Clear()

        $text = $txtSearch.Text.Trim()
        if ($text.Length -lt 2) {
            $lblStatus.Text = "Suchbegriff eingeben - die Suche startet automatisch (mind. 2 Zeichen)."
            return
        }

        $words = [string[]]@($text -split '\s+' | Where-Object { $_ })
        $roots = [string[]]@(
            [System.IO.DriveInfo]::GetDrives() |
                Where-Object { $_.IsReady -and ($_.DriveType -eq 'Fixed' -or $_.DriveType -eq 'Removable') } |
                ForEach-Object { $_.RootDirectory.FullName }
        )
        if ($roots.Count -eq 0) {
            $lblStatus.Text = "Keine durchsuchbaren Laufwerke gefunden."
            return
        }

        $searcher = [EarthFileSearcher]::new($roots, $words, [bool]$chkAllTypes.Checked, [bool]$chkSkipWindows.Checked)
        $state.Searcher = $searcher
        $lblStatus.Text = "Suche läuft..."
        $searcher.Start()
        $pollTimer.Start()
    }

    $debounceTimer.Add_Tick({ Start-ManualSearch })

    $pollTimer.Add_Tick({
        $s = $state.Searcher
        if ($null -eq $s) { $pollTimer.Stop(); return }

        $hit = $null
        $added = 0
        $listView.BeginUpdate()
        while ($added -lt 200 -and $s.Hits.TryDequeue([ref]$hit)) {
            $li = New-Object System.Windows.Forms.ListViewItem([System.IO.Path]::GetFileName($hit.FullPath))
            [void]$li.SubItems.Add($(if ($hit.IsDirectory) { "Ordner" } else { "Datei" }))
            [void]$li.SubItems.Add($(if ($hit.IsHidden) { "Ja" } else { "" }))
            [void]$li.SubItems.Add($hit.FullPath)
            $li.Tag = $hit
            [void]$listView.Items.Add($li)
            $added++
        }
        $listView.EndUpdate()

        if ($s.Finished -and $s.Hits.IsEmpty) {
            $pollTimer.Stop()
            if ($s.LimitReached) {
                $lblStatus.Text = "Limit von $($s.MaxHits) Treffern erreicht - bitte Suchbegriff eingrenzen."
            } else {
                $lblStatus.Text = "Fertig: $($listView.Items.Count) Treffer ($($s.ScannedCount) Einträge durchsucht)."
            }
        } else {
            $cur = [string]$s.CurrentDir
            if ($cur.Length -gt 80) { $cur = $cur.Substring(0, 77) + "..." }
            $lblStatus.Text = "Suche läuft... $($listView.Items.Count) Treffer | $($s.ScannedCount) Einträge | $cur"
        }
    })

    # --- Ereignisse ------------------------------------------------------------
    $txtSearch.Add_TextChanged({
        $debounceTimer.Stop()
        $debounceTimer.Start()
    })

    $txtSearch.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            $_.SuppressKeyPress = $true
            Start-ManualSearch
        }
    })

    $chkAllTypes.Add_CheckedChanged({ if ($txtSearch.Text.Trim().Length -ge 2) { $debounceTimer.Stop(); $debounceTimer.Start() } })
    $chkSkipWindows.Add_CheckedChanged({ if ($txtSearch.Text.Trim().Length -ge 2) { $debounceTimer.Stop(); $debounceTimer.Start() } })

    $btnSearch.Add_Click({ Start-ManualSearch })

    $btnStop.Add_Click({
        $debounceTimer.Stop()
        $pollTimer.Stop()
        if ($null -ne $state.Searcher) {
            $state.Searcher.Cancel()
            $lblStatus.Text = "Suche abgebrochen: $($listView.Items.Count) Treffer."
        }
    })

    # Option 1: Verzeichnis öffnen (bei Dateien wird die Datei im Explorer markiert)
    $btnOpen.Add_Click({
        $sel = @($listView.SelectedItems)
        if ($sel.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Bitte zuerst einen Treffer in der Liste auswählen.", "Hinweis", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            return
        }
        if ($sel.Count -gt 5) {
            $answer = [System.Windows.Forms.MessageBox]::Show("Es sind $($sel.Count) Treffer ausgewählt. Wirklich $($sel.Count) Explorer-Fenster öffnen?", "Bestätigung", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        }
        foreach ($item in $sel) {
            $hit = $item.Tag
            try {
                if ($hit.IsDirectory) {
                    Start-Process explorer.exe -ArgumentList "`"$($hit.FullPath)`""
                } else {
                    Start-Process explorer.exe -ArgumentList "/select,`"$($hit.FullPath)`""
                }
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Verzeichnis konnte nicht geöffnet werden:`n$($hit.FullPath)`n$($_.Exception.Message)", "Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            }
        }
    })

    $listView.Add_DoubleClick({ $btnOpen.PerformClick() })

    # Option 2: Verknüpfung direkt in 'Lan Games' (Desktop) erstellen, Ordner wird bei Bedarf angelegt
    $btnShortcut.Add_Click({
        $sel = @($listView.SelectedItems)
        if ($sel.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Bitte zuerst einen Treffer in der Liste auswählen.", "Hinweis", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            return
        }

        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        $report = [System.Collections.Generic.List[string]]::new()
        $created = 0
        try {
            $lanFolder = Get-LanGamesFolder

            foreach ($item in $sel) {
                $hit = $item.Tag
                try {
                    if ($hit.IsDirectory) {
                        if (Test-PelUnsafeGameRoot $hit.FullPath) {
                            $report.Add("Übersprungen (Sammelordner, bitte den Spielordner selbst wählen): $($hit.FullPath)")
                            continue
                        }
                        $lblStatus.Text = "Suche Haupt-EXE in: $($hit.FullPath)"
                        [System.Windows.Forms.Application]::DoEvents()
                        $exe = Find-MainExe -FolderPath $hit.FullPath
                        $name = [System.IO.Path]::GetFileName($hit.FullPath)
                        if ($exe) {
                            $targetPath = $exe
                            $workDir = [System.IO.Path]::GetDirectoryName($exe)
                        } else {
                            $targetPath = $hit.FullPath
                            $workDir = $hit.FullPath
                            $report.Add("Keine EXE gefunden - Verknüpfung zeigt auf den Ordner: $name")
                        }
                    } else {
                        $targetPath = $hit.FullPath
                        $workDir = [System.IO.Path]::GetDirectoryName($hit.FullPath)
                        $name = [System.IO.Path]::GetFileNameWithoutExtension($hit.FullPath)
                    }

                    $result = New-LanShortcut -TargetPath $targetPath -DestinationFolder $lanFolder -ShortcutName $name -WorkingDirectory $workDir
                    if ($result -eq "erstellt") { $created++ }
                    else { $report.Add("Bereits vorhanden: $name") }
                } catch {
                    $report.Add("Fehler bei $($hit.FullPath): $($_.Exception.Message)")
                }
            }
        } finally {
            $form.Cursor = [System.Windows.Forms.Cursors]::Default
        }

        $lblStatus.Text = "$created Verknüpfung(en) in '$lanFolder' erstellt."
        $msg = "$created Verknüpfung(en) wurden im Ordner 'Lan Games' erstellt:`n$lanFolder"
        if ($report.Count -gt 0) { $msg += "`n`n" + ($report -join "`n") }
        [System.Windows.Forms.MessageBox]::Show($msg, "Verknüpfung erstellen", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    })

    $form.Add_Shown({ $txtSearch.Focus() })

    $form.Add_FormClosing({
        $debounceTimer.Stop()
        $pollTimer.Stop()
        if ($null -ne $state.Searcher) { $state.Searcher.Cancel() }
    })

    [void]$form.ShowDialog()

    $debounceTimer.Dispose()
    $pollTimer.Dispose()
}

# ------------------------------------------------------------------------------
# OPTION 9: Server-Manager & Game Server Browser (Manager-Verbund Port 9872)
# ------------------------------------------------------------------------------
function Invoke-ServerManagerBrowser {

    # --- C#-Netzwerkkern (Scanner, P2P-Knoten) -----------------------------------
    if (-not ('EarthLanNode' -as [type])) {
        $netCode = @'
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

public class EarthServerHit
{
    public string Ip = "";
    public int Port;
    public string Protocol = "";
    public string Game = "";
    public string Folder = "";
    public string Key = "";
    public string Info = "";
    public string Source = "";
    public int Seen;
    // Tatsächlicher Spiel-/Verbindungsport, falls er vom Abfrageport abweicht (GameSpy
    // "hostport", A2S-EDF-Port). 0 = unbekannt bzw. identisch mit Port.
    public int JoinPort;
}

public static class EarthNet
{
    public static uint ToUInt(IPAddress a)
    {
        byte[] b = a.GetAddressBytes();
        return ((uint)b[0] << 24) | ((uint)b[1] << 16) | ((uint)b[2] << 8) | (uint)b[3];
    }

    public static string FromUInt(uint v)
    {
        return string.Format("{0}.{1}.{2}.{3}", (v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255);
    }

    public static string[] HostRange(string ip, string mask, int maxHosts)
    {
        uint ipN = ToUInt(IPAddress.Parse(ip));
        uint mk = ToUInt(IPAddress.Parse(mask));
        uint net = ipN & mk;
        uint bcast = net | ~mk;
        if (bcast - net < 2) return new string[0];
        uint first = net + 1;
        uint last = bcast - 1;
        if ((long)(last - first) + 1 > maxHosts)
        {
            net = ipN & 0xFFFFFF00u;
            first = net + 1;
            last = (net | 0xFFu) - 1;
        }
        List<string> list = new List<string>();
        for (uint x = first; x <= last; x++) list.Add(FromUInt(x));
        return list.ToArray();
    }
}

public class EarthGameScanner
{
    [DllImport("iphlpapi.dll", ExactSpelling = true)]
    private static extern int SendARP(uint destIp, uint srcIp, byte[] macAddr, ref uint physicalAddrLen);

    public string[] Ips;
    public string[] SelfIps;
    public int[] IgnoredPorts;
    public string[] TcpDb;
    public bool FullScan;
    public int[] CustomPorts;
    public bool SkipAliveCheck;
    public string[] PriorityIps;
    public int TotalAlive;
    public int TcpTimeoutMs = 700;
    public int Concurrency = 600;

    public ConcurrentQueue<EarthServerHit> Hits = new ConcurrentQueue<EarthServerHit>();
    public volatile bool CancelRequested;
    public volatile bool Finished;
    public volatile string Status = "";
    public int Phase = 1;
    public int HostsTotal;
    public int HostsChecked;
    public int HostsDone;
    public int HostsAlive;
    public int PortsTotal;
    public int PortsDone;

    private Dictionary<int, string[]> tcpDb = new Dictionary<int, string[]>();
    private Dictionary<int, bool> ignored = new Dictionary<int, bool>();
    private Thread worker;

    private static readonly int[] A2sPorts = new int[] { 27015, 27016, 27017, 27018, 27019, 27020, 27021, 27022, 27023, 27024, 27025, 27030, 2457, 7778, 7787, 26900, 26901, 28016, 27165 };
    private static readonly int[] BedrockPorts = new int[] { 19132 };
    private static readonly int[] QuakePorts = new int[] { 27960, 28960, 28961, 28962 };
    // Alle jemals gebräuchlichen GameSpy-Abfrageports (\status\-Protokoll), gesammelt aus den
    // historischen GameSpy-SDK-Standardports zahlreicher Spiele (Stand der bekannten Dokumentation):
    // 7778/7787 Unreal/UT, 27888/27889 UT2003/UT2004/Shogo, 23000-23009 Battlefield 1942/Vietnam,
    // 29900 Battlefield 2/2142/Project Reality, 6500 Unreal Tournament 3, 20142 Descent 3,
    // 28000/28001/28002 Starsiege: Tribes/Tribes 2, 28900/28910 GameSpy-Master/Heretic II/Soldier of Fortune,
    // 2346/2347 Ghost Recon, 12300/12301 Rainbow Six/Rogue Spear, 3282/3784 Klassiker mit GameSpy-Anbindung.
    private static readonly int[] GamespyPorts = new int[] {
        7778, 7787, 27888, 27889,
        23000, 23001, 23002, 23003, 23004, 23005, 23006, 23007, 23008, 23009,
        29900, 6500, 20142,
        28000, 28001, 28002, 28900, 28910,
        2346, 2347, 12300, 12301, 3282, 3784
    };

    public void Start()
    {
        if (IgnoredPorts != null) { foreach (int p in IgnoredPorts) ignored[p] = true; }
        if (TcpDb != null)
        {
            foreach (string line in TcpDb)
            {
                string[] f = line.Split('|');
                int port;
                if (f.Length >= 3 && int.TryParse(f[0], out port)) tcpDb[port] = new string[] { f[1], f[2] };
            }
        }
        int w, c;
        ThreadPool.GetMinThreads(out w, out c);
        if (w < 500) ThreadPool.SetMinThreads(500, c);
        worker = new Thread(Run);
        worker.IsBackground = true;
        worker.Start();
    }

    public void Cancel() { CancelRequested = true; }

    private bool IsSelf(string ip)
    {
        if (SelfIps == null) return false;
        for (int i = 0; i < SelfIps.Length; i++) { if (SelfIps[i] == ip) return true; }
        return false;
    }

    private bool IsAlive(string ipStr)
    {
        if (IsSelf(ipStr)) return true;
        IPAddress ip = IPAddress.Parse(ipStr);
        try
        {
            byte[] mac = new byte[6];
            uint len = 6;
            uint dest = BitConverter.ToUInt32(ip.GetAddressBytes(), 0);
            if (SendARP(dest, 0, mac, ref len) == 0) return true;
        }
        catch (Exception) { }
        try
        {
            using (Ping p = new Ping())
            {
                PingReply r = p.Send(ip, 400);
                if (r != null && r.Status == IPStatus.Success) return true;
            }
        }
        catch (Exception) { }
        return false;
    }

    [DllImport("iphlpapi.dll")]
    private static extern int GetIpNetTable(IntPtr pIpNetTable, ref int pdwSize, bool bOrder);

    private Dictionary<string, bool> ReadArpTable()
    {
        Dictionary<string, bool> result = new Dictionary<string, bool>();
        int size = 0;
        GetIpNetTable(IntPtr.Zero, ref size, false);
        if (size <= 0) return result;
        IntPtr buf = Marshal.AllocHGlobal(size);
        try
        {
            if (GetIpNetTable(buf, ref size, false) != 0) return result;
            int count = Marshal.ReadInt32(buf);
            int offset = 4;
            for (int i = 0; i < count; i++)
            {
                int physLen = Marshal.ReadInt32(buf, offset + 4);
                int addr = Marshal.ReadInt32(buf, offset + 16);
                int type = Marshal.ReadInt32(buf, offset + 20);
                if (physLen == 6 && (type == 3 || type == 4))
                {
                    byte[] bb = BitConverter.GetBytes(addr);
                    result[bb[0] + "." + bb[1] + "." + bb[2] + "." + bb[3]] = true;
                }
                offset += 24;
            }
        }
        catch (Exception) { }
        finally { Marshal.FreeHGlobal(buf); }
        return result;
    }

    private bool PingOnly(string ipStr)
    {
        try
        {
            using (Ping p = new Ping())
            {
                PingReply r = p.Send(IPAddress.Parse(ipStr), 350);
                return (r != null && r.Status == IPStatus.Success);
            }
        }
        catch (Exception) { return false; }
    }

    private void Run()
    {
        try
        {
            Dictionary<string, bool> inRange = new Dictionary<string, bool>();
            foreach (string r in Ips) inRange[r] = true;
            Dictionary<string, bool> used = new Dictionary<string, bool>();
            List<string> group1 = new List<string>();
            List<string> group2 = new List<string>();
            if (PriorityIps != null)
            {
                foreach (string p in PriorityIps)
                {
                    if (p != null && inRange.ContainsKey(p) && !used.ContainsKey(p)) { used[p] = true; group1.Add(p); }
                }
            }
            foreach (string r2 in Ips) { if (!used.ContainsKey(r2)) group2.Add(r2); }
            List<int> ports = BuildPortList();
            if (group1.Count > 0) ProcessGroup(group1, ports, "Bekannte Hosts");
            if (!CancelRequested && group2.Count > 0) ProcessGroup(group2, ports, (group1.Count > 0) ? "Restliches Subnetz" : "Subnetz");
            Status = CancelRequested ? "Scan abgebrochen." : "Scan abgeschlossen.";
        }
        catch (Exception ex)
        {
            Status = "Fehler: " + ex.Message;
        }
        Finished = true;
    }

    private void ProcessGroup(List<string> hosts, List<int> ports, string label)
    {
        Phase = 1;
        HostsTotal = hosts.Count;
        HostsChecked = 0;
        HostsDone = 0;
        HostsAlive = 0;
        Status = label + ": suche aktive Hosts";
        List<string> alive = new List<string>();
        object lk = new object();
        if (SkipAliveCheck)
        {
            alive.AddRange(hosts);
            HostsChecked = hosts.Count;
        }
        else if (hosts.Count > 2000)
        {
            ParallelOptions poBig = new ParallelOptions();
            poBig.MaxDegreeOfParallelism = 300;
            Parallel.ForEach(hosts, poBig, ip =>
            {
                if (CancelRequested) return;
                if (IsSelf(ip) || PingOnly(ip)) { lock (lk) { alive.Add(ip); } }
                Interlocked.Increment(ref HostsChecked);
            });
            Dictionary<string, bool> have = new Dictionary<string, bool>();
            foreach (string a in alive) have[a] = true;
            Dictionary<string, bool> arp = ReadArpTable();
            foreach (string h in hosts)
            {
                if (!have.ContainsKey(h) && arp.ContainsKey(h)) alive.Add(h);
            }
        }
        else
        {
            ParallelOptions poSmall = new ParallelOptions();
            poSmall.MaxDegreeOfParallelism = 64;
            Parallel.ForEach(hosts, poSmall, ip =>
            {
                if (CancelRequested) return;
                if (IsAlive(ip)) { lock (lk) { alive.Add(ip); } }
                Interlocked.Increment(ref HostsChecked);
            });
        }

        alive.Sort(delegate (string x, string y)
        {
            return EarthNet.ToUInt(IPAddress.Parse(x)).CompareTo(EarthNet.ToUInt(IPAddress.Parse(y)));
        });
        HostsAlive = alive.Count;
        TotalAlive += alive.Count;
        Phase = 2;
        foreach (string ipStr in alive)
        {
            if (CancelRequested) break;
            Status = label + ": scanne " + ipStr + " (" + (HostsDone + 1) + "/" + HostsAlive + ") ...";
            PortsTotal = ports.Count;
            PortsDone = 0;
            IPAddress ip = IPAddress.Parse(ipStr);
            Task udp = Task.Run(() => ProbeUdpHost(ip));
            ScanTcp(ip, ports);
            try { udp.Wait(); } catch (Exception) { }
            HostsDone++;
        }
    }

    private List<int> BuildPortList()
    {
        if (CustomPorts != null && CustomPorts.Length > 0)
        {
            return new List<int>(CustomPorts);
        }
        List<int> ports = new List<int>();
        Dictionary<int, bool> seen = new Dictionary<int, bool>();
        foreach (KeyValuePair<int, string[]> kv in tcpDb)
        {
            if (!ignored.ContainsKey(kv.Key) && !seen.ContainsKey(kv.Key)) { seen[kv.Key] = true; ports.Add(kv.Key); }
        }
        if (FullScan)
        {
            for (int p = 1024; p <= 49151; p++)
            {
                if (!ignored.ContainsKey(p) && !seen.ContainsKey(p)) { seen[p] = true; ports.Add(p); }
            }
        }
        return ports;
    }

    private async Task<bool> ProbeTcpAsync(IPAddress ip, int port, int timeoutMs)
    {
        using (TcpClient c = new TcpClient(AddressFamily.InterNetwork))
        {
            Task t = c.ConnectAsync(ip, port);
            Task first = await Task.WhenAny(t, Task.Delay(timeoutMs));
            if (first == t && !t.IsFaulted && !t.IsCanceled && c.Connected) return true;
            if (t.IsFaulted) { Exception ex = t.Exception; }
            else if (first != t)
            {
                Task ignored = t.ContinueWith(x => { Exception e = x.Exception; }, TaskContinuationOptions.OnlyOnFaulted);
            }
            return false;
        }
    }

    private void ScanTcp(IPAddress ip, List<int> ports)
    {
        SemaphoreSlim sem = new SemaphoreSlim(Concurrency);
        List<Task> tasks = new List<Task>();
        foreach (int p in ports)
        {
            if (CancelRequested) break;
            sem.Wait();
            int port = p;
            Task t = Task.Run(async () =>
            {
                try
                {
                    if (await ProbeTcpAsync(ip, port, TcpTimeoutMs)) { OnTcpOpen(ip, port); }
                }
                catch (Exception) { }
                finally
                {
                    Interlocked.Increment(ref PortsDone);
                    sem.Release();
                }
            });
            tasks.Add(t);
        }
        try { Task.WaitAll(tasks.ToArray()); } catch (Exception) { }
    }

    private void OnTcpOpen(IPAddress ip, int port)
    {
        EarthServerHit h = new EarthServerHit();
        h.Ip = ip.ToString();
        h.Port = port;
        h.Protocol = "TCP";
        string[] db;
        if (tcpDb.TryGetValue(port, out db)) { h.Key = db[0]; h.Game = db[1]; }
        if (port >= 25565 && port <= 25575)
        {
            string mc = QueryMinecraft(ip, port);
            if (mc != null) { h.Key = "minecraft-java"; h.Game = "Minecraft (Java)"; h.Info = mc; }
        }
        bool enrich = (h.Info.Length == 0);
        Hits.Enqueue(h);
        if (enrich) QueryA2S(ip, port);
    }

    private void ProbeUdpHost(IPAddress ip)
    {
        List<Task> tasks = new List<Task>();
        if (CustomPorts != null && CustomPorts.Length > 0)
        {
            int cnt = 0;
            bool silent = CustomPorts.Length <= 50;
            foreach (int cport in CustomPorts)
            {
                if (cnt++ >= 300) break;
                int cp1 = cport;
                tasks.Add(Task.Run(() => QueryA2S(ip, cp1)));
                tasks.Add(Task.Run(() => QueryBedrock(ip, cp1)));
                tasks.Add(Task.Run(() => QueryQuake(ip, cp1)));
                tasks.Add(Task.Run(() => QueryGamespy(ip, cp1, silent)));
            }
            try { Task.WaitAll(tasks.ToArray()); } catch (Exception) { }
            return;
        }
        foreach (int port in A2sPorts)
        {
            int pp = port;
            tasks.Add(Task.Run(() => QueryA2S(ip, pp)));
        }
        for (int i = 0; i < BedrockPorts.Length; i++)
        {
            int pb = BedrockPorts[i];
            tasks.Add(Task.Run(() => QueryBedrock(ip, pb)));
        }
        for (int i = 0; i < QuakePorts.Length; i++)
        {
            int pq = QuakePorts[i];
            tasks.Add(Task.Run(() => QueryQuake(ip, pq)));
        }
        for (int i = 0; i < GamespyPorts.Length; i++)
        {
            int pg = GamespyPorts[i];
            tasks.Add(Task.Run(() => QueryGamespy(ip, pg, false)));
        }
        try { Task.WaitAll(tasks.ToArray()); } catch (Exception) { }
    }

    private static byte[] BuildA2S(byte[] challenge)
    {
        byte[] head = new byte[] { 0xFF, 0xFF, 0xFF, 0xFF, 0x54 };
        byte[] body = Encoding.ASCII.GetBytes("Source Engine Query\0");
        int extra = (challenge == null) ? 0 : 4;
        byte[] q = new byte[head.Length + body.Length + extra];
        Buffer.BlockCopy(head, 0, q, 0, head.Length);
        Buffer.BlockCopy(body, 0, q, head.Length, body.Length);
        if (challenge != null) Buffer.BlockCopy(challenge, 0, q, head.Length + body.Length, 4);
        return q;
    }

    private static string ReadStr(byte[] b, ref int pos)
    {
        int start = pos;
        while (pos < b.Length && b[pos] != 0) pos++;
        string s = Encoding.UTF8.GetString(b, start, pos - start);
        pos++;
        return s;
    }

    private void QueryA2S(IPAddress ip, int port)
    {
        UdpClient u = null;
        try
        {
            u = new UdpClient(AddressFamily.InterNetwork);
            u.Client.ReceiveTimeout = 700;
            u.Connect(ip, port);
            byte[] q = BuildA2S(null);
            u.Send(q, q.Length);
            IPEndPoint ep = new IPEndPoint(IPAddress.Any, 0);
            byte[] r = u.Receive(ref ep);
            if (r.Length >= 9 && r[4] == 0x41)
            {
                byte[] ch = new byte[4];
                Array.Copy(r, 5, ch, 0, 4);
                q = BuildA2S(ch);
                u.Send(q, q.Length);
                r = u.Receive(ref ep);
            }
            if (r.Length > 6 && r[0] == 0xFF && r[1] == 0xFF && r[2] == 0xFF && r[3] == 0xFF && r[4] == 0x49)
            {
                int pos = 6;
                string name = ReadStr(r, ref pos);
                string map = ReadStr(r, ref pos);
                string folder = ReadStr(r, ref pos);
                string game = ReadStr(r, ref pos);
                pos += 2;
                int players = 0;
                int max = 0;
                if (pos + 1 < r.Length) { players = r[pos]; max = r[pos + 1]; }
                // Optionaler EDF-Block hinter der Versionskennung: Bit 0x80 = Spielport
                // (bei vielen Spielen weicht der Abfrageport vom Verbindungsport ab).
                int gamePort = 0;
                try
                {
                    int p2 = pos + 2 + 5;
                    if (p2 < r.Length)
                    {
                        ReadStr(r, ref p2);
                        if (p2 < r.Length)
                        {
                            byte edf = r[p2]; p2++;
                            if ((edf & 0x80) != 0 && p2 + 1 < r.Length) gamePort = r[p2] | (r[p2 + 1] << 8);
                        }
                    }
                }
                catch (Exception) { gamePort = 0; }
                EarthServerHit h = new EarthServerHit();
                h.Ip = ip.ToString();
                h.Port = port;
                h.Protocol = "UDP (A2S)";
                h.Key = "a2s";
                h.Game = game;
                h.Folder = folder;
                if (gamePort > 0 && gamePort < 65536 && gamePort != port) h.JoinPort = gamePort;
                h.Info = name + " | Map: " + map + " | Spieler: " + players + "/" + max;
                Hits.Enqueue(h);
            }
        }
        catch (Exception) { }
        finally { if (u != null) u.Close(); }
    }

    private void QueryBedrock(IPAddress ip, int port)
    {
        UdpClient u = null;
        try
        {
            u = new UdpClient(AddressFamily.InterNetwork);
            u.Client.ReceiveTimeout = 700;
            u.Connect(ip, port);
            byte[] magic = new byte[] { 0x00, 0xFF, 0xFF, 0x00, 0xFE, 0xFE, 0xFE, 0xFE, 0xFD, 0xFD, 0xFD, 0xFD, 0x12, 0x34, 0x56, 0x78 };
            byte[] q = new byte[33];
            q[0] = 0x01;
            Buffer.BlockCopy(magic, 0, q, 9, 16);
            u.Send(q, q.Length);
            IPEndPoint ep = new IPEndPoint(IPAddress.Any, 0);
            byte[] r = u.Receive(ref ep);
            if (r.Length > 35 && r[0] == 0x1C)
            {
                int len = (r[33] << 8) | r[34];
                if (r.Length >= 35 + len)
                {
                    string s = Encoding.UTF8.GetString(r, 35, len);
                    string[] p = s.Split(';');
                    EarthServerHit h = new EarthServerHit();
                    h.Ip = ip.ToString();
                    h.Port = port;
                    h.Protocol = "UDP (RakNet)";
                    h.Key = "minecraft-bedrock";
                    h.Game = "Minecraft (Bedrock)";
                    string motd = p.Length > 1 ? p[1] : "";
                    string ver = p.Length > 3 ? p[3] : "";
                    string pl = (p.Length > 5) ? (p[4] + "/" + p[5]) : "?";
                    h.Info = motd + " | Version " + ver + " | Spieler: " + pl;
                    Hits.Enqueue(h);
                }
            }
        }
        catch (Exception) { }
        finally { if (u != null) u.Close(); }
    }

    private void QueryQuake(IPAddress ip, int port)
    {
        UdpClient u = null;
        try
        {
            u = new UdpClient(AddressFamily.InterNetwork);
            u.Client.ReceiveTimeout = 700;
            u.Connect(ip, port);
            byte[] q = Encoding.ASCII.GetBytes("\u00FF\u00FF\u00FF\u00FFgetinfo earth\n");
            q[0] = 0xFF; q[1] = 0xFF; q[2] = 0xFF; q[3] = 0xFF;
            u.Send(q, q.Length);
            IPEndPoint ep = new IPEndPoint(IPAddress.Any, 0);
            byte[] r = u.Receive(ref ep);
            if (r.Length < 20) return;
            string t = Encoding.ASCII.GetString(r, 4, r.Length - 4);
            if (!t.StartsWith("infoResponse")) return;
            int nl = t.IndexOf('\n');
            string kv = (nl >= 0) ? t.Substring(nl + 1) : "";
            string[] parts = kv.Split('\\');
            Dictionary<string, string> d = new Dictionary<string, string>();
            for (int i = 1; i + 1 < parts.Length; i += 2) d[parts[i]] = parts[i + 1];
            string host = d.ContainsKey("hostname") ? d["hostname"] : "";
            string map = d.ContainsKey("mapname") ? d["mapname"] : "";
            string cl = d.ContainsKey("clients") ? d["clients"] : "?";
            string mx = d.ContainsKey("sv_maxclients") ? d["sv_maxclients"] : "?";
            string gm = d.ContainsKey("gamename") ? d["gamename"] : (d.ContainsKey("game") ? d["game"] : "");
            EarthServerHit h = new EarthServerHit();
            h.Ip = ip.ToString();
            h.Port = port;
            h.Protocol = "UDP (Quake3)";
            h.Key = "quake3";
            h.Game = (gm.Length > 0) ? gm : "id Tech / Call of Duty (Quake3-Protokoll)";
            h.Folder = gm;
            h.Info = host + " | Map: " + map + " | Spieler: " + cl + "/" + mx;
            Hits.Enqueue(h);
        }
        catch (Exception) { }
        finally { if (u != null) u.Close(); }
    }

    private static string GsVal(Dictionary<string, string> d, string k)
    {
        string v;
        return d.TryGetValue(k, out v) ? v : "";
    }

    private void QueryGamespy(IPAddress ip, int port, bool reportSilent)
    {
        UdpClient u = null;
        try
        {
            u = new UdpClient(AddressFamily.InterNetwork);
            u.Client.ReceiveTimeout = 800;
            u.Connect(ip, port);
            byte[] q = Encoding.ASCII.GetBytes("\\status\\");
            u.Send(q, q.Length);
            IPEndPoint ep = new IPEndPoint(IPAddress.Any, 0);
            byte[] r = u.Receive(ref ep);
            string t = Encoding.UTF8.GetString(r);
            string[] parts = t.Split('\\');
            Dictionary<string, string> d = new Dictionary<string, string>();
            for (int i = 1; i + 1 < parts.Length; i += 2) d[parts[i].ToLower()] = parts[i + 1];
            EarthServerHit h = new EarthServerHit();
            h.Ip = ip.ToString();
            h.Port = port;
            string gn = GsVal(d, "gamename");
            if (d.Count > 0)
            {
                h.Protocol = "UDP (GameSpy)";
                h.Key = "gamespy";
                h.Folder = gn;
                if (gn.ToLower().IndexOf("fear") >= 0) h.Game = "F.E.A.R.";
                else h.Game = (gn.Length > 0) ? gn : "GameSpy-Server";
                int hp;
                if (int.TryParse(GsVal(d, "hostport"), out hp) && hp > 0 && hp < 65536 && hp != port) h.JoinPort = hp;
                h.Info = GsVal(d, "hostname") + " | Map: " + GsVal(d, "mapname") + " | Spieler: " + GsVal(d, "numplayers") + "/" + GsVal(d, "maxplayers") + " | Typ: " + GsVal(d, "gametype");
            }
            else
            {
                h.Protocol = "UDP (Antwort)";
                h.Info = "UDP-Antwort erhalten (" + r.Length + " Bytes), Protokoll unbekannt";
            }
            Hits.Enqueue(h);
        }
        catch (SocketException se)
        {
            if (reportSilent && se.SocketErrorCode == SocketError.TimedOut)
            {
                EarthServerHit h2 = new EarthServerHit();
                h2.Ip = ip.ToString();
                h2.Port = port;
                h2.Protocol = "UDP (offen|gefiltert)";
                h2.Info = "Keine Antwort - UDP-Port evtl. offen (oder von Firewall verworfen)";
                Hits.Enqueue(h2);
            }
        }
        catch (Exception) { }
        finally { if (u != null) u.Close(); }
    }

    private static byte[] VarInt(int v)
    {
        List<byte> l = new List<byte>();
        uint u = (uint)v;
        do
        {
            byte b = (byte)(u & 0x7F);
            u >>= 7;
            if (u != 0) b |= 0x80;
            l.Add(b);
        } while (u != 0);
        return l.ToArray();
    }

    private static string Rx(string text, string pattern)
    {
        Match m = Regex.Match(text, pattern);
        return m.Success ? m.Groups[1].Value : "";
    }

    private static string QueryMinecraft(IPAddress ip, int port)
    {
        try
        {
            using (TcpClient c = new TcpClient(AddressFamily.InterNetwork))
            {
                IAsyncResult ar = c.BeginConnect(ip, port, null, null);
                if (!ar.AsyncWaitHandle.WaitOne(800)) return null;
                c.EndConnect(ar);
                c.ReceiveTimeout = 1200;
                c.SendTimeout = 1200;
                NetworkStream ns = c.GetStream();
                byte[] host = Encoding.UTF8.GetBytes(ip.ToString());
                List<byte> hs = new List<byte>();
                hs.Add(0x00);
                hs.AddRange(VarInt(47));
                hs.AddRange(VarInt(host.Length));
                hs.AddRange(host);
                hs.Add((byte)(port >> 8));
                hs.Add((byte)(port & 0xFF));
                hs.AddRange(VarInt(1));
                List<byte> pkt = new List<byte>();
                pkt.AddRange(VarInt(hs.Count));
                pkt.AddRange(hs);
                pkt.Add(0x01);
                pkt.Add(0x00);
                byte[] pk = pkt.ToArray();
                ns.Write(pk, 0, pk.Length);
                byte[] buf = new byte[8192];
                int total = 0;
                for (int i = 0; i < 3 && total < buf.Length; i++)
                {
                    try
                    {
                        int n = ns.Read(buf, total, buf.Length - total);
                        if (n <= 0) break;
                        total += n;
                    }
                    catch (Exception) { break; }
                }
                if (total == 0) return null;
                string text = Encoding.UTF8.GetString(buf, 0, total);
                if (text.IndexOf("\"players\"") < 0 && text.IndexOf("\"version\"") < 0) return null;
                string ver = Rx(text, "\"version\"\\s*:\\s*\\{\\s*\"name\"\\s*:\\s*\"([^\"]*)\"");
                string on = Rx(text, "\"online\"\\s*:\\s*(\\d+)");
                string mx = Rx(text, "\"max\"\\s*:\\s*(\\d+)");
                string desc = Rx(text, "\"description\"\\s*:\\s*\"([^\"]*)\"");
                if (desc.Length == 0) desc = Rx(text, "\"text\"\\s*:\\s*\"([^\"]*)\"");
                return desc + " | Version " + ver + " | Spieler: " + on + "/" + mx;
            }
        }
        catch (Exception) { return null; }
    }
}

public class EarthPeer
{
    public TcpClient Client;
    public StreamWriter Writer;
    public bool Outgoing;
    public string Id;
    public string Name = "";
    public string Ip = "";
}

public class EarthLanNode
{
    public const int PortNumber = 9872;
    public ConcurrentQueue<string> Events = new ConcurrentQueue<string>();
    public string NodeId;
    public string NodeName;
    public string BindIp;
    public volatile bool ScanRunning;
    public int ScanDone;
    public int ScanTotal;
    public string Mask = "";
    private UdpClient beaconRx;
    private string[] shared = new string[0];
    private readonly Dictionary<string, int> lastDial = new Dictionary<string, int>();

    private TcpListener listener;
    private volatile bool running;
    private volatile bool scanCancel;
    private readonly object peerLock = new object();
    private Dictionary<string, EarthPeer> peers = new Dictionary<string, EarthPeer>();

    public EarthLanNode(string bindIp, string nodeName)
    {
        BindIp = bindIp;
        NodeName = CleanName(nodeName);
        NodeId = Guid.NewGuid().ToString("N").Substring(0, 12);
    }

    private static string CleanName(string s)
    {
        if (s == null) return "";
        return s.Replace("\r", " ").Replace("\n", " ").Replace("|", "/");
    }

    private static string CleanLine(string s)
    {
        if (s == null) return "";
        return s.Replace("\r", " ").Replace("\n", " ");
    }

    public string Start()
    {
        try
        {
            listener = new TcpListener(IPAddress.Parse(BindIp), PortNumber);
            listener.Start();
            running = true;
            Thread t = new Thread(AcceptLoop);
            t.IsBackground = true;
            t.Start();
            StartBeacon();
            return null;
        }
        catch (Exception ex)
        {
            return ex.Message;
        }
    }

    public void Stop()
    {
        running = false;
        scanCancel = true;
        try { if (listener != null) listener.Stop(); } catch (Exception) { }
        try { if (beaconRx != null) beaconRx.Close(); } catch (Exception) { }
        List<EarthPeer> list = new List<EarthPeer>();
        lock (peerLock) { foreach (KeyValuePair<string, EarthPeer> kv in peers) list.Add(kv.Value); }
        foreach (EarthPeer p in list) { try { p.Client.Close(); } catch (Exception) { } }
    }

    private void AcceptLoop()
    {
        while (running)
        {
            try
            {
                TcpClient c = listener.AcceptTcpClient();
                EarthPeer p = new EarthPeer();
                p.Client = c;
                p.Outgoing = false;
                p.Ip = ((IPEndPoint)c.Client.RemoteEndPoint).Address.ToString();
                Thread t = new Thread(() => PeerLoop(p));
                t.IsBackground = true;
                t.Start();
            }
            catch (Exception)
            {
                if (!running) break;
                Thread.Sleep(50);
            }
        }
    }

    private void Send(EarthPeer p, string line)
    {
        try
        {
            lock (p) { p.Writer.WriteLine(line); }
        }
        catch (Exception) { }
    }

    private void PeerLoop(EarthPeer p)
    {
        try
        {
            NetworkStream ns = p.Client.GetStream();
            p.Client.NoDelay = true;
            p.Client.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.KeepAlive, true);
            p.Writer = new StreamWriter(ns, new UTF8Encoding(false));
            p.Writer.AutoFlush = true;
            p.Writer.NewLine = "\n";
            StreamReader rd = new StreamReader(ns, Encoding.UTF8);
            Send(p, "HELLO|PELAN1|" + NodeId + "|" + NodeName);
            p.Client.ReceiveTimeout = 5000;
            string line = rd.ReadLine();
            if (line == null) return;
            string[] f = line.Split(new char[] { '|' }, 4);
            if (f.Length < 4 || f[0] != "HELLO" || f[1] != "PELAN1") return;
            p.Id = f[2];
            p.Name = CleanName(f[3]);
            if (p.Id == NodeId) return;
            if (!Register(p)) return;
            SendShared(p);
            p.Client.ReceiveTimeout = 0;
            while (running)
            {
                line = rd.ReadLine();
                if (line == null) break;
                HandleLine(p, line);
            }
        }
        catch (Exception) { }
        finally
        {
            Unregister(p);
            try { p.Client.Close(); } catch (Exception) { }
        }
    }

    private bool Register(EarthPeer p)
    {
        lock (peerLock)
        {
            EarthPeer ex;
            if (peers.TryGetValue(p.Id, out ex))
            {
                string exInit = ex.Outgoing ? NodeId : ex.Id;
                string newInit = p.Outgoing ? NodeId : p.Id;
                if (string.CompareOrdinal(newInit, exInit) < 0)
                {
                    peers[p.Id] = p;
                    try { ex.Client.Close(); } catch (Exception) { }
                    Events.Enqueue("PEER+|" + p.Id + "|" + p.Name + "|" + p.Ip);
                    return true;
                }
                return false;
            }
            peers[p.Id] = p;
        }
        Events.Enqueue("PEER+|" + p.Id + "|" + p.Name + "|" + p.Ip);
        return true;
    }

    private void Unregister(EarthPeer p)
    {
        bool removed = false;
        lock (peerLock)
        {
            EarthPeer cur;
            if (p.Id != null && peers.TryGetValue(p.Id, out cur) && object.ReferenceEquals(cur, p))
            {
                peers.Remove(p.Id);
                removed = true;
            }
        }
        if (removed) Events.Enqueue("PEER-|" + p.Id + "|" + p.Name + "|" + p.Ip);
    }

    private void HandleLine(EarthPeer p, string line)
    {
        if (line.Length > 4000) return;
        if (line.StartsWith("MSG|")) Events.Enqueue("CHAT|" + p.Name + "|" + line.Substring(4));
        else if (line.StartsWith("SRV|")) Events.Enqueue("SRV|" + p.Name + "|" + line.Substring(4));
    }

    public int Broadcast(string text)
    {
        List<EarthPeer> list = new List<EarthPeer>();
        lock (peerLock) { foreach (KeyValuePair<string, EarthPeer> kv in peers) list.Add(kv.Value); }
        foreach (EarthPeer p in list) Send(p, "MSG|" + CleanLine(text));
        return list.Count;
    }

    public int PeerCount()
    {
        lock (peerLock) { return peers.Count; }
    }

    private bool IsConnectedIp(string ip)
    {
        lock (peerLock)
        {
            foreach (KeyValuePair<string, EarthPeer> kv in peers) { if (kv.Value.Ip == ip) return true; }
        }
        return false;
    }

    private TcpClient TryConnect(string ip, int timeoutMs)
    {
        TcpClient c = new TcpClient(AddressFamily.InterNetwork);
        try
        {
            IAsyncResult ar = c.BeginConnect(IPAddress.Parse(ip), PortNumber, null, null);
            if (ar.AsyncWaitHandle.WaitOne(timeoutMs))
            {
                c.EndConnect(ar);
                return c;
            }
        }
        catch (Exception) { }
        try { c.Close(); } catch (Exception) { }
        return null;
    }

    private void StartOutgoing(TcpClient c)
    {
        EarthPeer p = new EarthPeer();
        p.Client = c;
        p.Outgoing = true;
        p.Ip = ((IPEndPoint)c.Client.RemoteEndPoint).Address.ToString();
        Thread t = new Thread(() => PeerLoop(p));
        t.IsBackground = true;
        t.Start();
    }

    public void ConnectTo(string ip)
    {
        Thread t = new Thread(() =>
        {
            if (ip == BindIp) { Events.Enqueue("SYS|Das ist die eigene Adresse."); return; }
            if (IsConnectedIp(ip)) { Events.Enqueue("SYS|Bereits verbunden mit " + ip); return; }
            TcpClient c = TryConnect(ip, 2000);
            if (c == null) Events.Enqueue("SYS|Keine Verbindung zu " + ip + ":9872 (Manager dort nicht geoeffnet?)");
            else StartOutgoing(c);
        });
        t.IsBackground = true;
        t.Start();
    }

    private void StartBeacon()
    {
        try
        {
            beaconRx = new UdpClient(AddressFamily.InterNetwork);
            beaconRx.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
            beaconRx.Client.Bind(new IPEndPoint(IPAddress.Any, PortNumber));
            try { beaconRx.Client.IOControl((IOControlCode)(-1744830452), new byte[] { 0, 0, 0, 0 }, null); } catch (Exception) { }
            Thread rt = new Thread(BeaconRxLoop);
            rt.IsBackground = true;
            rt.Start();
        }
        catch (Exception)
        {
            beaconRx = null;
            Events.Enqueue("SYS|Automatische Suche (UDP 9872) nicht verfuegbar - bitte IP manuell eingeben.");
        }
        Thread tt = new Thread(BeaconTxLoop);
        tt.IsBackground = true;
        tt.Start();
    }

    private void BeaconRxLoop()
    {
        IPEndPoint ep = new IPEndPoint(IPAddress.Any, 0);
        while (running)
        {
            byte[] d;
            try { d = beaconRx.Receive(ref ep); }
            catch (Exception)
            {
                if (!running) break;
                Thread.Sleep(50);
                continue;
            }
            try
            {
                string text = Encoding.UTF8.GetString(d);
                string[] f = text.Split('|');
                if (f.Length < 3 || f[0] != "PELAN1B" || f[1] == NodeId) continue;
                string ip = ep.Address.ToString();
                if (ip == BindIp || IsConnectedIp(ip)) continue;
                int now = Environment.TickCount;
                int last;
                lock (lastDial)
                {
                    if (lastDial.TryGetValue(ip, out last) && (now - last) < 4000) continue;
                    lastDial[ip] = now;
                }
                string ipc = ip;
                string peerName = CleanName(f[2]);
                Thread t = new Thread(() =>
                {
                    TcpClient c = TryConnect(ipc, 1500);
                    if (c != null)
                    {
                        Events.Enqueue("SYS|Manager automatisch gefunden: " + peerName + " (" + ipc + ")");
                        StartOutgoing(c);
                    }
                });
                t.IsBackground = true;
                t.Start();
            }
            catch (Exception) { }
        }
    }

    private void BeaconTxLoop()
    {
        UdpClient tx = null;
        IPEndPoint bc1 = new IPEndPoint(IPAddress.Broadcast, PortNumber);
        IPEndPoint bc2 = null;
        try
        {
            tx = new UdpClient(new IPEndPoint(IPAddress.Parse(BindIp), 0));
            tx.EnableBroadcast = true;
            if (!string.IsNullOrEmpty(Mask))
            {
                uint ipN = EarthNet.ToUInt(IPAddress.Parse(BindIp));
                uint mk = EarthNet.ToUInt(IPAddress.Parse(Mask));
                bc2 = new IPEndPoint(IPAddress.Parse(EarthNet.FromUInt(ipN | ~mk)), PortNumber);
            }
        }
        catch (Exception) { return; }
        byte[] msg = Encoding.UTF8.GetBytes("PELAN1B|" + NodeId + "|" + NodeName);
        while (running)
        {
            try
            {
                tx.Send(msg, msg.Length, bc1);
                if (bc2 != null) tx.Send(msg, msg.Length, bc2);
            }
            catch (Exception) { }
            for (int i = 0; i < 30 && running; i++) Thread.Sleep(100);
        }
        try { tx.Close(); } catch (Exception) { }
    }

    public void SetSharedServers(string[] lines)
    {
        List<string> l = new List<string>();
        if (lines != null)
        {
            foreach (string s in lines)
            {
                if (l.Count >= 100) break;
                if (s != null && s.Length < 1500) l.Add(CleanLine(s));
            }
        }
        List<EarthPeer> list = new List<EarthPeer>();
        lock (peerLock)
        {
            shared = l.ToArray();
            foreach (KeyValuePair<string, EarthPeer> kv in peers) list.Add(kv.Value);
        }
        foreach (EarthPeer p in list) SendShared(p);
    }

    private void SendShared(EarthPeer p)
    {
        string[] cur;
        lock (peerLock) { cur = shared; }
        foreach (string s in cur) Send(p, "SRV|" + s);
    }

    public string[] GetPeerIps()
    {
        List<string> l = new List<string>();
        lock (peerLock)
        {
            foreach (KeyValuePair<string, EarthPeer> kv in peers) l.Add(kv.Value.Ip);
        }
        return l.ToArray();
    }

    public void CancelScan() { scanCancel = true; }

    public void ScanAsync(string[] ips)
    {
        if (ScanRunning) return;
        ScanRunning = true;
        scanCancel = false;
        ScanDone = 0;
        ScanTotal = ips.Length;
        Thread t = new Thread(() =>
        {
            try
            {
                int w, c2;
                ThreadPool.GetMinThreads(out w, out c2);
                if (w < 100) ThreadPool.SetMinThreads(100, c2);
                ParallelOptions po = new ParallelOptions();
                po.MaxDegreeOfParallelism = 48;
                Parallel.ForEach(ips, po, ip =>
                {
                    if (scanCancel || !running) return;
                    if (ip != BindIp && !IsConnectedIp(ip))
                    {
                        TcpClient c = TryConnect(ip, 600);
                        if (c != null) StartOutgoing(c);
                    }
                    Interlocked.Increment(ref ScanDone);
                });
            }
            catch (Exception) { }
            ScanRunning = false;
            Events.Enqueue("SYS|Scan nach Port 9872 abgeschlossen.");
        });
        t.IsBackground = true;
        t.Start();
    }
}
'@
        Add-Type -TypeDefinition $netCode -Language CSharp
    }

    # --- Zustand -----------------------------------------------------------------
    $state = @{
        Adapter       = $null
        Scanner       = $null
        Node          = $null
        HitMap        = @{}
        Servers       = [System.Collections.Generic.List[object]]::new()
        PeerItems     = @{}
        Unread        = 0
        Tick          = 0
        Panel         = 0
        JoinMap       = @{}
        ScanFinalized = $true
        FwRule        = $false
    }
    $fwRuleName  = 'Project Earth LAN Manager 9872'

    # --- Systemports, die bei der Suche ignoriert werden (Windows, Linux, macOS) ----
    $ignoredPorts = [int[]](@(
        135,137,138,139,445,1025,1026,1027,1028,1029,1433,1434,2869,3389,5040,5357,5358,5985,5986,7680,10243,
        21,22,23,25,53,67,68,69,80,110,111,123,143,161,389,443,465,514,515,587,631,636,993,995,2049,3306,5432,
        88,548,3283,5000,5900,7000,
        500,1900,3702,4500,5353,5355,9100,17500,27036,27037,62078,9872
    ) + (6000..6010))

    # --- Spiel-Profile (Join-Parameter je Spielfamilie, beliebig erweiterbar) ------
    $gameProfiles = @(
        @{ Key = 'source';            Name = 'Source-Engine-Spiel (Steam)';       Ports = @(27015,27016,27017,27018,27019,27020); Args = '+connect {IP}:{PORT}'; Uri = ''; SteamConnect = $true;  ExeNames = @('cs2.exe','csgo.exe','hl2.exe','left4dead2.exe','tf.exe'); Hints = @() },
        @{ Key = 'minecraft-java';    Name = 'Minecraft (Java)';                  Ports = @(25565); Args = ''; Uri = ''; SteamConnect = $false; ExeNames = @('MinecraftLauncher.exe','Minecraft.exe'); Hints = @('minecraft') },
        @{ Key = 'minecraft-bedrock'; Name = 'Minecraft (Bedrock)';               Ports = @(19132); Args = ''; Uri = 'minecraft://connect/?serverUrl={IP}&serverPort={PORT}'; SteamConnect = $false; ExeNames = @(); Hints = @('minecraft') },
        @{ Key = 'quake3';            Name = 'id Tech / Call of Duty (Quake3)';   Ports = @(27960,28960); Args = '+connect {IP}:{PORT}'; Uri = ''; SteamConnect = $false; ExeNames = @(); Hints = @() },
        @{ Key = 'unreal';            Name = 'Unreal Engine / Terraria / ARK';    Ports = @(7777,7778); Args = '{IP}:{PORT}'; Uri = ''; SteamConnect = $false; ExeNames = @(); Hints = @() },
        @{ Key = 'arma';              Name = 'Arma / DayZ';                       Ports = @(2302); Args = '-connect={IP} -port={PORT}'; Uri = ''; SteamConnect = $false; ExeNames = @('arma3_x64.exe','DayZ_x64.exe'); Hints = @('arma','dayz') },
        @{ Key = 'fivem';             Name = 'FiveM (GTA V)';                     Ports = @(30120); Args = ''; Uri = 'fivem://connect/{IP}:{PORT}'; SteamConnect = $false; ExeNames = @(); Hints = @('fivem') },
        @{ Key = 'factorio';          Name = 'Factorio';                          Ports = @(34197); Args = '--mp-connect {IP}:{PORT}'; Uri = ''; SteamConnect = $false; ExeNames = @('factorio.exe'); Hints = @('factorio') },
        @{ Key = 'rust';              Name = 'Rust';                              Ports = @(28015,28016); Args = '+connect {IP}:{PORT}'; Uri = ''; SteamConnect = $false; ExeNames = @('Rust.exe','RustClient.exe'); Hints = @('rust') },
        @{ Key = 'valheim';           Name = 'Valheim';                           Ports = @(2456,2457); Args = ''; Uri = ''; SteamConnect = $false; ExeNames = @('valheim.exe'); Hints = @('valheim') }
    )
    $genericProfile = @{ Key = 'generic'; Name = 'Unbekanntes Spiel'; Ports = @(); Args = ''; Uri = ''; SteamConnect = $false; ExeNames = @(); Hints = @() }

    $tcpDbLines = @()
    foreach ($gp in $gameProfiles) {
        foreach ($pt in $gp.Ports) { $tcpDbLines += ("{0}|{1}|{2}" -f $pt, $gp.Key, $gp.Name) }
    }

    # --- Farben & Schriften ----------------------------------------------------------
    $cWhite  = [System.Drawing.Color]::White
    $cAccent = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $cBtn    = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $cInput  = [System.Drawing.Color]::FromArgb(50, 50, 50)
    $cList   = [System.Drawing.Color]::FromArgb(40, 40, 40)
    $fontMain = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Regular)
    $fontBold = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

    # --- GUI-Hilfsfunktionen ---------------------------------------------------------
    function New-DkButton([string]$text, [int]$x, [int]$y, [int]$w, [int]$h, [bool]$accent = $false) {
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $text
        $b.Location = New-Object System.Drawing.Point($x, $y)
        $b.Size = New-Object System.Drawing.Size($w, $h)
        $b.FlatStyle = "Flat"
        $b.ForeColor = $cWhite
        $b.Font = $fontBold
        if ($accent) { $b.BackColor = $cAccent } else { $b.BackColor = $cBtn }
        return $b
    }

    function New-DkLabel([string]$text, [int]$x, [int]$y, [int]$w, [int]$h) {
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $text
        $l.Location = New-Object System.Drawing.Point($x, $y)
        $l.Size = New-Object System.Drawing.Size($w, $h)
        $l.ForeColor = $cWhite
        $l.Font = $fontMain
        return $l
    }

    function New-DkText([int]$x, [int]$y, [int]$w, [int]$h) {
        $t = New-Object System.Windows.Forms.TextBox
        $t.Location = New-Object System.Drawing.Point($x, $y)
        $t.Size = New-Object System.Drawing.Size($w, $h)
        $t.BackColor = $cInput
        $t.ForeColor = $cWhite
        $t.Font = $fontMain
        return $t
    }

    function New-DkCheck([string]$text, [int]$x, [int]$y, [int]$w, [bool]$checked) {
        $c = New-Object System.Windows.Forms.CheckBox
        $c.Text = $text
        $c.Location = New-Object System.Drawing.Point($x, $y)
        $c.Size = New-Object System.Drawing.Size($w, 22)
        $c.ForeColor = $cWhite
        $c.Font = $fontMain
        $c.Checked = $checked
        return $c
    }

    function New-DkListView([int]$x, [int]$y, [int]$w, [int]$h, [string[]]$cols, [int[]]$widths) {
        $lv = New-Object System.Windows.Forms.ListView
        $lv.Location = New-Object System.Drawing.Point($x, $y)
        $lv.Size = New-Object System.Drawing.Size($w, $h)
        $lv.View = "Details"
        $lv.FullRowSelect = $true
        $lv.HideSelection = $false
        $lv.BackColor = $cList
        $lv.ForeColor = $cWhite
        $lv.Font = $fontMain
        for ($i = 0; $i -lt $cols.Count; $i++) { [void]$lv.Columns.Add($cols[$i], $widths[$i]) }
        return $lv
    }

    function Show-Msg([string]$text, [string]$title = "Hinweis", $icon = [System.Windows.Forms.MessageBoxIcon]::Information) {
        [System.Windows.Forms.MessageBox]::Show($text, $title, [System.Windows.Forms.MessageBoxButtons]::OK, $icon) | Out-Null
    }

    # --- Netzwerkadapter ---------------------------------------------------------------
    # Die Adapterauswahl selbst ist zentral im Control Center (Live-Status -> "Adapter
    # wechseln"), siehe Get-PelSelectedAdapter/Select-PelNetworkAdapter weiter oben im
    # Skript. Hier wird nur noch die zentrale Auswahl übernommen bzw. bei Bedarf über
    # denselben zentralen Dialog geändert.

    # --- Firewall (Port 9872 nur für das lokale Subnetz) ---------------------------------
    function Set-LanFirewallRule([bool]$enable) {
        try {
            Get-NetFirewallRule -DisplayName "$fwRuleName*" -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
            if ($enable) {
                New-NetFirewallRule -DisplayName $fwRuleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort 9872 -RemoteAddress LocalSubnet -Profile Any -ErrorAction Stop | Out-Null
                New-NetFirewallRule -DisplayName "$fwRuleName (UDP)" -Direction Inbound -Action Allow -Protocol UDP -LocalPort 9872 -RemoteAddress LocalSubnet -Profile Any -ErrorAction Stop | Out-Null
                $state.FwRule = $true
            } else {
                $state.FwRule = $false
            }
        } catch { }
    }

    # --- Chat ---------------------------------------------------------------------------
    function Add-ChatLine([string]$text, $color) {
        $rtbChat.SelectionStart = $rtbChat.TextLength
        $rtbChat.SelectionColor = $color
        $rtbChat.AppendText("[" + (Get-Date).ToString("HH:mm") + "] " + $text + "`r`n")
        $rtbChat.ScrollToCaret()
    }

    function Stop-LanNode {
        if ($state.Node) {
            try { $state.Node.Stop() } catch { }
            $state.Node = $null
        }
        $lvPeers.Items.Clear()
        $state.PeerItems = @{}
    }

    function Start-LanNode {
        Stop-LanNode
        if (-not $state.Adapter) { return }
        Set-LanFirewallRule $true
        $node = New-Object EarthLanNode -ArgumentList $state.Adapter.Ip, $env:COMPUTERNAME
        $node.Mask = [string]$state.Adapter.Mask
        $err = $node.Start()
        if ($err) {
            Add-ChatLine "Port 9872 konnte nicht geöffnet werden: $err" ([System.Drawing.Color]::OrangeRed)
            $lblNode.Text = "Port 9872: FEHLER - $err"
            return
        }
        $state.Node = $node
        Add-ChatLine "Port 9872 geöffnet auf $($state.Adapter.Ip). Suche andere Project Earth LAN Manager ..." ([System.Drawing.Color]::LightGray)
        $ips = [EarthNet]::HostRange($state.Adapter.Ip, $state.Adapter.Mask, 1022)
        $node.ScanAsync([string[]]$ips)
    }

    function Set-Adapter($a) {
        $state.Adapter = $a
        $lblAdapter.Text = "Adapter: $($a.Name)  |  $($a.Ip) / $($a.Mask)"
        Start-LanNode
    }

    function Invoke-AdapterButton {
        # Öffnet den zentralen Adapter-Dialog (derselbe wie im Control Center).
        $sel = Select-PelNetworkAdapter -ParentForm $form
        if ($sel) { Set-Adapter $sel }
    }

    # --- Server Browser -------------------------------------------------------------------
    function Register-Hit($h) {
        $k = "$($h.Ip):$($h.Port)"
        $newScore = 0
        if ($h.Info) { $newScore += 2 }
        if ($h.Key) { $newScore += 1 }
        if ($state.HitMap.ContainsKey($k)) {
            $o = $state.HitMap[$k]
            if ($h.Source -eq 'peer') {
                if ($o.Source -eq 'peer') { $o.Seen = $h.Seen }
                return $false
            }
            $oldScore = 0
            if ($o.Info) { $oldScore += 2 }
            if ($o.Key) { $oldScore += 1 }
            if ($newScore -le $oldScore) { return $false }
        }
        $state.HitMap[$k] = $h
        return $true
    }

    function Update-HitList {
        $showUnknown = $chkUnknown.Checked
        $selKey = $null
        if ($lvHits.SelectedItems.Count -gt 0) {
            $t = $lvHits.SelectedItems[0].Tag
            $selKey = "$($t.Ip):$($t.Port)"
        }
        $rows = @($state.HitMap.Values | Sort-Object @{ Expression = { [version]$_.Ip } }, @{ Expression = { [int]$_.Port } })
        $lvHits.BeginUpdate()
        $lvHits.Items.Clear()
        $shown = 0
        foreach ($h in $rows) {
            $known = [bool]($h.Key -or ($h.Info -and ($h.Protocol -notlike '*lokal*')))
            if ((-not $known) -and (-not $showUnknown)) { continue }
            $ipText = $h.Ip
            if ($state.Adapter -and $h.Ip -eq $state.Adapter.Ip) { $ipText = "$($h.Ip) (dieser PC)" }
            $gameText = 'Unbekannt'
            if ($h.Game) { $gameText = $h.Game }
            $it = New-Object System.Windows.Forms.ListViewItem($ipText)
            [void]$it.SubItems.Add($gameText)
            $portText = [string]$h.Port
            if ([int]$h.JoinPort -gt 0 -and [int]$h.JoinPort -ne [int]$h.Port) { $portText = "$($h.Port) (Spiel: $($h.JoinPort))" }
            [void]$it.SubItems.Add($portText)
            [void]$it.SubItems.Add($h.Protocol)
            [void]$it.SubItems.Add($h.Info)
            $it.Tag = $h
            if (-not $known) { $it.ForeColor = [System.Drawing.Color]::Gray }
            [void]$lvHits.Items.Add($it)
            $shown++
            if ($selKey -and ("$($h.Ip):$($h.Port)" -eq $selKey)) { $it.Selected = $true }
        }
        $lvHits.EndUpdate()
        $lblCount.Text = "Gefundene Einträge: $shown"
    }

    function ConvertTo-PortList([string]$text) {
        $list = [System.Collections.Generic.List[int]]::new()
        foreach ($part in ($text -split '[,;\s]+')) {
            if (-not $part) { continue }
            $lo = 0
            $hi = 0
            if ($part -match '^(\d{1,5})-(\d{1,5})$') {
                $lo = [int]$Matches[1]
                $hi = [int]$Matches[2]
                if ($lo -gt $hi) { $tmp = $lo; $lo = $hi; $hi = $tmp }
            } elseif ($part -match '^\d{1,5}$') {
                $lo = [int]$part
                $hi = $lo
            } else {
                return $null
            }
            if ($lo -lt 1 -or $hi -gt 65535) { return $null }
            for ($pt = $lo; $pt -le $hi; $pt++) { $list.Add($pt) }
        }
        return ,$list.ToArray()
    }

    function Get-ManualIp {
        $ipText = $txtManIp.Text.Trim()
        $parsed = $null
        if ([System.Net.IPAddress]::TryParse($ipText, [ref]$parsed) -and $parsed.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
            return $ipText
        }
        return $null
    }

    function Add-LocalListenerHits([string]$ownIp, [int[]]$onlyPorts, [bool]$register = $true) {
        $found = 0
        $out = [System.Collections.Generic.List[object]]::new()
        $ignoredMap = @{}
        foreach ($ig in $ignoredPorts) { $ignoredMap[[int]$ig] = $true }
        $explicit = [bool]($onlyPorts -and $onlyPorts.Count -gt 0)
        $entries = [System.Collections.Generic.List[object]]::new()
        try {
            foreach ($e in @(Get-NetUDPEndpoint -ErrorAction Stop)) {
                if ($e.LocalAddress -eq '0.0.0.0' -or $e.LocalAddress -eq $ownIp) {
                    $entries.Add([pscustomobject]@{ Port = [int]$e.LocalPort; Proto = 'UDP'; ProcId = [int]$e.OwningProcess })
                }
            }
        } catch { }
        try {
            foreach ($e in @(Get-NetTCPConnection -State Listen -ErrorAction Stop)) {
                if ($e.LocalAddress -eq '0.0.0.0' -or $e.LocalAddress -eq $ownIp) {
                    $entries.Add([pscustomobject]@{ Port = [int]$e.LocalPort; Proto = 'TCP'; ProcId = [int]$e.OwningProcess })
                }
            }
        } catch { }
        $seenPorts = @{}
        foreach ($en in $entries) {
            $port = $en.Port
            if ($explicit) {
                if ($onlyPorts -notcontains $port) { continue }
            } else {
                if ($port -lt 1024 -or $port -ge 49152) { continue }
                if ($ignoredMap.ContainsKey($port)) { continue }
            }
            if ($seenPorts.ContainsKey($port)) { continue }
            $name = ''
            $path = ''
            $desc = ''
            try {
                $pr = Get-Process -Id $en.ProcId -ErrorAction Stop
                $name = $pr.ProcessName
                $path = $pr.Path
            } catch { }
            if ($path -and $path.StartsWith($env:windir, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            if ($name -match '^(System|Idle|Registry)$') { continue }
            if ($path) { try { $desc = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($path).FileDescription } catch { } }
            $seenPorts[$port] = $true
            $h = New-Object EarthServerHit
            $h.Ip = $ownIp
            $h.Port = $port
            $h.Protocol = "$($en.Proto) (lokal)"
            $h.Game = $(if ($desc) { $desc } else { $name })
            $h.Info = "Prozess: $name | $path"
            $h.Source = 'local'
            if ($path) { try { $h.Folder = Split-Path -Leaf (Split-Path -Parent $path) } catch { } }
            if (($path -match '(?i)server|dedicated|srv|steamapps|\\games\\|\\spiele\\|epic games|gog') -or ($name -match '(?i)server|dedicated|srv')) { $h.Key = 'local' }
            if ($register) { if (Register-Hit $h) { $found++ } } else { $out.Add($h) }
        }
        if ($register) { return $found }
        return $out.ToArray()
    }

    function ConvertTo-ShareText($t) {
        return (([string]$t) -replace '[|\r\n]', '/')
    }

    function Publish-SharedServers {
        if (-not $state.Node) { return }
        $lines = [System.Collections.Generic.List[string]]::new()
        if ($chkShare.Checked -and $state.Adapter) {
            foreach ($h in @(Add-LocalListenerHits $state.Adapter.Ip $null $false)) {
                if ($h.Key -ne 'local') { continue }
                $info = ([string]$h.Info -split ' \| ')[0]
                $proto = ([string]$h.Protocol).Replace('(lokal)', '(via Manager)')
                $lines.Add(("{0}|{1}|{2}|local|{3}|{4}|{5}" -f $h.Ip, $h.Port, (ConvertTo-ShareText $proto), (ConvertTo-ShareText $h.Game), (ConvertTo-ShareText $h.Folder), (ConvertTo-ShareText $info)))
            }
            foreach ($h in @($state.HitMap.Values)) {
                if ($h.Source -eq 'peer' -or $h.Source -eq 'local') { continue }
                if (-not ($h.Key -or $h.Info)) { continue }
                if (([string]$h.Protocol) -like '*lokal*') { continue }
                $lines.Add(("{0}|{1}|{2}|{3}|{4}|{5}|{6}" -f $h.Ip, $h.Port, (ConvertTo-ShareText $h.Protocol), (ConvertTo-ShareText $h.Key), (ConvertTo-ShareText $h.Game), (ConvertTo-ShareText $h.Folder), (ConvertTo-ShareText $h.Info)))
            }
        }
        $state.Node.SetSharedServers([string[]]$lines.ToArray())
    }

    function Start-ServerScan([string[]]$targetIps = $null, [int[]]$customPorts = $null, [bool]$skipAlive = $false, $full = $null) {
        if ($state.Scanner -and -not $state.Scanner.Finished) { return }
        $ips = $targetIps
        if (-not $ips) {
            if (-not $state.Adapter) {
                $sel = Select-PelNetworkAdapter -ParentForm $form
                if (-not $sel) { return }
                Set-Adapter $sel
            }
            $maxHosts = 1022
            if ($chkDeep.Checked) { $maxHosts = 65534 }
            $ips = [EarthNet]::HostRange($state.Adapter.Ip, $state.Adapter.Mask, $maxHosts)
        }
        if ($ips.Count -eq 0) {
            Show-Msg "Das Subnetz des Adapters enthält keine scannbaren Hosts." "Server Browser"
            return
        }
        $manual = ($skipAlive -or ($customPorts -and $customPorts.Count -gt 0))
        if ($manual -and -not $chkUnknown.Checked) { $chkUnknown.Checked = $true }
        $keepPeer = @{}
        foreach ($kv in @($state.HitMap.GetEnumerator())) { if ($kv.Value.Source -eq 'peer') { $keepPeer[$kv.Key] = $kv.Value } }
        $state.HitMap = $keepPeer
        $lvHits.Items.Clear()
        $ownIpLocal = ''
        if ($state.Adapter) { $ownIpLocal = $state.Adapter.Ip }
        if ($ownIpLocal -and ($ips -contains $ownIpLocal)) {
            [void](Add-LocalListenerHits $ownIpLocal $customPorts)
            Update-HitList
        }
        $sc = New-Object EarthGameScanner
        $sc.Ips = [string[]]$ips
        $selfIp = ''
        if ($state.Adapter) { $selfIp = $state.Adapter.Ip }
        $sc.SelfIps = [string[]]@($selfIp)
        $sc.IgnoredPorts = $ignoredPorts
        $sc.TcpDb = [string[]]$tcpDbLines
        if ($customPorts -and $customPorts.Count -gt 0) { $sc.CustomPorts = $customPorts }
        $sc.SkipAliveCheck = $skipAlive
        if (-not $targetIps -and $state.Adapter) {
            $prio = [System.Collections.Generic.List[string]]::new()
            if ($state.Node) { try { foreach ($pip in @($state.Node.GetPeerIps())) { $prio.Add([string]$pip) } } catch { } }
            foreach ($pkv in @($state.HitMap.GetEnumerator())) { if ($pkv.Value.Source -eq 'peer') { $prio.Add([string]$pkv.Value.Ip) } }
            try {
                foreach ($nb in @(Get-NetNeighbor -AddressFamily IPv4 -ErrorAction Stop)) {
                    if ([string]$nb.State -in @('Reachable', 'Stale', 'Delay', 'Probe', 'Permanent')) { $prio.Add([string]$nb.IPAddress) }
                }
            } catch { }
            foreach ($x in [EarthNet]::HostRange($state.Adapter.Ip, '255.255.255.0', 254)) { $prio.Add([string]$x) }
            $sc.PriorityIps = [string[]]$prio.ToArray()
        }
        if ($null -ne $full) { $sc.FullScan = [bool]$full } else { $sc.FullScan = [bool]$chkFull.Checked }
        $state.Scanner = $sc
        $state.ScanFinalized = $false
        $btnScan.Enabled = $false
        $lblScan.Text = "Scan gestartet ($($ips.Count) Adressen) ..."
        $pbScan.Value = 0
        $sc.Start()
    }

    # --- Spiel-Suche & Join -----------------------------------------------------------------
    # Beitreten: nutzt die gemeinsame Join-Logik (Invoke-PelJoinGame, oben im Skript), die
    # auch das Control Center ("Wer spielt was" -> "Mitspielen") verwendet. Die Adresse
    # landet dabei immer zusätzlich in der Zwischenablage.
    function Invoke-JoinHit($hit) {
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        try {
            $lblScan.Text = "Starte Spiel ..."
            [System.Windows.Forms.Application]::DoEvents()
            $res = Invoke-PelJoinGame -Ip ([string]$hit.Ip) -Port ([int]$hit.Port) -JoinPort ([int]$hit.JoinPort) -GameName ([string]$hit.Game) -Folder ([string]$hit.Folder) -Key ([string]$hit.Key) -ParentForm $form
            if ($res) { $lblScan.Text = $res }
        } finally {
            $form.Cursor = [System.Windows.Forms.Cursors]::Default
        }
    }

    # --- Server-Manager: Start, Neustart, Überwachung, Statuspflege ------------------------
    function Test-ServerRunning($s) {
        try {
            if (-not $s.Proc) { return $false }
            return (-not $s.Proc.HasExited)
        } catch { return $false }
    }

    function Start-ManagedServer($s) {
        $wd = Split-Path -Parent $s.Path
        $sp = @{ FilePath = $s.Path; WorkingDirectory = $wd; PassThru = $true }
        if ($s.Args) { $sp.ArgumentList = $s.Args }
        $s.Proc = Start-Process @sp
        $s.Started = Get-Date
        $s.ExitedAt = $null
        $s.StopRequested = $false
        if ($s.Item) {
            $s.Item.SubItems[1].Text = [string]$s.Proc.Id
            $s.Item.SubItems[2].Text = 'Läuft'
            $s.Item.SubItems[3].Text = $s.Started.ToString('HH:mm:ss')
            $s.Item.SubItems[4].Text = [string]$s.Restarts
        }
    }

    function Stop-ManagedServer($s) {
        $s.StopRequested = $true
        try {
            if (Test-ServerRunning $s) { & taskkill.exe /PID $s.Proc.Id /T /F 2>&1 | Out-Null }
        } catch { }
        if ($s.Item) { $s.Item.SubItems[2].Text = 'Beendet' }
    }

    function Update-ServerList {
        foreach ($s in $state.Servers) {
            $it = $s.Item
            if (-not $it) { continue }
            if (Test-ServerRunning $s) {
                $it.SubItems[2].Text = 'Läuft'
                $it.ForeColor = [System.Drawing.Color]::LightGreen
            } else {
                if ($s.StopRequested) {
                    $it.SubItems[2].Text = 'Beendet'
                    $it.ForeColor = [System.Drawing.Color]::Gray
                } else {
                    $code = ''
                    try { $code = " (Exit $($s.Proc.ExitCode))" } catch { }
                    $it.SubItems[2].Text = "Beendet/Abgestürzt$code"
                    $it.ForeColor = [System.Drawing.Color]::OrangeRed
                    if ($s.AutoRestart -and $s.Restarts -lt 10) {
                        if (-not $s.ExitedAt) {
                            $s.ExitedAt = Get-Date
                        } elseif (((Get-Date) - $s.ExitedAt).TotalSeconds -ge 3) {
                            $s.Restarts++
                            try { Start-ManagedServer $s } catch { $it.SubItems[2].Text = "Neustart fehlgeschlagen: $($_.Exception.Message)" }
                        }
                    }
                }
            }
            $it.SubItems[4].Text = [string]$s.Restarts
        }
    }

    function Add-FirewallAllow([string]$name, [string]$program, [string[]]$ports) {
        try {
            Get-NetFirewallRule -DisplayName "$name*" -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
            if ($program) {
                New-NetFirewallRule -DisplayName $name -Direction Inbound -Action Allow -Program $program -Profile Any -RemoteAddress LocalSubnet -ErrorAction Stop | Out-Null
            } else {
                New-NetFirewallRule -DisplayName "$name (UDP)" -Direction Inbound -Action Allow -Protocol UDP -LocalPort $ports -Profile Any -RemoteAddress LocalSubnet -ErrorAction Stop | Out-Null
                New-NetFirewallRule -DisplayName "$name (TCP)" -Direction Inbound -Action Allow -Protocol TCP -LocalPort $ports -Profile Any -RemoteAddress LocalSubnet -ErrorAction Stop | Out-Null
            }
            return $true
        } catch {
            Show-Msg "Firewall-Regel konnte nicht erstellt werden:`n$($_.Exception.Message)" "Firewall" ([System.Windows.Forms.MessageBoxIcon]::Error)
            return $false
        }
    }

    function Add-ManagedServer {
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Title = "Dedicated-Server-Datei wählen"
        $ofd.Filter = "Server (*.exe;*.bat;*.cmd)|*.exe;*.bat;*.cmd|Alle Dateien (*.*)|*.*"
        if ($ofd.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
        $s = [pscustomobject]@{
            Name          = [System.IO.Path]::GetFileNameWithoutExtension($ofd.FileName)
            Path          = $ofd.FileName
            Args          = $txtSrvArgs.Text.Trim()
            AutoRestart   = [bool]$chkRestart.Checked
            Proc          = $null
            Started       = $null
            ExitedAt      = $null
            StopRequested = $false
            Restarts      = 0
            Item          = $null
        }
        $it = New-Object System.Windows.Forms.ListViewItem($s.Name)
        [void]$it.SubItems.Add('-')
        [void]$it.SubItems.Add('Startet ...')
        [void]$it.SubItems.Add('-')
        [void]$it.SubItems.Add('0')
        [void]$it.SubItems.Add($s.Path)
        $it.Tag = $s
        $s.Item = $it
        [void]$lvServers.Items.Add($it)
        $state.Servers.Add($s)
        try {
            Start-ManagedServer $s
        } catch {
            $it.SubItems[2].Text = "Fehler: $($_.Exception.Message)"
            $s.StopRequested = $true
        }
    }

    # ===================================================================================
    # GUI
    # ===================================================================================
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Server-Manager & Game Server Browser"
    $form.Size = New-Object System.Drawing.Size(1010, 730)
    $form.MinimumSize = New-Object System.Drawing.Size(760, 480)
    $form.StartPosition = "CenterParent"
    $form.FormBorderStyle = "Sizable"
    $form.MaximizeBox = $true
    $form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $form.ForeColor = $cWhite

    $btnNav0 = New-DkButton "Game Server Browser" 12 10 220 34 $true
    $btnNav1 = New-DkButton "Server-Manager" 240 10 200 34
    $btnNav2 = New-DkButton "P2P / Text Chat (Port 9872)" 448 10 250 34
    $lblAdapter = New-DkLabel "Adapter: (keiner gewählt)" 710 18 280 22
    $lblAdapter.ForeColor = [System.Drawing.Color]::LightGray

    $panels = @()
    for ($i = 0; $i -lt 3; $i++) {
        $p = New-Object System.Windows.Forms.Panel
        $p.Location = New-Object System.Drawing.Point(12, 55)
        $p.Size = New-Object System.Drawing.Size(970, 630)
        $p.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
        $p.Visible = ($i -eq 0)
        $p.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
        $panels += $p
    }
    $pnlBrowser = $panels[0]
    $pnlManager = $panels[1]
    $pnlP2P     = $panels[2]

    function Set-SmAnchor($ctrl, [string[]]$sides) {
        $a = [System.Windows.Forms.AnchorStyles]::None
        foreach ($s in $sides) { $a = $a -bor [System.Windows.Forms.AnchorStyles]::$s }
        $ctrl.Anchor = $a
    }

    # ---- Panel 1: Game Server Browser ------------------------------------------------
    # Netzwerkadapter-Auswahl wurde zentralisiert (Control Center -> Live-Status ->
    # "Adapter wechseln"); dieses Panel übernimmt den zentral gewählten Adapter automatisch.
    $btnScan     = New-DkButton "Server Browser (Game-Ports scannen)" 0 0 400 36 $true
    $btnScanStop = New-DkButton "Stopp" 410 0 90 36
    $chkFull     = New-DkCheck "Vollscan (alle Ports 1024-49151)" 700 0 260 $true
    $chkUnknown  = New-DkCheck "Unbekannte Dienste anzeigen" 700 22 260 $false
    $chkDeep     = New-DkCheck "Ganzes Subnetz (auch /16)" 700 44 260 $true
    $lblScan     = New-DkLabel "Bereit." 0 44 690 20
    $pbScan = New-Object System.Windows.Forms.ProgressBar
    $pbScan.Location = New-Object System.Drawing.Point(0, 68)
    $pbScan.Size = New-Object System.Drawing.Size(960, 14)
    $pbScan.Minimum = 0
    $pbScan.Maximum = 100
    $lvHits = New-DkListView 0 134 960 376 @('IP-Adresse','Spiel','Port','Protokoll','Server-Info') @(170,220,70,110,380)
    $lblManIp    = New-DkLabel "IP:" 0 97 24 22
    $txtManIp    = New-DkText 26 93 150 26
    $lblManPort  = New-DkLabel "Port(s):" 186 97 60 22
    $txtManPorts = New-DkText 248 93 190 26
    $btnManIp     = New-DkButton "1. IP-Suche" 450 88 150 34
    $btnManSubnet = New-DkButton "2. Ganzes Subnetz" 610 88 170 34
    $btnManPort   = New-DkButton "3. Port-Suche" 790 88 170 34
    $tip = New-Object System.Windows.Forms.ToolTip
    $tip.SetToolTip($txtManPorts, "Ein Port (27015), Bereich (27000-27100) oder Liste (7777,25565). Leer = alle Ports.")
    $tip.SetToolTip($txtManIp, "Ziel-IP für Button 1 (bei Button 3 optional: leer = ganzes Subnetz).")
    $btnJoin = New-DkButton "Join: Spiel automatisch suchen & verbinden" 0 522 350 42 $true
    $btnCopy = New-DkButton "IP:Port kopieren" 360 522 170 42
    $lblCount = New-DkLabel "Gefundene Einträge: 0" 545 534 150 22
    $lblNote = New-DkLabel "Ignoriert werden Windows-, Linux- und macOS-Systemports (SMB, RDP, SSH, mDNS, AirPlay ...). UDP-Server werden nur erkannt, wenn sie auf ein bekanntes Abfrageprotokoll antworten (Source/A2S, Minecraft Bedrock, Quake3); TCP-Ports werden über die Spiel-Tabelle zugeordnet." 0 594 960 36
    $lblMgr = New-DkLabel "Manager-Verbund (Port 9872, Server-Listen-Austausch): kein Adapter gewählt" 0 570 700 20
    $chkShare = New-DkCheck "Server mit Managern teilen" 700 532 260 $true
    $lblNote.ForeColor = [System.Drawing.Color]::LightGray
    Set-SmAnchor $lvHits @('Top','Left','Right','Bottom')
    Set-SmAnchor $btnJoin @('Left','Bottom')
    Set-SmAnchor $btnCopy @('Left','Bottom')
    Set-SmAnchor $lblCount @('Left','Bottom')
    Set-SmAnchor $chkShare @('Left','Bottom')
    Set-SmAnchor $lblMgr @('Left','Bottom')
    Set-SmAnchor $lblNote @('Left','Right','Bottom')
    $pnlBrowser.Controls.AddRange(@($btnScan, $btnScanStop, $chkFull, $chkUnknown, $chkDeep, $lblScan, $pbScan, $lblManIp, $txtManIp, $lblManPort, $txtManPorts, $btnManIp, $btnManSubnet, $btnManPort, $lvHits, $btnJoin, $btnCopy, $lblCount, $chkShare, $lblMgr, $lblNote))

    # ---- Panel 2: Server-Manager -----------------------------------------------------
    $btnSrvAdd = New-DkButton "Dedicated-Server wählen & starten" 0 0 290 36 $true
    $lblArgs = New-DkLabel "Startparameter:" 305 9 110 22
    $txtSrvArgs = New-DkText 420 6 330 26
    $chkRestart = New-DkCheck "Bei Absturz automatisch neu starten" 765 8 200 $true
    $lvServers = New-DkListView 0 50 960 470 @('Name','PID','Status','Gestartet','Neustarts','Pfad') @(180,70,200,90,80,330)
    $btnSrvStop    = New-DkButton "Ausgewählte beenden" 0 530 190 38
    $btnSrvRestart = New-DkButton "Neu starten" 200 530 130 38
    $btnSrvStopAll = New-DkButton "Alle beenden" 340 530 130 38
    $btnSrvDir     = New-DkButton "Ordner öffnen" 480 530 130 38
    $btnSrvFwProg  = New-DkButton "Firewall: Programm" 620 530 170 38 $true
    $btnSrvFwPort  = New-DkButton "Firewall: Port" 800 530 160 38 $true
    Set-SmAnchor $lvServers @('Top','Left','Right','Bottom')
    Set-SmAnchor $btnSrvStop @('Left','Bottom')
    Set-SmAnchor $btnSrvRestart @('Left','Bottom')
    Set-SmAnchor $btnSrvStopAll @('Left','Bottom')
    Set-SmAnchor $btnSrvDir @('Left','Bottom')
    Set-SmAnchor $btnSrvFwProg @('Left','Bottom')
    Set-SmAnchor $btnSrvFwPort @('Left','Bottom')
    Set-SmAnchor $chkRestart @('Right','Top')
    $pnlManager.Controls.AddRange(@($btnSrvAdd, $lblArgs, $txtSrvArgs, $chkRestart, $lvServers, $btnSrvStop, $btnSrvRestart, $btnSrvStopAll, $btnSrvDir, $btnSrvFwProg, $btnSrvFwPort))

    # ---- Panel 3: P2P / Chat ---------------------------------------------------------
    $btnAdapter3 = New-DkButton "1. Netzwerkadapter einstellen" 0 0 240 36
    $lblIp = New-DkLabel "IP:" 250 10 24 22
    $txtIp = New-DkText 275 7 150 26
    $btnConnect = New-DkButton "2. Verbinden (Port 9872)" 435 0 220 36 $true
    $btnNetScan = New-DkButton "Netz scannen" 665 0 140 36
    $btnChat = New-DkButton "3. Text Chat" 815 0 145 36 $true
    $lblNode = New-DkLabel "Port 9872: geschlossen" 0 44 960 20
    $lvPeers = New-DkListView 0 70 960 128 @('Name','IP-Adresse','Status') @(360,200,300)
    $lblChatHint = New-DkLabel "Mit Button 3 den Text Chat öffnen. Gechattet wird mit allen verbundenen Project Earth LAN Managern." 0 235 960 22
    $lblChatHint.ForeColor = [System.Drawing.Color]::LightGray
    $rtbChat = New-Object System.Windows.Forms.RichTextBox
    $rtbChat.Location = New-Object System.Drawing.Point(0, 230)
    $rtbChat.Size = New-Object System.Drawing.Size(960, 300)
    $rtbChat.ReadOnly = $true
    $rtbChat.BackColor = $cList
    $rtbChat.ForeColor = $cWhite
    $rtbChat.Font = $fontMain
    $rtbChat.Visible = $false
    $txtChat = New-DkText 0 540 860 28
    $txtChat.Visible = $false
    $btnSend = New-DkButton "Senden" 870 537 90 32 $true
    $btnSend.Visible = $false
    $pnlP2P.Controls.AddRange(@($btnAdapter3, $lblIp, $txtIp, $btnConnect, $btnNetScan, $btnChat, $lblNode, $lvPeers, $lblChatHint, $rtbChat, $txtChat, $btnSend))

    $form.Controls.AddRange(@($btnNav0, $btnNav1, $lblAdapter, $pnlBrowser, $pnlManager))

    # ---- Panelwechsel -------------------------------------------------------------------
    function Show-Panel([int]$idx) {
        $state.Panel = $idx
        for ($i = 0; $i -lt 3; $i++) { $panels[$i].Visible = ($i -eq $idx) }
        $navs = @($btnNav0, $btnNav1, $btnNav2)
        for ($i = 0; $i -lt 3; $i++) {
            if ($i -eq $idx) { $navs[$i].BackColor = $cAccent } else { $navs[$i].BackColor = $cBtn }
        }
        if ($idx -eq 2) {
            if (-not $state.Adapter) {
                $lblNode.Text = "Port 9872: geschlossen - bitte zuerst Button 1 (Netzwerkadapter) klicken."
            } elseif (-not $state.Node) {
                Start-LanNode
            }
        }
    }

    # ---- Ereignisse: Navigation ---------------------------------------------------------
    $btnNav0.Add_Click({ Show-Panel 0 })
    $btnNav1.Add_Click({ Show-Panel 1 })
    $btnNav2.Add_Click({ Show-Panel 2 })

    # ---- Ereignisse: Browser -------------------------------------------------------------
    $btnScan.Add_Click({ Start-ServerScan })
    $btnScanStop.Add_Click({ if ($state.Scanner) { $state.Scanner.Cancel() } })

    # Manuelle Suche: 1 = eine IP, 2 = ganzes Subnetz, 3 = Port(s)
    $btnManIp.Add_Click({
        $ipText = Get-ManualIp
        if (-not $ipText) { Show-Msg "Bitte eine gültige IPv4-Adresse eingeben (z. B. 10.147.17.5)."; return }
        $ports = ConvertTo-PortList $txtManPorts.Text
        if ($null -eq $ports) { Show-Msg "Ungültige Port-Angabe. Beispiele: 27015 | 27000-27100 | 7777,25565"; return }
        if ($ports.Count -gt 0) { Start-ServerScan -TargetIps @($ipText) -CustomPorts $ports -SkipAlive $true -Full $false }
        else { Start-ServerScan -TargetIps @($ipText) -SkipAlive $true -Full $true }
    })

    $btnManSubnet.Add_Click({
        $ports = ConvertTo-PortList $txtManPorts.Text
        if ($null -eq $ports) { Show-Msg "Ungültige Port-Angabe. Beispiele: 27015 | 27000-27100 | 7777,25565"; return }
        if ($ports.Count -gt 0) { Start-ServerScan -CustomPorts $ports }
        else { Start-ServerScan }
    })

    $btnManPort.Add_Click({
        $ports = ConvertTo-PortList $txtManPorts.Text
        if ($null -eq $ports -or $ports.Count -eq 0) { Show-Msg "Bitte Port(s) eingeben. Beispiele: 27015 | 27000-27100 | 7777,25565"; return }
        if ($txtManIp.Text.Trim()) {
            $ipText = Get-ManualIp
            if (-not $ipText) { Show-Msg "Die eingegebene IP-Adresse ist ungültig."; return }
            Start-ServerScan -TargetIps @($ipText) -CustomPorts $ports -SkipAlive $true -Full $false
        } else {
            Start-ServerScan -CustomPorts $ports
        }
    })
    $chkUnknown.Add_CheckedChanged({ Update-HitList })

    $btnJoin.Add_Click({
        if ($lvHits.SelectedItems.Count -eq 0) {
            Show-Msg "Bitte zuerst einen Server in der Liste auswählen."
            return
        }
        Invoke-JoinHit $lvHits.SelectedItems[0].Tag
    })
    $lvHits.Add_DoubleClick({ $btnJoin.PerformClick() })

    $btnCopy.Add_Click({
        if ($lvHits.SelectedItems.Count -eq 0) { return }
        $t = $lvHits.SelectedItems[0].Tag
        $copyAddr = Get-PelJoinAddress -Ip ([string]$t.Ip) -Port ([int]$t.Port) -JoinPort ([int]$t.JoinPort) -GameName ([string]$t.Game) -Folder ([string]$t.Folder) -Key ([string]$t.Key)
        if (Set-PelClipboard $copyAddr) { $lblScan.Text = "Kopiert: $copyAddr" } else { $lblScan.Text = "Kopieren fehlgeschlagen - Adresse: $copyAddr" }
    })

    # ---- Ereignisse: Server-Manager ---------------------------------------------------------
    $btnSrvAdd.Add_Click({ Add-ManagedServer })

    $btnSrvStop.Add_Click({
        foreach ($it in @($lvServers.SelectedItems)) { Stop-ManagedServer $it.Tag }
    })

    $btnSrvRestart.Add_Click({
        foreach ($it in @($lvServers.SelectedItems)) {
            $s = $it.Tag
            Stop-ManagedServer $s
            Start-Sleep -Milliseconds 700
            $s.Restarts++
            try { Start-ManagedServer $s } catch { $it.SubItems[2].Text = "Neustart fehlgeschlagen: $($_.Exception.Message)" }
        }
    })

    $btnSrvStopAll.Add_Click({
        foreach ($s in $state.Servers) { Stop-ManagedServer $s }
    })


    $btnSrvFwProg.Add_Click({
        $sel = @($lvServers.SelectedItems)
        if ($sel.Count -eq 0) { Show-Msg "Bitte zuerst einen Server in der Liste auswählen."; return }
        foreach ($it in $sel) {
            $s = $it.Tag
            if ($s.Path -match '(?i)\.(bat|cmd)$') {
                Show-Msg "Für .bat/.cmd-Server bitte 'Firewall: Port' verwenden (eine Programm-Regel würde sonst für cmd.exe gelten)."
                continue
            }
            if (Add-FirewallAllow "Project Earth LAN Server - $($s.Name)" $s.Path @()) {
                Show-Msg "Eingehende Verbindungen (UDP und TCP) für '$($s.Name)' sind jetzt im lokalen Subnetz erlaubt."
            }
        }
    })

    $btnSrvFwPort.Add_Click({
        Add-Type -AssemblyName Microsoft.VisualBasic
        $txt = [Microsoft.VisualBasic.Interaction]::InputBox("Port(s) für eingehende Verbindungen (UDP und TCP), z. B. 27888 oder 27000-27100 oder 7777,25565:", "Firewall: Port freigeben", "27888")
        if (-not $txt) { return }
        $parts = @($txt -split '[,;\s]+' | Where-Object { $_ })
        if ($parts.Count -eq 0) { return }
        foreach ($pt in $parts) {
            if ($pt -notmatch '^\d{1,5}(-\d{1,5})?$') { Show-Msg "Ungültige Port-Angabe: $pt"; return }
        }
        if (Add-FirewallAllow "Project Earth LAN Port $txt" '' ([string[]]$parts)) {
            Show-Msg "Port(s) $txt sind jetzt für UDP und TCP im lokalen Subnetz freigegeben."
        }
    })

    $btnSrvDir.Add_Click({
        foreach ($it in @($lvServers.SelectedItems)) {
            $p = $it.Tag.Path
            try { Start-Process explorer.exe -ArgumentList "/select,`"$p`"" } catch { }
        }
    })

    # ---- Ereignisse: P2P / Chat -------------------------------------------------------------
    $btnAdapter3.Add_Click({ Invoke-AdapterButton })

    $btnConnect.Add_Click({
        $ipText = $txtIp.Text.Trim()
        $parsed = $null
        if (-not [System.Net.IPAddress]::TryParse($ipText, [ref]$parsed) -or $parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
            Show-Msg "Bitte eine gültige IPv4-Adresse eingeben (z. B. 10.147.17.5)."
            return
        }
        if (-not $state.Node) {
            if (-not $state.Adapter) { Show-Msg "Bitte zuerst Button 1 (Netzwerkadapter) verwenden."; return }
            Start-LanNode
        }
        if ($state.Node) {
            $state.Node.ConnectTo($ipText)
            Add-ChatLine "Verbinde zu ${ipText}:9872 ..." ([System.Drawing.Color]::LightGray)
        }
    })

    $btnNetScan.Add_Click({
        if (-not $state.Node) {
            if (-not $state.Adapter) { Show-Msg "Bitte zuerst Button 1 (Netzwerkadapter) verwenden."; return }
            Start-LanNode
            return
        }
        $ips = [EarthNet]::HostRange($state.Adapter.Ip, $state.Adapter.Mask, 1022)
        $state.Node.ScanAsync([string[]]$ips)
        Add-ChatLine "Scanne Netzwerk nach Port 9872 ..." ([System.Drawing.Color]::LightGray)
    })

    $btnChat.Add_Click({
        $show = -not $rtbChat.Visible
        $rtbChat.Visible = $show
        $txtChat.Visible = $show
        $btnSend.Visible = $show
        $lblChatHint.Visible = -not $show
        if ($show) {
            $state.Unread = 0
            $btnChat.Text = "3. Text Chat"
            $txtChat.Focus()
        }
    })

    $btnSend.Add_Click({
        $text = $txtChat.Text.Trim()
        if (-not $text) { return }
        if (-not $state.Node) {
            Show-Msg "Port 9872 ist nicht geöffnet. Bitte zuerst Button 1 (Netzwerkadapter) verwenden."
            return
        }
        $count = $state.Node.Broadcast($text)
        Add-ChatLine ("Ich: " + $text) ([System.Drawing.Color]::LightSkyBlue)
        if ($count -eq 0) { Add-ChatLine "(Kein anderer Manager verbunden - Nachricht wurde nicht zugestellt.)" ([System.Drawing.Color]::Orange) }
        $txtChat.Clear()
    })

    $txtChat.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            $_.SuppressKeyPress = $true
            $btnSend.PerformClick()
        }
    })

    # ---- Haupt-Timer: Scanner, P2P-Ereignisse, Server-Überwachung -------------------------------
    $mainTimer = New-Object System.Windows.Forms.Timer
    $mainTimer.Interval = 250
    $mainTimer.Add_Tick({
        $state.Tick = $state.Tick + 1

        # Scanner
        $sc = $state.Scanner
        if ($sc -and -not $state.ScanFinalized) {
            $fin = $sc.Finished
            $changed = $false
            $h = $null
            while ($sc.Hits.TryDequeue([ref]$h)) {
                if (Register-Hit $h) { $changed = $true }
            }
            if ($changed) { Update-HitList }
            if ($sc.Phase -eq 1) { $lblScan.Text = "$($sc.Status) ($($sc.HostsChecked)/$($sc.HostsTotal))" } else { $lblScan.Text = $sc.Status }
            $pct = 0
            if ($sc.Phase -eq 1) {
                if ($sc.HostsTotal -gt 0) { $pct = [int](($sc.HostsChecked * 100) / $sc.HostsTotal) }
            } elseif ($sc.HostsAlive -gt 0) {
                $portPart = 0
                if ($sc.PortsTotal -gt 0) { $portPart = [math]::Min(1.0, ($sc.PortsDone / $sc.PortsTotal)) }
                $pct = [int]((($sc.HostsDone + $portPart) * 100) / $sc.HostsAlive)
            }
            $pbScan.Value = [math]::Max(0, [math]::Min(100, $pct))
            if ($fin) {
                $state.ScanFinalized = $true
                $btnScan.Enabled = $true
                $pbScan.Value = 100
                Update-HitList
                $lblScan.Text = "$($sc.Status) Aktive Hosts: $($sc.TotalAlive)"
            }
        }

        # P2P-Ereignisse
        $node = $state.Node
        if ($node) {
            $ev = $null
            $n = 0
            while ($n -lt 200 -and $node.Events.TryDequeue([ref]$ev)) {
                $n++
                $type, $rest = $ev -split '\|', 2
                switch ($type) {
                    'PEER+' {
                        $f = $rest -split '\|', 3
                        if ($state.PeerItems.ContainsKey($f[0])) {
                            $pit = $state.PeerItems[$f[0]]
                            $pit.Text = $f[1]
                            $pit.SubItems[1].Text = $f[2]
                        } else {
                            $pit = New-Object System.Windows.Forms.ListViewItem($f[1])
                            [void]$pit.SubItems.Add($f[2])
                            [void]$pit.SubItems.Add('Verbunden (Manager offen)')
                            $pit.ForeColor = [System.Drawing.Color]::LightGreen
                            [void]$lvPeers.Items.Add($pit)
                            $state.PeerItems[$f[0]] = $pit
                        }
                        Add-ChatLine "$($f[1]) ($($f[2])) ist beigetreten." ([System.Drawing.Color]::LightGreen)
                        Publish-SharedServers
                    }
                    'PEER-' {
                        $f = $rest -split '\|', 3
                        if ($state.PeerItems.ContainsKey($f[0])) {
                            $lvPeers.Items.Remove($state.PeerItems[$f[0]])
                            $state.PeerItems.Remove($f[0])
                        }
                        Add-ChatLine "$($f[1]) hat die Verbindung getrennt." ([System.Drawing.Color]::Orange)
                    }
                    'CHAT' {
                        $f = $rest -split '\|', 2
                        Add-ChatLine ("$($f[0]): $($f[1])") $cWhite
                        if (-not $rtbChat.Visible) {
                            $state.Unread = $state.Unread + 1
                            $btnChat.Text = "3. Text Chat ($($state.Unread) neu)"
                        }
                    }
                    'SYS' {
                        Add-ChatLine $rest ([System.Drawing.Color]::LightGray)
                    }
                    'SRV' {
                        $f = $rest -split '\|', 8
                        if ($f.Count -ge 8) {
                            $ipP = $null
                            $ptP = 0
                            if ([System.Net.IPAddress]::TryParse($f[1], [ref]$ipP) -and $ipP.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and [int]::TryParse($f[2], [ref]$ptP) -and $ptP -ge 1 -and $ptP -le 65535) {
                                $sh = New-Object EarthServerHit
                                $sh.Ip = $f[1]
                                $sh.Port = $ptP
                                $sh.Protocol = $f[3]
                                $sh.Key = $f[4]
                                $sh.Game = $f[5]
                                $sh.Folder = $f[6]
                                $sh.Info = "$($f[7])  [von $($f[0])]"
                                $sh.Source = 'peer'
                                $sh.Seen = [Environment]::TickCount
                                if (Register-Hit $sh) { Update-HitList }
                            }
                        }
                    }
                }
            }
            $scanText = ''
            if ($node.ScanRunning) { $scanText = " | Scan: $($node.ScanDone)/$($node.ScanTotal)" }
            $lblNode.Text = "Port 9872 offen auf $($node.BindIp) | Verbundene Manager: $($node.PeerCount())$scanText"
            $lblMgr.Text = "Manager-Verbund (Port 9872, Server-Listen-Austausch): $($node.PeerCount()) Manager verbunden$scanText"
        }

        # Server-Listen teilen (alle ca. 10 s) und abgelaufene Manager-Einträge entfernen
        if ($state.Node -and (($state.Tick % 40) -eq 1)) { Publish-SharedServers }
        if (($state.Tick % 20) -eq 0) {
            $nowTick = [Environment]::TickCount
            $expired = @()
            foreach ($ekv in @($state.HitMap.GetEnumerator())) {
                if ($ekv.Value.Source -eq 'peer' -and (($nowTick - $ekv.Value.Seen) -gt 45000)) { $expired += $ekv.Key }
            }
            if ($expired.Count -gt 0) {
                foreach ($ek in $expired) { $state.HitMap.Remove($ek) }
                Update-HitList
            }
        }

        # Server-Überwachung (ca. alle 1,5 Sekunden)
        if (($state.Tick % 6) -eq 0 -and $state.Servers.Count -gt 0) { Update-ServerList }

        # Live-Übernahme eines im Control Center (Live-Status) gewechselten Adapters:
        # alle ca. 5 Sekunden prüfen und den LAN-Knoten (Port 9872) bei Bedarf automatisch
        # auf dem neuen Adapter neu starten - ohne dieses Fenster neu öffnen zu müssen.
        if (($state.Tick % 20) -eq 0) {
            $centralNow = Get-PelSelectedAdapter
            if ($centralNow -and (-not $state.Adapter -or $centralNow.Ip -ne $state.Adapter.Ip)) {
                Set-Adapter $centralNow
                Add-ChatLine "Adapter im Control Center gewechselt -> $($centralNow.Name) ($($centralNow.Ip)). LAN-Knoten wird neu gestartet ..." ([System.Drawing.Color]::LightGray)
            }
        }
    })
    $mainTimer.Start()

    # ---- Schließen ---------------------------------------------------------------------------
    $form.Add_FormClosing({
        $mainTimer.Stop()
        if ($state.Scanner) { $state.Scanner.Cancel() }
        if ($state.Node) { try { $state.Node.Stop() } catch { }; $state.Node = $null }
        if ($state.FwRule) { Set-LanFirewallRule $false }
        $running = @($state.Servers | Where-Object { Test-ServerRunning $_ })
        if ($running.Count -gt 0) {
            $answer = [System.Windows.Forms.MessageBox]::Show("Es laufen noch $($running.Count) Dedicated-Server. Jetzt beenden?", "Server-Manager", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
                foreach ($s in $running) { Stop-ManagedServer $s }
            }
        }
    })

    # ---- Start ---------------------------------------------------------------------------------
    try {
        # Adapter wird zentral im Control Center (Live-Status) gewählt. Ist dort schon
        # einer eingestellt, wird er hier automatisch übernommen - ohne eigenen Button.
        $centralAdapter = Get-PelSelectedAdapter
        if (-not $centralAdapter) {
            # Noch nichts zentral gewählt: automatisch den Adapter mit der niedrigsten
            # Schnittstellenmetrik nehmen (= von Windows bevorzugte Verbindung) und gleich
            # zentral speichern, damit Option 9/10 und das Control Center ab sofort
            # denselben Adapter verwenden.
            $centralAdapter = Get-PelAutoAdapter
            if ($centralAdapter) { Save-PelSelectedAdapter $centralAdapter }
        }
        if ($centralAdapter) {
            Connect-PelZeroTierNetwork -Adapter $centralAdapter
            Set-Adapter $centralAdapter
        }
        else { $lblAdapter.Text = "Adapter: keiner verfügbar - bitte im Control Center (Live-Status) wählen" }
    } catch { }
    Show-Panel 0
    [void]$form.ShowDialog()

    $mainTimer.Dispose()
}


function Initialize-VoiceTypes {
    if (-not ('EarthVoiceNode' -as [type])) {
        $voiceCode = @'
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

public static class EarthVoiceNet
{
    public static uint ToUInt(IPAddress a)
    {
        byte[] b = a.GetAddressBytes();
        return ((uint)b[0] << 24) | ((uint)b[1] << 16) | ((uint)b[2] << 8) | (uint)b[3];
    }

    public static string FromUInt(uint v)
    {
        return string.Format("{0}.{1}.{2}.{3}", (v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255);
    }
}

public static class EarthWinmm
{
    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);

    public const int CALLBACK_EVENT = 0x00050000;
    public const uint WHDR_DONE = 0x00000001;

    [StructLayout(LayoutKind.Sequential)]
    public struct WAVEFORMATEX
    {
        public ushort wFormatTag;
        public ushort nChannels;
        public uint nSamplesPerSec;
        public uint nAvgBytesPerSec;
        public ushort nBlockAlign;
        public ushort wBitsPerSample;
        public ushort cbSize;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct WAVEHDR
    {
        public IntPtr lpData;
        public uint dwBufferLength;
        public uint dwBytesRecorded;
        public IntPtr dwUser;
        public uint dwFlags;
        public uint dwLoops;
        public IntPtr lpNext;
        public IntPtr reserved;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct WAVEINCAPS
    {
        public ushort wMid;
        public ushort wPid;
        public uint vDriverVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string szPname;
        public uint dwFormats;
        public ushort wChannels;
        public ushort wReserved1;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct WAVEOUTCAPS
    {
        public ushort wMid;
        public ushort wPid;
        public uint vDriverVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string szPname;
        public uint dwFormats;
        public ushort wChannels;
        public ushort wReserved1;
        public uint dwSupport;
    }

    [DllImport("winmm.dll")] public static extern int waveInGetNumDevs();
    [DllImport("winmm.dll", CharSet = CharSet.Auto)] public static extern int waveInGetDevCaps(IntPtr uDeviceID, ref WAVEINCAPS pwic, int cbwic);
    [DllImport("winmm.dll")] public static extern int waveInOpen(out IntPtr phwi, int uDeviceID, ref WAVEFORMATEX pwfx, IntPtr dwCallback, IntPtr dwInstance, int fdwOpen);
    [DllImport("winmm.dll")] public static extern int waveInClose(IntPtr hwi);
    [DllImport("winmm.dll")] public static extern int waveInPrepareHeader(IntPtr hwi, IntPtr pwh, int cbwh);
    [DllImport("winmm.dll")] public static extern int waveInUnprepareHeader(IntPtr hwi, IntPtr pwh, int cbwh);
    [DllImport("winmm.dll")] public static extern int waveInAddBuffer(IntPtr hwi, IntPtr pwh, int cbwh);
    [DllImport("winmm.dll")] public static extern int waveInStart(IntPtr hwi);
    [DllImport("winmm.dll")] public static extern int waveInReset(IntPtr hwi);

    [DllImport("winmm.dll")] public static extern int waveOutGetNumDevs();
    [DllImport("winmm.dll", CharSet = CharSet.Auto)] public static extern int waveOutGetDevCaps(IntPtr uDeviceID, ref WAVEOUTCAPS pwoc, int cbwoc);
    [DllImport("winmm.dll")] public static extern int waveOutOpen(out IntPtr phwo, int uDeviceID, ref WAVEFORMATEX pwfx, IntPtr dwCallback, IntPtr dwInstance, int fdwOpen);
    [DllImport("winmm.dll")] public static extern int waveOutClose(IntPtr hwo);
    [DllImport("winmm.dll")] public static extern int waveOutPrepareHeader(IntPtr hwo, IntPtr pwh, int cbwh);
    [DllImport("winmm.dll")] public static extern int waveOutUnprepareHeader(IntPtr hwo, IntPtr pwh, int cbwh);
    [DllImport("winmm.dll")] public static extern int waveOutWrite(IntPtr hwo, IntPtr pwh, int cbwh);
    [DllImport("winmm.dll")] public static extern int waveOutReset(IntPtr hwo);

    public static string[] InputDeviceNames()
    {
        List<string> l = new List<string>();
        l.Add("Standardgeraet (Windows)");
        int n = waveInGetNumDevs();
        for (int i = 0; i < n; i++)
        {
            WAVEINCAPS c = new WAVEINCAPS();
            if (waveInGetDevCaps((IntPtr)i, ref c, Marshal.SizeOf(typeof(WAVEINCAPS))) == 0) l.Add(c.szPname);
            else l.Add("Geraet " + i);
        }
        return l.ToArray();
    }

    public static string[] OutputDeviceNames()
    {
        List<string> l = new List<string>();
        l.Add("Standardgeraet (Windows)");
        int n = waveOutGetNumDevs();
        for (int i = 0; i < n; i++)
        {
            WAVEOUTCAPS c = new WAVEOUTCAPS();
            if (waveOutGetDevCaps((IntPtr)i, ref c, Marshal.SizeOf(typeof(WAVEOUTCAPS))) == 0) l.Add(c.szPname);
            else l.Add("Geraet " + i);
        }
        return l.ToArray();
    }

    public static EarthWinmm.WAVEFORMATEX Format16kMono()
    {
        EarthWinmm.WAVEFORMATEX fmt = new EarthWinmm.WAVEFORMATEX();
        fmt.wFormatTag = 1;
        fmt.nChannels = 1;
        fmt.nSamplesPerSec = 16000;
        fmt.wBitsPerSample = 16;
        fmt.nBlockAlign = 2;
        fmt.nAvgBytesPerSec = 32000;
        fmt.cbSize = 0;
        return fmt;
    }
}

public class EarthAudioIn
{
    public const int FrameSamples = 320;
    private const int BufferCount = 4;
    public Action<short[]> OnFrame;
    private IntPtr hwi = IntPtr.Zero;
    private AutoResetEvent evt = new AutoResetEvent(false);
    private IntPtr[] hdrs;
    private IntPtr[] bufs;
    private Thread thread;
    private volatile bool running;

    public string Start(int deviceId)
    {
        Stop();
        EarthWinmm.WAVEFORMATEX fmt = EarthWinmm.Format16kMono();
        IntPtr h;
        int r = EarthWinmm.waveInOpen(out h, deviceId, ref fmt, evt.SafeWaitHandle.DangerousGetHandle(), IntPtr.Zero, EarthWinmm.CALLBACK_EVENT);
        if (r != 0) return "Mikrofon konnte nicht geoeffnet werden (Fehlercode " + r + ")";
        hwi = h;
        int hdrSize = Marshal.SizeOf(typeof(EarthWinmm.WAVEHDR));
        hdrs = new IntPtr[BufferCount];
        bufs = new IntPtr[BufferCount];
        for (int i = 0; i < BufferCount; i++)
        {
            bufs[i] = Marshal.AllocHGlobal(FrameSamples * 2);
            EarthWinmm.WAVEHDR hd = new EarthWinmm.WAVEHDR();
            hd.lpData = bufs[i];
            hd.dwBufferLength = (uint)(FrameSamples * 2);
            hdrs[i] = Marshal.AllocHGlobal(hdrSize);
            Marshal.StructureToPtr(hd, hdrs[i], false);
            EarthWinmm.waveInPrepareHeader(hwi, hdrs[i], hdrSize);
            EarthWinmm.waveInAddBuffer(hwi, hdrs[i], hdrSize);
        }
        running = true;
        EarthWinmm.waveInStart(hwi);
        thread = new Thread(Loop);
        thread.IsBackground = true;
        thread.Priority = ThreadPriority.AboveNormal;
        thread.Start();
        return null;
    }

    private void Loop()
    {
        int hdrSize = Marshal.SizeOf(typeof(EarthWinmm.WAVEHDR));
        int flagsOffset = (int)Marshal.OffsetOf(typeof(EarthWinmm.WAVEHDR), "dwFlags");
        int recOffset = (int)Marshal.OffsetOf(typeof(EarthWinmm.WAVEHDR), "dwBytesRecorded");
        while (running)
        {
            evt.WaitOne(100);
            if (!running) break;
            for (int i = 0; i < hdrs.Length; i++)
            {
                uint flags = (uint)Marshal.ReadInt32(hdrs[i], flagsOffset);
                if ((flags & EarthWinmm.WHDR_DONE) != 0)
                {
                    int rec = Marshal.ReadInt32(hdrs[i], recOffset);
                    if (rec > 1 && OnFrame != null)
                    {
                        short[] frame = new short[rec / 2];
                        Marshal.Copy(bufs[i], frame, 0, rec / 2);
                        try { OnFrame(frame); } catch (Exception) { }
                    }
                    if (running) EarthWinmm.waveInAddBuffer(hwi, hdrs[i], hdrSize);
                }
            }
        }
    }

    public void Stop()
    {
        running = false;
        if (thread != null) { thread.Join(500); thread = null; }
        if (hwi != IntPtr.Zero)
        {
            int hdrSize = Marshal.SizeOf(typeof(EarthWinmm.WAVEHDR));
            EarthWinmm.waveInReset(hwi);
            if (hdrs != null)
            {
                for (int i = 0; i < hdrs.Length; i++)
                {
                    EarthWinmm.waveInUnprepareHeader(hwi, hdrs[i], hdrSize);
                    Marshal.FreeHGlobal(hdrs[i]);
                    Marshal.FreeHGlobal(bufs[i]);
                }
            }
            EarthWinmm.waveInClose(hwi);
            hwi = IntPtr.Zero;
            hdrs = null;
            bufs = null;
        }
    }
}

public class EarthAudioOut
{
    public const int FrameSamples = 320;
    private const int BufferCount = 6;
    public Func<short[]> PullFrame;
    private IntPtr hwo = IntPtr.Zero;
    private AutoResetEvent evt = new AutoResetEvent(false);
    private IntPtr[] hdrs;
    private IntPtr[] bufs;
    private Thread thread;
    private volatile bool running;

    public string Start(int deviceId)
    {
        Stop();
        EarthWinmm.WAVEFORMATEX fmt = EarthWinmm.Format16kMono();
        IntPtr h;
        int r = EarthWinmm.waveOutOpen(out h, deviceId, ref fmt, evt.SafeWaitHandle.DangerousGetHandle(), IntPtr.Zero, EarthWinmm.CALLBACK_EVENT);
        if (r != 0) return "Lautsprecher konnte nicht geoeffnet werden (Fehlercode " + r + ")";
        hwo = h;
        int hdrSize = Marshal.SizeOf(typeof(EarthWinmm.WAVEHDR));
        hdrs = new IntPtr[BufferCount];
        bufs = new IntPtr[BufferCount];
        for (int i = 0; i < BufferCount; i++)
        {
            bufs[i] = Marshal.AllocHGlobal(FrameSamples * 2);
            Marshal.Copy(new short[FrameSamples], 0, bufs[i], FrameSamples);
            EarthWinmm.WAVEHDR hd = new EarthWinmm.WAVEHDR();
            hd.lpData = bufs[i];
            hd.dwBufferLength = (uint)(FrameSamples * 2);
            hdrs[i] = Marshal.AllocHGlobal(hdrSize);
            Marshal.StructureToPtr(hd, hdrs[i], false);
            EarthWinmm.waveOutPrepareHeader(hwo, hdrs[i], hdrSize);
            EarthWinmm.waveOutWrite(hwo, hdrs[i], hdrSize);
        }
        running = true;
        thread = new Thread(Loop);
        thread.IsBackground = true;
        thread.Priority = ThreadPriority.AboveNormal;
        thread.Start();
        return null;
    }

    private void Loop()
    {
        int hdrSize = Marshal.SizeOf(typeof(EarthWinmm.WAVEHDR));
        int flagsOffset = (int)Marshal.OffsetOf(typeof(EarthWinmm.WAVEHDR), "dwFlags");
        while (running)
        {
            evt.WaitOne(100);
            if (!running) break;
            for (int i = 0; i < hdrs.Length; i++)
            {
                uint flags = (uint)Marshal.ReadInt32(hdrs[i], flagsOffset);
                if ((flags & EarthWinmm.WHDR_DONE) != 0)
                {
                    short[] f = null;
                    try { if (PullFrame != null) f = PullFrame(); } catch (Exception) { }
                    if (f == null || f.Length < FrameSamples) f = new short[FrameSamples];
                    Marshal.Copy(f, 0, bufs[i], FrameSamples);
                    if (running) EarthWinmm.waveOutWrite(hwo, hdrs[i], hdrSize);
                }
            }
        }
    }

    public void Stop()
    {
        running = false;
        if (thread != null) { thread.Join(500); thread = null; }
        if (hwo != IntPtr.Zero)
        {
            int hdrSize = Marshal.SizeOf(typeof(EarthWinmm.WAVEHDR));
            EarthWinmm.waveOutReset(hwo);
            if (hdrs != null)
            {
                for (int i = 0; i < hdrs.Length; i++)
                {
                    EarthWinmm.waveOutUnprepareHeader(hwo, hdrs[i], hdrSize);
                    Marshal.FreeHGlobal(hdrs[i]);
                    Marshal.FreeHGlobal(bufs[i]);
                }
            }
            EarthWinmm.waveOutClose(hwo);
            hwo = IntPtr.Zero;
            hdrs = null;
            bufs = null;
        }
    }
}

public class EarthVoicePeer
{
    public string Id = "";
    public string Name = "";
    public string Ip = "";
    public string Chan = "";
    public bool Locked;
    public int LastSeen;
    public int LastAudio;
    public IPEndPoint Ep;
}

public class EarthJitter
{
    public Queue<short[]> Frames = new Queue<short[]>();
    public bool Playing;
}

public class EarthVoiceNode
{

    private static long lastBanLoad;
    private static HashSet<string> bannedIps = new HashSet<string>();
    private static readonly object banLock = new object();
    protected static bool IsIpBanned(string ip)
    {
        long now = Environment.TickCount;
        lock (banLock)
        {
            if (now - lastBanLoad > 4000 || now < lastBanLoad)
            {
                lastBanLoad = now;
                try
                {
                    HashSet<string> next = new HashSet<string>();
                    string path = @"C:\Project-Earth-Lan\ip_bans.json";
                    if (File.Exists(path))
                    {
                        string txt = File.ReadAllText(path, Encoding.UTF8);
                        foreach (Match m in Regex.Matches(txt, @"""Ip""\s*:\s*""([^""]*)""[^}]*?""Deleted""\s*:\s*(true|false)"))
                        {
                            if (m.Groups[2].Value == "false") next.Add(m.Groups[1].Value);
                        }
                    }
                    bannedIps = next;
                }
                catch (Exception) { }
            }
            return bannedIps.Contains(ip);
        }
    }

    public const int VoicePort = 9873;
    public string NodeId;
    public string NodeName;
    public ConcurrentQueue<string> Events = new ConcurrentQueue<string>();
    public volatile bool MicMuted;
    public volatile bool PttMode;
    public volatile int PttVKey = 0x12;
    public ConcurrentDictionary<string, int> Latencies = new ConcurrentDictionary<string, int>();
    private readonly Dictionary<string, long> pingSentAt = new Dictionary<string, long>();
    private readonly object pingLock = new object();
    public volatile bool Deafened;
    public volatile int Threshold = 350;
    public volatile int VolumePercent = 100;
    public volatile int MicLevel;
    public EarthAudioIn Mic;
    public EarthAudioOut Speaker;

    private UdpClient rx;
    private volatile bool running;
    private readonly object lk = new object();
    private readonly object jlk = new object();
    private readonly object ifLock = new object();
    private Dictionary<string, EarthVoicePeer> peers = new Dictionary<string, EarthVoicePeer>();
    private Dictionary<string, bool> members = new Dictionary<string, bool>();
    private Dictionary<string, bool> denied = new Dictionary<string, bool>();
    private Dictionary<string, EarthJitter> jitter = new Dictionary<string, EarthJitter>();
    private List<string> manualIps = new List<string>();
    private List<UdpClient> ifClients = new List<UdpClient>();
    private List<IPEndPoint> ifTargets = new List<IPEndPoint>();
    private string myChannel = "";
    private bool myLocked;
    private string myHash = "";
    private string pendingOut = "";
    private ushort seq;
    private int lastVoiceTick;

    public EarthVoiceNode(string name)
    {
        NodeName = CleanName(name);
        NodeId = Guid.NewGuid().ToString("N").Substring(0, 12);
    }

    private static string CleanName(string s)
    {
        if (s == null) return "";
        s = s.Replace("\r", " ").Replace("\n", " ").Replace("|", "/").Trim();
        if (s.Length > 40) s = s.Substring(0, 40);
        return s;
    }

    private static string HashPw(string channel, string pw)
    {
        byte[] salt = Encoding.UTF8.GetBytes("ProjectEarthLanVoice:" + channel);
        Rfc2898DeriveBytes kdf = new Rfc2898DeriveBytes((pw == null) ? "" : pw, salt, 3000);
        byte[] b = kdf.GetBytes(16);
        return BitConverter.ToString(b).Replace("-", "");
    }

    private static byte MuLawEncode(short sample)
    {
        int s = sample;
        int sign = (s >> 8) & 0x80;
        if (sign != 0) s = -s;
        if (s > 32635) s = 32635;
        s += 0x84;
        int exponent = 7;
        for (int mask = 0x4000; (s & mask) == 0 && exponent > 0; mask >>= 1) exponent--;
        int mantissa = (s >> (exponent + 3)) & 0x0F;
        return (byte)~(sign | (exponent << 4) | mantissa);
    }

    private static short MuLawDecode(byte b)
    {
        int u = ~b & 0xFF;
        int sign = u & 0x80;
        int exponent = (u >> 4) & 0x07;
        int mantissa = u & 0x0F;
        int s = ((mantissa << 3) + 0x84) << exponent;
        s -= 0x84;
        return (short)(sign != 0 ? -s : s);
    }

    // ---------------- Start / Stop ----------------
    public string Start()
    {
        try
        {
            rx = new UdpClient(AddressFamily.InterNetwork);
            rx.Client.Bind(new IPEndPoint(IPAddress.Any, VoicePort));
            rx.Client.ReceiveBufferSize = 262144;
            try { rx.Client.IOControl((IOControlCode)(-1744830452), new byte[] { 0, 0, 0, 0 }, null); } catch (Exception) { }
        }
        catch (Exception ex)
        {
            return "UDP-Port 9873 konnte nicht geoeffnet werden: " + ex.Message;
        }
        running = true;
        RefreshInterfaces();
        Thread t1 = new Thread(RxLoop);
        t1.IsBackground = true;
        t1.Start();
        Thread t2 = new Thread(BeaconLoop);
        t2.IsBackground = true;
        t2.Start();
        return null;
    }

    public void Stop()
    {
        if (!running) return;
        StopAudio();
        List<string> ips = new List<string>();
        lock (lk)
        {
            LeaveInternal();
            foreach (KeyValuePair<string, EarthVoicePeer> kv in peers) ips.Add(kv.Value.Ip);
        }
        byte[] bye = Encoding.UTF8.GetBytes("PV1|BYE|" + NodeId);
        foreach (string ip in ips) SendTo(ip, "PV1|BYE|" + NodeId);
        List<UdpClient> cl;
        List<IPEndPoint> tg;
        lock (ifLock) { cl = new List<UdpClient>(ifClients); tg = new List<IPEndPoint>(ifTargets); }
        for (int i = 0; i < cl.Count; i++)
        {
            try { cl[i].Send(bye, bye.Length, tg[i]); } catch (Exception) { }
        }
        running = false;
        try { rx.Close(); } catch (Exception) { }
        foreach (UdpClient c in cl) { try { c.Close(); } catch (Exception) { } }
    }

    public string StartAudio(int inDev, int outDev)
    {
        StopAudio();
        EarthAudioOut sp = new EarthAudioOut();
        sp.PullFrame = PullFrame;
        string e = sp.Start(outDev);
        if (e != null) return e;
        Speaker = sp;
        EarthAudioIn mic = new EarthAudioIn();
        mic.OnFrame = OnMicFrame;
        e = mic.Start(inDev);
        if (e != null) return e;
        Mic = mic;
        return null;
    }

    public void StopAudio()
    {
        EarthAudioIn m = Mic;
        EarthAudioOut s = Speaker;
        Mic = null;
        Speaker = null;
        if (m != null) m.Stop();
        if (s != null) s.Stop();
    }

    // ---------------- Netzwerk-Grundlagen ----------------
    private void SendTo(string ip, string text)
    {
        try
        {
            byte[] b = Encoding.UTF8.GetBytes(text);
            rx.Send(b, b.Length, ip, VoicePort);
        }
        catch (Exception) { }
    }

    private void RefreshInterfaces()
    {
        List<UdpClient> newClients = new List<UdpClient>();
        List<IPEndPoint> newTargets = new List<IPEndPoint>();
        try
        {
            foreach (NetworkInterface nic in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (nic.OperationalStatus != OperationalStatus.Up) continue;
                if (nic.NetworkInterfaceType == NetworkInterfaceType.Loopback || nic.NetworkInterfaceType == NetworkInterfaceType.Tunnel) continue;
                foreach (UnicastIPAddressInformation ua in nic.GetIPProperties().UnicastAddresses)
                {
                    if (ua.Address.AddressFamily != AddressFamily.InterNetwork || ua.IPv4Mask == null) continue;
                    if (ua.Address.ToString().StartsWith("169.254.")) continue;
                    try
                    {
                        UdpClient c = new UdpClient(new IPEndPoint(ua.Address, 0));
                        c.EnableBroadcast = true;
                        uint ipN = EarthVoiceNet.ToUInt(ua.Address);
                        uint mk = EarthVoiceNet.ToUInt(ua.IPv4Mask);
                        uint bc = ipN | ~mk;
                        newClients.Add(c);
                        newTargets.Add(new IPEndPoint(IPAddress.Parse(EarthVoiceNet.FromUInt(bc)), VoicePort));
                    }
                    catch (Exception) { }
                }
            }
        }
        catch (Exception) { }
        List<UdpClient> old;
        lock (ifLock)
        {
            old = ifClients;
            ifClients = newClients;
            ifTargets = newTargets;
        }
        foreach (UdpClient o in old) { try { o.Close(); } catch (Exception) { } }
    }

    private string PresenceText()
    {
        string c;
        bool l;
        lock (lk) { c = myChannel; l = myLocked; }
        return "PV1|HI|" + NodeId + "|" + NodeName + "|" + c + "|" + (l ? "1" : "0");
    }

    private void SendPresenceAll()
    {
        string text = PresenceText();
        byte[] msg = Encoding.UTF8.GetBytes(text);
        List<UdpClient> cl;
        List<IPEndPoint> tg;
        lock (ifLock) { cl = new List<UdpClient>(ifClients); tg = new List<IPEndPoint>(ifTargets); }
        IPEndPoint all = new IPEndPoint(IPAddress.Broadcast, VoicePort);
        for (int i = 0; i < cl.Count; i++)
        {
            try { cl[i].Send(msg, msg.Length, tg[i]); } catch (Exception) { }
            try { cl[i].Send(msg, msg.Length, all); } catch (Exception) { }
        }
        List<string> ips = new List<string>();
        lock (lk)
        {
            foreach (KeyValuePair<string, EarthVoicePeer> kv in peers) ips.Add(kv.Value.Ip);
            foreach (string m in manualIps) { if (!ips.Contains(m)) ips.Add(m); }
        }
        foreach (string ip in ips) SendTo(ip, text);
    }

    private void BeaconLoop()
    {
        int tick = 0;
        while (running)
        {
            try
            {
                if (tick % 5 == 4) RefreshInterfaces();
                SendPresenceAll();
                SendLatencyPings();
                Reconcile();
                Prune();
            }
            catch (Exception) { }
            tick++;
            for (int i = 0; i < 20 && running; i++) Thread.Sleep(100);
        }
    }

    private void SendLatencyPings()
    {
        List<EarthVoicePeer> list = new List<EarthVoicePeer>();
        lock (lk) { foreach (KeyValuePair<string, EarthVoicePeer> kv in peers) list.Add(kv.Value); }
        foreach (EarthVoicePeer p in list)
        {
            string tok = Guid.NewGuid().ToString("N").Substring(0, 8);
            lock (pingLock) { pingSentAt[p.Ip + "|" + tok] = Environment.TickCount; }
            SendTo(p.Ip, "PV1|LPING|" + NodeId + "|" + tok);
        }
    }

    private void Reconcile()
    {
        List<string> ips = new List<string>();
        string chan;
        string hash;
        lock (lk)
        {
            chan = myChannel;
            hash = myHash;
            if (chan.Length == 0) return;
            foreach (KeyValuePair<string, EarthVoicePeer> kv in peers)
            {
                EarthVoicePeer p = kv.Value;
                if (p.Chan == chan && !members.ContainsKey(p.Id) && !denied.ContainsKey(p.Id)) ips.Add(p.Ip);
            }
        }
        foreach (string ip in ips) SendTo(ip, "PV1|JOIN|" + NodeId + "|" + chan + "|" + hash);
    }

    private void Prune()
    {
        int now = Environment.TickCount;
        List<string> dead = new List<string>();
        lock (lk)
        {
            foreach (KeyValuePair<string, EarthVoicePeer> kv in peers)
            {
                if (now - kv.Value.LastSeen > 9000) dead.Add(kv.Key);
            }
            foreach (string d in dead) { peers.Remove(d); members.Remove(d); }
        }
        if (dead.Count > 0)
        {
            lock (jlk) { foreach (string d2 in dead) jitter.Remove(d2); }
        }
    }

    private EarthVoicePeer TouchPeer(string id, string name, string ip)
    {
        EarthVoicePeer p;
        if (!peers.TryGetValue(id, out p))
        {
            p = new EarthVoicePeer();
            p.Id = id;
            p.Name = (name.Length > 0) ? name : id;
            peers[id] = p;
        }
        else if (name.Length > 0)
        {
            p.Name = name;
        }
        p.Ip = ip;
        p.Ep = new IPEndPoint(IPAddress.Parse(ip), VoicePort);
        p.LastSeen = Environment.TickCount;
        return p;
    }

    private void LeaveInternal()
    {
        if (myChannel.Length > 0)
        {
            foreach (KeyValuePair<string, bool> kv in members)
            {
                EarthVoicePeer p;
                if (peers.TryGetValue(kv.Key, out p)) SendTo(p.Ip, "PV1|LEAVE|" + NodeId + "|" + myChannel);
            }
        }
        members.Clear();
        denied.Clear();
        myChannel = "";
        myLocked = false;
        myHash = "";
        lock (jlk) { jitter.Clear(); }
    }

    // ---------------- Empfang ----------------
    private void RxLoop()
    {
        IPEndPoint ep = new IPEndPoint(IPAddress.Any, 0);
        while (running)
        {
            byte[] data;
            try { data = rx.Receive(ref ep); }
            catch (Exception)
            {
                if (!running) break;
                Thread.Sleep(20);
                continue;
            }
            try
            {
                string vip = ep.Address.ToString();
                if (IsIpBanned(vip)) continue;
                if (data.Length > 15 && data[0] == 0xA1) HandleAudio(data);
                else if (data.Length > 4 && data[0] == (byte)'P') HandleControl(Encoding.UTF8.GetString(data), vip);
            }
            catch (Exception) { }
        }
    }

    private void HandleAudio(byte[] d)
    {
        if (Deafened) return;
        string id = Encoding.ASCII.GetString(d, 1, 12);
        lock (lk)
        {
            if (!members.ContainsKey(id)) return;
            EarthVoicePeer p;
            if (peers.TryGetValue(id, out p)) p.LastAudio = Environment.TickCount;
        }
        int n = d.Length - 15;
        if (n <= 0 || n > 1920) return;
        short[] fr = new short[n];
        for (int i = 0; i < n; i++) fr[i] = MuLawDecode(d[15 + i]);
        lock (jlk)
        {
            EarthJitter j;
            if (!jitter.TryGetValue(id, out j)) { j = new EarthJitter(); jitter[id] = j; }
            j.Frames.Enqueue(fr);
            while (j.Frames.Count > 12) j.Frames.Dequeue();
        }
    }

    private void HandleControl(string text, string ip)
    {
        string[] f = text.Split('|');
        if (f.Length < 3 || f[0] != "PV1") return;
        string type = f[1];
        string id = f[2];

        if (type == "LPING" && f.Length >= 4)
        {
            SendTo(ip, "PV1|LPONG|" + NodeId + "|" + f[3]);
            return;
        }
        if (type == "LPONG" && f.Length >= 4)
        {
            long sentAt;
            string key = ip + "|" + f[3];
            lock (pingLock)
            {
                if (pingSentAt.TryGetValue(key, out sentAt)) { pingSentAt.Remove(key); }
                else sentAt = 0;
            }
            if (sentAt > 0) Latencies[ip] = (int)(Environment.TickCount - sentAt);
            return;
        }
        if (id == NodeId || id.Length != 12) return;

        if (type == "HI")
        {
            if (f.Length < 6) return;
            bool isNew;
            lock (lk)
            {
                isNew = !peers.ContainsKey(id);
                EarthVoicePeer p = TouchPeer(id, CleanName(f[3]), ip);
                p.Chan = f[4];
                p.Locked = (f[5] == "1");
                if (members.ContainsKey(id) && p.Chan != myChannel) members.Remove(id);
            }
            if (isNew) SendTo(ip, PresenceText());
        }
        else if (type == "JOIN")
        {
            if (f.Length < 5) return;
            string jch = f[3];
            string jh = f[4];
            bool ok = false;
            lock (lk)
            {
                if (myChannel.Length > 0 && myChannel == jch && (!myLocked || jh == myHash))
                {
                    TouchPeer(id, "", ip);
                    members[id] = true;
                    ok = true;
                }
            }
            if (ok) SendTo(ip, "PV1|OK|" + NodeId + "|" + jch);
            else SendTo(ip, "PV1|NO|" + NodeId + "|" + jch);
        }
        else if (type == "OK")
        {
            if (f.Length < 4) return;
            lock (lk)
            {
                if (myChannel.Length > 0 && myChannel == f[3])
                {
                    TouchPeer(id, "", ip);
                    members[id] = true;
                }
            }
        }
        else if (type == "NO")
        {
            if (f.Length < 4) return;
            bool first = false;
            string lostChan = "";
            lock (lk)
            {
                if (myChannel.Length > 0 && myChannel == f[3] && !denied.ContainsKey(id))
                {
                    denied[id] = true;
                    first = true;
                    lostChan = myChannel;
                    if (members.Count == 0) LeaveInternal();
                }
            }
            if (first) Events.Enqueue("SYS|Beitritt zu '" + lostChan + "' abgelehnt (Passwort falsch oder Kanal geschlossen).");
        }
        else if (type == "LEAVE")
        {
            lock (lk) { members.Remove(id); }
        }
        else if (type == "BYE")
        {
            lock (lk) { peers.Remove(id); members.Remove(id); }
        }
        else if (type == "CALL")
        {
            if (f.Length < 4) return;
            string nm = CleanName(f[3]);
            lock (lk) { TouchPeer(id, nm, ip); }
            Events.Enqueue("CALL|" + id + "|" + nm);
        }
        else if (type == "DECL")
        {
            string who = id;
            lock (lk) { EarthVoicePeer p2; if (peers.TryGetValue(id, out p2)) who = p2.Name; if (pendingOut == id) pendingOut = ""; }
            Events.Enqueue("SYS|" + who + " hat den Anruf abgelehnt.");
        }
        else if (type == "ACC")
        {
            if (f.Length < 4) return;
            bool mine = false;
            string pair = f[3];
            lock (lk)
            {
                if (pendingOut == id)
                {
                    pendingOut = "";
                    TouchPeer(id, "", ip);
                    LeaveInternal();
                    myChannel = pair;
                    myLocked = true;
                    myHash = Guid.NewGuid().ToString("N");
                    members[id] = true;
                    mine = true;
                }
            }
            if (mine)
            {
                SendTo(ip, "PV1|OK|" + NodeId + "|" + pair);
                Events.Enqueue("SYS|Privatgespraech gestartet.");
                SendPresenceAll();
            }
        }
    }

    // ---------------- Kanal-API ----------------
    public string CreateChannel(string name, string password)
    {
        name = CleanName(name);
        if (name.Length == 0) return "Bitte einen Kanalnamen eingeben.";
        if (name.StartsWith("@")) return "Kanalnamen duerfen nicht mit @ beginnen.";
        lock (lk)
        {
            foreach (KeyValuePair<string, EarthVoicePeer> kv in peers)
            {
                if (kv.Value.Chan == name) return "Ein Kanal mit diesem Namen existiert bereits - bitte ueber Button 3 beitreten.";
            }
            LeaveInternal();
            myChannel = name;
            myLocked = !string.IsNullOrEmpty(password);
            myHash = HashPw(name, password);
        }
        SendPresenceAll();
        return null;
    }

    public string JoinChannel(string name, string password)
    {
        name = CleanName(name);
        if (name.Length == 0) return "Kein Kanal gewaehlt.";
        if (name.StartsWith("@")) return "Dieser Kanal ist privat.";
        List<string> targets = new List<string>();
        string hash;
        lock (lk)
        {
            LeaveInternal();
            myChannel = name;
            myHash = HashPw(name, password);
            hash = myHash;
            bool locked = false;
            foreach (KeyValuePair<string, EarthVoicePeer> kv in peers)
            {
                if (kv.Value.Chan == name)
                {
                    targets.Add(kv.Value.Ip);
                    if (kv.Value.Locked) locked = true;
                }
            }
            myLocked = locked;
        }
        foreach (string ip in targets) SendTo(ip, "PV1|JOIN|" + NodeId + "|" + name + "|" + hash);
        SendPresenceAll();
        return null;
    }

    public void LeaveChannel()
    {
        lock (lk) { LeaveInternal(); }
        SendPresenceAll();
    }

    public string Call(string peerId)
    {
        string ip = null;
        string nm = "";
        lock (lk)
        {
            EarthVoicePeer p;
            if (peers.TryGetValue(peerId, out p)) { ip = p.Ip; nm = p.Name; }
            pendingOut = peerId;
        }
        if (ip == null) return "Teilnehmer nicht gefunden.";
        SendTo(ip, "PV1|CALL|" + NodeId + "|" + NodeName);
        Events.Enqueue("SYS|Rufe " + nm + " an ...");
        return null;
    }

    public void AnswerCall(string peerId, bool accept)
    {
        string ip = null;
        lock (lk)
        {
            EarthVoicePeer p;
            if (peers.TryGetValue(peerId, out p)) ip = p.Ip;
        }
        if (ip == null) return;
        if (!accept)
        {
            SendTo(ip, "PV1|DECL|" + NodeId);
            return;
        }
        string pair = (string.CompareOrdinal(NodeId, peerId) < 0) ? ("@" + NodeId + "~" + peerId) : ("@" + peerId + "~" + NodeId);
        lock (lk)
        {
            LeaveInternal();
            myChannel = pair;
            myLocked = true;
            myHash = Guid.NewGuid().ToString("N");
            members[peerId] = true;
        }
        SendTo(ip, "PV1|ACC|" + NodeId + "|" + pair);
        SendPresenceAll();
    }

    public void AddManualPeer(string ip)
    {
        lock (lk) { if (!manualIps.Contains(ip)) manualIps.Add(ip); }
        SendTo(ip, PresenceText());
    }

    public string[] GetPeers()
    {
        List<string> l = new List<string>();
        int now = Environment.TickCount;
        lock (lk)
        {
            foreach (KeyValuePair<string, EarthVoicePeer> kv in peers)
            {
                EarthVoicePeer p = kv.Value;
                int lat;
                string latS = Latencies.TryGetValue(p.Ip, out lat) ? lat.ToString() : "-";
                l.Add(p.Id + "|" + p.Name + "|" + p.Ip + "|" + p.Chan + "|" + (p.Locked ? "1" : "0") + "|" + (members.ContainsKey(p.Id) ? "1" : "0") + "|" + ((now - p.LastAudio) < 400 ? "1" : "0") + "|" + latS);
            }
        }
        return l.ToArray();
    }

    public string GetState()
    {
        lock (lk) { return myChannel + "|" + (myLocked ? "1" : "0") + "|" + members.Count; }
    }

    // ---------------- Audio ----------------
    private void OnMicFrame(short[] f)
    {
        long sum = 0;
        for (int i = 0; i < f.Length; i++) sum += (long)f[i] * f[i];
        int rms = (int)Math.Sqrt((double)sum / f.Length);
        MicLevel = rms;
        int now = Environment.TickCount;
        if (PttMode)
        {
            bool pttHeld = (EarthWinmm.GetAsyncKeyState(PttVKey) & 0x8000) != 0;
            if (!MicMuted && pttHeld) lastVoiceTick = now;
        }
        else
        {
            if (!MicMuted && rms > Threshold) lastVoiceTick = now;
        }
        if (MicMuted || lastVoiceTick == 0 || (now - lastVoiceTick) > 300) return;

        List<IPEndPoint> targets = new List<IPEndPoint>();
        lock (lk)
        {
            foreach (KeyValuePair<string, bool> kv in members)
            {
                EarthVoicePeer p;
                if (peers.TryGetValue(kv.Key, out p) && p.Ep != null) targets.Add(p.Ep);
            }
        }
        if (targets.Count == 0) return;

        byte[] pkt = new byte[15 + f.Length];
        pkt[0] = 0xA1;
        Encoding.ASCII.GetBytes(NodeId, 0, 12, pkt, 1);
        seq++;
        pkt[13] = (byte)(seq >> 8);
        pkt[14] = (byte)(seq & 0xFF);
        for (int i = 0; i < f.Length; i++) pkt[15 + i] = MuLawEncode(f[i]);
        foreach (IPEndPoint t in targets)
        {
            try { rx.Send(pkt, pkt.Length, t); } catch (Exception) { }
        }
    }

    private long lastVolLoad;
    private Dictionary<string, int> peerVolumes = new Dictionary<string, int>();

    private int GetPeerVolumePercent(string ip)
    {
        long now = Environment.TickCount;
        if (now - lastVolLoad > 4000 || now < lastVolLoad)
        {
            lastVolLoad = now;
            try
            {
                Dictionary<string, int> next = new Dictionary<string, int>();
                string path = @"C:\Project-Earth-Lan\PeerVolumes.json";
                if (File.Exists(path))
                {
                    string txt = File.ReadAllText(path, Encoding.UTF8);
                    foreach (Match m in Regex.Matches(txt, @"""([0-9.]+)""\s*:\s*(\d+)"))
                    {
                        int v;
                        if (int.TryParse(m.Groups[2].Value, out v)) next[m.Groups[1].Value] = v;
                    }
                }
                peerVolumes = next;
            }
            catch (Exception) { }
        }
        int vol;
        return peerVolumes.TryGetValue(ip, out vol) ? vol : 100;
    }

    private short[] PullFrame()
    {
        int n = EarthAudioOut.FrameSamples;
        int[] acc = new int[n];
        lock (jlk)
        {
            foreach (KeyValuePair<string, EarthJitter> kv in jitter)
            {
                EarthJitter j = kv.Value;
                if (!j.Playing)
                {
                    if (j.Frames.Count >= 3) j.Playing = true;
                    else continue;
                }
                if (j.Frames.Count == 0) { j.Playing = false; continue; }
                short[] fr = j.Frames.Dequeue();
                string peerIp = "";
                lock (lk) { EarthVoicePeer pp; if (peers.TryGetValue(kv.Key, out pp)) peerIp = pp.Ip; }
                int pvol = (peerIp.Length > 0) ? GetPeerVolumePercent(peerIp) : 100;
                int len = Math.Min(fr.Length, n);
                for (int i = 0; i < len; i++) acc[i] += fr[i] * pvol / 100;
            }
        }
        short[] mix = new short[n];
        if (Deafened) return mix;
        int vol = VolumePercent;
        for (int i = 0; i < n; i++)
        {
            int v = acc[i] * vol / 100;
            if (v > 32767) v = 32767;
            if (v < -32768) v = -32768;
            mix[i] = (short)v;
        }
        return mix;
    }
}
'@
        Add-Type -TypeDefinition $voiceCode -Language CSharp
    }
}



function Initialize-FileTypes {
    if (-not ('EarthFileNode' -as [type])) {
        $fileCode = @'
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

public class EarthReader
{
    private Stream s;
    private byte[] buf = new byte[65536];
    private int pos;
    private int len;

    public EarthReader(Stream stream) { s = stream; }

    private bool Fill()
    {
        pos = 0;
        len = s.Read(buf, 0, buf.Length);
        return len > 0;
    }

    public string ReadLine()
    {
        MemoryStream ms = new MemoryStream();
        while (true)
        {
            if (pos >= len)
            {
                if (!Fill())
                {
                    if (ms.Length == 0) return null;
                    break;
                }
            }
            byte b = buf[pos++];
            if (b == 10) break;
            if (b != 13) ms.WriteByte(b);
            if (ms.Length > 8000000) throw new IOException("Zeile zu lang");
        }
        return Encoding.UTF8.GetString(ms.ToArray());
    }

    public bool ReadExact(byte[] dst, int off, int count)
    {
        int got = 0;
        while (got < count)
        {
            if (pos < len)
            {
                int n = Math.Min(len - pos, count - got);
                Buffer.BlockCopy(buf, pos, dst, off + got, n);
                pos += n;
                got += n;
            }
            else
            {
                int r = s.Read(dst, off + got, count - got);
                if (r <= 0) return false;
                got += r;
            }
        }
        return true;
    }
}

public class EarthFileEntry
{
    public string Rel = "";
    public string Full = "";
    public long Size;
    public long MTimeTicks;
    public int Chunks;
    public string FinalPath = "";
    public string PartPath = "";
    public string MapPath = "";
    public bool[] Have;
    public int Remaining;
    public bool Done;
    public bool Dirty;
    public FileStream Fs;
}

public class EarthXfer
{
    public string Id = "";
    public bool Outgoing;
    public string PeerName = "";
    public string PeerIp = "";
    public string Title = "";
    public string Token = "";
    public long TotalBytes;
    public long DoneBytes;
    public string Status = "";
    public volatile bool Cancel;
    public volatile bool Finished;
    public volatile bool Failed;
    public volatile bool Accepted;
    public volatile bool RemoteAbort;
    public int ChunkSize = 2097152;
    public int FilesLeft;
    public string DestRoot = "";
    public List<EarthFileEntry> Files = new List<EarthFileEntry>();
    public ManualResetEvent Decision = new ManualResetEvent(false);
    public long LastBytes;
    public int LastTick;
    public int LastProgress;
    public double Speed;
}

public class EarthSendState
{
    public Queue<int[]> Jobs = new Queue<int[]>();
    public object Lk = new object();
    public int Remaining;
    public volatile bool Abort;
}

public class EarthFilePeer
{
    public string Id = "";
    public string Name = "";
    public string Ip = "";
    public int LastSeen;
    public bool Manual;
}

public class EarthThrottle
{
    private readonly object lk = new object();
    private double allowance;
    private int last;

    public void Wait(int bytes, long rate)
    {
        if (rate <= 0) return;
        int sleepMs = 0;
        lock (lk)
        {
            int now = Environment.TickCount;
            if (last == 0) { last = now; allowance = rate; }
            double el = (now - last) / 1000.0;
            last = now;
            allowance += el * rate;
            if (allowance > rate) allowance = rate;
            allowance -= bytes;
            if (allowance < 0) sleepMs = (int)(-allowance / rate * 1000.0);
        }
        if (sleepMs > 0) Thread.Sleep(Math.Min(sleepMs, 2000));
    }
}

public class EarthFileNode
{

    private static long lastBanLoad;
    private static HashSet<string> bannedIps = new HashSet<string>();
    private static readonly object banLock = new object();
    protected static bool IsIpBanned(string ip)
    {
        long now = Environment.TickCount;
        lock (banLock)
        {
            if (now - lastBanLoad > 4000 || now < lastBanLoad)
            {
                lastBanLoad = now;
                try
                {
                    HashSet<string> next = new HashSet<string>();
                    string path = @"C:\Project-Earth-Lan\ip_bans.json";
                    if (File.Exists(path))
                    {
                        string txt = File.ReadAllText(path, Encoding.UTF8);
                        foreach (Match m in Regex.Matches(txt, @"""Ip""\s*:\s*""([^""]*)""[^}]*?""Deleted""\s*:\s*(true|false)"))
                        {
                            if (m.Groups[2].Value == "false") next.Add(m.Groups[1].Value);
                        }
                    }
                    bannedIps = next;
                }
                catch (Exception) { }
            }
            return bannedIps.Contains(ip);
        }
    }

    public const int PortNumber = 9876;
    public string NodeId;
    public string NodeName;
    public string BindIp = "";
    public string Mask = "";
    public string DownloadDir = "";
    public volatile int Streams = 4;
    public long LimitBytesPerSec;
    public ConcurrentQueue<string> Events = new ConcurrentQueue<string>();

    private TcpListener listener;
    private UdpClient beaconRx;
    private volatile bool running;
    private readonly object lk = new object();
    private Dictionary<string, EarthFilePeer> peers = new Dictionary<string, EarthFilePeer>();
    private Dictionary<string, EarthXfer> xfers = new Dictionary<string, EarthXfer>();
    private EarthThrottle throttle = new EarthThrottle();

    public EarthFileNode(string bindIp, string name)
    {
        BindIp = bindIp;
        NodeName = CleanName(name);
        NodeId = Guid.NewGuid().ToString("N").Substring(0, 12);
    }

    private static string CleanName(string s)
    {
        if (s == null) return "";
        s = s.Replace("\r", " ").Replace("\n", " ").Replace("|", "/").Trim();
        if (s.Length > 60) s = s.Substring(0, 60);
        return s;
    }

    private static void WriteLine(Stream s, string t)
    {
        byte[] b = Encoding.UTF8.GetBytes(t + "\n");
        s.Write(b, 0, b.Length);
    }

    private static string Sha256Hex(byte[] b, int len)
    {
        using (SHA256 sha = SHA256.Create())
        {
            byte[] h = sha.ComputeHash(b, 0, len);
            return BitConverter.ToString(h).Replace("-", "").ToLower();
        }
    }

    private static int ChunkLen(long size, int ci, int cs)
    {
        long rest = size - (long)ci * cs;
        return (int)Math.Min((long)cs, rest);
    }

    private static readonly string[] Reserved = new string[] { "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9" };

    private static string SafeRel(string rel)
    {
        if (rel == null) return null;
        rel = rel.Replace('\\', '/');
        string[] parts = rel.Split('/');
        List<string> ok = new List<string>();
        char[] bad = Path.GetInvalidFileNameChars();
        foreach (string p in parts)
        {
            if (p.Length == 0 || p == "." || p == "..") return null;
            if (p.IndexOfAny(bad) >= 0) return null;
            if (p.EndsWith(".") || p.EndsWith(" ")) return null;
            string stem = p;
            int dot = stem.IndexOf('.');
            if (dot >= 0) stem = stem.Substring(0, dot);
            foreach (string r in Reserved) { if (string.Equals(stem, r, StringComparison.OrdinalIgnoreCase)) return null; }
            ok.Add(p);
        }
        if (ok.Count == 0) return null;
        return string.Join(Path.DirectorySeparatorChar.ToString(), ok.ToArray());
    }

    private static TcpClient TryConnect(string ip, int timeoutMs)
    {
        TcpClient c = new TcpClient(AddressFamily.InterNetwork);
        try
        {
            IAsyncResult ar = c.BeginConnect(IPAddress.Parse(ip), PortNumber, null, null);
            if (ar.AsyncWaitHandle.WaitOne(timeoutMs))
            {
                c.EndConnect(ar);
                return c;
            }
        }
        catch (Exception) { }
        try { c.Close(); } catch (Exception) { }
        return null;
    }

    // ---------------- Start / Stop ----------------
    public string Start()
    {
        try
        {
            listener = new TcpListener(IPAddress.Parse(BindIp), PortNumber);
            listener.Start();
        }
        catch (Exception ex)
        {
            return "Port 9876 konnte nicht geoeffnet werden: " + ex.Message;
        }
        running = true;
        try
        {
            beaconRx = new UdpClient(AddressFamily.InterNetwork);
            beaconRx.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
            beaconRx.Client.Bind(new IPEndPoint(IPAddress.Any, PortNumber));
            try { beaconRx.Client.IOControl((IOControlCode)(-1744830452), new byte[] { 0, 0, 0, 0 }, null); } catch (Exception) { }
            Thread rt = new Thread(BeaconRxLoop);
            rt.IsBackground = true;
            rt.Start();
        }
        catch (Exception)
        {
            beaconRx = null;
            Events.Enqueue("SYS|Automatische Erkennung (UDP 9876) nicht verfuegbar - bitte IP manuell waehlen.");
        }
        Thread ta = new Thread(AcceptLoop);
        ta.IsBackground = true;
        ta.Start();
        Thread tb = new Thread(BeaconTxLoop);
        tb.IsBackground = true;
        tb.Start();
        Thread tm = new Thread(MaintenanceLoop);
        tm.IsBackground = true;
        tm.Start();
        return null;
    }

    public void Stop()
    {
        running = false;
        try { if (listener != null) listener.Stop(); } catch (Exception) { }
        try { if (beaconRx != null) beaconRx.Close(); } catch (Exception) { }
        List<EarthXfer> list = new List<EarthXfer>();
        lock (lk) { foreach (KeyValuePair<string, EarthXfer> kv in xfers) list.Add(kv.Value); }
        foreach (EarthXfer x in list)
        {
            x.Cancel = true;
            x.Decision.Set();
            if (!x.Outgoing) { SaveMaps(x); CloseStreams(x); }
        }
    }

    // ---------------- Erkennung ----------------
    private void UpsertPeer(string id, string name, string ip, bool manual)
    {
        bool isNew = false;
        lock (lk)
        {
            EarthFilePeer p;
            if (!peers.TryGetValue(id, out p))
            {
                p = new EarthFilePeer();
                p.Id = id;
                peers[id] = p;
                isNew = true;
            }
            p.Name = name;
            p.Ip = ip;
            p.LastSeen = Environment.TickCount;
            if (manual) p.Manual = true;
        }
        if (isNew) Events.Enqueue("SYS|Manager gefunden: " + name + " (" + ip + ")");
    }

    private void BeaconRxLoop()
    {
        IPEndPoint ep = new IPEndPoint(IPAddress.Any, 0);
        while (running)
        {
            byte[] d;
            try { d = beaconRx.Receive(ref ep); }
            catch (Exception)
            {
                if (!running) break;
                Thread.Sleep(50);
                continue;
            }
            try
            {
                string fip = ep.Address.ToString();
                if (IsIpBanned(fip)) continue;
                string[] f = Encoding.UTF8.GetString(d).Split('|');
                if (f.Length < 3 || f[0] != "PEFS1" || f[1] == NodeId) continue;
                UpsertPeer(f[1], CleanName(f[2]), fip, false);
            }
            catch (Exception) { }
        }
    }

    private void BeaconTxLoop()
    {
        UdpClient tx = null;
        IPEndPoint bc1 = new IPEndPoint(IPAddress.Broadcast, PortNumber);
        IPEndPoint bc2 = null;
        try
        {
            tx = new UdpClient(new IPEndPoint(IPAddress.Parse(BindIp), 0));
            tx.EnableBroadcast = true;
            if (!string.IsNullOrEmpty(Mask))
            {
                byte[] ib = IPAddress.Parse(BindIp).GetAddressBytes();
                byte[] mb = IPAddress.Parse(Mask).GetAddressBytes();
                byte[] bb = new byte[4];
                for (int i = 0; i < 4; i++) bb[i] = (byte)(ib[i] | (byte)~mb[i]);
                bc2 = new IPEndPoint(new IPAddress(bb), PortNumber);
            }
        }
        catch (Exception) { return; }
        while (running)
        {
            try
            {
                byte[] msg = Encoding.UTF8.GetBytes("PEFS1|" + NodeId + "|" + NodeName);
                tx.Send(msg, msg.Length, bc1);
                if (bc2 != null) tx.Send(msg, msg.Length, bc2);
            }
            catch (Exception) { }
            for (int i = 0; i < 30 && running; i++) Thread.Sleep(100);
        }
        try { tx.Close(); } catch (Exception) { }
    }

    public void AddManualPeer(string ip)
    {
        Thread t = new Thread(() =>
        {
            TcpClient c = TryConnect(ip, 2500);
            if (c == null)
            {
                Events.Enqueue("SYS|Keine Antwort von " + ip + ":9876 (Kommunikationszentrale dort nicht geoeffnet?)");
                return;
            }
            try
            {
                c.ReceiveTimeout = 3000;
                NetworkStream ns = c.GetStream();
                WriteLine(ns, "PING|" + NodeId + "|" + NodeName);
                EarthReader rd = new EarthReader(ns);
                string r = rd.ReadLine();
                if (r != null && r.StartsWith("PONG|"))
                {
                    string[] f = r.Split('|');
                    if (f.Length >= 3) UpsertPeer(f[1], CleanName(f[2]), ip, true);
                }
            }
            catch (Exception) { }
            finally { try { c.Close(); } catch (Exception) { } }
        });
        t.IsBackground = true;
        t.Start();
    }

    public string[] GetPeers()
    {
        List<string> l = new List<string>();
        int now = Environment.TickCount;
        lock (lk)
        {
            foreach (KeyValuePair<string, EarthFilePeer> kv in peers)
            {
                EarthFilePeer p = kv.Value;
                l.Add(p.Id + "|" + p.Name + "|" + p.Ip + "|" + ((now - p.LastSeen) / 1000));
            }
        }
        return l.ToArray();
    }

    private void MaintenanceLoop()
    {
        while (running)
        {
            for (int i = 0; i < 30 && running; i++) Thread.Sleep(100);
            try
            {
                int now = Environment.TickCount;
                List<EarthXfer> list = new List<EarthXfer>();
                lock (lk)
                {
                    List<string> dead = new List<string>();
                    foreach (KeyValuePair<string, EarthFilePeer> kv in peers)
                    {
                        if (!kv.Value.Manual && (now - kv.Value.LastSeen) > 12000) dead.Add(kv.Key);
                    }
                    foreach (string d in dead) peers.Remove(d);
                    foreach (KeyValuePair<string, EarthXfer> kv in xfers) list.Add(kv.Value);
                }
                foreach (EarthXfer x in list)
                {
                    if (!x.Outgoing && !x.Finished) SaveMaps(x);
                }
            }
            catch (Exception) { }
        }
    }

    // ---------------- Eingehende Verbindungen ----------------
    private void AcceptLoop()
    {
        while (running)
        {
            try
            {
                TcpClient c = listener.AcceptTcpClient();
                Thread t = new Thread(() => HandleConn(c));
                t.IsBackground = true;
                t.Start();
            }
            catch (Exception)
            {
                if (!running) break;
                Thread.Sleep(50);
            }
        }
    }

    private void HandleConn(TcpClient c)
    {
        try
        {
            c.NoDelay = true;
            c.ReceiveTimeout = 30000;
            c.SendTimeout = 30000;
            c.ReceiveBufferSize = 1048576;
            NetworkStream ns = c.GetStream();
            EarthReader rd = new EarthReader(ns);
            string line = rd.ReadLine();
            if (line == null) return;
            string[] f = line.Split('|');
            string ip = ((IPEndPoint)c.Client.RemoteEndPoint).Address.ToString();
            if (IsIpBanned(ip)) return;
            if (f[0] == "PING") WriteLine(ns, "PONG|" + NodeId + "|" + NodeName);
            else if (f[0] == "OFFER") HandleOffer(rd, ns, f, ip);
            else if (f[0] == "DATA") HandleData(rd, ns, f);
        }
        catch (Exception) { }
        finally { try { c.Close(); } catch (Exception) { } }
    }

    private void PrepareRecvFile(EarthXfer x, EarthFileEntry e)
    {
        e.FinalPath = Path.Combine(x.DestRoot, e.Rel);
        e.PartPath = e.FinalPath + ".part";
        e.MapPath = e.FinalPath + ".part.map";
        e.Have = new bool[e.Chunks];
        if (File.Exists(e.FinalPath))
        {
            FileInfo fi = new FileInfo(e.FinalPath);
            if (fi.Length == e.Size && Math.Abs(fi.LastWriteTimeUtc.Ticks - e.MTimeTicks) < 20000000L)
            {
                for (int i = 0; i < e.Chunks; i++) e.Have[i] = true;
                e.Remaining = 0;
                e.Done = true;
                return;
            }
        }
        Directory.CreateDirectory(Path.GetDirectoryName(e.FinalPath));
        bool resumed = false;
        if (File.Exists(e.PartPath) && File.Exists(e.MapPath))
        {
            try
            {
                string[] ml = File.ReadAllLines(e.MapPath);
                if (ml.Length >= 2 && ml[0] == (e.Size + "|" + e.MTimeTicks + "|" + x.ChunkSize) && ml[1].Length == e.Chunks)
                {
                    for (int i = 0; i < e.Chunks; i++) e.Have[i] = (ml[1][i] == '1');
                    resumed = true;
                }
            }
            catch (Exception) { }
        }
        if (!resumed)
        {
            try { if (File.Exists(e.PartPath)) File.Delete(e.PartPath); } catch (Exception) { }
            for (int i = 0; i < e.Chunks; i++) e.Have[i] = false;
        }
        int rem = 0;
        for (int i = 0; i < e.Chunks; i++) { if (!e.Have[i]) rem++; }
        e.Remaining = rem;
        e.Fs = new FileStream(e.PartPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.Read);
        if (rem == 0) FinalizeFile(x, e, false);
    }

    private static string UniqueName(string path)
    {
        string dir = Path.GetDirectoryName(path);
        string name = Path.GetFileNameWithoutExtension(path);
        string ext = Path.GetExtension(path);
        for (int i = 1; i < 10000; i++)
        {
            string cand = Path.Combine(dir, name + " (" + i + ")" + ext);
            if (!File.Exists(cand)) return cand;
        }
        return path;
    }

    private void FinalizeFile(EarthXfer x, EarthFileEntry e, bool countDown)
    {
        lock (e)
        {
            if (e.Done) return;
            try
            {
                if (e.Fs != null)
                {
                    e.Fs.SetLength(e.Size);
                    e.Fs.Flush(true);
                    e.Fs.Close();
                    e.Fs = null;
                }
                string target = e.FinalPath;
                if (File.Exists(target))
                {
                    FileInfo fi = new FileInfo(target);
                    if (fi.Length == e.Size && Math.Abs(fi.LastWriteTimeUtc.Ticks - e.MTimeTicks) < 20000000L)
                    {
                        File.Delete(e.PartPath);
                        target = null;
                    }
                    else target = UniqueName(target);
                }
                if (target != null)
                {
                    File.Move(e.PartPath, target);
                    try { File.SetLastWriteTimeUtc(target, new DateTime(e.MTimeTicks, DateTimeKind.Utc)); } catch (Exception) { }
                }
                try { if (File.Exists(e.MapPath)) File.Delete(e.MapPath); } catch (Exception) { }
                e.Done = true;
            }
            catch (Exception ex)
            {
                x.Status = "Fehler beim Abschliessen: " + ex.Message;
                x.Failed = true;
                return;
            }
        }
        if (countDown)
        {
            int left = Interlocked.Decrement(ref x.FilesLeft);
            if (left <= 0) CompleteTransfer(x);
        }
    }

    private void CompleteTransfer(EarthXfer x)
    {
        x.Finished = true;
        x.Status = "Fertig";
        Events.Enqueue("DONE|" + x.Id + "|" + x.Title);
    }

    private void HandleOffer(EarthReader rd, NetworkStream ns, string[] f, string ip)
    {
        if (f.Length < 7) return;
        string id = f[1];
        string sname = CleanName(f[3]);
        int fc;
        long total;
        int cs;
        if (!int.TryParse(f[4], out fc) || !long.TryParse(f[5], out total) || !int.TryParse(f[6], out cs)) return;
        if (fc < 0 || fc > 200000 || total < 0 || cs < 65536 || cs > 16777216 || id.Length == 0 || id.Length > 64) return;

        List<EarthFileEntry> files = new List<EarthFileEntry>();
        Dictionary<string, bool> seen = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
        for (int i = 0; i < fc; i++)
        {
            string l = rd.ReadLine();
            if (l == null) return;
            string[] ff = l.Split('|');
            long sz;
            long mt;
            if (ff.Length < 4 || ff[0] != "F" || !long.TryParse(ff[2], out sz) || !long.TryParse(ff[3], out mt) || sz < 0) return;
            string safe = SafeRel(ff[1]);
            if (safe == null || seen.ContainsKey(safe)) { WriteLine(ns, "DENY|Ungueltiger oder doppelter Dateipfad im Angebot"); return; }
            seen[safe] = true;
            long cnt = (sz + cs - 1) / cs;
            if (cnt > 10000000L) { WriteLine(ns, "DENY|Datei zu gross"); return; }
            EarthFileEntry e = new EarthFileEntry();
            e.Rel = safe;
            e.Size = sz;
            e.MTimeTicks = mt;
            e.Chunks = (int)cnt;
            files.Add(e);
        }
        string endl = rd.ReadLine();
        if (endl != "END") return;

        EarthXfer x = null;
        lock (lk) { xfers.TryGetValue(id, out x); }
        bool resume = (x != null && !x.Outgoing && !x.Finished && x.Accepted);
        if (!resume)
        {
            x = new EarthXfer();
            x.Id = id;
            x.Outgoing = false;
            x.PeerName = sname;
            x.PeerIp = ip;
            x.TotalBytes = total;
            x.ChunkSize = cs;
            x.Files = files;
            x.Title = (fc == 1) ? files[0].Rel : (fc + " Dateien");
            x.Token = Guid.NewGuid().ToString("N");
            x.DestRoot = DownloadDir;
            x.Status = "Wartet auf Zustimmung";
            lock (lk) { xfers[id] = x; }
            Events.Enqueue("OFFER|" + id + "|" + sname + "|" + ip + "|" + fc + "|" + total);
            bool got = x.Decision.WaitOne(60000);
            if (!got || !x.Accepted)
            {
                x.Status = got ? "Abgelehnt" : "Angebot abgelaufen";
                x.Failed = true;
                x.Finished = true;
                WriteLine(ns, "DENY|Nicht angenommen");
                return;
            }
            try
            {
                Directory.CreateDirectory(x.DestRoot);
                long doneAtStart = 0;
                int left = 0;
                foreach (EarthFileEntry e in x.Files)
                {
                    PrepareRecvFile(x, e);
                    for (int i = 0; i < e.Chunks; i++) { if (e.Have[i]) doneAtStart += ChunkLen(e.Size, i, cs); }
                    if (!e.Done) left++;
                }
                Interlocked.Exchange(ref x.DoneBytes, doneAtStart);
                x.FilesLeft = left;
                x.Status = "Empfange ...";
            }
            catch (Exception ex)
            {
                x.Status = "Fehler: " + ex.Message;
                x.Failed = true;
                x.Finished = true;
                WriteLine(ns, "DENY|Zielordner nicht beschreibbar: " + ex.Message.Replace("|", "/"));
                return;
            }
        }

        StringBuilder sb = new StringBuilder();
        sb.Append("ACCEPT|" + x.Token + "\n");
        for (int i = 0; i < x.Files.Count; i++)
        {
            EarthFileEntry e = x.Files[i];
            StringBuilder bits = new StringBuilder();
            lock (e) { for (int k = 0; k < e.Chunks; k++) bits.Append(e.Have[k] ? '1' : '0'); }
            sb.Append("H|" + i + "|" + bits.ToString() + "\n");
        }
        sb.Append("GO\n");
        byte[] reply = Encoding.UTF8.GetBytes(sb.ToString());
        ns.Write(reply, 0, reply.Length);
        if (x.FilesLeft <= 0 && !x.Finished) CompleteTransfer(x);
    }

    private void HandleData(EarthReader rd, NetworkStream ns, string[] f)
    {
        if (f.Length < 3) return;
        EarthXfer x = null;
        lock (lk) { xfers.TryGetValue(f[1], out x); }
        if (x == null || x.Outgoing || x.Token != f[2] || x.Cancel || !x.Accepted) { WriteLine(ns, "NO"); return; }
        WriteLine(ns, "READY");
        byte[] buf = new byte[x.ChunkSize];
        while (running && !x.Cancel)
        {
            string h = rd.ReadLine();
            if (h == null || h == "BYE") break;
            string[] p = h.Split('|');
            int fi;
            int ci;
            int len;
            if (p.Length < 5 || p[0] != "C") break;
            if (!int.TryParse(p[1], out fi) || !int.TryParse(p[2], out ci) || !int.TryParse(p[3], out len)) break;
            if (fi < 0 || fi >= x.Files.Count) break;
            EarthFileEntry e = x.Files[fi];
            if (ci < 0 || ci >= e.Chunks) break;
            if (len != ChunkLen(e.Size, ci, x.ChunkSize)) break;
            if (!rd.ReadExact(buf, 0, len)) break;
            bool good = string.Equals(Sha256Hex(buf, len), p[4], StringComparison.OrdinalIgnoreCase);
            if (good)
            {
                bool fresh = false;
                lock (e)
                {
                    if (!e.Done && !e.Have[ci] && e.Fs != null)
                    {
                        e.Fs.Seek((long)ci * x.ChunkSize, SeekOrigin.Begin);
                        e.Fs.Write(buf, 0, len);
                        e.Have[ci] = true;
                        e.Dirty = true;
                        e.Remaining--;
                        fresh = true;
                    }
                }
                if (fresh)
                {
                    Interlocked.Add(ref x.DoneBytes, len);
                    if (e.Remaining == 0) FinalizeFile(x, e, true);
                }
                WriteLine(ns, "OK|" + fi + "|" + ci);
            }
            else
            {
                WriteLine(ns, "BAD|" + fi + "|" + ci);
            }
        }
    }

    private void SaveMaps(EarthXfer x)
    {
        foreach (EarthFileEntry e in x.Files)
        {
            string bits = null;
            lock (e)
            {
                if (!e.Done && e.Have != null && e.Dirty)
                {
                    StringBuilder sb = new StringBuilder();
                    for (int i = 0; i < e.Chunks; i++) sb.Append(e.Have[i] ? '1' : '0');
                    bits = sb.ToString();
                    e.Dirty = false;
                    try { if (e.Fs != null) e.Fs.Flush(true); } catch (Exception) { }
                }
            }
            if (bits != null)
            {
                try { File.WriteAllText(e.MapPath, e.Size + "|" + e.MTimeTicks + "|" + x.ChunkSize + "\n" + bits); } catch (Exception) { }
            }
        }
    }

    private void CloseStreams(EarthXfer x)
    {
        foreach (EarthFileEntry e in x.Files)
        {
            lock (e)
            {
                if (e.Fs != null)
                {
                    try { e.Fs.Flush(true); e.Fs.Close(); } catch (Exception) { }
                    e.Fs = null;
                }
            }
        }
    }

    // ---------------- Senden ----------------
    private void CollectPath(string path, string relPrefix, List<EarthFileEntry> list)
    {
        try
        {
            FileAttributes at = File.GetAttributes(path);
            if ((at & FileAttributes.Directory) != 0)
            {
                if ((at & FileAttributes.ReparsePoint) != 0) return;
                string name = Path.GetFileName(path.TrimEnd('\\', '/'));
                if (name.Length == 0) name = "Ordner";
                string prefix = (relPrefix.Length > 0) ? (relPrefix + "/" + name) : name;
                foreach (string f in Directory.GetFiles(path)) CollectPath(f, prefix, list);
                foreach (string d in Directory.GetDirectories(path)) CollectPath(d, prefix, list);
            }
            else
            {
                FileInfo fi = new FileInfo(path);
                EarthFileEntry e = new EarthFileEntry();
                e.Full = path;
                e.Rel = (relPrefix.Length > 0) ? (relPrefix + "/" + fi.Name) : fi.Name;
                e.Size = fi.Length;
                e.MTimeTicks = fi.LastWriteTimeUtc.Ticks;
                list.Add(e);
            }
        }
        catch (Exception) { }
    }

    public string SendPaths(string peerIp, string peerName, string[] paths)
    {
        List<EarthFileEntry> list = new List<EarthFileEntry>();
        foreach (string p in paths) CollectPath(p, "", list);
        if (list.Count == 0) return "Keine lesbaren Dateien gefunden.";
        if (list.Count > 200000) return "Zu viele Dateien (max. 200000 pro Uebertragung).";
        EarthXfer x = new EarthXfer();
        x.Id = Guid.NewGuid().ToString("N").Substring(0, 16);
        x.Outgoing = true;
        x.PeerName = CleanName(peerName);
        x.PeerIp = peerIp;
        x.ChunkSize = 2097152;
        long total = 0;
        foreach (EarthFileEntry e in list)
        {
            e.Chunks = (int)((e.Size + x.ChunkSize - 1) / x.ChunkSize);
            total += e.Size;
        }
        x.Files = list;
        x.TotalBytes = total;
        x.Title = (list.Count == 1) ? list[0].Rel : (list.Count + " Dateien");
        x.Status = "Verbinde ...";
        lock (lk) { xfers[x.Id] = x; }
        Thread t = new Thread(() => SendWorker(x, peerIp));
        t.IsBackground = true;
        t.Start();
        return null;
    }

    private void SendWorker(EarthXfer x, string ip)
    {
        try
        {
            int attempt = 0;
            while (!x.Cancel && attempt < 6)
            {
                attempt++;
                x.Status = (attempt == 1) ? "Warte auf Zustimmung ..." : ("Verbindung wird wiederhergestellt (" + attempt + ") ...");
                bool[][] have;
                string token;
                string err;
                if (!Handshake(x, ip, out have, out token, out err))
                {
                    if (err != null && err.StartsWith("DENY"))
                    {
                        x.Failed = true;
                        x.Status = "Abgelehnt";
                        return;
                    }
                    x.Status = "Keine Verbindung - neuer Versuch ...";
                    Thread.Sleep(4000);
                    continue;
                }
                x.Token = token;
                x.Status = "Sende ...";
                if (TransferData(x, ip, have))
                {
                    x.Status = "Fertig";
                    return;
                }
                if (x.Cancel || x.RemoteAbort) break;
                x.Status = "Unterbrochen - versuche Fortsetzen ...";
                Thread.Sleep(4000);
            }
            if (x.Cancel) x.Status = "Abgebrochen";
            else if (x.RemoteAbort) { x.Failed = true; x.Status = "Vom Empfaenger abgebrochen"; }
            else { x.Failed = true; x.Status = "Unterbrochen - erneut senden setzt fort"; }
        }
        catch (Exception ex)
        {
            x.Failed = true;
            x.Status = "Fehler: " + ex.Message.Replace("|", "/");
        }
        finally
        {
            x.Finished = true;
        }
    }

    private bool Handshake(EarthXfer x, string ip, out bool[][] have, out string token, out string err)
    {
        have = null;
        token = null;
        err = null;
        TcpClient c = TryConnect(ip, 3000);
        if (c == null) { err = "Keine Verbindung"; return false; }
        try
        {
            c.NoDelay = true;
            c.ReceiveTimeout = 90000;
            c.SendTimeout = 30000;
            NetworkStream ns = c.GetStream();
            StringBuilder sb = new StringBuilder();
            sb.Append("OFFER|" + x.Id + "|" + NodeId + "|" + NodeName + "|" + x.Files.Count + "|" + x.TotalBytes + "|" + x.ChunkSize + "\n");
            foreach (EarthFileEntry e in x.Files) sb.Append("F|" + e.Rel + "|" + e.Size + "|" + e.MTimeTicks + "\n");
            sb.Append("END\n");
            byte[] ob = Encoding.UTF8.GetBytes(sb.ToString());
            ns.Write(ob, 0, ob.Length);
            EarthReader rd = new EarthReader(ns);
            string r = rd.ReadLine();
            if (r == null) { err = "Keine Antwort"; return false; }
            if (r.StartsWith("DENY")) { err = r; return false; }
            string[] rf = r.Split('|');
            if (rf[0] != "ACCEPT" || rf.Length < 2) { err = "Protokollfehler"; return false; }
            token = rf[1];
            have = new bool[x.Files.Count][];
            for (int i = 0; i < x.Files.Count; i++) have[i] = new bool[x.Files[i].Chunks];
            while (true)
            {
                string l = rd.ReadLine();
                if (l == null) { err = "Abbruch im Handshake"; return false; }
                if (l == "GO") break;
                string[] hf = l.Split('|');
                int idx;
                if (hf.Length >= 3 && hf[0] == "H" && int.TryParse(hf[1], out idx) && idx >= 0 && idx < have.Length)
                {
                    string bm = hf[2];
                    int n = Math.Min(bm.Length, have[idx].Length);
                    for (int j = 0; j < n; j++) have[idx][j] = (bm[j] == '1');
                }
            }
            return true;
        }
        catch (Exception ex)
        {
            err = ex.Message;
            return false;
        }
        finally { try { c.Close(); } catch (Exception) { } }
    }

    private bool TransferData(EarthXfer x, string ip, bool[][] have)
    {
        EarthSendState st = new EarthSendState();
        long already = 0;
        for (int fi = 0; fi < x.Files.Count; fi++)
        {
            EarthFileEntry e = x.Files[fi];
            for (int ci = 0; ci < e.Chunks; ci++)
            {
                if (have[fi][ci]) already += ChunkLen(e.Size, ci, x.ChunkSize);
                else st.Jobs.Enqueue(new int[] { fi, ci, 0 });
            }
        }
        Interlocked.Exchange(ref x.DoneBytes, already);
        st.Remaining = st.Jobs.Count;
        if (st.Remaining == 0) return true;

        int streams = Math.Max(1, Math.Min(8, Streams));
        List<Thread> threads = new List<Thread>();
        for (int i = 0; i < streams; i++)
        {
            Thread t = new Thread(() => DataSender(x, ip, st));
            t.IsBackground = true;
            t.Start();
            threads.Add(t);
        }
        foreach (Thread t in threads) t.Join();
        if (st.Abort) x.RemoteAbort = true;
        int rem;
        lock (st.Lk) { rem = st.Remaining; }
        return (rem <= 0 && !x.Cancel);
    }

    private void DataSender(EarthXfer x, string ip, EarthSendState st)
    {
        TcpClient c = null;
        NetworkStream ns = null;
        EarthReader rd = null;
        byte[] buf = new byte[x.ChunkSize];
        int failures = 0;
        try
        {
            while (!x.Cancel && !st.Abort)
            {
                int[] job = null;
                lock (st.Lk)
                {
                    if (st.Jobs.Count > 0) job = st.Jobs.Dequeue();
                    else if (st.Remaining <= 0) break;
                }
                if (job == null) { Thread.Sleep(50); continue; }

                bool ok = false;
                try
                {
                    if (c == null)
                    {
                        c = TryConnect(ip, 3000);
                        if (c == null) throw new IOException("Verbindung fehlgeschlagen");
                        c.NoDelay = true;
                        c.ReceiveTimeout = 30000;
                        c.SendTimeout = 30000;
                        c.SendBufferSize = 1048576;
                        ns = c.GetStream();
                        rd = new EarthReader(ns);
                        WriteLine(ns, "DATA|" + x.Id + "|" + x.Token);
                        string rr = rd.ReadLine();
                        if (rr == "NO") { st.Abort = true; throw new IOException("Vom Empfaenger abgelehnt"); }
                        if (rr != "READY") throw new IOException("Datenkanal abgelehnt");
                    }
                    EarthFileEntry e = x.Files[job[0]];
                    int len = ChunkLen(e.Size, job[1], x.ChunkSize);
                    using (FileStream fs = new FileStream(e.Full, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                    {
                        fs.Seek((long)job[1] * x.ChunkSize, SeekOrigin.Begin);
                        int got = 0;
                        while (got < len)
                        {
                            int r = fs.Read(buf, got, len - got);
                            if (r <= 0) break;
                            got += r;
                        }
                        if (got != len) throw new IOException("Datei hat sich waehrend der Uebertragung geaendert");
                    }
                    string hash = Sha256Hex(buf, len);
                    throttle.Wait(len, LimitBytesPerSec);
                    byte[] hb = Encoding.UTF8.GetBytes("C|" + job[0] + "|" + job[1] + "|" + len + "|" + hash + "\n");
                    ns.Write(hb, 0, hb.Length);
                    ns.Write(buf, 0, len);
                    string ack = rd.ReadLine();
                    if (ack == null) throw new IOException("Verbindung verloren");
                    ok = ack.StartsWith("OK|");
                    if (ok) Interlocked.Add(ref x.DoneBytes, len);
                }
                catch (Exception)
                {
                    failures++;
                    if (c != null) { try { c.Close(); } catch (Exception) { } }
                    c = null;
                    ns = null;
                    rd = null;
                }

                if (ok)
                {
                    lock (st.Lk) { st.Remaining--; }
                }
                else
                {
                    job[2]++;
                    lock (st.Lk) { st.Jobs.Enqueue(job); }
                    if (st.Abort || job[2] > 8 || failures > 30) break;
                    Thread.Sleep(Math.Min(8000, 300 * (1 << Math.Min(failures, 5))));
                }
            }
        }
        finally
        {
            if (c != null)
            {
                try { if (ns != null) WriteLine(ns, "BYE"); } catch (Exception) { }
                try { c.Close(); } catch (Exception) { }
            }
        }
    }

    // ---------------- Anzeige ----------------
    private static string CleanField(string s)
    {
        if (s == null) return "";
        return s.Replace("|", "/").Replace("\r", " ").Replace("\n", " ");
    }

    public string[] GetTransfers()
    {
        List<EarthXfer> list = new List<EarthXfer>();
        lock (lk) { foreach (KeyValuePair<string, EarthXfer> kv in xfers) list.Add(kv.Value); }
        List<string> res = new List<string>();
        int now = Environment.TickCount;
        foreach (EarthXfer x in list)
        {
            long done = Interlocked.Read(ref x.DoneBytes);
            if (x.LastTick == 0) { x.LastTick = now; x.LastBytes = done; x.LastProgress = now; }
            int dt = now - x.LastTick;
            if (dt >= 400)
            {
                double inst = (done - x.LastBytes) * 1000.0 / dt;
                if (inst < 0) inst = 0;
                x.Speed = x.Speed * 0.6 + inst * 0.4;
                if (done != x.LastBytes) x.LastProgress = now;
                x.LastBytes = done;
                x.LastTick = now;
            }
            if (x.Finished) x.Speed = 0;
            string status = x.Status;
            if (!x.Finished && !x.Outgoing && x.Accepted && (now - x.LastProgress) > 10000 && done < x.TotalBytes) status = "Wartet auf Sender (Fortsetzen moeglich)";
            double eta = -1;
            if (x.Speed > 1024 && x.TotalBytes > done) eta = (x.TotalBytes - done) / x.Speed;
            res.Add(x.Id + "|" + (x.Outgoing ? "Senden" : "Empfangen") + "|" + CleanField(x.PeerName) + "|" + CleanField(x.Title) + "|" + x.TotalBytes + "|" + done + "|" + ((long)x.Speed) + "|" + ((long)eta) + "|" + CleanField(status) + "|" + (x.Finished ? "1" : "0") + "|" + (x.Failed ? "1" : "0"));
        }
        return res.ToArray();
    }

    public void AnswerOffer(string id, bool accept)
    {
        EarthXfer x = null;
        lock (lk) { xfers.TryGetValue(id, out x); }
        if (x == null) return;
        x.Accepted = accept;
        x.Decision.Set();
    }

    public void CancelTransfer(string id)
    {
        EarthXfer x = null;
        lock (lk) { xfers.TryGetValue(id, out x); }
        if (x == null || x.Finished) return;
        x.Cancel = true;
        x.Decision.Set();
        x.Status = "Abgebrochen";
        if (!x.Outgoing)
        {
            SaveMaps(x);
            CloseStreams(x);
            x.Failed = true;
            x.Finished = true;
        }
    }

    public void RemoveFinished()
    {
        lock (lk)
        {
            List<string> dead = new List<string>();
            foreach (KeyValuePair<string, EarthXfer> kv in xfers) { if (kv.Value.Finished) dead.Add(kv.Key); }
            foreach (string d in dead) xfers.Remove(d);
        }
    }
}
'@
        Add-Type -TypeDefinition $fileCode -Language CSharp
    }
}



function Initialize-ChatTypes {
    if (-not ('EarthChatNode' -as [type])) {
        $chatCode = @'
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

public static class EarthChatFlash
{
    [StructLayout(LayoutKind.Sequential)]
    public struct FLASHWINFO
    {
        public uint cbSize;
        public IntPtr hwnd;
        public uint dwFlags;
        public uint uCount;
        public uint dwTimeout;
    }

    [DllImport("user32.dll")]
    private static extern bool FlashWindowEx(ref FLASHWINFO pwfi);

    public static void Flash(IntPtr hwnd)
    {
        FLASHWINFO fi = new FLASHWINFO();
        fi.cbSize = (uint)Marshal.SizeOf(typeof(FLASHWINFO));
        fi.hwnd = hwnd;
        fi.dwFlags = 0x0000000F;
        fi.uCount = 3;
        fi.dwTimeout = 0;
        FlashWindowEx(ref fi);
    }
}

public static class EarthChatNet
{
    public static uint ToUInt(IPAddress a)
    {
        byte[] b = a.GetAddressBytes();
        return ((uint)b[0] << 24) | ((uint)b[1] << 16) | ((uint)b[2] << 8) | (uint)b[3];
    }

    public static string FromUInt(uint v)
    {
        return string.Format("{0}.{1}.{2}.{3}", (v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255);
    }

    public static string[] HostRange(string ip, string mask, int maxHosts)
    {
        uint ipN = ToUInt(IPAddress.Parse(ip));
        uint mk = ToUInt(IPAddress.Parse(mask));
        uint net = ipN & mk;
        uint bcast = net | ~mk;
        if (bcast - net < 2) return new string[0];
        uint first = net + 1;
        uint last = bcast - 1;
        if ((long)(last - first) + 1 > maxHosts)
        {
            net = ipN & 0xFFFFFF00u;
            first = net + 1;
            last = (net | 0xFFu) - 1;
        }
        List<string> list = new List<string>();
        for (uint x = first; x <= last; x++) list.Add(FromUInt(x));
        return list.ToArray();
    }
}

public class EarthChatPeer
{
    public TcpClient Client;
    public StreamWriter Writer;
    public bool Outgoing;
    public string Id;
    public string Name = "";
    public string Ip = "";
    public string Chan = "";
}

public class EarthChatNode
{

    private static long lastBanLoad;
    private static HashSet<string> bannedIps = new HashSet<string>();
    private static readonly object banLock = new object();
    protected static bool IsIpBanned(string ip)
    {
        long now = Environment.TickCount;
        lock (banLock)
        {
            if (now - lastBanLoad > 4000 || now < lastBanLoad)
            {
                lastBanLoad = now;
                try
                {
                    HashSet<string> next = new HashSet<string>();
                    string path = @"C:\Project-Earth-Lan\ip_bans.json";
                    if (File.Exists(path))
                    {
                        string txt = File.ReadAllText(path, Encoding.UTF8);
                        foreach (Match m in Regex.Matches(txt, @"""Ip""\s*:\s*""([^""]*)""[^}]*?""Deleted""\s*:\s*(true|false)"))
                        {
                            if (m.Groups[2].Value == "false") next.Add(m.Groups[1].Value);
                        }
                    }
                    bannedIps = next;
                }
                catch (Exception) { }
            }
            return bannedIps.Contains(ip);
        }
    }

    public const int PortNumber = 9874;
    public ConcurrentQueue<string> Events = new ConcurrentQueue<string>();
    public string NodeId;
    public string NodeName;
    public string BindIp;
    public string Mask = "";
    public volatile bool ScanRunning;
    public int ScanDone;
    public int ScanTotal;

    private TcpListener listener;
    private UdpClient beaconRx;
    private volatile bool running;
    private volatile bool scanCancel;
    private readonly object peerLock = new object();
    private readonly object nameLock = new object();
    private readonly object chanLock = new object();
    private string myChan = "";
    private Dictionary<string, EarthChatPeer> peers = new Dictionary<string, EarthChatPeer>();
    private readonly Dictionary<string, int> lastDial = new Dictionary<string, int>();

    public EarthChatNode(string bindIp, string nodeName)
    {
        BindIp = bindIp;
        NodeName = CleanName(nodeName);
        NodeId = Guid.NewGuid().ToString("N").Substring(0, 12);
    }

    private static string CleanName(string s)
    {
        if (s == null) return "";
        s = s.Replace("\r", " ").Replace("\n", " ").Replace("|", "/").Trim();
        if (s.Length > 32) s = s.Substring(0, 32);
        return s;
    }

    private static string CleanLine(string s)
    {
        if (s == null) return "";
        return s.Replace("\r", " ").Replace("\n", " ");
    }

    private string CurrentName()
    {
        lock (nameLock) { return NodeName; }
    }

    private string CurrentChan()
    {
        lock (chanLock) { return myChan; }
    }

    // ---------------- Start / Stop ----------------
    public string Start()
    {
        try
        {
            listener = new TcpListener(IPAddress.Parse(BindIp), PortNumber);
            listener.Start();
            running = true;
            Thread t = new Thread(AcceptLoop);
            t.IsBackground = true;
            t.Start();
            StartBeacon();
            return null;
        }
        catch (Exception ex)
        {
            return ex.Message;
        }
    }

    public void Stop()
    {
        running = false;
        scanCancel = true;
        try { if (listener != null) listener.Stop(); } catch (Exception) { }
        try { if (beaconRx != null) beaconRx.Close(); } catch (Exception) { }
        foreach (EarthChatPeer p in SnapshotPeers()) { try { p.Client.Close(); } catch (Exception) { } }
    }

    private List<EarthChatPeer> SnapshotPeers()
    {
        List<EarthChatPeer> list = new List<EarthChatPeer>();
        lock (peerLock) { foreach (KeyValuePair<string, EarthChatPeer> kv in peers) list.Add(kv.Value); }
        return list;
    }

    // ---------------- Automatische Erkennung ----------------
    private void StartBeacon()
    {
        try
        {
            beaconRx = new UdpClient(AddressFamily.InterNetwork);
            beaconRx.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
            beaconRx.Client.Bind(new IPEndPoint(IPAddress.Any, PortNumber));
            try { beaconRx.Client.IOControl((IOControlCode)(-1744830452), new byte[] { 0, 0, 0, 0 }, null); } catch (Exception) { }
            Thread rt = new Thread(BeaconRxLoop);
            rt.IsBackground = true;
            rt.Start();
        }
        catch (Exception)
        {
            beaconRx = null;
            Events.Enqueue("SYS|Automatische Suche (UDP 9874) nicht verfuegbar - bitte IP manuell eingeben.");
        }
        Thread tt = new Thread(BeaconTxLoop);
        tt.IsBackground = true;
        tt.Start();
    }

    private void BeaconRxLoop()
    {
        IPEndPoint ep = new IPEndPoint(IPAddress.Any, 0);
        while (running)
        {
            byte[] d;
            try { d = beaconRx.Receive(ref ep); }
            catch (Exception)
            {
                if (!running) break;
                Thread.Sleep(50);
                continue;
            }
            try
            {
                string ip = ep.Address.ToString();
                if (IsIpBanned(ip)) continue;
                string[] f = Encoding.UTF8.GetString(d).Split('|');
                if (f.Length < 3 || f[0] != "PECHAT1B" || f[1] == NodeId) continue;
                if (ip == BindIp || IsConnectedIp(ip)) continue;
                int now = Environment.TickCount;
                int last;
                lock (lastDial)
                {
                    if (lastDial.TryGetValue(ip, out last) && (now - last) < 4000) continue;
                    lastDial[ip] = now;
                }
                string ipc = ip;
                string peerName = CleanName(f[2]);
                Thread t = new Thread(() =>
                {
                    TcpClient c = TryConnect(ipc, 1500);
                    if (c != null)
                    {
                        Events.Enqueue("SYS|Teilnehmer automatisch gefunden: " + peerName + " (" + ipc + ")");
                        StartOutgoing(c);
                    }
                });
                t.IsBackground = true;
                t.Start();
            }
            catch (Exception) { }
        }
    }

    private void BeaconTxLoop()
    {
        UdpClient tx = null;
        IPEndPoint bc1 = new IPEndPoint(IPAddress.Broadcast, PortNumber);
        IPEndPoint bc2 = null;
        try
        {
            tx = new UdpClient(new IPEndPoint(IPAddress.Parse(BindIp), 0));
            tx.EnableBroadcast = true;
            if (!string.IsNullOrEmpty(Mask))
            {
                uint ipN = EarthChatNet.ToUInt(IPAddress.Parse(BindIp));
                uint mk = EarthChatNet.ToUInt(IPAddress.Parse(Mask));
                bc2 = new IPEndPoint(IPAddress.Parse(EarthChatNet.FromUInt(ipN | ~mk)), PortNumber);
            }
        }
        catch (Exception) { return; }
        while (running)
        {
            try
            {
                byte[] msg = Encoding.UTF8.GetBytes("PECHAT1B|" + NodeId + "|" + CurrentName());
                tx.Send(msg, msg.Length, bc1);
                if (bc2 != null) tx.Send(msg, msg.Length, bc2);
            }
            catch (Exception) { }
            for (int i = 0; i < 30 && running; i++) Thread.Sleep(100);
        }
        try { tx.Close(); } catch (Exception) { }
    }

    // ---------------- Verbindungen ----------------
    private void AcceptLoop()
    {
        while (running)
        {
            try
            {
                TcpClient c = listener.AcceptTcpClient();
                EarthChatPeer p = new EarthChatPeer();
                p.Client = c;
                p.Outgoing = false;
                p.Ip = ((IPEndPoint)c.Client.RemoteEndPoint).Address.ToString();
                Thread t = new Thread(() => PeerLoop(p));
                t.IsBackground = true;
                t.Start();
            }
            catch (Exception)
            {
                if (!running) break;
                Thread.Sleep(50);
            }
        }
    }

    private void Send(EarthChatPeer p, string line)
    {
        try
        {
            lock (p) { p.Writer.WriteLine(line); }
        }
        catch (Exception) { }
    }

    private void PeerLoop(EarthChatPeer p)
    {
        try
        {
            if (IsIpBanned(p.Ip)) return;
            NetworkStream ns = p.Client.GetStream();
            p.Client.NoDelay = true;
            p.Client.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.KeepAlive, true);
            p.Writer = new StreamWriter(ns, new UTF8Encoding(false));
            p.Writer.AutoFlush = true;
            p.Writer.NewLine = "\n";
            StreamReader rd = new StreamReader(ns, Encoding.UTF8);
            Send(p, "HELLO|PECHAT1|" + NodeId + "|" + CurrentName() + "|" + CurrentChan());
            p.Client.ReceiveTimeout = 5000;
            string line = rd.ReadLine();
            if (line == null) return;
            string[] f = line.Split(new char[] { '|' }, 5);
            if (f.Length < 4 || f[0] != "HELLO" || f[1] != "PECHAT1") return;
            p.Id = f[2];
            p.Name = CleanName(f[3]);
            p.Chan = f.Length >= 5 ? CleanName(f[4]) : "";
            if (p.Id == NodeId) return;
            if (!Register(p)) return;
            p.Client.ReceiveTimeout = 0;
            while (running)
            {
                line = rd.ReadLine();
                if (line == null) break;
                HandleLine(p, line);
            }
        }
        catch (Exception) { }
        finally
        {
            Unregister(p);
            try { p.Client.Close(); } catch (Exception) { }
        }
    }

    private bool Register(EarthChatPeer p)
    {
        lock (peerLock)
        {
            EarthChatPeer ex;
            if (peers.TryGetValue(p.Id, out ex))
            {
                string exInit = ex.Outgoing ? NodeId : ex.Id;
                string newInit = p.Outgoing ? NodeId : p.Id;
                if (string.CompareOrdinal(newInit, exInit) < 0)
                {
                    peers[p.Id] = p;
                    try { ex.Client.Close(); } catch (Exception) { }
                    Events.Enqueue("PEER+|" + p.Id + "|" + p.Name + "|" + p.Ip);
                    return true;
                }
                return false;
            }
            peers[p.Id] = p;
        }
        Events.Enqueue("PEER+|" + p.Id + "|" + p.Name + "|" + p.Ip);
        return true;
    }

    private void Unregister(EarthChatPeer p)
    {
        bool removed = false;
        lock (peerLock)
        {
            EarthChatPeer cur;
            if (p.Id != null && peers.TryGetValue(p.Id, out cur) && object.ReferenceEquals(cur, p))
            {
                peers.Remove(p.Id);
                removed = true;
            }
        }
        if (removed) Events.Enqueue("PEER-|" + p.Id + "|" + p.Name + "|" + p.Ip);
    }

    private void HandleLine(EarthChatPeer p, string line)
    {
        if (line.Length > 8000) return;
        if (line.StartsWith("MSG|"))
        {
            Events.Enqueue("CHAT|" + p.Id + "|" + p.Name + "|" + line.Substring(4));
        }
        else if (line.StartsWith("PM|"))
        {
            Events.Enqueue("PM|" + p.Id + "|" + p.Name + "|" + line.Substring(3));
        }
        else if (line.StartsWith("NICK|"))
        {
            string nn = CleanName(line.Substring(5));
            if (nn.Length > 0)
            {
                string old = p.Name;
                p.Name = nn;
                Events.Enqueue("NICK|" + p.Id + "|" + old + "|" + nn);
            }
        }
        else if (line.StartsWith("CHAN|"))
        {
            p.Chan = CleanName(line.Substring(5));
        }
    }

    // ---------------- Kanaele ----------------
    public string GetMyChannel()
    {
        return CurrentChan();
    }

    public void SetChannel(string name)
    {
        name = CleanName(name);
        lock (chanLock) { myChan = name; }
        foreach (EarthChatPeer p in SnapshotPeers()) Send(p, "CHAN|" + name);
    }

    // ---------------- Nachrichten ----------------
    public int Broadcast(string text)
    {
        List<EarthChatPeer> list = SnapshotPeers();
        foreach (EarthChatPeer p in list) Send(p, "MSG|" + CleanLine(text));
        return list.Count;
    }

    // Sendet nur an Teilnehmer, deren aktueller Kanal exakt uebereinstimmt (temporaer
    // oder dauerhaft - die Kanal-Registrierung selbst lebt in FriendAndChannelManager,
    // hier zaehlt nur der aktuell gemeldete Kanalname jedes verbundenen Peers).
    public int SendToChannel(string channel, string text)
    {
        List<EarthChatPeer> list = SnapshotPeers();
        int n = 0;
        foreach (EarthChatPeer p in list)
        {
            if (p.Chan == channel) { Send(p, "MSG|" + CleanLine(text)); n++; }
        }
        return n;
    }

    public bool SendPrivate(string peerId, string text)
    {
        EarthChatPeer p = null;
        lock (peerLock) { peers.TryGetValue(peerId, out p); }
        if (p == null) return false;
        Send(p, "PM|" + CleanLine(text));
        return true;
    }

    public void SetName(string name)
    {
        string n = CleanName(name);
        if (n.Length == 0) return;
        lock (nameLock) { NodeName = n; }
        foreach (EarthChatPeer p in SnapshotPeers()) Send(p, "NICK|" + n);
    }

    public int PeerCount()
    {
        lock (peerLock) { return peers.Count; }
    }

    public string[] GetPeers()
    {
        List<string> l = new List<string>();
        lock (peerLock)
        {
            foreach (KeyValuePair<string, EarthChatPeer> kv in peers) l.Add(kv.Value.Id + "|" + kv.Value.Name + "|" + kv.Value.Ip + "|" + kv.Value.Chan);
        }
        return l.ToArray();
    }

    private bool IsConnectedIp(string ip)
    {
        lock (peerLock)
        {
            foreach (KeyValuePair<string, EarthChatPeer> kv in peers) { if (kv.Value.Ip == ip) return true; }
        }
        return false;
    }

    private TcpClient TryConnect(string ip, int timeoutMs)
    {
        TcpClient c = new TcpClient(AddressFamily.InterNetwork);
        try
        {
            IAsyncResult ar = c.BeginConnect(IPAddress.Parse(ip), PortNumber, null, null);
            if (ar.AsyncWaitHandle.WaitOne(timeoutMs))
            {
                c.EndConnect(ar);
                return c;
            }
        }
        catch (Exception) { }
        try { c.Close(); } catch (Exception) { }
        return null;
    }

    private void StartOutgoing(TcpClient c)
    {
        EarthChatPeer p = new EarthChatPeer();
        p.Client = c;
        p.Outgoing = true;
        p.Ip = ((IPEndPoint)c.Client.RemoteEndPoint).Address.ToString();
        Thread t = new Thread(() => PeerLoop(p));
        t.IsBackground = true;
        t.Start();
    }

    public void ConnectTo(string ip)
    {
        Thread t = new Thread(() =>
        {
            if (ip == BindIp) { Events.Enqueue("SYS|Das ist die eigene Adresse."); return; }
            if (IsConnectedIp(ip)) { Events.Enqueue("SYS|Bereits verbunden mit " + ip); return; }
            TcpClient c = TryConnect(ip, 2000);
            if (c == null) Events.Enqueue("SYS|Keine Verbindung zu " + ip + ":9874 (Chat dort nicht geoeffnet?)");
            else StartOutgoing(c);
        });
        t.IsBackground = true;
        t.Start();
    }

    public void ScanAsync(string[] ips)
    {
        if (ScanRunning) return;
        ScanRunning = true;
        scanCancel = false;
        ScanDone = 0;
        ScanTotal = ips.Length;
        Thread t = new Thread(() =>
        {
            try
            {
                int w, c2;
                ThreadPool.GetMinThreads(out w, out c2);
                if (w < 100) ThreadPool.SetMinThreads(100, c2);
                ParallelOptions po = new ParallelOptions();
                po.MaxDegreeOfParallelism = 48;
                Parallel.ForEach(ips, po, ip =>
                {
                    if (scanCancel || !running) return;
                    if (ip != BindIp && !IsConnectedIp(ip))
                    {
                        TcpClient c = TryConnect(ip, 600);
                        if (c != null) StartOutgoing(c);
                    }
                    Interlocked.Increment(ref ScanDone);
                });
            }
            catch (Exception) { }
            ScanRunning = false;
            Events.Enqueue("SYS|Scan nach Port 9874 abgeschlossen.");
        });
        t.IsBackground = true;
        t.Start();
    }
}
'@
        Add-Type -TypeDefinition $chatCode -Language CSharp
    }
}

# ------------------------------------------------------------------------------
# OPTION 10: Kommunikationszentrale - Chat, Dateien senden und Voice in einem Fenster
# ------------------------------------------------------------------------------
function Invoke-CommCenter {

    Initialize-ChatTypes
    Initialize-FileTypes
    Initialize-VoiceTypes
    Initialize-SocialTypes

    $st = @{
        Adapters    = @()
        Loading     = $true
        Panel       = 0
        Tick        = 0
        Nick        = $env:USERNAME
        # Chat
        ChatNode    = $null
        ChatItems   = @{}
        ChatChanItems = @{}
        ChatKnown   = @{}
        PmUnread    = @{}
        ChatUnread  = 0
        ChatFw      = $false
        ChatFriendsOnly = $false
        # Dateien
        FileNode    = $null
        FileTarget  = $null
        FilePeers   = @{}
        FileItems   = @{}
        FileFw      = $false
        DownloadDir = (Join-Path ([System.Environment]::GetFolderPath('UserProfile')) 'Downloads\ProjectEarthLAN')
        # Voice
        VoiceNode   = $null
        VoiceFw     = $false
        VcPeers     = @{}
        VcChans     = @{}
        InDev       = -1
        OutDev      = -1
        InName      = ''
        OutName     = ''
        VoiceFriendsOnly = $false
        # Kanal-Synchronisation (permanente, gespeicherte Voice-Kanäle - Port 9776)
        SocialNode  = $null
        SocialFw    = $false
    }
    # Sicherheit & Social: eigene Verwaltung (Ban/Freunde/Kanäle/Poke) direkt in der
    # Kommunikationszentrale, für das Kontextmenü der Teilnehmerlisten.
    $ccBans   = New-Object BanManager
    $ccSocial = New-Object FriendAndChannelManager
    $ccPokes  = New-Object PokeManager
    $dataDir = Join-Path $env:APPDATA 'ProjectEarthLan'
    $chatCfg = Join-Path $dataDir 'chat.json'
    $fileCfg = Join-Path $dataDir 'fileshare.json'
    $voiceCfg = Join-Path $dataDir 'voice.json'
    $histDir = Join-Path $dataDir 'chat'
    $baseTitle = "Project Earth LAN - Kommunikationszentrale"

    $cWhite  = [System.Drawing.Color]::White
    $cAccent = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $cBtn    = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $cInput  = [System.Drawing.Color]::FromArgb(50, 50, 50)
    $cList   = [System.Drawing.Color]::FromArgb(40, 40, 40)
    $cBack   = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $fontMain = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Regular)
    $fontBold = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

    # ===================================================================================
    # Allgemeine Hilfsfunktionen
    # ===================================================================================
    # Kurzschreibweise fuer Control.Anchor, damit Fenster/Bereiche frei in der Größe
    # verändert werden können und Listen/Textfelder automatisch mitskalieren, statt
    # bei Größenänderung abgeschnitten zu werden oder Leerraum zu lassen.
    function Set-CcAnchor($ctrl, [string[]]$sides) {
        $v = [System.Windows.Forms.AnchorStyles]::None
        foreach ($s in $sides) { $v = $v -bor [System.Windows.Forms.AnchorStyles]::$s }
        $ctrl.Anchor = $v
    }

    function New-CcButton([string]$text, [int]$x, [int]$y, [int]$w, [int]$h, [bool]$accent = $false) {
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $text
        $b.Location = New-Object System.Drawing.Point($x, $y)
        $b.Size = New-Object System.Drawing.Size($w, $h)
        $b.FlatStyle = "Flat"
        $b.ForeColor = $cWhite
        $b.Font = $fontBold
        if ($accent) { $b.BackColor = $cAccent } else { $b.BackColor = $cBtn }
        return $b
    }

    function New-CcLabel([string]$text, [int]$x, [int]$y, [int]$w, [int]$h) {
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $text
        $l.Location = New-Object System.Drawing.Point($x, $y)
        $l.Size = New-Object System.Drawing.Size($w, $h)
        $l.ForeColor = $cWhite
        $l.Font = $fontMain
        return $l
    }

    function New-CcText([int]$x, [int]$y, [int]$w, [int]$h) {
        $t = New-Object System.Windows.Forms.TextBox
        $t.Location = New-Object System.Drawing.Point($x, $y)
        $t.Size = New-Object System.Drawing.Size($w, $h)
        $t.BackColor = $cInput
        $t.ForeColor = $cWhite
        $t.Font = $fontMain
        return $t
    }

    function New-CcListView([int]$x, [int]$y, [int]$w, [int]$h, [string[]]$cols, [int[]]$widths) {
        $lv = New-Object System.Windows.Forms.ListView
        $lv.Location = New-Object System.Drawing.Point($x, $y)
        $lv.Size = New-Object System.Drawing.Size($w, $h)
        $lv.View = "Details"
        $lv.FullRowSelect = $true
        $lv.HideSelection = $false
        $lv.MultiSelect = $false
        $lv.BackColor = $cList
        $lv.ForeColor = $cWhite
        $lv.Font = $fontMain
        for ($i = 0; $i -lt $cols.Count; $i++) { [void]$lv.Columns.Add($cols[$i], $widths[$i]) }
        return $lv
    }

    function New-CcNumeric([int]$x, [int]$y, [int]$w, [int]$min, [int]$max, [int]$value) {
        $n = New-Object System.Windows.Forms.NumericUpDown
        $n.Location = New-Object System.Drawing.Point($x, $y)
        $n.Size = New-Object System.Drawing.Size($w, 24)
        $n.Minimum = $min
        $n.Maximum = $max
        $n.Value = $value
        $n.BackColor = $cInput
        $n.ForeColor = $cWhite
        $n.Font = $fontMain
        return $n
    }

    function New-CcRtb([int]$x, [int]$y, [int]$w, [int]$h) {
        $r = New-Object System.Windows.Forms.RichTextBox
        $r.Location = New-Object System.Drawing.Point($x, $y)
        $r.Size = New-Object System.Drawing.Size($w, $h)
        $r.ReadOnly = $true
        $r.BackColor = $cList
        $r.ForeColor = $cWhite
        $r.Font = $fontMain
        return $r
    }

    function Show-CcMsg([string]$text, [string]$title = "Kommunikationszentrale", $icon = [System.Windows.Forms.MessageBoxIcon]::Information) {
        [System.Windows.Forms.MessageBox]::Show($text, $title, [System.Windows.Forms.MessageBoxButtons]::OK, $icon) | Out-Null
    }

    function Add-CcRtb($rtb, [string]$text, $color, [bool]$stamp = $true) {
        $rtb.SelectionStart = $rtb.TextLength
        $rtb.SelectionColor = $color
        if ($stamp) { $rtb.AppendText("[" + (Get-Date).ToString("HH:mm") + "] " + $text + "`r`n") } else { $rtb.AppendText($text + "`r`n") }
        $rtb.ScrollToCaret()
    }

    function Format-CcBytes([double]$b) {
        if ($b -ge 1GB) { return ('{0:N2} GB' -f ($b / 1GB)) }
        if ($b -ge 1MB) { return ('{0:N1} MB' -f ($b / 1MB)) }
        if ($b -ge 1KB) { return ('{0:N0} KB' -f ($b / 1KB)) }
        return ('{0:N0} B' -f $b)
    }

    function Format-CcEta([double]$sec) {
        if ($sec -lt 0) { return '-' }
        if ($sec -ge 86400) { return '> 1 Tag' }
        return ([TimeSpan]::FromSeconds($sec)).ToString('hh\:mm\:ss')
    }

    function Read-CcText([string]$title, [string]$prompt, [bool]$secret = $false) {
        $d = New-Object System.Windows.Forms.Form
        $d.Text = $title
        $d.Size = New-Object System.Drawing.Size(440, 180)
        $d.StartPosition = "CenterParent"
        $d.FormBorderStyle = "FixedDialog"
        $d.MaximizeBox = $false
        $d.MinimizeBox = $false
        $d.BackColor = $cBack
        $d.ForeColor = $cWhite
        $l = New-CcLabel $prompt 14 14 400 22
        $t = New-CcText 14 44 396 26
        $t.UseSystemPasswordChar = $secret
        $ok = New-CcButton "OK" 210 90 90 32 $true
        $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $cn = New-CcButton "Abbrechen" 310 90 100 32
        $cn.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $d.AcceptButton = $ok
        $d.CancelButton = $cn
        $d.Controls.AddRange(@($l, $t, $ok, $cn))
        $result = $null
        if ($d.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
            if ($secret) { $result = $t.Text } else { $result = $t.Text.Trim() }
        }
        $d.Dispose()
        return $result
    }

    function Get-CcOwnIp {
        if ($st.Adapter) { return [string]$st.Adapter.Ip }
        return ''
    }

    # Liest Name/IP aus einem ausgewählten Listeneintrag, unabhängig davon, ob dessen
    # .Tag ein reiner String (Chat: nur Id), ein Objekt mit Name/Ip (Dateien) oder ein
    # Objekt mit Id/Name/Ip (Voice) ist - damit funktioniert ein gemeinsames Kontextmenü
    # auf allen drei Teilnehmerlisten der Kommunikationszentrale.
    function Get-CcPeerFromItem($item) {
        if (-not $item) { return $null }
        $tag = $item.Tag
        if ($tag -is [pscustomobject] -and ($tag.PSObject.Properties.Name -contains 'Ip')) {
            $ip = [string]$tag.Ip
            $name = [string]$tag.Name
        } else {
            if ([string]$tag -eq 'ALL') { return $null }
            $ip = [string]$item.ToolTipText
            $name = [string]$item.Text
        }
        if (-not $ip) { return $null }
        return [pscustomobject]@{ Name = $name; Ip = $ip }
    }

    # Liefert die IPs aller (nicht gelöschten) Freunde als schnelles Lookup-Set - genutzt
    # vom "Nur Freunde anzeigen"-Filter in Chat und Voice.
    function Get-CcFriendIpSet {
        $set = @{}
        foreach ($fr in @($ccSocial.GetFriends())) { $set[[string]$fr.Ip] = $true }
        return $set
    }

    # ---- Gemeinsame Kontextmenü-Aktionen (Ban/Freund/Poke/Kopieren/Lautstärke) --------------
    # Werden von den Kontextmenüs aller drei Teilnehmerlisten (Chat/Dateien/Voice) aufgerufen.
    function Invoke-CcAddFriend($peer) {
        if (-not $peer) { Show-CcMsg "Bitte zuerst einen Teilnehmer auswählen."; return }
        $notes = Read-CcText "Freund hinzufügen" "Notiz zu $($peer.Name) (optional):"
        if ($null -eq $notes) { return }
        $ccSocial.AddFriend($peer.Ip, $peer.Name, $notes)
        Show-CcMsg "$($peer.Name) wurde als Freund hinzugefügt."
    }
    function Invoke-CcRemoveFriend($peer) {
        if (-not $peer) { Show-CcMsg "Bitte zuerst einen Teilnehmer auswählen."; return }
        $ccSocial.RemoveFriend($peer.Ip)
        Show-CcMsg "$($peer.Name) wurde aus der Freundesliste entfernt."
    }
    function Invoke-CcPoke($peer, $node) {
        if (-not $peer) { Show-CcMsg "Bitte zuerst einen Teilnehmer auswählen."; return }
        $err = $ccPokes.TryPoke($peer.Ip, $peer.Name)
        if ($err) { Show-CcMsg $err; return }
        try { if ($node) { $node.SendPoke($peer.Ip, $st.Nick) } } catch { }
        Show-CcMsg "Poke gesendet an $($peer.Name)."
    }
    function Invoke-CcCopyIp($peer) {
        if (-not $peer) { return }
        try { [System.Windows.Forms.Clipboard]::SetText($peer.Ip) } catch { }
    }
    function Invoke-CcAdjustVolume($peer) {
        if (-not $peer) { Show-CcMsg "Bitte zuerst einen Teilnehmer auswählen."; return }
        $v = Read-CcText "Lautstärke anpassen" "Lautstärke für $($peer.Name) in % (0-200):"
        if (-not $v) { return }
        $vi = 0
        if (-not [int]::TryParse($v, [ref]$vi)) { Show-CcMsg "Bitte eine Zahl eingeben."; return }
        $vi = [math]::Max(0, [math]::Min(200, $vi))
        try {
            $volFile = 'C:\Project-Earth-Lan\PeerVolumes.json'
            $map = @{}
            if (Test-Path -LiteralPath $volFile) {
                try { (Get-Content -LiteralPath $volFile -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $map[$_.Name] = $_.Value } } catch { }
            }
            $map[$peer.Ip] = $vi
            if (-not (Test-Path -LiteralPath 'C:\Project-Earth-Lan')) { New-Item -Path 'C:\Project-Earth-Lan' -ItemType Directory -Force | Out-Null }
            $map | ConvertTo-Json | Set-Content -LiteralPath $volFile -Encoding UTF8
            Show-CcMsg "Lautstärke für $($peer.Name) auf $vi % gesetzt (wirkt in der Voice-Funktion)."
        } catch { }
    }
    function Invoke-CcBanIp($peer) {
        if (-not $peer) { Show-CcMsg "Bitte zuerst einen Teilnehmer auswählen."; return }
        $reason = Read-CcText "IP bannen" "Grund für den Bann von $($peer.Ip) ($($peer.Name)):"
        if ($null -eq $reason) { return }
        $ccBans.BanIP($peer.Ip, $reason, (Get-CcOwnIp))
        Show-CcMsg "$($peer.Ip) gebannt: $reason"
    }

    # Baut ein ContextMenuStrip mit den 6 Standardaktionen und hängt es an eine
    # Teilnehmerliste; $getNode liefert bei Bedarf den Netzwerk-Node für den Poke-Versand.
    # Liefert den passenden Netzwerk-Node (fuer Poke-Versand) zur jeweiligen Liste.
    # $lvPeersC/$lvPeersF/$lvPeersV sind feste, nicht wiederverwendete Variablen (keine
    # Schleifenvariable) - ein einfacher Vergleich per Referenz reicht hier aus.
    function Get-CcNodeForList($lv) {
        if ($lv -eq $lvPeersC) { return $st.ChatNode }
        if ($lv -eq $lvPeersF) { return $st.FileNode }
        if ($lv -eq $lvPeersV) { return $st.VoiceNode }
        return $null
    }

    # WICHTIG: Diese Handler duerfen KEIN .GetNewClosure() verwenden - das kappt die
    # Sichtbarkeit auf im Elternbereich definierte Funktionen (Get-CcPeerFromItem,
    # Invoke-Cc...) und fuehrte zu "Get-CcPeerFromItem wurde nicht erkannt" beim
    # Rechtsklick. Stattdessen wird die auslösende Liste zur Laufzeit über
    # ContextMenuStrip.SourceControl ermittelt - dieselbe Menüdefinition funktioniert
    # so unveraendert fuer Chat-, Datei- und Voice-Liste.
    function New-CcPeerContextMenu([System.Windows.Forms.ListView]$lv) {
        $ctx = New-Object System.Windows.Forms.ContextMenuStrip
        [void]$ctx.Items.Add("Freund hinzufügen")
        [void]$ctx.Items.Add("Freund entfernen")
        [void]$ctx.Items.Add("Anstupsen (Poke)")
        [void]$ctx.Items.Add("ZeroTier-IP kopieren")
        [void]$ctx.Items.Add("Lautstärke anpassen ...")
        [void]$ctx.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        [void]$ctx.Items.Add("IP bannen ...")
        $lv.ContextMenuStrip = $ctx
        $ctx.add_Opening({
            param($sender, $e)
            $srcLv = $sender.SourceControl
            if (-not $srcLv -or $srcLv.SelectedItems.Count -eq 0) { $e.Cancel = $true; return }
            $peer = Get-CcPeerFromItem $srcLv.SelectedItems[0]
            if (-not $peer) { $e.Cancel = $true }
        })
        $ctx.Items[0].Add_Click({
            param($sender, $e)
            $srcLv = $sender.Owner.SourceControl
            if (-not $srcLv -or $srcLv.SelectedItems.Count -eq 0) { return }
            Invoke-CcAddFriend (Get-CcPeerFromItem $srcLv.SelectedItems[0])
        })
        $ctx.Items[1].Add_Click({
            param($sender, $e)
            $srcLv = $sender.Owner.SourceControl
            if (-not $srcLv -or $srcLv.SelectedItems.Count -eq 0) { return }
            Invoke-CcRemoveFriend (Get-CcPeerFromItem $srcLv.SelectedItems[0])
        })
        $ctx.Items[2].Add_Click({
            param($sender, $e)
            $srcLv = $sender.Owner.SourceControl
            if (-not $srcLv -or $srcLv.SelectedItems.Count -eq 0) { return }
            Invoke-CcPoke (Get-CcPeerFromItem $srcLv.SelectedItems[0]) (Get-CcNodeForList $srcLv)
        })
        $ctx.Items[3].Add_Click({
            param($sender, $e)
            $srcLv = $sender.Owner.SourceControl
            if (-not $srcLv -or $srcLv.SelectedItems.Count -eq 0) { return }
            Invoke-CcCopyIp (Get-CcPeerFromItem $srcLv.SelectedItems[0])
        })
        $ctx.Items[4].Add_Click({
            param($sender, $e)
            $srcLv = $sender.Owner.SourceControl
            if (-not $srcLv -or $srcLv.SelectedItems.Count -eq 0) { return }
            Invoke-CcAdjustVolume (Get-CcPeerFromItem $srcLv.SelectedItems[0])
        })
        $ctx.Items[6].Add_Click({
            param($sender, $e)
            $srcLv = $sender.Owner.SourceControl
            if (-not $srcLv -or $srcLv.SelectedItems.Count -eq 0) { return }
            Invoke-CcBanIp (Get-CcPeerFromItem $srcLv.SelectedItems[0])
        })
        return $ctx
    }

    # Firewall-Regeln (gleiche Namen wie in den Einzeloptionen)
    function Set-CcFirewall([string]$which, [bool]$enable) {
        try {
            if ($which -eq 'chat') {
                Get-NetFirewallRule -DisplayName "Project Earth LAN Chat 9874*" -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
                if ($enable) {
                    New-NetFirewallRule -DisplayName "Project Earth LAN Chat 9874 (TCP)" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 9874 -RemoteAddress LocalSubnet -Profile Any -ErrorAction Stop | Out-Null
                    New-NetFirewallRule -DisplayName "Project Earth LAN Chat 9874 (UDP)" -Direction Inbound -Action Allow -Protocol UDP -LocalPort 9874 -RemoteAddress LocalSubnet -Profile Any -ErrorAction Stop | Out-Null
                    $st.ChatFw = $true
                } else { $st.ChatFw = $false }
            } elseif ($which -eq 'file') {
                Get-NetFirewallRule -DisplayName "Project Earth LAN File 9876*" -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
                if ($enable) {
                    New-NetFirewallRule -DisplayName "Project Earth LAN File 9876 (TCP)" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 9876 -RemoteAddress LocalSubnet -Profile Any -ErrorAction Stop | Out-Null
                    New-NetFirewallRule -DisplayName "Project Earth LAN File 9876 (UDP)" -Direction Inbound -Action Allow -Protocol UDP -LocalPort 9876 -RemoteAddress LocalSubnet -Profile Any -ErrorAction Stop | Out-Null
                    $st.FileFw = $true
                } else { $st.FileFw = $false }
            } elseif ($which -eq 'voice') {
                Get-NetFirewallRule -DisplayName "Project Earth LAN Voice 9873*" -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
                if ($enable) {
                    New-NetFirewallRule -DisplayName "Project Earth LAN Voice 9873" -Direction Inbound -Action Allow -Protocol UDP -LocalPort 9873 -RemoteAddress LocalSubnet -Profile Any -ErrorAction Stop | Out-Null
                    $st.VoiceFw = $true
                } else { $st.VoiceFw = $false }
            } elseif ($which -eq 'social') {
                Get-NetFirewallRule -DisplayName "Project Earth LAN Social 9776*" -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
                if ($enable) {
                    New-NetFirewallRule -DisplayName "Project Earth LAN Social 9776 (TCP)" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 9776 -RemoteAddress LocalSubnet -Profile Any -ErrorAction Stop | Out-Null
                    New-NetFirewallRule -DisplayName "Project Earth LAN Social 9776 (UDP)" -Direction Inbound -Action Allow -Protocol UDP -LocalPort 9776 -RemoteAddress LocalSubnet -Profile Any -ErrorAction Stop | Out-Null
                    $st.SocialFw = $true
                } else { $st.SocialFw = $false }
            }
        } catch { }
    }

    function Save-CcConfig {
        try {
            if (-not (Test-Path -LiteralPath $dataDir)) { New-Item -Path $dataDir -ItemType Directory -Force | Out-Null }
            @{ Nick = $st.Nick; Sound = [bool]$chkSoundC.Checked } | ConvertTo-Json | Set-Content -LiteralPath $chatCfg -Encoding UTF8
            @{ DownloadDir = $st.DownloadDir; Streams = [int]$numStreamsF.Value; LimitMB = [int]$numLimitF.Value } | ConvertTo-Json | Set-Content -LiteralPath $fileCfg -Encoding UTF8
            @{ InName = $st.InName; OutName = $st.OutName } | ConvertTo-Json | Set-Content -LiteralPath $voiceCfg -Encoding UTF8
        } catch { }
    }

    # ===================================================================================
    # CHAT
    # ===================================================================================
    function Get-CcHistFile { return (Join-Path $histDir ("chat_" + (Get-Date).ToString('yyyy-MM-dd') + ".log")) }

    function Add-CcChat([string]$text, $color, [bool]$save = $true) {
        Add-CcRtb $rtbChatC $text $color
        if ($save) {
            try {
                if (-not (Test-Path -LiteralPath $histDir)) { New-Item -Path $histDir -ItemType Directory -Force | Out-Null }
                Add-Content -LiteralPath (Get-CcHistFile) -Value ("[" + (Get-Date).ToString("HH:mm:ss") + "] " + $text) -Encoding UTF8
            } catch { }
        }
    }

    function Send-CcChatNotify {
        if ($st.Panel -ne 0) {
            $st.ChatUnread = $st.ChatUnread + 1
            $navChat.Text = "Chat ($($st.ChatUnread) neu)"
        }
        if (-not $chkSoundC.Checked) { return }
        if ([System.Windows.Forms.Form]::ActiveForm -eq $form -and $st.Panel -eq 0) { return }
        try { [System.Media.SystemSounds]::Asterisk.Play() } catch { }
        try { [EarthChatFlash]::Flash($form.Handle) } catch { }
    }

    function Stop-CcChat {
        if ($st.ChatNode) { try { $st.ChatNode.Stop() } catch { }; $st.ChatNode = $null }
        foreach ($k in @($st.ChatItems.Keys)) { $lvPeersC.Items.Remove($st.ChatItems[$k]) }
        $st.ChatItems = @{}
        $st.ChatKnown = @{}
        foreach ($k in @($st.ChatChanItems.Keys)) { $lvChansC.Items.Remove($st.ChatChanItems[$k]) }
        $st.ChatChanItems = @{}
        Set-CcSub $itemAllChanC 3 'aktiv'
        $itemAllChanC.ForeColor = [System.Drawing.Color]::LightGreen
    }

    function Start-CcChat {
        Stop-CcChat
        if (-not $st.Adapter) { return }
        $a = $st.Adapter
        Set-CcFirewall 'chat' $true
        $node = New-Object EarthChatNode -ArgumentList $a.Ip, $st.Nick
        $node.Mask = [string]$a.Mask
        $err = $node.Start()
        if ($err) {
            $lblNodeC.Text = "Port 9874: FEHLER - $err"
            return
        }
        $st.ChatNode = $node
        Add-CcChat "Chat: Port 9874 geöffnet auf $($a.Ip). Suche automatisch nach Teilnehmern ..." ([System.Drawing.Color]::LightGray) $false
        $node.ScanAsync([string[]]([EarthChatNet]::HostRange($a.Ip, $a.Mask, 1022)))
    }

    function Get-CcChatGroupLabel {
        if (-not $st.ChatNode) { return "Alle Teilnehmer" }
        $c = [string]$st.ChatNode.GetMyChannel()
        if ($c) { return "Kanal '$c'" } else { return "Alle Teilnehmer" }
    }

    function Update-CcChatTarget {
        $sel = $lvPeersC.SelectedItems
        if ($sel.Count -eq 0) {
            $lblToC.Text = "Gruppenchat: $(Get-CcChatGroupLabel)"
        } else {
            $pid2 = [string]$sel[0].Tag
            $lblToC.Text = "Privat an $($sel[0].Text)"
            if ($st.PmUnread.ContainsKey($pid2)) { $st.PmUnread.Remove($pid2) }
        }
    }

    function Update-CcChatPeers {
        $seen = @{}
        $friendSet = Get-CcFriendIpSet
        $filterOn = $st.ChatFriendsOnly
        foreach ($ln in @($st.ChatNode.GetPeers())) {
            $f = $ln -split '\|'
            if ($f.Count -lt 4) { continue }
            $id = $f[0]
            $isFriend = $friendSet.ContainsKey([string]$f[2])
            if ($filterOn -and -not $isFriend) { continue }
            $seen[$id] = $true
            $status = 'online'
            $unread = $st.PmUnread.ContainsKey($id)
            if ($unread) { $status = 'neue Nachricht' }
            $chanText = [string]$f[3]
            if ($st.ChatItems.ContainsKey($id)) {
                $it = $st.ChatItems[$id]
                if ($it.Text -ne $f[1]) { $it.Text = $f[1] }
                if ($it.SubItems[1].Text -ne $chanText) { $it.SubItems[1].Text = $chanText }
                if ($it.SubItems[2].Text -ne $status) { $it.SubItems[2].Text = $status }
            } else {
                $it = New-Object System.Windows.Forms.ListViewItem($f[1])
                [void]$it.SubItems.Add($chanText)
                [void]$it.SubItems.Add($status)
                $it.Tag = $id
                $it.ToolTipText = $f[2]
                [void]$lvPeersC.Items.Add($it)
                $st.ChatItems[$id] = $it
            }
            # Freunde bleiben dauerhaft grün markiert, unabhängig vom übrigen Status.
            if ($isFriend) { $it.ForeColor = [System.Drawing.Color]::LimeGreen }
            elseif ($unread) { $it.ForeColor = [System.Drawing.Color]::Orange }
            else { $it.ForeColor = $cWhite }
        }
        foreach ($k in @($st.ChatItems.Keys)) {
            if (-not $seen.ContainsKey($k)) {
                $lvPeersC.Items.Remove($st.ChatItems[$k])
                $st.ChatItems.Remove($k)
            }
        }
    }

    # Kanalliste analog zum Voice-Bereich: dauerhafte Kanäle (aus $ccSocial, gespeichert
    # + per Port 9776 mit anderen Managern abgeglichen) bleiben immer sichtbar, temporäre
    # Kanäle nur solange jemand drin ist. "Alle (Gruppenchat)" verlässt den Kanal wieder.
    function Update-CcChatChannels {
        $node = $st.ChatNode
        $myChan = [string]$node.GetMyChannel()
        $agg = @{}
        foreach ($c in @($ccSocial.GetChannels())) {
            $agg[$c.Name] = @{ N = 0; Locked = (-not [string]::IsNullOrEmpty($c.PasswordHash)); Id = $c.Id; Owner = $c.OwnerIp; Permanent = $true }
        }
        foreach ($ln in @($node.GetPeers())) {
            $f = $ln -split '\|'
            if ($f.Count -lt 4 -or -not $f[3]) { continue }
            $name = [string]$f[3]
            if (-not $agg.ContainsKey($name)) { $agg[$name] = @{ N = 0; Locked = $false; Id = ''; Owner = ''; Permanent = $false } }
            $agg[$name].N = $agg[$name].N + 1
        }
        if ($myChan) {
            if (-not $agg.ContainsKey($myChan)) { $agg[$myChan] = @{ N = 0; Locked = $false; Id = ''; Owner = ''; Permanent = $false } }
            $agg[$myChan].N = $agg[$myChan].N + 1
        }
        foreach ($name in @($agg.Keys)) {
            $prot = 'offen'
            if ($agg[$name].Locked) { $prot = 'Passwort' }
            $active = ''
            if ($name -eq $myChan) { $active = 'aktiv' }
            if ($st.ChatChanItems.ContainsKey($name)) {
                $ci = $st.ChatChanItems[$name]
            } else {
                $ci = New-Object System.Windows.Forms.ListViewItem($name)
                [void]$ci.SubItems.Add(''); [void]$ci.SubItems.Add(''); [void]$ci.SubItems.Add('')
                [void]$lvChansC.Items.Add($ci)
                $st.ChatChanItems[$name] = $ci
            }
            $ci.Tag = [pscustomobject]@{ Name = $name; Id = [string]$agg[$name].Id; Owner = [string]$agg[$name].Owner; Permanent = [bool]$agg[$name].Permanent }
            Set-CcSub $ci 1 ([string]$agg[$name].N)
            Set-CcSub $ci 2 $prot
            Set-CcSub $ci 3 $active
            if ($active) { $ci.ForeColor = [System.Drawing.Color]::LightGreen } else { $ci.ForeColor = $cWhite }
        }
        foreach ($k in @($st.ChatChanItems.Keys)) {
            if (-not $agg.ContainsKey($k)) {
                $lvChansC.Items.Remove($st.ChatChanItems[$k])
                $st.ChatChanItems.Remove($k)
            }
        }
        if (-not $myChan) { $itemAllChanC.ForeColor = [System.Drawing.Color]::LightGreen } else { $itemAllChanC.ForeColor = $cWhite }
        Set-CcSub $itemAllChanC 3 $(if (-not $myChan) { 'aktiv' } else { '' })
    }

    # ===================================================================================
    # DATEIEN
    # ===================================================================================
    function Add-CcFileLog([string]$text) {
        Add-CcRtb $rtbLogF $text ([System.Drawing.Color]::LightGray)
    }

    function Set-CcFileTarget($t) {
        $st.FileTarget = $t
        if ($t) { $lblTargetF.Text = "Ziel: $($t.Name)  ($($t.Ip))" } else { $lblTargetF.Text = "Ziel: (noch keins gewählt - Button 2)" }
    }

    function Stop-CcFile {
        if ($st.FileNode) { try { $st.FileNode.Stop() } catch { }; $st.FileNode = $null }
        foreach ($k in @($st.FilePeers.Keys)) { $lvPeersF.Items.Remove($st.FilePeers[$k]) }
        $st.FilePeers = @{}
    }

    function Start-CcFile {
        Stop-CcFile
        if (-not $st.Adapter) { return }
        $a = $st.Adapter
        Set-CcFirewall 'file' $true
        try { New-Item -Path $st.DownloadDir -ItemType Directory -Force | Out-Null } catch { }
        $node = New-Object EarthFileNode -ArgumentList $a.Ip, $st.Nick
        $node.Mask = [string]$a.Mask
        $node.DownloadDir = [string]$st.DownloadDir
        $node.Streams = [int]$numStreamsF.Value
        $node.LimitBytesPerSec = [long]([double]$numLimitF.Value * 1MB)
        $err = $node.Start()
        if ($err) {
            $lblNodeF.Text = "Port 9876: FEHLER - $err"
            return
        }
        $st.FileNode = $node
        $lblNodeF.Text = "Port 9876 offen auf $($a.Ip)  |  Firewall-Regel (TCP/UDP) erstellt  |  Suche nach anderen Managern läuft automatisch ..."
        Add-CcFileLog "Dateien: bereit auf $($a.Ip):9876. Download-Ordner: $($st.DownloadDir)"
    }

    function Select-CcFileTarget {
        $d = New-Object System.Windows.Forms.Form
        $d.Text = "IP Auswahl"
        $d.Size = New-Object System.Drawing.Size(520, 420)
        $d.StartPosition = "CenterParent"
        $d.FormBorderStyle = "FixedDialog"
        $d.MaximizeBox = $false
        $d.MinimizeBox = $false
        $d.BackColor = $cBack
        $d.ForeColor = $cWhite
        $l1 = New-CcLabel "Automatisch gefundene Manager:" 14 12 460 22
        $lb = New-Object System.Windows.Forms.ListBox
        $lb.Location = New-Object System.Drawing.Point(14, 38)
        $lb.Size = New-Object System.Drawing.Size(480, 200)
        $lb.BackColor = $cList
        $lb.ForeColor = $cWhite
        $lb.Font = $fontMain
        $peerObjs = @()
        if ($st.FileNode) {
            foreach ($ln in @($st.FileNode.GetPeers())) {
                $f = $ln -split '\|'
                if ($f.Count -lt 4) { continue }
                $peerObjs += [pscustomobject]@{ Name = $f[1]; Ip = $f[2] }
                [void]$lb.Items.Add("$($f[1])   ($($f[2]))")
            }
        }
        $l2 = New-CcLabel "oder IP-Adresse manuell eingeben:" 14 250 460 22
        $tb = New-CcText 14 276 250 26
        $ok = New-CcButton "Übernehmen" 250 330 120 34 $true
        $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $cn = New-CcButton "Abbrechen" 380 330 114 34
        $cn.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $lb.Add_DoubleClick({ $ok.PerformClick() })
        $d.AcceptButton = $ok
        $d.CancelButton = $cn
        $d.Controls.AddRange(@($l1, $lb, $l2, $tb, $ok, $cn))
        $result = $null
        if ($d.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
            $manual = $tb.Text.Trim()
            if ($manual) {
                $parsed = $null
                if ([System.Net.IPAddress]::TryParse($manual, [ref]$parsed) -and $parsed.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
                    if ($st.FileNode) { $st.FileNode.AddManualPeer($manual) }
                    $result = [pscustomobject]@{ Name = $manual; Ip = $manual }
                } else {
                    Show-CcMsg "Bitte eine gültige IPv4-Adresse eingeben (z. B. 10.147.17.5)."
                }
            } elseif ($lb.SelectedIndex -ge 0) {
                $result = $peerObjs[$lb.SelectedIndex]
            }
        }
        $d.Dispose()
        return $result
    }

    function Update-CcFilePeers {
        $seen = @{}
        foreach ($ln in @($st.FileNode.GetPeers())) {
            $f = $ln -split '\|'
            if ($f.Count -lt 4) { continue }
            $id = $f[0]
            $seen[$id] = $true
            $ago = "aktiv"
            if ([int]$f[3] -gt 5) { $ago = "zuletzt vor $($f[3]) s" }
            if ($st.FilePeers.ContainsKey($id)) {
                $it = $st.FilePeers[$id]
                if ($it.Text -ne $f[1]) { $it.Text = $f[1] }
                if ($it.SubItems[1].Text -ne $f[2]) { $it.SubItems[1].Text = $f[2] }
                if ($it.SubItems[2].Text -ne $ago) { $it.SubItems[2].Text = $ago }
            } else {
                $it = New-Object System.Windows.Forms.ListViewItem($f[1])
                [void]$it.SubItems.Add($f[2])
                [void]$it.SubItems.Add($ago)
                $it.Tag = [pscustomobject]@{ Name = $f[1]; Ip = $f[2] }
                [void]$lvPeersF.Items.Add($it)
                $st.FilePeers[$id] = $it
            }
        }
        foreach ($k in @($st.FilePeers.Keys)) {
            if (-not $seen.ContainsKey($k)) {
                $lvPeersF.Items.Remove($st.FilePeers[$k])
                $st.FilePeers.Remove($k)
            }
        }
    }

    function Update-CcTransfers {
        $seen = @{}
        foreach ($ln in @($st.FileNode.GetTransfers())) {
            $f = $ln -split '\|'
            if ($f.Count -lt 11) { continue }
            $id = $f[0]
            $seen[$id] = $true
            $total = [double]$f[4]
            $done = [double]$f[5]
            $speed = [double]$f[6]
            $eta = [double]$f[7]
            $pct = 100
            if ($total -gt 0) { $pct = [math]::Min(100, [int](($done * 100) / $total)) }
            $texts = @($f[1], $f[3], $f[2], (Format-CcBytes $total), "$pct %", ((Format-CcBytes $speed) + "/s"), (Format-CcEta $eta), $f[8])
            if ($f[9] -eq '1' -or $speed -le 0) { $texts[5] = '-'; $texts[6] = '-' }
            if ($st.FileItems.ContainsKey($id)) {
                $it = $st.FileItems[$id]
            } else {
                $it = New-Object System.Windows.Forms.ListViewItem($texts[0])
                for ($i = 1; $i -lt $texts.Count; $i++) { [void]$it.SubItems.Add($texts[$i]) }
                $it.Tag = $id
                [void]$lvTransfersF.Items.Add($it)
                $st.FileItems[$id] = $it
            }
            for ($i = 0; $i -lt $texts.Count; $i++) {
                if ($i -eq 0) { if ($it.Text -ne $texts[0]) { $it.Text = $texts[0] } }
                elseif ($it.SubItems[$i].Text -ne $texts[$i]) { $it.SubItems[$i].Text = $texts[$i] }
            }
            if ($f[10] -eq '1') { $it.ForeColor = [System.Drawing.Color]::OrangeRed }
            elseif ($f[9] -eq '1') { $it.ForeColor = [System.Drawing.Color]::LightGreen }
            else { $it.ForeColor = $cWhite }
        }
        foreach ($k in @($st.FileItems.Keys)) {
            if (-not $seen.ContainsKey($k)) {
                $lvTransfersF.Items.Remove($st.FileItems[$k])
                $st.FileItems.Remove($k)
            }
        }
    }

    # ===================================================================================
    # VOICE
    # ===================================================================================
    function Add-CcVoiceLog([string]$text) {
        Add-CcRtb $rtbLogV $text ([System.Drawing.Color]::LightGray)
    }

    function Start-CcVoiceAudio {
        if (-not $st.VoiceNode) { return }
        $err = $st.VoiceNode.StartAudio([int]$st.InDev, [int]$st.OutDev)
        if ($err) { Add-CcVoiceLog "Audio-Fehler: $err" } else { Add-CcVoiceLog "Audio aktiv (Eingabe: $($st.InName) | Ausgabe: $($st.OutName))." }
    }

    function Stop-CcSocial {
        if ($st.SocialNode) { try { $st.SocialNode.Stop() } catch { }; $st.SocialNode = $null }
    }

    # Startet den Kanal-Synchronisationsdienst (Port 9776): permanente Voice-Kanäle
    # (Name, Ersteller, Passwort-Hash) werden lokal gespeichert (BanManager/
    # FriendAndChannelManager schreiben auf Platte) UND automatisch per UDP-Beacon
    # gefunden sowie per TCP-Vollabgleich (letzter Stand gewinnt) mit allen anderen
    # laufenden Managern im Netzwerk abgeglichen - unabhängig davon, ob gerade
    # jemand im Kanal ist.
    function Start-CcSocial {
        if ($st.SocialNode) { return }
        if (-not $st.Adapter) { return }
        $a = $st.Adapter
        Set-CcFirewall 'social' $true
        $node = New-Object EarthSocialNode -ArgumentList $a.Ip, $st.Nick, $ccBans, $ccSocial, $ccPokes
        $node.Mask = [string]$a.Mask
        $err = $node.Start()
        if ($err) {
            Add-CcVoiceLog "Kanal-Synchronisation (Port 9776): FEHLER - $err (Kanäle bleiben lokal gespeichert, werden aber nicht automatisch abgeglichen)."
            return
        }
        $st.SocialNode = $node
        Add-CcVoiceLog "Kanal-Synchronisation aktiv (Port 9776) - permanente Kanäle werden automatisch mit anderen Managern abgeglichen."
    }

    function Start-CcVoice {
        if ($st.VoiceNode) { return }
        Set-CcFirewall 'voice' $true
        Start-CcSocial
        $node = New-Object EarthVoiceNode -ArgumentList $st.Nick
        $err = $node.Start()
        if ($err) {
            Show-CcMsg "Voice Chat konnte nicht gestartet werden:`n$err" "Voice Chat" ([System.Windows.Forms.MessageBoxIcon]::Error)
            return
        }
        $node.MicMuted = [bool]$chkMuteV.Checked
        $node.Deafened = [bool]$chkDeafV.Checked
        $node.PttMode = [bool]$chkPttV.Checked
        $node.PttVKey = [int]$pttKeyMap[[string]$cbPttKeyV.SelectedItem]
        $node.Threshold = [int]$tbSensV.Value
        $node.VolumePercent = [int]$tbVolV.Value
        $st.VoiceNode = $node
        Add-CcVoiceLog "Voice Chat gestartet. Suche automatisch nach anderen Teilnehmern (UDP 9873) ..."
        Start-CcVoiceAudio
    }

    function Select-CcDevices {
        $ins = [EarthWinmm]::InputDeviceNames()
        $outs = [EarthWinmm]::OutputDeviceNames()
        $d = New-Object System.Windows.Forms.Form
        $d.Text = "Sound Ein- und Ausgabe"
        $d.Size = New-Object System.Drawing.Size(520, 260)
        $d.StartPosition = "CenterParent"
        $d.FormBorderStyle = "FixedDialog"
        $d.MaximizeBox = $false
        $d.MinimizeBox = $false
        $d.BackColor = $cBack
        $d.ForeColor = $cWhite
        $l1 = New-CcLabel "Eingabegerät (Mikrofon):" 14 14 460 22
        $cbIn = New-Object System.Windows.Forms.ComboBox
        $cbIn.Location = New-Object System.Drawing.Point(14, 40)
        $cbIn.Size = New-Object System.Drawing.Size(480, 26)
        $cbIn.DropDownStyle = "DropDownList"
        $cbIn.BackColor = $cInput
        $cbIn.ForeColor = $cWhite
        $cbIn.Font = $fontMain
        foreach ($n in $ins) { [void]$cbIn.Items.Add($n) }
        $cbIn.SelectedIndex = [math]::Min([math]::Max($st.InDev + 1, 0), $cbIn.Items.Count - 1)
        $l2 = New-CcLabel "Ausgabegerät (Lautsprecher/Kopfhörer):" 14 80 460 22
        $cbOut = New-Object System.Windows.Forms.ComboBox
        $cbOut.Location = New-Object System.Drawing.Point(14, 106)
        $cbOut.Size = New-Object System.Drawing.Size(480, 26)
        $cbOut.DropDownStyle = "DropDownList"
        $cbOut.BackColor = $cInput
        $cbOut.ForeColor = $cWhite
        $cbOut.Font = $fontMain
        foreach ($n in $outs) { [void]$cbOut.Items.Add($n) }
        $cbOut.SelectedIndex = [math]::Min([math]::Max($st.OutDev + 1, 0), $cbOut.Items.Count - 1)
        $ok = New-CcButton "Übernehmen" 250 160 120 34 $true
        $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $cn = New-CcButton "Abbrechen" 380 160 114 34
        $cn.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $d.AcceptButton = $ok
        $d.CancelButton = $cn
        $d.Controls.AddRange(@($l1, $cbIn, $l2, $cbOut, $ok, $cn))
        $result = $null
        if ($d.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
            $result = @{ In = ($cbIn.SelectedIndex - 1); Out = ($cbOut.SelectedIndex - 1); InName = $cbIn.Text; OutName = $cbOut.Text }
        }
        $d.Dispose()
        return $result
    }

    function Set-CcSub($item, [int]$idx, [string]$text) {
        if ($item.SubItems[$idx].Text -ne $text) { $item.SubItems[$idx].Text = $text }
    }

    function Update-CcVoiceLists {
        $node = $st.VoiceNode
        $sp = ([string]$node.GetState()) -split '\|'
        $myChan = $sp[0]
        $myLocked = ($sp[1] -eq '1')
        $memberCount = [int]$sp[2]
        if ($myChan) {
            $label = $myChan
            if ($myChan.StartsWith('@')) { $label = 'Privatgespräch' }
            $lblStateV.Text = "Aktiver Kanal: $label   |   Verbundene Teilnehmer: $memberCount"
        } else {
            $lblStateV.Text = "Aktiver Kanal: (keiner) - Kanal erstellen oder einem Kanal beitreten"
        }
        $seen = @{}
        $agg = @{}
        $friendSet = Get-CcFriendIpSet
        $filterOn = $st.VoiceFriendsOnly

        # Permanente Kanäle (gespeichert + zwischen Managern per Port 9776 abgeglichen)
        # zuerst eintragen - sie bleiben sichtbar, auch wenn gerade niemand drin ist.
        foreach ($c in @($ccSocial.GetChannels())) {
            $agg[$c.Name] = @{ N = 0; Locked = (-not [string]::IsNullOrEmpty($c.PasswordHash)); Id = $c.Id; Owner = $c.OwnerIp; Permanent = $true }
        }

        foreach ($ln in @($node.GetPeers())) {
            $f = $ln -split '\|'
            if ($f.Count -lt 8) { continue }
            $id = $f[0]
            $isFriend = $friendSet.ContainsKey([string]$f[2])
            if ($filterOn -and -not $isFriend) { continue }
            $seen[$id] = $true
            $chanText = ''
            if ($f[3]) { if ($f[3].StartsWith('@')) { $chanText = '(privat)' } else { $chanText = $f[3] } }
            $status = ''
            if ($f[6] -eq '1') { $status = 'spricht' } elseif ($f[5] -eq '1') { $status = 'im Kanal' }
            if ($st.VcPeers.ContainsKey($id)) {
                $it = $st.VcPeers[$id]
                if ($it.Text -ne $f[1]) { $it.Text = $f[1] }
            } else {
                $it = New-Object System.Windows.Forms.ListViewItem($f[1])
                [void]$it.SubItems.Add($f[2])
                [void]$it.SubItems.Add($chanText)
                [void]$it.SubItems.Add($status)
                [void]$it.SubItems.Add($f[7])
                $it.Tag = [pscustomobject]@{ Id = $id; Name = $f[1]; Ip = $f[2] }
                [void]$lvPeersV.Items.Add($it)
                $st.VcPeers[$id] = $it
            }
            Set-CcSub $it 1 $f[2]
            Set-CcSub $it 2 $chanText
            Set-CcSub $it 3 $status
            Set-CcSub $it 4 $f[7]
            # Freunde bleiben dauerhaft grün markiert, unabhängig vom übrigen Status.
            if ($isFriend) { $it.ForeColor = [System.Drawing.Color]::LimeGreen }
            elseif ($f[6] -eq '1') { $it.ForeColor = [System.Drawing.Color]::LightGreen }
            else { $it.ForeColor = $cWhite }
            if ($f[3] -and -not $f[3].StartsWith('@')) {
                if (-not $agg.ContainsKey($f[3])) { $agg[$f[3]] = @{ N = 0; Locked = $false; Id = ''; Owner = ''; Permanent = $false } }
                $agg[$f[3]].N = $agg[$f[3]].N + 1
                if ($f[4] -eq '1') { $agg[$f[3]].Locked = $true }
            }
        }
        foreach ($k in @($st.VcPeers.Keys)) {
            if (-not $seen.ContainsKey($k)) {
                $lvPeersV.Items.Remove($st.VcPeers[$k])
                $st.VcPeers.Remove($k)
            }
        }
        if ($myChan -and -not $myChan.StartsWith('@')) {
            if (-not $agg.ContainsKey($myChan)) { $agg[$myChan] = @{ N = 0; Locked = $myLocked; Id = ''; Owner = ''; Permanent = $false } }
            $agg[$myChan].N = $agg[$myChan].N + 1
            if ($myLocked) { $agg[$myChan].Locked = $true }
        }
        foreach ($name in @($agg.Keys)) {
            $prot = 'offen'
            if ($agg[$name].Locked) { $prot = 'Passwort' }
            $active = ''
            if ($name -eq $myChan) { $active = 'aktiv' }
            $owner = [string]$agg[$name].Owner
            if (-not $owner) { $owner = '(temporär)' }
            if ($st.VcChans.ContainsKey($name)) {
                $ci = $st.VcChans[$name]
            } else {
                $ci = New-Object System.Windows.Forms.ListViewItem($name)
                [void]$ci.SubItems.Add('')
                [void]$ci.SubItems.Add('')
                [void]$ci.SubItems.Add('')
                [void]$ci.SubItems.Add('')
                [void]$lvChansV.Items.Add($ci)
                $st.VcChans[$name] = $ci
            }
            $ci.Tag = [pscustomobject]@{ Name = $name; Id = [string]$agg[$name].Id; Owner = [string]$agg[$name].Owner; Permanent = [bool]$agg[$name].Permanent }
            Set-CcSub $ci 1 $owner
            Set-CcSub $ci 2 ([string]$agg[$name].N)
            Set-CcSub $ci 3 $prot
            Set-CcSub $ci 4 $active
            if ($active) { $ci.ForeColor = [System.Drawing.Color]::LightGreen } else { $ci.ForeColor = $cWhite }
        }
        foreach ($k in @($st.VcChans.Keys)) {
            if (-not $agg.ContainsKey($k)) {
                $lvChansV.Items.Remove($st.VcChans[$k])
                $st.VcChans.Remove($k)
            }
        }
    }

    # ===================================================================================
    # GUI: Kopfbereich und drei Bereiche
    # ===================================================================================
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $baseTitle
    $form.Size = New-Object System.Drawing.Size(1010, 780)
    # Mindestgröße so, dass die rechte Button-Spalte im Voice-Bereich nie in die Regler
    # am unteren Rand hineinragt.
    $form.MinimumSize = New-Object System.Drawing.Size(900, 720)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "Sizable"
    $form.MaximizeBox = $true
    $form.BackColor = $cBack
    $form.ForeColor = $cWhite

    # Netzwerkadapter wird zentral im Control Center (Live-Status -> "Adapter wechseln")
    # gewählt; hier nur noch als reine Statusanzeige, keine eigene Auswahl mehr.
    $lblAd = New-CcLabel "Adapter: -" 12 12 600 22
    $lblAd.ForeColor = [System.Drawing.Color]::LightGray
    $lblNick = New-CcLabel "Dein Name:" 626 12 80 22
    $txtNick = New-CcText 708 8 176 26
    $btnNick = New-CcButton "Ändern" 890 6 94 30

    $navChat = New-CcButton "Chat" 12 44 200 36 $true
    $navFile = New-CcButton "Dateien senden" 220 44 200 36
    $navVoice = New-CcButton "Voice Chat" 428 44 200 36
    $lblStatus = New-CcLabel "" 640 52 344 22
    $lblStatus.ForeColor = [System.Drawing.Color]::LightGray

    $pC = New-Object System.Windows.Forms.Panel
    $pF = New-Object System.Windows.Forms.Panel
    $pV = New-Object System.Windows.Forms.Panel
    foreach ($pp in @($pC, $pF, $pV)) {
        $pp.Location = New-Object System.Drawing.Point(12, 90)
        $pp.Size = New-Object System.Drawing.Size(972, 650)
        $pp.BackColor = $cBack
        $pp.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
    }
    $pF.Visible = $false
    $pV.Visible = $false

    # ---- Bereich Chat ------------------------------------------------------------------------
    $btnClearC = New-CcButton "Chat leeren" 0 0 110 32
    $btnHistC = New-CcButton "Verlauf öffnen" 120 0 130 32
    $chkSoundC = New-Object System.Windows.Forms.CheckBox
    $chkSoundC.Text = "Ton / Blinken"
    $chkSoundC.Location = New-Object System.Drawing.Point(260, 5)
    $chkSoundC.Size = New-Object System.Drawing.Size(150, 24)
    $chkSoundC.ForeColor = $cWhite
    $chkSoundC.Font = $fontMain
    $chkSoundC.Checked = $true
    $lblNodeC = New-CcLabel "Port 9874: geschlossen" 0 38 972 20

    # ---- Kanäle: temporär (nur beitreten) oder dauerhaft (gespeichert + automatisch
    # mit allen anderen Managern synchronisiert, Port 9776 - dieselbe Kanal-Liste wie
    # im Voice-Bereich). "Alle (Gruppenchat)" ist kein echter Kanal, sondern verlässt
    # den aktuellen Kanal und sendet wieder an jeden verbundenen Teilnehmer.
    $btnC1 = New-CcButton "Kanal erstellen" 0 62 132 28 $true
    $btnC2 = New-CcButton "Passwort-Kanal" 138 62 132 28
    $lblChansC = New-CcLabel "Kanäle (Doppelklick = beitreten, Rechtsklick = löschen):" 0 94 270 16
    $lvChansC = New-CcListView 0 112 270 196 @('Kanal','Teiln.','Schutz','Status') @(110,50,55,55)
    $itemAllChanC = New-Object System.Windows.Forms.ListViewItem("Alle (Gruppenchat)")
    [void]$itemAllChanC.SubItems.Add(''); [void]$itemAllChanC.SubItems.Add(''); [void]$itemAllChanC.SubItems.Add('aktiv')
    $itemAllChanC.Tag = [pscustomobject]@{ Name = ''; Id = ''; Owner = ''; Permanent = $false }
    $itemAllChanC.Font = $fontBold
    [void]$lvChansC.Items.Add($itemAllChanC)

    $lblPeersC = New-CcLabel "Teilnehmer (Doppelklick/Auswahl = privat):" 0 314 270 16
    $btnFriendsC = New-CcButton "Nur Freunde: Aus" 0 330 270 24
    $lvPeersC = New-Object System.Windows.Forms.ListView
    $lvPeersC.Location = New-Object System.Drawing.Point(0, 358)
    $lvPeersC.Size = New-Object System.Drawing.Size(270, 264)
    $lvPeersC.View = "Details"
    $lvPeersC.FullRowSelect = $true
    $lvPeersC.HideSelection = $false
    $lvPeersC.MultiSelect = $false
    $lvPeersC.ShowItemToolTips = $true
    $lvPeersC.BackColor = $cList
    $lvPeersC.ForeColor = $cWhite
    $lvPeersC.Font = $fontMain
    [void]$lvPeersC.Columns.Add("Teilnehmer", 110)
    [void]$lvPeersC.Columns.Add("Kanal", 80)
    [void]$lvPeersC.Columns.Add("Status", 78)
    $rtbChatC = New-CcRtb 278 62 694 515
    $lblToC = New-CcLabel "Gruppenchat: Alle Teilnehmer" 278 584 694 20
    $txtChatC = New-CcText 278 608 600 28
    $txtChatC.MaxLength = 2000
    $btnSendC = New-CcButton "Senden" 886 605 86 32 $true
    $pC.Controls.AddRange(@($btnClearC, $btnHistC, $chkSoundC, $lblNodeC, $btnC1, $btnC2, $lblChansC, $lvChansC, $lblPeersC, $btnFriendsC, $lvPeersC, $rtbChatC, $lblToC, $txtChatC, $btnSendC))
    [void](New-CcPeerContextMenu $lvPeersC)
    $btnFriendsC.Add_Click({
        $st.ChatFriendsOnly = -not $st.ChatFriendsOnly
        if ($st.ChatFriendsOnly) {
            $btnFriendsC.Text = "Nur Freunde: An"
            $btnFriendsC.BackColor = $cAccent
        } else {
            $btnFriendsC.Text = "Nur Freunde: Aus"
            $btnFriendsC.BackColor = $cBtn
        }
        if ($st.ChatNode) { Update-CcChatPeers }
    })
    # Größenanpassung: die Kanal-/Teilnehmerlisten wachsen mit der Höhe, der Chatverlauf
    # mit Höhe UND Breite, die Eingabezeile bleibt unten und breit.
    Set-CcAnchor $lblNodeC @('Top','Left','Right')
    Set-CcAnchor $lvChansC @('Top','Left')
    Set-CcAnchor $lvPeersC @('Top','Left','Bottom')
    Set-CcAnchor $rtbChatC @('Top','Left','Right','Bottom')
    Set-CcAnchor $lblToC @('Left','Right','Bottom')
    Set-CcAnchor $txtChatC @('Left','Right','Bottom')
    Set-CcAnchor $btnSendC @('Right','Bottom')

    # Rechtsklick auf einen dauerhaften Chat-Kanal löschen (nur Ersteller/globaler Admin).
    $ctxChansC = New-Object System.Windows.Forms.ContextMenuStrip
    [void]$ctxChansC.Items.Add("Dauerhaften Kanal löschen")
    $lvChansC.ContextMenuStrip = $ctxChansC
    $ctxChansC.add_Opening({
        param($sender, $e)
        if ($lvChansC.SelectedItems.Count -eq 0 -or -not $lvChansC.SelectedItems[0].Tag.Permanent) { $e.Cancel = $true }
    })
    $ctxChansC.Items[0].Add_Click({
        if ($lvChansC.SelectedItems.Count -eq 0) { return }
        $tag = $lvChansC.SelectedItems[0].Tag
        if (-not $tag.Permanent) { return }
        $confirm = [System.Windows.Forms.MessageBox]::Show("Dauerhaften Kanal '$($tag.Name)' wirklich löschen?", "Kanal löschen", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        $err = $ccSocial.DeleteChannel($tag.Id, (Get-CcOwnIp))
        if ($err) { Show-CcMsg $err } else { Add-CcChat "Kanal '$($tag.Name)' gelöscht." ([System.Drawing.Color]::LightGray) $false }
    })

    # ---- Bereich Dateien ---------------------------------------------------------------------
    $btnF1 = New-CcButton "1. Datei senden" 0 0 200 38 $true
    $btnF2 = New-CcButton "2. IP Auswahl" 208 0 170 38
    $btnF3 = New-CcButton "3. Download-Verzeichnis öffnen" 386 0 260 38
    $btnFDir = New-CcButton "Download-Ordner ändern" 654 0 230 38
    $lblNodeF = New-CcLabel "Port 9876: geschlossen" 0 44 972 20
    $lblTargetF = New-CcLabel "Ziel: (noch keins gewählt - Button 2)" 0 68 700 22
    $lblDirF = New-CcLabel "" 0 90 972 20
    $lblDirF.ForeColor = [System.Drawing.Color]::LightGray
    $lblPeersF = New-CcLabel "Gefundene Manager (Doppelklick = als Ziel wählen):" 0 116 500 20
    $lblStreamsF = New-CcLabel "Parallele Verbindungen:" 520 116 170 20
    $numStreamsF = New-CcNumeric 695 113 60 1 8 4
    $lblLimitF = New-CcLabel "Limit MB/s (0 = aus):" 770 116 130 20
    $numLimitF = New-CcNumeric 900 113 72 0 10000 0
    $lvPeersF = New-CcListView 0 138 972 100 @('Name','IP-Adresse','Status') @(380,220,340)
    $lblTrF = New-CcLabel "Übertragungen (Fortschritt, Tempo, Restzeit):" 0 244 500 20
    $lvTransfersF = New-CcListView 0 266 972 226 @('Richtung','Datei / Ordner','Peer','Größe','Fortschritt','Tempo','Rest','Status') @(80,250,140,90,80,100,70,160)
    $btnCancelF = New-CcButton "Ausgewählte abbrechen" 0 500 220 32
    $btnClearF = New-CcButton "Fertige entfernen" 230 500 200 32
    $rtbLogF = New-CcRtb 0 540 972 100
    $pF.Controls.AddRange(@($btnF1, $btnF2, $btnF3, $btnFDir, $lblNodeF, $lblTargetF, $lblDirF, $lblPeersF, $lblStreamsF, $numStreamsF, $lblLimitF, $numLimitF, $lvPeersF, $lblTrF, $lvTransfersF, $btnCancelF, $btnClearF, $rtbLogF))
    [void](New-CcPeerContextMenu $lvPeersF)
    Set-CcAnchor $lvPeersF @('Top','Left','Right')
    Set-CcAnchor $lvTransfersF @('Top','Left','Right','Bottom')
    Set-CcAnchor $btnCancelF @('Left','Bottom')
    Set-CcAnchor $btnClearF @('Left','Bottom')
    Set-CcAnchor $rtbLogF @('Left','Right','Bottom')

    # ---- Bereich Voice -----------------------------------------------------------------------
    # Aufbau: links "Kanäle im Netzwerk", darunter "Teilnehmer", darunter Protokoll und
    # Audio-Einstellungen. Rechts eine Spalte mit ALLEN Buttons in einheitlicher Größe,
    # bündig unter "Dein Name" (Kopfzeile) - so bleibt die Bedienung an einer Stelle.
    $vColX = 696                     # linke Kante der Button-Spalte = linke Kante des Namensfelds
    $vColW = 276                     # bis zum rechten Rand (wie Namensfeld + "Ändern")
    $vBtnH = 34
    $vStep = 40
    $vLeftW = $vColX - 12            # Breite der linken Spalte (Listen, Protokoll, Regler)
    $btnV1 = New-CcButton "1. Kanal erstellen" $vColX (0 * $vStep) $vColW $vBtnH $true
    $btnV2 = New-CcButton "2. Privat sprechen" $vColX (1 * $vStep) $vColW $vBtnH
    $btnV3 = New-CcButton "3. Gruppen-Voice-Chat" $vColX (2 * $vStep) $vColW $vBtnH $true
    $btnV4 = New-CcButton "4. Passwort-Kanal" $vColX (3 * $vStep) $vColW $vBtnH
    $btnV5 = New-CcButton "5. Sound Ein/Aus" $vColX (4 * $vStep) $vColW $vBtnH
    $btnLeaveV = New-CcButton "Kanal verlassen" $vColX (5 * $vStep) $vColW $vBtnH
    $btnFriendsV = New-CcButton "Nur Freunde: Aus" $vColX (6 * $vStep) $vColW $vBtnH
    $lblIpV = New-CcLabel "Teilnehmer per IP hinzufügen (falls die automatische Suche nichts findet):" $vColX (7 * $vStep + 8) $vColW 36
    $txtIpV = New-CcText $vColX (7 * $vStep + 46) $vColW 26
    $btnIpAddV = New-CcButton "Hinzufügen" $vColX (7 * $vStep + 78) $vColW $vBtnH

    $lblStateV = New-CcLabel "Aktiver Kanal: (keiner)" 0 0 $vLeftW 22
    $lblChansV = New-CcLabel "Kanäle im Netzwerk:" 0 26 300 20
    $lvChansV = New-CcListView 0 48 $vLeftW 130 @('Kanal','Ersteller (IP)','Teilnehmer','Schutz','Status') @(190,130,90,90,150)
    $lblPeersV = New-CcLabel "Teilnehmer:" 0 186 300 20
    $lvPeersV = New-CcListView 0 208 $vLeftW 128 @('Name','IP-Adresse','Kanal','Status','Ping') @(190,130,150,110,70)
    $rtbLogV = New-CcRtb 0 344 $vLeftW 108
    $chkPttV = New-Object System.Windows.Forms.CheckBox
    $chkPttV.Text = "Push-to-Talk statt Sprachaktivierung"
    $chkPttV.Location = New-Object System.Drawing.Point(0, 460)
    $chkPttV.Size = New-Object System.Drawing.Size(260, 24)
    $chkPttV.ForeColor = $cWhite
    $chkPttV.Font = $fontMain
    $lblPttKeyV = New-CcLabel "Taste:" 270 462 50 20
    $cbPttKeyV = New-Object System.Windows.Forms.ComboBox
    $cbPttKeyV.Location = New-Object System.Drawing.Point(320, 458)
    $cbPttKeyV.Size = New-Object System.Drawing.Size(160, 26)
    $cbPttKeyV.DropDownStyle = "DropDownList"
    $cbPttKeyV.BackColor = $cInput
    $cbPttKeyV.ForeColor = $cWhite
    $cbPttKeyV.Font = $fontMain
    $pttKeyMap = [ordered]@{ 'Alt' = 0x12; 'Strg' = 0x11; 'Umschalt' = 0x10; 'Leertaste' = 0x20; 'Feststelltaste' = 0x14; 'Tab' = 0x09 }
    foreach ($kn in $pttKeyMap.Keys) { [void]$cbPttKeyV.Items.Add($kn) }
    $cbPttKeyV.SelectedIndex = 0
    $chkMuteV = New-Object System.Windows.Forms.CheckBox
    $chkMuteV.Text = "Mikrofon stumm"
    $chkMuteV.Location = New-Object System.Drawing.Point(0, 490)
    $chkMuteV.Size = New-Object System.Drawing.Size(170, 24)
    $chkMuteV.ForeColor = $cWhite
    $chkMuteV.Font = $fontMain
    $chkDeafV = New-Object System.Windows.Forms.CheckBox
    $chkDeafV.Text = "Ton aus (Ausgabe stumm)"
    $chkDeafV.Location = New-Object System.Drawing.Point(180, 490)
    $chkDeafV.Size = New-Object System.Drawing.Size(210, 24)
    $chkDeafV.ForeColor = $cWhite
    $chkDeafV.Font = $fontMain
    $lblLevelV = New-CcLabel "Mikro-Pegel:" 400 493 90 20
    $pbLevelV = New-Object System.Windows.Forms.ProgressBar
    $pbLevelV.Location = New-Object System.Drawing.Point(490, 492)
    $pbLevelV.Size = New-Object System.Drawing.Size(($vLeftW - 490), 18)
    $pbLevelV.Minimum = 0
    $pbLevelV.Maximum = 100
    $lblSensV = New-CcLabel "Empfindlichkeit (Schwelle):" 0 530 190 20
    $tbSensV = New-Object System.Windows.Forms.TrackBar
    $tbSensV.Location = New-Object System.Drawing.Point(190, 522)
    $tbSensV.Size = New-Object System.Drawing.Size(200, 45)
    $tbSensV.Minimum = 50
    $tbSensV.Maximum = 3000
    $tbSensV.TickFrequency = 500
    $tbSensV.Value = 350
    $lblVolV = New-CcLabel "Lautstärke:" 400 530 90 20
    $tbVolV = New-Object System.Windows.Forms.TrackBar
    $tbVolV.Location = New-Object System.Drawing.Point(490, 522)
    $tbVolV.Size = New-Object System.Drawing.Size(($vLeftW - 490), 45)
    $tbVolV.Minimum = 0
    $tbVolV.Maximum = 200
    $tbVolV.TickFrequency = 25
    $tbVolV.Value = 100
    $lblHintV = New-CcLabel "Tipp: Kanäle (Button 1/4) sind dauerhaft - sie bleiben gespeichert und werden automatisch mit allen anderen Managern abgeglichen, auch wenn gerade niemand drin ist. Für Sprachchat ein Headset benutzen (keine Echo-Unterdrückung)." 0 572 $vLeftW 56
    $lblHintV.ForeColor = [System.Drawing.Color]::LightGray
    $pV.Controls.AddRange(@($btnV1, $btnV2, $btnV3, $btnV4, $btnV5, $lblStateV, $btnLeaveV, $lblChansV, $lblPeersV, $btnFriendsV, $lvChansV, $lvPeersV, $rtbLogV, $chkMuteV, $chkDeafV, $lblLevelV, $pbLevelV, $lblSensV, $tbSensV, $lblVolV, $tbVolV, $lblIpV, $txtIpV, $btnIpAddV, $lblHintV, $chkPttV, $lblPttKeyV, $cbPttKeyV))
    [void](New-CcPeerContextMenu $lvPeersV)
    $btnFriendsV.Add_Click({
        $st.VoiceFriendsOnly = -not $st.VoiceFriendsOnly
        if ($st.VoiceFriendsOnly) {
            $btnFriendsV.Text = "Nur Freunde: An"
            $btnFriendsV.BackColor = $cAccent
        } else {
            $btnFriendsV.Text = "Nur Freunde: Aus"
            $btnFriendsV.BackColor = $cBtn
        }
        if ($st.VoiceNode) { Update-CcVoiceLists }
    })
    # Größenänderung: die Button-Spalte bleibt rechts oben (unter "Dein Name"), die Kanal-
    # liste wird breiter, die Teilnehmerliste wächst in Breite UND Höhe; Protokoll, Regler
    # und Hinweis bleiben als Block am unteren Rand.
    foreach ($cRight in @($btnV1, $btnV2, $btnV3, $btnV4, $btnV5, $btnLeaveV, $btnFriendsV, $lblIpV, $txtIpV, $btnIpAddV)) {
        Set-CcAnchor $cRight @('Top','Right')
    }
    Set-CcAnchor $lblStateV @('Top','Left','Right')
    Set-CcAnchor $lvChansV @('Top','Left','Right')
    Set-CcAnchor $lvPeersV @('Top','Left','Right','Bottom')
    foreach ($cLow in @($chkMuteV, $chkDeafV, $chkPttV, $lblPttKeyV, $cbPttKeyV, $lblLevelV, $lblSensV, $tbSensV, $lblVolV)) {
        Set-CcAnchor $cLow @('Left','Bottom')
    }
    Set-CcAnchor $pbLevelV @('Left','Right','Bottom')
    Set-CcAnchor $tbVolV @('Left','Right','Bottom')
    Set-CcAnchor $rtbLogV @('Left','Right','Bottom')
    Set-CcAnchor $lblHintV @('Left','Right','Bottom')

    # Rechtsklick auf einen dauerhaften Kanal: löschen (nur Ersteller oder globaler Admin,
    # transparent geprüft - kein versteckter Bypass-Code). Bei temporären, nicht
    # registrierten Kanälen ist der Menüpunkt deaktiviert.
    $ctxChansV = New-Object System.Windows.Forms.ContextMenuStrip
    [void]$ctxChansV.Items.Add("Dauerhaften Kanal löschen")
    $lvChansV.ContextMenuStrip = $ctxChansV
    $ctxChansV.add_Opening({
        param($s, $e)
        if ($lvChansV.SelectedItems.Count -eq 0 -or -not $lvChansV.SelectedItems[0].Tag.Permanent) { $e.Cancel = $true }
    })
    $ctxChansV.Items[0].Add_Click({
        if ($lvChansV.SelectedItems.Count -eq 0) { return }
        $tag = $lvChansV.SelectedItems[0].Tag
        if (-not $tag.Permanent) { return }
        $confirm = [System.Windows.Forms.MessageBox]::Show("Dauerhaften Kanal '$($tag.Name)' wirklich löschen?", "Kanal löschen", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        $err = $ccSocial.DeleteChannel($tag.Id, (Get-CcOwnIp))
        if ($err) { Show-CcMsg $err } else { Add-CcVoiceLog "Kanal '$($tag.Name)' gelöscht." }
    })

    $form.Controls.AddRange(@($lblAd, $lblNick, $txtNick, $btnNick, $navChat, $navFile, $navVoice, $lblStatus, $pC, $pF, $pV))
    Set-CcAnchor $lblStatus @('Top','Right')

    # ---- Umschalten der Bereiche --------------------------------------------------------------
    function Show-CcPanel([int]$idx) {
        $st.Panel = $idx
        $pC.Visible = ($idx -eq 0)
        $pF.Visible = ($idx -eq 1)
        $pV.Visible = ($idx -eq 2)
        $navs = @($navChat, $navFile, $navVoice)
        for ($i = 0; $i -lt 3; $i++) {
            if ($i -eq $idx) { $navs[$i].BackColor = $cAccent } else { $navs[$i].BackColor = $cBtn }
        }
        if ($idx -eq 0) {
            $st.ChatUnread = 0
            $navChat.Text = "Chat"
        }
        if ($idx -eq 2 -and -not $st.VoiceNode) { Start-CcVoice }
    }
    $navChat.Add_Click({ Show-CcPanel 0 })
    $navFile.Add_Click({ Show-CcPanel 1 })
    $navVoice.Add_Click({ Show-CcPanel 2 })

    # ---- Kopfbereich: Adapter und Name ------------------------------------------------------------
    # Der Adapter wird nicht mehr hier ausgewählt, sondern zentral im Control Center
    # (Live-Status -> "Adapter wechseln") - siehe Start beim Öffnen dieses Fensters weiter
    # unten, wo Get-PelSelectedAdapter einmalig gelesen und alle Netzdienste damit gestartet
    # werden.
    function Start-CcAllNodes {
        Start-CcChat
        Start-CcFile
        Start-CcSocial
    }

    $btnNick.Add_Click({
        $n = $txtNick.Text.Trim()
        if (-not $n) { Show-CcMsg "Bitte einen Namen eingeben."; return }
        $st.Nick = $n
        $clean = ($n -replace '[|\r\n]', '/')
        if ($clean.Length -gt 32) { $clean = $clean.Substring(0, 32) }
        if ($st.ChatNode) { $st.ChatNode.SetName($n) }
        if ($st.FileNode) { $st.FileNode.NodeName = $clean }
        if ($st.VoiceNode) { $st.VoiceNode.NodeName = $clean }
        Save-CcConfig
        Add-CcChat "Du heißt jetzt: $n" ([System.Drawing.Color]::LightGray) $false
    })
    $txtNick.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            $_.SuppressKeyPress = $true
            $btnNick.PerformClick()
        }
    })

    # ---- Ereignisse Chat -----------------------------------------------------------------------------
    $lvPeersC.Add_SelectedIndexChanged({ Update-CcChatTarget })

    $btnClearC.Add_Click({ $rtbChatC.Clear() })

    $btnHistC.Add_Click({
        try {
            if (-not (Test-Path -LiteralPath $histDir)) { New-Item -Path $histDir -ItemType Directory -Force | Out-Null }
            Start-Process explorer.exe -ArgumentList "`"$histDir`""
        } catch { Show-CcMsg "Ordner konnte nicht geöffnet werden:`n$($_.Exception.Message)" }
    })

    $chkSoundC.Add_CheckedChanged({ Save-CcConfig })

    $btnSendC.Add_Click({
        $text = $txtChatC.Text.Trim()
        if (-not $text) { return }
        if (-not $st.ChatNode) { Show-CcMsg "Der Chat-Dienst ist nicht aktiv. Bitte oben einen Netzwerkadapter wählen."; return }
        if ($lvPeersC.SelectedItems.Count -gt 0) {
            $target = [string]$lvPeersC.SelectedItems[0].Tag
            $targetName = $lvPeersC.SelectedItems[0].Text
            if ($st.ChatNode.SendPrivate($target, $text)) {
                Add-CcChat ("Ich an ${targetName} (privat): " + $text) ([System.Drawing.Color]::Violet)
            } else {
                Add-CcChat "($targetName ist nicht mehr verbunden - Nachricht wurde nicht zugestellt.)" ([System.Drawing.Color]::Orange) $false
            }
        } else {
            $myChan = [string]$st.ChatNode.GetMyChannel()
            if ($myChan) {
                $count = $st.ChatNode.SendToChannel($myChan, $text)
                Add-CcChat ("Ich [Kanal '$myChan']: " + $text) ([System.Drawing.Color]::LightSkyBlue)
                if ($count -eq 0) { Add-CcChat "(Niemand sonst im Kanal - Nachricht wurde nicht zugestellt.)" ([System.Drawing.Color]::Orange) $false }
            } else {
                $count = $st.ChatNode.Broadcast($text)
                Add-CcChat ("Ich: " + $text) ([System.Drawing.Color]::LightSkyBlue)
                if ($count -eq 0) { Add-CcChat "(Kein anderer Teilnehmer verbunden - Nachricht wurde nicht zugestellt.)" ([System.Drawing.Color]::Orange) $false }
            }
        }
        $txtChatC.Clear()
        $txtChatC.Focus()
    })
    $txtChatC.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            $_.SuppressKeyPress = $true
            $btnSendC.PerformClick()
        }
    })

    # ---- Ereignisse Chat-Kanäle ----------------------------------------------------------------------
    $btnC1.Add_Click({
        if (-not $st.ChatNode) { Show-CcMsg "Der Chat-Dienst ist nicht aktiv."; return }
        $name = Read-CcText "Kanal erstellen" "Name des neuen, dauerhaften Kanals:"
        if (-not $name) { return }
        $name = $name.Trim()
        foreach ($c in @($ccSocial.GetChannels())) {
            if ($c.Name -eq $name) { Show-CcMsg "Ein dauerhafter Kanal mit diesem Namen existiert bereits - bitte über die Liste beitreten."; return }
        }
        [void]$ccSocial.CreateChannel($name, (Get-CcOwnIp), '')
        $st.ChatNode.SetChannel($name)
        Add-CcChat "Dauerhafter Kanal '$name' erstellt, gespeichert und betreten. Wird automatisch mit anderen Managern abgeglichen." ([System.Drawing.Color]::LightGray) $false
        Update-CcChatTarget
    })
    $btnC2.Add_Click({
        if (-not $st.ChatNode) { Show-CcMsg "Der Chat-Dienst ist nicht aktiv."; return }
        $name = Read-CcText "Passwort-Kanal erstellen" "Name des neuen, dauerhaften Kanals:"
        if (-not $name) { return }
        $name = $name.Trim()
        foreach ($c in @($ccSocial.GetChannels())) {
            if ($c.Name -eq $name) { Show-CcMsg "Ein dauerhafter Kanal mit diesem Namen existiert bereits."; return }
        }
        $pw1 = Read-CcText "Passwort-Kanal erstellen" "Passwort festlegen:" $true
        if (-not $pw1) { return }
        $pw2 = Read-CcText "Passwort-Kanal erstellen" "Passwort wiederholen:" $true
        if ($pw1 -ne $pw2) { Show-CcMsg "Die Passwörter stimmen nicht überein."; return }
        [void]$ccSocial.CreateChannel($name, (Get-CcOwnIp), $pw1)
        $st.ChatNode.SetChannel($name)
        Add-CcChat "Dauerhafter Passwort-Kanal '$name' erstellt, gespeichert und betreten." ([System.Drawing.Color]::LightGray) $false
        Update-CcChatTarget
    })
    $lvChansC.Add_DoubleClick({
        if (-not $st.ChatNode) { Show-CcMsg "Der Chat-Dienst ist nicht aktiv."; return }
        if ($lvChansC.SelectedItems.Count -eq 0) { return }
        $it = $lvChansC.SelectedItems[0]
        $tag = $it.Tag
        if (-not $tag.Name) {
            $st.ChatNode.SetChannel('')
            Add-CcChat "Kanal verlassen - sende wieder an alle Teilnehmer." ([System.Drawing.Color]::LightGray) $false
            Update-CcChatTarget
            return
        }
        if ($it.SubItems[3].Text -eq 'aktiv') { Show-CcMsg "Du bist bereits in diesem Kanal."; return }
        $pw = ''
        if ($it.SubItems[2].Text -eq 'Passwort') {
            $pw = Read-CcText "Passwort-Kanal" "Passwort für Kanal '$($tag.Name)':" $true
            if ($null -eq $pw) { return }
            if ($tag.Permanent -and $tag.Id -and -not ($ccSocial.CheckChannelPassword($tag.Id, $pw))) {
                Show-CcMsg "Falsches Passwort."
                return
            }
        }
        $st.ChatNode.SetChannel($tag.Name)
        Add-CcChat "Kanal '$($tag.Name)' betreten." ([System.Drawing.Color]::LightGray) $false
        Update-CcChatTarget
    })

    # ---- Ereignisse Dateien --------------------------------------------------------------------------
    $btnF1.Add_Click({
        if (-not $st.FileNode) { Show-CcMsg "Der Datei-Dienst ist nicht aktiv. Bitte oben einen Netzwerkadapter wählen."; return }
        if (-not $st.FileTarget) {
            $t = Select-CcFileTarget
            if (-not $t) { return }
            Set-CcFileTarget $t
        }
        $choice = [System.Windows.Forms.MessageBox]::Show("Was möchtest du an $($st.FileTarget.Name) senden?`n`nJa = Dateien auswählen`nNein = ganzen Ordner auswählen", "Dateien senden", [System.Windows.Forms.MessageBoxButtons]::YesNoCancel, [System.Windows.Forms.MessageBoxIcon]::Question)
        $paths = @()
        if ($choice -eq [System.Windows.Forms.DialogResult]::Yes) {
            $ofd = New-Object System.Windows.Forms.OpenFileDialog
            $ofd.Title = "Dateien zum Senden auswählen"
            $ofd.Multiselect = $true
            if ($ofd.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
            $paths = @($ofd.FileNames)
        } elseif ($choice -eq [System.Windows.Forms.DialogResult]::No) {
            $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
            $fbd.Description = "Ordner zum Senden auswählen (inklusive Unterordner)"
            if ($fbd.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
            $paths = @($fbd.SelectedPath)
        } else {
            return
        }
        $st.FileNode.Streams = [int]$numStreamsF.Value
        $st.FileNode.LimitBytesPerSec = [long]([double]$numLimitF.Value * 1MB)
        $err = $st.FileNode.SendPaths([string]$st.FileTarget.Ip, [string]$st.FileTarget.Name, [string[]]$paths)
        if ($err) { Show-CcMsg $err } else { Add-CcFileLog "Sende an $($st.FileTarget.Name): $($paths.Count) Auswahl(en) - warte auf Zustimmung ..." }
    })

    $btnF2.Add_Click({
        $t = Select-CcFileTarget
        if ($t) { Set-CcFileTarget $t; Add-CcFileLog "Ziel gesetzt: $($t.Name) ($($t.Ip))" }
    })
    $lvPeersF.Add_DoubleClick({
        if ($lvPeersF.SelectedItems.Count -gt 0) {
            $t = $lvPeersF.SelectedItems[0].Tag
            Set-CcFileTarget $t
            Add-CcFileLog "Ziel gesetzt: $($t.Name) ($($t.Ip))"
        }
    })

    $btnF3.Add_Click({
        try {
            if (-not (Test-Path -LiteralPath $st.DownloadDir)) { New-Item -Path $st.DownloadDir -ItemType Directory -Force | Out-Null }
            Start-Process explorer.exe -ArgumentList "`"$($st.DownloadDir)`""
        } catch { Show-CcMsg "Ordner konnte nicht geöffnet werden:`n$($_.Exception.Message)" }
    })

    $btnFDir.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Download-Ordner wählen"
        $fbd.SelectedPath = $st.DownloadDir
        if ($fbd.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
            $st.DownloadDir = $fbd.SelectedPath
            $lblDirF.Text = "Download-Ordner: $($st.DownloadDir)"
            if ($st.FileNode) { $st.FileNode.DownloadDir = [string]$st.DownloadDir }
            Save-CcConfig
            Add-CcFileLog "Download-Ordner: $($st.DownloadDir) (gilt für neue Übertragungen)"
        }
    })

    $btnCancelF.Add_Click({
        if ($lvTransfersF.SelectedItems.Count -eq 0 -or -not $st.FileNode) { return }
        $st.FileNode.CancelTransfer([string]$lvTransfersF.SelectedItems[0].Tag)
    })
    $btnClearF.Add_Click({ if ($st.FileNode) { $st.FileNode.RemoveFinished() } })
    $numStreamsF.Add_ValueChanged({ if ($st.FileNode) { $st.FileNode.Streams = [int]$numStreamsF.Value; Save-CcConfig } })
    $numLimitF.Add_ValueChanged({ if ($st.FileNode) { $st.FileNode.LimitBytesPerSec = [long]([double]$numLimitF.Value * 1MB); Save-CcConfig } })

    # ---- Ereignisse Voice ----------------------------------------------------------------------------
    $btnV1.Add_Click({
        if (-not $st.VoiceNode) { Show-CcMsg "Der Voice-Dienst ist nicht aktiv."; return }
        $name = Read-CcText "Kanal erstellen" "Name des neuen, dauerhaften Kanals:"
        if (-not $name) { return }
        $name = $name.Trim()
        foreach ($c in @($ccSocial.GetChannels())) {
            if ($c.Name -eq $name) { Show-CcMsg "Ein dauerhafter Kanal mit diesem Namen existiert bereits - bitte über die Liste links beitreten."; return }
        }
        [void]$ccSocial.CreateChannel($name, (Get-CcOwnIp), '')
        $err = $st.VoiceNode.CreateChannel($name, '')
        if ($err) { Show-CcMsg $err } else { Add-CcVoiceLog "Dauerhafter Kanal '$name' erstellt, gespeichert und betreten. Wird automatisch mit anderen Managern abgeglichen." }
    })

    $btnV2.Add_Click({
        if (-not $st.VoiceNode) { Show-CcMsg "Der Voice-Dienst ist nicht aktiv."; return }
        if ($lvPeersV.SelectedItems.Count -eq 0) {
            Show-CcMsg "Bitte zuerst rechts einen Teilnehmer auswählen, mit dem du privat sprechen willst."
            return
        }
        $err = $st.VoiceNode.Call([string]$lvPeersV.SelectedItems[0].Tag.Id)
        if ($err) { Show-CcMsg $err }
    })
    $lvPeersV.Add_DoubleClick({ $btnV2.PerformClick() })

    $btnV3.Add_Click({
        if (-not $st.VoiceNode) { Show-CcMsg "Der Voice-Dienst ist nicht aktiv."; return }
        if ($lvChansV.SelectedItems.Count -eq 0) {
            Show-CcMsg "Bitte zuerst links einen Kanal auswählen (oder mit Button 1 einen neuen erstellen)."
            return
        }
        $it = $lvChansV.SelectedItems[0]
        $tag = $it.Tag
        $name = $tag.Name
        if ($it.SubItems[4].Text -eq 'aktiv') { Show-CcMsg "Du bist bereits in diesem Kanal."; return }
        $pw = ''
        if ($it.SubItems[3].Text -eq 'Passwort') {
            $pw = Read-CcText "Passwort-Kanal" "Passwort für Kanal '$name':" $true
            if ($null -eq $pw) { return }
            if ($tag.Permanent -and $tag.Id -and -not ($ccSocial.CheckChannelPassword($tag.Id, $pw))) {
                Show-CcMsg "Falsches Passwort."
                return
            }
        }
        $err = $st.VoiceNode.JoinChannel($name, $pw)
        if ($err) { Show-CcMsg $err } else { Add-CcVoiceLog "Trete Kanal '$name' bei ..." }
    })
    $lvChansV.Add_DoubleClick({ $btnV3.PerformClick() })

    $btnV4.Add_Click({
        if (-not $st.VoiceNode) { Show-CcMsg "Der Voice-Dienst ist nicht aktiv."; return }
        $name = Read-CcText "Passwort-Kanal erstellen" "Name des neuen, dauerhaften Kanals:"
        if (-not $name) { return }
        $name = $name.Trim()
        foreach ($c in @($ccSocial.GetChannels())) {
            if ($c.Name -eq $name) { Show-CcMsg "Ein dauerhafter Kanal mit diesem Namen existiert bereits."; return }
        }
        $pw1 = Read-CcText "Passwort-Kanal erstellen" "Passwort festlegen:" $true
        if (-not $pw1) { return }
        $pw2 = Read-CcText "Passwort-Kanal erstellen" "Passwort wiederholen:" $true
        if ($pw1 -ne $pw2) { Show-CcMsg "Die Passwörter stimmen nicht überein."; return }
        [void]$ccSocial.CreateChannel($name, (Get-CcOwnIp), $pw1)
        $err = $st.VoiceNode.CreateChannel($name, $pw1)
        if ($err) { Show-CcMsg $err } else { Add-CcVoiceLog "Dauerhafter Passwort-Kanal '$name' erstellt, gespeichert und betreten." }
    })

    $btnV5.Add_Click({
        $sel = Select-CcDevices
        if (-not $sel) { return }
        $st.InDev = [int]$sel.In
        $st.OutDev = [int]$sel.Out
        $st.InName = [string]$sel.InName
        $st.OutName = [string]$sel.OutName
        Save-CcConfig
        Start-CcVoiceAudio
    })

    $btnLeaveV.Add_Click({
        if ($st.VoiceNode) { $st.VoiceNode.LeaveChannel(); Add-CcVoiceLog "Kanal verlassen." }
    })

    $chkMuteV.Add_CheckedChanged({ if ($st.VoiceNode) { $st.VoiceNode.MicMuted = [bool]$chkMuteV.Checked } })
    $chkDeafV.Add_CheckedChanged({ if ($st.VoiceNode) { $st.VoiceNode.Deafened = [bool]$chkDeafV.Checked } })
    $chkPttV.Add_CheckedChanged({ if ($st.VoiceNode) { $st.VoiceNode.PttMode = [bool]$chkPttV.Checked } })
    $cbPttKeyV.Add_SelectedIndexChanged({ if ($st.VoiceNode -and $cbPttKeyV.SelectedItem) { $st.VoiceNode.PttVKey = [int]$pttKeyMap[[string]$cbPttKeyV.SelectedItem] } })
    $tbSensV.Add_ValueChanged({ if ($st.VoiceNode) { $st.VoiceNode.Threshold = [int]$tbSensV.Value } })
    $tbVolV.Add_ValueChanged({ if ($st.VoiceNode) { $st.VoiceNode.VolumePercent = [int]$tbVolV.Value } })

    $btnIpAddV.Add_Click({
        if (-not $st.VoiceNode) { Show-CcMsg "Der Voice-Dienst ist nicht aktiv."; return }
        $parsed = $null
        $ipText = $txtIpV.Text.Trim()
        if (-not [System.Net.IPAddress]::TryParse($ipText, [ref]$parsed) -or $parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
            Show-CcMsg "Bitte eine gültige IPv4-Adresse eingeben (z. B. 10.147.17.5)."
            return
        }
        $st.VoiceNode.AddManualPeer($ipText)
        Add-CcVoiceLog "Teilnehmer $ipText hinzugefügt."
    })

    $form.Add_Activated({
        if ($st.Panel -eq 0) { $st.ChatUnread = 0; $navChat.Text = "Chat" }
    })

    # ===================================================================================
    # Timer: Ereignisse aller drei Dienste, Listen des sichtbaren Bereichs
    # ===================================================================================
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 250
    $timer.Add_Tick({
        $st.Tick = $st.Tick + 1

        # Freundes-/Bannliste wurde außerhalb geändert (z. B. in Option 11): neu einlesen,
        # damit die Kommunikationszentrale nicht mit einem veralteten Stand weiterarbeitet
        # und ihn beim nächsten Speichern zurückschreibt.
        if (($st.Tick % 8) -eq 0) {
            try {
                $stamp = ''
                foreach ($sf in @([EarthSocialPaths]::BansFile, [EarthSocialPaths]::FriendsFile)) {
                    if ([System.IO.File]::Exists($sf)) { $stamp += [string][System.IO.File]::GetLastWriteTimeUtc($sf).Ticks + ';' } else { $stamp += '0;' }
                }
                if (-not $st.ContainsKey('SocialStamp')) { $st.SocialStamp = $stamp }
                elseif ($stamp -ne $st.SocialStamp) {
                    $st.SocialStamp = $stamp
                    $ccBans.Load()
                    $ccSocial.Load()
                }
            } catch { }
        }

        # --- Chat
        $cn = $st.ChatNode
        if ($cn) {
            $ev = $null
            $n = 0
            while ($n -lt 100 -and $cn.Events.TryDequeue([ref]$ev)) {
                $n++
                $type, $rest = $ev -split '\|', 2
                if ($type -eq 'SYS') {
                    Add-CcChat $rest ([System.Drawing.Color]::LightGray) $false
                } elseif ($type -eq 'PEER+') {
                    $f = $rest -split '\|', 3
                    if (-not $st.ChatKnown.ContainsKey($f[0])) {
                        $st.ChatKnown[$f[0]] = $f[1]
                        Add-CcChat "$($f[1]) ($($f[2])) ist beigetreten." ([System.Drawing.Color]::LightGreen)
                    }
                } elseif ($type -eq 'PEER-') {
                    $f = $rest -split '\|', 3
                    if ($st.ChatKnown.ContainsKey($f[0])) { $st.ChatKnown.Remove($f[0]) }
                    Add-CcChat "$($f[1]) hat die Verbindung getrennt." ([System.Drawing.Color]::Orange)
                } elseif ($type -eq 'NICK') {
                    $f = $rest -split '\|', 3
                    Add-CcChat "$($f[1]) heißt jetzt $($f[2])." ([System.Drawing.Color]::LightGray)
                } elseif ($type -eq 'CHAT') {
                    $f = $rest -split '\|', 3
                    Add-CcChat ("$($f[1]): $($f[2])") $cWhite
                    Send-CcChatNotify
                } elseif ($type -eq 'PM') {
                    $f = $rest -split '\|', 3
                    Add-CcChat ("[Privat] $($f[1]): $($f[2])") ([System.Drawing.Color]::Violet)
                    $isSel = ($st.Panel -eq 0 -and $lvPeersC.SelectedItems.Count -gt 0 -and [string]$lvPeersC.SelectedItems[0].Tag -eq $f[0])
                    if (-not $isSel) { $st.PmUnread[$f[0]] = $true }
                    Send-CcChatNotify
                }
            }
            if ($st.Panel -eq 0) {
                Update-CcChatPeers
                Update-CcChatChannels
                $scanText = ''
                if ($cn.ScanRunning) { $scanText = " | Scan: $($cn.ScanDone)/$($cn.ScanTotal)" }
                $lblNodeC.Text = "Port 9874 offen auf $($cn.BindIp) | Verbundene Teilnehmer: $($cn.PeerCount())$scanText"
            }
        }

        # --- Dateien
        $fn = $st.FileNode
        if ($fn) {
            $ev = $null
            $n = 0
            while ($n -lt 50 -and $fn.Events.TryDequeue([ref]$ev)) {
                $n++
                $type, $rest = $ev -split '\|', 2
                if ($type -eq 'SYS') {
                    Add-CcFileLog $rest
                } elseif ($type -eq 'DONE') {
                    $f = $rest -split '\|', 2
                    Add-CcFileLog "Fertig: $($f[1])"
                } elseif ($type -eq 'OFFER') {
                    $f = $rest -split '\|', 5
                    $timer.Stop()
                    $msg = "$($f[1]) ($($f[2])) möchte dir $($f[3]) Datei(en) senden ($(Format-CcBytes ([double]$f[4]))).`n`nGespeichert wird in:`n$($st.DownloadDir)`n`nAnnehmen?"
                    $answer = [System.Windows.Forms.MessageBox]::Show($msg, "Eingehende Dateien", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
                    $accept = ($answer -eq [System.Windows.Forms.DialogResult]::Yes)
                    $fn.AnswerOffer($f[0], $accept)
                    if ($accept) { Add-CcFileLog "Angebot von $($f[1]) angenommen." } else { Add-CcFileLog "Angebot von $($f[1]) abgelehnt." }
                    $timer.Start()
                }
            }
            if ($st.Panel -eq 1) {
                Update-CcFilePeers
                Update-CcTransfers
            }
        }

        # --- Voice
        $vn = $st.VoiceNode
        if ($vn) {
            $ev = $null
            $n = 0
            while ($n -lt 50 -and $vn.Events.TryDequeue([ref]$ev)) {
                $n++
                $type, $rest = $ev -split '\|', 2
                if ($type -eq 'SYS') {
                    Add-CcVoiceLog $rest
                } elseif ($type -eq 'CALL') {
                    $f = $rest -split '\|', 2
                    $timer.Stop()
                    $answer = [System.Windows.Forms.MessageBox]::Show("$($f[1]) möchte privat mit dir sprechen. Anruf annehmen?", "Eingehender Anruf", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
                    $accept = ($answer -eq [System.Windows.Forms.DialogResult]::Yes)
                    $vn.AnswerCall($f[0], $accept)
                    if ($accept) { Add-CcVoiceLog "Privatgespräch mit $($f[1]) gestartet." } else { Add-CcVoiceLog "Anruf von $($f[1]) abgelehnt." }
                    $timer.Start()
                }
            }
            if ($st.Panel -eq 2) {
                Update-CcVoiceLists
                $lvl = [int](($vn.MicLevel * 100) / 3000)
                $pbLevelV.Value = [math]::Max(0, [math]::Min(100, $lvl))
            }
        }

        $cCount = 0
        $fCount = 0
        if ($cn) { $cCount = $cn.PeerCount() }
        if ($fn) { $fCount = @($fn.GetPeers()).Count }
        $lblStatus.Text = "Chat: $cCount  |  Datei-Manager: $fCount"

        # Live-Übernahme eines im Control Center (Live-Status) gewechselten Adapters:
        # alle ca. 5 Sekunden prüfen, ob sich die zentral gespeicherte Auswahl geändert
        # hat, und Chat/Datei/Kanal-Dienste bei Bedarf automatisch auf dem neuen Adapter
        # neu starten - ohne dass dieses Fenster geschlossen und neu geöffnet werden muss.
        if (($st.Tick % 20) -eq 0) {
            $centralNow = Get-PelSelectedAdapter
            if ($centralNow -and (-not $st.Adapter -or $centralNow.Ip -ne $st.Adapter.Ip)) {
                $st.Adapter = $centralNow
                $lblAd.Text = "Adapter: $($st.Adapter.Name)  -  $($st.Adapter.Ip) / $($st.Adapter.Mask)"
                Add-CcChat "Adapter im Control Center gewechselt -> $($st.Adapter.Name) ($($st.Adapter.Ip)). Dienste werden neu gestartet ..." ([System.Drawing.Color]::LightGray) $false
                Start-CcAllNodes
            }
        }
    })

    # ---- Schließen -------------------------------------------------------------------------------------
    $form.Add_FormClosing({
        $timer.Stop()
        $active = 0
        if ($st.FileNode) {
            foreach ($ln in @($st.FileNode.GetTransfers())) {
                $f = $ln -split '\|'
                if ($f.Count -ge 10 -and $f[9] -eq '0') { $active++ }
            }
        }
        if ($active -gt 0) {
            $a = [System.Windows.Forms.MessageBox]::Show("Es laufen noch $active Dateiübertragung(en). Beim Schließen werden sie unterbrochen (Fortsetzen ist beim erneuten Senden möglich). Wirklich schließen?", "Kommunikationszentrale", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($a -ne [System.Windows.Forms.DialogResult]::Yes) {
                $_.Cancel = $true
                $timer.Start()
                return
            }
        }
        Stop-CcChat
        Stop-CcFile
        if ($st.VoiceNode) { try { $st.VoiceNode.Stop() } catch { }; $st.VoiceNode = $null }
        Stop-CcSocial
        if ($st.ChatFw) { Set-CcFirewall 'chat' $false }
        if ($st.FileFw) { Set-CcFirewall 'file' $false }
        if ($st.VoiceFw) { Set-CcFirewall 'voice' $false }
        if ($st.SocialFw) { Set-CcFirewall 'social' $false }
    })

    # ===================================================================================
    # Start
    # ===================================================================================
    if (Test-Path -LiteralPath $chatCfg) {
        try {
            $c1 = Get-Content -LiteralPath $chatCfg -Raw | ConvertFrom-Json
            if ($c1.Nick) { $st.Nick = [string]$c1.Nick }
            if ($null -ne $c1.Sound) { $chkSoundC.Checked = [bool]$c1.Sound }
        } catch { }
    }
    if (Test-Path -LiteralPath $fileCfg) {
        try {
            $c2 = Get-Content -LiteralPath $fileCfg -Raw | ConvertFrom-Json
            if ($c2.DownloadDir) { $st.DownloadDir = [string]$c2.DownloadDir }
            if ($c2.Streams) { $numStreamsF.Value = [math]::Min(8, [math]::Max(1, [int]$c2.Streams)) }
            if ($null -ne $c2.LimitMB) { $numLimitF.Value = [math]::Min(10000, [math]::Max(0, [int]$c2.LimitMB)) }
        } catch { }
    }
    $insList = [EarthWinmm]::InputDeviceNames()
    $outsList = [EarthWinmm]::OutputDeviceNames()
    $st.InName = $insList[0]
    $st.OutName = $outsList[0]
    if (Test-Path -LiteralPath $voiceCfg) {
        try {
            $c3 = Get-Content -LiteralPath $voiceCfg -Raw | ConvertFrom-Json
            $ii = [array]::IndexOf($insList, [string]$c3.InName)
            $oi = [array]::IndexOf($outsList, [string]$c3.OutName)
            if ($ii -ge 0) { $st.InDev = $ii - 1; $st.InName = $insList[$ii] }
            if ($oi -ge 0) { $st.OutDev = $oi - 1; $st.OutName = $outsList[$oi] }
        } catch { }
    }
    if (-not $st.Nick) { $st.Nick = $env:COMPUTERNAME }
    $txtNick.Text = $st.Nick
    $lblDirF.Text = "Download-Ordner: $($st.DownloadDir)"

    # Chat-Verlauf von heute
    try {
        $hf = Get-CcHistFile
        if (Test-Path -LiteralPath $hf) {
            $old = @(Get-Content -LiteralPath $hf -Tail 30 -Encoding UTF8)
            if ($old.Count -gt 0) {
                Add-CcRtb $rtbChatC "--- Verlauf (heute) ---" ([System.Drawing.Color]::Gray) $false
                foreach ($ol in $old) { Add-CcRtb $rtbChatC $ol ([System.Drawing.Color]::Gray) $false }
                Add-CcRtb $rtbChatC "--- Ende Verlauf ---" ([System.Drawing.Color]::Gray) $false
            }
        }
    } catch { }

    # Adapter kommt jetzt zentral aus dem Control Center (Live-Status -> "Adapter
    # wechseln"); ist dort noch nichts gewählt, automatisch den Adapter mit der
    # niedrigsten Schnittstellenmetrik nehmen (= von Windows bevorzugte Verbindung) und
    # gleich zentral speichern (damit Option 9 denselben verwendet).
    $st.Adapter = Get-PelSelectedAdapter
    if (-not $st.Adapter) {
        $st.Adapter = Get-PelAutoAdapter
        if ($st.Adapter) { Save-PelSelectedAdapter $st.Adapter }
    }
    if ($st.Adapter) { Connect-PelZeroTierNetwork -Adapter $st.Adapter }
    if (-not $st.Adapter) {
        Show-CcMsg "Es wurde kein aktiver IPv4-Netzwerkadapter gefunden. Bitte im Control Center (Live-Status) einen Adapter wählen." "Kommunikationszentrale" ([System.Windows.Forms.MessageBoxIcon]::Warning)
        $lblAd.Text = "Adapter: keiner verfügbar"
    } else {
        $lblAd.Text = "Adapter: $($st.Adapter.Name)  -  $($st.Adapter.Ip) / $($st.Adapter.Mask)"
    }
    $st.Loading = $false

    Show-CcPanel 0
    Start-CcAllNodes
    $timer.Start()

    [void]$form.ShowDialog()
    $timer.Dispose()
}


# ------------------------------------------------------------------------------
# Gemeinsame Typen: Sicherheit & Social (Bans, Freunde, Kanäle, Anstupsen).
# Wird von der Kommunikationszentrale für das Kontextmenü (Ban/Freund/Poke/
# Lautstärke) der Teilnehmerlisten verwendet.
# ------------------------------------------------------------------------------
function Initialize-SocialTypes {
    if (-not ('EarthSocialNode' -as [type])) {
        $socialCode = @'
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;

// -----------------------------------------------------------------------------
// Gemeinsamer Datenordner und Datenmodelle (JSON, von Hand geschrieben/gelesen -
// keine externe JSON-Bibliothek noetig, das Format ist absichtlich einfach).
// -----------------------------------------------------------------------------
public static class EarthSocialPaths
{
    public const string DataDir = @"C:\Project-Earth-Lan";
    public const string BansFile = @"C:\Project-Earth-Lan\ip_bans.json";
    public const string FriendsFile = @"C:\Project-Earth-Lan\Friendlist.json";
    public const string VolumesFile = @"C:\Project-Earth-Lan\PeerVolumes.json";

    public static void EnsureDir()
    {
        try { if (!Directory.Exists(DataDir)) Directory.CreateDirectory(DataDir); } catch (Exception) { }
    }
}

public class EarthBanEntry
{
    public string Ip = "";
    public string Reason = "";
    public string BannedByIp = "";
    public long TimestampUtc;
    public bool Deleted;
    public long UpdatedUtc;
}

public class EarthFriendEntry
{
    public string Ip = "";
    public string Name = "";
    public string Notes = "";
    public bool Deleted;
    public long UpdatedUtc;
}

public class EarthChannelEntry
{
    public string Id = "";
    public string Name = "";
    public string OwnerIp = "";
    public string PasswordHash = "";
    public string Salt = "";
    public long CreatedUtc;
    public bool Deleted;
    public long UpdatedUtc;
}

// -----------------------------------------------------------------------------
// Sehr einfacher, robuster JSON-Reader/-Writer fuer die drei Datenmodelle oben.
// Bewusst ohne fremde Abhaengigkeiten (Windows PowerShell 5.1 hat keine
// System.Text.Json). Werte werden Feld-fuer-Feld geschrieben/gelesen.
// -----------------------------------------------------------------------------
public static class EarthJson
{
    public static string Esc(string s)
    {
        if (s == null) return "";
        StringBuilder sb = new StringBuilder();
        foreach (char c in s)
        {
            if (c == '"' || c == '\\') sb.Append('\\').Append(c);
            else if (c == '\n') sb.Append("\\n");
            else if (c == '\r') { }
            else if (c < 0x20) sb.Append(' ');
            else sb.Append(c);
        }
        return sb.ToString();
    }

    private static Dictionary<string, string> ParseObject(string s, ref int pos)
    {
        Dictionary<string, string> d = new Dictionary<string, string>();
        SkipWs(s, ref pos);
        if (pos >= s.Length || s[pos] != '{') return d;
        pos++;
        SkipWs(s, ref pos);
        if (pos < s.Length && s[pos] == '}') { pos++; return d; }
        while (pos < s.Length)
        {
            SkipWs(s, ref pos);
            string key = ParseString(s, ref pos);
            SkipWs(s, ref pos);
            if (pos < s.Length && s[pos] == ':') pos++;
            SkipWs(s, ref pos);
            string val;
            if (pos < s.Length && s[pos] == '"') val = ParseString(s, ref pos);
            else val = ParseLiteral(s, ref pos);
            d[key] = val;
            SkipWs(s, ref pos);
            if (pos < s.Length && s[pos] == ',') { pos++; continue; }
            if (pos < s.Length && s[pos] == '}') { pos++; break; }
            break;
        }
        return d;
    }

    private static void SkipWs(string s, ref int pos)
    {
        while (pos < s.Length && char.IsWhiteSpace(s[pos])) pos++;
    }

    private static string ParseString(string s, ref int pos)
    {
        StringBuilder sb = new StringBuilder();
        if (pos >= s.Length || s[pos] != '"') return "";
        pos++;
        while (pos < s.Length && s[pos] != '"')
        {
            char c = s[pos];
            if (c == '\\' && pos + 1 < s.Length)
            {
                pos++;
                char n = s[pos];
                if (n == 'n') sb.Append('\n');
                else if (n == 't') sb.Append('\t');
                else sb.Append(n);
            }
            else sb.Append(c);
            pos++;
        }
        if (pos < s.Length) pos++;
        return sb.ToString();
    }

    private static string ParseLiteral(string s, ref int pos)
    {
        int start = pos;
        while (pos < s.Length && s[pos] != ',' && s[pos] != '}' && s[pos] != ']') pos++;
        return s.Substring(start, pos - start).Trim();
    }

    public static List<Dictionary<string, string>> ParseArray(string s)
    {
        List<Dictionary<string, string>> list = new List<Dictionary<string, string>>();
        int pos = s.IndexOf('[');
        if (pos < 0) return list;
        pos++;
        while (pos < s.Length)
        {
            SkipWs(s, ref pos);
            if (pos >= s.Length || s[pos] == ']') break;
            if (s[pos] == '{')
            {
                list.Add(ParseObject(s, ref pos));
            }
            SkipWs(s, ref pos);
            if (pos < s.Length && s[pos] == ',') { pos++; continue; }
            if (pos < s.Length && s[pos] == ']') { pos++; break; }
        }
        return list;
    }

    public static string GetStr(Dictionary<string, string> d, string k) { string v; return d.TryGetValue(k, out v) ? v : ""; }
    public static long GetLong(Dictionary<string, string> d, string k) { long v; string s; return (d.TryGetValue(k, out s) && long.TryParse(s, out v)) ? v : 0; }
    public static bool GetBool(Dictionary<string, string> d, string k) { string v; return d.TryGetValue(k, out v) && v.Trim().ToLower() == "true"; }
}

public static class EarthTime
{
    private static readonly DateTime Epoch = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc);
    public static long NowUtcMs() { return (long)(DateTime.UtcNow - Epoch).TotalMilliseconds; }
}

// -----------------------------------------------------------------------------
// BanManager: threadsicher, laedt/speichert ip_bans.json, wird von Chat-, Voice-
// und Datei-Knoten ueber EarthBanFilter (unten) konsultiert.
// -----------------------------------------------------------------------------
public class BanManager
{
    private readonly object lk = new object();
    private Dictionary<string, EarthBanEntry> bans = new Dictionary<string, EarthBanEntry>();
    public event Action Changed;

    public BanManager() { Load(); }

    public void Load()
    {
        lock (lk)
        {
            bans.Clear();
            try
            {
                if (File.Exists(EarthSocialPaths.BansFile))
                {
                    string txt = File.ReadAllText(EarthSocialPaths.BansFile, Encoding.UTF8);
                    foreach (Dictionary<string, string> o in EarthJson.ParseArray(txt))
                    {
                        EarthBanEntry e = new EarthBanEntry();
                        e.Ip = EarthJson.GetStr(o, "Ip");
                        e.Reason = EarthJson.GetStr(o, "Reason");
                        e.BannedByIp = EarthJson.GetStr(o, "BannedByIp");
                        e.TimestampUtc = EarthJson.GetLong(o, "TimestampUtc");
                        e.Deleted = EarthJson.GetBool(o, "Deleted");
                        e.UpdatedUtc = EarthJson.GetLong(o, "UpdatedUtc");
                        if (e.Ip.Length > 0) bans[e.Ip] = e;
                    }
                }
            }
            catch (Exception) { }
        }
    }

    public void Save()
    {
        lock (lk)
        {
            try
            {
                EarthSocialPaths.EnsureDir();
                StringBuilder sb = new StringBuilder();
                sb.Append("[\n");
                bool first = true;
                foreach (EarthBanEntry e in bans.Values)
                {
                    if (!first) sb.Append(",\n");
                    first = false;
                    sb.Append("  {");
                    sb.Append("\"Ip\":\"" + EarthJson.Esc(e.Ip) + "\",");
                    sb.Append("\"Reason\":\"" + EarthJson.Esc(e.Reason) + "\",");
                    sb.Append("\"BannedByIp\":\"" + EarthJson.Esc(e.BannedByIp) + "\",");
                    sb.Append("\"TimestampUtc\":" + e.TimestampUtc + ",");
                    sb.Append("\"Deleted\":" + (e.Deleted ? "true" : "false") + ",");
                    sb.Append("\"UpdatedUtc\":" + e.UpdatedUtc);
                    sb.Append("}");
                }
                sb.Append("\n]\n");
                File.WriteAllText(EarthSocialPaths.BansFile, sb.ToString(), Encoding.UTF8);
            }
            catch (Exception) { }
        }
    }

    public bool IsBanned(string ip)
    {
        lock (lk)
        {
            EarthBanEntry e;
            return (bans.TryGetValue(ip, out e) && !e.Deleted);
        }
    }

    public void BanIP(string ip, string reason, string byIp)
    {
        lock (lk)
        {
            EarthBanEntry e = new EarthBanEntry();
            e.Ip = ip;
            e.Reason = reason ?? "";
            e.BannedByIp = byIp ?? "";
            e.TimestampUtc = EarthTime.NowUtcMs();
            e.UpdatedUtc = e.TimestampUtc;
            e.Deleted = false;
            bans[ip] = e;
        }
        Save();
        if (Changed != null) Changed();
    }

    public void UnbanIP(string ip)
    {
        lock (lk)
        {
            EarthBanEntry e;
            if (bans.TryGetValue(ip, out e))
            {
                e.Deleted = true;
                e.UpdatedUtc = EarthTime.NowUtcMs();
            }
        }
        Save();
        if (Changed != null) Changed();
    }

    public List<EarthBanEntry> GetActive()
    {
        lock (lk)
        {
            List<EarthBanEntry> l = new List<EarthBanEntry>();
            foreach (EarthBanEntry e in bans.Values) { if (!e.Deleted) l.Add(e); }
            l.Sort((a, b) => b.TimestampUtc.CompareTo(a.TimestampUtc));
            return l;
        }
    }

    // Merge fuer Sync: Last-Write-Wins pro IP anhand UpdatedUtc.
    public bool MergeFrom(List<EarthBanEntry> incoming)
    {
        bool changed = false;
        lock (lk)
        {
            foreach (EarthBanEntry inc in incoming)
            {
                if (inc.Ip.Length == 0) continue;
                EarthBanEntry cur;
                if (!bans.TryGetValue(inc.Ip, out cur) || inc.UpdatedUtc > cur.UpdatedUtc)
                {
                    bans[inc.Ip] = inc;
                    changed = true;
                }
            }
        }
        if (changed) { Save(); if (Changed != null) Changed(); }
        return changed;
    }

    public List<EarthBanEntry> Snapshot()
    {
        lock (lk) { return new List<EarthBanEntry>(bans.Values); }
    }
}

// -----------------------------------------------------------------------------
// Wird von Chat-/Datei-/Voice-Knoten (in deren jeweiligem C#-Block dupliziert)
// konsultiert. Hier die Variante fuer den Security-Prozess selbst.
// -----------------------------------------------------------------------------
public static class EarthBanFilter
{
    private static readonly object lk = new object();
    private static HashSet<string> banned = new HashSet<string>();
    private static long lastLoad;

    public static void Refresh(bool force)
    {
        long now = Environment.TickCount;
        lock (lk)
        {
            if (!force && (now - lastLoad) < 4000) return;
            lastLoad = now;
        }
        HashSet<string> next = new HashSet<string>();
        try
        {
            if (File.Exists(EarthSocialPaths.BansFile))
            {
                string txt = File.ReadAllText(EarthSocialPaths.BansFile, Encoding.UTF8);
                foreach (Dictionary<string, string> o in EarthJson.ParseArray(txt))
                {
                    if (EarthJson.GetBool(o, "Deleted")) continue;
                    string ip = EarthJson.GetStr(o, "Ip");
                    if (ip.Length > 0) next.Add(ip);
                }
            }
        }
        catch (Exception) { }
        lock (lk) { banned = next; }
    }

    public static bool IsBanned(string ip)
    {
        Refresh(false);
        lock (lk) { return banned.Contains(ip); }
    }
}

// -----------------------------------------------------------------------------
// FriendAndChannelManager: Freunde + dauerhafte Kanaele (Metadaten). Nur der
// Owner oder ein Eintrag in GlobalAdmins darf loeschen/kicken - transparent,
// von jedem Nutzer selbst in seiner eigenen Friendlist.json einsehbar/pflegbar.
// -----------------------------------------------------------------------------
public class FriendAndChannelManager
{
    private readonly object lk = new object();
    private Dictionary<string, EarthFriendEntry> friends = new Dictionary<string, EarthFriendEntry>();
    private Dictionary<string, EarthChannelEntry> channels = new Dictionary<string, EarthChannelEntry>();
    private List<string> globalAdmins = new List<string>();
    public event Action Changed;

    public FriendAndChannelManager() { Load(); }

    public void Load()
    {
        lock (lk)
        {
            friends.Clear();
            channels.Clear();
            globalAdmins.Clear();
            try
            {
                if (File.Exists(EarthSocialPaths.FriendsFile))
                {
                    string txt = File.ReadAllText(EarthSocialPaths.FriendsFile, Encoding.UTF8);
                    int fi = txt.IndexOf("\"Friends\"");
                    int ci = txt.IndexOf("\"Channels\"");
                    int ai = txt.IndexOf("\"GlobalAdmins\"");
                    string friendsPart = (fi >= 0) ? txt.Substring(fi, (ci > fi ? ci : txt.Length) - fi) : "";
                    string chanPart = (ci >= 0) ? txt.Substring(ci, (ai > ci ? ai : txt.Length) - ci) : "";
                    string adminPart = (ai >= 0) ? txt.Substring(ai) : "";
                    foreach (Dictionary<string, string> o in EarthJson.ParseArray(friendsPart))
                    {
                        EarthFriendEntry e = new EarthFriendEntry();
                        e.Ip = EarthJson.GetStr(o, "Ip");
                        e.Name = EarthJson.GetStr(o, "Name");
                        e.Notes = EarthJson.GetStr(o, "Notes");
                        e.Deleted = EarthJson.GetBool(o, "Deleted");
                        e.UpdatedUtc = EarthJson.GetLong(o, "UpdatedUtc");
                        if (e.Ip.Length > 0) friends[e.Ip] = e;
                    }
                    foreach (Dictionary<string, string> o in EarthJson.ParseArray(chanPart))
                    {
                        EarthChannelEntry e = new EarthChannelEntry();
                        e.Id = EarthJson.GetStr(o, "Id");
                        e.Name = EarthJson.GetStr(o, "Name");
                        e.OwnerIp = EarthJson.GetStr(o, "OwnerIp");
                        e.PasswordHash = EarthJson.GetStr(o, "PasswordHash");
                        e.Salt = EarthJson.GetStr(o, "Salt");
                        e.CreatedUtc = EarthJson.GetLong(o, "CreatedUtc");
                        e.Deleted = EarthJson.GetBool(o, "Deleted");
                        e.UpdatedUtc = EarthJson.GetLong(o, "UpdatedUtc");
                        if (e.Id.Length > 0) channels[e.Id] = e;
                    }
                    foreach (Dictionary<string, string> o in EarthJson.ParseArray(adminPart))
                    {
                        string ip = EarthJson.GetStr(o, "Ip");
                        if (ip.Length > 0) globalAdmins.Add(ip);
                    }
                }
            }
            catch (Exception) { }
        }
    }

    public void Save()
    {
        lock (lk)
        {
            try
            {
                EarthSocialPaths.EnsureDir();
                StringBuilder sb = new StringBuilder();
                sb.Append("{\n  \"Friends\": [\n");
                bool first = true;
                foreach (EarthFriendEntry e in friends.Values)
                {
                    if (!first) sb.Append(",\n");
                    first = false;
                    sb.Append("    {\"Ip\":\"" + EarthJson.Esc(e.Ip) + "\",\"Name\":\"" + EarthJson.Esc(e.Name) + "\",\"Notes\":\"" + EarthJson.Esc(e.Notes) + "\",\"Deleted\":" + (e.Deleted ? "true" : "false") + ",\"UpdatedUtc\":" + e.UpdatedUtc + "}");
                }
                sb.Append("\n  ],\n  \"Channels\": [\n");
                first = true;
                foreach (EarthChannelEntry e in channels.Values)
                {
                    if (!first) sb.Append(",\n");
                    first = false;
                    sb.Append("    {\"Id\":\"" + EarthJson.Esc(e.Id) + "\",\"Name\":\"" + EarthJson.Esc(e.Name) + "\",\"OwnerIp\":\"" + EarthJson.Esc(e.OwnerIp) + "\",\"PasswordHash\":\"" + EarthJson.Esc(e.PasswordHash) + "\",\"Salt\":\"" + EarthJson.Esc(e.Salt) + "\",\"CreatedUtc\":" + e.CreatedUtc + ",\"Deleted\":" + (e.Deleted ? "true" : "false") + ",\"UpdatedUtc\":" + e.UpdatedUtc + "}");
                }
                sb.Append("\n  ],\n  \"GlobalAdmins\": [\n");
                first = true;
                foreach (string ip in globalAdmins)
                {
                    if (!first) sb.Append(",\n");
                    first = false;
                    sb.Append("    {\"Ip\":\"" + EarthJson.Esc(ip) + "\"}");
                }
                sb.Append("\n  ]\n}\n");
                File.WriteAllText(EarthSocialPaths.FriendsFile, sb.ToString(), Encoding.UTF8);
            }
            catch (Exception) { }
        }
    }

    public void AddFriend(string ip, string name, string notes)
    {
        lock (lk)
        {
            EarthFriendEntry e = new EarthFriendEntry();
            e.Ip = ip; e.Name = name ?? ""; e.Notes = notes ?? "";
            e.UpdatedUtc = EarthTime.NowUtcMs();
            friends[ip] = e;
        }
        Save();
        if (Changed != null) Changed();
    }

    public void RemoveFriend(string ip)
    {
        lock (lk)
        {
            EarthFriendEntry e;
            if (friends.TryGetValue(ip, out e)) { e.Deleted = true; e.UpdatedUtc = EarthTime.NowUtcMs(); }
        }
        Save();
        if (Changed != null) Changed();
    }

    public List<EarthFriendEntry> GetFriends()
    {
        lock (lk)
        {
            List<EarthFriendEntry> l = new List<EarthFriendEntry>();
            foreach (EarthFriendEntry e in friends.Values) { if (!e.Deleted) l.Add(e); }
            return l;
        }
    }

    public bool IsGlobalAdmin(string ip)
    {
        lock (lk) { return globalAdmins.Contains(ip); }
    }

    public void SetGlobalAdmin(string ip, bool isAdmin)
    {
        lock (lk)
        {
            globalAdmins.Remove(ip);
            if (isAdmin) globalAdmins.Add(ip);
        }
        Save();
        if (Changed != null) Changed();
    }

    public List<string> GetGlobalAdmins()
    {
        lock (lk) { return new List<string>(globalAdmins); }
    }

    private static string HashPassword(string password, string saltB64)
    {
        byte[] salt = Convert.FromBase64String(saltB64);
        using (Rfc2898DeriveBytes kdf = new Rfc2898DeriveBytes(password ?? "", salt, 20000))
        {
            return Convert.ToBase64String(kdf.GetBytes(32));
        }
    }

    public string CreateChannel(string name, string ownerIp, string password)
    {
        string id = Guid.NewGuid().ToString("N").Substring(0, 12);
        byte[] saltBytes = new byte[16];
        using (RNGCryptoServiceProvider rng = new RNGCryptoServiceProvider()) { rng.GetBytes(saltBytes); }
        string salt = Convert.ToBase64String(saltBytes);
        EarthChannelEntry e = new EarthChannelEntry();
        e.Id = id; e.Name = name; e.OwnerIp = ownerIp;
        e.Salt = salt;
        e.PasswordHash = string.IsNullOrEmpty(password) ? "" : HashPassword(password, salt);
        e.CreatedUtc = EarthTime.NowUtcMs();
        e.UpdatedUtc = e.CreatedUtc;
        lock (lk) { channels[id] = e; }
        Save();
        if (Changed != null) Changed();
        return id;
    }

    // Nur Owner oder globaler Admin darf loeschen - transparent, kein Bypass-Code.
    public string DeleteChannel(string id, string requesterIp)
    {
        EarthChannelEntry e;
        lock (lk) { channels.TryGetValue(id, out e); }
        if (e == null || e.Deleted) return "Kanal nicht gefunden.";
        bool allowed = (e.OwnerIp == requesterIp) || IsGlobalAdmin(requesterIp);
        if (!allowed) return "Nur der Ersteller (" + e.OwnerIp + ") oder ein globaler Admin darf diesen Kanal löschen.";
        lock (lk) { e.Deleted = true; e.UpdatedUtc = EarthTime.NowUtcMs(); }
        Save();
        if (Changed != null) Changed();
        return null;
    }

    public bool CheckChannelPassword(string id, string password)
    {
        EarthChannelEntry e;
        lock (lk) { channels.TryGetValue(id, out e); }
        if (e == null) return false;
        if (string.IsNullOrEmpty(e.PasswordHash)) return true;
        try { return HashPassword(password, e.Salt) == e.PasswordHash; } catch (Exception) { return false; }
    }

    public List<EarthChannelEntry> GetChannels()
    {
        lock (lk)
        {
            List<EarthChannelEntry> l = new List<EarthChannelEntry>();
            foreach (EarthChannelEntry e in channels.Values) { if (!e.Deleted) l.Add(e); }
            l.Sort((a, b) => a.Name.CompareToOrdinal(b.Name));
            return l;
        }
    }

    public bool MergeFrom(List<EarthFriendEntry> incFriends, List<EarthChannelEntry> incChannels)
    {
        bool changed = false;
        lock (lk)
        {
            foreach (EarthFriendEntry inc in incFriends)
            {
                if (inc.Ip.Length == 0) continue;
                EarthFriendEntry cur;
                if (!friends.TryGetValue(inc.Ip, out cur) || inc.UpdatedUtc > cur.UpdatedUtc) { friends[inc.Ip] = inc; changed = true; }
            }
            foreach (EarthChannelEntry inc in incChannels)
            {
                if (inc.Id.Length == 0) continue;
                EarthChannelEntry cur;
                if (!channels.TryGetValue(inc.Id, out cur) || inc.UpdatedUtc > cur.UpdatedUtc) { channels[inc.Id] = inc; changed = true; }
            }
        }
        if (changed) { Save(); if (Changed != null) Changed(); }
        return changed;
    }

    public List<EarthFriendEntry> SnapshotFriends() { lock (lk) { return new List<EarthFriendEntry>(friends.Values); } }
    public List<EarthChannelEntry> SnapshotChannels() { lock (lk) { return new List<EarthChannelEntry>(channels.Values); } }
}

internal static class EarthStrExt
{
    public static int CompareToOrdinal(this string a, string b) { return string.CompareOrdinal(a, b); }
}

// -----------------------------------------------------------------------------
// PokeManager: Cooldown pro Peer, Sperre bei Bann/DND, UI-Ereignis fuer Popup+Sound.
// -----------------------------------------------------------------------------
public class PokeManager
{
    public ConcurrentQueue<string> Events = new ConcurrentQueue<string>();
    public volatile bool DoNotDisturb;
    private readonly Dictionary<string, long> lastSentTo = new Dictionary<string, long>();
    private readonly object lk = new object();
    private const long CooldownMs = 5000;

    public string TryPoke(string peerId, string peerName)
    {
        long now = EarthTime.NowUtcMs();
        lock (lk)
        {
            long last;
            if (lastSentTo.TryGetValue(peerId, out last) && (now - last) < CooldownMs)
            {
                long waitS = (CooldownMs - (now - last) + 999) / 1000;
                return "Bitte warte noch " + waitS + " Sekunde(n), bevor du " + peerName + " erneut anstupst.";
            }
            lastSentTo[peerId] = now;
        }
        return null;
    }

    public void OnPokeReceived(string fromName, bool senderBanned)
    {
        if (senderBanned) return;
        if (DoNotDisturb)
        {
            Events.Enqueue("BLOCKED|" + fromName);
            return;
        }
        Events.Enqueue("POKE|" + fromName);
    }
}

// -----------------------------------------------------------------------------
// Sync-Knoten: UDP-Beacon zur Erkennung + TCP-Vollabgleich auf Port 9776.
// Traegt zugleich die Poke-Nachrichten (kleines, eigenstaendiges Protokoll).
// -----------------------------------------------------------------------------
public class EarthSocialPeer
{
    public string Id = "";
    public string Name = "";
    public string Ip = "";
    public int LastSeen;
}

public class EarthSocialNode
{
    public const int PortNumber = 9776;
    public string NodeId;
    public string NodeName;
    public string BindIp;
    public string Mask = "";
    public ConcurrentQueue<string> Events = new ConcurrentQueue<string>();
    public BanManager Bans;
    public FriendAndChannelManager Social;
    public PokeManager Pokes;

    private TcpListener listener;
    private UdpClient beaconRx;
    private volatile bool running;
    private readonly object peerLock = new object();
    private Dictionary<string, EarthSocialPeer> peers = new Dictionary<string, EarthSocialPeer>();
    private readonly Dictionary<string, long> pingSentAt = new Dictionary<string, long>();
    public ConcurrentDictionary<string, int> Latencies = new ConcurrentDictionary<string, int>();

    public EarthSocialNode(string bindIp, string name, BanManager bans, FriendAndChannelManager social, PokeManager pokes)
    {
        BindIp = bindIp;
        NodeName = CleanName(name);
        NodeId = Guid.NewGuid().ToString("N").Substring(0, 12);
        Bans = bans;
        Social = social;
        Pokes = pokes;
    }

    private static string CleanName(string s)
    {
        if (s == null) return "";
        s = s.Replace("\r", " ").Replace("\n", " ").Replace("|", "/").Trim();
        if (s.Length > 40) s = s.Substring(0, 40);
        return s;
    }

    public string Start()
    {
        try
        {
            listener = new TcpListener(IPAddress.Parse(BindIp), PortNumber);
            listener.Start();
        }
        catch (Exception ex) { return "Port 9776 konnte nicht geoeffnet werden: " + ex.Message; }
        running = true;
        try
        {
            beaconRx = new UdpClient(AddressFamily.InterNetwork);
            beaconRx.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
            beaconRx.Client.Bind(new IPEndPoint(IPAddress.Any, PortNumber));
            try { beaconRx.Client.IOControl((IOControlCode)(-1744830452), new byte[] { 0, 0, 0, 0 }, null); } catch (Exception) { }
            Thread rt = new Thread(BeaconRxLoop); rt.IsBackground = true; rt.Start();
        }
        catch (Exception) { beaconRx = null; }
        Thread ta = new Thread(AcceptLoop); ta.IsBackground = true; ta.Start();
        Thread tb = new Thread(BeaconTxLoop); tb.IsBackground = true; tb.Start();
        Thread tp = new Thread(PingLoop); tp.IsBackground = true; tp.Start();
        return null;
    }

    public void Stop()
    {
        running = false;
        try { if (listener != null) listener.Stop(); } catch (Exception) { }
        try { if (beaconRx != null) beaconRx.Close(); } catch (Exception) { }
    }

    private void BeaconRxLoop()
    {
        IPEndPoint ep = new IPEndPoint(IPAddress.Any, 0);
        while (running)
        {
            byte[] d;
            try { d = beaconRx.Receive(ref ep); }
            catch (Exception) { if (!running) break; Thread.Sleep(50); continue; }
            try
            {
                string ip = ep.Address.ToString();
                if (Bans.IsBanned(ip)) continue;
                string txt = Encoding.UTF8.GetString(d);
                if (txt.StartsWith("PESOC1B|"))
                {
                    string[] f = txt.Split('|');
                    if (f.Length < 3 || f[1] == NodeId) continue;
                    UpsertPeer(f[1], CleanName(f[2]), ip);
                    RequestSync(ip);
                }
                else if (txt.StartsWith("PING|"))
                {
                    byte[] pong = Encoding.UTF8.GetBytes("PONG|" + txt.Substring(5));
                    beaconRx.Send(pong, pong.Length, ep);
                }
                else if (txt.StartsWith("PONG|"))
                {
                    string tok = txt.Substring(5);
                    long sent;
                    lock (peerLock) { pingSentAt.TryGetValue(ip + "|" + tok, out sent); pingSentAt.Remove(ip + "|" + tok); }
                    if (sent > 0)
                    {
                        int ms = (int)(EarthTime.NowUtcMs() - sent);
                        Latencies[ip] = ms;
                    }
                }
                else if (txt.StartsWith("POKE|"))
                {
                    string[] f = txt.Split('|');
                    if (f.Length >= 3 && f[1] != NodeId) Pokes.OnPokeReceived(CleanName(f[2]), false);
                }
            }
            catch (Exception) { }
        }
    }

    private void BeaconTxLoop()
    {
        UdpClient tx = null;
        IPEndPoint bc1 = new IPEndPoint(IPAddress.Broadcast, PortNumber);
        IPEndPoint bc2 = null;
        try
        {
            tx = new UdpClient(new IPEndPoint(IPAddress.Parse(BindIp), 0));
            tx.EnableBroadcast = true;
            if (!string.IsNullOrEmpty(Mask))
            {
                byte[] ib = IPAddress.Parse(BindIp).GetAddressBytes();
                byte[] mb = IPAddress.Parse(Mask).GetAddressBytes();
                byte[] bb = new byte[4];
                for (int i = 0; i < 4; i++) bb[i] = (byte)(ib[i] | (byte)~mb[i]);
                bc2 = new IPEndPoint(new IPAddress(bb), PortNumber);
            }
        }
        catch (Exception) { return; }
        while (running)
        {
            try
            {
                byte[] msg = Encoding.UTF8.GetBytes("PESOC1B|" + NodeId + "|" + NodeName);
                tx.Send(msg, msg.Length, bc1);
                if (bc2 != null) tx.Send(msg, msg.Length, bc2);
            }
            catch (Exception) { }
            for (int i = 0; i < 50 && running; i++) Thread.Sleep(100);
        }
        try { tx.Close(); } catch (Exception) { }
    }

    private void PingLoop()
    {
        UdpClient tx = null;
        try { tx = new UdpClient(new IPEndPoint(IPAddress.Parse(BindIp), 0)); } catch (Exception) { return; }
        while (running)
        {
            List<EarthSocialPeer> list = SnapshotPeers();
            foreach (EarthSocialPeer p in list)
            {
                try
                {
                    string tok = Guid.NewGuid().ToString("N").Substring(0, 8);
                    lock (peerLock) { pingSentAt[p.Ip + "|" + tok] = EarthTime.NowUtcMs(); }
                    byte[] msg = Encoding.UTF8.GetBytes("PING|" + tok);
                    tx.Send(msg, msg.Length, new IPEndPoint(IPAddress.Parse(p.Ip), PortNumber));
                }
                catch (Exception) { }
            }
            for (int i = 0; i < 30 && running; i++) Thread.Sleep(100);
        }
        try { tx.Close(); } catch (Exception) { }
    }

    private void UpsertPeer(string id, string name, string ip)
    {
        bool isNew = false;
        lock (peerLock)
        {
            EarthSocialPeer p;
            if (!peers.TryGetValue(id, out p)) { p = new EarthSocialPeer(); p.Id = id; peers[id] = p; isNew = true; }
            p.Name = name; p.Ip = ip; p.LastSeen = Environment.TickCount;
        }
        if (isNew) Events.Enqueue("SYS|Teilnehmer gefunden: " + name + " (" + ip + ")");
        PrunePeers();
    }

    private void PrunePeers()
    {
        int now = Environment.TickCount;
        lock (peerLock)
        {
            List<string> dead = new List<string>();
            foreach (KeyValuePair<string, EarthSocialPeer> kv in peers) { if ((now - kv.Value.LastSeen) > 15000) dead.Add(kv.Key); }
            foreach (string d in dead) peers.Remove(d);
        }
    }

    public List<EarthSocialPeer> SnapshotPeers()
    {
        lock (peerLock) { return new List<EarthSocialPeer>(peers.Values); }
    }

    public string[] GetPeers()
    {
        List<string> l = new List<string>();
        foreach (EarthSocialPeer p in SnapshotPeers())
        {
            int lat;
            string latS = Latencies.TryGetValue(p.Ip, out lat) ? lat.ToString() : "-";
            l.Add(p.Id + "|" + p.Name + "|" + p.Ip + "|" + latS);
        }
        return l.ToArray();
    }

    private void AcceptLoop()
    {
        while (running)
        {
            try
            {
                TcpClient c = listener.AcceptTcpClient();
                Thread t = new Thread(() => HandleConn(c)); t.IsBackground = true; t.Start();
            }
            catch (Exception) { if (!running) break; Thread.Sleep(50); }
        }
    }

    private static void WriteLine(NetworkStream ns, string t)
    {
        byte[] b = Encoding.UTF8.GetBytes(t + "\n");
        ns.Write(b, 0, b.Length);
    }

    private static string ReadLine(NetworkStream ns)
    {
        MemoryStream ms = new MemoryStream();
        int b;
        while ((b = ns.ReadByte()) >= 0)
        {
            if (b == 10) break;
            if (b != 13) ms.WriteByte((byte)b);
            if (ms.Length > 4000000) break;
        }
        if (ms.Length == 0 && b < 0) return null;
        return Encoding.UTF8.GetString(ms.ToArray());
    }

    private void HandleConn(TcpClient c)
    {
        try
        {
            string ip = ((IPEndPoint)c.Client.RemoteEndPoint).Address.ToString();
            if (Bans.IsBanned(ip)) return;
            c.ReceiveTimeout = 15000;
            c.SendTimeout = 15000;
            NetworkStream ns = c.GetStream();
            string line = ReadLine(ns);
            if (line == null || !line.StartsWith("SYNC1|")) return;
            SendSnapshot(ns);
            string body = ReadAll(ns);
            ApplyIncoming(body);
        }
        catch (Exception) { }
        finally { try { c.Close(); } catch (Exception) { } }
    }

    private static string ReadAll(NetworkStream ns)
    {
        MemoryStream ms = new MemoryStream();
        byte[] buf = new byte[65536];
        try
        {
            while (true)
            {
                int n = ns.Read(buf, 0, buf.Length);
                if (n <= 0) break;
                ms.Write(buf, 0, n);
                if (ns.DataAvailable == false) break;
            }
        }
        catch (Exception) { }
        return Encoding.UTF8.GetString(ms.ToArray());
    }

    private void SendSnapshot(NetworkStream ns)
    {
        // Nur die dauerhaften Kanaele werden netzwerkweit abgeglichen. Freundes- und
        // Bannliste sind PERSOENLICH (Option 11) und verlassen den eigenen PC nicht - die
        // leeren Abschnitte bleiben nur fuer aeltere Versionen im Protokoll.
        StringBuilder sb = new StringBuilder();
        sb.Append("BANS\n");
        sb.Append("FRIENDS\n");
        sb.Append("CHANNELS\n");
        foreach (EarthChannelEntry e in Social.SnapshotChannels())
            sb.Append(e.Id + "\t" + e.Name.Replace("\t", " ") + "\t" + e.OwnerIp + "\t" + e.PasswordHash + "\t" + e.Salt + "\t" + e.CreatedUtc + "\t" + (e.Deleted ? 1 : 0) + "\t" + e.UpdatedUtc + "\n");
        sb.Append("END\n");
        byte[] b = Encoding.UTF8.GetBytes(sb.ToString());
        ns.Write(b, 0, b.Length);
    }

    private void ApplyIncoming(string body)
    {
        string[] lines = body.Split('\n');
        string section = "";
        List<EarthBanEntry> incBans = new List<EarthBanEntry>();
        List<EarthFriendEntry> incFriends = new List<EarthFriendEntry>();
        List<EarthChannelEntry> incChannels = new List<EarthChannelEntry>();
        foreach (string raw in lines)
        {
            string l = raw.TrimEnd('\r');
            if (l == "BANS" || l == "FRIENDS" || l == "CHANNELS" || l == "END") { section = l; continue; }
            if (l.Length == 0) continue;
            string[] f = l.Split('\t');
            try
            {
                if (section == "BANS" && f.Length >= 6)
                {
                    EarthBanEntry e = new EarthBanEntry();
                    e.Ip = f[0]; e.Reason = f[1]; e.BannedByIp = f[2];
                    e.TimestampUtc = long.Parse(f[3]); e.Deleted = f[4] == "1"; e.UpdatedUtc = long.Parse(f[5]);
                    incBans.Add(e);
                }
                else if (section == "FRIENDS" && f.Length >= 5)
                {
                    EarthFriendEntry e = new EarthFriendEntry();
                    e.Ip = f[0]; e.Name = f[1]; e.Notes = f[2]; e.Deleted = f[3] == "1"; e.UpdatedUtc = long.Parse(f[4]);
                    incFriends.Add(e);
                }
                else if (section == "CHANNELS" && f.Length >= 8)
                {
                    EarthChannelEntry e = new EarthChannelEntry();
                    e.Id = f[0]; e.Name = f[1]; e.OwnerIp = f[2]; e.PasswordHash = f[3]; e.Salt = f[4];
                    e.CreatedUtc = long.Parse(f[5]); e.Deleted = f[6] == "1"; e.UpdatedUtc = long.Parse(f[7]);
                    incChannels.Add(e);
                }
            }
            catch (Exception) { }
        }
        // Fremde Freundes-/Bannlisten (von aelteren Versionen noch mitgeschickt) werden
        // bewusst ignoriert - sonst koennte jeder im Netz die eigene Liste veraendern.
        incBans.Clear();
        incFriends.Clear();
        bool c2 = Social.MergeFrom(incFriends, incChannels);
        if (c2) Events.Enqueue("SYS|Kanal-Abgleich empfangen und übernommen.");
    }

    public void RequestSync(string ip)
    {
        Thread t = new Thread(() =>
        {
            try
            {
                if (Bans.IsBanned(ip)) return;
                using (TcpClient c = new TcpClient())
                {
                    IAsyncResult ar = c.BeginConnect(IPAddress.Parse(ip), PortNumber, null, null);
                    if (!ar.AsyncWaitHandle.WaitOne(2500)) return;
                    c.EndConnect(ar);
                    c.ReceiveTimeout = 15000;
                    c.SendTimeout = 15000;
                    NetworkStream ns = c.GetStream();
                    WriteLine(ns, "SYNC1|" + NodeId);
                    string body = ReadUntilEnd(ns);
                    ApplyIncoming(body);
                    SendSnapshot(ns);
                }
            }
            catch (Exception) { }
        });
        t.IsBackground = true;
        t.Start();
    }

    private static string ReadUntilEnd(NetworkStream ns)
    {
        MemoryStream ms = new MemoryStream();
        byte[] one = new byte[1];
        while (true)
        {
            int n = ns.Read(one, 0, 1);
            if (n <= 0) break;
            ms.WriteByte(one[0]);
            if (one[0] == 10)
            {
                if (ms.Length >= 4)
                {
                    byte[] arr = ms.ToArray();
                    string s = Encoding.UTF8.GetString(arr, Math.Max(0, arr.Length - 5), Math.Min(5, arr.Length));
                    if (s.Contains("END\n")) break;
                }
            }
            if (ms.Length > 8000000) break;
        }
        return Encoding.UTF8.GetString(ms.ToArray());
    }

    public void SendPoke(string peerIp, string myName)
    {
        try
        {
            using (UdpClient tx = new UdpClient(new IPEndPoint(IPAddress.Parse(BindIp), 0)))
            {
                byte[] msg = Encoding.UTF8.GetBytes("POKE|" + NodeId + "|" + CleanName(myName));
                tx.Send(msg, msg.Length, new IPEndPoint(IPAddress.Parse(peerIp), PortNumber));
            }
        }
        catch (Exception) { }
    }

    public void TriggerSync()
    {
        foreach (EarthSocialPeer p in SnapshotPeers()) RequestSync(p.Ip);
    }
}
'@
        Add-Type -TypeDefinition $socialCode -Language CSharp
    }
}


# ------------------------------------------------------------------------------
# OPTION 11 - FREUNDESLISTE, BANNLISTE & POSTFACH
# ------------------------------------------------------------------------------
# Freundes- und Bannliste sind dieselben Dateien wie in der Kommunikationszentrale
# (C:\Project-Earth-Lan\Friendlist.json / ip_bans.json) und bleiben auf dem eigenen PC.
# Das Postfach nutzt den Postfach-Dienst (siehe "POSTFACH" weiter oben): läuft das
# Control Center, arbeitet der Dienst dort; ist es geschlossen, übernimmt dieses Fenster.
function Invoke-FriendsBansMailbox {
    Initialize-SocialTypes
    Initialize-PelMailTypes
    $o11Bans = New-Object BanManager
    $o11Social = New-Object FriendAndChannelManager
    [void](Start-PelMailService)

    $cBack   = [System.Drawing.Color]::FromArgb(25, 25, 25)
    $cBtn    = [System.Drawing.Color]::FromArgb(45, 45, 45)
    $cAccent = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $cList   = [System.Drawing.Color]::FromArgb(20, 20, 20)
    $cInput  = [System.Drawing.Color]::FromArgb(35, 35, 35)
    $cWhite  = [System.Drawing.Color]::White
    $cGray   = [System.Drawing.Color]::LightGray
    $fontMain = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Regular)
    $fontBold = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

    # Veränderlicher Zustand immer in dieser Hashtable - Ereignis-Handler können Variablen
    # der Funktion lesen, aber nicht neu zuweisen.
    $o = @{
        Folder = 'in'; MailSig = ''; OnlineSig = ''; SocialStamp = ''; Tick = 0
        Online = @{}; NewCount = 0; LastSel = ''
    }

    function Set-O11Anchor($ctrl, [string[]]$sides) {
        $v = [System.Windows.Forms.AnchorStyles]::None
        foreach ($s in $sides) { $v = $v -bor [System.Windows.Forms.AnchorStyles]::$s }
        $ctrl.Anchor = $v
    }
    function New-O11Button([string]$text, [int]$x, [int]$y, [int]$w, [int]$h, [bool]$accent = $false) {
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $text
        $b.Location = New-Object System.Drawing.Point($x, $y)
        $b.Size = New-Object System.Drawing.Size($w, $h)
        $b.FlatStyle = 'Flat'
        $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
        $b.ForeColor = $cWhite
        $b.Font = $fontBold
        if ($accent) { $b.BackColor = $cAccent } else { $b.BackColor = $cBtn }
        return $b
    }
    function New-O11Label([string]$text, [int]$x, [int]$y, [int]$w, [int]$h) {
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $text
        $l.Location = New-Object System.Drawing.Point($x, $y)
        $l.Size = New-Object System.Drawing.Size($w, $h)
        $l.ForeColor = $cWhite
        $l.Font = $fontMain
        return $l
    }
    function New-O11List([int]$x, [int]$y, [int]$w, [int]$h, [string[]]$cols, [int[]]$widths) {
        $lv = New-Object System.Windows.Forms.ListView
        $lv.Location = New-Object System.Drawing.Point($x, $y)
        $lv.Size = New-Object System.Drawing.Size($w, $h)
        $lv.View = 'Details'
        $lv.FullRowSelect = $true
        $lv.HideSelection = $false
        $lv.MultiSelect = $false
        $lv.BackColor = $cList
        $lv.ForeColor = $cWhite
        $lv.Font = $fontMain
        for ($i = 0; $i -lt $cols.Count; $i++) { [void]$lv.Columns.Add($cols[$i], $widths[$i]) }
        return $lv
    }
    function Show-O11Msg([string]$text, $icon = [System.Windows.Forms.MessageBoxIcon]::Information) {
        [void][System.Windows.Forms.MessageBox]::Show($form, $text, 'Project Earth LAN', [System.Windows.Forms.MessageBoxButtons]::OK, $icon)
    }
    function Confirm-O11([string]$text) {
        return ([System.Windows.Forms.MessageBox]::Show($form, $text, 'Project Earth LAN', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question) -eq [System.Windows.Forms.DialogResult]::Yes)
    }
    function Test-O11Ip([string]$ip) { return [EarthMailStore]::IsValidIp(([string]$ip).Trim()) }

    # ---- Kleiner Eingabedialog mit mehreren Feldern ---------------------------------------
    # $fields: @( @{ Label; Value; Multi; Max } ... ) -> Array der eingegebenen Texte oder $null
    function Show-O11InputDialog([string]$title, [string]$hint, $fields, [string]$okText = 'OK') {
        $d = New-Object System.Windows.Forms.Form
        $d.Text = $title
        $d.StartPosition = 'CenterParent'
        $d.FormBorderStyle = 'FixedDialog'
        $d.MaximizeBox = $false
        $d.MinimizeBox = $false
        $d.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
        $d.ForeColor = $cWhite
        $y = 12
        if ($hint) {
            $lh = New-O11Label $hint 14 $y 440 40
            $lh.ForeColor = $cGray
            $d.Controls.Add($lh)
            $y += 46
        }
        $boxes = @()
        foreach ($fd in $fields) {
            $d.Controls.Add((New-O11Label $fd.Label 14 $y 440 20))
            $y += 22
            $tb = New-Object System.Windows.Forms.TextBox
            $tb.Location = New-Object System.Drawing.Point(14, $y)
            $tb.BackColor = $cInput
            $tb.ForeColor = $cWhite
            $tb.Font = $fontMain
            if ($fd.Max) { $tb.MaxLength = [int]$fd.Max }
            if ($fd.Multi) {
                $tb.Multiline = $true
                $tb.ScrollBars = 'Vertical'
                $tb.AcceptsReturn = $true
                $tb.Size = New-Object System.Drawing.Size(440, 90)
                $y += 96
            } else {
                $tb.Size = New-Object System.Drawing.Size(440, 26)
                $y += 32
            }
            $tb.Text = [string]$fd.Value
            $d.Controls.Add($tb)
            $boxes += $tb
        }
        $ok = New-O11Button $okText 214 ($y + 6) 120 32 $true
        $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $cancel = New-O11Button 'Abbrechen' 340 ($y + 6) 114 32
        $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $d.Controls.AddRange(@($ok, $cancel))
        $d.AcceptButton = $ok
        $d.CancelButton = $cancel
        $d.ClientSize = New-Object System.Drawing.Size(470, ($y + 50))
        $res = $d.ShowDialog($form)
        $vals = @($boxes | ForEach-Object { $_.Text })
        $d.Dispose()
        if ($res -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
        return ,$vals
    }

    # ===================================================================================
    # Fenster
    # ===================================================================================
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Project Earth LAN - Freundesliste, Bannliste & Postfach'
    $form.Size = New-Object System.Drawing.Size(980, 700)
    $form.MinimumSize = New-Object System.Drawing.Size(900, 640)
    $form.StartPosition = 'CenterScreen'
    $form.BackColor = $cBack
    $form.ForeColor = $cWhite

    $navMail    = New-O11Button 'Postfach' 12 12 200 36 $true
    $navFriends = New-O11Button 'Freundesliste' 220 12 200 36
    $navBans    = New-O11Button 'Bannliste' 428 12 200 36
    $lblSvc = New-O11Label '' 640 20 312 22
    $lblSvc.ForeColor = $cGray
    $lblSvc.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
    Set-O11Anchor $lblSvc @('Top','Right')

    $pMail = New-Object System.Windows.Forms.Panel
    $pFriends = New-Object System.Windows.Forms.Panel
    $pBans = New-Object System.Windows.Forms.Panel
    foreach ($pp in @($pMail, $pFriends, $pBans)) {
        $pp.Location = New-Object System.Drawing.Point(12, 58)
        $pp.Size = New-Object System.Drawing.Size(940, 590)
        $pp.BackColor = $cBack
        Set-O11Anchor $pp @('Top','Left','Right','Bottom')
    }
    $pFriends.Visible = $false
    $pBans.Visible = $false

    # Rechte Button-Spalte (einheitliche Größe) wie im Voice-Chat
    $colX = 700; $colW = 240; $btnH = 34; $step = 40
    $leftW = $colX - 12

    # ---- Postfach ------------------------------------------------------------------------
    $fldIn   = New-O11Button 'Eingang' 0 0 170 30 $true
    $fldOut  = New-O11Button 'Ausgang' 176 0 170 30
    $fldSent = New-O11Button 'Gesendet' 352 0 170 30
    $lvMail = New-O11List 0 38 $leftW 250 @('Von', 'Betreff', 'Datum', 'Status') @(180, 250, 120, 120)
    $rtbRead = New-Object System.Windows.Forms.RichTextBox
    $rtbRead.Location = New-Object System.Drawing.Point(0, 296)
    $rtbRead.Size = New-Object System.Drawing.Size($leftW, 294)
    $rtbRead.ReadOnly = $true
    $rtbRead.BackColor = $cList
    $rtbRead.ForeColor = $cWhite
    $rtbRead.BorderStyle = 'FixedSingle'
    $rtbRead.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Regular)
    $rtbRead.DetectUrls = $true
    $btnNew     = New-O11Button 'Neue Nachricht' $colX (0 * $step) $colW $btnH $true
    $btnReply   = New-O11Button 'Antworten' $colX (1 * $step) $colW $btnH
    $btnDelMail = New-O11Button 'Löschen' $colX (2 * $step) $colW $btnH
    $btnUnread  = New-O11Button 'Als ungelesen markieren' $colX (3 * $step) $colW $btnH
    $btnSndFr   = New-O11Button 'Absender als Freund' $colX (4 * $step) $colW $btnH
    $btnSndBan  = New-O11Button 'Absender bannen' $colX (5 * $step) $colW $btnH
    $btnMailDir = New-O11Button 'Postfach-Ordner öffnen' $colX (6 * $step) $colW $btnH
    $lblMailInfo = New-O11Label ("So kommen Nachrichten an:`n`n" +
        "• Empfänger online: sofort (live).`n`n" +
        "• Empfänger offline: Die Nachricht wartet im Ausgang und geht automatisch raus, sobald er online ist.`n`n" +
        "• Bis zu 3 laufende Manager halten zusätzlich eine verschlüsselte Kopie bereit - so kommt sie auch an, wenn du dann offline bist. Lesen kann sie nur der Empfänger.`n`n" +
        "Tipp: Autostart (Button 12) hält das Postfach immer empfangsbereit.") $colX (7 * $step + 6) $colW 300
    $lblMailInfo.ForeColor = $cGray
    $pMail.Controls.AddRange(@($fldIn, $fldOut, $fldSent, $lvMail, $rtbRead, $btnNew, $btnReply, $btnDelMail, $btnUnread, $btnSndFr, $btnSndBan, $btnMailDir, $lblMailInfo))
    Set-O11Anchor $lvMail @('Top','Left','Right')
    Set-O11Anchor $rtbRead @('Top','Left','Right','Bottom')
    foreach ($cr in @($btnNew, $btnReply, $btnDelMail, $btnUnread, $btnSndFr, $btnSndBan, $btnMailDir, $lblMailInfo)) { Set-O11Anchor $cr @('Top','Right') }

    # ---- Freundesliste -------------------------------------------------------------------
    $lblFr = New-O11Label 'Deine Freundesliste (Doppelklick = bearbeiten):' 0 0 $leftW 20
    $lvFriends = New-O11List 0 22 $leftW 290 @('Name', 'IP-Adresse', 'Notiz', 'Status') @(180, 130, 250, 110)
    $lblOn = New-O11Label 'Gerade im Netzwerk (andere laufende Manager, Doppelklick = als Freund hinzufügen):' 0 322 $leftW 20
    $lvOnline = New-O11List 0 344 $leftW 246 @('Name', 'IP-Adresse', 'Freund?') @(260, 160, 250)
    $btnFrAdd   = New-O11Button 'Freund hinzufügen' $colX (0 * $step) $colW $btnH $true
    $btnFrEdit  = New-O11Button 'Bearbeiten' $colX (1 * $step) $colW $btnH
    $btnFrDel   = New-O11Button 'Entfernen' $colX (2 * $step) $colW $btnH
    $btnFrMsg   = New-O11Button 'Nachricht schreiben' $colX (3 * $step) $colW $btnH
    $btnFrCopy  = New-O11Button 'IP kopieren' $colX (4 * $step) $colW $btnH
    $btnFrBan   = New-O11Button 'Bannen' $colX (5 * $step) $colW $btnH
    $btnOnAdd   = New-O11Button 'Online-Spieler als Freund' $colX 344 $colW $btnH
    $btnOnMsg   = New-O11Button 'Online-Spieler anschreiben' $colX (344 + $step) $colW $btnH
    $lblFrInfo = New-O11Label ("Die Freundesliste gehört nur dir und wird nicht mit anderen abgeglichen. Option 10 ('Nur Freunde') und der Live-Status nutzen dieselbe Liste.") $colX (6 * $step + 6) $colW 88
    $lblFrInfo.ForeColor = $cGray
    $pFriends.Controls.AddRange(@($lblFr, $lvFriends, $lblOn, $lvOnline, $btnFrAdd, $btnFrEdit, $btnFrDel, $btnFrMsg, $btnFrCopy, $btnFrBan, $btnOnAdd, $btnOnMsg, $lblFrInfo))
    Set-O11Anchor $lblFr @('Top','Left','Right')
    Set-O11Anchor $lvFriends @('Top','Left','Right')
    Set-O11Anchor $lblOn @('Top','Left','Right')
    Set-O11Anchor $lvOnline @('Top','Left','Right','Bottom')
    foreach ($cr in @($btnFrAdd, $btnFrEdit, $btnFrDel, $btnFrMsg, $btnFrCopy, $btnFrBan, $btnOnAdd, $btnOnMsg, $lblFrInfo)) { Set-O11Anchor $cr @('Top','Right') }

    # ---- Bannliste -----------------------------------------------------------------------
    $lblBn = New-O11Label 'Gebannte IP-Adressen:' 0 0 $leftW 20
    $lvBans = New-O11List 0 22 $leftW 568 @('IP-Adresse', 'Grund', 'Gebannt am', 'Gebannt von') @(140, 300, 130, 120)
    $btnBnAdd  = New-O11Button 'IP bannen' $colX (0 * $step) $colW $btnH $true
    $btnBnDel  = New-O11Button 'Entbannen' $colX (1 * $step) $colW $btnH
    $btnBnEdit = New-O11Button 'Grund ändern' $colX (2 * $step) $colW $btnH
    $lblBnInfo = New-O11Label ("Von gebannten IP-Adressen nimmt dein Manager nichts mehr an: Chat, Voice, Dateiübertragung, Kanal-Abgleich und Postfach ignorieren sie.`n`nDie Bannliste gehört nur dir - sie wird nicht an andere weitergegeben.") $colX (3 * $step + 6) $colW 160
    $lblBnInfo.ForeColor = $cGray
    $pBans.Controls.AddRange(@($lblBn, $lvBans, $btnBnAdd, $btnBnDel, $btnBnEdit, $lblBnInfo))
    Set-O11Anchor $lvBans @('Top','Left','Right','Bottom')
    foreach ($cr in @($btnBnAdd, $btnBnDel, $btnBnEdit, $lblBnInfo)) { Set-O11Anchor $cr @('Top','Right') }

    $form.Controls.AddRange(@($navMail, $navFriends, $navBans, $lblSvc, $pMail, $pFriends, $pBans))

    # ===================================================================================
    # Daten -> Listen
    # ===================================================================================
    function Get-O11FriendMap {
        $m = @{}
        foreach ($fr in @($o11Social.GetFriends())) { $m[[string]$fr.Ip] = $fr }
        return $m
    }

    function Get-O11MailDir {
        switch ($o.Folder) { 'out' { return [EarthMailStore]::Outbox } 'sent' { return [EarthMailStore]::Sent } default { return [EarthMailStore]::Inbox } }
    }

    function Get-O11SelectedMail {
        if ($lvMail.SelectedItems.Count -eq 0) { return $null }
        return $lvMail.SelectedItems[0].Tag
    }

    function Update-O11FolderButtons {
        $unread = [EarthMailStore]::CountUnread()
        $nOut = [EarthMailStore]::CountFiles([EarthMailStore]::Outbox)
        $nSent = [EarthMailStore]::CountFiles([EarthMailStore]::Sent)
        $fldIn.Text = if ($unread -gt 0) { "Eingang ($unread neu)" } else { 'Eingang' }
        $fldOut.Text = if ($nOut -gt 0) { "Ausgang ($nOut wartet)" } else { 'Ausgang' }
        $fldSent.Text = "Gesendet ($nSent)"
        $fldIn.BackColor = if ($o.Folder -eq 'in') { $cAccent } else { $cBtn }
        $fldOut.BackColor = if ($o.Folder -eq 'out') { $cAccent } else { $cBtn }
        $fldSent.BackColor = if ($o.Folder -eq 'sent') { $cAccent } else { $cBtn }
        $navMail.Text = if ($unread -gt 0) { "Postfach ($unread neu)" } else { 'Postfach' }
        $form.Text = if ($unread -gt 0) { "($unread neu) Project Earth LAN - Freundesliste, Bannliste & Postfach" } else { 'Project Earth LAN - Freundesliste, Bannliste & Postfach' }
        $btnReply.Enabled = ($o.Folder -eq 'in')
        $btnUnread.Enabled = ($o.Folder -eq 'in')
        $btnSndFr.Enabled = ($o.Folder -eq 'in')
        $btnSndBan.Enabled = ($o.Folder -eq 'in')
        $btnDelMail.Text = if ($o.Folder -eq 'out') { 'Senden abbrechen' } else { 'Löschen' }
        $lvMail.Columns[0].Text = if ($o.Folder -eq 'in') { 'Von' } else { 'An' }
    }

    function Update-O11MailList {
        $selId = ''
        $sel = Get-O11SelectedMail
        if ($sel) { $selId = [string]$sel.Id }
        $friends = Get-O11FriendMap
        $lvMail.BeginUpdate()
        $lvMail.Items.Clear()
        foreach ($m in @([EarthMailStore]::List((Get-O11MailDir)))) {
            if ($o.Folder -eq 'in') {
                $who = [string]$m.FromName
                if ($friends.ContainsKey([string]$m.FromIp) -and $friends[[string]$m.FromIp].Name) { $who = [string]$friends[[string]$m.FromIp].Name }
                if (-not $who) { $who = [string]$m.FromIp }
                $when = Format-PelMailTime $m.ReceivedUtc
                $status = if ($m.Read) { 'gelesen' } else { 'NEU' }
                if (-not $m.Verified) { $status += ' (unbestätigt)' }
            } elseif ($o.Folder -eq 'out') {
                $who = [string]$m.ToName
                if (-not $who) { $who = [string]$m.ToIp }
                $when = Format-PelMailTime $m.CreatedUtc
                $status = if ($m.Attempts -gt 0) { "wartet ($($m.Attempts). Versuch)" } else { 'wird gesendet ...' }
                if ($m.Relayed) { $status += ' + Kopie verteilt' }
            } else {
                $who = [string]$m.ToName
                if (-not $who) { $who = [string]$m.ToIp }
                $when = Format-PelMailTime $m.DeliveredUtc
                $status = 'zugestellt'
            }
            $subj = [string]$m.Subject
            if (-not $subj) { $subj = '(kein Betreff)' }
            $it = New-Object System.Windows.Forms.ListViewItem($who)
            [void]$it.SubItems.Add($subj)
            [void]$it.SubItems.Add($when)
            [void]$it.SubItems.Add($status)
            $it.Tag = $m
            if ($o.Folder -eq 'in' -and -not $m.Read) { $it.Font = $fontBold; $it.ForeColor = [System.Drawing.Color]::Gold }
            elseif ($o.Folder -eq 'out') { $it.ForeColor = [System.Drawing.Color]::Orange }
            [void]$lvMail.Items.Add($it)
            if ($selId -and $m.Id -eq $selId) { $it.Selected = $true }
        }
        $lvMail.EndUpdate()
        Update-O11FolderButtons
        if ($lvMail.SelectedItems.Count -eq 0) { $rtbRead.Clear(); $o.LastSel = '' }
    }

    function Add-O11ReadLine([string]$label, [string]$value, $color = $null) {
        $rtbRead.SelectionFont = $fontBold
        $rtbRead.SelectionColor = $cGray
        $rtbRead.AppendText("$label ")
        $rtbRead.SelectionFont = $fontMain
        if ($color) { $rtbRead.SelectionColor = $color } else { $rtbRead.SelectionColor = $cWhite }
        $rtbRead.AppendText("$value`n")
    }

    function Show-O11Mail($m) {
        $rtbRead.Clear()
        if (-not $m) { return }
        $fromTxt = if ($m.FromName) { "$($m.FromName) ($($m.FromIp))" } else { [string]$m.FromIp }
        $toTxt = if ($m.ToName) { "$($m.ToName) ($($m.ToIp))" } else { [string]$m.ToIp }
        if ($o.Folder -eq 'in') {
            Add-O11ReadLine 'Von:' $fromTxt
            Add-O11ReadLine 'Geschrieben:' (Format-PelMailTime $m.CreatedUtc)
            Add-O11ReadLine 'Empfangen:' (Format-PelMailTime $m.ReceivedUtc)
            Add-O11ReadLine 'Zustellung:' ([string]$m.Via)
            if ($m.Verified) { Add-O11ReadLine 'Absender:' 'bestätigt (kommt wirklich von dieser IP)' ([System.Drawing.Color]::LightGreen) }
            else { Add-O11ReadLine 'Absender:' 'NICHT bestätigt - weitergeleitet, und der Schlüssel des Absenders ist noch unbekannt. Im Zweifel direkt nachfragen.' ([System.Drawing.Color]::Orange) }
        } elseif ($o.Folder -eq 'out') {
            Add-O11ReadLine 'An:' $toTxt
            Add-O11ReadLine 'Geschrieben:' (Format-PelMailTime $m.CreatedUtc)
            $st = if ($m.LastError) { [string]$m.LastError } else { 'wird gerade zugestellt ...' }
            Add-O11ReadLine 'Status:' $st ([System.Drawing.Color]::Orange)
            if ($m.NextTryUtc -gt 0) { Add-O11ReadLine 'Nächster Versuch:' "$(Format-PelMailTime $m.NextTryUtc) (oder sofort, sobald der Empfänger online kommt)" }
            if ($m.Relayed) { Add-O11ReadLine 'Verschlüsselte Kopie bei:' ([string]$m.RelayedTo) }
        } else {
            Add-O11ReadLine 'An:' $toTxt
            Add-O11ReadLine 'Geschrieben:' (Format-PelMailTime $m.CreatedUtc)
            Add-O11ReadLine 'Zugestellt:' "$(Format-PelMailTime $m.DeliveredUtc) ($($m.Via))" ([System.Drawing.Color]::LightGreen)
        }
        $subj = [string]$m.Subject
        if (-not $subj) { $subj = '(kein Betreff)' }
        Add-O11ReadLine 'Betreff:' $subj
        $rtbRead.AppendText("`n")
        $rtbRead.SelectionFont = $rtbRead.Font
        $rtbRead.SelectionColor = $cWhite
        $rtbRead.AppendText([string]$m.Body)
        $rtbRead.SelectionStart = 0
        $rtbRead.ScrollToCaret()
    }

    function Update-O11Friends {
        $o11Social.Load()
        $selIp = ''
        if ($lvFriends.SelectedItems.Count -gt 0) { $selIp = [string]$lvFriends.SelectedItems[0].Tag.Ip }
        $lvFriends.BeginUpdate()
        $lvFriends.Items.Clear()
        foreach ($fr in @($o11Social.GetFriends() | Sort-Object { ([string]$_.Name).ToLowerInvariant() })) {
            $it = New-Object System.Windows.Forms.ListViewItem([string]$fr.Name)
            [void]$it.SubItems.Add([string]$fr.Ip)
            [void]$it.SubItems.Add([string]$fr.Notes)
            $on = $o.Online.ContainsKey([string]$fr.Ip)
            [void]$it.SubItems.Add($(if ($on) { 'online' } else { 'offline' }))
            $it.ForeColor = if ($on) { [System.Drawing.Color]::LightGreen } else { $cGray }
            $it.Tag = $fr
            [void]$lvFriends.Items.Add($it)
            if ($selIp -and $fr.Ip -eq $selIp) { $it.Selected = $true }
        }
        $lvFriends.EndUpdate()
        Update-O11OnlineList
    }

    function Update-O11OnlineList {
        $friends = Get-O11FriendMap
        $selIp = ''
        if ($lvOnline.SelectedItems.Count -gt 0) { $selIp = [string]$lvOnline.SelectedItems[0].Tag.Ip }
        $lvOnline.BeginUpdate()
        $lvOnline.Items.Clear()
        foreach ($ip in @($o.Online.Keys | Sort-Object)) {
            $name = [string]$o.Online[$ip]
            $it = New-Object System.Windows.Forms.ListViewItem($(if ($name) { $name } else { '(ohne Namen)' }))
            [void]$it.SubItems.Add($ip)
            $isFr = $friends.ContainsKey($ip)
            [void]$it.SubItems.Add($(if ($isFr) { 'ja' } else { '-' }))
            $it.ForeColor = if ($isFr) { [System.Drawing.Color]::LightGreen } else { $cWhite }
            $it.Tag = [pscustomobject]@{ Ip = $ip; Name = $name }
            [void]$lvOnline.Items.Add($it)
            if ($selIp -and $ip -eq $selIp) { $it.Selected = $true }
        }
        if ($lvOnline.Items.Count -eq 0) {
            $it = New-Object System.Windows.Forms.ListViewItem('(gerade niemand erkannt - erscheint, sobald andere Manager laufen)')
            $it.ForeColor = $cGray
            $it.Tag = $null
            [void]$lvOnline.Items.Add($it)
        }
        $lvOnline.EndUpdate()
    }

    function Update-O11Bans {
        $o11Bans.Load()
        $lvBans.BeginUpdate()
        $lvBans.Items.Clear()
        foreach ($b in @($o11Bans.GetActive())) {
            $it = New-Object System.Windows.Forms.ListViewItem([string]$b.Ip)
            [void]$it.SubItems.Add([string]$b.Reason)
            [void]$it.SubItems.Add((Format-PelMailTime $b.TimestampUtc))
            [void]$it.SubItems.Add([string]$b.BannedByIp)
            $it.Tag = $b
            [void]$lvBans.Items.Add($it)
        }
        $lvBans.EndUpdate()
    }

    function Update-O11Online {
        $map = @{}
        foreach ($p in @(Get-PelMailOnlinePeers)) {
            $parts = ([string]$p) -split '\|', 2
            if ($parts.Count -ge 1 -and $parts[0]) { $map[$parts[0]] = $(if ($parts.Count -ge 2) { $parts[1] } else { '' }) }
        }
        $sig = (($map.Keys | Sort-Object | ForEach-Object { "$_=$($map[$_])" }) -join ';')
        if ($sig -ne $o.OnlineSig) {
            $o.OnlineSig = $sig
            $o.Online = $map
            Update-O11Friends
        }
    }

    function Update-O11Service {
        if ($script:PelMailNode) {
            $lblSvc.Text = "Postfach-Dienst: aktiv in diesem Fenster (Port $($script:PelMailPort))"
            $lblSvc.ForeColor = [System.Drawing.Color]::LightGreen
        } else {
            $f = [EarthMailStore]::OnlineFile
            $fresh = $false
            try { $fresh = [System.IO.File]::Exists($f) -and (([DateTime]::UtcNow - [System.IO.File]::GetLastWriteTimeUtc($f)).TotalSeconds -lt 30) } catch { }
            if ($fresh) { $lblSvc.Text = 'Postfach-Dienst: aktiv (im Control Center)'; $lblSvc.ForeColor = [System.Drawing.Color]::LightGreen }
            else { $lblSvc.Text = 'Postfach-Dienst: startet ...'; $lblSvc.ForeColor = [System.Drawing.Color]::Orange }
        }
    }

    # ===================================================================================
    # Aktionen
    # ===================================================================================
    function Show-O11Panel([int]$idx) {
        $pMail.Visible = ($idx -eq 0)
        $pFriends.Visible = ($idx -eq 1)
        $pBans.Visible = ($idx -eq 2)
        $navs = @($navMail, $navFriends, $navBans)
        for ($i = 0; $i -lt 3; $i++) { $navs[$i].BackColor = $(if ($i -eq $idx) { $cAccent } else { $cBtn }) }
        if ($idx -eq 1) { Update-O11Friends }
        if ($idx -eq 2) { Update-O11Bans }
    }
    $navMail.Add_Click({ Show-O11Panel 0 })
    $navFriends.Add_Click({ Show-O11Panel 1 })
    $navBans.Add_Click({ Show-O11Panel 2 })

    function Set-O11Folder([string]$f) {
        $o.Folder = $f
        $rtbRead.Clear()
        $o.LastSel = ''
        Update-O11MailList
    }
    $fldIn.Add_Click({ Set-O11Folder 'in' })
    $fldOut.Add_Click({ Set-O11Folder 'out' })
    $fldSent.Add_Click({ Set-O11Folder 'sent' })

    $lvMail.Add_SelectedIndexChanged({
        $m = Get-O11SelectedMail
        if (-not $m) { return }
        if ($o.LastSel -eq [string]$m.Id) { return }
        $o.LastSel = [string]$m.Id
        Show-O11Mail $m
        if ($o.Folder -eq 'in' -and -not $m.Read) {
            $m.Read = $true
            [void][EarthMailStore]::SaveIfExists($m, [EarthMailStore]::Inbox)
            $it = $lvMail.SelectedItems[0]
            $it.Font = $fontMain
            $it.ForeColor = $cWhite
            $st = 'gelesen'
            if (-not $m.Verified) { $st += ' (unbestätigt)' }
            $it.SubItems[3].Text = $st
            Update-O11FolderButtons
        }
    })

    # Empfänger-Auswahl: Freunde + gerade online, jeweils "Name (IP)"; eigene IP-Eingabe möglich.
    function Show-O11Compose([string]$toIp = '', [string]$toName = '', [string]$subject = '', [string]$body = '') {
        $d = New-Object System.Windows.Forms.Form
        $d.Text = 'Neue Nachricht'
        $d.StartPosition = 'CenterParent'
        $d.FormBorderStyle = 'FixedDialog'
        $d.MaximizeBox = $false
        $d.MinimizeBox = $false
        $d.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
        $d.ForeColor = $cWhite
        $d.ClientSize = New-Object System.Drawing.Size(560, 470)
        $d.Controls.Add((New-O11Label 'An (Freund oder Online-Spieler wählen, oder IP eintippen):' 14 12 530 20))
        $cb = New-Object System.Windows.Forms.ComboBox
        $cb.DropDownStyle = 'DropDown'
        $cb.Location = New-Object System.Drawing.Point(14, 34)
        $cb.Size = New-Object System.Drawing.Size(530, 26)
        $cb.BackColor = $cInput
        $cb.ForeColor = $cWhite
        $cb.Font = $fontMain
        $seen = @{}
        foreach ($fr in @($o11Social.GetFriends() | Sort-Object { ([string]$_.Name).ToLowerInvariant() })) {
            $e = "$($fr.Name) ($($fr.Ip))"
            if (-not $seen.ContainsKey([string]$fr.Ip)) { [void]$cb.Items.Add($e); $seen[[string]$fr.Ip] = $true }
        }
        foreach ($ip in @($o.Online.Keys | Sort-Object)) {
            if ($seen.ContainsKey($ip)) { continue }
            $nm = [string]$o.Online[$ip]
            if (-not $nm) { $nm = 'online' }
            [void]$cb.Items.Add("$nm ($ip)")
            $seen[$ip] = $true
        }
        if ($toIp) { $cb.Text = $(if ($toName) { "$toName ($toIp)" } else { $toIp }) }
        $d.Controls.Add($cb)
        $d.Controls.Add((New-O11Label 'Betreff:' 14 70 530 20))
        $tbS = New-Object System.Windows.Forms.TextBox
        $tbS.Location = New-Object System.Drawing.Point(14, 92)
        $tbS.Size = New-Object System.Drawing.Size(530, 26)
        $tbS.MaxLength = [EarthMailStore]::MaxSubject
        $tbS.BackColor = $cInput; $tbS.ForeColor = $cWhite; $tbS.Font = $fontMain
        $tbS.Text = $subject
        $d.Controls.Add($tbS)
        $lblB = New-O11Label "Nachricht (max. $([EarthMailStore]::MaxBody) Zeichen):" 14 128 530 20
        $d.Controls.Add($lblB)
        $tbB = New-Object System.Windows.Forms.TextBox
        $tbB.Location = New-Object System.Drawing.Point(14, 150)
        $tbB.Size = New-Object System.Drawing.Size(530, 240)
        $tbB.Multiline = $true
        $tbB.AcceptsReturn = $true
        $tbB.ScrollBars = 'Vertical'
        $tbB.MaxLength = [EarthMailStore]::MaxBody
        $tbB.BackColor = $cInput; $tbB.ForeColor = $cWhite; $tbB.Font = $fontMain
        $tbB.Text = $body
        $d.Controls.Add($tbB)
        $lblHint = New-O11Label 'Ist der Empfänger online, kommt die Nachricht sofort an - sonst automatisch, sobald er seinen Manager startet.' 14 396 530 36
        $lblHint.ForeColor = $cGray
        $d.Controls.Add($lblHint)
        $ok = New-O11Button 'Senden' 304 430 120 32 $true
        $cancel = New-O11Button 'Abbrechen' 430 430 114 32
        $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $d.Controls.AddRange(@($ok, $cancel))
        $d.CancelButton = $cancel
        $state = @{ Ip = ''; Name = '' }
        $ok.Add_Click({
            $t = ([string]$cb.Text).Trim()
            $ipM = [regex]::Match($t, '(\d{1,3}(?:\.\d{1,3}){3})')
            if (-not $ipM.Success -or -not (Test-O11Ip $ipM.Groups[1].Value)) {
                [void][System.Windows.Forms.MessageBox]::Show($d, 'Bitte einen Empfänger auswählen oder eine gültige IP-Adresse eingeben (z. B. 10.147.20.15).', 'Neue Nachricht', 'OK', 'Warning')
                return
            }
            if (-not $tbB.Text.Trim() -and -not $tbS.Text.Trim()) {
                [void][System.Windows.Forms.MessageBox]::Show($d, 'Bitte einen Betreff oder Text eingeben.', 'Neue Nachricht', 'OK', 'Warning')
                return
            }
            $state.Ip = $ipM.Groups[1].Value
            $nm = ($t -replace '\s*\(?\d{1,3}(?:\.\d{1,3}){3}\)?\s*$', '').Trim()
            $frm = Get-O11FriendMap
            if ($frm.ContainsKey($state.Ip) -and $frm[$state.Ip].Name) { $nm = [string]$frm[$state.Ip].Name }
            elseif (-not $nm -and $o.Online.ContainsKey($state.Ip)) { $nm = [string]$o.Online[$state.Ip] }
            $state.Name = $nm
            $d.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $d.Close()
        })
        $res = $d.ShowDialog($form)
        $subjOut = $tbS.Text
        $bodyOut = $tbB.Text
        $d.Dispose()
        if ($res -ne [System.Windows.Forms.DialogResult]::OK) { return }
        $localIps = Get-PelLocalIpSet
        if ($localIps.ContainsKey($state.Ip)) {
            Show-O11Msg 'Das ist eine eigene IP-Adresse dieses PCs - bitte einen anderen Empfänger wählen.' ([System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        $ban = $false
        try { $ban = $o11Bans.IsBanned($state.Ip) } catch { }
        if ($ban -and -not (Confirm-O11 "$($state.Ip) steht auf deiner Bannliste - Antworten von dort nimmst du nicht an. Trotzdem senden?")) { return }
        $id = New-PelMailOutgoing -ToIp $state.Ip -ToName $state.Name -Subject $subjOut -Body $bodyOut
        if (-not $id) { Show-O11Msg 'Die Nachricht konnte nicht gespeichert werden.' ([System.Windows.Forms.MessageBoxIcon]::Error); return }
        Set-O11Folder 'out'
        $who = if ($state.Name) { $state.Name } else { $state.Ip }
        $lblSvc.Text = "Nachricht an $who liegt im Ausgang und wird zugestellt ..."
    }

    $btnNew.Add_Click({ Show-O11Compose })
    $btnReply.Add_Click({
        $m = Get-O11SelectedMail
        if (-not $m -or $o.Folder -ne 'in') { Show-O11Msg 'Bitte zuerst im Eingang eine Nachricht auswählen.'; return }
        $subj = [string]$m.Subject
        if ($subj -notmatch '^(AW|Re):') { $subj = "AW: $subj" }
        if ($subj.Length -gt [EarthMailStore]::MaxSubject) { $subj = $subj.Substring(0, [EarthMailStore]::MaxSubject) }
        $quoted = ((([string]$m.Body) -split "`n") | ForEach-Object { "> $_" }) -join "`r`n"
        $body = "`r`n`r`n--- $($m.FromName) schrieb am $(Format-PelMailTime $m.CreatedUtc): ---`r`n$quoted"
        if ($body.Length -gt [EarthMailStore]::MaxBody) { $body = $body.Substring(0, [EarthMailStore]::MaxBody) }
        Show-O11Compose ([string]$m.FromIp) ([string]$m.FromName) $subj $body
    })
    $lvMail.Add_DoubleClick({ if ($o.Folder -eq 'in') { $btnReply.PerformClick() } })

    $btnDelMail.Add_Click({
        $m = Get-O11SelectedMail
        if (-not $m) { Show-O11Msg 'Bitte zuerst eine Nachricht auswählen.'; return }
        $q = if ($o.Folder -eq 'out') { 'Diese Nachricht nicht mehr senden und aus dem Ausgang löschen?' } else { 'Nachricht endgültig löschen?' }
        if ($o.Folder -eq 'out' -and $m.Relayed) { $q += "`n`nHinweis: Eine verschlüsselte Kopie liegt bereits bei $($m.RelayedTo) und kann trotzdem noch zugestellt werden." }
        if (-not (Confirm-O11 $q)) { return }
        try { if ([System.IO.File]::Exists($m.FilePath)) { [System.IO.File]::Delete($m.FilePath) } } catch { Show-O11Msg "Löschen fehlgeschlagen: $($_.Exception.Message)" ([System.Windows.Forms.MessageBoxIcon]::Error) }
        $rtbRead.Clear()
        $o.LastSel = ''
        Update-O11MailList
    })
    $btnUnread.Add_Click({
        $m = Get-O11SelectedMail
        if (-not $m -or $o.Folder -ne 'in') { return }
        $m.Read = $false
        [void][EarthMailStore]::SaveIfExists($m, [EarthMailStore]::Inbox)
        $lvMail.SelectedItems.Clear()
        $o.LastSel = ''
        Update-O11MailList
    })

    function Add-O11FriendInteractive([string]$ip = '', [string]$name = '') {
        $vals = Show-O11InputDialog 'Freund hinzufügen' 'Name und ZeroTier-IP des Freundes (die IP steht z. B. im Live-Status unter "Wer spielt was" oder in seiner Datei "Project Earth Lan IP.txt").' @(
            @{ Label = 'Name:'; Value = $name; Max = 40 },
            @{ Label = 'IP-Adresse:'; Value = $ip; Max = 15 },
            @{ Label = 'Notiz (optional):'; Value = ''; Max = 200 }
        ) 'Hinzufügen'
        if (-not $vals) { return }
        $n = ([string]$vals[0]).Trim(); $i = ([string]$vals[1]).Trim(); $no = ([string]$vals[2]).Trim()
        if (-not (Test-O11Ip $i)) { Show-O11Msg "'$i' ist keine gültige IPv4-Adresse." ([System.Windows.Forms.MessageBoxIcon]::Warning); return }
        if (-not $n) { $n = $i }
        $o11Social.Load()
        $o11Social.AddFriend($i, $n, $no)
        Update-O11Friends
        if ($o.Folder -eq 'in') { Update-O11MailList }
    }

    function Get-O11SelFriend {
        if ($lvFriends.SelectedItems.Count -gt 0) { return $lvFriends.SelectedItems[0].Tag }
        return $null
    }

    $btnFrAdd.Add_Click({ Add-O11FriendInteractive })
    $btnFrEdit.Add_Click({
        $fr = Get-O11SelFriend
        if (-not $fr) { Show-O11Msg 'Bitte zuerst einen Freund auswählen.'; return }
        $vals = Show-O11InputDialog 'Freund bearbeiten' '' @(
            @{ Label = 'Name:'; Value = [string]$fr.Name; Max = 40 },
            @{ Label = 'IP-Adresse:'; Value = [string]$fr.Ip; Max = 15 },
            @{ Label = 'Notiz:'; Value = [string]$fr.Notes; Max = 200 }
        ) 'Speichern'
        if (-not $vals) { return }
        $n = ([string]$vals[0]).Trim(); $i = ([string]$vals[1]).Trim(); $no = ([string]$vals[2]).Trim()
        if (-not (Test-O11Ip $i)) { Show-O11Msg "'$i' ist keine gültige IPv4-Adresse." ([System.Windows.Forms.MessageBoxIcon]::Warning); return }
        if (-not $n) { $n = $i }
        $o11Social.Load()
        if ($i -ne [string]$fr.Ip) { $o11Social.RemoveFriend([string]$fr.Ip) }
        $o11Social.AddFriend($i, $n, $no)
        Update-O11Friends
    })
    $lvFriends.Add_DoubleClick({ $btnFrEdit.PerformClick() })
    $btnFrDel.Add_Click({
        $fr = Get-O11SelFriend
        if (-not $fr) { Show-O11Msg 'Bitte zuerst einen Freund auswählen.'; return }
        if (-not (Confirm-O11 "$($fr.Name) ($($fr.Ip)) aus der Freundesliste entfernen?")) { return }
        $o11Social.Load()
        $o11Social.RemoveFriend([string]$fr.Ip)
        Update-O11Friends
    })
    $btnFrMsg.Add_Click({
        $fr = Get-O11SelFriend
        if (-not $fr) { Show-O11Msg 'Bitte zuerst einen Freund auswählen.'; return }
        Show-O11Panel 0
        Show-O11Compose ([string]$fr.Ip) ([string]$fr.Name)
    })
    $btnFrCopy.Add_Click({
        $fr = Get-O11SelFriend
        if (-not $fr) { return }
        if (Set-PelClipboard ([string]$fr.Ip)) { $lblSvc.Text = "IP $($fr.Ip) kopiert." }
    })

    function Invoke-O11Ban([string]$ip, [string]$name) {
        if (-not (Test-O11Ip $ip)) { return }
        $vals = Show-O11InputDialog 'IP bannen' "Von $ip$(if ($name) { " ($name)" }) nimmt dein Manager danach nichts mehr an (Chat, Voice, Dateien, Postfach)." @(
            @{ Label = 'Grund (nur für dich sichtbar):'; Value = ''; Max = 200 }
        ) 'Bannen'
        if ($null -eq $vals) { return }
        $o11Bans.Load()
        $own = ''
        try { $own = Get-PelSourceIpFor $ip } catch { }
        $o11Bans.BanIP($ip, ([string]$vals[0]).Trim(), $own)
        Update-O11Bans
        Show-O11Msg "$ip ist jetzt gebannt."
    }
    $btnFrBan.Add_Click({
        $fr = Get-O11SelFriend
        if (-not $fr) { Show-O11Msg 'Bitte zuerst einen Freund auswählen.'; return }
        Invoke-O11Ban ([string]$fr.Ip) ([string]$fr.Name)
    })
    $btnSndFr.Add_Click({
        $m = Get-O11SelectedMail
        if (-not $m -or $o.Folder -ne 'in') { Show-O11Msg 'Bitte zuerst im Eingang eine Nachricht auswählen.'; return }
        Add-O11FriendInteractive ([string]$m.FromIp) ([string]$m.FromName)
    })
    $btnSndBan.Add_Click({
        $m = Get-O11SelectedMail
        if (-not $m -or $o.Folder -ne 'in') { Show-O11Msg 'Bitte zuerst im Eingang eine Nachricht auswählen.'; return }
        Invoke-O11Ban ([string]$m.FromIp) ([string]$m.FromName)
    })
    $btnMailDir.Add_Click({ try { Start-Process explorer.exe -ArgumentList "`"$((Get-O11MailDir))`"" } catch { } })

    $btnOnAdd.Add_Click({
        if ($lvOnline.SelectedItems.Count -eq 0 -or -not $lvOnline.SelectedItems[0].Tag) { Show-O11Msg 'Bitte unten einen Online-Spieler auswählen.'; return }
        $t = $lvOnline.SelectedItems[0].Tag
        Add-O11FriendInteractive ([string]$t.Ip) ([string]$t.Name)
    })
    $lvOnline.Add_DoubleClick({ $btnOnAdd.PerformClick() })
    $btnOnMsg.Add_Click({
        if ($lvOnline.SelectedItems.Count -eq 0 -or -not $lvOnline.SelectedItems[0].Tag) { Show-O11Msg 'Bitte unten einen Online-Spieler auswählen.'; return }
        $t = $lvOnline.SelectedItems[0].Tag
        Show-O11Panel 0
        Show-O11Compose ([string]$t.Ip) ([string]$t.Name)
    })

    $btnBnAdd.Add_Click({
        $vals = Show-O11InputDialog 'IP bannen' 'Von dieser IP nimmt dein Manager danach nichts mehr an (Chat, Voice, Dateien, Postfach).' @(
            @{ Label = 'IP-Adresse:'; Value = ''; Max = 15 },
            @{ Label = 'Grund (nur für dich sichtbar):'; Value = ''; Max = 200 }
        ) 'Bannen'
        if (-not $vals) { return }
        $i = ([string]$vals[0]).Trim()
        if (-not (Test-O11Ip $i)) { Show-O11Msg "'$i' ist keine gültige IPv4-Adresse." ([System.Windows.Forms.MessageBoxIcon]::Warning); return }
        $o11Bans.Load()
        $o11Bans.BanIP($i, ([string]$vals[1]).Trim(), (Get-PelSourceIpFor $i))
        Update-O11Bans
    })
    $btnBnDel.Add_Click({
        if ($lvBans.SelectedItems.Count -eq 0) { Show-O11Msg 'Bitte zuerst eine IP auswählen.'; return }
        $b = $lvBans.SelectedItems[0].Tag
        if (-not (Confirm-O11 "Bann für $($b.Ip) aufheben?")) { return }
        $o11Bans.Load()
        $o11Bans.UnbanIP([string]$b.Ip)
        Update-O11Bans
    })
    $btnBnEdit.Add_Click({
        if ($lvBans.SelectedItems.Count -eq 0) { Show-O11Msg 'Bitte zuerst eine IP auswählen.'; return }
        $b = $lvBans.SelectedItems[0].Tag
        $vals = Show-O11InputDialog 'Grund ändern' "Bann für $($b.Ip)" @( @{ Label = 'Grund:'; Value = [string]$b.Reason; Max = 200 } ) 'Speichern'
        if ($null -eq $vals) { return }
        $o11Bans.Load()
        $o11Bans.BanIP([string]$b.Ip, ([string]$vals[0]).Trim(), [string]$b.BannedByIp)
        Update-O11Bans
    })
    $lvBans.Add_DoubleClick({ $btnBnEdit.PerformClick() })

    # ===================================================================================
    # Timer: Postfach-Dienst, neue Nachrichten, Online-Liste, Änderungen von außen
    # ===================================================================================
    $o11Timer = New-Object System.Windows.Forms.Timer
    $o11Timer.Interval = 1000
    $o11Timer.Add_Tick({
        try {
            $o.Tick++
            # Control Center geschlossen? Dann übernimmt dieses Fenster den Postfach-Dienst.
            if (-not $script:PelMailNode -and ($o.Tick % 5) -eq 0) { [void](Start-PelMailService) }
            if ($script:PelMailNode) {
                $newCount = 0
                $ev = $null
                while ($script:PelMailNode.Events.TryDequeue([ref]$ev)) {
                    if (([string]$ev).StartsWith('NEW|')) { $newCount++ }
                }
                if ($newCount -gt 0) {
                    try { [System.Media.SystemSounds]::Asterisk.Play() } catch { }
                    $lblSvc.Text = "$newCount neue Nachricht(en) empfangen."
                }
            }
            $sig = [EarthMailStore]::Signature()
            if ($sig -ne $o.MailSig) {
                $o.MailSig = $sig
                Update-O11MailList
                $m = Get-O11SelectedMail
                if ($m) { Show-O11Mail $m }
            }
            if (($o.Tick % 3) -eq 1) {
                Update-O11Online
                Update-O11Service
                $stamp = ''
                foreach ($sf in @([EarthSocialPaths]::BansFile, [EarthSocialPaths]::FriendsFile)) {
                    if ([System.IO.File]::Exists($sf)) { $stamp += [string][System.IO.File]::GetLastWriteTimeUtc($sf).Ticks + ';' } else { $stamp += '0;' }
                }
                if ($stamp -ne $o.SocialStamp) {
                    $o.SocialStamp = $stamp
                    Update-O11Friends
                    Update-O11Bans
                }
            }
        } catch { }
    })

    $form.Add_Shown({
        Update-O11Service
        Update-O11MailList
        Update-O11Friends
        Update-O11Bans
        $o.MailSig = [EarthMailStore]::Signature()
        $o11Timer.Start()
    })
    $form.Add_FormClosing({
        $o11Timer.Stop()
        Stop-PelMailService
    })
    [void]$form.ShowDialog()
    $form.Dispose()
}

# ------------------------------------------------------------------------------
# OPTIONEN IN EIGENEM FENSTER STARTEN (mehrere Optionen gleichzeitig)
# ------------------------------------------------------------------------------
function Start-OptionWindow {
    param (
        [string]$OptionNumber,
        [scriptblock]$Fallback
    )
    $started = $false
    try {
        if ($script:IsCompiledExe -and $script:SelfPath) {
            # Kompilierte .exe (z. B. PS2EXE): die eigene .exe direkt erneut starten, sie
            # enthaelt das komplette Skript schon - kein "powershell.exe -File" noetig.
            Start-Process -FilePath $script:SelfPath -ArgumentList "-Option $OptionNumber" | Out-Null
            $started = $true
        } elseif ($script:SelfPath) {
            Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$($script:SelfPath)`" -Option $OptionNumber" | Out-Null
            $started = $true
        } else {
            $exe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
            if ($exe -and ([System.IO.Path]::GetFileName($exe) -notmatch '^(powershell|pwsh|powershell_ise)\.exe$')) {
                Start-Process -FilePath $exe -ArgumentList "-Option $OptionNumber" | Out-Null
                $started = $true
            }
        }
    } catch { }
    if (-not $started) { & $Fallback }
}

# ------------------------------------------------------------------------------
# ZENTRALES HAUPTMENÜ DASHBOARD
# ------------------------------------------------------------------------------
function Show-MainDashboard {
    $mainForm = New-Object System.Windows.Forms.Form
    $mainForm.Text = "Project Earth LAN - Control Center"
    $mainForm.Size = New-Object System.Drawing.Size(520, 1000)
    $mainForm.StartPosition = "CenterScreen"
    $mainForm.FormBorderStyle = "FixedDialog"
    $mainForm.MaximizeBox = $false
    $mainForm.BackColor = [System.Drawing.Color]::FromArgb(25, 25, 25)
    $mainForm.ForeColor = [System.Drawing.Color]::White
    # Auf kleinen Bildschirmen (z. B. Laptop mit 1366x768) passt das Fenster nicht ganz
    # auf den Schirm - dann auf die Arbeitsfläche begrenzen und scrollbar machen.
    try {
        $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        if ($mainForm.Height -gt $wa.Height) { $mainForm.Height = $wa.Height; $mainForm.AutoScroll = $true }
    } catch { }

    $fontHeader = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $fontBtn = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "Project Earth LAN - Manager Panel"
    $lblTitle.Location = New-Object System.Drawing.Point(20, 15)
    $lblTitle.Size = New-Object System.Drawing.Size(460, 30)
    $lblTitle.Font = $fontHeader
    $lblTitle.ForeColor = [System.Drawing.Color]::White
    $lblTitle.TextAlign = "MiddleCenter"
    $mainForm.Controls.Add($lblTitle)

    $buttons = @(
        @{ Text = "1. Project Earth LAN Installieren"; Action = { Invoke-InstallProjectEarthLan } },
        @{ Text = "2. Netzwerk Login ( 16 Stellige ZeroTier ID eingeben)"; Action = { Invoke-NetworkLogin } },
        @{ Text = "3. Netzwerk Logout"; Action = { Invoke-NetworkLogout } },
        @{ Text = "4. ReadMe erstellen"; Action = { Invoke-GenerateExplanationFile } },
        @{ Text = "5. Tools, Mods & Games Downloader"; Action = { Start-OptionWindow '5' { Invoke-ToolsModsGames } } },
        @{ Text = "6. Windows Remotedesktop aktivieren / deaktivieren"; Action = { Start-OptionWindow '6' { Invoke-RemoteDesktopZeroTier } } },
        @{ Text = "7. Spiele mit Lokalem Multiplayer (Lan) als Verknüpfung in einen Ordner auf Desktop anlegen"; Action = { Start-OptionWindow '7' { Invoke-LanGameFinder } } },
        @{ Text = "8. Manuelle Game Suche"; Action = { Start-OptionWindow '8' { Invoke-ManualGameSearch } } },
        @{ Text = "9. Server-Manager & Server Browser (Port 9872)"; Action = { Start-OptionWindow '9' { Invoke-ServerManagerBrowser } } },
        @{ Text = "10. Kommunikationszentrale (Chat, Dateien, Voice)"; Action = { Start-OptionWindow '10' { Invoke-CommCenter } } },
        @{ Text = "11. Freundesliste, Bannliste & Postfach"; Action = { Start-OptionWindow '11' { Invoke-FriendsBansMailbox } } },
        @{ Text = "12. Autostart: wird geprüft ..."; Action = $null; Key = 'autostart' }
    )

    $yPos = 55
    $btnAutostart = $null
    foreach ($btnInfo in $buttons) {
        $btn = New-Object System.Windows.Forms.Button
        $btn.Text = $btnInfo.Text
        $btn.Location = New-Object System.Drawing.Point(30, $yPos)
        $btn.Size = New-Object System.Drawing.Size(445, 34)
        $btn.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
        $btn.ForeColor = [System.Drawing.Color]::White
        $btn.FlatStyle = "Flat"
        $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
        $btn.Font = $fontBtn
        if ($btnInfo.Action) { $btn.Add_Click($btnInfo.Action) }
        if ($btnInfo.Key -eq 'autostart') { $btnAutostart = $btn }
        $mainForm.Controls.Add($btn)
        $yPos += 37
    }

    # ---- Button 12: Autostart an/aus (geplante Aufgabe, siehe Enable-PelAutostart) -------
    function Update-DashboardAutostartButton {
        $info = Get-PelAutostartInfo
        if ($info.Enabled -and $info.PathOk) {
            $btnAutostart.Text = "12. Autostart: AN  -  aus Autostart entfernen"
            $btnAutostart.ForeColor = [System.Drawing.Color]::LightGreen
        } elseif ($info.Enabled) {
            $btnAutostart.Text = "12. Autostart: zeigt auf alten Speicherort - neu einrichten"
            $btnAutostart.ForeColor = [System.Drawing.Color]::Orange
        } else {
            $btnAutostart.Text = "12. Autostart: AUS  -  zum Autostart hinzufügen"
            $btnAutostart.ForeColor = [System.Drawing.Color]::White
        }
    }
    $btnAutostart.Add_Click({
        $info = Get-PelAutostartInfo
        $ico = [System.Windows.Forms.MessageBoxIcon]::Question
        $yn = [System.Windows.Forms.MessageBoxButtons]::YesNo
        if ($info.Enabled -and $info.PathOk) {
            $ans = [System.Windows.Forms.MessageBox]::Show($mainForm, "Der Project Earth LAN Manager startet zurzeit automatisch mit Windows.`n`nAus dem Autostart entfernen?", 'Autostart', $yn, $ico)
            if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { return }
            $err = Disable-PelAutostart
            if ($err) { Show-PelMsg "Autostart konnte nicht entfernt werden:`n$err" 'Autostart' ([System.Windows.Forms.MessageBoxIcon]::Error) $mainForm }
            else { Show-PelMsg "Autostart entfernt. Der Manager startet nicht mehr automatisch mit Windows." 'Autostart' ([System.Windows.Forms.MessageBoxIcon]::Information) $mainForm }
        } else {
            $q = "Project Earth LAN Manager beim Windows-Start automatisch starten?`n`n" +
                 "- startet ca. 30 Sekunden nach der Anmeldung, minimiert in der Taskleiste`n" +
                 "- mit Administratorrechten, aber ohne UAC-Abfrage (als geplante Aufgabe)`n" +
                 "- Postfach, Live-Status und Spieleabend-Ankündigungen sind dann immer aktiv`n`n" +
                 "Programm: $($script:SelfPath)`n(Verschiebst du die Datei später, hier einfach neu einrichten.)"
            if ($info.Enabled) { $q = "Der Autostart zeigt noch auf einen anderen Speicherort:`n$($info.Target)`n`n" + $q }
            $ans = [System.Windows.Forms.MessageBox]::Show($mainForm, $q, 'Autostart', $yn, $ico)
            if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { return }
            $err = Enable-PelAutostart
            if ($err) { Show-PelMsg "Autostart konnte nicht eingerichtet werden:`n$err" 'Autostart' ([System.Windows.Forms.MessageBoxIcon]::Error) $mainForm }
            else { Show-PelMsg "Autostart eingerichtet. Ab der nächsten Anmeldung startet der Manager automatisch (minimiert).`n`nEntfernen jederzeit wieder über Button 12." 'Autostart' ([System.Windows.Forms.MessageBoxIcon]::Information) $mainForm }
        }
        Update-DashboardAutostartButton
    })
    Update-DashboardAutostartButton

    # ---- Live-Status: ZeroTier-Verbindung, eigene IP, Freunde online -------------------
    # Läuft direkt im Control Center, ohne dass Option 9/10 geöffnet werden muss.
    $fontMain = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Regular)
    $fontSmall = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)

    $grpStatusY = $yPos + 8
    $grpStatus = New-Object System.Windows.Forms.GroupBox
    $grpStatus.Text = "Live-Status"
    $grpStatus.Location = New-Object System.Drawing.Point(30, $grpStatusY)
    $grpStatus.Size = New-Object System.Drawing.Size(445, 440)
    $grpStatus.ForeColor = [System.Drawing.Color]::White
    $grpStatus.Font = $fontBtn
    $mainForm.Controls.Add($grpStatus)

    $lblZt = New-Object System.Windows.Forms.Label
    $lblZt.Text = "ZeroTier: wird geprüft ..."
    $lblZt.Location = New-Object System.Drawing.Point(15, 28)
    $lblZt.Size = New-Object System.Drawing.Size(415, 22)
    $lblZt.ForeColor = [System.Drawing.Color]::LightGray
    $lblZt.Font = $fontMain
    $grpStatus.Controls.Add($lblZt)

    $lblIp = New-Object System.Windows.Forms.Label
    $lblIp.Text = "Eigene IP: -"
    $lblIp.Location = New-Object System.Drawing.Point(15, 54)
    $lblIp.Size = New-Object System.Drawing.Size(415, 22)
    $lblIp.ForeColor = [System.Drawing.Color]::LightGray
    $lblIp.Font = $fontMain
    $grpStatus.Controls.Add($lblIp)

    $lblFriends = New-Object System.Windows.Forms.Label
    $lblFriends.Text = "Freunde online: -"
    $lblFriends.Location = New-Object System.Drawing.Point(15, 80)
    $lblFriends.Size = New-Object System.Drawing.Size(415, 22)
    $lblFriends.ForeColor = [System.Drawing.Color]::LightGray
    $lblFriends.Font = $fontMain
    $grpStatus.Controls.Add($lblFriends)

    $lblAdapter = New-Object System.Windows.Forms.Label
    $lblAdapter.Text = "Adapter: -"
    $lblAdapter.Location = New-Object System.Drawing.Point(15, 106)
    $lblAdapter.Size = New-Object System.Drawing.Size(415, 20)
    $lblAdapter.ForeColor = [System.Drawing.Color]::LightGray
    $lblAdapter.Font = $fontMain
    $grpStatus.Controls.Add($lblAdapter)

    $lblOtherMgrs = New-Object System.Windows.Forms.Label
    $lblOtherMgrs.Text = "Andere Manager im Netz: -"
    $lblOtherMgrs.Location = New-Object System.Drawing.Point(15, 130)
    $lblOtherMgrs.Size = New-Object System.Drawing.Size(415, 20)
    $lblOtherMgrs.ForeColor = [System.Drawing.Color]::LightGray
    $lblOtherMgrs.Font = $fontMain
    $grpStatus.Controls.Add($lblOtherMgrs)

    $lblVersion = New-Object System.Windows.Forms.Label
    $lblVersion.Text = "Version: $($script:PelVersion)"
    $lblVersion.Location = New-Object System.Drawing.Point(15, 154)
    $lblVersion.Size = New-Object System.Drawing.Size(212, 20)
    $lblVersion.ForeColor = [System.Drawing.Color]::LightGray
    $lblVersion.Font = $fontMain
    $grpStatus.Controls.Add($lblVersion)

    $lblNextEvent = New-Object System.Windows.Forms.Label
    $lblNextEvent.Text = "Nächster Spieleabend: -"
    $lblNextEvent.Location = New-Object System.Drawing.Point(15, 178)
    $lblNextEvent.Size = New-Object System.Drawing.Size(415, 20)
    $lblNextEvent.ForeColor = [System.Drawing.Color]::LightGray
    $lblNextEvent.Font = $fontMain
    $grpStatus.Controls.Add($lblNextEvent)

    # Postfach (Option 11): ungelesene Nachrichten, Klick öffnet das Postfach
    $lblMail = New-Object System.Windows.Forms.Label
    $lblMail.Text = "Postfach: -"
    $lblMail.Location = New-Object System.Drawing.Point(15, 202)
    $lblMail.Size = New-Object System.Drawing.Size(415, 20)
    $lblMail.ForeColor = [System.Drawing.Color]::LightGray
    $lblMail.Font = $fontMain
    $lblMail.Cursor = [System.Windows.Forms.Cursors]::Hand
    $lblMail.Add_Click({ Start-OptionWindow '11' { Invoke-FriendsBansMailbox } })
    $grpStatus.Controls.Add($lblMail)

    # ---- Wer spielt gerade was (aus dem Live-Status-Verbund, Port 9928) ----------------
    $lblPlayingHdr = New-Object System.Windows.Forms.Label
    $lblPlayingHdr.Text = "Wer spielt gerade was (Doppelklick = Mitspielen):"
    $lblPlayingHdr.Location = New-Object System.Drawing.Point(15, 226)
    $lblPlayingHdr.Size = New-Object System.Drawing.Size(415, 18)
    $lblPlayingHdr.ForeColor = [System.Drawing.Color]::White
    $lblPlayingHdr.Font = $fontMain
    $grpStatus.Controls.Add($lblPlayingHdr)

    $lvPlaying = New-Object System.Windows.Forms.ListView
    $lvPlaying.Location = New-Object System.Drawing.Point(15, 246)
    $lvPlaying.Size = New-Object System.Drawing.Size(415, 92)
    $lvPlaying.View = 'Details'
    $lvPlaying.FullRowSelect = $true
    $lvPlaying.HideSelection = $false
    $lvPlaying.MultiSelect = $false
    $lvPlaying.HeaderStyle = 'Nonclickable'
    $lvPlaying.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
    $lvPlaying.ForeColor = [System.Drawing.Color]::White
    $lvPlaying.Font = $fontMain
    [void]$lvPlaying.Columns.Add("Spieler", 118)
    [void]$lvPlaying.Columns.Add("Spiel", 165)
    [void]$lvPlaying.Columns.Add("Adresse", 110)
    $grpStatus.Controls.Add($lvPlaying)

    $btnAdapterSwitch = New-Object System.Windows.Forms.Button
    $btnAdapterSwitch.Text = "Adapter wechseln"
    $btnAdapterSwitch.Location = New-Object System.Drawing.Point(15, 344)
    $btnAdapterSwitch.Size = New-Object System.Drawing.Size(200, 28)
    $btnAdapterSwitch.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
    $btnAdapterSwitch.ForeColor = [System.Drawing.Color]::White
    $btnAdapterSwitch.FlatStyle = "Flat"
    $btnAdapterSwitch.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
    $btnAdapterSwitch.Font = $fontMain
    $btnAdapterSwitch.Add_Click({
        $chosen = Select-PelNetworkAdapter -ParentForm $mainForm
        if ($chosen) {
            Update-DashboardAdapterLabel
            # Beim Wechseln immer aktiv eine Verbindung aufbauen (nicht nur die Auswahl
            # speichern) - bei einem ZeroTier-Adapter automatisch dem Project Earth LAN
            # Netzwerk beitreten/verbunden bleiben und die Metrik optimieren.
            Connect-PelZeroTierNetwork -Adapter $chosen
            Update-DashboardStatus
        }
    })
    $grpStatus.Controls.Add($btnAdapterSwitch)

    $newDashButton = {
        param([string]$text, [int]$x, [int]$y, [bool]$accent)
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $text
        $b.Location = New-Object System.Drawing.Point($x, $y)
        $b.Size = New-Object System.Drawing.Size(200, 28)
        if ($accent) { $b.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215) } else { $b.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45) }
        $b.ForeColor = [System.Drawing.Color]::White
        $b.FlatStyle = "Flat"
        $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
        $b.Font = $fontMain
        $grpStatus.Controls.Add($b)
        return $b
    }
    $btnJoinPlayer = & $newDashButton "Mitspielen" 230 344 $true
    $btnPlanner    = & $newDashButton "Spieleabend-Planer" 15 378 $false
    $btnLogExport  = & $newDashButton "Fehlerlog exportieren" 230 378 $false

    # Neue Version auf GitHub? Button erscheint nur, wenn dort etwas Neueres liegt, und
    # öffnet dann nur die GitHub-Seite (kein automatischer Download/Austausch).
    $btnGitHub = & $newDashButton "Neue Version auf GitHub" 230 150 $true
    $btnGitHub.Size = New-Object System.Drawing.Size(200, 24)
    $btnGitHub.BackColor = [System.Drawing.Color]::FromArgb(0, 135, 70)
    $btnGitHub.Visible = $false
    $btnGitHub.Add_Click({ Open-PelGitHubPage })
    $dashTip = New-Object System.Windows.Forms.ToolTip
    $dashTip.SetToolTip($lblVersion, "Diese Version: $($script:PelVersion) - GitHub wird beim Start und alle 6 Stunden geprüft.")

    $lblUpdated = New-Object System.Windows.Forms.Label
    $lblUpdated.Text = "Aktualisiert: -"
    $lblUpdated.Location = New-Object System.Drawing.Point(15, 412)
    $lblUpdated.Size = New-Object System.Drawing.Size(415, 18)
    $lblUpdated.ForeColor = [System.Drawing.Color]::DimGray
    $lblUpdated.Font = $fontSmall
    $lblUpdated.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
    $grpStatus.Controls.Add($lblUpdated)

    function Update-DashboardAdapterLabel {
        $sel = Get-PelSelectedAdapter
        if ($sel) {
            $lblAdapter.Text = "Adapter: $($sel.Name)  ($($sel.Ip))"
            $lblAdapter.ForeColor = [System.Drawing.Color]::LightGreen
        } else {
            $lblAdapter.Text = "Adapter: nicht ausgewählt - bitte 'Adapter wechseln' klicken"
            $lblAdapter.ForeColor = [System.Drawing.Color]::OrangeRed
        }
    }

    # Beim Öffnen: ist noch kein Adapter zentral gewählt, automatisch den mit der
    # niedrigsten Schnittstellenmetrik nehmen (= von Windows bevorzugte Verbindung),
    # zentral speichern und - falls ZeroTier -
    # gleich aktiv verbinden, statt nur passiv "nicht ausgewählt" anzuzeigen.
    if (-not (Get-PelSelectedAdapter)) {
        $autoAdapter = Get-PelAutoAdapter
        if ($autoAdapter) {
            Save-PelSelectedAdapter $autoAdapter
            Connect-PelZeroTierNetwork -Adapter $autoAdapter
        }
    }
    Update-DashboardAdapterLabel

    # Freundesliste read-only laden (dieselbe Datei/derselbe Mechanismus wie in der
    # Kommunikationszentrale) - hier wird nichts gesendet, nur zum Anpingen gelesen.
    Initialize-SocialTypes
    $dashSocial = New-Object FriendAndChannelManager

    function Get-DashboardZtStatus {
        $r = [pscustomobject]@{ Connected = $false; Ip = ''; NetworkName = '' }
        try {
            $best = $null
            foreach ($cand in @(Get-PelZtNetworkStatusList)) {
                if ($cand.Status -eq 'OK') {
                    if ($cand.Id -eq $script:PelNetworkId) { $best = $cand; break }
                    if (-not $best) { $best = $cand }
                }
            }
            if ($best) { $r.Connected = $true; $r.Ip = $best.Ip; $r.NetworkName = $best.Name }
        } catch { }
        return $r
    }

    function Update-DashboardStatus {
        $zt = Get-DashboardZtStatus
        if ($zt.Connected) {
            $lblZt.Text = "ZeroTier: Verbunden ($($zt.NetworkName))"
            $lblZt.ForeColor = [System.Drawing.Color]::LightGreen
            $lblIp.Text = "Eigene IP: $($zt.Ip)"
        } else {
            $lblZt.Text = "ZeroTier: Nicht verbunden"
            $lblZt.ForeColor = [System.Drawing.Color]::OrangeRed
            $lblIp.Text = "Eigene IP: -"
        }
        $lblUpdated.Text = "Aktualisiert: " + (Get-Date -Format 'HH:mm:ss')
    }

    # Freunde werden per (nicht-blockierendem) ICMP-Ping asynchron geprüft, damit die
    # Oberfläche dabei nicht einfriert - ein Poll-Timer liest die Task-Ergebnisse ab,
    # sobald sie fertig sind (dasselbe Prinzip wie die Hintergrund-Scans in Option 9).
    $pingState = [pscustomobject]@{ Tasks = @(); Total = 0; Online = 0; Busy = $false }
    function Start-DashboardFriendPing {
        if ($pingState.Busy) { return }
        # Vor jeder Prüfung neu von der Festplatte laden, damit neu hinzugefügte/entfernte
        # Freunde (z. B. gerade eben in der Kommunikationszentrale geändert) sofort ohne
        # Neustart des Control Centers berücksichtigt werden.
        $dashSocial.Load()
        $friends = @($dashSocial.GetFriends())
        if ($friends.Count -eq 0) {
            $lblFriends.Text = "Freunde online: keine Freunde gespeichert"
            $lblFriends.ForeColor = [System.Drawing.Color]::LightGray
            return
        }
        $pingState.Busy = $true
        $pingState.Total = $friends.Count
        $pingState.Tasks = @($friends | ForEach-Object {
            $p = New-Object System.Net.NetworkInformation.Ping
            $p.SendPingAsync($_.Ip, 700)
        })
        $lblFriends.Text = "Freunde online: prüfe $($friends.Count) ..."
    }
    $pingPoll = New-Object System.Windows.Forms.Timer
    $pingPoll.Interval = 300
    $pingPoll.Add_Tick({
        if (-not $pingState.Busy) { return }
        foreach ($t in $pingState.Tasks) { if (-not $t.IsCompleted) { return } }
        $online = 0
        foreach ($t in $pingState.Tasks) {
            try { if ($t.Result.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) { $online++ } } catch { }
        }
        $lblFriends.Text = "Freunde online: $online von $($pingState.Total)"
        $lblFriends.ForeColor = if ($online -gt 0) { [System.Drawing.Color]::LightGreen } else { [System.Drawing.Color]::LightGray }
        $pingState.Online = $online
        $pingState.Busy = $false
    })
    $pingPoll.Start()

    $statusTimer = New-Object System.Windows.Forms.Timer
    $statusTimer.Interval = 8000
    $statusTimer.Add_Tick({ Update-DashboardStatus; Start-DashboardFriendPing })
    $statusTimer.Start()

    # ---- Live-Status-Verbund zwischen allen Managern (Port 9928) -----------------------
    # Jeder offene Control Center meldet per UDP-Broadcast laufend den eigenen Live-Status
    # (Name, IP, ZeroTier-Status, Freunde online, Version) UND hört gleichzeitig auf die
    # Meldungen aller anderen Manager im Netz - "kommunizieren und abrufen" ohne zentralen
    # Server (reines UDP-Broadcast/Listen-Prinzip).
    $script:PelOtherManagers = @{}

    $statTx = $null
    try { $statTx = New-Object System.Net.Sockets.UdpClient; $statTx.EnableBroadcast = $true } catch { $statTx = $null }
    $statBcEp = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Broadcast, $script:PelStatusPort)

    $statRx = $null
    try {
        $statRx = New-Object System.Net.Sockets.UdpClient
        $statRx.Client.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::Socket, [System.Net.Sockets.SocketOptionName]::ReuseAddress, $true)
        $statRx.Client.Bind((New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, $script:PelStatusPort)))
        $statRx.EnableBroadcast = $true
    } catch { $statRx = $null }

    try {
        Get-NetFirewallRule -DisplayName "Project Earth LAN Status $($script:PelStatusPort)*" -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
        New-NetFirewallRule -DisplayName "Project Earth LAN Status $($script:PelStatusPort) (UDP)" -Direction Inbound -Action Allow -Protocol UDP -LocalPort $script:PelStatusPort -RemoteAddress LocalSubnet -Profile Any -ErrorAction Stop | Out-Null
    } catch { }

    # ---- Zustand für "Wer spielt was", Spieleabende und Eigen-Filter --------------------
    # Windows liefert eigene Broadcasts auch an den Absender zurück - ohne diesen Filter
    # würde der eigene PC unter "Andere Manager" mitgezählt.
    $script:PelOwnIps = Get-PelLocalIpSet
    $script:PelMyName = Get-PelDisplayName
    $script:PelMyGame = $null
    $dashState = @{ PlayingSig = ''; OwnIp = ''; LastReqMs = [int64]0 }
    Import-PelEvents

    # Spielerkennung in einem eigenen, wiederverwendeten Hintergrund-Runspace (siehe
    # $script:PelGameDetectScript) - die Oberfläche friert dabei nicht ein.
    $script:PelGameCache = [hashtable]::Synchronized(@{})
    $gameDetect = @{ Rs = $null; PS = $null; Handle = $null }
    try {
        $gameDetect.Rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $gameDetect.Rs.Open()
    } catch { $gameDetect.Rs = $null }
    function Start-DashboardGameDetect {
        if (-not $gameDetect.Rs -or $gameDetect.PS) { return }
        try {
            $ps = [PowerShell]::Create()
            $ps.Runspace = $gameDetect.Rs
            [void]$ps.AddScript($script:PelGameDetectScript.ToString())
            [void]$ps.AddArgument($script:PelGameCache)
            [void]$ps.AddArgument($script:PelKnownGameExes)
            [void]$ps.AddArgument([string]$script:SelfPath)
            $gameDetect.PS = $ps
            $gameDetect.Handle = $ps.BeginInvoke()
        } catch { $gameDetect.PS = $null; $gameDetect.Handle = $null }
    }
    function Receive-DashboardGameDetect {
        if (-not $gameDetect.PS -or -not $gameDetect.Handle -or -not $gameDetect.Handle.IsCompleted) { return }
        try {
            $out = $gameDetect.PS.EndInvoke($gameDetect.Handle)
            $r = @($out | Where-Object { $_ })
            if ($r.Count -gt 0) { $script:PelMyGame = $r[0] } else { $script:PelMyGame = $null }
        } catch { }
        finally {
            try { $gameDetect.PS.Dispose() } catch { }
            $gameDetect.PS = $null
            $gameDetect.Handle = $null
        }
    }

    function Update-DashboardPlaying {
        $rows = New-Object System.Collections.Generic.List[object]
        $mg = $script:PelMyGame
        $self = [pscustomobject]@{
            IsSelf = $true; Name = "$($script:PelMyName) (du)"; Ip = $dashState.OwnIp; SrcIp = ''
            Game = ''; GameExe = ''; JoinPort = 0; Server = ''
        }
        if ($mg) { $self.Game = [string]$mg.Title; $self.GameExe = [string]$mg.Exe; $self.JoinPort = [int]$mg.JoinPort; $self.Server = [string]$mg.Server }
        $rows.Add($self)
        foreach ($m in @($script:PelOtherManagers.Values | Sort-Object @{ Expression = { if ($_.Game) { 0 } else { 1 } } }, Name)) { $rows.Add($m) }
        $sig = (($rows | ForEach-Object { "$($_.Name)|$($_.Game)|$($_.Ip)|$($_.SrcIp)|$($_.JoinPort)|$($_.Server)" }) -join ';')
        if ($sig -eq $dashState.PlayingSig) { return }
        $dashState.PlayingSig = $sig
        $selKey = $null
        if ($lvPlaying.SelectedItems.Count -gt 0) { $t = $lvPlaying.SelectedItems[0].Tag; $selKey = "$($t.Name)|$($t.SrcIp)" }
        $lvPlaying.BeginUpdate()
        $lvPlaying.Items.Clear()
        foreach ($m in $rows) {
            $ip = [string]$m.Ip
            if (-not $ip) { $ip = [string]$m.SrcIp }
            $gameText = '-'
            if ($m.Game) { $gameText = [string]$m.Game }
            $addr = $ip
            if ($m.Server) { $addr = [string]$m.Server }
            elseif ($m.Game -and [int]$m.JoinPort -gt 0 -and $ip) { $addr = "${ip}:$($m.JoinPort)" }
            if (-not $addr) { $addr = '-' }
            $it = New-Object System.Windows.Forms.ListViewItem([string]$m.Name)
            [void]$it.SubItems.Add($gameText)
            [void]$it.SubItems.Add($addr)
            $it.Tag = $m
            if ($m.IsSelf) { $it.ForeColor = [System.Drawing.Color]::LightSkyBlue }
            elseif ($m.Game) { $it.ForeColor = [System.Drawing.Color]::LightGreen }
            else { $it.ForeColor = [System.Drawing.Color]::LightGray }
            [void]$lvPlaying.Items.Add($it)
            if ($selKey -and ("$($m.Name)|$($m.SrcIp)" -eq $selKey)) { $it.Selected = $true }
        }
        $lvPlaying.EndUpdate()
    }

    function Send-DashboardUdp([string]$Text) {
        if (-not $statTx) { return }
        try {
            $b = [System.Text.Encoding]::UTF8.GetBytes($Text)
            [void]$statTx.Send($b, $b.Length, $statBcEp)
        } catch { }
    }

    # Gleich beim Öffnen nach bekannten Spieleabenden fragen (statt auf die nächste
    # reguläre Weitergabe zu warten) - wichtig für "Ankündigung beim Öffnen".
    $reqCore = "PEEVTREQ1|$(Get-PelNowMs)"
    Send-DashboardUdp "$reqCore|$(Get-PelHmacBase64 -Text $reqCore)"

    $btnJoinPlayer.Add_Click({
        if ($lvPlaying.SelectedItems.Count -eq 0) {
            Show-PelMsg "Bitte zuerst in der Liste 'Wer spielt gerade was' einen Spieler auswählen." 'Mitspielen' ([System.Windows.Forms.MessageBoxIcon]::Information) $mainForm
            return
        }
        $m = $lvPlaying.SelectedItems[0].Tag
        if ($m.IsSelf) {
            Show-PelMsg "Das bist du selbst - wähle einen anderen Spieler aus." 'Mitspielen' ([System.Windows.Forms.MessageBoxIcon]::Information) $mainForm
            return
        }
        $ip = [string]$m.Ip
        if (-not $ip) { $ip = [string]$m.SrcIp }
        if (-not $m.Game) {
            $clipOk = Set-PelClipboard $ip
            $clipTxt = if ($clipOk) { "Seine IP $ip liegt in der Zwischenablage." } else { "Seine IP lautet $ip." }
            Show-PelMsg "$($m.Name) spielt gerade nichts, das der Manager erkennt.`n`n$clipTxt" 'Mitspielen' ([System.Windows.Forms.MessageBoxIcon]::Information) $mainForm
            return
        }
        $tIp = $ip
        $tJoin = 0
        if ($m.Server -and ([string]$m.Server -match '^(\d{1,3}(\.\d{1,3}){3}):(\d{1,5})$')) { $tIp = $matches[1]; $tJoin = [int]$matches[3] }
        elseif ([int]$m.JoinPort -gt 0) { $tJoin = [int]$m.JoinPort }
        if ($tJoin -gt 0) {
            $res = Invoke-PelJoinGame -Ip $tIp -JoinPort $tJoin -GameName ([string]$m.Game) -ExeHint ([string]$m.GameExe) -ParentForm $mainForm
        } else {
            # Spieler hostet nicht selbst und sein Server ist unbekannt (z. B. UDP-Server):
            # Spiel ohne Verbindungsparameter starten, seine IP in die Zwischenablage.
            $res = Invoke-PelJoinGame -Ip $tIp -GameName ([string]$m.Game) -ExeHint ([string]$m.GameExe) -ParentForm $mainForm -LaunchOnly
        }
        if ($res) { $lblUpdated.Text = $res }
    })
    $lvPlaying.Add_DoubleClick({ $btnJoinPlayer.PerformClick() })

    $btnPlanner.Add_Click({
        if ($script:PelAnnounceForm -and -not $script:PelAnnounceForm.IsDisposed) { try { $script:PelAnnounceForm.Close() } catch { } }
        $script:PelAnnounceForm = $null
        Show-PelGameNightPlanner -ParentForm $mainForm
        $lblNextEvent.Text = Get-PelNextEventText
    })
    $btnLogExport.Add_Click({ Export-PelErrorLog -ParentForm $mainForm })

    # ---- Postfach-Dienst (Option 11) --------------------------------------------------
    # Läuft hier im Control Center, damit Nachrichten auch ankommen, während Option 11
    # geschlossen ist. Ist Option 11 gerade der Host (Control Center war zu), übernimmt
    # das Control Center automatisch, sobald Option 11 geschlossen wird.
    [void](Start-PelMailService -NoStatusListener)
    $mailState = @{ Unread = -1 }
    function Update-DashboardMail {
        try {
            $unread = [EarthMailStore]::CountUnread()
            $waiting = [EarthMailStore]::CountFiles([EarthMailStore]::Outbox)
            $txt = if ($unread -gt 0) { "Postfach: $unread ungelesene Nachricht(en) - klicken zum Öffnen" } else { "Postfach: keine neuen Nachrichten" }
            if ($waiting -gt 0) { $txt += "  |  $waiting im Ausgang" }
            if (-not $script:PelMailNode) { $txt += "  (Dienst in Option 11)" }
            $lblMail.Text = $txt
            $lblMail.ForeColor = if ($unread -gt 0) { [System.Drawing.Color]::Gold } else { [System.Drawing.Color]::LightGray }
            $mailState.Unread = $unread
        } catch { }
    }

    # ---- GitHub-Versionsprüfung im Hintergrund (siehe $script:PelGitHubCheckScript) -------
    $ghCheck = @{ Rs = $null; PS = $null; Handle = $null; NextMs = [int64]0 }
    function Start-DashboardGitHubCheck {
        if ($ghCheck.PS) { return }
        try {
            $ghCheck.Rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
            $ghCheck.Rs.Open()
            $ps = [PowerShell]::Create()
            $ps.Runspace = $ghCheck.Rs
            [void]$ps.AddScript($script:PelGitHubCheckScript.ToString())
            [void]$ps.AddArgument($script:PelGitHubApiLatest)
            [void]$ps.AddArgument($script:PelGitHubApiTags)
            [void]$ps.AddArgument($script:PelGitHubApiContents)
            [void]$ps.AddArgument($script:PelGitHubRawVersion)
            $ghCheck.PS = $ps
            $ghCheck.Handle = $ps.BeginInvoke()
        } catch {
            $ghCheck.PS = $null; $ghCheck.Handle = $null
            if ($ghCheck.Rs) { try { $ghCheck.Rs.Dispose() } catch { } ; $ghCheck.Rs = $null }
        }
    }
    function Receive-DashboardGitHubCheck {
        if (-not $ghCheck.PS -or -not $ghCheck.Handle -or -not $ghCheck.Handle.IsCompleted) { return }
        $res = $null
        try {
            $out = @($ghCheck.PS.EndInvoke($ghCheck.Handle))
            if ($out.Count -gt 0) { $res = $out[$out.Count - 1] }
        } catch { }
        finally {
            try { $ghCheck.PS.Dispose() } catch { }
            try { $ghCheck.Rs.Close(); $ghCheck.Rs.Dispose() } catch { }
            $ghCheck.PS = $null; $ghCheck.Handle = $null; $ghCheck.Rs = $null
        }
        $when = Get-Date -Format 'HH:mm'
        if ($res -and $res.Ok) {
            if ($res.Latest -and ([string]$res.Latest -gt [string]$script:PelVersion)) {
                $script:PelGitHubLatest = [string]$res.Latest
                $lblVersion.Text = "Version: $($script:PelVersion) (veraltet)"
                $lblVersion.ForeColor = [System.Drawing.Color]::Gold
                $btnGitHub.Text = "Neue Version $($res.Latest) auf GitHub"
                $btnGitHub.Visible = $true
                $dashTip.SetToolTip($btnGitHub, "Gefunden: $($res.Source)`nÖffnet $($script:PelGitHubUrl) im Browser - dort herunterladen und die alte Datei ersetzen.")
                $dashTip.SetToolTip($lblVersion, "Diese Version: $($script:PelVersion) - auf GitHub: $($res.Latest) (geprüft um $when)")
                if (-not $ghCheck.Logged) { Write-PelLog "Neuere Version auf GitHub: $($res.Latest) ($($res.Source))"; $ghCheck.Logged = $true }
            } else {
                $btnGitHub.Visible = $false
                $lblVersion.Text = "Version: $($script:PelVersion) (aktuell)"
                $lblVersion.ForeColor = [System.Drawing.Color]::LightGray
                $dashTip.SetToolTip($lblVersion, "Diese Version: $($script:PelVersion) - keine neuere Version auf GitHub (geprüft um $when)")
            }
        } else {
            $dashTip.SetToolTip($lblVersion, "Diese Version: $($script:PelVersion) - GitHub war um $when nicht erreichbar, nächster Versuch in 1 Stunde.")
            $ghCheck.NextMs = (Get-PelNowMs) + 3600000
        }
    }
    $ghCheck.NextMs = (Get-PelNowMs) + 4000

    $script:PelStatusHbTick = 0
    $statPoll = New-Object System.Windows.Forms.Timer
    $statPoll.Interval = 500
    $statPoll.Add_Tick({
        # Gesamter Tick abgesichert: ein unerwarteter Fehler darf den Live-Status nicht
        # anhalten (er landet trotzdem im Fehlerprotokoll, siehe Save-PelErrorRecords).
        try {
            $script:PelStatusHbTick++
            Receive-DashboardGameDetect
            if (($script:PelStatusHbTick % 20) -eq 1) { Start-DashboardGameDetect }

            # Zweiter Start (z. B. Doppelklick, während der Manager per Autostart minimiert
            # läuft): dieses Fenster wieder nach vorne holen statt ein zweites zu öffnen.
            if ($script:PelShowEvent) {
                try {
                    if ($script:PelShowEvent.WaitOne(0)) {
                        if ($mainForm.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) { $mainForm.WindowState = [System.Windows.Forms.FormWindowState]::Normal }
                        $mainForm.Activate()
                        $mainForm.TopMost = $true; $mainForm.TopMost = $false
                    }
                } catch { }
            }

            # GitHub-Prüfung: kurz nach dem Start, danach alle 6 Stunden
            Receive-DashboardGitHubCheck
            if (-not $ghCheck.PS -and (Get-PelNowMs) -ge $ghCheck.NextMs) {
                $ghCheck.NextMs = (Get-PelNowMs) + 21600000
                Start-DashboardGitHubCheck
            }

            # Postfach: neue Nachrichten melden, Dienst ggf. übernehmen, Anzeige aktualisieren
            if (-not $script:PelMailNode -and ($script:PelStatusHbTick % 20) -eq 5) { [void](Start-PelMailService -NoStatusListener) }
            if ($script:PelMailNode) {
                $ev = $null
                $newMsgs = New-Object System.Collections.Generic.List[object]
                while ($script:PelMailNode.Events.TryDequeue([ref]$ev)) {
                    $evs = [string]$ev
                    if ($evs.StartsWith('NEW|')) {
                        $nm = [EarthMailStore]::Load((Join-Path ([EarthMailStore]::Inbox) ($evs.Substring(4) + '.msg')))
                        if ($nm) { $newMsgs.Add($nm) }
                    } elseif ($evs.StartsWith('SENT|')) {
                        $sm = [EarthMailStore]::Load((Join-Path ([EarthMailStore]::Sent) ($evs.Substring(5) + '.msg')))
                        if ($sm) {
                            $who = if ($sm.ToName) { $sm.ToName } else { $sm.ToIp }
                            $lblUpdated.Text = "Nachricht an $who zugestellt ($(Get-Date -Format 'HH:mm'))"
                        }
                    }
                }
                if ($newMsgs.Count -gt 0) {
                    Show-PelMailNotification -Messages $newMsgs -ParentForm $mainForm
                    Update-DashboardMail
                }
                if (($script:PelStatusHbTick % 120) -eq 0) { $script:PelMailNode.MyName = $script:PelMyName }
            }
            if (($script:PelStatusHbTick % 10) -eq 3) { Update-DashboardMail }

            if ($statTx -and ($script:PelStatusHbTick % 16 -eq 0)) {
                try {
                    $ztNow = Get-DashboardZtStatus
                    $ownIp = if ($ztNow.Connected) { $ztNow.Ip } else { '' }
                    $dashState.OwnIp = $ownIp
                    if ($ownIp) { $script:PelOwnIps[$ownIp] = $true }
                    $gTitle = ''; $gExe = ''; $gJp = 0; $gSrv = ''
                    $mg = $script:PelMyGame
                    if ($mg) {
                        $gTitle = Limit-PelText (([string]$mg.Title) -replace '\|', '/') 48
                        $gExe = ([string]$mg.Exe) -replace '\|', '/'
                        $gJp = [int]$mg.JoinPort
                        $gSrv = ([string]$mg.Server) -replace '\|', '/'
                    }
                    $core = "PESTAT1|$($script:PelMyName)|$ownIp|$([int]$ztNow.Connected)|$($pingState.Online)|$($pingState.Total)|$($script:PelVersion)|$gTitle|$gExe|$gJp|$gSrv"
                    Send-DashboardUdp "$core|$(Get-PelHmacBase64 -Text $core)"
                } catch { }
            }

            # Fällige Spieleabende weitergeben (max. 2 pro Sekunde)
            if ($statTx -and ($script:PelStatusHbTick % 2 -eq 0)) {
                foreach ($ev in @(Get-PelDueEvents 2)) { Send-DashboardUdp (ConvertTo-PelEventWire $ev) }
            }

            if ($statRx) {
                try {
                    while ($statRx.Available -gt 0) {
                        $remoteEp = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
                        $bytes = $statRx.Receive([ref]$remoteEp)
                        $txt = [System.Text.Encoding]::UTF8.GetString($bytes)
                        $srcIp = $remoteEp.Address.ToString()
                        $isSelf = $script:PelOwnIps.ContainsKey($srcIp)
                        if ($txt.StartsWith('PESTAT1|')) {
                            if ($isSelf) { continue }
                            $f = $txt -split '\|'
                            if ($f.Count -lt 8) { continue }
                            $recvSig = $f[$f.Count - 1]
                            $recvCore = ($f[0..($f.Count - 2)] -join '|')
                            if (-not (Test-PelHmac -Text $recvCore -Signature $recvSig)) { continue }
                            # Postfach: Empfänger ist (wieder) online -> wartende Nachrichten sofort zustellen
                            if ($script:PelMailNode) { try { $script:PelMailNode.NotePeer($srcIp, [string]$f[1]) } catch { } }
                            $on = 0; $tot = 0; $jp = 0
                            [void][int]::TryParse($f[4], [ref]$on)
                            [void][int]::TryParse($f[5], [ref]$tot)
                            $mgr = [pscustomobject]@{
                                IsSelf = $false; Name = $f[1]; Ip = $f[2]; SrcIp = $srcIp; Zt = ($f[3] -eq '1'); Online = $on; Total = $tot; Version = $f[6]
                                Game = ''; GameExe = ''; JoinPort = 0; Server = ''
                                Seen = Get-PelNowMs
                            }
                            if ($f.Count -ge 12) {
                                $mgr.Game = $f[7]
                                $mgr.GameExe = $f[8]
                                if ([int]::TryParse($f[9], [ref]$jp)) { $mgr.JoinPort = $jp }
                                $mgr.Server = $f[10]
                            }
                            $script:PelOtherManagers[$srcIp] = $mgr
                        } elseif ($txt.StartsWith('PEEVT1|')) {
                            $inc = ConvertFrom-PelEventWire $txt
                            if ($inc) {
                                Register-PelEventHeard $inc.Id
                                [void](Merge-PelEvent $inc)
                            }
                        } elseif ($txt.StartsWith('PEEVTREQ1|')) {
                            if ($isSelf) { continue }
                            $rf = $txt -split '\|'
                            if ($rf.Count -eq 3 -and (Test-PelHmac -Text "$($rf[0])|$($rf[1])" -Signature $rf[2])) {
                                $nowMs = Get-PelNowMs
                                if (($nowMs - $dashState.LastReqMs) -gt 10000) {
                                    $dashState.LastReqMs = $nowMs
                                    Request-PelEventResend
                                }
                            }
                        }
                    }
                } catch { }
            }
            if (($script:PelStatusHbTick % 40) -eq 0) {
                $nowTick = Get-PelNowMs
                foreach ($k in @($script:PelOtherManagers.Keys)) {
                    if (($nowTick - $script:PelOtherManagers[$k].Seen) -gt 25000) { $script:PelOtherManagers.Remove($k) }
                }
            }
            if (($script:PelStatusHbTick % 20) -eq 0) { $script:PelOwnIps = Get-PelLocalIpSet }
            if (($script:PelStatusHbTick % 120) -eq 0) {
                $script:PelMyName = Get-PelDisplayName
                Remove-PelOldEvents
            }
            # Ankündigungen (neu in den nächsten 3 Tagen / Erinnerung 15 Min. vorher / Absage)
            if (($script:PelStatusHbTick % 10) -eq 0) {
                $nextText = Get-PelNextEventText
                $lblNextEvent.Text = $nextText
                if ($nextText -like '*keiner geplant') { $lblNextEvent.ForeColor = [System.Drawing.Color]::LightGray } else { $lblNextEvent.ForeColor = [System.Drawing.Color]::LightGreen }
                $ann = @(Get-PelPendingAnnouncements)
                if ($ann.Count -gt 0) { Show-PelEventAnnouncement -Items $ann -ParentForm $mainForm }
            }
            $n = $script:PelOtherManagers.Count
            if ($n -eq 0) {
                $lblOtherMgrs.Text = "Andere Manager im Netz: keine gefunden"
                $lblOtherMgrs.ForeColor = [System.Drawing.Color]::LightGray
            } else {
                $names = ((@($script:PelOtherManagers.Values) | Select-Object -First 3 | ForEach-Object { "$($_.Name)$(if($_.Zt){' (ZT)'}else{''})" }) -join ', ')
                $lblOtherMgrs.Text = "Andere Manager im Netz: $n  -  $names"
                $lblOtherMgrs.ForeColor = [System.Drawing.Color]::LightGreen
            }
            Update-DashboardPlaying
        } catch { }
    })
    $statPoll.Start()

    $mainForm.Add_FormClosing({
        $statusTimer.Stop(); $pingPoll.Stop(); $statPoll.Stop()
        Stop-PelMailService
        if ($ghCheck.PS) { try { $ghCheck.PS.Stop(); $ghCheck.PS.Dispose() } catch { } }
        if ($ghCheck.Rs) { try { $ghCheck.Rs.Close(); $ghCheck.Rs.Dispose() } catch { } }
        if ($script:PelMailNoteForm -and -not $script:PelMailNoteForm.IsDisposed) { try { $script:PelMailNoteForm.Close() } catch { } }
        if ($statRx) { try { $statRx.Close() } catch { } }
        if ($statTx) { try { $statTx.Close() } catch { } }
        if ($gameDetect.PS) { try { $gameDetect.PS.Stop(); $gameDetect.PS.Dispose() } catch { } }
        if ($gameDetect.Rs) { try { $gameDetect.Rs.Close(); $gameDetect.Rs.Dispose() } catch { } }
        if ($script:PelAnnounceForm -and -not $script:PelAnnounceForm.IsDisposed) { try { $script:PelAnnounceForm.Close() } catch { } }
    })

    Update-DashboardStatus
    Start-DashboardFriendPing
    Update-DashboardMail

    # Per Autostart gestartet: minimiert in die Taskleiste statt mitten auf den Bildschirm.
    if ($script:PelAutostartMode) { $mainForm.WindowState = [System.Windows.Forms.FormWindowState]::Minimized }

    [void]$mainForm.ShowDialog()
}

# ------------------------------------------------------------------------------
# SKRIPT START
# ------------------------------------------------------------------------------
if ($Option) {
    # Getrenntes Fenster: nur die gewählte Option ausführen (jede Option nur einmal gleichzeitig)
    $optMutex = New-Object System.Threading.Mutex($false, "Global\ProjectEarthLan_Option_$Option")
    $gotMutex = $false
    try { $gotMutex = $optMutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $gotMutex = $true }
    if (-not $gotMutex) {
        [System.Windows.Forms.MessageBox]::Show("Option $Option ist bereits in einem anderen Fenster geöffnet.", "Project Earth LAN", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        exit
    }
    Start-PelErrorLogging "Option$Option"
    try {
        switch ($Option) {
            '1'  { Invoke-InstallProjectEarthLan }
            '2'  { Invoke-NetworkLogin }
            '3'  { Invoke-NetworkLogout }
            '4'  { Invoke-GenerateExplanationFile }
            '5'  { Invoke-ToolsModsGames }
            '6'  { Invoke-RemoteDesktopZeroTier }
            '7'  { Invoke-LanGameFinder }
            '8'  { Invoke-ManualGameSearch }
            '9'  { Invoke-ServerManagerBrowser }
            '10' { Invoke-CommCenter }
            '11' { Invoke-FriendsBansMailbox }
            default { Show-MainDashboard }
        }
    } catch {
        $errText = ($Error | Select-Object -First 6 | Out-String)
        Write-PelLog -Level 'ABSTURZ' -Message ("Option ${Option}: " + ($errText -replace '\s+', ' '))
        [System.Windows.Forms.MessageBox]::Show("Option $Option konnte nicht gestartet werden:`n`n$errText", "Project Earth LAN - Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    } finally {
        Stop-PelErrorLogging
        try { $optMutex.ReleaseMutex() } catch { }
    }
} else {
    # Nur EIN Control Center pro PC: läuft schon eins (z. B. minimiert per Autostart),
    # wird es nach vorne geholt statt ein zweites zu öffnen (zwei Control Center würden
    # sich Postfach und Live-Status-Ports streitig machen).
    $ccMutex = $null
    $gotCc = $true
    try {
        $ccMutex = New-Object System.Threading.Mutex($false, 'Global\ProjectEarthLan_ControlCenter')
        try { $gotCc = $ccMutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $gotCc = $true }
    } catch { $gotCc = $true }
    if (-not $gotCc) {
        try { $showEv = [System.Threading.EventWaitHandle]::OpenExisting('Global\ProjectEarthLan_ControlCenter_Show'); [void]$showEv.Set() } catch { }
        exit
    }
    try { $script:PelShowEvent = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, 'Global\ProjectEarthLan_ControlCenter_Show') } catch { $script:PelShowEvent = $null }
    Start-PelErrorLogging 'ControlCenter'
    try {
        Show-MainDashboard
    } catch {
        $errText = ($Error | Select-Object -First 6 | Out-String)
        Write-PelLog -Level 'ABSTURZ' -Message ("Control Center: " + ($errText -replace '\s+', ' '))
        [System.Windows.Forms.MessageBox]::Show("Das Control Center wurde wegen eines Fehlers beendet:`n`n$errText`n`nÜber 'Fehlerlog exportieren' (nach dem Neustart) kannst du die Details weitergeben.", "Project Earth LAN - Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    } finally {
        Stop-PelErrorLogging
        try { if ($ccMutex) { $ccMutex.ReleaseMutex() } } catch { }
    }
}