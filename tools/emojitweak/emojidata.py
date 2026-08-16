import os
import re
import urllib.request

UNICODE_LATEST = "https://www.unicode.org/Public/emoji/latest/ReadMe.txt"
TWEMOJI_RELEASE = "https://api.github.com/repos/jdecked/twemoji/releases/latest"
TWEMOJI_TARBALL = "https://codeload.github.com/jdecked/twemoji/tar.gz/refs/tags/%s"

FE0F = 0xFE0F
ZWJ = 0x200D


def _get(url, headers=None):
    req = urllib.request.Request(url, headers=headers or {"User-Agent": "emojitweak"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def download(url, path, headers=None):
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return path, False
    data = _get(url, headers)
    tmp = path + ".part"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(tmp, "wb") as fh:
        fh.write(data)
    os.replace(tmp, path)
    return path, True


def resolve_emoji_version(cache_dir):
    path = os.path.join(cache_dir, "emoji-latest-ReadMe.txt")
    if not os.path.exists(path):
        with open(path, "wb") as fh:
            fh.write(_get(UNICODE_LATEST))
    text = open(path, encoding="utf-8").read()
    m = re.search(r"Public/(\d+\.\d+\.\d+)/emoji/", text)
    if m:
        ucd = m.group(1)
    else:
        m2 = re.search(r"Unicode Emoji,?\s+Version\s+(\d+)\.(\d+)", text)
        if not m2:
            raise RuntimeError("cannot determine emoji version from ReadMe")
        ucd = "%s.%s.0" % (m2.group(1), m2.group(2))
    m3 = re.search(r"Unicode Emoji,?\s+Version\s+(\d+\.\d+)", text)
    emoji_ver = m3.group(1) if m3 else ucd.rsplit(".", 1)[0]
    return ucd, emoji_ver


def fetch_emoji_test(cache_dir):
    ucd, emoji_ver = resolve_emoji_version(cache_dir)
    url = "https://www.unicode.org/Public/%s/emoji/emoji-test.txt" % ucd
    path = os.path.join(cache_dir, "emoji-test-%s.txt" % ucd)
    download(url, path)
    return path, ucd, emoji_ver


def fetch_twemoji(cache_dir):
    import json
    meta = os.path.join(cache_dir, "twemoji-release.json")
    if not os.path.exists(meta):
        with open(meta, "wb") as fh:
            fh.write(_get(TWEMOJI_RELEASE,
                          {"User-Agent": "emojitweak",
                           "Accept": "application/vnd.github+json"}))
    tag = json.load(open(meta))["tag_name"]
    tar = os.path.join(cache_dir, "twemoji-%s.tar.gz" % tag)
    download(TWEMOJI_TARBALL % tag, tar)
    svgdir = os.path.join(cache_dir, "twemoji", "assets", "svg")
    if not os.path.isdir(svgdir) or not os.listdir(svgdir):
        import tarfile
        root = os.path.join(cache_dir, "twemoji")
        os.makedirs(root, exist_ok=True)
        with tarfile.open(tar) as tf:
            prefix = tf.getnames()[0].split("/")[0]
            members = [m for m in tf.getmembers()
                       if m.name.startswith(prefix + "/assets/svg/")
                       or m.name.endswith("/LICENSE")]
            for m in members:
                m.name = m.name[len(prefix) + 1:]
            tf.extractall(root, members=members)
    return svgdir, tag


LINE = re.compile(r"^([0-9A-Fa-f ]+);\s*([a-z\-]+)\s*#\s*(\S+)\s+(E\d+\.\d+)\s+(.*)$")


def parse_emoji_test(path):
    entries = []
    for raw in open(path, encoding="utf-8"):
        line = raw.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        m = LINE.match(line)
        if not m:
            continue
        cps = tuple(int(x, 16) for x in m.group(1).split())
        entries.append((cps, m.group(2), m.group(5)))
    return entries


def build_identities(entries):
    identities = []
    aliases = {}
    current = None
    for cps, status, name in entries:
        if status in ("fully-qualified", "component"):
            current = cps
            identities.append((cps, name, status))
            aliases[cps] = cps
        elif status in ("minimally-qualified", "unqualified"):
            if current is None:
                continue
            aliases.setdefault(cps, current)
        else:
            continue
    return identities, aliases


def index_assets(svgdir):
    index = {}
    for fn in os.listdir(svgdir):
        if not fn.endswith(".svg"):
            continue
        try:
            cps = tuple(int(x, 16) for x in fn[:-4].split("-"))
        except ValueError:
            continue
        path = os.path.join(svgdir, fn)
        index.setdefault(cps, path)
        stripped = tuple(c for c in cps if c != FE0F)
        index.setdefault(stripped, path)
    return index


def find_asset(index, cps):
    for key in (cps, tuple(c for c in cps if c != FE0F)):
        if key in index:
            return index[key]
    return None
