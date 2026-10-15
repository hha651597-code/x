class_name Screen
extends Control
## Base of every screen. Game instantiates the script, adds it to the host, then calls enter().
## Screens never reference each other: they call Game.go / push / pop / back and read Game.session.
##
##   enter(params, info)  build + start the entrance. info = {overlay: bool, back: bool, from: String}
##   exit()               just before the screen is freed
##   on_action(dev, act)  a logical input from Controls (see controls.gd); only called when active
##   set_covered(b)       an overlay was pushed over (true) / popped (false); stop reacting while covered
##   probe()              JSON-able state for the debug harness

var params := {}
var covered := false
var screen_name := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func enter(_params: Dictionary, _info: Dictionary) -> void:
	pass

func exit() -> void:
	pass

func on_action(_dev: String, _act: String) -> void:
	pass

func set_covered(b: bool) -> void:
	covered = b

func probe() -> Dictionary:
	return {}
