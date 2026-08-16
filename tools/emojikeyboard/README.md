# emojikeyboard

A MobileSubstrate tweak that puts modern emoji into the **iOS 6 emoji keyboard**, and the
Cydia package that installs it. Companion to `tools/emojitweak`, which replaces
`AppleColorEmoji.ttf` so iOS 6 can *draw* modern emoji. The font is half the job: it makes
🫩 renderable, but the palette still offers only what Apple compiled into UIKit in 2012.

On iOS 6 the palette is not data. `UIKit.framework` on disk carries only
`Keyboard-default.plist` and `Keyboard-intl.plist`, neither of which mentions emoji; the six
categories are six hard-coded UTF-16 string constants in UIKit's `__cfstring`, read by
`+[UIKeyboardEmojiCategory categoryForType:]`. There is no plist to edit and no
keyboard-extension API, so the only way in is a hook.

Everything in `evidence/` is the static analysis this is built on: the decrypted 10B329 root
filesystem, a `dyld_v1` shared-cache parser, an annotating armv7 disassembler, class-dump
headers for the 23 classes in the emoji family, and `ios6_emoji_tables.json` — the complete
stock palette, slot by slot, extracted from the shipping binary.

## One line from nothing to a .deb

```sh
make deb
```

Compiles the dylib and the install-time shaping tool for armv7, generates the candidate list
from Unicode's `emoji-test.txt`, and packs everything into
`out/com.havrysh.emojikeyboard_<emoji-version>-<date>_iphoneos-arm.deb`. About a second on a
warm checkout; the first run downloads `emoji-test.txt` if `tools/emojitweak/cache/` has not
got it yet.

```
make            dylib + prep tool + palette data, no package
make deb        also the package
make check      static checks, then the host-side behaviour suite
make clean      drop the staging tree and built .deb files
make distclean  drop out/ and work/ entirely
make help
```

### Requirements

- Xcode with an iOS SDK — any modern one works, the deployment target is what matters
  (`SDK=<path>` to override; the Makefile prefers a checked-in `iPhoneOS12.4.sdk`)
- `ldid` for pseudo-signing — without it the build still runs and warns
- `dpkg-deb` — `brew install dpkg`
- Python 3
- `tools/emojitweak` next to this directory, for `emoji-test.txt` and `emojidata.py`
  (`EMOJITWEAK_DIR=<path>` to override)

## The package

```
Package:      com.havrysh.emojikeyboard
Name:         Modern Emoji Keyboard
Version:      <emoji version>-<YYYYMMDD>      e.g. 17.0-20260816
Section:      Keyboards
Architecture: iphoneos-arm
Depends:      firmware (>= 6.0), mobilesubstrate,
              com.havrysh.moderncoloremoji (>= 17.0)
```

Same version scheme as the font package, from the same source of truth: `build.py` writes the
Unicode Emoji version into `palette.plist` and `mkdeb.sh` reads it back out, so the two
packages built on the same day from the same `emoji-test.txt` carry the same version string.

Every field is overridable from the environment, which is the intended way to rename it for
your own repo:

```sh
EMOJIKEYBOARD_PACKAGE=net.example.emojikeyboard \
EMOJIKEYBOARD_NAME="Example Emoji Keyboard" \
EMOJIKEYBOARD_AUTHOR="You <you@example.com>" \
EMOJIKEYBOARD_HOMEPAGE=https://example.com/repo \
EMOJIKEYBOARD_DEPICTION=https://example.com/repo/emojikeyboard.html \
EMOJIKEYBOARD_FONTPACKAGE=net.example.emoji \
./mkdeb.sh
```

`EMOJIKEYBOARD_VERSION` overrides the whole version string if you need two builds on one day.
The preferences domain is *not* renamed by `EMOJIKEYBOARD_PACKAGE` — it is compiled into the
dylib as `EK_PREFS` and `mkdeb.sh` reads it out of the header so the package and the binary
can never disagree about where it lives.

### Why it depends on the font package

The tweak never offers an emoji the installed font cannot draw — every candidate is shaped
through CoreText first and dropped if it does not resolve to exactly one glyph in the emoji
font. So a missing font cannot put boxes in the keyboard. What it does instead is make the
package do nothing at all: on Apple's 2012 font almost every candidate fails the test and the
palette stays exactly as it shipped.

That is a bad way for a package to behave — silently inert, with the user assuming it is
broken — so the font is a hard `Depends`, not a `Recommends`. Cydia pulls it in, and the
version floor (`>= <emoji version>`) stops a stale font from quietly capping the repertoire:
both packages are generated from the same `emoji-test.txt`, so a keyboard built for Unicode
18.0 wants a font built for Unicode 18.0.

If you use a different modern emoji font — PoomSmart's, or your own build under another
package name — point the dependency at it, or loosen it:

```sh
EMOJIKEYBOARD_FONTPACKAGE=com.example.somefont ./mkdeb.sh   # depend on that instead
EMOJIKEYBOARD_FONTDEP=recommends ./mkdeb.sh                 # suggest, do not require
EMOJIKEYBOARD_FONTDEP=none ./mkdeb.sh                       # document only
```

Under `recommends` and `none` the description still names the font package and `postinst`
still warns when `/var/lib/emojitweak/AppleColorEmoji.ttf` is missing
(`EMOJIKEYBOARD_FONTFILE=<path>` changes which file it looks for).

### Both packages in one repo

Nothing overlaps. The font owns `/var/lib/emojitweak/` and, through its maintainer scripts,
`/System/Library/Fonts/Cache/AppleColorEmoji.ttf`; the keyboard owns `/var/lib/emojikeyboard/`
and two files in `/Library/MobileSubstrate/DynamicLibraries/`. No shared paths, no
`Conflicts`, no `Replaces`. Drop both `.deb` files into the same repo, run your `Packages`
generator over them, and Cydia resolves the dependency by itself.

### Payload layout

```
/Library/MobileSubstrate/DynamicLibraries/EmojiKeyboard.dylib   the tweak
/Library/MobileSubstrate/DynamicLibraries/EmojiKeyboard.plist   Filter = { Bundles = com.apple.UIKit }
/var/lib/emojikeyboard/palette.plist        candidate strings, shipped
/var/lib/emojikeyboard/emojipaletteprep     shaping tool, also a useful diagnostic
/var/lib/emojikeyboard/refresh              reshape + respring after a font change
/var/lib/emojikeyboard/respring             detached respring helper
```

Generated on the device, not shipped:

```
/var/lib/emojikeyboard/glyphs.plist         shaped result, written by postinst
/var/lib/emojikeyboard/disabled             create this to switch the tweak off
/var/mobile/Library/Preferences/com.havrysh.emojikeyboard.plist
```

171 KB installed. The whole payload is on the data partition except the two Substrate files,
which have to be where Substrate looks.

## Installing

Font first, then the keyboard — or both in one `dpkg -i`, which lets dpkg order them itself:

```sh
scp out/com.havrysh.emojikeyboard_*.deb \
    ../emojitweak/out/com.havrysh.moderncoloremoji_*.deb root@<device>:/tmp/
ssh root@<device> 'dpkg -i /tmp/com.havrysh.moderncoloremoji_*.deb /tmp/com.havrysh.emojikeyboard_*.deb'
```

Installing the keyboard alone on a device without the font leaves it unpacked but
unconfigured, with dpkg reporting a dependency problem. That is the hard `Depends` doing its
job; install the font and run `dpkg --configure -a`.

`postinst` pre-shapes the palette against the font that is actually installed, then resprings
through a detached helper that sleeps 4 s first, so dpkg and Cydia finish before SpringBoard
dies. `EMOJIKEYBOARD_NO_RESPRING=1` skips the respring — worth setting when you are working
over SSH and do not want the UI to drop out from under you.

**After changing the emoji font, run `/var/lib/emojikeyboard/refresh`.** Without it the first
app to open the emoji keyboard notices the font fingerprint changed and reshapes everything in
the background, which is correct but slower than doing it once from the shell.

## Recovery: switching it off from SSH

This matters more than the install instructions, so it comes with the reasoning.

The filter is `Bundles = (com.apple.UIKit)` — every process that can show a keyboard, and that
includes SpringBoard. A tweak with that reach has to be removable from a device whose UI is
not cooperating. Two facts make that possible:

- **SSH does not depend on SpringBoard.** `sshd` is a launchd job. A SpringBoard crash loop
  does not take SSH with it; if the device answers ping it will answer ssh.
- **The off switch is checked before anything else happens.** The constructor's first act is
  `getenv` and one `stat`. Nothing is loaded, no class is looked up, no hook is installed.

Work down this ladder and stop at the first rung that fixes it.

### 1. Off, without uninstalling

```sh
ssh root@<device> 'touch /var/lib/emojikeyboard/disabled; killall -9 SpringBoard'
```

Every process started after that respring loads the dylib and returns immediately from the
constructor. It survives reboots, needs no dpkg, and cannot half-apply. Processes already
running keep the hooks they installed until they are killed — reboot if you want certainty.

Back on: `rm /var/lib/emojikeyboard/disabled` and respring.

`EMOJIKEYBOARD_DISABLE=1` in the environment does the same for one process, which is only
reachable for something you launch by hand from the shell.

### 2. Unload it without dpkg

If dpkg is wedged, or you want the dylib gone this second:

```sh
ssh root@<device> 'rm -f /Library/MobileSubstrate/DynamicLibraries/EmojiKeyboard.dylib \
                         /Library/MobileSubstrate/DynamicLibraries/EmojiKeyboard.plist
                   killall -9 SpringBoard'
```

**Delete the dylib, or both files — never the `.plist` alone.** A dylib in that directory with
no matching filter plist is unfiltered, and Substrate loads it into *every* process on the
system instead of just the ones linking UIKit. Removing only the filter makes the blast radius
larger, not smaller.

This leaves dpkg's database disagreeing with the filesystem. Reconcile it later with
`dpkg -r --force-all com.havrysh.emojikeyboard`, or reinstall the package and remove it
properly.

### 3. Remove the package

```sh
ssh root@<device> 'dpkg -r com.havrysh.emojikeyboard'
```

dpkg deletes both Substrate files and everything under `/var/lib/emojikeyboard/` that the
package owns; `postrm` deletes the generated `glyphs.plist` and resprings after 4 s
(`EMOJIKEYBOARD_NO_RESPRING=1` to suppress that). `dpkg -P` additionally removes the directory
and the preferences plist.

Removal touches nothing outside those paths. There is no backup to restore and no system file
to put back, because the tweak never modified one — the palette it changes only ever existed
in memory.

To go back to fully stock, remove the keyboard **before or with** the font. The hard `Depends`
means dpkg will refuse to remove the font on its own while the keyboard is installed:

```sh
ssh root@<device> 'dpkg -r com.havrysh.emojikeyboard com.havrysh.moderncoloremoji'
```

Removing the font while keeping the keyboard is safe, just pointless: the stale glyph cache
fails its font fingerprint check, the background pass reshapes against Apple's font, and
almost nothing survives the filter, so the palette returns to stock.

### 4. Substrate safe mode

If SpringBoard is crash-looping and you want a UI rather than a shell, hold **Volume Up** from
the moment the Apple logo disappears until SpringBoard has finished starting. Safe mode loads
no Substrate dylibs at all, so the device comes up usable, with Cydia, and you can remove the
package from there. Substrate also drops into safe mode by itself after repeated SpringBoard
crashes.

### 5. Before you nuke it, find out what it did

Nearly every message the tweak can print is gated behind `Verbose`, because a tweak in every
UIKit process has no business writing to syslog by default. The exceptions are the two
unconditional ones: if a hook or the palette build raises, that is logged whatever the
preference says.

Turn logging on (the file is read once per process, so respring or relaunch the app after):

```sh
ssh root@<device> 'cat > /var/mobile/Library/Preferences/com.havrysh.emojikeyboard.plist <<"EOF"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Verbose</key><true/>
</dict></plist>
EOF
chown mobile:mobile /var/mobile/Library/Preferences/com.havrysh.emojikeyboard.plist
chmod 644 /var/mobile/Library/Preferences/com.havrysh.emojikeyboard.plist
killall -9 SpringBoard'
```

Then watch it: `syslog -w` works on a stock iOS 6 install, and `tail -f /var/log/syslog` works
if the `syslogd for iOS` package is installed. Everything the tweak writes is prefixed
`emojikeyboard:`.

What the interesting lines mean:

| line | meaning |
|---|---|
| `installed in <process>` | all guards passed, hooks are live |
| `…has an unexpected signature; doing nothing` | the runtime is not what this build expects — no hook was installed, the keyboard is stock |
| `could not hook …` | neither Substrate nor the fallback could install it; nothing was changed |
| `switched off` | the `disabled` file or `Enabled = NO` |
| `palette … from cache in N ms` | the fast path; N is what decides whether this feels instant |
| `category N: X stock + Y added` | the append actually happened |
| `… raised … ; every hook is now a straight pass-through` | an exception; the tweak has self-disabled for this process |

The last one is the one to report. Everything else is the tweak declining to act, which is
the designed behaviour and never needs recovery.

You can also ask the shaping tool directly, without involving the keyboard at all — the single
most useful diagnostic on the device:

```sh
ssh root@<device> '/var/lib/emojikeyboard/emojipaletteprep'
```

It prints how many candidates the installed font can draw, per category, and how long shaping
took. A low count means the font, not the tweak.

## Rebuilding when a new Unicode version lands

The keyboard's repertoire and the font's come from the same file, so they are bumped together
and **the font goes first**.

```sh
cd ../emojitweak
make refresh            # unpin Unicode and Twemoji
make deb                # new font, new emoji-test.txt in cache/

cd ../emojikeyboard
make distclean
make deb                # picks up the new cache/emoji-test-<ucd>.txt automatically
make check
```

`build.py` reads `emoji-test.txt` through `emojitweak`'s own `emojidata.py`, from
`emojitweak/cache/`. It never resolves a Unicode version of its own, which is the point: the
keyboard cannot offer a Unicode version the font was not built for. The version in
`palette.plist` — and therefore the package version, and the font dependency's floor — follows
whatever that file says.

Doing it in the other order gets you a keyboard package that depends on a font version that
does not exist in your repo yet, and Cydia will refuse to install it. That failure is loud and
harmless, but the order above avoids it.

`make distclean` matters: `out/palette.plist` is rebuilt only when `build.py` or
`ios6_emoji_tables.json` is newer than it, and a new `emoji-test.txt` in another directory does
not trip that rule.

Two things to look at in the new build before shipping:

- the per-category candidate counts `build.py` prints — a new Unicode version should add tens
  or low hundreds, and a jump to thousands means a group got remapped;
- `make check`'s dedupe result. New sequences occasionally collide with old ones under a given
  font, and the whole-palette dedupe is what catches it.

### Reproducibility

`mkdeb.sh` normalises ownership to `root/root`, sets every mtime in the staging tree from
`SOURCE_DATE_EPOCH` (defaulting to today 00:00 UTC), strips macOS xattrs, and compresses with
gzip, because dpkg 1.14-era tooling on old jailbreaks cannot read xz or zstd. The date in the
package version comes from the same epoch, so version and contents never disagree. Set it
explicitly to reproduce an older package:

```sh
SOURCE_DATE_EPOCH=1786838400 make deb
```

The build is not bit-for-bit reproducible the way the font's is — the compiler stamps its own
identity into the Mach-O and different Xcode versions will produce different bytes. Same
compiler, same source, same epoch does reproduce.

## What it does

Hooks `+[UIKeyboardEmojiCategory categoryForType:]` and, after the original has built a
category, appends every emoji from Unicode Emoji 17.0 that the installed font can actually
draw as a single glyph.

The palette has exactly six category slots, and the count is a literal
(`+numberOfCategories` is `movs r0,#6; bx lr`). The category bar's artwork, dividers and
segment images are six hard-coded generators in `UIKeyboardEmojiGraphics`, and `-name` /
`-displayName` / `-displaySymbol` / `-displayDescription` are each a `switch` with an explicit
`if (type > 5) return nil`. A seventh tab would mean hooking all of that and supplying
artwork, so this does not add one. The nine Unicode groups fold into the five non-Recents
categories instead:

| iOS 6 category | Unicode groups | stock | new candidates |
|---|---|---:|---:|
| 1 People | Smileys & Emotion, People & Body | 189 | 2416 |
| 2 Nature | Animals & Nature | 116 | 77 |
| 3 Objects | Food & Drink, Activities, Objects | 230 | 233 |
| 4 Places | Travel & Places, Flags | 101 | 330 |
| 5 Symbols | Symbols | 207 | 45 |
| 0 Recents | — | dynamic | not touched |

Recents is left alone. The `Component` group (skin-tone and hair modifiers) is not offered,
because those are not standalone emoji.

## Why every candidate is measured, not assumed

`-[UIKeyboardEmojiPage drawRect:]` draws each cell with

```c
CTFontDrawGlyphs(font, &glyph, &position, 1, ctx);   /* count == 1 */
```

One `CGGlyph` per cell. A multi-scalar sequence can only appear correctly if the font ligates
it to a single glyph — which is exactly what `emojitweak`'s `morx` table does. So the same
test the client's own `src/TGEmoji.m` uses to decide coverage is used here to decide
membership:

- **single scalars** — `CTFontGetGlyphsForCharacters`, keep if the glyph is not 0;
- **sequences** — build a `CTLine` and require `CTLineGetGlyphCount == 1`.

With one addition `TGEmoji.m` does not need. `TGEmoji.m` only wants a yes/no, but here the
glyph *value* is stored into `-[UIKeyboardEmoji setGlyph:]`, so the run's font is checked as
well: if CoreText fell back to another font, the single glyph it returns is an index into
*that* font and would draw an unrelated picture. Sequences whose run comes from anything but
the emoji font are dropped.

Anything that fails is left out, so the grid never shows `.notdef` or half of a family. With
Apple's 2012 font almost nothing passes, which is correct — that is why the font package is a
dependency.

Two further filters keep one picture to one cell:

- candidates are deduplicated against each other by resolved glyph, which is what removes the
  England/Scotland/Wales tag flags (iOS 6 CoreText deletes Unicode tag characters before the
  font is consulted, so all three shape to the plain black flag);
- candidates are deduplicated against the glyphs of the *whole* stock palette, not just the
  category being appended to. The host test found five real cases where this matters on
  Apple's own font, including `🏂🏻` colliding with stock `🏂` and `👨‍👩‍👦` with stock `👪`, in
  different categories.

## Keeping the keyboard responsive

Shaping ~3100 candidates is not something to do while the user is waiting.

1. **At install time**, `postinst` runs `/var/lib/emojikeyboard/emojipaletteprep` as root. It
   shapes everything once and writes `/var/lib/emojikeyboard/glyphs.plist`: the surviving
   strings plus their glyph ids, stamped with the palette file's size and mtime and a
   fingerprint of the font (its PostScript name, glyph count, and the glyph ids of eight probe
   codepoints).
2. **At runtime**, the first call to `categoryForType:` kicks a background pass on a low
   priority queue. Normally it just reads the cache and validates the stamp. If the stamp does
   not match — the font was changed after install — it reshapes from `palette.plist` instead,
   still off the main thread.
3. While that runs, the hook returns UIKit's own list untouched. When it finishes, the
   `UIKeyboardEmoji` objects are built on the background thread too, then a single main-queue
   pass appends them to whichever categories already exist. Every later `categoryForType:`
   call — one per category tap — finds them ready.
4. Each category is marked with an associated object once appended, so nothing is appended
   twice. `categoryForType:`'s own early-out means UIKit's builder still runs at most once per
   category.

The main-thread cost per category tap is then a set of ~843 stock glyph ids, two set lookups
per candidate, and one `arrayByAddingObjectsFromArray:`.

## Recents

`+[UIKeyboardEmojiCategory getGlyphForRecents:]` is replaced, because the original is sharp:

```c
buf = alloca(count * 8);                 /* 4 UTF-16 units per entry, hard cap */
...
line   = CTLineCreateWithAttributedString(<all recents concatenated>);
glyphs = CTRunGetGlyphsPtr(CTLineGetGlyphRuns(line)[0]);   /* run 0 only */
for (NSString *s in recents) [e setGlyph:*glyphs++];       /* one glyph each */
```

It never compares `CTLineGetGlyphCount` to the entry count. An eight-unit ZWJ family is
truncated to four units ending in a lone high surrogate, and if any entry shapes to two glyphs
the stream desynchronises and *every later recent draws someone else's picture*, then reads
past the end of the run. It is only reachable across a relaunch — within a session
`emojiUsed:` reuses the live objects and their glyphs.

The replacement resolves each entry on its own, keeps it only if it yields exactly one glyph
from the emoji font, and drops the rest. Entries keep their full `emojiString`, so the popup
and the inserted text stay correct. If nothing survives but the input was not empty, it defers
to the original rather than blanking the user's recents.

## Page dots

Paging itself is fully dynamic — `layoutPages` loops `while (idx < [emoji count])` and sets
`contentSize` and `numberOfPages` from the result, with no cap anywhere. The category bar does
not depend on the emoji count at all, only on the constant 6.

`EmojiPageControl` is the one thing that overflows: iOS 6 draws every dot with no clamping, so
~2600 People emoji at 21 per page is ~124 dots running off both edges of a 320 pt bar.
`-[UIKeyboardEmojiScrollView layoutPages]` is hooked to hide the page control when it would
exceed `PageDotLimit` (default 14). Nothing about paging changes; only the indicator is
hidden.

## What happens on a runtime this build does not expect

This is the difference between a tweak and a boot loop, so it is worth being exact. The filter
plist is `Bundles = (com.apple.UIKit)`, which is every process that shows a keyboard,
SpringBoard included. There is no situation in which this dylib may throw.

**Nothing is hooked until the runtime has been proven to match.** Before installing the main
hook the constructor requires, in order:

- `UIKeyboardEmojiCategory` and `UIKeyboardEmoji` to exist;
- `+categoryForType:` to return an object and take exactly one `int` (`NSMethodSignature`, so
  a build where the argument became `NSInteger`/`long long` is rejected rather than called
  with the wrong ABI);
- `+emojiWithString:` to return an object and take one object;
- `-setGlyph:` to take exactly one `unsigned short`, `-glyph` to return one, and
  `-emojiString` to return an object;
- `-emoji` to return an object and `-setEmoji:` to take one.

If any check fails, the constructor returns and **no hook is installed at all** — the process
behaves exactly as it does without the package. The two optional hooks
(`getGlyphForRecents:`, `layoutPages`) are guarded separately, so either can be skipped
without affecting the other or the main one.

**Nothing assumes a return shape.** `%orig` may return `nil` or something that is not a
`UIKeyboardEmojiCategory`; `-emoji` may return `nil` or a non-array; the elements may not
respond to `-glyph` or `-emojiString`. Each of those is checked at the point of use and
short-circuits to leaving the category alone. A category whose emoji array is empty is treated
as "not built yet" and skipped rather than marked, so it cannot be permanently poisoned by
being seen too early.

**Substrate is not linked.** `MSHookMessageEx` is resolved with `dlsym(RTLD_DEFAULT, …)` and
then by `dlopen` over four known paths. If none of them has it, the dylib falls back to
`method_setImplementation` — and only when the method is implemented directly on that exact
class, verified with `class_copyMethodList`. If that is not true either, no hook is installed.
A missing or renamed Substrate cannot stop the dylib from loading, because nothing about it is
a link-time dependency. UIKit is not linked either; every private class is reached through
`objc_getClass`.

**Everything that runs inside a hook runs inside `@try`.** An `NSException` from any of them
sets a global stop flag: from that point on every hook is a straight call to the original, for
the life of the process, and one line goes to syslog. That covers the `releaseCategories`
hazard — it does `[[self categories] removeAllObjects]` without nilling the static, so a later
`categoryForType:` would `objectAtIndex:` an empty array and raise `NSRangeException`. Nothing
in UIKit 6.1 calls it (every method of every `*Keyboard*` and `*UIPeripheral*` class was
scanned), but if something ever does, the exception is UIKit's own and this tweak stops rather
than compounding it.

**Missing or damaged data degrades to doing nothing.** A missing, truncated or wrong-format
`palette.plist` or `glyphs.plist` leaves the palette stock. A font that is not an emoji font,
or missing entirely, yields no candidates. A cache whose font fingerprint no longer matches is
discarded and reshaped.

**Two off switches that do not need dpkg**, both covered in Recovery above.

## Preferences

`/var/mobile/Library/Preferences/com.havrysh.emojikeyboard.plist`, read once per process with
a plain file read — no `cfprefsd`, so writing the file from SSH and relaunching is enough. Any
key that is missing or not a number falls back to its default, and an unreadable file means
all defaults.

| key | default | effect |
|---|---|---|
| `Enabled` | `YES` | `NO` installs no hooks |
| `SkinTones` | `YES` | `NO` drops skin-tone sequences at filter time (People 2416 → 386 candidates) |
| `HookRecents` | `YES` | `NO` leaves `+getGlyphForRecents:` alone |
| `HookPageDots` | `YES` | `NO` leaves `-layoutPages` alone |
| `PageDotLimit` | `14` | hide the page dots past this many pages; `0` never hides |
| `PrepareOnMainThread` | `NO` | `YES` builds the `UIKeyboardEmoji` objects on the main queue instead of the background one |
| `Verbose` | `NO` | `YES` logs what was appended, and timings, to syslog |

Changing `SkinTones` invalidates the glyph cache automatically.

## What was verified and what was not

### Verified

Everything below runs on `make check` and passes from a clean `make distclean; make deb`.

- **The build.** One command from an empty tree to a signed armv7 `.deb`, in about a second.
- **The binaries.** armv7 slice, iOS 6.0 deployment target, install name correct, constructor
  present, and — the two that matter — the dylib links neither UIKit nor Substrate, so neither
  a missing Substrate nor a private-framework change can stop it loading.
- **The filter.** `Filter = { Bundles = (com.apple.UIKit) }` and nothing else; no
  `Executables` or `Classes` clause widening it.
- **The package.** Ships the four payload files, depends on `mobilesubstrate` and on the font
  package at the right version floor, maintainer scripts parse as `sh`, no unsubstituted
  placeholder anywhere in `DEBIAN/`.
- **The candidate data.** 3101 sequences, no empties, no NULs, no unpaired surrogates, no
  duplicates, and exactly the five appendable category types.
- **The filter logic and the cache**, on the host: a cold shaping pass over every candidate, a
  warm run that must come out of the cache, a deliberately corrupted font stamp that must
  force a reshape, plus a damaged cache, a missing `palette.plist` and a truncated one — none
  of which may crash.
- **The hook's behaviour**, driven against stand-in `UIKeyboardEmojiCategory` /
  `UIKeyboardEmoji` classes carrying byte-for-byte the iOS 6.1.3 method signatures, pre-loaded
  with the real 843-slot stock palette from `evidence/ios6_emoji_tables.json`: stock entries
  keep their positions, nothing is appended twice, no cell would draw `.notdef`, no glyph or
  string appears in two cells, Recents is untouched, and the recents replacement keeps full
  strings and defers to the original when nothing survives.
- **Three unexpected-runtime cases**: `+categoryForType:` taking a `long long` instead of an
  `int`, `UIKeyboardEmoji.glyph` being 32 bits instead of 16, and the class not existing at
  all. All three must leave the stand-in palette byte-identical to what UIKit built, and do.
- **The dependency wiring**, all three `EMOJIKEYBOARD_FONTDEP` modes, and that
  `dpkg --compare-versions 17.0-20260816 ge 17.0` is true while a stale `16.0` font is
  correctly refused.

### Not verified

**Nothing in this project has run on hardware.** Not once. Everything above is a Mac
executing the same C against stand-in classes, which proves the logic and proves nothing about
the runtime.

Specifically unproven:

- that `+[UIKeyboardEmojiCategory categoryForType:]` on a real 10B329 device has the signature
  the guards expect, and therefore that a single hook is installed at all;
- every timing number. The host cold shape is 20 ms for 3101 candidates on an M-series Mac.
  The A5 figure is unknown and could plausibly be 50× that;
- that the glyph ids the tweak stores draw the right pictures. `CTFontDrawGlyphs` with one
  glyph is the whole rendering path, so a wrong id is a wrong picture, not a blank — the host
  test cannot see this because it has a different font;
- memory cost of ~2600 extra `UIKeyboardEmoji` objects in every process that opens the
  keyboard, on a 512 MB 4S;
- the iPad's `UIKeyboardEmojiPicker` family, which is a table view rather than the paged scroll
  view and was not disassembled in depth;
- whether skin tones on by default is usable on a 3.5-inch screen at ~124 pages, which is a
  judgement call, not a bug.

The counts printed by `make check` are this Mac's emoji coverage. They are not the device's
and mean nothing for it.

## On-device test plan

Two devices, in this order. Do the iPad 2 first: it is the less painful one to recover, and
steps 1–3 will have found a wrong hook before the 4S is ever touched.

Prerequisite: SSH working, and the `.deb` files from `out/` and `../emojitweak/out/` copied to
`/tmp` on the device.

### Step 0 — baseline, before installing anything

```sh
ssh root@<device> 'ls -la /Library/MobileSubstrate/DynamicLibraries/'
```

Note what else is loaded there. Open the emoji keyboard and confirm the stock palette works:
six tabs, People first, page dots present. Screenshot it. This is what "unchanged" looks like
later.

### Step 1 — font only

```sh
ssh root@<device> 'dpkg -i /tmp/com.havrysh.moderncoloremoji_*.deb'
```

Expect: modern emoji now *render* in Messages and Safari; the keyboard still offers the old
843. If the keyboard changed at this point, something other than these packages is hooking it.

### Step 2 — shape the palette without the keyboard in the picture

Install the keyboard package with the respring suppressed, so nothing loads yet:

```sh
ssh root@<device> 'EMOJIKEYBOARD_NO_RESPRING=1 dpkg -i /tmp/com.havrysh.emojikeyboard_*.deb'
```

`postinst` runs `emojipaletteprep` during that. **Read its output — this is the highest-value
number in the whole plan** and it comes before any hook has ever run:

- `shaped in N ms` is the cold cost on an A5. Under ~2000 ms: ship skin tones on. Over ~10000:
  rebuild with `EMOJIKEYBOARD_SKIN_TONES=0` and start again.
- the drawable total should be near 3101 — the font is built from the same `emoji-test.txt`,
  so it should cover essentially all of them, minus a handful the glyph dedupe removes. The
  Mac reaches 2664 (1986 / 77 / 233 / 323 / 45) with Apple's own font, so the device should be
  at or above those numbers. Well below means CoreText is not resolving the font you installed
  — check EmojiFontManager, and check the font package actually configured.

Run it again by hand to see a clean number:

```sh
ssh root@<device> '/var/lib/emojikeyboard/emojipaletteprep'
```

### Step 3 — load the hook, watching syslog

Turn on `Verbose` (the plist snippet is in Recovery), start `syslog -w | grep emojikeyboard`
in one SSH session, and respring from another:

```sh
ssh root@<device> 'killall -9 SpringBoard'
```

**What should appear:** `installed in SpringBoard`, then `palette … from cache in N ms` and
`category N: X stock + Y added` as you tap the tabs.

**What a wrong hook looks like** — and this is the point of doing it in this order:

| symptom | what it means | what to do |
|---|---|---|
| `…has an unexpected signature; doing nothing` | the guards rejected the runtime. Keyboard is stock, nothing is broken. | Send the line. It names the selector; the fix is in the guard, not on the device. |
| `installed in …` but no `category N:` lines | the hook is in, `%orig` returned something unexpected | Send the `category` lines that *are* there. |
| `… raised … ; every hook is now a straight pass-through` | an exception. The tweak self-disabled for that process. | Send the whole line with the exception name. This is the one real bug report. |
| nothing at all in syslog | the dylib did not load | Check the filter plist landed, check Substrate safe mode is not on. |
| SpringBoard crash loop | a hook faulted rather than raised | Recovery ladder rung 1, then rung 2. Grab `/var/mobile/Library/Logs/CrashReporter/`. |

A crash loop is the failure mode the guards exist to prevent, and it is also the only one that
needs the ladder. The others all leave a working keyboard.

### Step 4 — the grid

Open the emoji keyboard and go through all five appended tabs.

- **Every cell must be a picture.** A `.notdef` box or a blank cell means the filter let
  something through that CoreText cannot actually draw as one glyph.
- **No cell may be the wrong picture.** This is the failure the host test structurally cannot
  catch. Check specifically: one skin-tone sequence (🧑🏽), one ZWJ profession (👩‍🚀), one family
  (👨‍👩‍👦), one flag (🇺🇦), one keycap (1️⃣).
- **No emoji twice.** Scan People and Places in particular — those took the most candidates.
- **The first 189 cells of People must be the 2012 set, in the old order.** If the stock emoji
  moved, the append went in the wrong place.

Then tap several new emoji into a text field and confirm the *inserted text* is right, not
just the picture. A correct picture with wrong text means `emojiString` and `glyph` came from
different candidates.

### Step 5 — paging and both orientations

4S: 3×7 portrait, 2×11 landscape on a 4-inch screen, 2×10 on 3.5. iPad 2: 3×11 either way.

- Scroll to the last page of People. It must not be blank and must not be reachable past the
  end.
- The page dots must be hidden in People (well past the 14-page limit) and visible in Symbols.
  Set `PageDotLimit = 0` and confirm the dots come back and overflow the bar — that proves the
  hook is what is hiding them, not something else.
- Rotate with the keyboard open, mid-scroll.

### Step 6 — recents across a relaunch

The stock bug this replaces only fires across a relaunch, so:

1. Tap 6–8 new emoji, mixing a ZWJ family in with simple ones.
2. Force-quit the app and reopen it.
3. Open Recents and check **the whole row**, not the newest entry. A desync shows up as the
   *other* recents drawing someone else's picture.
4. Then set `HookRecents = NO`, respring, repeat. The stock path should now misbehave. If it
   does not, the replacement is unnecessary on this data — worth knowing either way.

### Step 7 — the shrink case

With the keyboard installed, scroll deep into People, then:

```sh
ssh root@<device> 'dpkg -r com.havrysh.moderncoloremoji; killall -9 SpringBoard'
```

Reopen the keyboard. `lastVisibleFirstEmojiIndex` is now past the end of a stock-sized
category. UIScrollView should clamp; confirm it does not land on a blank page. Then reinstall
the font and run `/var/lib/emojikeyboard/refresh`.

### Step 8 — pressure

- Simulate a memory warning with the keyboard open, and confirm nothing reaches
  `releaseCategories` (no exception line in syslog).
- On the 4S, measure the RSS of an app with the emoji keyboard open, with and without the
  tweak. ~2600 objects plus strings; confirm nothing gets jetsammed sooner than before.
- Leave the device running normally for a day with `Verbose = NO` and check
  `/var/mobile/Library/Logs/CrashReporter/` is not accumulating anything new.

### Step 9 — the iPad picker

`UIKeyboardEmojiPicker` / `…CategoryPicker` / `…CharacterPicker` is a table, not the paged
scroll view, and its row arithmetic was not disassembled in depth. On the iPad 2, open
whatever surfaces it and scroll the full length of a long category. This is the least
understood part of the system and the most likely place for a surprise.

### Step 10 — removal

Last, because it invalidates the rest:

```sh
ssh root@<device> 'touch /var/lib/emojikeyboard/disabled; killall -9 SpringBoard'   # rung 1
```

Confirm the keyboard is byte-for-byte the Step 0 screenshot. Then `rm` the file, respring,
confirm it comes back. Then:

```sh
ssh root@<device> 'dpkg -r com.havrysh.emojikeyboard'
```

Confirm both Substrate files are gone, the keyboard is stock, and the font still works. Then
`dpkg -P` and confirm `/var/lib/emojikeyboard/` and the preferences plist are gone too.

### Report back

The three things that decide what ships: `emojipaletteprep`'s `shaped in N ms` from Step 2,
the `palette … from cache in N ms` line from Step 3, and a photograph of the People tab from
Step 4 with skin tones on. Everything else is pass/fail.

## Interactions

**PoomSmart's EmojiFontManager** (`com.ps.emojifontmanager`) can redirect CoreText to a font
somewhere other than `/System/Library/Fonts/Cache/AppleColorEmoji.ttf`. This tweak asks
CoreText for the emoji font by name rather than opening a path, so it follows the redirect and
filters against whatever EFM actually resolved — which is the right behaviour, but it means
`postinst`'s "no modern emoji font found" warning can fire even though the keyboard will be
fine, and vice versa. `emojipaletteprep`'s drawable counts are the answer either way.

**EmojiPortLegacy** and other emoji-keyboard tweaks hook the same UIKit classes. Two tweaks
appending to the same category would double the palette or fight over `setGlyph:`. Nothing
here detects that; if another emoji keyboard tweak is installed, remove it first. There is no
`Conflicts` declared because the field would have to name packages that were never surveyed.

**EmojiAttributes** is a layout tweak and does not touch the palette.

## Files

```
build.py                   candidate list from emoji-test.txt -> out/palette.plist
src/EKPalette.{h,m}        data loading, CoreText filter, glyph cache, preferences
src/EKTweak.m              guards, hooks, append logic          -> EmojiKeyboard.dylib
src/EKPrep.m               install-time shaping tool            -> emojipaletteprep
package/EmojiKeyboard.plist  Substrate filter: Bundles = com.apple.UIKit
package/{control.in,postinst,postrm,refresh,respring}
mkdeb.sh                   package builder
verify.py                  static checks on the built products
hostcheck.sh               host-side behaviour and fail-safe suite
test/EKHookTest.m          hook driven against real-signature stand-ins
test/EKFailsafeTest.m      three unexpected-runtime cases
test/stocktable.py         the 843 stock slots -> a C table for the tests
evidence/                  the static analysis this is all based on
```

`evidence/disasm/*.txt` are Python tracebacks, not disassembly — that extraction pass failed
and wrote the files anyway. `evidence/ios6_emoji_tables.json` and the class-dump headers are
intact and are what everything here is built on.
