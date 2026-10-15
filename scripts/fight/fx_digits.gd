class_name FxDigits
extends RefCounted
## BA's bitmap damage numerals (the D_Font sheets). The sheet already carries each digit's outline and shadow.
## RECTS: digit -> [x, y, w, h, advance] in sheet pixels (256x128, digits are 64 px high), read from the game's font data. The
## advance of 1 is 36, not the font's 42: the glyph's ink ends at 37 of its 46 px, which left a gap of 6 to 8 px after it where
## every other pair of digits has -4 to 5. The region of 5 is 49 px wide, not 51: columns 49 and 50 of its cell hold a faint strip
## (alpha 36) that belongs to the fringe of the 6 beside it and showed as a stray line to the right of the last digit.

const RECTS := {
	"0": [1, 0, 54, 64, 48], "1": [55, 0, 46, 64, 36], "2": [101, 0, 51, 64, 48], "3": [152, 0, 51, 64, 48], "4": [205, 0, 51, 64, 48],
	"5": [0, 64, 49, 64, 48], "6": [51, 64, 51, 64, 48], "7": [101, 64, 51, 64, 48], "8": [154, 64, 51, 64, 48], "9": [205, 64, 51, 64, 48],
}
const SHEET := {"normal": "digits_normal", "weak": "digits_weak"}     # the only damage sheets FxArt registers; other variants fall back to normal

## Pixel width of `text` when a digit is `px_h` high. Characters that are not digits count as nothing.
static func width(text: String, px_h: float) -> float:
	var s := px_h / 64.0
	var w := 0.0
	for ch in text:
		if RECTS.has(ch):
			w += float(RECTS[ch][4]) * s
	return w

## One Sprite2D per digit under `parent`, centred on its origin horizontally and standing on it vertically.
static func build(parent: Node2D, text: String, variant: String, px_h: float) -> Array:
	var out: Array = []
	var s := px_h / 64.0
	var x := -width(text, px_h) * 0.5
	for ch in text:
		if not RECTS.has(ch):
			continue
		var r: Array = RECTS[ch]
		var sp := FxArt.sprite(str(SHEET.get(variant, "digits_normal")), "mix", false)
		sp.region_enabled = true
		sp.region_filter_clip_enabled = true
		sp.region_rect = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
		sp.scale = Vector2.ONE * s
		sp.position = Vector2(x + float(r[2]) * 0.5 * s, -px_h * 0.5)
		parent.add_child(sp)
		out.append(sp)
		x += float(r[4]) * s
	return out
