extends Node2D
## Live 3D presentation of the existing 2D simulation. assets/ba/sd/<key>/sd.json maps every state and kit move to
## source clips and layers (schema in sd_config.gd); the pose comes from sim counters plus the pose shown last (for the
## crossfade), and the sim never reads it.

const CONFIG := preload("res://scripts/models/sd_config.gd")
const COMPOSITE := preload("res://shaders/sd_composite.gdshader")
const BA := preload("res://scripts/models/ba_material_builder.gd")
const LIGHT_RIG := preload("res://scripts/models/ba_light_rig.gd")
const HALO_GLOW := preload("res://scripts/models/ba_halo_glow.gd")
## Viewport px at a 720 px high window; the height and camera size set the resolution. Wider than tall: lying and leaning poses
## reach about 390 px either side of the feet. A taller window grows the viewport (see _fit_viewport) so the model stays sharp.
const SIZE := Vector2i(880, 640)
const MAX_VIEW_SCALE := 2.0
const CLOSE_ZOOM := 1.3
const WORLD_PX := Arena.SPRITE_H / 2.35
const PRESSED_SLACK := 2.0   # px past the pair minimum that still counts as pressed against the foe
const HELD_SPEED := 2.5      # px a tick: a walker faster than this is not held still by the push or a wall, so its feet must move
## The fastest playback the distance clock asks of a clip (the fastest cadence the repo has looked at is 1.4x).
const STRIDE_CAP := 1.6

var cfg: Dictionary
var body: Sprite2D
var mat: ShaderMaterial
var viewport: SubViewport
var model: Node3D
var pivot: Node3D
var normalizer: Node3D
var camera: Camera3D
var player: AnimationPlayer
var meshes: Array[MeshInstance3D] = []
var hidden_meshes: Array[MeshInstance3D] = []
var skeletons: Array[Skeleton3D] = []
var baseline_nodes: Array = []
var baseline_bones: Array = []
var baseline_morphs: Array = []
var current_clip := ""
var current_time := 0.0
var raw_time := 0.0                   # the time asked of sample_clip(), before it clamps into the clip
var anim_name := ""                   # descriptor of the last pose(): a state anim, "moves/<key>" or "move_default"
var facing := 1
var muzzle_socket: Dictionary = {}
var grip_skeleton: Skeleton3D
var grip_bone := -1
var weapon_bone := -1
var grip_offset := Transform3D()      # weapon bone in the grip hand's frame, taken from the base sample
var ex_end_frame := -1
var ex_move: Dictionary = {}
var ex_endpoint_presented := false
var halo_glow: Sprite2D               # the additive ring behind the halo, null when the model has none
var ba_mats: Array[ShaderMaterial] = []   # every BA material of the model, outline passes included
var view_scale := 1.0                 # viewport size over SIZE: window height over 720 or the close shot's zoom, between 1 and MAX_VIEW_SCALE
var _shot_scale := 1.0                # the scale fit_zoom() asks for
var _look := []                       # the last set_look() arguments, so unchanged looks cost nothing
var look_driven := false              # true once fighter_view.gd sets the look every frame; sync() then leaves it alone
var blending := true                  # crossfade between anims; the preview and tests turn it off
var blend_w := 1.0                    # weight of the new anim in the running crossfade
var layer := Transform3D()            # whole-model layers (tilt, turn); pivot = facing yaw * layer
var sampled: Array = []               # [clip, raw_time] pairs of the last pose(): the base clip, then its overlays
var locked := {}                      # grip skeleton bones no overlay may set: the grip hand, its ancestors and children
var legs: Array = []                  # [thigh, calf, foot] bone indices per leg, for crouch IK
var pelvis := -1
var _aim_ids := {}                     # spine, arm and neck bones of the aim layer, looked up on first use
var _arm_l: Array = []                 # [upper arm, forearm, hand] of the free left arm, for the reach layer
var _arm_r: Array = []                 # the same for the gun arm, for the grip layer
const AIM_SPINE := 0.6                 # the spine bends this share of an aim, the arms swing the rest (sd.json "aim_spine")
const AIM_HEAD := 0.5                  # the head follows this share of an aim
var aim_enabled := true                # the SD suite turns the aim layer off to check the clip's own gun is level
var torso: Array = []                 # the hurtbox bones (pelvis, feet, upper arms, head) a lying pose rests on
var _masks := {}
var _shown := {}                      # what the last pose() displayed, for the next crossfade
var _from := {}                       # the snapshot the running crossfade starts from
var _blend_n := 0
var _blend_start := 0.0
var _clock := 0.0                     # distance clock: clip ticks at 1.0x walked since this walk or dash began (sd.json "stride")
var _seen_x := 0.0                    # position and tick at the previous sync(), for how far the body travelled
var _seen_frame := -1
var _sync_key := []                   # everything sync() read at its last pose; any pose or sample_clip() since clears it
var _clock_x := 0.0                   # position, state and state tick at the previous clock update
var _clock_state := -1
var _clock_sf := 0

static func supports(data: Dictionary) -> bool:
	var cfg := CONFIG.of(String(data.get("key", "")))
	if cfg.is_empty():
		return false
	if not ResourceLoader.exists(String(cfg.get("model", ""))):
		push_error("SD model '%s' in the sd.json of %s does not exist; using the 2D view" % [cfg.get("model", ""), data.get("key")])
		return false
	return true

func setup(data: Dictionary) -> void:
	cfg = CONFIG.of(String(data["key"]))
	viewport = SubViewport.new()
	viewport.name = "ModelViewport"
	viewport.size = SIZE
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var environment := WorldEnvironment.new()
	environment.environment = env
	world.add_child(environment)
	pivot = Node3D.new()
	world.add_child(pivot)
	normalizer = Node3D.new()
	pivot.add_child(normalizer)
	model = (load(cfg["model"]) as PackedScene).instantiate() as Node3D
	normalizer.add_child(model)
	player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for node in model.find_children("*", "", true, false):
		if node is MeshInstance3D:
			meshes.append(node)
			for part in cfg["hide"]:
				if String(part) in String(node.name):
					hidden_meshes.append(node)
		if node is Skeleton3D:
			skeletons.append(node)
	for node in model.find_children("*", "Node3D", true, false):
		baseline_nodes.append({"node": node, "transform": node.transform})
	for skeleton in skeletons:
		var poses: Array = []
		for i in skeleton.get_bone_count():
			poses.append(skeleton.get_bone_pose(i))
		baseline_bones.append({"skeleton": skeleton, "poses": poses})
	for mesh in meshes:
		var values: Array = []
		for i in mesh.mesh.get_blend_shape_count():
			values.append(mesh.get_blend_shape_value(i))
		baseline_morphs.append({"mesh": mesh, "values": values})
	var bones: Dictionary = cfg["bones"]
	for skeleton in skeletons:
		if skeleton.find_bone(bones["grip"]) >= 0 and skeleton.find_bone(bones["weapon"]) >= 0:
			grip_skeleton = skeleton
			grip_bone = skeleton.find_bone(bones["grip"])
			weapon_bone = skeleton.find_bone(bones["weapon"])
	if grip_skeleton == null:
		push_error("SD grip bone '%s' and weapon bone '%s' are not in one skeleton of %s" % [bones["grip"], bones["weapon"], cfg["model"]])
	else:
		for i in grip_skeleton.get_bone_count():
			var up := i
			while up >= 0 and up != grip_bone and up != weapon_bone:
				up = grip_skeleton.get_bone_parent(up)
			if up >= 0:
				locked[i] = true
			if grip_skeleton.get_bone_name(i).ends_with(bones["foot_suffix"]):
				var calf := grip_skeleton.get_bone_parent(i)
				var thigh := grip_skeleton.get_bone_parent(calf)
				legs.append([thigh, calf, i])
				pelvis = grip_skeleton.get_bone_parent(thigh)
				torso.append(i)
			if grip_skeleton.get_bone_name(i).ends_with(" UpperArm") or grip_skeleton.get_bone_name(i) == bones["head"]:
				torso.append(i)
		if pelvis >= 0:
			torso.append(pelvis)
		var up := grip_bone
		while up >= 0:
			locked[up] = true
			up = grip_skeleton.get_bone_parent(up)
		if cfg.has("extra_clips"):
			_merge_clips(String(cfg["extra_clips"]))
	for name in cfg["muzzle"]:
		var emitter := model.find_child(name, true, false) as Node3D
		if emitter and grip_skeleton:
			var bind_world: Transform3D = grip_skeleton.global_transform * grip_skeleton.get_bone_global_pose(weapon_bone)
			muzzle_socket = {"skeleton": grip_skeleton, "bone": weapon_bone, "local": bind_world.affine_inverse() * emitter.global_position}
			break
	var bounds := AABB()
	var first := true
	for mesh in meshes:
		for part in cfg["height_meshes"]:
			if String(part) in String(mesh.name):
				var box: AABB = model.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
				bounds = box if first else bounds.merge(box)
				first = false
				break
	if first:
		push_error("SD height_meshes %s match no mesh in %s; using scale 1" % [str(cfg["height_meshes"]), cfg["model"]])
		bounds = AABB(Vector3.ZERO, Vector3(0, float(cfg["height_units"]), 0))
	var scale_factor := float(cfg["height_units"]) / bounds.size.y
	normalizer.scale = Vector3.ONE * scale_factor
	normalizer.position = Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z) * scale_factor
	sample_clip(String(cfg["anims"].get("idle", cfg["move_default"])["clip"]), 0.0)
	if pelvis >= 0:
		# the idle clip stands turned (Hoshino -37, Hina -31 degrees), which made one facing a front view and the other a back view
		var hips_basis := _to_pivot().basis * grip_skeleton.get_bone_global_pose(pelvis).basis
		var forward := Vector3.BACK
		for v in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD]:
			if (hips_basis * v).dot(Vector3.BACK) > (hips_basis * forward).dot(Vector3.BACK):
				forward = v
		var heading := hips_basis * forward
		normalizer.rotation.y = atan2(heading.x, heading.z)
	var foot_y := INF
	for skeleton in skeletons:
		for i in skeleton.get_bone_count():
			if skeleton.get_bone_name(i).ends_with(bones["foot_suffix"]):
				var foot: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(i).origin
				foot_y = minf(foot_y, foot.y)
	if foot_y != INF:
		normalizer.position.y += -foot_y + float(cfg["ankle"])
	if pelvis >= 0:
		# the facing yaw turns about the feet origin, so the idle pelvis stands on it; on the Body box centre, Hina's hips
		# sat 50 px beside her feet and stepped sideways on every turn-around
		var hips := _to_pivot() * grip_skeleton.get_bone_global_pose(pelvis).origin
		normalizer.position -= Vector3(hips.x, 0.0, hips.z)
	var light: Variant = Game.session.stage.get("light", {})
	LIGHT_RIG.apply(light if light is Dictionary else {})
	ba_mats = BA.build(meshes, String(cfg["model"]).get_base_dir(), bool(cfg["halo_overlay"]))
	var camera_size := float(cfg["camera"]["size"])
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = camera_size
	camera.position = Vector3(0, float(cfg["camera"]["y"]), 7)
	world.add_child(camera)
	camera.make_current()
	body = Sprite2D.new()
	body.texture = viewport.get_texture()
	body.centered = false
	body.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	mat = ShaderMaterial.new()
	mat.shader = COMPOSITE
	body.material = mat
	add_child(body)
	_fit_viewport()
	for mesh in meshes:
		if "halo" in String(mesh.name).to_lower():
			var glow := HALO_GLOW.new()
			add_child(glow)
			glow.setup(mesh, camera, body)
			if not glow.is_queued_for_deletion():
				halo_glow = glow
	if is_inside_tree():
		get_window().size_changed.connect(_fit_viewport)
	pivot.rotation_degrees.y = float(cfg["yaw"])
	set_meta("sd_model", true)

## Sizes the viewport by the window height over the 720 px reference (the sprite is drawn at the same on-screen size either way, so
## a taller window gets a sharper model, not a bigger one) and the outline width with it. Steps of a quarter keep a window drag from
## reallocating the viewport on every pixel.
func _fit_viewport() -> void:
	var w := get_window() if is_inside_tree() else null
	var s := 1.0 if w == null else snappedf(clampf(float(w.size.y) / float(maxi(w.content_scale_size.y, 1)), 1.0, MAX_VIEW_SCALE), 0.25)
	s = maxf(s, _shot_scale)
	view_scale = s
	viewport.size = Vector2i(Vector2(SIZE) * s)
	body.offset = -camera.unproject_position(Vector3.ZERO)
	body.scale = Vector2.ONE * WORLD_PX * float(cfg["camera"]["size"]) / float(viewport.size.y)
	BA.set_outline_width(ba_mats, BA.OUTLINE_PX * s)

## A camera zoom above CLOSE_ZOOM (only the stage entry's cuts) would upscale the viewport's pixels, so the viewport grows to the
## next quarter step over the zoom, up to MAX_VIEW_SCALE, and shrinks back when the shot ends. The EX freeze and KO push stay
## below CLOSE_ZOOM, so a fight never reallocates it.
func fit_zoom(z: float) -> void:
	var want := 1.0 if z <= CLOSE_ZOOM else minf(ceilf(z * 4.0) / 4.0, MAX_VIEW_SCALE)
	if want != _shot_scale:
		_shot_scale = want
		_fit_viewport()

## Raw source sample: baselines reset, one clip at `seconds`, configured meshes hidden.
func sample_clip(clip: String, seconds: float) -> void:
	_sync_key = []
	raw_time = seconds
	player.stop(true)
	for item in baseline_nodes:
		item["node"].transform = item["transform"]
	for item in baseline_bones:
		for i in item["poses"].size():
			item["skeleton"].set_bone_pose(i, item["poses"][i])
	for item in baseline_morphs:
		for i in item["values"].size():
			item["mesh"].set_blend_shape_value(i, item["values"][i])
	if not player.has_animation(clip):
		push_error("Missing SD source clip: " + clip)
		return
	current_clip = clip
	current_time = clampf(seconds, 0.0, player.get_animation(clip).length)
	player.play(clip)
	player.seek(current_time, true)
	player.advance(0)
	for mesh in hidden_meshes:
		mesh.visible = false

func sync(f: Fighter) -> void:
	if f.world != null:
		fit_zoom(f.world.cam_zoom)
	var key := [f.frame, f.state, f.sf, f.move_key, f.mf, f.charge_t, f.facing, f.carry_anim, f.carry_t, f.position, f.vel,
		f.input.x, f.input.y, f.crush_t, f.stats.get("guard_crush"), f.stats["jump"], f.kv.get("anim"), f.kv.get("anim_t"),
		f.entry_cuts, f.ready_at, f._flash, f.dim, f.foe.position if f.foe else Vector2.ZERO, f.foe.state if f.foe else -1]
	if key == _sync_key:
		return
	_sync_pose(f)
	_sync_key = key

func _sync_pose(f: Fighter) -> void:
	if f.carry_anim != "" and cfg["anims"].has(f.carry_anim):
		pose(f.carry_anim, f.carry_t, "", {}, 0, 0, f.facing)
		if not look_driven:
			set_look(f._flash, Color.WHITE, f.dim, 0.0)
		return
	var anim := f.state_name()
	var sf: float = f.sf
	var kit_anim := String(f.kv.get("anim", ""))
	if f.state == Fighter.S.JUMP and kit_anim != "" and cfg["anims"].has(kit_anim):
		anim = kit_anim
		sf = int(f.kv.get("anim_t", f.sf))
	elif f.state == Fighter.S.INTRO:
		var step := f.intro_step()
		anim = step[0]
		sf = float(step[1])
	elif f.state == Fighter.S.BLOCK and f.crush_t > 0:
		anim = "hit"
		sf = int(f.stats.get("guard_crush", f.crush_t)) - f.crush_t
	elif f.state == Fighter.S.BLOCK and not f.is_grounded():
		anim = "block_air"
	elif f.state == Fighter.S.WALK and _held_still(f):
		anim = "idle"
	elif f.state == Fighter.S.WALK and f.vel.x * float(f.facing) < 0.0:
		anim = "walk_back"
	elif f.state == Fighter.S.BLOCK and f.input.y > 0:
		anim = "block_low"
	elif f.state == Fighter.S.IDLE and f.input.y > 0:
		anim = "crouch"   # blockstun, a move or hitstun ends in one IDLE tick before CROUCH; the model stays down
	elif f.state == Fighter.S.JUMP:
		# frames into the arc, read off its velocity: an air move that ends mid-air restarts JUMP at sf 0, which would
		# replay the takeoff
		sf = maxi(0, roundi((f.vel.y + float(f.stats["jump"])) / Arena.GRAVITY))
	var stride: Variant = cfg["anims"].get(anim, {}).get("stride")
	var strided: bool = stride is Array and (f.state == Fighter.S.WALK or f.state == Fighter.S.DASH)
	if strided:
		sf = _stride_clock(f, float(stride[0 if f.facing < 0 else 1]))
	else:
		_clock_state = -1
	pose(anim, sf, f.move_key, f.move, f.mf, f.charge_t, f.facing, f.sf if strided else -1)
	if not look_driven:
		set_look(f._flash, Color.WHITE, f.dim, 0.35 if f.state == Fighter.S.KO else 0.0)
	_seen_x = f.position.x
	_seen_frame = f.frame

## Walking into a foe the push already holds at the minimum spacing (within PRESSED_SLACK px of it): the run clip leans the
## trunk far past the feet and no width fixes that, so sync() stands instead. Presentation only; the walk clip is untouched.
func _pressed_on_foe(f: Fighter) -> bool:
	if f.foe == null or not f.pushes_foe():
		return false
	var dx := f.foe.position.x - f.position.x
	return float(f.input.x) == signf(dx) and absf(dx) <= f.push_min() + PRESSED_SLACK

## Walking into the wall, which holds the body as still as a foe the push is holding.
func _pressed_on_wall(f: Fighter) -> bool:
	return absf(f.position.x) >= Arena.HALF_W - 0.5 and float(f.input.x) == signf(f.position.x)

## Pressed against the foe or the wall AND the body is not travelling: a walker the push does not hold (a foe lying down, high
## in the air or moving away) keeps its stride clock, or its feet would glide in the idle pose.
func _held_still(f: Fighter) -> bool:
	if not (_pressed_on_foe(f) or _pressed_on_wall(f)):
		return false
	if _seen_frame < 0:
		return true
	return absf(f.position.x - _seen_x) / float(maxi(f.frame - _seen_frame, 1)) <= HELD_SPEED

## Clip ticks at 1.0x the body has walked: its travel along the facing (back is negative, so walking back runs the clip
## backwards from the same phase) over `stride`, the planted foot's screen speed at 1.0x. A walk or dash starts at 0. sync() runs
## per rendered frame, not per sim tick, so the position since the last call is what counts and the playback cap scales with the
## sim ticks since then.
func _stride_clock(f: Fighter, stride: float) -> float:
	if f.state != _clock_state or f.sf < _clock_sf:
		_clock = 0.0
	else:
		var cap := STRIDE_CAP * float(maxi(f.sf - _clock_sf, 1))
		_clock += clampf((f.position.x - _clock_x) * float(f.facing) / stride, -cap, cap)
	_clock_x = f.position.x
	_clock_state = f.state
	_clock_sf = f.sf
	return _clock

## The hit flash, dim, KO and super glow, as the colour hooks of the BA shaders. `ko` is the grayscale and tint amount, `glow` a rim
## colour. fighter_view.gd may call this after sync() with the flash colour and the glow it has.
func set_look(flash := 0.0, flash_col := Color.WHITE, dim := 1.0, ko := 0.0, glow := 0.0, glow_col := Color.WHITE) -> void:
	var now := [flash, flash_col, dim, ko, glow, glow_col]
	if now != _look:
		_look = now
		BA.set_look(ba_mats, flash, flash_col, dim, ko, glow, glow_col)
		if halo_glow:
			halo_glow.self_modulate = Color(dim, dim, dim)

## The one pose path for the game and tools. `anim` is a state anim name from sd.json; "attack" plays kit move
## `move_key` (its descriptor, or move_default) at move frame `mf`. Order: overlays and the base clip are sampled,
## the gun's offset in the grip hand is taken from the base sample, overlay bones are applied, then crouch IK, the
## crossfade, the weapon re-attach and the whole-model layers.
func pose(anim: String, sf: float, move_key := "", move := {}, mf := 0, charge_t := 0, face := 1, age := -1) -> void:
	facing = face
	var top: Dictionary
	var picked: Array
	var tick := sf if age < 0 else float(age)
	if anim == "attack":
		anim_name = "moves/" + move_key if cfg["moves"].has(move_key) else "move_default"
		top = cfg["moves"].get(move_key, cfg["move_default"])
		var hold: Dictionary = move.get("hold", {})
		# while the button is held the sim parks mf one short of hold.at and counts charge_t up from 1
		if charge_t > 0 and not hold.is_empty() and mf == int(hold["at"]) - 1:
			picked = _phase(top, move, mf + 1, charge_t - 1)
		else:
			picked = _phase(top, move, mf, charge_t)
		tick = mf + charge_t
		if move_key == "ex":
			ex_end_frame = int(move.get("frames", 1)) - 1
			ex_move = move
			ex_endpoint_presented = false
	elif anim in ["idle", "crouch", "jump"] and anim_name == "moves/ex" and ex_end_frame >= 0 and mf >= ex_end_frame and not ex_endpoint_presented:
		# a naturally completed EX holds its endpoint for one more tick
		ex_endpoint_presented = true
		top = cfg["moves"]["ex"]
		tick = ex_end_frame - 1
		picked = _phase(top, ex_move, tick, 0)
	else:
		anim_name = anim if cfg["anims"].has(anim) else "idle"
		top = cfg["anims"][anim_name]
		picked = _phase(top, {}, sf, 0)
	if _shown.is_empty() or anim_name != _shown["key"] or tick < float(_shown["tick"]):
		_from = _shown
		_blend_n = int(top.get("blend", 3)) if blending and not _from.is_empty() else 0
		_blend_start = tick
	var elapsed := tick - _blend_start
	blend_w = 1.0 if elapsed >= _blend_n else float(elapsed + 1) / float(_blend_n + 1)
	var d: Dictionary = picked[0]
	var t := clampf(float(picked[1]) / maxf(float(picked[2]), 1.0), 0.0, 1.0)
	var stash: Array = []
	var overlay_samples: Array = []
	for o in d.get("overlays", []) if grip_skeleton else []:
		sample_clip(String(o["clip"]), float(o["at"]) if o.has("at") else _seconds(o, picked[1], picked[2]))
		overlay_samples.append([current_clip, raw_time])
		for bone in _mask(o["bones"]):
			stash.append([bone, grip_skeleton.get_bone_pose(bone)])
	# sampled last, so the mouth and morph state come from the base clip
	sample_clip(String(d["clip"]), _seconds(d, picked[1], picked[2]))
	sampled = [[current_clip, raw_time]] + overlay_samples
	pivot.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float(face) * float(cfg["yaw"]))), Vector3.ZERO)
	if grip_skeleton == null:
		return
	var offset := grip_skeleton.get_bone_global_pose(grip_bone).affine_inverse() * grip_skeleton.get_bone_global_pose(weapon_bone)
	for item in stash:
		grip_skeleton.set_bone_pose(item[0], item[1])
	var crouch := _value(d.get("crouch", 0.0), t)
	if crouch != 0.0:
		_crouch(crouch)
	var aim := _value(d.get("aim", 0.0), t)
	var aim_arms := _value(d.get("aim_arms", 0.0), t)
	if (aim != 0.0 or aim_arms != 0.0) and aim_enabled:
		_aim(aim, float(d.get("aim_spine", AIM_SPINE)), aim_arms)
	var twist := _value(d.get("twist", 0.0), t)
	if twist != 0.0:
		_twist(twist, float(d.get("twist_head", 0.7)))
	var kick := Vector2(_value(d.get("kick", 0.0), t), _value(d.get("kick_up", 0.0), t))
	if kick != Vector2.ZERO:
		_kick(kick, _value(d.get("kick_in", 0.0), t), _value(d.get("kick_pitch", 0.0), t))
	var reach := Vector2(_value(d.get("reach", 0.0), t), _value(d.get("reach_up", 0.0), t))
	if reach != Vector2.ZERO:
		_reach(reach)
	var grip := Vector2(_value(d.get("grip", 0.0), t), _value(d.get("grip_up", 0.0), t))
	var grip_pitch := _value(d.get("grip_pitch", 0.0), t)
	if grip != Vector2.ZERO or grip_pitch != 0.0:
		_grip(grip, grip_pitch)
	var tilt := _value(d.get("tilt", 0.0), t)
	var spin := Basis(Vector3.UP, deg_to_rad(_value(d.get("turn", 0.0), t)))
	# the turn spins the body on its own vertical axis: about the model origin it would carry the hips sideways
	var hips := Vector3.ZERO if pelvis < 0 else _to_pivot() * grip_skeleton.get_bone_global_pose(pelvis).origin
	hips.y = 0.0
	var turned := Transform3D(spin, hips - spin * hips)
	var center := _tilt_center(String(d.get("tilt_pivot", "feet")), tilt, turned)
	layer = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(tilt)), center - Basis(Vector3.RIGHT, deg_to_rad(tilt)) * center) * turned
	layer.origin.y += _value(d.get("lift", 0.0), t)
	if blend_w < 1.0:
		# Bip001 (the skeleton's parent node) is animated per clip, so nodes blend with the bones. The gun's offset
		# blends with the arm and goes back on after, so it never slides off the hand; the feet blend as positions
		# (leg IK) so a leg swinging between two planted poses never dips through the floor.
		var feet := _feet()
		for k in baseline_nodes.size():
			var node: Node3D = baseline_nodes[k]["node"]
			node.transform = Transform3D(_from["nodes"][k]).interpolate_with(node.transform, blend_w)
		var from_bones: Array = _from["bones"]
		for k in skeletons.size():
			for i in skeletons[k].get_bone_count():
				skeletons[k].set_bone_pose(i, Transform3D(from_bones[k][i]).interpolate_with(skeletons[k].get_bone_pose(i), blend_w))
		var to_skeleton := _to_pivot().affine_inverse()
		for i in legs.size():
			_leg_ik(legs[i], to_skeleton * Transform3D(_from["feet"][i]).interpolate_with(feet[i], blend_w))
		offset = Transform3D(_from["offset"]).interpolate_with(offset, blend_w)
		layer = Transform3D(_from["layer"]).interpolate_with(layer, blend_w)
	grip_offset = offset
	reattach_weapon()
	pivot.transform = pivot.transform * layer
	var shown_bones: Array = []
	for sk in skeletons:
		var poses: Array = []
		for i in sk.get_bone_count():
			poses.append(sk.get_bone_pose(i))
		shown_bones.append(poses)
	var shown_nodes: Array = []
	for item in baseline_nodes:
		shown_nodes.append(item["node"].transform)
	_shown = {"key": anim_name, "tick": tick, "nodes": shown_nodes, "bones": shown_bones, "feet": _feet(), "offset": grip_offset, "layer": layer}
	if anim_name in ["down", "ko", "getup"]:
		_rest_on_floor()

## Raises a lying pose until its lowest torso bone is on the floor line, and only when one is below it (Hoshino's
## Vital_Death puts her right shoulder 0.048 units under). Hair, coat and wings spread wider than the body, so they are
## not counted. Kept out of the crossfade snapshot: each tick lifts only what its own pose needs.
func _rest_on_floor() -> void:
	var low := 0.0
	for b in torso:
		low = minf(low, (grip_skeleton.global_transform * grip_skeleton.get_bone_global_pose(b).origin).y)
	layer.origin.y -= low
	pivot.position.y -= low

## The phase that frame `mf` falls in, as [descriptor, frame inside it, its span]. A phase lasts its "over"
## (startup / active / recovery / a frame count); the last one runs to the move's last displayed frame, frames - 2
## (the sim leaves ATTACK on frames - 1), or for a state over the descriptor's "frames". Loop phases also run on
## through the hold frames (charge_t). Keys set on the descriptor (layers, overlays) apply to every phase.
func _phase(d: Dictionary, move: Dictionary, mf: float, charge_t: int) -> Array:
	if not d.has("phases"):
		return [d, float(mf + (charge_t if d.get("mode", "loop") == "loop" else 0)), float(move.get("frames", 2) - 2 if not move.is_empty() else d.get("frames", 0))]
	var phases: Array = d["phases"]
	var last := int(move.get("frames", 2)) - 2 if not move.is_empty() else int(d.get("frames", 0))
	var start := 0
	for i in phases.size():
		var p: Dictionary = phases[i]
		var end := maxi(last, start)
		if p.has("over"):
			var over: Variant = p["over"]
			end = start + (int(move.get(over, 0)) if over is String else int(over))
		if mf < end or i == phases.size() - 1:
			p = d.merged(p, true)
			return [p, float(mf - start + (charge_t if p.get("mode", "loop") == "loop" else 0)), float(end - start)]
		start = end
	return []

## Clip seconds for a descriptor `frame` ticks in. fit maps the span onto from..to; hold plays at speed and stops at
## `to`; loop wraps inside from..to. A negative speed runs each backwards (fit to..from, hold from `to`).
func _seconds(d: Dictionary, frame: float, span: float) -> float:
	var clip := String(d["clip"])
	var length := player.get_animation(clip).length if player.has_animation(clip) else 0.0
	var from := float(d.get("from", 0.0))
	var to := float(d.get("to", length))
	var speed := float(d.get("speed", 1.0))
	var elapsed := frame / Arena.FPS * speed
	match String(d.get("mode", "loop")):
		"fit":
			var k := clampf(frame / maxf(span, 1.0), 0.0, 1.0)
			return lerpf(from, to, k) if speed >= 0.0 else lerpf(to, from, k)
		"hold":
			return clampf((from if speed >= 0.0 else to) + elapsed, from, to)
	return from + fposmod(elapsed, maxf(to - from, 0.001))

## A layer value: a number, or keyframes [[t, value], ...] over t = 0..1 of the descriptor's span, linear between.
func _value(v: Variant, t: float) -> float:
	if not v is Array:
		return float(v)
	var keys: Array = v
	if t <= float(keys[0][0]):
		return float(keys[0][1])
	for i in keys.size() - 1:
		if t <= float(keys[i + 1][0]):
			return lerpf(float(keys[i][1]), float(keys[i + 1][1]), inverse_lerp(float(keys[i][0]), float(keys[i + 1][0]), t))
	return float(keys[-1][1])

## Grip skeleton bones matching the globs, minus the locked grip arm chain.
func _mask(globs: Array) -> Array:
	var key := str(globs)
	if not _masks.has(key):
		var list: Array = []
		for i in grip_skeleton.get_bone_count():
			if not locked.has(i):
				for g in globs:
					if grip_skeleton.get_bone_name(i).match(String(g)):
						list.append(i)
						break
		_masks[key] = list
	return _masks[key]

## Drops the pelvis `drop` world units and bends each leg so its foot stays where the clip put it.
func _crouch(drop: float) -> void:
	var feet := _feet()
	var to_skeleton := _to_pivot().affine_inverse()
	var hips := grip_skeleton.get_bone_global_pose(pelvis)
	hips.origin += to_skeleton.basis * Vector3(0.0, -drop, 0.0)
	_set_global(grip_skeleton, pelvis, hips)
	for i in legs.size():
		_leg_ik(legs[i], to_skeleton * feet[i], true)

func _find_aim_ids() -> void:
	if not _aim_ids.is_empty():
		return
	var sk := grip_skeleton
	var names: Dictionary = cfg["bones"]
	_aim_ids = {"spine": [], "arms": [], "neck": sk.find_bone(String(names["neck"]))}
	for n in names["spine"]:
		if sk.find_bone(String(n)) >= 0:
			_aim_ids["spine"].append(sk.find_bone(String(n)))
	for n in names["arms"]:
		if sk.find_bone(String(n)) >= 0:
			_aim_ids["arms"].append(sk.find_bone(String(n)))

## Upper-body aim: the spine bends and both arms swing about the shoulders' midpoint (so both hands stay on the gun)
## until the gun points `deg` degrees down (up when negative) in the model's side plane, while hips and legs keep the
## clip's stance. The neck gives part of the spine's bend back, so the head follows AIM_HEAD of the aim. `arms_extra`
## swings the arms that many degrees further, down when positive.
func _aim(deg: float, spine_share: float, arms_extra := 0.0) -> void:
	var sk := grip_skeleton
	_find_aim_ids()
	var axis := (_to_pivot().affine_inverse().basis * Vector3.RIGHT).normalized()
	var spine: Array = _aim_ids["spine"]
	for b in spine:
		_rotate_global(sk, b, Quaternion(axis, deg_to_rad(deg * spine_share / float(spine.size()))))
	var arms: Array = _aim_ids["arms"]
	var swing := Basis(Quaternion(axis, deg_to_rad(deg * (1.0 - spine_share) + arms_extra)))
	var chest := Vector3.ZERO
	for b in arms:
		chest += sk.get_bone_global_pose(b).origin / float(arms.size())
	for b in arms:
		var g := sk.get_bone_global_pose(b)
		_set_global(sk, b, Transform3D(swing * g.basis, chest + swing * (g.origin - chest)))
	if _aim_ids["neck"] >= 0:
		_rotate_global(sk, _aim_ids["neck"], Quaternion(axis, deg_to_rad(-deg * (spine_share - AIM_HEAD))))

## Twist layer: negative `deg` brings the left shoulder forward. The neck gives `head_share` of it back so the face stays
## on the foe.
func _twist(deg: float, head_share: float) -> void:
	_find_aim_ids()
	var axis := (_to_pivot().affine_inverse().basis * Vector3.UP).normalized()
	var spine: Array = _aim_ids["spine"]
	for b in spine:
		_rotate_global(grip_skeleton, b, Quaternion(axis, deg_to_rad(deg / float(spine.size()))))
	if _aim_ids["neck"] >= 0:
		_rotate_global(grip_skeleton, _aim_ids["neck"], Quaternion(axis, deg_to_rad(-deg * head_share)))

## Kick layer: the foot that stands further forward goes (forward, up) model units from where the clip put it, by leg IK;
## the other foot and the hips stay. The knee bends forward, as in a front kick.
## `inward` draws the foot's sideways position to the pelvis's: the stance puts the front foot 0.4 units to one side,
## which the facing yaw adds to one facing's reach and takes from the other. `pitch` is degrees about the lateral axis,
## negative lifting the toes.
func _kick(offset: Vector2, inward := 0.0, pitch := 0.0) -> void:
	var feet := _feet()
	var front := 0
	for i in legs.size():
		if feet[i].origin.z > feet[front].origin.z:
			front = i
	var target: Transform3D = feet[front]
	target.origin += Vector3(0.0, offset.y, offset.x)
	if inward != 0.0:
		target.origin.x = lerpf(target.origin.x, (_to_pivot() * grip_skeleton.get_bone_global_pose(pelvis).origin).x, inward)
	if pitch != 0.0:
		target.basis = Basis(Vector3.RIGHT, deg_to_rad(pitch)) * target.basis
	_leg_ik(legs[front], _to_pivot().affine_inverse() * target, true)

## Reach layer: the free left hand goes (forward, up) model units from where the clip put it, by arm IK with the elbow
## down and slightly out. The gun stays in the right hand, which no overlay or layer moves.
func _reach(offset: Vector2) -> void:
	if _arm_l.is_empty():
		for n in cfg["bones"]["arm_l"]:
			_arm_l.append(grip_skeleton.find_bone(String(n)))
	var target := grip_skeleton.get_bone_global_pose(_arm_l[2])
	target.origin += _to_pivot().affine_inverse().basis * Vector3(0.0, offset.y, offset.x)
	_leg_ik(_arm_l, target, true, Vector3(0.3, -1.0, 0.0))

## Grip layer: the gun hand goes (forward, up) from where the clip put it, then turns `pitch` degrees about the lateral
## axis (down when positive). reattach_weapon() carries the gun with the hand, so this also aims it.
func _grip(offset: Vector2, pitch: float) -> void:
	if _arm_r.is_empty():
		for n in cfg["bones"]["arm_l"]:
			_arm_r.append(grip_skeleton.find_bone(String(n).replace(" L ", " R ")))
	if offset != Vector2.ZERO:
		var target := grip_skeleton.get_bone_global_pose(_arm_r[2])
		target.origin += _to_pivot().affine_inverse().basis * Vector3(0.0, offset.y, offset.x)
		_leg_ik(_arm_r, target, true, Vector3(-0.3, -1.0, 0.0))
	if pitch != 0.0:
		_rotate_global(grip_skeleton, _arm_r[2], Quaternion((_to_pivot().affine_inverse().basis * Vector3.RIGHT).normalized(), deg_to_rad(pitch)))

## Clips authored in Blender (tools/sd_author) ship as a sidecar GLB with the model's node tree (no meshes) and their
## actions, so their track paths match this model's; tracks for nodes this model lacks are dropped. Scale tracks are
## dropped too: Blender's round trip brings the gun bone back at 0.0018 scale, and authored clips animate no scale.
func _merge_clips(path: String) -> void:
	var extra := (load(path) as PackedScene).instantiate()
	var source := extra.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var root := player.get_node(player.root_node)
	var library := player.get_animation_library("")
	for clip in source.get_animation_list():
		var anim := source.get_animation(clip).duplicate(true) as Animation
		for i in range(anim.get_track_count() - 1, -1, -1):
			var node_path := NodePath(String(anim.track_get_path(i)).get_slice(":", 0))
			if not root.has_node(node_path) or anim.track_get_type(i) == Animation.TYPE_SCALE_3D:
				anim.remove_track(i)
		library.add_animation(clip, anim)
	extra.free()

## Grip skeleton space to model space under the pivot (facing yaw and layers excluded).
func _to_pivot() -> Transform3D:
	return pivot.global_transform.affine_inverse() * grip_skeleton.global_transform

## Foot bone poses in model space, which (unlike skeleton space) stays put when a clip moves Bip001.
func _feet() -> Array:
	var to_pivot := _to_pivot()
	var list: Array = []
	for leg in legs:
		list.append(to_pivot * grip_skeleton.get_bone_global_pose(leg[2]))
	return list

## Two-bone IK: turns thigh and calf so the foot reaches `target` (skeleton space), then gives the foot its basis.
## The knee bends toward the model's forward (or `bend_to`, a model-space direction: the reach layer's elbow) when `ahead`
## is set (crouch), when the limb is straight, or when its own plane would put it under the floor; otherwise it keeps
## that plane (the crossfade's foot pinning, where a clip may point the knees anywhere).
func _leg_ik(leg: Array, target: Transform3D, ahead := false, bend_to := Vector3.ZERO) -> void:
	var sk := grip_skeleton
	var hip := sk.get_bone_global_pose(leg[0]).origin
	var knee := sk.get_bone_global_pose(leg[1]).origin
	var foot := sk.get_bone_global_pose(leg[2]).origin
	var upper := hip.distance_to(knee)
	var lower := knee.distance_to(foot)
	var dir := (target.origin - hip).normalized()
	var reach := clampf(hip.distance_to(target.origin), absf(upper - lower) + 1e-4, upper + lower - 1e-4)
	var bend := (knee - hip) - dir * (knee - hip).dot(dir)
	var to_pivot := _to_pivot()
	var forward := (to_pivot.affine_inverse().basis * (Vector3.BACK if bend_to == Vector3.ZERO else bend_to)).normalized()
	var pole := forward - dir * forward.dot(dir)
	# a wide stance tilts the hip-to-foot line outward once the pelvis drops, which turns the kept plane inward
	if (ahead and pole.length() > 0.1) or bend.length() < 0.05 * upper:
		bend = pole
	var along := (upper * upper - lower * lower + reach * reach) / (2.0 * reach)
	var side := sqrt(maxf(0.0, upper * upper - along * along))
	var want_knee := hip + dir * along + bend.normalized() * side
	var forward_knee := hip + dir * along + pole.normalized() * side
	# a crossfade out of a lying pose (down -> getup) swings the kept plane through the floor
	if pole.length() > 0.1 and (to_pivot * want_knee).y < minf(0.0, (to_pivot * forward_knee).y):
		want_knee = forward_knee
	_rotate_global(sk, leg[0], Quaternion((knee - hip).normalized(), (want_knee - hip).normalized()))
	knee = sk.get_bone_global_pose(leg[1]).origin
	foot = sk.get_bone_global_pose(leg[2]).origin
	_rotate_global(sk, leg[1], Quaternion((foot - knee).normalized(), (hip + dir * reach - knee).normalized()))
	_set_global(sk, leg[2], Transform3D(target.basis, sk.get_bone_global_pose(leg[2]).origin))

func _rotate_global(sk: Skeleton3D, bone: int, q: Quaternion) -> void:
	var g := sk.get_bone_global_pose(bone)
	_set_global(sk, bone, Transform3D(Basis(q) * g.basis, g.origin))

func _set_global(sk: Skeleton3D, bone: int, g: Transform3D) -> void:
	var parent := sk.get_bone_parent(bone)
	sk.set_bone_pose(bone, sk.get_bone_global_pose(parent).affine_inverse() * g if parent >= 0 else g)

## The point the tilt turns about, in layer space (model space after the turn, `spin`). "feet": the foot that would
## sink, on the floor, so the lean rolls over it; "plant": the lower foot, which a kick leaves as the only one on the
## floor; "hips": the pelvis.
func _tilt_center(kind: String, tilt: float, spin: Transform3D) -> Vector3:
	if tilt == 0.0 or grip_skeleton == null or legs.is_empty():
		return Vector3.ZERO
	var to_pivot := _to_pivot()
	if kind == "hips":
		return spin * (to_pivot * grip_skeleton.get_bone_global_pose(pelvis).origin)
	var z := -INF if tilt > 0.0 else INF
	var low := INF
	for leg in legs:
		var foot: Vector3 = spin * (to_pivot * grip_skeleton.get_bone_global_pose(leg[2]).origin)
		if kind == "plant":
			if foot.y < low:
				low = foot.y
				z = foot.z
		else:
			z = maxf(z, foot.z) if tilt > 0.0 else minf(z, foot.z)
	return Vector3(0.0, 0.0, z)

## Bip001_Weapon is not a child of the hand: anything that moves the arm after the base sample would leave the gun
## behind, so the weapon goes back to grip hand * grip_offset. A clip that parks the gun far off to hide it keeps it
## there (Hoshino's Victory clips put it about 100 units from the hand).
func reattach_weapon() -> void:
	var target := grip_skeleton.get_bone_global_pose(grip_bone) * grip_offset
	var parent := grip_skeleton.get_bone_parent(weapon_bone)
	if parent >= 0:
		target = grip_skeleton.get_bone_global_pose(parent).affine_inverse() * target
	grip_skeleton.set_bone_pose(weapon_bone, target)

func anchor_local(kind: String) -> Vector2:
	if kind == "muzzle" and not muzzle_socket.is_empty():
		var skeleton: Skeleton3D = muzzle_socket["skeleton"]
		var point: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(muzzle_socket["bone"]) * muzzle_socket["local"]
		return (camera.unproject_position(point) + body.offset) * body.scale
	var names: Array = [cfg["bones"]["head"]] if kind == "head" else cfg["muzzle"] + [cfg["bones"]["weapon"]]
	for name in names:
		for skeleton in skeletons:
			var i := skeleton.find_bone(name)
			if i >= 0:
				var point: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(i).origin
				return (camera.unproject_position(point) + body.offset) * body.scale
		var node := model.find_child(name, true, false) as Node3D
		if node:
			return (camera.unproject_position(node.global_position) + body.offset) * body.scale
	return Vector2(0, -200)

func describe() -> Dictionary:
	return {"model": cfg["model"], "anim": anim_name, "clip": current_clip, "time": current_time, "facing": facing,
		"head": anchor_local("head"), "muzzle": anchor_local("muzzle"), "viewport": viewport.size}
