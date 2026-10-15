extends SceneTree

const STAGES := "res://assets/ba/stages/"
const SD_ACTOR := "res://scripts/models/sd_fighter_actor.gd"
const BLOB_RADIUS := 0.5

var args := {}
var view: StageView
var loaded := ""
var layer: Node2D
var failed := false


func _initialize() -> void:
	create_timer(240.0).timeout.connect(func() -> void:
		print("WATCHDOG timed out")
		quit(1))
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_run()


func _run() -> void:
	await process_frame
	var shots: Array = [args]
	if args.has("batch"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(args["batch"]))
		if not (parsed is Array):
			print("bad batch file ", args["batch"])
			quit(1)
			return
		shots = parsed
	for s: Dictionary in shots:
		await _shoot(s)
	quit(1 if failed else 0)


func _load(stage: String, time: String) -> void:
	var key := stage + "/" + time
	if key == loaded:
		return
	if view != null:
		view.queue_free()
		await process_frame
	var dir := STAGES + stage
	var sj: Dictionary = StageLoader.read_json(dir + "/stage.json")
	var sess: Session = root.get_node("Game").session
	sess.stage_time = time
	for e: Dictionary in Stages.LIST:
		if e.get("map", "") == stage:
			sess.stage = e
	view = StageView.new()
	root.add_child(view)
	view.load_stage(dir, sj["times"][time])
	view.set_process(false)
	loaded = key


func _shoot(s: Dictionary) -> void:
	await _load(s.get("stage", StageLoader.stage_ids()[0]), s.get("time", "day"))
	var zoom := float(s.get("zoom", 1.0))
	var cam_x := float(s.get("cam_x", 0.0))
	var lift := float(s.get("lift", 0.0))
	var shake := Vector2(float(s.get("shake_x", 0.0)), float(s.get("shake_y", 0.0)))
	view.set_camera(cam_x, zoom, shake, lift)
	view.stage_time = float(s.get("t", StageView.PREWARM))
	view._push_time()
	if layer != null:
		layer.queue_free()
	layer = Node2D.new()
	root.add_child(layer)
	var blobs: Array = []
	for spec: String in String(s.get("fighters", "")).split(",", false):
		var p := spec.split(":")
		var actor: Node2D = load(SD_ACTOR).new()
		layer.add_child(actor)
		actor.setup({"key": p[0]})
		actor.pose(p[3], int(p[4]), "", {}, 0, 0, int(p[2]))
		var x := float(p[1])
		actor.position = Vector2(640.0 + (x - cam_x) * zoom + shake.x, 612.0 + lift * zoom + shake.y)
		actor.scale = Vector2.ONE * zoom
		var f := StageCamera.feet(view.info["lane"], view.info["camera"], x)
		blobs.append(Vector4(f.x, f.y, f.z, float(s.get("blob", BLOB_RADIUS))))
	view.set_shadow_blobs(blobs)
	for i in int(s.get("settle", 8)):
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var out: String = s["out"]
	var err := img.save_png(out)
	if err != OK:
		print("SAVE FAILED ", out, " ", error_string(err))
		failed = true
		return
	var rid := view.viewport.get_viewport_rid()
	var calls := RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	print("SHOT ", out, " ", img.get_size(), " stage_view ", view.viewport.size, " calls ", calls)
