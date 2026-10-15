#!/usr/bin/env python3
"""Copy the curated Blue Archive effect textures from the extraction export into assets/ba/fx and write PROVENANCE.json.
usage: python3 tools/fx_assets.py [export_dir]      (default export/ba_research/local-ba-fx/export)
The export has MANIFEST.csv with the bundle, CAB and path id of every file. Only the files listed in PICK are copied."""
import csv
import hashlib
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "export/ba_research/local-ba-fx/export"
DST = ROOT / "assets/ba/fx"

# published path (under assets/ba/fx) -> file in the export
PICK = {
    "spark/hit_star_burst_2x2.png": "fx/spark/hit_star_burst_2x2.png",
    "spark/cross_blades_4.png": "fx/spark/cross_blades_4.png",
    "spark/spark_streak_a.png": "fx/spark/spark_streak_a.png",
    "spark/spark_capsule_glow.png": "fx/spark/spark_capsule_glow.png",
    "muzzle/muzzle_flash_a_2x2.png": "fx/muzzle/muzzle_flash_a_2x2.png",
    "ring/circle_solid.png": "fx/ring/circle_solid.png",
    "ring/ring_wave_mask.png": "fx/ring/ring_wave_mask.png",
    "ring/glow_disc_soft.png": "fx/ring/glow_disc_soft.png",
    "ring/shockwave_spikes_2x2.png": "fx/ring/shockwave_spikes_2x2.png",
    "ring/shockwave_spikes_2x2_mask.png": "fx/ring/shockwave_spikes_2x2_mask.png",
    "block/block_card_shield_blue.png": "fx/block/block_card_shield_blue.png",
    "block/block_hexagon_outline.png": "fx/block/block_hexagon_outline.png",
    "damage_text/damage_digits_normal.png": "ui/damage_text/damage_digits_normal.png",
    "damage_text/damage_digits_weak.png": "ui/damage_text/damage_digits_weak.png",
    "dust/smoke_puff_white_2x2.png": "fx/dust/smoke_puff_white_2x2.png",
    "boom/boom_puff_sheet_4x4.png": "fx/boom/boom_puff_sheet_4x4.png",
    "boom/boom_spiky_cloud.png": "fx/boom/boom_spiky_cloud.png",
    "ko/focus_lines_spikes.png": "fx/ko/focus_lines_spikes.png",
    "spark/hit_8point_star_glow.png": "fx/spark/hit_8point_star_glow.png",
    "sparkle/sparkle_4point.png": "fx/sparkle/sparkle_4point.png",
    "heal/heal_plus_round.png": "fx/heal/heal_plus_round.png",
    "slash/slash_blade_streaks.png": "fx/slash/slash_blade_streaks.png",
    "spark/hit_4point_star_fat.png": "fx/spark/hit_4point_star_fat.png",
}

manifest = {}
with open(SRC / "MANIFEST.csv", newline="") as f:
    for row in csv.DictReader(f):
        manifest[row["file"]] = row

entries = []
for out_rel, src_rel in PICK.items():
    row = manifest.get(src_rel)
    if row is None:
        sys.exit("not in MANIFEST.csv: " + src_rel)
    dst = DST / out_rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(SRC / src_rel, dst)
    data = dst.read_bytes()
    entries.append({
        "runtime_path": "assets/ba/fx/" + out_rel,
        "source_name": row["source_name"],
        "bundle": row["bundle"],
        "cab": row["cab"],
        "path_id": row["path_id"],
        "container": row["container"],
        "width": int(row["width"]),
        "height": int(row["height"]),
        "sha256": hashlib.sha256(data).hexdigest(),
        "bytes": len(data),
    })

prov = {
    "source": "Blue Archive PC client (Steam install), extracted with UnityPy 2026-10-14",
    "extraction_scripts": "tools/fx_assets.py copies and checks the curated set from the research export; the UnityPy extraction itself "
                          "(export/ba_research/local-ba-fx/scripts) is not tracked",
    "files": entries,
    "scope": "Local fan project. Redistribution permission is not inferred.",
}
(DST / "PROVENANCE.json").write_text(json.dumps(prov, indent=2) + "\n")
print("copied %d files" % len(entries))
