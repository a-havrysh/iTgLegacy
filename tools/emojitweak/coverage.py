import os
import subprocess
import sys
from collections import Counter

import emojidata as E

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "cache")
FONT = os.path.join(HERE, "out", "AppleColorEmoji.ttf")


def gname(cps):
    return "_".join("u%04X" % c for c in cps)


def shape_many(font, texts, chunk=500):
    results = []
    for i in range(0, len(texts), chunk):
        part = texts[i:i + chunk]
        proc = subprocess.run(
            ["hb-shape", "--no-positions", "--no-clusters", "--font-funcs=ot",
             "--text-file=-", font],
            input="\n".join(part), capture_output=True, text=True)
        lines = proc.stdout.split("\n")
        lines = [l for l in lines if l.strip() != ""]
        if len(lines) != len(part):
            raise RuntimeError("hb-shape returned %d lines for %d inputs"
                               % (len(lines), len(part)))
        for line in lines:
            results.append(line.strip().strip("[]").split("|"))
    return results


def main():
    font = sys.argv[1] if len(sys.argv) > 1 else FONT
    test_path, ucd, ver = E.fetch_emoji_test(CACHE)
    entries = E.parse_emoji_test(test_path)
    identities, aliases = E.build_identities(entries)
    idset = {c for c, _, _ in identities}

    cases = []
    for key, target in sorted(aliases.items()):
        cases.append((key, target, gname(target)))

    texts = ["".join(chr(c) for c in key) for key, _, _ in cases]
    got = shape_many(font, texts)

    ok, bad = 0, []
    by_status = Counter()
    status_of = {}
    for cps, status, _ in entries:
        status_of.setdefault(cps, status)

    for (key, target, want), g in zip(cases, got):
        if g == [want]:
            ok += 1
            by_status[(status_of.get(key, "?"), True)] += 1
        else:
            bad.append((key, want, g))
            by_status[(status_of.get(key, "?"), False)] += 1

    seq_cases = [(k, t, w) for k, t, w in cases if len(k) > 1]
    seq_bad = [b for b in bad if len(b[0]) > 1]
    fq_seq = [(k, t, w) for k, t, w in cases
              if len(k) > 1 and status_of.get(k) == "fully-qualified"]
    fq_bad = [b for b in bad if len(b[0]) > 1
              and status_of.get(b[0]) == "fully-qualified"]

    print("font:", font)
    print("Unicode Emoji %s (UCD %s)" % (ver, ucd))
    print("emoji-test.txt lines checked: %d" % len(cases))
    print("  all forms          : %d/%d ok" % (ok, len(cases)))
    print("  RGI sequences (FQ) : %d/%d ok" % (len(fq_seq) - len(fq_bad), len(fq_seq)))
    print("  every multi-cp form: %d/%d ok" % (len(seq_cases) - len(seq_bad),
                                               len(seq_cases)))
    print("  single scalars     : %d/%d ok"
          % (len(cases) - len(seq_cases) - (len(bad) - len(seq_bad)),
             len(cases) - len(seq_cases)))
    for (status, good), n in sorted(by_status.items()):
        print("    %-20s %-5s %d" % (status, "ok" if good else "FAIL", n))
    if bad:
        print("\nfailures (%d):" % len(bad))
        for key, want, g in bad[:40]:
            print("  %-40s want %-40s got %s"
                  % (" ".join("%04X" % c for c in key), want, g))
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main())
