using System;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Net;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

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
    public string Placeholder = "";
    public string Caption = "";
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
    public volatile bool ControlEnabled;
    public string Placeholder = "";
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
            if (e1 != null) { MediaError = e1; o = null; }
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
            if (e2 != null) { MediaError = (MediaError.Length > 0 ? MediaError + " / " : "") + e2; m = null; }
            mic = m;
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
    private static readonly List<KeyValuePair<string, string>> prefixes = new List<KeyValuePair<string, string>>();
    private static readonly List<KeyValuePair<WeakReference, string>> reg = new List<KeyValuePair<WeakReference, string>>();
    private static readonly HashSet<string> missing = new HashSet<string>();

    // Zeilen "deutsch<TAB>english"; endet der deutsche Teil mit "*", gilt er als Anfang (Rest wird ebenfalls uebersetzt).
    public static void Load(string dict)
    {
        en.Clear(); prefixes.Clear();
        if (dict == null) return;
        foreach (string raw in dict.Split('\n'))
        {
            string line = raw.TrimEnd('\r');
            int t = line.IndexOf('\t');
            if (t <= 0) continue;
            string de = line.Substring(0, t), e = line.Substring(t + 1);
            if (de.EndsWith("*") && e.EndsWith("*")) prefixes.Add(new KeyValuePair<string, string>(de.Substring(0, de.Length - 1), e.Substring(0, e.Length - 1)));
            else en[de] = e;
        }
    }

    public static string T(string de)
    {
        if (string.IsNullOrEmpty(de) || Lang != "en") return de;
        string e;
        if (en.TryGetValue(de, out e)) return e;
        foreach (KeyValuePair<string, string> p in prefixes)
            if (de.StartsWith(p.Key, StringComparison.Ordinal)) return p.Value + T(de.Substring(p.Key.Length));
        lock (missing) { if (missing.Count < 500) missing.Add(de); }
        return de;
    }

    public static string F(string de, params object[] args)
    {
        try { return string.Format(T(de), args); } catch { return T(de); }
    }

    // Fuer die Build-Pruefung: Texte, fuer die es (noch) keine Uebersetzung gab.
    public static string[] Missing() { lock (missing) { string[] a = new string[missing.Count]; missing.CopyTo(a); return a; } }

    public static void Reg(object target, string de)
    {
        if (target == null) return;
        lock (reg) { reg.Add(new KeyValuePair<WeakReference, string>(new WeakReference(target), de)); }
        Set(target, T(de));
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
