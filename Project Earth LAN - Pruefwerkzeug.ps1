<#
================================================================================
 Project Earth LAN - Pruefwerkzeug
================================================================================
 Drei Dinge, damit man diesem (oder irgendeinem anderen) PowerShell-Programm
 nicht blind vertrauen muss:

   1. PRUEFBERICHT   Liest ein PowerShell-Skript und zeigt in normaler Sprache,
                     was es am PC veraendert, welche Ports es oeffnet und wohin
                     es ins Internet geht. Funktioniert bei JEDEM Skript, nicht
                     nur bei Project Earth LAN - genau darum ist das Ergebnis
                     etwas wert.
   2. ALLES ENTFERNEN  Raeumt alles wieder weg, was Project Earth LAN angelegt
                     hat: Ordner, Firewallregeln, Autostart-Aufgabe, Dateien.
   3. SANDBOX        Erzeugt eine .wsb-Datei: damit laeuft der Manager in einer
                     abgeschotteten Wegwerf-Umgebung von Windows, ohne den
                     echten PC anzufassen.

 Dieses Werkzeug braucht KEINE Administratorrechte, um zu pruefen (Punkt 1) -
 nur zum Entfernen (Punkt 2) fragt Windows nach.

 Es aendert von sich aus nichts, ausser dem, was du in Punkt 2 ausdruecklich
 anklickst, und dem Bericht/der .wsb-Datei, die es auf den Desktop schreibt.
================================================================================
#>
[CmdletBinding()]
param(
    [string]$Datei = '',
    [ValidateSet('', '1', '2', '3')][string]$Start = ''
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$cBack   = [System.Drawing.Color]::FromArgb(25, 25, 25)
$cPanel  = [System.Drawing.Color]::FromArgb(30, 30, 30)
$cBtn    = [System.Drawing.Color]::FromArgb(45, 45, 45)
$cAccent = [System.Drawing.Color]::FromArgb(0, 120, 215)
$cList   = [System.Drawing.Color]::FromArgb(20, 20, 20)
$cWhite  = [System.Drawing.Color]::White
$cGray   = [System.Drawing.Color]::LightGray
$fMain   = New-Object System.Drawing.Font('Segoe UI', 9.5)
$fBold   = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
$fMono   = New-Object System.Drawing.Font('Consolas', 9.5)
$fHead   = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)

function Test-IstAdmin {
    try { return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
    catch { return $false }
}

# ==============================================================================
# TEIL 1: DIE PRUEFUNG (ohne Oberflaeche verwendbar, damit sie nachvollziehbar ist)
# ==============================================================================
# Regeln: Befehlsnamen/Typen -> Kategorie. Bewusst grosszuegig gefasst; lieber
# etwas zu viel anzeigen als etwas uebersehen.
$script:PwRegeln = @(
    @{ Key = 'firewall'; Titel = 'Windows-Firewall aendern';
       Erklaerung = 'Legt Regeln in der Windows-Firewall an oder entfernt sie. Noetig, damit andere Teilnehmer den PC ueber die freigegebenen Ports erreichen koennen. Achte darauf, ob die Regeln auf das lokale Netz begrenzt sind (RemoteAddress LocalSubnet).';
       Muster = '^(New|Set|Remove|Enable|Disable|Get)-NetFirewall|^netsh$' }
    @{ Key = 'autostart'; Titel = 'Automatisch mit Windows starten';
       Erklaerung = 'Richtet einen Autostart ein - als geplante Aufgabe oder ueber die Registry. Bei Schadsoftware das haeufigste Mittel, sich festzusetzen; bei normalen Programmen eine normale Funktion, solange man sie selbst einschaltet und wieder abschalten kann.';
       Muster = '^(Register|Unregister|Set|New)-ScheduledTask|^schtasks$|^New-ScheduledTask(Action|Trigger|Principal|SettingsSet)$' }
    @{ Key = 'netz'; Titel = 'Netzwerk und Internet';
       Erklaerung = 'Verbindungen ins Netz: Webseiten abrufen, Dateien laden, eigene Ports oeffnen. Die gefundenen Adressen stehen weiter unten im Bericht - dort siehst du, WOHIN es geht.';
       Muster = '^(Invoke-WebRequest|Invoke-RestMethod|Start-BitsTransfer|Test-NetConnection|Test-Connection|Resolve-DnsName)$' }
    @{ Key = 'dateien'; Titel = 'Dateien und Ordner schreiben oder loeschen';
       Erklaerung = 'Erstellt, aendert oder loescht Dateien. Wichtig ist, WO das passiert - die Pfade stehen weiter unten.';
       Muster = '^(Set-Content|Add-Content|Out-File|New-Item|Remove-Item|Copy-Item|Move-Item|Rename-Item|Set-ItemProperty|New-ItemProperty|Remove-ItemProperty|Export-Csv|Export-Clixml)$' }
    @{ Key = 'registry'; Titel = 'Registry (Windows-Einstellungen) aendern';
       Erklaerung = 'Aenderungen an den Windows-Einstellungen. Bei diesem Manager betrifft das nur den Remotedesktop-Port (Option 6).';
       Muster = '^reg$|^reg\.exe$' }
    @{ Key = 'prozess'; Titel = 'Andere Programme starten';
       Erklaerung = 'Startet andere Programme - hier z. B. den ZeroTier-Installer, Spiele, den Browser oder den Explorer.';
       Muster = '^(Start-Process|Invoke-Item|Start-Job)$' }
    @{ Key = 'dienste'; Titel = 'Windows-Dienste steuern';
       Erklaerung = 'Startet oder stoppt Systemdienste (hier: der ZeroTier-Dienst).';
       Muster = '^(Start|Stop|Restart|Set|Get)-Service$|^sc$|^sc\.exe$' }
    @{ Key = 'konten'; Titel = 'Benutzerkonten und Rechte';
       Erklaerung = 'Legt Windows-Benutzerkonten an oder aendert sie. Beim Manager passiert das nur in Option 6, wenn du ausdruecklich ein Konto fuer Remotedesktop anlegst.';
       Muster = '^(New|Set|Remove|Get|Enable|Disable)-LocalUser$|^(Add|Remove)-LocalGroupMember$|^net$|^net\.exe$' }
    @{ Key = 'admin'; Titel = 'Administratorrechte anfordern';
       Erklaerung = 'Das Programm startet sich mit erhoehten Rechten neu (UAC-Abfrage). Noetig fuer Firewall, Netzwerkadapter und Installation.';
       Muster = 'RUNAS_MARKER' }
    @{ Key = 'code'; Titel = 'Code zur Laufzeit erzeugen';
       Erklaerung = 'Uebersetzt waehrend des Laufens zusaetzlichen Programmcode (Add-Type) oder benutzt .NET-Innereien. Fuer Sprachchat, Netzwerk und Verschluesselung ueblich - aber auch ein Mittel, Code zu verstecken. Im Skript steht dieser Code im Klartext und kann gelesen werden.';
       Muster = '^(Add-Type|New-Module)$' }
    @{ Key = 'krypto'; Titel = 'Verschluesselung';
       Erklaerung = 'Verschluesselt oder signiert Daten. Hier fuer Nachrichten im Postfach und die Signatur der Status-Meldungen. Bei Erpressungssoftware wuerde man zusaetzlich sehen, dass massenhaft eigene Dateien des Nutzers gelesen und ueberschrieben werden.';
       Muster = 'KRYPTO_MARKER' }
)

# Dinge, die bei Schadsoftware typisch sind. Werden IMMER aufgefuehrt - auch wenn
# nichts gefunden wurde. "Nicht gefunden" ist die eigentlich interessante Aussage.
$script:PwWarnMuster = @(
    @{ Titel = 'Virenschutz abschalten'; Regex = 'Set-MpPreference|DisableRealtimeMonitoring|Add-MpPreference\s+-ExclusionPath|MpCmdRun'; Schwer = $true
       Hinweis = 'Programme, die den Virenschutz aushebeln oder sich selbst als Ausnahme eintragen, sind ein ernstes Warnzeichen.' }
    @{ Titel = 'Schattenkopien / Wiederherstellung loeschen'; Regex = 'vssadmin|wbadmin|bcdedit|Delete\s+Shadows'; Schwer = $true
       Hinweis = 'Typisch fuer Erpressungssoftware, damit man Daten nicht zurueckholen kann.' }
    @{ Titel = 'Befehle aus Text ausfuehren (Invoke-Expression)'; Regex = '(?<![\w-])(Invoke-Expression|iex)\s'; Schwer = $true
       Hinweis = 'Damit laesst sich beliebiger, auch nachgeladener Code ausfuehren - der haeufigste Weg, Schadcode zu verstecken.' }
    @{ Titel = 'Code aus dem Internet direkt ausfuehren'; Regex = 'DownloadString|IWR[^\n]{0,40}\|\s*iex|Invoke-WebRequest[^\n]{0,60}\|\s*iex'; Schwer = $true
       Hinweis = 'Laedt Text aus dem Netz und fuehrt ihn sofort aus. Dann entscheidet nicht das Skript, was passiert, sondern der Server.' }
    @{ Titel = 'Versteckt gestartete PowerShell / verschluesselte Befehle'; Regex = '-EncodedCommand|\s-enc\s|-w\s+hidden|-WindowStyle\s+Hidden'; Schwer = $false
       Hinweis = 'Ein verstecktes Fenster allein ist harmlos (viele Programme starten unsichtbar). Zusammen mit -EncodedCommand ist es ein Warnzeichen.' }
    @{ Titel = 'Tastatureingaben abfragen'; Regex = 'GetAsyncKeyState|SetWindowsHookEx|GetKeyboardState'; Schwer = $false
       Hinweis = 'Wird fuer Push-to-Talk im Sprachchat gebraucht (Taste gedrueckt halten). Dieselbe Funktion kann aber auch ein Keylogger nutzen - schau, ob es zu einer Funktion passt, die das Programm offen anbietet.' }
    @{ Titel = 'Bildschirmfotos aufnehmen'; Regex = 'CopyFromScreen|PrintWindow|BitBlt'; Schwer = $false
       Hinweis = 'Bildschirmaufnahme. Bei einem LAN-Tool unnoetig - wenn es vorkommt, sollte es eine sichtbare Funktion dazu geben.' }
    @{ Titel = 'Zwischenablage lesen'; Regex = 'Get-Clipboard|Clipboard\]::GetText'; Schwer = $false
       Hinweis = 'Lesen der Zwischenablage. Harmlos, wenn das Programm eine Funktion wie "IP einfuegen" hat.' }
    @{ Titel = 'Browserdaten, Passwoerter, Krypto-Geldboersen'; Regex = 'Login Data|cookies\.sqlite|Local State|wallet\.dat|Bitcoin|Exodus|NordVPN|\\Passwords'; Schwer = $true
       Hinweis = 'Zugriff auf gespeicherte Zugangsdaten oder Geldboersen. Bei einem Spiele-Tool gibt es dafuer keinen Grund.' }
    @{ Titel = 'Zugangsdaten abfragen oder auslesen'; Regex = 'Get-Credential|ConvertTo-SecureString\s+-AsPlainText|LsaEnumerate|mimikatz'; Schwer = $false
       Hinweis = 'Abfrage von Passwoertern. Achte darauf, wofuer - und ob etwas davon verschickt wird.' }
    @{ Titel = 'Daten an unbekannte Server senden'; Regex = 'Invoke-RestMethod[^\n]{0,80}-Method\s+Post|UploadString|UploadFile'; Schwer = $false
       Hinweis = 'Hochladen von Daten. Pruefe die Zieladressen weiter unten im Bericht.' }
    @{ Titel = 'Verschleierter Code'; Regex = 'FromBase64String\(\s*"[A-Za-z0-9+/=]{200,}'; Schwer = $true
       Hinweis = 'Sehr lange, unlesbare Textbloecke, die zu Code entschluesselt werden - ein klassisches Versteck.' }
)

function Get-PwAnalyse {
    param([string]$Pfad, [string]$TextDirekt = '', [string]$AnzeigeName = '')

    # Bewusst eine normale Hashtable: bei [ordered] wirft PowerShell beim
    # spaeteren Zuweisen eines Arrays "Argument types do not match".
    $ergebnis = @{
        Datei = $Pfad; Fehler = ''; Zeilen = 0; Groesse = 0; Sha = ''
        Kategorien = @(); Warnungen = @(); Adressen = @(); Ports = @(); Pfade = @(); Aufgaben = @()
        PortsWeitere = 0; ParseFehler = 0
    }
    # Zwei Betriebsarten: eine Datei vom Datentraeger oder ein Text, der vorher aus
    # einer .exe geholt wurde (dann wird er kurz als Datei in %TEMP% abgelegt,
    # damit ihn der PowerShell-Parser genauso lesen kann).
    $tempDatei = ''
    $text = ''
    if ($TextDirekt) {
        $text = $TextDirekt
        $ergebnis.Groesse = [System.Text.Encoding]::UTF8.GetByteCount($text)
        if ($AnzeigeName) { $ergebnis.Datei = $AnzeigeName }
        try {
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try { $ergebnis.Sha = ([BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text))) -replace '-', '') } finally { $sha.Dispose() }
        } catch { }
        $tempOrdner = $env:TEMP
        if (-not $tempOrdner) { $tempOrdner = [System.IO.Path]::GetTempPath() }
        $tempDatei = Join-Path $tempOrdner ('pw_pruefung_' + [Guid]::NewGuid().ToString('N').Substring(0, 8) + '.ps1')
        try { [System.IO.File]::WriteAllText($tempDatei, $text, (New-Object System.Text.UTF8Encoding($true))) }
        catch { $ergebnis.Fehler = "Zwischendatei nicht schreibbar: $($_.Exception.Message)"; return $ergebnis }
        $Pfad = $tempDatei
    } else {
        if (-not (Test-Path -LiteralPath $Pfad)) { $ergebnis.Fehler = 'Datei nicht gefunden.'; return $ergebnis }
        $fi = Get-Item -LiteralPath $Pfad
        $ergebnis.Groesse = $fi.Length
        try { $ergebnis.Sha = (Get-FileHash -LiteralPath $Pfad -Algorithm SHA256).Hash } catch { }
        try { $text = [System.IO.File]::ReadAllText($Pfad, [System.Text.Encoding]::UTF8) } catch { $ergebnis.Fehler = "Datei nicht lesbar: $($_.Exception.Message)"; return $ergebnis }
    }
    $zeilen = $text -split "`r?`n"
    $ergebnis.Zeilen = $zeilen.Count

    # ---- Befehle ueber den PowerShell-Parser einsammeln (zuverlaessiger als Textsuche)
    $treffer = @{}
    foreach ($r in $script:PwRegeln) { $treffer[$r.Key] = New-Object System.Collections.Generic.List[object] }
    $parseErrs = $null
    $ast = $null
    try { $ast = [System.Management.Automation.Language.Parser]::ParseFile($Pfad, [ref]$null, [ref]$parseErrs) } catch { }
    if ($parseErrs) { $ergebnis.ParseFehler = @($parseErrs).Count }

    if ($ast) {
        $cmds = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
        foreach ($c in $cmds) {
            $name = ''
            try { $name = [string]$c.GetCommandName() } catch { }
            if (-not $name) { continue }
            $zeile = $c.Extent.StartLineNumber
            $text1 = ($c.Extent.Text -split "`r?`n")[0]
            if ($text1.Length -gt 150) { $text1 = $text1.Substring(0, 150) + ' ...' }
            foreach ($r in $script:PwRegeln) {
                if ($r.Muster -like '*_MARKER') { continue }
                if ($name -match $r.Muster) { $treffer[$r.Key].Add([pscustomobject]@{ Zeile = $zeile; Text = $text1.Trim() }) }
            }
            # Administratorrechte: Start-Process ... -Verb RunAs
            if ($name -eq 'Start-Process' -and $c.Extent.Text -match 'RunAs') {
                $treffer['admin'].Add([pscustomobject]@{ Zeile = $zeile; Text = $text1.Trim() })
            }
        }
    }

    # ---- Textsuche fuer Dinge, die keine Befehle sind (.NET-Aufrufe, Typen) -----
    for ($i = 0; $i -lt $zeilen.Count; $i++) {
        $z = $zeilen[$i]
        if (-not $z) { continue }
        $nr = $i + 1
        $kurz = $z.Trim()
        if ($kurz.Length -gt 150) { $kurz = $kurz.Substring(0, 150) + ' ...' }
        if ($z -match 'System\.Net\.Sockets|UdpClient|TcpClient|TcpListener|WebClient|HttpListener|Socket\(') {
            $treffer['netz'].Add([pscustomobject]@{ Zeile = $nr; Text = $kurz })
        }
        if ($z -match '\[System\.IO\.File\]::(Write|Append|Delete|Move|Copy|Replace)|\[System\.IO\.Directory\]::(Create|Delete|Move)') {
            $treffer['dateien'].Add([pscustomobject]@{ Zeile = $nr; Text = $kurz })
        }
        if ($z -match 'HKLM:|HKCU:|HKEY_LOCAL_MACHINE|HKEY_CURRENT_USER|Microsoft\.Win32\.Registry') {
            $treffer['registry'].Add([pscustomobject]@{ Zeile = $nr; Text = $kurz })
        }
        if ($z -match 'RSACryptoServiceProvider|AesCryptoServiceProvider|Aes\]::Create|HMACSHA|ProtectedData|Rfc2898|SHA256\]::Create') {
            $treffer['krypto'].Add([pscustomobject]@{ Zeile = $nr; Text = $kurz })
        }
        if ($z -match 'Verb\s+RunAs|requireAdmin') {
            $treffer['admin'].Add([pscustomobject]@{ Zeile = $nr; Text = $kurz })
        }
    }

    $katListe = New-Object System.Collections.Generic.List[object]
    foreach ($r in $script:PwRegeln) {
        $liste = @($treffer[$r.Key] | Sort-Object Zeile -Unique)
        $katListe.Add([pscustomobject]@{
            Key = $r.Key; Titel = $r.Titel; Erklaerung = $r.Erklaerung
            Anzahl = $liste.Count; Fundstellen = $liste
        })
    }
    $ergebnis.Kategorien = $katListe.ToArray()

    # ---- Warnmuster --------------------------------------------------------------
    $warnListe = New-Object System.Collections.Generic.List[object]
    foreach ($w in $script:PwWarnMuster) {
        $funde = New-Object System.Collections.Generic.List[object]
        for ($i = 0; $i -lt $zeilen.Count; $i++) {
            if ($zeilen[$i] -match $w.Regex) {
                $kurz = $zeilen[$i].Trim()
                if ($kurz.Length -gt 150) { $kurz = $kurz.Substring(0, 150) + ' ...' }
                $funde.Add([pscustomobject]@{ Zeile = ($i + 1); Text = $kurz })
            }
        }
        $warnListe.Add([pscustomobject]@{
            Titel = $w.Titel; Hinweis = $w.Hinweis; Schwer = [bool]$w.Schwer
            Anzahl = $funde.Count; Fundstellen = $funde.ToArray()
        })
    }
    $ergebnis.Warnungen = $warnListe.ToArray()

    # ---- Adressen, Ports, Pfade ---------------------------------------------------
    $adr = @{}
    foreach ($m in [regex]::Matches($text, '(?i)\b(?:https?|ftp)://[^\s"''<>\)\]]+')) {
        $u = $m.Value.TrimEnd('.,;:')
        if ($u.Length -le 120) { $adr[$u] = $true }
    }
    foreach ($m in [regex]::Matches($text, '(?<![\d.])((?:\d{1,3}\.){3}\d{1,3})(?![\d.])')) {
        $ip = $m.Groups[1].Value
        if ($ip -notmatch '^(0\.0\.0\.0|255\.255|127\.0\.0\.1|1\.1\.1\.1)$') { $adr["IP $ip"] = $true }
    }
    $ergebnis.Adressen = @($adr.Keys | Sort-Object)

    # Ports: NUR die, die das Skript selbst oeffnet oder belegt (Firewallregeln,
    # Listener, Port-Konstanten). Die vielen bekannten Spiel-Ports aus Tabellen
    # wuerden den Bericht sonst zumuellen - sie werden nur gezaehlt.
    $ports = @{}
    $portMuster = @(
        '-LocalPort\s+(\d{2,5})'
        'LocalPort\s*=\s*(\d{2,5})'
        'IPEndPoint\([^,)]+,\s*(\d{2,5})\s*\)'
        'TcpListener\([^,)]+,\s*(\d{2,5})\s*\)'
        'UdpClient\(\s*(\d{2,5})\s*\)'
        '(?i)port(?:number)?\s*=\s*(\d{2,5})'
        '(?i)\.Port\s*=\s*(\d{2,5})'
    )
    foreach ($mu in $portMuster) {
        foreach ($m in [regex]::Matches($text, $mu)) {
            $p = [int]$m.Groups[1].Value
            if ($p -ge 1 -and $p -le 65535) { $ports[$p] = $true }
        }
    }
    $ergebnis.Ports = @($ports.Keys | Sort-Object)
    $andere = @{}
    foreach ($m in [regex]::Matches($text, '(?<![\d.])(\d{4,5})(?![\d.])')) {
        $p = [int]$m.Groups[1].Value
        if ($p -ge 1024 -and $p -le 65535 -and -not $ports.ContainsKey($p)) { $andere[$p] = $true }
    }
    $ergebnis.PortsWeitere = $andere.Count

    $pfade = @{}
    foreach ($m in [regex]::Matches($text, '(?i)(?:[A-Z]:\\[^"''\s\)\]]{2,80}|%[A-Z]+%\\[^"''\s\)\]]{2,60}|\$env:[A-Z]+\\[^"''\s\)\]]{2,60})')) {
        $p = $m.Value.TrimEnd('.,;:\')
        if ($p -notmatch '^[A-Z]:\\?$') { $pfade[$p] = $true }
    }
    $ergebnis.Pfade = @($pfade.Keys | Sort-Object)

    $aufgListe = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($text, '(?i)TaskName\s*[= ]\s*[''"]([^''"]{3,80})[''"]')) {
        $aufgListe.Add($m.Groups[1].Value)
    }
    $ergebnis.Aufgaben = @($aufgListe | Sort-Object -Unique)

    if ($tempDatei) { try { Remove-Item -LiteralPath $tempDatei -Force -ErrorAction SilentlyContinue } catch { } }
    return $ergebnis
}

function Format-PwBericht {
    param($A, [int]$MaxFundstellen = 15)
    $sb = New-Object System.Text.StringBuilder
    $add = { param([string]$t) [void]$sb.AppendLine($t) }
    & $add ('=' * 78)
    & $add ' PRUEFBERICHT - was dieses PowerShell-Skript tut'
    & $add ('=' * 78)
    & $add ''
    & $add "Datei      : $($A.Datei)"
    & $add ("Groesse    : {0:N0} Bytes, {1:N0} Zeilen" -f $A.Groesse, $A.Zeilen)
    & $add "SHA-256    : $($A.Sha)"
    & $add "Geprueft   : $(Get-Date -Format 'dd.MM.yyyy HH:mm')"
    if ($A.ParseFehler -gt 0) { & $add "ACHTUNG    : $($A.ParseFehler) Syntaxfehler - das Skript ist moeglicherweise beschaedigt." }
    & $add ''
    & $add 'So liest du diesen Bericht: Keine der folgenden Faehigkeiten ist fuer sich'
    & $add 'genommen boese. Entscheidend ist, ob sie zu dem passt, was das Programm'
    & $add 'offen anbietet. Ein LAN-Tool DARF Ports oeffnen. Ein Taschenrechner nicht.'
    & $add ''
    & $add ('-' * 78)
    & $add ' 1. WAS DAS SKRIPT AM PC MACHT'
    & $add ('-' * 78)
    foreach ($k in $A.Kategorien) {
        & $add ''
        if ($k.Anzahl -eq 0) { & $add ("[  -  ] {0}: kommt nicht vor" -f $k.Titel); continue }
        & $add ("[{0,4} ] {1}" -f $k.Anzahl, $k.Titel)
        foreach ($z in ($k.Erklaerung -split '(?<=\.) ')) { & $add ("        $z") }
        $n = 0
        foreach ($f in $k.Fundstellen) {
            if ($n -ge $MaxFundstellen) { & $add ("        ... und $($k.Anzahl - $MaxFundstellen) weitere Stellen"); break }
            & $add ("        Zeile {0,-6} {1}" -f $f.Zeile, $f.Text)
            $n++
        }
    }
    & $add ''
    & $add ('-' * 78)
    & $add ' 2. TYPISCHE MERKMALE VON SCHADSOFTWARE'
    & $add ('-' * 78)
    & $add ' "nicht gefunden" ist hier die gute Nachricht.'
    foreach ($w in $A.Warnungen) {
        & $add ''
        if ($w.Anzahl -eq 0) {
            & $add ("[ nein ] {0}" -f $w.Titel)
        } else {
            $marke = if ($w.Schwer) { '[ JA!! ]' } else { '[  ja  ]' }
            & $add ("$marke {0}  ({1} Stellen)" -f $w.Titel, $w.Anzahl)
            & $add ("         $($w.Hinweis)")
            $n = 0
            foreach ($f in $w.Fundstellen) {
                if ($n -ge 6) { & $add ("         ... und $($w.Anzahl - 6) weitere"); break }
                & $add ("         Zeile {0,-6} {1}" -f $f.Zeile, $f.Text)
                $n++
            }
        }
    }
    & $add ''
    & $add ('-' * 78)
    & $add ' 3. WOHIN GEHT ES INS NETZ?'
    & $add ('-' * 78)
    if ($A.Adressen.Count -eq 0) { & $add ' Keine festen Adressen im Skript gefunden.' }
    else { foreach ($a in $A.Adressen) { & $add "   $a" } }
    & $add ''
    & $add ' Ports, die das Skript selbst oeffnet oder belegt:'
    if ($A.Ports.Count -eq 0) { & $add '   keine gefunden' } else { & $add ('   ' + (($A.Ports | Sort-Object) -join ', ')) }
    if ($A.PortsWeitere -gt 0) {
        & $add ("   (Ausserdem kommen {0} weitere Portnummern im Text vor - bei einem" -f $A.PortsWeitere)
        & $add '    Spiele-Tool sind das die bekannten Ports der einzelnen Spiele.)'
    }
    & $add ''
    & $add ('-' * 78)
    & $add ' 4. WELCHE ORDNER UND DATEIEN KOMMEN VOR?'
    & $add ('-' * 78)
    if ($A.Pfade.Count -eq 0) { & $add '   keine' }
    else { foreach ($p in ($A.Pfade | Select-Object -First 60)) { & $add "   $p" } }
    if ($A.Pfade.Count -gt 60) { & $add "   ... und $($A.Pfade.Count - 60) weitere" }
    if ($A.Aufgaben.Count -gt 0) {
        & $add ''
        & $add ' Geplante Aufgaben (Autostart):'
        foreach ($t in $A.Aufgaben) { & $add "   $t" }
    }
    & $add ''
    & $add ('=' * 78)
    & $add ' WAS DIESER BERICHT NICHT KANN'
    & $add ('=' * 78)
    & $add ' Er liest den Text des Skripts - er fuehrt es nicht aus und beweist nicht,'
    & $add ' dass es harmlos ist. Er zeigt, WELCHE Faehigkeiten drinstecken und WO sie'
    & $add ' im Code stehen, damit du gezielt nachsehen kannst. Wer ganz sicher gehen'
    & $add ' will, oeffnet die genannten Zeilen im Editor oder probiert das Programm'
    & $add ' zuerst in der Windows-Sandbox aus (Punkt 3 im Pruefwerkzeug).'
    & $add ''
    & $add ' Pruefe ruhig auch ein Skript, dem du vertraust - dann siehst du, dass'
    & $add ' dieses Werkzeug nicht nur bei Project Earth LAN "alles gut" sagt.'
    & $add ''
    & $add ' Bei einer .exe holt das Werkzeug das eingebettete Skript heraus und prueft'
    & $add ' dieses. Mit "Mit .ps1 vergleichen" laesst sich zeigen, dass die .exe genau'
    & $add ' aus der veroeffentlichten Skriptdatei gebaut wurde.'
    return $sb.ToString()
}
# ------------------------------------------------------------------------------
# .EXE PRUEFEN
# ------------------------------------------------------------------------------
# Eine mit PS2EXE gebaute .exe ist nur eine Huelle um das PowerShell-Skript: der
# Skripttext steckt als Base64-Block in der Datei. Den holen wir heraus - dann
# laesst sich die .exe genauso pruefen wie das Skript, und man kann vergleichen,
# ob sie wirklich aus der veroeffentlichten .ps1 gebaut wurde.
function Get-PwExeAngaben {
    param([string]$Pfad)
    $r = [pscustomobject]@{
        Pfad = $Pfad; Groesse = 0; Sha = ''; Firma = ''; Produkt = ''; Version = ''
        Beschreibung = ''; Copyright = ''; Signatur = 'nicht signiert'; Signierer = ''
        Herkunft = ''; DotNet = $false
    }
    try {
        $fi = Get-Item -LiteralPath $Pfad
        $r.Groesse = $fi.Length
        $vi = $fi.VersionInfo
        $r.Firma = [string]$vi.CompanyName
        $r.Produkt = [string]$vi.ProductName
        $r.Version = [string]$vi.FileVersion
        $r.Beschreibung = [string]$vi.FileDescription
        $r.Copyright = [string]$vi.LegalCopyright
    } catch { }
    try { $r.Sha = (Get-FileHash -LiteralPath $Pfad -Algorithm SHA256).Hash } catch { }
    try {
        $sig = Get-AuthenticodeSignature -LiteralPath $Pfad
        $r.Signatur = [string]$sig.Status
        if ($sig.SignerCertificate) { $r.Signierer = [string]$sig.SignerCertificate.Subject }
    } catch { }
    # Herkunft: Windows merkt sich, ob eine Datei aus dem Internet kam
    try {
        $z = Get-Content -LiteralPath $Pfad -Stream Zone.Identifier -ErrorAction Stop | Out-String
        if ($z -match 'ZoneId=3') { $r.Herkunft = 'aus dem Internet heruntergeladen' }
        elseif ($z -match 'ZoneId=2') { $r.Herkunft = 'aus dem lokalen Netzwerk' }
        if ($z -match '(?m)^HostUrl=(.+)$') { $r.Herkunft += ' (' + $matches[1].Trim() + ')' }
    } catch { $r.Herkunft = 'keine Internet-Markierung (lokal erstellt oder entfernt)' }
    return $r
}

# Holt den eingebetteten Skripttext aus einer .exe. Rueckgabe: Text oder $null.
function Get-PwSkriptAusExe {
    param([string]$Pfad)
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Pfad)
    } catch { return $null }
    if ($bytes.Length -lt 1000) { return $null }

    $sichten = @(
        [System.Text.Encoding]::Unicode.GetString($bytes)   # .NET legt Texte als UTF-16 ab
        [System.Text.Encoding]::ASCII.GetString($bytes)
    )
    $bester = $null
    foreach ($sicht in $sichten) {
        foreach ($m in [regex]::Matches($sicht, '[A-Za-z0-9+/]{1500,}={0,2}')) {
            $b64 = $m.Value
            # Laenge auf ein Vielfaches von 4 kuerzen, sonst wirft der Dekoder
            $rest = $b64.Length % 4
            if ($rest -ne 0) { $b64 = $b64.Substring(0, $b64.Length - $rest) }
            $roh = $null
            try { $roh = [Convert]::FromBase64String($b64) } catch { continue }
            if (-not $roh -or $roh.Length -lt 500) { continue }
            # evtl. zusaetzlich gepackt
            $kandidaten = New-Object System.Collections.Generic.List[string]
            $kandidaten.Add([System.Text.Encoding]::UTF8.GetString($roh))
            $kandidaten.Add([System.Text.Encoding]::Unicode.GetString($roh))
            try {
                $ms = New-Object System.IO.MemoryStream(, $roh)
                $gz = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionMode]::Decompress)
                $sr = New-Object System.IO.StreamReader($gz, [System.Text.Encoding]::UTF8)
                $kandidaten.Add($sr.ReadToEnd())
                $sr.Dispose()
            } catch { }
            foreach ($k in $kandidaten) {
                if (-not $k -or $k.Length -lt 500) { continue }
                # Sieht das nach PowerShell aus?
                $punkte = 0
                foreach ($mark in @('function ', '$script:', 'param(', 'Write-Host', 'foreach ', 'New-Object', '$_', 'if (')) {
                    if ($k.Contains($mark)) { $punkte++ }
                }
                if ($punkte -ge 3) {
                    if (-not $bester -or $k.Length -gt $bester.Length) { $bester = $k }
                }
            }
        }
        if ($bester) { break }
    }
    return $bester
}

# Vergleicht zwei Skripttexte unabhaengig von Zeilenenden und BOM.
function Compare-PwText {
    param([string]$A, [string]$B)
    $na = ($A -replace "`r`n", "`n").Trim([char]0xFEFF).Trim()
    $nb = ($B -replace "`r`n", "`n").Trim([char]0xFEFF).Trim()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $ha = [Convert]::ToBase64String($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($na)))
        $hb = [Convert]::ToBase64String($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($nb)))
    } finally { $sha.Dispose() }
    return [pscustomobject]@{ Gleich = ($ha -eq $hb); HashA = $ha; HashB = $hb
        ZeilenA = ($na -split "`n").Count; ZeilenB = ($nb -split "`n").Count }
}

function Format-PwExeKopf {
    param($E, $SkriptGefunden, [int]$SkriptLaenge)
    $z = New-Object System.Collections.Generic.List[string]
    $z.Add('--- Angaben der .exe ---')
    $z.Add("Datei        : $($E.Pfad)")
    $z.Add(("Groesse      : {0:N0} Bytes" -f $E.Groesse))
    $z.Add("SHA-256      : $($E.Sha)")
    $z.Add("Produkt      : $($E.Produkt)  $($E.Version)")
    $z.Add("Firma        : $(if ($E.Firma) { $E.Firma } else { '(leer)' })")
    $z.Add("Beschreibung : $($E.Beschreibung)")
    $z.Add("Copyright    : $($E.Copyright)")
    $z.Add("Signatur     : $($E.Signatur)$(if ($E.Signierer) { ' - ' + $E.Signierer } else { '' })")
    $z.Add("Herkunft     : $($E.Herkunft)")
    if ($SkriptGefunden) {
        $z.Add(("Eingebettetes Skript: gefunden, {0:N0} Zeichen - es wird unten geprueft" -f $SkriptLaenge))
    } else {
        $z.Add('Eingebettetes Skript: NICHT gefunden. Die Datei wurde vermutlich nicht mit')
        $z.Add('PS2EXE gebaut. Dann kann dieses Werkzeug nur die Angaben oben zeigen -')
        $z.Add('pruefe in dem Fall die .ps1 aus demselben Download.')
    }
    return ($z -join [Environment]::NewLine)
}

# ==============================================================================
# TEIL 2: ENTFERNEN
# ==============================================================================
$script:PwDesktop = ''
try { $script:PwDesktop = [Environment]::GetFolderPath('Desktop') } catch { }
if (-not $script:PwDesktop) { $script:PwDesktop = "$env:USERPROFILE\Desktop" }

$script:PwOrdner = @(
    @{ Pfad = 'C:\Project-Earth-Lan'; Text = 'Einstellungen, Freundes- und Bannliste, Postfach, Protokolle'; Standard = $true }
    @{ Pfad = "$env:APPDATA\ProjectEarthLan"; Text = 'Persoenliche Einstellungen, Chat-Verlauf'; Standard = $true }
    @{ Pfad = "$script:PwDesktop\Lan Games"; Text = 'Verknuepfungen zu deinen Spielen (Option 7/8) - loescht KEINE Spiele'; Standard = $false }
    @{ Pfad = "$script:PwDesktop\Server_Downloads"; Text = 'Heruntergeladene Dateien aus Option 5 - das sind DEINE Downloads'; Standard = $false }
    @{ Pfad = "$env:USERPROFILE\Downloads\ProjectEarthLAN"; Text = 'Empfangene Dateien aus der Kommunikationszentrale'; Standard = $false }
)
$script:PwDesktopDateien = @('Project Earth Lan IP.txt', 'RDP_Port.txt',
    'Was genau passiert wenn ich Project Earth LAN Manager benutze.txt', 'Defender-Meldung.txt')

function Get-PwOrdnerGroesse([string]$Pfad) {
    try {
        $b = (Get-ChildItem -LiteralPath $Pfad -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        if (-not $b) { return '0 KB' }
        if ($b -gt 1GB) { return ('{0:N1} GB' -f ($b / 1GB)) }
        if ($b -gt 1MB) { return ('{0:N1} MB' -f ($b / 1MB)) }
        return ('{0:N0} KB' -f ($b / 1KB))
    } catch { return '?' }
}

# Sucht alles, was Project Earth LAN auf diesem PC hinterlassen hat.
function Get-PwEntfernenListe {
    $liste = New-Object System.Collections.Generic.List[object]

    # 1. Autostart-Aufgabe
    try {
        $t = Get-ScheduledTask -TaskName 'Project Earth LAN Manager (Autostart)' -ErrorAction SilentlyContinue
        if ($t) {
            $liste.Add([pscustomobject]@{ Art = 'Aufgabe'; Titel = 'Autostart-Aufgabe "Project Earth LAN Manager (Autostart)"'
                Detail = 'Startet den Manager bei der Anmeldung'; Standard = $true; Ziel = 'Project Earth LAN Manager (Autostart)' })
        }
    } catch { }

    # 2. Firewallregeln
    try {
        $r = @(Get-NetFirewallRule -DisplayName 'Project Earth LAN*' -ErrorAction SilentlyContinue)
        if ($r.Count -gt 0) {
            $liste.Add([pscustomobject]@{ Art = 'Firewall'; Titel = "Firewallregeln ""Project Earth LAN*"" ($($r.Count) Stueck)"
                Detail = (($r | Select-Object -First 6 | ForEach-Object { $_.DisplayName }) -join ' | '); Standard = $true; Ziel = 'Project Earth LAN*' })
        }
        $rdp = @(Get-NetFirewallRule -DisplayName 'RDP Port 9870 (Custom)' -ErrorAction SilentlyContinue)
        if ($rdp.Count -gt 0) {
            $liste.Add([pscustomobject]@{ Art = 'Firewall'; Titel = 'Firewallregel "RDP Port 9870 (Custom)"'
                Detail = 'Remotedesktop-Regel aus Option 6 - gilt fuer ALLE Netzwerke'; Standard = $true; Ziel = 'RDP Port 9870 (Custom)' })
        }
    } catch { }

    # 3. Ordner
    foreach ($o in $script:PwOrdner) {
        if ($o.Pfad -and $o.Pfad -notmatch '^\\' -and (Test-Path -LiteralPath $o.Pfad)) {
            $liste.Add([pscustomobject]@{ Art = 'Ordner'; Titel = "Ordner $($o.Pfad)  [$(Get-PwOrdnerGroesse $o.Pfad)]"
                Detail = $o.Text; Standard = [bool]$o.Standard; Ziel = $o.Pfad })
        }
    }

    # 4. Einzelne Dateien auf dem Desktop
    $desk = $script:PwDesktop
    if ($desk -and (Test-Path -LiteralPath $desk)) {
    foreach ($d in $script:PwDesktopDateien) {
        $p = Join-Path $desk $d
        if (Test-Path -LiteralPath $p) {
            $liste.Add([pscustomobject]@{ Art = 'Datei'; Titel = "Datei $d (Desktop)"; Detail = 'Vom Manager erzeugte Textdatei'; Standard = $true; Ziel = $p })
        }
    }
    foreach ($z in @(Get-ChildItem -LiteralPath $desk -Filter 'ProjectEarthLan_Fehlerlog_*.zip' -File -ErrorAction SilentlyContinue)) {
        $liste.Add([pscustomobject]@{ Art = 'Datei'; Titel = "Fehlerlog $($z.Name)"; Detail = 'Exportiertes Fehlerprotokoll'; Standard = $true; Ziel = $z.FullName })
    }
    }

    # 5. ZeroTier-Netzwerke von Project Earth LAN
    $cli = ''
    foreach ($k in @("$env:ProgramFiles\ZeroTier\One\zerotier-cli.bat", "${env:ProgramFiles(x86)}\ZeroTier\One\zerotier-cli.bat")) {
        if ($k -and (Test-Path -LiteralPath $k)) { $cli = $k; break }
    }
    if ($cli) {
        foreach ($netz in @('091f0945fc5012f1', '091f0945fc744570')) {
            try {
                $out = & $cli listnetworks 2>$null | Out-String
                if ($out -match $netz) {
                    $liste.Add([pscustomobject]@{ Art = 'ZeroTier'; Titel = "ZeroTier-Netzwerk $netz verlassen"
                        Detail = 'Danach ist dieser PC nicht mehr im Project Earth LAN'; Standard = $true; Ziel = $netz })
                }
            } catch { }
        }
    }
    return $liste
}

function Invoke-PwEntfernen {
    param($Eintraege, [scriptblock]$Log)
    foreach ($e in $Eintraege) {
        try {
            switch ($e.Art) {
                'Aufgabe' {
                    Unregister-ScheduledTask -TaskName $e.Ziel -Confirm:$false -ErrorAction Stop
                    & $Log "Entfernt: Autostart-Aufgabe"
                }
                'Firewall' {
                    $n = 0
                    foreach ($r in @(Get-NetFirewallRule -DisplayName $e.Ziel -ErrorAction SilentlyContinue)) {
                        Remove-NetFirewallRule -Name $r.Name -ErrorAction SilentlyContinue
                        $n++
                    }
                    & $Log "Entfernt: $n Firewallregel(n) ($($e.Ziel))"
                }
                'Ordner' {
                    Remove-Item -LiteralPath $e.Ziel -Recurse -Force -ErrorAction Stop
                    & $Log "Geloescht: $($e.Ziel)"
                }
                'Datei' {
                    Remove-Item -LiteralPath $e.Ziel -Force -ErrorAction Stop
                    & $Log "Geloescht: $($e.Ziel)"
                }
                'ZeroTier' {
                    $cli = ''
                    foreach ($k in @("$env:ProgramFiles\ZeroTier\One\zerotier-cli.bat", "${env:ProgramFiles(x86)}\ZeroTier\One\zerotier-cli.bat")) {
                        if ($k -and (Test-Path -LiteralPath $k)) { $cli = $k; break }
                    }
                    if ($cli) { & $cli leave $e.Ziel 2>&1 | Out-Null; & $Log "Netzwerk verlassen: $($e.Ziel)" }
                    else { & $Log "ZeroTier nicht gefunden - Netzwerk $($e.Ziel) nicht verlassen" }
                }
            }
        } catch {
            & $Log "FEHLER bei '$($e.Titel)': $($_.Exception.Message)"
        }
    }
}

# ==============================================================================
# TEIL 3: SANDBOX
# ==============================================================================
function Test-PwSandbox {
    try { return (Test-Path -LiteralPath (Join-Path $env:WINDIR 'System32\WindowsSandbox.exe')) } catch { return $false }
}

function New-PwSandboxDatei {
    param([string]$Ordner, [string]$Ziel, [bool]$Netzwerk = $true)
    $netz = if ($Netzwerk) { 'Default' } else { 'Disable' }
    $xml = @"
<Configuration>
  <!-- Windows-Sandbox fuer Project Earth LAN.
       Der Ordner unten wird NUR LESEND in die Sandbox gelegt: Was in der Sandbox
       passiert, kann den echten PC nicht veraendern. Beim Schliessen der Sandbox
       wird alles darin spurlos geloescht. -->
  <VGpu>Disable</VGpu>
  <Networking>$netz</Networking>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>$Ordner</HostFolder>
      <SandboxFolder>C:\Users\WDAGUtilityAccount\Desktop\ProjectEarthLAN</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
  </MappedFolders>
  <LogonCommand>
    <Command>explorer.exe C:\Users\WDAGUtilityAccount\Desktop\ProjectEarthLAN</Command>
  </LogonCommand>
</Configuration>
"@
    [System.IO.File]::WriteAllText($Ziel, $xml, (New-Object System.Text.UTF8Encoding($false)))
    return $Ziel
}
# ==============================================================================
# TEIL 4: OBERFLAECHE
# ==============================================================================
function New-PwButton([string]$t, [int]$x, [int]$y, [int]$w, [int]$h, [bool]$accent = $false) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $t
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size($w, $h)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
    $b.ForeColor = $cWhite
    $b.Font = $fBold
    if ($accent) { $b.BackColor = $cAccent } else { $b.BackColor = $cBtn }
    return $b
}
function New-PwLabel([string]$t, [int]$x, [int]$y, [int]$w, [int]$h) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $t; $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Size = New-Object System.Drawing.Size($w, $h)
    $l.ForeColor = $cWhite; $l.Font = $fMain
    return $l
}
function New-PwBox([int]$x, [int]$y, [int]$w, [int]$h) {
    $t = New-Object System.Windows.Forms.RichTextBox
    $t.Location = New-Object System.Drawing.Point($x, $y)
    $t.Size = New-Object System.Drawing.Size($w, $h)
    $t.ReadOnly = $true; $t.BackColor = $cList; $t.ForeColor = $cWhite
    $t.BorderStyle = 'FixedSingle'; $t.Font = $fMono; $t.DetectUrls = $false
    $t.WordWrap = $false; $t.ScrollBars = 'Both'
    return $t
}

$st = @{ Analyse = $null; Bericht = ''; Liste = @(); ExeAngaben = $null; ExeSkript = '' }

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Project Earth LAN - Pruefwerkzeug'
$form.Size = New-Object System.Drawing.Size(1020, 760)
$form.MinimumSize = New-Object System.Drawing.Size(960, 700)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $cBack
$form.ForeColor = $cWhite

$lblKopf = New-PwLabel 'Project Earth LAN - Pruefwerkzeug' 16 12 600 26
$lblKopf.Font = $fHead
$lblSub = New-PwLabel 'Selbst nachsehen, statt jemandem glauben zu muessen.' 18 38 700 20
$lblSub.ForeColor = $cGray
$lblAdmin = New-PwLabel '' 620 16 370 40
$lblAdmin.ForeColor = $cGray
$lblAdmin.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$lblAdmin.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
if (Test-IstAdmin) { $lblAdmin.Text = 'Laeuft mit Administratorrechten'; $lblAdmin.ForeColor = [System.Drawing.Color]::Orange }
else { $lblAdmin.Text = 'Laeuft OHNE Administratorrechte' + [Environment]::NewLine + '(zum Pruefen reicht das - genau so soll es sein)' }

$nav1 = New-PwButton '1. Pruefbericht' 16 66 220 38 $true
$nav2 = New-PwButton '2. Alles entfernen' 244 66 220 38
$nav3 = New-PwButton '3. Sandbox' 472 66 220 38

$p1 = New-Object System.Windows.Forms.Panel
$p2 = New-Object System.Windows.Forms.Panel
$p3 = New-Object System.Windows.Forms.Panel
foreach ($pp in @($p1, $p2, $p3)) {
    $pp.Location = New-Object System.Drawing.Point(16, 114)
    $pp.Size = New-Object System.Drawing.Size(976, 600)
    $pp.BackColor = $cBack
    $pp.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
}
$p2.Visible = $false; $p3.Visible = $false

# ---- Bereich 1: Pruefbericht ---------------------------------------------------
$p1.Controls.Add((New-PwLabel 'Datei, die geprueft werden soll - .ps1 oder die fertige .exe:' 0 0 700 20))
$txtDatei = New-Object System.Windows.Forms.TextBox
$txtDatei.Location = New-Object System.Drawing.Point(0, 22)
$txtDatei.Size = New-Object System.Drawing.Size(640, 26)
$txtDatei.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40)
$txtDatei.ForeColor = $cWhite
$txtDatei.Font = $fMain
$btnWahl = New-PwButton 'Durchsuchen ...' 650 20 150 30
$btnPruef = New-PwButton 'Pruefen' 810 20 166 30 $true
$lvKat = New-Object System.Windows.Forms.ListView
$lvKat.Location = New-Object System.Drawing.Point(0, 62)
$lvKat.Size = New-Object System.Drawing.Size(380, 492)
$lvKat.View = 'Details'; $lvKat.FullRowSelect = $true; $lvKat.MultiSelect = $false
$lvKat.HideSelection = $false; $lvKat.BackColor = $cList; $lvKat.ForeColor = $cWhite; $lvKat.Font = $fMain
[void]$lvKat.Columns.Add('Anzahl', 60)
[void]$lvKat.Columns.Add('Thema', 300)
$rtbDet = New-PwBox 390 62 586 492
$lblStatus1 = New-PwLabel 'Noch nichts geprueft.' 0 562 380 20
$lblStatus1.ForeColor = $cGray
$btnSkript = New-PwButton 'Skript aus .exe speichern' 390 558 190 30
$btnVergleich = New-PwButton 'Mit .ps1 vergleichen' 586 558 180 30
$btnBericht = New-PwButton 'Ganzer Bericht' 772 558 110 30
$btnSpeichern = New-PwButton 'Speichern' 888 558 88 30
$p1.Controls.AddRange(@($txtDatei, $btnWahl, $btnPruef, $lvKat, $rtbDet, $lblStatus1, $btnSkript, $btnVergleich, $btnBericht, $btnSpeichern))
$lvKat.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Bottom
$rtbDet.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
foreach ($c in @($lblStatus1, $btnSkript, $btnVergleich, $btnBericht, $btnSpeichern)) { $c.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left }
foreach ($c in @($btnWahl, $btnPruef)) { $c.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right }
$txtDatei.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

function Set-PwDetail($k) {
    $rtbDet.Clear()
    if (-not $k) { return }
    $rtbDet.SelectionFont = $fBold; $rtbDet.SelectionColor = $cWhite
    $rtbDet.AppendText("$($k.Titel)`n`n")
    $rtbDet.SelectionFont = $fMain; $rtbDet.SelectionColor = $cGray
    $rtbDet.AppendText("$($k.Erklaerung)`n`n")
    $rtbDet.SelectionFont = $fMono
    if ($k.Anzahl -eq 0) {
        $rtbDet.SelectionColor = [System.Drawing.Color]::LightGreen
        $rtbDet.AppendText('Kommt in dieser Datei nicht vor.')
        return
    }
    $rtbDet.SelectionColor = $cWhite
    $rtbDet.AppendText("$($k.Anzahl) Fundstelle(n):`n`n")
    $n = 0
    foreach ($f in $k.Fundstellen) {
        if ($n -ge 200) { $rtbDet.AppendText("... und $($k.Anzahl - 200) weitere`n"); break }
        $rtbDet.SelectionColor = $cGray
        $rtbDet.AppendText(("Zeile {0,-7}" -f $f.Zeile))
        $rtbDet.SelectionColor = $cWhite
        $rtbDet.AppendText("$($f.Text)`n")
        $n++
    }
}

function Invoke-PwPruefung {
    $pfad = $txtDatei.Text.Trim('"').Trim()
    if (-not $pfad -or -not (Test-Path -LiteralPath $pfad)) {
        [void][System.Windows.Forms.MessageBox]::Show($form, 'Bitte zuerst eine Datei auswaehlen.', 'Pruefbericht', 'OK', 'Warning'); return
    }
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $lblStatus1.Text = 'Wird geprueft ...'
    $form.Refresh()
    try {
        $st.ExeAngaben = $null
        $st.ExeSkript = ''
        if ($pfad -match '(?i)\.exe$') {
            # .exe: erst die Dateiangaben, dann das eingebettete Skript herausholen
            $lblStatus1.Text = 'Programm wird untersucht, das eingebettete Skript wird gesucht ...'
            $form.Refresh()
            $st.ExeAngaben = Get-PwExeAngaben -Pfad $pfad
            $st.ExeSkript = Get-PwSkriptAusExe -Pfad $pfad
            if (-not $st.ExeSkript) {
                $lvKat.Items.Clear()
                $rtbDet.Clear()
                $rtbDet.SelectionFont = $fMono; $rtbDet.SelectionColor = $cWhite
                $rtbDet.AppendText((Format-PwExeKopf -E $st.ExeAngaben -SkriptGefunden $false -SkriptLaenge 0))
                $st.Analyse = $null
                $st.Bericht = (Format-PwExeKopf -E $st.ExeAngaben -SkriptGefunden $false -SkriptLaenge 0)
                $lblStatus1.Text = 'Kein eingebettetes Skript gefunden - nur die Dateiangaben sind lesbar.'
                return
            }
            $a = Get-PwAnalyse -TextDirekt $st.ExeSkript -AnzeigeName "$pfad  (Skript aus der .exe)"
        } else {
            $a = Get-PwAnalyse -Pfad $pfad
        }
        $st.Analyse = $a
        $st.Bericht = Format-PwBericht -A $a
        if ($st.ExeAngaben) {
            $st.Bericht = (Format-PwExeKopf -E $st.ExeAngaben -SkriptGefunden $true -SkriptLaenge $st.ExeSkript.Length) + [Environment]::NewLine + [Environment]::NewLine + $st.Bericht
        }
        $lvKat.BeginUpdate(); $lvKat.Items.Clear()
        foreach ($k in $a.Kategorien) {
            $it = New-Object System.Windows.Forms.ListViewItem([string]$k.Anzahl)
            [void]$it.SubItems.Add($k.Titel)
            $it.Tag = $k
            if ($k.Anzahl -eq 0) { $it.ForeColor = [System.Drawing.Color]::DimGray }
            [void]$lvKat.Items.Add($it)
        }
        $trenner = New-Object System.Windows.Forms.ListViewItem('')
        [void]$trenner.SubItems.Add('--- Merkmale von Schadsoftware ---')
        $trenner.ForeColor = $cGray
        [void]$lvKat.Items.Add($trenner)
        foreach ($w in $a.Warnungen) {
            $it = New-Object System.Windows.Forms.ListViewItem($(if ($w.Anzahl -eq 0) { 'nein' } else { [string]$w.Anzahl }))
            [void]$it.SubItems.Add($w.Titel)
            $it.Tag = [pscustomobject]@{ Titel = $w.Titel; Erklaerung = $w.Hinweis; Anzahl = $w.Anzahl; Fundstellen = $w.Fundstellen }
            if ($w.Anzahl -eq 0) { $it.ForeColor = [System.Drawing.Color]::LightGreen }
            elseif ($w.Schwer) { $it.ForeColor = [System.Drawing.Color]::OrangeRed }
            else { $it.ForeColor = [System.Drawing.Color]::Gold }
            [void]$lvKat.Items.Add($it)
        }
        $lvKat.EndUpdate()
        $schwer = @($a.Warnungen | Where-Object { $_.Schwer -and $_.Anzahl -gt 0 })
        $shaKurz = if ($a.Sha -and $a.Sha.Length -ge 32) { $a.Sha.Substring(0, 32) + '...' } else { '(nicht berechenbar)' }
        $lblStatus1.Text = "Geprueft: $($a.Zeilen) Zeilen | SHA-256: $shaKurz"
        $rtbDet.Clear()
        $rtbDet.SelectionFont = $fBold
        $rtbDet.SelectionColor = $(if ($schwer.Count -gt 0) { [System.Drawing.Color]::OrangeRed } else { [System.Drawing.Color]::LightGreen })
        if ($schwer.Count -gt 0) {
            $rtbDet.AppendText("$($schwer.Count) schwerwiegende(s) Merkmal(e) gefunden - links rot markiert.`n`n")
        } else {
            $rtbDet.AppendText("Keines der typischen Schadsoftware-Merkmale gefunden.`n`n")
        }
        $rtbDet.SelectionFont = $fMain; $rtbDet.SelectionColor = $cWhite
        $rtbDet.AppendText("Links auf ein Thema klicken, um die genauen Zeilen zu sehen.`n`n")
        $rtbDet.SelectionColor = $cGray
        if ($st.ExeAngaben) {
            $rtbDet.SelectionFont = $fMono
            $rtbDet.AppendText((Format-PwExeKopf -E $st.ExeAngaben -SkriptGefunden $true -SkriptLaenge $st.ExeSkript.Length) + "`n`n")
            $rtbDet.SelectionFont = $fMain
            $rtbDet.AppendText("Das eingebettete Skript (SHA-256 unten) wurde geprueft - die Themen links`ngelten also fuer den Inhalt dieser .exe.`n`n")
        }
        $rtbDet.AppendText("Geprueft : $($a.Datei)`nGroesse  : $('{0:N0}' -f $a.Groesse) Bytes`nZeilen   : $('{0:N0}' -f $a.Zeilen)`nSHA-256  : $($a.Sha)`n")
        if ($a.ParseFehler -gt 0) { $rtbDet.AppendText("ACHTUNG  : $($a.ParseFehler) Syntaxfehler - Datei evtl. beschaedigt.`n") }
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show($form, "Pruefung fehlgeschlagen:`n$($_.Exception.Message)", 'Pruefbericht', 'OK', 'Error')
    } finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
}

$btnWahl.Add_Click({
    $d = New-Object System.Windows.Forms.OpenFileDialog
    $d.Filter = 'Skript oder Programm (*.ps1;*.exe)|*.ps1;*.exe|PowerShell-Skript (*.ps1)|*.ps1|Programm (*.exe)|*.exe|Alle Dateien (*.*)|*.*'
    $d.Title = 'Welche Datei soll geprueft werden?'
    if ($d.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) { $txtDatei.Text = $d.FileName; Invoke-PwPruefung }
})
$btnPruef.Add_Click({ Invoke-PwPruefung })
$txtDatei.Add_KeyDown({ if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) { $_.SuppressKeyPress = $true; Invoke-PwPruefung } })
$lvKat.Add_SelectedIndexChanged({ if ($lvKat.SelectedItems.Count -gt 0) { Set-PwDetail $lvKat.SelectedItems[0].Tag } })
$btnSkript.Add_Click({
    if (-not $st.ExeSkript) { [void][System.Windows.Forms.MessageBox]::Show($form, 'Das gilt nur fuer eine gepruefte .exe: Dort holt das Werkzeug das eingebettete Skript heraus und kann es hier speichern.', 'Skript speichern', 'OK', 'Information'); return }
    $name = [System.IO.Path]::GetFileNameWithoutExtension($st.Analyse.Datei -replace '\s*\(Skript aus der \.exe\)$', '')
    $ziel = Join-Path $script:PwDesktop ("Skript_aus_" + $name + ".ps1")
    try {
        [System.IO.File]::WriteAllText($ziel, $st.ExeSkript, (New-Object System.Text.UTF8Encoding($true)))
        $lblStatus1.Text = "Gespeichert: $ziel"
        try { Start-Process notepad.exe -ArgumentList "`"$ziel`"" } catch { }
    } catch { [void][System.Windows.Forms.MessageBox]::Show($form, "Speichern fehlgeschlagen: $($_.Exception.Message)", 'Skript speichern', 'OK', 'Error') }
})
$btnVergleich.Add_Click({
    if (-not $st.ExeSkript) { [void][System.Windows.Forms.MessageBox]::Show($form, "Bitte zuerst eine .exe pruefen.`n`nDann kann hier verglichen werden, ob die .exe wirklich aus einer bestimmten .ps1 gebaut wurde.", 'Vergleichen', 'OK', 'Information'); return }
    $d = New-Object System.Windows.Forms.OpenFileDialog
    $d.Filter = 'PowerShell-Skript (*.ps1)|*.ps1|Alle Dateien (*.*)|*.*'
    $d.Title = 'Mit welcher .ps1 soll verglichen werden?'
    if ($d.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
    try {
        $andere = [System.IO.File]::ReadAllText($d.FileName, [System.Text.Encoding]::UTF8)
        $v = Compare-PwText -A $st.ExeSkript -B $andere
        $rtbDet.Clear()
        $rtbDet.SelectionFont = $fBold
        if ($v.Gleich) {
            $rtbDet.SelectionColor = [System.Drawing.Color]::LightGreen
            $rtbDet.AppendText("Identisch.`n`n")
            $rtbDet.SelectionFont = $fMain; $rtbDet.SelectionColor = $cWhite
            $rtbDet.AppendText("Die .exe enthaelt genau dieses Skript. Wer das Skript gelesen hat, weiss`ndamit auch, was die .exe tut - Zeile fuer Zeile dasselbe.`n`n")
        } else {
            $rtbDet.SelectionColor = [System.Drawing.Color]::OrangeRed
            $rtbDet.AppendText("NICHT identisch.`n`n")
            $rtbDet.SelectionFont = $fMain; $rtbDet.SelectionColor = $cWhite
            $rtbDet.AppendText("Die .exe wurde aus einem anderen Stand gebaut als diese .ps1. Das kann`nharmlos sein (neuere Version, andere Fassung) - es heisst aber, dass das`ngelesene Skript nicht beweist, was die .exe tut.`n`n")
        }
        $rtbDet.SelectionFont = $fMono; $rtbDet.SelectionColor = $cGray
        $rtbDet.AppendText("Skript aus der .exe : $($v.ZeilenA) Zeilen`nSHA-256 (Text)      : $($v.HashA)`n`n")
        $rtbDet.AppendText("Gewaehlte .ps1       : $($v.ZeilenB) Zeilen`nSHA-256 (Text)      : $($v.HashB)`n`n")
        $rtbDet.AppendText("Datei: $($d.FileName)`n")
        $rtbDet.AppendText("`nHinweis: Verglichen wird der reine Text, Zeilenenden und BOM zaehlen nicht mit.`n")
        $lblStatus1.Text = if ($v.Gleich) { 'Vergleich: .exe und .ps1 sind inhaltlich identisch.' } else { 'Vergleich: .exe und .ps1 sind NICHT identisch.' }
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show($form, "Vergleich fehlgeschlagen: $($_.Exception.Message)", 'Vergleichen', 'OK', 'Error')
    }
})
$btnBericht.Add_Click({
    if (-not $st.Bericht) { [void][System.Windows.Forms.MessageBox]::Show($form, 'Bitte zuerst eine Datei pruefen.', 'Bericht', 'OK', 'Information'); return }
    $rtbDet.Clear(); $rtbDet.SelectionFont = $fMono; $rtbDet.SelectionColor = $cWhite
    $rtbDet.AppendText($st.Bericht); $rtbDet.SelectionStart = 0; $rtbDet.ScrollToCaret()
})
$btnSpeichern.Add_Click({
    if (-not $st.Bericht) { [void][System.Windows.Forms.MessageBox]::Show($form, 'Bitte zuerst eine Datei pruefen.', 'Bericht', 'OK', 'Information'); return }
    $quelle = $txtDatei.Text.Trim('"').Trim()
    if ($st.Analyse) { $quelle = $st.Analyse.Datei -replace '\s*\(Skript aus der \.exe\)$', '' }
    $kurz = [System.IO.Path]::GetFileNameWithoutExtension($quelle)
    if (-not $kurz) { $kurz = 'Datei' }
    $ziel = Join-Path $script:PwDesktop ('Pruefbericht_' + $kurz + '.txt')
    try {
        [System.IO.File]::WriteAllText($ziel, $st.Bericht, (New-Object System.Text.UTF8Encoding($true)))
        $lblStatus1.Text = "Gespeichert: $ziel"
        try { Start-Process notepad.exe -ArgumentList "`"$ziel`"" } catch { }
    } catch { [void][System.Windows.Forms.MessageBox]::Show($form, "Speichern fehlgeschlagen: $($_.Exception.Message)", 'Bericht', 'OK', 'Error') }
})

# ---- Bereich 2: Alles entfernen ------------------------------------------------
$p2.Controls.Add((New-PwLabel 'Gefunden auf diesem PC - Haken setzen bei dem, was weg soll:' 0 0 700 20))
$clb = New-Object System.Windows.Forms.CheckedListBox
$clb.Location = New-Object System.Drawing.Point(0, 24)
$clb.Size = New-Object System.Drawing.Size(976, 250)
$clb.BackColor = $cList; $clb.ForeColor = $cWhite; $clb.Font = $fMain
$clb.CheckOnClick = $true; $clb.BorderStyle = 'FixedSingle'
$lblDetail2 = New-PwLabel '' 0 280 976 36
$lblDetail2.ForeColor = $cGray
$btnSuche = New-PwButton 'Suchen' 0 322 180 32 $true
$btnAlle = New-PwButton 'Alle auswaehlen' 190 322 170 32
$btnKeine = New-PwButton 'Keine' 370 322 110 32
$btnWeg = New-PwButton 'Ausgewaehltes entfernen' 700 322 276 32
$btnWeg.BackColor = [System.Drawing.Color]::FromArgb(150, 40, 40)
$rtbLog2 = New-PwBox 0 364 976 190
$lblHinweis2 = New-PwLabel 'ZeroTier One selbst wird nicht entfernt - das machst du bei Bedarf ueber Einstellungen > Apps. Ordner mit eigenen Dateien (Downloads, Lan Games) sind absichtlich nicht vorausgewaehlt.' 0 560 976 36
$lblHinweis2.ForeColor = $cGray
$p2.Controls.AddRange(@($clb, $lblDetail2, $btnSuche, $btnAlle, $btnKeine, $btnWeg, $rtbLog2, $lblHinweis2))
$clb.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$rtbLog2.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
$btnWeg.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
foreach ($c in @($lblHinweis2)) { $c.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right }

function Add-PwLog([string]$t) {
    $rtbLog2.AppendText("$(Get-Date -Format 'HH:mm:ss')  $t`n")
    $rtbLog2.SelectionStart = $rtbLog2.TextLength
    $rtbLog2.ScrollToCaret()
}

function Invoke-PwSuche {
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    try {
        $clb.Items.Clear()
        $st.Liste = @(Get-PwEntfernenListe)
        foreach ($e in $st.Liste) { [void]$clb.Items.Add($e.Titel, [bool]$e.Standard) }
        if ($st.Liste.Count -eq 0) {
            [void]$clb.Items.Add('Nichts gefunden - auf diesem PC ist nichts von Project Earth LAN uebrig.', $false)
            Add-PwLog 'Suche: nichts gefunden.'
        } else {
            Add-PwLog "Suche: $($st.Liste.Count) Eintrag/Eintraege gefunden."
        }
    } finally { $form.Cursor = [System.Windows.Forms.Cursors]::Default }
}

$btnSuche.Add_Click({ Invoke-PwSuche })
$btnAlle.Add_Click({ for ($i = 0; $i -lt $clb.Items.Count; $i++) { $clb.SetItemChecked($i, $true) } })
$btnKeine.Add_Click({ for ($i = 0; $i -lt $clb.Items.Count; $i++) { $clb.SetItemChecked($i, $false) } })
$clb.Add_SelectedIndexChanged({
    $i = $clb.SelectedIndex
    if ($i -ge 0 -and $i -lt $st.Liste.Count) { $lblDetail2.Text = $st.Liste[$i].Detail } else { $lblDetail2.Text = '' }
})
$btnWeg.Add_Click({
    if ($st.Liste.Count -eq 0) { [void][System.Windows.Forms.MessageBox]::Show($form, 'Bitte zuerst auf "Suchen" klicken.', 'Entfernen', 'OK', 'Information'); return }
    $wahl = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $st.Liste.Count; $i++) { if ($clb.GetItemChecked($i)) { $wahl.Add($st.Liste[$i]) } }
    if ($wahl.Count -eq 0) { [void][System.Windows.Forms.MessageBox]::Show($form, 'Nichts ausgewaehlt.', 'Entfernen', 'OK', 'Information'); return }
    if (-not (Test-IstAdmin)) {
        $a = [System.Windows.Forms.MessageBox]::Show($form, "Zum Entfernen von Firewallregeln und der Autostart-Aufgabe braucht Windows Administratorrechte.`n`nDas Werkzeug jetzt mit Administratorrechten neu starten?", 'Entfernen', 'YesNo', 'Question')
        if ($a -eq [System.Windows.Forms.DialogResult]::Yes) {
            $selbst = $PSCommandPath
            if (-not $selbst) { $selbst = $MyInvocation.MyCommand.Definition }
            try { Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$selbst`" -Start 2" -Verb RunAs; $form.Close() } catch { }
        }
        return
    }
    $txt = "Folgendes wird jetzt entfernt:`n`n" + (($wahl | ForEach-Object { " - $($_.Titel)" }) -join "`n") + "`n`nDas kann nicht rueckgaengig gemacht werden. Fortfahren?"
    if ([System.Windows.Forms.MessageBox]::Show($form, $txt, 'Wirklich entfernen?', 'YesNo', 'Warning') -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    try {
        Invoke-PwEntfernen -Eintraege $wahl -Log { param($t) Add-PwLog $t }
        Add-PwLog 'Fertig. Suche wird aktualisiert ...'
        Invoke-PwSuche
    } finally { $form.Cursor = [System.Windows.Forms.Cursors]::Default }
})

# ---- Bereich 3: Sandbox --------------------------------------------------------
$txtInfo3 = New-PwBox 0 0 976 300
$txtInfo3.Text = @'
Windows-Sandbox: den Manager gefahrlos ausprobieren

  Die Windows-Sandbox ist ein leeres Wegwerf-Windows, das in einem eigenen
  Fenster laeuft. Programme darin koennen den echten PC nicht sehen und nicht
  veraendern. Schliesst man das Fenster, ist alles darin restlos geloescht.

  Dieses Werkzeug schreibt dir eine fertige .wsb-Datei. Ein Doppelklick darauf
  startet die Sandbox, legt den gewaehlten Ordner NUR LESEND hinein und oeffnet
  ihn. Dort kannst du den Manager starten und zusehen, was er anlegt.

  Voraussetzung: Windows 10/11 Pro, Enterprise oder Education mit aktivierter
  Funktion "Windows-Sandbox" (Systemsteuerung > Programme > Windows-Features).
  In Windows Home gibt es die Sandbox nicht.

  Ehrlich dazugesagt: In der Sandbox laeuft NICHT alles. ZeroTier installiert
  einen Netzwerktreiber, und das klappt dort meist nicht - der Netzwerkteil
  bleibt also stumm. Was du sehen kannst: dass das Programm startet, welche
  Fenster es hat, welche Ordner und Dateien es anlegt und was es beim Start
  tut. Fuer einen ersten Eindruck ohne Risiko reicht das.
'@
$p3.Controls.Add($txtInfo3)
$p3.Controls.Add((New-PwLabel 'Ordner, der in die Sandbox gelegt wird (dort liegt der Manager):' 0 314 700 20))
$txtOrdner = New-Object System.Windows.Forms.TextBox
$txtOrdner.Location = New-Object System.Drawing.Point(0, 336)
$txtOrdner.Size = New-Object System.Drawing.Size(640, 26)
$txtOrdner.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40)
$txtOrdner.ForeColor = $cWhite; $txtOrdner.Font = $fMain
$btnOrdner = New-PwButton 'Ordner waehlen ...' 650 334 150 30
$chkNetz = New-Object System.Windows.Forms.CheckBox
$chkNetz.Text = 'Netzwerk in der Sandbox erlauben'
$chkNetz.Location = New-Object System.Drawing.Point(0, 374)
$chkNetz.Size = New-Object System.Drawing.Size(300, 24)
$chkNetz.ForeColor = $cWhite; $chkNetz.Font = $fMain; $chkNetz.Checked = $true
$btnWsb = New-PwButton 'Sandbox-Datei erstellen' 0 406 260 34 $true
$btnWsbStart = New-PwButton 'Sandbox jetzt starten' 270 406 240 34
$lblStatus3 = New-PwLabel '' 0 452 976 40
$lblStatus3.ForeColor = $cGray
$p3.Controls.AddRange(@($txtOrdner, $btnOrdner, $chkNetz, $btnWsb, $btnWsbStart, $lblStatus3))
$txtInfo3.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

$btnOrdner.Add_Click({
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = 'Ordner mit dem Project Earth LAN Manager waehlen'
    if ($d.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) { $txtOrdner.Text = $d.SelectedPath }
})
$btnWsb.Add_Click({
    $o = $txtOrdner.Text.Trim('"').Trim()
    if (-not $o -or -not (Test-Path -LiteralPath $o)) { [void][System.Windows.Forms.MessageBox]::Show($form, 'Bitte zuerst einen Ordner waehlen.', 'Sandbox', 'OK', 'Warning'); return }
    $ziel = Join-Path $script:PwDesktop 'Project Earth LAN in Sandbox testen.wsb'
    try {
        [void](New-PwSandboxDatei -Ordner (Resolve-Path -LiteralPath $o).Path -Ziel $ziel -Netzwerk $chkNetz.Checked)
        $lblStatus3.Text = "Erstellt: $ziel" + [Environment]::NewLine + 'Doppelklick darauf startet die Sandbox.'
        if (-not (Test-PwSandbox)) { $lblStatus3.Text += ' ACHTUNG: Windows-Sandbox ist auf diesem PC nicht installiert.' }
    } catch { [void][System.Windows.Forms.MessageBox]::Show($form, "Konnte nicht erstellt werden: $($_.Exception.Message)", 'Sandbox', 'OK', 'Error') }
})
$btnWsbStart.Add_Click({
    if (-not (Test-PwSandbox)) {
        [void][System.Windows.Forms.MessageBox]::Show($form, "Die Windows-Sandbox ist auf diesem PC nicht verfuegbar.`n`nEinschalten: Systemsteuerung > Programme > Windows-Features aktivieren > Haken bei 'Windows-Sandbox' (nur Pro/Enterprise/Education, danach Neustart).", 'Sandbox', 'OK', 'Information'); return
    }
    $ziel = Join-Path $script:PwDesktop 'Project Earth LAN in Sandbox testen.wsb'
    if (-not (Test-Path -LiteralPath $ziel)) { [void][System.Windows.Forms.MessageBox]::Show($form, 'Bitte zuerst die Sandbox-Datei erstellen.', 'Sandbox', 'OK', 'Information'); return }
    try { Start-Process -FilePath $ziel } catch { [void][System.Windows.Forms.MessageBox]::Show($form, "Start fehlgeschlagen: $($_.Exception.Message)", 'Sandbox', 'OK', 'Error') }
})

# ---- Umschalten ----------------------------------------------------------------
function Show-PwPanel([int]$i) {
    $p1.Visible = ($i -eq 1); $p2.Visible = ($i -eq 2); $p3.Visible = ($i -eq 3)
    $nav1.BackColor = $(if ($i -eq 1) { $cAccent } else { $cBtn })
    $nav2.BackColor = $(if ($i -eq 2) { $cAccent } else { $cBtn })
    $nav3.BackColor = $(if ($i -eq 3) { $cAccent } else { $cBtn })
    if ($i -eq 2 -and $clb.Items.Count -eq 0) { Invoke-PwSuche }
}
$nav1.Add_Click({ Show-PwPanel 1 })
$nav2.Add_Click({ Show-PwPanel 2 })
$nav3.Add_Click({ Show-PwPanel 3 })

$form.Controls.AddRange(@($lblKopf, $lblSub, $lblAdmin, $nav1, $nav2, $nav3, $p1, $p2, $p3))

# ---- Startwerte ----------------------------------------------------------------
$vorschlag = ''
if ($Datei -and (Test-Path -LiteralPath $Datei)) { $vorschlag = (Resolve-Path -LiteralPath $Datei).Path }
if (-not $vorschlag) {
    $suchOrte = @($PSScriptRoot, $script:PwDesktop)
    if ($env:USERPROFILE) { $suchOrte += (Join-Path $env:USERPROFILE 'Downloads') }
    foreach ($ort in $suchOrte) {
        if (-not $ort -or -not (Test-Path -LiteralPath $ort)) { continue }
        $t = @(Get-ChildItem -LiteralPath $ort -Filter '*Project*Earth*.ps1' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
        if ($t.Count -gt 0) { $vorschlag = $t[0].FullName; break }
    }
}
$txtDatei.Text = $vorschlag
if ($vorschlag) { $txtOrdner.Text = [System.IO.Path]::GetDirectoryName($vorschlag) }
else { $txtOrdner.Text = $script:PwDesktop }

switch ($Start) {
    '2' { Show-PwPanel 2 }
    '3' { Show-PwPanel 3 }
    default { Show-PwPanel 1 }
}
$form.Add_Shown({
    $form.Activate()
    if ($Start -eq '' -and $txtDatei.Text) { Invoke-PwPruefung }
})
[void]$form.ShowDialog()
$form.Dispose()
