extends SceneTree
## SD fighter animation suite. Every roster fighter with an sd.json (two per fight) x every state anim and kit move x
## both facings.
## Run with tools/sd_test.sh (a real small window). Exits 0 when every check passes.
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

const DRIFT_POS := 0.005      # model units
const DRIFT_DEG := 1.0
## Feet are measured against each sd.json's "ankle" (the idle foot bone height the actor stands the model on).
## 0.05 model units is 7 px at fight scale (2% of the 330 px body). Source clips shift the planted ankle by up to
## 0.045 (Hoshino's Vital_Panic, Exs); a layer bug (tilt about the wrong pivot, broken leg IK) moves it 0.1 or more.
## A foot may go as low as the raw source sample's own lowest foot allows (Hina's Vital_Death kneels on her shins),
## so the check catches what layers and blends add, not what the clip already does.
const FLOOR_TOL := 0.05
## Barrel (weapon bone -> muzzle on screen) against the line of fire, in degrees. A projectile flies along its spawn
## velocity: the source clips' steady aims read up to 6 off their shot line (Hoshino's weapon bone sits under the bore,
## her level aim measures -5 to -6) and the MG judder adds up to 4 (Hina's Normal_Attack_Ing and Exs loops), so 10.
## A gun normal's line of fire is the gameplay muzzle -> its hit-rect centre; the barrel only has to point into that
## zone, so its tolerance is the zone's angular radius from the muzzle, at least AIM_TOL and at most 45 (a zone that
## wraps the muzzle still needs the barrel on its side). That is coarse: Hoshino's whole recoil kick (12) fits inside
## it, so LEVEL_TOL and the kick check below guard the timing.
const AIM_TOL := 10.0
const AIM_ZONE_MAX := 45.0
## In the model's own frame (inside the tilt and turn layers, which do the aiming) every shot and spawn tick of both kits
## leaves the gun within 3 of level (Hoshino's weapon bone sits under her bore). Near the top of her kick it reads 10
## to 12 higher.
const LEVEL_TOL := 6.0
## A lone shot (no other shot within KICK_FRAMES, unlike an MG burst) is one blast: the clip's recoil lifts the gun at
## least KICK_DEG within the next KICK_FRAMES frames. Hoshino's kick lifts it 12; a shot that lands after the kick, or
## a kick still frames away, rises less.
const KICK_FRAMES := 3
const KICK_DEG := 6.0
## Between two fire frames the gun holds steady: once a shot's kick has passed, nothing pulls the weapon back along its
## barrel RECOIL model units (11 px) or more within KICK_FRAMES until the next shot. Hoshino's EX once played the Exs
## clip's 4.6 s shot, which has no blast, from mf 57 (0.13); Hina's MG judder between rounds stays under 0.05.
const RECOIL := 0.08
## Hips (pelvis bone, projected) against idle's in the same facing, fight px, over every sampled frame of every ground
## anim and move. Leans and steps move them up to 17 (dash, tilt 10); a body sitting beside the feet moved them 29 to
## 31 (a turn about a point 0.36 units to Hina's side) and 77 to 97 (her Stand_Attack_* clips:
## the standing pose 0.69 units to the side).
const HIPS_TOL := 20.0
## Idle hips (pelvis, projected) against the feet origin, fight px, both facings, over the idle loop. The facing yaw
## turns the model about that origin; setup() stands the idle pelvis (first frame) on it and the loop sways it up to 1.4
## px, so 3. Centred on the Body mesh box instead, the hips sat -50 / -33 (Hina) and -24 / -11 (Hoshino) off it, and the
## body stepped sideways on every turn-around.
const IDLE_HIPS := 3.0
## Authored travel: win and ex play clips whose body moves (Victory_*, Exs: up to 27). Aims up and down bend the upper
## body (sd.json "aim"), so 2H and Hina's super_down stay within HIPS_TOL.
const HIPS_ALLOW := {"win": 30.0, "ex": 30.0}
## getup rises from down's lying pose, whose hips lie a body length from the feet (Hina's Vital_Death backwards).
const HIPS_EXEMPT := ["getup"]
## Hips motion per tick across the crouch family's transitions (SLIDES), blending on, fight px. Aligned poses step up
## to 4.5 (a 3-tick crossfade covers a quarter of the gap a tick); the displaced kneel stepped 20 to 39.
const HIPS_STEP := 8.0
const SLIDES := [["crouch", "attack:2L"], ["crouch", "attack:2H"], ["crouch", "block_low"], ["attack:2L", "crouch"]]
## The edge check samples state anims every EDGE_STEP frames and moves every third frame, rendered.
const EDGE_STEP := 6
## Gameplay muzzle (a spawn's offset, a gun normal's kit _muzzle()) against the projected muzzle on every tick it fires
## from, each facing, fight px. The gameplay offset is the mean of the two facings, which sit up to 80 px apart (the gun
## is on her right side and facing is a yaw, not a mirror; Hoshino's jL and jH), so up to 40; the projectile's draw
## offset covers the rest. With the body off the yaw axis they sat up to 129 px apart (Hina's 5H).
const MUZZLE_DX := 45.0
const MUZZLE_DY := 20.0
## A gun normal's melee rect starts within RECT_START px of the measured muzzle, except in the kits listed in
## RECT_FRONT_EDGE, which are only reported: Hoshino's blast zones start at her front edge by design.
const RECT_START := 40.0
const RECT_FRONT_EDGE := ["hoshino"]
## Air states have no floor contact; down / ko lie on the torso, so their feet are not the contact (reported only).
## The backdash is a hop, so no foot is within HOP_PX of the floor on any tick it moves (|vx| > 1). sd_foot_test.gd checks the same on the live sim.
const HOP_PX := 6.0
## ...and its hips rise at least HOP_RISE model units (14 px) over idle's at tick 5: the legs alone clear the floor, the lift makes it a hop.
const HOP_RISE := 0.1
const NO_FLOOR := ["jump", "airhit", "down", "ko", "block_air", "dash_air", "dash_air_back", "glide", "backdash"]
## Lying states rest on the hurtbox bones (pelvis, feet, upper arms, head; not hair or wings): none goes more than
## LYING_TOL model units (1.4 px) below the floor line. Hoshino's Vital_Death put her right shoulder 0.048 under it.
const LYING := ["down", "ko", "getup"]
const LYING_TOL := 0.01
## A guard stands on both feet: in GUARDS no layer lifts a foot more than FOOT_LIFT model units (4 fight px) above where
## the raw clip puts it. A tilt rolls the body over the rear foot and lifts the front one: 1.8 px a degree on Hoshino's
## 104 px stance, so her old 6 degree lean back lifted it 11.
const GUARDS := ["block", "block_low"]
const FOOT_LIFT := 0.03
## A state anim with a constant "turn" undoes a clip set that faces another way, so its hips (pelvis forward, horizontal,
## every layer on, facing yaw off) average idle's heading over the span within TURN_TOL degrees. Hina's Vital_Panic
## faces 50 degrees off her Normal set; turned 40, her hit and air hit showed the back of her head facing left.
const TURN_TOL := 5.0
## Through the EX the projected muzzle moves at most EX_STEP fight px a tick, both facings: the cut-in freeze holds the
## first pose, so a jump of a third of her height on the next ticks reads as a cut. Hina's Exs drops the gun 190 px between
## 0.70 and 0.85 s, which a fit over her whole 8-tick startup showed as one 139 px jump.
const EX_STEP := 100.0
## Moving toward or away from the foe, and through the whole EX, the gun points at the foe on every frame, not only on
## fire frames. Hoshino's Move_Ing turns her body 53 degrees past her Normal set, which put her muzzle behind her feet
## facing left, and the end of her Exs clip swings the gun behind her (to -131 px facing right).
const AIMED_ANIMS := ["walk", "walk_back", "dash", "dash_air", "dash_air_back", "glide", "intro_run", "intro_stop"]
const STATE_ANIMS := ["idle", "walk", "walk_back", "dash", "backdash", "jump", "crouch", "block", "block_low", "block_air",
	"hit", "airhit", "down", "getup", "ko", "win", "intro", "intro_idle", "intro_cut", "intro_run", "intro_stop"]
## The run-in's anims in play order and the ticks of each. The stage entry no longer runs in (the descriptors stay dormant in
## sd.json), but they still have to hold together.
const ENTRY := [["intro_run", 57], ["intro_stop", 40], ["intro", 60]]
## The stage entry's anims: the fighter's own solo shot (96 ticks) and the wide block's ready pose. intro_cut is held to CUT_FACE, a
## stricter limit than the 90 degrees every other intro anim gets, because it is shown in a close-up.
const CUTS := [["intro_cut", 96], ["intro", 60]]
const CUT_FACE := 82.0
const ENTRY_SHOT := 96   # the solo shot's ticks (Arena.INTRO_SHOT)
const ENTRY_PAN := 36    # the pan between the shots (Arena.INTRO_PAN)
const ENTRY_WIDE := 229  # the first tick of the wide block (Arena.INTRO_WIDE_AT)
const ENTRY_READY := 272 # the tick the ready beat starts on in the entry (360 - Arena.INTRO_BEAT_END - 60)
## Anims only some fighters have, asked for through the kit's kv["anim"] (sd_config.gd): the others must lack them.
const KIT_ANIMS := {"hina": ["dash_air", "dash_air_back", "glide"]}
## What a fighter wears while a thrower carries it (the throw's carry dict names it); every SD fighter needs it.
const CARRY_ANIMS := ["carried"]
## Move keys every SD kit shares; each needs its own descriptor. Other kit keys play move_default.
const SHARED_MOVES := ["5L", "5H", "2L", "2H", "jL", "jH", "skill", "skill_air", "ex", "super", "super_down", "close_L", "close_H", "6L", "6H", "throw"]
## Chains the sim can produce, stepped tick by tick with blending on. [anim, ticks, opts]: anim is a state or
## "attack:<move key>" (ticks ignored: the whole move); "keep_sf" carries the state frame over (the key changes while
## sf keeps counting), "flip" turns the fighter around on that step (landing).
const SEQUENCES := [
	[["idle", 10], ["attack:5L", 0], ["attack:5L", 0], ["idle", 10]],
	[["crouch", 10], ["attack:2L", 0], ["crouch", 10]],
	[["walk", 12], ["walk_back", 12, {"keep_sf": true}], ["jump", 40], ["idle", 10, {"flip": true}]],
	[["jump", 12], ["attack:jL", 0], ["jump", 10], ["idle", 8]],
	[["hit", 16], ["hit", 10], ["idle", 10]],
	[["airhit", 20], ["down", 38], ["getup", 12], ["idle", 10]],
	[["block", 8], ["block_low", 8, {"keep_sf": true}], ["idle", 8]],
	[["jump", 12], ["block_air", 8], ["jump", 10], ["idle", 8]],
	[["jump", 12], ["dash_air", 16], ["glide", 20], ["jump", 10], ["idle", 8]],
	[["jump", 12], ["dash_air_back", 16], ["jump", 10], ["idle", 8]],
	[["intro_run", 57], ["intro_stop", 40], ["intro", 60], ["dash", 16], ["backdash", 18], ["idle", 8]],
	[["idle", 60], ["intro_cut", 96], ["idle", 120], ["intro", 60], ["dash", 16], ["backdash", 18], ["idle", 8]],
	[["idle", 6], ["attack:skill", 0], ["idle", 6]],
	[["idle", 6], ["attack:ex", 0], ["idle", 6]],
]
## The actor with its grip arm bent inside pose(), just before the re-attach, where later layers move the arm.
## gap is how far the bend pulled the gun off the hand, in world units.
const BENT_ARM := """extends "res://scripts/models/sd_fighter_actor.gd"
var gap := 0.0
func reattach_weapon() -> void:
	var arm := grip_skeleton.get_bone_parent(grip_skeleton.get_bone_parent(grip_bone))
	grip_skeleton.set_bone_pose_rotation(arm, grip_skeleton.get_bone_pose_rotation(arm) * Quaternion(Vector3.RIGHT, 0.6))
	var world := grip_skeleton.global_transform
	gap = (world * grip_skeleton.get_bone_global_pose(grip_bone) * grip_offset).origin.distance_to((world * grip_skeleton.get_bone_global_pose(weapon_bone)).origin)
	super()
"""

var failures: Array[String] = []
var checks := 0
var game: Node
var screen: Node
var states: Dictionary
var config: Script
var actor_script: Script
var measure_tool: Script
var max_drift := {}
var floor_report := {}
var spawn_report: Array[String] = []
var rect_report: Array[String] = []
var measured := {}
var aim_report: Array[String] = []
var hips_report := {}
var slide_report: Array[String] = []
var lift_report := {}
var face_report: Array[String] = []
var steady_report: Array[String] = []
var turn_report: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		if failures.size() < 60:
			print("SD_CHECK FAIL ", label)
		failures.append(label)

func _run() -> void:
	create_timer(300.0).timeout.connect(_watchdog)
	await process_frame
	config = load("res://scripts/models/sd_config.gd")
	actor_script = load("res://scripts/models/sd_fighter_actor.gd")
	measure_tool = load("res://scripts/models/tools/sd_measure.gd")
	check(config != null, "scripts/models/sd_config.gd loads")
	var probe: Node = actor_script.new()
	check(probe.has_method("pose") and probe.has_method("reattach_weapon"), "actor exposes pose() and reattach_weapon()")
	check("blending" in probe and "blend_w" in probe and "layer" in probe and "sampled" in probe, "actor exposes blending, blend_w, layer and sampled")
	probe.free()
	# prints one expected ERROR line
	config._cache["zzz_missing_model"] = {"model": "res://assets/ba/sd/zzz/Missing.glb"}
	check(not actor_script.supports({"key": "zzz_missing_model"}), "an sd.json whose model file is missing falls back to the 2D view")
	config._cache.erase("zzz_missing_model")
	var bent_script := GDScript.new()
	bent_script.source_code = BENT_ARM
	check(bent_script.reload() == OK, "bent-arm test actor compiles")
	if not failures.is_empty():
		_finish()
		return
	game = root.get_node("Game")
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	# every roster fighter with an sd.json, two per fight; an odd one out fights the first again
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
		game.session.players[0]["special"] = 10017
		game.session.players[1]["special"] = 10017
		await game.go("fight", {}, "cut")
		screen = game.stack.back()
		states = screen.f1.get_script().S
		screen.set_physics_process(false)
		screen.phase = "fight"
		for fighter in screen.fighters:
			fighter.set_process(false)
		for fighter in screen.fighters:
			var key := String(fighter.data["key"])
			if tested.has(key):
				continue
			tested[key] = true
			var cfg: Dictionary = config.of(key)
			check(not cfg.is_empty(), "sd.json exists for " + key)
			check(fighter.view.sd_mode, "fighter_view picks the SD actor from sd.json: " + key)
			if cfg.is_empty() or not fighter.view.sd_mode:
				continue
			# lives until exit: freeing it mid-run printed renderer "material is null" errors
			var ref: Node = actor_script.new()
			ref.visible = false
			ref.blending = false
			root.add_child(ref)
			ref.setup(fighter.data)
			var bent: Node = bent_script.new()
			bent.visible = false
			root.add_child(bent)
			bent.setup(fighter.data)
			bent.blending = false
			var actor: Node = fighter.view.sd_actor
			_check_setup(fighter, cfg)
			_check_config(fighter, actor, cfg)
			if tested.size() == 1:
				_features(fighter, ref)
			actor.blending = false
			_sockets_current(fighter, actor)
			_muzzles(fighter, actor)
			_sweep(fighter, actor, ref, cfg)
			_aim(fighter, actor)
			_steady(fighter, actor)
			_intro_face(fighter, actor, cfg)
			_turns(fighter, actor, cfg)
			_ex_steps(fighter, actor)
			_held(fighter, actor, ref, cfg)
			_gun_fx(fighter, actor)
			await _edges(fighter, actor, cfg)
			actor.blending = true
			_sequences(fighter, actor, ref)
			_slides(fighter, actor)
			_reactions(fighter, actor)
			_sync(fighter, actor, ref)
			_stride_clock(fighter, actor, cfg)
			_backdash_hop(fighter, actor, cfg)
			_pose_reattaches(bent, ref, cfg)
			_source_clips(actor, cfg)
			_mouths(actor)
			_hitstop_and_ex_end(fighter)
		_draw_order()
		await _ex_freeze()
	print("SD_ANIM tested ", tested.keys())
	_finish()

func _finish() -> void:
	print("SD_ANIM drift max (model units / deg): ", JSON.stringify(max_drift))
	print("SD_MUZZLE projected minus gameplay muzzle per fire frame, px: frame[xticks] dx f+1/f-1 dy (want |dx| <= %.0f, |dy| <= %.0f)" % [MUZZLE_DX, MUZZLE_DY])
	for line in spawn_report:
		print("SD_MUZZLE ", line)
	for line in rect_report:
		print("SD_RECT ", line)
	print("SD_AIM barrel/line of fire per shot tick, deg (+ down, facing right): mf[:charge] barrel f+1/f-1, want +- tol")
	for line in aim_report:
		print("SD_AIM ", line)
	print("SD_ANIM floor (lowest foot min..max per ground anim, against the sd.json ankle): ", JSON.stringify(floor_report))
	print("SD_FEET highest foot lift over the raw clip per guard, model units (tol %.3f): %s" % [FOOT_LIFT, JSON.stringify(lift_report)])
	for line in face_report:
		print("SD_FACE head turn from the camera, deg: ", line)
	for line in steady_report:
		print("SD_STEADY gun pulled back between shots, model units (tol %.3f): %s" % [RECOIL, line])
	print("SD_TURN hips heading off idle's per turned state anim, deg (tol %.0f): %s" % [TURN_TOL, ", ".join(turn_report)])
	print("SD_HIPS widest hips offset from idle's, px, f+1/f-1: ", JSON.stringify(hips_report))
	for line in slide_report:
		print("SD_SLIDE ", line)
	print("SD_ANIM ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	if game:
		root.get_node("Bgm").stop()
	await create_timer(0.3).timeout
	quit(0 if failures.is_empty() else 1)

func _watchdog() -> void:
	print("SD_ANIM FAIL watchdog timeout")
	quit(3)

# ── setup, materials, config ─────────────────────────────────────────────────

func _check_setup(fighter: Node, cfg: Dictionary) -> void:
	var actor: Node = fighter.view.sd_actor
	fighter.state = states.IDLE
	fighter.sf = 33
	fighter.view.step(1.0 / 60.0)
	check(fighter.body.texture is ViewportTexture, "live 3D viewport texture: " + String(fighter.data["key"]))
	check(actor.player.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL, "manual animation callback")
	check(not actor.muzzle_socket.is_empty(), "muzzle socket bound to the weapon bone: " + str(cfg["muzzle"]))
	check(fighter.view._shield_fx != bool(cfg["hide_shield_fx"]), "shield dome and glow follow sd.json hide_shield_fx")
	for part in cfg["hide"]:
		var n := 0
		for mesh in actor.meshes:
			if String(part) in String(mesh.name):
				n += 1
		check(n > 0, "%s: hide pattern '%s' matches a mesh, so the hidden-mesh checks test something" % [String(fighter.data["key"]), part])
	for mesh in actor.meshes:
		for i in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(i) as ShaderMaterial
			check(material != null, "toon surface material on " + String(mesh.name))
			if material and ("mouth" in material.resource_name.to_lower() or "eyemouth" in material.resource_name.to_lower()):
				check(bool(material.get_shader_parameter("alpha_mask")), "mouth/eye alpha mask retained")

func _check_config(fighter: Node, actor: Node, cfg: Dictionary) -> void:
	var key: String = String(cfg["model"]).get_file()
	for name in STATE_ANIMS:
		check(cfg["anims"].has(name), key + ": sd.json maps state anim " + name)
	for name in CARRY_ANIMS:
		check(cfg["anims"].has(name), key + ": sd.json maps the carried anim " + name)
	for fighter_key in KIT_ANIMS:
		for name in KIT_ANIMS[fighter_key]:
			check(cfg["anims"].has(name) == (String(fighter.data["key"]) == fighter_key), "%s: only %s has the kit anim %s" % [key, fighter_key, name])
	for name in SHARED_MOVES:
		check(cfg["moves"].has(name), key + ": sd.json maps shared move " + name)
	for name in cfg["moves"]:
		check(name in SHARED_MOVES, key + ": only shared moves have descriptors, the rest play move_default: " + name)
	var descriptors: Array = cfg["anims"].values() + cfg["moves"].values() + [cfg["move_default"]]
	var sk := _grip_skeleton(actor, cfg)
	for d in descriptors:
		for p in d.get("phases", [d]):
			var m: Dictionary = d.merged(p, true)
			var clip := String(m.get("clip", ""))
			check(actor.player.has_animation(clip), key + ": clip exists " + clip)
			if actor.player.has_animation(clip):
				_check_window(m, actor.player.get_animation(clip).length, key + " " + clip, ["from", "to"])
			for o in m.get("overlays", []):
				var oclip := String(o["clip"])
				check(actor.player.has_animation(oclip), key + ": overlay clip exists " + oclip)
				if actor.player.has_animation(oclip):
					_check_window(o, actor.player.get_animation(oclip).length, key + " overlay " + oclip, ["at", "from", "to"])
				var hits := 0
				for i in sk.get_bone_count():
					for g in o["bones"]:
						if sk.get_bone_name(i).match(String(g)):
							hits += 1
				check(hits > 0, key + ": overlay bones %s match bones" % str(o["bones"]))
		if d.has("phases"):
			for p in d["phases"].slice(0, -1):
				check(p.has("over"), key + ": every phase but the last has an over")
	check(sk != null, key + ": grip " + String(cfg["bones"]["grip"]) + " and weapon bone share a skeleton")
	# fighter.gd takes hurt_crouch_h for a move only when move.crouch is set, as the default kit's 2L and 2H set it
	for mk in ["2L", "2H"]:
		check(bool(fighter.moves[mk].get("crouch", false)), "%s: %s is a crouching move (move.crouch), like the default kit's" % [key, mk])
	# a move with no melee rect hits only with its rounds, so each leaves inside its active window; Hina's skill_air fired
	# its fifth round on its first recovery frame
	for mk in fighter.moves:
		var m: Dictionary = fighter.moves[mk]
		if not m["hit"].is_empty():
			continue
		var first := int(m["startup"])
		var last := first + int(m["active"]) - 1
		for sp in m["spawns"]:
			check(int(sp["frame"]) >= first and int(sp["frame"]) <= last, "%s: %s fires its frame %d round inside its active window %d..%d" % [key, mk, int(sp["frame"]), first, last])
	for mk in fighter.moves:
		var blend := int(cfg["moves"].get(mk, cfg["move_default"]).get("blend", 3))
		check(blend <= int(fighter.moves[mk]["startup"]), "%s: %s blend %d fits inside its startup %d" % [key, mk, blend, int(fighter.moves[mk]["startup"])])

## Clip times a descriptor names (from, to, an overlay's at) lie inside the clip.
func _check_window(d: Dictionary, length: float, tag: String, keys: Array) -> void:
	for k in keys:
		if d.has(k):
			check(float(d[k]) >= 0.0 and float(d[k]) <= length + 1e-4, "%s: %s %.3f lies inside the clip (0..%.3f)" % [tag, k, float(d[k]), length])

## assets/ba/sd/<key>/sockets.json is what tools/sd_measure.sh writes for today's model, sd.json and kit frames.
func _sockets_current(fighter: Node, actor: Node) -> void:
	var path := "res://assets/ba/sd/%s/sockets.json" % String(fighter.data["key"])
	var have := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var data: Dictionary = measure_tool.measure(fighter.moves, actor)
	measured[String(fighter.data["key"])] = data
	check(have == measure_tool.encode(data), path + " is current (re-run tools/sd_measure.sh)")

## Every tick a kit spawn or shot fires from (measure_tool.ticks()), both facings: the projected muzzle lies within
## MUZZLE_DX / MUZZLE_DY of the gameplay muzzle. Gun normals' rect starts against the measured muzzle are reported.
func _muzzles(fighter: Node, actor: Node) -> void:
	var name := String(fighter.data["key"])
	var keys: Array = fighter.moves.keys()
	keys.sort()
	for key in keys:
		var move: Dictionary = fighter.moves[key]
		var tag := "%s %s" % [name, key]
		var at: Dictionary = measure_tool.ticks(move)
		var frames: Array = at.keys()
		frames.sort()
		var cells: Array[String] = []
		for fr in frames:
			var offsets: Array = []
			for sp in move["spawns"]:
				if int(sp["frame"]) == fr and not sp.get("at_foe", false) and not sp.get("rel_owner", false):
					offsets.append([sp["offset"], sp.get("offset_left", sp["offset"])])
			if fr in move.get("shots", []) and fighter.kit.has_method("_muzzle"):
				var m: Vector2 = fighter.kit._muzzle(key, fr)
				offsets.append([m, m])
			var dx := {1: [INF, -INF], -1: [INF, -INF]}
			var dy := [INF, -INF]
			for t in at[fr]:
				for face in [1, -1]:
					actor.pose("attack", 0, key, move, t.x, t.y, face)
					var seen: Vector2 = actor.anchor_local("muzzle") * Vector2(face, 1)
					for o in offsets:
						var d: Vector2 = seen - Vector2(o[0 if face > 0 else 1])
						dx[face] = [minf(dx[face][0], d.x), maxf(dx[face][1], d.x)]
						dy = [minf(dy[0], d.y), maxf(dy[1], d.y)]
						check(absf(d.x) <= MUZZLE_DX and absf(d.y) <= MUZZLE_DY, "%s frame %d tick %s f%d: the projected muzzle %s lies within %.0f/%.0f px of the gameplay muzzle %s (dx %.1f dy %.1f)" % [tag, fr, str(t), face, str(seen.round()), MUZZLE_DX, MUZZLE_DY, str(o[0 if face > 0 else 1]), d.x, d.y])
			cells.append("%d%s %s/%s %s" % [fr, "x%d" % at[fr].size() if at[fr].size() > 1 else "", _span_text(dx[1]), _span_text(dx[-1]), _span_text(dy)])
		if not cells.is_empty():
			spawn_report.append("%s | %s" % [tag, " | ".join(cells)])
		var shots: Array = move.get("shots", [])
		if not move.get("swish", true) and not move["hit"].is_empty() and not shots.is_empty():
			var start: float = Rect2(move["hit"]["rect"]).position.x
			var mx: float = measured[name]["muzzle"][key][0]["sym"][0]
			rect_report.append("%s: rect starts at x %.0f, measured muzzle x %.1f at frame %d (%+.0f)%s" % [tag, start, mx, int(shots[0]), start - mx, "" if absf(start - mx) <= RECT_START else "  MISMATCH > %.0f" % RECT_START])
			if name not in RECT_FRONT_EDGE:
				check(absf(start - mx) <= RECT_START, "%s: the hit rect starts within %.0f px of the measured muzzle (%+.0f)" % [tag, RECT_START, start - mx])

func _span_text(r: Array) -> String:
	return "%+.0f" % r[0] if roundi(r[0]) == roundi(r[1]) else "%+.0f..%+.0f" % [r[0], r[1]]

# ── descriptor features on a synthetic config ────────────────────────────────

## Each descriptor feature on its own, against the raw clips: reverse, fit, hold, phases, overlays, tilt, turn, crouch, blend.
func _features(fighter: Node, ref: Node) -> void:
	var base: Dictionary = config.of(String(fighter.data["key"]))
	var cfg: Dictionary = base.duplicate(true)
	var left_arm := ["Bip001 L UpperArm", "Bip001 L Forearm"]
	cfg["anims"] = {
		"idle": {"clip": "Normal_Idle"},
		"rev": {"clip": "Move_Ing", "speed": -0.5},
		"fitrev": {"clip": "Vital_Death", "mode": "fit", "speed": -1, "from": 0.5, "to": 1.5, "frames": 10},
		"hold": {"clip": "Vital_Death", "mode": "hold", "from": 0.2, "to": 1.0},
		"phased": {"phases": [{"clip": "Victory_Start", "mode": "hold", "over": 20}, {"clip": "Victory_End"}]},
		"overlay": {"clip": "Normal_Idle", "overlays": [{"clip": "Exs", "at": 2.0, "bones": left_arm + ["Bip001 R *"]}]},
		"tilt_feet": {"clip": "Normal_Idle", "tilt": [[0.0, 0.0], [1.0, 12.0]], "frames": 10},
		"tilt_back": {"clip": "Normal_Idle", "tilt": -12},
		"tilt_hips": {"clip": "Normal_Idle", "tilt": 30, "tilt_pivot": "hips"},
		"turn": {"clip": "Normal_Idle", "turn": 40},
		"crouch": {"clip": "Normal_Idle", "crouch": 0.3},
		"snap": {"clip": "Victory_Start", "blend": 0},
		"past": {"clip": "Normal_Idle", "mode": "hold", "from": 99.0, "to": 99.0},
	}
	cfg["moves"] = {"held": {"phases": [{"clip": "Normal_Attack_Start", "mode": "fit", "over": "startup"},
		{"clip": "Normal_Attack_Ing", "over": "active"}, {"clip": "Normal_Attack_End", "mode": "fit"}]}}
	config._cache["zzz_features"] = cfg
	var a: Node = actor_script.new()
	a.visible = false
	root.add_child(a)
	a.setup({"key": "zzz_features"})
	a.blending = false
	var plain: Node = actor_script.new()
	plain.visible = false
	root.add_child(plain)
	plain.setup({"key": "zzz_features"})
	plain.blending = false
	var length: float = a.player.get_animation("Move_Ing").length
	a.pose("rev", 6, "", {}, 0, 0, 1)
	check(is_equal_approx(a.current_time, length - 0.05), "negative speed loops backwards (%.3f)" % a.current_time)
	a.pose("fitrev", 0, "", {}, 0, 0, 1)
	var t0: float = a.current_time
	a.pose("fitrev", 10, "", {}, 0, 0, 1)
	check(is_equal_approx(t0, 1.5) and is_equal_approx(a.current_time, 0.5), "reversed fit runs to..from over frames (%.2f -> %.2f)" % [t0, a.current_time])
	a.pose("hold", 300, "", {}, 0, 0, 1)
	check(is_equal_approx(a.current_time, 1.0), "hold stops at to")
	a.pose("past", 0, "", {}, 0, 0, 1)
	check(is_equal_approx(a.sampled[0][1], 99.0) and a.current_time <= a.player.get_animation("Normal_Idle").length, "sampled keeps the asked time past the clip end (sample_clip clamps only the shown pose)")
	a.pose("phased", 19, "", {}, 0, 0, 1)
	var p0: String = a.current_clip
	a.pose("phased", 25, "", {}, 0, 0, 1)
	check(p0 == "Victory_Start" and a.current_clip == "Victory_End" and is_equal_approx(a.current_time, 5.0 / 60.0), "state phases switch after their over frames")
	# while the button is down the sim parks mf at hold.at - 1 and counts charge_t from 1
	var move := {"frames": 30, "startup": 8, "active": 6, "recovery": 16, "hold": {"btn": "skill", "at": 8, "max": 20}}
	a.pose("attack", 0, "held", move, 7, 1, 1)
	check(a.current_clip == "Normal_Attack_Ing" and is_equal_approx(a.current_time, 0.0), "the first held tick shows the phase at hold.at (%s %.3f)" % [a.current_clip, a.current_time])
	a.pose("attack", 0, "held", move, 7, 13, 1)
	check(a.current_clip == "Normal_Attack_Ing" and is_equal_approx(a.current_time, 12.0 / 60.0), "a held move keeps looping its active phase")
	a.pose("attack", 0, "held", move, 8, 13, 1)
	check(a.current_clip == "Normal_Attack_Ing" and is_equal_approx(a.current_time, 13.0 / 60.0), "release carries on one frame past the hold")
	check(a.anim_name == "moves/held", "the actor reports the move descriptor it used")
	a.pose("attack", 0, "zzz_unknown", move, 8, 0, 1)
	check(a.anim_name == "move_default", "unknown move keys fall back to move_default")
	# overlay: masked bones carry the overlay clip, the grip arm and everything else the base clip
	a.pose("overlay", 30, "", {}, 0, 0, 1)
	var sk: Skeleton3D = a.grip_skeleton
	ref.sample_clip("Exs", 2.0)
	check(_same_local(a, ref, sk.find_bone("Bip001 L Forearm")), "overlay bones follow the overlay clip")
	ref.sample_clip("Normal_Idle", a.current_time)
	var arm := sk.get_bone_parent(a.grip_bone)
	check(_same_local(a, ref, a.grip_bone) and _same_local(a, ref, arm), "overlays never move the grip arm (Bip001 R * matched it)")
	check(_same_local(a, ref, sk.find_bone("Bip001 L Thigh")), "unmasked bones keep the base clip")
	check(a.sampled.size() == 2 and a.sampled[1][0] == "Exs", "sampled lists the base clip and each overlay")
	# whole-model layers stay inside the facing yaw
	for face in [1, -1]:
		a.pose("idle", 0, "", {}, 0, 0, face)
		var hips_idle := _bone_world(a, sk, a.pelvis)
		var feet_idle := _feet_world(a)
		var pivot_idle: Transform3D = a.pivot.transform
		a.pose("tilt_feet", 10, "", {}, 0, 0, face)
		var dx: float = (_bone_world(a, sk, a.pelvis) - hips_idle).x * float(face)
		check(dx > 0.03, "f%d: positive tilt leans toward the facing side (pelvis dx %.3f)" % [face, dx])
		check(_lowest_foot(a, base) >= float(base["ankle"]) - 0.01, "f%d: tilt about the feet keeps them on the floor (%.3f)" % [face, _lowest_foot(a, base)])
		a.pose("tilt_feet", 5, "", {}, 0, 0, face)
		check(absf(rad_to_deg(a.layer.basis.get_euler().x) - 6.0) < 0.1, "keyframed layers interpolate over the span")
		a.pose("tilt_back", 0, "", {}, 0, 0, face)
		check((_bone_world(a, sk, a.pelvis) - hips_idle).x * float(face) < -0.03 and _lowest_foot(a, base) >= float(base["ankle"]) - 0.01, "f%d: negative tilt leans back, feet on the floor" % face)
		a.pose("tilt_hips", 0, "", {}, 0, 0, face)
		check(_bone_world(a, sk, a.pelvis).distance_to(hips_idle) < 0.005, "f%d: tilt about the hips keeps the pelvis in place" % face)
		a.pose("turn", 0, "", {}, 0, 0, face)
		check(a.layer.basis.is_equal_approx(Basis(Vector3.UP, deg_to_rad(40.0))) and a.pivot.transform.is_equal_approx(pivot_idle * a.layer), "f%d: turn is an extra yaw inside the facing yaw" % face)
		check(_bone_world(a, sk, a.pelvis).distance_to(hips_idle) < 0.005, "f%d: turn spins the body about its pelvis, which stays put (%.4f)" % [face, _bone_world(a, sk, a.pelvis).distance_to(hips_idle)])
		a.pose("crouch", 0, "", {}, 0, 0, face)
		var drop: float = hips_idle.y - _bone_world(a, sk, a.pelvis).y
		check(absf(drop - 0.3) < 0.005, "f%d: crouch drops the pelvis by its value (%.3f)" % [face, drop])
		var feet := _feet_world(a)
		for i in feet.size():
			check(feet[i].distance_to(feet_idle[i]) < 0.005, "f%d: crouch IK keeps each foot where the clip put it (%.4f)" % [face, feet[i].distance_to(feet_idle[i])])
		var forward: Vector3 = a.pivot.global_transform.basis * Vector3.BACK
		for leg in a.legs:
			var hip := _bone_world(a, sk, leg[0])
			var line := (_bone_world(a, sk, leg[2]) - hip).normalized()
			var bend := _bone_world(a, sk, leg[1]) - hip
			bend -= line * bend.dot(line)
			var ahead := (forward - line * forward.dot(line)).normalized()
			check(bend.normalized().dot(ahead) > 0.9, "f%d: crouch IK bends the knee toward model forward (%.2f)" % [face, bend.normalized().dot(ahead)])
	# crossfade
	a.blending = true
	a.pose("idle", 0, "", {}, 0, 0, 1)
	a.pose("idle", 40, "", {}, 0, 0, 1)
	check(a.blend_w == 1.0, "no blend without a change")
	a.pose("crouch", 0, "", {}, 0, 0, 1)
	var blended := _pose_sig(a, base)
	check(is_equal_approx(a.blend_w, 0.25), "the first tick of a new anim shows 1/4 of it (blend 3)")
	plain.pose("crouch", 0, "", {}, 0, 0, 1)
	check(absf(blended - _pose_sig(plain, base)) > 0.01, "a blended tick differs from the unblended sample")
	a.pose("crouch", 1, "", {}, 0, 0, 1)
	a.pose("crouch", 1, "", {}, 0, 0, 1)
	check(is_equal_approx(a.blend_w, 0.5), "repeated samples of one tick (hitstop, freeze) hold the blend")
	a.pose("crouch", 3, "", {}, 0, 0, 1)
	plain.pose("crouch", 3, "", {}, 0, 0, 1)
	check(a.blend_w == 1.0 and absf(_pose_sig(a, base) - _pose_sig(plain, base)) < 1e-4, "the blend reaches the new anim after 3 ticks")
	a.pose("crouch", 0, "", {}, 0, 0, 1)
	check(a.blend_w < 1.0, "a restart of the same anim (frame goes back) blends too")
	a.pose("snap", 0, "", {}, 0, 0, 1)
	check(a.blend_w == 1.0, "blend 0 snaps")
	a.blending = false
	a.pose("crouch", 0, "", {}, 0, 0, 1)
	check(a.blend_w == 1.0, "blending off snaps (preview, tests)")
	config._cache.erase("zzz_features")

func _same_local(a: Node, b: Node, bone: int) -> bool:
	var x: Transform3D = a.grip_skeleton.get_bone_pose(bone)
	var y: Transform3D = b.grip_skeleton.get_bone_pose(bone)
	return x.origin.distance_to(y.origin) < 1e-4 and x.basis.get_rotation_quaternion().angle_to(y.basis.get_rotation_quaternion()) < 1e-3

func _bone_world(a: Node, sk: Skeleton3D, bone: int) -> Vector3:
	return sk.global_transform * sk.get_bone_global_pose(bone).origin

func _feet_world(a: Node) -> Array:
	var list: Array = []
	for leg in a.legs:
		list.append(_bone_world(a, a.grip_skeleton, leg[2]))
	return list

# ── every anim, both facings ─────────────────────────────────────────────────

func _sweep(fighter: Node, actor: Node, ref: Node, cfg: Dictionary) -> void:
	var runs: Array = []
	for name in cfg["anims"]:
		runs.append([name, "", {}, range(0, 240, 4)])
	for key in fighter.moves:
		runs.append(["attack", key, fighter.moves[key], range(-1, int(fighter.moves[key]["frames"]) - 1)])
	var idle_hips := {}
	for face in [1, -1]:
		var worst := 0.0
		for frame in range(0, 240, 4):
			actor.pose("idle", frame, "", {}, 0, 0, face)
			if absf(_hips_x(actor)) > absf(worst):
				worst = _hips_x(actor)
		check(absf(worst) <= IDLE_HIPS, "%s idle f%d: the hips stand on the feet origin, the facing yaw's axis (off by %.1f px, tol %.0f)" % [String(fighter.data["key"]), face, worst, IDLE_HIPS])
		actor.pose("idle", 0, "", {}, 0, 0, face)
		idle_hips[face] = _hips_x(actor)
	for run in runs:
		var anim: String = run[0]
		var move: Dictionary = run[2]
		var label: String = anim if anim != "attack" else "move " + String(run[1])
		var ground: bool = anim not in NO_FLOOR and not (anim == "attack" and bool(move.get("air", false)))
		var lowest := INF
		var highest := -INF
		var fire := {}
		for sp in move.get("spawns", []):
			if not sp.get("at_foe", false) and not sp.get("rel_owner", false):
				fire[int(sp["frame"])] = true
		for f in move.get("shots", []):
			fire[int(f)] = true
		var hips_off := {1: 0.0, -1: 0.0}
		for frame in run[3]:
			var right := {}
			for face in [1, -1]:
				if anim == "attack":
					actor.pose(anim, 0, run[1], move, frame, 0, face)
				else:
					actor.pose(anim, frame, "", {}, 0, 0, face)
				var tag := "%s %s f%d frame %d" % [String(fighter.data["key"]), label, face, frame]
				var want: String = anim if anim != "attack" else ("moves/" + String(run[1]) if cfg["moves"].has(run[1]) else "move_default")
				check(actor.anim_name == want, tag + ": reports descriptor " + want + " (got " + String(actor.anim_name) + ")")
				_check_sample(actor, ref, cfg, tag)
				var foot := _lowest_foot(actor, cfg)
				if ground:
					_check_floor(actor, ref, cfg, tag)
				if anim in LYING:
					_check_lying(actor, cfg, tag)
				if anim in GUARDS:
					var lift := _foot_lift(actor, ref)
					var lift_key := "%s %s" % [String(fighter.data["key"]), anim]
					lift_report[lift_key] = maxf(float(lift_report.get(lift_key, -INF)), snappedf(lift, 0.001))
					check(lift <= FOOT_LIFT, tag + ": both feet stay planted, no foot lifted %.3f above the raw clip's (tol %.3f)" % [lift, FOOT_LIFT])
				lowest = minf(lowest, foot)
				highest = maxf(highest, foot)
				var muzzle: Vector2 = actor.anchor_local("muzzle")
				var dx := _hips_x(actor) - float(idle_hips[face])
				if absf(dx) > absf(hips_off[face]):
					hips_off[face] = dx
				if fire.has(frame) or anim in AIMED_ANIMS or (anim == "attack" and run[1] == "ex"):
					check(muzzle.x * float(face) > 0.0, tag + ": muzzle on the facing side of the feet " + str(muzzle))
				if face == 1:
					right = {"sig": _pose_sig(actor, cfg), "pivot": actor.pivot.transform}
				else:
					_check_facing(actor, cfg, right, tag)
		if ground:
			check(absf(lowest - float(cfg["ankle"])) <= FLOOR_TOL, "%s %s: feet touch the floor (lowest %.4f)" % [String(fighter.data["key"]), label, lowest])
		floor_report["%s %s" % [String(fighter.data["key"]), label]] = "%s%.3f..%.3f" % ["" if ground else "(exempt) ", lowest, highest]
		var hips_tol: float = HIPS_ALLOW.get(anim if anim != "attack" else String(run[1]), HIPS_TOL)
		for face in [1, -1]:
			if ground and anim not in HIPS_EXEMPT:
				check(absf(hips_off[face]) <= hips_tol, "%s %s f%d: the hips stay over the feet like idle's (off by %.0f px, tol %.0f)" % [String(fighter.data["key"]), label, face, hips_off[face], hips_tol])
		hips_report["%s %s" % [String(fighter.data["key"]), label]] = "%s%+.0f/%+.0f" % ["" if ground and anim not in HIPS_EXEMPT else "(exempt) ", hips_off[1], hips_off[-1]]

## The pelvis bone's screen x relative to the feet origin, fight px.
func _hips_x(actor: Node) -> float:
	var sk: Skeleton3D = actor.grip_skeleton
	return ((actor.camera.unproject_position(sk.global_transform * sk.get_bone_global_pose(actor.pelvis).origin) + actor.body.offset) * actor.body.scale).x

## Every shot and spawn tick of every kit move, both facings: the barrel points along the line of fire (see AIM_TOL).
## Spawns fire along their velocity (a volley: the mean of its rounds); a held move's stream ticks are the hold ticks it
## fires on, and a spawn after the hold is sampled at each charge it can fire with. Shots that spawn nothing are gun
## normals: the gameplay muzzle (the kit's _muzzle(), else the projected muzzle averaged over both facings) to the
## centre of the hit rect.
func _aim(fighter: Node, actor: Node) -> void:
	var name := String(fighter.data["key"])
	for key in fighter.moves:
		var move: Dictionary = fighter.moves[key]
		var hold: Dictionary = move.get("hold", {})
		var ticks := {}
		for f in move.get("shots", []):
			ticks[Vector2i(int(f), 0)] = Vector2.ZERO
		for sp in move["spawns"]:
			if sp.get("at_foe", false) or sp.get("rel_owner", false):
				continue
			var at: Array = []
			if sp.get("hold_fire", false):
				for c in range(1, int(hold["max"]) + 1):
					if c % int(hold["fire_every"]) == 1:
						at.append(Vector2i(int(hold["at"]) - 1, c))
			elif not hold.is_empty() and int(sp["frame"]) >= int(hold["at"]):
				for c in [0, int(sp.get("min_charge", 0)), int(hold["max"])]:
					if c >= int(sp.get("min_charge", 0)) and c <= int(sp.get("max_charge", 99999)):
						at.append(Vector2i(int(sp["frame"]), c))
			else:
				at.append(Vector2i(int(sp["frame"]), 0))
			for t in at:
				ticks[t] = Vector2(ticks.get(t, Vector2.ZERO)) + Vector2(sp["vel"]).normalized()
		if ticks.is_empty():
			continue
		var order: Array = ticks.keys()
		order.sort_custom(func(a, b): return a.x * 1000 + a.y < b.x * 1000 + b.y)
		var cells: Array[String] = []
		for t in order:
			var seen := {}
			for face in [1, -1]:
				actor.pose("attack", 0, key, move, t.x, t.y, face)
				seen[face] = [_barrel(actor, face), actor.anchor_local("muzzle") * Vector2(face, 1)]
			var want := 0.0
			var tol := AIM_TOL
			if ticks[t] != Vector2.ZERO:
				want = rad_to_deg(Vector2(ticks[t]).angle())
			else:
				var r: Rect2 = move["hit"]["rect"]
				var muzzle: Vector2 = fighter.kit._muzzle(key, t.x) if fighter.kit.has_method("_muzzle") else (Vector2(seen[1][1]) + Vector2(seen[-1][1])) * 0.5
				var line := r.get_center() - muzzle
				var across := line.normalized().orthogonal()
				var radius := rad_to_deg(atan2(absf(across.x) * r.size.x * 0.5 + absf(across.y) * r.size.y * 0.5, line.length()))
				want = rad_to_deg(line.angle())
				tol = clampf(radius, AIM_TOL, AIM_ZONE_MAX)
			for face in [1, -1]:
				var err := absf(wrapf(float(seen[face][0]) - want, -180.0, 180.0))
				check(err <= tol, "%s move %s mf %d charge %d f%d: barrel %.1f along the line of fire %.1f (off %.1f, tol %.1f)" % [name, key, t.x, t.y, face, seen[face][0], want, err, tol])
			var level := _elevation(actor)
			# the clip's own gun is level and the layers (tilt, aim) do the aiming, so check it with the aim layer off
			actor.aim_enabled = false
			actor.pose("attack", 0, key, move, t.x, t.y, -1)
			var clip_level := _elevation(actor)
			actor.aim_enabled = true
			actor.pose("attack", 0, key, move, t.x, t.y, -1)
			# a clip authored aimed (tools/sd_author, sd.json "clip_aim") points its gun that many degrees down on its own
			var clip_aim := float(actor.cfg["moves"].get(key, {}).get("clip_aim", 0.0))
			check(absf(clip_level + clip_aim) <= LEVEL_TOL, "%s move %s mf %d charge %d: the clip's gun is level in the model's frame when it fires, past its clip_aim %.0f (%.1f, tol %.1f)" % [name, key, t.x, t.y, clip_aim, clip_level, LEVEL_TOL])
			var cell := "%d%s %+.0f/%+.0f want %+.0f+-%.0f lvl %+.0f" % [t.x, ":%d" % t.y if t.y > 0 else "", seen[1][0], seen[-1][0], want, tol, level]
			var lone: bool = t.x in move.get("shots", [])
			for s in move.get("shots", []):
				lone = lone and (int(s) == t.x or absi(int(s) - t.x) > KICK_FRAMES)
			if lone:
				var rise := -INF
				for k in range(1, KICK_FRAMES + 1):
					if t.x + k < int(move["frames"]) - 1:
						actor.pose("attack", 0, key, move, t.x + k, 0, 1)
						rise = maxf(rise, _elevation(actor) - level)
				check(rise >= KICK_DEG, "%s move %s mf %d: the recoil kick lifts the gun %.1f within %d frames of the lone shot (want %.1f)" % [name, key, t.x, rise, KICK_FRAMES, KICK_DEG])
				cell += " kick %+.0f" % rise
			cells.append(cell)
		aim_report.append("%s %s | %s" % [name, key, " | ".join(cells)])

## The gun holds steady between fire frames more than KICK_FRAMES + 1 apart (see RECOIL), in moves without a hold.
## Startup, recovery and closer shots are not covered.
func _steady(fighter: Node, actor: Node) -> void:
	var name := String(fighter.data["key"])
	for key in fighter.moves:
		var move: Dictionary = fighter.moves[key]
		if not move.get("hold", {}).is_empty():
			continue
		var fire := {}
		for f in move.get("shots", []):
			fire[int(f)] = true
		for sp in move["spawns"]:
			if not sp.get("at_foe", false) and not sp.get("rel_owner", false) and int(sp.get("min_charge", 0)) == 0:
				fire[int(sp["frame"])] = true
		var order: Array = fire.keys()
		order.sort()
		var worst := [0.0, -1]
		for i in order.size() - 1:
			for f in range(int(order[i]) + 1, int(order[i + 1]) - KICK_FRAMES):
				var at := _gun(actor, key, move, f)
				for k in range(1, KICK_FRAMES + 1):
					var back: float = -(_gun(actor, key, move, f + k)[0] - at[0]).dot(at[1])
					if back > worst[0]:
						worst = [back, f]
		if worst[1] >= 0:
			steady_report.append("%s %s: widest pull back %.3f from mf %d" % [name, key, worst[0], worst[1]])
			check(worst[0] < RECOIL, "%s move %s mf %d: the gun holds steady between shots (pulled back %.3f within %d frames, tol %.3f)" % [name, key, worst[1], worst[0], KICK_FRAMES, RECOIL])

## [weapon bone origin, barrel direction] in the model's own frame at move frame `mf`, facing right.
func _gun(actor: Node, key: String, move: Dictionary, mf: int) -> Array:
	actor.pose("attack", 0, key, move, mf, 0, 1)
	var sk: Skeleton3D = actor.grip_skeleton
	var to_model: Transform3D = actor.pivot.global_transform.affine_inverse() * sk.global_transform
	var origin: Vector3 = to_model * sk.get_bone_global_pose(actor.weapon_bone).origin
	var tip: Vector3 = to_model * (sk.get_bone_global_pose(actor.muzzle_socket["bone"]) * actor.muzzle_socket["local"])
	return [origin, (tip - origin).normalized()]

## The face shows through the whole intro (the run, the stop, the ready beat and the fighter's cut) in both facings: the
## head's facing, read off its ear-to-ear axis (the bone axis nearest model +X in idle) so a nod does not swing it, stays within
## 90 degrees of the camera (CUT_FACE for the close-up's intro_cut). Hoshino's Normal_Callsign looks back over her shoulder
## from 0.05 to 0.55 s, which faced the back of her head to the camera for a third of the intro when she faced left; Hina's
## looks away for all of it, so intro_cut turns the body back (a keyframed turn, which _turns leaves alone).
func _intro_face(fighter: Node, actor: Node, cfg: Dictionary) -> void:
	var sk: Skeleton3D = actor.grip_skeleton
	var head := sk.find_bone(String(cfg["bones"]["head"]))
	actor.pose("idle", 0, "", {}, 0, 0, 1)
	var rest: Basis = (actor.pivot.global_transform.affine_inverse() * sk.global_transform * sk.get_bone_global_pose(head)).basis
	var axis := Vector3.BACK
	for v in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD]:
		if (rest * v).dot(Vector3.RIGHT) > (rest * axis).dot(Vector3.RIGHT):
			axis = v
	for entry in ENTRY + [CUTS[0]]:
		var anim: String = entry[0]
		var limit := CUT_FACE if anim == "intro_cut" else 90.0
		for face in [1, -1]:
			var widest := 0.0
			var away: Array = []
			for frame in _span(actor, cfg["anims"][anim]) + 1:
				actor.pose(anim, frame, "", {}, 0, 0, face)
				var look: Vector3 = ((sk.global_transform * sk.get_bone_global_pose(head)).basis * axis).cross(Vector3.UP)
				var yaw := rad_to_deg(atan2(look.x, look.z))
				if absf(yaw) > absf(widest):
					widest = yaw
				if absf(yaw) >= limit:
					away.append(frame)
			var key := String(fighter.data["key"])
			face_report.append("%s %s f%d: widest %.0f, ticks at %.0f or more %s" % [key, anim, face, widest, limit, away])
			check(away.is_empty(), "%s %s f%d: the face never turns from the camera (widest %.0f, ticks at %.0f or more %s)" % [key, anim, face, widest, limit, away])

## See EX_STEP.
func _ex_steps(fighter: Node, actor: Node) -> void:
	var move: Dictionary = fighter.moves.get("ex", {})
	if move.is_empty():
		return
	for face in [1, -1]:
		var last := Vector2.INF
		var worst := [0.0, -1]
		for mf in range(-1, int(move["frames"]) - 1):
			actor.pose("attack", 0, "ex", move, mf, 0, face)
			var m: Vector2 = actor.anchor_local("muzzle")
			if last != Vector2.INF and m.distance_to(last) > float(worst[0]):
				worst = [m.distance_to(last), mf]
			last = m
		check(float(worst[0]) <= EX_STEP, "%s ex f%d: the muzzle moves at most %.0f px a tick (%.0f into mf %d)" % [String(fighter.data["key"]), face, EX_STEP, worst[0], worst[1]])

## See TURN_TOL. The hips' forward axis is the pelvis bone axis nearest model forward (+Z) in idle.
func _turns(fighter: Node, actor: Node, cfg: Dictionary) -> void:
	actor.pose("idle", 0, "", {}, 0, 0, 1)
	var rest := _hips_basis(actor, cfg)
	var axis := Vector3.BACK
	for v in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD]:
		if (rest * v).dot(Vector3.BACK) > (rest * axis).dot(Vector3.BACK):
			axis = v
	var idle := _heading(actor, cfg, "idle", axis)
	for anim in cfg["anims"]:
		var turn: Variant = cfg["anims"][anim].get("turn")
		if not (turn is float or turn is int):
			continue
		var off := wrapf(_heading(actor, cfg, anim, axis) - idle, -180.0, 180.0)
		turn_report.append("%s %s %+.1f" % [String(fighter.data["key"]), anim, off])
		check(absf(off) <= TURN_TOL, "%s %s: the turn %.0f brings the hips back to idle's heading (off %+.1f, tol %.0f)" % [String(fighter.data["key"]), anim, float(turn), off, TURN_TOL])
	var key := String(fighter.data["key"])
	var run_end := _heading_at(actor, cfg, "intro_run", int(ENTRY[0][1]) - 1, axis)
	var stop_start := _heading_at(actor, cfg, "intro_stop", 0, axis)
	var stop_end := _heading_at(actor, cfg, "intro_stop", int(ENTRY[1][1]) - 1, axis)
	var join := wrapf(stop_start - run_end, -180.0, 180.0)
	var settle := wrapf(stop_end - idle, -180.0, 180.0)
	turn_report.append("%s run>stop %+.1f, stop>idle %+.1f" % [key, join, settle])
	check(absf(join) <= TURN_TOL, "%s: the stop's first tick faces within %.0f of the run's last (off %+.1f)" % [key, TURN_TOL, join])
	check(absf(settle) <= TURN_TOL, "%s: the stop's last tick faces within %.0f of idle's (off %+.1f)" % [key, TURN_TOL, settle])

## Mean horizontal heading of the hips over `anim`'s span, facing right, degrees about +Y from model forward.
func _heading(actor: Node, cfg: Dictionary, anim: String, axis: Vector3) -> float:
	var sum := Vector2.ZERO
	for frame in _span(actor, cfg["anims"][anim]) + 1:
		sum += _facing(actor, cfg, anim, frame, axis)
	return rad_to_deg(sum.angle())

func _heading_at(actor: Node, cfg: Dictionary, anim: String, frame: int, axis: Vector3) -> float:
	return rad_to_deg(_facing(actor, cfg, anim, frame, axis).angle())

func _facing(actor: Node, cfg: Dictionary, anim: String, frame: int, axis: Vector3) -> Vector2:
	actor.pose(anim, frame, "", {}, 0, 0, 1)
	var f: Vector3 = _hips_basis(actor, cfg) * axis
	return Vector2(f.z, f.x).normalized()

## The pelvis basis in world space with the facing yaw taken off (layers kept).
func _hips_basis(actor: Node, cfg: Dictionary) -> Basis:
	var sk: Skeleton3D = actor.grip_skeleton
	return Basis(Vector3.UP, -deg_to_rad(float(actor.facing) * float(cfg["yaw"]))) * sk.global_transform.basis * sk.get_bone_global_pose(actor.pelvis).basis

## Screen angle of the barrel, weapon bone origin -> muzzle point, facing right, + = down.
func _barrel(actor: Node, face: int) -> float:
	var sk: Skeleton3D = actor.grip_skeleton
	var cam: Camera3D = actor.camera
	var origin: Vector3 = sk.global_transform * sk.get_bone_global_pose(actor.weapon_bone).origin
	var tip: Vector3 = sk.global_transform * sk.get_bone_global_pose(actor.muzzle_socket["bone"]) * actor.muzzle_socket["local"]
	var d := cam.unproject_position(tip) - cam.unproject_position(origin)
	return rad_to_deg(Vector2(d.x * float(face), d.y).angle())

## Barrel elevation in the model's own frame, inside the facing yaw and the tilt / turn layers, + = up.
func _elevation(actor: Node) -> float:
	var sk: Skeleton3D = actor.grip_skeleton
	var to_model: Transform3D = actor.pivot.global_transform.affine_inverse() * sk.global_transform
	var tip: Vector3 = to_model * (sk.get_bone_global_pose(actor.muzzle_socket["bone"]) * actor.muzzle_socket["local"])
	return rad_to_deg(asin((tip - to_model * sk.get_bone_global_pose(actor.weapon_bone).origin).normalized().y))

## The f-1 pose is the f+1 pose turned by -2 * yaw: same skeleton, no mirroring.
func _check_facing(actor: Node, cfg: Dictionary, right: Dictionary, tag: String) -> void:
	check(absf(_pose_sig(actor, cfg) - float(right["sig"])) < 1e-4, tag + ": facing leaves the skeleton pose unchanged")
	var turned := Transform3D(Basis(Vector3.UP, -2.0 * deg_to_rad(float(cfg["yaw"]))), Vector3.ZERO) * Transform3D(right["pivot"])
	check(actor.pivot.transform.is_equal_approx(turned), tag + ": facing changes only the yaw")

## Held moves through the real Fighter.tick() and view, button down until the hold runs out: the held phase keeps
## moving while held, and release carries on from it in the same clip.
func _held(fighter: Node, actor: Node, ref: Node, cfg: Dictionary) -> void:
	var name := String(fighter.data["key"])
	for key in fighter.moves:
		var move: Dictionary = fighter.moves[key]
		var hold: Dictionary = move.get("hold", {})
		if hold.is_empty() or bool(move.get("air", false)):
			continue
		for face in [1, -1]:
			fighter.state = states.IDLE
			fighter.facing = face
			fighter.input.held[String(hold["btn"])] = true
			fighter._start_move(key)
			var times := {}
			var last := []
			for i in int(move["frames"]) + int(hold["max"]) + 2:
				if fighter.state != states.ATTACK:
					break
				fighter.tick()
				fighter.view.step(1.0 / 60.0)
				var tag := "%s move %s held f%d mf %d charge %d" % [name, key, face, fighter.mf, fighter.charge_t]
				_check_sample(actor, ref, cfg, tag)
				_check_floor(actor, ref, cfg, tag)
				var held: bool = fighter.charge_t > 0 and fighter.mf == int(hold["at"]) - 1
				if held:
					times["%.3f" % actor.current_time] = true
				elif not last.is_empty() and last[0]:
					var step := fposmod(actor.current_time - float(last[2]), actor.player.get_animation(actor.current_clip).length)
					check(actor.current_clip == last[1] and absf(step - 1.0 / 60.0) < 1e-3, tag + ": release carries on from the held pose (%s %.3f -> %s %.3f)" % [last[1], last[2], actor.current_clip, actor.current_time])
				last = [held, actor.current_clip, actor.current_time]
			fighter.input.held[String(hold["btn"])] = false
			check(times.size() > 3, "%s %s f%d: the held phase keeps looping while held (%d distinct times)" % [name, key, face, times.size()])
	for p in screen.projectiles:
		if is_instance_valid(p):
			p.queue_free()
	screen.projectiles.clear()
	fighter.state = states.IDLE

## Gun normals ("swish": false) through the real tick and view, both facings: each fire frame (shots and spawns) flashes
## once, at the gun's projected muzzle in that tick's pose, and no swish arc is drawn.
func _gun_fx(fighter: Node, actor: Node) -> void:
	var name := String(fighter.data["key"])
	var home: Vector2 = fighter.position
	var keys: Array = fighter.moves.keys()
	keys.sort()
	for key in keys:
		var move: Dictionary = fighter.moves[key]
		if move.get("swish", true) or move.get("shots", []).is_empty():
			continue
		var fire := {}
		for f in move["shots"]:
			fire[int(f)] = true
		for sp in move["spawns"]:
			if not sp.get("hold_fire", false) and int(sp.get("min_charge", 0)) == 0:
				fire[int(sp["frame"])] = true
		for face in [1, -1]:
			var air: bool = move["air"]
			fighter.state = states.IDLE
			fighter.facing = face
			fighter.hitstop = 0
			fighter.position = home - Vector2(0, 300 if air else 0)
			fighter.vel = Vector2(0, -12 if air else 0)
			fighter._start_move(key)
			fighter.view.step(1.0 / 60.0)
			var flashes := {}
			var swishes := 0
			while fighter.state == states.ATTACK:
				var known := {}
				for n in screen.fx_layer.get_children():
					known[n] = true
				fighter.tick()
				fighter.view.step(1.0 / 60.0)
				for n in screen.fx_layer.get_children():
					if known.has(n) or not "kind" in n:
						continue
					if n.kind == "swish":
						swishes += 1
					elif n.kind == "muzzle":
						var gun: Vector2 = fighter.position + fighter.view.rig.transform * actor.anchor_local("muzzle")
						flashes[fighter.mf] = int(flashes.get(fighter.mf, 0)) + 1
						check(n.position.distance_to(gun) < 1.0, "%s %s f%d mf %d: the flash sits on the gun's muzzle (%s, gun %s)" % [name, key, face, fighter.mf, str(n.position.round()), str(gun.round())])
			var want: Array = fire.keys()
			want.sort()
			var got: Array = flashes.keys()
			got.sort()
			check(got == want and flashes.values().all(func(c): return c == 1), "%s %s f%d: one flash per fire frame %s (got %s)" % [name, key, face, str(want), str(flashes)])
			check(swishes == 0, "%s %s f%d: a gun normal draws no swish (%d)" % [name, key, face, swishes])
	for p in screen.projectiles:
		if is_instance_valid(p):
			p.queue_free()
	screen.projectiles.clear()
	fighter.position = home
	fighter.vel = Vector2.ZERO
	fighter.state = states.IDLE

func _check_sample(actor: Node, ref: Node, cfg: Dictionary, tag: String, want_rel: Variant = null) -> void:
	for s in actor.sampled:
		var has_clip: bool = actor.player.has_animation(s[0])
		check(has_clip, tag + ": clip exists " + String(s[0]))
		if has_clip:
			var t: float = s[1]
			check(is_finite(t) and t >= 0.0 and t <= actor.player.get_animation(s[0]).length + 1e-4, tag + ": time asked of the clip lies inside it " + str(t))
	check(not actor.sampled.is_empty() and actor.sampled[0][0] == actor.current_clip, tag + ": sampled starts with the base clip")
	_check_drift(actor, ref, cfg, tag, want_rel)
	for v in [actor.pivot.scale, actor.normalizer.scale, actor.model.scale]:
		check(v.x > 0.0 and v.y > 0.0 and v.z > 0.0, tag + ": no negative 3D scale")
	check(actor.pivot.transform.basis.determinant() > 0.0 and actor.layer.basis.determinant() > 0.0, tag + ": pivot and layers are rotations")
	check(actor.body.scale.x > 0.0 and actor.body.scale.y > 0.0 and actor.scale.x > 0.0 and actor.scale.y > 0.0, tag + ": no negative 2D scale")
	var facing_yaw := Transform3D(Basis(Vector3.UP, deg_to_rad(float(actor.facing) * float(cfg["yaw"]))), Vector3.ZERO)
	check(actor.pivot.transform.is_equal_approx(facing_yaw * actor.layer), tag + ": the facing yaw sits outside every layer")
	for sk in actor.skeletons:
		check(sk.global_transform.basis.determinant() > 0.0, tag + ": skeleton not mirrored")
	for mesh in actor.meshes:
		for part in cfg["hide"]:
			if String(part) in String(mesh.name):
				check(not mesh.visible, tag + ": hidden mesh stays hidden " + String(mesh.name))
	check(actor.anchor_local("muzzle").is_finite() and actor.anchor_local("head").is_finite(), tag + ": finite muzzle/head projection")

## The gun in the grip hand's frame must match the raw base sample of the same clip and time (or, during a
## crossfade, `want_rel`: the base sample blended from what was shown when the anim changed).
func _check_drift(actor: Node, ref: Node, cfg: Dictionary, tag: String, want_rel: Variant = null) -> void:
	if want_rel == null:
		want_rel = _base_rel(actor, ref, cfg)
	var d := _drift(actor, cfg, want_rel)
	var key := String(cfg["model"]).get_file()
	var m: Array = max_drift.get(key, [0.0, 0.0, 0.0])
	max_drift[key] = [maxf(m[0], d.x), maxf(m[1], d.y), maxf(m[2], d.z)]
	check(d.x <= DRIFT_POS and d.y <= DRIFT_DEG and d.z <= DRIFT_POS, tag + ": weapon stays in the grip hand (pos %.4f, %.2f deg, muzzle %.4f)" % [d.x, d.y, d.z])

func _base_rel(actor: Node, ref: Node, cfg: Dictionary) -> Transform3D:
	ref.sample_clip(actor.current_clip, actor.current_time)
	return _grip_rel(ref, cfg)

## (weapon position error, angle error in degrees, muzzle position error) in model units, at the actor's hand.
func _drift(actor: Node, cfg: Dictionary, want_rel: Transform3D) -> Vector3:
	var sk := _grip_skeleton(actor, cfg)
	var hand := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(cfg["bones"]["grip"]))
	var want := hand * want_rel
	var got := hand * _grip_rel(actor, cfg)
	var local: Vector3 = actor.muzzle_socket.get("local", Vector3.ZERO)
	return Vector3(want.origin.distance_to(got.origin),
		rad_to_deg(want.basis.get_rotation_quaternion().angle_to(got.basis.get_rotation_quaternion())),
		(want * local).distance_to(got * local))

func _grip_skeleton(actor: Node, cfg: Dictionary) -> Skeleton3D:
	for sk in actor.skeletons:
		if sk.find_bone(cfg["bones"]["grip"]) >= 0 and sk.find_bone(cfg["bones"]["weapon"]) >= 0:
			return sk
	return null

func _grip_rel(actor: Node, cfg: Dictionary) -> Transform3D:
	var sk := _grip_skeleton(actor, cfg)
	return sk.get_bone_global_pose(sk.find_bone(cfg["bones"]["grip"])).affine_inverse() * sk.get_bone_global_pose(sk.find_bone(cfg["bones"]["weapon"]))

## The lowest a foot may go: the floor, or the raw base sample's lowest foot when the clip itself goes lower.
## `ref` holds that raw sample (the drift check sampled it at the actor's clip and time).
func _floor(ref: Node, cfg: Dictionary) -> float:
	return minf(float(cfg["ankle"]), _lowest_foot(ref, cfg)) - FLOOR_TOL

## Feet and knees (calf bone origins) of a ground pose, by the same rule: a joint resting on the floor sits at ankle
## height, so neither may go FLOOR_TOL below that unless the raw clip already puts it lower (kneeling).
func _check_floor(actor: Node, ref: Node, cfg: Dictionary, tag: String, feet := true) -> void:
	if feet:
		check(_lowest_foot(actor, cfg) >= _floor(ref, cfg), tag + ": foot not below the floor (%.4f, raw clip %.4f)" % [_lowest_foot(actor, cfg), _lowest_foot(ref, cfg)])
	var knee := _lowest_knee(actor)
	check(knee >= minf(float(cfg["ankle"]), _lowest_knee(ref)) - FLOOR_TOL, tag + ": knee not below the floor (%.4f, raw clip %.4f)" % [knee, _lowest_knee(ref)])

## See LYING_TOL.
func _check_lying(actor: Node, cfg: Dictionary, tag: String) -> void:
	var sk: Skeleton3D = actor.grip_skeleton
	var bones: Array = [actor.pelvis, sk.find_bone(String(cfg["bones"]["head"]))]
	for leg in actor.legs:
		bones.append(leg[2])
	for i in sk.get_bone_count():
		if sk.get_bone_name(i).ends_with(" UpperArm"):
			bones.append(i)
	var low := INF
	var name := ""
	for b in bones:
		var y: float = _bone_world(actor, sk, b).y
		if y < low:
			low = y
			name = sk.get_bone_name(b)
	check(bones.size() == 6 and low >= -LYING_TOL, tag + ": the body lies on the floor, %s %.3f (tol -%.3f)" % [name, low, LYING_TOL])

func _lowest_knee(actor: Node) -> float:
	var y := INF
	for leg in actor.legs:
		y = minf(y, _bone_world(actor, actor.grip_skeleton, leg[1]).y)
	return y

func _lowest_foot(actor: Node, cfg: Dictionary) -> float:
	var y := INF
	for sk in actor.skeletons:
		for i in sk.get_bone_count():
			if sk.get_bone_name(i).ends_with(String(cfg["bones"]["foot_suffix"])):
				y = minf(y, (sk.global_transform * sk.get_bone_global_pose(i).origin).y)
	return y

## The most any foot sits above the same foot in the raw sample `ref` holds (the drift check sampled it at the actor's
## clip and time).
func _foot_lift(actor: Node, ref: Node) -> float:
	var lift := -INF
	for leg in actor.legs:
		lift = maxf(lift, _bone_world(actor, actor.grip_skeleton, leg[2]).y - _bone_world(ref, ref.grip_skeleton, leg[2]).y)
	return lift

func _pose_sig(actor: Node, cfg: Dictionary) -> float:
	var sk := _grip_skeleton(actor, cfg)
	var s := 0.0
	for i in sk.get_bone_count():
		var g := sk.get_bone_global_pose(i)
		s += g.origin.x + 2.0 * g.origin.y + 3.0 * g.origin.z + g.basis.x.x + g.basis.y.y + g.basis.z.z
	return s

# ── sequential stepping across state changes, blending on ────────────────────

## A sequence step may name an anim only another fighter's kit has. Any other missing name is a real failure.
func _is_other_kit_anim(anim: String, fighter_key: String) -> bool:
	for k in KIT_ANIMS:
		if k != fighter_key and anim in KIT_ANIMS[k]:
			return true
	return false

func _sequences(fighter: Node, actor: Node, ref: Node) -> void:
	var cfg: Dictionary = actor.cfg
	var name := String(fighter.data["key"])
	for seq in SEQUENCES:
		if seq.any(func(step): return not step[0].begins_with("attack:") and not cfg["anims"].has(step[0]) and _is_other_kit_anim(step[0], name)):
			continue
		for start_face in [1, -1]:
			var face: int = start_face
			var labels: Array = []
			var shown := Transform3D()
			var from := Transform3D()
			var from_ground := true
			var last_key := ""
			var last_tick := 0
			var change_tick := 0
			var blend := 0
			var sf := 0
			for i in seq.size():
				var step: Array = seq[i]
				var opts: Dictionary = step[2] if step.size() > 2 else {}
				var anim: String = step[0]
				var mk := ""
				var move := {}
				if anim.begins_with("attack:"):
					mk = anim.get_slice(":", 1)
					move = fighter.moves.get(mk, {})
					anim = "attack"
					if move.is_empty():
						continue
				if opts.get("flip", false):
					face = -face
				labels.append(step[0])
				if not opts.get("keep_sf", false):
					sf = 0
				var ticks: Array = range(-1, int(move["frames"]) - 1) if anim == "attack" else range(int(step[1]))
				var ground: bool = anim not in NO_FLOOR and not bool(move.get("air", false))
				for t in ticks:
					if i == 0 and t == ticks[0]:
						actor.blending = false
					actor.pose(anim, sf, mk, move, t, 0, face)
					actor.blending = true
					var tick: int = t if anim == "attack" else sf
					var tag := "%s seq %s f%d %s t%d" % [name, "->".join(labels), start_face, step[0], tick]
					var top: Dictionary = cfg["moves"].get(mk, cfg["move_default"]) if anim == "attack" else cfg["anims"][anim]
					if actor.anim_name != last_key or tick < last_tick:
						from = shown
						from_ground = last_key == "" or ground_key(last_key)
						change_tick = tick
						blend = int(top.get("blend", 3)) if not (i == 0 and t == ticks[0]) else 0
					var e := tick - change_tick
					var w := 1.0 if e >= blend else float(e + 1) / float(blend + 1)
					check(is_equal_approx(actor.blend_w, w), tag + ": blend weight %.2f after %d ticks (got %.2f)" % [w, e, actor.blend_w])
					var want := from.interpolate_with(_base_rel(actor, ref, cfg), w) if w < 1.0 else _base_rel(actor, ref, cfg)
					_check_sample(actor, ref, cfg, tag, want)
					shown = _grip_rel(actor, cfg)
					if ground:
						# feet blending in from an air or lying pose are exempt, knees are not
						_check_floor(actor, ref, cfg, tag, w >= 1.0 or from_ground)
					if anim in LYING:
						_check_lying(actor, cfg, tag)
					last_key = actor.anim_name
					last_tick = tick
					sf += 1

func ground_key(key: String) -> bool:
	return key not in NO_FLOOR and key not in ["moves/jL", "moves/jH", "moves/skill_air"]

## SLIDES stepped tick by tick with blending on, both facings: 12 ticks of a state, a whole move. The hips may not
## slide across the screen between ticks (HIPS_STEP).
func _slides(fighter: Node, actor: Node) -> void:
	var name := String(fighter.data["key"])
	for pair in SLIDES:
		for face in [1, -1]:
			actor.blending = false
			var xs: Array = []
			for anim in pair:
				var mk: String = anim.get_slice(":", 1) if anim.begins_with("attack:") else ""
				var move: Dictionary = fighter.moves.get(mk, {})
				for t in range(-1, int(move.get("frames", 0)) - 1) if mk != "" else range(12):
					if mk != "":
						actor.pose("attack", 0, mk, move, t, 0, face)
					else:
						actor.pose(anim, t, "", {}, 0, 0, face)
					actor.blending = true
					xs.append(_hips_x(actor))
			var worst := 0.0
			for k in range(1, xs.size()):
				worst = maxf(worst, absf(float(xs[k]) - float(xs[k - 1])))
			var tag := "%s %s f%d" % [name, "->".join(pair), face]
			check(worst <= HIPS_STEP, "%s: the hips move at most %.0f px a tick (%.1f)" % [tag, HIPS_STEP, worst])
			slide_report.append("%s: widest step %.1f px, hips %.0f..%.0f" % [tag, worst, xs.min(), xs.max()])
	actor.blending = true

## Nothing the model draws reaches the viewport border, where it would be cut off (a halo, a head, a barrel): every
## state anim over its whole span (to its held last pose) and every kit move, both facings, rendered and read back.
func _edges(fighter: Node, actor: Node, cfg: Dictionary) -> void:
	var name := String(fighter.data["key"])
	var runs: Array = []
	for anim in cfg["anims"]:
		var span := _span(actor, cfg["anims"][anim])
		runs.append([anim, "", {}, range(0, span, EDGE_STEP) + [span]])
	for key in fighter.moves:
		runs.append(["attack", key, fighter.moves[key], range(-1, int(fighter.moves[key]["frames"]) - 1, 3)])
	var samples := 0
	for run in runs:
		for face in [1, -1]:
			for frame in run[3]:
				if run[0] == "attack":
					actor.pose("attack", 0, run[1], run[2], frame, 0, face)
				else:
					actor.pose(run[0], frame, "", {}, 0, 0, face)
				await RenderingServer.frame_post_draw
				var img: Image = actor.viewport.get_texture().get_image()
				var w := img.get_width()
				var h := img.get_height()
				var hits := 0
				for x in w:
					hits += int(img.get_pixel(x, 0).a > 0.05) + int(img.get_pixel(x, h - 1).a > 0.05)
				for y in h:
					hits += int(img.get_pixel(0, y).a > 0.05) + int(img.get_pixel(w - 1, y).a > 0.05)
				samples += 1
				check(hits == 0, "%s %s %s f%d frame %d: nothing drawn on the viewport border (%d px)" % [name, run[0], run[1], face, frame, hits])
	check(samples > 0, name + ": the edge check rendered samples")

## Ticks in one pass of a state descriptor, the preview's rule: its "frames", else each phase's "over" or its clip
## window at its speed (a hold reaches `to`, a loop wraps once). A "stride" anim is one pass at 1.0x here, as in the preview.
func _span(actor: Node, d: Dictionary) -> int:
	if d.has("frames"):
		return int(d["frames"])
	var n := 0.0
	for p in d.get("phases", [d]):
		if p.has("over"):
			n += float(p["over"])
			continue
		var q: Dictionary = d.merged(p, true)
		var length: float = actor.player.get_animation(String(q["clip"])).length
		n += (float(q.get("to", length)) - float(q.get("from", 0.0))) * 60.0 / maxf(absf(float(q.get("speed", 1.0))), 0.1)
	return mini(ceili(n), 600)

## Hit, air-hit and block reactions, and the EX's first pose that the cut-in freeze holds, show in full from their first
## tick: hitstop and the freeze repeat that tick, so a crossfade would hold at its first quarter.
func _reactions(fighter: Node, actor: Node) -> void:
	var name := String(fighter.data["key"])
	var runs := [["hit", "", {}], ["airhit", "", {}], ["block", "", {}], ["block_low", "", {}], ["block_air", "", {}], ["attack", "ex", fighter.moves.get("ex", {})]]
	for r in runs:
		if r[0] == "attack" and Dictionary(r[2]).is_empty():
			continue
		actor.blending = false
		actor.pose("idle", 30, "", {}, 0, 0, 1)
		actor.blending = true
		for i in 3:
			actor.pose(r[0], -1, r[1], r[2], -1, 0, 1)
		check(actor.blend_w == 1.0, "%s %s %s: the frozen first tick shows the whole pose (blend %.2f)" % [name, r[0], r[1], actor.blend_w])

## sync()'s state-to-anim mapping on the live fighter: walking backwards plays walk_back, blocking with down held plays
## block_low, idle with down held plays crouch (blockstun, a move or hitstun ends in one IDLE tick before CROUCH), and a
## jump's frame is its time in the arc read off vel.y, which equals sf on a plain jump and keeps the legs mid-arc when an
## air move ends and JUMP restarts at sf 0.
func _sync(fighter: Node, actor: Node, ref: Node) -> void:
	var name := String(fighter.data["key"])
	var gravity: float = load("res://scripts/fight/arena.gd").GRAVITY
	var jump := float(fighter.stats["jump"])
	fighter.hitstop = 0
	fighter.facing = 1
	fighter.sf = 5
	for c in [[states.WALK, -3.0, 0, "walk_back"], [states.WALK, 3.0, 0, "walk"], [states.BLOCK, 0.0, 1, "block_low"], [states.BLOCK, 0.0, 0, "block"], [states.IDLE, 0.0, 1, "crouch"]]:
		fighter.state = c[0]
		fighter.vel = Vector2(c[1], 0.0)
		fighter.input.y = c[2]
		fighter.view.step(1.0 / 60.0)
		check(actor.anim_name == c[3], "%s sync: state %d vel.x %.0f down %d plays %s (got %s)" % [name, c[0], c[1], c[2], c[3], actor.anim_name])
	fighter.input.y = 0
	fighter.state = states.INTRO
	# the 60 tick intro of later rounds, then the stage entry: idle until the fighter's own solo shot, intro_cut through it and the pan
	# that follows, the ready beat from the wide block on, then the idle
	var start: int = 1 + (fighter.slot - 1) * (ENTRY_SHOT + ENTRY_PAN)
	var rows := [[false, 20, "intro", 20], [false, 59, "intro", 59], [false, 60, "intro_idle", 60]]
	rows.append([true, ENTRY_WIDE, "idle", ENTRY_WIDE])
	rows.append([true, ENTRY_READY - 1, "idle", ENTRY_READY - 1])
	rows.append([true, ENTRY_READY, "intro", 0])
	rows.append([true, ENTRY_READY + 59, "intro", 59])
	rows.append([true, ENTRY_READY + 60, "intro_idle", ENTRY_READY + 60])
	rows.append([true, 359, "intro_idle", 359])
	for sf in [1, start, start + 1, start + ENTRY_SHOT - 1, ENTRY_SHOT + ENTRY_PAN, ENTRY_SHOT + ENTRY_PAN + 1, ENTRY_WIDE - 1]:
		rows.append([true, sf, "intro_cut" if sf >= start else "idle", sf - start if sf >= start else sf])
	for c in rows:
		fighter.entry_cuts = c[0]
		fighter.ready_at = ENTRY_READY if c[0] else 0
		fighter.sf = c[1]
		fighter.view.step(1.0 / 60.0)
		ref.pose(c[2], c[3], "", {}, 0, 0, 1)
		check(actor.anim_name == c[2] and str(actor.sampled) == str(ref.sampled), "%s sync: INTRO (entry_cuts %s) at sf %d plays %s at %d (%s, want %s)" % [name, str(c[0]), c[1], c[2], c[3], actor.anim_name, str(ref.sampled)])
	fighter.entry_cuts = false
	fighter.ready_at = 0
	fighter.sf = 5
	fighter.state = states.JUMP
	for c in [[0, 0], [9, 9], [24, 24], [0, 24]]:
		fighter.sf = c[0]
		fighter.vel = Vector2(0.0, -jump + gravity * float(c[1]))
		fighter.view.step(1.0 / 60.0)
		ref.pose("jump", c[1], "", {}, 0, 0, 1)
		check(actor.anim_name == "jump" and str(actor.sampled) == str(ref.sampled), "%s sync: jump at sf %d, %d ticks into the arc, plays the jump at %d (%s, want %s)" % [name, c[0], c[1], c[1], str(actor.sampled), str(ref.sampled)])
	_sync_guard_and_kit(fighter, actor, ref, gravity)
	fighter.state = states.IDLE
	fighter.vel = Vector2.ZERO
	fighter.sf = 0

## The backdash is a hop (sd.json "lift" and the jump's leg overlay): it moves 0.8 x the dash stat, decaying 0.95 a tick, and no foot is
## within HOP_PX of the floor on any tick after the first while |vx| > 1.
func _backdash_hop(fighter: Node, actor: Node, cfg: Dictionary) -> void:
	var name := String(fighter.data["key"])
	var ppu := absf((actor.camera.unproject_position(Vector3(0, 1, 0)) - actor.camera.unproject_position(Vector3.ZERO)).y * actor.body.scale.y)
	var skeleton: Skeleton3D = actor.grip_skeleton
	var moving := 0
	var was_blending: bool = actor.blending
	actor.blending = false
	for face in [1, -1]:
		for frame in range(1, int(cfg["anims"]["backdash"]["frames"]) + 1):
			if 0.8 * float(fighter.stats["dash"]) * pow(0.95, frame) <= 1.0:
				continue
			actor.pose("backdash", frame, "", {}, 0, 0, face)
			var low := INF
			for leg in actor.legs:
				low = minf(low, (skeleton.global_transform * skeleton.get_bone_global_pose(leg[2]).origin).y)
			moving += 1
			check((low - float(cfg["ankle"])) * ppu >= HOP_PX, "%s backdash f%+d tick %d: no foot within %.0f px of the floor while it moves (lowest %.1f)" % [name, face, frame, HOP_PX, (low - float(cfg["ankle"])) * ppu])
	actor.pose("idle", 0, "", {}, 0, 0, 1)
	var idle_hips: float = (skeleton.global_transform * skeleton.get_bone_global_pose(actor.pelvis).origin).y
	actor.pose("backdash", 5, "", {}, 0, 0, 1)
	var rise: float = (skeleton.global_transform * skeleton.get_bone_global_pose(actor.pelvis).origin).y - idle_hips
	actor.blending = was_blending
	check(moving > 10, "%s backdash: the hop check covers its moving ticks (%d)" % [name, moving])
	check(rise >= HOP_RISE, "%s backdash: the hop lifts the hips %.3f over idle's at tick 5, at least %.2f model units (sd.json lift)" % [name, rise, HOP_RISE])

## The distance clock (sd.json "stride"): in WALK and DASH sync() plays the clip at the body's travel over the planted foot's
## stride for the facing, so it follows any sim speed. pose() takes a float tick; walk and walk back share one phase (back runs the
## clip backwards); a dash restarts at 0; the playback is capped at STRIDE_CAP per sim tick; a render frame that skips or repeats
## ticks gets the same clock; the crossfade keeps its own monotonic tick, so walking back for ten ticks ends with the blend done.
func _stride_clock(fighter: Node, actor: Node, cfg: Dictionary) -> void:
	var name := String(fighter.data["key"])
	var cap: float = actor_script.STRIDE_CAP
	var home: Vector2 = fighter.position
	var was_blending: bool = actor.blending
	var length: float = actor.player.get_animation(String(cfg["anims"]["walk"]["clip"])).length
	actor.blending = false
	actor.pose("walk", 7.0, "", {}, 0, 0, 1)
	var t7: float = actor.raw_time
	actor.pose("walk", 8.0, "", {}, 0, 0, 1)
	var t8: float = actor.raw_time
	actor.pose("walk", 7.4, "", {}, 0, 0, 1)
	check(actor.raw_time > t7 and actor.raw_time < t8 and is_equal_approx(actor.raw_time, lerpf(t7, t8, 0.4)), "%s: pose('walk', 7.4) plays between the clip times of ticks 7 and 8 (%.4f, %.4f, %.4f)" % [name, t7, actor.raw_time, t8])
	for face in [1, -1]:
		var stride: float = float(cfg["anims"]["walk"]["stride"][0 if face < 0 else 1])
		var dash_stride: float = float(cfg["anims"]["dash"]["stride"][0 if face < 0 else 1])
		var tag := "%s sync f%+d" % [name, face]
		fighter.facing = face
		_stride_enter(fighter, actor, states.WALK)
		check(actor.anim_name == "walk" and is_equal_approx(actor.raw_time, 0.0), tag + ": a walk starts at clip time 0 (%s %.4f)" % [actor.anim_name, actor.raw_time])
		_stride_move(fighter, actor, 3.4 * face, 20)
		var want := fposmod(20.0 * 3.4 / stride / 60.0, length)
		check(absf(actor.raw_time - want) < 0.0005, tag + ": 20 ticks at 3.4 px reach clip time distance / stride (%.4f, want %.4f)" % [actor.raw_time, want])
		_stride_move(fighter, actor, -3.4 * face, 10)
		check(actor.anim_name == "walk_back", tag + ": walking back plays walk_back (%s)" % actor.anim_name)
		want = fposmod(10.0 * 3.4 / stride / 60.0, length)
		check(absf(actor.raw_time - want) < 0.0005, tag + ": ten ticks back run the clip back to distance / stride (%.4f, want %.4f)" % [actor.raw_time, want])
		_stride_move(fighter, actor, -3.4 * face, 10)
		check(absf(actor.raw_time) < 0.0005 or absf(actor.raw_time - length) < 0.0005, tag + ": back where the walk began, the clip is where it began (%.4f)" % actor.raw_time)
		_stride_enter(fighter, actor, states.DASH)
		check(actor.anim_name == "dash" and is_equal_approx(actor.raw_time, 0.0), tag + ": a dash restarts the clip at 0 (%s %.4f)" % [actor.anim_name, actor.raw_time])
		_stride_move(fighter, actor, 40.0 * face, 1)
		check(is_equal_approx(actor.raw_time * 60.0, cap), tag + ": one tick of 40 px plays %.1f clip ticks (%.3f)" % [cap, actor.raw_time * 60.0])
		_stride_enter(fighter, actor, states.DASH)
		fighter.sf += 3
		fighter.position.x += 10.0 * face
		actor.sync(fighter)
		check(is_equal_approx(actor.raw_time * 60.0, minf(10.0 / dash_stride, 3.0 * cap)), tag + ": a frame that skips three ticks gets the whole 10 px (%.3f)" % (actor.raw_time * 60.0))
		_stride_enter(fighter, actor, states.WALK)
		_stride_move(fighter, actor, 3.4 * face, 10, true)
		want = fposmod(10.0 * 3.4 / stride / 60.0, length)
		check(absf(actor.raw_time - want) < 0.0005, tag + ": a frame drawn twice a tick counts the distance once (%.4f, want %.4f)" % [actor.raw_time, want])
		actor.blending = true
		_stride_enter(fighter, actor, states.IDLE)
		_stride_enter(fighter, actor, states.WALK)
		_stride_move(fighter, actor, -3.0 * face, 12)
		check(actor.anim_name == "walk_back" and actor.blend_w == 1.0, tag + ": twelve ticks of walking back, blending on, end with the crossfade done (blend %.2f)" % actor.blend_w)
		actor.blending = false
	fighter.state = states.IDLE
	fighter.sf = 0
	fighter.vel = Vector2.ZERO
	fighter.position = home
	fighter.facing = 1
	actor.sync(fighter)
	actor.blending = was_blending

func _stride_enter(fighter: Node, actor: Node, state: int) -> void:
	fighter.state = state
	fighter.sf = 0
	fighter.vel = Vector2.ZERO
	fighter.position.x = 0.0
	actor.sync(fighter)

## One sim tick of `dx` px a tick, `ticks` times, synced after each (twice when the frame is drawn twice).
func _stride_move(fighter: Node, actor: Node, dx: float, ticks: int, twice := false) -> void:
	for i in ticks:
		fighter.position.x += dx
		fighter.vel.x = dx
		fighter.sf += 1
		actor.sync(fighter)
		if twice:
			actor.sync(fighter)

## A blocked fighter in the air plays block_air whatever down says, a crushed one the hit reel from its first tick, and
## in JUMP a kit's kv["anim"] / kv["anim_t"] picks the anim and its tick (sd_config.gd). The fighter is put back after.
func _sync_guard_and_kit(fighter: Node, actor: Node, ref: Node, gravity: float) -> void:
	var name := String(fighter.data["key"])
	var arena: Script = load("res://scripts/fight/arena.gd")
	var home: Vector2 = fighter.position
	var kv: Dictionary = fighter.kv
	var crush_stat: Variant = fighter.stats.get("guard_crush")
	fighter.kv = {}
	fighter.stats["guard_crush"] = 60
	fighter.vel = Vector2.ZERO
	fighter.state = states.BLOCK
	for height in [0.0, 200.0]:
		fighter.position.y = arena.GROUND - height
		for down in [0, 1]:
			for crush in [0, 10]:
				fighter.input.y = down
				fighter.crush_t = crush
				fighter.sf = 5
				fighter.view.step(1.0 / 60.0)
				var want := "hit" if crush > 0 else ("block_air" if height > 0.0 else ("block_low" if down == 1 else "block"))
				check(actor.anim_name == want, "%s sync: BLOCK %.0f px up, down %d, crush_t %d plays %s (got %s)" % [name, height, down, crush, want, actor.anim_name])
				if crush > 0:
					ref.pose("hit", 50, "", {}, 0, 0, 1)
					check(str(actor.sampled) == str(ref.sampled), "%s sync: a crush with 10 of 60 ticks left plays the hit reel 50 ticks in (%s, want %s)" % [name, str(actor.sampled), str(ref.sampled)])
	fighter.crush_t = 0
	fighter.input.y = 0
	fighter.position = home
	fighter.state = states.JUMP
	fighter.sf = 3
	fighter.vel = Vector2(0.0, -float(fighter.stats["jump"]) + gravity * 3.0)
	fighter.kv = {"anim": "backdash", "anim_t": 7}
	fighter.view.step(1.0 / 60.0)
	ref.pose("backdash", 7, "", {}, 0, 0, 1)
	check(actor.anim_name == "backdash" and str(actor.sampled) == str(ref.sampled), "%s sync: kv anim backdash at anim_t 7 plays it 7 ticks in, not the jump arc's tick (%s, %s)" % [name, actor.anim_name, str(actor.sampled)])
	for kit_anim in ["dash_air", "dash_air_back", "glide"]:
		if actor.cfg["anims"].has(kit_anim):
			fighter.state = states.JUMP
			fighter.kv = {"anim": kit_anim, "anim_t": 7}
			fighter.view.step(1.0 / 60.0)
			ref.pose(kit_anim, 7, "", {}, 0, 0, 1)
			check(actor.anim_name == kit_anim and str(actor.sampled) == str(ref.sampled), "%s sync: kv anim %s at anim_t 7 plays it 7 ticks in (%s, %s)" % [name, kit_anim, actor.anim_name, str(actor.sampled)])
	if not actor.cfg["anims"].has("glide"):
		fighter.state = states.JUMP
		fighter.kv = {"anim": "glide", "anim_t": 7}
		fighter.view.step(1.0 / 60.0)
		check(actor.anim_name == "jump", "%s sync: a fighter without a glide plays the jump when the kit asks for one (got %s)" % [name, actor.anim_name])
	fighter.state = states.JUMP
	fighter.kv = {"anim": "zzz_missing", "anim_t": 7}
	fighter.view.step(1.0 / 60.0)
	check(actor.anim_name == "jump", "%s sync: a kv anim the fighter lacks plays the jump (got %s)" % [name, actor.anim_name])
	fighter.kv = {"anim": "backdash", "anim_t": 7}
	fighter.state = states.HIT
	fighter.view.step(1.0 / 60.0)
	check(actor.anim_name == "hit", "%s sync: a stale kv anim outside JUMP is ignored (got %s)" % [name, actor.anim_name])
	fighter.kv = kv
	if crush_stat == null:
		fighter.stats.erase("guard_crush")
	else:
		fighter.stats["guard_crush"] = crush_stat

## pose() must put the gun back in the hand after anything that moves the grip arm past the base sample.
func _pose_reattaches(bent: Node, ref: Node, cfg: Dictionary) -> void:
	for face in [1, -1]:
		for anim in ["idle", "walk"]:
			bent.gap = 0.0
			bent.pose(anim, 20, "", {}, 0, 0, face)
			var tag := "%s %s f%d bent arm" % [String(cfg["model"]).get_file(), anim, face]
			check(bent.gap > 0.02, tag + ": pose() re-attaches after the arm moves (the bend pulled the gun %.3f off the hand)" % bent.gap)
			_check_drift(bent, ref, cfg, tag)

# ── source clips, morphs, hitstop, EX ────────────────────────────────────────

func _source_clips(actor: Node, cfg: Dictionary) -> void:
	for clip in actor.player.get_animation_list():
		var length: float = actor.player.get_animation(clip).length
		for fraction in [0.0, 0.25, 0.5, 0.75, 1.0]:
			actor.sample_clip(String(clip), length * fraction)
			for mesh in actor.meshes:
				for part in cfg["hide"]:
					if String(part) in String(mesh.name):
						check(not mesh.visible, "hidden mesh stays hidden: source %s %.2f %s" % [clip, fraction, mesh.name])

func _mouths(actor: Node) -> void:
	actor.sample_clip("Normal_Idle", 0.55)
	var original := _mouth_weights(actor)
	for cycle in 3:
		for clip in ["Cafe_Walk", "Exs", "Move_Ing", "Normal_Idle"]:
			actor.sample_clip(clip, 0.55)
		actor.pose("idle", 33, "", {}, 0, 0, 1)
		actor.sample_clip("Normal_Idle", 0.55)
		check(_mouth_weights(actor) == original, "interrupted clips restore mouth weights")

func _mouth_weights(actor: Node) -> Array:
	var list: Array = []
	for mesh in actor.meshes:
		if String(mesh.name).begins_with("Mouth"):
			var weights: Array = []
			for i in mesh.mesh.get_blend_shape_count():
				weights.append(mesh.get_blend_shape_value(i))
			list.append([String(mesh.name), weights])
	return list

func _hitstop_and_ex_end(fighter: Node) -> void:
	var actor: Node = fighter.view.sd_actor
	fighter.facing = 1
	fighter.state = states.HIT
	fighter.sf = 17
	fighter.hitstun = 40
	fighter.hitstop = 4
	fighter.view.step(1.0 / 60.0)
	var stopped: float = actor.current_time
	var tick_before: int = fighter.frame
	for i in 3:
		fighter.tick()
		fighter.view.step(1.0 / 60.0)
	check(fighter.frame == tick_before + 3, "simulation frame advances during hitstop")
	check(is_equal_approx(actor.current_time, stopped), "animation holds during hitstop")
	check(fighter.view.rig.scale.x > 0.0 and fighter.view.rig.scale.y > 0.0, "fighter_view rig never mirrored")
	# down held as the EX ends: its IDLE tick plays crouch, which must hold the endpoint too
	for down in [0, 1]:
		fighter.hitstop = 0
		fighter.state = states.ATTACK
		fighter.move_key = "ex"
		fighter.move = fighter.moves["ex"]
		fighter.mf = int(fighter.move["frames"]) - 2
		var before := [fighter.position, fighter.hp, fighter.meter, fighter.mf, fighter.sf, fighter.hurtbox(), fighter.vel, fighter.state]
		fighter.view.step(1.0 / 60.0)
		check(before == [fighter.position, fighter.hp, fighter.meter, fighter.mf, fighter.sf, fighter.hurtbox(), fighter.vel, fighter.state], "visual step leaves the simulation untouched")
		var ex_clip: String = actor.current_clip
		var ex_end: float = actor.current_time
		var ex_d: Dictionary = actor.cfg["moves"]["ex"]
		var last: Dictionary = ex_d.get("phases", [ex_d])[-1]
		var want_end := float(last.get("to", actor.player.get_animation(String(last["clip"])).length))
		check(ex_clip == String(last["clip"]) and is_equal_approx(ex_end, want_end), "EX reaches its endpoint on the last displayed frame (%s %.3f, want %.3f)" % [ex_clip, ex_end, want_end])
		fighter.mf = int(fighter.move["frames"]) - 1
		fighter.state = states.IDLE
		fighter.move = {}
		fighter.input.y = down
		fighter.view.step(1.0 / 60.0)
		check(actor.current_clip == ex_clip and is_equal_approx(actor.current_time, ex_end), "natural EX completion presents the endpoint once (down %d)" % down)
		fighter.view.step(1.0 / 60.0)
		check(actor.anim_name == ("crouch" if down else "idle"), "EX completion returns to %s" % ("crouch" if down else "idle"))
	fighter.input.y = 0

## Far apart so no hit lands: P2 attacking alone draws over P1, every other case keeps P1 on top.
func _draw_order() -> void:
	screen.f1.position.x = -400.0
	screen.f2.position.x = 400.0
	for c in [["", "5H"], ["5H", ""], ["5L", "5H"], ["", ""]]:
		for i in 2:
			var f: Node = screen.fighters[i]
			f.state = states.IDLE
			f.move = {}
			f.move_key = ""
			if c[i] != "":
				f._start_move(c[i])
		screen._sim_step()
		var p2_front: bool = c[0] == "" and c[1] != ""
		check((screen.f2.z_index > screen.f1.z_index) == p2_front, "draw order with p1 '%s' and p2 '%s': p2 %s p1 (z %d vs %d)" % [c[0], c[1], "over" if p2_front else "under", screen.f2.z_index, screen.f1.z_index])
	for f in screen.fighters:
		f.state = states.IDLE
		f.move = {}
		f.move_key = ""

func _ex_freeze() -> void:
	screen.f1.meter = 100.0
	screen.f1._start_move("ex")
	screen._sim_step()
	check(screen.world_frozen, "EX enters the world freeze")
	var actor: Node = screen.f1.view.sd_actor
	var freeze_time: float = actor.current_time
	var freeze_mf: int = screen.f1.mf
	for i in 50:
		screen._sim_step()
		screen.f1.view.step(1.0 / 60.0)
		await process_frame
	check(screen.f1.mf == freeze_mf, "move counter holds in the freeze")
	check(screen.f1.z_index == screen.FREEZE_Z, "the EX caster draws over the freeze veil")
	check(is_equal_approx(actor.current_time, freeze_time), "model pose holds in the freeze")
	for i in 30:
		screen._sim_step()
	for fighter in screen.fighters:
		fighter.view.step(1.0 / 60.0)
	check(not screen.world_frozen, "world resumes after the freeze")
	check(screen.f1.mf > freeze_mf and actor.current_time != freeze_time, "EX pose moves again after the freeze")
	check(screen.release_t < screen.VEIL_OUT_FRAMES and screen.f1.z_index == screen.FREEZE_Z, "the EX caster stays over the veil while it lifts (release_t %d)" % screen.release_t)
	for i in screen.VEIL_OUT_FRAMES:
		screen._sim_step()
	check(screen.f1.z_index == 4 and screen.f2.z_index == 3, "the EX caster drops back to the fighters' order once the veil is gone (release_t %d, z %d vs %d)" % [screen.release_t, screen.f1.z_index, screen.f2.z_index])
	screen._clear_freeze()
