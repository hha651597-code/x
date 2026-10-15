# Far-field theme kits

A map picks its far field with `far_kit` in `tools/stages/maps.json`. `farfield_gen.py` merges `farfield_kits/<kit>/kit.json` with the map's own `maps/<map>/world.json`; keys in `world.json` win, and `sources`, `assets`, `crops`, `windows` and `fx` are merged by name. `layers` come from `world.json` when it has them, otherwise from the kit.

Kit keys

- `sources`: donor scenes per time (`d`, `n`). `"self"` is the map's own scene. A donor must exist in both times.
- `assets`: id to `{src, go}`, the official game object to cut. Optional `face: "auto"` turns a one-sided facade toward the camera, `gain` scales its baked light, `alpha: "drop"` skips decal sheets, `pick: "brightest"` takes the best lit instance.
- `crops`: rectangles cut from an official atlas into their own texture, for tiled ground and skyline blocks.
- `windows`: per atlas material, the window cells (atlas pixels). Night builds an emission texture from those cells' own pixels. A per-instance seed in UV2 picks which cells light up.
- `fx`: the official smoke and glow textures and their per-time shader parameters.
- `chunks`, `rules`, `haze`, `props_haze`, `texture_downscale`, `lit`: draw-call chunking, the keep-out rules, the haze curve (the colour comes from the map's `sky.json`), donor texture size, default lit-window fraction.
- `night_floor`: minimum baked light of far-field pieces at night (rgb), so a piece cut from a dark lightmap spot still shows its texture.

Vertex colours reach Godot as 8 bit, so every material carries its own `color_scale` in the sidecar `params` and the colours are stored divided by it.

Layer types in `world.json` or `kit.json`: `place`, `scatter` (optional `roof` clutter and smoke), `stacks` (tiers of pieces built up from a base), `line` (poles, wires, lamps with night glow), `ring` (a slab skyline on an arc), `skyline` (contiguous blocks that close the horizon), `ground` (flat colour skirt), `ground_cells` (cells on a street grid, textured from a crop, with optional `tint` and a `block` brightness range for the lots), `smoke`, `glow`. `lod` on a layer drops parts smaller than that fraction of a piece, which saves triangles on far layers.

Kits

- `gehenna-city`: slum and industrial city built from Gehenna's own pieces, ruins tenement facades and roof units, harbor containers and cranes.
- `desert`: dune ring, sand skirt, ruins slabs and the landmark tower, for Abydos maps such as the Valley of Student Council Presidents. Its `layers` use `"src": "self"` and `"go": "@ground"`, so the map's `world.json` only has to name its ground object with `ground_object`.
