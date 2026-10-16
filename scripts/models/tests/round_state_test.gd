extends SceneTree
## The round and match state machine on the real FightScreen, one _sim_step at a time with its physics process off: Restart
## Round in the K.O. and round-end windows, what may still decide a round after TIME UP, the loser's assist after a K.O., a heal
## pool on a fighter who is already dead, resuming from pause with a button held, TIME UP against K.O., the K.O. flash against its
## impact frame, the match stats across a restart, infinite EX through a cut-in, and a sweep of every kit's projectile moves with
## the foe at every distance the push lets it stand (point-blank rounds must still hit).
## Run with TEST=res://scripts/models/tests/round_state_test.gd tools/sd_test.sh (a real small window).
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.
## It never finishes a match: each scenario stops before round_end's 150 ticks would call _finish_match, and the run ends by
## checking that records.json is untouched.

const HINA := 10004
const HOSHINO := 10005
const NEUTRAL := 10003    # an assist nobody calls in the scenarios that name it
const VEHICLE := 20012    # Rolling Strike: a delayed strike that sweeps across the ring
const VOLLEY := 10009     # Covering Fire: five rounds from the caster
const HEALER := 23001     # First Aid: a heal pool of 14 percent of max hp
const PROJ_TAIL := 90     # ticks a sweep runs past the end of the move for rounds still in flight
const LIFT := 60.0        # how high an air move hovers: its rounds leave from the chest of a standing foe

var checks := 0
var failures: Array = []
var game: Node
var sfx: Node
var dbg: Node
var controls: Node
var screen: Node
var f1: Node
var f2: Node
var S: Dictionary
var FI: GDScript
var M: GDScript
var A: GDScript
var FighterScript: GDScript
var FxScript: GDScript
var FlashScript: GDScript
var KitsScript: GDScript
var _pend := {}
var _records_before := ""

func _initialize() -> void:
	call_deferred("_run")

## A trailing "(...)" in a label is the measured detail: printed on a failure, left out of the check's name.
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("ROUND_STATE_CHECK FAIL ", label)
		var cut := label.rfind(" (")
		failures.append(label.substr(0, cut) if label.ends_with(")") and cut > 0 else label)

func _run() -> void:
	create_timer(900.0).timeout.connect(func() -> void:
		print("ROUND_STATE FAIL watchdog timeout")
		quit(3))
	await process_frame
	FI = load("res://scripts/fight/fight_input.gd")
	M = load("res://scripts/fight/movesets.gd")
	A = load("res://scripts/fight/arena.gd")
	FighterScript = load("res://scripts/fight/fighter.gd")
	FxScript = load("res://scripts/fight/fx.gd")
	FlashScript = load("res://scripts/fight/fx_flash.gd")
	KitsScript = load("res://scripts/fight/kits.gd")
	game = root.get_node("Game")
	sfx = root.get_node("Sfx")
	dbg = root.get_node("Dbg")
	controls = root.get_node("Controls")
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	_records_before = FileAccess.get_file_as_string("user://records.json")
	dbg.intro_entry = false
	await _boot("versus2p", HINA, HOSHINO, NEUTRAL, NEUTRAL)
	_restart_round()
	_time_up()
	_trade()
	_focus_out()
	_ko_buffer()
	_cancelled_bullets()
	_fresh_round()
	_hitstop_press()
	_resume_from_pause()
	_overkill_and_ko_time()
	_ko_flash()
	_stats_restart()
	await _boot("versus2p", HINA, HOSHINO, NEUTRAL, VEHICLE)
	_late_assist("strike", 14)
	await _boot("versus2p", HINA, HOSHINO, NEUTRAL, VOLLEY)
	_late_assist("volley", 8)
	await _boot("versus2p", HOSHINO, HINA, NEUTRAL, HEALER)
	_heal_revive()
	await _boot("training", HINA, HOSHINO, NEUTRAL, NEUTRAL)
	_training_cutin()
	await _boot("training", HINA, HOSHINO, NEUTRAL, NEUTRAL)
	_sweep()
	check(not screen.match_over, "no scenario finished a match")
	check(FileAccess.get_file_as_string("user://records.json") == _records_before, "records.json is untouched")
	print("ROUND_STATE ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

# helpers
func _boot(mode: String, p1: int, p2: int, sp1: int, sp2: int) -> void:
	game.session.begin(mode)
	game.session.players[0]["fighter"] = p1
	game.session.players[1]["fighter"] = p2
	game.session.players[0]["special"] = sp1
	game.session.players[1]["special"] = sp2
	await game.go("fight", {}, "cut")
	screen = game.stack.back()
	screen.set_physics_process(false)
	f1 = screen.f1
	f2 = screen.f2
	S = f1.get_script().S
	for f in [f1, f2]:
		f.human = false
	screen.brains = [null, null]

## Both fighters' input for the next tick only: the screen reads f.input as it stands, so a button not named here is released.
func _press(f: Node, btns: Array, x := 0, y := 0) -> void:
	_pend[f.slot] = [x, y, btns]

func _tick(n := 1) -> void:
	for i in n:
		for f in screen.fighters:
			var p: Array = _pend.get(f.slot, [0, 0, []])
			f.input = FI.from_held(f.input, p[0], p[1], p[2])
		_pend.clear()
		screen._sim_step()

func _to_phase(ph: String, cap := 1500) -> void:
	var n := 0
	while screen.phase != ph and n < cap and not screen.match_over:
		_tick()
		n += 1

## A first or later round at the start of its fight, both fighters idle, `x1` and `x2` apart, nothing carried over.
func _new_round(wins := [0, 0], round_no := 1, x1 := -40.0, x2 := 40.0) -> void:
	_reset_match(wins, round_no)
	screen._start_round()
	_to_phase("fight")
	_place(x1, x2)

func _reset_match(wins: Array, round_no: int) -> void:
	_pend.clear()
	screen.wins = wins.duplicate()
	screen.round_no = round_no
	screen.match_over = false
	screen.paused = false
	screen._stats.clear()
	for f in screen.fighters:
		f.stat_damage_dealt = 0.0
		f.stat_max_combo = 0
		f.stat_hits = 0
	_clear_fx()

func _clear_fx() -> void:
	for c in screen.fx_layer.get_children():
		if c.get_script() == FxScript:
			c.free()

func _place(x1: float, x2: float) -> void:
	for f in screen.fighters:
		f._set_state(S.IDLE)
		f.hitstop = 0
		f.invuln = 0
		f.vel = Vector2.ZERO
		f.input = FI.new()
		f.meter = 0.0
	f1.position.x = x1
	f2.position.x = x2
	f1.facing = 1 if x2 > x1 else -1
	f2.facing = -f1.facing

## P1 lands a light on a P2 with 5 hp left, and the K.O. plays out until P2 is down.
func _kill_f2() -> void:
	f2.hp = 5.0
	_press(f1, ["light"])
	_tick(40)

func _kill_f1() -> void:
	f1.hp = 5.0
	_press(f2, ["light"])
	_tick(40)

func _restart() -> void:
	screen.set_paused(true)
	screen.hud.pause_activate(1)

func _wins() -> String:
	return str(screen.wins)

func _flash_alpha() -> float:
	return (screen.hud.get("_flash_col") as Color).a

# Restart Round
func _restart_round() -> void:
	_new_round()
	_kill_f2()
	_to_phase("round_end")
	check(screen.wins == [1, 0], "setup: P1's K.O. banks the win (wins %s)" % _wins())
	_tick(20)
	_restart()
	check(screen.wins == [0, 0], "Restart Round in round_end takes the banked win back (wins %s)" % _wins())
	check(screen.phase == "intro" and screen.round_no == 1 and not screen.paused, "Restart Round in round_end replays round 1 (phase %s, round %d)" % [screen.phase, screen.round_no])
	_to_phase("fight")
	_place(-40.0, 40.0)
	_kill_f1()
	_to_phase("round_end")
	check(screen.wins == [0, 1], "the replayed round counts once: P2's win is the only win (wins %s)" % _wins())

	# match point: P1 takes round 3 for [2, 1], restarts, and P2 wins the replay. The match is then P2's on the replay, not a 2-2 tie.
	_new_round([1, 1], 3)
	_kill_f2()
	_to_phase("round_end")
	check(screen.wins == [2, 1], "setup: round 3 banks [2, 1] (wins %s)" % _wins())
	_restart()
	check(screen.wins == [1, 1] and screen.round_no == 3, "Restart Round at match point goes back to [1, 1] in round 3 (wins %s, round %d)" % [_wins(), screen.round_no])
	_to_phase("fight")
	_place(-40.0, 40.0)
	_kill_f1()
	_to_phase("round_end")
	check(screen.wins == [1, 2], "the replay decides it: [1, 2], not a tie (wins %s)" % _wins())
	check(not screen.match_over, "the replay is not over before its round_end ends")

	# a DRAW banks nothing, so Restart Round leaves the wins alone
	_new_round([1, 0], 2)
	f1.hp = 500.0
	f2.hp = 500.0
	screen.timer_frames = 3
	_to_phase("round_end")
	check(screen.wins == [1, 0] and int(screen._stats.get("last_winner", -1)) == 0, "setup: TIME UP at equal hp is a draw and banks nothing (wins %s)" % _wins())
	_restart()
	check(screen.wins == [1, 0] and screen.round_no == 2, "Restart Round after a draw keeps the wins and the round (wins %s, round %d)" % [_wins(), screen.round_no])

	# in the K.O. window nothing is banked yet: the round restarts whole with the wins as they were
	_new_round()
	_kill_f2()
	_to_phase("ko")
	_tick(10)
	check(screen.phase == "ko" and screen.wins == [0, 0], "setup: the K.O. window banks nothing yet (phase %s, wins %s)" % [screen.phase, _wins()])
	_restart()
	check(screen.wins == [0, 0] and screen.phase == "intro" and screen.round_no == 1, "Restart Round in the K.O. window keeps the wins (wins %s, phase %s)" % [_wins(), screen.phase])
	check(f1.hp == f1.max_hp and f2.hp == f2.max_hp and f2.state == S.INTRO, "Restart Round in the K.O. window stands both fighters up at full hp")
	check(screen.slowmo == 0, "Restart Round in the K.O. window ends the slow-mo")
	_to_phase("fight")
	_place(-40.0, 40.0)
	_kill_f2()
	_to_phase("round_end")
	check(screen.wins == [1, 0], "after a K.O. restart the replay banks one win (wins %s)" % _wins())

	# the stage entry's cuts: a restart there must still start the ready beat and reset what the HUD reads of the intro
	dbg.intro_entry = true
	screen._entered = false
	_reset_match([0, 0], 1)
	screen._start_round()
	check(screen.entry and screen.phase == "intro", "setup: the first round plays the stage entry")
	_tick(150)
	check(screen.intro_cut == 1 and screen.round_intro_at == -1, "setup: in P2's solo shot the ROUND band has not been asked for (shot %d, at %d)" % [screen.intro_cut, screen.round_intro_at])
	_restart()
	check(not screen.entry and screen.intro_len == 60 and screen.phase == "intro" and screen.phase_t == 0, "Restart Round in the entry plays the 60 tick ready beat")
	check(screen.round_intro_at == 0 and screen.intro_cut == -1 and screen.intro_cover == 0.0, "Restart Round in the entry resets the HUD's intro state (at %d, cut %d, cover %.2f)" % [screen.round_intro_at, screen.intro_cut, screen.intro_cover])
	check(not f1.entry_cuts and not f2.entry_cuts, "Restart Round in the entry clears the fighters' cut flag")
	_tick(60)
	check(screen.phase == "fight", "the ready beat after the restart ends in FIGHT")
	dbg.intro_entry = false

# Time up
func _time_up() -> void:
	# a swing that is active after the buzzer
	_new_round()
	f1.hp = 510.0
	f2.hp = 500.0
	screen.timer_frames = 4
	_press(f2, ["light"])
	_tick(6)
	check(screen.phase == "ko", "setup: the buzzer sounded (phase %s)" % screen.phase)
	_to_phase("round_end")
	check(screen.wins == [1, 0], "a swing that lands after TIME UP does not decide the round (wins %s, f1 %.1f, f2 %.1f)" % [_wins(), f1.hp, f2.hp])

	# a round in flight: P1 trails 500 to 510 and fires from across the ring
	_new_round([0, 0], 1, -300.0, 300.0)
	f1.hp = 500.0
	f2.hp = 510.0
	screen.timer_frames = 20
	_press(f1, ["skill"])
	var shots := false
	for i in 40:
		_tick()
		shots = shots or screen.projectiles.size() > 0
	_to_phase("round_end")
	check(shots, "setup: a round was in flight at the buzzer")
	check(screen.wins == [0, 1], "a projectile that lands after TIME UP does not decide the round (wins %s, f2 %.1f)" % [_wins(), f2.hp])

	# a buffered EX that would start a cut-in under the TIME UP banner
	_new_round()
	f1.hp = 510.0
	f2.hp = 500.0
	f2.meter = 100.0
	screen.timer_frames = 2
	_press(f2, ["ex"])
	var froze := false
	for i in 12:
		_tick()
		froze = froze or screen.time_stop > 0 or screen.world_frozen
	check(not froze and f2.state != S.ATTACK, "a buffered EX at the buzzer starts no cut-in (frozen %s, f2 %s)" % [str(froze), f2.state_name()])
	_to_phase("round_end")
	check(screen.wins == [1, 0] and f1.hp == 510.0, "a buffered EX at the buzzer does not decide the round (wins %s, f1 %.1f)" % [_wins(), f1.hp])

	# a heal pool that keeps running through the banner
	_new_round([0, 0], 1, -300.0, 300.0)
	f1.hp = 510.0
	f2.hp = 500.0
	f2.heal_pool = 140.0
	screen.timer_frames = 3
	_to_phase("round_end")
	check(screen.wins == [1, 0], "a heal pool running through TIME UP does not decide the round (wins %s, f2 %.1f)" % [_wins(), f2.hp])

	# the plain case and the draw still work
	_new_round([0, 0], 1, -300.0, 300.0)
	f1.hp = 400.0
	f2.hp = 500.0
	screen.timer_frames = 3
	_to_phase("round_end")
	check(screen.wins == [0, 1], "TIME UP: the fighter with more hp takes the round (wins %s)" % _wins())
	_new_round([0, 0], 1, -300.0, 300.0)
	f1.hp = 500.0
	f2.hp = 500.0
	screen.timer_frames = 3
	_to_phase("round_end")
	check(screen.wins == [0, 0], "TIME UP at equal hp is a draw (wins %s)" % _wins())

	# nothing lands in the K.O. or round_end phases
	_new_round()
	var h: Dictionary = M.H(Rect2(), 50.0, 14, 10, 3.0, {"hitstop": 0})
	check(String(f2.receive_hit(f1, h, f1.position, false)) == "hit", "setup: a hit lands in the fight phase")
	for ph in ["ko", "round_end"]:
		_place(-40.0, 40.0)
		f2.hp = f2.max_hp
		screen.phase = ph
		var hp := float(f2.hp)
		check(String(f2.receive_hit(f1, h, f1.position, false)) == "miss" and f2.hp == hp, "no hit lands in the %s phase" % ph)
	screen.phase = "fight"

# rounds that land on the same tick
## Two lethal rounds that reach their targets on one tick are a trade: both fighters go down. Only a fighter who was already down
## when the tick began stops firing.
func _trade() -> void:
	_new_round([0, 0], 1, -200.0, 200.0)
	f1.hp = 5.0
	f2.hp = 5.0
	var h: Dictionary = M.H(Rect2(), 50.0, 14, 10, 3.0, {"hitstop": 0})
	for f in [f1, f2]:
		screen.spawn_projectile(f, M._spawn(0, Vector2(0, -150.0), Vector2(20, 0), h, {"size": Vector2(30, 10)}))
	screen.projectiles[0].position = Vector2(f2.position.x - 50.0, A.GROUND - 150.0)
	screen.projectiles[1].position = Vector2(f1.position.x + 50.0, A.GROUND - 150.0)
	screen._tick_projectiles([])
	check(f1.hp <= 0.0 and f2.hp <= 0.0, "two lethal rounds that land on the same tick trade (f1 %.1f, f2 %.1f)" % [f1.hp, f2.hp])

	# a lethal swing and a lethal round on one tick trade too
	_new_round()
	f1.hp = 5.0
	f2.hp = 5.0
	_press(f1, ["light"])
	var n := 0
	while not (f1.state == S.ATTACK and f1.mf == int(f1.move["startup"]) - 1) and n < 60:
		_tick()
		n += 1
	screen.spawn_projectile(f2, M._spawn(0, Vector2(0, -150.0), Vector2(20, 0), h, {"size": Vector2(30, 10)}))
	screen.projectiles[0].position = Vector2(f1.position.x + 50.0, A.GROUND - 150.0)
	_tick()
	check(f1.hp <= 0.0 and f2.hp <= 0.0, "a lethal swing and a lethal round on the same tick trade (f1 %.1f, f2 %.1f)" % [f1.hp, f2.hp])

## Losing the window focus pauses a played match; a scripted run (tests, step files) and a finished match are left alone.
func _focus_out() -> void:
	var sess: GDScript = game.session.get_script()
	var real: String = sess.settings_path
	_new_round()
	screen.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not screen.paused, "a scripted run does not pause on focus loss")
	sess.settings_path = "user://zz_focus.cfg"
	screen.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(screen.paused, "losing the window focus pauses the fight")
	screen.set_paused(false)
	screen.match_over = true
	screen.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	screen.match_over = false
	sess.settings_path = real
	check(not screen.paused, "a finished match does not pause on focus loss")

## An EX buffered when the K.O. lands must not start the ult under the banner.
func _ko_buffer() -> void:
	_new_round()
	f2.meter = 100.0
	_press(f2, ["ex"])
	_tick()
	f1._ko()
	var froze := false
	for i in 12:
		_tick()
		froze = froze or screen.time_stop > 0 or screen.world_frozen
	check(not froze and f2.meter >= 100.0, "a buffered EX at the K.O. starts no cut-in (frozen %s, meter %.1f)" % [str(froze), f2.meter])

## A cancelled round is dead for the rest of the step: two sim steps in one engine frame must not move it again.
func _cancelled_bullets() -> void:
	_new_round([0, 0], 1, -300.0, 300.0)
	var h: Dictionary = M.H(Rect2(), 50.0, 14, 10, 3.0, {"hitstop": 0})
	for f in [f1, f2]:
		screen.spawn_projectile(f, M._spawn(0, Vector2(0, -150.0), Vector2(20, 0), h, {"size": Vector2(30, 10)}))
	screen.projectiles[0].position = Vector2(-10.0, A.GROUND - 150.0)
	screen.projectiles[1].position = Vector2(10.0, A.GROUND - 150.0)
	var shots: Array = screen.projectiles.duplicate()
	screen._tick_projectiles([])
	check(shots[0].dead and shots[1].dead, "setup: two opposing rounds cancel")
	var at: Vector2 = shots[0].position
	screen._tick_projectiles([])
	check(shots[0].position == at, "a cancelled round does not move again before it is freed (%s -> %s)" % [at, shots[0].position])

## The next round starts clean: no juggle count, no half-played CPU plan.
func _fresh_round() -> void:
	_new_round()
	var brain: RefCounted = (load("res://scripts/fight/cpu_brain.gd") as GDScript).new()
	brain.setup(f1, f2, 2, 7)
	screen.brains = [brain, null]
	f1.juggle = 3
	brain._taps.append({"btn": "heavy", "wait": 2})
	brain._plan_t = 20
	brain._block_t = 9
	brain.prev.held["light"] = true
	screen._start_round()
	check(f1.juggle == 0, "a new round starts with no juggle count (%d)" % f1.juggle)
	check(brain._taps.is_empty() and brain._plan_t == 0 and brain._block_t == 0 and not brain.prev.held["light"], "a new round clears the CPU brain's plan")
	screen.brains = [null, null]

## A button tapped while the fighter is held in hitstop still reaches the 7 tick buffer.
func _hitstop_press() -> void:
	_new_round()
	f1.hitstop = 6
	_press(f1, ["heavy"])
	_tick(8)
	check(f1.state == S.ATTACK, "a heavy tapped in hitstop starts when the hitstop ends (%s)" % f1.state_name())

# the loser's assist
func _late_assist(kind: String, late: int) -> void:
	# P2 calls the assist and P1 lands the lethal light `blow` ticks later: at 2 nothing has left yet, at `late` it is on its way
	for blow in [2, late]:
		_new_round()
		f1.hp = 30.0 if blow == 2 else 60.0     # enough to survive the rounds that land before the lethal blow
		f2.hp = 5.0
		f2.assist_cd = 0
		var live := 0
		var queued := 0
		for i in 32:
			_press(f2, ["assist"] if i == 0 else [])
			_press(f1, ["light"] if i == blow else [])
			_tick()
			if f2.hp <= 0.0 and live == 0:
				live = queued
			queued = screen.projectiles.size() + screen._events.size()
		check(live > 0, "setup: %s, blow at %d: something of the loser's is still to land when the blow does" % [kind, blow])
		_to_phase("round_end")
		check(screen.wins == [1, 0], "%s, blow at %d: the assist of a fighter who is already K.O.'d does not turn the win into a draw (wins %s, f1 %.1f)" % [kind, blow, _wins(), f1.hp])

	# the winner at full hp is not touched, and stands on the floor
	_new_round()
	f1.hp = f1.max_hp
	f2.hp = 5.0
	f2.assist_cd = 0
	for i in 12:
		_press(f2, ["assist"] if i == 0 else [])
		_press(f1, ["light"] if i == 2 else [])
		_tick()
	_to_phase("round_end")
	_tick(40)
	check(f1.hp == f1.max_hp, "%s: the winner takes no damage from the loser's assist (f1 %.1f)" % [kind, f1.hp])
	check(f1.position.y >= A.GROUND - 0.5, "%s: the winner stands on the floor in the win pose (y %.1f, state %s)" % [kind, f1.position.y, f1.state_name()])
	check(screen.projectiles.is_empty() and screen._events.is_empty(), "%s: nothing of the loser's is left to land (%d rounds, %d events)" % [kind, screen.projectiles.size(), screen._events.size()])

# a heal pool on a fighter who is dying
func _heal_revive() -> void:
	# f1 is Hoshino, f2 is Hina with the Healer assist
	_new_round()
	f2.hp = 5.0
	f2.heal_pool = 140.0
	_press(f1, ["light"])
	var ko := false
	for i in 100:
		_tick()
		if f2.state == S.KO:
			ko = true
			break
	check(ko and f2.hp == 0.0, "a heal pool does not revive a fighter killed in the air (state %s, hp %.1f)" % [f2.state_name(), f2.hp])
	_to_phase("round_end")
	check(screen.wins == [1, 0], "the K.O. decides the round although a heal pool was running (wins %s)" % _wins())

	# the real Healer assist, pressed half a second before the lethal blow
	_new_round()
	f2.hp = 100.0
	f2.assist_cd = 0
	for i in 30:
		_press(f2, ["assist"] if i == 0 else [])
		_tick()
	check(f2.heal_pool > 0.0, "setup: the Healer assist started a heal pool (%.1f)" % f2.heal_pool)
	f2.hp = 5.0
	_press(f1, ["light"])
	ko = false
	for i in 100:
		_tick()
		if f2.state == S.KO:
			ko = true
			break
	check(ko, "a running Healer assist does not undo a killing blow (state %s, hp %.1f)" % [f2.state_name(), f2.hp])
	_to_phase("round_end")
	check(screen.wins == [1, 0], "the K.O. stands with the Healer assist on (wins %s)" % _wins())

	# lifesteal of a fighter who has just been killed
	_new_round()
	var steal: Dictionary = M.H(Rect2(), 50.0, 14, 10, 3.0, {"hitstop": 0, "lifesteal": 0.5})
	f1.hp = 0.0
	f1._set_state(S.AIRHIT)
	f2.receive_hit(f1, steal, f1.position, false)
	check(f1.hp == 0.0, "a lifesteal hit does not heal an attacker who is already at 0 hp (%.1f)" % f1.hp)
	_new_round()
	f1.hp = 500.0
	f2.receive_hit(f1, steal, f1.position, false)
	check(f1.hp > 500.0, "a lifesteal hit still heals a living attacker (%.1f)" % f1.hp)


# resuming from pause
func _resume_from_pause() -> void:
	f1.human = true
	for act in ["confirm", "back", "aux"]:
		_new_round()
		f1.human = true
		screen.set_paused(true)
		controls.set_held("kb1", act, true)
		screen.set_paused(false)
		_pend.clear()
		for i in 4:
			screen._sim_step()
		check(f1.state != S.ATTACK, "resuming from pause with %s held throws no attack (state %s)" % [act, f1.state_name()])
		controls.set_held("kb1", act, false)
		screen._sim_step()
		controls.set_held("kb1", act, true)
		screen._sim_step()
		screen._sim_step()
		check(f1.state == S.ATTACK, "a fresh %s press after the resume still acts (state %s)" % [act, f1.state_name()])
		controls.set_held("kb1", act, false)
	# the AI side keeps its own input: only humans are re-read
	_new_round()
	f1.human = false
	f1.input = FI.from_held(f1.input, 1, 0, ["light"])
	var before: Dictionary = f1.input.held.duplicate()
	screen.set_paused(true)
	screen.set_paused(false)
	check(f1.input.held == before, "resuming leaves a non-human fighter's input alone")
	f1.human = false

# TIME UP against K.O., overkill
func _overkill_and_ko_time() -> void:
	_new_round()
	f1.hp = 5.0
	_press(f2, ["light"])
	_tick(10)
	check(is_equal_approx(f2.stat_damage_dealt, 5.0), "the damage stat counts the 5 hp that were left, not the overkill (%.1f)" % f2.stat_damage_dealt)
	check(f2.stat_hits == 1, "the killing blow is one hit (%d)" % f2.stat_hits)

	# a lethal blow with the clock on its last ticks is a K.O., not TIME UP
	_new_round()
	f2.hp = 5.0
	screen.timer_frames = 9
	_press(f1, ["light"])
	var landed := false
	var slow := 0
	for i in 80:
		_tick()
		if screen.phase == "ko":
			landed = true
			slow = screen.slowmo
			break
	check(landed, "setup: the killing blow ends the fight phase on the hit (f2 %s)" % f2.state_name())
	check(f2.state != S.KO, "the round ends before the loser lands (f2 %s)" % f2.state_name())
	check(slow > 0, "a lethal blow in the last ticks plays the K.O. slow-mo, not TIME UP (slowmo %d)" % slow)
	_to_phase("round_end")
	check(screen.wins == [1, 0], "a lethal blow in the last ticks still takes the round (wins %s)" % _wins())

# the K.O. flash and its impact frame
func _ko_flash() -> void:
	game.session.reduce_flashes = false
	FlashScript.set("_last_impact_ms", -100000)
	_new_round()
	screen.hud.set("_flash_col", Color(1, 1, 1, 0))
	_kill_f2()
	var ink := _impact()
	check(ink != null and ink.visible, "setup: the K.O. starts a visible impact frame")
	check(_flash_alpha() == 0.0, "the K.O. does not flash white over its own impact frame (alpha %.2f)" % _flash_alpha())

	# an impact frame inside 340 ms of the last one is not built, so the flash stays
	_new_round()
	screen.hud.set("_flash_col", Color(1, 1, 1, 0))
	FlashScript.set("_last_impact_ms", Time.get_ticks_msec() + 1000000)
	_kill_f2()
	ink = _impact()
	check(ink != null and not ink.visible, "setup: a second impact frame inside 340 ms is hidden")
	check(_flash_alpha() > 0.7, "the K.O. flashes white when its impact frame is refused (alpha %.2f)" % _flash_alpha())

	# Reduce Flashes: no impact frame, the flash is capped
	game.session.reduce_flashes = true
	FlashScript.set("_last_impact_ms", -100000)
	_new_round()
	screen.hud.set("_flash_col", Color(1, 1, 1, 0))
	_kill_f2()
	ink = _impact()
	check(ink != null and not ink.visible, "setup: Reduce Flashes builds no impact frame")
	check(_flash_alpha() > 0.0 and _flash_alpha() <= 0.31, "with Reduce Flashes the K.O. flash is capped, not dropped (alpha %.2f)" % _flash_alpha())
	game.session.reduce_flashes = false
	FlashScript.set("_last_impact_ms", -100000)

func _impact() -> Node:
	var found: Node = null
	for c in screen.fx_layer.get_children():
		if c.get_script() == FxScript and c.kind == "impact":
			found = c
	return found

# match stats across a restart
func _stats_restart() -> void:
	_new_round()
	_press(f1, ["light"])
	_tick(30)
	check(f1.stat_damage_dealt > 0.0 and f1.stat_hits > 0, "setup: P1 landed a hit (%.1f damage, %d hits)" % [f1.stat_damage_dealt, f1.stat_hits])
	_restart()
	check(f1.stat_damage_dealt == 0.0 and f1.stat_hits == 0 and f1.stat_max_combo == 0, "a restarted first round leaves no damage, hits or combo in the match stats (%.1f, %d, %d)" % [f1.stat_damage_dealt, f1.stat_hits, f1.stat_max_combo])

	# round 2 keeps round 1's numbers and drops only its own
	_new_round()
	_kill_f2()
	_to_phase("round_end")
	var dmg := float(f1.stat_damage_dealt)
	var hits: int = f1.stat_hits
	_to_phase("intro")
	check(screen.round_no == 2 and not screen.match_over, "setup: round 2 started (round %d)" % screen.round_no)
	_to_phase("fight")
	_place(-40.0, 40.0)
	_press(f1, ["light"])
	_tick(30)
	check(f1.stat_damage_dealt > dmg, "setup: round 2's hit added damage (%.1f)" % f1.stat_damage_dealt)
	_restart()
	check(is_equal_approx(f1.stat_damage_dealt, dmg) and f1.stat_hits == hits, "a restarted round 2 returns to round 1's totals (%.1f of %.1f, %d of %d hits)" % [f1.stat_damage_dealt, dmg, f1.stat_hits, hits])

# infinite EX in training
func _training_cutin() -> void:
	_new_round()
	screen.infinite_meter = true
	f1.meter = 100.0
	_press(f1, ["ex"])
	var froze := 0
	var low := 0
	for i in 100:
		_tick()
		if screen.time_stop > 0:
			froze += 1
			if f1.meter < 100.0:
				low += 1
	check(froze == 72, "setup: the ult froze the world for 72 ticks (%d)" % froze)
	check(low == 0, "infinite EX reads full through the whole cut-in (%d of %d ticks low)" % [low, froze])
	check(f1.meter == 100.0, "infinite EX is full after the cut-in (%.1f)" % f1.meter)
	screen.infinite_meter = false
	_new_round()
	f1.meter = 100.0
	_press(f1, ["ex"])
	_tick(12)
	check(screen.time_stop > 0 and f1.meter == 0.0, "without infinite EX the ult spends the meter (%.1f)" % f1.meter)

# every kit's projectile moves against a foe at every distance
func _sweep() -> void:
	screen.phase = "fight"
	var foes: Dictionary = {}
	for id in [HOSHINO, HINA]:
		foes[id] = _make(id, 2)
	var rows := 0
	for e in game.fighters:
		var att := _make(int(e["id"]), 1)
		for key in att.moves:
			var m: Dictionary = att.moves[key]
			var reach := _point_blank_reach(m)
			if reach <= 0.0:
				continue
			for id in foes:
				var foe: Node = foes[id]
				_pair(att, foe)
				var lo := ceili(att.push_min())
				var hi := ceili(reach)
				var missed: Array = []
				for d in range(lo, hi + 1):
					if not _lands(att, foe, key, float(d)):
						missed.append(d)
				rows += 1
				check(missed.is_empty(), "%s %s against %s: a hit at every distance from %d to %d px (missed %d: %s)" % [e["key"], key, game.by_id[id]["key"], lo, hi, missed.size(), str(missed.slice(0, 8))])
		att.queue_free()
	for id in foes:
		(foes[id] as Node).queue_free()
	screen.f1 = f1
	screen.f2 = f2
	screen.fighters = [f1, f2]
	check(rows >= 10, "the sweep covered the projectile moves of the roster (%d rows)" % rows)

func _make(id: int, slot: int) -> Node:
	var f: Node = FighterScript.new()
	screen.fighters_layer.add_child(f)
	f.world = screen
	f.setup(game.by_id[id], slot, {})
	f.human = true       # nothing reads a human's input here; a CPU fighter's kit would swing back
	return f

func _pair(att: Node, foe: Node) -> void:
	att.foe = foe
	foe.foe = att
	screen.f1 = att
	screen.f2 = foe
	screen.fighters = [att, foe]

## How far past the muzzle the sweep goes (the farthest spawn offset plus its first step) for a move that fires level rounds straight
## ahead at a standing foe; 0 for every other move. Rounds that are aimed up or down, lobbed, laid at a spot, placed on the foe
## or carried by the owner are not point-blank shots.
func _point_blank_reach(m: Dictionary) -> float:
	if m["crouch"]:
		return 0.0
	var reach := 0.0
	var level := false
	for sp in m["spawns"]:
		if sp.get("at_foe", false) or sp.get("rel_owner", false) or sp.get("follow", false) or sp.get("hold_fire", false):
			continue
		if String(sp["kind"]) not in ["bullet", "pellet", "snipe", "beam"] or (sp["hit"] as Dictionary).is_empty():
			continue
		var v: Vector2 = sp["vel"]
		var o: Vector2 = sp["offset"]
		if v.x <= 0.0 or o.x <= 0.0 or absf(v.y) > v.x * tan(deg_to_rad(A.LEVEL_DEG)):
			continue
		level = true
		reach = maxf(reach, o.x + v.x)
	return reach if level else 0.0

## True when `key` hits `foe` standing `d` px in front of `att`. A kit that rolls its own result on the cast (Aru's gamble swaps in
## a fumble) is cast again until the move that runs is the one asked for.
func _lands(att: Node, foe: Node, key: String, d: float) -> bool:
	for attempt in 40:
		att.reset_round(0.0, 1)
		foe.reset_round(d, -1)
		for f in [att, foe]:
			f._set_state(S.IDLE)
			f.input = FI.new()
		att.meter = 100.0
		att.stat_hits = 0
		if att.moves[key]["air"]:
			att.position.y = A.GROUND - LIFT
			att._set_state(S.JUMP)
		att._start_move(key)
		if String(att.move.get("name", key)) == key:
			break
	screen._freeze_queue.clear()
	screen._freeze_casters.clear()
	screen._freeze_pending = false
	for i in int(att.move["frames"]) + PROJ_TAIL:
		if att.moves[key]["air"]:
			att.position.y = A.GROUND - LIFT
			att.vel.y = 0.0
		att.tick()
		foe.tick()
		screen._resolve_hits()
		screen._push_apart()
		screen._tick_projectiles([])
		if att.stat_hits > 0:
			break
	var hit: bool = att.stat_hits > 0
	for p in screen.projectiles:
		if is_instance_valid(p):
			p.free()
	screen.projectiles.clear()
	screen._events.clear()
	_clear_fx()
	return hit
