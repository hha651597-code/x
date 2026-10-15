extends SceneTree
## HUD captures at 1280x720: pause (training, versus, long label), the result screen (win and lose, P1 and P2 side) and the
## training overlay. A real fight stands behind; the facade's old drawing is hidden so only the new modules show.
## Run: HUD_MENUS_OUT=/path/ HUD_MENUS_SHOTS=pause,result,training zsh tools/hud_menus_shots.sh   (a real window, never headless)

class StubWorld extends Node:
	var training := false
	var round_no := 2

class StubHud extends Control:
	var world: Node
	var items: Array = []
	var _time := 0.0
	var _paused := true
	func pause_items() -> Array:
		return items
	func pause_activate(_i: int) -> void:
		pass

var game: Node
var screen: Node
var hud: Control
var out := "/tmp/ba-hud-out/menus/"
var FI: GDScript

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(240.0).timeout.connect(func() -> void: quit(3))
	var o := OS.get_environment("HUD_MENUS_OUT")
	if o != "":
		out = o
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	FI = load("res://scripts/fight/fight_input.gd")
	game = root.get_node("Game")
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	var which := OS.get_environment("HUD_MENUS_SHOTS").split(",")
	if "pause" in which:
		await _pause()
	if "result" in which:
		await _result()
	if "training" in which:
		await _training()
	print("HUD_MENUS_SHOTS done")
	quit(0)

func _wait(sec: float) -> void:
	await create_timer(sec).timeout

func _shot(name: String) -> void:
	for i in 3:
		await process_frame
	root.get_texture().get_image().save_png(out + name + ".png")

func _fight(mode: String) -> void:
	game.session.begin(mode)
	game.session.players[0]["fighter"] = 10004
	game.session.players[1]["fighter"] = 10005
	root.get_node("Dbg").intro_entry = false     # the 300 tick entry intro would hide the idle picture these checks need
	await game.go("fight", {}, "cut")
	screen = game.stack.back()
	hud = screen.hud
	await _wait(2.2)
	screen.set_physics_process(false)
	for ch in hud.get_children():
		if ch != hud._pause and ch != hud._train:
			ch.visible = false

func _pause() -> void:
	await _fight("training")
	screen.set_paused(true)
	await _wait(1.4)
	await _shot("pause_training_resume")
	hud._pause.select(4)
	screen.infinite_meter = true
	await _wait(1.4)
	await _shot("pause_training_toggle")
	screen.set_paused(false)
	await _fight("versus2p")
	screen.set_paused(true)
	await _wait(1.4)
	await _shot("pause_versus")
	screen.set_paused(false)
	var stub := StubHud.new()
	stub.world = StubWorld.new()
	stub.world.training = true
	stub.items = [
		{"id": "resume", "label": "Resume", "value": ""},
		{"id": "restart", "label": "Reset Positions", "value": ""},
		{"id": "dummy", "label": "Dummy Behaviour During Combo Practice", "value": "Crouch"},
		{"id": "select", "label": "Return To Character Select And Pick Again", "value": ""},
		{"id": "menu", "label": "Main Menu", "value": ""},
	]
	stub.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stub.z_index = 120
	screen.add_child(stub)
	stub.add_child(stub.world)
	var p: Control = load("res://scripts/fight/hud_pause.gd").new().setup(stub)
	stub.add_child(p)
	p.open()
	p.select(2, false)
	await _wait(1.4)
	await _shot("pause_long_label")
	stub.queue_free()

func _result() -> void:
	var stats := [{"damage": 1234.0, "combo": 9, "hits": 31}, {"damage": 800.0, "combo": 5, "hits": 22}]
	var cases := [
		["versus2p", 1, 0, "result_p1_win"],
		["versus2p", 2, 0, "result_p2_win"],
		["versus-cpu", 1, 0, "result_cpu_you_win"],
		["arcade", 1, 1, "result_arcade_stage"],
		["arcade", 1, 4, "result_arcade_clear"],
		["arcade", 2, 1, "result_arcade_lost"],
	]
	for c in cases:
		game.session.begin(c[0])
		game.session.players[0]["fighter"] = 10004
		game.session.players[1]["fighter"] = 10005
		game.session.arcade_stage = c[2]
		var winner: int = c[1]
		var st := stats.duplicate(true)
		if winner == 2:
			st.reverse()
		await game.go("result", {"winner": winner, "wins": [2, 1] if winner == 1 else [1, 2], "rounds": 3, "stats": st}, "cut")
		await _wait(2.4)
		await _shot(c[3])
		if c[3] == "result_p1_win" or c[3] == "result_p2_win":
			game.stack.back().on_action("kb1", "down")
			await _wait(0.5)
			await _shot(c[3] + "_sel2")

func _training() -> void:
	await _fight("training")
	var tr: Control = hud._train
	var f1: Node = screen.f1
	screen.phase = "fight"
	tr.reset()
	var seq := [[0, 0, []], [1, 0, []], [1, 1, []], [0, 1, []], [1, 0, ["light"]], [0, 0, ["light"]], [0, 0, ["heavy"]],
			[-1, 0, ["skill", "dash"]], [0, -1, ["ex"]], [0, 0, ["assist"]]]
	var dur := [10, 12, 4, 3, 5, 3, 9, 6, 4, 2]
	await _wait(0.4)
	await _shot("training_empty")
	for i in seq.size():
		f1.input = FI.from_held(f1.input, seq[i][0], seq[i][1], seq[i][2])
		screen._frame += dur[i]
		tr.sample(screen)
	f1.input = FI.new()
	f1.stat_max_combo = 9
	tr.note_combo(8, 129.0, hud._time)
	await _wait(1.0)
	await _shot("training_tip")
	f1.stat_max_combo = 11
	tr.note_combo(11, 203.0, hud._time)
	await _wait(0.5)
	await _shot("training_best")
	await _wait(5.0)
	await _shot("training_after_tip")
