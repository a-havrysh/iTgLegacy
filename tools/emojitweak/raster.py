import io
import os
import subprocess
from PIL import Image, ImageDraw, ImageFont

MASTER = 192
STRIKES = (20, 40, 48, 96)
COLORS = {20: 128, 40: 128, 48: 128, 96: 200}

TEXT_FONT_CANDIDATES = (
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "/Library/Fonts/Arial.ttf",
)


def render_master(svg_path, size=MASTER):
    out = subprocess.run(
        ["rsvg-convert", "-w", str(size), "-h", str(size), "-f", "png", svg_path],
        check=True, capture_output=True)
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
    return ImageFont.load_default()


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
