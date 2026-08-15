#!/usr/bin/env python3
"""Draw side-by-side comparisons for each hardware limit."""
import os

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   'docs', 'design-proposals', 'svg')

W, H = 320, 480
GAP = 34
PAD = 16
LABEL = 30
TOTAL_W = W * 2 + GAP + PAD * 2
TOTAL_H = H + LABEL + PAD * 2

HEAD = ('<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
        'width="%d" height="%d">'
        '<defs><linearGradient id="nav" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#7699c0"/><stop offset="1" stop-color="#42678f"/></linearGradient>'
        '<linearGradient id="mnav" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#f7f7f7"/><stop offset="1" stop-color="#efefef"/></linearGradient>'
        '</defs>'
        '<rect width="%d" height="%d" fill="#e9edf2"/>' % (TOTAL_W, TOTAL_H, TOTAL_W, TOTAL_H))
TAIL = '</svg>'


def label(x, text, colour):
    return ('<text x="%d" y="%d" font-family="Helvetica" font-size="13" font-weight="bold" '
            'fill="%s" letter-spacing="0.6">%s</text>' % (x, PAD + 18, colour, text))


def frame(x):
    return ('<rect x="%d" y="%d" width="%d" height="%d" fill="#000" rx="3"/>'
            % (x - 1, PAD + LABEL - 1, W + 2, H + 2))


def modern_chrome(x, y, title, sub=''):
    """A flat modern nav bar, to stand for today's client."""
    out = '<rect x="%d" y="%d" width="%d" height="%d" fill="#fff"/>' % (x, y, W, H)
    out += '<rect x="%d" y="%d" width="%d" height="20" fill="#fff"/>' % (x, y, W)
    out += ('<text x="%d" y="%d" font-family="Helvetica" font-size="11" fill="#000">9:41</text>'
            % (x + 12, y + 14))
    out += '<rect x="%d" y="%d" width="%d" height="44" fill="url(#mnav)"/>' % (x, y + 20, W)
    out += ('<text x="%d" y="%d" font-family="Helvetica" font-size="17" font-weight="bold" '
            'fill="#000" text-anchor="middle">%s</text>' % (x + W // 2, y + 48, title))
    if sub:
        out += ('<text x="%d" y="%d" font-family="Helvetica" font-size="11" fill="#8e8e93" '
                'text-anchor="middle">%s</text>' % (x + W // 2, y + 60, sub))
    out += '<rect x="%d" y="%d" width="%d" height="1" fill="#c8c7cc"/>' % (x, y + 64, W)
    return out


def legacy_chrome(x, y, title, sub=''):
    out = '<rect x="%d" y="%d" width="%d" height="%d" fill="#e5e8ec"/>' % (x, y, W, H)
    out += '<rect x="%d" y="%d" width="%d" height="20" fill="#000"/>' % (x, y, W)
    out += ('<text x="%d" y="%d" font-family="Helvetica" font-size="11" font-weight="bold" '
            'fill="#fff">9:41</text>' % (x + 12, y + 14))
    out += '<rect x="%d" y="%d" width="%d" height="44" fill="url(#nav)"/>' % (x, y + 20, W)
    out += ('<image x="%d" y="%d" width="62" height="30" xlink:href="ASSET:BackButton"/>'
            % (x + 6, y + 27))
    out += ('<text x="%d" y="%d" font-family="Helvetica" font-size="12" fill="#fff" '
            'text-anchor="middle">Back</text>' % (x + 41, y + 46))
    yy = y + 48 if not sub else y + 44
    out += ('<text x="%d" y="%d" font-family="Helvetica" font-size="19" font-weight="bold" '
            'fill="#fff" text-anchor="middle">%s</text>' % (x + W // 2, yy, title))
    if sub:
        out += ('<text x="%d" y="%d" font-family="Helvetica" font-size="11" '
                'fill="#ccd8e6" text-anchor="middle">%s</text>' % (x + W // 2, y + 58, sub))
    return out


def txt(x, y, s, size=14, fill='#111', weight='normal', anchor='start', family='Helvetica'):
    return ('<text x="%d" y="%d" font-family="%s" font-size="%s" font-weight="%s" fill="%s" '
            'text-anchor="%s">%s</text>' % (x, y, family, size, weight, fill, anchor, s))


def row(x, y, w, h, fill='#fff', stroke='#d6dae0'):
    return ('<rect x="%d" y="%d" width="%d" height="%d" fill="%s" stroke="%s" stroke-width="1"/>'
            % (x, y, w, h, fill, stroke))


def note(x, y, w, lines, colour='#a8741d'):
    out = '<rect x="%d" y="%d" width="%d" height="%d" fill="#fdf6e6" stroke="%s"/>' % (
        x, y, w, 20 + 15 * len(lines), colour)
    out += '<rect x="%d" y="%d" width="3" height="%d" fill="%s"/>' % (x, y, 20 + 15 * len(lines), colour)
    for i, line in enumerate(lines):
        out += txt(x + 11, y + 17 + 15 * i, line, 11, '#6b4a10')
    return out


LEFT = PAD
RIGHT = PAD + W + GAP
TOP = PAD + LABEL


def build(name, left_body, right_body):
    svg = HEAD
    svg += label(LEFT, 'HOW IT WORKS TODAY', '#8b97a5')
    svg += label(RIGHT, 'WHAT WE CAN DO', '#a8741d')
    svg += frame(LEFT) + frame(RIGHT)
    svg += left_body(LEFT, TOP)
    svg += right_body(RIGHT, TOP)
    svg += TAIL
    with open(os.path.join(OUT, name), 'w', encoding='utf-8') as handle:
        handle.write(svg)
    return name


# ---------------------------------------------------------------- statistics

def stats_modern(x, y):
    o = modern_chrome(x, y, 'Statistics')
    o += txt(x + 16, y + 96, 'Followers', 13, '#8e8e93', 'bold')
    o += txt(x + 16, y + 118, '128 402', 26, '#000', 'bold')
    o += txt(x + 120, y + 118, '+2 190 this week', 12, '#34c759')
    pts = [(0, 70), (40, 58), (80, 62), (120, 40), (160, 44), (200, 26), (240, 30), (288, 8)]
    path = ' '.join('%s%d,%d' % ('M' if i == 0 else 'L', x + 16 + px, y + 150 + py)
                    for i, (px, py) in enumerate(pts))
    o += ('<path d="%s L%d,%d L%d,%d Z" fill="#e8f2fd"/>' % (
        path, x + 16 + 288, y + 230, x + 16, y + 230))
    o += '<path d="%s" fill="none" stroke="#007aff" stroke-width="2"/>' % path
    for px, py in pts:
        o += '<circle cx="%d" cy="%d" r="2.5" fill="#007aff"/>' % (x + 16 + px, y + 150 + py)
    o += '<rect x="%d" y="%d" width="%d" height="26" fill="#f2f2f7" rx="5"/>' % (x + 16, y + 244, 288)
    o += '<rect x="%d" y="%d" width="150" height="26" fill="#007aff" rx="5"/>' % (x + 90, y + 244)
    o += '<circle cx="%d" cy="%d" r="7" fill="#fff" stroke="#007aff" stroke-width="2"/>' % (x + 90, y + 257)
    o += '<circle cx="%d" cy="%d" r="7" fill="#fff" stroke="#007aff" stroke-width="2"/>' % (x + 240, y + 257)
    o += txt(x + 160, y + 288, 'drag either handle to zoom the range', 11, '#8e8e93', 'normal', 'middle')
    o += '<rect x="%d" y="%d" width="118" height="46" fill="#fff" stroke="#d1d1d6" rx="6"/>' % (x + 150, y + 96)
    o += txt(x + 160, y + 114, '14 Aug', 11, '#8e8e93', 'bold')
    o += txt(x + 160, y + 132, '126 212', 15, '#000', 'bold')
    o += txt(x + 160, y + 330, 'tap any point for a tooltip', 11, '#8e8e93')
    o += txt(x + 160, y + 350, 'pinch to zoom, two-finger pan', 11, '#8e8e93', 'normal', 'middle')
    return o


def stats_ours(x, y):
    o = legacy_chrome(x, y, 'Statistics')
    yy = y + 76
    o += txt(x + 14, yy + 14, 'GROWTH', 12, '#5d708f', 'bold')
    for i, (k, v, c) in enumerate([('Followers', '128 402', '#111'),
                                   ('This week', '+2 190', '#3aa03a'),
                                   ('This month', '+8 940', '#3aa03a'),
                                   ('Notifications', '81%', '#111')]):
        ry = yy + 22 + i * 44
        o += row(x + 8, ry, W - 16, 44)
        o += txt(x + 20, ry + 27, k, 15)
        o += txt(x + W - 20, ry + 27, v, 15, c, 'bold', 'end')
    yy2 = yy + 22 + 4 * 44 + 18
    o += txt(x + 14, yy2, 'LAST 7 DAYS', 12, '#5d708f', 'bold')
    o += row(x + 8, yy2 + 8, W - 16, 96)
    bars = [42, 55, 48, 70, 62, 88, 76]
    days = ['M', 'T', 'W', 'T', 'F', 'S', 'S']
    for i, b in enumerate(bars):
        bx = x + 26 + i * 40
        o += '<rect x="%d" y="%d" width="22" height="%d" fill="#5d8ec4"/>' % (bx, yy2 + 88 - b, b)
        o += txt(bx + 11, yy2 + 100, days[i], 10, '#8b97a5', 'normal', 'middle')
    o += note(x + 8, yy2 + 118, W - 16,
              ['A drawn bar chart, redrawn only when the data',
               'changes. No zoom, no range handles, no tooltips:',
               'those need continuous path re-tessellation.'])
    return o


# ---------------------------------------------------------------- instant view

def iv_modern(x, y):
    o = modern_chrome(x, y, 'Article')
    o += '<rect x="%d" y="%d" width="%d" height="118" fill="#dfe6ee"/>' % (x, y + 65, W)
    o += '<circle cx="%d" cy="%d" r="26" fill="#c3d2e2"/>' % (x + 60, y + 118)
    o += '<path d="M%d,%d L%d,%d L%d,%d L%d,%d Z" fill="#aec1d6"/>' % (
        x + 150, y + 183, x + 200, y + 120, x + 250, y + 183, x + 150, y + 183)
    o += txt(x + 16, y + 208, 'The quiet return of the', 21, '#000', 'bold')
    o += txt(x + 16, y + 232, 'small phone', 21, '#000', 'bold')
    o += txt(x + 16, y + 254, 'Anna Petrova  ·  8 min read', 12, '#8e8e93')
    o += '<rect x="%d" y="%d" width="%d" height="1" fill="#e5e5ea"/>' % (x + 16, y + 266, W - 32)
    for i in range(7):
        wid = W - 32 if i % 3 != 2 else 210
        o += '<rect x="%d" y="%d" width="%d" height="9" fill="#d8d8dd" rx="2"/>' % (
            x + 16, y + 282 + i * 18, wid)
    o += '<rect x="%d" y="%d" width="%d" height="60" fill="#f2f2f7" rx="6"/>' % (x + 16, y + 414, W - 32)
    o += txt(x + 28, y + 438, 'Rendered natively, in-app,', 12, '#8e8e93')
    o += txt(x + 28, y + 456, 'typography under our control.', 12, '#8e8e93')
    return o


def iv_ours(x, y):
    o = legacy_chrome(x, y, 'Chat', 'Anna Petrova')
    o += '<rect x="%d" y="%d" width="%d" height="%d" fill="#dfe3d8"/>' % (x, y + 64, W, H - 64)
    bx, by = x + 12, y + 84
    o += '<image x="%d" y="%d" width="250" height="150" xlink:href="ASSET:Msg_In" ' \
         'preserveAspectRatio="none"/>' % (bx, by)
    o += '<rect x="%d" y="%d" width="3" height="112" fill="#3a76b0"/>' % (bx + 18, by + 16)
    o += txt(bx + 30, by + 30, 'telegraph.style', 12, '#3a76b0', 'bold')
    o += txt(bx + 30, by + 50, 'The quiet return of the', 13, '#111', 'bold')
    o += txt(bx + 30, by + 68, 'small phone', 13, '#111', 'bold')
    o += txt(bx + 30, by + 88, 'A 4-inch screen forces', 12, '#555')
    o += txt(bx + 30, by + 104, 'choices a large one never...', 12, '#555')
    o += txt(bx + 210, by + 136, '14:02', 11, '#8b97a5')
    o += row(x + 12, y + 254, W - 24, 44, '#f6f7f9')
    o += txt(x + 26, y + 281, 'Open link', 15, '#2f6ba8', 'bold')
    o += txt(x + W - 26, y + 281, '›', 18, '#b7bec7', 'normal', 'end')
    o += note(x + 12, y + 312, W - 24,
              ['The preview is ours, drawn in the bubble.',
               'The article itself opens in the system browser:',
               'iOS 6 has only UIWebView, which cannot render',
               'an Instant View page at acceptable speed.'])
    return o


# ---------------------------------------------------------------- stories

def stories_modern(x, y):
    o = '<rect x="%d" y="%d" width="%d" height="%d" fill="#0b0b0d"/>' % (x, y, W, H)
    o += ('<defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">'
          '<stop offset="0" stop-color="#2a3550"/><stop offset="0.6" stop-color="#7d5a72"/>'
          '<stop offset="1" stop-color="#e0885c"/></linearGradient></defs>')
    o += '<rect x="%d" y="%d" width="%d" height="%d" fill="url(#sky)"/>' % (x, y, W, H)
    o += '<circle cx="%d" cy="%d" r="26" fill="#ffd9a0"/>' % (x + 210, y + 300)
    o += '<path d="M%d,%d L%d,%d L%d,%d L%d,%d L%d,%d Z" fill="#1d2333"/>' % (
        x, y + H, x + 90, y + 330, x + 160, y + 400, x + 250, y + 320, x + W, y + H)
    for i in range(5):
        seg = (W - 24) // 5 - 4
        fill = '#fff' if i < 2 else 'rgba(255,255,255,.35)'
        o += '<rect x="%d" y="%d" width="%d" height="3" fill="%s" rx="1.5"/>' % (
            x + 12 + i * (seg + 4), y + 12, seg, fill)
    o += '<circle cx="%d" cy="%d" r="15" fill="#c8b8a0" stroke="#fff" stroke-width="1.5"/>' % (x + 28, y + 40)
    o += txt(x + 52, y + 38, 'Alena Grishko', 13, '#fff', 'bold')
    o += txt(x + 52, y + 54, '3 h ago', 11, 'rgba(255,255,255,.75)')
    o += txt(x + W - 20, y + 46, '×', 22, '#fff', 'normal', 'end')
    o += txt(x + 16, y + 388, 'Last light over the river.', 15, '#fff')
    o += '<rect x="%d" y="%d" width="%d" height="34" fill="rgba(255,255,255,.18)" rx="17"/>' % (
        x + 14, y + 420, W - 96)
    o += txt(x + 32, y + 442, 'Send message', 13, 'rgba(255,255,255,.85)')
    o += txt(x + W - 56, y + 444, '♥', 20, '#fff')
    o += txt(x + W - 26, y + 444, '↗', 18, '#fff')
    o += txt(x + W // 2, y + 470, 'swipe down to dismiss  ·  swipe up for more',
             10, 'rgba(255,255,255,.6)', 'normal', 'middle')
    return o


def stories_ours(x, y):
    o = legacy_chrome(x, y, 'Alena Grishko', '2 of 5  ·  3 h ago')
    for i in range(5):
        seg = (W - 24) // 5 - 4
        fill = '#fff' if i < 2 else 'rgba(255,255,255,.35)'
        o += '<rect x="%d" y="%d" width="%d" height="3" fill="%s"/>' % (
            x + 12 + i * (seg + 4), y + 66, seg, fill)
    o += '<rect x="%d" y="%d" width="%d" height="%d" fill="#000"/>' % (x, y + 72, W, H - 72 - 40)
    o += ('<defs><linearGradient id="sky2" x1="0" y1="0" x2="0" y2="1">'
          '<stop offset="0" stop-color="#2a3550"/><stop offset="0.6" stop-color="#7d5a72"/>'
          '<stop offset="1" stop-color="#e0885c"/></linearGradient></defs>')
    o += '<rect x="%d" y="%d" width="200" height="300" fill="url(#sky2)"/>' % (x + 60, y + 82)
    o += '<circle cx="%d" cy="%d" r="20" fill="#ffd9a0"/>' % (x + 190, y + 250)
    o += '<path d="M%d,%d L%d,%d L%d,%d L%d,%d Z" fill="#1d2333"/>' % (
        x + 60, y + 382, x + 130, y + 300, x + 200, y + 382, x + 60, y + 382)
    o += '<rect x="%d" y="%d" width="200" height="42" fill="rgba(0,0,0,.55)"/>' % (x + 60, y + 340)
    o += txt(x + 70, y + 358, 'Last light over the river.', 12, '#fff')
    o += txt(x + 70, y + 374, 'Went the long way home.', 12, '#fff')
    o += '<image x="%d" y="%d" width="100" height="30" xlink:href="ASSET:ButtonGroupLeft"/>' % (x + 10, y + H - 36)
    o += '<image x="%d" y="%d" width="100" height="30" xlink:href="ASSET:ButtonGroupCenter"/>' % (x + 110, y + H - 36)
    o += '<image x="%d" y="%d" width="100" height="30" xlink:href="ASSET:ButtonGroupRight"/>' % (x + 210, y + H - 36)
    o += txt(x + 60, y + H - 16, 'Reply', 12, '#fff', 'bold', 'middle')
    o += txt(x + 160, y + H - 16, '♥ 12', 12, '#fff', 'bold', 'middle')
    o += txt(x + 260, y + H - 16, 'Share', 12, '#fff', 'bold', 'middle')
    o += note(x + 10, y + 388, W - 20,
              ['Nav bar stays: iOS 6 has no swipe-to-dismiss,',
               'so Back is the only way out. Tap the sides to',
               'advance. No timer, which would skip on slow data.'])
    return o


# ---------------------------------------------------------------- stickers

def stick_modern(x, y):
    o = modern_chrome(x, y, 'Stickers')
    cols, rows_n = 4, 4
    for r in range(rows_n):
        for c in range(cols):
            cx = x + 22 + c * 72
            cy = y + 92 + r * 76
            hue = (r * 4 + c) * 23 % 360
            o += ('<circle cx="%d" cy="%d" r="28" fill="hsl(%d,62%%,72%%)"/>'
                  % (cx + 28, cy + 28, hue))
            o += '<circle cx="%d" cy="%d" r="4" fill="#3a3a3a"/>' % (cx + 19, cy + 22)
            o += '<circle cx="%d" cy="%d" r="4" fill="#3a3a3a"/>' % (cx + 37, cy + 22)
            o += ('<path d="M%d,%d Q%d,%d %d,%d" stroke="#3a3a3a" stroke-width="2.5" fill="none"/>'
                  % (cx + 17, cy + 34, cx + 28, cy + 44, cx + 39, cy + 34))
    o += '<rect x="%d" y="%d" width="%d" height="52" fill="rgba(255,255,255,.94)"/>' % (x, y + H - 52, W)
    o += txt(x + W // 2, y + H - 20, 'every tile animating at 60fps', 12, '#8e8e93', 'normal', 'middle')
    return o


def stick_ours(x, y):
    o = legacy_chrome(x, y, 'Stickers')
    o += '<rect x="%d" y="%d" width="%d" height="%d" fill="#dfe3d8"/>' % (x, y + 64, W, H - 64)
    o += '<image x="%d" y="%d" width="%d" height="80" xlink:href="ASSET:Cell102" ' \
         'preserveAspectRatio="none"/>' % (x, y + 72, W)
    o += '<image x="%d" y="%d" width="%d" height="80" xlink:href="ASSET:Cell102" ' \
         'preserveAspectRatio="none"/>' % (x, y + 154, W)
    for r in range(2):
        for c in range(4):
            cx = x + 6 + c * 78
            cy = y + 78 + r * 82
            hue = (r * 4 + c) * 23 % 360
            o += ('<circle cx="%d" cy="%d" r="30" fill="hsl(%d,62%%,72%%)"/>'
                  % (cx + 36, cy + 34, hue))
            o += '<circle cx="%d" cy="%d" r="4" fill="#3a3a3a"/>' % (cx + 26, cy + 28)
            o += '<circle cx="%d" cy="%d" r="4" fill="#3a3a3a"/>' % (cx + 46, cy + 28)
            o += ('<path d="M%d,%d Q%d,%d %d,%d" stroke="#3a3a3a" stroke-width="2.5" fill="none"/>'
                  % (cx + 24, cy + 40, cx + 36, cy + 50, cx + 48, cy + 40))
    o += '<circle cx="%d" cy="%d" r="30" fill="none" stroke="#a8741d" stroke-width="2"/>' % (x + 42, y + 112)
    o += txt(x + 42, y + 150, 'held', 10, '#a8741d', 'bold', 'middle')
    o += note(x + 10, y + 250, W - 20,
              ['Every sticker is a still first frame.',
               'One animates at a time, and only while held:',
               'a single A5 core cannot decode sixteen Lottie',
               'timelines at once, and sixteen live ones would',
               'exhaust the 512MB budget on their own.'])
    return o


# ---------------------------------------------------------------- payments

def pay_modern(x, y):
    o = modern_chrome(x, y, 'Confirm')
    o += '<rect x="%d" y="%d" width="%d" height="%d" fill="#f2f2f7"/>' % (x, y + 65, W, H - 65)
    o += '<rect x="%d" y="%d" width="%d" height="72" fill="#fff"/>' % (x, y + 80, W)
    o += txt(x + 16, y + 108, 'Telegram Premium', 16, '#000', 'bold')
    o += txt(x + 16, y + 130, '3 months', 13, '#8e8e93')
    o += txt(x + W - 16, y + 118, '$12.99', 18, '#000', 'bold', 'end')
    o += '<rect x="%d" y="%d" width="%d" height="56" fill="#fff"/>' % (x, y + 168, W)
    o += '<rect x="%d" y="%d" width="34" height="22" fill="#1a1f71" rx="3"/>' % (x + 16, y + 185)
    o += txt(x + 33, y + 200, 'VISA', 9, '#fff', 'bold', 'middle')
    o += txt(x + 60, y + 202, '•••• 4242', 15, '#000')
    o += '<rect x="%d" y="%d" width="%d" height="50" fill="#000" rx="9"/>' % (x + 16, y + 250, W - 32)
    o += txt(x + W // 2, y + 275, ' Pay', 19, '#fff', 'bold', 'middle')
    o += txt(x + W // 2, y + 320, 'Double-click to confirm', 12, '#8e8e93', 'normal', 'middle')
    return o


def pay_ours(x, y):
    o = legacy_chrome(x, y, 'Telegram Premium')
    o += '<rect x="%d" y="%d" width="%d" height="%d" fill="#e5e8ec"/>' % (x, y + 64, W, H - 64)
    yy = y + 80
    o += txt(x + 14, yy + 14, 'STATUS', 12, '#5d708f', 'bold')
    o += row(x + 8, yy + 22, W - 16, 44)
    o += txt(x + 20, yy + 49, 'Premium', 15)
    o += txt(x + W - 20, yy + 49, 'not active', 15, '#8b97a5', 'normal', 'end')
    o += txt(x + 14, yy + 96, 'WHAT IT CHANGES', 12, '#5d708f', 'bold')
    for i, (k, a, b) in enumerate([('Pinned chats', '5', '10'),
                                   ('Folders', '10', '20'),
                                   ('Upload size', '2 GB', '4 GB')]):
        ry = yy + 104 + i * 44
        o += row(x + 8, ry, W - 16, 44)
        o += txt(x + 20, ry + 27, k, 15)
        o += txt(x + W - 62, ry + 27, a, 15, '#8b97a5', 'normal', 'end')
        o += txt(x + W - 50, ry + 27, '→', 13, '#b7bec7')
        o += txt(x + W - 20, ry + 27, b, 15, '#2f6ba8', 'bold', 'end')
    o += note(x + 8, yy + 250, W - 16,
              ['Informational only. There is no Buy button:',
               'in-app purchase needs a StoreKit stack and a',
               'developer account this build does not have,',
               'and card payment needs a modern web view.',
               'Subscribe elsewhere; the status shows here.'])
    return o


def main():
    os.makedirs(OUT, exist_ok=True)
    made = [
        build('limit-statistics.svg', stats_modern, stats_ours),
        build('limit-instantview.svg', iv_modern, iv_ours),
        build('limit-stories.svg', stories_modern, stories_ours),
        build('limit-stickers.svg', stick_modern, stick_ours),
        build('limit-payments.svg', pay_modern, pay_ours),
    ]
    print('wrote', len(made), 'comparisons')


if __name__ == '__main__':
    main()
