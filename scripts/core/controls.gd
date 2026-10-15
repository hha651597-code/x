extends Node
## One input path for every screen. Turns keyboard clusters and gamepads into logical actions
## per DEVICE and emits `action(device, name)` on press (directions also auto-repeat).
##
##   actions : up down left right confirm back aux aux2 lb rb start
##   devices : "kb1"  left-hand cluster   W A S D · F confirm · G back · R aux · T aux2 · Q/E shoulders
##             "kb2"  right-hand cluster  arrows · Enter or / confirm · Backspace/Right-Shift back
##                                        · ; aux · ' aux2 · , . shoulders
##             "pad0".."pad7" gamepads    d-pad / left stick · A confirm · B back · X aux · Y aux2 · LB/RB
##             "shared"  Space = confirm, Escape = back, Tab = start (single-player contexts only)
##   Screens decide who may act: single-player screens accept every device; versus screens accept
##   only the device bound to that player's slot (Game.session.device_of(slot)).

signal action(device: String, name: String)

const REPEAT_DELAY := 0.34
const REPEAT_RATE := 0.085
const DIRS := ["up", "down", "left", "right", "lb", "rb"]

const KB1 := {
	KEY_W: "up", KEY_S: "down", KEY_A: "left", KEY_D: "right",
	KEY_F: "confirm", KEY_G: "back", KEY_R: "aux", KEY_T: "aux2",
	KEY_Q: "lb", KEY_E: "rb", KEY_V: "start",
}
const KB2 := {
	KEY_UP: "up", KEY_DOWN: "down", KEY_LEFT: "left", KEY_RIGHT: "right",
	KEY_ENTER: "confirm", KEY_KP_ENTER: "confirm", KEY_KP_0: "confirm", KEY_SLASH: "confirm",
	KEY_BACKSPACE: "back", KEY_KP_1: "back",
	KEY_SEMICOLON: "aux", KEY_KP_2: "aux", KEY_APOSTROPHE: "aux2", KEY_KP_3: "aux2",
	KEY_COMMA: "lb", KEY_KP_4: "lb", KEY_PERIOD: "rb", KEY_KP_6: "rb", KEY_KP_5: "start",
}
const SHARED := {KEY_SPACE: "confirm", KEY_ESCAPE: "back", KEY_TAB: "start"}

const PAD_BUTTONS := {
	JOY_BUTTON_A: "confirm", JOY_BUTTON_B: "back", JOY_BUTTON_X: "aux", JOY_BUTTON_Y: "aux2",
	JOY_BUTTON_LEFT_SHOULDER: "lb", JOY_BUTTON_RIGHT_SHOULDER: "rb", JOY_BUTTON_START: "start",
	JOY_BUTTON_DPAD_UP: "up", JOY_BUTTON_DPAD_DOWN: "down", JOY_BUTTON_DPAD_LEFT: "left", JOY_BUTTON_DPAD_RIGHT: "right",
}

var enabled := true
var _held := {}          # "dev:act" -> seconds held
var _src := {}           # "dev:act" -> {physical source: true}, so one source letting go keeps the action held
var _axis := {}          # "dev:axis" -> -1 / 0 / 1
var log: Array = []      # last actions, for the debug probe

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_joy_connection)

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.echo:
			return
		var code := k.physical_keycode
		var found := _lookup_key(code, k)
		if found.is_empty():
			return
		if k.pressed:
			_press(found[0], found[1], code)
		else:
			_release(found[0], found[1], code)
	elif event is InputEventJoypadButton:
		var b := event as InputEventJoypadButton
		if PAD_BUTTONS.has(b.button_index):
			var dev := "pad%d" % b.device
			if b.pressed:
				_press(dev, PAD_BUTTONS[b.button_index], b.button_index)
			else:
				_release(dev, PAD_BUTTONS[b.button_index], b.button_index)
	elif event is InputEventJoypadMotion:
		var m := event as InputEventJoypadMotion
		if m.axis == JOY_AXIS_LEFT_X or m.axis == JOY_AXIS_LEFT_Y:
			var dev := "pad%d" % m.device
			var key := "%s:%d" % [dev, m.axis]
			var now := 0
			if m.axis_value > 0.55:
				now = 1
			elif m.axis_value < -0.55:
				now = -1
			var before: int = _axis.get(key, 0)
			if now != before:
				var neg := "left" if m.axis == JOY_AXIS_LEFT_X else "up"
				var pos := "right" if m.axis == JOY_AXIS_LEFT_X else "down"
				if before == -1: _release(dev, neg, key)
				if before == 1: _release(dev, pos, key)
				_axis[key] = now
				if now == -1: _press(dev, neg, key)
				if now == 1: _press(dev, pos, key)

func _lookup_key(code: int, k: InputEventKey) -> Array:
	if KB1.has(code):
		return ["kb1", KB1[code]]
	if KB2.has(code):
		return ["kb2", KB2[code]]
	if code == KEY_SHIFT and int(k.get("location")) == KEY_LOCATION_RIGHT:
		return ["kb2", "back"]
	if SHARED.has(code):
		return ["shared", SHARED[code]]
	return []

func _press(dev: String, act: String, src: Variant) -> void:
	if not enabled:
		return
	var key := dev + ":" + act
	if not _src.has(key):
		_src[key] = {}
	_src[key][src] = true
	if _held.has(key):
		return
	_held[key] = 0.0
	_emit(dev, act)

func _release(dev: String, act: String, src: Variant) -> void:
	var key := dev + ":" + act
	var srcs: Dictionary = _src.get(key, {})
	srcs.erase(src)
	if srcs.is_empty():
		_held.erase(key)
		_src.erase(key)

func _emit(dev: String, act: String) -> void:
	log.append("%s:%s" % [dev, act])
	if log.size() > 12:
		log.pop_front()
	action.emit(dev, act)

func _process(delta: float) -> void:
	if not enabled:
		return
	for key in _held.keys():
		var act: String = key.get_slice(":", 1)
		if act not in DIRS:
			continue
		var before: float = _held[key]
		var t := before + delta
		_held[key] = t
		if t > REPEAT_DELAY:
			var n0 := int(floor((before - REPEAT_DELAY) / REPEAT_RATE)) if before > REPEAT_DELAY else -1
			var n1 := int(floor((t - REPEAT_DELAY) / REPEAT_RATE))
			if n1 > n0:
				_emit(key.get_slice(":", 0), act)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_held.clear()
		_src.clear()
		_axis.clear()

## A pad that left holds nothing: its keys and stick state go, so no direction stays stuck.
func _on_joy_connection(id: int, connected: bool) -> void:
	ControllerGlyphs.forget()
	if connected:
		return
	var prefix := "pad%d:" % id
	for d: Dictionary in [_held, _src, _axis]:
		for key in d.keys():
			if key.begins_with(prefix):
				d.erase(key)

## Held directions stop auto-repeating until released. Called when the screen changes, so a key held through
## a transition does not scroll or toggle on the next screen.
func latch_repeats() -> void:
	for key in _held:
		_held[key] = -1.0e9

## Is this action currently held on that device?
func is_held(dev: String, act: String) -> bool:
	return _held.has(dev + ":" + act)

## Hold / release an action programmatically (debug harness, scripted tests).
func set_held(dev: String, act: String, on: bool) -> void:
	if on:
		_held[dev + ":" + act] = 0.0
	else:
		_held.erase(dev + ":" + act)
		_src.erase(dev + ":" + act)

## Synthesize a press (debug harness, mouse clicks that act as confirm).
func inject(dev: String, act: String) -> void:
	_emit(dev, act)

## Which devices exist right now (keyboard clusters are always there).
func devices() -> Array:
	var out := ["kb1", "kb2"]
	for id in Input.get_connected_joypads():
		out.append("pad%d" % id)
	return out

## The picture for a device's action: the pad's own family glyph, or the keyboard key. null when there is none,
## and label_for is the fallback.
func glyph_for(dev: String, act: String) -> Texture2D:
	if dev.begins_with("pad"):
		return ControllerGlyphs.texture(ControllerGlyphs.family_of(dev), act)
	return ControllerGlyphs.key_glyph(dev, act)

## Prompt text for a device's action ("F", "Enter", "A").
func label_for(dev: String, act: String) -> String:
	if dev.begins_with("pad"):
		return {"confirm": "A", "back": "B", "aux": "X", "aux2": "Y", "lb": "LB", "rb": "RB", "dpad": "D-pad", "stick_l": "L-stick", "start": "Start"}.get(act, act)
	if dev == "kb1":
		return {"confirm": "F", "back": "G", "aux": "R", "aux2": "T", "lb": "Q", "rb": "E"}.get(act, act)
	if dev == "kb2":
		return {"confirm": "Enter", "back": "Bksp", "aux": ";", "aux2": "'", "lb": ",", "rb": "."}.get(act, act)
	return {"confirm": "Space", "back": "Esc"}.get(act, act)
