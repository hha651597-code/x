extends SceneTree
## Four motion defects found on 2026-10-15, each on the real FightScreen with its physics process off:
## the last round's winner sparkles are gone when the next round starts, hit sparks and damage numbers stand still under
## the pause menu and the hit boxes still redraw there, consecutive damage numbers stack instead of overlapping,
## and a hit's first drawn frame carries the full 0.55 flash.
## Run with TEST=res://scripts/models/tests/motion_fixes_test.gd tools/sd_test.sh (a real small window).

const HINA := 10004
const HOSHINO := 10005
const NEUTRAL := 10003

var checks := 0
var failures: Array = []
var game: Node
var screen: Node
var FxScript: GDScript
var PartsScript: GDScript

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("MOTION_FIXES_CHECK FAIL ", label)
		failures.append(label)

func _run() -> void:
	create_timer(300.0).timeout.connect(func() -> void:
		print("MOTION_FIXES FAIL watchdog timeout")
		quit(3))
	await process_frame
	FxScript = load("res://scripts/fight/fx.gd")
	PartsScript = load("res://scripts/fight/fx_particles.gd")
	game = root.get_node("Game")
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	root.get_node("Dbg").intro_entry = false
	await _boot()
	_stale_sparkles()
	_stacked_numbers()
	_flash_peak()
	await _pause_stills_the_world()
	print("MOTION_FIXES ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _boot() -> void:
	game.session.begin("versus2p")
	game.session.players[0]["fighter"] = HINA
	game.session.players[1]["fighter"] = HOSHINO
	game.session.players[0]["special"] = NEUTRAL
	game.session.players[1]["special"] = NEUTRAL
	await game.go("fight", {}, "cut")
	screen = game.stack.back()
	screen.set_physics_process(false)
	for f in screen.fighters:
		f.human = false
	screen.brains = [null, null]

func _digits() -> Array:
	return screen.fx_layer.get_children().filter(func(c: Node) -> bool: return c.get_script() == FxScript and c.data.get("digits", false))

func _clear_fx() -> void:
	for c in screen.fx_layer.get_children():
		if c.get_script() == FxScript:
			c.free()

# the last round's winner sparkles
func _stale_sparkles() -> void:
	var parts: Node = PartsScript.of(screen.fx_layer)
	for i in 8:
		parts.emit(PartsScript.K.STAR, Vector2(i * 20.0, 300.0), Vector2(0, -26.0), 0.7, 14.0, Color.WHITE)
	check(parts._ps.size() == 8, "the winner sparkles are emitted")
	screen._start_round()
	check(parts._ps.is_empty(), "a new round starts without the last round's sparkles (%d left)" % parts._ps.size())

# consecutive damage numbers
func _stacked_numbers() -> void:
	_clear_fx()
	var at := Vector2(100.0, 290.0)
	screen.fx_damage(at, 25.0, false)
	screen.fx_damage(at, 29.0, false)
	var live := _digits()
	check(live.size() == 2, "two damage numbers are alive")
	if live.size() == 2:
		check(live[0].position.y - live[1].position.y >= 70.0, "the second damage number clears the first once it has risen (%.0f px)" % (live[0].position.y - live[1].position.y))
	_clear_fx()
	screen.fx_damage(at, 25.0, false)
	screen.fx_damage(at, 29.0, false)
	_digits()[0].age = 0.65     # the first is fading out: the next number takes the low row again, the second stays up
	screen.fx_damage(at, 31.0, false)
	var rows := _digits().map(func(c: Node) -> float: return c.position.y)
	check(rows.size() == 3 and rows[2] == at.y and rows[1] < at.y, "a rapid combo alternates two rows (%s)" % [rows])
	_clear_fx()

# a hit's first drawn frame
func _flash_peak() -> void:
	var f: Node = screen.f2
	check(f.view.sd_mode, "the flash probe runs on an SD fighter")
	f._flash = 0.0
	f._process(1.0 / 60.0)
	f._flash = 0.55
	f._process(1.0 / 60.0)
	var look: Array = f.view.sd_actor._look
	check(absf(float(look[0]) - 0.55) < 0.001, "a hit's first drawn frame carries the full flash (%.2f)" % float(look[0]))
	check(absf(f._flash - 0.40) < 0.001, "the flash still fades by 0.15 per frame (%.2f)" % f._flash)
	f._flash = 0.0

# the pause menu
func _pause_stills_the_world() -> void:
	_clear_fx()
	screen.fx_damage(Vector2(0, 290), 25.0, false)
	var num: Node = _digits()[0]
	var spark: Node = FxScript.make(screen.fx_layer, "ring", Vector2(0, 200), 5.0)
	await process_frame
	check(num.age > 0.0 and spark.age > 0.0, "an Fx ages while the game runs")
	screen.set_paused(true)
	await process_frame
	var n_age: float = num.age
	var s_age: float = spark.age
	for i in 5:
		await process_frame
	check(num.age == n_age and spark.age == s_age, "damage numbers and sparks stand still under the pause menu")
	check(screen.fighters_layer.process_mode == Node.PROCESS_MODE_DISABLED and screen.stage_node.process_mode == Node.PROCESS_MODE_DISABLED, "the fighters and the stage stop with the pause")
	var back: Node2D = screen.f1.view.back
	var draws := [0]
	var drawn: Callable = back.cb
	back.cb = func(ci: Node2D) -> void:
		draws[0] += 1
		drawn.call(ci)
	await RenderingServer.frame_post_draw
	var before: int = draws[0]
	screen.debug_boxes = true
	await RenderingServer.frame_post_draw
	check(draws[0] > before, "toggling Hitboxes in the pause menu redraws the boxes of a paused world")
	back.cb = drawn
	screen.debug_boxes = false
	screen.set_paused(false)
	await process_frame
	await process_frame
	check(not is_instance_valid(num) or num.age > n_age, "the Fx age again after the resume")
	check(screen.fx_layer.process_mode == Node.PROCESS_MODE_INHERIT and screen.fighters_layer.process_mode == Node.PROCESS_MODE_INHERIT, "the resume restores the world")
	# a pause inside the EX freeze hands the world back to the freeze, not to the game
	screen._set_world_frozen(true)
	screen.set_paused(true)
	screen.set_paused(false)
	check(screen.world_frozen and screen.fx_layer.process_mode == Node.PROCESS_MODE_DISABLED, "resuming from a pause inside the EX freeze keeps the world frozen")
	screen._set_world_frozen(false)
	check(not screen.world_frozen and screen.fx_layer.process_mode == Node.PROCESS_MODE_INHERIT, "the end of the freeze restores the world")
	screen.set_paused(true)
	screen.restart_round()
	check(not screen.paused and screen.fighters_layer.process_mode == Node.PROCESS_MODE_INHERIT, "restarting the round from the pause menu restores the world")
	_clear_fx()
