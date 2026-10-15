extends SceneTree

const STAGES := "res://assets/ba/stages/"
const ZOOMS := [0.7, 1.0, 1.24]
const PANS := [-7.8, 0.0, 7.4]
const LIFTS := [0.0, 1.2]
const CLOSE_ZOOMS := [1.45, 1.7, 1.8]
const CLOSE_PANS := [-0.905, 0.0, 0.905]
const EX_ZOOMS := [1.0, 1.15, 1.3]
const EX_PANS := [-2.286, -1.905, -1.429, 1.429, 1.905, 2.286]
const CONTROL_MIN := 1000

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


func _void_sky() -> Sky:
	var sh := Shader.new()
	sh.code = "shader_type sky; void sky() { COLOR = EYEDIR.y < 0.0 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 1.0); }"
	var m := ShaderMaterial.new()
	m.shader = sh
	var s := Sky.new()
	s.sky_material = m
	return s


func _count(view: StageView) -> int:
	await RenderingServer.frame_post_draw
	var img := view.viewport.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var d := img.get_data()
	var n := 0
	for i in range(0, d.size(), 4):
		if d[i + 1] > 200 and d[i] < 80 and d[i + 2] < 80:
			n += 1
	return n


func _frame(view: StageView, zoom: float, pan: float, lift: float) -> int:
	view.set_camera(pan * float(view.info["camera"]["px_per_unit"]), zoom)
	view.camera.global_position.y += lift
	for i in 4:
		await process_frame
	return await _count(view)


func _run() -> void:
	await process_frame
	var d := DirAccess.open(STAGES)
	var ids: Array[String] = []
	for n in d.get_directories():
		if FileAccess.file_exists(STAGES + n + "/stage.json"):
			ids.append(n)
	ids.sort()
	for id in ids:
		var sj: Dictionary = StageLoader.read_json(STAGES + id + "/stage.json")
		for time: String in sj["times"]:
			var view := StageView.new()
			root.add_child(view)
			view.load_stage(STAGES + id, sj["times"][time])
			view.set_process(false)
			view.sky.visible = false
			view.env.sky = _void_sky()
			var tag := "%s/%s" % [id, time]
			var total := 0
			var framings: Array[Vector2] = []
			for z: float in ZOOMS:
				for p: float in PANS:
					framings.append(Vector2(z, p))
			for z: float in CLOSE_ZOOMS:
				for p: float in CLOSE_PANS:
					framings.append(Vector2(z, p))
			for z: float in EX_ZOOMS:
				for p: float in EX_PANS:
					framings.append(Vector2(z, p))
			for lift: float in LIFTS:
				for f in framings:
					var n: int = await _frame(view, f.x, f.y, lift)
					total += n
					check(n == 0, "%s zoom %.2f pan %.2f lift %.1f has %d void pixels" % [tag, f.x, f.y, lift, n])
			var far: Array[Node3D] = []
			for c in view.world.get_children():
				if c.name == "far" or c.name == "props":
					far.append(c)
			for f in far:
				f.visible = false
			var control: int = await _frame(view, 1.0, 0.0, 0.0)
			check(control > CONTROL_MIN, "%s without the far field shows %d void pixels, the counter needs more than %d" % [tag, control, CONTROL_MIN])
			print("void ", tag, " total=", total, " control=", control)
			view.queue_free()
			await process_frame
	print("STAGE_VOID %s checks=%d fails=%d" % ["PASS" if fails.is_empty() else "FAIL", checks, fails.size()])
	quit(0 if fails.is_empty() else 1)
