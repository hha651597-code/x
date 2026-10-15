# Expression portraits

The HUD card and the result portrait of each fighter in seven more moods. Made by `tools/hud_expressions.py` from
the fighters' story-standing Spine rigs (`<name>_spr`), the same drawings the plain `Student_Portrait_<Name>.png` and
`assets/ba/portrait/<id>.webp` were cut from. Each new face is patched onto today's art, so everything outside the face is
today's pixels and the card does not shift when the state changes.

## Files

| file | what |
|---|---|
| `Student_Portrait_<Name>_<state>.webp` | 252x204 with the card's parallelogram alpha. States: `scratched`, `hurt`, `critical`, `flinch`, `win`, `lose`, `ko`. `<Name>` is the texture name in `index.json` (a `CH` number for a few students), as for the plain card |
| `expressions.json` | roster id (string) to state to file name in this folder. `calm` is the plain `.png` card |
| `../../portrait/<id>_win.webp`, `<id>_lose.webp` | result-screen images on the canvas of `<id>.webp`, so `SelectFrames.HEADS` still fits |

`expressions.json` also has `_overlays`: roster id to state to the list of baked overlays (below). Skip keys that start with `_`
when you walk the ids.

All seven state files exist for every fighter, even where two states share a face and differ only by overlay.

`calm` is the plain card for Hina. Hoshino's plain card is her laughing wink, which
does not read as calm, so her calm is `Student_Portrait_Hoshino_calm.webp` (face 01) and `expressions.json` points at it. A
game that uses the plain card for calm shows the wink. Provenance for the result images is in
`assets/ba/portrait/PROVENANCE.json`, for the tiles in `../PROVENANCE.json`.

## Ladder

The game picks the state; the art only has to be distinct. The thresholds: `scratched` below 0.80 of the HP bar, `hurt`
below 0.55, `critical` below 0.25, `flinch` for a drop of 0.12 or more, `ko` at 0, `win` after a won round, `lose` on the
result screen. `lose` and `win` tiles also exist so the card can show them.

## Overlays

Where a fighter's real faces do not differ enough at 150x121 (`DIFF_MIN` in the tool), the state carries overlays baked into the
tile, listed in `_overlays`: BA's own `sweat`, `sweat2`, `tears`, `shock` (the "!") and `twinkle` emotes from
`assets/ba/hud/sprites`, and the grades `vig1` and `vig2` (red edge, stronger and darker) and `desat`. The game does not draw
them again. Result images take the emotes only.

## Decisions

* `ko` is the rig's `Eye_Close_01` sampled at 0.05 s (`99` does not close every fighter's eyes).

## Rebuild

```
python tools/hud_expressions.py extract --install <BlueArchive> --work W      # UnityPy; copies the bundles out first
python tools/hud_expressions.py sheets  --work W --out S                      # every face of every fighter, labelled
python tools/hud_expressions.py build   --work W                              # tiles, result images, JSON, provenance
```

`build` exits non-zero when a state's face differs from calm by less than `DIFF_MIN` and has no overlay. The crops and colour
fits come from `tools/hud_expressions_fit.py`, run once per change of the plain art, and are committed in
`tools/hud_expressions_fit.json`. The picks are in `tools/hud_expressions_picks.json`.
