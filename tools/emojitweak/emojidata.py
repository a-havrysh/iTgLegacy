import json
import os
import re
import tarfile
import urllib.error
import urllib.request

UNICODE_LATEST = "https://www.unicode.org/Public/emoji/latest/ReadMe.txt"
TWEMOJI_RELEASE = "https://api.github.com/repos/jdecked/twemoji/releases/latest"
TWEMOJI_TARBALL = "https://codeload.github.com/jdecked/twemoji/tar.gz/refs/tags/%s"

FE0F = 0xFE0F
ZWJ = 0x200D

MIN_TEST_ENTRIES = 3000
MIN_SVG_ASSETS = 3000


class SourceError(RuntimeError):
    pass


def _get(url, headers=None):
    req = urllib.request.Request(url, headers=headers or {"User-Agent": "emojitweak"})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.read()
    except urllib.error.HTTPError as e:
        raise SourceError(
            "%s returned HTTP %s (%s).\n"
            "The upstream layout has probably changed; check the URL by hand."
            % (url, e.code, e.reason)) from None
    except urllib.error.URLError as e:
        raise SourceError("cannot reach %s: %s" % (url, e.reason)) from None


def download(url, path, headers=None):
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return path, False
    data = _get(url, headers)
    if not data:
        raise SourceError("%s returned an empty body" % url)
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    tmp = path + ".part"
    with open(tmp, "wb") as fh:
        fh.write(data)
    os.replace(tmp, path)
    return path, True


def resolve_emoji_version(cache_dir):
    path = os.path.join(cache_dir, "emoji-latest-ReadMe.txt")
    download(UNICODE_LATEST, path)
    text = open(path, encoding="utf-8").read()

    m = re.search(r"Public/(\d+\.\d+\.\d+)/emoji/", text)
    if m:
        ucd = m.group(1)
    else:
        m2 = re.search(r"Unicode Emoji,?\s+Version\s+(\d+)\.(\d+)", text)
        if not m2:
            raise SourceError(
                "cannot find a version in %s.\n"
                "%s no longer has the expected shape. Delete that cache file, "
                "read the ReadMe by hand and update the patterns in "
                "resolve_emoji_version()." % (path, UNICODE_LATEST))
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
    meta = os.path.join(cache_dir, "twemoji-release.json")
    download(TWEMOJI_RELEASE, meta,
             {"User-Agent": "emojitweak", "Accept": "application/vnd.github+json"})
    try:
        tag = json.load(open(meta, encoding="utf-8"))["tag_name"]
    except (ValueError, KeyError, TypeError):
        raise SourceError(
            "no tag_name in %s.\n"
            "The GitHub releases API returned something unexpected, most often an "
            "unauthenticated rate-limit reply. Delete that file and retry, or set "
            "GH_TOKEN and try again." % meta) from None
    if not isinstance(tag, str) or not tag.strip():
        raise SourceError("empty tag_name in %s" % meta)

    tar = os.path.join(cache_dir, "twemoji-%s.tar.gz" % tag)
    download(TWEMOJI_TARBALL % tag, tar)

    root = os.path.join(cache_dir, "twemoji")
    svgdir = os.path.join(root, "assets", "svg")
    if not os.path.isdir(svgdir) or not os.listdir(svgdir):
        os.makedirs(root, exist_ok=True)
        with tarfile.open(tar) as tf:
            names = tf.getnames()
            if not names:
                raise SourceError("%s is empty" % tar)
            prefix = names[0].split("/")[0]
            wanted = prefix + "/assets/svg/"
            members = [m for m in tf.getmembers()
                       if m.name.startswith(wanted) or m.name.endswith("/LICENSE")]
            if not any(m.name.startswith(wanted) for m in members):
                raise SourceError(
                    "%s contains no %s.\n"
                    "Twemoji %s has moved its artwork; update fetch_twemoji() to the "
                    "new layout." % (tar, wanted, tag))
            for m in members:
                m.name = m.name[len(prefix) + 1:]
            tf.extractall(root, members=members)

    if not os.path.isdir(svgdir):
        raise SourceError("expected SVG artwork at %s after extracting %s"
                          % (svgdir, tar))
    n = sum(1 for f in os.listdir(svgdir) if f.endswith(".svg"))
    if n < MIN_SVG_ASSETS:
        raise SourceError(
            "only %d SVG files in %s, expected at least %d.\n"
            "The extraction is incomplete or Twemoji %s changed shape. Delete "
            "%s and the tarball, then retry." % (n, svgdir, MIN_SVG_ASSETS, tag, root))
    return svgdir, tag


LINE = re.compile(r"^([0-9A-Fa-f ]+);\s*([a-z\-]+)\s*#\s*(\S+)\s+(E\d+\.\d+)\s+(.*)$")


def parse_emoji_test(path):
    entries = []
    unmatched = []
    for raw in open(path, encoding="utf-8"):
        line = raw.rstrip("\n")
        if not line.strip() or line.startswith("#"):
            continue
        m = LINE.match(line)
        if not m:
            unmatched.append(line)
            continue
        cps = tuple(int(x, 16) for x in m.group(1).split())
        entries.append((cps, m.group(2), m.group(5)))

    if unmatched:
        sample = "\n".join("    " + l[:90] for l in unmatched[:5])
        raise SourceError(
            "%d data lines in %s did not parse:\n%s\n"
            "emoji-test.txt has changed format; update the LINE pattern in "
            "emojidata.py before shipping a build." % (len(unmatched), path, sample))
    if len(entries) < MIN_TEST_ENTRIES:
        raise SourceError(
            "only %d entries parsed out of %s, expected at least %d.\n"
            "The file is truncated or is not emoji-test.txt. Delete it and retry."
            % (len(entries), path, MIN_TEST_ENTRIES))
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
