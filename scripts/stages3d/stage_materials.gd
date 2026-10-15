class_name StageMaterials
extends RefCounted

const INC := "res://shaders/stage_env.gdshaderinc"
const MODES := {"_ENV_CUTOUT_MODE": 1, "_ENV_ALPHA_MODE": 2, "_ENV_REFLECT_MODE": 3, "_ENV_EMISSION_MODE": 4, "_ENV_SPECULAR_MODE": 5}
const FLOATS := ["_Cutoff", "_LightmapStrength", "_ReflectBaseAmount", "_ReflectAnglePower", "_ShadowAttenRefl", "_ReflectStrength", "_EmissionStrength", "_SpecPower", "_ShadowAttenSpec"]
const CULLS := {0: "cull_disabled", 1: "cull_front", 2: "cull_back"}
static var _shaders := {}


static func v4(a: Array) -> Vector4:
	return Vector4(a[0], a[1], a[2], a[3])


static func shader_kind(name: String) -> int:
	if name == "MX/VertexColor":
		return 2
	if name == "FX/General Unlit Texture":
		return 1
	return 0


static func env_mode(keywords: Array) -> int:
	for k: String in MODES:
		if k in keywords:
			return MODES[k]
	return 0


static func header(sc: Dictionary, foliage := false) -> String:
	var kind := shader_kind(String(sc["shader"]))
	var mode := env_mode(sc["keywords"])
	var b: Dictionary = sc["blend"]
	var src := int(b["src"]) if b["src"] != null else 1
	var dst := int(b["dst"]) if b["dst"] != null else 0
	var transparent := kind == 2 or mode == 2
	var blend := ""
	var mul2x := false
	if src == 5 and dst == 10:
		transparent = true
	elif src == 5 and dst == 1:
		transparent = true
		blend = "blend_add"
	elif src == 1 and dst == 1:
		blend = "blend_add"
	elif src == 2 and dst == 3:
		blend = "blend_mul"
		mul2x = true
	var cull := int(b["cull"]) if b["cull"] != null else 2
	var s := "shader_type spatial;\n"
	if foliage:
		s += "#define BA_FOLIAGE\n"
	if blend != "":
		s += "#define BA_BLEND %s\n" % blend
	if transparent:
		s += "#define BA_TRANSPARENT\n"
	if mul2x:
		s += "#define BA_MUL2X\n"
	s += "#define BA_CULL %s\n" % CULLS.get(cull, "cull_back")
	return s + '#include "%s"\n' % INC


static func shader_for(code: String) -> Shader:
	if not _shaders.has(code):
		var sh := Shader.new()
		sh.code = code
		_shaders[code] = sh
	return _shaders[code]


static func build(sc: Dictionary, albedo: Texture2D, dir: String, ctx: Dictionary, foliage := false) -> ShaderMaterial:
	var kind := shader_kind(String(sc["shader"]))
	var m := ShaderMaterial.new()
	m.shader = shader_for(header(sc, foliage))
	m.set_shader_parameter("ba_shader", kind)
	m.set_shader_parameter("env_mode", env_mode(sc["keywords"]))
	var cols: Dictionary = sc["colors"]
	var tint: String = "_TintColor" if kind == 2 else "_Color"
	if cols.has(tint):
		m.set_shader_parameter("_Color", v4(cols[tint]))
	var texs: Dictionary = sc["textures"]
	if texs.has("_MainTex"):
		var mt: Dictionary = texs["_MainTex"]
		m.set_shader_parameter("_MainTex_ST", Vector4(mt["scale"][0], mt["scale"][1], mt["offset"][0], mt["offset"][1]))
		if albedo != null:
			m.set_shader_parameter("_MainTex", albedo)
		elif mt["file"] != null:
			m.set_shader_parameter("_MainTex", load(dir.path_join(mt["file"])))
	for tn: String in ["_ReflectTex", "_EmissionTex", "_SpecTex"]:
		if texs.has(tn) and texs[tn]["file"] != null:
			m.set_shader_parameter(tn, load(dir.path_join(texs[tn]["file"])))
			if tn == "_ReflectTex":
				var rt: Dictionary = texs[tn]
				m.set_shader_parameter("_ReflectTex_ST", Vector4(rt["scale"][0], rt["scale"][1], rt["offset"][0], rt["offset"][1]))
	for f: String in FLOATS:
		if sc["floats"].has(f):
			m.set_shader_parameter(f, float(sc["floats"][f]))
	if cols.has("_SpecLightColor"):
		m.set_shader_parameter("_SpecLightColor", v4(cols["_SpecLightColor"]))
	if cols.has("_SpecLightDir"):
		var d: Array = cols["_SpecLightDir"]
		m.set_shader_parameter("_SpecLightDir", Vector4(-d[0], d[1], d[2], d[3]))
	var zf: Variant = sc["blend"]["zoffset_factor"]
	m.set_shader_parameter("z_offset", float(zf) if zf != null else 0.0)
	# not fully functional. a surface with no lightmap takes the shader's flat probe (sh9 = 1,1,1); the converter does not publish the scene's SH9 yet.
	var lm: Texture2D = ctx.get("lightmap")
	m.set_shader_parameter("use_lightmap", lm != null)
	if lm != null:
		m.set_shader_parameter("lightmap", lm)
	m.set_shader_parameter("subtractive_shadow_color", ctx["subtractive"])
	m.set_shader_parameter("main_light_shadow_strength", ctx["shadow_strength"])
	m.set_shader_parameter("clip_plane", ctx["clip"])
	m.set_shader_parameter("shadow_blobs", ctx["blobs"])
	return m
