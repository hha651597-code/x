extends SceneTree
## Stage-entry intro the way other fighters open a match: P1's solo
## shot, the pan, P2's solo shot, the wide block with the ROUND band and FIGHT! on tick 336, control on tick 360. The camera on
## every tick, the poses, who is visible, the voice ticks, the FIGHT! call, the skip and pause, round 2's 120 tick wide block and
## the matches that keep the 60 tick intro. Both fighter orders. Hina and Hoshino only (the sprite kits are checked as data).
## Run with TEST=res://scripts/models/tests/intro_test.gd tools/sd_test.sh (a real small window).
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

const SHOT := 96
const PAN := 36
const WIDE := 229        # the first tick of the wide block
const FULL := 360
const ROUND := 120       # round 2 and 3
const FIGHT_AT := 336    # FIGHT! shows this tick (24 before control)
const READY_AT := 272    # the ready beat starts here in the entry: it ends 28 ticks before control, 4 before FIGHT!
const READY_AT_2 := 32   # and here in round 2 and 3 (120 ticks)
const FACE_BAND := Vector2(300.0, 420.0)
const MAX_ZOOM := 1.8

var checks := 0
var failures: Array = []
var game: Node
var screen: Node
var states: Dictionary
var K: Dictionary
var T: Dictionary
var M: GDScript
var sfx: Node
var dbg: Node
var controls: Node
var face_report: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("INTRO_CHECK FAIL ", label)
		failures.append(label)

func _run() -> void:
	create_timer(300.0).timeout.connect(func() -> void:
		print("INTRO_TEST FAIL watchdog timeout")
		quit(3))
	await process_frame
	K = (load("res://scripts/fight/arena.gd") as GDScript).get_script_constant_map()
	M = load("res://scripts/fight/movesets.gd")
	game = root.get_node("Game")
	sfx = root.get_node("Sfx")
	dbg = root.get_node("Dbg")
	controls = root.get_node("Controls")
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	await _match("versus2p", 10004, 10005)
	T = screen.get_script().get_script_constant_map()
	_data()
	_timeline("hina first")
	_forced_phase()
	_pause()
	_close_ups()
	_held_buttons()
	_skip()
	_skip_buttons()
	_ignored_skips()
	_later_rounds()
	_hud_contract()
	_review_cases()
	_camera_after_the_entry()
	_flag_off()
	await _match("versus2p", 10005, 10004)
	_timeline("hoshino first")
	await _match("training", 10004, 10005)
	_training()
	for line in face_report:
		print("INTRO_FACE ", line)
	print("INTRO_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

# ── helpers ──────────────────────────────────────────────────────────────────
func _match(mode: String, p1: int, p2: int) -> void:
	game.session.begin(mode)
	game.session.players[0]["fighter"] = p1
	game.session.players[1]["fighter"] = p2
	game.session.players[0]["special"] = 10017
	game.session.players[1]["special"] = 10017
	await game.go("fight", {}, "cut")
	screen = game.stack.back()
	screen.set_physics_process(false)
	states = screen.f1.get_script().S
	_first_round()

## A fresh first round, whatever physics frames ran while the match loaded.
func _first_round() -> void:
	screen.set("_entered", false)
	screen.f1.human = true
	screen.f2.human = screen.mode == "versus2p"
	screen._start_round()

func _steps(n: int) -> void:
	for i in n:
		screen._sim_step()

func _played(name: String) -> int:
	return int(sfx.played.get(name, 0))

func _voices(f: Node) -> Array:
	return sfx.voice_log.filter(func(v: Dictionary) -> bool: return v["event"] == "intro" and v["slot"] == f.slot)

func _lift() -> float:
	return float(screen.bg_layer.get_meta("lift", 0.0))

func _view(f: Node) -> void:
	f.view.step(1.0 / 60.0)

## The easings and the table, written out here rather than called.
func _ss(u: float) -> float:
	return u * u * (3.0 - 2.0 * u)

func _sss(u: float) -> float:
	return u * u * u * (u * (u * 6.0 - 15.0) + 10.0)

## [zoom, cam_x, lift] on tick t of the entry, from the table (P1 on the left mark, P2 on the right).
func _want_cam(t: int) -> Array:
	var z := 1.0
	var x := 0.0
	if t <= SHOT:
		z = 1.52 + 0.18 * _ss(float(t - 1) / 95.0)
		x = -190.0
	elif t <= SHOT + PAN:
		var e := _sss(float(t - SHOT) / float(PAN))
		z = 1.70 - 0.18 * e
		x = -190.0 + 380.0 * e
	elif t < WIDE:
		z = 1.52 + 0.18 * _ss(float(t - SHOT - PAN - 1) / 95.0)
		x = 190.0
	else:
		return [1.0, 0.0, 0.0]
	return [z, x, 177.0 - 232.0 / z]

## What fighter `slot` plays after sim tick t (sf equals t then): the idle until its own shot, intro_cut from the shot's first
## tick through the pan and the other shot, the idle from the wide block, the ready beat for 60 ticks from READY_AT, then the idle
## again with its long crossfade (intro_idle).
func _want_step(slot: int, t: int) -> Array:
	if t >= WIDE:
		if t < READY_AT:
			return ["idle", t]
		return ["intro", t - READY_AT] if t - READY_AT < 60 else ["intro_idle", t]
	var start := 1 + (slot - 1) * (SHOT + PAN)
	return ["intro_cut", t - start] if t >= start else ["idle", t]

func _step_of(f: Node) -> Array:
	return f.intro_step() if f.has_method("intro_step") else ["", -1]

## Which fighters are drawn on tick t: the one in a locked shot alone, both in the pan and the wide block.
func _want_visible(slot: int, t: int) -> bool:
	if t <= SHOT:
		return slot == 1
	if t > SHOT + PAN and t < WIDE:
		return slot == 2
	return true

## The state both endings must leave: marks, IDLE, no velocity, input, phase and the camera. Not the assist cooldown (it counts from
## the FIGHT! call, which a skip makes earlier), sf, frame or
## _frame.
func _end_state() -> Array:
	var out: Array = [screen.phase, screen.phase_t, screen.cam_zoom, screen.cam_x, _lift(), screen.get("intro_cut"), screen.get("intro_cover")]
	for f in screen.fighters:
		out.append([f.position, f.vel, f.state, f.input.held, f.input.pressed, f.facing, f.visible])
	return out

# ── the entry decision, the constants, the shot table ────────────────────────
func _data() -> void:
	check(screen.get("intro_len") == FULL, "a versus2p first round plays the entry: 360 ticks (got %s)" % str(screen.get("intro_len")))
	check(K.get("INTRO_SHOT") == SHOT and K.get("INTRO_PAN") == PAN and K.get("INTRO_WIDE_AT") == WIDE and K.get("INTRO_FULL") == FULL, "the constants: shot 96, pan 36, wide block from 229, 360 in all")
	check(K.get("INTRO_ROUND") == ROUND and K.get("INTRO_FIGHT_LEAD") == FULL - FIGHT_AT and K.get("INTRO_READY") == 60, "round 2 and 3 take 120, FIGHT! leads control by 24, the short intro is 60")
	check(K.get("INTRO_X") == 865.0, "INTRO_X stays defined for the arenas test")
	check(not K.has("INTRO_CUTS") and not K.has("INTRO_CUT_LEN") and not K.has("INTRO_SPEED") and not K.has("INTRO_RUN"), "the four cuts' and the run-in's constants are gone")
	for f in screen.fighters:
		check(int(f.stats.get("intro_run", -1)) == 0, "slot %d: the intro_run stat is 0, nothing reads it" % f.slot)
	var sprites := 0
	for e in game.fighters:
		if e["key"] != "hina" and e["key"] != "hoshino":
			sprites += 1
			check(int(M.stats_for(e).get("intro_run", -1)) == 0, "sprite kit %s has intro_run 0" % e["key"])
	check(sprites == 0, "every roster fighter has a model (%d without)" % sprites)
	check(int(M.stats_for({"weapon": "AR", "bullet": "Pierce", "role": "DamageDealer", "armor": "Unarmed"}).get("intro_run", -1)) == 0, "a roster entry without a key has intro_run 0")
	check(dbg.get("intro_entry") == true, "outside a step file the entry flag is on")
	var cfgs: Script = load("res://scripts/models/sd_config.gd")
	for key in ["hina", "hoshino"]:
		var anims: Dictionary = cfgs.of(key)["anims"]
		check(anims.has("intro_cut") and anims.has("intro"), "%s: intro_cut and the ready beat are mapped" % key)
	var k: Dictionary = T.get("ENTRY_SHOT", {})
	check(not T.has("CUT_KINDS") and not k.is_empty(), "one shot table, the old assist and fighter cuts are gone")
	if not k.is_empty():
		check(float(k["z0"]) == 1.52 and float(k["z1"]) == 1.7 and float(k["zb"]) == 1.52 and float(k["lead"]) == 40.0, "the table: zoom 1.52 to 1.7, the pan lands on 1.52, lead 40 px")
		check(float(k["z0"]) > 1.5 and float(k["zb"]) > 1.5 and float(k["z1"]) <= 1.75, "every shot zoom is in (1.5, 1.75], one viewport scale of 1.75, never over 1.8")
		check(float(k["face_y"]) == 380.0 and float(k["face_up"]) == 177.0, "the face is held at screen y 380 from a face height of 177")

# ── the whole timeline, tick by tick ─────────────────────────────────────────
func _timeline(label: String) -> void:
	_first_round()
	var f1: Node = screen.f1
	var f2: Node = screen.f2
	var fights0 := _played("fight")
	var timer0: int = screen.timer_frames
	var v1 := _voices(f1).size()
	var v2 := _voices(f2).size()
	check(f1.position.x == -230.0 and f2.position.x == 230.0, "%s: both fighters start on their marks, no run-in (%.1f, %.1f)" % [label, f1.position.x, f2.position.x])
	var bad := {}
	var frame0: int = f1.frame
	var prev := [1.52, -190.0]
	for t in range(1, FULL):
		screen._sim_step()
		_view(f1)
		_view(f2)
		var tag := "%s tick %d" % [label, t]
		var shooting := t < WIDE
		var cut := 0 if t <= SHOT else (1 if t > SHOT + PAN and t < WIDE else -1)
		_note(bad, "phase", screen.phase == "intro" and screen.phase_t == t, tag + ": phase intro, phase_t %d (%s %d)" % [t, screen.phase, screen.phase_t])
		_note(bad, "marks", f1.position.x == -230.0 and f2.position.x == 230.0 and f1.vel.x == 0.0 and f2.vel.x == 0.0 and f1.state == states.INTRO and f2.state == states.INTRO, tag + ": on the marks, at rest, in INTRO")
		_note(bad, "timer", screen.timer_frames == timer0, tag + ": the round timer has not started")
		var want_cd := 0 if t <= FIGHT_AT else t - FIGHT_AT
		_note(bad, "assist", f1.assist_cd == int(f1.stats["assist_cd"]) - want_cd and f2.assist_cd == int(f2.stats["assist_cd"]) - want_cd, tag + ": the support cooldown is full until FIGHT! and counts from it (%d, %d, want minus %d)" % [f1.assist_cd, f2.assist_cd, want_cd])
		_note(bad, "kit", f1.frame == frame0 + t, tag + ": Fighter.frame counts (the kit ticks run through the intro)")
		_note(bad, "freeze", screen.time_stop == 0 and screen.freeze_caster == null and screen.freeze_log.is_empty(), tag + ": no cut-in, no time stop")
		_note(bad, "cut", screen.intro_cut == cut, tag + ": intro_cut %d (got %s)" % [cut, str(screen.intro_cut)])
		var want_t := -1 if cut < 0 else (t - 1 if cut == 0 else t - SHOT - PAN - 1)
		_note(bad, "cut_t", screen.intro_cut_t == want_t, tag + ": intro_cut_t %d (got %s)" % [want_t, str(screen.intro_cut_t)])
		_note(bad, "side", screen.intro_side == cut, tag + ": intro_side %d (got %s)" % [cut, str(screen.intro_side)])
		var want_pan := float(t - SHOT) / float(PAN) if t > SHOT and t <= SHOT + PAN else -1.0
		_note(bad, "pan", is_equal_approx(screen.intro_pan, want_pan), tag + ": intro_pan %.3f (got %s)" % [want_pan, str(screen.intro_pan)])
		var want_cover := clampf(1.0 - float(t - WIDE) / float(T["COVER_RAMP"]), 0.0, 1.0)
		_note(bad, "cover", is_equal_approx(screen.intro_cover, want_cover), tag + ": intro_cover %.3f (got %s)" % [want_cover, str(screen.intro_cover)])
		for f in [f1, f2]:
			var want := _want_step(f.slot, t)
			_note(bad, "step", _step_of(f) == want, tag + ": slot %d plays %s (got %s)" % [f.slot, str(want), str(_step_of(f))])
			_note(bad, "anim", f.view.sd_actor.anim_name == want[0], tag + ": slot %d's actor shows %s (got %s)" % [f.slot, want[0], f.view.sd_actor.anim_name])
			_note(bad, "visible", f.visible == _want_visible(f.slot, t), tag + ": slot %d is %s (visible %s)" % [f.slot, "drawn" if _want_visible(f.slot, t) else "hidden", str(f.visible)])
		var z: float = screen.cam_zoom
		var shot_lift := _lift()
		var want_cam := _want_cam(t)
		_note(bad, "zoom cap", z <= MAX_ZOOM, tag + ": zoom %.3f never passes 1.8" % z)
		_note(bad, "612", absf(screen.world_root.position.y - (612.0 - 560.0 * z + shot_lift * z)) < 0.01 and absf(screen.world_root.scale.x - z) < 1e-6, tag + ": the feet row stays pinned at 612")
		_note(bad, "z", absf(z - float(want_cam[0])) < 1e-4, tag + ": zoom %.4f, want %.4f" % [z, float(want_cam[0])])
		_note(bad, "x", absf(screen.cam_x - float(want_cam[1])) < 1e-3, tag + ": camera x %.2f, want %.2f" % [screen.cam_x, float(want_cam[1])])
		_note(bad, "lift", absf(shot_lift - float(want_cam[2])) < 1e-3, tag + ": lift %.3f, want %.3f" % [shot_lift, float(want_cam[2])])
		_note(bad, "xlimit", absf(screen.cam_x) <= 200.0 + 1e-6, tag + ": |camera x| is at most 200 (got %.2f)" % screen.cam_x)
		if shooting:
			_note(bad, "zoom floor", z >= 1.5 - 1e-6, tag + ": a shot never goes under zoom 1.5 (%.3f)" % z)
			_note(bad, "pan speed", absf(screen.cam_x - float(prev[1])) <= 20.0 and absf(z - float(prev[0])) <= 0.02, tag + ": no jump inside the shots and the pan (x %.2f to %.2f, zoom %.4f to %.4f)" % [float(prev[1]), screen.cam_x, float(prev[0]), z])
			for f in [f1, f2]:
				if f.visible:
					_note(bad, "sharp", f.view.sd_actor.view_scale == 1.75, tag + ": slot %d's viewport scale is 1.75 for zoom %.3f, no reallocation inside the entry (%.2f)" % [f.slot, z, f.view.sd_actor.view_scale])
		else:
			_note(bad, "wide", z == 1.0 and screen.cam_x == 0.0 and shot_lift == 0.0, tag + ": the wide block is zoom 1, x 0, lift 0 exactly (%.4f, %.4f, %.4f)" % [z, screen.cam_x, shot_lift])
			_note(bad, "wide scale", f1.view.sd_actor.view_scale == 1.0 and f2.view.sd_actor.view_scale == 1.0, tag + ": the viewports are back at the window's scale")
		if cut >= 0:
			var who: Node = [f1, f2][cut]
			var h: Vector2 = who.view.head_pos()
			var sx: float = screen.world_root.position.x + h.x * z
			var sy: float = screen.world_root.position.y + h.y * z
			_note(bad, "face y", sy >= FACE_BAND.x and sy <= FACE_BAND.y, tag + ": slot %d's face at screen y %.0f, want %.0f to %.0f" % [who.slot, sy, FACE_BAND.x, FACE_BAND.y])
			_note(bad, "face x", sx >= 150.0 and sx <= 1130.0, tag + ": slot %d's face at screen x %.0f is in frame" % [who.slot, sx])
			if t == 1 or t == SHOT or t == SHOT + PAN + 1 or t == WIDE - 1 or t % 24 == 0:
				face_report.append("%s tick %d shot %d: zoom %.3f x %.1f lift %.1f face (%.0f, %.0f) scale %.2f" % [label, t, cut, z, screen.cam_x, shot_lift, sx, sy, who.view.sd_actor.view_scale])
		_note(bad, "fight sound", _played("fight") == fights0 + (1 if t >= FIGHT_AT else 0), tag + ": FIGHT! plays once, on tick 336")
		_note(bad, "voice1", _voices(f1).size() == v1 + (1 if t >= 3 else 0), tag + ": P1's voice fires once, at tick 3")
		_note(bad, "voice2", _voices(f2).size() == v2 + (1 if t >= SHOT + PAN + 3 else 0), tag + ": P2's voice fires once, at tick 135")
		prev = [z, screen.cam_x]
	for k in bad:
		check(false, "%s: %s (%d ticks, first: %s)" % [label, k, bad[k]["n"], bad[k]["first"]])
	# the cut to the wide block is one hard step, the pan and the shots are not
	_first_round()
	_steps(WIDE - 2)
	var z228: float = screen.cam_zoom
	_steps(1)
	check(screen.phase_t == WIDE - 1 and screen.cam_zoom > 1.6 and screen.cam_x == 190.0, "%s: tick 228 is still P2's close shot (%.3f, %.1f)" % [label, screen.cam_zoom, screen.cam_x])
	_steps(1)
	check(screen.phase_t == WIDE and screen.cam_zoom == 1.0 and screen.cam_x == 0.0 and _lift() == 0.0, "%s: tick 229 cuts to the wide shot at once" % label)
	_first_round()
	fights0 = _played("fight")
	v1 = _voices(f1).size()
	v2 = _voices(f2).size()
	timer0 = screen.timer_frames
	_steps(FULL - 1)
	check(screen.phase == "intro" and screen.phase_t == FULL - 1, "%s: tick 359 is still the intro" % label)
	_steps(1)
	check(screen.phase == "fight" and screen.phase_t == 0, "%s: tick 360 is control (%s)" % [label, screen.phase])
	check(_played("fight") == fights0 + 1, "%s: one FIGHT! sound in all" % label)
	check(f1.state == states.IDLE and f2.state == states.IDLE and f1.visible and f2.visible, "%s: both fighters are IDLE and drawn at control" % label)
	check(f1.assist_cd == int(f1.stats["assist_cd"]) - 24 and f2.assist_cd == int(f2.stats["assist_cd"]) - 24, "%s: the support cooldown has counted the 24 ticks since FIGHT! at control (%d, %d)" % [label, f1.assist_cd, f2.assist_cd])
	check(screen.cam_zoom == 1.0 and screen.cam_x == 0.0 and _lift() == 0.0, "%s: the camera is wide at control" % label)
	check(screen.intro_cut == -1 and screen.intro_cover == 0.0 and screen.intro_side == -1 and screen.intro_pan == -1.0, "%s: no intro properties in the fight phase" % label)
	check(_voices(f1).size() == v1 + 1 and _voices(f2).size() == v2 + 1, "%s: one voice line per fighter" % label)
	for f in [f1, f2]:
		var line: Dictionary = _voices(f).back()
		check(String(line["clip"]).ends_with("Battle_In_2.ogg"), "%s: slot %d's line is Battle_In_2 (%s)" % [label, f.slot, line["clip"]])
	check(screen.timer_frames == timer0, "%s: the round timer starts full" % label)
	screen._sim_step()
	check(screen.timer_frames == timer0 - 1, "%s: and counts down in the fight phase" % label)
	check(f1.assist_cd == int(f1.stats["assist_cd"]) - 25 and f2.assist_cd == int(f2.stats["assist_cd"]) - 25, "%s: and it keeps counting (%d, %d)" % [label, f1.assist_cd, f2.assist_cd])
	for f in [f1, f2]:
		_view(f)
		check(f.view.sd_actor.view_scale == 1.0, "%s: slot %d's viewport is at the window's scale in the fight" % [label, f.slot])

func _note(bad: Dictionary, key: String, ok: bool, label: String) -> void:
	checks += 1
	if ok:
		return
	if not bad.has(key):
		bad[key] = {"n": 0, "first": label}
	bad[key]["n"] += 1

## Face height from the real head in the real pose, and a locked shot never shows the foe.
func _close_ups() -> void:
	_first_round()
	var faces: Array = []
	for t in range(1, WIDE):
		screen._sim_step()
		_view(screen.f1)
		_view(screen.f2)
		if t == 48 or t == SHOT + PAN + 48:
			var who: Node = screen.f1 if t == 48 else screen.f2
			var h: Vector2 = who.view.head_pos()
			faces.append(screen.world_root.position.y + h.y * screen.cam_zoom)
	check(faces.size() == 2, "both solo shots were sampled")
	for y in faces:
		check(y >= 340.0 and y <= 430.0, "a solo shot holds the face near y 380 (%.0f)" % y)
	var a: Node = screen.f1.view.sd_actor
	a.fit_zoom(1.24)
	check(a.view_scale == 1.0, "an EX freeze zoom of 1.24 leaves the viewport at the window's scale")
	a.fit_zoom(1.8)
	check(a.view_scale >= 1.8 and a.view_scale <= float(a.MAX_VIEW_SCALE), "zoom 1.8 grows the viewport to a quarter step above it (%.2f)" % a.view_scale)
	a.fit_zoom(3.0)
	check(a.view_scale == float(a.MAX_VIEW_SCALE), "the viewport scale is capped (%.2f)" % a.view_scale)
	a.fit_zoom(1.0)
	check(a.view_scale == 1.0, "back at zoom 1 the viewport shrinks to the window's scale")

## A forced phase change mid-shot leaves a wide camera on the next camera update (no glide out of a close-up), and both fighters drawn.
func _forced_phase() -> void:
	_first_round()
	_steps(50)
	check(screen.cam_zoom > 1.5 and screen.intro_cut == 0 and not screen.f2.visible, "setup: mid P1 shot with a close camera and P2 hidden (%.3f)" % screen.cam_zoom)
	screen.phase = "fight"
	screen._apply_camera()
	check(screen.cam_zoom == 1.0 and screen.cam_x == 0.0 and _lift() == 0.0, "forcing the fight phase mid-shot gives a wide camera on the next update (%.3f, %.2f, %.2f)" % [screen.cam_zoom, screen.cam_x, _lift()])
	check(screen.intro_cut == -1 and screen.intro_cover == 0.0 and screen.f1.visible and screen.f2.visible, "and the shot properties read off, both fighters drawn")
	screen.phase = "intro"
	_first_round()

func _pause() -> void:
	_first_round()
	_steps(2)
	var v := _voices(screen.f1).size()
	screen.set_paused(true)
	var z: float = screen.cam_zoom
	_steps(30)
	check(screen.phase_t == 2 and screen.cam_zoom == z, "paused: the clock and the camera hold (%d)" % screen.phase_t)
	check(_voices(screen.f1).size() == v, "paused: no voice")
	screen.set_paused(false)
	_steps(1)
	check(screen.phase_t == 3 and _voices(screen.f1).size() == v + 1, "unpaused: the voice fires on tick 3, once")
	_steps(1)
	check(_voices(screen.f1).size() == v + 1, "and not again")

# ── held buttons, skip ───────────────────────────────────────────────────────
func _held_buttons() -> void:
	_first_round()
	controls.set_held("kb1", "confirm", true)
	_steps(FULL)
	check(screen.phase == "fight", "a held button does not skip")
	_steps(1)
	check(screen.f1.state != states.ATTACK, "a light button held through the intro does not attack on the first fight tick")
	_steps(1)
	check(screen.f1.state != states.ATTACK, "and not on the next either")
	controls.set_held("kb1", "confirm", false)
	_steps(2)
	controls.set_held("kb1", "confirm", true)
	_steps(1)
	check(screen.f1.state == states.ATTACK, "a fresh press in the fight phase still attacks")
	controls.set_held("kb1", "confirm", false)

func _skip() -> void:
	_first_round()
	_steps(FULL)
	var natural := _end_state()
	for at in [30, 100, 250, 340]:
		_first_round()
		var fights0 := _played("fight")
		_steps(at)
		screen.on_action("kb1", "confirm")
		_steps(1)
		if at == 30:
			check(screen.phase == "intro" and screen.phase_t == 31, "a press on tick 30 is ignored (%s, %d)" % [screen.phase, screen.phase_t])
			screen.on_action("kb2", "back")
			_steps(1)
			check(screen.phase == "fight" and screen.phase_t == 0, "a press after tick 30 ends the intro on the next tick (%s)" % screen.phase)
		else:
			check(screen.phase == "fight" and screen.phase_t == 0, "a press on tick %d ends the intro on the next tick" % at)
		check(_played("fight") == fights0 + 1, "a skip at tick %d plays one FIGHT! sound, not two" % at)
		var cd_full: int = int(screen.f1.stats["assist_cd"])
		var cd_want: int = cd_full if at < FIGHT_AT else cd_full - (at + 1 - FIGHT_AT)
		check(screen.f1.assist_cd == cd_want and not screen.f1.assist_hold, "a skip at tick %d: the support cooldown starts at the FIGHT! call, full if it was not called yet (%d, want %d)" % [at, screen.f1.assist_cd, cd_want])
		check(screen.cam_zoom == 1.0 and screen.cam_x == 0.0 and _lift() == 0.0, "a skip at tick %d leaves the camera wide" % at)
		var skipped := _end_state()
		check(str(skipped) == str(natural), "a skip at tick %d ends in the natural end's state\n  skip    %s\n  natural %s" % [at, str(skipped), str(natural)])

func _skip_buttons() -> void:
	for act in ["confirm", "back", "aux", "aux2"]:
		_first_round()
		_steps(40)
		screen.on_action("kb1", act)
		_steps(1)
		check(screen.phase == "fight", act + " skips the entry after tick 30")

func _ignored_skips() -> void:
	for case in [["lb", "an assist press"], ["rb", "a dash press"], ["left", "a direction"], ["start", "start (it pauses)"]]:
		_first_round()
		_steps(40)
		var was_paused: bool = screen.paused
		screen.on_action("kb1", case[0])
		if screen.paused != was_paused:
			screen.set_paused(false)
		_steps(1)
		check(screen.phase == "intro" and screen.phase_t == 41, "%s does not skip" % case[1])
	_first_round()
	_steps(40)
	screen.on_action("kb3", "confirm")
	_steps(1)
	check(screen.phase == "intro", "a device that belongs to neither player does not skip")
	screen.f1.human = false
	screen.f2.human = false
	screen.on_action("kb1", "confirm")
	_steps(1)
	check(screen.phase == "intro", "with both fighters on the CPU nobody can skip")
	_steps(FULL)

# ── rounds 2 and 3, a restart and training ───────────────────────────────────
func _later_rounds() -> void:
	var voices := _voices(screen.f1).size() + _voices(screen.f2).size()
	# round 2 after a finished round: the 120 tick wide block
	_first_round()
	_steps(FULL)
	screen.wins = [1, 0]
	screen._next_round_or_finish()
	check(screen.round_no == 2 and screen.get("intro_len") == ROUND, "round 2 plays the 120 tick wide block (%s)" % str(screen.get("intro_len")))
	check(screen.f1.position.x == -230.0 and screen.f2.position.x == 230.0 and screen.intro_cut == -1 and screen.intro_cover == 0.0, "round 2 starts on the marks with no shots")
	check(screen.round_intro_at == 0, "round 2: the ROUND band is asked for at the start")
	var plain := true
	for t in range(1, ROUND):
		screen._sim_step()
		screen.f1.view.step(1.0 / 60.0)
		var want: Array = ["idle", t] if t < READY_AT_2 else (["intro", t - READY_AT_2] if t - READY_AT_2 < 60 else ["intro_idle", t])
		plain = plain and screen.cam_zoom == 1.0 and screen.cam_x == 0.0 and _lift() == 0.0 and screen.f1.intro_step() == want
		plain = plain and screen.f1.view.sd_actor.anim_name == want[0] and screen.f1.view.sd_actor.view_scale == 1.0 and screen.f1.visible and screen.f2.visible
	check(plain, "round 2: wide camera, the idle then the ready beat from tick 32 then the settling idle, both drawn, on every tick")
	check(screen.phase == "intro", "round 2: tick 119 is still the intro")
	_steps(1)
	check(screen.phase == "fight" and screen.f1.position.x == -230.0 and screen.f2.position.x == 230.0, "round 2: control on tick 120, nobody moved")
	# the FIGHT! call of round 2 comes on tick 96, once
	screen.wins = [1, 0]
	screen.round_no = 1
	_first_round()
	_steps(FULL)
	var before := _played("fight")
	screen.wins = [1, 0]
	screen._next_round_or_finish()
	_steps(ROUND - 24 - 1)
	check(_played("fight") == before, "round 2: no FIGHT! before tick 96")
	_steps(1)
	check(_played("fight") == before + 1, "round 2: FIGHT! on tick 96")
	_steps(24)
	check(screen.phase == "fight" and _played("fight") == before + 1, "round 2: control on tick 120, still one FIGHT!")
	# a restart keeps the 60 tick intro and calls FIGHT! once, at its end
	_first_round()
	_steps(FULL)
	screen.round_no = 1
	screen.restart_round()
	check(screen.get("intro_len") == 60, "a restart plays the 60 tick intro (%s)" % str(screen.get("intro_len")))
	check(screen.f1.position.x == -230.0 and screen.f2.position.x == 230.0 and screen.intro_cut == -1 and screen.intro_cover == 0.0, "a restart starts on the marks with no shots")
	var f2s := _played("fight")
	plain = true
	for t in range(1, 60):
		screen._sim_step()
		screen.f1.view.step(1.0 / 60.0)
		plain = plain and screen.cam_zoom == 1.0 and screen.cam_x == 0.0 and _lift() == 0.0 and screen.f1.intro_step() == ["intro", t]
		plain = plain and screen.f1.view.sd_actor.anim_name == "intro" and screen.f1.view.sd_actor.view_scale == 1.0
	check(plain, "a restart: wide camera and the ready beat on every tick")
	check(screen.phase == "intro" and _played("fight") == f2s, "a restart: tick 59 is still the intro, no FIGHT! yet")
	_steps(1)
	check(screen.phase == "fight" and _played("fight") == f2s + 1, "a restart: FIGHT! on tick 60, once")
	check(_voices(screen.f1).size() + _voices(screen.f2).size() == voices + 3 * 2, "round 2 and the restart fire no voice hooks (three entries played here, two voices each)")
	_first_round()
	_steps(50)
	check(screen.phase == "intro" and screen.cam_zoom > 1.0 and not screen.f2.visible, "a restart mid-shot: setup is a close shot with P2 hidden")
	screen.restart_round()
	_steps(1)
	check(screen.cam_zoom == 1.0 and screen.get("intro_len") == 60 and screen.f1.visible and screen.f2.visible, "restart out of a close shot: wide at once, both drawn, and the 60 tick intro")
	screen.round_no = 1
	screen.wins = [0, 0]

## What the HUD builds against: the ROUND band asked for at the wide block or on a skip, the cover ramp, the focus point.
func _hud_contract() -> void:
	_first_round()
	check(screen.round_intro_at == -1, "entry: no ROUND band at the start of the round")
	_steps(48)
	check(screen.intro_cut == 0 and absf(screen.intro_focus.x - (640.0 - 40.0 * screen.cam_zoom)) < 1.0 and screen.intro_focus.y == 380.0, "P1's shot: the focus is 40 px of lead left of the centre at face y 380 (%s)" % str(screen.intro_focus))
	_steps(SHOT - 48 + 10)
	check(screen.intro_cut == -1 and screen.intro_pan > 0.0 and screen.intro_focus == Vector2.ZERO, "the pan: no shot, a pan progress, no focus (%.3f)" % screen.intro_pan)
	_steps(PAN - 10 + 48)
	check(screen.intro_cut == 1 and absf(screen.intro_focus.x - (640.0 + 40.0 * screen.cam_zoom)) < 1.0 and screen.intro_focus.y == 380.0, "P2's shot: the focus is right of the centre at y 380 (%s)" % str(screen.intro_focus))
	_steps(WIDE - 1 - screen.phase_t)
	check(screen.phase_t == WIDE - 1 and screen.round_intro_at == -1 and screen.intro_cover == 1.0, "tick 228: still no ROUND band, the cover is full")
	_steps(1)
	check(screen.phase_t == WIDE and screen.round_intro_at == WIDE, "the ROUND band is asked for on tick 229, the first of the wide block (%d)" % screen.round_intro_at)
	check(screen.intro_cut == -1 and screen.intro_focus == Vector2.ZERO and screen.intro_cover == 1.0, "tick 229: no shot, no focus, the cover has not started to fall")
	_steps(4)
	check(absf(screen.intro_cover - 0.5) < 0.001, "tick 233: the cover is half down (%.3f)" % screen.intro_cover)
	_steps(4)
	check(screen.intro_cover == 0.0, "tick 237: the cover is gone (%.3f)" % screen.intro_cover)
	_steps(FULL - screen.phase_t)
	check(screen.phase == "fight" and screen.intro_cover == 0.0 and screen.round_intro_at == WIDE, "control: the ROUND band was asked for once, at tick 229")
	for at in [31, 100, 250]:
		_first_round()
		_steps(at)
		screen.on_action("kb1", "confirm")
		_steps(1)
		check(screen.phase == "fight" and screen.round_intro_at >= 0 and screen.intro_cover == 0.0 and screen.intro_focus == Vector2.ZERO, "a skip at tick %d asks for the ROUND band when it ends the intro and drops the cover and focus (%d)" % [at, screen.round_intro_at])
	_first_round()
	check(screen.f1.assist_cd == int(screen.f1.stats["assist_cd"]) and screen.f1.assist_hold and screen.f2.assist_hold, "the round opens with the full support cooldown, held until FIGHT! is called (%d)" % screen.f1.assist_cd)
	screen.hud._entered = false
	check(not screen.hud._entered, "setup: the HUD has not started its entrance")
	_steps(WIDE - 1)
	check(not screen.hud._entered, "through the shots and the pan the HUD has not been told to start its entrance")
	_steps(1)
	check(screen.hud._entered, "on tick 229 FightScreen really calls hud.round_intro")
	screen.wins = [1, 0]
	screen._next_round_or_finish()
	check(screen.round_intro_at == 0 and screen.intro_cover == 0.0, "round 2: the ROUND band is asked for at the start, as before")
	screen.round_no = 1
	screen.wins = [0, 0]
	_first_round()
	_steps(70)
	check(screen.intro_pan > 0.0 or screen.intro_cut >= 0, "setup: a fresh entry is in a shot or the pan mid-way")
	screen.entry = false
	check(screen.intro_focus == Vector2.ZERO and screen.intro_cover == 0.0 and screen.intro_pan == -1.0 and screen.intro_cut == -1, "no entry, no focus, no cover, no pan")
	screen.entry = true

## Edge cases: FIGHT! across a pause, a restart after round 2, and the floor reflection of a hidden fighter.
func _review_cases() -> void:
	_first_round()
	_steps(FIGHT_AT - 1)
	var before := _played("fight")
	screen.set_paused(true)
	_steps(30)
	check(_played("fight") == before and screen.phase_t == FIGHT_AT - 1, "paused one tick before FIGHT!: nothing plays and the clock holds")
	screen.set_paused(false)
	_steps(1)
	check(_played("fight") == before + 1 and screen.phase_t == FIGHT_AT, "unpaused: FIGHT! plays on tick 336, once")
	_first_round()
	_steps(FULL)
	screen.wins = [1, 0]
	screen._next_round_or_finish()
	check(screen.get("intro_len") == ROUND, "setup: round 2 plays the 120 tick block")
	screen.restart_round()
	check(screen.get("intro_len") == 60, "a restart in round 2 plays the 60 tick intro, not round 2's 120 (%s)" % str(screen.get("intro_len")))
	screen.round_no = 1
	screen.wins = [0, 0]
	_first_round()
	_steps(50)
	var lines: Node = null
	for c in screen.stage_node.get_children():
		if c.get("_refl") != null:
			lines = c
	check(lines != null or screen.bg_layer.get_meta("fx").view != null, "setup: the stage has its floor lines node, or is a 3D arena without one")
	if lines != null:
		lines._process(0.0)
		for i in 2:
			var f: Node = screen.fighters[i]
			check(f.visible or not lines._refl[i].visible, "slot %d is hidden in the other's shot: so is its floor reflection" % f.slot)

## The camera must not stay latched on a shot: with the fighters apart the live camera zooms out after control.
func _camera_after_the_entry() -> void:
	_first_round()
	_steps(FULL)
	screen.f1.position.x = -520.0
	screen.f2.position.x = 520.0
	_steps(90)
	check(screen.phase == "fight" and screen.cam_zoom < 0.9, "after control the live camera follows the fighters, not the last shot (zoom %.3f)" % screen.cam_zoom)
	# at full separation the arena is narrower than the screen: the camera centres instead of fighting an inverted clamp
	screen.f1.position.x = -600.0
	screen.f2.position.x = 600.0
	_steps(120)
	check(screen.cam_zoom < 0.71 and absf(screen.cam_x) < 1.0, "fighters 1200 px apart: the camera sits at the centre (zoom %.3f, x %.2f)" % [screen.cam_zoom, screen.cam_x])
	# a restart carries neither the shake nor the lift of the round it replaces
	screen._shake = 6.0
	screen.bg_layer.set_meta("lift", 30.0)
	screen.restart_round()
	check(screen._shake == 0.0 and _lift() == 0.0, "a restart clears the camera shake and the background lift (%.2f, %.2f)" % [screen._shake, _lift()])

func _flag_off() -> void:
	dbg.set("intro_entry", false)
	_first_round()
	check(screen.get("intro_len") == 60 and screen.f1.position.x == -230.0, "with the flag off a first round keeps the 60 tick intro")
	_steps(10)
	check(screen.intro_cut == -1 and screen.cam_zoom == 1.0 and screen.f1.visible and screen.f2.visible, "and no shots")
	dbg.set("intro_entry", true)

func _training() -> void:
	check(screen.training and screen.get("intro_len") == 60, "training never plays the entry (%s)" % str(screen.get("intro_len")))
	check(screen.f1.position.x == -230.0 and screen.f2.position.x == 230.0, "training starts on the marks")
	var voices := _voices(screen.f1).size() + _voices(screen.f2).size()
	_steps(59)
	check(screen.intro_cut == -1 and screen.cam_zoom == 1.0, "training: no shots, wide camera")
	_steps(1)
	check(screen.phase == "fight" and _voices(screen.f1).size() + _voices(screen.f2).size() == voices, "training: control on tick 60, no voice hooks")
	screen.wins = [1, 0]
	screen._next_round_or_finish()
	check(screen.get("intro_len") == 60, "a K.O. in training starts the next round with the 60 tick intro, not 120 (%s)" % str(screen.get("intro_len")))
	screen.wins = [0, 0]
