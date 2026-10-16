class_name Card
extends Control
## The house card (white rounded border + picture + shadow), optionally a parallelogram.
## A Control: position/size/scale/rotation/modulate work as usual; the look lives in
## shaders/card.gdshader. `size` is the card; the shadow/glow draw outside it (up to `margin` px).

const SHADER := preload("res://shaders/card.gdshader")

var mat: ShaderMaterial
var margin := 36.0
var dim_value := 1.0

func _init() -> void:
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	material = mat
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	resized.connect(_on_resized)

func _ready() -> void:
	pivot_offset = size * 0.5
	_on_resized()

func _on_resized() -> void:
	pivot_offset = size * 0.5
	mat.set_shader_parameter("card_size", size)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2(-margin, -margin), size + Vector2(margin, margin) * 2.0), Color.WHITE)

# configuration (chainable)
func setup(card_size: Vector2, radius := 18.0, border := 5.0) -> Card:
	size = card_size
	custom_minimum_size = card_size
	mat.set_shader_parameter("radius", radius)
	mat.set_shader_parameter("border", border)
	return self

func set_picture(tex: Texture2D, focus := Vector2(0.5, 0.5), zoom := 1.0) -> Card:
	mat.set_shader_parameter("use_pic", tex != null)
	if tex:
		mat.set_shader_parameter("pic", tex)
	mat.set_shader_parameter("focus", focus)
	mat.set_shader_parameter("zoom", zoom)
	return self

func set_fill(c: Color) -> Card:
	mat.set_shader_parameter("fill_color", c)
	return self

func set_shear(v: float) -> Card:
	mat.set_shader_parameter("shear", v)
	return self

func set_gloss(v: float) -> Card:
	mat.set_shader_parameter("gloss", v)
	return self

func set_shadow(amount: float, blur := 14.0, offset := Vector2(0, 6)) -> Card:
	mat.set_shader_parameter("shadow_amt", amount)
	mat.set_shader_parameter("shadow_blur", blur)
	mat.set_shader_parameter("shadow_off", offset)
	return self

func set_dim(v: float) -> Card:
	dim_value = v
	mat.set_shader_parameter("dim", v)
	return self

func set_tint(c: Color, amount: float) -> Card:
	mat.set_shader_parameter("tint", Color(c.r, c.g, c.b, amount))
	return self

func get_param(name: String) -> Variant:
	return mat.get_shader_parameter(name)

func set_param(name: String, value: Variant) -> void:
	mat.set_shader_parameter(name, value)
