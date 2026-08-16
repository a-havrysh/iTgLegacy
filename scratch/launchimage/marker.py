import sys, os, re, glob
from PIL import Image
out = sys.argv[1]
walls = {}
for line in open(out + '.frames'):
    m = re.match(r'frame (\d+) at \+(\d+) ms wall (\d+):(\d+):(\d+)\.(\d+)', line)
    if m:
        walls[int(m.group(1))] = int(m.group(3))*3600+int(m.group(4))*60+int(m.group(5))+int(m.group(6))/1000.0
marks = []
for line in open(out + '.perf', errors='ignore'):
    m = re.search(r'(\d+):(\d+):(\d+)\.(\d+) iTgLegacy.*PERF launch (?:\+\d+ ms )?\(tap \+(\d+) ms\): (.+?)(?: rss|$)', line)
    if m:
        t = int(m.group(1))*3600+int(m.group(2))*60+int(m.group(3))+int(m.group(4))/1000.0
        marks.append((t, int(m.group(5)), m.group(6).strip()))
marks.sort()
tap = marks[0][0] - marks[0][1]/1000.0
def magenta(im):
    px = im.convert('RGB').getdata()
    return sum(1 for r,g,b in px if r > 200 and b > 200 and g < 90)
rows = []
for f in sorted(glob.glob(os.path.join(out, '*.png'))):
    i = int(re.search(r'(\d+)\.png$', f).group(1))
    if i not in walls: continue
    im = Image.open(f)
    rows.append(((walls[i]-tap)*1000, os.path.basename(f), magenta(im)))
events = [('%+7.0f' % t, n, 'launch image (%d marker px)' % m if m > 200 else 'no marker') for t, n, m in rows]
for e in events: print('%s ms  %s  %s' % e)
print()
for t, tapms, what in marks: print('%+7d ms  APP: %s' % (tapms, what))
