"""Read a OneNote section file (.one) into pages without OneNote.

Uses the bundled, patched copy of pyOneNote for the low-level file format and
rebuilds pages, paragraphs, tables, images and attachments from it. If a file
can't be parsed (for example very old OneNote 2007 sections), falls back to
recovering readable text straight from the file bytes.
"""
import os
import re
import struct
import uuid
from datetime import datetime, timedelta

from pyOneNote.Header import Header  # noqa: F401  (imported for side effects in pyOneNote)
from pyOneNote.FileNode import (FileNodeList, ExtendedGUID, CompactID,
                                ObjectSpaceManifestListReferenceFND,
                                RootObjectReference2FNDX, RootObjectReference3FND,
                                ObjectSpaceManifestRootFND, ObjectDeclarationFileData3RefCountFND,
                                FileDataStoreObjectReferenceFND)
from pyOneNote.OneDocument import OneDocment

# ---- property ids (MS-ONE) -------------------------------------------------
P_CONTENT_CHILDREN = 0x24001C1F   # ContentChildNodes (OutlineElement / PageManifest)
P_ELEMENT_CHILDREN = 0x24001C20   # ElementChildNodes (Page, Outline, Table, Row, Cell, ...)
P_STRUCT_CHILDREN = 0x24001D5F
P_GRAPH_SPACES = 0x2C001D63       # ChildGraphSpaceElementNodes (page order in a section)
P_PICTURE = 0x20001C3F
P_WEBPICTURE = 0x200034C8
P_EMBEDDED_FILE = 0x20001D9B
P_TEXT_UNICODE = 0x1C001C22
P_TEXT_ASCII = 0x1C003498
P_TITLE_CACHED = 0x1C001CF3
P_TITLE_FROM_PAGE = 0x1C001D3C
P_IMAGE_FILENAME = 0x1C001DD7
P_IMAGE_ALT = 0x1C001E58
P_EMBEDDED_NAME = 0x1C001D9C
P_LAST_MODIFIED = 0x14001D7A      # Time32
P_CREATED32 = 0x14001D09          # Time32
P_TOPO_CREATED = 0x18001C65       # FILETIME
P_LAST_MODIFIED_TS = 0x18001D77   # FILETIME
P_TEXT_RUN_INDEX = 0x1C001E12
P_TEXT_RUN_FORMAT = 0x24001E13
P_PARAGRAPH_STYLE = 0x2000342C
P_STYLE_ID = 0x1C00345A
P_BOLD, P_ITALIC, P_UNDERLINE, P_STRIKE = 0x08001C04, 0x08001C05, 0x08001C06, 0x08001C07
P_HYPERLINK = 0x08001E14
P_HYPERLINK_URL = 0x1C001E20
P_LIST_NODES = 0x24001C26
P_NUMBER_FORMAT = 0x1C001C1A
P_NOTE_TAG_STATES = 0x04003489
P_NOTE_TAG_COMPLETED = 0x1400346F
P_PAGE_LEVEL = 0x14001DFF

J = {  # jcid -> short name
    0x00060007: "section", 0x00060008: "pageseries", 0x0006000B: "page",
    0x0006000C: "outline", 0x0006000D: "oe", 0x0006000E: "richtext",
    0x00060011: "image", 0x00060012: "numberlist", 0x00060019: "outlinegroup",
    0x00060022: "table", 0x00060023: "row", 0x00060024: "cell", 0x0006002C: "title",
    0x00020030: "pagemeta", 0x00020031: "sectionmeta", 0x00060035: "embedded",
    0x00060037: "manifest", 0x0012004D: "style", 0x0006003C: "versionhistory",
}

FIELD_LINK = re.compile('﷟HYPERLINK\\s+"([^"]*)"')


def _key(x):
    """Normalise CompactID / ExtendedGUID into a hashable (guid, n)."""
    if isinstance(x, CompactID):
        g = x.resolve_guid()
        return (str(g), x.n) if g is not None else None
    if isinstance(x, ExtendedGUID):
        return (str(x.guid), x.n)
    return None


def _time32(b):
    try:
        v, = struct.unpack('<I', b)
        if v == 0:
            return None
        return datetime(1980, 1, 1) + timedelta(seconds=v)
    except Exception:
        return None


def _filetime(b):
    try:
        v, = struct.unpack('<Q', b)
        if v == 0:
            return None
        return datetime(1601, 1, 1) + timedelta(microseconds=v // 10)
    except Exception:
        return None


def _clean(s):
    return s.replace('\x00', '').replace('\r\n', '\n').replace('\r', '\n').replace('\x0b', '\n')


class Obj:
    __slots__ = ("jcid", "props", "space")

    def __init__(self, jcid, space):
        self.jcid = jcid
        self.props = {}
        self.space = space

    @property
    def kind(self):
        return J.get(self.jcid, "")

    def raw(self, pid):
        v = self.props.get(pid)
        return v

    def bytes_(self, pid):
        v = self.props.get(pid)
        return getattr(v, 'Data', None)

    def text(self, pid, enc='utf-16-le'):
        b = self.bytes_(pid)
        if b is None:
            return None
        try:
            return _clean(b.decode(enc, 'replace'))
        except Exception:
            return None

    def refs(self, pid):
        v = self.props.get(pid)
        if isinstance(v, list):
            out = []
            for x in v:
                k = _key(x) if x is not None else None
                if k:
                    out.append(k)
            return out
        return []

    def flag(self, pid):
        return self.props.get(pid) is True


class Section:
    def __init__(self, path):
        self.path = path
        self.objects = {}        # key -> Obj
        self.space_roots = {}    # space -> {role: key}
        self.space_order = []
        self.filedata = {}       # oid key -> ('guid'|'file', ref, ext)
        self.blobs = {}          # guid str (lower) -> bytes
        self.root_space = None

    # -- low level -----------------------------------------------------------
    def load(self):
        with open(self.path, 'rb') as f:
            doc = OneDocment(f)
            self._walk(doc.root_file_node_list, None, {})
        return self

    def _walk(self, node_list, space, jcid_by_key):
        for frag in node_list.fragments:
            for node in frag.fileNodes:
                data = getattr(node, 'data', None)
                cur_space = space
                if isinstance(data, ObjectSpaceManifestListReferenceFND):
                    cur_space = (str(data.gosid.guid), data.gosid.n)
                    if cur_space not in self.space_roots:
                        self.space_roots[cur_space] = {}
                        self.space_order.append(cur_space)
                elif isinstance(data, ObjectSpaceManifestRootFND):
                    self.root_space = (str(data.gosidRoot.guid), data.gosidRoot.n)
                elif isinstance(data, (RootObjectReference2FNDX, RootObjectReference3FND)) and space:
                    k = _key(data.oidRoot)
                    if k:
                        self.space_roots[space][data.RootRole] = k
                elif isinstance(data, ObjectDeclarationFileData3RefCountFND):
                    k = _key(data.oid)
                    ref = data.FileDataReference.StringData
                    ext = data.Extension.StringData
                    if k:
                        if ref.startswith('<ifndf>'):
                            g = ref.replace('<ifndf>{', '').replace('}', '').lower()
                            self.filedata[k] = ('guid', g, ext)
                        elif ref.startswith('<file>'):
                            self.filedata[k] = ('file', ref[len('<file>'):], ext)
                elif isinstance(data, FileDataStoreObjectReferenceFND):
                    try:
                        self.blobs[str(data.guidReference).lower()] = data.fileDataStoreObject.FileData
                    except Exception:
                        pass

                ps = getattr(node, 'propertySet', None)
                oid = getattr(node, 'decl_oid', None)
                if ps is not None and oid is not None:
                    k = _key(oid)
                    if k:
                        jc = getattr(node, 'decl_jcid', None)
                        if jc is None:
                            jc = jcid_by_key.get(k)
                        else:
                            jcid_by_key[k] = jc
                        o = Obj(jc, cur_space)
                        body = ps.body
                        for prid, val in zip(body.rgPrids, body.rgData):
                            o.props[prid.value if prid.type != 2 else (prid.value & 0x7fffffff)] = (
                                prid.boolValue if prid.type == 2 else val)
                        self.objects[k] = o   # later revisions win
                for child in node.children:
                    self._walk(child, cur_space, jcid_by_key)

    # -- files ----------------------------------------------------------------
    def file_bytes(self, k):
        fd = self.filedata.get(k)
        if not fd:
            return None, None
        kind, ref, ext = fd
        if kind == 'guid':
            return self.blobs.get(ref), ext
        base = os.path.dirname(self.path)
        for cand in (os.path.join(base, 'onefiles', ref), os.path.join(base, ref)):
            if os.path.isfile(cand):
                with open(cand, 'rb') as f:
                    return f.read(), ext
        return None, ext


# ---- page building ----------------------------------------------------------

class PageBuilder:
    def __init__(self, sec, emit_asset):
        self.sec = sec
        self.emit_asset = emit_asset   # (bytes, filename_hint) -> relative url

    def get(self, k):
        return self.sec.objects.get(k)

    def style_of(self, k):
        o = self.get(k)
        return o

    def runs(self, o):
        """Return list of runs {t, b, i, u, s, href} and paragraph style id."""
        text = o.text(P_TEXT_UNICODE)
        if text is None:
            text = o.text(P_TEXT_ASCII, 'cp1252')
        if text is None:
            return [], None
        pstyle = None
        ps = o.refs(P_PARAGRAPH_STYLE)
        if ps:
            so = self.get(ps[0])
            if so:
                pstyle = (so.text(P_STYLE_ID) or '').strip() or None

        idx_b = o.bytes_(P_TEXT_RUN_INDEX)
        ends = []
        if idx_b:
            ends = [x for x in struct.unpack('<%dI' % (len(idx_b) // 4), idx_b[:len(idx_b) // 4 * 4])]
        fmts = o.refs(P_TEXT_RUN_FORMAT)
        bounds = []
        start = 0
        for e in ends:
            bounds.append((start, min(e, len(text))))
            start = e
        bounds.append((start, len(text)))
        runs = []
        for i, (a, b) in enumerate(bounds):
            seg = text[a:b]
            if not seg:
                continue
            st = self.get(fmts[i]) if i < len(fmts) else None
            runs.append({
                't': seg,
                'b': bool(st and st.flag(P_BOLD)),
                'i': bool(st and st.flag(P_ITALIC)),
                'u': bool(st and st.flag(P_UNDERLINE)),
                's': bool(st and st.flag(P_STRIKE)),
                'link': bool(st and st.flag(P_HYPERLINK)),
            })
        # resolve hyperlink field codes
        out, pending = [], None
        for r in runs:
            t = r['t']
            m = FIELD_LINK.search(t)
            while m:
                pending = m.group(1)
                t = t[:m.start()] + t[m.end():]
                m = FIELD_LINK.search(t)
            t = t.replace('﷟', '')
            if not t:
                continue
            r['t'] = t
            if pending and (r['link'] or not out or True):
                r['href'] = pending
                if not r['link']:
                    pending = None
            elif r['link'] and re.match(r'https?://|www\.', t.strip()):
                r['href'] = t.strip()
            if not r['link']:
                pending = None
            out.append(r)
        return out, pstyle

    def checkbox(self, oe):
        v = oe.props.get(P_NOTE_TAG_STATES)
        if isinstance(v, list) and v:
            done = any(getattr(ps, 'rgPrids', None) and
                       any(p.value == P_NOTE_TAG_COMPLETED for p in ps.rgPrids) for ps in v)
            return 'done' if done else 'todo'
        return None

    def list_marker(self, oe):
        for k in oe.refs(P_LIST_NODES):
            ln = self.get(k)
            if ln is None:
                continue
            fmt = ln.text(P_NUMBER_FORMAT) or ''
            # numbered formats contain a placeholder control char (< 0x20) after the length char
            if any(ord(c) < 0x20 for c in fmt[1:] if c not in '\n'):
                return 'num'
            return 'bullet'
        return None

    def block(self, k, depth, seen, out):
        if k in seen:
            return
        seen.add(k)
        o = self.get(k)
        if o is None:
            return
        kind = o.kind
        if kind in ('outline', 'outlinegroup', 'title', 'page'):
            for c in o.refs(P_ELEMENT_CHILDREN):
                self.block(c, depth if kind != 'outlinegroup' else depth, seen, out)
        elif kind == 'oe':
            marker = self.list_marker(o)
            box = self.checkbox(o)
            first = True
            for c in o.refs(P_CONTENT_CHILDREN):
                co = self.get(c)
                if co is None:
                    continue
                sub = []
                self.block(c, depth, seen, sub)
                for b in sub:
                    if first and b['type'] == 'p':
                        if marker:
                            b['list'] = marker
                        if box:
                            b['check'] = box
                    first = False
                out.extend(sub)
            for c in o.refs(P_ELEMENT_CHILDREN):
                self.block(c, depth + 1, seen, out)
        elif kind == 'richtext':
            runs, pstyle = self.runs(o)
            if runs and any(r['t'].strip() for r in runs):
                out.append({'type': 'p', 'depth': depth, 'runs': runs, 'style': pstyle})
        elif kind == 'table':
            rows = []
            for rk in o.refs(P_ELEMENT_CHILDREN):
                ro = self.get(rk)
                if ro is None:
                    continue
                cells = []
                for ck in ro.refs(P_ELEMENT_CHILDREN):
                    cb = []
                    co = self.get(ck)
                    if co is not None:
                        for ek in co.refs(P_ELEMENT_CHILDREN):
                            self.block(ek, 0, seen, cb)
                    cells.append(cb)
                rows.append(cells)
            if rows:
                out.append({'type': 'table', 'depth': depth, 'rows': rows})
        elif kind == 'image':
            refs = o.refs(P_PICTURE) or o.refs(P_WEBPICTURE)
            name = (o.text(P_IMAGE_FILENAME) or 'image').strip() or 'image'
            alt = (o.text(P_IMAGE_ALT) or '').strip()
            ocr = (o.text(P_TEXT_UNICODE) or '').strip()
            url = None
            if refs:
                data, ext = self.sec.file_bytes(refs[0])
                if data:
                    url = self.emit_asset(data, name, ext)
            out.append({'type': 'img', 'depth': depth, 'src': url, 'name': name, 'alt': alt, 'ocr': ocr})
        elif kind == 'embedded':
            refs = o.refs(P_EMBEDDED_FILE)
            name = (o.text(P_EMBEDDED_NAME) or 'attachment').strip() or 'attachment'
            url = None
            if refs:
                data, ext = self.sec.file_bytes(refs[0])
                if data:
                    url = self.emit_asset(data, name, ext)
            out.append({'type': 'file', 'depth': depth, 'href': url, 'name': name})
        else:
            # unknown container: still try to follow children so text isn't lost
            for c in o.refs(P_ELEMENT_CHILDREN) + o.refs(P_CONTENT_CHILDREN):
                self.block(c, depth, seen, out)

    def page_from_space(self, space):
        roots = self.sec.space_roots.get(space, {})
        page_obj_key = None
        meta = None
        for role, k in roots.items():
            o = self.get(k)
            if o is None:
                continue
            if o.kind == 'manifest':
                for c in o.refs(P_CONTENT_CHILDREN):
                    co = self.get(c)
                    if co is not None and co.kind == 'page':
                        page_obj_key = c
            elif o.kind == 'page':
                page_obj_key = k
            elif o.kind == 'pagemeta':
                meta = o
        if page_obj_key is None:
            # fallback: any page node living in this space
            for k, o in self.sec.objects.items():
                if o.space == space and o.kind == 'page':
                    page_obj_key = k
                    break
        if page_obj_key is None:
            return None
        if meta is None:
            for o in self.sec.objects.values():
                if o.space == space and o.kind == 'pagemeta':
                    meta = o
                    break
        po = self.get(page_obj_key)
        title = None
        if meta is not None:
            title = meta.text(P_TITLE_CACHED)
        if not title:
            title = po.text(P_TITLE_FROM_PAGE)
        blocks = []
        seen = set()
        title_blocks = []
        for c in po.refs(P_ELEMENT_CHILDREN):
            co = self.get(c)
            if co is not None and co.kind == 'title':
                self.block(c, 0, seen, title_blocks)
            else:
                self.block(c, 0, seen, blocks)
        title_text = ' '.join(''.join(r['t'] for r in b['runs']) for b in title_blocks if b['type'] == 'p').strip()
        title = (title or '').strip() or title_text or 'Untitled page'
        created = None
        modified = None
        if meta is not None:
            created = _filetime(meta.bytes_(P_TOPO_CREATED) or b'') if meta.bytes_(P_TOPO_CREATED) else None
            if created is None and isinstance(meta.props.get(P_TOPO_CREATED), bytes):
                created = _filetime(meta.props[P_TOPO_CREATED])
        lm = po.props.get(P_LAST_MODIFIED)
        if isinstance(lm, bytes):
            modified = _time32(lm)
        # date shown in title area (OneNote's page date) if present
        for b in title_blocks[1:]:
            pass
        level = 1
        if meta is not None:
            lv = meta.props.get(P_PAGE_LEVEL)
            if isinstance(lv, bytes) and len(lv) == 4:
                level = max(1, min(3, struct.unpack('<I', lv)[0]))
        return {'title': title, 'blocks': blocks, 'created': created, 'modified': modified, 'level': level}

    def pages(self):
        sec = self.sec
        order = []
        # preferred: page order as stored in the section's page series
        for k, o in sec.objects.items():
            if o.kind == 'pageseries':
                v = o.props.get(P_GRAPH_SPACES)
                if isinstance(v, list):
                    for x in v:
                        kk = _key(x)
                        if kk and kk not in order:
                            order.append(kk)
        listed = set(order)
        # spaces that hold a page but weren't listed (older or deleted copies) - kept, but flagged
        for sp in sec.space_order:
            if sp not in listed:
                order.append(sp)
        pages, sigs = [], set()
        for sp in order:
            p = self.page_from_space(sp)
            if p is None:
                continue
            if listed and sp not in listed:
                if not p['blocks']:
                    continue
                p['orphan'] = True
            sig = (p['title'], len(p['blocks']), _plain_blocks(p['blocks'])[:2000])
            if sig in sigs:
                continue
            sigs.add(sig)
            pages.append(p)
        return pages


def _plain_blocks(blocks):
    parts = []
    for b in blocks:
        if b['type'] == 'p':
            parts.append(''.join(r['t'] for r in b['runs']))
        elif b['type'] == 'table':
            for row in b['rows']:
                for cell in row:
                    parts.append(_plain_blocks(cell))
        elif b['type'] == 'img':
            parts.append(b.get('alt') or '')
            parts.append(b.get('ocr') or '')
        elif b['type'] == 'file':
            parts.append(b.get('name') or '')
    return '\n'.join(p for p in parts if p)


# ---- fallback: raw text recovery ---------------------------------------------
_U16 = re.compile(rb'(?:[\x09\x0a\x0d\x20-\x7e\xa0-\xff]\x00|[\x13\x14\x18-\x1d\x22\x26\xac]\x20){6,}')


_NOISE = {'Calibri', 'Calibri Light', 'PageTitle', 'PageDateTime', 'PageTime', 'Consolas', 'Comic Sans MS',
          'Comic sans', 'Arial', 'Segoe UI', 'Times New Roman', 'Courier New', 'Cambria', 'Aptos', 'Verdana',
          'blockquote', 'OneNote_RecycleBin', 'Tahoma'}


def raw_text_pages(path):
    with open(path, 'rb') as f:
        data = f.read()
    seen, items = set(), []
    for off in (0, 1):
        for m in _U16.finditer(data, off):
            if (m.start() - off) % 2:
                continue
            s = _clean(m.group().decode('utf-16-le', 'ignore')).strip()
            if sum(c.isalpha() for c in s) < 4 or s in seen:
                continue
            # skip font/style/system names
            if s in _NOISE or re.fullmatch(r'[A-Za-z]:\\.*', s) or re.fullmatch(r'\{?[0-9a-fA-F-]{36}\}?', s):
                continue
            seen.add(s)
            items.append((m.start(), s))
    items.sort()
    blocks = [{'type': 'p', 'depth': 0, 'runs': [{'t': s}], 'style': None} for _, s in items]
    if not blocks:
        return []
    return [{'title': 'Recovered text', 'blocks': blocks, 'created': None, 'modified': None,
             'level': 1, 'recovered': True}]


def read_section(path, emit_asset):
    """Return (pages, mode, error). mode is 'full' or 'recovered'."""
    err = None
    try:
        sec = Section(path).load()
        pages = PageBuilder(sec, emit_asset).pages()
        if pages:
            return pages, 'full', None
        err = 'no pages found by the parser'
    except Exception as e:  # keep going with the fallback
        err = '%s: %s' % (type(e).__name__, e)
    try:
        return raw_text_pages(path), 'recovered', err
    except Exception as e:
        return [], 'failed', '%s; fallback failed: %s' % (err, e)
