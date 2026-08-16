import sys, os, re, glob
from PIL import Image, ImageChops

out = sys.argv[1]
frames = sorted(glob.glob(os.path.join(out, '*.png')))

# wall clock per frame
walls = {}
for line in open(out + '.frames'):
    m = re.match(r'frame (\d+) at \+(\d+) ms wall (\d+):(\d+):(\d+)\.(\d+)', line)
    if m:
        i = int(m.group(1))
        walls[i] = int(m.group(3))*3600 + int(m.group(4))*60 + int(m.group(5)) + int(m.group(6))/1000.0

# app milestones
marks = []
for line in open(out + '.perf', errors='ignore'):
    m = re.search(r'(\d+):(\d+):(\d+)\.(\d+) iTgLegacy.*PERF launch (?:\+\d+ ms )?\(tap \+(\d+) ms\): (.+?) rss', line)
    if m:
        t = int(m.group(1))*3600 + int(m.group(2))*60 + int(m.group(3)) + int(m.group(4))/1000.0
        marks.append((t, int(m.group(5)), m.group(6)))
    m2 = re.search(r'(\d+):(\d+):(\d+)\.(\d+) iTgLegacy.*PERF launch \(tap \+(\d+) ms\): image ready', line)
    if m2:
        t = int(m2.group(1))*3600 + int(m2.group(2))*60 + int(m2.group(3)) + int(m2.group(4))/1000.0
        marks.append((t, int(m2.group(5)), 'image ready (dyld done)'))
marks.sort()
if not marks:
    print('no marks'); sys.exit(1)
tap = marks[0][0] - marks[0][1]/1000.0     # wall clock of the tap

ref = None
snap = sys.argv[2] if len(sys.argv) > 2 else None
if snap: ref = Image.open(snap).convert('RGB')

prev = None
rows = []
for f in frames:
    i = int(re.search(r'(\d+)\.png$', f).group(1))
    if i not in walls: continue
    im = Image.open(f).convert('RGB')
    w, h = im.size
    body = im.crop((0, 40, w, h))
    d = ''
    if prev is not None:
        bb = ImageChops.difference(body, prev).getbbox()
        d = 'unchanged' if bb is None else 'changed'
    prev = body
    m = ''
    if ref is not None:
        bb = ImageChops.difference(im.crop((0,40,w,h)), ref.crop((0,40,w,h))).getbbox()
        if bb is None: m = 'IDENTICAL to snapshot'
        else:
            diff = ImageChops.difference(im.crop((0,40,w,h)), ref.crop((0,40,w,h)))
            px = sum(1 for p in diff.getdata() if sum(p) > 24)
            m = 'differs from snapshot in %d px, box y=%d..%d' % (px, bb[1]+40, bb[3]+40)
    rows.append((walls[i]-tap, os.path.basename(f), d, m))

print('tap at 0 ms (derived from the app clock)')
for t, name, d, m in rows:
    print('%+7.0f ms  %s  %-9s %s' % (t*1000, name, d, m))
print()
for t, tapms, what in marks:
    print('%+7d ms  APP: %s' % (tapms, what))
