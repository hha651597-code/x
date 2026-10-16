class_name StageSky
extends Node3D

const SKY_SHADER := "res://shaders/stage_sky.gdshader"
const CLOUD_SHADER := "res://shaders/stage_sky_cloud.gdshader"
const DISC_SHADER := "res://shaders/stage_sky_disc.gdshader"

var stage_time := 0.0
var cfg: Dictionary
var pal: Dictionary
var night := false
var rest := Vector3.ZERO
var sun_dir := Vector3.UP
var sky_mat: ShaderMaterial
var layers: Array = []
var far_distance := 0.0
var _mesh_src: Node
var _mats := {}


func setup(info: Dictionary, dir: String, cam: Camera3D, env: Environment, arena: Node = null) -> void:
	cfg = info["sky"]
	pal = cfg["palette"]
	night = bool(info["night"])
	rest = StageCamera.solve(info["lane"], info["camera"], 0.0, 1.0).origin
	var cel: Dictionary = cfg["celestial"]
	sun_dir = _dir(cel["az"], cel["el"])
	_mesh_src = (load(cfg["meshes"]) as PackedScene).instantiate()
	_build_dome(env)
	for l: Dictionary in cfg["layers"]:
		_build_layer(l, dir)
		far_distance = maxf(far_distance, float(l.get("dist", 0.0)))
	_build_celestial()
	far_distance = maxf(far_distance, float(cel["dist"]))
	_mesh_src.free()
	if arena != null:
		for mi: MeshInstance3D in arena.find_children("*Cloud*", "MeshInstance3D", true, false):
			mi.visible = false
	set_stage_time(0.0)
	follow(cam.global_position)


func set_stage_time(t: float) -> void:
	stage_time = t
	if night:
		sky_mat.set_shader_parameter("stage_time", t)
	for layer: Dictionary in layers:
		if layer["drift"] != 0.0:
			_place_layer_items(layer)


func follow(cam_pos: Vector3) -> void:
	for layer: Dictionary in layers:
		var node: Node3D = layer["node"]
		node.global_position = layer["base"] + layer["follow"] * (cam_pos - rest)


func _dir(az_deg: float, el_deg: float) -> Vector3:
	var az := deg_to_rad(az_deg)
	var el := deg_to_rad(el_deg)
	return Vector3(cos(el) * cos(az), sin(el), cos(el) * sin(az))


func _build_dome(env: Environment) -> void:
	var g: Dictionary = cfg["gradient"]
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load(SKY_SHADER)
	sky_mat.set_shader_parameter("_SkyColor", StageLoader.color3(g["sky_color"]))
	sky_mat.set_shader_parameter("_EquatorColor", StageLoader.color3(g["equator_color"]))
	sky_mat.set_shader_parameter("_SkyGradient", g["sky_gradient"])
	sky_mat.set_shader_parameter("_EquatorOffset", g["equator_offset"])
	var h: Dictionary = pal["haze"]
	sky_mat.set_shader_parameter("haze_color", StageLoader.color3(h["color"]))
	sky_mat.set_shader_parameter("haze_height", h["height"])
	sky_mat.set_shader_parameter("haze_strength", h["strength"])
	var gl: Dictionary = pal["glow"]
	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	sky_mat.set_shader_parameter("glow_color", StageLoader.color3(gl["color"]))
	sky_mat.set_shader_parameter("glow_strength", gl["strength"])
	sky_mat.set_shader_parameter("glow_size", gl["size"])
	sky_mat.set_shader_parameter("horizon_glow_strength", gl["horizon"])
	sky_mat.set_shader_parameter("stars_amount", pal["stars"])
	if pal.has("star_color"):
		sky_mat.set_shader_parameter("star_color", StageLoader.color3(pal["star_color"]))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.background_mode = Environment.BG_SKY
	env.sky = sky


func _cloud_mat(layer: Dictionary, baked: bool) -> ShaderMaterial:
	var key := "%s%s" % [layer["name"], baked]
	if _mats.has(key):
		return _mats[key]
	var c: Dictionary = pal["cloud"]
	var m := ShaderMaterial.new()
	m.shader = load(CLOUD_SHADER)
	m.render_priority = int(layer["priority"])
	m.set_shader_parameter("tint_alpha", c["alpha"])
	m.set_shader_parameter("lit_color", StageLoader.color3(c["lit"]))
	m.set_shader_parameter("mid_color", StageLoader.color3(c["mid"]))
	m.set_shader_parameter("shade_color", StageLoader.color3(c["shade"]))
	m.set_shader_parameter("sun_color", StageLoader.color3(c["sun"]))
	m.set_shader_parameter("haze_color", StageLoader.color3(pal["haze"]["color"]))
	m.set_shader_parameter("haze_height", pal["haze"]["height"])
	m.set_shader_parameter("sun_dir", sun_dir)
	m.set_shader_parameter("layer_alpha", layer["alpha"])
	m.set_shader_parameter("haze_amount", layer["haze"])
	m.set_shader_parameter("baked", 1 if baked else 0)
	_mats[key] = m
	return m


func _mesh(mesh_name: String) -> MeshInstance3D:
	return _mesh_src.find_child(mesh_name, true, false) as MeshInstance3D


func _plane(mesh_name: String) -> String:
	for p: String in cfg["planes"]["xy"]:
		if mesh_name.begins_with(p):
			return "xy"
	return "xz"


func _build_layer(l: Dictionary, dir: String) -> void:
	var node := Node3D.new()
	node.name = "Layer_" + String(l["name"])
	add_child(node)
	var world: bool = l.get("world", false)
	var layer := {"name": l["name"], "node": node, "follow": float(l["follow"]), "drift": float(l["drift"]), "base": Vector3.ZERO if world else rest, "dist": float(l.get("dist", 0.0)), "items": []}
	layers.append(layer)
	if world:
		for b: Dictionary in StageLoader.read_json(dir.path_join(cfg["bank"])):
			var src := _mesh(b["mesh"])
			var mi := _instance(node, src, _cloud_mat(l, false))
			var q: Array = b["quat"]
			var s := StageLoader.color3(b["scale"])
			mi.transform = Transform3D(Basis(Quaternion(q[0], q[1], q[2], q[3])) * Basis.from_scale(s), StageLoader.color3(b["pos"]))
			mi.set_instance_shader_parameter("up_half_world", src.mesh.get_aabb().size.z * 0.5 * absf(s.z))
		return
	var i := 0
	for it: Array in l["items"]:
		var src := _mesh(it[0])
		var mi := _instance(node, src, _cloud_mat(l, String(it[0]).begins_with("Muk_")))
		var item := {"mi": mi, "name": it[0], "az": float(it[1]), "el": float(it[2]), "w": float(it[3]), "flip": int(it[4]) == 1, "roll": float(it[5]), "speed": 0.6 + 0.8 * fmod(absf(sin(float(i) * 12.9898 + 4.1)) * 43758.5, 1.0)}
		layer["items"].append(item)
		mi.set_instance_shader_parameter("up_half_world", _up_extent(mi, it[0]) * 0.5 * _scale_for(mi, layer["dist"], item["w"]))
		i += 1
	_place_layer_items(layer)


func _instance(parent: Node3D, src: MeshInstance3D, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = src.mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _scale_for(mi: MeshInstance3D, dist: float, width_deg: float) -> float:
	return 2.0 * dist * tan(deg_to_rad(width_deg) * 0.5) / mi.mesh.get_aabb().size.x


func _up_extent(mi: MeshInstance3D, mesh_name: String) -> float:
	var bb := mi.mesh.get_aabb()
	return bb.size.y if _plane(mesh_name) == "xy" else bb.size.z


func _place_layer_items(layer: Dictionary) -> void:
	for it: Dictionary in layer["items"]:
		var az: float = it["az"] + layer["drift"] * it["speed"] * stage_time
		_place(it["mi"], it["name"], az, it["el"], layer["dist"], it["w"], it["flip"], it["roll"])


func _place(mi: MeshInstance3D, mesh_name: String, az: float, el: float, dist: float, width_deg: float, flip: bool, roll: float) -> void:
	var d := _dir(az, el)
	var n := -d
	var right := Vector3.UP.cross(n).normalized()
	var up := n.cross(right).normalized()
	var s := _scale_for(mi, dist, width_deg)
	var b: Basis = Basis(right, up, n) if _plane(mesh_name) == "xy" else Basis(right, -n, up)
	b = Basis(n, deg_to_rad(roll)) * b
	b = b * Basis.from_scale(Vector3(-s if flip else s, s, s))
	mi.transform = Transform3D(b, d * dist)


func _build_celestial() -> void:
	var cel: Dictionary = cfg["celestial"]
	var node := Node3D.new()
	node.name = "Layer_celestial"
	add_child(node)
	layers.append({"name": "celestial", "node": node, "follow": 1.0, "drift": 0.0, "base": rest, "dist": float(cel["dist"]), "items": []})
	var mesh_name: String = cel["moon_mesh"] if night else cel["sun_mesh"]
	var m := ShaderMaterial.new()
	m.shader = load(DISC_SHADER)
	m.render_priority = -10
	m.set_shader_parameter("color", StageLoader.color3(pal["moon_disc"] if night else pal["sun_disc"]))
	m.set_shader_parameter("kind", 1 if night else 0)
	var mi := _instance(node, _mesh(mesh_name), m)
	_place(mi, mesh_name, cel["az"], cel["el"], cel["dist"], cel["moon_deg"] if night else cel["sun_deg"], false, 0.0)
