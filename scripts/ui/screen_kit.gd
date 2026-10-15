extends RefCounted
## Drawing pieces shared by the menu, assign and options screens (preload, no class_name), on top of BaArt and ba_menu.gd.

const Menu := preload("res://scripts/ui/ba_menu.gd")

const DOT_PITCH := 8.0
const DOT_PX := 3.0
const FACET_W := 185
const FACET_H := 140.0
const FACET_MAX := 0.91           # the lightest grey in the facet card's opaque middle

static var _facet_tex: ImageTexture

## UIAni_Scale_Select: 0.8, 0.962 at 0.067 s, 1.0 at 0.25 s. Same curve as the pause menu's bracket.
static func pop(t: float) -> float:
	if t < 0.067:
		return lerpf(0.8, 0.962, t / 0.067)
	return lerpf(0.962, 1.0, clampf((t - 0.067) / 0.183, 0.0, 1.0))

## The notched yellow Card_Select_Line around rect, leaning with the thing it frames. t is the screen clock (pulse), age the
## seconds since this thing was selected (pop). The sprite is drawn as two halves, so a wide rect gets two end brackets and not
## the glow of its middle column stretched into a line.
static func bracket(ci: CanvasItem, rect: Rect2, shear: float, t: float, age: float, a := 1.0) -> void:
	var s := pop(age)
	var r := Rect2(rect.get_center() - rect.size * s * 0.5, rect.size * s)
	var tint := Color(1, 1, 1, Motion.pulse(t) * a)
	var tex := BaArt.tex("Common__Card_Select_Line")
	if tex == null:
		return
	var b: Array = BaArt.info("Common__Card_Select_Line")["borders"]
	var half_l := float(b[0])
	var half_r := float(b[1])
	var k := 0.8
	if r.size.x < (half_l + half_r) * k:
		Menu.nine(ci, "Common__Card_Select_Line", r, k, tint, shear, 0.46)
		return
	var top := float(b[2])
	var bot := float(b[3])
	var sh := float(tex.get_height())
	var ky := minf(0.46, r.size.y / maxf(top + bot, 0.001))
	var sy := [0.0, top, sh - bot, sh]
	var dy := [r.position.y, r.position.y + top * ky, r.end.y - bot * ky, r.end.y]
	if shear != 0.0:
		ci.draw_set_transform_matrix(BaArt.lean_xform(shear, r.get_center().y))
	for j in 3:
		ci.draw_texture_rect_region(tex, Rect2(r.position.x, dy[j], half_l * k, dy[j + 1] - dy[j]), Rect2(0.0, sy[j], half_l, sy[j + 1] - sy[j]), tint)
		ci.draw_texture_rect_region(tex, Rect2(r.end.x - half_r * k, dy[j], half_r * k, dy[j + 1] - dy[j]),
				Rect2(tex.get_width() - half_r, sy[j], half_r, sy[j + 1] - sy[j]), tint)
	if shear != 0.0:
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)

## A dotted rule from x0 to x1 at y, made of BA's Common_Line_Dot.
static func dots(ci: CanvasItem, x0: float, x1: float, y: float, tint: Color) -> void:
	var x := x0
	while x + DOT_PX <= x1:
		BaArt.blit(ci, "Combat__Common_Line_Dot", Rect2(x, y, DOT_PX, DOT_PX), tint)
		x += DOT_PITCH

## A pastel in the picture's most colourful hue, for the label strip that sits on it: the strip belongs to the tile.
static func hue_tint(pic: Texture2D) -> Color:
	var img := pic.get_image()
	img.convert(Image.FORMAT_RGBA8)
	img.resize(8, 6, Image.INTERPOLATE_LANCZOS)
	var best := Color.WHITE
	var best_score := -1.0
	for y in img.get_height():
		for x in img.get_width():
			var px := img.get_pixel(x, y)
			var score := px.s * px.v
			if score > best_score:
				best_score = score
				best = px
	return Color.from_hsv(best.h, 0.6, 1.0)

## BA's facet plate under a label: a flat rounded plate in tint (lightened to a pastel), with the facet card's triangles
## multiplied over it as slightly darker tones. The whole thing leans with `shear` like the tile it sits on.
static func strip(ci: CanvasItem, rect: Rect2, tint: Color, shear: float) -> void:
	var base := tint.lerp(Color.WHITE, 0.4)
	Menu.nine(ci, "Common__Common_Nonoutline_W_Bg", rect, Menu.K, base, shear)
	var facets := _facets()
	if facets == null:
		return
	var h := minf(FACET_H, float(FACET_W) * rect.size.y / rect.size.x)
	ci.draw_set_transform_matrix(BaArt.lean_xform(shear, rect.get_center().y))
	ci.draw_texture_rect_region(facets, rect.grow(-2.0), Rect2(0.0, (FACET_H - h) * 0.5, FACET_W, h), base)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)

## The opaque middle of Combat_CardBg_EX (x 31..216, y 30..170 of the sprite) as a white texture whose lightest triangle is
## 1.0 and the darkest about 0.75, so tinting it gives a plate colour with its own darker tones.
static func _facets() -> Texture2D:
	if _facet_tex == null:
		var src := BaArt.tex("Combat__Combat_CardBg_EX")
		if src == null:
			return null
		var img := src.get_image()
		img.convert(Image.FORMAT_RGBA8)
		var out := Image.create(FACET_W, int(FACET_H), false, Image.FORMAT_RGBA8)
		for y in int(FACET_H):
			for x in FACET_W:
				var g := minf(img.get_pixel(31 + x, 30 + y).r / FACET_MAX, 1.0)
				out.set_pixel(x, y, Color(g, g, g, 1.0))
		_facet_tex = ImageTexture.create_from_image(out)
	return _facet_tex
