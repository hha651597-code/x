# Blue Archive effect textures

Extracted from a Blue Archive Steam install with UnityPy. Provenance (bundle, asset path, sha256) is in
`PROVENANCE.json`; `tools/fx_assets.py` regenerates this folder from the extraction export.

The sheets are mostly white-on-black masks (DXT1 in the game, no real alpha), so `shaders/fx_sprite.gdshader` takes alpha
from luminance for them. The damage numerals and the later effect sheets (puffs, explosion frames, the spike cloud,
focus lines, the thin four-point star) have real alpha.

Used with permission for this fan project. Redistribution permission is not inferred.
