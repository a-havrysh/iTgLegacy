import glob
import os
import plistlib
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
DYLIB = os.path.join(OUT, "EmojiKeyboard.dylib")
PREP = os.path.join(OUT, "emojipaletteprep")
PALETTE = os.path.join(OUT, "palette.plist")
FILTER = os.path.join(HERE, "package", "EmojiKeyboard.plist")

FAILURES = []


def check(condition, message):
    print("  %s  %s" % ("ok  " if condition else "FAIL", message))
    if not condition:
        FAILURES.append(message)


def run(*args):
    return subprocess.run(args, capture_output=True, text=True).stdout


def check_macho(path, kind):
    print("%s (%s)" % (os.path.basename(path), kind))
    check(os.path.exists(path), "exists")
    if not os.path.exists(path):
        return
    check("armv7" in run("lipo", "-info", path), "armv7 slice")
    linked = "\n".join(l for l in run("otool", "-L", path).split("\n")[2:]
                       if l.startswith("\t"))
    check("UIKit" not in linked,
          "does not link UIKit (private classes are resolved at runtime)")
    check("substrate" not in linked.lower(),
          "does not link Substrate (resolved with dlsym, so a missing "
          "Substrate cannot break the load)")
    load = run("otool", "-l", path)
    check("LC_VERSION_MIN_IPHONEOS" in load, "built for iPhoneOS")
    check("\n      minos 6.0" in load or "6.0" in load.split("LC_VERSION_MIN_IPHONEOS")[-1][:200],
          "deployment target 6.0")
    if kind == "dylib":
        check("/Library/MobileSubstrate/DynamicLibraries/EmojiKeyboard.dylib" in load,
              "install name is the MobileSubstrate path")
        check("__mod_init_func" in load, "has a constructor")


def check_filter():
    print("EmojiKeyboard.plist (Substrate filter)")
    check(os.path.exists(FILTER), "exists")
    if not os.path.exists(FILTER):
        return
    with open(FILTER, "rb") as fh:
        root = plistlib.load(fh)
    bundles = root.get("Filter", {}).get("Bundles")
    check(bundles == ["com.apple.UIKit"],
          "loads only into processes that link UIKit")
    check(set(root.get("Filter", {})) == {"Bundles"},
          "no Executables or Classes clause widening the filter")


def check_palette():
    print("palette.plist (candidate list)")
    check(os.path.exists(PALETTE), "exists")
    if not os.path.exists(PALETTE):
        return
    with open(PALETTE, "rb") as fh:
        root = plistlib.load(fh)
    check(root.get("format") == 1, "format 1")
    categories = root.get("categories", {})
    check(sorted(categories) == ["1", "2", "3", "4", "5"],
          "exactly the five appendable iOS 6 category types (Recents is left alone)")

    total = 0
    bad_empty = 0
    bad_surrogate = 0
    bad_nul = 0
    for key in sorted(categories):
        for text in categories[key]:
            total += 1
            if not text:
                bad_empty += 1
            if "\x00" in text:
                bad_nul += 1
            units = text.encode("utf-16-le")
            i = 0
            while i < len(units):
                unit = units[i] | (units[i + 1] << 8)
                if 0xD800 <= unit <= 0xDBFF:
                    if i + 3 >= len(units):
                        bad_surrogate += 1
                        break
                    low = units[i + 2] | (units[i + 3] << 8)
                    if not 0xDC00 <= low <= 0xDFFF:
                        bad_surrogate += 1
                        break
                    i += 4
                    continue
                if 0xDC00 <= unit <= 0xDFFF:
                    bad_surrogate += 1
                    break
                i += 2
    check(bad_empty == 0, "no empty candidates")
    check(bad_nul == 0, "no NUL in any candidate")
    check(bad_surrogate == 0, "no unpaired surrogates")
    check(total > 0, "%d candidates" % total)

    seen = set()
    duplicates = sum(1 for key in sorted(categories) for t in categories[key]
                     if t in seen or seen.add(t))
    check(duplicates == 0, "no candidate appears twice")


def check_deb():
    debs = sorted(glob.glob(os.path.join(OUT, "*.deb")))
    print("package")
    check(bool(debs), "a .deb was built")
    if not debs:
        return
    deb = debs[-1]
    listing = run("dpkg-deb", "-c", deb)
    for path in ("/Library/MobileSubstrate/DynamicLibraries/EmojiKeyboard.dylib",
                 "/Library/MobileSubstrate/DynamicLibraries/EmojiKeyboard.plist",
                 "/var/lib/emojikeyboard/palette.plist",
                 "/var/lib/emojikeyboard/emojipaletteprep"):
        check(path in listing, "ships %s" % path)
    control = run("dpkg-deb", "-I", deb, "control")
    fields = {}
    for line in control.split("\n"):
        if line[:1] not in (" ", "") and ":" in line:
            key, _, value = line.partition(":")
            fields[key.strip()] = value.strip()
    check("mobilesubstrate" in fields.get("Depends", ""),
          "depends on mobilesubstrate")

    with open(PALETTE, "rb") as fh:
        version = plistlib.load(fh)["unicode"]
    font = os.environ.get("EMOJIKEYBOARD_FONTPACKAGE", "com.havrysh.moderncoloremoji")
    spec = "%s (>= %s)" % (font, version)
    relationship = ("Depends" if spec in fields.get("Depends", "")
                    else "Recommends" if spec in fields.get("Recommends", "")
                    else None)
    check(relationship is not None,
          "%s is a %s relationship (an emoji the font cannot draw is never "
          "offered, but without the font there is nothing to offer)"
          % (spec, (relationship or "missing").lower()))
    check(font in control,
          "the font package is named in the description either way")

    check("@" not in control.replace("kesha1511@gmail.com", ""),
          "no unsubstituted placeholder in control")
    for script in ("postinst", "postrm"):
        body = run("dpkg-deb", "-I", deb, script)
        check(body.startswith("#!/bin/sh"), "%s is a shell script" % script)
        check("@" not in body, "no unsubstituted placeholder in %s" % script)


def main():
    check_macho(DYLIB, "dylib")
    check_macho(PREP, "prep tool")
    check_filter()
    check_palette()
    check_deb()
    print("")
    if FAILURES:
        print("verify: %d check(s) failed" % len(FAILURES))
        return 1
    print("verify: everything checks out")
    return 0


if __name__ == "__main__":
    sys.exit(main())
