# Pruefung des Windows-Teils auf einem echten Windows (PowerShell 5.1): kompiliert den gesamten C#-Block wie im
# fertigen Skript und laesst Helfer und Kunde in einem Prozess gegeneinander laufen (Bildschirm, Eingaben, Ton, Kamera).
param([string]$Code = (Join-Path $PSScriptRoot '..\out\PesAll.cs'), [string]$OutDir = (Join-Path $PSScriptRoot '..\out'))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$sw0 = [Diagnostics.Stopwatch]::StartNew()
Add-Type -TypeDefinition (Get-Content -Raw $Code) -Language CSharp -ReferencedAssemblies System.Windows.Forms, System.Drawing
Write-Host ("C#-Block kompiliert in {0} ms (PowerShell {1}, {2} Bit)" -f $sw0.ElapsedMilliseconds, $PSVersionTable.PSVersion, ([IntPtr]::Size * 8))
$script:fail = 0
function Check([bool]$ok, [string]$what) { if ($ok) { Write-Host "  OK   $what" } else { Write-Host "  FEHLER $what"; $script:fail++ } }
function Info([string]$t) { Write-Host "  ..   $t" }
function WaitFor([scriptblock]$cond, [int]$ms = 10000) { $sw = [Diagnostics.Stopwatch]::StartNew(); while ($sw.ElapsedMilliseconds -lt $ms) { [System.Windows.Forms.Application]::DoEvents(); if (& $cond) { return $true }; Start-Sleep -Milliseconds 20 }; return $false }
[void][IO.Directory]::CreateDirectory($OutDir)

# Sprache
[PesI18n]::Load("Hallo`tHello`nFehler: *`tError: *`nDatei {0}`tFile {0}")
Check ([PesI18n]::T('Hallo') -eq 'Hallo') 'Deutsch bleibt unveraendert'
[PesI18n]::Lang = 'en'
Check ([PesI18n]::T('Hallo') -eq 'Hello' -and [PesI18n]::T('Fehler: Hallo') -eq 'Error: Hello' -and [PesI18n]::F('Datei {0}', 'x') -eq 'File x') 'Englisch: Wort, Anfang und Platzhalter'
$lbl = New-Object System.Windows.Forms.Label; [PesI18n]::Reg($lbl, 'Hallo'); [PesI18n]::Lang = 'de'; [PesI18n]::ApplyAll()
Check ($lbl.Text -eq 'Hallo') 'Umschalten beschriftet registrierte Controls neu'

$mons = [PesNative]::Monitors()
Info ("Bildschirme: " + (($mons | ForEach-Object { "$($_.Width)x$($_.Height)@$($_.X),$($_.Y)" }) -join ' | '))
Info ("Kameras: " + (([PesCamera]::Devices()) -join ', ') + " | Mikrofone: " + (([PesWinmm]::InputDeviceNames()) -join ', ') + " | Lautsprecher: " + (([PesWinmm]::OutputDeviceNames()) -join ', '))
Check ([Runtime.InteropServices.Marshal]::SizeOf([type][PesNative+INPUT]) -eq $(if ([IntPtr]::Size -eq 8) { 40 } else { 28 })) 'INPUT-Struktur hat die richtige Groesse'

$port = 39790
$rv = New-Object PesRendezvousServer; $rv.Port = $port; $rv.BindAddress = [Net.IPAddress]::Loopback; $rv.Start()
$lobby = [PesProto]::NewLobby(); $pw = [PesProto]::NewPassword()
$dl = Join-Path ([IO.Path]::GetTempPath()) ("pes-win-" + [guid]::NewGuid().ToString('N'))
$hH = New-Object PesHost; $hH.View = New-Object PesViewPanel; $hH.RemoteVideo = New-Object PesVideoPanel; $hH.SelfVideo = New-Object PesVideoPanel
$hC = New-Object PesHost; $hC.RemoteVideo = New-Object PesVideoPanel; $hC.SelfVideo = New-Object PesVideoPanel
$hH.Connect('127.0.0.1', $port, $lobby, $pw, 'Helfer', $null, 1, 39792, '127.0.0.1', (Join-Path $dl 'H'))
$hC.Connect('127.0.0.1', $port, $lobby, $pw, 'Kunde', $null, 2, 39793, '127.0.0.1', (Join-Path $dl 'C'))
Check (WaitFor { $hH.State -eq 2 -and $hC.State -eq 2 } 15000) 'Beide Seiten gestartet (Verbinden im Hintergrund)'
Check (WaitFor { $hH.Session.Paired -and $hC.Session.Paired } 20000) 'Kopplung Helfer <-> Kunde'

# Bildschirm
Check ($hH.Session.RequestScreen(2)) 'Helfer fordert Bildschirm mit Steuerung an'
$req = $false; [void](WaitFor { $x = $null; while ($hC.Session.Events.TryDequeue([ref]$x)) { if ($x -like "SCREEN*req*2") { $script:req = $true } }; $script:req } 8000)
Check $req 'Anfrage kommt beim Kunden an'
$hC.StartShare($true)
Check (WaitFor { $hH.Session.ShareActive -and $hH.Session.ControlActive -and $hH.Session.ScreenW -gt 0 } 10000) 'Freigabe mit Steuerung gemeldet'
$got = WaitFor { $hH.View.HasImage -and $hH.View.Rects -gt 0 } 15000
Check $got ("Bildschirmbild kommt beim Helfer an (" + $hH.Session.ScreenW + "x" + $hH.Session.ScreenH + ")")
if (-not $got) { Info ("Aufnahme-Fehler: " + $hC.Screen.LastError) }
Start-Sleep -Milliseconds 1500
Info ("Rechtecke: " + $hH.View.Rects + ", Byte: " + $hH.View.Bytes + ", Bilder/s: " + $hC.Screen.Fps + ", kbit/s: " + $hC.Screen.Kbps)
$png = Join-Path $OutDir 'fernbild.png'
if ($hH.View.SaveImage($png)) {
    $bmp = New-Object System.Drawing.Bitmap($png)
    $colors = New-Object 'System.Collections.Generic.HashSet[int]'
    for ($y = 0; $y -lt $bmp.Height; $y += 16) { for ($x = 0; $x -lt $bmp.Width; $x += 16) { [void]$colors.Add($bmp.GetPixel($x, $y).ToArgb()) } }
    Info ("Fernbild gespeichert: " + $bmp.Width + "x" + $bmp.Height + ", verschiedene Farben in der Stichprobe: " + $colors.Count)
    Check ($bmp.Width -eq $hH.Session.ScreenW -and $bmp.Height -eq $hH.Session.ScreenH) 'Fernbild hat die gemeldete Groesse'
    $bmp.Dispose()
}
# Aenderung auf dem Bildschirm: ein Fenster zeigen und pruefen, dass neue Rechtecke kommen
$f = New-Object System.Windows.Forms.Form; $f.Text = 'PES-Test'; $f.StartPosition = 'Manual'; $f.Location = New-Object System.Drawing.Point(40, 40); $f.Size = New-Object System.Drawing.Size(500, 300); $f.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215); $f.TopMost = $true
$l2 = New-Object System.Windows.Forms.Label; $l2.Text = 'Project Earth Support - Bildschirmtest'; $l2.ForeColor = [System.Drawing.Color]::White; $l2.Font = New-Object System.Drawing.Font('Segoe UI', 16); $l2.Dock = 'Fill'; $l2.TextAlign = 'MiddleCenter'; $f.Controls.Add($l2)
$before = $hH.View.Rects
$f.Show(); [System.Windows.Forms.Application]::DoEvents()
Check (WaitFor { $hH.View.Rects -gt $before } 8000) 'Geaenderter Bereich wird nachgeliefert'
Start-Sleep -Milliseconds 1200; [System.Windows.Forms.Application]::DoEvents()
[void]$hH.View.SaveImage((Join-Path $OutDir 'fernbild-fenster.png'))
$bmp = New-Object System.Drawing.Bitmap((Join-Path $OutDir 'fernbild-fenster.png'))
$sx = [double]$bmp.Width / $mons[0].Width; $px = $bmp.GetPixel([int](290 * $sx), [int](70 * $sx))
Info ("Farbe im Testfenster (erwartet etwa 0,120,215): " + $px.R + "," + $px.G + "," + $px.B)
Check ([Math]::Abs($px.R - 0) -lt 40 -and [Math]::Abs($px.G - 120) -lt 40 -and [Math]::Abs($px.B - 215) -lt 40) 'Inhalt des Fernbilds stimmt (blaues Testfenster an der richtigen Stelle)'
$bmp.Dispose()

# Eingaben: Zeiger bewegen
$hH.View.ControlEnabled = $true
$c0 = [System.Windows.Forms.Cursor]::Position
$hH.Session.InputMove(16384, 16384)
[void](WaitFor { $hC.Input.Count -ge 1 } 5000)
Start-Sleep -Milliseconds 300
$c1 = [System.Windows.Forms.Cursor]::Position
$sb = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
Info ("Zeiger vorher $($c0.X),$($c0.Y) nachher $($c1.X),$($c1.Y); Bildschirm $($sb.Width)x$($sb.Height)")
Check ([Math]::Abs($c1.X - $sb.Width / 4) -le ($sb.Width * 0.03 + 3) -and [Math]::Abs($c1.Y - $sb.Height / 4) -le ($sb.Height * 0.03 + 3)) 'Zeiger steht nach InputMove an der richtigen Stelle'
# Klick in das Testfenster und Text tippen
$tb = New-Object System.Windows.Forms.TextBox; $tb.Dock = 'Top'; $f.Controls.Add($tb); $tb.BringToFront(); $f.Activate(); [void]$tb.Focus(); [System.Windows.Forms.Application]::DoEvents()
$cx = [int](($f.Left + 250) * 65535 / ($sb.Width - 1)); $cy = [int](($f.Top + 42) * 65535 / ($sb.Height - 1))
[void]$hH.Session.InputButton(0, $true, $cx, $cy); [void]$hH.Session.InputButton(0, $false, $cx, $cy)
Start-Sleep -Milliseconds 300; [System.Windows.Forms.Application]::DoEvents()
[void]$hH.Session.InputText('Hallo PES'); [void]$hH.Session.InputKey(0x41, $true, $false); [void]$hH.Session.InputKey(0x41, $false, $false)
[void](WaitFor { $tb.Text.Length -ge 10 } 5000)
Info ("Text im Testfeld: '" + $tb.Text + "'")
Check ($tb.Text -eq 'Hallo PESa') 'Mausklick, Text und Taste kommen im Fenster des Kunden an'
# Steuerung entziehen
$hC.SetControl($false)
Check (WaitFor { -not $hH.Session.ControlActive } 5000) 'Steuerung entzogen gemeldet'
$n0 = $hC.Input.Count; [void]$hH.Session.InputKey(0x42, $true, $false); Start-Sleep -Milliseconds 400
Check ($hC.Input.Count -eq $n0) 'Ohne Erlaubnis wird nichts mehr ausgefuehrt'
$hC.StopShare()
Check (WaitFor { -not $hH.Session.ShareActive -and -not $hC.Screen.IsRunning } 5000) 'Freigabe beendet, Aufnahme gestoppt'
$f.Close()

# Anruf: Ton und Kamera duerfen ohne Geraete nicht abstuerzen
[void]$hH.Session.Call()
[void](WaitFor { $hC.Session.CallState -eq 2 } 5000); $hC.Session.AnswerCall($true)
Check (WaitFor { $hH.Session.CallState -eq 3 -and $hC.Session.CallState -eq 3 } 5000) 'Anruf aktiv'
$hH.StartMedia(-1, -1); $hC.StartMedia(-1, -1)
Start-Sleep -Milliseconds 800
Info ("Ton Helfer: '" + $hH.MediaError + "'  Ton Kunde: '" + $hC.MediaError + "'")
Check ($hH.MediaRunning -and $hC.MediaRunning) 'Ton gestartet (Fehlermeldung statt Absturz, falls kein Geraet da ist)'
$hC.Session.SetMedia($true, $true); $hC.StartCamera('', $false)
[void](WaitFor { -not $hC.CameraRunning -or $hH.Session.VideoAgeMs -lt 2000 } 6000)
Info ("Kamera: laeuft=" + $hC.CameraRunning + " Fehler='" + $hC.CameraError + "'")
Check ($hC.CameraRunning -or $hC.CameraError.Length -gt 0) 'Kamera: Bild oder verstaendliche Fehlermeldung (kein Absturz)'
# Videoanzeige mit einem erzeugten JPEG
$b2 = New-Object System.Drawing.Bitmap(320, 240); $g2 = [System.Drawing.Graphics]::FromImage($b2); $g2.Clear([System.Drawing.Color]::DarkGreen); $g2.Dispose()
$ms = New-Object IO.MemoryStream; $b2.Save($ms, [System.Drawing.Imaging.ImageFormat]::Jpeg); $jpg = $ms.ToArray(); $b2.Dispose()
[void]$hC.Session.SendVideo($jpg, 1)
Check (WaitFor { $hH.Session.VideoAgeMs -lt 3000 } 5000) 'Videobild wird uebertragen'
$hH.RemoteVideo.Size = New-Object System.Drawing.Size(320, 240)
$shot = New-Object System.Drawing.Bitmap(320, 240); $hH.RemoteVideo.DrawToBitmap($shot, (New-Object System.Drawing.Rectangle(0, 0, 320, 240)))
$pc = $shot.GetPixel(160, 120); $shot.Save((Join-Path $OutDir 'videopanel.png')); $shot.Dispose()
Info ("Farbe im Videopanel (erwartet dunkelgruen 0,100,0): " + $pc.R + "," + $pc.G + "," + $pc.B)
Check ($pc.G -gt 60 -and $pc.R -lt 60 -and $pc.B -lt 60) 'Videopanel zeichnet das empfangene Bild (gedreht)'
$hH.Session.Hangup()
[void](WaitFor { $hC.Session.CallState -eq 0 } 5000)
$hH.StopMedia(); $hC.StopMedia()
$hC.Disconnect()
Check (WaitFor { -not $hH.Session.Paired } 6000) 'Trennen wird beim Helfer erkannt'
$hH.Disconnect(); Start-Sleep -Milliseconds 500; $rv.Stop()
try { Remove-Item -Recurse -Force $dl -ErrorAction SilentlyContinue } catch { }
if ($script:fail -gt 0) { Write-Host "ERGEBNIS: $($script:fail) Fehler"; exit 1 } else { Write-Host 'ERGEBNIS: alle Pruefungen bestanden'; exit 0 }
