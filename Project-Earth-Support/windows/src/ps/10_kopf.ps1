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
