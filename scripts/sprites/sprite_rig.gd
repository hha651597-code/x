class_name SpriteRig
extends Node2D
## A skeletal sprite puppet built from the student's REAL Spine standing-sprite parts
## (assets/ba/rig/<name>/rig.json, built from the Spine data plus a joint spec).
##
## * the body is one (or a few) mesh(es) skinned to a Skeleton2D — pose any bone to bend limbs, lean, crouch…
## * faces are the official expression sprites (swap with set_face), with an optional blink layer
## * halo glow layers follow the head bone
## Origin = the fighter's feet (y down); units are rig px (about 1000 px tall) — scale the node to fit.
##
## Bone pose format: {bone: [rot_deg, dx, dy]} or [rot_deg, dx, dy, sx, sy]; missing bones stay at rest.

const RIG_DIR := "res://assets/ba/rig/"

var rig_name := ""
var height := 1000.0
var skeleton: Skeleton2D
var bones: Dictionary = {}          # name -> Bone2D
var _rest_pos: Dictionary = {}      # name -> Vector2 (local to parent)
var _rest_global: Dictionary = {}   # name -> Vector2 (rig space)
var _statics: Array = []            # {node, bone}
var face_nodes: Dictionary = {}     # expression key -> Node2D
var _blink_node: Node2D
var _cur_face := ""
var _blink := false
var glow_scale := 1.0

static func exists(rname: String) -> bool:
	return FileAccess.file_exists(RIG_DIR + rname + "/rig.json")

static func load_rig(rname: String) -> SpriteRig:
	if not exists(rname):
		return null
	var f := FileAccess.open(RIG_DIR + rname + "/rig.json", FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var r := SpriteRig.new()
	r.rig_name = rname
	r._build(data)
	return r

func _build(data: Dictionary) -> void:
	height = float(data.get("height", 1000.0))
	skeleton = Skeleton2D.new()
	skeleton.name = "Skeleton"
	add_child(skeleton)
	# bones (parents are listed before children)
	for b in data["bones"]:
		var bone := Bone2D.new()
		bone.name = b["name"]
		var head := Vector2(b["head"][0], b["head"][1])
		var tail := Vector2(b["tail"][0], b["tail"][1])
		var parent_name: String = b["parent"]
		var parent_global := Vector2.ZERO
		var parent_node: Node = skeleton
		if parent_name != "":
			parent_node = bones[parent_name]
			parent_global = _rest_global[parent_name]
		var local := head - parent_global
		parent_node.add_child(bone)
		bone.position = local
		bone.rest = Transform2D(0.0, local)
		bone.set_autocalculate_length_and_angle(false)
		bone.set_length(maxf(1.0, head.distance_to(tail)))
		bone.set_bone_angle((tail - head).angle())
		bones[b["name"]] = bone
		_rest_pos[b["name"]] = local
		_rest_global[b["name"]] = head
	# layers in draw order
	var tex_cache := {}
	for L in data["layers"]:
		var key: String = L["png"]
		if not tex_cache.has(key):
			tex_cache[key] = load(RIG_DIR + rig_name + "/" + key)
		var tex: Texture2D = tex_cache[key]
		var poly := Polygon2D.new()
		poly.name = String(L["name"]).replace("/", "_")
		poly.texture = tex
		var verts := PackedVector2Array()
		for v in L["verts"]:
			verts.append(Vector2(v[0], v[1]))
		poly.polygon = verts
		var uvs := PackedVector2Array()
		for u in L["uvs"]:
			uvs.append(Vector2(u[0], u[1]))
		poly.uv = uvs
		var tris: Array = []
		for t in L["tris"]:
			tris.append(PackedInt32Array([int(t[0]), int(t[1]), int(t[2])]))
		poly.polygons = tris
		var col: Array = L.get("color", [1, 1, 1, 1])
		poly.color = Color(col[0], col[1], col[2], col[3])
		if L["blend"] == "additive":
			var m := CanvasItemMaterial.new()
			m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			poly.material = m
		elif L["blend"] == "multiply":
			var m2 := CanvasItemMaterial.new()
			m2.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
			poly.material = m2
		poly.set_meta("group", L["group"])
		add_child(poly)
		if L["kind"] == "skinned":
			poly.skeleton = poly.get_path_to(skeleton)
			var weights: Dictionary = L["weights"]
			for bname in weights:
				var arr := PackedFloat32Array()
				for w in weights[bname]:
					arr.append(float(w))
				poly.add_bone(skeleton.get_path_to(bones[bname]), arr)
		else:
			_statics.append({"node": poly, "bone": L["bone"]})
			var grp: String = L["group"]
			if grp == "face":
				if String(L["key"]).begins_with("eyeclose"):
					_blink_node = poly
					poly.visible = false
				else:
					face_nodes[L["key"]] = poly
					poly.visible = bool(L["default"])
					if poly.visible:
						_cur_face = L["key"]
	set_pose({})

## Pose the skeleton. Bones not in `pose` return to rest.
func set_pose(pose: Dictionary) -> void:
	for bname in bones:
		var bone: Bone2D = bones[bname]
		var p = pose.get(bname, null)
		if p == null:
			bone.position = _rest_pos[bname]
			bone.rotation = 0.0
			bone.scale = Vector2.ONE
		else:
			bone.position = _rest_pos[bname] + Vector2(p[1] if p.size() > 1 else 0.0, p[2] if p.size() > 2 else 0.0)
			bone.rotation = deg_to_rad(p[0])
			bone.scale = Vector2(p[3] if p.size() > 3 else 1.0, p[4] if p.size() > 4 else 1.0)
	_sync_statics()

func _sync_statics() -> void:
	for s in _statics:
		var bname: String = s["bone"]
		if bname == "" or not bones.has(bname):
			continue
		var bone: Bone2D = bones[bname]
		var cur: Transform2D = bone.get_relative_transform_to_parent(self)
		(s["node"] as Node2D).transform = cur * Transform2D(0.0, -(_rest_global[bname] as Vector2))

## Show an official expression sprite by key (e.g. "01_normal", "06_shout"); false if unknown.
func set_face(key: String) -> bool:
	if not face_nodes.has(key):
		return false
	if _cur_face != "" and face_nodes.has(_cur_face):
		(face_nodes[_cur_face] as Node2D).visible = false
	_cur_face = key
	(face_nodes[key] as Node2D).visible = not _blink
	return true

func face() -> String:
	return _cur_face

func face_keys() -> Array:
	return face_nodes.keys()

## Blink: hide the open-eyes face and show the closed-eyes layer.
func set_blink(on: bool) -> void:
	_blink = on
	if _blink_node:
		_blink_node.visible = on
	if face_nodes.has(_cur_face):
		(face_nodes[_cur_face] as Node2D).visible = not on

## Tint everything (hit flash etc.).
func set_tint(c: Color) -> void:
	for ch in get_children():
		if ch is Polygon2D and ch.get_meta("group", "") != "halo":
			(ch as Polygon2D).self_modulate = c

func set_halo_visible(v: bool) -> void:
	for ch in get_children():
		if ch is Polygon2D and ch.get_meta("group", "") == "halo":
			ch.visible = v

func bone_world(bname: String) -> Vector2:
	if not bones.has(bname):
		return Vector2.ZERO
	return (bones[bname] as Bone2D).get_relative_transform_to_parent(self) * Vector2.ZERO
