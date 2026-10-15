extends SceneTree
## The HUD through the first round's stage entry (scripts/fight/fight_hud.gd). The fighters own the frame while the shots and the
## camera pan play: nothing of the HUD is on screen until round_intro runs at the wide beat, then the rails and cards whip in under
## the falling intro_cover. The engine's tick numbers are measured, never assumed: "the shots" are the ticks before the world's
## round_intro_at is set. A stub world drives the facade through the cover values and the cut fields; a real FightScreen then plays
## the entry (shots, whip-in, skip, restart, pause), later rounds and training, and a pixel probe compares the screen with the HUD
## on and off.
## Run: TEST=res://scripts/fight/tests/hud_intro_test.gd MAXLINES=300 zsh tools/sd_test.sh   (a real small window)
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

class StubWorld extends Node:
	var f1: Object = null
	var intro_cut := -1
	var intro_cut_t := -1
	var intro_side := -1
	var intro_cover := 1.0
	var round_intro_at := -1

class BareWorld extends Node:
	var f1: Object = null

class FakeCutin extends Control:
	var level := 0.0
	func strength() -> float:
		return level
	func sync(_w: Node) -> void:
		pass

const GUARD := 1200       # ticks a loop may run before the test gives up on the engine
const RAMP_MAX := 8       # ticks the cover takes to fall once the wide beat starts
const LEAK_PX := 100      # pixels (on a 2 px grid) the HUD-on capture may differ from the HUD-off one beyond the capture noise

var checks := 0
var failures: Array = []
var game: Node
var dbg: Node
var screen: Node
var hud: Control
var real_cutin: Control
var shots := 0            # ticks before round_intro in a measured entry
var natural := 0          # ticks of that entry up to FIGHT!

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("HUD_INTRO_CHECK FAIL ", label)
		failures.append(label)

func near(a: float, b: float, eps := 0.01) -> bool:
	return absf(a - b) <= eps

func _run() -> void:
	create_timer(240.0).timeout.connect(func() -> void:
		print("HUD_INTRO_TEST FAIL watchdog timeout")
		quit(3))
	await process_frame
	game = root.get_node("Game")
	dbg = root.get_node("Dbg")
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	await _open_match("versus2p")
	_gone()
	_stub_world()
	_measure()
	_shots_hidden()
	await _pixels()
	_whip_in()
	_pause()
	_skip()
	_restart()
	await _later_rounds()
	check(BaArt.warnings().is_empty(), "no art warnings: " + str(BaArt.warnings()))
	print("HUD_INTRO_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _open_match(mode: String) -> void:
	dbg.intro_entry = true
	game.session.begin(mode)
	game.session.players[0].merge({"fighter": 10004, "special": 20001}, true)
	game.session.players[1].merge({"fighter": 10005, "special": 23005}, true)
	await game.go("fight", {}, "cut")
	screen = game.stack.back()
	screen.set_physics_process(false)
	hud = screen.hud
	hud.set_process(false)
	real_cutin = hud._cutin

func _gone() -> void:
	check(hud.get("_intro") == null and not ResourceLoader.exists("res://scripts/fight/hud_intro.gd"), "the stage entry has no HUD layer of its own")

# ── the real first round ─────────────────────────────────────────────────────
func _fresh() -> void:
	screen.set("_entered", false)
	screen.f1.human = true
	screen.f2.human = true
	screen._start_round()
	hud._entered = false
	hud._enter_age = 10.0
	hud._banner.active = false     # a banner is drawn out by the frames this synchronous loop never renders
	hud._cutin = real_cutin
	hud._process(0.0)

func _tick(n := 1) -> void:
	for i in n:
		screen._sim_step()
		hud._process(1.0 / 60.0)

func _alpha(n: Control) -> float:
	return n.modulate.a

func _rails_alpha_all(want: float) -> bool:
	for n in hud._dim_nodes:
		if not near(_alpha(n), want, 0.0001):
			return false
	return true

## Nothing but the rails and cards is ever up before round_intro, and those are at alpha 0.
func _overlays_idle() -> bool:
	return not hud._banner.active and hud._flash_col.a <= 0.01 and not hud._cutin.visible and not hud._pause.visible

## Ticks until round_intro has run, and until the intro is over.
func _to_round_intro() -> int:
	var n := 0
	while screen.round_intro_at < 0 and n < GUARD:
		_tick()
		n += 1
	return n

func _to_fight() -> int:
	var n := 0
	while screen.phase == "intro" and n < GUARD:
		_tick()
		n += 1
	return n

func _measure() -> void:
	_fresh()
	check(screen.entry and screen.round_intro_at == -1, "setup: the first round plays the stage entry and round_intro has not run")
	var n := _to_round_intro()
	shots = n
	check(n < GUARD and n > 60 and screen.round_intro_at == n, "round_intro runs on tick %d, after more than the plain 60 tick intro" % n)
	natural = n + _to_fight()
	check(screen.phase == "fight" and natural > n, "and the entry ends in the fight on tick %d" % natural)

func _shots_hidden() -> void:
	_fresh()
	var hidden := true
	var covered := true
	var idle := true
	var asleep := true
	var n := 0
	while true:
		_tick()
		if screen.round_intro_at >= 0 or n > GUARD:
			break
		n += 1
		hidden = hidden and _rails_alpha_all(0.0)
		covered = covered and screen.intro_cover == 1.0
		idle = idle and _overlays_idle()
		asleep = asleep and not hud._entered
	check(n == shots - 1, "the second run plays the same %d ticks of shots" % shots)
	check(covered, "the engine holds intro_cover at 1 until round_intro runs")
	check(hidden, "rails and cards are at alpha 0 on every tick of the shots and the pan")
	check(idle, "no banner, flash, cut-in or pause popup is up on any of them")
	check(asleep, "the entrance has not started before round_intro")

## HUD on against HUD off, with no sim step between the captures: the difference may not exceed the noise of two captures with the
## HUD off. Probed along the shots and on the last tick before round_intro, where the rails sit at home at alpha 0.
func _pixels() -> void:
	_fresh()
	var worst := 0
	var noise := 0
	var last := 0
	var at := 0
	var step := maxi(shots / 8, 1)
	while true:
		_tick()
		if screen.round_intro_at >= 0:
			break
		at += 1
		if at % step == 0 or at == shots - 1:
			var probe: Dictionary = await _probe()
			worst = maxi(worst, int(probe["diff"]))
			noise = maxi(noise, int(probe["noise"]))
			last = int(probe["diff"])
	check(worst <= noise + LEAK_PX, "no pixel of the HUD is on screen through the shots (%d differ, %d are noise)" % [worst, noise])
	check(last <= noise + LEAK_PX, "nor on the last tick before round_intro (%d differ)" % last)
	_tick(30)
	var control: Dictionary = await _probe()
	check(int(control["diff"]) > 1000 and int(control["diff"]) > 20 * (int(control["noise"]) + 1), "control: the same probe sees the HUD once it is up (%d pixels differ)" % int(control["diff"]))

func _grab() -> Image:
	await process_frame
	await process_frame
	return root.get_texture().get_image()

func _differ(a: Image, b: Image) -> int:
	if a.get_data() == b.get_data():
		return 0
	var n := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) > 0.03:
				n += 1
	return n

func _probe() -> Dictionary:
	hud.visible = false
	var off1: Image = await _grab()
	hud.visible = true
	var on: Image = await _grab()
	hud.visible = false
	var off2: Image = await _grab()
	hud.visible = true
	return {"diff": _differ(on, off1), "noise": _differ(off1, off2)}

# ── the whip-in under the falling cover ──────────────────────────────────────
func _whip_in() -> void:
	_fresh()
	_to_round_intro()
	check(hud._entered, "round_intro starts the entrance")
	check(hud._top.position.y < -100.0 and hud._bottom.position.y > 100.0, "the rails start off screen on that tick (%.0f, %.0f)" % [hud._top.position.y, hud._bottom.position.y])
	var prev_y: float = hud._top.position.y
	var rises := true
	var follows := true
	var falls := true
	var prev_cover: float = screen.intro_cover
	var ramp := 0
	var n := 0
	while screen.phase == "intro" and n < GUARD:
		_tick()
		n += 1
		var cover: float = screen.intro_cover
		rises = rises and hud._top.position.y >= prev_y - 0.001
		follows = follows and near(_alpha(hud._top), 1.0 - cover, 0.0001) and _rails_alpha_all(1.0 - cover)
		falls = falls and cover <= prev_cover
		prev_y = hud._top.position.y
		prev_cover = cover
		if cover > 0.0:
			ramp += 1
	check(rises, "the rails only ever move toward home")
	check(follows, "the rails and cards follow 1 minus intro_cover on every tick")
	check(falls and ramp <= RAMP_MAX, "the cover only falls, over %d ticks after round_intro (limit %d)" % [ramp, RAMP_MAX])
	check(screen.phase == "fight" and hud._top.position.y == 0.0 and hud._bottom.position.y == 0.0 and _rails_alpha_all(1.0), "FIGHT!: the rails are home and fully shown")

# ── the facade against a stub world ──────────────────────────────────────────
## alpha = (1 - 0.82 x cut-in) x (1 - cover), whatever the cut fields say.
func _stub_world() -> void:
	var real_world: Node = hud.world
	var fake := FakeCutin.new()
	hud._cutin = fake
	var w := StubWorld.new()
	w.f1 = screen.f1
	hud.world = w
	for shot in [[-1, 1.0], [0, 1.0], [1, 1.0], [2, 1.0]]:
		w.intro_cut = shot[0]
		w.intro_cut_t = 7 if shot[0] >= 0 else -1
		w.intro_side = shot[0] / 2 if shot[0] >= 0 else -1
		w.intro_cover = shot[1]
		hud._process(0.0)
		check(_rails_alpha_all(0.0), "stub: intro_cut %d with the cover at 1 shows no rail or card" % shot[0])
	var prev := -1.0
	var rising := true
	var ramp_ok := true
	for k in RAMP_MAX + 1:
		w.intro_cover = 1.0 - float(k) / float(RAMP_MAX)
		hud._process(0.0)
		var a: float = _alpha(hud._top)
		rising = rising and a >= prev
		prev = a
		ramp_ok = ramp_ok and _rails_alpha_all(1.0 - w.intro_cover)
	check(rising and ramp_ok and prev == 1.0, "stub: a cover falling 1 to 0 in %d steps brings every rail and card from 0 to 1, step by step" % RAMP_MAX)
	w.intro_cut = 1
	w.intro_cover = 0.0
	hud._process(0.0)
	check(_rails_alpha_all(1.0), "stub: the HUD reads the cover, not the cut: a cut with the cover at 0 shows them")
	for level in [0.0, 0.5, 1.0]:
		for cover in [1.0, 0.5, 0.0]:
			fake.level = level
			w.intro_cover = cover
			hud._process(0.0)
			var want: float = (1.0 - 0.82 * level) * (1.0 - cover)
			check(_rails_alpha_all(want), "stub: cut-in %.1f, cover %.1f: every rail and card is %.3f" % [level, cover, want])
	fake.level = 0.0
	for off in [[-0.5, 1.0], [3.0, 0.0]]:
		w.intro_cover = off[0]
		hud._process(0.0)
		check(_rails_alpha_all(off[1]), "stub: a cover of %.1f is clamped to alpha %.0f" % [off[0], off[1]])
	var bare := BareWorld.new()
	bare.f1 = screen.f1
	hud.world = bare
	hud._process(0.0)
	check(_rails_alpha_all(1.0), "a world with no intro_cover shows the rails")
	hud.world = real_world
	hud._cutin = real_cutin
	bare.free()
	w.free()
	fake.free()

# ── pause, skip, restart ─────────────────────────────────────────────────────
func _pause() -> void:
	_fresh()
	_tick(shots / 2)
	var t0: int = screen.phase_t
	screen.set_paused(true)
	_tick(12)
	check(screen.phase_t == t0 and _rails_alpha_all(0.0), "paused mid-shots: the clock holds and the rails stay hidden")
	screen.set_paused(false)
	_tick()
	check(screen.phase_t == t0 + 1 and _rails_alpha_all(0.0), "unpaused: the shots go on, the rails still hidden")
	_fresh()
	_to_round_intro()
	hud._process(1.0 / 60.0)
	check(hud._top.position.y < 0.0, "the rails are on their way in at the wide beat (%.1f)" % hud._top.position.y)
	screen.set_paused(true)
	hud._process(1.0 / 60.0)
	check(hud._top.position.y == 0.0 and hud._bottom.position.y == 0.0, "pausing at the wide beat settles the rails in place, never half way up")
	screen.set_paused(false)
	hud._process(1.0 / 60.0)
	check(hud._top.position.y == 0.0, "and they stay there after")

## A press every tick through the rest of the entry, so the engine's skip lock and where its skip lands do not matter.
func _skip() -> void:
	for at in [shots / 4, shots / 2, shots - 5, shots + 3]:
		_fresh()
		_tick(at)
		var live: bool = screen.round_intro_at < 0
		var total: int = at
		var whip_y := 0.0
		var prev_y := -INF
		var rises := true
		var follows := true
		while screen.phase == "intro" and total < GUARD:
			var was: int = screen.round_intro_at
			screen.on_action("kb1", "confirm")
			_tick()
			total += 1
			if was < 0 and screen.round_intro_at >= 0:
				whip_y = hud._top.position.y
			if screen.round_intro_at >= 0:
				follows = follows and near(_alpha(hud._top), 1.0 - screen.intro_cover, 0.0001) and _rails_alpha_all(1.0 - screen.intro_cover)
				rises = rises and hud._top.position.y >= prev_y - 0.001
				prev_y = hud._top.position.y
		check(screen.phase == "fight" and (total < natural if live else total <= natural), "skip at %d: the press ends the entry on tick %d (it takes %d unskipped)" % [at, total, natural])
		check(hud._entered and screen.round_intro_at >= 0 and follows and rises, "skip at %d: the rails follow 1 minus the cover and only move toward home" % at)
		if live:
			check(whip_y < -100.0 and whip_y > -170.0, "skip at %d: the whip-in starts on the tick round_intro runs (%.0f)" % [at, whip_y])
		_tick(12)
		check(_rails_alpha_all(1.0) and hud._top.position.y > -30.0, "skip at %d: the rails are shown and nearly home 12 ticks on (%.0f)" % [at, hud._top.position.y])

func _restart() -> void:
	for at in [shots / 3, shots * 4 / 5]:
		_fresh()
		_tick(at)
		check(not _rails_alpha_all(1.0) and screen.round_intro_at < 0, "setup: restart at %d, in the shots" % at)
		screen.restart_round()
		hud._process(1.0 / 60.0)
		check(screen.intro_cover == 0.0 and _rails_alpha_all(1.0) and hud._entered, "restart at %d: no cover, the plain intro starts the rails" % at)
		var n := _to_fight()
		check(screen.phase == "fight" and n < shots, "restart at %d: a plain intro, shorter than the entry, then the fight (%d ticks)" % [at, n])

# ── later rounds and training ────────────────────────────────────────────────
func _later_rounds() -> void:
	_fresh()
	_to_fight()
	for n in [2, 3]:
		screen.round_no = n
		screen._start_round()
		hud._process(1.0 / 60.0)
		check(not screen.entry and screen.intro_cover == 0.0, "round %d: the engine plays the plain intro" % n)
		check(_rails_alpha_all(1.0) and hud._top.position.y == 0.0 and hud._bottom.position.y == 0.0, "round %d: the rails stay where they are, the entrance does not replay" % n)
		var home := true
		for k in GUARD:
			if screen.phase != "intro":
				break
			_tick()
			home = home and hud._top.position.y == 0.0
		check(home and screen.phase == "fight", "round %d: nor during the intro" % n)
	await _open_match("training")
	screen._start_round()
	hud._process(1.0 / 60.0)
	check(not screen.entry and screen.intro_cover == 0.0, "training: the plain intro, whatever Dbg.intro_entry says")
	check(_rails_alpha_all(1.0) and hud._entered, "training: no cover, the rails whip in as before")
	_to_fight()
	check(screen.phase == "fight" and _rails_alpha_all(1.0), "training: still shown after the intro")
