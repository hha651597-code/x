class_name Fx
extends Node2D
## Short-lived visual effects (animated in real time so hit-stop still shows them). The sprite kinds (FxKinds, FxKindsB2) are BA's
## own textures: sparks, muzzles, rings, blocks, damage numbers, dust, sparkles, heals, explosions, KO bursts, melee swings and
## the impact frame. Sight lines, charge orbs, speed lines and flares are still drawn here.
## Also hosts the shared draw helpers (soft glow texture, tapered shards, 4-point stars, hexagons).

var kind := ""
var age := 0.0
var life := 0.3
var color := Color.WHITE
var size := 1.0
var dir := 1
var text := ""
var seed_v := 0.0
var data := {}
var parts: Array = []     # the Sprite2D layers of a sprite-based kind (see FxKinds)

static var _t_glow: Texture2D
static var _t_bubble: Texture2D

static func make(parent: Node, fx_kind: String, pos: Vector2, fx_life: float, opts := {}) -> Fx:
	var f := Fx.new()
	f.kind = fx_kind
	f.position = pos
	f.life = maxf(fx_life, 0.001)
	f.color = opts.get("color", Color.WHITE)
	f.size = opts.get("size", 1.0)
	f.dir = opts.get("dir", 1)
	f.text = opts.get("text", "")
	f.seed_v = opts.get("seed", 0.0)
	f.data = opts
	f.z_index = opts.get("z", 30)
	parent.add_child(f)
	return f

func _ready() -> void:
	if kind in FxKinds.KINDS:
		FxKinds.build(self)
		if not parts.is_empty():
			FxKinds.update(self, 0.0)      # no frame with unmodulated layers

func _process(delta: float) -> void:
	age += delta
	if age >= life:
		queue_free()
		return
	if data.has("follow"):
		var fo = data["follow"]
		if is_instance_valid(fo):
			position = fo.position + Vector2(data.get("foff", Vector2.ZERO))
	queue_redraw()
	if not parts.is_empty():
		FxKinds.update(self, clampf(age / life, 0.0, 1.0))

# shared helpers
## Soft white radial blob (alpha 1 in the centre, 0 at the rim). Tint with the draw colour.
static func glow_tex() -> Texture2D:
	if _t_glow == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.22, 0.5, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0.16), Color(1, 1, 1, 0.0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		_t_glow = t
	return _t_glow

## Bubble: transparent centre, soft bright rim (shield domes, auras).
static func bubble_tex() -> Texture2D:
	if _t_bubble == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.55, 0.82, 0.94, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.38), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 192
		t.height = 192
		_t_bubble = t
	return _t_bubble

## Deterministic pseudo-random 0..1.
static func h(i: float, s: float) -> float:
	return fposmod(sin(i * 12.9898 + s * 78.233) * 43758.5453, 1.0)

## Holds `k` (0..1) on one of `n` poses and returns its index 0..n-1, so a shape changes in steps instead of smoothly.
static func pose(k: float, n: int) -> int:
	return clampi(int(k * float(n)), 0, n - 1)

static func glow(ci: CanvasItem, p: Vector2, r: float, c: Color) -> void:
	if r <= 0.5 or c.a <= 0.003:
		return
	ci.draw_texture_rect(glow_tex(), Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, c)

static func bubble(ci: CanvasItem, p: Vector2, r: float, c: Color) -> void:
	ci.draw_texture_rect(bubble_tex(), Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, c)

## Tapered spike: wide base at distance l0 from p, point at l1 (direction `ang`).
static func shard(ci: CanvasItem, p: Vector2, ang: float, l0: float, l1: float, w: float, c: Color) -> void:
	if c.a <= 0.003 or absf(l1 - l0) < 0.5:
		return
	var d := Vector2.from_angle(ang)
	var n := Vector2(-d.y, d.x) * w * 0.5
	ci.draw_colored_polygon(PackedVector2Array([p + d * l0 + n, p + d * l1, p + d * l0 - n]), c)

## Gradient quad from `a` (width wa, colour ca) to `b` (width wb, colour cb): bullet tails, beams, trails.
static func ribbon(ci: CanvasItem, a: Vector2, b: Vector2, wa: float, wb: float, ca: Color, cb: Color) -> void:
	var d := b - a
	if d.length_squared() < 0.01:
		return
	var n := Vector2(-d.y, d.x).normalized()
	ci.draw_polygon(PackedVector2Array([a + n * wa * 0.5, b + n * wb * 0.5, b - n * wb * 0.5, a - n * wa * 0.5]),
		PackedColorArray([ca, cb, cb, ca]))

## 4-point sparkle (concave). `fat` is the waist ratio.
static func star4(ci: CanvasItem, p: Vector2, r: float, c: Color, rot := 0.0, fat := 0.16) -> void:
	if r <= 0.5 or c.a <= 0.003:
		return
	var pts := PackedVector2Array()
	for i in 8:
		var a := rot + PI * 0.25 * float(i)
		var rr := r if i % 2 == 0 else r * fat
		pts.append(p + Vector2(cos(a), sin(a)) * rr)
	ci.draw_colored_polygon(pts, c)

static func hexagon(ci: CanvasItem, p: Vector2, r: float, c: Color, width := 3.0, rot := 0.0, fill := 0.0) -> void:
	if r <= 0.5 or c.a <= 0.003:
		return
	var pts := PackedVector2Array()
	for i in 7:
		var a := rot + PI / 3.0 * float(i)
		pts.append(p + Vector2(cos(a), sin(a)) * r)
	if fill > 0.0:
		ci.draw_colored_polygon(pts.slice(0, 6), Color(c.r, c.g, c.b, c.a * fill))
	ci.draw_polyline(pts, c, width, true)

# drawing
func _draw() -> void:
	var k := clampf(age / life, 0.0, 1.0)
	match kind:
		"text": _d_text(k)
		"sight": _d_sight(k)
		"charge": _d_charge(k)
		"speed": _d_speed(k)
		"flare": _d_flare(k)
		"swish", "slash": FxKindsB2.draw_swish(self, k)
		"impact": _d_impact()

func _d_text(k: float) -> void:
	if not parts.is_empty():
		return                                  # numerals are sprites (FxKinds)
	var pop := 1.0 + 0.35 * maxf(0.0, 1.0 - k * 8.0)
	var rise := -40.0 * Motion.whip(age, 0.12, 0.6)
	var a := 1.0 if k < 0.6 else (1.0 - k) / 0.4
	var s := int(round(float(data.get("fsize", 34)) * pop))
	var p2 := Vector2(-150.0, rise)
	var font := UI.font_display()
	draw_string_outline(font, p2, text, HORIZONTAL_ALIGNMENT_CENTER, 300, s, 8, BaTokens.alpha(BaTokens.NUM_OUTLINE, a))
	draw_string(font, p2, text, HORIZONTAL_ALIGNMENT_CENTER, 300, s, Color(color.r, color.g, color.b, a))

func _d_sight(_k: float) -> void:
	var d2 := float(dir)
	var pulse := 1.0 if FxFlash.reduced() else 0.5 + 0.5 * sin(age * 70.0)
	var cc := Color(1, 0.22, 0.22)
	ribbon(self, Vector2.ZERO, Vector2(1500.0 * d2, 0), 3.0, 1.0, Color(cc.r, cc.g, cc.b, 0.85 * (0.55 + 0.45 * pulse)), Color(cc.r, cc.g, cc.b, 0.0))
	ribbon(self, Vector2.ZERO, Vector2(1500.0 * d2, 0), 9.0, 3.0, Color(cc.r, cc.g, cc.b, 0.18), Color(cc.r, cc.g, cc.b, 0.0))
	glow(self, Vector2.ZERO, 16.0 + 6.0 * pulse, Color(1, 0.4, 0.4, 0.8))
	star4(self, Vector2.ZERO, 12.0 + 6.0 * pulse, Color(1, 1, 1, 0.9), 0.0, 0.14)

func _d_charge(k: float) -> void:
	var inv := 1.0 - k
	var c := color
	var rr := 8.0 + 30.0 * k
	glow(self, Vector2.ZERO, rr * 2.4, Color(c.r, c.g, c.b, 0.45 + 0.3 * k))
	glow(self, Vector2.ZERO, rr * 1.2, Color(1, 1, 1, 0.85))
	for i in 12:
		var a := TAU * float(i) / 12.0 + seed_v + k * 2.0
		var dist := (86.0 + 30.0 * h(float(i), 4.0)) * inv * inv + 6.0
		var p := Vector2.from_angle(a) * dist
		var tail := Vector2.from_angle(a) * (dist + 26.0 * inv)
		ribbon(self, tail, p, 1.0, 5.0 * k + 1.5, Color(c.r, c.g, c.b, 0.0), Color(1, 1, 1, 0.9 * k + 0.1))
	draw_arc(Vector2.ZERO, rr * 1.9, 0.0, TAU, 28, Color(c.r, c.g, c.b, 0.7 * inv + 0.2), 3.0, true)
	star4(self, Vector2.ZERO, rr * 2.6, Color(1, 1, 1, 0.7 * k), k * 3.0, 0.1)

func _d_speed(_k: float) -> void:
	var inv := 1.0 - clampf(age / life, 0.0, 1.0)
	var rnd := RandomNumberGenerator.new()
	rnd.seed = int(seed_v * 1000.0) + 5
	for i in 26:
		var y := rnd.randf_range(-360.0, 360.0)
		var x0 := rnd.randf_range(-660.0, 660.0) + (age * 900.0 * float(dir))
		var ln := rnd.randf_range(120.0, 360.0)
		ribbon(self, Vector2(x0, y), Vector2(x0 - ln * float(dir), y), 3.0, 0.5, Color(1, 1, 1, inv * 0.6), Color(1, 1, 1, 0.0))

## Plain soft flash: glow + ring + optional streaks (data.streaks)
## The ink field of an impact frame (the white burst and lines are FxKindsB2's sprites over it). A hidden node does not draw.
func _d_impact() -> void:
	var half := float(data.get("field", 6000.0))
	draw_rect(Rect2(-half, -half, half * 2.0, half * 2.0), Color(0.03, 0.04, 0.08, 0.9))

func _d_flare(k: float) -> void:
	var inv := 1.0 - k
	var c := color
	glow(self, Vector2.ZERO, 120.0 * size * (1.0 - 0.3 * k), Color(c.r, c.g, c.b, 0.6 * inv))
	glow(self, Vector2.ZERO, 60.0 * size * (1.0 - 0.5 * k), Color(1, 1, 1, inv))
	star4(self, Vector2.ZERO, 130.0 * size * (1.0 - 0.5 * k), Color(1, 1, 1, inv * 0.9), 0.0, 0.1)

# convenience factories used by FightScreen / Fighter
static func spark(parent: Node, pos: Vector2, spark_kind: String, face: int, sd := 0.0) -> void:
	var col := Color(1.0, 0.93, 0.55)
	var sz := 1.0
	var lf := 0.22
	match spark_kind:
		"heavy":
			col = Color(1.0, 0.66, 0.22)
			sz = 1.6
			lf = 0.32
		"ex":
			col = Color(0.62, 0.93, 1.0)
			sz = 2.5
			lf = 0.46
		"block":
			make(parent, "block", pos, 0.3, {"dir": face})
			return
	make(parent, "spark", pos, lf, {"color": col, "size": sz, "seed": sd, "dir": face})
	if spark_kind != "light":
		# one under the star's z of 30: the shockwave leaves from the star's edge and stays behind it
		make(parent, "ring", pos, 0.3 if spark_kind == "heavy" else 0.42, {"color": col, "size": FxKinds.ring_size_for_star(sz), "z": 29})
