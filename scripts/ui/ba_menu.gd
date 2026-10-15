extends RefCounted
## Drawing pieces shared by the pause menu, the result screen and the training overlay (preload, no class_name).
## BA's UI sprites are cut at 2x the 1280x720 reference, so popups, plates and ribbons are drawn at K.

const K := 0.5
const SHEAR := BaTokens.SHEAR

## BaArt.nine with the corners drawn at k times their cut size (ky for the top and bottom ones when it differs). shear leans
## the whole rect around its centre.
static func nine(ci: CanvasItem, name: String, rect: Rect2, k := K, tint := Color.WHITE, shear := 0.0, ky := -1.0) -> void:
	BaArt.nine(ci, name, rect, tint, shear, k, ky)

## Bold italic Noto Sans leaning "/" around the baseline, like BA's labels. align 0, 1, 2: pos.x is the left edge, the
## centre or the right edge. pos.y is the baseline. Returns the width. Resets the canvas transform.
static func label(ci: CanvasItem, text: String, pos: Vector2, size: int, fill: Color, outline := Color(0, 0, 0, 0), ow := 0, align := 0, weight := 700) -> float:
	var f := UI.font_ui(weight)
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := pos.x - w * (0.0 if align == 0 else (0.5 if align == 1 else 1.0))
	ci.draw_set_transform_matrix(BaArt.lean_xform(SHEAR, pos.y))
	if ow > 0 and outline.a > 0.0:
		ci.draw_string_outline(f, Vector2(x, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ow, outline)
	ci.draw_string(f, Vector2(x, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, fill)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	return w

static func text_width(text: String, size: int, weight := 700) -> float:
	return UI.font_ui(weight).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

## The largest size from `size` down to `min_size` at which text fits max_w in font.
static func fit_font(font: Font, text: String, size: int, max_w: float, min_size := 12) -> int:
	var s := size
	while s > min_size and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > max_w:
		s -= 1
	return s

static func fit(text: String, size: int, max_w: float, min_size := 12, weight := 700) -> int:
	return fit_font(UI.font_ui(weight), text, size, max_w, min_size)

## text cut to max_w with an ellipsis, for labels that stay too long at the smallest size.
static func clip(text: String, size: int, max_w: float, weight := 700) -> String:
	if text_width(text, size, weight) <= max_w:
		return text
	var s := text
	while s.length() > 1 and text_width(s + "…", size, weight) > max_w:
		s = s.left(s.length() - 1)
	return s.strip_edges() + "…"

## A hint line is a list of parts: a String is italic label text, a Texture2D is a controller or key glyph.
## glyph_h is the picture's side. Glyphs are white with alpha, so `fill` tints them like the text.
static func parts_width(parts: Array, size: int, glyph_h: float, weight := 700) -> float:
	var w := 0.0
	for p in parts:
		w += glyph_h if p is Texture2D else text_width(p, size, weight)
	return w

## Draws the parts from pos.x along the baseline pos.y. Returns the width. The lean stays on the text and the glyphs stand upright.
static func draw_parts(ci: CanvasItem, parts: Array, pos: Vector2, size: int, glyph_h: float, fill: Color, weight := 700) -> float:
	var x := pos.x
	for p in parts:
		if p is Texture2D:
			ci.draw_texture_rect(p, Rect2(x, pos.y - size * 0.34 - glyph_h * 0.5, glyph_h, glyph_h), false, fill)
			x += glyph_h
		else:
			x += label(ci, p, Vector2(x, pos.y), size, fill, Color(0, 0, 0, 0), 0, 0, weight)
	return x - pos.x

## A navy ribbon with a white rim (Combat_Title_Bg), leaned. Text is white italic, centred, sized to the ribbon.
static func ribbon(ci: CanvasItem, rect: Rect2, text: String, a := 1.0) -> void:
	ribbon_parts(ci, rect, [text], a)

## The same ribbon holding parts (text and glyphs), the whole line shrunk to fit.
static func ribbon_parts(ci: CanvasItem, rect: Rect2, parts: Array, a := 1.0, glyph_k := 0.76) -> void:
	nine(ci, "Combat__Combat_Title_Bg", rect, K, Color(1, 1, 1, a), SHEAR)
	var size := int(rect.size.y * 0.58)
	var gh := rect.size.y * glyph_k   # the rim is part of the rect: the glyph stays inside it
	while size > 9 and parts_width(parts, size, gh) > rect.size.x - 16.0:
		size -= 1
	var w := parts_width(parts, size, gh)
	draw_parts(ci, parts, Vector2(rect.get_center().x - w * 0.5, rect.get_center().y + size * 0.36), size, gh, Color(1, 1, 1, a))

## The notched yellow Card_Select_Line around rect. pulse is Motion.pulse(t).
static func bracket(ci: CanvasItem, rect: Rect2, pulse := 1.0, a := 1.0) -> void:
	nine(ci, "Common__Card_Select_Line", rect, 0.8, Color(1, 1, 1, pulse * a), 0.0, 0.46)
