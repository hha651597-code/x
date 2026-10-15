#!/usr/bin/env python3
"""The main menu's Story and Single Play pictures: a random chapter illustration from Blue Archive's story-chapter select art.
Writes assets/ba/menu_cg/<name>.jpg (1024 px wide), menu_cg.json (the two pools) and PROVENANCE.json.

Copy the bundles out of the install first and never run anything from it (SRC is a scratch folder):
  cp .../PUB/Resource/GameData/Windows/*uis-03_scenario-05_mode* SRC/
usage: ~/Tools/venv-stages/bin/python -I tools/menu_cg_assets.py SRC        (UnityPy, Pillow)

The pools were sorted by eye: BATTLE shows the student with a weapon in hand, STORY is everything calmer."""
import glob
import hashlib
import io
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/ba/menu_cg"
WIDTH = 1024

BATTLE = ["Sub_Chapter_1_1", "Sub_Chapter_3_1", "Sub_Chapter_5_1", "Sub_Chapter_6_1", "Sub_Chapter_7_1", "Sub_Chapter_8_1", "Sub_Chapter_9_1",
          "Sub_Chapter_12_1", "Sub_Chapter_15_1", "Sub_Chapter_18_1", "Sub_Chapter_19_1", "Sub_Chapter_20_1", "Sub_Chapter_23_1",
          "Mini_Chapter_6_1", "Mini_Chapter_9_1", "Mini_Chapter_10_1", "Mini_Chapter_11_1"]
STORY = ["Sub_Chapter_2_1", "Sub_Chapter_4_1", "Sub_Chapter_10_1", "Sub_Chapter_11_1", "Sub_Chapter_13_1", "Sub_Chapter_14_1", "Sub_Chapter_16_1",
         "Sub_Chapter_17_1", "Sub_Chapter_21_1", "Sub_Chapter_22_1", "Sub_Chapter_24_1", "Sub_Chapter_25_1", "Sub_Chapter_26_1",
         "Mini_Chapter_1_1", "Mini_Chapter_2_1", "Mini_Chapter_3_1", "Mini_Chapter_4_1", "Mini_Chapter_5_1", "Mini_Chapter_7_1",
         "Mini_Chapter_12_1", "Mini_Chapter_13_1", "Mini_Chapter_14_1", "Mini_Chapter_15_1",
         "Replay_Contents_Prologue_EpisodeSelect", "Replay_Contents_Shop_EpisodeSelect"]


def main(src):
    import UnityPy
    from PIL import Image
    need = set(BATTLE + STORY)
    found = {}
    for f in sorted(glob.glob(str(Path(src) / "*.bundle"))):
        for o in UnityPy.load(f).objects:
            if o.type.name == "Texture2D":
                d = o.read()
                if d.m_Name in need and d.m_Name not in found:
                    found[d.m_Name] = (d.image.convert("RGB"), Path(f).name)
    missing = need - set(found)
    if missing:
        sys.exit("textures not found in %s: %s" % (src, sorted(missing)))
    OUT.mkdir(parents=True, exist_ok=True)
    prov = {}
    for name, (im, bundle) in sorted(found.items()):
        im = im.resize((WIDTH, round(im.height * WIDTH / im.width)), Image.LANCZOS)
        buf = io.BytesIO()
        im.save(buf, "JPEG", quality=84)
        (OUT / (name + ".jpg")).write_bytes(buf.getvalue())
        prov[name + ".jpg"] = {"texture": name, "bundle": bundle, "sha256": hashlib.sha256(buf.getvalue()).hexdigest(),
                               "derived_from": "tools/menu_cg_assets.py: resized to %d px wide, JPEG q84" % WIDTH}
    (OUT / "menu_cg.json").write_text(json.dumps({"battle": BATTLE, "story": STORY}, indent=1) + "\n")
    (OUT / "PROVENANCE.json").write_text(json.dumps(prov, indent=1, sort_keys=True) + "\n")
    print("wrote %d pictures, %.1f MB" % (len(prov), sum(p.stat().st_size for p in OUT.glob("*.jpg")) / 1048576))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else sys.exit(__doc__))
