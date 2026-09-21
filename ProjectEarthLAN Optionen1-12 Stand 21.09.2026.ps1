# ==============================================================================
# Project Earth LAN - All in One Manager, Downloader & Game Finder
# Features: Admin-Elevated | Full White Text / Dark GUI | Progress Bar Dialogs
# ==============================================================================

# 0. OPTIONS-PARAMETER (getrennte Fenster): -Option <Nummer> startet nur diese Option
$Option = ''
for ($ai = 0; $ai -lt ($args.Count - 1); $ai++) {
    if ([string]$args[$ai] -eq '-Option') { $Option = [string]$args[$ai + 1] }
}
$script:SelfPath = $PSCommandPath

# 1. ADMIN-RECHTE & KONSOLE EINRICHTEN
$Host.UI.RawUI.ForegroundColor = "White"
Clear-Host

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if ($PSCommandPath) {
        $optArg = ""
        if ($Option) { $optArg = " -Option $Option" }
        Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"$optArg" -Verb RunAs
        exit
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
# OPTION 2: Vollständige Deinstallation
# ------------------------------------------------------------------------------
function Invoke-FullUninstall {
    $confirm = [System.Windows.Forms.MessageBox]::Show("Möchtest du ZeroTier One inkl. aller versteckten Dateien, Einstellungen und Adapter wirklich VOLLSTÄNDIG entfernen?", "Deinstallation bestätigen", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    Show-ProgressDialog -Title "Deinstallation: ZeroTier One" -TaskScript {
        param($report)

        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

        &$report "1/5 Stoppe ZeroTier-Dienste und Prozesse..." 15
        & sc.exe stop "ZeroTierOneService" 2>&1 | Out-Null
        Get-Service -Name "*ZeroTier*" -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue
        Stop-Process -Name "*zerotier*", "ZeroTier One UI" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        &$report "2/5 Deinstalliere ZeroTier One über MSI / Registry..." 35
        $uninstalled = $false
        $uninstallKeys = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )

        foreach($key in $uninstallKeys) {
            Get-ItemProperty $key -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*ZeroTier*" } | ForEach-Object {
                if ($_.UninstallString) {
                    $uninst = $_.UninstallString
                    if ($uninst -match "msiexec") {
                        $code = [regex]::Match($uninst, "\{[A-F0-9\-]+\}").Value
                        Start-Process msiexec.exe -ArgumentList "/x $code /qn /norestart" -Wait -ErrorAction SilentlyContinue
                        $uninstalled = $true
                    } else {
                        Start-Process cmd.exe -ArgumentList "/c $uninst /S" -Wait -ErrorAction SilentlyContinue
                        $uninstalled = $true
                    }
                }
            }
        }

        if (-not $uninstalled) {
            $wmiApp = Get-CimInstance Win32_Product | Where-Object { $_.Name -like "*ZeroTier*" }
            if ($wmiApp) { $wmiApp | Remove-CimInstance -ErrorAction SilentlyContinue }
        }

        &$report "3/5 Entferne ZeroTier Netzwerkadapter..." 60
        Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "*ZeroTier*" -or $_.Name -like "*ZeroTier*" } | ForEach-Object {
            $interfaceGuid = $_.InterfaceGuid
            Get-CimInstance Win32_NetworkAdapter | Where-Object { $_.GUID -eq $interfaceGuid } | Remove-CimInstance -ErrorAction SilentlyContinue
        }

        &$report "4/5 Bereinige Ordnerstrukturen..." 80
        $targetFolders = @(
            "$env:ProgramFiles\ZeroTier",
            "${env:ProgramFiles(x86)}\ZeroTier",
            "$env:ProgramData\ZeroTier"
            "$env:LocalAppData\ZeroTier"
        )

        foreach ($targetPath in $targetFolders) {
            if (Test-Path $targetPath) {
                try {
                    takeown.exe /f "$targetPath" /r /d y 2>&1 | Out-Null
                    icacls.exe "$targetPath" /grant "${currentUser}:(F)" /t /c /q 2>&1 | Out-Null
                    Remove-Item -Path $targetPath -Recurse -Force -ErrorAction Stop
                } catch {}
            }
        }

        &$report "5/5 Bereinige Registry-Einträge..." 95
        $regPaths = @(
            "HKLM:\SOFTWARE\ZeroTier",
            "HKLM:\SYSTEM\CurrentControlSet\Services\ZeroTierOneService",
            "HKCU:\SOFTWARE\ZeroTier",
            "HKLM:\SOFTWARE\WOW6432Node\ZeroTier"
        )
        foreach ($path in $regPaths) {
            if (Test-Path $path) { Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue }
        }

        &$report "Deinstallation vollständig abgeschlossen!" 100
    }
}

# ------------------------------------------------------------------------------
# OPTION 3: Netzwerk Login
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
# OPTION 4: Netzwerk Logout
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
# OPTION 5: Project Earth LAN Chat
# ------------------------------------------------------------------------------
function Invoke-InstallLanMessenger {
    Show-ProgressDialog -Title "Installation: Earth LAN Chat (LAN Messenger)" -TaskScript {
        param($report)

        $LmcUrl = "https://github.com/lanmessenger/lanmessenger/releases/download/v1.2.39/lmc-1.2.39-win32.exe"
        $InstallerPath = "$env:TEMP\lmc-installer.exe"

        &$report "1/3 Lade LAN Messenger herunter..." 25
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $LmcUrl -OutFile $InstallerPath

        &$report "2/3 Installiere LAN Messenger im Hintergrund..." 65
        $installProcess = Start-Process -FilePath $InstallerPath -ArgumentList "/S" -Wait -PassThru

        Remove-Item -Path $InstallerPath -Force -ErrorAction SilentlyContinue

        &$report "3/3 Richte Autostart ein & starte Messenger..." 90
        $possiblePaths = @(
            "$env:ProgramFiles\LAN Messenger\lmc.exe",
            "${env:ProgramFiles(x86)}\LAN Messenger\lmc.exe"
        )

        $installedExe = $null
        foreach ($path in $possiblePaths) {
            if (Test-Path $path) {
                $installedExe = $path
                break
            }
        }

        if ($installedExe) {
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "LAN Messenger" -Value "`"$installedExe`"" -ErrorAction SilentlyContinue
            Start-Process -FilePath $installedExe
            &$report "LAN Messenger erfolgreich installiert und gestartet!" 100
        } else {
            &$report "Fehler: Exe konnte nicht gefunden werden." 100
        }
    }
}

# ------------------------------------------------------------------------------
# OPTION 6: Was genau macht der Manager inklusive Impressum
# ------------------------------------------------------------------------------
function Invoke-GenerateExplanationFile {
    $DesktopPath = [System.IO.Path]::Combine($env:USERPROFILE, "Desktop")
    $TxtFile = Join-Path $DesktopPath "Was genau passiert wenn ich Project Earth LAN Manager benutze.txt"

    $explanationText = @"
================================================================================
WAS GENAU PASSIERT, WENN ICH DEN PROJECT EARTH LAN MANAGER BENUTZE?
================================================================================

--------------------------------------------------------------------------------
1. WOHER KOMMT ZEROTIER ONE UND WAS MACHT ES AUF DEM PC?
--------------------------------------------------------------------------------

Gründung: ZeroTier wurde im Januar 2011 von Adam Ierymenko ins Leben gerufen. Der Hauptsitz des Unternehmens befindet sich in den USA (Irvine/San Francisco, Kalifornien).

Hintergrund: Die Idee entstand aus der Frustration über die komplizierte, starre und fehleranfällige Konfiguration traditioneller Netzwerkinfrastrukturen und VPNs bei einem US-Behördenprojekt.

Entwicklung: Das Projekt startete als Open-Source-Initiative und hat sich im Laufe der Jahre zu einer weitverbreiteten Plattform für virtuelle Netzwerke entwickelt, die sowohl von Einzelpersonen (z. B. für Gaming oder Heimnetzwerke) als auch von Unternehmen für Cloud- und IoT-Infrastrukturen genutzt wird.

Welchen Zweck erfüllt es?

Hauptzweck: Der Hauptzweck von ZeroTier besteht darin, Geräte überall auf der Welt so miteinander zu verbinden, als befänden sie sich im selben physischen lokalen Netzwerk (LAN) – unabhängig davon, wo sie sich gerade befinden oder hinter welchen Routern (und NAT/Firewalls) sie versteckt sind.

Virtuelles Layer-2-Netzwerk: Es emuliert ein herkömmliches Ethernet-Netzwerk auf Software-Ebene. Geräte erhalten virtuelle IP-Adressen und können direkt miteinander kommunizieren.

Peer-to-Peer-Verbindungen (P2P): Sobald die Verbindung zwischen zwei Geräten hergestellt ist, läuft der Datenverkehr direkt von Punkt zu Punkt (P2P), was für geringe Latenzen sorgt. Es ist kein manuelles Port-Forwarding (Portweiterleitung) am Router nötig.

Einfachheit statt Hardware-VPN: Es ersetzt oder ergänzt komplexe, teure Hardware-VPNs durch eine schlanke Software, die auf PCs, Servern, Smartphones und Routern installiert werden kann.

Sicherheit: Alle Datenströme sind standardmäßig Ende-zu-Ende-verschlüsselt (mit modernen Standards wie ChaCha20/Curve25519). Über ein zentrales Web-Interface (ZeroTier Central) lassen sich feingranulare Zugriffsregeln und Firewall-Richtlinien (Flow Rules) definieren.
--------------------------------------------------------------------------------
3. WAS MACHT DER PROJECT EARTH LAN MANAGER?
--------------------------------------------------------------------------------
Option 1: Installiert Automatisch, ZeroTierOne und verbindet euch mit dem ZeroTierOne NetzwerK Project Earth Lan (für Lan Gaming ohne Drittanbieter,Werbefrei,Kostenlos) 
und dem Account und Verwaltungsnetzwerk um euer eigenes kostenloses
ZeroTierOne Netzwerk zu erstellen und zu Verwalten.

Option 2: Deinstalliert es Vollständig mit allen Ordnern,Netzwerk Adaptern und Einstellungen-

Option 3: Ist eine Netzwerk Login Option gebt die 16 Stellige ID des Netzwerks ein und ihr werdet verbunden,
der Adapter wird erstellt und automatisch Konfiguriert.

Option 4: Ist ein Logout Button der den Adapter löscht, euch aus dem Netzwerk ausloggt, aber eure IP beim wiederverbinden beibehält.

Option 5: Installiert den Lan Messenger ein Open Source Tool was nur in Lokalen Netzwerken funktioniert und somit auch in den von ZeroTierOne.
Aufgebaut wie der MSN Messenger mit Chat,Gruppenchat für alle die im gleichen Netzwerk sind. Teilnehmer erscheinen Automatisch.

Option 6: Erstellt diese ReadMe die alle wichtigen Infos über den Project Earth Lan Manager hat und ZeroTierOne

Option 7: Mit dem Tools,Mods, Games Downloader greift ihr automatisch auf den im Project Earth Lan befindlichen FTP Server zu wo ihr Tools,Mods und Games findet. Mit einem Button der auch die Ordner immer aktuallsiert.

Option 8: Remote Desktop Manager damit könnt ihr euer Passwort änder für euren Lokalen Account oder erstellt einen neuen mit Passwort. Damit ihr das Windows eigene Remotdesktop aktivieren und deaktivieren könnt. Falls ihr euch gegenseitig mal helfen müsst.

Option 9: Sucht auf eurem PC über 500 Spiele die Lokalen Multiplayer (LAN) haben und sammelt sie alle als Verknüpfungen in einem Ordner auf dem Desktop. Damit ihr direkt auf einer Lan oder Project Earth Lan auf eure Spiele zugreifen könn.
--------------------------------------------------------------------------------
4. WOHER KOMMT DER LAN MESSENGER UND WAS MACHT ER AUF DEM PC?
--------------------------------------------------------------------------------
Ein Open-Source-Chat ohne Serverzwang zur Kommunikation im Project Earth LAN.
--------------------------------------------------------------------------------
Impressum: Project Earht Lan
           
           Kontakt:
           Alexander Meiß
           Bahnhofstr. 28
           63549 Ronneburg Hüttengesäß
           Tel: +4915156947939
           Email: firehawk215@googlemail.com
"@

    Set-Content -Path $TxtFile -Value $explanationText -Encoding UTF8 -Force
    Write-Host "Erklärungs-Datei erfolgreich auf dem Desktop erstellt!"
    [System.Windows.Forms.MessageBox]::Show("Die Datei wurde erfolgreich auf deinem Desktop erstellt!", "Erfolg", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
}



# ------------------------------------------------------------------------------
# OPTION 7: Tools, Mods, Games
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
# OPTION 8: Windows Remotedesktop
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
# OPTION 9: LAN Game Verknüpfung in Ordner auf Desktop
# ------------------------------------------------------------------------------
function Invoke-LanGameFinder {
    # Hilfsfunktion: Verknüpfung erstellen
    function New-GameShortcut {
        param ([string]$SourcePath, [string]$DestinationFolder, [string]$ShortcutName)
        $cleanName = $ShortcutName -replace '[\\/:*?"<>|]', ''
        $shortcutPath = Join-Path -Path $DestinationFolder -ChildPath "$cleanName.lnk"
        
        $wshShell = New-Object -ComObject WScript.Shell
        $shortcut = $wshShell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $SourcePath
        $shortcut.WorkingDirectory = [System.IO.Path]::GetDirectoryName($SourcePath)
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
    $btnDriveSelect.Size = New-Object System.Drawing.Size(180, 35)
    $btnDriveSelect.Text = "Festplatten Auswählen"
    $btnDriveSelect.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $btnDriveSelect.ForeColor = [System.Drawing.Color]::White
    $btnDriveSelect.FlatStyle = "Flat"
    $btnDriveSelect.Font = $fontMain

    $btnStartScan = New-Object System.Windows.Forms.Button
    $btnStartScan.Location = New-Object System.Drawing.Point(210, 20)
    $btnStartScan.Size = New-Object System.Drawing.Size(260, 35)
    $btnStartScan.Text = "Suche Starten"
    $btnStartScan.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnStartScan.ForeColor = [System.Drawing.Color]::White
    $btnStartScan.FlatStyle = "Flat"
    $btnStartScan.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

    $btnOpenFolder = New-Object System.Windows.Forms.Button
    $btnOpenFolder.Location = New-Object System.Drawing.Point(480, 20)
    $btnOpenFolder.Size = New-Object System.Drawing.Size(240, 35)
    $btnOpenFolder.Text = "Ordner 'Lan Games' Öffnen"
    $btnOpenFolder.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $btnOpenFolder.ForeColor = [System.Drawing.Color]::White
    $btnOpenFolder.FlatStyle = "Flat"
    $btnOpenFolder.Font = $fontMain

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
    $form.Controls.Add($txtLog)

    $global:SelectedDrives = Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Root

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
            $global:SelectedDrives = $checkedListBox.CheckedItems
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

    $btnStartScan.Add_Click({
        $txtLog.Clear()
        $txtLog.AppendText("Starte Scan mit Whitelist- und Blacklist-Filter...`r`n")
        [System.Windows.Forms.Application]::DoEvents()

        $desktopPath = [System.Environment]::GetFolderPath("Desktop")
        $targetDir = Join-Path -Path $desktopPath -ChildPath "Lan Games"
        if (-not (Test-Path $targetDir)) { New-Item -Path $targetDir -ItemType Directory -Force | Out-Null } 
        else { Remove-Item -Path "$targetDir\*" -Force -Recurse -ErrorAction SilentlyContinue }

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
        $GameWhitelist = ($RawText -split ',') | ForEach-Object { $_.Trim() } | Select-Object -Unique

        $ToolBlacklist = @(
            "7-zip", "winrar", "docker", "jdownloader", "kodi", "bandicam", "total commander", 
            "sd card formatter", "driver", "tool", "update", "browser", "chrome", "firefox", 
            "edge", "java", "flash", "visual c++", "runtime", "codec", "player", "messenger", 
            "client", "server", "zerotier", "registry", "clone", "helper", "sdk", "mod", 
            "plugin", "nvidia", "amd", "intel", "realtek", "windows", "office", "dotnet", 
            "antivirus", "security", "framework", "discord", "teams", "zoom", "skype", 
            "spotify", "virtualbox", "vmware", "notepad", "vlc", "ccleaner", "steamworks shared, Worldbuilder, level editor,unrealed,testapp"
        )

        $AllDiscoveredGames = @()

        $steamReg = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -Name "InstallPath" -ErrorAction SilentlyContinue
        if ($null -ne $steamReg -and $null -ne $steamReg.InstallPath) {
            $steamLibs = @( (Join-Path $steamReg.InstallPath "steamapps") )
            $vdfPath = Join-Path $steamReg.InstallPath "steamapps\libraryfolders.vdf"
            if (Test-Path $vdfPath) {
                $vdfContent = Get-Content $vdfPath -ErrorAction SilentlyContinue
                foreach ($line in $vdfContent) {
                    if ($line -match '"path"\s+"([^"]+)"') {
                        $steamLibs += Join-Path ($matches[1] -replace '\\\\', '\') "steamapps"
                    }
                }
            }
            foreach ($lib in $steamLibs) {
                $commonPath = Join-Path $lib "common"
                if (Test-Path $commonPath) {
                    foreach ($sg in (Get-ChildItem -Path $commonPath -Directory -Force -ErrorAction SilentlyContinue)) {
                        $AllDiscoveredGames += [PSCustomObject]@{ Name = $sg.Name; Path = $sg.FullName; Source = "Steam" }
                    }
                }
            }
        }

        $epicManifestPath = "C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests"
        if (Test-Path $epicManifestPath) {
            foreach ($file in (Get-ChildItem -Path $epicManifestPath -Filter "*.item" -Force -ErrorAction SilentlyContinue)) {
                try {
                    $json = Get-Content $file.FullName -Raw | ConvertFrom-Json
                    if ($null -ne $json.DisplayName -and $null -ne $json.InstallLocation) {
                        $AllDiscoveredGames += [PSCustomObject]@{ Name = $json.DisplayName; Path = $json.InstallLocation; Source = "Epic" }
                    }
                } catch { }
            }
        }

        foreach ($install in (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Ubisoft\Launcher\Installs\*" -ErrorAction SilentlyContinue)) {
            if ($null -ne $install.InstallDir) {
                $AllDiscoveredGames += [PSCustomObject]@{ Name = (Split-Path $install.InstallDir -Leaf); Path = $install.InstallDir; Source = "Ubisoft" }
            }
        }
        foreach ($install in (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games\*" -ErrorAction SilentlyContinue)) {
            if ($null -ne $install.GAMENAME -and $null -ne $install.path) {
                $AllDiscoveredGames += [PSCustomObject]@{ Name = $install.GAMENAME; Path = $install.path; Source = "GOG" }
            }
        }
        foreach ($install in (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Origin Games\*" -ErrorAction SilentlyContinue)) {
            if ($null -ne $install.DisplayName -and $null -ne $install.InstallDir) {
                $AllDiscoveredGames += [PSCustomObject]@{ Name = $install.DisplayName; Path = $install.InstallDir; Source = "EA App" }
            }
        }

        foreach ($drive in $global:SelectedDrives) {
            foreach ($dir in @((Join-Path $drive "Games"), (Join-Path $drive "Spiele"), (Join-Path $drive "Program Files\ElAmigos"), (Join-Path $drive "Program Files (x86)\ElAmigos"))) {
                if (Test-Path $dir) {
                    foreach ($sd in (Get-ChildItem -Path $dir -Directory -Force -ErrorAction SilentlyContinue)) {
                        $AllDiscoveredGames += [PSCustomObject]@{ Name = $sd.Name; Path = $sd.FullName; Source = "CustomDir" }
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
            $AllDiscoveredGames += [PSCustomObject]@{ Name = $app.DisplayName; Path = $app.InstallLocation; Source = "Registry" }
        }

        $txtLog.AppendText("Wende Whitelist & Blacklist an und erstelle Verknüpfungen...`r`n")
        [System.Windows.Forms.Application]::DoEvents()
        
        $gamesCount = 0
        $processedPaths = @()
        $processedNames = @()

        foreach ($gameObj in $AllDiscoveredGames) {
            if ([string]::IsNullOrWhiteSpace($gameObj.Path)) { continue }
            $cleanPath = $gameObj.Path.TrimEnd('\')
            if ($processedPaths -contains $cleanPath) { continue }
            if ($processedNames -contains $gameObj.Name.ToLower()) { continue }

            $isBlacklisted = $false
            foreach ($bad in $ToolBlacklist) {
                if ($gameObj.Name -like "*$bad*") { $isBlacklisted = $true; break }
            }
            if ($isBlacklisted) { continue }

            if ($gameObj.Source -ne "Steam" -and $gameObj.Source -ne "Epic" -and $gameObj.Source -ne "Ubisoft" -and $gameObj.Source -ne "GOG" -and $gameObj.Source -ne "EA App") {
                $isWhitelisted = $false
                foreach ($good in $GameWhitelist) {
                    if ($gameObj.Name -like "*$good*") { $isWhitelisted = $true; break }
                }
                if (-not $isWhitelisted) { continue }
            }

            $driveMatch = $false
            foreach ($drive in $global:SelectedDrives) {
                if ($cleanPath.StartsWith($drive, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $driveMatch = $true; break
                }
            }
            if (-not $driveMatch) { continue }

            if (Test-Path $cleanPath) {
                $blacklistPattern = ($ToolBlacklist | ForEach-Object { [regex]::Escape($_) }) -join '|'

                $exes = Get-ChildItem -Path $cleanPath -Filter "*.exe" -Recurse -Force -ErrorAction SilentlyContinue |
                        Where-Object { 
                            $_.Name -notmatch "(?i)unins|setup|dxweb|crash|report|redist|launcher|config|updater|dxsetup|vcredist|dotnet|worldbuilder|editor" -and
                            ($blacklistPattern -eq '' -or $_.Name -notmatch "(?i)$blacklistPattern")
                        }
                
                if ($null -ne $exes) {
                    $mainExe = $exes | Sort-Object Length -Descending | Select-Object -First 1
                    if ($null -ne $mainExe) {
                        $txtLog.AppendText("[$($gameObj.Source)] Übernommen: $($gameObj.Name)`r`n")
                        New-GameShortcut -SourcePath $mainExe.FullName -DestinationFolder $targetDir -ShortcutName $gameObj.Name
                        $processedPaths += $cleanPath
                        $processedNames += $gameObj.Name.ToLower()
                        $gamesCount++
                        [System.Windows.Forms.Application]::DoEvents()
                    }
                }
            }
        }

        $txtLog.AppendText("`r`nFertig! Es wurden $gamesCount saubere LAN-Spiele verknüpft.`r`n")
    })

    [void]$form.ShowDialog()
}

# ------------------------------------------------------------------------------
# OPTION 10: Manuelle Game Suche (dynamisch, systemweit, inkl. versteckter Dateien)
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
    $excludePattern = "(?i)unins|setup|dxweb|crash|report|redist|launcher|config|updater|dxsetup|vcredist|dotnet|worldbuilder|editor"

    # --- Hilfsfunktionen -------------------------------------------------------
    function Get-LanGamesFolder {
        $desktopPath = [System.Environment]::GetFolderPath("Desktop")
        $path = Join-Path -Path $desktopPath -ChildPath "Lan Games"
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -Path $path -ItemType Directory -Force | Out-Null
        }
        return $path
    }

    function Find-MainExe {
        param ([string]$FolderPath)
        $all = @(Get-ChildItem -LiteralPath $FolderPath -Filter "*.exe" -Recurse -Force -ErrorAction SilentlyContinue)
        if ($all.Count -eq 0) { return $null }
        $good = @($all | Where-Object { $_.Name -notmatch $excludePattern })
        if ($good.Count -gt 0) {
            return ($good | Sort-Object Length -Descending | Select-Object -First 1).FullName
        }
        return ($all | Sort-Object Length -Descending | Select-Object -First 1).FullName
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
# OPTION 11: Server-Manager, Game Server Browser & P2P Chat (Port 9872)
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
    private static readonly int[] GamespyPorts = new int[] { 27888, 27889, 7778, 23000 };

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
                EarthServerHit h = new EarthServerHit();
                h.Ip = ip.ToString();
                h.Port = port;
                h.Protocol = "UDP (A2S)";
                h.Key = "a2s";
                h.Game = game;
                h.Folder = folder;
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
    $joinMapFile = Join-Path $env:APPDATA 'ProjectEarthLan\joinmap.json'
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
    function Get-AdapterList {
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
                $list.Add([pscustomobject]@{
                    Name        = $nic.Name
                    Description = $nic.Description
                    Ip          = $ip
                    Mask        = $mask
                    IsZeroTier  = [bool](($nic.Description -match 'ZeroTier') -or ($nic.Name -match 'ZeroTier'))
                })
            }
        }
        return $list
    }

    function Select-NetworkAdapter {
        $adapters = @(Get-AdapterList)
        if ($adapters.Count -eq 0) {
            Show-Msg "Es wurde kein aktiver IPv4-Netzwerkadapter gefunden." "Netzwerkadapter" ([System.Windows.Forms.MessageBoxIcon]::Warning)
            return $null
        }
        $dlg = New-Object System.Windows.Forms.Form
        $dlg.Text = "Netzwerkadapter wählen"
        $dlg.Size = New-Object System.Drawing.Size(700, 380)
        $dlg.StartPosition = "CenterParent"
        $dlg.FormBorderStyle = "FixedDialog"
        $dlg.MaximizeBox = $false
        $dlg.MinimizeBox = $false
        $dlg.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
        $dlg.ForeColor = $cWhite

        $lblHint = New-DkLabel "Adapter für LAN/ZeroTier auswählen (ZeroTier-Adapter sind grün markiert):" 12 12 660 22
        $lv = New-DkListView 12 40 660 240 @('Adapter','Beschreibung','IPv4','Maske') @(150,260,120,110)
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
                if ($a.IsZeroTier) { $preselect = $it }
                elseif ($state.Adapter -and $state.Adapter.Ip -eq $a.Ip) { $preselect = $it }
            }
        }
        if (-not $preselect) { $preselect = $lv.Items[0] }
        $preselect.Selected = $true

        $btnOk = New-DkButton "Übernehmen" 400 295 130 34 $true
        $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $btnCancel = New-DkButton "Abbrechen" 542 295 130 34
        $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $lv.Add_DoubleClick({ $btnOk.PerformClick() })
        $dlg.AcceptButton = $btnOk
        $dlg.CancelButton = $btnCancel
        $dlg.Controls.AddRange(@($lblHint, $lv, $btnOk, $btnCancel))

        $result = $null
        if ($dlg.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
            if ($lv.SelectedItems.Count -gt 0) { $result = $lv.SelectedItems[0].Tag }
        }
        $dlg.Dispose()
        return $result
    }

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
        if ($state.Node -or $state.Panel -eq 2) { Start-LanNode }
    }

    function Invoke-AdapterButton {
        $sel = Select-NetworkAdapter
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
            [void]$it.SubItems.Add([string]$h.Port)
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
                $sel = Select-NetworkAdapter
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
    function Save-JoinMap {
        try {
            $dir = Split-Path -Parent $joinMapFile
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
            $state.JoinMap | ConvertTo-Json | Set-Content -LiteralPath $joinMapFile -Encoding UTF8
        } catch { }
    }

    function Get-GameProfile($hit) {
        $p = $null
        if ($hit.Key -eq 'a2s') {
            if ($hit.Port -ge 27015 -and $hit.Port -le 27030) { $p = $gameProfiles | Where-Object { $_.Key -eq 'source' } | Select-Object -First 1 }
        } elseif ($hit.Key) {
            $p = $gameProfiles | Where-Object { $_.Key -eq $hit.Key } | Select-Object -First 1
        }
        if (-not $p) { $p = $gameProfiles | Where-Object { $_.Ports -contains [int]$hit.Port } | Select-Object -First 1 }
        if (-not $p) { $p = $genericProfile }
        return $p
    }

    function ConvertTo-NormName([string]$s) {
        if (-not $s) { return '' }
        return ($s.ToLower() -replace '[^a-z0-9]', '')
    }

    function Get-SteamCommonFolders {
        $paths = @()
        $steam = $null
        try { $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath } catch { }
        if (-not $steam) { try { $steam = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction SilentlyContinue).InstallPath } catch { } }
        if ($steam) {
            $steam = $steam -replace '/', '\'
            $paths += (Join-Path $steam 'steamapps\common')
            $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
            if (Test-Path -LiteralPath $vdf) {
                foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) {
                    $lib = $m.Groups[1].Value -replace '\\\\', '\'
                    $paths += (Join-Path $lib 'steamapps\common')
                }
            }
        }
        return @($paths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -Unique)
    }

    function Get-GameCandidates {
        $cands = [System.Collections.Generic.List[object]]::new()

        # 1. Verknüpfungen im Ordner "Lan Games" (Option 9/10)
        $lanFolder = Join-Path ([System.Environment]::GetFolderPath('Desktop')) 'Lan Games'
        if (Test-Path -LiteralPath $lanFolder) {
            $wsh = New-Object -ComObject WScript.Shell
            foreach ($lnk in @(Get-ChildItem -LiteralPath $lanFolder -Filter '*.lnk' -ErrorAction SilentlyContinue)) {
                try {
                    $target = $wsh.CreateShortcut($lnk.FullName).TargetPath
                    if ($target -and (Test-Path -LiteralPath $target -PathType Leaf)) {
                        $cands.Add([pscustomobject]@{ Name = $lnk.BaseName; Dir = (Split-Path -Parent $target); Exe = $target })
                    }
                } catch { }
            }
        }

        # 2. Steam-Bibliotheken
        foreach ($lib in @(Get-SteamCommonFolders)) {
            foreach ($d in @(Get-ChildItem -LiteralPath $lib -Directory -ErrorAction SilentlyContinue)) {
                $cands.Add([pscustomobject]@{ Name = $d.Name; Dir = $d.FullName; Exe = $null })
            }
        }

        # 3. Epic Games
        $epicDir = Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'
        if (Test-Path -LiteralPath $epicDir) {
            foreach ($mf in @(Get-ChildItem -LiteralPath $epicDir -Filter '*.item' -ErrorAction SilentlyContinue)) {
                try {
                    $j = Get-Content -LiteralPath $mf.FullName -Raw | ConvertFrom-Json
                    if ($j.DisplayName -and $j.InstallLocation) {
                        $exe = $null
                        if ($j.LaunchExecutable) {
                            $ce = Join-Path $j.InstallLocation $j.LaunchExecutable
                            if (Test-Path -LiteralPath $ce) { $exe = $ce }
                        }
                        $cands.Add([pscustomobject]@{ Name = $j.DisplayName; Dir = $j.InstallLocation; Exe = $exe })
                    }
                } catch { }
            }
        }

        # 4. Installierte Programme (GOG, Uninstall-Registry)
        $regPaths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
        foreach ($rp in $regPaths) {
            foreach ($e in @(Get-ItemProperty -Path $rp -ErrorAction SilentlyContinue)) {
                if ($e.DisplayName -and $e.InstallLocation -and (Test-Path -LiteralPath $e.InstallLocation)) {
                    $cands.Add([pscustomobject]@{ Name = $e.DisplayName; Dir = $e.InstallLocation; Exe = $null })
                }
            }
        }

        # 5. Übliche Spielordner auf allen festen Laufwerken
        foreach ($drv in [System.IO.DriveInfo]::GetDrives()) {
            if ($drv.DriveType -ne 'Fixed' -or -not $drv.IsReady) { continue }
            foreach ($rel in @('Games','Spiele','XboxGames','GOG Games','Epic Games','SteamLibrary\steamapps\common','Program Files','Program Files (x86)')) {
                $base = Join-Path $drv.RootDirectory.FullName $rel
                if (Test-Path -LiteralPath $base) {
                    foreach ($d in @(Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue)) {
                        $cands.Add([pscustomobject]@{ Name = $d.Name; Dir = $d.FullName; Exe = $null })
                    }
                }
            }
        }
        return $cands
    }

    function Find-BestCandidate($cands, [string[]]$phrases) {
        $best = $null
        $bestScore = 0
        foreach ($c in $cands) {
            $cn = ConvertTo-NormName $c.Name
            if ($cn.Length -lt 3) { continue }
            foreach ($ph in $phrases) {
                $pn = ConvertTo-NormName $ph
                if ($pn.Length -lt 3) { continue }
                $score = 0
                if ($cn -eq $pn) { $score = 100 }
                elseif ($cn.Contains($pn) -or ($cn.Length -ge 5 -and $pn.Contains($cn))) { $score = 90 }
                else {
                    $tokens = @(($ph.ToLower() -split '[^a-z0-9]+') | Where-Object { $_.Length -ge 3 })
                    if ($tokens.Count -gt 0) {
                        $hits = 0
                        foreach ($tk in $tokens) { if ($cn.Contains($tk)) { $hits++ } }
                        if ($hits -eq $tokens.Count) { $score = 70 }
                    }
                }
                if ($score -gt $bestScore) { $best = $c; $bestScore = $score }
            }
        }
        return $best
    }

    function Find-GameMainExe([string]$dir, [string[]]$preferred) {
        $excl = '(?i)unins|setup|dxweb|crash|report|redist|launcher|config|updater|dxsetup|vcredist|dotnet|editor|server|srcds|dedicated|benchmark|easyanticheat|helper|installer|patch|cef'
        $all = @(Get-ChildItem -LiteralPath $dir -Filter '*.exe' -Recurse -Depth 4 -Force -ErrorAction SilentlyContinue)
        if ($all.Count -eq 0) { return $null }
        foreach ($pn in $preferred) {
            $m = $all | Where-Object { $_.Name -ieq $pn } | Select-Object -First 1
            if ($m) { return $m.FullName }
        }
        $good = @($all | Where-Object { $_.Name -notmatch $excl })
        if ($good.Count -gt 0) { return ($good | Sort-Object Length -Descending | Select-Object -First 1).FullName }
        return ($all | Sort-Object Length -Descending | Select-Object -First 1).FullName
    }

    function Invoke-JoinHit($hit) {
        $gp = Get-GameProfile $hit
        $addr = "$($hit.Ip):$($hit.Port)"
        $argText = ([string]$gp.Args).Replace('{IP}', [string]$hit.Ip).Replace('{PORT}', [string]$hit.Port)

        # URI-basierte Spiele (z. B. Minecraft Bedrock, FiveM)
        if ($gp.Uri) {
            $uri = ([string]$gp.Uri).Replace('{IP}', [string]$hit.Ip).Replace('{PORT}', [string]$hit.Port)
            try { Start-Process $uri } catch { Show-Msg "Spiel-Protokoll konnte nicht gestartet werden:`n$uri`n$($_.Exception.Message)" "Join" ([System.Windows.Forms.MessageBoxIcon]::Error) }
            return
        }

        $mapKey = "$($gp.Key)|$($hit.Game)"
        $exe = $null
        if ($state.JoinMap.ContainsKey($mapKey) -and (Test-Path -LiteralPath $state.JoinMap[$mapKey])) {
            $exe = $state.JoinMap[$mapKey]
        }

        if (-not $exe) {
            $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
            try {
                $lblScan.Text = "Suche passende Spiel.exe ..."
                [System.Windows.Forms.Application]::DoEvents()
                $rawPhrases = @(@($hit.Game, $hit.Folder) + @($gp.Hints) | Where-Object { $_ })
                $phrases = @()
                foreach ($rp in $rawPhrases) {
                    $phrases += $rp
                    $cleanP = (([string]$rp) -replace '(?i)\b(dedicated|server|srv|dedizierter)\b', ' ' -replace '[-_]+', ' ' -replace '\s+', ' ').Trim()
                    if ($cleanP -and $cleanP -ne $rp) { $phrases += $cleanP }
                }
                if ($phrases.Count -gt 0) {
                    $cands = Get-GameCandidates
                    $best = Find-BestCandidate $cands ([string[]]$phrases)
                    if ($best) {
                        if ($best.Exe) { $exe = $best.Exe }
                        else { $exe = Find-GameMainExe $best.Dir ([string[]]$gp.ExeNames) }
                    }
                }
            } finally {
                $form.Cursor = [System.Windows.Forms.Cursors]::Default
            }
        }

        if (-not $exe) {
            $steamOk = Test-Path 'HKCU:\Software\Valve\Steam'
            if ($gp.SteamConnect -and $steamOk) {
                try { Start-Process ("steam://connect/" + $addr); return } catch { }
            }
            $ofd = New-Object System.Windows.Forms.OpenFileDialog
            $ofd.Title = "Spiel-EXE für '$($hit.Game)' auswählen (wird gemerkt)"
            $ofd.Filter = "Programme (*.exe)|*.exe|Alle Dateien (*.*)|*.*"
            if ($ofd.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
            $exe = $ofd.FileName
        }

        $state.JoinMap[$mapKey] = $exe
        Save-JoinMap

        try {
            $sp = @{ FilePath = $exe; WorkingDirectory = (Split-Path -Parent $exe) }
            if ($argText) { $sp.ArgumentList = $argText }
            Start-Process @sp
            $lblScan.Text = "Gestartet: $([System.IO.Path]::GetFileName($exe)) -> $addr"
            if (-not $argText) {
                try { [System.Windows.Forms.Clipboard]::SetText($addr) } catch { }
                Show-Msg "Das Spiel wurde gestartet.`nFür dieses Spiel ist kein automatischer Verbindungsparameter bekannt - die Server-Adresse '$addr' liegt in der Zwischenablage (Direktverbindung im Spiel einfügen)." "Join"
            }
        } catch {
            Show-Msg "Spiel konnte nicht gestartet werden:`n$exe`n$($_.Exception.Message)" "Join" ([System.Windows.Forms.MessageBoxIcon]::Error)
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
    $form.Text = "Server-Manager, Game Server Browser & P2P Chat"
    $form.Size = New-Object System.Drawing.Size(1010, 730)
    $form.StartPosition = "CenterParent"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
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
        $panels += $p
    }
    $pnlBrowser = $panels[0]
    $pnlManager = $panels[1]
    $pnlP2P     = $panels[2]

    # ---- Panel 1: Game Server Browser ------------------------------------------------
    $btnAdapter1 = New-DkButton "1. Netzwerkadapter wählen" 0 0 240 36
    $btnScan     = New-DkButton "2. Server Browser (Game-Ports scannen)" 250 0 330 36 $true
    $btnScanStop = New-DkButton "Stopp" 590 0 90 36
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
    $lblCount = New-DkLabel "Gefundene Einträge: 0" 545 534 300 22
    $lblNote = New-DkLabel "Ignoriert werden Windows-, Linux- und macOS-Systemports (SMB, RDP, SSH, mDNS, AirPlay ...). UDP-Server werden nur erkannt, wenn sie auf ein bekanntes Abfrageprotokoll antworten (Source/A2S, Minecraft Bedrock, Quake3); TCP-Ports werden über die Spiel-Tabelle zugeordnet." 0 572 960 50
    $lblNote.ForeColor = [System.Drawing.Color]::LightGray
    $pnlBrowser.Controls.AddRange(@($btnAdapter1, $btnScan, $btnScanStop, $chkFull, $chkUnknown, $chkDeep, $lblScan, $pbScan, $lblManIp, $txtManIp, $lblManPort, $txtManPorts, $btnManIp, $btnManSubnet, $btnManPort, $lvHits, $btnJoin, $btnCopy, $lblCount, $lblNote))

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
    $chkShare = New-DkCheck "Meine lokalen Server mit anderen Managern teilen (Server-Listen-Austausch)" 0 202 700 $true
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
    $pnlP2P.Controls.AddRange(@($btnAdapter3, $lblIp, $txtIp, $btnConnect, $btnNetScan, $btnChat, $lblNode, $lvPeers, $chkShare, $lblChatHint, $rtbChat, $txtChat, $btnSend))

    $form.Controls.AddRange(@($btnNav0, $btnNav1, $btnNav2, $lblAdapter, $pnlBrowser, $pnlManager, $pnlP2P))

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
    $btnAdapter1.Add_Click({ Invoke-AdapterButton })
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
        try { [System.Windows.Forms.Clipboard]::SetText("$($t.Ip):$($t.Port)") } catch { }
        $lblScan.Text = "Kopiert: $($t.Ip):$($t.Port)"
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
    if (Test-Path -LiteralPath $joinMapFile) {
        try {
            $obj = Get-Content -LiteralPath $joinMapFile -Raw | ConvertFrom-Json
            foreach ($prop in $obj.PSObject.Properties) { $state.JoinMap[$prop.Name] = [string]$prop.Value }
        } catch { }
    }
    Show-Panel 0
    [void]$form.ShowDialog()

    $mainTimer.Dispose()
}


# ------------------------------------------------------------------------------
# OPTION 12: Voice Chat (eigene Kanäle, Privat, Gruppen, Passwort-Kanäle)
# ------------------------------------------------------------------------------
function Invoke-VoiceChat {

    # --- C#-Kern: Audio (winmm), UDP-Netzwerk, Kanalverwaltung --------------------------
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
using System.Text;
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
    public const int VoicePort = 9873;
    public string NodeId;
    public string NodeName;
    public ConcurrentQueue<string> Events = new ConcurrentQueue<string>();
    public volatile bool MicMuted;
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
                Reconcile();
                Prune();
            }
            catch (Exception) { }
            tick++;
            for (int i = 0; i < 20 && running; i++) Thread.Sleep(100);
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
                if (data.Length > 15 && data[0] == 0xA1) HandleAudio(data);
                else if (data.Length > 4 && data[0] == (byte)'P') HandleControl(Encoding.UTF8.GetString(data), ep.Address.ToString());
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
                l.Add(p.Id + "|" + p.Name + "|" + p.Ip + "|" + p.Chan + "|" + (p.Locked ? "1" : "0") + "|" + (members.ContainsKey(p.Id) ? "1" : "0") + "|" + ((now - p.LastAudio) < 400 ? "1" : "0"));
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
        if (!MicMuted && rms > Threshold) lastVoiceTick = now;
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
                int len = Math.Min(fr.Length, n);
                for (int i = 0; i < len; i++) acc[i] += fr[i];
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

    # --- Zustand ------------------------------------------------------------------------
    $state = @{
        Node      = $null
        PeerItems = @{}
        ChanItems = @{}
        Tick      = 0
        FwRule    = $false
        InDev     = -1
        OutDev    = -1
        InName    = ''
        OutName   = ''
    }
    $cfgFile = Join-Path $env:APPDATA 'ProjectEarthLan\voice.json'
    $fwName  = 'Project Earth LAN Voice 9873'

    $cWhite  = [System.Drawing.Color]::White
    $cAccent = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $cBtn    = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $cInput  = [System.Drawing.Color]::FromArgb(50, 50, 50)
    $cList   = [System.Drawing.Color]::FromArgb(40, 40, 40)
    $fontMain = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Regular)
    $fontBold = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

    # --- GUI-Hilfsfunktionen --------------------------------------------------------------
    function New-VcButton([string]$text, [int]$x, [int]$y, [int]$w, [int]$h, [bool]$accent = $false) {
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

    function New-VcLabel([string]$text, [int]$x, [int]$y, [int]$w, [int]$h) {
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $text
        $l.Location = New-Object System.Drawing.Point($x, $y)
        $l.Size = New-Object System.Drawing.Size($w, $h)
        $l.ForeColor = $cWhite
        $l.Font = $fontMain
        return $l
    }

    function New-VcListView([int]$x, [int]$y, [int]$w, [int]$h, [string[]]$cols, [int[]]$widths) {
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

    function Show-VcMsg([string]$text, [string]$title = "Voice Chat", $icon = [System.Windows.Forms.MessageBoxIcon]::Information) {
        [System.Windows.Forms.MessageBox]::Show($text, $title, [System.Windows.Forms.MessageBoxButtons]::OK, $icon) | Out-Null
    }

    function Add-VcLog([string]$text) {
        $rtbLog.SelectionStart = $rtbLog.TextLength
        $rtbLog.SelectionColor = [System.Drawing.Color]::LightGray
        $rtbLog.AppendText("[" + (Get-Date).ToString("HH:mm:ss") + "] " + $text + "`r`n")
        $rtbLog.ScrollToCaret()
    }

    function Read-VcText([string]$title, [string]$prompt, [bool]$secret = $false) {
        $d = New-Object System.Windows.Forms.Form
        $d.Text = $title
        $d.Size = New-Object System.Drawing.Size(440, 180)
        $d.StartPosition = "CenterParent"
        $d.FormBorderStyle = "FixedDialog"
        $d.MaximizeBox = $false
        $d.MinimizeBox = $false
        $d.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
        $d.ForeColor = $cWhite
        $l = New-VcLabel $prompt 14 14 400 22
        $t = New-Object System.Windows.Forms.TextBox
        $t.Location = New-Object System.Drawing.Point(14, 44)
        $t.Size = New-Object System.Drawing.Size(396, 26)
        $t.BackColor = $cInput
        $t.ForeColor = $cWhite
        $t.Font = $fontMain
        $t.UseSystemPasswordChar = $secret
        $ok = New-VcButton "OK" 210 90 90 32 $true
        $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $cn = New-VcButton "Abbrechen" 310 90 100 32
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

    function Save-VcConfig {
        try {
            $dir = Split-Path -Parent $cfgFile
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
            @{ InName = $state.InName; OutName = $state.OutName } | ConvertTo-Json | Set-Content -LiteralPath $cfgFile -Encoding UTF8
        } catch { }
    }

    function Set-VcFirewall([bool]$enable) {
        try {
            Get-NetFirewallRule -DisplayName "$fwName*" -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
            if ($enable) {
                New-NetFirewallRule -DisplayName $fwName -Direction Inbound -Action Allow -Protocol UDP -LocalPort 9873 -RemoteAddress LocalSubnet -Profile Any -ErrorAction Stop | Out-Null
                $state.FwRule = $true
            } else {
                $state.FwRule = $false
            }
        } catch { }
    }

    function Start-VcAudio {
        if (-not $state.Node) { return }
        $err = $state.Node.StartAudio([int]$state.InDev, [int]$state.OutDev)
        if ($err) { Add-VcLog "Audio-Fehler: $err" } else { Add-VcLog "Audio aktiv (Eingabe: $($state.InName) | Ausgabe: $($state.OutName))." }
    }

    function Select-VcDevices {
        $ins = [EarthWinmm]::InputDeviceNames()
        $outs = [EarthWinmm]::OutputDeviceNames()
        $d = New-Object System.Windows.Forms.Form
        $d.Text = "Sound Ein- und Ausgabe"
        $d.Size = New-Object System.Drawing.Size(520, 260)
        $d.StartPosition = "CenterParent"
        $d.FormBorderStyle = "FixedDialog"
        $d.MaximizeBox = $false
        $d.MinimizeBox = $false
        $d.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
        $d.ForeColor = $cWhite

        $l1 = New-VcLabel "Eingabegerät (Mikrofon):" 14 14 460 22
        $cbIn = New-Object System.Windows.Forms.ComboBox
        $cbIn.Location = New-Object System.Drawing.Point(14, 40)
        $cbIn.Size = New-Object System.Drawing.Size(480, 26)
        $cbIn.DropDownStyle = "DropDownList"
        $cbIn.BackColor = $cInput
        $cbIn.ForeColor = $cWhite
        $cbIn.Font = $fontMain
        foreach ($n in $ins) { [void]$cbIn.Items.Add($n) }
        $cbIn.SelectedIndex = [math]::Min([math]::Max($state.InDev + 1, 0), $cbIn.Items.Count - 1)

        $l2 = New-VcLabel "Ausgabegerät (Lautsprecher/Kopfhörer):" 14 80 460 22
        $cbOut = New-Object System.Windows.Forms.ComboBox
        $cbOut.Location = New-Object System.Drawing.Point(14, 106)
        $cbOut.Size = New-Object System.Drawing.Size(480, 26)
        $cbOut.DropDownStyle = "DropDownList"
        $cbOut.BackColor = $cInput
        $cbOut.ForeColor = $cWhite
        $cbOut.Font = $fontMain
        foreach ($n in $outs) { [void]$cbOut.Items.Add($n) }
        $cbOut.SelectedIndex = [math]::Min([math]::Max($state.OutDev + 1, 0), $cbOut.Items.Count - 1)

        $ok = New-VcButton "Übernehmen" 250 160 120 34 $true
        $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $cn = New-VcButton "Abbrechen" 380 160 114 34
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

    function Set-VcSub($item, [int]$idx, [string]$text) {
        if ($item.SubItems[$idx].Text -ne $text) { $item.SubItems[$idx].Text = $text }
    }

    function Update-VcLists {
        $node = $state.Node
        $st = ([string]$node.GetState()) -split '\|'
        $myChan = $st[0]
        $myLocked = ($st[1] -eq '1')
        $memberCount = [int]$st[2]
        if ($myChan) {
            $label = $myChan
            if ($myChan.StartsWith('@')) { $label = 'Privatgespräch' }
            $lblState.Text = "Aktiver Kanal: $label   |   Verbundene Teilnehmer: $memberCount"
        } else {
            $lblState.Text = "Aktiver Kanal: (keiner) - Kanal erstellen oder einem Kanal beitreten"
        }

        $seen = @{}
        $agg = @{}
        foreach ($ln in @($node.GetPeers())) {
            $f = $ln -split '\|'
            if ($f.Count -lt 7) { continue }
            $id = $f[0]
            $seen[$id] = $true
            $chanText = ''
            if ($f[3]) {
                if ($f[3].StartsWith('@')) { $chanText = '(privat)' } else { $chanText = $f[3] }
            }
            $status = ''
            if ($f[6] -eq '1') { $status = 'spricht' } elseif ($f[5] -eq '1') { $status = 'im Kanal' }

            if ($state.PeerItems.ContainsKey($id)) {
                $it = $state.PeerItems[$id]
                if ($it.Text -ne $f[1]) { $it.Text = $f[1] }
            } else {
                $it = New-Object System.Windows.Forms.ListViewItem($f[1])
                [void]$it.SubItems.Add($f[2])
                [void]$it.SubItems.Add($chanText)
                [void]$it.SubItems.Add($status)
                $it.Tag = $id
                [void]$lvPeers.Items.Add($it)
                $state.PeerItems[$id] = $it
            }
            Set-VcSub $it 1 $f[2]
            Set-VcSub $it 2 $chanText
            Set-VcSub $it 3 $status
            if ($f[6] -eq '1') { $it.ForeColor = [System.Drawing.Color]::LightGreen } else { $it.ForeColor = $cWhite }

            if ($f[3] -and -not $f[3].StartsWith('@')) {
                if (-not $agg.ContainsKey($f[3])) { $agg[$f[3]] = @{ N = 0; Locked = $false } }
                $agg[$f[3]].N = $agg[$f[3]].N + 1
                if ($f[4] -eq '1') { $agg[$f[3]].Locked = $true }
            }
        }
        foreach ($k in @($state.PeerItems.Keys)) {
            if (-not $seen.ContainsKey($k)) {
                $lvPeers.Items.Remove($state.PeerItems[$k])
                $state.PeerItems.Remove($k)
            }
        }

        if ($myChan -and -not $myChan.StartsWith('@')) {
            if (-not $agg.ContainsKey($myChan)) { $agg[$myChan] = @{ N = 0; Locked = $myLocked } }
            $agg[$myChan].N = $agg[$myChan].N + 1
            if ($myLocked) { $agg[$myChan].Locked = $true }
        }

        foreach ($name in @($agg.Keys)) {
            $prot = 'offen'
            if ($agg[$name].Locked) { $prot = 'Passwort' }
            $active = ''
            if ($name -eq $myChan) { $active = 'aktiv' }
            if ($state.ChanItems.ContainsKey($name)) {
                $ci = $state.ChanItems[$name]
            } else {
                $ci = New-Object System.Windows.Forms.ListViewItem($name)
                [void]$ci.SubItems.Add('')
                [void]$ci.SubItems.Add('')
                [void]$ci.SubItems.Add('')
                $ci.Tag = $name
                [void]$lvChans.Items.Add($ci)
                $state.ChanItems[$name] = $ci
            }
            Set-VcSub $ci 1 ([string]$agg[$name].N)
            Set-VcSub $ci 2 $prot
            Set-VcSub $ci 3 $active
            if ($active) { $ci.ForeColor = [System.Drawing.Color]::LightGreen } else { $ci.ForeColor = $cWhite }
        }
        foreach ($k in @($state.ChanItems.Keys)) {
            if (-not $agg.ContainsKey($k)) {
                $lvChans.Items.Remove($state.ChanItems[$k])
                $state.ChanItems.Remove($k)
            }
        }
    }

    # ===================================================================================
    # GUI
    # ===================================================================================
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Project Earth LAN - Voice Chat"
    $form.Size = New-Object System.Drawing.Size(1010, 720)
    $form.StartPosition = "CenterParent"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $form.ForeColor = $cWhite

    $btn1 = New-VcButton "1. Kanal erstellen" 12 10 188 38 $true
    $btn2 = New-VcButton "2. Privat sprechen" 208 10 188 38
    $btn3 = New-VcButton "3. Gruppen-Voice-Chat" 404 10 188 38 $true
    $btn4 = New-VcButton "4. Passwort-Kanal" 600 10 188 38
    $btn5 = New-VcButton "5. Sound Ein/Aus" 796 10 188 38

    $lblState = New-VcLabel "Aktiver Kanal: (keiner)" 12 60 760 22
    $btnLeave = New-VcButton "Kanal verlassen" 796 54 188 32

    $lblChans = New-VcLabel "Kanäle im Netzwerk:" 12 92 300 20
    $lblPeers = New-VcLabel "Teilnehmer:" 492 92 300 20
    $lvChans = New-VcListView 12 114 470 190 @('Kanal','Teilnehmer','Schutz','Status') @(200,90,90,70)
    $lvPeers = New-VcListView 492 114 492 190 @('Name','IP-Adresse','Kanal','Status') @(160,110,130,80)

    $rtbLog = New-Object System.Windows.Forms.RichTextBox
    $rtbLog.Location = New-Object System.Drawing.Point(12, 314)
    $rtbLog.Size = New-Object System.Drawing.Size(972, 190)
    $rtbLog.ReadOnly = $true
    $rtbLog.BackColor = $cList
    $rtbLog.ForeColor = $cWhite
    $rtbLog.Font = $fontMain

    $chkMute = New-Object System.Windows.Forms.CheckBox
    $chkMute.Text = "Mikrofon stumm"
    $chkMute.Location = New-Object System.Drawing.Point(12, 514)
    $chkMute.Size = New-Object System.Drawing.Size(170, 24)
    $chkMute.ForeColor = $cWhite
    $chkMute.Font = $fontMain

    $chkDeaf = New-Object System.Windows.Forms.CheckBox
    $chkDeaf.Text = "Ton aus (Ausgabe stumm)"
    $chkDeaf.Location = New-Object System.Drawing.Point(200, 514)
    $chkDeaf.Size = New-Object System.Drawing.Size(220, 24)
    $chkDeaf.ForeColor = $cWhite
    $chkDeaf.Font = $fontMain

    $lblLevel = New-VcLabel "Mikro-Pegel:" 440 517 90 20
    $pbLevel = New-Object System.Windows.Forms.ProgressBar
    $pbLevel.Location = New-Object System.Drawing.Point(535, 516)
    $pbLevel.Size = New-Object System.Drawing.Size(449, 18)
    $pbLevel.Minimum = 0
    $pbLevel.Maximum = 100

    $lblSens = New-VcLabel "Empfindlichkeit (Schwelle):" 12 555 190 20
    $tbSens = New-Object System.Windows.Forms.TrackBar
    $tbSens.Location = New-Object System.Drawing.Point(205, 548)
    $tbSens.Size = New-Object System.Drawing.Size(240, 45)
    $tbSens.Minimum = 50
    $tbSens.Maximum = 3000
    $tbSens.TickFrequency = 500
    $tbSens.Value = 350

    $lblVol = New-VcLabel "Lautstärke:" 480 555 90 20
    $tbVol = New-Object System.Windows.Forms.TrackBar
    $tbVol.Location = New-Object System.Drawing.Point(575, 548)
    $tbVol.Size = New-Object System.Drawing.Size(240, 45)
    $tbVol.Minimum = 0
    $tbVol.Maximum = 200
    $tbVol.TickFrequency = 25
    $tbVol.Value = 100

    $lblIp = New-VcLabel "Teilnehmer per IP hinzufügen (falls die automatische Suche nichts findet):" 12 606 520 20
    $txtIp = New-Object System.Windows.Forms.TextBox
    $txtIp.Location = New-Object System.Drawing.Point(540, 603)
    $txtIp.Size = New-Object System.Drawing.Size(150, 26)
    $txtIp.BackColor = $cInput
    $txtIp.ForeColor = $cWhite
    $txtIp.Font = $fontMain
    $btnIpAdd = New-VcButton "Hinzufügen" 700 598 140 34

    $lblHint = New-VcLabel "Tipp: Für Sprachchat ein Headset benutzen (keine Echo-Unterdrückung). Sprache wird nur an Teilnehmer deines Kanals gesendet." 12 645 972 20
    $lblHint.ForeColor = [System.Drawing.Color]::LightGray

    $form.Controls.AddRange(@($btn1, $btn2, $btn3, $btn4, $btn5, $lblState, $btnLeave, $lblChans, $lblPeers, $lvChans, $lvPeers, $rtbLog, $chkMute, $chkDeaf, $lblLevel, $pbLevel, $lblSens, $tbSens, $lblVol, $tbVol, $lblIp, $txtIp, $btnIpAdd, $lblHint))

    # ---- Ereignisse ------------------------------------------------------------------------
    # Button 1: eigenen (öffentlichen) Kanal erstellen
    $btn1.Add_Click({
        $name = Read-VcText "Kanal erstellen" "Name des neuen Kanals:"
        if (-not $name) { return }
        $err = $state.Node.CreateChannel($name, '')
        if ($err) { Show-VcMsg $err } else { Add-VcLog "Kanal '$name' erstellt und betreten." }
    })

    # Button 2: privat sprechen (1:1) mit dem markierten Teilnehmer
    $btn2.Add_Click({
        if ($lvPeers.SelectedItems.Count -eq 0) {
            Show-VcMsg "Bitte zuerst rechts einen Teilnehmer auswählen, mit dem du privat sprechen willst."
            return
        }
        $err = $state.Node.Call([string]$lvPeers.SelectedItems[0].Tag)
        if ($err) { Show-VcMsg $err }
    })
    $lvPeers.Add_DoubleClick({ $btn2.PerformClick() })

    # Button 3: Gruppen-Voice-Chat (markiertem Kanal beitreten)
    $btn3.Add_Click({
        if ($lvChans.SelectedItems.Count -eq 0) {
            Show-VcMsg "Bitte zuerst links einen Kanal auswählen (oder mit Button 1 einen neuen erstellen)."
            return
        }
        $it = $lvChans.SelectedItems[0]
        $name = [string]$it.Tag
        if ($it.SubItems[3].Text -eq 'aktiv') { Show-VcMsg "Du bist bereits in diesem Kanal."; return }
        $pw = ''
        if ($it.SubItems[2].Text -eq 'Passwort') {
            $pw = Read-VcText "Passwort-Kanal" "Passwort für Kanal '$name':" $true
            if ($null -eq $pw) { return }
        }
        $err = $state.Node.JoinChannel($name, $pw)
        if ($err) { Show-VcMsg $err } else { Add-VcLog "Trete Kanal '$name' bei ..." }
    })
    $lvChans.Add_DoubleClick({ $btn3.PerformClick() })

    # Button 4: passwortgeschützten Kanal erstellen
    $btn4.Add_Click({
        $name = Read-VcText "Passwort-Kanal erstellen" "Name des neuen Kanals:"
        if (-not $name) { return }
        $pw1 = Read-VcText "Passwort-Kanal erstellen" "Passwort festlegen:" $true
        if (-not $pw1) { return }
        $pw2 = Read-VcText "Passwort-Kanal erstellen" "Passwort wiederholen:" $true
        if ($pw1 -ne $pw2) { Show-VcMsg "Die Passwörter stimmen nicht überein."; return }
        $err = $state.Node.CreateChannel($name, $pw1)
        if ($err) { Show-VcMsg $err } else { Add-VcLog "Passwort-Kanal '$name' erstellt und betreten." }
    })

    # Button 5: Sound-Ein- und Ausgabe wählen
    $btn5.Add_Click({
        $sel = Select-VcDevices
        if (-not $sel) { return }
        $state.InDev = [int]$sel.In
        $state.OutDev = [int]$sel.Out
        $state.InName = [string]$sel.InName
        $state.OutName = [string]$sel.OutName
        Save-VcConfig
        Start-VcAudio
    })

    $btnLeave.Add_Click({
        $state.Node.LeaveChannel()
        Add-VcLog "Kanal verlassen."
    })

    $chkMute.Add_CheckedChanged({ if ($state.Node) { $state.Node.MicMuted = [bool]$chkMute.Checked } })
    $chkDeaf.Add_CheckedChanged({ if ($state.Node) { $state.Node.Deafened = [bool]$chkDeaf.Checked } })
    $tbSens.Add_ValueChanged({ if ($state.Node) { $state.Node.Threshold = [int]$tbSens.Value } })
    $tbVol.Add_ValueChanged({ if ($state.Node) { $state.Node.VolumePercent = [int]$tbVol.Value } })

    $btnIpAdd.Add_Click({
        $parsed = $null
        $ipText = $txtIp.Text.Trim()
        if (-not [System.Net.IPAddress]::TryParse($ipText, [ref]$parsed) -or $parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
            Show-VcMsg "Bitte eine gültige IPv4-Adresse eingeben (z. B. 10.147.17.5)."
            return
        }
        $state.Node.AddManualPeer($ipText)
        Add-VcLog "Teilnehmer $ipText hinzugefügt."
    })

    # ---- Timer: Ereignisse, Listen, Pegel -----------------------------------------------------
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 250
    $timer.Add_Tick({
        $node = $state.Node
        if (-not $node) { return }
        $state.Tick = $state.Tick + 1

        $ev = $null
        $n = 0
        while ($n -lt 50 -and $node.Events.TryDequeue([ref]$ev)) {
            $n++
            $type, $rest = $ev -split '\|', 2
            if ($type -eq 'SYS') {
                Add-VcLog $rest
            } elseif ($type -eq 'CALL') {
                $f = $rest -split '\|', 2
                $timer.Stop()
                $answer = [System.Windows.Forms.MessageBox]::Show("$($f[1]) möchte privat mit dir sprechen. Anruf annehmen?", "Eingehender Anruf", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
                $accept = ($answer -eq [System.Windows.Forms.DialogResult]::Yes)
                $node.AnswerCall($f[0], $accept)
                if ($accept) { Add-VcLog "Privatgespräch mit $($f[1]) gestartet." } else { Add-VcLog "Anruf von $($f[1]) abgelehnt." }
                $timer.Start()
            }
        }

        Update-VcLists
        $lvl = [int](($node.MicLevel * 100) / 3000)
        $pbLevel.Value = [math]::Max(0, [math]::Min(100, $lvl))
    })

    # ---- Schließen ---------------------------------------------------------------------------------
    $form.Add_FormClosing({
        $timer.Stop()
        if ($state.Node) {
            try { $state.Node.Stop() } catch { }
            $state.Node = $null
        }
        if ($state.FwRule) { Set-VcFirewall $false }
    })

    # ---- Start -------------------------------------------------------------------------------------
    $ins = [EarthWinmm]::InputDeviceNames()
    $outs = [EarthWinmm]::OutputDeviceNames()
    $state.InName = $ins[0]
    $state.OutName = $outs[0]
    if (Test-Path -LiteralPath $cfgFile) {
        try {
            $cfg = Get-Content -LiteralPath $cfgFile -Raw | ConvertFrom-Json
            $ii = [array]::IndexOf($ins, [string]$cfg.InName)
            $oi = [array]::IndexOf($outs, [string]$cfg.OutName)
            if ($ii -ge 0) { $state.InDev = $ii - 1; $state.InName = $ins[$ii] }
            if ($oi -ge 0) { $state.OutDev = $oi - 1; $state.OutName = $outs[$oi] }
        } catch { }
    }

    Set-VcFirewall $true
    $node = New-Object EarthVoiceNode -ArgumentList "$env:USERNAME ($env:COMPUTERNAME)"
    $err = $node.Start()
    if ($err) {
        Show-VcMsg "Voice Chat konnte nicht gestartet werden:`n$err`n`nLäuft der Voice Chat bereits in einem anderen Fenster?" "Voice Chat" ([System.Windows.Forms.MessageBoxIcon]::Error)
        if ($state.FwRule) { Set-VcFirewall $false }
        return
    }
    $state.Node = $node
    Add-VcLog "Voice Chat gestartet. Suche automatisch nach anderen Teilnehmern (UDP 9873) ..."
    Start-VcAudio
    $timer.Start()

    [void]$form.ShowDialog()
    $timer.Dispose()
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
        if ($script:SelfPath) {
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
    $mainForm.Size = New-Object System.Drawing.Size(520, 740)
    $mainForm.StartPosition = "CenterScreen"
    $mainForm.FormBorderStyle = "FixedDialog"
    $mainForm.MaximizeBox = $false
    $mainForm.BackColor = [System.Drawing.Color]::FromArgb(25, 25, 25)
    $mainForm.ForeColor = [System.Drawing.Color]::White

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
        @{ Text = "2. ZeroTier (Project Earth Lan) vollständig Deinstallieren"; Action = { Invoke-FullUninstall } },
        @{ Text = "3. Netzwerk Login ( 16 Stellige ZeroTier ID eingeben)"; Action = { Invoke-NetworkLogin } },
        @{ Text = "4. Netzwerk Logout"; Action = { Invoke-NetworkLogout } },
        @{ Text = "5. Earth LAN Chat (LAN Messenger) Installieren"; Action = { Invoke-InstallLanMessenger } },
        @{ Text = "6. ReadMe erstellen"; Action = { Invoke-GenerateExplanationFile } },
        @{ Text = "7. Tools, Mods & Games Downloader"; Action = { Start-OptionWindow '7' { Invoke-ToolsModsGames } } },
        @{ Text = "8. Windows Remotedesktop aktivieren / deaktivieren"; Action = { Start-OptionWindow '8' { Invoke-RemoteDesktopZeroTier } } },
        @{ Text = "9. Spiele mit Lokalem Multiplayer (Lan) als Verknüpfung in einen Ordner auf Desktop anlegen"; Action = { Start-OptionWindow '9' { Invoke-LanGameFinder } } },
        @{ Text = "10. Manuelle Game Suche"; Action = { Start-OptionWindow '10' { Invoke-ManualGameSearch } } },
        @{ Text = "11. Server-Manager, Server Browser & P2P Chat (Port 9872)"; Action = { Start-OptionWindow '11' { Invoke-ServerManagerBrowser } } },
        @{ Text = "12. Voice Chat (Kanäle, Privat, Gruppen, Passwort)"; Action = { Start-OptionWindow '12' { Invoke-VoiceChat } } }
    )

    $yPos = 55
    foreach ($btnInfo in $buttons) {
        $btn = New-Object System.Windows.Forms.Button
        $btn.Text = $btnInfo.Text
        $btn.Location = New-Object System.Drawing.Point(30, $yPos)
        $btn.Size = New-Object System.Drawing.Size(445, 40)
        $btn.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
        $btn.ForeColor = [System.Drawing.Color]::White
        $btn.FlatStyle = "Flat"
        $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
        $btn.Font = $fontBtn
        $action = $btnInfo.Action
        $btn.Add_Click($action)
        $mainForm.Controls.Add($btn)
        $yPos += 48
    }

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
    try {
        switch ($Option) {
            '1'  { Invoke-InstallProjectEarthLan }
            '2'  { Invoke-FullUninstall }
            '3'  { Invoke-NetworkLogin }
            '4'  { Invoke-NetworkLogout }
            '5'  { Invoke-InstallLanMessenger }
            '6'  { Invoke-GenerateExplanationFile }
            '7'  { Invoke-ToolsModsGames }
            '8'  { Invoke-RemoteDesktopZeroTier }
            '9'  { Invoke-LanGameFinder }
            '10' { Invoke-ManualGameSearch }
            '11' { Invoke-ServerManagerBrowser }
            '12' { Invoke-VoiceChat }
            default { Show-MainDashboard }
        }
    } catch {
        $errText = ($Error | Select-Object -First 6 | Out-String)
        [System.Windows.Forms.MessageBox]::Show("Option $Option konnte nicht gestartet werden:`n`n$errText", "Project Earth LAN - Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    } finally {
        try { $optMutex.ReleaseMutex() } catch { }
    }
} else {
    Show-MainDashboard
}