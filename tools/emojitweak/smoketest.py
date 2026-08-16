import os
import sys

import emojidata as E
import fontasm
import raster

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "cache")
OUT = os.path.join(HERE, "out", "smoke-AppleColorEmoji.ttf")

CASES = [
    (0x1F604,),
    (0x1F1FA, 0x1F1E6),
    (0x1F468, 0x200D, 0x1F469, 0x200D, 0x1F467),
    (0x1F468, 0x200D, 0x1F4BB),
    (0x1F44D, 0x1F3FD),
    (0x0031, 0xFE0F, 0x20E3),
    (0x2764, 0xFE0F, 0x200D, 0x1F525),
    (0x1F3F4, 0xE0067, 0xE0062, 0xE0073, 0xE0063, 0xE0074, 0xE007F),
]

ZERO = {0x200D, 0xFE0F} | set(range(0xE0020, 0xE0080))


def name_for(cps):
    return "_".join("u%04X" % c for c in cps)


def main():
    svgdir, tag = E.fetch_twemoji(CACHE)
    index = E.index_assets(svgdir)

    bases = sorted({c for seq in CASES for c in seq})
    ligs = [seq for seq in CASES if len(seq) > 1]

    glyph_order = [".notdef"]
    glyph_order += [name_for((c,)) for c in bases]
    glyph_order += [name_for(s) for s in ligs]

    strikes = {p: {} for p in raster.STRIKES}
    for c in bases:
        path = E.find_asset(index, (c,))
        if path is None:
            continue
        master = raster.render_master(path)
        for ppem, data in raster.strikes_for(master).items():
            strikes[ppem][name_for((c,))] = data
    for s in ligs:
        path = E.find_asset(index, s)
        if path is None:
            print("no art for", name_for(s))
            continue
        master = raster.render_master(path)
        for ppem, data in raster.strikes_for(master).items():
            strikes[ppem][name_for(s)] = data

    cmap = {c: name_for((c,)) for c in bases}
    seqs = [(tuple(name_for((c,)) for c in s), name_for(s)) for s in ligs]
    zero_advance = {name_for((c,)) for c in bases if c in ZERO}

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    fontasm.assemble(glyph_order, cmap, strikes, seqs, zero_advance,
                     "0.1;smoke;%s" % tag, OUT)
    size, tables, font = fontasm.report(OUT)
    print("wrote", OUT, "%.1f KB" % (size / 1024.0))
    print("glyphs", len(glyph_order), "morx bytes", tables.get("morx"),
          "sbix bytes", tables.get("sbix"))
    print("cmap subtables",
          [(t.format, t.platformID, t.platEncID) for t in font["cmap"].tables])
    return 0


if __name__ == "__main__":
    sys.exit(main())
