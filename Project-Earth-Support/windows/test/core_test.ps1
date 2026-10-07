# Selbsttest des plattformneutralen Kerns (laeuft unter pwsh/Linux und Windows PowerShell 5.1).
param([string]$Src = (Join-Path $PSScriptRoot '..\src'), [int]$LossPercent = 0, [int]$FileMb = 3)
$ErrorActionPreference = 'Stop'
$code = (Get-Content -Raw (Join-Path $Src 'PesCoreHead.cs')) + (Get-Content -Raw (Join-Path $Src 'PesEngine.cs')) + "`n" + (Get-Content -Raw (Join-Path $Src 'PesSession.cs'))
if ($PSVersionTable.PSEdition -eq 'Core') { Add-Type -TypeDefinition $code -Language CSharp -IgnoreWarnings -CompilerOptions '-langversion:5', '-nowarn:CS8632,SYSLIB0041,SYSLIB0021,SYSLIB0023' }
else { Add-Type -TypeDefinition $code -Language CSharp }
$script:fail = 0
function Check([bool]$ok, [string]$what) { if ($ok) { Write-Host "  OK   $what" } else { Write-Host "  FEHLER $what"; $script:fail++ } }
function WaitFor([scriptblock]$cond, [int]$ms = 10000) { $sw = [Diagnostics.Stopwatch]::StartNew(); while ($sw.ElapsedMilliseconds -lt $ms) { if (& $cond) { return $true }; Start-Sleep -Milliseconds 20 }; return $false }
function Drain($s) { $l = New-Object System.Collections.Generic.List[string]; $x = $null; while ($s.Events.TryDequeue([ref]$x)) { $l.Add($x) }; return ,$l }

$port = 39890
$rv = New-Object PesRendezvousServer; $rv.Port = $port; $rv.BindAddress = [Net.IPAddress]::Loopback; $rv.Start()
$lobby = [PesProto]::NewLobby(); $pw = [PesProto]::NewPassword()
$code1 = [PesProto]::InviteCreate("127.0.0.1:$port", $lobby, $pw)
$inv = [PesProto]::InviteParse("Hallo, hier der Code: $code1 bitte einfuegen")
Check ($inv -and $inv[0] -eq "127.0.0.1:$port" -and $inv[1] -eq $lobby -and $inv[2] -eq $pw) 'Einladungscode erzeugen und lesen'
Check ($pw.Length -ge 16) 'Passwort mindestens 16 Zeichen'
Check ([PesProto]::CleanFileName('..\..\Windows\evil?.exe') -eq 'evil_.exe') 'Dateiname bereinigen'
Check ([PesProto]::CleanFileName('CON.txt') -eq '_CON.txt') 'Reservierte Namen'
$mu = $true; foreach ($v in @(0, 1, -1, 100, -100, 1000, -1000, 12345, -12345, 32000, -32000)) { $d = [PesProto]::MuLawDecode([PesProto]::MuLawEncode([int16]$v)); if ([Math]::Abs($d - $v) -gt [Math]::Max(16, [Math]::Abs($v) / 16)) { $mu = $false } }
Check $mu 'u-law hin und zurueck'

$eA = New-Object PesP2pEngine; $eA.PreferredPort = 39892; $eA.BindAddress = [Net.IPAddress]::Loopback
$eB = New-Object PesP2pEngine; $eB.PreferredPort = 39893; $eB.BindAddress = [Net.IPAddress]::Loopback
$eA.Start('127.0.0.1', $port, $lobby, $pw, 'Helfer-PC', $null)
$eB.Start('127.0.0.1', $port, $lobby, $pw, 'Kunden-PC', $null)
$sA = New-Object PesSession($eA); $sA.MyName = 'Helfer'; $sA.Role = 1
$sB = New-Object PesSession($eB); $sB.MyName = 'Kunde'; $sB.Role = 2
$dl = Join-Path ([IO.Path]::GetTempPath()) ("pes-test-" + [guid]::NewGuid().ToString('N')); [void][IO.Directory]::CreateDirectory($dl)
$sA.DownloadDir = Join-Path $dl 'A'; $sB.DownloadDir = Join-Path $dl 'B'
$sA.Start(); $sB.Start()
if ($LossPercent -gt 0) {
    Add-Type -TypeDefinition @"
using System;
public static class PesTestLoss {
    public static Action<byte[]> Wrap(Action<byte[]> inner, int percent) {
        Random r = new Random(4711);
        return delegate (byte[] p) { bool drop; lock (r) { drop = r.Next(100) < percent; } if (!drop) inner(p); };
    }
}
"@
    $eA.InboundSink = [PesTestLoss]::Wrap($eA.InboundSink, $LossPercent)
    $eB.InboundSink = [PesTestLoss]::Wrap($eB.InboundSink, $LossPercent)
    Write-Host "Paketverlust simuliert: $LossPercent %"
}
Check (WaitFor { $sA.Paired -and $sB.Paired -and $sA.PartnerName -eq 'Kunde' -and $sB.PartnerName -eq 'Helfer' } 20000) 'Kopplung Helfer <-> Kunde'
Start-Sleep -Milliseconds 600
$evA = Drain $sA; $evB = Drain $sB
Check (($evA -join "`n") -match 'PEER.up.Kunde') 'Ereignis PEER up beim Helfer'
Write-Host ("  Wege: " + (($eA.GetPeers() | ForEach-Object { $_.Name + '=' + $_.Mode }) -join ', '))

# Chat
[void]$sA.SendChat('Hallo Kunde, Umlaute: aeoeue 123')
[void]$sB.SendChat('Hallo Helfer')
$gotB = $false; $gotA = $false
[void](WaitFor { foreach ($e in (Drain $sB)) { if ($e -like "CHAT*Hallo Kunde, Umlaute: aeoeue 123") { $script:gotB = $true } }; foreach ($e in (Drain $sA)) { if ($e -like "CHAT*Hallo Helfer") { $script:gotA = $true } }; $script:gotA -and $script:gotB } 8000)
Check ($gotA -and $gotB) 'Chat in beide Richtungen'

# Anruf
Check ($sA.Call()) 'Anruf starten'
Check (WaitFor { $sB.CallState -eq 2 } 8000) 'Kunde klingelt'
$sB.AnswerCall($true)
Check (WaitFor { $sA.CallState -eq 3 -and $sB.CallState -eq 3 } 8000) 'Anruf aktiv'
$frame = New-Object 'int16[]' 320; for ($i = 0; $i -lt 320; $i++) { $frame[$i] = [int16](8000 * [Math]::Sin($i / 5.0)) }
for ($i = 0; $i -lt 30; $i++) { $sA.SendAudio($frame); Start-Sleep -Milliseconds 5 }
$heard = $false; for ($i = 0; $i -lt 40 -and -not $heard; $i++) { $f = $sB.PullAudio(); foreach ($v in $f) { if ([Math]::Abs($v) -gt 2000) { $heard = $true; break } }; Start-Sleep -Milliseconds 10 }
Check $heard 'Ton kommt an'
Add-Type -TypeDefinition @"
using System;
using System.Collections.Concurrent;
public class PesTestSink {
    public ConcurrentQueue<byte[]> Frames = new ConcurrentQueue<byte[]>();
    public ConcurrentQueue<int[]> Rects = new ConcurrentQueue<int[]>();
    public ConcurrentQueue<byte[]> Inputs = new ConcurrentQueue<byte[]>();
    public int Rot = -1; public long RectBytes; public int BadRect;
    public Action<byte[], int> Video() { return delegate (byte[] j, int r) { Rot = r; Frames.Enqueue(j); }; }
    public Action<int[], byte[]> Screen() { return delegate (int[] r, byte[] j) { for (int i = 0; i < j.Length; i++) if (j[i] != (byte)((i * 7 + r[2]) & 255)) { BadRect++; break; } RectBytes += j.Length; Rects.Enqueue(r); }; }
    public Action<byte[]> Input() { return delegate (byte[] b) { Inputs.Enqueue(b); }; }
}
"@
$sink = New-Object PesTestSink
$sB.OnVideoFrame = $sink.Video(); $sA.OnScreenRect = $sink.Screen(); $sB.OnInput = $sink.Input()
$sA.SetMedia($true, $true)
$jpg = New-Object byte[] 9000; (New-Object Random 1).NextBytes($jpg)
$okV = $false
for ($i = 0; $i -lt 40 -and -not $okV; $i++) { [void]$sA.SendVideo($jpg, 3); Start-Sleep -Milliseconds 40; $f = $null; while ($sink.Frames.TryDequeue([ref]$f)) { if ($f.Length -eq 9000 -and $f[8999] -eq $jpg[8999] -and $f[0] -eq $jpg[0]) { $okV = $true } } }
Check ($okV -and $sink.Rot -eq 3) 'Videobild (9 Teile) kommt an, Drehung stimmt'
Check (WaitFor { $sB.PartnerCam } 5000) 'Kamera-Zustand wird gemeldet'

# Bildschirm: erst nach Freigabe
Check (-not $sB.SendScreenRect(1280, 720, 0, 0, 64, 64, 0, (New-Object byte[] 10))) 'Kein Bildschirm ohne Freigabe'
[void]$sA.RequestScreen(2)
$req = $false; [void](WaitFor { foreach ($e in (Drain $sB)) { if ($e -like "SCREEN*req*2") { $script:req = $true } }; $script:req } 8000)
Check $req 'Anfrage zum Steuern kommt beim Kunden an'
Check (-not $sA.InputKey(65, $true, $false)) 'Keine Eingabe ohne Erlaubnis'
$sB.SetShare($true, $false, 1280, 720, 0, 1)
Check (WaitFor { $sA.ShareActive -and -not $sA.ControlActive } 8000) 'Freigabe ohne Steuerung gemeldet'
Check (-not $sA.InputKey(65, $true, $false)) 'Nur ansehen: Eingabe bleibt gesperrt'
$sB.SetShare($true, $true, 1280, 720, 0, 1)
Check (WaitFor { $sA.ControlActive } 8000) 'Steuerung erlaubt gemeldet'
$total = 0; $n = 0
$sw = [Diagnostics.Stopwatch]::StartNew()
foreach ($size in @(300000, 1500, 60000, 1, 1100, 1101, 250000, 40000)) {
    $x = 64 * $n; $buf = New-Object byte[] $size; for ($i = 0; $i -lt $size; $i++) { $buf[$i] = [byte](($i * 7 + $x) -band 255) }
    Check ($sB.SendScreenRect(1280, 720, $x, 0, 64, 64, 1, $buf)) "Rechteck $size Byte gesendet"; $total += $size; $n++
}
Check (WaitFor { $sink.Rects.Count -eq $n } 60000) "Alle $n Rechtecke angekommen ($total Byte in $($sw.ElapsedMilliseconds) ms)"
Check ($sink.BadRect -eq 0 -and $sink.RectBytes -eq $total) 'Rechteck-Inhalte unveraendert und in Reihenfolge'
$ordered = $true; $i = 0; $r = $null; while ($sink.Rects.TryDequeue([ref]$r)) { if ($r[2] -ne 64 * $i) { $ordered = $false }; $i++ }
Check $ordered 'Reihenfolge der Rechtecke'
[void]$sA.InputButton(0, $true, 1000, 2000); [void]$sA.InputButton(0, $false, 1000, 2000); [void]$sA.InputKey(0x41, $true, $false); [void]$sA.InputText('abc'); $sA.InputMove(30000, 40000)
Check (WaitFor { $sink.Inputs.Count -ge 5 } 8000) 'Eingaben kommen beim Kunden an (Taste, Text, Zeiger)'
$b = $null; [void]$sink.Inputs.TryDequeue([ref]$b)
Check ($b -and $b[0] -eq 2 -and $b[1] -eq 0 -and $b[2] -eq 1 -and (($b[3] * 256 + $b[4]) -eq 1000)) 'Mausklick-Inhalt stimmt'
$sB.SetShare($false, $false, 0, 0, 0, 1)
Check (WaitFor { -not $sA.ShareActive } 8000) 'Freigabe beendet gemeldet'
Check (-not $sA.InputKey(65, $true, $false)) 'Nach dem Beenden keine Eingabe mehr'

# Datei
$src = Join-Path $dl 'quelle test.bin'; $data = New-Object byte[] ($FileMb * 1024 * 1024 + 12345); (New-Object Random 7).NextBytes($data); [IO.File]::WriteAllBytes($src, $data)
Check ($null -eq $sA.OfferFile($src)) 'Datei anbieten'
$offer = $false; [void](WaitFor { foreach ($e in (Drain $sB)) { if ($e -like "FILE*offer*quelle test.bin*") { $script:offer = $true } }; $script:offer } 8000)
Check $offer 'Angebot kommt an'
$sw.Restart()
Check ($null -eq $sB.AnswerFile($true)) 'Angebot annehmen'
Check (WaitFor { $f = $sB.RxFile; $f -and $f.State -eq 2 } 120000) "Datei empfangen ($($data.Length) Byte in $($sw.ElapsedMilliseconds) ms)"
Check (WaitFor { $f = $sA.TxFile; $f -and $f.State -eq 2 } 8000) 'Absender bekommt die Bestaetigung'
$dst = Join-Path $sB.DownloadDir 'quelle test.bin'
$same = [IO.File]::Exists($dst) -and ((Get-FileHash $dst -Algorithm SHA256).Hash -eq (Get-FileHash $src -Algorithm SHA256).Hash)
Check $same 'Empfangene Datei ist identisch (SHA-256)'
Check (@(Get-ChildItem $sB.DownloadDir -Filter *.part).Count -eq 0) 'Keine Teil-Datei uebrig'
# Ablehnen
Check ($null -eq $sB.OfferFile($src)) 'Datei in Gegenrichtung anbieten'
[void](WaitFor { $f = $sA.RxFile; $f -and $f.Id -ne 0 -and $f.State -eq 0 } 8000)
[void]$sA.AnswerFile($false)
Check (WaitFor { $f = $sB.TxFile; $f -and $f.State -eq 3 } 8000) 'Ablehnung kommt beim Absender an'

# Auflegen und Trennen
$sA.Hangup()
Check (WaitFor { $sB.CallState -eq 0 } 8000) 'Auflegen kommt an'
Write-Host ("  Wiederholte Pakete: A=" + $sA.Retransmits + " B=" + $sB.Retransmits + ", RTT A=" + $sA.Rtt + " ms")
$sB.Stop()
Check (WaitFor { -not $sA.Paired } 5000) 'Abmeldung wird sofort erkannt'
$sA.Stop(); $eA.Stop(); $eB.Stop(); $rv.Stop()
try { Remove-Item -Recurse -Force $dl } catch { }
if ($script:fail -gt 0) { Write-Host "ERGEBNIS: $($script:fail) Fehler"; exit 1 } else { Write-Host 'ERGEBNIS: alle Pruefungen bestanden'; exit 0 }
