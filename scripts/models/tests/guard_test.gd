extends SceneTree
## Guard: the class table, drain, refill, crush, air block, just guard and the HUD bar. Hina attacks, Hoshino defends.
## Run with TEST=res://scripts/models/tests/guard_test.gd tools/sd_test.sh (a real small window).
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

var checks := 0
var failures: Array = []
var screen: Node
var states: Dictionary
var FI: GDScript
var A: GDScript
var M: GDScript
var att: Node
var def: Node

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("GUARD_CHECK FAIL ", label)
		failures.append(label)

func _run() -> void:
	create_timer(180.0).timeout.connect(func() -> void:
		print("GUARD_TEST FAIL watchdog timeout")
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
	screen = game.stack.back()
	screen.set_physics_process(false)
	screen.phase = "fight"
	states = screen.f1.get_script().S
	att = screen.f1
	def = screen.f2
	_classes(game)
	_ground()
	_air()
	await _just_guard()
	_refill()
	await _crush()
	_misc()
	await _hud()
	_cpu()
	print("GUARD_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

# helpers
func _reset() -> void:
	att.reset_round(-100.0, 1)
	def.reset_round(100.0, -1)
	for f in [att, def]:
		f._set_state(states.IDLE)
		f.input = FI.new()
		f.hitstop = 0
		f.invuln = 0
		f.meter = 0.0
	def.guard_all = false

## The defender holds back (away from the attacker) for one tick.
func _hold_back(extra_ticks := 0) -> void:
	def.input = FI.from_held(def.input, 1, 0, [])
	def.tick()
	for i in extra_ticks:
		def.input = FI.from_held(def.input, 1, 0, [])
		def.tick()

func _hit(dmg := 50.0, level := "mid", chip := 0.0) -> String:
	var h: Dictionary = M.H(Rect2(), dmg, 12, 10, 4.0, {"hitstop": 0, "chip": chip, "level": level})
	return String(def.receive_hit(att, h, att.position, false))

func _raw(dmg: float) -> float:
	return dmg * att.hit_mult(false)

func _drain(dmg: float, k := 1.0) -> float:
	return _raw(dmg) * A.GUARD_DRAIN * float(att.stats["guard_dealt"]) * k

func _up() -> void:
	def.position.y = A.GROUND - 200.0
	def.vel = Vector2.ZERO
	def._set_state(states.JUMP)

## The hud feed draws the JUST GUARD and GUARD CRUSH words; it picks the event up on the next frame.
func _feed_word(id: String) -> bool:
	await process_frame
	for w in screen.hud._feed._words:
		if w["id"] == id:
			return true
	return false

func _played(name: String) -> int:
	return int(root.get_node("Sfx").played.get(name, 0))

# the class table
func _profile(weapon: String, role: String, armor: String) -> Dictionary:
	return M.stats_for({"weapon": weapon, "bullet": "Pierce", "role": role, "armor": armor})

func _expect(who: String, s: Dictionary, size: float, delay: int, refill: float, crush: int, jg: int, dealt: float) -> void:
	check(is_equal_approx(float(s["guard_max"]), size), "%s: guard size %.2f" % [who, size])
	check(int(s["guard_delay"]) == delay, "%s: refill delay %d" % [who, delay])
	check(is_equal_approx(float(s["guard_refill"]), refill), "%s: refill speed %.3f" % [who, refill])
	check(int(s["guard_crush"]) == crush, "%s: crush stun %d" % [who, crush])
	check(int(s["guard_jg"]) == jg, "%s: just guard window %d" % [who, jg])
	check(is_equal_approx(float(s["guard_dealt"]), dealt), "%s: guard damage dealt %.3f" % [who, dealt])
	check(not s.has("hp"), who + ": no class sets hp")

func _classes(game: Node) -> void:
	_expect("standard", _profile("AR", "DamageDealer", "Unarmed"), 100.0, 60, 0.5, 50, 4, 1.0)
	_expect("speed", _profile("SMG", "DamageDealer", "LightArmor"), 80.0, 40, 0.88, 40, 5, 0.85)
	_expect("power", _profile("MG", "DamageDealer", "HeavyArmor"), 135.0, 80, 0.35, 60, 3, 1.2)
	_expect("tricky", _profile("SR", "DamageDealer", "HeavyArmor"), 100.0, 50, 0.55, 50, 5, 1.0)
	_expect("tanker", _profile("AR", "Tanker", "Unarmed"), 143.75, 80, 0.35, 60, 3, 1.26)
	_expect("healer", _profile("AR", "Healer", "Unarmed"), 90.0, 60, 0.5, 50, 4, 1.0)
	_expect("hoshino", def.stats, 153.75, 80, 0.35, 60, 3, 1.26)
	_expect("hina", att.stats, 135.0, 80, 0.35, 60, 3, 1.2)
	var kits = load("res://scripts/fight/kits.gd")
	var hp_free := true
	for e in game.fighters:
		hp_free = hp_free and not kits.make(e).build_stats().has("hp")
	check(hp_free, "no kit sets hp")
	check(is_equal_approx(att.max_hp, A.MAX_HP) and is_equal_approx(def.max_hp, A.MAX_HP), "every fighter has the universal hp")

# blocking on the ground and in the air
func _ground() -> void:
	_reset()
	_hold_back(10)
	var before := float(def.guard)
	check(_hit(50.0) == "block" and def.state == states.BLOCK, "ground: holding back blocks")
	check(is_equal_approx(before - float(def.guard), _drain(50.0)), "ground: the drain is dmg x 0.8 x the attacker's guard damage (%.2f)" % (before - float(def.guard)))
	check(is_equal_approx(def.meter, 2.0 * A.METER_PACE), "ground: a block gives 2 meter, paced")
	_reset()
	_hold_back(10)
	var hp := float(def.hp)
	_hit(100.0, "mid", 0.08)
	check(is_equal_approx(hp - float(def.hp), 100.0 * 0.08 * att.hit_mult(false)), "ground: a block costs chip damage")
	_reset()
	_hold_back(10)
	check(_hit(50.0, "low") == "hit", "ground: standing does not block a low")
	_reset()
	def.input = FI.from_held(def.input, 1, 1, [])
	def.tick()
	check(_hit(50.0, "high") == "hit", "ground: crouching does not block a high")
	_reset()
	def.input = FI.from_held(def.input, 1, 1, [])
	def.tick()
	check(_hit(50.0, "low") == "block", "ground: crouching blocks a low")

func _air() -> void:
	_reset()
	_up()
	def.input = FI.from_held(def.input, 1, 0, [])
	var before := float(def.guard)
	check(_hit(50.0, "low") == "block" and def.state == states.BLOCK and def.block_air, "air: back blocks any level and the block is an air block")
	check(is_equal_approx(before - float(def.guard), _drain(50.0, A.AIR_BLOCK)), "air: the drain is x1.5")
	def.hitstop = 0
	var y0: float = def.position.y
	for i in 6:
		def.input = FI.from_held(def.input, 1, 0, [])
		def.tick()
	check(def.position.y > y0 and def.state == states.BLOCK, "air: gravity pulls a blocking fighter down")
	for i in 200:
		def.input = FI.from_held(def.input, 1, 0, [])
		def.tick()
		if def.is_grounded():
			break
	def.input = FI.from_held(def.input, 1, 0, [])
	def.tick()
	check(def.is_grounded() and def.state == states.IDLE, "air: landing ends an air block")
	# back is away from the foe even after crossing over: the defender stands left of the attacker, facing stale
	_reset()
	_up()
	def.position.x = -200.0
	def.input = FI.from_held(def.input, 1, 0, [])
	check(_hit(50.0) == "hit", "air: holding toward the foe does not block after a cross-over")
	_reset()
	_up()
	def.position.x = -200.0
	def.input = FI.from_held(def.input, -1, 0, [])
	check(_hit(50.0) == "block", "air: holding away from the foe blocks after a cross-over")
	_reset()
	_up()
	def._set_state(states.ATTACK)
	def.move = {"air": true, "cancel": [], "hit": {}, "spawns": [], "frames": 30, "startup": 5, "active": 5, "cutin": false}
	def.input = FI.from_held(def.input, 1, 0, [])
	check(_hit(50.0) == "hit", "air: no air block while attacking")

# just guard
func _just_guard() -> void:
	var window := int(def.stats["guard_jg"])
	for k in [window, window + 1]:
		_reset()
		_hold_back(k)
		var before := float(def.guard)
		var hp := float(def.hp)
		var res := _hit(100.0, "mid", 0.08)
		var jg: bool = k <= window
		check(res == "block", "just guard %d: still a block" % k)
		check(bool(def.last_block_jg) == jg, "just guard %d: recognised as %s" % [k, str(jg)])
		check((is_equal_approx(before, float(def.guard))) == jg, "just guard %d: the drain is %s" % [k, "skipped" if jg else "applied"])
		check((is_equal_approx(hp, float(def.hp))) == jg, "just guard %d: chip is %s" % [k, "skipped" if jg else "applied"])
		check((int(def.blockstun) == 5) == jg and (jg or int(def.blockstun) == 10), "just guard %d: blockstun %s" % [k, "halved" if jg else "normal"])
		check(is_equal_approx(def.meter, (5.0 if jg else 2.0) * A.METER_PACE), "just guard %d: meter, paced" % k)
	_reset()
	_hold_back(1)
	await process_frame
	var n := _played("just_guard")
	_hit(50.0)
	check(_played("just_guard") == n + 1 and await _feed_word("just_guard"), "just guard: the sound and the text fire")
	var after := float(def.guard)
	_hit(50.0)
	check(float(def.guard) < after and not def.last_block_jg, "just guard: the press is consumed by the first guarded hit")
	# a press during hitstop still counts
	_reset()
	def.hitstop = 5
	def.input = FI.from_held(def.input, 1, 0, [])
	def.tick()
	check(def._back_age == 0, "just guard: a press made in hitstop is tracked")
	def.hitstop = 0
	_hit(50.0)
	check(def.last_block_jg, "just guard: a press made in hitstop counts")

# refill
func _refill() -> void:
	_reset()
	_hold_back(10)
	_hit(50.0)
	def.hitstop = 0
	var after := float(def.guard)
	var delay := int(def.stats["guard_delay"])
	for i in delay:
		def.input = FI.new()
		def.tick()
	check(is_equal_approx(float(def.guard), after), "refill: nothing for %d ticks after a guarded hit" % delay)
	def.input = FI.new()
	def.tick()
	check(is_equal_approx(float(def.guard), after + float(def.stats["guard_refill"])), "refill: then the refill speed a tick")
	def.guard = float(def.stats["guard_max"]) - 0.1
	for i in 5:
		def.input = FI.new()
		def.tick()
	check(is_equal_approx(float(def.guard), float(def.stats["guard_max"])), "refill: never above the guard size")

# crush
func _crush() -> void:
	_reset()
	_hold_back(10)
	def.guard = 1.0
	var n := _played("guard_crush")
	check(_hit(50.0) == "block", "crush: the hit that empties the guard is still guarded")
	check(int(def.crush_t) == int(def.stats["guard_crush"]) and def.state == states.BLOCK, "crush: stunned in BLOCK for the class's time")
	check(is_equal_approx(float(def.guard), float(def.stats["guard_max"])), "crush: the guard comes back full")
	check(_played("guard_crush") == n + 1 and await _feed_word("guard_crush"), "crush: the sound and the text fire")
	def.hitstop = 0
	var hp := float(def.hp)
	check(_hit(50.0) == "hit" and float(def.hp) < hp and int(def.crush_t) == 0, "crush: any hit lands and ends the stun")
	# an air crush falls, lands and stays stunned
	_reset()
	_up()
	def.input = FI.from_held(def.input, 1, 0, [])
	def.guard = 1.0
	_hit(50.0)
	def.hitstop = 0
	for i in 200:
		def.tick()
		if def.is_grounded():
			break
	check(def.is_grounded() and def.state == states.BLOCK and int(def.crush_t) > 0, "crush: an air crush stays stunned after landing")
	def.input = FI.new()
	for i in 80:
		def.tick()
	check(def.state == states.IDLE and int(def.crush_t) == 0, "crush: the stun ends")

func _misc() -> void:
	_reset()
	_hold_back(1)
	def.guard_all = true
	var before := float(def.guard)
	for i in 6:
		_hit(200.0)
		def.hitstop = 0
	check(is_equal_approx(float(def.guard), before) and int(def.crush_t) == 0, "the training dummy never loses guard")
	_reset()
	def.guard = 5.0
	def.reset_round(100.0, -1)
	check(is_equal_approx(float(def.guard), float(def.stats["guard_max"])), "a new round restores the guard")

# HUD bar
func _hud() -> void:
	_reset()
	await process_frame
	var got = screen.hud.get("_guard_bars") if screen.hud != null else null
	var bars: Array = got if got is Array else []
	check(bars.size() == 2, "hud: one guard bar per player")
	if bars.size() != 2:
		return
	var gmax := float(att.stats["guard_max"])
	att.guard = gmax * 0.4
	await process_frame
	var bar = bars[0]
	check(is_equal_approx(float(bar.mat.get_shader_parameter("fill")), 0.4), "hud: fill follows the guard")
	check(float(bar.mat.get_shader_parameter("trail")) >= 0.4 - 0.001, "hud: the trail never trails below the fill")
	att.guard = gmax
	await process_frame
	var full: Color = bar.mat.get_shader_parameter("col_bot")
	check(full.g > full.r, "hud: a full guard is green")
	att.guard = gmax * 0.1
	await process_frame
	var low: Color = bar.mat.get_shader_parameter("col_bot")
	check(low.r > low.g, "hud: a low guard is red")
	att.guard = gmax
	att.crush_t = 20
	await process_frame
	check(is_equal_approx(float(bar.mat.get_shader_parameter("fill")), 1.0 - 20.0 / float(att.stats["guard_crush"])), "hud: a crush sweeps the bar")
	att.crush_t = 0

# CPU
## One scripted exchange: Hina's 5L against a CPU Hoshino. Returns the guarded hit's last_block_jg, or -1 when no block happened.
func _cpu_exchange(level: int, seed_value: int, air: bool) -> int:
	_reset()
	if air:
		_up()
	var brain = load("res://scripts/fight/cpu_brain.gd").new()
	brain.setup(def, att, level, seed_value)
	att._start_move("5L")
	for step in 60:
		def.input = brain.think()
		att.tick()
		def.tick()
		var h: Dictionary = att.active_hit()
		if not h.is_empty():
			var res := String(def.receive_hit(att, h, att.position, false))
			att.move_hit = true
			return (1 if def.last_block_jg else 0) if res == "block" else -1
	return -1

func _cpu() -> void:
	var blocks := 0
	var air_blocks := 0
	var jgs := 0
	for seed_value in 60:
		var r := _cpu_exchange(3, seed_value, false)
		if r >= 0:
			blocks += 1
			jgs += r
		if _cpu_exchange(3, seed_value, true) >= 0:
			air_blocks += 1
	check(blocks > 20, "cpu: a level 3 cpu blocks on the ground (%d of 60)" % blocks)
	check(air_blocks > 20, "cpu: a level 3 cpu blocks in the air (%d of 60)" % air_blocks)
	check(jgs > 0 and jgs < blocks, "cpu: a level 3 cpu sometimes times a just guard (%d of %d blocks)" % [jgs, blocks])
	var crouched_in_air := false
	var brain = load("res://scripts/fight/cpu_brain.gd").new()
	_reset()
	_up()
	brain.setup(def, att, 3, 1)
	att._start_move("2L")
	for step in 30:
		def.input = brain.think()
		crouched_in_air = crouched_in_air or def.input.y > 0
		att.tick()
	check(not crouched_in_air, "cpu: never holds down in the air")

