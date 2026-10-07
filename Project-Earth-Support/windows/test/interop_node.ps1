# Testknoten fuer den Interop-Test: Mini-Vermittler + (optional) C#-Kunde mit festem Verhalten.
# Laeuft, bis die Datei <Dir>\stop existiert oder die Zeit abgelaufen ist.
param([string]$Src = (Join-Path $PSScriptRoot '..\src'), [int]$Port = 39890, [string]$Lobby = '', [string]$Password = '', [string]$Dir = '', [switch]$RvOnly, [int]$Seconds = 300)
$ErrorActionPreference = 'Stop'
$code = (Get-Content -Raw (Join-Path $Src 'PesCoreHead.cs')) + (Get-Content -Raw (Join-Path $Src 'PesEngine.cs')) + "`n" + (Get-Content -Raw (Join-Path $Src 'PesSession.cs'))
if ($PSVersionTable.PSEdition -eq 'Core') { Add-Type -TypeDefinition $code -Language CSharp -IgnoreWarnings -CompilerOptions '-langversion:5', '-nowarn:CS8632,SYSLIB0041,SYSLIB0021,SYSLIB0023' }
else { Add-Type -TypeDefinition $code -Language CSharp }
Add-Type -TypeDefinition @"
using System;
using System.Collections.Concurrent;
public class PesNodeSink {
    public ConcurrentQueue<string> Inputs = new ConcurrentQueue<string>();
    public Action<byte[]> Input() { return delegate (byte[] b) {
        int k = b[0]; string s = "?";
        if (k == 1) s = "1:" + ((b[1] << 8) | b[2]) + ":" + ((b[3] << 8) | b[4]);
        else if (k == 2) s = "2:" + b[1] + ":" + b[2] + ":" + ((b[3] << 8) | b[4]) + ":" + ((b[5] << 8) | b[6]);
        else if (k == 4) s = "4:" + ((b[1] << 8) | b[2]) + ":" + b[3];
        else if (k == 5) s = "5:" + System.Text.Encoding.UTF8.GetString(b, 1, b.Length - 1);
        Inputs.Enqueue(s); }; }
}
"@
$rv = New-Object PesRendezvousServer; $rv.Port = $Port; $rv.BindAddress = [Net.IPAddress]::Loopback; $rv.Start()
[void][IO.Directory]::CreateDirectory($Dir)
[IO.File]::WriteAllText((Join-Path $Dir 'ready'), 'ok')
$stop = Join-Path $Dir 'stop'
$sw = [Diagnostics.Stopwatch]::StartNew()
if ($RvOnly) {
    while (-not [IO.File]::Exists($stop) -and $sw.Elapsed.TotalSeconds -lt $Seconds) { Start-Sleep -Milliseconds 100 }
    $rv.Stop(); exit 0
}
$e = New-Object PesP2pEngine; $e.PreferredPort = 39896; $e.BindAddress = [Net.IPAddress]::Loopback
$e.Start('127.0.0.1', $Port, $Lobby, $Password, 'Kunden-PC', $null)
$s = New-Object PesSession($e); $s.MyName = 'Kunde'; $s.Role = 2; $s.Platform = 1; $s.DownloadDir = Join-Path $Dir 'B'
$sink = New-Object PesNodeSink; $s.OnInput = $sink.Input()
$s.Start()
$end = $false; $opt = ''; $mediaLeft = 0; $mi = 0
$fr = New-Object 'int16[]' 320; for ($i = 0; $i -lt 320; $i++) { $fr[$i] = [int16](9000 * [Math]::Sin($i / 4.0)) }
$vid = New-Object byte[] 9000; for ($i = 0; $i -lt 9000; $i++) { $vid[$i] = [byte](($i * 13) -band 255) }
while (-not $end -and -not [IO.File]::Exists($stop) -and $sw.Elapsed.TotalSeconds -lt $Seconds) {
    $x = $null
    while ($s.Events.TryDequeue([ref]$x)) {
        $f = $x.Split([char]31)
        if ($f[0] -eq 'CHAT' -and $f[2] -eq 'ENDE') { $end = $true }
        elseif ($f[0] -eq 'CHAT' -and $f[2] -eq 'INPUTS?') { [void]$s.SendChat('Inputs: ' + ($sink.Inputs.ToArray() -join ' ') + ' ' + $opt) }
        elseif ($f[0] -eq 'CHAT') { [void]$s.SendChat('Echo: ' + $f[2]) }
        elseif ($f[0] -eq 'CALL' -and $f[1] -eq 'in') { $s.AnswerCall($true) }
        elseif ($f[0] -eq 'CALL' -and $f[1] -eq 'active') { $s.SetMedia($true, $true); $mediaLeft = 200; $mi = 0 }
        elseif ($f[0] -eq 'SCREEN' -and $f[1] -eq 'req' -and $f[2] -eq '2') {
            $s.SetShare($true, $true, 1280, 720, 0, 1); $n = 0
            foreach ($size in @(300000, 1500, 60000, 1, 1100, 1101, 250000, 40000)) {
                $px = 64 * $n; $buf = New-Object byte[] $size; for ($i = 0; $i -lt $size; $i++) { $buf[$i] = [byte](($i * 7 + $px) -band 255) }
                [void]$s.SendScreenRect(1280, 720, $px, 0, 64, 64, 1, $buf); $n++
            }
        }
        elseif ($f[0] -eq 'SCREEN' -and $f[1] -eq 'req' -and $f[2] -eq '3') { $s.SetShare($false, $false, 0, 0, 0, 1) }
        elseif ($f[0] -eq 'SCREEN' -and $f[1] -eq 'opt') { $opt = 'opt:' + $f[2] + ':' + $f[3] }
        elseif ($f[0] -eq 'FILE' -and $f[1] -eq 'offer') { [void]$s.AnswerFile($true) }
        elseif ($f[0] -eq 'FILE' -and $f[1] -eq 'received') { [void]$s.OfferFile($f[3]) }
    }
    if ($mediaLeft -gt 0 -and $s.CallState -eq 3) { $s.SendAudio($fr); if ($mi % 5 -eq 0) { [void]$s.SendVideo($vid, 2) }; $mi++; $mediaLeft-- }
    Start-Sleep -Milliseconds 20
}
Start-Sleep -Milliseconds 800
$s.Stop(); $e.Stop(); $rv.Stop()
exit 0
