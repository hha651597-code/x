class_name SelectCursor
extends Control
## A player's frame on the roster grid: BA's Card_Select_Line bracket in the side colour, 4 px, alpha pulsing 1.0 to 0.7 on
## the measured half cycle. No glow and no spring. Locking stops the pulse and flashes the tile white once.
## The screen drives it with snap_to, appear, nudge, lock, unlock, tick and the target and inset fields.

const LINE := "Common__Card_Select_Line"
const K := 0.5
const REACH := Vector2(102.0, 92.0)
const LIFT := Vector2(0.0, -4.0)

static var _white: Texture2D

var slot := 1
var target := Vector2.ZERO          # frame centre, screen px
var inset := 0.0
var locked := false
var _col := Color.WHITE
var _centre := Vector2.ZERO
var _appear := -1.0
var _flash := 0.0
var _clock := 0.0
var _inset := 0.0

func setup(player_slot: int, col: Color) -> void:
	slot = player_slot
	_col = col
	size = REACH
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 2 if slot == 1 else 3
	modulate.a = 0.0

## Card_Select_Line without its orange glow, white so it takes any side colour.
static func white_line() -> Texture2D:
	if _white == null:
		var src := BaArt.tex(LINE)
		if src == null:
			return null
		var img := src.get_image()
		img.convert(Image.FORMAT_RGBA8)
		for y in img.get_height():
			for x in img.get_width():
				var p := img.get_pixel(x, y)
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, p.a * smoothstep(0.45, 0.8, p.g)))
		_white = ImageTexture.create_from_image(img)
	return _white

## The bracket, 9-sliced into rect at K, in tint.
static func paint_line(ci: CanvasItem, rect: Rect2, tint: Color) -> void:
	var t := white_line()
	if t != null:
		BaArt.nine_tex(ci, t, BaArt.info(LINE)["borders"], rect, tint, 0.0, K)

func snap_to(c: Vector2) -> void:
	_centre = c
	target = c
	_place()

func appear() -> void:
	if _appear < 0.0:
		_appear = 0.0

## The cursor moved: the pulse restarts at full alpha so the frame is bright where it lands.
func nudge() -> void:
	_clock = 0.0

func lock() -> void:
	locked = true
	_flash = 1.0

func unlock() -> void:
	locked = false
	_clock = 0.0

func tick(delta: float, _t: float) -> void:
	if _appear < 0.0:
		return
	_appear += delta
	_clock += delta
	_flash = move_toward(_flash, 0.0, delta * 4.0)
	_centre = _centre.lerp(target, 1.0 - exp(-delta * 26.0))
	_inset = lerpf(_inset, inset, 1.0 - exp(-delta * 18.0))
	modulate.a = Motion.whip(_appear, 0.1, 0.15)
	_place()
	queue_redraw()

func _place() -> void:
	size = REACH - Vector2(_inset, _inset) * 2.0
	position = _centre + LIFT - size * 0.5

func pulse() -> float:
	return 1.0 if locked else Motion.pulse(_clock)

func _draw() -> void:
	paint_line(self, Rect2(Vector2.ZERO, size), Color(_col, pulse()))
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size).grow(-5.0), Color(1.0, 1.0, 1.0, _flash * 0.5))
