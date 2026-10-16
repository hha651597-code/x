class_name StageFxLayer
extends RefCounted

const DRAW_SHADER := "res://shaders/stage_fx_smoke.gdshader"
const PARTICLE_SHADER := "res://shaders/stage_fx_smoke_particles.gdshader"
const GLOW_SHADER := "res://shaders/stage_glow.gdshader"


static func load_fx(w: StageLoader.World, base: String) -> void:
	var doc: Dictionary = StageLoader.read_json(w.dir.path_join(base))
	if doc.is_empty():
		return
	var root := Node3D.new()
	root.name = "Fx"
	w.add_child(root)
	var luts := {}
	for e: Dictionary in doc["emitters"]:
		var sys: Dictionary = doc["systems"][e["system"]]
		add_emitter(w, root, doc, sys, e, luts)
		for g: Dictionary in e.get("glows", []):
			add_glow(w, root, doc, e, g)


static func add_emitter(w: StageLoader.World, parent: Node3D, doc: Dictionary, sys: Dictionary, e: Dictionary, luts: Dictionary) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = String(e["name"]).validate_node_name()
	var slots := int(ceil(sys["life"][1] * sys["rate"]))
	p.amount = slots
	p.lifetime = slots / sys["rate"]
	p.explosiveness = 1.0
	p.local_coords = true
	p.fixed_fps = 0
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-2.5, -1.0, -2.5), Vector3(5.0, 6.0, 5.0))
	p.position = StageLoader.color3(e["pos"])
	var pm := ShaderMaterial.new()
	pm.shader = load(PARTICLE_SHADER)
	pm.set_shader_parameter("seed", int(hash(str(e["pos"]))) & 0x7fffffff)
	pm.set_shader_parameter("time_offset", float(e["time_offset"]))
	pm.set_shader_parameter("rate", float(sys["rate"]))
	pm.set_shader_parameter("slots", float(slots))
	pm.set_shader_parameter("life_rng", Vector2(sys["life"][0], sys["life"][1]))
	pm.set_shader_parameter("size_rng", Vector2(sys["size"][0], sys["size"][1]))
	pm.set_shader_parameter("start_speed", float(sys["start_speed"]))
	pm.set_shader_parameter("accel", StageLoader.color3(sys["gravity"]) * float(sys["gravity_mod"]))
	pm.set_shader_parameter("force_z_rng", Vector2(sys["force_z"][0], sys["force_z"][1]))
	pm.set_shader_parameter("roll_rng", Vector2(sys["start_roll"][0], sys["start_roll"][1]))
	pm.set_shader_parameter("roll_vel_rng", Vector2(sys["roll_speed"][0], sys["roll_speed"][1]))
	pm.set_shader_parameter("dir", StageLoader.color3(sys["dir"]).normalized())
	pm.set_shader_parameter("hscale", float(sys["scale"]))
	p.process_material = pm
	var mat := ShaderMaterial.new()
	mat.shader = load(DRAW_SHADER)
	var m: Dictionary = sys["material"]
	mat.set_shader_parameter("flow_tex", load(doc["tex_dir"] + m["textures"]["flow"] + ".png"))
	mat.set_shader_parameter("main_tex", load(doc["tex_dir"] + m["textures"]["main"] + ".png"))
	mat.set_shader_parameter("lut", _lut(sys, luts))
	mat.set_shader_parameter("lut_w", int(sys["lut_w"]))
	mat.set_shader_parameter("flow_st", StageMaterials.v4(m["flow_st"]))
	mat.set_shader_parameter("r_color", StageMaterials.v4(m["r_color"]))
	for k: String in m["floats"]:
		mat.set_shader_parameter(k, float(m["floats"][k]))
	mat.set_shader_parameter("pivot", StageLoader.color3(sys["pivot"]))
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	p.draw_pass_1 = quad
	p.material_override = mat
	parent.add_child(p)
	p.emitting = true
	w.timed.append(pm)
	w.timed.append(mat)
	return p


static func add_glow(w: StageLoader.World, parent: Node3D, doc: Dictionary, e: Dictionary, g: Dictionary) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var m := ShaderMaterial.new()
	m.shader = load(GLOW_SHADER)
	m.set_shader_parameter("glow_tex", load(doc["glow_tex"]))
	m.set_shader_parameter("tint", StageLoader.color3(g["tint"]))
	m.set_shader_parameter("intensity", float(g["intensity"]))
	m.set_shader_parameter("flicker", float(g["flicker"]))
	m.set_shader_parameter("seed", float(g["seed"]))
	w.timed.append(m)
	var mi := MeshInstance3D.new()
	mi.name = String(e["name"]).validate_node_name() + "_glow"
	mi.mesh = q
	mi.material_override = m
	mi.position = StageLoader.color3(e["pos"]) + StageLoader.color3(g["offset"])
	mi.scale = Vector3.ONE * float(g["size"])
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _lut(sys: Dictionary, cache: Dictionary) -> ImageTexture:
	var key := str(sys["lut"].hash())
	if cache.has(key):
		return cache[key]
	var w := int(sys["lut_w"])
	var img := Image.create_from_data(w, 3, false, Image.FORMAT_RGBAF, PackedFloat32Array(sys["lut"]).to_byte_array())
	var t := ImageTexture.create_from_image(img)
	cache[key] = t
	return t
