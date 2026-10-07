
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
#@@CSHARP@@
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
#@@DICT@@
'@

# Deutsche Anzeige für Meldungen aus dem Kern (der Kern selbst ist bewusst reines ASCII)
$script:PesI18nDictDe = @'
#@@DICTDE@@
'@
