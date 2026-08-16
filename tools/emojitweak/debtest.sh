#!/bin/sh
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
IPAD=${IPAD:-192.168.18.217}
export IPAD
SH="$HERE/ipad.sh"
PACKAGE=${EMOJITWEAK_PACKAGE:-com.havrysh.moderncoloremoji}
SYSFONT=/System/Library/Fonts/Cache/AppleColorEmoji.ttf
PKGDIR=/var/lib/emojitweak
PROBE=/tmp/emojiprobe2
SAMPLES=/tmp/debtest-samples.txt

die() { echo "debtest: $*" >&2; exit 1; }

write_samples() {
    python3 - "$HERE/work/debtest-samples.txt" <<'PY'
import sys, io
cases = [
    ("grinning face",              [0x1F600]),
    ("woman, medium skin",         [0x1F469, 0x1F3FD]),
    ("family: man woman girl",     [0x1F468, 0x200D, 0x1F469, 0x200D, 0x1F467]),
    ("flag: Ukraine",              [0x1F1FA, 0x1F1E6]),
    ("keycap: 1",                  [0x0031, 0xFE0F, 0x20E3]),
    ("face with bags (Emoji 16)",  [0x1FAE9]),
    ("firefighter",                [0x1F9D1, 0x200D, 0x1F692]),
    ("root vegetable (Emoji 16)",  [0x1FADC]),
    ("kiss: woman, man",           [0x1F469, 0x200D, 0x2764, 0xFE0F, 0x200D,
                                    0x1F48B, 0x200D, 0x1F468]),
    ("flag: Scotland (tag flag)",  [0x1F3F4, 0xE0067, 0xE0062, 0xE0073,
                                    0xE0063, 0xE0074, 0xE007F]),
]
with io.open(sys.argv[1], "w", encoding="utf-8") as fh:
    for _, cps in cases:
        fh.write("".join(chr(c) for c in cps) + "\n")
with io.open(sys.argv[1] + ".names", "w", encoding="utf-8") as fh:
    for name, cps in cases:
        fh.write("%s\t%s\n" % (name, " ".join("%04X" % c for c in cps)))
PY
}

report() {
    echo "--- $1"
    "$SH" "ls -l $SYSFONT 2>/dev/null || echo 'NO FONT AT $SYSFONT'"
    "$SH" "dpkg -s $PACKAGE 2>/dev/null | grep -E '^(Package|Status|Version):' || echo 'package not installed'"
    "$SH" "ls -l $PKGDIR 2>/dev/null || echo '$PKGDIR absent'"
    echo "--- CoreText sees:"
    "$SH" "$PROBE $SAMPLES /tmp/debtest-$2.png 48 5" > "$HERE/work/probe-$2.txt" 2>&1 || true
    python3 - "$HERE/work/probe-$2.txt" "$HERE/work/debtest-samples.txt.names" <<'PY'
import sys
lines = [l.rstrip("\n") for l in open(sys.argv[1], encoding="utf-8", errors="replace")]
names = [l.rstrip("\n").split("\t") for l in open(sys.argv[2], encoding="utf-8")]
for l in lines:
    if l.startswith("#"):
        print("   ", l)
for l in lines:
    if l.startswith("#") or "\t" not in l:
        continue
    p = l.split("\t")
    if len(p) != 4:
        continue
    i = int(p[0])
    nm = names[i][0] if i < len(names) else "?"
    n = int(p[1])
    verdict = "one glyph" if n == 1 else "%d glyphs" % n
    print("    %-28s %-9s %-6s gids %s" % (nm, verdict, p[2], p[3]))
PY
}

case "${1:-}" in
prepare)
    mkdir -p "$HERE/work"
    write_samples
    [ -x "$HERE/out/emojiprobe2" ] || die "out/emojiprobe2 missing"
    "$SH" push "$HERE/out/emojiprobe2" "$PROBE"
    "$SH" push "$HERE/work/debtest-samples.txt" "$SAMPLES"
    "$SH" "chmod +x $PROBE"
    ;;
status)
    report "current state" "${2:-now}"
    ;;
install)
    deb=$(ls -t "$HERE/out/"*.deb 2>/dev/null | sed -n 1p) || true
    [ -n "${deb:-}" ] || die "no .deb in out/ -- run ./mkdeb.sh"
    echo "debtest: pushing $(basename "$deb")"
    "$SH" push "$deb" "/tmp/$(basename "$deb")"
    "$SH" "${EMOJITWEAK_NO_RESPRING:+EMOJITWEAK_NO_RESPRING=1 }dpkg -i /tmp/$(basename "$deb")"
    ;;
remove)
    "$SH" "${EMOJITWEAK_NO_RESPRING:+EMOJITWEAK_NO_RESPRING=1 }dpkg -r $PACKAGE"
    ;;
purge)
    "$SH" "${EMOJITWEAK_NO_RESPRING:+EMOJITWEAK_NO_RESPRING=1 }dpkg -P $PACKAGE"
    ;;
pull-png)
    "$SH" pull "/tmp/debtest-${2:-now}.png" "$HERE/work/debtest-${2:-now}.png"
    ;;
*)
    echo "usage: debtest.sh {prepare|status [tag]|install|remove|purge|pull-png [tag]}" >&2
    exit 2
    ;;
esac
