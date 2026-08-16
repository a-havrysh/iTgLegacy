# emojitweak

A replacement `AppleColorEmoji.ttf` for jailbroken iOS 6, and the Cydia package that
installs it.

iOS 6 shipped 1359 emoji glyphs. This font carries 4005, built from Twemoji artwork
against the current `emoji-test.txt`, with an AAT `morx` table that composes skin
tones, ZWJ professions, family sequences, keycaps and flags the way iOS 6's CoreText
expects. Metrics are byte-identical to the stock font, so nothing in the system
shifts by a pixel.

## One line from nothing to a .deb

```sh
make deb
```

That downloads `emoji-test.txt` and the Twemoji release, rasterises every glyph at
20/40/48/96 ppem, assembles the font, and packs it into
`out/com.havrysh.moderncoloremoji_<emoji-version>-<date>_iphoneos-arm.deb`.

Cold, that is about 17 s for the font plus a few seconds for the package. With
`work/strikes-*.pickle` warm the font takes about 5 s. `make deb` skips the font
build entirely if `out/AppleColorEmoji.ttf` already exists.

### Requirements

- Python 3 with `fontTools` (4.60 here) and Pillow
- `rsvg-convert` — `brew install librsvg`
- `dpkg-deb` — `brew install dpkg`
- network access on the first build only

Only for the on-device checks (`make probe`, `make device-check`, `debtest.sh`):

- `ldid` — `brew install ldid`
- an iOS SDK with an armv7 slice, picked up automatically from `build/sdks/` in this
  repo, or named with `PROBE_SDK=`
- `sshpass` for `ipad.sh`

### Other targets

| target | what it does |
|---|---|
| `make font` | build `out/AppleColorEmoji.ttf` only |
| `make probe` | cross-compile `out/emojiprobe2`, the on-device CoreText probe |
| `make refresh` | unpin Unicode and Twemoji so the next build fetches new releases |
| `make check` | host-side coverage check with HarfBuzz |
| `make device-check` | full CoreText coverage check on the device (`IPAD=<ip>`) |
| `make install-ipad` | build the .deb, push it, `dpkg -i`, print what CoreText sees |
| `make remove-ipad` | `dpkg -r`, print what CoreText sees |
| `make clean` | drop the staging tree and built .deb files |
| `make distclean` | also drop `out/` and the raster cache |

## The package

```
Package:      com.havrysh.moderncoloremoji
Name:         Modern Color Emoji
Version:      <emoji version>-<YYYYMMDD>      e.g. 17.0-20260816
Section:      Fonts
Architecture: iphoneos-arm
Depends:      firmware (>= 6.0)
```

Every one of those is overridable from the environment, which is the intended way to
rename it for your own repo:

```sh
EMOJITWEAK_PACKAGE=net.example.emoji \
EMOJITWEAK_NAME="Example Emoji" \
EMOJITWEAK_AUTHOR="You <you@example.com>" \
EMOJITWEAK_HOMEPAGE=https://example.com/repo \
EMOJITWEAK_DEPICTION=https://example.com/repo/emoji.html \
./mkdeb.sh
```

`EMOJITWEAK_VERSION` overrides the whole version string if you need to ship two
builds on the same day.

### Payload layout

The font ships to `/var/lib/emojitweak/`, not to `/System`. The data partition has
gigabytes free; the system partition on a 4S has a couple of hundred megabytes, and
dpkg unpacks a `.dpkg-new` temporary alongside every file it installs. Keeping the
25 MB payload off `/` means dpkg can never fill the system partition on its own, and
it means the maintainer scripts — not dpkg's file list — own the system font path, so
a removal can always put the stock font back.

```
/var/lib/emojitweak/AppleColorEmoji.ttf         the payload
/var/lib/emojitweak/AppleColorEmoji.ttf.stock   your stock font, made on first install
/var/lib/emojitweak/COPYING                     licence and attribution
/var/lib/emojitweak/respring                    detached respring helper
```

### Install

`preinst` refuses the install, before anything is unpacked, unless
`/System/Library/Fonts/Cache` exists, is writable, and has the font size plus 4 MB
free. The message names the mount point, the free space, the needed space and the
shortfall, and says nothing has been changed.

`postinst` then:

1. checks the payload is the exact byte count baked in at build time;
2. backs the stock font up to `…ttf.stock`, **unless** a backup already exists (second
   install) or the font currently installed is byte-identical to the payload (our own
   font — backing that up would destroy the only copy of the stock one);
3. re-checks free space;
4. copies to `AppleColorEmoji.ttf.emojitweak-new`, verifies the byte count, `chmod 644`,
   then renames over the live path — so a failed or short copy never leaves a broken
   font behind;
5. resprings via a detached helper that sleeps first, so dpkg (and Cydia) finish before
   SpringBoard dies.

Set `EMOJITWEAK_NO_RESPRING=1` to skip step 5.

### Remove

`postrm remove` copies `…ttf.stock` back, verifies, resprings, and keeps the backup
(it is your only copy — `dpkg -P` deletes it along with the directory). If the system
partition is too tight for the temp-then-rename dance it deletes the replacement font
first and copies directly, which is safe because the backup is what it is copying from.

If the backup is **missing**, removal still succeeds but deliberately leaves the
current font in place — deleting it would leave the device with no colour emoji at
all — and prints where to get an original from an iOS 6.1.3 IPSW.

## Rebuilding when a new Unicode version lands

`emojidata.py` resolves the newest Unicode Emoji release and the newest Twemoji
release, then caches both under `cache/`. Those caches are what pin a build, so a
plain rebuild will keep giving you the old repertoire. Unpin them:

```sh
make refresh
make deb
```

`make refresh` deletes `cache/emoji-latest-ReadMe.txt`, `cache/twemoji-release.json`
and the extracted `cache/twemoji/` tree — that last one matters, because the extractor
skips extraction when the SVG directory is already populated, so a new tarball with an
old extracted tree would silently rebuild the old artwork.

A new Unicode release usually lands before Twemoji has drawn the new emoji. `build.py`
refuses to build in that case rather than shipping blank glyphs, and names every emoji
it has no artwork for:

```
build.py: 163 emoji in Unicode Emoji 18.0 have no Twemoji v17.0.3 artwork and would
ship as blank glyphs: ...
```

Wait for the Twemoji release that covers it, or set `EMOJITWEAK_ALLOW_MISSING_ART=1`
to ship the blanks deliberately.

The other upstream breakages fail the build with a message naming the file to delete,
rather than producing a quietly wrong font: a 404 or moved URL, a `ReadMe.txt` that no
longer states a version, an `emoji-test.txt` whose line format changed, a GitHub API
rate-limit reply instead of a release, and a Twemoji tarball that no longer keeps its
artwork in `assets/svg/`. A failed download never leaves a truncated file in `cache/`.

Then check the result before you ship it:

```sh
make check                 # HarfBuzz, on the host
make device-check          # CoreText, on the device
```

`device-check` shapes every line of `emoji-test.txt` through iOS 6 CoreText and
compares the glyph IDs it reports against `getGlyphID`. Expect three failures and only
three: the England, Scotland and Wales tag flags. iOS 6 deletes Unicode tag characters
before the font is consulted (a lone `U+E0067` that *is* in the cmap comes back as
glyph 65535, CoreText's deleted-glyph sentinel), so all three arrive as an
indistinguishable `1F3F4` plus six deleted glyphs and degrade to 🏴. The rules are in
the font for any newer shaper. Anything beyond those three is a regression.

The version in the package follows whatever `build.py` put in the font's name table,
so a new Unicode release changes the package version automatically.

### Reproducibility

`mkdeb.sh` is byte-reproducible. It normalises ownership to `root/root`, sets every
mtime in the staging tree to `SOURCE_DATE_EPOCH`, strips macOS xattrs, and compresses
with gzip (dpkg 1.14-era tooling on old jailbreaks cannot read xz or zstd).

The font is reproducible too. `head.created` and `head.modified` are the only
non-deterministic bytes in it, and fontTools takes those from `SOURCE_DATE_EPOCH` when
it is set — which is why the Makefile exports one variable for both steps:

```make
SOURCE_DATE_EPOCH ?= <today 00:00 UTC>
export SOURCE_DATE_EPOCH
```

So `make deb` twice from an empty `out/` gives a byte-identical font *and* a
byte-identical .deb — verified, and the font that ended up on the iPad hashes the same
as the one on the host. Set the variable explicitly to reproduce an older package:

```sh
SOURCE_DATE_EPOCH=1786838400 make deb
```

The date in the package version comes from the same epoch, so version and contents
never disagree. Running `python3 build.py` on its own, outside make and without the
variable, still works but stamps the current time into `head` — the font will differ
from a make-built one in those eight bytes and nothing else.

The repertoire is pinned by the Unicode and Twemoji releases, both recorded in the
font's name table (`17.0;twemoji-17.0.3`) and in `out/COPYING`.

One caveat inherited from the builder: `work/strikes-*.pickle` is a pickle, chosen
because it holds PNG blobs. It is written and read only by `build.py` in its own
directory, and it is unpickled without validation — never point the build at a cache
file from anywhere else.

## Licence obligations

**You must ship `COPYING` with the font.** `build.py` writes it to `out/COPYING` and
`mkdeb.sh` puts it in the package at `/var/lib/emojitweak/COPYING`. That file is not
decoration; it is what makes redistribution lawful.

- **Artwork: Twemoji, CC-BY 4.0.** [jdecked/twemoji](https://github.com/jdecked/twemoji),
  © Twitter, Inc and other contributors. CC-BY 4.0 requires attribution, a link to the
  licence, and an indication that the material was modified. `COPYING` carries all
  three, including an explicit modifications notice (rasterised to PNG at four ppem
  sizes, colour-quantised, embedded as sbix strikes). CC-BY is not copyleft, so the
  font and the package are not forced under any particular licence — but the attribution
  travels with the artwork wherever it goes. If you publish a depiction page for the
  package in your repo, put the same attribution on it: the .deb is not the only place a
  user encounters the work.
- **Repertoire: Unicode.** `emoji-test.txt` from the UCD drives which sequences exist.
  It is build input, not redistributed, but `COPYING` credits Unicode, Inc. and links
  the Unicode Terms of Use anyway.
- **Apple: nothing of theirs is in the file.** No Apple artwork, outlines or font data.
  The family name `Apple Color Emoji` and PostScript name `AppleColorEmoji` are present
  only because iOS 6 CoreText resolves the system emoji font by those names. That is a
  functional requirement, not a claim of origin — but they are Apple trademarks, so do
  not describe the package as Apple's font or as containing it, and keep the package's
  own display name distinct (`Modern Color Emoji`).

If you swap the artwork for something else, `build.py`'s `ATTRIBUTION` template is the
one place to update, and the new obligations are whatever that artwork's licence says —
Noto Emoji is SIL OFL 1.1, which has a reserved-font-name clause that would bite here
given the font is deliberately named `Apple Color Emoji`.

## Testing on a device

```sh
make probe                      # cross-compile out/emojiprobe2 (once)
./debtest.sh prepare            # push the probe binary and a 10-sequence sample set
./debtest.sh status stock       # what CoreText resolves right now
./debtest.sh install            # push and dpkg -i the newest .deb in out/
./debtest.sh status installed
./debtest.sh pull-png installed # fetch the rendered grid
./debtest.sh remove             # dpkg -r
./debtest.sh purge              # dpkg -P, also deletes the stock backup
```

`IPAD=<ip>` selects the device (default `192.168.18.217`); `ipad.sh` handles the legacy
SSH algorithms iOS 6 needs. `status` prints CoreText's font header — `glyphs=1359` is
stock, `glyphs=4005` is this package — and one line per sample showing how many glyphs
the sequence shaped to and which font served them. One glyph from `emoji` is a pass.

To exercise the disk-space refusal, fill the system partition first:

```sh
./ipad.sh 'dd if=/dev/zero of=/ballast.bin bs=1048576 count=245'
./debtest.sh install     # preinst refuses, nothing changes
./ipad.sh 'rm -f /ballast.bin'
```

## Interactions

PoomSmart's **EmojiFontManager** (`com.ps.emojifontmanager`) can redirect CoreText to a
font somewhere other than `/System/Library/Fonts/Cache/AppleColorEmoji.ttf`. It owns no
files at that path so there is no dpkg conflict, and this package installs and removes
cleanly alongside it — but if EFM is pointing elsewhere you will not see this font.
**EmojiPortLegacy** and **EmojiAttributes** are keyboard and layout tweaks and do not
touch the font file.
