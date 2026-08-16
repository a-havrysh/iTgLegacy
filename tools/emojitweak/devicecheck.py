import os
import subprocess
import sys
from collections import Counter

from fontTools.ttLib import TTFont

import emojidata as E

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "cache")
OUTDIR = os.path.join(HERE, "out")
FONT = os.path.join(OUTDIR, "AppleColorEmoji.ttf")
IPAD = os.path.join(HERE, "ipad.sh")


def gname(cps):
    return "_".join("u%04X" % c for c in cps)


def sh(*args):
    return subprocess.run([IPAD] + list(args), capture_output=True, text=True)


def main():
    test_path, ucd, ver = E.fetch_emoji_test(CACHE)
    entries = E.parse_emoji_test(test_path)
    identities, aliases = E.build_identities(entries)
    status_of = {}
    for cps, status, _ in entries:
        status_of.setdefault(cps, status)

    font = TTFont(FONT, lazy=True)
    gid = {n: i for i, n in enumerate(font.getGlyphOrder())}

    cases = sorted(aliases.items())
    samples = os.path.join(OUTDIR, "samples.txt")
    with open(samples, "w", encoding="utf-8") as fh:
        for key, _ in cases:
            fh.write("".join(chr(c) for c in key) + "\n")

    print("pushing probe and %d samples" % len(cases))
    sh("push", os.path.join(OUTDIR, "emojiprobe2"), "/tmp/emojiprobe2")
    sh("push", samples, "/tmp/samples.txt")
    sh("chmod +x /tmp/emojiprobe2")

    print("running on device")
    res = sh("/tmp/emojiprobe2 /tmp/samples.txt")
    if res.returncode != 0:
        print(res.stdout[-2000:])
        print(res.stderr[-2000:])
        return 1

    header = ""
    rows = {}
    for line in res.stdout.split("\n"):
        line = line.strip()
        if line.startswith("#"):
            header = line
            continue
        parts = line.split("\t")
        if len(parts) != 4:
            continue
        idx = int(parts[0])
        rows[idx] = (int(parts[1]), parts[2],
                     [int(x) for x in parts[3].split(",") if x != ""])

    print(header)
    ok, bad = 0, []
    per_status = Counter()
    for i, (key, target) in enumerate(cases):
        want = gid[gname(target)]
        got = rows.get(i)
        if got is None:
            bad.append((key, want, None, "missing"))
            per_status[(status_of.get(key, "?"), False)] += 1
            continue
        n, fontkind, glyphs = got
        if glyphs == [want] and fontkind == "emoji":
            ok += 1
            per_status[(status_of.get(key, "?"), True)] += 1
        else:
            bad.append((key, want, glyphs, fontkind))
            per_status[(status_of.get(key, "?"), False)] += 1

    seq_total = sum(1 for k, _ in cases if len(k) > 1)
    seq_bad = sum(1 for b in bad if len(b[0]) > 1)
    fq_total = sum(1 for k, _ in cases
                   if len(k) > 1 and status_of.get(k) == "fully-qualified")
    fq_bad = sum(1 for b in bad if len(b[0]) > 1
                 and status_of.get(b[0]) == "fully-qualified")

    print("\ndevice CoreText composition, Unicode Emoji %s" % ver)
    print("  all emoji-test forms : %d/%d" % (ok, len(cases)))
    print("  RGI sequences (FQ)   : %d/%d" % (fq_total - fq_bad, fq_total))
    print("  every multi-cp form  : %d/%d" % (seq_total - seq_bad, seq_total))
    print("  single scalars       : %d/%d"
          % ((len(cases) - seq_total) - (len(bad) - seq_bad), len(cases) - seq_total))
    for (status, good), n in sorted(per_status.items()):
        print("    %-20s %-5s %d" % (status, "ok" if good else "FAIL", n))
    if bad:
        print("\nfailures (%d), first 40:" % len(bad))
        for key, want, glyphs, kind in bad[:40]:
            print("  %-44s want gid %-6d got %s (%s)"
                  % (" ".join("%04X" % c for c in key), want, glyphs, kind))
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main())
