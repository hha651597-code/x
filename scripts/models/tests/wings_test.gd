extends SceneTree
## Hina's wings: the air dash (once per jump, 16 ticks at 14.3 px, no gravity, air attacks locked for 8) and the glide (fall
## capped at 2.5, 90 ticks per jump, up held after it was released once). Hoshino has neither.
## Run with MAXLINES=60 TEST=res://scripts/models/tests/wings_test.gd tools/sd_test.sh (a real small window).
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

var checks := 0
var failures: Array = []
var hina: Node
var hoshino: Node
var states: Dictionary
var FI: GDScript
var A: GDScript
var M: GDScript

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("WINGS_CHECK FAIL ", label)
		failures.append(label)

func _run() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		print("WINGS_TEST FAIL watchdog timeout")
		quit(3))
	await process_frame
	FI = load("res://scripts/fight/fight_input.gd")
	A = load("res://scripts/fight/arena.gd")
	M = load("res://scripts/fight/movesets.gd")
	var game: Node = root.get_node("Game")
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	game.session.begin("training")
	game.session.players[0]["fighter"] = 10004
	game.session.players[1]["fighter"] = 10005
	await game.go("fight", {}, "cut")
	var screen: Node = game.stack.back()
	screen.set_physics_process(false)
	screen.phase = "fight"
	states = screen.f1.get_script().S
	hina = screen.f1
	hoshino = screen.f2
	_dash()
	_dash_rules()
	_glide()
	_glide_gate()
	_glide_attack()
	_dash_on_landing()
	_back_dash_hit()
	_hit_clears()
	_hoshino()
	print("WINGS_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _reset(f: Node) -> void:
	var other: Node = hoshino if f == hina else hina
	other.position = Vector2(300.0 if f == hina else -300.0, A.GROUND)
	other.state = states.IDLE
	f.reset_round(-300.0 if f == hina else 300.0, 1 if f == hina else -1)
	f._set_state(states.IDLE)
	f.input = FI.new()
	f.hitstop = 0
	f.sf = 0

func _step(f: Node, x := 0, y := 0, btns := []) -> void:
	f.input = FI.from_held(f.input, x, y, btns)
	f.tick()

## A real jump from the floor, then `rise` ticks with nothing held.
func _takeoff(f: Node, rise := 4, x := 0) -> void:
	_reset(f)
	_step(f, x, -1)
	for i in rise:
		_step(f, x)

func _land(f: Node) -> void:
	for i in 200:
		if f.state != states.JUMP:
			break
		_step(f)
	_step(f)

func _dash() -> void:
	var f := hina
	_takeoff(f)
	check(f.state == states.JUMP, "hina: a jump from the floor is JUMP")
	var y0: float = f.position.y
	var vy := true
	var vx := true
	var lock := true
	var anim := true
	for i in 16:
		_step(f, 0, 0, ["dash"] if i == 0 else [])
		vx = vx and is_equal_approx(f.vel.x, 14.3 * float(f.facing))
		vy = vy and is_equal_approx(f.vel.y, 0.0)
		lock = lock and f.air_ok == (i >= 8)
		anim = anim and String(f.kv.get("anim", "")) == "dash_air" and int(f.kv.get("anim_t", -1)) == i
	check(vx, "hina: a neutral air dash runs 16 ticks at 14.3 px forward")
	check(vy, "hina: gravity is cancelled for the whole dash")
	check(is_equal_approx(f.position.y, y0), "hina: the dash holds her height")
	check(lock, "hina: air attacks are locked for the first 8 ticks of the dash and free after")
	check(anim, "hina: the kit anim is dash_air with anim_t counting up from 0")
	_step(f)
	check(is_equal_approx(f.vel.x, float(f.stats["jump_dx"]) * float(f.facing)), "hina: the dash hands her jump speed back (%.1f)" % f.vel.x)
	check(String(f.kv.get("anim", "")) == "", "hina: no kit anim once the dash is over")
	check(f.vel.y > 0.0, "hina: she falls again after the dash")
	_step(f, 0, 0, ["dash"])
	check(not is_equal_approx(f.vel.x, 14.3 * float(f.facing)) and int(f.kv["dash_t"]) == 0, "hina: a second dash in the same jump does nothing")
	_land(f)
	check(f.state == states.IDLE, "hina: she lands")
	for i in 5:
		_step(f, 0, -1 if i == 0 else 0)
	_step(f, 0, 0, ["dash"])
	check(is_equal_approx(f.vel.x, 14.3 * float(f.facing)), "hina: landing gives the dash back")
	_takeoff(f)
	_step(f, -f.facing, 0, ["dash"])
	check(is_equal_approx(f.vel.x, -14.3 * float(f.facing)) and String(f.kv["anim"]) == "dash_air_back", "hina: holding back dashes back and asks for dash_air_back")
	_takeoff(f)
	_step(f, f.facing, 0, ["dash"])
	check(is_equal_approx(f.vel.x, 14.3 * float(f.facing)) and String(f.kv["anim"]) == "dash_air", "hina: holding forward dashes forward")

func _dash_rules() -> void:
	var f := hina
	_takeoff(f)
	_step(f, 0, 0, ["dash"])
	_step(f, 0, 0, ["light"])
	for i in 8:
		_step(f)
	check(f.state == states.JUMP, "hina: a light press early in the dash fires nothing while the lock holds (state %d)" % f.state)
	for i in 10:
		_step(f)
	_takeoff(f)
	_step(f, 0, 0, ["dash"])
	for i in 8:
		_step(f)
	_step(f, 0, 0, ["light"])
	check(f.state == states.ATTACK and f.move_key == "jL", "hina: a light press once the lock is over starts jL (%s)" % f.move_key)
	_step(f)
	check(int(f.kv["dash_t"]) == 0 and String(f.kv["anim"]) == "" and f.air_ok, "hina: an air attack ends the dash and leaves no kit anim")
	check(is_equal_approx(f.vel.x, float(f.stats["jump_dx"]) * float(f.facing)), "hina: an air attack that cuts the dash short gets her jump speed, not the dash's (%.1f)" % f.vel.x)

func _glide() -> void:
	var f := hina
	_reset(f)
	f._set_state(states.JUMP)
	f.position.y = A.GROUND - 600.0
	f.vel = Vector2(0.0, 8.0)
	_step(f)
	_step(f, 0, -1)
	var worst := 0.0
	var anim := true
	var ticks := 0
	while String(f.kv.get("anim", "")) == "glide" and ticks < 200:
		worst = maxf(worst, f.vel.y)
		anim = anim and int(f.kv.get("anim_t", -1)) == ticks
		ticks += 1
		_step(f, 0, -1)
	check(worst <= 2.5 + 1e-6, "hina: the glide never falls faster than 2.5 (%.3f)" % worst)
	check(ticks == 90, "hina: the glide lasts 90 ticks (%d)" % ticks)
	check(anim, "hina: glide anim_t counts from 0")
	check(f.vel.y > 2.5, "hina: the fall speeds up again once the glide runs out (%.2f)" % f.vel.y)
	_reset(f)
	f._set_state(states.JUMP)
	f.position.y = A.GROUND - 600.0
	f.vel = Vector2(0.0, 8.0)
	_step(f)
	_step(f, 0, -1)
	_step(f, 0, -1)
	check(String(f.kv["anim"]) == "glide", "hina: up held while falling glides")
	_step(f, 0, 0)
	check(String(f.kv["anim"]) == "" and f.vel.y > 2.5, "hina: releasing up ends the glide")

func _glide_gate() -> void:
	var f := hina
	_reset(f)
	for i in 3:
		_step(f, 0, -1)
	var fastest := 0.0
	var glided := false
	for i in 30:
		_step(f, 0, -1)
		fastest = maxf(fastest, f.vel.y)
		glided = glided or String(f.kv.get("anim", "")) == "glide"
	check(not glided and fastest > 2.5, "hina: up held from takeoff does not glide at the apex (fastest fall %.1f)" % fastest)
	_step(f, 0, 0)
	_step(f, 0, -1)
	check(String(f.kv.get("anim", "")) == "glide", "hina: up released once and pressed again glides")

func _hit_clears() -> void:
	var f := hina
	_takeoff(f)
	_step(f, 0, 0, ["dash"])
	_step(f)
	f.receive_hit(hoshino, M.H(Rect2(), 30.0, 20, 10, 4.0, {"hitstop": 0, "launch": Vector2(2, -4)}), hoshino.position, false)
	f.hitstop = 0
	check(f.state == states.AIRHIT or f.state == states.HIT, "hina: a hit in the dash lands (state %d)" % f.state)
	_step(f)
	check(int(f.kv["dash_t"]) == 0 and String(f.kv["anim"]) == "" and f.air_ok, "hina: a hit clears the dash, its anim and the attack lock")

## Holding back to dash back is also the air block input, so a hit one tick in is blocked and the block ends the dash.
func _back_dash_hit() -> void:
	var f := hina
	_takeoff(f)
	hoshino.position = Vector2(f.position.x + float(f.facing) * 120.0, f.position.y)
	_step(f, -f.facing, 0, ["dash"])
	check(int(f.kv["dash_t"]) > 0 and String(f.kv["anim"]) == "dash_air_back", "hina: the back dash starts with back held")
	var h: Dictionary = M.H(Rect2(), 30.0, 20, 10, 4.0, {"hitstop": 0})
	check(f._can_block(h), "hina: back held in a back dash lets her air block")
	f.receive_hit(hoshino, h, hoshino.position, false)
	f.hitstop = 0
	check(f.state == states.BLOCK and f.block_air, "hina: a hit in the back dash is air blocked (state %d)" % f.state)
	_step(f, -f.facing)
	check(int(f.kv["dash_t"]) == 0 and String(f.kv["anim"]) == "", "hina: the block ends the dash and its anim")

func _hoshino() -> void:
	var f := hoshino
	_takeoff(f)
	var vx0: float = f.vel.x
	_step(f, 0, 0, ["dash"])
	check(is_equal_approx(f.vel.x, vx0) and not f.kv.has("dash_t"), "hoshino: dash in the air does nothing")
	for i in 100:
		_step(f, 0, -1)
	check(String(f.kv.get("anim", "")) == "", "hoshino: holding up never glides or asks for a kit anim")

func _glide_attack() -> void:
	var f := hina
	_reset(f)
	f._set_state(states.JUMP)
	f.position.y = A.GROUND - 700.0
	f.vel = Vector2(0.0, 8.0)
	_step(f)
	_step(f, 0, -1)
	_step(f, 0, -1)
	check(String(f.kv["anim"]) == "glide", "hina: gliding before the attack")
	_step(f, 0, -1, ["light"])
	check(f.state == states.ATTACK, "hina: a light press in the glide starts an air attack")
	var ticks := 0
	while f.state == states.ATTACK and ticks < 80:
		_step(f, 0, -1)
		ticks += 1
	check(f.state == states.JUMP and not f.is_grounded(), "hina: the air attack ends in the air (state %d)" % f.state)
	var again := false
	for i in 5:
		_step(f, 0, -1)
		again = again or String(f.kv.get("anim", "")) == "glide"
	check(not again, "hina: an air attack ends the glide even with up still held")
	_step(f, 0, 0)
	_step(f, 0, -1)
	check(String(f.kv.get("anim", "")) == "glide", "hina: up released and pressed again glides after the attack")

## The dash press on the tick she lands must stay buffered for a ground dash, not zero vel.y and skip _land().
func _dash_on_landing() -> void:
	var f := hina
	_reset(f)
	f._set_state(states.JUMP)
	f.position.y = A.GROUND
	f.vel = Vector2(0.0, 4.0)
	_step(f, 0, 0, ["dash"])
	check(f.state != states.JUMP and int(f.kv["dash_t"]) == 0, "hina: a dash press on the landing tick still lands her (state %d)" % f.state)
	_step(f)
	check(f.state == states.DASH, "hina: the buffered press becomes a ground dash (state %d)" % f.state)
