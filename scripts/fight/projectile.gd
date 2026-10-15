class_name Projectile
extends Node2D
## Bullets, pellets, snipes, rockets, grenades, mortar shells, beams, flames and explosion blasts.
## Created by FightScreen.spawn_projectile from a Movesets spawn spec. Ticks at the fixed 60 Hz.

var owner_f: Fighter
var target: Fighter
var hit: Dictionary = {}
var vel := Vector2.ZERO
var gravity := 0.0
var life := 60
var size := Vector2(30, 10)
var kind := "bullet"
var color := Color(1, 0.9, 0.5)
var explode: Dictionary = {}
var facing := 1
var dead := false
var age := 0
var hit_cd := 0
var hits := 0
var world: Node
var homing := 0.0              # steering strength (0..1 per frame) toward the target
var boomerang := 0             # frame at which it turns around and comes back to the owner
var bounces := 0               # floor bounces left
var follow := false            # keeps its offset from the owner (auras, pillars)
var follow_off := Vector2.ZERO
var muzzle_sweep := false # Buckshot: a foe touching the barrel is hit even if the muzzle has passed through them.
var mine: Dictionary = {}      # {arm: frames, radius: px} — lies still, detonates when the foe is close
var speed0 := 0.0
var draw_off := Vector2.ZERO   # presentation only: the gun's true muzzle minus the spawn point, eased out over DRAW_EASE
var draw_along := false        # bullets drawn along their velocity (SD fighters; others keep the flat facing draw)

const DRAW_EASE := 6.0

func rect() -> Rect2:
	match kind:
		"beam":
			if facing >= 0:
				return Rect2(position.x, position.y - size.y * 0.5, size.x, size.y)
			return Rect2(position.x - size.x, position.y - size.y * 0.5, size.x, size.y)
		"blast":
			return Rect2(position - size * 0.5, size)
	return Rect2(position - size * 0.5, size)

func tick() -> void:
	age += 1
	life -= 1
	if hit_cd > 0:
		hit_cd -= 1
	if life <= 0:
		if kind in ["grenade", "shell", "rocket"] and not explode.is_empty():
			_explode()
		dead = true
		return
	vel.y += gravity
	if homing > 0.0 and target != null and speed0 > 0.0:
		var want := (target.hurtbox().get_center() - position).normalized() * speed0
		vel = vel.lerp(want, homing)
	if boomerang > 0 and age >= boomerang and owner_f != null:
		var back := (owner_f.position + Vector2(0, -160.0) - position)
		if back.length() < 46.0:
			dead = true
			return
		vel = vel.lerp(back.normalized() * maxf(speed0, 14.0) * 1.2, 0.18)
		if age == boomerang:
			hit_cd = 0
	if follow and owner_f != null:
		position = owner_f.position + Vector2(follow_off.x * float(owner_f.facing), follow_off.y)
		vel = Vector2.ZERO
	var bounced := false
	if bounces > 0 and position.y >= Arena.GROUND - 6.0 and vel.y > 0.0:
		vel.y = -vel.y * 0.72
		bounces -= 1
		position.y = Arena.GROUND - 6.0
		bounced = true
	if not mine.is_empty():
		vel = Vector2.ZERO
		if age >= int(mine.get("arm", 30)) and target != null:
			if target.hurtbox().get_center().distance_to(position) <= float(mine.get("radius", 90.0)):
				_explode()
				dead = true
				return
		position += vel
		queue_redraw()
		return
	position += vel
	if kind in ["grenade", "shell"] and not bounced and position.y >= Arena.GROUND - 8.0 and age > 2:
		_explode()
		dead = true
		return
	if absf(position.x) > 1700.0 or position.y > Arena.GROUND + 100.0:
		dead = true
		return
	if hit_cd > 0 or target == null or hit.is_empty():
		queue_redraw()
		return
	var hb := target.hurtbox()
	var shot_rect := rect()
	if muzzle_sweep and age == 1 and owner_f != null:
		var origin := position - vel
		var barrel := Rect2(minf(owner_f.position.x, origin.x), origin.y - size.y * 0.5,
			absf(origin.x - owner_f.position.x), size.y)
		shot_rect = shot_rect.merge(barrel)
	if shot_rect.intersects(hb):
		var res := target.receive_hit(owner_f, hit, position, true)
		if res != "miss":
			hits += 1
			if not explode.is_empty() and kind != "blast":
				_explode()
			if kind in ["beam", "flame", "blast"]:
				hit_cd = 10 if kind != "blast" else 99
			elif not bool(hit.get("pierce", false)):
				dead = true
			else:
				hit_cd = 12
			if res == "block":
				owner_f.meter = minf(Arena.MAX_METER, owner_f.meter + 1.0)
	queue_redraw()

func _explode() -> void:
	if explode.is_empty() or kind == "blast":
		return
	world.spawn_blast(owner_f, position, float(explode["radius"]), explode["hit"], color)
	explode = {}

## The kinds drawn from BA's own textures (assets/ba/fx/bullet and the shared sheets). LUM_KINDS use the white-on-black sheets,
## ALPHA_KINDS the ones with real alpha; both add onto the scene. The rest keep their drawn bodies.
const LUM_KINDS := ["bullet", "snipe", "pellet", "beam", "pillar", "wave", "crescent"]
const ALPHA_KINDS := ["orb", "flame", "blast"]
const COMET_HEAD := 0.84        # where the head sits along the tracer_comet sheet
const BEAM_BODY := Rect2(0.4, 0.0, 0.2, 1.0)   # the sheet's flat middle, in uv, so a stretched beam keeps a full-length body

func _ready() -> void:
	if kind in LUM_KINDS:
		material = FxArt.material("add", true, false)
	elif kind in ALPHA_KINDS:
		material = FxArt.material("add", false, false)

## One frame of an FX sheet drawn into rect, in the current transform.
func _blit(sheet: String, rect: Rect2, col: Color, frame := 0) -> void:
	var t := FxArt.tex(sheet)
	if t == null:
		return
	var cols := int(FxArt.SHEETS[sheet]["cols"])
	var fs := FxArt.frame_size(sheet)
	draw_texture_rect_region(t, rect, Rect2(Vector2(frame % cols, frame / cols) * fs, fs), col)

## A beam body of `length` along +x and `thick` across: the sheet's flat middle stretched, so its soft edges stay on the sides.
func _blit_beam(length: float, thick: float, col: Color, centred := false) -> void:
	var t := FxArt.tex("beam_soft")
	if t == null:
		return
	var sz := t.get_size()
	draw_texture_rect_region(t, Rect2(-length * 0.5 if centred else 0.0, -thick * 0.5, length, thick),
		Rect2(BEAM_BODY.position * sz, BEAM_BODY.size * sz), col)

## A tracer: the comet sheet with its head at `head_x` and a white hot core.
func _tracer(head_x: float, length: float, thick: float, col: Color) -> void:
	_blit("tracer_comet", Rect2(head_x - COMET_HEAD * length, -thick * 0.5, length, thick), Color(col.r, col.g, col.b, 0.95))
	_blit("tracer_head", Rect2(head_x - thick * 0.75, -thick * 0.45, thick * 1.1, thick * 0.9), Color(1, 1, 1, 0.9))

func _draw() -> void:
	var fx := float(facing)
	var o := draw_off * clampf(1.0 - float(age) / DRAW_EASE, 0.0, 1.0)
	draw_set_transform(o, 0.0, Vector2.ONE)
	match kind:
		"bullet":
			draw_set_transform(o, vel.angle() if draw_along and vel.length() > 0.1 else (0.0 if facing >= 0 else PI), Vector2.ONE)
			_tracer(size.x * 0.5, size.x * 3.6, size.y * 3.4, color)
		"snipe":
			draw_set_transform(o, 0.0 if facing >= 0 else PI, Vector2.ONE)
			_tracer(size.x * 0.5, size.x * 5.0, size.y * 3.8, color)
		"pellet":
			draw_set_transform(o, vel.angle(), Vector2.ONE)
			_tracer(size.y * 0.3, size.x * 2.4, size.y * 2.4, color)
		"grenade":
			draw_circle(Vector2.ZERO, 14.0, Color(0.15, 0.2, 0.28))
			draw_circle(Vector2(-3, -3), 5.0, color)
			draw_arc(Vector2.ZERO, 14.0, 0, TAU, 16, Color.WHITE, 2.0)
		"rocket":
			draw_set_transform(o, 0.0, Vector2(fx, 1.0))
			draw_circle(Vector2(-26, 0), 12.0 + sin(float(age) * 1.7) * 3.0, Color(1.0, 0.6, 0.15, 0.7))
			draw_rect(Rect2(-22, -7, 44, 14), Color(0.85, 0.88, 0.95))
			draw_polygon(PackedVector2Array([Vector2(22, -7), Vector2(34, 0), Vector2(22, 7)]), PackedColorArray([Color(0.9, 0.3, 0.25)]))
		"strike":
			draw_rect(Rect2(-95, -50, 190, 78), Color(color.r * 0.6 + 0.3, color.g * 0.6 + 0.3, color.b * 0.6 + 0.3, 0.95))
			draw_rect(Rect2(-95, -50, 190, 78), Color.WHITE, false, 4.0)
			draw_rect(Rect2(-70, -38, 54, 30), Color(0.75, 0.92, 1.0, 0.9))
			draw_circle(Vector2(-55, 30), 18.0, Color(0.1, 0.12, 0.2))
			draw_circle(Vector2(55, 30), 18.0, Color(0.1, 0.12, 0.2))
			draw_circle(Vector2(-55, 30), 8.0, Color.WHITE)
			draw_circle(Vector2(55, 30), 8.0, Color.WHITE)
		"orb":
			var pulse := 1.0 + 0.12 * sin(float(age) * 0.7)
			var r := size.x * 0.95 * pulse
			_blit("energy_ball", Rect2(-r, -r, r * 2.0, r * 2.0), Color(color.r, color.g, color.b, 0.85))
			var c := r * 0.55
			_blit("energy_ball", Rect2(-c, -c, c * 2.0, c * 2.0), Color(1, 1, 1, 0.95))
		"mine":
			var armed := age >= int(mine.get("arm", 30))
			var pl := 0.5 + 0.5 * sin(float(age) * (0.5 if armed else 0.15))
			draw_circle(Vector2.ZERO, 16.0, Color(0.12, 0.14, 0.22))
			draw_arc(Vector2.ZERO, 16.0, 0, TAU, 20, Color(1, 1, 1, 0.9), 2.0)
			draw_circle(Vector2.ZERO, 6.0, Color(color.r, color.g, color.b, (0.4 + 0.6 * pl) if armed else 0.3))
			if armed:
				draw_arc(Vector2.ZERO, float(mine.get("radius", 90.0)) * (0.8 + 0.2 * pl), 0, TAU, 28, Color(color.r, color.g, color.b, 0.25), 2.0)
		"wave":
			var k3 := clampf(float(age) / 24.0, 0.0, 1.0)
			draw_set_transform(o, 0.0, Vector2(fx, 1.0))
			_blit("blade", Rect2(-size.x * 0.4, -size.y * 0.6, size.x * 0.8, size.y * 1.2), Color(color.r, color.g, color.b, 0.9 * (1.0 - k3 * 0.4)), mini(int(k3 * 4.0), 3))
		"pillar":
			var kp := clampf(float(age) / 8.0, 0.0, 1.0)
			var wd := size.x * (0.3 + 0.7 * kp) * (1.0 - clampf(float(age - 10) / 20.0, 0.0, 1.0) * 0.6)
			draw_set_transform(o, -PI * 0.5, Vector2.ONE)
			_blit_beam(size.y, wd * 1.5, Color(color.r, color.g, color.b, 0.9), true)
			_blit_beam(size.y, wd * 0.5, Color(1, 1, 1, 0.95), true)
		"crescent":
			draw_set_transform(o, vel.angle() if vel.length() > 0.1 else 0.0, Vector2.ONE)
			_blit("blade", Rect2(-size.x * 0.5, -size.y * 0.75, size.x, size.y * 1.5), Color(color.r, color.g, color.b, 0.95), mini(age / 3, 3))
		"shell":
			draw_rect(Rect2(-9, -22, 18, 40), Color(0.85, 0.88, 0.95))
			draw_polygon(PackedVector2Array([Vector2(-9, 18), Vector2(0, 30), Vector2(9, 18)]), PackedColorArray([Color(0.9, 0.3, 0.25)]))
			draw_line(Vector2(0, -22), Vector2(0, -70), Color(color.r, color.g, color.b, 0.4), 6.0, true)
		"beam":
			var t := float(life) / float(maxi(1, age + life))
			var th := size.y * (0.55 + 0.45 * t)
			draw_set_transform(o, 0.0, Vector2(fx, 1.0))
			_blit_beam(size.x, th * 2.4, Color(color.r, color.g, color.b, 0.95))
			_blit_beam(size.x, th * 1.0, Color(1, 1, 1, 0.97))
			_blit("tracer_head", Rect2(-th * 1.6, -th * 1.6, th * 3.2, th * 3.2), Color(1, 1, 1, 0.9))
		"flame":
			var k := clampf(float(age) / 20.0, 0.0, 1.0)
			var fr := mini(int(k * 20.0), 19)
			var fs := 70.0 + 70.0 * k
			draw_set_transform(o, 0.0, Vector2(fx, 1.0))
			_blit("fire_puff", Rect2(size.x * 0.25 * k - fs * 0.5, -fs * 0.5, fs, fs), Color(1.0, 0.5, 0.15, 0.95 * (1.0 - k)), fr)
			_blit("fire_puff", Rect2(size.x * 0.3 * k - fs * 0.35, -fs * 0.35, fs * 0.7, fs * 0.7), Color(1.0, 0.9, 0.5, 0.9 * (1.0 - k)), fr)
		"blast":
			var k2 := clampf(float(age) / 8.0, 0.0, 1.0)
			var r2 := size.x * 0.62 * (0.45 + 0.55 * k2)
			_blit("fire_puff", Rect2(-r2, -r2, r2 * 2.0, r2 * 2.0), Color(color.r, color.g, color.b, 0.95 * (1.0 - k2 * 0.6)), mini(int(k2 * 19.0), 19))
			var r3 := r2 * 0.7
			_blit("fire_puff", Rect2(-r3, -r3, r3 * 2.0, r3 * 2.0), Color(1.0, 0.92, 0.65, 0.9 * (1.0 - k2)), mini(int(k2 * 19.0) + 1, 19))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if world and world.debug_boxes:
		var rr := rect()
		draw_rect(Rect2(rr.position - position, rr.size), Color(1, 0.4, 0.1, 0.9), false, 2.0)
