#!/bin/sh
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
OUTDIR="$HERE/out"
STAGE="$HERE/work/deb"
TEMPLATES="$HERE/package"

DYLIB_SRC="$OUTDIR/EmojiKeyboard.dylib"
PREP_SRC="$OUTDIR/emojipaletteprep"
PALETTE_SRC="$OUTDIR/palette.plist"
FILTER_SRC="$TEMPLATES/EmojiKeyboard.plist"

PKGDIRNAME=emojikeyboard
PKGDIR="/var/lib/$PKGDIRNAME"
PREFS=$(sed -n 's/^#define EK_PREFS "\(.*\)"$/\1/p' "$HERE/src/EKPalette.h")
SUBDIR="/Library/MobileSubstrate/DynamicLibraries"
DYLIB="$SUBDIR/EmojiKeyboard.dylib"
FILTER="$SUBDIR/EmojiKeyboard.plist"

PACKAGE=${EMOJIKEYBOARD_PACKAGE:-com.havrysh.emojikeyboard}
NAME=${EMOJIKEYBOARD_NAME:-Modern Emoji Keyboard}
AUTHOR=${EMOJIKEYBOARD_AUTHOR:-Oleksandr Havrysh <kesha1511@gmail.com>}
MAINTAINER=${EMOJIKEYBOARD_MAINTAINER:-$AUTHOR}
HOMEPAGE=${EMOJIKEYBOARD_HOMEPAGE:-}
DEPICTION=${EMOJIKEYBOARD_DEPICTION:-}
FONTPACKAGE=${EMOJIKEYBOARD_FONTPACKAGE:-com.havrysh.moderncoloremoji}
FONTFILE=${EMOJIKEYBOARD_FONTFILE:-/var/lib/emojitweak/AppleColorEmoji.ttf}
FONTDEP=${EMOJIKEYBOARD_FONTDEP:-depends}

die() { echo "mkdeb: $*" >&2; exit 1; }

command -v dpkg-deb >/dev/null 2>&1 || die "dpkg-deb not found (brew install dpkg)"
command -v python3 >/dev/null 2>&1 || die "python3 not found"
for f in "$DYLIB_SRC" "$PREP_SRC" "$PALETTE_SRC" "$FILTER_SRC"; do
    [ -f "$f" ] || die "$f missing -- run: make"
done
[ -n "$PREFS" ] || die "could not read EK_PREFS out of $HERE/src/EKPalette.h"

command -v otool >/dev/null 2>&1 && {
    otool -h "$DYLIB_SRC" >/dev/null 2>&1 || die "$DYLIB_SRC is not a Mach-O file"
    lipo -info "$DYLIB_SRC" | grep -q armv7 || die "$DYLIB_SRC has no armv7 slice"
    lipo -info "$PREP_SRC" | grep -q armv7 || die "$PREP_SRC has no armv7 slice"
    otool -L "$DYLIB_SRC" | grep -q UIKit && die "$DYLIB_SRC links UIKit; it must not"
} || true

meta=$(python3 - "$PALETTE_SRC" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as fh:
    root = plistlib.load(fh)
categories = root["categories"]
print(root["unicode"])
print(sum(len(v) for v in categories.values()))
print("on" if root.get("skinTones") else "off")
PY
)
EMOJI_VERSION=$(echo "$meta" | sed -n 1p)
CANDIDATES=$(echo "$meta" | sed -n 2p)
SKIN_TONES=$(echo "$meta" | sed -n 3p)
[ -n "$EMOJI_VERSION" ] || die "could not read the emoji version out of $PALETTE_SRC"

DEPENDS="firmware (>= 6.0), mobilesubstrate"
RECOMMENDS=""
case "$FONTDEP" in
depends)
    DEPENDS="$DEPENDS, $FONTPACKAGE (>= $EMOJI_VERSION)" ;;
recommends)
    RECOMMENDS="$FONTPACKAGE (>= $EMOJI_VERSION)" ;;
none)
    ;;
*)
    die "EMOJIKEYBOARD_FONTDEP must be depends, recommends or none (got '$FONTDEP')" ;;
esac

STOCK_COUNT=$(python3 - "$HERE/evidence/ios6_emoji_tables.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
print(sum(c.get("total_emoji", 0) for c in data["categories"]))
PY
)

if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
    EPOCH=$SOURCE_DATE_EPOCH
else
    EPOCH=$(python3 -c 'import calendar,time; t=time.gmtime(); print(calendar.timegm((t.tm_year,t.tm_mon,t.tm_mday,0,0,0,0,0,0)))')
fi
export SOURCE_DATE_EPOCH=$EPOCH
BUILD_DATE=$(python3 -c "import time,sys; print(time.strftime('%Y%m%d', time.gmtime(int(sys.argv[1]))))" "$EPOCH")
TOUCH_STAMP=$(python3 -c "import time,sys; print(time.strftime('%Y%m%d%H%M.%S', time.gmtime(int(sys.argv[1]))))" "$EPOCH")

VERSION=${EMOJIKEYBOARD_VERSION:-$EMOJI_VERSION-$BUILD_DATE}
DEB="$OUTDIR/${PACKAGE}_${VERSION}_iphoneos-arm.deb"

kb() { python3 -c 'import os,sys; print((os.path.getsize(sys.argv[1])+1023)//1024)' "$1"; }
INSTALLED_SIZE=$(( $(kb "$DYLIB_SRC") + $(kb "$PREP_SRC") + $(kb "$PALETTE_SRC") + \
                   $(kb "$FILTER_SRC") + 3 ))

echo "mkdeb: $PACKAGE $VERSION"
echo "  palette   Unicode Emoji $EMOJI_VERSION, $CANDIDATES candidates, skin tones $SKIN_TONES"
echo "  stock     $STOCK_COUNT iOS 6 slots already in the palette"
echo "  font      $FONTPACKAGE (>= $EMOJI_VERSION), as a $FONTDEP relationship"
echo "  payload   $DYLIB, $FILTER, $PKGDIR"
echo "  epoch     $EPOCH ($BUILD_DATE, UTC)"

rm -rf "$STAGE"
ROOT="$STAGE/root"
mkdir -p "$ROOT/DEBIAN" "$ROOT$PKGDIR" "$ROOT$SUBDIR"

COPYFILE_DISABLE=1
export COPYFILE_DISABLE
cp "$DYLIB_SRC" "$ROOT$DYLIB"
cp "$FILTER_SRC" "$ROOT$FILTER"
cp "$PREP_SRC" "$ROOT$PKGDIR/emojipaletteprep"
cp "$PALETTE_SRC" "$ROOT$PKGDIR/palette.plist"
cp "$TEMPLATES/respring" "$ROOT$PKGDIR/respring"

esc() { printf '%s' "$1" | sed 's/[\\&|]/\\&/g'; }

subst() {
    sed \
        -e "s|@PACKAGE@|$(esc "$PACKAGE")|g" \
        -e "s|@NAME@|$(esc "$NAME")|g" \
        -e "s|@VERSION@|$(esc "$VERSION")|g" \
        -e "s|@AUTHOR@|$(esc "$AUTHOR")|g" \
        -e "s|@MAINTAINER@|$(esc "$MAINTAINER")|g" \
        -e "s|@HOMEPAGE@|$(esc "$HOMEPAGE")|g" \
        -e "s|@EMOJI_VERSION@|$(esc "$EMOJI_VERSION")|g" \
        -e "s|@CANDIDATES@|$CANDIDATES|g" \
        -e "s|@STOCK_COUNT@|$STOCK_COUNT|g" \
        -e "s|@INSTALLED_SIZE@|$INSTALLED_SIZE|g" \
        -e "s|@PKGDIR@|$(esc "$PKGDIR")|g" \
        -e "s|@PKGDIRNAME@|$(esc "$PKGDIRNAME")|g" \
        -e "s|@PREFS@|$(esc "$PREFS")|g" \
        -e "s|@DYLIB@|$(esc "$DYLIB")|g" \
        -e "s|@FILTER@|$(esc "$FILTER")|g" \
        -e "s|@FONTFILE@|$(esc "$FONTFILE")|g" \
        -e "s|@FONTPACKAGE@|$(esc "$FONTPACKAGE")|g" \
        -e "s|@DEPENDS@|$(esc "$DEPENDS")|g" \
        -e "s|@RECOMMENDS@|$(esc "$RECOMMENDS")|g" \
        "$1"
}

subst "$TEMPLATES/refresh" > "$ROOT$PKGDIR/refresh"
sh -n "$ROOT$PKGDIR/refresh" || die "refresh is not valid shell"

subst "$TEMPLATES/control.in" > "$ROOT/DEBIAN/control"
[ -n "$HOMEPAGE" ] || sed -i.bak '/^Homepage: *$/d' "$ROOT/DEBIAN/control"
[ -n "$RECOMMENDS" ] || sed -i.bak '/^Recommends: *$/d' "$ROOT/DEBIAN/control"
rm -f "$ROOT/DEBIAN/control.bak"
[ -z "$DEPICTION" ] || echo "Depiction: $DEPICTION" >> "$ROOT/DEBIAN/control"

for s in postinst postrm; do
    subst "$TEMPLATES/$s" > "$ROOT/DEBIAN/$s"
    chmod 755 "$ROOT/DEBIAN/$s"
    sh -n "$ROOT/DEBIAN/$s" || die "$s is not valid shell"
done
grep -q '@[A-Z_]*@' "$ROOT/DEBIAN"/* && die "unsubstituted placeholder left in DEBIAN/" || true

md5here() {
    if command -v md5 >/dev/null 2>&1; then md5 -q "$1"; else md5sum "$1" | cut -d' ' -f1; fi
}
: > "$ROOT/DEBIAN/md5sums"
( cd "$ROOT" && find . -type f -not -path './DEBIAN/*' | sed 's|^\./||' | sort ) | while read -r rel; do
    echo "$(md5here "$ROOT/$rel")  $rel" >> "$ROOT/DEBIAN/md5sums"
done

chmod 755 "$ROOT$PKGDIR/respring" "$ROOT$PKGDIR/emojipaletteprep" \
          "$ROOT$PKGDIR/refresh"
chmod 644 "$ROOT$DYLIB" "$ROOT$FILTER" "$ROOT$PKGDIR/palette.plist" \
          "$ROOT/DEBIAN/control" "$ROOT/DEBIAN/md5sums"
find "$ROOT" -type d -exec chmod 755 {} +

command -v xattr >/dev/null 2>&1 && xattr -cr "$ROOT" 2>/dev/null || true
find "$ROOT" -name '._*' -delete 2>/dev/null || true
find "$ROOT" -exec touch -h -t "$TOUCH_STAMP" {} +

mkdir -p "$OUTDIR"
rm -f "$DEB"
dpkg-deb --root-owner-group --uniform-compression -Zgzip -z9 --build "$ROOT" "$DEB" >/dev/null

echo ""
dpkg-deb --info "$DEB" | sed -n '1,3p'
echo "  $DEB"
python3 -c '
import hashlib, os, sys
p = sys.argv[1]
h = hashlib.sha256(open(p, "rb").read()).hexdigest()
print("  %.2f MB  sha256 %s" % (os.path.getsize(p) / 1048576.0, h))
' "$DEB"
