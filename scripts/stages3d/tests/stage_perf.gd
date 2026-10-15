extends SceneTree

const STAGES := "res://assets/ba/stages/"
const SD_ACTOR := "res://scripts/models/sd_fighter_actor.gd"

var args := {}


func _initialize() -> void:
	create_timer(240.0).timeout.connect(func() -> void:
		print("WATCHDOG timed out")
		quit(1))
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_run()


func _calls(rid: RID) -> int:
	return RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)


func _prims(rid: RID) -> int:
	return RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await process_frame
	var stage: String = args.get("stage", StageLoader.stage_ids()[0])
	var time: String = args.get("time", "day")
	var frames := int(args.get("frames", 600))
	var warm := int(args.get("warmup", 60))
	var with_sd: bool = args.get("fighters", "1") != "0"
	var sj: Dictionary = StageLoader.read_json(STAGES + stage + "/stage.json")
	var t_load := Time.get_ticks_usec()
	var view := StageView.new()
	root.add_child(view)
	view.load_stage(STAGES + stage, sj["times"][time])
	var load_ms := (Time.get_ticks_usec() - t_load) / 1000.0
	var actors: Array = []
	var layer := Node2D.new()
	root.add_child(layer)
	if with_sd:
		for spec: Array in [["hina", -250.0, 1], ["hoshino", 250.0, -1]]:
			var a: Node2D = load(SD_ACTOR).new()
			layer.add_child(a)
			a.setup({"key": spec[0]})
			a.position = Vector2(640.0 + float(spec[1]), 612.0)
			actors.append({"actor": a, "face": spec[2], "key": spec[0]})
	var srid := view.viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(srid, true)
	var times := PackedFloat64Array()
	var last := Time.get_ticks_usec()
	for i in warm + frames:
		var t := float(i) / 60.0
		view.set_camera(120.0 * sin(t * 0.7), 1.0 + 0.1 * sin(t * 0.4))
		for it: Dictionary in actors:
			it["actor"].pose("idle", i, "", {}, 0, 0, it["face"])
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
	var warm_max := 0.0
	for i in warm:
		warm_max = maxf(warm_max, times[i])
	var run := times.slice(warm)
	var sorted := Array(run)
	sorted.sort()
	var sum := 0.0
	for v in run:
		sum += v
	var off := PackedFloat64Array()
	var off_n := int(args.get("offscreen", 200))
	for i in 20:
		RenderingServer.force_draw(false)
	var sync_a := view.viewport.get_texture().get_image()
	var t0 := Time.get_ticks_usec()
	for i in off_n:
		var t := float(i) / 60.0
		view.set_camera(120.0 * sin(t * 0.7), 1.0 + 0.1 * sin(t * 0.4))
		for it: Dictionary in actors:
			it["actor"].pose("idle", i, "", {}, 0, 0, it["face"])
		RenderingServer.force_draw(false)
	var sync_b := view.viewport.get_texture().get_image()
	var off_ms := (Time.get_ticks_usec() - t0) / 1000.0 / off_n
	var out := {
		"stage": stage, "time": time, "frames": frames, "fighters": with_sd,
		"load_ms": snappedf(load_ms, 0.1),
		"mean_ms": snappedf(sum / run.size(), 0.01), "p95_ms": snappedf(sorted[int(sorted.size() * 0.95)], 0.01), "p99_ms": snappedf(sorted[int(sorted.size() * 0.99)], 0.01), "max_ms": snappedf(sorted[-1], 0.01),
		"warmup_max_ms": snappedf(warm_max, 0.01),
		"offscreen_ms_per_frame": snappedf(off_ms, 0.01),
		"stage_viewport_cpu_ms": snappedf(RenderingServer.viewport_get_measured_render_time_cpu(srid), 0.001),
		"stage_viewport_gpu_ms": snappedf(RenderingServer.viewport_get_measured_render_time_gpu(srid), 0.001),
		"stage_view_size": [view.viewport.size.x, view.viewport.size.y],
		"draw_calls": {"stage": _calls(view.viewport.get_viewport_rid())},
		"primitives": {"stage": _prims(view.viewport.get_viewport_rid())},
	}
	for it: Dictionary in actors:
		var a: Node2D = it["actor"]
		out["draw_calls"]["sd_" + it["key"]] = _calls(a.viewport.get_viewport_rid())
		out["sd_viewport_size"] = [a.viewport.size.x, a.viewport.size.y]
	out["draw_calls"]["root"] = _calls(root.get_viewport_rid())
	print("PERF ", JSON.stringify(out))
	quit()
