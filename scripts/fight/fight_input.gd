class_name FightInput
extends RefCounted
## One fighter's intent for one simulation frame: a direction and a set of buttons, produced by a
## human (polling Controls) or by CpuBrain. The Fighter only ever reads this object.
##
##   x  -1 left / +1 right (screen space)      y  -1 up (jump) / +1 down (crouch)
##   buttons: light heavy skill ex assist dash   (held[] = down now, pressed[] = went down this frame)
##
## Human mapping (actions from controls.gd):  confirm = light   back = heavy   aux = skill
##   aux2 = ex   lb = assist   rb = dash   up/down/left/right = move / jump / crouch.

const BUTTONS := ["light", "heavy", "skill", "ex", "assist", "dash"]
const ACTION_TO_BUTTON := {"confirm": "light", "back": "heavy", "aux": "skill", "aux2": "ex", "lb": "assist", "rb": "dash"}

var x := 0
var y := 0
var held := {}
var pressed := {}

func _init() -> void:
	for b in BUTTONS:
		held[b] = false
		pressed[b] = false

func is_held(b: String) -> bool:
	return held.get(b, false)

func was_pressed(b: String) -> bool:
	return pressed.get(b, false)

func clear() -> void:
	x = 0
	y = 0
	for b in BUTTONS:
		held[b] = false
		pressed[b] = false

## Devices that drive `slot` this match.
static func devices_for(slot: int) -> Array:
	if Game.session.humans() == 1:
		if slot == 1:
			return Controls.devices()
		return []
	var d: String = Game.session.device_of(slot)
	if d == "" or d == "shared":
		d = "kb1" if slot == 1 else "kb2"
	return [d]

## Read the held state of a human slot; `prev` supplies the previous frame for edge detection.
static func read_human(slot: int, prev: FightInput) -> FightInput:
	var fi := FightInput.new()
	var devs := devices_for(slot)
	for d in devs:
		if Controls.is_held(d, "left"): fi.x -= 1
		if Controls.is_held(d, "right"): fi.x += 1
		if Controls.is_held(d, "up"): fi.y -= 1
		if Controls.is_held(d, "down"): fi.y += 1
		for act in ACTION_TO_BUTTON:
			if Controls.is_held(d, act):
				fi.held[ACTION_TO_BUTTON[act]] = true
	fi.x = clampi(fi.x, -1, 1)
	fi.y = clampi(fi.y, -1, 1)
	for b in BUTTONS:
		fi.pressed[b] = fi.held[b] and not (prev != null and prev.held[b])
	return fi

## Build the next frame from a held-set (used by CpuBrain / the harness).
static func from_held(prev: FightInput, nx: int, ny: int, btns: Array) -> FightInput:
	var fi := FightInput.new()
	fi.x = nx
	fi.y = ny
	for b in btns:
		fi.held[b] = true
	for b in BUTTONS:
		fi.pressed[b] = fi.held[b] and not (prev != null and prev.held[b])
	return fi
