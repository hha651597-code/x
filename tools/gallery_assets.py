#!/usr/bin/env python3
"""BA sprites and textures that only the Extras screen uses -> assets/ba/gallery, with PROVENANCE.json and index.json.

Standard library only (Python 3.9). Same input as tools/hud_assets.py build: the research export (default
export/ba_research/research2, gitignored; override with --src) with generic-tells/ba/{sprites,tex,sprite_index.json} and
ba-ui-language/all_paths.txt (container path and bundle of every texture). Re-running rewrites everything under assets/ba/gallery.

  python3 -I tools/gallery_assets.py build
"""
import argparse
import hashlib
import json
import shutil
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/ba/gallery"
DEFAULT_SRC = ROOT / "export/ba_research/research2"

# <atlas>__<sprite> -> what the Extras screen draws with it
SPRITES = {
    "Common__Card_Item_Bg_N": "facet card behind every portrait tile and the art stage",
    "Common__Common_Icon_Formation_Star": "rarity stars, lit",
    "Common__Common_Icon_Formation_Star_Disable": "rarity stars, unlit",
    "Common__Common_Deco_DotLine": "dotted row divider",
}
TEX = {
    "UIs__00_Images__Image_Normal_Empty2": "records empty state",
}

SCOPE = ("Local fan project. Redistribution permission is not inferred.")


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        sys.exit("not a png: %s" % path)
    return struct.unpack(">II", head[16:24])


def load_paths(src):
    """container path -> bundle (all_paths.txt is path, bundle, index file; tab separated)."""
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


def build(args):
    src = Path(args.src)
    ba = src / "generic-tells/ba"
    paths = load_paths(src)
    sprite_index = json.loads((ba / "sprite_index.json").read_text())
    prov = {}
    index = {"sprites": {}, "tex": {}}
    for sub in ("sprites", "tex"):
        d = OUT / sub
        d.mkdir(parents=True, exist_ok=True)
        for p in d.glob("*.png"):
            p.unlink()

    for stem, use in sorted(SPRITES.items()):
        atlas, name = stem.split("__", 1)
        hits = [e for e in sprite_index[name] if e["atlas"] == atlas]
        if not hits:
            sys.exit("sprite not in sprite_index: " + stem)
        e = hits[0]
        dst = OUT / "sprites" / (stem + ".png")
        shutil.copyfile(ba / "sprites" / (stem + ".png"), dst)
        if tuple(png_size(dst)) != (e["w"], e["h"]):
            sys.exit("size mismatch for " + stem)
        index["sprites"][stem] = {"w": e["w"], "h": e["h"], "borders": e["b"]}
        container = "Assets/_MX/UIs/Atlas/%s.png" % atlas
        if container not in paths:
            sys.exit("atlas bundle not found: " + atlas)
        prov["sprites/" + stem + ".png"] = {"kind": "extracted", "source_name": name, "atlas": atlas, "bundle": paths[container],
                                            "container": container, "use": use}

    for stem, use in sorted(TEX.items()):
        dst = OUT / "tex" / (stem + ".png")
        shutil.copyfile(ba / "tex" / (stem + ".png"), dst)
        w, h = png_size(dst)
        container, bundle = tex_container(stem, paths)
        index["tex"][stem] = {"w": w, "h": h}
        prov["tex/" + stem + ".png"] = {"kind": "extracted", "source_name": stem.rsplit("__", 1)[1], "bundle": bundle,
                                        "container": container, "use": use}

    for rel, meta in prov.items():
        p = OUT / rel
        w, h = png_size(p)
        data = p.read_bytes()
        meta.update({"runtime_path": "assets/ba/gallery/" + rel, "width": w, "height": h,
                     "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)})
    (OUT / "PROVENANCE.json").write_text(json.dumps({
        "source": "Blue Archive PC client (Steam install), extracted with UnityPy 2026-10-14 (through the research export)",
        "extraction_scripts": "tools/gallery_assets.py; research export export/ba_research/research2 (not tracked)",
        "files": [prov[k] for k in sorted(prov)],
        "scope": SCOPE}, indent=2) + "\n")
    (OUT / "index.json").write_text(json.dumps(index, indent=1) + "\n")
    for p in OUT.rglob("*.png.import"):
        if not p.with_suffix("").exists():
            p.unlink()
    print("gallery assets: %d sprites, %d textures" % (len(index["sprites"]), len(index["tex"])))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build", help="copy and write PROVENANCE.json and index.json")
    b.add_argument("--src", default=str(DEFAULT_SRC))
    args = ap.parse_args()
    build(args)


if __name__ == "__main__":
    main()
