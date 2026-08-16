#!/bin/sh
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
OUTDIR="$HERE/out"
STAGE="$HERE/work/deb"
FONT="$OUTDIR/AppleColorEmoji.ttf"
COPYING="$OUTDIR/COPYING"
TEMPLATES="$HERE/package"

PKGDIRNAME=emojitweak
PKGDIR="/var/lib/$PKGDIRNAME"
SYSFONT="/System/Library/Fonts/Cache/AppleColorEmoji.ttf"
SYSDIR="/System/Library/Fonts/Cache"
MARGIN_KB=${EMOJITWEAK_MARGIN_KB:-4096}

PACKAGE=${EMOJITWEAK_PACKAGE:-com.havrysh.moderncoloremoji}
NAME=${EMOJITWEAK_NAME:-Modern Color Emoji}
AUTHOR=${EMOJITWEAK_AUTHOR:-Oleksandr Havrysh <kesha1511@gmail.com>}
MAINTAINER=${EMOJITWEAK_MAINTAINER:-$AUTHOR}
HOMEPAGE=${EMOJITWEAK_HOMEPAGE:-}
DEPICTION=${EMOJITWEAK_DEPICTION:-}

die() { echo "mkdeb: $*" >&2; exit 1; }

command -v dpkg-deb >/dev/null 2>&1 || die "dpkg-deb not found (brew install dpkg)"
command -v python3 >/dev/null 2>&1 || die "python3 not found"
[ -f "$FONT" ] || die "$FONT missing -- run ./build.py first"
[ -f "$COPYING" ] || die "$COPYING missing -- run ./build.py first"

meta=$(python3 - "$FONT" <<'PY'
import sys
from fontTools.ttLib import TTFont
font = TTFont(sys.argv[1], lazy=True)
version = next(str(r) for r in font["name"].names if r.nameID == 5)
emoji, _, twemoji = version.partition(";twemoji-")
strike = font["sbix"].strikes[sorted(font["sbix"].strikes)[0]]
imaged = sum(1 for g in strike.glyphs.values() if g.imageData)
print(emoji.strip())
print(twemoji.strip() or "unknown")
print(imaged)
PY
)
EMOJI_VERSION=$(echo "$meta" | sed -n 1p)
TWEMOJI_VERSION=$(echo "$meta" | sed -n 2p)
GLYPH_COUNT=$(echo "$meta" | sed -n 3p)
[ -n "$EMOJI_VERSION" ] || die "could not read the emoji version out of $FONT"

if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
    EPOCH=$SOURCE_DATE_EPOCH
else
    EPOCH=$(python3 -c 'import calendar,time; t=time.gmtime(); print(calendar.timegm((t.tm_year,t.tm_mon,t.tm_mday,0,0,0,0,0,0)))')
fi
export SOURCE_DATE_EPOCH=$EPOCH
BUILD_DATE=$(python3 -c "import time,sys; print(time.strftime('%Y%m%d', time.gmtime(int(sys.argv[1]))))" "$EPOCH")
TOUCH_STAMP=$(python3 -c "import time,sys; print(time.strftime('%Y%m%d%H%M.%S', time.gmtime(int(sys.argv[1]))))" "$EPOCH")

VERSION=${EMOJITWEAK_VERSION:-$EMOJI_VERSION-$BUILD_DATE}

FONT_BYTES=$(python3 -c 'import os,sys; print(os.path.getsize(sys.argv[1]))' "$FONT")
FONT_KB=$(( (FONT_BYTES + 1023) / 1024 ))
REQUIRED_MB=$(( (FONT_KB + MARGIN_KB) / 1024 ))
COPYING_KB=$(python3 -c 'import os,sys; print((os.path.getsize(sys.argv[1])+1023)//1024)' "$COPYING")
INSTALLED_SIZE=$(( FONT_KB + COPYING_KB + 1 ))

DEB="$OUTDIR/${PACKAGE}_${VERSION}_iphoneos-arm.deb"

echo "mkdeb: $PACKAGE $VERSION"
echo "  emoji     Unicode $EMOJI_VERSION / twemoji $TWEMOJI_VERSION / $GLYPH_COUNT images"
echo "  payload   $FONT_KB KB -> $PKGDIR/AppleColorEmoji.ttf"
echo "  needs     $REQUIRED_MB MB free on $SYSDIR at install time"
echo "  epoch     $EPOCH ($BUILD_DATE, UTC)"

rm -rf "$STAGE"
ROOT="$STAGE/root"
mkdir -p "$ROOT/DEBIAN" "$ROOT$PKGDIR"

COPYFILE_DISABLE=1
export COPYFILE_DISABLE
cp "$FONT" "$ROOT$PKGDIR/AppleColorEmoji.ttf"
cp "$COPYING" "$ROOT$PKGDIR/COPYING"
cp "$TEMPLATES/respring" "$ROOT$PKGDIR/respring"

esc() {
    printf '%s' "$1" | sed 's/[\\&|]/\\&/g'
}

subst() {
    sed \
        -e "s|@PACKAGE@|$(esc "$PACKAGE")|g" \
        -e "s|@NAME@|$(esc "$NAME")|g" \
        -e "s|@VERSION@|$(esc "$VERSION")|g" \
        -e "s|@AUTHOR@|$(esc "$AUTHOR")|g" \
        -e "s|@MAINTAINER@|$(esc "$MAINTAINER")|g" \
        -e "s|@HOMEPAGE@|$(esc "$HOMEPAGE")|g" \
        -e "s|@DEPICTION@|$(esc "$DEPICTION")|g" \
        -e "s|@EMOJI_VERSION@|$(esc "$EMOJI_VERSION")|g" \
        -e "s|@TWEMOJI_VERSION@|$(esc "$TWEMOJI_VERSION")|g" \
        -e "s|@GLYPH_COUNT@|$GLYPH_COUNT|g" \
        -e "s|@INSTALLED_SIZE@|$INSTALLED_SIZE|g" \
        -e "s|@FONT_BYTES@|$FONT_BYTES|g" \
        -e "s|@FONT_KB@|$FONT_KB|g" \
        -e "s|@MARGIN_KB@|$MARGIN_KB|g" \
        -e "s|@REQUIRED_MB@|$REQUIRED_MB|g" \
        -e "s|@PKGDIR@|$(esc "$PKGDIR")|g" \
        -e "s|@PKGDIRNAME@|$(esc "$PKGDIRNAME")|g" \
        -e "s|@SYSFONT@|$(esc "$SYSFONT")|g" \
        -e "s|@SYSDIR@|$(esc "$SYSDIR")|g" \
        "$1"
}

subst "$TEMPLATES/control.in" > "$ROOT/DEBIAN/control"
[ -n "$HOMEPAGE" ] || sed -i.bak '/^Homepage: *$/d' "$ROOT/DEBIAN/control"
rm -f "$ROOT/DEBIAN/control.bak"
[ -z "$DEPICTION" ] || echo "Depiction: $DEPICTION" >> "$ROOT/DEBIAN/control"

for s in preinst postinst postrm; do
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

chmod 755 "$ROOT$PKGDIR/respring"
chmod 644 "$ROOT$PKGDIR/AppleColorEmoji.ttf" "$ROOT$PKGDIR/COPYING" \
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
