extends SceneTree

const STAGES := "res://assets/ba/stages/"
const PX_TOL := 1.0
const LIFT_TOL := 0.01
const PROBE_TOL := 2.0
const PROBE_R := 0.06
const LANES := [-250.0, -230.0, 0.0, 230.0, 250.0]
const PROBE_LANES := [-230.0, 230.0]
const START_X := 230.0
const CUT_LEN := 60
const CUT_KINDS := [[1.35, 1.45, 30.0, 400.0, 161.0], [1.52, 1.72, 40.0, 380.0, 177.0]]
const CORNER_ZOOMS := [0.7, 1.0, 1.45, 1.8]
const CORNER_XS := [-250.0, 0.0, 250.0]
const CORNER_LIFTS := [0.0, 60.0]
const STRICT_PROBES := ["intro_v2", "corner_cuts"]
const STRICT_LIFT := 41.0
const CONTROL_MIN := 1000
const FILM_TICKS := [1, 8, 48, 96, 97, 100, 104, 108, 112, 116, 120, 124, 128, 132, 133, 180, 228, 229, 230, 260]

var checks := 0
var fails: Array[String] = []
var paths := {}


func _initialize() -> void:
	create_timer(900.0).timeout.connect(func() -> void:
		print("WATCHDOG timed out")
		quit(1))
	paths = {
		"intro_p1_left": _intro.bind(1.0),
		"intro_p1_right": _intro.bind(-1.0),
		"intro_v2": _intro_v2,
		"pan_sweep": _pan_sweep,
		"dolly": _dolly,
		"corner_cuts": _corner_cuts,
		"jitter": _jitter,
		"ex_corner": _ex_corner,
	}
	if "--film" in OS.get_cmdline_user_args():
		_film()
	else:
		_run()


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails.append(what)
		if fails.size() <= 100:
			print("FAIL ", what)


func _tick(cam_x: float, zoom: float, lift: float, shake := Vector2.ZERO) -> Dictionary:
	return {"cam_x": cam_x, "zoom": zoom, "lift": lift, "shake": shake}


func _framing(t: Dictionary) -> String:
	return "cam_x %.1f zoom %.3f lift %.2f shake %s" % [t["cam_x"], t["zoom"], t["lift"], t["shake"]]


# look at scripts/fight/fight_screen.gd _cut_shot and CUT_KINDS for reference as to why i picked this.
func _intro(side: float) -> Array:
	var out := []
	for phase_t in range(1, 301):
		var c := (phase_t - 1) / CUT_LEN
		if c >= 4:
			out.append(_tick(0.0, 1.0, 0.0))
			continue
		var k: Array = CUT_KINDS[c % 2]
		var facing := (1.0 if c < 2 else -1.0) * side
		var u := float((phase_t - 1) % CUT_LEN) / float(CUT_LEN - 1)
		var p := 0.86 * (1.0 - pow(1.0 - u / 0.3, 3.0)) if u < 0.3 else 0.86 + 0.14 * (u - 0.3) / 0.7
		var z := lerpf(k[0], k[1], p)
		out.append(_tick(-facing * START_X + k[2] * facing, z, k[4] - (612.0 - k[3]) / z))
	return out


# look at scripts/fight/fight_screen.gd _entry_shot (122d4366) for reference as to why i picked this.
func _intro_v2() -> Array:
	var out := []
	for phase_t in range(1, 301):
		var x := 190.0
		var z := 1.0
		if phase_t <= 96:
			x = -190.0
			z = 1.52 + 0.18 * smoothstep(0.0, 1.0, (phase_t - 1) / 95.0)
		elif phase_t <= 132:
			var u := (phase_t - 96) / 36.0
			var e := u * u * u * (u * (6.0 * u - 15.0) + 10.0)
			x = -190.0 + 380.0 * e
			z = 1.7 - 0.18 * e
		elif phase_t <= 228:
			z = 1.52 + 0.18 * smoothstep(0.0, 1.0, (phase_t - 133) / 95.0)
		var t := _tick(x, z, 177.0 - 232.0 / z) if phase_t <= 228 else _tick(0.0, 1.0, 0.0)
		if phase_t in [1, 8, 96, 133, 228, 229, 230] or (phase_t >= 97 and phase_t <= 132):
			t["render"] = true
		out.append(t)
	return out


func _pan_sweep() -> Array:
	var out := []
	for z: float in [1.0, 1.45, 1.8]:
		for lift: float in [0.0, 60.0]:
			for i in 101:
				out.append(_tick(250.0 - absf(10.0 * i - 500.0), z, lift))
	return out


func _dolly() -> Array:
	var out := []
	for x: float in [-250.0, 0.0, 250.0]:
		var z := 1.0
		out.append(_tick(x, z, 0.0))
		for goal: float in [1.8, 0.7, 1.8]:
			while z != goal:
				z = move_toward(z, goal, 0.02)
				out.append(_tick(x, z, 0.0))
	return out


func _corner_cuts() -> Array:
	var corners := []
	for z: float in CORNER_ZOOMS:
		for x: float in CORNER_XS:
			for lift: float in CORNER_LIFTS:
				corners.append(_tick(x, z, lift))
	var n := corners.size()
	var next := PackedInt32Array()
	next.resize(n)
	var stack := [0]
	var order := []
	while not stack.is_empty():
		var v: int = stack.back()
		if next[v] < n - 1:
			var u := next[v] + int(next[v] >= v)
			next[v] += 1
			stack.append(u)
		else:
			order.append(stack.pop_back())
	order.reverse()
	var out := []
	for v: int in order:
		for i in 3:
			out.append(corners[v])
	return out


func _jitter() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261015
	var at := Vector3(0.0, 1.0, 0.0)
	var goal := at
	var out := []
	for i in 1500:
		if i % 120 == 0:
			goal = Vector3(rng.randf_range(-250.0, 250.0), rng.randf_range(0.7, 1.8), rng.randf_range(0.0, 60.0))
		var step := (goal - at) * 0.04
		at += Vector3(clampf(step.x, -12.0, 12.0) + rng.randf_range(-3.0, 3.0), clampf(step.y, -0.02, 0.02) + rng.randf_range(-0.005, 0.005), clampf(step.z, -3.0, 3.0) + rng.randf_range(-1.0, 1.0))
		at = at.clamp(Vector3(-250.0, 0.7, 0.0), Vector3(250.0, 1.8, 60.0))
		out.append(_tick(at.x, at.y, at.z, Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 7.0)))
	return out


func _ex_corner() -> Array:
	var out := []
	for z: float in [1.0, 1.15, 1.3]:
		for lift: float in [0.0, 56.0]:
			for i in 193:
				out.append(_tick(480.0 - absf(10.0 * i - 960.0), z, lift))
	return out


func _cut_ticks(path: Array) -> Array:
	var out := []
	for i in path.size():
		if i == 0 or absf(path[i]["cam_x"] - path[i - 1]["cam_x"]) > 20.0 or absf(path[i]["zoom"] - path[i - 1]["zoom"]) > 0.04 or absf(path[i]["lift"] - path[i - 1]["lift"]) > 6.0:
			out.append(i)
	return out


func _stage_dirs() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(STAGES)
	for n in d.get_directories():
		if FileAccess.file_exists(STAGES + n + "/stage.json"):
			out.append(STAGES + n)
	out.sort()
	return out


func _void_sky() -> Sky:
	var sh := Shader.new()
	sh.code = "shader_type sky; void sky() { COLOR = EYEDIR.y < 0.0 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 1.0); }"
	var m := ShaderMaterial.new()
	m.shader = sh
	var s := Sky.new()
	s.sky_material = m
	return s


func _void_count(d: PackedByteArray) -> int:
	var n := 0
	for i in range(0, d.size(), 4):
		if d[i + 1] > 200 and d[i] < 80 and d[i + 2] < 80:
			n += 1
	return n


func _probe(view: StageView, x_px: float) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.0, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.0, 1.0)
	mat.no_depth_test = true
	var sphere := SphereMesh.new()
	sphere.radius = PROBE_R
	sphere.height = PROBE_R * 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	view.world.add_child(mi)
	mi.global_position = StageCamera.feet(view.info["lane"], view.info["camera"], x_px)
	return mi


func _apply(fx: Control, t: Dictionary) -> void:
	var z: float = t["zoom"]
	var sh: Vector2 = t["shake"]
	fx.update_camera(t["cam_x"], z, sh, 612.0 + float(t["lift"]) * z + sh.y - 24.0 * z)


func _analytic(view: StageView, t: Dictionary, tag: String, st: Dictionary) -> void:
	var k := float(view.viewport.size.x) / 1280.0
	var z: float = t["zoom"]
	var sh: Vector2 = t["shake"]
	for x: float in LANES:
		var p := view.camera.unproject_position(StageCamera.feet(view.info["lane"], view.info["camera"], x)) / k
		var want := Vector2(640.0 + (x - float(t["cam_x"])) * z + sh.x, 612.0 + float(t["lift"]) * z + sh.y)
		st["worst"] = maxf(st["worst"], p.distance_to(want))
		check(absf(p.x - want.x) <= PX_TOL and absf(p.y - want.y) <= PX_TOL, "%s lane x %d lands at %s, want %s (%s)" % [tag, x, p, want, _framing(t)])
	var lift := float(view.cam_state["lift"])
	st["lift_worst"] = maxf(st["lift_worst"], absf(lift - float(t["lift"])))
	check(absf(lift - float(t["lift"])) <= LIFT_TOL, "%s StageFx derives lift %.4f, want %.4f (%s)" % [tag, lift, t["lift"], _framing(t)])


func _grab(view: StageView) -> Image:
	await RenderingServer.frame_post_draw
	var img := view.viewport.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _probe_lane(view: StageView, t: Dictionary, want: float) -> float:
	var z: float = t["zoom"]
	var sh: Vector2 = t["shake"]
	var m := PROBE_R * float(view.info["camera"]["px_per_unit"]) * z + 9.0
	var x0 := float(t["cam_x"]) - sh.x / z
	return clampf(want, x0 + (m - 640.0) / z, x0 + (640.0 - m) / z)


func _render(view: StageView, t: Dictionary, tag: String, probe: bool, probes: Array, boxes: Array, st: Dictionary) -> void:
	var xs: Array = PROBE_LANES.duplicate()
	for j in probes.size():
		var pr: MeshInstance3D = probes[j]
		pr.visible = probe
		if probe:
			xs[j] = _probe_lane(view, t, PROBE_LANES[j])
			st["probe_moved"] += int(xs[j] != PROBE_LANES[j])
			pr.global_position = StageCamera.feet(view.info["lane"], view.info["camera"], xs[j])
	var t0 := Time.get_ticks_usec()
	var img: Image = await _grab(view)
	var d := img.get_data()
	var n := _void_count(d)
	st["rendered"] += 1
	st["void"] += n
	check(n == 0, "%s shows %d void pixels (%s)" % [tag, n, _framing(t)])
	if n > 0 and not st["saved"]:
		st["saved"] = true
		var png := "res://tmp/b2_void_%s.png" % tag.replace("/", "_").replace(" ", "_")
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tmp"))
		img.save_png(ProjectSettings.globalize_path(png))
		print("void frame saved to ", png)
	if probe:
		_check_probes(view, img, d, t, tag, probes, xs, st)
	for pr: MeshInstance3D in probes:
		pr.visible = false
	_check_near(view, t, tag, boxes, st)
	st["ms"] += float(Time.get_ticks_usec() - t0) / 1000.0


func _check_probes(view: StageView, img: Image, d: PackedByteArray, t: Dictionary, tag: String, probes: Array, xs: Array, st: Dictionary) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var k := float(w) / 1280.0
	var r := PROBE_R * float(view.info["camera"]["px_per_unit"]) * float(t["zoom"]) * k
	var m := r + 8.0 * k
	for j in probes.size():
		var pr: MeshInstance3D = probes[j]
		var c := view.camera.unproject_position(pr.global_position)
		if c.x - m < 0.0 or c.y - m < 0.0 or c.x + m > float(w) or c.y + m > float(h):
			st["probe_off"] += 1
			st["probe_off_low"] += int(float(t["lift"]) <= STRICT_LIFT)
			continue
		var sum := Vector2.ZERO
		var cnt := 0
		for y in range(int(c.y - m), int(c.y + m) + 1):
			for x in range(int(c.x - m), int(c.x + m) + 1):
				var o := (y * w + x) * 4
				if d[o] > 200 and d[o + 1] < 60 and d[o + 2] > 200:
					sum += Vector2(x + 0.5, y + 0.5)
					cnt += 1
		st["probes"] += 1
		var err := INF if cnt == 0 else (sum / cnt).distance_to(c) / k
		if cnt > 0:
			st["probe_worst"] = maxf(st["probe_worst"], err)
		check(err <= PROBE_TOL, "%s probe at lane x %.1f drawn %s px from the camera set this tick (%d probe pixels, want it at %s; %s)" % [tag, xs[j], snappedf(err, 0.01), cnt, c / k, _framing(t)])


func _near_hits(o: Vector3, near: float, boxes: Array) -> Array:
	var best := INF
	var best_name := ""
	var inside := []
	for b: Array in boxes:
		var box: AABB = b[1]
		var dist := o.distance_to(o.clamp(box.position, box.end))
		if dist < best:
			best = dist
			best_name = b[0]
		if box.grow(near + 0.05).has_point(o):
			inside.append("%s %s" % [b[0], box])
	return [inside, best, best_name]


func _check_near(view: StageView, t: Dictionary, tag: String, boxes: Array, st: Dictionary) -> void:
	var o := view.camera.global_position
	var near := view.camera.near
	var h := _near_hits(o, near, boxes)
	if h[1] < st["near"]:
		st["near"] = h[1]
		st["near_at"] = "%s at %s" % [h[2], _framing(t)]
	check(h[0].is_empty(), "%s camera %s is inside the grown box of %s (%s)" % [tag, o, h[0], _framing(t)])
	check(near < h[1], "%s camera near %.3f is not below the distance %.3f to %s (%s)" % [tag, near, h[1], h[2], _framing(t)])


func _void_control(fx: Control, view: StageView, tag: String) -> int:
	var hidden := []
	for c in view.world.get_children():
		if c.name == "far" or c.name == "props":
			c.visible = false
			hidden.append(c)
	_apply(fx, _tick(0.0, 1.0, 0.0))
	var img: Image = await _grab(view)
	var n := _void_count(img.get_data())
	for c: Node3D in hidden:
		c.visible = true
	check(hidden.size() == 2 and n > CONTROL_MIN, "%s without the far field and props shows %d void pixels with %d roots hidden, the counter needs more than %d" % [tag, n, hidden.size(), CONTROL_MIN])
	return n


func _drive(fx: Control, view: StageView, tag: String, path: Array, probes: Array, boxes: Array, strict: bool) -> void:
	var cuts := {}
	for i: int in _cut_ticks(path):
		cuts[i] = true
	var st := {"worst": 0.0, "lift_worst": 0.0, "rendered": 0, "forced": 0, "probes": 0, "probe_off": 0, "probe_off_low": 0, "probe_moved": 0, "probe_worst": 0.0, "void": 0, "saved": false, "near": INF, "near_at": "", "ms": 0.0}
	var xf: Array[Transform3D] = []
	var left := 0
	for i in path.size():
		var t: Dictionary = path[i]
		_apply(fx, t)
		_analytic(view, t, "%s tick %d" % [tag, i + 1], st)
		xf.append(view.camera.transform)
		if cuts.has(i):
			left = 3
		var forced: bool = t.get("render", false)
		st["forced"] += int(forced)
		if left > 0 or i % 4 == 0 or forced:
			await _render(view, t, "%s tick %d" % [tag, i + 1], cuts.has(i) or i % 12 == 0 or forced, probes, boxes, st)
		left -= 1
	for i in range(path.size() - 1, -1, -1):
		_apply(fx, path[i])
		check(view.camera.transform == xf[i], "%s tick %d replayed after tick %d gives a different camera (%s)" % [tag, i + 1, mini(i + 2, path.size()), _framing(path[i])])
	if strict:
		check(st["probe_off_low"] == 0, "%s skipped %d probes off screen at lift <= %.0f" % [tag, st["probe_off_low"], STRICT_LIFT])
	print("path %s ticks=%d cuts=%d render_flags=%d rendered=%d worst_px=%.4f lift_err=%.5f probes=%d probes_moved=%d probes_off_screen=%d (lift<=%.0f: %d) probe_worst_px=%.3f void=%d nearest_prop=%.3f m (%s) ms_per_render=%.1f" % [
		tag, path.size(), cuts.size(), st["forced"], st["rendered"], st["worst"], st["lift_worst"], st["probes"], st["probe_moved"], st["probe_off"], STRICT_LIFT, st["probe_off_low"], st["probe_worst"], st["void"], st["near"], st["near_at"], st["ms"] / maxf(1.0, st["rendered"])])


func _build(sess: Session, entry: Dictionary, time: String) -> Control:
	sess.stage_time = time
	sess.stage = entry
	var fx: Control = load("res://scripts/fight/stage_fx.gd").new()
	root.add_child(fx)
	fx.build(sess.stage)
	return fx


func _film() -> void:
	await process_frame
	var sess: Session = root.get_node("Game").session
	var path := _intro_v2()
	for entry: Dictionary in Stages.LIST:
		if entry.get("map", "") != "gehennaslum":
			continue
		for time: String in entry["times"]:
			var fx := _build(sess, entry, time)
			var view: StageView = fx.view
			view.set_process(false)
			var cam := view.camera
			var far := Vector3.ZERO
			var far_d := 0.0
			var near := Vector3.ZERO
			var near_d := INF
			for c in view.world.get_children():
				if c.name == "far":
					for mi: MeshInstance3D in c.find_children("*", "MeshInstance3D", true, false):
						var p := (mi.global_transform * mi.get_aabb()).get_center()
						var dep := (p - cam.global_position).dot(-cam.global_basis.z)
						if cam.is_position_in_frustum(p) and dep > far_d:
							far = p
							far_d = dep
						if cam.is_position_in_frustum(p) and dep < near_d:
							near = p
							near_d = dep
			var refs := {"lane0": StageCamera.feet(view.info["lane"], view.info["camera"], 0.0), "far_near": near, "far": far}
			var out := ProjectSettings.globalize_path("res://tmp/intro2/" + time)
			DirAccess.make_dir_recursive_absolute(out)
			var prev := {}
			var peak := {}
			for i in path.size():
				var phase_t := i + 1
				view.world.set_stage_time(StageView.PREWARM + i / 60.0)
				view.sky.set_stage_time(StageView.PREWARM + i / 60.0)
				_apply(fx, path[i])
				var line := ""
				for r: String in refs:
					var s := cam.unproject_position(refs[r])
					if phase_t >= 97 and phase_t <= 132:
						var d: Vector2 = s - prev[r]
						peak[r] = maxf(peak.get(r, 0.0), d.length())
						line += " %s (%.1f, %.1f) d (%.2f, %.2f)" % [r, s.x, s.y, d.x, d.y]
					prev[r] = s
				if line != "":
					print("FILM %s tick %d cam_x %.2f zoom %.4f%s" % [time, phase_t, path[i]["cam_x"], path[i]["zoom"], line])
				if phase_t in FILM_TICKS:
					var img: Image = await _grab(view)
					img.save_png(out.path_join("tick_%03d.png" % phase_t))
			print("FILM %s far_near %s depth %.1f m, far %s depth %.1f m, peak px per tick %s, %d frames in %s" % [time, near, near_d, far, far_d, peak, FILM_TICKS.size(), out])
			fx.queue_free()
			await process_frame
	quit(0)


func _run() -> void:
	await process_frame
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var t_start := Time.get_ticks_msec()
	var want_cuts := [0, 60, 120, 180, 240]
	check(_cut_ticks(_intro(1.0)) == want_cuts and _cut_ticks(_intro(-1.0)) == want_cuts, "the cut detector finds the current intro's five cuts on ticks 1, 61, 121, 181 and 241")
	var corner: Array = _corner_cuts()
	var pairs := {}
	for i: int in _cut_ticks(corner):
		if i > 0:
			pairs[_framing(corner[i - 1]) + " > " + _framing(corner[i])] = true
	check(pairs.size() == 24 * 23, "the corner path cuts between every ordered pair of the 24 corners once (%d)" % pairs.size())
	var v2: Array = _intro_v2()
	var flagged := []
	for i in v2.size():
		if v2[i].get("render", false):
			flagged.append(i + 1)
	check(v2.size() == 300 and flagged == [1, 8, 96] + range(97, 133) + [133, 228, 229, 230], "intro_v2 is 300 ticks and flags ticks 1, 8, 96, 97 to 132, 133, 228, 229 and 230 for rendering (%s)" % [flagged])
	var sess: Session = root.get_node("Game").session
	for dir in _stage_dirs():
		var sj: Dictionary = StageLoader.read_json(dir + "/stage.json")
		var entry := {}
		for e: Dictionary in Stages.LIST:
			if e.get("map", "") == sj["id"]:
				entry = e
		check(not entry.is_empty(), "%s has a Stages.LIST entry" % sj["id"])
		if entry.is_empty():
			continue
		for time: String in sj["times"]:
			var t_var := Time.get_ticks_msec()
			var fx := _build(sess, entry, time)
			var view: StageView = fx.view
			check(view != null and view.world != null and view.info["night"] == (time == "night"), "%s/%s StageFx builds the %s 3D stage from the session entry" % [sj["id"], time, time])
			view.set_process(false)
			view.sky.visible = false
			view.env.sky = _void_sky()
			var probes := []
			for x: float in PROBE_LANES:
				probes.append(_probe(view, x))
			var boxes := []
			var roots := 0
			for c in view.world.get_children():
				if c.name == "props" or c.name == "Dressing":
					roots += 1
					for mi: MeshInstance3D in c.find_children("*", "MeshInstance3D", true, false):
						boxes.append([String(c.name) + "/" + mi.name, mi.global_transform * mi.get_aabb()])
			check(roots == 2 and not boxes.is_empty(), "%s/%s has the props and Dressing roots (%d roots, %d meshes)" % [sj["id"], time, roots, boxes.size()])
			var o := view.camera.global_position
			var hit := _near_hits(o, view.camera.near, [["synthetic", AABB(o - Vector3.ONE * 0.1, Vector3.ONE * 0.2)]])
			check(not hit[0].is_empty() and not view.camera.near < hit[1], "%s/%s the near-plane check flags a synthetic box around the camera (inside %s, distance %.3f)" % [sj["id"], time, hit[0], hit[1]])
			await process_frame
			var control: int = await _void_control(fx, view, "%s/%s" % [sj["id"], time])
			for name: String in paths:
				await _drive(fx, view, "%s/%s %s" % [sj["id"], time, name], paths[name].call(), probes, boxes, name in STRICT_PROBES)
			print("variant %s/%s viewport %s void_control=%d took %.1f s" % [sj["id"], time, view.viewport.size, control, float(Time.get_ticks_msec() - t_var) / 1000.0])
			for pr: MeshInstance3D in probes:
				pr.queue_free()
			fx.queue_free()
			await process_frame
	print("runtime %.1f s" % (float(Time.get_ticks_msec() - t_start) / 1000.0))
	print("STAGE_PATH %s checks=%d fails=%d" % ["PASS" if fails.is_empty() else "FAIL", checks, fails.size()])
	quit(0 if fails.is_empty() else 1)
