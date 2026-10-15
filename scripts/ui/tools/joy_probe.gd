extends SceneTree
## Prints what Godot knows about each connected pad: name, guid, is_joy_known and every joy info key with its type. Run it once per
## platform with a real pad (a window opens): godot --path . --script res://scripts/ui/tools/joy_probe.gd
## The values feed ControllerGlyphs.classify; nothing here has been checked on real hardware yet.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await create_timer(1.0).timeout
	var ids := Input.get_connected_joypads()
	print("PROBE pads=", ids, " os=", OS.get_name(), " ver=", Engine.get_version_info().string)
	for id in ids:
		print("PROBE pad", id, " name=", Input.get_joy_name(id), " guid=", Input.get_joy_guid(id), " known=", Input.is_joy_known(id))
		var info := Input.get_joy_info(id)
		for k in info:
			print("PROBE   ", k, " = ", info[k], " (", type_string(typeof(info[k])), ")")
		print("PROBE   family=", ControllerGlyphs.classify(info, Input.get_joy_name(id)))
	quit(0)
