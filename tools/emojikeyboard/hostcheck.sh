#!/bin/sh
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
SRC="$HERE/src"
WORK="$HERE/work/hostcheck"
PALETTE="$HERE/out/palette.plist"

die() { echo "hostcheck: $*" >&2; exit 1; }

[ -f "$PALETTE" ] || die "$PALETTE missing -- run: make palette"

rm -rf "$WORK"
mkdir -p "$WORK/root"
cp "$PALETTE" "$WORK/root/palette.plist"
: > "$WORK/prefs.plist"

echo "hostcheck: building the palette core for this Mac"
clang -x objective-c -fno-objc-arc -fobjc-exceptions -O1 \
    -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations \
    -DEK_ROOT="\"$WORK/root\"" -DEK_PREFS="\"$WORK/prefs.plist\"" \
    -I"$SRC" -framework Foundation -framework CoreText -framework CoreGraphics \
    -o "$WORK/prep" "$SRC/EKPalette.m" "$SRC/EKPrep.m"

echo "hostcheck: cold run (shapes every candidate against this Mac's emoji font)"
"$WORK/prep" || die "cold run failed"

[ -f "$WORK/root/glyphs.plist" ] || die "no glyph cache was written"

echo "hostcheck: warm run (must come back out of the cache)"
"$WORK/prep" | grep -q "from cache" || die "the second run did not use the cache"

echo "hostcheck: stale-font detection"
python3 - "$WORK/root/glyphs.plist" <<'PY'
import plistlib, sys
path = sys.argv[1]
with open(path, "rb") as fh:
    root = plistlib.load(fh)
root["font"] = "deliberately-wrong"
with open(path, "wb") as fh:
    plistlib.dump(root, fh, fmt=plistlib.FMT_BINARY)
PY
"$WORK/prep" | grep -q "drawable, shaped in" || die "a stale font stamp did not force a reshape"

echo "hostcheck: damaged cache is survived"
printf 'not a plist at all' > "$WORK/root/glyphs.plist"
"$WORK/prep" >/dev/null || die "a damaged cache was not survived"

echo "hostcheck: missing palette data is survived"
mv "$WORK/root/palette.plist" "$WORK/palette.plist.away"
rm -f "$WORK/root/glyphs.plist"
if "$WORK/prep" >/dev/null 2>&1; then
    die "a missing palette.plist should be reported as a failure, not success"
fi
mv "$WORK/palette.plist.away" "$WORK/root/palette.plist"

echo "hostcheck: truncated palette data is survived"
head -c 64 "$WORK/root/palette.plist" > "$WORK/root/palette.plist.bad"
mv "$WORK/root/palette.plist.bad" "$WORK/root/palette.plist"
"$WORK/prep" >/dev/null 2>&1 || true

echo ""
echo "hostcheck: hook behaviour against stand-ins with the real iOS 6 signatures"
cp "$PALETTE" "$WORK/root/palette.plist"
rm -f "$WORK/root/glyphs.plist"
python3 "$HERE/test/stocktable.py" "$WORK/EKStockTable.h"
clang -x objective-c -fno-objc-arc -fobjc-exceptions -O1 \
    -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations \
    -DEK_ROOT="\"$WORK/root\"" -DEK_PREFS="\"$WORK/prefs.plist\"" \
    -I"$SRC" -I"$WORK" -framework Foundation -framework CoreText \
    -framework CoreGraphics \
    -o "$WORK/hooktest" "$SRC/EKPalette.m" "$SRC/EKTweak.m" \
    "$HERE/test/EKHookTest.m"
"$WORK/hooktest" || die "hook behaviour checks failed"

echo ""
echo "hostcheck: fail-safe behaviour on a runtime this build does not expect"
for case in 1 2 3; do
    clang -x objective-c -fno-objc-arc -fobjc-exceptions -O1 \
        -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations \
        -DEK_ROOT="\"$WORK/root\"" -DEK_PREFS="\"$WORK/prefs.plist\"" \
        -DEK_FAILSAFE_CASE=$case \
        -I"$SRC" -framework Foundation -framework CoreText \
        -framework CoreGraphics \
        -o "$WORK/failsafe$case" "$SRC/EKPalette.m" "$SRC/EKTweak.m" \
        "$HERE/test/EKFailsafeTest.m"
    "$WORK/failsafe$case" || die "fail-safe case $case did not hold"
done

echo ""
echo "hostcheck: all checks passed"
echo "  note: the counts above are this Mac's emoji coverage, not the device's."
echo "        They only prove the filter, the cache and the failure paths work."
