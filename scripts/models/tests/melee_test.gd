extends SceneTree
## Close strikes, command normals and throws: the five move keys of both SD kits, which key a press picks, the light +
## heavy chord, the throw's rules, the tech, strike blocking, the CPU and the generic throw. Hina and Hoshino only.
## Every distance in this file is a legacy distance, the unit the ranges are written in: centres minus
## Fighter.spacing_extra() (44 here), so 74 is the closest two fighters stand. _place() and _place_flipped() add the extra.
## Run with TEST=res://scripts/models/tests/melee_test.gd tools/sd_test.sh (a real small window).
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
var game: Node

# startup, active, recovery, raw dmg, hitstun, blockstun, push, level, rect, cancels
const SPEC := {
	"hina": {
		"close_L": [6, 3, 13, 26.0, 16, 10, 6.0, "mid", Rect2(20, -150, 95, 75), ["light", "heavy", "skill", "ex"]],
		"close_H": [11, 4, 22, 54.0, 24, 15, 11.0, "mid", Rect2(10, -215, 95, 160), ["skill", "ex"]],
		"6L": [9, 3, 15, 30.0, 17, 11, 5.0, "mid", Rect2(24, -150, 150, 75), ["light", "heavy", "skill", "ex"]],
		"6H": [20, 4, 24, 60.0, 26, 16, 4.0, "high", Rect2(28, -285, 105, 190), ["skill", "ex"]],
		"throw": [7, 3, 28, 70.0, 0, 0, 0.0, "mid", Rect2(0, -200, 110, 170), []],
	},
	"hoshino": {
		"close_L": [5, 3, 12, 32.0, 16, 10, 5.5, "mid", Rect2(14, -205, 85, 115), ["light", "heavy", "skill", "ex"]],
		"close_H": [12, 4, 22, 56.0, 25, 15, 9.0, "mid", Rect2(10, -215, 110, 110), ["skill", "ex"]],
		"6L": [9, 3, 14, 34.0, 17, 11, 5.0, "mid", Rect2(20, -185, 140, 70), ["light", "heavy", "skill", "ex"]],
		"6H": [22, 4, 26, 62.0, 26, 16, 4.0, "high", Rect2(24, -285, 100, 190), ["skill", "ex"]],
		"throw": [8, 3, 30, 80.0, 0, 0, 0.0, "mid", Rect2(0, -200, 105, 170), []],
	},
}

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("MELEE_CHECK FAIL ", label)
		failures.append(label)

func _run() -> void:
	create_timer(240.0).timeout.connect(func() -> void:
		print("MELEE_TEST FAIL watchdog timeout")
		quit(3))
	await process_frame
	FI = load("res://scripts/fight/fight_input.gd")
	A = load("res://scripts/fight/arena.gd")
	M = load("res://scripts/fight/movesets.gd")
	game = root.get_node("Game")
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
	_constants()
	var ready := true
	for who in [screen.f1, screen.f2]:
		_as(who)
		_data()
		if not _has_all():
			ready = false
			continue
		_no_dead_zone()
		_selection()
		_chord()
		_review_cases()
		_throw()
		_clash()
		_strikes()
		_sounds()
	if ready:
		_hoshino_armor()
		_cpu()
	_generic()
	print("MELEE_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

# ── helpers ──────────────────────────────────────────────────────────────────
## `who` attacks from the left, its foe defends from the right.
func _as(who: Node) -> void:
	att = who
	def = who.foe

func _has_all() -> bool:
	for key in ["close_L", "close_H", "6L", "6H", "throw"]:
		if not att.moves.has(key):
			return false
	return true

func _const(name: String) -> float:
	return float(A.get_script_constant_map().get(name, 0.0))

func _name() -> String:
	return String(att.data["key"])

func _place(dist: float) -> void:
	att.reset_round(0.0, 1)
	def.reset_round(dist + att.spacing_extra(), -1)
	for f in [att, def]:
		f._set_state(states.IDLE)
		f.input = FI.new()
		f.hitstop = 0
		f.invuln = 0
		f.meter = 0.0
		f.guard_all = false

func _press(f: Node, btns: Array, x := 0, y := 0) -> void:
	f.input = FI.from_held(f.input, x, y, btns)
	f.tick()

## Both fighters tick on idle input, then the screen resolves the connects, as _tick_fight does.
func _step() -> void:
	att.input = FI.from_held(att.input, 0, 0, [])
	def.input = FI.from_held(def.input, 0, 0, [])
	att.tick()
	def.tick()
	screen._resolve_hits()
	screen._push_apart()

## A connected throw carries the foe: steps until the thrower lets it go, which is where the throw's hit lands.
func _to_release() -> void:
	def.frame = att.frame
	for i in 80:
		if def.carrier == null:
			return
		_step()

func _key(dist: float, btns: Array, x := 0, y := 0, foe_air := false) -> String:
	_place(dist)
	if foe_air:
		def.position.y = A.GROUND - 200.0
		def._set_state(states.JUMP)
	_press(att, btns, x, y)
	return String(att.move_key) if att.state == states.ATTACK else ""

func _hold_back(f: Node, ticks: int) -> void:
	for i in ticks:
		f.input = FI.from_held(f.input, -f.facing, 0, [])
		f.tick()

func _text_count(t: String) -> int:
	var n := 0
	for c in screen.fx_layer.get_children():
		if c.get("kind") == "text" and c.get("text") == t:
			n += 1
	return n

func _played(name: String) -> int:
	return int(root.get_node("Sfx").played.get(name, 0))

func _hit_of(f: Node, key: String) -> Dictionary:
	return f.moves[key]["hit"]

func _connect(key: String) -> String:
	return String(def.receive_hit(att, _hit_of(att, key), att.position, false))

# ── constants and data ───────────────────────────────────────────────────────
func _constants() -> void:
	check(is_equal_approx(_const("CLOSE_RANGE"), 96.0), "Arena.CLOSE_RANGE is 96")
	check(is_equal_approx(_const("THROW_RANGE"), 120.0), "Arena.THROW_RANGE is 120")

func _data() -> void:
	var who := _name()
	var dm := float(att.stats["dmg"])
	for key in SPEC[who]:
		var s: Array = SPEC[who][key]
		check(att.moves.has(key), "%s: has %s" % [who, key])
		if not att.moves.has(key):
			continue
		var m: Dictionary = att.moves[key]
		var h: Dictionary = m["hit"]
		var tag := "%s %s" % [who, key]
		check(int(m["startup"]) == s[0] and int(m["active"]) == s[1] and int(m["recovery"]) == s[2], tag + ": frames %d/%d/%d" % [s[0], s[1], s[2]])
		check(is_equal_approx(float(h["dmg"]), float(s[3]) * dm), tag + ": raw dmg %.0f through dm" % s[3])
		check(h["rect"] == s[8], tag + ": rect " + str(s[8]))
		check(m["cancel"] == s[9], tag + ": cancels " + str(s[9]))
		check(h["level"] == s[7], tag + ": level " + String(s[7]))
		check(float(h["meter"]) >= 4.0 and float(h["meter"]) <= 10.0, tag + ": meter 4 to 10")
		check(String(m.get("source", "")).contains("adaptation"), tag + ": the source says adaptation")
		check(not m["air"] and not m["cutin"] and not m.get("super", false), tag + ": a ground normal, no cost")
		check(not m.has("shots") and m["spawns"].is_empty(), tag + ": no shots and no spawns, so the magazine and sockets.json are untouched")
		if key == "throw":
			check(bool(h.get("throw", false)) and bool(h["kd"]) and is_equal_approx(float(h.get("snap", 0.0)), 80.0), tag + ": a throw with a knockdown, the snap kept for a throw with no carry")
			check(int(h["hitstop"]) == (10 if who == "hina" else 6), tag + ": the release holds %d ticks" % (10 if who == "hina" else 6))
			check(h["launch"] == (Vector2(6, 5) if who == "hina" else Vector2(11, -5.5)), tag + ": the release launch")
			check(m.has("carry") and int(m["carry"]["grab_stop"]) == 4, tag + ": it carries the foe, a grab stop of 4")
			check(not m.get("swish", true), tag + ": no swing arc")
			check(not bool(h.get("grab", false)), tag + ": grab stays the unblockable flag of other kits")
		else:
			check(int(h["hitstun"]) == s[4] and int(h["blockstun"]) == s[5] and is_equal_approx(float(h["push"]), float(s[6])), tag + ": stun and push")
			check(m.get("swish", true) and not bool(h.get("throw", false)) and not bool(h.get("grab", false)), tag + ": a plain strike with its swing arc")
	if not _has_all():
		return
	var one: Array = att.moves["6L"]["vx"]
	var step := 3.0 if who == "hina" else 2.0
	check(one.size() == 1 and int(one[0]["from"]) == 6 and int(one[0]["to"]) == 10 and is_equal_approx(float(one[0]["v"]), step), who + " 6L: steps %.0f px a tick over frames 6 to 10" % step)
	check(att.moves["6H"]["vx"].is_empty() and att.moves["close_L"]["vx"].is_empty(), who + ": only 6L steps")
	var ar: Dictionary = att.moves["close_H"].get("armor", {})
	if who == "hoshino":
		check(int(ar.get("hits", 0)) == 1 and int(ar.get("from", -1)) == 3 and int(ar.get("to", -1)) == 11 and is_equal_approx(float(ar.get("dmg", 0)), 0.5), "hoshino close_H: one hit of armor over frames 3 to 11 at half damage")
	else:
		check(ar.is_empty(), "hina close_H: no armor")
	check(not att.stats.has("hp") and is_equal_approx(att.max_hp, A.MAX_HP), who + ": hp stays universal")
	var header := ""
	for line in FileAccess.get_file_as_string("res://scripts/fight/kits/kit_%s.gd" % who).split("\n"):
		if line != "extends Kit" and not line.begins_with("##"):
			break
		header += line + "\n"
	check(header.length() > 200 and not header.contains("does not swing") and not header.contains("no melee"), who + ": the kit header no longer denies melee")

## Hina's gun normals start 116 px out, which used to miss Hoshino's narrow hurtbox below a 92 px distance while the push let
## them stand 74 apart. The pair minimum is now past that, so every key reaches a standing foe at the closest spacing.
func _no_dead_zone() -> void:
	var who := _name()
	for dist in [74.0, 80.0, 90.0]:
		_place(dist)
		for k in ["close_L", "close_H", "5L", "5H"]:
			var wr: Rect2 = att.melee_rect(_hit_of(att, k)["rect"])
			check(wr.intersects(def.hurtbox()), "%s %s: reaches a foe at legacy %d px" % [who, k, int(dist)])
	_place(96.0)
	for k in ["close_L", "close_H", "6L", "6H"]:
		var wr3: Rect2 = att.melee_rect(_hit_of(att, k)["rect"])
		check(wr3.intersects(def.hurtbox()), "%s %s: connects at the 96 px close range" % [who, k])

# ── which key a press starts ─────────────────────────────────────────────────
func _selection() -> void:
	var who := _name()
	for d in [[95.0, "close"], [96.0, "close"], [97.0, "5"]]:
		check(_key(d[0], ["light"]) == ("close_L" if d[1] == "close" else "5L"), "%s: light at %d px starts %s" % [who, int(d[0]), d[1]])
		check(_key(d[0], ["heavy"]) == ("close_H" if d[1] == "close" else "5H"), "%s: heavy at %d px starts %s" % [who, int(d[0]), d[1]])
	check(_key(200.0, ["light"]) == "5L" and _key(200.0, ["heavy"]) == "5H", who + ": far away a press is the gun normal")
	check(_key(60.0, ["light"], 0, 0, true) == "5L" and _key(60.0, ["heavy"], 0, 0, true) == "5H", who + ": an airborne foe keeps the gun normal")
	check(_key(60.0, ["light"], 0, 1) == "2L" and _key(60.0, ["heavy"], 0, 1) == "2H", who + ": down held keeps 2L and 2H up close")
	check(_key(160.0, ["light"], 1) == "6L" and _key(160.0, ["heavy"], 1) == "6H", who + ": forward held starts the command normal up to 160 px")
	check(_key(161.0, ["light"], 1) == "5L" and _key(161.0, ["heavy"], 1) == "5H", who + ": 161 px away forward held keeps the gun normal")
	check(_key(400.0, ["heavy"], 1) == "5H", who + ": walking in from far keeps the gun normal")
	check(_const("COMMAND_RANGE") == 160.0, "Arena.COMMAND_RANGE is 160")
	check(_key(60.0, ["light"], 1) == "6L" and _key(60.0, ["heavy"], 1) == "6H", who + ": the command normal beats the close strike")
	check(_key(200.0, ["light"], -1) == "5L", who + ": back held is a plain press")
	_place(150.0)
	att._set_state(states.WALK)
	_press(att, ["heavy"], 1)
	check(att.state == states.ATTACK and att.move_key == "6H", who + ": a press while walking in is the command normal")
	_place(60.0)
	att._set_state(states.CROUCH)
	_press(att, ["light"], 0, 1)
	check(att.move_key == "2L", who + ": a crouching press is 2L")
	var saved: Dictionary = att.moves.duplicate()
	att.moves.erase("6L")
	check(_key(60.0, ["light"], 1) == "close_L", who + ": an erased 6L falls to the close strike")
	check(_key(150.0, ["light"], 1) == "5L", who + ": an erased 6L falls to 5L at range")
	att.moves.erase("close_L")
	check(_key(60.0, ["light"], 1) == "5L" and _key(60.0, ["light"]) == "5L", who + ": with neither key the press is 5L")
	att.moves = saved
	var stub := GDScript.new()
	stub.source_code = "extends Kit\nfunc map_ground_input(f):\n\treturn '5H' if f.consume('light') else ''\n"
	stub.reload()
	var kit: Object = att.kit
	att.kit = stub.new()
	check(_key(60.0, ["light"]) == "5H", who + ": the kit's own mapping comes first")
	att.kit = kit
	# a cancel keeps mapping to 5x at point-blank range
	_place(60.0)
	att._start_move("close_L")
	att.move_connected = true
	att.mf = 5
	_press(att, ["light"])
	check(att.move_key == "5L", who + ": close_L cancels into 5L, the point-blank gun burst")
	_place(60.0)
	att._start_move("close_H")
	att.move_connected = true
	att.mf = 12
	_press(att, ["skill"])
	check(att.move_key == "skill", who + ": close_H cancels into the skill")

# ── the light + heavy chord ──────────────────────────────────────────────────
## Presses `first`, then `second` `gap` ticks later (0 = the same tick); returns the move started.
func _late(first: String, second: String, gap: int, dist := 100.0) -> String:
	_place(dist)
	if gap == 0:
		_press(att, [first, second])
	else:
		_press(att, [first])
		for i in gap - 1:
			_press(att, [])
		_press(att, [second])
	return String(att.move_key) if att.state == states.ATTACK else ""

## The attacker on the right, facing left; the foe on the left.
func _place_flipped(dist: float) -> void:
	_place(dist)
	att.reset_round(500.0, -1)
	def.reset_round(500.0 - dist - att.spacing_extra(), 1)
	for f in [att, def]:
		f._set_state(states.IDLE)
		f.input = FI.new()
		f.hitstop = 0

func _review_cases() -> void:
	var who := _name()
	# facing left: the range, the chord and the snap follow the attacker's side, not the sign of the distance
	_place_flipped(60.0)
	_press(att, ["light"])
	check(att.move_key == "close_L", who + ": facing left, light at 60 px is the close strike")
	_place_flipped(200.0)
	_press(att, ["light"])
	check(att.move_key == "5L", who + ": facing left, light at 200 px is the gun normal")
	_place_flipped(110.0)
	_press(att, ["light", "heavy"])
	check(att.move_key == "throw", who + ": facing left, the chord at 110 px is the throw")
	_place_flipped(200.0)
	_press(att, ["light", "heavy"])
	check(att.move_key == "5H", who + ": facing left, the chord at 200 px is not")
	_place_flipped(110.0)
	att._start_move("throw")
	_connect("throw")
	_to_release()
	var end: Array = att.moves["throw"]["carry"]["path"][-1]
	check(is_equal_approx(def.position.x, att.position.x + float(att.facing) * float(end[1])), who + ": facing left, the foe is carried to the path's end in front of the thrower (x %.0f)" % def.position.x)
	# a foe in an air move is not thrown even though its state is ATTACK
	_place(100.0)
	def.position.y = A.GROUND - 120.0
	def._set_state(states.ATTACK)
	def.move = def.moves["jH"] if def.moves.has("jH") else def.moves["5H"]
	att._start_move("throw")
	check(_connect("throw") == "miss", who + ": a foe in the air in an attack is not thrown")
	# buffered presses while stunned: two ticks apart is a chord, five apart is not
	for gap in [1, 3]:
		check(_stunned("heavy", "light", gap) == "throw", who + ": heavy then light %d ticks apart while stunned is the throw" % gap)
	check(_stunned("heavy", "light", 4) == "5H", who + ": heavy then light 4 ticks apart while stunned is a plain heavy")
	check(_stunned("light", "heavy", 4) == "5H", who + ": light then heavy 4 ticks apart while stunned is a plain heavy")
	for extra in [0, 1, 2]:
		for pair in [["heavy", "light"], ["light", "heavy"]]:
			check(_stunned(pair[0], pair[1], 4, extra) != "throw", who + ": %s then %s 4 ticks apart, %d extra stun ticks: never the throw" % [pair[0], pair[1], extra])
	# a move a kit hook starts mid-attack counts as a cancel and never upgrades
	_place(100.0)
	_press(att, ["light"])
	check(not att._cancelled, who + ": a move started from idle is not a cancel")
	att._start_move("5H")
	check(att._cancelled, who + ": a move started in the middle of another is a cancel")
	_press(att, ["light"])
	check(att.move_key == "5H", who + ": it does not restart as the throw")
	# a late throw press gives back what the first move's on_move_start paid
	if who == "hina":
		_place(100.0)
		att.kv["mag"] = 49
		_press(att, ["light"])
		check(int(att.kv["mag"]) < 49, "hina: the gun normal spends rounds at once")
		_press(att, ["heavy"])
		check(att.move_key == "throw" and int(att.kv["mag"]) == 49, "hina: a late throw press gives the rounds back (mag %d)" % int(att.kv["mag"]))
		_place(100.0)
		att.kv["mag"] = 2
		att.kv["lock_t"] = 0
		_press(att, ["light"])
		check(int(att.kv["lock_t"]) > 0, "hina: an empty magazine starts Lock & Load")
		_press(att, ["heavy"])
		check(att.move_key == "throw" and int(att.kv["lock_t"]) <= 1 and int(att.kv["mag"]) == 2, "hina: the late throw press also cancels the free Lock & Load (lock_t %d, mag %d)" % [int(att.kv["lock_t"]), int(att.kv["mag"])])

## The attacker is in hitstun, which ends right after `second`, while `first` and then `second` are pressed `gap` ticks apart.
func _stunned(first: String, second: String, gap: int, extra := 0) -> String:
	_place(100.0)
	att._set_state(states.HIT)
	att.hitstun = gap + 2 + extra
	_press(att, [first])
	for i in gap - 1:
		_press(att, [])
	_press(att, [second])
	for i in 12:
		if att.state == states.ATTACK:
			break
		_press(att, [])
	return String(att.move_key) if att.state == states.ATTACK else ""

func _chord() -> void:
	var who := _name()
	check(_late("light", "heavy", 0) == "throw", who + ": light + heavy on one tick is the throw")
	check(not att.buffered("light") and not att.buffered("heavy"), who + ": the throw consumes both buttons")
	check(_late("light", "heavy", 0, 120.0) == "throw", who + ": the throw reaches a foe 120 px away")
	check(_late("light", "heavy", 0, 121.0) == "5H", who + ": a foe 121 px away is a plain heavy")
	check(_late("light", "heavy", 0, 60.0) == "throw", who + ": the throw also works at close range")
	_place(100.0)
	_press(att, ["light"])
	check(att.state == states.ATTACK and att.move_key == "5L", who + ": a lone light starts at once, with no input delay")
	for gap in [1, A.CHORD]:
		check(_late("light", "heavy", gap) == "throw", who + ": heavy %d ticks after light restarts the move as the throw" % gap)
		check(_late("heavy", "light", gap) == "throw", who + ": light %d ticks after heavy restarts the move as the throw" % gap)
	check(_late("light", "heavy", A.CHORD + 1) == "5L", who + ": heavy %d ticks after light is too late" % (A.CHORD + 1))
	check(_late("heavy", "light", A.CHORD + 1) == "5H", who + ": light %d ticks after heavy is too late" % (A.CHORD + 1))
	check(_late("light", "heavy", A.CHORD + 1, 80.0) == "close_L", who + ": too late at close range keeps the close strike")
	check(_late("light", "heavy", 2, 80.0) == "throw", who + ": a late chord at close range is still the throw")
	check(_late("light", "heavy", A.CHORD, 200.0) == "5L", who + ": out of range a late press does not restart")
	for k in ["5L", "5H", "6L", "6H", "close_L", "close_H"]:
		_place(100.0)
		att._start_move(k)
		_press(att, ["light" if k.ends_with("H") else "heavy"])
		check(att.move_key == "throw", who + ": " + k + " restarts as the throw on the other button")
	_place(100.0)
	att._start_move("close_L")
	att.move_hit = true
	_press(att, ["heavy"])
	check(att.move_key == "close_L", who + ": a move that has hit does not restart")
	_place(100.0)
	att._start_move("2L")
	_press(att, ["heavy"])
	check(att.move_key == "2L", who + ": a crouching move does not restart")
	_place(100.0)
	att._start_move("5L")
	att.move_connected = true
	att.mf = 4
	_press(att, ["light"])
	check(att.move_key == "5L" and att.mf == -1, who + ": the light cancel restarts 5L")
	_press(att, ["heavy"])
	check(att.move_key == "5L", who + ": a move started by a cancel never restarts as a throw")
	_place(100.0)
	def.position.y = A.GROUND - 200.0
	def._set_state(states.JUMP)
	_press(att, ["light", "heavy"])
	check(att.move_key != "throw", who + ": no throw against an airborne foe")
	_place(100.0)
	_press(att, ["light", "heavy"], 0, 1)
	check(att.move_key == "2H", who + ": crouching, the chord is 2H")
	_place(100.0)
	att.position.y = A.GROUND - 100.0
	att._set_state(states.JUMP)
	_press(att, ["light", "heavy"])
	check(att.move_key != "throw", who + ": no throw from the air")
	_place(100.0)
	_press(att, ["light", "heavy"], 1)
	check(att.move_key == "throw", who + ": forward held does not stop the chord")
	# a plain chord far away: both buttons exist, heavy goes first, light is not a throw
	_place(300.0)
	_press(att, ["light", "heavy"])
	check(att.move_key == "5H", who + ": a far button mash is a normal")

# ── the throw ────────────────────────────────────────────────────────────────
func _start_throw() -> void:
	_place(110.0)
	att._start_move("throw")

func _expected(key: String) -> float:
	return float(_hit_of(att, key)["dmg"]) * att.hit_mult(false) * float(def.stats["taken"])

func _throw() -> void:
	var who := _name()
	_start_throw()
	var hp := float(def.hp)
	var guard := float(def.guard)
	var idle := int(def._guard_idle)
	var slam := _played("slam")
	check(_connect("throw") == "hit" and def.state == states.AIRHIT, who + " throw: connects on an idle foe")
	check(att.hitstop == int(att.moves["throw"]["carry"]["grab_stop"]) and def.hitstop == 0 and def.carrier == att, who + " throw: the connect grabs: the thrower holds the grab, the foe is held")
	check(is_equal_approx(hp, float(def.hp)) and _played("slam") == slam, who + " throw: no damage and no slam at the connect")
	_to_release()
	check(is_equal_approx(hp - float(def.hp), _expected("throw")), who + " throw: damage is dmg x dm x taken, at the release (%.1f)" % (hp - float(def.hp)))
	var end: Array = att.moves["throw"]["carry"]["path"][-1]
	check(is_equal_approx(def.position.x, att.position.x + float(att.facing) * float(end[1])), who + " throw: the foe is carried to the path's end in front of the thrower")
	var stop := int(_hit_of(att, "throw")["hitstop"])
	check(att.hitstop == stop and def.hitstop == stop, who + " throw: both fighters hold %d ticks of hitstop at the release" % stop)
	var launch: Vector2 = _hit_of(att, "throw")["launch"]
	check(is_equal_approx(def.vel.y, launch.y) and is_equal_approx(def.vel.x, float(att.facing) * launch.x), who + " throw: the foe flies away with the kit's launch")
	check(is_equal_approx(float(def.guard), guard) and int(def._guard_idle) == idle and not def.last_block_jg, who + " throw: guard, its refill timer and just guard are untouched")
	check(_played("slam") == slam + 1, who + " throw: the release plays slam")
	check(att.move_hit and att.move_connected and def.combo_hits == 1, who + " throw: counts as one hit")
	# beats every defence
	_start_throw()
	def.guard_all = true
	check(_connect("throw") == "hit", who + " throw: beats a guard_all foe")
	_start_throw()
	_hold_back(def, 10)
	hp = float(def.hp)
	guard = float(def.guard)
	var held := _connect("throw") == "hit"
	_to_release()
	check(held and hp > float(def.hp) and is_equal_approx(float(def.guard), guard), who + " throw: beats a foe holding back, no chip, no drain")
	_start_throw()
	_hold_back(def, 1)
	check(_connect("throw") == "hit" and not def.last_block_jg, who + " throw: beats a just guard press")
	_start_throw()
	def.input = FI.from_held(def.input, 1, 1, [])
	def.tick()
	check(_connect("throw") == "hit", who + " throw: beats a crouch block")
	for s in [states.DASH, states.BACKDASH, states.WALK, states.CROUCH]:
		_start_throw()
		def._set_state(s)
		check(_connect("throw") == "hit", who + " throw: hits a foe in state %d" % s)
	_start_throw()
	def.state = states.ATTACK
	def.move = {"cutin": false, "super": false, "air": false, "cancel": [], "hit": {}, "spawns": [], "frames": 30, "startup": 5, "active": 5, "armor": {"from": 0, "to": 29, "hits": 3, "dmg": 0.5}, "counter": {"from": 0, "to": 29, "move": "", "text": "X", "meter": 8.0}}
	def.armor_hits_left = 3
	def.mf = 3
	hp = float(def.hp)
	held = _connect("throw") == "hit"
	_to_release()
	check(held and is_equal_approx(hp - float(def.hp), _expected("throw")) and def.state == states.AIRHIT, who + " throw: beats an armor and a counter window, at full damage")
	# what it misses
	var misses := {"hit": states.HIT, "airhit": states.AIRHIT, "block": states.BLOCK, "down": states.DOWN, "getup": states.GETUP, "ko": states.KO}
	for n in misses:
		_start_throw()
		def.state = misses[n]
		hp = float(def.hp)
		check(_connect("throw") == "miss" and is_equal_approx(hp, float(def.hp)), who + " throw: misses a foe in " + n)
	_start_throw()
	def.crush_t = 20
	def.state = states.BLOCK
	check(_connect("throw") == "miss", who + " throw: misses a guard-crushed foe, who takes a normal combo")
	_start_throw()
	def.position.y = A.GROUND - 200.0
	def._set_state(states.JUMP)
	check(_connect("throw") == "miss", who + " throw: misses a jumping foe")
	_start_throw()
	def.state = states.ATTACK
	def.move = {"cutin": true, "super": false, "air": false, "cancel": [], "hit": {}, "spawns": [], "frames": 30, "startup": 5, "active": 5}
	check(_connect("throw") == "miss", who + " throw: misses a foe inside a cut-in move")
	_start_throw()
	def.state = states.ATTACK
	def.powered = true
	def.move = {"cutin": false, "super": false, "air": false, "cancel": [], "hit": {}, "spawns": [], "frames": 30, "startup": 5, "active": 5}
	check(_connect("throw") == "miss", who + " throw: misses a foe in a powered super")
	_start_throw()
	def.state = states.IDLE
	def.move = {"cutin": true, "super": false, "air": false, "cancel": [], "hit": {}, "spawns": [], "frames": 30, "startup": 5, "active": 5}
	check(_connect("throw") == "hit", who + " throw: a foe who was hit out of a cut-in move and stands idle is thrown")
	_start_throw()
	def.invuln = 5
	check(_connect("throw") == "miss", who + " throw: misses an invulnerable foe")
	_start_throw()
	def.shield_frames = 30
	hp = float(def.hp)
	check(_connect("throw") == "block" and is_equal_approx(hp, float(def.hp)) and def.shield_frames == 0, who + " throw: an assist shield absorbs it")
	for k in ["throw", "close_L", "6L"]:
		_place(80.0 if k != "6L" else 120.0)
		def.shield_frames = 30
		hp = float(def.hp)
		att.input = FI.from_held(att.input, 1 if k == "6L" else 0, 0, ["light", "heavy"] if k == "throw" else ["light"])
		att.tick()
		for i in 30:
			_step()
		check(is_equal_approx(hp, float(def.hp)) and def.state != states.AIRHIT and def.shield_frames <= 0, who + " " + k + ": an assist shield soaks the whole move, not only its first active tick (hp %.0f)" % def.hp)
	# a foe at the wall is not snapped through it
	_place(110.0)
	att.position.x = A.HALF_W - 40.0
	def.position.x = A.HALF_W - 5.0
	att._start_move("throw")
	_connect("throw")
	_to_release()
	check(def.position.x <= A.HALF_W, who + " throw: the carry stays inside the arena")
	# through the real tick: startup, a hit on the active frame, hitstop
	_place(100.0)
	_press(att, ["light", "heavy"])
	var landed := -1
	for i in 30:
		_step()
		if def.state == states.AIRHIT:
			landed = int(att.mf)
			break
	check(landed == int(att.moves["throw"]["startup"]), who + " throw: lands on its first active frame (mf %d)" % landed)
	# a whiff: the recovery is the full move
	_place(300.0)
	att._start_move("throw")
	var ticks := 0
	while att.state == states.ATTACK and ticks < 80:
		_step()
		ticks += 1
	var frames := int(att.moves["throw"]["frames"])
	check(ticks == frames and int(att.moves["throw"]["recovery"]) >= 28, who + " throw: a whiff takes the whole move (%d of %d ticks)" % [ticks, frames])
	check(is_equal_approx(def.hp, def.max_hp), who + " throw: a whiff does nothing")

# ── the tech ─────────────────────────────────────────────────────────────────
func _both_throw(def_head_start: int) -> void:
	_place(100.0)
	def._start_move("throw")
	for i in def_head_start:
		def.tick()
	att._start_move("throw")

func _clash() -> void:
	var who := _name()
	# both active on the same tick, through the screen's two-connect resolution
	_both_throw(1)
	var n := _played("tech")
	var texts := _text_count("TECH")
	var gap0 := absf(def.position.x - att.position.x)
	var ticks := 0
	while att.state == states.ATTACK and def.state == states.ATTACK and ticks < 40:
		_step()
		ticks += 1
	check(att.state != states.ATTACK and def.state != states.ATTACK, who + " tech: both moves end")
	check(att.move.is_empty() and def.move.is_empty(), who + " tech: neither fighter keeps a move")
	check(is_equal_approx(att.hp, att.max_hp) and is_equal_approx(def.hp, def.max_hp), who + " tech: nobody takes damage")
	check(att.state != states.AIRHIT and def.state != states.AIRHIT and att.state != states.DOWN and def.state != states.DOWN, who + " tech: nobody is thrown")
	check(att.hitstop == 8 and def.hitstop == 8, who + " tech: both hold 8 ticks of hitstop")
	check(att.carrying == null and def.carrying == null and att.carrier == null and def.carrier == null, who + " tech: nobody is carried")
	check(absf(def.position.x - att.position.x) > gap0, who + " tech: they are pushed apart")
	check(_played("tech") == n + 1 and _text_count("TECH") == texts + 1, who + " tech: one sound and one TECH text")
	# either order of the two connects gives the same result
	for first_att in [true, false]:
		_both_throw(1)
		while att.mf < int(att.moves["throw"]["startup"]) or def.mf < int(def.moves["throw"]["startup"]):
			att.input = FI.from_held(att.input, 0, 0, [])
			def.input = FI.from_held(def.input, 0, 0, [])
			att.tick()
			def.tick()
		var a := att if first_att else def
		var b := def if first_att else att
		var t0 := _text_count("TECH")
		b.receive_hit(a, a.moves["throw"]["hit"], a.position, false)
		a.receive_hit(b, b.moves["throw"]["hit"], b.position, false)
		check(a.state != states.ATTACK and b.state != states.ATTACK and is_equal_approx(a.hp, a.max_hp) and is_equal_approx(b.hp, b.max_hp), who + " tech: the second connect cannot throw the first fighter (att first %s)" % str(first_att))
		check(_text_count("TECH") == t0 + 1, who + " tech: one text whichever connect lands first (att first %s)" % str(first_att))
	# a throw against a foe still in its own throw's startup is a tech too, so a one tick head start does not decide it
	_both_throw(0)
	att.tick()
	check(String(def.receive_hit(att, att.moves["throw"]["hit"], att.position, false)) == "miss" and def.state != states.ATTACK and att.state != states.ATTACK, who + " tech: a throw into the foe's throw startup clashes")
	# a throw and a strike that connect on the same tick trade, whichever connect lands first
	for strike_first in [true, false]:
		_place(80.0)
		att._start_move("throw")
		def._start_move("close_L")
		while att.mf < int(att.moves["throw"]["startup"]) or def.mf < int(def.moves["close_L"]["startup"]):
			att.input = FI.from_held(att.input, 0, 0, [])
			def.input = FI.from_held(def.input, 0, 0, [])
			att.tick()
			def.tick()
		var t_hp := float(att.hp)
		var d_hp := float(def.hp)
		if strike_first:
			att.receive_hit(def, def.moves["close_L"]["hit"], def.position, false)
			def.receive_hit(att, att.moves["throw"]["hit"], att.position, false)
		else:
			def.receive_hit(att, att.moves["throw"]["hit"], att.position, false)
			att.receive_hit(def, def.moves["close_L"]["hit"], def.position, false)
		check(float(att.hp) < t_hp and float(def.hp) < d_hp and def.state == states.AIRHIT, who + " tech: a same-tick strike and throw trade (strike first %s)" % str(strike_first))
	# a throw into the foe's recovery is a plain throw
	_place(100.0)
	def._start_move("throw")
	def.mf = int(def.move["startup"]) + int(def.move["active"])
	att._start_move("throw")
	att.mf = int(att.move["startup"])
	check(_connect("throw") == "hit" and def.state == states.AIRHIT, who + " tech: a whiffing throw in recovery is punished")

# ── strikes against a blocking foe ───────────────────────────────────────────
func _strikes() -> void:
	var who := _name()
	for key in ["close_L", "close_H", "6L"]:
		_place(100.0)
		_hold_back(def, 10)
		var guard := float(def.guard)
		var h := _hit_of(att, key)
		check(_connect(key) == "block" and def.state == states.BLOCK, "%s %s: holding back blocks it" % [who, key])
		var drain: float = float(h["dmg"]) * att.hit_mult(false) * A.GUARD_DRAIN * float(att.stats["guard_dealt"])
		check(is_equal_approx(guard - float(def.guard), drain), "%s %s: drains guard by dmg x 0.8 x guard_dealt (%.1f)" % [who, key, drain])
	_place(100.0)
	_hold_back(def, 10)
	check(_connect("6H") == "block", who + " 6H: a standing block stops the overhead")
	_place(100.0)
	def.input = FI.from_held(def.input, 1, 1, [])
	def.tick()
	check(_connect("6H") == "hit", who + " 6H: a crouch block loses to the overhead")
	_place(100.0)
	def.input = FI.from_held(def.input, 1, 1, [])
	def.tick()
	check(_connect("close_L") == "block", who + " close_L: a crouch block stops a mid strike")
	# a strike is a hit: stun and push land as authored
	_place(100.0)
	var h2 := _hit_of(att, "close_L")
	check(_connect("close_L") == "hit" and def.state == states.HIT and int(def.hitstun) == int(h2["hitstun"]), who + " close_L: hits for its hitstun")
	# a strike leaves Hina's magazine alone
	if who == "hina":
		for key in ["close_L", "close_H", "6L", "6H", "throw"]:
			_place(100.0)
			att.kv["mag"] = 30
			att._start_move(key)
			check(int(att.kv["mag"]) == 30 and int(att.kv["lock_t"]) == 0, "hina %s: the magazine is not spent and Lock & Load is not fed" % key)
		_place(100.0)
		att.kv["mag"] = 1
		att._start_move("close_H")
		check(int(att.kv["mag"]) == 1 and int(att.kv["lock_t"]) == 0, "hina close_H: an empty-looking magazine does not reload from a strike")

func _hoshino_armor() -> void:
	att = screen.f1
	def = screen.f2
	_place(100.0)
	def._start_move("close_H")
	for i in 6:
		def.tick()
	check(def.state == states.ATTACK and def.mf >= 3 and def.mf <= 11, "hoshino close_H: inside its armor window")
	var hp := float(def.hp)
	var h := _hit_of(att, "5L")
	var res := String(def.receive_hit(att, h, att.position, false))
	var adm: float = float(h["dmg"]) * att.hit_mult(false) * 0.5 * float(def.stats["taken"])
	check(res == "hit" and def.state == states.ATTACK and def.move_key == "close_H", "hoshino close_H: the first hit is absorbed and the strike keeps going")
	check(is_equal_approx(hp - float(def.hp), adm), "hoshino close_H: the absorbed hit costs half damage (%.1f)" % (hp - float(def.hp)))
	def.hitstop = 0
	res = String(def.receive_hit(att, h, att.position, false))
	check(def.state != states.ATTACK, "hoshino close_H: the second hit trades and ends the strike")
	_place(100.0)
	def._start_move("close_H")
	for i in 14:
		def.tick()
	check(def.mf > 11, "hoshino close_H: past frame 11")
	res = String(def.receive_hit(att, h, att.position, false))
	check(def.state != states.ATTACK, "hoshino close_H: no armor after frame 11")

# ── sound hooks ──────────────────────────────────────────────────────────────
func _sounds() -> void:
	var who := _name()
	for k in [["close_L", "swing"], ["6L", "swing"], ["close_H", "swing"], ["6H", "swing"], ["throw", "throw"]]:
		_place(100.0)
		var n := _played(k[1])
		att._start_move(k[0])
		check(_played(k[1]) == n + 1, "%s %s: starting it plays %s" % [who, k[0], k[1]])
	_place(100.0)
	var lo := _played("hit_l")
	_connect("close_L")
	check(_played("hit_l") == lo + 1, who + " close_L: the hit plays hit_l")
	_place(100.0)
	var hi := _played("hit_h")
	_connect("close_H")
	check(_played("hit_h") == hi + 1, who + " close_H: the hit plays hit_h")

# ── the CPU ──────────────────────────────────────────────────────────────────
func _brain(level: int, seed_value: int) -> Object:
	var b = load("res://scripts/fight/cpu_brain.gd").new()
	b.setup(def, att, level, seed_value)
	return b

func _cpu() -> void:
	att = screen.f1
	def = screen.f2
	_place(100.0)
	att._start_move("throw")
	check(_brain(1, 1)._threat(100.0) == "throw", "cpu: a throw in startup is a throw threat")
	att._start_move("6H")
	check(_brain(1, 1)._threat(100.0) == "high", "cpu: a 6H is an overhead threat")
	att._start_move("close_L")
	check(_brain(1, 1)._threat(100.0) == "mid", "cpu: a close strike is a mid threat")
	var taps := [0, 0, 0, 0]
	var blocked := 0
	for level in 4:
		for seed_value in 400:
			_place(100.0)
			att._start_move("throw")
			var b = _brain(level, seed_value)
			var fi = b.think()
			if fi.is_held("light") and fi.is_held("heavy"):
				taps[level] += 1
			if int(b._block_t) > 0 or b._jg:
				blocked += 1
	check(taps[0] == 0, "cpu: level 0 never reacts to a throw (%d of 400)" % taps[0])
	check(taps[1] > 20 and taps[1] < 65, "cpu: level 1 taps light + heavy about 10%% of the time (%d of 400)" % taps[1])
	check(taps[2] > 70 and taps[2] < 135, "cpu: level 2 about 25%% (%d of 400)" % taps[2])
	check(taps[3] > 125 and taps[3] < 200, "cpu: level 3 about 40%% (%d of 400)" % taps[3])
	check(blocked == 0, "cpu: it never holds block against a throw (%d)" % blocked)
	# strings
	var strings := {}
	for key in ["5L", "close_L", "6L", "5H", "close_H", "6H"]:
		var seen := {}
		for seed_value in 60:
			_place(100.0)
			att._start_move(key)
			att.chain = 0
			var b = _brain(2, seed_value)
			b.me = att
			b.foe = def
			seen[b._next_in_string()] = true
		strings[key] = seen.keys()
		strings[key].sort()
	check(strings["close_L"] == strings["5L"] and strings["6L"] == strings["5L"], "cpu: close_L and 6L continue like 5L " + str(strings["close_L"]))
	check(strings["close_H"] == strings["5H"] and strings["6H"] == strings["5H"], "cpu: close_H and 6H continue like 5H " + str(strings["close_H"]))
	check("heavy" in strings["close_L"] and "skill" in strings["close_H"], "cpu: the strings exist")
	# close range plans
	var throws := 0
	var far := 0
	for seed_value in 300:
		for dist in [100.0, 150.0]:
			_place(dist)
			var b = _brain(3, seed_value)
			b.me = att
			b.foe = def
			b._choose(dist)
			if b._plan == "throw":
				if dist < A.THROW_RANGE:
					throws += 1
				else:
					far += 1
	check(throws > 5 and throws < 80, "cpu: it picks a throw plan close in now and then (%d of 300)" % throws)
	check(far == 0, "cpu: never past throw range (%d)" % far)
	_place(100.0)
	def.position.y = A.GROUND - 200.0
	def._set_state(states.JUMP)
	var air := 0
	for seed_value in 300:
		var b = _brain(3, seed_value)
		b.me = att
		b.foe = def
		b._choose(100.0)
		if b._plan == "throw":
			air += 1
	check(air == 0, "cpu: never plans a throw against a foe who is not actionable")

# ── the generic throw and the audit ──────────────────────────────────────────
func _generic() -> void:
	if not M.get_script_method_list().any(func(m: Dictionary) -> bool: return m["name"] == "throw_for"):
		check(false, "Movesets.throw_for exists")
		return
	var base := {"bullet": "Pierce", "role": "DamageDealer", "armor": "Unarmed", "key": ""}
	var styles := {
		"AR": ["TOSS", 7, 3, 28, 72.0, Vector2(7, -6.5), 8], "SMG": ["SWEEP", 6, 3, 24, 62.0, Vector2(4.5, -2.5), 6], "SR": ["SHOVE", 6, 3, 28, 56.0, Vector2(11, -3), 8],
		"SG": ["HURL", 8, 3, 30, 80.0, Vector2(9.5, -4.5), 6], "MG": ["SLAM", 7, 3, 28, 70.0, Vector2(6, 5), 10], "HG": ["SWEEP", 6, 3, 24, 62.0, Vector2(4.5, -2.5), 6]}
	for w in styles:
		var s: Array = styles[w]
		var d: Dictionary = base.duplicate()
		d["weapon"] = w
		var st: Dictionary = M.stats_for(d)
		var m: Dictionary = M.throw_for(d, st)
		var h: Dictionary = m["hit"]
		check(m.get("style", "") == s[0], w + ": generic throw is a " + String(s[0]))
		check(int(m["startup"]) == s[1] and int(m["active"]) == s[2] and int(m["recovery"]) == s[3], "%s: generic throw %d/%d/%d" % [w, s[1], s[2], s[3]])
		check(is_equal_approx(float(h["dmg"]), float(s[4]) * float(st["dmg"])), "%s: generic throw raw %d x dmg" % [w, s[4]])
		check(is_equal_approx(h["rect"].size.x, 105.0 * float(st["reach"])) and is_equal_approx(h["rect"].size.y, 170.0) and h["rect"].position == Vector2(0, -200), w + ": generic throw reach follows the weapon")
		check(bool(h["throw"]) and bool(h["kd"]) and h["launch"] == s[5] and is_equal_approx(float(h["snap"]), 80.0) and int(h["hitstop"]) == s[6], w + ": generic throw flags")
		check(not m.get("swish", true) and m["cancel"].is_empty() and not m["cutin"] and is_equal_approx(float(m["cost"]), 0.0), w + ": generic throw has no swing arc, cancel or cost")
		check(m.has("carry") == (w != "SR"), w + ": only the sniper's shove has no carry")
	var kits = load("res://scripts/fight/kits.gd")
	var own := 0
	var plain := 0
	var gun_kits := 0
	for e in game.fighters:
		var k = kits.make(e)
		var st: Dictionary = k.build_stats()
		var moves: Dictionary = k.build_moves(st)
		var key := String(e["key"])
		var has_throw := moves.has("throw")
		if key in ["hina", "hoshino"]:
			own += 1 if has_throw else 0
		else:
			plain += 1 if not has_throw else 0
			check(not moves.has("close_L") and not moves.has("6L") and not moves.has("6H"), key + ": a sprite kit defines no strike or command keys, so it keeps 5L and 5H on forward")
		var guns := false
		for n in ["5L", "5H"]:
			guns = guns or not (moves[n].get("shots", []) as Array).is_empty()
		if guns:
			gun_kits += 1
			check(moves.has("close_L") and moves.has("close_H"), key + ": a kit whose normals are gun shots defines close_L and close_H")
		var g: Dictionary = M.throw_for(e, st)
		check(bool(g["hit"]["throw"]) and String(g.get("style", "")) != "", key + ": the generic throw builds for every roster entry")
	check(own == 2, "hina and hoshino define their own throw (%d)" % own)
	check(plain == game.fighters.size() - 2, "the other %d kits define none, so Fighter.setup merges the generic one (%d)" % [game.fighters.size() - 2, plain])
	check(gun_kits == 2, "only Hina and Hoshino fire their normals (%d)" % gun_kits)
	check(screen.f1.moves["throw"].has("source") and screen.f2.moves["throw"].has("source"), "a kit's own throw is not overwritten by the generic one")
