import json
import os
import plistlib
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
FONTTOOL = os.environ.get("EMOJITWEAK_DIR") or os.path.join(HERE, os.pardir,
                                                            "emojitweak")
FONTTOOL = os.path.abspath(FONTTOOL)
CACHE = os.path.join(FONTTOOL, "cache")
EVIDENCE = os.path.join(HERE, "evidence", "ios6_emoji_tables.json")
OUT = os.path.join(HERE, "out", "palette.plist")

FORMAT = 1

FE0F = 0xFE0F
FE0E = 0xFE0E

PEOPLE, NATURE, OBJECTS, PLACES, SYMBOLS = 1, 2, 3, 4, 5

GROUP_TO_TYPE = {
    "Smileys & Emotion": PEOPLE,
    "People & Body": PEOPLE,
    "Animals & Nature": NATURE,
    "Food & Drink": OBJECTS,
    "Activities": OBJECTS,
    "Objects": OBJECTS,
    "Travel & Places": PLACES,
    "Flags": PLACES,
    "Symbols": SYMBOLS,
    "Component": None,
}

TYPE_NAMES = {PEOPLE: "People", NATURE: "Nature", OBJECTS: "Objects",
              PLACES: "Places", SYMBOLS: "Symbols"}

GROUP_ORDER = ["Smileys & Emotion", "People & Body", "Animals & Nature",
               "Food & Drink", "Activities", "Objects", "Travel & Places",
               "Flags", "Symbols"]

SKIN_TONES = set(range(0x1F3FB, 0x1F400))
HAIR = set(range(0x1F9B0, 0x1F9B4))


def load_emojidata():
    sys.path.insert(0, FONTTOOL)
    try:
        import emojidata
    except ImportError:
        raise SystemExit("build.py: cannot import emojidata from %s\n"
                         "          set EMOJITWEAK_DIR to the font project"
                         % FONTTOOL)
    return emojidata


def parse_grouped(path):
    entries = []
    group = None
    subgroup = None
    for raw in open(path, encoding="utf-8"):
        line = raw.rstrip("\n")
        if line.startswith("# group:"):
            group = line.split(":", 1)[1].strip()
            continue
        if line.startswith("# subgroup:"):
            subgroup = line.split(":", 1)[1].strip()
            continue
        if not line or line.startswith("#"):
            continue
        head, _, tail = line.partition(";")
        if not tail:
            continue
        status = tail.split("#", 1)[0].strip()
        try:
            cps = tuple(int(x, 16) for x in head.split())
        except ValueError:
            continue
        if not cps:
            continue
        entries.append((cps, status, group, subgroup))
    return entries


def normalise(cps):
    stripped = tuple(c for c in cps if c not in (FE0F, FE0E))
    return stripped or cps


def text(cps):
    return "".join(chr(c) for c in cps)


def stock_strings():
    if not os.path.exists(EVIDENCE):
        return set(), 0
    data = json.load(open(EVIDENCE, encoding="utf-8"))
    keys = set()
    total = 0
    for cat in data.get("categories", []):
        for slot in cat.get("slot_units", []):
            units = [int(u, 16) for u in slot]
            units = [u for u in units if u]
            if not units:
                continue
            total += 1
            keys.add(normalise(decode_utf16(units)))
        for seq in cat.get("extra_sequences", []):
            units = [int(u, 16) for u in seq]
            total += 1
            keys.add(normalise(decode_utf16(units)))
    return keys, total


def decode_utf16(units):
    out = []
    i = 0
    while i < len(units):
        u = units[i]
        if 0xD800 <= u <= 0xDBFF and i + 1 < len(units):
            out.append(0x10000 + ((u - 0xD800) << 10) + (units[i + 1] - 0xDC00))
            i += 2
        else:
            out.append(u)
            i += 1
    return tuple(out)


def plan(skin_tones):
    E = load_emojidata()
    path, ucd, emoji_ver = E.fetch_emoji_test(CACHE)
    entries = parse_grouped(path)
    stock, stock_count = stock_strings()

    by_group = {}
    seen = set()
    for cps, status, group, subgroup in entries:
        if status != "fully-qualified":
            continue
        if GROUP_TO_TYPE.get(group) is None:
            continue
        key = normalise(cps)
        if key in seen or key in stock:
            continue
        if not skin_tones and (set(cps) & SKIN_TONES):
            continue
        seen.add(key)
        by_group.setdefault(group, []).append(cps)

    buckets = {t: [] for t in TYPE_NAMES}
    for group in GROUP_ORDER:
        for cps in by_group.get(group, []):
            buckets[GROUP_TO_TYPE[group]].append(cps)

    return buckets, ucd, emoji_ver, stock_count, path


def main():
    skin_tones = os.environ.get("EMOJIKEYBOARD_SKIN_TONES", "1") not in (
        "0", "no", "off", "false")
    buckets, ucd, emoji_ver, stock_count, path = plan(skin_tones)

    payload = {
        "format": FORMAT,
        "unicode": emoji_ver,
        "ucd": ucd,
        "generated": time.strftime("%Y-%m-%d", time.gmtime(
            int(os.environ.get("SOURCE_DATE_EPOCH", time.time())))),
        "skinTones": bool(skin_tones),
        "categories": {},
    }
    for t in sorted(TYPE_NAMES):
        payload["categories"][str(t)] = [text(cps) for cps in buckets[t]]

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    tmp = OUT + ".part"
    with open(tmp, "wb") as fh:
        plistlib.dump(payload, fh, fmt=plistlib.FMT_BINARY, sort_keys=True)
    os.replace(tmp, OUT)

    total = sum(len(v) for v in payload["categories"].values())
    print("palette: Unicode Emoji %s (UCD %s), skin tones %s"
          % (emoji_ver, ucd, "on" if skin_tones else "off"))
    print("  source   %s" % path)
    print("  stock    %d iOS 6 slots excluded" % stock_count)
    for t in sorted(TYPE_NAMES):
        n = len(payload["categories"][str(t)])
        seqs = sum(1 for s in payload["categories"][str(t)] if len(s) > 2)
        print("  type %d   %-8s %5d candidates (%d multi-unit)"
              % (t, TYPE_NAMES[t], n, seqs))
    print("  total    %d candidates" % total)
    print("  wrote    %s (%d bytes)" % (OUT, os.path.getsize(OUT)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
