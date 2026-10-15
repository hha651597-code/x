extends SceneTree
## The render check of the carried throws: the real sim stepped tick by tick, the real view, one full frame saved at connect, grab end,
## hoist, hold, release, release + 3, touchdown and DOWN, for each thrower in both facings (Hina throws Hoshino, Hoshino throws Hina).
## Run in a real 1280x720 window, never headless (tools/sd_test.sh opens 640x360, so call Godot yourself): OUT=<dir> (default /tmp/carry_shots) Godot --path . --resolution 1280x720 --script res://scripts/models/tests/carry_shots.gd.
## Writes <OUT>/<thrower>_f<facing>_<n>_<label>.png and prints a CARRY_SHOT line per frame with the tick it was taken at.
## WHO limits the thrower, FRONT=0|1 overrides the move's front flag, MARK draws the hand and chest crosses, FX keeps the effect layer, FULL also saves the whole frame.
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

const LABELS := ["connect", "grab_end", "hoist", "hold", "release", "release3", "fly1", "fly2", "touchdown", "down", "down10", "down20"]
const CROP := Vector2i(600, 480)   # screen px around the pair, feet 60 px above the bottom edge

var screen: Node
var FI: GDScript
var states: Dictionary

func _initialize() -> void:
	call_deferred("_run")

func _env(name: String, fallback: String) -> String:
	var v := OS.get_environment(name)
	return v if v != "" else fallback

func _place(att: Node, def: Node, face: int) -> void:
	att.reset_round(-150.0 * float(face), face)
	def.reset_round(att.position.x + float(face) * (110.0 + att.spacing_extra()), -face)
	def.frame = att.frame
	screen.phase = "fight"
	for f in [att, def]:
		f._set_state(states.IDLE)
		f.input = FI.new()
		f.hitstop = 0
		f.invuln = 0

## The tick (counted from the throw's start) of every label, from a dry run of the same sim.
func _plan(att: Node, def: Node, face: int) -> Dictionary:
	_place(att, def, face)
	att._start_move("throw")
	var c: Dictionary = att.moves["throw"]["carry"]
	var at := {}
	var prev_air := -1
	for i in 260:
		screen._tick_fight(false)
		if def.carrier != null and not at.has("connect"):
			at["connect"] = i
		if at.has("connect") and not at.has("grab_end") and att.mf > int(att.moves["throw"]["startup"]):
			at["grab_end"] = i
		if def.carrier != null and att.mf == int(c["path"][0][0]) + 3 and att.hitstop == 0 and not at.has("hoist"):
			at["hoist"] = i
		if def.carrier != null and att.mf == int(c["release"]) - 1 and att.hitstop == 0:
			at["hold"] = i
		if at.has("connect") and def.carrier == null and not at.has("release"):
			at["release"] = i
		if at.has("release") and not at.has("release3") and i == at["release"] + 3:
			at["release3"] = i
			at["fly1"] = at["release"] + int(att.moves["throw"]["hit"]["hitstop"]) + 3
			at["fly2"] = at["release"] + int(att.moves["throw"]["hit"]["hitstop"]) + 7
		if def.state == states.AIRHIT and at.has("release"):
			prev_air = i
		if def.state == states.DOWN and not at.has("down"):
			at["touchdown"] = prev_air
			at["down"] = i + 3
			at["down10"] = i + 10
			at["down20"] = i + 20
		if at.has("down") and i >= at["down"] + 17:
			break
	return at

## A debug cross on a bone, in the colour given: the thrower's free hand (red) and the foe's chest (blue) when MARK is set.
func _mark(img: Image, f: Node, bone: String, col: Color) -> void:
	var actor: Node = f.view.sd_actor
	var sk: Skeleton3D = actor.grip_skeleton
	var p: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone)).origin
	var local: Vector2 = (actor.camera.unproject_position(p) + actor.body.offset) * actor.body.scale
	var at: Vector2 = f.view.rig.get_global_transform_with_canvas() * local * (float(img.get_height()) / 720.0)
	for d in range(-7, 8):
		for t in [-1, 0, 1]:
			for q in [Vector2i(int(at.x) + d, int(at.y) + t), Vector2i(int(at.x) + t, int(at.y) + d)]:
				if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height():
					img.set_pixelv(q, col)

func _shoot(out: String, who: String, face: int, n: int, label: String, tick: int, att: Node, def: Node) -> void:
	screen._sort_fighters()
	for f in [att, def]:
		f.view.step(1.0 / 60.0)
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if OS.get_environment("MARK") != "":
		_mark(img, att, "Bip001 L Hand", Color(1, 0, 0))
		_mark(img, def, "Bip001 Spine1", Color(0, 0.4, 1))
	var a: Vector2 = att.view.get_global_transform_with_canvas().origin * (float(img.get_height()) / 720.0)
	var d: Vector2 = def.view.get_global_transform_with_canvas().origin * (float(img.get_height()) / 720.0)
	var mid := (a + d) * 0.5
	var rect := Rect2i(Vector2i(int(mid.x) - CROP.x / 2, int(a.y) + 60 - CROP.y), CROP).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	img.get_region(rect).save_png("%s/%s_f%d_%d_%s.png" % [out, who, face, n, label])
	if OS.get_environment("FULL") != "":
		img.save_png("%s/full_%s_f%d_%d_%s.png" % [out, who, face, n, label])
	print("CARRY_SHOT %s f%+d %d %s tick %d mf %d foe x %.1f y %.1f roll %.1f state %s" % [who, face, n, label, tick, att.mf, def.position.x - att.position.x, def.position.y - 560.0, def.carry_roll * float(face), def.state_name()])

func _run() -> void:
	create_timer(300.0).timeout.connect(func() -> void:
		print("CARRY_SHOTS FAIL watchdog")
		quit(3))
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await process_frame
	FI = load("res://scripts/fight/fight_input.gd")
	var game: Node = root.get_node("Game")
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	game.session.begin("training")
	game.session.players[0]["fighter"] = 10004
	game.session.players[1]["fighter"] = 10005
	await game.go("fight", {}, "cut")
	screen = game.stack.back()
	screen.set_physics_process(false)
	screen.phase = "fight"
	screen.hud.visible = false
	states = screen.f1.get_script().S
	for f in screen.fighters:
		f.set_process(false)
	var out := _env("OUT", ProjectSettings.globalize_path("res://export/carry_shots"))
	DirAccess.make_dir_recursive_absolute(out)
	var only := _env("WHO", "")
	for att in [screen.f1, screen.f2]:
		var who := String(att.data["key"])
		if only != "" and only != who:
			continue
		var def: Node = att.foe
		if OS.get_environment("FRONT") != "" and att.moves["throw"].has("carry"):
			att.moves["throw"]["carry"]["front"] = OS.get_environment("FRONT") == "1"
		for face in [1, -1]:
			if not att.moves["throw"].has("carry"):
				continue
			var at := _plan(att, def, face)
			_place(att, def, face)
			for c in screen.fx_layer.get_children():
				if c.name != "Particles":
					c.queue_free()
			screen.fx_layer.visible = OS.get_environment("FX") != ""
			att.view.sd_actor.blending = true
			def.view.sd_actor.blending = true
			for k in 6:
				att.view.step(1.0 / 60.0)
				def.view.step(1.0 / 60.0)
			att._start_move("throw")
			var n := 0
			for i in 260:
				screen._tick_fight(false)
				att.view.step(1.0 / 60.0)
				def.view.step(1.0 / 60.0)
				for label in LABELS:
					if at.get(label, -2) == i:
						n += 1
						await _shoot(out, who, face, n, label, i, att, def)
				if i >= int(at.get("down20", 0)):
					break
	print("CARRY_SHOTS done ", out)
	root.get_node("Bgm").stop()
	await create_timer(0.3).timeout
	quit(0)
