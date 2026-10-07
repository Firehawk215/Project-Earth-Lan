// ============================================================================
// Project Earth Support - P2P-Kern (uebernommen aus dem Project Earth LAN Manager)
//   PesBytes       : Big-Endian-Helfer
//   PesP2pCrypto   : AES-256-CTR + HMAC-SHA256 (Encrypt-then-MAC), 16 Byte Tag
//   PesP2pEngine   : Signaling-Client, UDP Hole Punching, Relay-Fallback
// Das Protokoll (Magic 'PS'/'PE', Schluesselableitung, Lobby-ID) ist unveraendert.
// Statt eines virtuellen Netzwerkadapters gibt es SendIp() und InboundSink (IPv4-Pakete).
// Bewusst C# 5 (Windows PowerShell 5.1 / Add-Type / PS2EXE kompatibel).
// ============================================================================

public static class PesBytes
{
    public static uint ReadU32(byte[] b, int o) { return ((uint)b[o] << 24) | ((uint)b[o + 1] << 16) | ((uint)b[o + 2] << 8) | b[o + 3]; }
    public static void WriteU32(byte[] b, int o, uint v) { b[o] = (byte)(v >> 24); b[o + 1] = (byte)(v >> 16); b[o + 2] = (byte)(v >> 8); b[o + 3] = (byte)v; }
    public static int ReadU16(byte[] b, int o) { return (b[o] << 8) | b[o + 1]; }
    public static void WriteU16(byte[] b, int o, int v) { b[o] = (byte)(v >> 8); b[o + 1] = (byte)v; }
    public static ulong ReadU64(byte[] b, int o) { return ((ulong)ReadU32(b, o) << 32) | ReadU32(b, o + 4); }
    public static void WriteU64(byte[] b, int o, ulong v) { WriteU32(b, o, (uint)(v >> 32)); WriteU32(b, o + 4, (uint)v); }
    public static string IpToString(uint ip) { return (ip >> 24) + "." + ((ip >> 16) & 255) + "." + ((ip >> 8) & 255) + "." + (ip & 255); }
    public static uint IpToUInt(IPAddress a) { return ReadU32(a.GetAddressBytes(), 0); }
    public static IPAddress UIntToIp(uint v) { byte[] b = new byte[4]; WriteU32(b, 0, v); return new IPAddress(b); }
    public static bool IsPrivate(IPAddress a)
    {
        byte[] b = a.GetAddressBytes();
        if (b.Length != 4) return false;
        return b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) || (b[0] == 192 && b[1] == 168) || (b[0] == 100 && b[1] >= 64 && b[1] <= 127);
    }
    public static byte[] Utf8Limit(string s, int maxBytes)
    {
        if (s == null) s = "";
        while (s.Length > 0 && Encoding.UTF8.GetByteCount(s) > maxBytes) s = s.Substring(0, s.Length - 1);
        return Encoding.UTF8.GetBytes(s);
    }
}

// ----------------------------------------------------------------------------
// Paketformat Peer <-> Peer (alles nach dem Header ist verschluesselt):
//   [0..1]  Magic 'P''E'   [2] Typ   [3..10] Absender-NodeId   [11..14] Seq
//   [15..]  AES-256-CTR(Nutzdaten)    [letzte 16] HMAC-SHA256(Header+Chiffrat)
// CTR-Zaehlerblock = NodeId(8) | Seq(4) | Blocknummer(4) -> nie doppelt, weil jede
// Sitzung eine neue Zufalls-NodeId bekommt und Seq pro Paket hochzaehlt.
// Eine Instanz pro Thread verwenden (HMAC/ICryptoTransform sind nicht threadsicher).
// ----------------------------------------------------------------------------
public sealed class PesP2pCrypto
{
    public const int Hdr = 15;
    public const int Tag = 16;
    private readonly ICryptoTransform ecb;
    private readonly HMACSHA256 mac;

    public PesP2pCrypto(byte[] encKey, byte[] macKey)
    {
        Aes aes = Aes.Create();
        aes.Mode = CipherMode.ECB;
        aes.Padding = PaddingMode.None;
        aes.Key = encKey;
        ecb = aes.CreateEncryptor();
        mac = new HMACSHA256(macKey);
    }

    private void Ctr(ulong node, uint seq, byte[] src, int srcOff, byte[] dst, int dstOff, int len)
    {
        if (len <= 0) return;
        int blocks = (len + 15) / 16;
        byte[] ctr = new byte[blocks * 16];
        for (int b = 0; b < blocks; b++)
        {
            int o = b * 16;
            PesBytes.WriteU64(ctr, o, node);
            PesBytes.WriteU32(ctr, o + 8, seq);
            PesBytes.WriteU32(ctr, o + 12, (uint)b);
        }
        byte[] ks = new byte[ctr.Length];
        ecb.TransformBlock(ctr, 0, ctr.Length, ks, 0);
        for (int i = 0; i < len; i++) dst[dstOff + i] = (byte)(src[srcOff + i] ^ ks[i]);
    }

    public byte[] Seal(byte type, ulong node, uint seq, byte[] body, int off, int len)
    {
        byte[] p = new byte[Hdr + len + Tag];
        p[0] = 0x50; p[1] = 0x45; p[2] = type;
        PesBytes.WriteU64(p, 3, node);
        PesBytes.WriteU32(p, 11, seq);
        Ctr(node, seq, body, off, p, Hdr, len);
        byte[] h = mac.ComputeHash(p, 0, Hdr + len);
        Buffer.BlockCopy(h, 0, p, Hdr + len, Tag);
        return p;
    }

    // Liefert die entschluesselten Nutzdaten oder null (falscher Schluessel / manipuliert).
    public byte[] Open(byte[] buf, int off, int len, out byte type, out ulong node, out uint seq)
    {
        type = 0; node = 0; seq = 0;
        if (len < Hdr + Tag || buf[off] != 0x50 || buf[off + 1] != 0x45) return null;
        int bodyLen = len - Hdr - Tag;
        byte[] h = mac.ComputeHash(buf, off, Hdr + bodyLen);
        int diff = 0;
        for (int i = 0; i < Tag; i++) diff |= h[i] ^ buf[off + Hdr + bodyLen + i];
        if (diff != 0) return null;
        type = buf[off + 2];
        node = PesBytes.ReadU64(buf, off + 3);
        seq = PesBytes.ReadU32(buf, off + 11);
        byte[] body = new byte[bodyLen];
        Ctr(node, seq, buf, off + Hdr, body, 0, bodyLen);
        return body;
    }
}

public sealed class PesP2pPeer
{
    public ulong NodeId;
    public string Name = "";
    public uint Vip;
    public IPEndPoint PublicEp;
    public List<IPEndPoint> LocalEps = new List<IPEndPoint>();
    public volatile IPEndPoint DirectEp;   // bestaetigter direkter Weg (nach Hole Punching)
    public volatile int Path;              // 0 = verbinde / punching, 1 = direkt, 2 = relay
    public long LastRxMs;
    public long LastHelloMs;
    public long LastRelayHelloMs;
    public long PunchStartMs;
    public volatile int RttMs = -1;
    public long RxBytes;
    public long TxBytes;
    public volatile int AuthFails;
    public volatile bool InServerList = true;
    public bool HasRev;          // Info kam ueber Erweiterung E2 (mit Revision)
    public uint InfoRev;         // Lobby-Revision dieser Info
    public bool Punching;        // Hole Punching hat tatsaechlich begonnen (fuer den Relay-Timer)
    // Replay-Schutz (Sliding Window, 64 Pakete)
    public bool AnySeq;
    public uint MaxSeq;
    public ulong Window;
}

public sealed class PesP2pPeerInfo
{
    public string Name;
    public string Ip;
    public string Mode;
    public string Endpoint;
    public int RttMs;
    public long RxBytes;
    public long TxBytes;
    public ulong NodeId;
    public uint Vip;
    public int Path;
}

public sealed class PesP2pEngine
{
    // ---- Protokoll-Konstanten -------------------------------------------------
    public const byte ProtoVersion = 1;
    private const byte T_HELLO = 1, T_HELLO_ACK = 2, T_DATA = 4, T_BYE = 5;
    private const byte S_REGISTER = 0x10, S_LEAVE = 0x11, S_RELAY = 0x12;
    private const byte S_WELCOME = 0x20, S_PEER = 0x21, S_RELAYED = 0x22, S_ERROR = 0x23, S_MEMBERS = 0x24;
    private const byte S_SYNC = 0x25, S_PEER2 = 0x26, S_GONE = 0x27, EXT_V2 = 0xE2;
    private const int SIO_UDP_CONNRESET = -1744830452;
    // Hole Punching: hoechstens so viele Mitspieler je 200-ms-Takt anpingen (bei 500 Leuten in
    // einer Lobby wuerde sonst jeder neue Mitspieler seinen Upload und den Router fluten)
    public int PunchBudgetPerTick = 120;

    // ---- Einstellungen (vor Start() setzbar) ------------------------------------
    public int PreferredPort = 9892;       // fester Port = feste Firewall-Regel / optionale Portweiterleitung
    public IPAddress BindAddress = IPAddress.Any;   // zentrale Adapterauswahl: nur ueber diesen Adapter senden/empfangen
    public volatile Action<byte[]> InboundSink;     // geprueft eingehende IPv4-Pakete (statt Adapter)
    public bool AllowRelay = true;         // Fallback ueber den Vermittlungsserver bei symmetrischem NAT
    // Broadcast-Firewall: Hintergrund-"Laerm" von Windows, Linux und macOS (Namensdienste,
    // Geraetesuche, App-Suchfunktionen) wird weder gesendet noch angenommen. Laesst sich
    // zur Laufzeit per SetNoiseFilter() umstellen (GUI: "Broadcast-Firewall").
    private volatile HashSet<int> noisePorts = new HashSet<int>(new int[] { 5353, 5355, 137, 138, 1900, 3702, 67, 68, 17500, 57621, 1716, 21027, 427, 8611, 8612, 161 });
    private volatile bool noiseEnabled = true, noiseIgmp = true, noiseStrict = true;
    private readonly ConcurrentDictionary<int, long> noiseStats = new ConcurrentDictionary<int, long>();
    private long noiseBlocked;
    public long NoiseBlocked { get { return Interlocked.Read(ref noiseBlocked); } }
    public bool NoiseFilterEnabled { get { return noiseEnabled; } }

    public void SetNoiseFilter(bool enabled, int[] udpPorts, bool blockIgmp, bool strict)
    {
        HashSet<int> h = new HashSet<int>();
        if (udpPorts != null) foreach (int x in udpPorts) if (x > 0 && x < 65536) h.Add(x);
        noisePorts = h;
        noiseIgmp = blockIgmp;
        noiseStrict = strict;
        noiseEnabled = enabled;
    }

    public void ResetNoiseStats() { noiseStats.Clear(); Interlocked.Exchange(ref noiseBlocked, 0); }

    // "5353=120;137=40;-2=7" (-2 = IGMP), sortiert nach Anzahl
    public string GetNoiseStats()
    {
        List<KeyValuePair<int, long>> l = new List<KeyValuePair<int, long>>(noiseStats);
        l.Sort(delegate (KeyValuePair<int, long> a, KeyValuePair<int, long> b) { return b.Value.CompareTo(a.Value); });
        StringBuilder sb = new StringBuilder();
        foreach (KeyValuePair<int, long> kv in l) sb.Append(kv.Key).Append('=').Append(kv.Value).Append(';');
        return sb.ToString();
    }
    public int PunchTimeoutMs = 8000;      // so lange Hole Punching, bevor Relay genutzt wird
    public int PeerTimeoutMs = 20000;      // ohne Lebenszeichen -> Verbindung neu aufbauen

    // ---- Status (von PowerShell per Timer gelesen) ------------------------------
    private volatile string state = "Getrennt";
    public string State { get { return state; } }
    public volatile string LastError = "";
    public volatile string AssignedIp = "";
    public volatile int PrefixLength = 16;
    public volatile string PublicEndpoint = "";
    public volatile bool IpChanged = false;
    public volatile bool ServerReachable = false;
    public int LocalPort { get { return localPort; } }
    public bool IsRunning { get { return running; } }
    public uint Vip { get { return vip; } }
    public ulong OwnNodeId { get { return nodeId; } }
    public int PeerCount { get { lock (sync) { return byNode.Count; } } }
    public readonly ConcurrentQueue<string> Log = new ConcurrentQueue<string>();

    // ---- intern -----------------------------------------------------------------
    private readonly object sync = new object();
    private readonly Dictionary<ulong, PesP2pPeer> byNode = new Dictionary<ulong, PesP2pPeer>();
    private readonly Dictionary<uint, PesP2pPeer> byVip = new Dictionary<uint, PesP2pPeer>();
    private static readonly Stopwatch clock = Stopwatch.StartNew();
    private Socket sock;
    private readonly object tunLock = new object();
    private ManualResetEvent stopEvent;
    private Thread udpThread, maintThread;
    private volatile bool stopping, running;
    private PesP2pCrypto cTun, cUdp, cMaint;
    private byte[] lobbyId, machineKey;
    private ulong nodeId;
    private string displayName = "", serverHost = "";
    private int serverPort, localPort;
    private volatile IPEndPoint serverEp;
    private long lastResolveMs = -1000000, lastRegTxMs = -1000000, lastServerRxMs = 0;
    private volatile bool gotWelcome;
    private long lastGoneCleanMs;
    private volatile uint vip, mask, bcast;
    private int seqCounter;
    private byte[] cookie = new byte[8];                 // Anti-Spoofing-Cookie vom Server
    // Erweiterung E2: Abgleich der Mitgliederliste (nur im Empfangs-Thread benutzt)
    private uint syncRev;
    private int syncTotal;
    private readonly HashSet<ulong> syncIds = new HashSet<ulong>();
    private readonly Dictionary<ulong, KeyValuePair<uint, long>> gone = new Dictionary<ulong, KeyValuePair<uint, long>>();

    private static long Now() { return clock.ElapsedMilliseconds; }

    private void AddLog(string text)
    {
        Log.Enqueue(DateTime.Now.ToString("HH:mm:ss") + "  " + text);
        string dummy;
        while (Log.Count > 400 && Log.TryDequeue(out dummy)) { }
    }

    private void SetState(string s) { if (state != s) { state = s; AddLog("Status: " + s); } }

    private uint NextSeq() { return (uint)Interlocked.Increment(ref seqCounter); }

    // Lobby-Schluessel: PBKDF2 (100.000 Runden) aus Passwort + Lobbyname.
    // Der Server sieht nur die LobbyId (Hash des Namens) - nie Passwort oder Schluessel.
    public static byte[] DeriveLobbyId(string lobbyName)
    {
        using (SHA256 sha = SHA256.Create())
        {
            byte[] h = sha.ComputeHash(Encoding.UTF8.GetBytes("PEL-LOBBY-V1|" + lobbyName.Trim().ToLowerInvariant()));
            byte[] id = new byte[16];
            Buffer.BlockCopy(h, 0, id, 0, 16);
            return id;
        }
    }

    // =========================================================================
    // START
    // =========================================================================
    public void Start(string serverHostName, int serverUdpPort, string lobbyName, string password,
                      string myName, string machineKeyHex)
    {
        if (running) throw new InvalidOperationException("P2P laeuft bereits.");
        if (string.IsNullOrEmpty(lobbyName) || lobbyName.Trim().Length < 3) throw new ArgumentException("Der Lobby-Name muss mindestens 3 Zeichen haben.");
        if (string.IsNullOrEmpty(password) || password.Length < 6) throw new ArgumentException("Das Lobby-Passwort muss mindestens 6 Zeichen haben.");
        if (string.IsNullOrEmpty(serverHostName)) throw new ArgumentException("Kein Vermittlungsserver eingetragen.");

        stopping = false; gotWelcome = false; ServerReachable = false; IpChanged = false;
        vip = 0; mask = 0; bcast = 0; AssignedIp = ""; PublicEndpoint = ""; LastError = "";
        lastResolveMs = -1000000; lastRegTxMs = -1000000; lastServerRxMs = 0; serverEp = null;
        cookie = new byte[8];
        lock (sync) { byNode.Clear(); byVip.Clear(); }

        serverHost = serverHostName.Trim(); serverPort = serverUdpPort;
        displayName = string.IsNullOrEmpty(myName) ? Environment.MachineName : myName;

        // Schluessel ableiten
        SetState("Schluessel werden abgeleitet ...");
        lobbyId = DeriveLobbyId(lobbyName);
        byte[] salt = Encoding.UTF8.GetBytes("PEL-P2P-V1|" + lobbyName.Trim().ToLowerInvariant());
        byte[] km;
        using (Rfc2898DeriveBytes kdf = new Rfc2898DeriveBytes(password, salt, 100000)) { km = kdf.GetBytes(64); }
        byte[] encKey = new byte[32], macKey = new byte[32];
        Buffer.BlockCopy(km, 0, encKey, 0, 32);
        Buffer.BlockCopy(km, 32, macKey, 0, 32);
        cTun = new PesP2pCrypto(encKey, macKey);
        cUdp = new PesP2pCrypto(encKey, macKey);
        cMaint = new PesP2pCrypto(encKey, macKey);

        machineKey = new byte[16];
        if (!string.IsNullOrEmpty(machineKeyHex) && machineKeyHex.Length == 32)
        {
            for (int i = 0; i < 16; i++) machineKey[i] = Convert.ToByte(machineKeyHex.Substring(i * 2, 2), 16);
        }
        byte[] rnd = new byte[8];
        using (RandomNumberGenerator rng = RandomNumberGenerator.Create())
        {
            do { rng.GetBytes(rnd); nodeId = PesBytes.ReadU64(rnd, 0); } while (nodeId == 0);
            if (string.IsNullOrEmpty(machineKeyHex)) rng.GetBytes(machineKey);
            byte[] s4 = new byte[4]; rng.GetBytes(s4); seqCounter = (int)(PesBytes.ReadU32(s4, 0) & 0x0FFFFFFF);
        }

        stopEvent = new ManualResetEvent(false);

        // UDP-Socket (ein Socket fuer Server UND alle Peers -> gleiche NAT-Zuordnung)
        try
        {
            sock = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
            try { sock.IOControl(SIO_UDP_CONNRESET, new byte[] { 0, 0, 0, 0 }, null); } catch { }
            IPAddress bindIp = BindAddress == null ? IPAddress.Any : BindAddress;
            try { sock.Bind(new IPEndPoint(bindIp, PreferredPort)); }
            catch (SocketException)
            {
                AddLog("UDP-Port " + PreferredPort + " ist belegt - nutze einen zufaelligen Port.");
                sock.Bind(new IPEndPoint(bindIp, 0));
            }
            sock.ReceiveTimeout = 1000;
            sock.ReceiveBufferSize = 1 << 20;
            sock.SendBufferSize = 1 << 20;
            localPort = ((IPEndPoint)sock.LocalEndPoint).Port;
        }
        catch
        {
            try { if (sock != null) sock.Close(); } catch { }
            throw;
        }

        running = true;
        AddLog("Lokaler UDP-Port: " + localPort);
        SetState("Verbinde mit Vermittlungsserver ...");
        udpThread = new Thread(UdpLoop); udpThread.IsBackground = true; udpThread.Name = "PES-P2P-UDP"; udpThread.Start();
        maintThread = new Thread(MaintLoop); maintThread.IsBackground = true; maintThread.Name = "PES-P2P-MAINT"; maintThread.Start();
    }

    // =========================================================================
    // STOP
    // =========================================================================
    public void Stop()
    {
        if (!running) return;
        stopping = true;
        try { stopEvent.Set(); } catch { }
        if (maintThread != null) maintThread.Join(3000);
        // Abmelden: Peers und Server sofort informieren (sonst erst nach Timeout)
        try
        {
            byte[] empty = new byte[0];
            foreach (PesP2pPeer p in SnapshotPeers())
            {
                byte[] bye = cMaint.Seal(T_BYE, nodeId, NextSeq(), empty, 0, 0);
                IPEndPoint d = p.DirectEp;
                if (p.Path == 1 && d != null) SendRaw(bye, d);
                else if (p.Path == 2) SendRelay(p.NodeId, bye);
            }
            IPEndPoint se = serverEp;
            if (se != null)
            {
                byte[] lv = new byte[3 + 16 + 8];
                lv[0] = 0x50; lv[1] = 0x53; lv[2] = S_LEAVE;
                Buffer.BlockCopy(lobbyId, 0, lv, 3, 16);
                PesBytes.WriteU64(lv, 19, nodeId);
                SendRaw(lv, se);
            }
        }
        catch { }
        try { sock.Close(); } catch { }
        if (udpThread != null) udpThread.Join(3000);
        running = false;
        ServerReachable = false;
        AssignedIp = "";
        lock (sync) { byNode.Clear(); byVip.Clear(); }
        SetState("Getrennt");
    }

    // =========================================================================
    // Ausgehend: IPv4-Pakete der lokalen Seite -> Peers
    // =========================================================================
    private void CountNoise(int key)
    {
        Interlocked.Increment(ref noiseBlocked);
        noiseStats.AddOrUpdate(key, 1, delegate (int k, long v) { return v + 1; });
    }

    // multi = Ziel ist Broadcast/Multicast. Im strengen Modus werden die Dienste auch als
    // direkte Pakete (Anfragen UND Antworten, also Quell- oder Zielport) geblockt.
    private bool IsNoise(byte[] p, bool multi)
    {
        if (!noiseEnabled) return false;
        byte proto = p[9];
        if (proto == 2) { if (noiseIgmp) { CountNoise(-2); return true; } return false; }   // IGMP
        if (proto != 17) return false;
        if (!multi && !noiseStrict) return false;
        int ihl = (p[0] & 15) * 4;
        if (p.Length < ihl + 4) return true;
        int sport = PesBytes.ReadU16(p, ihl);
        int dport = PesBytes.ReadU16(p, ihl + 2);
        HashSet<int> set = noisePorts;
        if (set.Contains(dport)) { CountNoise(dport); return true; }
        if (noiseStrict && set.Contains(sport)) { CountNoise(sport); return true; }
        return false;
    }

    public void SendIp(byte[] p)
    {
        if (!running || stopping || p == null) return;
        if (p.Length < 20 || (p[0] >> 4) != 4) return;                // nur IPv4
        uint my = vip;
        if (my == 0) return;
        uint dst = PesBytes.ReadU32(p, 16);
        bool multi = dst == 0xFFFFFFFF || dst == bcast || (dst >> 28) == 0xE;
        if (IsNoise(p, multi)) return;
        if (multi)
        {
            // Broadcast/Multicast (Server-Browser, LAN-Suche) an ALLE verbundenen Peers
            foreach (PesP2pPeer peer in SnapshotPeers()) if (peer.Path != 0) SendData(peer, p);
            return;
        }
        if ((dst & mask) != (my & mask)) return;
        PesP2pPeer target;
        lock (sync) { byVip.TryGetValue(dst, out target); }
        if (target == null || target.Path == 0) return;                // noch nicht verbunden -> verwerfen (Spiel wiederholt)
        SendData(target, p);
    }

    private void SendData(PesP2pPeer peer, byte[] ipPacket)
    {
        byte[] wire;
        // HMAC/AES-Objekte sind nicht threadsicher; SendIp kommt aus mehreren Threads
        lock (tunLock) { wire = cTun.Seal(T_DATA, nodeId, NextSeq(), ipPacket, 0, ipPacket.Length); }
        IPEndPoint d = peer.DirectEp;
        if (peer.Path == 1 && d != null) SendRaw(wire, d);
        else if (peer.Path == 2) SendRelay(peer.NodeId, wire);
        else return;
        Interlocked.Add(ref peer.TxBytes, ipPacket.Length);
    }

    private void SendRaw(byte[] data, IPEndPoint ep)
    {
        try { sock.SendTo(data, ep); } catch (ObjectDisposedException) { } catch (SocketException) { }
    }

    private void SendRelay(ulong toNode, byte[] wire)
    {
        IPEndPoint se = serverEp;
        if (se == null || !AllowRelay) return;
        byte[] r = new byte[3 + 16 + 8 + 8 + wire.Length];
        r[0] = 0x50; r[1] = 0x53; r[2] = S_RELAY;
        Buffer.BlockCopy(lobbyId, 0, r, 3, 16);
        PesBytes.WriteU64(r, 19, nodeId);
        PesBytes.WriteU64(r, 27, toNode);
        Buffer.BlockCopy(wire, 0, r, 35, wire.Length);
        SendRaw(r, se);
    }

    // =========================================================================
    // THREAD 2: UDP -> virtueller Adapter (eingehend) + Server-Nachrichten
    // =========================================================================
    private void UdpLoop()
    {
        byte[] buf = new byte[65536];
        while (!stopping)
        {
            EndPoint from = new IPEndPoint(IPAddress.Any, 0);
            int n;
            try { n = sock.ReceiveFrom(buf, ref from); }
            catch (ObjectDisposedException) { break; }
            catch (SocketException se)
            {
                if (stopping) break;
                if (se.SocketErrorCode == SocketError.TimedOut || se.SocketErrorCode == SocketError.ConnectionReset || se.SocketErrorCode == SocketError.MessageSize) continue;
                AddLog("UDP-Fehler: " + se.SocketErrorCode);
                Thread.Sleep(50);
                continue;
            }
            if (n < 3) continue;
            IPEndPoint ep = (IPEndPoint)from;
            try
            {
                if (buf[0] == 0x50 && buf[1] == 0x53)
                {
                    IPEndPoint se2 = serverEp;
                    if (se2 != null && se2.Equals(ep)) HandleServer(buf, n, ep);
                }
                else if (buf[0] == 0x50 && buf[1] == 0x45)
                {
                    HandlePeerPacket(buf, 0, n, ep, false);
                }
            }
            catch (Exception ex) { AddLog("Paketfehler: " + ex.Message); }
        }
    }

    private bool ReplayOk(PesP2pPeer p, uint seq)
    {
        lock (p)
        {
            if (!p.AnySeq) { p.AnySeq = true; p.MaxSeq = seq; p.Window = 1UL; return true; }
            if (seq > p.MaxSeq)
            {
                uint d = seq - p.MaxSeq;
                p.Window = d >= 64 ? 1UL : ((p.Window << (int)d) | 1UL);
                p.MaxSeq = seq;
                return true;
            }
            uint back = p.MaxSeq - seq;
            if (back >= 64) return false;
            ulong bit = 1UL << (int)back;
            if ((p.Window & bit) != 0) return false;
            p.Window |= bit;
            return true;
        }
    }

    private void HandlePeerPacket(byte[] buf, int off, int len, IPEndPoint ep, bool viaRelay)
    {
        if (len < PesP2pCrypto.Hdr + PesP2pCrypto.Tag) return;
        ulong sender = PesBytes.ReadU64(buf, off + 3);
        if (sender == nodeId) return;
        PesP2pPeer p;
        lock (sync) { byNode.TryGetValue(sender, out p); }
        if (p == null) return;                                          // (noch) nicht in der Lobby-Liste
        byte type; ulong node; uint seq;
        byte[] body = cUdp.Open(buf, off, len, out type, out node, out seq);
        if (body == null)
        {
            int f = ++p.AuthFails;
            if (f == 5) AddLog("Pakete von " + p.Name + " lassen sich nicht pruefen - anderes Lobby-Passwort?");
            return;
        }
        if (!ReplayOk(p, seq)) return;
        p.AuthFails = 0;
        Interlocked.Exchange(ref p.LastRxMs, Now());

        if (!viaRelay)
        {
            IPEndPoint cur = p.DirectEp;
            if (p.Path != 1 || cur == null)
            {
                p.DirectEp = ep;
                p.Path = 1;
                AddLog("Direktverbindung (Hole Punching) mit " + p.Name + " ueber " + ep);
            }
            else if (!cur.Equals(ep) && (PesBytes.IsPrivate(ep.Address) || !PesBytes.IsPrivate(cur.Address)))
            {
                // Roaming / besserer Weg (z. B. gleiches Heimnetz statt Umweg ueber die Public-IP)
                p.DirectEp = ep;
                AddLog("Weg zu " + p.Name + " gewechselt -> " + ep);
            }
        }
        else if (p.Path == 0)
        {
            p.Path = 2;
            AddLog("Verbindung mit " + p.Name + " laeuft ueber Relay (Vermittlungsserver).");
        }

        switch (type)
        {
            case T_HELLO:
                if (body.Length >= 16 && PesBytes.ReadU64(body, 0) == nodeId)
                {
                    byte[] ack = new byte[16];
                    PesBytes.WriteU64(ack, 0, sender);
                    Buffer.BlockCopy(body, 8, ack, 8, 8);
                    byte[] w = cUdp.Seal(T_HELLO_ACK, nodeId, NextSeq(), ack, 0, 16);
                    if (viaRelay) SendRelay(sender, w); else SendRaw(w, ep);
                }
                break;
            case T_HELLO_ACK:
                if (body.Length >= 16 && PesBytes.ReadU64(body, 0) == nodeId)
                {
                    long rtt = Now() - (long)PesBytes.ReadU64(body, 8);
                    if (rtt >= 0 && rtt < 10000) p.RttMs = (int)rtt;
                }
                break;
            case T_DATA:
                DeliverInbound(p, body);
                break;
            case T_BYE:
                p.Path = 0; p.DirectEp = null; p.InServerList = false;
                AddLog(p.Name + " hat die Lobby verlassen.");
                break;
        }
    }

    private void DeliverInbound(PesP2pPeer p, byte[] ip)
    {
        if (ip.Length < 20 || (ip[0] >> 4) != 4) return;
        uint src = PesBytes.ReadU32(ip, 12);
        uint dst = PesBytes.ReadU32(ip, 16);
        if (src != p.Vip) return;                                       // Anti-Spoofing: nur die eigene virtuelle IP des Peers
        uint my = vip;
        bool multiIn = dst == 0xFFFFFFFF || dst == bcast || (dst >> 28) == 0xE;
        if (!(dst == my || multiIn)) return;
        if (IsNoise(ip, multiIn)) return;                               // auch eingehend (aeltere Manager-Versionen)
        if (stopping) return;
        Action<byte[]> sink = InboundSink;
        if (sink == null) return;
        Interlocked.Add(ref p.RxBytes, ip.Length);
        sink(ip);
    }

    // =========================================================================
    // Signaling: Nachrichten vom Vermittlungsserver
    // =========================================================================
    private static IPEndPoint ReadEp(byte[] b, int o)
    {
        byte[] a = new byte[4];
        Buffer.BlockCopy(b, o, a, 0, 4);
        return new IPEndPoint(new IPAddress(a), PesBytes.ReadU16(b, o + 4));
    }

    private void HandleServer(byte[] b, int n, IPEndPoint ep)
    {
        Interlocked.Exchange(ref lastServerRxMs, Now());
        if (!ServerReachable) { ServerReachable = true; if (gotWelcome) SetState("Verbunden"); }
        byte t = b[2];
        if (t == S_WELCOME && n >= 3 + 4 + 6 + 1 + 8)
        {
            uint newVip = PesBytes.ReadU32(b, 3);
            IPEndPoint pub = ReadEp(b, 7);
            int prefix = b[13];
            byte[] ck = new byte[8];
            Buffer.BlockCopy(b, 14, ck, 0, 8);
            cookie = ck;
            if (newVip == 0)
            {
                // Erste Antwort: nur Cookie (beweist, dass wir unter dieser Adresse erreichbar
                // sind - Schutz gegen gefaelschte Absender). Sofort erneut registrieren.
                Interlocked.Exchange(ref lastRegTxMs, -1000000);
                return;
            }
            if (prefix < 8 || prefix > 30) prefix = 16;
            uint m = prefix == 0 ? 0 : 0xFFFFFFFF << (32 - prefix);
            PublicEndpoint = pub.ToString();
            if (newVip != vip || m != mask)
            {
                mask = m; bcast = (newVip & m) | ~m; vip = newVip;
                PrefixLength = prefix;
                AssignedIp = PesBytes.IpToString(newVip);
                IpChanged = true;
                AddLog("Virtuelle IP zugewiesen: " + AssignedIp + "/" + prefix + " (oeffentlich sichtbar als " + PublicEndpoint + ")");
            }
            gotWelcome = true;
            SetState("Verbunden");
        }
        else if (t == S_PEER && n >= 3 + 8 + 4 + 6 + 2)
        {
            ApplyPeer(b, n, 3, false, 0);
        }
        else if (t == S_PEER2 && n >= 8 + 8 + 4 + 6 + 2)
        {
            ApplyPeer(b, n, 8, true, PesBytes.ReadU32(b, 4));
        }
        else if (t == S_GONE && n >= 15)
        {
            uint rev = PesBytes.ReadU32(b, 3);
            ulong nid = PesBytes.ReadU64(b, 7);
            lock (sync)
            {
                gone[nid] = new KeyValuePair<uint, long>(rev, Now());
                PesP2pPeer p;
                if (byNode.TryGetValue(nid, out p) && (!p.HasRev || !Newer(p.InfoRev, rev))) p.InServerList = false;
            }
        }
        else if (t == S_SYNC && n >= 12)
        {
            uint rev = PesBytes.ReadU32(b, 3);
            int total = PesBytes.ReadU16(b, 7);
            int cnt = b[11];
            if (rev != syncRev || syncTotal != total) { syncRev = rev; syncTotal = total; syncIds.Clear(); }
            for (int i = 0; i < cnt && 12 + i * 8 + 8 <= n; i++) syncIds.Add(PesBytes.ReadU64(b, 12 + i * 8));
            if (syncIds.Count >= syncTotal)
            {
                lock (sync)
                {
                    foreach (PesP2pPeer p in byNode.Values)
                    {
                        KeyValuePair<uint, long> g;
                        bool goneLater = gone.TryGetValue(p.NodeId, out g) && Newer(g.Key, rev);
                        if (syncIds.Contains(p.NodeId)) { if (!goneLater) p.InServerList = true; }
                        else if (!p.HasRev || !Newer(p.InfoRev, rev)) p.InServerList = false;
                    }
                }
                syncIds.Clear(); syncTotal = -1;
            }
        }
        else if (t == S_MEMBERS && n >= 4)
        {
            int cnt = b[3];
            HashSet<ulong> set = new HashSet<ulong>();
            for (int i = 0; i < cnt && 4 + i * 8 + 8 <= n; i++) set.Add(PesBytes.ReadU64(b, 4 + i * 8));
            lock (sync) { foreach (PesP2pPeer p in byNode.Values) p.InServerList = set.Contains(p.NodeId); }
        }
        else if (t == S_RELAYED && n >= 3 + 8 + PesP2pCrypto.Hdr + PesP2pCrypto.Tag)
        {
            ulong from = PesBytes.ReadU64(b, 3);
            if (PesBytes.ReadU64(b, 11 + 3) != from) return;            // Absender im Paket muss zum Relay-Absender passen
            HandlePeerPacket(b, 11, n - 11, ep, true);
        }
        else if (t == S_ERROR && n >= 5)
        {
            int ml = Math.Min(b[4], n - 5);
            string msg = Encoding.UTF8.GetString(b, 5, ml);
            LastError = msg;
            SetState("Fehler: " + msg);
        }
    }

    // Mitspieler-Info aus PEER (alt) bzw. PEER2 (mit Revision) uebernehmen
    private void ApplyPeer(byte[] b, int n, int start, bool withRev, uint rev)
    {
        {
            int o = start;
            ulong nid = PesBytes.ReadU64(b, o); o += 8;
            uint pv = PesBytes.ReadU32(b, o); o += 4;
            IPEndPoint pub = ReadEp(b, o); o += 6;
            int nl = b[o++];
            if (o + nl + 1 > n) return;
            string nm = Encoding.UTF8.GetString(b, o, nl); o += nl;
            int cnt = b[o++];
            List<IPEndPoint> locals = new List<IPEndPoint>();
            for (int i = 0; i < cnt && o + 6 <= n; i++) { locals.Add(ReadEp(b, o)); o += 6; }
            if (nid == nodeId) return;
            bool isNew = false;
            lock (sync)
            {
                if (withRev)
                {
                    KeyValuePair<uint, long> g;
                    if (gone.TryGetValue(nid, out g))
                    {
                        if (!Newer(rev, g.Key)) return;             // verspaetete Info ueber jemanden, der schon weg ist
                        gone.Remove(nid);
                    }
                }
                PesP2pPeer p;
                if (byNode.TryGetValue(nid, out p) && withRev && p.HasRev && Newer(p.InfoRev, rev)) return;   // aeltere Info
                if (p == null)
                {
                    p = new PesP2pPeer();
                    p.NodeId = nid;
                    p.PunchStartMs = Now();
                    byNode[nid] = p;
                    isNew = true;
                }
                if (p.Vip != pv)
                {
                    PesP2pPeer old;
                    if (p.Vip != 0 && byVip.TryGetValue(p.Vip, out old) && old == p) byVip.Remove(p.Vip);
                    p.Vip = pv;
                    byVip[pv] = p;
                }
                p.Name = nm;
                p.PublicEp = pub;
                p.LocalEps = locals;
                p.InServerList = true;
                if (withRev) { p.HasRev = true; p.InfoRev = rev; }
            }
            if (isNew) AddLog("Mitspieler in der Lobby: " + nm + " (" + PesBytes.IpToString(pv) + ") - starte Hole Punching an " + pub);
        }
    }

    private List<IPEndPoint> GetLocalCandidates()
    {
        List<IPEndPoint> list = new List<IPEndPoint>();
        try
        {
            foreach (NetworkInterface ni in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (ni.OperationalStatus != OperationalStatus.Up) continue;
                if (ni.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
                foreach (UnicastIPAddressInformation ua in ni.GetIPProperties().UnicastAddresses)
                {
                    if (ua.Address.AddressFamily != AddressFamily.InterNetwork) continue;
                    byte[] a = ua.Address.GetAddressBytes();
                    if (a[0] == 169 && a[1] == 254) continue;
                    uint u = PesBytes.IpToUInt(ua.Address);
                    if (mask != 0 && (u & mask) == (vip & mask)) continue;
                    if (BindAddress != null && !BindAddress.Equals(IPAddress.Any) && !ua.Address.Equals(BindAddress)) continue;
                    list.Add(new IPEndPoint(ua.Address, localPort));
                    if (list.Count >= 6) return list;
                }
            }
        }
        catch { }
        return list;
    }

    private void SendRegister()
    {
        IPEndPoint se = serverEp;
        if (se == null) return;
        byte[] nm = PesBytes.Utf8Limit(displayName, 32);
        List<IPEndPoint> locals = GetLocalCandidates();
        byte[] p = new byte[4 + 16 + 8 + 16 + 1 + nm.Length + 1 + locals.Count * 6 + 8 + 9];
        p[0] = 0x50; p[1] = 0x53; p[2] = S_REGISTER; p[3] = ProtoVersion;
        Buffer.BlockCopy(lobbyId, 0, p, 4, 16);
        PesBytes.WriteU64(p, 20, nodeId);
        Buffer.BlockCopy(machineKey, 0, p, 28, 16);
        int o = 44;
        p[o++] = (byte)nm.Length;
        Buffer.BlockCopy(nm, 0, p, o, nm.Length); o += nm.Length;
        p[o++] = (byte)locals.Count;
        foreach (IPEndPoint l in locals)
        {
            Buffer.BlockCopy(l.Address.GetAddressBytes(), 0, p, o, 4);
            PesBytes.WriteU16(p, o + 4, l.Port);
            o += 6;
        }
        Buffer.BlockCopy(cookie, 0, p, o, 8);
        // Erweiterung E2: eigener Stand der Mitgliederliste (alte Server ignorieren das)
        p[o + 8] = EXT_V2;
        PesBytes.WriteU64(p, o + 9, ListDigest());
        SendRaw(p, se);
    }

    private static ulong Mix(ulong nid, uint rev)
    {
        ulong z = nid ^ ((ulong)rev * 0x9E3779B97F4A7C15UL);
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
        return z ^ (z >> 31);
    }

    private static bool Newer(uint a, uint b) { return (int)(a - b) > 0; }

    private ulong ListDigest()
    {
        ulong d = 0;
        lock (sync) { foreach (PesP2pPeer p in byNode.Values) if (p.HasRev && p.InServerList) d ^= Mix(p.NodeId, p.InfoRev); }
        return d;
    }

    private void SendHello(PesP2pPeer p, IPEndPoint ep, bool viaRelay)
    {
        byte[] body = new byte[16];
        PesBytes.WriteU64(body, 0, p.NodeId);
        PesBytes.WriteU64(body, 8, (ulong)Now());
        byte[] w = cMaint.Seal(T_HELLO, nodeId, NextSeq(), body, 0, 16);
        if (viaRelay) SendRelay(p.NodeId, w); else SendRaw(w, ep);
    }

    // =========================================================================
    // THREAD 3: Wartung - Registrierung, Hole Punching, Keepalive, Timeouts
    // =========================================================================
    private void MaintLoop()
    {
        while (!stopping)
        {
            try { MaintTick(); }
            catch (Exception ex) { AddLog("Wartungsfehler: " + ex.Message); }
            if (stopEvent.WaitOne(200)) break;
        }
    }

    private void MaintTick()
    {
        long now = Now();

        // DNS des Servers alle 5 Minuten neu aufloesen (DynDNS-tauglich)
        if (serverEp == null || now - lastResolveMs > 300000)
        {
            lastResolveMs = now;
            try
            {
                IPAddress ip = null;
                if (!IPAddress.TryParse(serverHost, out ip))
                {
                    foreach (IPAddress a in Dns.GetHostAddresses(serverHost))
                        if (a.AddressFamily == AddressFamily.InterNetwork) { ip = a; break; }
                }
                if (ip != null)
                {
                    IPEndPoint ne = new IPEndPoint(ip, serverPort);
                    if (serverEp == null || !serverEp.Equals(ne)) { serverEp = ne; AddLog("Vermittlungsserver: " + ne); }
                }
                else if (serverEp == null) SetState("Fehler: Server-Adresse nicht aufloesbar");
            }
            catch (Exception ex) { if (serverEp == null) SetState("Fehler: Server nicht aufloesbar (" + ex.Message + ")"); }
        }

        // Registrierung / Keepalive beim Server (anfangs schnell, dann alle 10 s)
        long sinceSrv = now - Interlocked.Read(ref lastServerRxMs);
        int regInterval = (gotWelcome && ServerReachable) ? 10000 : 2000;
        if (now - Interlocked.Read(ref lastRegTxMs) >= regInterval) { Interlocked.Exchange(ref lastRegTxMs, now); SendRegister(); }
        if (ServerReachable && sinceSrv > 35000)
        {
            ServerReachable = false;
            SetState(gotWelcome ? "Server nicht erreichbar - bestehende Direktverbindungen bleiben aktiv" : "Verbinde mit Vermittlungsserver ...");
        }

        if (!gotWelcome) return;                                        // ohne eigene IP kein Punching

        // Alte "ist weg"-Merker aufraeumen (nur gegen verspaetete Pakete noetig)
        if (gone.Count > 0 && now - lastGoneCleanMs > 30000)
        {
            lastGoneCleanMs = now;
            lock (sync)
            {
                List<ulong> old = new List<ulong>();
                foreach (KeyValuePair<ulong, KeyValuePair<uint, long>> kv in gone) if (now - kv.Value.Value > 120000) old.Add(kv.Key);
                foreach (ulong id in old) gone.Remove(id);
            }
        }

        int budget = PunchBudgetPerTick;
        foreach (PesP2pPeer p in SnapshotPeers())
        {
            long lastRx = Interlocked.Read(ref p.LastRxMs);

            if (p.Path != 0 && lastRx > 0 && now - lastRx > PeerTimeoutMs)
            {
                AddLog("Keine Antwort mehr von " + p.Name + " - baue Verbindung neu auf.");
                p.Path = 0; p.DirectEp = null; p.PunchStartMs = now; p.RttMs = -1; p.Punching = false;
            }

            if (p.Path == 1)
            {
                // Keepalive haelt das NAT-Loch offen (typische UDP-Timeouts: 30-120 s)
                IPEndPoint d = p.DirectEp;
                if (d != null && now - p.LastHelloMs >= 5000) { p.LastHelloMs = now; SendHello(p, d, false); }
            }
            else
            {
                // UDP Hole Punching: beide Seiten senden gleichzeitig an alle bekannten
                // Adressen des anderen -> beide NATs legen eine Zuordnung an, das erste
                // authentifizierte Paket bestaetigt den direkten Weg.
                if (!p.Punching)
                {
                    if (budget <= 0) continue;                          // kommt im naechsten Takt dran
                    p.Punching = true; p.PunchStartMs = now;
                }
                long since = now - p.PunchStartMs;
                int iv = since < 10000 ? 250 : 2000;
                if (now - p.LastHelloMs >= iv && budget > 0)
                {
                    budget--;
                    p.LastHelloMs = now;
                    if (p.PublicEp != null) SendHello(p, p.PublicEp, false);
                    List<IPEndPoint> locals = p.LocalEps;
                    if (locals != null) foreach (IPEndPoint l in locals) SendHello(p, l, false);
                }
                if (p.Path == 0 && since > PunchTimeoutMs && AllowRelay && ServerReachable)
                {
                    p.Path = 2;
                    AddLog("Kein direkter Weg zu " + p.Name + " (symmetrisches NAT?) - nutze Relay ueber den Vermittlungsserver.");
                }
                if (p.Path == 2 && now - p.LastRelayHelloMs >= 2000) { p.LastRelayHelloMs = now; SendHello(p, null, true); }
            }

            if (!p.InServerList && (lastRx == 0 || now - lastRx > 15000))
            {
                lock (sync)
                {
                    byNode.Remove(p.NodeId);
                    PesP2pPeer cur;
                    if (byVip.TryGetValue(p.Vip, out cur) && cur == p) byVip.Remove(p.Vip);
                }
                AddLog(p.Name + " ist nicht mehr in der Lobby.");
            }
        }
    }

    private List<PesP2pPeer> SnapshotPeers()
    {
        lock (sync) { return new List<PesP2pPeer>(byNode.Values); }
    }

    // Fuer die GUI (Timer im Control Center)
    public PesP2pPeerInfo[] GetPeers()
    {
        List<PesP2pPeerInfo> r = new List<PesP2pPeerInfo>();
        foreach (PesP2pPeer p in SnapshotPeers())
        {
            PesP2pPeerInfo i = new PesP2pPeerInfo();
            i.Name = p.Name;
            i.NodeId = p.NodeId; i.Vip = p.Vip; i.Path = p.Path;
            i.Ip = PesBytes.IpToString(p.Vip);
            IPEndPoint d = p.DirectEp;
            if (p.Path == 1) { i.Mode = "Direkt"; i.Endpoint = d == null ? "" : d.ToString(); }
            else if (p.Path == 2) { i.Mode = "Relay"; i.Endpoint = "ueber Server"; }
            else { i.Mode = p.AuthFails >= 5 ? "Passwort falsch?" : "Verbinde ..."; i.Endpoint = p.PublicEp == null ? "" : p.PublicEp.ToString(); }
            i.RttMs = p.Path == 0 ? -1 : p.RttMs;
            i.RxBytes = Interlocked.Read(ref p.RxBytes);
            i.TxBytes = Interlocked.Read(ref p.TxBytes);
            r.Add(i);
        }
        r.Sort(delegate (PesP2pPeerInfo a, PesP2pPeerInfo b2) { return string.Compare(a.Name, b2.Name, StringComparison.OrdinalIgnoreCase); });
        return r.ToArray();
    }
}

// ============================================================================
// Mini-Vermittler: protokollgleich zum Vermittlungsserver des Project Earth LAN Managers
// (Anmeldung mit Cookie, feste virtuelle IP je Geraet, Relay bei strengem NAT).
// Er sieht nur die Lobby-ID (Hash) - nie Passwort, Schluessel oder Inhalte.
// ============================================================================
public sealed class PesRvMember
{
    public ulong NodeId;
    public string MachineKey;
    public IPEndPoint Ep;
    public uint Vip;
    public byte[] Name = new byte[0];
    public byte[] Locals = new byte[0];
    public long LastSeen;
    public double Tokens;
    public double ByteTokens;
    public long TokenTs;
    // Protokoll-Erweiterung "E2" (ab 2026.09.29): Mitgliederliste nur bei Aenderungen
    public bool V2;
    public uint Rev;          // Lobby-Revision der letzten Aenderung dieses Mitglieds
    public int Mismatch;      // wie oft in Folge der Stand des Clients nicht passte
}

public sealed class PesRvLobby
{
    public string Id;
    public Dictionary<ulong, PesRvMember> Members = new Dictionary<ulong, PesRvMember>();
    public Dictionary<string, uint> Leases = new Dictionary<string, uint>();
    public long LastActive;
    public uint Rev;          // zaehlt jede Aenderung (Beitritt, Adresswechsel, Verlassen)
    public ulong Digest;      // XOR ueber Mix(NodeId, Rev) aller Mitglieder
}

public sealed class PesRendezvousServer
{
    private const byte S_REGISTER = 0x10, S_LEAVE = 0x11, S_RELAY = 0x12;
    private const byte S_WELCOME = 0x20, S_PEER = 0x21, S_RELAYED = 0x22, S_ERROR = 0x23, S_MEMBERS = 0x24;
    // Erweiterung E2: Clients haengen an REGISTER [0xE2][Digest u64] an (alte Server ignorieren das).
    // Sie bekommen dann nur noch Aenderungen (PEER2/GONE) statt alle 10 s die komplette Liste;
    // die komplette Liste (PEER2 + SYNC) nur, wenn ihr Stand zweimal hintereinander nicht passt.
    private const byte S_SYNC = 0x25, S_PEER2 = 0x26, S_GONE = 0x27, EXT_V2 = 0xE2;
    private const int SyncChunk = 150;
    private const uint NetBase = 0x0A4D0000;   // 10.77.0.0
    private const int Prefix = 16;

    public int Port = 9890;
    public int MaxMembers = 8;
    public int MaxLobbies = 200;
    public int RelayPps = 4000;
    // Relay-Bandbreite in Mbit/s (0 = unbegrenzt): je Mitglied und fuer alle zusammen. Schuetzt
    // den Upload des Gastgebers, wenn viele Mitspieler hinter strengem NAT/CGNAT sitzen.
    public double RelayMbitPerMember = 0;
    public double RelayMbitTotal = 0;
    private double totalTokens;
    private long totalTs;
    public long RelayDropped;
    public readonly ConcurrentQueue<string> Log = new ConcurrentQueue<string>();
    public long RelayedPackets;
    public volatile int MemberCount;
    // Nur wenn der Server beim Spieler zu Hause laeuft (Manager-Option "Lobby hosten"):
    // oeffentliche IP des Anschlusses. Mitglieder, die sich ueber Loopback/LAN anmelden
    // (der Host selbst, Gaeste im selben Heimnetz), werden dann mit dieser IP angekuendigt.
    public volatile IPAddress PublicIp;
    public IPAddress BindAddress = IPAddress.Any;
    public bool IsRunning { get { return thread != null && !stopping; } }

    private readonly Dictionary<string, PesRvLobby> lobbies = new Dictionary<string, PesRvLobby>();
    private readonly Stopwatch clock = Stopwatch.StartNew();
    private readonly byte[] cookieKey = new byte[32];
    private HMACSHA256 cookieMac;
    private Socket sock;
    private Thread thread;
    private volatile bool stopping;

    private long Now() { return clock.ElapsedMilliseconds; }
    private void AddLog(string s) { Log.Enqueue(DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + s); }

    private static uint ReadU32(byte[] b, int o) { return ((uint)b[o] << 24) | ((uint)b[o + 1] << 16) | ((uint)b[o + 2] << 8) | b[o + 3]; }
    private static void WriteU32(byte[] b, int o, uint v) { b[o] = (byte)(v >> 24); b[o + 1] = (byte)(v >> 16); b[o + 2] = (byte)(v >> 8); b[o + 3] = (byte)v; }
    private static ulong ReadU64(byte[] b, int o) { return ((ulong)ReadU32(b, o) << 32) | ReadU32(b, o + 4); }
    private static void WriteU64(byte[] b, int o, ulong v) { WriteU32(b, o, (uint)(v >> 32)); WriteU32(b, o + 4, (uint)v); }
    private static string Hex(byte[] b, int o, int n) { StringBuilder sb = new StringBuilder(n * 2); for (int i = 0; i < n; i++) sb.Append(b[o + i].ToString("x2")); return sb.ToString(); }
    private static string Ip(uint v) { return (v >> 24) + "." + ((v >> 16) & 255) + "." + ((v >> 8) & 255) + "." + (v & 255); }

    public void Start()
    {
        using (RandomNumberGenerator rng = RandomNumberGenerator.Create()) rng.GetBytes(cookieKey);
        cookieMac = new HMACSHA256(cookieKey);
        sock = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
        try { sock.IOControl(-1744830452, new byte[] { 0, 0, 0, 0 }, null); } catch { }   // nur Windows (SIO_UDP_CONNRESET)
        sock.Bind(new IPEndPoint(BindAddress == null ? IPAddress.Any : BindAddress, Port));
        sock.ReceiveTimeout = 1000;
        sock.ReceiveBufferSize = 4 << 20;
        sock.SendBufferSize = 4 << 20;
        thread = new Thread(Loop);
        thread.IsBackground = true;
        thread.Start();
        AddLog("Vermittlungsserver laeuft auf UDP-Port " + Port);
    }

    public void Stop()
    {
        stopping = true;
        try { sock.Close(); } catch { }
        if (thread != null) thread.Join(3000);
    }

    // Wird nur im Server-Thread aktualisiert (kein gleichzeitiger Zugriff auf die Listen).
    private volatile string statsText = "Lobbys: 0, Mitglieder: 0";
    public string Stats() { return statsText + ", Relay-Pakete: " + Interlocked.Read(ref RelayedPackets) + ", wegen Limit verworfen: " + Interlocked.Read(ref RelayDropped); }

    private byte[] Cookie(IPEndPoint ep)
    {
        byte[] d = new byte[6];
        Buffer.BlockCopy(ep.Address.GetAddressBytes(), 0, d, 0, 4);
        d[4] = (byte)(ep.Port >> 8); d[5] = (byte)ep.Port;
        byte[] h = cookieMac.ComputeHash(d);
        byte[] c = new byte[8];
        Buffer.BlockCopy(h, 0, c, 0, 8);
        return c;
    }

    private static bool IsPrivateOrLoopback(IPAddress a)
    {
        if (IPAddress.IsLoopback(a)) return true;
        byte[] b = a.GetAddressBytes();
        if (b.Length != 4) return false;
        return b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) || (b[0] == 192 && b[1] == 168) || (b[0] == 169 && b[1] == 254);
    }

    private IPEndPoint Advertised(IPEndPoint ep)
    {
        IPAddress pub = PublicIp;
        if (pub != null && IsPrivateOrLoopback(ep.Address)) return new IPEndPoint(pub, ep.Port);
        return ep;
    }

    private void Send(byte[] data, IPEndPoint ep) { try { sock.SendTo(data, ep); } catch { } }

    private void Loop()
    {
        byte[] buf = new byte[65536];
        long lastCleanup = 0;
        while (!stopping)
        {
            EndPoint from = new IPEndPoint(IPAddress.Any, 0);
            int n = 0;
            try { n = sock.ReceiveFrom(buf, ref from); }
            catch (ObjectDisposedException) { break; }
            catch (SocketException) { n = 0; }
            if (stopping) break;
            try
            {
                if (n >= 3 && buf[0] == 0x50 && buf[1] == 0x53)
                {
                    IPEndPoint ep = (IPEndPoint)from;
                    if (buf[2] == S_REGISTER) OnRegister(buf, n, ep);
                    else if (buf[2] == S_RELAY) OnRelay(buf, n, ep);
                    else if (buf[2] == S_LEAVE) OnLeave(buf, n, ep);
                }
            }
            catch (Exception ex) { AddLog("Paketfehler: " + ex.Message); }
            long now = Now();
            if (now - lastCleanup > 1000) { lastCleanup = now; Cleanup(now); }
        }
    }

    private void SendError(IPEndPoint ep, byte code, string msg)
    {
        byte[] m = Encoding.UTF8.GetBytes(msg);
        if (m.Length > 200) Array.Resize(ref m, 200);
        byte[] p = new byte[5 + m.Length];
        p[0] = 0x50; p[1] = 0x53; p[2] = S_ERROR; p[3] = code; p[4] = (byte)m.Length;
        Buffer.BlockCopy(m, 0, p, 5, m.Length);
        Send(p, ep);
    }

    private byte[] BuildPeer(PesRvMember m)
    {
        byte[] p = new byte[3 + 8 + 4 + 6 + 1 + m.Name.Length + 1 + m.Locals.Length];
        p[0] = 0x50; p[1] = 0x53; p[2] = S_PEER;
        WriteU64(p, 3, m.NodeId);
        WriteU32(p, 11, m.Vip);
        IPEndPoint adv = Advertised(m.Ep);
        Buffer.BlockCopy(adv.Address.GetAddressBytes(), 0, p, 15, 4);
        p[19] = (byte)(adv.Port >> 8); p[20] = (byte)adv.Port;
        int o = 21;
        p[o++] = (byte)m.Name.Length;
        Buffer.BlockCopy(m.Name, 0, p, o, m.Name.Length); o += m.Name.Length;
        p[o++] = (byte)(m.Locals.Length / 6);
        Buffer.BlockCopy(m.Locals, 0, p, o, m.Locals.Length);
        return p;
    }

    // Altes Format (nur fuer Manager vor 2026.09.29): hoechstens 255 Eintraege.
    private byte[] BuildMembers(PesRvLobby l)
    {
        int cnt = Math.Min(l.Members.Count, 255);
        byte[] p = new byte[4 + cnt * 8];
        p[0] = 0x50; p[1] = 0x53; p[2] = S_MEMBERS; p[3] = (byte)cnt;
        int i = 0;
        foreach (ulong id in l.Members.Keys) { if (i >= cnt) break; WriteU64(p, 4 + i * 8, id); i++; }
        return p;
    }

    private void Broadcast(PesRvLobby l, byte[] data, ulong except)
    {
        foreach (PesRvMember o in l.Members.Values) if (o.NodeId != except) Send(data, o.Ep);
    }

    // ---- Erweiterung E2 -------------------------------------------------------------------
    public static ulong Mix(ulong nid, uint rev)
    {
        ulong z = nid ^ ((ulong)rev * 0x9E3779B97F4A7C15UL);
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
        return z ^ (z >> 31);
    }

    // PEER2 = [P S 0x26][Art: 0 Aenderung / 1 Abgleich][Rev u32] + Inhalt wie PEER
    private byte[] BuildPeer2(PesRvMember m, byte kind)
    {
        byte[] bp = BuildPeer(m);
        byte[] p = new byte[bp.Length + 5];
        p[0] = 0x50; p[1] = 0x53; p[2] = S_PEER2; p[3] = kind;
        WriteU32(p, 4, m.Rev);
        Buffer.BlockCopy(bp, 3, p, 8, bp.Length - 3);
        return p;
    }

    // Mitglied neu/geaendert: neue Revision, allen E2-Clients (auch ihm selbst) die Aenderung,
    // alten Clients wie bisher PEER + Mitgliederliste.
    private void NotifyChange(PesRvLobby l, PesRvMember m)
    {
        if (m.Rev != 0) l.Digest ^= Mix(m.NodeId, m.Rev);
        l.Rev++; if (l.Rev == 0) l.Rev = 1;
        m.Rev = l.Rev;
        l.Digest ^= Mix(m.NodeId, m.Rev);
        byte[] p2 = BuildPeer2(m, 0);
        byte[] pm = null, mem = null;
        foreach (PesRvMember x in l.Members.Values)
        {
            if (x.V2) Send(p2, x.Ep);
            else if (x.NodeId != m.NodeId)
            {
                if (pm == null) { pm = BuildPeer(m); mem = BuildMembers(l); }
                Send(pm, x.Ep); Send(mem, x.Ep);
            }
        }
    }

    // Mitglied ist weg (abgemeldet, Timeout, neue Sitzung desselben PCs). Vorher schon entfernt.
    private void NotifyGone(PesRvLobby l, PesRvMember m)
    {
        if (m.Rev != 0) l.Digest ^= Mix(m.NodeId, m.Rev);
        l.Rev++; if (l.Rev == 0) l.Rev = 1;
        byte[] g = new byte[15];
        g[0] = 0x50; g[1] = 0x53; g[2] = S_GONE;
        WriteU32(g, 3, l.Rev);
        WriteU64(g, 7, m.NodeId);
        byte[] mem = null;
        foreach (PesRvMember x in l.Members.Values)
        {
            if (x.V2) Send(g, x.Ep);
            else { if (mem == null) mem = BuildMembers(l); Send(mem, x.Ep); }
        }
    }

    // Kompletter Abgleich: alle anderen als PEER2 (Art 1), danach die Mitgliederliste in
    // Stuecken: SYNC = [P S 0x25][Rev u32][Gesamt u16][Start u16][Anzahl u8][NodeIds...]
    private void SendSync(PesRvLobby l, PesRvMember m)
    {
        foreach (PesRvMember x in l.Members.Values) if (x.NodeId != m.NodeId) Send(BuildPeer2(x, 1), m.Ep);
        List<ulong> ids = new List<ulong>(l.Members.Keys);
        int total = ids.Count;
        for (int st = 0; st < total; st += SyncChunk)
        {
            int cnt = Math.Min(SyncChunk, total - st);
            byte[] p = new byte[12 + cnt * 8];
            p[0] = 0x50; p[1] = 0x53; p[2] = S_SYNC;
            WriteU32(p, 3, l.Rev);
            p[7] = (byte)(total >> 8); p[8] = (byte)total;
            p[9] = (byte)(st >> 8); p[10] = (byte)st;
            p[11] = (byte)cnt;
            for (int i = 0; i < cnt; i++) WriteU64(p, 12 + i * 8, ids[st + i]);
            Send(p, m.Ep);
        }
    }

    // Feste virtuelle IP je PC (MachineKey) und Lobby: deterministisch aus dem Hash,
    // bei Kollision die naechste freie. Letztes Oktett nie .0/.255 (Spiele-Kompatibilitaet).
    private uint AllocateVip(PesRvLobby l, string mk)
    {
        HashSet<uint> used = new HashSet<uint>();
        foreach (PesRvMember o in l.Members.Values) used.Add(o.Vip);
        uint lease;
        if (l.Leases.TryGetValue(mk, out lease) && !used.Contains(lease)) return lease;
        uint idx;
        // Nur aus dem MachineKey (nicht aus der Lobby) -> derselbe PC hat in JEDER Lobby und auf
        // JEDEM Server dieselbe virtuelle IP (wichtig fuer Freundesliste, Moderatoren, Bans,
        // Kanal-Ersteller - die alle ueber die IP laufen). Nur bei einer Kollision weicht sie ab.
        using (SHA256 sha = SHA256.Create()) idx = ReadU32(sha.ComputeHash(Encoding.ASCII.GetBytes("PEL-VIP|" + mk)), 0) % 65024u;
        for (int t = 0; t < 65024; t++)
        {
            uint v = NetBase | ((idx / 254u) << 8) | (idx % 254u + 1u);
            bool leasedToOther = false;
            foreach (KeyValuePair<string, uint> kv in l.Leases) if (kv.Value == v && kv.Key != mk) { leasedToOther = true; break; }
            if (!used.Contains(v) && !leasedToOther) { l.Leases[mk] = v; return v; }
            idx = (idx + 1u) % 65024u;
        }
        return 0;
    }

    private void OnRegister(byte[] b, int n, IPEndPoint ep)
    {
        if (n < 46) return;
        if (b[3] != 1) { SendError(ep, 1, "Veraltete oder neuere Programmversion - bitte aktualisieren."); return; }
        string lid = Hex(b, 4, 16);
        ulong nid = ReadU64(b, 20);
        string mk = Hex(b, 28, 16);
        int o = 44;
        int nl = b[o++];
        if (nl > 32 || o + nl + 1 > n) return;
        byte[] name = new byte[nl]; Buffer.BlockCopy(b, o, name, 0, nl); o += nl;
        int cnt = b[o++];
        if (cnt > 8 || o + cnt * 6 > n) return;
        byte[] locals = new byte[cnt * 6]; Buffer.BlockCopy(b, o, locals, 0, cnt * 6); o += cnt * 6;
        byte[] expect = Cookie(ep);
        bool cookieOk = o + 8 <= n;
        for (int i = 0; cookieOk && i < 8; i++) if (b[o + i] != expect[i]) cookieOk = false;
        bool v2 = cookieOk && o + 8 + 9 <= n && b[o + 8] == EXT_V2;
        ulong clientDigest = v2 ? ReadU64(b, o + 9) : 0;

        byte[] w = new byte[22];
        w[0] = 0x50; w[1] = 0x53; w[2] = S_WELCOME;
        IPEndPoint advSelf = Advertised(ep);
        Buffer.BlockCopy(advSelf.Address.GetAddressBytes(), 0, w, 7, 4);
        w[11] = (byte)(advSelf.Port >> 8); w[12] = (byte)advSelf.Port; w[13] = Prefix;
        Buffer.BlockCopy(expect, 0, w, 14, 8);
        if (!cookieOk)
        {
            // Erst Cookie ausliefern (virtuelle IP 0 = "noch nicht aufgenommen").
            // Gefaelschte Absender bekommen so nie Mitgliederlisten (kein Verstaerker).
            Send(w, ep);
            return;
        }

        long now = Now();
        PesRvLobby l;
        if (!lobbies.TryGetValue(lid, out l))
        {
            if (lobbies.Count >= MaxLobbies) { SendError(ep, 2, "Server ausgelastet (zu viele Lobbys)."); return; }
            l = new PesRvLobby(); l.Id = lid; lobbies[lid] = l;
            // Zufaelliger Startwert: nach einem Server-Neustart passt kein alter Client-Stand zufaellig
            byte[] rr = new byte[4];
            using (RandomNumberGenerator rng = RandomNumberGenerator.Create()) rng.GetBytes(rr);
            l.Rev = ReadU32(rr, 0);
        }
        l.LastActive = now;

        bool changed = false, isNew = false;
        PesRvMember m;
        if (!l.Members.TryGetValue(nid, out m))
        {
            // Gleicher PC mit neuer Sitzung (Absturz/Neustart)? Alte Sitzung sofort entfernen.
            List<PesRvMember> stale = new List<PesRvMember>();
            foreach (PesRvMember x in l.Members.Values) if (x.MachineKey == mk) stale.Add(x);
            foreach (PesRvMember s in stale) { l.Members.Remove(s.NodeId); NotifyGone(l, s); }
            if (l.Members.Count >= MaxMembers) { SendError(ep, 3, "Lobby ist voll (max. " + MaxMembers + ")."); return; }
            m = new PesRvMember();
            m.NodeId = nid; m.MachineKey = mk; m.Ep = ep;
            m.Vip = AllocateVip(l, mk);
            if (m.Vip == 0) { SendError(ep, 4, "Keine freie virtuelle IP."); return; }
            m.Tokens = RelayPps; m.ByteTokens = RelayMbitPerMember * 125000.0; m.TokenTs = now;
            l.Members[nid] = m;
            changed = true; isNew = true;
            AddLog("Lobby " + lid.Substring(0, 8) + ": + " + Encoding.UTF8.GetString(name) + " (" + Ip(m.Vip) + ") von " + ep + " [" + l.Members.Count + " online]");
        }
        if (!m.Ep.Equals(ep)) { m.Ep = ep; changed = true; }
        if (!Same(m.Name, name) || !Same(m.Locals, locals)) { m.Name = name; m.Locals = locals; changed = true; }
        m.LastSeen = now;
        m.V2 = v2;

        WriteU32(w, 3, m.Vip);
        Send(w, ep);
        if (changed) NotifyChange(l, m);
        if (m.V2)
        {
            // Stand des Clients = alle anderen Mitglieder mit ihrer Revision
            ulong expected = l.Digest ^ Mix(m.NodeId, m.Rev);
            if (clientDigest == expected) m.Mismatch = 0;
            // Erst beim zweiten Fehlstand in Folge abgleichen (ein einzelner kann nur eine gerade
            // unterwegs befindliche Aenderung sein). Nach einem Abgleich zaehlt der naechste sofort.
            else if (isNew || ++m.Mismatch >= 2) { m.Mismatch = 1; SendSync(l, m); }
        }
        else
        {
            // Alte Manager-Version: wie bisher komplette Liste bei jeder Anmeldung
            Send(BuildMembers(l), ep);
            foreach (PesRvMember x in l.Members.Values) if (x.NodeId != nid) Send(BuildPeer(x), ep);
        }
    }

    private static bool Same(byte[] a, byte[] b)
    {
        if (a.Length != b.Length) return false;
        for (int i = 0; i < a.Length; i++) if (a[i] != b[i]) return false;
        return true;
    }

    private void OnLeave(byte[] b, int n, IPEndPoint ep)
    {
        if (n < 27) return;
        PesRvLobby l;
        if (!lobbies.TryGetValue(Hex(b, 3, 16), out l)) return;
        ulong nid = ReadU64(b, 19);
        PesRvMember m;
        if (!l.Members.TryGetValue(nid, out m) || !m.Ep.Equals(ep)) return;
        l.Members.Remove(nid);
        AddLog("Lobby " + l.Id.Substring(0, 8) + ": - " + Encoding.UTF8.GetString(m.Name) + " (abgemeldet) [" + l.Members.Count + " online]");
        NotifyGone(l, m);
    }

    private void OnRelay(byte[] b, int n, IPEndPoint ep)
    {
        if (n < 35 + 31) return;
        PesRvLobby l;
        if (!lobbies.TryGetValue(Hex(b, 3, 16), out l)) return;
        PesRvMember src, dst;
        if (!l.Members.TryGetValue(ReadU64(b, 19), out src) || !src.Ep.Equals(ep)) return;
        if (!l.Members.TryGetValue(ReadU64(b, 27), out dst)) return;
        long now = Now();
        long el = now - src.TokenTs;
        src.TokenTs = now;
        src.Tokens = Math.Min(RelayPps, src.Tokens + el * RelayPps / 1000.0);
        if (src.Tokens < 1) return;
        int bytes = n - 35 + 11;
        if (RelayMbitPerMember > 0)
        {
            double rate = RelayMbitPerMember * 125000.0;
            src.ByteTokens = Math.Min(rate, src.ByteTokens + el * rate / 1000.0);
            if (src.ByteTokens < bytes) { Interlocked.Increment(ref RelayDropped); return; }
        }
        if (RelayMbitTotal > 0)
        {
            double rate = RelayMbitTotal * 125000.0;
            totalTokens = Math.Min(rate, totalTokens + (now - totalTs) * rate / 1000.0);
            totalTs = now;
            if (totalTokens < bytes) { Interlocked.Increment(ref RelayDropped); return; }
            totalTokens -= bytes;
        }
        if (RelayMbitPerMember > 0) src.ByteTokens -= bytes;
        src.Tokens -= 1;
        src.LastSeen = now;
        byte[] f = new byte[3 + 8 + (n - 35)];
        f[0] = 0x50; f[1] = 0x53; f[2] = S_RELAYED;
        WriteU64(f, 3, src.NodeId);
        Buffer.BlockCopy(b, 35, f, 11, n - 35);
        Send(f, dst.Ep);
        Interlocked.Increment(ref RelayedPackets);
    }

    private void Cleanup(long now)
    {
        List<string> emptyLobbies = new List<string>();
        foreach (PesRvLobby l in lobbies.Values)
        {
            List<PesRvMember> dead = new List<PesRvMember>();
            foreach (PesRvMember m in l.Members.Values) if (now - m.LastSeen > 35000) dead.Add(m);
            foreach (PesRvMember d in dead)
            {
                AddLog("Lobby " + l.Id.Substring(0, 8) + ": - " + Encoding.UTF8.GetString(d.Name) + " (Timeout)");
                l.Members.Remove(d.NodeId);
                NotifyGone(l, d);
            }
            if (l.Members.Count == 0 && now - l.LastActive > 6L * 3600 * 1000) emptyLobbies.Add(l.Id);
        }
        foreach (string id in emptyLobbies) lobbies.Remove(id);
        int total = 0;
        foreach (PesRvLobby l in lobbies.Values) total += l.Members.Count;
        statsText = "Lobbys: " + lobbies.Count + ", Mitglieder: " + total;
        MemberCount = total;
    }
}
