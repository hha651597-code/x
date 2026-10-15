#!/usr/bin/env python3
"""Register each fighter's Spine render on today's art and write tools/hud_expressions_fit.json (committed).

For the HUD card (assets/ba/hud/portraits/Student_Portrait_<Name>.png) and the result portrait (assets/ba/portrait/<id>.webp):
SIFT matches between a render and the image give a similarity transform; the image rectangle in skeleton units is the
crop the build renders with. Also stored: the face animation today's art shows (smallest difference) and the fit error.
Needs cv2, Pillow and numpy (venv-sprites). Run `hud_expressions.py extract` first.

  ~/Tools/venv-sprites/bin/python tools/hud_expressions_fit.py --work W [--only toki,hina]"""
import argparse
import json
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hud_expressions as he  # noqa: E402
import spine_render as sr  # noqa: E402


def gray(im):
    bg = Image.new("RGBA", im.size, (128, 128, 128, 255))
    bg.alpha_composite(im.convert("RGBA"))
    return cv2.cvtColor(np.asarray(bg.convert("RGB")), cv2.COLOR_RGB2GRAY)


def sift_fit(rig, img, anim, region, s0, up):
    """Image rectangle (0,0,w,h) in skeleton units, from SIFT matches between the render of `region` and img (scaled by `up`)."""
    skel, regs, tex = rig
    r = sr.render(skel, regs, tex, anim, s0, region)
    g_img = cv2.resize(gray(img), None, fx=up, fy=up, interpolation=cv2.INTER_CUBIC)
    sift = cv2.SIFT_create(4000)
    k1, d1 = sift.detectAndCompute(g_img, None)
    k2, d2 = sift.detectAndCompute(gray(r), None)
    m = [p for p in cv2.BFMatcher(cv2.NORM_L2).knnMatch(d1, d2, k=2) if len(p) == 2]
    good = [a for a, b in m if a.distance < 0.75 * b.distance]
    p_img = np.float32([k1[a.queryIdx].pt for a in good])
    p_ren = np.float32([k2[a.trainIdx].pt for a in good])
    M, inl = cv2.estimateAffinePartial2D(p_img, p_ren, ransacReprojThreshold=2.0)    # image(up) px -> render px
    if M is None or inl.sum() < 12:
        raise RuntimeError("only %d inliers" % (0 if inl is None else inl.sum()))
    rot = float(np.degrees(np.arctan2(M[1, 0], M[0, 0])))
    w, h = img.size
    corners = np.float32([[0, 0], [w * up, h * up]])
    cr = corners @ M[:, :2].T + M[:, 2]                  # corners in render px
    x0 = region[0] + cr[0, 0] / s0
    x1 = region[0] + cr[1, 0] / s0
    ytop = region[3] - cr[0, 1] / s0
    ybot = region[3] - cr[1, 1] / s0
    return [x0, ybot, x1, ytop], int(inl.sum()), len(good), rot


def region_for(skel, slot, mult):
    lo, hi = he.face_box(skel, slot)
    c = (lo + hi) / 2
    half = (hi[0] - lo[0]) * mult
    return (c[0] - half, c[1] - half * 0.8, c[0] + half, c[1] + half * 0.8)


def pair_pixels(a, b, erode=4):
    """Pixels opaque in both (and away from the silhouette), as float arrays (n,3)."""
    A = np.asarray(a.convert("RGBA")).astype(float)
    B = np.asarray(b.convert("RGBA")).astype(float)
    m = ((A[..., 3] > 250) & (B[..., 3] > 250)).astype(np.uint8)
    m = cv2.erode(m, np.ones((2 * erode + 1, 2 * erode + 1), np.uint8)).astype(bool)
    return A[..., :3][m], B[..., :3][m], m


def mad(existing, rendered):
    ex, rd, m = pair_pixels(existing, rendered, 2)
    return float(np.abs(ex - rd).mean()) if len(ex) else 99.0


def fit_one(work, key, f, anims=None):
    rig = he.load_rig(work, f["spr"])
    skel = rig[0]
    slot = he.face_slot(skel)
    cand = anims or [a for a in he.face_anims(skel) if he.WORD.fullmatch(a) and not a.startswith("S2_")][:10]
    out = {}
    jobs = {
        "card": (Image.open(he.PORTRAITS / (f["tex"] + ".png")).convert("RGBA"), region_for(skel, slot, 4.2), 1.0, 2),
        "result": (Image.open(he.RESULTS / ("%d.webp" % f["id"])).convert("RGBA"), None, 0.5, 1),
    }
    for kind, (img, region, s0, up) in jobs.items():
        if region is None:
            sk = skel["skeleton"]
            region = (sk["x"], sk["y"], sk["x"] + sk["width"], sk["y"] + sk["height"])
        crop, inl, n, rot = sift_fit(rig, img, cand[0], region, s0, up)
        best = None
        for a in cand:
            r = he.render_view(rig, a, crop, img.size, 1 if img.width > 400 else he.SS)
            e = mad(img, r)
            if best is None or e < best[0]:
                best = (e, a, r)
        e, a, r = best
        out[kind] = {"crop": [round(v, 3) for v in crop], "anim": a, "inliers": inl, "matches": n, "rot": round(rot, 2),
                     "diff": round(e, 1)}
        print("%-8s %-6s anim %-6s inliers %3d/%3d rot %5.2f diff %5.1f" % (key, kind, a, inl, n, rot, e), flush=True)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--work", required=True)
    ap.add_argument("--only")
    a = ap.parse_args()
    fit = json.loads(he.FIT.read_text()) if he.FIT.exists() else {}
    for key, f in he.fighters().items():
        if a.only and key not in a.only.split(","):
            continue
        try:
            fit[key] = fit_one(a.work, key, f)
        except Exception as e:
            print(key, "FAIL", repr(e), flush=True)
    he.FIT.write_text(json.dumps(fit, indent=1) + "\n")


if __name__ == "__main__":
    main()
