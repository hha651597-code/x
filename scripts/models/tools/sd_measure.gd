extends SceneTree
## Measures every roster fighter with an sd.json into assets/ba/sd/<key>/sockets.json (read by sd_sockets.gd):
##   muzzle   per kit move and spawn / shot frame, the projected muzzle in fight px from the feet, facing-right convention,
##            posed through pose() with blending off: "right" facing right, "left" facing left, "sym" their mean (the
##            symmetric gameplay offset; a mean of |x| would hide a muzzle on the wrong side)
##   hurtbox  {w, h, crouch_h} from torso bones, not the Body mesh (Hina's spans its wing-weighted vertices and hair)
##   push     the full width of the body cylinder fighters push each other with, see push_width()
## Run with tools/sd_measure.sh (a real small window). The suite re-measures with measure() and encode()
## and compares, so the files stay current. Game scripts are load()ed inside _run(): preloading them here would parse
## them before the autoloads exist.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(120.0).timeout.connect(func():
		print("SD_MEASURE FAIL watchdog timeout")
		quit(3))
	await process_frame
	var config: Script = load("res://scripts/models/sd_config.gd")
	var fighter_script: Script = load("res://scripts/fight/fighter.gd")
	var written := 0
	for entry in root.get_node("Game").fighters:
		var key := String(entry.get("key", ""))
		if config.of(key).is_empty():
			continue
		# kept alive until quit: freeing an SD actor mid-run printed renderer "material is null" errors in the suite
		var f: Node = fighter_script.new()
		f.visible = false
		root.add_child(f)
		f.setup(entry, 1, {})
		if not f.view.sd_mode:
			print("SD_MEASURE FAIL %s has an sd.json but no SD actor" % key)
			quit(1)
			return
		var data := measure(f.moves, f.view.sd_actor)
		var path := "res://assets/ba/sd/%s/sockets.json" % key
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			print("SD_MEASURE FAIL cannot write ", path)
			quit(1)
			return
		file.store_string(encode(data))
		file.close()
		written += 1
		print("SD_MEASURE %s hurtbox %s (default w 92 h 272 crouch_h 168), push %d (default 74), %d moves -> %s" % [key, JSON.stringify(data["hurtbox"]), data["push"], data["muzzle"].size(), path])
	print("SD_MEASURE PASS wrote %d sockets.json" % written)
	quit(0)

## The (move frame, charge_t) ticks each spawn and shot frame of `move` fires on, keyed by that frame, as the sim fires
## them: the stream (hold_fire) at hold.at - 1 on every fire_every-th held tick, a spawn after the hold at no charge and at
## its min and max charge, everything else at charge 0. Spawns at the foe or the floor leave no muzzle.
static func ticks(move: Dictionary) -> Dictionary:
	var hold: Dictionary = move.get("hold", {})
	var out := {}
	for s in move.get("shots", []):
		out[int(s)] = [Vector2i(int(s), 0)]
	for sp in move["spawns"]:
		if sp.get("at_foe", false) or sp.get("rel_owner", false):
			continue
		var fr := int(sp["frame"])
		var at: Array = []
		if sp.get("hold_fire", false):
			for c in range(1, int(hold["max"]) + 1):
				if c % int(hold["fire_every"]) == 1:
					at.append(Vector2i(int(hold["at"]) - 1, c))
		elif not hold.is_empty() and fr >= int(hold["at"]):
			for c in [0, int(sp.get("min_charge", 0)), int(hold["max"])]:
				if c >= int(sp.get("min_charge", 0)) and c <= int(sp.get("max_charge", 99999)):
					at.append(Vector2i(fr, c))
		else:
			at.append(Vector2i(fr, 0))
		var list: Array = out.get(fr, [])
		for t in at:
			if not t in list:
				list.append(t)
		out[fr] = list
	return out

## Muzzles of every move in `moves` (frame entries averaged over their ticks), the hurtbox and the push width, from `actor`.
static func measure(moves: Dictionary, actor: Node) -> Dictionary:
	var blending: bool = actor.blending
	actor.blending = false
	var muzzle := {}
	for key in moves:
		var move: Dictionary = moves[key]
		var at := ticks(move)
		var frames: Array = at.keys()
		frames.sort()
		var list: Array = []
		for fr in frames:
			var sum := {1: Vector2.ZERO, -1: Vector2.ZERO}
			for t in at[fr]:
				for face in [1, -1]:
					actor.pose("attack", 0, key, move, t.x, t.y, face)
					sum[face] += actor.anchor_local("muzzle") * Vector2(face, 1)
			var right: Vector2 = sum[1] / float(at[fr].size())
			var left: Vector2 = sum[-1] / float(at[fr].size())
			list.append({"frame": fr, "right": _px(right), "left": _px(left), "sym": _px((right + left) * 0.5)})
		if not list.is_empty():
			muzzle[key] = list
	var stand := _body(actor, "idle")
	var low := _body(actor, "crouch")
	actor.blending = blending
	var hurtbox := {}
	if not stand.is_empty() and not low.is_empty():
		hurtbox = {"w": roundi((stand[1] + stand[-1]) * 0.5), "h": roundi(-stand["top"]), "crouch_h": roundi(-low["top"])}
	return {"hurtbox": hurtbox, "push": push_width(actor), "muzzle": muzzle}

# push width
## What counts as the trunk, and from what height: the stance spread and the coat hem below it do not.
const TRUNK := ["torso", "hips", "skirt", "head"]
const TRUNK_FROM := 60.0
const PUSH_ANIMS := ["idle", "crouch", "block", "block_low"]
const PUSH_SAMPLES := 10

## The full width of the body cylinder: twice the largest front reach (toward the foe, from the feet origin, whole px
## rounded up) of the trunk (torso, hips, skirt and head, at heights of TRUNK_FROM px and up) over idle, crouch, block and
## block_low, both facings, each taken as the median of PUSH_SAMPLES poses spread over the anim. Hair, guns, wings, arms,
## legs and the coat hem stand outside it. 0 when the actor has no skeleton or none of the anims.
static func push_width(actor: Node) -> int:
	var prep := trunk_prep(actor)
	if prep.is_empty():
		return 0
	var blending: bool = actor.blending
	actor.blending = false
	var reach := 0.0
	for anim in PUSH_ANIMS:
		if not actor.cfg["anims"].has(anim):
			continue
		var span := anim_span(actor, actor.cfg["anims"][anim])
		var n := mini(span, PUSH_SAMPLES)
		for face in [1, -1]:
			var front: Array = []
			for i in n:
				actor.pose(anim, roundi(float(i) * float(span - 1) / float(maxi(n - 1, 1))), "", {}, 0, 0, face)
				var e := trunk_extent(actor, prep)
				front.append(e.y if face == 1 else -e.x)
			front.sort()
			reach = maxf(reach, (float(front[(n - 1) >> 1]) + float(front[n >> 1])) * 0.5)
	actor.blending = blending
	return 2 * ceili(reach)

## Ticks an anim descriptor plays over (the preview's count, so the samples land where the sheets do).
static func anim_span(actor: Node, d: Dictionary) -> int:
	if d.has("frames"):
		return maxi(1, int(d["frames"]))
	var n := 0.0
	for p in d.get("phases", [d]):
		var over: Variant = p.get("over")
		if over is float or over is int:
			n += float(over)
			continue
		var q: Dictionary = d.merged(p, true)
		var clip := String(q.get("clip", ""))
		var length: float = actor.player.get_animation(clip).length if actor.player.has_animation(clip) else 1.0
		var speed := absf(float(q.get("speed", 1.0)))
		n += (float(q.get("to", length)) - float(q.get("from", 0.0))) * Arena.FPS / speed if speed > 0.0 else Arena.FPS
	return clampi(ceili(n) + 1, 1, 600)

## The body group of a skinned vertex from the name of its dominant bone (the Body mesh is one mesh holding body, hair,
## coat and wings, so mesh visibility cannot split it).
static func _group(bone_name: String, surface: String) -> String:
	if "Wing" in bone_name:
		return "wings"
	if "Hair" in surface or bone_name.begins_with("bone_hair"):
		return "hair"
	if bone_name.begins_with("bone_skirt"):
		return "skirt"
	if bone_name.begins_with("jacket") or bone_name.begins_with("bone_ja") or bone_name.begins_with("coat") or bone_name.begins_with("bone_coat"):
		return "coat"
	if "Pelvis" in bone_name:
		return "hips"
	if "Thigh" in bone_name or "Calf" in bone_name or "Foot" in bone_name or "Toe" in bone_name:
		return "legs"
	if "UpperArm" in bone_name or "Forearm" in bone_name or "ForeArm" in bone_name or "Hand" in bone_name or "Finger" in bone_name or "Wrist" in bone_name or "Deltoid" in bone_name or "Twist" in bone_name:
		return "arms"
	if "Spine" in bone_name or "Neck" in bone_name or "Clavicle" in bone_name:
		return "torso"
	if "Head" in bone_name or "eye" in bone_name or "Mouth" in bone_name or "Xtra" in bone_name:
		return "head"
	return "other"

## The trunk vertices of every skinned mesh of `actor` with their skin weights, for trunk_extent().
static func trunk_prep(actor: Node) -> Array:
	var out: Array = []
	var sk: Skeleton3D = actor.grip_skeleton
	if sk == null:
		return out
	for m in actor.meshes:
		if String(m.name).begins_with("Mouth") or "Weapon" in String(m.name) or m.skin == null or m in actor.hidden_meshes:
			continue
		var skin: Skin = m.skin
		var bone_of := PackedInt32Array()
		for k in skin.get_bind_count():
			var bi := skin.get_bind_bone(k)
			bone_of.append(bi if bi >= 0 else sk.find_bone(skin.get_bind_name(k)))
		for s in m.mesh.get_surface_count():
			var arr: Array = m.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bn: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var wt: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var surface := String(m.mesh.surface_get_name(s))
			var keep := {"skin": skin, "bone_of": bone_of, "verts": PackedVector3Array(), "bn": PackedInt32Array(), "wt": PackedFloat32Array()}
			for i in verts.size():
				var best := 0
				for j in 4:
					if wt[i * 4 + j] > wt[i * 4 + best]:
						best = j
				if _group(sk.get_bone_name(bone_of[bn[i * 4 + best]]), surface) in TRUNK:
					keep["verts"].append(verts[i])
					keep["bn"].append_array(bn.slice(i * 4, i * 4 + 4))
					keep["wt"].append_array(wt.slice(i * 4, i * 4 + 4))
			out.append(keep)
	return out

## (left, right) edge of the trunk in the actor's current pose: skinned on the CPU, in fight px from the feet origin,
## +x screen right, over the vertices TRUNK_FROM px above the feet and higher.
static func trunk_extent(actor: Node, prep: Array) -> Vector2:
	var sk: Skeleton3D = actor.grip_skeleton
	var to_world: Transform3D = sk.global_transform
	var px: float = actor.WORLD_PX
	var lo := INF
	var hi := -INF
	for p in prep:
		var skin: Skin = p["skin"]
		var bone_of: PackedInt32Array = p["bone_of"]
		var xf: Array = []
		for k in skin.get_bind_count():
			xf.append(to_world * sk.get_bone_global_pose(bone_of[k]) * skin.get_bind_pose(k))
		var verts: PackedVector3Array = p["verts"]
		var bn: PackedInt32Array = p["bn"]
		var wt: PackedFloat32Array = p["wt"]
		for i in verts.size():
			var at := Vector3.ZERO
			for j in 4:
				if wt[i * 4 + j] > 0.0:
					at += (xf[bn[i * 4 + j]] as Transform3D) * verts[i] * wt[i * 4 + j]
			if at.y * px >= TRUNK_FROM:
				lo = minf(lo, at.x * px)
				hi = maxf(hi, at.x * px)
	return Vector2(lo, hi)

## Bone extents of `anim` at its first tick: the width per facing (1, -1) across the shoulders (* UpperArm), pelvis and
## feet, and "top", the crown (the head bone raised sd.json "crown"). The width differs about 3x between facings (the
## stance is seen across facing right, end on facing left); measure() takes the mean.
static func _body(actor: Node, anim: String) -> Dictionary:
	var sk: Skeleton3D = actor.grip_skeleton
	if sk == null or actor.pelvis < 0:
		return {}
	var bones: Array = [actor.pelvis]
	for leg in actor.legs:
		bones.append(leg[2])
	for i in sk.get_bone_count():
		if sk.get_bone_name(i).ends_with(" UpperArm"):
			bones.append(i)
	var head := sk.find_bone(String(actor.cfg["bones"]["head"]))
	if head < 0 or bones.size() < 5:
		return {}
	var out := {}
	for face in [1, -1]:
		actor.pose(anim, 0, "", {}, 0, 0, face)
		var xs: Array = []
		for b in bones:
			xs.append(_screen(actor, sk.global_transform * sk.get_bone_global_pose(b).origin).x)
		out[face] = float(xs.max()) - float(xs.min())
		out["top"] = _screen(actor, sk.global_transform * sk.get_bone_global_pose(head).origin + Vector3(0.0, float(actor.cfg["crown"]), 0.0)).y
	return out

static func _screen(actor: Node, world: Vector3) -> Vector2:
	return (actor.camera.unproject_position(world) + actor.body.offset) * actor.body.scale

static func _px(v: Vector2) -> Array:
	return [snappedf(v.x, 0.1) + 0.0, snappedf(v.y, 0.1) + 0.0]

## One move per block, one frame entry per line, keys sorted: a re-run gives the same bytes.
static func encode(data: Dictionary) -> String:
	var lines: Array[String] = ["{", "\t\"hurtbox\": %s," % JSON.stringify(data["hurtbox"]), "\t\"push\": %d," % data["push"], "\t\"muzzle\": {"]
	var keys: Array = data["muzzle"].keys()
	keys.sort()
	for i in keys.size():
		lines.append("\t\t\"%s\": [" % keys[i])
		var list: Array = data["muzzle"][keys[i]]
		for j in list.size():
			lines.append("\t\t\t%s%s" % [JSON.stringify(list[j]), "," if j < list.size() - 1 else ""])
		lines.append("\t\t]%s" % ("," if i < keys.size() - 1 else ""))
	lines.append("\t}")
	lines.append("}")
	return "\n".join(lines) + "\n"
