extends RefCounted
## Drawing helpers for the EX cut-in and the result screen (static; call through a preload). Colours come from BaTokens.

## Extra transform applied under every lean() (the banners tilt their whole slab + text a few degrees).
static var base := Transform2D.IDENTITY

## Slanted polygon with the lean given at the top (positive = top leans right), for full-width slabs.
static func slab(x0: float, x1: float, y: float, h: float, lean: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0 + lean * 0.5, y), Vector2(x1 + lean * 0.5, y), Vector2(x1 - lean * 0.5, y + h), Vector2(x0 - lean * 0.5, y + h)])

static func width(font: Font, s: String, size: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

## Outlined text. anchor: 0 = pos.x is the left edge, 1 = centre, 2 = right edge. pos.y is the baseline.
static func text(c: CanvasItem, font: Font, pos: Vector2, s: String, size: int, fill: Color, outline: Color, ow: int, anchor := 0) -> float:
	var w := width(font, s, size)
	var x := pos.x
	if anchor == 1:
		x -= w * 0.5
	elif anchor == 2:
		x -= w
	if ow > 0 and outline.a > 0.001:
		c.draw_string_outline(font, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ow, outline)
	c.draw_string(font, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, fill)
	return w

## Outlined text that is shrunk (font size) until it fits `max_w`.
static func text_fit(c: CanvasItem, font: Font, pos: Vector2, s: String, size: int, max_w: float, fill: Color, outline: Color, ow: int, anchor := 0) -> void:
	var sz := size
	while sz > 10 and width(font, s, sz) > max_w:
		sz -= 2
	text(c, font, pos, s, sz, fill, outline, ow, anchor)

## Italic lean for everything drawn until unlean(): origin = baseline point, k = shear (0.2 ≈ 11 deg).
static func lean(c: CanvasItem, origin: Vector2, k: float, scale := 1.0) -> void:
	c.draw_set_transform_matrix(base * Transform2D(Vector2(scale, 0), Vector2(-k * scale, scale), origin))

static func unlean(c: CanvasItem) -> void:
	c.draw_set_transform_matrix(base)

## A rotation about `pivot` (for tilting a banner).
static func tilt(pivot: Vector2, angle: float) -> Transform2D:
	var r := Transform2D(angle, Vector2.ZERO)
	r.origin = pivot - r.basis_xform(pivot)
	return r

## A Blue Archive style halo: two flat concentric rings (drawn as ellipses).
static func halo(c: CanvasItem, ctr: Vector2, rx: float, ry: float, col: Color, w: float) -> void:
	c.draw_set_transform_matrix(base * Transform2D(Vector2(1.0, 0.0), Vector2(0.0, ry / rx), ctr))
	c.draw_arc(Vector2.ZERO, rx, 0.0, TAU, 40, col, w, true)
	c.draw_arc(Vector2.ZERO, rx * 0.62, 0.0, TAU, 32, col, maxf(1.0, w * 0.7), true)
	c.draw_set_transform_matrix(base)
