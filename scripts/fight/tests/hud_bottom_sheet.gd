extends SceneTree
## Captures of the bottom row over a real training fight, 1280x720, into tmp/hud_bottom_<name>.png.
## Run: zsh tools/hud_bottom_sheet.sh
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

const OUT := "res://tmp/hud_bottom_"

var screen: Node
var bottom: Control
var f1: Node
var f2: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		print("HUD_BOTTOM_SHEET FAIL watchdog timeout")
		quit(3))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tmp"))
	await process_frame
	var game: Node = root.get_node("Game")
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	game.session.begin("training")
	game.session.players[0]["fighter"] = 10004
	game.session.players[1]["fighter"] = 10005
	game.session.players[0]["special"] = 20001
	game.session.players[1]["special"] = 23005
	root.get_node("Dbg").intro_entry = false     # the 300 tick entry intro would hide the idle picture these checks need
	await game.go("fight", {}, "cut")
	screen = game.stack.back()
	screen.set_physics_process(false)
	screen.phase = "fight"
	screen.hud.visible = false
	screen.hud.process_mode = Node.PROCESS_MODE_DISABLED
	f1 = screen.f1
	f2 = screen.f2
	bottom = (load("res://scripts/fight/hud_bottom.gd") as GDScript).new()
	screen.add_child(bottom)
	bottom.z_index = 100
	bottom.setup(screen)
	await _frames(20)
	for m in [0.0, 20.0, 50.0, 90.0, 100.0]:
		_state(m, m, 0, 0)
		await _frames(1 if m < 50.0 else 14)
		_save("meter_%d" % int(m))
	_state(35.0, 100.0, 0, 0)
	await _frames(6)
	_save("meter_35_100")
	_state(0.0, 0.0, 0, 0)
	await _frames(40)
	_state(50.0, 100.0, 0, 0)
	await _frames(1)
	_save("edge_super_ex")
	await _frames(5)
	_save("edge_super_ex_b")
	await _frames(8)
	_save("edge_super_ex_c")
	_state(60.0, 20.0, 0, 90)
	await _frames(40)
	_save("assist_ready_and_cooling")
	_state(60.0, 60.0, 0, 0)
	await _frames(40)
	f1.position.x = -Arena.HALF_W + 110.0
	screen._apply_camera()
	bottom.callout(f1)
	bottom.callout(f2)
	var t0: float = bottom._time
	for t in [0.05, 0.12, 0.3, 0.8, 1.3, 1.6]:
		await _until(t0 + t)
		_save("callout_%03d" % roundi(t * 100.0))
	_state(60.0, 60.0, 0, 0)
	f1.assist_data = {}
	f1.assist = {}
	await _frames(20)
	_save("no_assist_p1")
	f2.assist_data = {}
	f2.assist = {}
	await _frames(20)
	_save("no_assist_both")
	quit(0)

func _until(t: float) -> void:
	while bottom._time < t:
		await process_frame

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _state(m1: float, m2: float, cd1: int, cd2: int) -> void:
	f1.meter = m1
	f2.meter = m2
	f1.assist_cd = cd1
	f2.assist_cd = cd2

func _save(name: String) -> void:
	var img: Image = root.get_texture().get_image()
	var err := img.save_png(OUT + name + ".png")
	print("saved ", name, " ", img.get_size(), " ", error_string(err))
	if err != OK:
		print("HUD_BOTTOM_SHEET FAIL could not save ", name)
		quit(1)
