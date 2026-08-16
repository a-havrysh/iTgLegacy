#!/bin/sh
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
WORK="$HERE/work/pkgtest"
FONT_1X_NAME=AppleColorEmoji.ttf
FONT_2X_NAME=AppleColorEmoji@2x.ttf

pass=0
fail=0

die() { echo "pkgtest: $*" >&2; exit 1; }

ok() { pass=$(( pass + 1 )); echo "  ok    $*"; }

bad() { fail=$(( fail + 1 )); echo "  FAIL  $*" >&2; }

[ -f "$HERE/out/$FONT_1X_NAME" ] || die "out/$FONT_1X_NAME missing -- run: make font"
[ -f "$HERE/out/$FONT_2X_NAME" ] || die "out/$FONT_2X_NAME missing -- run: make font"

stage() {
    _sys="$1"
    _pkg="$2"
    _margin="$3"
    rm -rf "$WORK/stage"
    mkdir -p "$WORK/stage"
    EMOJITWEAK_SYSDIR="$_sys" EMOJITWEAK_PKGDIR="$_pkg" \
        EMOJITWEAK_MARGIN_KB="$_margin" EMOJITWEAK_STAGE_ONLY=1 \
        "$HERE/mkdeb.sh" >"$WORK/stage/mkdeb.log" 2>&1 \
        || { cat "$WORK/stage/mkdeb.log" >&2; die "staging failed"; }
    cp "$HERE/work/deb/root/DEBIAN/preinst" "$WORK/stage/preinst"
    cp "$HERE/work/deb/root/DEBIAN/postinst" "$WORK/stage/postinst"
    cp "$HERE/work/deb/root/DEBIAN/postrm" "$WORK/stage/postrm"
    chmod 755 "$WORK/stage"/pre* "$WORK/stage"/post*
}

new_case() {
    CASE="$1"
    SYS="$WORK/$CASE/sys"
    PKG="$WORK/$CASE/pkg"
    rm -rf "$WORK/$CASE"
    mkdir -p "$SYS" "$PKG"
    echo "$CASE"
}

unpack() {
    cp "$HERE/out/$FONT_1X_NAME" "$PKG/$FONT_1X_NAME"
    cp "$HERE/out/$FONT_2X_NAME" "$PKG/$FONT_2X_NAME"
    printf '#!/bin/sh\nexit 0\n' > "$PKG/respring"
    chmod 755 "$PKG/respring"
}

fake_stock() {
    python3 -c 'import sys; open(sys.argv[1], "wb").write(b"STOCK" + b"\0" * 300000)' \
        "$SYS/$1"
}

run() {
    _script="$1"
    shift
    set +e
    EMOJITWEAK_NO_RESPRING=1 "$WORK/stage/$_script" "$@" \
        >"$WORK/$CASE/$_script.out" 2>"$WORK/$CASE/$_script.err"
    _rc=$?
    set -e
    echo "$_rc"
}

same() {
    cmp -s "$1" "$2"
}

echo "staging maintainer scripts against a fake system font directory"
mkdir -p "$WORK"

echo ""
new_case neither
stage "$SYS" "$PKG" 4096
rc=$(run preinst install)
[ "$rc" != 0 ] && ok "preinst refuses when no emoji font exists (rc=$rc)" \
                || bad "preinst accepted a device with no emoji font"
grep -q "no Apple colour emoji font found" "$WORK/$CASE/preinst.err" \
    && ok "preinst says why" || bad "preinst error message is missing the reason"
unpack
rc=$(run postinst configure)
[ "$rc" != 0 ] && ok "postinst refuses too (rc=$rc)" \
                || bad "postinst wrote a font nobody reads"
[ -f "$SYS/$FONT_1X_NAME" ] || [ -f "$SYS/$FONT_2X_NAME" ] \
    && bad "postinst created a font in $SYS" || ok "nothing was written to $SYS"

echo ""
new_case only1x
stage "$SYS" "$PKG" 4096
fake_stock "$FONT_1X_NAME"
cp "$SYS/$FONT_1X_NAME" "$WORK/$CASE/stock1x"
unpack
rc=$(run preinst install)
[ "$rc" = 0 ] && ok "preinst accepts a non-Retina device" || bad "preinst rc=$rc"
grep -q "will replace: $FONT_1X_NAME" "$WORK/$CASE/preinst.out" \
    && ok "preinst picked $FONT_1X_NAME only" \
    || bad "preinst target list wrong: $(cat "$WORK/$CASE/preinst.out")"
rc=$(run postinst configure)
[ "$rc" = 0 ] && ok "postinst rc=0" || bad "postinst rc=$rc: $(cat "$WORK/$CASE/postinst.err")"
same "$SYS/$FONT_1X_NAME" "$PKG/$FONT_1X_NAME" \
    && ok "$FONT_1X_NAME replaced" || bad "$FONT_1X_NAME not replaced"
[ -f "$SYS/$FONT_2X_NAME" ] && bad "postinst invented $FONT_2X_NAME" \
    || ok "$FONT_2X_NAME left absent"
same "$PKG/$FONT_1X_NAME.stock" "$WORK/$CASE/stock1x" \
    && ok "stock font backed up" || bad "backup missing or wrong"
rc=$(run postrm remove)
[ "$rc" = 0 ] && ok "postrm rc=0" || bad "postrm rc=$rc"
same "$SYS/$FONT_1X_NAME" "$WORK/$CASE/stock1x" \
    && ok "stock font restored" || bad "stock font NOT restored"

echo ""
new_case only2x
stage "$SYS" "$PKG" 4096
fake_stock "$FONT_2X_NAME"
cp "$SYS/$FONT_2X_NAME" "$WORK/$CASE/stock2x"
unpack
rc=$(run preinst install)
[ "$rc" = 0 ] && ok "preinst accepts a Retina device" || bad "preinst rc=$rc"
grep -q "will replace: $FONT_2X_NAME" "$WORK/$CASE/preinst.out" \
    && ok "preinst picked $FONT_2X_NAME only" \
    || bad "preinst target list wrong: $(cat "$WORK/$CASE/preinst.out")"
rc=$(run postinst configure)
[ "$rc" = 0 ] && ok "postinst rc=0" || bad "postinst rc=$rc: $(cat "$WORK/$CASE/postinst.err")"
same "$SYS/$FONT_2X_NAME" "$PKG/$FONT_2X_NAME" \
    && ok "$FONT_2X_NAME replaced with the 2x payload" || bad "$FONT_2X_NAME not replaced"
[ -f "$SYS/$FONT_1X_NAME" ] && bad "postinst invented $FONT_1X_NAME" \
    || ok "$FONT_1X_NAME left absent"
rc=$(run postrm remove)
[ "$rc" = 0 ] && ok "postrm rc=0" || bad "postrm rc=$rc"
same "$SYS/$FONT_2X_NAME" "$WORK/$CASE/stock2x" \
    && ok "stock font restored" || bad "stock font NOT restored"

echo ""
new_case both
stage "$SYS" "$PKG" 4096
fake_stock "$FONT_1X_NAME"
fake_stock "$FONT_2X_NAME"
cp "$SYS/$FONT_1X_NAME" "$WORK/$CASE/stock1x"
cp "$SYS/$FONT_2X_NAME" "$WORK/$CASE/stock2x"
unpack
rc=$(run preinst install)
[ "$rc" = 0 ] && ok "preinst accepts a device with both names" || bad "preinst rc=$rc"
grep -q "will replace: $FONT_1X_NAME $FONT_2X_NAME" "$WORK/$CASE/preinst.out" \
    && ok "preinst picked both" \
    || bad "preinst target list wrong: $(cat "$WORK/$CASE/preinst.out")"
rc=$(run postinst configure)
[ "$rc" = 0 ] && ok "postinst rc=0" || bad "postinst rc=$rc: $(cat "$WORK/$CASE/postinst.err")"
same "$SYS/$FONT_1X_NAME" "$PKG/$FONT_1X_NAME" \
    && ok "1x got the 1x payload" || bad "1x payload wrong"
same "$SYS/$FONT_2X_NAME" "$PKG/$FONT_2X_NAME" \
    && ok "2x got the 2x payload" || bad "2x payload wrong"
rc=$(run postrm remove)
[ "$rc" = 0 ] && ok "postrm rc=0" || bad "postrm rc=$rc"
same "$SYS/$FONT_1X_NAME" "$WORK/$CASE/stock1x" \
    && ok "1x stock restored" || bad "1x stock NOT restored"
same "$SYS/$FONT_2X_NAME" "$WORK/$CASE/stock2x" \
    && ok "2x stock restored" || bad "2x stock NOT restored"
rc=$(run postrm purge)
[ -f "$PKG/$FONT_1X_NAME.stock" ] || [ -f "$PKG/$FONT_2X_NAME.stock" ] \
    && bad "purge left backups behind" || ok "purge removed both backups"

echo ""
new_case nospace
stage "$SYS" "$PKG" 999999999
fake_stock "$FONT_2X_NAME"
cp "$SYS/$FONT_2X_NAME" "$WORK/$CASE/stock2x"
unpack
rc=$(run preinst install)
[ "$rc" != 0 ] && ok "preinst refuses when the target has no room (rc=$rc)" \
                || bad "preinst ignored the space check"
grep -q "not enough free space" "$WORK/$CASE/preinst.err" \
    && ok "preinst says why" || bad "space message missing"
same "$SYS/$FONT_2X_NAME" "$WORK/$CASE/stock2x" \
    && ok "the stock font is untouched" || bad "the stock font was changed anyway"

echo ""
new_case corrupt
stage "$SYS" "$PKG" 4096
fake_stock "$FONT_2X_NAME"
cp "$SYS/$FONT_2X_NAME" "$WORK/$CASE/stock2x"
unpack
printf 'truncated' > "$PKG/$FONT_2X_NAME"
rc=$(run postinst configure)
[ "$rc" != 0 ] && ok "postinst refuses a damaged payload (rc=$rc)" \
                || bad "postinst installed a damaged payload"
same "$SYS/$FONT_2X_NAME" "$WORK/$CASE/stock2x" \
    && ok "the stock font is untouched" || bad "the stock font was changed anyway"

echo ""
echo "pkgtest: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
