// ============================================================================
// Project Earth Support - Sitzungsschicht (plattformneutral, C# 5)
//   PesProto    : Konstanten, Einladungscode, u-law, IPv4/UDP-Huelle
//   PesRel      : zuverlaessiger, geordneter Nachrichtenstrom ueber UDP (Fenster, SACK)
//   PesSession  : Partnersuche (HELLO), Anruf, Ton, Video, Bildschirm, Eingaben, Chat, Dateien
// Dienst "Support": virtueller UDP-Port 9891, Magic-Byte 0xA8. Alles laeuft als normale
// IPv4/UDP-Pakete durch die unveraenderte P2P-Engine (AES-256-CTR + HMAC-SHA256 je Paket).
// Eingehenden Daten wird nie vertraut: Laengen, Zustaende und Absender werden geprueft.
// ============================================================================
public static class PesProto
{
    public const byte Magic = 0xA8;
    public const int Port = 9891;
    public const int Version = 1;
    public const int Mss = 1100;                 // Nutzdaten je Paket (MTU 1380 der Engine wird nie erreicht)
    public const int Frame = 320;                // 20 ms bei 16 kHz mono

    public const byte K_HELLO = 0x01, K_REL = 0x02, K_ACK = 0x03, K_BYE = 0x04, K_AUDIO = 0x10, K_VIDEO = 0x11;

    // Nachrichten auf Strom 0 (Steuerung)
    public const byte M_CHAT = 0x20, M_CALL = 0x21, M_MEDIA = 0x22;
    public const byte M_SCRREQ = 0x30, M_SCRSTAT = 0x31, M_INPUT = 0x32, M_SCROPT = 0x33;
    public const byte M_FOFFER = 0x40, M_FANSW = 0x41, M_FCANCEL = 0x44, M_FDONE = 0x45;
    // Strom 1 (Dateidaten) und Strom 2 (Bildschirm)
    public const byte M_FDATA = 0x42, M_FEND = 0x43, M_RECT = 0x60;

    public const int RoleHelper = 1, RoleCustomer = 2;
    public const int CallIdle = 0, CallOut = 1, CallIn = 2, CallActive = 3;

    public const int VideoChunk = 1100;
    public const int VideoMaxFrame = VideoChunk * 255;
    public const char Sep = (char)31;            // Trenner in Ereigniszeilen (kommt in Texten nicht vor)

    public static byte MuLawEncode(short sample)
    {
        int s = sample;
        int sign = (s >> 8) & 0x80;
        if (sign != 0) s = -s;
        if (s > 32635) s = 32635;
        s += 0x84;
        int exponent = 7;
        int mask = 0x4000;
        while ((s & mask) == 0 && exponent > 0) { exponent--; mask >>= 1; }
        int mantissa = (s >> (exponent + 3)) & 0x0F;
        return (byte)(~(sign | (exponent << 4) | mantissa));
    }

    public static short MuLawDecode(byte b)
    {
        int u = (~b) & 0xFF;
        int sign = u & 0x80;
        int exponent = (u >> 4) & 0x07;
        int mantissa = u & 0x0F;
        int s = ((mantissa << 3) + 0x84) << exponent;
        s -= 0x84;
        return (short)(sign != 0 ? -s : s);
    }

    // ---- Einladungscode "PES1:" + Base64url(Server \n Lobby \n Passwort) ----
    public static string InviteCreate(string server, string lobby, string password)
    {
        byte[] raw = Encoding.UTF8.GetBytes(server + "\n" + lobby + "\n" + password);
        return "PES1:" + Convert.ToBase64String(raw).TrimEnd('=').Replace('+', '-').Replace('/', '_');
    }

    // Liefert { Server, Lobby, Passwort } oder null.
    public static string[] InviteParse(string text)
    {
        if (string.IsNullOrEmpty(text)) return null;
        int i = text.IndexOf("PES1:", StringComparison.Ordinal);
        if (i < 0) return null;
        StringBuilder sb = new StringBuilder();
        for (int k = i + 5; k < text.Length && sb.Length < 600; k++)
        {
            char c = text[k];
            bool ok = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_';
            if (!ok) break;
            sb.Append(c);
        }
        if (sb.Length == 0) return null;
        try
        {
            string b = sb.ToString().Replace('-', '+').Replace('_', '/');
            while (b.Length % 4 != 0) b += "=";
            string s = Encoding.UTF8.GetString(Convert.FromBase64String(b));
            string[] parts = s.Split('\n');
            if (parts.Length < 3 || parts[0].Length == 0 || parts[1].Length == 0) return null;
            string pw = string.Join("\n", parts, 2, parts.Length - 2);
            return new string[] { parts[0], parts[1], pw };
        }
        catch { return null; }
    }

    // Zerlegt "host" oder "host:port"; null bei ungueltiger Eingabe.
    public static bool ParseServer(string text, int defaultPort, out string host, out int port)
    {
        host = null; port = defaultPort;
        if (text == null) return false;
        string t = text.Trim();
        if (t.Length == 0 || t.Length > 255) return false;
        int c = t.LastIndexOf(':');
        string h = t;
        if (c >= 0)
        {
            h = t.Substring(0, c);
            int p;
            if (!int.TryParse(t.Substring(c + 1), out p) || p < 1 || p > 65535) return false;
            port = p;
        }
        if (h.Length == 0) return false;
        foreach (char ch in h)
        {
            bool ok = (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '.' || ch == '-';
            if (!ok) return false;
        }
        host = h;
        return true;
    }

    private const string Alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789";

    public static string RandomText(int length)
    {
        byte[] r = new byte[length * 2];
        using (RandomNumberGenerator rng = RandomNumberGenerator.Create()) rng.GetBytes(r);
        StringBuilder sb = new StringBuilder(length);
        for (int i = 0; i < length; i++) sb.Append(Alphabet[((r[i * 2] << 8) | r[i * 2 + 1]) % Alphabet.Length]);
        return sb.ToString();
    }

    public static string NewLobby() { return "pes-" + RandomText(12).ToLowerInvariant(); }
    public static string NewPassword() { return RandomText(24); }

    // ---- IPv4/UDP-Huelle (die Engine transportiert IPv4-Pakete) ----
    public static byte[] Wrap(uint src, uint dst, int ipId, byte[] payload, int len)
    {
        byte[] p = new byte[28 + len];
        p[0] = 0x45; p[1] = 0;
        PesBytes.WriteU16(p, 2, 28 + len);
        PesBytes.WriteU16(p, 4, ipId & 0xFFFF);
        p[6] = 0x40; p[7] = 0;                    // nicht fragmentieren
        p[8] = 64; p[9] = 17;                     // TTL, UDP
        PesBytes.WriteU32(p, 12, src);
        PesBytes.WriteU32(p, 16, dst);
        int sum = 0;
        for (int i = 0; i < 20; i += 2) sum += (p[i] << 8) | p[i + 1];
        while ((sum >> 16) != 0) sum = (sum & 0xFFFF) + (sum >> 16);
        PesBytes.WriteU16(p, 10, (~sum) & 0xFFFF);
        PesBytes.WriteU16(p, 20, Port);
        PesBytes.WriteU16(p, 22, Port);
        PesBytes.WriteU16(p, 24, 8 + len);
        p[26] = 0; p[27] = 0;                     // UDP-Pruefsumme 0 = keine (IPv4 erlaubt; HMAC der Engine schuetzt)
        Buffer.BlockCopy(payload, 0, p, 28, len);
        return p;
    }

    // Liefert den Offset der Nutzdaten oder -1; src = virtuelle IP des Absenders.
    public static int Unwrap(byte[] ip, out uint src, out int len)
    {
        src = 0; len = 0;
        if (ip == null || ip.Length < 30) return -1;
        if ((ip[0] >> 4) != 4) return -1;
        int ihl = (ip[0] & 15) * 4;
        if (ihl < 20 || ip.Length < ihl + 10) return -1;
        if (ip[9] != 17) return -1;
        if ((PesBytes.ReadU16(ip, 6) & 0x3FFF) != 0) return -1;      // Fragmente werden nicht angenommen
        int total = PesBytes.ReadU16(ip, 2);
        if (total > ip.Length || total < ihl + 10) return -1;
        if (PesBytes.ReadU16(ip, ihl + 2) != Port) return -1;
        int ulen = PesBytes.ReadU16(ip, ihl + 4);
        if (ulen < 10 || ihl + ulen > total) return -1;
        if (ip[ihl + 8] != Magic) return -1;
        src = PesBytes.ReadU32(ip, 12);
        len = ulen - 8;
        return ihl + 8;
    }

    public static string CleanName(string s, int max)
    {
        if (s == null) return "";
        StringBuilder sb = new StringBuilder();
        foreach (char c in s)
        {
            if (c < 32 || c == 127) continue;
            sb.Append(c);
            if (sb.Length >= max) break;
        }
        return sb.ToString().Trim();
    }

    // Dateiname aus dem Netz: nie Pfade, keine reservierten Zeichen, begrenzte Laenge.
    public static string CleanFileName(string s)
    {
        if (s == null) s = "";
        int cut = Math.Max(s.LastIndexOf('/'), s.LastIndexOf('\\'));
        if (cut >= 0) s = s.Substring(cut + 1);
        StringBuilder sb = new StringBuilder();
        foreach (char c in s)
        {
            if (c < 32 || c == 127 || c == '<' || c == '>' || c == ':' || c == '"' || c == '/' || c == '\\' || c == '|' || c == '?' || c == '*') { sb.Append('_'); continue; }
            sb.Append(c);
            if (sb.Length >= 120) break;
        }
        string r = sb.ToString().Trim().TrimEnd('.', ' ');
        while (r.StartsWith(".")) r = r.Substring(1);
        if (r.Length == 0) r = "datei";
        string up = r.ToUpperInvariant();
        int dot = up.IndexOf('.');
        string stem = dot < 0 ? up : up.Substring(0, dot);
        string[] reserved = new string[] { "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9" };
        foreach (string x in reserved) if (stem == x) { r = "_" + r; break; }
        return r;
    }
}

// ----------------------------------------------------------------------------
// Zuverlaessiger Nachrichtenstrom. Paket (nach Magic/Art/Epoche/Strom):
//   REL: seq(4) | fl(1) | Daten      fl Bit0 = Nachrichtenanfang, Bit1 = Nachrichtenende
//   ACK: cum(4) | sack(8)            cum = naechste erwartete Nummer, sack = Bits fuer cum+1 .. cum+64
// Nicht threadsicher - die Sitzung sperrt.
// ----------------------------------------------------------------------------
public sealed class PesRel
{
    private sealed class Seg
    {
        public byte[] Data; public byte Fl; public long LastTx; public int TxCount; public bool Sacked;
    }

    public readonly int Id;
    public const int MaxMessage = 8 * 1024 * 1024;
    private const int RxWindow = 1024;
    private const int MinWindow = 12;            // darunter faellt das Sendefenster nie (zufaellige Verluste sind kein Stau)

    // Senden
    private readonly Queue<byte[]> txMsgs = new Queue<byte[]>();
    private int txOff;
    private long queuedBytes, flightBytes;
    private uint sndUna, sndNxt;
    private readonly Dictionary<uint, Seg> flight = new Dictionary<uint, Seg>();
    private double cwnd = 16, ssthresh = 96;
    private int srtt = -1, rttvar = 0;
    private long lastCutMs = -100000;
    private uint recoverSeq;
    private bool hasSack; private uint highSack;  // hoechstes Paket, das die Gegenseite ausser der Reihe schon hat
    // Empfangen
    private uint rcvNxt;
    private readonly Dictionary<uint, Seg> ooo = new Dictionary<uint, Seg>();
    private MemoryStream asm;
    public bool AckDue;

    public long Retransmits;

    public PesRel(int id) { Id = id; }

    public long Backlog { get { return queuedBytes + flightBytes; } }
    public int Rtt { get { return srtt; } }
    public bool Idle { get { return txMsgs.Count == 0 && flight.Count == 0; } }

    public void Reset()
    {
        txMsgs.Clear(); txOff = 0; queuedBytes = 0; flightBytes = 0;
        sndUna = 0; sndNxt = 0; flight.Clear();
        cwnd = 16; ssthresh = 96; srtt = -1; rttvar = 0; lastCutMs = -100000; recoverSeq = 0;
        hasSack = false; highSack = 0;
        rcvNxt = 0; ooo.Clear(); asm = null; AckDue = false;
    }

    public void Enqueue(byte[] msg)
    {
        if (msg == null || msg.Length == 0 || msg.Length > MaxMessage) return;
        txMsgs.Enqueue(msg);
        queuedBytes += msg.Length;
    }

    private int Rto()
    {
        if (srtt < 0) return 400;
        int r = srtt + 4 * rttvar + 20;
        if (r < 120) r = 120;
        if (r > 1500) r = 1500;
        return r;
    }

    private static byte[] Build(uint seq, Seg s)
    {
        byte[] p = new byte[5 + s.Data.Length];
        PesBytes.WriteU32(p, 0, seq);
        p[4] = s.Fl;
        Buffer.BlockCopy(s.Data, 0, p, 5, s.Data.Length);
        return p;
    }

    // Faellige Wiederholungen und neue Pakete erzeugen (hoechstens budget Stueck).
    public void Pump(long now, int budget, List<byte[]> outPackets)
    {
        if (flight.Count > 0)
        {
            int rto = Rto();
            // Liegt ein Paket nachweislich hinter einer Luecke (die Gegenseite hat schon spaetere), reicht eine kurze Wartezeit
            int holeGate = srtt < 0 ? 60 : Math.Max(40, srtt * 3 / 2);
            uint s = sndUna;
            int scanned = 0;
            while (s != sndNxt && budget > 0 && scanned < 2048)
            {
                Seg g;
                if (flight.TryGetValue(s, out g) && !g.Sacked)
                {
                    bool hole = hasSack && (int)(highSack - s) >= 2;
                    int back = g.TxCount - 3; if (back < 0) back = 0; if (back > 2) back = 2;
                    long wait = hole ? holeGate : ((long)rto << back);
                    if (now - g.LastTx > wait)
                    {
                        g.LastTx = now; g.TxCount++; Retransmits++;
                        outPackets.Add(Build(s, g)); budget--;
                        if (now - lastCutMs > Math.Max(rto, 200) && (int)(s - recoverSeq) >= 0)
                        {
                            lastCutMs = now;
                            ssthresh = Math.Max(MinWindow, cwnd * 0.7);
                            cwnd = Math.Max(MinWindow, cwnd * 0.7);
                            recoverSeq = sndNxt;
                        }
                    }
                }
                s++; scanned++;
            }
        }
        while (budget > 0 && txMsgs.Count > 0 && (int)(sndNxt - sndUna) < (int)cwnd && (int)(sndNxt - sndUna) < RxWindow - 8)
        {
            byte[] m = txMsgs.Peek();
            int n = Math.Min(PesProto.Mss, m.Length - txOff);
            Seg g = new Seg();
            g.Data = new byte[n];
            Buffer.BlockCopy(m, txOff, g.Data, 0, n);
            g.Fl = (byte)((txOff == 0 ? 1 : 0) | (txOff + n >= m.Length ? 2 : 0));
            g.LastTx = now; g.TxCount = 1;
            txOff += n;
            queuedBytes -= n; flightBytes += n;
            if (txOff >= m.Length) { txMsgs.Dequeue(); txOff = 0; }
            flight[sndNxt] = g;
            outPackets.Add(Build(sndNxt, g));
            sndNxt++; budget--;
        }
    }

    public void OnAck(uint cum, ulong sack, long now, List<byte[]> outPackets)
    {
        if ((int)(cum - sndUna) < 0 || (int)(sndNxt - cum) < 0) return;      // veraltet oder unplausibel
        while (sndUna != cum)
        {
            Seg g;
            if (flight.TryGetValue(sndUna, out g))
            {
                flight.Remove(sndUna);
                flightBytes -= g.Data.Length;
                // Laufzeit nur von Paketen messen, die nie wiederholt wurden und nicht hinter einer Luecke warteten
                if (g.TxCount == 1 && !g.Sacked) Sample((int)(now - g.LastTx));
                if (cwnd < ssthresh) cwnd += 1; else cwnd += 1.0 / cwnd;
                if (cwnd > 256) cwnd = 256;
            }
            sndUna++;
        }
        if (hasSack && (int)(highSack - sndUna) < 0) hasSack = false;
        if (sack == 0) return;
        for (int i = 0; i < 64; i++)
        {
            if ((sack & (1UL << i)) == 0) continue;
            uint q = cum + 1 + (uint)i;
            Seg g;
            if (!flight.TryGetValue(q, out g)) continue;
            if (!g.Sacked) { g.Sacked = true; if (g.TxCount == 1) Sample((int)(now - g.LastTx)); }
            if (!hasSack || (int)(q - highSack) > 0) { hasSack = true; highSack = q; }
        }
        // Luecken sofort schliessen (Pump prueft die kurze Wartezeit je Paket)
        Pump(now, 8, outPackets);
    }

    private void Sample(int rtt)
    {
        if (rtt < 0) return;
        if (rtt > 5000) rtt = 5000;
        if (srtt < 0) { srtt = rtt; rttvar = rtt / 2; }
        else
        {
            int d = Math.Abs(srtt - rtt);
            rttvar = (3 * rttvar + d) / 4;
            srtt = (7 * srtt + rtt) / 8;
        }
    }

    // Ein eingehendes Datenpaket; vollstaendige Nachrichten landen in deliver.
    public void OnData(byte[] buf, int off, int len, List<byte[]> deliver)
    {
        if (len < 6) return;
        uint seq = PesBytes.ReadU32(buf, off);
        byte fl = buf[off + 4];
        int n = len - 5;
        if (n > PesProto.Mss + 64) return;
        AckDue = true;
        int d = (int)(seq - rcvNxt);
        if (d < 0 || d >= RxWindow) return;                              // doppelt oder zu weit voraus
        if (d > 0)
        {
            if (!ooo.ContainsKey(seq))
            {
                Seg g = new Seg(); g.Fl = fl; g.Data = new byte[n];
                Buffer.BlockCopy(buf, off + 5, g.Data, 0, n);
                ooo[seq] = g;
            }
            return;
        }
        Accept(fl, buf, off + 5, n, deliver);
        rcvNxt++;
        Seg nx;
        while (ooo.TryGetValue(rcvNxt, out nx))
        {
            ooo.Remove(rcvNxt);
            Accept(nx.Fl, nx.Data, 0, nx.Data.Length, deliver);
            rcvNxt++;
        }
    }

    private void Accept(byte fl, byte[] b, int off, int n, List<byte[]> deliver)
    {
        if ((fl & 1) != 0) asm = new MemoryStream();
        if (asm == null) return;                                        // Mitte ohne Anfang: verwerfen
        if (asm.Length + n > MaxMessage) { asm = null; return; }
        asm.Write(b, off, n);
        if ((fl & 2) != 0) { deliver.Add(asm.ToArray()); asm = null; }
    }

    public byte[] BuildAck()
    {
        AckDue = false;
        byte[] p = new byte[12];
        PesBytes.WriteU32(p, 0, rcvNxt);
        ulong sack = 0;
        if (ooo.Count > 0)
        {
            for (int i = 0; i < 64; i++) if (ooo.ContainsKey(rcvNxt + 1 + (uint)i)) sack |= 1UL << i;
        }
        PesBytes.WriteU64(p, 4, sack);
        return p;
    }
}

public sealed class PesFileInfo
{
    public uint Id;
    public string Name = "";
    public string Path = "";
    public long Size;
    public long Done;
    public int State;        // 0 = wartet auf Antwort, 1 = laeuft, 2 = fertig, 3 = abgebrochen/Fehler, 4 = gesendet, wartet auf Bestaetigung
    public string Error = "";
}

public sealed class PesSession
{
    // ---- Einstellungen (vor Start() setzen) ----
    public string MyName = "";
    public int Role = PesProto.RoleCustomer;
    public int Platform = 1;                     // 1 = Windows, 2 = Android
    public string DownloadDir = "";
    public long MaxFileSize = 4L * 1024 * 1024 * 1024;

    // ---- Rueckrufe (kommen aus Arbeits-Threads, muessen schnell sein) ----
    public volatile Action<byte[], int> OnVideoFrame;                    // JPEG, Drehung 0..3
    public volatile Action<int[], byte[]> OnScreenRect;                  // { sw, sh, x, y, w, h, fl }, JPEG
    public volatile Action<byte[]> OnInput;                              // Eingabe vom Helfer (nur bei erlaubter Steuerung)

    // ---- Ereignisse fuer die Oberflaeche (per Timer abholen): Felder mit PesProto.Sep getrennt ----
    public readonly ConcurrentQueue<string> Events = new ConcurrentQueue<string>();

    // ---- Zustand ----
    public volatile bool Paired;
    public volatile string PartnerName = "";
    public volatile int PartnerRole;
    public volatile int PartnerPlatform;
    public volatile uint PartnerVip;
    public volatile int CallState;
    public volatile bool PartnerCam, PartnerMic;
    public volatile bool MyCam, MyMic = true;
    public volatile bool ShareActive, ControlActive;                     // Kunde: eigener Zustand; Helfer: Zustand des Kunden
    public volatile int ScreenW, ScreenH, ScreenMonitor, ScreenMonitors;
    public volatile int WantQuality = 2, WantMonitor = 0;                // Kunde: Wunsch des Helfers
    private long lastVideoRx, lastAudioRx;

    private readonly PesP2pEngine engine;
    private readonly object lk = new object();
    private readonly PesRel[] rel = new PesRel[] { new PesRel(0), new PesRel(1), new PesRel(2) };
    private static readonly Stopwatch clock = Stopwatch.StartNew();
    private Thread thread;
    private volatile bool running;
    private uint mySid, partnerSid;
    private bool handshake;
    private long lastHelloTx = -100000, lastPartnerRx, callSince;
    private int ipId, audioSeq, videoSeq;
    // Zeiger (zusammengefasst, hoechstens alle 25 ms)
    private int ptrX = -1, ptrY = -1; private bool ptrDirty; private long lastPtrTx;
    // Ton
    private readonly Queue<short[]> jitter = new Queue<short[]>();
    private bool jitterPlaying;
    // Video-Empfang
    private int vSeq = -1, vCount, vGot, vBytes, vRot; private byte[][] vParts;
    // Dateien
    private PesFileInfo txFile, rxFile;
    private FileStream txStream, rxStream;
    private SHA256 txHash, rxHash;
    private string rxTemp = "";

    public PesSession(PesP2pEngine eng) { engine = eng; }

    private static long Now() { return clock.ElapsedMilliseconds; }
    public long VideoAgeMs { get { long t = Interlocked.Read(ref lastVideoRx); return t == 0 ? long.MaxValue : Now() - t; } }
    public long AudioAgeMs { get { long t = Interlocked.Read(ref lastAudioRx); return t == 0 ? long.MaxValue : Now() - t; } }
    public long ScreenBacklog { get { lock (lk) { return rel[2].Backlog; } } }
    public long Retransmits { get { lock (lk) { return rel[0].Retransmits + rel[1].Retransmits + rel[2].Retransmits; } } }
    public int Rtt { get { lock (lk) { return rel[0].Rtt; } } }

    private void Ev(params string[] f) { Events.Enqueue(string.Join(PesProto.Sep.ToString(), f)); string d; while (Events.Count > 2000 && Events.TryDequeue(out d)) { } }

    public void Start()
    {
        if (running) return;
        byte[] r = new byte[4];
        using (RandomNumberGenerator rng = RandomNumberGenerator.Create()) { do { rng.GetBytes(r); mySid = PesBytes.ReadU32(r, 0); } while (mySid == 0); }
        MyName = PesProto.CleanName(MyName, 32);
        running = true;
        engine.InboundSink = OnIp;
        thread = new Thread(Loop); thread.IsBackground = true; thread.Name = "PES-SESSION"; thread.Start();
    }

    public void Stop()
    {
        if (!running) return;
        try { if (CallState != PesProto.CallIdle) Hangup(); } catch { }
        try { lock (lk) { FlushLocked(Now()); } } catch { }
        try { if (Paired) { SendBye(); Thread.Sleep(30); SendBye(); } } catch { }
        running = false;
        if (thread != null) thread.Join(1500);
        engine.InboundSink = null;
        lock (lk) { Unpair("", false); }
    }

    // =========================================================================
    // Senden (roh)
    // =========================================================================
    private void SendRaw(uint dst, byte[] payload)
    {
        uint my = engine.Vip;
        if (my == 0 || dst == 0) return;
        int id = Interlocked.Increment(ref ipId);
        engine.SendIp(PesProto.Wrap(my, dst, id, payload, payload.Length));
    }

    private void SendHello(uint dst, bool toPartner)
    {
        byte[] nm = PesBytes.Utf8Limit(MyName, 32);
        byte[] p = new byte[15 + nm.Length];
        p[0] = PesProto.Magic; p[1] = PesProto.K_HELLO;
        p[2] = PesProto.Version; p[3] = (byte)Role; p[4] = (byte)Platform;
        p[5] = (byte)((Paired && !toPartner) ? 1 : 0);                  // Bit0 = bereits in einer Sitzung
        PesBytes.WriteU32(p, 6, mySid);
        PesBytes.WriteU32(p, 10, toPartner ? partnerSid : 0);
        p[14] = (byte)nm.Length;
        Buffer.BlockCopy(nm, 0, p, 15, nm.Length);
        SendRaw(dst, p);
    }

    // Abmeldung: der Partner muss nicht erst auf den Zeitablauf warten.
    private void SendBye()
    {
        byte[] p = new byte[6];
        p[0] = PesProto.Magic; p[1] = PesProto.K_BYE;
        PesBytes.WriteU32(p, 2, mySid);
        SendRaw(PartnerVip, p);
    }

    private void SendRelPacket(int stream, byte kind, byte[] body)
    {
        byte[] p = new byte[7 + body.Length];
        p[0] = PesProto.Magic; p[1] = kind;
        PesBytes.WriteU32(p, 2, mySid ^ partnerSid);
        p[6] = (byte)stream;
        Buffer.BlockCopy(body, 0, p, 7, body.Length);
        SendRaw(PartnerVip, p);
    }

    // Unter lk: Wiederholungen, neue Pakete und Bestaetigungen aller Stroeme senden.
    private void FlushLocked(long now)
    {
        if (!handshake) return;
        List<byte[]> pk = new List<byte[]>();
        for (int i = 0; i < rel.Length; i++)
        {
            pk.Clear();
            rel[i].Pump(now, i == 0 ? 16 : 12, pk);
            foreach (byte[] b in pk) SendRelPacket(i, PesProto.K_REL, b);
            if (rel[i].AckDue) SendRelPacket(i, PesProto.K_ACK, rel[i].BuildAck());
        }
    }

    private bool SendMsg(int stream, byte[] msg)
    {
        lock (lk)
        {
            if (!handshake) return false;
            rel[stream].Enqueue(msg);
            if (stream == 0) FlushLocked(Now());
            return true;
        }
    }

    private static byte[] Msg(byte type, params byte[] body)
    {
        byte[] m = new byte[1 + body.Length];
        m[0] = type;
        Buffer.BlockCopy(body, 0, m, 1, body.Length);
        return m;
    }

    // =========================================================================
    // Arbeits-Thread
    // =========================================================================
    private void Loop()
    {
        while (running)
        {
            try { Tick(); } catch (Exception ex) { Ev("SYS", "Sitzungsfehler: " + ex.Message); }
            Thread.Sleep(5);
        }
    }

    private void Tick()
    {
        long now = Now();
        List<uint> helloTo = null;
        lock (lk)
        {
            if (Paired && now - lastPartnerRx > 12000) Unpair("Verbindung zum Partner verloren.", true);
            if (CallState == PesProto.CallOut && now - callSince > 45000) { CallState = PesProto.CallIdle; Ev("CALL", "timeout"); EnqueueLocked(0, Msg(PesProto.M_CALL, 5)); }
            if (CallState == PesProto.CallIn && now - callSince > 50000) { CallState = PesProto.CallIdle; Ev("CALL", "missed"); }
            int iv = handshake ? 2000 : 500;
            if (now - lastHelloTx >= iv)
            {
                lastHelloTx = now;
                helloTo = new List<uint>();
                foreach (PesP2pPeerInfo pi in engine.GetPeers()) if (pi.Path != 0 && pi.Vip != 0) helloTo.Add(pi.Vip);
            }
            if (handshake)
            {
                if (ptrDirty && now - lastPtrTx >= 25 && rel[0].Backlog < 4000)
                {
                    ptrDirty = false; lastPtrTx = now;
                    byte[] b = new byte[6];
                    b[0] = PesProto.M_INPUT; b[1] = 1;
                    PesBytes.WriteU16(b, 2, ptrX); PesBytes.WriteU16(b, 4, ptrY);
                    rel[0].Enqueue(b);
                }
                PumpFileLocked();
                FlushLocked(now);
            }
        }
        if (helloTo != null)
        {
            uint pv = PartnerVip;
            foreach (uint v in helloTo) SendHello(v, Paired && v == pv);
        }
    }

    private void EnqueueLocked(int stream, byte[] msg) { if (handshake) rel[stream].Enqueue(msg); }

    // Unter lk. Setzt alles zurueck, was an den Partner gebunden ist.
    private void Unpair(string reason, bool notify)
    {
        bool was = Paired;
        Paired = false; handshake = false; partnerSid = 0;
        foreach (PesRel r in rel) r.Reset();
        CallState = PesProto.CallIdle; PartnerCam = false; PartnerMic = false;
        ShareActive = false; ControlActive = false;
        lock (jitter) { jitter.Clear(); jitterPlaying = false; vSeq = -1; vParts = null; }
        ptrDirty = false;
        AbortTxLocked("Verbindung getrennt", false);
        AbortRxLocked("Verbindung getrennt", false);
        PartnerVip = 0;
        if (was && notify) Ev("PEER", "down", PartnerName, reason);
        PartnerName = "";
    }

    // =========================================================================
    // Empfang (laeuft im UDP-Thread der Engine)
    // =========================================================================
    private void OnIp(byte[] ip)
    {
        if (!running) return;
        uint src; int len;
        int off = PesProto.Unwrap(ip, out src, out len);
        if (off < 0 || len < 2) return;
        byte kind = ip[off + 1];
        try
        {
            if (kind == PesProto.K_HELLO) { OnHello(ip, off, len, src); return; }
            if (!Paired || src != PartnerVip) return;                   // alles andere nur vom Partner
            if (kind == PesProto.K_BYE)
            {
                if (len >= 6) lock (lk) { if (Paired && PesBytes.ReadU32(ip, off + 2) == partnerSid) Unpair("Der Partner hat die Sitzung beendet.", true); }
                return;
            }
            if (kind == PesProto.K_AUDIO) { OnAudio(ip, off, len); return; }
            if (kind == PesProto.K_VIDEO) { OnVideo(ip, off, len); return; }
            if (kind == PesProto.K_REL || kind == PesProto.K_ACK) OnRel(kind, ip, off, len);
        }
        catch (Exception ex) { Ev("SYS", "Paketfehler: " + ex.Message); }
    }

    private void OnHello(byte[] b, int off, int len, uint src)
    {
        if (len < 15) return;
        if (b[off + 2] != PesProto.Version) return;
        int role = b[off + 3], plat = b[off + 4], flags = b[off + 5];
        uint sid = PesBytes.ReadU32(b, off + 6);
        uint echo = PesBytes.ReadU32(b, off + 10);
        int nl = b[off + 14];
        if (nl > 32 || 15 + nl > len || sid == 0) return;
        if (role != PesProto.RoleHelper && role != PesProto.RoleCustomer) return;
        string name = PesProto.CleanName(Encoding.UTF8.GetString(b, off + 15, nl), 32);
        if (name.Length == 0) name = "?";
        bool reply = false;
        lock (lk)
        {
            long now = Now();
            if (Paired && src == PartnerVip)
            {
                if (sid != partnerSid)
                {
                    // Partner hat neu gestartet: alles zuruecksetzen und neu koppeln
                    Unpair("Partner hat neu gestartet.", true);
                }
                else
                {
                    lastPartnerRx = now;
                    PartnerName = name;
                    if (!handshake && echo == mySid) { handshake = true; Ev("PEER", "up", name, role.ToString(), plat.ToString()); }
                    return;
                }
            }
            if (Paired) return;                                         // belegt: andere werden nicht angenommen
            if (role == Role) { return; }                               // Helfer koppelt nur mit Kunde und umgekehrt
            if ((flags & 1) != 0 && echo != mySid) return;              // Gegenseite ist schon vergeben
            Paired = true; PartnerVip = src; partnerSid = sid; PartnerName = name;
            PartnerRole = role; PartnerPlatform = plat; lastPartnerRx = now;
            handshake = echo == mySid;
            foreach (PesRel r in rel) r.Reset();
            if (handshake) Ev("PEER", "up", name, role.ToString(), plat.ToString());
            reply = true;
        }
        if (reply) SendHello(src, true);
    }

    private void OnRel(byte kind, byte[] b, int off, int len)
    {
        if (len < 7 + 5) return;
        List<byte[]> deliver = null;
        int stream;
        lock (lk)
        {
            if (!handshake) return;
            if (PesBytes.ReadU32(b, off + 2) != (mySid ^ partnerSid)) return;
            stream = b[off + 6];
            if (stream >= rel.Length) return;
            long now = Now();
            lastPartnerRx = now;
            if (kind == PesProto.K_REL)
            {
                deliver = new List<byte[]>();
                rel[stream].OnData(b, off + 7, len - 7, deliver);
                SendRelPacket(stream, PesProto.K_ACK, rel[stream].BuildAck());
            }
            else
            {
                if (len < 7 + 12) return;
                List<byte[]> pk = new List<byte[]>();
                rel[stream].OnAck(PesBytes.ReadU32(b, off + 7), PesBytes.ReadU64(b, off + 11), now, pk);
                rel[stream].Pump(now, 12, pk);                          // Fenster ist frei geworden: gleich nachschieben
                foreach (byte[] x in pk) SendRelPacket(stream, PesProto.K_REL, x);
            }
        }
        if (deliver != null) foreach (byte[] m in deliver) { try { OnMessage(stream, m); } catch (Exception ex) { Ev("SYS", "Nachrichtenfehler: " + ex.Message); } }
    }

    private void OnMessage(int stream, byte[] m)
    {
        if (m.Length < 1) return;
        byte t = m[0];
        if (stream == 2)
        {
            if (t != PesProto.M_RECT || m.Length < 14 || Role != PesProto.RoleHelper) return;
            int[] r = new int[7];
            for (int i = 0; i < 6; i++) r[i] = PesBytes.ReadU16(m, 1 + i * 2);
            r[6] = m[13];
            if (r[0] < 16 || r[1] < 16 || r[0] > 8192 || r[1] > 8192) return;
            if (r[4] < 1 || r[5] < 1 || r[2] + r[4] > r[0] || r[3] + r[5] > r[1]) return;
            byte[] jpg = new byte[m.Length - 14];
            Buffer.BlockCopy(m, 14, jpg, 0, jpg.Length);
            ScreenW = r[0]; ScreenH = r[1];
            Action<int[], byte[]> cb = OnScreenRect;
            if (cb != null) cb(r, jpg);
            return;
        }
        if (stream == 1) { OnFileStream(t, m); return; }
        switch (t)
        {
            case PesProto.M_CHAT:
                {
                    if (m.Length > 1 + 8000) return;
                    string text = Encoding.UTF8.GetString(m, 1, m.Length - 1).Replace(PesProto.Sep, ' ');
                    Ev("CHAT", PartnerName, text);
                    break;
                }
            case PesProto.M_CALL:
                if (m.Length >= 2) OnCall(m[1]);
                break;
            case PesProto.M_MEDIA:
                if (m.Length >= 3) { PartnerCam = m[1] != 0; PartnerMic = m[2] != 0; Ev("MEDIA", m[1].ToString(), m[2].ToString()); }
                break;
            case PesProto.M_SCRREQ:
                if (m.Length >= 2 && Role == PesProto.RoleCustomer && m[1] >= 1 && m[1] <= 5) Ev("SCREEN", "req", m[1].ToString());
                break;
            case PesProto.M_SCRSTAT:
                if (m.Length >= 9 && Role == PesProto.RoleHelper)
                {
                    ShareActive = m[1] != 0; ControlActive = m[1] != 0 && m[2] != 0;
                    ScreenW = PesBytes.ReadU16(m, 3); ScreenH = PesBytes.ReadU16(m, 5);
                    ScreenMonitor = m[7]; ScreenMonitors = m[8];
                    Ev("SCREEN", "state", m[1].ToString(), m[2].ToString());
                }
                break;
            case PesProto.M_INPUT:
                if (Role == PesProto.RoleCustomer && ControlActive && ShareActive && m.Length >= 2 && m.Length <= 1 + 1 + 1024)
                {
                    Action<byte[]> cb = OnInput;
                    if (cb != null) { byte[] body = new byte[m.Length - 1]; Buffer.BlockCopy(m, 1, body, 0, body.Length); cb(body); }
                }
                break;
            case PesProto.M_SCROPT:
                if (m.Length >= 3 && Role == PesProto.RoleCustomer)
                {
                    int q = m[1]; if (q < 1) q = 1; if (q > 3) q = 3;
                    WantQuality = q; WantMonitor = m[2];
                    Ev("SCREEN", "opt", q.ToString(), m[2].ToString());
                }
                break;
            case PesProto.M_FOFFER: OnFileOffer(m); break;
            case PesProto.M_FANSW: OnFileAnswer(m); break;
            case PesProto.M_FCANCEL: OnFileCancel(m); break;
            case PesProto.M_FDONE: OnFileDone(m); break;
        }
    }

    // =========================================================================
    // Chat
    // =========================================================================
    public bool SendChat(string text)
    {
        if (string.IsNullOrEmpty(text)) return false;
        if (text.Length > 2000) text = text.Substring(0, 2000);
        byte[] t = Encoding.UTF8.GetBytes(text);
        byte[] m = new byte[1 + t.Length];
        m[0] = PesProto.M_CHAT;
        Buffer.BlockCopy(t, 0, m, 1, t.Length);
        return SendMsg(0, m);
    }

    // =========================================================================
    // Anruf (Ton + Video)
    // =========================================================================
    private void OnCall(int sub)
    {
        bool sendAccept = false, media = false;
        lock (lk)
        {
            switch (sub)
            {
                case 1:
                    if (CallState == PesProto.CallIdle) { CallState = PesProto.CallIn; callSince = Now(); Ev("CALL", "in", PartnerName); }
                    else if (CallState == PesProto.CallOut) { CallState = PesProto.CallActive; sendAccept = true; media = true; Ev("CALL", "active"); }
                    break;
                case 2:
                    if (CallState == PesProto.CallOut) { CallState = PesProto.CallActive; media = true; Ev("CALL", "active"); }
                    break;
                case 3:
                    if (CallState == PesProto.CallOut) { CallState = PesProto.CallIdle; Ev("CALL", "declined"); }
                    break;
                case 4:
                    if (CallState != PesProto.CallIdle) { CallState = PesProto.CallIdle; ClearMediaLocked(); Ev("CALL", "ended"); }
                    break;
                case 5:
                    if (CallState == PesProto.CallIn) { CallState = PesProto.CallIdle; Ev("CALL", "missed"); }
                    break;
            }
        }
        if (sendAccept) SendMsg(0, Msg(PesProto.M_CALL, 2));
        if (media) SendMedia();
    }

    private void ClearMediaLocked() { lock (jitter) { jitter.Clear(); jitterPlaying = false; vSeq = -1; vParts = null; } PartnerCam = false; }

    public bool Call()
    {
        lock (lk)
        {
            if (!handshake || CallState != PesProto.CallIdle) return false;
            CallState = PesProto.CallOut; callSince = Now();
        }
        Ev("CALL", "out");
        return SendMsg(0, Msg(PesProto.M_CALL, 1));
    }

    public void AnswerCall(bool accept)
    {
        lock (lk)
        {
            if (CallState != PesProto.CallIn) return;
            CallState = accept ? PesProto.CallActive : PesProto.CallIdle;
        }
        SendMsg(0, Msg(PesProto.M_CALL, (byte)(accept ? 2 : 3)));
        if (accept) { Ev("CALL", "active"); SendMedia(); }
    }

    public void Hangup()
    {
        int st;
        lock (lk) { st = CallState; CallState = PesProto.CallIdle; ClearMediaLocked(); }
        if (st == PesProto.CallIdle) return;
        SendMsg(0, Msg(PesProto.M_CALL, (byte)(st == PesProto.CallOut ? 5 : (st == PesProto.CallIn ? 3 : 4))));
        Ev("CALL", "ended");
    }

    public void SetMedia(bool cam, bool mic)
    {
        MyCam = cam; MyMic = mic;
        if (CallState == PesProto.CallActive) SendMedia();
    }

    private void SendMedia() { SendMsg(0, Msg(PesProto.M_MEDIA, (byte)(MyCam ? 1 : 0), (byte)(MyMic ? 1 : 0))); }

    // Ein Mikrofon-Frame (320 Samples, 16 kHz mono).
    public void SendAudio(short[] f)
    {
        if (f == null || f.Length < PesProto.Frame) return;
        if (CallState != PesProto.CallActive || !MyMic || !Paired) return;
        byte[] p = new byte[4 + PesProto.Frame];
        p[0] = PesProto.Magic; p[1] = PesProto.K_AUDIO;
        int s = Interlocked.Increment(ref audioSeq);
        PesBytes.WriteU16(p, 2, s & 0xFFFF);
        for (int i = 0; i < PesProto.Frame; i++) p[4 + i] = PesProto.MuLawEncode(f[i]);
        SendRaw(PartnerVip, p);
    }

    private void OnAudio(byte[] b, int off, int len)
    {
        if (CallState != PesProto.CallActive) return;
        int n = len - 4;
        if (n != PesProto.Frame) return;
        short[] fr = new short[n];
        for (int i = 0; i < n; i++) fr[i] = PesProto.MuLawDecode(b[off + 4 + i]);
        Interlocked.Exchange(ref lastAudioRx, Now());
        lock (jitter)
        {
            jitter.Enqueue(fr);
            while (jitter.Count > 12) jitter.Dequeue();
        }
    }

    // Naechster Wiedergabe-Frame (320 Samples); Stille, solange nichts ansteht.
    public short[] PullAudio()
    {
        lock (jitter)
        {
            if (!jitterPlaying) { if (jitter.Count >= 3) jitterPlaying = true; else return new short[PesProto.Frame]; }
            if (jitter.Count == 0) { jitterPlaying = false; return new short[PesProto.Frame]; }
            return jitter.Dequeue();
        }
    }

    // Ein JPEG-Bild der eigenen Kamera, wird in Teilen gesendet (verlorene Bilder werden nicht wiederholt).
    public bool SendVideo(byte[] jpeg, int rotQuarter)
    {
        if (jpeg == null || jpeg.Length == 0 || jpeg.Length > PesProto.VideoMaxFrame) return false;
        if (CallState != PesProto.CallActive || !MyCam || !Paired) return false;
        int cnt = (jpeg.Length + PesProto.VideoChunk - 1) / PesProto.VideoChunk;
        int sq = Interlocked.Increment(ref videoSeq) & 0xFFFF;
        uint dst = PartnerVip;
        for (int i = 0; i < cnt; i++)
        {
            int o = i * PesProto.VideoChunk;
            int n = Math.Min(PesProto.VideoChunk, jpeg.Length - o);
            byte[] p = new byte[7 + n];
            p[0] = PesProto.Magic; p[1] = PesProto.K_VIDEO;
            PesBytes.WriteU16(p, 2, sq);
            p[4] = (byte)i; p[5] = (byte)cnt; p[6] = (byte)(rotQuarter & 3);
            Buffer.BlockCopy(jpeg, o, p, 7, n);
            SendRaw(dst, p);
        }
        return true;
    }

    private void OnVideo(byte[] b, int off, int len)
    {
        if (CallState != PesProto.CallActive || len < 8) return;
        int seq = PesBytes.ReadU16(b, off + 2);
        int idx = b[off + 4], cnt = b[off + 5], rot = b[off + 6] & 3;
        int n = len - 7;
        if (cnt == 0 || idx >= cnt || n <= 0 || n > PesProto.VideoChunk) return;
        byte[] done = null;
        lock (jitter)
        {
            if (vParts == null || vSeq != seq || vCount != cnt)
            {
                // Nur neuere Bilder beginnen (verspaetete Teile alter Bilder verwerfen)
                if (vParts != null && vSeq >= 0 && ((seq - vSeq) & 0xFFFF) > 0x8000) return;
                vSeq = seq; vCount = cnt; vGot = 0; vBytes = 0; vRot = rot; vParts = new byte[cnt][];
            }
            if (vParts[idx] != null) return;
            if (vBytes + n > PesProto.VideoMaxFrame) { vParts = null; return; }
            byte[] part = new byte[n];
            Buffer.BlockCopy(b, off + 7, part, 0, n);
            vParts[idx] = part; vGot++; vBytes += n;
            if (vGot == vCount)
            {
                done = new byte[vBytes];
                int o = 0;
                foreach (byte[] x in vParts) { Buffer.BlockCopy(x, 0, done, o, x.Length); o += x.Length; }
                vParts = null;
            }
        }
        if (done != null)
        {
            Interlocked.Exchange(ref lastVideoRx, Now());
            Action<byte[], int> cb = OnVideoFrame;
            if (cb != null) cb(done, rot);
        }
    }

    // =========================================================================
    // Bildschirm
    // =========================================================================
    // Helfer: 1 = ansehen, 2 = ansehen und steuern, 3 = beenden, 4 = Steuerung abgeben, 5 = Komplettbild neu senden
    public bool RequestScreen(int sub)
    {
        if (Role != PesProto.RoleHelper || sub < 1 || sub > 5) return false;
        return SendMsg(0, Msg(PesProto.M_SCRREQ, (byte)sub));
    }

    public bool SetScreenOptions(int quality, int monitor)
    {
        if (Role != PesProto.RoleHelper) return false;
        return SendMsg(0, Msg(PesProto.M_SCROPT, (byte)quality, (byte)monitor));
    }

    // Kunde: eigenen Freigabe-Zustand setzen und dem Helfer melden.
    public void SetShare(bool share, bool control, int w, int h, int monitor, int monitors)
    {
        if (Role != PesProto.RoleCustomer) return;
        ShareActive = share; ControlActive = share && control;
        ScreenW = w; ScreenH = h; ScreenMonitor = monitor; ScreenMonitors = monitors;
        byte[] m = new byte[9];
        m[0] = PesProto.M_SCRSTAT; m[1] = (byte)(share ? 1 : 0); m[2] = (byte)(share && control ? 1 : 0);
        PesBytes.WriteU16(m, 3, w); PesBytes.WriteU16(m, 5, h);
        m[7] = (byte)monitor; m[8] = (byte)monitors;
        SendMsg(0, m);
    }

    // Kunde: ein geaendertes Rechteck (JPEG) senden. fl Bit0 = letztes Rechteck dieses Durchgangs.
    public bool SendScreenRect(int sw, int sh, int x, int y, int w, int h, int fl, byte[] jpeg)
    {
        if (Role != PesProto.RoleCustomer || !ShareActive || jpeg == null) return false;
        byte[] m = new byte[14 + jpeg.Length];
        m[0] = PesProto.M_RECT;
        PesBytes.WriteU16(m, 1, sw); PesBytes.WriteU16(m, 3, sh);
        PesBytes.WriteU16(m, 5, x); PesBytes.WriteU16(m, 7, y);
        PesBytes.WriteU16(m, 9, w); PesBytes.WriteU16(m, 11, h);
        m[13] = (byte)fl;
        Buffer.BlockCopy(jpeg, 0, m, 14, jpeg.Length);
        lock (lk)
        {
            if (!handshake) return false;
            rel[2].Enqueue(m);
            FlushLocked(Now());
        }
        return true;
    }

    // ---- Eingaben des Helfers (Koordinaten 0..65535 bezogen auf den freigegebenen Bildschirm) ----
    public void InputMove(int x, int y)
    {
        if (Role != PesProto.RoleHelper || !ControlActive) return;
        lock (lk) { ptrX = Clamp16(x); ptrY = Clamp16(y); ptrDirty = true; }
    }

    private static int Clamp16(int v) { return v < 0 ? 0 : (v > 65535 ? 65535 : v); }

    private bool SendInput(byte[] body)
    {
        if (Role != PesProto.RoleHelper || !ControlActive) return false;
        byte[] m = new byte[1 + body.Length];
        m[0] = PesProto.M_INPUT;
        Buffer.BlockCopy(body, 0, m, 1, body.Length);
        lock (lk)
        {
            if (!handshake) return false;
            ptrDirty = false;                                           // die Taste traegt die aktuelle Position selbst
            rel[0].Enqueue(m);
            FlushLocked(Now());
        }
        return true;
    }

    public bool InputButton(int button, bool down, int x, int y)
    {
        byte[] b = new byte[7];
        b[0] = 2; b[1] = (byte)button; b[2] = (byte)(down ? 1 : 0);
        PesBytes.WriteU16(b, 3, Clamp16(x)); PesBytes.WriteU16(b, 5, Clamp16(y));
        return SendInput(b);
    }

    public bool InputWheel(int delta, int x, int y)
    {
        if (delta > 32767) delta = 32767; if (delta < -32768) delta = -32768;
        byte[] b = new byte[7];
        b[0] = 3; PesBytes.WriteU16(b, 1, delta & 0xFFFF);
        PesBytes.WriteU16(b, 3, Clamp16(x)); PesBytes.WriteU16(b, 5, Clamp16(y));
        return SendInput(b);
    }

    public bool InputKey(int vk, bool down, bool extended)
    {
        byte[] b = new byte[5];
        b[0] = 4; PesBytes.WriteU16(b, 1, vk & 0xFFFF); b[3] = (byte)(down ? 1 : 0); b[4] = (byte)(extended ? 1 : 0);
        return SendInput(b);
    }

    public bool InputText(string text)
    {
        if (string.IsNullOrEmpty(text)) return false;
        if (text.Length > 200) text = text.Substring(0, 200);
        byte[] t = Encoding.UTF8.GetBytes(text);
        byte[] b = new byte[1 + t.Length];
        b[0] = 5;
        Buffer.BlockCopy(t, 0, b, 1, t.Length);
        return SendInput(b);
    }

    // =========================================================================
    // Dateien (eine Uebertragung je Richtung; der Empfaenger muss zustimmen)
    // =========================================================================
    public PesFileInfo TxFile { get { lock (lk) { return Copy(txFile); } } }
    public PesFileInfo RxFile { get { lock (lk) { return Copy(rxFile); } } }

    private static PesFileInfo Copy(PesFileInfo f)
    {
        if (f == null) return null;
        PesFileInfo c = new PesFileInfo();
        c.Id = f.Id; c.Name = f.Name; c.Path = f.Path; c.Size = f.Size; c.Done = f.Done; c.State = f.State; c.Error = f.Error;
        return c;
    }

    // Liefert null bei Erfolg, sonst eine Fehlermeldung.
    public string OfferFile(string path)
    {
        try
        {
            FileInfo fi = new FileInfo(path);
            if (!fi.Exists) return "Datei nicht gefunden.";
            if (fi.Length > MaxFileSize) return "Datei ist zu gross.";
            lock (lk)
            {
                if (!handshake) return "Nicht verbunden.";
                if (txFile != null && (txFile.State < 2 || txFile.State == 4)) return "Es laeuft bereits eine Uebertragung.";
                byte[] r = new byte[4];
                using (RandomNumberGenerator rng = RandomNumberGenerator.Create()) rng.GetBytes(r);
                PesFileInfo f = new PesFileInfo();
                f.Id = PesBytes.ReadU32(r, 0); f.Name = PesProto.CleanFileName(fi.Name); f.Path = fi.FullName; f.Size = fi.Length;
                txFile = f;
                byte[] nm = PesBytes.Utf8Limit(f.Name, 240);
                byte[] m = new byte[13 + nm.Length];
                m[0] = PesProto.M_FOFFER;
                PesBytes.WriteU32(m, 1, f.Id);
                PesBytes.WriteU64(m, 5, (ulong)f.Size);
                Buffer.BlockCopy(nm, 0, m, 13, nm.Length);
                rel[0].Enqueue(m);
                FlushLocked(Now());
            }
            return null;
        }
        catch (Exception ex) { return ex.Message; }
    }

    private void OnFileOffer(byte[] m)
    {
        if (m.Length < 14 || m.Length > 13 + 300) return;
        uint id = PesBytes.ReadU32(m, 1);
        ulong size = PesBytes.ReadU64(m, 5);
        string name = PesProto.CleanFileName(Encoding.UTF8.GetString(m, 13, m.Length - 13));
        lock (lk)
        {
            if ((rxFile != null && rxFile.State < 2) || size > (ulong)MaxFileSize)
            {
                rel[0].Enqueue(Msg(PesProto.M_FANSW, m[1], m[2], m[3], m[4], 0));
                return;
            }
            PesFileInfo f = new PesFileInfo();
            f.Id = id; f.Name = name; f.Size = (long)size;
            rxFile = f;
        }
        Ev("FILE", "offer", id.ToString(), name, size.ToString());
    }

    // Empfaenger: Angebot annehmen oder ablehnen. Liefert null bei Erfolg.
    public string AnswerFile(bool accept)
    {
        lock (lk)
        {
            if (rxFile == null || rxFile.State != 0) return "Kein offenes Angebot.";
            byte[] a = new byte[6];
            a[0] = PesProto.M_FANSW; PesBytes.WriteU32(a, 1, rxFile.Id); a[5] = (byte)(accept ? 1 : 0);
            if (!accept) { rxFile.State = 3; rxFile.Error = "abgelehnt"; rel[0].Enqueue(a); FlushLocked(Now()); return null; }
            try
            {
                Directory.CreateDirectory(DownloadDir);
                rxTemp = System.IO.Path.Combine(DownloadDir, rxFile.Name + "." + rxFile.Id.ToString("x8") + ".part");
                rxStream = new FileStream(rxTemp, FileMode.Create, FileAccess.Write, FileShare.None, 65536);
                rxHash = SHA256.Create();
                rxFile.State = 1;
            }
            catch (Exception ex)
            {
                rxFile.State = 3; rxFile.Error = ex.Message;
                a[5] = 0; rel[0].Enqueue(a); FlushLocked(Now());
                return ex.Message;
            }
            rel[0].Enqueue(a); FlushLocked(Now());
        }
        return null;
    }

    private void OnFileAnswer(byte[] m)
    {
        if (m.Length < 6) return;
        uint id = PesBytes.ReadU32(m, 1);
        bool ok = m[5] != 0;
        lock (lk)
        {
            if (txFile == null || txFile.Id != id || txFile.State != 0) return;
            if (!ok) { txFile.State = 3; txFile.Error = "abgelehnt"; Ev("FILE", "declined", txFile.Name); return; }
            try
            {
                txStream = new FileStream(txFile.Path, FileMode.Open, FileAccess.Read, FileShare.Read, 65536);
                txHash = SHA256.Create();
                txFile.State = 1;
                Ev("FILE", "sending", txFile.Name);
            }
            catch (Exception ex) { AbortTxLocked(ex.Message, true); }
        }
    }

    // Unter lk: Dateidaten nachschieben, solange der Strom nicht staut.
    private void PumpFileLocked()
    {
        if (txFile == null || txFile.State != 1 || txStream == null) return;
        try
        {
            int rounds = 0;
            while (rel[1].Backlog < 256 * 1024 && rounds++ < 8)
            {
                byte[] buf = new byte[5 + 32768];
                int n = txStream.Read(buf, 5, 32768);
                if (n <= 0)
                {
                    txHash.TransformFinalBlock(new byte[0], 0, 0);
                    byte[] e = new byte[5 + 32];
                    e[0] = PesProto.M_FEND; PesBytes.WriteU32(e, 1, txFile.Id);
                    Buffer.BlockCopy(txHash.Hash, 0, e, 5, 32);
                    rel[1].Enqueue(e);
                    try { txStream.Close(); } catch { }
                    txStream = null;
                    txFile.State = 4;                                   // gesendet, wartet auf Bestaetigung
                    return;
                }
                txHash.TransformBlock(buf, 5, n, null, 0);
                buf[0] = PesProto.M_FDATA; PesBytes.WriteU32(buf, 1, txFile.Id);
                if (n < 32768) Array.Resize(ref buf, 5 + n);
                rel[1].Enqueue(buf);
                txFile.Done += n;
            }
        }
        catch (Exception ex) { AbortTxLocked(ex.Message, true); }
    }

    private void OnFileStream(byte t, byte[] m)
    {
        if (m.Length < 5) return;
        uint id = PesBytes.ReadU32(m, 1);
        string doneEv = null, donePath = null;
        lock (lk)
        {
            if (rxFile == null || rxFile.Id != id || rxFile.State != 1 || rxStream == null) return;
            try
            {
                if (t == PesProto.M_FDATA)
                {
                    int n = m.Length - 5;
                    if (rxFile.Done + n > rxFile.Size) { AbortRxLocked("mehr Daten als angekuendigt", true); return; }
                    rxStream.Write(m, 5, n);
                    rxHash.TransformBlock(m, 5, n, null, 0);
                    rxFile.Done += n;
                }
                else if (t == PesProto.M_FEND && m.Length >= 37)
                {
                    rxHash.TransformFinalBlock(new byte[0], 0, 0);
                    byte[] h = rxHash.Hash;
                    bool ok = rxFile.Done == rxFile.Size;
                    for (int i = 0; ok && i < 32; i++) if (h[i] != m[5 + i]) ok = false;
                    rxStream.Close(); rxStream = null;
                    if (!ok) { AbortRxLocked("Pruefsumme stimmt nicht", true); return; }
                    string target = System.IO.Path.Combine(DownloadDir, rxFile.Name);
                    int k = 1;
                    while (File.Exists(target) || Directory.Exists(target))
                    {
                        string stem = System.IO.Path.GetFileNameWithoutExtension(rxFile.Name), ext = System.IO.Path.GetExtension(rxFile.Name);
                        target = System.IO.Path.Combine(DownloadDir, stem + " (" + k + ")" + ext);
                        k++;
                    }
                    File.Move(rxTemp, target);
                    rxFile.Path = target; rxFile.State = 2;
                    byte[] d = new byte[6];
                    d[0] = PesProto.M_FDONE; PesBytes.WriteU32(d, 1, id); d[5] = 1;
                    rel[0].Enqueue(d);
                    doneEv = rxFile.Name; donePath = target;
                }
            }
            catch (Exception ex) { AbortRxLocked(ex.Message, true); }
        }
        if (doneEv != null) Ev("FILE", "received", doneEv, donePath);
    }

    private void OnFileCancel(byte[] m)
    {
        if (m.Length < 5) return;
        uint id = PesBytes.ReadU32(m, 1);
        lock (lk)
        {
            if (rxFile != null && rxFile.Id == id && rxFile.State < 2) AbortRxLocked("vom Absender abgebrochen", false);
            if (txFile != null && txFile.Id == id && (txFile.State < 2 || txFile.State == 4)) AbortTxLocked("vom Empfaenger abgebrochen", false);
        }
    }

    private void OnFileDone(byte[] m)
    {
        if (m.Length < 6) return;
        uint id = PesBytes.ReadU32(m, 1);
        lock (lk)
        {
            if (txFile == null || txFile.Id != id) return;
            if (m[5] != 0) { txFile.State = 2; Ev("FILE", "sent", txFile.Name); }
            else { txFile.State = 3; txFile.Error = "Empfaenger meldet Fehler"; Ev("FILE", "failed", txFile.Name, txFile.Error); }
        }
    }

    public void CancelFiles()
    {
        lock (lk)
        {
            if (txFile != null && (txFile.State < 2 || txFile.State == 4)) AbortTxLocked("abgebrochen", true);
            if (rxFile != null && rxFile.State < 2) AbortRxLocked("abgebrochen", true);
            FlushLocked(Now());
        }
    }

    private void AbortTxLocked(string why, bool tell)
    {
        try { if (txStream != null) txStream.Close(); } catch { }
        txStream = null;
        if (txFile == null || txFile.State == 2 || txFile.State == 3) return;
        txFile.State = 3; txFile.Error = why;
        if (tell && handshake) { byte[] c = new byte[5]; c[0] = PesProto.M_FCANCEL; PesBytes.WriteU32(c, 1, txFile.Id); rel[0].Enqueue(c); }
        Ev("FILE", "failed", txFile.Name, why);
    }

    private void AbortRxLocked(string why, bool tell)
    {
        try { if (rxStream != null) rxStream.Close(); } catch { }
        rxStream = null;
        try { if (rxTemp.Length > 0 && File.Exists(rxTemp)) File.Delete(rxTemp); } catch { }
        rxTemp = "";
        if (rxFile == null || rxFile.State == 2 || rxFile.State == 3) return;
        bool wasOffer = rxFile.State == 0;
        rxFile.State = 3; rxFile.Error = why;
        if (tell && handshake) { byte[] c = new byte[5]; c[0] = PesProto.M_FCANCEL; PesBytes.WriteU32(c, 1, rxFile.Id); rel[0].Enqueue(c); }
        Ev("FILE", wasOffer ? "withdrawn" : "failed", rxFile.Name, why);
    }
}
