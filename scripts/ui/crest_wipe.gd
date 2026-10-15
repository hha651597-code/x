class_name CrestWipe
extends Control
## Full-screen school-crest wipe. Timeline (seconds, scaled by `speed`):
##   0.00-0.40  black slabs drop in (staggered columns, accent edge lines)      -> on_cover() at ~0.44
##   0.20-0.80  the emblem springs in: rings/spikes/petals draw themselves, spins, glows
##   0.80-1.10  hold (cube spins, spinner turns)
##   1.10-1.60  the camera pushes through the emblem while an iris with a glowing rim opens on the new screen
## `await CrestWipe.new().run("red"|"gold"|"sakura", on_cover)` from Transition.

signal done

const WIPE_SHADER := preload("res://shaders/crest_wipe.gdshader")
const GLOW_SHADER := preload("res://shaders/crest_glow.gdshader")
const ACCENTS := {
	"red": Color(1.0, 0.3, 0.4),
	"gold": Color(1.0, 0.82, 0.38),
	"sakura": Color(0.98, 0.52, 0.84),
}
const T_COVER := 0.40
const T_EMBLEM := 0.20
const T_OUT := 1.10
const T_END := 1.60

var kind := "red"
var speed := 1.0
var _t := 0.0
var _covered := false
var _running := false
var _on_cover: Callable
var _sfx := {}
var _wipe: ColorRect
var _wipe_mat: ShaderMaterial
var _vp: SubViewport
var _emblem: CrestEmblem
var _view: TextureRect
var _glow_mat: ShaderMaterial

func run(kind_: String, on_cover: Callable, speed_ := 1.0) -> void:
	kind = kind_ if ACCENTS.has(kind_) else "red"
	speed = maxf(0.2, speed_)
	_on_cover = on_cover
	_build()
	_running = true
	await done

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP     # swallow clicks while the wipe runs
	var accent: Color = ACCENTS[kind]
	_wipe = ColorRect.new()
	_wipe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wipe_mat = ShaderMaterial.new()
	_wipe_mat.shader = WIPE_SHADER
	_wipe_mat.set_shader_parameter("accent", accent)
	_wipe_mat.set_shader_parameter("cover", 0.0)
	_wipe.material = _wipe_mat
	add_child(_wipe)

	_vp = SubViewport.new()
	_vp.size = Vector2i(int(1280 * CrestEmblem.VP), int(720 * CrestEmblem.VP))
	_vp.transparent_bg = true
	_vp.msaa_2d = Viewport.MSAA_2X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_emblem = CrestEmblem.new()
	_emblem.kind = kind
	_emblem.modulate.a = 0.0
	_vp.add_child(_emblem)

	_view = TextureRect.new()
	_view.texture = _vp.get_texture()
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow_mat = ShaderMaterial.new()
	_glow_mat.shader = GLOW_SHADER
	match kind:
		"gold":
			_glow_mat.set_shader_parameter("glow_near", 1.0)
			_glow_mat.set_shader_parameter("glow_far", 0.8)
			_glow_mat.set_shader_parameter("r_far", 34.0)
			_glow_mat.set_shader_parameter("tint", Color(1.0, 0.92, 0.5))
		"sakura":
			_glow_mat.set_shader_parameter("glow_near", 0.6)
			_glow_mat.set_shader_parameter("glow_far", 1.0)
			_glow_mat.set_shader_parameter("r_far", 38.0)
			_glow_mat.set_shader_parameter("tint", Color(1.0, 0.6, 0.85))
		_:
			_glow_mat.set_shader_parameter("glow_near", 1.1)
			_glow_mat.set_shader_parameter("glow_far", 0.85)
			_glow_mat.set_shader_parameter("tint", Color(1.0, 0.8, 0.85))
	_view.material = _glow_mat
	add_child(_view)

func _once(key: String, sound: String, pitch := 1.0, vol := 1.0) -> void:
	if not _sfx.has(key):
		_sfx[key] = true
		Sfx.play(sound, pitch, vol)

func _process(delta: float) -> void:
	if not _running:
		return
	_t += minf(delta, 0.05) * speed
	var t := _t
	_wipe_mat.set_shader_parameter("cover", clampf(t / T_COVER, 0.0, 1.0))
	_once("whoosh", "whoosh")
	if t >= T_EMBLEM:
		_once("crest", "crest")
	if not _covered and t >= T_COVER + 0.04:
		_covered = true
		if _on_cover.is_valid():
			_on_cover.call()
	var et := maxf(0.0, t - T_EMBLEM)
	_emblem.t = et
	_emblem.enter = clampf(et / 0.55, 0.0, 1.0)
	_emblem.pop = UI.spring(et * 1.1, 6.0, 9.0)
	var out_t := clampf((t - T_OUT) / (T_END - T_OUT), 0.0, 1.0)
	if out_t > 0.0:
		_once("whoosh2", "whoosh", 1.35, 0.7)
	_emblem.zoom = 1.0 + 2.8 * pow(out_t, 2.0)
	_emblem.modulate.a = clampf(et * 7.0, 0.0, 1.0) * (1.0 - smoothstep(0.5, 0.95, out_t))
	_emblem.queue_redraw()
	_wipe_mat.set_shader_parameter("iris", 1250.0 * pow(out_t, 1.7))
	_wipe_mat.set_shader_parameter("ring_amt", sin(clampf(out_t * 1.15, 0.0, 1.0) * PI) * 0.9)
	if t >= T_END:
		_running = false
		done.emit()

func probe() -> Dictionary:
	return {"kind": kind, "t": snappedf(_t, 0.01), "covered": _covered}
