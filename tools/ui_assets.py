#!/usr/bin/env python3
"""The few extra Blue Archive sprites the options screen uses -> assets/ba/ui, with PROVENANCE.json.

Reads the research export (gitignored, default export/ba_research/research2) that tools/hud_assets.py also reads:
generic-tells/ba/sprites and ba-ui-language/all_paths.txt. Standard library only.
  python3 -I tools/ui_assets.py [--src DIR]"""
import argparse
import hashlib
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/ba/ui"
DEFAULT_SRC = ROOT / "export/ba_research/research2"

# <atlas>__<sprite>: Common_Option_Sound_* are the speaker icons of BA's sound options; Common_Icon_Close is its white X
SPRITES = ["Common__Common_Icon_Close", "Common__Common_Option_Sound_Full", "Common__Common_Option_Sound_Mute"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=str(DEFAULT_SRC))
    src = Path(ap.parse_args().src)
    bundles = {}
    for line in (src / "ba-ui-language/all_paths.txt").read_text().splitlines():
        parts = line.split("\t")
        if len(parts) >= 2:
            bundles[parts[0]] = parts[1]
    index = json.loads((src / "generic-tells/ba/sprite_index.json").read_text())
    files = []
    OUT.mkdir(parents=True, exist_ok=True)
    for stem in SPRITES:
        atlas, name = stem.split("__", 1)
        data = (src / "generic-tells/ba/sprites" / (stem + ".png")).read_bytes()
        w, h = struct.unpack(">II", data[16:24])
        hit = [e for e in index[name] if e["atlas"] == atlas][0]
        assert (w, h) == (hit["w"], hit["h"]), stem
        container = "Assets/_MX/UIs/Atlas/%s.png" % atlas
        (OUT / (stem + ".png")).write_bytes(data)
        files.append({"kind": "extracted", "source_name": name, "atlas": atlas, "bundle": bundles[container], "container": container,
                      "runtime_path": "assets/ba/ui/%s.png" % stem, "width": w, "height": h,
                      "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)})
    prov = {"source": "Blue Archive PC client (Steam install), extracted with UnityPy 2026-10-14",
            "extraction_scripts": "tools/ui_assets.py (copy and provenance) from the research export used by tools/hud_assets.py",
            "files": files,
            "scope": "Local fan project. Redistribution permission is not inferred."}
    (OUT / "PROVENANCE.json").write_text(json.dumps(prov, indent=2) + "\n")
    print("ui assets: %d sprites" % len(files))


if __name__ == "__main__":
    main()
