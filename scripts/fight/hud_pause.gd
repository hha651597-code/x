extends Control
## Pause menu as BA's system popup: Common_Popup_Bg with a facet header, a yellow hairline and a mode ribbon, rows as white
## sheared plates (the selected one yellow with the notched bracket), toggles as cyan or grey capsules, all over a navy scrim
## with a 3 px blur. Keyboard and mouse (hover selects, click activates).
## The HUD owns the item list and the actions: hud.pause_items() -> [{id, label, value}], hud.pause_activate(i).

const Menu := preload("res://scripts/ui/ba_menu.gd")
const PainterScript := preload("res://scripts/ui/painter.gd")
const Training := preload("res://scripts/fight/hud_training.gd")
const BLUR := preload("res://shaders/screen_blur.gdshader")

const PANEL_W := 500.0
const HEADER_H := 66.0
const ROW_W := 400.0
const ROW_H := 42.0
const ROW_PITCH := 46.0
const ROWS_TOP := 131.0
const BELOW_ROWS := 44.0
const CAP_W := 84.0
const SCRIM_BLUR := 3.0
const SCRIM_DARKEN := 0.45
const SELECT_POP := 0.25

var hud: Control
var index := 0
var _t := 0.0
var _sel_t := 1.0
var _open_t := 0.0
var _rows: Array = []
var _mat: ShaderMaterial
var _scrim: ColorRect
var _paint: Control

func setup(h: Control) -> Control:
	hud = h
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_mat = ShaderMaterial.new()
	_mat.shader = BLUR
	_mat.set_shader_parameter("dark_color", BaTokens.NAVY)
	var back := BackBufferCopy.new()     # without it the blur reads the screen as the first shader that needed it saw it: the stage only
	back.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(back)
	_scrim = ColorRect.new()
	_scrim.size = Vector2(1280, 720)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim.material = _mat
	add_child(_scrim)
	_paint = PainterScript.new().setup(Vector2(1280, 720), _draw_panel)
	add_child(_paint)
	return self

func open() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	index = 0
	_t = 0.0
	_open_t = 0.0
	_sel_t = SELECT_POP
	_layout()

func close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func select(i: int, sound := true) -> void:
	var n := _rows.size()
	if n == 0:
		return
	i = posmod(i, n)
	if i != index:
		index = i
		_sel_t = 0.0
		if sound:
			Sfx.play("tick")

func _layout() -> void:
	_rows = hud.pause_items()
	index = clampi(index, 0, maxi(_rows.size() - 1, 0))

func _panel_rect() -> Rect2:
	var h := ROWS_TOP + ROW_PITCH * float(maxi(_rows.size() - 1, 0)) + ROW_H + BELOW_ROWS
	return Rect2(640.0 - PANEL_W * 0.5, 360.0 - h * 0.5, PANEL_W, h)

func _row_rect(i: int) -> Rect2:
	return Rect2(640.0 - ROW_W * 0.5, _panel_rect().position.y + ROWS_TOP + ROW_PITCH * float(i), ROW_W, ROW_H)

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_open_t += delta
	_sel_t += delta
	var items: Array = hud.pause_items()
	if items.size() != _rows.size():
		_layout()
	else:
		_rows = items
	var k := clampf(_open_t / 0.133, 0.0, 1.0)
	_mat.set_shader_parameter("blur", SCRIM_BLUR * k)
	_mat.set_shader_parameter("darken", SCRIM_DARKEN * k)
	_paint.position.y = -(1.0 - Motion.whip(_open_t)) * 300.0
	_paint.scale.y = lerpf(0.5, 1.0, clampf(_open_t / 0.183, 0.0, 1.0))
	_paint.modulate.a = clampf(_open_t / 0.217, 0.0, 1.0)
	_paint.queue_redraw()

func _gui_input(ev: InputEvent) -> void:
	if not visible or Game.busy:
		return
	if ev is InputEventMouseMotion:
		var p: Vector2 = (ev as InputEventMouseMotion).position
		for i in _rows.size():
			if _row_rect(i).grow(2.0).has_point(p):
				select(i)
				return
	elif ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var p2: Vector2 = (ev as InputEventMouseButton).position
		for i in _rows.size():
			if _row_rect(i).grow(2.0).has_point(p2):
				select(i, false)
				hud.pause_activate(i)
				accept_event()
				return

## UIAni_Scale_Select: 0.8, 0.962 at 0.067 s, 1.0 at 0.25 s.
static func _pop(t: float) -> float:
	if t < 0.067:
		return lerpf(0.8, 0.962, t / 0.067)
	return lerpf(0.962, 1.0, clampf((t - 0.067) / 0.183, 0.0, 1.0))

func _draw_panel(c: Control) -> void:
	if _rows.is_empty():
		return
	var p := _panel_rect()
	Menu.nine(c, "Common__Common_Popup_Bg", p)
	var head_h := float(BaArt.info("Common__Common_Top_Menu_Bg")["h"])
	Menu.nine(c, "Common__Common_Top_Menu_Bg", Rect2(p.position, Vector2(PANEL_W, HEADER_H)), HEADER_H / head_h)
	Menu.label(c, "PAUSED", Vector2(640.0, p.position.y + 47.0), 38, BaTokens.INK, Color.WHITE, 2, 1, 800)
	var wipe := clampf((_open_t - 0.133) / 0.134, 0.0, 1.0)
	var hw := 120.0 * wipe
	var hy := p.position.y + 80.0
	var lean := BaTokens.SHEAR * 4.0
	c.draw_colored_polygon(PackedVector2Array([Vector2(640.0 - hw * 0.5 + lean, hy), Vector2(640.0 + hw * 0.5 + lean, hy),
			Vector2(640.0 + hw * 0.5, hy + 4.0), Vector2(640.0 - hw * 0.5, hy + 4.0)]), BaTokens.BRACKET)
	Menu.ribbon(c, Rect2(590.0, p.position.y + 92.0, 100.0, 22.0), _mode_text())
	for i in _rows.size():
		_draw_row(c, i)
	if hud.world.training:
		Training.draw_tip(c, Vector2(p.end.x + 24.0, p.position.y + 250.0))
	Menu.label(c, hint_text(), Vector2(p.end.x - 30.0, p.end.y - 26.0), 12, Color(BaTokens.INK, 0.8), Color(0, 0, 0, 0), 0, 2, 600)

## The key hint under the rows. A row with a value (Dummy, Hitboxes, Infinite EX) also answers Left and Right.
func hint_text() -> String:
	var toggle := index < _rows.size() and str((_rows[index] as Dictionary).get("value", "")) != ""
	return "Up / Down: select    %s    Back: resume" % ("Left / Right: change" if toggle else "Confirm: ok")

func _mode_text() -> String:
	if hud.world.training:
		return "TRAINING"
	var n = hud.world.get("round_no")
	return "ROUND %d" % int(n) if n != null else "PAUSED"

func _draw_row(c: Control, i: int) -> void:
	var it: Dictionary = _rows[i]
	var r := _row_rect(i)
	var sel := i == index
	Menu.nine(c, "Combat__Common_Btn_BG", r, Menu.K, BaTokens.CONFIRM_PLATE if sel else Color.WHITE, BaTokens.SHEAR)
	var value := str(it.get("value", ""))
	var label := str(it["label"])
	var ink := BaTokens.CONFIRM_INK if sel else BaTokens.LABEL_INK
	var room := ROW_W - 60.0 - ((CAP_W + 24.0) if value != "" else 0.0)
	var size := Menu.fit(label, 22, room, 16)
	Menu.label(c, Menu.clip(label, size, room), Vector2(r.position.x + 30.0, r.position.y + 26.0), size, ink)
	if value != "":
		var off := value.to_lower() == "off"
		var cap := Rect2(r.end.x - 24.0 - CAP_W, r.position.y + 3.5, CAP_W, 35.0)
		Menu.nine(c, "Combat__Common_Btn_BG", cap, Menu.K, BaTokens.GREY_OFF if off else BaTokens.CYAN_PLATE, BaTokens.SHEAR)
		var v := value.to_upper()
		Menu.label(c, v, Vector2(cap.get_center().x, r.position.y + 23.0), Menu.fit(v, 15, CAP_W - 18.0, 10), Color.WHITE,
				BaTokens.GREY_OFF_EDGE if off else BaTokens.HEAD_OUTLINE, 2, 1, 800)
	if sel:
		var s := _pop(_sel_t)
		var br := r.grow_individual(14.0, 7.0, 14.0, 4.0)
		br = Rect2(br.get_center() - br.size * s * 0.5, br.size * s)
		Menu.bracket(c, br, Motion.pulse(_t))
