<#
.SYNOPSIS
    Pruefwerkzeug - erstellt einen verstaendlichen Pruefbericht fuer .ps1-Skripte und fertige .exe-Dateien.
.DESCRIPTION
    Fuer alle, die ein Tool von Alexander (Project Earth LAN Manager, PEL-Rendezvous, Konsolen-Waechter,
    Heizungs-Planer, Oelbrenner-Einstellhilfe, EXE-Builder ...) pruefen wollen, ohne Code lesen zu koennen.
    Was es macht:
      - Pruefbericht fuer .ps1: Syntax (PowerShell-Parser), SHA256, Signatur, Zeichenkodierung,
        Kopierfehler-Zeichen, und in Klartext: wo das Skript ins Netzwerk geht, welche Ports und
        Internet-Adressen vorkommen, wo Firewall, Registry, Autostart, Fremdprogramme und Loeschbefehle
        stehen - jeweils mit Zeilennummern zum Nachlesen.
      - Pruefbericht fuer .exe: SHA256, Abgleich mit der .sha256.txt daneben, Signatur, Versionsangaben,
        und ob die passende .ps1 daneben liegt.
      - Sandbox-Datei (.wsb) erstellen: der Ordner wird schreibgeschuetzt in die Windows-Sandbox eingebunden.
      - "Alles entfernen": zeigt, was die Tools auf dem PC angelegt haben (Ordner, Firewall-Regeln
        "Project Earth ...", geplante Aufgaben "Project Earth ...") und entfernt nur das Angehakte.
    Was es NICHT macht:
      - Die gepruefte Datei wird NIE ausgefuehrt, nur gelesen.
      - Kein Netzwerkzugriff, kein Selbst-Update, es wird nichts hochgeladen.
      - Der Bericht ist eine statische Pruefung und kein Virenscanner. Er zeigt, was im Code steht.
    Daten:
      - %LOCALAPPDATA%\Pruefwerkzeug (settings.json, Pruefwerkzeug.log)
.PARAMETER Entfernen
    Oeffnet direkt den Dialog "Alles entfernen" (wird mit Admin-Rechten neu gestartet).
.PARAMETER Relaunched
    Intern: markiert den Neustart (STA / Windows PowerShell 5.1 / Admin).
.PARAMETER AppDataPfad
    Intern: %APPDATA% des Benutzers, der "Alles entfernen" gestartet hat.
.PARAMETER LocalPfad
    Intern: %LOCALAPPDATA% des Benutzers, der "Alles entfernen" gestartet hat.
# Version: 2.0.0
    Autor: Alexander Meiss
    Start: Rechtsklick -> "Mit PowerShell ausfuehren"
#>
#Requires -Version 5.1
param(
    [switch]$Entfernen,
    [switch]$Relaunched,
    [string]$AppDataPfad = '',
    [string]$LocalPfad = ''
)

# ====================================================================================================
# 3. START-ABSICHERUNG (STA, Windows PowerShell 5.1, .ps1 vs .exe, kein Konsolenfenster)
# ====================================================================================================
# Bewusst KEINE Admin-Anforderung fuer das Pruefen: Lesen braucht keine Sonderrechte.
# Nur "Alles entfernen" startet das Werkzeug sichtbar angekuendigt mit Admin-Rechten neu.
$script:IsCompiledExe = -not ($PSCommandPath -and $PSCommandPath -like '*.ps1')
if ($script:IsCompiledExe) {
    try { $script:SelfPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName } catch { $script:SelfPath = $null }
} else {
    $script:SelfPath = $PSCommandPath
}

if (-not $script:IsCompiledExe -and -not $Relaunched) {
    $pwNeustart = $false
    if ($PSVersionTable.PSEdition -eq 'Core') { $pwNeustart = $true }
    if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { $pwNeustart = $true }
    if ($pwNeustart) {
        $pwPsExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $pwArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', ('"{0}"' -f $PSCommandPath), '-Relaunched')
        if ($Entfernen) { $pwArgs += '-Entfernen' }
        Start-Process -FilePath $pwPsExe -ArgumentList $pwArgs -WindowStyle Hidden
        return
    }
}

# Eigenes Konsolenfenster sofort ausblenden (immer aktiv, kein Schalter).
try {
    if (-not ('PwKonsole' -as [type])) {
        Add-Type -Namespace '' -Name 'PwKonsole' -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
'@
    }
    $pwFenster = [PwKonsole]::GetConsoleWindow()
    if ($pwFenster -ne [System.IntPtr]::Zero) { [void][PwKonsole]::ShowWindow($pwFenster, 0) }
} catch { }

# ====================================================================================================
# 4. ASSEMBLIES
# ====================================================================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ====================================================================================================
# 5. KONFIGURATION
# ====================================================================================================
$script:PwTitel    = 'Pruefwerkzeug'
$script:PwVersion  = '2.0.0'
$script:PwDatenDir = Join-Path $env:LOCALAPPDATA 'Pruefwerkzeug'
$script:PwSettingsFile = Join-Path $script:PwDatenDir 'settings.json'
$script:PwLogFile  = Join-Path $script:PwDatenDir 'Pruefwerkzeug.log'
$script:PwSettings = @{ LetzterOrdner = '' }
$script:PwDateien  = New-Object System.Collections.Generic.List[string]
$script:PwBericht  = New-Object System.Collections.Generic.List[object]
$script:PwWorker   = $null

$script:PwFarbe = @{
    Fenster = [System.Drawing.Color]::FromArgb(25, 25, 25)
    Eingabe = [System.Drawing.Color]::FromArgb(15, 15, 15)
    Knopf   = [System.Drawing.Color]::FromArgb(45, 45, 45)
    Rahmen  = [System.Drawing.Color]::FromArgb(70, 70, 70)
    Akzent  = [System.Drawing.Color]::FromArgb(0, 120, 215)
    Gefahr  = [System.Drawing.Color]::FromArgb(160, 50, 40)
    OK      = [System.Drawing.Color]::FromArgb(90, 210, 130)
    Warnung = [System.Drawing.Color]::FromArgb(255, 180, 60)
    Fehler  = [System.Drawing.Color]::FromArgb(255, 110, 100)
    Detail  = [System.Drawing.Color]::FromArgb(170, 178, 190)
}
$script:PwFont     = New-Object System.Drawing.Font('Segoe UI', 9.5)
$script:PwFontFett = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$script:PwFontLog  = New-Object System.Drawing.Font('Consolas', 9)
$script:PwFontLogFett = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold)

# ====================================================================================================
# 6. HILFSFUNKTIONEN
# ====================================================================================================
function Write-PwLog {
    # Fehlerprotokoll mit Rotation bei 1 MB. Darf nie abstuerzen.
    param([string]$Message, [string]$Level = 'INFO')
    try {
        if (-not (Test-Path -LiteralPath $script:PwDatenDir)) { [void](New-Item -ItemType Directory -Path $script:PwDatenDir -Force) }
        if (Test-Path -LiteralPath $script:PwLogFile) {
            if ((Get-Item -LiteralPath $script:PwLogFile).Length -gt 1MB) {
                Move-Item -LiteralPath $script:PwLogFile -Destination ($script:PwLogFile + '.1') -Force
            }
        }
        $line = "{0} [{1}] {2}`r`n" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
        [System.IO.File]::AppendAllText($script:PwLogFile, $line, [System.Text.Encoding]::UTF8)
    } catch { }
}

function Write-PwTextAtomic {
    # Atomar schreiben: erst Temp-Datei, dann ersetzen. So bleibt nie eine halbe Datei zurueck.
    param([string]$Path, [string]$Text, [bool]$MitBom = $false)
    $tmp = "$Path.tmp"
    [System.IO.File]::WriteAllText($tmp, $Text, (New-Object System.Text.UTF8Encoding($MitBom)))
    # [NullString]::Value statt $null - sonst lehnt File.Replace den Sicherungspfad ab
    if ([System.IO.File]::Exists($Path)) { [System.IO.File]::Replace($tmp, $Path, [NullString]::Value) }
    else { [System.IO.File]::Move($tmp, $Path) }
}

function Read-PwSettings {
    try {
        if (Test-Path -LiteralPath $script:PwSettingsFile) {
            $json = Get-Content -LiteralPath $script:PwSettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($json.LetzterOrdner -is [string]) { $script:PwSettings.LetzterOrdner = $json.LetzterOrdner }
        }
    } catch { Write-PwLog ('Einstellungen nicht lesbar: ' + $_.Exception.Message) 'WARN' }
}

function Save-PwSettings {
    try {
        if (-not (Test-Path -LiteralPath $script:PwDatenDir)) { [void](New-Item -ItemType Directory -Path $script:PwDatenDir -Force) }
        Write-PwTextAtomic -Path $script:PwSettingsFile -Text ($script:PwSettings | ConvertTo-Json)
    } catch { Write-PwLog ('Einstellungen nicht speicherbar: ' + $_.Exception.Message) 'WARN' }
}

function Show-PwInfo {
    param([string]$Text, [string]$Symbol = 'Information')
    [void][System.Windows.Forms.MessageBox]::Show($Text, $script:PwTitel, 'OK', $Symbol)
}

function Show-PwFrage {
    param([string]$Text)
    $r = [System.Windows.Forms.MessageBox]::Show($Text, $script:PwTitel, 'YesNo', 'Warning')
    return ($r -eq [System.Windows.Forms.DialogResult]::Yes)
}

function New-PwButton {
    param($Parent, [string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H, [string]$Art = 'Normal')
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Location = New-Object System.Drawing.Point($X, $Y)
    $b.Size = New-Object System.Drawing.Size($W, $H)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderColor = $script:PwFarbe.Rahmen
    $b.ForeColor = [System.Drawing.Color]::White
    $b.Font = $script:PwFont
    if ($Art -eq 'Akzent') { $b.BackColor = $script:PwFarbe.Akzent }
    elseif ($Art -eq 'Gefahr') { $b.BackColor = $script:PwFarbe.Gefahr }
    else { $b.BackColor = $script:PwFarbe.Knopf }
    $Parent.Controls.Add($b)
    return $b
}

function New-PwLabel {
    param($Parent, [string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Location = New-Object System.Drawing.Point($X, $Y)
    $l.Size = New-Object System.Drawing.Size($W, $H)
    $l.ForeColor = [System.Drawing.Color]::White
    $l.Font = $script:PwFont
    $Parent.Controls.Add($l)
    return $l
}

function New-PwForm {
    param([string]$Text, [int]$W, [int]$H)
    $f = New-Object System.Windows.Forms.Form
    $f.Text = $Text
    $f.ClientSize = New-Object System.Drawing.Size($W, $H)
    $f.StartPosition = 'CenterScreen'
    $f.BackColor = $script:PwFarbe.Fenster
    $f.ForeColor = [System.Drawing.Color]::White
    $f.Font = $script:PwFont
    return $f
}

# ====================================================================================================
# 7. PRUEF-LOGIK (laeuft im Hintergrund-Runspace; liest nur, fuehrt nichts aus)
# ====================================================================================================
# WICHTIG: Diese Funktionen werden in einen eigenen Runspace uebernommen und duerfen deshalb
# keine $script:-Variablen und keine GUI-Elemente benutzen.

function Get-PwKategorien {
    # Reihenfolge = Reihenfolge im Bericht. Art 'Warnung' = bitte genauer ansehen, 'Detail' = normale Technik.
    return @(
        @{ Name = 'Auffaellige Befehle (Code nachladen/verschleiern, Virenschutz aendern)'; Art = 'Warnung'
           Muster = 'Invoke-Expression|\biex\b|-EncodedCommand|DownloadString|DownloadFile|Add-MpPreference|Set-MpPreference|DisableRealtimeMonitoring|bitsadmin|certutil\S*\s+-decode' },
        @{ Name = 'Netzwerk (Verbindungen, Server, Downloads)'; Art = 'Detail'
           Muster = 'UdpClient|TcpListener|TcpClient|HttpListener|WebClient|HttpWebRequest|Invoke-WebRequest|Invoke-RestMethod|System\.Net\.Sockets' },
        @{ Name = 'Firewall-Regeln'; Art = 'Detail'
           Muster = 'New-NetFirewallRule|Remove-NetFirewallRule|Set-NetFirewallRule|netsh\S*\s+advfirewall' },
        @{ Name = 'Registry-Aenderungen'; Art = 'Detail'
           Muster = '(New|Set|Remove)-Item(Property)?\b.*(HKLM|HKCU|HKCR):|Registry::|\breg(\.exe)?\s+(add|delete)\b' },
        @{ Name = 'Autostart und geplante Aufgaben'; Art = 'Detail'
           Muster = 'Register-ScheduledTask|Unregister-ScheduledTask|schtasks|CurrentVersion\\Run' },
        @{ Name = 'Start anderer Programme'; Art = 'Detail'
           Muster = 'Start-Process|ProcessStartInfo|Process\]::Start' },
        @{ Name = 'Admin-Rechte'; Art = 'Detail'
           Muster = '-Verb\s+RunAs|WindowsBuiltInRole|RequireAdministrator|#Requires\s+-RunAsAdministrator' },
        @{ Name = 'Loeschbefehle'; Art = 'Detail'
           Muster = 'Remove-Item|\.IO\.(File|Directory)\]::Delete|MoveFileEx' },
        # Base64 allein ist normal (Einladungscodes, Schluessel) und deshalb bewusst keine Warnung.
        @{ Name = 'Base64-Daten (z. B. Einladungscodes, Schluessel)'; Art = 'Detail'
           Muster = 'FromBase64String' },
        @{ Name = 'Passwoerter/Schluessel (Verschluesselung)'; Art = 'Detail'
           Muster = 'ProtectedData|ConvertFrom-SecureString|ConvertTo-SecureString|HMACSHA256|RSACryptoServiceProvider' }
    )
}

function Get-PwSignaturZeilen {
    # Signatur einer Datei in Klartext. Get-AuthenticodeSignature ist ein Cmdlet (kein Fremdprozess).
    param([string]$Pfad)
    $z = New-Object System.Collections.Generic.List[object]
    try {
        $sig = Get-AuthenticodeSignature -LiteralPath $Pfad -ErrorAction Stop
        $wer = ''
        if ($sig.SignerCertificate) { $wer = $sig.SignerCertificate.Subject }
        $status = [string]$sig.Status
        if ($status -eq 'Valid') {
            $z.Add([pscustomobject]@{ Art = 'OK'; Text = 'Signatur: gueltig und auf diesem PC vertrauenswuerdig. Herausgeber: ' + $wer })
        } elseif ($status -eq 'NotSigned') {
            $z.Add([pscustomobject]@{ Art = 'Warnung'; Text = 'Signatur: keine. Die Datei ist nicht signiert (Herkunft ueber SHA256 pruefen).' })
        } elseif ($status -eq 'HashMismatch') {
            $z.Add([pscustomobject]@{ Art = 'Fehler'; Text = 'Signatur: UNGUELTIG. Die Datei wurde NACH dem Signieren veraendert! Herausgeber laut Signatur: ' + $wer })
        } else {
            $z.Add([pscustomobject]@{ Art = 'Warnung'; Text = 'Signatur: vorhanden, aber dieser PC vertraut dem Zertifikat nicht (' + $status + '). Bei selbstsignierten Zertifikaten normal. Herausgeber: ' + $wer })
        }
        if ($sig.TimeStamperCertificate) {
            $z.Add([pscustomobject]@{ Art = 'Detail'; Text = '  Zeitstempel vorhanden (' + $sig.TimeStamperCertificate.Subject + ')' })
        } elseif ($status -ne 'NotSigned') {
            $z.Add([pscustomobject]@{ Art = 'Detail'; Text = '  Kein Zeitstempel in der Signatur.' })
        }
    } catch {
        $z.Add([pscustomobject]@{ Art = 'Warnung'; Text = 'Signatur: konnte nicht gelesen werden (' + $_.Exception.Message + ')' })
    }
    return $z
}

function Get-PwSha256 {
    param([string]$Pfad)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $fs = $null
    try {
        $fs = [System.IO.File]::OpenRead($Pfad)
        return ([System.BitConverter]::ToString($sha.ComputeHash($fs)) -replace '-', '')
    } finally {
        if ($fs) { $fs.Dispose() }
        $sha.Dispose()
    }
}

function Get-PwSkriptBericht {
    # Statische Pruefung einer .ps1. Die Datei wird gelesen und vom Parser zerlegt, aber NIE ausgefuehrt.
    param([string]$Pfad)
    $out = New-Object System.Collections.Generic.List[object]
    $name = [System.IO.Path]::GetFileName($Pfad)
    $out.Add([pscustomobject]@{ Art = 'Titel'; Text = 'SKRIPT: ' + $name })
    $out.Add([pscustomobject]@{ Art = 'Detail'; Text = 'Pfad: ' + $Pfad })

    $bytes = [System.IO.File]::ReadAllBytes($Pfad)
    $hatBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $nichtAscii = $false
    foreach ($b in $bytes) { if ($b -gt 127) { $nichtAscii = $true; break } }
    $text = $null
    if ($hatBom) {
        $text = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    } else {
        try { $text = (New-Object System.Text.UTF8Encoding($false, $true)).GetString($bytes) }
        catch { $text = [System.Text.Encoding]::Default.GetString($bytes) }
    }
    $zeilen = $text -split "`r?`n"
    $out.Add([pscustomobject]@{ Art = 'Detail'; Text = ('Groesse: {0:N0} Bytes, {1:N0} Zeilen' -f $bytes.Length, $zeilen.Count) })
    $out.Add([pscustomobject]@{ Art = 'Info'; Text = 'SHA256: ' + (Get-PwSha256 $Pfad) })

    # --- Kopfangaben
    $m = [regex]::Match($text, '(?m)^\s*#\s*Version:\s*(\S+)')
    if ($m.Success) { $out.Add([pscustomobject]@{ Art = 'Detail'; Text = 'Version laut Kopfblock: ' + $m.Groups[1].Value }) }
    $m = [regex]::Match($text, '(?m)^\s*\$script:\w*Version\s*=\s*["'']([^"'']+)["'']')
    if ($m.Success) { $out.Add([pscustomobject]@{ Art = 'Detail'; Text = 'Version laut Variable: ' + $m.Groups[1].Value }) }
    $m = [regex]::Match($text, '(?s)\.SYNOPSIS\s*\r?\n\s*([^\r\n]+)')
    if ($m.Success) { $out.Add([pscustomobject]@{ Art = 'Detail'; Text = 'Beschreibung: ' + $m.Groups[1].Value.Trim() }) }

    # --- Signatur
    foreach ($z in (Get-PwSignaturZeilen $Pfad)) { $out.Add($z) }

    # --- Kodierung und Kopierfehler
    if ($hatBom) { $out.Add([pscustomobject]@{ Art = 'OK'; Text = 'Kodierung: UTF-8 mit BOM.' }) }
    elseif (-not $nichtAscii) { $out.Add([pscustomobject]@{ Art = 'OK'; Text = 'Kodierung: reines ASCII.' }) }
    else { $out.Add([pscustomobject]@{ Art = 'Warnung'; Text = 'Kodierung: Sonderzeichen ohne BOM. Windows PowerShell 5.1 zeigt Umlaute dann falsch an.' }) }
    $kopier = @{ 0x201C = 'typografisches Anfuehrungszeichen'; 0x201D = 'typografisches Anfuehrungszeichen'; 0x201E = 'typografisches Anfuehrungszeichen'
                 0x2018 = 'typografischer Apostroph'; 0x2019 = 'typografischer Apostroph'; 0x2013 = 'Halbgeviertstrich'; 0x2014 = 'Geviertstrich'
                 0x00A0 = 'geschuetztes Leerzeichen'; 0x200B = 'unsichtbares Leerzeichen' }
    $kopierFunde = 0
    for ($i = 0; $i -lt $zeilen.Count; $i++) {
        foreach ($code in $kopier.Keys) {
            if ($zeilen[$i].IndexOf([char]$code) -ge 0) {
                $kopierFunde++
                if ($kopierFunde -le 10) { $out.Add([pscustomobject]@{ Art = 'Warnung'; Text = ('Kopierfehler-Zeichen in Zeile {0}: {1}' -f ($i + 1), $kopier[$code]) }) }
            }
        }
    }
    if ($kopierFunde -eq 0) { $out.Add([pscustomobject]@{ Art = 'OK'; Text = 'Kopierfehler-Zeichen: keine gefunden.' }) }
    elseif ($kopierFunde -gt 10) { $out.Add([pscustomobject]@{ Art = 'Warnung'; Text = ('... insgesamt {0} Stellen mit Kopierfehler-Zeichen.' -f $kopierFunde) }) }

    # --- Syntax (Parser zerlegt nur, fuehrt nichts aus)
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        $out.Add([pscustomobject]@{ Art = 'Fehler'; Text = ('Syntax: {0} Fehler gefunden.' -f $errors.Count) })
        $n = 0
        foreach ($e in $errors) {
            $n++
            if ($n -gt 15) { break }
            $out.Add([pscustomobject]@{ Art = 'Fehler'; Text = ('  Zeile {0}, Spalte {1}: {2}' -f $e.Extent.StartLineNumber, $e.Extent.StartColumnNumber, $e.Message) })
        }
    } else {
        $out.Add([pscustomobject]@{ Art = 'OK'; Text = 'Syntax: fehlerfrei (PowerShell-Parser).' })
    }
    $funktionen = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    $out.Add([pscustomobject]@{ Art = 'Detail'; Text = ('Aufbau: {0} Funktionen, {1} eingebettete Add-Type-Aufrufe (C#/Windows-API).' -f $funktionen.Count, ([regex]::Matches($text, '(?im)^\s*[^#\r\n]*\bAdd-Type\b')).Count) })

    # --- Kommentarzeilen ermitteln, damit Erklaerungen im Kommentar nicht als Fund zaehlen
    $istKommentar = New-Object 'bool[]' ($zeilen.Count + 2)
    foreach ($t in $tokens) {
        if ($t.Kind -ne [System.Management.Automation.Language.TokenKind]::Comment) { continue }
        $von = $t.Extent.StartLineNumber; $bis = $t.Extent.EndLineNumber
        if ($bis -gt $von) {
            for ($k = $von; $k -le $bis -and $k -le $zeilen.Count; $k++) { $istKommentar[$k] = $true }
        } elseif ($von -le $zeilen.Count -and $zeilen[$von - 1].TrimStart().StartsWith('#')) {
            $istKommentar[$von] = $true
        }
    }

    # --- Kategorien in Klartext mit Zeilennummern
    $out.Add([pscustomobject]@{ Art = 'Titel'; Text = 'Was steht im Code? (Zeilennummern zum Nachlesen)' })
    $opt = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    $auffaellig = 0
    foreach ($kat in (Get-PwKategorien)) {
        $rx = New-Object System.Text.RegularExpressions.Regex($kat.Muster, $opt)
        $treffer = New-Object System.Collections.Generic.List[int]
        for ($i = 0; $i -lt $zeilen.Count; $i++) {
            if ($istKommentar[$i + 1]) { continue }
            if ($rx.IsMatch($zeilen[$i])) { $treffer.Add($i + 1) }
        }
        if ($treffer.Count -eq 0) {
            $out.Add([pscustomobject]@{ Art = 'OK'; Text = $kat.Name + ': nichts gefunden.' })
            continue
        }
        if ($kat.Art -eq 'Warnung') { $auffaellig += $treffer.Count }
        $erste = @($treffer | Select-Object -First 12) -join ', '
        $mehr = ''
        if ($treffer.Count -gt 12) { $mehr = ' ...' }
        $out.Add([pscustomobject]@{ Art = $kat.Art; Text = ('{0}: {1} Stellen. Zeilen: {2}{3}' -f $kat.Name, $treffer.Count, $erste, $mehr) })
        if ($kat.Art -eq 'Warnung') {
            foreach ($nr in ($treffer | Select-Object -First 8)) {
                $z = $zeilen[$nr - 1].Trim()
                if ($z.Length -gt 150) { $z = $z.Substring(0, 150) + ' ...' }
                $out.Add([pscustomobject]@{ Art = 'Detail'; Text = ('    {0}: {1}' -f $nr, $z) })
            }
        }
    }

    # --- Ports
    $ports = New-Object 'System.Collections.Generic.SortedSet[int]'
    $rxPort = New-Object System.Text.RegularExpressions.Regex('port\w*["'']?\s*[=:,]\s*["'']?(\d{2,5})\b|(?:UdpClient|TcpListener|IPEndPoint|TcpClient)\s*\(?[^)\r\n]*?\b(\d{4,5})\b|-(?:Local|Remote)Port\s+(\d{2,5})', $opt)
    for ($i = 0; $i -lt $zeilen.Count; $i++) {
        if ($istKommentar[$i + 1]) { continue }
        foreach ($pm in $rxPort.Matches($zeilen[$i])) {
            foreach ($g in 1..3) {
                if ($pm.Groups[$g].Success) {
                    $p = [int]$pm.Groups[$g].Value
                    if ($p -ge 20 -and $p -le 65535) { [void]$ports.Add($p) }
                }
            }
        }
    }
    if ($ports.Count -gt 0) { $out.Add([pscustomobject]@{ Art = 'Detail'; Text = 'Zahlen, die wie Ports aussehen (automatisch erkannt, Fehltreffer moeglich): ' + (@($ports) -join ', ') }) }
    else { $out.Add([pscustomobject]@{ Art = 'OK'; Text = 'Fest genannte Ports: keine.' }) }

    # --- Internet-Adressen (nur die Rechnernamen)
    $hosts = New-Object 'System.Collections.Generic.SortedSet[string]'
    foreach ($um in [regex]::Matches($text, 'https?://([A-Za-z0-9.-]+\.[A-Za-z]{2,})')) { [void]$hosts.Add($um.Groups[1].Value.ToLower()) }
    if ($hosts.Count -gt 0) {
        $out.Add([pscustomobject]@{ Art = 'Detail'; Text = ('Internet-Adressen im Text ({0}): {1}' -f $hosts.Count, (@($hosts | Select-Object -First 40) -join ', ')) })
    } else {
        $out.Add([pscustomobject]@{ Art = 'OK'; Text = 'Internet-Adressen im Text: keine.' })
    }

    # --- Firewall-Regelnamen
    $regeln = New-Object 'System.Collections.Generic.SortedSet[string]'
    foreach ($fm in [regex]::Matches($text, '["''](Project Earth[^"''\r\n]{0,80})["'']')) {
        $zeilenAnfang = $text.LastIndexOf("`n", $fm.Index) + 1
        $zeilenEnde = $text.IndexOf("`n", $fm.Index)
        if ($zeilenEnde -lt 0) { $zeilenEnde = $text.Length }
        if ($text.Substring($zeilenAnfang, $zeilenEnde - $zeilenAnfang) -match 'FirewallRule|DisplayName') { [void]$regeln.Add($fm.Groups[1].Value) }
    }
    if ($regeln.Count -gt 0) { $out.Add([pscustomobject]@{ Art = 'Detail'; Text = 'Namen von Firewall-Regeln: ' + (@($regeln) -join ' | ') }) }

    # --- Fazit
    $out.Add([pscustomobject]@{ Art = 'Titel'; Text = 'Fazit fuer ' + $name })
    if ($errors -and $errors.Count -gt 0) { $out.Add([pscustomobject]@{ Art = 'Fehler'; Text = 'Das Skript hat Syntaxfehler und laeuft so nicht.' }) }
    if ($auffaellig -gt 0) {
        $out.Add([pscustomobject]@{ Art = 'Warnung'; Text = ('{0} auffaellige Stellen. Das ist kein Beweis fuer Schadcode - bitte die genannten Zeilen ansehen oder jemanden fragen, der Code lesen kann.' -f $auffaellig) })
    } else {
        $out.Add([pscustomobject]@{ Art = 'OK'; Text = 'Keine auffaelligen Befehle (Code nachladen, verschleiern, Virenschutz aendern) gefunden.' })
    }
    $out.Add([pscustomobject]@{ Art = 'Detail'; Text = 'Hinweis: statische Pruefung. Sie zeigt, was im Code steht, ersetzt aber keinen Virenscanner.' })
    return $out
}

function Get-PwExeBericht {
    # Pruefung einer fertigen .exe: Hash, Signatur, Versionsangaben, Begleitdateien. Nichts wird gestartet.
    param([string]$Pfad)
    $out = New-Object System.Collections.Generic.List[object]
    $name = [System.IO.Path]::GetFileName($Pfad)
    $ordner = [System.IO.Path]::GetDirectoryName($Pfad)
    $out.Add([pscustomobject]@{ Art = 'Titel'; Text = 'PROGRAMM: ' + $name })
    $out.Add([pscustomobject]@{ Art = 'Detail'; Text = 'Pfad: ' + $Pfad })
    $out.Add([pscustomobject]@{ Art = 'Detail'; Text = ('Groesse: {0:N0} Bytes' -f (New-Object System.IO.FileInfo($Pfad)).Length) })
    $hash = Get-PwSha256 $Pfad
    $out.Add([pscustomobject]@{ Art = 'Info'; Text = 'SHA256: ' + $hash })

    # --- Abgleich mit der veroeffentlichten Pruefsumme
    $hashDatei = $Pfad + '.sha256.txt'
    if (Test-Path -LiteralPath $hashDatei) {
        $soll = [regex]::Match([System.IO.File]::ReadAllText($hashDatei), '[0-9A-Fa-f]{64}')
        if (-not $soll.Success) {
            $out.Add([pscustomobject]@{ Art = 'Warnung'; Text = 'Pruefsummen-Datei gefunden, enthaelt aber keinen SHA256-Wert.' })
        } elseif ($soll.Value.ToUpper() -eq $hash.ToUpper()) {
            $out.Add([pscustomobject]@{ Art = 'OK'; Text = 'Pruefsumme stimmt mit ' + [System.IO.Path]::GetFileName($hashDatei) + ' ueberein.' })
        } else {
            $out.Add([pscustomobject]@{ Art = 'Fehler'; Text = 'Pruefsumme stimmt NICHT mit ' + [System.IO.Path]::GetFileName($hashDatei) + ' ueberein. Die .exe ist nicht die veroeffentlichte Datei!' })
        }
    } else {
        $out.Add([pscustomobject]@{ Art = 'Warnung'; Text = 'Keine Datei "' + $name + '.sha256.txt" daneben. Den SHA256-Wert oben mit dem auf GitHub vergleichen.' })
    }

    foreach ($z in (Get-PwSignaturZeilen $Pfad)) { $out.Add($z) }

    try {
        $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Pfad)
        $out.Add([pscustomobject]@{ Art = 'Detail'; Text = ('Angaben in der Datei: Beschreibung "{0}", Version "{1}", Firma "{2}"' -f $vi.FileDescription, $vi.FileVersion, $vi.CompanyName) })
    } catch { }

    # --- Liegt der Quelltext daneben?
    $skripte = @(Get-ChildItem -LiteralPath $ordner -Filter '*.ps1' -File -ErrorAction SilentlyContinue)
    if ($skripte.Count -gt 0) {
        $out.Add([pscustomobject]@{ Art = 'OK'; Text = 'Quelltext im selben Ordner: ' + (@($skripte | ForEach-Object { $_.Name }) -join ', ') })
        $out.Add([pscustomobject]@{ Art = 'Detail'; Text = '  Die .ps1 ebenfalls pruefen lassen - dort steht, was das Programm tut.' })
    } else {
        $out.Add([pscustomobject]@{ Art = 'Warnung'; Text = 'Keine .ps1 im selben Ordner. Zu jeder .exe sollte der Quelltext daneben liegen.' })
    }
    $out.Add([pscustomobject]@{ Art = 'Detail'; Text = 'Hinweis: Der Inhalt der .exe wird nicht zerlegt. Ob sie genau aus der .ps1 gebaut wurde, laesst sich nur ueber die veroeffentlichte Pruefsumme oder durch eigenes Bauen pruefen.' })
    return $out
}

function Invoke-PwPruefung {
    # Einstieg im Hintergrund-Runspace: prueft alle Dateien nacheinander.
    param([string[]]$Dateien, $Sync)
    $alle = New-Object System.Collections.Generic.List[object]
    $nr = 0
    foreach ($d in $Dateien) {
        $nr++
        $Sync.Status = ('Pruefe {0} von {1}: {2}' -f $nr, $Dateien.Count, [System.IO.Path]::GetFileName($d))
        try {
            if (-not (Test-Path -LiteralPath $d)) { throw 'Datei nicht gefunden.' }
            if ($d -like '*.exe') { $teil = Get-PwExeBericht $d } else { $teil = Get-PwSkriptBericht $d }
            foreach ($z in $teil) { $alle.Add($z) }
        } catch {
            $alle.Add([pscustomobject]@{ Art = 'Titel'; Text = 'DATEI: ' + [System.IO.Path]::GetFileName($d) })
            $alle.Add([pscustomobject]@{ Art = 'Fehler'; Text = 'Konnte nicht geprueft werden: ' + $_.Exception.Message })
        }
        $alle.Add([pscustomobject]@{ Art = 'Leer'; Text = '' })
    }
    return $alle
}

function Start-PwPruefung {
    # Startet die Pruefung in einem Runspace (kein Start-Job: der wuerde einen eigenen powershell.exe-Prozess starten).
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    foreach ($fn in 'Get-PwKategorien', 'Get-PwSignaturZeilen', 'Get-PwSha256', 'Get-PwSkriptBericht', 'Get-PwExeBericht', 'Invoke-PwPruefung') {
        $def = (Get-Item ('function:' + $fn)).Definition
        $iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry($fn, $def)))
    }
    $sync = [hashtable]::Synchronized(@{ Status = 'Pruefung startet ...' })
    $rs = [runspacefactory]::CreateRunspace($iss)
    $rs.ApartmentState = 'MTA'
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddCommand('Invoke-PwPruefung').AddParameter('Dateien', [string[]]$script:PwDateien.ToArray()).AddParameter('Sync', $sync)
    $script:PwWorker = @{ Ps = $ps; Rs = $rs; Sync = $sync; Handle = $ps.BeginInvoke() }
}

function Receive-PwPruefung {
    # Wird vom Timer aufgerufen. Liefert $true, wenn die Pruefung fertig ist und der Bericht abgeholt wurde.
    $w = $script:PwWorker
    if (-not $w) { return $false }
    $script:Ui.Status.Text = [string]$w.Sync.Status
    if (-not $w.Handle.IsCompleted) { return $false }
    try {
        $ergebnis = $w.Ps.EndInvoke($w.Handle)
        $script:PwBericht.Clear()
        $script:PwBericht.Add([pscustomobject]@{ Art = 'Detail'; Text = ('Pruefbericht vom {0} - {1} {2} auf {3}' -f (Get-Date -Format 'dd.MM.yyyy HH:mm:ss'), $script:PwTitel, $script:PwVersion, $env:COMPUTERNAME) })
        $script:PwBericht.Add([pscustomobject]@{ Art = 'Leer'; Text = '' })
        foreach ($z in $ergebnis) { $script:PwBericht.Add($z) }
        foreach ($f in $w.Ps.Streams.Error) { Write-PwLog ('Pruefung: ' + $f.ToString()) 'ERROR' }
    } catch {
        Write-PwLog ('Pruefung abgebrochen: ' + $_.Exception.Message) 'ERROR'
        $script:PwBericht.Clear()
        $script:PwBericht.Add([pscustomobject]@{ Art = 'Fehler'; Text = 'Die Pruefung ist fehlgeschlagen: ' + $_.Exception.Message })
    } finally {
        try { $w.Ps.Dispose() } catch { }
        try { $w.Rs.Dispose() } catch { }
        $script:PwWorker = $null
    }
    return $true
}

function Get-PwBerichtText {
    $sb = New-Object System.Text.StringBuilder
    foreach ($z in $script:PwBericht) {
        if ($z.Art -eq 'Titel') { [void]$sb.AppendLine(('=== {0} ===' -f $z.Text)) }
        elseif ($z.Art -eq 'Leer') { [void]$sb.AppendLine('') }
        elseif ($z.Art -eq 'Detail' -or $z.Art -eq 'Info') { [void]$sb.AppendLine('         ' + $z.Text) }
        else { [void]$sb.AppendLine(('[{0}] {1}' -f $z.Art.ToUpper().PadRight(7).Substring(0, 6), $z.Text)) }
    }
    return $sb.ToString()
}

# --- Alles entfernen -------------------------------------------------------------------------------
function Get-PwSpuren {
    # Sucht, was die Tools auf diesem PC angelegt haben. Es wird nur gesucht, nichts veraendert.
    param([string]$AppData, [string]$LocalAppData)
    $liste = New-Object System.Collections.Generic.List[object]
    $ordner = @(
        @{ Pfad = 'C:\Project-Earth-Lan'; Wozu = 'Project Earth LAN Manager (Einstellungen, Logs, Schluessel)' },
        @{ Pfad = (Join-Path $env:ProgramData 'KonsolenWaechter'); Wozu = 'Konsolen-Waechter' },
        @{ Pfad = (Join-Path $AppData 'HeizungsPlaner'); Wozu = 'Heizungs-Planer' },
        @{ Pfad = (Join-Path $LocalAppData 'OelbrennerEinstellhilfe'); Wozu = 'Oelbrenner-Einstellhilfe' },
        @{ Pfad = (Join-Path $LocalAppData 'Pruefwerkzeug'); Wozu = 'dieses Pruefwerkzeug' }
    )
    foreach ($o in $ordner) {
        if (Test-Path -LiteralPath $o.Pfad -PathType Container) {
            $liste.Add([pscustomobject]@{ Typ = 'Ordner'; Name = $o.Pfad; Anzeige = ('Ordner: {0}  ({1})' -f $o.Pfad, $o.Wozu) })
        }
    }
    try {
        foreach ($r in @(Get-NetFirewallRule -DisplayName 'Project Earth*' -ErrorAction SilentlyContinue)) {
            $liste.Add([pscustomobject]@{ Typ = 'Firewall'; Name = $r.Name; Anzeige = ('Firewall-Regel: {0}' -f $r.DisplayName) })
        }
    } catch { Write-PwLog ('Firewall-Suche: ' + $_.Exception.Message) 'WARN' }
    try {
        foreach ($t in @(Get-ScheduledTask -TaskName 'Project Earth*' -ErrorAction SilentlyContinue)) {
            $liste.Add([pscustomobject]@{ Typ = 'Aufgabe'; Name = $t.TaskName; Pfad = $t.TaskPath; Anzeige = ('Geplante Aufgabe: {0}{1}' -f $t.TaskPath, $t.TaskName) })
        }
    } catch { Write-PwLog ('Aufgaben-Suche: ' + $_.Exception.Message) 'WARN' }
    return $liste
}

function Remove-PwSpur {
    # Entfernt genau einen Eintrag. Rueckgabe: '' bei Erfolg, sonst die Fehlermeldung.
    param($Spur, [string]$SicherungsOrdner)
    try {
        if ($Spur.Typ -eq 'Ordner') {
            # Schluesseldateien (z. B. owner.key) vorher auf den Desktop sichern - die sind nicht wiederherstellbar.
            $keys = @(Get-ChildItem -LiteralPath $Spur.Name -Recurse -File -Include '*.key', '*.pfx' -ErrorAction SilentlyContinue)
            if ($keys.Count -gt 0) {
                if (-not (Test-Path -LiteralPath $SicherungsOrdner)) { [void](New-Item -ItemType Directory -Path $SicherungsOrdner -Force) }
                foreach ($k in $keys) { Copy-Item -LiteralPath $k.FullName -Destination (Join-Path $SicherungsOrdner $k.Name) -Force }
            }
            Remove-Item -LiteralPath $Spur.Name -Recurse -Force -ErrorAction Stop
        } elseif ($Spur.Typ -eq 'Firewall') {
            Remove-NetFirewallRule -Name $Spur.Name -ErrorAction Stop
        } elseif ($Spur.Typ -eq 'Aufgabe') {
            Unregister-ScheduledTask -TaskName $Spur.Name -TaskPath $Spur.Pfad -Confirm:$false -ErrorAction Stop
        }
        Write-PwLog ('Entfernt: ' + $Spur.Anzeige)
        return ''
    } catch {
        Write-PwLog ('Entfernen fehlgeschlagen: ' + $Spur.Anzeige + ' - ' + $_.Exception.Message) 'ERROR'
        return $_.Exception.Message
    }
}

# ====================================================================================================
# 8. OBERFLAECHE UND EVENT-HANDLER
# ====================================================================================================
function Add-PwDateien {
    param([string[]]$Pfade)
    foreach ($p in $Pfade) {
        if (-not $p) { continue }
        if (Test-Path -LiteralPath $p -PathType Container) {
            $gefunden = @(Get-ChildItem -LiteralPath $p -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -eq '.ps1' -or $_.Extension -eq '.exe' })
            foreach ($g in $gefunden) { if (-not $script:PwDateien.Contains($g.FullName)) { $script:PwDateien.Add($g.FullName) } }
            $script:PwSettings.LetzterOrdner = $p
        } elseif ((Test-Path -LiteralPath $p -PathType Leaf) -and ($p -like '*.ps1' -or $p -like '*.exe')) {
            if (-not $script:PwDateien.Contains($p)) { $script:PwDateien.Add($p) }
            $script:PwSettings.LetzterOrdner = [System.IO.Path]::GetDirectoryName($p)
        }
    }
    $script:Ui.Liste.BeginUpdate()
    $script:Ui.Liste.Items.Clear()
    foreach ($d in $script:PwDateien) { [void]$script:Ui.Liste.Items.Add([System.IO.Path]::GetFileName($d)) }
    $script:Ui.Liste.EndUpdate()
    $script:Ui.Status.Text = ('{0} Dateien in der Liste. "Pruefen" startet den Bericht.' -f $script:PwDateien.Count)
    Save-PwSettings
}

function Show-PwBericht {
    $box = $script:Ui.Bericht
    $box.SuspendLayout()
    $box.Clear()
    foreach ($z in $script:PwBericht) {
        $farbe = [System.Drawing.Color]::White
        $font = $script:PwFontLog
        $prefix = '   '
        if ($z.Art -eq 'Titel') { $font = $script:PwFontLogFett; $prefix = '' }
        elseif ($z.Art -eq 'OK') { $farbe = $script:PwFarbe.OK; $prefix = '[OK]      ' }
        elseif ($z.Art -eq 'Warnung') { $farbe = $script:PwFarbe.Warnung; $prefix = '[ACHTUNG] ' }
        elseif ($z.Art -eq 'Fehler') { $farbe = $script:PwFarbe.Fehler; $prefix = '[FEHLER]  ' }
        elseif ($z.Art -eq 'Detail') { $farbe = $script:PwFarbe.Detail; $prefix = '          ' }
        elseif ($z.Art -eq 'Info') { $prefix = '          ' }
        $box.SelectionStart = $box.TextLength
        $box.SelectionColor = $farbe
        $box.SelectionFont = $font
        $box.AppendText($prefix + $z.Text + "`r`n")
    }
    $box.SelectionStart = 0
    $box.ScrollToCaret()
    $box.ResumeLayout()
}

function New-PwSandboxDatei {
    # Erstellt eine .wsb-Datei: Ordner schreibgeschuetzt in die Windows-Sandbox einbinden.
    if ($script:PwDateien.Count -eq 0) { Show-PwInfo 'Bitte zuerst eine Datei oder einen Ordner waehlen. Dessen Ordner wird in die Sandbox eingebunden.'; return }
    $index = $script:Ui.Liste.SelectedIndex
    if ($index -lt 0) { $index = 0 }
    $ordner = [System.IO.Path]::GetDirectoryName($script:PwDateien[$index])
    $netz = Show-PwFrage ("Soll die Sandbox Netzwerk/Internet haben?`n`nJa: zum Testen von Netzwerk-Funktionen.`nNein: komplett abgeschottet (sicherer).")
    $netzText = 'Disable'
    if ($netz) { $netzText = 'Default' }
    $xml = @(
        '<Configuration>',
        '  <MappedFolders>',
        '    <MappedFolder>',
        ('      <HostFolder>{0}</HostFolder>' -f [System.Security.SecurityElement]::Escape($ordner)),
        '      <SandboxFolder>C:\Users\WDAGUtilityAccount\Desktop\Pruefung</SandboxFolder>',
        '      <ReadOnly>true</ReadOnly>',
        '    </MappedFolder>',
        '  </MappedFolders>',
        ('  <Networking>{0}</Networking>' -f $netzText),
        '</Configuration>'
    ) -join "`r`n"
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    try {
        $dlg.Title = 'Sandbox-Datei speichern'
        $dlg.Filter = 'Windows-Sandbox (*.wsb)|*.wsb'
        $dlg.FileName = 'Pruefung-in-Sandbox.wsb'
        $dlg.InitialDirectory = [Environment]::GetFolderPath('Desktop')
        if ($dlg.ShowDialog($script:Ui.Form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
        Write-PwTextAtomic -Path $dlg.FileName -Text $xml
        Show-PwInfo ("Gespeichert:`n{0}`n`nDoppelklick startet die Windows-Sandbox. Der Ordner`n{1}`nliegt dort schreibgeschuetzt auf dem Desktop unter `"Pruefung`".`n`nDie Windows-Sandbox gibt es nur in Windows Pro/Enterprise und muss unter `"Windows-Features`" aktiviert sein." -f $dlg.FileName, $ordner)
    } catch {
        Write-PwLog ('Sandbox-Datei: ' + $_.Exception.Message) 'ERROR'
        Show-PwInfo ('Die Sandbox-Datei konnte nicht gespeichert werden: ' + $_.Exception.Message) 'Error'
    } finally { $dlg.Dispose() }
}

function Save-PwBericht {
    if ($script:PwBericht.Count -eq 0) { Show-PwInfo 'Es gibt noch keinen Bericht. Bitte zuerst "Pruefen" klicken.'; return }
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    try {
        $dlg.Title = 'Pruefbericht speichern'
        $dlg.Filter = 'Textdatei (*.txt)|*.txt'
        $dlg.FileName = ('Pruefbericht_{0}.txt' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        $dlg.InitialDirectory = [Environment]::GetFolderPath('Desktop')
        if ($dlg.ShowDialog($script:Ui.Form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
        Write-PwTextAtomic -Path $dlg.FileName -Text (Get-PwBerichtText) -MitBom $true
        $script:Ui.Status.Text = 'Bericht gespeichert: ' + $dlg.FileName
    } catch {
        Write-PwLog ('Bericht speichern: ' + $_.Exception.Message) 'ERROR'
        Show-PwInfo ('Der Bericht konnte nicht gespeichert werden: ' + $_.Exception.Message) 'Error'
    } finally { $dlg.Dispose() }
}

function Start-PwEntfernenProzess {
    # "Alles entfernen" laeuft als eigener Prozess mit Admin-Rechten (Firewall/Aufgaben brauchen Admin).
    if (-not (Show-PwFrage ("`"Alles entfernen`" sucht nach Ordnern, Firewall-Regeln und geplanten Aufgaben der Tools und zeigt sie als Liste.`n`nEntfernt wird erst, was du dort anhakst und bestaetigst.`n`nDafuer sind Admin-Rechte noetig (Windows fragt gleich nach). Fortfahren?"))) { return }
    try {
        $extra = @('-Entfernen', '-Relaunched', '-AppDataPfad', ('"{0}"' -f $env:APPDATA), '-LocalPfad', ('"{0}"' -f $env:LOCALAPPDATA))
        if ($script:IsCompiledExe) {
            Start-Process -FilePath $script:SelfPath -ArgumentList $extra -Verb RunAs -WindowStyle Hidden
        } else {
            $psExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $argumente = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', ('"{0}"' -f $script:SelfPath)) + $extra
            Start-Process -FilePath $psExe -ArgumentList $argumente -Verb RunAs -WindowStyle Hidden
        }
    } catch {
        # Abgelehnte Admin-Abfrage landet hier.
        Write-PwLog ('Admin-Neustart: ' + $_.Exception.Message) 'WARN'
        $script:Ui.Status.Text = 'Admin-Rechte wurden nicht erteilt. Es wurde nichts entfernt.'
    }
}

function Show-PwEntfernen {
    # Eigenes Fenster (eigener Prozess, Admin): Liste der Spuren mit Haken, Entfernen nur nach Bestaetigung.
    $istAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $istAdmin) { Show-PwInfo 'Ohne Admin-Rechte kann nichts entfernt werden.' 'Warning'; return }
    $appData = $env:APPDATA; $localData = $env:LOCALAPPDATA
    # Uebergebene Pfade nur annehmen, wenn es echte, vorhandene Ordner sind.
    if ($AppDataPfad -and [System.IO.Path]::IsPathRooted($AppDataPfad) -and (Test-Path -LiteralPath $AppDataPfad -PathType Container)) { $appData = $AppDataPfad }
    if ($LocalPfad -and [System.IO.Path]::IsPathRooted($LocalPfad) -and (Test-Path -LiteralPath $LocalPfad -PathType Container)) { $localData = $LocalPfad }
    $spuren = Get-PwSpuren -AppData $appData -LocalAppData $localData

    $form = New-PwForm ($script:PwTitel + ' - Alles entfernen') 760 480
    $form.FormBorderStyle = 'FixedDialog'; $form.MaximizeBox = $false
    $kopf = New-PwLabel $form 'Das wurde auf diesem PC gefunden. Entfernt wird nur, was angehakt ist. Bitte vorher alle Tools beenden.' 12 10 736 22
    $kopf.Font = $script:PwFontFett
    $clb = New-Object System.Windows.Forms.CheckedListBox
    $clb.Location = New-Object System.Drawing.Point(12, 40); $clb.Size = New-Object System.Drawing.Size(736, 350)
    $clb.BackColor = $script:PwFarbe.Eingabe; $clb.ForeColor = [System.Drawing.Color]::White
    $clb.BorderStyle = 'FixedSingle'; $clb.CheckOnClick = $true; $clb.Font = $script:PwFontLog; $clb.HorizontalScrollbar = $true
    foreach ($s in $spuren) { [void]$clb.Items.Add($s.Anzeige, $false) }
    $form.Controls.Add($clb)
    $status = New-PwLabel $form '' 12 396 736 22
    if ($spuren.Count -eq 0) { $status.Text = 'Nichts gefunden - auf diesem PC liegen keine Spuren der Tools.' }
    else { $status.Text = ('{0} Eintraege gefunden. Schluesseldateien (*.key, *.pfx) werden vor dem Loeschen auf den Desktop gesichert.' -f $spuren.Count) }
    $btnAlle = New-PwButton $form 'Alle anhaken' 12 430 130 34
    $btnWeg = New-PwButton $form 'Angehaktes entfernen' 370 430 200 34 'Gefahr'
    $btnZu = New-PwButton $form 'Schliessen' 588 430 160 34

    $btnAlle.Add_Click({ for ($i = 0; $i -lt $clb.Items.Count; $i++) { $clb.SetItemChecked($i, $true) } }.GetNewClosure())
    $btnZu.Add_Click({ $form.Close() }.GetNewClosure())
    $btnWeg.Add_Click({
        $auswahl = @($clb.CheckedIndices)
        if ($auswahl.Count -eq 0) { $status.Text = 'Nichts angehakt.'; return }
        if (-not (Show-PwFrage ("{0} Eintraege werden jetzt endgueltig entfernt.`n`nDas laesst sich nicht rueckgaengig machen. Wirklich entfernen?" -f $auswahl.Count))) { return }
        $sicherung = Join-Path ([Environment]::GetFolderPath('Desktop')) ('Pruefwerkzeug-Sicherung_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
        $btnWeg.Enabled = $false
        $fehler = New-Object System.Collections.Generic.List[string]
        $erledigt = New-Object System.Collections.Generic.List[int]
        foreach ($i in $auswahl) {
            $status.Text = 'Entferne: ' + $spuren[$i].Anzeige
            [System.Windows.Forms.Application]::DoEvents()
            $meldung = Remove-PwSpur -Spur $spuren[$i] -SicherungsOrdner $sicherung
            if ($meldung) { $fehler.Add($spuren[$i].Anzeige + ' -> ' + $meldung) } else { $erledigt.Add($i) }
        }
        # Von hinten entfernen, damit die Indizes von Liste und Anzeige zusammenpassen.
        foreach ($i in ($erledigt | Sort-Object -Descending)) { $clb.Items.RemoveAt($i); $spuren.RemoveAt($i) }
        $btnWeg.Enabled = $true
        $status.Text = ('{0} entfernt, {1} fehlgeschlagen.' -f $erledigt.Count, $fehler.Count)
        if ($fehler.Count -gt 0) { Show-PwInfo ("Nicht entfernt (laeuft das Tool noch?):`n`n" + ($fehler -join "`n")) 'Warning' }
        if (Test-Path -LiteralPath $sicherung) { Show-PwInfo ("Schluesseldateien wurden gesichert nach:`n" + $sicherung) }
    }.GetNewClosure())
    [System.Windows.Forms.Application]::Run($form)
}

function Show-PwHauptfenster {
    $script:Ui = @{}
    $form = New-PwForm ($script:PwTitel + ' ' + $script:PwVersion + ' - Pruefbericht fuer .ps1 und .exe') 1100 700
    $form.MinimumSize = New-Object System.Drawing.Size(900, 520)
    $form.AllowDrop = $true
    $script:Ui.Form = $form

    $btnDatei  = New-PwButton $form 'Dateien waehlen' 12 12 140 34
    $btnOrdner = New-PwButton $form 'Ordner waehlen' 158 12 140 34
    $btnLeeren = New-PwButton $form 'Liste leeren' 304 12 110 34
    $btnPruef  = New-PwButton $form 'Pruefen' 420 12 130 34 'Akzent'
    $btnSpeich = New-PwButton $form 'Bericht speichern' 556 12 150 34
    $btnSand   = New-PwButton $form 'Sandbox-Datei' 712 12 130 34
    $btnWeg    = New-PwButton $form 'Alles entfernen' 948 12 140 34 'Gefahr'
    $btnWeg.Anchor = 'Top, Right'
    $script:Ui.Pruefen = $btnPruef

    $hinweis = New-PwLabel $form 'Dateien oder Ordner hierher ziehen. Die Dateien werden nur gelesen und nie ausgefuehrt.' 12 52 900 20
    $hinweis.ForeColor = $script:PwFarbe.Detail
    $hinweis.Font = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Italic)

    $liste = New-Object System.Windows.Forms.ListBox
    $liste.Location = New-Object System.Drawing.Point(12, 78); $liste.Size = New-Object System.Drawing.Size(286, 584)
    $liste.BackColor = $script:PwFarbe.Eingabe; $liste.ForeColor = [System.Drawing.Color]::White
    $liste.BorderStyle = 'FixedSingle'; $liste.IntegralHeight = $false; $liste.HorizontalScrollbar = $true
    $liste.Anchor = 'Top, Bottom, Left'
    $form.Controls.Add($liste)
    $script:Ui.Liste = $liste

    $box = New-Object System.Windows.Forms.RichTextBox
    $box.Location = New-Object System.Drawing.Point(304, 78); $box.Size = New-Object System.Drawing.Size(784, 584)
    $box.BackColor = $script:PwFarbe.Eingabe; $box.ForeColor = [System.Drawing.Color]::White
    $box.BorderStyle = 'None'; $box.ReadOnly = $true; $box.Font = $script:PwFontLog; $box.WordWrap = $true; $box.DetectUrls = $false
    $box.Anchor = 'Top, Bottom, Left, Right'
    $form.Controls.Add($box)
    $script:Ui.Bericht = $box

    $status = New-PwLabel $form 'Bereit. Dateien oder einen Ordner waehlen, dann "Pruefen".' 12 670 1076 22
    $status.Anchor = 'Bottom, Left, Right'
    $status.ForeColor = $script:PwFarbe.Detail
    $script:Ui.Status = $status

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 200
    $script:Ui.Timer = $timer
    $timer.Add_Tick({
        if (Receive-PwPruefung) {
            $script:Ui.Timer.Stop()
            Show-PwBericht
            $script:Ui.Pruefen.Enabled = $true
            $script:Ui.Status.Text = 'Pruefung fertig. "Bericht speichern" legt ihn als Textdatei ab.'
        }
    })

    $btnDatei.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        try {
            $dlg.Title = 'Skripte oder Programme waehlen'
            $dlg.Filter = 'Skripte und Programme (*.ps1;*.exe)|*.ps1;*.exe'
            $dlg.Multiselect = $true
            if ($script:PwSettings.LetzterOrdner -and (Test-Path -LiteralPath $script:PwSettings.LetzterOrdner)) { $dlg.InitialDirectory = $script:PwSettings.LetzterOrdner }
            if ($dlg.ShowDialog($script:Ui.Form) -eq [System.Windows.Forms.DialogResult]::OK) { Add-PwDateien $dlg.FileNames }
        } finally { $dlg.Dispose() }
    })
    $btnOrdner.Add_Click({
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        try {
            $dlg.Description = 'Ordner mit .ps1- und .exe-Dateien waehlen (alle darin werden geprueft)'
            if ($script:PwSettings.LetzterOrdner -and (Test-Path -LiteralPath $script:PwSettings.LetzterOrdner)) { $dlg.SelectedPath = $script:PwSettings.LetzterOrdner }
            if ($dlg.ShowDialog($script:Ui.Form) -eq [System.Windows.Forms.DialogResult]::OK) { Add-PwDateien @($dlg.SelectedPath) }
        } finally { $dlg.Dispose() }
    })
    $btnLeeren.Add_Click({
        $script:PwDateien.Clear()
        $script:Ui.Liste.Items.Clear()
        $script:Ui.Status.Text = 'Liste geleert.'
    })
    $btnPruef.Add_Click({
        if ($script:PwWorker) { return }
        if ($script:PwDateien.Count -eq 0) { Show-PwInfo 'Bitte zuerst Dateien oder einen Ordner waehlen.'; return }
        $script:Ui.Pruefen.Enabled = $false
        $script:Ui.Bericht.Clear()
        try {
            Start-PwPruefung
            $script:Ui.Timer.Start()
        } catch {
            Write-PwLog ('Pruefung starten: ' + $_.Exception.Message) 'ERROR'
            $script:Ui.Pruefen.Enabled = $true
            Show-PwInfo ('Die Pruefung konnte nicht gestartet werden: ' + $_.Exception.Message) 'Error'
        }
    })
    $btnSpeich.Add_Click({ Save-PwBericht })
    $btnSand.Add_Click({ New-PwSandboxDatei })
    $btnWeg.Add_Click({ Start-PwEntfernenProzess })

    $form.Add_DragEnter({
        if ($_.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) { $_.Effect = [System.Windows.Forms.DragDropEffects]::Copy }
    })
    $form.Add_DragDrop({
        $pfade = [string[]]$_.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)
        Add-PwDateien $pfade
    })
    $form.Add_FormClosing({
        $script:Ui.Timer.Stop()
        if ($script:PwWorker) {
            try { $script:PwWorker.Ps.Stop() } catch { }
            try { $script:PwWorker.Ps.Dispose() } catch { }
            try { $script:PwWorker.Rs.Dispose() } catch { }
            $script:PwWorker = $null
        }
    })

    try { [System.Windows.Forms.Application]::Run($form) }
    finally { $timer.Stop(); $timer.Dispose() }
}

# ====================================================================================================
# 9. START (Mutex, Fehlerprotokoll, Hauptfenster)
# ====================================================================================================
$pwMutex = $null
$pwNeu = $false
try {
    # Eigener Mutex-Name fuer den Entfernen-Dialog, damit er neben dem Hauptfenster laufen darf.
    $pwMutexName = 'Local\Pruefwerkzeug_Hauptfenster'
    if ($Entfernen) { $pwMutexName = 'Global\Pruefwerkzeug_Entfernen' }
    $pwMutex = New-Object System.Threading.Mutex($true, $pwMutexName, [ref]$pwNeu)
    if (-not $pwNeu) {
        Show-PwInfo 'Das Pruefwerkzeug laeuft bereits.'
    } else {
        Read-PwSettings
        if ($Entfernen) { Show-PwEntfernen } else { Show-PwHauptfenster }
    }
} catch {
    Write-PwLog ('Absturz: ' + $_.Exception.Message + ' | ' + $_.ScriptStackTrace) 'ERROR'
    Show-PwInfo ("Das Pruefwerkzeug wurde durch einen Fehler beendet:`n`n" + $_.Exception.Message + "`n`nProtokoll: " + $script:PwLogFile) 'Error'
} finally {
    if ($pwMutex) {
        if ($pwNeu) { try { $pwMutex.ReleaseMutex() } catch { } }
        $pwMutex.Dispose()
    }
}
