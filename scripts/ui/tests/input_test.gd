extends SceneTree
## Controls and Session.device_of: input sources, repeat latching, focus loss, pad disconnect, a missing claimed pad.
## Run: TEST=res://scripts/ui/tests/input_test.gd zsh tools/sd_test.sh   (a real small window)
## Drives a private Controls instance by hand (events and _process), so the live autoload and its keys are untouched.

var checks := 0
var failures: Array = []
var C: Node
var got: Array = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("INPUT_CHECK FAIL ", label)
		failures.append(label)

func _key(code: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code as Key
	e.pressed = down
	C._input(e)

func _btn(dev: int, b: int, down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = dev
	e.button_index = b as JoyButton
	e.pressed = down
	C._input(e)

func _stick(dev: int, axis: int, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = dev
	e.axis = axis as JoyAxis
	e.axis_value = v
	C._input(e)

func _count(tag: String) -> int:
	return got.count(tag)

func _run() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		print("INPUT_TEST FAIL watchdog timeout")
		quit(3))
	await process_frame
	C = load("res://scripts/core/controls.gd").new()
	C.action.connect(func(dev: String, act: String) -> void: got.append(dev + ":" + act))
	_repeat()
	_sources()
	_focus()
	_disconnect()
	_device_of()
	C.free()
	await _router()
	print("INPUT_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _repeat() -> void:
	got.clear()
	_key(KEY_S, true)
	for i in 30:
		C._process(0.05)
	check(_count("kb1:down") > 3, "a held direction auto-repeats (%d)" % _count("kb1:down"))
	C.latch_repeats()
	var n := _count("kb1:down")
	for i in 60:
		C._process(0.05)
	check(_count("kb1:down") == n, "a latched direction stops repeating")
	check(C.is_held("kb1", "down"), "a latched direction is still held")
	_key(KEY_S, false)
	check(not C.is_held("kb1", "down"), "releasing a latched direction clears it")
	_key(KEY_S, true)
	check(_count("kb1:down") == n + 1, "the next press emits again")
	for i in 30:
		C._process(0.05)
	check(_count("kb1:down") > n + 2, "and repeats again after the release")
	_key(KEY_S, false)

func _sources() -> void:
	got.clear()
	_btn(0, JOY_BUTTON_DPAD_RIGHT, true)
	_stick(0, JOY_AXIS_LEFT_X, 1.0)
	_stick(0, JOY_AXIS_LEFT_X, 0.0)
	check(C.is_held("pad0", "right"), "releasing the stick keeps a held d-pad")
	_btn(0, JOY_BUTTON_DPAD_RIGHT, false)
	check(not C.is_held("pad0", "right"), "releasing the d-pad ends it")
	_key(KEY_ENTER, true)
	_key(KEY_SLASH, true)
	_key(KEY_ENTER, false)
	check(C.is_held("kb2", "confirm"), "releasing Enter keeps a held slash")
	_key(KEY_SLASH, false)
	check(not C.is_held("kb2", "confirm"), "releasing slash ends it")
	check(_count("kb2:confirm") == 1, "two keys on one action emit one confirm")

func _focus() -> void:
	got.clear()
	_stick(1, JOY_AXIS_LEFT_X, 1.0)
	C.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not C.is_held("pad1", "right"), "focus loss clears held keys")
	_stick(1, JOY_AXIS_LEFT_X, 1.0)
	check(_count("pad1:right") == 2, "a stick still deflected after focus returns presses again (%d)" % _count("pad1:right"))
	_stick(1, JOY_AXIS_LEFT_X, 0.0)

func _disconnect() -> void:
	_stick(2, JOY_AXIS_LEFT_Y, 1.0)
	_btn(2, JOY_BUTTON_A, true)
	_key(KEY_D, true)
	C._on_joy_connection(2, false)
	check(not C.is_held("pad2", "down") and not C.is_held("pad2", "confirm"), "an unplugged pad holds nothing")
	check(C.is_held("kb1", "right"), "other devices keep their keys")
	_key(KEY_D, false)
	got.clear()
	_stick(2, JOY_AXIS_LEFT_Y, 1.0)
	check(_count("pad2:down") == 1, "a pad that comes back starts from neutral")
	C._on_joy_connection(2, false)

func _device_of() -> void:
	var S: GDScript = load("res://scripts/core/session.gd")
	var s = S.new()
	s.begin("versus2p")
	s.players[0].merge({"claimed": true, "device": "kb2"}, true)
	s.players[1].merge({"claimed": true, "device": "kb1"}, true)
	check(s.device_of(1) == "kb2" and s.device_of(2) == "kb1", "claimed keyboards swap sides")
	s.players[0].merge({"device": "pad99"}, true)
	s.players[1].merge({"device": "kb2"}, true)
	check(s.device_of(1) == "kb1", "a claimed pad that is not connected falls back to the slot's keyboard")
	check(s.controls("kb1", 1) and not s.controls("pad99", 1), "and the slot answers to that keyboard")
	check(s.device_of(2) == "kb2", "a claimed keyboard stays as claimed")
	s.players[1].merge({"device": "kb1"}, true)
	check(s.device_of(1) == "kb2" and s.device_of(2) == "kb1", "the fallback skips a keyboard the other player claimed")
	s.players[1].merge({"device": "pad98"}, true)
	check(s.device_of(1) == "kb1" and s.device_of(2) == "kb2", "two lost pads get one keyboard each")

## Game._swap, push and pop latch whatever is held, so it cannot repeat into the next screen.
func _router() -> void:
	var host := Control.new()
	root.add_child(host)
	var game: Node = root.get_node("Game")
	var ctl: Node = root.get_node("Controls")
	game.host = host
	var held := func() -> float: return ctl._held["kb1:down"]
	game.start("menu")
	ctl.set_held("kb1", "down", true)
	game.push("options")
	check(held.call() < 0.0, "push latches a held direction")
	ctl.set_held("kb1", "down", true)
	game.pop()
	check(held.call() < 0.0, "pop latches a held direction")
	ctl.set_held("kb1", "down", true)
	game._swap("menu", {}, {"from": "", "back": false})
	check(held.call() < 0.0, "a screen swap latches a held direction")
	ctl.set_held("kb1", "down", false)
	for s in game.stack:
		s.exit()
		s.queue_free()
	game.stack.clear()
	host.queue_free()
