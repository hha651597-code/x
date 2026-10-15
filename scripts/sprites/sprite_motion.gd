class_name SpriteMotion
extends RefCounted
## The motion mapper: turns a Fighter's simulation state into the sprite frame to show. Reads the sim, never writes it.
##
## Timing rules (the sim is authoritative):
##  * ATTACK: the pose is a pure function of the move frame f.mf against the move's startup / active / recovery
##    (SpriteSet.move_pose), so hit-stop (f.mf frozen), hold-to-charge (f.mf held) and cancels just work.
##  * Every other state plays its slot's animation on a clock that counts SIM ticks (f.frame), so loops and one-shots
##    freeze in hit-stop, in the EX cut-in time-stop and in pause, and slow down in the KO slow-motion.
##    Walk anims with a "stride" advance by the distance actually walked (no foot sliding at any speed).
##  * One-shots (intro, crouch-down, knockdown, get-up, KO, win…) hold their last frame; a transition anim (anims.json
##    "transitions", plus "land" after any airborne → grounded change) plays once before the new state's anim.

var sset: SpriteSet
var f: Fighter

# ── output (read by FighterView / SpriteActor every render frame) ──
var frame := ""               # frame name to show
var opts := {}                # nudges for this frame: {dx, dy, scale, flip}
var slot := ""                # state slot / "move:<key>" / "trans:<anim>"
var authored := true          # false when the slot / move fell back to another animation
var via := ""                 # the slot / move key whose drawing is actually shown (== slot when authored)
var phase := ""               # move phase (ATTACK only)
var smear := 0.0              # 0..1 on the first ticks of a fast attack's active frame
var airborne := false

var _state := -1
var _sf := 0
var _slot := ""
var _clock := 0.0
var _trans := ""
var _tclock := 0.0
var _last_frame := -1
var _last_x := 0.0
var _dist := 0.0
var _was_air := false
var _move_key := ""
var _prev_mf := -99
var _act_ticks := 0.0
var _prev_phase := ""
var _hit_slot := "hit"
var _block_slot := "block"
var _crouch_attack := false

func setup(s: SpriteSet, fighter: Fighter) -> void:
	sset = s
	f = fighter
	_last_x = f.position.x

## Call once per render frame (FighterView.step). Pure function of the sim + this mapper's clocks.
func update() -> void:
	var S := Fighter.S
	var ticks := 0
	if _last_frame >= 0:
		ticks = clampi(f.frame - _last_frame, 0, 30)
	_last_frame = f.frame
	var adv := 0.0 if f.hitstop > 0 else float(ticks)
	var entered := f.state != _state or f.sf < _sf
	if entered:
		_enter(_state, f.state)
		_state = f.state
	_sf = f.sf
	smear = 0.0
	phase = ""
	if f.state == S.ATTACK and not f.move.is_empty():
		_crouch_attack = bool(f.move.get("crouch", false))
		_update_move(adv)
	else:
		_update_state(adv)
	_last_x = f.position.x
	airborne = not f.is_grounded()
	# the sim lands one tick AFTER the position reaches the floor (a JUMP / air-attack frame can already be "grounded"), so a
	# jump or an air move counts as airborne for the landing check even on that last frame
	_was_air = airborne or f.state == Fighter.S.JUMP or (f.state == Fighter.S.ATTACK and bool(f.move.get("air", false)))

func _enter(old: int, new: int) -> void:
	var S := Fighter.S
	_clock = 0.0
	_dist = 0.0
	_trans = ""
	_tclock = 0.0
	_slot = ""
	var on: String = String(Fighter.STATE_NAMES[old]) if old >= 0 and old < Fighter.STATE_NAMES.size() else ""
	var nn: String = String(Fighter.STATE_NAMES[new]) if new >= 0 and new < Fighter.STATE_NAMES.size() else ""
	if old >= 0:
		_trans = sset.transition_for(on, nn)
	# landing: any airborne -> grounded change into a standing state plays "land" once (when authored)
	if _trans == "" and _was_air and f.is_grounded() and new in [S.IDLE, S.WALK, S.CROUCH] and sset.has_slot("land"):
		_trans = String(sset.resolve_slot("land")["anim"])
	match new:
		Fighter.S.HIT:
			var crouched: bool = old == S.CROUCH or (old == S.ATTACK and _crouch_attack) or f.input.y > 0 \
				or (old == S.HIT and _hit_slot == "hit_crouch")
			if crouched:
				_hit_slot = "hit_crouch"
			elif f.hitstun >= 28:
				_hit_slot = "stun"
			elif f.hitstop >= 11:
				_hit_slot = "hit_heavy"
			else:
				_hit_slot = "hit"
		Fighter.S.BLOCK:
			_block_slot = "block_crouch" if (f.input.y > 0 or old == S.CROUCH) else "block"

func _slot_for_state() -> String:
	match f.state:
		Fighter.S.IDLE:
			# Hina's OVERWORK (below 45 % HP the demon takes over): her restless, shadow-eyed idle
			return "idle_overwork" if bool(f.kv.get("rage", false)) and sset.has_slot("idle_overwork") else "idle"
		Fighter.S.WALK:
			return "walk" if signf(f.vel.x) * float(f.facing) >= 0.0 else "walk_back"
		Fighter.S.CROUCH: return "crouch"
		Fighter.S.JUMP:
			if f.vel.y < -3.5:
				return "jump_rise"
			if f.vel.y > 3.5:
				return "jump_fall"
			return "jump_apex"
		Fighter.S.HIT: return _hit_slot
		Fighter.S.AIRHIT:
			return "airhit_rise" if f.vel.y < 0.0 else "airhit_fall"
		Fighter.S.BLOCK: return _block_slot
		Fighter.S.DOWN: return "down"
		Fighter.S.GETUP: return "getup"
		Fighter.S.DASH: return "dash"
		Fighter.S.BACKDASH: return "backdash"
		Fighter.S.KO: return "ko"
		Fighter.S.INTRO: return "intro"
		Fighter.S.WIN: return "win"
	return "idle"

func _update_state(adv: float) -> void:
	# transition first (plays once, then the state's own anim starts from its beginning)
	if _trans != "":
		var ta: Dictionary = sset.anims.get(_trans, {})
		_tclock += adv
		if ta.is_empty() or _tclock >= float(ta["total"]):
			_trans = ""
		else:
			var r0 := sset.anim_at(ta, _tclock)
			_set_out(r0[0], ta)
			slot = "trans:" + _trans
			authored = true
			via = slot
			return
	var sl := _slot_for_state()
	if sl != _slot:
		# a new slot inside the same state (jump rise -> apex -> fall, walk fwd <-> back…) restarts its clock,
		# except walk <-> walk_back which keep the stride phase
		if not (_slot.begins_with("walk") and sl.begins_with("walk")):
			_clock = 0.0
		_slot = sl
	var r := sset.resolve_slot(sl)
	var a: Dictionary = sset.anims.get(String(r["anim"]), {})
	slot = sl
	authored = bool(r["authored"])
	via = String(r.get("via", sl))
	if a.is_empty():
		_show_any()
		return
	var t := 0.0
	if float(a["stride"]) > 0.0 and f.state == Fighter.S.WALK:
		if adv > 0.0:
			_dist += absf(f.position.x - _last_x)
		t = _dist / float(a["stride"]) * float(a["total"])
	else:
		_clock += adv
		t = _clock
	var res := sset.anim_at(a, t, bool(r["reverse"]))
	_set_out(res[0], a)

func _update_move(adv: float) -> void:
	var key := f.move_key
	if key != _move_key or f.mf < _prev_mf:
		_move_key = key
		_act_ticks = 0.0
		_prev_phase = ""
	_prev_mf = f.mf
	var ms := sset.move_spec(key, f.move)
	var sp: Dictionary = ms["spec"]
	var pose := sset.move_pose(sp, f.move, maxi(f.mf, 0))
	slot = "move:" + key
	authored = bool(ms["authored"])
	via = String(ms["via"])
	phase = String(pose["phase"])
	if String(pose["frame"]) == "" or not sset.frames.has(String(pose["frame"])):
		_show_any()
	else:
		frame = String(pose["frame"])
		opts = pose["opts"]
	# smear: the first ~2 ticks of the first active frame of a fast melee attack (anims.json move "smear" overrides)
	if phase != _prev_phase:
		_act_ticks = 0.0
		_prev_phase = phase
	var want: Variant = sp.get("smear", null)
	var fast: bool = not (f.move.get("hit", {}) as Dictionary).is_empty() and int(f.move.get("active", 9)) <= 8
	var use_smear: bool = bool(want) if want != null else fast
	if use_smear and bool(pose["first_active"]):
		smear = clampf(1.0 - _act_ticks / 2.0, 0.0, 1.0)
		_act_ticks += adv

func _set_out(entry: Array, a: Dictionary) -> void:
	frame = String(entry[0])
	opts = SpriteSet.merge(a.get("opts", {}), entry[2])
	if not sset.frames.has(frame):
		_show_any()

func _show_any() -> void:
	# last resort so something is always drawn: the idle anim's first frame, else any frame
	var r := sset.resolve_slot("idle")
	var a: Dictionary = sset.anims.get(String(r["anim"]), {})
	if not a.is_empty() and sset.frames.has(String(a["frames"][0][0])):
		frame = String(a["frames"][0][0])
	elif not sset.frames.is_empty():
		frame = String(sset.frames.keys()[0])
	opts = {}
	authored = false

## True when the shown drawing is a stand-in for a lying / flying slot (e.g. a hit frame for an unauthored knockdown):
## FighterView then lays the whole drawing down with the puppet's body pose so a knockdown still reads as one.
func needs_body_pose() -> bool:
	if authored:
		return false
	match f.state:
		Fighter.S.DOWN, Fighter.S.KO:
			return not (via in ["down", "ko"])
		Fighter.S.GETUP:
			return via != "getup"
		Fighter.S.AIRHIT:
			return not (via in ["airhit_rise", "airhit_fall", "down", "ko"])
	return false

## True while the shown pose is a held, quiet one (breathing bob is allowed).
func breathing() -> bool:
	var S := Fighter.S
	return f.state in [S.IDLE, S.CROUCH, S.INTRO, S.WIN] and _trans == ""
