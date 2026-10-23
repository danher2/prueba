import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.awt.Desktop;
import java.awt.GraphicsEnvironment;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.BindException;
import java.net.HttpURLConnection;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.Proxy;
import java.net.URI;
import java.net.URL;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.nio.file.DirectoryStream;
import java.nio.file.FileVisitResult;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.SimpleFileVisitor;
import java.nio.file.StandardCopyOption;
import java.nio.file.attribute.BasicFileAttributes;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.Date;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * My Notes - a small OneNote-style notes app.
 *
 * Runs a private web server on this computer only (127.0.0.1) and opens the
 * notes in your browser. Notebooks and sections are folders; every page is a
 * normal .html file you can open even without this app:
 *
 *   MyNotes\Daily\Oct 2026\20261022-140512-3f9a.html
 *   MyNotes\Daily\Oct 2026\_assets\   (images and attached files)
 *
 * Works with Java 8 or newer. No internet access is needed or used.
 */
public class NotesApp {
    static final Charset UTF8 = StandardCharsets.UTF_8;
    static final String VERSION = "1.0";
    static final SecureRandom RNG = new SecureRandom();

    static volatile Path root;
    static String token;
    static int port;
    static HttpServer server;
    static Path lockFile;
    static String uiCache;

    // ------------------------------------------------------------------ startup
    public static void main(String[] args) throws Exception {
        boolean noBrowser = false;
        String rootArg = null;
        for (String a : args) {
            if (a.equals("--no-browser")) noBrowser = true;
            else rootArg = a;
        }
        root = chooseRoot(rootArg);
        Files.createDirectories(root);

        // One running copy per computer: if it's already running, just open it.
        lockFile = Paths.get(System.getProperty("java.io.tmpdir"), "mynotes-" + System.getProperty("user.name", "user") + ".lock");
        if (Files.exists(lockFile)) {
            try {
                String[] pt = new String(Files.readAllBytes(lockFile), UTF8).trim().split("\\s+");
                int p = Integer.parseInt(pt[0]);
                String t = pt[1];
                HttpURLConnection c = (HttpURLConnection) new URL("http://127.0.0.1:" + p + "/api/ping?t=" + t).openConnection(Proxy.NO_PROXY);
                c.setConnectTimeout(1500);
                c.setReadTimeout(1500);
                if (c.getResponseCode() == 200) {
                    String url = "http://127.0.0.1:" + p + "/?t=" + t;
                    System.out.println("My Notes is already running: " + url);
                    if (!noBrowser) openBrowser(url);
                    return;
                }
            } catch (Exception ignored) {
            }
        }

        token = hex(16);
        for (int p = 8765; p < 8800 && server == null; p++) {
            try {
                server = HttpServer.create(new InetSocketAddress(InetAddress.getLoopbackAddress(), p), 0);
                port = p;
            } catch (BindException e) {
                // try next port
            }
        }
        if (server == null) {
            server = HttpServer.create(new InetSocketAddress(InetAddress.getLoopbackAddress(), 0), 0);
            port = server.getAddress().getPort();
        }
        server.createContext("/", new com.sun.net.httpserver.HttpHandler() {
            public void handle(HttpExchange ex) throws IOException { NotesApp.handle(ex); }
        });
        server.setExecutor(null); // one request at a time: simple and safe for file writes
        server.start();
        Files.write(lockFile, (port + " " + token).getBytes(UTF8));
        Runtime.getRuntime().addShutdownHook(new Thread(new Runnable() {
            public void run() {
                try { Files.deleteIfExists(lockFile); } catch (IOException ignored) { }
            }
        }));

        String url = "http://127.0.0.1:" + port + "/?t=" + token;
        System.out.println("My Notes " + VERSION + " is running.");
        System.out.println("Open: " + url);
        System.out.println("Notes folder: " + root);
        System.out.println("Use Quit in the app's menu (or close this window) to stop it.");
        if (!noBrowser) openBrowser(url);
    }

    static Path configFile() {
        return Paths.get(System.getProperty("user.home"), ".mynotes", "config.properties");
    }

    /** Notes folder: command line > saved setting > OneDrive (work, then personal) > Documents. */
    static Path chooseRoot(String arg) {
        if (arg != null) return Paths.get(arg).toAbsolutePath().normalize();
        try {
            Path cf = configFile();
            if (Files.exists(cf)) {
                Properties p = new Properties();
                InputStream in = Files.newInputStream(cf);
                try { p.load(in); } finally { in.close(); }
                String r = p.getProperty("root");
                if (r != null && r.trim().length() > 0) return Paths.get(r.trim()).toAbsolutePath().normalize();
            }
        } catch (Exception ignored) {
        }
        Path od = oneDriveFolder();
        if (od != null) return od.resolve("MyNotes");
        return Paths.get(System.getProperty("user.home"), "Documents", "MyNotes");
    }

    static Path oneDriveFolder() {
        for (String env : new String[] { "OneDriveCommercial", "OneDrive" }) {
            String v = System.getenv(env);
            if (v != null && v.length() > 0 && Files.isDirectory(Paths.get(v))) return Paths.get(v);
        }
        return null;
    }

    static void saveRootSetting(Path r) throws IOException {
        Path cf = configFile();
        Files.createDirectories(cf.getParent());
        Properties p = new Properties();
        p.setProperty("root", r.toString());
        OutputStream out = Files.newOutputStream(cf);
        try { p.store(out, "My Notes settings"); } finally { out.close(); }
    }

    // ------------------------------------------------------------------ http
    static class ApiError extends RuntimeException {
        ApiError(String m) { super(m); }
    }

    static void handle(HttpExchange ex) throws IOException {
        try {
            String host = ex.getRequestHeaders().getFirst("Host");
            if (host == null || !(host.equals("127.0.0.1:" + port) || host.equals("localhost:" + port))) {
                send(ex, 403, "text/plain", "Forbidden".getBytes(UTF8));
                return;
            }
            String path = ex.getRequestURI().getRawPath();
            Map<String, String> q = query(ex.getRequestURI().getRawQuery());
            if (path.equals("/") || path.equals("/index.html")) {
                send(ex, 200, "text/html; charset=utf-8", ui().getBytes(UTF8));
                return;
            }
            if (path.startsWith("/files/")) {
                serveFile(ex, path);
                return;
            }
            if (path.startsWith("/api/")) {
                String t = ex.getRequestHeaders().getFirst("X-Token");
                if (t == null) t = q.get("t");
                if (t == null || !MessageDigest.isEqual(t.getBytes(UTF8), token.getBytes(UTF8))) {
                    sendJson(ex, 401, err("This tab is from an older session. Start My Notes again from its launcher."));
                    return;
                }
                Object res = api(ex, path.substring(5), q);
                sendJson(ex, 200, res);
                return;
            }
            send(ex, 404, "text/plain", "Not found".getBytes(UTF8));
        } catch (ApiError e) {
            sendJson(ex, 400, err(e.getMessage()));
        } catch (Exception e) {
            e.printStackTrace();
            try { sendJson(ex, 500, err("Something went wrong: " + e)); } catch (Exception ignored) { }
        } finally {
            ex.close();
        }
    }

    static Map<String, Object> err(String m) {
        Map<String, Object> r = new LinkedHashMap<String, Object>();
        r.put("error", m);
        return r;
    }

    static Map<String, Object> ok() {
        Map<String, Object> r = new LinkedHashMap<String, Object>();
        r.put("ok", Boolean.TRUE);
        return r;
    }

    static void send(HttpExchange ex, int code, String type, byte[] body) throws IOException {
        ex.getResponseHeaders().set("Content-Type", type);
        ex.getResponseHeaders().set("Cache-Control", "no-store");
        ex.getResponseHeaders().set("X-Content-Type-Options", "nosniff");
        ex.sendResponseHeaders(code, body.length == 0 ? -1 : body.length);
        if (body.length > 0) {
            OutputStream os = ex.getResponseBody();
            os.write(body);
            os.close();
        }
    }

    static void sendJson(HttpExchange ex, int code, Object o) throws IOException {
        send(ex, code, "application/json; charset=utf-8", toJson(o).getBytes(UTF8));
    }

    static Map<String, String> query(String raw) {
        Map<String, String> m = new HashMap<String, String>();
        if (raw == null) return m;
        for (String part : raw.split("&")) {
            int i = part.indexOf('=');
            if (i < 0) m.put(pct(part), "");
            else m.put(pct(part.substring(0, i)), pct(part.substring(i + 1).replace('+', ' ')));
        }
        return m;
    }

    /** Percent-decoding that leaves '+' alone. */
    static String pct(String s) {
        ByteArrayOutputStream b = new ByteArrayOutputStream();
        for (int i = 0; i < s.length(); ) {
            char c = s.charAt(i);
            if (c == '%' && i + 2 < s.length() && isHex(s.charAt(i + 1)) && isHex(s.charAt(i + 2))) {
                b.write(Integer.parseInt(s.substring(i + 1, i + 3), 16));
                i += 3;
            } else {
                int cp = s.codePointAt(i);
                byte[] bs = new String(Character.toChars(cp)).getBytes(UTF8);
                b.write(bs, 0, bs.length);
                i += Character.charCount(cp);
            }
        }
        return new String(b.toByteArray(), UTF8);
    }

    static boolean isHex(char c) {
        return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
    }

    static byte[] readBody(HttpExchange ex, long limit) throws IOException {
        InputStream in = ex.getRequestBody();
        ByteArrayOutputStream b = new ByteArrayOutputStream();
        byte[] buf = new byte[65536];
        int n;
        long total = 0;
        while ((n = in.read(buf)) > 0) {
            total += n;
            if (total > limit) throw new ApiError("That file is too large (limit " + (limit / (1024 * 1024)) + " MB).");
            b.write(buf, 0, n);
        }
        return b.toByteArray();
    }

    @SuppressWarnings("unchecked")
    static Map<String, Object> jsonBody(HttpExchange ex) throws IOException {
        String s = new String(readBody(ex, 50L * 1024 * 1024), UTF8);
        Object o = new JsonParser(s).parse();
        if (!(o instanceof Map)) throw new ApiError("Bad request");
        return (Map<String, Object>) o;
    }

    static String ui() throws IOException {
        if (uiCache != null) return uiCache;
        InputStream in = NotesApp.class.getResourceAsStream("/notes-ui.html");
        byte[] b = null;
        if (in != null) {
            try { b = readAll(in); } finally { in.close(); }
        } else {
            for (Path p : new Path[] { Paths.get("notes-ui.html"), Paths.get("src", "notes-ui.html") }) {
                if (Files.exists(p)) { b = Files.readAllBytes(p); break; }
            }
        }
        if (b == null) throw new IOException("notes-ui.html is missing next to the app");
        uiCache = new String(b, UTF8);
        return uiCache;
    }

    static byte[] readAll(InputStream in) throws IOException {
        ByteArrayOutputStream b = new ByteArrayOutputStream();
        byte[] buf = new byte[65536];
        int n;
        while ((n = in.read(buf)) > 0) b.write(buf, 0, n);
        return b.toByteArray();
    }

    static void serveFile(HttpExchange ex, String rawPath) throws IOException {
        Path f = filesPathToFile(rawPath);
        if (f == null || !Files.isRegularFile(f)) {
            send(ex, 404, "text/plain", "Not found".getBytes(UTF8));
            return;
        }
        String type = contentType(f.getFileName().toString());
        byte[] body = Files.readAllBytes(f);
        ex.getResponseHeaders().set("Content-Security-Policy", "sandbox");
        send(ex, 200, type, body);
    }

    /** /files/<notebook>/<section>/_assets/<file>  ->  file inside the notes folder (or null). */
    static Path filesPathToFile(String rawPath) {
        String[] segs = rawPath.substring("/files/".length()).split("/");
        if (segs.length != 4) return null;
        try {
            String nb = pct(segs[0]), sec = pct(segs[1]), as = pct(segs[2]), fn = pct(segs[3]);
            if (!as.equals("_assets") || !safeSegment(nb) || !safeSegment(sec) || !safeSegment(fn)) return null;
            Path f = root.resolve(nb).resolve(sec).resolve("_assets").resolve(fn).normalize();
            if (!f.startsWith(root)) return null;
            return f;
        } catch (Exception e) {
            return null;
        }
    }

    static boolean safeSegment(String s) {
        return s.length() > 0 && !s.equals(".") && !s.equals("..") && s.indexOf('/') < 0 && s.indexOf('\\') < 0 && s.indexOf(':') < 0 && s.indexOf('\0') < 0;
    }

    static String contentType(String name) {
        String n = name.toLowerCase();
        if (n.endsWith(".png")) return "image/png";
        if (n.endsWith(".jpg") || n.endsWith(".jpeg")) return "image/jpeg";
        if (n.endsWith(".gif")) return "image/gif";
        if (n.endsWith(".bmp")) return "image/bmp";
        if (n.endsWith(".webp")) return "image/webp";
        if (n.endsWith(".svg")) return "image/svg+xml";
        if (n.endsWith(".ico")) return "image/x-icon";
        if (n.endsWith(".pdf")) return "application/pdf";
        if (n.endsWith(".txt") || n.endsWith(".log") || n.endsWith(".csv")) return "text/plain; charset=utf-8";
        return "application/octet-stream";
    }

    // ------------------------------------------------------------------ api
    static Object api(HttpExchange ex, String name, Map<String, String> q) throws Exception {
        if (name.equals("ping")) return ok();
        if (name.equals("info")) {
            Map<String, Object> r = new LinkedHashMap<String, Object>();
            r.put("root", root.toString());
            r.put("version", VERSION);
            Path od = oneDriveFolder();
            r.put("oneDrive", od == null ? null : od.toString());
            r.put("inOneDrive", od != null && root.startsWith(od));
            r.put("defaultImport", Paths.get(System.getProperty("user.home"), "Desktop", "OneNoteViewer").toString());
            r.put("suggestedRoot", od == null ? null : od.resolve("MyNotes").toString());
            return r;
        }
        if (name.equals("tree")) return tree();
        if (name.equals("page")) return readPageJson(q.get("nb"), q.get("sec"), q.get("id"));
        if (name.equals("search")) return search(q.get("q"));
        if (name.equals("find")) return find(q.get("id"));
        if (name.equals("upload")) return upload(ex, q.get("nb"), q.get("sec"), q.get("name"));

        if (!"POST".equals(ex.getRequestMethod())) throw new ApiError("Bad request");
        if (name.equals("quit")) {
            new Thread(new Runnable() {
                public void run() {
                    try { Thread.sleep(400); } catch (InterruptedException ignored) { }
                    server.stop(0);
                    System.exit(0);
                }
            }).start();
            return ok();
        }
        Map<String, Object> b = jsonBody(ex);
        if (name.equals("save")) return save(b);
        if (name.equals("create")) return create(b);
        if (name.equals("rename")) return rename(b);
        if (name.equals("delete")) return delete(b);
        if (name.equals("reorder")) return reorder(b);
        if (name.equals("movepage")) return movePage(b);
        if (name.equals("open")) return open(str(b, "target"));
        if (name.equals("openfolder")) return openPath(root);
        if (name.equals("setup")) return setup();
        if (name.equals("import")) return importViewer(str(b, "path"));
        if (name.equals("setroot")) return setRoot(str(b, "path"));
        throw new ApiError("Unknown action");
    }

    static String str(Map<String, Object> m, String k) {
        Object o = m.get(k);
        return o == null ? null : o.toString();
    }

    // ------------------------------------------------------------------ storage helpers
    static final Pattern ID = Pattern.compile("[0-9A-Za-z-]{1,64}");
    static final String[] RESERVED = { "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
            "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9" };

    static String cleanName(String s) {
        if (s == null) throw new ApiError("Please type a name.");
        s = s.replaceAll("[\\\\/:*?\"<>|\\x00-\\x1f]", "-").trim();
        while (s.startsWith(".") || s.startsWith("_")) s = s.substring(1).trim();
        while (s.endsWith(".")) s = s.substring(0, s.length() - 1).trim();
        if (s.length() > 80) s = s.substring(0, 80).trim();
        if (s.isEmpty()) throw new ApiError("Please type a different name.");
        for (String r : RESERVED) if (s.equalsIgnoreCase(r)) s = s + "-";
        return s;
    }

    static Path nbDir(String nb) {
        if (nb == null || !safeSegment(nb) || nb.startsWith(".") || nb.startsWith("_")) throw new ApiError("Unknown notebook");
        Path d = root.resolve(nb).normalize();
        if (!d.startsWith(root) || !Files.isDirectory(d)) throw new ApiError("The notebook \"" + nb + "\" was not found.");
        return d;
    }

    static Path secDir(String nb, String sec) {
        Path n = nbDir(nb);
        if (sec == null || !safeSegment(sec) || sec.startsWith(".") || sec.startsWith("_")) throw new ApiError("Unknown section");
        Path d = n.resolve(sec).normalize();
        if (!d.startsWith(n) || !Files.isDirectory(d)) throw new ApiError("The section \"" + sec + "\" was not found.");
        return d;
    }

    static Path pageFile(String nb, String sec, String id) {
        if (id == null || !ID.matcher(id).matches()) throw new ApiError("Unknown page");
        return secDir(nb, sec).resolve(id + ".html");
    }

    static List<String> childDirs(Path dir) throws IOException {
        List<String> r = new ArrayList<String>();
        DirectoryStream<Path> ds = Files.newDirectoryStream(dir);
        try {
            for (Path p : ds) {
                String n = p.getFileName().toString();
                if (Files.isDirectory(p) && !n.startsWith(".") && !n.startsWith("_")) r.add(n);
            }
        } finally { ds.close(); }
        Collections.sort(r, String.CASE_INSENSITIVE_ORDER);
        return r;
    }

    static List<String> pageIds(Path sec) throws IOException {
        List<String> ids = new ArrayList<String>();
        DirectoryStream<Path> ds = Files.newDirectoryStream(sec, "*.html");
        try {
            for (Path p : ds) {
                String n = p.getFileName().toString();
                String id = n.substring(0, n.length() - 5);
                if (ID.matcher(id).matches()) ids.add(id);
            }
        } finally { ds.close(); }
        Collections.sort(ids); // ids start with the creation time
        return ids;
    }

    static List<String> readOrder(Path dir) {
        List<String> r = new ArrayList<String>();
        Path f = dir.resolve(".order");
        if (!Files.exists(f)) return r;
        try {
            for (String line : new String(Files.readAllBytes(f), UTF8).split("\r?\n")) if (line.trim().length() > 0) r.add(line.trim());
        } catch (IOException ignored) { }
        return r;
    }

    static void writeOrder(Path dir, List<String> names) throws IOException {
        StringBuilder sb = new StringBuilder();
        for (String n : names) sb.append(n).append('\n');
        writeAtomic(dir.resolve(".order"), sb.toString().getBytes(UTF8));
    }

    /** Items in the saved order, then any others (new or added outside the app). */
    static List<String> ordered(Path dir, List<String> present) {
        LinkedHashSet<String> out = new LinkedHashSet<String>();
        for (String n : readOrder(dir)) if (present.contains(n)) out.add(n);
        out.addAll(present);
        return new ArrayList<String>(out);
    }

    static void addToOrder(Path dir, String name, int index) throws IOException {
        List<String> present = new ArrayList<String>(readOrder(dir));
        present.remove(name);
        if (index < 0 || index > present.size()) present.add(name);
        else present.add(index, name);
        writeOrder(dir, present);
    }

    static void removeFromOrder(Path dir, String name) throws IOException {
        List<String> o = readOrder(dir);
        if (o.remove(name)) writeOrder(dir, o);
    }

    static void writeAtomic(Path f, byte[] data) throws IOException {
        Path tmp = f.resolveSibling(".tmp-" + f.getFileName().toString() + "-" + hex(4));
        Files.write(tmp, data);
        try {
            Files.move(tmp, f, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
        } catch (IOException e) {
            Files.move(tmp, f, StandardCopyOption.REPLACE_EXISTING);
        }
    }

    static String now() {
        return new SimpleDateFormat("yyyy-MM-dd HH:mm").format(new Date());
    }

    static String newId(String created) {
        String base;
        try {
            Date d = new SimpleDateFormat("yyyy-MM-dd HH:mm").parse(created);
            base = new SimpleDateFormat("yyyyMMdd-HHmm").format(d);
        } catch (Exception e) {
            base = new SimpleDateFormat("yyyyMMdd-HHmm").format(new Date());
        }
        return base + "-" + hex(3);
    }

    // ------------------------------------------------------------------ pages
    static class Meta {
        long mtime;
        String title, created, modified, text;
    }

    static final Map<Path, Meta> cache = new HashMap<Path, Meta>();

    static Meta meta(Path f) throws IOException {
        long mt = Files.getLastModifiedTime(f).toMillis();
        Meta m = cache.get(f);
        if (m != null && m.mtime == mt) return m;
        String s = new String(Files.readAllBytes(f), UTF8);
        m = new Meta();
        m.mtime = mt;
        m.title = unesc(between(s, "<title>", "</title>"));
        m.created = metaValue(s, "created");
        m.modified = metaValue(s, "modified");
        m.text = plainText(content(s));
        cache.put(f, m);
        return m;
    }

    static String between(String s, String a, String b) {
        int i = s.indexOf(a);
        if (i < 0) return "";
        int j = s.indexOf(b, i + a.length());
        if (j < 0) return "";
        return s.substring(i + a.length(), j);
    }

    static String metaValue(String s, String name) {
        Matcher m = Pattern.compile("<meta name=\"" + name + "\" content=\"([^\"]*)\"").matcher(s);
        return m.find() ? unesc(m.group(1)) : "";
    }

    static String content(String s) {
        int i = s.indexOf("<!--content-->");
        int j = s.lastIndexOf("<!--/content-->");
        if (i >= 0 && j > i) return s.substring(i + "<!--content-->".length(), j).trim();
        int bi = s.indexOf("<body");
        if (bi >= 0) {
            int bs = s.indexOf('>', bi);
            int be = s.lastIndexOf("</body>");
            if (bs > 0 && be > bs) return s.substring(bs + 1, be);
        }
        return s;
    }

    static String plainText(String html) {
        String t = html.replaceAll("(?i)<(br|/p|/div|/li|/tr|/h[1-6]|/blockquote|/pre)[^>]*>", "\n")
                .replaceAll("(?i)</t[dh]>", " ")
                .replaceAll("<[^>]*>", "");
        return unesc(t).replace('\u00A0', ' ').replaceAll("[ \\t]+", " ").replaceAll("\\n\\s*\\n+", "\n").trim();
    }

    static String esc(String s) {
        if (s == null) return "";
        return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;");
    }

    static String unesc(String s) {
        if (s == null || s.indexOf('&') < 0) return s == null ? "" : s;
        Matcher m = Pattern.compile("&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);").matcher(s);
        StringBuffer sb = new StringBuffer();
        while (m.find()) {
            String e = m.group(1), r;
            try {
                if (e.startsWith("#x")) r = new String(Character.toChars(Integer.parseInt(e.substring(2), 16)));
                else if (e.startsWith("#")) r = new String(Character.toChars(Integer.parseInt(e.substring(1))));
                else if (e.equals("amp")) r = "&";
                else if (e.equals("lt")) r = "<";
                else if (e.equals("gt")) r = ">";
                else if (e.equals("quot")) r = "\"";
                else if (e.equals("apos")) r = "'";
                else if (e.equals("nbsp")) r = "\u00A0";
                else r = m.group(0);
            } catch (Exception x) {
                r = m.group(0);
            }
            m.appendReplacement(sb, Matcher.quoteReplacement(r));
        }
        m.appendTail(sb);
        return sb.toString();
    }

    static void writePage(Path f, String title, String html, String created, String modified) throws IOException {
        html = (html == null ? "" : html).replaceAll("<!--[\\s\\S]*?-->", "");
        html = html.replaceAll("(?is)<script[\\s\\S]*?</script>", "");
        String shownDate = created;
        String s = "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\">\n"
                + "<title>" + esc(title) + "</title>\n"
                + "<meta name=\"created\" content=\"" + esc(created) + "\">\n"
                + "<meta name=\"modified\" content=\"" + esc(modified) + "\">\n"
                + "<meta name=\"generator\" content=\"My Notes\">\n"
                + "<style>body{font-family:'Segoe UI',Calibri,Arial,sans-serif;max-width:900px;margin:32px auto;padding:0 20px;line-height:1.5;color:#222}"
                + "img{max-width:100%}table{border-collapse:collapse}td,th{border:1px solid #bbb;padding:4px 8px;vertical-align:top}"
                + ".page-date{color:#777;font-size:13px}.done{color:#888}.ocr{border:1px dashed #bbb;padding:6px 10px;white-space:pre-wrap}"
                + "pre{background:#f4f4f4;padding:8px;border-radius:4px}blockquote{border-left:3px solid #ccc;margin-left:0;padding-left:12px}</style>\n"
                + "</head><body>\n"
                + "<h1 class=\"page-title\">" + esc(title) + "</h1>\n"
                + "<p class=\"page-date\">" + esc(shownDate) + "</p>\n"
                + "<!--content-->\n" + html + "\n<!--/content-->\n"
                + "</body></html>\n";
        writeAtomic(f, s.getBytes(UTF8));
        cache.remove(f);
    }

    static Map<String, Object> pageEntry(String id, Meta m) {
        Map<String, Object> p = new LinkedHashMap<String, Object>();
        p.put("id", id);
        p.put("title", m.title);
        p.put("created", m.created);
        p.put("modified", m.modified);
        return p;
    }

    static Object tree() throws IOException {
        List<Object> nbs = new ArrayList<Object>();
        for (String nb : ordered(root, childDirs(root))) {
            Path nd = root.resolve(nb);
            Map<String, Object> n = new LinkedHashMap<String, Object>();
            n.put("name", nb);
            List<Object> secs = new ArrayList<Object>();
            for (String sec : ordered(nd, childDirs(nd))) {
                Path sd = nd.resolve(sec);
                Map<String, Object> s = new LinkedHashMap<String, Object>();
                s.put("name", sec);
                List<Object> pages = new ArrayList<Object>();
                for (String id : ordered(sd, pageIds(sd))) {
                    try { pages.add(pageEntry(id, meta(sd.resolve(id + ".html")))); } catch (IOException ignored) { }
                }
                s.put("pages", pages);
                secs.add(s);
            }
            n.put("sections", secs);
            nbs.add(n);
        }
        Map<String, Object> r = new LinkedHashMap<String, Object>();
        r.put("notebooks", nbs);
        r.put("root", root.toString());
        return r;
    }

    static Object readPageJson(String nb, String sec, String id) throws IOException {
        Path f = pageFile(nb, sec, id);
        if (!Files.exists(f)) throw new ApiError("That page no longer exists.");
        String s = new String(Files.readAllBytes(f), UTF8);
        Map<String, Object> r = new LinkedHashMap<String, Object>();
        r.put("nb", nb);
        r.put("sec", sec);
        r.put("id", id);
        r.put("title", unesc(between(s, "<title>", "</title>")));
        r.put("created", metaValue(s, "created"));
        r.put("modified", metaValue(s, "modified"));
        r.put("html", content(s));
        return r;
    }

    static Object save(Map<String, Object> b) throws IOException {
        Path f = pageFile(str(b, "nb"), str(b, "sec"), str(b, "id"));
        String created = now();
        if (Files.exists(f)) {
            Meta m = meta(f);
            if (m.created != null && m.created.length() > 0) created = m.created;
        } else {
            addToOrder(f.getParent(), str(b, "id"), -1);
        }
        String title = str(b, "title");
        if (title == null) title = "";
        title = title.replaceAll("[\\r\\n]+", " ").trim();
        String modified = now();
        writePage(f, title, str(b, "html"), created, modified);
        Map<String, Object> r = ok();
        r.put("modified", modified);
        return r;
    }

    static Object create(Map<String, Object> b) throws IOException {
        String type = str(b, "type");
        Map<String, Object> r = ok();
        if ("notebook".equals(type)) {
            String name = cleanName(str(b, "name"));
            Path d = root.resolve(name);
            if (Files.exists(d)) throw new ApiError("A notebook called \"" + name + "\" already exists.");
            Files.createDirectories(d);
            addToOrder(root, name, -1);
            String sec = "New Section 1";
            Files.createDirectories(d.resolve(sec));
            addToOrder(d, sec, -1);
            r.put("name", name);
            r.put("section", sec);
            r.put("id", newPage(d.resolve(sec), "", -1));
        } else if ("section".equals(type)) {
            Path n = nbDir(str(b, "nb"));
            String name = cleanName(str(b, "name"));
            Path d = n.resolve(name);
            if (Files.exists(d)) throw new ApiError("A section called \"" + name + "\" already exists in this notebook.");
            Files.createDirectories(d);
            addToOrder(n, name, -1);
            r.put("name", name);
            r.put("id", newPage(d, "", -1));
        } else if ("page".equals(type)) {
            Path s = secDir(str(b, "nb"), str(b, "sec"));
            Object idx = b.get("index");
            r.put("id", newPage(s, str(b, "title") == null ? "" : str(b, "title"), idx instanceof Number ? ((Number) idx).intValue() : -1));
        } else throw new ApiError("Unknown type");
        return r;
    }

    static String newPage(Path secDir, String title, int index) throws IOException {
        String created = now();
        String id = newId(created);
        writePage(secDir.resolve(id + ".html"), title, "<p><br></p>", created, created);
        List<String> order = ordered(secDir, pageIds(secDir));
        order.remove(id);
        if (index < 0 || index > order.size()) order.add(id);
        else order.add(index, id);
        writeOrder(secDir, order);
        return id;
    }

    static Object rename(Map<String, Object> b) throws IOException {
        String type = str(b, "type");
        String name = cleanName(str(b, "name"));
        Map<String, Object> r = ok();
        if ("notebook".equals(type)) {
            Path d = nbDir(str(b, "nb"));
            String old = d.getFileName().toString();
            if (!old.equals(name)) {
                Path t = root.resolve(name);
                if (Files.exists(t) && !old.equalsIgnoreCase(name)) throw new ApiError("A notebook called \"" + name + "\" already exists.");
                moveDir(d, t);
                replaceInOrder(root, old, name);
                cache.clear();
            }
        } else if ("section".equals(type)) {
            Path d = secDir(str(b, "nb"), str(b, "sec"));
            String old = d.getFileName().toString();
            if (!old.equals(name)) {
                Path t = d.getParent().resolve(name);
                if (Files.exists(t) && !old.equalsIgnoreCase(name)) throw new ApiError("A section called \"" + name + "\" already exists.");
                moveDir(d, t);
                replaceInOrder(d.getParent(), old, name);
                cache.clear();
            }
        } else throw new ApiError("Unknown type");
        r.put("name", name);
        return r;
    }

    static void moveDir(Path from, Path to) throws IOException {
        if (from.toString().equalsIgnoreCase(to.toString())) {
            // case-only rename on Windows needs a stop in between
            Path tmp = from.resolveSibling(".rename-" + hex(4));
            Files.move(from, tmp);
            Files.move(tmp, to);
        } else {
            Files.move(from, to);
        }
    }

    static void replaceInOrder(Path dir, String old, String name) throws IOException {
        List<String> o = readOrder(dir);
        int i = o.indexOf(old);
        if (i >= 0) o.set(i, name);
        else o.add(name);
        writeOrder(dir, o);
    }

    static Object delete(Map<String, Object> b) throws IOException {
        String type = str(b, "type");
        Path trash = root.resolve("_Trash");
        Files.createDirectories(trash);
        String stamp = new SimpleDateFormat("yyyyMMdd-HHmmss").format(new Date());
        if ("notebook".equals(type)) {
            Path d = nbDir(str(b, "nb"));
            Files.move(d, trash.resolve(stamp + " " + d.getFileName()));
            removeFromOrder(root, d.getFileName().toString());
        } else if ("section".equals(type)) {
            Path d = secDir(str(b, "nb"), str(b, "sec"));
            Files.move(d, trash.resolve(stamp + " " + d.getParent().getFileName() + " - " + d.getFileName()));
            removeFromOrder(d.getParent(), d.getFileName().toString());
        } else if ("page".equals(type)) {
            Path f = pageFile(str(b, "nb"), str(b, "sec"), str(b, "id"));
            if (Files.exists(f)) {
                Path t = trash.resolve(stamp + " pages").resolve(str(b, "nb") + " - " + str(b, "sec"));
                Files.createDirectories(t);
                copyAssets(f, t);
                Files.move(f, t.resolve(f.getFileName()), StandardCopyOption.REPLACE_EXISTING);
                removeFromOrder(f.getParent(), str(b, "id"));
            }
        } else throw new ApiError("Unknown type");
        cache.clear();
        return ok();
    }

    @SuppressWarnings("unchecked")
    static Object reorder(Map<String, Object> b) throws IOException {
        String type = str(b, "type");
        Object namesO = b.get("names");
        if (!(namesO instanceof List)) throw new ApiError("Bad request");
        List<String> names = new ArrayList<String>();
        for (Object o : (List<Object>) namesO) names.add(String.valueOf(o));
        Path dir;
        List<String> present;
        if ("notebooks".equals(type)) { dir = root; present = childDirs(root); }
        else if ("sections".equals(type)) { dir = nbDir(str(b, "nb")); present = childDirs(dir); }
        else if ("pages".equals(type)) { dir = secDir(str(b, "nb"), str(b, "sec")); present = pageIds(dir); }
        else throw new ApiError("Unknown type");
        LinkedHashSet<String> out = new LinkedHashSet<String>();
        for (String n : names) if (present.contains(n)) out.add(n);
        for (String n : ordered(dir, present)) out.add(n);
        writeOrder(dir, new ArrayList<String>(out));
        return ok();
    }

    static Object movePage(Map<String, Object> b) throws IOException {
        Path f = pageFile(str(b, "nb"), str(b, "sec"), str(b, "id"));
        if (!Files.exists(f)) throw new ApiError("That page no longer exists.");
        Path to = secDir(str(b, "toNb"), str(b, "toSec"));
        if (to.equals(f.getParent())) return ok();
        String id = str(b, "id");
        Path target = to.resolve(id + ".html");
        if (Files.exists(target)) { id = newId(meta(f).created); target = to.resolve(id + ".html"); }
        copyAssets(f, to);
        Files.move(f, target);
        removeFromOrder(f.getParent(), str(b, "id"));
        Object idx = b.get("index");
        List<String> order = ordered(to, pageIds(to));
        order.remove(id);
        int i = idx instanceof Number ? ((Number) idx).intValue() : -1;
        if (i < 0 || i > order.size()) order.add(id); else order.add(i, id);
        writeOrder(to, order);
        cache.clear();
        Map<String, Object> r = ok();
        r.put("id", id);
        return r;
    }

    static final Pattern ASSET_REF = Pattern.compile("_assets/([^\"'\\s<>)]+)");

    /** Copy the images/attachments a page uses into another section's _assets folder. */
    static void copyAssets(Path pageFile, Path toDir) throws IOException {
        String s = new String(Files.readAllBytes(pageFile), UTF8);
        Matcher m = ASSET_REF.matcher(s);
        Path fromAssets = pageFile.getParent().resolve("_assets");
        Path toAssets = toDir.resolve("_assets");
        while (m.find()) {
            String fn = pct(m.group(1));
            if (!safeSegment(fn)) continue;
            Path src = fromAssets.resolve(fn);
            if (!Files.isRegularFile(src)) continue;
            Files.createDirectories(toAssets);
            Path dst = toAssets.resolve(fn);
            if (!Files.exists(dst)) Files.copy(src, dst);
        }
    }

    /** Position of t in hay where t starts a word (not in the middle of a word), or -1. */
    static int findWord(String hay, String t, int from) {
        int i = hay.indexOf(t, from);
        while (i >= 0) {
            if (i == 0 || !Character.isLetterOrDigit(hay.charAt(i - 1))) return i;
            i = hay.indexOf(t, i + 1);
        }
        return -1;
    }

    static boolean hasAll(String hay, String[] terms) {
        for (String t : terms) if (findWord(hay, t, 0) < 0) return false;
        return true;
    }

    /**
     * Pages whose title, text or SECTION NAME contain every term (matched at the start of
     * words, so "arp" finds "ARP" and "arphardening" but not "carpeta"), best first,
     * plus the sections whose own name matches.
     */
    static Object search(String q) throws IOException {
        Map<String, Object> res = new LinkedHashMap<String, Object>();
        List<Object> secRes = new ArrayList<Object>();
        List<Object> pageRes = new ArrayList<Object>();
        res.put("sections", secRes);
        res.put("pages", pageRes);
        if (q == null || q.trim().isEmpty()) return res;
        String[] terms = parseTerms(q);
        if (terms.length == 0) return res;
        final List<Object[]> hits = new ArrayList<Object[]>();
        for (String nb : ordered(root, childDirs(root))) {
            Path nd = root.resolve(nb);
            for (String sec : ordered(nd, childDirs(nd))) {
                Path sd = nd.resolve(sec);
                String where = sec.toLowerCase().replaceAll("\\s+", " ");
                List<String> ids = pageIds(sd);
                if (hasAll(where, terms)) {
                    Map<String, Object> sr = new LinkedHashMap<String, Object>();
                    sr.put("nb", nb);
                    sr.put("sec", sec);
                    sr.put("pages", ids.size());
                    secRes.add(sr);
                }
                for (String id : ids) {
                    Meta m;
                    try { m = meta(sd.resolve(id + ".html")); } catch (IOException e) { continue; }
                    String title = m.title.toLowerCase().replaceAll("\\s+", " "), flat = m.text.replaceAll("\\s+", " "), text = flat.toLowerCase();
                    int score = 0;
                    boolean all = true;
                    int at = -1;
                    for (String t : terms) {
                        boolean inT = findWord(title, t, 0) >= 0, inS = findWord(where, t, 0) >= 0;
                        int first = findWord(text, t, 0);
                        if (!inT && !inS && first < 0) { all = false; break; }
                        if (inT) score += 10;
                        if (inS) score += 4;
                        if (first >= 0 && (at < 0 || first < at)) at = first;
                        int c = 0;
                        for (int i = first; i >= 0 && c < 20; i = findWord(text, t, i + 1)) c++;
                        score += c;
                    }
                    if (!all) continue;
                    Map<String, Object> p = pageEntry(id, m);
                    p.put("nb", nb);
                    p.put("sec", sec);
                    String snip = at < 0 ? flat.substring(0, Math.min(140, flat.length()))
                            : (at > 60 ? "\u2026" : "") + flat.substring(Math.max(0, at - 60), Math.min(flat.length(), at + 120));
                    p.put("snippet", snip.replace('\n', ' '));
                    hits.add(new Object[] { score, p });
                }
            }
        }
        Collections.sort(hits, new Comparator<Object[]>() {
            public int compare(Object[] a, Object[] b) { return ((Integer) b[0]) - ((Integer) a[0]); }
        });
        for (int i = 0; i < hits.size() && i < 300; i++) pageRes.add(hits.get(i)[1]);
        res.put("total", hits.size());
        return res;
    }

    /** Search words: "an exact phrase" or (an exact phrase) count as one term; other words are separate terms. */
    static final Pattern TERM = Pattern.compile("[\"\u201C\u201D]([^\"\u201C\u201D]*)[\"\u201C\u201D]?|\\(([^)]*)\\)?|(\\S+)");

    static String[] parseTerms(String q) {
        List<String> out = new ArrayList<String>();
        Matcher m = TERM.matcher(q.toLowerCase());
        while (m.find()) {
            String t = m.group(1) != null ? m.group(1) : m.group(2) != null ? m.group(2) : m.group(3);
            t = t.replaceAll("\\s+", " ").trim();
            if (!t.isEmpty()) out.add(t);
        }
        return out.toArray(new String[0]);
    }

    static Object find(String id) throws IOException {
        if (id == null || !ID.matcher(id).matches()) throw new ApiError("That link doesn't point to a page.");
        for (String nb : childDirs(root)) {
            for (String sec : childDirs(root.resolve(nb))) {
                if (Files.exists(root.resolve(nb).resolve(sec).resolve(id + ".html"))) {
                    Map<String, Object> r = ok();
                    r.put("nb", nb);
                    r.put("sec", sec);
                    r.put("id", id);
                    return r;
                }
            }
        }
        throw new ApiError("The linked page was not found (it may have been deleted).");
    }

    static Object upload(HttpExchange ex, String nb, String sec, String name) throws IOException {
        if (!"POST".equals(ex.getRequestMethod())) throw new ApiError("Bad request");
        Path s = secDir(nb, sec);
        byte[] data = readBody(ex, 300L * 1024 * 1024);
        String fn = assetName(data, name);
        Path assets = s.resolve("_assets");
        Files.createDirectories(assets);
        Path f = assets.resolve(fn);
        if (!Files.exists(f)) Files.write(f, data);
        Map<String, Object> r = ok();
        r.put("src", "_assets/" + fn);
        return r;
    }

    static String assetName(byte[] data, String name) {
        String base = name == null ? "file" : name;
        base = base.replace('\\', '/');
        base = base.substring(base.lastIndexOf('/') + 1);
        String ext = "";
        int dot = base.lastIndexOf('.');
        if (dot > 0 && base.length() - dot <= 10) { ext = base.substring(dot).toLowerCase(); base = base.substring(0, dot); }
        base = base.replaceAll("[^A-Za-z0-9._-]+", "_").replaceAll("^[._]+", "");
        ext = ext.replaceAll("[^a-z0-9.]", "");
        if (base.length() > 60) base = base.substring(0, 60);
        if (base.isEmpty()) base = "file";
        return sha(data).substring(0, 10) + "_" + base + ext;
    }

    // ------------------------------------------------------------------ opening links
    static Object open(String target) throws Exception {
        if (target == null || target.trim().isEmpty()) throw new ApiError("Nothing to open");
        target = target.trim();
        Path p = null;
        if (target.startsWith("/files/")) {
            p = filesPathToFile(target);
        } else if (target.regionMatches(true, 0, "file:", 0, 5)) {
            try {
                p = Paths.get(new URI(target.replace(" ", "%20")));
            } catch (Exception e) {
                String rest = pct(target.substring(5));
                while (rest.startsWith("///")) rest = rest.substring(1);
                if (rest.startsWith("//") && rest.length() > 3 && rest.charAt(3) == ':') rest = rest.substring(2);
                else if (rest.startsWith("/") && rest.length() > 2 && rest.charAt(2) == ':') rest = rest.substring(1);
                else if (rest.startsWith("//")) rest = "\\\\" + rest.substring(2);
                p = Paths.get(rest);
            }
        } else if (target.matches("^[A-Za-z]:[\\\\/].*") || target.startsWith("\\\\")) {
            p = Paths.get(target);
        } else {
            throw new ApiError("Can't open: " + target);
        }
        if (p == null || !Files.exists(p)) throw new ApiError("Not found: " + (p == null ? target : p.toString()));
        return openPath(p);
    }

    static Object openPath(Path p) throws Exception {
        File f = p.toFile();
        boolean done = false;
        if (!GraphicsEnvironment.isHeadless() && Desktop.isDesktopSupported() && Desktop.getDesktop().isSupported(Desktop.Action.OPEN)) {
            try { Desktop.getDesktop().open(f); done = true; } catch (Exception ignored) { }
        }
        if (!done) {
            String os = System.getProperty("os.name", "").toLowerCase();
            if (os.contains("win")) new ProcessBuilder("explorer.exe", f.getAbsolutePath()).start();
            else if (os.contains("mac")) new ProcessBuilder("open", f.getAbsolutePath()).start();
            else new ProcessBuilder("xdg-open", f.getAbsolutePath()).start();
        }
        return ok();
    }

    static void openBrowser(String url) {
        try {
            if (!GraphicsEnvironment.isHeadless() && Desktop.isDesktopSupported() && Desktop.getDesktop().isSupported(Desktop.Action.BROWSE)) {
                Desktop.getDesktop().browse(new URI(url));
                return;
            }
        } catch (Exception ignored) { }
        try {
            String os = System.getProperty("os.name", "").toLowerCase();
            if (os.contains("win")) new ProcessBuilder("rundll32", "url.dll,FileProtocolHandler", url).start();
            else if (os.contains("mac")) new ProcessBuilder("open", url).start();
            else new ProcessBuilder("xdg-open", url).start();
        } catch (Exception e) {
            System.out.println("Open this address in your browser: " + url);
        }
    }

    // ------------------------------------------------------------------ first run / settings
    static Object setup() throws IOException {
        for (String nb : new String[] { "Daily", "Stories", "Tutorials" }) {
            Path d = root.resolve(nb);
            if (Files.exists(d)) continue;
            Files.createDirectories(d);
            addToOrder(root, nb, -1);
            String sec = "General";
            Files.createDirectories(d.resolve(sec));
            addToOrder(d, sec, -1);
            newPage(d.resolve(sec), "", -1);
        }
        return ok();
    }

    static Object setRoot(String path) throws IOException {
        if (path == null || path.trim().isEmpty()) throw new ApiError("Please choose a folder.");
        Path t = Paths.get(path.trim()).toAbsolutePath().normalize();
        if (t.equals(root)) return ok();
        if (t.startsWith(root) || root.startsWith(t)) throw new ApiError("Please pick a folder that is not inside (or around) the current notes folder.");
        Files.createDirectories(t);
        boolean empty = childDirs(t).isEmpty();
        boolean hasNotes = !childDirs(root).isEmpty();
        Map<String, Object> r = ok();
        if (empty && hasNotes) {
            copyTree(root, t);
            r.put("copied", Boolean.TRUE);
        } else {
            r.put("copied", Boolean.FALSE);
        }
        saveRootSetting(t);
        root = t;
        cache.clear();
        r.put("root", t.toString());
        return r;
    }

    static void copyTree(final Path from, final Path to) throws IOException {
        Files.walkFileTree(from, new SimpleFileVisitor<Path>() {
            public FileVisitResult preVisitDirectory(Path dir, BasicFileAttributes a) throws IOException {
                Files.createDirectories(to.resolve(from.relativize(dir).toString()));
                return FileVisitResult.CONTINUE;
            }
            public FileVisitResult visitFile(Path file, BasicFileAttributes a) throws IOException {
                Path dst = to.resolve(from.relativize(file).toString());
                if (!Files.exists(dst)) Files.copy(file, dst);
                return FileVisitResult.CONTINUE;
            }
        });
    }

    // ------------------------------------------------------------------ import from OneNote Viewer
    static class ImportCtx {
        Path viewerDir, secDir;
        int assets;
    }

    @SuppressWarnings("unchecked")
    static Object importViewer(String path) throws IOException {
        if (path == null || path.trim().isEmpty()) throw new ApiError("Please type the folder of your OneNote Viewer.");
        Path p = Paths.get(path.trim().replaceAll("^\"|\"$", ""));
        Path index = Files.isDirectory(p) ? p.resolve("index.html") : p;
        if (!Files.isRegularFile(index)) throw new ApiError("Couldn't find index.html in " + p + ". Pick the OneNoteViewer folder (the one with index.html).");
        String html = new String(Files.readAllBytes(index), UTF8);
        int at = html.indexOf("const DATA = ");
        if (at < 0) throw new ApiError("That index.html wasn't made by the OneNote Viewer.");
        Object data;
        try {
            data = new JsonParser(html, at + "const DATA = ".length()).parse();
        } catch (RuntimeException e) {
            throw new ApiError("Couldn't read the viewer's data: " + e.getMessage());
        }
        if (!(data instanceof Map)) throw new ApiError("That viewer has no notes in it.");
        ImportCtx ctx = new ImportCtx();
        ctx.viewerDir = index.getParent();
        int nNb = 0, nSec = 0, nPages = 0;
        Object nbsO = ((Map<String, Object>) data).get("notebooks");
        if (!(nbsO instanceof List)) throw new ApiError("That viewer has no notes in it.");
        for (Object nbO : (List<Object>) nbsO) {
            Map<String, Object> nb = (Map<String, Object>) nbO;
            String nbName = cleanName(str(nb, "name"));
            Path nd = root.resolve(nbName);
            if (!Files.exists(nd)) { Files.createDirectories(nd); addToOrder(root, nbName, -1); }
            nNb++;
            for (Object secO : (List<Object>) nb.get("sections")) {
                Map<String, Object> sec = (Map<String, Object>) secO;
                StringBuilder sn = new StringBuilder();
                Object groups = sec.get("groups");
                if (groups instanceof List) for (Object g : (List<Object>) groups) sn.append(g).append(" - ");
                sn.append(str(sec, "name"));
                String secName = cleanName(sn.toString());
                String unique = secName;
                for (int k = 2; Files.exists(nd.resolve(unique)); k++) unique = secName + " (" + k + ")";
                Path sd = nd.resolve(unique);
                Files.createDirectories(sd);
                addToOrder(nd, unique, -1);
                nSec++;
                ctx.secDir = sd;
                List<String> order = new ArrayList<String>();
                boolean recovered = !"full".equals(str(sec, "mode"));
                for (Object pO : (List<Object>) sec.get("pages")) {
                    Map<String, Object> pg = (Map<String, Object>) pO;
                    String created = str(pg, "created");
                    String modified = str(pg, "modified");
                    if (created == null || created.isEmpty()) created = modified != null && !modified.isEmpty() ? modified : now();
                    if (modified == null || modified.isEmpty()) modified = created;
                    String title = fixSymbols(str(pg, "title"));
                    if (Boolean.TRUE.equals(pg.get("orphan"))) title = title + " (older copy)";
                    StringBuilder body = new StringBuilder();
                    if (recovered) body.append("<p><i>Imported as text only - this OneNote section couldn't be fully read.</i></p>\n");
                    renderBlocks((List<Object>) pg.get("blocks"), ctx, body);
                    String id = newId(created);
                    while (Files.exists(sd.resolve(id + ".html"))) id = newId(created);
                    writePage(sd.resolve(id + ".html"), title, body.toString(), created, modified);
                    order.add(id);
                    nPages++;
                }
                writeOrder(sd, order);
            }
        }
        Map<String, Object> r = ok();
        r.put("notebooks", nNb);
        r.put("sections", nSec);
        r.put("pages", nPages);
        r.put("assets", ctx.assets);
        return r;
    }

    static final Pattern WEB_IMG = Pattern.compile("(?i).*\\.(png|jpe?g|gif|bmp|webp|svg|ico)$");

    @SuppressWarnings("unchecked")
    static void renderBlocks(List<Object> blocks, ImportCtx ctx, StringBuilder sb) throws IOException {
        if (blocks == null) return;
        String openTag = null;
        int openDepth = -1;
        for (Object bo : blocks) {
            Map<String, Object> b = (Map<String, Object>) bo;
            String type = str(b, "type");
            int depth = b.get("depth") instanceof Number ? ((Number) b.get("depth")).intValue() : 0;
            String indent = depth > 0 ? " style=\"margin-left:" + (depth * 24) + "px\"" : "";
            if ("p".equals(type) && b.get("list") != null) {
                String tag = "num".equals(str(b, "list")) ? "ol" : "ul";
                if (!tag.equals(openTag) || depth != openDepth) {
                    if (openTag != null) sb.append("</").append(openTag).append(">\n");
                    sb.append('<').append(tag).append(indent).append('>');
                    openTag = tag;
                    openDepth = depth;
                }
                sb.append("<li").append("done".equals(str(b, "check")) ? " class=\"done\"" : "").append('>')
                        .append(inline(b)).append("</li>");
                continue;
            }
            if (openTag != null) { sb.append("</").append(openTag).append(">\n"); openTag = null; openDepth = -1; }
            if ("p".equals(type)) {
                String style = str(b, "style") == null ? "" : str(b, "style").toLowerCase();
                String in = inline(b);
                String cls = "done".equals(str(b, "check")) ? " class=\"done\"" : "";
                if (style.matches("h[1-6]")) sb.append('<').append(style).append(indent).append(cls).append('>').append(in).append("</").append(style).append(">\n");
                else if (style.equals("code")) sb.append("<p").append(indent).append("><code>").append(in).append("</code></p>\n");
                else if (style.equals("quote") || style.equals("cite")) sb.append("<blockquote").append(indent).append('>').append(in).append("</blockquote>\n");
                else sb.append("<p").append(indent).append(cls).append('>').append(in).append("</p>\n");
            } else if ("table".equals(type)) {
                sb.append("<table").append(indent).append("><tbody>");
                for (Object rowO : (List<Object>) b.get("rows")) {
                    sb.append("<tr>");
                    for (Object cellO : (List<Object>) rowO) {
                        sb.append("<td>");
                        StringBuilder cell = new StringBuilder();
                        renderBlocks((List<Object>) cellO, ctx, cell);
                        sb.append(cell.length() == 0 ? "<br>" : cell.toString());
                        sb.append("</td>");
                    }
                    sb.append("</tr>");
                }
                sb.append("</tbody></table>\n");
            } else if ("img".equals(type)) {
                String src = copyViewerAsset(str(b, "src"), ctx);
                String name = str(b, "name") == null ? "image" : str(b, "name");
                String alt = str(b, "alt") == null ? "" : str(b, "alt");
                String ocr = str(b, "ocr") == null ? "" : str(b, "ocr");
                if (src != null && WEB_IMG.matcher(src).matches()) {
                    sb.append("<p").append(indent).append("><img src=\"").append(esc(src)).append("\" alt=\"").append(esc(alt.isEmpty() ? ocr : alt)).append("\"></p>\n");
                } else {
                    if (src != null) sb.append("<p").append(indent).append("><a class=\"att\" href=\"").append(esc(src)).append("\">\uD83D\uDCC4 ").append(esc(name)).append("</a></p>\n");
                    String t = ocr.isEmpty() ? alt : ocr;
                    if (!t.isEmpty()) sb.append("<div class=\"ocr\"").append(indent).append('>').append(esc(fixSymbols(t)).replace("\n", "<br>")).append("</div>\n");
                }
            } else if ("file".equals(type)) {
                String src = copyViewerAsset(str(b, "href"), ctx);
                String name = str(b, "name") == null ? "attachment" : str(b, "name");
                if (src != null) sb.append("<p").append(indent).append("><a class=\"att\" href=\"").append(esc(src)).append("\">\uD83D\uDCCE ").append(esc(name)).append("</a></p>\n");
                else sb.append("<p").append(indent).append(">\uD83D\uDCCE ").append(esc(name)).append(" (file was not stored in OneNote)</p>\n");
            }
        }
        if (openTag != null) sb.append("</").append(openTag).append(">\n");
    }

    @SuppressWarnings("unchecked")
    static String inline(Map<String, Object> b) {
        StringBuilder sb = new StringBuilder();
        String check = str(b, "check");
        if (check != null) sb.append("<span class=\"todo\" contenteditable=\"false\" data-done=\"").append("done".equals(check) ? "1" : "0").append("\">")
                .append("done".equals(check) ? "\u2611" : "\u2610").append("</span>\u00A0");
        Object runsO = b.get("runs");
        if (!(runsO instanceof List)) return sb.toString();
        for (Object ro : (List<Object>) runsO) {
            Map<String, Object> r = (Map<String, Object>) ro;
            String t = esc(fixSymbols(str(r, "t"))).replace("\n", "<br>");
            if (Boolean.TRUE.equals(r.get("b"))) t = "<b>" + t + "</b>";
            if (Boolean.TRUE.equals(r.get("i"))) t = "<i>" + t + "</i>";
            if (Boolean.TRUE.equals(r.get("u")) && r.get("href") == null) t = "<u>" + t + "</u>";
            if (Boolean.TRUE.equals(r.get("s"))) t = "<s>" + t + "</s>";
            String href = linkHref(str(r, "href"));
            if (href != null) t = "<a href=\"" + esc(href) + "\">" + t + "</a>";
            sb.append(t);
        }
        return sb.toString();
    }

    static String linkHref(String h) {
        if (h == null) return null;
        h = h.trim();
        if (h.matches("(?i)^(https?:|mailto:|file:).*")) return h;
        if (h.matches("(?i)^www\\..*")) return "https://" + h;
        if (h.matches("^[A-Za-z]:[\\\\/].*")) return "file:///" + h.replace('\\', '/').replace(" ", "%20").replace("#", "%23");
        if (h.startsWith("\\\\")) return "file:" + h.replace('\\', '/').replace(" ", "%20").replace("#", "%23");
        return null; // onenote: links and others can't be followed outside OneNote
    }

    static String copyViewerAsset(String src, ImportCtx ctx) throws IOException {
        if (src == null || !src.startsWith("assets/")) return null;
        String fn = pct(src.substring("assets/".length()));
        if (!safeSegment(fn)) return null;
        Path from = ctx.viewerDir.resolve("assets").resolve(fn).normalize();
        if (!from.startsWith(ctx.viewerDir) || !Files.isRegularFile(from)) return null;
        String name = fn.replaceAll("[^A-Za-z0-9._-]+", "_");
        Path assets = ctx.secDir.resolve("_assets");
        Files.createDirectories(assets);
        Path to = assets.resolve(name);
        if (!Files.exists(to)) { Files.copy(from, to); ctx.assets++; }
        return "_assets/" + name;
    }

    /** OneNote bullets typed in Symbol/Wingdings fonts are private-use characters; show normal ones instead. */
    static String fixSymbols(String s) {
        if (s == null) return "";
        StringBuilder sb = null;
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c < '\uF000' || c > '\uF0FF') { if (sb != null) sb.append(c); continue; }
            if (sb == null) { sb = new StringBuilder(s.length()); sb.append(s, 0, i); }
            switch (c) {
                case '\uF0B7': case '\uF0A1': case '\uF06C': sb.append('\u2022'); break;
                case '\uF0A7': case '\uF06E': sb.append('\u25AA'); break;
                case '\uF0A8': case '\uF06F': case '\uF071': sb.append('\u25A1'); break;
                case '\uF076': sb.append('\u25C6'); break;
                case '\uF0D8': case '\uF0E0': case '\uF0E8': case '\uF0F0': sb.append('\u2192'); break;
                case '\uF0FC': sb.append('\u2713'); break;
                case '\uF0FB': case '\uF0FD': sb.append('\u2717'); break;
                case '\uF04A': sb.append('\u263A'); break;
                case '\uF0B0': sb.append('\u00B0'); break;
                default:
                    int a = c - 0xF000;
                    sb.append(a >= 0x20 && a < 0x7F ? (char) a : '\u2022');
            }
        }
        return sb == null ? s : sb.toString();
    }

    // ------------------------------------------------------------------ small utilities
    static String hex(int bytes) {
        byte[] b = new byte[bytes];
        RNG.nextBytes(b);
        StringBuilder sb = new StringBuilder();
        for (byte x : b) sb.append(String.format("%02x", x));
        return sb.toString();
    }

    static String sha(byte[] data) {
        try {
            byte[] h = MessageDigest.getInstance("SHA-1").digest(data);
            StringBuilder sb = new StringBuilder();
            for (byte x : h) sb.append(String.format("%02x", x));
            return sb.toString();
        } catch (Exception e) {
            return hex(10);
        }
    }

    @SuppressWarnings("unchecked")
    static String toJson(Object o) {
        StringBuilder sb = new StringBuilder();
        writeJson(sb, o);
        return sb.toString();
    }

    @SuppressWarnings("unchecked")
    static void writeJson(StringBuilder sb, Object o) {
        if (o == null) sb.append("null");
        else if (o instanceof String) jsonStr(sb, (String) o);
        else if (o instanceof Number || o instanceof Boolean) sb.append(o.toString());
        else if (o instanceof Map) {
            sb.append('{');
            boolean first = true;
            for (Map.Entry<String, Object> e : ((Map<String, Object>) o).entrySet()) {
                if (!first) sb.append(',');
                first = false;
                jsonStr(sb, e.getKey());
                sb.append(':');
                writeJson(sb, e.getValue());
            }
            sb.append('}');
        } else if (o instanceof List) {
            sb.append('[');
            boolean first = true;
            for (Object x : (List<Object>) o) {
                if (!first) sb.append(',');
                first = false;
                writeJson(sb, x);
            }
            sb.append(']');
        } else jsonStr(sb, o.toString());
    }

    static void jsonStr(StringBuilder sb, String s) {
        sb.append('"');
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"': sb.append("\\\""); break;
                case '\\': sb.append("\\\\"); break;
                case '\n': sb.append("\\n"); break;
                case '\r': sb.append("\\r"); break;
                case '\t': sb.append("\\t"); break;
                default:
                    if (c < 0x20 || c == '\u2028' || c == '\u2029') sb.append(String.format("\\u%04x", (int) c));
                    else sb.append(c);
            }
        }
        sb.append('"');
    }

    /** Minimal JSON reader (objects, arrays, strings, numbers, true/false/null). */
    static class JsonParser {
        final String s;
        int i;

        JsonParser(String s) { this(s, 0); }
        JsonParser(String s, int start) { this.s = s; this.i = start; }

        Object parse() { ws(); return value(0); }

        void ws() { while (i < s.length() && Character.isWhitespace(s.charAt(i))) i++; }

        RuntimeException bad() { return new ApiError("Unexpected data at position " + i); }

        Object value(int depth) {
            if (depth > 200) throw bad();
            ws();
            if (i >= s.length()) throw bad();
            char c = s.charAt(i);
            if (c == '{') {
                i++;
                Map<String, Object> m = new LinkedHashMap<String, Object>();
                ws();
                if (i < s.length() && s.charAt(i) == '}') { i++; return m; }
                while (true) {
                    ws();
                    if (i >= s.length() || s.charAt(i) != '"') throw bad();
                    String k = string();
                    ws();
                    if (i >= s.length() || s.charAt(i) != ':') throw bad();
                    i++;
                    m.put(k, value(depth + 1));
                    ws();
                    if (i >= s.length()) throw bad();
                    char d = s.charAt(i++);
                    if (d == '}') return m;
                    if (d != ',') throw bad();
                }
            }
            if (c == '[') {
                i++;
                List<Object> l = new ArrayList<Object>();
                ws();
                if (i < s.length() && s.charAt(i) == ']') { i++; return l; }
                while (true) {
                    l.add(value(depth + 1));
                    ws();
                    if (i >= s.length()) throw bad();
                    char d = s.charAt(i++);
                    if (d == ']') return l;
                    if (d != ',') throw bad();
                }
            }
            if (c == '"') return string();
            if (s.startsWith("true", i)) { i += 4; return Boolean.TRUE; }
            if (s.startsWith("false", i)) { i += 5; return Boolean.FALSE; }
            if (s.startsWith("null", i)) { i += 4; return null; }
            int st = i;
            while (i < s.length() && "+-0123456789.eE".indexOf(s.charAt(i)) >= 0) i++;
            if (st == i) throw bad();
            String num = s.substring(st, i);
            try {
                if (num.indexOf('.') < 0 && num.indexOf('e') < 0 && num.indexOf('E') < 0) return Long.parseLong(num);
                return Double.parseDouble(num);
            } catch (NumberFormatException e) {
                throw bad();
            }
        }

        String string() {
            i++; // opening quote
            StringBuilder sb = new StringBuilder();
            while (true) {
                if (i >= s.length()) throw bad();
                char c = s.charAt(i++);
                if (c == '"') return sb.toString();
                if (c != '\\') { sb.append(c); continue; }
                if (i >= s.length()) throw bad();
                char e = s.charAt(i++);
                switch (e) {
                    case '"': sb.append('"'); break;
                    case '\\': sb.append('\\'); break;
                    case '/': sb.append('/'); break;
                    case 'b': sb.append('\b'); break;
                    case 'f': sb.append('\f'); break;
                    case 'n': sb.append('\n'); break;
                    case 'r': sb.append('\r'); break;
                    case 't': sb.append('\t'); break;
                    case 'u':
                        if (i + 4 > s.length()) throw bad();
                        sb.append((char) Integer.parseInt(s.substring(i, i + 4), 16));
                        i += 4;
                        break;
                    default: throw bad();
                }
            }
        }
    }
}
