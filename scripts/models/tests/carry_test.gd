extends SceneTree
## The carried throws (Hina's Takedown, Hoshino's Shoulder Toss): the carry dict, the grab, the foe's path tick by tick, the
## release, the aborts, the walls, the hand fit and the order independence. Hina and Hoshino only.
## Every distance is a legacy distance (centres minus Fighter.spacing_extra()), placed through _place().
## Run with TEST=res://scripts/models/tests/carry_test.gd tools/sd_test.sh (a real small window).
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

var checks := 0
var failures: Array = []
var screen: Node
var game: Node
var states: Dictionary
var FI: GDScript
var A: GDScript
var att: Node
var def: Node
var face := 1
var traces := {}          # "<thrower>_<face>" -> per-tick rows, to compare across slots and facings

# startup, active, recovery, raw dmg, release hitstop, shake
const SPEC := {
	"hina": [7, 3, 28, 70.0, 10, 7.0],
	"hoshino": [8, 3, 30, 80.0, 6, 6.0],
}
const FIT_MEAN := 25.0     # px, over every carried tick
const FIT_STEADY := 16.0   # px, every carried tick after the first three pull-in ticks
const PULL_IN := 3
const SPIN_LEAN := 35.0    # deg, how far from a whole turn the roll may be when the foe touches down

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("CARRY_CHECK FAIL ", label)
		failures.append(label)

func _run() -> void:
	create_timer(420.0).timeout.connect(func() -> void:
		print("CARRY_TEST FAIL watchdog timeout")
		quit(3))
	await process_frame
	FI = load("res://scripts/fight/fight_input.gd")
	A = load("res://scripts/fight/arena.gd")
	game = root.get_node("Game")
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	await _boot(10004, 10005)
	_audit_selftest()
	for who in [screen.f1, screen.f2]:
		_as(who)
		_data()
		if not _has_carry():
			continue
		for f in [1, -1]:
			face = f
			_grab()
			_path()
			_release()
			_recoil_and_landing()
			_view()
			_fit()
		face = 1
		_whiff()
		_untouchable()
		_crossup()
		_trade()
		_juggle()
		_aborts()
		_kill()
		_banner()
		_walls()
		_sounds()
		_freeze()
	_both_orders()
	await _boot(10005, 10004)
	_swapped_slots()
	print("CARRY_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _boot(p1: int, p2: int) -> void:
	game.session.begin("training")
	game.session.players[0]["fighter"] = p1
	game.session.players[1]["fighter"] = p2
	await game.go("fight", {}, "cut")
	screen = game.stack.back()
	screen.set_physics_process(false)
	screen.phase = "fight"
	states = screen.f1.get_script().S

# helpers
func _as(who: Node) -> void:
	att = who
	def = who.foe

func _name() -> String:
	return String(att.data["key"])

func _tag() -> String:
	return "%s f%+d" % [_name(), face]

func _has_carry() -> bool:
	var ok: bool = att.moves.has("throw") and not att.moves["throw"].get("carry", {}).is_empty()
	check(ok, _name() + " throw: has a carry dict")
	return ok

func _carry() -> Dictionary:
	return att.moves["throw"]["carry"]

func _hit() -> Dictionary:
	return att.moves["throw"]["hit"]

func _played(name: String) -> int:
	return int(root.get_node("Sfx").played.get(name, 0))

## The thrower stands 150 px from the middle, facing `face`; the foe `dist` legacy px in front of it.
func _place(dist := 110.0) -> void:
	att.reset_round(-150.0 * float(face), face)
	def.reset_round(att.position.x + float(face) * (dist + att.spacing_extra()), -face)
	def.frame = att.frame
	screen.phase = "fight"
	screen.slowmo = 0
	for f in [att, def]:
		f._set_state(states.IDLE)
		f.input = FI.new()
		f.hitstop = 0
		f.invuln = 0
		f.meter = 0.0
		f.guard_all = false

func _step() -> void:
	screen._tick_fight(false)

## Starts the throw and steps to the connect. Returns the ticks it took, -1 when nothing was grabbed.
func _to_grab(dist := 110.0) -> int:
	_place(dist)
	att._start_move("throw")
	for i in 30:
		_step()
		if def.carrier != null:
			return i + 1
	return -1

## Steps until the thrower's move frame reaches `mf` (hitstop ticks do not count), the foe still held when it can be.
func _to_mf(mf: int) -> void:
	for i in 80:
		if att.mf >= mf and att.hitstop == 0:
			return
		_step()

func _expected(h: Dictionary, is_projectile := false) -> float:
	return float(h["dmg"]) * att.hit_mult(is_projectile) * float(def.stats["taken"])

## The path through the keys, from `catch` (the foe's offset at the grab) at the move's startup: [x, y, roll] at move frame `mf`.
func _at(c: Dictionary, catch: Vector2, mf: int) -> Array:
	var p0 := [float(att.moves["throw"]["startup"]), catch.x, catch.y, 0.0]
	for k in c["path"]:
		var p1 := [float(k[0]), float(k[1]), float(k[2]), float(k[3])]
		if float(mf) <= p1[0]:
			var t: float = (float(mf) - float(p0[0])) / maxf(float(p1[0]) - float(p0[0]), 0.001)
			return [lerpf(p0[1], p1[1], t), lerpf(p0[2], p1[2], t), lerpf(p0[3], p1[3], t)]
		p0 = p1
	return [p0[1], p0[2], p0[3]]

func _row() -> Array:
	var s := float(face)
	return [att.state, att.mf, att.hitstop, snappedf(att.position.x * s, 0.0001), snappedf(att.position.y, 0.0001),
		def.state, def.hitstop, snappedf(def.position.x * s, 0.0001), snappedf(def.position.y, 0.0001),
		snappedf(def.carry_roll * s, 0.0001), snappedf(def.vel.x * s, 0.0001), snappedf(def.vel.y, 0.0001),
		snappedf(def.hp, 0.0001), snappedf(att.meter, 0.0001), def.carry_t, def.carry_anim, def.carrier != null, att.carrying != null]

## A whole throw from the placement to both fighters idle again: one row per tick and the summary numbers.
func _trace() -> Dictionary:
	_place()
	att._start_move("throw")
	var rows: Array = []
	var m := {"grab": -1, "release": -1, "down": -1, "att_idle": -1, "def_idle": -1, "land_x": 0.0, "land_roll": 0.0, "recoil": 0.0, "x0": att.position.x}
	var was_carried := false
	var last_air_roll := 0.0
	for i in 260:
		_step()
		rows.append(_row())
		if def.carrier != null and m["grab"] < 0:
			m["grab"] = i
		if was_carried and def.carrier == null and m["release"] < 0:
			m["release"] = i
		was_carried = def.carrier != null
		if def.state == states.AIRHIT:
			last_air_roll = def.carry_roll * float(face)
		if def.state == states.DOWN and m["down"] < 0:
			m["down"] = i
			m["land_x"] = (def.position.x - att.position.x) * float(face)
			m["land_roll"] = last_air_roll
		if m["grab"] >= 0 and att.state == states.IDLE and m["att_idle"] < 0:
			m["att_idle"] = i
		if m["down"] >= 0 and def.state == states.IDLE and m["def_idle"] < 0:
			m["def_idle"] = i
		if m["att_idle"] >= 0 and m["def_idle"] >= 0:
			break
	m["recoil"] = absf(att.position.x - m["x0"])
	return {"rows": rows, "m": m}

# the audit
## What a throw's carry dict must satisfy; the problems, empty when it is sound. `foe_anims` are the anims of the fighter it holds.
func _audit(m: Dictionary, foe_anims: Array) -> Array:
	var bad: Array = []
	var c: Dictionary = m.get("carry", {})
	if c.is_empty():
		return ["no carry dict"]
	var path: Array = c.get("path", [])
	if path.is_empty():
		return ["empty path"]
	var last := -1
	for k in path:
		if k.size() != 4:
			bad.append("a key is not [mf, x, y, roll]")
			continue
		if int(k[0]) <= last:
			bad.append("keys not ascending in mf")
		last = int(k[0])
		if float(k[2]) > 0.0:
			bad.append("a key below the floor")
		if absf(float(k[1])) > 160.0:
			bad.append("a key farther than 160 px")
	if int(path[0][0]) <= int(m["startup"]):
		bad.append("first key not after startup")
	var rel := int(c.get("release", -1))
	if rel <= int(path[0][0]) or rel >= int(m["frames"]) - 1:
		bad.append("release outside the first key and the move's end")
	if rel != int(path[path.size() - 1][0]):
		bad.append("the last key is not the release")
	if int(c.get("grab_stop", -1)) < 0:
		bad.append("negative grab stop")
	if float(c.get("pivot", 0.0)) <= 0.0:
		bad.append("no pivot")
	if not String(c.get("anim", "")) in foe_anims:
		bad.append("anim missing from the foe's sd.json")
	if not m.get("hit", {}).get("throw", false):
		bad.append("the move's hit is not a throw")
	return bad

func _audit_selftest() -> void:
	var good := {"startup": 7, "frames": 38, "hit": {"throw": true}, "carry": {"anim": "carried", "pivot": 76.0, "grab_stop": 4, "release": 22, "spin": 12.0, "path": [[10, 65, 0, 0], [22, 56, -34, -8]]}}
	check(_audit(good, ["carried"]).is_empty(), "audit: a sound dict passes")
	var cases := {
		"no carry dict": func(m: Dictionary) -> void: m.erase("carry"),
		"keys not ascending in mf": func(m: Dictionary) -> void: m["carry"]["path"][1][0] = 10,
		"first key not after startup": func(m: Dictionary) -> void: m["carry"]["path"][0][0] = 7,
		"a key below the floor": func(m: Dictionary) -> void: m["carry"]["path"][1][2] = 4,
		"a key farther than 160 px": func(m: Dictionary) -> void: m["carry"]["path"][1][1] = 161,
		"release outside the first key and the move's end": func(m: Dictionary) -> void: m["carry"]["release"] = 37,
		"the last key is not the release": func(m: Dictionary) -> void: m["carry"]["release"] = 20,
		"negative grab stop": func(m: Dictionary) -> void: m["carry"]["grab_stop"] = -1,
		"anim missing from the foe's sd.json": func(m: Dictionary) -> void: m["carry"]["anim"] = "nope",
		"the move's hit is not a throw": func(m: Dictionary) -> void: m["hit"]["throw"] = false,
	}
	for name in cases:
		var m: Dictionary = good.duplicate(true)
		(cases[name] as Callable).call(m)
		check(name in _audit(m, ["carried"]), "audit: flags '%s'" % name)

# data
func _data() -> void:
	var who := _name()
	var s: Array = SPEC[who]
	var m: Dictionary = att.moves["throw"]
	check(int(m["startup"]) == s[0] and int(m["active"]) == s[1] and int(m["recovery"]) == s[2], who + " throw: frames %d/%d/%d" % [s[0], s[1], s[2]])
	if not m.has("carry"):
		return
	var c: Dictionary = m["carry"]
	var h: Dictionary = m["hit"]
	var foe_anims: Array = def.view.sd_actor.cfg["anims"].keys()
	var own_anims: Array = att.view.sd_actor.cfg["anims"].keys()
	check(_audit(m, foe_anims).is_empty(), who + " throw: the carry dict is sound for its foe " + str(_audit(m, foe_anims)))
	check(_audit(m, own_anims).is_empty(), who + " throw: the carry dict is sound when held by its own kind " + str(_audit(m, own_anims)))
	check(bool(c["front"]) == (String(att.data["key"]) != "hoshino"), who + " throw: the held foe is drawn in front, except in Hoshino's hoist, where Hina would hide her")
	check(is_equal_approx(float(h["dmg"]), float(s[3]) * float(att.stats["dmg"])), who + " throw: raw damage %.0f through dm" % s[3])
	check(int(h["hitstop"]) == s[4] and is_equal_approx(float(h["shake"]), float(s[5])), who + " throw: release hitstop %d and shake %.0f" % [s[4], s[5]])
	check(bool(h["kd"]) and String(h["sfx"]) == "slam" and String(h["spark"]) == "heavy", who + " throw: a knockdown that plays slam")
	check(float(h["launch"].x) > 0.0, who + " throw: the release launches away from the thrower")
	check(is_equal_approx(float(h.get("snap", 0.0)), 80.0), who + " throw: the snap stays as the fallback")
	check(float(c.get("spin", 0.0)) > 0.0, who + " throw: the tumble spins")
	check(String(m.get("source", "")).contains("adaptation"), who + " throw: the source says adaptation")
	check(m["cancel"].is_empty() and not m.has("shots") and m["spawns"].is_empty(), who + " throw: no cancels, shots or spawns")
	var sfx_names := []
	for e in m.get("sfx", []):
		sfx_names.append(String(e["name"]))
		check(int(e["frame"]) > int(m["startup"]) and int(e["frame"]) <= int(c["release"]), who + " throw: swing at frame %d is inside the carry" % int(e["frame"]))
	check(sfx_names.has("swing"), who + " throw: swings during the hoist")

# the grab
func _grab() -> void:
	var t := _tag()
	var hp := 0.0
	_place()
	hp = float(def.hp)
	var n := _played("grab")
	var ticks := _to_grab_from_placed()
	check(ticks == int(att.moves["throw"]["startup"]) + 1, t + " grab: lands on the first active frame (tick %d)" % ticks)
	if ticks < 0:
		return
	var c := _carry()
	check(def.carrier == att and att.carrying == def, t + " grab: the two are linked")
	check(def.state == states.AIRHIT and def.move.is_empty() and def.vel == Vector2.ZERO, t + " grab: the foe is held in the airhit pose with no move")
	check(is_equal_approx(float(def.hp), hp) and def.combo_hits == 0, t + " grab: no damage yet")
	check(att.hitstop == int(c["grab_stop"]) and def.hitstop == 0, t + " grab: the thrower holds %d ticks, the foe none" % int(c["grab_stop"]))
	check(att.move_hit and not att.move_connected, t + " grab: the move is spent but counts as connected only once the hit lands, so no kit chains out of the hold")
	check(def.facing == -att.facing, t + " grab: the foe faces the thrower")
	check(def.carry_anim == String(c["anim"]) and def.carry_roll == 0.0 and def.carry_t == 0, t + " grab: the foe shows the carried anim from its first tick")
	check(is_equal_approx(def.carry_pivot.y, -float(c["pivot"])), t + " grab: the roll pivots about the pelvis")
	check(def.carry_front == bool(c["front"]), t + " grab: the foe takes the move's z-order flag")
	check(_played("grab") == n + 1, t + " grab: plays grab once")
	var x0: float = att.position.x
	for i in int(c["grab_stop"]) + 3:
		_step()
	check(is_equal_approx(att.position.x, x0), t + " grab: the thrower does not move")

func _to_grab_from_placed() -> int:
	att._start_move("throw")
	for i in 30:
		_step()
		if def.carrier != null:
			return i + 1
	return -1

# the path
func _path() -> void:
	var t := _tag()
	_to_grab()
	var c := _carry()
	var catch := Vector2((def.position.x - att.position.x) * float(face), def.position.y - A.GROUND)
	var worst := 0.0
	var worst_roll := 0.0
	var seen := 0
	var key_hits := {}
	var prev_mf := int(att.mf)
	var moved := 0
	while def.carrier != null and seen < 80:
		var before: Vector2 = def.position
		_step()
		seen += 1
		var mf := int(att.mf)
		if mf == prev_mf:
			check(def.position == before, t + " path: the foe stands still while the thrower holds (mf %d)" % mf)
			continue
		prev_mf = mf
		moved += 1
		var want := _at(c, catch, mf)
		var wx := clampf(att.position.x + float(face) * float(want[0]), -A.HALF_W, A.HALF_W)
		var wy := minf(A.GROUND + float(want[1]), A.GROUND)
		worst = maxf(worst, maxf(absf(def.position.x - wx), absf(def.position.y - wy)))
		worst_roll = maxf(worst_roll, absf(def.carry_roll - float(want[2]) * float(face)))
		for k in c["path"]:
			if int(k[0]) == mf:
				key_hits[mf] = true
		if def.carrier != null:
			check(def.state == states.AIRHIT and def.carry_t == moved, t + " path: still held and counting (carry_t %d, moved %d)" % [def.carry_t, moved])
	check(worst < 0.001 and worst_roll < 0.001, t + " path: the foe's feet and roll follow the keys on every tick (off by %.4f px, %.4f deg)" % [worst, worst_roll])
	check(key_hits.size() == c["path"].size(), t + " path: every key frame was visited (%d of %d)" % [key_hits.size(), c["path"].size()])
	check(moved == int(c["release"]) - int(att.moves["throw"]["startup"]), t + " path: one step per move frame from startup to the release (%d)" % moved)

# the release
func _release() -> void:
	var t := _tag()
	_place()
	var hp := float(def.hp)
	var hits0: int = att.stat_hits
	var throws := _played("throw")
	var grabs := _played("grab")
	var slams := _played("slam")
	var techs := _played("tech")
	att._start_move("throw")
	var rel := int(_carry()["release"])
	var released_tick := -1
	var hp_before_release := hp
	for i in 80:
		_step()
		if def.carrier != null:
			hp_before_release = float(def.hp)
		elif released_tick < 0 and def.carry_anim != "":
			released_tick = i
			break
	check(released_tick >= 0, t + " release: the foe is let go")
	check(is_equal_approx(hp_before_release, hp), t + " release: no damage while held")
	check(att.mf == rel and att.carrying == null and def.carrier == null, t + " release: on the move frame %d with both links cleared" % rel)
	var h := _hit()
	var raw_exp := _expected(h)
	check(is_equal_approx(hp - float(def.hp), raw_exp), t + " release: damage is dmg x dm x taken, once (%.2f of %.2f)" % [hp - float(def.hp), raw_exp])
	var bonus := (hp - float(def.hp)) / (float(h["dmg"]) * float(def.stats["taken"]))
	if _name() == "hina":
		check(is_equal_approx(bonus, 1.05), t + " release: Out-and-Out adds 5 percent against the lifted foe (x%.3f)" % bonus)
	else:
		check(is_equal_approx(bonus, 1.0), t + " release: Hoshino's throw has no bonus (x%.3f)" % bonus)
	check(def.combo_hits == 1 and att.stat_hits == hits0 + 1 and att.move_connected, t + " release: one hit, and the move counts as connected")
	check(def.state == states.AIRHIT and is_equal_approx(def.vel.x, float(face) * float(h["launch"].x)), t + " release: the foe leaves with the kit's launch")
	check(att.hitstop == int(h["hitstop"]) and def.hitstop == int(h["hitstop"]), t + " release: both fighters hold %d ticks (thrower %d, foe %d)" % [int(h["hitstop"]), att.hitstop, def.hitstop])
	check(is_equal_approx(att.meter, float(h["meter"]) * A.METER_PACE), t + " release: the thrower gains the throw's meter, paced")
	check(_played("throw") == throws + 1 and _played("grab") == grabs + 1 and _played("slam") == slams + 1 and _played("tech") == techs, t + " release: throw, grab and slam once each, no tech")
	check(is_equal_approx(def.carry_spin, float(_carry()["spin"]) * float(face)), t + " release: the tumble starts spinning")
	for i in 120:
		_step()
	check(_played("slam") == slams + 1, t + " release: slam is not played again")

# recoil, landing, advantage
func _recoil_and_landing() -> void:
	var t := _tag()
	var r := _trace()
	var m: Dictionary = r["m"]
	traces[t] = r["rows"]
	check(m["down"] > 0 and m["def_idle"] > 0 and m["att_idle"] > 0, t + " landing: the foe lands and both get up (down %d, foe idle %d, thrower idle %d)" % [m["down"], m["def_idle"], m["att_idle"]])
	check(float(m["recoil"]) < 0.01, t + " landing: the thrower is not dragged (%.3f px)" % float(m["recoil"]))
	var adv: int = int(m["def_idle"]) - int(m["att_idle"])
	print("CARRY_INFO ", t, " grab tick ", m["grab"], " release tick ", m["release"], " down tick ", m["down"], " lands ", snappedf(float(m["land_x"]), 0.1), " px, roll at touchdown ", snappedf(float(m["land_roll"]), 0.1), ", thrower idle ", m["att_idle"], ", foe idle ", m["def_idle"], ", advantage ", adv, ", recoil ", snappedf(float(m["recoil"]), 0.01))
	if _name() == "hina":
		check(float(m["land_x"]) >= 100.0 and float(m["land_x"]) <= 160.0, t + " landing: Hina's foe lands in front of her (%.0f px)" % float(m["land_x"]))
	else:
		check(float(m["land_x"]) >= 170.0 and float(m["land_x"]) <= 260.0, t + " landing: Hoshino's foe is thrown clear (%.0f px)" % float(m["land_x"]))
	check(adv >= 25 and adv <= 60, t + " landing: the thrower recovers well before the foe (+%d ticks)" % adv)
	var turn := fposmod(float(m["land_roll"]) + 180.0, 360.0) - 180.0
	check(absf(turn) <= SPIN_LEAN, t + " landing: the roll at touchdown is near a whole turn (%.1f deg, %.1f off)" % [float(m["land_roll"]), turn])

# the view
func _view() -> void:
	var t := _tag()
	_to_grab()
	var c := _carry()
	var v: Node = def.view
	v.step(1.0 / 60.0)
	att.view.step(1.0 / 60.0)
	var held_rot: float = v.rig.rotation
	check(v.rig.z_index == (2 if bool(c["front"]) else 0) and att.view.rig.z_index == 0, t + " view: the held foe is drawn in front of the thrower when the move says front")
	_to_mf(int(c["release"]) - 1)
	v.step(1.0 / 60.0)
	att.view.step(1.0 / 60.0)
	check(is_equal_approx(v.rig.rotation, deg_to_rad(def.carry_roll)), t + " view: the rig rolls by carry_roll while held (%.1f deg)" % def.carry_roll)
	var pv: Vector2 = def.carry_pivot
	check((v.rig.position - (pv - pv.rotated(v.rig.rotation))).length() < 0.01, t + " view: the roll turns about the pelvis")
	check(def.view.sd_actor.anim_name == String(c["anim"]), t + " view: the foe plays the carried anim (%s)" % def.view.sd_actor.anim_name)
	check(att.view.sd_actor.anim_name == "moves/throw", t + " view: the thrower plays her throw (%s)" % att.view.sd_actor.anim_name)
	for i in 4:
		_step()
	check(def.carrier == null and def.carry_anim != "", t + " view: the tumble goes on after the release")
	v.step(1.0 / 60.0)
	check(is_equal_approx(v.rig.rotation, deg_to_rad(def.carry_roll)) and v.rig.z_index == (2 if bool(c["front"]) else 0), t + " view: the tumbling foe keeps its roll and its place")
	for i in 80:
		_step()
		if def.state == states.DOWN:
			break
	v.step(1.0 / 60.0)
	check(def.state == states.DOWN and def.carry_anim == "" and def.carry_roll == 0.0 and def.carry_spin == 0.0, t + " view: touchdown clears the roll and the anim")
	check(is_zero_approx(v.rig.rotation) and v.rig.z_index == 0 and v.rig.position.length() < 6.0, t + " view: the lying foe is unrotated and back in the normal z order")
	check(held_rot == 0.0, t + " view: the rig starts unrolled at the grab")
	# a puppet foe's roll spring: a tumble that ends on a whole turn drops the turns, so it lies down the short way round
	var r: int = v.ROT
	var val0: float = v._val[r]
	var vel0: float = v._vel[r]
	v._val[r] = 6.3
	v._vel[r] = 20.0
	v._on_state(states.AIRHIT, states.DOWN)
	check(absf(float(v._val[r]) + 1.52) <= PI and is_equal_approx(float(v._vel[r]), -2.5), t + " view: a puppet's tumble lands on the short way round, with only the knockdown kick left (%.2f rad)" % float(v._val[r]))
	v._val[r] = -0.65
	v._vel[r] = 1.5
	v._on_state(states.AIRHIT, states.DOWN)
	check(is_equal_approx(float(v._val[r]), -0.65) and is_equal_approx(float(v._vel[r]), -1.0), t + " view: an ordinary fall keeps its spring")
	v._val[r] = val0
	v._vel[r] = vel0

# the hand fit
func _px(actor: Node, bone: String) -> Vector2:
	var sk: Skeleton3D = actor.grip_skeleton
	var i := sk.find_bone(bone)
	var p: Vector3 = sk.global_transform * sk.get_bone_global_pose(i).origin
	return (actor.camera.unproject_position(p) + actor.body.offset) * actor.body.scale

## Gap between the thrower's free hand and the foe's chest (after the roll) on every carried tick, from the real sim and both
## actors. The first PULL_IN ticks after the grab are exempt from the steady gap: the foe is still being pulled in.
func _gaps() -> Dictionary:
	_to_grab()
	var aa: Node = att.view.sd_actor
	var da: Node = def.view.sd_actor
	var gaps: Array = []
	var prev_mf := int(att.mf)
	var carried_ticks := 0
	while carried_ticks < 80:
		var was := def.carrier != null
		_step()
		if not was:
			break
		if int(att.mf) == prev_mf:
			continue
		prev_mf = int(att.mf)
		carried_ticks += 1
		aa.sync(att)
		da.sync(def)
		var hand: Vector2 = att.position + _px(aa, "Bip001 L Hand")
		var pv: Vector2 = def.carry_pivot
		var chest: Vector2 = def.position + pv + (_px(da, "Bip001 Spine1") - pv).rotated(deg_to_rad(def.carry_roll))
		gaps.append(hand.distance_to(chest))
	var mean := 0.0
	var steady := 0.0
	for i in gaps.size():
		mean += float(gaps[i]) / float(gaps.size())
		if i >= PULL_IN:
			steady = maxf(steady, float(gaps[i]))
	return {"gaps": gaps, "mean": mean, "steady": steady}

func _fit() -> void:
	var t := _tag()
	var g := _gaps()
	var gaps: Array = g["gaps"]
	var line := ""
	for x in gaps:
		line += " %.0f" % float(x)
	print("CARRY_FIT ", t, " holds ", def.data["key"], " mean ", snappedf(float(g["mean"]), 0.1), " steady ", snappedf(float(g["steady"]), 0.1), " gaps", line)
	check(gaps.size() > PULL_IN + 4, t + " fit: enough carried ticks to judge (%d)" % gaps.size())
	check(float(g["mean"]) <= FIT_MEAN, t + " fit: the foe's chest rides the free hand, mean %.1f px of %.0f" % [float(g["mean"]), FIT_MEAN])
	check(float(g["steady"]) <= FIT_STEADY, t + " fit: and stays on it after the pull-in, steady %.1f px of %.0f" % [float(g["steady"]), FIT_STEADY])

# a whiff
func _whiff() -> void:
	var who := _name()
	_place(300.0)
	att._start_move("throw")
	var ticks := 0
	while att.state == states.ATTACK and ticks < 80:
		_step()
		ticks += 1
		check(def.carrier == null and att.carrying == null, who + " whiff: nothing is carried")
	check(ticks == int(att.moves["throw"]["frames"]), who + " whiff: the whole move runs (%d of %d ticks)" % [ticks, int(att.moves["throw"]["frames"])])
	check(is_equal_approx(def.hp, def.max_hp) and def.carry_anim == "", who + " whiff: nothing happens to the foe")

# a held foe cannot be touched
func _untouchable() -> void:
	var who := _name()
	_to_grab()
	_to_mf(int(att.moves["throw"]["startup"]) + 4)
	var hp := float(def.hp)
	var bullet: Dictionary = def.moves["close_L"]["hit"]
	check(String(def.receive_hit(att, bullet, att.position, true)) == "miss" and is_equal_approx(hp, float(def.hp)), who + " held: a projectile misses")
	check(String(def.receive_hit(att, bullet, att.position, false)) == "miss" and is_equal_approx(hp, float(def.hp)), who + " held: a melee hit misses")
	check(String(def.receive_hit(att, _hit(), att.position, false)) == "miss" and is_equal_approx(hp, float(def.hp)), who + " held: a second throw misses")
	check(def.carrier == att and att.carrying == def and def.combo_hits == 0, who + " held: the hold is not disturbed")
	def.shield_frames = 30
	check(String(def.receive_hit(att, bullet, att.position, false)) == "miss" and def.shield_frames == 30, who + " held: an assist shield is not spent on a miss")
	def.shield_frames = 0
	# an assist shield soaks the throw at the connect: no carry at all
	_place()
	def.shield_frames = 30
	att._start_move("throw")
	for i in 20:
		_step()
	check(def.carrier == null and att.carrying == null and def.shield_frames == 0 and is_equal_approx(def.hp, def.max_hp), who + " shield: an assist shield absorbs the throw and nothing is carried")
	# the foe's own tick does nothing while held, whatever it presses
	_to_grab()
	def.input = FI.from_held(def.input, 1, 0, ["light", "heavy", "dash"])
	var p: Vector2 = def.position
	def.tick()
	check(def.position == p and def.state == states.AIRHIT and not def.buffered("light"), who + " held: the foe's own tick moves nothing and buffers nothing")
	# push-apart leaves both where they are while one holds the other
	var ax: float = att.position.x
	for i in 8:
		_step()
	check(is_equal_approx(att.position.x, ax), who + " held: push-apart does not shove the thrower (moved %.3f px)" % (att.position.x - ax))

# aborts
func _mid_carry() -> void:
	_to_grab()
	var c := _carry()
	_to_mf((int(c["path"][0][0]) + int(c["release"])) / 2)
	check(def.carrier == att, _name() + " abort: held at mf %d" % att.mf)

func _released_once(label: String, hp: float, projectile: bool) -> void:
	check(def.carrier == null and att.carrying == null, label + ": both links are cleared")
	check(def.state == states.AIRHIT and def.combo_hits == 1, label + ": the foe is released in the air with one hit")
	var want := _expected(_hit(), projectile)
	check(is_equal_approx(hp - float(def.hp), want), label + ": the throw's hit lands once (%.2f of %.2f)" % [hp - float(def.hp), want])
	check(def.carry_anim != "" and is_equal_approx(def.carry_spin, float(_carry()["spin"]) * float(face)), label + ": and it tumbles")
	for i in 3:
		_step()
	check(is_equal_approx(hp - float(def.hp), want) and def.combo_hits == 1, label + ": nothing lands twice")

func _aborts() -> void:
	var who := _name()
	var hit_in: Dictionary = def.moves["close_L"]["hit"]
	_mid_carry()
	var hp := float(def.hp)
	var thrower_hp := float(att.hp)
	att.receive_hit(def, hit_in, def.position, true)
	check(att.state != states.ATTACK and float(att.hp) < thrower_hp, who + " abort by a hit: the thrower is hit")
	_released_once(who + " abort by a hit", hp, true)
	_mid_carry()
	hp = float(def.hp)
	att.receive_hit(def, hit_in, def.position, false)
	_released_once(who + " abort by a melee hit", hp, true)
	_mid_carry()
	hp = float(def.hp)
	att._start_move("5L")
	check(att.move_key == "5L", who + " abort by a kit move: the new move runs")
	_released_once(who + " abort by a kit move", hp, true)
	_mid_carry()
	hp = float(def.hp)
	att._start_dash(false)
	_released_once(who + " abort by a dash", hp, true)
	_mid_carry()
	hp = float(def.hp)
	att._end_move()
	_released_once(who + " abort by the move ending", hp, true)
	_mid_carry()
	hp = float(def.hp)
	att._ko()
	check(att.state == states.KO, who + " abort by a KO: the thrower is down")
	_released_once(who + " abort by a KO", hp, true)
	screen.phase = "fight"
	screen.slowmo = 0
	_mid_carry()
	hp = float(def.hp)
	att.start_win()
	_released_once(who + " abort by a win", hp, true)
	# the foe is the one who goes down or wins
	_mid_carry()
	var carried_hp := float(def.hp)
	def._ko()
	check(def.carrier == null and att.carrying == null and def.state == states.KO and def.carry_anim == "", who + " abort by the foe's KO: the links and the view fields are cleared")
	check(carried_hp > 0.0 and is_zero_approx(def.hp), who + " abort by the foe's KO: hp is zero")
	screen.phase = "fight"
	screen.slowmo = 0
	# a hit on the thrower on the release tick lands after the release: the foe was let go first
	_to_grab()
	_to_mf(int(_carry()["release"]) - 1)
	hp = float(def.hp)
	_step()
	check(def.carrier == null, who + " abort on the release tick: the foe was released by the tick")
	att.receive_hit(def, hit_in, def.position, true)
	check(def.combo_hits == 1 and is_equal_approx(hp - float(def.hp), _expected(_hit())), who + " abort on the release tick: the throw lands once (%.2f)" % (hp - float(def.hp)))
	# a round start clears everything and applies nothing
	_mid_carry()
	att.reset_round(-150.0, 1)
	def.reset_round(150.0, -1)
	check(def.carrier == null and att.carrying == null and def.carry_anim == "" and def.carry_roll == 0.0 and def.carry_spin == 0.0 and def.carry_t == 0, who + " round start: no link and no view field is left")
	check(is_equal_approx(def.hp, def.max_hp), who + " round start: nobody is hurt")

# a foe caught in a move of its own, facing away
func _crossup() -> void:
	var who := _name()
	_place()
	def.state = states.ATTACK
	def.move = {"cutin": false, "super": false, "air": false, "cancel": [], "hit": {}, "spawns": [], "frames": 30, "startup": 5, "active": 5}
	def.facing = att.facing
	att._start_move("throw")
	check(String(def.receive_hit(att, _hit(), att.position, false)) == "hit" and def.carrier == att, who + " cross-up: a foe in a move of its own is grabbed")
	check(def.move.is_empty() and def.state == states.AIRHIT, who + " cross-up: its move is dropped")
	check(def.facing == -att.facing, who + " cross-up: and it faces the thrower, so the pose and the landing read the right way round")

# the thrower is struck on the connect tick
func _trade() -> void:
	var who := _name()
	for strike_first in [true, false]:
		_place(80.0)
		att._start_move("throw")
		def._start_move("close_L")
		for i in 40:
			if att.mf >= int(att.moves["throw"]["startup"]) and def.mf >= int(def.moves["close_L"]["startup"]):
				break
			att.tick()
			def.tick()
		var t_hp := float(att.hp)
		var d_hp := float(def.hp)
		var strike: Dictionary = def.moves["close_L"]["hit"]
		if strike_first:
			att.receive_hit(def, strike, def.position, false)
			def.receive_hit(att, _hit(), att.position, false)
		else:
			def.receive_hit(att, _hit(), att.position, false)
			att.receive_hit(def, strike, def.position, false)
		check(float(att.hp) < t_hp and float(def.hp) < d_hp and def.state == states.AIRHIT and def.combo_hits == 1, who + " trade: both take their hit (strike first %s)" % str(strike_first))
		check(def.carrier == null and att.carrying == null, who + " trade: nobody is left holding (strike first %s)" % str(strike_first))
		for i in 60:
			_step()
		check(def.carrier == null and att.carrying == null and def.combo_hits <= 1, who + " trade: and nothing lands twice (strike first %s)" % str(strike_first))

# a hit on the tumbling foe
func _juggle() -> void:
	var who := _name()
	_to_grab()
	for i in 80:
		_step()
		if def.carrier == null:
			break
	for i in int(_hit()["hitstop"]) + 2:
		_step()
	check(def.carry_anim != "" and def.state == states.AIRHIT, who + " juggle: the foe is tumbling")
	def.receive_hit(att, att.moves["close_L"]["hit"], att.position, true)
	check(def.state == states.AIRHIT and def.carry_anim == "" and is_zero_approx(def.carry_roll) and is_zero_approx(def.carry_spin), who + " juggle: a hit on the tumbling foe ends the tumble")
	for i in 12:
		_step()
	check(def.carry_anim == "", who + " juggle: and it stays ended")

# a throw that kills
func _kill() -> void:
	var who := _name()
	_to_grab()
	def.hp = 40.0
	for i in 40:
		_step()
		if def.carrier == null:
			break
	check(is_equal_approx(def.hp, 0.0) and def.state == states.AIRHIT, who + " kill: hp is 0 at the release and the foe is still in the air")
	check(att.hp > 0.0 and def.carrier == null, who + " kill: released")
	var ko_tick := -1
	for i in 120:
		_step()
		if def.state == states.KO:
			ko_tick = i
			break
	check(ko_tick > 0, who + " kill: the foe lands and goes down for good (tick %d after the release)" % ko_tick)
	check(def.carry_anim == "" and def.carry_roll == 0.0, who + " kill: the view fields are cleared")
	screen.phase = "fight"
	screen.slowmo = 0

## TIME UP or the K.O. banner while the foe is held: the round is decided from the buzzer's snapshot, so the release lets the foe
## go and lands nothing, and the foe falls and lies down.
func _banner() -> void:
	var who := _name()
	for ph in ["ko", "round_end"]:
		_to_grab()
		var hp := float(def.hp)
		var dealt: float = att.stat_damage_dealt
		screen.phase = ph
		for i in 40:
			_step()
			if def.carrier == null:
				break
		check(def.carrier == null and att.carrying == null, who + " " + ph + " banner: the foe is let go at the release")
		check(is_equal_approx(float(def.hp), hp) and def.combo_hits == 0 and is_equal_approx(att.stat_damage_dealt, dealt) and is_zero_approx(att.meter), who + " " + ph + " banner: no damage, combo or meter lands (hp %.1f of %.1f)" % [def.hp, hp])
		for i in 120:
			_step()
			if def.state == states.DOWN:
				break
		check(def.state == states.DOWN and def.carry_anim == "" and def.carry_roll == 0.0, who + " " + ph + " banner: the foe falls and lies down with its view fields cleared")
	screen.phase = "fight"
	screen.slowmo = 0

# walls
func _walls() -> void:
	var who := _name()
	for f in [1, -1]:
		face = f
		_to_grab()
		att.position.x = float(f) * (A.HALF_W - 20.0)
		var worst := 0.0
		for i in 80:
			_step()
			worst = maxf(worst, absf(def.position.x) - A.HALF_W)
			if def.state == states.DOWN:
				break
		check(worst <= 0.0, who + " wall f%+d: the foe never leaves the arena (%.1f px past)" % [f, worst])
		check(absf(att.position.x) <= A.HALF_W, who + " wall f%+d: nor does the thrower" % f)
	face = 1

# sounds
func _sounds() -> void:
	var who := _name()
	_place()
	var swings := _played("swing")
	var lands := _played("land")
	att._start_move("throw")
	for i in 200:
		_step()
		if att.state != states.ATTACK and def.state != states.DOWN and i > 60:
			break
	var want := 0
	for e in att.moves["throw"].get("sfx", []):
		if String(e["name"]) == "swing":
			want += 1
	check(_played("swing") == swings + want, who + " sounds: %d swing(s) during the carry (%d)" % [want, _played("swing") - swings])
	check(_played("land") == lands + 1, who + " sounds: the foe's landing plays land once")

# an EX freeze in the middle
func _freeze_run(frozen: bool) -> Array:
	_place()
	att._start_move("throw")
	var rows: Array = []
	var did := false
	for i in 90:
		if frozen and not did and att.mf >= int(_carry()["path"][0][0]) + 1 and def.carrier != null and att.hitstop == 0:
			did = true
			screen.time_stop = 8
			var before := _row()
			for j in 8:
				screen._sim_step()
			check(_row() == before, _name() + " freeze: nothing moves in a freeze (8 ticks)")
		screen._sim_step()
		rows.append(_row())
	if frozen:
		check(did, _name() + " freeze: the freeze was exercised during the hold")
	return rows

func _freeze() -> void:
	var plain := _freeze_run(false)
	var frozen := _freeze_run(true)
	check(plain == frozen, _name() + " freeze: the carry resumes tick for tick after a freeze")
	screen.time_stop = 0

# determinism, facings, both tick orders
func _both_orders() -> void:
	face = 1
	for who in [screen.f1, screen.f2]:
		_as(who)
		var a: Array = _trace()["rows"]
		var b: Array = _trace()["rows"]
		check(a == b, _name() + " determinism: two runs give the same state on every tick (%d rows)" % a.size())
		face = -1
		var m: Array = _trace()["rows"]
		face = 1
		check(a == m, _name() + " mirror: facing left gives the mirrored numbers on every tick")
		check(traces.has("%s f+1" % _name()) and traces["%s f+1" % _name()] == a, _name() + " determinism: the traced run matches")

func _swapped_slots() -> void:
	for who in [screen.f1, screen.f2]:
		_as(who)
		face = 1
		var swapped: Array = _trace()["rows"]
		var key := "%s f+1" % _name()
		check(traces.has(key) and traces[key] == swapped, _name() + " slots: the same throw in the other slot gives the same state on every tick")
