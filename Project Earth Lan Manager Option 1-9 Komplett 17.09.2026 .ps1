# ==============================================================================
# Project Earth LAN - All in One Manager, Downloader & Game Finder
# Features: Admin-Elevated | Full White Text / Dark GUI | Progress Bar Dialogs
# ==============================================================================

# 1. ADMIN-RECHTE & KONSOLE EINRICHTEN
$Host.UI.RawUI.ForegroundColor = "White"
Clear-Host

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if ($PSCommandPath) {
        Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
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
Impressum: Project Earth Lan
           
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
    $lstFiles.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40)
    $lstFiles.ForeColor = [System.Drawing.Color]::White
    $lstFiles.Font = $fontMain
    $form.Controls.Add($lstFiles)

    $btnDownload = New-Object System.Windows.Forms.Button
    $btnDownload.Text = "Ausgewählte Datei herunterladen"
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
            if ($txtPass.Text -ne ) {
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
            $lstFiles.Items.Add($file)
        }
        
        &$logCallback "Vorgang beendet. $($files.Count) Datei(en) erfasst."
    })

    $btnDownload.add_Click({
        if ($lstFiles.SelectedIndex -eq -1) {
            [System.Windows.Forms.MessageBox]::Show("Bitte wähle zuerst eine Datei aus der Liste aus.", "Hinweis", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }

        $selectedFileRel = $lstFiles.SelectedItem.ToString()
        $category = if ($rbTools.Checked) { "Windows Tools" } elseif ($rbMods.Checked) { "Mods" } else { "Games" }
        
        $targetDir = Join-Path $downloadBaseDir $category
        if (-not (Test-Path -Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }

        $fileName = [System.IO.Path]::GetFileName($selectedFileRel)
        $destinationFile = Join-Path $targetDir $fileName

        $escapedRelPath = ($selectedFileRel -split '/' | ForEach-Object { [System.Uri]::EscapeDataString($_) }) -join '/'
        $downloadUrl = "$baseUrl/$([System.Uri]::EscapeDataString($category))/$escapedRelPath"

        &$logCallback "Starte Download von: $downloadUrl"
        &$logCallback "Zielpfad: $destinationFile"

        $progressBar.Value = 0
        $btnDownload.Enabled = $false

        try {
            $request = [System.Net.HttpWebRequest]::Create($downloadUrl)
            $request.Method = "GET"
            $request.UserAgent = "Mozilla/5.0"
            
            $response = $request.GetResponse()
            $totalBytes = $response.ContentLength
            $responseStream = $response.GetResponseStream()
            $targetStream = [System.IO.File]::Create($destinationFile)

            $buffer = New-Object byte[] 65536
            $bytesRead = 0
            $totalRead = 0

            while (($bytesRead = $responseStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $targetStream.Write($buffer, 0, $bytesRead)
                $totalRead += $bytesRead

                if ($totalBytes -gt 0) {
                    $percent = [int](($totalRead / $totalBytes) * 100)
                    $progressBar.Value = [Math]::Min(100, $percent)
                    [System.Windows.Forms.Application]::DoEvents()
                }
            }

            $targetStream.Close()
            $responseStream.Close()
            $response.Close()

            $progressBar.Value = 100
            &$logCallback "DOWNLOAD ERFOLGREICH: $fileName"
            [System.Windows.Forms.MessageBox]::Show("Datei erfolgreich heruntergeladen!`n`nPfad: $destinationFile", "Erfolg", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            &$logCallback "DOWNLOAD FEHLER: $($_.Exception.Message)"
            [System.Windows.Forms.MessageBox]::Show("Fehler beim Herunterladen: $($_.Exception.Message)", "Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        } finally {
            $btnDownload.Enabled = $true
        }
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
Zombies Monsters Robots,Game,Black,UT2004
"@
        $GameWhitelist = ($RawText -split ',') | ForEach-Object { $_.Trim() } | Select-Object -Unique

        $ToolBlacklist = @(
            "7-zip", "winrar", "docker", "jdownloader", "kodi", "bandicam", "total commander", 
            "sd card formatter", "driver", "tool", "update", "browser", "chrome", "firefox", 
            "edge", "java", "flash", "visual c++", "runtime", "codec", "player", "messenger", 
            "client", "server", "zerotier", "registry", "clone", "helper", "sdk", "mod", 
            "plugin", "nvidia", "amd", "intel", "realtek", "windows", "office", "dotnet", 
            "antivirus", "security", "framework", "discord", "teams", "zoom", "skype", 
            "spotify", "virtualbox", "vmware", "notepad", "vlc", "ccleaner", "steamworks shared", "Worldbuilder", "level editor","unrealed","testapp"
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
# ZENTRALES HAUPTMENÜ DASHBOARD
# ------------------------------------------------------------------------------
function Show-MainDashboard {
    $mainForm = New-Object System.Windows.Forms.Form
    $mainForm.Text = "Project Earth LAN - Control Center"
    $mainForm.Size = New-Object System.Drawing.Size(520, 570)
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
        @{ Text = "6. Erklärungs-Datei auf Desktop erstellen inklusive Impressum"; Action = { Invoke-GenerateExplanationFile } },
        @{ Text = "7. Tools, Mods & Games Downloader"; Action = { Invoke-ToolsModsGames } },
        @{ Text = "8. Windows Remotedesktop aktivieren / deaktivieren"; Action = { Invoke-RemoteDesktopZeroTier } },
        @{ Text = "9. Spiele mit Lokalem Multiplayer (Lan) als Verknüpfung in einen Ordner auf Desktop anlegen"; Action = { Invoke-LanGameFinder } }
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
Show-MainDashboard
