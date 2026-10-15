# Blue Archive HUD art

Sprites, textures, numerals and portraits for the fight HUD, taken from a Blue Archive Steam install. The NGUI atlases
and the UI textures were read with UnityPy; `PROVENANCE.json` has the bundle, container path, size and sha256 of every file.
`index.json` has the size and 9-slice borders of every sprite (and a note where the Godot margins differ from NGUI's),
the portrait of every roster id, the word table and the school crests.

| folder | what | made by |
|---|---|---|
| `sprites/` | `<Atlas>__<Name>.png`, cut from the atlases | `tools/hud_assets.py build` |
| `tex/` | whole UI textures, named by their container path (`UIs__00_Images__...`) | `tools/hud_assets.py build` |
| `numerals/` | the six D_Font digit sheets and `glyphs.json`, the glyph boxes cut by alpha component | `tools/hud_assets.py build` |
| `portraits/` | `Student_Portrait_<Name>.png` and `_Small` for the two fighters and 81 specials, `MISSING.txt` | `tools/hud_assets.py extract-portraits`, then `build` |
| `portraits/` (expressions) | `Student_Portrait_<Name>_<state>.webp`, `expressions.json`, and `assets/ba/portrait/<id>_win.webp` and `_lose.webp`: the seven moods of every fighter, see `portraits/README.md` | `tools/hud_expressions.py` |
| `words/` | our baked stand-ins for ROUND n, FINAL ROUND, K.O., SUPER, EX READY, JUST GUARD, GUARD CRUSH | `tools/hud_words.py` |

Roster ids map to a portrait through `CharacterExcel`'s `dev_name` (a few students are `CH` numbers, such as `CH0187`), then through the roster name. The
match is recorded per id in `index.json` (`matched_by`). `MISSING.txt` lists ids that fall back to a baked
parallelogram from `assets/ba/portrait`; it is empty today.

The baked words are ours: Chakra Petch Bold Italic (OFL, `assets/fonts`) with a gradient, rim, outline and soft drop edge in
BA's style. They are not BA lettering and sit beside the real BLOCK, MISS and FIGHT! sprites only until an artist redraws them.

Code: `scripts/ui/ba_art.gd` (`BaArt`), `ba_numerals.gd` (`BaNumerals`), `ba_words.gd` (`BaWords`). Test:
`TEST=res://scripts/ui/tests/ba_art_test.gd MAXLINES=300 zsh tools/sd_test.sh`. Contact sheet: `zsh tools/ba_art_sheet.sh`.

Used with permission for this fan project. Redistribution permission is not inferred.
