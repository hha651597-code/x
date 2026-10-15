#!/usr/bin/env python3
"""Bake a stand-in for a Student_Portrait the install does not have: the repo's bust card (assets/ba/collection/<id>.webp)
cropped to 252x204 and cut into BA's 10 degree rounded parallelogram. Writes Student_Portrait_<Name>_fallback.png next to
the real ones; then run tools/hud_assets.py build, which lists the id in portraits/MISSING.txt.
Nothing needs it today: all 30 fighters and 81 specials have a real portrait.
usage: ~/Tools/venv-sprites/bin/python tools/hud_fallback.py <roster id> [<roster id> ...] [--out DIR]   (Pillow)"""
import argparse
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
W, H = 252, 204
TAN = math.tan(math.radians(10.0))
SS = 4        # supersampling for the rounded corners


def bake(art_path):
    shift = round(H * TAN)
    inner = (W - shift, H)
    art = Image.open(art_path).convert("RGBA")
    k = max(inner[0] / art.width, inner[1] / art.height)
    art = art.resize((round(art.width * k), round(art.height * k)), Image.LANCZOS)
    left, top = (art.width - inner[0]) // 2, 0
    art = art.crop((left, top, left + inner[0], top + inner[1]))
    mask = Image.new("L", (inner[0] * SS, inner[1] * SS), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, inner[0] * SS - 1, inner[1] * SS - 1), radius=18 * SS, fill=255)
    mask = mask.resize(inner, Image.LANCZOS)
    art.putalpha(mask)
    # x' = x + (H - y) * tan: the top edge leans right
    return art.transform((W, H), Image.AFFINE, (1, TAN, -shift, 0, 1, 0), resample=Image.BICUBIC)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("ids", nargs="+", type=int)
    ap.add_argument("--out", default=str(ROOT / "assets/ba/hud/portraits"))
    args = ap.parse_args()
    roster = json.loads((ROOT / "assets/ba/roster.json").read_text())
    people = {p["id"]: p for p in roster["fighters"] + roster["specials"]}
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    for i in args.ids:
        p = people[i]
        dst = out / ("Student_Portrait_%s_fallback.png" % p["name"])
        bake(ROOT / "assets/ba" / p["collection"]).save(dst, optimize=True)
        print(dst)


if __name__ == "__main__":
    main()
