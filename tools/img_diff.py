#!/usr/bin/env python3
"""Mean absolute per-channel difference (0..255) of two same-size PNGs, optionally over a box.
usage: ~/Tools/venv-sprites/bin/python tools/img_diff.py a.png b.png [x0 y0 x1 y1]"""
import sys
from PIL import Image, ImageChops

a = Image.open(sys.argv[1]).convert("RGB")
b = Image.open(sys.argv[2]).convert("RGB")
if a.size != b.size:
    sys.exit("size mismatch %s vs %s" % (a.size, b.size))
if len(sys.argv) >= 7:
    box = tuple(int(v) for v in sys.argv[3:7])
    a, b = a.crop(box), b.crop(box)
d = ImageChops.difference(a, b)
n = a.size[0] * a.size[1]
sums = [sum(ch.getdata()) for ch in d.split()]
print("mean abs diff R,G,B = %.2f %.2f %.2f" % tuple(s / n for s in sums))
