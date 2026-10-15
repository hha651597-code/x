extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	var path := OS.get_environment("MOVIE_STEPS")
	var config = JSON.parse_string(FileAccess.get_file_as_string(path if path != "" else "res://scripts/models/tests/sd_gameplay_movie.json"))
	var debug: Node = root.get_node("Dbg")
	for step in config["steps"]:
		await debug._step(step)
	var music: Node = root.get_node("Bgm")
	music.stop()
	music.set_process(false)
	music.call("_exit_tree")
	await create_timer(0.3).timeout
	call_deferred("quit", 0)
