extends SceneTree
## Captures the SD fighters in a real fight screen for before and after comparisons of the shading.
## Run in a real window: SHOT_DIR=/tmp/out TAG=after LIGHT=none|day|night SHOTS=idle,attack,hit,ko \
##   godot --path . --resolution 1280x720 --script res://scripts/models/tests/ba_shade_shots.gd
## Writes <dir>/<tag>_<light>_<key>_<pose>_f<facing>.png (a crop around the fighter) and <tag>_<light>_full_<n>.png.
## VIA_VIEW=1 poses hit, block, ko and super through fighter_view.step(). OUTLINE_PX overrides the hull width (0 draws none). LIGHT sets Game.session.stage["light"] by hand, since no stage publishes it yet; nothing outside this script reads it from here.
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

## The day numbers are the Gehenna slum values. The night descriptor has no fighter_dir yet, so the front-biased one
## here is our own.
const LIGHTS := {
	"day": {"night": false, "key_color": Color(1, 1, 1), "key_dir": Vector3(-0.4438, 0.8951, 0.0423), "ambient": Color(0.723, 0.723, 0.723),
		"fighter_dir": Vector3(0.5964, 0.4964, 0.6308)},
	"night": {"night": true, "key_color": Color(0.683, 0.75, 1.0), "key_dir": Vector3(-0.4452, 0.8926, 0.0708), "ambient": Color(0.391, 0.391, 0.76),
		"fighter_dir": Vector3(0.0, 0.5, 0.866)},
}
const CROP := Vector2(500, 440)

func _initialize() -> void:
	call_deferred("_run")

func _env(name: String, fallback: String) -> String:
	var v := OS.get_environment(name)
	return v if v != "" else fallback

## The fight view's own step (flash colour and glow from fighter_view.gd) or the actor's sync() alone.
func _show(fighter: Node, via_view: bool) -> void:
	if via_view:
		fighter.view.step(1.0 / 60.0)
	else:
		fighter.view.sd_actor.sync(fighter)

func _run() -> void:
	var out := _env("SHOT_DIR", "/tmp/ba-ui-out/credits/raw")
	var tag := _env("TAG", "after")
	var light := _env("LIGHT", "none")
	var shots := _env("SHOTS", "idle,attack,hit,ko").split(",")
	DirAccess.make_dir_recursive_absolute(out)
	var game: Node = root.get_node("Game")
	var stages: GDScript = load("res://scripts/core/stages.gd")
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	game.session.begin("training")
	game.session.players[0]["fighter"] = 10004
	game.session.players[1]["fighter"] = 10005
	game.session.players[0]["special"] = 10017
	game.session.players[1]["special"] = 10017
	var stage: Dictionary = stages.LIST[0].duplicate()
	if LIGHTS.has(light):
		stage["light"] = LIGHTS[light]
	game.session.stage = stage
	await game.go("fight", {}, "cut")
	var screen: Node = game.stack.back()
	var S: Dictionary = screen.f1.get_script().S
	screen.set_physics_process(false)
	screen.phase = "fight"
	screen.hud.visible = false
	for fighter in screen.fighters:
		fighter.set_process(false)
	if OS.get_environment("OUTLINE_PX") != "":
		for fighter in screen.fighters:
			var actor: Node = fighter.view.sd_actor
			actor.BA.set_outline_width(actor.ba_mats, float(OS.get_environment("OUTLINE_PX")))
	var via_view := OS.get_environment("VIA_VIEW") == "1"
	var n := 0
	for shot in shots:
		for face in [1, -1]:
			for fighter in screen.fighters:
				var actor: Node = fighter.view.sd_actor
				var view_face: int = face
				fighter.facing = view_face
				fighter._flash = 0.0
				fighter.dim = 1.0
				actor.set_look()
				fighter.state = S.IDLE
				fighter.sf = 30
				actor.blending = false
				match shot:
					"idle":
						actor.pose("idle", 30, "", {}, 0, 0, face)
					"attack":
						var key := "5H"
						var move: Dictionary = fighter.moves[key]
						actor.pose("attack", 0, key, move, 8, 0, face)
					"hit":
						fighter._flash = 0.55
						fighter.state = S.HIT
						fighter.sf = 3
						_show(fighter, via_view)
					"block":
						fighter._flash = 0.3
						fighter.state = S.BLOCK
						fighter.sf = 3
						_show(fighter, via_view)
					"ko":
						fighter.state = S.KO
						fighter.sf = 90
						_show(fighter, via_view)
					"hitc", "blockc":
						# the view's flash colour
						fighter._flash = 0.55 if shot == "hitc" else 0.3
						fighter.state = S.HIT if shot == "hitc" else S.BLOCK
						fighter.sf = 3
						actor.sync(fighter)
						actor.set_look(fighter._flash, Color(1.0, 0.97, 0.9) if shot == "hitc" else Color(0.62, 0.95, 1.0))
					"super":
						if via_view:
							fighter.view._super = 1.0
							_show(fighter, true)
						else:
							actor.pose("idle", 30, "", {}, 0, 0, face)
							actor.set_look(0.0, Color.WHITE, 1.0, 0.0, 0.9, Color(1.0, 0.85, 0.35))
			for i in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			n += 1
			img.save_png("%s/%s_%s_full_%s_f%d.png" % [out, tag, light, shot, face])
			var scale := float(img.get_height()) / 720.0
			for fighter in screen.fighters:
				var origin: Vector2 = fighter.view.get_global_transform_with_canvas().origin * scale
				var rect := Rect2i(Vector2i(int(origin.x - CROP.x * scale * 0.5), int(origin.y - CROP.y * scale * 0.86)), Vector2i(CROP * scale))
				var crop := img.get_region(rect.intersection(Rect2i(Vector2i.ZERO, img.get_size())))
				crop.save_png("%s/%s_%s_%s_%s_f%d.png" % [out, tag, light, fighter.data["key"], shot, face])
	print("BA_SHOTS done ", n, " ", out, " window ", root.size)
	root.get_node("Bgm").stop()
	await create_timer(0.3).timeout
	quit(0)
