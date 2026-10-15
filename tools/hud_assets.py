#!/usr/bin/env python3
"""Curated Blue Archive HUD art -> assets/ba/hud, with PROVENANCE.json and index.json.

Standard library only (Python 3.9), except the one-time portrait extraction, which needs UnityPy:

  1. Once, in a venv:   python3 -m venv V && V/bin/pip install UnityPy fmod_toolkit Pillow
     Copy the two bundles that hold the portraits out of the install first:
       cp .../PUB/Resource/GameData/Windows/uis-01_common-01_character-_mxload-2024-11-18_000_*.bundle B/   (215 textures)
       cp .../PUB/Resource/Preload/Windows/prologgroup-*uis-01_common-01_character-_mxprolog-2024-11-18_*.bundle B/   (7)
     Fetch CharacterExcel (roster id -> dev_name, e.g. 10062 Toki = CH0187):
       https://raw.githubusercontent.com/arisu-archive/bluearchive-data/global/ExcelDB/CharacterExcel.json
     V/bin/python -I tools/hud_assets.py extract-portraits B --out P --character-excel CharacterExcel.json
  2. ~/Tools/venv-sprites/bin/python tools/hud_words.py   (Pillow: bakes the stand-in words)
  3. python3 -I tools/hud_assets.py build --portraits P    (copies, slices numerals, writes the JSON files)

`build` reads the research export (default export/ba_research/research2, gitignored; override with --src):
generic-tells/ba/{sprites,tex,sprite_index.json}, gap/work/ba_extra (D_Font sheets) and ba-ui-language/all_paths.txt
(container path and bundle of every texture). Re-running it rewrites everything under assets/ba/hud except the baked
words and fallback portraits, which it only hashes, and the expression tiles of tools/hud_expressions.py, whose provenance it keeps. Without --portraits it keeps the portraits already tracked."""
import argparse
import hashlib
import json
import re
import shutil
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HUD = ROOT / "assets/ba/hud"
DEFAULT_SRC = ROOT / "export/ba_research/research2"

# <atlas>__<sprite> -> the build-list entries that use it
SPRITES = {
    "Combat__Combat_Bg_Hp": "2 3 4 10",
    "Combat__Combat_Gauge_Hp": "2 4",
    "Combat__Common_Bg_Raius5px": "2 4 5 13",
    "Combat__Common_Line_Dot": "2",
    "Combat__Combat_Title_Bg": "2 3 10 11",
    "Combat__Combat_CardBg_EX": "1 6",
    "Combat__Combat_CardBg_EX_CostTag": "3 4 5 6 12",
    "Combat__Combat_CostBg": "5",
    "Combat__Combat_Cost_Gauge": "5",
    "Combat__Combat_Time_Icon": "3",
    "Combat__Combat_Icon_Buff_ATK": "4",
    "Combat__Combat_Icon_Buff_DEF": "4",
    "Combat__Combat_Icon_Buff_Shield": "4",
    "Combat__Combat_Icon_Buff_AmmoCount": "4",
    "Combat__Combat_Icon_Buff_BlockRate": "4",
    "Combat__Combat_Icon_Debuff_ATK": "4",
    "Combat__Combat_Icon_CC_Stunned": "4 9",
    "Combat__Combat_Icon_Special_Fury": "4",
    "Combat__Common_Btn_BG": "5 10 11",
    "Combat__Combat_Balloon_Sup": "6",
    "Combat__Combat_CardBg_Tactice_Support": "12",
    "Combat__Combat_Icon_Arrow": "12",
    "Combat__Ingame_Operater_Text_Bg": "12",
    "Combat__Ingame_Emo_NearlyDead": "14",
    "Common__Common_Bg_Raius10px": "3",
    "Common__Card_Role_Bg": "2",
    "Common__Common_Icon_DamageDealer": "2",
    "Common__Common_Icon_Tanker": "2 4",
    "Common__Common_Icon_Healer": "2",
    "Common__Common_Icon_Supporter": "2",
    "Common__Common_Icon_Vehicle": "2",
    "Common__Common_Btn_Normal_Y_S_Pt": "5 11",
    "Common__Common_Btn_Normal_B_S_Pt": "5 11",
    "Common__Common_Nonoutline_W_Bg": "6 13",
    "Common__Card_Select_Line": "6 10 11",
    "Common__Common_Popup_Bg": "10",
    "Common__Common_Top_Menu_Bg": "10",
    "Common__Common_Attack_Icon": "7",
    "Common__Common_Defense_Icon": "11",
    "Emoji__Emoji_Twinkle": "3 9",
    "Emoji__Emoji_Sweat_1": "expressions",
    "Emoji__Emoji_Sweat_2": "expressions",
    "Emoji__Emoji_Tear_1": "expressions",
    "Emoji__Emoji_Exclamation": "expressions",
    "Floater__Imagefont_Block": "7",
    "Floater__Imagefont_Block_Resist": "7",
    "Floater__Imagefont_Miss_Unit": "7",
    "Floater__Imagefont_Immune_Unit": "7",
    "Floater__Imagefont_Cri_Bg": "7 8",
}

SCHOOLS = ["Abydos", "Arius", "Gehenna", "Hyakkiyako", "Millennium", "RedWinter", "Shanhaijing", "SRT", "Trinity", "Valkyrie"]
CREST = "UIs__01_Common__11_SchoolIcon__School_Icon_"

TEX = {
    "UIs__00_Images__ImageFont__Ingame_Image_Fight": "8",
    "UIs__00_Images__ImageFont__Ingame_Image_Start": "8",
    "UIs__00_Images__Ingame_Start_Light": "5 8",
    "UIs__00_Images__ImageFont__ImgFont_MinigameRhythm_Combo": "7",
    "UIs__00_Images__ImageFont__ImgFont_Win_ArenaResult": "8 11",
    "UIs__00_Images__ImageFont__ImgFont_Lose_Arena_Result": "8 11",
    "UIs__00_Images__ImageFont__ImgFont_VS": "11",
    "UIs__00_Images__ImageFont__ImgFont_BestRecord": "12",
    "UIs__00_Images__ImageFont__Ingame_Warning_Text_1": "14",
    "UIs__00_Images__Image_Triangle_Pattern_Deco_1": "1 11",
    "UIs__00_Images__Image_Deco_Circle": "1",
    "UIs__00_Images__BG__Tactic_Result_Bg": "11",
    "UIs__00_Images__Formation__UITex_BGBlueLight": "8",
    "UIs__00_Images__Ingame_Warning_Deco_3": "4 9",
    "UIs__00_Images__Ingame_Warning_Deco_1": "14",
}
# black-ground light textures: BA draws them additive (BaArt.additive())
ADDITIVE = {"UIs__00_Images__Ingame_Start_Light", "UIs__00_Images__Formation__UITex_BGBlueLight"}
for _s in SCHOOLS:
    TEX[CREST + (_s if _s in ("Arius",) else _s.upper())] = "2"

# tier -> (sheet in gap/work/ba_extra, container in the install, glyph gap in sheet px)
NUMERALS = {
    "NORMAL": ("D_Font_Normal__0fbbc.png", "D_Font_Normal.png"),
    "EFFECTIVE": ("D_Font_Effective__0fbbc.png", "D_Font_Effective.png"),
    "WEAK": ("D_Font_Weak__0fbbc.png", "D_Font_Weak.png"),
    "RESIST": ("D_Font_Resist__0fbbc.png", "D_Font_Resist.png"),
    "WHITE": ("D_Font__0fbbc.png", "D_Font.png"),
    "MINI": ("D_Font_Mini__49a6b.png", "D_Font_Mini.png"),
}
GLYPH_GAP = {"MINI": -8}      # outline overlap between neighbours, in sheet px (the mini sheet is 2x)
GLYPH_GAP_DEFAULT = -4

# word -> sprite or texture stem for BA's own image fonts; the baked stand-ins live in words/ (tools/hud_words.py)
REAL_WORDS = {
    "fight": "UIs__00_Images__ImageFont__Ingame_Image_Fight",
    "start": "UIs__00_Images__ImageFont__Ingame_Image_Start",
    "win": "UIs__00_Images__ImageFont__ImgFont_Win_ArenaResult",
    "lose": "UIs__00_Images__ImageFont__ImgFont_Lose_Arena_Result",
    "vs": "UIs__00_Images__ImageFont__ImgFont_VS",
    "warning": "UIs__00_Images__ImageFont__Ingame_Warning_Text_1",
    "block": "Floater__Imagefont_Block",
    "block_resist": "Floater__Imagefont_Block_Resist",
    "miss": "Floater__Imagefont_Miss_Unit",
    "immune": "Floater__Imagefont_Immune_Unit",
    "combo": "UIs__00_Images__ImageFont__ImgFont_MinigameRhythm_Combo",
    "best_record": "UIs__00_Images__ImageFont__ImgFont_BestRecord",
}
BAKED_WORDS = ["round_1", "round_2", "round_3", "final", "ko", "super", "ex_ready", "just_guard", "guard_crush",
               "training", "draw", "time_up"] + ["round_%d" % n for n in range(4, 10)]

ALIASES = {}    # roster name -> Student_Portrait name, when neither dev_name nor the name matches
PREFIX = "Student_Portrait_"

SCOPE = ("Local fan project. Redistribution permission is not inferred.")


# ---------------------------------------------------------------- PNG (stdlib)

def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        sys.exit("not a png: %s" % path)
    return struct.unpack(">II", head[16:24])


def read_rgba(path):
    """8-bit, non-interlaced RGB or RGBA PNG -> (w, h, bytearray RGBA)."""
    d = Path(path).read_bytes()
    pos, idat = 8, b""
    w = h = bd = ct = il = 0
    while pos < len(d):
        n, t = struct.unpack(">I4s", d[pos:pos + 8])
        body = d[pos + 8:pos + 8 + n]
        pos += 12 + n
        if t == b"IHDR":
            w, h, bd, ct, _, _, il = struct.unpack(">IIBBBBB", body)
        elif t == b"IDAT":
            idat += body
    if bd != 8 or il != 0 or ct not in (2, 6):
        sys.exit("unsupported png (bit depth %d, colour type %d, interlace %d): %s" % (bd, ct, il, path))
    bpp = 4 if ct == 6 else 3
    raw = zlib.decompress(idat)
    stride = w * bpp
    out = bytearray(h * stride)
    prev = bytearray(stride)
    for y in range(h):
        ft = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        if ft == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 255
        elif ft == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif ft == 3:
            for i in range(stride):
                line[i] = (line[i] + (((line[i - bpp] if i >= bpp else 0) + prev[i]) >> 1)) & 255
        elif ft == 4:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if (pa <= pb and pa <= pc) else (b if pb <= pc else c))) & 255
        out[y * stride:(y + 1) * stride] = line
        prev = line
    if bpp == 3:
        rgba = bytearray(w * h * 4)
        for i in range(w * h):
            rgba[i * 4:i * 4 + 3] = out[i * 3:i * 3 + 3]
            rgba[i * 4 + 3] = 255
        return w, h, rgba
    return w, h, out


def components(w, h, px, thr=1):
    """4-connected components of alpha >= thr: (area, x, y, w, h) boxes."""
    seen = bytearray(w * h)
    res = []
    for s in range(w * h):
        if px[s * 4 + 3] < thr or seen[s]:
            continue
        stack = [s]
        seen[s] = 1
        n = 0
        x0 = y0 = 1 << 30
        x1 = y1 = -1
        while stack:
            p = stack.pop()
            n += 1
            y, x = divmod(p, w)
            x0, x1, y0, y1 = min(x0, x), max(x1, x), min(y0, y), max(y1, y)
            for q in ((p - 1) if x else -1, (p + 1) if x < w - 1 else -1, p - w if y else -1, p + w if y < h - 1 else -1):
                if q >= 0 and not seen[q] and px[q * 4 + 3] >= thr:
                    seen[q] = 1
                    stack.append(q)
        res.append((n, x0, y0, x1 - x0 + 1, y1 - y0 + 1))
    return res


def slice_digits(path):
    """The ten glyph boxes of a D_Font sheet (two rows, 0-4 then 5-9) by alpha connected component, plus a per-glyph y
    offset against the most common top of its row, so round digits (0 6 8 9) overshoot instead of floating."""
    w, h, px = read_rgba(path)
    comps = [c for c in components(w, h, px) if c[0] > 40]
    if len(comps) != 10:
        sys.exit("%s: %d glyph components, expected 10 (two digits merged or a stray speck)" % (path, len(comps)))
    top = sorted((c for c in comps if c[2] + c[4] / 2 < h / 2), key=lambda c: c[1])
    bot = sorted((c for c in comps if c[2] + c[4] / 2 >= h / 2), key=lambda c: c[1])
    if len(top) != 5 or len(bot) != 5:
        sys.exit("%s: rows are %d + %d glyphs, expected 5 + 5" % (path, len(top), len(bot)))
    glyphs = {}
    for row in (top, bot):
        tops = [c[2] for c in row]
        ref = max(set(tops), key=tops.count)
        for c in row:
            glyphs[str(len(glyphs))] = {"rect": [c[1], c[2], c[3], c[4]], "dy": c[2] - ref}
    heights = [g["rect"][3] for g in glyphs.values()]
    rects = [g["rect"] for g in glyphs.values()]
    for i, a in enumerate(rects):
        for b in rects[i + 1:]:
            if a[0] < b[0] + b[2] and b[0] < a[0] + a[2] and a[1] < b[1] + b[3] and b[1] < a[1] + a[3]:
                sys.exit("%s: glyph boxes overlap: %s %s" % (path, a, b))
    return {"sheet": [w, h], "height": max(set(heights), key=heights.count), "glyphs": glyphs}


# ---------------------------------------------------------------- helpers

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def fixed_borders(w, h, b):
    """NGUI borders can leave no centre pixel (Combat_Bg_Hp 13+13 on 25 px): shave them to keep one stretched pixel."""
    l, r, t, bt = b
    if l + r > w - 1:
        ex = l + r - (w - 1)
        l, r = l - (ex + 1) // 2, r - ex // 2
    if t + bt > h - 1:
        ex = t + bt - (h - 1)
        t, bt = t - (ex + 1) // 2, bt - ex // 2
    return [l, r, t, bt]


def load_paths(src):
    """container path -> bundle, from the research export's all_paths.txt (path, bundle, index file; tab separated).
    The extraction dumps turned spaces in container paths into underscores (Image_Triangle Pattern_Deco_1), so keys do too."""
    out = {}
    for line in (src / "ba-ui-language/all_paths.txt").read_text().splitlines():
        parts = line.split("\t")
        if len(parts) >= 2:
            out[parts[0].replace(" ", "_")] = parts[1]
    return out


def tex_container(stem, paths):
    for prefix in ("Assets/_MX/AddressableAsset/", "Assets/_MX/"):
        cand = prefix + stem.replace("__", "/") + ".png"
        if cand in paths:
            return cand, paths[cand]
    sys.exit("no container path for texture " + stem)


def roster():
    r = json.loads((ROOT / "assets/ba/roster.json").read_text())
    return r["fighters"] + r["specials"]


# ---------------------------------------------------------------- extract-portraits (UnityPy, once)

def extract_portraits(args):
    import UnityPy
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    index = {}
    for b in sorted(p for d in args.bundles for p in Path(d).glob("*.bundle")):
        env = UnityPy.load(str(b))
        containers = {o.path_id: k for k, o in env.container.items()}
        for obj in env.objects:
            if obj.type.name != "Texture2D":
                continue
            d = obj.read()
            if not d.m_Name.startswith(PREFIX) or d.m_Name in index:
                continue
            d.image.save(out / (d.m_Name + ".png"))
            index[d.m_Name] = {"bundle": b.name, "path_id": obj.path_id, "container": containers.get(obj.path_id, ""),
                               "width": d.m_Width, "height": d.m_Height}
    (out / "index.json").write_text(json.dumps(index, indent=1))
    print("extracted %d portrait textures" % len(index))
    if args.character_excel:
        rows = json.loads(Path(args.character_excel).read_text())["data_list"]
        dev = {r["id"]: r["dev_name"] for r in rows}
        names = {str(f["id"]): dev.get(f["id"], "") for f in roster()}
        (out / "names.json").write_text(json.dumps(names, indent=1))
        print("dev names for %d roster ids" % len(names))


# ---------------------------------------------------------------- build

def build(args):
    src = Path(args.src)
    ba = src / "generic-tells/ba"
    paths = load_paths(src)
    sprite_index = json.loads((ba / "sprite_index.json").read_text())
    prov = {}
    index = {"sprites": {}, "tex": {}, "portraits": {}, "words": {}, "crests": {}}
    old_index = json.loads((HUD / "index.json").read_text()) if (HUD / "index.json").exists() else {}

    for sub in ("sprites", "tex", "numerals"):
        wipe_pngs(HUD / sub)

    for stem, entries in sorted(SPRITES.items()):
        atlas, name = stem.split("__", 1)
        hits = [e for e in sprite_index[name] if e["atlas"] == atlas]
        if not hits:
            sys.exit("sprite not in sprite_index: " + stem)
        e = hits[0]
        dst = HUD / "sprites" / (stem + ".png")
        shutil.copyfile(ba / "sprites" / (stem + ".png"), dst)
        if tuple(png_size(dst)) != (e["w"], e["h"]):
            sys.exit("size mismatch for " + stem)
        borders = fixed_borders(e["w"], e["h"], e["b"])
        item = {"w": e["w"], "h": e["h"], "borders": borders, "padding": e["p"]}
        if borders != e["b"]:
            item["source_borders"] = e["b"]
            item["note"] = ("NGUI borders %s leave no centre pixel on %dx%d; use margins l=%d r=%d t=%d b=%d "
                            "(one stretched pixel) in a Godot nine-patch" % ("/".join(map(str, e["b"])), e["w"], e["h"], *borders))
        index["sprites"][stem] = item
        container = "Assets/_MX/UIs/Atlas/%s.png" % atlas
        bundle = paths.get(container)
        if bundle is None:
            sys.exit("atlas bundle not found: " + atlas)
        prov["sprites/" + stem + ".png"] = {"kind": "extracted", "source_name": name, "atlas": atlas, "bundle": bundle,
                                            "container": container, "entries": entries}

    for stem, entries in sorted(TEX.items()):
        dst = HUD / "tex" / (stem + ".png")
        shutil.copyfile(ba / "tex" / (stem + ".png"), dst)
        w, h = png_size(dst)
        container, bundle = tex_container(stem, paths)
        index["tex"][stem] = {"w": w, "h": h}
        if stem in ADDITIVE:
            index["tex"][stem]["blend"] = "add"
        prov["tex/" + stem + ".png"] = {"kind": "extracted", "source_name": stem.rsplit("__", 1)[1], "bundle": bundle,
                                        "container": container, "entries": entries}
    for s in SCHOOLS:
        index["crests"][s.lower()] = CREST + (s if s == "Arius" else s.upper())

    glyphs = {"tiers": {}}
    for tier, (sheet, container_name) in NUMERALS.items():
        dst = HUD / "numerals" / (container_name)
        shutil.copyfile(src / "gap/work/ba_extra" / sheet, dst)
        g = slice_digits(dst)
        g["file"] = "numerals/" + container_name
        g["gap"] = GLYPH_GAP.get(tier, GLYPH_GAP_DEFAULT)
        glyphs["tiers"][tier] = g
        container = "Assets/_MX/UIs/_MXCommon/Fonts/" + container_name
        prov["numerals/" + container_name] = {"kind": "extracted", "source_name": container_name[:-4], "bundle": paths[container],
                                              "container": container, "entries": "0 3 5 7 12"}
    (HUD / "numerals/glyphs.json").write_text(json.dumps(glyphs, indent=1) + "\n")

    for word, stem in REAL_WORDS.items():
        index["words"][word] = {"kind": "ba", "texture": stem}
    for word in BAKED_WORDS:
        if not (HUD / "words" / (word + ".png")).exists():
            sys.exit("baked word missing, run tools/hud_words.py first: " + word)
        index["words"][word] = {"kind": "baked", "file": "words/%s.png" % word}
        prov["words/%s.png" % word] = {"kind": "baked", "source_name": word,
                                       "derived_from": "tools/hud_words.py from assets/fonts/ChakraPetch-BoldItalic.ttf (OFL)",
                                       "entries": "8 9"}

    portraits(args, index, old_index, prov)

    for rel, meta in prov.items():
        p = HUD / rel
        w, h = png_size(p)
        data = p.read_bytes()
        meta.update({"runtime_path": "assets/ba/hud/" + rel, "width": w, "height": h,
                     "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)})
    files = [prov[k] for k in sorted(prov)]
    keep = [e for e in json.loads((HUD / "PROVENANCE.json").read_text())["files"] if str(e.get("derived_from", "")).startswith("tools/hud_expressions.py")]
    files = sorted(files + keep, key=lambda e: e["runtime_path"])
    (HUD / "PROVENANCE.json").write_text(json.dumps({
        "source": "Blue Archive PC client (Steam install), extracted with UnityPy 2026-10-14",
        "extraction_scripts": "tools/hud_assets.py (copy, slice, provenance), tools/hud_words.py (baked words); research "
                              "export export/ba_research/research2 (not tracked)",
        "files": files,
        "scope": SCOPE}, indent=2) + "\n")
    (HUD / "index.json").write_text(json.dumps(index, indent=1) + "\n")
    drop_orphan_imports()
    print("hud assets: %d sprites, %d textures, %d numeral sheets, %d portraits, %d files with provenance" % (
        len(index["sprites"]), len(index["tex"]), len(NUMERALS), len(index["portraits"]), len(files)))


def portraits(args, index, old_index, prov):
    pdir = HUD / "portraits"
    people = roster()
    if not args.portraits:
        index["portraits"] = old_index.get("portraits", {})
        for rel in sorted(p.relative_to(HUD).as_posix() for p in pdir.glob("*.png")):
            prov[rel] = old_prov(rel)
        return
    src = Path(args.portraits)
    idx = json.loads((src / "index.json").read_text())
    lower = {k.lower(): k for k in idx}
    names_file = src / "names.json"
    names = json.loads(names_file.read_text()) if names_file.exists() else {k: v.get("dev_name", "") for k, v in old_index.get("portraits", {}).items()}
    wipe_pngs(pdir)
    missing = []
    for f in people:
        dev = re.sub(r"_default$", "", names.get(str(f["id"]), ""), flags=re.I)
        got = None
        for cand, how in ((dev, "dev_name"), (f["name"], "name"), (ALIASES.get(f["name"], ""), "alias")):
            key = lower.get((PREFIX + cand).lower()) if cand else None
            if key:
                got = (key, how, cand)
                break
        if got is None:
            missing.append(f)
            continue
        key, how, cand = got
        other = lower.get((PREFIX + f["name"]).lower())
        if how == "dev_name" and other and other != key:
            print("note: %s (%d) resolves to %s by dev_name but a texture named %s also exists" % (f["name"], f["id"], key, other))
        small = lower.get((key + "_Small").lower())
        entry = {"name": f["name"], "kind": f["kind"], "dev_name": dev, "matched_by": how, "texture": key, "fallback": False,
                 "file": "portraits/%s.png" % key, "small": ("portraits/%s.png" % small) if small else None}
        for k in (key, small):
            if k and not (pdir / (k + ".png")).exists():
                shutil.copyfile(src / (k + ".png"), pdir / (k + ".png"))
                m = idx[k]
                prov["portraits/%s.png" % k] = {"kind": "extracted", "source_name": k, "bundle": m["bundle"],
                                                "container": m["container"], "path_id": m["path_id"], "entries": "1 6"}
        index["portraits"][str(f["id"])] = entry
    lines = ["# Roster ids with no Student_Portrait in the install bundles. Each one uses a baked parallelogram fallback",
             "# (tools/hud_fallback.py) from the bust card in assets/ba/collection, named Student_Portrait_<name>_fallback.png.",
             "# One line per id: <id> <name> <kind>"]
    for f in missing:
        fb = "%s%s_fallback.png" % (PREFIX, f["name"])
        if not (HUD / "portraits" / fb).exists():
            sys.exit("no portrait for %s (%d) and no %s: run tools/hud_fallback.py" % (f["name"], f["id"], fb))
        index["portraits"][str(f["id"])] = {"name": f["name"], "kind": f["kind"], "dev_name": "", "matched_by": "fallback",
                                            "texture": fb[:-4], "fallback": True, "file": "portraits/" + fb, "small": None}
        prov["portraits/" + fb] = {"kind": "baked", "source_name": fb[:-4], "derived_from": "tools/hud_fallback.py from assets/ba/collection/%d.webp" % f["id"],
                                   "entries": "1 6"}
        lines.append("%d %s %s" % (f["id"], f["name"], f["kind"]))
    (pdir / "MISSING.txt").write_text("\n".join(lines) + "\n")
    print("portraits: %d resolved, %d on fallback" % (len(index["portraits"]) - len(missing), len(missing)))


def wipe_pngs(d):
    """Empty a folder of PNGs but keep Godot's .import files, so a rebuild does not change their uids, and the baked
    *_fallback.png portraits, which only tools/hud_fallback.py makes."""
    d.mkdir(parents=True, exist_ok=True)
    for p in d.glob("*.png"):
        if not p.name.endswith("_fallback.png"):
            p.unlink()


def drop_orphan_imports():
    for p in HUD.rglob("*.png.import"):
        if not p.with_suffix("").exists():
            p.unlink()


def old_prov(rel):
    old = json.loads((HUD / "PROVENANCE.json").read_text())["files"]
    for e in old:
        if e["runtime_path"] == "assets/ba/hud/" + rel:
            return {k: v for k, v in e.items() if k not in ("runtime_path", "width", "height", "sha256", "bytes")}
    sys.exit("no provenance entry to keep for " + rel)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    ex = sub.add_parser("extract-portraits", help="UnityPy: pull every Student_Portrait* texture out of copied bundles")
    ex.add_argument("bundles", nargs="+", help="directories of copied .bundle files")
    ex.add_argument("--out", required=True)
    ex.add_argument("--character-excel", help="CharacterExcel.json, to write names.json (roster id -> dev_name)")
    b = sub.add_parser("build", help="copy, slice and write PROVENANCE.json and index.json")
    b.add_argument("--src", default=str(DEFAULT_SRC))
    b.add_argument("--portraits", help="the extract-portraits output folder")
    args = ap.parse_args()
    (extract_portraits if args.cmd == "extract-portraits" else build)(args)


if __name__ == "__main__":
    main()
