extends Screen
## The fight itself. Entered from the VS splash with Game.go("fight", {}, "slam").
## Owns: the stage + camera, two Fighters, projectiles, effects, the round state machine
## (intro → fight → ko → round_end → next round or result), assists, the training dummy and pause.
## Simulation is fixed-step (_physics_process, 60 Hz) so it is deterministic for a given input stream.
##
## Rules: best of 3 rounds, 60 s timer, 100-point meter (skill + EX: super, 50; EX alone at 100: the ult), assist every ~10 s.
## Modes (Game.session.mode): versus2p · versus-cpu · arcade (CPU ladder) · training (infinite, dummy).

const HudScript := preload("res://scripts/fight/fight_hud.gd")
const BACKDROP_SHADER := preload("res://shaders/backdrop.gdshader")

## ── EX ult freeze ("super freeze") ──────────────────────────────────────────
## Pressing EX alone at a full meter starts the EX move (Fighter._start_move → begin_cutin). At the end of that sim tick the
## WHOLE world stops: no fighter / projectile / assist-event / kit tick, no timer, no CPU thinking, no hit-stop countdown,
## and every world node (stage, floor, fighters + their views, projectiles, effects, particles, kit nodes) has its
## processing disabled, so nothing moves, spawns, animates or plays a sound. Only the HUD cut-in runs, on the SIM clock
## (freeze_t), so the overlay and the freeze cannot drift apart and pausing holds both. After FREEZE_FRAMES the world
## resumes exactly where it stopped (same frame, same positions, the EX move continues from its first frame).
## Two EX on the same tick are queued: the second cut-in plays right after the first, the world stays frozen between.
const FREEZE_FRAMES := 72          # one cut-in = 1.2 s of frozen world
const STAMP_FRAME := 20            # the EX skill name lands (impact sound + small camera kick)
const FOCUS_FRAMES := 40           # after the freeze the camera favours the caster this long
const RELEASE_FRAMES := 27         # post-freeze release flash / shockwave (visual only, counted in sim ticks)
const CUT_FADE_AFTER := 30         # the cut-in clip fades out this many ticks (0.5 s) after the world resumes
const VEIL_OUT_FRAMES := 14        # the veil lifts over this many ticks after the resume (the caster stays on top until then)
const FREEZE_Z := 75               # caster drawn above the freeze veil (z 70) and the aura (z 72), below the HUD (z 100)
const SKIP_AFTER := 30             # stage entry: an attack press skips it once this many ticks have passed
const VOICE_AT := 2                # stage entry: a fighter's line starts this many ticks into its solo shot
const COVER_RAMP := 8              # ticks the HUD cover takes to fall to 0 at the start of the wide block
const VOICE_MAX_S := 1.8           # only Battle_In_2 fits (Hina 1.05 s, Hoshino 1.77 s); In_1 runs past its shot
## The stage entry's solo shot (Arena.INTRO_SHOT ticks each, P1 then P2, a pan of Arena.INTRO_PAN ticks between). Zoom eases z0 to z1
## in P1's shot and zb to z1 in P2's (the pan lands on zb); cam_x sits `lead` px past the fighter toward the foe; the lift holds the
## face at screen y face_y, face_up being the face's height above the feet in the intro_cut pose. Every zoom stays inside one
## quarter step of the SD viewport scale (1.5 and 1.75), so nothing reallocates the viewports inside the entry.
const ENTRY_SHOT := {"z0": 1.52, "z1": 1.70, "zb": 1.52, "lead": 40.0, "face_y": 380.0, "face_up": 177.0}

var debug_boxes := false:
	set(v):
		debug_boxes = v
		for f in fighters:        # a paused world does not redraw itself
			f.view.back.queue_redraw()
		for p in projectiles:
			if is_instance_valid(p):
				p.queue_redraw()

var world_root: Node2D
var bg_layer: Control
var stage_node: Node2D
var fighters_layer: Node2D
var proj_layer: Node2D
var fx_layer: Node2D
var hud: Control

var f1: Fighter
var f2: Fighter
var fighters: Array = []
var projectiles: Array = []
var brains: Array = [null, null]
var rng := RandomNumberGenerator.new()

var phase := "intro"
var phase_t := 0
var intro_len := Arena.INTRO_READY   # ticks of this round's intro: the stage entry's 360 on a match's first round, 120 on a later round, else the 60 tick ready beat
var entry := false                   # this round's intro is the stage entry: two solo shots and a pan, then the wide block
var _entered := false                # the entry has been decided for this match (it plays once)
var _skip := false                   # an attack press asked to skip the entry; the next intro tick ends it
var _cut_cam := false                # the camera last showed a shot, so the next update that is not one cuts back to wide
var _after_round := false            # the next _start_round follows a finished round (it gets the 120 tick wide block)
var _fight_called := false           # FIGHT! has been shown this intro (a skip shows it when it ends the intro)
## What the HUD reads. intro_cut is 0 in P1's solo shot, 1 in P2's and -1 otherwise (the pan included); intro_cut_t is the ticks since
## that shot began (0 on its first); intro_side is the same as intro_cut; intro_pan runs 0 to 1 over the pan and is -1 otherwise;
## intro_cover is 1 until the wide block and ramps to 0 over COVER_RAMP ticks from it (rails and cards stay hidden while it is above 0).
var intro_cut: int:
	get:
		if not entry or phase != "intro":
			return -1
		var t := maxi(phase_t, 1)
		if t <= Arena.INTRO_SHOT:
			return 0
		return 1 if t > Arena.INTRO_SHOT + Arena.INTRO_PAN and t < Arena.INTRO_WIDE_AT else -1
var intro_cut_t: int:
	get:
		var c := intro_cut
		return -1 if c < 0 else maxi(phase_t, 1) - 1 - c * (Arena.INTRO_SHOT + Arena.INTRO_PAN)
var intro_side: int:
	get: return intro_cut
var intro_pan: float:
	get:
		if not entry or phase != "intro" or phase_t <= Arena.INTRO_SHOT or phase_t > Arena.INTRO_SHOT + Arena.INTRO_PAN:
			return -1.0
		return float(phase_t - Arena.INTRO_SHOT) / float(Arena.INTRO_PAN)
var intro_cover: float:
	get:
		if entry and phase == "intro":
			return clampf(1.0 - float(phase_t - Arena.INTRO_WIDE_AT) / float(COVER_RAMP), 0.0, 1.0)
		return 0.0
## Where the HUD may put plates: screen x of the solo shot's fighter (the feet column) and y of its face, or ZERO outside the shots.
var intro_focus: Vector2:
	get:
		var c := intro_cut
		if c < 0:
			return Vector2.ZERO
		var shot := _entry_shot()
		return Vector2(640.0 + ((fighters[c] as Fighter).position.x - float(shot[1])) * float(shot[0]), float(ENTRY_SHOT["face_y"]))
var round_intro_at := -1             # phase_t when this round's ROUND band was asked for (0: at the start), -1 until then
var round_no := 1
var wins := [0, 0]
var timer_frames := Arena.ROUND_SECONDS * 60
var time_stop := 0                 # sim frames left in the CURRENT cut-in; the world is frozen while > 0
var freeze_t := 0                  # sim frames since the current cut-in started
var freeze_caster: Fighter = null  # whose cut-in is playing (null = not frozen)
var release_t := -1                # sim frames since the world resumed (-1 = no release effect running)
var release_caster: Fighter = null
var world_frozen := false
var freeze_log: Array = []         # [{"frame", "slot", "event"}] for the harness / probe
var _freeze_queue: Array = []      # casters, first = playing; a same-tick second EX waits here
var _freeze_casters: Array = []    # everyone who triggered during this freeze (their buffers are flushed on resume)
var _freeze_pending := false       # an EX started during this tick: the freeze begins when the tick ends
var _freeze_presses := [{}, {}]    # buttons non-casting humans pressed during the freeze (re-buffered on resume)
var _focus_t := 0
var _focus_f: Fighter = null
var _punch := 0.0                  # camera zoom punch (decays every tick)
var _vis_frame := 0                # counts every unpaused tick (camera shake jitter keeps going in a freeze)
var _ult_test: RefCounted = null   # debug-only freeze proof logger (scripts/fight/tools/ult_probe.gd, env ULT_TEST)
var slowmo := 0
var paused := false
var training := false
var mode := "versus2p"
var cam_x := 0.0
var cam_zoom := 1.0
var _shake := 0.0
var _events: Array = []
var _frame := 0
var _last_shot := {}               # slot -> _frame of that fighter's last synthesised shot sound
var _cut_fade := -1                # ticks since a cut-in with a sound set resumed; the clip fades at CUT_FADE_AFTER (-1: none pending)
var dummy_mode := "stand"
var infinite_meter := false
var match_over := false
var _stats := {}
var _round_stats: Array = []       # each fighter's [damage, combo, hits] when this round began; Restart Round goes back to them
var _buzzer: Array = []            # both hp at TIME UP: the round is decided from these, whatever lands under the banner

func enter(p: Dictionary, _info: Dictionary) -> void:
	Input.joy_connection_changed.connect(_on_joy_connection)
	mode = Game.session.mode
	training = mode == "training"
	rng.seed = 424242 + int(Game.session.players[0]["fighter"]) * 31 + int(Game.session.players[1]["fighter"])
	_resolve_picks()
	_build_stage()
	_build_fighters()
	var ut := OS.get_environment("ULT_TEST")
	if OS.is_debug_build() and ut != "":
		_ult_test = load("res://scripts/fight/tools/ult_probe.gd").new()
		_ult_test.setup(ut)
	hud = HudScript.new()
	add_child(hud)
	hud.setup(self)
	_start_round()

# ── setup ────────────────────────────────────────────────────────────────────
func _setup_arcade() -> void:
	var sess: Session = Game.session
	var p1 := int(sess.players[0]["fighter"])
	if sess.arcade_ladder.is_empty():
		var ids: Array = []
		for f in Game.fighters:
			if int(f["id"]) != p1:
				ids.append(int(f["id"]))
		var r := RandomNumberGenerator.new()
		r.seed = 9001 + p1
		for i in range(ids.size() - 1, 0, -1):
			var j := r.randi_range(0, i)
			var tmp = ids[i]
			ids[i] = ids[j]
			ids[j] = tmp
		sess.arcade_ladder = ids.slice(0, 5)
	var idx := clampi(sess.arcade_stage, 0, sess.arcade_ladder.size() - 1)
	sess.players[1]["fighter"] = int(sess.arcade_ladder[idx])
	sess.players[1]["special"] = -1
	if idx > 0:
		sess.stage = Stages.LIST[(idx * 3 + p1) % Stages.LIST.size()]

func _resolve_picks() -> void:
	if Game.session.mode == "arcade" and typeof(Game.session.players[0]["fighter"]) in [TYPE_INT, TYPE_FLOAT]:
		_setup_arcade()
	for i in 2:
		var pl: Dictionary = Game.session.players[i]
		var fid = pl["fighter"]
		if typeof(fid) == TYPE_FLOAT:
			fid = int(fid)
			pl["fighter"] = fid
		if typeof(fid) != TYPE_INT or fid < 0 or not Game.by_id.has(fid):
			var pick: Dictionary = Game.fighters[rng.randi_range(0, Game.fighters.size() - 1)]
			pl["fighter"] = int(pick["id"])
		var sp = pl["special"]
		if typeof(sp) == TYPE_FLOAT:
			sp = int(sp)
			pl["special"] = sp
		if typeof(sp) != TYPE_INT or sp < 0 or not Game.by_id.has(sp):
			var pick2: Dictionary = Game.specials[rng.randi_range(0, Game.specials.size() - 1)]
			pl["special"] = int(pick2["id"])
	if Game.session.stage.is_empty():
		Game.session.stage = Stages.LIST[rng.randi_range(0, Stages.LIST.size() - 1)]

func _build_stage() -> void:
	bg_layer = Control.new()
	bg_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_layer.z_index = -20
	add_child(bg_layer)
	# plate + grade + particles live in StageFx (scripts/fight/stage_fx.gd); colours sampled from the plate tint the floor
	var fx: Control = load("res://scripts/fight/stage_fx.gd").new()
	bg_layer.add_child(fx)
	fx.build(Game.session.stage)
	bg_layer.set_meta("fx", fx)
	bg_layer.set_meta("colors", fx.colors)

	world_root = Node2D.new()
	world_root.name = "World"
	add_child(world_root)
	stage_node = _make_floor()
	world_root.add_child(stage_node)
	fighters_layer = Node2D.new()
	world_root.add_child(fighters_layer)
	proj_layer = Node2D.new()
	proj_layer.z_index = 10
	world_root.add_child(proj_layer)
	fx_layer = Node2D.new()
	fx_layer.z_index = 20
	world_root.add_child(fx_layer)

func _make_floor() -> Node2D:
	var fx: Control = bg_layer.get_meta("fx")
	return fx.make_floor(self, bg_layer.get_meta("colors"))

func _build_fighters() -> void:
	var picks: Array = []
	for i in 2:
		var pl: Dictionary = Game.session.players[i]
		var entry: Dictionary = Game.by_id[int(pl["fighter"])]
		var assist_entry: Dictionary = Game.by_id.get(int(pl["special"]), {})
		var f := Fighter.new()
		fighters_layer.add_child(f)
		f.world = self
		f.setup(entry, i + 1, assist_entry)
		picks.append(f)
	f1 = picks[0]
	f2 = picks[1]
	f1.foe = f2
	f2.foe = f1
	fighters = [f1, f2]
	# who is human?
	f1.human = true
	f2.human = Game.session.mode == "versus2p"
	if not f2.human:
		var lvl := 1
		if mode == "arcade":
			lvl = clampi(Game.session.arcade_stage / 2 + 1, 1, 3)
		var b := CpuBrain.new()
		b.setup(f2, f1, lvl, 7001 + int(f2.data["id"]))
		brains[1] = b
	if training:
		f2.human = false
	if Dbg.cpu_vs_cpu:
		f1.human = false
		f2.human = false
		var b1 := CpuBrain.new()
		b1.setup(f1, f2, 2, 3001 + int(f1.data["id"]))
		brains[0] = b1
		if brains[1] == null:
			var b2 := CpuBrain.new()
			b2.setup(f2, f1, 2, 7001 + int(f2.data["id"]))
			brains[1] = b2

func _start_round() -> void:
	Sfx.stop_all()
	phase = "intro"
	phase_t = 0
	timer_frames = Arena.ROUND_SECONDS * 60
	_clear_freeze()
	slowmo = 0
	for p in projectiles:
		if is_instance_valid(p):
			p.queue_free()
	projectiles.clear()
	FxParticles.of(fx_layer)._ps.clear()     # the last round's winner sparkles must not hang in the new round
	_events.clear()
	_buzzer.clear()
	_round_stats = fighters.map(func(f: Fighter) -> Array: return [f.stat_damage_dealt, f.stat_max_combo, f.stat_hits])
	entry = not training and not _entered and Dbg.intro_entry
	_entered = true
	_skip = false
	_fight_called = false
	intro_len = Arena.INTRO_FULL if entry else (Arena.INTRO_ROUND if _after_round else Arena.INTRO_READY)
	_after_round = false
	f1.reset_round(-Arena.START_X, 1)
	f2.reset_round(Arena.START_X, -1)
	f1.entry_cuts = entry
	f2.entry_cuts = entry
	for f in fighters:
		f.ready_at = intro_len - Arena.INTRO_BEAT_END - Arena.INTRO_READY if intro_len > Arena.INTRO_READY else 0
	# the support cooldown opens full and holds through the intro; it starts counting down when FIGHT! is called (training keeps a 1 s lock)
	for f in fighters:
		f.assist_cd = 60 if training else int(f.stats["assist_cd"])
		f.assist_hold = true
	if training:
		f1.meter = 100.0
		f2.meter = 100.0
	if _ult_test != null:
		_ult_test.round_start(self)
	for f in fighters:
		f.dim = 1.0
	cam_x = 0.0
	cam_zoom = 1.0
	_shake = 0.0     # a restart out of a K.O. must not carry its shake or its airborne lift into the ready beat
	bg_layer.set_meta("lift", 0.0)
	_apply_camera()
	round_intro_at = -1
	if not entry:
		_call_round_intro()
	Sfx.play("whoosh", 0.9, 0.6)

# ── fixed-step simulation ────────────────────────────────────────────────────
func _physics_process(_delta: float) -> void:
	var n := Dbg.sim_mult if Dbg.sim_mult > 1 else 1   # test harness can run many sim ticks per physics frame
	for i in n:
		_sim_step()
		if _ult_test != null:
			_ult_test.tick(self)

func _sim_step() -> void:
	if paused or Game.busy or match_over:
		return
	_vis_frame += 1
	# EX freeze gate FIRST: nothing below (events, slow-mo, fighters, projectiles, timer, CPU) runs while frozen
	if time_stop > 0:
		_tick_freeze()
		_update_visual_only()
		return
	_frame += 1
	phase_t += 1
	if release_t >= 0:
		release_t += 1
		if release_t > RELEASE_FRAMES:
			release_t = -1
			release_caster = null
	if _cut_fade >= 0:
		_cut_fade += 1
		if _cut_fade == CUT_FADE_AFTER:
			_cut_fade = -1
			for o in fighters:
				if o.has_sounds():
					Sfx.stop_cut(o.slot, 0.5)
	if _focus_t > 0:
		_focus_t -= 1
	if slowmo > 0:
		slowmo -= 1
		if slowmo % 3 != 0:
			_update_visual_only()
			return
	_run_events()
	_tick_phase()
	if _freeze_pending:
		_enter_freeze()
	_update_visual_only()

func _tick_phase() -> void:
	match phase:
		"intro":
			_tick_intro()
		"fight":
			_tick_fight()
		"ko":
			_tick_fight(false)
			if phase_t > 110:
				_end_round()
		"round_end":
			_tick_fight(false)
			if phase_t > 150:
				_next_round_or_finish()

## The ROUND band and the HUD rails start here: at the start of a round, or at the wide beat of the stage entry.
func _call_round_intro() -> void:
	round_intro_at = phase_t
	hud.round_intro(round_no)

func _tick_intro() -> void:
	f1.tick()
	f2.tick()
	if entry and phase_t == Arena.INTRO_WIDE_AT:
		_call_round_intro()
	if entry:
		for i in 2:
			if phase_t == (Arena.INTRO_SHOT + Arena.INTRO_PAN) * i + 1 + VOICE_AT:
				(fighters[i] as Fighter).voice("intro", VOICE_MAX_S)
	if intro_len > Arena.INTRO_READY and phase_t == intro_len - Arena.INTRO_FIGHT_LEAD:
		_call_fight()
	if _skip or phase_t == intro_len:
		_end_intro()

## FIGHT! on the screen and in the ears: once per intro, 24 ticks before control in the entry and in rounds 2 and 3, at the end
## of the short intros and on a skip.
func _call_fight() -> void:
	if _fight_called:
		return
	_fight_called = true
	for f in fighters:
		f.assist_hold = false     # the support cooldown starts counting when FIGHT! is called
	hud.banner("FIGHT!", "", Color("ffd94a"), 0.9)
	Sfx.play("fight")

## The natural end and the skip: both fighters on their marks, IDLE, FIGHT!. A button held through the intro is a held
## button, not a new press, so it does not attack on the first fight tick.
func _end_intro() -> void:
	_skip = false
	if round_intro_at < 0:
		_call_round_intro()
	for f in fighters:
		f.position.x = -float(f.facing) * Arena.START_X
		f.vel.x = 0.0
		f.state = Fighter.S.IDLE
		f.visible = true
		if f.human:
			_release_presses(f)
	_call_fight()
	phase = "fight"
	phase_t = 0

## What a human's input is after the intro, a pause or a freeze: the buttons still held are held, not new presses.
func _release_presses(f: Fighter) -> void:
	var held := FightInput.read_human(f.slot, null)
	for b in FightInput.BUTTONS:
		held.pressed[b] = false
	f.input = held

func _gather_input() -> void:
	if f1.human:
		f1.input = FightInput.read_human(1, f1.input)
	elif brains[0]:
		f1.input = brains[0].think()
	if f2.human:
		f2.input = FightInput.read_human(2, f2.input)
	elif training:
		f2.input = _dummy_input()
	elif brains[1]:
		f2.input = brains[1].think()

func _dummy_input() -> FightInput:
	var fi: FightInput
	match dummy_mode:
		"crouch":
			fi = FightInput.from_held(f2.input, 0, 1, [])
		"jump":
			fi = FightInput.from_held(f2.input, 0, -1 if (_frame % 90) == 0 else 0, [])
		"guard":
			fi = FightInput.from_held(f2.input, 0, 0, [])
		"cpu":
			if brains[1] == null:
				var b := CpuBrain.new()
				b.setup(f2, f1, 1, 99)
				brains[1] = b
			return brains[1].think()
		_:
			fi = FightInput.from_held(f2.input, 0, 0, [])
	f2.guard_all = dummy_mode == "guard"
	return fi

func _tick_fight(live_input := true) -> void:
	if live_input:
		_gather_input()
	else:
		f1.input = FightInput.new()
		f2.input = FightInput.new()
	f1.tick()
	f2.tick()
	if _freeze_pending:
		# an EX started this tick (both fighters have had their tick, so a same-frame double EX is caught): the world
		# stops right here — hits, push, projectiles and the timer of this tick wait for the resume
		return
	_resolve_hits()
	_push_apart()
	_tick_projectiles()
	if live_input and phase == "fight":
		if not training:
			timer_frames -= 1
			if timer_frames <= 0 and f1.hp > 0.0 and f2.hp > 0.0:     # a lethal blow on the last tick is a K.O. when the loser lands
				_time_up()
		else:
			_training_upkeep()

func _resolve_hits() -> void:
	# Collect both fighters' connections BEFORE applying either, so simultaneous hits trade fairly.
	var connects: Array = []
	for att in fighters:
		var h: Dictionary = att.active_hit()
		if h.is_empty():
			continue
		var def: Fighter = att.foe
		var wr: Rect2 = att.melee_rect(h["rect"])
		if wr.intersects(def.hurtbox()):
			connects.append({"att": att, "def": def, "h": h, "from": att.position})
	for c in connects:
		(c["def"] as Fighter).receive_hit(c["att"], c["h"], c["from"], false)

func _push_apart() -> void:
	var a := f1
	var b := f2
	if a.carry_anim != "" or b.carry_anim != "":
		return
	var dx := b.position.x - a.position.x
	var gap := a.push_min()
	if absf(dx) < gap and a.pushes_foe():
		var push := (gap - absf(dx)) * 0.5
		var s := 1.0 if dx >= 0.0 else -1.0
		if dx == 0.0:
			s = -float(a.facing)
		a.position.x -= s * push
		b.position.x += s * push
		for f in fighters:
			f.position.x = clampf(f.position.x, -Arena.HALF_W, Arena.HALF_W)
		# the wall stopped one of them: the other gives way for what is left
		var rest := gap - absf(b.position.x - a.position.x)
		if rest > 0.001:
			if absf(a.position.x) >= Arena.HALF_W:
				b.position.x += s * rest
			else:
				a.position.x -= s * rest
			for f in fighters:
				f.position.x = clampf(f.position.x, -Arena.HALF_W, Arena.HALF_W)

func _tick_projectiles() -> void:
	var keep: Array = []
	var down := fighters.filter(func(f: Fighter) -> bool: return f.hp <= 0.0)     # judged before any round lands, so mutual hits still trade
	for p in projectiles:
		if not is_instance_valid(p):
			continue
		if p.owner_f in down:     # a fighter who is down fires no more rounds
			p.queue_free()
			continue
		p.tick()
		if p.dead:
			p.queue_free()
		else:
			keep.append(p)
	projectiles = keep
	# opposing bullets cancel each other (beams and blasts excepted)
	for i in projectiles.size():
		for j in range(i + 1, projectiles.size()):
			var a: Projectile = projectiles[i]
			var b: Projectile = projectiles[j]
			if a.dead or b.dead or a.owner_f == b.owner_f:
				continue
			if a.kind in ["beam", "blast", "flame", "shell"] or b.kind in ["beam", "blast", "flame", "shell"]:
				continue
			if a.rect().intersects(b.rect()):
				var mid := (a.position + b.position) * 0.5
				Fx.spark(fx_layer, mid, "light", 1, 0.3)
				a.dead = true
				b.dead = true
				a.queue_free()
				b.queue_free()

func _training_upkeep() -> void:
	if f2.hp < f2.max_hp and f2.combo_hits == 0 and f2.state in [Fighter.S.IDLE, Fighter.S.CROUCH, Fighter.S.WALK]:
		f2.hp = minf(f2.max_hp, f2.hp + 12.0)
	if f1.hp < f1.max_hp:
		f1.hp = minf(f1.max_hp, f1.hp + 12.0)
	if f2.hp <= 0.0:
		f2.hp = f2.max_hp

## Also runs on the ticks of an EX freeze, so infinite EX never reads 0 under the cut-in.
func _update_visual_only() -> void:
	if infinite_meter:
		f1.meter = 100.0
		f2.meter = 100.0
	_sort_fighters()
	_apply_camera()
	hud.refresh()

## P1 draws over P2 unless P2 is attacking and P1 is not, so a point-blank attacker's arms and gun stay in front.
## The EX caster keeps FREEZE_Z through the freeze and until the veil has lifted.
func _sort_fighters() -> void:
	if time_stop > 0 or (release_t >= 0 and release_t < VEIL_OUT_FRAMES):
		return
	var p2_front := f2.is_attacking() and not f1.is_attacking()
	f1.z_index = 3 if p2_front else 4
	f2.z_index = 4 if p2_front else 3

# ── world services used by fighters / projectiles ────────────────────────────
func spawn_projectile(owner_fighter: Fighter, spec: Dictionary) -> void:
	var p := Projectile.new()
	p.owner_f = owner_fighter
	p.target = owner_fighter.foe
	p.world = self
	p.facing = owner_fighter.facing
	var off: Vector2 = spec.get("offset_left", spec["offset"]) if owner_fighter.facing < 0 else spec["offset"]
	var fc := float(owner_fighter.facing)
	if spec["at_foe"]:
		p.position = Vector2(owner_fighter.foe.position.x + off.x * fc, Arena.GROUND + off.y)
	elif spec.get("rel_owner", false):
		p.position = Vector2(owner_fighter.position.x + off.x * fc, Arena.GROUND + off.y)
	else:
		p.position = owner_fighter.position + Vector2(off.x * fc, off.y)
	var v: Vector2 = spec["vel"]
	p.vel = Vector2(v.x * fc, v.y)
	p.gravity = spec["gravity"]
	p.life = spec["life"]
	p.size = spec["size"]
	p.kind = spec["kind"]
	p.hit = spec["hit"]
	p.color = spec["color"]
	p.explode = spec["explode"]
	# charge scaling (move["hold"]): {dmg, speed, size} extra fractions at full charge
	var ch: Dictionary = spec.get("charge", {})
	if not ch.is_empty():
		var hold: Dictionary = owner_fighter.move.get("hold", {})
		var cf := clampf(float(owner_fighter.charge_t) / float(maxi(1, int(hold.get("max", 1)))), 0.0, 1.0)
		p.hit = p.hit.duplicate()
		p.hit["dmg"] = float(p.hit["dmg"]) * (1.0 + cf * float(ch.get("dmg", 0.0)))
		p.vel *= 1.0 + cf * float(ch.get("speed", 0.0))
		p.size *= 1.0 + cf * float(ch.get("size", 0.0))
		p.life = int(float(p.life) * (1.0 + cf * float(ch.get("life", 0.0))))
	# the generic super: the powered skill's rounds carry its boost from the moment they leave the gun
	if owner_fighter.powered:
		if not p.hit.is_empty():
			p.hit = p.hit.duplicate()
			p.hit["dmg"] = float(p.hit["dmg"]) * Arena.SUPER_DMG
		if not p.explode.is_empty() and p.explode.has("hit"):
			p.explode = p.explode.duplicate()
			p.explode["hit"] = (p.explode["hit"] as Dictionary).duplicate()
			p.explode["hit"]["dmg"] = float(p.explode["hit"]["dmg"]) * Arena.SUPER_DMG
	# behaviours (look at relevant docs)
	p.homing = float(spec.get("homing", 0.0))
	p.boomerang = int(spec.get("boomerang", 0))
	p.bounces = int(spec.get("bounce", 0))
	p.follow = bool(spec.get("follow", false))
	p.follow_off = off
	p.muzzle_sweep = bool(spec.get("muzzle_sweep", false))
	p.mine = spec.get("mine", {})
	p.speed0 = p.vel.length()
	# a grenade launcher fired down is a coin flip: the grenade bounces once and explodes, or it is a dud
	# not fully functional. rocket launchers should hurt their own shooter when fired down; no kit has one yet.
	if p.kind == "grenade" and String(owner_fighter.data.get("weapon", "")) == "GL" and rad_to_deg(atan2(p.vel.y, absf(p.vel.x))) > Arena.LEVEL_DEG:
		if rng.randf() < 0.5:
			p.bounces = 1
		else:
			p.hit = {}
			p.explode = {}
	# SD fighters: the gameplay origin is the symmetric (measured) muzzle; the round is drawn from the gun's real
	# muzzle in this facing and eases onto its path, and the flash sits on the gun
	var flash := p.position
	if owner_fighter.view.sd_mode and not spec["at_foe"] and not spec.get("rel_owner", false) and not p.follow:
		flash = owner_fighter.view.shot_origin()
		p.draw_off = flash - p.position
		p.draw_along = true
	proj_layer.add_child(p)
	projectiles.append(p)
	match p.kind:
		"bullet", "pellet":
			Fx.make(fx_layer, "muzzle", flash, 0.09, {"dir": owner_fighter.facing, "color": p.color, "size": 0.8})
			if owner_fighter.has_sounds() and not spec.get("assist", false):
				owner_fighter.sfx("shot")
			elif _frame - int(_last_shot.get(owner_fighter.slot, -10)) >= 3:
				# fixes bug(fight): one fighter's stream muted the other's shot sounds, the throttle is per fighter now
				Sfx.play("shot", 1.0 + float(owner_fighter.slot) * 0.04, 0.5)
				_last_shot[owner_fighter.slot] = _frame
		"snipe":
			Fx.make(fx_layer, "muzzle", flash, 0.14, {"dir": owner_fighter.facing, "color": p.color, "size": 1.6})
			Sfx.play("shot_big")
			shake(5.0)
		"beam":
			Fx.make(fx_layer, "muzzle", flash, 0.16, {"dir": owner_fighter.facing, "color": p.color, "size": 1.8})
			Sfx.play("beam")
			shake(4.0)
		"grenade", "rocket":
			Sfx.play("launch")
		"shell":
			Sfx.play("whoosh", 1.4, 0.4)
		"flame":
			Sfx.play("flame", 1.0, 0.3)

func spawn_blast(owner_fighter: Fighter, pos: Vector2, radius: float, hit: Dictionary, color: Color) -> void:
	var p := Projectile.new()
	p.owner_f = owner_fighter
	p.target = owner_fighter.foe
	p.world = self
	p.kind = "blast"
	p.position = pos
	p.size = Vector2(radius * 2.0, radius * 2.0)
	p.life = 6
	p.hit = hit
	p.color = color
	proj_layer.add_child(p)
	projectiles.append(p)
	Fx.make(fx_layer, "boom", pos, 0.55, {"color": color, "size": radius / 100.0, "seed": rng.randf() * 3.0})
	Sfx.play("boom")
	shake(5.0)

func call_assist(f: Fighter) -> void:
	if not f.assist_ready():
		return
	f.assist_cd = int(f.stats["assist_cd"])
	f.assist_calls += 1
	var a: Dictionary = f.assist
	hud.assist_callout(f)
	Sfx.play("claim", 1.2, 0.7)
	var fc := float(f.facing)
	match a["kind"]:
		"guard":
			f.shield_frames = 300
			fx_ring_at(f.position + Vector2(0, -150), Color(0.5, 0.85, 1.0))
		"heal":
			f.heal_pool = f.max_hp * 0.14
			Fx.make(fx_layer, "heal", f.position, 1.2, {"seed": 1.0})
		"buff":
			f.buff_frames = 420
			fx_ring_at(f.position + Vector2(0, -150), Color(1.0, 0.85, 0.35))
		"strike":
			var hit := Movesets.H(Rect2(), 70.0, 24, 16, 6.0, {"meter": 6.0, "hitstop": 8, "spark": "heavy", "sfx": "hit_h", "launch": Vector2(6, -10), "kd": true, "shake": 4.0})
			_events.append({"t": 18, "owner": f, "f": func():
				var p := Projectile.new()
				p.owner_f = f
				p.target = f.foe
				p.world = self
				p.facing = f.facing
				p.kind = "strike"
				p.position = Vector2(f.position.x - fc * 640.0, Arena.GROUND - 50.0)
				p.vel = Vector2(fc * 17.0, 0)
				p.size = Vector2(190, 100)
				p.life = 120
				p.hit = hit
				p.color = a["color"]
				p.explode = {}
				proj_layer.add_child(p)
				projectiles.append(p)
				Sfx.play("whoosh", 0.7, 0.6)})
		_:  # volley
			for i in 5:
				_events.append({"t": 14 + i * 5, "owner": f, "f": func():
					var spec := Movesets._spawn(0, Vector2(-30, -170 + 22.0 * float(i % 3)), Vector2(20, 0), Movesets.H(Rect2(), 22.0, 14, 10, 3.0, {"meter": 2.0, "hitstop": 3}),
						{"size": Vector2(36, 10), "color": a["color"], "life": 80, "assist": true})
					spawn_projectile(f, spec)})

func fx_ring_at(pos: Vector2, color: Color) -> void:
	Fx.make(fx_layer, "ring", pos, 0.5, {"color": color, "size": 0.9})

func _run_events() -> void:
	if _events.is_empty():
		return
	var keep: Array = []
	for e in _events:
		e["t"] = int(e["t"]) - 1
		if int(e["t"]) <= 0:
			if (e["owner"] as Fighter).hp > 0.0:     # a fighter who is already down calls nothing in
				e["f"].call()
		else:
			keep.append(e)
	_events = keep

## Called by Fighter._start_move when a `cutin: true` move (the EX) starts. Only queues: the freeze begins when the
## current sim tick has finished (so the other fighter's tick of the same frame still happens → same-frame double EX).
func begin_cutin(f: Fighter) -> void:
	if f in _freeze_queue:
		return
	_freeze_queue.append(f)
	if not (f in _freeze_casters):
		_freeze_casters.append(f)
	_log_freeze(f.slot, "trigger")
	if time_stop <= 0:
		_freeze_pending = true

func _log_freeze(slot: int, ev: String) -> void:
	freeze_log.append({"frame": _frame, "vis": _vis_frame, "slot": slot, "event": ev})
	if freeze_log.size() > 48:
		freeze_log = freeze_log.slice(freeze_log.size() - 48)

## Timing shared with the HUD cut-in (seconds).
func freeze_consts() -> Dictionary:
	return {"freeze_s": float(FREEZE_FRAMES) / 60.0, "stamp_s": float(STAMP_FRAME) / 60.0,
		"veil_out_s": float(VEIL_OUT_FRAMES) / 60.0, "release_s": float(RELEASE_FRAMES) / 60.0}

func is_frozen() -> bool:
	return time_stop > 0

## Seconds into the current cut-in on the sim clock (+ the sub-tick fraction for smooth drawing). -1 when not frozen.
func freeze_age() -> float:
	if time_stop <= 0 or freeze_caster == null:
		return -1.0
	return (float(freeze_t) + _frac()) / 60.0

## Seconds since the world resumed after the last cut-in (release flash / shockwave). -1 when none.
func release_age() -> float:
	if release_t < 0:
		return -1.0
	return (float(release_t) + _frac()) / 60.0

func _frac() -> float:
	if paused or Game.busy:
		return 0.0
	return clampf(Engine.get_physics_interpolation_fraction(), 0.0, 0.999)

func _enter_freeze() -> void:
	_freeze_pending = false
	if _freeze_queue.is_empty():
		return
	_set_world_frozen(true)
	for c in _freeze_queue:
		_pose_caster(c)          # show the EX start pose now — the view is not processed again until the resume
	_freeze_presses = [{}, {}]
	_shake = 0.0                 # no leftover world shake: the camera move during the freeze is the cut-in's own
	release_t = -1
	release_caster = null
	_start_cutin(_freeze_queue[0])

func _start_cutin(f: Fighter) -> void:
	freeze_caster = f
	freeze_t = 0
	time_stop = FREEZE_FRAMES
	for o in fighters:
		(o as Fighter).z_index = FREEZE_Z if o == f else 5 - (o as Fighter).slot
	_punch = 0.1
	hud.cutin(f)
	if f.has_sounds():
		f.sfx("cutin")
		f.voice("ult")
	else:
		Sfx.play("super", 1.0, 0.9)
		Sfx.play("ult_rise", 1.0 if f.slot == 1 else 1.06, 0.8)
	_log_freeze(f.slot, "cutin")

func _tick_freeze() -> void:
	freeze_t += 1
	time_stop -= 1
	_record_freeze_input()
	if freeze_t == STAMP_FRAME:
		Sfx.play("ult_stamp", 1.0, 0.9)
		shake(3.0)
	if time_stop > 0:
		return
	_freeze_queue.pop_front()
	if not _freeze_queue.is_empty():
		_start_cutin(_freeze_queue[0])     # same-frame second EX: its cut-in follows, the world stays frozen
	else:
		_exit_freeze()

func _exit_freeze() -> void:
	var c := freeze_caster
	var n_casters := _freeze_casters.size()
	freeze_caster = null
	time_stop = 0
	freeze_t = 0
	_set_world_frozen(false)
	for o in fighters:
		(o as Fighter).z_index = FREEZE_Z if o == c else 5 - (o as Fighter).slot   # back to normal when the veil is gone
	_flush_inputs()
	for caster in _freeze_casters:
		if caster.has_sounds():
			_cut_fade = 0
	_freeze_casters.clear()
	release_t = 0
	release_caster = c
	_focus_t = FOCUS_FRAMES
	_focus_f = c if n_casters == 1 else null
	_punch = 0.06
	shake(7.0)
	Sfx.play("ult_release", 1.0, 0.9)
	Sfx.play("boom", 0.8, 0.5)
	_log_freeze(c.slot if c != null else 0, "resume")

## Round start / restart: drop any freeze (also used when the round is restarted from the pause menu mid-freeze).
func _clear_freeze() -> void:
	time_stop = 0
	freeze_t = 0
	freeze_caster = null
	release_t = -1
	release_caster = null
	_cut_fade = -1
	_freeze_queue.clear()
	_freeze_casters.clear()
	_freeze_pending = false
	_freeze_presses = [{}, {}]
	_focus_t = 0
	_focus_f = null
	_punch = 0.0
	if world_root != null:
		_set_world_frozen(false)
	for o in fighters:
		(o as Fighter).z_index = 5 - (o as Fighter).slot
	if hud != null:
		hud.cutin_stop()

## The world subtree stops processing (its _process: views / springs / ghosts, Fx, particles, projectile visuals, kit
## nodes, stage motes, floor reflections). The HUD and this screen keep running. Drawing stays as it was last drawn.
func _set_world_frozen(on: bool) -> void:
	world_frozen = on
	_world_process()

## The world also stands still under the pause menu, so a spark or a damage number does not expire behind it.
func _world_process() -> void:
	var pm: Node.ProcessMode = Node.PROCESS_MODE_DISABLED if world_frozen or paused else Node.PROCESS_MODE_INHERIT
	for n in [bg_layer, stage_node, fighters_layer, proj_layer, fx_layer]:
		if n != null and is_instance_valid(n):
			(n as Node).process_mode = pm

## Put the caster's visual into its EX start pose before its view is frozen. Sprite fighters show the first EX frame
## (SpriteMotion maps f.mf, which stays at the move's first frame for the whole freeze). Puppet fighters get their pose
## springs settled toward the EX start pose (no ghosts / particles are emitted by this).
func _pose_caster(f: Fighter) -> void:
	var v: Node = f.view
	if v == null or not is_instance_valid(v):
		return
	if v.get("sd_mode"):
		v.sd_actor.sync(f)       # an SD model poses straight from the sim; the springs do not move it
		return
	if v.has_method("_targets") and v.has_method("_integrate") and v.has_method("_apply"):
		var dt := 1.0 / 60.0
		for i in 14:
			v.call("_targets", dt)
			v.call("_integrate", dt)
			v.call("_apply", dt)
	elif v.has_method("step"):
		v.call("step", 0.0)

## Non-casting humans may press buttons during the freeze (e.g. to answer the ult): remember them for the resume.
func _record_freeze_input() -> void:
	for i in 2:
		var f: Fighter = fighters[i]
		if not f.human or f in _freeze_casters:
			continue
		var fi := FightInput.read_human(f.slot, f.input)
		var rec: Dictionary = _freeze_presses[i]
		for b in FightInput.BUTTONS:
			if fi.was_pressed(b):
				rec[b] = true
		f.input = fi

## Resume: casters' buffered / held presses must not leak into the ult (buffer flushed, held buttons are not new presses);
## the other human's presses made during the freeze are re-buffered so they are not lost.
func _flush_inputs() -> void:
	for i in 2:
		var f: Fighter = fighters[i]
		if f in _freeze_casters:
			f._buf.clear()
			f._age.clear()
			if f.human:
				_release_presses(f)
			else:
				for b in FightInput.BUTTONS:
					f.input.pressed[b] = false
		elif f.human:
			var rec: Dictionary = _freeze_presses[i]
			for b in rec:
				f._buf[b] = Fighter.BUFFER
	_freeze_presses = [{}, {}]

func fx_dust(pos: Vector2, n: int) -> void:
	for i in n:
		Fx.make(fx_layer, "dust", pos + Vector2(0, -4), 0.45, {"seed": float(i), "size": 1.0, "z": 4})

func fx_skid(pos: Vector2, heading: int) -> void:
	for i in 2:
		Fx.make(fx_layer, "dust", pos + Vector2(0, -4), 0.45, {"seed": float(i * 2), "size": 1.0, "spread": 0.8, "drift": float(heading), "z": 4})

func fx_afterimage(f: Fighter, _life: int) -> void:
	f.add_ghost()   # pooled warped-pose ghost sprites live in the fighter's view (no per-dash node churn)

func fx_cue(f: Fighter, kind: String) -> void:
	var muzzle: Vector2 = f.view.shot_origin() if f.view.sd_mode else f.position + Vector2(float(f.facing) * 80.0, -188.0)
	match kind:
		"sight":
			Fx.make(fx_layer, "sight", muzzle, 0.35, {"dir": f.facing})
		"charge":
			Fx.make(fx_layer, "charge", muzzle, 0.45, {"color": f.stats["color"]})
			Sfx.play("charge")

func fx_spark(pos: Vector2, kind: String, face: int) -> void:
	Fx.spark(fx_layer, pos, kind, face, rng.randf() * 3.0)

func fx_text(pos: Vector2, text: String, color: Color) -> void:
	Fx.make(fx_layer, "text", pos, 0.9, {"text": text, "color": color, "fsize": 40, "z": 42})

func fx_heal(f: Fighter) -> void:
	Fx.make(fx_layer, "heal", f.position, 1.1, {"seed": float(_frame) * 0.1})
	if f.has_sounds():
		f.sfx("heal_tick")
	else:
		Sfx.play("claim", 1.5, 0.4)

func fx_damage(pos: Vector2, dmg: float, big: bool) -> void:
	var fsize := 44 if big else 32
	var lift := 40.0 + fsize * 1.2     # the number's own rise plus most of its height, so a risen one and the next do not touch
	var low := false      # a rapid combo alternates two rows: a number still on screen at the spawn row sends the next one up
	var high := false
	for n in fx_layer.get_children():
		if n is Fx and n.data.get("digits", false) and n.age < 0.6:
			if n.position.y > pos.y - lift * 0.5:
				low = true
			else:
				high = true
	if low and not high:
		pos.y -= lift
	Fx.make(fx_layer, "text", pos, 0.7, {"text": str(int(round(dmg))), "color": Color(1, 0.95, 0.6) if big else Color.WHITE, "fsize": fsize, "z": 40, "digits": true})

func shake(amount: float) -> void:
	_shake = maxf(_shake, FxFlash.shake(amount))

func on_hit(att: Fighter, def: Fighter, h: Dictionary, combo: int) -> void:
	hud.on_combo(att, def, combo, h)
	if h.get("spark", "") == "ex":
		hud.flash(Color(1, 1, 1), 0.5)

func on_ko(def: Fighter) -> void:
	if phase != "fight":
		return
	phase = "ko"
	phase_t = 0
	slowmo = 100
	hud.banner("K.O.", "", Color("ff4a5c"), 1.6)
	var ink := Fx.make(fx_layer, "impact", def.position + Vector2(0, -150), 0.05, {"z": 70, "seed": rng.randf() * 3.0})
	if not ink.visible:     # the white flash would grey the ink field; it stays for a refused impact frame
		hud.flash(Color(1, 1, 1), 0.8)
	Sfx.play("ko")
	def.voice("ko")
	shake(10.0)

func _time_up() -> void:
	_buzzer = [f1.hp, f2.hp]
	for f in fighters:
		f._buf.clear()
		f._age.clear()
	phase = "ko"
	phase_t = 0
	hud.banner("TIME UP", "", Color("ffd94a"), 1.4)
	Sfx.play("ko", 1.4, 0.6)

func _end_round() -> void:
	var hp1 := f1.hp if _buzzer.is_empty() else float(_buzzer[0])
	var hp2 := f2.hp if _buzzer.is_empty() else float(_buzzer[1])
	var winner := 0
	if hp1 <= 0.0 and hp2 <= 0.0:
		winner = 0
	elif hp2 <= 0.0:
		winner = 1
	elif hp1 <= 0.0:
		winner = 2
	else:
		var a := hp1 / f1.max_hp
		var b := hp2 / f2.max_hp
		winner = 0 if is_equal_approx(a, b) else (1 if a > b else 2)
	phase = "round_end"
	phase_t = 0
	if winner > 0:
		wins[winner - 1] += 1
		var w: Fighter = fighters[winner - 1]
		w.start_win()
		hud.banner("%s WINS" % Fighters.display_name(w.data).to_upper(), "ROUND %d" % round_no, Color("ffffff"), 2.0)
		Sfx.play("claim", 0.8)
		if wins[winner - 1] >= 2:
			w.voice("victory")
	else:
		hud.banner("DRAW", "", Color("ffffff"), 1.6)
	hud.refresh()
	_stats["last_winner"] = winner

func _next_round_or_finish() -> void:
	if wins[0] >= 2 or wins[1] >= 2:
		_finish_match()
	else:
		round_no += 1
		_after_round = not training     # training keeps its 60 tick ready beat after a K.O.
		_start_round()

func _finish_match() -> void:
	if match_over:
		return
	match_over = true
	var winner := 1 if wins[0] > wins[1] else 2
	var wf: Fighter = fighters[winner - 1]
	var lf: Fighter = fighters[2 - winner]
	Records.add_match(mode, int(wf.data["id"]), int(lf.data["id"]), not Dbg.cpu_vs_cpu and (winner == 1 or mode == "versus2p"), {"combo": wf.stat_max_combo, "damage": wf.stat_damage_dealt})
	if mode == "arcade" and winner == 1 and Game.session.arcade_stage + 1 >= Game.session.arcade_ladder.size():
		Records.add_arcade_clear()
	Game.go("result", {
		"winner": winner,
		"wins": wins.duplicate(),
		"rounds": round_no,
		"stats": [
			{"damage": f1.stat_damage_dealt, "combo": f1.stat_max_combo, "hits": f1.stat_hits},
			{"damage": f2.stat_damage_dealt, "combo": f2.stat_max_combo, "hits": f2.stat_hits},
		],
	}, "fade")

# ── camera ───────────────────────────────────────────────────────────────────
func _apply_camera() -> void:
	var intro := phase == "intro"
	var dist := 2.0 * Arena.START_X if intro else absf(f1.position.x - f2.position.x)
	var target_zoom := clampf(1280.0 / (dist + 640.0), 0.7, 1.0)
	var mid := 0.0 if intro else (f1.position.x + f2.position.x) * 0.5
	if time_stop > 0 and freeze_caster != null:
		# EX freeze: push in on the caster (cornered or mid-air included — the clamp + lift below keep her framed)
		target_zoom = minf(1.24, target_zoom * 1.18)
		mid = lerpf(mid, freeze_caster.position.x, 0.6)
	elif phase == "ko" and slowmo > 0:
		# KO push-in on the loser
		target_zoom = minf(1.1, target_zoom * 1.1)
		var loser: Fighter = f1 if f1.hp <= 0.0 else (f2 if f2.hp <= 0.0 else null)
		if loser != null:
			mid = lerpf(mid, loser.position.x, 0.55)
	elif _focus_t > 0 and _focus_f != null and is_instance_valid(_focus_f):
		# the first moments of the ult: the camera still favours the caster, easing back to the normal framing
		var fk := float(_focus_t) / float(FOCUS_FRAMES)
		target_zoom = minf(1.14, target_zoom * (1.0 + 0.1 * fk))
		mid = lerpf(mid, _focus_f.position.x, 0.5 * fk)
	# smooth zoom: pull out quickly when the fighters separate, push in gently. In an EX freeze the camera settles on
	# the caster within ~15 ticks and then holds still (mid-freeze frames are identical), apart from the stamp kick.
	var frozen := time_stop > 0
	cam_zoom = lerpf(cam_zoom, target_zoom, 0.25 if frozen else (0.14 if target_zoom < cam_zoom else 0.07))
	# tiny look-ahead in the direction the fighters are moving
	var look := 0.0 if frozen or intro else clampf((f1.vel.x + f2.vel.x) * 4.0, -36.0, 36.0)
	var limit := maxf(0.0, Arena.HALF_W + 150.0 - 640.0 / cam_zoom)     # below zoom 0.7033 the arena is narrower than the screen: centre
	cam_x = lerpf(cam_x, clampf(mid + look, -limit, limit), 0.25 if frozen else 0.14)
	# vertical lift while someone is airborne so heads stay in frame
	var lift_goal := clampf((Arena.GROUND - minf(f1.position.y, f2.position.y)) * 0.2, 0.0, 56.0)
	var lift: float = lerpf(float(bg_layer.get_meta("lift", 0.0)), lift_goal, 0.12)
	bg_layer.set_meta("lift", lift)
	# the stage entry's shots and pan are assigned, never lerped, and the first update after them (or a forced phase) cuts back to wide
	var shooting := entry and phase == "intro" and phase_t < Arena.INTRO_WIDE_AT
	if shooting or _cut_cam:
		_cut_cam = shooting
		var shot := _entry_shot()
		cam_zoom = shot[0]
		cam_x = shot[1]
		lift = shot[2]
		bg_layer.set_meta("lift", lift)
		var solo := intro_cut     # the foe is out of a locked shot, whose edge its gun and hair would poke into
		for i in 2:
			(fighters[i] as Fighter).visible = solo < 0 or solo == i
	_shake = maxf(0.0, _shake - 0.55)
	var sh := Vector2(sin(float(_vis_frame) * 2.3), cos(float(_vis_frame) * 1.9)) * _shake
	var ground_y := 612.0
	# EX zoom punch on top of the smoothed zoom (decays every tick)
	_punch = maxf(0.0, _punch * 0.86 - 0.002)
	var z := cam_zoom * (1.0 + _punch)
	var zx := cam_x
	if _punch > 0.0 and freeze_caster != null:
		zx = lerpf(cam_x, freeze_caster.position.x, clampf(_punch * 3.0, 0.0, 0.5))
	world_root.scale = Vector2(z, z)
	world_root.position = Vector2(640.0 - zx * z, ground_y - Arena.GROUND * z + lift * z) + sh
	# background parallax + floor uniforms
	var horizon_y := world_root.position.y + (Arena.GROUND - 24.0) * z
	var fx: Control = bg_layer.get_meta("fx")
	fx.update_camera(zx, z, sh, horizon_y)
	fx.set_floor_camera(stage_node.get_meta("floor_mat"), z, horizon_y)

## [zoom, cam_x, lift] on this tick of the entry: P1's shot, the pan, P2's shot, then the wide block ([1, 0, 0]). The shots ease by
## smoothstep, the pan by smootherstep.
func _entry_shot() -> Array:
	var t := maxi(phase_t, 1)
	if not entry or phase != "intro" or t >= Arena.INTRO_WIDE_AT:
		return [1.0, 0.0, 0.0]
	var k := ENTRY_SHOT
	var xa: float = f1.position.x + float(k["lead"]) * float(f1.facing)
	var xb: float = f2.position.x + float(k["lead"]) * float(f2.facing)
	var z: float
	var x: float
	if t <= Arena.INTRO_SHOT:
		z = lerpf(float(k["z0"]), float(k["z1"]), smoothstep(0.0, 1.0, float(t - 1) / float(Arena.INTRO_SHOT - 1)))
		x = xa
	elif t <= Arena.INTRO_SHOT + Arena.INTRO_PAN:
		var u := float(t - Arena.INTRO_SHOT) / float(Arena.INTRO_PAN)
		var e := u * u * u * (u * (u * 6.0 - 15.0) + 10.0)
		z = lerpf(float(k["z1"]), float(k["zb"]), e)
		x = lerpf(xa, xb, e)
	else:
		var u := float(t - Arena.INTRO_SHOT - Arena.INTRO_PAN - 1) / float(Arena.INTRO_SHOT - 1)
		z = lerpf(float(k["zb"]), float(k["z1"]), smoothstep(0.0, 1.0, u))
		x = xb
	return [z, x, float(k["face_up"]) - (612.0 - float(k["face_y"])) / z]

# ── input: pause + menu ──────────────────────────────────────────────────────
## A claimed pad that unplugs pauses the match. Session.device_of already hands its slot back to the keyboard.
func _on_joy_connection(id: int, connected: bool) -> void:
	if connected or paused or match_over:
		return
	for pl in Game.session.players:
		if pl["claimed"] and pl["device"] == "pad%d" % id:
			set_paused(true)

func on_action(dev: String, act: String) -> void:
	if act == "start" or (act == "back" and dev == "shared"):
		if match_over:
			return
		set_paused(not paused)
		return
	if paused:
		hud.pause_action(act)
	elif entry and phase == "intro" and phase_t > SKIP_AFTER and act in ["confirm", "back", "aux", "aux2"]:
		for f in fighters:
			if f.human and Game.session.controls(dev, f.slot):
				_skip = true

func set_paused(p: bool) -> void:
	paused = p
	_world_process()
	if p:
		Controls.latch_repeats()
	hud.show_pause(p)
	Sfx.play("tick")
	if not p:
		for f in fighters:
			if f.human:
				_release_presses(f)

func restart_round() -> void:
	set_paused(false)
	var banked := int(_stats.get("last_winner", 0))
	if phase == "round_end" and banked > 0:
		wins[banked - 1] -= 1     # the replay banks its own win, so the round counts once
	for i in 2:
		var f: Fighter = fighters[i]
		f.stat_damage_dealt = _round_stats[i][0]
		f.stat_max_combo = _round_stats[i][1]
		f.stat_hits = _round_stats[i][2]
	_start_round()

func quit_to_menu() -> void:
	set_paused(false)
	Sfx.stop_all()
	Game.go("menu", {}, "fade")

func quit_to_select() -> void:
	set_paused(false)
	Sfx.stop_all()
	Game.session.new_picks()
	Game.go("select", {}, "crest", {"crest": "gold"})

func cycle_dummy(step := 1) -> void:
	var order := ["stand", "crouch", "jump", "guard", "cpu"]
	dummy_mode = order[posmod(order.find(dummy_mode) + step, order.size())]
	f2.guard_all = dummy_mode == "guard"

func _probe_fighter(f: Fighter) -> Dictionary:
	return {"hp": snappedf(f.hp, 0.1), "meter": snappedf(f.meter, 0.1), "state": f.state_name(), "x": snappedf(f.position.x, 0.01),
		"y": snappedf(f.position.y, 0.01), "combo": f.foe.combo_hits, "move": f.move_key if f.state == Fighter.S.ATTACK else "",
		"mf": f.mf, "sf": f.sf, "tick": f.frame, "hitstop": f.hitstop, "facing": f.facing,
		"guard": snappedf(f.guard, 0.1), "crush": f.crush_t, "carrier": f.carrier.slot if f.carrier != null else 0}

func probe() -> Dictionary:
	var parts := 0
	var pn := fx_layer.get_node_or_null("Particles")
	if pn != null:
		parts = (pn as FxParticles)._ps.size()
	var proj_pos: Array = []
	for p in projectiles:
		if is_instance_valid(p):
			proj_pos.append([snappedf(p.position.x, 0.1), snappedf(p.position.y, 0.1)])
	return {
		"phase": phase, "phase_t": phase_t, "intro_cut": intro_cut, "intro_cut_t": intro_cut_t, "cam_zoom": snappedf(cam_zoom, 0.001),
		"round": round_no, "wins": wins, "timer": int(timer_frames / 60), "timer_frames": timer_frames, "mode": mode,
		"p1": _probe_fighter(f1), "p2": _probe_fighter(f2),
		"projectiles": projectiles.size(), "proj_pos": proj_pos, "particles": parts, "fx_nodes": fx_layer.get_child_count(),
		"events": _events.size(), "frame": _frame, "vis_frame": _vis_frame, "paused": paused,
		"freeze": {"time_stop": time_stop, "t": freeze_t, "frozen": world_frozen, "caster": freeze_caster.slot if freeze_caster != null else 0,
			"queue": _freeze_queue.size(), "release_t": release_t, "focus_t": _focus_t, "log": freeze_log.slice(maxi(0, freeze_log.size() - 6))},
		"buf": [f1._buf.keys(), f2._buf.keys()],
	}
