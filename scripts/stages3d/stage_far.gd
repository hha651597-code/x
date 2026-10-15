class_name StageFar
extends RefCounted

const FAR_INC := "res://shaders/stage_far.gdshaderinc"
const KINDS := {"opaque": "FF_OPAQUE", "cutout": "FF_CUTOUT", "flat": "FF_FLAT", "smoke": "FF_SMOKE", "glow": "FF_GLOW", "card": "FF_CARD"}
static var _shaders := {}


static func shader_for(kind: String, emis: bool) -> Shader:
	var key := "%s%s" % [kind, emis]
	if not _shaders.has(key):
		var s := Shader.new()
		s.code = "shader_type spatial;\n#define %s\n%s#include \"%s\"\n" % [KINDS[kind], "#define FF_EMIS\n" if emis else "", FAR_INC]
		_shaders[key] = s
	return _shaders[key]


static func param(v: Variant) -> Variant:
	if v is Array:
		return Vector2(v[0], v[1]) if v.size() == 2 else StageLoader.color3(v)
	return v


static func load_group(w: StageLoader.World, base: String, ctx: Dictionary) -> void:
	var side: Dictionary = StageLoader.read_json(w.dir.path_join(base + ".json"))
	var root: Node3D = (load(w.dir.path_join(base + ".glb")) as PackedScene).instantiate()
	w.add_child(root)
	var g: Dictionary = w.info["sky"]["gradient"]
	var haze: Dictionary = side["haze"]
	var mats := {}
	for key: String in side["materials"]:
		var m: Dictionary = side["materials"][key]
		var sm := ShaderMaterial.new()
		sm.shader = shader_for(m["kind"], m.has("emis"))
		if m["tex"]:
			sm.set_shader_parameter("albedo_tex", load(w.dir.path_join(m["tex"])))
		sm.set_shader_parameter("color_mul", StageLoader.color3(m["color_mul"]))
		sm.set_shader_parameter("cutoff", m["cutoff"])
		sm.set_shader_parameter("color_scale", float(side["color_scale"]))
		sm.set_shader_parameter("sky_color", StageLoader.color3(g["sky_color"]))
		sm.set_shader_parameter("equator_color", StageLoader.color3(g["equator_color"]))
		sm.set_shader_parameter("sky_gradient", g["sky_gradient"])
		sm.set_shader_parameter("equator_offset", g["equator_offset"])
		sm.set_shader_parameter("clip_plane", ctx["clip"])
		for k: String in ["density", "power", "amount", "low", "low_scale"]:
			if haze.has(k):
				sm.set_shader_parameter("haze_" + k, haze[k])
		sm.set_shader_parameter("haze_color", StageLoader.color3(haze["color"]))
		if m.has("emis"):
			sm.set_shader_parameter("emis_tex", load(w.dir.path_join(m["emis"])))
			var r: Array = m["emis_rect"]
			sm.set_shader_parameter("emis_rect", Vector4(r[0], r[1], r[2], r[3]))
		var params: Dictionary = m.get("params", {})
		for k: String in params:
			sm.set_shader_parameter(k, param(params[k]))
		if m["kind"] == "smoke" or m["kind"] == "glow":
			w.timed.append(sm)
		mats[key] = sm
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var ci: Dictionary = side["chunks"][mi.name]
		mi.set_surface_override_material(0, mats[ci["material"]])
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if ci.has("cull_margin"):
			mi.extra_cull_margin = float(ci["cull_margin"])
		elif side["materials"][ci["material"]]["kind"] == "glow":
			for corner: Vector2 in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]:
				mi.extra_cull_margin = maxf(mi.extra_cull_margin, corner.length())
