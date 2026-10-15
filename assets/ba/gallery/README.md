# Blue Archive art for the Extras screen

Four sprites and one texture that only `scripts/ui/gallery_*.gd` use, taken from a Blue Archive Steam install through the
same research export as `assets/ba/hud`. `PROVENANCE.json` has the bundle, container path, size and sha256 of every file;
`index.json` has the size and 9-slice borders.

| file | what it is for |
|---|---|
| `sprites/Common__Card_Item_Bg_N.png` | the facet card with its white rim: every portrait tile, the art stage, the jukebox sleeve, the empty-state card. Tinted per school |
| `sprites/Common__Common_Icon_Formation_Star.png`, `..._Star_Disable.png` | rarity stars, lit and unlit |
| `sprites/Common__Common_Deco_DotLine.png` | the dotted divider between rows |
| `tex/UIs__00_Images__Image_Normal_Empty2.png` | Plana in a triangle, BA's own empty-state picture, on the Records page with no matches |

Everything else the screen draws (header, ribbons, plates, bracket, portraits, role icons, crests, numerals, gauges) comes from
`assets/ba/hud` through `BaArt`, `BaNumerals` and `scripts/ui/ba_menu.gd`.

Rebuild: `python3 -I tools/gallery_assets.py build --src <research export>` (standard library only). Test: the hash checks in
`scripts/ui/tests/extras_test.gd`.

Used with permission for this fan project. Redistribution permission is not inferred.
