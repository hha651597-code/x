class_name Fighter
extends Node2D
## One combatant. Simulation runs in tick() at a fixed 60 Hz (driven by FightScreen); drawing is a
## "paper puppet": the student's official full-body portrait, posed by the state machine.
##
## States: IDLE WALK CROUCH JUMP ATTACK HIT AIRHIT BLOCK DOWN GETUP DASH BACKDASH KO INTRO WIN
## Coordinates: position = feet in world pixels (y grows down, Arena.GROUND is the floor).
## Hit/hurt boxes are Rect2 in world space; move rects are authored relative to the feet, facing right.

enum S { IDLE, WALK, CROUCH, JUMP, ATTACK, HIT, AIRHIT, BLOCK, DOWN, GETUP, DASH, BACKDASH, KO, INTRO, WIN }
const STATE_NAMES := ["idle", "walk", "crouch", "jump", "attack", "hit", "airhit", "block", "down", "getup", "dash", "backdash", "ko", "intro", "win"]
const BUFFER := 7

var slot := 1
var data: Dictionary = {}
var stats: Dictionary = {}
var moves: Dictionary = {}
var assist: Dictionary = {}
var assist_data: Dictionary = {}
var foe: Fighter
var world: Node                       # FightScreen
var input := FightInput.new()
var human := true

var facing := 1
var vel := Vector2.ZERO
var state := S.IDLE
var sf := 0                           # frames in this state
var frame := 0
var hp := 1000.0
var max_hp := 1000.0
var meter := 0.0
var hitstop := 0
var hitstun := 0
var blockstun := 0
var guard := 100.0          # 0..stats.guard_max
var crush_t := 0            # ticks of guard-crush stun left
var block_air := false      # this BLOCK started in the air
var last_block_jg := false  # the last guarded hit was a just guard (kits read it in on_block_dealt)
var _guard_idle := 0        # ticks since the last guarded hit
var _back_age := 99         # ticks since back was freshly pressed
var _prev_x := 0
var invuln := 0
var down_timer := 0
var assist_cd := 0
var assist_hold := false   # the round's opening support cooldown waits for FIGHT!
var assist_calls := 0      # assists called this match (a kit reads the change as "a call just happened")
var buff_frames := 0
var shield_frames := 0
var heal_pool := 0.0
var slide := 0                        # attacker pushed back by corner pressure
var air_ok := true
var carrier: Fighter = null           # the thrower holding this fighter: its own tick does nothing until the release
var carrying: Fighter = null          # the fighter this one holds
var carry_hit: Dictionary = {}        # the throw's hit, applied at the release
var carry_from := Vector2.ZERO        # where the held foe stood at the grab, relative to the feet, facing right
var carry_roll := 0.0                 # view: degrees on screen; positive swings the head away from the thrower
var carry_spin := 0.0                 # degrees a tick the roll keeps turning after the release, until touchdown
var carry_pivot := Vector2.ZERO       # view: the point the roll turns about, relative to the feet
var carry_anim := ""                  # sd.json anim shown while the foe is held and while it tumbles
var carry_t := 0
var carry_front := true               # view: drawn in front of the thrower
var ready_at := 0                     # the sf the ready beat starts on (the screen sets it after reset_round)
var entry_cuts := false               # this round's intro is the stage entry's two solo shots (the screen sets it after reset_round)

var move: Dictionary = {}
var move_key := ""
var mf := 0
var move_hit := false
var move_connected := false
var chain := 0
var _spawned := {}
var _buf := {}
var _age := {}                        # ticks since each buffered button first went down (re-presses keep it)
var powered := false                  # the generic super: this skill runs powered (Arena.SUPER_DMG, armor)
var _paid := {}                        # kv values on_move_start changed, as they were before; a late throw press refunds them
var _cancelled := false               # the running move began as a cancel, so a late second button never turns it into a throw

# combo bookkeeping (stored on the DEFENDER)
var combo_hits := 0
var big_voiced := false               # this combo already drew a big-hit line
var combo_dmg := 0.0
var combo_scale := 1.0
var juggle := 0
var stat_damage_dealt := 0.0
var stat_max_combo := 0
var stat_hits := 0

var guard_all := false                # training dummy: always blocks
var kit: Kit                          # this student's fighting style (scripts/fight/kits/)
var kv := {}                          # kit-private state (stacks, timers…) — reset every round by the kit
var armor_hits_left := 0              # hits the current move can still absorb (move["armor"])
var charge_t := 0                     # frames the current move's hold button was held (move["hold"])
var slow_frames := 0                  # movement debuff (hit["slow"])
var slow_mult := 1.0
var view: Node2D                      # FighterView (all visuals)
var rig: Node2D
var body: Sprite2D
var _mat: ShaderMaterial
var _flash := 0.0
var _t := 0.0
var _ghosts: Array = []
var dim := 1.0

func _ready() -> void:
	z_index = 5 - slot

func setup(roster_entry: Dictionary, player_slot: int, assist_entry: Dictionary) -> void:
	slot = player_slot
	data = roster_entry
	kit = Kits.make(roster_entry)
	stats = kit.build_stats()
	for k in ["walk", "walk_back", "dash", "jump_dx"]:
		stats[k] *= Arena.MOVE_SCALE
	moves = kit.build_moves(stats)
	if not moves.has("throw"):
		moves["throw"] = Movesets.throw_for(data, stats)
	_assign_costs()
	max_hp = Arena.MAX_HP
	hp = max_hp
	guard = float(stats.get("guard_max", 100.0))
	if not assist_entry.is_empty():
		assist_data = assist_entry
		assist = Movesets.assist_for(assist_entry)
		assist_cd = 150
	# visual rig (soft-body shader puppet, springs, auras, ghosts) lives in FighterView
	view = (load("res://scripts/fight/fighter_view.gd") as GDScript).new()
	add_child(view)
	view.setup(self)
	rig = view.rig
	body = view.body
	_mat = view.mat

## The meter tiers belong to the engine, not the kits: a cut-in move is the ult, a "super" move costs a super.
func _assign_costs() -> void:
	for k in moves:
		var m: Dictionary = moves[k]
		if m["cutin"]:
			m["cost"] = Arena.EX_COST
		elif m.get("super", false):
			m["cost"] = Arena.SUPER_COST

func reset_round(x: float, face: int) -> void:
	position = Vector2(x, Arena.GROUND)
	vel = Vector2.ZERO
	facing = face
	hp = max_hp
	state = S.INTRO
	sf = 0
	entry_cuts = false
	ready_at = 0
	hitstop = 0
	hitstun = 0
	blockstun = 0
	guard = float(stats.get("guard_max", 100.0))
	crush_t = 0
	block_air = false
	last_block_jg = false
	_guard_idle = 0
	_back_age = 99
	_prev_x = 0
	invuln = 0
	_carry_drop()
	carry_anim = ""
	carry_roll = 0.0
	carry_spin = 0.0
	carry_t = 0
	move = {}
	mf = 0
	combo_hits = 0
	combo_scale = 1.0
	combo_dmg = 0.0
	buff_frames = 0
	shield_frames = 0
	heal_pool = 0.0
	_buf.clear()
	_age.clear()
	powered = false
	input = FightInput.new()
	_ghosts.clear()
	_flash = 0.0
	armor_hits_left = 0
	charge_t = 0
	slow_frames = 0
	slow_mult = 1.0
	kv = {}
	kit.on_round_start(self)

# ── queries ──────────────────────────────────────────────────────────────────
func is_grounded() -> bool:
	return position.y >= Arena.GROUND - 0.5

func actionable() -> bool:
	return state in [S.IDLE, S.WALK, S.CROUCH]

func is_attacking() -> bool:
	return state == S.ATTACK

func state_name() -> String:
	return STATE_NAMES[state]

## Stats hurt_w / hurt_h / hurt_crouch_h size it per fighter (SD kits measure theirs from the model).
func hurtbox() -> Rect2:
	var w := float(stats.get("hurt_w", 92.0))
	var h := float(stats.get("hurt_h", 272.0))
	if state == S.CROUCH or (state == S.ATTACK and move.get("crouch", false)):
		h = float(stats.get("hurt_crouch_h", 168.0))
	elif state == S.DOWN or state == S.KO:
		return Rect2(position.x - 120.0, position.y - 46.0, 240.0, 46.0)
	return Rect2(position.x - w * 0.5, position.y - h, w, h)

## Full width of the cylinder that keeps two fighters apart. SD kits measure theirs from the model (sockets.json); the
## sprite kits keep Arena.PUSH_W, the width every range was authored against.
func push_w() -> float:
	return float(stats.get("push_w", Arena.PUSH_W))

## The push acts on this pair: neither is lying down or KO'd and their feet are under 170 px apart in height. FightScreen._push_apart
## and the actor's idle-while-pressed pose both ask it, so a pose never claims a hold the push does not apply.
func pushes_foe() -> bool:
	return foe != null and absf(position.y - foe.position.y) < 170.0 and state != S.DOWN and state != S.KO and foe.state != S.DOWN and foe.state != S.KO

## The closest two fighters' centres may come: the mean of their push widths (alone, our own).
func push_min() -> float:
	return push_w() if foe == null else (push_w() + foe.push_w()) * 0.5

## How much farther apart than Arena.PUSH_W this pair stands. Ranges and rects authored against 74 px add or take it off.
func spacing_extra() -> float:
	return 0.0 if foe == null else push_min() - Arena.PUSH_W

## The live melee hit data this frame, or {} (not active / already connected).
func active_hit() -> Dictionary:
	if state != S.ATTACK or move.is_empty() or move["hit"].is_empty() or move_hit:
		return {}
	if mf >= int(move["startup"]) and mf < int(move["startup"]) + int(move["active"]):
		return move["hit"]
	return {}

## World-space rect of a facing-right-authored Rect2.
func world_rect(r: Rect2) -> Rect2:
	if facing >= 0:
		return Rect2(position + r.position, r.size)
	return Rect2(position.x - r.position.x - r.size.x, position.y + r.position.y, r.size.x, r.size.y)

## world_rect() of a melee hit with its far edge grown by the extra spacing: kits authored the reach against the old 74 px
## minimum, so the foe's edge sits the same distance inside it. The one rect that is tested against hurtboxes.
func melee_rect(r: Rect2) -> Rect2:
	var wr := world_rect(r)
	var more := spacing_extra()
	if facing < 0:
		wr.position.x -= more
	wr.size.x += more
	return wr

func dmg_mult() -> float:
	return (1.25 if buff_frames > 0 else 1.0) * float(kv.get("dmg_mult", 1.0))

## dmg_mult() for a hit landing now. The generic super's boost goes on melee hits here; its projectiles carry it
## from the moment they spawn (FightScreen.spawn_projectile), so a round in flight is not boosted twice or late.
func hit_mult(is_projectile: bool) -> float:
	return dmg_mult() * (Arena.SUPER_DMG if powered and not is_projectile else 1.0)

## A super is running: a kit's own super move, or the generic powered skill.
func in_super() -> bool:
	return state == S.ATTACK and (powered or bool(move.get("super", false)))

## Movement speed multiplier (slow debuff × the kit's own speed_mult).
func speed_mult() -> float:
	return (slow_mult if slow_frames > 0 else 1.0) * float(kv.get("speed_mult", 1.0))

## Public button access for kits (input mapping hooks).
func consume(b: String) -> bool:
	return _consume(b)

func buffered(b: String) -> bool:
	return _buf.has(b)

## Meter earned by fighting (hits dealt and taken, blocks, counters, armor), paced by Arena.METER_PACE. A kit's own bonuses add to
## `meter` directly and are not paced.
func gain_meter(x: float) -> void:
	meter = minf(Arena.MAX_METER, meter + x * Arena.METER_PACE)

func assist_ready() -> bool:
	return not assist.is_empty() and assist_cd <= 0

## Hina and Hoshino have a sound set (assets/audio/ba/manifest.json); every other fighter keeps the synthesised sounds.
func has_sounds() -> bool:
	return Sfx.manifest.get("sets", {}).has(String(data.get("key", "")))

func sfx(event: String, pitch := 1.0, vol := 1.0) -> bool:
	return Sfx.play_for(String(data.get("key", "")), slot, frame, event, pitch, vol, move_key if state == S.ATTACK else "")

## The clock is the screen's _vis_frame, not Fighter.frame: a line plays in real time, and frame stalls in an EX freeze.
func voice(line: String, max_s := 0.0) -> bool:
	return Sfx.voice(String(data.get("key", "")), slot, world._vis_frame, line, world.time_stop > 0, max_s)

# ── per-frame simulation ─────────────────────────────────────────────────────
func tick() -> void:
	frame += 1
	_track_back()
	if carrier != null:
		return
	if hitstop > 0:
		hitstop -= 1
		return
	_update_buffer()
	if invuln > 0: invuln -= 1
	if crush_t > 0: crush_t -= 1
	_guard_idle += 1
	if _guard_idle > int(stats["guard_delay"]) and guard < float(stats["guard_max"]):
		guard = minf(float(stats["guard_max"]), guard + float(stats["guard_refill"]))
	if assist_cd > 0 and not assist_hold: assist_cd -= 1
	if buff_frames > 0: buff_frames -= 1
	if shield_frames > 0: shield_frames -= 1
	if heal_pool > 0.0 and hp > 0.0:
		var h := minf(heal_pool, 0.9)
		hp = minf(max_hp, hp + h)
		heal_pool -= h
	if slide > 0:
		slide -= 1
	if slow_frames > 0:
		slow_frames -= 1
	kit.on_tick(self)
	match state:
		S.IDLE, S.WALK, S.CROUCH: _tick_ground()
		S.JUMP: _tick_air()
		S.ATTACK: _tick_attack()
		S.HIT: _tick_hit()
		S.AIRHIT: _tick_airhit()
		S.BLOCK: _tick_block()
		S.DOWN: _tick_down()
		S.GETUP: _tick_getup()
		S.DASH, S.BACKDASH: _tick_dash()
		S.KO: _tick_ko()
		S.INTRO: vel.x = 0.0
		S.WIN: vel.x = 0.0
	sf += 1
	_move_body()

## What the SD view plays during the intro: [anim, tick in it]. The stage entry plays the idle until the fighter's own solo shot,
## intro_cut from the shot's first tick (P1's on tick 1, P2's after the pan) through the pan and the other shot; from the wide
## block on it is the idle, then the ready beat `intro` for 60 ticks from `ready_at` (it ends just before FIGHT!), then
## `intro_idle` (the idle with a long crossfade, so the rifle settles instead of dropping). A 60 tick intro plays the beat from
## tick 0 (sf equals phase_t when the view syncs).
func intro_step() -> Array:
	if entry_cuts and sf < Arena.INTRO_WIDE_AT:
		var start := 1 + (slot - 1) * (Arena.INTRO_SHOT + Arena.INTRO_PAN)
		return ["intro_cut", sf - start] if sf >= start else ["idle", sf]
	var k := sf - ready_at
	if k < 0:
		return ["idle", sf]
	return ["intro", k] if k < Arena.INTRO_READY else ["intro_idle", sf]

func _update_buffer() -> void:
	for b in _buf.keys():
		_buf[b] -= 1
		_age[b] = int(_age.get(b, 0)) + 1
		if _buf[b] <= 0:
			_buf.erase(b)
			_age.erase(b)
	for b in FightInput.BUTTONS:
		if input.was_pressed(b):
			# mashing keeps a button's age; a press after a longer gap starts a new one
			if not _buf.has(b) or BUFFER - int(_buf[b]) > Arena.CHORD:
				_age[b] = 0
			_buf[b] = BUFFER

func _consume(b: String) -> bool:
	_age.erase(b)
	if _buf.has(b):
		_buf.erase(b)
		return true
	return false

# ── meter tiers: skill + EX is the super, EX alone at a full meter the ult ──────
func _chord() -> bool:
	return _buf.has("skill") and _buf.has("ex") and meter >= Arena.SUPER_COST \
		and absi(int(_age.get("skill", 0)) - int(_age.get("ex", 0))) <= Arena.CHORD

## A lone EX at a full meter waits Arena.CHORD ticks for a skill press before it becomes the ult.
func _ult_pending() -> bool:
	return _buf.has("ex") and meter >= Arena.EX_COST and int(_age.get("ex", Arena.CHORD)) < Arena.CHORD

func _ult_ready() -> bool:
	return _buf.has("ex") and meter >= Arena.EX_COST and int(_age.get("ex", Arena.CHORD)) >= Arena.CHORD

## The kit's own super ("super", or "super_down" with down held), else the generic one: its skill, powered.
func _start_super(down: bool) -> void:
	_consume("skill")
	var key := "super_down" if down and moves.has("super_down") else "super"
	if moves.has(key):
		_consume("ex")
		_start_move(key)
		Sfx.play("super", 1.25, 0.7)
		return
	_start_move("skill")
	if move_key == "skill":
		_power_skill()
	else:
		_consume("ex")   # the kit turned the skill into another move (an empty gun reloads): no super, no cost

## The generic super on the running skill: pay for it and power it up.
func _power_skill() -> void:
	_consume("ex")
	meter -= Arena.SUPER_COST
	powered = true
	armor_hits_left = maxi(armor_hits_left, 1)
	Sfx.play("super", 1.25, 0.7)

## Skill, then EX within Arena.CHORD ticks and before the skill fired anything: it becomes the super.
func _try_upgrade() -> bool:
	if move_key != "skill" or powered or mf >= Arena.CHORD or not _spawned.is_empty() or move_hit or not is_grounded():
		return false
	if not _buf.has("ex") or int(_age["ex"]) > mf + 1 or meter < Arena.SUPER_COST:
		return false
	if moves.has("super"):
		_start_super(input.y > 0)
		return true
	_power_skill()
	return false

func _face_foe() -> void:
	if foe and absf(foe.position.x - position.x) > 6.0:
		facing = 1 if foe.position.x > position.x else -1

func _set_state(s: int) -> void:
	if carrying != null and s != S.ATTACK:
		_carry_end(true)
	if s != S.AIRHIT:
		_carry_drop_held()
	state = s
	if s in [S.HIT, S.AIRHIT, S.BLOCK, S.KO]:
		Sfx.stop_move(slot)
	if s != S.ATTACK:
		powered = false
	sf = -1   # becomes 0 at the end of this tick

func _tick_ground() -> void:
	_face_foe()
	if _try_actions():
		return
	if input.y < 0:
		_jump()
		return
	if input.y > 0:
		if state != S.CROUCH:
			_set_state(S.CROUCH)
		vel.x = 0.0
		return
	if input.x != 0:
		var fwd := input.x == facing
		vel.x = float(input.x) * (stats["walk"] if fwd else stats["walk_back"]) * speed_mult()
		if state != S.WALK:
			_set_state(S.WALK)
	else:
		vel.x = 0.0
		if state != S.IDLE:
			_set_state(S.IDLE)

## Buttons while actionable on the ground. Returns true when a move/dash/assist started.
func _try_actions() -> bool:
	if _chord():
		_start_super(input.y > 0)
		return true
	if _ult_pending():
		vel.x = 0.0
		return true
	var mapped := kit.map_ground_input(self)
	if mapped != "":
		_start_move(mapped)
		return true
	if _ult_ready():
		_consume("ex")
		_start_move("ex")
		return true
	if _buf.has("skill"):
		_consume("skill")
		_start_move("skill")
		return true
	if _throw_chord():
		_consume("light")
		_consume("heavy")
		_start_move("throw")
		return true
	if _buf.has("heavy"):
		_consume("heavy")
		_start_move(_normal_key("H"))
		return true
	if _buf.has("light"):
		_consume("light")
		_start_move(_normal_key("L"))
		return true
	if _buf.has("assist") and assist_ready():
		_consume("assist")
		world.call_assist(self)
		return false
	if _buf.has("dash"):
		_consume("dash")
		_start_dash(input.x != 0 and input.x != facing)
		return true
	return false

## The grounded foe is within `r` px of us: the legacy distance, centre to centre minus the extra spacing, so every range
## keeps the reach it was authored with against the old 74 px minimum.
func _foe_near(r: float) -> bool:
	return foe != null and foe.is_grounded() and absf(foe.position.x - position.x) - spacing_extra() <= r

## Light and heavy on the ground, checked in this order: down (2x), forward with a 6x the kit defines and a foe within
## Arena.COMMAND_RANGE (so walking in keeps the gun normals), a foe within
## Arena.CLOSE_RANGE with a close_x the kit defines, else 5x.
func _normal_key(b: String) -> String:
	if input.y > 0:
		return "2" + b
	if input.x == facing and moves.has("6" + b) and _foe_near(Arena.COMMAND_RANGE):
		return "6" + b
	if _foe_near(Arena.CLOSE_RANGE) and moves.has("close_" + b):
		return "close_" + b
	return "5" + b

func _throw_ok() -> bool:
	return moves.has("throw") and input.y <= 0 and is_grounded() and _foe_near(Arena.THROW_RANGE)

func _throw_chord() -> bool:
	return _buf.has("light") and _buf.has("heavy") and absi(int(_age.get("light", 0)) - int(_age.get("heavy", 0))) <= Arena.CHORD and _throw_ok()

## A lone light or heavy starts at once; the other button inside the first Arena.CHORD frames of a move that has not hit
## restarts it as the throw, like the super's upgrade. A cancel never upgrades, or a link in a combo would whiff a throw.
func _try_throw_upgrade() -> bool:
	if not move_key in ["5L", "5H", "6L", "6H", "close_L", "close_H"] or _cancelled or mf >= Arena.CHORD or move_hit or not _throw_ok():
		return false
	var other := "light" if move_key.ends_with("H") else "heavy"
	if not _buf.has(other) or int(_age.get(other, 99)) > mf + 1:
		return false
	_consume(other)
	for k in _paid:
		if _paid[k] == null:
			kv.erase(k)
		else:
			kv[k] = _paid[k]
	_start_move("throw")
	return true

func _jump() -> void:
	_set_state(S.JUMP)
	vel = Vector2(float(input.x) * stats["jump_dx"], -stats["jump"])
	air_ok = true
	world.fx_dust(position, 3)
	Sfx.play("jump", 1.0, 0.6)

func _start_dash(back: bool) -> void:
	_set_state(S.BACKDASH if back else S.DASH)
	vel.x = float(-facing if back else facing) * (stats["dash"] * (0.8 if back else 1.0)) * speed_mult()
	if back:
		invuln = maxi(invuln, 8)
	world.fx_dust(position, 4)
	world.fx_afterimage(self, 5)
	Sfx.play("dash", 1.0, 0.7)

func _tick_dash() -> void:
	var dur := 16 if state == S.DASH else 18
	vel.x *= 0.95
	if sf % 3 == 0:
		world.fx_afterimage(self, 3)
	if sf >= dur:
		vel.x = 0.0
		world.fx_skid(position, facing if state == S.DASH else -facing)
		_set_state(S.IDLE)

func _tick_air() -> void:
	vel.y += Arena.GRAVITY
	if _try_air_actions():
		return
	if is_grounded() and vel.y > 0.0:
		_land()

func _try_air_actions() -> bool:
	var mapped := kit.map_air_input(self)
	if mapped != "":
		_start_move(mapped)
		return true
	if _buf.has("heavy") and air_ok:
		_consume("heavy")
		_start_move("jH")
		return true
	if _buf.has("light") and air_ok:
		_consume("light")
		_start_move("jL")
		return true
	if _buf.has("skill") and air_ok:
		_consume("skill")
		_start_move("skill_air")
		return true
	if _buf.has("assist") and assist_ready():
		_consume("assist")
		world.call_assist(self)
	return false

func _land() -> void:
	position.y = Arena.GROUND
	vel = Vector2.ZERO
	_set_state(S.IDLE)
	_face_foe()
	world.fx_dust(position, 3)
	Sfx.play("land", 1.0, 0.5)

func _start_move(key: String) -> void:
	if not moves.has(key):
		return
	if carrying != null:
		_carry_end(true)
	var m: Dictionary = moves[key]
	if key != move_key or state != S.ATTACK:
		chain = 0
	else:
		chain += 1
	move = m
	move_key = key
	powered = false
	_cancelled = state == S.ATTACK
	mf = -1
	move_hit = false
	move_connected = false
	_spawned.clear()
	charge_t = 0
	var kv_before := kv.duplicate(true)
	armor_hits_left = int(m.get("armor", {}).get("hits", 0))
	if m["cost"] > 0.0:
		meter -= m["cost"]
	if state != S.JUMP and not m["air"]:
		vel.x = 0.0
	_set_state(S.ATTACK)
	if m["air"]:
		pass
	if m["cutin"]:
		world.begin_cutin(self)
	elif key in ["5L", "2L", "jL", "close_L", "6L"] and not m.has("shots"):
		Sfx.play("swing", 1.2, 0.5)
	elif key in ["5H", "2H", "jH", "close_H", "6H"] and not m.has("shots"):
		Sfx.play("swing", 0.8, 0.7)
	elif key == "throw":
		Sfx.play("throw", 1.0, 0.7)
	kit.on_move_start(self, key)
	_paid.clear()
	for k in kv:
		if not kv_before.has(k) or kv[k] != kv_before[k]:
			_paid[k] = kv_before.get(k)

func _tick_attack() -> void:
	mf += 1
	if carrying != null:
		_carry_step()
	if _try_upgrade() or _try_throw_upgrade():
		return
	var airborne: bool = move["air"] or not is_grounded()
	# hold-to-charge: freeze the move at frame `at` while the button stays down (up to `max` frames)
	var hold: Dictionary = move.get("hold", {})
	if not hold.is_empty() and mf == int(hold["at"]) and charge_t < int(hold["max"]) and input.is_held(String(hold["btn"])):
		mf -= 1
		charge_t += 1
		vel.x *= 0.6
		if airborne:
			vel.y = minf(vel.y + Arena.GRAVITY * 0.2, 2.0)
		var fe := int(hold.get("fire_every", 0))
		if fe > 0 and charge_t % fe == 1:
			# sustained fire: every `fire_every` frames of holding, spawn the specs tagged "hold_fire"
			for i in move["spawns"].size():
				var hs: Dictionary = move["spawns"][i]
				if hs.get("hold_fire", false):
					world.spawn_projectile(self, hs)
		elif fe == 0 and charge_t % 8 == 1:
			world.fx_cue(self, "charge")
		return
	# invulnerability window
	var inv: Array = move.get("inv", [])
	if inv.size() == 2 and mf >= int(inv[0]) and mf <= int(inv[1]):
		invuln = maxi(invuln, 1)
	# motion: forward speed list (legacy) + general velocity segments (set / add, optional gravity-off)
	var moving := false
	for seg in move["vx"]:
		if mf >= int(seg["from"]) and mf < int(seg["to"]):
			vel.x = float(facing) * float(seg["v"]) * speed_mult()
			moving = true
	var nograv := false
	for seg in move.get("motion", []):
		if mf >= int(seg["from"]) and mf < int(seg["to"]):
			var add_mode: bool = seg.get("mode", "set") == "add"
			if seg.has("vx"):
				var vx := float(facing) * float(seg["vx"])
				vel.x = vel.x + vx if add_mode else vx
				moving = true
			if seg.has("vy"):
				vel.y = vel.y + float(seg["vy"]) if add_mode else float(seg["vy"])
			if seg.get("nograv", false):
				nograv = true
	if airborne and not nograv:
		vel.y += Arena.GRAVITY
	if not moving and not airborne:
		vel.x *= 0.6
	# teleport / self effects / sound cues
	var tp: Dictionary = move.get("teleport", {})
	if not tp.is_empty() and mf == int(tp["frame"]):
		_teleport(tp)
	for e in move.get("self", []):
		if int(e["frame"]) == mf:
			_apply_self(e)
	for e in move.get("sfx", []):
		if int(e["frame"]) == mf:
			sfx(String(e["name"]), float(e.get("pitch", 1.0)), float(e.get("vol", 1.0)))
	# cues + projectiles
	for cue in move["fx"]:
		if int(cue["frame"]) == mf:
			world.fx_cue(self, cue["kind"])
	for i in move["spawns"].size():
		var sp: Dictionary = move["spawns"][i]
		if int(sp["frame"]) == mf and not _spawned.has(i):
			_spawned[i] = true
			if sp.get("hold_fire", false):
				continue
			if charge_t < int(sp.get("min_charge", 0)) or charge_t > int(sp.get("max_charge", 99999)):
				continue
			world.spawn_projectile(self, sp)
	# chain / cancel
	if move_connected and mf < int(move["frames"]) - 1 and not move["cancel"].is_empty():
		if _try_cancel():
			return
	if airborne and is_grounded() and vel.y > 0.0:
		_land()
		return
	if mf >= int(move["frames"]) - 1:
		_end_move()

## Blink to `tp.to` ("behind" the foe / "front" / "away"), `tp.gap` px from them.
func _teleport(tp: Dictionary) -> void:
	if foe == null:
		return
	world.fx_dust(position, 4)
	world.fx_afterimage(self, 6)
	var gap := float(tp.get("gap", 90.0)) + spacing_extra()
	var side := signf(position.x - foe.position.x)
	if side == 0.0:
		side = -float(facing)
	match String(tp.get("to", "behind")):
		"behind":
			position.x = foe.position.x - float(foe.facing) * gap
		"front":
			position.x = foe.position.x + side * gap
		"away":
			position.x = foe.position.x + side * gap
	position.x = clampf(position.x, -Arena.HALF_W, Arena.HALF_W)
	if tp.has("y"):
		position.y = Arena.GROUND + float(tp["y"])
	facing = 1 if foe.position.x > position.x else -1
	world.fx_dust(position, 4)
	Sfx.play("whoosh", 1.4, 0.6)

## Self effects at a move frame: {frame, heal (fraction of max hp), heal_flat, shield (frames), buff (frames), meter, invuln, armor_hits}.
func _apply_self(e: Dictionary) -> void:
	if e.has("heal"):
		heal_pool += max_hp * float(e["heal"])
		world.fx_heal(self)
	if e.has("heal_flat"):
		heal_pool += float(e["heal_flat"])
		world.fx_heal(self)
	if e.has("shield"):
		shield_frames = int(e["shield"])
	if e.has("buff"):
		buff_frames = int(e["buff"])
	if e.has("meter"):
		meter = clampf(meter + float(e["meter"]), 0.0, Arena.MAX_METER)
	if e.has("invuln"):
		invuln = maxi(invuln, int(e["invuln"]))
	if e.has("armor_hits"):
		armor_hits_left = int(e["armor_hits"])

func _try_cancel() -> bool:
	var c: Array = move["cancel"]
	if ("skill" in c or "ex" in c) and not move["air"] and is_grounded() and _chord():
		_start_super(input.y > 0)
		return true
	if "ex" in c and not move["air"] and _ult_pending():
		return false
	if "ex" in c and _ult_ready() and not move["air"]:
		_consume("ex")
		_start_move("ex")
		return true
	if "skill" in c and _buf.has("skill"):
		_consume("skill")
		_start_move("skill_air" if not is_grounded() else "skill")
		return true
	if "heavy" in c and _buf.has("heavy"):
		_consume("heavy")
		_start_move(("jH" if not is_grounded() else ("2H" if input.y > 0 else "5H")))
		return true
	if "light" in c and _buf.has("light") and chain < 2:
		_consume("light")
		_start_move(("jL" if not is_grounded() else ("2L" if input.y > 0 else "5L")))
		return true
	return false

func _end_move() -> void:
	if carrying != null:
		_carry_end(true)
	if move.get("cutin", false):
		Sfx.stop_move(slot)
	move = {}
	if not is_grounded():
		_set_state(S.JUMP)
	else:
		vel.x = 0.0
		_set_state(S.IDLE)

func _tick_hit() -> void:
	vel.x *= 0.86
	hitstun -= 1
	if hitstun <= 0:
		_recover()

func _recover() -> void:
	combo_hits = 0
	combo_scale = 1.0
	combo_dmg = 0.0
	juggle = 0
	if hp <= 0.0:
		_ko()
		return
	_set_state(S.IDLE)

func _tick_airhit() -> void:
	vel.y += Arena.GRAVITY
	carry_roll += carry_spin
	if is_grounded() and vel.y > 0.0:
		position.y = Arena.GROUND
		vel.x *= 0.35
		vel.y = 0.0
		world.fx_dust(position, 5)
		world.shake(3.0)
		Sfx.play("land", 0.7, 0.8)
		if hp <= 0.0:
			_ko()
		else:
			_set_state(S.DOWN)
			down_timer = 38
			combo_hits = 0
			combo_scale = 1.0
			combo_dmg = 0.0
			juggle = 0

func _tick_block() -> void:
	vel.x *= 0.84
	if not is_grounded():
		vel.y += Arena.GRAVITY
	elif block_air:
		_land()
		return
	blockstun -= 1
	if blockstun <= 0:
		_set_state(S.IDLE if is_grounded() else S.JUMP)

## A fresh press of back, counted in real sim ticks (before the hitstop return, so a press in hitstop still counts).
func _track_back() -> void:
	_back_age = mini(_back_age + 1, 99)
	if input.x != _prev_x and input.x == -facing:
		_back_age = 0
	_prev_x = input.x

func _guard_crush() -> void:
	crush_t = int(stats["guard_crush"])
	blockstun = crush_t
	block_air = false
	guard = float(stats["guard_max"])
	Sfx.play("guard_crush")
	world.shake(5.0)

func _tick_down() -> void:
	vel.x *= 0.85
	down_timer -= 1
	if down_timer <= 0:
		_set_state(S.GETUP)
		invuln = 14

func _tick_getup() -> void:
	vel.x = 0.0
	if sf >= 12:
		_set_state(S.IDLE)

func _ko() -> void:
	kit.on_ko(self)
	hp = 0.0
	_set_state(S.KO)
	vel.x *= 0.3
	world.on_ko(self)

func _tick_ko() -> void:
	vel.x *= 0.85
	vel.y += Arena.GRAVITY
	if is_grounded():
		position.y = Arena.GROUND
		vel.y = 0.0

func start_win() -> void:
	_set_state(S.WIN)
	vel = Vector2.ZERO

func _move_body() -> void:
	position += vel
	var lim := Arena.HALF_W
	if position.x < -lim:
		position.x = -lim
		vel.x = maxf(vel.x, 0.0)
	elif position.x > lim:
		position.x = lim
		vel.x = minf(vel.x, 0.0)
	if position.y > Arena.GROUND:
		position.y = Arena.GROUND
		if state not in [S.JUMP, S.ATTACK, S.AIRHIT, S.KO]:
			vel.y = 0.0

# ── receiving hits ───────────────────────────────────────────────────────────
## Returns "hit", "block" or "miss". `from` = world position of the hit (for knock direction).
func receive_hit(att: Fighter, h: Dictionary, from: Vector2, is_projectile: bool) -> String:
	if carrier != null or invuln > 0 or state in [S.KO, S.DOWN, S.GETUP, S.INTRO, S.WIN] or world.phase in ["ko", "round_end"]:
		return "miss"
	if shield_frames > 0:
		shield_frames = 0
		world.fx_spark(position + Vector2(0, -170), "block", facing)
		Sfx.play("block")
		att.hitstop = 4
		if not is_projectile:
			att.move_hit = true
		return "block"
	var dir := 1 if position.x >= from.x else -1
	if h.get("throw", false):
		return _take_throw(att, h)
	var is_grab: bool = bool(h.get("grab", false))
	# parry / counter window and super-armor window of the move being performed
	if state == S.ATTACK and not move.is_empty() and not is_grab:
		var cw: Dictionary = move.get("counter", {})
		if not cw.is_empty() and mf >= int(cw["from"]) and mf <= int(cw["to"]):
			_do_counter(att, h, cw, dir, is_projectile)
			return "block"
		var ar: Dictionary = move.get("armor", {})
		if not ar.is_empty() and mf >= int(ar["from"]) and mf <= int(ar["to"]) and armor_hits_left > 0:
			var adm := float(h["dmg"]) * att.hit_mult(is_projectile) * float(ar.get("dmg", 0.6)) * float(stats["taken"])
			if hp - adm > 0.0:
				armor_hits_left -= 1
				_do_armor_hit(att, h, adm, is_projectile)
				return "hit"
		# the generic super: one hit of armor until the powered skill goes active
		if powered and ar.is_empty() and mf < int(move["startup"]) and armor_hits_left > 0:
			var pdm := float(h["dmg"]) * att.hit_mult(is_projectile) * 0.6 * float(stats["taken"])
			if hp - pdm > 0.0:
				armor_hits_left -= 1
				_do_armor_hit(att, h, pdm, is_projectile)
				return "hit"
	if not is_grab and _can_block(h):
		_do_block(att, h, dir, is_projectile)
		return "block"
	_carry_drop_held()
	_do_hit(att, h, dir, is_projectile)
	return "hit"

## A throw beats block, armor and counter (it is checked before them) but needs a foe on the ground who is acting or
## idle: not in hitstun, blockstun (a guard crush too), the air or a cut-in or super. Hitting a fighter who is in the
## startup or active frames of their own throw is a tech instead. A throw with a carry dict grabs the foe; one without
## (or whose thrower was struck on the same tick) snaps it in front and hits at once.
func _take_throw(att: Fighter, h: Dictionary) -> String:
	if not att.move.get("hit", {}).get("throw", false):
		return "miss"   # the second connect of a tech: _tech emptied its thrower's move
	if state == S.ATTACK and move.get("hit", {}).get("throw", false) and mf < int(move["startup"]) + int(move["active"]):
		_tech(att)
		return "miss"
	if not is_grounded() or state not in [S.IDLE, S.WALK, S.CROUCH, S.DASH, S.BACKDASH, S.ATTACK] or in_super() or (state == S.ATTACK and move.get("cutin", false)):
		return "miss"
	var c: Dictionary = att.move.get("carry", {})
	if not c.is_empty() and att.state == S.ATTACK:
		_grab(att, h, c)
		return "hit"
	position.x = clampf(att.position.x + float(att.facing) * (float(h.get("snap", 80.0)) + spacing_extra()), -Arena.HALF_W, Arena.HALF_W)
	_do_hit(att, h, att.facing, false)
	return "hit"

## The grab: the foe is held in the airhit pose (its own tick does nothing) and the thrower's move frame carries it along the
## path. No damage yet: the throw's hit lands at the release.
func _grab(att: Fighter, h: Dictionary, c: Dictionary) -> void:
	move = {}
	_set_state(S.AIRHIT)
	vel = Vector2.ZERO
	hitstop = 0
	facing = -att.facing
	carrier = att
	att.carrying = self
	att.carry_hit = h
	att.carry_from = Vector2((position.x - att.position.x) * float(att.facing), position.y - Arena.GROUND)
	carry_anim = String(c["anim"])
	carry_roll = 0.0
	carry_spin = 0.0
	carry_t = 0
	carry_pivot = Vector2(0.0, -float(c["pivot"]))
	carry_front = bool(c.get("front", true))
	att.move_hit = true
	att.hitstop = int(c["grab_stop"])
	world.fx_spark(att.position + Vector2(float(att.facing) * 70.0, -150.0), "light", att.facing)
	att.sfx("grab")
	world.shake(2.0)

## One step of the held foe along the move's path: linear between the [mf, x, y, roll] keys, from where it was caught at the
## move's startup, in the thrower's facing. The thrower's tick runs it, so the foe's slot makes no difference.
func _carry_step() -> void:
	var c: Dictionary = move.get("carry", {})
	if c.is_empty():
		_carry_end(true)
		return
	var from := Vector4(float(move["startup"]), carry_from.x, carry_from.y, 0.0)   # (mf, x, y, roll)
	var cur := from
	for k in c["path"]:
		var to := Vector4(float(k[0]), float(k[1]), float(k[2]), float(k[3]))
		cur = to
		if float(mf) <= to.x:
			cur = from.lerp(to, (float(mf) - from.x) / maxf(to.x - from.x, 1.0))
			break
		from = to
	var f := carrying
	f.position = Vector2(clampf(position.x + float(facing) * cur.y, -Arena.HALF_W, Arena.HALF_W), minf(Arena.GROUND + cur.z, Arena.GROUND))
	f.carry_roll = cur.w * float(facing)
	f.carry_t += 1
	if mf >= int(c["release"]):
		_carry_end(false)

## Lets the foe go and lands the throw's hit on it. An abort (the thrower was hit, started another move, went down) does the
## same at once without touching the thrower's own hitstop or move flags. Under the TIME UP or K.O. banner nothing lands, as in
## receive_hit: the foe is let go and falls.
func _carry_end(abort: bool) -> void:
	var f := carrying
	carrying = null
	f.carrier = null
	f.carry_spin = float(move.get("carry", {}).get("spin", 0.0)) * float(facing)
	if world.phase in ["ko", "round_end"]:
		return
	f._do_hit(self, carry_hit, facing, abort)
	if f.frame < frame:
		f.hitstop += 1   # it ticks after us this step and would lose a hitstop tick that the other slot order keeps

## Cuts the hold from either end with no hit: a round start.
func _carry_drop() -> void:
	if carrying != null:
		carrying.carrier = null
	if carrier != null:
		carrier.carrying = null
	carrying = null
	carrier = null

## The held fighter leaves the airhit pose (it went down or won, or the tumble ended): the view fields go.
func _carry_drop_held() -> void:
	if carrier != null:
		_carry_drop()
	carry_anim = ""
	carry_roll = 0.0
	carry_spin = 0.0

## Two throws meet: both moves end, both hold 8 ticks and step apart. No damage, no new state.
func _tech(att: Fighter) -> void:
	var side := 1.0 if position.x >= att.position.x else -1.0
	var mid := (position.x + att.position.x) * 0.5
	for f in [self, att]:
		f._end_move()
		f.hitstop = 8
		f.position.x = clampf(f.position.x + (side if f == self else -side) * 14.0, -Arena.HALF_W, Arena.HALF_W)
	world.fx_spark(Vector2(mid, Arena.GROUND - 170.0), "block", facing)
	world.fx_text(Vector2(mid, Arena.GROUND - 300.0), "TECH", Color(1.0, 0.92, 0.45))
	world.shake(3.0)
	Sfx.play("tech")

## A parried hit: nothing lands, the attacker is shoved back and our counter move starts.
func _do_counter(att: Fighter, h: Dictionary, cw: Dictionary, dir: int, is_projectile: bool) -> void:
	invuln = maxi(invuln, 10)
	gain_meter(float(cw.get("meter", 8.0)))
	if not is_projectile:
		att.hitstop = 10
		att.vel.x = -float(dir) * 5.0
		att.move_hit = true
	hitstop = 8
	world.fx_spark(position + Vector2(float(-facing) * 30.0, -170), "block", facing)
	world.fx_text(position + Vector2(0, -300), String(cw.get("text", "COUNTER!")), Color(1.0, 0.92, 0.45))
	world.shake(4.0)
	Sfx.play("block", 0.7)
	Sfx.play("claim", 1.3, 0.5)
	_flash = 0.5
	facing = 1 if att.position.x > position.x else -1
	if String(cw.get("move", "")) != "":
		_start_move(String(cw["move"]))

## Super-armor: the hit is absorbed (reduced damage, no stun / knockback) and the move keeps going.
func _do_armor_hit(att: Fighter, h: Dictionary, dmg: float, is_projectile: bool) -> void:
	hp -= dmg
	att.stat_damage_dealt += dmg
	att.gain_meter(float(h["meter"]) * 0.6)
	gain_meter(dmg * 0.05)
	if not is_projectile:
		att.hitstop = 5
		att.move_hit = true
		att.move_connected = true
	hitstop = 4
	_flash = 0.4
	world.fx_spark(position + Vector2(float(-facing) * 22.0, -180), "heavy", facing)
	world.fx_damage(position + Vector2(0, -280), dmg, false)
	world.shake(2.0)
	Sfx.play("block", 0.8)

func _can_block(h: Dictionary) -> bool:
	if crush_t > 0:
		return false
	var air := not is_grounded()
	if air:
		if state != S.JUMP and state != S.BLOCK:
			return false
	elif not (actionable() or state == S.BLOCK or state == S.DASH or state == S.BACKDASH):
		return false
	if guard_all:
		return true
	var away := -facing
	if air and foe != null:
		away = -1 if foe.position.x > position.x else 1   # back means away from the foe, even after a cross-over
	if input.x != away:
		return false
	if air:
		return true
	var crouching := input.y > 0
	match h.get("level", "mid"):
		"low": return crouching
		"high": return not crouching
	return true

func _do_block(att: Fighter, h: Dictionary, dir: int, is_projectile: bool) -> void:
	var air := not is_grounded()
	var jg := _back_age <= int(stats["guard_jg"])
	var raw := float(h["dmg"]) * att.hit_mult(is_projectile)
	var k := Arena.AIR_BLOCK if air else 1.0
	_set_state(S.BLOCK)
	block_air = air
	_guard_idle = 0
	last_block_jg = jg
	blockstun = int(h["blockstun"])
	vel.x = float(dir) * float(h["push"]) * 1.1
	if jg:
		_back_age = 99   # one press guards one hit, so a stream of rounds is not all just guards
		blockstun = maxi(1, ceili(float(blockstun) * 0.5))
		gain_meter(Arena.JG_METER)
	else:
		var chip := raw * float(h.get("chip", 0.08)) * k * (0.0 if kv.get("no_chip", false) else 1.0)
		hp = maxf(1.0, hp - chip)
		gain_meter(2.0)
		if not guard_all:
			guard = maxf(0.0, guard - raw * Arena.GUARD_DRAIN * float(att.stats["guard_dealt"]) * k)
	att.gain_meter(float(h["meter"]) * 0.4)
	var stop := maxi(3, int(h["hitstop"]) - 2)
	hitstop = stop
	if not is_projectile:
		att.hitstop = stop
		att.move_hit = true
		att.move_connected = true
		if _at_wall(dir):
			att.slide = 8
			att.vel.x = -float(dir) * float(h["push"]) * 1.1
	world.fx_spark(position + Vector2(float(-facing) * 22.0, -175), "block", facing)
	if jg:
		_flash = 0.9
		Sfx.play("just_guard")
	else:
		_flash = 0.3
		Sfx.play("block")
	att.kit.on_block_dealt(att, self, h)
	if guard <= 0.0 and not jg:
		_guard_crush()

func _do_hit(att: Fighter, h: Dictionary, dir: int, is_projectile: bool) -> void:
	crush_t = 0
	var cscale := combo_scale
	var dmg := float(h["dmg"]) * att.hit_mult(is_projectile) * cscale * float(stats["taken"])
	dmg = kit.on_hit_taken(self, att, h, dmg)
	att.stat_damage_dealt += minf(dmg, maxf(hp, 0.0))     # the stat counts the hp that was left, not the overkill
	hp -= dmg
	combo_hits += 1
	combo_dmg += dmg
	combo_scale = maxf(0.35, combo_scale * 0.88)
	att.stat_hits += 1
	att.stat_max_combo = maxi(att.stat_max_combo, combo_hits)
	var gain_mult := 1.5 if att.buff_frames > 0 else 1.0
	att.gain_meter(float(h["meter"]) * gain_mult)
	gain_meter(dmg * 0.04)
	var stop := int(h["hitstop"])
	hitstop = stop
	if not is_projectile:
		att.hitstop = stop
		att.move_hit = true
		att.move_connected = true
		if _at_wall(dir):
			att.slide = 8
			att.vel.x = -float(dir) * float(h["push"]) * 1.0
	var launch: Vector2 = h["launch"]
	var airborne := not is_grounded()
	if h["kd"] or launch != Vector2.ZERO or airborne:
		_set_state(S.AIRHIT)
		juggle += 1
		var lx := launch.x if launch.x != 0.0 else float(h["push"]) * 0.8
		var ly := launch.y if launch.y != 0.0 else -6.0 + float(mini(juggle, 4)) * 0.8
		if airborne and launch.y == 0.0:
			ly = -5.0 + float(mini(juggle, 4)) * 0.7
		vel = Vector2(float(dir) * lx, ly)
		position.y = minf(position.y, Arena.GROUND - 2.0) if ly < 0.0 else position.y
	else:
		_set_state(S.HIT)
		hitstun = int(h["hitstun"])
		vel.x = float(dir) * float(h["push"])
	if h.has("slow"):
		slow_frames = int(h["slow"]["frames"])
		slow_mult = float(h["slow"]["mult"])
	if h.has("lifesteal") and att.hp > 0.0:
		att.hp = minf(att.max_hp, att.hp + dmg * float(h["lifesteal"]))
	if h.has("pull"):
		vel.x -= float(dir) * float(h["pull"])
	att.kit.on_hit_dealt(att, self, h, dmg)
	_flash = 0.55
	world.fx_spark(position + Vector2(float(-dir) * 18.0, -190.0), h["spark"], -dir)
	world.fx_damage(position + Vector2(float(dir) * 30.0, -270), dmg, h["spark"] != "light")
	world.shake(float(h["shake"]))
	world.on_hit(att, self, h, combo_hits)
	att.sfx(String(h["sfx"]))
	if combo_hits == 1:
		big_voiced = false
	if hp > 0.0 and not big_voiced and (h["kd"] or launch != Vector2.ZERO):
		big_voiced = voice("big_hit")
	if hp <= 0.0:
		hp = 0.0
		if state != S.AIRHIT:
			_set_state(S.AIRHIT)
			vel = Vector2(float(dir) * 7.0, -9.0)
		else:
			vel.x = float(dir) * maxf(absf(vel.x), 7.0)
			vel.y = minf(vel.y, -9.0)

func _at_wall(dir: int) -> bool:
	return absf(position.x + float(dir) * 70.0) >= Arena.HALF_W

# ── drawing (all visuals live in FighterView; see scripts/fight/fighter_view.gd) ──
func _process(delta: float) -> void:
	_t += delta
	if view:
		view.step(delta)
	_flash = maxf(0.0, _flash - delta * 9.0)     # after the view reads it, so a hit's first drawn frame is the full flash

## Afterimage hook used by FightScreen.fx_afterimage (dash trails).
func add_ghost(col := Color(0.7, 0.9, 1.0), life := 0.28) -> void:
	if view:
		view.add_ghost(col, life)
