extends SceneTree
## Captures of the top rail (hud_top.gd) on a real training fight, at 1280x720: round start, mid-fight, low HP with its ghost,
## guard low and crushed, the last ten seconds, the training plate, a long name, plus a contact sheet against a reference
## mockup. The module reads a stub world, so every state is set by hand; the stage and the fighters behind are real.
## Run (a real window, never headless):
##   Godot --path . --resolution 1280x720 --position 40,40 --script res://scripts/fight/tests/hud_top_sheet.gd
## Env: HUD_OUT (default /tmp/ba-hud-out/top), HUD_MOCKUP (a mockup png to compare against, optional).

const OUT_DEFAULT := "/tmp/ba-hud-out/top"
const MOCKUP_DEFAULT := ""

class StubFighter extends RefCounted:
	var data: Dictionary
	var hp := 1000.0
	var max_hp := 1000.0
	var stats := {"guard_max": 100.0, "guard_crush": 60.0}
	var guard := 100.0
	var crush_t := 0
	var state := 0
	var powered := false
	var armor_hits_left := 0
	var move := {}
	var mf := 0
	var kv := {}

class StubWorld extends Node:
	var fighters: Array = []
	var timer_frames := 3600
	var training := false
	var mode := "versus2p"
	var wins := [0, 0]
	var phase := "fight"
	var round_no := 1

var out := OUT_DEFAULT
var screen: Node
var world: StubWorld
var top: Control
var a: StubFighter
var b: StubFighter
var shots := {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(180.0).timeout.connect(func() -> void:
		print("HUD_TOP_SHEET FAIL watchdog timeout")
		quit(3))
	await process_frame
	out = OS.get_environment("HUD_OUT") if OS.get_environment("HUD_OUT") != "" else OUT_DEFAULT
	DirAccess.make_dir_recursive_absolute(out)
	var game: Node = root.get_node("Game")
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	game.session.begin("training")
	game.session.players[0]["fighter"] = 10004
	game.session.players[1]["fighter"] = 10005
	root.get_node("Dbg").intro_entry = false     # the 300 tick entry intro would hide the idle picture these checks need
	await game.go("fight", {}, "cut")
	screen = game.stack.back()
	screen.set_physics_process(false)
	screen.phase = "fight"
	(screen.hud as Control).visible = false
	world = StubWorld.new()
	screen.add_child(world)
	a = StubFighter.new()
	b = StubFighter.new()
	a.data = (screen.f1.data as Dictionary).duplicate()
	b.data = (screen.f2.data as Dictionary).duplicate()
	world.fighters = [a, b]
	top = load("res://scripts/fight/hud_top.gd").new().setup(world)
	top.z_index = 100
	screen.add_child(top)
	await _frames(8)

	await _shot("start")
	b.data["name"] = "Hoshino"
	world.wins = [1, 0]
	world.round_no = 2
	a.hp = 720.0
	b.hp = 550.0
	a.guard = 80.0
	b.guard = 25.0
	a.kv = {"mag": 31}
	a.powered = true
	b.state = 7
	await _frames(40)
	await _shot("mid")
	a.hp = 180.0
	await _frames(14)
	await _shot("lowhp_ghost")
	a.hp = 1000.0
	b.hp = 1000.0
	a.guard = 20.0
	b.guard = 100.0
	b.crush_t = 36
	b.powered = false
	b.state = 0
	await _frames(40)
	await _shot("guard_low_crush")
	b.crush_t = 0
	a.hp = 160.0
	b.hp = 1000.0
	a.guard = 100.0
	b.guard = 30.0
	b.crush_t = 20
	await _frames(40)
	await _shot("lowhp_and_crush")
	a.hp = 1000.0
	b.hp = 200.0
	a.crush_t = 24
	b.crush_t = 0
	b.guard = 100.0
	await _frames(40)
	await _shot("crush_p1_lowhp_p2")
	a.crush_t = 0
	a.hp = 150.0
	b.hp = 1000.0
	top.anchor_outer = false
	await _frames(40)
	await _shot("lowhp_vs_anchor")
	top.anchor_outer = true
	a.hp = 1000.0
	world.timer_frames = 540
	world.wins = [1, 1]
	top._time = 0.0
	await _shot("last10_a")
	top._time = 0.34
	await _shot("last10_b")
	world.wins = [0, 0]
	world.timer_frames = 3600
	world.training = true
	world.mode = "training"
	await _frames(6)
	await _shot("training")
	world.training = false
	world.mode = "versus2p"
	a.data["name"] = "Hinakamishimoyama-Nakajima Prefect"
	b.data["name"] = "Hoshino Takanashi of Abydos"
	await _frames(6)
	await _shot("longname")
	top.visible = false
	var real: Control = load("res://scripts/fight/hud_top.gd").new().setup(screen)
	real.z_index = 100
	screen.add_child(real)
	screen.f1.hp = 640.0
	screen.f2.hp = 880.0
	await _frames(40)
	await _shot("real_world")
	_contact()
	print("HUD_TOP_SHEET done ", shots.keys())
	quit(0)

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _shot(name: String) -> void:
	await _frames(2)
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name])
	shots[name] = img

func _contact() -> void:
	var mock_path := OS.get_environment("HUD_MOCKUP") if OS.get_environment("HUD_MOCKUP") != "" else MOCKUP_DEFAULT
	var mock := Image.load_from_file(mock_path)
	if mock == null or not shots.has("mid"):
		return
	var sheet := Image.create(2560, 360, false, Image.FORMAT_RGBA8)
	var mid: Image = shots["mid"]
	mock.convert(Image.FORMAT_RGBA8)
	mid.convert(Image.FORMAT_RGBA8)
	sheet.blit_rect(mock, Rect2i(0, 0, 1280, 360), Vector2i(0, 0))
	sheet.blit_rect(mid, Rect2i(0, 0, 1280, 360), Vector2i(1280, 0))
	sheet.save_png("%s/contact_top.png" % out)
