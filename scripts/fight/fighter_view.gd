extends Node2D
## Visual rig of a Fighter (child node "View"). Reads the simulation state, never writes it.
## Fighters with assets/ba/sd/<key>/sd.json use SD actors with texture-preserving toon materials; others keep the paths below.
##  * The portrait is drawn through shaders/fighter.gdshader (soft-body warp: lean from the hips, S-bend, feet swing,
##    per-segment squash/stretch, breathing, jelly wobble) so the torso whips while the feet stay planted.
##  * Pose channels are driven by critically/under-damped springs: the state machine only sets TARGETS (anticipation ->
##    snap -> follow-through per move) and events (hit, land, shot) kick the springs, which gives overshoot and weight.
##  * Also: ground shadow, EX-ready halo, super/buff/shield auras, afterimage pool, casings, swish arcs, KO / win effects.

const SHADER := preload("res://shaders/fighter.gdshader")
const SD_ACTOR := preload("res://scripts/models/sd_fighter_actor.gd")
const PAD_X := 0.62
const PAD_TOP := 0.26
const PAD_BOT := 0.05
const GHOSTS := 8

# pose channels
enum { PX, PY, ROT, LEAN, TWIST, LEGS, SWAY, SYL, SYT, SYH, SX, PUFF, WOB, PIVOT, NCH }
const CH := {"px": PX, "py": PY, "rot": ROT, "lean": LEAN, "twist": TWIST, "legs": LEGS, "sway": SWAY, "syl": SYL,
	"syt": SYT, "syh": SYH, "sx": SX, "puff": PUFF, "wob": WOB, "pivot": PIVOT}
const NEUTRAL := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0]
const FREQ := [7.0, 8.0, 8.5, 8.5, 7.0, 9.0, 6.0, 10.0, 8.5, 8.5, 10.0, 6.0, 5.0, 12.0]
const ZETA := [0.5, 0.5, 0.5, 0.45, 0.5, 0.55, 0.7, 0.5, 0.5, 0.5, 0.55, 0.7, 0.28, 0.8]

# per-shot recoil kicks (velocity impulses): [px px/s, rot rad/s, lean /s, wob]
const KICK := {
	"AR": [330.0, 2.4, 2.0, 0.35], "SMG": [210.0, 1.4, 1.2, 0.3], "HG": [420.0, 3.4, 2.6, 0.4],
	"SG": [1500.0, 7.0, 6.0, 1.0], "SR": [1300.0, 6.0, 4.5, 0.9], "MG": [260.0, 1.2, 1.4, 0.32],
	"GL": [820.0, 4.0, 3.4, 0.6], "RL": [900.0, 4.2, 3.6, 0.6], "RG": [1100.0, 4.0, 4.0, 0.9],
	"MT": [600.0, 2.0, 2.0, 0.4], "FT": [90.0, 0.6, 0.6, 0.2],
}
const NO_CASING := ["RG", "GL", "RL", "MT", "FT"]

class DrawProxy extends Node2D:
	var cb: Callable
	func _draw() -> void:
		if cb.is_valid():
			cb.call(self)

var f: Fighter
var rig: Node2D
var body: Sprite2D
var back: DrawProxy
var mat: ShaderMaterial
var sd_mode := false
var sd_actor: Node2D
var _shield_fx := true                # sd.json "hide_shield_fx" turns off the shield dome and glow

var _val := PackedFloat32Array()
var _vel := PackedFloat32Array()
var _tg := PackedFloat32Array()
var _fmul := 1.0
var _time := 0.0
var _wph := 0.0
var _mff := 0.0
var _prev_state := -1
var _prev_mf := -99
var _prev_key := ""
var _prev_flash := 0.0
var _prev_spawned := 0
var _prev_hitstop := 0
var _prev_connected := false
var _prev_vy := 0.0
var _flash_col := Color.WHITE
var _super := 0.0
var _ex_ready := 0.0
var _glow_col := Color(0.55, 0.9, 1.0)
var _u := {}
var _ghosts: Array = []
var _ghost_i := 0
var _ghost_cd := 0.0
var _fx_cd := 0.0
var _win_t := 0.0
var _hit_shake := 0.0
var _tex_scale := 0.3
var _weapon := "AR"
var _jit := Vector2.ZERO
var _swish_fx: Fx

static var _mip_cache := {}

static func mip_texture(tex: Texture2D) -> Texture2D:
	var key := tex.resource_path
	if key != "" and _mip_cache.has(key):
		return _mip_cache[key]
	var img := tex.get_image()
	if img == null:
		return tex
	if img.is_compressed():
		img.decompress()
	img.fix_alpha_edges()
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	if key != "":
		_mip_cache[key] = t
	return t

func setup(fighter: Fighter) -> void:
	f = fighter
	name = "View"
	_weapon = String(f.data.get("weapon", "AR"))
	_val.resize(NCH)
	_vel.resize(NCH)
	_tg.resize(NCH)
	for i in NCH:
		_val[i] = NEUTRAL[i]
		_tg[i] = NEUTRAL[i]
	back = DrawProxy.new()
	back.cb = _draw_back
	add_child(back)
	rig = Node2D.new()
	add_child(rig)
	_glow_col = Color(f.stats["color"]).lerp(Color.WHITE, 0.35)
	if SD_ACTOR.supports(f.data):
		sd_actor = SD_ACTOR.new()
		rig.add_child(sd_actor)
		sd_actor.setup(f.data)
		sd_actor.look_driven = true
		body = sd_actor.body
		mat = sd_actor.mat
		_shield_fx = not bool(sd_actor.cfg["hide_shield_fx"])
		sd_mode = true
		return
	body = Sprite2D.new()
	var tex: Texture2D = UI.portrait(int(f.data["id"]))
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	body.texture = mip_texture(tex)
	_tex_scale = Arena.SPRITE_H / th
	_glow_col = Color(f.stats["color"]).lerp(Color.WHITE, 0.35)
	_setup_sprite(body, tw, th)
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	_init_material(mat, tw, th)
	body.material = mat
	rig.add_child(body)
	_build_ghosts(tw, th)

func _setup_sprite(sp: Sprite2D, tw: float, th: float) -> void:
	var px := th * PAD_X
	var pt := th * PAD_TOP
	var pb := th * PAD_BOT
	sp.centered = false
	sp.region_enabled = true
	sp.region_rect = Rect2(-px, -pt, tw + 2.0 * px, th + pt + pb)
	sp.offset = Vector2(-tw * 0.5 - px, -th - pt)
	sp.scale = Vector2(_tex_scale, _tex_scale)
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func _init_material(m: ShaderMaterial, tw: float, th: float) -> void:
	m.set_shader_parameter("outline_color", Color(1, 1, 1, 0.95) if f.slot == 1 else Color(0.92, 0.96, 1.0, 0.95))
	m.set_shader_parameter("aspect", tw / th)
	m.set_shader_parameter("outline_px", 2.0 / _tex_scale)
	m.set_shader_parameter("lod", maxf(0.0, log(1.0 / _tex_scale) / log(2.0) - 0.4))

func _build_ghosts(tw: float, th: float) -> void:
	var parent := f.get_parent()
	for i in GHOSTS:
		var sp := Sprite2D.new()
		sp.texture = body.texture
		_setup_sprite(sp, tw, th)
		var gm := ShaderMaterial.new()
		gm.shader = SHADER
		_init_material(gm, tw, th)
		sp.material = gm
		sp.z_index = 2
		sp.visible = false
		parent.add_child(sp)
		_ghosts.append({"spr": sp, "mat": gm, "age": 0.0, "life": 0.3, "alpha": 0.5})

# ── per-frame ────────────────────────────────────────────────────────────────
func step(delta: float) -> void:
	delta = minf(delta, 0.05)
	_time += delta
	if sd_mode:
		sd_actor.sync(f)          # before the events, so shots, flashes and casings read this tick's pose
	if f.state == Fighter.S.ATTACK:
		_mff = clampf(_mff + delta * 60.0, float(maxi(f.mf, 0)), float(maxi(f.mf, 0)) + 0.99)
	_track_events(delta)
	_targets(delta)
	_integrate(delta)
	_apply(delta)
	_update_ghosts(delta)
	_ambient_fx(delta)
	back.queue_redraw()

func _world_fx() -> Node:
	return f.world.fx_layer if f.world else null

func _parts() -> FxParticles:
	var l := _world_fx()
	return FxParticles.of(l) if l else null

func _muzzle_pos() -> Vector2:
	if sd_mode:
		return f.position + rig.transform * sd_actor.anchor_local("muzzle")
	return f.position + Vector2(float(f.facing) * 54.0, -176.0)

## The muzzle for effects the sim starts mid-tick (a projectile, a charge cue), before this view's own step: an SD
## actor is posed to the sim's current tick first. Presentation only; the sim never reads it.
func shot_origin() -> Vector2:
	if sd_mode:
		sd_actor.sync(f)
	return _muzzle_pos()

## World position of the head, for effects that want it.
func head_pos() -> Vector2:
	if sd_mode:
		return f.position + rig.transform * sd_actor.anchor_local("head")
	return f.position + Vector2(0.0, -Arena.SPRITE_H * 0.9)

# ── events: detect sim-state changes and turn them into spring kicks / effects ─
func _track_events(_delta: float) -> void:
	# round restart / state change
	if f.state != _prev_state:
		_on_state(_prev_state, f.state)
		_prev_state = f.state
	# hit / block (the sim sets _flash on impact: 0.55 hit, 0.3 block)
	if f._flash > _prev_flash + 0.001:
		if f.state == Fighter.S.BLOCK:
			_on_block()
		else:
			_on_hit()
	_prev_flash = f._flash
	# attack bookkeeping
	if f.state == Fighter.S.ATTACK and not f.move.is_empty():
		var restart := f.mf < _prev_mf or f.move_key != _prev_key
		if restart:
			_prev_spawned = 0
			_mff = float(maxi(f.mf, 0))
			_prev_connected = false
		if f.mf != _prev_mf:
			var st := int(f.move["startup"])
			if f.mf == st and not f.move["hit"].is_empty() and f.move.get("swish", true):
				_spawn_swish()
			if f.mf == st - 1 and (f.move["cutin"] or f.in_super()):
				_super = maxf(_super, 0.6)
			# gun normals: every "shots" frame passed since the last step (the sim can run ahead of the view); a frame
			# that also spawns a projectile is shown by the spawn
			var rounds := 0
			for s in f.move.get("shots", []):
				if int(s) <= f.mf and (restart or int(s) > _prev_mf) and f.move["spawns"].all(func(sp): return int(sp["frame"]) != int(s)):
					rounds += 1
			if rounds > 0:
				_gun_shot(rounds)
		var n := f._spawned.size()
		if n > _prev_spawned:
			_on_shot(n - _prev_spawned)
		_prev_spawned = n
		if f.move_connected and not _prev_connected:
			_val[LEAN] += 0.02
			_vel[PX] += 220.0
		_prev_connected = f.move_connected
		_prev_mf = f.mf
		_prev_key = f.move_key
	else:
		_prev_mf = -99
		_prev_key = ""
		_prev_spawned = 0
	# landing squash (any airborne -> grounded transition handled in _on_state); hitstop impact tracking
	_prev_hitstop = f.hitstop
	_prev_vy = f.vel.y

func _on_state(old: int, new: int) -> void:
	var S := Fighter.S
	if new == S.INTRO:
		for i in NCH:
			_val[i] = NEUTRAL[i]
			_vel[i] = 0.0
		for g in _ghosts:
			g["spr"].visible = false
		_super = 0.0
		return
	if old == S.AIRHIT and (new == S.DOWN or new == S.KO):
		# a carried throw's tumble has turned the roll spring past whole turns: lie down the short way round, not backwards through them
		var turns := roundf((-1.52 - _val[ROT]) / TAU)
		if turns != 0.0:
			_val[ROT] += TAU * turns
			_vel[ROT] = 0.0
	match new:
		S.JUMP:
			if old != S.ATTACK:
				_val[SYL] = 0.78
				_val[SX] = 1.1
				_val[SYT] = 0.95
		S.DASH:
			_vel[LEAN] += 4.0
			_vel[PX] += 500.0
			_dash_fx(1.0)
		S.BACKDASH:
			_vel[LEAN] -= 3.0
			_vel[PX] -= 400.0
			_dash_fx(-1.0)
		S.DOWN:
			_vel[PY] += 260.0
			_vel[WOB] += 0.8
			_vel[ROT] -= 2.5
		S.GETUP:
			_vel[SYL] -= 3.0
			_vel[SX] += 2.0
		S.KO:
			_ko_fx()
		S.WIN:
			_win_t = 0.0
	# landing: JUMP / ATTACK(air) / AIRHIT -> a grounded state
	if old in [S.JUMP] and new in [S.IDLE, S.WALK, S.CROUCH, S.ATTACK, S.DASH, S.BACKDASH]:
		_land_squash(0.7)
	elif old == S.ATTACK and new in [S.IDLE, S.WALK, S.CROUCH] and f.is_grounded() and _prev_vy > 3.0:
		_land_squash(0.7)

func _land_squash(k: float) -> void:
	_val[SYL] = lerpf(1.0, 0.76, k)
	_val[SX] = lerpf(1.0, 1.12, k)
	_val[SYT] = lerpf(1.0, 0.93, k)
	_vel[LEAN] += 2.0 * k
	_vel[WOB] += 0.5 * k
	var p := _parts()
	if p:
		for i in 6:
			var s := -1.0 if i % 2 == 0 else 1.0
			p.emit(FxParticles.K.PUFF, f.position + Vector2(s * 12.0, -6.0), Vector2(s * (90.0 + 60.0 * Fx.h(float(i), 2.0)), -30.0),
				0.45, 11.0, Color.WHITE, 0.0, 3.0)

func _on_hit() -> void:
	_flash_col = Color(1.0, 0.97, 0.9)
	var s := clampf(float(f.hitstop) / 9.0, 0.5, 1.6)
	_hit_shake = s
	_vel[LEAN] -= 5.5 * s
	_vel[ROT] -= 4.0 * s
	_vel[PX] -= 700.0 * s
	_vel[WOB] += 1.4 * s
	_val[SYT] = 1.0 - 0.07 * s
	_val[SYL] = 1.0 - 0.04 * s
	_val[SX] = 1.0 + 0.04 * s

func _on_block() -> void:
	_flash_col = Color(0.62, 0.95, 1.0)
	_hit_shake = 0.5
	_vel[PX] -= 520.0
	_vel[LEAN] -= 1.5
	_val[SYL] = 0.92
	_val[SX] = 1.05

func _on_shot(count: int) -> void:
	var k: Array = KICK.get(_weapon, KICK["AR"])
	var amp := 1.0 if f.state == Fighter.S.ATTACK else 0.5
	if f.move.get("cutin", false):
		amp *= 1.0 if f.move.get("frames", 0) < 60 else 0.55
	_vel[PX] -= float(k[0]) * amp
	_vel[ROT] -= float(k[1]) * amp
	_vel[LEAN] -= float(k[2]) * amp
	_vel[WOB] += float(k[3]) * amp
	var p := _parts()
	if p and not _weapon in NO_CASING and (count == 1 or _weapon == "SG"):
		var o := f.position + Vector2(float(f.facing) * 30.0, -176.0)
		if sd_mode:
			o = _muzzle_pos() - Vector2(float(f.facing) * 40.0, 0.0)
		p.casing(o, f.facing, 1.0 if _weapon != "SG" else 1.4)

## A gun normal's rounds (move "shots"): the recoil kick and casing of _on_shot and a muzzle flash at the gun.
func _gun_shot(count: int) -> void:
	_on_shot(count)
	var l := _world_fx()
	if l:
		Fx.make(l, "muzzle", _muzzle_pos(), 0.09, {"dir": f.facing, "color": Color(f.stats["color"]), "size": 0.8})

func _spawn_swish() -> void:
	var l := _world_fx()
	if l == null:
		return
	var m: Dictionary = f.move
	var r: Rect2 = m["hit"]["rect"]
	var key: String = f.move_key
	var cy := r.position.y + r.size.y * 0.5
	var d := {"off": Vector2(r.position.x - r.size.x * 0.1, cy), "r": r.size.x * 0.85, "a0": -1.1, "a1": 0.5, "thick": 26.0, "squash": 1.0}
	match key:
		"5H":
			d["a0"] = -1.3
			d["a1"] = 0.75
			d["thick"] = 42.0
			d["r"] = r.size.x * 0.9
		"2L":
			d["off"] = Vector2(r.position.x - 8.0, r.position.y + r.size.y * 0.55)
			d["a0"] = -0.55
			d["a1"] = 0.5
			d["squash"] = 0.4
			d["thick"] = 20.0
		"2H":
			d["off"] = Vector2(r.position.x + r.size.x * 0.4, r.position.y + r.size.y * 0.92)
			d["a0"] = 0.55
			d["a1"] = -1.9
			d["r"] = r.size.y * 0.5
			d["thick"] = 36.0
		"jL":
			d["a0"] = -0.9
			d["a1"] = 0.7
			d["thick"] = 22.0
		"jH":
			d["off"] = Vector2(r.position.x, r.position.y + r.size.y * 0.2)
			d["a0"] = -1.35
			d["a1"] = 1.05
			d["thick"] = 36.0
			d["r"] = r.size.x * 0.9
	var big := key in ["5H", "2H", "jH"]
	d["color"] = Color(f.stats["color"]).lerp(Color.WHITE, 0.4)
	d["dir"] = f.facing
	d["follow"] = f
	d["foff"] = Vector2.ZERO
	d["z"] = 35
	d["seed"] = float(f.frame)
	_swish_fx = Fx.make(l, "swish", f.position, 0.2 + float(m["active"]) / 60.0 * 0.4 + (0.06 if big else 0.0), d)

func _dash_fx(sign_: float) -> void:
	var p := _parts()
	if p == null:
		return
	for i in 7:
		var back_dir := -float(f.facing) * sign_
		p.emit(FxParticles.K.PUFF, f.position + Vector2(back_dir * (8.0 + 7.0 * float(i)), -8.0 - 4.0 * Fx.h(float(i), 1.3)),
			Vector2(back_dir * (50.0 + 70.0 * Fx.h(float(i), 4.1)), -20.0), 0.5, 10.0 + 4.0 * Fx.h(float(i), 8.0), Color.WHITE, 0.0, 2.5)

func _ko_fx() -> void:
	var l := _world_fx()
	if l == null:
		return
	var c := f.position + Vector2(0, -150)
	Fx.make(l, "ko", c, 1.0, {"color": Color(1.0, 0.45, 0.4), "z": 45})
	var p := _parts()
	if p:
		for i in 22:
			var a := TAU * float(i) / 22.0 + Fx.h(float(i), 6.0)
			var sp := 260.0 + 520.0 * Fx.h(float(i), 2.2)
			p.emit(FxParticles.K.SPARK, c, Vector2.from_angle(a) * sp, 0.6 + 0.4 * Fx.h(float(i), 9.0), 5.0, Color(1.0, 0.85, 0.5), 700.0, 1.2)
		for i in 8:
			p.emit(FxParticles.K.STAR, c + Vector2(Fx.h(float(i), 3.0) * 160.0 - 80.0, Fx.h(float(i), 5.0) * 120.0 - 70.0),
				Vector2(0, -30), 0.8 + 0.5 * Fx.h(float(i), 1.0), 22.0 + 12.0 * Fx.h(float(i), 7.0), Color(1.0, 0.8, 0.5), 0.0, 0.0, 0.0, Fx.h(float(i), 8.0))

# ── ambient effects (auras, ghosts during supers, win sparkles) ──────────────
func _ambient_fx(delta: float) -> void:
	var S := Fighter.S
	var is_ex: bool = f.state == S.ATTACK and not f.move.is_empty() and (bool(f.move.get("cutin", false)) or f.in_super())
	var goal := 1.0 if is_ex else 0.0
	_super = move_toward(_super, goal, delta * (3.0 if goal > _super else 0.9))
	var ready := f.meter >= Arena.EX_COST and f.state not in [S.KO, S.WIN, S.DOWN, S.INTRO]
	_ex_ready = move_toward(_ex_ready, 1.0 if ready else 0.0, delta * 2.5)
	_fx_cd -= delta
	_ghost_cd -= delta
	var p := _parts()
	if p == null:
		return
	if is_ex and _ghost_cd <= 0.0:
		_ghost_cd = 0.07
		add_ghost(_glow_col, 0.32)
	if _super > 0.05 and _fx_cd <= 0.0:
		_fx_cd = 0.045
		var a := Fx.h(_time * 31.0, 1.0) * TAU
		var o := f.position + Vector2(cos(a) * 70.0, -20.0 - Fx.h(_time * 17.0, 2.0) * 60.0)
		p.emit(FxParticles.K.MOTE, o, Vector2(0.0, -150.0 - 100.0 * _super), 0.7, 18.0, _glow_col)
	elif f.buff_frames > 0 and _fx_cd <= 0.0:
		_fx_cd = 0.09
		var a2 := Fx.h(_time * 23.0, 4.0) * TAU
		p.emit(FxParticles.K.MOTE, f.position + Vector2(cos(a2) * 60.0, -30.0), Vector2(0, -80.0), 0.9, 13.0, Color(1.0, 0.85, 0.35))
	elif f.state == S.WIN and _fx_cd <= 0.0:
		_fx_cd = 0.07
		var o2 := f.position + Vector2(Fx.h(_time * 13.0, 3.0) * 220.0 - 110.0, -40.0 - Fx.h(_time * 29.0, 7.0) * 280.0)
		p.emit(FxParticles.K.STAR, o2, Vector2(0, -26.0), 0.7, 14.0 + 12.0 * Fx.h(_time * 7.0, 1.0), Color(1.0, 0.92, 0.55), 0.0, 0.0, 0.0, Fx.h(_time * 5.0, 9.0))
	elif f.state == S.WALK and _fx_cd <= 0.0 and f.is_grounded():
		_fx_cd = 0.18
		var bd := -signf(f.vel.x)
		p.emit(FxParticles.K.PUFF, f.position + Vector2(bd * 18.0, -5.0), Vector2(bd * 28.0, -14.0), 0.35, 6.5, Color.WHITE, 0.0, 2.0)

# ── ghosts (afterimages) ─────────────────────────────────────────────────────
func add_ghost(col := Color(0.7, 0.9, 1.0), life := 0.28) -> void:
	if _ghosts.is_empty():
		return
	var g: Dictionary = _ghosts[_ghost_i]
	_ghost_i = (_ghost_i + 1) % GHOSTS
	var sp: Sprite2D = g["spr"]
	var gm: ShaderMaterial = g["mat"]
	for k in _u:
		gm.set_shader_parameter(k, _u[k])
	gm.set_shader_parameter("flash", 0.8)
	gm.set_shader_parameter("flash_color", col)
	gm.set_shader_parameter("glow", 0.0)
	gm.set_shader_parameter("dim", 1.0)
	sp.global_transform = body.global_transform
	sp.visible = true
	g["age"] = 0.0
	g["life"] = life
	g["alpha"] = 0.55

func _update_ghosts(delta: float) -> void:
	for g in _ghosts:
		var sp: Sprite2D = g["spr"]
		if not sp.visible:
			continue
		g["age"] = float(g["age"]) + delta
		var k := float(g["age"]) / float(g["life"])
		if k >= 1.0:
			sp.visible = false
			continue
		var op := float(g["alpha"]) * (1.0 - k) * (1.0 - k)
		(g["mat"] as ShaderMaterial).set_shader_parameter("opacity", op)

# ── pose targets ─────────────────────────────────────────────────────────────
func _t(c: int, v: float) -> void:
	_tg[c] = v

func _ta(c: int, v: float) -> void:
	_tg[c] += v

func _add_def(d: Dictionary, w: float) -> void:
	if w <= 0.0:
		return
	for k in d:
		_tg[CH[k]] += float(d[k]) * w

static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

func _targets(delta: float) -> void:
	var S := Fighter.S
	for i in NCH:
		_tg[i] = NEUTRAL[i]
	_fmul = 1.0
	var fc := float(f.facing)
	var b := sin(_time * 2.6)
	match f.state:
		S.IDLE, S.INTRO:
			var sw := sin(_time * 1.15 + float(f.slot))
			var bob := 0.5 + 0.5 * sin(_time * 5.2)
			_t(PUFF, 0.016 * b + 0.01)
			_t(SYT, 1.0 + 0.007 * b)
			_t(LEAN, 0.014 * sw + 0.012)
			_t(PX, 1.5 * sw)
			_t(SYL, 1.0 - 0.014 * bob)
			_t(TWIST, 0.006 * sin(_time * 1.7))
			if f.state == S.INTRO:
				_ta(LEAN, 0.02)
				_ta(SYL, -0.02 * bob)
				_ta(PY, 2.0 * bob)
		S.WALK:
			_wph += absf(f.vel.x) * 60.0 * 0.035 * delta
			var sn := sin(_wph)
			var cs := cos(_wph)
			var mv := signf(f.vel.x * fc)
			_t(PY, 5.5 * absf(sn))
			_t(LEGS, 0.055 * sn * mv)
			_t(LEAN, 0.04 * mv + 0.012 * cs)
			_t(ROT, 0.02 * mv)
			_t(TWIST, -0.022 * sn)
			_t(SYL, 1.0 - 0.025 * (1.0 - absf(sn)))
			_t(PUFF, 0.012 * b + 0.008)
			_t(PX, 2.0 * mv)
		S.CROUCH:
			_fmul = 1.35
			_t(SYL, 0.5)
			_t(SYT, 0.8)
			_t(SYH, 0.93)
			_t(SX, 1.05)
			_t(LEAN, 0.1)
			_t(ROT, 0.03)
			_t(PX, 3.0)
			_t(PUFF, 0.02 * b + 0.015)
		S.JUMP:
			_pose_air(false)
		S.DASH:
			_fmul = 1.4
			_t(LEAN, 0.24)
			_t(ROT, 0.18)
			_t(SX, 1.06)
			_t(SYL, 0.93)
			_t(LEGS, -0.1)
			_t(PX, 7.0)
		S.BACKDASH:
			_fmul = 1.3
			var pr := clampf(float(f.sf) / 18.0, 0.0, 1.0)
			_t(LEAN, -0.15)
			_t(ROT, -0.12)
			_t(PY, 16.0 * sin(PI * pr))
			_t(SYL, 1.03)
			_t(LEGS, 0.08)
		S.ATTACK:
			_pose_attack()
		S.HIT:
			var sk := clampf(float(f.hitstun) / 10.0, 0.0, 1.0)
			_fmul = 1.3
			_t(LEAN, -0.17 * sk)
			_t(ROT, -0.1 * sk)
			_t(PX, -11.0 * sk)
			_t(SYT, 1.0 - 0.05 * sk)
			_t(TWIST, 0.05 * sk)
			_t(SYL, 1.0 - 0.03 * sk)
		S.AIRHIT:
			var rising := f.vel.y < 0.0
			var held := f.carry_anim != ""
			_t(PIVOT, 0.23 if held else 0.34)
			_t(ROT, deg_to_rad(f.carry_roll) * fc if held else (-0.65 if rising else -1.15))
			_t(LEAN, -0.1)
			_t(LEGS, 0.1)
			_t(SYL, 0.92)
			_t(WOB, 0.0)
			_fmul = 0.8
		S.BLOCK:
			_t(LEAN, 0.05)
			_t(ROT, -0.04)
			_t(SYL, 0.9)
			_t(SYT, 0.97)
			_t(SX, 1.04)
			_t(PX, -7.0)
		S.DOWN, S.KO:
			_t(PIVOT, 0.26)
			_t(ROT, -1.52)
			_t(PY, -42.0)
			_t(LEAN, -0.04)
			_t(PX, 62.0)
			_t(LEGS, 0.06)
			_fmul = 0.9
		S.GETUP:
			var g := _ease(float(f.sf) / 12.0)
			_t(PIVOT, 0.26)
			_t(ROT, -1.52 * (1.0 - g))
			_t(PY, -42.0 * (1.0 - g))
			_t(PX, 62.0 * (1.0 - g))
			_t(SYL, 1.0 + 0.05 * g)
			_fmul = 1.25
		S.WIN:
			_win_t += delta
			var ph := fposmod(_win_t, 2.3)
			if ph < 0.28:
				var q := _ease(ph / 0.28)
				_t(SYL, 1.0 - 0.2 * q)
				_t(SYT, 1.0 - 0.06 * q)
				_t(SX, 1.0 + 0.05 * q)
				_t(LEAN, 0.06 * q)
			elif ph < 0.95:
				var q2 := (ph - 0.28) / 0.67
				_t(PY, 62.0 * sin(PI * q2))
				_t(SYL, 1.07 - 0.1 * q2)
				_t(SYT, 1.03)
				_t(SX, 0.97)
				_t(LEAN, -0.06)
				_t(ROT, -0.06 * sin(PI * q2))
			else:
				_t(LEAN, -0.045 + 0.01 * sin(_time * 2.0))
				_t(PUFF, 0.035 + 0.01 * b)
				_t(SYT, 1.012)
				_t(PX, -2.0)
	# dim / flash / tint are applied in _apply

func _pose_air(_attacking: bool) -> void:
	var asc := clampf(-f.vel.y / 17.0, -1.0, 1.0)
	var stretch := absf(asc)
	_t(SYL, lerpf(0.84, 1.06 if asc > 0.0 else 1.03, stretch))
	_t(SYT, lerpf(0.97, 1.03, stretch))
	_t(SX, lerpf(1.04, 0.96, stretch))
	_t(LEAN, 0.03 + 0.03 * (1.0 - stretch))
	_t(ROT, clampf(f.vel.x * float(f.facing) * 0.014, -0.14, 0.14) + (0.05 if asc < 0.0 else 0.0))
	_t(LEGS, -0.05 * asc + 0.03)
	_t(PUFF, 0.01)

# per-move poses: [wind-up offsets, strike offsets] (+ a base applied the whole move)
func _pose_attack() -> void:
	var m: Dictionary = f.move
	if m.is_empty():
		return
	var key: String = f.move_key
	var p: Dictionary = m["pose"]
	var st := float(m["startup"])
	var ac := float(m["active"])
	var rc := float(m["recovery"])
	var fr := _mff
	var w := 0.0
	var s := 0.0
	if fr < st:
		w = _ease((fr + 1.0) / maxf(st, 1.0))
	elif fr < st + ac + 1.0:
		s = 1.0
	else:
		s = 1.0 - _ease((fr - st - ac - 1.0) / maxf(rc * 0.8, 1.0))
	var air: bool = m["air"] or not f.is_grounded()
	var defs := _defs(key, p, air)
	var base: Dictionary = defs[2]
	_add_def(base, 1.0)
	_add_def(defs[0], w)
	_add_def(defs[1], s)
	if air:
		_pose_air(true)
		_add_def(defs[0], w)
	var hop := float(p.get("hop", 0.0))
	if hop != 0.0:
		_ta(PY, hop * s)
	# snappier springs for the strike
	_fmul = 1.35 if s > 0.5 else 1.0
	# sustained fire vibration
	if s > 0.5 and key in ["skill", "skill_air", "ex"] and (_weapon in ["MG", "SMG", "AR"] or key == "ex"):
		_ta(PX, sin(_time * 70.0) * 1.2)
		_ta(ROT, sin(_time * 53.0) * 0.008)
	if key == "ex":
		_ta(SYT, 0.03 * _super)

func _defs(key: String, p: Dictionary, air: bool) -> Array:
	var lunge := float(p.get("lunge", 0.0))
	var pl := float(p.get("lean", 0.0))
	var wd := {}
	var sd := {}
	var base := {}
	match key:
		"5L":
			wd = {"lean": -0.05, "rot": -0.05, "twist": -0.03, "px": -5.0}
			sd = {"lean": 0.08 + pl * 0.4, "rot": 0.05, "twist": 0.035, "px": lunge, "legs": 0.03, "syt": 0.02}
		"5H":
			wd = {"lean": -0.13, "rot": -0.11, "syl": -0.1, "twist": -0.06, "px": -10.0}
			sd = {"lean": 0.2, "rot": 0.15, "syl": 0.03, "syt": 0.04, "twist": 0.07, "px": lunge, "legs": 0.05}
		"throw":
			match String(f.move.get("style", "")):
				"SLAM":
					wd = {"lean": -0.2, "rot": -0.1, "syl": 0.04, "px": -8.0}
					sd = {"lean": 0.2, "rot": 0.14, "py": -6.0, "syl": -0.06, "syt": 0.04, "px": lunge}
				"HURL":
					wd = {"lean": -0.16, "rot": -0.12, "twist": -0.09, "syl": -0.04, "px": -12.0}
					sd = {"lean": 0.2, "rot": 0.16, "twist": 0.1, "legs": 0.05, "syt": 0.04, "px": lunge}
				"TOSS":
					wd = {"lean": -0.16, "rot": -0.1, "twist": -0.08, "syl": 0.04, "px": -8.0}
					sd = {"lean": 0.18, "rot": 0.14, "twist": 0.12, "syt": 0.04, "px": lunge}
				"SWEEP":
					wd = {"lean": 0.06, "syl": -0.16, "syt": -0.05, "px": -4.0}
					sd = {"lean": 0.16, "rot": 0.06, "syl": -0.3, "syt": -0.1, "legs": 0.14, "px": lunge}
				"SHOVE":
					sd = {"lean": 0.12, "rot": 0.1, "twist": 0.04, "syt": 0.03, "px": lunge}
				_:
					wd = {"lean": -0.12, "rot": -0.08, "syl": -0.08, "px": -8.0}
					sd = {"lean": 0.22, "rot": 0.16, "syt": 0.05, "twist": 0.06, "px": lunge}
		"2L":
			base = {"syl": -0.5, "syt": -0.2, "syh": -0.07, "sx": 0.05, "lean": 0.1}
			wd = {"lean": -0.03, "px": -4.0}
			sd = {"lean": 0.07, "legs": 0.13, "px": lunge, "twist": 0.02}
		"2H":
			base = {"syl": -0.5, "syt": -0.2, "syh": -0.07, "sx": 0.05, "lean": 0.1}
			wd = {"syl": -0.06, "lean": 0.05, "px": -5.0}
			sd = {"syl": 0.55, "syt": 0.27, "syh": 0.1, "sx": -0.05, "lean": -0.22, "rot": -0.1, "legs": -0.06, "px": lunge, "twist": -0.05}
		"jL":
			wd = {"lean": -0.04, "syl": -0.06}
			sd = {"lean": 0.1, "rot": 0.08, "legs": 0.1, "syl": -0.06, "px": lunge}
		"jH":
			wd = {"lean": -0.08, "rot": -0.08, "syl": -0.08}
			sd = {"lean": 0.2, "rot": 0.3, "legs": 0.17, "syl": -0.05, "px": lunge, "twist": 0.05}
		"skill", "skill_air", "ex":
			var r := _skill_defs(key == "ex", pl)
			wd = r[0]
			sd = r[1]
			if air:
				sd = sd.duplicate()
				sd["rot"] = float(sd.get("rot", 0.0)) + 0.12
	return [wd, sd, base]

func _skill_defs(ex: bool, _pl: float) -> Array:
	var wd := {}
	var sd := {}
	match _weapon:
		"SMG":
			wd = {"syl": -0.04}
			sd = {"lean": 0.05, "syl": -0.1, "px": 4.0, "sx": 0.03}
		"HG":
			wd = {"lean": -0.05, "rot": -0.04, "twist": -0.03}
			sd = {"lean": 0.05, "px": 8.0, "twist": 0.03, "syl": -0.04}
		"SG":
			wd = {"lean": 0.06, "syl": -0.14, "rot": 0.04, "px": 2.0}
			sd = {"lean": -0.12, "rot": -0.1, "px": -12.0, "syl": -0.08, "twist": -0.04}
		"SR":
			wd = {"lean": 0.07, "rot": 0.04, "syl": -0.16, "sx": 0.03, "px": 2.0}
			sd = {"rot": -0.07, "px": -9.0, "syl": -0.14, "lean": -0.03}
		"MG":
			wd = {"lean": 0.05, "syl": -0.12, "sx": 0.04, "px": 2.0}
			sd = {"lean": 0.07, "syl": -0.16, "sx": 0.05, "px": 5.0}
		"GL", "RL", "MT":
			wd = {"lean": -0.1, "rot": -0.07, "syl": -0.04}
			sd = {"lean": -0.13, "rot": -0.09, "px": -8.0, "syl": -0.06}
		"RG":
			wd = {"lean": -0.06, "syl": 0.05, "syt": 0.05, "syh": 0.03}
			sd = {"lean": 0.06, "rot": 0.05, "px": -8.0, "syl": -0.06}
		"FT":
			wd = {"lean": 0.04, "syl": -0.06}
			sd = {"lean": 0.07, "syl": -0.1, "px": 3.0}
		_:
			wd = {"lean": -0.03, "rot": -0.03, "syl": -0.06}
			sd = {"lean": 0.06, "rot": 0.04, "syl": -0.08, "px": 6.0, "sx": 0.02}
	if ex:
		wd = {"lean": -0.08, "rot": -0.06, "syl": 0.04, "syt": 0.05, "py": 6.0}
		sd = sd.duplicate()
		for k in sd:
			sd[k] = float(sd[k]) * 1.3
	return [wd, sd]

# ── spring integration + applying to the nodes / shader ──────────────────────
func _integrate(delta: float) -> void:
	var n := maxi(1, int(ceil(delta / (1.0 / 120.0))))
	var hstep := delta / float(n)
	for i in NCH:
		var w: float = TAU * float(FREQ[i]) * _fmul
		var k := w * w
		var c := 2.0 * float(ZETA[i]) * w
		var v := _vel[i]
		var x := _val[i]
		var t := _tg[i]
		for j in n:
			v += (k * (t - x) - c * v) * hstep
			x += v * hstep
		_vel[i] = v
		_val[i] = x

func _apply(delta: float) -> void:
	var fc := float(f.facing)
	var S := Fighter.S
	# hit-stop jitter on the receiver
	_hit_shake = maxf(0.0, _hit_shake - delta * 4.0)
	_jit = Vector2.ZERO
	if f.hitstop > 0 and f.state in [S.HIT, S.AIRHIT, S.BLOCK]:
		var amp := FxFlash.shake(5.0) * minf(_hit_shake + 0.3, 1.6)
		_jit = Vector2(sin(_time * 95.0), cos(_time * 70.0) * 0.4) * amp
	var glow := maxf(_ex_ready * (0.22 + 0.1 * sin(_time * 4.0)), _super * (0.75 + 0.2 * sin(_time * 18.0)))
	var gcol := _glow_col
	if f.buff_frames > 0:
		glow = maxf(glow, 0.45)
		gcol = Color(1.0, 0.85, 0.35)
	if f.shield_frames > 0 and _shield_fx:
		glow = maxf(glow, 0.4)
		gcol = Color(0.55, 0.88, 1.0)
	if sd_mode:
		rig.rotation = deg_to_rad(f.carry_roll)
		rig.position = _jit + f.carry_pivot - f.carry_pivot.rotated(rig.rotation)
		rig.z_index = 2 if f.carry_anim != "" and f.carry_front else 0
		rig.scale = Vector2.ONE
		sd_actor.set_look(f._flash, _flash_col, f.dim, 0.45 if f.state == S.KO else 0.0, glow, gcol)
		if f._flash <= 0.01:
			_flash_col = Color.WHITE
		return
	var rot := _val[ROT] * fc
	var anchor := Vector2(_val[PX] * fc, -_val[PY]) + _jit
	var pv := Vector2(0.0, -_val[PIVOT] * Arena.SPRITE_H)
	var t := Transform2D(rot, Vector2(fc, 1.0), 0.0, Vector2.ZERO)
	rig.position = anchor + pv - t * pv
	rig.rotation = rot
	rig.scale = Vector2(fc, 1.0)
	if is_instance_valid(_swish_fx):
		_swish_fx.data["foff"] = Vector2(_val[PX] * fc, -_val[PY])
	var is_ko := f.state == S.KO
	var op := 1.0
	if f.invuln > 0 and (f.frame / 3) % 2 == 0 and f.state == S.GETUP:
		op = 0.55
	var u := {
		"flash": f._flash,
		"flash_color": _flash_col,
		"dim": f.dim,
		"desat": 0.55 if is_ko else 0.0,
		"opacity": op,
		"glow": glow,
		"glow_color": gcol,
		"lean": _val[LEAN], "twist": _val[TWIST], "legs": _val[LEGS], "sway": _val[SWAY],
		"syl": clampf(_val[SYL], 0.3, 1.4), "syt": clampf(_val[SYT], 0.5, 1.4), "syh": clampf(_val[SYH], 0.6, 1.3),
		"sx": clampf(_val[SX], 0.7, 1.4), "puff": _val[PUFF], "wob": _val[WOB], "wob_ph": _time * 16.0,
	}
	_u = u
	for k in u:
		mat.set_shader_parameter(k, u[k])
	if f._flash <= 0.01:
		_flash_col = Color.WHITE

# ── back layer (behind the sprite): shadow, halo, auras, shield ──────────────
func _draw_back(ci: Node2D) -> void:
	var S := Fighter.S
	# ground shadow
	var gy := Arena.GROUND - f.position.y
	var hk := clampf(gy / 360.0, 0.0, 0.8)
	var sw := 86.0 * (1.0 - hk * 0.55)
	var sa := 0.34 * (1.0 - hk)
	if f.state in [S.DOWN, S.KO]:
		sw = 120.0
	ci.draw_set_transform(Vector2(0, gy), 0.0, Vector2(1.0, 0.2))
	Fx.glow(ci, Vector2.ZERO, sw * 1.35, Color(0.0, 0.04, 0.14, sa * 0.8))
	Fx.glow(ci, Vector2.ZERO, sw * 0.78, Color(0.0, 0.03, 0.1, sa * 0.9))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var cpos := Vector2(0, -150)
	# EX-ready halo (soft pulse behind the body + a ground ring)
	if _ex_ready > 0.01:
		var pu := 0.5 + 0.5 * sin(_time * 4.0)
		Fx.glow(ci, cpos, 170.0 + 14.0 * pu, Color(_glow_col.r, _glow_col.g, _glow_col.b, _ex_ready * (0.14 + 0.07 * pu)))
		ci.draw_set_transform(Vector2(0, gy), 0.0, Vector2(1.0, 0.22))
		ci.draw_arc(Vector2.ZERO, 70.0 + 10.0 * pu, 0.0, TAU, 36, Color(_glow_col.r, _glow_col.g, _glow_col.b, _ex_ready * (0.35 + 0.2 * pu)), 5.0, true)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# super aura: big glow, rising light ribbons, expanding ground rings
	if _super > 0.02:
		var sp := _super
		Fx.glow(ci, cpos, 260.0 * (0.8 + 0.2 * sin(_time * 14.0)), Color(_glow_col.r, _glow_col.g, _glow_col.b, 0.5 * sp))
		for i in 7:
			var fi := float(i)
			var x := (fi - 3.0) * 20.0 + sin(_time * 3.0 + fi) * 8.0
			var ph := fposmod(_time * 1.6 + Fx.h(fi, 2.0), 1.0)
			var y1 := -ph * 330.0
			Fx.ribbon(ci, Vector2(x, y1 + 120.0), Vector2(x, y1), 5.0, 1.0, Color(1, 1, 1, 0.0), Color(_glow_col.r, _glow_col.g, _glow_col.b, 0.8 * sp * (1.0 - ph)))
		for j in 2:
			var rk := fposmod(_time * 1.8 + float(j) * 0.5, 1.0)
			ci.draw_set_transform(Vector2(0, gy), 0.0, Vector2(1.0, 0.24))
			ci.draw_arc(Vector2.ZERO, 40.0 + 150.0 * rk, 0.0, TAU, 40, Color(_glow_col.r, _glow_col.g, _glow_col.b, sp * (1.0 - rk)), 6.0 * (1.0 - rk) + 1.0, true)
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# buff aura
	if f.buff_frames > 0:
		var ba := minf(1.0, float(f.buff_frames) / 30.0)
		var gc := Color(1.0, 0.85, 0.35)
		Fx.glow(ci, cpos, 150.0 + 8.0 * sin(_time * 8.0), Color(gc.r, gc.g, gc.b, 0.22 * ba))
		ci.draw_set_transform(Vector2(0, gy), 0.0, Vector2(1.0, 0.24))
		ci.draw_arc(Vector2.ZERO, 66.0 + 4.0 * sin(_time * 8.0), 0.0, TAU, 36, Color(gc.r, gc.g, gc.b, 0.6 * ba), 4.0, true)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# shield dome with hexagons
	if f.shield_frames > 0 and _shield_fx:
		var a := 0.65 + 0.2 * sin(_time * 12.0)
		Fx.bubble(ci, cpos, 138.0, Color(0.5, 0.88, 1.0, a))
		for i in 6:
			var ang := _time * 0.6 + TAU * float(i) / 6.0
			var hp := cpos + Vector2(cos(ang), sin(ang)) * 118.0
			Fx.hexagon(ci, hp, 14.0, Color(0.8, 0.97, 1.0, 0.45 + 0.25 * sin(_time * 7.0 + float(i))), 2.0, ang, 0.15)
	# debug boxes
	if f.world and f.world.debug_boxes:
		var hb := f.hurtbox()
		ci.draw_rect(Rect2(hb.position - f.position, hb.size), Color(0.2, 0.6, 1.0, 0.8), false, 2.0)
		var ah := f.active_hit()
		if not ah.is_empty():
			var wr := f.melee_rect(ah["rect"])
			ci.draw_rect(Rect2(wr.position - f.position, wr.size), Color(1.0, 0.2, 0.2, 0.9), false, 2.0)
