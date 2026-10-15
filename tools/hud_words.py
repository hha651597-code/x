#!/usr/bin/env python3
"""Bake the HUD's stand-in words (Blue Archive has no ROUND n, K.O., SUPER, EX READY, JUST GUARD or GUARD CRUSH lettering)
into assets/ba/hud/words/, 2x size, transparent. Chakra Petch Bold Italic (OFL, assets/fonts) with a vertical gradient,
a darker rim and a light top edge inside, a hard outline and a soft drop edge below, the way BA's own image fonts are built.
Run before tools/hud_assets.py build, which hashes the result.
usage: ~/Tools/venv-sprites/bin/python tools/hud_words.py [word ...]      (Pillow + numpy)"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/ba/hud/words"
FONT = ROOT / "assets/fonts/ChakraPetch-BoldItalic.ttf"
SCALE = 2
INK = "#39436F"

# text, cap height at 1x in px, gradient top, bottom, outline colour, outline width at 1x, extra thin outer ring colour or None
WORDS = {
    "round_1": ("ROUND 1", 40, "#FFFFFF", "#B7E1FF", INK, 3, None),
    "round_2": ("ROUND 2", 40, "#FFFFFF", "#B7E1FF", INK, 3, None),
    "round_3": ("ROUND 3", 40, "#FFFFFF", "#B7E1FF", INK, 3, None),
    "final": ("FINAL ROUND", 40, "#FFFFFF", "#B7E1FF", INK, 3, None),
    "super": ("SUPER", 26, "#FFFFFF", "#A9E3FF", INK, 3, None),
    "ex_ready": ("EX READY", 26, "#FFFFFF", "#FFF0A0", INK, 3, None),
    "ko": ("K.O.", 120, "#FFF25E", "#FF7A2B", "#C9560F", 4, "#4A2008"),
    "just_guard": ("JUST GUARD", 40, "#FFEC3D", "#FF9B14", "#C25200", 2, "#4A2000"),
    "guard_crush": ("GUARD CRUSH", 44, "#FFABA3", "#E64B5C", "#A32A40", 2, "#4A0F1C"),
    "training": ("TRAINING", 40, "#FFFFFF", "#B7E1FF", INK, 3, None),
    "draw": ("DRAW", 90, "#FFFFFF", "#B7E1FF", INK, 3, None),
    "time_up": ("TIME UP", 90, "#FFF25E", "#FF7A2B", "#C9560F", 4, "#4A2008"),
    **{"round_%d" % n: ("ROUND %d" % n, 40, "#FFFFFF", "#B7E1FF", INK, 3, None) for n in range(4, 10)},
}


def rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float32)


def cap_size(cap):
    """Font size whose capital H is `cap` px tall."""
    size = cap
    for _ in range(4):
        box = ImageFont.truetype(str(FONT), size).getbbox("H")
        size = max(1, round(size * cap / (box[3] - box[1])))
    return size


def mask(text, font, track, canvas, pad, stroke=0):
    """The text as an L image; stroke grows the glyphs round (Pillow's stroke_width)."""
    m = Image.new("L", canvas, 0)
    d = ImageDraw.Draw(m)
    x = pad
    for ch in text:
        d.text((x, pad), ch, font=font, fill=255, stroke_width=stroke, stroke_fill=255)
        x += font.getlength(ch) + track
    return m


def over(img, colour, a):
    """Composite a colour (or an RGB image) with coverage a over a non-premultiplied RGBA float image, in place."""
    out_a = a + img[..., 3:] * (1 - a)
    img[..., :3] = (colour * a + img[..., :3] * img[..., 3:] * (1 - a)) / np.maximum(out_a, 1e-6)
    img[..., 3:] = out_a


def shifted(a, dx, dy):
    out = np.zeros_like(a)
    h, w = a.shape
    ys, yd = (slice(0, h - dy), slice(dy, h)) if dy >= 0 else (slice(-dy, h), slice(0, h + dy))
    xs, xd = (slice(0, w - dx), slice(dx, w)) if dx >= 0 else (slice(-dx, w), slice(0, w + dx))
    out[yd, xd] = a[ys, xs]
    return out


def bake(text, cap, top, bottom, outline, ow, ring):
    cap *= SCALE
    ow *= SCALE
    font = ImageFont.truetype(str(FONT), cap_size(cap))
    track = cap * 0.03
    reach = ow + (SCALE if ring else 0)
    pad = reach + 8 * SCALE
    width = int(sum(font.getlength(c) + track for c in text)) + 2 * pad
    canvas = (width, int(cap * 1.7) + 2 * pad)
    fill = np.asarray(mask(text, font, track, canvas, pad), np.float32) / 255.0
    ys, xs = np.nonzero(fill > 0.5)
    y0, y1 = ys.min(), ys.max() + 1
    t = np.clip((np.arange(canvas[1])[:, None] - y0) / max(y1 - y0, 1), 0, 1) * np.ones((1, canvas[0]), np.float32)
    colour = rgb(top)[None, None] * (1 - t[..., None]) + rgb(bottom)[None, None] * t[..., None]
    k = 2 * SCALE + 1
    inner = np.asarray(Image.fromarray((fill * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(k)), np.float32) / 255.0
    rim = np.clip(fill - inner, 0, 1)[..., None]
    lit = np.clip(fill - shifted(fill, 0, 2 * SCALE), 0, 1)[..., None]
    shade = np.clip(fill - shifted(fill, 0, -2 * SCALE), 0, 1)[..., None]
    colour = colour * (1 - 0.35 * rim) + (colour * 0.72) * (0.35 * rim)
    colour = colour * (1 - 0.55 * lit) + 255.0 * (0.55 * lit)
    colour = colour * (1 - 0.18 * shade) + (colour * 0.7) * (0.18 * shade)
    out_mask = np.asarray(mask(text, font, track, canvas, pad, ow), np.float32) / 255.0
    layers = []
    if ring:
        ring_mask = np.asarray(mask(text, font, track, canvas, pad, ow + SCALE), np.float32) / 255.0
        layers.append((ring_mask, rgb(ring)))
    layers.append((out_mask, rgb(outline)))
    drop = Image.fromarray((layers[0][0] * 255).astype(np.uint8))
    drop = np.asarray(drop.filter(ImageFilter.GaussianBlur(2 * SCALE)), np.float32) / 255.0
    drop = shifted(drop, 0, 3 * SCALE) * 0.32
    img = np.zeros((canvas[1], canvas[0], 4), np.float32)
    img[..., :3] = rgb("#1D2A55")
    img[..., 3] = drop
    for m, c in layers:
        over(img, c, m[..., None])
    over(img, colour, fill[..., None])
    img[..., 3] *= 255.0
    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
    return im.crop(im.getbbox())


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name in sys.argv[1:] or WORDS:
        im = bake(*WORDS[name])
        im.save(OUT / (name + ".png"), optimize=True)
        print(name, im.size)


if __name__ == "__main__":
    main()
