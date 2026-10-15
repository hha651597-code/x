extends SceneTree
## SD foot test. Drives the real sim (Fighter.tick with FightInput.from_held) and the real SdFighterActor.sync for every
## roster fighter with an sd.json, both facings, at normal speed and under a slow debuff (the walk also under a speed
## buff), and measures whether the feet stay planted. Body speeds are read from the sim, never from constants. The walk clip
## follows any sim speed (its clock is distance over stride), but the dash stride is fitted to the 1.3x stat, so a speed change
## can turn the dash checks red, which is the point. A dash slowed to about 0.55 to 0.8 may brush the floor with a foot
## (Hoshino, measured near-touch 4.5 to 5 px), so only 0.5 and 0.35 are held.
## Run with MAXLINES=120 TEST=res://scripts/models/tests/sd_foot_test.gd tools/sd_test.sh (a real small window).
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

## A foot is planted on a tick when its model y is within CONTACT model units (4 px) of the lowest foot of the whole run. Hoshino's
## stride moves about 10 percent with this threshold (0.02 to 0.05), so the stride in sd.json and this test use the same rule.
const CONTACT := 0.03
## Consecutive planted ticks of one foot make a stance; shorter touches are a foot passing the floor, not a step.
const MIN_STANCE_TICKS := 3
## A run with fewer stances proves nothing (Hoshino's run has a foot down only 10 to 19 ticks in 40), so it fails.
const MIN_STANCES := 2
## Mean ground slip of a planted foot, px per tick, over the stances of a run. The dash decays x0.95 a tick and the clip clock is
## capped at 1.6x, so its first ticks may skate a little.
const SKATE := 1.0
const DASH_SKATE := 2.0
## The furthest one stance may carry its foot over the ground, px.
const STANCE_PX := 25.0
## A hop's feet clear the floor by this many px (backdash, jump, air dash).
const AIR_PX := 6.0
## The last ticks of a jump are its landing: the feet reach for the floor while the body is still 16 px a tick above it (Hoshino's
## Move_Jump legs end in the landing pose, 5.7, -10.7 and -15.1 px over the line on her last three ticks). Reported, not checked.
const LANDING_TICKS := 3
## Ticks dropped at the start of a walk before measuring, and of a dash. The dash clock
## is capped at 1.6x playback while the body starts at 13 to 14 px a tick, so the first foot down skates a little; Hina facing left
## reads 3.3 mean (23.1 px) with only two ticks dropped, 1.8 with three.
const SKIP_TICKS := 4
const DASH_SKIP := 3
const WALK_TICKS := 200
const SLOW_WALK_TICKS := 260
const DASHES := 4
const SLOW := 0.5
const SLOWER := 0.35
const BUFF := 1.3
## Sim stats after Arena.MOVE_SCALE (1.3): the foot checks read speeds from the sim, so they cannot notice the scalar going missing.
const PINS := {
	"hina": {"walk": 4.42, "walk_back": 3.9, "dash": 13.0, "jump_dx": 7.15},
	"hoshino": {"walk": 4.693, "walk_back": 4.03, "dash": 14.3, "jump_dx": 7.8},
}

var failures: Array[String] = []
var checks := 0
var report: Array[String] = []
var FI: GDScript
var A: GDScript
var states: Dictionary
var game: Node
var screen: Node
var config: Script

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		if failures.size() < 60:
			print("SD_FOOT_CHECK FAIL ", label)
		failures.append(label)

func _run() -> void:
	create_timer(280.0).timeout.connect(func() -> void:
		print("SD_FOOT FAIL watchdog timeout")
		quit(3))
	await process_frame
	config = load("res://scripts/models/sd_config.gd")
	FI = load("res://scripts/fight/fight_input.gd")
	A = load("res://scripts/fight/arena.gd")
	game = root.get_node("Game")
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	var ids: Array = []
	for e in game.fighters:
		if not config.of(String(e.get("key", ""))).is_empty():
			ids.append(int(e["id"]))
	check(not ids.is_empty(), "the roster has fighters with an sd.json")
	var tested := {}
	for i in range(0, ids.size(), 2):
		game.session.begin("training")
		game.session.players[0]["fighter"] = ids[i]
		game.session.players[1]["fighter"] = ids[(i + 1) % ids.size()]
		await game.go("fight", {}, "cut")
		screen = game.stack.back()
		states = screen.f1.get_script().S
		screen.set_physics_process(false)
		screen.phase = "fight"
		for f in screen.fighters:
			f.set_process(false)
		for f in screen.fighters:
			var key := String(f.data["key"])
			if tested.has(key):
				continue
			tested[key] = true
			_fighter(f, config.of(key))
	for line in report:
		print("SD_FOOT ", line)
	print("SD_FOOT tested ", tested.keys())
	print("SD_FOOT ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	if game:
		root.get_node("Bgm").stop()
	await create_timer(0.3).timeout
	quit(0 if failures.is_empty() else 1)

func _fighter(f: Node, cfg: Dictionary) -> void:
	var key := String(f.data["key"])
	var a: Node = f.view.sd_actor
	a.blending = false
	for anim in ["walk", "walk_back", "dash"]:
		var s: Variant = cfg["anims"][anim].get("stride")
		check(s is Array and s.size() == 2 and float(s[0]) > 0.0 and float(s[1]) > 0.0, "%s: the %s anim carries a stride [left, right]" % [key, anim])
	if PINS.has(key):
		for stat in PINS[key]:
			check(absf(float(f.stats[stat]) - float(PINS[key][stat])) < 0.01, "%s: stat %s is %.3f after the move scale (sim has %.3f)" % [key, stat, PINS[key][stat], float(f.stats[stat])])
	for face in [1, -1]:
		for mode in ["normal", "slow", "slower"]:
			_walk(f, a, key, face, mode, "walk")
			_walk(f, a, key, face, mode, "walk_back")
			_dash(f, a, key, face, mode)
			_backdash(f, a, key, face, mode)
			_jump(f, a, key, face, mode, "jump_fwd")
			_jump(f, a, key, face, mode, "jump_back")
			if cfg["anims"].has("dash_air"):
				_air_dash(f, a, key, face, mode, "airdash")
				_air_dash(f, a, key, face, mode, "airdash_back")
		_walk(f, a, key, face, "buff", "walk")

# ── driving the sim ──────────────────────────────────────────────────────────

func _place(f: Node, a: Node, face: int, x: float, mode: String) -> void:
	var foe: Node = f.foe
	f.reset_round(x, face)
	foe.reset_round(float(face) * 700.0, -face)
	for who in [f, foe]:
		who._set_state(states.IDLE)
		who.input = FI.new()
		who.hitstop = 0
		who.invuln = 0
	f.facing = face
	if mode == "slow" or mode == "slower":
		f.slow_frames = 100000
		f.slow_mult = SLOW if mode == "slow" else SLOWER
	elif mode == "buff":
		f.kv["speed_mult"] = BUFF
	a.sync(f)

## One sim tick with the given input, then the actor's pose of that tick: [feet ground x, foot model y, foot px over the floor] per leg.
func _tick(f: Node, a: Node, x: int, y: int, btns: Array) -> Dictionary:
	f.input = FI.from_held(f.input, x, y, btns)
	f.tick()
	a.sync(f)
	var sk: Skeleton3D = a.grip_skeleton
	var ppu := absf((a.camera.unproject_position(Vector3(0, 1, 0)) - a.camera.unproject_position(Vector3.ZERO)).y * a.body.scale.y)
	var feet: Array = []
	for leg in a.legs:
		var w: Vector3 = sk.global_transform * sk.get_bone_global_pose(leg[2]).origin
		var screen_x: float = ((a.camera.unproject_position(w) + a.body.offset) * a.body.scale).x
		feet.append({"gx": f.position.x + screen_x, "y": w.y, "h": (A.GROUND - f.position.y) + (w.y - float(a.cfg["ankle"])) * ppu})
	return {"state": f.state, "sf": f.sf, "vx": f.vel.x, "x": f.position.x, "anim": a.anim_name, "kv_anim": String(f.kv.get("anim", "")), "feet": feet}

func _hold(f: Node, a: Node, x: int, y: int, btns: Array, n: int, into: Array) -> void:
	for i in n:
		into.append(_tick(f, a, x, y, btns))

# ── ground runs ──────────────────────────────────────────────────────────────

## Stances of the feet over segments (arrays of consecutive ticks): [{n, d}] with the ground distance d the foot covered while planted.
func _stances(segments: Array) -> Array:
	var low := INF
	for seg in segments:
		for t in seg:
			for ft in t["feet"]:
				low = minf(low, ft["y"])
	var out: Array = []
	for seg in segments:
		for leg in 2:
			var run: Array = []
			for t in seg + [null]:
				if t != null and t["feet"][leg]["y"] <= low + CONTACT:
					run.append(t["feet"][leg]["gx"])
					continue
				if run.size() >= MIN_STANCE_TICKS:
					out.append({"n": run.size(), "d": absf(run[-1] - run[0])})
				run = []
	return out

func _judge(tag: String, segments: Array, limit: float, flight_ok := false) -> void:
	var stances := _stances(segments)
	if flight_ok:
		# a slowed dash that never brings a foot within AIR_PX of the floor is a bound, whatever the stance finder makes of its apex
		var clear := INF
		for seg in segments:
			for t in seg:
				for ft in t["feet"]:
					clear = minf(clear, ft["h"])
		if clear >= AIR_PX or stances.is_empty():
			report.append("%s: bound, lowest foot %.1f px over the floor" % [tag, clear])
			check(clear >= AIR_PX, "%s: a slowed dash that plants no foot keeps both feet %.0f px up (lowest %.1f)" % [tag, AIR_PX, clear])
			return
	var slip := 0.0
	var worst := 0.0
	for s in stances:
		slip += s["d"] / float(s["n"] - 1) / float(stances.size())
		worst = maxf(worst, s["d"])
	var vx_first := 0.0
	var vx_last := 0.0
	if not segments.is_empty() and not segments[0].is_empty():
		vx_first = absf(segments[0][0]["vx"])
		vx_last = absf(segments[-1][-1]["vx"])
	report.append("%s: body %.2f..%.2f px/tick, slip %.2f px/tick, worst stance %.1f px, stances %d" % [tag, vx_first, vx_last, slip, worst, stances.size()])
	check(stances.size() >= MIN_STANCES, "%s: at least %d stances (got %d), so the run proves something" % [tag, MIN_STANCES, stances.size()])
	check(slip <= limit, "%s: mean slip %.2f px per tick, at most %.1f" % [tag, slip, limit])
	check(worst <= STANCE_PX, "%s: worst stance carries the foot %.1f px, at most %.0f" % [tag, worst, STANCE_PX])

func _walk(f: Node, a: Node, key: String, face: int, mode: String, anim: String) -> void:
	var n := SLOW_WALK_TICKS if mode.begins_with("slow") else WALK_TICKS
	var forward := anim == "walk"
	_place(f, a, face, -float(face) * 700.0 if forward else float(face) * 500.0, mode)
	var run: Array = []
	_hold(f, a, face if forward else -face, 0, [], n, run)
	var seg: Array = []
	for t in run.slice(SKIP_TICKS):
		if t["state"] == states.WALK and t["anim"] == anim:
			seg.append(t)
	check(seg.size() == run.size() - SKIP_TICKS, "%s %s f%+d %s: every tick plays %s (%d of %d)" % [key, anim, face, mode, anim, seg.size(), run.size() - SKIP_TICKS])
	_judge("%s %s f%+d %s" % [key, anim, face, mode], [seg], SKATE)

func _dash(f: Node, a: Node, key: String, face: int, mode: String) -> void:
	_place(f, a, face, -float(face) * 700.0, mode)
	var segments: Array = []
	for d in DASHES:
		var run: Array = []
		_hold(f, a, 0, 0, [], 3, [])
		_hold(f, a, face, 0, ["dash"], 1, run)
		_hold(f, a, 0, 0, [], 30, run)
		var seg: Array = []
		for t in run:
			if t["state"] == states.DASH:
				seg.append(t)
		segments.append(seg.slice(DASH_SKIP))
		_hold(f, a, 0, 0, [], 4, [])
	_judge("%s dash f%+d %s" % [key, face, mode], segments, DASH_SKATE, mode.begins_with("slow"))

func _backdash(f: Node, a: Node, key: String, face: int, mode: String) -> void:
	_place(f, a, face, float(face) * 300.0, mode)
	var run: Array = []
	_hold(f, a, 0, 0, [], 3, [])
	_hold(f, a, -face, 0, ["dash"], 1, run)
	_hold(f, a, 0, 0, [], 30, run)
	var low := INF
	var n := 0
	for t in run:
		if t["state"] != states.BACKDASH or t["sf"] < 1 or absf(t["vx"]) <= 1.0:
			continue
		n += 1
		for ft in t["feet"]:
			low = minf(low, ft["h"])
	report.append("%s backdash f%+d %s: lowest foot %.1f px over the floor on %d moving ticks" % [key, face, mode, low, n])
	check(n >= 10, "%s backdash f%+d %s: the run has moving backdash ticks (%d)" % [key, face, mode, n])
	check(low >= AIR_PX, "%s backdash f%+d %s: no foot within %.0f px of the floor while it moves (lowest %.1f)" % [key, face, mode, AIR_PX, low])

# ── air runs ─────────────────────────────────────────────────────────────────

func _jump(f: Node, a: Node, key: String, face: int, mode: String, sc: String) -> void:
	_place(f, a, face, -float(face) * 200.0, mode)
	var jx := face if sc == "jump_fwd" else -face
	var run: Array = []
	_hold(f, a, 0, 0, [], 2, [])
	_hold(f, a, jx, -1, [], 1, run)
	_hold(f, a, jx, 0, [], 60, run)
	var air: Array = []
	for t in run:
		if t["state"] == states.JUMP:
			air.append(t)
	var low := INF
	for t in air.slice(2, air.size() - LANDING_TICKS):
		for ft in t["feet"]:
			low = minf(low, ft["h"])
	var landing := 0.0
	var tail: Array = []
	for t in air.slice(maxi(air.size() - 8, 0)):
		tail.append(snappedf(minf(t["feet"][0]["h"], t["feet"][1]["h"]), 0.1))
	if not air.is_empty():
		landing = minf(air[-1]["feet"][0]["h"], air[-1]["feet"][1]["h"])
	report.append("%s %s f%+d %s: %d air ticks, travel %.0f px, lowest foot %.1f px over the floor, landing tick %.1f px, last 8 %s" % [key, sc, face, mode, air.size(), absf(air[-1]["x"] - air[0]["x"]) if not air.is_empty() else 0.0, low, landing, str(tail)])
	check(air.size() > 20, "%s %s f%+d %s: the jump has air ticks (%d)" % [key, sc, face, mode, air.size()])
	check(low >= AIR_PX, "%s %s f%+d %s: no foot within %.0f px of the floor in flight (lowest %.1f)" % [key, sc, face, mode, AIR_PX, low])

func _air_dash(f: Node, a: Node, key: String, face: int, mode: String, sc: String) -> void:
	_place(f, a, face, -float(face) * 400.0, mode)
	var ax := face if sc == "airdash" else -face
	var run: Array = []
	_hold(f, a, 0, 0, [], 2, [])
	_hold(f, a, face, -1, [], 1, [])
	_hold(f, a, face, 0, [], 10, [])
	_hold(f, a, ax, 0, ["dash"], 1, run)
	_hold(f, a, ax, 0, [], 24, run)
	var dash: Array = []
	for t in run:
		if String(t["kv_anim"]).begins_with("dash_air") and t["state"] == states.JUMP:
			dash.append(t)
	var low := INF
	for t in dash:
		for ft in t["feet"]:
			low = minf(low, ft["h"])
	report.append("%s %s f%+d %s: %d dash ticks at %.2f px/tick, lowest foot %.1f px over the floor" % [key, sc, face, mode, dash.size(), absf(dash[0]["vx"]) if not dash.is_empty() else 0.0, low])
	check(dash.size() >= 12, "%s %s f%+d %s: the air dash runs (%d ticks)" % [key, sc, face, mode, dash.size()])
	check(low >= AIR_PX, "%s %s f%+d %s: no foot within %.0f px of the floor in the air dash (lowest %.1f)" % [key, sc, face, mode, AIR_PX, low])
