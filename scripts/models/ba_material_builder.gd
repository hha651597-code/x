extends RefCounted
## Builds the Blue Archive style materials of an SD model (what SdFighterActor._build_materials did with sd_toon), from the numbers
## in assets/ba/sd/ba_char_params.json, and drives their colour hooks. Material kind comes from the GLB material name:
## halo, eyebrow, eyemouth or mouth, face, hair, anything else (body, weapon, shield) is the body shader.
## Textures are looked up next to the model as <Pre>_Original_{Body,Hair,Face}_Mask.png and <Pre>_Original_Hair_Spec.png; a missing
## one turns that surface's mask off (use_mask false) and the shader still runs.

const BODY := preload("res://shaders/ba_body.gdshader")
const HAIR := preload("res://shaders/ba_hair.gdshader")
const FACE := preload("res://shaders/ba_face.gdshader")
const UNLIT := preload("res://shaders/ba_unlit.gdshader")
const OUTLINE := preload("res://shaders/ba_outline.gdshader")
const HALO := preload("res://shaders/sd_halo.gdshader")
const PARAMS_PATH := "res://assets/ba/sd/ba_char_params.json"
## Outline width in SubViewport pixels at the reference 720p window: BA's 0.002 NDC is 1.28 reference px, and the actor draws its
## viewport at 0.80 scale, so 1.28 / 0.80.
const OUTLINE_PX := 1.6
## Eyebrows sit this far in front of the face (BA's _ZCorrection times our model scale) and mouths a little less.
const EYEBROW_PUSH := 1.5
const MOUTH_PUSH := 0.01
## Faces are seen 65 degrees off BA's near-frontal camera, which lowers N.V and put every face in shadow; this lifts the shade term.
const FACE_VIEW_BIAS := 0.45
const FALLBACK_OUTLINE := Color(0.13, 0.13, 0.13)
## set_look: the colour added per unit of the sim's flash (0.55 on a hit) and its cap, past which the cel shading washes out.
const FLASH_GAIN := 0.55
const FLASH_CAP := 0.3
const FLASH_RIM := 0.8
const GLOW_RIM := 0.5
const KO_TINT := Color(0.72, 0.76, 0.9)

static var _params := {}

static func _v4(a: Array) -> Vector4:
	return Vector4(a[0], a[1], a[2], a[3])

static func _c(a: Array) -> Color:
	return Color(a[0], a[1], a[2])

## BA's numbers per model (hina, hoshino), read from its material files.
static func params() -> Dictionary:
	if _params.is_empty():
		_params = JSON.parse_string(FileAccess.get_file_as_string(PARAMS_PATH))
	return _params

static func _tex(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null

static func _mask(m: ShaderMaterial, tex: Texture2D) -> void:
	m.set_shader_parameter("use_mask", tex != null)
	if tex:
		m.set_shader_parameter("mask_tex", tex)

## Replaces every surface's material of `meshes` with the BA shaders and returns each ShaderMaterial made, outline passes included.
## `model_dir` is the model's folder, res://assets/ba/sd/<key>: its name picks the parameters and the textures. `halo_overlay`
## draws the halo on top of the geometry. A model without parameters keeps its own materials.
static func build(meshes: Array[MeshInstance3D], model_dir: String, halo_overlay: bool, outline_px := OUTLINE_PX) -> Array[ShaderMaterial]:
	var key := model_dir.get_file()
	if not params().has(key):
		push_error("No Blue Archive shading parameters for '%s' in %s; keeping the model's own materials" % [key, PARAMS_PATH])
		return []
	var p: Dictionary = params()[key]
	var tex_dir := model_dir + "/"
	var pre := key.capitalize() + "_Original_"
	var made: Array[ShaderMaterial] = []
	var white := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	var fallback := ImageTexture.create_from_image(white)
	for mesh in meshes:
		for i in mesh.mesh.get_surface_count():
			var orig := mesh.get_active_material(i) as BaseMaterial3D
			if orig == null:
				continue
			var label := orig.resource_name.to_lower()
			var tex: Texture2D = orig.albedo_texture if orig.albedo_texture else fallback
			var m := ShaderMaterial.new()
			m.resource_name = orig.resource_name + "_BA"
			var line := FALLBACK_OUTLINE
			var hull := true
			if "halo" in label:
				m.shader = HALO if halo_overlay else UNLIT
				m.set_shader_parameter("tint", _c(p["halo"]["tint"]))
				hull = false
			elif "eyebrow" in label:
				m.shader = UNLIT
				m.set_shader_parameter("tint", orig.albedo_color)
				m.set_shader_parameter("z_push", float(p["eyebrow"]["z_correction"]) * EYEBROW_PUSH)
				hull = false
			elif "mouth" in label:
				m.shader = UNLIT
				m.set_shader_parameter("z_push", MOUTH_PUSH)
				hull = false
			elif "face" in label:
				var f: Dictionary = p["face"]
				m.shader = FACE
				m.set_shader_parameter("shadow_tint", _c(f["shadow_tint"]))
				m.set_shader_parameter("face_light_dir", StageLoader.color3(f["face_light_dir"]))
				for k in ["shadow_threshold", "rim_area", "rim_level", "rim_strength", "mask_g_sensitivity", "mask_r_apply"]:
					m.set_shader_parameter(k, f[k])
				m.set_shader_parameter("view_bias", FACE_VIEW_BIAS)
				_mask(m, _tex(tex_dir + pre + "Face_Mask.png"))
				line = _c(f["outline_tint"])
			elif "hair" in label:
				var h: Dictionary = p["hair"]
				m.shader = HAIR
				m.set_shader_parameter("shadow_tint", _c(h["shadow_tint"]))
				m.set_shader_parameter("spec_dir_mul", StageLoader.color3(h["spec_dir_mul"]))
				m.set_shader_parameter("glow_tint", StageLoader.color3(h["glow_tint"]))
				for k in ["shadow_threshold", "spec_top_mul", "spec_top_level", "spec_bot_area", "spec_bot_mul", "spec_strength", "rim_area", "rim_level",
						"rim_strength", "glow_strength", "mask_g_sensitivity", "mask_r_apply"]:
					m.set_shader_parameter(k, h[k])
				_mask(m, _tex(tex_dir + pre + "Hair_Mask.png"))
				var spec := _tex(tex_dir + pre + "Hair_Spec.png")
				m.set_shader_parameter("use_spec", spec != null)
				if spec:
					m.set_shader_parameter("spec_tex", spec)
				line = _c(h["outline_tint"])
			else:
				var b: Dictionary = p["body"]
				var weapon := "weapon" in label or "shield" in label
				m.shader = BODY
				m.set_shader_parameter("shadow_threshold", Vector4(0.5, 0.5, 0.5, 0.5) if weapon else _v4(b["shadow_threshold"]))
				for li in 4:
					m.set_shader_parameter("shadow_tint_%d" % li, StageLoader.color3(p["weapon"]["shadow_col"]) if weapon else StageLoader.color3(b["shadow_tints"][li]))
				for k in ["view_offset", "view_power", "view_strength", "view_edge", "inv_view_power", "inv_view_strength", "base_brightness", "rim_area", "rim_strength"]:
					m.set_shader_parameter(k, _v4(b[k]))
				m.set_shader_parameter("glow_tint", StageLoader.color3(b["glow_tint"]))
				m.set_shader_parameter("glow_strength", b["glow_strength"])
				m.set_shader_parameter("mask_g_sensitivity", b["mask_g_sensitivity"])
				m.set_shader_parameter("fallback_layer", 1)
				_mask(m, null if weapon else _tex(tex_dir + pre + "Body_Mask.png"))
				line = _c(p["weapon"]["outline_tint"] if weapon else b["outline_tint"])
			m.set_shader_parameter("albedo_tex", tex)
			if m.shader == UNLIT:
				m.set_shader_parameter("alpha_mask", true)
				m.set_shader_parameter("alpha_cutoff", orig.alpha_scissor_threshold)
				if "halo" not in label and "eyebrow" not in label:
					m.set_shader_parameter("tint", orig.albedo_color)
			elif m.shader != HALO:
				m.set_shader_parameter("tint", orig.albedo_color)
			if hull and outline_px > 0.0:
				var o := ShaderMaterial.new()
				o.shader = OUTLINE
				o.set_shader_parameter("albedo_tex", tex)
				o.set_shader_parameter("tint", orig.albedo_color)
				o.set_shader_parameter("outline_tint", line)
				o.set_shader_parameter("width_px", outline_px)
				m.next_pass = o
				made.append(o)
			made.append(m)
			mesh.set_surface_override_material(i, m)
	return made

## BA's _CodeAddColor / _CodeMultiplyColor / _CodeAddRimColor and grayscale on every material that has them: hit flash, dim, super glow
## and KO. The cel shading and the outline stay under them.
static func set_code(mats: Array[ShaderMaterial], add: Vector3, mul: Vector3, rim: Vector3, gray: float) -> void:
	for m in mats:
		if m.shader == OUTLINE:
			m.set_shader_parameter("code_mul", mul)
		elif m.shader != HALO:
			m.set_shader_parameter("code_add", add)
			m.set_shader_parameter("code_mul", mul)
			m.set_shader_parameter("code_gray", gray)
			if m.shader != UNLIT:
				m.set_shader_parameter("code_rim", rim)

## The hit flash, dim, KO and super glow as the colour hooks. flash: the sim's flash amount in its colour (an add, capped, plus a
## rim); dim: multiplies everything; ko: grayscale and cool tint amount; glow: a rim colour.
static func set_look(mats: Array[ShaderMaterial], flash: float, flash_col: Color, dim: float, ko: float, glow: float, glow_col: Color) -> void:
	var fc := Vector3(flash_col.r, flash_col.g, flash_col.b)
	var gc := Vector3(glow_col.r, glow_col.g, glow_col.b)
	var f := clampf(flash, 0.0, 1.0)
	var tint := Color.WHITE.lerp(KO_TINT, ko)
	set_code(mats, fc * minf(f * FLASH_GAIN, FLASH_CAP), Vector3(tint.r, tint.g, tint.b) * dim, fc * f * FLASH_RIM + gc * glow * GLOW_RIM, ko)

static func set_outline_width(mats: Array[ShaderMaterial], px: float) -> void:
	for m in mats:
		if m.shader == OUTLINE:
			m.set_shader_parameter("width_px", px)
