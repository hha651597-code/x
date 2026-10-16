extends Node
## Debug / verification harness (autoload "Dbg"). Does nothing in a normal run.
##
##   Godot --path . -- --script=.dev/shots/menu.json         run a step file, then quit
##   Godot --path . -- --screen=select                       open straight onto a screen
##
## A step file is JSON: {"steps": [ ... ]} with steps like
##   {"session": {"mode": "versus2p", "players": [{"claimed": true, "device": "kb1", "fighter": 10005}, {...}]}}
##   {"go": "select", "params": {}, "style": "cut"}      {"wait": 1.5}      {"frames": 3}
##   {"press": ["kb1", "confirm"], "times": 2}           {"shot": "/tmp/menu.png", "scale": 0.5}
##   {"tap": ["kb1","aux"], "frames": 4}   {"hold": ["kb1","right"]}  {"release": ["kb1","right"]}  {"release_all": true}  {"timescale": 4}
##   {"print": true}      {"mouse": [640, 360]}      {"click": [640, 360]}      {"quit": true}
##   {"intro_entry": true}   play the 360 tick stage entry (two solo shots and a pan) in a fight (a step file keeps the 60 tick intro otherwise)
##   {"session": {"stage": "gehenna-night", "stage_time": "night"}}     the time a 3D stage shows
##   {"go": "fight"} with no stage in the session plays on gehenna-night (the default testing map)
##   {"stage_print": true}      prints the 3D stage's own clock and camera       {"perf": {"frames": 600, "warmup": 30}}   frame times, vsync off
##   {"stage_shot": "/tmp/stage.png"}      saves the 3D stage's own viewport, without the HUD or the fighters
##   {"stage_trace": 310}      for the next 310 frames prints STAGETRACE <frame> {cam_x, zoom, lift, feet_err_px, the fight's phase tick, frame ms}
##   {"mem": "tag"}      prints MEM tag {object, node, orphan, resource counts, static, texture, buffer and video memory, draw calls, subviewports, stack depth, fps, window size, the session's stage and time}

signal ready_to_run

var start_screen := ""
var sim_mult := 1          # extra fight sim ticks per physics frame (headless stress tests)
var cpu_vs_cpu := false   # both fighters CPU-driven (stress tests / attract mode)
var intro_entry := true   # the first round plays the 360 tick stage entry; a step file keeps the 60 tick intro unless it sets {"intro_entry": true}
var _script_path := ""

func _ready() -> void:
	if not OS.is_debug_build():
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--script="):
			_script_path = a.substr(9)
		elif a.begins_with("--screen="):
			start_screen = a.substr(9)
	if _script_path != "":
		ready_to_run.connect(_run, CONNECT_ONE_SHOT)
		# harness runs are silent unless --audio is passed (step files get rerun a lot)
		if not OS.get_cmdline_user_args().has("--audio"):
			AudioServer.set_bus_mute(0, true)
		intro_entry = false

## The first screen: --screen=name wins; a step file starts on the menu so its steps do not wait on the title; the game launched
## as itself (is_game: main.tscn is the current scene, which tests adding it under the root are not) opens the title.
func boot_screen(is_game: bool) -> String:
	if start_screen != "":
		return start_screen
	return "title" if is_game and _script_path == "" else "menu"

func _run() -> void:
	var f := FileAccess.open(_script_path, FileAccess.READ)
	if f == null:
		printerr("Dbg: cannot read ", _script_path)
		get_tree().quit(2)
		return
	var data = JSON.parse_string(f.get_as_text())
	if data == null:
		printerr("Dbg: bad JSON in ", _script_path)
		get_tree().quit(2)
		return
	# failsafe so a stuck script cannot hang forever
	get_tree().create_timer(float(data.get("timeout", 180)), true, false, true).timeout.connect(func():
		printerr("Dbg: timeout")
		get_tree().quit(3))
	await get_tree().process_frame
	await get_tree().process_frame
	for step in data.get("steps", []):
		await _step(step)
	get_tree().quit(0)

func _step(s: Dictionary) -> void:
	if s.has("session"):
		_apply_session(s["session"])
	if s.has("sim_mult"):
		sim_mult = int(s["sim_mult"])
	if s.has("cpu_vs_cpu"):
		cpu_vs_cpu = bool(s["cpu_vs_cpu"])
	if s.has("intro_entry"):
		intro_entry = bool(s["intro_entry"])
	if s.has("go"):
		var guard := 0
		while Game.busy and guard < 600:
			await get_tree().process_frame
			guard += 1
		if s["go"] == "fight" and Game.session.stage.is_empty():
			_apply_session({"stage": "gehenna-night"})
		var t0 := Time.get_ticks_usec()
		await Game.go(s["go"], s.get("params", {}), s.get("style", "cut"), s.get("opts", {}))
		print("GO ", s["go"], " ", snappedf(float(Time.get_ticks_usec() - t0) / 1000.0, 0.1), " ms")
	if s.has("go_async"):   # start a transition without waiting for it (shoot mid-wipe with later steps)
		Game.go(s["go_async"], s.get("params", {}), s.get("style", "cut"), s.get("opts", {}))
	if s.has("push"):
		Game.push(s["push"], s.get("params", {}))
	if s.has("pop"):
		Game.pop()
	if s.has("wait"):
		await get_tree().create_timer(float(s["wait"])).timeout
	if s.has("frames"):
		for i in int(s["frames"]):
			await get_tree().process_frame
	if s.has("press"):
		for i in int(s.get("times", 1)):
			Controls.inject(s["press"][0], s["press"][1])
			await get_tree().process_frame
			if s.has("gap"):
				await get_tree().create_timer(float(s["gap"])).timeout
	if s.has("until_screen"):
		var waited := 0.0
		var limit := float(s.get("max", 120.0))
		while Game.current_name() != s["until_screen"] and waited < limit:
			await get_tree().create_timer(0.25, true, false, true).timeout
			waited += 0.25
		print("UNTIL ", s["until_screen"], " reached=", Game.current_name() == s["until_screen"], " waited=", waited)
	if s.has("tap"):
		var taps: Array = s["tap"] if s["tap"][0] is Array else [s["tap"]]
		for pair in taps:
			Controls.set_held(pair[0], pair[1], true)
		for i in int(s.get("frames", 4)):
			await get_tree().physics_frame
		for pair in taps:
			Controls.set_held(pair[0], pair[1], false)
	if s.has("hold"):
		for pair in (s["hold"] if s["hold"][0] is Array else [s["hold"]]):
			Controls.set_held(pair[0], pair[1], true)
	if s.has("release"):
		for pair in (s["release"] if s["release"][0] is Array else [s["release"]]):
			Controls.set_held(pair[0], pair[1], false)
	if s.has("release_all"):
		Controls._held.clear()
	if s.has("timescale"):
		Engine.time_scale = float(s["timescale"])
	if s.has("mouse"):
		_mouse(s["mouse"], false)
	if s.has("click"):
		_mouse(s["click"], true)
	if s.has("shot"):
		await _shot(s["shot"], float(s.get("scale", 0.0)))
	if s.has("fighter"):
		_fighter_step(s["fighter"])
	if s.has("print"):
		print("PROBE ", JSON.stringify(Game.probe()))
	if s.has("stage_print"):
		_stage_print()
	if s.has("stage_trace"):
		_stage_trace(int(s["stage_trace"]))
	if s.has("mem"):
		_mem(String(s["mem"]))
	if s.has("stage_shot"):
		var v := _stage_view()
		if v != null:
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute(String(s["stage_shot"]).get_base_dir())
			v.viewport.get_texture().get_image().save_png(s["stage_shot"])
	if s.has("perf"):
		await _perf(int(s["perf"].get("frames", 600)), int(s["perf"].get("warmup", 30)))
	if s.has("quit"):
		get_tree().quit(0)

func _apply_session(d: Dictionary) -> void:
	var sess: Session = Game.session
	if d.has("mode"):
		sess.begin(d["mode"])
	if d.has("players"):
		for i in d["players"].size():
			for k in d["players"][i]:
				sess.players[i][k] = d["players"][i][k]
	if d.has("stage_time"):
		sess.stage_time = d["stage_time"]
	if d.has("stage"):
		for st in Stages.LIST:
			if st["id"] == d["stage"]:
				sess.stage = st
	if d.has("bgm"):
		sess.bgm = d["bgm"]
	if d.has("bgm_volume"):
		sess.bgm_volume = float(d["bgm_volume"])

func _stage_view() -> StageView:
	if Game.stack.is_empty() or not ("bg_layer" in Game.stack.back()):
		return null
	return Game.stack.back().bg_layer.get_meta("fx").get("view")

func _stage_print() -> void:
	var v := _stage_view()
	if v == null:
		print("STAGE none")
		return
	print("STAGE ", JSON.stringify(_stage_state(v)))

func _stage_trace(frames: int) -> void:
	var last := Time.get_ticks_usec()
	for i in frames:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var v := _stage_view()
		if v == null:
			print("STAGETRACE ", Engine.get_process_frames(), " none")
		else:
			var d := _stage_state(v)
			print("STAGETRACE ", Engine.get_process_frames(), " ", JSON.stringify({"cam_x": d["cam_x"], "zoom": d["zoom"], "lift": d["lift"], "feet_err_px": d["feet_err_px"],
				"tick": Game.stack.back().get("phase_t"), "ms": snappedf(float(now - last) / 1000.0, 0.1)}))
		last = now

func _stage_state(v: StageView) -> Dictionary:
	var scr = Game.stack.back()
	var c: Dictionary = v.cam_state
	var k := float(v.viewport.size.x) / 1280.0
	var ppu := float(v.info["camera"]["px_per_unit"])
	var feet_err := []
	for f in [scr.f1, scr.f2]:
		var p: Vector3 = StageCamera.feet(v.info["lane"], v.info["camera"], f.position.x) + Vector3.UP * (Arena.GROUND - f.position.y) / ppu
		feet_err.append(snappedf(v.camera.unproject_position(p).distance_to(f.get_global_transform_with_canvas().origin * k), 0.001))
	var a := v.camera.unproject_position(StageCamera.feet(v.info["lane"], v.info["camera"], 0.0))
	var b := v.camera.unproject_position(StageCamera.feet(v.info["lane"], v.info["camera"], ppu))
	return {"stage_time": v.stage_time, "cam_x": c["cam_x"], "zoom": c["zoom"], "lift": c["lift"],
		"frozen": scr.world_frozen, "process": v.can_process(), "feet_err_px": feet_err, "px_per_unit_err": snappedf(a.distance_to(b) / k - ppu * float(c["zoom"]), 0.001),
		"variant": v.info["id"]}

func _mem(tag: String) -> void:
	var monitors := {"objects": Performance.OBJECT_COUNT, "nodes": Performance.OBJECT_NODE_COUNT, "orphans": Performance.OBJECT_ORPHAN_NODE_COUNT,
		"resources": Performance.OBJECT_RESOURCE_COUNT, "static_bytes": Performance.MEMORY_STATIC, "texture_bytes": Performance.RENDER_TEXTURE_MEM_USED,
		"buffer_bytes": Performance.RENDER_BUFFER_MEM_USED, "video_bytes": Performance.RENDER_VIDEO_MEM_USED,
		"objects_in_frame": Performance.RENDER_TOTAL_OBJECTS_IN_FRAME, "draw_calls": Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME}
	var m := {}
	for k in monitors:
		m[k] = Performance.get_monitor(monitors[k])
	var w := DisplayServer.window_get_size()
	m["subviewports"] = _count_subviewports(get_tree().root)
	m["stack"] = Game.stack.size()
	m["fps"] = Engine.get_frames_per_second()
	m["window"] = [w.x, w.y]
	m["stage"] = Game.session.stage.get("id", "")
	m["time"] = Game.session.stage.get("time", "")
	print("MEM ", tag, " ", JSON.stringify(m))

func _count_subviewports(n: Node) -> int:
	var c := 1 if n is SubViewport else 0
	for ch in n.get_children():
		c += _count_subviewports(ch)
	return c

func _perf(frames: int, warmup: int) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var rids := {"root": get_tree().root.get_viewport_rid()}
	var v := _stage_view()
	if v != null:
		rids["stage"] = v.viewport.get_viewport_rid()
	for i in 2:
		var view = Game.stack.back().get("f%d" % (i + 1)).view
		if view != null and view.get("sd_actor") != null:
			rids["sd%d" % (i + 1)] = view.sd_actor.viewport.get_viewport_rid()
	for r in rids.values():
		RenderingServer.viewport_set_measure_render_time(r, true)
	for i in warmup:
		await get_tree().process_frame
	var ts := PackedFloat64Array()
	var sums := {}
	var last := Time.get_ticks_usec()
	for i in frames:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		ts.append(float(now - last) / 1000.0)
		last = now
		for k in rids:
			sums[k + "_cpu"] = float(sums.get(k + "_cpu", 0.0)) + RenderingServer.viewport_get_measured_render_time_cpu(rids[k])
			sums[k + "_gpu"] = float(sums.get(k + "_gpu", 0.0)) + RenderingServer.viewport_get_measured_render_time_gpu(rids[k])
	var sorted := ts.duplicate()
	sorted.sort()
	var total := 0.0
	for t in ts:
		total += t
	for k in sums:
		sums[k] = snappedf(float(sums[k]) / frames, 0.001)
	for i in 20:
		RenderingServer.force_draw(false)
	get_tree().root.get_texture().get_image()
	var t1 := Time.get_ticks_usec()
	for i in 300:
		RenderingServer.force_draw(false)
	get_tree().root.get_texture().get_image()
	var forced := float(Time.get_ticks_usec() - t1) / 1000.0 / 300.0
	print("PERF ", JSON.stringify({"frames": frames, "mean_ms": snappedf(total / frames, 0.01), "p95_ms": snappedf(sorted[int(frames * 0.95)], 0.01),
		"max_ms": snappedf(sorted[frames - 1], 0.01), "forced_draw_ms": snappedf(forced, 0.01), "render_ms": sums}))

func _mouse(p: Array, click: bool) -> void:
	var pos := Vector2(p[0], p[1])
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	Input.parse_input_event(ev)
	if click:
		for pressed in [true, false]:
			var b := InputEventMouseButton.new()
			b.position = pos
			b.global_position = pos
			b.button_index = MOUSE_BUTTON_LEFT
			b.pressed = pressed
			Input.parse_input_event(b)

func _shot(path: String, scale: float) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var target_w := 1280
	if scale > 0.0:
		target_w = int(1280.0 * scale)
	if img.get_width() != target_w:
		img.resize(target_w, int(round(float(target_w) * 9.0 / 16.0)), Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("SHOT ", path, " ", img.get_size())


## {"fighter": {"slot": 1, "state": "HIT", "hitstun": 40, "hitstop": 0, "pos": [x, y], "vel": [x, y], "hp": n, "meter": n}} - test hook for the
## verification tours: put a fighter of the running fight into a state the normal moves rarely reach (a heavy hit, a long stun, high in the air
## so an air move can play out). World coordinates as in the probe (floor y = 560). Does nothing outside a fight.
func _fighter_step(d: Dictionary) -> void:
	if Game.stack.is_empty():
		return
	var scr = Game.stack.back()
	if not ("f1" in scr and "f2" in scr):
		return
	var f: Fighter = scr.f1 if int(d.get("slot", 1)) == 1 else scr.f2
	if d.has("hp"):
		f.hp = float(d["hp"])
	if d.has("meter"):
		f.meter = float(d["meter"])
	if d.has("guard"):
		f.guard = float(d["guard"])
	if d.has("pos"):
		f.position = Vector2(float(d["pos"][0]), float(d["pos"][1]))
	if d.has("gap"):   # px past the pair's push minimum from the other fighter, on the side that one faces; after pos, so it wins
		var other: Fighter = scr.f2 if f == scr.f1 else scr.f1
		f.position.x = other.position.x + float(other.facing) * (f.push_min() + float(d["gap"]))
	if d.has("vel"):
		f.vel = Vector2(float(d["vel"][0]), float(d["vel"][1]))
	if d.has("hitstun"):
		f.hitstun = int(d["hitstun"])
	if d.has("hitstop"):
		f.hitstop = int(d["hitstop"])
	if d.has("blockstun"):
		f.blockstun = int(d["blockstun"])
	if d.has("state"):
		f._set_state(int(Fighter.S[String(d["state"])]))
		if String(d["state"]) == "JUMP":
			f.air_ok = true
