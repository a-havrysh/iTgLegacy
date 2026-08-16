import io
import os
import shutil
import subprocess
from PIL import Image, ImageDraw, ImageFont

MASTER = 192
VARIANTS = {
    "1x": (20, 40, 48, 96),
    "2x": (40, 64, 96, 192),
}
STRIKES = tuple(sorted({p for s in VARIANTS.values() for p in s}))
COLORS = {20: 128, 40: 128, 48: 128, 64: 160, 96: 200, 192: 256}

RSVG = os.environ.get("RSVG_CONVERT", "rsvg-convert")

TEXT_FONT_CANDIDATES = (
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "/Library/Fonts/Arial.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
)


def require_tools():
    if shutil.which(RSVG) is None:
        raise SystemExit(
            "raster.py: %r is not on PATH.\n"
            "Install it (brew install librsvg) or point RSVG_CONVERT at it." % RSVG)
    if not any(os.path.exists(p) for p in TEXT_FONT_CANDIDATES):
        raise SystemExit(
            "raster.py: none of the fallback text fonts exist:\n  %s\n"
            "Keycap digit components would render as an unreadable default bitmap. "
            "Add a path to TEXT_FONT_CANDIDATES."
            % "\n  ".join(TEXT_FONT_CANDIDATES))


def render_master(svg_path, size=MASTER):
    out = subprocess.run(
        [RSVG, "-w", str(size), "-h", str(size), "-f", "png", svg_path],
        check=True, capture_output=True)
    if not out.stdout:
        raise RuntimeError("%s produced no output for %s" % (RSVG, svg_path))
    return Image.open(io.BytesIO(out.stdout)).convert("RGBA")


def encode(img, ppem, colors):
    if img.size != (ppem, ppem):
        img = img.resize((ppem, ppem), Image.LANCZOS)
    pal = img.quantize(colors=colors, method=Image.FASTOCTREE, dither=Image.NONE)
    buf = io.BytesIO()
    pal.save(buf, format="PNG", optimize=True)
    data = buf.getvalue()
    buf2 = io.BytesIO()
    img.save(buf2, format="PNG", optimize=True)
    raw = buf2.getvalue()
    return data if len(data) <= len(raw) else raw


def strikes_for(master, sizes=STRIKES, colors=None):
    colors = colors or COLORS
    return {ppem: encode(master, ppem, colors[ppem]) for ppem in sizes}


def _text_font(px):
    for path in TEXT_FONT_CANDIDATES:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, px)
            except Exception:
                continue
    raise RuntimeError("no usable text font; run raster.require_tools() first")


def render_text_master(ch, size=MASTER):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    font = _text_font(int(size * 0.72))
    box = d.textbbox((0, 0), ch, font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    d.text((size / 2 - w / 2 - box[0], size * 0.55 - h / 2 - box[1]), ch,
           font=font, fill=(30, 30, 30, 255))
    return img


def render_keycap_master(size=MASTER):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pad = size * 0.06
    d.rounded_rectangle([pad, pad, size - pad, size - pad],
                        radius=size * 0.16, outline=(60, 60, 60, 255),
                        width=max(2, int(size * 0.045)))
    return img
