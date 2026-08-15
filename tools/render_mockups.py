#!/usr/bin/env python3
"""Render design-proposal SVGs to retina PNGs.

Agents write plain SVG at 320x480 points and refer to the real 2013 artwork by
name, as xlink:href="ASSET:HeaderButton". This substitutes each of those for a
base64 data URI of the matching @2x PNG before handing the file to rsvg-convert,
so a proposal can sit on top of genuine Telegram chrome without an agent ever
having to deal with binary data.
"""
import base64
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMAGES = os.path.join(REPO, 'images')
SRC = os.path.join(REPO, 'docs', 'design-proposals', 'svg')
OUT = os.path.join(REPO, 'docs', 'design-proposals', 'png')

_cache = {}

# An empty xlink:href points an <image> at the document itself, which sends
# librsvg into unbounded recursion, so a name that resolves to nothing has to
# become a real, tiny image rather than an empty string.
BLANK = ('data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
         'AAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==')

ALIASES = {
    'wallpaper': 'builtin-wallpaper-0.jpg',
    'Wallpaper': 'builtin-wallpaper-0.jpg',
}


def data_uri(name):
    if name in _cache:
        return _cache[name]
    candidates = [name + '@2x.png', name + '.png', name + '.jpg', name]
    if name in ALIASES:
        candidates.insert(0, ALIASES[name])
    for candidate in candidates:
        path = os.path.join(IMAGES, candidate)
        if not os.path.exists(path):
            continue
        mime = 'image/jpeg' if candidate.lower().endswith(('.jpg', '.jpeg')) else 'image/png'
        with open(path, 'rb') as handle:
            uri = 'data:%s;base64,%s' % (mime, base64.b64encode(handle.read()).decode())
        _cache[name] = uri
        return uri
    _cache[name] = None
    return None


def render(svg_path, png_path):
    with open(svg_path, 'r', encoding='utf-8') as handle:
        svg = handle.read()

    missing = []

    def replace(match):
        name = match.group(1)
        uri = data_uri(name)
        if uri is None:
            missing.append(name)
            return BLANK
        return uri

    svg = re.sub(r'ASSET:([A-Za-z0-9_@.\-]+)', replace, svg)

    tmp = svg_path + '.resolved.svg'
    with open(tmp, 'w', encoding='utf-8') as handle:
        handle.write(svg)
    try:
        subprocess.run(['rsvg-convert', '-w', '640', tmp, '-o', png_path], check=True)
    finally:
        os.unlink(tmp)
    return missing


def main():
    os.makedirs(OUT, exist_ok=True)
    if not os.path.isdir(SRC):
        print('no svg directory at', SRC)
        return 1

    ok = 0
    failed = []
    all_missing = set()
    for name in sorted(os.listdir(SRC)):
        if not name.endswith('.svg'):
            continue
        svg_path = os.path.join(SRC, name)
        png_path = os.path.join(OUT, name[:-4] + '.png')
        try:
            all_missing.update(render(svg_path, png_path))
            ok += 1
        except subprocess.CalledProcessError:
            failed.append(name)

    print('rendered %d, failed %d' % (ok, len(failed)))
    for name in failed:
        print('  FAILED', name)
    if all_missing:
        print('missing assets:', ', '.join(sorted(all_missing)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
