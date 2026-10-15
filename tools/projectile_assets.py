#!/usr/bin/env python3
"""The textures Blue Archive's own bullets, beams and energy balls are drawn with, for the projectiles in scripts/fight/projectile.gd.
Writes assets/ba/fx/bullet/<name>.png and adds their entries to assets/ba/fx/PROVENANCE.json.

Copy the effect bundles out of the install first and never run anything from it (SRC is a scratch folder):
  cp .../PUB/Resource/GameData/Windows/*effectsfreezed* SRC/
usage: ~/Tools/venv-stages/bin/python -I tools/projectile_assets.py SRC        (UnityPy, Pillow)

Most of these are white-on-black masks with no real alpha (FX_TEX_Bulletline_*, FX_TEX_BeamLine_1): shaders/fx_sprite.gdshader takes
their alpha from luminance, like the rest of assets/ba/fx. Energy_Ball_01, Beam_01, Falloffbeam_01 and Fire_08 carry real alpha."""
import glob
import hashlib
import io
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/ba/fx/bullet"

# our name -> the game's texture (width, height pin the right one where two share a name)
TEXTURES = {
    "tracer_comet": ("FX_TEX_Bulletline_02", 512, 256),
    "tracer_head": ("FX_TEX_Bulletline_07", 128, 128),
    "tracer_capsule": ("FX_TEX_Bulletline_03", 256, 256),
    "beam_soft": ("FX_TEX_BeamLine_1", 512, 512),
    "beam_strip": ("FX_TEX_Beam_01", 128, 32),
    "beam_falloff": ("FX_TEX_Falloffbeam_01", 128, 128),
    "energy_ball": ("FX_TEX_Energy_Ball_01", 128, 128),
    "fire_puff_5x4": ("FX_TEX_Fire_08", 512, 512),
}


def main(src):
    import UnityPy
    want = {(t[0], t[1], t[2]): k for k, t in TEXTURES.items()}
    found = {}
    for f in sorted(glob.glob(str(Path(src) / "*.bundle"))):
        for o in UnityPy.load(f).objects:
            if o.type.name == "Texture2D":
                d = o.read()
                k = want.get((d.m_Name, d.m_Width, d.m_Height))
                if k and k not in found:
                    found[k] = (d.image.convert("RGBA"), Path(f).name, d.m_Name, str(o.path_id), d.m_Width, d.m_Height)
    missing = set(TEXTURES) - set(found)
    if missing:
        sys.exit("textures not found in %s: %s" % (src, sorted(missing)))
    OUT.mkdir(parents=True, exist_ok=True)
    prov_path = ROOT / "assets/ba/fx/PROVENANCE.json"
    prov = json.loads(prov_path.read_text())
    prov["files"] = [e for e in prov["files"] if not e["runtime_path"].startswith("assets/ba/fx/bullet/")]
    for name, (im, bundle, tex, path_id, w, h) in sorted(found.items()):
        buf = io.BytesIO()
        im.save(buf, "PNG", optimize=True)
        (OUT / (name + ".png")).write_bytes(buf.getvalue())
        prov["files"].append({"runtime_path": "assets/ba/fx/bullet/%s.png" % name, "source_name": tex, "bundle": bundle, "path_id": path_id,
                              "container": "Assets/_MX/EffectsFreezed/Texture/%s" % tex, "width": w, "height": h,
                              "sha256": hashlib.sha256(buf.getvalue()).hexdigest(), "bytes": len(buf.getvalue()),
                              "derived_from": "tools/projectile_assets.py: exported unchanged as RGBA PNG"})
    prov_path.write_text(json.dumps(prov, indent=1) + "\n")
    print("wrote %d textures" % len(found))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else sys.exit(__doc__))
