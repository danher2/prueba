#!/usr/bin/env python3
"""OneNote Viewer - read OneNote section files (.one) without OneNote.

Usage:
    python onenote_viewer.py <notebooks folder> [more folders or .one files] [-o OUTPUT_FOLDER]

It scans the folder(s) for .one files, reads every page (text, formatting,
lists, tables, links, images and attachments) and writes a browsable,
searchable viewer:  OUTPUT_FOLDER/index.html  (plus an assets folder).

Your original files are only read, never changed.
"""
import argparse
import hashlib
import html
import json
import os
import re
import subprocess
import sys
import time
import webbrowser

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.setrecursionlimit(20000)

from onenote_extract import read_section, _plain_blocks  # noqa: E402

WEB_IMAGE_EXT = {'.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp', '.svg', '.ico'}
SKIP_DIRS = {'onenote_recyclebin', 'onefiles'}


def safe_name(s, default='file'):
    s = re.sub(r'[<>:"/\\|?*\x00-\x1f]', '_', s or '').strip(' .')
    return s[:80] or default


class Assets:
    def __init__(self, out_dir):
        self.dir = os.path.join(out_dir, 'assets')
        os.makedirs(self.dir, exist_ok=True)
        self.by_hash = {}
        self.count = 0
        self.bytes = 0

    def emit(self, data, name, ext):
        h = hashlib.sha1(data).hexdigest()[:16]
        if h in self.by_hash:
            return self.by_hash[h]
        base, e = os.path.splitext(name or '')
        e = (e or ext or '').lower()
        if e and not e.startswith('.'):
            e = '.' + e
        fname = '%s_%s%s' % (h[:8], safe_name(base, 'file'), e)
        with open(os.path.join(self.dir, fname), 'wb') as f:
            f.write(data)
        url = 'assets/' + fname
        self.by_hash[h] = url
        self.count += 1
        self.bytes += len(data)
        return url


def find_sections(paths, include_deleted=False):
    """Yield (notebook_name, group_path_list, section_name, file_path)."""
    seen = set()
    for p in paths:
        p = os.path.abspath(p)
        if os.path.isfile(p):
            if p.lower().endswith('.one') and p not in seen:
                seen.add(p)
                nb = os.path.basename(os.path.dirname(p)) or 'Notebook'
                yield nb, [], os.path.splitext(os.path.basename(p))[0], p
            continue
        if not os.path.isdir(p):
            print('  ! Not found: %s' % p)
            continue
        root_name = os.path.basename(p.rstrip('\\/')) or 'Notebooks'
        for dirpath, dirnames, filenames in os.walk(p):
            dirnames[:] = sorted(d for d in dirnames if include_deleted or d.lower() not in SKIP_DIRS)
            rel = os.path.relpath(dirpath, p)
            parts = [] if rel == '.' else rel.split(os.sep)
            ones = sorted(f for f in filenames if f.lower().endswith('.one'))
            if not ones:
                continue
            # A folder of .one files is a notebook; deeper folders are section groups.
            if parts:
                nb, groups = parts[0], parts[1:]
            else:
                nb, groups = root_name, []
            for fn in ones:
                if not include_deleted and fn.lower().startswith('onenote_deletedpages'):
                    continue
                fp = os.path.join(dirpath, fn)
                if fp in seen:
                    continue
                seen.add(fp)
                yield nb, groups, os.path.splitext(fn)[0], fp


def file_format(path):
    try:
        with open(path, 'rb') as f:
            head = f.read(64)
    except OSError:
        return 'unreadable'
    if head[48:52] == bytes.fromhex('3fdd9a10'):
        return 'desktop'
    if head[48:52] == bytes.fromhex('2fe98d63'):
        return 'cloud'
    return 'unknown'


def unpack_onepkg(paths, out):
    """.onepkg files are packed notebooks (CAB archives). Windows can unpack them with expand.exe."""
    result = []
    for p in paths:
        pkgs = []
        if os.path.isfile(p) and p.lower().endswith('.onepkg'):
            pkgs = [p]
        else:
            result.append(p)
            if os.path.isdir(p):
                for dp, _dn, fns in os.walk(p):
                    pkgs += [os.path.join(dp, f) for f in fns if f.lower().endswith('.onepkg')]
        for pkg in pkgs:
            name = os.path.splitext(os.path.basename(pkg))[0]
            dest = os.path.join(out, '_unpacked', safe_name(name, 'notebook'))
            os.makedirs(dest, exist_ok=True)
            print('Unpacking %s ...' % os.path.basename(pkg))
            try:
                subprocess.run(['expand', pkg, '-F:*', dest], check=True,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                result.append(dest)
            except Exception:
                print('  ! Could not unpack %s automatically. On Windows run:\n'
                      '    expand "%s" -F:* "%s"\n  then point this tool at that folder.' % (pkg, pkg, dest))
    return result


def fmt_dt(d):
    return d.strftime('%Y-%m-%d %H:%M') if d else None


def main():
    ap = argparse.ArgumentParser(description='Read OneNote .one files without OneNote and build a searchable viewer.')
    ap.add_argument('paths', nargs='+', help='Folder(s) containing your notebooks, or .one / .onepkg files')
    ap.add_argument('-o', '--output', default=None, help='Output folder (default: "OneNote Viewer" next to the first input)')
    ap.add_argument('--include-deleted', action='store_true', help='Also read OneNote_RecycleBin / deleted pages')
    ap.add_argument('--no-open', action='store_true', help="Don't open the viewer in the browser when done")
    args = ap.parse_args()
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(errors='replace')
        except Exception:
            pass

    first = os.path.abspath(args.paths[0])
    out = os.path.abspath(args.output or os.path.join(os.path.dirname(first.rstrip('\\/')), 'OneNote Viewer'))
    os.makedirs(out, exist_ok=True)
    assets = Assets(out)

    paths = unpack_onepkg(args.paths, out)
    sections = list(find_sections(paths, args.include_deleted))
    if not sections:
        print('No .one files found in: %s' % ', '.join(args.paths))
        print('Tip: point it at the folder that contains your notebook folders (the ones with .one files).')
        return 1

    print('Found %d section file(s). Reading...' % len(sections))
    t0 = time.time()
    notebooks = {}   # name -> {"name", "sections": [...]}
    report = []
    total_pages = 0
    page_id = 0
    for i, (nb, groups, sec_name, fp) in enumerate(sections, 1):
        fmt = file_format(fp)
        size_mb = os.path.getsize(fp) / 1e6
        print('  [%d/%d] %s / %s%s (%.1f MB) ...' % (i, len(sections), nb, ' / '.join(groups + [sec_name]),
                                                    '', size_mb), end='', flush=True)
        st = time.time()
        pages, mode, err = read_section(fp, assets.emit)
        note = None
        if mode != 'full':
            if fmt == 'cloud':
                note = ('This section is in the OneDrive/SharePoint download format, which this tool can only '
                        'partly read. Showing the text it could recover.')
            else:
                note = "This section's format couldn't be fully read. Showing the text that could be recovered."
        sec_pages = []
        for p in pages:
            page_id += 1
            sec_pages.append({
                'id': page_id,
                'title': p['title'],
                'level': p.get('level', 1),
                'created': fmt_dt(p.get('created')),
                'modified': fmt_dt(p.get('modified')),
                'orphan': bool(p.get('orphan')),
                'blocks': p['blocks'],
                'text': _plain_blocks(p['blocks']),
            })
        total_pages += len(sec_pages)
        nbo = notebooks.setdefault(nb, {'name': nb, 'sections': []})
        nbo['sections'].append({'name': sec_name, 'groups': groups, 'file': fp, 'mode': mode,
                                'note': note, 'pages': sec_pages})
        status = {'full': 'ok', 'recovered': 'text only', 'failed': 'FAILED'}[mode]
        print(' %d page(s), %s (%.1fs)' % (len(sec_pages), status, time.time() - st))
        report.append('%-10s %4d pages  %s%s' % (status, len(sec_pages), fp, ('   [' + err + ']') if err and mode != 'full' else ''))

    data = {'generated': time.strftime('%Y-%m-%d %H:%M'), 'notebooks': list(notebooks.values())}
    with open(os.path.join(HERE, 'viewer_template.html'), encoding='utf-8') as f:
        tpl = f.read()
    payload = json.dumps(data, ensure_ascii=False, separators=(',', ':')).replace('</', '<\\/')
    page = tpl.replace('/*__DATA__*/null', payload)
    index = os.path.join(out, 'index.html')
    with open(index, 'w', encoding='utf-8') as f:
        f.write(page)
    with open(os.path.join(out, 'report.txt'), 'w', encoding='utf-8') as f:
        f.write('OneNote Viewer report - %s\n\n' % data['generated'])
        f.write('\n'.join(report) + '\n')

    full = sum(1 for r in report if r.startswith('ok'))
    print('\nDone in %.0fs: %d notebook(s), %d section(s), %d page(s), %d image/attachment file(s).'
          % (time.time() - t0, len(notebooks), len(sections), total_pages, assets.count))
    if full < len(sections):
        print('%d section(s) could only be partly read - see report.txt' % (len(sections) - full))
    print('Viewer: %s' % index)
    if not args.no_open:
        try:
            webbrowser.open('file:///' + index.replace('\\', '/').lstrip('/'))
        except Exception:
            pass
    return 0


if __name__ == '__main__':
    sys.exit(main())
