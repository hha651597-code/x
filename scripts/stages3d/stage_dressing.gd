class_name StageDressing
extends RefCounted


static func load_dressing(w: StageLoader.World, base: String, ctx: Dictionary, night: bool) -> void:
	var d: Dictionary = StageLoader.read_json(w.dir.path_join(base + ".json"))
	if d.is_empty():
		return
	var kit_base: String = d["kit"]
	var side: Dictionary = StageLoader.read_json(w.dir.path_join(kit_base + ".materials.json")).get("materials", {})
	if side.is_empty():
		return
	var kit: Node = (load(w.dir.path_join(kit_base + ".glb")) as PackedScene).instantiate()
	var src := {}
	for mi: MeshInstance3D in kit.find_children("*", "MeshInstance3D", true, false):
		src[mi.name] = mi.mesh
	kit.free()
	var root := Node3D.new()
	root.name = "Dressing"
	w.add_child(root)
	var wind: Dictionary = d["wind"]
	var cache := {}
	var tag := "n" if night else "d"
	var n := 0
	for it: Dictionary in d["items"]:
		if it.has("only") and it["only"] != tag:
			continue
		var mesh: Mesh = src[it["mesh"]]
		var mi := MeshInstance3D.new()
		mi.name = "%s_%d" % [it["mesh"], n]
		mi.mesh = mesh
		for s in mesh.get_surface_count():
			var sm := mesh.surface_get_material(s) as StandardMaterial3D
			var key := sm.resource_name
			if not cache.has(key):
				var m := StageMaterials.build(side[key], sm.albedo_texture, w.dir, ctx, true)
				m.set_shader_parameter("wind_amp", float(wind["amp"]))
				m.set_shader_parameter("wind_speed", float(wind["speed"]))
				m.set_shader_parameter("wind_dir", Vector2(wind["dir"][0], wind["dir"][1]))
				cache[key] = m
				w.timed.append(m)
				w.lit.append(m)
			mi.set_surface_override_material(s, cache[key])
		var p: Array = it["pos"]
		var b := Basis.from_euler(Vector3(deg_to_rad(it.get("pitch", 0.0)), deg_to_rad(it.get("yaw", 0.0)), deg_to_rad(it.get("roll", 0.0))))
		b = b.scaled(Vector3.ONE * float(it["scale"]))
		mi.transform = Transform3D(b, Vector3(p[0], p[1], p[2]))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		var l: Array = it["light"][tag]
		mi.set_instance_shader_parameter("inst_light", Vector3(l[0], l[1], l[2]) * float(d["light_gain"]))
		mi.set_instance_shader_parameter("inst_phase", float(it["phase"]))
		mi.set_instance_shader_parameter("inst_sway", Vector2(it["sway"][0], it["sway"][1]))
		mi.set_instance_shader_parameter("inst_wind", float(it["wind"]))
		n += 1
