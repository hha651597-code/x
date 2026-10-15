extends Node2D
## Floor decoration drawn in world space: glowing arena-edge posts with a light barrier, haze outside the arena and the
## mirror images of the two fighters on the glossy floor. (The tiles / grid live in shaders/stage_floor.gdshader.)

const REFLECT_SHADER := preload("res://shaders/reflect_fade.gdshader")

var world: Node
var colors := {}
var _refl: Array = []
var _mats: Array = []

func _ready() -> void:
	for i in 2:
		var spr := Sprite2D.new()
		var m := ShaderMaterial.new()
		m.shader = REFLECT_SHADER
		spr.material = m
		spr.visible = false
		add_child(spr)
		_refl.append(spr)
		_mats.append(m)

func _process(_delta: float) -> void:
	if world == null or world.fighters.size() < 2:
		return
	var flip := Transform2D(Vector2(1, 0), Vector2(0, -1), Vector2(0.0, 2.0 * Arena.GROUND))
	for i in 2:
		var f: Fighter = world.fighters[i]
		var spr: Sprite2D = _refl[i]
		if not is_instance_valid(f) or not f.visible or f.body == null or f.body.texture == null or (f.view and f.view.get("rig_mode")):
			spr.visible = false
			continue
		var b: Sprite2D = f.body
		spr.visible = true
		spr.texture = b.texture
		spr.centered = b.centered
		spr.offset = b.offset
		spr.flip_h = b.flip_h
		spr.hframes = b.hframes
		spr.vframes = b.vframes
		spr.frame = b.frame
		spr.region_enabled = b.region_enabled
		spr.region_rect = b.region_rect
		spr.transform = flip * b.get_relative_transform_to_parent(world.world_root)
		(_mats[i] as ShaderMaterial).set_shader_parameter("dim", clampf(f.dim * 1.2, 0.3, 1.0))

func _draw() -> void:
	var y0 := Arena.GROUND - 24.0
	var acc := Color(1.0, 0.86, 0.35)
	var avg: Color = colors.get("avg", Color(0.5, 0.7, 0.95))
	var fog := Color(avg.r * 0.35, avg.g * 0.45, avg.b * 0.7, 0.0)
	for sx in [-1.0, 1.0]:
		var x := float(sx) * (Arena.HALF_W + 100.0)
		# haze outside the arena
		var xo := x + float(sx) * 1500.0
		var fog_in := Color(fog.r, fog.g, fog.b, 0.0)
		var fog_out := Color(fog.r, fog.g, fog.b, 0.5)
		draw_polygon(PackedVector2Array([Vector2(x, y0 - 900.0), Vector2(xo, y0 - 900.0), Vector2(xo, y0 + 700.0), Vector2(x, y0 + 700.0)]), PackedColorArray([fog_in, fog_out, fog_out, fog_in]))
		# light barrier panel rising from the post
		var top := Color(1, 1, 1, 0.0)
		var low := Color(1.0, 0.95, 0.75, 0.30)
		draw_polygon(PackedVector2Array([Vector2(x, y0 - 250.0), Vector2(x - float(sx) * 70.0, y0 - 250.0), Vector2(x - float(sx) * 70.0, y0 + 30.0), Vector2(x, y0 + 30.0)]), PackedColorArray([top, top, low, Color(1.0, 0.95, 0.75, 0.5)]))
		# glossy post
		draw_line(Vector2(x, y0 + 32.0), Vector2(x, y0 - 250.0), Color(1, 1, 1, 0.9), 5.0, true)
		draw_line(Vector2(x, y0 + 32.0), Vector2(x, y0 - 90.0), acc, 5.0, true)
		# cap diamond
		var cap := PackedVector2Array([Vector2(x, y0 - 268.0), Vector2(x + 9.0, y0 - 250.0), Vector2(x, y0 - 232.0), Vector2(x - 9.0, y0 - 250.0)])
		draw_colored_polygon(cap, acc)
		var loop := PackedVector2Array(cap)
		loop.append(cap[0])
		draw_polyline(loop, Color.WHITE, 2.5, true)
		# floor glow under the post
		draw_set_transform(Vector2(x, y0 + 34.0), 0.0, Vector2(1.0, 0.22))
		draw_circle(Vector2.ZERO, 80.0, Color(1.0, 0.9, 0.5, 0.20))
		draw_circle(Vector2.ZERO, 44.0, Color(1.0, 0.95, 0.7, 0.30))
		draw_set_transform_matrix(Transform2D.IDENTITY)
