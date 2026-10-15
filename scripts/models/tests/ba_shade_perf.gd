extends SceneTree
## Frame cost of the SD fighter shading, in a real window:
##   godot --path . --resolution 1600x900 --script res://scripts/models/tests/ba_shade_perf.gd
## The display pacing (60 or 144 Hz) hides GPU work and Metal reports 0 for the viewport GPU timer, so frames are forced with
## RenderingServer.force_draw(false) (no swap, no pacing) and each chunk ends with a read-back that waits for the GPU.
## Default: the Hina vs Hoshino fight screen with the sim frozen and both fighters animating (HUD included).
## ACTORS=0,32,64 instead draws that many animating actors, one viewport each; the slope is the cost of one fighter viewport.
## Prints BA_PERF with the median, min and max milliseconds per frame over 8 chunks of FRAMES (default 40), and the median
## share of it spent in pose() (CPU animation, the same before and after the shading change).

func _initialize() -> void:
	call_deferred("_run")

func _median(a: Array) -> float:
	var s := a.duplicate()
	s.sort()
	return s[s.size() / 2]

func _chunks(step: Callable, frames: int) -> Dictionary:
	var ms: Array = []
	var posing: Array = []
	for c in 10:
		var t0 := Time.get_ticks_usec()
		var stepped := 0
		for i in frames:
			var t1 := Time.get_ticks_usec()
			step.call(c * frames + i)
			stepped += Time.get_ticks_usec() - t1
			RenderingServer.force_draw(false)
		root.get_texture().get_image()
		ms.append(float(Time.get_ticks_usec() - t0) / 1000.0 / float(frames))
		posing.append(float(stepped) / 1000.0 / float(frames))
	ms = ms.slice(2)
	posing = posing.slice(2)
	return {"median": snappedf(_median(ms), 0.01), "min": snappedf(ms.min(), 0.01), "max": snappedf(ms.max(), 0.01), "pose_median": snappedf(_median(posing), 0.01)}

func _run() -> void:
	var frames := int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 40
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	if OS.get_environment("CONTENT_H") != "":
		root.content_scale_size = Vector2i(root.content_scale_size.x, int(OS.get_environment("CONTENT_H")))
	var out := {"size": [root.size.x, root.size.y]}
	if OS.get_environment("ACTORS") != "":
		var actor_script: GDScript = load("res://scripts/models/sd_fighter_actor.gd")
		var by_count := {}
		for c in OS.get_environment("ACTORS").split(","):
			var holder := Node2D.new()
			root.add_child(holder)
			var actors: Array = []
			for i in int(c):
				var actor: Node2D = actor_script.new()
				actor.position = Vector2(60 + (i % 16) * 70, 90 + (i / 16) * 110)
				actor.scale = Vector2.ONE * 0.12
				holder.add_child(actor)
				actor.setup({"key": "hina" if i % 2 == 0 else "hoshino"})
				actor.blending = false
				actors.append(actor)
			var step := func(n: int) -> void:
				for a in actors:
					a.pose("idle", n, "", {}, 0, 0, 1)
			for i in 5:
				await process_frame
			by_count[c] = _chunks(step, frames)
			holder.queue_free()
			await process_frame
		out["by_actor_count"] = by_count
	else:
		var game: Node = root.get_node("Game")
		game.session.begin("training")
		game.session.players[0]["fighter"] = 10004
		game.session.players[1]["fighter"] = 10005
		game.session.players[0]["special"] = 10017
		game.session.players[1]["special"] = 10017
		await game.go("fight", {}, "cut")
		var screen: Node = game.stack.back()
		screen.set_physics_process(false)
		screen.phase = "fight"
		for fighter in screen.fighters:
			fighter.set_process(false)
		for i in 5:
			await process_frame
		var step := func(n: int) -> void:
			for fighter in screen.fighters:
				fighter.view.sd_actor.pose("idle", n, "", {}, 0, 0, 1 if fighter == screen.f1 else -1)
		out["fight"] = _chunks(step, frames)
		out["fighter_viewport"] = Vector2i(screen.fighters[0].view.sd_actor.viewport.size)
	print("BA_PERF ", JSON.stringify(out))
	root.get_node("Bgm").stop()
	await create_timer(0.3).timeout
	quit(0)
