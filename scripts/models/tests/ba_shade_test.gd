extends SceneTree
## Blue Archive shading of the SD fighters: the shaders compile and draw with the masks present and absent, every surface of both
## models gets its numbers and an outline, the stage light descriptor drives the rendered colours, the flash is capped, the outline
## and viewport follow the window height, the composite has no dark fringe, and the shipped textures match PROVENANCE.json.
## Run with TEST=res://scripts/models/tests/ba_shade_test.gd tools/sd_test.sh (a real small window).
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

## The Gehenna slum values, published as Game.session.stage["light"].
const DAY := {"night": false, "key_color": Color(1, 1, 1), "key_dir": Vector3(-0.4438, 0.8951, 0.0423), "ambient": Color(0.723, 0.723, 0.723),
	"fighter_dir": Vector3(0.5964, 0.4964, 0.6308)}
const NIGHT := {"night": true, "key_color": Color(0.683, 0.75, 1.0), "key_dir": Vector3(-0.4452, 0.8926, 0.0708), "ambient": Color(0.391, 0.391, 0.76),
	"fighter_dir": Vector3(-0.386, 0.776, 0.5)}
const KEYS := ["hina", "hoshino"]
## Wrong types, NaN, INF, a negative colour, a zero direction, a null: each must read as the fixed value, not raise.
const BAD_LIGHTS := [
	{"key_color": [1.0, 0.5, 0.2]}, {"key_color": "red"}, {"key_color": null}, {"key_color": Color(INF, 1, 1)}, {"key_color": Color(1, NAN, 1)},
	{"key_color": Color(-1, -1, -1)}, {"ambient": [0.7, 0.7, 0.7]}, {"ambient": "grey"}, {"ambient": Color(INF, INF, INF)}, {"ambient": Color(-2, 0, 0)},
	{"fighter_dir": [0, 1, 0]}, {"fighter_dir": "up"}, {"fighter_dir": Vector3(NAN, 0, 1)}, {"fighter_dir": Vector3(INF, 0, 0)}, {"fighter_dir": Vector3.ZERO},
	{"night": "yes"}, {"night": 1}, {"night": null},
]

var checks := 0
var failures: Array[String] = []
var game: Node
var actor_script: GDScript
var rig: GDScript
var builder: GDScript

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		if failures.size() < 60:
			print("BA_SHADE_CHECK FAIL ", label)
		failures.append(label)

func near(a: float, b: float, eps := 0.002) -> bool:
	return absf(a - b) <= eps

func _run() -> void:
	create_timer(240.0).timeout.connect(func() -> void:
		print("BA_SHADE_TEST FAIL watchdog timeout")
		quit(3))
	await process_frame
	game = root.get_node("Game")
	actor_script = load("res://scripts/models/sd_fighter_actor.gd")
	rig = load("res://scripts/models/ba_light_rig.gd")
	builder = load("res://scripts/models/ba_material_builder.gd")
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	_assets()
	_light_globals()
	await _stage_hookup()
	var actors := {}
	for key: String in KEYS:
		actors[key] = await _make_actor(key)
		_surfaces(actors[key], key)
		_no_masks(key)
	await _render_checks(actors["hoshino"])
	await _render_checks(actors["hina"])
	await _light_colours(actors["hoshino"])
	await _flash_and_ko(actors["hoshino"])
	await _sync_checks()
	_window_scale(actors["hina"])
	for key: String in KEYS:
		_halo_glow(actors[key], key)
	await _halo_without_materials()
	await _fringe()
	_finish()

func _make_actor(key: String) -> Node:
	var actor: Node = actor_script.new()
	root.add_child(actor)
	actor.setup({"key": key})
	actor.blending = false
	actor.pose("idle", 30, "", {}, 0, 0, 1)
	return actor

## Mean and spread of the luminance over the opaque pixels of the actor's viewport, and their mean colour.
func _render(actor: Node) -> Dictionary:
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = actor.viewport.get_texture().get_image()
	var n := 0
	var sum := Color(0, 0, 0, 0)
	var lum: Array = []
	for y in range(0, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			var c := img.get_pixel(x, y)
			if c.a > 0.95:
				n += 1
				sum += c
				lum.append(0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b)
	var mean := 0.0
	for l in lum:
		mean += l
	mean /= maxf(float(n), 1.0)
	var var_sum := 0.0
	for l in lum:
		var_sum += (l - mean) * (l - mean)
	return {"n": n, "mean": mean, "std": sqrt(var_sum / maxf(float(n), 1.0)), "rgb": Vector3(sum.r, sum.g, sum.b) / maxf(float(n), 1.0)}

# ── assets ───────────────────────────────────────────────────────────────────

func _assets() -> void:
	var prov: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ba/sd/PROVENANCE.json"))
	var listed := {}
	for group in ["models", "textures", "parameters"]:
		for e in prov.get(group, []):
			var path := "res://" + String(e["runtime_path"])
			listed[path] = true
			check(FileAccess.file_exists(path), "PROVENANCE file exists: " + path)
			if FileAccess.file_exists(path):
				var bytes := FileAccess.get_file_as_bytes(path)
				check(bytes.size() == int(e["bytes"]), "PROVENANCE bytes match: " + path)
				check(FileAccess.get_sha256(path) == String(e["sha256"]), "PROVENANCE sha256 matches: " + path)
				check(e.has("kind") or group == "models", "PROVENANCE entry has a kind: " + path)
				check(String(e["source"]) != "", "PROVENANCE entry has a source: " + path)
	for key: String in KEYS:
		var dir: String = "res://assets/ba/sd/%s/" % key
		var pre: String = key.capitalize() + "_Original_"
		for name in ["Body_Mask", "Hair_Mask", "Face_Mask", "Hair_Spec"]:
			var path: String = dir + pre + name + ".png"
			check(listed.has(path), "shipped texture is listed in PROVENANCE: " + path)
			var imp := FileAccess.get_file_as_string(path + ".import")
			check("compress/mode=0\n" in imp, "lossless import: " + name)
			check("mipmaps/generate=false" in imp, "no mipmaps: " + name)
			check("detect_3d/compress_to=0" in imp, "no 3D recompression: " + name)
			check("fix_alpha_border=false" in imp, "alpha border left alone, the painted RGB under alpha 0 is data: " + name)
	for key: String in KEYS:
		for f in DirAccess.get_files_at("res://assets/ba/sd/" + key):
			if f.ends_with(".png"):
				check(listed.has("res://assets/ba/sd/%s/%s" % [key, f]), "no unlisted texture: " + f)
	check(not FileAccess.file_exists("res://shaders/sd_toon.gdshader"), "sd_toon is gone, nothing draws with it")
	var uniforms: Array = (load("res://shaders/sd_composite.gdshader") as Shader).get_shader_uniform_list()
	var names := uniforms.map(func(u: Dictionary) -> String: return u["name"])
	check(not names.has("outline_px") and not names.has("outline_color"), "the composite has no alpha-dilation outline")

# ── stage light ──────────────────────────────────────────────────────────────

func _light_globals() -> void:
	var names := ["ba_light_dir", "ba_light_tone", "ba_shadow_tone", "ba_light_data", "ba_ambient"]
	var fallback: Dictionary = rig.values({})
	for n in names:
		var setting: Dictionary = ProjectSettings.get_setting("shader_globals/" + n, {})
		check(not setting.is_empty(), "global shader parameter registered in project.godot: " + n)
		var dflt: Variant = setting.get("value")
		check(typeof(dflt) == typeof(fallback[n]) and (dflt - fallback[n]).length() < 1e-4, "the project default of %s is the fixed value (%s)" % [n, str(dflt)])
	var dir: Vector3 = rig.DEFAULT["fighter_dir"]
	check((fallback["ba_light_dir"] as Vector3).is_equal_approx(dir.normalized()), "no descriptor: the fixed light direction")
	check(near((fallback["ba_light_data"] as Vector4).y, 1.0) and near((fallback["ba_light_data"] as Vector4).x, 1.0), "no descriptor: full intensity, no shadow bias")
	check(rig.values({"key_dir": Vector3(0, 1, 0), "yaw_deg": 12.0}) == fallback, "an unused key (key_dir, yaw_deg) changes nothing; missing keys fall back")
	var day: Dictionary = rig.values(DAY)
	check((day["ba_light_dir"] as Vector3).is_equal_approx((DAY["fighter_dir"] as Vector3).normalized()), "day: the light direction is fighter_dir")
	check(not (day["ba_light_dir"] as Vector3).is_equal_approx((DAY["key_dir"] as Vector3).normalized()), "day: the edge-on key_dir is not the shading direction")
	var night: Dictionary = rig.values(NIGHT)
	var tone_d: Vector3 = day["ba_light_tone"]
	var tone_n: Vector3 = night["ba_light_tone"]
	check(tone_n.z / tone_n.x > tone_d.z / tone_d.x + 0.05, "night: the lit tone is bluer than day's")
	check(tone_n.length() < tone_d.length(), "night: the lit tone is dimmer than day's")
	check((night["ba_light_data"] as Vector4).x < (day["ba_light_data"] as Vector4).x, "night: the intensity drops")
	check((night["ba_ambient"] as Vector3).z > (night["ba_ambient"] as Vector3).x, "night: the ambient is blue")
	check((rig.values({"fighter_dir": Vector3.ZERO})["ba_light_dir"] as Vector3).is_equal_approx(dir.normalized()), "a zero fighter_dir falls back to the fixed direction")
	for bad in BAD_LIGHTS:
		check(rig.values(bad) == fallback, "a malformed light falls back to the fixed values: " + str(bad))
	var half_bad: Dictionary = rig.values({"key_color": "red", "ambient": Color(0.2, 0.3, 0.5)})
	check((half_bad["ba_ambient"] as Vector3).is_equal_approx(Vector3(0.2, 0.3, 0.5) * rig.AMBIENT_SCALE) and half_bad["ba_light_tone"] == fallback["ba_light_tone"], "a bad key falls back on its own; the good ones are kept")
	for real in [day, night]:
		var t: Vector3 = real["ba_light_tone"]
		var sh: Vector3 = real["ba_shadow_tone"]
		check(minf(t.x, minf(t.y, t.z)) > 0.5 and maxf(t.x, maxf(t.y, t.z)) <= 1.0 and minf(sh.x, minf(sh.y, sh.z)) > 0.5, "the published day and night give sane tones (%s, %s)" % [str(t), str(sh)])
	var hot: Vector3 = rig.values({"key_color": Color(2.5, 2.0, 1.5)})["ba_light_tone"]
	check(hot.x > 1.0 and not is_nan(hot.x), "a key colour above 1 is used as stored")

## The actor reads the session's stage on setup; a stage without a descriptor puts the fixed values back. Read through the colours.
func _stage_hookup() -> void:
	game.session.stage = {"id": "ba_shade_test", "light": NIGHT}
	var probe: Node = actor_script.new()
	root.add_child(probe)
	probe.setup({"key": "hoshino"})
	probe.pose("idle", 30, "", {}, 0, 0, 1)
	var night: Dictionary = await _render(probe)
	game.session.stage = {"id": "ba_shade_test"}
	var probe2: Node = actor_script.new()
	root.add_child(probe2)
	probe2.setup({"key": "hoshino"})
	probe2.pose("idle", 30, "", {}, 0, 0, 1)
	var plain: Dictionary = await _render(probe2)
	rig.apply({})
	var plain_ref: Dictionary = await _render(probe2)
	var nv: Vector3 = night["rgb"]
	var pv: Vector3 = plain["rgb"]
	check(nv.z / nv.x > pv.z / pv.x + 0.02, "setup() applies Game.session.stage['light']: night is bluer (%.3f > %.3f)" % [nv.z / nv.x, pv.z / pv.x])
	check(((plain["rgb"] as Vector3) - (plain_ref["rgb"] as Vector3)).length() < 0.002, "a stage without a light renders the fixed values")
	game.session.stage = {"id": "ba_shade_test", "light": "dusk"}
	var probe3: Node = actor_script.new()
	root.add_child(probe3)
	probe3.setup({"key": "hoshino"})
	probe3.pose("idle", 30, "", {}, 0, 0, 1)
	var odd: Dictionary = await _render(probe3)
	check(((odd["rgb"] as Vector3) - (plain_ref["rgb"] as Vector3)).length() < 0.002, "a light that is not a Dictionary renders the fixed values")
	game.session.stage = {}

# ── materials ────────────────────────────────────────────────────────────────

func _v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])

func _col(a: Array) -> Color:
	return Color(a[0], a[1], a[2])

func _surfaces(actor: Node, key: String) -> void:
	var p: Dictionary = builder.params()[key]
	var seen := {}
	for mesh in actor.meshes:
		for i in mesh.mesh.get_surface_count():
			var m := mesh.get_active_material(i) as ShaderMaterial
			check(m != null, "%s %s s%d: a ShaderMaterial" % [key, mesh.name, i])
			if m == null:
				continue
			var label := m.resource_name.to_lower()
			check(m.get_shader_parameter("albedo_tex") != null, "%s: albedo_tex lands on %s" % [key, m.resource_name])
			var hull := m.next_pass as ShaderMaterial
			if "halo" in label:
				seen["halo"] = true
				var overlay: bool = actor.cfg["halo_overlay"]
				check(m.shader == (builder.HALO if overlay else builder.UNLIT), "%s: the halo draws %s" % [key, "on top (sd_halo)" if overlay else "with ba_unlit"])
				check((m.get_shader_parameter("tint") as Color).is_equal_approx(_col(p["halo"]["tint"])), key + ": the halo takes BA's tint")
				check(hull == null, key + ": the halo has no outline")
			elif "mouth" in label or "eyebrow" in label:
				seen["eyebrow" if "eyebrow" in label else "mouth"] = true
				check(m.shader == builder.UNLIT, "%s: %s is unlit" % [key, m.resource_name])
				check(bool(m.get_shader_parameter("alpha_mask")), "%s: %s keeps its alpha cut" % [key, m.resource_name])
				check(float(m.get_shader_parameter("z_push")) > 0.0, "%s: %s is pushed toward the camera" % [key, m.resource_name])
				check(hull == null, "%s: %s has no outline" % [key, m.resource_name])
			else:
				var kind := "face" if "face" in label else ("hair" if "hair" in label else "body")
				seen[kind] = true
				check(m.shader == {"face": builder.FACE, "hair": builder.HAIR, "body": builder.BODY}[kind], "%s: %s uses ba_%s" % [key, m.resource_name, kind])
				check(hull != null and hull.shader == builder.OUTLINE, "%s: %s has the outline pass" % [key, m.resource_name])
				if hull:
					check(near(float(hull.get_shader_parameter("width_px")), builder.OUTLINE_PX * float(actor.view_scale)), "%s: %s outline width follows the viewport scale" % [key, m.resource_name])
					check(hull.get_shader_parameter("albedo_tex") == m.get_shader_parameter("albedo_tex"), "%s: %s outline shares the albedo" % [key, m.resource_name])
				var weapon := "weapon" in label or "shield" in label
				match kind:
					"body":
						if weapon:
							seen["weapon"] = true
							check(not bool(m.get_shader_parameter("use_mask")), key + ": the weapon has no mask")
						else:
							check(bool(m.get_shader_parameter("use_mask")) and m.get_shader_parameter("mask_tex") != null, key + ": the body has its mask")
							var t: Array = p["body"]["shadow_threshold"]
							check((m.get_shader_parameter("shadow_threshold") as Vector4).is_equal_approx(Vector4(t[0], t[1], t[2], t[3])), key + ": the body's four layer thresholds")
							check((m.get_shader_parameter("shadow_tint_1") as Vector3).is_equal_approx(_v3(p["body"]["shadow_tints"][1])), key + ": the body's layer 1 shadow tint")
							if hull:
								check((hull.get_shader_parameter("outline_tint") as Color).is_equal_approx(_col(p["body"]["outline_tint"])), key + ": the body's outline tint")
					"hair":
						check(bool(m.get_shader_parameter("use_mask")) and bool(m.get_shader_parameter("use_spec")) and m.get_shader_parameter("spec_tex") != null, key + ": the hair has its mask and spec texture")
						check(near(float(m.get_shader_parameter("shadow_threshold")), float(p["hair"]["shadow_threshold"])), key + ": the hair's threshold")
						if hull:
							check((hull.get_shader_parameter("outline_tint") as Color).is_equal_approx(_col(p["hair"]["outline_tint"])), key + ": the hair's outline tint")
					"face":
						check(bool(m.get_shader_parameter("use_mask")) and m.get_shader_parameter("mask_tex") != null, key + ": the face has its mask")
						check((m.get_shader_parameter("face_light_dir") as Vector3).is_equal_approx(_v3(p["face"]["face_light_dir"])), key + ": the face's own light")
						if hull:
							check((hull.get_shader_parameter("outline_tint") as Color).is_equal_approx(_col(p["face"]["outline_tint"])), key + ": the face's outline tint")
	for kind in ["halo", "eyebrow", "mouth", "face", "hair", "body", "weapon"]:
		check(seen.has(kind), "%s has a %s surface to check" % [key, kind])
	check(actor.ba_mats.size() > 0, key + ": the actor keeps its materials for the colour hooks")

## A model whose folder has no mask or spec files still gets a working material: every use_mask false.
func _no_masks(key: String) -> void:
	var cfg: Dictionary = load("res://scripts/models/sd_config.gd").of(key)
	var scene := (load(cfg["model"]) as PackedScene).instantiate()
	root.add_child(scene)
	var meshes: Array[MeshInstance3D] = []
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		meshes.append(n)
	var mats: Array[ShaderMaterial] = builder.build(meshes, "res://zzz_no_masks/" + key, false)
	check(mats.size() > 0, key + ": materials are built without any mask file")
	var masked := 0
	for m in mats:
		if m.shader in [builder.BODY, builder.HAIR, builder.FACE]:
			check(not bool(m.get_shader_parameter("use_mask")), key + ": no file, use_mask false on " + m.resource_name)
			if m.shader == builder.HAIR:
				check(not bool(m.get_shader_parameter("use_spec")), key + ": no file, use_spec false on " + m.resource_name)
			masked += 1
	check(masked > 0, key + ": the maskless build has masked-kind surfaces to check")

# ── rendering ────────────────────────────────────────────────────────────────

func _set_masks(actor: Node, on: bool) -> void:
	for m in actor.ba_mats:
		if m.shader in [builder.BODY, builder.HAIR, builder.FACE] and m.get_shader_parameter("mask_tex") != null:
			m.set_shader_parameter("use_mask", on)
		if m.shader == builder.HAIR:
			m.set_shader_parameter("use_spec", on)

func _render_checks(actor: Node) -> void:
	var key: String = actor.cfg["model"].get_base_dir().get_file()
	rig.apply({})
	var with_masks: Dictionary = await _render(actor)
	_set_masks(actor, false)
	var without: Dictionary = await _render(actor)
	_set_masks(actor, true)
	check(int(with_masks["n"]) > 2000, "%s: the model renders opaque pixels with masks (%d)" % [key, with_masks["n"]])
	check(int(without["n"]) > 2000, "%s: the model still renders without masks (%d)" % [key, without["n"]])
	check(absf(float(with_masks["n"]) - float(without["n"])) < 0.02 * float(with_masks["n"]), "%s: masks do not change the silhouette" % key)
	check(float(with_masks["std"]) > 0.05 and float(without["std"]) > 0.05, "%s: shading and texture give the render real contrast (%.3f / %.3f)" % [key, with_masks["std"], without["std"]])
	check(((with_masks["rgb"] as Vector3) - (without["rgb"] as Vector3)).length() > 0.002, "%s: the masks change the colours" % key)
	# every hull is drawn: with the outline off the figure loses its dark line pixels
	var lined: Dictionary = await _render(actor)
	builder.set_outline_width(actor.ba_mats, 0.0)
	var bare: Dictionary = await _render(actor)
	builder.set_outline_width(actor.ba_mats, builder.OUTLINE_PX * float(actor.view_scale))
	check(int(lined["n"]) > int(bare["n"]) + 100, "%s: the hull outline adds pixels around the figure (%d to %d)" % [key, bare["n"], lined["n"]])

func _light_colours(actor: Node) -> void:
	rig.apply({})
	var base: Dictionary = await _render(actor)
	rig.apply(DAY)
	var day: Dictionary = await _render(actor)
	rig.apply(NIGHT)
	var night: Dictionary = await _render(actor)
	rig.apply({"key_color": Color(1.0, 0.55, 0.2), "ambient": Color(0.7, 0.7, 0.7)})
	var warm: Dictionary = await _render(actor)
	rig.apply({})
	var dv: Vector3 = day["rgb"]
	var nv: Vector3 = night["rgb"]
	var wv: Vector3 = warm["rgb"]
	check(float(night["mean"]) < float(day["mean"]) - 0.01, "night renders darker than day (%.3f < %.3f)" % [night["mean"], day["mean"]])
	check(nv.z / nv.x > dv.z / dv.x + 0.02, "night renders bluer than day (b/r %.3f > %.3f)" % [nv.z / nv.x, dv.z / dv.x])
	check(wv.x / wv.z > dv.x / dv.z + 0.05, "a warm key renders redder than day (r/b %.3f > %.3f)" % [wv.x / wv.z, dv.x / dv.z])
	check(((base["rgb"] as Vector3) - dv).length() > 0.002, "a descriptor changes the render against the fixed values")
	check(float(day["std"]) > 0.05 and float(night["std"]) > 0.05, "day and night keep their contrast")

func _flash_and_ko(actor: Node) -> void:
	rig.apply({})
	actor.set_look()
	var base: Dictionary = await _render(actor)
	actor.set_look(0.55, Color.WHITE)
	var flash: Dictionary = await _render(actor)
	actor.set_look(1.0, Color.WHITE)
	var full: Dictionary = await _render(actor)
	actor.set_look(0.0, Color.WHITE, 1.0, 1.0)
	var ko: Dictionary = await _render(actor)
	actor.set_look(0.0, Color.WHITE, 0.5)
	var dim: Dictionary = await _render(actor)
	actor.set_look()
	check(float(flash["mean"]) > float(base["mean"]) + 0.02, "a hit flash brightens the figure (%.3f > %.3f)" % [flash["mean"], base["mean"]])
	check(float(flash["std"]) > 0.6 * float(base["std"]) and float(full["std"]) > 0.6 * float(base["std"]), "a flash keeps the cel shading's contrast, a mix to white at 0.55 would leave 0.45 (%.2f, %.2f of %.3f)" % [float(flash["std"]) / float(base["std"]), float(full["std"]) / float(base["std"]), base["std"]])
	check(float(full["mean"]) < 0.97, "a full flash does not white the figure out (%.3f)" % full["mean"])
	var rgb: Vector3 = ko["rgb"]
	check(absf(rgb.x - rgb.y) < 0.12 and absf(rgb.y - rgb.z) < 0.12, "KO is grayscale (%s)" % str(rgb))
	check(float(dim["mean"]) < float(base["mean"]) * 0.8, "dim multiplies the figure (sRGB-encoded read-back) (%.3f vs %.3f)" % [dim["mean"], base["mean"]])
	# the colour hooks themselves: every BA material, the add capped
	var cap: float = builder.FLASH_CAP
	check(cap >= 0.25 and cap <= 0.35, "the flash cap stays near 0.25 to 0.35 so the cel shading survives (%.2f)" % cap)
	actor.set_look(1.0, Color.WHITE)
	var hooked := 0
	for m in actor.ba_mats:
		if m.shader in [builder.BODY, builder.HAIR, builder.FACE, builder.UNLIT]:
			var add: Vector3 = m.get_shader_parameter("code_add")
			check(add.x <= cap + 1e-4 and add.y <= cap + 1e-4 and add.z <= cap + 1e-4 and add.x > 0.0, "the flash add is capped at %.2f on %s (%.3f)" % [cap, m.resource_name, add.x])
			hooked += 1
	check(hooked > 20, "the flash reaches every BA material, mouths and eyes included (%d)" % hooked)
	var body_mat: ShaderMaterial
	for m in actor.ba_mats:
		if m.shader == builder.BODY:
			body_mat = m
			break
	actor.set_look(0.0, Color.WHITE, 1.0, 0.0, 1.0, Color.RED)
	var rim: Vector3 = body_mat.get_shader_parameter("code_rim")
	check(near(rim.x, builder.GLOW_RIM) and near(rim.y, 0.0) and near(rim.z, 0.0), "a glow colour reaches the rim, scaled by GLOW_RIM (%s)" % str(rim))
	actor.set_look(0.0, Color.WHITE, 1.0, 1.0)
	var mul: Vector3 = body_mat.get_shader_parameter("code_mul")
	check(near(mul.x, builder.KO_TINT.r) and near(mul.y, builder.KO_TINT.g) and near(mul.z, builder.KO_TINT.b) and mul.z > mul.x + 0.1, "KO multiplies by a cool tint, bluer than red (%s)" % str(mul))
	actor.set_look(0.0, Color.WHITE, 0.6, 0.0, 0.0, Color.WHITE)
	for m in actor.ba_mats:
		if m.shader == builder.OUTLINE:
			check(near((m.get_shader_parameter("code_mul") as Vector3).x, 0.6), "dim reaches the outline pass")
			break
	actor.set_look()

## Without the view driving the look, the actor's own sync() still sets the flash and KO look from the sim's fields.
func _sync_checks() -> void:
	game.session.begin("training")
	game.session.players[0]["fighter"] = 10004
	game.session.players[1]["fighter"] = 10005
	game.session.players[0]["special"] = 10017
	game.session.players[1]["special"] = 10017
	root.get_node("Dbg").intro_entry = false     # the 300 tick entry intro would hide the idle picture these checks need
	await game.go("fight", {}, "cut")
	var screen: Node = game.stack.back()
	var S: Dictionary = screen.f1.get_script().S
	# a live fight poses the model after most _process calls of the frame: the ring must still sit on the halo when it is drawn
	for i in 90:
		await process_frame
	await RenderingServer.frame_post_draw
	for fighter in screen.fighters:
		var live: Node = fighter.view.sd_actor
		for c in live.get_children():
			if c is Sprite2D and c != live.body:
				var h: MeshInstance3D = c.halo
				var want: Vector2 = (live.camera.unproject_position(h.global_transform * h.mesh.get_aabb().get_center()) + live.body.offset) * live.body.scale
				check(c.position.distance_to(want) < 3.0, "%s: in a live fight the halo ring is on the halo when drawn (%.1f px off)" % [fighter.data["key"], c.position.distance_to(want)])
	screen.set_physics_process(false)
	for fighter in screen.fighters:
		fighter.set_process(false)
		var actor: Node = fighter.view.sd_actor
		actor.look_driven = false     # the view sets it; these checks are sync()'s own path
		var body := _first(actor, builder.BODY)
		fighter._flash = 0.0
		fighter.state = S.IDLE
		actor.sync(fighter)
		check((body.get_shader_parameter("code_add") as Vector3) == Vector3.ZERO, "sync: no flash, no add")
		fighter._flash = 0.55
		fighter.state = S.HIT
		actor.sync(fighter)
		var add: Vector3 = body.get_shader_parameter("code_add")
		check(add.x > 0.05 and add.x <= builder.FLASH_CAP + 1e-4, "sync: the sim's flash 0.55 becomes a capped add (%.3f)" % add.x)
		fighter._flash = 0.0
		fighter.state = S.KO
		actor.sync(fighter)
		check(near(float(body.get_shader_parameter("code_gray")), 0.35), "sync: KO sets the grayscale")
		fighter.state = S.IDLE
		fighter.dim = 0.5
		actor.sync(fighter)
		check(near((body.get_shader_parameter("code_mul") as Vector3).x, 0.5), "sync: the fighter's dim multiplies")
		fighter.dim = 1.0
		actor.sync(fighter)
		body.set_shader_parameter("code_add", Vector3.ONE)
		actor.sync(fighter)
		check((body.get_shader_parameter("code_add") as Vector3) == Vector3.ONE, "an unchanged look is not written again")
		actor.look_driven = true
		fighter._flash = 0.9
		actor.sync(fighter)
		check((body.get_shader_parameter("code_add") as Vector3) == Vector3.ONE, "with look_driven sync() leaves the look to the view")
		actor.look_driven = false
		fighter._flash = 0.0

## A halo mesh whose model got no BA materials (no numbers in ba_char_params.json) is skipped, not a SCRIPT ERROR.
func _halo_without_materials() -> void:
	var glow: Node = load("res://scripts/models/ba_halo_glow.gd").new()
	root.add_child(glow)
	var halo := MeshInstance3D.new()
	halo.mesh = QuadMesh.new()
	var cam := Camera3D.new()
	var body := Sprite2D.new()
	glow.setup(halo, cam, body)
	await process_frame
	check(not is_instance_valid(glow) or glow.is_queued_for_deletion(), "a halo without a BA material drops its ring and raises no error")
	for n: Node in [halo, cam, body]:
		n.free()

## The additive halo ring follows the halo mesh, takes its hue, and hides with it.
func _halo_glow(actor: Node, key: String) -> void:
	var glow: Sprite2D
	for c in actor.get_children():
		if c is Sprite2D and c != actor.body:
			glow = c
	check(glow != null, key + ": a halo glow sprite is built")
	if glow == null:
		return
	check((glow.material as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_ADD, key + ": the halo glow is additive")
	var halo: MeshInstance3D = glow.halo
	for anim in ["idle", "walk", "dash", "jump", "hit"]:     # a tilted crown projects to an offset box: the ring must stay on the halo's centre
		actor.pose(anim, 12, "", {}, 0, 0, 1)
		glow.place()
		var centre: Vector2 = (actor.camera.unproject_position(halo.global_transform * halo.mesh.get_aabb().get_center()) + actor.body.offset) * actor.body.scale
		check(glow.visible and glow.position.distance_to(centre) < 3.0, "%s: the glow sits on the halo in %s (%.1f px off)" % [key, anim, glow.position.distance_to(centre)])
	actor.pose("idle", 30, "", {}, 0, 0, 1)
	glow.place()
	check(glow.scale.x * glow.texture.width > 40.0 and glow.scale.x * glow.texture.width < 400.0, "%s: the glow is ring sized (%.0f px)" % [key, glow.scale.x * glow.texture.width])
	var before := glow.position
	actor.pose("idle", 30, "", {}, 0, 0, -1)
	glow.place()
	check(glow.position.distance_to(before) > 1.0, key + ": the glow follows the halo when the fighter turns")
	halo.visible = false
	glow.place()
	check(not glow.visible, key + ": the glow hides with the halo")
	halo.visible = true
	actor.pose("idle", 30, "", {}, 0, 0, 1)
	glow.place()
	var colour: Color = glow.modulate
	check(colour.r >= 0.99 or colour.g >= 0.99 or colour.b >= 0.99, key + ": the glow colour is a full-strength hue")
	check(near(colour.a, glow.STRENGTH), key + ": the glow strength")

func _first(actor: Node, shader: Shader) -> ShaderMaterial:
	for m in actor.ba_mats:
		if m.shader == shader:
			return m
	return null

func _window_scale(actor: Node) -> void:
	var base_size: Vector2i = actor.viewport.size
	var base_offset: Vector2 = actor.body.offset
	var base_on_screen: float = actor.body.scale.x * float(base_size.x)
	var real_h := root.size.y
	var saved := root.content_scale_size
	var table := {1.5: int(round(float(real_h) / 1.5)), 2.0: int(round(float(real_h) / 2.0)), 1.0: int(real_h), 4.0: int(round(float(real_h) / 4.0))}
	for want in [1.5, 2.0, 1.0, 4.0]:
		root.content_scale_size = Vector2i(saved.x, table[want])
		actor._fit_viewport()
		var s := minf(want, 2.0)
		check(near(actor.view_scale, s, 0.01), "window %.1fx the base height: viewport scale %.2f (got %.2f)" % [want, s, actor.view_scale])
		check(actor.viewport.size == Vector2i(Vector2(880, 640) * s), "the viewport is %s at scale %.2f (got %s)" % [str(Vector2i(Vector2(880, 640) * s)), s, str(actor.viewport.size)])
		check(near(actor.body.scale.x * float(actor.viewport.size.x), base_on_screen, 0.01), "the sprite stays the same size on screen at scale %.2f" % s)
		check((actor.body.offset - base_offset * s).length() < 0.5, "the sprite's offset (the feet origin) scales with the viewport at scale %.2f (%s)" % [s, str(actor.body.offset)])
		for m in actor.ba_mats:
			if m.shader == builder.OUTLINE:
				check(near(float(m.get_shader_parameter("width_px")), builder.OUTLINE_PX * s, 0.001), "outline width is %.2f px at scale %.2f" % [builder.OUTLINE_PX * s, s])
				break
	root.content_scale_size = saved
	actor._fit_viewport()
	check(actor.viewport.size == base_size, "the viewport goes back to its size with the window")

# ── composite fringe ─────────────────────────────────────────────────────────

func lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b

## A flat disc in a transparent MSAA 4x viewport like the actor's, drawn through the real composite over a background of its own
## colour. A fringe-free composite gives 1.0 at every edge pixel; "sprite" is the viewport's own colour against the interior,
## the number it measures (0.70 at 50 percent coverage).
func _fringe() -> void:
	var comp := load("res://shaders/sd_composite.gdshader") as Shader
	var report: Array[String] = []
	for fix in [true, false, null]:
		var screen_ratio := {}
		var sprite_ratio := {}
		for c in [Color(0.9, 0.9, 0.92), Color(0.2, 0.25, 0.4)]:
			var vp := SubViewport.new()
			vp.size = Vector2i(880, 640)
			vp.transparent_bg = true
			vp.own_world_3d = true
			vp.msaa_3d = Viewport.MSAA_4X
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			root.add_child(vp)
			var env := Environment.new()
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0, 0, 0, 0)
			env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
			var we := WorldEnvironment.new()
			we.environment = env
			vp.add_child(we)
			var disc := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 1.0
			sphere.height = 2.0
			disc.mesh = sphere
			var flat := StandardMaterial3D.new()
			flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			flat.albedo_color = c
			disc.material_override = flat
			vp.add_child(disc)
			var cam := Camera3D.new()
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = 3.65
			cam.position = Vector3(0, 0, 7)
			vp.add_child(cam)
			cam.make_current()
			var out := SubViewport.new()
			out.size = Vector2i(900, 660)
			out.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			root.add_child(out)
			var bg := ColorRect.new()
			bg.color = c
			bg.size = Vector2(900, 660)
			out.add_child(bg)
			var sprite := Sprite2D.new()
			sprite.texture = vp.get_texture()
			sprite.centered = false
			sprite.position = Vector2(10, 10)
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			var mat := ShaderMaterial.new()
			mat.shader = comp
			if fix != null:
				mat.set_shader_parameter("fix_fringe", fix)
			sprite.material = mat
			out.add_child(sprite)
			for i in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			var src := vp.get_texture().get_image()
			var img := out.get_texture().get_image()
			for y in src.get_height():
				for x in src.get_width():
					var a := src.get_pixel(x, y).a
					if a > 0.4 and a < 0.6:
						screen_ratio[c] = screen_ratio.get(c, []) + [lum(img.get_pixel(x + 10, y + 10)) / lum(c)]
						sprite_ratio[c] = sprite_ratio.get(c, []) + [lum(Color(src.get_pixel(x, y), 1.0)) / lum(c)]
			vp.queue_free()
			out.queue_free()
		for c in screen_ratio:
			var s1 := 0.0
			for r in screen_ratio[c]:
				s1 += r
			var s2 := 0.0
			for r in sprite_ratio[c]:
				s2 += r
			var screen_mean: float = s1 / float(screen_ratio[c].size())
			var sprite_mean: float = s2 / float(sprite_ratio[c].size())
			check(screen_ratio[c].size() > 20, "the fringe probe found edge pixels near 50 percent coverage")
			report.append("fix_fringe=%s %s: on screen %.3f, sprite colour %.3f (n=%d)" % ["default" if fix == null else str(fix), str(c), screen_mean, sprite_mean, screen_ratio[c].size()])
			if fix != false:
				check(screen_mean > 0.985 and screen_mean < 1.015, "with the fix (%s) the 50 percent edge reads %.3f of the interior on screen" % [str(fix), screen_mean])
			else:
				check(screen_mean < 0.92, "without the fix the 50 percent edge is dark on screen (%.3f), so the probe measures the fringe" % screen_mean)
				check(sprite_mean < 0.8, "without the fix the sprite's own edge colour is %.3f of the interior" % sprite_mean)
	for line in report:
		print("BA_SHADE_FRINGE ", line)

func _finish() -> void:
	print("BA_SHADE_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	root.get_node("Bgm").stop()
	await create_timer(0.3).timeout
	quit(0 if failures.is_empty() else 1)
