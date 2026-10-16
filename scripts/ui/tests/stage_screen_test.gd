extends SceneTree
## The stage + BGM overlay: Back restores the BGM and the select re-opens its special panels, Confirm writes the stage
## and jumps to the VS screen, and the "?" roulette lands on a real stage before it jumps.
## Run: TEST=res://scripts/ui/tests/stage_screen_test.gd MAXLINES=200 zsh tools/sd_test.sh   (a real small window)

class StubTransition extends Node:
	var styles: Array = []
	var cover_all := false
	func play(style: String, _opts: Dictionary, on_cover: Callable) -> void:
		if style != "cut":
			styles.append(style)
		if style == "cut" or cover_all:
			on_cover.call()

const DT := 1.0 / 60.0

var checks := 0
var failures: Array = []
var game: Node
var stub: StubTransition
var real_transition: Node
var stages: GDScript

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("STAGE_SCREEN_CHECK FAIL ", label)
		failures.append(label)

func _run() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		print("STAGE_SCREEN_TEST FAIL watchdog timeout")
		quit(3))
	await process_frame
	game = root.get_node("Game")
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	real_transition = game.transition
	stub = StubTransition.new()
	root.add_child(stub)
	game.transition = stub
	stages = load("res://scripts/core/stages.gd")
	await _back()
	await _confirm()
	await _roulette()
	game.transition = real_transition
	print("STAGE_SCREEN_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _session() -> void:
	var s = game.session
	s.begin("versus2p")
	for i in 2:
		s.players[i]["claimed"] = true
		s.players[i]["device"] = "kb1" if i == 0 else "kb2"
		s.players[i]["locked"] = true
	s.players[0]["fighter"] = 10004
	s.players[1]["fighter"] = 10005
	s.players[0]["special"] = 10017
	s.players[1]["special"] = 10040
	s.stage = {}
	s.bgm = "auto"

func _tick(scr: Node, frames: int) -> void:
	for i in frames:
		scr._process(DT)

## Select screen with both players done, then the stage overlay pushed over it and past its input lock.
func _push_stage() -> Array:
	_session()
	stub.styles.clear()
	await game.go("select", {}, "cut")
	var sel: Node = game.current()
	sel.set_process(false)
	while not sel.probe()["entered"]:
		sel._process(DT)
	game.push("stage", {})
	var scr: Node = game.current()
	scr.set_process(false)
	_tick(scr, 30)
	return [sel, scr]

func _back() -> void:
	var pair := await _push_stage()
	var sel: Node = pair[0]
	var scr: Node = pair[1]
	check(game.current_name() == "stage" and sel.covered, "the stage overlay covers the select screen")
	scr.on_action("kb1", "rb")
	_tick(scr, 3)
	check(game.session.bgm == "pachad", "the BGM bar previews through the session")
	scr.on_action("kb2", "back")
	await process_frame
	check(game.current() == sel and not sel.covered, "back pops the overlay and uncovers the select screen")
	check(game.session.bgm == "auto", "back restores the BGM from before the overlay")
	var p: Dictionary = sel.probe()
	check(p["state"] == ["special", "special"] and not p["players"][0]["locked"], "both humans fall back to the special pick")
	_tick(sel, 30)
	p = sel.probe()
	check(p["panels"][0]["open"] and p["panels"][1]["open"], "the special panels re-open")

func _confirm() -> void:
	var pair := await _push_stage()
	var scr: Node = pair[1]
	stub.cover_all = true
	scr.on_action("kb1", "confirm")
	check(scr.probe()["leaving"] and game.session.stage.get("id", "") == stages.LIST[0]["id"], "confirm writes the stage to the session")
	_tick(scr, 30)
	check(game.current_name() == "vs" and stub.styles == ["fade"], "confirm jumps to the VS screen with the fade")
	stub.cover_all = false

func _roulette() -> void:
	var pair := await _push_stage()
	var scr: Node = pair[1]
	for row in 2:
		for _i in 12:
			if scr.probe()["stage"] == "random":
				break
			scr.on_action("kb1", "right")
			_tick(scr, 3)
		if scr.probe()["stage"] != "random":
			scr.on_action("kb1", "down")
			_tick(scr, 3)
	check(scr.probe()["stage"] == "random", "right reaches the random tile")
	stub.cover_all = true
	scr.on_action("kb1", "confirm")
	check(scr.probe()["roulette"] and game.session.stage.is_empty(), "confirm on the random tile starts the roulette, no stage yet")
	var n := 0
	while game.current_name() == "stage" and n < 400:
		scr._process(DT)
		n += 1
	check(game.current_name() == "vs", "the roulette locks a stage and jumps to the VS screen (%d frames)" % n)
	check(game.session.stage.get("id", "") in stages.LIST.map(func(s): return s["id"]), "the roulette lands on a real stage, not the random tile")
	stub.cover_all = false
