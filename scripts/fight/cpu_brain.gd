class_name CpuBrain
extends RefCounted
## A small rules-based opponent. Reads the fighters' public state and produces a FightInput each
## frame. Deterministic: all randomness comes from its own seeded RandomNumberGenerator.
## level 0..3 (easy → hard) scales reaction time, blocking and aggression.

var me: Fighter
var foe: Fighter
var level := 1
var rng := RandomNumberGenerator.new()
var prev := FightInput.new()

var _plan := ""
var _plan_t := 0
var _x := 0
var _y := 0
var _taps: Array = []          # queued button taps: {btn, wait}
var _react := 0
var _block_t := 0
var _crouch_block := false
var _jg := false               # waiting, neutral, to press back so the block lands as a just guard
const JG_P := [0.0, 0.1, 0.2, 0.35]   # chance by level that a reaction tries a just guard instead of a plain block
const TECH_P := [0.0, 0.1, 0.25, 0.4]  # chance by level that a throw in startup is answered with a throw of its own
var _held_btns: Array = []
var _hold_btn := ""
var _hold_t := 0

func setup(fighter: Fighter, opponent: Fighter, lvl: int, seed_value: int) -> void:
	me = fighter
	foe = opponent
	level = clampi(lvl, 0, 3)
	rng.seed = seed_value

func think() -> FightInput:
	var btns: Array = []
	var dist := absf(foe.position.x - me.position.x) - me.spacing_extra()   # the legacy distance every threshold below was tuned on
	var grounded := me.is_grounded()
	var away := -me.facing if grounded else (-1 if foe.position.x > me.position.x else 1)   # in the air, away from the foe
	# ── defence: react to an incoming attack / projectile ───────────────────
	if _jg:
		var t := _ticks_to_hit()
		if t <= 0 or t > 12 or not (me.actionable() or me.state == Fighter.S.JUMP):
			_jg = false
		elif t <= int(me.stats["guard_jg"]):
			_jg = false
			_block_t = 10 + rng.randi_range(0, 6)
			return _out(away, 1 if (_crouch_block and grounded) else 0, [])
		else:
			return _out(0, 1 if (_crouch_block and grounded) else 0, [])
	if _block_t > 0:
		_block_t -= 1
		return _out(away, 1 if (_crouch_block and grounded) else 0, [])
	var threat := _threat(dist)
	if threat != "" and (me.actionable() or me.state == Fighter.S.JUMP):
		if _react > 0:
			_react -= 1
		elif threat == "throw":
			_react = 20
			if me.is_grounded() and rng.randf() < TECH_P[level]:
				return _out(0, 0, ["light", "heavy"])
		else:
			if rng.randf() < [0.2, 0.45, 0.7, 0.9][level]:
				_crouch_block = threat == "low" and grounded
				if _ticks_to_hit() > int(me.stats["guard_jg"]) and rng.randf() < JG_P[level]:
					_jg = true
					return _out(0, 1 if _crouch_block else 0, [])
				_block_t = 14 + rng.randi_range(0, 10)
				return _out(away, 1 if _crouch_block else 0, [])
			else:
				_react = 20
	else:
		_react = maxi(0, _react - 1)

	# ── continue an attack string ────────────────────────────────────────────
	if me.state == Fighter.S.ATTACK and me.move_connected:
		var nxt := _next_in_string()
		if nxt != "":
			_taps.append({"btn": nxt, "wait": 0})
	# queued taps (one press at a time, with a release frame between)
	if not _taps.is_empty():
		var t: Dictionary = _taps[0]
		if int(t["wait"]) > 0:
			t["wait"] = int(t["wait"]) - 1
		else:
			for b in String(t["btn"]).split("+"):   # "skill+ex" presses both on one frame (the super chord)
				btns.append(b)
			_taps.pop_front()
			if _hold_t > 0 and _hold_btn == t["btn"]:
				_held_btns = [t["btn"]]
			return _out(_x, _y, btns)
	if _hold_t > 0 and not _held_btns.is_empty():
		_hold_t -= 1
		if _hold_t == 0:
			_held_btns = []
		return _out(_x, _y, _held_btns.duplicate())
	if me.state == Fighter.S.ATTACK or not (me.actionable() or me.state == Fighter.S.JUMP):
		return _out(0 if me.state != Fighter.S.JUMP else _x, 0, [])

	# ── choose a plan ────────────────────────────────────────────────────────
	if _plan_t > 0:
		_plan_t -= 1
	else:
		_choose(dist)
	if me.state == Fighter.S.JUMP:
		if _plan == "air_attack" and _plan_t == 0:
			_taps.append({"btn": "heavy" if rng.randf() < 0.5 else "light", "wait": 0})
		return _out(_x, 0, [])
	return _out(_x, _y, [])

func _choose(dist: float) -> void:
	_x = 0
	_y = 0
	# the character's own style gets a say (bespoke kits)
	var kp := me.kit.ai_pick(me, foe, dist, rng)
	if not kp.is_empty() and rng.randf() < 0.55:
		for b in kp.get("taps", []):
			_taps.append({"btn": b, "wait": 0})
		_x = int(kp.get("x", 0)) * me.facing
		_y = int(kp.get("y", 0))
		_hold_btn = String(kp.get("hold_btn", ""))
		_hold_t = int(kp.get("hold", 0))
		_plan = "kit"
		_plan_t = int(kp.get("t", 24))
		return
	var r := rng.randf()
	var fast := 1.0 + 0.25 * float(level)
	if me.assist_ready() and dist > 180.0 and r < 0.12 * fast:
		_taps.append({"btn": "assist", "wait": 0})
		_plan = "assist"
		_plan_t = 20
		return
	# the super: skill and EX on one frame (ahead of any kit remap of the skill); below a full meter, so the ult stays the ult
	if me.meter >= Arena.SUPER_COST and me.meter < Arena.EX_COST and (foe.state in [Fighter.S.HIT, Fighter.S.AIRHIT, Fighter.S.BLOCK] or dist < 360.0) and r < 0.2 * fast:
		_taps.append({"btn": "skill+ex", "wait": 0})
		_y = 1 if rng.randf() < 0.3 else 0
		_plan = "super"
		_plan_t = 40
		return
	if me.meter >= Arena.EX_COST and (foe.state in [Fighter.S.HIT, Fighter.S.AIRHIT, Fighter.S.BLOCK] or dist < 420.0) and r < 0.25 * fast:
		_taps.append({"btn": "ex", "wait": 0})
		_plan = "ex"
		_plan_t = 40
		return
	if dist > 420.0:
		var q := rng.randf()
		if q < 0.4:
			_taps.append({"btn": "skill", "wait": 0})
			_plan = "shoot"
			_plan_t = 30
		elif q < 0.6:
			_taps.append({"btn": "dash", "wait": 0})
			_x = me.facing
			_plan = "dash"
			_plan_t = 18
		else:
			_x = me.facing
			_plan = "approach"
			_plan_t = roundi(rng.randi_range(14, 36) / Arena.MOVE_SCALE)
		return
	if dist > 190.0:
		var q2 := rng.randf()
		if q2 < 0.3:
			_x = me.facing
			_y = -1
			_plan = "air_attack"
			_plan_t = 28
		elif q2 < 0.5:
			_taps.append({"btn": "skill", "wait": 0})
			_plan = "shoot"
			_plan_t = 26
		elif q2 < 0.65:
			_taps.append({"btn": "dash", "wait": 0})
			_x = me.facing
			_plan = "dash"
			_plan_t = 16
		else:
			_x = me.facing
			_plan = "approach"
			_plan_t = roundi(rng.randi_range(8, 20) / Arena.MOVE_SCALE)
		return
	# close range
	if dist < Arena.THROW_RANGE and me.is_grounded() and foe.actionable() and rng.randf() < 0.08 * fast:
		_taps.append({"btn": "light+heavy", "wait": 0})
		_plan = "throw"
		_plan_t = 30
		return
	var q3 := rng.randf()
	if q3 < 0.55:
		_taps.append({"btn": "light", "wait": 0})
		_plan = "poke"
		_plan_t = 12
	elif q3 < 0.72:
		_taps.append({"btn": "heavy", "wait": 0})
		_plan = "heavy"
		_plan_t = 24
	elif q3 < 0.8:
		_y = 1
		_taps.append({"btn": "light", "wait": 0})
		_plan = "low"
		_plan_t = 14
	elif q3 < 0.9:
		_x = -me.facing
		_plan = "retreat"
		_plan_t = roundi(rng.randi_range(10, 22) / Arena.MOVE_SCALE)
	else:
		_taps.append({"btn": "skill", "wait": 0})
		_plan = "shoot"
		_plan_t = 20

func _next_in_string() -> String:
	var key := me.move_key
	if key in ["close_L", "6L"]:
		key = "5L"
	elif key in ["close_H", "6H"]:
		key = "5H"
	if key == "5L" or key == "2L":
		var q := rng.randf()
		if me.chain < 1 and q < 0.6:
			return "light"
		if q < 0.85:
			return "heavy"
		return "skill"
	if key == "5H":
		return "skill" if rng.randf() < 0.6 else ""
	if key == "skill" and me.meter >= Arena.EX_COST and rng.randf() < 0.5:
		return "ex"
	return ""

## Ticks until the foe's melee hit is live, or -1 when it has none. The hit resolves in the step the move reaches its startup frame.
func _ticks_to_hit() -> int:
	if foe.state != Fighter.S.ATTACK or foe.move.is_empty() or foe.move["hit"].is_empty():
		return -1
	return int(foe.move["startup"]) - foe.mf

## "" | "mid" | "low": is the foe about to hit me?
func _threat(dist: float) -> String:
	if foe.state == Fighter.S.ATTACK and not foe.move.is_empty():
		var h: Dictionary = foe.move.get("hit", {})
		if not h.is_empty() and dist < 260.0:
			return "throw" if h.get("throw", false) else str(h.get("level", "mid"))
		if foe.move["spawns"].size() > 0 and foe.mf >= int(foe.move["startup"]) - 4:
			return "mid"
	for p in me.world.projectiles:
		if not is_instance_valid(p):
			continue
		if p.owner_f == foe and not p.dead and absf(p.position.x - me.position.x) < 330.0 and p.kind != "blast":
			return "mid"
	return ""

func _out(x: int, y: int, btns: Array) -> FightInput:
	var fi := FightInput.from_held(prev, x, y, btns)
	prev = fi
	return fi
