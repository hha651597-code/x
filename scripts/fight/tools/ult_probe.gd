extends RefCounted
## Debug-only EX-freeze proof harness. Inert unless the environment variable ULT_TEST is set, e.g.
##   ULT_TEST=meter,log,check tools/run.sh scripts/fight/tools/shots/ult_freeze_p1_hoshino.json
##   ULT_TEST=meter,check    tools/sim.sh scripts/fight/tools/shots/ult_cpu_sim.json
## Parts:
##   meter  both players start every round with a full EX meter (100 = one ult)
##   log    one "ULT {...}" line per sim tick from 3 ticks before an EX trigger until 40 ticks after the resume:
##          frame, frozen, time_stop, freeze_t, both fighters (x, y, state, move, mf, hitstop), projectile positions,
##          particle count, effect-node count, event count, timer
##   check  automatic invariants, one "ULT_CHECK ..." line per freeze: every frozen tick must leave the world snapshot
##          identical (positions, velocities, states, move frames, hit-stop, buffers, projectiles, particles, effects,
##          assist events, timer, CPU-visible frame counter); the freeze must last FREEZE_FRAMES per queued cut-in; on
##          the first tick after the resume each caster's move frame advances by exactly one (no skipped frames).

var opts := {}
var _snap := {}
var _frozen_ticks := 0
var _casters := 0
var _ok := true
var _why := ""
var _count := 0
var _resume_check := []      # [[fighter, mf at freeze]] verified on the first resumed tick
var _last_vis := -1
var _ring: Array = []        # last few ticks (printed when a trigger shows up)
var _log_left := 0
var _seen_log := 0

func setup(spec: String) -> void:
	for part in spec.split(","):
		opts[part.strip_edges()] = true
	print("ULT_TEST ", opts.keys())

func round_start(w: Node) -> void:
	if opts.has("meter"):
		(w.get("f1") as Fighter).meter = 100.0
		(w.get("f2") as Fighter).meter = 100.0

## Called after every physics frame's sim step(s).
func tick(w: Node) -> void:
	var vis: int = w.get("_vis_frame")
	if vis == _last_vis:
		return                      # paused / busy: no sim tick happened
	_last_vis = vis
	var frozen: bool = int(w.get("time_stop")) > 0
	if opts.has("check"):
		_check(w, frozen)
	if opts.has("log"):
		_log(w)

func _fighter_state(f: Fighter) -> Array:
	return [snappedf(f.position.x, 0.001), snappedf(f.position.y, 0.001), snappedf(f.vel.x, 0.001), snappedf(f.vel.y, 0.001),
		f.state, f.sf, f.mf, f.move_key, f.hitstop, f.hitstun, f.blockstun, f.invuln, snappedf(f.hp, 0.01), snappedf(f.meter, 0.01),
		f.frame, f.assist_cd, str(f._buf), f.facing, f.combo_hits]

func _world_state(w: Node) -> Dictionary:
	var projs: Array = []
	for p in w.get("projectiles"):
		if is_instance_valid(p):
			var pr: Projectile = p
			projs.append([snappedf(pr.position.x, 0.01), snappedf(pr.position.y, 0.01), snappedf(pr.vel.x, 0.01), snappedf(pr.vel.y, 0.01), pr.life, pr.dead])
	var fx_layer: Node = w.get("fx_layer")
	var parts := -1
	var pn := fx_layer.get_node_or_null("Particles")
	if pn != null:
		parts = (pn as FxParticles)._ps.size()
	var fx_ages: Array = []
	for c in fx_layer.get_children():
		if c is Fx:
			fx_ages.append(snappedf((c as Fx).age, 0.0001))
	return {
		"f1": _fighter_state(w.get("f1")), "f2": _fighter_state(w.get("f2")), "proj": projs, "parts": parts,
		"fx": fx_ages, "events": (w.get("_events") as Array).size(), "timer": w.get("timer_frames"), "frame": w.get("_frame"),
		"phase": w.get("phase"), "phase_t": w.get("phase_t"), "slowmo": w.get("slowmo"),
	}

func _check(w: Node, frozen: bool) -> void:
	if _snap.is_empty():
		if not frozen:
			return
		# first look at a new freeze: the trigger tick just ended and the world is stopped
		_count += 1
		_ok = true
		_why = ""
		_frozen_ticks = 0
		_snap = _world_state(w)
		var q: Array = w.get("_freeze_queue")
		_casters = q.size()
		_resume_check = []
		for c in q:
			var cf: Fighter = c
			_resume_check.append([cf, cf.mf])
		return
	var now := _world_state(w)
	if frozen or int(now["frame"]) == int(_snap["frame"]):
		# a frozen tick (including the last one, which ends the freeze without simulating): nothing may change
		_frozen_ticks += 1
		for k in _snap:
			if str(_snap[k]) != str(now[k]):
				_fail("frozen tick %d: %s changed %s -> %s" % [_frozen_ticks, k, str(_snap[k]), str(now[k])])
				_snap[k] = now[k]
		return
	# first simulated tick after the resume
	var consts: Dictionary = w.call("freeze_consts")
	var expect := int(round(float(consts["freeze_s"]) * 60.0)) * _casters
	if _frozen_ticks != expect:
		_fail("freeze lasted %d ticks, expected %d" % [_frozen_ticks, expect])
	if int(now["frame"]) != int(_snap["frame"]) + 1:
		_fail("sim frame jumped %d -> %d" % [int(_snap["frame"]), int(now["frame"])])
	for pair in _resume_check:
		var f: Fighter = pair[0]
		var mf0: int = pair[1]
		if f.state == Fighter.S.ATTACK and f.move_key == "ex" and f.mf != mf0 + 1:
			_fail("P%d resumed at mf %d (frozen at %d)" % [f.slot, f.mf, mf0])
	print("ULT_CHECK #%d %s frozen_ticks=%d casters=%d frame=%d %s" % [_count, "OK" if _ok else "FAIL", _frozen_ticks, _casters, int(now["frame"]), _why])
	_resume_check = []
	_snap = {}

func _fail(msg: String) -> void:
	if _ok:
		_why = msg
	_ok = false
	printerr("ULT_CHECK violation: ", msg)

func _log(w: Node) -> void:
	var fl: Array = w.get("freeze_log")
	var line := _line(w)
	_ring.append(line)
	if _ring.size() > 3:
		_ring.pop_front()
	if fl.size() != _seen_log:
		_seen_log = fl.size()
		if _log_left <= 0:
			for r in _ring:
				print("ULT ", JSON.stringify(r))
		_log_left = 40 + 72 * 2
		return
	if int(w.get("time_stop")) > 0:
		_log_left = maxi(_log_left, 41)
	if _log_left > 0:
		_log_left -= 1
		print("ULT ", JSON.stringify(line))

func _line(w: Node) -> Dictionary:
	var out := {"frame": w.get("_frame"), "vis": w.get("_vis_frame"), "ts": w.get("time_stop"), "ft": w.get("freeze_t"),
		"frozen": w.get("world_frozen"), "rel": w.get("release_t"), "timer": w.get("timer_frames")}
	for i in 2:
		var f: Fighter = w.get("f1") if i == 0 else w.get("f2")
		out["p%d" % (i + 1)] = [snappedf(f.position.x, 0.01), snappedf(f.position.y, 0.01), f.state_name(), f.move_key if f.state == Fighter.S.ATTACK else "", f.mf, f.hitstop, snappedf(f.meter, 0.1), f.z_index]
	var st := _world_state(w)
	out["proj"] = (st["proj"] as Array).size()
	out["parts"] = st["parts"]
	out["fx"] = (st["fx"] as Array).size()
	out["events"] = st["events"]
	return out
