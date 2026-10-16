extends SceneTree

const STAGES := "res://assets/ba/stages/"
const PX_TOL := 1.0

var checks := 0
var fails: Array[String] = []


func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void:
		print("WATCHDOG timed out")
		quit(1))
	_run()


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails.append(what)
		print("FAIL ", what)


func _run() -> void:
	await process_frame
	_test_plate_cover()
	for dir in _stage_dirs():
		var sj: Dictionary = StageLoader.read_json(dir + "/stage.json")
		for time: String in sj["times"]:
			var view := StageView.new()
			root.add_child(view)
			view.load_stage(dir, sj["times"][time])
			await process_frame
			var tag := "%s/%s" % [sj["id"], time]
			_test_camera(view, tag)
			_test_loader(view, tag)
			_test_sky(view, tag)
			await _test_freeze(view, tag)
			view.queue_free()
			await process_frame
	print("STAGE_TEST %s checks=%d fails=%d" % ["PASS" if fails.is_empty() else "FAIL", checks, fails.size()])
	quit(0 if fails.is_empty() else 1)


func _stage_dirs() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(STAGES)
	for n in d.get_directories():
		if FileAccess.file_exists(STAGES + n + "/stage.json"):
			out.append(STAGES + n)
	out.sort()
	return out


func _test_plate_cover() -> void:
	var fx: Control = load("res://scripts/fight/stage_fx.gd").new()
	root.add_child(fx)
	fx.build({"id": "gehenna-night", "plate": "bg/BG_Gehenna_Collection.jpg"})
	for z: float in [0.7, 1.0, 1.24, 1.35, 1.45, 1.72, 1.8]:
		for cam_x: float in [-260.0, -200.0, 0.0, 200.0, 260.0]:
			for shake: Vector2 in [Vector2.ZERO, Vector2(7.0, -5.0), Vector2(-7.0, 5.0), Vector2(7.0, 5.0), Vector2(-7.0, -5.0)]:
				fx.update_camera(cam_x, z, shake, 636.0)
				var r := Rect2(fx.plate.position, fx.plate.size * fx.plate.scale)
				check(r.position.x <= 0.0 and r.position.y <= 0.0 and r.end.x >= 1280.0 and r.end.y >= 720.0, "the 2D plate covers the screen at zoom %.2f, cam_x %.0f, shake %s" % [z, cam_x, shake])
	fx.queue_free()


func _screen(view: StageView, x_px: float) -> Vector2:
	return view.camera.unproject_position(StageCamera.feet(view.info["lane"], view.info["camera"], x_px))


func _test_camera(view: StageView, tag: String) -> void:
	var cam: Dictionary = view.info["camera"]
	var half: float = view.info["lane"]["fight_half_px"]
	var zooms: Array = cam["zooms"].duplicate()
	zooms.append(1.0)
	zooms.append_array([1.45, 1.7, 1.8])
	var worst := 0.0
	for z: float in zooms:
		for cam_x: float in [0.0, 310.0, -450.0, 190.0, -190.0]:
			for lift: float in [0.0, 20.0, 40.0, 60.0]:
				for shake: Vector2 in [Vector2.ZERO, Vector2(7.0, -5.0)]:
					view.set_camera(cam_x, z, shake, lift)
					for x in [-half, -200.0, 0.0, 250.0, half]:
						var p := _screen(view, x)
						var want := Vector2(640.0 + (x - cam_x) * z + shake.x, 612.0 + lift * z + shake.y)
						worst = maxf(worst, p.distance_to(want))
						check(absf(p.x - want.x) <= PX_TOL and absf(p.y - want.y) <= PX_TOL, "%s camera z=%.2f cam_x=%d lift=%d shake=%s x=%d: got %s want %s" % [tag, z, cam_x, lift, shake, x, p, want])
					var a := _screen(view, 0.0)
					var b := _screen(view, float(cam["px_per_unit"]))
					check(absf((b.x - a.x) - float(cam["px_per_unit"]) * z) <= PX_TOL, "%s px per unit at z=%.2f" % [tag, z])
	print("camera ", tag, " worst error px ", snappedf(worst, 0.001))
	view.set_camera(0.0, 1.0)


func _test_loader(view: StageView, tag: String) -> void:
	var w := view.world
	check(w.report["null_materials"] == 0 and w.report["missing_sidecar"].is_empty(), "%s map has no null or unknown material" % tag)
	check(w.report["surfaces"] > 0 and w.report["lightmapped_surfaces"] > 0, "%s map surfaces and lightmapped surfaces" % tag)
	var meshes := 0
	var bad := 0
	var unbound := 0
	for mi: MeshInstance3D in w.find_children("*", "MeshInstance3D", true, false):
		meshes += 1
		var surfaces := mi.mesh.get_surface_count()
		for s in surfaces:
			var m: Material = mi.material_override if mi.material_override != null else mi.get_surface_override_material(s)
			if not (m is ShaderMaterial):
				bad += 1
				continue
			if StageLoader.lightmap_index(mi.name) >= 0 and w.map_root.is_ancestor_of(mi):
				var sm := m as ShaderMaterial
				var lm: Texture2D = sm.get_shader_parameter("lightmap")
				if lm == null or not sm.get_shader_parameter("use_lightmap") or lm.get_image().get_format() != Image.FORMAT_BPTC_RGBFU:
					unbound += 1
	check(meshes > 0, "%s world has meshes (%d)" % [tag, meshes])
	check(bad == 0, "%s every surface has a ShaderMaterial (%d without)" % [tag, bad])
	check(unbound == 0, "%s every lightmapped surface has the HDR lightmap bound (%d without)" % [tag, unbound])
	for p: GPUParticles3D in w.find_children("*", "GPUParticles3D", true, false):
		check(p.process_material is ShaderMaterial and p.material_override is ShaderMaterial, "%s particles use shader materials" % tag)
	view.set_shadow_blobs([Vector4(1.0, 2.0, 3.0, 0.5)])
	check(not w.lit.is_empty(), "%s lit materials are registered for shadow blobs" % tag)
	var blobs_ok := true
	var lit_map := 0
	for mi: MeshInstance3D in w.map_root.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var sm := mi.get_surface_override_material(s) as ShaderMaterial
			if sm != null and sm.get_shader_parameter("ba_shader") == 0:
				lit_map += 1
				var arr: PackedVector4Array = sm.get_shader_parameter("shadow_blobs")
				blobs_ok = blobs_ok and arr.size() == 2 and arr[0] == Vector4(1.0, 2.0, 3.0, 0.5) and arr[1] == Vector4.ZERO
	check(blobs_ok and lit_map > 0, "%s set_shadow_blobs reaches every lit map surface (%d)" % [tag, lit_map])
	view.set_shadow_blobs([])
	check(view.env.sky != null and view.env.background_mode == Environment.BG_SKY, "%s sky is set" % tag)
	check(view.env.tonemap_mode == Environment.TONE_MAPPER_LINEAR and view.env.ambient_light_source == Environment.AMBIENT_SOURCE_DISABLED, "%s linear tonemap, no ambient" % tag)


func _world_box(mi: MeshInstance3D) -> AABB:
	var t := mi.global_transform
	var faces := mi.mesh.get_faces()
	var box := AABB(t * faces[0], Vector3.ZERO)
	for v in faces:
		box = box.expand(t * v)
	return box


func _test_sky(view: StageView, tag: String) -> void:
	var bank: Array = StageLoader.read_json(view.stage_dir.path_join(view.info["sky"]["bank"]))
	var clouds := view.sky.get_node("Layer_bank").get_children()
	check(clouds.size() == bank.size(), "%s rebuilds every bank cloud (%d of %d)" % [tag, clouds.size(), bank.size()])
	var off := 0
	var worst := 0.0
	for i in mini(clouds.size(), bank.size()):
		var twin := view.world.map_root.find_child(bank[i]["node"], true, false) as MeshInstance3D
		if twin == null:
			check(false, "%s bank cloud %s has a twin in the map" % [tag, bank[i]["node"]])
			continue
		var a := _world_box(clouds[i])
		var b := _world_box(twin)
		var err := maxf(a.position.distance_to(b.position), a.end.distance_to(b.end))
		worst = maxf(worst, err)
		off += int(err > 0.05)
		check(err <= 0.05 and not twin.visible, "%s bank cloud %s spans %s, its hidden twin %s (%.3f m off)" % [tag, bank[i]["node"], a, b, err])
	print("bank ", tag, " clouds=", bank.size(), " off=", off, " worst_m=", snappedf(worst, 0.001))
	for layer: Dictionary in view.sky.layers:
		for it: Dictionary in layer["items"]:
			var mi: MeshInstance3D = it["mi"]
			var right := Vector3.UP.cross(-mi.position).normalized()
			var mirrored: bool = mi.transform.basis.x.dot(right) < 0.0
			check(mirrored == it["flip"], "%s sky %s %s at az %.0f has flip %s but mirrored %s" % [tag, layer["name"], it["name"], it["az"], it["flip"], mirrored])


func _grab(view: StageView) -> PackedByteArray:
	await RenderingServer.frame_post_draw
	return view.viewport.get_texture().get_image().get_data()


func _diff(a: PackedByteArray, b: PackedByteArray) -> int:
	if a.size() != b.size():
		return a.size()
	var n := 0
	for i in range(0, a.size(), 4):
		if a[i] != b[i] or a[i + 1] != b[i + 1] or a[i + 2] != b[i + 2]:
			n += 1
	return n


func _test_freeze(view: StageView, tag: String) -> void:
	view.set_camera(0.0, 1.0)
	for i in 40:
		await process_frame
	view.process_mode = Node.PROCESS_MODE_DISABLED
	var t0 := view.stage_time
	for i in 3:
		await process_frame
	var a := await _grab(view)
	for i in 12:
		await process_frame
	await create_timer(0.4).timeout
	var b := await _grab(view)
	check(view.stage_time == t0, "%s stage_time holds while frozen" % tag)
	var frozen_diff := _diff(a, b)
	check(frozen_diff == 0, "%s frozen frames are identical (%d differing pixels)" % [tag, frozen_diff])
	view.process_mode = Node.PROCESS_MODE_INHERIT
	for i in 25:
		await process_frame
	var c := await _grab(view)
	var live_diff := _diff(a, c)
	check(view.stage_time > t0 and live_diff > 40, "%s resumed frames differ (%d differing pixels)" % [tag, live_diff])
	print("freeze ", tag, " frozen_diff=", frozen_diff, " live_diff=", live_diff, " t0=", snappedf(t0, 0.001))
