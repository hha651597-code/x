class_name AssignPanel
extends Control
## One white "Player N" panel of the controller-assign overlay. The card is the shader
## (shaders/assign_panel.gdshader); the title tag, the optional CPU plate and the ready bracket are drawn over it by a Painter.
## size = the card (367x270); the shadow bleeds MARGIN px outside.

const Menu := preload("res://scripts/ui/ba_menu.gd")
const Kit := preload("res://scripts/ui/screen_kit.gd")
const Painter := preload("res://scripts/ui/painter.gd")
const SHADER := preload("res://shaders/assign_panel.gdshader")
const SIZE := Vector2(367, 270)
const MARGIN := 34.0
const DIM := 0.85
const TAG_SIZE := 24

var mat: ShaderMaterial
var title_text := ""
var tint := Color.WHITE
var cpu_label := ""
var cpu_sub := ""
var claimed := false
var _flash := 0.0
var _t := 0.0
var _ready_age := 1.0
var _over: Control

func _init() -> void:
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	material = mat
	size = SIZE
	custom_minimum_size = SIZE
	pivot_offset = SIZE * 0.5
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat.set_shader_parameter("card_size", SIZE)
	_over = Painter.new().setup(SIZE, _draw_over)
	add_child(_over)

## side_tint is the player's colour (BaTokens.P1_LIGHT / P2_LIGHT): the title strip is cut from it.
func setup(text: String, side_tint := Color.WHITE) -> AssignPanel:
	title_text = text
	tint = side_tint
	return self

## Fill the panel with the big CPU read-out (single-human modes: the second player is the computer).
func set_cpu(label: String, sub: String) -> AssignPanel:
	cpu_label = label
	cpu_sub = sub
	return self

## Ready (claimed) panels carry BA's yellow bracket; the others sit at 0.85 once any panel is ready.
func set_ready(on: bool, others_ready: bool) -> void:
	if on and not claimed:
		_ready_age = 0.0
	claimed = on
	var d := 1.0 if (on or not others_ready) else DIM
	modulate = Color(d, d, d, 1.0)

func set_flash(v: float) -> void:
	_flash = v
	mat.set_shader_parameter("flash", v)

func tag_rect() -> Rect2:
	return Rect2(-10.0, 16.0, Menu.text_width(title_text, TAG_SIZE) + 44.0, float(TAG_SIZE) * 1.5)

func _draw() -> void:
	draw_rect(Rect2(Vector2(-MARGIN, -MARGIN), SIZE + Vector2(MARGIN, MARGIN) * 2.0), Color.WHITE)

func _process(delta: float) -> void:
	_t += delta
	_ready_age += delta
	_over.queue_redraw()

func _draw_over(c: Control) -> void:
	var tag := tag_rect()
	Kit.strip(c, tag, tint, BaTokens.SHEAR)
	Menu.label(c, title_text, Vector2(tag.position.x + 22.0, tag.get_center().y + float(TAG_SIZE) * 0.34), TAG_SIZE, BaTokens.LABEL_INK)
	if cpu_label != "":
		var plate := Rect2(SIZE.x * 0.5 - 100.0, 92.0, 200.0, 72.0)
		Menu.nine(c, "Combat__Combat_Title_Bg", plate, Menu.K, Color.WHITE, BaTokens.SHEAR)
		Menu.label(c, cpu_label, Vector2(plate.get_center().x, plate.get_center().y + 16.0), 46, BaTokens.WHITE, BaTokens.HEAD_OUTLINE, 2, 1, 800)
		Menu.label(c, cpu_sub, Vector2(SIZE.x * 0.5, 196.0), 16, BaTokens.INK, Color(0, 0, 0, 0), 0, 1, 700)
	if claimed:
		Kit.bracket(c, Rect2(Vector2.ZERO, SIZE).grow(9.0), 0.0, _t, _ready_age)
