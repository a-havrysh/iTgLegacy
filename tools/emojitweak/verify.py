import subprocess
import sys


def shape(font_path, cps):
    text = "".join(chr(c) for c in cps)
    out = subprocess.run(["hb-shape", "--no-positions", "--no-clusters",
                          "--font-funcs=ot", font_path, text],
                         check=True, capture_output=True, text=True)
    return out.stdout.strip().strip("[]").split("|") if out.stdout.strip() else []


def check(font_path, cases, context=False):
    ok, bad = 0, []
    for cps, expect in cases:
        got = shape(font_path, cps)
        if got == [expect]:
            ok += 1
        else:
            bad.append((cps, expect, got))
    return ok, bad


def check_batch(font_path, cases, chunk=400):
    ok, bad = 0, []
    items = list(cases)
    for i in range(0, len(items), chunk):
        part = items[i:i + chunk]
        text = "\n".join("".join(chr(c) for c in cps) for cps, _ in part)
        proc = subprocess.run(["hb-shape", "--no-positions", "--no-clusters",
                               "--font-funcs=ot", "--text-file=-", font_path],
                              input=text, capture_output=True, text=True)
        lines = proc.stdout.strip().split("\n")
        if len(lines) != len(part):
            for cps, expect in part:
                got = shape(font_path, cps)
                if got == [expect]:
                    ok += 1
                else:
                    bad.append((cps, expect, got))
            continue
        for (cps, expect), line in zip(part, lines):
            got = line.strip().strip("[]").split("|") if line.strip() else []
            if got == [expect]:
                ok += 1
            else:
                bad.append((cps, expect, got))
    return ok, bad


def fmt(cps):
    return " ".join("%04X" % c for c in cps)


if __name__ == "__main__":
    path = sys.argv[1]
    from smoketest import CASES, name_for
    cases = [(c, name_for(c)) for c in CASES]
    ok, bad = check(path, cases)
    print("shaped ok:", ok, "of", len(cases))
    for cps, expect, got in bad:
        print("  FAIL", fmt(cps), "expected", expect, "got", got)
