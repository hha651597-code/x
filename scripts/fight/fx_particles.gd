class_name FxParticles
extends Node2D
## Pooled world-space particles drawn in one node: brass casings, sparks, soft motes, twinkling stars, dust puffs. Stars and puffs
## are BA's own textures (FxArt "star4" and "puff", both with real alpha, so a plain texture draw does) held on a few poses;
## motes are still a soft glow.
## One instance per FightScreen (child "Particles" of the fx layer); fetch it with FxParticles.of(layer).

enum K { CASING, SPARK, MOTE, STAR, PUFF }
const MAXP := 260

class P:
	var k := 0
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var life := 0.5
	var age := 0.0
	var size := 4.0
	var col := Color.WHITE
	var grav := 0.0
	var drag := 0.0
	var rot := 0.0
	var spin := 0.0
	var rest := false
	var ground := 0.0
	var frame := 0

var _ps: Array = []

static func of(layer: Node) -> FxParticles:
	var n := layer.get_node_or_null("Particles")
	if n == null:
		n = FxParticles.new()
		n.name = "Particles"
		n.z_index = 1
		layer.add_child(n)
	return n as FxParticles

func emit(kind: int, pos: Vector2, vel: Vector2, life: float, size: float, col: Color, grav := 0.0, drag := 0.0, spin := 0.0, rot := 0.0) -> void:
	if _ps.size() >= MAXP:
		_ps.remove_at(0)
	var p := P.new()
	p.k = kind
	p.pos = pos
	p.vel = vel
	p.life = life
	p.size = size
	p.col = col
	p.grav = grav
	p.drag = drag
	p.spin = spin
	p.rot = rot
	p.frame = int(Fx.h(pos.x, pos.y) * 4.0) % 4
	p.ground = Arena.GROUND - 3.0
	_ps.append(p)

## Brass shell ejected from `pos`, flying backwards (-dir) and up, bouncing on the floor.
func casing(pos: Vector2, dir: int, strength := 1.0, col := Color(1.0, 0.82, 0.38)) -> void:
	emit(K.CASING, pos, Vector2(-float(dir) * (90.0 + 120.0 * randf_fixed()) * strength, -(240.0 + 150.0 * randf_fixed())),
		0.9, 1.0, col, 1500.0, 0.0, (randf_fixed() - 0.5) * 40.0, randf_fixed() * TAU)

var _seed := 1.0
func randf_fixed() -> float:
	_seed += 1.0
	return Fx.h(_seed, 3.7)

func _process(delta: float) -> void:
	if _ps.is_empty():
		return
	var dt := minf(delta, 0.05)
	var i := 0
	while i < _ps.size():
		var p: P = _ps[i]
		p.age += dt
		if p.age >= p.life:
			_ps[i] = _ps[_ps.size() - 1]
			_ps.pop_back()
			continue
		if not p.rest:
			p.vel.y += p.grav * dt
			if p.drag > 0.0:
				p.vel *= maxf(0.0, 1.0 - p.drag * dt)
			p.pos += p.vel * dt
			p.rot += p.spin * dt
			if p.k == K.CASING and p.pos.y >= p.ground and p.vel.y > 0.0:
				p.pos.y = p.ground
				p.vel.y = -p.vel.y * 0.35
				p.vel.x *= 0.6
				p.spin *= 0.5
				if absf(p.vel.y) < 40.0:
					p.rest = true
					p.age = maxf(p.age, p.life - 0.35)
		i += 1
	queue_redraw()

func _draw() -> void:
	for p: P in _ps:
		var t := p.age / p.life
		var inv := 1.0 - t
		match p.k:
			K.CASING:
				var a := minf(1.0, inv * 3.0)
				draw_set_transform(p.pos, p.rot, Vector2.ONE)
				draw_rect(Rect2(-4.5, -2.0, 9.0, 4.0), Color(p.col.r, p.col.g, p.col.b, a))
				draw_rect(Rect2(-4.5, -2.0, 3.0, 4.0), Color(1, 1, 0.85, a))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			K.SPARK:
				var tail := p.pos - p.vel * 0.03
				Fx.ribbon(self, tail, p.pos, 0.5, p.size * inv + 0.8, Color(p.col.r, p.col.g, p.col.b, 0.0), Color(p.col.r, p.col.g, p.col.b, inv))
				draw_circle(p.pos, p.size * 0.45 * inv + 0.6, Color(1, 1, 1, inv))
			K.MOTE:
				var tw := sin(t * PI)
				Fx.glow(self, p.pos, p.size * (0.7 + 0.5 * tw), Color(p.col.r, p.col.g, p.col.b, 0.7 * tw))
				draw_circle(p.pos, p.size * 0.18 * tw + 0.4, Color(1, 1, 1, 0.8 * tw))
			K.STAR:
				var sc: float = [0.3, 1.0, 0.65, 0.3][Fx.pose(t, 4)]
				_star(p.pos, p.size * sc, p.rot, p.col)
			K.PUFF:
				var r: float = p.size * 1.3 * [0.5, 1.0, 1.0, 0.7, 0.4][Fx.pose(t, 5)]
				var fr := FxArt.frame_size("puff")
				var tex := FxArt.tex("puff")
				if tex != null:
					draw_texture_rect_region(tex, Rect2(p.pos - Vector2(r, r), Vector2(r, r) * 2.0),
						Rect2(Vector2(float(p.frame % 2), float(p.frame / 2)) * fr, fr), Color(p.col.r, p.col.g, p.col.b, 1.0))

## A twinkle: BA's four-point flare in the colour on a darker rim a third larger, and the same star on top in white.
func _star(pos: Vector2, r: float, rot: float, col: Color) -> void:
	var tex := FxArt.tex("star4")
	if tex == null or r < 0.5:
		return
	var dark := Color(col.r * 0.45, col.g * 0.5, col.b * 0.6, 1.0)
	draw_set_transform(pos, rot, Vector2.ONE)
	draw_texture_rect(tex, Rect2(Vector2(-r, -r) * 1.9, Vector2(r, r) * 3.8), false, dark)
	draw_texture_rect(tex, Rect2(Vector2(-r, -r) * 1.5, Vector2(r, r) * 3.0), false, Color(col.r, col.g, col.b, 1.0))
	draw_texture_rect(tex, Rect2(Vector2(-r, -r), Vector2(r, r) * 2.0), false, Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
