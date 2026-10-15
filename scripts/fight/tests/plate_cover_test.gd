extends SceneTree

var checks := 0
var fails := 0


func _initialize() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		print("WATCHDOG timed out")
		quit(1))
	await process_frame
	var fx: Control = load("res://scripts/fight/stage_fx.gd").new()
	root.add_child(fx)
	fx.build({"id": "gehenna-night", "plate": "bg/BG_Gehenna_Collection.jpg"})
	for z: float in [0.7, 1.0, 1.24, 1.35, 1.45, 1.72, 1.8]:
		for cam_x: float in [-260.0, -200.0, 0.0, 200.0, 260.0]:
			for shake: Vector2 in [Vector2.ZERO, Vector2(7.0, -5.0), Vector2(-7.0, 5.0), Vector2(7.0, 5.0), Vector2(-7.0, -5.0)]:
				fx.update_camera(cam_x, z, shake, 636.0)
				var r := Rect2(fx.plate.position, fx.plate.size * fx.plate.scale)
				checks += 1
				if not (r.position.x <= 0.0 and r.position.y <= 0.0 and r.end.x >= 1280.0 and r.end.y >= 720.0):
					fails += 1
					print("FAIL the plate covers the screen at zoom %.2f, cam_x %.0f, shake %s: %s" % [z, cam_x, shake, r])
	print("PLATE_COVER_TEST %s checks=%d fails=%d" % ["PASS" if fails == 0 else "FAIL", checks, fails])
	quit(0 if fails == 0 else 1)
