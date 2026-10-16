extends SceneTree
## Per-character push widths: the number in sockets.json and
## the rule that measures it, the pair minimum and the wall-aware push, the ranges, melee rects, throw snap and teleports that
## shift by the extra spacing, the push that stands aside while a carry runs, the idle pose while walking into the foe, the Dbg gap key, and how far the trunks overlap at the
## minimum spacing. Hina and Hoshino only.
## Run with TEST=res://scripts/models/tests/push_test.gd tools/sd_test.sh (a real small window).
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

const WIDTH := {"hina": 120, "hoshino": 116}
const PAIRINGS := [["hina", "hoshino"], ["hoshino", "hina"], ["hina", "hina"], ["hoshino", "hoshino"]]
const IDS := {"hina": 10004, "hoshino": 10005}
const STAND := ["idle", "crouch", "block", "block_low", "block_air", "hit", "jump", "intro"]
const STAND_CAP := 8.0
const LYING := ["down", "ko"]   # never pushed (see _push), so their trunks may lie across the foe
## Overlap caps in px by "fighter pose", each the worst of the first run on the real models (against both fighters, on both
## sides) rounded up plus 1, and 0 for a pose that leaves air between the trunks. The lean clips (walk, dash, the intro run) and
## the lunging strikes overlap on purpose; walking into the foe at the minimum shows the idle pose instead (_walk).
const CAPS := {
	"hina airhit": 0, "hina backdash": 0, "hina carried": 8, "hina dash": 90, "hina dash_air": 10, "hina dash_air_back": 0, "hina getup": 207,
	"hina glide": 0, "hina intro_cut": 0, "hina intro_idle": 0, "hina intro_run": 90, "hina intro_stop": 46, "hina walk": 67, "hina walk_back": 68, "hina win": 11,
	"hina move:2H": 0, "hina move:2L": 0, "hina move:5H": 4, "hina move:5L": 0, "hina move:6H": 6, "hina move:6L": 7,
	"hina move:close_H": 3, "hina move:close_L": 0, "hina move:ex": 0, "hina move:jH": 0, "hina move:jL": 0, "hina move:skill": 4,
	"hina move:skill_air": 0, "hina move:super": 4, "hina move:super_down": 0, "hina move:throw": 6,
	"hoshino airhit": 0, "hoshino backdash": 0, "hoshino carried": 2, "hoshino dash": 45, "hoshino getup": 0, "hoshino intro_cut": 4, "hoshino intro_idle": 4, "hoshino intro_run": 45,
	"hoshino intro_stop": 33, "hoshino walk": 19, "hoshino walk_back": 19, "hoshino win": 51,
	"hoshino move:2H": 1, "hoshino move:2L": 28, "hoshino move:5H": 11, "hoshino move:5L": 11, "hoshino move:6H": 38,
	"hoshino move:6L": 34, "hoshino move:close_H": 35, "hoshino move:close_L": 40, "hoshino move:ex": 10, "hoshino move:jH": 48,
	"hoshino move:jL": 39, "hoshino move:skill": 11, "hoshino move:skill_air": 26, "hoshino move:super": 6,
	"hoshino move:super_down": 11, "hoshino move:throw": 33,
}

var checks := 0
var failures: Array = []
var game: Node
var FI: GDScript
var A: GDScript
var measure_tool: Script
var sockets: Script
var S: Dictionary
var screen: Node
var f1: Node
var f2: Node
var extra := 0.0   # how much farther apart than Arena.PUSH_W this pairing stands, from the widths above, not from the engine

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("PUSH_CHECK FAIL ", label)
		failures.append(label)

func _run() -> void:
	create_timer(900.0).timeout.connect(func() -> void:
		print("PUSH_TEST FAIL watchdog timeout")
		quit(3))
	await process_frame
	FI = load("res://scripts/fight/fight_input.gd")
	A = load("res://scripts/fight/arena.gd")
	measure_tool = load("res://scripts/models/tools/sd_measure.gd")
	sockets = load("res://scripts/models/sd_sockets.gd")
	game = root.get_node("Game")
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	for pair in PAIRINGS:
		await _boot(pair[0], pair[1])
		if pair == PAIRINGS[0]:
			_data()
			_sprites()
			_overlap()
		_push(pair)
		_corner(pair)
		extra = _want(pair) - A.PUSH_W
		_ranges(pair)
		_snap(pair)
		_teleport(pair)
		_cpu(pair)
		_walk(pair)
		_glide(pair)
		_dbg_gap(pair)
		if pair == PAIRINGS[0]:
			_reach()
	print("PUSH_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

# ── helpers ──────────────────────────────────────────────────────────────────
## A fresh training fight with `left` as player 1 and `right` as player 2.
func _boot(left: String, right: String) -> void:
	game.session.begin("training")
	game.session.players[0]["fighter"] = IDS[left]
	game.session.players[1]["fighter"] = IDS[right]
	await game.go("fight", {}, "cut")
	screen = game.stack.back()
	screen.set_physics_process(false)
	screen.phase = "fight"
	S = screen.f1.get_script().S
	f1 = screen.f1
	f2 = screen.f2

func _idle(f: Node) -> void:
	f._set_state(S.IDLE)
	f.input = FI.new()
	f.hitstop = 0
	f.invuln = 0
	f.vel = Vector2.ZERO

## f1 stands at x1 facing right, f2 `dx` px to its right facing left, both idle on the floor.
func _place(x1: float, dx: float) -> void:
	f1.reset_round(x1, 1)
	f2.reset_round(x1 + dx, -1)
	_idle(f1)
	_idle(f2)

func _want(pair: Array) -> float:
	return float(WIDTH[pair[0]] + WIDTH[pair[1]]) * 0.5

func _gap() -> float:
	return absf(f2.position.x - f1.position.x)

func _stats_of(key: String) -> Dictionary:
	for e in game.fighters:
		if String(e["key"]) == key:
			return load("res://scripts/fight/kits.gd").make(e).build_stats()
	return {}

# ── the number ───────────────────────────────────────────────────────────────
func _data() -> void:
	for f in [f1, f2]:
		var key := String(f.data["key"])
		check(int(sockets.push(key)) == WIDTH[key], "%s: sockets.json push is %d" % [key, WIDTH[key]])
		check(is_equal_approx(f.push_w(), float(WIDTH[key])), "%s: push_w() is %d" % [key, WIDTH[key]])
		check(float(f.stats.get("hurt_w", 0.0)) <= float(WIDTH[key]), key + ": the hurtbox sits inside the cylinder")
		check(measure_tool.push_width(f.view.sd_actor) == WIDTH[key], "%s: the measuring rule gives %d" % [key, WIDTH[key]])
	var kits = load("res://scripts/fight/kits.gd")
	var plain := 0
	for e in game.fighters:
		var key := String(e["key"])
		var st: Dictionary = kits.make(e).build_stats()
		if key in WIDTH:
			check(is_equal_approx(float(st.get("push_w", 0.0)), float(WIDTH[key])), key + ": build_stats sets push_w from sockets.json")
		else:
			plain += 1 if not st.has("push_w") else 0
	check(plain == game.fighters.size() - 2, "the other %d kits keep the default push width (%d)" % [game.fighters.size() - 2, plain])
	check(is_equal_approx(A.PUSH_W, 74.0), "Arena.PUSH_W stays 74, the legacy width every range was authored against")

## Bare Fighter nodes (stats only, never in the tree).
func _bare(stats: Dictionary) -> Node:
	var f: Node = (load("res://scripts/fight/fighter.gd") as GDScript).new()
	f.stats = stats
	return f

func _sprites() -> void:
	var made := {}
	for k in ["hina", "hoshino"]:
		made[k] = [_bare(_stats_of(k)), _bare(_stats_of(k))]
	for case in [["hina", "hoshino", 118.0]]:
		var a: Node = made[case[0]][0]
		var b: Node = made[case[1]][1]
		a.foe = b
		b.foe = a
		check(is_equal_approx(a.push_min(), case[2]) and is_equal_approx(b.push_min(), case[2]), "%s v %s: pair minimum %.0f" % [case[0], case[1], case[2]])
		check(is_equal_approx(a.spacing_extra(), case[2] - 74.0), "%s v %s: spacing extra %.0f" % [case[0], case[1], case[2] - 74.0])
	var lone: Node = made["hina"][0]
	lone.foe = null
	check(is_equal_approx(lone.spacing_extra(), 0.0) and is_equal_approx(lone.push_min(), 120.0), "no foe: no extra spacing, the own width is the minimum")
	for k in made:
		for f in made[k]:
			f.free()

# ── the push ─────────────────────────────────────────────────────────────────
func _push(pair: Array) -> void:
	var tag := "%s v %s" % pair
	var want := _want(pair)
	check(is_equal_approx(f1.push_min(), want) and is_equal_approx(f2.push_min(), want), "%s: the pair minimum is %.0f" % [tag, want])
	check(is_equal_approx(f1.spacing_extra(), want - A.PUSH_W), "%s: the spacing extra is %.0f" % [tag, want - A.PUSH_W])
	# one call lands exactly on the minimum, each fighter moving the same amount about the middle
	for dx in [0.0, 30.0, want - 1.0]:
		_place(-200.0, dx)
		var mid: float = (f1.position.x + f2.position.x) * 0.5
		screen._push_apart()
		check(absf(_gap() - want) < 0.01, "%s: from %.0f px apart one push leaves %.2f (want %.0f)" % [tag, dx, _gap(), want])
		check(absf((f1.position.x + f2.position.x) * 0.5 - mid) < 0.01, "%s: from %.0f px apart both move the same amount" % [tag, dx])
	_place(-200.0, want)
	var before := [f1.position.x, f2.position.x]
	screen._push_apart()
	check([f1.position.x, f2.position.x] == before, "%s: at the minimum nobody moves" % tag)
	_place(-200.0, want + 0.5)
	screen._push_apart()
	check(absf(_gap() - (want + 0.5)) < 0.001, "%s: half a px past the minimum nobody moves" % tag)
	# the height gate: a jumper whose feet are under 170 px apart is pushed, one above that is not
	for dy in [169.0, 170.0]:
		_place(-200.0, 30.0)
		f1.position.y = A.GROUND - dy
		f1._set_state(S.JUMP)
		screen._push_apart()
		check((absf(_gap() - want) < 0.01) == (dy < 170.0), "%s: feet %.0f px apart in height %s" % [tag, dy, "push" if dy < 170.0 else "do not push"])
	# DOWN and KO lie on the floor and are never pushed, from either side
	for st in [S.DOWN, S.KO]:
		for lying in [f1, f2]:
			_place(-200.0, 30.0)
			lying.state = st
			screen._push_apart()
			check(is_equal_approx(_gap(), 30.0), "%s: %s fighter %d is not pushed" % [tag, f1.STATE_NAMES[st], lying.slot])
	# HIT, BLOCK, GETUP and ATTACK fighters are pushed
	for st in [S.HIT, S.AIRHIT, S.BLOCK, S.GETUP, S.ATTACK]:
		_place(-200.0, 30.0)
		f1.state = st
		screen._push_apart()
		check(absf(_gap() - want) < 0.01, "%s: a fighter in %s is pushed" % [tag, f1.STATE_NAMES[st]])
	_place(-200.0, 30.0)

## A fighter pressed into a wall, walking and dashing: the pair never closes under the minimum, whichever side the wall is on.
func _corner(pair: Array) -> void:
	var tag := "%s v %s" % pair
	var want := _want(pair)
	for wall in [-1.0, 1.0]:
		for mode in ["walk", "dash"]:
			var target: Node = f1 if wall < 0.0 else f2
			var presser: Node = f2 if wall < 0.0 else f1
			_place(-300.0, 300.0)
			target.position.x = wall * A.HALF_W
			presser.position.x = wall * (A.HALF_W - 260.0)
			var low := 1e9
			for t in 140:
				presser.input = FI.from_held(presser.input, int(wall), 0, ["dash"] if mode == "dash" and t % 24 == 0 else [])
				target.input = FI.from_held(target.input, 0, 0, [])
				f1.tick()
				f2.tick()
				screen._push_apart()
				low = minf(low, _gap())
			var label := "%s: %s into the %s wall" % [tag, mode, "left" if wall < 0.0 else "right"]
			check(low > want - 0.01, label + " never closes under %.0f (lowest %.2f)" % [want, low])
			check(absf(_gap() - want) < 0.01, label + " ends at the minimum (%.2f)" % _gap())
			check(absf(f1.position.x) <= A.HALF_W and absf(f2.position.x) <= A.HALF_W, label + ": both stay inside the arena")
	_place(-200.0, 300.0)

# ── ranges, snap, teleports: legacy distance + the spacing extra ─────────────
## `att` presses `btns` (forward held when `fwd`, down when `down`) with the foe `legacy` px away: the legacy distance the
## ranges were authored against, so centres are legacy + extra. Returns the move that started.
func _key(att: Node, legacy: float, btns: Array, fwd := false, down := false, foe_air := false) -> String:
	_place(-300.0, legacy + extra)
	if foe_air:
		att.foe.position.y = A.GROUND - 200.0
		att.foe._set_state(S.JUMP)
	att.input = FI.from_held(att.input, att.facing if fwd else 0, 1 if down else 0, btns)
	att.tick()
	return String(att.move_key) if att.state == S.ATTACK else ""

func _ranges(pair: Array) -> void:
	for att in [f1, f2]:
		var who := "%s v %s, %s attacks" % [pair[0], pair[1], "left" if att == f1 else "right"]
		for b in [["light", "L"], ["heavy", "H"]]:
			check(_key(att, 96.0, [b[0]]) == "close_" + b[1], "%s: %s at legacy 96 starts close_%s" % [who, b[0], b[1]])
			check(_key(att, 97.0, [b[0]]) == "5" + b[1], "%s: %s at legacy 97 starts 5%s" % [who, b[0], b[1]])
			check(_key(att, 74.0, [b[0]]) == "close_" + b[1], "%s: %s standing at the minimum starts close_%s" % [who, b[0], b[1]])
			check(_key(att, 160.0, [b[0]], true) == "6" + b[1], "%s: forward + %s at legacy 160 starts 6%s" % [who, b[0], b[1]])
			check(_key(att, 161.0, [b[0]], true) == "5" + b[1], "%s: forward + %s at legacy 161 starts 5%s" % [who, b[0], b[1]])
		check(_key(att, 120.0, ["light", "heavy"]) == "throw", who + ": the chord throws at legacy 120")
		check(_key(att, 121.0, ["light", "heavy"]) == "5H", who + ": the chord is a plain heavy at legacy 121")
		check(_key(att, 60.0, ["light"], false, false, true) == "5L", who + ": an airborne foe keeps the gun normal")

## A throw with no carry dict snaps the foe `snap` plus the extra spacing in front and leaves the thrower where it stands; a carried
## throw grabs the foe where it stands, and the push leaves both alone while one holds the other.
func _snap(pair: Array) -> void:
	for att in [f1, f2]:
		for carried in [false, true]:
			var who := "%s v %s, %s throws%s" % [pair[0], pair[1], "left" if att == f1 else "right", " carried" if carried else " snapped"]
			for legacy in [60.0, 100.0, 120.0]:
				_place(-300.0, legacy + extra)
				att._start_move("throw")
				if not carried:
					att.move = att.moves["throw"].duplicate(true)
					att.move.erase("carry")
				var def: Node = att.foe
				var at: float = att.position.x
				var foe_at: float = def.position.x
				check(String(def.receive_hit(att, att.moves["throw"]["hit"], att.position, false)) == "hit", "%s at legacy %.0f: connects" % [who, legacy])
				screen._push_apart()
				var want := foe_at if carried else at + float(att.facing) * (80.0 + extra)
				check(absf(def.position.x - want) < 0.01, "%s at legacy %.0f: the foe stands %.0f px in front (%.2f)" % [who, legacy, absf(want - at), def.position.x - at])
				check(att.position.x == at, "%s at legacy %.0f: the thrower is not dragged back" % [who, legacy])

func _teleport(pair: Array) -> void:
	for att in [f1, f2]:
		var who := "%s v %s, %s teleports" % [pair[0], pair[1], "left" if att == f1 else "right"]
		for to in ["behind", "front", "away"]:
			_place(-300.0, 200.0)
			att._teleport({"to": to, "gap": 82.0})
			check(absf(absf(att.foe.position.x - att.position.x) - (82.0 + extra)) < 0.01, "%s %s: lands gap + extra (%.2f)" % [who, to, absf(att.foe.position.x - att.position.x)])

func _cpu(pair: Array) -> void:
	var cpu: GDScript = load("res://scripts/fight/cpu_brain.gd")
	for legacy in [119.5, 120.5]:
		var throws := 0
		for seed_value in 600:
			_place(-300.0, legacy + extra)
			var b: RefCounted = cpu.new()
			b.setup(f1, f2, 3, seed_value)
			b.think()
			if b._plan == "throw":
				throws += 1
		check((throws > 0) == (legacy < A.THROW_RANGE), "%s v %s: the CPU plans a throw only inside legacy 120 (%d of 600 at %.1f)" % [pair[0], pair[1], throws, legacy])

# ── the walk at the minimum, and the Dbg gap key ─────────────────────────────
## The anim sync() shows for `att` walking (state WALK) with the foe `gap` px past the pair minimum.
func _shown(att: Node, gap: float, state: int, dir: int) -> String:
	_place(-300.0, _want([att.data["key"], att.foe.data["key"]]) + gap)
	att._set_state(state)
	att.input = FI.from_held(att.input, dir * att.facing, 0, [])
	att.vel.x = float(dir * att.facing) * 3.0
	att.view.sd_actor.blending = false
	att.view.sd_actor._seen_frame = -1
	att.view.sd_actor.sync(att)
	return String(att.view.sd_actor.anim_name)

func _walk(pair: Array) -> void:
	for att in [f1, f2]:
		var who := "%s v %s, %s walks" % [pair[0], pair[1], "left" if att == f1 else "right"]
		check(_shown(att, 0.0, S.WALK, 1) == "idle", who + " into the foe at the minimum: stands")
		check(_shown(att, 2.0, S.WALK, 1) == "idle", who + " into the foe 2 px past the minimum: stands")
		check(_shown(att, 2.5, S.WALK, 1) == "walk", who + " into the foe 2.5 px past the minimum: walks")
		check(_shown(att, 40.0, S.WALK, 1) == "walk", who + " into the foe from afar: walks")
		check(_shown(att, 0.0, S.WALK, -1) == "walk_back", who + " away from the foe at the minimum: walks back")
		check(_shown(att, 0.0, S.DASH, 1) == "dash", who + " dashing at the minimum: dashes")
		check(_shown(att, 0.0, S.IDLE, 1) == "idle", who + " idle at the minimum: idle")
	_place(-300.0, 300.0)

## The anims sync() shows on the last 8 of 12 real ticks of `att` walking into the foe from `gap` px past the pair minimum
## (tick, the foe's own move, the push, sync). `foe_move` is called every tick to move or pose the foe.
func _glide_anims(att: Node, gap: float, foe_setup: Callable, foe_move: Callable) -> Array:
	var pair := [att.data["key"], att.foe.data["key"]]
	_place(-300.0, _want(pair) + gap)
	var foe: Node = att.foe
	foe_setup.call(foe)
	var actor: Node = att.view.sd_actor
	actor.blending = false
	actor._seen_frame = -1
	var seen: Array = []
	for t in 12:
		att.input = FI.from_held(att.input, att.facing, 0, [])
		att.tick()
		foe_move.call(foe, att)
		screen._push_apart()
		actor.sync(att)
		if t >= 4:
			seen.append(String(actor.anim_name))
	return seen

func _all(anims: Array, name: String) -> bool:
	for a in anims:
		if a != name:
			return false
	return true

## Idle while pressed means the push is really holding the body: a foe lying down, high up or moving away does not hold it.
func _glide(pair: Array) -> void:
	var none := func(_foe: Node, _att: Node) -> void: pass
	for att in [f1, f2]:
		var who := "%s v %s, %s walks" % [pair[0], pair[1], "left" if att == f1 else "right"]
		var shove := _glide_anims(att, 0.0, func(_foe: Node) -> void: pass, none)
		check(_all(shove, "idle"), who + " into a standing foe it shoves: stands (%s)" % str(shove))
		var down := _glide_anims(att, 1.0, func(foe: Node) -> void:
			foe._set_state(S.DOWN)
			foe.down_timer = 999, none)
		check(_all(down, "walk"), who + " at a foe lying down: walks, nothing holds it (%s)" % str(down))
		var up := _glide_anims(att, 1.0, func(foe: Node) -> void:
			foe.position.y = A.GROUND - 175.0
			foe._set_state(S.JUMP), none)
		check(_all(up, "walk"), who + " under a foe 175 px up: walks (%s)" % str(up))
		var chase := _glide_anims(att, 1.0, func(_foe: Node) -> void: pass, func(foe: Node, a: Node) -> void:
			foe.position.x += float(a.facing) * float(a.stats["walk"]))
		check(_all(chase, "walk"), who + " chasing a foe that walks away at its speed: walks (%s)" % str(chase))
		_place(-300.0, 400.0)
		att.position.x = -float(att.facing) * A.HALF_W
		att.foe.position.x = att.position.x + float(att.facing) * 400.0
		var actor: Node = att.view.sd_actor
		actor.blending = false
		actor._seen_frame = -1
		var wall: Array = []
		for t in 12:
			att.input = FI.from_held(att.input, -att.facing, 0, [])
			att.tick()
			screen._push_apart()
			actor.sync(att)
			if t >= 4:
				wall.append(String(actor.anim_name))
		check(_all(wall, "idle"), who + " into the wall: stands (%s)" % str(wall))
	_place(-300.0, 300.0)

## {"fighter": {"slot": n, "gap": g}} stands the slot on the side the other fighter faces, g px past the pair minimum.
func _dbg_gap(pair: Array) -> void:
	var dbg: Node = root.get_node("Dbg")
	var want := _want(pair)
	_place(-300.0, 300.0)
	dbg._fighter_step({"slot": 2, "gap": 26})
	check(absf(f2.position.x - (f1.position.x + float(f1.facing) * (want + 26.0))) < 0.01, "%s v %s: slot 2 gap 26 stands %.0f px from slot 1 (%.2f)" % [pair[0], pair[1], want + 26.0, f2.position.x - f1.position.x])
	dbg._fighter_step({"slot": 1, "gap": 0})
	check(absf(absf(f2.position.x - f1.position.x) - want) < 0.01, "%s v %s: slot 1 gap 0 stands at the minimum from slot 2" % [pair[0], pair[1]])
	check(f1.position.x < f2.position.x, "slot 1 stays on the side slot 2 faces")
	dbg._fighter_step({"slot": 2, "pos": [-300.0, 560.0], "gap": 0})
	check(absf(f2.position.x - (f1.position.x + float(f1.facing) * want)) < 0.01, "%s v %s: gap wins over pos in one step" % [pair[0], pair[1]])
	_place(-300.0, 300.0)

# ── how far the trunks overlap at the minimum spacing ────────────────────────
## Poses a fighter's can have, as {name, face, ext}: every state anim (10 samples), every kit move (every third frame, a held
## move also at its parking frame), both facings, blending off, with the trunk's (left, right) edge from the feet origin.
func _trunk_poses(f: Node) -> Array:
	var actor: Node = f.view.sd_actor
	actor.blending = false
	var prep: Array = measure_tool.trunk_prep(actor)
	var out: Array = []
	for face in [1, -1]:
		for name in actor.cfg["anims"]:
			var span: int = measure_tool.anim_span(actor, actor.cfg["anims"][name])
			var n := mini(span, 10)
			for i in n:
				var sf := roundi(float(i) * float(span - 1) / float(maxi(n - 1, 1)))
				actor.pose(name, sf, "", {}, 0, 0, face)
				out.append({"name": name, "face": face, "sf": sf, "ext": measure_tool.trunk_extent(actor, prep)})
		for key in f.moves:
			var mv: Dictionary = f.moves[key]
			var mf := -1
			while mf <= int(mv["frames"]) - 2:
				actor.pose("attack", 0, key, mv, mf, 0, face)
				out.append({"name": "move:" + key, "face": face, "sf": mf, "ext": measure_tool.trunk_extent(actor, prep)})
				mf += 3
			if mv.has("hold"):
				actor.pose("attack", 0, key, mv, int(mv["hold"]["at"]) - 1, int(mv["hold"]["max"]), face)
				out.append({"name": "move:" + key, "face": face, "sf": -2, "ext": measure_tool.trunk_extent(actor, prep)})
	return out

## Each pose of each fighter against the other fighter, and itself, standing idle at the engine's minimum spacing, on either
## side: how many px the trunks run into each other (negative: air between them). The first run on the real model gave the
## caps below; STAND poses share one cap, every other pose its own, and a pose with no cap is a failure so a new anim or move
## must be looked at. Guns, hair and wings are not trunk and overlap freely.
func _overlap() -> void:
	var table := {}
	var idle := {}
	var width := {}
	for f in [f1, f2]:
		var key := String(f.data["key"])
		width[key] = f.push_w()
		table[key] = _trunk_poses(f)
		for p in table[key]:
			if p["name"] == "idle" and p["sf"] == 0:
				idle[[key, p["face"]]] = p["ext"]
	var worst := {}
	for a in table:
		for p in table[a]:
			for b in table:
				var m: float = (float(width[a]) + float(width[b])) * 0.5
				var o: float = p["ext"].y - (m + idle[[b, -1]].x) if p["face"] == 1 else idle[[b, 1]].y - (m + p["ext"].x)
				var tag := "%s %s" % [a, p["name"]]
				if o > float(worst.get(tag, -1e9)):
					worst[tag] = o
	var names := worst.keys()
	names.sort()
	var seen := {}
	for tag in names:
		var name: String = String(tag).get_slice(" ", 1)
		seen[name] = true
		if OS.get_environment("PUSH_REPORT") != "":
			print("PUSH_POSE ", tag, " ", snappedf(worst[tag], 0.1))
		if name in STAND:
			check(worst[tag] <= STAND_CAP, "%s: the standing trunks overlap by %.1f px at most %.0f" % [tag, worst[tag], STAND_CAP])
		elif name in LYING:
			continue
		else:
			check(CAPS.has(tag) and worst[tag] <= float(CAPS[tag]), "%s: the trunks overlap by %.1f px, cap %s" % [tag, worst[tag], str(CAPS.get(tag, "none: look at this pose and add one"))])
	check(names.size() >= 60 and "idle" in seen and "move:throw" in seen, "the overlap test saw %d poses" % names.size())

# ── what a rect reaches ──────────────────────────────────────────────────────
## Bare fighters face to face: `att` (hina or hoshino, with its real moves) against a foe of `foe_key`.
func _duel(att_key: String, foe_key: String, d: float, att_left: bool) -> Array:
	var att: Node = _bare(_stats_of(att_key))
	var foe: Node = _bare(_stats_of(foe_key))
	att.moves = (f1 if f1.data["key"] == att_key else f2).moves
	att.foe = foe
	foe.foe = att
	att.facing = 1 if att_left else -1
	foe.facing = -att.facing
	att.position = Vector2(0.0 if att_left else d, A.GROUND)
	foe.position = Vector2(d if att_left else 0.0, A.GROUND)
	return [att, foe]

## The far edge of every melee rect grows by the spacing, so the reach beyond contact is what it was at 74 px: it connects
## up to half a px inside the old reach and misses half a px past it.
func _reach() -> void:
	var rects := 0
	var dead := 0
	for att_key in WIDTH:
		for foe_key in ["hina", "hoshino"]:
			for left in [true, false]:
				var duel := _duel(att_key, foe_key, 200.0, left)
				var att: Node = duel[0]
				var foe: Node = duel[1]
				var ex: float = (float(WIDTH[att_key]) + float(WIDTH.get(foe_key, 74))) * 0.5 - A.PUSH_W
				var tag := "%s v %s, %s attacks" % [att_key, foe_key, "left" if left else "right"]
				var hw: float = foe.hurtbox().size.x * 0.5
				for key in att.moves:
					var h: Dictionary = att.moves[key]["hit"]
					if h.is_empty() or (h["rect"] as Rect2).size == Vector2.ZERO:
						continue
					var r: Rect2 = h["rect"]
					var at := Rect2(att.position + r.position, r.size)
					var hb: Rect2 = foe.hurtbox()
					if at.position.y >= hb.end.y or at.end.y <= hb.position.y:
						continue   # never meets a standing foe in height, whatever the spacing
					rects += 1
					var reach := r.end.x + hw
					for probe in [[reach + ex - 0.5, true, "inside"], [reach + ex + 0.5, false, "past"]]:
						foe.position.x = att.position.x + float(att.facing) * probe[0]
						check(att.melee_rect(r).intersects(foe.hurtbox()) == probe[1], "%s %s: %s its old reach of %.1f px" % [tag, key, probe[2], reach])
					if att_key == "hina" and key in ["5L", "5H", "2L", "jL", "jH"]:
						foe.position.x = att.position.x + float(att.facing) * (A.PUSH_W + ex)
						dead += 1
						check(att.melee_rect(r).intersects(foe.hurtbox()), "%s %s: connects at the minimum spacing, no dead zone" % [tag, key])
				att.free()
				foe.free()
	check(rects >= 60 and dead == 20, "the reach test saw %d rects and %d dead-zone cases" % [rects, dead])
