# ==============================================================================
# Project Earth LAN - Vermittlungsserver (Signaling / Rendezvous + Relay)
# Version: 2026.10.05
# ==============================================================================
# Minimaler UDP-Server fuer das native P2P-Netzwerk des LAN Managers.
#   - vermittelt die oeffentlichen + lokalen Adressen aller Lobby-Mitglieder
#     (Grundlage fuer UDP Hole Punching)
#   - vergibt pro Lobby eine feste virtuelle IP je PC (10.77.x.y/16)
#   - leitet verschluesselte Pakete weiter, wenn kein direkter Weg moeglich ist
#     (beide Seiten hinter symmetrischem NAT) - der Server kann sie NICHT lesen
#
# Der Server kennt weder Lobby-Namen noch Passwoerter (nur einen Hash des Namens)
# und speichert nichts auf der Festplatte.
#
# Start:
#   Windows:  powershell -ExecutionPolicy Bypass -File .\PEL-Rendezvous.ps1 [-Port 47810]
#   Linux:    pwsh ./PEL-Rendezvous.ps1 [-Port 47810]        (PowerShell 7)
# Voraussetzung: UDP-Port (Standard 47810) in Firewall/Router eingehend freigeben.
# Im Fenster-Modus (Windows) legt der Server die Windows-Firewall-Regel ab Version
# 2026.10.05 selbst an, wenn sie fehlt (ohne Administratorrechte fragt Windows einmal
# nach; beim stillen Autostart wird nicht gefragt, sondern nur im Protokoll gewarnt).
# Der Regelname ist derselbe wie im LAN Manager ("Project Earth LAN Vermittlungsserver
# (UDP <Port>)") - es entsteht keine doppelte Regel.
# Beenden: Strg+C
#
# Läuft der Server zu Hause (wechselnde öffentliche IP), kann er seinen DynDNS-Namen
# selbst aktuell halten (Prüfung alle 5 Minuten):
#   .\PEL-Rendezvous.ps1 -DuckDnsDomain meinlan -DuckDnsToken <token>
#   .\PEL-Rendezvous.ps1 -DynUpdateUrl 'https://user:pass@dynupdate.no-ip.com/nic/update?hostname=NAME&myip={IP}'
# Router mit eingebautem DynDNS (z. B. MyFRITZ!) brauchen nichts davon.
#
# Fenster (Windows): Beim Start öffnet sich eine Oberfläche mit allen Adressen, unter
# denen der Server erreichbar ist (öffentliche IP, MyFRITZ!, DuckDNS, andere DynDNS,
# LAN, dieser PC), DynDNS-Auswahl wie in Option 10, Kopier-Knöpfen für Adresse und
# Einladungscode, Router-Freigabe (UPnP) und Firewall-Knopf. Einstellungen landen in
# C:\Project-Earth-Lan\p2p\rendezvous_settings.json (Token/Passwort per DPAPI).
#   .\PEL-Rendezvous.ps1 -MyFritzName abc123xyz.myfritz.net
#   .\PEL-Rendezvous.ps1 -DynName meinlan.ddns.net -DynUpdateUrl '...{IP}'
# Infobereich: Minimieren legt das Fenster als Symbol neben die Uhr (Klick = öffnen). Mit
# -Autostart startet der Server direkt dort, ohne Fenster. Der Haken 'Mit Windows starten'
# im Fenster trägt das automatisch ein (Registry HKCU\...\Run, kein Administrator nötig).
#   .\PEL-Rendezvous.ps1 -Autostart
# Ohne Fenster (z. B. VPS oder Linux) wie bisher im Konsolenfenster:
#   .\PEL-Rendezvous.ps1 -NoGui
#
# Grosse Lobbys (bis 512 Spieler je Lobby, -MaxMembersPerLobby): Manager ab Version
# 2026.09.29 bekommen nur Aenderungen der Mitgliederliste - im Ruhezustand braucht der
# Server bei 512 Spielern nur ca. 20 kbit/s. Aeltere Manager bekommen wie frueher die
# komplette Liste bei jeder Anmeldung (viel Traffic, und sie sehen hoechstens 255 Mitspieler)
# - fuer grosse Lobbys also alle auf den aktuellen Manager bringen.
# Relay-Bandbreite begrenzen (Mbit/s, 0 = unbegrenzt), z. B. am Heimanschluss:
#   .\PEL-Rendezvous.ps1 -RelayMbitTotal 10 -RelayMbitPerMember 3
# ==============================================================================
param(
    [int]$Port = 47810,
    [string]$DuckDnsDomain = '',
    [string]$DuckDnsToken = '',
    [string]$DynUpdateUrl = '',
    [int]$MaxMembersPerLobby = 512,
    [int]$RelayPacketsPerSecond = 4000,
    [double]$RelayMbitPerMember = 0,
    [double]$RelayMbitTotal = 0,
    [string]$MyFritzName = '',
    [string]$DynName = '',
    [switch]$NoGui,
    [switch]$Autostart
)

# Nur eine Instanz (Fenster-Modus): ein zweiter Start holt das Fenster der laufenden
# Instanz aus dem Infobereich nach vorn, statt nur eine Port-Fehlermeldung zu zeigen.
$script:RvSelfPs1 = $PSCommandPath
$script:RvMutex = $null
$script:RvShowEv = $null
if (-not $NoGui -and $env:OS -eq 'Windows_NT') {
    try {
        $rvNew = $false
        $script:RvMutex = New-Object System.Threading.Mutex($true, 'Local\PEL-Rendezvous-Gui', [ref]$rvNew)
        $script:RvShowEv = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, 'Local\PEL-Rendezvous-Show')
        if (-not $rvNew) { [void]$script:RvShowEv.Set(); exit 0 }
    } catch { }
}

$rvCode = @'
using System;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Threading;

public sealed class PelRvMember
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

public sealed class PelRvLobby
{
    public string Id;
    public Dictionary<ulong, PelRvMember> Members = new Dictionary<ulong, PelRvMember>();
    public Dictionary<string, uint> Leases = new Dictionary<string, uint>();
    public long LastActive;
    public uint Rev;          // zaehlt jede Aenderung (Beitritt, Adresswechsel, Verlassen)
    public ulong Digest;      // XOR ueber Mix(NodeId, Rev) aller Mitglieder
}

public sealed class PelRendezvousServer
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

    public int Port = 47810;
    public int MaxMembers = 512;
    public int MaxLobbies = 2000;
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

    private readonly Dictionary<string, PelRvLobby> lobbies = new Dictionary<string, PelRvLobby>();
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
        sock.Bind(new IPEndPoint(IPAddress.Any, Port));
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

    private byte[] BuildPeer(PelRvMember m)
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
    private byte[] BuildMembers(PelRvLobby l)
    {
        int cnt = Math.Min(l.Members.Count, 255);
        byte[] p = new byte[4 + cnt * 8];
        p[0] = 0x50; p[1] = 0x53; p[2] = S_MEMBERS; p[3] = (byte)cnt;
        int i = 0;
        foreach (ulong id in l.Members.Keys) { if (i >= cnt) break; WriteU64(p, 4 + i * 8, id); i++; }
        return p;
    }

    private void Broadcast(PelRvLobby l, byte[] data, ulong except)
    {
        foreach (PelRvMember o in l.Members.Values) if (o.NodeId != except) Send(data, o.Ep);
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
    private byte[] BuildPeer2(PelRvMember m, byte kind)
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
    private void NotifyChange(PelRvLobby l, PelRvMember m)
    {
        if (m.Rev != 0) l.Digest ^= Mix(m.NodeId, m.Rev);
        l.Rev++; if (l.Rev == 0) l.Rev = 1;
        m.Rev = l.Rev;
        l.Digest ^= Mix(m.NodeId, m.Rev);
        byte[] p2 = BuildPeer2(m, 0);
        byte[] pm = null, mem = null;
        foreach (PelRvMember x in l.Members.Values)
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
    private void NotifyGone(PelRvLobby l, PelRvMember m)
    {
        if (m.Rev != 0) l.Digest ^= Mix(m.NodeId, m.Rev);
        l.Rev++; if (l.Rev == 0) l.Rev = 1;
        byte[] g = new byte[15];
        g[0] = 0x50; g[1] = 0x53; g[2] = S_GONE;
        WriteU32(g, 3, l.Rev);
        WriteU64(g, 7, m.NodeId);
        byte[] mem = null;
        foreach (PelRvMember x in l.Members.Values)
        {
            if (x.V2) Send(g, x.Ep);
            else { if (mem == null) mem = BuildMembers(l); Send(mem, x.Ep); }
        }
    }

    // Kompletter Abgleich: alle anderen als PEER2 (Art 1), danach die Mitgliederliste in
    // Stuecken: SYNC = [P S 0x25][Rev u32][Gesamt u16][Start u16][Anzahl u8][NodeIds...]
    private void SendSync(PelRvLobby l, PelRvMember m)
    {
        foreach (PelRvMember x in l.Members.Values) if (x.NodeId != m.NodeId) Send(BuildPeer2(x, 1), m.Ep);
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
    private uint AllocateVip(PelRvLobby l, string mk)
    {
        HashSet<uint> used = new HashSet<uint>();
        foreach (PelRvMember o in l.Members.Values) used.Add(o.Vip);
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
        if (b[3] != 1) { SendError(ep, 1, "Veraltete oder neuere Manager-Version - bitte aktualisieren."); return; }
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
        PelRvLobby l;
        if (!lobbies.TryGetValue(lid, out l))
        {
            if (lobbies.Count >= MaxLobbies) { SendError(ep, 2, "Server ausgelastet (zu viele Lobbys)."); return; }
            l = new PelRvLobby(); l.Id = lid; lobbies[lid] = l;
            // Zufaelliger Startwert: nach einem Server-Neustart passt kein alter Client-Stand zufaellig
            byte[] rr = new byte[4];
            using (RandomNumberGenerator rng = RandomNumberGenerator.Create()) rng.GetBytes(rr);
            l.Rev = ReadU32(rr, 0);
        }
        l.LastActive = now;

        bool changed = false, isNew = false;
        PelRvMember m;
        if (!l.Members.TryGetValue(nid, out m))
        {
            // Gleicher PC mit neuer Sitzung (Absturz/Neustart)? Alte Sitzung sofort entfernen.
            List<PelRvMember> stale = new List<PelRvMember>();
            foreach (PelRvMember x in l.Members.Values) if (x.MachineKey == mk) stale.Add(x);
            foreach (PelRvMember s in stale) { l.Members.Remove(s.NodeId); NotifyGone(l, s); }
            if (l.Members.Count >= MaxMembers) { SendError(ep, 3, "Lobby ist voll (max. " + MaxMembers + ")."); return; }
            m = new PelRvMember();
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
            foreach (PelRvMember x in l.Members.Values) if (x.NodeId != nid) Send(BuildPeer(x), ep);
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
        PelRvLobby l;
        if (!lobbies.TryGetValue(Hex(b, 3, 16), out l)) return;
        ulong nid = ReadU64(b, 19);
        PelRvMember m;
        if (!l.Members.TryGetValue(nid, out m) || !m.Ep.Equals(ep)) return;
        l.Members.Remove(nid);
        AddLog("Lobby " + l.Id.Substring(0, 8) + ": - " + Encoding.UTF8.GetString(m.Name) + " (abgemeldet) [" + l.Members.Count + " online]");
        NotifyGone(l, m);
    }

    private void OnRelay(byte[] b, int n, IPEndPoint ep)
    {
        if (n < 35 + 31) return;
        PelRvLobby l;
        if (!lobbies.TryGetValue(Hex(b, 3, 16), out l)) return;
        PelRvMember src, dst;
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
        foreach (PelRvLobby l in lobbies.Values)
        {
            List<PelRvMember> dead = new List<PelRvMember>();
            foreach (PelRvMember m in l.Members.Values) if (now - m.LastSeen > 35000) dead.Add(m);
            foreach (PelRvMember d in dead)
            {
                AddLog("Lobby " + l.Id.Substring(0, 8) + ": - " + Encoding.UTF8.GetString(d.Name) + " (Timeout)");
                l.Members.Remove(d.NodeId);
                NotifyGone(l, d);
            }
            if (l.Members.Count == 0 && now - l.LastActive > 6L * 3600 * 1000) emptyLobbies.Add(l.Id);
        }
        foreach (string id in emptyLobbies) lobbies.Remove(id);
        int total = 0;
        foreach (PelRvLobby l in lobbies.Values) total += l.Members.Count;
        statsText = "Lobbys: " + lobbies.Count + ", Mitglieder: " + total;
        MemberCount = total;
    }
}
'@

if (-not ('PelRendezvousServer' -as [type])) { Add-Type -TypeDefinition $rvCode -Language CSharp }

$srv = New-Object PelRendezvousServer
$srv.Port = $Port
$srv.MaxMembers = $MaxMembersPerLobby
$srv.RelayPps = $RelayPacketsPerSecond
$srv.RelayMbitPerMember = $RelayMbitPerMember
$srv.RelayMbitTotal = $RelayMbitTotal
try {
    $srv.Start()
} catch {
    $startErr = "Server konnte UDP-Port $Port nicht öffnen (läuft er schon, z. B. in Option 10 des Managers?): $($_.Exception.Message)"
    Write-Host $startErr -ForegroundColor Red
    if (-not $NoGui -and $env:OS -eq 'Windows_NT') {
        try { Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.MessageBox]::Show($startErr, 'Project Earth LAN - Vermittlungsserver', 'OK', 'Error') } catch { }
    }
    exit 1
}
Write-Host "Project Earth LAN Vermittlungsserver - UDP $Port (Strg+C zum Beenden)" -ForegroundColor Cyan
$dynWork = {
    param([int]$Provider, [string]$Name, [string]$Secret, [string]$LastIp, [bool]$Force, [int]$Port)
    $r = [ordered]@{ Ip = ''; Updated = $false; Ok = $true; Message = ''; Resolved = '' }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
    foreach ($u in @('https://api.ipify.org', 'https://ipv4.icanhazip.com')) {
        try {
            $t = ([string](Invoke-RestMethod -Uri $u -TimeoutSec 6 -UseBasicParsing)).Trim()
            if ($t -match '^\d{1,3}(\.\d{1,3}){3}$') { $r.Ip = $t; break }
        } catch { }
    }
    if (-not $r.Ip) { $r.Ok = $false; $r.Message = 'Öffentliche IP nicht ermittelbar (Internet weg?)'; return [pscustomobject]$r }
    $need = $Force -or ($r.Ip -ne $LastIp)
    $hostName = ''
    if ($Provider -eq 2) {
        $dom = (([string]$Name).Trim() -replace '(?i)\.duckdns\.org(:\d+)?$', '')
        $hostName = "$dom.duckdns.org"
        if (-not $dom -or -not $Secret) { $r.Ok = $false; $r.Message = 'DuckDNS: Subdomain und Token eintragen.' }
        elseif ($need) {
            $url = "https://www.duckdns.org/update?domains=$([uri]::EscapeDataString($dom))&token=$([uri]::EscapeDataString($Secret.Trim()))&ip=$($r.Ip)"
            try {
                $resp = ([string](Invoke-RestMethod -Uri $url -TimeoutSec 10 -UseBasicParsing)).Trim()
                if ($resp -eq 'OK') { $r.Updated = $true; $r.Message = "DuckDNS aktualisiert: $hostName -> $($r.Ip)" }
                else { $r.Ok = $false; $r.Message = "DuckDNS lehnt ab ('$resp') - Subdomain oder Token falsch?" }
            } catch { $r.Ok = $false; $r.Message = "DuckDNS nicht erreichbar: $($_.Exception.Message)" }
        } else { $r.Message = "DuckDNS aktuell ($hostName -> $($r.Ip))" }
    }
    elseif ($Provider -eq 3) {
        $hostName = (([string]$Name).Trim() -replace '^(?i)https?://', '' -replace ':\d+$', '')
        if (-not $Secret -or $Secret -notmatch '^(?i)https?://') { $r.Ok = $false; $r.Message = 'Update-URL fehlt (muss mit http:// oder https:// beginnen).' }
        elseif ($need) {
            $url = $Secret.Trim().Replace('{IP}', $r.Ip).Replace('{ip}', $r.Ip)
            $headers = @{}
            # Zugangsdaten in der URL (https://benutzer:passwort@host/...) als Basic-Auth senden
            if ($url -match '^(https?://)([^/@:]+):([^/@]+)@(.+)$') {
                $pair = [uri]::UnescapeDataString($matches[2]) + ':' + [uri]::UnescapeDataString($matches[3])
                $headers['Authorization'] = 'Basic ' + [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($pair))
                $url = $matches[1] + $matches[4]
            }
            try {
                $resp = [string](Invoke-WebRequest -Uri $url -Headers $headers -UserAgent 'ProjectEarthLAN-Manager/1.0' -TimeoutSec 10 -UseBasicParsing).Content
                $short = ($resp -replace '\s+', ' ').Trim()
                if ($short.Length -gt 60) { $short = $short.Substring(0, 60) + '...' }
                if ($resp -match '(?i)\b(badauth|nohost|notfqdn|abuse|badagent|911|error|fail|ko|unauthori[sz]ed)\b') { $r.Ok = $false; $r.Message = "Anbieter meldet Fehler: $short" }
                else { $r.Updated = $true; $r.Message = "DynDNS aktualisiert ($short)" }
            } catch { $r.Ok = $false; $r.Message = "Update-URL fehlgeschlagen: $($_.Exception.Message)" }
        } else { $r.Message = "DynDNS aktuell ($($r.Ip))" }
    }
    elseif ($Provider -eq 1) {
        $hostName = (([string]$Name).Trim() -replace '^(?i)https?://', '' -replace ':\d+$', '')
        $r.Message = 'Router aktualisiert den Namen selbst.'
    }
    else { $r.Message = "Öffentliche IP: $($r.Ip)" }
    if ($hostName) {
        try {
            $a = [System.Net.Dns]::GetHostAddresses($hostName) | Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } | Select-Object -First 1
            if ($a) { $r.Resolved = $a.ToString() }
        } catch { }
    }
    [pscustomobject]$r
}

# ==============================================================================
# Grafische Oberfläche (Windows). Mit -NoGui oder unter Linux läuft der Server wie
# bisher im Konsolenfenster weiter (unten).
# ==============================================================================
$rvUseGui = (-not $NoGui) -and ($env:OS -eq 'Windows_NT')
if ($rvUseGui) {
    try { Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction Stop } catch { $rvUseGui = $false }
}
if ($rvUseGui) {
# Die Fenster-Befehle stehen in einem Text-Block und werden erst hier geladen: PowerShell unter
# Linux würde sonst schon beim Einlesen an den Windows-Grafiktypen scheitern (auch mit -NoGui).
$rvGuiCode = @'
    [System.Windows.Forms.Application]::EnableVisualStyles()
    # Konsolenfenster ausblenden (nicht nur minimieren) - alles Wichtige steht im Fenster.
    # Hausregel: Ein Tool mit Oberfläche zeigt kein leeres Konsolenfenster.
    try {
        if (-not ('PelRvWin' -as [type])) {
            Add-Type -Namespace '' -Name 'PelRvWin' -MemberDefinition ('[System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();' +
                "`n" + '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int n);')
        }
        $cw = [PelRvWin]::GetConsoleWindow()
        if ($cw -ne [IntPtr]::Zero) { [void][PelRvWin]::ShowWindow($cw, 0) }
    } catch { }

    # ---------------- Einstellungen (Passwörter/Token per DPAPI, nur dieser Windows-Benutzer) -----
    $rvCfgDir = 'C:\Project-Earth-Lan\p2p'
    try { if (-not [System.IO.Directory]::Exists($rvCfgDir)) { [void][System.IO.Directory]::CreateDirectory($rvCfgDir) } }
    catch { $rvCfgDir = Join-Path $env:APPDATA 'ProjectEarthLan'; try { [void][System.IO.Directory]::CreateDirectory($rvCfgDir) } catch { } }
    $script:RvCfgPath = Join-Path $rvCfgDir 'rendezvous_settings.json'

    function Protect-RvText([string]$Plain) {
        if (-not $Plain) { return '' }
        try { return (ConvertTo-SecureString -String $Plain -AsPlainText -Force | ConvertFrom-SecureString) } catch { return '' }
    }
    function Unprotect-RvText([string]$Enc) {
        if (-not $Enc) { return '' }
        $bstr = [IntPtr]::Zero
        try {
            $ss = ConvertTo-SecureString -String $Enc -ErrorAction Stop
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss)
            return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        } catch { return '' }
        finally { if ($bstr -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) } }
    }

    $cfg = [ordered]@{ MyFritz = ''; DuckDomain = ''; DuckTokenEnc = ''; OtherName = ''; OtherUrlEnc = ''; Lobby = ''; PasswordEnc = ''; Upnp = $true; Provider = 0 }
    $cfgLoaded = $false
    try {
        if ([System.IO.File]::Exists($script:RvCfgPath)) {
            $j = Get-Content -LiteralPath $script:RvCfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($k in @($cfg.Keys)) { if ($j.PSObject.Properties[$k] -and $null -ne $j.$k) { $cfg[$k] = $j.$k } }
            $cfgLoaded = $true
        }
    } catch { }
    if (-not $cfgLoaded) {
        # Erster Start: DynDNS, Lobby und Passwort aus Option 10 des Managers übernehmen
        try {
            $mp = 'C:\Project-Earth-Lan\p2p\p2p_settings.json'
            if ([System.IO.File]::Exists($mp)) {
                $m = Get-Content -LiteralPath $mp -Raw -Encoding UTF8 | ConvertFrom-Json
                $mprov = [int]$m.DynProvider
                if ($mprov -eq 0 -and $m.HostAddress) { $mprov = 1; $m.DynName = [string]$m.HostAddress }
                switch ($mprov) {
                    1 { $cfg.MyFritz = [string]$m.DynName }
                    2 { $cfg.DuckDomain = [string]$m.DynName; $cfg.DuckTokenEnc = [string]$m.DynSecretEnc }
                    3 { $cfg.OtherName = [string]$m.DynName; $cfg.OtherUrlEnc = [string]$m.DynSecretEnc }
                }
                if ($mprov -gt 0) { $cfg.Provider = $mprov - 1 }
                if ($m.HostLobby) { $cfg.Lobby = [string]$m.HostLobby }
                if ($m.HostPasswordEnc) { $cfg.PasswordEnc = [string]$m.HostPasswordEnc }
            }
        } catch { }
    }
    # Startparameter haben Vorrang
    if ($MyFritzName) { $cfg.MyFritz = $MyFritzName }
    if ($DuckDnsDomain) { $cfg.DuckDomain = $DuckDnsDomain }
    if ($DuckDnsToken) { $cfg.DuckTokenEnc = Protect-RvText $DuckDnsToken }
    if ($DynUpdateUrl) { $cfg.OtherUrlEnc = Protect-RvText $DynUpdateUrl }
    if ($DynName) { $cfg.OtherName = $DynName }
    if (-not $cfg.Lobby) { $cfg.Lobby = "$($env:COMPUTERNAME)s Lobby" }
    if (-not (Unprotect-RvText ([string]$cfg.PasswordEnc))) {
        $chars = 'abcdefghkmnpqrstuvwxyzABCDEFGHKLMNPQRSTUVWXYZ23456789'
        $rb = New-Object byte[] 10
        [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($rb)
        $cfg.PasswordEnc = Protect-RvText (-join ($rb | ForEach-Object { $chars[$_ % $chars.Length] }))
    }
    $script:RvCfg = $cfg

    function Save-RvCfg {
        try { ($script:RvCfg | ConvertTo-Json) | Set-Content -LiteralPath $script:RvCfgPath -Encoding UTF8 } catch { }
    }
    Save-RvCfg

    # ---------------- Hilfsfunktionen -------------------------------------------------
    # Name säubern: kein http://, kein Pfad, kein Port, keine Leer-/Steuerzeichen
    function ConvertTo-RvHost([string]$Text) {
        $t = ([string]$Text) -replace '[\s\u200B-\u200D\uFEFF]', ''
        $t = $t -replace '^(?i)[a-z]+://', ''
        $t = $t -replace '/.*$', ''
        $t = $t -replace '^[^@]*@', ''
        $t = $t -replace ':\d*$', ''
        return $t.Trim('.').ToLowerInvariant()
    }
    function Get-RvDuckHost {
        $d = ConvertTo-RvHost $script:RvCfg.DuckDomain
        if (-not $d) { return '' }
        $d = $d -replace '(?i)\.duckdns\.org$', ''
        return "$d.duckdns.org"
    }
    function Test-RvPublicIPv4([string]$Ip) {
        $a = $null
        if (-not [System.Net.IPAddress]::TryParse($Ip, [ref]$a)) { return $false }
        $b = $a.GetAddressBytes()
        if ($b.Length -ne 4) { return $false }
        if ($b[0] -eq 10 -or $b[0] -eq 127 -or $b[0] -eq 0 -or ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or ($b[0] -eq 192 -and $b[1] -eq 168)) { return $false }
        if ($b[0] -eq 100 -and $b[1] -ge 64 -and $b[1] -le 127) { return $false }
        if ($b[0] -eq 169 -and $b[1] -eq 254) { return $false }
        return $true
    }
    function Get-RvInternetLanIp {
        $u = $null
        try { $u = New-Object System.Net.Sockets.UdpClient; $u.Connect('8.8.8.8', 53); return $u.Client.LocalEndPoint.Address.ToString() }
        catch { return '' } finally { if ($u) { $u.Close() } }
    }
    # LAN-Adressen dieses PCs (ohne Loopback, APIPA und das virtuelle P2P-Netz 10.77.x.x)
    function Get-RvLanAddresses {
        $list = @()
        try {
            foreach ($ni in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
                if ($ni.OperationalStatus -ne 'Up' -or $ni.NetworkInterfaceType -eq 'Loopback') { continue }
                foreach ($ua in $ni.GetIPProperties().UnicastAddresses) {
                    if ($ua.Address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { continue }
                    $ip = $ua.Address.ToString()
                    if ($ip -like '127.*' -or $ip -like '169.254.*' -or $ip -like '10.77.*') { continue }
                    $list += [pscustomobject]@{ Ip = $ip; Adapter = $ni.Name }
                }
            }
        } catch { }
        return $list
    }
    # Kopieren: genau "adresse:port" - ohne Leerzeichen, Zeilenumbruch oder unsichtbare Zeichen
    function Set-RvClipboard([string]$Text) {
        $t = ([string]$Text) -replace '[\s\u200B-\u200D\uFEFF]', ''
        if (-not $t) { return $false }
        try { [System.Windows.Forms.Clipboard]::SetDataObject($t, $true, 10, 100); return $true } catch { }
        try { Set-Clipboard -Value $t; return $true } catch { return $false }
    }
    function New-RvInviteCode([string]$Server, [string]$Lobby, [string]$Password) {
        $raw = [System.Text.Encoding]::UTF8.GetBytes("$Server`n$Lobby`n$Password")
        return 'PEL1:' + ([Convert]::ToBase64String($raw).TrimEnd('=').Replace('+', '-').Replace('/', '_'))
    }

    # ---------------- Hintergrund-Prüfung (Runspace, das Fenster hängt nicht) ---------------
    # Ermittelt die öffentliche IP, aktualisiert DuckDNS / andere DynDNS, löst alle Namen auf,
    # richtet auf Wunsch die Router-Freigabe (UPnP) ein und prüft die Windows-Firewall.
    $script:RvCheckScript = {
        param($In)
        $dyn = [scriptblock]::Create($In.DynWork)
        $out = [ordered]@{ PublicIp = ''; Entries = @{}; UpnpTried = $false; UpnpOk = $false; UpnpIp = ''; UpnpError = ''; FirewallOk = $null }
        foreach ($e in $In.Entries) {
            $r = $null
            try { $r = & $dyn $e.Provider $e.Name $e.Secret $In.LastIp ([bool]$e.Force) $In.Port } catch { }
            if ($r) {
                if ($r.Ip -and -not $out.PublicIp) { $out.PublicIp = $r.Ip }
                $out.Entries[$e.Key] = [pscustomobject]@{ Ok = [bool]$r.Ok; Updated = [bool]$r.Updated; Message = [string]$r.Message; Resolved = [string]$r.Resolved; Ip = [string]$r.Ip }
            }
        }
        if (-not $out.PublicIp) {
            try { $r = & $dyn 0 '' '' '' $false $In.Port; if ($r.Ip) { $out.PublicIp = $r.Ip } } catch { }
        }
        if ($In.Upnp -and $In.LanIp) {
            $out.UpnpTried = $true
            try {
                $nat = New-Object -ComObject HNetCfg.NATUPnP
                $col = $null
                for ($i = 0; $i -lt 4 -and -not $col; $i++) { $col = $nat.StaticPortMappingCollection; if (-not $col) { Start-Sleep -Milliseconds 1500 } }
                if ($col) {
                    foreach ($p in $In.UpnpPorts) {
                        try { $col.Remove($p, 'UDP') } catch { }
                        $m = $col.Add($p, 'UDP', $p, $In.LanIp, $true, "Project Earth LAN $p")
                        if ($m -and $m.ExternalIPAddress) { $out.UpnpIp = [string]$m.ExternalIPAddress }
                    }
                    $out.UpnpOk = $true
                } else { $out.UpnpError = 'Router antwortet nicht auf UPnP' }
            } catch { $out.UpnpError = $_.Exception.Message }
        }
        try {
            $rules = @(Get-NetFirewallRule -Direction Inbound -Enabled True -Action Allow -ErrorAction Stop |
                Where-Object { $_.DisplayName -like 'PEL*' -or $_.DisplayName -like 'Project Earth*' } |
                Get-NetFirewallPortFilter -ErrorAction SilentlyContinue |
                Where-Object { $_.Protocol -eq 'UDP' -and (@($_.LocalPort) -contains [string]$In.Port -or @($_.LocalPort) -contains 'Any') })
            $out.FirewallOk = ($rules.Count -gt 0)
        } catch { }
        [pscustomobject]$out
    }

    $script:Rv = [pscustomobject]@{
        Srv = $srv; Port = $Port; P2pPort = 47800
        PublicIp = ''; LanIp = ''; Results = @{}; LastCheck = [DateTime]::MinValue; NextCheck = [DateTime]::Now
        Job = $null; ForceNext = $true; LastUpdateOk = @{ Duck = [DateTime]::MinValue; Other = [DateTime]::MinValue }
        UpnpOk = $false; UpnpTried = $false; UpnpIp = ''; UpnpError = ''; UpnpPorts = @(); Cgnat = $false; FirewallOk = $null; FwAutoTried = $false
        IpChanged = ''; DynWorkText = $dynWork.ToString(); ManualMsg = $false
    }

    function Start-RvCheck([bool]$Force) {
        $rv = $script:Rv
        if ($rv.Job) { return }
        $c = $script:RvCfg
        $entries = @()
        $f = $Force -or $rv.ForceNext
        if ($c.MyFritz) { $entries += @{ Key = 'MyFritz'; Provider = 1; Name = [string]$c.MyFritz; Secret = ''; Force = $false } }
        $dTok = Unprotect-RvText ([string]$c.DuckTokenEnc)
        if ($c.DuckDomain -and $dTok) { $entries += @{ Key = 'Duck'; Provider = 2; Name = [string]$c.DuckDomain; Secret = $dTok; Force = ($f -or ([DateTime]::Now - $rv.LastUpdateOk.Duck).TotalHours -ge 6) } }
        $oUrl = Unprotect-RvText ([string]$c.OtherUrlEnc)
        if ($c.OtherName -or $oUrl) { $entries += @{ Key = 'Other'; Provider = 3; Name = [string]$c.OtherName; Secret = $oUrl; Force = ($f -or ([DateTime]::Now - $rv.LastUpdateOk.Other).TotalHours -ge 6) } }
        $rv.LanIp = Get-RvInternetLanIp
        $in = @{ DynWork = $rv.DynWorkText; Entries = $entries; LastIp = $rv.PublicIp; Port = $rv.Port
                 Upnp = ([bool]$c.Upnp -and ($Force -or -not $rv.UpnpOk)); UpnpPorts = [int[]]@($rv.Port, $rv.P2pPort); LanIp = $rv.LanIp }
        $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $rs.ApartmentState = 'STA'
        $rs.Open()
        $ps = [System.Management.Automation.PowerShell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddScript($script:RvCheckScript.ToString()).AddArgument($in)
        $rv.Job = [pscustomobject]@{ PS = $ps; Rs = $rs; Handle = $ps.BeginInvoke() }
        $rv.ForceNext = $false
        Update-RvView
    }

    # Legt die eingehende Windows-Firewall-Regel für den Server-Port an (gleicher Name wie
    # im LAN Manager). Als Administrator direkt; sonst - nur wenn $Prompt gesetzt ist - über
    # einen versteckt gestarteten, erhöhten PowerShell-Prozess (Windows fragt einmal nach).
    # Rückgabe: $true = Regel vorhanden/angelegt. Fehler landen als Text in $script:RvFwError.
    function Enable-RvFirewall([bool]$Prompt) {
        $script:RvFwError = ''
        $port = [int]$script:Rv.Port
        $rn = "Project Earth LAN Vermittlungsserver (UDP $port)"
        $isAdmin = $false
        try { $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { }
        try {
            if ($isAdmin) {
                if (-not (Get-NetFirewallRule -DisplayName $rn -ErrorAction SilentlyContinue)) {
                    New-NetFirewallRule -DisplayName $rn -Direction Inbound -Action Allow -Protocol UDP -LocalPort $port -Profile Any -ErrorAction Stop | Out-Null
                }
                return $true
            }
            if (-not $Prompt) { $script:RvFwError = 'keine Administratorrechte'; return $false }
            $cmd = "if (-not (Get-NetFirewallRule -DisplayName '$rn' -ErrorAction SilentlyContinue)) { New-NetFirewallRule -DisplayName '$rn' -Direction Inbound -Action Allow -Protocol UDP -LocalPort $port -Profile Any | Out-Null }"
            $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $p = Start-Process -FilePath $exe -ArgumentList @('-NoProfile', '-WindowStyle', 'Hidden', '-Command', $cmd) -Verb RunAs -WindowStyle Hidden -PassThru -Wait
            if ($p.ExitCode -ne 0) { throw "Befehl endete mit Code $($p.ExitCode)" }
            return $true
        } catch {
            $script:RvFwError = $_.Exception.Message
            return $false
        }
    }

    function Receive-RvCheck {
        $rv = $script:Rv
        $job = $rv.Job
        if (-not $job -or -not $job.Handle.IsCompleted) { return }
        $res = $null
        try { $res = @($job.PS.EndInvoke($job.Handle)) | Select-Object -Last 1 } catch { }
        try { $job.PS.Dispose(); $job.Rs.Close(); $job.Rs.Dispose() } catch { }
        $rv.Job = $null
        $rv.LastCheck = [DateTime]::Now
        $ok = $false
        if ($res) {
            if ($res.PublicIp) {
                if ($rv.PublicIp -and $res.PublicIp -ne $rv.PublicIp) {
                    $rv.IpChanged = "Öffentliche IP gewechselt: $($rv.PublicIp) -> $($res.PublicIp)"
                    Add-RvLog $rv.IpChanged
                }
                $rv.PublicIp = [string]$res.PublicIp
                $ok = $true
            }
            $rv.Results = @{}
            foreach ($k in @($res.Entries.Keys)) {
                $e = $res.Entries[$k]
                $rv.Results[$k] = $e
                if ($e.Updated -and $e.Ok -and $rv.LastUpdateOk.ContainsKey($k)) { $rv.LastUpdateOk[$k] = [DateTime]::Now }
                if ($e.Updated -or -not $e.Ok) { Add-RvLog ("[DynDNS] " + $e.Message) }
                if (-not $e.Ok) { $ok = $false }
            }
            if ($res.UpnpTried) {
                $rv.UpnpTried = $true
                if ($res.UpnpOk -and -not $rv.UpnpOk) { Add-RvLog "Router-Freigabe (UPnP) eingerichtet: UDP $($rv.Port) und $($rv.P2pPort) -> $($rv.LanIp)" }
                if (-not $res.UpnpOk -and $res.UpnpError) { Add-RvLog "Router-Freigabe (UPnP) nicht möglich: $($res.UpnpError)" }
                $rv.UpnpOk = [bool]$res.UpnpOk
                if ($rv.UpnpOk) { $rv.UpnpPorts = @($rv.Port, $rv.P2pPort) }
                $rv.UpnpIp = [string]$res.UpnpIp
                $rv.UpnpError = [string]$res.UpnpError
            }
            $rv.Cgnat = [bool]($rv.UpnpIp -and ((-not (Test-RvPublicIPv4 $rv.UpnpIp)) -or ($rv.PublicIp -and $rv.UpnpIp -ne $rv.PublicIp)))
            if ($null -ne $res.FirewallOk) { $rv.FirewallOk = [bool]$res.FirewallOk }
            # Fehlt die Firewall-Regel, einmal pro Lauf selbst anlegen (wie der LAN Manager
            # beim Start). Beim stillen Autostart ohne Administratorrechte wird nicht
            # nachgefragt - dann bleibt die Warnung im Fenster und der Knopf stehen.
            if ($rv.FirewallOk -eq $false -and -not $rv.FwAutoTried) {
                $rv.FwAutoTried = $true
                if (Enable-RvFirewall (-not $Autostart)) {
                    $rv.FirewallOk = $true
                    Add-RvLog "Firewall-Regel für UDP $($rv.Port) automatisch angelegt."
                } else {
                    Add-RvLog "Firewall-Regel für UDP $($rv.Port) fehlt und wurde nicht angelegt ($($script:RvFwError)) - bitte 'Firewall freigeben' klicken."
                }
            }
        }
        # Wie Option 10: Mitglieder, die sich über LAN/Loopback anmelden (z. B. der eigene Manager),
        # werden anderen mit der öffentlichen IP angekündigt -> direkte Verbindung statt Relay.
        if ($rv.PublicIp -and -not $rv.Cgnat -and (Test-RvPublicIPv4 $rv.PublicIp)) {
            try { $rv.Srv.PublicIp = [System.Net.IPAddress]::Parse($rv.PublicIp) } catch { }
        } elseif ($rv.Cgnat) { $rv.Srv.PublicIp = $null }
        $rv.NextCheck = if ($ok) { [DateTime]::Now.AddMinutes(5) } else { [DateTime]::Now.AddMinutes(1) }
        if ($rv.ManualMsg) { $rv.ManualMsg = $false; Show-RvFlash $(if ($ok) { "Geprüft: öffentliche IP $($rv.PublicIp)" } else { 'Prüfung mit Fehlern - Details im Protokoll' }) }
        Update-RvView
    }

    function Remove-RvUpnp {
        $rv = $script:Rv
        if (-not $rv.UpnpPorts -or $rv.UpnpPorts.Count -eq 0) { return }
        try {
            $col = (New-Object -ComObject HNetCfg.NATUPnP).StaticPortMappingCollection
            if ($col) { foreach ($p in $rv.UpnpPorts) { try { $col.Remove([int]$p, 'UDP') } catch { } } }
        } catch { }
        $rv.UpnpPorts = @()
    }

    # ---------------- Fenster ---------------------------------------------------------
    $cBack = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $cField = [System.Drawing.Color]::FromArgb(40, 40, 40)
    $cBtn = [System.Drawing.Color]::FromArgb(45, 45, 45)
    $cBorder = [System.Drawing.Color]::FromArgb(70, 70, 70)
    $cGreen = [System.Drawing.Color]::FromArgb(0, 135, 70)

    $f = New-Object System.Windows.Forms.Form
    $f.Text = "Project Earth LAN - Vermittlungsserver (UDP $Port)"
    $f.StartPosition = 'CenterScreen'
    $f.ClientSize = New-Object System.Drawing.Size(1010, 630)
    $f.MinimumSize = New-Object System.Drawing.Size(700, 480)
    $f.AutoScroll = $true
    $f.BackColor = $cBack
    $f.ForeColor = [System.Drawing.Color]::White
    $f.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Regular)
    $fontSmall = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Regular)
    $fontBold = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    $tip = New-Object System.Windows.Forms.ToolTip

    $mk = {
        param($parent, [string]$type, [string]$text, [int]$x, [int]$y, [int]$w, [int]$h)
        $c = New-Object ("System.Windows.Forms.$type")
        $c.Text = $text
        $c.Location = New-Object System.Drawing.Point($x, $y)
        $c.Size = New-Object System.Drawing.Size($w, $h)
        if ($type -eq 'TextBox') { $c.BackColor = $cField; $c.ForeColor = [System.Drawing.Color]::White; $c.BorderStyle = 'FixedSingle' }
        if ($type -eq 'Button') { $c.FlatStyle = 'Flat'; $c.BackColor = $cBtn; $c.FlatAppearance.BorderColor = $cBorder }
        if ($type -eq 'GroupBox') { $c.ForeColor = [System.Drawing.Color]::White }
        $parent.Controls.Add($c)
        return $c
    }

    # ===== linke Spalte ========================================================
    $gSrv = & $mk $f 'GroupBox' 'Server' 12 8 480 164
    $lRun = & $mk $gSrv 'Label' '' 12 22 456 22
    $lRun.ForeColor = [System.Drawing.Color]::LightGreen
    $lRun.Font = $fontBold
    $lStats = & $mk $gSrv 'Label' '' 12 46 456 20
    $lStats.ForeColor = [System.Drawing.Color]::LightGray
    $lPub = & $mk $gSrv 'Label' '' 12 68 456 20
    $lFw = & $mk $gSrv 'Label' '' 12 90 300 20
    $cUpnp = & $mk $gSrv 'CheckBox' 'Router-Freigabe automatisch (UPnP)' 12 112 270 26
    $cUpnp.Checked = [bool]$cfg.Upnp
    $tip.SetToolTip($cUpnp, "Gibt UDP $Port (Server) und 47800 (P2P deines Managers) im Router frei. Beim Beenden wird die Freigabe wieder entfernt.`nFritz!Box: Internet -> Freigaben -> Gerät -> 'Selbstständige Portfreigaben erlauben'.")
    $cAuto = & $mk $gSrv 'CheckBox' 'Mit Windows starten (im Infobereich)' 12 136 300 24
    $script:RvAutoBox = $cAuto
    $tip.SetToolTip($cAuto, 'Startet den Vermittlungsserver bei der Windows-Anmeldung automatisch - ohne Fenster, nur als Symbol im Infobereich neben der Uhr. Kein Administrator nötig.')
    $bFw = & $mk $gSrv 'Button' 'Firewall freigeben' 318 86 150 26
    $tip.SetToolTip($bFw, "Legt die eingehende Windows-Firewall-Regel für UDP $Port an (fragt nach Administratorrechten).")
    $bIpNow = & $mk $gSrv 'Button' 'IP jetzt aktualisieren' 318 114 150 26
    $tip.SetToolTip($bIpNow, 'Prüft sofort die öffentliche IP, aktualisiert DuckDNS / DynDNS und prüft alle Namen. Automatisch passiert das alle 5 Minuten.')

    $gDyn = & $mk $f 'GroupBox' 'Feste Adresse (DynDNS)' 12 178 480 226
    [void](& $mk $gDyn 'Label' 'Anbieter:' 12 26 90 20)
    $cProv = & $mk $gDyn 'ComboBox' '' 104 23 364 24
    $cProv.DropDownStyle = 'DropDownList'
    $cProv.FlatStyle = 'Flat'
    $cProv.BackColor = $cField
    $cProv.ForeColor = [System.Drawing.Color]::White
    [void]$cProv.Items.AddRange(@(
        'Router hält den Namen aktuell (z. B. MyFRITZ!)',
        'DuckDNS (kostenlos, Server aktualisiert selbst)',
        'Andere DynDNS (No-IP, dynv6, IPv64 ... mit {IP})'))
    $lName = & $mk $gDyn 'Label' 'Name:' 12 58 90 20
    $tName = & $mk $gDyn 'TextBox' '' 104 56 364 24
    $lSecret = & $mk $gDyn 'Label' 'Token:' 12 90 90 20
    $tSecret = & $mk $gDyn 'TextBox' '' 104 88 290 24
    $cShow = & $mk $gDyn 'CheckBox' 'zeigen' 400 88 70 24
    $bSave = & $mk $gDyn 'Button' 'Speichern && testen' 12 120 160 28
    $bSave.BackColor = $cGreen
    $bDel = & $mk $gDyn 'Button' 'Entfernen' 178 120 100 28
    $lDynRes = & $mk $gDyn 'Label' '' 284 125 186 40
    $lDynRes.Font = $fontSmall
    $lDynRes.ForeColor = [System.Drawing.Color]::LightGray
    $lHint = & $mk $gDyn 'Label' '' 12 166 456 54
    $lHint.Font = $fontSmall
    $lHint.ForeColor = [System.Drawing.Color]::DarkGray

    $gInv = & $mk $f 'GroupBox' 'Einladungscode für den Manager' 12 410 480 146
    [void](& $mk $gInv 'Label' 'Lobby-Name:' 12 26 90 20)
    $tLobby = & $mk $gInv 'TextBox' ([string]$cfg.Lobby) 104 24 364 24
    [void](& $mk $gInv 'Label' 'Passwort:' 12 58 90 20)
    $tPass = & $mk $gInv 'TextBox' (Unprotect-RvText ([string]$cfg.PasswordEnc)) 104 56 290 24
    $bNewPw = & $mk $gInv 'Button' 'Neu' 400 55 68 26
    $lInv = & $mk $gInv 'Label' "Der Code enthält die rechts markierte Adresse, Lobby-Name und Passwort. Freunde klicken im Control Center (P2P-Box) auf 'Einladung einfügen'. Du selbst trittst mit der Adresse 'Dieser PC' bei." 12 86 456 52
    $lInv.Font = $fontSmall
    $lInv.ForeColor = [System.Drawing.Color]::DarkGray

    $lWarn = & $mk $f 'Label' '' 12 562 480 58
    $lWarn.ForeColor = [System.Drawing.Color]::Orange
    $lWarn.Font = $fontSmall

    # ===== rechte Spalte =======================================================
    $gAddr = & $mk $f 'GroupBox' 'Adressen zum Verbinden (Doppelklick = kopieren)' 504 8 494 350
    $lv = New-Object System.Windows.Forms.ListView
    $lv.View = 'Details'
    $lv.FullRowSelect = $true
    $lv.MultiSelect = $false
    $lv.HideSelection = $false
    $lv.HeaderStyle = 'Nonclickable'
    $lv.BackColor = $cField
    $lv.ForeColor = [System.Drawing.Color]::White
    $lv.BorderStyle = 'FixedSingle'
    $lv.Location = New-Object System.Drawing.Point(12, 24)
    $lv.Size = New-Object System.Drawing.Size(470, 226)
    [void]$lv.Columns.Add('Art', 110)
    [void]$lv.Columns.Add('Adresse (so eintragen)', 200)
    [void]$lv.Columns.Add('Status', 156)
    $gAddr.Controls.Add($lv)
    $bCopy = & $mk $gAddr 'Button' 'Adresse kopieren' 12 258 150 34
    $bCopy.BackColor = $cGreen
    $bCopy.Font = $fontBold
    $bCopyInv = & $mk $gAddr 'Button' 'Einladung kopieren' 168 258 160 34
    $bCopyInv.Font = $fontBold
    $bCopyHost = & $mk $gAddr 'Button' 'Nur Name/IP' 334 258 148 34
    $tip.SetToolTip($bCopyHost, 'Kopiert die Adresse ohne :Port (z. B. für Router-Einstellungen oder ping).')
    $lFlash = & $mk $gAddr 'Label' '' 12 298 470 44
    $lFlash.ForeColor = [System.Drawing.Color]::LightGreen
    $lFlash.Font = $fontSmall

    $ctx = New-Object System.Windows.Forms.ContextMenuStrip
    $miCopy = $ctx.Items.Add('Adresse kopieren')
    $miInv = $ctx.Items.Add('Einladung mit dieser Adresse kopieren')
    $miHost = $ctx.Items.Add('Nur Name/IP kopieren (ohne Port)')
    $lv.ContextMenuStrip = $ctx

    $gLog = & $mk $f 'GroupBox' 'Protokoll' 504 364 494 256
    $tLog = & $mk $gLog 'TextBox' '' 12 22 470 222
    $tLog.Multiline = $true
    $tLog.ReadOnly = $true
    $tLog.ScrollBars = 'Vertical'
    $tLog.WordWrap = $false
    $tLog.Font = New-Object System.Drawing.Font('Consolas', 8.5, [System.Drawing.FontStyle]::Regular)

    $script:RvUi = [pscustomobject]@{ Form = $f; Run = $lRun; Stats = $lStats; Pub = $lPub; Fw = $lFw; Upnp = $cUpnp; BtnFw = $bFw; IpNow = $bIpNow
        Prov = $cProv; NameLbl = $lName; Name = $tName; SecretLbl = $lSecret; Secret = $tSecret; Show = $cShow; DynRes = $lDynRes; Hint = $lHint
        Lobby = $tLobby; Pass = $tPass; Warn = $lWarn; List = $lv; Flash = $lFlash; Log = $tLog; FlashUntil = [DateTime]::MinValue; FlashTimer = $null }

    function Add-RvLog([string]$Text) {
        $u = $script:RvUi
        $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $Text
        if (-not $u -or $u.Log.IsDisposed) { return }
        if ($u.Log.TextLength -gt 60000) { $u.Log.Text = $u.Log.Text.Substring($u.Log.TextLength - 40000) }
        $u.Log.AppendText($line + "`r`n")
    }
    function Show-RvFlash([string]$Text, [bool]$Bad = $false) {
        $u = $script:RvUi
        $u.Flash.ForeColor = if ($Bad) { [System.Drawing.Color]::Orange } else { [System.Drawing.Color]::LightGreen }
        $u.Flash.Text = $Text
        $u.FlashUntil = [DateTime]::Now.AddSeconds(8)
    }

    # Anbieter-Auswahl: Felder zeigen die gespeicherten Werte des gewählten Anbieters
    $cProv.Add_SelectedIndexChanged({
        $u = $script:RvUi; $c = $script:RvCfg
        $i = $u.Prov.SelectedIndex
        $c.Provider = $i
        $u.DynRes.Text = ''
        switch ($i) {
            0 { $u.NameLbl.Text = 'Name:'; $u.SecretLbl.Text = '(nicht nötig)'; $u.Name.Text = [string]$c.MyFritz; $u.Secret.Text = ''; $u.Secret.Enabled = $false; $u.Show.Enabled = $false
                $u.Hint.Text = "Die Fritz!Box hält den Namen selbst aktuell. Du findest ihn unter Internet -> MyFRITZ!-Konto (z. B. abc123xyz.myfritz.net). Einfach so einfügen - https:// und Schrägstriche werden automatisch entfernt." }
            1 { $u.NameLbl.Text = 'Subdomain:'; $u.SecretLbl.Text = 'Token:'; $u.Name.Text = [string]$c.DuckDomain; $u.Secret.Text = (Unprotect-RvText ([string]$c.DuckTokenEnc)); $u.Secret.Enabled = $true; $u.Show.Enabled = $true
                $u.Hint.Text = "Auf duckdns.org anmelden, Subdomain anlegen (z. B. 'meinlan' -> meinlan.duckdns.org) und den Token von dort kopieren. Der Server meldet deine IP alle 5 Minuten (nur bei Änderung)." }
            2 { $u.NameLbl.Text = 'Name:'; $u.SecretLbl.Text = 'Update-URL:'; $u.Name.Text = [string]$c.OtherName; $u.Secret.Text = (Unprotect-RvText ([string]$c.OtherUrlEnc)); $u.Secret.Enabled = $true; $u.Show.Enabled = $true
                $u.Hint.Text = "Name = deine Adresse beim Anbieter (z. B. meinlan.ddns.net). Update-URL mit {IP} als Platzhalter, z. B. https://benutzer:passwort@dynupdate.no-ip.com/nic/update?hostname=NAME&myip={IP}" }
        }
        $u.Secret.UseSystemPasswordChar = ($i -eq 1 -or $i -eq 2) -and -not $u.Show.Checked
        $u.Name.Enabled = $true
    })
    $cShow.Add_CheckedChanged({ $u = $script:RvUi; $u.Secret.UseSystemPasswordChar = -not $u.Show.Checked })

    $bSave.Add_Click({
        $u = $script:RvUi; $c = $script:RvCfg
        $name = ConvertTo-RvHost $u.Name.Text
        $sec = ([string]$u.Secret.Text).Trim()
        switch ($u.Prov.SelectedIndex) {
            0 { if (-not $name) { $u.DynRes.Text = 'Bitte den MyFRITZ!-Namen eintragen.'; $u.DynRes.ForeColor = [System.Drawing.Color]::Orange; return }
                $c.MyFritz = $name }
            1 { $name = $name -replace '(?i)\.duckdns\.org$', ''
                if (-not $name -or -not $sec) { $u.DynRes.Text = 'Subdomain und Token eintragen.'; $u.DynRes.ForeColor = [System.Drawing.Color]::Orange; return }
                $c.DuckDomain = $name; $c.DuckTokenEnc = Protect-RvText $sec }
            2 { if (-not $name -or $sec -notmatch '^(?i)https?://') { $u.DynRes.Text = 'Name und Update-URL (http/https) eintragen.'; $u.DynRes.ForeColor = [System.Drawing.Color]::Orange; return }
                $c.OtherName = $name; $c.OtherUrlEnc = Protect-RvText $sec }
        }
        $u.Name.Text = $name
        Save-RvCfg
        $u.DynRes.Text = 'gespeichert - wird geprüft ...'
        $u.DynRes.ForeColor = [System.Drawing.Color]::LightGray
        $script:Rv.ManualMsg = $true
        Start-RvCheck $true
        Update-RvView
    })
    $bDel.Add_Click({
        $u = $script:RvUi; $c = $script:RvCfg
        switch ($u.Prov.SelectedIndex) {
            0 { $c.MyFritz = '' }
            1 { $c.DuckDomain = ''; $c.DuckTokenEnc = '' }
            2 { $c.OtherName = ''; $c.OtherUrlEnc = '' }
        }
        foreach ($k in @('MyFritz', 'Duck', 'Other')[$u.Prov.SelectedIndex]) { $script:Rv.Results.Remove($k) }
        $u.Name.Text = ''; $u.Secret.Text = ''; $u.DynRes.Text = 'entfernt'
        Save-RvCfg
        Update-RvView
    })

    $cUpnp.Add_CheckedChanged({
        $script:RvCfg.Upnp = [bool]$script:RvUi.Upnp.Checked
        Save-RvCfg
        if ($script:RvCfg.Upnp) { Start-RvCheck $false }
        else { Remove-RvUpnp; $script:Rv.UpnpOk = $false; $script:Rv.UpnpTried = $false; Add-RvLog 'Router-Freigabe (UPnP) entfernt.'; Update-RvView }
    })
    $bIpNow.Add_Click({ $script:Rv.ManualMsg = $true; Show-RvFlash 'wird geprüft ...'; Start-RvCheck $true })
    $bFw.Add_Click({
        $port = $script:Rv.Port
        if (Enable-RvFirewall $true) {
            $script:Rv.FirewallOk = $true
            Add-RvLog "Firewall-Regel für UDP $port angelegt."
            Show-RvFlash 'Firewall-Regel angelegt.'
        } else { Show-RvFlash "Firewall-Regel nicht angelegt: $($script:RvFwError)" $true }
        Start-RvCheck $false
    })
    $bNewPw.Add_Click({
        $chars = 'abcdefghkmnpqrstuvwxyzABCDEFGHKLMNPQRSTUVWXYZ23456789'
        $rb = New-Object byte[] 10
        [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($rb)
        $script:RvUi.Pass.Text = -join ($rb | ForEach-Object { $chars[$_ % $chars.Length] })
    })
    $tLobby.Add_Leave({ $script:RvCfg.Lobby = $script:RvUi.Lobby.Text.Trim(); Save-RvCfg })
    $tPass.Add_Leave({ $script:RvCfg.PasswordEnc = Protect-RvText $script:RvUi.Pass.Text; Save-RvCfg })
    $tPass.Add_TextChanged({ $script:RvCfg.PasswordEnc = Protect-RvText $script:RvUi.Pass.Text })

    function Get-RvSelected {
        $l = $script:RvUi.List
        if ($l.SelectedItems.Count -eq 0) { if ($l.Items.Count -gt 0) { $l.Items[0].Selected = $true } else { return $null } }
        return $l.SelectedItems[0]
    }
    $doCopy = {
        param([int]$Mode)   # 0 = Adresse, 1 = Einladung, 2 = ohne Port
        $it = Get-RvSelected
        if (-not $it) { Show-RvFlash 'Noch keine Adresse vorhanden.' $true; return }
        $addr = [string]$it.Tag
        if ($Mode -eq 2) { $txt = $addr -replace ':\d+$', ''; $what = $txt }
        elseif ($Mode -eq 1) {
            $u = $script:RvUi
            $lob = $u.Lobby.Text.Trim(); $pw = $u.Pass.Text
            if ($lob.Length -lt 3) { Show-RvFlash 'Der Lobby-Name muss mindestens 3 Zeichen haben.' $true; return }
            if ($pw.Length -lt 6) { Show-RvFlash 'Das Lobby-Passwort muss mindestens 6 Zeichen haben.' $true; return }
            $script:RvCfg.Lobby = $lob; $script:RvCfg.PasswordEnc = Protect-RvText $pw; Save-RvCfg
            $txt = New-RvInviteCode $addr $lob $pw
            $what = "Einladung für $addr (Lobby '$lob')"
        }
        else { $txt = $addr; $what = $addr }
        if (Set-RvClipboard $txt) {
            $extra = if ($Mode -eq 1) { "`nFreunde: Control Center -> P2P-Box -> 'Einladung einfügen'. Der Code enthält das Passwort." }
                     elseif ($Mode -eq 0) { "`nIm Manager in der P2P-Box ins Feld 'Vermittlungsserver' einfügen." } else { '' }
            Show-RvFlash ("Kopiert: $what" + $extra)
        } else { Show-RvFlash 'Zwischenablage ist gerade belegt - bitte nochmal klicken.' $true }
    }
    $bCopy.Add_Click({ & $doCopy 0 })
    $bCopyInv.Add_Click({ & $doCopy 1 })
    $bCopyHost.Add_Click({ & $doCopy 2 })
    $miCopy.Add_Click({ & $doCopy 0 })
    $miInv.Add_Click({ & $doCopy 1 })
    $miHost.Add_Click({ & $doCopy 2 })
    $lv.Add_DoubleClick({ & $doCopy 0 })
    $lv.Add_KeyDown({ param($s, $e) if ($e.Control -and $e.KeyCode -eq 'C') { & $doCopy 0; $e.Handled = $true } })

    # ---------------- Anzeige aktualisieren -------------------------------------------
    function Update-RvView {
        $u = $script:RvUi; $rv = $script:Rv; $c = $script:RvCfg
        if (-not $u -or $u.Form.IsDisposed) { return }
        $port = $rv.Port
        $u.Run.Text = "Läuft auf UDP-Port $port"
        $u.Stats.Text = $rv.Srv.Stats()
        $chk = if ($rv.Job) { 'wird gerade geprüft ...' } elseif ($rv.LastCheck -gt [DateTime]::MinValue) { 'geprüft ' + $rv.LastCheck.ToString('HH:mm:ss') + ', nächste ' + $rv.NextCheck.ToString('HH:mm') } else { 'noch nicht geprüft' }
        $u.Pub.Text = 'Öffentliche IP: ' + $(if ($rv.PublicIp) { $rv.PublicIp } else { '-' }) + "   ($chk)"
        if ($null -eq $rv.FirewallOk) { $u.Fw.Text = 'Windows-Firewall: unbekannt'; $u.Fw.ForeColor = [System.Drawing.Color]::LightGray }
        elseif ($rv.FirewallOk) { $u.Fw.Text = "Windows-Firewall: UDP $port frei"; $u.Fw.ForeColor = [System.Drawing.Color]::LightGreen }
        else { $u.Fw.Text = "Windows-Firewall: UDP $port NICHT frei"; $u.Fw.ForeColor = [System.Drawing.Color]::Orange }

        # Ergebnis-Text des gerade gewählten Anbieters
        $key = @('MyFritz', 'Duck', 'Other')[[Math]::Max(0, $u.Prov.SelectedIndex)]
        if ($rv.Results.ContainsKey($key) -and -not $rv.Job) {
            $r = $rv.Results[$key]
            $t = [string]$r.Message
            if ($rv.PublicIp) {
                if ($r.Resolved -eq $rv.PublicIp) { $t += ' - Name passt' }
                elseif ($r.Resolved) { $t += " - Name zeigt noch auf $($r.Resolved)" }
                else { $t += ' - Name (noch) nicht auflösbar' }
            }
            $u.DynRes.Text = $t
            $u.DynRes.ForeColor = if ($r.Ok -and $r.Resolved -eq $rv.PublicIp) { [System.Drawing.Color]::LightGreen } else { [System.Drawing.Color]::Orange }
            $tip.SetToolTip($u.DynRes, $t)
        }

        # ---- Adressliste neu aufbauen (Auswahl merken) ----
        $sel = if ($u.List.SelectedItems.Count -gt 0) { [string]$u.List.SelectedItems[0].Tag } else { '' }
        $rows = New-Object System.Collections.ArrayList
        $addName = {
            param([string]$kind, [string]$hostName, [string]$key)
            if (-not $hostName) { return }
            $r = $null
            if ($rv.Results.ContainsKey($key)) { $r = $rv.Results[$key] }
            $st = 'wird geprüft ...'; $good = $null
            if ($r) {
                if (-not $r.Ok) { $st = 'Fehler beim Aktualisieren'; $good = $false }
                elseif ($rv.PublicIp -and $r.Resolved -eq $rv.PublicIp) { $st = 'OK - zeigt auf deine IP'; $good = $true }
                elseif ($r.Resolved) { $st = "zeigt auf $($r.Resolved) (alt)"; $good = $false }
                else { $st = 'nicht auflösbar'; $good = $false }
            }
            [void]$rows.Add([pscustomobject]@{ Kind = $kind; Addr = "$hostName`:$port"; Status = $st; Good = $good; Rank = $(if ($good) { 0 } else { 2 }) })
        }
        & $addName 'MyFRITZ!' (ConvertTo-RvHost $c.MyFritz) 'MyFritz'
        & $addName 'DuckDNS' (Get-RvDuckHost) 'Duck'
        & $addName 'DynDNS' (ConvertTo-RvHost $c.OtherName) 'Other'
        if ($rv.PublicIp) {
            $st = if ($rv.Cgnat) { 'kein eigener Anschluss (CGNAT)' } else { 'ändert sich bei IP-Wechsel' }
            [void]$rows.Add([pscustomobject]@{ Kind = 'Öffentliche IP'; Addr = "$($rv.PublicIp):$port"; Status = $st; Good = $(if ($rv.Cgnat) { $false } else { $null }); Rank = 1 })
        }
        $mainLan = Get-RvInternetLanIp
        foreach ($a in (Get-RvLanAddresses | Sort-Object { $_.Ip -ne $mainLan })) {
            [void]$rows.Add([pscustomobject]@{ Kind = 'LAN (' + $a.Adapter + ')'; Addr = "$($a.Ip):$port"; Status = 'nur im selben Heimnetz'; Good = $null; Rank = 3 })
        }
        [void]$rows.Add([pscustomobject]@{ Kind = 'Dieser PC'; Addr = "127.0.0.1:$port"; Status = 'für deinen eigenen Manager'; Good = $null; Rank = 4 })
        $sorted = @($rows | Sort-Object Rank)
        # Empfehlung markieren: erster passender DynDNS-Name, sonst die öffentliche IP
        $best = $sorted | Where-Object { $_.Good -eq $true } | Select-Object -First 1
        if (-not $best -and -not $rv.Cgnat) { $best = $sorted | Where-Object { $_.Kind -eq 'Öffentliche IP' } | Select-Object -First 1 }

        $u.List.BeginUpdate()
        $u.List.Items.Clear()
        foreach ($r in $sorted) {
            $it = New-Object System.Windows.Forms.ListViewItem($(if ($r -eq $best) { '★ ' + $r.Kind } else { $r.Kind }))
            [void]$it.SubItems.Add($r.Addr)
            [void]$it.SubItems.Add($(if ($r -eq $best) { $r.Status + ' - empfohlen' } else { $r.Status }))
            $it.Tag = $r.Addr
            $it.UseItemStyleForSubItems = $true
            if ($r.Good -eq $true) { $it.ForeColor = [System.Drawing.Color]::LightGreen }
            elseif ($r.Good -eq $false) { $it.ForeColor = [System.Drawing.Color]::Orange }
            [void]$u.List.Items.Add($it)
            if ($sel -and $r.Addr -eq $sel) { $it.Selected = $true }
        }
        if ($u.List.SelectedItems.Count -eq 0 -and $u.List.Items.Count -gt 0) {
            $idx = 0
            if ($best) { for ($i = 0; $i -lt $u.List.Items.Count; $i++) { if ([string]$u.List.Items[$i].Tag -eq $best.Addr) { $idx = $i; break } } }
            $u.List.Items[$idx].Selected = $true
        }
        $u.List.EndUpdate()

        # ---- Hinweise ----
        $w = @()
        if ($rv.Cgnat) { $w += "Dein Router hat keine eigene öffentliche IPv4-Adresse (Router meldet $($rv.UpnpIp), das Internet sieht $($rv.PublicIp)). Typisch für DS-Lite/CGNAT: Freunde von außen erreichen diesen Server NICHT, auch DynDNS hilft dann nicht. Im selben Heimnetz klappt es (LAN-Adresse). Für Online-Runden: Server auf einem VPS oder bei jemandem mit normalem Anschluss." }
        elseif ($rv.UpnpTried -and -not $rv.UpnpOk) { $w += "Automatische Router-Freigabe hat nicht geklappt ($($rv.UpnpError)). Bitte im Router einmalig UDP $port (und 47800) an $($rv.LanIp) weiterleiten (Fritz!Box: Internet -> Freigaben -> Portfreigaben)." }
        elseif (-not $c.Upnp) { $w += "UPnP ist aus: Für Freunde übers Internet muss UDP $port im Router an $(Get-RvInternetLanIp) weitergeleitet sein." }
        if ($rv.FirewallOk -eq $false) { $w += "Die Windows-Firewall blockt UDP $port vermutlich - 'Firewall freigeben' klicken." }
        if ($rv.IpChanged) { $w += $rv.IpChanged + ' - Namen (DynDNS) folgen automatisch, eine reine IP im Einladungscode nicht.' }
        $u.Warn.Text = ($w -join "`n`n")
    }

    # ---------------- Timer: Protokoll, Status, Prüfungen --------------------------------
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 500
    $script:RvTick = 0
    $timer.Add_Tick({
        $rv = $script:Rv; $u = $script:RvUi
        $line = $null
        while ($rv.Srv.Log.TryDequeue([ref]$line)) {
            if ($u.Log.TextLength -gt 60000) { $u.Log.Text = $u.Log.Text.Substring($u.Log.TextLength - 40000) }
            $u.Log.AppendText($line + "`r`n")
        }
        if ($rv.Job -and $rv.Job.Handle.IsCompleted) { Receive-RvCheck }
        elseif (-not $rv.Job -and [DateTime]::Now -ge $rv.NextCheck) { Start-RvCheck $false }
        if ($u.Flash.Text -and [DateTime]::Now -gt $u.FlashUntil) { $u.Flash.Text = '' }
        $script:RvTick++
        if ($script:RvTick % 4 -eq 0) { $u.Stats.Text = $rv.Srv.Stats(); try { $script:RvTray.Text = ('PEL-Server: ' + $u.Stats.Text) } catch { } }
        if ($script:RvShowEv -and $script:RvShowEv.WaitOne(0)) { Show-RvWindow }
        if ($script:RvTick % 60 -eq 0) { Update-RvView }   # LAN-Adressen etc. alle 30 s
    })

    # ---------------- Infobereich-Symbol (Tray) + Autostart --------------------------------
    $script:RvForm = $f
    $script:RvStartHidden = [bool]$Autostart
    $script:RvTipShown = $false
    $script:RvRunKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $script:RvRunName = 'PEL-Rendezvous'

    # Befehl für den Autostart: bei der EXE sie selbst, beim .ps1 powershell.exe ohne Fenster
    function Get-RvAutostartCommand {
        $exe = $null
        try { $exe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName } catch { }
        if (-not $exe) { return $null }
        if ($exe -match '(?i)\\(powershell|pwsh)(_ise)?\.exe$') {
            if ($script:RvSelfPs1 -and $script:RvSelfPs1 -like '*.ps1') {
                return ('"{0}" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "{1}" -Autostart' -f $exe, $script:RvSelfPs1)
            }
            return $null
        }
        return ('"{0}" -Autostart' -f $exe)
    }
    function Get-RvAutostart {
        try { return [bool](Get-ItemProperty -Path $script:RvRunKey -Name $script:RvRunName -ErrorAction Stop).($script:RvRunName) } catch { return $false }
    }
    function Set-RvAutostart([bool]$On) {
        try {
            if ($On) {
                $cmd = Get-RvAutostartCommand
                if (-not $cmd) { return $false }
                Set-ItemProperty -Path $script:RvRunKey -Name $script:RvRunName -Value $cmd -ErrorAction Stop
            } else {
                Remove-ItemProperty -Path $script:RvRunKey -Name $script:RvRunName -ErrorAction SilentlyContinue
            }
            return $true
        } catch { return $false }
    }

    $script:RvAutoBusy = $true
    $cAuto.Checked = (Get-RvAutostart)
    $script:RvAutoBusy = $false
    # Pfad aktuell halten (EXE verschoben oder neu gebaut)
    if ($cAuto.Checked) { [void](Set-RvAutostart $true) }
    $cAuto.Add_CheckedChanged({
        if ($script:RvAutoBusy) { return }
        $want = [bool]$script:RvAutoBox.Checked
        if (Set-RvAutostart $want) {
            if ($want) { Add-RvLog 'Autostart eingeschaltet: startet bei der Anmeldung im Infobereich.' } else { Add-RvLog 'Autostart ausgeschaltet.' }
        } else {
            $script:RvAutoBusy = $true
            $script:RvAutoBox.Checked = (Get-RvAutostart)
            $script:RvAutoBusy = $false
            Show-RvFlash 'Autostart konnte nicht geändert werden.' $true
        }
    })

    function Show-RvWindow {
        $fm = $script:RvForm
        if (-not $fm -or $fm.IsDisposed) { return }
        if ($script:RvStartHidden) {
            # erster Aufruf nach einem Start ohne Fenster: sichtbar machen und mittig setzen
            $script:RvStartHidden = $false
            $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
            $fm.Location = New-Object System.Drawing.Point(([int]($wa.X + [Math]::Max(0, ($wa.Width - $fm.Width) / 2))), ([int]($wa.Y + [Math]::Max(0, ($wa.Height - $fm.Height) / 2))))
            $fm.ShowInTaskbar = $true
            $fm.Opacity = 1
        }
        if (-not $fm.Visible) { $fm.Show() }
        if ($fm.WindowState -eq 'Minimized') { $fm.WindowState = 'Normal' }
        $fm.Activate()
        $fm.BringToFront()
    }

    $ni = New-Object System.Windows.Forms.NotifyIcon
    $script:RvTray = $ni
    try { $ni.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
    catch { $ni.Icon = [System.Drawing.SystemIcons]::Application }
    $f.Icon = $ni.Icon
    $ni.Text = 'Project Earth LAN - Vermittlungsserver'
    $nm = New-Object System.Windows.Forms.ContextMenuStrip
    $nmOpen = $nm.Items.Add('Fenster öffnen')
    $script:RvTrayAuto = $nm.Items.Add('Mit Windows starten')
    [void]$nm.Items.Add('-')
    $nmExit = $nm.Items.Add('Beenden')
    $ni.ContextMenuStrip = $nm
    $nm.Add_Opening({ $script:RvTrayAuto.Checked = [bool]$script:RvAutoBox.Checked })
    $nmOpen.Add_Click({ Show-RvWindow })
    $script:RvTrayAuto.Add_Click({ $script:RvAutoBox.Checked = -not $script:RvAutoBox.Checked })
    $nmExit.Add_Click({
        if ($script:Rv.Srv.MemberCount -gt 0) { Show-RvWindow }   # Rückfrage 'noch Mitspieler verbunden' sichtbar machen
        $script:RvForm.Close()
    })
    $ni.Add_MouseClick({ param($s, $e) if ($e.Button -eq 'Left') { Show-RvWindow } })

    # Minimieren = in den Infobereich (kein Taskleisten-Eintrag mehr)
    $f.Add_Resize({
        if ($script:RvForm.WindowState -eq 'Minimized') {
            $script:RvForm.Hide()
            if (-not $script:RvTipShown) {
                $script:RvTipShown = $true
                try { $script:RvTray.ShowBalloonTip(2000, 'Project Earth LAN', 'Der Vermittlungsserver läuft im Infobereich weiter.', 'Info') } catch { }
            }
        }
    })
    # Start ohne Fenster (Autostart): unsichtbar und außerhalb des Bildschirms öffnen, dann sofort verstecken
    if ($script:RvStartHidden) {
        $f.ShowInTaskbar = $false
        $f.Opacity = 0
        $f.StartPosition = 'Manual'
        $f.Location = New-Object System.Drawing.Point(-32000, -32000)
    }
    $ni.Visible = $true

    $f.Add_FormClosing({
        param($s, $e)
        if ($script:Rv.Srv.MemberCount -gt 0) {
            $a = [System.Windows.Forms.MessageBox]::Show($script:RvUi.Form, "Es sind noch $($script:Rv.Srv.MemberCount) Mitspieler verbunden. Server wirklich beenden?`n`nNeue Spieler können dann nicht mehr beitreten.", 'Vermittlungsserver beenden', 'YesNo', 'Question')
            if ($a -ne 'Yes') { $e.Cancel = $true; return }
        }
    })
    $f.Add_Shown({
        $script:RvUi.Prov.SelectedIndex = [Math]::Max(0, [Math]::Min(2, [int]$script:RvCfg.Provider))
        Add-RvLog "Einstellungen: $($script:RvCfgPath)"
        Update-RvView
        Start-RvCheck $true
        $timer.Start()
        if ($script:RvStartHidden) { $script:RvForm.Hide() }
    })

    try {
        [System.Windows.Forms.Application]::Run($f)
    } finally {
        $timer.Stop()
        try { $script:RvTray.Visible = $false; $script:RvTray.Dispose() } catch { }
        Save-RvCfg
        Remove-RvUpnp
        $srv.Stop()
    }
    exit 0
'@
. ([scriptblock]::Create($rvGuiCode))
}

$dynProvider = if ($DuckDnsDomain -and $DuckDnsToken) { 2 } elseif ($DynUpdateUrl) { 3 } else { 0 }
$dynName = if ($dynProvider -eq 2) { $DuckDnsDomain } else { '' }
$dynSecret = if ($dynProvider -eq 2) { $DuckDnsToken } else { $DynUpdateUrl }
$dynLastIp = ''
$dynLastOk = [DateTime]::MinValue
$dynNext = [DateTime]::Now
if ($dynProvider -gt 0) { Write-Host "DynDNS aktiv - öffentliche IP wird alle 5 Minuten geprüft." -ForegroundColor Cyan }
$line = $null
$lastStats = [DateTime]::Now
try {
    while ($true) {
        while ($srv.Log.TryDequeue([ref]$line)) { Write-Host $line }
        if ($dynProvider -gt 0 -and [DateTime]::Now -ge $dynNext) {
            $force = ([DateTime]::Now - $dynLastOk).TotalHours -ge 6
            try { $r = & $dynWork $dynProvider $dynName $dynSecret $dynLastIp $force $Port } catch { $r = $null }
            if ($r -and $r.Ip) {
                if ($dynLastIp -and $r.Ip -ne $dynLastIp) { Write-Host "Öffentliche IP gewechselt: $dynLastIp -> $($r.Ip)" -ForegroundColor Yellow }
                $dynLastIp = $r.Ip
            }
            if ($r -and ($r.Updated -or -not $r.Ok)) { Write-Host ("[DynDNS] " + $r.Message) -ForegroundColor $(if ($r.Ok) { 'Green' } else { 'Red' }) }
            if ($r -and $r.Updated -and $r.Ok) { $dynLastOk = [DateTime]::Now }
            $dynNext = if ($r -and $r.Ok) { [DateTime]::Now.AddMinutes(5) } else { [DateTime]::Now.AddMinutes(1) }
        }
        if (([DateTime]::Now - $lastStats).TotalMinutes -ge 5) { Write-Host ("[Status] " + $srv.Stats()) -ForegroundColor DarkGray; $lastStats = [DateTime]::Now }
        Start-Sleep -Milliseconds 500
    }
} finally {
    $srv.Stop()
    Write-Host "Vermittlungsserver beendet." -ForegroundColor Yellow
}
