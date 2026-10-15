extends Control
## A fight-HUD gauge from BA's sprites: the Combat_Bg_Hp frame over a navy track (9-sliced, leaned), and on top a fill layer
## (shaders/hud_bar_fill.gdshader) that draws the ghost, the flat fill, quarter ticks and the thumb inside the frame.
## `size` is (bar width + |shear|) x bar height, shear being px of lean over the full height (negative leans "\").
## `mat` is the fill layer's material: params fill, trail (the ghost's reach), col_bot (the fill colour) and ticks. Any
## other param is ignored by the shader. `top` of setup() is unused but stays, so hud_top and hud_top_test keep the
## six-argument form.

const FRAME := "Combat__Combat_Bg_Hp"
const TRACK := "Combat__Common_Bg_Raius5px"
const SHADER := preload("res://shaders/hud_bar_fill.gdshader")
## The frame sprite (25x26, borders 12/12/10/14, drawn at 1x and shrunk together on a bar shorter than 24 px) has its track on rows 4
## to 16, then a white lip on rows 17 to 18 with a shadow under it. The fill starts one row into the track and stops at the lip.
const ROWS_ABOVE := 5.0
const ROWS_BELOW := 9.0     # sprite rows from the lip to the bottom edge

var mat: ShaderMaterial
var _w := 0.0
var _h := 0.0
var _k := 0.0    # lean in px of x per px of height

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	var layer := ColorRect.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.material = mat
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layer)

func setup(bar_w: float, bar_h: float, shear: float, mirror: bool, _top: Color, bot: Color) -> Control:
	_w = bar_w
	_h = bar_h
	_k = shear / bar_h
	size = Vector2(bar_w + absf(shear), bar_h)
	var inset_x := 6.0 if bar_h > 20.0 else 4.0
	var ky := minf(1.0, bar_h / 24.0)
	var top := ROWS_ABOVE * ky
	mat.set_shader_parameter("inner", Vector4(absf(shear) * 0.5 + inset_x, top, bar_w - inset_x * 2.0, bar_h - top - ROWS_BELOW * ky))
	mat.set_shader_parameter("shear", _k)
	mat.set_shader_parameter("mirror", mirror)
	mat.set_shader_parameter("col_bot", bot)
	queue_redraw()
	return self

## Restrict the fill to the frame's x range [from_x, to_x] (0 is the frame's left edge), so a card or plate laid over the
## bar's ends does not eat part of the gauge: at full it spans exactly this range.
func fill_span(from_x: float, to_x: float) -> void:
	var inner: Vector4 = mat.get_shader_parameter("inner")
	mat.set_shader_parameter("inner", Vector4(absf(_k) * _h * 0.5 + from_x, inner.y, to_x - from_x, inner.w))

func param(name: String, value: Variant) -> void:
	mat.set_shader_parameter(name, value)

func _draw() -> void:
	var r := Rect2(absf(_k) * _h * 0.5, 0.0, _w, _h)
	BaArt.nine(self, TRACK, r.grow_individual(-2.0, -1.0, -2.0, -1.0), BaTokens.NAVY, _k)
	BaArt.nine(self, FRAME, r, Color.WHITE, _k)
