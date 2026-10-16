extends Control
## Boot: creates the screen host + transition layer, hands them to Game and opens the title (the menu under a step file or a test).
## (The debug harness, scripts/core/dbg.gd, can start somewhere else with --screen=name.)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var host := Control.new()
	host.name = "ScreenHost"
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(host)
	var tr := preload("res://scripts/ui/transition.gd").new()
	tr.name = "Transition"
	add_child(tr)
	Game.host = host
	Game.transition = tr
	Game.start(Dbg.boot_screen(get_tree().current_scene == self))
	Dbg.ready_to_run.emit()
