class_name CrestEmblem
extends Control
## The big emblem of a crest wipe, drawn procedurally in 1280×720 reference pixels.
## It lives inside a SubViewport (see crest_wipe.gd) that is drawn at VP× resolution; the glow is added
## by shaders/crest_glow.gdshader. CrestWipe animates the public fields every frame:
##   kind   "red" (three rings + spinning cube) | "gold" (winged spiked halo) | "sakura" (petals in a circle)
##   t      seconds since the emblem appeared (spins, bobs, spinner)
##   enter  0..1 draw-in progress          pop  spring 0..~1.15 (scale / stagger overshoot)
##   zoom   extra camera push-in (1 = rest), multiplies everything

const VP := 1.5
const CENTER := Vector2(640, 360)

const RED := Color(0.91, 0.26, 0.34)
const MAROON := Color(0.17, 0.02, 0.05, 0.95)
const GOLD_HI := Color(1.0, 0.93, 0.66)
const GOLD := Color(0.98, 0.78, 0.29)
const GOLD_LO := Color(0.9, 0.6, 0.17)
const PINK := Color(0.95, 0.56, 0.83)
const PINK_HI := Color(0.99, 0.68, 0.9)
const PINK_LO := Color(0.9, 0.42, 0.73)

static var _petal: PackedVector2Array

var kind := "red"
var t := 0.0
var enter := 1.0
var pop := 1.0
var zoom := 1.0

func _init() -> void:
	size = Vector2(1280, 720)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

# helpers
## Set the draw transform: reference px → viewport px (VP×), then centre/rotation/scale.
func _xf(center: Vector2, rot: float, scl: Vector2) -> void:
	draw_set_transform_matrix(Transform2D(0.0, Vector2(VP, VP), 0.0, Vector2.ZERO) * Transform2D(rot, scl, 0.0, center))

static func _chaikin(pts: PackedVector2Array, rounds: int) -> PackedVector2Array:
	var cur := pts
	for _r in rounds:
		var nxt := PackedVector2Array()
		for i in cur.size():
			var a := cur[i]
			var b := cur[(i + 1) % cur.size()]
			nxt.append(a.lerp(b, 0.25))
			nxt.append(a.lerp(b, 0.75))
		cur = nxt
	return cur

static func _ease_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)

func _draw() -> void:
	match kind:
		"gold": _draw_gold()
		"sakura": _draw_sakura()
		_: _draw_red()

# red: three double rings on a tilted disc + spinning cube
func _draw_red() -> void:
	var sc := lerpf(0.35, 1.0, minf(pop, 1.25)) * zoom
	var c := CENTER + Vector2(-8, 0)
	var squash := 0.62
	var theta := (1.0 - _ease_out(enter)) * -2.4 + t * 0.55
	# big thin ring (draws itself in), thicker at the sides like a tilted disc
	_xf(c, 0.0, Vector2(sc, sc * squash))
	var sweep := TAU * _ease_out(enter * 1.15)
	draw_arc(Vector2.ZERO, 215.0, -PI * 0.5 + theta, -PI * 0.5 + theta + sweep, 120, RED, 15.0, true)
	draw_arc(Vector2.ZERO, 215.0, -PI * 0.5 + theta, -PI * 0.5 + theta + sweep, 120, Color(1, 0.62, 0.68, 0.45), 4.0, true)
	# three double rings at the corners of a triangle
	for k in 3:
		var a := theta + TAU * float(k) / 3.0
		var plan := Vector2(cos(a), sin(a)) * 210.0
		var ks := clampf(UI.spring(maxf(0.0, t - 0.06 * k) * 1.5, 7.0, 10.0), 0.0, 1.3)
		var rc := c + Vector2(plan.x, plan.y * squash) * sc
		_xf(rc, 0.0, Vector2(sc * ks, sc * ks * squash))
		draw_circle(Vector2.ZERO, 100.0, MAROON)
		draw_circle(Vector2.ZERO, 64.0, Color(0, 0, 0, 1))
		draw_arc(Vector2.ZERO, 100.0, 0.0, TAU, 72, RED, 10.0, true)
		draw_arc(Vector2.ZERO, 66.0, 0.0, TAU, 72, RED, 7.0, true)
		draw_arc(Vector2.ZERO, 100.0, PI * 1.05, PI * 1.55, 24, Color(1, 0.7, 0.75, 0.55), 3.0, true)
	# cube
	var cs := clampf(UI.spring(maxf(0.0, t - 0.1) * 1.4, 6.0, 10.0), 0.0, 1.3)
	_xf(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_cube(c + Vector2(10, -38 + sin(t * 2.3) * 5.0) * sc, 54.0 * sc * cs, t * 2.2 + (1.0 - enter) * 3.0)

func _draw_cube(c: Vector2, s: float, spin: float) -> void:
	if s < 1.0:
		return
	var q := Quaternion(Vector3(1, 1, 1).normalized(), Vector3(0, -1, 0))
	var b := Basis(Vector3.RIGHT, 0.5) * Basis(Vector3.UP, spin) * Basis(q)
	var verts: Array[Vector3] = []
	for i in 8:
		verts.append(b * Vector3(float(i & 1) * 2.0 - 1.0, float((i >> 1) & 1) * 2.0 - 1.0, float((i >> 2) & 1) * 2.0 - 1.0))
	var faces := [[1, 3, 7, 5], [0, 4, 6, 2], [2, 6, 7, 3], [0, 1, 5, 4], [4, 5, 7, 6], [0, 2, 3, 1]]
	var normals := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	var low := 0
	for i in 8:
		if verts[i].y < verts[low].y:
			low = i
	var light := Vector3(-0.35, 0.85, 0.5).normalized()
	var base := Color(0.36, 0.43, 0.56)
	for f in 6:
		var n: Vector3 = b * normals[f]
		if n.z <= 0.0:
			continue
		var pts := PackedVector2Array()
		for vi in faces[f]:
			var v: Vector3 = verts[vi]
			pts.append(c + Vector2(v.x, -v.y) * s)
		var k := clampf(0.58 + 0.62 * maxf(0.0, n.dot(light)), 0.0, 1.35)
		var col := Color(base.r * k, base.g * k, base.b * k, 1.0)
		draw_colored_polygon(pts, col)
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, Color(0.27, 0.32, 0.45, 0.9), 1.6, true)
		# the red corner pointing down
		var idx: int = (faces[f] as Array).find(low)
		if idx >= 0:
			var fl: Array = faces[f]
			var pl: Vector2 = pts[idx]
			var pa: Vector2 = pts[(idx + 1) % 4]
			var pb: Vector2 = pts[(idx + 3) % 4]
			var tip := PackedVector2Array([pl, pl.lerp(pa, 0.42), pl.lerp(pb, 0.42)])
			draw_colored_polygon(tip, Color(0.95, 0.27, 0.38).lerp(Color(0.6, 0.1, 0.2), 1.0 - minf(k, 1.0)))

# gold: winged halo with radiating spikes
func _draw_gold() -> void:
	var base_sc := 0.97
	var sc := lerpf(0.22, base_sc, minf(pop, 1.2)) * zoom
	var e := _ease_out(enter)
	# wings first (behind the ring), they slide out of the ring
	for side in [-1.0, 1.0]:
		var ws := clampf(UI.spring(maxf(0.0, t - 0.08) * 1.3, 6.0, 9.0), 0.0, 1.25)
		_xf(CENTER + Vector2(side * (1.0 - ws) * -60.0, 0.0), 0.0, Vector2(sc * side, sc))
		_draw_wing(ws)
	# spikes (spin in)
	var spin := (1.0 - e) * -1.3 + sin(t * 1.2) * 0.012
	for j in 12:
		var phi := deg_to_rad(15.0 + 30.0 * j) + spin
		var long := (j % 3) == 1
		var js := clampf(UI.spring(maxf(0.0, t - 0.02 * j) * 1.4, 7.0, 10.0), 0.0, 1.3)
		var rc := 335.0
		_xf(CENTER + Vector2(cos(phi), sin(phi)) * rc * sc, phi, Vector2(sc * js, sc * js))
		var lin := 123.0 if long else 85.0
		var lout := 181.0 if long else 113.0
		var w := 46.0 if long else 34.0
		_draw_spike(lin, lout, w)
	# ring
	_xf(CENTER, 0.0, Vector2(sc, sc))
	var sweep := TAU * minf(1.0, e * 1.1)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var n := 160
	var a0 := -PI * 0.5
	for i in n + 1:
		var a := a0 + sweep * float(i) / float(n)
		pts.append(Vector2(cos(a), sin(a)) * 334.0)
		var b := 0.5 + 0.5 * cos(a - deg_to_rad(-130.0))
		cols.append(GOLD_LO.lerp(GOLD_HI, pow(b, 1.3)))
	if pts.size() > 2:
		draw_polyline_colors(pts, cols, 36.0, true)
		draw_arc(Vector2.ZERO, 346.0, a0, a0 + sweep, 120, Color(1, 0.97, 0.78, 0.5), 4.0, true)

func _draw_spike(lin: float, lout: float, w: float) -> void:
	var pts := PackedVector2Array([
		Vector2(-lin, 0), Vector2(-lin * 0.24, w * 0.34), Vector2(0, w), Vector2(lout * 0.24, w * 0.34),
		Vector2(lout, 0), Vector2(lout * 0.24, -w * 0.34), Vector2(0, -w), Vector2(-lin * 0.24, -w * 0.34),
	])
	var cols := PackedColorArray([GOLD_HI, GOLD, GOLD_LO, GOLD, GOLD_HI, GOLD, GOLD_LO, GOLD])
	draw_polygon(pts, cols)

## Right-hand wing in local space (mirrored with a negative x scale for the left one).
func _draw_wing(_k: float) -> void:
	var top := PackedVector2Array([
		Vector2(318, -22), Vector2(365, -40), Vector2(412, -62), Vector2(458, -78), Vector2(500, -82),
		Vector2(560, -72), Vector2(630, -50), Vector2(700, -26), Vector2(760, -6),
	])
	var poly := PackedVector2Array(top)
	poly.append(Vector2(770, 4))
	# scalloped lower edge, tip -> root
	var bumps := [700.0, 640.0, 580.0, 520.0, 460.0, 400.0]
	for cx in bumps:
		var yb := lerpf(30.0, 4.0, (cx - 340.0) / 420.0)
		for i in 7:
			var a := PI * float(i) / 6.0
			poly.append(Vector2(cx + cos(a) * 30.0, yb + sin(a) * 26.0))
	poly.append(Vector2(340, 34))
	var cols := PackedColorArray()
	for p in poly:
		var k := clampf((p.y + 80.0) / 130.0, 0.0, 1.0)
		cols.append(Color(1.0, 0.88, 0.5).lerp(Color(0.97, 0.74, 0.27), pow(k, 0.9)))
	var tri := Geometry2D.triangulate_polygon(poly)
	if tri.size() >= 3:
		draw_polygon(poly, cols)
	else:
		draw_colored_polygon(poly, GOLD)
	draw_polyline(top, Color(1, 0.96, 0.75, 0.75), 3.5, true)

# sakura: five petals inside a ring, with a loading spinner
static func petal() -> PackedVector2Array:
	if _petal.is_empty():
		var up := PackedVector2Array([Vector2(66, 0), Vector2(120, 26), Vector2(190, 66), Vector2(270, 106), Vector2(340, 136),
			Vector2(400, 150), Vector2(455, 150), Vector2(492, 134), Vector2(503, 110), Vector2(500, 70), Vector2(496, 36), Vector2(468, 0)])
		var pts := PackedVector2Array()
		for p in up:
			pts.append(p)
		for i in range(up.size() - 2, 0, -1):
			pts.append(Vector2(up[i].x, -up[i].y))
		_petal = _chaikin(pts, 3)
	return _petal

## A thick closed stroke with clean joins: butt segments + a disc on every vertex.
func _stroke_loop(pts: PackedVector2Array, width: float, col: Color) -> void:
	var n := pts.size()
	for i in n:
		draw_line(pts[i], pts[(i + 1) % n], col, width, false)
	for i in n:
		draw_circle(pts[i], width * 0.5, col)

func _draw_sakura() -> void:
	var sc := lerpf(0.3, 1.0, minf(pop, 1.2)) * zoom
	var e := _ease_out(enter)
	var rot := (1.0 - e) * -1.3 + t * 0.07
	_xf(CENTER, 0.0, Vector2(sc, sc))
	var sweep := TAU * minf(1.0, e * 1.1)
	var ring_pts := PackedVector2Array()
	var ring_cols := PackedColorArray()
	for i in 129:
		var a := -PI * 0.5 + sweep * float(i) / 128.0
		ring_pts.append(Vector2(cos(a), sin(a)) * 578.0)
		ring_cols.append(PINK_LO.lerp(PINK_HI, 0.5 + 0.5 * sin(a - 0.4)))
	if ring_pts.size() > 2:
		draw_polyline_colors(ring_pts, ring_cols, 66.0, true)
	var pet := petal()
	for k in 5:
		var ks := clampf(UI.spring(maxf(0.0, t - 0.05 * k) * 1.4, 6.5, 9.5), 0.0, 1.3)
		var a := rot - PI * 0.5 + TAU * float(k) / 5.0
		_xf(CENTER, a, Vector2(sc * ks, sc * ks))
		_stroke_loop(pet, 56.0, PINK.lerp(PINK_HI, float(k) / 8.0))
	# loading spinner in the middle
	_xf(CENTER, 0.0, Vector2(sc, sc))
	var spin_in := clampf((t - 0.15) * 4.0, 0.0, 1.0)
	draw_circle(Vector2.ZERO, 31.0, Color(0, 0, 0, 0.9 * spin_in))
	draw_arc(Vector2.ZERO, 27.0, 0.0, TAU, 40, Color(0.85, 0.78, 0.92, 0.35 * spin_in), 5.0, true)
	var sa := t * 5.0
	draw_arc(Vector2.ZERO, 27.0, sa, sa + PI * 0.7, 20, Color(0.93, 0.88, 0.97, spin_in), 7.0, true)
