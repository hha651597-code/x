extends SceneTree
## Super and ult tiers: chord timing, costs, the lone EX, the generic super and the HUD labels. Hina and Hoshino only.
## Run with TEST=res://scripts/models/tests/super_test.gd tools/sd_test.sh (a real small window).
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

var checks := 0
var failures: Array = []
var screen: Node
var states: Dictionary
var FI: GDScript
var A: GDScript

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("SUPER_CHECK FAIL ", label)
		failures.append(label)

func _run() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		print("SUPER_TEST FAIL watchdog timeout")
		quit(3))
	await process_frame
	FI = load("res://scripts/fight/fight_input.gd")
	A = load("res://scripts/fight/arena.gd")
	var game: Node = root.get_node("Game")
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	game.session.begin("training")
	game.session.players[0]["fighter"] = 10004
	game.session.players[1]["fighter"] = 10005
	await game.go("fight", {}, "cut")
	screen = game.stack.back()
	screen.set_physics_process(false)
	screen.phase = "fight"
	states = screen.f1.get_script().S
	for f in [screen.f1, screen.f2]:
		_tiers(f)
	_generic(screen.f2)
	_pace(screen.f1)
	_hud()
	print("SUPER_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _idle(f: Node) -> void:
	f.reset_round(f.position.x, f.facing)
	f._set_state(states.IDLE)
	f.input = FI.new()
	f.sf = 0

## Feeds `ticks` ticks of input; schedule = {tick: [buttons pressed on that tick]}.
func _drive(f: Node, meter: float, schedule: Dictionary, ticks: int, y := 0) -> void:
	_idle(f)
	f.meter = meter
	for t in ticks:
		f.input = FI.from_held(f.input, 0, y, schedule.get(t, []))
		f.tick()

func _tiers(f: Node) -> void:
	var who := String(f.data["key"])
	check(is_equal_approx(float(f.moves["ex"]["cost"]), 100.0), who + ": the ult costs 100")
	check(is_equal_approx(float(f.moves["super"]["cost"]), 50.0), who + ": the super costs 50")
	check(is_equal_approx(float(f.moves["super_down"]["cost"]), 50.0), who + ": the down super costs 50")
	_drive(f, 50.0, {0: ["skill", "ex"]}, 2)
	check(f.move_key == "super" and is_zero_approx(f.meter), who + ": skill + ex on one frame at 50 is the super")
	_drive(f, 50.0, {0: ["skill", "ex"]}, 2, 1)
	check(f.move_key == "super_down", who + ": down + skill + ex is the down super")
	_drive(f, 60.0, {0: ["skill"], 2: ["ex"]}, 4)
	check(f.move_key == "super" and is_equal_approx(f.meter, 10.0), who + ": ex 2 frames after skill upgrades it to the super")
	_drive(f, 60.0, {0: ["skill"], 5: ["ex"]}, 7)
	check(f.move_key == "skill" and is_equal_approx(f.meter, 60.0), who + ": ex 5 frames after skill is too late")
	_drive(f, 60.0, {0: ["ex"], 3: ["skill"]}, 5)
	check(f.move_key == "super", who + ": skill 3 frames after ex is still the super")
	_drive(f, 100.0, {0: ["ex"], 2: ["skill"]}, 4)
	check(f.move_key == "super" and is_equal_approx(f.meter, 50.0), who + ": at full meter, ex then skill is the super")
	_drive(f, 100.0, {0: ["ex"]}, 2)
	check(f.state != states.ATTACK, who + ": a lone ex at full meter waits for a skill press")
	_drive(f, 100.0, {0: ["ex"], 1: ["ex"], 3: ["ex"]}, 5)
	check(f.move_key == "ex" and is_zero_approx(f.meter), who + ": a lone ex at full meter fires the ult after 3 frames, mashing or not")
	_idle(f)
	f.meter = 100.0
	f._set_state(states.HIT)
	f.hitstun = 7
	for t in 12:
		f.input = FI.from_held(f.input, 0, 0, {0: ["skill"], 4: ["skill", "ex"]}.get(t, []))
		f.tick()
	check(f.move_key == "super" and is_equal_approx(f.meter, 50.0), who + ": a stale skill press does not spoil a fresh skill + ex")
	_drive(f, 99.0, {0: ["ex"]}, 10)
	check(f.state != states.ATTACK and is_equal_approx(f.meter, 99.0), who + ": a lone ex below full meter does nothing")
	_drive(f, 40.0, {0: ["skill", "ex"]}, 2)
	check(f.move_key == "skill" and is_equal_approx(f.meter, 40.0), who + ": below 50 the chord is just the skill")
	_idle(f)
	f.meter = 50.0
	f.position.y = A.GROUND - 200.0
	f._set_state(states.JUMP)
	for t in 2:
		f.input = FI.from_held(f.input, 0, 0, ["skill", "ex"] if t == 0 else [])
		f.tick()
	check(f.move_key != "super" and is_equal_approx(f.meter, 50.0), who + ": no super in the air")
	f.position.y = A.GROUND

## The generic super, on Hoshino with her own supers taken away.
func _generic(f: Node) -> void:
	f.moves.erase("super")
	f.moves.erase("super_down")
	var base := float(f.moves["skill"]["spawns"][0]["hit"]["dmg"])
	_drive(f, 50.0, {0: ["skill", "ex"]}, 2)
	check(f.move_key == "skill" and f.powered and is_zero_approx(f.meter), "generic: the chord plays the skill powered for 50")
	check(f.armor_hits_left == 1, "generic: the powered skill has armor against one hit")
	f.moves["skill"]["armor"] = {"from": 0, "to": 10, "hits": 3, "dmg": 0.5}
	_drive(f, 50.0, {0: ["skill", "ex"]}, 2)
	check(f.armor_hits_left == 3, "generic: a skill with its own armor keeps it")
	f.moves["skill"].erase("armor")
	check(is_equal_approx(f.hit_mult(false), f.dmg_mult() * 1.3) and is_equal_approx(f.hit_mult(true), f.dmg_mult()),
		"generic: melee hits get +30% at impact, projectiles do not get it twice")
	var before: int = screen.projectiles.size()
	var spawned: Dictionary = {}
	for t in 40:
		f.input = FI.from_held(f.input, 0, 0, [])
		f.tick()
		if screen.projectiles.size() > before and spawned.is_empty():
			spawned = screen.projectiles[before].hit
	check(not spawned.is_empty() and is_equal_approx(float(spawned["dmg"]), base * 1.3), "generic: a powered pellet carries +30% from spawn")
	check(is_equal_approx(float(f.moves["skill"]["spawns"][0]["hit"]["dmg"]), base), "generic: the move's own hit data is untouched")
	for t in 40:
		f.input = FI.from_held(f.input, 0, 0, [])
		f.tick()
	check(not f.powered, "generic: powered ends with the move")
	_drive(f, 60.0, {0: ["skill"], 2: ["ex"]}, 4)
	check(f.move_key == "skill" and f.powered and is_equal_approx(f.meter, 10.0), "generic: ex just after skill powers it up in place")

## Meter earned by fighting is paced (hits, blocks, counters, armor); the meter still caps at 100 and the tiers stay at 50 and 100.
func _pace(f: Node) -> void:
	f.meter = 0.0
	f.gain_meter(10.0)
	check(is_equal_approx(f.meter, 10.0 * A.METER_PACE) and A.METER_PACE < 1.0, "pace: 10 meter earned is %.1f" % f.meter)
	f.meter = 99.0
	f.gain_meter(10.0)
	check(f.meter == A.MAX_METER and A.SUPER_COST == 50.0 and A.EX_COST == 100.0, "pace: the meter caps at 100 and the tiers keep their costs")

func _hud() -> void:
	var hud: GDScript = load("res://scripts/fight/fight_hud.gd")
	check(hud.meter_label(49.0) == "EX", "hud: 49 reads EX")
	check(hud.meter_label(50.0) == "SUPER", "hud: 50 reads SUPER")
	check(hud.meter_label(99.0) == "SUPER", "hud: 99 reads SUPER")
	check(hud.meter_label(100.0) == "EX READY", "hud: 100 reads EX READY")
