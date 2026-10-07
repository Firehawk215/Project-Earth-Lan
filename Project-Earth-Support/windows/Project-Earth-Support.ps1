<#
.SYNOPSIS
    Project Earth Support - Live-Fernwartung mit Video-Chat über ein eigenes, verschlüsseltes P2P-Netz.
.DESCRIPTION
    Ein Helfer (dieses Programm oder die Android-App "Project Earth Support") hilft einem Kunden am PC:
      - oben:  Live-Video-Chat mit Ton (Anruf mit Annehmen/Ablehnen)
      - unten: Fernwartung - der Kunde gibt seinen Bildschirm frei, auf Wunsch mit Maus und Tastatur
      - dazu:  Textchat und Datei-Übertragung in beide Richtungen
    Die Verbindung läuft über ein eigenes P2P-Netz (Einladungscode "PES1:...", unabhängig vom
    Project Earth LAN Manager). Das Protokoll der Verbindung ist dasselbe wie dort: Vermittlung,
    UDP Hole Punching, Relay-Fallback, AES-256-CTR + HMAC-SHA256 je Paket.

    Sicherheit und Transparenz:
      - Der Bildschirm wird NUR nach ausdrücklicher Zustimmung des Kunden übertragen, die Steuerung
        nur nach einer zweiten Zustimmung. Solange übertragen wird, steht ein roter Hinweis oben am Bildschirm.
      - Notfall-Stopp für den Kunden: Strg+Umschalt+F12 beendet die Freigabe sofort.
      - Kein unbeaufsichtigter Zugriff, keine versteckten Funktionen, kein Selbst-Update.
      - Einladungscodes werden nur mit DPAPI verschlüsselt gespeichert, Einstellungen atomar geschrieben.
      - Es werden keine Konsolenprogramme gestartet; das eigene Konsolenfenster wird ausgeblendet.

    Dateien: C:\ProgramData\Project-Earth-Support (Einstellungen, Protokolle).
    Ports:   UDP 9892 (eigene P2P-Verbindung), UDP 9890 (Mini-Vermittler, nur wenn er gestartet wird),
             Dienst "Support" im virtuellen Netz: UDP 9891, Kennbyte 0xA8.
.PARAMETER Vermittler
    Startet nur den Mini-Vermittler (kleines Statusfenster). Pro Port eine eigene Instanz.
.PARAMETER Port
    UDP-Port für den Mini-Vermittler (Standard: aus den Einstellungen, sonst 9890).
.PARAMETER Optionen
    Öffnet nur das Optionen-Fenster (eigener Prozess).
.PARAMETER Hilfe
    Öffnet nur das Hilfe-Fenster (eigener Prozess).
.PARAMETER Autostart
    Start durch den Windows-Autostart: Das Programm bleibt im Infobereich neben der Uhr.
.PARAMETER Selbsttest
    Baut alle Fenster einmal auf, prüft die eingebetteten Programmteile und beendet sich wieder
    (für die Build-Prüfung). Das Ergebnis steht im Protokoll und im Rückgabewert.
.PARAMETER Relaunched
    Intern: Das Skript wurde bereits mit den richtigen Rechten neu gestartet.
.NOTES
# Version: 2026.10.07
    Autor: Alexander Meiß
    Start: Rechtsklick -> "Mit PowerShell ausführen" (fordert Admin-Rechte automatisch an)
#>
#Requires -Version 5.1
param(
    [switch]$Vermittler,
    [int]$Port = 0,
    [switch]$Optionen,
    [switch]$Hilfe,
    [switch]$Autostart,
    [switch]$Selbsttest,
    [switch]$Relaunched
)

# ==============================================================================
# 3. START-ABSICHERUNG: Windows PowerShell 5.1, STA, 64 Bit, Administrator
# ==============================================================================
$script:IsCompiledExe = -not ($PSCommandPath -and $PSCommandPath -like '*.ps1')
if ($script:IsCompiledExe) {
    # Als .exe (PS2EXE): die eigene .exe wird direkt neu gestartet, nie über powershell.exe
    try { $script:SelfPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName } catch { $script:SelfPath = $null }
} else {
    $script:SelfPath = $PSCommandPath
}

# Die Argumente dieses Starts (für einen Neustart mit denselben Schaltern)
$script:PesModeArgs = New-Object System.Collections.Generic.List[string]
if ($Vermittler) { $script:PesModeArgs.Add('-Vermittler') }
if ($Port -gt 0) { $script:PesModeArgs.Add('-Port'); $script:PesModeArgs.Add([string]$Port) }
if ($Optionen) { $script:PesModeArgs.Add('-Optionen') }
if ($Hilfe) { $script:PesModeArgs.Add('-Hilfe') }
if ($Autostart) { $script:PesModeArgs.Add('-Autostart') }
if ($Selbsttest) { $script:PesModeArgs.Add('-Selbsttest') }

$script:PesPowerShellExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not [Environment]::Is64BitProcess -and [Environment]::Is64BitOperatingSystem) {
    # Aus einem 32-Bit-Prozess heraus führt nur "sysnative" zur 64-Bit-PowerShell
    $script:PesPowerShellExe = Join-Path $env:WINDIR 'sysnative\WindowsPowerShell\v1.0\powershell.exe'
}

$pesPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$pesIsAdmin = $pesPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$pesIsSta = [Threading.Thread]::CurrentThread.ApartmentState -eq 'STA'
$pesIs64 = [Environment]::Is64BitProcess -or -not [Environment]::Is64BitOperatingSystem
$pesIsCore = $PSVersionTable.PSEdition -eq 'Core'

if (-not $Relaunched) {
    $pesRestart = $false
    if ($script:IsCompiledExe) { if (-not $pesIsAdmin) { $pesRestart = $true } }
    elseif ($pesIsCore -or -not $pesIsSta -or -not $pesIs64 -or -not $pesIsAdmin) { $pesRestart = $true }
    if ($pesRestart) {
        try {
            if ($script:IsCompiledExe) {
                $pesArgs = @($script:PesModeArgs) + @('-Relaunched')
                # Die .exe hat kein Konsolenfenster; "-WindowStyle Hidden" würde hier das Programmfenster selbst verstecken
                Start-Process -FilePath $script:SelfPath -ArgumentList $pesArgs -Verb RunAs
            } else {
                $pesArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', ('"' + $PSCommandPath + '"')) + @($script:PesModeArgs) + @('-Relaunched')
                if ($pesIsAdmin) { Start-Process -FilePath $script:PesPowerShellExe -ArgumentList $pesArgs -WindowStyle Hidden }
                else { Start-Process -FilePath $script:PesPowerShellExe -ArgumentList $pesArgs -Verb RunAs -WindowStyle Hidden }
            }
        } catch {
            # Die Abfrage der Administrator-Rechte wurde abgelehnt
            Add-Type -AssemblyName System.Windows.Forms
            [void][System.Windows.Forms.MessageBox]::Show('Project Earth Support braucht Administrator-Rechte (Firewall-Regel, Steuerung von Programmen mit erhöhten Rechten). Bitte erneut starten und die Abfrage bestätigen.', 'Project Earth Support', 'OK', 'Warning')
        }
        exit
    }
} elseif (-not $pesIsAdmin) {
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show('Project Earth Support konnte nicht mit Administrator-Rechten gestartet werden.', 'Project Earth Support', 'OK', 'Warning')
    exit
}

# Eigenes Konsolenfenster ausblenden (fest eingebaut, kein Schalter) - auch bei "Mit PowerShell ausführen"
try {
    Add-Type -Namespace PesBoot -Name Con -MemberDefinition '[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow(); [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);'
    $pesCon = [PesBoot.Con]::GetConsoleWindow()
    if ($pesCon -ne [IntPtr]::Zero) { [void][PesBoot.Con]::ShowWindow($pesCon, 0) }
} catch { }

# ==============================================================================
# 4. ASSEMBLIES
# ==============================================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Security
[System.Windows.Forms.Application]::EnableVisualStyles()

# ==============================================================================
# 5. KONFIGURATION UND GLOBALE VARIABLEN
# ==============================================================================
$script:PesVersion = '2026.10.07'
$script:PesTitle = 'Project Earth Support'
$script:PesDataDir = Join-Path $env:ProgramData 'Project-Earth-Support'
$script:PesLogDir = Join-Path $script:PesDataDir 'logs'
$script:PesSettingsPath = Join-Path $script:PesDataDir 'settings.json'
$script:PesDefaultRvPort = 9890          # Mini-Vermittler (UDP)
$script:PesDefaultUdpPort = 9892         # eigene P2P-Verbindung (UDP)
$script:PesTaskName = 'Project Earth Support Autostart'
$script:PesFirewallPrefix = 'Project Earth Support'
$script:PesLogContext = 'support'
$script:NL = [Environment]::NewLine

# Designsystem (ein Farbsatz für alle Project-Earth-Programme)
$script:C = @{
    Bg         = [System.Drawing.Color]::FromArgb(30, 30, 30)       # 1E1E1E
    Surface    = [System.Drawing.Color]::FromArgb(45, 45, 45)       # 2D2D2D
    Field      = [System.Drawing.Color]::FromArgb(40, 40, 40)       # 282828
    Border     = [System.Drawing.Color]::FromArgb(70, 70, 70)       # 464646
    Text       = [System.Drawing.Color]::FromArgb(241, 241, 241)    # F1F1F1
    Muted      = [System.Drawing.Color]::FromArgb(170, 178, 190)    # AAB2BE
    Accent     = [System.Drawing.Color]::FromArgb(0, 120, 215)      # 0078D7
    AccentText = [System.Drawing.Color]::FromArgb(58, 150, 221)     # 3A96DD
    Ok         = [System.Drawing.Color]::FromArgb(0, 135, 70)       # 008746
    OkText     = [System.Drawing.Color]::FromArgb(78, 201, 176)     # 4EC9B0
    Warn       = [System.Drawing.Color]::FromArgb(255, 170, 60)     # FFAA3C
    Err        = [System.Drawing.Color]::FromArgb(244, 135, 113)    # F48771
    Danger     = [System.Drawing.Color]::FromArgb(160, 50, 40)      # A03228
}
$script:FontUi = New-Object System.Drawing.Font('Segoe UI', 9.5)
$script:FontBold = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$script:FontSmall = New-Object System.Drawing.Font('Segoe UI', 8.5)
$script:FontBig = New-Object System.Drawing.Font('Segoe UI', 13)
$script:FontMono = New-Object System.Drawing.Font('Consolas', 9)

$script:PesSettings = $null
$script:PesHost = $null
$script:PesJobs = New-Object System.Collections.ArrayList

# ==============================================================================
# 6. HILFSFUNKTIONEN
# ==============================================================================

# ---- Protokoll (Datei, Rotation bei 1 MB; darf nie abstürzen; nie Codes oder Passwörter) ----
function Write-PesLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        if (-not [System.IO.Directory]::Exists($script:PesLogDir)) { [void][System.IO.Directory]::CreateDirectory($script:PesLogDir) }
        $file = Join-Path $script:PesLogDir ($script:PesLogContext + '.log')
        if ([System.IO.File]::Exists($file) -and (New-Object System.IO.FileInfo($file)).Length -gt 1MB) {
            $old = $file + '.1'
            if ([System.IO.File]::Exists($old)) { [System.IO.File]::Delete($old) }
            [System.IO.File]::Move($file, $old)
        }
        $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
        [System.IO.File]::AppendAllText($file, $line + $script:NL, [System.Text.Encoding]::UTF8)
    } catch { }
}

# ---- Einstellungen: JSON, atomar geschrieben (Temp-Datei -> Replace/Move) ----
function Write-PesTextFileAtomic {
    param([string]$Path, [string]$Text)
    $dir = [System.IO.Path]::GetDirectoryName($Path)
    if (-not [System.IO.Directory]::Exists($dir)) { [void][System.IO.Directory]::CreateDirectory($dir) }
    $tmp = $Path + '.tmp'
    [System.IO.File]::WriteAllText($tmp, $Text, (New-Object System.Text.UTF8Encoding($false)))
    # [NullString]::Value statt $null - sonst lehnt File.Replace den Sicherungspfad ab
    if ([System.IO.File]::Exists($Path)) { [System.IO.File]::Replace($tmp, $Path, [NullString]::Value) }
    else { [System.IO.File]::Move($tmp, $Path) }
}

function Get-PesDefaultSettings {
    $dl = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads\Project Earth Support'
    return [ordered]@{
        Name            = [string]$env:COMPUTERNAME
        Language        = 'de'
        Role            = 'Kunde'
        AdapterName     = ''
        UdpPort         = $script:PesDefaultUdpPort
        ServerAddress   = ''
        InviteEnc       = ''
        RememberInvite  = $true
        MicDevice       = ''
        SpeakerDevice   = ''
        Camera          = ''
        CameraFlip      = $false
        EchoGate        = $true
        DownloadDir     = $dl
        Quality         = 2
        MinimizeToTray  = $false
        MachineKey      = ''
        RvPort          = $script:PesDefaultRvPort
        RvAutostart     = $false
    }
}

function Read-PesSettings {
    $s = Get-PesDefaultSettings
    try {
        if ([System.IO.File]::Exists($script:PesSettingsPath)) {
            $j = [System.IO.File]::ReadAllText($script:PesSettingsPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            foreach ($k in @($s.Keys)) {
                $p = $j.PSObject.Properties[$k]
                if ($null -eq $p -or $null -eq $p.Value) { continue }
                # Nur bekannte Schlüssel mit passendem Typ übernehmen
                if ($s[$k] -is [bool]) { $s[$k] = [bool]$p.Value }
                elseif ($s[$k] -is [int]) { $n = 0; if ([int]::TryParse([string]$p.Value, [ref]$n)) { $s[$k] = $n } }
                else { $s[$k] = [string]$p.Value }
            }
        }
    } catch { Write-PesLog -Level 'FEHLER' -Message ('Einstellungen konnten nicht gelesen werden: ' + $_.Exception.Message) }
    if ($s.UdpPort -lt 1024 -or $s.UdpPort -gt 65535) { $s.UdpPort = $script:PesDefaultUdpPort }
    if ($s.RvPort -lt 1 -or $s.RvPort -gt 65535) { $s.RvPort = $script:PesDefaultRvPort }
    if ($s.Quality -lt 1 -or $s.Quality -gt 3) { $s.Quality = 2 }
    if ($s.Language -ne 'en') { $s.Language = 'de' }
    if ($s.Role -ne 'Helfer') { $s.Role = 'Kunde' }
    if ([string]::IsNullOrWhiteSpace($s.Name)) { $s.Name = [string]$env:COMPUTERNAME }
    if ($s.MachineKey -notmatch '^[0-9a-f]{32}$') {
        # Geräteschlüssel: sorgt nur dafür, dass dieser PC beim Vermittler immer dieselbe virtuelle Adresse bekommt
        $b = New-Object byte[] 16
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try { $rng.GetBytes($b) } finally { $rng.Dispose() }
        $s.MachineKey = -join ($b | ForEach-Object { $_.ToString('x2') })
        try { Write-PesTextFileAtomic -Path $script:PesSettingsPath -Text ($s | ConvertTo-Json) } catch { }
    }
    return $s
}

function Save-PesSettings {
    try { Write-PesTextFileAtomic -Path $script:PesSettingsPath -Text ($script:PesSettings | ConvertTo-Json) }
    catch { Write-PesLog -Level 'FEHLER' -Message ('Einstellungen konnten nicht gespeichert werden: ' + $_.Exception.Message) }
}

# ---- Geheimnisse (Einladungscode enthält das Sitzungs-Passwort): nur per DPAPI gespeichert ----
function Protect-PesText {
    param([string]$Plain)
    if ([string]::IsNullOrEmpty($Plain)) { return '' }
    try {
        $b = [System.Text.Encoding]::UTF8.GetBytes($Plain)
        $p = [System.Security.Cryptography.ProtectedData]::Protect($b, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        return [Convert]::ToBase64String($p)
    } catch { return '' }
}

function Unprotect-PesText {
    param([string]$Enc)
    if ([string]::IsNullOrEmpty($Enc)) { return '' }
    try {
        $p = [System.Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($Enc), $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        return [System.Text.Encoding]::UTF8.GetString($p)
    } catch { return '' }
}

# ---- Hintergrundarbeit in Runspaces (kein Start-Job, kein Fremdprozess); Ergebnis holt der Timer ab ----
function Start-PesJob {
    param([string]$Name, [scriptblock]$Script, [object[]]$Arguments = @(), [scriptblock]$OnDone = $null)
    try {
        $ps = [powershell]::Create()
        [void]$ps.AddScript($Script.ToString())
        foreach ($a in $Arguments) { [void]$ps.AddArgument($a) }
        $h = $ps.BeginInvoke()
        [void]$script:PesJobs.Add([pscustomobject]@{ Name = $Name; Ps = $ps; Handle = $h; OnDone = $OnDone })
    } catch { Write-PesLog -Level 'FEHLER' -Message ("Hintergrundaufgabe '$Name': " + $_.Exception.Message) }
}

function Receive-PesJobs {
    for ($i = $script:PesJobs.Count - 1; $i -ge 0; $i--) {
        $j = $script:PesJobs[$i]
        if (-not $j.Handle.IsCompleted) { continue }
        $res = $null
        try { $res = $j.Ps.EndInvoke($j.Handle) } catch { $res = 'Fehler: ' + $_.Exception.Message }
        try { $j.Ps.Dispose() } catch { }
        $script:PesJobs.RemoveAt($i)
        $text = [string]($res | Select-Object -Last 1)
        Write-PesLog -Message ("Hintergrundaufgabe '" + $j.Name + "': " + $text)
        if ($j.OnDone) { try { & $j.OnDone $text } catch { } }
    }
}

# ---- Firewall: pro Dienst eine Regel "Project Earth Support ... (UDP <Port>)" ----
$script:PesFirewallAddScript = {
    param([string]$Name, [int]$UdpPort, [string]$Description)
    try {
        $r = Get-NetFirewallRule -DisplayName $Name -ErrorAction SilentlyContinue
        if ($r) { return 'vorhanden' }
        $p = @{ DisplayName = $Name; Direction = 'Inbound'; Action = 'Allow'; Protocol = 'UDP'; LocalPort = $UdpPort; Profile = 'Any'; Description = $Description }
        [void](New-NetFirewallRule @p -ErrorAction Stop)
        return 'angelegt'
    } catch { return 'Fehler: ' + $_.Exception.Message }
}

$script:PesFirewallRemoveScript = {
    param([string]$Prefix)
    try {
        $n = 0
        foreach ($r in @(Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like ($Prefix + '*') })) {
            Remove-NetFirewallRule -Name $r.Name -ErrorAction SilentlyContinue
            $n++
        }
        return ('entfernt: ' + $n)
    } catch { return 'Fehler: ' + $_.Exception.Message }
}

function Add-PesFirewallRule {
    param([string]$Service, [int]$UdpPort)
    $name = if ([string]::IsNullOrEmpty($Service)) { '{0} (UDP {1})' -f $script:PesFirewallPrefix, $UdpPort } else { '{0} {1} (UDP {2})' -f $script:PesFirewallPrefix, $Service, $UdpPort }
    Start-PesJob -Name ('Firewall-Regel ' + $name) -Script $script:PesFirewallAddScript -Arguments @($name, $UdpPort, 'Project Earth Support: eingehende P2P-Verbindungen (UDP)')
}

# ---- Autostart: geplante Aufgabe bei der Anmeldung, versteckt, mit höchsten Rechten ----
$script:PesTaskScript = {
    param([bool]$Enable, [string]$TaskName, [string]$Exe, [string]$Arguments)
    try {
        if (-not $Enable) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
            return 'entfernt'
        }
        $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        if ([string]::IsNullOrEmpty($Arguments)) { $action = New-ScheduledTaskAction -Execute $Exe }
        else { $action = New-ScheduledTaskAction -Execute $Exe -Argument $Arguments }
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
        $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
        $p = @{ TaskName = $TaskName; Action = $action; Trigger = $trigger; Principal = $principal; Settings = $settings; Description = 'Startet Project Earth Support bei der Anmeldung im Infobereich.' }
        [void](Register-ScheduledTask @p -Force -ErrorAction Stop)
        return 'angelegt'
    } catch { return 'Fehler: ' + $_.Exception.Message }
}

function Test-PesAutostart {
    try { return [bool](Get-ScheduledTask -TaskName $script:PesTaskName -ErrorAction SilentlyContinue) } catch { return $false }
}

# Startet dieses Programm noch einmal mit anderen Schaltern (Optionen, Hilfe, Vermittler) - immer ohne Konsolenfenster.
function Start-PesSelf {
    param([string[]]$ModeArgs)
    try {
        $extra = @($ModeArgs) + @('-Relaunched')
        if ($script:IsCompiledExe) { return Start-Process -FilePath $script:SelfPath -ArgumentList $extra -PassThru }
        $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', ('"' + $script:SelfPath + '"')) + $extra
        return Start-Process -FilePath $script:PesPowerShellExe -ArgumentList $a -WindowStyle Hidden -PassThru
    } catch {
        Write-PesLog -Level 'FEHLER' -Message ('Unterfenster konnte nicht gestartet werden: ' + $_.Exception.Message)
        return $null
    }
}

# ---- Zentrale Adapterauswahl: Name wird gespeichert, die IPv4-Adresse bei jedem Verbinden neu ermittelt ----
function Get-PesAdapterList {
    $list = New-Object System.Collections.ArrayList
    try {
        foreach ($ni in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
            if ($ni.OperationalStatus -ne [System.Net.NetworkInformation.OperationalStatus]::Up) { continue }
            if ($ni.NetworkInterfaceType -eq [System.Net.NetworkInformation.NetworkInterfaceType]::Loopback) { continue }
            foreach ($ua in $ni.GetIPProperties().UnicastAddresses) {
                if ($ua.Address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { continue }
                $ip = $ua.Address.ToString()
                if ($ip.StartsWith('169.254.')) { continue }
                [void]$list.Add([pscustomobject]@{ Name = $ni.Name; Ip = $ip; Text = ($ni.Name + '  -  ' + $ip) })
                break
            }
        }
    } catch { }
    return ,$list
}

# Liefert die IPv4-Adresse des gewählten Adapters oder '' (= automatisch, alle Adapter).
function Get-PesBindIp {
    $want = [string]$script:PesSettings.AdapterName
    if ([string]::IsNullOrEmpty($want)) { return '' }
    foreach ($a in (Get-PesAdapterList)) { if ($a.Name -eq $want) { return $a.Ip } }
    Write-PesLog -Level 'WARNUNG' -Message ("Gewählter Netzwerkadapter '" + $want + "' ist nicht aktiv - nutze automatisch alle Adapter.")
    return ''
}

function Get-PesDeviceIndex {
    param([string[]]$Names, [string]$Want)
    if ([string]::IsNullOrEmpty($Want)) { return -1 }
    for ($i = 0; $i -lt $Names.Count; $i++) { if ($Names[$i] -eq $Want) { return $i } }
    return -1
}

function Format-PesSize {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
    return ('{0} B' -f $Bytes)
}

# ==============================================================================
# 6b. C#-INLINE-KLASSEN (P2P-Kern, Sitzung, Windows-Teil, Sprache) - ein Block, einmal geladen
# ==============================================================================
$script:PesCode = @'
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing;
using System.IO;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Net;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using System;

// ============================================================================
// Project Earth Support - P2P-Kern (uebernommen aus dem Project Earth LAN Manager)
//   PesBytes       : Big-Endian-Helfer
//   PesP2pCrypto   : AES-256-CTR + HMAC-SHA256 (Encrypt-then-MAC), 16 Byte Tag
//   PesP2pEngine   : Signaling-Client, UDP Hole Punching, Relay-Fallback
// Das Protokoll (Magic 'PS'/'PE', Schluesselableitung, Lobby-ID) ist unveraendert.
// Statt eines virtuellen Netzwerkadapters gibt es SendIp() und InboundSink (IPv4-Pakete).
// Bewusst C# 5 (Windows PowerShell 5.1 / Add-Type / PS2EXE kompatibel).
// ============================================================================

public static class PesBytes
{
    public static uint ReadU32(byte[] b, int o) { return ((uint)b[o] << 24) | ((uint)b[o + 1] << 16) | ((uint)b[o + 2] << 8) | b[o + 3]; }
    public static void WriteU32(byte[] b, int o, uint v) { b[o] = (byte)(v >> 24); b[o + 1] = (byte)(v >> 16); b[o + 2] = (byte)(v >> 8); b[o + 3] = (byte)v; }
    public static int ReadU16(byte[] b, int o) { return (b[o] << 8) | b[o + 1]; }
    public static void WriteU16(byte[] b, int o, int v) { b[o] = (byte)(v >> 8); b[o + 1] = (byte)v; }
    public static ulong ReadU64(byte[] b, int o) { return ((ulong)ReadU32(b, o) << 32) | ReadU32(b, o + 4); }
    public static void WriteU64(byte[] b, int o, ulong v) { WriteU32(b, o, (uint)(v >> 32)); WriteU32(b, o + 4, (uint)v); }
    public static string IpToString(uint ip) { return (ip >> 24) + "." + ((ip >> 16) & 255) + "." + ((ip >> 8) & 255) + "." + (ip & 255); }
    public static uint IpToUInt(IPAddress a) { return ReadU32(a.GetAddressBytes(), 0); }
    public static IPAddress UIntToIp(uint v) { byte[] b = new byte[4]; WriteU32(b, 0, v); return new IPAddress(b); }
    public static bool IsPrivate(IPAddress a)
    {
        byte[] b = a.GetAddressBytes();
        if (b.Length != 4) return false;
        return b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) || (b[0] == 192 && b[1] == 168) || (b[0] == 100 && b[1] >= 64 && b[1] <= 127);
    }
    public static byte[] Utf8Limit(string s, int maxBytes)
    {
        if (s == null) s = "";
        while (s.Length > 0 && Encoding.UTF8.GetByteCount(s) > maxBytes) s = s.Substring(0, s.Length - 1);
        return Encoding.UTF8.GetBytes(s);
    }
}

// ----------------------------------------------------------------------------
// Paketformat Peer <-> Peer (alles nach dem Header ist verschluesselt):
//   [0..1]  Magic 'P''E'   [2] Typ   [3..10] Absender-NodeId   [11..14] Seq
//   [15..]  AES-256-CTR(Nutzdaten)    [letzte 16] HMAC-SHA256(Header+Chiffrat)
// CTR-Zaehlerblock = NodeId(8) | Seq(4) | Blocknummer(4) -> nie doppelt, weil jede
// Sitzung eine neue Zufalls-NodeId bekommt und Seq pro Paket hochzaehlt.
// Eine Instanz pro Thread verwenden (HMAC/ICryptoTransform sind nicht threadsicher).
// ----------------------------------------------------------------------------
public sealed class PesP2pCrypto
{
    public const int Hdr = 15;
    public const int Tag = 16;
    private readonly ICryptoTransform ecb;
    private readonly HMACSHA256 mac;

    public PesP2pCrypto(byte[] encKey, byte[] macKey)
    {
        Aes aes = Aes.Create();
        aes.Mode = CipherMode.ECB;
        aes.Padding = PaddingMode.None;
        aes.Key = encKey;
        ecb = aes.CreateEncryptor();
        mac = new HMACSHA256(macKey);
    }

    private void Ctr(ulong node, uint seq, byte[] src, int srcOff, byte[] dst, int dstOff, int len)
    {
        if (len <= 0) return;
        int blocks = (len + 15) / 16;
        byte[] ctr = new byte[blocks * 16];
        for (int b = 0; b < blocks; b++)
        {
            int o = b * 16;
            PesBytes.WriteU64(ctr, o, node);
            PesBytes.WriteU32(ctr, o + 8, seq);
            PesBytes.WriteU32(ctr, o + 12, (uint)b);
        }
        byte[] ks = new byte[ctr.Length];
        ecb.TransformBlock(ctr, 0, ctr.Length, ks, 0);
        for (int i = 0; i < len; i++) dst[dstOff + i] = (byte)(src[srcOff + i] ^ ks[i]);
    }

    public byte[] Seal(byte type, ulong node, uint seq, byte[] body, int off, int len)
    {
        byte[] p = new byte[Hdr + len + Tag];
        p[0] = 0x50; p[1] = 0x45; p[2] = type;
        PesBytes.WriteU64(p, 3, node);
        PesBytes.WriteU32(p, 11, seq);
        Ctr(node, seq, body, off, p, Hdr, len);
        byte[] h = mac.ComputeHash(p, 0, Hdr + len);
        Buffer.BlockCopy(h, 0, p, Hdr + len, Tag);
        return p;
    }

    // Liefert die entschluesselten Nutzdaten oder null (falscher Schluessel / manipuliert).
    public byte[] Open(byte[] buf, int off, int len, out byte type, out ulong node, out uint seq)
    {
        type = 0; node = 0; seq = 0;
        if (len < Hdr + Tag || buf[off] != 0x50 || buf[off + 1] != 0x45) return null;
        int bodyLen = len - Hdr - Tag;
        byte[] h = mac.ComputeHash(buf, off, Hdr + bodyLen);
        int diff = 0;
        for (int i = 0; i < Tag; i++) diff |= h[i] ^ buf[off + Hdr + bodyLen + i];
        if (diff != 0) return null;
        type = buf[off + 2];
        node = PesBytes.ReadU64(buf, off + 3);
        seq = PesBytes.ReadU32(buf, off + 11);
        byte[] body = new byte[bodyLen];
        Ctr(node, seq, buf, off + Hdr, body, 0, bodyLen);
        return body;
    }
}

public sealed class PesP2pPeer
{
    public ulong NodeId;
    public string Name = "";
    public uint Vip;
    public IPEndPoint PublicEp;
    public List<IPEndPoint> LocalEps = new List<IPEndPoint>();
    public volatile IPEndPoint DirectEp;   // bestaetigter direkter Weg (nach Hole Punching)
    public volatile int Path;              // 0 = verbinde / punching, 1 = direkt, 2 = relay
    public long LastRxMs;
    public long LastHelloMs;
    public long LastRelayHelloMs;
    public long PunchStartMs;
    public volatile int RttMs = -1;
    public long RxBytes;
    public long TxBytes;
    public volatile int AuthFails;
    public volatile bool InServerList = true;
    public bool HasRev;          // Info kam ueber Erweiterung E2 (mit Revision)
    public uint InfoRev;         // Lobby-Revision dieser Info
    public bool Punching;        // Hole Punching hat tatsaechlich begonnen (fuer den Relay-Timer)
    // Replay-Schutz (Sliding Window, 64 Pakete)
    public bool AnySeq;
    public uint MaxSeq;
    public ulong Window;
}

public sealed class PesP2pPeerInfo
{
    public string Name;
    public string Ip;
    public string Mode;
    public string Endpoint;
    public int RttMs;
    public long RxBytes;
    public long TxBytes;
    public ulong NodeId;
    public uint Vip;
    public int Path;
}

public sealed class PesP2pEngine
{
    // ---- Protokoll-Konstanten -------------------------------------------------
    public const byte ProtoVersion = 1;
    private const byte T_HELLO = 1, T_HELLO_ACK = 2, T_DATA = 4, T_BYE = 5;
    private const byte S_REGISTER = 0x10, S_LEAVE = 0x11, S_RELAY = 0x12;
    private const byte S_WELCOME = 0x20, S_PEER = 0x21, S_RELAYED = 0x22, S_ERROR = 0x23, S_MEMBERS = 0x24;
    private const byte S_SYNC = 0x25, S_PEER2 = 0x26, S_GONE = 0x27, EXT_V2 = 0xE2;
    private const int SIO_UDP_CONNRESET = -1744830452;
    // Hole Punching: hoechstens so viele Mitspieler je 200-ms-Takt anpingen (bei 500 Leuten in
    // einer Lobby wuerde sonst jeder neue Mitspieler seinen Upload und den Router fluten)
    public int PunchBudgetPerTick = 120;

    // ---- Einstellungen (vor Start() setzbar) ------------------------------------
    public int PreferredPort = 9892;       // fester Port = feste Firewall-Regel / optionale Portweiterleitung
    public IPAddress BindAddress = IPAddress.Any;   // zentrale Adapterauswahl: nur ueber diesen Adapter senden/empfangen
    public volatile Action<byte[]> InboundSink;     // geprueft eingehende IPv4-Pakete (statt Adapter)
    public bool AllowRelay = true;         // Fallback ueber den Vermittlungsserver bei symmetrischem NAT
    // Broadcast-Firewall: Hintergrund-"Laerm" von Windows, Linux und macOS (Namensdienste,
    // Geraetesuche, App-Suchfunktionen) wird weder gesendet noch angenommen. Laesst sich
    // zur Laufzeit per SetNoiseFilter() umstellen (GUI: "Broadcast-Firewall").
    private volatile HashSet<int> noisePorts = new HashSet<int>(new int[] { 5353, 5355, 137, 138, 1900, 3702, 67, 68, 17500, 57621, 1716, 21027, 427, 8611, 8612, 161 });
    private volatile bool noiseEnabled = true, noiseIgmp = true, noiseStrict = true;
    private readonly ConcurrentDictionary<int, long> noiseStats = new ConcurrentDictionary<int, long>();
    private long noiseBlocked;
    public long NoiseBlocked { get { return Interlocked.Read(ref noiseBlocked); } }
    public bool NoiseFilterEnabled { get { return noiseEnabled; } }

    public void SetNoiseFilter(bool enabled, int[] udpPorts, bool blockIgmp, bool strict)
    {
        HashSet<int> h = new HashSet<int>();
        if (udpPorts != null) foreach (int x in udpPorts) if (x > 0 && x < 65536) h.Add(x);
        noisePorts = h;
        noiseIgmp = blockIgmp;
        noiseStrict = strict;
        noiseEnabled = enabled;
    }

    public void ResetNoiseStats() { noiseStats.Clear(); Interlocked.Exchange(ref noiseBlocked, 0); }

    // "5353=120;137=40;-2=7" (-2 = IGMP), sortiert nach Anzahl
    public string GetNoiseStats()
    {
        List<KeyValuePair<int, long>> l = new List<KeyValuePair<int, long>>(noiseStats);
        l.Sort(delegate (KeyValuePair<int, long> a, KeyValuePair<int, long> b) { return b.Value.CompareTo(a.Value); });
        StringBuilder sb = new StringBuilder();
        foreach (KeyValuePair<int, long> kv in l) sb.Append(kv.Key).Append('=').Append(kv.Value).Append(';');
        return sb.ToString();
    }
    public int PunchTimeoutMs = 8000;      // so lange Hole Punching, bevor Relay genutzt wird
    public int PeerTimeoutMs = 20000;      // ohne Lebenszeichen -> Verbindung neu aufbauen

    // ---- Status (von PowerShell per Timer gelesen) ------------------------------
    private volatile string state = "Getrennt";
    public string State { get { return state; } }
    public volatile string LastError = "";
    public volatile string AssignedIp = "";
    public volatile int PrefixLength = 16;
    public volatile string PublicEndpoint = "";
    public volatile bool IpChanged = false;
    public volatile bool ServerReachable = false;
    public int LocalPort { get { return localPort; } }
    public bool IsRunning { get { return running; } }
    public uint Vip { get { return vip; } }
    public ulong OwnNodeId { get { return nodeId; } }
    public int PeerCount { get { lock (sync) { return byNode.Count; } } }
    public readonly ConcurrentQueue<string> Log = new ConcurrentQueue<string>();

    // ---- intern -----------------------------------------------------------------
    private readonly object sync = new object();
    private readonly Dictionary<ulong, PesP2pPeer> byNode = new Dictionary<ulong, PesP2pPeer>();
    private readonly Dictionary<uint, PesP2pPeer> byVip = new Dictionary<uint, PesP2pPeer>();
    private static readonly Stopwatch clock = Stopwatch.StartNew();
    private Socket sock;
    private readonly object tunLock = new object();
    private ManualResetEvent stopEvent;
    private Thread udpThread, maintThread;
    private volatile bool stopping, running;
    private PesP2pCrypto cTun, cUdp, cMaint;
    private byte[] lobbyId, machineKey;
    private ulong nodeId;
    private string displayName = "", serverHost = "";
    private int serverPort, localPort;
    private volatile IPEndPoint serverEp;
    private long lastResolveMs = -1000000, lastRegTxMs = -1000000, lastServerRxMs = 0;
    private volatile bool gotWelcome;
    private long lastGoneCleanMs;
    private volatile uint vip, mask, bcast;
    private int seqCounter;
    private byte[] cookie = new byte[8];                 // Anti-Spoofing-Cookie vom Server
    // Erweiterung E2: Abgleich der Mitgliederliste (nur im Empfangs-Thread benutzt)
    private uint syncRev;
    private int syncTotal;
    private readonly HashSet<ulong> syncIds = new HashSet<ulong>();
    private readonly Dictionary<ulong, KeyValuePair<uint, long>> gone = new Dictionary<ulong, KeyValuePair<uint, long>>();

    private static long Now() { return clock.ElapsedMilliseconds; }

    private void AddLog(string text)
    {
        Log.Enqueue(DateTime.Now.ToString("HH:mm:ss") + "  " + text);
        string dummy;
        while (Log.Count > 400 && Log.TryDequeue(out dummy)) { }
    }

    private void SetState(string s) { if (state != s) { state = s; AddLog("Status: " + s); } }

    private uint NextSeq() { return (uint)Interlocked.Increment(ref seqCounter); }

    // Lobby-Schluessel: PBKDF2 (100.000 Runden) aus Passwort + Lobbyname.
    // Der Server sieht nur die LobbyId (Hash des Namens) - nie Passwort oder Schluessel.
    public static byte[] DeriveLobbyId(string lobbyName)
    {
        using (SHA256 sha = SHA256.Create())
        {
            byte[] h = sha.ComputeHash(Encoding.UTF8.GetBytes("PEL-LOBBY-V1|" + lobbyName.Trim().ToLowerInvariant()));
            byte[] id = new byte[16];
            Buffer.BlockCopy(h, 0, id, 0, 16);
            return id;
        }
    }

    // =========================================================================
    // START
    // =========================================================================
    public void Start(string serverHostName, int serverUdpPort, string lobbyName, string password,
                      string myName, string machineKeyHex)
    {
        if (running) throw new InvalidOperationException("P2P laeuft bereits.");
        if (string.IsNullOrEmpty(lobbyName) || lobbyName.Trim().Length < 3) throw new ArgumentException("Der Lobby-Name muss mindestens 3 Zeichen haben.");
        if (string.IsNullOrEmpty(password) || password.Length < 6) throw new ArgumentException("Das Lobby-Passwort muss mindestens 6 Zeichen haben.");
        if (string.IsNullOrEmpty(serverHostName)) throw new ArgumentException("Kein Vermittlungsserver eingetragen.");

        stopping = false; gotWelcome = false; ServerReachable = false; IpChanged = false;
        vip = 0; mask = 0; bcast = 0; AssignedIp = ""; PublicEndpoint = ""; LastError = "";
        lastResolveMs = -1000000; lastRegTxMs = -1000000; lastServerRxMs = 0; serverEp = null;
        cookie = new byte[8];
        lock (sync) { byNode.Clear(); byVip.Clear(); }

        serverHost = serverHostName.Trim(); serverPort = serverUdpPort;
        displayName = string.IsNullOrEmpty(myName) ? Environment.MachineName : myName;

        // Schluessel ableiten
        SetState("Schluessel werden abgeleitet ...");
        lobbyId = DeriveLobbyId(lobbyName);
        byte[] salt = Encoding.UTF8.GetBytes("PEL-P2P-V1|" + lobbyName.Trim().ToLowerInvariant());
        byte[] km;
        using (Rfc2898DeriveBytes kdf = new Rfc2898DeriveBytes(password, salt, 100000)) { km = kdf.GetBytes(64); }
        byte[] encKey = new byte[32], macKey = new byte[32];
        Buffer.BlockCopy(km, 0, encKey, 0, 32);
        Buffer.BlockCopy(km, 32, macKey, 0, 32);
        cTun = new PesP2pCrypto(encKey, macKey);
        cUdp = new PesP2pCrypto(encKey, macKey);
        cMaint = new PesP2pCrypto(encKey, macKey);

        machineKey = new byte[16];
        if (!string.IsNullOrEmpty(machineKeyHex) && machineKeyHex.Length == 32)
        {
            for (int i = 0; i < 16; i++) machineKey[i] = Convert.ToByte(machineKeyHex.Substring(i * 2, 2), 16);
        }
        byte[] rnd = new byte[8];
        using (RandomNumberGenerator rng = RandomNumberGenerator.Create())
        {
            do { rng.GetBytes(rnd); nodeId = PesBytes.ReadU64(rnd, 0); } while (nodeId == 0);
            if (string.IsNullOrEmpty(machineKeyHex)) rng.GetBytes(machineKey);
            byte[] s4 = new byte[4]; rng.GetBytes(s4); seqCounter = (int)(PesBytes.ReadU32(s4, 0) & 0x0FFFFFFF);
        }

        stopEvent = new ManualResetEvent(false);

        // UDP-Socket (ein Socket fuer Server UND alle Peers -> gleiche NAT-Zuordnung)
        try
        {
            sock = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
            try { sock.IOControl(SIO_UDP_CONNRESET, new byte[] { 0, 0, 0, 0 }, null); } catch { }
            IPAddress bindIp = BindAddress == null ? IPAddress.Any : BindAddress;
            try { sock.Bind(new IPEndPoint(bindIp, PreferredPort)); }
            catch (SocketException)
            {
                AddLog("UDP-Port " + PreferredPort + " ist belegt - nutze einen zufaelligen Port.");
                sock.Bind(new IPEndPoint(bindIp, 0));
            }
            sock.ReceiveTimeout = 1000;
            sock.ReceiveBufferSize = 1 << 20;
            sock.SendBufferSize = 1 << 20;
            localPort = ((IPEndPoint)sock.LocalEndPoint).Port;
        }
        catch
        {
            try { if (sock != null) sock.Close(); } catch { }
            throw;
        }

        running = true;
        AddLog("Lokaler UDP-Port: " + localPort);
        SetState("Verbinde mit Vermittlungsserver ...");
        udpThread = new Thread(UdpLoop); udpThread.IsBackground = true; udpThread.Name = "PES-P2P-UDP"; udpThread.Start();
        maintThread = new Thread(MaintLoop); maintThread.IsBackground = true; maintThread.Name = "PES-P2P-MAINT"; maintThread.Start();
    }

    // =========================================================================
    // STOP
    // =========================================================================
    public void Stop()
    {
        if (!running) return;
        stopping = true;
        try { stopEvent.Set(); } catch { }
        if (maintThread != null) maintThread.Join(3000);
        // Abmelden: Peers und Server sofort informieren (sonst erst nach Timeout)
        try
        {
            byte[] empty = new byte[0];
            foreach (PesP2pPeer p in SnapshotPeers())
            {
                byte[] bye = cMaint.Seal(T_BYE, nodeId, NextSeq(), empty, 0, 0);
                IPEndPoint d = p.DirectEp;
                if (p.Path == 1 && d != null) SendRaw(bye, d);
                else if (p.Path == 2) SendRelay(p.NodeId, bye);
            }
            IPEndPoint se = serverEp;
            if (se != null)
            {
                byte[] lv = new byte[3 + 16 + 8];
                lv[0] = 0x50; lv[1] = 0x53; lv[2] = S_LEAVE;
                Buffer.BlockCopy(lobbyId, 0, lv, 3, 16);
                PesBytes.WriteU64(lv, 19, nodeId);
                SendRaw(lv, se);
            }
        }
        catch { }
        try { sock.Close(); } catch { }
        if (udpThread != null) udpThread.Join(3000);
        running = false;
        ServerReachable = false;
        AssignedIp = "";
        lock (sync) { byNode.Clear(); byVip.Clear(); }
        SetState("Getrennt");
    }

    // =========================================================================
    // Ausgehend: IPv4-Pakete der lokalen Seite -> Peers
    // =========================================================================
    private void CountNoise(int key)
    {
        Interlocked.Increment(ref noiseBlocked);
        noiseStats.AddOrUpdate(key, 1, delegate (int k, long v) { return v + 1; });
    }

    // multi = Ziel ist Broadcast/Multicast. Im strengen Modus werden die Dienste auch als
    // direkte Pakete (Anfragen UND Antworten, also Quell- oder Zielport) geblockt.
    private bool IsNoise(byte[] p, bool multi)
    {
        if (!noiseEnabled) return false;
        byte proto = p[9];
        if (proto == 2) { if (noiseIgmp) { CountNoise(-2); return true; } return false; }   // IGMP
        if (proto != 17) return false;
        if (!multi && !noiseStrict) return false;
        int ihl = (p[0] & 15) * 4;
        if (p.Length < ihl + 4) return true;
        int sport = PesBytes.ReadU16(p, ihl);
        int dport = PesBytes.ReadU16(p, ihl + 2);
        HashSet<int> set = noisePorts;
        if (set.Contains(dport)) { CountNoise(dport); return true; }
        if (noiseStrict && set.Contains(sport)) { CountNoise(sport); return true; }
        return false;
    }

    public void SendIp(byte[] p)
    {
        if (!running || stopping || p == null) return;
        if (p.Length < 20 || (p[0] >> 4) != 4) return;                // nur IPv4
        uint my = vip;
        if (my == 0) return;
        uint dst = PesBytes.ReadU32(p, 16);
        bool multi = dst == 0xFFFFFFFF || dst == bcast || (dst >> 28) == 0xE;
        if (IsNoise(p, multi)) return;
        if (multi)
        {
            // Broadcast/Multicast (Server-Browser, LAN-Suche) an ALLE verbundenen Peers
            foreach (PesP2pPeer peer in SnapshotPeers()) if (peer.Path != 0) SendData(peer, p);
            return;
        }
        if ((dst & mask) != (my & mask)) return;
        PesP2pPeer target;
        lock (sync) { byVip.TryGetValue(dst, out target); }
        if (target == null || target.Path == 0) return;                // noch nicht verbunden -> verwerfen (Spiel wiederholt)
        SendData(target, p);
    }

    private void SendData(PesP2pPeer peer, byte[] ipPacket)
    {
        byte[] wire;
        // HMAC/AES-Objekte sind nicht threadsicher; SendIp kommt aus mehreren Threads
        lock (tunLock) { wire = cTun.Seal(T_DATA, nodeId, NextSeq(), ipPacket, 0, ipPacket.Length); }
        IPEndPoint d = peer.DirectEp;
        if (peer.Path == 1 && d != null) SendRaw(wire, d);
        else if (peer.Path == 2) SendRelay(peer.NodeId, wire);
        else return;
        Interlocked.Add(ref peer.TxBytes, ipPacket.Length);
    }

    private void SendRaw(byte[] data, IPEndPoint ep)
    {
        try { sock.SendTo(data, ep); } catch (ObjectDisposedException) { } catch (SocketException) { }
    }

    private void SendRelay(ulong toNode, byte[] wire)
    {
        IPEndPoint se = serverEp;
        if (se == null || !AllowRelay) return;
        byte[] r = new byte[3 + 16 + 8 + 8 + wire.Length];
        r[0] = 0x50; r[1] = 0x53; r[2] = S_RELAY;
        Buffer.BlockCopy(lobbyId, 0, r, 3, 16);
        PesBytes.WriteU64(r, 19, nodeId);
        PesBytes.WriteU64(r, 27, toNode);
        Buffer.BlockCopy(wire, 0, r, 35, wire.Length);
        SendRaw(r, se);
    }

    // =========================================================================
    // THREAD 2: UDP -> virtueller Adapter (eingehend) + Server-Nachrichten
    // =========================================================================
    private void UdpLoop()
    {
        byte[] buf = new byte[65536];
        while (!stopping)
        {
            EndPoint from = new IPEndPoint(IPAddress.Any, 0);
            int n;
            try { n = sock.ReceiveFrom(buf, ref from); }
            catch (ObjectDisposedException) { break; }
            catch (SocketException se)
            {
                if (stopping) break;
                if (se.SocketErrorCode == SocketError.TimedOut || se.SocketErrorCode == SocketError.ConnectionReset || se.SocketErrorCode == SocketError.MessageSize) continue;
                AddLog("UDP-Fehler: " + se.SocketErrorCode);
                Thread.Sleep(50);
                continue;
            }
            if (n < 3) continue;
            IPEndPoint ep = (IPEndPoint)from;
            try
            {
                if (buf[0] == 0x50 && buf[1] == 0x53)
                {
                    IPEndPoint se2 = serverEp;
                    if (se2 != null && se2.Equals(ep)) HandleServer(buf, n, ep);
                }
                else if (buf[0] == 0x50 && buf[1] == 0x45)
                {
                    HandlePeerPacket(buf, 0, n, ep, false);
                }
            }
            catch (Exception ex) { AddLog("Paketfehler: " + ex.Message); }
        }
    }

    private bool ReplayOk(PesP2pPeer p, uint seq)
    {
        lock (p)
        {
            if (!p.AnySeq) { p.AnySeq = true; p.MaxSeq = seq; p.Window = 1UL; return true; }
            if (seq > p.MaxSeq)
            {
                uint d = seq - p.MaxSeq;
                p.Window = d >= 64 ? 1UL : ((p.Window << (int)d) | 1UL);
                p.MaxSeq = seq;
                return true;
            }
            uint back = p.MaxSeq - seq;
            if (back >= 64) return false;
            ulong bit = 1UL << (int)back;
            if ((p.Window & bit) != 0) return false;
            p.Window |= bit;
            return true;
        }
    }

    private void HandlePeerPacket(byte[] buf, int off, int len, IPEndPoint ep, bool viaRelay)
    {
        if (len < PesP2pCrypto.Hdr + PesP2pCrypto.Tag) return;
        ulong sender = PesBytes.ReadU64(buf, off + 3);
        if (sender == nodeId) return;
        PesP2pPeer p;
        lock (sync) { byNode.TryGetValue(sender, out p); }
        if (p == null) return;                                          // (noch) nicht in der Lobby-Liste
        byte type; ulong node; uint seq;
        byte[] body = cUdp.Open(buf, off, len, out type, out node, out seq);
        if (body == null)
        {
            int f = ++p.AuthFails;
            if (f == 5) AddLog("Pakete von " + p.Name + " lassen sich nicht pruefen - anderes Lobby-Passwort?");
            return;
        }
        if (!ReplayOk(p, seq)) return;
        p.AuthFails = 0;
        Interlocked.Exchange(ref p.LastRxMs, Now());

        if (!viaRelay)
        {
            IPEndPoint cur = p.DirectEp;
            if (p.Path != 1 || cur == null)
            {
                p.DirectEp = ep;
                p.Path = 1;
                AddLog("Direktverbindung (Hole Punching) mit " + p.Name + " ueber " + ep);
            }
            else if (!cur.Equals(ep) && (PesBytes.IsPrivate(ep.Address) || !PesBytes.IsPrivate(cur.Address)))
            {
                // Roaming / besserer Weg (z. B. gleiches Heimnetz statt Umweg ueber die Public-IP)
                p.DirectEp = ep;
                AddLog("Weg zu " + p.Name + " gewechselt -> " + ep);
            }
        }
        else if (p.Path == 0)
        {
            p.Path = 2;
            AddLog("Verbindung mit " + p.Name + " laeuft ueber Relay (Vermittlungsserver).");
        }

        switch (type)
        {
            case T_HELLO:
                if (body.Length >= 16 && PesBytes.ReadU64(body, 0) == nodeId)
                {
                    byte[] ack = new byte[16];
                    PesBytes.WriteU64(ack, 0, sender);
                    Buffer.BlockCopy(body, 8, ack, 8, 8);
                    byte[] w = cUdp.Seal(T_HELLO_ACK, nodeId, NextSeq(), ack, 0, 16);
                    if (viaRelay) SendRelay(sender, w); else SendRaw(w, ep);
                }
                break;
            case T_HELLO_ACK:
                if (body.Length >= 16 && PesBytes.ReadU64(body, 0) == nodeId)
                {
                    long rtt = Now() - (long)PesBytes.ReadU64(body, 8);
                    if (rtt >= 0 && rtt < 10000) p.RttMs = (int)rtt;
                }
                break;
            case T_DATA:
                DeliverInbound(p, body);
                break;
            case T_BYE:
                p.Path = 0; p.DirectEp = null; p.InServerList = false;
                AddLog(p.Name + " hat die Lobby verlassen.");
                break;
        }
    }

    private void DeliverInbound(PesP2pPeer p, byte[] ip)
    {
        if (ip.Length < 20 || (ip[0] >> 4) != 4) return;
        uint src = PesBytes.ReadU32(ip, 12);
        uint dst = PesBytes.ReadU32(ip, 16);
        if (src != p.Vip) return;                                       // Anti-Spoofing: nur die eigene virtuelle IP des Peers
        uint my = vip;
        bool multiIn = dst == 0xFFFFFFFF || dst == bcast || (dst >> 28) == 0xE;
        if (!(dst == my || multiIn)) return;
        if (IsNoise(ip, multiIn)) return;                               // auch eingehend (aeltere Manager-Versionen)
        if (stopping) return;
        Action<byte[]> sink = InboundSink;
        if (sink == null) return;
        Interlocked.Add(ref p.RxBytes, ip.Length);
        sink(ip);
    }

    // =========================================================================
    // Signaling: Nachrichten vom Vermittlungsserver
    // =========================================================================
    private static IPEndPoint ReadEp(byte[] b, int o)
    {
        byte[] a = new byte[4];
        Buffer.BlockCopy(b, o, a, 0, 4);
        return new IPEndPoint(new IPAddress(a), PesBytes.ReadU16(b, o + 4));
    }

    private void HandleServer(byte[] b, int n, IPEndPoint ep)
    {
        Interlocked.Exchange(ref lastServerRxMs, Now());
        if (!ServerReachable) { ServerReachable = true; if (gotWelcome) SetState("Verbunden"); }
        byte t = b[2];
        if (t == S_WELCOME && n >= 3 + 4 + 6 + 1 + 8)
        {
            uint newVip = PesBytes.ReadU32(b, 3);
            IPEndPoint pub = ReadEp(b, 7);
            int prefix = b[13];
            byte[] ck = new byte[8];
            Buffer.BlockCopy(b, 14, ck, 0, 8);
            cookie = ck;
            if (newVip == 0)
            {
                // Erste Antwort: nur Cookie (beweist, dass wir unter dieser Adresse erreichbar
                // sind - Schutz gegen gefaelschte Absender). Sofort erneut registrieren.
                Interlocked.Exchange(ref lastRegTxMs, -1000000);
                return;
            }
            if (prefix < 8 || prefix > 30) prefix = 16;
            uint m = prefix == 0 ? 0 : 0xFFFFFFFF << (32 - prefix);
            PublicEndpoint = pub.ToString();
            if (newVip != vip || m != mask)
            {
                mask = m; bcast = (newVip & m) | ~m; vip = newVip;
                PrefixLength = prefix;
                AssignedIp = PesBytes.IpToString(newVip);
                IpChanged = true;
                AddLog("Virtuelle IP zugewiesen: " + AssignedIp + "/" + prefix + " (oeffentlich sichtbar als " + PublicEndpoint + ")");
            }
            gotWelcome = true;
            SetState("Verbunden");
        }
        else if (t == S_PEER && n >= 3 + 8 + 4 + 6 + 2)
        {
            ApplyPeer(b, n, 3, false, 0);
        }
        else if (t == S_PEER2 && n >= 8 + 8 + 4 + 6 + 2)
        {
            ApplyPeer(b, n, 8, true, PesBytes.ReadU32(b, 4));
        }
        else if (t == S_GONE && n >= 15)
        {
            uint rev = PesBytes.ReadU32(b, 3);
            ulong nid = PesBytes.ReadU64(b, 7);
            lock (sync)
            {
                gone[nid] = new KeyValuePair<uint, long>(rev, Now());
                PesP2pPeer p;
                if (byNode.TryGetValue(nid, out p) && (!p.HasRev || !Newer(p.InfoRev, rev))) p.InServerList = false;
            }
        }
        else if (t == S_SYNC && n >= 12)
        {
            uint rev = PesBytes.ReadU32(b, 3);
            int total = PesBytes.ReadU16(b, 7);
            int cnt = b[11];
            if (rev != syncRev || syncTotal != total) { syncRev = rev; syncTotal = total; syncIds.Clear(); }
            for (int i = 0; i < cnt && 12 + i * 8 + 8 <= n; i++) syncIds.Add(PesBytes.ReadU64(b, 12 + i * 8));
            if (syncIds.Count >= syncTotal)
            {
                lock (sync)
                {
                    foreach (PesP2pPeer p in byNode.Values)
                    {
                        KeyValuePair<uint, long> g;
                        bool goneLater = gone.TryGetValue(p.NodeId, out g) && Newer(g.Key, rev);
                        if (syncIds.Contains(p.NodeId)) { if (!goneLater) p.InServerList = true; }
                        else if (!p.HasRev || !Newer(p.InfoRev, rev)) p.InServerList = false;
                    }
                }
                syncIds.Clear(); syncTotal = -1;
            }
        }
        else if (t == S_MEMBERS && n >= 4)
        {
            int cnt = b[3];
            HashSet<ulong> set = new HashSet<ulong>();
            for (int i = 0; i < cnt && 4 + i * 8 + 8 <= n; i++) set.Add(PesBytes.ReadU64(b, 4 + i * 8));
            lock (sync) { foreach (PesP2pPeer p in byNode.Values) p.InServerList = set.Contains(p.NodeId); }
        }
        else if (t == S_RELAYED && n >= 3 + 8 + PesP2pCrypto.Hdr + PesP2pCrypto.Tag)
        {
            ulong from = PesBytes.ReadU64(b, 3);
            if (PesBytes.ReadU64(b, 11 + 3) != from) return;            // Absender im Paket muss zum Relay-Absender passen
            HandlePeerPacket(b, 11, n - 11, ep, true);
        }
        else if (t == S_ERROR && n >= 5)
        {
            int ml = Math.Min(b[4], n - 5);
            string msg = Encoding.UTF8.GetString(b, 5, ml);
            LastError = msg;
            SetState("Fehler: " + msg);
        }
    }

    // Mitspieler-Info aus PEER (alt) bzw. PEER2 (mit Revision) uebernehmen
    private void ApplyPeer(byte[] b, int n, int start, bool withRev, uint rev)
    {
        {
            int o = start;
            ulong nid = PesBytes.ReadU64(b, o); o += 8;
            uint pv = PesBytes.ReadU32(b, o); o += 4;
            IPEndPoint pub = ReadEp(b, o); o += 6;
            int nl = b[o++];
            if (o + nl + 1 > n) return;
            string nm = Encoding.UTF8.GetString(b, o, nl); o += nl;
            int cnt = b[o++];
            List<IPEndPoint> locals = new List<IPEndPoint>();
            for (int i = 0; i < cnt && o + 6 <= n; i++) { locals.Add(ReadEp(b, o)); o += 6; }
            if (nid == nodeId) return;
            bool isNew = false;
            lock (sync)
            {
                if (withRev)
                {
                    KeyValuePair<uint, long> g;
                    if (gone.TryGetValue(nid, out g))
                    {
                        if (!Newer(rev, g.Key)) return;             // verspaetete Info ueber jemanden, der schon weg ist
                        gone.Remove(nid);
                    }
                }
                PesP2pPeer p;
                if (byNode.TryGetValue(nid, out p) && withRev && p.HasRev && Newer(p.InfoRev, rev)) return;   // aeltere Info
                if (p == null)
                {
                    p = new PesP2pPeer();
                    p.NodeId = nid;
                    p.PunchStartMs = Now();
                    byNode[nid] = p;
                    isNew = true;
                }
                if (p.Vip != pv)
                {
                    PesP2pPeer old;
                    if (p.Vip != 0 && byVip.TryGetValue(p.Vip, out old) && old == p) byVip.Remove(p.Vip);
                    p.Vip = pv;
                    byVip[pv] = p;
                }
                p.Name = nm;
                p.PublicEp = pub;
                p.LocalEps = locals;
                p.InServerList = true;
                if (withRev) { p.HasRev = true; p.InfoRev = rev; }
            }
            if (isNew) AddLog("Mitspieler in der Lobby: " + nm + " (" + PesBytes.IpToString(pv) + ") - starte Hole Punching an " + pub);
        }
    }

    private List<IPEndPoint> GetLocalCandidates()
    {
        List<IPEndPoint> list = new List<IPEndPoint>();
        try
        {
            foreach (NetworkInterface ni in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (ni.OperationalStatus != OperationalStatus.Up) continue;
                if (ni.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
                foreach (UnicastIPAddressInformation ua in ni.GetIPProperties().UnicastAddresses)
                {
                    if (ua.Address.AddressFamily != AddressFamily.InterNetwork) continue;
                    byte[] a = ua.Address.GetAddressBytes();
                    if (a[0] == 169 && a[1] == 254) continue;
                    uint u = PesBytes.IpToUInt(ua.Address);
                    if (mask != 0 && (u & mask) == (vip & mask)) continue;
                    if (BindAddress != null && !BindAddress.Equals(IPAddress.Any) && !ua.Address.Equals(BindAddress)) continue;
                    list.Add(new IPEndPoint(ua.Address, localPort));
                    if (list.Count >= 6) return list;
                }
            }
        }
        catch { }
        return list;
    }

    private void SendRegister()
    {
        IPEndPoint se = serverEp;
        if (se == null) return;
        byte[] nm = PesBytes.Utf8Limit(displayName, 32);
        List<IPEndPoint> locals = GetLocalCandidates();
        byte[] p = new byte[4 + 16 + 8 + 16 + 1 + nm.Length + 1 + locals.Count * 6 + 8 + 9];
        p[0] = 0x50; p[1] = 0x53; p[2] = S_REGISTER; p[3] = ProtoVersion;
        Buffer.BlockCopy(lobbyId, 0, p, 4, 16);
        PesBytes.WriteU64(p, 20, nodeId);
        Buffer.BlockCopy(machineKey, 0, p, 28, 16);
        int o = 44;
        p[o++] = (byte)nm.Length;
        Buffer.BlockCopy(nm, 0, p, o, nm.Length); o += nm.Length;
        p[o++] = (byte)locals.Count;
        foreach (IPEndPoint l in locals)
        {
            Buffer.BlockCopy(l.Address.GetAddressBytes(), 0, p, o, 4);
            PesBytes.WriteU16(p, o + 4, l.Port);
            o += 6;
        }
        Buffer.BlockCopy(cookie, 0, p, o, 8);
        // Erweiterung E2: eigener Stand der Mitgliederliste (alte Server ignorieren das)
        p[o + 8] = EXT_V2;
        PesBytes.WriteU64(p, o + 9, ListDigest());
        SendRaw(p, se);
    }

    private static ulong Mix(ulong nid, uint rev)
    {
        ulong z = nid ^ ((ulong)rev * 0x9E3779B97F4A7C15UL);
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
        return z ^ (z >> 31);
    }

    private static bool Newer(uint a, uint b) { return (int)(a - b) > 0; }

    private ulong ListDigest()
    {
        ulong d = 0;
        lock (sync) { foreach (PesP2pPeer p in byNode.Values) if (p.HasRev && p.InServerList) d ^= Mix(p.NodeId, p.InfoRev); }
        return d;
    }

    private void SendHello(PesP2pPeer p, IPEndPoint ep, bool viaRelay)
    {
        byte[] body = new byte[16];
        PesBytes.WriteU64(body, 0, p.NodeId);
        PesBytes.WriteU64(body, 8, (ulong)Now());
        byte[] w = cMaint.Seal(T_HELLO, nodeId, NextSeq(), body, 0, 16);
        if (viaRelay) SendRelay(p.NodeId, w); else SendRaw(w, ep);
    }

    // =========================================================================
    // THREAD 3: Wartung - Registrierung, Hole Punching, Keepalive, Timeouts
    // =========================================================================
    private void MaintLoop()
    {
        while (!stopping)
        {
            try { MaintTick(); }
            catch (Exception ex) { AddLog("Wartungsfehler: " + ex.Message); }
            if (stopEvent.WaitOne(200)) break;
        }
    }

    private void MaintTick()
    {
        long now = Now();

        // DNS des Servers alle 5 Minuten neu aufloesen (DynDNS-tauglich)
        if (serverEp == null || now - lastResolveMs > 300000)
        {
            lastResolveMs = now;
            try
            {
                IPAddress ip = null;
                if (!IPAddress.TryParse(serverHost, out ip))
                {
                    foreach (IPAddress a in Dns.GetHostAddresses(serverHost))
                        if (a.AddressFamily == AddressFamily.InterNetwork) { ip = a; break; }
                }
                if (ip != null)
                {
                    IPEndPoint ne = new IPEndPoint(ip, serverPort);
                    if (serverEp == null || !serverEp.Equals(ne)) { serverEp = ne; AddLog("Vermittlungsserver: " + ne); }
                }
                else if (serverEp == null) SetState("Fehler: Server-Adresse nicht aufloesbar");
            }
            catch (Exception ex) { if (serverEp == null) SetState("Fehler: Server nicht aufloesbar (" + ex.Message + ")"); }
        }

        // Registrierung / Keepalive beim Server (anfangs schnell, dann alle 10 s)
        long sinceSrv = now - Interlocked.Read(ref lastServerRxMs);
        int regInterval = (gotWelcome && ServerReachable) ? 10000 : 2000;
        if (now - Interlocked.Read(ref lastRegTxMs) >= regInterval) { Interlocked.Exchange(ref lastRegTxMs, now); SendRegister(); }
        if (ServerReachable && sinceSrv > 35000)
        {
            ServerReachable = false;
            SetState(gotWelcome ? "Server nicht erreichbar - bestehende Direktverbindungen bleiben aktiv" : "Verbinde mit Vermittlungsserver ...");
        }

        if (!gotWelcome) return;                                        // ohne eigene IP kein Punching

        // Alte "ist weg"-Merker aufraeumen (nur gegen verspaetete Pakete noetig)
        if (gone.Count > 0 && now - lastGoneCleanMs > 30000)
        {
            lastGoneCleanMs = now;
            lock (sync)
            {
                List<ulong> old = new List<ulong>();
                foreach (KeyValuePair<ulong, KeyValuePair<uint, long>> kv in gone) if (now - kv.Value.Value > 120000) old.Add(kv.Key);
                foreach (ulong id in old) gone.Remove(id);
            }
        }

        int budget = PunchBudgetPerTick;
        foreach (PesP2pPeer p in SnapshotPeers())
        {
            long lastRx = Interlocked.Read(ref p.LastRxMs);

            if (p.Path != 0 && lastRx > 0 && now - lastRx > PeerTimeoutMs)
            {
                AddLog("Keine Antwort mehr von " + p.Name + " - baue Verbindung neu auf.");
                p.Path = 0; p.DirectEp = null; p.PunchStartMs = now; p.RttMs = -1; p.Punching = false;
            }

            if (p.Path == 1)
            {
                // Keepalive haelt das NAT-Loch offen (typische UDP-Timeouts: 30-120 s)
                IPEndPoint d = p.DirectEp;
                if (d != null && now - p.LastHelloMs >= 5000) { p.LastHelloMs = now; SendHello(p, d, false); }
            }
            else
            {
                // UDP Hole Punching: beide Seiten senden gleichzeitig an alle bekannten
                // Adressen des anderen -> beide NATs legen eine Zuordnung an, das erste
                // authentifizierte Paket bestaetigt den direkten Weg.
                if (!p.Punching)
                {
                    if (budget <= 0) continue;                          // kommt im naechsten Takt dran
                    p.Punching = true; p.PunchStartMs = now;
                }
                long since = now - p.PunchStartMs;
                int iv = since < 10000 ? 250 : 2000;
                if (now - p.LastHelloMs >= iv && budget > 0)
                {
                    budget--;
                    p.LastHelloMs = now;
                    if (p.PublicEp != null) SendHello(p, p.PublicEp, false);
                    List<IPEndPoint> locals = p.LocalEps;
                    if (locals != null) foreach (IPEndPoint l in locals) SendHello(p, l, false);
                }
                if (p.Path == 0 && since > PunchTimeoutMs && AllowRelay && ServerReachable)
                {
                    p.Path = 2;
                    AddLog("Kein direkter Weg zu " + p.Name + " (symmetrisches NAT?) - nutze Relay ueber den Vermittlungsserver.");
                }
                if (p.Path == 2 && now - p.LastRelayHelloMs >= 2000) { p.LastRelayHelloMs = now; SendHello(p, null, true); }
            }

            if (!p.InServerList && (lastRx == 0 || now - lastRx > 15000))
            {
                lock (sync)
                {
                    byNode.Remove(p.NodeId);
                    PesP2pPeer cur;
                    if (byVip.TryGetValue(p.Vip, out cur) && cur == p) byVip.Remove(p.Vip);
                }
                AddLog(p.Name + " ist nicht mehr in der Lobby.");
            }
        }
    }

    private List<PesP2pPeer> SnapshotPeers()
    {
        lock (sync) { return new List<PesP2pPeer>(byNode.Values); }
    }

    // Fuer die GUI (Timer im Control Center)
    public PesP2pPeerInfo[] GetPeers()
    {
        List<PesP2pPeerInfo> r = new List<PesP2pPeerInfo>();
        foreach (PesP2pPeer p in SnapshotPeers())
        {
            PesP2pPeerInfo i = new PesP2pPeerInfo();
            i.Name = p.Name;
            i.NodeId = p.NodeId; i.Vip = p.Vip; i.Path = p.Path;
            i.Ip = PesBytes.IpToString(p.Vip);
            IPEndPoint d = p.DirectEp;
            if (p.Path == 1) { i.Mode = "Direkt"; i.Endpoint = d == null ? "" : d.ToString(); }
            else if (p.Path == 2) { i.Mode = "Relay"; i.Endpoint = "ueber Server"; }
            else { i.Mode = p.AuthFails >= 5 ? "Passwort falsch?" : "Verbinde ..."; i.Endpoint = p.PublicEp == null ? "" : p.PublicEp.ToString(); }
            i.RttMs = p.Path == 0 ? -1 : p.RttMs;
            i.RxBytes = Interlocked.Read(ref p.RxBytes);
            i.TxBytes = Interlocked.Read(ref p.TxBytes);
            r.Add(i);
        }
        r.Sort(delegate (PesP2pPeerInfo a, PesP2pPeerInfo b2) { return string.Compare(a.Name, b2.Name, StringComparison.OrdinalIgnoreCase); });
        return r.ToArray();
    }
}

// ============================================================================
// Mini-Vermittler: protokollgleich zum Vermittlungsserver des Project Earth LAN Managers
// (Anmeldung mit Cookie, feste virtuelle IP je Geraet, Relay bei strengem NAT).
// Er sieht nur die Lobby-ID (Hash) - nie Passwort, Schluessel oder Inhalte.
// ============================================================================
public sealed class PesRvMember
{
    public ulong NodeId;
    public string MachineKey;
    public IPEndPoint Ep;
    public uint Vip;
    public byte[] Name = new byte[0];
    public byte[] Locals = new byte[0];
    public long LastSeen;
    public double Tokens;
    public double ByteTokens;
    public long TokenTs;
    // Protokoll-Erweiterung "E2" (ab 2026.09.29): Mitgliederliste nur bei Aenderungen
    public bool V2;
    public uint Rev;          // Lobby-Revision der letzten Aenderung dieses Mitglieds
    public int Mismatch;      // wie oft in Folge der Stand des Clients nicht passte
}

public sealed class PesRvLobby
{
    public string Id;
    public Dictionary<ulong, PesRvMember> Members = new Dictionary<ulong, PesRvMember>();
    public Dictionary<string, uint> Leases = new Dictionary<string, uint>();
    public long LastActive;
    public uint Rev;          // zaehlt jede Aenderung (Beitritt, Adresswechsel, Verlassen)
    public ulong Digest;      // XOR ueber Mix(NodeId, Rev) aller Mitglieder
}

public sealed class PesRendezvousServer
{
    private const byte S_REGISTER = 0x10, S_LEAVE = 0x11, S_RELAY = 0x12;
    private const byte S_WELCOME = 0x20, S_PEER = 0x21, S_RELAYED = 0x22, S_ERROR = 0x23, S_MEMBERS = 0x24;
    // Erweiterung E2: Clients haengen an REGISTER [0xE2][Digest u64] an (alte Server ignorieren das).
    // Sie bekommen dann nur noch Aenderungen (PEER2/GONE) statt alle 10 s die komplette Liste;
    // die komplette Liste (PEER2 + SYNC) nur, wenn ihr Stand zweimal hintereinander nicht passt.
    private const byte S_SYNC = 0x25, S_PEER2 = 0x26, S_GONE = 0x27, EXT_V2 = 0xE2;
    private const int SyncChunk = 150;
    private const uint NetBase = 0x0A4D0000;   // 10.77.0.0
    private const int Prefix = 16;

    public int Port = 9890;
    public int MaxMembers = 8;
    public int MaxLobbies = 200;
    public int RelayPps = 4000;
    // Relay-Bandbreite in Mbit/s (0 = unbegrenzt): je Mitglied und fuer alle zusammen. Schuetzt
    // den Upload des Gastgebers, wenn viele Mitspieler hinter strengem NAT/CGNAT sitzen.
    public double RelayMbitPerMember = 0;
    public double RelayMbitTotal = 0;
    private double totalTokens;
    private long totalTs;
    public long RelayDropped;
    public readonly ConcurrentQueue<string> Log = new ConcurrentQueue<string>();
    public long RelayedPackets;
    public volatile int MemberCount;
    // Nur wenn der Server beim Spieler zu Hause laeuft (Manager-Option "Lobby hosten"):
    // oeffentliche IP des Anschlusses. Mitglieder, die sich ueber Loopback/LAN anmelden
    // (der Host selbst, Gaeste im selben Heimnetz), werden dann mit dieser IP angekuendigt.
    public volatile IPAddress PublicIp;
    public IPAddress BindAddress = IPAddress.Any;
    public bool IsRunning { get { return thread != null && !stopping; } }

    private readonly Dictionary<string, PesRvLobby> lobbies = new Dictionary<string, PesRvLobby>();
    private readonly Stopwatch clock = Stopwatch.StartNew();
    private readonly byte[] cookieKey = new byte[32];
    private HMACSHA256 cookieMac;
    private Socket sock;
    private Thread thread;
    private volatile bool stopping;

    private long Now() { return clock.ElapsedMilliseconds; }
    private void AddLog(string s) { Log.Enqueue(DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + s); }

    private static uint ReadU32(byte[] b, int o) { return ((uint)b[o] << 24) | ((uint)b[o + 1] << 16) | ((uint)b[o + 2] << 8) | b[o + 3]; }
    private static void WriteU32(byte[] b, int o, uint v) { b[o] = (byte)(v >> 24); b[o + 1] = (byte)(v >> 16); b[o + 2] = (byte)(v >> 8); b[o + 3] = (byte)v; }
    private static ulong ReadU64(byte[] b, int o) { return ((ulong)ReadU32(b, o) << 32) | ReadU32(b, o + 4); }
    private static void WriteU64(byte[] b, int o, ulong v) { WriteU32(b, o, (uint)(v >> 32)); WriteU32(b, o + 4, (uint)v); }
    private static string Hex(byte[] b, int o, int n) { StringBuilder sb = new StringBuilder(n * 2); for (int i = 0; i < n; i++) sb.Append(b[o + i].ToString("x2")); return sb.ToString(); }
    private static string Ip(uint v) { return (v >> 24) + "." + ((v >> 16) & 255) + "." + ((v >> 8) & 255) + "." + (v & 255); }

    public void Start()
    {
        using (RandomNumberGenerator rng = RandomNumberGenerator.Create()) rng.GetBytes(cookieKey);
        cookieMac = new HMACSHA256(cookieKey);
        sock = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
        try { sock.IOControl(-1744830452, new byte[] { 0, 0, 0, 0 }, null); } catch { }   // nur Windows (SIO_UDP_CONNRESET)
        sock.Bind(new IPEndPoint(BindAddress == null ? IPAddress.Any : BindAddress, Port));
        sock.ReceiveTimeout = 1000;
        sock.ReceiveBufferSize = 4 << 20;
        sock.SendBufferSize = 4 << 20;
        thread = new Thread(Loop);
        thread.IsBackground = true;
        thread.Start();
        AddLog("Vermittlungsserver laeuft auf UDP-Port " + Port);
    }

    public void Stop()
    {
        stopping = true;
        try { sock.Close(); } catch { }
        if (thread != null) thread.Join(3000);
    }

    // Wird nur im Server-Thread aktualisiert (kein gleichzeitiger Zugriff auf die Listen).
    private volatile string statsText = "Lobbys: 0, Mitglieder: 0";
    public string Stats() { return statsText + ", Relay-Pakete: " + Interlocked.Read(ref RelayedPackets) + ", wegen Limit verworfen: " + Interlocked.Read(ref RelayDropped); }

    private byte[] Cookie(IPEndPoint ep)
    {
        byte[] d = new byte[6];
        Buffer.BlockCopy(ep.Address.GetAddressBytes(), 0, d, 0, 4);
        d[4] = (byte)(ep.Port >> 8); d[5] = (byte)ep.Port;
        byte[] h = cookieMac.ComputeHash(d);
        byte[] c = new byte[8];
        Buffer.BlockCopy(h, 0, c, 0, 8);
        return c;
    }

    private static bool IsPrivateOrLoopback(IPAddress a)
    {
        if (IPAddress.IsLoopback(a)) return true;
        byte[] b = a.GetAddressBytes();
        if (b.Length != 4) return false;
        return b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) || (b[0] == 192 && b[1] == 168) || (b[0] == 169 && b[1] == 254);
    }

    private IPEndPoint Advertised(IPEndPoint ep)
    {
        IPAddress pub = PublicIp;
        if (pub != null && IsPrivateOrLoopback(ep.Address)) return new IPEndPoint(pub, ep.Port);
        return ep;
    }

    private void Send(byte[] data, IPEndPoint ep) { try { sock.SendTo(data, ep); } catch { } }

    private void Loop()
    {
        byte[] buf = new byte[65536];
        long lastCleanup = 0;
        while (!stopping)
        {
            EndPoint from = new IPEndPoint(IPAddress.Any, 0);
            int n = 0;
            try { n = sock.ReceiveFrom(buf, ref from); }
            catch (ObjectDisposedException) { break; }
            catch (SocketException) { n = 0; }
            if (stopping) break;
            try
            {
                if (n >= 3 && buf[0] == 0x50 && buf[1] == 0x53)
                {
                    IPEndPoint ep = (IPEndPoint)from;
                    if (buf[2] == S_REGISTER) OnRegister(buf, n, ep);
                    else if (buf[2] == S_RELAY) OnRelay(buf, n, ep);
                    else if (buf[2] == S_LEAVE) OnLeave(buf, n, ep);
                }
            }
            catch (Exception ex) { AddLog("Paketfehler: " + ex.Message); }
            long now = Now();
            if (now - lastCleanup > 1000) { lastCleanup = now; Cleanup(now); }
        }
    }

    private void SendError(IPEndPoint ep, byte code, string msg)
    {
        byte[] m = Encoding.UTF8.GetBytes(msg);
        if (m.Length > 200) Array.Resize(ref m, 200);
        byte[] p = new byte[5 + m.Length];
        p[0] = 0x50; p[1] = 0x53; p[2] = S_ERROR; p[3] = code; p[4] = (byte)m.Length;
        Buffer.BlockCopy(m, 0, p, 5, m.Length);
        Send(p, ep);
    }

    private byte[] BuildPeer(PesRvMember m)
    {
        byte[] p = new byte[3 + 8 + 4 + 6 + 1 + m.Name.Length + 1 + m.Locals.Length];
        p[0] = 0x50; p[1] = 0x53; p[2] = S_PEER;
        WriteU64(p, 3, m.NodeId);
        WriteU32(p, 11, m.Vip);
        IPEndPoint adv = Advertised(m.Ep);
        Buffer.BlockCopy(adv.Address.GetAddressBytes(), 0, p, 15, 4);
        p[19] = (byte)(adv.Port >> 8); p[20] = (byte)adv.Port;
        int o = 21;
        p[o++] = (byte)m.Name.Length;
        Buffer.BlockCopy(m.Name, 0, p, o, m.Name.Length); o += m.Name.Length;
        p[o++] = (byte)(m.Locals.Length / 6);
        Buffer.BlockCopy(m.Locals, 0, p, o, m.Locals.Length);
        return p;
    }

    // Altes Format (nur fuer Manager vor 2026.09.29): hoechstens 255 Eintraege.
    private byte[] BuildMembers(PesRvLobby l)
    {
        int cnt = Math.Min(l.Members.Count, 255);
        byte[] p = new byte[4 + cnt * 8];
        p[0] = 0x50; p[1] = 0x53; p[2] = S_MEMBERS; p[3] = (byte)cnt;
        int i = 0;
        foreach (ulong id in l.Members.Keys) { if (i >= cnt) break; WriteU64(p, 4 + i * 8, id); i++; }
        return p;
    }

    private void Broadcast(PesRvLobby l, byte[] data, ulong except)
    {
        foreach (PesRvMember o in l.Members.Values) if (o.NodeId != except) Send(data, o.Ep);
    }

    // ---- Erweiterung E2 -------------------------------------------------------------------
    public static ulong Mix(ulong nid, uint rev)
    {
        ulong z = nid ^ ((ulong)rev * 0x9E3779B97F4A7C15UL);
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
        return z ^ (z >> 31);
    }

    // PEER2 = [P S 0x26][Art: 0 Aenderung / 1 Abgleich][Rev u32] + Inhalt wie PEER
    private byte[] BuildPeer2(PesRvMember m, byte kind)
    {
        byte[] bp = BuildPeer(m);
        byte[] p = new byte[bp.Length + 5];
        p[0] = 0x50; p[1] = 0x53; p[2] = S_PEER2; p[3] = kind;
        WriteU32(p, 4, m.Rev);
        Buffer.BlockCopy(bp, 3, p, 8, bp.Length - 3);
        return p;
    }

    // Mitglied neu/geaendert: neue Revision, allen E2-Clients (auch ihm selbst) die Aenderung,
    // alten Clients wie bisher PEER + Mitgliederliste.
    private void NotifyChange(PesRvLobby l, PesRvMember m)
    {
        if (m.Rev != 0) l.Digest ^= Mix(m.NodeId, m.Rev);
        l.Rev++; if (l.Rev == 0) l.Rev = 1;
        m.Rev = l.Rev;
        l.Digest ^= Mix(m.NodeId, m.Rev);
        byte[] p2 = BuildPeer2(m, 0);
        byte[] pm = null, mem = null;
        foreach (PesRvMember x in l.Members.Values)
        {
            if (x.V2) Send(p2, x.Ep);
            else if (x.NodeId != m.NodeId)
            {
                if (pm == null) { pm = BuildPeer(m); mem = BuildMembers(l); }
                Send(pm, x.Ep); Send(mem, x.Ep);
            }
        }
    }

    // Mitglied ist weg (abgemeldet, Timeout, neue Sitzung desselben PCs). Vorher schon entfernt.
    private void NotifyGone(PesRvLobby l, PesRvMember m)
    {
        if (m.Rev != 0) l.Digest ^= Mix(m.NodeId, m.Rev);
        l.Rev++; if (l.Rev == 0) l.Rev = 1;
        byte[] g = new byte[15];
        g[0] = 0x50; g[1] = 0x53; g[2] = S_GONE;
        WriteU32(g, 3, l.Rev);
        WriteU64(g, 7, m.NodeId);
        byte[] mem = null;
        foreach (PesRvMember x in l.Members.Values)
        {
            if (x.V2) Send(g, x.Ep);
            else { if (mem == null) mem = BuildMembers(l); Send(mem, x.Ep); }
        }
    }

    // Kompletter Abgleich: alle anderen als PEER2 (Art 1), danach die Mitgliederliste in
    // Stuecken: SYNC = [P S 0x25][Rev u32][Gesamt u16][Start u16][Anzahl u8][NodeIds...]
    private void SendSync(PesRvLobby l, PesRvMember m)
    {
        foreach (PesRvMember x in l.Members.Values) if (x.NodeId != m.NodeId) Send(BuildPeer2(x, 1), m.Ep);
        List<ulong> ids = new List<ulong>(l.Members.Keys);
        int total = ids.Count;
        for (int st = 0; st < total; st += SyncChunk)
        {
            int cnt = Math.Min(SyncChunk, total - st);
            byte[] p = new byte[12 + cnt * 8];
            p[0] = 0x50; p[1] = 0x53; p[2] = S_SYNC;
            WriteU32(p, 3, l.Rev);
            p[7] = (byte)(total >> 8); p[8] = (byte)total;
            p[9] = (byte)(st >> 8); p[10] = (byte)st;
            p[11] = (byte)cnt;
            for (int i = 0; i < cnt; i++) WriteU64(p, 12 + i * 8, ids[st + i]);
            Send(p, m.Ep);
        }
    }

    // Feste virtuelle IP je PC (MachineKey) und Lobby: deterministisch aus dem Hash,
    // bei Kollision die naechste freie. Letztes Oktett nie .0/.255 (Spiele-Kompatibilitaet).
    private uint AllocateVip(PesRvLobby l, string mk)
    {
        HashSet<uint> used = new HashSet<uint>();
        foreach (PesRvMember o in l.Members.Values) used.Add(o.Vip);
        uint lease;
        if (l.Leases.TryGetValue(mk, out lease) && !used.Contains(lease)) return lease;
        uint idx;
        // Nur aus dem MachineKey (nicht aus der Lobby) -> derselbe PC hat in JEDER Lobby und auf
        // JEDEM Server dieselbe virtuelle IP (wichtig fuer Freundesliste, Moderatoren, Bans,
        // Kanal-Ersteller - die alle ueber die IP laufen). Nur bei einer Kollision weicht sie ab.
        using (SHA256 sha = SHA256.Create()) idx = ReadU32(sha.ComputeHash(Encoding.ASCII.GetBytes("PEL-VIP|" + mk)), 0) % 65024u;
        for (int t = 0; t < 65024; t++)
        {
            uint v = NetBase | ((idx / 254u) << 8) | (idx % 254u + 1u);
            bool leasedToOther = false;
            foreach (KeyValuePair<string, uint> kv in l.Leases) if (kv.Value == v && kv.Key != mk) { leasedToOther = true; break; }
            if (!used.Contains(v) && !leasedToOther) { l.Leases[mk] = v; return v; }
            idx = (idx + 1u) % 65024u;
        }
        return 0;
    }

    private void OnRegister(byte[] b, int n, IPEndPoint ep)
    {
        if (n < 46) return;
        if (b[3] != 1) { SendError(ep, 1, "Veraltete oder neuere Programmversion - bitte aktualisieren."); return; }
        string lid = Hex(b, 4, 16);
        ulong nid = ReadU64(b, 20);
        string mk = Hex(b, 28, 16);
        int o = 44;
        int nl = b[o++];
        if (nl > 32 || o + nl + 1 > n) return;
        byte[] name = new byte[nl]; Buffer.BlockCopy(b, o, name, 0, nl); o += nl;
        int cnt = b[o++];
        if (cnt > 8 || o + cnt * 6 > n) return;
        byte[] locals = new byte[cnt * 6]; Buffer.BlockCopy(b, o, locals, 0, cnt * 6); o += cnt * 6;
        byte[] expect = Cookie(ep);
        bool cookieOk = o + 8 <= n;
        for (int i = 0; cookieOk && i < 8; i++) if (b[o + i] != expect[i]) cookieOk = false;
        bool v2 = cookieOk && o + 8 + 9 <= n && b[o + 8] == EXT_V2;
        ulong clientDigest = v2 ? ReadU64(b, o + 9) : 0;

        byte[] w = new byte[22];
        w[0] = 0x50; w[1] = 0x53; w[2] = S_WELCOME;
        IPEndPoint advSelf = Advertised(ep);
        Buffer.BlockCopy(advSelf.Address.GetAddressBytes(), 0, w, 7, 4);
        w[11] = (byte)(advSelf.Port >> 8); w[12] = (byte)advSelf.Port; w[13] = Prefix;
        Buffer.BlockCopy(expect, 0, w, 14, 8);
        if (!cookieOk)
        {
            // Erst Cookie ausliefern (virtuelle IP 0 = "noch nicht aufgenommen").
            // Gefaelschte Absender bekommen so nie Mitgliederlisten (kein Verstaerker).
            Send(w, ep);
            return;
        }

        long now = Now();
        PesRvLobby l;
        if (!lobbies.TryGetValue(lid, out l))
        {
            if (lobbies.Count >= MaxLobbies) { SendError(ep, 2, "Server ausgelastet (zu viele Lobbys)."); return; }
            l = new PesRvLobby(); l.Id = lid; lobbies[lid] = l;
            // Zufaelliger Startwert: nach einem Server-Neustart passt kein alter Client-Stand zufaellig
            byte[] rr = new byte[4];
            using (RandomNumberGenerator rng = RandomNumberGenerator.Create()) rng.GetBytes(rr);
            l.Rev = ReadU32(rr, 0);
        }
        l.LastActive = now;

        bool changed = false, isNew = false;
        PesRvMember m;
        if (!l.Members.TryGetValue(nid, out m))
        {
            // Gleicher PC mit neuer Sitzung (Absturz/Neustart)? Alte Sitzung sofort entfernen.
            List<PesRvMember> stale = new List<PesRvMember>();
            foreach (PesRvMember x in l.Members.Values) if (x.MachineKey == mk) stale.Add(x);
            foreach (PesRvMember s in stale) { l.Members.Remove(s.NodeId); NotifyGone(l, s); }
            if (l.Members.Count >= MaxMembers) { SendError(ep, 3, "Lobby ist voll (max. " + MaxMembers + ")."); return; }
            m = new PesRvMember();
            m.NodeId = nid; m.MachineKey = mk; m.Ep = ep;
            m.Vip = AllocateVip(l, mk);
            if (m.Vip == 0) { SendError(ep, 4, "Keine freie virtuelle IP."); return; }
            m.Tokens = RelayPps; m.ByteTokens = RelayMbitPerMember * 125000.0; m.TokenTs = now;
            l.Members[nid] = m;
            changed = true; isNew = true;
            AddLog("Lobby " + lid.Substring(0, 8) + ": + " + Encoding.UTF8.GetString(name) + " (" + Ip(m.Vip) + ") von " + ep + " [" + l.Members.Count + " online]");
        }
        if (!m.Ep.Equals(ep)) { m.Ep = ep; changed = true; }
        if (!Same(m.Name, name) || !Same(m.Locals, locals)) { m.Name = name; m.Locals = locals; changed = true; }
        m.LastSeen = now;
        m.V2 = v2;

        WriteU32(w, 3, m.Vip);
        Send(w, ep);
        if (changed) NotifyChange(l, m);
        if (m.V2)
        {
            // Stand des Clients = alle anderen Mitglieder mit ihrer Revision
            ulong expected = l.Digest ^ Mix(m.NodeId, m.Rev);
            if (clientDigest == expected) m.Mismatch = 0;
            // Erst beim zweiten Fehlstand in Folge abgleichen (ein einzelner kann nur eine gerade
            // unterwegs befindliche Aenderung sein). Nach einem Abgleich zaehlt der naechste sofort.
            else if (isNew || ++m.Mismatch >= 2) { m.Mismatch = 1; SendSync(l, m); }
        }
        else
        {
            // Alte Manager-Version: wie bisher komplette Liste bei jeder Anmeldung
            Send(BuildMembers(l), ep);
            foreach (PesRvMember x in l.Members.Values) if (x.NodeId != nid) Send(BuildPeer(x), ep);
        }
    }

    private static bool Same(byte[] a, byte[] b)
    {
        if (a.Length != b.Length) return false;
        for (int i = 0; i < a.Length; i++) if (a[i] != b[i]) return false;
        return true;
    }

    private void OnLeave(byte[] b, int n, IPEndPoint ep)
    {
        if (n < 27) return;
        PesRvLobby l;
        if (!lobbies.TryGetValue(Hex(b, 3, 16), out l)) return;
        ulong nid = ReadU64(b, 19);
        PesRvMember m;
        if (!l.Members.TryGetValue(nid, out m) || !m.Ep.Equals(ep)) return;
        l.Members.Remove(nid);
        AddLog("Lobby " + l.Id.Substring(0, 8) + ": - " + Encoding.UTF8.GetString(m.Name) + " (abgemeldet) [" + l.Members.Count + " online]");
        NotifyGone(l, m);
    }

    private void OnRelay(byte[] b, int n, IPEndPoint ep)
    {
        if (n < 35 + 31) return;
        PesRvLobby l;
        if (!lobbies.TryGetValue(Hex(b, 3, 16), out l)) return;
        PesRvMember src, dst;
        if (!l.Members.TryGetValue(ReadU64(b, 19), out src) || !src.Ep.Equals(ep)) return;
        if (!l.Members.TryGetValue(ReadU64(b, 27), out dst)) return;
        long now = Now();
        long el = now - src.TokenTs;
        src.TokenTs = now;
        src.Tokens = Math.Min(RelayPps, src.Tokens + el * RelayPps / 1000.0);
        if (src.Tokens < 1) return;
        int bytes = n - 35 + 11;
        if (RelayMbitPerMember > 0)
        {
            double rate = RelayMbitPerMember * 125000.0;
            src.ByteTokens = Math.Min(rate, src.ByteTokens + el * rate / 1000.0);
            if (src.ByteTokens < bytes) { Interlocked.Increment(ref RelayDropped); return; }
        }
        if (RelayMbitTotal > 0)
        {
            double rate = RelayMbitTotal * 125000.0;
            totalTokens = Math.Min(rate, totalTokens + (now - totalTs) * rate / 1000.0);
            totalTs = now;
            if (totalTokens < bytes) { Interlocked.Increment(ref RelayDropped); return; }
            totalTokens -= bytes;
        }
        if (RelayMbitPerMember > 0) src.ByteTokens -= bytes;
        src.Tokens -= 1;
        src.LastSeen = now;
        byte[] f = new byte[3 + 8 + (n - 35)];
        f[0] = 0x50; f[1] = 0x53; f[2] = S_RELAYED;
        WriteU64(f, 3, src.NodeId);
        Buffer.BlockCopy(b, 35, f, 11, n - 35);
        Send(f, dst.Ep);
        Interlocked.Increment(ref RelayedPackets);
    }

    private void Cleanup(long now)
    {
        List<string> emptyLobbies = new List<string>();
        foreach (PesRvLobby l in lobbies.Values)
        {
            List<PesRvMember> dead = new List<PesRvMember>();
            foreach (PesRvMember m in l.Members.Values) if (now - m.LastSeen > 35000) dead.Add(m);
            foreach (PesRvMember d in dead)
            {
                AddLog("Lobby " + l.Id.Substring(0, 8) + ": - " + Encoding.UTF8.GetString(d.Name) + " (Timeout)");
                l.Members.Remove(d.NodeId);
                NotifyGone(l, d);
            }
            if (l.Members.Count == 0 && now - l.LastActive > 6L * 3600 * 1000) emptyLobbies.Add(l.Id);
        }
        foreach (string id in emptyLobbies) lobbies.Remove(id);
        int total = 0;
        foreach (PesRvLobby l in lobbies.Values) total += l.Members.Count;
        statsText = "Lobbys: " + lobbies.Count + ", Mitglieder: " + total;
        MemberCount = total;
    }
}

// ============================================================================
// Project Earth Support - Sitzungsschicht (plattformneutral, C# 5)
//   PesProto    : Konstanten, Einladungscode, u-law, IPv4/UDP-Huelle
//   PesRel      : zuverlaessiger, geordneter Nachrichtenstrom ueber UDP (Fenster, SACK)
//   PesSession  : Partnersuche (HELLO), Anruf, Ton, Video, Bildschirm, Eingaben, Chat, Dateien
// Dienst "Support": virtueller UDP-Port 9891, Magic-Byte 0xA8. Alles laeuft als normale
// IPv4/UDP-Pakete durch die unveraenderte P2P-Engine (AES-256-CTR + HMAC-SHA256 je Paket).
// Eingehenden Daten wird nie vertraut: Laengen, Zustaende und Absender werden geprueft.
// ============================================================================
public static class PesProto
{
    public const byte Magic = 0xA8;
    public const int Port = 9891;
    public const int Version = 1;
    public const int Mss = 1100;                 // Nutzdaten je Paket (MTU 1380 der Engine wird nie erreicht)
    public const int Frame = 320;                // 20 ms bei 16 kHz mono

    public const byte K_HELLO = 0x01, K_REL = 0x02, K_ACK = 0x03, K_BYE = 0x04, K_AUDIO = 0x10, K_VIDEO = 0x11;

    // Nachrichten auf Strom 0 (Steuerung)
    public const byte M_CHAT = 0x20, M_CALL = 0x21, M_MEDIA = 0x22;
    public const byte M_SCRREQ = 0x30, M_SCRSTAT = 0x31, M_INPUT = 0x32, M_SCROPT = 0x33;
    public const byte M_FOFFER = 0x40, M_FANSW = 0x41, M_FCANCEL = 0x44, M_FDONE = 0x45;
    // Strom 1 (Dateidaten) und Strom 2 (Bildschirm)
    public const byte M_FDATA = 0x42, M_FEND = 0x43, M_RECT = 0x60;

    public const int RoleHelper = 1, RoleCustomer = 2;
    public const int CallIdle = 0, CallOut = 1, CallIn = 2, CallActive = 3;

    public const int VideoChunk = 1100;
    public const int VideoMaxFrame = VideoChunk * 255;
    public const char Sep = (char)31;            // Trenner in Ereigniszeilen (kommt in Texten nicht vor)

    public static byte MuLawEncode(short sample)
    {
        int s = sample;
        int sign = (s >> 8) & 0x80;
        if (sign != 0) s = -s;
        if (s > 32635) s = 32635;
        s += 0x84;
        int exponent = 7;
        int mask = 0x4000;
        while ((s & mask) == 0 && exponent > 0) { exponent--; mask >>= 1; }
        int mantissa = (s >> (exponent + 3)) & 0x0F;
        return (byte)(~(sign | (exponent << 4) | mantissa));
    }

    public static short MuLawDecode(byte b)
    {
        int u = (~b) & 0xFF;
        int sign = u & 0x80;
        int exponent = (u >> 4) & 0x07;
        int mantissa = u & 0x0F;
        int s = ((mantissa << 3) + 0x84) << exponent;
        s -= 0x84;
        return (short)(sign != 0 ? -s : s);
    }

    // ---- Einladungscode "PES1:" + Base64url(Server \n Lobby \n Passwort) ----
    public static string InviteCreate(string server, string lobby, string password)
    {
        byte[] raw = Encoding.UTF8.GetBytes(server + "\n" + lobby + "\n" + password);
        return "PES1:" + Convert.ToBase64String(raw).TrimEnd('=').Replace('+', '-').Replace('/', '_');
    }

    // Liefert { Server, Lobby, Passwort } oder null.
    public static string[] InviteParse(string text)
    {
        if (string.IsNullOrEmpty(text)) return null;
        int i = text.IndexOf("PES1:", StringComparison.Ordinal);
        if (i < 0) return null;
        StringBuilder sb = new StringBuilder();
        for (int k = i + 5; k < text.Length && sb.Length < 600; k++)
        {
            char c = text[k];
            bool ok = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_';
            if (!ok) break;
            sb.Append(c);
        }
        if (sb.Length == 0) return null;
        try
        {
            string b = sb.ToString().Replace('-', '+').Replace('_', '/');
            while (b.Length % 4 != 0) b += "=";
            string s = Encoding.UTF8.GetString(Convert.FromBase64String(b));
            string[] parts = s.Split('\n');
            if (parts.Length < 3 || parts[0].Length == 0 || parts[1].Length == 0) return null;
            string pw = string.Join("\n", parts, 2, parts.Length - 2);
            return new string[] { parts[0], parts[1], pw };
        }
        catch { return null; }
    }

    // Zerlegt "host" oder "host:port"; null bei ungueltiger Eingabe.
    public static bool ParseServer(string text, int defaultPort, out string host, out int port)
    {
        host = null; port = defaultPort;
        if (text == null) return false;
        string t = text.Trim();
        if (t.Length == 0 || t.Length > 255) return false;
        int c = t.LastIndexOf(':');
        string h = t;
        if (c >= 0)
        {
            h = t.Substring(0, c);
            int p;
            if (!int.TryParse(t.Substring(c + 1), out p) || p < 1 || p > 65535) return false;
            port = p;
        }
        if (h.Length == 0) return false;
        foreach (char ch in h)
        {
            bool ok = (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '.' || ch == '-';
            if (!ok) return false;
        }
        host = h;
        return true;
    }

    private const string Alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789";

    public static string RandomText(int length)
    {
        byte[] r = new byte[length * 2];
        using (RandomNumberGenerator rng = RandomNumberGenerator.Create()) rng.GetBytes(r);
        StringBuilder sb = new StringBuilder(length);
        for (int i = 0; i < length; i++) sb.Append(Alphabet[((r[i * 2] << 8) | r[i * 2 + 1]) % Alphabet.Length]);
        return sb.ToString();
    }

    public static string NewLobby() { return "pes-" + RandomText(12).ToLowerInvariant(); }
    public static string NewPassword() { return RandomText(24); }

    // ---- IPv4/UDP-Huelle (die Engine transportiert IPv4-Pakete) ----
    public static byte[] Wrap(uint src, uint dst, int ipId, byte[] payload, int len)
    {
        byte[] p = new byte[28 + len];
        p[0] = 0x45; p[1] = 0;
        PesBytes.WriteU16(p, 2, 28 + len);
        PesBytes.WriteU16(p, 4, ipId & 0xFFFF);
        p[6] = 0x40; p[7] = 0;                    // nicht fragmentieren
        p[8] = 64; p[9] = 17;                     // TTL, UDP
        PesBytes.WriteU32(p, 12, src);
        PesBytes.WriteU32(p, 16, dst);
        int sum = 0;
        for (int i = 0; i < 20; i += 2) sum += (p[i] << 8) | p[i + 1];
        while ((sum >> 16) != 0) sum = (sum & 0xFFFF) + (sum >> 16);
        PesBytes.WriteU16(p, 10, (~sum) & 0xFFFF);
        PesBytes.WriteU16(p, 20, Port);
        PesBytes.WriteU16(p, 22, Port);
        PesBytes.WriteU16(p, 24, 8 + len);
        p[26] = 0; p[27] = 0;                     // UDP-Pruefsumme 0 = keine (IPv4 erlaubt; HMAC der Engine schuetzt)
        Buffer.BlockCopy(payload, 0, p, 28, len);
        return p;
    }

    // Liefert den Offset der Nutzdaten oder -1; src = virtuelle IP des Absenders.
    public static int Unwrap(byte[] ip, out uint src, out int len)
    {
        src = 0; len = 0;
        if (ip == null || ip.Length < 30) return -1;
        if ((ip[0] >> 4) != 4) return -1;
        int ihl = (ip[0] & 15) * 4;
        if (ihl < 20 || ip.Length < ihl + 10) return -1;
        if (ip[9] != 17) return -1;
        if ((PesBytes.ReadU16(ip, 6) & 0x3FFF) != 0) return -1;      // Fragmente werden nicht angenommen
        int total = PesBytes.ReadU16(ip, 2);
        if (total > ip.Length || total < ihl + 10) return -1;
        if (PesBytes.ReadU16(ip, ihl + 2) != Port) return -1;
        int ulen = PesBytes.ReadU16(ip, ihl + 4);
        if (ulen < 10 || ihl + ulen > total) return -1;
        if (ip[ihl + 8] != Magic) return -1;
        src = PesBytes.ReadU32(ip, 12);
        len = ulen - 8;
        return ihl + 8;
    }

    public static string CleanName(string s, int max)
    {
        if (s == null) return "";
        StringBuilder sb = new StringBuilder();
        foreach (char c in s)
        {
            if (c < 32 || c == 127) continue;
            sb.Append(c);
            if (sb.Length >= max) break;
        }
        return sb.ToString().Trim();
    }

    // Dateiname aus dem Netz: nie Pfade, keine reservierten Zeichen, begrenzte Laenge.
    public static string CleanFileName(string s)
    {
        if (s == null) s = "";
        int cut = Math.Max(s.LastIndexOf('/'), s.LastIndexOf('\\'));
        if (cut >= 0) s = s.Substring(cut + 1);
        StringBuilder sb = new StringBuilder();
        foreach (char c in s)
        {
            if (c < 32 || c == 127 || c == '<' || c == '>' || c == ':' || c == '"' || c == '/' || c == '\\' || c == '|' || c == '?' || c == '*') { sb.Append('_'); continue; }
            sb.Append(c);
            if (sb.Length >= 120) break;
        }
        string r = sb.ToString().Trim().TrimEnd('.', ' ');
        while (r.StartsWith(".")) r = r.Substring(1);
        if (r.Length == 0) r = "datei";
        string up = r.ToUpperInvariant();
        int dot = up.IndexOf('.');
        string stem = dot < 0 ? up : up.Substring(0, dot);
        string[] reserved = new string[] { "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9" };
        foreach (string x in reserved) if (stem == x) { r = "_" + r; break; }
        return r;
    }
}

// ----------------------------------------------------------------------------
// Zuverlaessiger Nachrichtenstrom. Paket (nach Magic/Art/Epoche/Strom):
//   REL: seq(4) | fl(1) | Daten      fl Bit0 = Nachrichtenanfang, Bit1 = Nachrichtenende
//   ACK: cum(4) | sack(8)            cum = naechste erwartete Nummer, sack = Bits fuer cum+1 .. cum+64
// Nicht threadsicher - die Sitzung sperrt.
// ----------------------------------------------------------------------------
public sealed class PesRel
{
    private sealed class Seg
    {
        public byte[] Data; public byte Fl; public long LastTx; public int TxCount; public bool Sacked;
    }

    public readonly int Id;
    public const int MaxMessage = 8 * 1024 * 1024;
    private const int RxWindow = 1024;
    private const int MinWindow = 12;            // darunter faellt das Sendefenster nie (zufaellige Verluste sind kein Stau)

    // Senden
    private readonly Queue<byte[]> txMsgs = new Queue<byte[]>();
    private int txOff;
    private long queuedBytes, flightBytes;
    private uint sndUna, sndNxt;
    private readonly Dictionary<uint, Seg> flight = new Dictionary<uint, Seg>();
    private double cwnd = 16, ssthresh = 96;
    private int srtt = -1, rttvar = 0;
    private long lastCutMs = -100000;
    private uint recoverSeq;
    private bool hasSack; private uint highSack;  // hoechstes Paket, das die Gegenseite ausser der Reihe schon hat
    // Empfangen
    private uint rcvNxt;
    private readonly Dictionary<uint, Seg> ooo = new Dictionary<uint, Seg>();
    private MemoryStream asm;
    public bool AckDue;

    public long Retransmits;

    public PesRel(int id) { Id = id; }

    public long Backlog { get { return queuedBytes + flightBytes; } }
    public int Rtt { get { return srtt; } }
    public bool Idle { get { return txMsgs.Count == 0 && flight.Count == 0; } }

    public void Reset()
    {
        txMsgs.Clear(); txOff = 0; queuedBytes = 0; flightBytes = 0;
        sndUna = 0; sndNxt = 0; flight.Clear();
        cwnd = 16; ssthresh = 96; srtt = -1; rttvar = 0; lastCutMs = -100000; recoverSeq = 0;
        hasSack = false; highSack = 0;
        rcvNxt = 0; ooo.Clear(); asm = null; AckDue = false;
    }

    public void Enqueue(byte[] msg)
    {
        if (msg == null || msg.Length == 0 || msg.Length > MaxMessage) return;
        txMsgs.Enqueue(msg);
        queuedBytes += msg.Length;
    }

    private int Rto()
    {
        if (srtt < 0) return 400;
        int r = srtt + 4 * rttvar + 20;
        if (r < 120) r = 120;
        if (r > 1500) r = 1500;
        return r;
    }

    private static byte[] Build(uint seq, Seg s)
    {
        byte[] p = new byte[5 + s.Data.Length];
        PesBytes.WriteU32(p, 0, seq);
        p[4] = s.Fl;
        Buffer.BlockCopy(s.Data, 0, p, 5, s.Data.Length);
        return p;
    }

    // Faellige Wiederholungen und neue Pakete erzeugen (hoechstens budget Stueck).
    public void Pump(long now, int budget, List<byte[]> outPackets)
    {
        if (flight.Count > 0)
        {
            int rto = Rto();
            // Liegt ein Paket nachweislich hinter einer Luecke (die Gegenseite hat schon spaetere), reicht eine kurze Wartezeit
            int holeGate = srtt < 0 ? 60 : Math.Max(40, srtt * 3 / 2);
            uint s = sndUna;
            int scanned = 0;
            while (s != sndNxt && budget > 0 && scanned < 2048)
            {
                Seg g;
                if (flight.TryGetValue(s, out g) && !g.Sacked)
                {
                    bool hole = hasSack && (int)(highSack - s) >= 2;
                    int back = g.TxCount - 3; if (back < 0) back = 0; if (back > 2) back = 2;
                    long wait = hole ? holeGate : ((long)rto << back);
                    if (now - g.LastTx > wait)
                    {
                        g.LastTx = now; g.TxCount++; Retransmits++;
                        outPackets.Add(Build(s, g)); budget--;
                        if (now - lastCutMs > Math.Max(rto, 200) && (int)(s - recoverSeq) >= 0)
                        {
                            lastCutMs = now;
                            ssthresh = Math.Max(MinWindow, cwnd * 0.7);
                            cwnd = Math.Max(MinWindow, cwnd * 0.7);
                            recoverSeq = sndNxt;
                        }
                    }
                }
                s++; scanned++;
            }
        }
        while (budget > 0 && txMsgs.Count > 0 && (int)(sndNxt - sndUna) < (int)cwnd && (int)(sndNxt - sndUna) < RxWindow - 8)
        {
            byte[] m = txMsgs.Peek();
            int n = Math.Min(PesProto.Mss, m.Length - txOff);
            Seg g = new Seg();
            g.Data = new byte[n];
            Buffer.BlockCopy(m, txOff, g.Data, 0, n);
            g.Fl = (byte)((txOff == 0 ? 1 : 0) | (txOff + n >= m.Length ? 2 : 0));
            g.LastTx = now; g.TxCount = 1;
            txOff += n;
            queuedBytes -= n; flightBytes += n;
            if (txOff >= m.Length) { txMsgs.Dequeue(); txOff = 0; }
            flight[sndNxt] = g;
            outPackets.Add(Build(sndNxt, g));
            sndNxt++; budget--;
        }
    }

    public void OnAck(uint cum, ulong sack, long now, List<byte[]> outPackets)
    {
        if ((int)(cum - sndUna) < 0 || (int)(sndNxt - cum) < 0) return;      // veraltet oder unplausibel
        while (sndUna != cum)
        {
            Seg g;
            if (flight.TryGetValue(sndUna, out g))
            {
                flight.Remove(sndUna);
                flightBytes -= g.Data.Length;
                // Laufzeit nur von Paketen messen, die nie wiederholt wurden und nicht hinter einer Luecke warteten
                if (g.TxCount == 1 && !g.Sacked) Sample((int)(now - g.LastTx));
                if (cwnd < ssthresh) cwnd += 1; else cwnd += 1.0 / cwnd;
                if (cwnd > 256) cwnd = 256;
            }
            sndUna++;
        }
        if (hasSack && (int)(highSack - sndUna) < 0) hasSack = false;
        if (sack == 0) return;
        for (int i = 0; i < 64; i++)
        {
            if ((sack & (1UL << i)) == 0) continue;
            uint q = cum + 1 + (uint)i;
            Seg g;
            if (!flight.TryGetValue(q, out g)) continue;
            if (!g.Sacked) { g.Sacked = true; if (g.TxCount == 1) Sample((int)(now - g.LastTx)); }
            if (!hasSack || (int)(q - highSack) > 0) { hasSack = true; highSack = q; }
        }
        // Luecken sofort schliessen (Pump prueft die kurze Wartezeit je Paket)
        Pump(now, 8, outPackets);
    }

    private void Sample(int rtt)
    {
        if (rtt < 0) return;
        if (rtt > 5000) rtt = 5000;
        if (srtt < 0) { srtt = rtt; rttvar = rtt / 2; }
        else
        {
            int d = Math.Abs(srtt - rtt);
            rttvar = (3 * rttvar + d) / 4;
            srtt = (7 * srtt + rtt) / 8;
        }
    }

    // Ein eingehendes Datenpaket; vollstaendige Nachrichten landen in deliver.
    public void OnData(byte[] buf, int off, int len, List<byte[]> deliver)
    {
        if (len < 6) return;
        uint seq = PesBytes.ReadU32(buf, off);
        byte fl = buf[off + 4];
        int n = len - 5;
        if (n > PesProto.Mss + 64) return;
        AckDue = true;
        int d = (int)(seq - rcvNxt);
        if (d < 0 || d >= RxWindow) return;                              // doppelt oder zu weit voraus
        if (d > 0)
        {
            if (!ooo.ContainsKey(seq))
            {
                Seg g = new Seg(); g.Fl = fl; g.Data = new byte[n];
                Buffer.BlockCopy(buf, off + 5, g.Data, 0, n);
                ooo[seq] = g;
            }
            return;
        }
        Accept(fl, buf, off + 5, n, deliver);
        rcvNxt++;
        Seg nx;
        while (ooo.TryGetValue(rcvNxt, out nx))
        {
            ooo.Remove(rcvNxt);
            Accept(nx.Fl, nx.Data, 0, nx.Data.Length, deliver);
            rcvNxt++;
        }
    }

    private void Accept(byte fl, byte[] b, int off, int n, List<byte[]> deliver)
    {
        if ((fl & 1) != 0) asm = new MemoryStream();
        if (asm == null) return;                                        // Mitte ohne Anfang: verwerfen
        if (asm.Length + n > MaxMessage) { asm = null; return; }
        asm.Write(b, off, n);
        if ((fl & 2) != 0) { deliver.Add(asm.ToArray()); asm = null; }
    }

    public byte[] BuildAck()
    {
        AckDue = false;
        byte[] p = new byte[12];
        PesBytes.WriteU32(p, 0, rcvNxt);
        ulong sack = 0;
        if (ooo.Count > 0)
        {
            for (int i = 0; i < 64; i++) if (ooo.ContainsKey(rcvNxt + 1 + (uint)i)) sack |= 1UL << i;
        }
        PesBytes.WriteU64(p, 4, sack);
        return p;
    }
}

public sealed class PesFileInfo
{
    public uint Id;
    public string Name = "";
    public string Path = "";
    public long Size;
    public long Done;
    public int State;        // 0 = wartet auf Antwort, 1 = laeuft, 2 = fertig, 3 = abgebrochen/Fehler, 4 = gesendet, wartet auf Bestaetigung
    public string Error = "";
}

public sealed class PesSession
{
    // ---- Einstellungen (vor Start() setzen) ----
    public string MyName = "";
    public int Role = PesProto.RoleCustomer;
    public int Platform = 1;                     // 1 = Windows, 2 = Android
    public string DownloadDir = "";
    public long MaxFileSize = 4L * 1024 * 1024 * 1024;

    // ---- Rueckrufe (kommen aus Arbeits-Threads, muessen schnell sein) ----
    public volatile Action<byte[], int> OnVideoFrame;                    // JPEG, Drehung 0..3
    public volatile Action<int[], byte[]> OnScreenRect;                  // { sw, sh, x, y, w, h, fl }, JPEG
    public volatile Action<byte[]> OnInput;                              // Eingabe vom Helfer (nur bei erlaubter Steuerung)

    // ---- Ereignisse fuer die Oberflaeche (per Timer abholen): Felder mit PesProto.Sep getrennt ----
    public readonly ConcurrentQueue<string> Events = new ConcurrentQueue<string>();

    // ---- Zustand ----
    public volatile bool Paired;
    public volatile string PartnerName = "";
    public volatile int PartnerRole;
    public volatile int PartnerPlatform;
    public volatile uint PartnerVip;
    public volatile int CallState;
    public volatile bool PartnerCam, PartnerMic;
    public volatile bool MyCam, MyMic = true;
    public volatile bool ShareActive, ControlActive;                     // Kunde: eigener Zustand; Helfer: Zustand des Kunden
    public volatile int ScreenW, ScreenH, ScreenMonitor, ScreenMonitors;
    public volatile int WantQuality = 2, WantMonitor = 0;                // Kunde: Wunsch des Helfers
    private long lastVideoRx, lastAudioRx;

    private readonly PesP2pEngine engine;
    private readonly object lk = new object();
    private readonly PesRel[] rel = new PesRel[] { new PesRel(0), new PesRel(1), new PesRel(2) };
    private static readonly Stopwatch clock = Stopwatch.StartNew();
    private Thread thread;
    private volatile bool running;
    private uint mySid, partnerSid;
    private bool handshake;
    private long lastHelloTx = -100000, lastPartnerRx, callSince;
    private int ipId, audioSeq, videoSeq;
    // Zeiger (zusammengefasst, hoechstens alle 25 ms)
    private int ptrX = -1, ptrY = -1; private bool ptrDirty; private long lastPtrTx;
    // Ton
    private readonly Queue<short[]> jitter = new Queue<short[]>();
    private bool jitterPlaying;
    // Video-Empfang
    private int vSeq = -1, vCount, vGot, vBytes, vRot; private byte[][] vParts;
    // Dateien
    private PesFileInfo txFile, rxFile;
    private FileStream txStream, rxStream;
    private SHA256 txHash, rxHash;
    private string rxTemp = "";

    public PesSession(PesP2pEngine eng) { engine = eng; }

    private static long Now() { return clock.ElapsedMilliseconds; }
    public long VideoAgeMs { get { long t = Interlocked.Read(ref lastVideoRx); return t == 0 ? long.MaxValue : Now() - t; } }
    public long AudioAgeMs { get { long t = Interlocked.Read(ref lastAudioRx); return t == 0 ? long.MaxValue : Now() - t; } }
    public long ScreenBacklog { get { lock (lk) { return rel[2].Backlog; } } }
    public long Retransmits { get { lock (lk) { return rel[0].Retransmits + rel[1].Retransmits + rel[2].Retransmits; } } }
    public int Rtt { get { lock (lk) { return rel[0].Rtt; } } }

    private void Ev(params string[] f) { Events.Enqueue(string.Join(PesProto.Sep.ToString(), f)); string d; while (Events.Count > 2000 && Events.TryDequeue(out d)) { } }

    public void Start()
    {
        if (running) return;
        byte[] r = new byte[4];
        using (RandomNumberGenerator rng = RandomNumberGenerator.Create()) { do { rng.GetBytes(r); mySid = PesBytes.ReadU32(r, 0); } while (mySid == 0); }
        MyName = PesProto.CleanName(MyName, 32);
        running = true;
        engine.InboundSink = OnIp;
        thread = new Thread(Loop); thread.IsBackground = true; thread.Name = "PES-SESSION"; thread.Start();
    }

    public void Stop()
    {
        if (!running) return;
        try { if (CallState != PesProto.CallIdle) Hangup(); } catch { }
        try { lock (lk) { FlushLocked(Now()); } } catch { }
        try { if (Paired) { SendBye(); Thread.Sleep(30); SendBye(); } } catch { }
        running = false;
        if (thread != null) thread.Join(1500);
        engine.InboundSink = null;
        lock (lk) { Unpair("", false); }
    }

    // =========================================================================
    // Senden (roh)
    // =========================================================================
    private void SendRaw(uint dst, byte[] payload)
    {
        uint my = engine.Vip;
        if (my == 0 || dst == 0) return;
        int id = Interlocked.Increment(ref ipId);
        engine.SendIp(PesProto.Wrap(my, dst, id, payload, payload.Length));
    }

    private void SendHello(uint dst, bool toPartner)
    {
        byte[] nm = PesBytes.Utf8Limit(MyName, 32);
        byte[] p = new byte[15 + nm.Length];
        p[0] = PesProto.Magic; p[1] = PesProto.K_HELLO;
        p[2] = PesProto.Version; p[3] = (byte)Role; p[4] = (byte)Platform;
        p[5] = (byte)((Paired && !toPartner) ? 1 : 0);                  // Bit0 = bereits in einer Sitzung
        PesBytes.WriteU32(p, 6, mySid);
        PesBytes.WriteU32(p, 10, toPartner ? partnerSid : 0);
        p[14] = (byte)nm.Length;
        Buffer.BlockCopy(nm, 0, p, 15, nm.Length);
        SendRaw(dst, p);
    }

    // Abmeldung: der Partner muss nicht erst auf den Zeitablauf warten.
    private void SendBye()
    {
        byte[] p = new byte[6];
        p[0] = PesProto.Magic; p[1] = PesProto.K_BYE;
        PesBytes.WriteU32(p, 2, mySid);
        SendRaw(PartnerVip, p);
    }

    private void SendRelPacket(int stream, byte kind, byte[] body)
    {
        byte[] p = new byte[7 + body.Length];
        p[0] = PesProto.Magic; p[1] = kind;
        PesBytes.WriteU32(p, 2, mySid ^ partnerSid);
        p[6] = (byte)stream;
        Buffer.BlockCopy(body, 0, p, 7, body.Length);
        SendRaw(PartnerVip, p);
    }

    // Unter lk: Wiederholungen, neue Pakete und Bestaetigungen aller Stroeme senden.
    private void FlushLocked(long now)
    {
        if (!handshake) return;
        List<byte[]> pk = new List<byte[]>();
        for (int i = 0; i < rel.Length; i++)
        {
            pk.Clear();
            rel[i].Pump(now, i == 0 ? 16 : 12, pk);
            foreach (byte[] b in pk) SendRelPacket(i, PesProto.K_REL, b);
            if (rel[i].AckDue) SendRelPacket(i, PesProto.K_ACK, rel[i].BuildAck());
        }
    }

    private bool SendMsg(int stream, byte[] msg)
    {
        lock (lk)
        {
            if (!handshake) return false;
            rel[stream].Enqueue(msg);
            if (stream == 0) FlushLocked(Now());
            return true;
        }
    }

    private static byte[] Msg(byte type, params byte[] body)
    {
        byte[] m = new byte[1 + body.Length];
        m[0] = type;
        Buffer.BlockCopy(body, 0, m, 1, body.Length);
        return m;
    }

    // =========================================================================
    // Arbeits-Thread
    // =========================================================================
    private void Loop()
    {
        while (running)
        {
            try { Tick(); } catch (Exception ex) { Ev("SYS", "Sitzungsfehler: " + ex.Message); }
            Thread.Sleep(5);
        }
    }

    private void Tick()
    {
        long now = Now();
        List<uint> helloTo = null;
        lock (lk)
        {
            if (Paired && now - lastPartnerRx > 12000) Unpair("Verbindung zum Partner verloren.", true);
            if (CallState == PesProto.CallOut && now - callSince > 45000) { CallState = PesProto.CallIdle; Ev("CALL", "timeout"); EnqueueLocked(0, Msg(PesProto.M_CALL, 5)); }
            if (CallState == PesProto.CallIn && now - callSince > 50000) { CallState = PesProto.CallIdle; Ev("CALL", "missed"); }
            int iv = handshake ? 2000 : 500;
            if (now - lastHelloTx >= iv)
            {
                lastHelloTx = now;
                helloTo = new List<uint>();
                foreach (PesP2pPeerInfo pi in engine.GetPeers()) if (pi.Path != 0 && pi.Vip != 0) helloTo.Add(pi.Vip);
            }
            if (handshake)
            {
                if (ptrDirty && now - lastPtrTx >= 25 && rel[0].Backlog < 4000)
                {
                    ptrDirty = false; lastPtrTx = now;
                    byte[] b = new byte[6];
                    b[0] = PesProto.M_INPUT; b[1] = 1;
                    PesBytes.WriteU16(b, 2, ptrX); PesBytes.WriteU16(b, 4, ptrY);
                    rel[0].Enqueue(b);
                }
                PumpFileLocked();
                FlushLocked(now);
            }
        }
        if (helloTo != null)
        {
            uint pv = PartnerVip;
            foreach (uint v in helloTo) SendHello(v, Paired && v == pv);
        }
    }

    private void EnqueueLocked(int stream, byte[] msg) { if (handshake) rel[stream].Enqueue(msg); }

    // Unter lk. Setzt alles zurueck, was an den Partner gebunden ist.
    private void Unpair(string reason, bool notify)
    {
        bool was = Paired;
        Paired = false; handshake = false; partnerSid = 0;
        foreach (PesRel r in rel) r.Reset();
        CallState = PesProto.CallIdle; PartnerCam = false; PartnerMic = false;
        ShareActive = false; ControlActive = false;
        lock (jitter) { jitter.Clear(); jitterPlaying = false; vSeq = -1; vParts = null; }
        ptrDirty = false;
        AbortTxLocked("Verbindung getrennt", false);
        AbortRxLocked("Verbindung getrennt", false);
        PartnerVip = 0;
        if (was && notify) Ev("PEER", "down", PartnerName, reason);
        PartnerName = "";
    }

    // =========================================================================
    // Empfang (laeuft im UDP-Thread der Engine)
    // =========================================================================
    private void OnIp(byte[] ip)
    {
        if (!running) return;
        uint src; int len;
        int off = PesProto.Unwrap(ip, out src, out len);
        if (off < 0 || len < 2) return;
        byte kind = ip[off + 1];
        try
        {
            if (kind == PesProto.K_HELLO) { OnHello(ip, off, len, src); return; }
            if (!Paired || src != PartnerVip) return;                   // alles andere nur vom Partner
            if (kind == PesProto.K_BYE)
            {
                if (len >= 6) lock (lk) { if (Paired && PesBytes.ReadU32(ip, off + 2) == partnerSid) Unpair("Der Partner hat die Sitzung beendet.", true); }
                return;
            }
            if (kind == PesProto.K_AUDIO) { OnAudio(ip, off, len); return; }
            if (kind == PesProto.K_VIDEO) { OnVideo(ip, off, len); return; }
            if (kind == PesProto.K_REL || kind == PesProto.K_ACK) OnRel(kind, ip, off, len);
        }
        catch (Exception ex) { Ev("SYS", "Paketfehler: " + ex.Message); }
    }

    private void OnHello(byte[] b, int off, int len, uint src)
    {
        if (len < 15) return;
        if (b[off + 2] != PesProto.Version) return;
        int role = b[off + 3], plat = b[off + 4], flags = b[off + 5];
        uint sid = PesBytes.ReadU32(b, off + 6);
        uint echo = PesBytes.ReadU32(b, off + 10);
        int nl = b[off + 14];
        if (nl > 32 || 15 + nl > len || sid == 0) return;
        if (role != PesProto.RoleHelper && role != PesProto.RoleCustomer) return;
        string name = PesProto.CleanName(Encoding.UTF8.GetString(b, off + 15, nl), 32);
        if (name.Length == 0) name = "?";
        bool reply = false;
        lock (lk)
        {
            long now = Now();
            if (Paired && src == PartnerVip)
            {
                if (sid != partnerSid)
                {
                    // Partner hat neu gestartet: alles zuruecksetzen und neu koppeln
                    Unpair("Partner hat neu gestartet.", true);
                }
                else
                {
                    lastPartnerRx = now;
                    PartnerName = name;
                    if (!handshake && echo == mySid) { handshake = true; Ev("PEER", "up", name, role.ToString(), plat.ToString()); }
                    return;
                }
            }
            if (Paired) return;                                         // belegt: andere werden nicht angenommen
            if (role == Role) { return; }                               // Helfer koppelt nur mit Kunde und umgekehrt
            if ((flags & 1) != 0 && echo != mySid) return;              // Gegenseite ist schon vergeben
            Paired = true; PartnerVip = src; partnerSid = sid; PartnerName = name;
            PartnerRole = role; PartnerPlatform = plat; lastPartnerRx = now;
            handshake = echo == mySid;
            foreach (PesRel r in rel) r.Reset();
            if (handshake) Ev("PEER", "up", name, role.ToString(), plat.ToString());
            reply = true;
        }
        if (reply) SendHello(src, true);
    }

    private void OnRel(byte kind, byte[] b, int off, int len)
    {
        if (len < 7 + 5) return;
        List<byte[]> deliver = null;
        int stream;
        lock (lk)
        {
            if (!handshake) return;
            if (PesBytes.ReadU32(b, off + 2) != (mySid ^ partnerSid)) return;
            stream = b[off + 6];
            if (stream >= rel.Length) return;
            long now = Now();
            lastPartnerRx = now;
            if (kind == PesProto.K_REL)
            {
                deliver = new List<byte[]>();
                rel[stream].OnData(b, off + 7, len - 7, deliver);
                SendRelPacket(stream, PesProto.K_ACK, rel[stream].BuildAck());
            }
            else
            {
                if (len < 7 + 12) return;
                List<byte[]> pk = new List<byte[]>();
                rel[stream].OnAck(PesBytes.ReadU32(b, off + 7), PesBytes.ReadU64(b, off + 11), now, pk);
                rel[stream].Pump(now, 12, pk);                          // Fenster ist frei geworden: gleich nachschieben
                foreach (byte[] x in pk) SendRelPacket(stream, PesProto.K_REL, x);
            }
        }
        if (deliver != null) foreach (byte[] m in deliver) { try { OnMessage(stream, m); } catch (Exception ex) { Ev("SYS", "Nachrichtenfehler: " + ex.Message); } }
    }

    private void OnMessage(int stream, byte[] m)
    {
        if (m.Length < 1) return;
        byte t = m[0];
        if (stream == 2)
        {
            if (t != PesProto.M_RECT || m.Length < 14 || Role != PesProto.RoleHelper) return;
            int[] r = new int[7];
            for (int i = 0; i < 6; i++) r[i] = PesBytes.ReadU16(m, 1 + i * 2);
            r[6] = m[13];
            if (r[0] < 16 || r[1] < 16 || r[0] > 8192 || r[1] > 8192) return;
            if (r[4] < 1 || r[5] < 1 || r[2] + r[4] > r[0] || r[3] + r[5] > r[1]) return;
            byte[] jpg = new byte[m.Length - 14];
            Buffer.BlockCopy(m, 14, jpg, 0, jpg.Length);
            ScreenW = r[0]; ScreenH = r[1];
            Action<int[], byte[]> cb = OnScreenRect;
            if (cb != null) cb(r, jpg);
            return;
        }
        if (stream == 1) { OnFileStream(t, m); return; }
        switch (t)
        {
            case PesProto.M_CHAT:
                {
                    if (m.Length > 1 + 8000) return;
                    string text = Encoding.UTF8.GetString(m, 1, m.Length - 1).Replace(PesProto.Sep, ' ');
                    Ev("CHAT", PartnerName, text);
                    break;
                }
            case PesProto.M_CALL:
                if (m.Length >= 2) OnCall(m[1]);
                break;
            case PesProto.M_MEDIA:
                if (m.Length >= 3) { PartnerCam = m[1] != 0; PartnerMic = m[2] != 0; Ev("MEDIA", m[1].ToString(), m[2].ToString()); }
                break;
            case PesProto.M_SCRREQ:
                if (m.Length >= 2 && Role == PesProto.RoleCustomer && m[1] >= 1 && m[1] <= 5) Ev("SCREEN", "req", m[1].ToString());
                break;
            case PesProto.M_SCRSTAT:
                if (m.Length >= 9 && Role == PesProto.RoleHelper)
                {
                    ShareActive = m[1] != 0; ControlActive = m[1] != 0 && m[2] != 0;
                    ScreenW = PesBytes.ReadU16(m, 3); ScreenH = PesBytes.ReadU16(m, 5);
                    ScreenMonitor = m[7]; ScreenMonitors = m[8];
                    Ev("SCREEN", "state", m[1].ToString(), m[2].ToString());
                }
                break;
            case PesProto.M_INPUT:
                if (Role == PesProto.RoleCustomer && ControlActive && ShareActive && m.Length >= 2 && m.Length <= 1 + 1 + 1024)
                {
                    Action<byte[]> cb = OnInput;
                    if (cb != null) { byte[] body = new byte[m.Length - 1]; Buffer.BlockCopy(m, 1, body, 0, body.Length); cb(body); }
                }
                break;
            case PesProto.M_SCROPT:
                if (m.Length >= 3 && Role == PesProto.RoleCustomer)
                {
                    int q = m[1]; if (q < 1) q = 1; if (q > 3) q = 3;
                    WantQuality = q; WantMonitor = m[2];
                    Ev("SCREEN", "opt", q.ToString(), m[2].ToString());
                }
                break;
            case PesProto.M_FOFFER: OnFileOffer(m); break;
            case PesProto.M_FANSW: OnFileAnswer(m); break;
            case PesProto.M_FCANCEL: OnFileCancel(m); break;
            case PesProto.M_FDONE: OnFileDone(m); break;
        }
    }

    // =========================================================================
    // Chat
    // =========================================================================
    public bool SendChat(string text)
    {
        if (string.IsNullOrEmpty(text)) return false;
        if (text.Length > 2000) text = text.Substring(0, 2000);
        byte[] t = Encoding.UTF8.GetBytes(text);
        byte[] m = new byte[1 + t.Length];
        m[0] = PesProto.M_CHAT;
        Buffer.BlockCopy(t, 0, m, 1, t.Length);
        return SendMsg(0, m);
    }

    // =========================================================================
    // Anruf (Ton + Video)
    // =========================================================================
    private void OnCall(int sub)
    {
        bool sendAccept = false, media = false;
        lock (lk)
        {
            switch (sub)
            {
                case 1:
                    if (CallState == PesProto.CallIdle) { CallState = PesProto.CallIn; callSince = Now(); Ev("CALL", "in", PartnerName); }
                    else if (CallState == PesProto.CallOut) { CallState = PesProto.CallActive; sendAccept = true; media = true; Ev("CALL", "active"); }
                    break;
                case 2:
                    if (CallState == PesProto.CallOut) { CallState = PesProto.CallActive; media = true; Ev("CALL", "active"); }
                    break;
                case 3:
                    if (CallState == PesProto.CallOut) { CallState = PesProto.CallIdle; Ev("CALL", "declined"); }
                    break;
                case 4:
                    if (CallState != PesProto.CallIdle) { CallState = PesProto.CallIdle; ClearMediaLocked(); Ev("CALL", "ended"); }
                    break;
                case 5:
                    if (CallState == PesProto.CallIn) { CallState = PesProto.CallIdle; Ev("CALL", "missed"); }
                    break;
            }
        }
        if (sendAccept) SendMsg(0, Msg(PesProto.M_CALL, 2));
        if (media) SendMedia();
    }

    private void ClearMediaLocked() { lock (jitter) { jitter.Clear(); jitterPlaying = false; vSeq = -1; vParts = null; } PartnerCam = false; }

    public bool Call()
    {
        lock (lk)
        {
            if (!handshake || CallState != PesProto.CallIdle) return false;
            CallState = PesProto.CallOut; callSince = Now();
        }
        Ev("CALL", "out");
        return SendMsg(0, Msg(PesProto.M_CALL, 1));
    }

    public void AnswerCall(bool accept)
    {
        lock (lk)
        {
            if (CallState != PesProto.CallIn) return;
            CallState = accept ? PesProto.CallActive : PesProto.CallIdle;
        }
        SendMsg(0, Msg(PesProto.M_CALL, (byte)(accept ? 2 : 3)));
        if (accept) { Ev("CALL", "active"); SendMedia(); }
    }

    public void Hangup()
    {
        int st;
        lock (lk) { st = CallState; CallState = PesProto.CallIdle; ClearMediaLocked(); }
        if (st == PesProto.CallIdle) return;
        SendMsg(0, Msg(PesProto.M_CALL, (byte)(st == PesProto.CallOut ? 5 : (st == PesProto.CallIn ? 3 : 4))));
        Ev("CALL", "ended");
    }

    public void SetMedia(bool cam, bool mic)
    {
        MyCam = cam; MyMic = mic;
        if (CallState == PesProto.CallActive) SendMedia();
    }

    private void SendMedia() { SendMsg(0, Msg(PesProto.M_MEDIA, (byte)(MyCam ? 1 : 0), (byte)(MyMic ? 1 : 0))); }

    // Ein Mikrofon-Frame (320 Samples, 16 kHz mono).
    public void SendAudio(short[] f)
    {
        if (f == null || f.Length < PesProto.Frame) return;
        if (CallState != PesProto.CallActive || !MyMic || !Paired) return;
        byte[] p = new byte[4 + PesProto.Frame];
        p[0] = PesProto.Magic; p[1] = PesProto.K_AUDIO;
        int s = Interlocked.Increment(ref audioSeq);
        PesBytes.WriteU16(p, 2, s & 0xFFFF);
        for (int i = 0; i < PesProto.Frame; i++) p[4 + i] = PesProto.MuLawEncode(f[i]);
        SendRaw(PartnerVip, p);
    }

    private void OnAudio(byte[] b, int off, int len)
    {
        if (CallState != PesProto.CallActive) return;
        int n = len - 4;
        if (n != PesProto.Frame) return;
        short[] fr = new short[n];
        for (int i = 0; i < n; i++) fr[i] = PesProto.MuLawDecode(b[off + 4 + i]);
        Interlocked.Exchange(ref lastAudioRx, Now());
        lock (jitter)
        {
            jitter.Enqueue(fr);
            while (jitter.Count > 12) jitter.Dequeue();
        }
    }

    // Naechster Wiedergabe-Frame (320 Samples); Stille, solange nichts ansteht.
    public short[] PullAudio()
    {
        lock (jitter)
        {
            if (!jitterPlaying) { if (jitter.Count >= 3) jitterPlaying = true; else return new short[PesProto.Frame]; }
            if (jitter.Count == 0) { jitterPlaying = false; return new short[PesProto.Frame]; }
            return jitter.Dequeue();
        }
    }

    // Ein JPEG-Bild der eigenen Kamera, wird in Teilen gesendet (verlorene Bilder werden nicht wiederholt).
    public bool SendVideo(byte[] jpeg, int rotQuarter)
    {
        if (jpeg == null || jpeg.Length == 0 || jpeg.Length > PesProto.VideoMaxFrame) return false;
        if (CallState != PesProto.CallActive || !MyCam || !Paired) return false;
        int cnt = (jpeg.Length + PesProto.VideoChunk - 1) / PesProto.VideoChunk;
        int sq = Interlocked.Increment(ref videoSeq) & 0xFFFF;
        uint dst = PartnerVip;
        for (int i = 0; i < cnt; i++)
        {
            int o = i * PesProto.VideoChunk;
            int n = Math.Min(PesProto.VideoChunk, jpeg.Length - o);
            byte[] p = new byte[7 + n];
            p[0] = PesProto.Magic; p[1] = PesProto.K_VIDEO;
            PesBytes.WriteU16(p, 2, sq);
            p[4] = (byte)i; p[5] = (byte)cnt; p[6] = (byte)(rotQuarter & 3);
            Buffer.BlockCopy(jpeg, o, p, 7, n);
            SendRaw(dst, p);
        }
        return true;
    }

    private void OnVideo(byte[] b, int off, int len)
    {
        if (CallState != PesProto.CallActive || len < 8) return;
        int seq = PesBytes.ReadU16(b, off + 2);
        int idx = b[off + 4], cnt = b[off + 5], rot = b[off + 6] & 3;
        int n = len - 7;
        if (cnt == 0 || idx >= cnt || n <= 0 || n > PesProto.VideoChunk) return;
        byte[] done = null;
        lock (jitter)
        {
            if (vParts == null || vSeq != seq || vCount != cnt)
            {
                // Nur neuere Bilder beginnen (verspaetete Teile alter Bilder verwerfen)
                if (vParts != null && vSeq >= 0 && ((seq - vSeq) & 0xFFFF) > 0x8000) return;
                vSeq = seq; vCount = cnt; vGot = 0; vBytes = 0; vRot = rot; vParts = new byte[cnt][];
            }
            if (vParts[idx] != null) return;
            if (vBytes + n > PesProto.VideoMaxFrame) { vParts = null; return; }
            byte[] part = new byte[n];
            Buffer.BlockCopy(b, off + 7, part, 0, n);
            vParts[idx] = part; vGot++; vBytes += n;
            if (vGot == vCount)
            {
                done = new byte[vBytes];
                int o = 0;
                foreach (byte[] x in vParts) { Buffer.BlockCopy(x, 0, done, o, x.Length); o += x.Length; }
                vParts = null;
            }
        }
        if (done != null)
        {
            Interlocked.Exchange(ref lastVideoRx, Now());
            Action<byte[], int> cb = OnVideoFrame;
            if (cb != null) cb(done, rot);
        }
    }

    // =========================================================================
    // Bildschirm
    // =========================================================================
    // Helfer: 1 = ansehen, 2 = ansehen und steuern, 3 = beenden, 4 = Steuerung abgeben, 5 = Komplettbild neu senden
    public bool RequestScreen(int sub)
    {
        if (Role != PesProto.RoleHelper || sub < 1 || sub > 5) return false;
        return SendMsg(0, Msg(PesProto.M_SCRREQ, (byte)sub));
    }

    public bool SetScreenOptions(int quality, int monitor)
    {
        if (Role != PesProto.RoleHelper) return false;
        return SendMsg(0, Msg(PesProto.M_SCROPT, (byte)quality, (byte)monitor));
    }

    // Kunde: eigenen Freigabe-Zustand setzen und dem Helfer melden.
    public void SetShare(bool share, bool control, int w, int h, int monitor, int monitors)
    {
        if (Role != PesProto.RoleCustomer) return;
        ShareActive = share; ControlActive = share && control;
        ScreenW = w; ScreenH = h; ScreenMonitor = monitor; ScreenMonitors = monitors;
        byte[] m = new byte[9];
        m[0] = PesProto.M_SCRSTAT; m[1] = (byte)(share ? 1 : 0); m[2] = (byte)(share && control ? 1 : 0);
        PesBytes.WriteU16(m, 3, w); PesBytes.WriteU16(m, 5, h);
        m[7] = (byte)monitor; m[8] = (byte)monitors;
        SendMsg(0, m);
    }

    // Kunde: ein geaendertes Rechteck (JPEG) senden. fl Bit0 = letztes Rechteck dieses Durchgangs.
    public bool SendScreenRect(int sw, int sh, int x, int y, int w, int h, int fl, byte[] jpeg)
    {
        if (Role != PesProto.RoleCustomer || !ShareActive || jpeg == null) return false;
        byte[] m = new byte[14 + jpeg.Length];
        m[0] = PesProto.M_RECT;
        PesBytes.WriteU16(m, 1, sw); PesBytes.WriteU16(m, 3, sh);
        PesBytes.WriteU16(m, 5, x); PesBytes.WriteU16(m, 7, y);
        PesBytes.WriteU16(m, 9, w); PesBytes.WriteU16(m, 11, h);
        m[13] = (byte)fl;
        Buffer.BlockCopy(jpeg, 0, m, 14, jpeg.Length);
        lock (lk)
        {
            if (!handshake) return false;
            rel[2].Enqueue(m);
            FlushLocked(Now());
        }
        return true;
    }

    // ---- Eingaben des Helfers (Koordinaten 0..65535 bezogen auf den freigegebenen Bildschirm) ----
    public void InputMove(int x, int y)
    {
        if (Role != PesProto.RoleHelper || !ControlActive) return;
        lock (lk) { ptrX = Clamp16(x); ptrY = Clamp16(y); ptrDirty = true; }
    }

    private static int Clamp16(int v) { return v < 0 ? 0 : (v > 65535 ? 65535 : v); }

    private bool SendInput(byte[] body)
    {
        if (Role != PesProto.RoleHelper || !ControlActive) return false;
        byte[] m = new byte[1 + body.Length];
        m[0] = PesProto.M_INPUT;
        Buffer.BlockCopy(body, 0, m, 1, body.Length);
        lock (lk)
        {
            if (!handshake) return false;
            ptrDirty = false;                                           // die Taste traegt die aktuelle Position selbst
            rel[0].Enqueue(m);
            FlushLocked(Now());
        }
        return true;
    }

    public bool InputButton(int button, bool down, int x, int y)
    {
        byte[] b = new byte[7];
        b[0] = 2; b[1] = (byte)button; b[2] = (byte)(down ? 1 : 0);
        PesBytes.WriteU16(b, 3, Clamp16(x)); PesBytes.WriteU16(b, 5, Clamp16(y));
        return SendInput(b);
    }

    public bool InputWheel(int delta, int x, int y)
    {
        if (delta > 32767) delta = 32767; if (delta < -32768) delta = -32768;
        byte[] b = new byte[7];
        b[0] = 3; PesBytes.WriteU16(b, 1, delta & 0xFFFF);
        PesBytes.WriteU16(b, 3, Clamp16(x)); PesBytes.WriteU16(b, 5, Clamp16(y));
        return SendInput(b);
    }

    public bool InputKey(int vk, bool down, bool extended)
    {
        byte[] b = new byte[5];
        b[0] = 4; PesBytes.WriteU16(b, 1, vk & 0xFFFF); b[3] = (byte)(down ? 1 : 0); b[4] = (byte)(extended ? 1 : 0);
        return SendInput(b);
    }

    public bool InputText(string text)
    {
        if (string.IsNullOrEmpty(text)) return false;
        if (text.Length > 200) text = text.Substring(0, 200);
        byte[] t = Encoding.UTF8.GetBytes(text);
        byte[] b = new byte[1 + t.Length];
        b[0] = 5;
        Buffer.BlockCopy(t, 0, b, 1, t.Length);
        return SendInput(b);
    }

    // =========================================================================
    // Dateien (eine Uebertragung je Richtung; der Empfaenger muss zustimmen)
    // =========================================================================
    public PesFileInfo TxFile { get { lock (lk) { return Copy(txFile); } } }
    public PesFileInfo RxFile { get { lock (lk) { return Copy(rxFile); } } }

    private static PesFileInfo Copy(PesFileInfo f)
    {
        if (f == null) return null;
        PesFileInfo c = new PesFileInfo();
        c.Id = f.Id; c.Name = f.Name; c.Path = f.Path; c.Size = f.Size; c.Done = f.Done; c.State = f.State; c.Error = f.Error;
        return c;
    }

    // Liefert null bei Erfolg, sonst eine Fehlermeldung.
    public string OfferFile(string path)
    {
        try
        {
            FileInfo fi = new FileInfo(path);
            if (!fi.Exists) return "Datei nicht gefunden.";
            if (fi.Length > MaxFileSize) return "Datei ist zu gross.";
            lock (lk)
            {
                if (!handshake) return "Nicht verbunden.";
                if (txFile != null && (txFile.State < 2 || txFile.State == 4)) return "Es laeuft bereits eine Uebertragung.";
                byte[] r = new byte[4];
                using (RandomNumberGenerator rng = RandomNumberGenerator.Create()) rng.GetBytes(r);
                PesFileInfo f = new PesFileInfo();
                f.Id = PesBytes.ReadU32(r, 0); f.Name = PesProto.CleanFileName(fi.Name); f.Path = fi.FullName; f.Size = fi.Length;
                txFile = f;
                byte[] nm = PesBytes.Utf8Limit(f.Name, 240);
                byte[] m = new byte[13 + nm.Length];
                m[0] = PesProto.M_FOFFER;
                PesBytes.WriteU32(m, 1, f.Id);
                PesBytes.WriteU64(m, 5, (ulong)f.Size);
                Buffer.BlockCopy(nm, 0, m, 13, nm.Length);
                rel[0].Enqueue(m);
                FlushLocked(Now());
            }
            return null;
        }
        catch (Exception ex) { return ex.Message; }
    }

    private void OnFileOffer(byte[] m)
    {
        if (m.Length < 14 || m.Length > 13 + 300) return;
        uint id = PesBytes.ReadU32(m, 1);
        ulong size = PesBytes.ReadU64(m, 5);
        string name = PesProto.CleanFileName(Encoding.UTF8.GetString(m, 13, m.Length - 13));
        lock (lk)
        {
            if ((rxFile != null && rxFile.State < 2) || size > (ulong)MaxFileSize)
            {
                rel[0].Enqueue(Msg(PesProto.M_FANSW, m[1], m[2], m[3], m[4], 0));
                return;
            }
            PesFileInfo f = new PesFileInfo();
            f.Id = id; f.Name = name; f.Size = (long)size;
            rxFile = f;
        }
        Ev("FILE", "offer", id.ToString(), name, size.ToString());
    }

    // Empfaenger: Angebot annehmen oder ablehnen. Liefert null bei Erfolg.
    public string AnswerFile(bool accept)
    {
        lock (lk)
        {
            if (rxFile == null || rxFile.State != 0) return "Kein offenes Angebot.";
            byte[] a = new byte[6];
            a[0] = PesProto.M_FANSW; PesBytes.WriteU32(a, 1, rxFile.Id); a[5] = (byte)(accept ? 1 : 0);
            if (!accept) { rxFile.State = 3; rxFile.Error = "abgelehnt"; rel[0].Enqueue(a); FlushLocked(Now()); return null; }
            try
            {
                Directory.CreateDirectory(DownloadDir);
                rxTemp = System.IO.Path.Combine(DownloadDir, rxFile.Name + "." + rxFile.Id.ToString("x8") + ".part");
                rxStream = new FileStream(rxTemp, FileMode.Create, FileAccess.Write, FileShare.None, 65536);
                rxHash = SHA256.Create();
                rxFile.State = 1;
            }
            catch (Exception ex)
            {
                rxFile.State = 3; rxFile.Error = ex.Message;
                a[5] = 0; rel[0].Enqueue(a); FlushLocked(Now());
                return ex.Message;
            }
            rel[0].Enqueue(a); FlushLocked(Now());
        }
        return null;
    }

    private void OnFileAnswer(byte[] m)
    {
        if (m.Length < 6) return;
        uint id = PesBytes.ReadU32(m, 1);
        bool ok = m[5] != 0;
        lock (lk)
        {
            if (txFile == null || txFile.Id != id || txFile.State != 0) return;
            if (!ok) { txFile.State = 3; txFile.Error = "abgelehnt"; Ev("FILE", "declined", txFile.Name); return; }
            try
            {
                txStream = new FileStream(txFile.Path, FileMode.Open, FileAccess.Read, FileShare.Read, 65536);
                txHash = SHA256.Create();
                txFile.State = 1;
                Ev("FILE", "sending", txFile.Name);
            }
            catch (Exception ex) { AbortTxLocked(ex.Message, true); }
        }
    }

    // Unter lk: Dateidaten nachschieben, solange der Strom nicht staut.
    private void PumpFileLocked()
    {
        if (txFile == null || txFile.State != 1 || txStream == null) return;
        try
        {
            int rounds = 0;
            while (rel[1].Backlog < 256 * 1024 && rounds++ < 8)
            {
                byte[] buf = new byte[5 + 32768];
                int n = txStream.Read(buf, 5, 32768);
                if (n <= 0)
                {
                    txHash.TransformFinalBlock(new byte[0], 0, 0);
                    byte[] e = new byte[5 + 32];
                    e[0] = PesProto.M_FEND; PesBytes.WriteU32(e, 1, txFile.Id);
                    Buffer.BlockCopy(txHash.Hash, 0, e, 5, 32);
                    rel[1].Enqueue(e);
                    try { txStream.Close(); } catch { }
                    txStream = null;
                    txFile.State = 4;                                   // gesendet, wartet auf Bestaetigung
                    return;
                }
                txHash.TransformBlock(buf, 5, n, null, 0);
                buf[0] = PesProto.M_FDATA; PesBytes.WriteU32(buf, 1, txFile.Id);
                if (n < 32768) Array.Resize(ref buf, 5 + n);
                rel[1].Enqueue(buf);
                txFile.Done += n;
            }
        }
        catch (Exception ex) { AbortTxLocked(ex.Message, true); }
    }

    private void OnFileStream(byte t, byte[] m)
    {
        if (m.Length < 5) return;
        uint id = PesBytes.ReadU32(m, 1);
        string doneEv = null, donePath = null;
        lock (lk)
        {
            if (rxFile == null || rxFile.Id != id || rxFile.State != 1 || rxStream == null) return;
            try
            {
                if (t == PesProto.M_FDATA)
                {
                    int n = m.Length - 5;
                    if (rxFile.Done + n > rxFile.Size) { AbortRxLocked("mehr Daten als angekuendigt", true); return; }
                    rxStream.Write(m, 5, n);
                    rxHash.TransformBlock(m, 5, n, null, 0);
                    rxFile.Done += n;
                }
                else if (t == PesProto.M_FEND && m.Length >= 37)
                {
                    rxHash.TransformFinalBlock(new byte[0], 0, 0);
                    byte[] h = rxHash.Hash;
                    bool ok = rxFile.Done == rxFile.Size;
                    for (int i = 0; ok && i < 32; i++) if (h[i] != m[5 + i]) ok = false;
                    rxStream.Close(); rxStream = null;
                    if (!ok) { AbortRxLocked("Pruefsumme stimmt nicht", true); return; }
                    string target = System.IO.Path.Combine(DownloadDir, rxFile.Name);
                    int k = 1;
                    while (File.Exists(target) || Directory.Exists(target))
                    {
                        string stem = System.IO.Path.GetFileNameWithoutExtension(rxFile.Name), ext = System.IO.Path.GetExtension(rxFile.Name);
                        target = System.IO.Path.Combine(DownloadDir, stem + " (" + k + ")" + ext);
                        k++;
                    }
                    File.Move(rxTemp, target);
                    rxFile.Path = target; rxFile.State = 2;
                    byte[] d = new byte[6];
                    d[0] = PesProto.M_FDONE; PesBytes.WriteU32(d, 1, id); d[5] = 1;
                    rel[0].Enqueue(d);
                    doneEv = rxFile.Name; donePath = target;
                }
            }
            catch (Exception ex) { AbortRxLocked(ex.Message, true); }
        }
        if (doneEv != null) Ev("FILE", "received", doneEv, donePath);
    }

    private void OnFileCancel(byte[] m)
    {
        if (m.Length < 5) return;
        uint id = PesBytes.ReadU32(m, 1);
        lock (lk)
        {
            if (rxFile != null && rxFile.Id == id && rxFile.State < 2) AbortRxLocked("vom Absender abgebrochen", false);
            if (txFile != null && txFile.Id == id && (txFile.State < 2 || txFile.State == 4)) AbortTxLocked("vom Empfaenger abgebrochen", false);
        }
    }

    private void OnFileDone(byte[] m)
    {
        if (m.Length < 6) return;
        uint id = PesBytes.ReadU32(m, 1);
        lock (lk)
        {
            if (txFile == null || txFile.Id != id) return;
            if (m[5] != 0) { txFile.State = 2; Ev("FILE", "sent", txFile.Name); }
            else { txFile.State = 3; txFile.Error = "Empfaenger meldet Fehler"; Ev("FILE", "failed", txFile.Name, txFile.Error); }
        }
    }

    public void CancelFiles()
    {
        lock (lk)
        {
            if (txFile != null && (txFile.State < 2 || txFile.State == 4)) AbortTxLocked("abgebrochen", true);
            if (rxFile != null && rxFile.State < 2) AbortRxLocked("abgebrochen", true);
            FlushLocked(Now());
        }
    }

    private void AbortTxLocked(string why, bool tell)
    {
        try { if (txStream != null) txStream.Close(); } catch { }
        txStream = null;
        if (txFile == null || txFile.State == 2 || txFile.State == 3) return;
        txFile.State = 3; txFile.Error = why;
        if (tell && handshake) { byte[] c = new byte[5]; c[0] = PesProto.M_FCANCEL; PesBytes.WriteU32(c, 1, txFile.Id); rel[0].Enqueue(c); }
        Ev("FILE", "failed", txFile.Name, why);
    }

    private void AbortRxLocked(string why, bool tell)
    {
        try { if (rxStream != null) rxStream.Close(); } catch { }
        rxStream = null;
        try { if (rxTemp.Length > 0 && File.Exists(rxTemp)) File.Delete(rxTemp); } catch { }
        rxTemp = "";
        if (rxFile == null || rxFile.State == 2 || rxFile.State == 3) return;
        bool wasOffer = rxFile.State == 0;
        rxFile.State = 3; rxFile.Error = why;
        if (tell && handshake) { byte[] c = new byte[5]; c[0] = PesProto.M_FCANCEL; PesBytes.WriteU32(c, 1, rxFile.Id); rel[0].Enqueue(c); }
        Ev("FILE", wasOffer ? "withdrawn" : "failed", rxFile.Name, why);
    }
}

// ============================================================================
// Project Earth Support - Windows-Teil (C# 5)
//   PesNative     : P/Invoke (Konsole ausblenden, Bildschirm, Zeiger, Eingaben)
//   PesScreen     : Bildschirm aufnehmen, geaenderte Bereiche als JPEG senden (Kunde)
//   PesInput      : Maus und Tastatur des Helfers ausfuehren (Kunde, nur nach Erlaubnis)
//   PesWinmm/...  : Mikrofon und Lautsprecher (16 kHz mono, wie im Project Earth LAN Manager)
//   PesCamera     : Webcam ueber Media Foundation, Bilder als JPEG
//   PesVideoPanel : Anzeige eines Videobilds      PesViewPanel : Anzeige und Bedienung des fernen Bildschirms
//   PesHost       : verbindet Sitzung, Geraete und Anzeige; wird von PowerShell bedient
// ============================================================================
public static class PesNative
{
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
    [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr ctx);
    [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
    [DllImport("gdi32.dll")] public static extern bool BitBlt(IntPtr hdcDest, int x, int y, int w, int h, IntPtr hdcSrc, int sx, int sy, int rop);
    [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr h);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int n);
    [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h);

    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct CURSORINFO { public int cbSize; public int flags; public IntPtr hCursor; public POINT pt; }
    [StructLayout(LayoutKind.Sequential)] public struct ICONINFO { public bool fIcon; public int xHotspot; public int yHotspot; public IntPtr hbmMask; public IntPtr hbmColor; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public int dwFlags; }

    [DllImport("user32.dll")] public static extern bool GetCursorInfo(ref CURSORINFO ci);
    [DllImport("user32.dll")] public static extern bool GetIconInfo(IntPtr hIcon, out ICONINFO ii);
    [DllImport("user32.dll")] public static extern bool DrawIconEx(IntPtr hdc, int x, int y, IntPtr hIcon, int cx, int cy, int step, IntPtr brush, int flags);

    public delegate bool MonitorEnumProc(IntPtr hMon, IntPtr hdc, ref RECT rc, IntPtr data);
    [DllImport("user32.dll")] public static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, MonitorEnumProc proc, IntPtr data);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern bool GetMonitorInfo(IntPtr hMon, ref MONITORINFO mi);

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Explicit)]
    public struct INPUTUNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT { public uint type; public INPUTUNION U; }
    [DllImport("user32.dll", SetLastError = true)] public static extern uint SendInput(uint n, INPUT[] inputs, int size);
    [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint mapType);

    public const int SRCCOPY = 0x00CC0020, CAPTUREBLT = 0x40000000;

    // Blendet das eigene Konsolenfenster aus (auch bei "Mit PowerShell ausfuehren").
    public static void HideConsole()
    {
        try { IntPtr h = GetConsoleWindow(); if (h != IntPtr.Zero) ShowWindow(h, 0); } catch { }
    }

    // Aufnahme- und Eingabe-Thread arbeiten in echten Bildpunkten (die Oberflaeche selbst bleibt unveraendert).
    public static void SetThreadDpiAware()
    {
        try { SetThreadDpiAwarenessContext(new IntPtr(-4)); } catch { }           // ab Windows 10 1703: je Monitor (aeltere Systeme: Aufruf fehlt, dann unveraendert)
    }

    // Alle Bildschirme (Hauptbildschirm zuerst), in echten Bildpunkten des aufrufenden Threads.
    public static Rectangle[] Monitors()
    {
        List<Rectangle> all = new List<Rectangle>();
        List<Rectangle> primary = new List<Rectangle>();
        MonitorEnumProc cb = delegate (IntPtr hMon, IntPtr hdc, ref RECT rc, IntPtr data)
        {
            MONITORINFO mi = new MONITORINFO();
            mi.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
            if (GetMonitorInfo(hMon, ref mi))
            {
                Rectangle r = Rectangle.FromLTRB(mi.rcMonitor.Left, mi.rcMonitor.Top, mi.rcMonitor.Right, mi.rcMonitor.Bottom);
                if ((mi.dwFlags & 1) != 0) primary.Add(r); else all.Add(r);
            }
            return true;
        };
        try { EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, cb, IntPtr.Zero); } catch { }
        GC.KeepAlive(cb);
        primary.AddRange(all);
        if (primary.Count == 0) primary.Add(new Rectangle(0, 0, Math.Max(640, GetSystemMetrics(0)), Math.Max(480, GetSystemMetrics(1))));
        return primary.ToArray();
    }
}

// ----------------------------------------------------------------------------
// Bildschirm des Kunden: aufnehmen, verkleinern, mit dem letzten gesendeten Stand
// vergleichen und nur geaenderte Bereiche als JPEG senden. Gesendet wird nur, wenn
// der Strom nicht staut - so bleibt die Verzoegerung auch bei langsamer Leitung klein.
// ----------------------------------------------------------------------------
public sealed class PesScreen
{
    private const int Tile = 64;
    private readonly PesSession session;
    private Thread thread;
    private volatile bool running;
    private volatile bool forceFull;
    public volatile string LastError = "";
    public volatile int Fps, Kbps;
    public volatile int MonX, MonY, MonW, MonH, VirtX, VirtY, VirtW, VirtH;
    public volatile int Monitors = 1;

    public PesScreen(PesSession s) { session = s; }
    public bool IsRunning { get { return running; } }
    public void ForceFull() { forceFull = true; }

    public void Start()
    {
        if (running) return;
        running = true; forceFull = true; LastError = "";
        thread = new Thread(Loop); thread.IsBackground = true; thread.Name = "PES-SCREEN"; thread.Start();
    }

    public void Stop()
    {
        running = false;
        Thread t = thread;
        if (t != null && t != Thread.CurrentThread) t.Join(1500);
        thread = null; Fps = 0; Kbps = 0;
    }

    private static ImageCodecInfo JpegCodec()
    {
        foreach (ImageCodecInfo c in ImageCodecInfo.GetImageEncoders()) if (c.FormatID == ImageFormat.Jpeg.Guid) return c;
        return null;
    }

    private void Loop()
    {
        PesNative.SetThreadDpiAware();
        Bitmap full = null, scaled = null;
        byte[] cur = null, prev = null;
        int sw = 0, sh = 0, quality = 0, mon = -1, mw = 0, mh = 0;
        ImageCodecInfo codec = JpegCodec();
        EncoderParameters ep = new EncoderParameters(1);
        MemoryStream ms = new MemoryStream(1 << 16);
        Stopwatch clock = Stopwatch.StartNew();
        long sentTotal = 0, lastDelivered = 0, lastRateMs = 0, statMs = 0, statBytes = 0;
        int statFrames = 0;
        double rate = 400000;                                           // geschaetzte Zustellrate in Byte/s
        try
        {
            while (running && session.ShareActive)
            {
                long t0 = clock.ElapsedMilliseconds;
                try
                {
                    int wantQ = session.WantQuality; if (wantQ < 1) wantQ = 1; if (wantQ > 3) wantQ = 3;
                    Rectangle[] mons = PesNative.Monitors();
                    int wantMon = session.WantMonitor; if (wantMon < 0 || wantMon >= mons.Length) wantMon = 0;
                    Rectangle mr = mons[wantMon];
                    Monitors = mons.Length;
                    if (wantQ != quality || wantMon != mon || mr.Width != mw || mr.Height != mh || full == null)
                    {
                        quality = wantQ; mon = wantMon; mw = mr.Width; mh = mr.Height;
                        int maxW = quality == 1 ? 1024 : (quality == 2 ? 1366 : 1920);
                        double sc = Math.Min(1.0, (double)maxW / mw);
                        sw = Math.Max(64, ((int)(mw * sc)) & ~1); sh = Math.Max(64, ((int)(mh * sc)) & ~1);
                        if (scaled != null && scaled != full) scaled.Dispose();
                        if (full != null) full.Dispose();
                        full = new Bitmap(mw, mh, PixelFormat.Format32bppRgb);
                        scaled = (sw == mw && sh == mh) ? full : new Bitmap(sw, sh, PixelFormat.Format32bppRgb);
                        cur = new byte[sw * 4 * sh]; prev = new byte[sw * 4 * sh];
                        ep.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, (long)(quality == 1 ? 38 : (quality == 2 ? 52 : 70)));
                        forceFull = true;
                        session.SetShare(true, session.ControlActive, sw, sh, mon, mons.Length);
                    }
                    MonX = mr.X; MonY = mr.Y; MonW = mr.Width; MonH = mr.Height;
                    VirtX = PesNative.GetSystemMetrics(76); VirtY = PesNative.GetSystemMetrics(77);
                    VirtW = PesNative.GetSystemMetrics(78); VirtH = PesNative.GetSystemMetrics(79);

                    // Zustellrate schaetzen und nur senden, wenn hoechstens ca. 250 ms Daten anstehen
                    long backlog = session.ScreenBacklog;
                    long nowMs = clock.ElapsedMilliseconds;
                    if (nowMs - lastRateMs >= 500)
                    {
                        long delivered = sentTotal - backlog;
                        double r = (delivered - lastDelivered) * 1000.0 / Math.Max(1, nowMs - lastRateMs);
                        if (backlog > 20000 || r > rate) rate = rate * 0.6 + r * 0.4;
                        if (rate < 20000) rate = 20000;
                        lastDelivered = delivered; lastRateMs = nowMs;
                    }
                    long limit = Math.Max(30000, (long)(rate * 0.25));
                    if (backlog > limit) { Thread.Sleep(15); continue; }

                    Capture(full, mr);
                    if (scaled != full)
                    {
                        using (Graphics g = Graphics.FromImage(scaled))
                        {
                            g.InterpolationMode = InterpolationMode.Bilinear;
                            g.PixelOffsetMode = PixelOffsetMode.Half;
                            g.CompositingMode = CompositingMode.SourceCopy;
                            g.DrawImage(full, new Rectangle(0, 0, sw, sh), 0, 0, mw, mh, GraphicsUnit.Pixel);
                        }
                    }
                    BitmapData bd = scaled.LockBits(new Rectangle(0, 0, sw, sh), ImageLockMode.ReadOnly, PixelFormat.Format32bppRgb);
                    try
                    {
                        if (bd.Stride == sw * 4) Marshal.Copy(bd.Scan0, cur, 0, cur.Length);
                        else for (int y = 0; y < sh; y++) Marshal.Copy(new IntPtr(bd.Scan0.ToInt64() + (long)y * bd.Stride), cur, y * sw * 4, sw * 4);
                    }
                    finally { scaled.UnlockBits(bd); }

                    bool fullPass = forceFull; forceFull = false;
                    List<Rectangle> rects = Diff(cur, prev, sw, sh, fullPass);
                    for (int i = 0; i < rects.Count && running && session.ShareActive; i++)
                    {
                        Rectangle rc = rects[i];
                        ms.SetLength(0);
                        using (Bitmap part = scaled.Clone(rc, PixelFormat.Format24bppRgb)) part.Save(ms, codec, ep);
                        byte[] jpg = ms.ToArray();
                        if (!session.SendScreenRect(sw, sh, rc.X, rc.Y, rc.Width, rc.Height, i == rects.Count - 1 ? 1 : 0, jpg)) break;
                        sentTotal += jpg.Length; statBytes += jpg.Length;
                        for (int y = rc.Y; y < rc.Bottom; y++) Buffer.BlockCopy(cur, (y * sw + rc.X) * 4, prev, (y * sw + rc.X) * 4, rc.Width * 4);
                        // Staut der Strom, kommt der Rest im naechsten Durchgang. Bei einem Komplettbild werden die
                        // noch nicht gesendeten Bereiche als "geaendert" markiert, damit sie sicher nachkommen.
                        if (session.ScreenBacklog > limit * 4)
                        {
                            if (fullPass)
                            {
                                for (int j = i + 1; j < rects.Count; j++)
                                {
                                    Rectangle rr = rects[j];
                                    for (int y = rr.Y; y < rr.Bottom; y++)
                                    {
                                        int o = (y * sw + rr.X) * 4;
                                        for (int n = 0; n < rr.Width * 4; n += 4) prev[o + n] = (byte)~cur[o + n];
                                    }
                                }
                            }
                            break;
                        }
                    }
                    if (rects.Count > 0) statFrames++;
                    LastError = "";
                }
                catch (Exception ex)
                {
                    // z. B. Sperrbildschirm oder UAC-Abfrage (sicherer Desktop): kein Bild, spaeter erneut versuchen
                    LastError = ex.Message;
                    forceFull = true;
                    Thread.Sleep(400);
                }
                long now = clock.ElapsedMilliseconds;
                if (now - statMs >= 1000)
                {
                    Fps = (int)(statFrames * 1000 / Math.Max(1, now - statMs));
                    Kbps = (int)(statBytes * 8 / Math.Max(1, now - statMs));
                    statMs = now; statFrames = 0; statBytes = 0;
                }
                int interval = quality == 1 ? 140 : (quality == 2 ? 100 : 80);
                int wait = interval - (int)(clock.ElapsedMilliseconds - t0);
                if (wait > 0) Thread.Sleep(wait); else Thread.Sleep(1);
            }
        }
        finally
        {
            try { if (scaled != null && scaled != full) scaled.Dispose(); } catch { }
            try { if (full != null) full.Dispose(); } catch { }
            running = false; Fps = 0; Kbps = 0;
        }
    }

    private static void Capture(Bitmap full, Rectangle mr)
    {
        IntPtr screen = PesNative.GetDC(IntPtr.Zero);
        try
        {
            using (Graphics g = Graphics.FromImage(full))
            {
                IntPtr hdc = g.GetHdc();
                try
                {
                    if (!PesNative.BitBlt(hdc, 0, 0, mr.Width, mr.Height, screen, mr.X, mr.Y, PesNative.SRCCOPY | PesNative.CAPTUREBLT))
                        throw new InvalidOperationException("Bildschirm konnte nicht gelesen werden (gesperrt oder UAC-Abfrage?)");
                    // Mauszeiger einzeichnen (BitBlt liefert ihn nicht mit)
                    PesNative.CURSORINFO ci = new PesNative.CURSORINFO();
                    ci.cbSize = Marshal.SizeOf(typeof(PesNative.CURSORINFO));
                    if (PesNative.GetCursorInfo(ref ci) && ci.flags == 1 && ci.hCursor != IntPtr.Zero)
                    {
                        int hx = 0, hy = 0;
                        PesNative.ICONINFO ii;
                        if (PesNative.GetIconInfo(ci.hCursor, out ii))
                        {
                            hx = ii.xHotspot; hy = ii.yHotspot;
                            if (ii.hbmMask != IntPtr.Zero) PesNative.DeleteObject(ii.hbmMask);
                            if (ii.hbmColor != IntPtr.Zero) PesNative.DeleteObject(ii.hbmColor);
                        }
                        PesNative.DrawIconEx(hdc, ci.pt.X - mr.X - hx, ci.pt.Y - mr.Y - hy, ci.hCursor, 0, 0, 0, IntPtr.Zero, 3);
                    }
                }
                finally { g.ReleaseHdc(hdc); }
            }
        }
        finally { PesNative.ReleaseDC(IntPtr.Zero, screen); }
    }

    // Geaenderte Kacheln finden und zu Rechtecken zusammenfassen (waagerecht, dann gleiche Spalten senkrecht bis 256 Bildpunkte).
    private static List<Rectangle> Diff(byte[] cur, byte[] prev, int sw, int sh, bool all)
    {
        List<Rectangle> res = new List<Rectangle>();
        Dictionary<long, int> open = new Dictionary<long, int>();
        Dictionary<long, int> next = new Dictionary<long, int>();
        int tw = (sw + Tile - 1) / Tile, th = (sh + Tile - 1) / Tile;
        for (int ty = 0; ty < th; ty++)
        {
            int y0 = ty * Tile, y1 = Math.Min(sh, y0 + Tile);
            int runStart = -1;
            next.Clear();
            for (int tx = 0; tx <= tw; tx++)
            {
                bool ch = false;
                if (tx < tw)
                {
                    if (all) ch = true;
                    else
                    {
                        int x0 = tx * Tile * 4, x1 = Math.Min(sw, (tx + 1) * Tile) * 4;
                        for (int y = y0; y < y1 && !ch; y++)
                        {
                            int o = y * sw * 4;
                            for (int i = o + x0; i < o + x1; i++) if (cur[i] != prev[i]) { ch = true; break; }
                        }
                    }
                }
                if (ch) { if (runStart < 0) runStart = tx; continue; }
                if (runStart < 0) continue;
                int rx = runStart * Tile, rw = Math.Min(sw, tx * Tile) - rx;
                runStart = -1;
                long key = (long)(((ulong)(uint)rx << 20) | (ulong)(uint)rw);
                int idx;
                if (open.TryGetValue(key, out idx) && res[idx].Height + (y1 - y0) <= 256)
                {
                    Rectangle o2 = res[idx];
                    res[idx] = new Rectangle(o2.X, o2.Y, o2.Width, o2.Height + (y1 - y0));
                    next[key] = idx;
                }
                else { res.Add(new Rectangle(rx, y0, rw, y1 - y0)); next[key] = res.Count - 1; }
            }
            Dictionary<long, int> tmp = open; open = next; next = tmp;
        }
        return res;
    }
}

// ----------------------------------------------------------------------------
// Eingaben des Helfers ausfuehren. Die Sitzung reicht sie nur durch, wenn der Kunde
// die Steuerung erlaubt hat; hier wird zusaetzlich jede Laenge und jeder Wert geprueft.
// ----------------------------------------------------------------------------
public sealed class PesInput
{
    private readonly PesScreen screen;
    private readonly BlockingCollection<byte[]> queue = new BlockingCollection<byte[]>(new ConcurrentQueue<byte[]>(), 4000);
    private Thread thread;
    private volatile bool running;
    public volatile bool Enabled;
    public long Count;
    private readonly HashSet<int> downKeys = new HashSet<int>();
    private int downButtons;

    public PesInput(PesScreen s) { screen = s; }

    public void Start()
    {
        if (running) return;
        running = true;
        thread = new Thread(Loop); thread.IsBackground = true; thread.Name = "PES-INPUT"; thread.Start();
    }

    public void Stop()
    {
        running = false; Enabled = false;
        try { queue.Add(new byte[0]); } catch { }
        Thread t = thread;
        if (t != null) t.Join(1000);
        thread = null;
    }

    // Kommt aus dem Netz-Thread: nur einreihen.
    public void Post(byte[] body)
    {
        if (!Enabled || body == null || body.Length < 1 || body.Length > 1100) return;
        queue.TryAdd(body);
    }

    private void Loop()
    {
        PesNative.SetThreadDpiAware();
        while (running)
        {
            byte[] b;
            try { if (!queue.TryTake(out b, 200)) { if (!Enabled) ReleaseAll(); continue; } } catch { break; }
            if (!running) break;
            if (!Enabled || b.Length == 0) { ReleaseAll(); continue; }
            try { Apply(b); Interlocked.Increment(ref Count); } catch { }
        }
        ReleaseAll();
    }

    // Wird die Steuerung beendet, bleiben keine Tasten oder Maustasten "haengen".
    private void ReleaseAll()
    {
        if (downKeys.Count == 0 && downButtons == 0) return;
        try
        {
            foreach (int vk in new List<int>(downKeys)) Key(vk, false, false);
            downKeys.Clear();
            for (int i = 0; i < 3; i++) if ((downButtons & (1 << i)) != 0) Mouse(i == 0 ? 0x0004u : (i == 1 ? 0x0010u : 0x0040u), 0, false, 0, 0);
            downButtons = 0;
        }
        catch { }
    }

    private void Apply(byte[] b)
    {
        switch (b[0])
        {
            case 1:
                if (b.Length >= 5) Mouse(0, 0, true, PesBytes.ReadU16(b, 1), PesBytes.ReadU16(b, 3));
                break;
            case 2:
                if (b.Length >= 7 && b[1] <= 2)
                {
                    bool down = b[2] != 0;
                    uint f = b[1] == 0 ? (down ? 0x0002u : 0x0004u) : (b[1] == 1 ? (down ? 0x0008u : 0x0010u) : (down ? 0x0020u : 0x0040u));
                    Mouse(f, 0, true, PesBytes.ReadU16(b, 3), PesBytes.ReadU16(b, 5));
                    if (down) downButtons |= 1 << b[1]; else downButtons &= ~(1 << b[1]);
                }
                break;
            case 3:
                if (b.Length >= 7)
                {
                    int delta = (short)PesBytes.ReadU16(b, 1);
                    if (delta > 1200) delta = 1200; if (delta < -1200) delta = -1200;
                    Mouse(0x0800, (uint)delta, true, PesBytes.ReadU16(b, 3), PesBytes.ReadU16(b, 5));
                }
                break;
            case 4:
                if (b.Length >= 5)
                {
                    int vk = PesBytes.ReadU16(b, 1);
                    if (vk < 1 || vk > 254) break;
                    bool down = b[3] != 0;
                    Key(vk, down, b[4] != 0);
                    if (down) downKeys.Add(vk); else downKeys.Remove(vk);
                }
                break;
            case 5:
                {
                    string t = Encoding.UTF8.GetString(b, 1, b.Length - 1);
                    if (t.Length > 256) t = t.Substring(0, 256);
                    foreach (char c in t)
                    {
                        if (c == '\n') { Key(0x0D, true, false); Key(0x0D, false, false); continue; }
                        if (c == '\r') continue;
                        if (c == '\t') { Key(0x09, true, false); Key(0x09, false, false); continue; }
                        if (c < 32) continue;
                        Unicode(c, true); Unicode(c, false);
                    }
                    break;
                }
        }
    }

    // x/y: 0..65535 bezogen auf den freigegebenen Bildschirm -> Koordinaten des gesamten Desktops
    private void Mouse(uint flags, uint data, bool move, int x, int y)
    {
        PesNative.INPUT[] inp = new PesNative.INPUT[1];
        inp[0].type = 0;
        uint f = flags;
        if (move)
        {
            int mw = screen.MonW, mh = screen.MonH, vw = screen.VirtW, vh = screen.VirtH;
            if (mw <= 0 || mh <= 0 || vw <= 1 || vh <= 1) return;
            double px = screen.MonX + x / 65535.0 * (mw - 1);
            double py = screen.MonY + y / 65535.0 * (mh - 1);
            inp[0].U.mi.dx = (int)Math.Round((px - screen.VirtX) * 65535.0 / (vw - 1));
            inp[0].U.mi.dy = (int)Math.Round((py - screen.VirtY) * 65535.0 / (vh - 1));
            f |= 0x0001 | 0x8000 | 0x4000;                               // MOVE | ABSOLUTE | VIRTUALDESK
        }
        inp[0].U.mi.mouseData = data;
        inp[0].U.mi.dwFlags = f;
        PesNative.SendInput(1, inp, Marshal.SizeOf(typeof(PesNative.INPUT)));
    }

    private static void Key(int vk, bool down, bool extended)
    {
        PesNative.INPUT[] inp = new PesNative.INPUT[1];
        inp[0].type = 1;
        inp[0].U.ki.wVk = (ushort)vk;
        inp[0].U.ki.wScan = (ushort)PesNative.MapVirtualKey((uint)vk, 0);
        inp[0].U.ki.dwFlags = (down ? 0u : 0x0002u) | (extended ? 0x0001u : 0u);
        PesNative.SendInput(1, inp, Marshal.SizeOf(typeof(PesNative.INPUT)));
    }

    private static void Unicode(char c, bool down)
    {
        PesNative.INPUT[] inp = new PesNative.INPUT[1];
        inp[0].type = 1;
        inp[0].U.ki.wVk = 0;
        inp[0].U.ki.wScan = c;
        inp[0].U.ki.dwFlags = 0x0004u | (down ? 0u : 0x0002u);          // KEYEVENTF_UNICODE
        PesNative.SendInput(1, inp, Marshal.SizeOf(typeof(PesNative.INPUT)));
    }
}

// ----------------------------------------------------------------------------
// Ton ueber winmm (waveIn/waveOut), 16 kHz mono 16 Bit, 20-ms-Bloecke.
// Uebernommen aus dem Sprachchat des Project Earth LAN Managers.
// ----------------------------------------------------------------------------
public static class PesWinmm
{
    public const int CALLBACK_EVENT = 0x00050000;
    public const uint WHDR_DONE = 0x00000001;

    [StructLayout(LayoutKind.Sequential)]
    public struct WAVEFORMATEX
    {
        public ushort wFormatTag; public ushort nChannels; public uint nSamplesPerSec; public uint nAvgBytesPerSec;
        public ushort nBlockAlign; public ushort wBitsPerSample; public ushort cbSize;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct WAVEHDR
    {
        public IntPtr lpData; public uint dwBufferLength; public uint dwBytesRecorded; public IntPtr dwUser;
        public uint dwFlags; public uint dwLoops; public IntPtr lpNext; public IntPtr reserved;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct WAVEINCAPS
    {
        public ushort wMid; public ushort wPid; public uint vDriverVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string szPname;
        public uint dwFormats; public ushort wChannels; public ushort wReserved1;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct WAVEOUTCAPS
    {
        public ushort wMid; public ushort wPid; public uint vDriverVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string szPname;
        public uint dwFormats; public ushort wChannels; public ushort wReserved1; public uint dwSupport;
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

    // Namen ohne den Eintrag "Standardgeraet" (den ergaenzt die Oberflaeche); Index i gehoert zu Geraet i.
    public static string[] InputDeviceNames()
    {
        List<string> l = new List<string>();
        int n = waveInGetNumDevs();
        for (int i = 0; i < n; i++)
        {
            WAVEINCAPS c = new WAVEINCAPS();
            if (waveInGetDevCaps((IntPtr)i, ref c, Marshal.SizeOf(typeof(WAVEINCAPS))) == 0) l.Add(c.szPname); else l.Add("Geraet " + i);
        }
        return l.ToArray();
    }

    public static string[] OutputDeviceNames()
    {
        List<string> l = new List<string>();
        int n = waveOutGetNumDevs();
        for (int i = 0; i < n; i++)
        {
            WAVEOUTCAPS c = new WAVEOUTCAPS();
            if (waveOutGetDevCaps((IntPtr)i, ref c, Marshal.SizeOf(typeof(WAVEOUTCAPS))) == 0) l.Add(c.szPname); else l.Add("Geraet " + i);
        }
        return l.ToArray();
    }

    public static WAVEFORMATEX Format16kMono()
    {
        WAVEFORMATEX fmt = new WAVEFORMATEX();
        fmt.wFormatTag = 1; fmt.nChannels = 1; fmt.nSamplesPerSec = 16000; fmt.wBitsPerSample = 16;
        fmt.nBlockAlign = 2; fmt.nAvgBytesPerSec = 32000; fmt.cbSize = 0;
        return fmt;
    }
}

public sealed class PesAudioIn
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

    // deviceId -1 = Standardgeraet von Windows. Liefert null bei Erfolg.
    public string Start(int deviceId)
    {
        Stop();
        PesWinmm.WAVEFORMATEX fmt = PesWinmm.Format16kMono();
        IntPtr h;
        int r = PesWinmm.waveInOpen(out h, deviceId, ref fmt, evt.SafeWaitHandle.DangerousGetHandle(), IntPtr.Zero, PesWinmm.CALLBACK_EVENT);
        if (r != 0) return "Mikrofon konnte nicht geoeffnet werden (Fehlercode " + r + ")";
        hwi = h;
        int hdrSize = Marshal.SizeOf(typeof(PesWinmm.WAVEHDR));
        hdrs = new IntPtr[BufferCount];
        bufs = new IntPtr[BufferCount];
        for (int i = 0; i < BufferCount; i++)
        {
            bufs[i] = Marshal.AllocHGlobal(FrameSamples * 2);
            PesWinmm.WAVEHDR hd = new PesWinmm.WAVEHDR();
            hd.lpData = bufs[i];
            hd.dwBufferLength = (uint)(FrameSamples * 2);
            hdrs[i] = Marshal.AllocHGlobal(hdrSize);
            Marshal.StructureToPtr(hd, hdrs[i], false);
            PesWinmm.waveInPrepareHeader(hwi, hdrs[i], hdrSize);
            PesWinmm.waveInAddBuffer(hwi, hdrs[i], hdrSize);
        }
        running = true;
        PesWinmm.waveInStart(hwi);
        thread = new Thread(Loop); thread.IsBackground = true; thread.Priority = ThreadPriority.AboveNormal; thread.Name = "PES-MIC"; thread.Start();
        return null;
    }

    private void Loop()
    {
        int hdrSize = Marshal.SizeOf(typeof(PesWinmm.WAVEHDR));
        int flagsOffset = (int)Marshal.OffsetOf(typeof(PesWinmm.WAVEHDR), "dwFlags");
        int recOffset = (int)Marshal.OffsetOf(typeof(PesWinmm.WAVEHDR), "dwBytesRecorded");
        while (running)
        {
            evt.WaitOne(100);
            if (!running) break;
            for (int i = 0; i < hdrs.Length; i++)
            {
                uint flags = (uint)Marshal.ReadInt32(hdrs[i], flagsOffset);
                if ((flags & PesWinmm.WHDR_DONE) != 0)
                {
                    int rec = Marshal.ReadInt32(hdrs[i], recOffset);
                    if (rec > 1 && OnFrame != null)
                    {
                        short[] frame = new short[rec / 2];
                        Marshal.Copy(bufs[i], frame, 0, rec / 2);
                        try { OnFrame(frame); } catch (Exception) { }
                    }
                    if (running) PesWinmm.waveInAddBuffer(hwi, hdrs[i], hdrSize);
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
            int hdrSize = Marshal.SizeOf(typeof(PesWinmm.WAVEHDR));
            PesWinmm.waveInReset(hwi);
            if (hdrs != null)
            {
                for (int i = 0; i < hdrs.Length; i++)
                {
                    PesWinmm.waveInUnprepareHeader(hwi, hdrs[i], hdrSize);
                    Marshal.FreeHGlobal(hdrs[i]);
                    Marshal.FreeHGlobal(bufs[i]);
                }
            }
            PesWinmm.waveInClose(hwi);
            hwi = IntPtr.Zero; hdrs = null; bufs = null;
        }
    }
}

public sealed class PesAudioOut
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
        PesWinmm.WAVEFORMATEX fmt = PesWinmm.Format16kMono();
        IntPtr h;
        int r = PesWinmm.waveOutOpen(out h, deviceId, ref fmt, evt.SafeWaitHandle.DangerousGetHandle(), IntPtr.Zero, PesWinmm.CALLBACK_EVENT);
        if (r != 0) return "Lautsprecher konnte nicht geoeffnet werden (Fehlercode " + r + ")";
        hwo = h;
        int hdrSize = Marshal.SizeOf(typeof(PesWinmm.WAVEHDR));
        hdrs = new IntPtr[BufferCount];
        bufs = new IntPtr[BufferCount];
        for (int i = 0; i < BufferCount; i++)
        {
            bufs[i] = Marshal.AllocHGlobal(FrameSamples * 2);
            Marshal.Copy(new short[FrameSamples], 0, bufs[i], FrameSamples);
            PesWinmm.WAVEHDR hd = new PesWinmm.WAVEHDR();
            hd.lpData = bufs[i];
            hd.dwBufferLength = (uint)(FrameSamples * 2);
            hdrs[i] = Marshal.AllocHGlobal(hdrSize);
            Marshal.StructureToPtr(hd, hdrs[i], false);
            PesWinmm.waveOutPrepareHeader(hwo, hdrs[i], hdrSize);
            PesWinmm.waveOutWrite(hwo, hdrs[i], hdrSize);
        }
        running = true;
        thread = new Thread(Loop); thread.IsBackground = true; thread.Priority = ThreadPriority.AboveNormal; thread.Name = "PES-SPK"; thread.Start();
        return null;
    }

    private void Loop()
    {
        int hdrSize = Marshal.SizeOf(typeof(PesWinmm.WAVEHDR));
        int flagsOffset = (int)Marshal.OffsetOf(typeof(PesWinmm.WAVEHDR), "dwFlags");
        while (running)
        {
            evt.WaitOne(100);
            if (!running) break;
            for (int i = 0; i < hdrs.Length; i++)
            {
                uint flags = (uint)Marshal.ReadInt32(hdrs[i], flagsOffset);
                if ((flags & PesWinmm.WHDR_DONE) != 0)
                {
                    short[] f = null;
                    try { if (PullFrame != null) f = PullFrame(); } catch (Exception) { }
                    if (f == null || f.Length < FrameSamples) f = new short[FrameSamples];
                    Marshal.Copy(f, 0, bufs[i], FrameSamples);
                    if (running) PesWinmm.waveOutWrite(hwo, hdrs[i], hdrSize);
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
            int hdrSize = Marshal.SizeOf(typeof(PesWinmm.WAVEHDR));
            PesWinmm.waveOutReset(hwo);
            if (hdrs != null)
            {
                for (int i = 0; i < hdrs.Length; i++)
                {
                    PesWinmm.waveOutUnprepareHeader(hwo, hdrs[i], hdrSize);
                    Marshal.FreeHGlobal(hdrs[i]);
                    Marshal.FreeHGlobal(bufs[i]);
                }
            }
            PesWinmm.waveOutClose(hwo);
            hwo = IntPtr.Zero; hdrs = null; bufs = null;
        }
    }
}

// ----------------------------------------------------------------------------
// Webcam ueber Media Foundation (Source Reader liefert RGB32). Nur die wirklich
// benutzten Methoden sind ausgeschrieben; die uebrigen stehen als Platzhalter in
// der richtigen Reihenfolge, damit die COM-Tabellen stimmen.
// ----------------------------------------------------------------------------
[ComImport, Guid("2cd2d921-c447-44a7-a13c-4adabfc247e3"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IPesMFAttributes
{
    void GetItem(); void GetItemType(); void CompareItem(); void Compare();
    [PreserveSig] int GetUINT32([In] ref Guid key, out int value);
    [PreserveSig] int GetUINT64([In] ref Guid key, out long value);
    void GetDouble();
    [PreserveSig] int GetGUID([In] ref Guid key, out Guid value);
    void GetStringLength(); void GetString();
    [PreserveSig] int GetAllocatedString([In] ref Guid key, [MarshalAs(UnmanagedType.LPWStr)] out string value, out int length);
    void GetBlobSize(); void GetBlob(); void GetAllocatedBlob(); void GetUnknown(); void SetItem(); void DeleteItem(); void DeleteAllItems();
    [PreserveSig] int SetUINT32([In] ref Guid key, int value);
    [PreserveSig] int SetUINT64([In] ref Guid key, long value);
    void SetDouble();
    [PreserveSig] int SetGUID([In] ref Guid key, [In] ref Guid value);
    void SetString(); void SetBlob(); void SetUnknown(); void LockStore(); void UnlockStore(); void GetCount(); void GetItemByIndex(); void CopyAllItems();
}

[ComImport, Guid("44ae0fa8-ea31-4109-8d2e-4cae4997c555"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IPesMFMediaType
{
    void GetItem(); void GetItemType(); void CompareItem(); void Compare();
    [PreserveSig] int GetUINT32([In] ref Guid key, out int value);
    [PreserveSig] int GetUINT64([In] ref Guid key, out long value);
    void GetDouble();
    [PreserveSig] int GetGUID([In] ref Guid key, out Guid value);
    void GetStringLength(); void GetString(); void GetAllocatedString();
    void GetBlobSize(); void GetBlob(); void GetAllocatedBlob(); void GetUnknown(); void SetItem(); void DeleteItem(); void DeleteAllItems();
    [PreserveSig] int SetUINT32([In] ref Guid key, int value);
    [PreserveSig] int SetUINT64([In] ref Guid key, long value);
    void SetDouble();
    [PreserveSig] int SetGUID([In] ref Guid key, [In] ref Guid value);
    void SetString(); void SetBlob(); void SetUnknown(); void LockStore(); void UnlockStore(); void GetCount(); void GetItemByIndex(); void CopyAllItems();
    void GetMajorType(); void IsCompressedFormat(); void IsEqual(); void GetRepresentation(); void FreeRepresentation();
}

[ComImport, Guid("7FEE9E9A-4A89-47a6-899C-B6A53A70FB67"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IPesMFActivate
{
    void GetItem(); void GetItemType(); void CompareItem(); void Compare();
    void GetUINT32(); void GetUINT64(); void GetDouble(); void GetGUID(); void GetStringLength(); void GetString();
    [PreserveSig] int GetAllocatedString([In] ref Guid key, [MarshalAs(UnmanagedType.LPWStr)] out string value, out int length);
    void GetBlobSize(); void GetBlob(); void GetAllocatedBlob(); void GetUnknown(); void SetItem(); void DeleteItem(); void DeleteAllItems();
    void SetUINT32(); void SetUINT64(); void SetDouble(); void SetGUID();
    void SetString(); void SetBlob(); void SetUnknown(); void LockStore(); void UnlockStore(); void GetCount(); void GetItemByIndex(); void CopyAllItems();
    [PreserveSig] int ActivateObject([In] ref Guid riid, [MarshalAs(UnmanagedType.IUnknown)] out object obj);
    [PreserveSig] int ShutdownObject();
    void DetachObject();
}

[ComImport, Guid("045FA593-8799-42b8-BC8D-8968C6453507"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IPesMFMediaBuffer
{
    [PreserveSig] int Lock(out IntPtr buffer, out int maxLength, out int currentLength);
    [PreserveSig] int Unlock();
    void GetCurrentLength(); void SetCurrentLength(); void GetMaxLength();
}

[ComImport, Guid("c40a00f2-b93a-4d80-ae8c-5a1c634f58e4"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IPesMFSample
{
    void GetItem(); void GetItemType(); void CompareItem(); void Compare();
    void GetUINT32(); void GetUINT64(); void GetDouble(); void GetGUID(); void GetStringLength(); void GetString(); void GetAllocatedString();
    void GetBlobSize(); void GetBlob(); void GetAllocatedBlob(); void GetUnknown(); void SetItem(); void DeleteItem(); void DeleteAllItems();
    void SetUINT32(); void SetUINT64(); void SetDouble(); void SetGUID();
    void SetString(); void SetBlob(); void SetUnknown(); void LockStore(); void UnlockStore(); void GetCount(); void GetItemByIndex(); void CopyAllItems();
    void GetSampleFlags(); void SetSampleFlags(); void GetSampleTime(); void SetSampleTime(); void GetSampleDuration(); void SetSampleDuration();
    void GetBufferCount(); void GetBufferByIndex();
    [PreserveSig] int ConvertToContiguousBuffer(out IPesMFMediaBuffer buffer);
    void AddBuffer(); void RemoveBufferByIndex(); void RemoveAllBuffers(); void GetTotalLength(); void CopyToBuffer();
}

[ComImport, Guid("70ae66f2-c809-4e4f-8915-bdcb406b7993"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IPesMFSourceReader
{
    void GetStreamSelection();
    [PreserveSig] int SetStreamSelection(int streamIndex, [MarshalAs(UnmanagedType.Bool)] bool selected);
    [PreserveSig] int GetNativeMediaType(int streamIndex, int mediaTypeIndex, out IPesMFMediaType type);
    [PreserveSig] int GetCurrentMediaType(int streamIndex, out IPesMFMediaType type);
    [PreserveSig] int SetCurrentMediaType(int streamIndex, IntPtr reserved, IPesMFMediaType type);
    void SetCurrentPosition();
    [PreserveSig] int ReadSample(int streamIndex, int controlFlags, out int actualStreamIndex, out int streamFlags, out long timestamp, out IPesMFSample sample);
    void Flush(); void GetServiceForStream(); void GetPresentationAttribute();
}

public sealed class PesCamera
{
    [DllImport("mfplat.dll")] private static extern int MFStartup(int version, int flags);
    [DllImport("mfplat.dll")] private static extern int MFShutdown();
    [DllImport("mfplat.dll")] private static extern int MFCreateAttributes(out IPesMFAttributes attrs, int initialSize);
    [DllImport("mfplat.dll")] private static extern int MFCreateMediaType(out IPesMFMediaType type);
    [DllImport("mf.dll")] private static extern int MFEnumDeviceSources(IPesMFAttributes attrs, out IntPtr activateArray, out int count);
    [DllImport("mfreadwrite.dll")] private static extern int MFCreateSourceReaderFromMediaSource([MarshalAs(UnmanagedType.IUnknown)] object source, IPesMFAttributes attrs, out IPesMFSourceReader reader);

    private static readonly Guid SourceType = new Guid("c60ac5fe-252a-478f-a0ef-bc8fa5f7cad3");
    private static readonly Guid SourceTypeVidcap = new Guid("8ac3587a-4ae7-42d8-99e0-0a6013eef90f");
    private static readonly Guid FriendlyName = new Guid("60d0e559-52f8-4fa2-bbce-acdb34a8ec01");
    private static readonly Guid MajorType = new Guid("48eba18e-f8c9-4687-bf11-0a74c9f96a8f");
    private static readonly Guid SubType = new Guid("f7e34c9a-42e8-4714-b74b-cb29d72c35e5");
    private static readonly Guid FrameSize = new Guid("1652c33d-d6b2-4012-b834-72030849a37d");
    private static readonly Guid DefaultStride = new Guid("644b4e48-1e02-4516-b0eb-c01ca9d49ac6");
    private static readonly Guid TypeVideo = new Guid("73646976-0000-0010-8000-00AA00389B71");
    private static readonly Guid FormatRgb32 = new Guid("00000016-0000-0010-8000-00AA00389B71");
    private static readonly Guid EnableVideoProcessing = new Guid("fb394f3d-ccf1-42ee-bbb3-f9b845d5681d");
    private static readonly Guid IidMediaSource = new Guid("279a808d-aec7-40c8-9c6b-a6b492c78a66");
    private const int FirstVideo = unchecked((int)0xFFFFFFFC);
    private const int MfVersion = 0x00020070;

    public Action<byte[]> OnJpeg;                 // verkleinertes JPEG, fertig zum Senden
    public volatile string LastError = "";
    public volatile bool Flip;                    // Bild steht auf dem Kopf? (manche Treiber liefern von unten nach oben)
    public volatile int MaxWidth = 320;
    private Thread thread;
    private volatile bool running;
    public bool IsRunning { get { return running; } }

    private static void Check(int hr, string what)
    {
        if (hr < 0) throw new InvalidOperationException(what + " (0x" + hr.ToString("X8") + ")");
    }

    // Namen aller Kameras; leer, wenn keine vorhanden ist.
    public static string[] Devices()
    {
        List<string> names = new List<string>();
        IPesMFAttributes attrs = null;
        IntPtr arr = IntPtr.Zero;
        bool started = false;
        try
        {
            if (MFStartup(MfVersion, 0) < 0) return names.ToArray();
            started = true;
            if (MFCreateAttributes(out attrs, 1) < 0) return names.ToArray();
            Guid k = SourceType, v = SourceTypeVidcap;
            attrs.SetGUID(ref k, ref v);
            int count;
            if (MFEnumDeviceSources(attrs, out arr, out count) < 0) return names.ToArray();
            for (int i = 0; i < count; i++)
            {
                IntPtr p = Marshal.ReadIntPtr(arr, i * IntPtr.Size);
                if (p == IntPtr.Zero) continue;
                try
                {
                    IPesMFActivate act = (IPesMFActivate)Marshal.GetObjectForIUnknown(p);
                    string nm; int len; Guid fk = FriendlyName;
                    if (act.GetAllocatedString(ref fk, out nm, out len) >= 0 && !string.IsNullOrEmpty(nm)) names.Add(nm); else names.Add("Kamera " + (i + 1));
                    Marshal.ReleaseComObject(act);
                }
                catch { names.Add("Kamera " + (i + 1)); }
                finally { Marshal.Release(p); }
            }
        }
        catch { }
        finally
        {
            if (arr != IntPtr.Zero) Marshal.FreeCoTaskMem(arr);
            try { if (attrs != null) Marshal.ReleaseComObject(attrs); } catch { }
            if (started) try { MFShutdown(); } catch { }
        }
        return names.ToArray();
    }

    // deviceName leer = erste Kamera. Fehler stehen danach in LastError.
    public void Start(string deviceName)
    {
        if (running) return;
        running = true; LastError = "";
        thread = new Thread(delegate () { Loop(deviceName); });
        thread.IsBackground = true; thread.Name = "PES-CAM"; thread.Start();
    }

    public void Stop()
    {
        running = false;
        Thread t = thread;
        if (t != null && t != Thread.CurrentThread) t.Join(2500);
        thread = null;
    }

    private void Loop(string deviceName)
    {
        IPesMFAttributes attrs = null, rattrs = null;
        IPesMFSourceReader reader = null;
        object source = null;
        IPesMFActivate chosen = null;
        IntPtr arr = IntPtr.Zero;
        bool started = false;
        try
        {
            Check(MFStartup(MfVersion, 0), "Media Foundation nicht verfuegbar");
            started = true;
            Check(MFCreateAttributes(out attrs, 1), "Attribute");
            Guid k = SourceType, v = SourceTypeVidcap;
            attrs.SetGUID(ref k, ref v);
            int count;
            Check(MFEnumDeviceSources(attrs, out arr, out count), "Kameras konnten nicht aufgelistet werden");
            if (count <= 0) throw new InvalidOperationException("Keine Kamera gefunden.");
            for (int i = 0; i < count; i++)
            {
                IntPtr p = Marshal.ReadIntPtr(arr, i * IntPtr.Size);
                if (p == IntPtr.Zero) continue;
                IPesMFActivate act = (IPesMFActivate)Marshal.GetObjectForIUnknown(p);
                Marshal.Release(p);
                string nm; int len; Guid fk = FriendlyName;
                act.GetAllocatedString(ref fk, out nm, out len);
                bool take = chosen == null && (string.IsNullOrEmpty(deviceName) || string.Equals(nm, deviceName, StringComparison.OrdinalIgnoreCase));
                if (take) chosen = act; else Marshal.ReleaseComObject(act);
            }
            if (chosen == null) throw new InvalidOperationException("Die gewaehlte Kamera ist nicht angeschlossen.");
            Guid iid = IidMediaSource;
            Check(chosen.ActivateObject(ref iid, out source), "Kamera konnte nicht geoeffnet werden (wird sie von einem anderen Programm benutzt?)");
            Check(MFCreateAttributes(out rattrs, 1), "Attribute");
            Guid vp = EnableVideoProcessing;
            rattrs.SetUINT32(ref vp, 1);
            Check(MFCreateSourceReaderFromMediaSource(source, rattrs, out reader), "Kamera-Leser");

            // Kleines natives Format bevorzugen (weniger Rechenlast); schlaegt das fehl, bleibt die Voreinstellung
            try { PickNative(reader); } catch { }
            IPesMFMediaType want;
            Check(MFCreateMediaType(out want), "Medientyp");
            Guid mk = MajorType, mv = TypeVideo, sk = SubType, sv = FormatRgb32;
            want.SetGUID(ref mk, ref mv);
            want.SetGUID(ref sk, ref sv);
            Check(reader.SetCurrentMediaType(FirstVideo, IntPtr.Zero, want), "Die Kamera liefert kein passendes Bildformat");
            Marshal.ReleaseComObject(want);
            IPesMFMediaType cur;
            Check(reader.GetCurrentMediaType(FirstVideo, out cur), "Bildformat");
            long fs; Guid fk2 = FrameSize;
            Check(cur.GetUINT64(ref fk2, out fs), "Bildgroesse");
            int w = (int)(fs >> 32), h = (int)(fs & 0xFFFFFFFF);
            int stride; Guid dk = DefaultStride;
            if (cur.GetUINT32(ref dk, out stride) < 0 || stride == 0) stride = w * 4;
            Marshal.ReleaseComObject(cur);
            if (w < 16 || h < 16 || w > 8192 || h > 8192) throw new InvalidOperationException("Unerwartete Bildgroesse " + w + "x" + h);

            ImageCodecInfo codec = null;
            foreach (ImageCodecInfo c in ImageCodecInfo.GetImageEncoders()) if (c.FormatID == ImageFormat.Jpeg.Guid) codec = c;
            EncoderParameters ep = new EncoderParameters(1);
            ep.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, 55L);
            MemoryStream ms = new MemoryStream(1 << 15);
            byte[] raw = new byte[w * 4 * h];
            Stopwatch clock = Stopwatch.StartNew();
            long lastSent = -1000;
            int errors = 0;
            while (running)
            {
                int actual, flags; long ts; IPesMFSample sample;
                int hr = reader.ReadSample(FirstVideo, 0, out actual, out flags, out ts, out sample);
                if (hr < 0 || (flags & 1) != 0) { if (++errors > 20) throw new InvalidOperationException("Die Kamera liefert keine Bilder mehr."); Thread.Sleep(50); continue; }
                if ((flags & 2) != 0) throw new InvalidOperationException("Die Kamera wurde getrennt.");
                if (sample == null) { Thread.Sleep(5); continue; }
                errors = 0;
                try
                {
                    // hoechstens ca. 12 Bilder je Sekunde weitergeben
                    if (clock.ElapsedMilliseconds - lastSent < 80) continue;
                    IPesMFMediaBuffer buf;
                    if (sample.ConvertToContiguousBuffer(out buf) < 0 || buf == null) continue;
                    try
                    {
                        IntPtr ptr; int max, len;
                        if (buf.Lock(out ptr, out max, out len) < 0) continue;
                        try { if (len >= raw.Length) Marshal.Copy(ptr, raw, 0, raw.Length); else continue; }
                        finally { buf.Unlock(); }
                    }
                    finally { Marshal.ReleaseComObject(buf); }
                    lastSent = clock.ElapsedMilliseconds;
                    int mw = MaxWidth; if (mw < 160) mw = 160;
                    int ow = Math.Min(w, mw) & ~1, oh = Math.Max(2, (int)((long)h * ow / w) & ~1);
                    GCHandle pin = GCHandle.Alloc(raw, GCHandleType.Pinned);
                    try
                    {
                        using (Bitmap src = new Bitmap(w, h, w * 4, PixelFormat.Format32bppRgb, pin.AddrOfPinnedObject()))
                        using (Bitmap dst = new Bitmap(ow, oh, PixelFormat.Format24bppRgb))
                        {
                            using (Graphics g = Graphics.FromImage(dst))
                            {
                                g.InterpolationMode = InterpolationMode.Bilinear;
                                g.PixelOffsetMode = PixelOffsetMode.Half;
                                g.DrawImage(src, new Rectangle(0, 0, ow, oh), 0, 0, w, h, GraphicsUnit.Pixel);
                            }
                            if ((stride < 0) != Flip) dst.RotateFlip(RotateFlipType.RotateNoneFlipY);
                            ms.SetLength(0);
                            dst.Save(ms, codec, ep);
                        }
                    }
                    finally { pin.Free(); }
                    Action<byte[]> cb = OnJpeg;
                    if (cb != null) cb(ms.ToArray());
                }
                finally { Marshal.ReleaseComObject(sample); }
            }
        }
        catch (Exception ex) { LastError = ex.Message; }
        finally
        {
            running = false;
            try { if (reader != null) Marshal.ReleaseComObject(reader); } catch { }
            try { if (chosen != null) { chosen.ShutdownObject(); Marshal.ReleaseComObject(chosen); } } catch { }
            try { if (source != null) Marshal.ReleaseComObject(source); } catch { }
            try { if (rattrs != null) Marshal.ReleaseComObject(rattrs); } catch { }
            try { if (attrs != null) Marshal.ReleaseComObject(attrs); } catch { }
            if (arr != IntPtr.Zero) Marshal.FreeCoTaskMem(arr);
            if (started) try { MFShutdown(); } catch { }
        }
    }

    // Natives Format waehlen: moeglichst nah an 640x480, nie groesser als noetig.
    private static void PickNative(IPesMFSourceReader reader)
    {
        IPesMFMediaType best = null;
        long bestScore = long.MaxValue;
        for (int i = 0; i < 200; i++)
        {
            IPesMFMediaType t;
            if (reader.GetNativeMediaType(FirstVideo, i, out t) < 0 || t == null) break;
            long fs; Guid fk = FrameSize;
            if (t.GetUINT64(ref fk, out fs) >= 0)
            {
                int w = (int)(fs >> 32), h = (int)(fs & 0xFFFFFFFF);
                long score = Math.Abs((long)w * h - 640L * 480L) + (w < 320 ? 1000000 : 0);
                if (score < bestScore) { if (best != null) Marshal.ReleaseComObject(best); best = t; bestScore = score; continue; }
            }
            Marshal.ReleaseComObject(t);
        }
        if (best != null)
        {
            reader.SetCurrentMediaType(FirstVideo, IntPtr.Zero, best);
            Marshal.ReleaseComObject(best);
        }
    }
}

// ----------------------------------------------------------------------------
// Anzeige eines Videobilds (Partner oder eigene Kamera). Bilder kommen als JPEG aus
// einem Arbeits-Thread; gezeichnet wird im Oberflaechen-Thread.
// ----------------------------------------------------------------------------
public class PesVideoPanel : Control
{
    private readonly object sync = new object();
    private Bitmap frame;
    private int rot;
    private long lastFrameTick;
    private volatile bool dirty;
    private readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer();
    private string placeholder = "", caption = "";
    // Aenderungen der Texte loesen ein Neuzeichnen aus (ueber den Zeitgeber im Oberflaechen-Thread)
    public string Placeholder { get { return placeholder; } set { string v = value ?? ""; if (v != placeholder) { placeholder = v; dirty = true; } } }
    public string Caption { get { return caption; } set { string v = value ?? ""; if (v != caption) { caption = v; dirty = true; } } }
    public bool Mirror;

    public PesVideoPanel()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        BackColor = Color.FromArgb(20, 24, 28);
        ForeColor = Color.FromArgb(241, 241, 241);
        timer.Interval = 40;
        timer.Tick += delegate
        {
            // Bild verschwindet, wenn 2,5 s nichts mehr kam (Kamera aus / Verbindung weg)
            bool stale;
            lock (sync) { stale = frame != null && Environment.TickCount - lastFrameTick > 2500; if (stale) { frame.Dispose(); frame = null; } }
            if (dirty || stale) { dirty = false; Invalidate(); }
        };
        timer.Start();
    }

    // Aus beliebigem Thread.
    public void SetJpeg(byte[] jpeg, int rotQuarter)
    {
        if (jpeg == null || jpeg.Length < 16 || IsDisposed) return;
        Bitmap b = null;
        try
        {
            using (MemoryStream ms = new MemoryStream(jpeg))
            using (Image img = Image.FromStream(ms, false, true))
            {
                if (img.Width > 4096 || img.Height > 4096) return;
                b = new Bitmap(img);                                    // Kopie, damit der Datenstrom geschlossen werden kann
            }
        }
        catch { return; }
        lock (sync)
        {
            if (frame != null) frame.Dispose();
            frame = b; rot = rotQuarter & 3; lastFrameTick = Environment.TickCount;
        }
        dirty = true;
    }

    public void Clear()
    {
        lock (sync) { if (frame != null) { frame.Dispose(); frame = null; } }
        dirty = true;
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.Clear(BackColor);
        bool drawn = false;
        lock (sync)
        {
            if (frame != null && Width > 4 && Height > 4)
            {
                int fw = frame.Width, fh = frame.Height;
                bool side = (rot & 1) != 0;
                double iw = side ? fh : fw, ih = side ? fw : fh;
                double sc = Math.Min(Width / iw, Height / ih);
                float dw = (float)(fw * sc), dh = (float)(fh * sc);
                g.InterpolationMode = InterpolationMode.Bilinear;
                GraphicsState st = g.Save();
                g.TranslateTransform(Width / 2f, Height / 2f);
                g.RotateTransform(rot * 90f);
                if (Mirror) g.ScaleTransform(-1f, 1f);
                g.DrawImage(frame, -dw / 2f, -dh / 2f, dw, dh);
                g.Restore(st);
                drawn = true;
            }
        }
        if (!drawn && !string.IsNullOrEmpty(Placeholder))
        {
            using (StringFormat sf = new StringFormat())
            using (Brush br = new SolidBrush(Color.FromArgb(170, 178, 190)))
            {
                sf.Alignment = StringAlignment.Center; sf.LineAlignment = StringAlignment.Center;
                g.DrawString(Placeholder, Font, br, new RectangleF(4, 4, Width - 8, Height - 8), sf);
            }
        }
        if (!string.IsNullOrEmpty(Caption))
        {
            SizeF sz = g.MeasureString(Caption, Font);
            using (Brush bg = new SolidBrush(Color.FromArgb(150, 0, 0, 0))) g.FillRectangle(bg, 6, Height - sz.Height - 8, sz.Width + 8, sz.Height + 2);
            using (Brush br = new SolidBrush(ForeColor)) g.DrawString(Caption, Font, br, 10, Height - sz.Height - 7);
        }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) { timer.Stop(); timer.Dispose(); lock (sync) { if (frame != null) { frame.Dispose(); frame = null; } } }
        base.Dispose(disposing);
    }
}

// ----------------------------------------------------------------------------
// Ferner Bildschirm beim Helfer: setzt die empfangenen JPEG-Rechtecke zusammen,
// zeichnet sie eingepasst und meldet Maus und Tastatur an die Sitzung.
// ----------------------------------------------------------------------------
public class PesViewPanel : Control
{
    private readonly object sync = new object();
    private Bitmap canvas;
    private volatile bool dirty;
    private readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer();
    private readonly BlockingCollection<KeyValuePair<int[], byte[]>> queue = new BlockingCollection<KeyValuePair<int[], byte[]>>(new ConcurrentQueue<KeyValuePair<int[], byte[]>>(), 3000);
    private Thread worker;
    private volatile bool alive = true;
    public PesSession Session;
    private volatile bool controlEnabled;
    private string placeholder = "";
    public bool ControlEnabled { get { return controlEnabled; } set { if (value != controlEnabled) { controlEnabled = value; dirty = true; } } }
    public string Placeholder { get { return placeholder; } set { string v = value ?? ""; if (v != placeholder) { placeholder = v; dirty = true; } } }
    public long Rects, Bytes;

    public PesViewPanel()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.Selectable, true);
        BackColor = Color.FromArgb(18, 18, 18);
        ForeColor = Color.FromArgb(170, 178, 190);
        TabStop = true;
        timer.Interval = 33;
        timer.Tick += delegate { if (dirty) { dirty = false; Invalidate(); } };
        timer.Start();
        worker = new Thread(Work); worker.IsBackground = true; worker.Name = "PES-VIEW"; worker.Start();
    }

    // Aus dem Netz-Thread: nur einreihen (JPEG-Dekodieren laeuft im eigenen Thread).
    public void Post(int[] r, byte[] jpeg)
    {
        if (!alive || r == null || r.Length < 7 || jpeg == null) return;
        bool ok = false;
        try { ok = queue.TryAdd(new KeyValuePair<int[], byte[]>(r, jpeg), 40); } catch { }
        // Kommt die Anzeige nicht nach, ginge ein Bereich verloren: dann ein Komplettbild nachfordern
        if (!ok) { PesSession s = Session; if (s != null) s.RequestScreen(5); }
    }

    private void Work()
    {
        while (alive)
        {
            KeyValuePair<int[], byte[]> it;
            try { if (!queue.TryTake(out it, 250)) continue; } catch { break; }
            try
            {
                int[] r = it.Key;
                using (MemoryStream ms = new MemoryStream(it.Value))
                using (Image img = Image.FromStream(ms, false, true))
                {
                    if (img.Width != r[4] || img.Height != r[5]) continue;   // Bild passt nicht zur Ankuendigung
                    lock (sync)
                    {
                        if (canvas == null || canvas.Width != r[0] || canvas.Height != r[1])
                        {
                            if (canvas != null) canvas.Dispose();
                            canvas = new Bitmap(r[0], r[1], PixelFormat.Format24bppRgb);
                        }
                        using (Graphics g = Graphics.FromImage(canvas))
                        {
                            g.CompositingMode = CompositingMode.SourceCopy;
                            g.InterpolationMode = InterpolationMode.NearestNeighbor;
                            g.PixelOffsetMode = PixelOffsetMode.Half;
                            g.DrawImage(img, new Rectangle(r[2], r[3], r[4], r[5]), 0, 0, r[4], r[5], GraphicsUnit.Pixel);
                        }
                    }
                }
                Interlocked.Increment(ref Rects); Interlocked.Add(ref Bytes, it.Value.Length);
                dirty = true;
            }
            catch { }
        }
    }

    public void ClearImage()
    {
        lock (sync) { if (canvas != null) { canvas.Dispose(); canvas = null; } }
        dirty = true;
    }

    public bool HasImage { get { lock (sync) { return canvas != null; } } }

    // Bildschirmfoto des fernen Bildschirms als PNG speichern. Liefert false, wenn noch kein Bild da ist.
    public bool SaveImage(string path)
    {
        lock (sync)
        {
            if (canvas == null) return false;
            canvas.Save(path, ImageFormat.Png);
            return true;
        }
    }

    // Lage des Bilds im Panel (eingepasst, zentriert)
    private RectangleF ImageRect()
    {
        lock (sync)
        {
            if (canvas == null || Width < 8 || Height < 8) return RectangleF.Empty;
            double sc = Math.Min((double)Width / canvas.Width, (double)Height / canvas.Height);
            float w = (float)(canvas.Width * sc), h = (float)(canvas.Height * sc);
            return new RectangleF((Width - w) / 2f, (Height - h) / 2f, w, h);
        }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.Clear(BackColor);
        bool drawn = false;
        lock (sync)
        {
            if (canvas != null && Width > 8 && Height > 8)
            {
                double sc = Math.Min((double)Width / canvas.Width, (double)Height / canvas.Height);
                float w = (float)(canvas.Width * sc), h = (float)(canvas.Height * sc);
                g.InterpolationMode = sc < 1.0 ? InterpolationMode.Bilinear : InterpolationMode.NearestNeighbor;
                g.PixelOffsetMode = PixelOffsetMode.Half;
                g.DrawImage(canvas, (Width - w) / 2f, (Height - h) / 2f, w, h);
                drawn = true;
            }
        }
        if (!drawn && !string.IsNullOrEmpty(Placeholder))
        {
            using (StringFormat sf = new StringFormat())
            using (Brush br = new SolidBrush(ForeColor))
            {
                sf.Alignment = StringAlignment.Center; sf.LineAlignment = StringAlignment.Center;
                g.DrawString(Placeholder, Font, br, new RectangleF(8, 8, Width - 16, Height - 16), sf);
            }
        }
        if (ControlEnabled && Focused)
        {
            using (Pen p = new Pen(Color.FromArgb(0, 120, 215), 2f)) g.DrawRectangle(p, 1, 1, Width - 3, Height - 3);
        }
    }

    private bool Map(Point p, out int x, out int y)
    {
        x = 0; y = 0;
        RectangleF r = ImageRect();
        if (r.Width < 2 || r.Height < 2) return false;
        double fx = (p.X - r.X) / (r.Width - 1), fy = (p.Y - r.Y) / (r.Height - 1);
        if (fx < 0) fx = 0; if (fx > 1) fx = 1; if (fy < 0) fy = 0; if (fy > 1) fy = 1;
        x = (int)Math.Round(fx * 65535); y = (int)Math.Round(fy * 65535);
        return true;
    }

    private static int Btn(MouseButtons b) { return b == MouseButtons.Left ? 0 : (b == MouseButtons.Right ? 1 : (b == MouseButtons.Middle ? 2 : -1)); }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e);
        if (!Focused) Focus();
        int x, y; PesSession s = Session;
        if (!ControlEnabled || s == null || Btn(e.Button) < 0 || !Map(e.Location, out x, out y)) return;
        s.InputButton(Btn(e.Button), true, x, y);
    }

    protected override void OnMouseUp(MouseEventArgs e)
    {
        base.OnMouseUp(e);
        int x, y; PesSession s = Session;
        if (!ControlEnabled || s == null || Btn(e.Button) < 0 || !Map(e.Location, out x, out y)) return;
        s.InputButton(Btn(e.Button), false, x, y);
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        int x, y; PesSession s = Session;
        if (!ControlEnabled || s == null || !Map(e.Location, out x, out y)) return;
        s.InputMove(x, y);
    }

    protected override void OnMouseWheel(MouseEventArgs e)
    {
        base.OnMouseWheel(e);
        int x, y; PesSession s = Session;
        if (!ControlEnabled || s == null || !Map(e.Location, out x, out y)) return;
        s.InputWheel(e.Delta, x, y);
    }

    protected override void OnGotFocus(EventArgs e) { base.OnGotFocus(e); Invalidate(); }
    protected override void OnLostFocus(EventArgs e) { base.OnLostFocus(e); Invalidate(); }

    // Tasten gehen an den fernen PC, solange das Bild den Fokus hat (auch Tab, Pfeile, Alt, F-Tasten).
    public override bool PreProcessMessage(ref Message msg)
    {
        int m = msg.Msg;
        if (ControlEnabled && Session != null && (m == 0x0100 || m == 0x0101 || m == 0x0104 || m == 0x0105))
        {
            int vk = (int)(msg.WParam.ToInt64() & 0xFFFF);
            bool ext = ((msg.LParam.ToInt64() >> 24) & 1) != 0;
            Session.InputKey(vk, m == 0x0100 || m == 0x0104, ext);
            return true;
        }
        return base.PreProcessMessage(ref msg);
    }

    // Tastenfolge senden (z. B. Strg+Umschalt+Esc): alle druecken, in umgekehrter Reihenfolge loslassen.
    public void SendChord(int[] vks)
    {
        PesSession s = Session;
        if (!ControlEnabled || s == null || vks == null) return;
        foreach (int vk in vks) s.InputKey(vk, true, vk == 0x5B);
        for (int i = vks.Length - 1; i >= 0; i--) s.InputKey(vks[i], false, vks[i] == 0x5B);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            alive = false; timer.Stop(); timer.Dispose();
            lock (sync) { if (canvas != null) { canvas.Dispose(); canvas = null; } }
        }
        base.Dispose(disposing);
    }
}

// ----------------------------------------------------------------------------
// Bindeglied fuer PowerShell: baut Engine und Sitzung auf (im Hintergrund, die
// Oberflaeche blockiert nie) und schaltet Ton, Kamera, Freigabe und Steuerung.
// ----------------------------------------------------------------------------
public sealed class PesHost
{
    public PesP2pEngine Engine;
    public PesSession Session;
    public PesScreen Screen;
    public PesInput Input;
    public PesVideoPanel RemoteVideo, SelfVideo;
    public PesViewPanel View;
    public volatile int State;                    // 0 = getrennt, 1 = verbindet, 2 = laeuft, 3 = Fehler
    public volatile string Error = "";
    public volatile string MediaError = "";
    public volatile bool EchoGate = true;         // Mikrofon stumm, solange der Partner laut zu hoeren ist (ohne Kopfhoerer sinnvoll)
    public volatile int MicLevel, SpeakerLevel;
    private PesAudioIn mic;
    private PesAudioOut spk;
    private PesCamera cam;
    private long loudTick;
    private readonly object mediaLock = new object();

    public bool MediaRunning { get { return spk != null; } }
    public bool CameraRunning { get { PesCamera c = cam; return c != null && c.IsRunning; } }
    public string CameraError { get { PesCamera c = cam; return c == null ? "" : c.LastError; } }

    // Verbindet im Hintergrund (Schluesselableitung dauert einen Moment).
    public void Connect(string server, int port, string lobby, string password, string name, string machineKey,
                        int role, int udpPort, string bindIp, string downloadDir)
    {
        if (State == 1 || State == 2) return;
        State = 1; Error = "";
        PesP2pEngine eng = new PesP2pEngine();
        eng.PreferredPort = udpPort;
        IPAddress bind;
        if (!string.IsNullOrEmpty(bindIp) && IPAddress.TryParse(bindIp, out bind)) eng.BindAddress = bind;
        PesSession ses = new PesSession(eng);
        ses.MyName = name; ses.Role = role; ses.Platform = 1; ses.DownloadDir = downloadDir;
        Engine = eng; Session = ses;
        Screen = new PesScreen(ses);
        Input = new PesInput(Screen);
        PesVideoPanel rv = RemoteVideo; PesViewPanel vw = View; PesInput inp = Input;
        ses.OnVideoFrame = delegate (byte[] j, int r) { if (rv != null) rv.SetJpeg(j, r); };
        ses.OnScreenRect = delegate (int[] r, byte[] j) { if (vw != null) vw.Post(r, j); };
        ses.OnInput = delegate (byte[] b) { inp.Post(b); };
        if (vw != null) vw.Session = ses;
        Thread t = new Thread(delegate ()
        {
            try
            {
                eng.Start(server, port, lobby, password, name, machineKey);
                ses.Start();
                State = 2;
            }
            catch (Exception ex)
            {
                Error = ex.Message; State = 3;
                try { eng.Stop(); } catch { }
            }
        });
        t.IsBackground = true; t.Name = "PES-CONNECT"; t.Start();
    }

    public void Disconnect()
    {
        StopShare();
        StopMedia();
        PesSession s = Session; PesP2pEngine e = Engine;
        Session = null; Engine = null;
        PesViewPanel vw = View;
        if (vw != null) { vw.Session = null; vw.ControlEnabled = false; vw.ClearImage(); }
        if (RemoteVideo != null) RemoteVideo.Clear();
        if (SelfVideo != null) SelfVideo.Clear();
        State = 0;
        if (s == null && e == null) return;
        // Abmelden kann bis zu einigen Sekunden dauern (Threads beenden) - nicht im Oberflaechen-Thread
        Thread t = new Thread(delegate ()
        {
            try { if (s != null) s.Stop(); } catch { }
            try { if (e != null) e.Stop(); } catch { }
        });
        t.IsBackground = true; t.Name = "PES-DISCONNECT"; t.Start();
        t.Join(200);
    }

    // ---- Ton und Kamera (waehrend eines Anrufs) ----
    public void StartMedia(int micDevice, int speakerDevice)
    {
        lock (mediaLock)
        {
            if (spk != null) return;
            PesSession s = Session;
            if (s == null) return;
            MediaError = "";
            PesAudioOut o = new PesAudioOut();
            o.PullFrame = delegate ()
            {
                short[] f = s.PullAudio();
                int peak = 0;
                for (int i = 0; i < f.Length; i += 4) { int a = f[i] < 0 ? -f[i] : f[i]; if (a > peak) peak = a; }
                SpeakerLevel = peak;
                if (peak > 2500) Interlocked.Exchange(ref loudTick, Stopwatch.GetTimestamp());
                return f;
            };
            string e1 = o.Start(speakerDevice);
            if (e1 != null) o = null;
            spk = o == null ? new PesAudioOut() : o;
            PesAudioIn m = new PesAudioIn();
            m.OnFrame = delegate (short[] f)
            {
                int peak = 0;
                for (int i = 0; i < f.Length; i += 4) { int a = f[i] < 0 ? -f[i] : f[i]; if (a > peak) peak = a; }
                MicLevel = peak;
                if (EchoGate)
                {
                    long lt = Interlocked.Read(ref loudTick);
                    if (lt != 0 && (Stopwatch.GetTimestamp() - lt) * 1000 / Stopwatch.Frequency < 250) return;
                }
                s.SendAudio(f);
            };
            string e2 = m.Start(micDevice);
            if (e2 != null) m = null;
            mic = m;
            if (e1 != null && e2 != null) MediaError = "Kein Lautsprecher und kein Mikrofon gefunden - der Anruf laeuft ohne Ton.";
            else if (e1 != null) MediaError = "Kein Lautsprecher gefunden - du hoerst den Partner nicht.";
            else if (e2 != null) MediaError = "Kein Mikrofon gefunden - der Partner hoert dich nicht.";
        }
    }

    public void StopMedia()
    {
        lock (mediaLock)
        {
            StopCamera();
            try { if (mic != null) mic.Stop(); } catch { }
            try { if (spk != null) spk.Stop(); } catch { }
            mic = null; spk = null; MicLevel = 0; SpeakerLevel = 0;
        }
    }

    public void StartCamera(string deviceName, bool flip)
    {
        PesSession s = Session;
        if (s == null || CameraRunning) return;
        PesCamera c = new PesCamera();
        c.Flip = flip;
        PesVideoPanel sv = SelfVideo;
        c.OnJpeg = delegate (byte[] j) { s.SendVideo(j, 0); if (sv != null) sv.SetJpeg(j, 0); };
        cam = c;
        c.Start(deviceName);
    }

    public void StopCamera()
    {
        PesCamera c = cam; cam = null;
        if (c != null) try { c.Stop(); } catch { }
        if (SelfVideo != null) SelfVideo.Clear();
    }

    // ---- Freigabe des eigenen Bildschirms (Kunde, nur nach ausdruecklicher Zustimmung in der Oberflaeche) ----
    public void StartShare(bool control)
    {
        PesSession s = Session;
        if (s == null || s.Role != PesProto.RoleCustomer) return;
        s.SetShare(true, control, 0, 0, 0, 1);
        Input.Enabled = control;
        if (control) Input.Start();
        Screen.Start();
    }

    public void SetControl(bool control)
    {
        PesSession s = Session;
        if (s == null || !s.ShareActive) return;
        Input.Enabled = control;
        if (control) Input.Start();
        s.SetShare(true, control, s.ScreenW, s.ScreenH, s.ScreenMonitor, s.ScreenMonitors);
    }

    public void StopShare()
    {
        PesSession s = Session;
        PesInput i = Input; PesScreen sc = Screen;
        if (i != null) i.Enabled = false;
        if (s != null && s.Role == PesProto.RoleCustomer && s.ShareActive) { try { s.SetShare(false, false, 0, 0, 0, 1); } catch { } }
        if (sc != null) sc.Stop();
        if (i != null) i.Stop();
    }
}

// ----------------------------------------------------------------------------
// Zweisprachigkeit DE/EN: Der Quelltext bleibt deutsch. Bei "en" wird jeder Text
// beim Anzeigen uebersetzt (Woerterbuch "deutscher Text<TAB>English text").
// Registrierte Controls werden beim Umschalten der Sprache sofort neu beschriftet.
// ----------------------------------------------------------------------------
public static class PesI18n
{
    public static volatile string Lang = "de";
    private static readonly Dictionary<string, string> en = new Dictionary<string, string>(StringComparer.Ordinal);
    private static readonly List<KeyValuePair<string, string>> enPrefixes = new List<KeyValuePair<string, string>>();
    // Die Meldungen des Kerns sind bewusst reines ASCII ("laeuft"); fuer die deutsche Anzeige gibt es hier die Schreibweise mit Umlauten
    private static readonly Dictionary<string, string> de = new Dictionary<string, string>(StringComparer.Ordinal);
    private static readonly List<KeyValuePair<string, string>> dePrefixes = new List<KeyValuePair<string, string>>();
    private static readonly List<KeyValuePair<WeakReference, string>> reg = new List<KeyValuePair<WeakReference, string>>();
    private static readonly HashSet<string> missing = new HashSet<string>();

    // Zeilen "deutsch<TAB>anderer Text"; endet der deutsche Teil mit "*", gilt er als Anfang (der Rest wird ebenfalls nachgeschlagen).
    private static void Fill(string dict, Dictionary<string, string> exact, List<KeyValuePair<string, string>> prefixes)
    {
        exact.Clear(); prefixes.Clear();
        if (dict == null) return;
        foreach (string raw in dict.Split('\n'))
        {
            string line = raw.TrimEnd('\r');
            int t = line.IndexOf('\t');
            if (t <= 0 || line.StartsWith("#")) continue;
            string k = line.Substring(0, t), v = line.Substring(t + 1);
            if (k.EndsWith("*") && v.EndsWith("*")) prefixes.Add(new KeyValuePair<string, string>(k.Substring(0, k.Length - 1), v.Substring(0, v.Length - 1)));
            else exact[k] = v;
        }
    }

    public static void Load(string dictEn, string dictDe)
    {
        Fill(dictEn, en, enPrefixes);
        Fill(dictDe, de, dePrefixes);
    }

    private static bool Find(string text, Dictionary<string, string> exact, List<KeyValuePair<string, string>> prefixes, out string result)
    {
        if (exact.TryGetValue(text, out result)) return true;
        foreach (KeyValuePair<string, string> p in prefixes)
        {
            if (!text.StartsWith(p.Key, StringComparison.Ordinal)) continue;
            string rest = text.Substring(p.Key.Length), r2;
            result = p.Value + (Find(rest, exact, prefixes, out r2) ? r2 : rest);
            return true;
        }
        result = text;
        return false;
    }

    // Feste Texte der Oberflaeche (deutsch im Quelltext).
    public static string T(string text)
    {
        if (string.IsNullOrEmpty(text) || Lang != "en") return text;
        string r;
        if (Find(text, en, enPrefixes, out r)) return r;
        lock (missing) { if (missing.Count < 500) missing.Add(text); }
        return text;
    }

    // Meldungen aus dem Kern oder vom System: uebersetzen, soweit bekannt; sonst unveraendert.
    public static string Core(string text)
    {
        if (string.IsNullOrEmpty(text)) return text;
        string r;
        if (Lang == "en") { Find(text, en, enPrefixes, out r); return r; }
        Find(text, de, dePrefixes, out r);
        return r;
    }

    public static string F(string text, params object[] args)
    {
        try { return string.Format(T(text), args); } catch { return T(text); }
    }

    // Fuer die Build-Pruefung: feste Texte, fuer die es keine englische Fassung gab.
    public static string[] Missing() { lock (missing) { string[] a = new string[missing.Count]; missing.CopyTo(a); return a; } }

    public static void Reg(object target, string text)
    {
        if (target == null) return;
        lock (reg) { reg.Add(new KeyValuePair<WeakReference, string>(new WeakReference(target), text)); }
        Set(target, T(text));
    }

    private static void Set(object target, string text)
    {
        Control c = target as Control;
        if (c != null) { c.Text = text; return; }
        ToolStripItem i = target as ToolStripItem;
        if (i != null) { i.Text = text; return; }
    }

    public static void ApplyAll()
    {
        lock (reg)
        {
            for (int k = reg.Count - 1; k >= 0; k--)
            {
                object t = reg[k].Key.Target;
                if (t == null) { reg.RemoveAt(k); continue; }
                Control c = t as Control;
                if (c != null && c.IsDisposed) { reg.RemoveAt(k); continue; }
                try { Set(t, T(reg[k].Value)); } catch { }
            }
        }
    }
}
'@

function Initialize-PesTypes {
    if (-not ('PesHost' -as [type])) {
        # -IgnoreWarnings: eine harmlose Compiler-Warnung darf das Programm nie am Start hindern
        Add-Type -TypeDefinition $script:PesCode -Language CSharp -ReferencedAssemblies System.Windows.Forms, System.Drawing -IgnoreWarnings
    }
    [PesI18n]::Load($script:PesI18nDictEn, $script:PesI18nDictDe)
}

# ---- Sprache: Quelltext deutsch; Englisch über das Wörterbuch (deutscher Text<TAB>English text) ----
function T {
    param([string]$De)
    if ($args.Count -gt 0) { return [PesI18n]::F($De, [object[]]$args) }
    return [PesI18n]::T($De)
}

$script:PesI18nDictEn = @'
Abbrechen	Cancel
Ablehnen	Decline
Adresse kopieren	Copy address
Alles entfernen	Remove everything
Alles entfernen ...	Remove everything ...
Alles, was auf dem Bildschirm steht, wird übertragen. Sie können die Freigabe jederzeit beenden.	Everything shown on the screen is transmitted. You can stop sharing at any time.
Allgemein	General
Als Helfer erzeugst du ihn mit "Neuer Code".	As the helper you create it with "New code".
Anfrage abgelehnt.	Request declined.
Anfrage des Helfers	Request from the helper
Anleitung und Hilfe	Guide and help
Annehmen	Accept
Anruf abbrechen	Cancel call
Anruf beendet.	Call ended.
Anruf gestartet ...	Calling ...
Anruf verbunden.	Call connected.
Anrufen	Call
Ansehen und steuern	View and control
Ansicht beenden	Stop viewing
Auf den Desktop speichern	Save to desktop
Auflegen	Hang up
Ausführen (Windows+R)	Run (Windows+R)
Automatisch (empfohlen)	Automatic (recommended)
Autostart:	Autostart:
Beenden	Stop
Beim Minimieren in den Infobereich (neben der Uhr) legen	Minimize to the notification area (next to the clock)
Bereit für einen Anruf	Ready for a call
Bildschirm anfordern	Request screen
Bildschirm angefordert - der Kunde muss zustimmen.	Screen requested - the customer has to agree.
Bildschirm freigeben	Share screen
Bildschirm wird an {0} übertragen - mit Steuerung von Maus und Tastatur.	Screen is being transmitted to {0} - with control of mouse and keyboard.
Bildschirm wird an {0} übertragen - nur ansehen.	Screen is being transmitted to {0} - view only.
Bildschirm wird übertragen an {0}	Screen is being transmitted to {0}
Bildschirm wird übertragen an {0} - MIT STEUERUNG	Screen is being transmitted to {0} - WITH CONTROL
Bildschirm {0}	Screen {0}
Bildschirmfoto gespeichert: {0}	Screenshot saved: {0}
Bildschirmfoto konnte nicht gespeichert werden:	Screenshot could not be saved:
Bitte einen Namen eintragen.	Please enter a name.
Bitte zuerst die Adresse des Vermittlers eintragen (Name oder IP, optional mit :Port).	Please enter the address of the mediator first (name or IP, optionally with :port).
Chat und Verlauf	Chat and history
Das Datei-Angebot wurde zurückgezogen: {0}	The file offer was withdrawn: {0}
Datei angeboten: {0} - warte auf die Zustimmung des Partners.	File offered: {0} - waiting for the partner to agree.
Datei empfangen	Receive file
Datei empfangen und geprüft: {0}	File received and verified: {0}
Datei für den Partner auswählen	Choose a file for the partner
Datei gesendet und geprüft: {0}	File sent and verified: {0}
Datei kann nicht empfangen werden:	File cannot be received:
Datei kann nicht gesendet werden:	File cannot be sent:
Datei senden	Send file
Datei-Übertragung abgebrochen: {0}	File transfer aborted: {0}
Der Einladungscode ist ungültig. Er beginnt mit "PES1:" und kommt vom Helfer.	The invitation code is invalid. It starts with "PES1:" and comes from the helper.
Der Helfer hat die Ansicht beendet.	The helper stopped viewing.
Der Helfer hat die Steuerung abgegeben.	The helper released control.
Der Helfer sieht Ihren Bildschirm erst, wenn Sie zustimmen.	The helper only sees your screen after you agree.
Der Kunde erlaubt die Steuerung nicht (nur ansehen).	The customer does not allow control (view only).
Der Kunde hat die Anfrage abgelehnt.	The customer declined the request.
Der Kunde überträgt seinen Bildschirm - Steuerung erlaubt.	The customer is sharing the screen - control allowed.
Der Kunde überträgt seinen Bildschirm - nur ansehen.	The customer is sharing the screen - view only.
Der Kunde überträgt seinen Bildschirm nicht mehr.	The customer is no longer sharing the screen.
Der Kunde überträgt seinen Bildschirm nicht.	The customer is not sharing the screen.
Der Partner hat den Anruf abgelehnt.	The partner declined the call.
Der Partner hat die Datei abgelehnt: {0}	The partner declined the file: {0}
Der Partner hat nicht abgenommen.	The partner did not answer.
Der UDP-Port muss zwischen 1024 und 65535 liegen.	The UDP port must be between 1024 and 65535.
Der UDP-Port und der Vermittler-Port müssen verschieden sein.	The UDP port and the mediator port must be different.
Der Vermittler konnte nicht starten (Port {0} belegt?):	The mediator could not start (port {0} in use?):
Der Vermittler läuft auf UDP-Port {0}.	The mediator is running on UDP port {0}.
Der Vermittler-Port muss zwischen 1024 und 65535 liegen.	The mediator port must be between 1024 and 65535.
Desktop anzeigen (Windows+D)	Show desktop (Windows+D)
Die Kamera des Partners ist aus.	The partner's camera is off.
Die Sitzung läuft noch. Programm wirklich beenden?	The session is still running. Really quit the program?
Die Vermittler-Adresse im Einladungscode ist ungültig.	The mediator address in the invitation code is invalid.
Die öffentliche Adresse (DynDNS-Name) wird im Fenster des Vermittlers eingetragen - je Port getrennt.	The public address (DynDNS name) is entered in the mediator window - separately for each port.
Die öffentliche Adresse ist ungültig (nur Name oder IP, ohne Port).	The public address is invalid (name or IP only, without port).
Diese Adresse trägt der Helfer als "Vermittler-Adresse" ein:	The helper enters this address as "Mediator address":
Echo-Sperre: Mikrofon stumm, solange der Partner spricht (für Lautsprecher)	Echo lock: microphone muted while the partner speaks (for speakers)
Eigener Mini-Vermittler (nur für Helfer)	Own mini mediator (helpers only)
Einfügen	Paste
Eingehender Anruf	Incoming call
Eingehender Anruf ...	Incoming call ...
Einladungscode (PES1:...)	Invitation code (PES1:...)
Einladungscode in die Zwischenablage kopiert. Schicke ihn dem Kunden (z. B. per Messenger oder E-Mail).	Invitation code copied to the clipboard. Send it to the customer (e.g. by messenger or e-mail).
Empfange Datei: {0}	Receiving file: {0}
Empfange {0}: {1} von {2}	Receiving {0}: {1} of {2}
Empfangene Dateien	Received files
Empfangene Dateien und das Programm selbst bleiben erhalten.	Received files and the program itself are kept.
Entfernen	Remove
Entfernt den Autostart, alle Firewall-Regeln "Project Earth Support ..." und den Ordner mit Einstellungen und Protokollen.	Removes the autostart, all firewall rules "Project Earth Support ..." and the folder with settings and logs.
Erlauben	Allow
Erlauben Sie das nur Personen, denen Sie vertrauen. Notfall-Stopp: Strg+Umschalt+F12	Only allow this for people you trust. Emergency stop: Ctrl+Shift+F12
Erste Kamera	First camera
Es klingelt beim Partner ...	Ringing ...
Fenster schließen (Alt+F4)	Close window (Alt+F4)
Fenster wechseln (Alt+Tab)	Switch window (Alt+Tab)
Fernwartung	Remote support
Firewall-Regeln "Project Earth Support ...":	Firewall rules "Project Earth Support ...":
Firewall-Regeln entfernen	Remove firewall rules
Firewall-Regeln werden entfernt ...	Removing firewall rules ...
Foto	Photo
Freigabe beenden	Stop sharing
Freigabe beendet.	Sharing stopped.
Gespeichert	Saved
Gespeichert. Die Änderungen gelten ab dem nächsten Verbinden.	Saved. The changes apply from the next connection.
Getrennt.	Disconnected.
Großansicht	Large view
Helfer	helper
Hier erscheint das Bild des Partners, sobald ein Anruf läuft.	The partner's picture appears here as soon as a call is running.
Hier erscheint der Bildschirm des Kunden.	The customer's screen appears here.
Hilfe	Help
Hinweis: Bei Sperrbildschirm oder Windows-Sicherheitsabfrage (UAC) gibt es kurz kein Bild.	Note: on the lock screen or during a Windows security prompt (UAC) there is no picture for a moment.
Ich	Me
Ich brauche Hilfe	I need help
Ich helfe	I am helping
Ihr Bildschirm wird NICHT übertragen.	Your screen is NOT being transmitted.
Ihr Bildschirm wird an {0} übertragen - mit Steuerung.	Your screen is being transmitted to {0} - with control.
Ihr Bildschirm wird an {0} übertragen - nur ansehen.	Your screen is being transmitted to {0} - view only.
Im Gespräch	In call
Im selben Netz (LAN/WLAN) reicht die Adresse dieses PCs. Für Kunden im Internet: im Router den UDP-Port an diesen PC weiterleiten und hier die öffentliche Adresse (DynDNS-Name oder feste IP) eintragen.	In the same network (LAN/Wi-Fi) the address of this PC is enough. For customers on the internet: forward the UDP port to this PC in the router and enter the public address (DynDNS name or fixed IP) here.
In den Infobereich	To notification area
Ja, erlauben	Yes, allow
Ja, freigeben	Yes, share
Kamera	Camera
Kamera: an	Camera: on
Kamera: aus	Camera: off
Kamerabild steht auf dem Kopf: umdrehen	Camera picture is upside down: flip it
Kopieren	Copy
Kunde	customer
Lautsprecher	Speaker
Live-Video-Chat	Live video chat
Maus und Tastatur kann er nur bedienen, wenn Sie das zusätzlich erlauben.	Mouse and keyboard can only be used if you additionally allow it.
Mein Name	My name
Mikrofon	Microphone
Mikrofon: an	Microphone: on
Mikrofon: aus	Microphone: off
Mit "Bildschirm anfordern" fragst du ihn danach.	Ask for it with "Request screen".
Mit Windows starten (bleibt im Infobereich, verbindet nicht von selbst)	Start with Windows (stays in the notification area, never connects by itself)
Nehmen Sie nur Dateien an, die Sie erwarten. Gespeichert wird im Ordner "Downloads\Project Earth Support".	Only accept files you are expecting. They are saved in the folder "Downloads\Project Earth Support".
Nein	No
Netzwerk	Network
Netzwerkadapter	Network adapter
Neuer Code	New code
Neuer Einladungscode erzeugt. Mit "Kopieren" in die Zwischenablage legen und dem Kunden schicken.	New invitation code created. Put it on the clipboard with "Copy" and send it to the customer.
Nicht verbunden. Rechts den Einladungscode einfügen und auf Verbinden klicken.	Not connected. Paste the invitation code on the right and click Connect.
Normal	Normal
Normalansicht	Normal view
Notfall-Stopp jederzeit: Strg+Umschalt+F12	Emergency stop at any time: Ctrl+Shift+F12
Notfall-Stopp: Freigabe beendet.	Emergency stop: sharing stopped.
Notfall-Stopp: Strg+Umschalt+F12	Emergency stop: Ctrl+Shift+F12
Nur ansehen	View only
Ohne eigenen Server: unten auf "Vermittler" klicken - er läuft dann auf diesem PC.	Without a server of your own: click "Mediator" at the bottom - it then runs on this PC.
Optionen	Options
Protokoll-Ordner öffnen	Open log folder
Scharf	Sharp
Schließen	Close
Sende Datei: {0}	Sending file: {0}
Sende {0}: {1} von {2}	Sending {0}: {1} of {2}
Senden	Send
Sitzung gestartet.	Session started.
Sitzung läuft - warte auf den Helfer.	Session running - waiting for the helper.
Sitzung läuft - warte auf den Kunden. Schicke ihm den Einladungscode.	Session running - waiting for the customer. Send them the invitation code.
Sitzung mit {0} wirklich beenden?	Really end the session with {0}?
Soll {0} Ihren Bildschirm jetzt sehen können?	Should {0} be able to see your screen now?
Soll {0} Maus und Tastatur dieses PCs bedienen dürfen?	Should {0} be allowed to use mouse and keyboard of this PC?
Sparsam	Economy
Speichern	Save
Speichern fehlgeschlagen	Saving failed
Sprache	Language
Standard	Default
Standardgerät (Windows)	Default device (Windows)
Steuerung anfordern	Request control
Steuerung angefordert - der Kunde muss zustimmen.	Control requested - the customer has to agree.
Steuerung erlauben	Allow control
Steuerung gesperrt - der Helfer kann nur noch zusehen.	Control locked - the helper can only watch now.
Steuerung sperren	Lock control
Steuerung: an	Control: on
Task-Manager (Strg+Umschalt+Esc)	Task Manager (Ctrl+Shift+Esc)
Tasten	Keys
Teilnehmer: {0}   weitergeleitete Pakete: {1}	Participants: {0}   forwarded packets: {1}
Ton und Kamera	Sound and camera
Trennen	Disconnect
UDP-Port (Standard 9890)	UDP port (default 9890)
UDP-Port (Standard 9892)	UDP port (default 9892)
Verbinde mit dem Vermittler {0} ...	Connecting to the mediator {0} ...
Verbinden	Connect
Verbinden fehlgeschlagen:	Connecting failed:
Verbindung	Connection
Verbindung wird aufgebaut ...	Connecting ...
Verbunden mit {0}	Connected to {0}
Vermittler	Mediator
Vermittler beenden	Stop mediator
Vermittler zusammen mit dem Autostart starten	Start the mediator together with the autostart
Vermittler-Adresse (Name oder IP, optional :Port)	Mediator address (name or IP, optional :port)
Verpasster Anruf.	Missed call.
Warte auf Zustimmung: {0}	Waiting for consent: {0}
Warte auf das Bild ...	Waiting for the picture ...
Warte auf die Zustimmung des Kunden ...	Waiting for the customer to agree ...
Weg: {0}	Path: {0}
Windows-Taste	Windows key
Wird entfernt ...	Removing ...
Wählen	Choose
Zufallsport	Random port
Zurück	Back
direkt	direct
merken	remember
ruft an (Video-Chat mit Ton)	is calling (video chat with sound)
verbindet ...	connecting ...
{0} ist nicht mehr verbunden.	{0} is no longer connected.
{0} ist verbunden ({1}, {2}).	{0} is connected ({1}, {2}).
{0} möchte Ihnen eine Datei senden:	{0} wants to send you a file:
{0} möchte Ihren Bildschirm sehen und Maus und Tastatur bedienen.	{0} wants to see your screen and use mouse and keyboard.
{0} möchte Ihren Bildschirm sehen.	{0} wants to see your screen.
{0} möchte zusätzlich Maus und Tastatur bedienen.	{0} additionally wants to use mouse and keyboard.
{0} ruft an.	{0} is calling.
Öffentliche Adresse	Public address
Öffnen	Open
Über diesen Vermittler laufen gerade Sitzungen. Wirklich beenden?	Sessions are currently running through this mediator. Really stop it?
Übernehmen	Apply
Übertragung: {0} Bilder/s, {1} kbit/s	Transmission: {0} frames/s, {1} kbit/s
über den Vermittler (Relay)	via the mediator (relay)
Getrennt	Disconnected
Verbunden	Connected
Schluessel werden abgeleitet ...	Deriving keys ...
Verbinde mit Vermittlungsserver ...	Connecting to the mediator ...
Server nicht erreichbar - bestehende Direktverbindungen bleiben aktiv	Mediator not reachable - existing direct connections stay active
Fehler: *	Error: *
Server-Adresse nicht aufloesbar	Mediator address cannot be resolved
Veraltete oder neuere Programmversion - bitte aktualisieren.	Outdated or newer program version - please update.
Server ausgelastet (zu viele Lobbys).	Mediator is full (too many sessions).
Keine freie virtuelle IP.	No free virtual address.
P2P laeuft bereits.	The connection is already running.
Der Lobby-Name muss mindestens 3 Zeichen haben.	The session name must have at least 3 characters.
Das Lobby-Passwort muss mindestens 6 Zeichen haben.	The session password must have at least 6 characters.
Kein Vermittlungsserver eingetragen.	No mediator entered.
Verbindung zum Partner verloren.	Connection to the partner lost.
Partner hat neu gestartet.	The partner restarted.
Der Partner hat die Sitzung beendet.	The partner ended the session.
Verbindung getrennt	connection closed
Datei nicht gefunden.	File not found.
Datei ist zu gross.	File is too large.
Nicht verbunden.	Not connected.
Es laeuft bereits eine Uebertragung.	A transfer is already running.
Kein offenes Angebot.	No open offer.
abgelehnt	declined
vom Absender abgebrochen	cancelled by the sender
vom Empfaenger abgebrochen	cancelled by the receiver
Empfaenger meldet Fehler	receiver reports an error
mehr Daten als angekuendigt	more data than announced
Pruefsumme stimmt nicht	checksum does not match
abgebrochen	cancelled
Kein Lautsprecher und kein Mikrofon gefunden - der Anruf laeuft ohne Ton.	No speaker and no microphone found - the call runs without sound.
Kein Lautsprecher gefunden - du hoerst den Partner nicht.	No speaker found - you cannot hear the partner.
Kein Mikrofon gefunden - der Partner hoert dich nicht.	No microphone found - the partner cannot hear you.
Keine Kamera gefunden.	No camera found.
Die gewaehlte Kamera ist nicht angeschlossen.	The selected camera is not connected.
Die Kamera liefert keine Bilder mehr.	The camera no longer delivers pictures.
Die Kamera wurde getrennt.	The camera was disconnected.
Kamera konnte nicht geoeffnet werden (wird sie von einem anderen Programm benutzt?) *	Camera could not be opened (is another program using it?) *
Die Kamera liefert kein passendes Bildformat *	The camera does not deliver a suitable picture format *
Media Foundation nicht verfuegbar *	Media Foundation not available *
angelegt	created
vorhanden	exists
entfernt	removed
entfernt: *	removed: *
'@

# Deutsche Anzeige für Meldungen aus dem Kern (der Kern selbst ist bewusst reines ASCII)
$script:PesI18nDictDe = @'
Schluessel werden abgeleitet ...	Schlüssel werden abgeleitet ...
Server-Adresse nicht aufloesbar	Vermittler-Adresse lässt sich nicht auflösen
Verbinde mit Vermittlungsserver ...	Verbinde mit dem Vermittler ...
Server nicht erreichbar - bestehende Direktverbindungen bleiben aktiv	Vermittler nicht erreichbar - bestehende Direktverbindungen bleiben aktiv
Fehler: *	Fehler: *
P2P laeuft bereits.	Die Verbindung läuft bereits.
Der Lobby-Name muss mindestens 3 Zeichen haben.	Der Sitzungsname muss mindestens 3 Zeichen haben.
Das Lobby-Passwort muss mindestens 6 Zeichen haben.	Das Sitzungs-Passwort muss mindestens 6 Zeichen haben.
Kein Vermittlungsserver eingetragen.	Kein Vermittler eingetragen.
Server ausgelastet (zu viele Lobbys).	Der Vermittler ist ausgelastet (zu viele Sitzungen).
Datei ist zu gross.	Datei ist zu groß.
Es laeuft bereits eine Uebertragung.	Es läuft bereits eine Übertragung.
vom Empfaenger abgebrochen	vom Empfänger abgebrochen
Empfaenger meldet Fehler	Empfänger meldet einen Fehler
mehr Daten als angekuendigt	mehr Daten als angekündigt
Pruefsumme stimmt nicht	Prüfsumme stimmt nicht
Kein Lautsprecher und kein Mikrofon gefunden - der Anruf laeuft ohne Ton.	Kein Lautsprecher und kein Mikrofon gefunden - der Anruf läuft ohne Ton.
Kein Lautsprecher gefunden - du hoerst den Partner nicht.	Kein Lautsprecher gefunden - du hörst den Partner nicht.
Kein Mikrofon gefunden - der Partner hoert dich nicht.	Kein Mikrofon gefunden - der Partner hört dich nicht.
Die gewaehlte Kamera ist nicht angeschlossen.	Die gewählte Kamera ist nicht angeschlossen.
Kamera konnte nicht geoeffnet werden (wird sie von einem anderen Programm benutzt?) *	Kamera konnte nicht geöffnet werden (wird sie von einem anderen Programm benutzt?) *
Media Foundation nicht verfuegbar *	Media Foundation nicht verfügbar *
'@

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

# Knopfleiste, die bei schmalem Fenster in eine zweite Zeile umbricht (nichts wird abgeschnitten)
function New-PesBar {
    param([string]$Dock = 'Top')
    $p = New-Object System.Windows.Forms.FlowLayoutPanel
    $p.Dock = $Dock
    $p.AutoSize = $true
    $p.AutoSizeMode = 'GrowAndShrink'
    $p.WrapContents = $true
    $p.BackColor = $script:C.Surface
    $p.Padding = New-Object System.Windows.Forms.Padding(6, 4, 6, 4)
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
    $barCall = New-PesBar -Dock 'Bottom'
    $u.BtnCall = New-PesButton -Text 'Anrufen' -X 0 -Y 0 -W 150 -H 32 -Kind 'ok' -Parent $barCall
    $u.BtnMic = New-PesButton -Text 'Mikrofon: an' -X 0 -Y 0 -W 130 -H 32 -Parent $barCall
    $u.BtnCam = New-PesButton -Text 'Kamera: aus' -X 0 -Y 0 -W 130 -H 32 -Parent $barCall
    $u.LblCall = New-PesLabel -Text '' -X 0 -Y 0 -W 100 -H 22 -Kind 'muted' -Parent $barCall
    $u.LblCall.Font = $script:FontUi
    $u.LblCall.AutoSize = $true
    $u.LblCall.Margin = New-Object System.Windows.Forms.Padding(8, 10, 4, 4)
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

    $barH = New-PesBar -Dock 'Top'
    $u.BarHelper = $barH
    $u.BtnView = New-PesButton -Text 'Bildschirm anfordern' -X 0 -Y 0 -W 170 -H 32 -Kind 'accent' -Parent $barH
    $u.BtnControl = New-PesButton -Text 'Steuerung anfordern' -X 0 -Y 0 -W 160 -H 32 -Parent $barH
    $u.CmbQuality = New-PesCombo -X 0 -Y 0 -W 100 -Parent $barH
    $u.CmbMonitor = New-PesCombo -X 0 -Y 0 -W 116 -Parent $barH
    $u.CmbQuality.Margin = New-Object System.Windows.Forms.Padding(3, 7, 3, 3)
    $u.CmbMonitor.Margin = New-Object System.Windows.Forms.Padding(3, 7, 3, 3)
    $u.BtnKeys = New-PesButton -Text 'Tasten' -X 0 -Y 0 -W 80 -H 32 -Parent $barH
    $u.BtnShot = New-PesButton -Text 'Foto' -X 0 -Y 0 -W 70 -H 32 -Parent $barH
    $u.BtnFull = New-PesButton -Text 'Großansicht' -X 0 -Y 0 -W 110 -H 32 -Parent $barH
    $barC = New-PesBar -Dock 'Top'
    $u.BarCustomer = $barC
    $u.BtnShare = New-PesButton -Text 'Bildschirm freigeben' -X 0 -Y 0 -W 190 -H 32 -Kind 'accent' -Parent $barC
    $u.BtnAllow = New-PesButton -Text 'Steuerung erlauben' -X 0 -Y 0 -W 180 -H 32 -Parent $barC
    $lblHot = New-PesLabel -Text 'Notfall-Stopp: Strg+Umschalt+F12' -X 0 -Y 0 -W 300 -H 22 -Kind 'muted' -Parent $barC
    $lblHot.Font = $script:FontUi
    $lblHot.AutoSize = $true
    $lblHot.Margin = New-Object System.Windows.Forms.Padding(8, 10, 4, 4)

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
        Initialize-PesSplit
        Update-PesSideLayout
        Update-PesTexts
    })
    Update-PesSideLayout
    return $f
}

# Teilt den Hauptbereich in Video (oben, 42 %) und Fernwartung (unten). Geht erst, wenn das Fenster seine Größe hat -
# beim Autostart (versteckt im Infobereich) also erst beim ersten Öffnen.
function Initialize-PesSplit {
    if ($script:PesState.SplitDone) { return }
    try {
        $sp = $script:PesUi.Split
        if ($sp.Height -lt 380) { return }
        $sp.SplitterDistance = [int]($sp.Height * 0.42)
        $sp.Panel1MinSize = 150
        $sp.Panel2MinSize = 200
        $script:PesState.SplitDone = $true
    } catch { }
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
        Initialize-PesSplit
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
    $o.Echo = New-PesCheck -Text 'Echo-Sperre: Mikrofon stumm, solange der Partner spricht (für Lautsprecher)' -X 16 -Y $y -W 570 -Parent $f; $o.Echo.Checked = [bool]$s.EchoGate; $y += 34

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
