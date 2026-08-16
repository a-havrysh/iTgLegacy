import hashlib
import os
import pickle
import sys
import time
from multiprocessing import Pool

import emojidata as E
import fontasm
import raster

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "cache")
WORK = os.path.join(HERE, "work")
OUTDIR = os.path.join(HERE, "out")
OUT_NAMES = {"1x": "AppleColorEmoji.ttf", "2x": "AppleColorEmoji@2x.ttf"}

ZWJ = 0x200D
FE0F = 0xFE0F
KEYCAP = 0x20E3
TAGS = set(range(0xE0020, 0xE0080))
INVISIBLE = {ZWJ, FE0F} | TAGS
TEXT_BASES = {0x23, 0x2A} | set(range(0x30, 0x3A))


def gname(cps):
    return "_".join("u%04X" % c for c in cps)


def plan():
    test_path, ucd, emoji_ver = E.fetch_emoji_test(CACHE)
    svgdir, tag = E.fetch_twemoji(CACHE)
    entries = E.parse_emoji_test(test_path)
    identities, aliases = E.build_identities(entries)
    index = E.index_assets(svgdir)

    idset = {cps for cps, _, _ in identities}
    glyph_of = {cps: gname(cps) for cps in idset}

    cmap = {}
    for cps in idset:
        if len(cps) == 1:
            cmap[cps[0]] = glyph_of[cps]
    for key, target in aliases.items():
        if len(key) == 1 and key[0] not in cmap:
            cmap[key[0]] = glyph_of[target]

    all_cps = set()
    for key in aliases:
        all_cps.update(key)
    for cps in idset:
        all_cps.update(cps)

    synthetic = sorted(c for c in all_cps if c not in cmap)
    for c in synthetic:
        cmap[c] = gname((c,))

    seqs = []
    collisions = {}
    for key, target in sorted(aliases.items()):
        if len(key) < 2:
            continue
        comps = tuple(cmap[c] for c in key)
        lig = glyph_of[target]
        if comps in collisions and collisions[comps] != lig:
            continue
        collisions[comps] = lig
        seqs.append((comps, lig))

    dedup = {}
    for comps, lig in seqs:
        dedup[comps] = lig
    seqs = sorted(dedup.items())

    glyph_order = [".notdef"]
    glyph_order += [gname((c,)) for c in synthetic]
    glyph_order += sorted(glyph_of[c] for c in idset)

    zero_advance = {gname((c,)) for c in synthetic if c in INVISIBLE}

    art = {}
    for cps in idset:
        path = E.find_asset(index, cps)
        if path:
            art[glyph_of[cps]] = ("svg", path)
    for c in synthetic:
        n = gname((c,))
        if c in INVISIBLE:
            continue
        path = E.find_asset(index, (c,))
        if path:
            art[n] = ("svg", path)
        elif c in TEXT_BASES:
            art[n] = ("text", chr(c))
        elif c == KEYCAP:
            art[n] = ("keycap", "")

    unpainted = sorted(cps for cps in idset if glyph_of[cps] not in art)
    unpainted += sorted((c,) for c in synthetic
                        if c not in INVISIBLE and gname((c,)) not in art)

    meta = dict(ucd=ucd, emoji_ver=emoji_ver, twemoji=tag,
                identities=identities, aliases=aliases, idset=idset,
                glyph_of=glyph_of, unpainted=unpainted)
    return glyph_order, cmap, seqs, zero_advance, art, meta


def check_artwork(meta):
    unpainted = meta["unpainted"]
    if not unpainted:
        print("  artwork: every emoji has a Twemoji image")
        return
    listing = "\n".join("    " + " ".join("%04X" % c for c in cps)
                        for cps in unpainted[:20])
    more = "" if len(unpainted) <= 20 else "\n    ... and %d more" % (len(unpainted) - 20)
    message = (
        "%d emoji in Unicode Emoji %s have no Twemoji %s artwork and would ship as\n"
        "blank glyphs:\n%s%s\n\n"
        "Twemoji is behind this Unicode release. Either wait for a Twemoji release\n"
        "that covers it, pin an older emoji-test.txt, or set\n"
        "EMOJITWEAK_ALLOW_MISSING_ART=1 to ship the blanks deliberately."
        % (len(unpainted), meta["emoji_ver"], meta["twemoji"], listing, more))
    if os.environ.get("EMOJITWEAK_ALLOW_MISSING_ART"):
        print("  WARNING: " + message.replace("\n", "\n  "))
        return
    raise SystemExit("build.py: " + message)


def _render(job):
    name, kind, arg = job
    if kind == "svg":
        master = raster.render_master(arg)
    elif kind == "text":
        master = raster.render_text_master(arg)
    else:
        master = raster.render_keycap_master()
    return name, raster.strikes_for(master)


def rasterise(art, tag):
    key = hashlib.sha1(("%s|%s|%s|%s" % (tag, raster.MASTER, raster.STRIKES,
                                         sorted(raster.COLORS.items()))
                        ).encode()).hexdigest()[:16]
    os.makedirs(WORK, exist_ok=True)
    cache_path = os.path.join(WORK, "strikes-%s.pickle" % key)
    if os.path.exists(cache_path):
        with open(cache_path, "rb") as fh:
            cached = pickle.load(fh)
        if set(cached) == set(art):
            print("  raster cache hit: %s" % os.path.basename(cache_path))
            return cached

    jobs = [(n, k, a) for n, (k, a) in sorted(art.items())]
    t0 = time.time()
    out = {}
    with Pool() as pool:
        for i, (name, strikes) in enumerate(pool.imap_unordered(_render, jobs, 32), 1):
            out[name] = strikes
            if i % 500 == 0:
                print("  rasterised %d/%d (%.0fs)" % (i, len(jobs), time.time() - t0))
    print("  rasterised %d glyphs in %.0fs" % (len(out), time.time() - t0))
    with open(cache_path, "wb") as fh:
        pickle.dump(out, fh, protocol=4)
    return out


def main():
    t0 = time.time()
    print("resolving sources")
    glyph_order, cmap, seqs, zero_advance, art, meta = plan()
    print("  Unicode UCD %s / Emoji %s / twemoji %s"
          % (meta["ucd"], meta["emoji_ver"], meta["twemoji"]))
    print("  identities %d  glyphs %d  cmap entries %d  morx sequences %d"
          % (len(meta["idset"]), len(glyph_order), len(cmap), len(seqs)))
    check_artwork(meta)

    print("rasterising")
    raster.require_tools()
    rendered = rasterise(art, meta["twemoji"])

    strikes = {p: {} for p in raster.STRIKES}
    for name, per in rendered.items():
        for ppem, data in per.items():
            strikes[ppem][name] = data

    print("assembling")
    os.makedirs(OUTDIR, exist_ok=True)
    version = "%s;twemoji-%s" % (meta["emoji_ver"], meta["twemoji"].lstrip("v"))

    targets = dict(raster.VARIANTS)
    if os.environ.get("EMOJITWEAK_MEASURE_UNION"):
        targets["union"] = raster.STRIKES
        OUT_NAMES["union"] = "AppleColorEmoji-union.ttf"

    for variant in sorted(targets):
        ppems = targets[variant]
        subset = {p: strikes[p] for p in ppems}
        out = os.path.join(OUTDIR, OUT_NAMES[variant])
        fontasm.assemble(glyph_order, cmap, subset, seqs, zero_advance, version, out)

        size, tables, font = fontasm.report(out)
        print("\n=== %s  (%s, strikes %s)"
              % (out, variant, "/".join(str(p) for p in ppems)))
        print("total size            %8.2f MB" % (size / 1048576.0))
        for tag in ("sbix", "morx", "cmap", "glyf", "post", "hmtx"):
            if tag in tables:
                print("  %-4s                %8.2f MB" % (tag, tables[tag] / 1048576.0))
        for p in ppems:
            bytes_at = sum(len(v) for v in subset[p].values())
            print("  strike %3d           %8.2f MB  (%d glyphs, %d colors)"
                  % (p, bytes_at / 1048576.0, len(subset[p]), raster.COLORS[p]))
        print("  glyphs %d  morx subtables %d"
              % (font["maxp"].numGlyphs,
                 len(font["morx"].table.MorphChain[0].MorphSubtable)))
    print("  built in %.0fs" % (time.time() - t0))

    write_attribution(meta)
    print("  wrote %s" % os.path.join(OUTDIR, "COPYING"))
    return 0


ATTRIBUTION = """AppleColorEmoji replacement for iOS 6
built by tools/emojitweak/build.py

Emoji repertoire
  Unicode Emoji %(emoji_ver)s (emoji-test.txt, UCD %(ucd)s)
  Copyright (C) Unicode, Inc.  Used under the Unicode Terms of Use:
  https://www.unicode.org/terms_of_use.html

Artwork
  Twemoji %(twemoji)s -- https://github.com/jdecked/twemoji
  Copyright (C) Twitter, Inc and other contributors.
  Graphics licensed under CC-BY 4.0:
  https://creativecommons.org/licenses/by/4.0/

  MODIFICATIONS: the Twemoji SVG artwork was rasterised to PNG bitmaps at
  20, 40, 48, 64, 96 and 192 pixels per em, colour-quantised, and embedded as sbix
  bitmap strikes in a TrueType font. No Twemoji source file is redistributed
  unmodified.

This font contains no Apple artwork, outlines or font data. The family name
"Apple Color Emoji" and PostScript name "AppleColorEmoji" are used only so
that iOS 6 CoreText resolves the system emoji font to this file.
"""


def write_attribution(meta):
    text = ATTRIBUTION % dict(emoji_ver=meta["emoji_ver"], ucd=meta["ucd"],
                              twemoji=meta["twemoji"])
    with open(os.path.join(OUTDIR, "COPYING"), "w", encoding="utf-8") as fh:
        fh.write(text)


if __name__ == "__main__":
    sys.exit(main())
