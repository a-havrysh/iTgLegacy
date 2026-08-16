#!/bin/sh
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
OUTDIR="$HERE/out"
STAGE="$HERE/work/deb"
FONT_1X_NAME=AppleColorEmoji.ttf
FONT_2X_NAME=AppleColorEmoji@2x.ttf
FONT_1X="$OUTDIR/$FONT_1X_NAME"
FONT_2X="$OUTDIR/$FONT_2X_NAME"
COPYING="$OUTDIR/COPYING"
TEMPLATES="$HERE/package"

PKGDIRNAME=emojitweak
PKGDIR=${EMOJITWEAK_PKGDIR:-/var/lib/$PKGDIRNAME}
SYSDIR=${EMOJITWEAK_SYSDIR:-/System/Library/Fonts/Cache}
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
[ -f "$FONT_1X" ] || die "$FONT_1X missing -- run ./build.py first"
[ -f "$FONT_2X" ] || die "$FONT_2X missing -- run ./build.py first"
[ -f "$COPYING" ] || die "$COPYING missing -- run ./build.py first"

meta=$(python3 - "$FONT_1X" "$FONT_2X" <<'PYEOF'
import sys
from fontTools.ttLib import TTFont

versions = set()
strikes = []
imaged = []
for path in sys.argv[1:]:
    font = TTFont(path, lazy=True)
    versions.add(next(str(r) for r in font["name"].names if r.nameID == 5))
    ppems = sorted(font["sbix"].strikes)
    strikes.append("/".join(str(p) for p in ppems))
    first = font["sbix"].strikes[ppems[0]]
    imaged.append(sum(1 for g in first.glyphs.values() if g.imageData))

if len(versions) != 1:
    raise SystemExit("the payload fonts disagree on version: %s" % sorted(versions))
if len(set(imaged)) != 1:
    raise SystemExit("the payload fonts have different glyph counts: %s" % imaged)

emoji, _, twemoji = versions.pop().partition(";twemoji-")
print(emoji.strip())
print(twemoji.strip() or "unknown")
print(imaged[0])
print(strikes[0])
print(strikes[1])
PYEOF
) || die "could not read metadata out of the payload fonts"
EMOJI_VERSION=$(echo "$meta" | sed -n 1p)
TWEMOJI_VERSION=$(echo "$meta" | sed -n 2p)
GLYPH_COUNT=$(echo "$meta" | sed -n 3p)
STRIKES_1X=$(echo "$meta" | sed -n 4p)
STRIKES_2X=$(echo "$meta" | sed -n 5p)
[ -n "$STRIKES_1X" ] || die "could not read the strike list out of $FONT_1X"
[ -n "$STRIKES_2X" ] || die "could not read the strike list out of $FONT_2X"
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

bytes_of() { python3 -c 'import os,sys; print(os.path.getsize(sys.argv[1]))' "$1"; }

FONT_1X_BYTES=$(bytes_of "$FONT_1X")
FONT_2X_BYTES=$(bytes_of "$FONT_2X")
FONT_1X_KB=$(( (FONT_1X_BYTES + 1023) / 1024 ))
FONT_2X_KB=$(( (FONT_2X_BYTES + 1023) / 1024 ))
if [ "$FONT_1X_KB" -ge "$FONT_2X_KB" ]; then MAX_FONT_KB=$FONT_1X_KB; else MAX_FONT_KB=$FONT_2X_KB; fi
REQUIRED_MB=$(( (MAX_FONT_KB + MARGIN_KB) / 1024 ))
COPYING_KB=$(( ( $(bytes_of "$COPYING") + 1023 ) / 1024 ))
INSTALLED_SIZE=$(( FONT_1X_KB + FONT_2X_KB + COPYING_KB + 1 ))

DEB="$OUTDIR/${PACKAGE}_${VERSION}_iphoneos-arm.deb"

echo "mkdeb: $PACKAGE $VERSION"
echo "  emoji     Unicode $EMOJI_VERSION / twemoji $TWEMOJI_VERSION / $GLYPH_COUNT images"
echo "  payload   $FONT_1X_KB KB strikes $STRIKES_1X -> $SYSDIR/$FONT_1X_NAME"
echo "  payload   $FONT_2X_KB KB strikes $STRIKES_2X -> $SYSDIR/$FONT_2X_NAME"
echo "  needs     $REQUIRED_MB MB free on $SYSDIR at install time, per font replaced"
echo "  epoch     $EPOCH ($BUILD_DATE, UTC)"

rm -rf "$STAGE"
ROOT="$STAGE/root"
mkdir -p "$ROOT/DEBIAN" "$ROOT$PKGDIR"

COPYFILE_DISABLE=1
export COPYFILE_DISABLE
cp "$FONT_1X" "$ROOT$PKGDIR/$FONT_1X_NAME"
cp "$FONT_2X" "$ROOT$PKGDIR/$FONT_2X_NAME"
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
        -e "s|@FONT_1X@|$(esc "$FONT_1X_NAME")|g" \
        -e "s|@FONT_2X@|$(esc "$FONT_2X_NAME")|g" \
        -e "s|@FONT_1X_BYTES@|$FONT_1X_BYTES|g" \
        -e "s|@FONT_2X_BYTES@|$FONT_2X_BYTES|g" \
        -e "s|@FONT_1X_KB@|$FONT_1X_KB|g" \
        -e "s|@FONT_2X_KB@|$FONT_2X_KB|g" \
        -e "s|@STRIKES_1X@|$(esc "$STRIKES_1X")|g" \
        -e "s|@STRIKES_2X@|$(esc "$STRIKES_2X")|g" \
        -e "s|@MARGIN_KB@|$MARGIN_KB|g" \
        -e "s|@REQUIRED_MB@|$REQUIRED_MB|g" \
        -e "s|@PKGDIR@|$(esc "$PKGDIR")|g" \
        -e "s|@PKGDIRNAME@|$(esc "$PKGDIRNAME")|g" \
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
chmod 644 "$ROOT$PKGDIR/$FONT_1X_NAME" "$ROOT$PKGDIR/$FONT_2X_NAME" \
          "$ROOT$PKGDIR/COPYING" \
          "$ROOT/DEBIAN/control" "$ROOT/DEBIAN/md5sums"
find "$ROOT" -type d -exec chmod 755 {} +

command -v xattr >/dev/null 2>&1 && xattr -cr "$ROOT" 2>/dev/null || true
find "$ROOT" -name '._*' -delete 2>/dev/null || true
find "$ROOT" -exec touch -h -t "$TOUCH_STAMP" {} +

if [ -n "${EMOJITWEAK_STAGE_ONLY:-}" ]; then
    echo ""
    echo "  EMOJITWEAK_STAGE_ONLY is set; stopped after staging $ROOT"
    exit 0
fi

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
