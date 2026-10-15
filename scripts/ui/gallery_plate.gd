class_name GalleryPlate
extends Control
## The art stage of Extras > Characters: BA's leaned facet card (Card_Item_Bg_N) in the school's tint with a halo ring behind the head, and the
## student's art standing on it. Fighters' art rises above the card's top edge like the portrait cards in BA's lists; it is cut at
## the card's slanted sides and bottom. `show_art()` swaps the picture with a slide and a short ghost of the old one.

const RING := "UIs__00_Images__Image_Deco_Circle"
const SWAP_T := 0.34
## The art's window inside the card sprite, in the sprite's own 256x210 pixels: inside the rim, following the 10 degree lean
const SRC := Vector2(256.0, 210.0)
const TOP_L := 43.0
const TOP_R := 248.0
const BOT_L := 8.0
const BOT_R := 212.0
const TOP_Y := 8.0
const BOT_Y := 198.0

var plate := Rect2()               # where the facet sprite is drawn, in this control's pixels
var overflow := 0.0                # how far the art may rise above the card
var halo := Vector2.ZERO           # centre of the ring behind the head
var halo_px := 0.0
var tint := Color.WHITE
var _cur := {}
var _old := {}
var _swap := 1.0
var _dir := 1.0
var _flash := 0.0

func setup(size_px: Vector2) -> GalleryPlate:
	size = size_px
	custom_minimum_size = size_px
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	return self

func set_plate(r: Rect2, rise: float) -> void:
	plate = r
	overflow = rise
	queue_redraw()

func set_scheme(c: Color) -> void:
	tint = c
	queue_redraw()

func set_halo(at: Vector2, diameter: float) -> void:
	halo = at
	halo_px = diameter

## Show `tex` in `rect` (control pixels). `dir` = +1 slides in from the right, -1 from the left.
func show_art(tex: Texture2D, rect: Rect2, dir := 1.0, animate := true) -> void:
	if animate and not _cur.is_empty():
		_old = _cur
		_swap = 0.0
	else:
		_old = {}
		_swap = 1.0
	_dir = dir
	_cur = {"tex": tex, "rect": rect}
	queue_redraw()

func pulse() -> void:
	_flash = 1.0

func _process(delta: float) -> void:
	if _swap < 1.0 or _flash > 0.0:
		_swap = minf(_swap + delta / SWAP_T, 1.0)
		_flash = move_toward(_flash, 0.0, delta * 3.2)
		queue_redraw()

## The card's opaque outline, TL TR BR BL.
func card_polygon() -> PackedVector2Array:
	var k := plate.size / SRC
	var p := plate.position
	return PackedVector2Array([p + Vector2(TOP_L, TOP_Y) * k, p + Vector2(TOP_R, TOP_Y) * k, p + Vector2(BOT_R, BOT_Y) * k, p + Vector2(BOT_L, BOT_Y) * k])

## The region the art may cover: the card plus a box above its top edge that runs on to the plate's right edge, so hair and arms
## that rise above the card are not sliced along its slant (the info popup covers the rest).
func clip_polygon() -> PackedVector2Array:
	var c := card_polygon()
	if overflow <= 0.0:
		return c
	var top := c[0].y - overflow
	return PackedVector2Array([Vector2(c[0].x, top), Vector2(size.x, top), Vector2(size.x, c[0].y), c[1], c[2], c[3], c[0]])

func _draw_art(a: Dictionary, off: Vector2, alpha: float) -> void:
	var tex: Texture2D = a.get("tex")
	if tex == null or alpha <= 0.0:
		return
	var r: Rect2 = a["rect"]
	r.position += off
	var quad := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	for poly in Geometry2D.intersect_polygons(quad, clip_polygon()):
		var uvs := PackedVector2Array()
		for p in poly:
			uvs.append((p - r.position) / r.size)
		draw_colored_polygon(poly, Color(1, 1, 1, alpha), uvs, tex)

func _draw() -> void:
	if plate.size == Vector2.ZERO:
		return
	if halo_px > 0.0:
		BaArt.blit(self, RING, Rect2(halo - Vector2.ONE * halo_px * 0.5, Vector2.ONE * halo_px), Color(1, 1, 1, 0.75))
	GalleryKit.blit(self, GalleryKit.art(GalleryKit.CARD), plate, tint)
	var e := Motion.whip(_swap * SWAP_T, 0.12, 0.22)
	if not _old.is_empty() and _swap < 1.0:
		_draw_art(_old, Vector2(-_dir * e * 36.0, 0.0), 0.7 * (1.0 - clampf(_swap / 0.6, 0.0, 1.0)))
	_draw_art(_cur, Vector2(_dir * (1.0 - e) * 54.0, 0.0), clampf(_swap * 3.2, 0.0, 1.0))
	if _flash > 0.0:
		draw_colored_polygon(card_polygon(), Color(1, 1, 1, _flash * 0.3))
