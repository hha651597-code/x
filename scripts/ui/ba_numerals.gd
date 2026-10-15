class_name BaNumerals
extends RefCounted
## BA's D_Font bitmap numerals (assets/ba/hud/numerals), digits 0 to 9 only: the sheets hold nothing else, no colon, no
## percent. Glyph boxes come from numerals/glyphs.json (cut once by tools/hud_assets.py), nothing is measured at runtime.
## height is the height in px of a flat digit (1 2 3 4 5 7); round ones overshoot it by a pixel or two, like the sheet.
## Tiers are BA's damage colours: NORMAL white with a brown outline, EFFECTIVE orange, WEAK yellow, RESIST blue; WHITE is the
## plain white sheet the timer uses and MINI the small blue-white one.

enum Tier {NORMAL, EFFECTIVE, WEAK, RESIST, WHITE, MINI}

const KEYS := ["NORMAL", "EFFECTIVE", "WEAK", "RESIST", "WHITE", "MINI"]
const SPACE := 0.3        # a space is this much of the height

static var _tiers := {}

static func _tier(tier: int) -> Dictionary:
	if _tiers.is_empty():
		var f := FileAccess.open(BaArt.DIR + "numerals/glyphs.json", FileAccess.READ)
		if f == null:
			BaArt.warn("glyphs", "missing numerals/glyphs.json")
			_tiers = {"tiers": {}}
		else:
			_tiers = JSON.parse_string(f.get_as_text())
	var t: Dictionary = _tiers["tiers"].get(KEYS[tier], {})
	if not t.is_empty() and not t.has("tex"):
		t["tex"] = BaArt.file(str(t["file"]))
	return t

## Each drawable character of text as [x offset, glyph or null for a space], and the total width. Characters other than
## digits and spaces are skipped. s is px per sheet px.
static func _layout(text: String, t: Dictionary, s: float) -> Array:
	var cells: Array = []
	var x := 0.0
	var gap := float(t["gap"]) * s
	for ch in text:
		var g = t["glyphs"].get(ch)
		if g == null and ch != " ":
			continue
		if not cells.is_empty():
			x += gap
		cells.append([x, g])
		x += (float(g["rect"][2]) * s) if g != null else SPACE * float(t["height"]) * s
	return [cells, x]

static func width(text: String, height: float, tier: int = Tier.NORMAL) -> float:
	var t := _tier(tier)
	if t.is_empty():
		return 0.0
	return float(_layout(text, t, height / float(t["height"]))[1])

## pos is the top-left (align 0), top-centre (1) or top-right (2) of the text box.
static func draw(ci: CanvasItem, text: String, pos: Vector2, height: float, tier: int = Tier.NORMAL, tint := Color.WHITE, align := 0) -> void:
	var t := _tier(tier)
	if t.is_empty() or t["tex"] == null:
		return
	var s := height / float(t["height"])
	var lay := _layout(text, t, s)
	var x0 := pos.x - float(lay[1]) * (0.0 if align == 0 else (0.5 if align == 1 else 1.0))
	for c in lay[0]:
		if c[1] == null:
			continue
		var r: Array = c[1]["rect"]
		ci.draw_texture_rect_region(t["tex"], Rect2(x0 + float(c[0]), pos.y + float(c[1]["dy"]) * s, float(r[2]) * s, float(r[3]) * s),
				Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])), tint)
