class_name SlamWipe
extends Control
## The fast "slam" wipe (~0.5 s): a slab leaning like every BA plate (white leading edge, accent stripe, navy body, accent +
## white trailing stripes) slashes across the screen, covers it for a few frames (on_cover() is called there) and
## carries on to reveal the new screen. Used for the fight intro: `await Game.transition.play("slam", {}, cb)`.
## opts: {"color": Color accent, "dir": 1.0 (left->right) | -1.0, "speed": 1.0 (<1 = slow motion, for tests)}

signal done

const T_END := 0.56
const SLANT := BaTokens.SHEAR
const WIDTH := 2100.0
const U_MIN := -140.0
const U_MAX := 1280.0

var accent := BaTokens.SLAM_ACCENT
var dir := 1.0
var speed := 1.0
var _t := 0.0
var _running := false
var _covered := false
var _flash := 0.0
var _on_cover: Callable
var _lines: Array = []

func run(on_cover: Callable, opts := {}) -> void:
	_on_cover = on_cover
	accent = opts.get("color", accent)
	dir = -1.0 if float(opts.get("dir", 1.0)) < 0.0 else 1.0
	speed = maxf(0.05, float(opts.get("speed", 1.0)))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 14:
		_lines.append({"off": rng.randf_range(0.05, 0.95), "len": rng.randf_range(120.0, 420.0), "w": rng.randf_range(1.5, 4.0), "a": rng.randf_range(0.15, 0.45)})
	_running = true
	Sfx.play("whoosh", 1.25, 1.0)
	await done

static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 4.0 * x * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0

func _process(delta: float) -> void:
	if not _running:
		return
	_t += minf(delta, 0.05) * speed
	_flash = maxf(0.0, _flash - delta * 6.0 * speed)
	var b := _lead()
	if not _covered and b >= U_MAX + 220.0:
		_covered = true
		_flash = 1.0
		Sfx.play("slam")
		if _on_cover.is_valid():
			_on_cover.call()
	queue_redraw()
	if _t >= T_END:
		_running = false
		done.emit()

func _lead() -> float:
	var span := (U_MAX + WIDTH) - U_MIN
	return U_MIN + span * _ease(_t / T_END)

func _band(lo: float, hi: float, col: Color) -> void:
	var y0 := -20.0
	var y1 := 740.0
	var pts := PackedVector2Array([
		Vector2(lo + SLANT * y0, y0), Vector2(hi + SLANT * y0, y0),
		Vector2(hi + SLANT * y1, y1), Vector2(lo + SLANT * y1, y1),
	])
	if dir < 0.0:
		for i in pts.size():
			pts[i].x = 1280.0 - pts[i].x
		pts.reverse()
	draw_colored_polygon(pts, col)

func _draw() -> void:
	if not _running:
		return
	var b := _lead()
	var a := b - WIDTH
	var navy := Color(0.03, 0.07, 0.17)
	_band(a, b, navy)
	# speed lines inside the body
	for l in _lines:
		var u: float = lerpf(a + 260.0, b - 260.0, l["off"])
		var y0 := 40.0 + float(l["off"]) * 560.0
		var p0 := Vector2(u + SLANT * y0, y0)
		var p1 := p0 + Vector2(float(l["len"]) * 0.9, 0.0)
		if dir < 0.0:
			p0.x = 1280.0 - p0.x
			p1.x = 1280.0 - p1.x
		draw_line(p0, p1, Color(accent.r, accent.g, accent.b, l["a"]), l["w"], true)
	_band(b - 230.0, b - 70.0, accent)
	_band(b - 70.0, b, Color.WHITE)
	_band(a + 70.0, a + 230.0, accent)
	_band(a, a + 70.0, Color.WHITE)
	if _flash > 0.01:
		draw_rect(Rect2(0, 0, 1280, 720), Color(1, 1, 1, FxFlash.flash(_flash * 0.45)))
