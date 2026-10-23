<#
  Build-OneNoteViewer.ps1
  Reads OneNote section files (.one) without OneNote and builds a browsable,
  searchable viewer with every page: Desktop\OneNoteViewer\index.html

  Usage (from the folder that holds your notebook folders):
      powershell -ExecutionPolicy Bypass -File .\Build-OneNoteViewer.ps1
  or with explicit folders:
      .\Build-OneNoteViewer.ps1 -Root "C:\Users\me\Documents\Note" -OutDir "C:\Users\me\Desktop\OneNoteViewer"

  Your .one files are only read, never changed. Nothing is sent anywhere.
#>
param(
    [string]$Root = $(if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }),
    [string]$OutDir = "$env:USERPROFILE\Desktop\OneNoteViewer",
    [switch]$IncludeDeleted,
    [switch]$NoOpen
)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\', '/')

# ---------------------------------------------------------------- reader (C#)
$cs = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

// Reads OneNote desktop section files (.one, MS-ONESTORE revision store) and
// builds pages for a browser viewer. Written for C# 5 / .NET Framework 4.x so it
// compiles inside Windows PowerShell 5.1 with Add-Type.
public static class OneNoteReader
{
    // ---------------------------------------------------------------- JSON out
    static StringBuilder json;
    static int pageCounter;
    static bool firstNotebook, firstSection, inNotebook;
    static string currentNotebook;
    static string assetsDir;
    static Dictionary<string, string> assetByHash;
    public static int AssetCount, PageCount;

    public static void Begin(string outDir)
    {
        json = new StringBuilder();
        json.Append("{\"notebooks\":[");
        pageCounter = 0; AssetCount = 0; PageCount = 0;
        firstNotebook = true; inNotebook = false; currentNotebook = null;
        assetsDir = Path.Combine(outDir, "assets");
        Directory.CreateDirectory(assetsDir);
        assetByHash = new Dictionary<string, string>();
    }

    public static string Finish(string generated)
    {
        if (inNotebook) json.Append("]}");
        json.Append("],\"generated\":"); Str(json, generated); json.Append("}");
        return json.ToString().Replace("</", "<\\/");
    }

    // Reads one section and appends it to the output. Returns a status line.
    public static string AddSection(string notebook, string groups, string sectionName, string path)
    {
        if (notebook != currentNotebook)
        {
            if (inNotebook) json.Append("]}");
            if (!firstNotebook) json.Append(",");
            firstNotebook = false; inNotebook = true; currentNotebook = notebook; firstSection = true;
            json.Append("{\"name\":"); Str(json, notebook); json.Append(",\"sections\":[");
        }
        List<Page> pages = null;
        string mode = "full", err = null, note = null;
        try
        {
            Section sec = new Section(path);
            sec.Load();
            pages = new PageBuilder(sec).Pages();
            if (pages.Count == 0) { err = "no pages found"; pages = null; }
        }
        catch (Exception e) { err = e.GetType().Name + ": " + e.Message; pages = null; }
        if (pages == null)
        {
            mode = "recovered";
            try { pages = RawText(path); } catch (Exception) { pages = new List<Page>(); mode = "failed"; }
            note = IsCloudFormat(path)
                ? "This section is in the OneDrive/SharePoint download format, which this tool can only partly read. Showing the text it could recover."
                : "This section's format couldn't be fully read. Showing the text that could be recovered.";
        }
        if (!firstSection) json.Append(",");
        firstSection = false;
        json.Append("{\"name\":"); Str(json, sectionName);
        json.Append(",\"groups\":[");
        bool fg = true;
        foreach (string g in (groups ?? "").Split(new char[] { '\\', '/' }, StringSplitOptions.RemoveEmptyEntries))
        { if (!fg) json.Append(","); fg = false; Str(json, g); }
        json.Append("],\"file\":"); Str(json, path);
        json.Append(",\"mode\":"); Str(json, mode);
        json.Append(",\"note\":"); if (note == null) json.Append("null"); else Str(json, note);
        json.Append(",\"pages\":[");
        bool fp = true;
        foreach (Page p in pages)
        {
            if (!fp) json.Append(","); fp = false;
            pageCounter++; PageCount++;
            json.Append("{\"id\":").Append(pageCounter);
            json.Append(",\"title\":"); Str(json, p.Title);
            json.Append(",\"level\":").Append(p.Level);
            json.Append(",\"created\":"); if (p.Created.HasValue) Str(json, p.Created.Value.ToString("yyyy-MM-dd HH:mm")); else json.Append("null");
            json.Append(",\"modified\":"); if (p.Modified.HasValue) Str(json, p.Modified.Value.ToString("yyyy-MM-dd HH:mm")); else json.Append("null");
            json.Append(",\"orphan\":").Append(p.Orphan ? "true" : "false");
            json.Append(",\"blocks\":"); Blocks(json, p.Blocks);
            json.Append(",\"text\":"); Str(json, Plain(p.Blocks));
            json.Append("}");
        }
        json.Append("]}");
        string status = mode == "full" ? "ok" : (mode == "recovered" ? "text only" : "FAILED");
        return status + "|" + pages.Count + "|" + (mode != "full" && err != null ? err : "");
    }

    static void Str(StringBuilder sb, string s)
    {
        sb.Append('"');
        if (s != null)
        {
            foreach (char c in s)
            {
                switch (c)
                {
                    case '"': sb.Append("\\\""); break;
                    case '\\': sb.Append("\\\\"); break;
                    case '\n': sb.Append("\\n"); break;
                    case '\r': break;
                    case '\t': sb.Append("\\t"); break;
                    default:
                        if (c < 0x20 || c == '\u2028' || c == '\u2029') sb.Append("\\u").Append(((int)c).ToString("x4"));
                        else sb.Append(c);
                        break;
                }
            }
        }
        sb.Append('"');
    }

    static void Blocks(StringBuilder sb, List<Block> blocks)
    {
        sb.Append('[');
        bool first = true;
        foreach (Block b in blocks)
        {
            if (!first) sb.Append(','); first = false;
            sb.Append("{\"type\":"); Str(sb, b.Type);
            sb.Append(",\"depth\":").Append(b.Depth);
            if (b.Type == "p")
            {
                sb.Append(",\"style\":"); if (b.Style == null) sb.Append("null"); else Str(sb, b.Style);
                if (b.List != null) { sb.Append(",\"list\":"); Str(sb, b.List); }
                if (b.Check != null) { sb.Append(",\"check\":"); Str(sb, b.Check); }
                sb.Append(",\"runs\":[");
                bool fr = true;
                foreach (Run r in b.Runs)
                {
                    if (!fr) sb.Append(','); fr = false;
                    sb.Append("{\"t\":"); Str(sb, r.T);
                    if (r.B) sb.Append(",\"b\":true");
                    if (r.I) sb.Append(",\"i\":true");
                    if (r.U) sb.Append(",\"u\":true");
                    if (r.S) sb.Append(",\"s\":true");
                    if (r.Href != null) { sb.Append(",\"href\":"); Str(sb, r.Href); }
                    sb.Append('}');
                }
                sb.Append(']');
            }
            else if (b.Type == "table")
            {
                sb.Append(",\"rows\":[");
                bool frw = true;
                foreach (List<List<Block>> row in b.Rows)
                {
                    if (!frw) sb.Append(','); frw = false;
                    sb.Append('[');
                    bool fc = true;
                    foreach (List<Block> cell in row) { if (!fc) sb.Append(','); fc = false; Blocks(sb, cell); }
                    sb.Append(']');
                }
                sb.Append(']');
            }
            else if (b.Type == "img")
            {
                sb.Append(",\"src\":"); if (b.Src == null) sb.Append("null"); else Str(sb, b.Src);
                sb.Append(",\"name\":"); Str(sb, b.Name);
                sb.Append(",\"alt\":"); Str(sb, b.Alt ?? "");
                sb.Append(",\"ocr\":"); Str(sb, b.Ocr ?? "");
            }
            else if (b.Type == "file")
            {
                sb.Append(",\"href\":"); if (b.Src == null) sb.Append("null"); else Str(sb, b.Src);
                sb.Append(",\"name\":"); Str(sb, b.Name);
            }
            sb.Append('}');
        }
        sb.Append(']');
    }

    internal static string Plain(List<Block> blocks)
    {
        StringBuilder sb = new StringBuilder();
        foreach (Block b in blocks)
        {
            string t = null;
            if (b.Type == "p") { StringBuilder r = new StringBuilder(); foreach (Run x in b.Runs) r.Append(x.T); t = r.ToString(); }
            else if (b.Type == "table")
            {
                StringBuilder r = new StringBuilder();
                foreach (List<List<Block>> row in b.Rows) foreach (List<Block> cell in row) { string c = Plain(cell); if (c.Length > 0) r.Append(c).Append('\n'); }
                t = r.ToString().TrimEnd('\n');
            }
            else if (b.Type == "img") t = ((b.Alt ?? "") + "\n" + (b.Ocr ?? "")).Trim();
            else if (b.Type == "file") t = b.Name;
            if (!string.IsNullOrEmpty(t)) { if (sb.Length > 0) sb.Append('\n'); sb.Append(t); }
        }
        return sb.ToString();
    }

    internal static string EmitAsset(byte[] data, string name, string ext)
    {
        string hash;
        using (SHA1 sha = SHA1.Create())
        {
            byte[] h = sha.ComputeHash(data);
            StringBuilder hs = new StringBuilder();
            for (int i = 0; i < 8; i++) hs.Append(h[i].ToString("x2"));
            hash = hs.ToString();
        }
        string url;
        if (assetByHash.TryGetValue(hash, out url)) return url;
        string bn = Path.GetFileNameWithoutExtension(name ?? "");
        string e = Path.GetExtension(name ?? "");
        if (string.IsNullOrEmpty(e)) e = ext ?? "";
        e = e.ToLowerInvariant();
        if (e.Length > 0 && e[0] != '.') e = "." + e;
        bn = Regex.Replace(bn, "[<>:\"/\\\\|?*\\x00-\\x1f]", "_").Trim(' ', '.');
        if (bn.Length > 60) bn = bn.Substring(0, 60);
        if (bn.Length == 0) bn = "file";
        if (e.Length > 10) e = "";
        string fname = hash + "_" + bn + e;
        File.WriteAllBytes(Path.Combine(assetsDir, fname), data);
        url = "assets/" + Uri.EscapeDataString(fname);
        assetByHash[hash] = url;
        AssetCount++;
        return url;
    }

    public static bool IsCloudFormat(string path)
    {
        try
        {
            using (FileStream f = File.OpenRead(path))
            {
                byte[] h = new byte[64];
                if (f.Read(h, 0, 64) < 64) return false;
                return h[48] == 0x2f && h[49] == 0xe9 && h[50] == 0x8d && h[51] == 0x63;
            }
        }
        catch (Exception) { return false; }
    }

    internal class StrSet
    {
        Dictionary<string, bool> d = new Dictionary<string, bool>();
        public StrSet() { }
        public StrSet(string[] items) { foreach (string s in items) d[s] = true; }
        public bool Add(string s) { if (d.ContainsKey(s)) return false; d[s] = true; return true; }
        public bool Contains(string s) { return s != null && d.ContainsKey(s); }
        public int Count { get { return d.Count; } }
    }

    // ---------------------------------------------------------------- model
    internal class Run { public string T; public bool B, I, U, S, Link; public string Href; }
    internal class Block
    {
        public string Type; public int Depth; public List<Run> Runs; public string Style, List, Check;
        public List<List<List<Block>>> Rows; public string Src, Name, Alt, Ocr;
    }
    internal class Page
    {
        public string Title; public List<Block> Blocks; public DateTime? Created, Modified; public int Level = 1; public bool Orphan;
    }

    // ---------------------------------------------------------------- file format
    internal class Obj
    {
        public int Kind; // low 16 bits of jcid
        public Dictionary<uint, object> Props;
        public string Space;
    }

    internal class Section
    {
        public string Path;
        byte[] d;
        public Dictionary<string, Obj> Objects = new Dictionary<string, Obj>();
        public Dictionary<string, Dictionary<uint, string>> Roots = new Dictionary<string, Dictionary<uint, string>>();
        public List<string> SpaceOrder = new List<string>();
        public Dictionary<string, string[]> FileData = new Dictionary<string, string[]>(); // oid -> kind, ref, ext
        public Dictionary<string, long[]> Blobs = new Dictionary<string, long[]>();          // guid -> offset, length
        Dictionary<string, int> kindByKey = new Dictionary<string, int>();

        // id resolution
        Dictionary<uint, string> table = new Dictionary<uint, string>();
        Dictionary<uint, string> revTable = new Dictionary<uint, string>();
        Dictionary<string, Dictionary<uint, string>> tablesByRid = new Dictionary<string, Dictionary<uint, string>>();
        List<Dictionary<uint, string>> allTables = new List<Dictionary<uint, string>>();
        string curRid, curDep;
        int listsVisited, groupDepth;

        public Section(string path) { Path = path; }

        public void Load()
        {
            d = File.ReadAllBytes(Path);
            if (d.Length < 1024) throw new Exception("file too small");
            // guidFileFormat must be the revision store format {109ADD3F-911B-49F5-A5D0-1791EDC8AED8}
            if (!(d[48] == 0x3f && d[49] == 0xdd && d[50] == 0x9a && d[51] == 0x10))
                throw new Exception("not a OneNote desktop revision-store file");
            long stp = (long)BitConverter.ToUInt64(d, 172);
            long cb = BitConverter.ToUInt32(d, 180);
            ParseList(stp, cb, null, 0);
        }

        static string Ex(byte[] d, int off)
        {
            byte[] g = new byte[16];
            Array.Copy(d, off, g, 0, 16);
            return new Guid(g).ToString() + "|" + BitConverter.ToUInt32(d, off + 16);
        }

        string Resolve(uint v)
        {
            if (v == 0) return null;
            uint n = v & 0xff, idx = v >> 8;
            string g;
            if (table.TryGetValue(idx, out g)) return g + "|" + n;
            if (revTable.TryGetValue(idx, out g)) return g + "|" + n;
            for (int i = allTables.Count - 1; i >= 0; i--)
                if (allTables[i].TryGetValue(idx, out g)) return g + "|" + n;
            return null;
        }

        void ReadRef(ref int p, int stpFormat, int cbFormat, out long stp, out long cb)
        {
            switch (stpFormat)
            {
                case 0: stp = (long)BitConverter.ToUInt64(d, p); p += 8; break;
                case 1: stp = BitConverter.ToUInt32(d, p); p += 4; break;
                case 2: stp = (long)BitConverter.ToUInt16(d, p) * 8; p += 2; break;
                default: stp = (long)BitConverter.ToUInt32(d, p) * 8; p += 4; break;
            }
            switch (cbFormat)
            {
                case 0: cb = BitConverter.ToUInt32(d, p); p += 4; break;
                case 1: cb = (long)BitConverter.ToUInt64(d, p); p += 8; break;
                case 2: cb = (long)d[p] * 8; p += 1; break;
                default: cb = (long)BitConverter.ToUInt16(d, p) * 8; p += 2; break;
            }
        }

        bool Valid(long stp, long cb) { return stp >= 0 && cb > 0 && stp + cb <= d.Length && stp < d.Length; }

        void ParseList(long stp, long cb, string space, int depth)
        {
            if (depth > 30 || ++listsVisited > 200000) return;
            int guard = 0;
            while (Valid(stp, cb) && guard++ < 100000)
            {
                long end = stp + cb;
                if (BitConverter.ToUInt64(d, (int)stp) != 0xA4567AB1F5F7F4C4UL) return;
                int p = (int)stp + 16;
                while (p + 4 <= end - 20)
                {
                    uint h = BitConverter.ToUInt32(d, p);
                    int id = (int)(h & 0x3ff);
                    int size = (int)((h >> 10) & 0x1fff);
                    int stpF = (int)((h >> 23) & 3), cbF = (int)((h >> 25) & 3);
                    if (id == 0xff || id == 0 || size < 4) break;
                    int start = p;
                    p += 4;
                    try { Node(id, p, stpF, cbF, space, depth); }
                    catch (Exception) { }
                    p = start + size;
                }
                int q = (int)(end - 20);
                long nstp = (long)BitConverter.ToUInt64(d, q);
                long ncb = BitConverter.ToUInt32(d, q + 8);
                if (nstp == unchecked((long)0xFFFFFFFFFFFFFFFFUL) || ncb == 0 || nstp == stp) return;
                stp = nstp; cb = ncb;
            }
        }

        void Node(int id, int p, int stpF, int cbF, string space, int depth)
        {
            long stp, cb;
            switch (id)
            {
                case 0x004: break; // ObjectSpaceManifestRootFND
                case 0x008: // ObjectSpaceManifestListReferenceFND
                    {
                        ReadRef(ref p, stpF, cbF, out stp, out cb);
                        string sp = Ex(d, p);
                        if (!Roots.ContainsKey(sp)) { Roots[sp] = new Dictionary<uint, string>(); SpaceOrder.Add(sp); }
                        ParseList(stp, cb, sp, depth + 1);
                        break;
                    }
                case 0x010: // RevisionManifestListReferenceFND
                case 0x090: // FileDataStoreListReferenceFND
                    ReadRef(ref p, stpF, cbF, out stp, out cb);
                    ParseList(stp, cb, space, depth + 1);
                    break;
                case 0x01B: case 0x01E: case 0x01F: // RevisionManifestStart4/6/7
                    curRid = Ex(d, p); curDep = Ex(d, p + 20);
                    revTable = new Dictionary<uint, string>();
                    table = revTable;
                    tablesByRid[curRid] = revTable; allTables.Add(revTable);
                    break;
                case 0x021: case 0x022: // GlobalIdTableStart(2)
                    table = new Dictionary<uint, string>();
                    allTables.Add(table);
                    if (groupDepth == 0)
                    {
                        revTable = table;
                        if (curRid != null) tablesByRid[curRid] = table;
                    }
                    break;
                case 0x024: // GlobalIdTableEntryFNDX
                    {
                        uint idx = BitConverter.ToUInt32(d, p);
                        byte[] g = new byte[16]; Array.Copy(d, p + 4, g, 0, 16);
                        table[idx] = new Guid(g).ToString();
                        break;
                    }
                case 0x025: // GlobalIdTableEntry2FNDX
                    {
                        uint from = BitConverter.ToUInt32(d, p), to = BitConverter.ToUInt32(d, p + 4);
                        Dictionary<uint, string> dep; string g;
                        if (curDep != null && tablesByRid.TryGetValue(curDep, out dep) && dep.TryGetValue(from, out g)) table[to] = g;
                        break;
                    }
                case 0x026: // GlobalIdTableEntry3FNDX
                    {
                        uint from = BitConverter.ToUInt32(d, p), cnt = BitConverter.ToUInt32(d, p + 4), to = BitConverter.ToUInt32(d, p + 8);
                        Dictionary<uint, string> dep; string g;
                        if (curDep != null && tablesByRid.TryGetValue(curDep, out dep))
                            for (uint i = 0; i < cnt && i < 100000; i++) if (dep.TryGetValue(from + i, out g)) table[to + i] = g;
                        break;
                    }
                case 0x0B0: // ObjectGroupListReferenceFND
                    {
                        ReadRef(ref p, stpF, cbF, out stp, out cb);
                        Dictionary<uint, string> saved = table;
                        groupDepth++;
                        try { ParseList(stp, cb, space, depth + 1); }
                        finally { groupDepth--; table = saved; }
                        break;
                    }
                case 0x059: // RootObjectReference2FNDX
                    {
                        string k = Resolve(BitConverter.ToUInt32(d, p));
                        uint role = BitConverter.ToUInt32(d, p + 4);
                        if (k != null && space != null) Roots[space][role] = k;
                        break;
                    }
                case 0x05A: // RootObjectReference3FND
                    if (space != null) Roots[space][BitConverter.ToUInt32(d, p + 20)] = Ex(d, p);
                    break;
                case 0x0A4: case 0x0A5: case 0x0C4: case 0x0C5: // ObjectDeclaration2(Large)RefCountFND, ReadOnly
                    {
                        ReadRef(ref p, stpF, cbF, out stp, out cb);
                        string k = Resolve(BitConverter.ToUInt32(d, p));
                        uint jcid = BitConverter.ToUInt32(d, p + 4);
                        if (k != null)
                        {
                            kindByKey[k] = (int)(jcid & 0xffff);
                            if (((jcid >> 17) & 1) == 1) AddObject(k, (int)(jcid & 0xffff), stp, cb, space);
                        }
                        break;
                    }
                case 0x02D: case 0x02E: // ObjectDeclarationWithRefCountFNDX (older layout)
                    {
                        ReadRef(ref p, stpF, cbF, out stp, out cb);
                        string k = Resolve(BitConverter.ToUInt32(d, p));
                        int jci = BitConverter.ToUInt16(d, p + 4) & 0x3ff;
                        if (k != null) { kindByKey[k] = jci; AddObject(k, jci, stp, cb, space); }
                        break;
                    }
                case 0x041: case 0x042: // ObjectRevisionWithRefCountFNDX - edited objects
                    {
                        ReadRef(ref p, stpF, cbF, out stp, out cb);
                        string k = Resolve(BitConverter.ToUInt32(d, p));
                        int kind;
                        if (k != null && kindByKey.TryGetValue(k, out kind)) AddObject(k, kind, stp, cb, space);
                        else if (k != null) AddObject(k, -1, stp, cb, space);
                        break;
                    }
                case 0x072: case 0x073: // ObjectDeclarationFileData3(Large)RefCountFND
                    {
                        string k = Resolve(BitConverter.ToUInt32(d, p));
                        int q = p + 8 + (id == 0x072 ? 1 : 4);
                        string fref = Sis(ref q), ext = Sis(ref q);
                        if (k != null)
                        {
                            if (fref.StartsWith("<ifndf>"))
                                FileData[k] = new string[] { "guid", fref.Replace("<ifndf>", "").Trim('{', '}').ToLowerInvariant(), ext };
                            else if (fref.StartsWith("<file>"))
                                FileData[k] = new string[] { "file", fref.Substring(6), ext };
                        }
                        break;
                    }
                case 0x094: // FileDataStoreObjectReferenceFND
                    {
                        ReadRef(ref p, stpF, cbF, out stp, out cb);
                        byte[] g = new byte[16]; Array.Copy(d, p, g, 0, 16);
                        if (Valid(stp, cb) && stp + 36 <= d.Length)
                        {
                            long len = (long)BitConverter.ToUInt64(d, (int)stp + 16);
                            if (len >= 0 && stp + 36 + len <= d.Length)
                                Blobs[new Guid(g).ToString().ToLowerInvariant()] = new long[] { stp + 36, len };
                        }
                        break;
                    }
            }
        }

        string Sis(ref int q)
        {
            int cch = (int)BitConverter.ToUInt32(d, q); q += 4;
            if (cch < 0 || cch > 100000) throw new Exception("bad string");
            string s = Encoding.Unicode.GetString(d, q, cch * 2); q += cch * 2;
            return s;
        }

        void AddObject(string key, int kind, long stp, long cb, string space)
        {
            if (!Valid(stp, cb)) return;
            Dictionary<uint, object> props;
            try { props = ReadPropSet((int)stp); }
            catch (Exception) { return; }
            Obj o = new Obj();
            o.Kind = kind; o.Props = props; o.Space = space;
            Objects[key] = o; // later revisions win
        }

        class Streams { public List<string> Oids = new List<string>(), Osids = new List<string>(), Ctx = new List<string>(); public int Oi, Si, Ci; }

        Dictionary<uint, object> ReadPropSet(int p)
        {
            Streams s = new Streams();
            uint h = BitConverter.ToUInt32(d, p); p += 4;
            int count = (int)(h & 0xffffff);
            bool ext = ((h >> 30) & 1) == 1, noOsid = ((h >> 31) & 1) == 1;
            for (int i = 0; i < count; i++) { s.Oids.Add(Resolve(BitConverter.ToUInt32(d, p))); p += 4; }
            if (!noOsid)
            {
                uint h2 = BitConverter.ToUInt32(d, p); p += 4;
                int c2 = (int)(h2 & 0xffffff);
                for (int i = 0; i < c2; i++) { s.Osids.Add(Resolve(BitConverter.ToUInt32(d, p))); p += 4; }
                ext = ((h2 >> 30) & 1) == 1;
            }
            if (ext)
            {
                uint h3 = BitConverter.ToUInt32(d, p); p += 4;
                int c3 = (int)(h3 & 0xffffff);
                for (int i = 0; i < c3; i++) { s.Ctx.Add(Resolve(BitConverter.ToUInt32(d, p))); p += 4; }
            }
            return ReadProps(ref p, s, 0);
        }

        Dictionary<uint, object> ReadProps(ref int p, Streams s, int depth)
        {
            if (depth > 20) throw new Exception("nesting");
            int n = BitConverter.ToUInt16(d, p); p += 2;
            uint[] prids = new uint[n];
            for (int i = 0; i < n; i++) { prids[i] = BitConverter.ToUInt32(d, p); p += 4; }
            Dictionary<uint, object> props = new Dictionary<uint, object>();
            for (int i = 0; i < n; i++)
            {
                uint pr = prids[i];
                int type = (int)((pr >> 26) & 0x1f);
                uint key = pr & 0x7fffffff;
                object v = null;
                switch (type)
                {
                    case 0x1: v = null; break;
                    case 0x2: v = ((pr >> 31) & 1) == 1; break;
                    case 0x3: v = Slice(p, 1); p += 1; break;
                    case 0x4: v = Slice(p, 2); p += 2; break;
                    case 0x5: v = Slice(p, 4); p += 4; break;
                    case 0x6: v = Slice(p, 8); p += 8; break;
                    case 0x7:
                        {
                            int len = (int)BitConverter.ToUInt32(d, p); p += 4;
                            if (len < 0 || p + len > d.Length) throw new Exception("bad length");
                            v = Slice(p, len); p += len; break;
                        }
                    case 0x8: case 0x9:
                        {
                            int c = 1;
                            if (type == 0x9) { c = (int)BitConverter.ToUInt32(d, p); p += 4; }
                            List<string> l = new List<string>();
                            for (int j = 0; j < c; j++) l.Add(s.Oi < s.Oids.Count ? s.Oids[s.Oi++] : null);
                            v = l; break;
                        }
                    case 0xA: case 0xB:
                        {
                            int c = 1;
                            if (type == 0xB) { c = (int)BitConverter.ToUInt32(d, p); p += 4; }
                            List<string> l = new List<string>();
                            for (int j = 0; j < c; j++) l.Add(s.Si < s.Osids.Count ? s.Osids[s.Si++] : null);
                            v = l; break;
                        }
                    case 0xC: case 0xD:
                        {
                            int c = 1;
                            if (type == 0xD) { c = (int)BitConverter.ToUInt32(d, p); p += 4; }
                            List<string> l = new List<string>();
                            for (int j = 0; j < c; j++) l.Add(s.Ci < s.Ctx.Count ? s.Ctx[s.Ci++] : null);
                            v = l; break;
                        }
                    case 0x10:
                        {
                            int c = (int)BitConverter.ToUInt32(d, p); p += 4;
                            List<Dictionary<uint, object>> arr = new List<Dictionary<uint, object>>();
                            if (c > 0) { p += 4; for (int j = 0; j < c && j < 100000; j++) arr.Add(ReadProps(ref p, s, depth + 1)); }
                            v = arr; break;
                        }
                    case 0x11: v = ReadProps(ref p, s, depth + 1); break;
                    default: throw new Exception("bad property type");
                }
                props[key] = v;
            }
            return props;
        }

        byte[] Slice(int p, int len)
        {
            byte[] b = new byte[len];
            Array.Copy(d, p, b, 0, len);
            return b;
        }

        public byte[] FileBytes(string key, out string ext)
        {
            ext = null;
            string[] fd;
            if (key == null || !FileData.TryGetValue(key, out fd)) return null;
            ext = fd[2];
            if (fd[0] == "guid")
            {
                long[] b;
                if (Blobs.TryGetValue(fd[1], out b)) return Slice((int)b[0], (int)b[1]);
                return null;
            }
            string dir = System.IO.Path.GetDirectoryName(Path);
            string[] cands = { System.IO.Path.Combine(System.IO.Path.Combine(dir, "onefiles"), fd[1]), System.IO.Path.Combine(dir, fd[1]) };
            foreach (string c in cands) if (File.Exists(c)) return File.ReadAllBytes(c);
            return null;
        }
    }

    // ---------------------------------------------------------------- pages
    const uint P_CONTENT_CHILDREN = 0x24001C1F, P_ELEMENT_CHILDREN = 0x24001C20, P_GRAPH_SPACES = 0x2C001D63;
    const uint P_PICTURE = 0x20001C3F, P_WEBPICTURE = 0x200034C8, P_EMBEDDED_FILE = 0x20001D9B;
    const uint P_TEXT_UNICODE = 0x1C001C22, P_TEXT_ASCII = 0x1C003498, P_TITLE_CACHED = 0x1C001CF3, P_TITLE_FROM_PAGE = 0x1C001D3C;
    const uint P_IMAGE_FILENAME = 0x1C001DD7, P_IMAGE_ALT = 0x1C001E58, P_EMBEDDED_NAME = 0x1C001D9C;
    const uint P_LAST_MODIFIED = 0x14001D7A, P_TOPO_CREATED = 0x18001C65;
    const uint P_TEXT_RUN_INDEX = 0x1C001E12, P_TEXT_RUN_FORMAT = 0x24001E13, P_PARAGRAPH_STYLE = 0x2000342C, P_STYLE_ID = 0x1C00345A;
    const uint P_BOLD = 0x08001C04, P_ITALIC = 0x08001C05, P_UNDERLINE = 0x08001C06, P_STRIKE = 0x08001C07, P_HYPERLINK = 0x08001E14;
    const uint P_LIST_NODES = 0x24001C26, P_NUMBER_FORMAT = 0x1C001C1A, P_NOTE_TAG_STATES = 0x04003489, P_NOTE_TAG_COMPLETED = 0x1400346F;
    const uint P_PAGE_LEVEL = 0x14001DFF;
    const int K_PAGESERIES = 0x08, K_PAGE = 0x0B, K_OUTLINE = 0x0C, K_OE = 0x0D, K_RICHTEXT = 0x0E, K_IMAGE = 0x11,
              K_OUTLINEGROUP = 0x19, K_TABLE = 0x22, K_ROW = 0x23, K_CELL = 0x24, K_TITLE = 0x2C, K_PAGEMETA = 0x30,
              K_EMBEDDED = 0x35, K_MANIFEST = 0x37;

    static readonly Regex FieldLink = new Regex("\uFDDFHYPERLINK\\s+\"([^\"]*)\"");

    internal class PageBuilder
    {
        Section sec;
        public PageBuilder(Section s) { sec = s; }

        Obj Get(string k) { Obj o; if (k != null && sec.Objects.TryGetValue(k, out o)) return o; return null; }

        static List<string> Refs(Obj o, uint pid)
        {
            object v; List<string> res = new List<string>();
            if (o != null && o.Props.TryGetValue(pid, out v))
            {
                List<string> l = v as List<string>;
                if (l != null) foreach (string x in l) if (x != null) res.Add(x);
            }
            return res;
        }
        static byte[] Bytes(Obj o, uint pid) { object v; if (o != null && o.Props.TryGetValue(pid, out v)) return v as byte[]; return null; }
        static bool Flag(Obj o, uint pid) { object v; return o != null && o.Props.TryGetValue(pid, out v) && v is bool && (bool)v; }
        static string Clean(string s) { return FixSymbols(s.Replace("\0", "").Replace("\r\n", "\n").Replace('\r', '\n').Replace('\v', '\n')); }
        // Bullets and arrows typed in Symbol/Wingdings fonts are stored as private-use characters
        // (U+F0xx) that normal fonts show as boxes. Map the common ones to regular characters.
        static string FixSymbols(string s)
        {
            bool any = false;
            foreach (char ch in s) if (ch >= '\uF000' && ch <= '\uF0FF') { any = true; break; }
            if (!any) return s;
            StringBuilder sb = new StringBuilder(s.Length);
            foreach (char ch in s)
            {
                if (ch < '\uF000' || ch > '\uF0FF') { sb.Append(ch); continue; }
                switch ((int)ch)
                {
                    case 0xF0B7: case 0xF0A1: case 0xF06C: sb.Append('\u2022'); break; // bullet
                    case 0xF0A7: case 0xF06E: sb.Append('\u25AA'); break;               // small square
                    case 0xF0A8: case 0xF06F: case 0xF071: sb.Append('\u25A1'); break;  // empty square
                    case 0xF076: sb.Append('\u25C6'); break;                            // diamond
                    case 0xF0D8: case 0xF0E0: case 0xF0E8: case 0xF0F0: sb.Append('\u2192'); break; // arrows
                    case 0xF0FC: sb.Append('\u2713'); break;                            // check
                    case 0xF0FB: case 0xF0FD: sb.Append('\u2717'); break;               // cross
                    case 0xF04A: sb.Append('\u263A'); break;                            // smiley
                    case 0xF0B0: sb.Append('\u00B0'); break;
                    default:
                        int a = ch - 0xF000;
                        if (a >= 0x20 && a < 0x7F) sb.Append((char)a); else sb.Append('\u2022');
                        break;
                }
            }
            return sb.ToString();
        }
        static string Text(Obj o, uint pid)
        {
            byte[] b = Bytes(o, pid);
            if (b == null) return null;
            return Clean(Encoding.Unicode.GetString(b, 0, b.Length - (b.Length % 2)));
        }
        static string Ascii(Obj o, uint pid)
        {
            byte[] b = Bytes(o, pid);
            if (b == null) return null;
            Encoding enc;
            try { enc = Encoding.GetEncoding(1252); } catch (Exception) { enc = Encoding.GetEncoding("iso-8859-1"); }
            return Clean(enc.GetString(b));
        }

        List<Run> Runs(Obj o, out string style)
        {
            style = null;
            string text = Text(o, P_TEXT_UNICODE) ?? Ascii(o, P_TEXT_ASCII);
            List<Run> outRuns = new List<Run>();
            if (text == null) return outRuns;
            List<string> ps = Refs(o, P_PARAGRAPH_STYLE);
            if (ps.Count > 0)
            {
                Obj so = Get(ps[0]);
                string sid = so != null ? Text(so, P_STYLE_ID) : null;
                if (sid != null && sid.Trim().Length > 0) style = sid.Trim();
            }
            List<int> ends = new List<int>();
            byte[] ib = Bytes(o, P_TEXT_RUN_INDEX);
            if (ib != null) for (int i = 0; i + 4 <= ib.Length; i += 4) ends.Add((int)BitConverter.ToUInt32(ib, i));
            List<string> fmts = Refs(o, P_TEXT_RUN_FORMAT);
            List<Run> runs = new List<Run>();
            int start = 0;
            for (int i = 0; i <= ends.Count; i++)
            {
                int e = i < ends.Count ? Math.Min(ends[i], text.Length) : text.Length;
                if (e < start) e = start;
                string seg = text.Substring(start, e - start);
                start = e;
                if (seg.Length == 0) continue;
                Obj st = i < fmts.Count ? Get(fmts[i]) : null;
                Run r = new Run();
                r.T = seg; r.B = Flag(st, P_BOLD); r.I = Flag(st, P_ITALIC); r.U = Flag(st, P_UNDERLINE);
                r.S = Flag(st, P_STRIKE); r.Link = Flag(st, P_HYPERLINK);
                runs.Add(r);
            }
            string pending = null;
            foreach (Run r in runs)
            {
                string t = r.T;
                Match m = FieldLink.Match(t);
                while (m.Success)
                {
                    pending = m.Groups[1].Value;
                    t = t.Substring(0, m.Index) + t.Substring(m.Index + m.Length);
                    m = FieldLink.Match(t);
                }
                t = t.Replace("\uFDDF", "");
                if (t.Length == 0) continue;
                r.T = t;
                if (pending != null) { r.Href = pending; if (!r.Link) pending = null; }
                else if (r.Link && Regex.IsMatch(t.Trim(), "^(https?://|www\\.)")) r.Href = t.Trim();
                if (!r.Link) pending = null;
                outRuns.Add(r);
            }
            return outRuns;
        }

        string Checkbox(Obj oe)
        {
            object v;
            if (!oe.Props.TryGetValue(P_NOTE_TAG_STATES, out v)) return null;
            List<Dictionary<uint, object>> l = v as List<Dictionary<uint, object>>;
            if (l == null || l.Count == 0) return null;
            foreach (Dictionary<uint, object> ps in l) if (ps.ContainsKey(P_NOTE_TAG_COMPLETED)) return "done";
            return "todo";
        }

        string ListMarker(Obj oe)
        {
            foreach (string k in Refs(oe, P_LIST_NODES))
            {
                Obj ln = Get(k);
                if (ln == null) continue;
                string f = Text(ln, P_NUMBER_FORMAT) ?? "";
                for (int i = 1; i < f.Length; i++) if (f[i] < 0x20 && f[i] != '\n') return "num";
                return "bullet";
            }
            return null;
        }

        void Walk(string k, int depth, StrSet seen, List<Block> outB)
        {
            if (k == null || seen.Contains(k) || seen.Count > 200000) return;
            seen.Add(k);
            Obj o = Get(k);
            if (o == null) return;
            int kind = o.Kind;
            if (kind == K_OUTLINE || kind == K_OUTLINEGROUP || kind == K_TITLE || kind == K_PAGE)
            {
                foreach (string c in Refs(o, P_ELEMENT_CHILDREN)) Walk(c, depth, seen, outB);
            }
            else if (kind == K_OE)
            {
                string marker = ListMarker(o), box = Checkbox(o);
                bool first = true;
                foreach (string c in Refs(o, P_CONTENT_CHILDREN))
                {
                    List<Block> sub = new List<Block>();
                    Walk(c, depth, seen, sub);
                    foreach (Block b in sub)
                    {
                        if (first && b.Type == "p") { if (marker != null) b.List = marker; if (box != null) b.Check = box; }
                        first = false;
                    }
                    outB.AddRange(sub);
                }
                foreach (string c in Refs(o, P_ELEMENT_CHILDREN)) Walk(c, depth + 1, seen, outB);
            }
            else if (kind == K_RICHTEXT)
            {
                string style;
                List<Run> runs = Runs(o, out style);
                bool any = false;
                foreach (Run r in runs) if (r.T.Trim().Length > 0) { any = true; break; }
                if (any) { Block b = new Block(); b.Type = "p"; b.Depth = depth; b.Runs = runs; b.Style = style; outB.Add(b); }
            }
            else if (kind == K_TABLE)
            {
                List<List<List<Block>>> rows = new List<List<List<Block>>>();
                foreach (string rk in Refs(o, P_ELEMENT_CHILDREN))
                {
                    Obj ro = Get(rk);
                    if (ro == null) continue;
                    List<List<Block>> cells = new List<List<Block>>();
                    foreach (string ck in Refs(ro, P_ELEMENT_CHILDREN))
                    {
                        List<Block> cb = new List<Block>();
                        Obj co = Get(ck);
                        if (co != null) foreach (string ek in Refs(co, P_ELEMENT_CHILDREN)) Walk(ek, 0, seen, cb);
                        cells.Add(cb);
                    }
                    rows.Add(cells);
                }
                if (rows.Count > 0) { Block b = new Block(); b.Type = "table"; b.Depth = depth; b.Rows = rows; outB.Add(b); }
            }
            else if (kind == K_IMAGE)
            {
                List<string> refs = Refs(o, P_PICTURE);
                if (refs.Count == 0) refs = Refs(o, P_WEBPICTURE);
                Block b = new Block(); b.Type = "img"; b.Depth = depth;
                b.Name = (Text(o, P_IMAGE_FILENAME) ?? "").Trim(); if (b.Name.Length == 0) b.Name = "image";
                b.Alt = (Text(o, P_IMAGE_ALT) ?? "").Trim();
                b.Ocr = (Text(o, P_TEXT_UNICODE) ?? "").Trim();
                if (refs.Count > 0)
                {
                    string ext; byte[] data = sec.FileBytes(refs[0], out ext);
                    if (data != null && data.Length > 0) b.Src = EmitAsset(data, b.Name, ext);
                }
                outB.Add(b);
            }
            else if (kind == K_EMBEDDED)
            {
                List<string> refs = Refs(o, P_EMBEDDED_FILE);
                Block b = new Block(); b.Type = "file"; b.Depth = depth;
                b.Name = (Text(o, P_EMBEDDED_NAME) ?? "").Trim(); if (b.Name.Length == 0) b.Name = "attachment";
                if (refs.Count > 0)
                {
                    string ext; byte[] data = sec.FileBytes(refs[0], out ext);
                    if (data != null && data.Length > 0) b.Src = EmitAsset(data, b.Name, ext);
                }
                outB.Add(b);
            }
            else
            {
                foreach (string c in Refs(o, P_ELEMENT_CHILDREN)) Walk(c, depth, seen, outB);
                foreach (string c in Refs(o, P_CONTENT_CHILDREN)) Walk(c, depth, seen, outB);
            }
        }

        static DateTime? FileTime(byte[] b)
        {
            if (b == null || b.Length != 8) return null;
            long v = BitConverter.ToInt64(b, 0);
            if (v <= 0) return null;
            try { return DateTime.FromFileTimeUtc(v).ToLocalTime(); } catch (Exception) { return null; }
        }
        static DateTime? Time32(byte[] b)
        {
            if (b == null || b.Length != 4) return null;
            uint v = BitConverter.ToUInt32(b, 0);
            if (v == 0) return null;
            return new DateTime(1980, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddSeconds(v).ToLocalTime();
        }

        Page FromSpace(string space)
        {
            Dictionary<uint, string> roots;
            sec.Roots.TryGetValue(space, out roots);
            string pageKey = null; Obj meta = null;
            if (roots != null)
            {
                foreach (KeyValuePair<uint, string> kv in roots)
                {
                    Obj o = Get(kv.Value);
                    if (o == null) continue;
                    if (o.Kind == K_MANIFEST) { foreach (string c in Refs(o, P_CONTENT_CHILDREN)) { Obj co = Get(c); if (co != null && co.Kind == K_PAGE) pageKey = c; } }
                    else if (o.Kind == K_PAGE) pageKey = kv.Value;
                    else if (o.Kind == K_PAGEMETA) meta = o;
                }
            }
            if (pageKey == null)
                foreach (KeyValuePair<string, Obj> kv in sec.Objects) if (kv.Value.Space == space && kv.Value.Kind == K_PAGE) { pageKey = kv.Key; break; }
            if (pageKey == null) return null;
            if (meta == null)
                foreach (Obj o in sec.Objects.Values) if (o.Space == space && o.Kind == K_PAGEMETA) { meta = o; break; }
            Obj po = Get(pageKey);
            string title = meta != null ? Text(meta, P_TITLE_CACHED) : null;
            if (string.IsNullOrEmpty(title) || title.Trim().Length == 0) title = Text(po, P_TITLE_FROM_PAGE);
            List<Block> blocks = new List<Block>(), titleBlocks = new List<Block>();
            StrSet seen = new StrSet();
            foreach (string c in Refs(po, P_ELEMENT_CHILDREN))
            {
                Obj co = Get(c);
                if (co != null && co.Kind == K_TITLE) Walk(c, 0, seen, titleBlocks); else Walk(c, 0, seen, blocks);
            }
            if (title == null || title.Trim().Length == 0)
            {
                StringBuilder tb = new StringBuilder();
                foreach (Block b in titleBlocks) if (b.Type == "p") { foreach (Run r in b.Runs) tb.Append(r.T); tb.Append(' '); }
                title = tb.ToString();
            }
            title = (title ?? "").Trim();
            if (title.Length == 0) title = "Untitled page";
            Page p = new Page();
            p.Title = title; p.Blocks = blocks;
            if (meta != null) p.Created = FileTime(Bytes(meta, P_TOPO_CREATED));
            p.Modified = Time32(Bytes(po, P_LAST_MODIFIED));
            if (meta != null)
            {
                byte[] lv = Bytes(meta, P_PAGE_LEVEL);
                if (lv != null && lv.Length == 4) { int l = (int)BitConverter.ToUInt32(lv, 0); p.Level = Math.Max(1, Math.Min(3, l)); }
            }
            return p;
        }

        public List<Page> Pages()
        {
            List<string> order = new List<string>();
            StrSet listed = new StrSet();
            foreach (Obj o in sec.Objects.Values)
            {
                if (o.Kind != K_PAGESERIES) continue;
                foreach (string k in Refs(o, P_GRAPH_SPACES)) if (listed.Add(k)) order.Add(k);
            }
            foreach (string sp in sec.SpaceOrder) if (!listed.Contains(sp) && !order.Contains(sp)) order.Add(sp);
            List<Page> pages = new List<Page>();
            StrSet sigs = new StrSet();
            foreach (string sp in order)
            {
                Page p = FromSpace(sp);
                if (p == null) continue;
                if (listed.Count > 0 && !listed.Contains(sp))
                {
                    if (p.Blocks.Count == 0) continue;
                    p.Orphan = true;
                }
                string plain = Plain(p.Blocks);
                string sig = p.Title + "\u0001" + p.Blocks.Count + "\u0001" + (plain.Length > 2000 ? plain.Substring(0, 2000) : plain);
                if (!sigs.Add(sig)) continue;
                pages.Add(p);
            }
            return pages;
        }
    }

    // ---------------------------------------------------------------- fallback
    static readonly StrSet Noise = new StrSet(new string[] {
        "Calibri", "Calibri Light", "PageTitle", "PageDateTime", "PageTime", "Consolas", "Comic Sans MS", "Comic sans",
        "Arial", "Segoe UI", "Times New Roman", "Courier New", "Cambria", "Aptos", "Verdana", "blockquote", "cite",
        "OneNote_RecycleBin", "Tahoma", "Atlassian Sans" });

    static List<Page> RawText(string path)
    {
        byte[] d = File.ReadAllBytes(path);
        List<KeyValuePair<int, string>> items = new List<KeyValuePair<int, string>>();
        StrSet seen = new StrSet();
        for (int align = 0; align < 2; align++)
        {
            StringBuilder cur = new StringBuilder();
            int curStart = -1;
            for (int i = align; i + 1 < d.Length; i += 2)
            {
                byte lo = d[i], hi = d[i + 1];
                bool ok = (hi == 0 && ((lo >= 0x20 && lo <= 0x7e) || lo >= 0xa0 || lo == 9 || lo == 10 || lo == 13))
                          || (hi == 0x20 && (lo == 0x13 || lo == 0x14 || (lo >= 0x18 && lo <= 0x1d) || lo == 0x22 || lo == 0x26 || lo == 0xac));
                if (ok) { if (curStart < 0) curStart = i; cur.Append((char)(lo | (hi << 8))); }
                if (!ok || i + 3 >= d.Length)
                {
                    if (cur.Length >= 6)
                    {
                        string s = cur.ToString().Replace("\r\n", "\n").Replace('\r', '\n').Trim();
                        int letters = 0; foreach (char c in s) if (char.IsLetter(c)) letters++;
                        if (letters >= 4 && !seen.Contains(s) && !Noise.Contains(s)
                            && !Regex.IsMatch(s, "^[A-Za-z]:\\\\") && !Regex.IsMatch(s, "^\\{?[0-9a-fA-F-]{36}\\}?$"))
                        { seen.Add(s); items.Add(new KeyValuePair<int, string>(curStart, s)); }
                    }
                    cur.Length = 0; curStart = -1;
                }
            }
        }
        items.Sort(delegate (KeyValuePair<int, string> a, KeyValuePair<int, string> b) { return a.Key.CompareTo(b.Key); });
        List<Page> pages = new List<Page>();
        if (items.Count == 0) return pages;
        Page p = new Page(); p.Title = "Recovered text"; p.Blocks = new List<Block>();
        foreach (KeyValuePair<int, string> it in items)
        {
            string s = FieldLink.Replace(it.Value, "").Replace("\uFDDF", "");
            Block b = new Block(); b.Type = "p"; b.Runs = new List<Run>();
            Run r = new Run(); r.T = s; b.Runs.Add(r);
            p.Blocks.Add(b);
        }
        pages.Add(p);
        return pages;
    }
}
'@

if (-not ('OneNoteReader' -as [type])) {
    Add-Type -TypeDefinition $cs -Language CSharp
}

# ---------------------------------------------------------------- viewer page
$template = @'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>OneNote Viewer</title>
<style>
:root{
  --bg:#f6f5f8; --panel:#ffffff; --side:#f0eef4; --ink:#1f1d24; --muted:#6b6776; --line:#e2dfe8;
  --accent:#7719aa; --accent-soft:#efe4f6; --hit:#fff1a8; --hit-strong:#ffd84d; --code:#f3f1f6;
  --warn-bg:#fff6e5; --warn-line:#f0c46a;
}
@media (prefers-color-scheme: dark){
  :root{
    --bg:#16151a; --panel:#1e1d23; --side:#19181d; --ink:#ebe8f0; --muted:#9a95a6; --line:#2e2c35;
    --accent:#c38be6; --accent-soft:#2c2235; --hit:#5a4a10; --hit-strong:#8a6d00; --code:#26242c;
    --warn-bg:#2d2615; --warn-line:#6b5420;
  }
}
*{box-sizing:border-box}
html,body{height:100%}
body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.55 "Segoe UI",system-ui,-apple-system,Roboto,Helvetica,Arial,sans-serif}
a{color:var(--accent)}
.app{display:grid;grid-template-columns:340px 1fr;height:100vh}
aside{background:var(--side);border-right:1px solid var(--line);display:flex;flex-direction:column;min-height:0}
.brand{padding:16px 16px 10px;display:flex;align-items:center;gap:10px}
.brand .logo{width:28px;height:28px;border-radius:6px;background:var(--accent);color:#fff;display:grid;place-items:center;font-weight:700;font-size:15px}
.brand h1{font-size:15px;margin:0;font-weight:600}
.brand small{display:block;color:var(--muted);font-size:12px;font-weight:400}
.search{padding:4px 12px 10px}
.search input{width:100%;padding:9px 12px;border:1px solid var(--line);border-radius:8px;background:var(--panel);color:var(--ink);font:inherit;outline:none}
.search input:focus{border-color:var(--accent);box-shadow:0 0 0 3px var(--accent-soft)}
.search .meta{font-size:12px;color:var(--muted);padding:6px 2px 0;min-height:18px}
.tree{overflow:auto;flex:1;padding:0 6px 20px}
.nb>.row{font-weight:600}
.row{display:flex;align-items:center;gap:6px;padding:5px 8px;border-radius:6px;cursor:pointer;user-select:none;color:var(--ink)}
.row:hover{background:var(--accent-soft)}
.row .chev{width:14px;color:var(--muted);flex:none;transition:transform .12s;font-size:11px}
.open>.row .chev{transform:rotate(90deg)}
.row .count{margin-left:auto;color:var(--muted);font-size:12px;font-weight:400}
.row .badge{font-size:10px;padding:1px 6px;border-radius:10px;background:var(--warn-bg);border:1px solid var(--warn-line);color:var(--ink);font-weight:400}
.kids{display:none;padding-left:12px}
.open>.kids{display:block}
.sec>.row{font-size:14px}
.sec .swatch{width:4px;height:16px;border-radius:2px;flex:none}
.pg{display:block;padding:4px 8px 4px 28px;border-radius:6px;cursor:pointer;color:var(--ink);text-decoration:none;font-size:13.5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.pg.l2{padding-left:44px}.pg.l3{padding-left:60px}
.pg:hover{background:var(--accent-soft)}
.pg.active{background:var(--accent);color:#fff}
.pg .d{color:var(--muted);font-size:11.5px;margin-left:6px}
.pg.active .d{color:#eee}
.results .res{padding:8px 10px;border-radius:8px;cursor:pointer;margin:2px 0}
.results .res:hover,.results .res.active{background:var(--accent-soft)}
.results .res b{display:block;font-size:13.5px;font-weight:600}
.results .res .where{font-size:11.5px;color:var(--muted)}
.results .res .snip{font-size:12.5px;color:var(--ink);opacity:.85;margin-top:2px}
mark{background:var(--hit);color:inherit;border-radius:2px;padding:0 1px}
mark.cur{background:var(--hit-strong)}
main{overflow:auto;min-width:0}
.topbar{position:sticky;top:0;background:color-mix(in srgb,var(--bg) 92%,transparent);backdrop-filter:blur(6px);display:flex;align-items:center;gap:8px;padding:10px 28px;border-bottom:1px solid var(--line);z-index:2}
.crumbs{color:var(--muted);font-size:13px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;flex:1}
.btn{border:1px solid var(--line);background:var(--panel);color:var(--ink);border-radius:7px;padding:6px 11px;font:inherit;font-size:13px;cursor:pointer;white-space:nowrap}
.btn:hover{border-color:var(--accent)}
.btn:disabled{opacity:.4;cursor:default}
.paper{max-width:900px;margin:24px auto 80px;background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:36px 48px 48px;min-height:60vh}
.paper h2.title{font-size:28px;font-weight:600;margin:0 0 4px;line-height:1.25;border-bottom:1px solid var(--line);padding-bottom:10px}
.paper .dates{color:var(--muted);font-size:12.5px;margin-bottom:22px}
.warn{background:var(--warn-bg);border:1px solid var(--warn-line);border-radius:8px;padding:10px 14px;font-size:13.5px;margin-bottom:18px}
.content p{margin:0 0 6px;white-space:pre-wrap;word-wrap:break-word}
.content .li{display:flex;gap:8px}
.content .li>.m{flex:none;min-width:1.1em;color:var(--muted);text-align:right}
.content h1,.content h2,.content h3,.content h4,.content h5,.content h6{margin:16px 0 6px;line-height:1.3}
.content h1{font-size:22px}.content h2{font-size:19px}.content h3{font-size:17px}.content h4,.content h5,.content h6{font-size:15px}
.content .code{font-family:Consolas,"Cascadia Mono",monospace;background:var(--code);padding:2px 6px;border-radius:4px;font-size:13.5px}
.content .quote{border-left:3px solid var(--line);padding-left:10px;color:var(--muted)}
.content .chk{font-size:16px;line-height:1;margin-right:2px}
.content .done{color:var(--muted)}
.content table{border-collapse:collapse;margin:8px 0 12px;max-width:100%}
.content td{border:1px solid var(--line);padding:6px 9px;vertical-align:top;min-width:40px}
.content td p:last-child{margin-bottom:0}
.content figure{margin:8px 0 12px}
.content figure img{max-width:100%;height:auto;border-radius:6px;border:1px solid var(--line);cursor:zoom-in;background:#fff}
.content figcaption{font-size:12px;color:var(--muted);white-space:pre-wrap}
.content .file{display:inline-flex;align-items:center;gap:8px;padding:7px 12px;border:1px solid var(--line);border-radius:8px;margin:4px 0 10px;text-decoration:none;color:var(--ink);background:var(--bg)}
.content .file:hover{border-color:var(--accent)}
.content .ocr{border:1px dashed var(--line);border-radius:8px;padding:8px 12px;margin:6px 0 12px;font-size:13.5px;white-space:pre-wrap}
.content .ocr .lbl{display:block;font-size:11.5px;color:var(--muted);margin-bottom:4px}
.empty{color:var(--muted);text-align:center;padding:80px 20px}
.lightbox{position:fixed;inset:0;background:rgba(0,0,0,.82);display:none;align-items:center;justify-content:center;z-index:9;cursor:zoom-out}
.lightbox img{max-width:94vw;max-height:94vh;background:#fff}
.lightbox.on{display:flex}
.toast{position:fixed;bottom:22px;left:50%;transform:translateX(-50%);background:var(--ink);color:var(--bg);padding:8px 16px;border-radius:8px;font-size:13px;opacity:0;transition:opacity .2s;pointer-events:none}
.toast.on{opacity:1}
.menu-btn{display:none}
@media (max-width:820px){
  .app{grid-template-columns:1fr}
  aside{position:fixed;inset:0 20% 0 0;z-index:5;transform:translateX(-100%);transition:transform .2s}
  aside.show{transform:none}
  .menu-btn{display:inline-block}
  .paper{margin:12px;padding:22px 18px}
  .topbar{padding:10px 12px}
}
@media print{aside,.topbar{display:none}.app{display:block}.paper{border:0;margin:0;max-width:none}}
</style>
</head>
<body>
<div class="app">
  <aside id="side">
    <div class="brand"><div class="logo">N</div><div><h1>OneNote Viewer</h1><small id="stats"></small></div></div>
    <div class="search"><input id="q" type="search" placeholder="Search all notes  ( / )" autocomplete="off"><div class="meta" id="qmeta"></div></div>
    <div class="tree" id="tree"></div>
    <div class="tree results" id="results" hidden></div>
  </aside>
  <main id="main">
    <div class="topbar">
      <button class="btn menu-btn" id="menu">&#x2630;</button>
      <div class="crumbs" id="crumbs"></div>
      <button class="btn" id="prevHit" hidden title="Previous match">&#x25B2;</button>
      <button class="btn" id="nextHit" hidden title="Next match">&#x25BC;</button>
      <button class="btn" id="prev" title="Previous page (Alt+&#x2191;)">&#x2039; Prev</button>
      <button class="btn" id="next" title="Next page (Alt+&#x2193;)">Next &#x203A;</button>
      <button class="btn" id="copy" title="Copy this page so you can paste it into OneNote web">Copy page</button>
    </div>
    <div class="paper" id="paper"><div class="empty">Pick a page on the left, or search all your notes.</div></div>
  </main>
</div>
<div class="lightbox" id="lb"><img alt=""></div>
<div class="toast" id="toast"></div>
<script>
const DATA = /*__DATA__*/null;
const COLORS=['#7719aa','#2b88d8','#e3008c','#00a36c','#d87a00','#c239b3','#0099bc','#8764b8','#ca5010','#498205'];
const pages=[]; // flat list in display order
const byId=new Map();
const $=s=>document.querySelector(s);
const esc=s=>String(s??'').replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
function store(k,v){try{if(v===undefined)return localStorage.getItem(k);localStorage.setItem(k,v)}catch(e){return null}}

// ---------- index ----------
let si=0;
for(const nb of DATA.notebooks){
  nb.sections.forEach(sec=>{
    sec.color=COLORS[si++%COLORS.length];
    for(const p of sec.pages){
      p.nb=nb.name; p.sec=sec; p.lc=(p.title+'\n'+p.text).toLowerCase();
      pages.push(p); byId.set(p.id,p);
    }
  });
}
$('#stats').textContent=`${DATA.notebooks.length} notebook${DATA.notebooks.length==1?'':'s'} \u00b7 ${pages.length.toLocaleString()} pages`;

// ---------- tree ----------
function el(tag,cls,html){const e=document.createElement(tag);if(cls)e.className=cls;if(html!=null)e.innerHTML=html;return e}
function buildTree(){
  const tree=$('#tree'); tree.innerHTML='';
  for(const nb of DATA.notebooks){
    const n=el('div','nb open');
    const total=nb.sections.reduce((a,s)=>a+s.pages.length,0);
    n.append(el('div','row',`<span class="chev">\u25b6</span><span>${esc(nb.name)}</span><span class="count">${total}</span>`));
    const kids=el('div','kids'); n.append(kids);
    const groupNodes=new Map();
    for(const sec of nb.sections){
      let parent=kids, path='';
      for(const g of sec.groups){
        path+='/'+g;
        if(!groupNodes.has(path)){
          const gn=el('div','grp');
          gn.append(el('div','row',`<span class="chev">\u25b6</span><span>\u{1F4C1} ${esc(g)}</span>`));
          const gk=el('div','kids'); gn.append(gk); parent.append(gn); groupNodes.set(path,gk);
        }
        parent=groupNodes.get(path);
      }
      const s=el('div','sec'); sec.node=s;
      const badge=sec.mode!=='full'?'<span class="badge">text only</span>':'';
      s.append(el('div','row',`<span class="chev">\u25b6</span><span class="swatch" style="background:${sec.color}"></span><span>${esc(sec.name)}</span>${badge}<span class="count">${sec.pages.length}</span>`));
      const sk=el('div','kids');
      for(const p of sec.pages){
        const a=el('a','pg l'+(p.level||1));
        a.href='#p'+p.id; a.dataset.id=p.id;
        a.innerHTML=esc(p.title)+(p.created?`<span class="d">${esc(p.created.slice(0,10))}</span>`:'');
        a.title=p.title; p.link=a; sk.append(a);
      }
      s.append(sk); parent.append(s);
    }
    tree.append(n);
  }
  tree.addEventListener('click',e=>{
    const row=e.target.closest('.row'); if(!row)return;
    row.parentElement.classList.toggle('open');
  });
}

// ---------- rendering ----------
function runsHtml(runs){
  return runs.map(r=>{
    let t=esc(r.t);
    if(r.b)t='<strong>'+t+'</strong>';
    if(r.i)t='<em>'+t+'</em>';
    if(r.u&&!r.href)t='<u>'+t+'</u>';
    if(r.s)t='<s>'+t+'</s>';
    if(r.href){const h=/^(https?:|mailto:|onenote:|file:|\\\\)/i.test(r.href)?r.href:(/^www\./i.test(r.href)?'https://'+r.href:r.href);t=`<a href="${esc(h)}" target="_blank" rel="noopener">${t}</a>`}
    return t;
  }).join('');
}
const WEB_IMG=/\.(png|jpe?g|gif|bmp|webp|svg|ico)$/i;
function blocksHtml(blocks){
  let out='', num=[];
  for(const b of blocks){
    const pad=b.depth?` style="margin-left:${b.depth*24}px"`:'';
    if(b.type==='p'){
      const st=(b.style||'').toLowerCase();
      let inner=runsHtml(b.runs);
      if(b.check)inner=`<span class="chk">${b.check==='done'?'\u2611':'\u2610'}</span> `+(b.check==='done'?`<span class="done">${inner}</span>`:inner);
      if(b.list){
        num.length=Math.max(num.length,b.depth+1);
        let m='\u2022';
        if(b.list==='num'){num[b.depth]=(num[b.depth]||0)+1;m=num[b.depth]+'.'}
        num.length=b.depth+1;
        out+=`<p class="li"${pad}><span class="m">${m}</span><span>${inner}</span></p>`;
        continue;
      }
      num.length=Math.min(num.length,b.depth);
      if(/^h[1-6]$/.test(st))out+=`<${st}${pad}>${inner}</${st}>`;
      else if(st==='code')out+=`<p${pad}><span class="code">${inner}</span></p>`;
      else if(st==='quote'||st==='cite')out+=`<p class="quote"${pad}>${inner}</p>`;
      else out+=`<p${pad}>${inner}</p>`;
    }else if(b.type==='table'){
      out+=`<table${pad}>`+b.rows.map(r=>'<tr>'+r.map(c=>'<td>'+blocksHtml(c)+'</td>').join('')+'</tr>').join('')+'</table>';
    }else if(b.type==='img'){
      if(b.src&&WEB_IMG.test(b.src)){
        out+=`<figure${pad}><img loading="lazy" src="${esc(b.src)}" alt="${esc(b.alt||b.ocr||b.name)}" title="${esc(b.ocr||'')}"></figure>`;
      }else{
        if(b.src)out+=`<a class="file"${pad} href="${esc(b.src)}" download>\u{1F4C4} ${esc(b.name)}</a>`;
        const t=b.ocr||b.alt;
        if(t)out+=`<div class="ocr"${pad}><span class="lbl">Text from ${esc(b.name||'printout')}</span>${esc(t)}</div>`;
        else if(!b.src)out+=`<p${pad}><i>(image not stored in the section)</i></p>`;
      }
    }else if(b.type==='file'){
      out+=b.href?`<a class="file"${pad} href="${esc(b.href)}" download="${esc(b.name)}">\u{1F4CE} ${esc(b.name)}</a>`:`<p${pad}>\u{1F4CE} ${esc(b.name)} <i>(attachment not stored in the section)</i></p>`;
    }
  }
  return out;
}
let current=null, hits=[], hitIdx=-1;
function show(id,opts={}){
  const p=byId.get(+id); if(!p)return;
  current=p;
  document.querySelectorAll('.pg.active').forEach(a=>a.classList.remove('active'));
  if(p.link){p.link.classList.add('active');let n=p.sec.node;while(n&&n.classList){if(n.classList.contains('sec')||n.classList.contains('grp')||n.classList.contains('nb'))n.classList.add('open');n=n.parentElement}
    if(!opts.fromTree)p.link.scrollIntoView({block:'nearest'})}
  const dates=[p.created&&'Created '+p.created,p.modified&&'Last changed '+p.modified].filter(Boolean).join('  \u00b7  ');
  $('#crumbs').textContent=[p.nb,...p.sec.groups,p.sec.name].join('  \u203a  ');
  $('#paper').innerHTML=`<h2 class="title">${esc(p.title)}</h2><div class="dates">${esc(dates)}</div>`+
    (p.sec.note?`<div class="warn">${esc(p.sec.note)}</div>`:'')+
    (p.orphan?`<div class="warn">This page isn't in the section's page list, so it may be an older or deleted copy of another page.</div>`:'')+
    `<div class="content">${blocksHtml(p.blocks)||'<p class="empty">(This page has no text \u2014 it may contain only drawings or ink.)</p>'}</div>`;
  const i=pages.indexOf(p); $('#prev').disabled=i<=0; $('#next').disabled=i>=pages.length-1;
  if(location.hash!=='#p'+p.id)history.replaceState(null,'','#p'+p.id);
  store('onv-last',p.id);
  highlight(opts.query ?? $('#q').value.trim());
  if(!opts.keepScroll)$('#main').scrollTop=0;
  $('#side').classList.remove('show');
}
function highlight(q){
  hits=[];hitIdx=-1;
  const showNav=v=>{$('#prevHit').hidden=$('#nextHit').hidden=!v};
  if(!q){showNav(false);return}
  const terms=q.toLowerCase().split(/\s+/).filter(Boolean).map(t=>t.replace(/[.*+?^${}()|[\]\\]/g,'\\$&'));
  if(!terms.length){showNav(false);return}
  const re=new RegExp('('+terms.join('|')+')','gi');
  const root=$('#paper');
  const walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT);
  const nodes=[];while(walker.nextNode())nodes.push(walker.currentNode);
  for(const n of nodes){
    if(!re.test(n.nodeValue)){re.lastIndex=0;continue}re.lastIndex=0;
    const frag=document.createDocumentFragment();let last=0;
    n.nodeValue.replace(re,(m,_g,off)=>{frag.append(n.nodeValue.slice(last,off));const mk=el('mark');mk.textContent=m;frag.append(mk);hits.push(mk);last=off+m.length;return m});
    frag.append(n.nodeValue.slice(last));n.replaceWith(frag);
  }
  showNav(hits.length>0);
  if(hits.length)jumpHit(0);
}
function jumpHit(d){
  if(!hits.length)return;
  if(hitIdx>=0)hits[hitIdx].classList.remove('cur');
  hitIdx=(hitIdx+d+hits.length)%hits.length;
  hits[hitIdx].classList.add('cur');
  hits[hitIdx].scrollIntoView({block:'center'});
}
$('#nextHit').onclick=()=>jumpHit(1);
$('#prevHit').onclick=()=>jumpHit(-1);

// ---------- search ----------
let searchTimer=null;
function search(q){
  const res=$('#results'), tree=$('#tree'), meta=$('#qmeta');
  if(!q){res.hidden=true;tree.hidden=false;meta.textContent='';if(current)highlight('');return}
  const terms=q.toLowerCase().split(/\s+/).filter(Boolean);
  const found=[];
  for(const p of pages){
    if(terms.every(t=>p.lc.includes(t))){
      let score=0;for(const t of terms){if(p.title.toLowerCase().includes(t))score+=5;let i=-1,c=0;while((i=p.lc.indexOf(t,i+1))!==-1&&c<20)c++;score+=c}
      found.push([score,p]);
    }
  }
  found.sort((a,b)=>b[0]-a[0]);
  meta.textContent=found.length?`${found.length.toLocaleString()} page${found.length==1?'':'s'} found`:'No matches';
  const re=new RegExp('('+terms.map(t=>t.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')).join('|')+')','gi');
  const parts=found.slice(0,300).map(([,p])=>{
    const i=p.text.toLowerCase().indexOf(terms[0]);
    let snip=i<0?p.text.slice(0,140):(i>60?'\u2026':'')+p.text.slice(Math.max(0,i-60),i+100);
    snip=esc(snip.replace(/\s+/g,' ')).replace(re,'<mark>$1</mark>');
    return `<div class="res" data-id="${p.id}"><b>${esc(p.title).replace(re,'<mark>$1</mark>')}</b><span class="where">${esc(p.nb)} \u203a ${esc(p.sec.name)}${p.created?' \u00b7 '+esc(p.created.slice(0,10)):''}</span><div class="snip">${snip}</div></div>`;
  });
  if(found.length>300)parts.push(`<div class="meta" style="padding:8px">Showing the top 300 \u2014 add more words to narrow it down.</div>`);
  res.innerHTML=parts.join('');res.hidden=false;tree.hidden=true;
}
$('#q').addEventListener('input',e=>{clearTimeout(searchTimer);searchTimer=setTimeout(()=>search(e.target.value.trim()),120)});
$('#q').addEventListener('keydown',e=>{if(e.key==='Escape'){e.target.value='';search('')}if(e.key==='Enter'){const f=$('#results .res');if(f)show(f.dataset.id)}});
$('#results').addEventListener('click',e=>{const r=e.target.closest('.res');if(!r)return;document.querySelectorAll('.res.active').forEach(x=>x.classList.remove('active'));r.classList.add('active');show(r.dataset.id)});
$('#tree').addEventListener('click',e=>{const a=e.target.closest('.pg');if(!a)return;e.preventDefault();show(a.dataset.id,{fromTree:true})});

// ---------- actions ----------
function step(d){if(!current)return show(pages[0]?.id);const i=pages.indexOf(current)+d;if(pages[i])show(pages[i].id)}
$('#prev').onclick=()=>step(-1);$('#next').onclick=()=>step(1);
$('#menu').onclick=()=>$('#side').classList.toggle('show');
function toast(t){const e=$('#toast');e.textContent=t;e.classList.add('on');setTimeout(()=>e.classList.remove('on'),1800)}
$('#copy').onclick=()=>{
  if(!current)return;
  document.querySelectorAll('mark').forEach(m=>m.replaceWith(m.textContent));
  const node=$('#paper .content'); if(!node)return;
  const title=$('#paper h2.title');
  const range=document.createRange();range.setStartBefore(title);range.setEndAfter(node);
  const sel=getSelection();sel.removeAllRanges();sel.addRange(range);
  let ok=false;try{ok=document.execCommand('copy')}catch(e){}
  sel.removeAllRanges();
  toast(ok?'Copied \u2014 paste it into a page in OneNote web':'Select the text and press Ctrl+C to copy');
};
document.addEventListener('keydown',e=>{
  if(e.key==='/'&&document.activeElement!==$('#q')){e.preventDefault();$('#q').focus();$('#q').select()}
  if(e.altKey&&e.key==='ArrowDown'){e.preventDefault();step(1)}
  if(e.altKey&&e.key==='ArrowUp'){e.preventDefault();step(-1)}
});
$('#paper').addEventListener('click',e=>{const img=e.target.closest('figure img');if(!img)return;$('#lb img').src=img.src;$('#lb').classList.add('on')});
$('#lb').onclick=()=>$('#lb').classList.remove('on');
window.addEventListener('hashchange',()=>{const m=location.hash.match(/^#p(\d+)/);if(m&&(!current||current.id!=+m[1]))show(m[1])});

buildTree();
const start=(location.hash.match(/^#p(\d+)/)||[])[1]||store('onv-last');
if(start&&byId.has(+start))show(start);else if(pages.length)show(pages[0].id);
</script>
</body>
</html>
'@

# ---------------------------------------------------------------- helpers
$monthNames = @{
    'jan'=1;'january'=1;'enero'=1;'ene'=1
    'feb'=2;'february'=2;'febrero'=2
    'mar'=3;'march'=3;'marzo'=3
    'apr'=4;'april'=4;'abril'=4;'abr'=4
    'may'=5;'mayo'=5
    'jun'=6;'june'=6;'junio'=6
    'jul'=7;'july'=7;'julio'=7
    'aug'=8;'august'=8;'agosto'=8;'ago'=8
    'sep'=9;'sept'=9;'september'=9;'septiembre'=9;'setiembre'=9
    'oct'=10;'october'=10;'octubre'=10
    'nov'=11;'november'=11;'noviembre'=11
    'dec'=12;'december'=12;'diciembre'=12;'dic'=12
}
function Get-SectionSortKey([string]$name) {
    # Sections named like "Oct 2026" / "Agosto 2022" sort by date (newest first), others alphabetically after.
    if ($name -match '^\s*([A-Za-z]+)\.?\s+(\d{4})\s*$') {
        $m = $monthNames[$Matches[1].ToLower()]
        if ($m) { return '0_' + (9999 - [int]$Matches[2]).ToString('0000') + '_' + (12 - $m).ToString('00') }
    }
    return '1_' + $name.ToLower()
}

# ---------------------------------------------------------------- find sections
$outFull = [IO.Path]::GetFullPath($OutDir).TrimEnd('\', '/')
$files = Get-ChildItem -LiteralPath $Root -Recurse -File -Filter *.one -ErrorAction SilentlyContinue | Where-Object {
    $_.Extension -eq '.one' -and
    -not $_.FullName.StartsWith($outFull + '\', [StringComparison]::OrdinalIgnoreCase) -and
    $_.FullName -notmatch '\\onefiles\\' -and
    ($IncludeDeleted -or ($_.FullName -notmatch '\\OneNote_RecycleBin\\' -and $_.Name -notlike 'OneNote_DeletedPages*'))
}

$rootName = Split-Path -Leaf $Root
$sections = foreach ($f in $files) {
    $rel = $f.DirectoryName.Substring($Root.Length).TrimStart('\', '/')
    $parts = @(if ($rel) { $rel -split '[\\/]' })
    if ($parts.Count -gt 0) { $nb = $parts[0]; $groups = ($parts | Select-Object -Skip 1) -join '\' }
    else { $nb = $rootName; $groups = '' }
    [pscustomobject]@{ Notebook = $nb; Groups = $groups; Name = $f.BaseName; Path = $f.FullName; Size = $f.Length
                       Key = (Get-SectionSortKey $f.BaseName) }
}
$sections = @($sections | Sort-Object Notebook, Groups, Key)

if ($sections.Count -eq 0) {
    Write-Host "No .one files found under $Root" -ForegroundColor Yellow
    Write-Host "Put this script in the folder that contains your notebook folders, or pass -Root ""C:\path\to\folder""."
    return
}

# ---------------------------------------------------------------- build
if (Test-Path -LiteralPath $OutDir) { Remove-Item -LiteralPath $OutDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

Write-Host ""
Write-Host "Reading $($sections.Count) sections from $Root ..." -ForegroundColor Cyan
[OneNoteReader]::Begin($OutDir)
$report = New-Object System.Collections.Generic.List[string]
$i = 0; $partial = 0
$sw = [Diagnostics.Stopwatch]::StartNew()
foreach ($s in $sections) {
    $i++
    $label = (@($s.Notebook) + @(if ($s.Groups) { $s.Groups }) + @($s.Name)) -join ' / '
    Write-Host ("  [{0}/{1}] {2} ({3:N1} MB) ... " -f $i, $sections.Count, $label, ($s.Size / 1MB)) -NoNewline
    $r = [OneNoteReader]::AddSection($s.Notebook, $s.Groups, $s.Name, $s.Path)
    $st, $n, $err = $r.Split('|', 3)
    $color = if ($st -eq 'ok') { 'Green' } else { 'Yellow' }
    if ($st -ne 'ok') { $partial++ }
    Write-Host "$n page(s), $st" -ForegroundColor $color
    $report.Add(('{0,-10} {1,5} pages  {2}{3}' -f $st, $n, $s.Path, $(if ($err) { "   [$err]" } else { '' })))
}

$json = [OneNoteReader]::Finish((Get-Date -Format 'yyyy-MM-dd HH:mm'))
$html = $template.Replace('/*__DATA__*/null', $json)
$index = Join-Path $OutDir 'index.html'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($index, $html, $utf8)
[IO.File]::WriteAllText((Join-Path $OutDir 'report.txt'), ("OneNote Viewer report - " + (Get-Date) + "`r`n`r`n" + ($report -join "`r`n") + "`r`n"), $utf8)

Write-Host ""
Write-Host ("Done in {0:N0}s: {1} sections, {2} pages, {3} images/attachments." -f $sw.Elapsed.TotalSeconds, $sections.Count, [OneNoteReader]::PageCount, [OneNoteReader]::AssetCount) -ForegroundColor Cyan
if ($partial -gt 0) { Write-Host "$partial section(s) could only be partly read - see report.txt" -ForegroundColor Yellow }
Write-Host "Viewer: $index"
if (-not $NoOpen) { Invoke-Item -LiteralPath $index }
