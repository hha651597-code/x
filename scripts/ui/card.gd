class_name Card
extends Control
## The house card (white rounded border + picture + shadow), optionally a parallelogram.
## A Control: position/size/scale/rotation/modulate work as usual; the look lives in
## shaders/card.gdshader. `size` is the CARD; the shadow/glow draw outside it (up to `margin` px).

const SHADER := preload("res://shaders/card.gdshader")
const YELLOW := UI.YELLOW
const WHITE := Color.WHITE

var mat: ShaderMaterial
var margin := 36.0
var highlighted := false
var dim_value := 1.0
var _hl := 0.0                      # animated 0..1 highlight amount
var _base_border := 5.0
var _hl_border := 8.0
var _border_color := WHITE
var _hl_color := YELLOW
var _tween: Tween

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

# ── configuration (chainable) ────────────────────────────────────────────────
func setup(card_size: Vector2, radius := 18.0, border := 5.0) -> Card:
	size = card_size
	custom_minimum_size = card_size
	_base_border = border
	_hl_border = border * 1.5
	mat.set_shader_parameter("radius", radius)
	mat.set_shader_parameter("border", border)
	_apply_highlight()
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

func set_border_colors(normal: Color, hl := YELLOW) -> Card:
	_border_color = normal
	_hl_color = hl
	_apply_highlight()
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

func set_glow(color: Color, amount: float, glow_size := 10.0) -> Card:
	mat.set_shader_parameter("glow_color", color)
	mat.set_shader_parameter("glow_amt", amount)
	mat.set_shader_parameter("glow_size", glow_size)
	return self

func set_dim(v: float) -> Card:
	dim_value = v
	mat.set_shader_parameter("dim", v)
	return self

func set_saturation(v: float) -> Card:
	mat.set_shader_parameter("saturation", v)
	return self

func set_tint(c: Color, amount: float) -> Card:
	mat.set_shader_parameter("tint", Color(c.r, c.g, c.b, amount))
	return self

func get_param(name: String) -> Variant:
	return mat.get_shader_parameter(name)

func set_param(name: String, value: Variant) -> void:
	mat.set_shader_parameter(name, value)

# ── highlight (yellow border + thicker) ─────────────────────────────────────
func set_highlighted(on: bool, animate := true) -> void:
	if on == highlighted and not animate:
		return
	highlighted = on
	if _tween and _tween.is_valid():
		_tween.kill()
	if animate and is_inside_tree():
		_tween = create_tween()
		_tween.tween_method(_set_hl, _hl, 1.0 if on else 0.0, 0.14)
	else:
		_set_hl(1.0 if on else 0.0)

func _set_hl(v: float) -> void:
	_hl = v
	_apply_highlight()

func _apply_highlight() -> void:
	mat.set_shader_parameter("border_color", _border_color.lerp(_hl_color, _hl))
	mat.set_shader_parameter("border", lerpf(_base_border, _hl_border, _hl))
