from fontTools.ttLib import TTFont, newTable
from fontTools.ttLib.tables._c_m_a_p import CmapSubtable
from fontTools.ttLib.tables._g_l_y_f import Glyph as GlyfGlyph, GlyphCoordinates
from fontTools.ttLib.tables.sbixGlyph import Glyph as SbixGlyph
from fontTools.ttLib.tables.sbixStrike import Strike
from fontTools.ttLib.tables import ttProgram
from fontTools.fontBuilder import FontBuilder

UPEM = 800
ADVANCE = 800
HHEA_ASCENT = 800
HHEA_DESCENT = -250
TYPO_ASCENT = 750
TYPO_DESCENT = -250
VHEA_ASCENT = 500
VHEA_DESCENT = -500

FAMILY = "Apple Color Emoji"
STYLE = "Regular"
POSTSCRIPT = "AppleColorEmoji"


def _box_glyph():
    g = GlyfGlyph()
    g.numberOfContours = 2
    g.endPtsOfContours = [0, 1]
    g.flags = bytearray([1, 1])
    g.coordinates = GlyphCoordinates([(0, 0), (UPEM, UPEM)])
    g.program = ttProgram.Program()
    g.program.fromBytecode(b"")
    return g


def _empty_glyph():
    g = GlyfGlyph()
    g.numberOfContours = 0
    g.endPtsOfContours = []
    g.flags = bytearray()
    g.coordinates = GlyphCoordinates([])
    return g


def make_cmap(mapping):
    tbl = newTable("cmap")
    tbl.tableVersion = 0
    tbl.tables = []
    for enc in (3, 4):
        sub = CmapSubtable.newSubtable(12)
        sub.platformID = 0
        sub.platEncID = enc
        sub.language = 0
        sub.format = 12
        sub.reserved = 0
        sub.length = 0
        sub.numGroups = 0
        sub.cmap = dict(mapping)
        sub.data = None
        tbl.tables.append(sub)
    return tbl


def make_sbix(strikes, glyph_order):
    tbl = newTable("sbix")
    tbl.version = 1
    tbl.flags = 1
    tbl.numStrikes = len(strikes)
    tbl.strikes = {}
    for ppem in sorted(strikes):
        strike = Strike(ppem=ppem, resolution=72)
        images = strikes[ppem]
        for name in glyph_order:
            data = images.get(name)
            if data is None:
                strike.glyphs[name] = SbixGlyph(glyphName=name, graphicType=None,
                                                imageData=None)
            else:
                strike.glyphs[name] = SbixGlyph(glyphName=name, graphicType="png ",
                                                imageData=data, originOffsetX=0,
                                                originOffsetY=0)
        tbl.strikes[ppem] = strike
    return tbl


def assemble(glyph_order, cmap_mapping, strikes, seqs, zero_advance, version_str,
             out_path):
    fb = FontBuilder(UPEM, isTTF=True)
    fb.setupGlyphOrder(glyph_order)

    glyphs = {}
    for name in glyph_order:
        if name in (".notdef", ".null") or name in zero_advance:
            glyphs[name] = _empty_glyph()
        else:
            glyphs[name] = _box_glyph()
    fb.setupGlyf(glyphs, calcGlyphBounds=True)

    metrics = {}
    for name in glyph_order:
        adv = 0 if (name in zero_advance or name == ".null") else ADVANCE
        metrics[name] = (adv, 0)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=HHEA_ASCENT, descent=HHEA_DESCENT, lineGap=0)

    fb.font["cmap"] = make_cmap(cmap_mapping)

    fb.setupNameTable({
        "familyName": FAMILY,
        "styleName": STYLE,
        "uniqueFontIdentifier": "%s; %s" % (FAMILY, version_str),
        "fullName": FAMILY,
        "version": version_str,
        "psName": POSTSCRIPT,
    }, mac=True, windows=True)

    fb.setupOS2(version=3, sTypoAscender=TYPO_ASCENT, sTypoDescender=TYPO_DESCENT,
                sTypoLineGap=0, usWinAscent=0, usWinDescent=0, sxHeight=500,
                sCapHeight=UPEM, fsType=0, usWeightClass=400, usWidthClass=5,
                fsSelection=64, xAvgCharWidth=733,
                panose=dict(bFamilyType=0, bSerifStyle=0, bWeight=0, bProportion=0,
                            bContrast=0, bStrokeVariation=0, bArmStyle=0,
                            bLetterForm=0, bMidline=0, bXHeight=0))
    fb.setupPost(keepGlyphNames=True, italicAngle=0, underlinePosition=-75,
                 underlineThickness=50, isFixedPitch=0)

    font = fb.font

    vhea = newTable("vhea")
    vhea.tableVersion = 0x00011000
    vhea.ascent = VHEA_ASCENT
    vhea.descent = VHEA_DESCENT
    vhea.lineGap = 0
    vhea.advanceHeightMax = UPEM
    vhea.minTopSideBearing = 0
    vhea.minBottomSideBearing = 0
    vhea.yMaxExtent = 0
    vhea.caretSlopeRise = 0
    vhea.caretSlopeRun = 1
    vhea.caretOffset = 0
    vhea.reserved1 = vhea.reserved2 = vhea.reserved3 = vhea.reserved4 = 0
    vhea.metricDataFormat = 0
    vhea.numberOfVMetrics = len(glyph_order)
    font["vhea"] = vhea

    vmtx = newTable("vmtx")
    vmtx.metrics = {n: (UPEM, 0) for n in glyph_order}
    font["vmtx"] = vmtx

    font["morx"] = make_morx_for(font, seqs)
    font["sbix"] = make_sbix(strikes, glyph_order)

    head = font["head"]
    head.flags = 265
    head.lowestRecPPEM = 9
    head.unitsPerEm = UPEM

    font.save(out_path)
    return out_path


def make_morx_for(font, seqs):
    from morxbuild import make_morx
    order = font.getGlyphOrder()
    gid = {n: i for i, n in enumerate(order)}.__getitem__
    return make_morx(seqs, gid)


def report(path):
    import os
    font = TTFont(path, lazy=True)
    sizes = {}
    with open(path, "rb") as fh:
        import struct
        fh.seek(4)
        num = struct.unpack(">H", fh.read(2))[0]
        fh.seek(12)
        for _ in range(num):
            tag, _cs, _off, ln = struct.unpack(">4sLLL", fh.read(16))
            sizes[tag.decode()] = ln
    return os.path.getsize(path), sizes, font
