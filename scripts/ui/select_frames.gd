class_name SelectFrames
extends RefCounted
## Framing of the big select-screen art. HEADS maps a fighter id to the head square [x, y, side] inside
## its portrait (pixels of the portrait file, found by matching the 120px head icon against the portrait).
## Every portrait is then scaled so its head square is HEAD_PX wide and the head lands on the side's anchor,
## which keeps the face size constant across differently-drawn portraits (like the video).

const HEAD_PX := 240.0
const ANCHOR := [Vector2(238, 196), Vector2(1058, 200)]   # head-square centre for P1 / P2

const HEADS := {
	10005: [217, 60, 230],  # Hoshino
	10004: [570, 117, 185],  # Hina
}

## {scale, pos} to place `tex` (full portrait) so that fighter `id`'s head sits on the anchor of `slot` (1|2).
static func frame(id: int, tex: Texture2D, slot: int) -> Dictionary:
	var h: Array = HEADS.get(id, [tex.get_width() * 0.3, 60, tex.get_width() * 0.4])
	var s := HEAD_PX / float(h[2])
	var centre := Vector2(float(h[0]) + float(h[2]) * 0.5, float(h[1]) + float(h[2]) * 0.5)
	return {"scale": s, "pos": ANCHOR[slot - 1] - centre * s, "size": Vector2(tex.get_size()) * s}

const NOTO := "res://assets/fonts/NotoSans-Variable.ttf"
static var _fonts := {}

## The video's wide black display face, approximated with Noto Sans Black stretched a little (names, big labels).
static func font(weight := 900, xscale := 1.12, spacing := -1) -> Font:
	var key := "%d/%.2f/%d" % [weight, xscale, spacing]
	if not _fonts.has(key):
		var f := FontVariation.new()
		f.base_font = load(NOTO)
		f.variation_opentype = {UI.WGHT_TAG: weight}
		f.variation_transform = Transform2D(Vector2(xscale, 0.0), Vector2(0.0, 1.0), Vector2.ZERO)
		f.spacing_glyph = spacing
		_fonts[key] = f
	return _fonts[key]

## A Label in that face with the white outline of the stills (ink fill). `size` is the em in px.
static func text(txt: String, size: int, outline := 4, weight := 900, xscale := 1.12, spacing := -1,
		align := HORIZONTAL_ALIGNMENT_LEFT, ink := BaTokens.SELECT_INK) -> Label:
	var l := Label.new()
	l.text = txt
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font(weight, xscale, spacing))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ink)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", Color.WHITE)
	l.add_theme_color_override("font_shadow_color", Color(0.05, 0.1, 0.18, 0.28))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("line_spacing", 0)
	return l
