extends Control
## A Control whose _draw is a Callable, for one-off glyphs (chevrons, the X button, key caps, icons)
## so a screen does not need a file per little shape.  Usage:
##   const Painter := preload("res://scripts/ui/painter.gd")
##   var g := Painter.new().setup(Vector2(24, 24), func(c: Control): c.draw_circle(c.size * 0.5, 10.0, Color.WHITE))
## Call g.queue_redraw() after changing whatever the painter reads.

var painter: Callable

func setup(sz: Vector2, fn: Callable) -> Control:
	size = sz
	custom_minimum_size = sz
	pivot_offset = sz * 0.5
	painter = fn
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	return self

func _draw() -> void:
	if painter.is_valid():
		painter.call(self)
