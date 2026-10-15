extends CanvasLayer
## Screen transitions. `await Game.transition.play(style, opts, on_cover)`:
## on_cover() runs once, while the old screen is fully hidden — that is where Game swaps screens.
## Styles:
##   "cut"    instant
##   "fade"   quick dip to dark
##   "crest"  school-crest wipe (crest_wipe.gd), opts {"crest": "red" | "gold" | "sakura"}, ~1.6 s
##   "slam"   fast diagonal white/colour slash (slam_wipe.gd), ~0.55 s, opts {"color": Color, "dir": 1.0}

signal finished

var _fade: ColorRect

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade = ColorRect.new()
	_fade.color = Color(0.02, 0.03, 0.06, 0.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)

func play(style: String, opts: Dictionary, on_cover: Callable) -> void:
	match style:
		"cut":
			on_cover.call()
		"crest":
			await _play_crest(opts, on_cover)
		"slam":
			await _play_slam(opts, on_cover)
		_:
			var t := create_tween()
			t.tween_property(_fade, "color:a", 1.0, 0.16)
			await t.finished
			on_cover.call()
			var t2 := create_tween()
			t2.tween_property(_fade, "color:a", 0.0, 0.2)
			await t2.finished
	finished.emit()

func _play_crest(opts: Dictionary, on_cover: Callable) -> void:
	var wipe := CrestWipe.new()
	add_child(wipe)
	await wipe.run(String(opts.get("crest", "red")), on_cover, float(opts.get("speed", 1.0)))
	wipe.queue_free()

func _play_slam(opts: Dictionary, on_cover: Callable) -> void:
	var wipe := SlamWipe.new()
	add_child(wipe)
	await wipe.run(on_cover, opts)
	wipe.queue_free()
