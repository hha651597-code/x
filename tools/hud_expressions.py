#!/usr/bin/env python3
"""Expression portraits for the 30 fighters: HUD state tiles and the result-screen win and lose images.

Every fighter has a story-standing Spine rig (<name>_spr) whose face is one slot; the animations 00..NN swap that
slot's mesh. Today's Student_Portrait and portrait/<id>.webp are crops of the same rig, so a new face keeps the drawing.
`extract` needs UnityPy (venv-stages); `build`, `states` and the fit (tools/hud_expressions_fit.py) need Pillow, numpy and cv2 (venv-sprites).

  extract   copy the _spr bundles out of the install, read skel/atlas/png, convert the skeleton with SkelToJson
  sheets    one contact sheet per fighter with every face labelled (what the picks are chosen from)
  build     render the picks from tools/hud_expressions_picks.json with the crops in tools/hud_expressions_fit.json,
            write the tiles, the result images, assets/ba/hud/portraits/expressions.json and the PROVENANCE entries,
            and flag every state that does not differ from calm at HUD size

  python tools/hud_expressions.py extract --install /path/to/BlueArchive --work W
  python tools/hud_expressions.py sheets  --work W --out S
  python tools/hud_expressions.py build   --work W [--only toki,hina]

Rebuild: `extract`, then `build`. The crops and colour fits come from `fit` (once per art change) and are committed.
Bundles for 27 fighters are in GameData; Hasumi, Wakamo and Yuuka are only in Preload (prologdepengroup-*)."""
import argparse
import hashlib
import json
import re
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools/third_party"))
import spine_render as sr  # noqa: E402

HUD = ROOT / "assets/ba/hud"
PORTRAITS = HUD / "portraits"
RESULTS = ROOT / "assets/ba/portrait"
PICKS = ROOT / "tools/hud_expressions_picks.json"
FIT = ROOT / "tools/hud_expressions_fit.json"
STATES = ["scratched", "hurt", "critical", "flinch", "win", "lose", "ko"]
CARD = (252, 204)
SS = 2                       # supersampling for the tiles
QUALITY = 90
DIFF_MIN = 3.0               # a state under this mean RGB difference from calm over the face box at 150x121 needs an overlay
SKEL_COMMIT = "c2c7cae90b0deb063ef23fbd808430cd1a462356"
WORD = re.compile(r"(S\d_)?\d+")


def fighters():
    """roster key -> dict(id, name, tex (Student_Portrait stem), spr (rig name))."""
    roster = json.loads((ROOT / "assets/ba/roster.json").read_text())["fighters"]
    idx = json.loads((HUD / "index.json").read_text())["portraits"]
    out = {}
    for f in roster:
        e = idx[str(f["id"])]
        out[f["key"]] = {"id": f["id"], "name": f["name"], "tex": e["texture"],
                         "spr": re.sub(r"_default$", "", e["dev_name"], flags=re.I).lower() + "_spr"}
    return out


def rig_dir(work, spr):
    return Path(work) / "rigs" / spr


def load_rig(work, spr):
    return sr.load(rig_dir(work, spr), spr)


def face_slot(skel):
    """The slot whose attachment the numbered animations swap (most distinct attachments)."""
    seen = {}
    for an, a in skel["animations"].items():
        if WORD.fullmatch(an):
            for sl, tl in a.get("slots", {}).items():
                for k in tl.get("attachment", []):
                    if k.get("name"):
                        seen.setdefault(sl, set()).add(k["name"])
    return max(seen.items(), key=lambda kv: len(kv[1]))[0]


def face_anims(skel):
    """Every animation that changes the face slot, numbered ones first (plus the eye-closing ones)."""
    fs = face_slot(skel)
    keep = [a for a, d in skel["animations"].items() if "attachment" in d.get("slots", {}).get(fs, {})]
    return sorted(keep, key=lambda a: (not WORD.fullmatch(a), a))


def face_label(skel, anim, slot):
    ks = skel["animations"][anim].get("slots", {}).get(slot, {}).get("attachment", [])
    return (ks[0].get("name") if ks else None) or "eyes shut"


def render_view(rig, anim, crop, size, ss=SS):
    """The crop (skeleton units) of the rig in `anim`, as an RGBA image of exactly `size`, rendered ss times larger."""
    skel, regs, tex = rig
    im = sr.render(skel, regs, tex, anim, size[0] * ss / (crop[2] - crop[0]), crop)
    return im if im.size == tuple(size) else im.resize(tuple(size), Image.LANCZOS)


def extract(a):
    import UnityPy
    from SkelToJson import convert_skel_to_json
    work = Path(a.work)
    install = Path(a.install) / "BlueArchive_Data/StreamingAssets/PUB/Resource"
    for key, f in fighters().items():
        spr, out = f["spr"], rig_dir(work, f["spr"])
        if (out / (spr + ".json")).exists():
            continue
        bundles = sorted(p for d in ("GameData", "Preload") for p in (install / d / "Windows").glob("*spinecharacters-%s-*.bundle" % spr))
        if not bundles:
            sys.exit("no bundle for " + spr)
        src = work / "bundles" / spr
        src.mkdir(parents=True, exist_ok=True)
        out.mkdir(parents=True, exist_ok=True)
        got = {}
        for b in bundles:
            shutil.copyfile(b, src / b.name)
            for k, o in UnityPy.load(str(src / b.name)).container.items():
                base = Path(k).name.lower()
                if not base.startswith(spr + "."):
                    continue
                d = o.read()
                if o.type.name == "TextAsset":
                    s = d.m_Script
                    (out / base).write_bytes(s.encode("utf-8", "surrogateescape") if isinstance(s, str) else bytes(s))
                elif o.type.name == "Texture2D":
                    d.image.save(out / (base if base.endswith(".png") else base + ".png"))
                else:
                    continue
                got[base] = {"bundle": b.name, "container": k, "path_id": o.path_id}
        for need in (".skel.bytes", ".atlas.txt", ".png"):
            if spr + need not in got:
                sys.exit("%s: %s missing from %s" % (key, need, [b.name for b in bundles]))
        convert_skel_to_json(str(out / (spr + ".skel.bytes")), str(out / (spr + ".json")))
        (out / "sources.json").write_text(json.dumps(got, indent=1))
        print(key, spr, len(bundles), "bundles", flush=True)


def sheets(a):
    fit = json.loads(FIT.read_text())
    outd = Path(a.out)
    outd.mkdir(parents=True, exist_ok=True)
    for key, f in fighters().items():
        if a.only and key not in a.only.split(","):
            continue
        rig = load_rig(a.work, f["spr"])
        skel = rig[0]
        slot = face_slot(skel)
        tiles = []
        for an in face_anims(skel):
            im = render_view(rig, an, fit[key]["card"]["crop"], CARD, 1)
            bg = Image.new("RGBA", im.size, (70, 76, 90, 255))
            bg.alpha_composite(im)
            ImageDraw.Draw(bg).text((4, 4), "%s %s" % (an, face_label(skel, an, slot)), fill=(255, 255, 0, 255))
            tiles.append(bg.convert("RGB"))
        cols = min(6, len(tiles))
        rows = (len(tiles) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * CARD[0], rows * CARD[1]))
        for i, t in enumerate(tiles):
            sheet.paste(t, ((i % cols) * CARD[0], (i // cols) * CARD[1]))
        sheet.save(outd / (key + ".png"))
        print(key, len(tiles), flush=True)


def face_box(skel, slot):
    """Union of the face slot's meshes in skeleton units: (min xy, max xy)."""
    W = sr.bone_world(skel["bones"])
    bone = next(s["bone"] for s in skel["slots"] if s["name"] == slot)
    pts = []
    for sk in skel["skins"]:
        for att in sk["attachments"].get(slot, {}).values():
            if att.get("type") == "mesh":
                pts.append(sr.mesh_world(att, bone, skel["bones"], W)[0])
            elif att.get("type") in (None, "region"):
                pts.append(sr.region_world(att, bone, W)[0])
    pts = np.concatenate(pts)
    return pts.min(0), pts.max(0)


def box_px(skel, crop, size):
    """The face slot's box in canvas pixels, clipped to the canvas."""
    lo, hi = face_box(skel, face_slot(skel))
    sx, sy = size[0] / (crop[2] - crop[0]), size[1] / (crop[3] - crop[1])
    x0, x1 = (lo[0] - crop[0]) * sx, (hi[0] - crop[0]) * sx
    y0, y1 = (crop[3] - hi[1]) * sy, (crop[3] - lo[1]) * sy
    return max(0, x0), max(0, y0), min(size[0], x1), min(size[1], y1)


def over_gray(im):
    bg = Image.new("RGBA", im.size, (128, 128, 128, 255))
    bg.alpha_composite(im.convert("RGBA"))
    return np.asarray(bg.convert("RGB")).astype(float)


def patch(existing, base, face):
    """Today's art with the face swapped. Inside the changed region the new render takes today's colours (the
    low-frequency part of existing - base carries the engine's grading), so nothing outside the face moves."""
    import cv2
    d = over_gray(face) - over_gray(base)
    m = Image.fromarray(((np.abs(d).max(2) > 6) * 255).astype(np.uint8))
    w = np.asarray(m.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(1.5))).astype(float) / 255
    e = np.asarray(existing.convert("RGBA")).astype(float)
    b = np.asarray(base.convert("RGBA")).astype(float)
    f = np.asarray(face.convert("RGBA")).astype(float)
    both = ((e[..., 3] > 250) & (b[..., 3] > 250) & (np.abs(e[..., :3] - b[..., :3]).max(2) < 30)).astype(float)   # not on misregistered edges
    k = max(3, int(existing.width / 8) | 1)
    num = cv2.GaussianBlur((e[..., :3] - b[..., :3]) * both[..., None], (k, k), 0)
    den = cv2.GaussianBlur(both, (k, k), 0)[..., None]
    lf = np.where(den > 0.05, num / np.maximum(den, 0.05), 0)
    a1 = (f[..., 3] / 255)[..., None]
    new = a1 * (f[..., :3] + lf) + (1 - a1) * (e[..., :3] + d)
    rgb = np.clip(e[..., :3] * (1 - w[..., None]) + new * w[..., None], 0, 255)
    return Image.fromarray(np.dstack([rgb, e[..., 3]]).astype(np.uint8))


# overlay presets: sprite (assets/ba/hud/sprites stem), width as a fraction of the face box, anchor as fractions of the box
EMOTE = {
    "sweat": ("Emoji__Emoji_Sweat_1", 0.17, 0.86, 0.12),
    "sweat2": ("Emoji__Emoji_Sweat_2", 0.12, 0.10, 0.18),
    "tears": ("Emoji__Emoji_Tear_1", 0.10, [0.28, 0.72], 0.66),
    "twinkle": ("Emoji__Emoji_Twinkle", 0.22, [0.85, 0.14], [0.14, 0.32]),
    "shock": ("Emoji__Emoji_Exclamation", 0.10, 0.90, 0.17),
}
# whole-tile grades: saturation kept, red vignette, dark vignette
GRADE = {"vig1": (1.0, 0.45, 0.0), "vig2": (0.8, 0.8, 0.25), "desat": (0.45, 0.0, 0.1)}


def grade(im, sat, red, dark):
    a = im.convert("RGBA")
    rgb = ImageEnhance.Color(a.convert("RGB")).enhance(sat)
    arr = np.asarray(rgb).astype(float)
    h, w = arr.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    v = np.clip((np.sqrt(((xx - w / 2) / (w / 2)) ** 2 + ((yy - h / 2) / (h / 2)) ** 2) - 0.45) / 0.9, 0, 1)[..., None]
    arr = arr * (1 - dark * v) * (np.array([1.0, 1.0, 1.0]) - np.array([0.0, 0.85, 0.85]) * red * v)
    out = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).convert("RGBA")
    out.putalpha(a.getchannel("A"))
    return out


def overlay(im, fx, box, tiles=True):
    """Bake the named overlays into im. Emotes are placed by the face box; grades (tiles only) go last."""
    im = im.convert("RGBA")
    fw, fh = box[2] - box[0], box[3] - box[1]
    for name in fx:
        if name in GRADE:
            if tiles:
                im = grade(im, *GRADE[name])
            continue
        stem, wf, xs, ys = EMOTE[name]
        xs, ys = xs if isinstance(xs, list) else [xs], ys if isinstance(ys, list) else [ys]
        spr = Image.open(HUD / "sprites" / (stem + ".png")).convert("RGBA")
        w = max(4, int(fw * wf))
        spr = spr.resize((w, max(4, int(spr.height * w / spr.width))), Image.LANCZOS)
        for xf, yf in zip(xs, ys * len(xs) if len(ys) == 1 else ys):
            x = int(box[0] + fw * xf - spr.width / 2)
            y = int(box[1] + fh * yf - spr.height / 2)
            x, y = min(max(0, x), im.width - spr.width), min(max(0, y), im.height - spr.height)
            layer = Image.new("RGBA", im.size, (0, 0, 0, 0))
            layer.alpha_composite(spr, (x, y))
            im = Image.alpha_composite(im, layer)
    return im


def parse_pick(v):
    """"04" or {"face": "04", "fx": ["sweat", "vig1"]} -> (face, fx)."""
    return (v, []) if isinstance(v, str) else (v["face"], v.get("fx", []))


def sprite_names(fx):
    return [EMOTE[n][0] for n in fx if n in EMOTE]


def face_diff(a, b, box):
    """Mean RGB difference over the face box at HUD size (150x121), over pixels opaque in b."""
    sx = 150 / a.width
    ra = np.asarray(a.convert("RGBA").resize((150, 121), Image.LANCZOS)).astype(float)
    rb = np.asarray(b.convert("RGBA").resize((150, 121), Image.LANCZOS)).astype(float)
    x0, y0, x1, y1 = [int(round(v * sx)) for v in box]
    ra, rb = ra[y0:y1, x0:x1], rb[y0:y1, x0:x1]
    m = rb[..., 3] > 200
    return float(np.abs(ra[..., :3] - rb[..., :3])[m].mean()) if m.any() else 0.0


def save_webp(im, path):
    im.save(path, "WEBP", quality=QUALITY, method=6)
    return path.stat().st_size


def tile_stem(f):
    return f["tex"]


def build(a):
    picks = json.loads(Path(a.picks).read_text())
    fit = json.loads(FIT.read_text())
    only = a.only.split(",") if a.only else None
    flagged, carried, table, sizes = [], [], {}, {"hud": 0, "result": 0}
    files = {"hud": [], "result": []}
    expr, overlays = {}, {}
    for key, f in fighters().items():
        if only and key not in only:
            continue
        pk = picks[key]
        rig = load_rig(a.work, f["spr"])
        skel = rig[0]
        src = json.loads((rig_dir(a.work, f["spr"]) / "sources.json").read_text())
        bundles = sorted({v["bundle"] for v in src.values()})
        ex = Image.open(PORTRAITS / (f["tex"] + ".png")).convert("RGBA")
        c = fit[key]["card"]
        r0 = render_view(rig, c["anim"], c["crop"], CARD)
        box = box_px(skel, c["crop"], CARD)
        stem = tile_stem(f)
        entry = {"calm": stem + ".png"}
        calm_img = ex
        face0, fx0 = parse_pick(pk["calm"])
        if face0 != c["anim"]:
            img = patch(ex, r0, render_view(rig, face0, c["crop"], CARD))
            if face_diff(img, ex, box) > 2.0:
                calm_img = img
                entry["calm"] = stem + "_calm.webp"
                if a.write:
                    sizes["hud"] += save_webp(img, PORTRAITS / entry["calm"])
                files["hud"].append((entry["calm"], img, f, face0, []))
        rows = {}
        for st in STATES:
            face, fx = parse_pick(pk[st])
            img = patch(ex, r0, render_view(rig, face, c["crop"], CARD))
            d = face_diff(img, calm_img, box)
            if fx:
                img = overlay(img, fx, box)
                img.putalpha(ex.getchannel("A"))       # emotes stay inside the card's parallelogram
            rows[st] = (face, fx, round(d, 1))
            if d < DIFF_MIN and fx:
                carried.append("%s %s" % (key, st))
            if d < DIFF_MIN and not fx:
                flagged.append("%s %s face %s differs from calm by %.1f at 150x121 and has no overlay" % (key, st, face, d))
            fn = "%s_%s.webp" % (stem, st)
            entry[st] = fn
            if fx:
                overlays.setdefault(str(f["id"]), {})[st] = fx
            files["hud"].append((fn, img, f, face, fx))
            if a.write:
                sizes["hud"] += save_webp(img, PORTRAITS / fn)
        expr[str(f["id"])] = entry
        table[key] = rows
        if a.write and not a.tiles_only:
            rc = fit[key]["result"]
            res = Image.open(RESULTS / ("%d.webp" % f["id"])).convert("RGBA")
            rr0 = render_view(rig, rc["anim"], rc["crop"], res.size, 1)
            rbox = box_px(skel, rc["crop"], res.size)
            for st in ("win", "lose"):
                face, fx = parse_pick(pk[st])
                fx = [n for n in fx if n in EMOTE]
                if face == rc["anim"] and not fx:
                    flagged.append("%s %s: face %s is the one the portrait already shows" % (key, st, face))
                img = patch(res, rr0, render_view(rig, face, rc["crop"], res.size, 1))
                if fx:
                    img = overlay(img, fx, rbox, tiles=False)
                fn = "%d_%s.webp" % (f["id"], st)
                files["result"].append((fn, img, f, face, fx))
                sizes["result"] += save_webp(img, RESULTS / fn)
        print("%-8s %s" % (key, "  ".join("%s %s/%.1f%s" % (s, r[0], r[2], "+" + ",".join(r[1]) if r[1] else "") for s, r in rows.items())), flush=True)
    print("face differs by less than %.1f and an overlay carries the state: %s" % (DIFF_MIN, ", ".join(carried) or "none"))
    for line in flagged:
        print("FLAG", line)
    if a.write and not only:
        (PORTRAITS / "expressions.json").write_text(json.dumps({**expr, "_overlays": overlays}, indent=1) + "\n")
        if not a.tiles_only:
            write_provenance(a, files, picks)
    print("bytes written: hud %d, result %d" % (sizes["hud"], sizes["result"]))
    if flagged:
        sys.exit("%d flagged states" % len(flagged))


def write_provenance(a, files, picks):
    def entry(kind, fn, im, f, face, fx, path):
        rig = rig_dir(a.work, f["spr"])
        src = json.loads((rig / "sources.json").read_text())
        bundles = sorted({v["bundle"] for v in src.values()})
        data = path.read_bytes()
        d = ("tools/hud_expressions.py: %s rig %s (%s), face animation %s, patched onto %s, SkelToJson %s" %
             (f["spr"], "bundles " + ", ".join(bundles), "Preload" if bundles[0].startswith("prolog") else "GameData", face,
              (f["tex"] + ".png") if kind == "hud" else ("portrait/%d.webp" % f["id"]), SKEL_COMMIT[:8]))
        if fx:
            d += "; overlays " + ", ".join(fx) + (" from " + ", ".join(sprite_names(fx)) if sprite_names(fx) else "")
        return {"kind": "baked", "source_name": fn[:-5], "derived_from": d, "entries": "expressions",
                "runtime_path": str(path.relative_to(ROOT)), "width": im.width, "height": im.height,
                "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}
    hud = [entry("hud", fn, im, f, face, fx, PORTRAITS / fn) for fn, im, f, face, fx in files["hud"]]
    res = [entry("result", fn, im, f, face, fx, RESULTS / fn) for fn, im, f, face, fx in files["result"]]
    p = HUD / "PROVENANCE.json"
    prov = json.loads(p.read_text())
    prov["files"] = [e for e in prov["files"] if not str(e.get("derived_from", "")).startswith("tools/hud_expressions.py")]
    prov["files"] = sorted(prov["files"] + hud, key=lambda e: e["runtime_path"])
    p.write_text(json.dumps(prov, indent=2) + "\n")
    (RESULTS / "PROVENANCE.json").write_text(json.dumps({
        "source": "Blue Archive PC client (Steam install), Spine rigs read with UnityPy and SkelToJson",
        "extraction_scripts": "tools/hud_expressions.py (build), tools/hud_expressions_fit.py (crops)",
        "files": sorted(res, key=lambda e: e["runtime_path"]),
        "scope": "Local fan project. Redistribution permission is not inferred."}, indent=2) + "\n")


def states(a):
    """Contact sheets of the built tiles: one row per fighter, calm then the seven states, labelled."""
    ex = json.loads((PORTRAITS / "expressions.json").read_text())
    outd = Path(a.out)
    outd.mkdir(parents=True, exist_ok=True)
    cols = ["calm"] + STATES
    people = [(k, f) for k, f in fighters().items()]
    for n in range(0, len(people), 10):
        chunk = people[n:n + 10]
        sheet = Image.new("RGB", (len(cols) * CARD[0], len(chunk) * CARD[1]), (70, 76, 90))
        for r, (k, f) in enumerate(chunk):
            for c, st in enumerate(cols):
                im = Image.open(PORTRAITS / ex[str(f["id"])][st]).convert("RGBA")
                bg = Image.new("RGBA", im.size, (70, 76, 90, 255))
                bg.alpha_composite(im)
                ImageDraw.Draw(bg).text((4, 4), "%s %s" % (k, st), fill=(255, 255, 0, 255))
                sheet.paste(bg.convert("RGB"), (c * CARD[0], r * CARD[1]))
        sheet.save(outd / ("states_%d.png" % (n // 10)))
    if not (RESULTS / "10062_win.webp").exists():
        return
    fit = json.loads(FIT.read_text())
    cell = 300
    for n in range(0, len(people), 10):
        chunk = people[n:n + 10]
        sheet = Image.new("RGB", (6 * cell, 5 * cell), (70, 76, 90))
        for i, (k, f) in enumerate(chunk):
            skel = load_rig(a.work, f["spr"])[0] if a.work else None
            base = Image.open(RESULTS / ("%d.webp" % f["id"])).convert("RGBA")
            x0, y0, x1, y1 = box_px(skel, fit[k]["result"]["crop"], base.size)
            side = max(x1 - x0, y1 - y0) * 1.5
            cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
            box = tuple(int(v) for v in (cx - side / 2, cy - side / 2, cx + side / 2, cy + side / 2))
            for j, nm in enumerate(("%d" % f["id"], "%d_win" % f["id"], "%d_lose" % f["id"])):
                im = Image.open(RESULTS / (nm + ".webp")).convert("RGBA")
                bg = Image.new("RGBA", im.size, (70, 76, 90, 255))
                bg.alpha_composite(im)
                t = bg.crop(box).resize((cell, cell), Image.LANCZOS).convert("RGB")
                ImageDraw.Draw(t).text((4, 4), "%s %s" % (k, nm.split("_")[-1] if "_" in nm else "now"), fill=(255, 255, 0))
                sheet.paste(t, (((i % 2) * 3 + j) * cell, (i // 2) * cell))
        sheet.save(outd / ("results_%d.png" % (n // 10)))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    e = sub.add_parser("extract")
    e.add_argument("--install", required=True)
    e.add_argument("--work", required=True)
    s = sub.add_parser("sheets")
    s.add_argument("--work", required=True)
    s.add_argument("--out", required=True)
    s.add_argument("--only")
    b = sub.add_parser("build", help="render and write; --no-write only prints the table and the flags")
    b.add_argument("--work", required=True)
    b.add_argument("--picks", default=str(PICKS))
    b.add_argument("--only")
    b.add_argument("--tiles-only", action="store_true", help="skip the result images (the slow part)")
    b.add_argument("--no-write", dest="write", action="store_false")
    t = sub.add_parser("states", help="contact sheets of the built tiles and result heads")
    t.add_argument("--out", required=True)
    t.add_argument("--work", required=True)
    a = ap.parse_args()
    {"extract": extract, "sheets": sheets, "build": build, "states": states}[a.cmd](a)


if __name__ == "__main__":
    main()
