class_name StageLoader
extends RefCounted


class World extends Node3D:
	var info: Dictionary
	var dir: String
	var map_root: Node3D
	var timed: Array[ShaderMaterial] = []
	var lit: Array[ShaderMaterial] = []
	var report := {"surfaces": 0, "null_materials": 0, "missing_sidecar": [], "lightmapped_surfaces": 0}

	func set_stage_time(t: float) -> void:
		for m in timed:
			m.set_shader_parameter("stage_time", t)

	func set_shadow_blobs(blobs: Array) -> void:
		var arr := PackedVector4Array([Vector4.ZERO, Vector4.ZERO])
		for i in mini(blobs.size(), 2):
			arr[i] = blobs[i]
		for m in lit:
			m.set_shader_parameter("shadow_blobs", arr)


static func stage_ids() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open("res://assets/ba/stages")
	for n in d.get_directories():
		if FileAccess.file_exists("res://assets/ba/stages/%s/stage.json" % n):
			out.append(n)
	out.sort()
	return out


static func read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "cannot open " + path)
	return JSON.parse_string(f.get_as_text())


static func color3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


static func lightmap_index(node_name: String) -> int:
	var tag := node_name.get_slice("_", 0)
	if not tag.begins_with("lm") or tag == "lmn":
		return -1
	return int(tag.substr(2))


static func load_variant(stage_dir: String, variant: String, layers := ["map", "far", "props", "dressing", "fx"]) -> World:
	var info: Dictionary = read_json(stage_dir.path_join(variant + ".json"))
	var files: Dictionary = info["files"]
	var w := World.new()
	w.name = "World_" + variant
	w.info = info
	w.dir = stage_dir
	var clip: Array = info["clip"]["plane"] if info["clip"]["plane"] != null else [0.0, 0.0, 0.0, 0.0]
	var ctx := {
		"subtractive": color3(info["render"]["subtractive_shadow_color"]),
		"shadow_strength": float(info["render"]["main_light_shadow_strength"]),
		"clip": Vector4(clip[0], clip[1], clip[2], clip[3]),
		"blobs": PackedVector4Array([Vector4.ZERO, Vector4.ZERO]),
	}
	if "map" in layers:
		_load_map(w, files, ctx)
	if "far" in layers and files.has("far"):
		StageFar.load_group(w, files["far"], ctx)
	if "props" in layers and files.has("props"):
		StageFar.load_group(w, files["props"], ctx)
	if "dressing" in layers and files.has("dressing"):
		StageDressing.load_dressing(w, files["dressing"], ctx, variant.ends_with("_n"))
	if "fx" in layers and files.has("fx"):
		StageFxLayer.load_fx(w, files["fx"])
	return w


static func _load_map(w: World, files: Dictionary, ctx: Dictionary) -> void:
	var side: Dictionary = read_json(w.dir.path_join(files["materials"]))["materials"]
	var lms := {}
	for k: String in files["lightmaps"]:
		lms[int(k)] = load(w.dir.path_join(files["lightmaps"][k]))
	var root: Node3D = (load(w.dir.path_join(files["glb"])) as PackedScene).instantiate()
	w.add_child(root)
	w.map_root = root
	var cache := {}
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var idx := lightmap_index(mi.name)
		for s in mi.mesh.get_surface_count():
			w.report["surfaces"] += 1
			var src := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if src == null:
				w.report["null_materials"] += 1
				continue
			if not side.has(src.resource_name):
				w.report["missing_sidecar"].append(src.resource_name)
				continue
			var key := "%s|%d" % [src.resource_name, idx]
			if not cache.has(key):
				var c := ctx.duplicate()
				c["lightmap"] = lms.get(idx)
				var m := StageMaterials.build(side[src.resource_name], src.albedo_texture, w.dir, c)
				cache[key] = m
				if side[src.resource_name]["shader"] == "MX/E-Standard":
					w.lit.append(m)
			mi.set_surface_override_material(s, cache[key])
			if idx >= 0:
				w.report["lightmapped_surfaces"] += 1
